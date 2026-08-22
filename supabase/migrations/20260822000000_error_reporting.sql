-- First-party error reporting for the Signalcase server, the macOS app, and
-- the website. Rows are written by service_role only; there are no client
-- policies on purpose.

create table public.error_reports (
  id bigint generated always as identity primary key,
  source text not null
    check (source in ('server', 'macos', 'web')),
  message text not null check (char_length(message) <= 2000),
  stack text,
  path text,
  method text,
  request_id text,
  app_version text,
  os_version text,
  context jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

comment on table public.error_reports is
  'Operational error reports captured from the server and native clients.';

create index error_reports_occurred_at_idx
  on public.error_reports (occurred_at desc);

create index error_reports_source_idx
  on public.error_reports (source, occurred_at desc);

alter table public.error_reports enable row level security;

revoke all on table public.error_reports
  from public, anon, authenticated, service_role;

grant insert, select, delete
  on table public.error_reports to service_role;

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
  removed_errors integer := 0;
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

  delete from public.error_reports
  where occurred_at < now() - interval '90 days';
  get diagnostics removed_errors = row_count;

  return jsonb_build_object(
    'raw_events', removed_events,
    'oauth_states', removed_states,
    'feedback', removed_feedback,
    'rate_limits', removed_limits,
    'stripe_webhooks', removed_webhooks,
    'error_reports', removed_errors
  );
end;
$$;

revoke all on function public.cleanup_signalcase_data()
  from public, anon, authenticated;
grant execute on function public.cleanup_signalcase_data() to service_role;
