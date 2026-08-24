import Link from "next/link";
import { signInWithGitHub } from "./actions";

type SignInPageProps = {
  searchParams: Promise<{
    error?: string;
    next?: string;
    unconfigured?: string;
  }>;
};

export default async function SignInPage({ searchParams }: SignInPageProps) {
  const params = await searchParams;
  const backendConfigured = Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  );

  if (!backendConfigured || params.unconfigured === "1") {
    return (
      <main className="auth-page">
        <Link className="auth-brand" href="/">
          <span>⌁</span>
          SIGNALCASE
        </Link>

        <section className="auth-card">
          <div className="auth-eyebrow">SELF-HOSTED</div>
          <h1>This site is a demo</h1>
          <p>
            Signalcase has no official hosted service. To use it with your team,
            run your own instance — the repository includes a step-by-step guide.
          </p>
          <a
            className="auth-button"
            href="https://github.com/prioneto/signalcase/blob/main/docs/SELF_HOSTING.md"
            target="_blank"
            rel="noreferrer"
          >
            <span className="github-mark">GH</span>
            Read the self-hosting guide
            <span>→</span>
          </a>
          <small>Free and open source under AGPL-3.0. No account here is required.</small>
        </section>
      </main>
    );
  }

  return (
    <main className="auth-page">
      <Link className="auth-brand" href="/">
        <span>⌁</span>
        SIGNALCASE
      </Link>

      <section className="auth-card">
        <div className="auth-eyebrow">SIGNALCASE CLOUD</div>

        <h1>Sign in to your workspace</h1>

        <p>
          Your team’s cases, connections, and case status will stay synchronized
          across every Mac.
        </p>

        {params.error ? <div className="auth-error">{params.error}</div> : null}

        <form action={signInWithGitHub}>
          <input name="next" type="hidden" value={params.next ?? "/dashboard"} />
          <button className="auth-button" type="submit">
            <span className="github-mark">GH</span>
            Continue with GitHub
            <span>→</span>
          </button>
        </form>

        <small>
          GitHub is currently used only to identify your Signalcase account.
          Repository access is not requested.
        </small>
      </section>
    </main>
  );
}
