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

  insert into public.rooms (id, family_id, type, title)
  values (v_room_id, v_family_id, 'family', trim(p_family_name) || ' 가족방');

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
