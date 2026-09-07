// 2026-06-11 — self-discovering parity guard: every SENTRY_MONITOR_SLUG an
// Inngest cron heartbeats to MUST have a matching sentry_cron_monitor
// resource in infra/sentry/cron-monitors.tf.
//
// Why: Sentry's check-in API silently tolerates unknown monitor slugs, so a
// cron whose monitor was never added to IaC heartbeats into the void — a
// dead cron in that state pages nowhere (missed-check-in detection never
// arms). PR #5133's AC12 verification found 13 of 36 code slugs in exactly
// this state; this guard makes the gap structural-impossible for new crons
// (the same readdirSync pattern as cron-safe-commit-parity.test.ts, per
// learning 2026-06-07-self-discovering-parity-guard-for-cross-producer-drift).
//
// Direction is one-way (code → IaC): the tf file legitimately carries
// monitors with no Inngest slug (GHA-fired workflows like
// scheduled-terraform-drift, host-timer beacons like cron-egress-resolve).

import { readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";

const FUNCTIONS_DIR = resolve(__dirname, "../../../server/inngest/functions");
const MONITORS_TF = resolve(
  __dirname,
  "../../../infra/sentry/cron-monitors.tf",
);
const WORKFLOWS_DIR = resolve(__dirname, "../../../../../.github/workflows");

// Per ADR-033's prefix table, oneshot-* functions must declare NO monitor
// slug (a crontab monitor pages MISSED forever after the single fire).
// The one historical deviation is grandfathered here; new entries require
// the same deliberate decision this list makes visible.
const ONESHOT_SLUG_EXEMPTIONS = new Set(["oneshot-gdpr-gate-50d-eval"]);

// Cron slugs whose sentry_cron_monitor was intentionally REMOVED because the
// cron is DISABLED via a kill-switch (#6031 — the GHCR minter: App installation
// tokens can't pull the private packages, ADR-088 arm-b). The handler keeps its
// SENTRY_MONITOR_SLUG const for easy re-enable, but heartbeats never fire (it
// no-ops under GHCR_MINTER_DISABLED=true), so there is no dropped-check-in risk.
// Remove this exemption when the monitor + cron are restored.
const DISABLED_CRON_SLUG_EXEMPTIONS = new Set(["scheduled-ghcr-token-minter"]);

// Slugs assigned via SENTRY_MONITOR_SLUG consts in cron/event handlers.
// The literal-extraction regex is deliberately narrow (double-quoted
// kebab-case value on the declaration line) — a dynamically-computed slug
// would evade it, but no handler does that and the convention is enforced
// by this file's existence.
const SLUG_RE = /SENTRY_MONITOR_SLUG\s*=\s*"([a-z0-9-]+)"/g;

function nonOneshotFiles(): string[] {
  // Per ADR-033's prefix table, oneshot-* functions get NO Sentry cron
  // monitor — a crontab-scheduled monitor would page MISSED on every
  // period after the single fire. Their errors route via
  // reportSilentFallback instead.
  return readdirSync(FUNCTIONS_DIR).filter(
    (f) => f.endsWith(".ts") && !f.startsWith("oneshot-"),
  );
}

function codeSlugs(): string[] {
  const slugs = new Set<string>();
  for (const file of nonOneshotFiles()) {
    const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
    for (const m of src.matchAll(SLUG_RE)) {
      slugs.add(m[1]);
    }
  }
  return [...slugs].sort();
}

function iacMonitorNames(): Set<string> {
  const tf = readFileSync(MONITORS_TF, "utf-8");
  const names = new Set<string>();
  // cron-monitors.tf carries ONLY sentry_cron_monitor resources (uptime
  // monitors and issue alerts live in sibling files), so a top-level name
  // attr IS a monitor slug — the resource-count pin below enforces that
  // assumption mechanically.
  for (const m of tf.matchAll(/^\s*name\s*=\s*"([a-z0-9-]+)"/gm)) {
    names.add(m[1]);
  }
  return names;
}

function iacResourceCount(): number {
  const tf = readFileSync(MONITORS_TF, "utf-8");
  return [...tf.matchAll(/^resource "sentry_cron_monitor" /gm)].length;
}

// ---------------------------------------------------------------------------
// #6374 — GHA-workflow heartbeat-slug parity. The Inngest-cron guard above is
// one-way (code → IaC). GHA workflows (scheduled-inngest-health, realtime-probe,
// terraform-drift, …) heartbeat to Sentry via the `sentry-heartbeat` action with
// a `monitor-slug:` — and those slugs need a matching sentry_cron_monitor in
// cron-monitors.tf, or Sentry silently drops the check-ins to an unknown slug and
// the heartbeat pages nowhere (the #6374 root cause).
//
// This guard once had a second clause: that the monitor's resource also appear in
// apply-sentry-infra.yml's `-target=` allowlist, since a saved plan built against
// an explicit target set left un-targeted monitors declared-but-never-applied. The
// workflow now plans the sentry root FULL, so `declared ≡ applied` by construction
// and that clause could no longer fail. The slug → monitor clause below is NOT
// covered by that change — Sentry slug matching is exact and a workflow can still
// name a slug no resource declares.
// ---------------------------------------------------------------------------

// Every `monitor-slug: <slug>` used by a .github/workflows/*.yml sentry-heartbeat step.
function workflowHeartbeatSlugs(): string[] {
  const slugs = new Set<string>();
  for (const file of readdirSync(WORKFLOWS_DIR)) {
    if (!file.endsWith(".yml") && !file.endsWith(".yaml")) continue;
    const src = readFileSync(join(WORKFLOWS_DIR, file), "utf-8");
    // Tolerate an optionally-quoted slug + an optional trailing inline comment so a future
    // emitter written `monitor-slug: "foo"` or `monitor-slug: foo  # note` cannot silently
    // drop from the parity set (fail-open) — the exact class this guard exists to prevent.
    for (const m of src.matchAll(/^\s*monitor-slug:\s*"?([a-z0-9-]+)"?\s*(?:#.*)?$/gm)) {
      slugs.add(m[1]);
    }
  }
  return [...slugs].sort();
}

// The set of cron-monitor `name`s (the Sentry slugs) DECLARED in cron-monitors.tf.
// Parsed per-resource (not a whole-file slug grep) so a `name = "..."` appearing in
// a comment or a non-cron-monitor block cannot satisfy a workflow's slug. Only
// membership is ever queried, so this is a Set — it used to be a Map<name,id>
// whose value half was read only by the `-target=` parity check retired in #6589.
function tfDeclaredMonitorSlugs(tf: string): Set<string> {
  const slugs = new Set<string>();
  const re =
    /^resource\s+"sentry_cron_monitor"\s+"[a-z0-9_]+"\s*\{([\s\S]*?)^\}/gm;
  for (const m of tf.matchAll(re)) {
    const nameMatch = m[1].match(/\n\s*name\s*=\s*"([a-z0-9-]+)"/);
    if (nameMatch) slugs.add(nameMatch[1]);
  }
  return slugs;
}

// Pure gap detector. Extracted so the deliberately-broken-fixture test can
// exercise it without mutating the tree.
function workflowSlugGaps(
  slugs: string[],
  tf: string,
): { missingMonitor: string[] } {
  const declared = tfDeclaredMonitorSlugs(tf);
  const missingMonitor = slugs.filter((slug) => !declared.has(slug));
  return { missingMonitor };
}

describe("Sentry GHA-workflow heartbeat-slug parity (#6374)", () => {
  it("discovers the known workflow-heartbeat slug cohort (anti-vacuity)", () => {
    const slugs = workflowHeartbeatSlugs();
    expect(slugs.length).toBeGreaterThanOrEqual(4);
    expect(slugs).toContain("scheduled-inngest-health");
    expect(slugs).toContain("scheduled-realtime-probe");
  });

  it("every workflow heartbeat slug has a cron-monitor in cron-monitors.tf", () => {
    const tf = readFileSync(MONITORS_TF, "utf-8");
    const { missingMonitor } = workflowSlugGaps(workflowHeartbeatSlugs(), tf);
    expect(
      missingMonitor,
      `workflow heartbeat slug(s) with NO sentry_cron_monitor in cron-monitors.tf ` +
        `(Sentry silently drops check-ins to unknown slugs — the error heartbeat ` +
        `pages nowhere): ${missingMonitor.join(", ")}`,
    ).toEqual([]);
  });

  it("a broken fixture (slug missing from cron-monitors.tf) is caught", () => {
    const tf = 'resource "sentry_cron_monitor" "foo" {\n  name = "foo"\n}\n';
    const { missingMonitor } = workflowSlugGaps(["orphan-slug"], tf);
    expect(missingMonitor).toEqual(["orphan-slug"]);
  });

  it("a slug WITH a declared monitor is not reported as a gap (no false positives)", () => {
    const tf = 'resource "sentry_cron_monitor" "bar" {\n  name = "bar-slug"\n}\n';
    const { missingMonitor } = workflowSlugGaps(["bar-slug"], tf);
    expect(missingMonitor).toEqual([]);
  });
});

describe("Sentry cron-monitor IaC parity", () => {
  it("discovers a sane slug universe (anti-vacuity: the extractor must find the known cohort)", () => {
    const slugs = codeSlugs();
    // Floor, not exact count — new crons grow the set. If this fails LOW,
    // the extraction regex broke (a refactor of the const shape), which
    // would otherwise make the parity assertion below vacuously green.
    expect(slugs.length).toBeGreaterThanOrEqual(30);
    expect(slugs).toContain("scheduled-rule-prune");
    expect(slugs).toContain("scheduled-weekly-analytics");
  });

  it("per-producer anti-vacuity: every heartbeating handler yields an extracted slug", () => {
    // The global floor above has slack, so a SINGLE new cron whose slug
    // declaration evades SLUG_RE (typed annotation, template literal,
    // renamed const) would pass both it and the parity check while
    // heartbeating into the void. Pin extraction per producer: any file
    // that calls postSentryHeartbeat must yield >= 1 slug.
    const silent = nonOneshotFiles().filter((file) => {
      // _-prefixed files are shared helper modules (one of them DEFINES
      // postSentryHeartbeat), not heartbeat producers.
      if (file.startsWith("_")) return false;
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      if (!src.includes("postSentryHeartbeat")) return false;
      return [...src.matchAll(SLUG_RE)].length === 0;
    });
    expect(
      silent,
      `handler(s) call postSentryHeartbeat but SLUG_RE extracted no slug — ` +
        `declare the canonical \`const SENTRY_MONITOR_SLUG = "<kebab>"\` shape ` +
        `(or fix SLUG_RE if the convention changed): ${silent.join(", ")}`,
    ).toEqual([]);
  });

  it("oneshot-* files declare no monitor slug (ADR-033 prefix table) outside the exempt list", () => {
    const offenders: string[] = [];
    for (const file of readdirSync(FUNCTIONS_DIR)) {
      if (!file.startsWith("oneshot-") || !file.endsWith(".ts")) continue;
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      for (const m of src.matchAll(SLUG_RE)) {
        if (!ONESHOT_SLUG_EXEMPTIONS.has(m[1])) {
          offenders.push(`${file} -> ${m[1]}`);
        }
      }
    }
    expect(
      offenders,
      `oneshot functions must not declare SENTRY_MONITOR_SLUG (a crontab ` +
        `monitor false-alerts on a non-recurring fn; check-ins to an ` +
        `un-provisioned slug are void). Route errors via reportSilentFallback ` +
        `instead, or add a deliberate exemption: ${offenders.join(", ")}`,
    ).toEqual([]);
  });

  it("tf name-attr extraction is pinned to the resource count (no prose/foreign-resource leak)", () => {
    expect(iacMonitorNames().size).toBe(iacResourceCount());
  });

  it("every code slug has a sentry_cron_monitor resource in cron-monitors.tf", () => {
    const names = iacMonitorNames();
    const missing = codeSlugs().filter(
      (s) => !names.has(s) && !DISABLED_CRON_SLUG_EXEMPTIONS.has(s),
    );
    expect(
      missing,
      `Inngest handlers heartbeat to monitor slug(s) with no IaC resource — ` +
        `check-ins are silently dropped and a dead cron pages nowhere. Add a ` +
        `sentry_cron_monitor block to apps/web-platform/infra/sentry/` +
        `cron-monitors.tf for: ${missing.join(", ")}`,
    ).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Heartbeat STEP SHAPE (#7834).
//
// The slug↔monitor parity above answers "does a declared slug have a resource".
// It cannot see the three other ways a heartbeat silently stops being a
// dead-man's switch, and nothing else asserted them for ANY workflow:
//
//   (1) the step is not the LAST step of its job, so an earlier `exit 1` on the
//       drift path leaves it unreached;
//   (2) its `if:` lost `always()`, so it inherits an implicit `success()` and
//       SKIPS on exactly the failing runs the monitor exists to observe;
//   (3) the step id its `status:` expression reads was renamed, so the
//       expression resolves to the fallback arm on every run — the monitor then
//       pages daily forever while (1) and (2) both still pass.
//
// SCOPES ARE MEASURED, NOT ASSUMED. A cohort audit of all 11 heartbeat steps
// across 10 workflows (2026-09-06) found `continue-on-error: true` and an `if:`
// CONTAINING `always()` universal, but terminality and the exact step name are
// NOT: `scheduled-terraform-drift.yml` documents a step deliberately placed
// after its heartbeat, and `workspaces-luks-verify.yml` names its step
// `Sentry Crons check-in`. Asserting `if:` EQUALS `always()` would red three
// siblings that legitimately carry `always() && <extra>`.
// ---------------------------------------------------------------------------

// Tolerant of an optional quote, mirroring the `monitor-slug` regex above whose
// own comment calls an intolerant version "the exact class this guard exists to
// prevent". Measured: quoting the path removed a whole workflow from the cohort
// with the suite still green.
const HEARTBEAT_USES_RE = /uses:\s*"?\.\/\.github\/actions\/sentry-heartbeat"?/;

type HeartbeatStep = {
  file: string;
  job: string;
  name: string | null;
  ifExpr: string | null;
  continueOnError: boolean;
  isLastInJob: boolean;
  statusStepIds: string[];
  idsBefore: Set<string>;
  // The DESTINATION and the raw expression. Without these the guard asserts the
  // step's shape while saying nothing about which monitor it feeds or what it
  // computes — measured: deleting `monitor-slug:`, re-pointing it at another
  // monitor, inverting the allowlist to a denylist, and typoing the output name
  // all left the suite 14/14 green.
  monitorSlug: string | null;
  statusExpr: string | null;
};

// Indentation-based walk. Keyed on the composite action PATH, never the bare
// string "sentry-heartbeat" — two workflows mention that string in prose only
// (apply-web-platform-infra.yml, and this workflow's own header), and a
// substring key would pull both in as phantom cohort members.
function heartbeatSteps(): HeartbeatStep[] {
  const out: HeartbeatStep[] = [];
  for (const file of readdirSync(WORKFLOWS_DIR)) {
    if (!file.endsWith(".yml") && !file.endsWith(".yaml")) continue;
    const src = readFileSync(join(WORKFLOWS_DIR, file), "utf-8");
    if (!HEARTBEAT_USES_RE.test(src)) continue;
    const lines = src.split("\n");

    let job = "<none>";
    let stepStart = -1;
    const stepStarts: { line: number; job: string }[] = [];
    const jobBoundaries: number[] = [];

    for (let i = 0; i < lines.length; i++) {
      const l = lines[i];
      if (/^ {2}[A-Za-z_][\w-]*:\s*$/.test(l)) {
        jobBoundaries.push(i);
        job = l.trim().replace(/:$/, "");
      }
      // Indent-tolerant, not hardcoded to six spaces: a 4-space step list is
      // ordinary YAML, and a `^ {6}- ` literal made such a file contribute ZERO
      // steps while still containing the action — total invisibility at green.
      // Anchored on the keys a step can legally open with so a `- ` inside a
      // `with:`/`env:` block cannot register as a step start.
      if (/^\s{2,}- (name|uses|id|if|with|env|run|continue-on-error|timeout-minutes|working-directory|shell):/.test(l))
        stepStarts.push({ line: i, job });
    }

    for (let s = 0; s < stepStarts.length; s++) {
      stepStart = stepStarts[s].line;
      const nextStep = s + 1 < stepStarts.length ? stepStarts[s + 1].line : lines.length;
      const nextJob = jobBoundaries.find((b) => b > stepStart) ?? lines.length;
      const end = Math.min(nextStep, nextJob);
      const block = lines.slice(stepStart, end).join("\n");
      if (!HEARTBEAT_USES_RE.test(block)) continue;

      // Last in its job iff no further step start precedes the next job boundary.
      const isLastInJob = nextStep >= nextJob;

      const nameM = block.match(/^ {6}- name:\s*(.+?)\s*$/m);
      const ifM = block.match(/^\s*if:\s*(.+?)\s*$/m);
      const statusM = block.match(/^\s*status:\s*(.+?)\s*$/m);
      const statusStepIds = statusM
        ? [...statusM[1].matchAll(/steps\.([A-Za-z_][\w-]*)\./g)].map((m) => m[1])
        : [];

      const idsBefore = new Set<string>();
      for (const prior of stepStarts) {
        if (prior.line >= stepStart || prior.job !== stepStarts[s].job) continue;
        const pEnd = stepStarts.find((x) => x.line > prior.line)?.line ?? lines.length;
        const pBlock = lines.slice(prior.line, pEnd).join("\n");
        // Both shapes: `- id: foo` on the step's own dash line, and `id: foo`
        // on a following line. scheduled-realtime-probe.yml uses the FIRST, and
        // a regex anchored only on the second reports its healthy heartbeat as
        // a dangling reference — a false positive that reads exactly like the
        // real defect this assertion hunts.
        const idM = pBlock.match(/^\s*(?:- )?id:\s*([A-Za-z_][\w-]*)\s*$/m);
        if (idM) idsBefore.add(idM[1]);
      }

      const slugM = block.match(/^\s*monitor-slug:\s*"?([a-z0-9-]+)"?\s*(?:#.*)?$/m);

      out.push({
        monitorSlug: slugM ? slugM[1] : null,
        statusExpr: statusM ? statusM[1] : null,
        file,
        job: stepStarts[s].job,
        name: nameM ? nameM[1] : null,
        ifExpr: ifM ? ifM[1] : null,
        continueOnError: /^\s*continue-on-error:\s*true\s*$/m.test(block),
        statusStepIds,
        isLastInJob,
        idsBefore,
      });
    }
  }
  return out;
}

describe("Sentry heartbeat step shape (#7834)", () => {
  it("the cohort is exactly the set of workflows carrying the action (no silent drop)", () => {
    // THE closure check. Every other assertion here quantifies over whatever the
    // walk returned, so a walk that stops seeing a member reports no offenders
    // for it forever. Derive the population a SECOND way — a plain file-level
    // regex — and require the two to agree. Measured before this existed:
    // dropping two files from the walk, and adding a 4-space-indented workflow
    // carrying three defects, both left the suite fully green.
    const withAction = readdirSync(WORKFLOWS_DIR)
      .filter((f) => /\.ya?ml$/.test(f))
      .filter((f) => HEARTBEAT_USES_RE.test(readFileSync(join(WORKFLOWS_DIR, f), "utf-8")))
      .sort();
    const inCohort = [...new Set(heartbeatSteps().map((s) => s.file))].sort();
    expect(inCohort).toEqual(withAction);
  });

  it("discovers the known heartbeat-step cohort (anti-vacuity)", () => {
    const steps = heartbeatSteps();
    // Measured 2026-09-06 ON THIS BRANCH: 12 steps across 11 workflows
    // (scheduled-terraform-drift.yml carries two). An earlier revision of this
    // comment said 11/10 — the PRE-change tree — which left the floor two units
    // slack instead of one, and a floor is an anti-vacuity counter, so an
    // off-by-one in the comment is an off-by-one in the guard.
    expect(steps.length).toBeGreaterThanOrEqual(12);
    expect(steps.map((s) => s.file)).toContain("scheduled-terraform-drift.yml");
  });

  it("cohort-wide: every heartbeat step names a monitor-slug", () => {
    const bad = heartbeatSteps()
      .filter((s) => !s.monitorSlug)
      .map((s) => `${s.file}:${s.job}`);
    expect(bad).toEqual([]);
  });

  it("scheduled-terraform-drift's drift-check heartbeat is NOT terminal (must-FAIL fixture)", () => {
    // The natural negative that makes `isLastInJob` unwritable as a constant.
    // Without it the field had a must-PASS fixture and no must-FAIL one, so
    // `const isLastInJob = true` passed the whole suite while terminality — the
    // property this block exists to pin — was unasserted.
    const s = heartbeatSteps().find(
      (x) => x.file === "scheduled-terraform-drift.yml" && x.job === "drift-check",
    );
    expect(s).toBeDefined();
    expect(s!.isLastInJob).toBe(false);
  });

  it("cohort-wide: every heartbeat step carries continue-on-error: true", () => {
    const bad = heartbeatSteps()
      .filter((s) => !s.continueOnError)
      .map((s) => `${s.file}:${s.job}`);
    expect(bad).toEqual([]);
  });

  it("cohort-wide: every heartbeat step's if: contains always()", () => {
    // CONTAINS, not equals — main-health-monitor, scheduled-supabase-advisor-scan
    // and workspaces-luks-verify all legitimately carry `always() && <extra>`.
    const bad = heartbeatSteps()
      .filter((s) => !s.ifExpr || !s.ifExpr.includes("always()"))
      .map((s) => `${s.file}:${s.job} if=${s.ifExpr ?? "<none>"}`);
    expect(bad).toEqual([]);
  });

  it("cohort-wide: every step id read by a status: expression exists earlier in the same job", () => {
    // Catches the rename that leaves position and always() both green while the
    // expression resolves to its fallback arm on every run.
    const dangling: string[] = [];
    for (const s of heartbeatSteps()) {
      for (const id of s.statusStepIds) {
        if (!s.idsBefore.has(id)) dangling.push(`${s.file}:${s.job} -> steps.${id}`);
      }
    }
    expect(dangling).toEqual([]);
  });

  it("scheduled-sentry-alert-drift: the heartbeat is present, terminal, and named", () => {
    // Scoped deliberately. Terminality is NOT a cohort invariant — see the
    // header — so it is asserted only for the workflow this PR adds.
    const steps = heartbeatSteps().filter(
      (s) => s.file === "scheduled-sentry-alert-drift.yml",
    );
    expect(steps.length).toBe(1);
    expect(steps[0].name).toBe("Sentry check-in (final)");
    expect(steps[0].isLastInJob).toBe(true);
    expect(steps[0].statusStepIds).toContain("probe");

    // WHERE it checks in. `statusStepIds` captures the step id and discards
    // everything else, so the assertion above is satisfied by any expression
    // that merely mentions the step. Measured: deleting `monitor-slug:` and
    // re-pointing it at `scheduled-terraform-drift` both left the suite green —
    // the second is worse than silence, because it keeps another workflow's
    // monitor alive after that workflow dies.
    expect(steps[0].monitorSlug).toBe("scheduled-sentry-alert-drift");

    // WHAT it computes. Three measured mutants passed `toContain("probe")`:
    // an `!= 'unavailable'` denylist (which this workflow's own comment says
    // must never be written, and which also deletes the backstop), a
    // `&& 'ok' || 'ok'` that can never report error, and a one-character typo
    // of the OUTPUT name (the id half was asserted, the name half was not).
    const expr = steps[0].statusExpr ?? "";
    expect(expr).toMatch(/steps\.probe\.outputs\.verdict\s*==\s*'clean'/);
    expect(expr).toMatch(/steps\.probe\.outputs\.verdict\s*==\s*'drift'/);
    expect(expr).toMatch(/steps\.file_drift\.outputs\.filed\s*==\s*'true'/);
    // Allowlist, never denylist — the mechanical form of the comment above the step.
    expect(expr).not.toMatch(/steps\.\w+\.outputs\.\w+\s*!=/);
    // It must be able to reach BOTH arms.
    expect(expr).toMatch(/&&\s*'ok'\s*\|\|\s*'error'/);
  });
});
