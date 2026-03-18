create or replace function public.app_issue_invite(p_family_id text, p_created_by text)
returns public.invites
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.invites%rowtype;
begin
  delete from public.invites
  where family_id = p_family_id
    and status = 'active';

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
  v_invite public.invites%rowtype;
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

  insert into public.rooms (id, family_id, type, title, created_by)
  values (v_room_id, v_family_id, 'family', trim(p_family_name) || ' 가족방', v_admin_id);

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
    trim(p_family_name) || ' 가족채팅방이 만들어졌습니다.'
  );

  v_invite := public.app_issue_invite(v_family_id, v_admin_id);

  return jsonb_build_object(
    'familyId', v_family_id,
    'memberId', v_admin_id,
    'activeRoomId', v_room_id,
    'familyName', trim(p_family_name),
    'memberName', trim(p_admin_name),
    'role', 'admin',
    'inviteCodes', jsonb_build_array(v_invite.code)
  );
end;
$$;

with ranked_active_invites as (
  select
    id,
    row_number() over (
      partition by family_id
      order by created_at desc, id desc
    ) as row_number
  from public.invites
  where status = 'active'
)
delete from public.invites invites
using ranked_active_invites ranked
where invites.id = ranked.id
  and ranked.row_number > 1;
