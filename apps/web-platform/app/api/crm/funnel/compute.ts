// Pure count-based funnel computation for GET /api/crm/funnel
// (feat-beta-crm-ui #6172). Kept OUT of route.ts because Next.js route files may
// export only HTTP handlers (cq-nextjs-route-files-http-only-exports); this
// sibling module holds the testable pure function + its types.
//
// COUNTS/TIMINGS ONLY — never receives or returns note bodies or contact PII
// beyond stage counts (AC4).

import { FUNNEL_STAGES } from "@/lib/crm/stage-probability";

// Below this prior-stage count a conversion % is statistically meaningless at
// beta volume — render "insufficient data" instead. prev===3 still shows (3<3
// is false), matching the approved wireframe.
export const LOW_N_THRESHOLD = 3;

const MS_PER_DAY = 86_400_000;

// The linear funnel (closed_lost is a terminal branch) — single source in
// stage-probability.ts (review P3-1).
export { FUNNEL_STAGES };

export type ContactRow = { id: string; stage: string; created_at: string };
export type TransitionRow = {
  contact_id: string;
  from_stage: string | null;
  to_stage: string;
  entered_at: string;
};

export type FunnelStage = {
  stage: string;
  reached: number;
  conversionPct: number | null;
};
export type PerTransition = { from: string; to: string; avgDays: number | null };

export type FunnelResult = {
  stages: FunnelStage[];
  closedLost: number;
  avgTimeInStageDays: number | null;
  perTransition: PerTransition[];
};

export function computeFunnel(
  contacts: ContactRow[],
  transitions: TransitionRow[],
): FunnelResult {
  const funnelIndex = new Map<string, number>(
    FUNNEL_STAGES.map((s, i) => [s, i] as [string, number]),
  );

  // First-entry timestamp per (contact, stage): 'new' anchors on created_at;
  // every other stage anchors on the EARLIEST transition into it (a regression
  // re-entry must not overwrite the first-reached time).
  const enteredAt = new Map<string, Map<string, number>>();
  const seed = (cid: string) => {
    let m = enteredAt.get(cid);
    if (!m) {
      m = new Map();
      enteredAt.set(cid, m);
    }
    return m;
  };

  for (const c of contacts) {
    seed(c.id).set("new", Date.parse(c.created_at));
  }
  for (const t of transitions) {
    if (!funnelIndex.has(t.to_stage)) continue; // ignore closed_lost transitions
    const m = seed(t.contact_id);
    const ts = Date.parse(t.entered_at);
    const prior = m.get(t.to_stage);
    if (prior === undefined || ts < prior) m.set(t.to_stage, ts);
  }

  // Also mark the CURRENT stage as occupied even if it produced no transition
  // (defensive; normally a non-'new' current stage has a transition row).
  for (const c of contacts) {
    if (funnelIndex.has(c.stage) && !seed(c.id).has(c.stage)) {
      seed(c.id).set(c.stage, Date.parse(c.created_at));
    }
  }

  // reached[stage] = # contacts whose max occupied funnel depth >= stage depth.
  const reached = new Array(FUNNEL_STAGES.length).fill(0);
  for (const c of contacts) {
    const occ = enteredAt.get(c.id);
    if (!occ) continue;
    let maxDepth = -1;
    for (const stage of occ.keys()) {
      const idx = funnelIndex.get(stage);
      if (idx !== undefined && idx > maxDepth) maxDepth = idx;
    }
    for (let i = 0; i <= maxDepth; i++) reached[i]++;
  }

  const stages: FunnelStage[] = FUNNEL_STAGES.map((stage, i) => {
    let conversionPct: number | null = null;
    if (i > 0) {
      const prev = reached[i - 1];
      conversionPct =
        prev < LOW_N_THRESHOLD ? null : Math.round((reached[i] / prev) * 100);
    }
    return { stage, reached: reached[i], conversionPct };
  });

  // Per-hop velocity (adjacent funnel stages only). duration = enteredAt(to) -
  // enteredAt(from), counted only when both are present and the hop is forward.
  const allDurations: number[] = [];
  const perTransition: PerTransition[] = [];
  for (let i = 0; i < FUNNEL_STAGES.length - 1; i++) {
    const from = FUNNEL_STAGES[i];
    const to = FUNNEL_STAGES[i + 1];
    const durations: number[] = [];
    for (const occ of enteredAt.values()) {
      const a = occ.get(from);
      const b = occ.get(to);
      if (a === undefined || b === undefined || b < a) continue;
      const days = (b - a) / MS_PER_DAY;
      durations.push(days);
      allDurations.push(days);
    }
    perTransition.push({
      from,
      to,
      avgDays: durations.length ? round1(mean(durations)) : null,
    });
  }

  return {
    stages,
    closedLost: contacts.filter((c) => c.stage === "closed_lost").length,
    avgTimeInStageDays: allDurations.length ? round1(mean(allDurations)) : null,
    perTransition,
  };
}

function mean(xs: number[]): number {
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}
function round1(x: number): number {
  return Math.round(x * 10) / 10;
}
