-- Server-owned OAuth state and credentials for provider connections.
-- These tables are in public because the hosted Data API exposes that schema,
-- but no browser or native client role receives table privileges or RLS policies.

create table public.provider_oauth_states (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null
    references public.projects(id) on delete cascade,
  provider public.provider_kind not null,
  state_hash text not null unique,
  code_verifier_ciphertext text not null,
  external_project_ref text,
  redirect_uri text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.provider_credentials (
  connection_id uuid primary key
    references public.provider_connections(id) on delete cascade,
  access_token_ciphertext text not null,
  refresh_token_ciphertext text,
  token_type text not null default 'Bearer',
  granted_scope text,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.provider_credentials is
  'Server-only encrypted provider credentials. Never grant access to client roles.';

create index provider_oauth_states_expiry_idx
  on public.provider_oauth_states(expires_at)
  where consumed_at is null;

create index provider_oauth_states_project_id_idx
  on public.provider_oauth_states(project_id);

-- Cover existing foreign keys that the production database advisor identified.
create index if not exists workspaces_created_by_idx
  on public.workspaces(created_by);

create index if not exists invitations_invited_by_idx
  on public.invitations(invited_by);

create index if not exists case_shares_created_by_idx
  on public.case_shares(created_by);

alter table public.provider_oauth_states enable row level security;
alter table public.provider_credentials enable row level security;

revoke all on table public.provider_oauth_states from public, anon, authenticated;
revoke all on table public.provider_credentials from public, anon, authenticated;
grant select, insert, update, delete
  on table public.provider_oauth_states to service_role;
grant select, insert, update, delete
  on table public.provider_credentials to service_role;

create trigger provider_credentials_set_updated_at
before update on public.provider_credentials
for each row execute function private.set_updated_at();

-- The platform may install this helper while creating tables in the dashboard.
-- It should never be callable by client roles because it changes table security.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'revoke all on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
end;
$$;

-- ensure_workspace superseded this non-idempotent first version before launch.
drop function if exists public.create_workspace(text);

-- Keep SECURITY DEFINER implementations out of the exposed API schema. The
-- public wrappers are SECURITY INVOKER and expose only the checked operations.
alter function public.ensure_workspace(text) set schema private;
alter function private.ensure_workspace(text) rename to ensure_workspace_impl;

revoke all on function private.ensure_workspace_impl(text) from public, anon;
grant execute on function private.ensure_workspace_impl(text) to authenticated;

create function public.ensure_workspace(workspace_name text)
returns public.workspaces
language sql
security invoker
set search_path = ''
as $$
  select * from private.ensure_workspace_impl(workspace_name);
$$;

revoke all on function public.ensure_workspace(text) from public, anon;
grant execute on function public.ensure_workspace(text) to authenticated;

alter function public.set_case_status(uuid, public.case_status) set schema private;
alter function private.set_case_status(uuid, public.case_status)
  rename to set_case_status_impl;

revoke all on function private.set_case_status_impl(uuid, public.case_status)
  from public, anon;
grant execute on function private.set_case_status_impl(uuid, public.case_status)
  to authenticated;

create function public.set_case_status(
  target_case_id uuid,
  new_status public.case_status
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.set_case_status_impl(target_case_id, new_status);
$$;

revoke all on function public.set_case_status(uuid, public.case_status)
  from public, anon;
grant execute on function public.set_case_status(uuid, public.case_status)
  to authenticated;
