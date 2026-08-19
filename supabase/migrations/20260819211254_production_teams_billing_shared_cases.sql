-- Production collaboration, billing, quotas, and server-side operational
-- controls. Client roles receive read access only where RLS can prove workspace
-- membership. All mutations are performed by authenticated Signalcase routes
-- after an explicit owner/member check.

alter type public.case_status add value if not exists 'active';
alter type public.case_status add value if not exists 'resolved';
alter type public.case_severity add value if not exists 'high';
alter type public.case_severity add value if not exists 'critical';

alter table public.cases
  add column if not exists reference_number bigint,
  add column if not exists release text,
  add column if not exists environment text not null default 'Production',
  add column if not exists snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(snapshot) = 'object'),
  add column if not exists revision bigint not null default 1
    check (revision > 0),
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists updated_by uuid references auth.users(id) on delete set null,
  add column if not exists deleted_at timestamptz;

with numbered as (
  select id,
         row_number() over (partition by project_id order by created_at, id) as number
  from public.cases
  where reference_number is null
)
update public.cases as target
set reference_number = numbered.number
from numbered
where target.id = numbered.id;

alter table public.cases alter column reference_number set not null;

create unique index if not exists cases_project_reference_number_idx
  on public.cases(project_id, reference_number);

create index if not exists cases_project_updated_idx
  on public.cases(project_id, updated_at desc)
  where deleted_at is null;

create or replace function private.assign_case_reference_number()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.reference_number is null then
    perform pg_advisory_xact_lock(hashtextextended(new.project_id::text, 0));
    select coalesce(max(reference_number), 0) + 1
      into new.reference_number
      from public.cases
      where project_id = new.project_id;
  end if;
  return new;
end;
$$;

revoke all on function private.assign_case_reference_number()
  from public, anon, authenticated;

create trigger cases_assign_reference_number
before insert on public.cases
for each row execute function private.assign_case_reference_number();

create table public.case_status_changes (
  id bigint generated always as identity primary key,
  case_id uuid not null references public.cases(id) on delete cascade,
  changed_by uuid references auth.users(id) on delete set null,
  from_status public.case_status,
  to_status public.case_status not null,
  created_at timestamptz not null default now()
);

create index case_status_changes_case_time_idx
  on public.case_status_changes(case_id, created_at desc);

alter table public.case_status_changes enable row level security;

create policy case_status_changes_select
on public.case_status_changes
for select
to authenticated
using (private.can_access_case(case_id));

grant select on public.case_status_changes to authenticated;

alter table public.invitations
  add column if not exists accepted_by uuid references auth.users(id) on delete set null,
  add column if not exists revoked_at timestamptz;

create unique index if not exists invitations_one_pending_email_idx
  on public.invitations(workspace_id, lower(email))
  where accepted_at is null and revoked_at is null;

create table public.workspace_settings (
  workspace_id uuid primary key references public.workspaces(id) on delete cascade,
  member_limit smallint not null default 5 check (member_limit between 1 and 100),
  project_limit smallint not null default 3 check (project_limit between 1 and 100),
  event_retention_days smallint not null default 30
    check (event_retention_days between 7 and 365),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.workspace_subscriptions (
  workspace_id uuid primary key references public.workspaces(id) on delete cascade,
  provider text not null default 'internal'
    check (provider in ('internal', 'stripe')),
  plan_key text not null default 'team',
  status text not null default 'trialing'
    check (status in (
      'trialing', 'active', 'past_due', 'incomplete', 'incomplete_expired',
      'paused', 'unpaid', 'canceled'
    )),
  stripe_customer_id text unique,
  stripe_subscription_id text unique,
  stripe_price_id text,
  trial_ends_at timestamptz,
  current_period_ends_at timestamptz,
  cancel_at_period_end boolean not null default false,
  last_payment_failed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.workspace_settings (workspace_id)
select id from public.workspaces
on conflict (workspace_id) do nothing;

insert into public.workspace_subscriptions (workspace_id, trial_ends_at)
select id, created_at + interval '14 days'
from public.workspaces
on conflict (workspace_id) do nothing;

create or replace function private.bootstrap_workspace_operations()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null and new.created_by <> auth.uid() then
    raise exception 'Workspace owner does not match the authenticated user';
  end if;
  insert into public.workspace_settings (workspace_id) values (new.id);
  insert into public.workspace_subscriptions (workspace_id, trial_ends_at)
  values (new.id, new.created_at + interval '14 days');
  return new;
end;
$$;

revoke all on function private.bootstrap_workspace_operations()
  from public, anon, authenticated;

create trigger workspaces_bootstrap_operations
after insert on public.workspaces
for each row execute function private.bootstrap_workspace_operations();

create trigger workspace_settings_set_updated_at
before update on public.workspace_settings
for each row execute function private.set_updated_at();

create trigger workspace_subscriptions_set_updated_at
before update on public.workspace_subscriptions
for each row execute function private.set_updated_at();

alter table public.workspace_settings enable row level security;
alter table public.workspace_subscriptions enable row level security;

create policy workspace_settings_select
on public.workspace_settings
for select
to authenticated
using (private.is_workspace_member(workspace_id));

create policy workspace_subscriptions_select
on public.workspace_subscriptions
for select
to authenticated
using (private.is_workspace_member(workspace_id));

grant select on public.workspace_settings to authenticated;
grant select on public.workspace_subscriptions to authenticated;

create table public.stripe_webhook_events (
  event_id text primary key,
  event_type text not null,
  livemode boolean not null,
  processed_at timestamptz not null default now()
);

comment on table public.stripe_webhook_events is
  'Server-only idempotency ledger for verified Stripe webhook deliveries.';

alter table public.stripe_webhook_events enable row level security;

create table public.api_rate_limits (
  bucket text not null,
  subject_hash text not null check (subject_hash ~ '^[a-f0-9]{64}$'),
  window_start timestamptz not null,
  request_count integer not null default 1 check (request_count > 0),
  primary key (bucket, subject_hash, window_start)
);

comment on table public.api_rate_limits is
  'Server-only fixed-window counters. Subjects are SHA-256 hashes.';

alter table public.api_rate_limits enable row level security;

create or replace function public.consume_signalcase_rate_limit(
  limit_bucket text,
  limit_subject_hash text,
  limit_window_seconds integer,
  limit_max_requests integer
)
returns table(allowed boolean, remaining integer, reset_at timestamptz)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  bucket_start timestamptz;
  current_count integer;
begin
  if limit_bucket !~ '^[a-z0-9:_-]{1,80}$'
     or limit_subject_hash !~ '^[a-f0-9]{64}$'
     or limit_window_seconds < 1
     or limit_window_seconds > 86400
     or limit_max_requests < 1
     or limit_max_requests > 100000 then
    raise exception 'Invalid rate limit configuration';
  end if;

  bucket_start := to_timestamp(
    floor(extract(epoch from now()) / limit_window_seconds) * limit_window_seconds
  );

  insert into public.api_rate_limits (
    bucket, subject_hash, window_start, request_count
  ) values (
    limit_bucket, limit_subject_hash, bucket_start, 1
  )
  on conflict (bucket, subject_hash, window_start)
  do update set request_count = public.api_rate_limits.request_count + 1
  returning request_count into current_count;

  return query select
    current_count <= limit_max_requests,
    greatest(0, limit_max_requests - current_count),
    bucket_start + make_interval(secs => limit_window_seconds);
end;
$$;

revoke all on function public.consume_signalcase_rate_limit(text, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_signalcase_rate_limit(text, text, integer, integer)
  to service_role;

create or replace function public.cleanup_signalcase_data()
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  removed_events integer := 0;
  removed_states integer := 0;
  removed_feedback integer := 0;
  removed_limits integer := 0;
  removed_webhooks integer := 0;
begin
  delete from public.raw_events as events
  using public.projects as projects, public.workspace_settings as settings
  where events.project_id = projects.id
    and projects.workspace_id = settings.workspace_id
    and events.received_at < now() - make_interval(days => settings.event_retention_days);
  get diagnostics removed_events = row_count;

  delete from public.provider_oauth_states
  where expires_at < now() - interval '1 day';
  get diagnostics removed_states = row_count;

  delete from public.feedback_submissions
  where created_at < now() - interval '365 days';
  get diagnostics removed_feedback = row_count;

  delete from public.api_rate_limits
  where window_start < now() - interval '2 days';
  get diagnostics removed_limits = row_count;

  delete from public.stripe_webhook_events
  where processed_at < now() - interval '90 days';
  get diagnostics removed_webhooks = row_count;

  return jsonb_build_object(
    'raw_events', removed_events,
    'oauth_states', removed_states,
    'feedback', removed_feedback,
    'rate_limits', removed_limits,
    'stripe_webhooks', removed_webhooks
  );
end;
$$;

revoke all on function public.cleanup_signalcase_data()
  from public, anon, authenticated;
grant execute on function public.cleanup_signalcase_data() to service_role;

revoke all on table public.case_status_changes from service_role;
revoke all on table public.workspace_members from service_role;
revoke all on table public.invitations from service_role;
revoke all on table public.workspace_settings from service_role;
revoke all on table public.workspace_subscriptions from service_role;
revoke all on table public.stripe_webhook_events from service_role;
revoke all on table public.api_rate_limits from service_role;

grant select, insert, update, delete on public.cases to service_role;
grant select, insert, update, delete on public.case_status_changes to service_role;
grant select, insert, update, delete on public.raw_events to service_role;
grant select, insert, update, delete on public.workspace_members to service_role;
grant select, insert, update, delete on public.invitations to service_role;
grant select, insert, update, delete on public.workspace_settings to service_role;
grant select, insert, update, delete on public.workspace_subscriptions to service_role;
grant select, insert, delete on public.stripe_webhook_events to service_role;
grant select, insert, update, delete on public.api_rate_limits to service_role;

grant usage, select on sequence public.case_status_changes_id_seq to service_role;

-- Seat checks and invitation acceptance must be atomic. These server-only
-- functions take an advisory lock per workspace before counting or mutating
-- members, so simultaneous browser/app requests cannot exceed plan limits.
create or replace function public.create_signalcase_invitation(
  target_workspace_id uuid,
  actor_user_id uuid,
  invited_email text,
  invited_role public.workspace_role,
  invited_token_hash text,
  invitation_expires_at timestamptz
)
returns public.invitations
language plpgsql
security invoker
set search_path = ''
as $$
declare
  member_limit_value integer;
  occupied_seats integer;
  created_invitation public.invitations;
begin
  perform pg_advisory_xact_lock(hashtextextended(target_workspace_id::text, 0));
  if not exists (
    select 1 from public.workspace_members
    where workspace_id = target_workspace_id
      and user_id = actor_user_id
      and role = 'owner'
  ) then
    raise exception 'Only a workspace owner can invite members';
  end if;

  select member_limit into member_limit_value
  from public.workspace_settings where workspace_id = target_workspace_id;

  select
    (select count(*) from public.workspace_members where workspace_id = target_workspace_id)
    +
    (select count(*) from public.invitations
      where workspace_id = target_workspace_id
        and accepted_at is null and revoked_at is null and expires_at > now())
  into occupied_seats;

  if occupied_seats >= coalesce(member_limit_value, 5) then
    raise exception 'Workspace member limit reached';
  end if;

  update public.invitations set revoked_at = now()
  where workspace_id = target_workspace_id
    and lower(email) = lower(invited_email)
    and accepted_at is null and revoked_at is null;

  insert into public.invitations (
    workspace_id, email, role, token_hash, invited_by, expires_at
  ) values (
    target_workspace_id, lower(trim(invited_email)), invited_role,
    invited_token_hash, actor_user_id, invitation_expires_at
  ) returning * into created_invitation;
  return created_invitation;
end;
$$;

create or replace function public.accept_signalcase_invitation(
  invited_token_hash text,
  accepting_user_id uuid,
  accepting_email text
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  target public.invitations;
  member_limit_value integer;
  member_count integer;
begin
  select * into target from public.invitations
  where token_hash = invited_token_hash
  for update;
  if not found
     or target.accepted_at is not null
     or target.revoked_at is not null
     or target.expires_at <= now() then
    raise exception 'Invitation is unavailable';
  end if;
  if lower(target.email) <> lower(trim(accepting_email)) then
    raise exception 'Invitation email does not match';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(target.workspace_id::text, 0));
  select member_limit into member_limit_value
  from public.workspace_settings where workspace_id = target.workspace_id;
  select count(*) into member_count
  from public.workspace_members where workspace_id = target.workspace_id;

  if not exists (
    select 1 from public.workspace_members
    where workspace_id = target.workspace_id and user_id = accepting_user_id
  ) and member_count >= coalesce(member_limit_value, 5) then
    raise exception 'Workspace member limit reached';
  end if;

  insert into public.workspace_members (workspace_id, user_id, role)
  values (target.workspace_id, accepting_user_id, target.role)
  on conflict (workspace_id, user_id) do nothing;

  update public.invitations
  set accepted_at = now(), accepted_by = accepting_user_id
  where id = target.id;
  return target.workspace_id;
end;
$$;

revoke all on function public.create_signalcase_invitation(uuid, uuid, text, public.workspace_role, text, timestamptz)
  from public, anon, authenticated;
revoke all on function public.accept_signalcase_invitation(text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.create_signalcase_invitation(uuid, uuid, text, public.workspace_role, text, timestamptz)
  to service_role;
grant execute on function public.accept_signalcase_invitation(text, uuid, text)
  to service_role;
