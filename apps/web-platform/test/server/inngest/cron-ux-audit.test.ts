// TR9 PR-11/2 (#4464) — cron-ux-audit handler unit tests.
//
// Same shape as cron-legal-audit.test.ts:
//   1. Registration shape smoke (import loads without throwing).
//   2. Prompt-canary anchors from the GHA scheduled-ux-audit.yml prompt.
//   3. Timing constants exported for substrate-extraction parity.

import { describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronUxAudit,
  CLAUDE_CODE_FLAGS,
  KILL_ESCALATION_MS,
  MAX_TURN_DURATION_MS,
} from "@/server/inngest/functions/cron-ux-audit";
import { CRON_MCP_ALLOWLISTS } from "@/server/inngest/functions/_cron-claude-eval-substrate";

describe("cronUxAudit — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronUxAudit).toBeDefined();
    expect(typeof cronUxAudit).toBe("object");
  });
});

describe("cronUxAudit — exported timing constants", () => {
  it("MAX_TURN_DURATION_MS is 50 minutes (matches sibling claude-eval crons)", () => {
    expect(MAX_TURN_DURATION_MS).toBe(50 * 60 * 1000);
  });

  it("KILL_ESCALATION_MS is 5 seconds (SIGTERM → SIGKILL grace)", () => {
    expect(KILL_ESCALATION_MS).toBe(5_000);
  });
});

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-ux-audit.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-ux-audit"', "canonical function id"],
    ['cron: "0 9 1 * *"', "monthly 1st @ 09:00 UTC schedule"],
    ['event: "cron/ux-audit.manual-trigger"', "operator manual trigger"],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm on agent-loop failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("UX_AUDIT_PROMPT — anchor strings (regression-detection)", () => {
  it.each([
    ["Run /soleur:ux-audit", "skill-invocation directive"],
    ["MILESTONE RULE", "rule keyword"],
    ["CAP_OPEN_ISSUES = 20", "open-issue cap enforcement"],
    ["CAP_PER_RUN     = 5", "per-run severity-ranked cap"],
    ["Injection safety:", "agent-output interpolation guard"],
    ["UX_AUDIT_DRY_RUN", "dry-run env var reference"],
    ["route-list.yaml", "route list reference"],
  ])("contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("#4730 — heartbeat decoupled from claude exit code (best-effort)", () => {
  it("success-path heartbeat is liveness (ok: true), not the bare spawn exit code", () => {
    // Findings upload is conditional ("No findings.json found — skipping
    // upload"), so a clean run with no findings is NORMAL. The monitor's
    // liveness contract is "pipeline ran end-to-end without an INFRA fault" —
    // decoupled from claude's exit. Mirrors cron-bug-fixer.ts (PR #4727). The
    // pre-fix line was the forbidden `ok: spawnResult.ok`.
    expect(SUT_SOURCE).not.toContain("ok: spawnResult.ok");
    // #5674 classify-fatal: the final heartbeat is gated on decision.ok from
    // resolveBestEffortEvalOk (green on clean/benign, red on a fatal class),
    // NOT an unconditional `ok: true`.
    expect(SUT_SOURCE).toContain("resolveBestEffortEvalOk(spawnResult)");
    expect(SUT_SOURCE).toContain("postSentryHeartbeat({ ok: decision.ok");
    // A FATAL class (credit/auth/spawn/timeout) reports + flips the monitor red.
    expect(SUT_SOURCE).toContain('op: "claude-eval-fatal"');
  });

  it("surfaces the non-zero exit as a non-paging WARNING Sentry event (off-host visible)", () => {
    // warnSilentFallback (queryable WARNING), NOT a bare logger.warn — see
    // cq-silent-fallback-must-mirror-to-sentry / hr-observability-layer-citation.
    expect(SUT_SOURCE).toContain("warnSilentFallback");
    expect(SUT_SOURCE).toContain('op: "claude-eval-nonzero-noop"');
  });
});

describe("#5199 — restored containment (token narrow + pinned mcp + live dry-run)", () => {
  it("mints the narrowed ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS token (not the full grant)", () => {
    expect(SUT_SOURCE).toContain("ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS");
    expect(SUT_SOURCE).toMatch(/repositories:\s*\[REPO_NAME\]/);
  });

  it("pins @playwright/mcp to an exact version (no @latest supply-chain fetch)", () => {
    expect(SUT_SOURCE).not.toContain("@playwright/mcp@latest");
    expect(SUT_SOURCE).toContain("@playwright/mcp@0.0.75");
  });

  it("wires UX_AUDIT_DRY_RUN from env (live by default) — not hardcoded true", () => {
    expect(SUT_SOURCE).not.toContain('UX_AUDIT_DRY_RUN: "true"');
    expect(SUT_SOURCE).toContain("process.env.UX_AUDIT_DRY_RUN");
  });
  // NOTE: the deferIfTier2Cron guard is KEPT (defensive no-op once removed from
  // the set) to mirror the restored cron-legal-audit / cron-agent-native-audit
  // pattern — the restore is proven by TIER2_DEFERRED_CRONS not having the cron
  // (cron-shared.test.ts), not by deleting the guard.

  it("the mcp__playwright__* tools in --allowedTools match CRON_MCP_ALLOWLISTS exactly (parity, no drift)", () => {
    // --allowedTools is what the CLI OFFERS; CRON_MCP_ALLOWLISTS is what the
    // containment hook PERMITS. They must agree or ux-audit silently degrades
    // (a tool offered-but-denied fails mid-run; a tool permitted-but-not-offered
    // is a dead grant). Derive the offered set from the source-of-truth flag.
    const allowedToolsIdx = CLAUDE_CODE_FLAGS.indexOf("--allowedTools");
    expect(allowedToolsIdx).toBeGreaterThan(-1);
    const offered = CLAUDE_CODE_FLAGS[allowedToolsIdx + 1]
      .split(",")
      .filter((t) => t.startsWith("mcp__"))
      .sort();
    const permitted = [...CRON_MCP_ALLOWLISTS["cron-ux-audit"].tools].sort();
    expect(offered).toEqual(permitted);
  });
});

describe("#5691 — Playwright survives --strict-mcp-config (substrate prepends it)", () => {
  // The substrate (spawnClaudeEval) now prepends --strict-mcp-config, which
  // ignores ALL MCP configs except those named via --mcp-config. ux-audit is
  // the one cron that legitimately needs an MCP server (Playwright), so it MUST
  // re-supply it explicitly or it silently loses every mcp__playwright__* tool
  // and posts a zero-screenshot exit-0 GREEN run (the runtime Sentry Crons
  // monitor is liveness-only and cannot catch this — obs P1-c). This static
  // assertion is the PRIMARY pre-merge guard against that silent-degradation.
  it("re-supplies the Playwright MCP server via --mcp-config .mcp.json, before the trailing --", () => {
    const mcpIdx = CLAUDE_CODE_FLAGS.indexOf("--mcp-config");
    expect(mcpIdx).toBeGreaterThan(-1);
    // The relative .mcp.json resolves against spawnCwd → the per-fire overlay
    // ux-audit writes at setup (cron-ux-audit.ts:302-307), not the repo-root dev file.
    expect(CLAUDE_CODE_FLAGS[mcpIdx + 1]).toBe(".mcp.json");
    // Must precede the trailing `--` end-of-options marker, else the CLI reads
    // `.mcp.json` as a positional prompt arg rather than a flag value.
    const lastSeparatorIdx = CLAUDE_CODE_FLAGS.lastIndexOf("--");
    expect(lastSeparatorIdx).toBeGreaterThan(-1);
    expect(mcpIdx).toBeLessThan(lastSeparatorIdx);
  });

  it("offers mcp__playwright__* tools — so the re-supplied server is load-bearing, not dead config", () => {
    const allowedToolsIdx = CLAUDE_CODE_FLAGS.indexOf("--allowedTools");
    const offered = CLAUDE_CODE_FLAGS[allowedToolsIdx + 1]
      .split(",")
      .filter((t) => t.startsWith("mcp__playwright__"));
    expect(offered.length).toBeGreaterThan(0);
  });
});

describe("#5676 — npx registry-probe silenced at source (intended-drop, ADR-052 amendment)", () => {
  // #5199 deliberately keeps registry.npmjs.org OFF the egress allowlist so
  // @playwright/mcp resolves to the image-baked dep, not a runtime fetch. But
  // bare `npx` still performs a registry-metadata dial on spawn, which the
  // firewall correctly drops — generating steady, by-design `egress-blocked`
  // noise (#5676, the dominant 104.16.x.34 Cloudflare-anycast pool = npmjs.org).
  // Source-silence: pass npm_config_prefer_offline so npx uses the baked cache
  // and skips the registry dial when cache-warm. prefer-offline (NOT offline) so
  // a cache miss degrades to today's behavior rather than hard-failing the cron.
  it("the Playwright MCP npx entry sets npm_config_prefer_offline so no registry-metadata dial fires when cache-warm", () => {
    expect(SUT_SOURCE).toContain("npm_config_prefer_offline");
    // prefer-offline degrades gracefully; `offline` would hard-fail on a cold
    // _cacache (Docker layer pruning can drop it) — must NOT use the hard form.
    // `\b` (not `\s*:`) also catches a JSON-quoted `"npm_config_offline":` form;
    // it can't match the prefer-offline token (no `npm_config_offline` substring
    // exists in `npm_config_prefer_offline`).
    expect(SUT_SOURCE).not.toMatch(/npm_config_offline\b/);
  });

  it("wires the prefer-offline env on the (sole) mcpServers.playwright npx config", () => {
    // The env must ride the MCP-server config the cron writes to .mcp.json so the
    // spawned npx inherits it. Whitespace-tolerant so a prettier reflow (multi-line
    // / brace spacing) doesn't false-RED a behavior-intact config; pins the key +
    // the "true" string value (npm reads npm_config_* env vars as strings).
    expect(SUT_SOURCE).toMatch(
      /env:\s*\{\s*npm_config_prefer_offline:\s*["']true["']\s*\}/,
    );
    // Exactly one mcpServers block (sweep confirmed), so asserting the npx command
    // is also present establishes both ride the same playwright config.
    expect(SUT_SOURCE).toContain('command: "npx"');
  });
});
