"use client";

// PR-G (#3947) — Merged BYOK + Inngest section component. `source` prop
// switches rendering between the two row shapes. Per Code Simplicity +
// DHH review: BYOK and Inngest sections share the same wrapper +
// pagination, so they collapse into one component (cut from 6 files to
// 2 in plan v2).
//
// Phase 6 (Art. 22(3) affordance): each Inngest row inlines a mailto:
// "Request human review →" anchor + a Link to /dashboard/settings/scope-grants
// "Change authorization →" anchor. Per CLO advisory + spec-flow-analyzer
// critical-tier finding. Closed-preview cohort routes through
// legal@jikigai.com email; the inbox + outbound reply is the audit trail.

import Link from "next/link";
import { useEffect, useState } from "react";
import { RedactedEventSummary } from "./redacted-event-summary";

export interface ByokRow {
  ts: string;
  agent_role: string;
  token_count: number;
  unit_cost_cents: number;
}

export interface InngestRunRow {
  id: string;
  startedAt: string | null;
  endedAt: string | null;
  status: string;
  actionClass: string;
  tierAtTimeOfEvent: string | null;
  customerIdMasked: string;
}

interface ByokProps {
  source: "byok";
  rows: ByokRow[];
}

interface InngestProps {
  source: "inngest";
  initialRows?: InngestRunRow[];
}

type Props = ByokProps | InngestProps;

const REQUEST_REVIEW_SUBJECT_PREFIX = "Request human review";

function buildMailto(run: InngestRunRow): string {
  const subject = `${REQUEST_REVIEW_SUBJECT_PREFIX}: ${run.actionClass} (${run.id})`;
  const body =
    "I'd like a human to review this automated action.\n\n" +
    `Run: ${run.id}\n` +
    `Action class: ${run.actionClass}\n` +
    `Tier at time: ${run.tierAtTimeOfEvent ?? "(unspecified)"}\n\n` +
    "[Your perspective]";
  return `mailto:legal@jikigai.com?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}

export function AuditSections(props: Props) {
  if (props.source === "byok") {
    return <ByokSection rows={props.rows} />;
  }
  return <InngestSection initialRows={props.initialRows} />;
}

function ByokSection({ rows }: { rows: ByokRow[] }) {
  return (
    <section
      aria-labelledby="byok-section-header"
      className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1"
    >
      <header className="border-b border-soleur-border-default px-5 py-3">
        <h2 id="byok-section-header" className="font-medium text-soleur-text-primary">
          BYOK invocations
        </h2>
        <p className="mt-1 text-xs text-soleur-text-muted">
          Anthropic SDK calls billed to your BYOK key, paginated 50 per page.
        </p>
      </header>
      {rows.length === 0 ? (
        <p className="px-5 py-6 text-sm text-soleur-text-secondary">
          No BYOK invocations yet. When Soleur runs an action on your behalf,
          it logs token + cost here.
        </p>
      ) : (
        <table className="w-full text-sm">
          <thead className="text-left text-xs uppercase text-soleur-text-muted">
            <tr>
              <th className="px-5 py-2 font-medium">Timestamp</th>
              <th className="px-5 py-2 font-medium">Agent role</th>
              <th className="px-5 py-2 font-medium">Tokens</th>
              <th className="px-5 py-2 font-medium">Cost (¢)</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r, i) => (
              <tr
                key={`${r.ts}-${i}`}
                className="border-t border-soleur-border-default/50"
              >
                <td className="px-5 py-2 text-soleur-text-secondary">
                  {new Date(r.ts).toLocaleString()}
                </td>
                <td className="px-5 py-2 text-soleur-text-primary">{r.agent_role}</td>
                <td className="px-5 py-2 text-soleur-text-secondary">
                  {r.token_count.toLocaleString()}
                </td>
                <td className="px-5 py-2 text-soleur-text-secondary">
                  {r.unit_cost_cents}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  );
}

function InngestSection({ initialRows }: { initialRows?: InngestRunRow[] }) {
  const [runs, setRuns] = useState<InngestRunRow[] | null>(initialRows ?? null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(!initialRows);

  useEffect(() => {
    if (initialRows) return;
    let cancelled = false;
    setLoading(true);
    fetch("/api/dashboard/runs")
      .then(async (res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json() as Promise<{ runs: InngestRunRow[] }>;
      })
      .then((body) => {
        if (cancelled) return;
        setRuns(body.runs);
        setLoading(false);
      })
      .catch((e: unknown) => {
        if (cancelled) return;
        setError(e instanceof Error ? e.message : "fetch failed");
        setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [initialRows]);

  return (
    <section
      aria-labelledby="inngest-section-header"
      className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1"
    >
      <header className="border-b border-soleur-border-default px-5 py-3">
        <h2
          id="inngest-section-header"
          className="font-medium text-soleur-text-primary"
        >
          Automated runs
        </h2>
        <p className="mt-1 text-xs text-soleur-text-muted">
          What Soleur ran while you slept. Capped at 50 most recent.
        </p>
      </header>

      {loading ? (
        <p className="px-5 py-6 text-sm text-soleur-text-muted">Loading…</p>
      ) : error ? (
        <div
          role="alert"
          className="px-5 py-6 text-sm text-soleur-text-danger"
        >
          Couldn&apos;t reach the run history. BYOK section above is
          unaffected. Try refreshing in a moment.
        </div>
      ) : !runs || runs.length === 0 ? (
        <p className="px-5 py-6 text-sm text-soleur-text-secondary">
          No automated runs yet. When a payment-failed event triggers a
          draft, it appears here.
        </p>
      ) : (
        <ul className="divide-y divide-soleur-border-default/50">
          {runs.map((run) => (
            <li key={run.id} className="px-5 py-4">
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0 flex-1">
                  <RedactedEventSummary
                    masked={run.customerIdMasked}
                    eventName={run.actionClass}
                  />
                  <p className="mt-1 text-xs text-soleur-text-muted">
                    {run.startedAt
                      ? new Date(run.startedAt).toLocaleString()
                      : "started: ?"}
                    {" · "}
                    status: {run.status}
                    {run.tierAtTimeOfEvent ? (
                      <>
                        {" · "}
                        tier at time:{" "}
                        <code className="text-soleur-text-secondary">
                          {run.tierAtTimeOfEvent}
                        </code>
                      </>
                    ) : null}
                  </p>
                </div>
              </div>
              <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs">
                <a
                  href={buildMailto(run)}
                  className="text-soleur-gold hover:underline"
                >
                  Request human review →
                </a>
                <Link
                  href="/dashboard/settings/scope-grants"
                  className="text-soleur-text-secondary hover:text-soleur-text-primary hover:underline"
                >
                  Change authorization →
                </Link>
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
