create index if not exists messages_family_id_created_at_idx
on public.messages (family_id, created_at);
