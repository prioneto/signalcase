create index if not exists case_status_changes_changed_by_idx
  on public.case_status_changes(changed_by)
  where changed_by is not null;

create index if not exists cases_created_by_idx
  on public.cases(created_by)
  where created_by is not null;

create index if not exists cases_updated_by_idx
  on public.cases(updated_by)
  where updated_by is not null;

create index if not exists invitations_accepted_by_idx
  on public.invitations(accepted_by)
  where accepted_by is not null;
