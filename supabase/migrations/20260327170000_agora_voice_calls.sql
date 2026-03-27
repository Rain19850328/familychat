alter table public.rooms
  add column if not exists voice_call_active boolean not null default false,
  add column if not exists voice_channel_name text,
  add column if not exists voice_call_started_at timestamptz,
  add column if not exists voice_call_started_by text references public.members(id) on delete set null,
  add column if not exists voice_call_updated_at timestamptz not null default timezone('utc', now());

create index if not exists rooms_family_id_voice_call_active_idx
  on public.rooms (family_id, voice_call_active);

create or replace function public.app_start_room_voice_call(
  p_room_id text,
  p_member_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room public.rooms%rowtype;
  v_channel_name text;
begin
  select r.*
  into v_room
  from public.rooms r
  join public.room_members rm
    on rm.room_id = r.id
   and rm.member_id = p_member_id
  where r.id = p_room_id
  limit 1;

  if v_room.id is null then
    raise exception 'member is not allowed in this room';
  end if;

  v_channel_name := coalesce(
    nullif(v_room.voice_channel_name, ''),
    'voice-' || v_room.family_id || '-' || v_room.id
  );

  update public.rooms
  set
    voice_call_active = true,
    voice_channel_name = v_channel_name,
    voice_call_started_at = coalesce(v_room.voice_call_started_at, timezone('utc', now())),
    voice_call_started_by = coalesce(v_room.voice_call_started_by, p_member_id),
    voice_call_updated_at = timezone('utc', now())
  where id = v_room.id;

  return jsonb_build_object(
    'roomId', v_room.id,
    'familyId', v_room.family_id,
    'channelName', v_channel_name,
    'isActive', true,
    'startedBy', coalesce(v_room.voice_call_started_by, p_member_id),
    'startedAt', coalesce(v_room.voice_call_started_at, timezone('utc', now()))
  );
end;
$$;

create or replace function public.app_end_room_voice_call(
  p_room_id text,
  p_member_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.room_members rm
    where rm.room_id = p_room_id
      and rm.member_id = p_member_id
  ) then
    raise exception 'member is not allowed in this room';
  end if;

  update public.rooms
  set
    voice_call_active = false,
    voice_call_updated_at = timezone('utc', now())
  where id = p_room_id;
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
        ), '{}'::jsonb),
        'voiceCallActive', r.voice_call_active,
        'voiceChannelName', r.voice_channel_name,
        'voiceCallStartedAt', r.voice_call_started_at,
        'voiceCallStartedBy', r.voice_call_started_by
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

grant execute on function public.app_start_room_voice_call(text, text) to anon, authenticated;
grant execute on function public.app_end_room_voice_call(text, text) to anon, authenticated;
grant execute on function public.app_get_family_snapshot(text) to anon, authenticated;
