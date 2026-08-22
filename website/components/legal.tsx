import Link from "next/link";
import type { ReactNode } from "react";

export const legalNavLinks = [
  { href: "/support", label: "Support" },
  { href: "/terms", label: "Terms" },
  { href: "/privacy", label: "Privacy" },
  { href: "/refunds", label: "Refunds" },
];

export function LegalShell({
  eyebrow,
  title,
  updated,
  children,
}: {
  eyebrow: string;
  title: string;
  updated?: string;
  children: ReactNode;
}) {
  return (
    <main>
      <nav className="nav shell">
        <Link className="brand" href="/" aria-label="Signalcase home">
          <span className="brand-mark" aria-hidden="true">⌁</span>
          <span>SIGNALCASE</span>
        </Link>
        <div className="nav-links">
          {legalNavLinks.map((link) => (
            <Link key={link.href} href={link.href}>{link.label}</Link>
          ))}
        </div>
        <a className="nav-cta" href="/">Back to home <span>↗</span></a>
      </nav>

      <article className="legal shell">
        <header className="legal-head">
          <span className="legal-eyebrow">{eyebrow}</span>
          <h1>{title}</h1>
          {updated ? <p className="legal-updated">Last updated {updated}</p> : null}
        </header>
        <div className="legal-body">{children}</div>
      </article>

      <footer className="shell legal-footer">
        <div className="brand"><span className="brand-mark">⌁</span><span>SIGNALCASE</span></div>
        <div className="legal-footer-links">
          {legalNavLinks.map((link) => (
            <Link key={link.href} href={link.href}>{link.label}</Link>
          ))}
        </div>
      </footer>
    </main>
  );
}

export function LegalSection({ heading, children }: { heading: string; children: ReactNode }) {
  return (
    <section>
      <h2>{heading}</h2>
      {children}
    </section>
  );
}
