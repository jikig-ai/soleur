// #5106 — Inngest cron model-tier registry + MODEL_PRICING parity.
//
// Guards the SSOT extraction of the per-cron Anthropic model-ID literals
// into `server/inngest/model-tiers.ts`:
//   (a) no-raw-literal: zero quoted "claude-sonnet-5" / "claude-opus-4-8"
//       string literals on NON-comment code lines across functions/*.ts
//       (the verbatim `--model …` mirrors of GHA `claude_args` live in
//       comments on purpose and are excluded by comment-stripping).
//   (b) sanity: the walk found >= 17 cron/event files (an empty walk
//       cannot pass vacuously).
//   (c) pricing parity: MODEL_PRICING keys === the AnthropicModelId union
//       members (both directions). The union is the only thing that flows
//       through `MODEL_PRICING[leaderModule.model]` at
//       agent-on-spawn-requested.ts:474, so the parity is scoped to the
//       consumed values (sonnet + haiku). If a future PR makes opus
//       reachable through that lookup, widen this assertion + add the
//       opus pricing entry then.
//   (d) identity: EXECUTION_MODEL === SONNET_MODEL and
//       AUDIT_MODEL === "claude-opus-4-8".

import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE the ES-module imports below — sets NEXT_PHASE so
// importing agent-on-spawn-requested (which calls inngest.createFunction at
// module load) short-circuits the inngest client's startup-key check.
// Idiom from cron-roadmap-review.test.ts:19-26.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  SONNET_MODEL,
  HAIKU_MODEL,
} from "@/server/inngest/leader-prompts/constants";
import {
  EXECUTION_MODEL,
  AUDIT_MODEL,
} from "@/server/inngest/model-tiers";
import { MODEL_PRICING } from "@/server/inngest/functions/agent-on-spawn-requested";

const FUNCTIONS_DIR = join(__dirname, "../../../server/inngest/functions");

const RAW_MODEL_LITERAL = /"claude-sonnet-5"|"claude-opus-4-8"/;

/**
 * Blank out comment lines so the verbatim `--model claude-…` GHA-mirror
 * comments are not flagged. Removes block comments wholesale, then blanks any
 * line whose first non-whitespace content begins a comment (`//` or a `*`
 * jsdoc/block continuation). Comment lines are mapped to "" (not filtered) so
 * the surviving line indices still match the real file line numbers in the
 * offender report. Code lines are left intact — never truncated at `//` — so a
 * raw literal preceded by a string containing `//` cannot slip through as a
 * false-negative (fail-safe: an over-strict match is preferable to a missed
 * literal in a drift guard).
 */
function stripComments(src: string): string {
  const noBlock = src.replace(/\/\*[\s\S]*?\*\//g, "");
  return noBlock
    .split("\n")
    .map((line) => {
      const trimmed = line.trimStart();
      return trimmed.startsWith("//") || trimmed.startsWith("*") ? "" : line;
    })
    .join("\n");
}

describe("model-tiers registry — #5106", () => {
  const files = readdirSync(FUNCTIONS_DIR).filter((f) => f.endsWith(".ts"));

  it("walks >= 17 cron/event function files (non-vacuous)", () => {
    expect(files.length).toBeGreaterThanOrEqual(17);
  });

  it("holds zero raw model-ID string literals on code lines", () => {
    const offenders: string[] = [];
    for (const f of files) {
      const code = stripComments(readFileSync(join(FUNCTIONS_DIR, f), "utf8"));
      code.split("\n").forEach((line, i) => {
        if (RAW_MODEL_LITERAL.test(line)) {
          offenders.push(`${f}:${i + 1}: ${line.trim()}`);
        }
      });
    }
    expect(offenders).toEqual([]);
  });

  it("MODEL_PRICING keys exactly equal the AnthropicModelId union members", () => {
    const unionMembers = [SONNET_MODEL, HAIKU_MODEL].sort();
    const pricingKeys = Object.keys(MODEL_PRICING).sort();
    expect(pricingKeys).toEqual(unionMembers);
  });

  it("EXECUTION_MODEL is the sonnet SSOT and AUDIT_MODEL is opus-4-8", () => {
    expect(EXECUTION_MODEL).toBe(SONNET_MODEL);
    expect(EXECUTION_MODEL).toBe("claude-sonnet-5");
    // Intentional model-bump tripwire: AUDIT_MODEL has no SSOT constant to
    // alias (opus is not an AnthropicModelId member), so it is pinned to the
    // literal here. A deliberate re-tier (e.g. opus-4-7 → opus-4-8, a separate
    // model-bump PR per ADR-053) must update this assertion in lockstep.
    expect(AUDIT_MODEL).toBe("claude-opus-4-8");
  });
});
