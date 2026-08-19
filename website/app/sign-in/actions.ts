"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function safeNext(value: FormDataEntryValue | null) {
  const path = typeof value === "string" ? value : "";
  return path.startsWith("/") && !path.startsWith("//") ? path : "/dashboard";
}

export async function signInWithGitHub(formData: FormData) {
  const siteURL = process.env.NEXT_PUBLIC_SITE_URL;

  if (!siteURL) {
    throw new Error("NEXT_PUBLIC_SITE_URL is not configured.");
  }

  const next = safeNext(formData.get("next"));
  const supabase = await createClient();

  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: "github",
    options: {
      redirectTo: `${siteURL}/auth/callback?next=${encodeURIComponent(next)}`,
    },
  });

  if (error) {
    redirect(`/sign-in?error=${encodeURIComponent(error.message)}`);
  }

  if (!data.url) {
    redirect("/sign-in?error=GitHub%20did%20not%20return%20a%20login%20URL");
  }

  redirect(data.url);
}
