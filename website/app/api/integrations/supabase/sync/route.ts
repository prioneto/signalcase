import { APIError, jsonError, requireProjectAccess } from "@/lib/api-auth";
import { decryptSecret, encryptSecret } from "@/lib/credential-crypto";
import { exchangeManagementToken, managementAPI } from "@/lib/supabase-management";

type Body = { projectId?: string; start?: string; end?: string };

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as Body;
    if (!body.projectId || !body.start || !body.end) throw new APIError("Missing sync time range.");
    const start = new Date(body.start);
    const end = new Date(body.end);
    if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) || end <= start) {
      throw new APIError("Choose a valid sync time range.");
    }
    if (end.getTime() - start.getTime() > 24 * 60 * 60 * 1000) {
      throw new APIError("A single sync can cover at most 24 hours.");
    }

    const { admin } = await requireProjectAccess(request, body.projectId);
    const { data: connection, error: connectionError } = await admin
      .from("provider_connections")
      .select("id, state, metadata")
      .eq("project_id", body.projectId)
      .eq("provider", "supabase")
      .maybeSingle();
    if (connectionError || !connection || connection.state !== "connected") {
      throw new APIError("Connect Supabase before syncing logs.", 409);
    }
    const projectRef = connection.metadata?.external_project_ref;
    if (!projectRef) throw new APIError("The Supabase project reference is missing.", 409);

    const { data: credential, error: credentialError } = await admin
      .from("provider_credentials")
      .select("*")
      .eq("connection_id", connection.id)
      .maybeSingle();
    if (credentialError || !credential) throw new APIError("Reconnect Supabase to restore access.", 409);

    let accessToken = decryptSecret(credential.access_token_ciphertext);
    if (credential.expires_at && new Date(credential.expires_at).getTime() < Date.now() + 60_000) {
      if (!credential.refresh_token_ciphertext) throw new APIError("Reconnect Supabase; its access expired.", 409);
      const refreshed = await exchangeManagementToken(new URLSearchParams({
        grant_type: "refresh_token",
        refresh_token: decryptSecret(credential.refresh_token_ciphertext),
      }));
      accessToken = refreshed.access_token;
      const expiresAt = refreshed.expires_in
        ? new Date(Date.now() + refreshed.expires_in * 1000).toISOString()
        : null;
      await admin.from("provider_credentials").update({
        access_token_ciphertext: encryptSecret(refreshed.access_token),
        refresh_token_ciphertext: refreshed.refresh_token
          ? encryptSecret(refreshed.refresh_token)
          : credential.refresh_token_ciphertext,
        expires_at: expiresAt,
        granted_scope: refreshed.scope ?? credential.granted_scope,
      }).eq("connection_id", connection.id);
    }

    const sql = `
      select timestamp, event_message, source,
        log_attributes['request.method'] as method,
        log_attributes['request.path'] as path,
        log_attributes['response.status_code'] as status_code,
        log_attributes['request.id'] as request_id,
        log_attributes['sb.auth_user'] as user_id,
        log_attributes['parsed.sql_state_code'] as sql_state,
        log_attributes['parsed.error_severity'] as error_severity
      from logs
      where source in ('edge_logs', 'postgres_logs', 'auth_logs', 'function_edge_logs', 'function_logs', 'storage_logs')
      order by timestamp desc
      limit 500
    `;
    let cursorEnd = end;
    const rows: Record<string, unknown>[] = [];
    for (let page = 0; page < 10; page += 1) {
      const logsURL = new URL(`${managementAPI}/projects/${projectRef}/analytics/endpoints/logs`);
      logsURL.searchParams.set("sql", sql);
      logsURL.searchParams.set("iso_timestamp_start", start.toISOString());
      logsURL.searchParams.set("iso_timestamp_end", cursorEnd.toISOString());
      const logsResponse = await fetch(logsURL, {
        headers: { Authorization: `Bearer ${accessToken}` },
        cache: "no-store",
      });
      const payload = await logsResponse.json().catch(() => ({}));
      if (!logsResponse.ok) {
        const message = payload.message ?? payload.error ?? `Supabase returned ${logsResponse.status}.`;
        await admin.from("provider_connections").update({ state: "error", last_error: String(message) }).eq("id", connection.id);
        throw new APIError(String(message), 502);
      }
      const pageRows = Array.isArray(payload)
        ? payload
        : ["data", "result", "logs", "events", "items"]
            .map((key) => payload[key])
            .find(Array.isArray) ?? [];
      rows.push(...pageRows);
      if (pageRows.length < 500) break;
      const timestamps = pageRows
        .map((row: Record<string, unknown>) => new Date(String(row.timestamp ?? "")).getTime())
        .filter(Number.isFinite);
      if (!timestamps.length) break;
      const nextEnd = new Date(Math.min(...timestamps) - 1);
      if (nextEnd <= start || nextEnd >= cursorEnd) break;
      cursorEnd = nextEnd;
    }
    await admin.from("provider_connections").update({
      state: "connected",
      last_synced_at: new Date().toISOString(),
      last_error: null,
    }).eq("id", connection.id);
    return Response.json({ payload: { result: rows } });
  } catch (error) {
    return jsonError(error);
  }
}
