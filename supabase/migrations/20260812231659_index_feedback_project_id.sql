create index feedback_submissions_project_id_idx
  on public.feedback_submissions(project_id)
  where project_id is not null;
