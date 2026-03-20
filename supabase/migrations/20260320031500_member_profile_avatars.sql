alter table public.members
  add column if not exists avatar_key text,
  add column if not exists avatar_image_data_url text;

create or replace function public.app_update_member_profile(
  p_member_id text,
  p_name text,
  p_avatar_key text default null,
  p_avatar_image_data_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.members%rowtype;
  v_name text := trim(coalesce(p_name, ''));
  v_avatar_key text := nullif(trim(coalesce(p_avatar_key, '')), '');
  v_avatar_image_data_url text := nullif(trim(coalesce(p_avatar_image_data_url, '')), '');
begin
  if v_name = '' then
    raise exception 'member name is required';
  end if;

  if not exists (
    select 1
    from public.members
    where id = p_member_id
  ) then
    raise exception 'member does not exist';
  end if;

  update public.members
  set
    name = v_name,
    avatar_key = case
      when v_avatar_image_data_url is not null then null
      else v_avatar_key
    end,
    avatar_image_data_url = v_avatar_image_data_url
  where id = p_member_id
  returning * into v_member;

  return jsonb_build_object(
    'id', v_member.id,
    'familyId', v_member.family_id,
    'name', v_member.name,
    'role', v_member.role,
    'avatarKey', v_member.avatar_key,
    'avatarImageDataUrl', v_member.avatar_image_data_url,
    'lastSeenAt', v_member.last_seen_at
  );
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
        'avatarKey', m.avatar_key,
        'avatarImageDataUrl', m.avatar_image_data_url,
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

grant execute on function public.app_update_member_profile(text, text, text, text) to anon, authenticated;
grant execute on function public.app_get_family_snapshot(text) to anon, authenticated;
