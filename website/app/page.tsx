"use client";

import { useEffect, useState } from "react";

type Source = "SB" | "RD" | "APP";
type AppWindow = "signalcase" | "workflow" | "sources" | "about";

type ProductCase = {
  id: string;
  title: string;
  status: "NEW" | "ACTIVE";
  severity: "CRITICAL" | "HIGH";
  occurrences: number;
  users: number;
  sources: Source[];
  summary: string;
  findings: { tone: "good" | "bad" | "warn"; title: string; body: string }[];
  events: { time: string; source: Source; title: string; detail: string }[];
  code: string;
};

const cases: ProductCase[] = [
  {
    id: "SIG-104",
    title: "Profile writes fail after the latest deploy",
    status: "NEW",
    severity: "CRITICAL",
    occurrences: 12,
    users: 7,
    sources: ["RD", "APP", "SB"],
    summary: "The release reaches production, then Supabase rejects profile writes with a missing customer ID.",
    findings: [
      { tone: "good", title: "Deployment completed", body: "Render marked release 9f3a1b live before the first failure." },
      { tone: "bad", title: "Database write failed", body: "Supabase rejected a null customer_id in every matching request." },
      { tone: "warn", title: "Started after deploy 9f3a1b", body: "The first failure appeared seven minutes after release." },
    ],
    events: [
      { time: "14:28:04", source: "RD", title: "Deploy 9f3a1b became live", detail: "fitref-web · production" },
      { time: "14:35:22", source: "APP", title: "ProfileWriteError", detail: "Missing customer ID · req_91d" },
      { time: "14:35:24", source: "SB", title: "Profile update rejected", detail: "23502 · null customer_id" },
    ],
    code: "app/api/profile/route.ts:184",
  },
  {
    id: "SIG-103",
    title: "Nightly import exceeds the request timeout",
    status: "ACTIVE",
    severity: "HIGH",
    occurrences: 8,
    users: 8,
    sources: ["RD", "SB"],
    summary: "A Render worker times out while Supabase is processing the same large import query.",
    findings: [
      { tone: "good", title: "Worker starts normally", body: "Render starts the scheduled job with the expected release." },
      { tone: "bad", title: "Query runs too long", body: "Supabase records the statement until the worker timeout is reached." },
      { tone: "warn", title: "The failure repeats nightly", body: "Three scheduled runs share the same fingerprint." },
    ],
    events: [
      { time: "02:00:00", source: "RD", title: "Scheduled import started", detail: "analytics-worker · release 28cc04" },
      { time: "02:00:17", source: "SB", title: "Import query still running", detail: "statement exceeded 15 seconds" },
      { time: "02:00:30", source: "RD", title: "Worker request timed out", detail: "Job exceeded its 30-second limit" },
    ],
    code: "workers/nightly-import.ts:96",
  },
  {
    id: "SIG-101",
    title: "Profile reads are denied after team invitations",
    status: "ACTIVE",
    severity: "HIGH",
    occurrences: 31,
    users: 14,
    sources: ["SB", "RD"],
    summary: "Invited members authenticate, but their first profile request is rejected by RLS.",
    findings: [
      { tone: "good", title: "Authentication works", body: "Every affected request follows a successful login." },
      { tone: "bad", title: "RLS rejects members", body: "Owners succeed while role=member receives SQLSTATE 42501." },
      { tone: "warn", title: "API returns the same error", body: "Render records a 403 for each rejected request." },
    ],
    events: [
      { time: "09:17:21", source: "SB", title: "Auth login succeeded", detail: "email provider · usr_101" },
      { time: "09:17:23", source: "SB", title: "RLS policy denied profile read", detail: "42501 · permission denied" },
      { time: "09:17:24", source: "RD", title: "GET /api/profile returned 403", detail: "14 affected users" },
    ],
    code: "supabase/migrations/team_profile_policy.sql:23",
  },
];

const sourceName: Record<Source, string> = { SB: "Supabase", RD: "Render", APP: "Application" };
const downloadHref = process.env.NEXT_PUBLIC_MAC_DOWNLOAD_URL || "/sign-in";

export default function Home() {
  const [activeWindow, setActiveWindow] = useState<AppWindow | null>("signalcase");
  const [selectedID, setSelectedID] = useState(cases[0].id);
  const [maximized, setMaximized] = useState(false);
  const [clock, setClock] = useState("MON · 12:05");
  const selected = cases.find((item) => item.id === selectedID) ?? cases[0];

  useEffect(() => {
    const updateClock = () => {
      const now = new Date();
      const day = now.toLocaleDateString("en", { weekday: "short" }).toUpperCase();
      const time = now.toLocaleTimeString("en", { hour: "2-digit", minute: "2-digit", hour12: false });
      setClock(`${day} · ${time}`);
    };
    updateClock();
    const timer = window.setInterval(updateClock, 30_000);
    return () => window.clearInterval(timer);
  }, []);

  const openWindow = (app: AppWindow) => {
    setActiveWindow(app);
    setMaximized(false);
  };

  return (
    <main className="os-desktop">
      <h1 className="sr-only">Signalcase — Native bug evidence for small teams</h1>

      <header className="os-menu-bar">
        <button className="os-menu-brand" onClick={() => openWindow("signalcase")} aria-label="Open Signalcase">
          <span className="os-menu-mark">⌁</span>
          <strong>Signalcase</strong>
        </button>
        <nav className="os-menu-links" aria-label="Application menu">
          <button onClick={() => openWindow("about")}>About</button>
          <button onClick={() => openWindow("workflow")}>Workflow</button>
          <button onClick={() => openWindow("sources")}>Sources</button>
        </nav>
        <div className="os-status">
          <span className="os-live"><i /> SYSTEMS ONLINE</span>
          <span aria-hidden="true">◒</span>
          <span>{clock}</span>
        </div>
      </header>

      <div className="os-wallpaper" aria-hidden="true">
        <span className="wallpaper-ring ring-a" />
        <span className="wallpaper-ring ring-b" />
        <span className="wallpaper-signal">⌁</span>
        <p>EVERY TRACE<br />ONE CASE</p>
      </div>

      <aside className="desktop-shortcuts" aria-label="Desktop applications">
        <DesktopShortcut label="Signalcase" icon="⌁" tone="lime" onOpen={() => openWindow("signalcase")} />
        <DesktopShortcut label="Workflow" icon="↗" tone="blue" onOpen={() => openWindow("workflow")} />
        <DesktopShortcut label="Sources" icon="⌘" tone="purple" onOpen={() => openWindow("sources")} />
        <a className="desktop-shortcut" href={downloadHref}>
          <span className="desktop-icon icon-orange">↓</span>
          <span>Download</span>
        </a>
      </aside>

      <section className={`os-stage ${maximized ? "is-maximized" : ""}`} aria-live="polite">
        {activeWindow === "signalcase" && (
          <WindowFrame title="Signalcase — fitref" onClose={() => setActiveWindow(null)} onZoom={() => setMaximized((value) => !value)}>
            <ProductApp selected={selected} selectedID={selectedID} onSelect={setSelectedID} onOpenAbout={() => openWindow("about")} />
          </WindowFrame>
        )}
        {activeWindow === "workflow" && (
          <WindowFrame title="Workflow" onClose={() => setActiveWindow(null)} onZoom={() => setMaximized((value) => !value)} compact>
            <InfoWindow eyebrow="01 / WORKFLOW" title="From noisy services to one usable case." intro="Signalcase keeps the few events that prove what happened and turns them into a handoff your developer can use.">
              <div className="os-step-grid">
                <InfoCard number="01" icon="⌁" title="Collect" text="Read recent deploys, errors, database events, and webhook deliveries from your stack." />
                <InfoCard number="02" icon="⌘" title="Connect" text="Match request IDs, releases, users, fingerprints, and timestamps across services." />
                <InfoCard number="03" icon="↗" title="Hand off" text="Give the developer a compact timeline, relevant code, impact, and a repeatable test." />
              </div>
            </InfoWindow>
          </WindowFrame>
        )}
        {activeWindow === "sources" && (
          <WindowFrame title="Connected Sources" onClose={() => setActiveWindow(null)} onZoom={() => setMaximized((value) => !value)} compact>
            <InfoWindow eyebrow="02 / SOURCES" title="One failure. Every trace." intro="Start with read-only connections. Signalcase brings the evidence together without asking your team to live in another dashboard.">
              <div className="os-source-grid">
                <SourceCard source="SB" title="Supabase" text="Auth, Postgres, RLS, Storage and Edge Functions." />
                <SourceCard source="RD" title="Render" text="Deploys, restarts, workers and service logs." />
                <SourceCard source="APP" title="Application" text="Errors, routes, releases, users and request IDs." />
              </div>
            </InfoWindow>
          </WindowFrame>
        )}
        {activeWindow === "about" && (
          <WindowFrame title="About Signalcase" onClose={() => setActiveWindow(null)} onZoom={() => setMaximized((value) => !value)} compact>
            <div className="about-window">
              <div className="about-mark">⌁</div>
              <span className="about-version">SIGNALCASE · MACOS</span>
              <h2>Your logs already know <em>what broke.</em></h2>
              <p>Signalcase connects the events around a failure and hands developers one compact, reproducible case—without searching separate dashboards.</p>
              <div className="about-actions">
                <button className="os-primary" onClick={() => openWindow("signalcase")}>Launch the demo <span>→</span></button>
                <a className="os-secondary" href={downloadHref}>Download for macOS</a>
              </div>
              <div className="about-proof"><span>NO REQUIRED AI</span><i /><span>READ-ONLY CONNECTIONS</span><i /><span>FREE FOR SMALL TEAMS</span></div>
            </div>
          </WindowFrame>
        )}
      </section>

      <nav className="os-dock" aria-label="Dock">
        <DockButton label="Signalcase" icon="⌁" tone="lime" active={activeWindow === "signalcase"} onOpen={() => openWindow("signalcase")} />
        <DockButton label="Workflow" icon="↗" tone="blue" active={activeWindow === "workflow"} onOpen={() => openWindow("workflow")} />
        <DockButton label="Sources" icon="⌘" tone="purple" active={activeWindow === "sources"} onOpen={() => openWindow("sources")} />
        <span className="dock-divider" />
        <DockButton label="About" icon="i" tone="dark" active={activeWindow === "about"} onOpen={() => openWindow("about")} />
        <a className="dock-button" href={downloadHref} aria-label="Download Signalcase" title="Download">
          <span className="dock-icon icon-orange">↓</span>
        </a>
      </nav>
    </main>
  );
}

function WindowFrame({ title, children, onClose, onZoom, compact = false }: { title: string; children: React.ReactNode; onClose: () => void; onZoom: () => void; compact?: boolean }) {
  return (
    <div className={`os-window ${compact ? "os-window-compact" : ""}`} role="dialog" aria-label={title}>
      <div className="os-titlebar">
        <div className="os-traffic">
          <button className="traffic-close" onClick={onClose} aria-label="Close window" />
          <button className="traffic-min" onClick={onClose} aria-label="Minimize window" />
          <button className="traffic-zoom" onClick={onZoom} aria-label="Zoom window" />
        </div>
        <strong>{title}</strong>
        <span className="titlebar-state"><i /> LIVE</span>
      </div>
      <div className="os-window-content">{children}</div>
      <span className="window-resize" aria-hidden="true" />
    </div>
  );
}

function ProductApp({ selected, selectedID, onSelect, onOpenAbout }: { selected: ProductCase; selectedID: string; onSelect: (id: string) => void; onOpenAbout: () => void }) {
  return (
    <div className="demo-app">
      <aside className="demo-sidebar">
        <div className="demo-brand"><b>⌁</b><span>SIGNALCASE</span></div>
        <button className="sync-button"><span>⌁</span> Sync recent logs</button>
        <small>INBOX</small>
        <button className="demo-nav active"><span>All cases</span><b>{cases.length}</b></button>
        <button className="demo-nav"><span>New</span><b>1</b></button>
        <button className="demo-nav"><span>Active</span><b>2</b></button>
        <div className="sidebar-bottom">
          <small>PROJECT</small>
          <div className="project-switcher"><span>▰</span><div><b>fitref</b><p>3 connected sources</p></div></div>
          <button className="about-link" onClick={onOpenAbout}>What is Signalcase? <span>↗</span></button>
        </div>
      </aside>

      <section className="demo-cases">
        <header><div><h2>Grouped problems</h2><p>{cases.length} cases from connected logs</p></div><span className="status-light" /></header>
        <div className="demo-search">⌕ <span>Search cases…</span><kbd>⌘ K</kbd></div>
        <div className="demo-case-rows">
          {cases.map((item) => (
            <button className={`demo-case ${selectedID === item.id ? "selected" : ""}`} key={item.id} onClick={() => onSelect(item.id)}>
              <div className="demo-case-meta"><span>{item.id}</span><time>{item.occurrences}×</time></div>
              <h3>{item.title}</h3>
              <div className="demo-case-foot"><b>{item.status}</b><span>{item.users} USERS</span><SourcePills sources={item.sources} /></div>
            </button>
          ))}
        </div>
      </section>

      <section className="demo-detail">
        <header className="demo-detail-top"><div><span>{selected.id}</span><i /><b>{selected.status}</b></div><button>Copy packet</button></header>
        <div className="demo-detail-title">
          <small>{selected.severity} · PRODUCTION</small>
          <h2>{selected.title}</h2>
          <p>{selected.summary}</p>
        </div>
        <div className="demo-impact">
          <div><small>OCCURRENCES</small><b>{selected.occurrences}</b></div>
          <div><small>AFFECTED USERS</small><b>{selected.users}</b></div>
          <div><small>SOURCES</small><SourcePills sources={selected.sources} /></div>
        </div>
        <div className="demo-section-heading"><div><small>PROVEN FROM THE LOGS</small><p>No guesses. Every finding links to an event.</p></div><span>RULE-BASED</span></div>
        <div className="demo-findings">
          {selected.findings.map((finding, index) => (
            <div className="demo-finding" key={finding.title}>
              <b className={finding.tone}>{String(index + 1).padStart(2, "0")}</b>
              <div><h3>{finding.title}</h3><p>{finding.body}</p></div>
              <span className={finding.tone}>{finding.tone === "good" ? "✓" : finding.tone === "bad" ? "!" : "◷"}</span>
            </div>
          ))}
        </div>
        <div className="demo-section-heading timeline-title"><div><small>UNIFIED TIMELINE</small></div><span>{selected.events.length} RELATED EVENTS</span></div>
        <div className="demo-timeline">
          {selected.events.map((event) => (
            <div className="demo-event" key={`${event.time}-${event.title}`}>
              <time>{event.time}</time><SourceBadge source={event.source} /><div><h3>{event.title}</h3><p>{event.detail}</p></div><small>{sourceName[event.source]}</small>
            </div>
          ))}
        </div>
        <div className="demo-code"><small>RELEVANT CODE</small><code>{selected.code}</code></div>
      </section>
    </div>
  );
}

function InfoWindow({ eyebrow, title, intro, children }: { eyebrow: string; title: string; intro: string; children: React.ReactNode }) {
  return <div className="info-window"><span>{eyebrow}</span><h2>{title}</h2><p>{intro}</p>{children}</div>;
}

function InfoCard({ number, icon, title, text }: { number: string; icon: string; title: string; text: string }) {
  return <article className="os-info-card"><span>{number}</span><i>{icon}</i><h3>{title}</h3><p>{text}</p></article>;
}

function SourceCard({ source, title, text }: { source: Source; title: string; text: string }) {
  return <article className="os-source-card"><SourceBadge source={source} /><div><h3>{title}</h3><p>{text}</p></div><span>↗</span></article>;
}

function DesktopShortcut({ label, icon, tone, onOpen }: { label: string; icon: string; tone: string; onOpen: () => void }) {
  return <button className="desktop-shortcut" onDoubleClick={onOpen} onClick={onOpen}><span className={`desktop-icon icon-${tone}`}>{icon}</span><span>{label}</span></button>;
}

function DockButton({ label, icon, tone, active, onOpen }: { label: string; icon: string; tone: string; active: boolean; onOpen: () => void }) {
  return <button className={`dock-button ${active ? "active" : ""}`} onClick={onOpen} aria-label={`Open ${label}`} title={label}><span className={`dock-icon icon-${tone}`}>{icon}</span></button>;
}

function SourceBadge({ source }: { source: Source }) {
  return <span className={`source-badge source-${source.toLowerCase()}`}>{source}</span>;
}

function SourcePills({ sources }: { sources: Source[] }) {
  return <span className="source-pills">{sources.map((source) => <SourceBadge key={source} source={source} />)}</span>;
}
