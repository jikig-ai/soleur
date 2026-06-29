// #4689/#4686/#4684 — un-wiring guard for the output-aware heartbeat.
//
// The behavioral contract of resolveOutputAwareOk lives in cron-shared.test.ts.
// THIS file guards the integration points the helper was built for: the three
// always-create producer handlers must feed the OUTPUT-aware result
// (`heartbeatOk`) to postSentryHeartbeat — NOT the bare spawn exit code
// (`ok: spawnResult.ok`), which is the exact pre-fix line the PR replaces.
//
// Without this guard a revert of just the handler wiring (leaving the helper
// intact and green) would pass the entire suite — the helper unit tests can't
// see the call sites. Per cq-test-fixtures-synthesized-only we read the
// production source via readFileSync (the wiring IS the artifact under test)
// and assert the established source-shape anchors, mirroring the convention in
// cron-roadmap-review.test.ts.

import { describe, expect, it } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";

const FN_DIR = resolve(__dirname, "../../../server/inngest/functions");

const WIRED_PRODUCERS = [
  "cron-roadmap-review.ts",
  "cron-content-generator.ts",
  "cron-competitive-analysis.ts",
  // #4730 — the 4 always-create producers among the claude-eval siblings of
  // scheduled-bug-fixer. Each creates a `[Scheduled] …` summary issue every
  // run, so a clean exit that produced no artifact must turn the monitor RED
  // (output-aware) instead of false-green on the bare spawn exit code.
  "cron-growth-audit.ts",
  "cron-growth-execution.ts",
  "cron-seo-aeo-audit.ts",
  "cron-community-monitor.ts",
  // cron-campaign-calendar files a per-overdue `scheduled-campaign-calendar`
  // issue (STEP 2c) AND a heartbeat audit issue with the same label when zero
  // overdue (STEP 2.5) — an artifact lands every run, so it is output-aware.
  "cron-campaign-calendar.ts",
] as const;

// #4730 — the 4 best-effort claude-eval siblings. A non-zero claude exit (or a
// clean run that legitimately files no issue) is the NORMAL outcome for these
// audit/review crons, so they DECOUPLE the heartbeat from the spawn exit code
// (postSentryHeartbeat({ ok: true }) on a clean end-to-end run) and surface the
// non-zero exit as a non-paging WARNING Sentry event — the bug-fixer shape
// (PR #4727), NOT the output-aware producer shape. They legitimately have
// NEITHER `ok: spawnResult.ok` (the forbidden pre-fix line) NOR
// `resolveOutputAwareOk` (the wrong pattern — would false-RED a healthy
// zero-artifact run), exactly like cron-strategy-review's exclusion above.
const BEST_EFFORT_CRONS = [
  "cron-agent-native-audit.ts",
  "cron-legal-audit.ts",
  "cron-ux-audit.ts",
] as const;

describe("output-aware heartbeat wiring (always-create producers)", () => {
  it.each(WIRED_PRODUCERS)(
    "%s gates its heartbeat on output, not the bare spawn exit code",
    (file) => {
      const src = readFileSync(resolve(FN_DIR, file), "utf-8");

      // Calls the output-aware resolver…
      expect(src).toContain("resolveOutputAwareOk(");
      // …captures a replay-stable run window…
      expect(src).toContain('"run-started-at"');
      expect(src).toContain("runStartedAt");
      // …and feeds the RESOLVED result to the heartbeat + the function return.
      // The pre-fix line was `postSentryHeartbeat({ ok: spawnResult.ok, ...})`;
      // post-#5728 the terminal heartbeat is no longer posted inline — it routes
      // through finalizeOutputAwareHeartbeat (memoization-safe, final-attempt
      // gated), so `heartbeatOk` is threaded into the helper and into the
      // `return { ok: heartbeatOk }`.
      expect(src).toContain("ok: heartbeatOk");
      // The success path must NOT still pass the raw spawn result. (The
      // setup-failure early-exit legitimately passes `ok: false`, so we only
      // forbid the spawnResult.ok form specifically.) This anchor intentionally
      // relies on the leading-space `ok:` to distinguish the heartbeat key from
      // the resolver's legitimate `spawnOk: spawnResult.ok` argument (capital
      // O), which producers DO contain — see the toContain("resolveOutputAwareOk(")
      // assertion above.
      expect(src).not.toContain("ok: spawnResult.ok");

      // #5728 — the terminal heartbeat routes through the shared
      // finalizeOutputAwareHeartbeat helper (NOT a second inline postSentryHeartbeat
      // call site, which would double-signal under retry memoization), and the
      // handler body throw + setup-workspace catch BOTH rethrow a benign
      // DeployInProgressError bare (no heartbeat — the ADR-068 fail-safe defer).
      // A revert of just this wiring would otherwise pass the whole suite.
      expect(src).toContain("finalizeOutputAwareHeartbeat(");
      expect(src).toContain("instanceof DeployInProgressError");
      expect(src).toContain('op: "handler-body-threw"');

      // #4773 — the diagnostic triple (exitCode + stderrTail + stdoutTail) must
      // be threaded from the SpawnResult into resolveOutputAwareOk, or the
      // scheduled-output-missing Sentry extra loses the only off-host-visible
      // failure reason (app stdout/stderr are not shipped to Better Stack). A
      // revert of just the threading would otherwise pass the whole suite — this
      // is the same un-wiring-guard rationale as `ok: heartbeatOk` above. The
      // `!?` tolerates the post-#5728 `spawnResult!.X` non-null form (spawnResult
      // is now hoisted as `SpawnResult | null` for the flag pattern).
      expect(src).toMatch(/stderrTail: spawnResult!?\.stderrTail/);
      expect(src).toMatch(/exitCode: spawnResult!?\.exitCode/);
      expect(src).toMatch(/stdoutTail: spawnResult!?\.stdoutTail/);

      // #4960/#4978 — the handler-level silence-hole fallback. When the
      // output-aware check found no labeled issue in the run window (mid-eval
      // crash / API 500 / max-turns kill bypassed the prompt's create step),
      // the handler ITSELF files a FAILED audit issue via the shared
      // ensureScheduledAuditIssue helper so the run is never silent. Post-#5728
      // the gate moved into finalizeOutputAwareHeartbeat's `onBeforeHeartbeat`
      // (run only on the post path, ordered before the single terminal heartbeat,
      // and skipped entirely on a non-final-attempt retry), so the gating shape is
      // `onBeforeHeartbeat: heartbeatOk ? undefined : …` rather than the old
      // `if (!heartbeatOk)`. The create is still wrapped so a fallback failure is
      // reported to Sentry (op:"ensure-audit-issue-failed") not crashing teardown.
      expect(src).toContain("ensureScheduledAuditIssue(");
      expect(src).toContain('"ensure-audit-issue"');
      expect(src).toMatch(/onBeforeHeartbeat:\s*heartbeatOk\s*\?\s*undefined/);
      expect(src).toContain('op: "ensure-audit-issue-failed"');
    },
  );

  it.each(BEST_EFFORT_CRONS)(
    "%s is best-effort: heartbeat decoupled from spawn exit, NOT output-aware",
    (file) => {
      const src = readFileSync(resolve(FN_DIR, file), "utf-8");

      // The forbidden pre-fix line — the bare spawn exit code as the heartbeat.
      expect(src).not.toContain("ok: spawnResult.ok");
      // Best-effort, NOT a producer: must NOT adopt the output-aware resolver
      // (that would false-RED a healthy run that legitimately files nothing).
      expect(src).not.toContain("resolveOutputAwareOk");
      // #5674 classify-fatal: the heartbeat is gated on decision.ok from
      // resolveBestEffortEvalOk — GREEN on a clean/benign run, RED on a FATAL
      // class (credit/auth/spawn/timeout). NOT an unconditional `ok: true`.
      expect(src).toContain("resolveBestEffortEvalOk(spawnResult)");
      expect(src).toContain("postSentryHeartbeat({ ok: decision.ok");
      // A FATAL class reports + flips the monitor red.
      expect(src).toContain('op: "claude-eval-fatal"');
      // A BENIGN non-zero exit IS surfaced — as a queryable, non-paging WARNING
      // Sentry event (off-host-visible), not a bare logger.warn.
      expect(src).toContain("warnSilentFallback");
      expect(src).toContain('op: "claude-eval-nonzero-noop"');

      // #4978 — best-effort crons are NOT output-aware producers, so they must
      // NOT adopt the silence-hole fallback. A clean run that legitimately
      // files no issue is the NORMAL outcome here; firing the fallback would
      // spam FAILED audit issues on every healthy zero-artifact run.
      expect(src).not.toContain("ensureScheduledAuditIssue");
    },
  );

  it("cron-strategy-review is intentionally NOT wired (pure-TS, already output-aware)", () => {
    // strategy-review derives ok from `review.errors === 0` and legitimately
    // creates zero issues on an all-clean run; wiring resolveOutputAwareOk
    // would false-red those healthy runs. Guard the deliberate exclusion so a
    // future "wire all four for symmetry" change has to confront this comment.
    const src = readFileSync(resolve(FN_DIR, "cron-strategy-review.ts"), "utf-8");
    expect(src).not.toContain("resolveOutputAwareOk");
    expect(src).toContain("ok: result.ok");
  });
});

// #4993 — fleet-wide headless /soleur:* skill resolution parity guard.
//
// A headless `claude --print` cron eval can only resolve+invoke a /soleur:*
// plugin skill when its CLAUDE_CODE_FLAGS carry BOTH `--plugin-dir
// plugins/soleur` (registers the symlinked plugin — the interactive
// marketplace/enabledPlugins trust flow is skipped under --print) AND `Skill`
// (+`Task` for skills that fan out subagents) in --allowedTools. #4987/PR #4989
// fixed cron-content-generator (the first instance); this guard makes the fix
// fleet-wide and self-protecting so the gap cannot silently re-open when a NEW
// producer adds a /soleur:* prompt.
//
// SELF-DISCOVERING: rather than 10 near-duplicate per-file test blocks (the
// duplicate-coverage anti-pattern), this reads every cron-*.ts / event-*.ts in
// the functions dir and classifies a file as skill-invoking when it BOTH spawns
// a claude eval (defines CLAUDE_CODE_FLAGS) AND invokes /soleur: in a non-comment
// (prompt) line. That excludes the two text-only false positives
// (cron-nag-4216-readiness, cron-skill-freshness — these define NO
// CLAUDE_CODE_FLAGS, so the CLAUDE_CODE_FLAGS predicate ALONE excludes them;
// their /soleur: text lives in generated issue/nag bodies, not an eval prompt)
// and the four eval producers that carry CLAUDE_CODE_FLAGS but invoke no skill
// (roadmap-review, community-monitor, follow-through-monitor, daily-triage —
// excluded by the prompt-body predicate). The discovered set
// is asserted === the known expected set so a new producer must be classified
// (and flagged) explicitly. content-generator is INCLUDED — it is itself a
// self-discovered skill-invoking producer, so this guard also protects the
// original #4987 fix from regressing.
describe("headless skill resolution parity (#4993)", () => {
  // The authoritative skill-invoking-producer set: every cron/event handler whose
  // eval PROMPT runs a /soleur:* skill. Drift here is intentional friction — a new
  // producer that invokes a skill MUST be added (and carry the flags) or the
  // discovery assertion below fails loud. This list slices the producer corpus on
  // a DIFFERENT axis than WIRED_PRODUCERS / BEST_EFFORT_CRONS above (skill
  // invocation vs. heartbeat-wiring class); the lists overlap by design and are
  // maintained independently.
  const EXPECTED_SKILL_PRODUCERS = [
    "cron-agent-native-audit.ts",
    "cron-bug-fixer.ts",
    "cron-campaign-calendar.ts",
    "cron-competitive-analysis.ts",
    "cron-content-generator.ts",
    "cron-growth-audit.ts",
    "cron-growth-execution.ts",
    "cron-legal-audit.ts",
    "cron-seo-aeo-audit.ts",
    "cron-ux-audit.ts",
    "event-ship-merge.ts",
  ].sort();

  // Strip `//` line comments so a /soleur: mention in a comment (sibling-skill
  // references abound — content-generator's header, and roadmap-review /
  // community-monitor's reconciled "invokes no /soleur:* skill" notes) does not
  // misclassify a file. We deliberately do NOT strip `*`/`/*`-prefixed lines:
  // every real prompt invocation lives on a `Run /soleur:…` line inside a
  // template literal, and stripping `*` would risk silently false-EXCLUDING a
  // future prompt whose text starts with a markdown bullet (`* Run /soleur:…`) —
  // the dangerous-quiet direction (producer ships unguarded, test stays green).
  // Verified: no flag-carrying producer carries /soleur: in a block comment.
  const promptBody = (src: string): string =>
    src
      .split("\n")
      .filter((line) => !line.trim().startsWith("//"))
      .join("\n");

  const discovered = readdirSync(FN_DIR)
    .filter((f) => /^(cron|event)-.*\.ts$/.test(f))
    .filter((f) => {
      const src = readFileSync(resolve(FN_DIR, f), "utf-8");
      return src.includes("CLAUDE_CODE_FLAGS") && promptBody(src).includes("/soleur:");
    })
    .sort();

  it("discovers exactly the known skill-invoking producers (empty-corpus / drift guard)", () => {
    // Non-vacuity: a glob that silently matches nothing must fail loud.
    expect(discovered.length).toBeGreaterThan(0);
    expect(discovered).toEqual(EXPECTED_SKILL_PRODUCERS);
  });

  it.each(EXPECTED_SKILL_PRODUCERS)(
    "%s carries --plugin-dir + Skill + Task in CLAUDE_CODE_FLAGS, plugin-dir before --",
    (file) => {
      const src = readFileSync(resolve(FN_DIR, file), "utf-8");
      const flagsMatch = src.match(/const CLAUDE_CODE_FLAGS = \[([\s\S]*?)\];/);
      const flagsBlock = flagsMatch ? flagsMatch[1] : "";
      expect(flagsBlock.length).toBeGreaterThan(0);

      // Registers the plugin (clone's tracked tree — #5091) (headless --print does not auto-discover it).
      expect(flagsBlock).toContain('"--plugin-dir"');
      expect(flagsBlock).toContain('"plugins/soleur"');
      expect(flagsBlock).toMatch(/"--plugin-dir",\s*\n\s*"plugins\/soleur",/);

      // --allowedTools allowlist must let the eval invoke the skill (Skill) and
      // any subagent the skill fans out (Task). Both must appear in the single
      // allowlist string, not merely somewhere in the block.
      const allowMatch = flagsBlock.match(/"--allowedTools",\s*\n\s*"([^"]*)"/);
      const allowList = allowMatch ? allowMatch[1] : "";
      expect(allowList.split(",")).toContain("Skill");
      expect(allowList.split(",")).toContain("Task");

      // --plugin-dir must precede the load-bearing `--` end-of-options marker.
      const endMarker = flagsBlock.indexOf('"--"');
      expect(endMarker).toBeGreaterThan(-1);
      expect(flagsBlock.indexOf('"--plugin-dir"')).toBeLessThan(endMarker);
      expect(flagsBlock.indexOf('"plugins/soleur"')).toBeLessThan(endMarker);
    },
  );
});
