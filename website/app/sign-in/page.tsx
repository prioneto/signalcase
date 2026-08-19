import Link from "next/link";
import { signInWithGitHub } from "./actions";

type SignInPageProps = {
  searchParams: Promise<{
    error?: string;
    next?: string;
  }>;
};

export default async function SignInPage({ searchParams }: SignInPageProps) {
  const params = await searchParams;

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
