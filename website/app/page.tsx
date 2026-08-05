"use client";

import { useState } from "react";

type Source = "SB" | "ST" | "RD" | "RC" | "SN";

type ProductCase = {
  id: string;
  title: string;
  status: string;
  severity: string;
  occurrences: number;
  users: number;
  sources: Source[];
  summary: string;
  findings: { tone: "good" | "bad" | "warn"; title: string; body: string }[];
  events: { time: string; source: Source; title: string; detail: string }[];
  code: string;
};

const productPreviewCases: ProductCase[] = [
  {
    id: "SIG-104",
    title: "Checkout webhook fails after the latest deploy",
    status: "NEW",
    severity: "CRITICAL",
    occurrences: 12,
    users: 7,
    sources: ["RD", "ST", "SB"],
    summary: "Stripe completes the payment, but the webhook fails before Supabase grants access.",
    findings: [
      { tone: "good", title: "Payment succeeded", body: "Stripe completed checkout and emitted evt_731." },
      { tone: "bad", title: "Application processing failed", body: "Supabase rejected a null customer_id and the webhook returned 500." },
      { tone: "warn", title: "Started after deploy 9f3a1b", body: "The first matching failure appeared seven minutes after release." },
    ],
    events: [
      { time: "14:28:04", source: "RD", title: "Deploy 9f3a1b became live", detail: "fitref-web · production" },
      { time: "14:35:22", source: "ST", title: "checkout.session.completed", detail: "€19.99 · evt_731 · req_91d" },
      { time: "14:35:24", source: "SB", title: "Profile update rejected", detail: "23502 · null value in customer_id" },
      { time: "14:35:25", source: "ST", title: "Webhook returned 500", detail: "Endpoint scheduled for retry" },
    ],
    code: "app/api/webhooks/stripe/route.ts:184",
  },
  {
    id: "SIG-103",
    title: "Renewed subscribers are not receiving Pro access",
    status: "TRIAGED",
    severity: "HIGH",
    occurrences: 8,
    users: 8,
    sources: ["RC", "SB"],
    summary: "RevenueCat records a successful renewal, but the Supabase entitlement remains expired.",
    findings: [
      { tone: "good", title: "Renewal is valid", body: "The production event contains the expected Pro entitlement." },
      { tone: "bad", title: "Sync function timed out", body: "All affected users share a five-second Edge Function timeout." },
      { tone: "warn", title: "Event can be retried", body: "The stable event ID has no corresponding successful database write." },
    ],
    events: [
      { time: "11:04:12", source: "RC", title: "RENEWAL", detail: "pro_monthly · usr_844 · rc_evt_54" },
      { time: "11:04:17", source: "SB", title: "Edge Function timed out", detail: "subscription-sync exceeded 5 seconds" },
      { time: "11:04:39", source: "SB", title: "Entitlement remained expired", detail: "profiles.pro_until was not updated" },
    ],
    code: "supabase/functions/revenuecat-webhook/index.ts:96",
  },
  {
    id: "SIG-101",
    title: "Profile reads are denied after team invitations",
    status: "FIXING",
    severity: "HIGH",
    occurrences: 31,
    users: 14,
    sources: ["SB", "SN"],
    summary: "Invited members can authenticate, but their first profile request is rejected by RLS.",
    findings: [
      { tone: "good", title: "Authentication works", body: "Every affected request follows a successful login." },
      { tone: "bad", title: "One RLS policy rejects members", body: "Owners succeed while role=member receives SQLSTATE 42501." },
      { tone: "warn", title: "Fix branch linked", body: "A policy update is ready for local verification." },
    ],
    events: [
      { time: "09:17:21", source: "SB", title: "Auth login succeeded", detail: "email provider · usr_101" },
      { time: "09:17:23", source: "SB", title: "RLS policy denied profile read", detail: "42501 · permission denied" },
      { time: "09:17:24", source: "SN", title: "ProfileBootstrapError", detail: "14 affected users · release 28cc04" },
    ],
    code: "supabase/migrations/team_profile_policy.sql:23",
  },
];

const sourceName: Record<Source, string> = {
  SB: "Supabase",
  ST: "Stripe",
  RD: "Render",
  RC: "RevenueCat",
  SN: "Sentry",
};

export default function Home() {
  const cases = productPreviewCases;
  const [selectedID, setSelectedID] = useState(productPreviewCases[0].id);
  const selected = cases.find((item) => item.id === selectedID) ?? cases[0];

  return (
    <main>
      <nav className="nav shell">
        <a className="brand" href="#top" aria-label="Signalcase home">
          <span className="brand-mark" aria-hidden="true">⌁</span>
          <span>SIGNALCASE</span>
        </a>
        <div className="nav-links">
          <a href="#workflow">Workflow</a>
          <a href="#sources">Sources</a>
          <a href="#preview">Product</a>
        </div>
        <a className="nav-cta" href="#preview">See the product <span>↘</span></a>
      </nav>

      <section className="hero shell" id="top">
        <div className="hero-copy">
          <div className="eyebrow"><span className="live-dot" /> NATIVE BUG EVIDENCE FOR SMALL TEAMS</div>
          <h1>Your logs already know <em>what broke.</em></h1>
          <p>Signalcase connects the events around a failure and hands developers one compact, reproducible case—without searching five dashboards.</p>
          <div className="hero-actions">
            <a className="primary" href="#preview">See Signalcase <span>→</span></a>
            <a className="secondary" href="#workflow">See how it works</a>
          </div>
          <div className="hero-proof">
            <span>NO REQUIRED AI</span><i />
            <span>READ-ONLY CONNECTIONS</span><i />
            <span>MAC NATIVE</span>
          </div>
        </div>

        <div className="signal-orbit" aria-hidden="true">
          <div className="orbit orbit-one" />
          <div className="orbit orbit-two" />
          <div className="center-signal">
            <span className="pulse-line">⌁</span>
            <small>4 EVENTS</small>
            <strong>1 CASE</strong>
          </div>
          <span className="orbit-node node-one source-sb">SB</span>
          <span className="orbit-node node-two source-st">ST</span>
          <span className="orbit-node node-three source-rd">RD</span>
          <span className="orbit-node node-four source-rc">RC</span>
        </div>
      </section>

      <section className="preview-shell shell" id="preview">
        <div className="window-bar">
          <div className="traffic"><span /><span /><span /></div>
          <div className="window-title">Signalcase · fitref</div>
          <span className="capture-small">⌁ Sync recent logs</span>
        </div>
        <div className="product">
          <aside className="product-side">
            <div className="mini-brand"><b>⌁</b><span>SIGNALCASE</span></div>
            <span className="side-capture">＋ Sync logs</span>
            <small>INBOX</small>
            <button className="side-nav active"><span>All cases</span><b>{cases.length}</b></button>
            <button className="side-nav"><span>New</span><b>{cases.filter((item) => item.status === "NEW").length}</b></button>
            <button className="side-nav"><span>Triaged</span><b>{cases.filter((item) => item.status === "TRIAGED").length}</b></button>
            <button className="side-nav"><span>Fixing</span><b>{cases.filter((item) => item.status === "FIXING").length}</b></button>
            <div className="side-bottom">
              <small>PROJECT</small>
              <div className="project-card"><span>▰</span><div><b>fitref</b><p>Source linked</p></div></div>
            </div>
          </aside>

          <section className="case-list">
            <header><div><h3>Grouped problems</h3><p>{cases.length} cases from connected logs</p></div><span className="status-light" /></header>
            <div className="search">⌕ <span>Search errors, IDs, files…</span></div>
            <div className="rows">
              {cases.map((item) => (
                <button className={`case-row ${selected.id === item.id ? "selected" : ""}`} key={item.id} onClick={() => setSelectedID(item.id)}>
                  <div className="case-meta"><span>{item.id}</span><time>{item.occurrences}×</time></div>
                  <h4>{item.title}</h4>
                  <div className="row-bottom"><b>{item.status}</b><span>{item.users} USERS</span><SourcePills sources={item.sources} /></div>
                </button>
              ))}
            </div>
          </section>

          <section className="case-detail">
            <header className="detail-top"><div><span>{selected.id}</span><i /> <b>{selected.status}</b></div><button>Copy packet</button></header>
            <div className="detail-title">
              <small>{selected.severity} · PRODUCTION</small>
              <h2>{selected.title}</h2>
              <p>{selected.summary}</p>
            </div>
            <div className="impact">
              <div><small>OCCURRENCES</small><b>{selected.occurrences}</b></div>
              <div><small>AFFECTED USERS</small><b>{selected.users}</b></div>
              <div><small>SOURCES</small><SourcePills sources={selected.sources} /></div>
            </div>
            <div className="section-heading"><div><small>PROVEN FROM THE LOGS</small><p>No guesses. Every finding links to an event.</p></div><span>RULE-BASED</span></div>
            <div className="findings">
              {selected.findings.map((finding, index) => (
                <div className="finding" key={finding.title}>
                  <b className={finding.tone}>{String(index + 1).padStart(2, "0")}</b>
                  <div><h5>{finding.title}</h5><p>{finding.body}</p></div>
                  <span className={finding.tone}>{finding.tone === "good" ? "✓" : finding.tone === "bad" ? "!" : "◷"}</span>
                </div>
              ))}
            </div>
            <div className="section-heading timeline-heading"><div><small>UNIFIED TIMELINE</small></div><span>{selected.events.length} RELATED EVENTS</span></div>
            <div className="timeline">
              {selected.events.map((event) => (
                <div className="event" key={`${event.time}-${event.title}`}>
                  <time>{event.time}</time><SourceBadge source={event.source} /><div><h5>{event.title}</h5><p>{event.detail}</p></div><small>{sourceName[event.source]}</small>
                </div>
              ))}
            </div>
            <div className="code-line"><small>RELEVANT CODE</small><code>{selected.code}</code></div>
          </section>
        </div>
      </section>

      <section className="workflow shell" id="workflow">
        <div className="section-intro">
          <span>01 / WORKFLOW</span>
          <h2>From noisy services to one usable case.</h2>
          <p>The useful part is not collecting more logs. It is preserving the few events that prove what happened.</p>
        </div>
        <div className="steps">
          <article><span>01</span><div className="step-icon">⌁</div><h3>Collect</h3><p>Read recent events, deploys, errors, and webhook deliveries from the tools already in your stack.</p></article>
          <article><span>02</span><div className="step-icon">⌘</div><h3>Connect</h3><p>Match exact request IDs, event IDs, users, releases, fingerprints, and timestamps.</p></article>
          <article><span>03</span><div className="step-icon">↗</div><h3>Hand off</h3><p>Give the developer a compact timeline, relevant code, impact, and repeatable test—not another dashboard.</p></article>
        </div>
      </section>

      <section className="sources shell" id="sources">
        <div className="source-copy"><span>02 / SOURCES</span><h2>One failure.<br />Every trace.</h2><p>Start with read-only integrations. Add an always-on webhook collector only when the team needs production capture while every Mac is asleep.</p></div>
        <div className="source-grid">
          {[{ code: "SB", name: "Supabase", text: "Auth, Postgres, RLS, Storage and Edge Functions" }, { code: "ST", name: "Stripe", text: "Events, payments and failed webhook deliveries" }, { code: "RD", name: "Render", text: "Deploys, restarts, workers and service logs" }, { code: "RC", name: "RevenueCat", text: "Purchases, renewals, billing and entitlements" }, { code: "SN", name: "Sentry", text: "Exceptions, releases and affected users" }].map((source) => (
            <article key={source.code}><SourceBadge source={source.code as Source} /><div><h3>{source.name}</h3><p>{source.text}</p></div><span>↗</span></article>
          ))}
        </div>
      </section>

      <section className="closing shell">
        <span className="closing-label">BUILT FOR THE BUG BETWEEN DASHBOARDS</span>
        <h2>Stop searching.<br /><em>Start reproducing.</em></h2>
        <a className="primary" href="#sources">See supported sources <span>→</span></a>
      </section>

      <footer className="shell"><div className="brand"><span className="brand-mark">⌁</span><span>SIGNALCASE</span></div><p>Native bug evidence for small development teams.</p><span>MACOS · 2026</span></footer>
    </main>
  );
}

function SourceBadge({ source }: { source: Source }) {
  return <span className={`source-badge source-${source.toLowerCase()}`}>{source}</span>;
}

function SourcePills({ sources }: { sources: Source[] }) {
  return <span className="source-pills">{sources.map((source) => <SourceBadge key={source} source={source} />)}</span>;
}
