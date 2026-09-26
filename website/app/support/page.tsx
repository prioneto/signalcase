import type { Metadata } from "next";
import { LegalSection, LegalShell } from "@/components/legal";
import { site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Support — Signalcase",
  description: "Get help with Signalcase: GitHub issues, in-app feedback, and common questions.",
};

export default function SupportPage() {
  return (
    <LegalShell eyebrow="SUPPORT" title="Get help" updated="August 22, 2026">
      <p>
        Signalcase is self-hosted open source, so support runs through the{" "}
        <a href={site.issuesURL} target="_blank" rel="noreferrer">GitHub issue tracker</a> — no support
        inbox, and every answer is public so the next person with the same problem finds it. Bug reports
        with a case reference or screenshot get fixed sooner.
      </p>

      <LegalSection heading="In the app">
        <ul>
          <li><strong>Send Feedback…</strong> (app menu or Settings) — reports a bug, asks a question, or requests a feature to whoever runs your Signalcase server, optionally attaching app version details.</li>
          <li><strong>Settings → Activity &amp; data</strong> — shows recent sync activity per source, which usually explains whether data reached Signalcase.</li>
        </ul>
      </LegalSection>

      <LegalSection heading="Common questions">
        <dl>
          <dt>Is it really free?</dt>
          <dd>Yes. Signalcase is open source under AGPL-3.0: build the app, run your own server, and use it with your whole team — no payment, no card, no ads.</dd>
          <dt>Sync finds nothing</dt>
          <dd>Check that the source is connected in Settings → Connections, that the time window covers the failure, and that provider retention still holds the events.</dd>
          <dt>Authorization fails with 403</dt>
          <dd>Disconnect and reconnect the source so the requested read-only scopes are granted again.</dd>
          <dt>Cases don&apos;t sync between Macs</dt>
          <dd>Make sure both Macs are signed in with the same GitHub account and have selected the same project in Settings → General.</dd>
        </dl>
      </LegalSection>

      <LegalSection heading="Security issues">
        <p>
          Found a security problem? Use GitHub&apos;s private security report (the{" "}
          <strong>Security</strong> tab of the repository) instead of opening a public issue. We take
          reports seriously and will credit responsible disclosures if you want.
        </p>
      </LegalSection>
    </LegalShell>
  );
}
