-- Server-only ingest credentials for production application events. The raw
-- secret is shown once by the native app; only its SHA-256 hash is retained.

create table public.application_ingest_keys (
  project_id uuid primary key
    references public.projects(id) on delete cascade,
  connection_id uuid not null unique
    references public.provider_connections(id) on delete cascade,
  secret_hash text not null unique
    check (secret_hash ~ '^[a-f0-9]{64}$'),
  last_used_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.application_ingest_keys is
  'Server-only hashes of production Application Logs bearer tokens.';

alter table public.application_ingest_keys enable row level security;

revoke all on table public.application_ingest_keys
  from public, anon, authenticated, service_role;

grant select, insert, update, delete
  on table public.application_ingest_keys to service_role;

-- New Supabase projects no longer expose new tables automatically. Keep the
-- collector privileges explicit for both the key lookup and event insertion.
grant select, insert, update
  on table public.provider_connections to service_role;
grant select, insert
  on table public.raw_events to service_role;

create trigger application_ingest_keys_set_updated_at
before update on public.application_ingest_keys
for each row execute function private.set_updated_at();
