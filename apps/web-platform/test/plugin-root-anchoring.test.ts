import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";

/**
 * plugin-root-anchoring.test.ts — #7442.
 *
 * Guards the CUSTOMER-FACING command surface (`plugins/soleur/commands/ ** /*.md`)
 * so no producer invocation can resolve against the caller's working directory.
 * On any repo that is not this monorepo, a CWD-relative operand resolves into
 * the CUSTOMER's tree — and on a name collision, executes THEIR file.
 *
 * Canonical form: bare `${CLAUDE_PLUGIN_ROOT}/<payload-relative-path>`.
 * Rejected: `${CLAUDE_PLUGIN_ROOT:-…}` and `${CLAUDE_PLUGIN_ROOT:?…}`. Neither is
 * the literal token, so neither is substituted; the `:-` form then expands to a
 * customer-controlled relative path (the reported bug), and `:?` hard-fails on
 * exactly the marketplace surface the fix targets.
 *
 * DELIBERATELY OUT OF SCOPE — state it rather than imply closure:
 *   - `plugins/soleur/skills/ ** ` still carries ~100 `${CLAUDE_PLUGIN_ROOT:-…}`
 *     sites. That convention migration is deferred; it requires changing
 *     `server/safe-bash.ts`'s exact-literal set and the coupling test's regex,
 *     which does not belong behind a P1 customer bug fix. Tracked separately.
 *   - Shipped `.sh`/`.ts` under `plugins/soleur/ ** /scripts/` are not scanned,
 *     so path defects INSIDE payload scripts remain uncovered.
 */

const REPO_ROOT = resolve(__dirname, "../../..");
const COMMANDS_DIR = resolve(REPO_ROOT, "plugins/soleur/commands");
const PAYLOAD_ROOT = resolve(REPO_ROOT, "plugins/soleur");

/**
 * Closed set of areas permitted to invoke a monorepo-only repo-root script.
 * THIS IS THE ANTI-LAUNDERING CONDITION. Every other condition below is
 * satisfiable by anyone who wraps an invocation in an `if`; membership here is
 * not, because expanding it means editing this file — a reviewable diff.
 *
 * `rule-prune` qualifies because the area is monorepo-only BY CONSTRUCTION: its
 * input (`knowledge-base/project/rule-metrics.json`) derives from
 * `.claude/.rule-incidents.jsonl`, written by `emit_incident()` in
 * `.claude/hooks/lib/incidents.sh` — Soleur's own rule-corpus telemetry, which
 * does not and should not exist on a customer machine.
 */
const MONOREPO_ONLY_AREAS: ReadonlySet<string> = new Set(["rule-prune"]);

/** Byte-exact sentinel assignment that opens a monorepo-gated fence. */
const SENTINEL_LITERAL =
  'SOLEUR_MONOREPO="$(test -f plugins/soleur/.claude-plugin/plugin.json && pwd || true)"';

/** Executable verbs whose first operand is a script path. */
const VERB = /^\s*(?:bash|bun|node|sh|python3?)\s+(\S+)/;

const ANCHOR_PREFIX = "${CLAUDE_PLUGIN_ROOT}/";

interface Invocation {
  file: string;
  line: string;
  operand: string;
  lineIdx: number;
  /** Index into `fences`, or -1 when the invocation is an inline code span. */
  fenceIdx: number;
}

interface Fence {
  startIdx: number;
  endIdx: number;
  body: string[];
}

function commandFiles(): string[] {
  const out: string[] = [];
  const walk = (dir: string) => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const full = resolve(dir, e.name);
      if (e.isDirectory()) walk(full);
      else if (e.isFile() && e.name.endsWith(".md")) out.push(full);
    }
  };
  walk(COMMANDS_DIR);
  return out.sort();
}

/**
 * Collect fenced ```bash blocks AND inline code spans.
 *
 * Both matter, and the inline case is the one that bites: the two rule-prune
 * invocations this guard exists to constrain were inline spans inside numbered
 * list items, which a column-0 fence scanner cannot see. An indent-aware fence
 * regex is also required — every producer fence here is list-indented.
 */
function parse(file: string): { invocations: Invocation[]; fences: Fence[] } {
  const src = readFileSync(file, "utf8");
  const lines = src.split("\n");
  const fences: Fence[] = [];
  const invocations: Invocation[] = [];

  let openIdx = -1;
  let body: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    // Indent-aware: ```bash may be nested under a list item.
    if (/^\s*```/.test(lines[i])) {
      if (openIdx === -1) {
        openIdx = i;
        body = [];
      } else {
        fences.push({ startIdx: openIdx, endIdx: i, body });
        openIdx = -1;
      }
      continue;
    }
    if (openIdx !== -1) body.push(lines[i]);
  }

  const fenceOf = (idx: number) =>
    fences.findIndex((f) => idx > f.startIdx && idx < f.endIdx);

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    const inFence = fenceOf(i);

    if (inFence !== -1) {
      const m = raw.match(VERB);
      if (m) {
        invocations.push({ file, line: raw.trim(), operand: m[1], lineIdx: i, fenceIdx: inFence });
      }
      continue;
    }

    // Inline code spans on a prose line, e.g. `bash scripts/foo.sh --flag`.
    for (const span of raw.matchAll(/`([^`]+)`/g)) {
      const m = span[1].match(VERB);
      if (m) {
        invocations.push({
          file,
          line: span[1].trim(),
          operand: m[1],
          lineIdx: i,
          fenceIdx: -1,
        });
      }
    }
  }
  return { invocations, fences };
}

/**
 * Monorepo-gated: ALL SIX conditions, each failing closed. Returns the matched
 * area on success so P3b can prove every closed-set member is exercised.
 */
function monorepoGatedArea(inv: Invocation, fences: Fence[]): string | null {
  if (inv.fenceIdx === -1) return null; // an inline span carries no gate
  const fence = fences[inv.fenceIdx];
  const bodyStart = fence.startIdx + 1;
  const rel = inv.lineIdx - bodyStart;

  // (2) exact sentinel literal present
  const sentinelRel = fence.body.findIndex((l) => l.includes(SENTINEL_LITERAL));
  if (sentinelRel === -1) return null;

  // (3) ordering — sentinel strictly before the invocation
  if (!(sentinelRel < rel)) return null;

  // (4) emission, and (1) closed-set membership of the emitted area
  const emit = fence.body.find((l) => l.includes('echo "SOLEUR_SYNC_AREA_UNAVAILABLE area='));
  if (!emit) return null;
  const areaMatch = emit.match(/SOLEUR_SYNC_AREA_UNAVAILABLE area=(\S+)/);
  if (!areaMatch) return null;
  const area = areaMatch[1];
  if (!MONOREPO_ONLY_AREAS.has(area)) return null;

  // (5) halt between sentinel and invocation
  const exitRel = fence.body.findIndex((l) => /^\s*exit 2\s*$/.test(l));
  if (exitRel === -1 || !(exitRel > sentinelRel && exitRel < rel)) return null;

  // (6) one gate, one command — otherwise a single sentinel launders several
  const invocationsInFence = fence.body.filter((l) => VERB.test(l)).length;
  if (invocationsInFence !== 1) return null;

  // (7) the operand itself must be fail-closed in isolation. Added beyond the
  // ruled six because a gate on a SEPARATE LINE does not survive a line-wise
  // reader: measured, the decoys executed when the invocation was extracted
  // alone. `"$SOLEUR_MONOREPO/…` degrades to `/…` when unset, which is
  // root-anchored and nonexistent rather than customer-controlled.
  if (!inv.operand.startsWith('"$SOLEUR_MONOREPO/')) return null;

  return area;
}

describe("plugin-root anchoring — customer-facing command surface", () => {
  const files = commandFiles();
  const parsed = files.map((f) => ({ file: f, ...parse(f) }));
  const allInvocations = parsed.flatMap((p) => p.invocations);

  it("P3: extracts at least one executable invocation (anti-vacuity floor)", () => {
    // Floor is >= 1, deliberately NOT pinned to today's count, so legitimately
    // removing a producer does not false-fail the guard. Mirrors the reasoning
    // committed at plugin-root-list-carveout-coupling.test.ts:41-44.
    expect(allInvocations.length).toBeGreaterThanOrEqual(1);
  });

  it("P1: every producer operand is bare-anchored or monorepo-gated", () => {
    const violations: string[] = [];
    for (const p of parsed) {
      for (const inv of p.invocations) {
        if (inv.operand.startsWith(ANCHOR_PREFIX)) continue;
        if (monorepoGatedArea(inv, p.fences)) continue;
        violations.push(`${inv.file.replace(REPO_ROOT + "/", "")}: ${inv.line}`);
      }
    }
    expect(violations).toEqual([]);
  });

  it("P1b: no :- or :? default anywhere in the command surface", () => {
    const violations: string[] = [];
    for (const f of files) {
      const src = readFileSync(f, "utf8");
      if (src.includes("${CLAUDE_PLUGIN_ROOT:-") || src.includes("${CLAUDE_PLUGIN_ROOT:?")) {
        violations.push(f.replace(REPO_ROOT + "/", ""));
      }
    }
    expect(violations).toEqual([]);
  });

  it("P2: every anchored operand resides in the plugin payload", () => {
    // The residency teeth. Catches a producer that is perfectly anchored but
    // points at a path no marketplace install would carry.
    const missing: string[] = [];
    for (const inv of allInvocations) {
      if (!inv.operand.startsWith(ANCHOR_PREFIX)) continue;
      const rel = inv.operand.slice(ANCHOR_PREFIX.length).replace(/["']/g, "");
      if (!existsSync(resolve(PAYLOAD_ROOT, rel))) {
        missing.push(`${inv.file.replace(REPO_ROOT + "/", "")}: plugins/soleur/${rel}`);
      }
    }
    expect(missing).toEqual([]);
  });

  it("P3b: every MONOREPO_ONLY_AREAS member is exercised by a live gated site", () => {
    // Anti-graveyard ratchet: a member with no live gated site REDs, so the
    // closed vocabulary cannot silently accumulate dead entries and rot into a
    // free-form one.
    const exercised = new Set<string>();
    for (const p of parsed) {
      for (const inv of p.invocations) {
        const area = monorepoGatedArea(inv, p.fences);
        if (area) exercised.add(area);
      }
    }
    expect([...MONOREPO_ONLY_AREAS].filter((a) => !exercised.has(a))).toEqual([]);
  });
});
