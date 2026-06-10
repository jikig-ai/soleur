// #5091 — self-discovering parity guard for the bot-cron safe-commit invariants.
//
// Static per-file test lists rot (the next producer is never added), so this
// guard walks server/inngest/functions/ at run time (readdirSync pattern per
// learning 2026-06-07-self-discovering-parity-guard-for-cross-producer-drift)
// and enforces four mechanical invariants:
//
//   1. NO cron/event source (nor the containment hook) contains a blanket
//      git-add literal — comments included, so keep new code comments clear
//      of the literals.
//   2. The migrated crons import + call safeCommitAndPr AND carry the
//      platform-persistence prompt anchor (minimum-bound, not exact-count:
//      an exact count makes every future migration fail this test for no
//      signal).
//   3. Tier-2 restoration constraint: a migrated cron's CRON_BASH_ALLOWLISTS
//      entry (if present) must NOT re-arm prompt-side persistence verbs —
//      the handler owns persistence now. A restoration that re-adds
//      git add/commit/push or gh pr create/merge fails CI here instead of
//      relying on a PR-body memo (the #5026 sequencing hazard).
//   4. Exempt list (explicit, with rationale): the legacy handler-side
//      spawnGitChecked pipelines + the 4 scoped-add prompt crons (migration
//      tracked by the consolidation follow-up issue) + roadmap-review (live
//      Tier-1; guarded by the hook's blanket-staging deny set).

import { readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { CRON_BASH_ALLOWLISTS } from "@/server/inngest/functions/_cron-claude-eval-substrate";

const FUNCTIONS_DIR = resolve(__dirname, "../../../server/inngest/functions");
const HOOK_PATH = resolve(__dirname, "../../../server/inngest/cron-bash-allowlist-hook.mjs");

// Crons migrated to handler-side persistence (#5091). Grows as the
// consolidation follow-up migrates the rest.
const MIGRATED = [
  "cron-seo-aeo-audit.ts",
  "cron-content-generator.ts",
  "cron-growth-execution.ts",
];

// Crons that still carry their own persistence, each with a rationale.
// Tracked for migration by the #5091 consolidation follow-up issue unless
// noted otherwise.
const EXEMPT: Record<string, string> = {
  // Prompt-level SCOPED adds (not the blanket #5026 class), Tier-2 dormant:
  "cron-campaign-calendar.ts": "scoped prompt add; consolidation follow-up",
  "cron-growth-audit.ts": "scoped prompt add; consolidation follow-up",
  "cron-community-monitor.ts": "scoped prompt add; consolidation follow-up",
  "cron-competitive-analysis.ts": "scoped prompt add; consolidation follow-up",
  // Handler-side spawnGitChecked pipelines with scoped adds (live, working):
  "cron-weekly-analytics.ts": "legacy handler-side pipeline; consolidation follow-up",
  "cron-compound-promote.ts": "legacy handler-side pipeline; consolidation follow-up",
  "cron-content-publisher.ts": "legacy handler-side pipeline; consolidation follow-up",
  "cron-content-vendor-drift.ts": "legacy handler-side pipeline; consolidation follow-up",
  "cron-rule-prune.ts": "legacy handler-side pipeline; consolidation follow-up",
  // Live Tier-1: model improvises git within its bash allowlist; the hook's
  // blanket-staging deny set + the prompt STAGING RULE are its guard:
  "cron-roadmap-review.ts": "hook-guarded Tier-1 self-commit",
  // Skill-mediated: commit step lives in plugins/soleur/skills/fix-issue
  // (scoped add since #5091), not in the prompt:
  "cron-bug-fixer.ts": "fix-issue skill owns the commit step (scoped add)",
};

const cronFiles = readdirSync(FUNCTIONS_DIR).filter((f) =>
  /^(cron|event)-.*\.ts$/.test(f),
);

describe("safe-commit parity — invariant 1: no blanket git-add literal anywhere", () => {
  it.each(cronFiles.map((f) => [f]))("%s carries no blanket-add literal", (file) => {
    const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
    expect(src).not.toContain("git add -A");
    expect(src).not.toContain("git add --all");
    expect(src).not.toContain("git add -u");
    expect(src).not.toContain("git add .");
  });

  it("the containment hook itself carries no blanket-add literal (comments included)", () => {
    const src = readFileSync(HOOK_PATH, "utf-8");
    expect(src).not.toContain("git add -A");
    expect(src).not.toContain("git add --all");
    expect(src).not.toContain("git add -u");
  });
});

describe("safe-commit parity — invariant 2: migrated crons route through safeCommitAndPr", () => {
  it("discovers the migrated crons and keeps MIGRATED/EXEMPT disjoint", () => {
    for (const f of MIGRATED) {
      expect(cronFiles).toContain(f);
      expect(EXEMPT[f]).toBeUndefined();
    }
    // EXEMPT files must not CALL safeCommitAndPr (importing the shared
    // enableAutoMergeSquash, as cron-bug-fixer does, is fine) — a migrated
    // cron left in EXEMPT silently skips invariants 2-3 (review P2).
    for (const f of Object.keys(EXEMPT)) {
      const src = readFileSync(join(FUNCTIONS_DIR, f), "utf-8");
      expect(src, `${f} calls safeCommitAndPr but sits in EXEMPT — move it to MIGRATED`).not.toMatch(
        /safeCommitAndPr\(\{/,
      );
    }
  });

  it.each(MIGRATED.map((f) => [f]))(
    "%s routes through safeCommitAndPr behind the issue-verified gate",
    (file) => {
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      // Import may grow more named members (bug-fixer pattern) — assert
      // module + call, not exact formatting.
      expect(src).toContain('from "./_cron-safe-commit"');
      expect(src).toMatch(/safeCommitAndPr\(\{/);
      expect(src).toContain("PERSISTENCE: Do NOT run git add");
      // Plan AC5: the persistence step MUST be gated on issue-verified
      // output AND not-timed-out — a regression to `spawnResult.ok` (the
      // #4747 hazard) or a dropped timeout clause turns this red.
      expect(src).toMatch(
        /if \(heartbeatOk && !spawnResult\.abortedByTimeout\) \{[\s\S]{0,800}?safeCommitAndPr\(\{/,
      );
      // The prompt must not retain a prompt-side commit block.
      expect(src).not.toContain("MANDATORY FINAL STEP");
    },
  );
});

describe("safe-commit parity — invariant 3: Tier-2 restoration must not re-arm prompt-side persistence", () => {
  const PERSISTENCE_PREFIXES = [
    "git add",
    "git commit",
    "git push",
    "gh pr create",
    "gh pr merge",
  ];

  it("canary: the allowlist key shape matches real CRON_BASH_ALLOWLISTS keys", () => {
    // If the cronName derivation below ever drifts from the map's key
    // format, invariant 3 would silently no-op forever (review P3) — this
    // canary pins the shape against the one key that exists today.
    expect(Object.keys(CRON_BASH_ALLOWLISTS)).toContain("cron-roadmap-review");
  });

  it.each(MIGRATED.map((f) => [f]))(
    "%s allowlist (if present) excludes persistence verbs",
    (file) => {
      const cronName = file.replace(/\.ts$/, "");
      const allowlist = CRON_BASH_ALLOWLISTS[cronName];
      if (!allowlist) return; // not restored yet — nothing to assert
      for (const prefix of PERSISTENCE_PREFIXES) {
        const offending = allowlist.filter((entry) => entry.startsWith(prefix));
        expect(
          offending,
          `${cronName} is migrated to handler-side persistence; its bash allowlist must not re-arm "${prefix}"`,
        ).toEqual([]);
      }
    },
  );
});

describe("safe-commit parity — invariant 4: every PR-persisting cron is migrated or exempt", () => {
  // A cron "persists" when its source stages files (prompt shell or
  // handler-side git add). Detection is the staging verb itself — scoped
  // forms included — so a NEW cron that adds any commit pathway must either
  // migrate to safeCommitAndPr or document an exemption here.
  it("classifies every cron with a staging pathway", () => {
    const unaccounted: string[] = [];
    for (const file of cronFiles) {
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      const stages =
        /git add /.test(src) || /spawnGitChecked\(\s*\[\s*"add"/.test(src) || /\["add",/.test(src);
      if (!stages) continue;
      if (MIGRATED.includes(file)) continue;
      if (EXEMPT[file]) continue;
      unaccounted.push(file);
    }
    expect(
      unaccounted,
      "new cron with a staging pathway: migrate it to safeCommitAndPr or add a rationale to EXEMPT",
    ).toEqual([]);
  });
});
