create extension if not exists pg_net with schema extensions;

create table if not exists public.push_subscriptions (
  id text primary key default public.app_generate_id('pushsub'),
  family_id text not null references public.families(id) on delete cascade,
  member_id text not null references public.members(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  last_seen_at timestamptz not null default timezone('utc', now())
);

create index if not exists push_subscriptions_family_id_idx on public.push_subscriptions (family_id);
create index if not exists push_subscriptions_member_id_idx on public.push_subscriptions (member_id);

create table if not exists public.push_dispatch_log (
  message_id text primary key references public.messages(id) on delete cascade,
  dispatched_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.push_vapid_config (
  id boolean primary key default true check (id),
  public_key text not null,
  private_key text not null,
  subject text not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create or replace function public.app_upsert_push_subscription(
  p_member_id text,
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.members%rowtype;
  v_subscription public.push_subscriptions%rowtype;
begin
  if coalesce(trim(p_endpoint), '') = '' then
    raise exception 'push endpoint is required';
  end if;

  if coalesce(trim(p_p256dh), '') = '' or coalesce(trim(p_auth), '') = '' then
    raise exception 'push subscription keys are required';
  end if;

  select *
  into v_member
  from public.members
  where id = p_member_id
  limit 1;

  if not found then
    raise exception 'member does not exist';
  end if;

  insert into public.push_subscriptions (
    family_id,
    member_id,
    endpoint,
    p256dh,
    auth,
    user_agent,
    updated_at,
    last_seen_at
  )
  values (
    v_member.family_id,
    v_member.id,
    trim(p_endpoint),
    trim(p_p256dh),
    trim(p_auth),
    nullif(trim(coalesce(p_user_agent, '')), ''),
    timezone('utc', now()),
    timezone('utc', now())
  )
  on conflict (endpoint) do update
  set
    family_id = excluded.family_id,
    member_id = excluded.member_id,
    p256dh = excluded.p256dh,
    auth = excluded.auth,
    user_agent = excluded.user_agent,
    updated_at = timezone('utc', now()),
    last_seen_at = timezone('utc', now())
  returning * into v_subscription;

  return jsonb_build_object(
    'id', v_subscription.id,
    'endpoint', v_subscription.endpoint
  );
end;
$$;

create or replace function public.app_remove_push_subscription(
  p_member_id text,
  p_endpoint text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.push_subscriptions
  where member_id = p_member_id
    and (
      p_endpoint is null
      or endpoint = p_endpoint
    );
end;
$$;

create or replace function public.app_claim_push_dispatch(p_message_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows integer := 0;
begin
  insert into public.push_dispatch_log (message_id)
  values (p_message_id)
  on conflict (message_id) do nothing;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
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
      and msg.type in ('text', 'image')
      and msg.sender_id is not null
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'endpoint', subscription.endpoint,
        'title', case
          when message.room_type = 'family' then coalesce(nullif(message.room_title, ''), message.family_name, '가족 전체방')
          when message.room_type = 'dm' then coalesce(message.sender_name, '가족 1:1')
          else coalesce(nullif(message.room_title, ''), '가족 그룹방')
        end,
        'body', case
          when message.type = 'image' and coalesce(trim(message.text), '') <> '' then '사진 · ' || left(trim(message.text), 120)
          when message.type = 'image' then '사진이 도착했습니다.'
          else left(coalesce(nullif(trim(message.text), ''), '새 메시지가 도착했습니다.'), 120)
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
  if new.type not in ('text', 'image') or new.sender_id is null then
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

drop trigger if exists messages_push_webhook on public.messages;

create trigger messages_push_webhook
after insert on public.messages
for each row
execute function public.app_dispatch_push_webhook();

grant execute on function public.app_upsert_push_subscription(text, text, text, text, text) to anon, authenticated;
grant execute on function public.app_remove_push_subscription(text, text) to anon, authenticated;
grant execute on function public.app_claim_push_dispatch(text) to anon, authenticated;
grant execute on function public.app_get_push_delivery_batch(text) to anon, authenticated;
