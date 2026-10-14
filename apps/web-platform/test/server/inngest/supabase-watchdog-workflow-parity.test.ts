// 2026-09-28 — #9168: workflow-contract parity for the Supabase hang watchdog.
//
// `.github/workflows/scheduled-supabase-watchdog.yml` is the bounded
// auto-restart executor: it probes the Management API health endpoint,
// corroborates against app `/health`, runs the extracted classifier
// (scripts/supabase-watchdog-classify.sh — the single chokepoint for the
// verdict) and writes a prod restart ONLY behind `vars.WATCHDOG_ARMED == '1'`
// (dark-launch) and the sentinel-comment ledger. This suite pins the parts of
// the contract a review-by-eye would miss: trigger set, mutex, permissions,
// the armed gate, the sentinel literal and the audit label.
//
// Deliberately a NEW file (not folded into sentry-monitor-iac-parity.test.ts):
// that file walks the whole heartbeat cohort; this one pins THIS workflow's
// write-path contract.
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { parse as parseYaml } from "yaml";

const WORKFLOW = resolve(
  __dirname,
  "../../../../../.github/workflows/scheduled-supabase-watchdog.yml",
);

interface WorkflowDoc {
  on?: Record<string, unknown>;
  concurrency?: { group?: unknown; "cancel-in-progress"?: unknown };
  permissions?: Record<string, unknown>;
  jobs?: Record<string, { steps?: { id?: string; if?: string; uses?: string; name?: string }[] }>;
}

function doc(): WorkflowDoc {
  return parseYaml(readFileSync(WORKFLOW, "utf-8")) as WorkflowDoc;
}

function src(): string {
  return readFileSync(WORKFLOW, "utf-8");
}

describe("scheduled-supabase-watchdog workflow contract (#9168)", () => {
  it("triggers are exactly {schedule, workflow_dispatch} — schedule is the documented fallback (ADR-248)", () => {
    const on = doc().on ?? {};
    expect(Object.keys(on).sort()).toEqual(["schedule", "workflow_dispatch"]);
    const schedule = (on.schedule ?? []) as Array<{ cron?: string }>;
    expect(schedule.map((s) => s.cron)).toEqual(["*/5 * * * *"]);
  });

  it("serializes runs on the supabase-watchdog concurrency group (the restart mutex)", () => {
    const conc = doc().concurrency;
    expect(conc?.group).toBe("supabase-watchdog");
    // cancel-in-progress: false — a queued second run must wait, never cancel
    // the in-flight probe window (double-restart guard).
    expect(conc?.["cancel-in-progress"]).toBe(false);
  });

  it("permissions are contents:read + issues:write and NOTHING else", () => {
    const perms = doc().permissions ?? {};
    expect(perms.contents).toBe("read");
    expect(perms.issues).toBe("write");
    // No actions: write (it dispatches no workflows) and no contents:write —
    // the restart credential is the Supabase PAT in secrets, never github.token.
    expect(Object.keys(perms).sort()).toEqual(["contents", "issues"]);
  });

  it("invokes the extracted classifier as the single verdict chokepoint", () => {
    expect(src()).toContain("scripts/supabase-watchdog-classify.sh");
  });

  it("gates the restart write on vars.WATCHDOG_ARMED (dark-launch detect-only)", () => {
    expect(src()).toContain("vars.WATCHDOG_ARMED");
  });

  it("carries the restart sentinel-comment literal (the attempt ledger)", () => {
    // Written AT the restart POST, never on confirmed 2xx; an absent/unparseable
    // sentinel on a claimed-restart run fails closed.
    expect(src()).toContain("<!-- watchdog:restart epoch=");
  });

  it("files the audit issue under the supabase-auto-restart label", () => {
    expect(src()).toContain("supabase-auto-restart");
  });

  it("double-keys the audit-issue lookup on label AND title, requiring uniqueness", () => {
    // gh issue list is newest-first — without the title filter + the >1
    // fail-closed arm, labeling a NEWER issue would silently re-base the
    // sentinel ledger to attempts=0 and reset the cooldown and give-up.
    expect(src()).toContain('contains("watchdog audit")');
    expect(src()).toContain('select(.title | contains("watchdog audit"))]');
  });

  it("reads the sentinel ledger from github-actions[bot] comments only", () => {
    // Without the author filter a public/guest comment could forge sentinels
    // (false give-up/perma-cooldown) or trip corrupt=1 every tick.
    expect(src()).toContain('select(.user.login == "github-actions[bot]")');
  });

  it("writes the sentinel BEFORE the restart POST and the claim label AFTER it", () => {
    // The protocol order is load-bearing: sentinel → POST → label. Within the
    // restart step's run block, the sentinel write must precede the POST and
    // the label must follow it — a reorder silently loses tamper evidence.
    const s = src();
    const step = s.slice(s.indexOf("id: restart"));
    const iSentinel = step.indexOf("watchdog:restart epoch=");
    const iPost = step.indexOf("/v1/projects/${REF}/restart");
    const iLabel = step.indexOf('add-label "watchdog-restart-attempted"');
    expect(iSentinel).toBeGreaterThan(-1);
    expect(iPost).toBeGreaterThan(-1);
    expect(iLabel).toBeGreaterThan(-1);
    expect(iSentinel).toBeLessThan(iPost);
    expect(iPost).toBeLessThan(iLabel);
    expect(step).toContain("blocked-ledger-write");
  });

  it("plumbs the REAL probe verdict into --decide (not a re-asserted literal)", () => {
    // A hardcoded `--verdict hang-signature` would leave the step `if:` as the
    // ONLY signature gate; plumbing the probe output means a loosened `if:`
    // can never turn an ambiguous run into a restart.
    expect(src()).toContain("--verdict \"$VERDICT\"");
    expect(src()).toContain("VERDICT: ${{ steps.probe.outputs.verdict }}");
  });

  it("gates restart-capable steps on hang-signature + a healthy ledger", () => {
    const jobs = doc().jobs as Record<string, { steps?: { id?: string; if?: string }[] }>;
    const steps = (jobs.watchdog?.steps ?? []).filter((s) => s.id);
    const byId = new Map(steps.map((s) => [s.id, s]));
    for (const id of ["ledger", "decide"]) {
      expect(byId.get(id)?.if ?? "").toContain("hang-signature");
      expect(byId.get(id)?.if ?? "").toContain("issue_ok == 'true'");
    }
    expect(byId.get("restart")?.if).toBe(
      "always() && steps.decide.outputs.action == 'restart'",
    );
    expect(byId.get("audit")?.if ?? "").toContain("always()");
  });

  it("fails closed on ledger READ failures, not just corrupt content", () => {
    // `|| true` on the comments/labels reads would make a partial GitHub
    // outage indistinguishable from an empty ledger — silently resetting the
    // cooldown and give-up bounds.
    expect(src()).toContain('COMMENTS_RC=$?');
    expect(src()).toContain('CLAIM_RC=$?');
    expect(src()).toContain('corrupt="1"');
    expect(src()).toContain('EDITED_SENTINELS');
  });

  it("checks into the scheduled-supabase-watchdog Sentry monitor as the terminal step", () => {
    const jobs = doc().jobs ?? {};
    const jobNames = Object.keys(jobs);
    expect(jobNames.length).toBeGreaterThanOrEqual(1);
    // The heartbeat must be the LAST step of its job so every earlier failure
    // path still reports (the #7834 terminality class).
    const hb: { id?: string; if?: string; uses?: string }[] = [];
    for (const job of Object.values(jobs)) {
      for (const step of job.steps ?? []) {
        if ((step.uses ?? "").includes("actions/sentry-heartbeat")) {
          hb.push(step);
          expect(job.steps?.[job.steps.length - 1]).toBe(step);
        }
      }
    }
    expect(hb.length).toBe(1);
    expect(src()).toContain("monitor-slug: scheduled-supabase-watchdog");
  });
});
