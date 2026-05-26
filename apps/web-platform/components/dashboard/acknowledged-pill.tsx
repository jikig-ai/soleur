// PR-B (#4379) — Acknowledged pill extracted from today-card.tsx so
// LeaderLoopStatus can render it for the state-matrix "done" branch.
// Original pill semantics unchanged from PR-A (#4124).

export interface AcknowledgedPillProps {
  artifactUrl: string;
  degraded: "enqueue_failed" | "no_artifact_in_pr_a" | undefined;
}

export type PillState = "ack" | "pending" | "queued" | "no_artifact";

export function derivePillState(
  artifactUrl: string,
  degraded: AcknowledgedPillProps["degraded"],
): PillState {
  // Pure derivation. Precedence: no_artifact_in_pr_a > enqueue_failed >
  // artifactUrl-present > artifactUrl-absent. Each branch is exclusive.
  if (degraded === "no_artifact_in_pr_a") return "no_artifact";
  if (degraded === "enqueue_failed") return "queued";
  if (artifactUrl) return "ack";
  return "pending";
}

export function AcknowledgedPill({ artifactUrl, degraded }: AcknowledgedPillProps) {
  const state = derivePillState(artifactUrl, degraded);

  if (state === "no_artifact") {
    return (
      <span
        data-testid="acknowledged-pill"
        data-pill-state="no_artifact"
        className="inline-flex items-center gap-2 rounded-full bg-slate-700/40 px-3 py-1 text-xs font-medium text-slate-100"
      >
        Acknowledged — full handling lands in PR-B (#4360)
      </span>
    );
  }
  if (state === "queued") {
    return (
      <span
        data-testid="acknowledged-pill"
        data-pill-state="queued"
        className="inline-flex items-center gap-2 rounded-full bg-amber-700/30 px-3 py-1 text-xs font-medium text-amber-100"
      >
        Acknowledged (queued — retry from a fresh card if no artifact appears within a minute)
      </span>
    );
  }
  if (state === "pending") {
    return (
      <span
        data-testid="acknowledged-pill"
        data-pill-state="pending"
        className="inline-flex items-center gap-2 rounded-full bg-green-700/30 px-3 py-1 text-xs font-medium text-green-100"
      >
        Acknowledged (pending artifact)
      </span>
    );
  }
  return (
    <a
      href={artifactUrl}
      target="_blank"
      rel="noopener noreferrer"
      data-testid="acknowledged-pill"
      data-pill-state="ack"
      className="inline-flex items-center gap-2 rounded-full bg-green-700/30 px-3 py-1 text-xs font-medium text-green-100 hover:bg-green-700/40"
    >
      Acknowledged — View on GitHub
    </a>
  );
}
