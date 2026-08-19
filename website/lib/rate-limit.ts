import { createHash } from "node:crypto";
import type { SupabaseClient } from "@supabase/supabase-js";
import { APIError } from "@/lib/api-auth";

type RateLimitRow = {
  allowed: boolean;
  remaining: number;
  reset_at: string;
};

export async function enforceRateLimit(
  admin: SupabaseClient,
  input: {
    bucket: string;
    subject: string;
    maximum: number;
    windowSeconds: number;
  },
) {
  const subjectHash = createHash("sha256").update(input.subject).digest("hex");
  const { data, error } = await admin.rpc("consume_signalcase_rate_limit", {
    limit_bucket: input.bucket,
    limit_subject_hash: subjectHash,
    limit_window_seconds: input.windowSeconds,
    limit_max_requests: input.maximum,
  });
  if (error) throw new APIError("Signalcase could not verify the request limit.", 503);

  const row = (Array.isArray(data) ? data[0] : data) as RateLimitRow | null;
  if (!row?.allowed) {
    const retryAt = row?.reset_at ? new Date(row.reset_at) : null;
    const seconds = retryAt
      ? Math.max(1, Math.ceil((retryAt.getTime() - Date.now()) / 1_000))
      : input.windowSeconds;
    throw new APIError(`Too many requests. Try again in ${seconds} seconds.`, 429);
  }
  return row;
}
