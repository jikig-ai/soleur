// #5106 — Inngest cron model-tier registry + MODEL_PRICING parity.
//
// Guards the SSOT extraction of the per-cron Anthropic model-ID literals
// into `server/inngest/model-tiers.ts`:
//   (a) no-raw-literal: zero quoted EXECUTION_MODEL / AUDIT_MODEL string
//       literals on NON-comment code lines across functions/*.ts
//       (the pattern is derived from those constants — see RAW_MODEL_LITERAL)
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
//       AUDIT_MODEL === "claude-opus-5-5".
//   (e) #8603 audit-cron effort pin — "Guard 1", walks G1-a…G1-f below:
//       every audit-tier argv routes its model AND effort through the one
//       AUDIT_CLI_ARGS tuple, spread before the `"--"` end-of-options marker,
//       in exactly the six AUDIT_CRONS; every other `--model` argv names
//       EXECUTION_MODEL, no argv carries a raw `--effort`, and no other
//       model/effort channel is used. Plus identity pins on AUDIT_EFFORT and
//       the tuple shape.

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
  AUDIT_EFFORT,
  AUDIT_CLI_ARGS,
} from "@/server/inngest/model-tiers";
import { MODEL_PRICING } from "@/server/inngest/functions/agent-on-spawn-requested";
import { stripComments } from "../../helpers/strip-comments";

const FUNCTIONS_DIR = join(__dirname, "../../../server/inngest/functions");

// DERIVED from the SSOT constants, never restated. A hand-written copy of the
// model ID here is a second, unsynchronized pin: when the registry moves and
// this does not, the walk silently scans for a literal that no longer exists
// and the guard passes vacuously (green, not red — so the "config swaps red
// the coupled fixtures" heuristic cannot catch it). #6934 shipped exactly that
// miss. Model IDs are [a-z0-9-] only, so no regex escaping is needed.
const RAW_MODEL_LITERAL = new RegExp(`"${SONNET_MODEL}"|"${AUDIT_MODEL}"`);

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

  // Non-vacuity control for the walk above. The offenders-are-empty assertion
  // is satisfied both by "the guard works" and by "the guard scans for a
  // literal that cannot occur" — the #6934 failure. Pin that the pattern
  // actually matches a synthesized positive for BOTH tiers, so a stale or
  // mis-derived RAW_MODEL_LITERAL fails loudly instead of passing green.
  it("RAW_MODEL_LITERAL matches a synthesized literal for both tiers", () => {
    expect(RAW_MODEL_LITERAL.test(`const m = "${AUDIT_MODEL}";`)).toBe(true);
    expect(RAW_MODEL_LITERAL.test(`const m = "${EXECUTION_MODEL}";`)).toBe(true);
    // and does not match an unrelated model ID
    expect(RAW_MODEL_LITERAL.test(`const m = "claude-haiku-4-5-20251001";`)).toBe(
      false,
    );
  });

  it("MODEL_PRICING keys exactly equal the AnthropicModelId union members", () => {
    const unionMembers = [SONNET_MODEL, HAIKU_MODEL].sort();
    const pricingKeys = Object.keys(MODEL_PRICING).sort();
    expect(pricingKeys).toEqual(unionMembers);
  });

  // Pricing-drift tripwire. The keys-match test above guards the SHAPE of
  // MODEL_PRICING but says nothing about its VALUES — which is how the haiku
  // row carried retired Haiku 3.5 rates ($0.80/$4/$0.08/$1) under the Haiku
  // 4.5 key for two months, under-attributing 20% into a WORM ledger that
  // both BYOK cap layers sum. A test cannot know live prices, so this pins
  // the committed rates with their source; a genuine price change must update
  // it deliberately rather than drifting in unnoticed.
  //
  // The sonnet row previously held the scheduled POST-INTRO rate ($3/$15) on
  // purpose (#6942), so it would become correct on 2026-09-01 with no second
  // edit. Anthropic then CANCELLED that increase: $2/$10 is now the standard
  // price and the Sep-1 rise will not occur. Committed and published rates
  // therefore agree again — this pins today's billed price.
  //
  // Source: https://platform.claude.com/docs/en/about-claude/pricing.md (2026-09-03)
  //   Haiku 4.5   $1 / $5    cache-read $0.10  5m cache-write $1.25
  //   Sonnet 5    $2 / $10   cache-read $0.20  5m cache-write $2.50
  it("MODEL_PRICING values match the committed per-MTok rates", () => {
    const M = 1_000_000;
    expect(MODEL_PRICING[HAIKU_MODEL]).toEqual({
      inputPerToken: 1 / M,
      outputPerToken: 5 / M,
      cacheReadPerToken: 0.1 / M,
      cacheCreatePerToken: 1.25 / M,
    });
    expect(MODEL_PRICING[SONNET_MODEL]).toEqual({
      inputPerToken: 2 / M,
      outputPerToken: 10 / M,
      cacheReadPerToken: 0.2 / M,
      cacheCreatePerToken: 2.5 / M,
    });
  });

  it("EXECUTION_MODEL is the sonnet SSOT and AUDIT_MODEL is opus-5-5", () => {
    expect(EXECUTION_MODEL).toBe(SONNET_MODEL);
    expect(EXECUTION_MODEL).toBe("claude-sonnet-5");
    // Intentional model-bump tripwire: AUDIT_MODEL has no SSOT constant to
    // alias (opus is not an AnthropicModelId member), so it is pinned to the
    // literal here. A deliberate re-tier (e.g. opus-5 → opus-5-5, a separate
    // model-bump PR per ADR-053) must update this assertion in lockstep.
    expect(AUDIT_MODEL).toBe("claude-opus-5-5");
  });
});

// #8603 Guard 1 — audit-cron `--effort` argv pin.
//
// Property: every `claude` argv in functions/*.ts that selects the audit model
// also passes `--effort AUDIT_EFFORT`, before the `"--"` end-of-options marker
// (#4017: a flag after `--` becomes prompt text), and no argv that does not
// select the audit model passes `--effort`.
//
// Chokepoints: AUDIT_CLI_ARGS is the only place AUDIT_MODEL and AUDIT_EFFORT
// are paired (identity pin below), audit crons may use the tuple ONLY as a
// whole-line `...AUDIT_CLI_ARGS,` inside CLAUDE_CODE_FLAGS, and every other
// `"--model"` token names EXECUTION_MODEL — so the audit tier can only reach
// the CLI through the full tuple. G1-f additionally bans the CLI's other
// model/effort channels in this directory (raw model literals,
// `--fallback-model`, `--settings`/`--agents` JSON, effort env/settings keys).
// Together G1-c and G1-f are what make the pinned-CLI id guard
// (claude-cli-pin-knows-models.test.ts) complete for this directory.
//
// Moving a cron between tiers is a reviewed ADR-053 change that edits
// AUDIT_CRONS in the same diff — the table is compared by set identity, never
// a `>= 6` floor, so swapping one cron for another still reds.
const AUDIT_CRONS = [
  "cron-agent-native-audit.ts",
  "cron-architecture-diagram-sync.ts",
  "cron-competitive-analysis.ts",
  "cron-growth-audit.ts",
  "cron-legal-audit.ts",
  "cron-ux-audit.ts",
];

// Each walk's pattern, exported to the positive controls below so a pattern
// that can never match cannot pass as "no offenders".
const NAMES_AUDIT_CONST = /\bAUDIT_(MODEL|EFFORT)\b/;
const RAW_EFFORT_FLAG = /["'`]--effort/;
const MODEL_FLAG_VALUE = /["'`]--model["'`],\s*([^\s,\]]+)/g;
const MODEL_FLAG_EQUALS = /["'`]--model=/;
const WHOLE_LINE_SPREAD = /^\s*\.\.\.AUDIT_CLI_ARGS,\s*$/;
const FLAGS_ARRAY_OPEN = /^(export )?const CLAUDE_CODE_FLAGS = \[\s*$/;
const END_OF_OPTIONS = /^\s*["'`]--["'`],\s*$/;
// Other ways the pinned CLI accepts a model or an effort level.
const OTHER_CHANNELS =
  /["'`]claude-(opus|sonnet|haiku|fable)-|--fallback-model|["'`]--settings["'`]|["'`]--agents["'`]|CLAUDE_CODE_EFFORT_LEVEL|\beffortLevel\b/;

describe("audit-cron effort pin — #8603 Guard 1", () => {
  const files = readdirSync(FUNCTIONS_DIR).filter((f) => f.endsWith(".ts"));
  const code = new Map(
    files.map((f) => {
      const raw = readFileSync(join(FUNCTIONS_DIR, f), "utf8");
      return [f, stripComments(raw).split("\n")] as const;
    }),
  );

  it("stripComments keeps line numbers and never eats code after a `/*` inside a comment", () => {
    const out = stripComments(
      '// globs like bot-fix/* here\nconst x = ["--model", "claude-x"]; // tail\n/** doc */\nconst u = "http://z";\ntype T = {\n  a: string;\n  // before-brace\n};',
    ).split("\n");
    expect(out).toHaveLength(8);
    expect(out[1]).toContain('["--model", "claude-x"]');
    expect(out[1]).not.toContain("tail");
    expect(out[3]).toContain('"http://z"');
    // A comment before a closing punctuation token is trivia of that token.
    expect(out[6]).not.toContain("before-brace");
    expect(out.join("\n")).not.toMatch(/globs|doc|tail/);
    for (const f of files) {
      const raw = readFileSync(join(FUNCTIONS_DIR, f), "utf8");
      expect(code.get(f)!.length, `${f}: stripComments changed the line count`).toBe(
        raw.split("\n").length,
      );
    }
  });

  it("every walk pattern matches a synthesized positive (non-vacuity)", () => {
    expect(NAMES_AUDIT_CONST.test('  "--model", AUDIT_MODEL,')).toBe(true);
    expect(RAW_EFFORT_FLAG.test('  "--effort", "high",')).toBe(true);
    expect([...'"--model", AUDIT_MODEL,'.matchAll(MODEL_FLAG_VALUE)][0][1]).toBe("AUDIT_MODEL");
    expect(MODEL_FLAG_EQUALS.test('"--model=claude-x"')).toBe(true);
    expect(WHOLE_LINE_SPREAD.test("  ...AUDIT_CLI_ARGS,")).toBe(true);
    expect(WHOLE_LINE_SPREAD.test("  ...AUDIT_CLI_ARGS.slice(0, 2),")).toBe(false);
    for (const bad of [
      '"claude-opus-9-9"',
      '"--fallback-model"',
      '"--settings", "{}"',
      '"--agents", "{}"',
      "CLAUDE_CODE_EFFORT_LEVEL: 'low'",
      "effortLevel: 'low'",
    ]) {
      expect(OTHER_CHANNELS.test(bad), bad).toBe(true);
    }
  });

  it("AUDIT_EFFORT is the operator-requested 'high'", () => {
    expect(AUDIT_EFFORT).toBe("high");
  });

  it("AUDIT_CLI_ARGS pairs the audit model then the effort, in argv order", () => {
    expect(AUDIT_CLI_ARGS).toEqual([
      "--model",
      AUDIT_MODEL,
      "--effort",
      AUDIT_EFFORT,
    ]);
  });

  const offendersOf = (test: (line: string) => boolean) => {
    const out: string[] = [];
    for (const [f, lines] of code) {
      lines.forEach((line, i) => {
        if (test(line)) out.push(`${f}:${i + 1}: ${line.trim()}`);
      });
    }
    return out;
  };

  it("G1-a: no code line names AUDIT_MODEL or AUDIT_EFFORT directly", () => {
    expect(
      offendersOf((l) => NAMES_AUDIT_CONST.test(l)),
      "spread ...AUDIT_CLI_ARGS instead of naming the audit model/effort (ADR-053)",
    ).toEqual([]);
  });

  it("G1-b: no argv carries a raw --effort literal (any quote style)", () => {
    expect(offendersOf((l) => RAW_EFFORT_FLAG.test(l))).toEqual([]);
  });

  it("G1-c: every --model argv value is EXECUTION_MODEL, none in an audit cron, and no --model= form", () => {
    const captures: string[] = [];
    const offenders: string[] = [];
    for (const [f, lines] of code) {
      const src = lines.join("\n");
      for (const m of src.matchAll(MODEL_FLAG_VALUE)) {
        captures.push(m[1]);
        if (m[1] !== "EXECUTION_MODEL") offenders.push(`${f}: ${m[1]}`);
        // A second --model after the spread would silently override the tuple.
        if (AUDIT_CRONS.includes(f)) offenders.push(`${f}: extra --model ${m[1]}`);
      }
      if (MODEL_FLAG_EQUALS.test(src)) offenders.push(`${f}: --model= form`);
    }
    // Non-vacuity floor: 10 today; headroom so retiring one execution cron
    // does not trip it, but an empty/mis-stripped walk cannot pass.
    expect(captures.length).toBeGreaterThanOrEqual(5);
    expect(
      offenders,
      "audit-tier crons must spread ...AUDIT_CLI_ARGS; re-tiering is an ADR-053 change that edits AUDIT_CRONS",
    ).toEqual([]);
  });

  it("G1-d: exactly the six AUDIT_CRONS use the tuple, and only as a whole-line spread", () => {
    const spreaders = [...code]
      .filter(([, lines]) => lines.some((l) => WHOLE_LINE_SPREAD.test(l)))
      .map(([f]) => f)
      .sort();
    expect(
      spreaders,
      "moving a cron between tiers is a reviewed ADR-053 change: edit AUDIT_CRONS in the same diff",
    ).toEqual([...AUDIT_CRONS].sort());
    // Any other use of the tuple (a partial `.slice`, a hoisted copy, an
    // index) could drop or reorder --effort while still "mentioning" it.
    expect(
      offendersOf(
        (l) =>
          /\bAUDIT_CLI_ARGS\b/.test(l) &&
          !WHOLE_LINE_SPREAD.test(l) &&
          !/^import \{ AUDIT_CLI_ARGS \} from "@\/server\/inngest\/model-tiers";$/.test(l.trim()),
      ),
    ).toEqual([]);
  });

  it("G1-e: in each audit cron the spread sits inside CLAUDE_CODE_FLAGS, once, before the single '--'", () => {
    for (const f of AUDIT_CRONS) {
      const lines = code.get(f);
      expect(lines, `${f} not found in functions/`).toBeDefined();
      const idx = (re: RegExp) =>
        lines!.flatMap((l, i) => (re.test(l) ? [i] : []));
      const open = idx(FLAGS_ARRAY_OPEN);
      const spread = idx(WHOLE_LINE_SPREAD);
      const marker = idx(END_OF_OPTIONS);
      expect(open.length, `${f}: expected one CLAUDE_CODE_FLAGS array`).toBe(1);
      expect(spread.length, `${f}: expected exactly one ...AUDIT_CLI_ARGS spread`).toBe(1);
      expect(marker.length, `${f}: expected exactly one "--" line`).toBe(1);
      expect(spread[0], `${f}: spread must be inside CLAUDE_CODE_FLAGS`).toBeGreaterThan(open[0]);
      expect(
        spread[0],
        `${f}: ...AUDIT_CLI_ARGS must sit before "--" (a flag after it is prompt text, #4017)`,
      ).toBeLessThan(marker[0]);
    }
  });

  it("G1-f: no other channel sets a model or effort for the cron CLI", () => {
    expect(
      offendersOf((l) => OTHER_CHANNELS.test(l)),
      "route model/effort through model-tiers.ts (AUDIT_CLI_ARGS / EXECUTION_MODEL) so the pinned-CLI guard sees it",
    ).toEqual([]);
  });
});
