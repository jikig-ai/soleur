// TR9 Phase-2 — cron-content-vendor-drift registration smoke + source-shape anchors.
//
// Test coverage:
//   1. Registration shape (cron + manual-trigger event triggers, concurrency,
//      retries) — drift here breaks the Inngest scheduler contract.
//   2. Source-shape anchors — verbatim strings from the implementation that
//      must survive silent refactoring.
//   3. Exported constants (SYNTHETIC_CHECK_NAMES, MAX_RUN_DURATION_MS,
//      ISSUE_EXIT_CODES, NOTICE_FILE_REL, CLASSIFIER_REL, PARSER_REL).
//   4. Trust-model routing: ISSUE_EXIT_CODES set shape.

import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronContentVendorDrift,
  MAX_RUN_DURATION_MS,
  ISSUE_EXIT_CODES,
  NOTICE_FILE_REL,
  PARSER_REL,
  CLASSIFIER_REL,
  SKILL_PREFIX,
} from "@/server/inngest/functions/cron-content-vendor-drift";
// #5111: consolidated into the safe-commit helper (was a per-cron copy).
import { SYNTHETIC_CHECK_NAMES } from "@/server/inngest/functions/_cron-safe-commit";
import {
  mayAttestFreshness,
  heartbeatOk,
  couldNotMeasure,
  classifyFileComparison,
  STALENESS_WARN_DAYS,
  WRITE_SUPPRESSION_DAYS,
  type ComparisonTotals,
} from "@/server/inngest/functions/cron-content-vendor-drift";

// =============================================================================
// Registration smoke
// =============================================================================

describe("cronContentVendorDrift — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronContentVendorDrift).toBeDefined();
    expect(typeof cronContentVendorDrift).toBe("object");
  });
});

// =============================================================================
// Source-shape anchors
// =============================================================================

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-content-vendor-drift.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-content-vendor-drift"', "canonical function id"],
    ['cron: "17 11 * * 1"', "Monday 11:17 off-peak schedule"],
    [
      'event: "cron/content-vendor-drift.manual-trigger"',
      "operator manual trigger",
    ],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("handler source-shape anchors", () => {
  it.each([
    ["scheduled-content-vendor-drift", "Sentry monitor slug"],
    ["plugins/soleur/skills/gdpr-gate/NOTICE", "NOTICE file path"],
    [
      "plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh",
      "parser script path",
    ],
    [
      "plugins/soleur/skills/gdpr-gate/scripts/vendor-drift-classify.sh",
      "classifier script path",
    ],
    [
      "chore(vendor-drift): re-vendor gosprinto/compliance-skills",
      "commit message",
    ],
    ["vendor-pin-drift-resolution.md", "runbook reference"],
    ["mintInstallationToken", "token minting"],
    ["setupEphemeralWorkspace", "workspace setup"],
    ["teardownEphemeralWorkspace", "workspace teardown"],
    ["postSentryHeartbeat", "heartbeat at end"],
    ["reportSilentFallback", "Sentry mirror on error"],
    ["ensureLabels", "label creation"],
    ["vendor/pin-drift", "drift label"],
    ["vendor/license-changed", "license drift label"],
    ["vendor/upstream-archived", "archived label"],
    ["vendor/upstream-rollback", "rollback label"],
    ["vendor/cron-failure", "cron failure label"],
    ["compliance/critical", "compliance label"],
    ["needs-human-review", "human review label"],
    [
      "drift requires human re-vendor",
      "trust model routing explanation",
    ],
    ["Ref #3517", "issue reference"],
  ])("contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("handler-side persistence (#5111)", () => {
  it("routes the PR path through safeCommitAndPr with direct merge, labels, and synthetic checks", () => {
    expect(SUT_SOURCE).toContain('from "./_cron-safe-commit"');
    expect(SUT_SOURCE).toMatch(/safeCommitAndPr\(\{/);
    expect(SUT_SOURCE).toContain('mergeMode: "direct"');
    expect(SUT_SOURCE).toContain("syntheticChecks");
    expect(SUT_SOURCE).toContain("prLabels: detectResult.labels");
    // Directory allowlist entry carries the trailing slash the helper's
    // startsWith matching requires; NOTICE is an exact-file entry.
    expect(SUT_SOURCE).toContain(
      "allowedPaths: [`${SKILL_PREFIX}/NOTICE`, `${SKILL_PREFIX}/references/`]",
    );
    // The private staging pipeline must not return.
    expect(SUT_SOURCE).not.toContain("spawnGitChecked");
  });
});

// =============================================================================
// Exported constants
// =============================================================================

describe("exported constants", () => {
  it("MAX_RUN_DURATION_MS is 15 minutes", () => {
    expect(MAX_RUN_DURATION_MS).toBe(15 * 60 * 1000);
  });

  it("SYNTHETIC_CHECK_NAMES has exactly 7 entries", () => {
    expect(SYNTHETIC_CHECK_NAMES.length).toBe(7);
  });

  it("SYNTHETIC_CHECK_NAMES matches the verbatim list", () => {
    expect(SYNTHETIC_CHECK_NAMES).toEqual([
      "test",
      "dependency-review",
      "e2e",
      "skill-security-scan PR gate",
      "enforce",
      "cla-check",
      "cla-evidence",
    ]);
  });

  it("NOTICE_FILE_REL points to gdpr-gate NOTICE", () => {
    expect(NOTICE_FILE_REL).toBe("plugins/soleur/skills/gdpr-gate/NOTICE");
  });

  it("PARSER_REL points to notice-frontmatter.sh", () => {
    expect(PARSER_REL).toBe(
      "plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh",
    );
  });

  it("CLASSIFIER_REL points to vendor-drift-classify.sh", () => {
    expect(CLASSIFIER_REL).toBe(
      "plugins/soleur/skills/gdpr-gate/scripts/vendor-drift-classify.sh",
    );
  });

  it("SKILL_PREFIX is plugins/soleur/skills/gdpr-gate", () => {
    expect(SKILL_PREFIX).toBe("plugins/soleur/skills/gdpr-gate");
  });
});

// =============================================================================
// Trust-model routing: ISSUE_EXIT_CODES
// =============================================================================

describe("ISSUE_EXIT_CODES — trust-model routing", () => {
  it("contains exit codes 10, 11, 12, 15, 16 (security-relevant)", () => {
    expect(ISSUE_EXIT_CODES.has(10)).toBe(true);
    expect(ISSUE_EXIT_CODES.has(11)).toBe(true);
    expect(ISSUE_EXIT_CODES.has(12)).toBe(true);
    expect(ISSUE_EXIT_CODES.has(15)).toBe(true);
    expect(ISSUE_EXIT_CODES.has(16)).toBe(true);
  });

  it("does NOT contain exit code 13 (low-risk batched drift → PR route)", () => {
    expect(ISSUE_EXIT_CODES.has(13)).toBe(false);
  });

  it("does NOT contain exit code 0 (no drift)", () => {
    expect(ISSUE_EXIT_CODES.has(0)).toBe(false);
  });

  it("has exactly 5 entries", () => {
    expect(ISSUE_EXIT_CODES.size).toBe(5);
  });
});

// =============================================================================
// No claude binary spawn
// =============================================================================

describe("no claude binary spawn", () => {
  it("handler source contains no claude spawn references", () => {
    expect(SUT_SOURCE).not.toMatch(/CLAUDE_BIN/);
    expect(SUT_SOURCE).not.toMatch(/resolveClaudeBin/);
    expect(SUT_SOURCE).not.toMatch(/spawnClaudeEval/);
    expect(SUT_SOURCE).not.toMatch(/--allowedTools/);
  });
});


// =============================================================================
// Guard 3 — the attestation writer (#7710)
// =============================================================================
//
// Property: `last-verified` advances only as the recorded consequence of a
// comparison THIS RUN performed, over the COMPLETE registry, that returned
// zero drift AND zero errors.
//
// The assembly is the comparison's returned TOTALS — not either
// `return { drift: "none" }` statement. The property quantifies over every
// exit: clean, drifted, drift-detected-but-classifier-zero, comparison failed,
// partial. That is why the predicate is a pure exported function rather than
// an inline conditional: an inline one could only be grep-asserted, and a grep
// cannot quantify over exits.

describe("mayAttestFreshness — Guard 3 write predicate", () => {
  const clean: ComparisonTotals = {
    registryCount: 8,
    filesExamined: 8,
    filesSame: 8,
    filesDrifted: 0,
    filesError: 0,
    upstreamRepoState: "ok",
  };

  it("permits the write on a complete, clean, error-free comparison", () => {
    expect(mayAttestFreshness(clean)).toBe(true);
  });

  // Matrix row 1. The mutation this forbids is keying the write on
  // `detectResult.drift === "none"`, which is TRUTHY at the classifyRc===0
  // return — reached AFTER drift was detected. Expressed here as totals: a run
  // that found drift must never attest, whatever verdict accompanied it.
  it("refuses when drift was detected, even if a verdict said none", () => {
    expect(mayAttestFreshness({ ...clean, filesSame: 7, filesDrifted: 1 })).toBe(
      false,
    );
  });

  // Matrix row 2. An unfetchable file scored as SAME is the false-clean arm.
  it("refuses when any file could not be compared", () => {
    expect(
      mayAttestFreshness({ ...clean, filesSame: 7, filesError: 1 }),
    ).toBe(false);
  });

  // Matrix row 3. A partial comparison is not evidence of currency.
  it("refuses a partial comparison", () => {
    expect(
      mayAttestFreshness({ ...clean, filesExamined: 5, filesSame: 5 }),
    ).toBe(false);
  });

  // This is the exact shape the registry undercount produced for 117 days:
  // five of eight compared, all SAME, zero errors — clean-looking, and not
  // evidence about the three files it never looked at.
  it("refuses the 5-of-8 shape that #7710 shipped", () => {
    expect(
      mayAttestFreshness({
        registryCount: 8,
        filesExamined: 5,
        filesSame: 5,
        filesDrifted: 0,
        filesError: 0,
        upstreamRepoState: "ok",
      }),
    ).toBe(false);
  });

  // Matrix row 4 — second member. First file SAME, second DRIFTED: the
  // predicate must key on the TOTAL, not on the first result.
  it("refuses when the SECOND file drifted", () => {
    expect(
      mayAttestFreshness({
        registryCount: 2,
        filesExamined: 2,
        filesSame: 1,
        filesDrifted: 1,
        filesError: 0,
        upstreamRepoState: "ok",
      }),
    ).toBe(false);
  });

  // Matrix row 5 — own dispatch. `0 of 0` is not evidence, and a writer
  // treating it as such is vacuous: it would attest hardest exactly when the
  // registry failed to load.
  it("refuses an empty registry — 0 of 0 is not evidence", () => {
    expect(
      mayAttestFreshness({
        registryCount: 0,
        filesExamined: 0,
        filesSame: 0,
        filesDrifted: 0,
        filesError: 0,
        upstreamRepoState: "ok",
      }),
    ).toBe(false);
  });

  // Harness row (ii): a must-PASS non-canonical input. The predicate consumes
  // totals, so per-file record ORDER cannot reach it — asserted rather than
  // assumed, since an implementation that reduced over an ordered array could
  // regress here.
  it("is order-independent — totals are a sum, not a sequence", () => {
    const a: ComparisonTotals = {
      registryCount: 3,
      filesExamined: 3,
      filesSame: 3,
      filesDrifted: 0,
      filesError: 0,
      upstreamRepoState: "ok",
    };
    const b: ComparisonTotals = { ...a };
    expect(mayAttestFreshness(a)).toBe(mayAttestFreshness(b));
    expect(mayAttestFreshness(a)).toBe(true);
  });

  // Every conjunct must be independently load-bearing. If dropping one still
  // yields the same verdict on some input, that conjunct is dead code and the
  // predicate is weaker than it reads.
  // P1-A. Every file compares SAME against an archived upstream — the blobs at
  // the pinned SHAs still resolve — so the per-file totals are IDENTICAL to a
  // healthy run. Before this conjunct the cron opened a `compliance/critical`
  // "upstream archived" issue and advanced `last-verified` in the same pass.
  it("refuses when upstream is ARCHIVED, though every file compares SAME", () => {
    expect(mayAttestFreshness({ ...clean, upstreamRepoState: "archived" })).toBe(
      false,
    );
  });

  it("refuses when upstream was RENAMED", () => {
    expect(mayAttestFreshness({ ...clean, upstreamRepoState: "renamed" })).toBe(
      false,
    );
  });

  // "I could not reach the repo" is not evidence the repo is fine, and it is
  // also not evidence it is archived — it is its own state, and it refuses.
  it("refuses when the repo-meta probe could not answer", () => {
    expect(
      mayAttestFreshness({ ...clean, upstreamRepoState: "unreachable" }),
    ).toBe(false);
  });

  it("has no redundant conjunct — each one alone flips a clean verdict", () => {
    expect(mayAttestFreshness({ ...clean, registryCount: 0, filesExamined: 0 })).toBe(false);
    expect(mayAttestFreshness({ ...clean, filesExamined: 7 })).toBe(false);
    expect(mayAttestFreshness({ ...clean, filesDrifted: 1 })).toBe(false);
    expect(mayAttestFreshness({ ...clean, filesError: 1 })).toBe(false);
    expect(
      mayAttestFreshness({ ...clean, upstreamRepoState: "archived" }),
    ).toBe(false);
  });
});

describe("couldNotMeasure — states with no route", () => {
  const clean: ComparisonTotals = {
    registryCount: 8,
    filesExamined: 8,
    filesSame: 8,
    filesDrifted: 0,
    filesError: 0,
    upstreamRepoState: "ok",
  };

  it("is false on a clean measurement", () => {
    expect(couldNotMeasure(clean)).toBe(false);
  });

  it("is false when drift was found — drift IS a measurement", () => {
    expect(couldNotMeasure({ ...clean, filesSame: 7, filesDrifted: 1 })).toBe(
      false,
    );
    expect(couldNotMeasure({ ...clean, upstreamRepoState: "archived" })).toBe(
      false,
    );
  });

  // Each of these produces no issue, no PR and no artifact. Without this
  // predicate they end in a GREEN check-in with nothing behind it.
  it("is true when the registry could not be read", () => {
    expect(couldNotMeasure({ ...clean, registryCount: 0, filesExamined: 0 })).toBe(
      true,
    );
  });

  it("is true on a partial comparison", () => {
    expect(couldNotMeasure({ ...clean, filesExamined: 5 })).toBe(true);
  });

  it("is true when any file errored", () => {
    expect(couldNotMeasure({ ...clean, filesError: 1 })).toBe(true);
  });

  it("is true when the repo probe could not answer", () => {
    expect(
      couldNotMeasure({ ...clean, upstreamRepoState: "unreachable" }),
    ).toBe(true);
  });
});

describe("heartbeatOk — Guard 3 row 6", () => {
  // The monitor tracks the ARTIFACT's age, not whether this run merged.
  //
  // Keying on the merge was measured to be wrong on the DOMINANT path: the
  // sibling mergeMode:"direct" cron's PRs (#4083/#3766/#3468) each armed
  // auto-merge 6s after creation and merged 54-69s later, i.e. after the run
  // ended. A merge-keyed heartbeat would have paged on every healthy run.
  it("is healthy when the artifact is inside the banner window", () => {
    expect(heartbeatOk(false, true, 7)).toBe(true);
    expect(heartbeatOk(false, true, STALENESS_WARN_DAYS - 1)).toBe(true);
  });

  it("is UNHEALTHY once the artifact reaches the banner threshold", () => {
    expect(heartbeatOk(false, true, STALENESS_WARN_DAYS)).toBe(false);
    expect(heartbeatOk(false, true, 117)).toBe(false);
  });

  it("is healthy on the ordinary PR-opened-not-yet-merged path", () => {
    // The write happened, the merge lands seconds later. Age is still fresh
    // because the previous cycle landed; nothing is wrong.
    expect(heartbeatOk(false, true, 21)).toBe(true);
  });

  it("is healthy when the run was never eligible — drift has its own routes", () => {
    expect(heartbeatOk(false, false, null)).toBe(true);
    expect(heartbeatOk(false, false, 999)).toBe(true);
  });

  it("is UNHEALTHY whenever the run could not measure, regardless of age", () => {
    expect(heartbeatOk(true, true, 0)).toBe(false);
    expect(heartbeatOk(true, false, 0)).toBe(false);
  });

  it("is UNHEALTHY when the field it attests could not be read", () => {
    expect(heartbeatOk(false, true, null)).toBe(false);
  });

  // The margin the suppression leaves. One missed run stays inside the
  // window; two do not, which is the intended alarm.
  it("leaves the suppression window inside the banner threshold", () => {
    expect(WRITE_SUPPRESSION_DAYS).toBeLessThan(STALENESS_WARN_DAYS);
    expect(heartbeatOk(false, true, WRITE_SUPPRESSION_DAYS + 7)).toBe(true);
    expect(heartbeatOk(false, true, WRITE_SUPPRESSION_DAYS + 14)).toBe(false);
  });
});

describe("handler source-shape — the write is totals-gated (#7710)", () => {
  // Complements the behavioural tests above: they prove the PREDICATE is
  // correct, this proves the HANDLER calls it rather than reimplementing the
  // decision inline or keying on the verdict.
  const src = readFileSync(
    resolve(
      __dirname,
      "../../../server/inngest/functions/cron-content-vendor-drift.ts",
    ),
    "utf8",
  );

  it("gates the attestation on mayAttestFreshness, not on detectResult.drift", () => {
    expect(src).toMatch(
      /const attestationEligible = mayAttestFreshness\(detectResult\);/,
    );
    // Anchored on the assignment, not on a bare token: `drift === "none"`
    // legitimately appears in the status mapping on the return line.
    expect(src).not.toMatch(
      /attestationEligible\s*=\s*[^;]*detectResult\.drift/,
    );
  });

  it("routes the attestation through safeCommitAndPr with direct merge", () => {
    // Slice BOUNDED to the attest step. Running to EOF also swallows the
    // drift route's own `mergeMode: "direct"`, so the assertion could be
    // satisfied by the wrong call site (found while mutation-proving).
    const attestStart = src.indexOf('step.run("attest-freshness"');
    const attestEnd = src.indexOf("attestationPrNumber = attestation.pr");
    expect(attestStart).toBeGreaterThan(-1);
    expect(attestEnd).toBeGreaterThan(attestStart);
    const step = src.slice(attestStart, attestEnd);
    expect(step).toMatch(/safeCommitAndPr\(/);
    // Anchored at line-start on the property assignment: the same slice
    // contains a comment quoting `mergeMode: "direct"`, so a bare match
    // survives changing the actual option (measured during #7710 review).
    expect(step).toMatch(/^\s*mergeMode: "direct",$/m);
    // allowedPaths must be the NOTICE alone — an attestation must not be able
    // to carry a content change in on the same commit.
    expect(step).toMatch(/allowedPaths: \[`\$\{SKILL_PREFIX\}\/NOTICE`\]/);
  });

  it("contains no raw push to the default branch", () => {
    expect(src).not.toMatch(/push[^\n]*origin[^\n]*\bmain\b/);
  });

  it("posts the heartbeat with the computed value, never a literal true", () => {
    const hb = src.slice(src.indexOf('step.run("sentry-heartbeat"'));
    expect(hb).toMatch(/ok: isHealthy/);
    expect(hb).not.toMatch(/ok: true/);
  });

  it("keys the heartbeat on the observed artifact age, not on this run's merge", () => {
    // Regression guard: keying on `res.merged` paged on the healthy path,
    // because the direct merge normally fails and auto-merge lands the PR
    // after the run ends.
    expect(src).toMatch(/heartbeatOk\(\s*measurementFailed,/);
    expect(src).not.toMatch(/heartbeatOk\(attestationEligible, wroteAttestation\)/);
  });

  it("emits the accountability summary at a level the sinks keep", () => {
    // logger.info reaches no layer: the Sentry breadcrumb mirror keeps
    // >= warn and the Vector pipeline drops pino level < 40.
    const sum = src.slice(src.indexOf('step.run("attestation-summary"'));
    expect(sum).toMatch(/logger\.warn\(/);
    expect(sum).not.toMatch(/logger\.info\(/);
  });

  it("no longer claims last-verified is bumped at PR-creation time", () => {
    // The drift PR body asserted this on every PR it opened, while nothing had
    // done it since #4483.
    expect(src).not.toMatch(/last-verified bumped at PR-creation time/);
  });

  it("routes per-file scoring through classifyFileComparison", () => {
    // Anchored on the CALL, not on a counter increment: the loop has three
    // `filesError += 1` sites, so a bare-token grep for one is satisfied by
    // the others and survives the mutation it exists to catch
    // (cq-assert-anchor-not-bare-token). Measured: that exact bare-token form
    // survived Guard 3's M-loop mutation.
    expect(src).toMatch(
      /const verdict = classifyFileComparison\(oldSha, currentSha\);/,
    );
  });

  it("scores an unparseable contents response as ERROR, not SAME", () => {
    // The pre-#7710 form was `if (!currentSha || currentSha === oldSha) continue;`
    // — one branch for two different facts.
    expect(src).not.toMatch(/!currentSha \|\| currentSha === oldSha/);
    expect(src).toMatch(/filesError \+= 1;/);
  });

  it("derives registryCount from DECLARED records, not the emitted view", () => {
    // The tautology this closes: `upstream-files` drops a record missing its
    // upstream SHA, so `upstreamFiles.length` shrinks with `filesExamined`
    // and the completeness conjunct can never fail (#7710 review).
    expect(src).not.toMatch(/const registryCount = upstreamFiles\.length;/);
    expect(src).toMatch(/\["record-count", "lifted-files"\]/);
  });

  it("threads repository-level drift into the predicate", () => {
    expect(src).toMatch(/upstreamRepoState = "archived";/);
    expect(src).toMatch(/upstreamRepoState = "renamed";/);
    expect(src).toMatch(/upstreamRepoState = "unreachable";/);
  });

  it("uses the memoized runStartedAt for the attestation date", () => {
    expect(src).toMatch(/const today = runStartedAt\.slice\(0, 10\);/);
  });

  it("opens the attestation PR OUTSIDE the drift dedup namespace", () => {
    // The detect step dedups the re-vendor route on `ci/content-vendor-drift-`.
    // An attestation PR on that same prefix — the ordinary state, since the
    // direct merge normally falls back to armed auto-merge — would make the
    // next genuine-drift run return `skipped-open-pr` and open nothing, with a
    // green heartbeat. Two reviewers converged on this independently.
    expect(src).toMatch(
      /ATTEST_BRANCH_PREFIX = "ci\/vendor-attest"/,
    );
    expect(src).toMatch(/branchName: `\$\{ATTEST_BRANCH_PREFIX\}-/);
    // The dedup query must still key on the drift prefix, not the attest one.
    expect(src).toMatch(/head:ci\/content-vendor-drift-/);
  });

  it("refuses to stack attestation PRs", () => {
    const step = src.slice(src.indexOf('step.run("attest-freshness"'));
    expect(step).toMatch(/head:\$\{ATTEST_BRANCH_PREFIX\}-/);
    expect(step).toMatch(/attest-pr-already-open/);
  });

  it("keeps the write INSIDE the eligibility guard", () => {
    // Nothing asserted this before: a mutation hoisting the step out of the
    // conditional left every predicate test and every source-shape test green.
    const guardIdx = src.indexOf("if (attestationEligible) {");
    const stepIdx = src.indexOf('step.run("attest-freshness"');
    expect(guardIdx).toBeGreaterThan(-1);
    expect(stepIdx).toBeGreaterThan(guardIdx);
  });

  it("derives the registry size from two independently-derived views", () => {
    // record-count shares its opener predicate with _emit_files, so deleting
    // an opener shrinks both together (measured: declared 7, emitted 7, one
    // record lost). key-count reads a key the opener predicate never consumes.
    expect(src).toMatch(/\["key-count", "lifted-files", "status"\]/);
    expect(src).toMatch(/Math\.max\(declaredOpeners, declaredStatus\)/);
  });

  it("does not claim a repo rename from a single per-file fetch failure", () => {
    // Anchored on the BLOCK, not on proximity. A `catch[\s\S]{0,200}` window
    // was the first attempt and it survived its own mutation: the
    // explanatory comment inside the catch is longer than the window, so the
    // window never reached the mutated line. That is a guard narrower than
    // the property it names — the defect class this whole PR is about.
    const catchIdx = src.indexOf("} catch (fetchErr) {");
    expect(catchIdx).toBeGreaterThan(-1);
    const loopEnd = src.indexOf("const declaredResult");
    expect(loopEnd).toBeGreaterThan(catchIdx);
    const catchBlock = src.slice(catchIdx, loopEnd);
    // The per-file catch must count the error and invent no repo-level
    // verdict — `driftFlags` is the classifier's repo-level channel.
    expect(catchBlock).toMatch(/filesError \+= 1;/);
    expect(catchBlock).not.toMatch(/^\s*driftFlags\s*=/m);
  });

  it("carries the comparison evidence in the COMMIT MESSAGE, not only the PR body", () => {
    // The repo squash-merges with COMMIT_MESSAGES, so the PR body never lands
    // on main — and ADR-203's Art. 5(2) argument rests on the commit being
    // the record.
    const step = src.slice(src.indexOf('step.run("attest-freshness"'));
    const cm = step.slice(step.indexOf("commitMessage:"), step.indexOf("branchName:"));
    expect(cm).toMatch(/filesSame/);
    expect(cm).toMatch(/filesDrifted/);
    expect(cm).toMatch(/upstreamRepoState/);
  });

  it("populates aggDiffParts — the classifier must receive the diff", () => {
    expect(src).toMatch(/aggDiffParts\.push\(/);
  });
});


describe("classifyFileComparison — Guard 3 row 2 (the false-clean arm)", () => {
  it("scores a matching sha as SAME", () => {
    expect(classifyFileComparison("abc", "abc")).toBe("same");
  });

  it("scores a differing sha as DRIFTED", () => {
    expect(classifyFileComparison("abc", "def")).toBe("drifted");
  });

  // THE mutation that survived a bare-token source grep. A response that
  // arrived without a sha must never be scored SAME: doing so makes an
  // upstream outage read as a verified-clean corpus, and the attestation
  // predicate would then permit a write on evidence that does not exist.
  it("scores a response with NO sha as ERROR, never SAME", () => {
    expect(classifyFileComparison("abc", undefined)).toBe("error");
    expect(classifyFileComparison("abc", "")).toBe("error");
  });

  it("scores an unreadable registry line as ERROR", () => {
    expect(classifyFileComparison(undefined, "def")).toBe("error");
    expect(classifyFileComparison("", "def")).toBe("error");
  });

  it("never returns SAME when either side is missing", () => {
    for (const pinned of [undefined, "", "abc"]) {
      for (const upstream of [undefined, ""]) {
        expect(classifyFileComparison(pinned, upstream)).toBe("error");
      }
    }
  });
});
