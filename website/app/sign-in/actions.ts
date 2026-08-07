"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function signInWithGitHub() {
  const siteURL = process.env.NEXT_PUBLIC_SITE_URL;

  if (!siteURL) {
    throw new Error("NEXT_PUBLIC_SITE_URL is not configured.");
  }

  const supabase = await createClient();

  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: "github",
    options: {
      redirectTo: `${siteURL}/auth/callback`,
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
