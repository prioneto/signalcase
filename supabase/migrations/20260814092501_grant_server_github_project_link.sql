-- The GitHub repository selection route stores the canonical repository URL on
-- the Signalcase project after access has already been checked for the caller.
-- Keep this server grant column-scoped rather than granting broad project CRUD.
grant select (id), update (repository_url)
  on table public.projects
  to service_role;
