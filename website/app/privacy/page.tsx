import type { Metadata } from "next";
import { LegalSection, LegalShell } from "@/components/legal";
import { site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Privacy Policy — Signalcase",
  description: "What Signalcase collects, why, and how long it is kept.",
};

export default function PrivacyPage() {
  return (
    <LegalShell eyebrow="LEGAL" title="Privacy Policy" updated="August 22, 2026">
      <p>
        This policy explains what {site.legalEntity} collects when you use the Signalcase macOS app and
        website, why we collect it, and how long we keep it. The short version: Signalcase reads only the
        log sources you connect, stores the minimum needed to run your workspace, and never sells data.
      </p>

      <LegalSection heading="1. What we collect">
        <ul>
          <li><strong>Account:</strong> your GitHub-linked email and user identifier when you sign in.</li>
          <li><strong>Connected sources:</strong> OAuth tokens for Supabase and a GitHub App installation you approve. Tokens are encrypted at rest on our servers and used only for the read-only scopes shown during connection. Render credentials stay in your Mac&apos;s Keychain unless you choose to use another supported flow.</li>
          <li><strong>Log events:</strong> the events retrieved from sources you connect (or send to an Application Logs endpoint), including timestamps, messages, request IDs, and technical context such as release versions.</li>
          <li><strong>Cases:</strong> the grouped cases, statuses, and notes your team creates.</li>
          <li><strong>Billing:</strong> subscription state handled by Stripe. We never see or store full card numbers.</li>
          <li><strong>Diagnostics:</strong> optional error reports from the app and server, containing an error message, short stack trace, and version information. They never include your logs or provider credentials.</li>
          <li><strong>Feedback:</strong> what you voluntarily type into the feedback form, plus the app details you choose to include.</li>
        </ul>
      </LegalSection>

      <LegalSection heading="2. Why we process it">
        <p>
          To provide the Service you signed up for (authenticating you, syncing cases between your Macs,
          reading connected sources), to bill subscriptions, to keep the Service secure and reliable
          (rate limits, abuse prevention, error monitoring), and to answer support requests. These purposes
          correspond to performance of a contract, legitimate interests in operating a secure service, and —
          where required, such as for optional diagnostics — your consent.
        </p>
      </LegalSection>

      <LegalSection heading="3. Retention">
        <p>
          Log events are kept for 30 days per workspace by default and then deleted automatically. Cases
          are kept until your team deletes them or the workspace ends. Error reports and billing records
          are kept for up to 90 days (billing records as long as required by tax law). Deleting a project,
          leaving a workspace, or deleting your account removes associated data; deletion requests are
          honored within 30 days.
        </p>
      </LegalSection>

      <LegalSection heading="4. Subprocessors">
        <ul>
          <li><strong>Supabase</strong> — database, authentication, and storage of workspace data.</li>
          <li><strong>Vercel</strong> — hosting of the Signalcase server and website.</li>
          <li><strong>Stripe</strong> — subscription payments and customer portal.</li>
          <li><strong>GitHub</strong> — sign-in identity and repository evidence you connect.</li>
        </ul>
        <p>We do not sell personal data and do not share it with advertisers.</p>
      </LegalSection>

      <LegalSection heading="5. Your rights">
        <p>
          Where GDPR, UK GDPR, or similar laws apply, you can request access, correction, export, or
          erasure of your personal data, and object to or restrict certain processing. Workspace owners can
          delete projects and members directly in the app; for anything else, email{" "}
          <a href={`mailto:${site.privacyEmail}`}>{site.privacyEmail}</a>. California residents have
          equivalent rights to know, delete, and opt out of any &quot;sale&quot; (we do not sell data).
        </p>
      </LegalSection>

      <LegalSection heading="6. Security">
        <p>
          Provider tokens are encrypted before storage and are only decrypted server-side to fulfill syncs.
          Traffic uses HTTPS. Access to production data is limited, credential tables are not reachable by
          client applications, and secrets are redacted from stored event payloads where they are detected.
        </p>
      </LegalSection>

      <LegalSection heading="7. Changes and contact">
        <p>
          If this policy changes materially, we will note the new date above and notify signed-in users in
          the app for significant changes. Questions: <a href={`mailto:${site.privacyEmail}`}>{site.privacyEmail}</a>.
        </p>
      </LegalSection>
    </LegalShell>
  );
}
