alter table public.push_vapid_config
  alter column public_key type jsonb using public_key::jsonb,
  alter column private_key type jsonb using private_key::jsonb;
