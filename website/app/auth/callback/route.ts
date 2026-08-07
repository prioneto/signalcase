import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

function safeRelativePath(value: string | null) {
  if (!value || !value.startsWith("/") || value.startsWith("//")) {
    return "/dashboard";
  }

  return value;
}

function redirectOrigin(request: Request) {
  const requestURL = new URL(request.url);

  if (process.env.NODE_ENV === "development") {
    return requestURL.origin;
  }

  const forwardedHost = request.headers.get("x-forwarded-host");

  if (forwardedHost) {
    return `https://${forwardedHost}`;
  }

  return requestURL.origin;
}

export async function GET(request: Request) {
  const requestURL = new URL(request.url);
  const code = requestURL.searchParams.get("code");
  const next = safeRelativePath(requestURL.searchParams.get("next"));
  const origin = redirectOrigin(request);

  if (!code) {
    return NextResponse.redirect(
      `${origin}/auth/auth-code-error?reason=missing-code`,
    );
  }

  const supabase = await createClient();

  const { error: exchangeError } =
    await supabase.auth.exchangeCodeForSession(code);

  if (exchangeError) {
    return NextResponse.redirect(
      `${origin}/auth/auth-code-error?reason=code-exchange`,
    );
  }

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) {
    return NextResponse.redirect(
      `${origin}/auth/auth-code-error?reason=missing-user`,
    );
  }

  const githubName =
    typeof user.user_metadata?.user_name === "string"
      ? user.user_metadata.user_name.trim().slice(0, 55)
      : "";

  const workspaceName = githubName
    ? `${githubName}'s Workspace`
    : "My Workspace";

  const { error: workspaceError } = await supabase.rpc("ensure_workspace", {
    workspace_name: workspaceName,
  });

  if (workspaceError) {
    return NextResponse.redirect(
      `${origin}/auth/auth-code-error?reason=workspace`,
    );
  }

  return NextResponse.redirect(`${origin}${next}`, 303);
}
