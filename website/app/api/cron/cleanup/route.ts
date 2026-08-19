import { createAdminClient } from "@/lib/supabase/admin";

export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return Response.json({ error: "Unauthorized." }, { status: 401 });
  }
  const admin = createAdminClient();
  const { data, error } = await admin.rpc("cleanup_signalcase_data");
  if (error) {
    console.error("Signalcase cleanup failed", { message: error.message });
    return Response.json({ error: "Cleanup failed." }, { status: 500 });
  }
  return Response.json({ cleaned: data, completedAt: new Date().toISOString() });
}
