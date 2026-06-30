// TR9 Phase 2 — cron-content-generator handler unit tests.
//
// Minimal test coverage focused on load-bearing invariants:
//   1. Registration shape (cron + manual-trigger event triggers, concurrency,
//      retries) — drift here breaks the Inngest scheduler contract.
//   2. Prompt-canary anchors (seo-refresh-queue, content-writer,
//      social-distribute, validate-blog-links, Do NOT run git add) —
//      original anchors from the GHA prompt that must survive silent
//      paraphrasing.
//   3. Timing constants exported (MAX_TURN_DURATION_MS, KILL_ESCALATION_MS).
//   4. buildSpawnEnv allowlist — positive class (5 base vars) AND negative
//      class (sensitive denylist + spread operator).

import { describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE all ES-module imports below — sets NEXT_PHASE so
// the inngest client's startup-key check short-circuits (same path Next.js
// `next build` uses). Mirrors cron-roadmap-review.test.ts.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronContentGenerator,
  KILL_ESCALATION_MS,
  MAX_TURN_DURATION_MS,
} from "@/server/inngest/functions/cron-content-generator";

describe("cronContentGenerator — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronContentGenerator).toBeDefined();
    expect(typeof cronContentGenerator).toBe("object");
  });
});

describe("cronContentGenerator — exported timing constants", () => {
  it("MAX_TURN_DURATION_MS is 55 minutes (from 60 min GHA timeout minus headroom)", () => {
    expect(MAX_TURN_DURATION_MS).toBe(55 * 60 * 1000);
  });

  it("KILL_ESCALATION_MS is 5 seconds (SIGTERM → SIGKILL grace)", () => {
    expect(KILL_ESCALATION_MS).toBe(5_000);
  });
});

// Source-file-content tests — read the SUT file and assert the prompt
// constant contains the verbatim anchors. Per AGENTS.md
// `cq-test-fixtures-synthesized-only`, we read the production source via
// readFileSync rather than synthesising a parallel prompt fixture.

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-content-generator.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors (cross-check the import-time smoke)", () => {
  it.each([
    ['id: "cron-content-generator"', "canonical function id"],
    ['cron: "0 10 * * 2,4"', "Tuesday/Thursday 10:00 UTC schedule"],
    ['event: "cron/content-generator.manual-trigger"', "operator manual trigger"],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm on agent-loop failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("CONTENT_GENERATOR_PROMPT — anchor strings (regression-detection)", () => {
  describe("original GHA-workflow prompt anchors (must survive port)", () => {
    it.each([
      ["seo-refresh-queue", "topic queue source"],
      ["content-writer", "article generation skill"],
      ["social-distribute", "distribution content skill"],
      ["validate-blog-links", "link validation script"],
      ["PERSISTENCE: Do NOT run git add", "platform-persistence directive (#5091)"],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });

  describe("safety-guard anchors (cohort discipline)", () => {
    it.each([
      [
        "Do NOT push directly to main",
        "PR-based commit pattern (no direct main writes)",
      ],
      [
        "opens a PR for your changes",
        "handler-side persistence note (#5091)",
      ],
      [
        "scheduled-content-generator",
        "label name for audit issue",
      ],
      [
        'MILESTONE RULE:',
        "milestone enforcement rule keyword",
      ],
      [
        '@11ty/eleventy',
        "CI Eleventy build validation (referenced as the CI gate, not a local build)",
      ],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });
});

// ---------------------------------------------------------------------------
// #4987 — skill + build-validation degradation fix.
//   (A) CLAUDE_CODE_FLAGS must let the headless `claude --print` eval resolve
//       AND invoke the plugin's /soleur:* skills: `--plugin-dir plugins/soleur`
//       loads the plugin from the clone's own tracked tree (#5091) — a bare
//       plugins/ dir does NOT auto-register
//       in headless mode — see feature-request-plugin-dir-settings.md), and the
//       `--allowedTools` allowlist must include `Skill` (invoke skills) + `Task`
//       (content-writer's fact-checker subagent).
//   (B) STEP 4 build validation cannot run in the no-node_modules shallow clone;
//       it is deferred to the PR's CI gate (which the --auto merge blocks on).
// ---------------------------------------------------------------------------

describe("CLAUDE_CODE_FLAGS — skill + plugin-dir resolution (#4987)", () => {
  const flagsMatch = SUT_SOURCE.match(
    /const CLAUDE_CODE_FLAGS = \[([\s\S]*?)\];/,
  );
  const flagsBlock = flagsMatch ? flagsMatch[1] : "";

  it("CLAUDE_CODE_FLAGS array is present in source", () => {
    expect(flagsBlock.length).toBeGreaterThan(0);
  });

  it("--allowedTools allowlist includes Skill and Task (invoke /soleur:* + fact-checker subagent)", () => {
    expect(SUT_SOURCE).toContain(
      '"Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Skill,Task"',
    );
  });

  it("loads the plugin via --plugin-dir plugins/soleur (clone's own tracked tree — #5091)", () => {
    expect(flagsBlock).toContain('"--plugin-dir"');
    expect(flagsBlock).toContain('"plugins/soleur"');
    expect(flagsBlock).toMatch(/"--plugin-dir",\s*\n\s*"plugins\/soleur",/);
  });

  it("--plugin-dir is positioned BEFORE the load-bearing `--` end-of-options marker", () => {
    // `"--"` (quote-dash-dash-quote) is the standalone marker; `"--print"` etc.
    // never contain it, so indexOf is unambiguous.
    const endMarker = flagsBlock.indexOf('"--"');
    expect(endMarker).toBeGreaterThan(-1);
    expect(flagsBlock.indexOf('"--plugin-dir"')).toBeLessThan(endMarker);
    expect(flagsBlock.indexOf('"plugins/soleur"')).toBeLessThan(endMarker);
  });

  it("does NOT bump the turn budget — --max-turns 50 unchanged", () => {
    expect(SUT_SOURCE).toContain('"--max-turns",\n  "50",');
  });
});

describe("CONTENT_GENERATOR_PROMPT — STEP 4 CI-deferred validation (#4987)", () => {
  // Capture the STEP 4 block (STEP 4 heading → STEP 5 heading) so assertions bind
  // to STEP 4 specifically, not the prompt as a whole. This guards the defect
  // CLASS — a local-build imperative reappearing in STEP 4 under ANY wording —
  // rather than one exact byte-string. Per test-design review of PR #4989.
  const step4Match = SUT_SOURCE.match(/STEP 4 —[\s\S]*?\nSTEP 5 —/);
  const step4 = step4Match ? step4Match[0] : "";

  it("STEP 4 block is present in the prompt", () => {
    expect(step4.length).toBeGreaterThan(0);
  });

  it("STEP 4 defers validation to CI and forbids a local build", () => {
    expect(step4).toMatch(/Validation runs in CI/);
    expect(step4).toContain("no node_modules");
    expect(step4).toMatch(/do NOT build locally/i);
  });

  it("STEP 4 issues no bare local-build imperative (defect-class guard)", () => {
    // No line inside STEP 4 may START with a build/validation command — the old
    // shape was `STEP 4 — Validate:\nnpx @11ty/eleventy\nbash scripts/validate-…`.
    // The Eleventy/link commands may appear ONLY as inline references to the CI
    // gate (e.g. CI runs "npx @11ty/eleventy"), never as a leading imperative.
    expect(step4).not.toMatch(/^\s*npx @11ty\/eleventy/m);
    expect(step4).not.toMatch(/^\s*bash scripts\/validate-blog-links\.sh/m);
  });

  it("STEP 4 still names the CI validation commands (@11ty/eleventy + validate-blog-links)", () => {
    expect(step4).toContain("@11ty/eleventy");
    expect(step4).toContain("validate-blog-links");
  });
});

// ---------------------------------------------------------------------------
// Silence-hole fallback guard (#4960). The handler can terminate without the
// prompt's STEP 6 audit issue (mid-eval crash / API 500 / max-turns kill); the
// `ensure-audit-issue` step creates a self-reported FAILED audit issue so the
// run is never silent and the cron-cloud-task-heartbeat watchdog stays green.
// ---------------------------------------------------------------------------

describe("ensure-audit-issue fallback — source-shape anchors (#4960)", () => {
  it.each([
    ['"ensure-audit-issue"', "handler fallback step id"],
    ["[Scheduled] Content Generator -", "audit-issue title prefix literal"],
    ["scheduled-content-generator", "audit-issue label literal"],
    ["ensure-audit-issue-failed", "reportSilentFallback op for a failed fallback create"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });

  it("fallback step is gated on the output-aware result (heartbeatOk === false)", () => {
    // The create must NOT fire when the prompt already produced an issue. The
    // gate moved into finalizeOutputAwareHeartbeat's onBeforeHeartbeat callback
    // (#5728), which is `undefined` when heartbeatOk is true and only runs the
    // ensure-audit-issue step when red.
    expect(SUT_SOURCE).toMatch(
      /onBeforeHeartbeat:\s*heartbeatOk\s*\?\s*undefined/,
    );
  });

  it("fallback create is wrapped in try/catch → reportSilentFallback (never throws)", () => {
    const stepMatch = SUT_SOURCE.match(
      /"ensure-audit-issue"[\s\S]+?reportSilentFallback\([\s\S]+?op:\s*"ensure-audit-issue-failed"/,
    );
    expect(stepMatch).not.toBeNull();
  });

  it("does NOT bump the turn budget — --max-turns 50 is unchanged (Deliverable 3)", () => {
    expect(SUT_SOURCE).toContain('"--max-turns",\n  "50",');
  });
});

// NOTE: the behavioral coverage for the audit-issue fallback now lives in
// cron-shared.test.ts (`ensureScheduledAuditIssue (shared fallback)`) — the
// helper was extracted into _cron-shared.ts and parameterized for all 8
// always-create producers (#4978). The wiring (the call site + `!heartbeatOk`
// gate) stays guarded by the source-shape anchors above and by
// cron-producer-output-wiring.test.ts.

describe("buildSpawnEnv allowlist (security surface)", () => {
  const buildEnvMatch = SUT_SOURCE.match(
    /function buildSpawnEnv\([\s\S]+?\n\}\n/,
  );
  const buildEnvBody = buildEnvMatch ? buildEnvMatch[0] : "";

  it("buildSpawnEnv function is present in source", () => {
    expect(buildEnvBody.length).toBeGreaterThan(0);
  });

  describe("positive class — base vars MUST be allowlisted", () => {
    it.each([
      "PATH",
      "HOME",
      "NODE_ENV",
      "ANTHROPIC_API_KEY",
    ])("allowlist contains %s", (key) => {
      expect(buildEnvBody).toContain(`${key}: process.env.${key}`);
    });
  });

  describe("negative class — sensitive vars MUST NOT be allowlisted", () => {
    it.each([
      ["DOPPLER_TOKEN", "Doppler service token; full secrets-read on prd"],
      ["GITHUB_APP_PRIVATE_KEY", "GitHub App PEM; full repo write across installations"],
      ["SENTRY_AUTH_TOKEN", "Sentry write API token; full project access"],
      ["SUPABASE_SERVICE_ROLE_KEY", "Supabase service role; bypasses RLS"],
      ["INNGEST_SIGNING_KEY", "Inngest substrate auth; arbitrary event forging"],
      ["INNGEST_EVENT_KEY", "Inngest substrate auth; arbitrary event forging"],
      ["STRIPE_SECRET_KEY", "Stripe API; payment surface"],
      ["RESEND_API_KEY", "Resend email; impersonation surface"],
      ["BYOK_ENCRYPTION_KEY", "Symmetric key for user BYOK secrets"],
    ])("allowlist does NOT contain %s (%s)", (key) => {
      expect(buildEnvBody).not.toContain(key);
    });

    it("allowlist does NOT use ...process.env spread (would defeat allowlist)", () => {
      expect(buildEnvBody).not.toMatch(/\.\.\.process\.env/);
    });
  });
});
