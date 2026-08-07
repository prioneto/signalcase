import Link from "next/link";

type ErrorPageProps = {
  searchParams: Promise<{
    reason?: string;
  }>;
};

const messages: Record<string, string> = {
  "missing-code": "GitHub did not return a login code.",
  "code-exchange": "The login code expired or could not be verified.",
  "missing-user": "Signalcase could not load your account.",
  workspace:
    "Your account was created, but the workspace could not be prepared.",
};

export default async function AuthErrorPage({ searchParams }: ErrorPageProps) {
  const { reason = "" } = await searchParams;

  return (
    <main className="auth-page">
      <section className="auth-card">
        <div className="auth-eyebrow">SIGN-IN PROBLEM</div>
        <h1>We couldn’t finish signing you in</h1>
        <p>
          {messages[reason] ?? "An unexpected authentication error occurred."}
        </p>

        <Link className="auth-button" href="/sign-in">
          Try again
          <span>→</span>
        </Link>
      </section>
    </main>
  );
}
