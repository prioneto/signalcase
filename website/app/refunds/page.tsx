import type { Metadata } from "next";
import { LegalSection, LegalShell } from "@/components/legal";
import { site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Refunds and cancellation — Signalcase",
  description: "How to cancel Signalcase and when refunds apply.",
};

export default function RefundsPage() {
  return (
    <LegalShell eyebrow="BILLING" title="Refunds & Cancellation" updated="August 22, 2026">
      <LegalSection heading="Cancelling your subscription">
        <p>
          You can cancel at any time. Open the app&apos;s <strong>Settings → Billing</strong> and choose
          &quot;Manage subscription&quot;, or ask us and we will do it for you. Cancelling stops all future
          charges; your workspace stays on the paid plan until the end of the period you already paid for,
          then moves to a limited read-only state.
        </p>
      </LegalSection>

      <LegalSection heading="Free trial">
        <p>
          Every new workspace starts with a 14-day free trial with full functionality. No card is required,
          so nothing is charged when the trial ends unless you explicitly subscribed.
        </p>
      </LegalSection>

      <LegalSection heading="Refund policy">
        <ul>
          <li><strong>First payment:</strong> if Signalcase is not working for your team, tell us within 14 days of your first charge and we will refund it in full — no forms, no interrogation.</li>
          <li><strong>Renewal payments:</strong> tell us within 7 days of an accidental renewal and we will refund it, provided the plan was not used substantially in that period.</li>
          <li><strong>Service failure:</strong> if a sustained outage (over 24 consecutive hours) prevents you from using a paid plan in a billing month, you can request a credit or refund of that month.</li>
          <li><strong>Chargebacks:</strong> please contact us before disputing a charge; we can usually resolve billing issues faster than a card dispute.</li>
        </ul>
        <p>
          Approved refunds are issued by Stripe to the original payment method and typically appear within
          5–10 business days.
        </p>
      </LegalSection>

      <LegalSection heading="How to request a refund">
        <p>
          Email <a href={`mailto:${site.supportEmail}`}>{site.supportEmail}</a> from any email address on
          the workspace (or include the workspace name) with the words &quot;refund request&quot; in the
          subject. We reply within two business days.
        </p>
      </LegalSection>

      <LegalSection heading="Statutory rights">
        <p>
          Nothing here limits consumer rights you have under the law of your country of residence, including
          EU/UK distance-selling rules where they apply.
        </p>
      </LegalSection>
    </LegalShell>
  );
}
