-- Feedback submitted from the native app. Users may create feedback but cannot
-- read, edit, or delete submissions through the public Data API.

create table public.feedback_submissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid default auth.uid()
    references auth.users(id) on delete set null,
  project_id uuid
    references public.projects(id) on delete set null,
  kind text not null
    check (kind in ('bug', 'question', 'feature')),
  subject text not null
    check (char_length(trim(subject)) between 1 and 160),
  message text not null
    check (char_length(trim(message)) between 1 and 10000),
  contact_email text
    check (contact_email is null or char_length(contact_email) <= 320),
  app_version text,
  app_build text,
  os_version text,
  project_name text,
  connected_sources text[] not null default '{}',
  status text not null default 'new'
    check (status in ('new', 'reviewed', 'planned', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.feedback_submissions is
  'Bug reports, questions, and feature requests submitted from Signalcase clients.';

create index feedback_submissions_status_created_at_idx
  on public.feedback_submissions(status, created_at desc);

create index feedback_submissions_user_id_idx
  on public.feedback_submissions(user_id)
  where user_id is not null;

create trigger feedback_submissions_set_updated_at
before update on public.feedback_submissions
for each row execute function private.set_updated_at();

alter table public.feedback_submissions enable row level security;

create policy feedback_submissions_insert
on public.feedback_submissions
for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and (
    project_id is null
    or private.can_access_project(project_id)
  )
);

-- Explicit grants are required for new Data API tables. The native app only
-- receives INSERT; support staff use the Dashboard or server credentials.
revoke all on table public.feedback_submissions from public, anon, authenticated;
grant insert on table public.feedback_submissions to authenticated;
grant select, insert, update, delete
  on table public.feedback_submissions to service_role;
