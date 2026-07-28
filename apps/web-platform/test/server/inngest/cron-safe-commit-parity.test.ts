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
//   4. Exempt list (explicit, with rationale): permanently two entries since
//      #5111 emptied the migration backlog — roadmap-review (live Tier-1;
//      guarded by the hook's blanket-staging deny set) and bug-fixer (the
//      fix-issue skill owns its commit step). See ADR-054.

import { readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { CRON_BASH_ALLOWLISTS } from "@/server/inngest/functions/_cron-claude-eval-substrate";
import { TIER2_DEFERRED_CRONS } from "@/server/inngest/functions/_cron-shared";

const FUNCTIONS_DIR = resolve(__dirname, "../../../server/inngest/functions");
const HOOK_PATH = resolve(__dirname, "../../../server/inngest/cron-bash-allowlist-hook.mjs");

// Claude-spawn crons migrated to handler-side persistence (#5091 + #5111).
// Full invariant-2 assertions apply: these have a prompt (PERSISTENCE anchor)
// and a spawn result (the heartbeatOk gate).
const MIGRATED_PROMPT = [
  "cron-seo-aeo-audit.ts",
  "cron-content-generator.ts",
  "cron-growth-execution.ts",
  "cron-campaign-calendar.ts",
  "cron-growth-audit.ts",
  "cron-community-monitor.ts",
  "cron-competitive-analysis.ts",
  "cron-architecture-diagram-sync.ts",
];

// Pure-TS data-refresh pipelines migrated by #5111. No claude spawn → no
// prompt and no heartbeatOk gate, so invariant 2's prompt-anchor/gate
// assertions are unsatisfiable by construction; this cohort asserts
// import + call + no private spawnGitChecked staging instead.
const MIGRATED_HANDLER = [
  "cron-weekly-analytics.ts",
  "cron-compound-promote.ts",
  "cron-content-publisher.ts",
  "cron-content-vendor-drift.ts",
  "cron-rule-prune.ts",
];

const MIGRATED_ALL = [...MIGRATED_PROMPT, ...MIGRATED_HANDLER];

// Permanent exemptions (ADR-054) — each with a rationale. This list must
// NOT grow without an ADR-054 amendment.
const EXEMPT: Record<string, string> = {
  // Live Tier-1: model improvises git within its bash allowlist; the hook's
  // blanket-staging deny set + the prompt STAGING RULE are its guard:
  "cron-roadmap-review.ts": "hook-guarded Tier-1 self-commit",
  // Skill-mediated: commit step lives in plugins/soleur/skills/fix-issue
  // (scoped add since #5091), not in the prompt:
  "cron-bug-fixer.ts": "fix-issue skill owns the commit step (scoped add)",
};

// Read-only probe crons (#5674) — a third class beyond MIGRATED/EXEMPT.
// `cron-anthropic-credit-probe.ts` does NO git and opens NO PR (it pages a
// Sentry heartbeat from a 1-token Anthropic canary call), so the safe-commit
// invariant does not apply: it is neither migrated (nothing to route through
// safeCommitAndPr) nor exempt (exemption is for crons that DO self-commit).
// `cron-anthropic-cost-report.ts` (ADR-107) is the same class — it reads the
// Anthropic Admin cost_report API and emits a `SOLEUR_CLAUDE_COST_DAILY` marker,
// holding no git and opening no PR. Both are covered by invariant 1's directory
// walk (carry no blanket git-add) and need no MIGRATED/EXEMPT entry. Documented
// here so the cron-tier2-parity sibling-set sweep sees this dependent
// acknowledged when EXPECTED_CRON_FUNCTIONS grows with a new read-only probe.
const READ_ONLY_PROBES = [
  "cron-anthropic-credit-probe.ts",
  "cron-anthropic-cost-report.ts",
];

// Dispatch-hybrid crons (#5872 acknowledgment) — a fourth implicit class beyond
// MIGRATED/EXEMPT/READ_ONLY_PROBES. `cron-dev-migration-drift`, `cron-terraform-drift`,
// `cron-domain-model-drift` and `cron-inngest-config-drift` (#6780, event-only/dormant)
// are SCHEDULERS ONLY: the dispatcher mints a
// short-lived installation token and POSTs a `workflow_dispatch`, holding no git
// and opening no PR (the git-touching / issue-filing work runs in the ephemeral
// GHA executor, not the Node dispatcher). Like READ_ONLY_PROBES the safe-commit
// invariant does not apply — they carry no persistence path — so they need no
// list entry and are covered by invariant 1's directory walk. Documented here so
// the cron-tier2-parity sibling-set sweep sees this dependent acknowledged when
// EXPECTED_CRON_FUNCTIONS grows with a new dispatch-hybrid cron. `cron-action-
// required-sla` (#6831) is the same class — it enumerates the action-required
// backlog and fans out `sla/issue.process` events to a worker that mutates issue
// labels/state via the GitHub API, holding no git and opening no PR; the
// safe-commit invariant does not apply and it needs no MIGRATED/EXEMPT entry
// (covered by invariant 1's directory walk).

// #6657: cron-gh-pages-cert-reissue is a fifth class — an EVENT-TRIGGERED
// live-infra remediation. It flips CF DNS proxy state + re-orders the GitHub
// Pages cert via the App token and files/comments issues via the poll cron, but
// it holds NO git and opens NO PR (no safeCommitAndPr path). Like the read-only
// probes + dispatch-hybrids, the safe-commit invariant does not apply — it needs
// no MIGRATED/EXEMPT entry and is covered by invariant 1's directory walk.
// Acknowledged here so the cron-tier2-parity sibling-set sweep sees this
// dependent when EXPECTED_CRON_FUNCTIONS grows with a new event-triggered cron.

const cronFiles = readdirSync(FUNCTIONS_DIR).filter((f) =>
  /^(cron|event)-.*\.ts$/.test(f),
);

describe("safe-commit parity — read-only probe crons own no persistence path", () => {
  it.each(READ_ONLY_PROBES.map((f) => [f]))(
    "%s exists, does not import safeCommitAndPr, and is not EXEMPT-listed",
    (file) => {
      expect(cronFiles).toContain(file);
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      expect(src).not.toMatch(/safeCommitAndPr\(\{/);
      expect(EXEMPT[file]).toBeUndefined();
    },
  );
});

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
    for (const f of MIGRATED_ALL) {
      expect(cronFiles).toContain(f);
      expect(EXEMPT[f]).toBeUndefined();
    }
    // The two cohorts must not overlap (a cron is prompt-gated XOR pure-TS).
    for (const f of MIGRATED_PROMPT) {
      expect(MIGRATED_HANDLER).not.toContain(f);
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

  it.each(MIGRATED_PROMPT.map((f) => [f]))(
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

  it.each(MIGRATED_HANDLER.map((f) => [f]))(
    "%s (pure-TS pipeline) routes through safeCommitAndPr with no private staging copy",
    (file) => {
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      expect(src).toContain('from "./_cron-safe-commit"');
      expect(src).toMatch(/safeCommitAndPr\(\{/);
      // The #5111 migration deleted each file's private spawnGitChecked
      // staging/commit/push/PR pipeline — its return is a regression.
      expect(src).not.toContain("spawnGitChecked");
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

  it.each(MIGRATED_ALL.map((f) => [f]))(
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
  const stagesFiles = (src: string): boolean =>
    /git add /.test(src) || /spawnGitChecked\(\s*\[\s*"add"/.test(src) || /\["add",/.test(src);

  it("classifies every cron with a staging pathway", () => {
    const unaccounted: string[] = [];
    for (const file of cronFiles) {
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      if (!stagesFiles(src)) continue;
      if (MIGRATED_ALL.includes(file)) continue;
      if (EXEMPT[file]) continue;
      unaccounted.push(file);
    }
    expect(
      unaccounted,
      "new cron with a staging pathway: migrate it to safeCommitAndPr or add a rationale to EXEMPT",
    ).toEqual([]);
  });

  // Migration is a CONSTRAINT, not a terminal state: a migrated cron that
  // re-grows its own staging pathway alongside the helper call would slip
  // every other invariant (invariant 1 matches contiguous literals only;
  // invariant 2 HANDLER checks the spawnGitChecked identifier only). The
  // helper must be a migrated cron's ONLY staging pathway. The prompt
  // cohort's PERSISTENCE directive is comma-delimited ("git add,") so it
  // does not trip the /git add / trailing-space detector.
  it.each(MIGRATED_ALL.map((f) => [f]))(
    "%s has no staging pathway outside safeCommitAndPr",
    (file) => {
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      expect(
        stagesFiles(src),
        `${file} is migrated but carries its own staging pathway — route it through safeCommitAndPr`,
      ).toBe(false);
    },
  );
});

// #5199 — restore the 7 mergeMode:"auto" Tier-2-deferred crons. Each is now a
// Tier-1, hook-contained PR-flow cron: a finite CRON_BASH_ALLOWLISTS entry,
// ABSENT from TIER2_DEFERRED_CRONS, minting the DEFAULT_CRON_TOKEN_PERMISSIONS
// (contents/issues/pull_requests:write — they push + open PRs via
// safeCommitAndPr) scoped to [REPO_NAME]. Only cron-bug-fixer stays deferred.
const RESTORED_AUTO_CRONS = [
  "cron-growth-audit",
  "cron-growth-execution",
  "cron-competitive-analysis",
  "cron-seo-aeo-audit",
  "cron-content-generator",
  "cron-campaign-calendar",
  "cron-community-monitor",
] as const;

describe("#5199 — restored auto-crons: parity (allowlisted AND not deferred)", () => {
  it.each(RESTORED_AUTO_CRONS.map((c) => [c]))(
    "%s IS a CRON_BASH_ALLOWLISTS key AND ABSENT from TIER2_DEFERRED_CRONS",
    (cronName) => {
      expect(Object.keys(CRON_BASH_ALLOWLISTS)).toContain(cronName);
      expect(TIER2_DEFERRED_CRONS.has(cronName)).toBe(false);
    },
  );

  it("TIER2_DEFERRED_CRONS is EMPTY — all Tier-2 crons restored (#5199)", () => {
    expect([...TIER2_DEFERRED_CRONS]).toEqual([]);
  });
});

// #5199 (final) — restore cron-bug-fixer, the LAST Tier-2-deferred cron. Unlike
// the 7 auto-crons above, bug-fixer's commit step lives in the fix-issue SKILL
// (NOT safeCommitAndPr), so it stays in EXEMPT and its CRON_BASH_ALLOWLISTS entry
// legitimately carries git/gh-pr persistence verbs. It mints
// DEFAULT_CRON_TOKEN_PERMISSIONS scoped to [REPO_NAME] (a write-capable token —
// ISSUE_CREATOR's contents:read would 403 the push).
describe("#5199 — restored cron-bug-fixer: parity (allowlisted AND not deferred)", () => {
  it("cron-bug-fixer IS a CRON_BASH_ALLOWLISTS key AND ABSENT from TIER2_DEFERRED_CRONS", () => {
    expect(Object.keys(CRON_BASH_ALLOWLISTS)).toContain("cron-bug-fixer");
    expect(TIER2_DEFERRED_CRONS.has("cron-bug-fixer")).toBe(false);
  });

  it("cron-bug-fixer.ts mints DEFAULT_CRON_TOKEN_PERMISSIONS scoped to [REPO_NAME] (not ISSUE_CREATOR)", () => {
    const src = readFileSync(join(FUNCTIONS_DIR, "cron-bug-fixer.ts"), "utf-8");
    expect(src).toContain("permissions: DEFAULT_CRON_TOKEN_PERMISSIONS");
    expect(src).toMatch(/repositories:\s*\[REPO_NAME\]/);
    // bug-fixer pushes + opens PRs via the SKILL — it must NOT use the
    // issue-creator preset (contents:read), which would 403 the push.
    expect(src).not.toContain("ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS");
  });

  it("cron-bug-fixer.ts stays in EXEMPT (SKILL owns the commit, not safeCommitAndPr)", () => {
    expect(EXEMPT["cron-bug-fixer.ts"]).toBeDefined();
    expect(MIGRATED_ALL).not.toContain("cron-bug-fixer.ts");
  });

  it("cron-bug-fixer allowlist contains no entry beginning with 'gh api' (F4a)", () => {
    const allowlist = CRON_BASH_ALLOWLISTS["cron-bug-fixer"];
    expect(allowlist).toBeDefined();
    const offending = (allowlist ?? []).filter((entry) =>
      entry.startsWith("gh api"),
    );
    expect(
      offending,
      "cron-bug-fixer: arbitrary-method 'gh api' defeats the exfil defense (F4a)",
    ).toEqual([]);
  });
});

describe("#5199 — restored auto-crons: token mint narrowed to DEFAULT permissions", () => {
  it.each(RESTORED_AUTO_CRONS.map((c) => [c]))(
    "%s mints DEFAULT_CRON_TOKEN_PERMISSIONS scoped to [REPO_NAME] (not ISSUE_CREATOR)",
    (cronName) => {
      const src = readFileSync(join(FUNCTIONS_DIR, `${cronName}.ts`), "utf-8");
      expect(src).toContain("permissions: DEFAULT_CRON_TOKEN_PERMISSIONS");
      expect(src).toMatch(/repositories:\s*\[REPO_NAME\]/);
      // These 7 push + open PRs via safeCommitAndPr — they must NOT use the
      // issue-creator preset (contents:read), which would 403 the push/PR.
      expect(src).not.toContain("ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS");
    },
  );
});

describe("#5199 — restored auto-crons: no gh-api allowlist entry (F4a)", () => {
  it.each(RESTORED_AUTO_CRONS.map((c) => [c]))(
    "%s allowlist contains no entry beginning with 'gh api'",
    (cronName) => {
      const allowlist = CRON_BASH_ALLOWLISTS[cronName];
      expect(allowlist).toBeDefined();
      const offending = (allowlist ?? []).filter((entry) =>
        entry.startsWith("gh api"),
      );
      expect(
        offending,
        `${cronName}: arbitrary-method 'gh api' defeats the exfil defense (F4a)`,
      ).toEqual([]);
    },
  );
});

describe("#6031 — cron-ghcr-token-minter is a non-git cron", () => {
  // The GHCR installation-token minter mints a token and writes to Doppler; it
  // does NO git operations, so it neither calls safeCommitAndPr nor carries a
  // CRON_BASH_ALLOWLISTS entry, and is not a deferred Tier-2 cron. Acknowledged
  // here so the sibling-set sweep sees this dependent when EXPECTED_CRON_FUNCTIONS
  // grows (cron-tier2-parity set).
  it("has no CRON_BASH_ALLOWLISTS entry and is not Tier-2 deferred", () => {
    expect(CRON_BASH_ALLOWLISTS["cron-ghcr-token-minter"]).toBeUndefined();
    expect(TIER2_DEFERRED_CRONS.has("cron-ghcr-token-minter")).toBe(false);
  });
});

describe("#6602 — cron-expenses-verify-by is a non-git dispatch-hybrid cron", () => {
  // The expenses verify_by scheduler mints an installation token and dispatches
  // scheduled-expenses-verify-by.yml; it does NO git operations, so it neither
  // calls safeCommitAndPr nor carries a CRON_BASH_ALLOWLISTS entry, and is not a
  // deferred Tier-2 cron. Acknowledged here so the sibling-set sweep sees this
  // dependent when EXPECTED_CRON_FUNCTIONS grows (cron-tier2-parity set).
  it("has no CRON_BASH_ALLOWLISTS entry and is not Tier-2 deferred", () => {
    expect(CRON_BASH_ALLOWLISTS["cron-expenses-verify-by"]).toBeUndefined();
    expect(TIER2_DEFERRED_CRONS.has("cron-expenses-verify-by")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// #6750 A1 pin 1 + pin 3 — the cohort pins that survive merge. ADD-ONLY:
// nothing above this line is modified.
// ---------------------------------------------------------------------------
// The roster is DERIVED FROM BEHAVIOUR, not from the MIGRATED_PROMPT literal
// above. MIGRATED_PROMPT is a hand-maintained array, so a 9th cron that calls
// finalizeOutputAwareHeartbeat without being added to it would silently escape
// this gate — and omission is the dangerous direction (see the ADR-126
// amendment: omitting `retryEligible: false` while consuming safeCommitAndPr's
// return value buys an Inngest replay that cannot succeed).
const FINALIZE_CALLERS = cronFiles.filter((f) =>
  /finalizeOutputAwareHeartbeat\(/.test(readFileSync(join(FUNCTIONS_DIR, f), "utf-8")),
);

describe("#6750 A1 pin 1 — every finalizeOutputAwareHeartbeat caller passes retryEligible: false", () => {
  it("discovers the cohort by behaviour and finds a non-trivial roster", () => {
    // Cardinality guard: a filter that silently matched nothing would make
    // every it.each below vacuous (zero cases is a passing suite).
    expect(FINALIZE_CALLERS.length).toBeGreaterThanOrEqual(8);
    for (const f of MIGRATED_PROMPT) expect(FINALIZE_CALLERS).toContain(f);
  });

  it.each(FINALIZE_CALLERS.map((f) => [f]))(
    "%s passes retryEligible: false AT THE CALL SITE",
    (file) => {
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      // ANCHORED, not a bare token. Measured against the reference
      // implementation: the bare token `retryEligible: false` returns 2 (the
      // field AND the mirrored explanatory comment), so a bare-token assertion
      // stays GREEN after the FIELD is deleted — vacuous by construction.
      // The leading indent and the trailing comma are both load-bearing: only
      // an object-literal property can produce them, and a comment line cannot.
      expect(src).toMatch(/^\s+retryEligible: false,$/m);
    },
  );
});

// A1 pin 3 — the class table is single-sourced in scripts/cron-artifact-age.sh.
// Without this, the shell detector's `class` column and the handlers' compiled
// class arms are two independent rosters that drift silently — which is exactly
// how cron-content-generator came to be classified A in the detector while its
// prompt carries two no-artifact stop paths (ADR-126 amendment, R3).
describe("#6750 A1 pin 3 — the shell class table matches the handlers' class arms", () => {
  const AGE_SCRIPT = resolve(__dirname, "../../../../../scripts/cron-artifact-age.sh");

  /** name -> "A" | "B", parsed from the detector's pipe-delimited producer table. */
  const shellClasses = (): Map<string, string> => {
    const out = new Map<string, string>();
    for (const line of readFileSync(AGE_SCRIPT, "utf-8").split("\n")) {
      // name|cron_expr|interval_days|class|anchor_regex
      const m = /^(cron-[a-z-]+)\|[^|]*\|[^|]*\|([AB])\|/.exec(line);
      if (m) out.set(m[1], m[2]);
    }
    return out;
  };

  it("parses a non-empty table (guards against a silent regex/format drift)", () => {
    const t = shellClasses();
    expect(t.size).toBeGreaterThanOrEqual(9);
  });

  it("classifies cron-content-generator as B — it has two prompt-mandated no-artifact exits (R3)", () => {
    // A near-miss pin on the ONE row this PR corrects. Under the old value (A)
    // a legitimate no-topic / failed-citations run would false-RED the monitor.
    expect(shellClasses().get("cron-content-generator")).toBe("B");
  });

  // F6 — the `class` column was single-sourced; `anchor_regex` was not, and it
  // is the more load-bearing of the two: the freshness probe's soundness AND the
  // detector's staleness measurement both rest on it. A handler renaming its
  // COMMIT_MESSAGE updates its own probe automatically and silently desyncs the
  // detector, which then pages at 22d for a healthy producer.
  it("each handler's COMMIT_MESSAGE matches the detector's anchor_regex column", () => {
    const rows = new Map<string, string>();
    for (const line of readFileSync(AGE_SCRIPT, "utf-8").split("\n")) {
      const m = /^(cron-[a-z-]+)\|[^|]*\|[^|]*\|[AB]\|(.+)$/.exec(line);
      if (m) rows.set(m[1], m[2]);
    }
    let checked = 0;
    for (const file of MIGRATED_PROMPT) {
      const name = file.replace(/\.ts$/, "");
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      const cm = /^const COMMIT_MESSAGE = "([^"]+)";$/m.exec(src);
      if (!cm) continue; // community-monitor predates the const; covered by its own suite
      const anchor = rows.get(name);
      expect(anchor, `${name} missing from cron-artifact-age.sh`).toBeDefined();
      // The shell column is an ERE anchored at ^; unescape it and require it to
      // be a prefix of what the handler actually commits.
      const unescaped = anchor!.replace(/^\^/, "").replace(/\\([().])/g, "$1");
      expect(
        cm[1].startsWith(unescaped),
        `${name}: handler commits "${cm[1]}" but the detector anchors on "${anchor}"`,
      ).toBe(true);
      checked += 1;
    }
    expect(checked).toBe(7);
  });

  it("agrees with each handler's compiled class arm for every MIGRATED_PROMPT cron", () => {
    const table = shellClasses();
    let checked = 0;
    for (const file of MIGRATED_PROMPT) {
      const name = file.replace(/\.ts$/, "");
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      const shellClass = table.get(name);
      expect(shellClass, `${name} missing from cron-artifact-age.sh`).toBeDefined();
      // The handler declares its own class as a single source-visible literal
      // so the two rosters are mechanically comparable.
      const m = /^export const PRODUCER_CLASS = "([AB])";$/m.exec(src);
      expect(m, `${name} declares no PRODUCER_CLASS`).not.toBeNull();
      expect(m![1], `${name}: shell says ${shellClass}, handler says ${m![1]}`).toBe(shellClass);
      checked += 1;
    }
    // Cardinality: the loop must actually have run for the whole cohort.
    expect(checked).toBe(MIGRATED_PROMPT.length);
  });
});

// #6750 AC6b — the ANTI-VACUITY gate on the dedup hardening itself.
//
// digestCommittedOnDefaultBranch is an EXISTENCE probe. Pointed at a DATE-NAMED
// path it proves "this run's artifact landed"; pointed at a directory or a
// permanent file it returns 200 forever and becomes a guard that can never fail
// — which would reproduce the always-green defect INSIDE its own fix. This test
// is the thing that stops a future handler from taking the easy wrong arm.
describe("#6750 AC6b — the existence probe is only used where it can actually fail", () => {
  const COHORT = MIGRATED_PROMPT.filter((f) => f !== "cron-community-monitor.ts");

  it("exactly ONE cohort handler uses the existence probe, and it is the date-named producer", () => {
    const users = COHORT.filter((f) =>
      /digestCommittedOnDefaultBranch\(/.test(readFileSync(join(FUNCTIONS_DIR, f), "utf-8")),
    );
    expect(users).toEqual(["cron-growth-audit.ts"]);
  });

  it("the other six use the FRESHNESS probe", () => {
    const users = COHORT.filter((f) =>
      /artifactCommittedSince\(/.test(readFileSync(join(FUNCTIONS_DIR, f), "utf-8")),
    );
    expect(users).toHaveLength(6);
    expect(users).not.toContain("cron-growth-audit.ts");
  });

  it("NEGATIVE: no existence probe is passed a directory or an undated path", () => {
    // FAIL-CLOSED. The previous form extracted `path:` with a regex that assumed
    // it was the FIRST key; reordering the object literal made it match zero
    // calls, the loop body never ran, and BOTH assertions silently skipped —
    // leaving growth-audit's only dedup guard unguarded. A gate on vacuity that
    // is itself vacuity-prone is the defect this PR exists to close, so the
    // per-file cardinality assertion below is the load-bearing line.
    let inspected = 0;
    for (const file of COHORT) {
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      // Capture the whole call BODY, order-independently, then pull `path:` out.
      const calls = [...src.matchAll(/digestCommittedOnDefaultBranch\(\{([\s\S]*?)\}\)/g)];
      const declares = /digestCommittedOnDefaultBranch\(/.test(src);
      expect(
        calls.length > 0,
        `${file}: calls digestCommittedOnDefaultBranch but the gate could not parse it — the gate is DISENGAGED`,
      ).toBe(declares);
      for (const [, body] of calls) {
        const m = /(?:^|\n)\s*path:\s*([^\n]+?),\s*$/m.exec(body);
        expect(m, `${file}: no path: argument found in the call body`).not.toBeNull();
        const arg = m![1];
        // A directory argument can never 404 once the directory exists.
        expect(arg.trimEnd().replace(/[`"']/g, "")).not.toMatch(/\/$/);
        // Nor may it be a bare directory CONSTANT — the source-text check above
        // cannot see through an identifier.
        expect(arg).not.toMatch(/^\s*[A-Z_]+\s*$/);
        // The path MUST vary per run, or the probe is a constant-true guard. The
        // only sanctioned source of that variance is the run date.
        expect(arg).toMatch(/runStartedAt\.slice\(0, 10\)/);
        inspected += 1;
      }
    }
    // Cardinality: exactly one cohort handler uses the existence probe.
    expect(inspected).toBe(1);
  });

  // F1 — the SYMMETRIC gate for the freshness probe, which the original AC6b
  // omitted: the PR built an anti-vacuity gate for the 1 existence-probe
  // producer and none for the 6 freshness-probe producers, i.e. the majority
  // path. `sinceIso` is what makes it a FRESHNESS probe rather than an
  // existence probe; pinning it to 1970 made it match forever and survived the
  // whole suite.
  it("NEGATIVE: every freshness probe binds its window AND its anchor to the run date", () => {
    let inspected = 0;
    for (const file of COHORT) {
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      const calls = [...src.matchAll(/artifactCommittedSince\(\{([\s\S]*?)\}\)/g)];
      const declares = /artifactCommittedSince\(/.test(src);
      expect(
        calls.length > 0,
        `${file}: calls artifactCommittedSince but the gate could not parse it — the gate is DISENGAGED`,
      ).toBe(declares);
      for (const [, body] of calls) {
        const since = /(?:^|\n)\s*sinceIso:\s*([^\n]+?),\s*$/m.exec(body);
        expect(since, `${file}: no sinceIso argument`).not.toBeNull();
        expect(since![1]).toMatch(/runStartedAt\.slice\(0, 10\)/);
        const prefix = /(?:^|\n)\s*anchorPrefix:\s*([^\n]+?),\s*$/m.exec(body);
        expect(prefix, `${file}: no anchorPrefix argument`).not.toBeNull();
        // Date-bound anchor: a message-only anchor matches a PREVIOUS day's
        // artifact that merged after midnight (safeCommitAndPr defaults to
        // auto-merge, so the commit lands on main hours after the run).
        expect(prefix![1]).toMatch(/runStartedAt\.slice\(0, 10\)/);
        inspected += 1;
      }
    }
    expect(inspected).toBe(6);
  });
});
