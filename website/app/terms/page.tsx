import type { Metadata } from "next";
import { LegalSection, LegalShell } from "@/components/legal";
import { site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Terms of Service — Signalcase",
  description: "The terms that govern your use of Signalcase.",
};

export default function TermsPage() {
  return (
    <LegalShell eyebrow="LEGAL" title="Terms of Service" updated="August 22, 2026">
      <p>
        These Terms of Service (&quot;Terms&quot;) govern your access to and use of the
        Signalcase macOS application and the Signalcase source repository at
        {site.repoURL.replace("https://", "")},
        and any related services (together, the &quot;Service&quot;). The Service is operated by{" "}
        {site.legalEntity} (&quot;we&quot;, &quot;us&quot;). By creating an account or downloading
        the app you agree to these Terms.
      </p>

      <LegalSection heading="1. Accounts">
        <p>
          You sign in with GitHub. You are responsible for keeping access to your GitHub account secure and
          for all activity that happens under your Signalcase account. Workspaces have one or more owners;
          owners manage members and projects for their workspace.
        </p>
      </LegalSection>

      <LegalSection heading="2. Free license">
        <p>
          Signalcase is provided free of charge. We grant you a personal, non-exclusive,
          non-transferable license to download, install, and use the app for any lawful purpose, including
          commercial use within your team. You do not need to pay, enter a payment method, or subscribe —
          and there are no ads inside the app.
        </p>
        <p>
          We may offer optional paid products or services in the future. If we ever do, they will be clearly
          separate from this free offering, and nothing in these Terms obligates you to buy anything.
        </p>
      </LegalSection>

      <LegalSection heading="3. Acceptable use">
        <p>You agree not to:</p>
        <ul>
          <li>use the Service to break the law or the terms of the platforms you connect;</li>
          <li>connect log sources you do not own or are not permitted to read;</li>
          <li>attempt to access other workspaces&apos; data, probe or overload our servers, or reverse engineer protections on credential storage beyond what the license allows;</li>
          <li>resell or provide the Service as a competing hosted product without written permission.</li>
        </ul>
      </LegalSection>

      <LegalSection heading="4. Your data">
        <p>
          You keep all rights to the logs, cases, and other content you connect or import
          (&quot;Your Data&quot;). You grant us the limited right to store and process Your Data only to
          operate and support the Service for you, including synchronizing it between your signed-in Macs.
          Provider connections are read-only. If you delete a project or your account, we remove the
          associated data as described in the Privacy Policy.
        </p>
      </LegalSection>

      <LegalSection heading="5. Fair use limits">
        <p>
          The hosted parts of the Service include technical limits designed so the free service stays fast
          and available for everyone — such as workspace member and project counts, event history length,
          and API rate limits. These limits are shown in the app. Do not build tooling to circumvent them;
          if you need more headroom, contact us.
        </p>
      </LegalSection>

      <LegalSection heading="6. Findings are informational">
        <p>
          Case grouping and findings are produced by deterministic rules applied to the logs you connect.
          They are intended as development aids, not guarantees. You remain responsible for verifying any
          issue before acting on it, and for decisions about your own production systems.
        </p>
      </LegalSection>

      <LegalSection heading="7. Availability and changes">
        <p>
          We aim for high availability but do not guarantee uninterrupted service, and we may change,
          suspend, or discontinue the free Service at any time. If that ever happens, we will give
          reasonable notice where practical and your local data stays on your Mac. Third-party APIs
          (including Supabase, Render, GitHub) may impose limits or outages outside our control.
        </p>
      </LegalSection>

      <LegalSection heading="8. Termination">
        <p>
          You may stop using the Service and delete your account at any time. We may suspend or close
          accounts that violate these Terms or that create security risk for other users, with notice when
          practical. When a workspace is deleted, its shared data is removed after the retention window
          described in the Privacy Policy.
        </p>
      </LegalSection>

      <LegalSection heading="9. Disclaimers and liability">
        <p>
          The Service is provided &quot;as is&quot;, free of charge, without warranties of any kind except
          those that cannot be excluded by law. To the maximum extent permitted by law, we are not liable
          for indirect or consequential damages, and our total liability relating to the Service is limited
          to the greater of the amount you paid us (nothing, in most cases) or the minimum allowed by law.
          Nothing in these Terms limits liability that cannot be limited under applicable law.
        </p>
      </LegalSection>

      <LegalSection heading="10. Governing law">
        <p>
          These Terms are governed by the laws of the country or state in which {site.legalEntity} is
          established, without regard to conflict-of-law rules. Mandatory consumer protections in your
          country of residence still apply where relevant.
        </p>
      </LegalSection>

      <LegalSection heading="11. Contact">
        <p>
          Questions about these Terms: <a href={site.issuesURL} target="_blank" rel="noreferrer">open an issue on GitHub</a>.
        </p>
      </LegalSection>
    </LegalShell>
  );
}
