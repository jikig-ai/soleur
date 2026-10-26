import type { ReactNode } from "react";
import { ArrowLeft, Ban, Check, Info, Lock, Minus, TriangleAlert } from "lucide-react";
import { NavLink } from "@/components/ui/nav-link";
import { EgressAuditRefreshButton } from "@/components/settings/egress-audit-refresh-button";
import type { EgressAuditResult } from "@/server/egress-audit-read";
import {
  formatAbsolute,
  formatAgo,
  outcomeOf,
  type DecisionFilter,
  type EgressAuditPayload,
  type Outcome,
} from "@/lib/egress-audit/summary";

// #9545 PR2 — the egress audit destination view (wireframes 07-04..07-25). Presentational: the loader's
// tagged result is the only input, so the whole state ladder is a pure function of it.
//
// Copy rules (CLO, spec FR4): counts are minimums ("at least N"), the list is best-effort and entries
// may be missing, it is visible to every current member including activity from before they joined, no
// member or session is recorded, records are deleted about 30 days after they were recorded. Never the
// words "complete", "every connection", "tamper-proof" or "sessions", and never a calendar date in a
// retention sentence (rows expire individually; no stored date exists).

const BASE = "/dashboard/settings/scope-grants/egress-audit";
const PRIVACY_RIGHTS_URL = "https://soleur.ai/pages/legal/privacy-policy.html#data-subject-rights";
const FILTERS: { key: DecisionFilter; label: string }[] = [
  { key: "all", label: "All" },
  { key: "allowed", label: "Allowed" },
  { key: "blocked", label: "Blocked" },
  { key: "other", label: "Other" },
];
const hrefFor = (f: DecisionFilter) => (f === "all" ? BASE : `${BASE}?decision=${f}`);
const nf = (n: number) => n.toLocaleString("en-US");

const OUTCOME_STYLE: Record<Outcome, { text: string; Icon: typeof Check }> = {
  Allowed: { text: "text-emerald-400", Icon: Check },
  Blocked: { text: "text-red-400", Icon: Ban },
  Other: { text: "text-soleur-text-secondary", Icon: Minus },
};

function OutcomeLabel({ decision }: { decision: string }) {
  const o = outcomeOf(decision);
  const { text, Icon } = OUTCOME_STYLE[o];
  return (
    <span className={`inline-flex items-center gap-1.5 text-xs font-medium ${text}`}>
      <Icon aria-hidden="true" className="h-3 w-3" />
      {o}
    </span>
  );
}

function Notice({ icon, lead, body, tone = "default" }: { icon: ReactNode; lead: string; body: ReactNode; tone?: "default" | "gold" }) {
  return (
    <div
      className={`flex gap-2.5 rounded-none border bg-soleur-bg-surface-2 p-3 ${
        tone === "gold" ? "border-soleur-accent-gold-fg" : "border-soleur-border-default"
      }`}
    >
      <span className="mt-0.5 shrink-0 text-soleur-accent-gold-fg">{icon}</span>
      <div className="flex min-w-0 flex-col gap-1">
        <span className="text-xs font-semibold text-soleur-text-primary">{lead}</span>
        <span className="text-xs text-soleur-text-secondary">{body}</span>
      </div>
    </div>
  );
}

function StateCard({
  icon,
  title,
  body,
  action,
  alert = false,
  danger = false,
}: {
  icon: ReactNode;
  title: string;
  body: ReactNode;
  action?: ReactNode;
  alert?: boolean;
  danger?: boolean;
}) {
  return (
    <div
      role={alert ? "alert" : undefined}
      className={`flex flex-col items-center gap-3 rounded-none border bg-soleur-bg-surface-1 p-8 text-center ${
        danger ? "border-red-400" : "border-soleur-border-default"
      }`}
    >
      <span aria-hidden="true" className={danger ? "text-red-400" : "text-soleur-text-muted"}>
        {icon}
      </span>
      <p className="text-[15px] font-semibold text-soleur-text-primary">{title}</p>
      <p className="text-sm text-soleur-text-secondary">{body}</p>
      {action}
    </div>
  );
}

function Banner() {
  return (
    <Notice
      icon={<Info aria-hidden="true" className="h-3.5 w-3.5" />}
      lead="A best-effort summary, not a full record."
      body="Some requests may be missing and counts are minimums. Every current member of this workspace can see this list, including activity from before they joined. No member or session is recorded. Records are deleted about 30 days after they were recorded."
    />
  );
}

function Chips({ filter }: { filter: DecisionFilter }) {
  return (
    <div className="flex flex-col gap-2">
      <nav aria-label="Filter by outcome" className="flex">
        {FILTERS.map((f) => {
          const selected = f.key === filter;
          return (
            <NavLink
              key={f.key}
              href={hrefFor(f.key)}
              aria-current={selected ? "page" : undefined}
              className={`border px-4 py-1.5 text-xs transition-colors ${
                selected
                  ? "border-soleur-accent-gold-fg bg-soleur-bg-surface-2 font-semibold text-soleur-text-primary"
                  : "border-soleur-border-default font-medium text-soleur-text-muted hover:bg-soleur-bg-surface-2"
              }`}
            >
              {f.label}
            </NavLink>
          );
        })}
      </nav>
      <p className="text-[11px] text-soleur-text-muted">
        Other: the request was neither completed as allowed nor blocked by policy, for example because the destination returned an error.
      </p>
    </div>
  );
}

function TimeText({ iso, now }: { iso: string; now: number }) {
  return (
    <time dateTime={iso} title={formatAbsolute(iso)}>
      {formatAgo(iso, now)}
    </time>
  );
}

function HostTable({ data, now }: { data: EgressAuditPayload; now: number }) {
  return (
    <table className="w-full border border-soleur-border-default bg-soleur-bg-surface-1 text-left text-[13px]">
      <caption className="sr-only">Hosts your workspace's agents contacted in the last 30 days, with outcome and a minimum request count</caption>
      <thead className="hidden bg-soleur-bg-surface-2 text-[11px] font-medium uppercase tracking-wide text-soleur-text-muted md:table-header-group">
        <tr>
          <th scope="col" className="px-3.5 py-2.5 font-medium">Host</th>
          <th scope="col" className="w-28 px-3.5 py-2.5 font-medium">Outcome</th>
          <th scope="col" className="w-36 px-3.5 py-2.5 text-right font-medium">Requests (minimum)</th>
          <th scope="col" className="w-36 px-3.5 py-2.5 text-right font-medium">Last seen</th>
        </tr>
      </thead>
      <tbody>
        {data.rows.map((r) => (
          <tr
            key={`${r.host}|${r.decision}`}
            className="block border-t border-soleur-border-default px-3.5 py-3 md:table-row md:px-0 md:py-0"
          >
            <th scope="row" className="block break-all px-0 font-medium text-soleur-text-primary md:table-cell md:px-3.5 md:py-3" title={r.host}>
              {r.host}
            </th>
            <td className="mt-1.5 inline-block md:mt-0 md:table-cell md:px-3.5 md:py-3">
              <OutcomeLabel decision={r.decision} />
            </td>
            <td className="ml-3 inline-block text-xs text-soleur-text-muted md:ml-0 md:table-cell md:px-3.5 md:py-3 md:text-right md:text-[13px] md:text-soleur-text-primary">
              {`at least ${nf(r.request_count)}`}
            </td>
            <td className="ml-3 inline-block text-xs text-soleur-text-muted md:ml-0 md:table-cell md:px-3.5 md:py-3 md:text-right md:text-[13px] md:text-soleur-text-secondary">
              <TimeText iso={r.last_seen} now={now} />
            </td>
          </tr>
        ))}
        {data.overflow.map((o) => (
          <tr
            key={`overflow|${o.decision}`}
            className="block border-t border-soleur-border-default px-3.5 py-3 md:table-row md:px-0 md:py-0"
          >
            <th scope="row" className="block px-0 font-normal text-soleur-text-secondary md:table-cell md:px-3.5 md:py-3">
              <span className="inline-flex items-center gap-1.5">
                Other hosts, not listed individually
                <span
                  tabIndex={0}
                  role="img"
                  aria-label="Counts are minimums and may be lower than actual activity."
                  title="Counts are minimums and may be lower than actual activity."
                  className="inline-flex text-soleur-text-muted"
                >
                  <Info aria-hidden="true" className="h-3 w-3" />
                </span>
              </span>
            </th>
            <td className="mt-1.5 inline-block md:mt-0 md:table-cell md:px-3.5 md:py-3">
              <OutcomeLabel decision={o.decision} />
            </td>
            <td className="ml-3 inline-block text-xs text-soleur-text-muted md:ml-0 md:table-cell md:px-3.5 md:py-3 md:text-right md:text-[13px] md:text-soleur-text-primary">
              {`at least ${nf(o.request_count)}`}
            </td>
            <td className="ml-3 inline-block text-xs text-soleur-text-muted md:ml-0 md:table-cell md:px-3.5 md:py-3 md:text-right md:text-[13px] md:text-soleur-text-secondary">
              <TimeText iso={o.last_seen} now={now} />
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function Header({ workspaceName }: { workspaceName: string | null }) {
  return (
    <>
      <NavLink href="/dashboard/settings/scope-grants" className="inline-flex w-fit items-center gap-1.5 text-xs font-medium text-soleur-accent-gold-fg">
        <ArrowLeft aria-hidden="true" className="h-3 w-3" />
        Scope Grants
      </NavLink>
      <header className="flex flex-col gap-2.5">
        <h1 className="text-2xl font-medium text-soleur-text-primary">Egress audit log</h1>
        <p className="text-sm text-soleur-text-secondary">
          {`Sites ${workspaceName ? `${workspaceName}'s` : "your workspace's"} agents contacted in about the last 30 days, with the outcome of each (best-effort).`}
        </p>
      </header>
    </>
  );
}

function Footer() {
  return (
    <p className="text-xs text-soleur-text-muted">
      History can't be deleted from this page.{" "}
      <a href={PRIVACY_RIGHTS_URL} className="font-medium text-soleur-accent-gold-fg">
        How to request erasure
      </a>
    </p>
  );
}

function UnavailableCard() {
  return (
    <StateCard
      alert
      danger
      icon={<TriangleAlert className="h-6 w-6" />}
      title="Couldn't load the egress audit log."
      body="This is a loading error, not an empty log. Nothing has been deleted. Try again, and contact support if it keeps failing."
      action={<EgressAuditRefreshButton label="Try again" />}
    />
  );
}

export function EgressAuditView({ result, filter, now = Date.now() }: { result: EgressAuditResult; filter: DecisionFilter; now?: number }) {
  const shell = (children: ReactNode, workspaceName: string | null = null) => (
    <div className="flex max-w-[760px] flex-col gap-5">
      <Header workspaceName={workspaceName} />
      {children}
      <Footer />
    </div>
  );

  if (result.kind === "forbidden") {
    return shell(
      <StateCard
        icon={<Lock className="h-6 w-6" />}
        title="You no longer have access to this workspace."
        body="Ask a workspace owner to add you again, or switch workspace."
        action={
          <NavLink href="/dashboard" className="border border-soleur-border-default px-4 py-2 text-xs font-medium text-soleur-text-primary">
            Switch workspace
          </NavLink>
        }
        alert
      />,
    );
  }
  if (result.kind === "unbound") {
    return shell(
      <StateCard
        icon={<Lock className="h-6 w-6" />}
        title="We couldn't determine your workspace."
        body="Pick a workspace and try again."
        action={
          <NavLink href="/dashboard" className="border border-soleur-border-default px-4 py-2 text-xs font-medium text-soleur-text-primary">
            Switch workspace
          </NavLink>
        }
      />,
    );
  }
  if (result.kind === "unavailable") {
    return shell(
      <>
        <Banner />
        <UnavailableCard />
      </>,
    );
  }

  const { data, collection, webAccess, workspaceName } = result;
  const hasData = data.rows.length > 0 || data.overflow.length > 0;
  const filteredLabel = FILTERS.find((f) => f.key === filter)?.label ?? "";
  const total = data.summary.request_count_min ?? 0;
  const blocked = data.summary.blocked_request_count_min ?? 0;

  if (hasData) {
    return shell(
      <>
        <Banner />
        {webAccess === false && (
          <Notice
            icon={<Info aria-hidden="true" className="h-3.5 w-3.5" />}
            lead="Web access is off. Nothing new is recorded."
            body="Records are deleted about 30 days after they were recorded."
          />
        )}
        {data.truncated && (
          <Notice
            tone="gold"
            icon={<Info aria-hidden="true" className="h-3.5 w-3.5" />}
            lead={filter === "all" ? "Showing the 200 most recent entries." : `Showing the 200 most recent ${filteredLabel} entries.`}
            body="Older entries in this 30-day window are not listed, and counts are minimums."
          />
        )}
        <p className="text-[13px] font-medium text-soleur-text-primary" aria-live="polite">
          {`At least ${nf(total)} requests · at least ${nf(blocked)} blocked${filter === "all" ? "" : " (all outcomes)"}`}
        </p>
        <Chips filter={filter} />
        <HostTable data={data} now={now} />
      </>,
      workspaceName,
    );
  }

  // No rows. A filter that matches nothing while the window has requests is its own line, not an empty state.
  if (filter !== "all" && total > 0) {
    return shell(
      <>
        <Banner />
        <Chips filter={filter} />
        <div className="flex items-center gap-3 border border-soleur-border-default bg-soleur-bg-surface-2 p-4 text-sm text-soleur-text-secondary">
          <span>{`No ${filteredLabel} requests in the last 30 days.`}</span>
          <NavLink href={BASE} className="font-medium text-soleur-accent-gold-fg">
            Show all
          </NavLink>
        </div>
      </>,
      workspaceName,
    );
  }

  if (collection === false) {
    return shell(
      <StateCard
        icon={<Info className="h-6 w-6" />}
        title="Recording isn't on for this workspace."
        body="Nothing is listed because recording hasn't started, not because agents made no requests. When it starts, the sites agents contact appear here."
      />,
      workspaceName,
    );
  }
  if (collection === "unknown" || webAccess === null) {
    return shell(
      <>
        <Banner />
        <UnavailableCard />
      </>,
      workspaceName,
    );
  }
  if (webAccess === false) {
    return shell(
      <>
        <Banner />
        <StateCard
          icon={<Info className="h-6 w-6" />}
          title="Nothing recorded in the last 30 days"
          body="Web access is off, so nothing new is recorded. Records are deleted about 30 days after they were recorded."
        />
      </>,
      workspaceName,
    );
  }
  return shell(
    <>
      <Banner />
      <StateCard
        icon={<Info className="h-6 w-6" />}
        title="No requests recorded yet"
        body="Nothing has been recorded yet. Requests can take a few minutes to appear."
        action={<EgressAuditRefreshButton label="Refresh" />}
      />
    </>,
    workspaceName,
  );
}
