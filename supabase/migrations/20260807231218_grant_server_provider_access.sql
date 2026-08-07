-- The project predates Supabase's current Data API grant defaults. Its
-- provider_connections table therefore did not give service_role the CRUD
-- privileges required by the hosted OAuth routes.

revoke all on table public.provider_connections from service_role;
grant select, insert, update, delete
  on table public.provider_connections to service_role;

-- Keep the two credential tables server-only and remove inherited privileges
-- such as TRUNCATE, TRIGGER, and REFERENCES that the OAuth routes never use.
revoke all on table public.provider_oauth_states from service_role;
revoke all on table public.provider_credentials from service_role;

grant select, insert, update, delete
  on table public.provider_oauth_states to service_role;
grant select, insert, update, delete
  on table public.provider_credentials to service_role;
