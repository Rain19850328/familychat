create or replace function public.app_send_message(
  p_family_id text,
  p_room_id text,
  p_sender_id text,
  p_message_type text,
  p_text text,
  p_image_data_url text,
  p_client_message_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message_id text := coalesce(
    nullif(trim(p_client_message_id), ''),
    public.app_generate_id('message')
  );
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

  if exists (
    select 1
    from public.messages msg
    where msg.id = v_message_id
      and msg.family_id = p_family_id
  ) then
    return jsonb_build_object('id', v_message_id);
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
  )
  on conflict (id) do nothing;

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
    and not exists (
      select 1
      from public.message_reads mr
      where mr.message_id = msg.id
        and mr.member_id = p_member_id
    )
  on conflict (message_id, member_id) do nothing;
end;
$$;
