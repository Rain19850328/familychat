create extension if not exists pgcrypto with schema extensions;

create table if not exists public.families (
  id text primary key,
  name text not null,
  allow_group_rooms boolean not null default false,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.members (
  id text primary key,
  family_id text not null references public.families(id) on delete cascade,
  name text not null,
  role text not null check (role in ('admin', 'member')),
  created_at timestamptz not null default timezone('utc', now()),
  last_seen_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.rooms (
  id text primary key,
  family_id text not null references public.families(id) on delete cascade,
  type text not null check (type in ('family', 'dm', 'group')),
  title text not null default '',
  dm_key text,
  created_at timestamptz not null default timezone('utc', now()),
  unique (family_id, dm_key)
);

create table if not exists public.room_members (
  family_id text not null references public.families(id) on delete cascade,
  room_id text not null references public.rooms(id) on delete cascade,
  member_id text not null references public.members(id) on delete cascade,
  muted boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (room_id, member_id)
);

create table if not exists public.invites (
  id text primary key,
  family_id text not null references public.families(id) on delete cascade,
  code text not null unique,
  created_by text not null references public.members(id) on delete cascade,
  status text not null check (status in ('active', 'used', 'revoked')),
  used_by text references public.members(id) on delete set null,
  used_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.messages (
  id text primary key,
  family_id text not null references public.families(id) on delete cascade,
  room_id text not null references public.rooms(id) on delete cascade,
  sender_id text references public.members(id) on delete set null,
  type text not null check (type in ('system', 'text', 'image')),
  text text not null default '',
  image_data_url text,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.message_reads (
  family_id text not null references public.families(id) on delete cascade,
  message_id text not null references public.messages(id) on delete cascade,
  member_id text not null references public.members(id) on delete cascade,
  read_at timestamptz not null default timezone('utc', now()),
  primary key (message_id, member_id)
);

create index if not exists members_family_id_idx on public.members (family_id);
create index if not exists rooms_family_id_idx on public.rooms (family_id);
create index if not exists room_members_family_id_idx on public.room_members (family_id);
create index if not exists invites_family_id_idx on public.invites (family_id);
create index if not exists messages_family_id_idx on public.messages (family_id);
create index if not exists messages_room_id_created_at_idx on public.messages (room_id, created_at);
create index if not exists message_reads_family_id_idx on public.message_reads (family_id);

create or replace function public.app_generate_id(p_prefix text)
returns text
language sql
volatile
as $$
  select p_prefix || '-' || encode(extensions.gen_random_bytes(8), 'hex');
$$;

create or replace function public.app_dm_key(p_first_member_id text, p_second_member_id text)
returns text
language sql
immutable
as $$
  select case
    when p_first_member_id <= p_second_member_id then p_first_member_id || ':' || p_second_member_id
    else p_second_member_id || ':' || p_first_member_id
  end;
$$;

create or replace function public.app_generate_invite_code()
returns text
language plpgsql
volatile
as $$
declare
  v_code text;
begin
  loop
    v_code := 'FAM-' || upper(substr(encode(extensions.gen_random_bytes(4), 'hex'), 1, 6));
    exit when not exists (
      select 1
      from public.invites
      where code = v_code
    );
  end loop;

  return v_code;
end;
$$;

create or replace function public.app_issue_invite(p_family_id text, p_created_by text)
returns public.invites
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.invites%rowtype;
begin
  insert into public.invites (
    id,
    family_id,
    code,
    created_by,
    status
  )
  values (
    public.app_generate_id('invite'),
    p_family_id,
    public.app_generate_invite_code(),
    p_created_by,
    'active'
  )
  returning * into v_invite;

  return v_invite;
end;
$$;

create or replace function public.app_get_or_create_dm_room(
  p_family_id text,
  p_first_member_id text,
  p_second_member_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dm_key text;
  v_room_id text;
begin
  if p_first_member_id = p_second_member_id then
    raise exception 'direct room requires two distinct members';
  end if;

  if not exists (
    select 1
    from public.members
    where id = p_first_member_id
      and family_id = p_family_id
  ) then
    raise exception 'first member is not in family';
  end if;

  if not exists (
    select 1
    from public.members
    where id = p_second_member_id
      and family_id = p_family_id
  ) then
    raise exception 'second member is not in family';
  end if;

  v_dm_key := public.app_dm_key(p_first_member_id, p_second_member_id);
  v_room_id := public.app_generate_id('room');

  insert into public.rooms (
    id,
    family_id,
    type,
    title,
    dm_key
  )
  values (
    v_room_id,
    p_family_id,
    'dm',
    '',
    v_dm_key
  )
  on conflict (family_id, dm_key) do nothing;

  select id
  into v_room_id
  from public.rooms
  where family_id = p_family_id
    and dm_key = v_dm_key;

  insert into public.room_members (family_id, room_id, member_id)
  values
    (p_family_id, v_room_id, p_first_member_id),
    (p_family_id, v_room_id, p_second_member_id)
  on conflict (room_id, member_id) do nothing;

  return jsonb_build_object('id', v_room_id);
end;
$$;

create or replace function public.app_create_family(
  p_family_name text,
  p_admin_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_family_id text := public.app_generate_id('family');
  v_admin_id text := public.app_generate_id('member');
  v_room_id text := public.app_generate_id('room');
  v_message_id text := public.app_generate_id('message');
  v_invite_a public.invites%rowtype;
  v_invite_b public.invites%rowtype;
begin
  if coalesce(trim(p_family_name), '') = '' then
    raise exception 'family name is required';
  end if;

  if coalesce(trim(p_admin_name), '') = '' then
    raise exception 'admin name is required';
  end if;

  insert into public.families (id, name)
  values (v_family_id, trim(p_family_name));

  insert into public.members (id, family_id, name, role)
  values (v_admin_id, v_family_id, trim(p_admin_name), 'admin');

  insert into public.rooms (id, family_id, type, title)
  values (v_room_id, v_family_id, 'family', '가족 전체방');

  insert into public.room_members (family_id, room_id, member_id)
  values (v_family_id, v_room_id, v_admin_id);

  insert into public.messages (
    id,
    family_id,
    room_id,
    sender_id,
    type,
    text
  )
  values (
    v_message_id,
    v_family_id,
    v_room_id,
    null,
    'system',
    trim(p_family_name) || ' 가족 채팅방이 만들어졌습니다.'
  );

  v_invite_a := public.app_issue_invite(v_family_id, v_admin_id);
  v_invite_b := public.app_issue_invite(v_family_id, v_admin_id);

  return jsonb_build_object(
    'familyId', v_family_id,
    'memberId', v_admin_id,
    'activeRoomId', v_room_id,
    'familyName', trim(p_family_name),
    'memberName', trim(p_admin_name),
    'role', 'admin',
    'inviteCodes', jsonb_build_array(v_invite_a.code, v_invite_b.code)
  );
end;
$$;

create or replace function public.app_join_family(
  p_invite_code text,
  p_member_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.invites%rowtype;
  v_family public.families%rowtype;
  v_member_id text := public.app_generate_id('member');
  v_family_room_id text;
  v_message_id text := public.app_generate_id('message');
  v_existing_member record;
begin
  if coalesce(trim(p_member_name), '') = '' then
    raise exception 'member name is required';
  end if;

  select *
  into v_invite
  from public.invites
  where code = upper(trim(p_invite_code))
  limit 1;

  if not found then
    raise exception 'invite not found';
  end if;

  if v_invite.status <> 'active' then
    raise exception 'invite is no longer active';
  end if;

  select *
  into v_family
  from public.families
  where id = v_invite.family_id;

  insert into public.members (id, family_id, name, role)
  values (v_member_id, v_family.id, trim(p_member_name), 'member');

  select id
  into v_family_room_id
  from public.rooms
  where family_id = v_family.id
    and type = 'family'
  order by created_at asc
  limit 1;

  if v_family_room_id is not null then
    insert into public.room_members (family_id, room_id, member_id)
    values (v_family.id, v_family_room_id, v_member_id)
    on conflict (room_id, member_id) do nothing;
  end if;

  update public.invites
  set
    status = 'used',
    used_by = v_member_id,
    used_at = timezone('utc', now())
  where id = v_invite.id;

  for v_existing_member in
    select id
    from public.members
    where family_id = v_family.id
      and id <> v_member_id
  loop
    perform public.app_get_or_create_dm_room(v_family.id, v_member_id, v_existing_member.id);
  end loop;

  if v_family_room_id is not null then
    insert into public.messages (
      id,
      family_id,
      room_id,
      sender_id,
      type,
      text
    )
    values (
      v_message_id,
      v_family.id,
      v_family_room_id,
      null,
      'system',
      trim(p_member_name) || '님이 가족 그룹에 참여했습니다.'
    );
  end if;

  return jsonb_build_object(
    'familyId', v_family.id,
    'memberId', v_member_id,
    'activeRoomId', v_family_room_id,
    'familyName', v_family.name,
    'memberName', trim(p_member_name),
    'role', 'member'
  );
end;
$$;

create or replace function public.app_create_invite(
  p_family_id text,
  p_admin_member_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.members%rowtype;
  v_invite public.invites%rowtype;
begin
  select *
  into v_admin
  from public.members
  where id = p_admin_member_id
    and family_id = p_family_id
  limit 1;

  if not found or v_admin.role <> 'admin' then
    raise exception 'only admins can create invites';
  end if;

  v_invite := public.app_issue_invite(p_family_id, p_admin_member_id);

  return jsonb_build_object(
    'id', v_invite.id,
    'code', v_invite.code,
    'status', v_invite.status,
    'createdAt', v_invite.created_at
  );
end;
$$;

create or replace function public.app_send_message(
  p_family_id text,
  p_room_id text,
  p_sender_id text,
  p_message_type text,
  p_text text,
  p_image_data_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message_id text := public.app_generate_id('message');
begin
  if p_message_type not in ('text', 'image') then
    raise exception 'invalid message type';
  end if;

  if coalesce(trim(p_text), '') = '' and coalesce(trim(p_image_data_url), '') = '' then
    raise exception 'message text or image is required';
  end if;

  if not exists (
    select 1
    from public.room_members rm
    where rm.family_id = p_family_id
      and rm.room_id = p_room_id
      and rm.member_id = p_sender_id
  ) then
    raise exception 'member is not allowed in this room';
  end if;

  insert into public.messages (
    id,
    family_id,
    room_id,
    sender_id,
    type,
    text,
    image_data_url
  )
  values (
    v_message_id,
    p_family_id,
    p_room_id,
    p_sender_id,
    p_message_type,
    coalesce(p_text, ''),
    nullif(p_image_data_url, '')
  );

  insert into public.message_reads (family_id, message_id, member_id)
  values (p_family_id, v_message_id, p_sender_id)
  on conflict (message_id, member_id) do nothing;

  update public.members
  set last_seen_at = timezone('utc', now())
  where id = p_sender_id
    and family_id = p_family_id;

  return jsonb_build_object('id', v_message_id);
end;
$$;

create or replace function public.app_mark_room_read(
  p_room_id text,
  p_member_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_family_id text;
begin
  select family_id
  into v_family_id
  from public.room_members
  where room_id = p_room_id
    and member_id = p_member_id
  limit 1;

  if v_family_id is null then
    raise exception 'member is not in room';
  end if;

  insert into public.message_reads (family_id, message_id, member_id)
  select
    v_family_id,
    msg.id,
    p_member_id
  from public.messages msg
  where msg.room_id = p_room_id
  on conflict (message_id, member_id) do nothing;
end;
$$;

create or replace function public.app_set_room_mute(
  p_room_id text,
  p_member_id text,
  p_muted boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.room_members
  set muted = p_muted
  where room_id = p_room_id
    and member_id = p_member_id;

  if not found then
    raise exception 'member is not in room';
  end if;
end;
$$;

create or replace function public.app_touch_member(p_member_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.members
  set last_seen_at = timezone('utc', now())
  where id = p_member_id;
end;
$$;

create or replace function public.app_get_family_snapshot(p_family_id text)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'id', f.id,
    'name', f.name,
    'createdAt', f.created_at,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id,
        'familyId', m.family_id,
        'name', m.name,
        'role', m.role,
        'createdAt', m.created_at,
        'lastSeenAt', m.last_seen_at
      ) order by m.created_at asc)
      from public.members m
      where m.family_id = f.id
    ), '[]'::jsonb),
    'rooms', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'familyId', r.family_id,
        'type', r.type,
        'title', r.title,
        'createdAt', r.created_at,
        'memberIds', coalesce((
          select jsonb_agg(rm.member_id order by rm.created_at asc)
          from public.room_members rm
          where rm.room_id = r.id
        ), '[]'::jsonb),
        'mutedBy', coalesce((
          select jsonb_object_agg(rm.member_id, rm.muted)
          from public.room_members rm
          where rm.room_id = r.id
        ), '{}'::jsonb)
      ) order by r.created_at asc)
      from public.rooms r
      where r.family_id = f.id
    ), '[]'::jsonb),
    'invites', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id,
        'familyId', i.family_id,
        'code', i.code,
        'createdBy', i.created_by,
        'status', i.status,
        'usedBy', i.used_by,
        'usedAt', i.used_at,
        'createdAt', i.created_at
      ) order by i.created_at desc)
      from public.invites i
      where i.family_id = f.id
    ), '[]'::jsonb),
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', msg.id,
        'roomId', msg.room_id,
        'familyId', msg.family_id,
        'senderId', msg.sender_id,
        'type', msg.type,
        'text', msg.text,
        'imageDataUrl', msg.image_data_url,
        'createdAt', msg.created_at,
        'readBy', coalesce((
          select jsonb_object_agg(mr.member_id, mr.read_at)
          from public.message_reads mr
          where mr.message_id = msg.id
        ), '{}'::jsonb)
      ) order by msg.created_at asc)
      from public.messages msg
      where msg.family_id = f.id
    ), '[]'::jsonb),
    'settings', jsonb_build_object(
      'allowGroupRooms', f.allow_group_rooms
    )
  )
  from public.families f
  where f.id = p_family_id;
$$;

grant usage on schema public to anon, authenticated;
grant select on public.families to anon, authenticated;
grant select on public.members to anon, authenticated;
grant select on public.rooms to anon, authenticated;
grant select on public.room_members to anon, authenticated;
grant select on public.invites to anon, authenticated;
grant select on public.messages to anon, authenticated;
grant select on public.message_reads to anon, authenticated;
grant execute on function public.app_get_or_create_dm_room(text, text, text) to anon, authenticated;
grant execute on function public.app_create_family(text, text) to anon, authenticated;
grant execute on function public.app_join_family(text, text) to anon, authenticated;
grant execute on function public.app_create_invite(text, text) to anon, authenticated;
grant execute on function public.app_send_message(text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.app_mark_room_read(text, text) to anon, authenticated;
grant execute on function public.app_set_room_mute(text, text, boolean) to anon, authenticated;
grant execute on function public.app_touch_member(text) to anon, authenticated;
grant execute on function public.app_get_family_snapshot(text) to anon, authenticated;
