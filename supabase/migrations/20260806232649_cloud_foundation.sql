-- Signalcase Cloud: initial team, integration, event, and case model.

create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;
grant usage on schema private to authenticated;

create type public.workspace_role as enum (
  'owner',
  'member'
);

create type public.provider_kind as enum (
  'supabase',
  'render',
  'stripe',
  'revenuecat',
  'sentry',
  'application'
);

create type public.connection_state as enum (
  'disconnected',
  'connecting',
  'connected',
  'error'
);

create type public.event_level as enum (
  'debug',
  'info',
  'warning',
  'error',
  'critical'
);

create type public.case_status as enum (
  'new',
  'reviewed',
  'fixing',
  'verified'
);

create type public.case_severity as enum (
  'normal',
  'elevated',
  'urgent'
);

create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null
    check (char_length(trim(name)) between 2 and 80),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.workspace_members (
  workspace_id uuid not null
    references public.workspaces(id) on delete cascade,
  user_id uuid not null
    references auth.users(id) on delete cascade,
  role public.workspace_role not null default 'member',
  created_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null
    references public.workspaces(id) on delete cascade,
  name text not null
    check (char_length(trim(name)) between 1 and 100),
  slug text not null
    check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  repository_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, slug)
);

create table public.provider_connections (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null
    references public.projects(id) on delete cascade,
  provider public.provider_kind not null,
  state public.connection_state not null default 'disconnected',

  -- Safe identifiers only. Never put API keys or access tokens here.
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),

  connected_at timestamptz,
  last_synced_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, provider)
);

comment on column public.provider_connections.metadata is
  'Non-secret provider metadata only. Credentials belong in server-side encrypted storage.';

create table public.raw_events (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null
    references public.projects(id) on delete cascade,
  connection_id uuid
    references public.provider_connections(id) on delete set null,
  provider public.provider_kind not null,
  provider_event_id text,
  dedupe_key text not null,
  level public.event_level not null default 'info',
  event_type text not null,
  title text not null,
  summary text,
  request_id text,
  actor_external_id text,
  release text,
  route text,

  -- The collector must redact secrets before storing this payload.
  payload jsonb not null default '{}'::jsonb
    check (jsonb_typeof(payload) = 'object'),

  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  unique (project_id, dedupe_key)
);

comment on column public.raw_events.payload is
  'Redacted provider payload. Must not contain credentials, authorization headers, or payment details.';

create table public.cases (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null
    references public.projects(id) on delete cascade,
  fingerprint text not null,
  title text not null,
  summary text,
  status public.case_status not null default 'new',
  severity public.case_severity not null default 'normal',
  occurrence_count integer not null default 1
    check (occurrence_count >= 1),
  affected_users integer not null default 0
    check (affected_users >= 0),
  first_seen_at timestamptz not null,
  last_seen_at timestamptz not null,
  root_cause text,
  reproduction_steps text[] not null default '{}',
  relevant_code jsonb not null default '[]'::jsonb
    check (jsonb_typeof(relevant_code) = 'array'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, fingerprint),
  check (last_seen_at >= first_seen_at)
);

create table public.case_events (
  case_id uuid not null
    references public.cases(id) on delete cascade,
  event_id uuid not null
    references public.raw_events(id) on delete cascade,
  correlation_reason text not null,
  is_proven boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (case_id, event_id)
);

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null
    references public.workspaces(id) on delete cascade,
  email text not null,
  role public.workspace_role not null default 'member',
  token_hash text not null unique,
  invited_by uuid not null references auth.users(id),
  accepted_at timestamptz,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table public.case_shares (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null
    references public.cases(id) on delete cascade,
  token_hash text not null unique,
  created_by uuid not null references auth.users(id),
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create index workspace_members_user_id_idx
  on public.workspace_members(user_id);

create index projects_workspace_id_idx
  on public.projects(workspace_id);

create index provider_connections_project_id_idx
  on public.provider_connections(project_id);

create index raw_events_project_time_idx
  on public.raw_events(project_id, occurred_at desc);

create index raw_events_request_id_idx
  on public.raw_events(project_id, request_id)
  where request_id is not null;

create index raw_events_actor_idx
  on public.raw_events(project_id, actor_external_id)
  where actor_external_id is not null;

create unique index raw_events_provider_event_idx
  on public.raw_events(connection_id, provider_event_id)
  where connection_id is not null
    and provider_event_id is not null;

create index cases_project_status_idx
  on public.cases(project_id, status, last_seen_at desc);

create index case_events_event_id_idx
  on public.case_events(event_id);

create index invitations_workspace_idx
  on public.invitations(workspace_id);

create index case_shares_case_idx
  on public.case_shares(case_id);

-- Updated-at trigger

create or replace function private.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function private.set_updated_at() from public;
revoke all on function private.set_updated_at() from anon;
revoke all on function private.set_updated_at() from authenticated;

create trigger workspaces_set_updated_at
before update on public.workspaces
for each row execute function private.set_updated_at();

create trigger projects_set_updated_at
before update on public.projects
for each row execute function private.set_updated_at();

create trigger provider_connections_set_updated_at
before update on public.provider_connections
for each row execute function private.set_updated_at();

create trigger cases_set_updated_at
before update on public.cases
for each row execute function private.set_updated_at();

-- RLS helper functions. These live outside the public API schema.

create or replace function private.is_workspace_member(
  target_workspace_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and exists (
      select 1
      from public.workspace_members as membership
      where membership.workspace_id = target_workspace_id
        and membership.user_id = (select auth.uid())
    );
$$;

create or replace function private.is_workspace_owner(
  target_workspace_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and exists (
      select 1
      from public.workspace_members as membership
      where membership.workspace_id = target_workspace_id
        and membership.user_id = (select auth.uid())
        and membership.role = 'owner'
    );
$$;

create or replace function private.can_access_project(
  target_project_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and exists (
      select 1
      from public.projects as project
      join public.workspace_members as membership
        on membership.workspace_id = project.workspace_id
      where project.id = target_project_id
        and membership.user_id = (select auth.uid())
    );
$$;

create or replace function private.can_access_case(
  target_case_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and exists (
      select 1
      from public.cases as signal_case
      join public.projects as project
        on project.id = signal_case.project_id
      join public.workspace_members as membership
        on membership.workspace_id = project.workspace_id
      where signal_case.id = target_case_id
        and membership.user_id = (select auth.uid())
    );
$$;

revoke all on function private.is_workspace_member(uuid) from public, anon;
revoke all on function private.is_workspace_owner(uuid) from public, anon;
revoke all on function private.can_access_project(uuid) from public, anon;
revoke all on function private.can_access_case(uuid) from public, anon;

grant execute on function private.is_workspace_member(uuid) to authenticated;
grant execute on function private.is_workspace_owner(uuid) to authenticated;
grant execute on function private.can_access_project(uuid) to authenticated;
grant execute on function private.can_access_case(uuid) to authenticated;

-- Atomic workspace creation for signed-in users.

create or replace function public.create_workspace(
  workspace_name text
)
returns public.workspaces
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  normalized_name text;
  created_workspace public.workspaces;
begin
  caller_id := (select auth.uid());
  normalized_name := trim(workspace_name);

  if caller_id is null then
    raise exception 'Authentication required';
  end if;

  if char_length(normalized_name) < 2
     or char_length(normalized_name) > 80 then
    raise exception 'Workspace name must contain 2 to 80 characters';
  end if;

  insert into public.workspaces (name, created_by)
  values (normalized_name, caller_id)
  returning * into created_workspace;

  insert into public.workspace_members (
    workspace_id,
    user_id,
    role
  )
  values (
    created_workspace.id,
    caller_id,
    'owner'
  );

  return created_workspace;
end;
$$;

revoke all on function public.create_workspace(text) from public;
revoke all on function public.create_workspace(text) from anon;
grant execute on function public.create_workspace(text) to authenticated;

-- Allows members to move cases through the simple workflow without
-- giving the native app permission to rewrite detector-generated evidence.

create or replace function public.set_case_status(
  target_case_id uuid,
  new_status public.case_status
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.can_access_case(target_case_id) then
    raise exception 'Case not found or access denied';
  end if;

  update public.cases
  set status = new_status
  where id = target_case_id;
end;
$$;

revoke all on function public.set_case_status(uuid, public.case_status)
  from public;

revoke all on function public.set_case_status(uuid, public.case_status)
  from anon;

grant execute on function public.set_case_status(
  uuid,
  public.case_status
) to authenticated;

-- Row Level Security

alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.projects enable row level security;
alter table public.provider_connections enable row level security;
alter table public.raw_events enable row level security;
alter table public.cases enable row level security;
alter table public.case_events enable row level security;
alter table public.invitations enable row level security;
alter table public.case_shares enable row level security;

create policy workspaces_select
on public.workspaces
for select
to authenticated
using (private.is_workspace_member(id));

create policy workspaces_update
on public.workspaces
for update
to authenticated
using (private.is_workspace_owner(id))
with check (private.is_workspace_owner(id));

create policy workspace_members_select
on public.workspace_members
for select
to authenticated
using (private.is_workspace_member(workspace_id));

create policy projects_select
on public.projects
for select
to authenticated
using (private.is_workspace_member(workspace_id));

create policy projects_insert
on public.projects
for insert
to authenticated
with check (private.is_workspace_owner(workspace_id));

create policy projects_update
on public.projects
for update
to authenticated
using (private.is_workspace_owner(workspace_id))
with check (private.is_workspace_owner(workspace_id));

create policy projects_delete
on public.projects
for delete
to authenticated
using (private.is_workspace_owner(workspace_id));

create policy provider_connections_select
on public.provider_connections
for select
to authenticated
using (private.can_access_project(project_id));

create policy raw_events_select
on public.raw_events
for select
to authenticated
using (private.can_access_project(project_id));

create policy cases_select
on public.cases
for select
to authenticated
using (private.can_access_project(project_id));

create policy case_events_select
on public.case_events
for select
to authenticated
using (private.can_access_case(case_id));

create policy invitations_select
on public.invitations
for select
to authenticated
using (private.is_workspace_owner(workspace_id));

create policy case_shares_select
on public.case_shares
for select
to authenticated
using (private.can_access_case(case_id));

-- Explicit API privileges. RLS still decides which rows are accessible.

revoke all on all tables in schema public from anon;
revoke all on all tables in schema public from authenticated;

grant select on public.workspaces to authenticated;
grant update (name) on public.workspaces to authenticated;

grant select on public.workspace_members to authenticated;

grant select, insert, update, delete
  on public.projects
  to authenticated;

grant select on public.provider_connections to authenticated;
grant select on public.raw_events to authenticated;
grant select on public.cases to authenticated;
grant select on public.case_events to authenticated;
grant select on public.invitations to authenticated;
grant select on public.case_shares to authenticated;
