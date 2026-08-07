-- Returns an existing workspace for the signed-in user or creates one.
-- The advisory lock prevents duplicate workspaces during simultaneous callbacks.

create or replace function public.ensure_workspace(
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
  selected_workspace public.workspaces;
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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text, 0)
  );

  select workspace.*
  into selected_workspace
  from public.workspaces as workspace
  join public.workspace_members as membership
    on membership.workspace_id = workspace.id
  where membership.user_id = caller_id
  order by membership.created_at
  limit 1;

  if found then
    return selected_workspace;
  end if;

  insert into public.workspaces (
    name,
    created_by
  )
  values (
    normalized_name,
    caller_id
  )
  returning * into selected_workspace;

  insert into public.workspace_members (
    workspace_id,
    user_id,
    role
  )
  values (
    selected_workspace.id,
    caller_id,
    'owner'
  );

  return selected_workspace;
end;
$$;

revoke all on function public.ensure_workspace(text) from public;
revoke all on function public.ensure_workspace(text) from anon;
grant execute on function public.ensure_workspace(text) to authenticated;
