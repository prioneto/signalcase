"use client";

import { useEffect, useRef, useState } from "react";
import { BrandMark } from "@/components/brand-mark";
import { site } from "@/lib/site";

type Source = "SB" | "RD" | "APP" | "GH";
type AppWindow = "signalcase" | "workflow" | "sources" | "about";
type AppIconName = "signalcase" | "workflow" | "sources" | "about" | "source";
type CaseFilter = "ALL" | "NEW" | "ACTIVE";

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

const sourceName: Record<Source, string> = { SB: "Supabase", RD: "Render", APP: "Application", GH: "GitHub" };
const downloadHref = process.env.NEXT_PUBLIC_MAC_DOWNLOAD_URL || site.repoURL;
const downloadLabel = process.env.NEXT_PUBLIC_MAC_DOWNLOAD_URL ? "Download" : "GitHub";

export default function Home() {
  const [activeWindow, setActiveWindow] = useState<AppWindow | null>("signalcase");
  const [selectedID, setSelectedID] = useState(cases[0].id);
  const [maximized, setMaximized] = useState(false);
  const [minimized, setMinimized] = useState(false);
  const [noticeOpen, setNoticeOpen] = useState(true);
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
    setMinimized(false);
  };

  return (
    <main
      className="os-desktop"
      onPointerMove={(event) => {
        event.currentTarget.style.setProperty("--pointer-x", `${event.clientX}px`);
        event.currentTarget.style.setProperty("--pointer-y", `${event.clientY}px`);
      }}
    >
      <h1 className="sr-only">Signalcase — free, open-source bug evidence for macOS</h1>

      <header className="os-menu-bar">
        <button className="os-menu-brand" onClick={() => openWindow("signalcase")} aria-label="Open Signalcase">
          <span className="os-menu-mark"><BrandMark /></span>
          <strong>Signalcase</strong>
        </button>
        <nav className="os-menu-links" aria-label="Application menu">
          <button onClick={() => openWindow("about")}>About</button>
          <button onClick={() => openWindow("workflow")}>Workflow</button>
          <button onClick={() => openWindow("sources")}>Sources</button>
        </nav>
        <div className="os-status">
          <span className="os-live"><i /> SYSTEMS ONLINE</span>
          <span className="os-status-icon" aria-hidden="true">◒</span>
          <span className="os-clock">{clock}</span>
          <a className="os-menu-cta" href={site.repoURL} target="_blank" rel="noreferrer"><GitHubMark />GitHub</a>
        </div>
      </header>

      <div className="os-wallpaper" aria-hidden="true">
        <span className="wallpaper-ring ring-a" />
        <span className="wallpaper-ring ring-b" />
        <BrandMark className="wallpaper-signal" />
        <p>EVERY TRACE<br />ONE CASE</p>
      </div>

      <aside className="desktop-shortcuts" aria-label="Desktop applications">
        <DesktopShortcut label="Signalcase" icon="signalcase" tone="lime" onOpen={() => openWindow("signalcase")} />
        <DesktopShortcut label="Workflow" icon="workflow" tone="blue" onOpen={() => openWindow("workflow")} />
        <DesktopShortcut label="Sources" icon="sources" tone="purple" onOpen={() => openWindow("sources")} />
        <a className="desktop-shortcut" href={downloadHref} target={downloadHref.startsWith("http") ? "_blank" : undefined} rel="noreferrer">
          <span className="desktop-icon icon-orange"><AppGlyph name="source" /></span>
          <span>{downloadLabel}</span>
        </a>
      </aside>

      {noticeOpen && (
        <aside className="os-notice" aria-label="Introduction">
          <span className="os-notice-icon"><BrandMark /></span>
          <div>
            <div className="os-notice-meta"><b>SIGNALCASE</b><span>now</span></div>
            <strong>Free and open source for macOS</strong>
            <p>Turns logs from Supabase, Render, GitHub, and your app into evidence-backed bug cases. Self&#8209;hosted, no AI account needed.</p>
            <div className="os-notice-actions">
              <a href={site.repoURL} target="_blank" rel="noreferrer">View on GitHub</a>
              <button onClick={() => { setNoticeOpen(false); openWindow("workflow"); }}>How it works</button>
            </div>
          </div>
          <button className="os-notice-close" onClick={() => setNoticeOpen(false)} aria-label="Dismiss notification">×</button>
        </aside>
      )}

      <section className={`os-stage ${maximized ? "is-maximized" : ""} ${minimized ? "is-minimized" : ""}`} aria-live="polite">
        {activeWindow === "signalcase" && (
          <WindowFrame title="Signalcase — fitref" onClose={() => setActiveWindow(null)} onMinimize={() => setMinimized(true)} onZoom={() => setMaximized((value) => !value)}>
            <ProductApp selected={selected} selectedID={selectedID} onSelect={setSelectedID} onOpenAbout={() => openWindow("about")} />
          </WindowFrame>
        )}
        {activeWindow === "workflow" && (
          <WindowFrame title="Workflow" onClose={() => setActiveWindow(null)} onMinimize={() => setMinimized(true)} onZoom={() => setMaximized((value) => !value)} compact>
            <InfoWindow eyebrow="01 / WORKFLOW" title="From noisy services to one usable case." intro="Signalcase keeps the few events that prove what happened and turns them into a handoff your developer can use.">
              <div className="os-step-grid">
                <InfoCard number="01" icon="⌁" title="Collect" text="Read recent deploys, errors, database events, and failed CI runs from your stack." />
                <InfoCard number="02" icon="⌘" title="Connect" text="Match request IDs, releases, users, fingerprints, and timestamps across services." />
                <InfoCard number="03" icon="↗" title="Hand off" text="Give the developer a compact timeline, relevant code, impact, and a repeatable test." />
              </div>
            </InfoWindow>
          </WindowFrame>
        )}
        {activeWindow === "sources" && (
          <WindowFrame title="Connected Sources" onClose={() => setActiveWindow(null)} onMinimize={() => setMinimized(true)} onZoom={() => setMaximized((value) => !value)} compact>
            <InfoWindow eyebrow="02 / SOURCES" title="One failure. Every trace." intro="Start with read-only connections. Signalcase brings the evidence together without asking your team to live in another dashboard.">
              <div className="os-source-grid">
                <SourceCard source="SB" title="Supabase" text="Auth, Postgres, RLS, Storage and Edge Functions." />
                <SourceCard source="RD" title="Render" text="Deploys, restarts, workers and service logs." />
                <SourceCard source="APP" title="Application" text="Errors, routes, releases, users and request IDs." />
                <SourceCard source="GH" title="GitHub" text="Failed Actions runs with branch, commit and actor." />
              </div>
            </InfoWindow>
          </WindowFrame>
        )}
        {activeWindow === "about" && (
          <WindowFrame title="About Signalcase" onClose={() => setActiveWindow(null)} onMinimize={() => setMinimized(true)} onZoom={() => setMaximized((value) => !value)} compact>
            <div className="about-window">
              <div className="about-mark"><BrandMark /></div>
              <span className="about-version">SIGNALCASE · MACOS 14+</span>
              <h2>Your logs already know <em>what broke.</em></h2>
              <p>Signalcase connects the events around a failure and hands developers one compact, reproducible case—without searching separate dashboards.</p>
              <div className="about-actions">
                <button className="os-primary" onClick={() => openWindow("signalcase")}>Launch the demo <span>→</span></button>
                <a className="os-secondary" href={downloadHref} target={downloadHref.startsWith("http") ? "_blank" : undefined} rel="noreferrer">{downloadLabel === "Download" ? "Download for Mac" : "Build from source"}</a>
              </div>
              <div className="about-proof"><span>NO AI ACCOUNT</span><i /><span>READ-ONLY CONNECTIONS</span><i /><span>FREE &amp; OPEN SOURCE</span></div>
            </div>
          </WindowFrame>
        )}
      </section>

      <nav className="os-dock" aria-label="Dock">
        <DockButton label="Signalcase" icon="signalcase" tone="lime" active={activeWindow === "signalcase"} minimized={minimized && activeWindow === "signalcase"} onOpen={() => openWindow("signalcase")} />
        <DockButton label="Workflow" icon="workflow" tone="blue" active={activeWindow === "workflow"} minimized={minimized && activeWindow === "workflow"} onOpen={() => openWindow("workflow")} />
        <DockButton label="Sources" icon="sources" tone="purple" active={activeWindow === "sources"} minimized={minimized && activeWindow === "sources"} onOpen={() => openWindow("sources")} />
        <span className="dock-divider" />
        <DockButton label="About" icon="about" tone="dark" active={activeWindow === "about"} minimized={minimized && activeWindow === "about"} onOpen={() => openWindow("about")} />
        <a className="dock-button" data-label={downloadLabel} href={downloadHref} aria-label={downloadLabel === "Download" ? "Download Signalcase" : "Open Signalcase on GitHub"} target={downloadHref.startsWith("http") ? "_blank" : undefined} rel="noreferrer">
          <span className="dock-icon icon-orange"><AppGlyph name="source" /></span>
        </a>
      </nav>
    </main>
  );
}

function WindowFrame({ title, children, onClose, onMinimize, onZoom, compact = false }: { title: string; children: React.ReactNode; onClose: () => void; onMinimize: () => void; onZoom: () => void; compact?: boolean }) {
  return (
    <div className={`os-window ${compact ? "os-window-compact" : ""}`} role="dialog" aria-label={title}>
      <div className="os-titlebar" onDoubleClick={onZoom} title="Double-click to zoom">
        <div className="os-traffic" onDoubleClick={(event) => event.stopPropagation()}>
          <button className="traffic-close" onClick={onClose} aria-label="Close window" />
          <button className="traffic-min" onClick={onMinimize} aria-label="Minimize window" />
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
  const [filter, setFilter] = useState<CaseFilter>("ALL");
  const [query, setQuery] = useState("");
  const [syncState, setSyncState] = useState<"idle" | "syncing" | "done">("idle");
  const [copied, setCopied] = useState(false);
  const searchRef = useRef<HTMLInputElement>(null);
  const filteredCases = cases.filter((item) => {
    const matchesFilter = filter === "ALL" || item.status === filter;
    const search = query.trim().toLowerCase();
    return matchesFilter && (!search || `${item.id} ${item.title} ${item.summary}`.toLowerCase().includes(search));
  });

  useEffect(() => {
    const handleShortcut = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        searchRef.current?.focus();
      }
    };
    window.addEventListener("keydown", handleShortcut);
    return () => window.removeEventListener("keydown", handleShortcut);
  }, []);

  useEffect(() => {
    if (filteredCases.length > 0 && !filteredCases.some((item) => item.id === selectedID)) {
      onSelect(filteredCases[0].id);
    }
  }, [filter, query, selectedID]);

  useEffect(() => {
    if (syncState !== "syncing") return;
    const timer = window.setTimeout(() => setSyncState("done"), 1100);
    return () => window.clearTimeout(timer);
  }, [syncState]);

  useEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(false), 1800);
    return () => window.clearTimeout(timer);
  }, [copied]);

  const selectFilter = (nextFilter: CaseFilter) => {
    setFilter(nextFilter);
    const next = cases.find((item) => nextFilter === "ALL" || item.status === nextFilter);
    if (next) onSelect(next.id);
  };

  const copyPacket = async () => {
    const packet = [
      `${selected.id} — ${selected.title}`,
      `${selected.severity} · ${selected.status}`,
      selected.summary,
      `Impact: ${selected.occurrences} occurrences · ${selected.users} users`,
      `Relevant code: ${selected.code}`,
    ].join("\n");
    try {
      await navigator.clipboard.writeText(packet);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  };

  return (
    <div className="demo-app">
      <aside className="demo-sidebar">
        <div className="demo-brand"><b><BrandMark /></b><span>SIGNALCASE</span></div>
        <button className={`sync-button ${syncState}`} onClick={() => setSyncState("syncing")} disabled={syncState === "syncing"}>
          <span>{syncState === "done" ? "✓" : "↻"}</span>
          {syncState === "syncing" ? "Syncing sources…" : syncState === "done" ? "Logs up to date" : "Sync recent logs"}
        </button>
        <small>INBOX</small>
        <button className={`demo-nav ${filter === "ALL" ? "active" : ""}`} onClick={() => selectFilter("ALL")} aria-pressed={filter === "ALL"}><span>All cases</span><b>{cases.length}</b></button>
        <button className={`demo-nav ${filter === "NEW" ? "active" : ""}`} onClick={() => selectFilter("NEW")} aria-pressed={filter === "NEW"}><span>New</span><b>{cases.filter((item) => item.status === "NEW").length}</b></button>
        <button className={`demo-nav ${filter === "ACTIVE" ? "active" : ""}`} onClick={() => selectFilter("ACTIVE")} aria-pressed={filter === "ACTIVE"}><span>Active</span><b>{cases.filter((item) => item.status === "ACTIVE").length}</b></button>
        <div className="sidebar-bottom">
          <small>PROJECT</small>
          <div className="project-switcher"><span>▰</span><div><b>fitref</b><p>3 connected sources</p></div></div>
          <button className="about-link" onClick={onOpenAbout}>What is Signalcase? <span>↗</span></button>
        </div>
      </aside>

      <section className="demo-cases">
        <header><div><h2>Grouped problems</h2><p>{filteredCases.length} {filteredCases.length === 1 ? "case" : "cases"} from connected logs</p></div><span className="status-light" /></header>
        <label className="demo-search">
          <span aria-hidden="true">⌕</span>
          <input ref={searchRef} value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search cases…" aria-label="Search cases" />
          {query ? <button onClick={() => setQuery("")} aria-label="Clear search">×</button> : <kbd>⌘ K</kbd>}
        </label>
        <div className="demo-case-rows">
          {filteredCases.map((item) => (
            <button className={`demo-case ${selectedID === item.id ? "selected" : ""}`} key={item.id} onClick={() => onSelect(item.id)}>
              <div className="demo-case-meta"><span>{item.id}</span><time>{item.occurrences}×</time></div>
              <h3>{item.title}</h3>
              <div className="demo-case-foot"><b>{item.status}</b><span>{item.users} USERS</span><SourcePills sources={item.sources} /></div>
            </button>
          ))}
          {filteredCases.length === 0 && <div className="demo-empty"><span>⌕</span><b>No matching cases</b><button onClick={() => { setQuery(""); setFilter("ALL"); }}>Clear filters</button></div>}
        </div>
      </section>

      <section className="demo-detail">
        <header className="demo-detail-top"><div><span>{selected.id}</span><i /><b>{selected.status}</b></div><button className={copied ? "copied" : ""} onClick={copyPacket}>{copied ? "✓ Copied" : "Copy packet"}</button></header>
        <div className="demo-detail-body" key={selected.id}>
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
        </div>
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

function DesktopShortcut({ label, icon, tone, onOpen }: { label: string; icon: AppIconName; tone: string; onOpen: () => void }) {
  return <button className="desktop-shortcut" onDoubleClick={onOpen} onClick={onOpen}><span className={`desktop-icon icon-${tone}`}><AppGlyph name={icon} /></span><span>{label}</span></button>;
}

function DockButton({ label, icon, tone, active, minimized, onOpen }: { label: string; icon: AppIconName; tone: string; active: boolean; minimized: boolean; onOpen: () => void }) {
  return <button className={`dock-button ${active ? "active" : ""} ${minimized ? "minimized" : ""}`} data-label={label} onClick={onOpen} aria-label={`Open ${label}`}><span className={`dock-icon icon-${tone}`}><AppGlyph name={icon} /></span></button>;
}

function AppGlyph({ name }: { name: AppIconName }) {
  if (name === "signalcase") {
    return <BrandMark className="app-glyph app-glyph-full" />;
  }

  if (name === "workflow") {
    return <svg className="app-glyph" viewBox="0 0 32 32" fill="none" aria-hidden="true"><path d="M8 23.5 23.5 8M13.5 7.5h10.8v10.8" stroke="currentColor" strokeWidth="3.4" strokeLinecap="round" strokeLinejoin="round" /><circle cx="8" cy="23.5" r="2.4" fill="currentColor" /></svg>;
  }

  if (name === "sources") {
    return <svg className="app-glyph" viewBox="0 0 32 32" fill="none" aria-hidden="true"><path d="m10.2 11.4 5.8 4.2 5.8-4.2M16 15.6v7" stroke="currentColor" strokeWidth="2.7" strokeLinecap="round" /><circle cx="9" cy="10.5" r="3.2" fill="currentColor" /><circle cx="23" cy="10.5" r="3.2" fill="currentColor" /><circle cx="16" cy="24" r="3.2" fill="currentColor" /></svg>;
  }

  if (name === "about") {
    return <svg className="app-glyph" viewBox="0 0 32 32" fill="none" aria-hidden="true"><circle cx="16" cy="16" r="10.5" stroke="currentColor" strokeWidth="2.4" /><circle cx="16" cy="11" r="1.7" fill="currentColor" /><path d="M16 15v7" stroke="currentColor" strokeWidth="2.8" strokeLinecap="round" /></svg>;
  }

  return <svg className="app-glyph" viewBox="0 0 32 32" fill="none" aria-hidden="true"><path d="m11 9-6 7 6 7M21 9l6 7-6 7M18.5 6.5l-5 19" stroke="currentColor" strokeWidth="2.7" strokeLinecap="round" strokeLinejoin="round" /></svg>;
}

function GitHubMark() {
  return <svg className="github-glyph" viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z" /></svg>;
}

function SourceBadge({ source }: { source: Source }) {
  return <span className={`source-badge source-${source.toLowerCase()}`}>{source}</span>;
}

function SourcePills({ sources }: { sources: Source[] }) {
  return <span className="source-pills">{sources.map((source) => <SourceBadge key={source} source={source} />)}</span>;
}
