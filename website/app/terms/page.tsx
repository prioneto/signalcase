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
        Signalcase macOS application, the Signalcase website at {site.domain.replace(/^https?:\/\//, "")},
        and any related services (together, the &quot;Service&quot;). The Service is operated by{" "}
        {site.legalEntity} (&quot;we&quot;, &quot;us&quot;). By creating an account, downloading the app,
        or starting a subscription you agree to these Terms.
      </p>

      <LegalSection heading="1. Accounts">
        <p>
          You sign in with GitHub. You are responsible for keeping access to your GitHub account secure and
          for all activity that happens under your Signalcase account. Workspaces have one or more owners;
          owners manage members, projects, and billing for their workspace.
        </p>
      </LegalSection>

      <LegalSection heading="2. Subscriptions and billing">
        <p>
          The Service is offered as a paid team subscription billed monthly through Stripe. New workspaces
          start with a free trial; you are not charged during the trial and no card is required until you
          subscribe. Subscriptions renew automatically until cancelled. Prices exclude applicable taxes,
          which are added at checkout where required.
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

      <LegalSection heading="5. Findings are informational">
        <p>
          Case grouping and findings are produced by deterministic rules applied to the logs you connect.
          They are intended as development aids, not guarantees. You remain responsible for verifying any
          issue before acting on it, and for decisions about your own production systems.
        </p>
      </LegalSection>

      <LegalSection heading="6. Availability and changes">
        <p>
          We aim for high availability but do not guarantee uninterrupted service. We may add, change, or
          remove features; if a change materially reduces core functionality of a paid plan, we will give
          reasonable notice by email or in-product. Third-party APIs (including Supabase, Render, GitHub,
          and Stripe) may impose limits or outages outside our control.
        </p>
      </LegalSection>

      <LegalSection heading="7. Termination">
        <p>
          You may stop using the Service and cancel your subscription at any time. We may suspend or close
          accounts that violate these Terms or that create security risk for other customers, with notice
          when practical. When a workspace subscription ends, shared data becomes read-only and is deleted
          after the retention window described in the Privacy Policy.
        </p>
      </LegalSection>

      <LegalSection heading="8. Disclaimers and liability">
        <p>
          The Service is provided &quot;as is&quot; without warranties of any kind except those that cannot
          be excluded by law. To the maximum extent permitted by law, our total liability arising out of or
          relating to the Service is limited to the amount you paid us in the twelve months before the
          claim. Nothing in these Terms limits liability that cannot be limited under applicable law.
        </p>
      </LegalSection>

      <LegalSection heading="9. Governing law">
        <p>
          These Terms are governed by the laws of the country or state in which {site.legalEntity} is
          established, without regard to conflict-of-law rules. Mandatory consumer protections in your
          country of residence still apply where relevant.
        </p>
      </LegalSection>

      <LegalSection heading="10. Contact">
        <p>
          Questions about these Terms: <a href={`mailto:${site.supportEmail}`}>{site.supportEmail}</a>.
        </p>
      </LegalSection>
    </LegalShell>
  );
}
