alter table public.messages
  add column if not exists audio_data_url text,
  add column if not exists audio_duration_ms integer;

alter table public.messages
  drop constraint if exists messages_type_check;

alter table public.messages
  add constraint messages_type_check
  check (type in ('system', 'text', 'image', 'audio'));

drop function if exists public.app_send_message(text, text, text, text, text, text, text);

create or replace function public.app_send_message(
  p_family_id text,
  p_room_id text,
  p_sender_id text,
  p_message_type text,
  p_text text,
  p_image_data_url text,
  p_audio_data_url text default '',
  p_audio_duration_ms integer default null,
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
  v_text text := coalesce(p_text, '');
  v_image_data_url text := nullif(trim(coalesce(p_image_data_url, '')), '');
  v_audio_data_url text := nullif(trim(coalesce(p_audio_data_url, '')), '');
  v_audio_duration_ms integer := case
    when p_audio_duration_ms is null or p_audio_duration_ms <= 0 then null
    else p_audio_duration_ms
  end;
begin
  if p_message_type not in ('text', 'image', 'audio') then
    raise exception 'invalid message type';
  end if;

  if p_message_type = 'audio' then
    if v_audio_data_url is null then
      raise exception 'audio payload is required';
    end if;
  elsif coalesce(trim(v_text), '') = '' and v_image_data_url is null then
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
    image_data_url,
    audio_data_url,
    audio_duration_ms
  )
  values (
    v_message_id,
    p_family_id,
    p_room_id,
    p_sender_id,
    p_message_type,
    v_text,
    v_image_data_url,
    v_audio_data_url,
    v_audio_duration_ms
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
        'audioDataUrl', msg.audio_data_url,
        'audioDurationMs', msg.audio_duration_ms,
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

create or replace function public.app_get_push_delivery_batch(p_message_id text)
returns jsonb
language sql
stable
set search_path = public
as $$
  with target_message as (
    select
      msg.id,
      msg.family_id,
      msg.room_id,
      msg.sender_id,
      msg.type,
      msg.text,
      room.type as room_type,
      room.title as room_title,
      family.name as family_name,
      sender.name as sender_name
    from public.messages msg
    join public.rooms room
      on room.id = msg.room_id
    join public.families family
      on family.id = msg.family_id
    left join public.members sender
      on sender.id = msg.sender_id
    where msg.id = p_message_id
      and msg.type in ('text', 'image', 'audio')
      and msg.sender_id is not null
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'endpoint', subscription.endpoint,
        'title', case
          when message.room_type = 'family' then coalesce(nullif(message.room_title, ''), message.family_name, 'Family')
          when message.room_type = 'dm' then coalesce(message.sender_name, 'Direct message')
          else coalesce(nullif(message.room_title, ''), 'Group room')
        end,
        'body', case
          when message.type = 'audio' then 'Sent a voice message.'
          when message.type = 'image' and coalesce(trim(message.text), '') <> '' then 'Photo: ' || left(trim(message.text), 120)
          when message.type = 'image' then 'Sent a photo.'
          else left(coalesce(nullif(trim(message.text), ''), 'New message received.'), 120)
        end,
        'tag', message.family_id || ':' || message.room_id,
        'data', jsonb_build_object(
          'familyId', message.family_id,
          'roomId', message.room_id,
          'messageId', message.id
        ),
        'subscription', jsonb_build_object(
          'endpoint', subscription.endpoint,
          'keys', jsonb_build_object(
            'p256dh', subscription.p256dh,
            'auth', subscription.auth
          )
        )
      )
    ),
    '[]'::jsonb
  )
  from target_message message
  join public.room_members room_member
    on room_member.room_id = message.room_id
   and room_member.member_id <> message.sender_id
   and room_member.muted = false
  join public.push_subscriptions subscription
    on subscription.member_id = room_member.member_id
   and subscription.family_id = message.family_id;
$$;

create or replace function public.app_dispatch_push_webhook()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.type not in ('text', 'image', 'audio') or new.sender_id is null then
    return new;
  end if;

  perform net.http_post(
    url := 'https://csarhidurfxdmcworbtk.supabase.co/functions/v1/push-notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNzYXJoaWR1cmZ4ZG1jd29yYnRrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4MTIwNTgsImV4cCI6MjA4OTM4ODA1OH0.AW7mIgO0M_qk3xjrLkATrHO__HWFozcTyxjEIf-rjr8',
      'apikey', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNzYXJoaWR1cmZ4ZG1jd29yYnRrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4MTIwNTgsImV4cCI6MjA4OTM4ODA1OH0.AW7mIgO0M_qk3xjrLkATrHO__HWFozcTyxjEIf-rjr8'
    ),
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'messages',
      'schema', 'public',
      'record', row_to_json(new),
      'old_record', null
    )
  );

  return new;
end;
$$;

grant execute on function public.app_send_message(text, text, text, text, text, text, text, integer, text) to anon, authenticated;
grant execute on function public.app_get_family_snapshot(text) to anon, authenticated;
grant execute on function public.app_get_push_delivery_batch(text) to anon, authenticated;
