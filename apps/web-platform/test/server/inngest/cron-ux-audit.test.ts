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
    expect(SUT_SOURCE).toContain("postSentryHeartbeat({ ok: true");
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
    expect(SUT_SOURCE).not.toMatch(/npm_config_offline\s*:/);
  });

  it("wires the env as an exact literal on the (sole) mcpServers.playwright npx config", () => {
    // The env must ride the MCP-server config the cron writes to .mcp.json so
    // the spawned npx inherits it. There is exactly one mcpServers block (sweep
    // confirmed), so the exact env literal next to the npx command is the
    // co-location proof; assert the literal value is "true" (string, as npm reads
    // npm_config_* env vars), not a bare boolean.
    expect(SUT_SOURCE).toContain('env: { npm_config_prefer_offline: "true" }');
    expect(SUT_SOURCE).toContain('command: "npx"');
  });
});
