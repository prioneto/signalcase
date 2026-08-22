import type { Metadata } from "next";
import { LegalSection, LegalShell } from "@/components/legal";
import { site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Support — Signalcase",
  description: "Get help with Signalcase: email, in-app feedback, and status.",
};

export default function SupportPage() {
  return (
    <LegalShell eyebrow="SUPPORT" title="Get help" updated="August 22, 2026">
      <p>
        The fastest way to reach a human is <a href={`mailto:${site.supportEmail}`}>{site.supportEmail}</a>.
        We reply within two business days, usually faster. Bug reports with a case reference or screenshot
        get fixed sooner.
      </p>

      <LegalSection heading="In the app">
        <ul>
          <li><strong>Send Feedback…</strong> (app menu or Settings) — reports a bug, asks a question, or requests a feature straight to us, optionally attaching app version details.</li>
          <li><strong>Settings → Activity &amp; data</strong> — shows recent sync activity per source, which usually explains whether data reached Signalcase.</li>
        </ul>
      </LegalSection>

      <LegalSection heading="Common questions">
        <dl>
          <dt>Sync finds nothing</dt>
          <dd>Check that the source is connected in Settings → Connections, that the time window covers the failure, and that provider retention still holds the events.</dd>
          <dt>Authorization fails with 403</dt>
          <dd>Disconnect and reconnect the source so the requested read-only scopes are granted again.</dd>
          <dt>Billing questions</dt>
          <dd>Owners can manage the subscription under Settings → Billing; see also our refunds page.</dd>
        </dl>
      </LegalSection>

      <LegalSection heading="Security issues">
        <p>
          Found a security problem? Email{" "}
          <a href={`mailto:${site.privacyEmail}`}>{site.privacyEmail}</a> with details instead of opening a
          public issue. We take reports seriously and will credit responsible disclosures if you want.
        </p>
      </LegalSection>
    </LegalShell>
  );
}
