create or replace function public.app_remove_member(
  p_family_id text,
  p_admin_member_id text,
  p_target_member_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin public.members%rowtype;
  v_target public.members%rowtype;
  v_family_room_id text;
  v_message_id text := public.app_generate_id('message');
begin
  select *
  into v_admin
  from public.members
  where id = p_admin_member_id
    and family_id = p_family_id
  limit 1;

  if not found or v_admin.role <> 'admin' then
    raise exception 'only admins can remove members';
  end if;

  select *
  into v_target
  from public.members
  where id = p_target_member_id
    and family_id = p_family_id
  limit 1;

  if not found then
    raise exception 'member not found';
  end if;

  if v_target.id = v_admin.id then
    raise exception 'admin cannot remove themselves';
  end if;

  if v_target.role = 'admin' then
    raise exception 'admin member cannot be removed';
  end if;

  select id
  into v_family_room_id
  from public.rooms
  where family_id = p_family_id
    and type = 'family'
  order by created_at asc
  limit 1;

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
      p_family_id,
      v_family_room_id,
      null,
      'system',
      v_target.name || '님이 방장에 의해 가족에서 탈퇴되었습니다.'
    );
  end if;

  delete from public.rooms r
  where r.family_id = p_family_id
    and r.type = 'dm'
    and exists (
      select 1
      from public.room_members rm
      where rm.room_id = r.id
        and rm.member_id = p_target_member_id
    );

  delete from public.members
  where id = p_target_member_id
    and family_id = p_family_id;

  return jsonb_build_object(
    'removedMemberId', v_target.id
  );
end;
$$;

grant execute on function public.app_remove_member(text, text, text) to anon, authenticated;
