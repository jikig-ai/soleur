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
 * Canonical form: bare `${CLAUDE_PLUGIN_ROOT}/<payload-relative-path>`, QUOTED.
 * Rejected: `${CLAUDE_PLUGIN_ROOT:-…}` and `${CLAUDE_PLUGIN_ROOT:?…}`. Neither is
 * the literal token, so neither is substituted; the `:-` form then expands to a
 * customer-controlled relative path (the reported bug).
 *
 * DELIBERATELY OUT OF SCOPE — stated rather than implied:
 *   - `plugins/soleur/skills/ ** ` still carries ~98 `${CLAUDE_PLUGIN_ROOT:-…}`
 *     sites and some bare-CWD-relative `bash plugins/soleur/scripts/…` sites.
 *     Deferred to #7453; that is also an open bypass of THIS guard, since moving
 *     a producer into a SKILL.md escapes the scope below onto a surface that is
 *     equally customer-facing.
 *   - Shipped `.sh`/`.ts` under `plugins/soleur/ ** /scripts/` are not scanned.
 *   - Remaining follow-ups: #7452.
 */

const REPO_ROOT = resolve(__dirname, "../../..");
const COMMANDS_DIR = resolve(REPO_ROOT, "plugins/soleur/commands");
const PAYLOAD_ROOT = resolve(REPO_ROOT, "plugins/soleur");

/**
 * Closed set of areas permitted to invoke a monorepo-only repo-root script.
 * THIS IS THE ANTI-LAUNDERING CONDITION. Every other condition is satisfiable by
 * anyone who wraps an invocation in an `if`; membership here is not, because
 * expanding it means editing this file — a reviewable diff.
 */
const MONOREPO_ONLY_AREAS: ReadonlySet<string> = new Set(["rule-prune"]);

/** Byte-exact sentinel assignment that opens a monorepo-gated fence. */
const SENTINEL_LITERAL =
  'SOLEUR_MONOREPO="$(test -f plugins/soleur/.claude-plugin/plugin.json && pwd || true)"';

/**
 * The mandated fail-closed preflight (ADR-179 decision 2). Anchored on the
 * manifest probe rather than on a whole block, so reformatting does not
 * false-fail while deleting the gate still does.
 */
const PREFLIGHT_ANCHOR = '"${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"';

const ANCHOR_PREFIX = "${CLAUDE_PLUGIN_ROOT}/";

/** The one command file whose producer guards P6 pins. Scoped deliberately:
 *  `parse()` walks the whole command surface, and go.md contributes anchored
 *  operands that are not sync.md producers. */
const SYNC_MD = resolve(COMMANDS_DIR, "sync.md");

/**
 * Closed set of areas a producer guard may declare in its `affects=` token.
 * Closed BY CONSTRUCTION: widening it means editing this file, which is a
 * reviewable diff — the same anti-laundering property as MONOREPO_ONLY_AREAS.
 */
const PRODUCER_AREAS: ReadonlySet<string> = new Set(["c4", "coverage", "domain-model"]);

/** Runners whose FIRST operand is a script path. */
const RUNNERS = "bash|bun|node|sh|python3?|bunx|npx|tsx|deno|exec|source";

/**
 * Command position, not line start. `cd x && bash foo` and `FOO=1 bash foo` both
 * put the invocation in second position, which a `^\s*` anchor cannot see — both
 * were measured to defeat the previous form of this guard while executing a
 * planted decoy.
 */
const RUNNER_RE = new RegExp(
  String.raw`(?:^|\||&&|;|\bthen\b|\bdo\b|\$\()\s*(?:\w+=\S*\s+)*(?:${RUNNERS})\s+(\S+)`,
  "g",
);

/**
 * Direct execution with no runner token — `./script.sh`, `../x/y.sh`. Measured to
 * defeat the runner-only form while executing a planted decoy, i.e. #7442
 * reintroduced in different clothes.
 */
const DIRECT_EXEC_RE = new RegExp(
  String.raw`(?:^|\||&&|;|\bthen\b|\bdo\b|\$\()\s*(?:\w+=\S*\s+)*(\.{1,2}/\S+)`,
  "g",
);

interface Invocation {
  file: string;
  line: string;
  operand: string;
  lineIdx: number;
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

/** Strip one layer of surrounding quotes from an operand. */
function unquote(op: string): string {
  return op.replace(/^["']/, "").replace(/["']$/, "");
}

function extractOperands(text: string): string[] {
  const out: string[] = [];
  for (const re of [RUNNER_RE, DIRECT_EXEC_RE]) {
    re.lastIndex = 0;
    for (const m of text.matchAll(re)) out.push(m[1]);
  }
  return out;
}

/**
 * Collect fenced blocks AND inline code spans.
 *
 * Fence tracking follows CommonMark run-length: a closer must be at least as
 * long as its opener. A naive "toggle on any ```" is a parity counter, and a
 * four-backtick documentation fence containing a three-backtick bash fence
 * inverts parity for the rest of the file — measured to blind this guard
 * completely, which is why `fencesBalanced` is asserted rather than assumed.
 */
function parse(file: string): {
  invocations: Invocation[];
  fences: Fence[];
  fencesBalanced: boolean;
  hasBashFence: boolean;
} {
  const lines = readFileSync(file, "utf8").split("\n");
  const fences: Fence[] = [];
  const invocations: Invocation[] = [];

  let openIdx = -1;
  let openLen = 0;
  let body: string[] = [];
  let hasBashFence = false;

  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^\s*(`{3,})(.*)$/);
    if (m) {
      const len = m[1].length;
      if (openIdx === -1) {
        openIdx = i;
        openLen = len;
        body = [];
        if (/^\s*bash\b/.test(m[2])) hasBashFence = true;
        continue;
      }
      // A closer carries no info string and must be >= the opener's length.
      if (len >= openLen && m[2].trim() === "") {
        fences.push({ startIdx: openIdx, endIdx: i, body });
        openIdx = -1;
        openLen = 0;
        continue;
      }
    }
    if (openIdx !== -1) body.push(lines[i]);
  }
  const fencesBalanced = openIdx === -1;

  const fenceOf = (idx: number) =>
    fences.findIndex((f) => idx > f.startIdx && idx < f.endIdx);

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    const inFence = fenceOf(i);
    if (inFence !== -1) {
      for (const operand of extractOperands(raw)) {
        invocations.push({ file, line: raw.trim(), operand, lineIdx: i, fenceIdx: inFence });
      }
      continue;
    }
    for (const span of raw.matchAll(/`([^`]+)`/g)) {
      for (const operand of extractOperands(span[1])) {
        invocations.push({ file, line: span[1].trim(), operand, lineIdx: i, fenceIdx: -1 });
      }
    }
  }
  return { invocations, fences, fencesBalanced, hasBashFence };
}

/** True when the operand escapes the payload via `..` after normalization. */
function escapesPayload(operand: string): boolean {
  const rel = unquote(operand).slice(ANCHOR_PREFIX.length);
  const abs = resolve(PAYLOAD_ROOT, rel);
  return !abs.startsWith(PAYLOAD_ROOT + "/");
}

function isAnchored(operand: string): boolean {
  return unquote(operand).startsWith(ANCHOR_PREFIX);
}

/**
 * Monorepo-gated: ALL SEVEN conditions, each failing closed. Condition (1)
 * (closed-set membership) is the anti-laundering one; (7) is the only one with
 * real teeth against a hostile operand, so it is deliberately strict.
 */
function monorepoGatedArea(inv: Invocation, fences: Fence[]): string | null {
  if (inv.fenceIdx === -1) return null;
  const fence = fences[inv.fenceIdx];
  const rel = inv.lineIdx - (fence.startIdx + 1);

  // (2) exact sentinel literal
  const sentinelRel = fence.body.findIndex((l) => l.includes(SENTINEL_LITERAL));
  if (sentinelRel === -1) return null;
  // (3) ordering
  if (!(sentinelRel < rel)) return null;
  // (4) emission + (1) closed-set membership
  const emit = fence.body.find((l) => l.includes('echo "SOLEUR_SYNC_AREA_UNAVAILABLE area='));
  if (!emit) return null;
  const areaMatch = emit.match(/SOLEUR_SYNC_AREA_UNAVAILABLE area=(\S+)/);
  if (!areaMatch || !MONOREPO_ONLY_AREAS.has(areaMatch[1])) return null;
  // (5) halt between sentinel and invocation
  const exitRel = fence.body.findIndex((l) => /^\s*exit 2\s*$/.test(l));
  if (exitRel === -1 || !(exitRel > sentinelRel && exitRel < rel)) return null;
  // (6) one gate, one command
  if (fence.body.reduce((n, l) => n + extractOperands(l).length, 0) !== 1) return null;
  // (7) the operand must be fail-closed IN ISOLATION and must not escape via `..`.
  //     `:?` is correct here (unlike for CLAUDE_PLUGIN_ROOT) because the value is
  //     assigned two lines above by code in this repo, not supplied by the harness
  //     — so an ambient export cannot direct it.
  const bare = unquote(inv.operand);
  if (!bare.startsWith("${SOLEUR_MONOREPO:?")) return null;
  if (bare.includes("/../") || bare.endsWith("/..")) return null;

  return areaMatch[1];
}

describe("plugin-root anchoring — customer-facing command surface", () => {
  const files = commandFiles();
  const parsed = files.map((f) => ({ file: f, ...parse(f) }));
  const allInvocations = parsed.flatMap((p) => p.invocations);
  let assertions = 0;
  const seen = () => {
    assertions += 1;
  };

  it("P0: every command file's fences are balanced", () => {
    // An unbalanced fence silently drops every invocation after it, which makes
    // all downstream assertions vacuous rather than failing.
    seen();
    expect(parsed.filter((p) => !p.fencesBalanced).map((p) => p.file)).toEqual([]);
  });

  it("P3: any file with a bash fence yields at least one invocation", () => {
    // Per-file, not global: a global `>= 1` floor stays green while one file
    // contributes and another has been blinded.
    seen();
    const blind = parsed
      .filter((p) => p.hasBashFence && p.invocations.length === 0)
      .map((p) => p.file.replace(REPO_ROOT + "/", ""));
    expect(blind).toEqual([]);
  });

  it("P1: every producer operand is bare-anchored or monorepo-gated", () => {
    seen();
    const violations: string[] = [];
    for (const p of parsed) {
      for (const inv of p.invocations) {
        if (isAnchored(inv.operand)) continue;
        if (monorepoGatedArea(inv, p.fences)) continue;
        violations.push(`${inv.file.replace(REPO_ROOT + "/", "")}: ${inv.line}`);
      }
    }
    expect(violations).toEqual([]);
  });

  it("P1b: no :- or :? default on CLAUDE_PLUGIN_ROOT in the command surface", () => {
    seen();
    const violations = files
      .filter((f) => {
        const src = readFileSync(f, "utf8");
        return src.includes("${CLAUDE_PLUGIN_ROOT:-") || src.includes("${CLAUDE_PLUGIN_ROOT:?");
      })
      .map((f) => f.replace(REPO_ROOT + "/", ""));
    expect(violations).toEqual([]);
  });

  it("P1c: every anchored operand is quoted", () => {
    // An unquoted expansion word-splits on an install path containing a space
    // (measured: `/mnt/c/Users/First Last/…`), and the split prefix is what gets
    // executed. The preflight cannot see this — it passes, then the run breaks.
    seen();
    const unquoted = allInvocations
      .filter((inv) => isAnchored(inv.operand) && !/^["']/.test(inv.operand))
      .map((inv) => `${inv.file.replace(REPO_ROOT + "/", "")}: ${inv.line}`);
    expect(unquoted).toEqual([]);
  });

  it("P2: every anchored operand resides INSIDE the plugin payload", () => {
    seen();
    const bad: string[] = [];
    for (const inv of allInvocations) {
      if (!isAnchored(inv.operand)) continue;
      const rel = unquote(inv.operand).slice(ANCHOR_PREFIX.length);
      // Containment first: `resolve()` normalizes `..` straight through the
      // payload boundary, so a `${CLAUDE_PLUGIN_ROOT}/../../x` operand would
      // otherwise land on a real repo-root file and be certified resident.
      if (escapesPayload(inv.operand)) {
        bad.push(`ESCAPES PAYLOAD: ${inv.line}`);
        continue;
      }
      if (!existsSync(resolve(PAYLOAD_ROOT, rel))) {
        bad.push(`NOT RESIDENT: plugins/soleur/${rel}`);
      }
    }
    expect(bad).toEqual([]);
  });

  it("P3b: every MONOREPO_ONLY_AREAS member is exercised by a live gated site", () => {
    seen();
    const exercised = new Set<string>();
    for (const p of parsed) {
      for (const inv of p.invocations) {
        const area = monorepoGatedArea(inv, p.fences);
        if (area) exercised.add(area);
      }
    }
    expect([...MONOREPO_ONLY_AREAS].filter((a) => !exercised.has(a))).toEqual([]);
  });

  it("P4: every command file with an anchored producer carries the fail-closed preflight", () => {
    // ADR-179 decision 2 mandates this per command file, and it is the half of
    // the safety argument that carries the bare form. Without this assertion the
    // whole preflight block is deletable with the suite green.
    seen();
    const missing: string[] = [];
    for (const p of parsed) {
      const anchored = p.invocations.filter((inv) => isAnchored(inv.operand));
      if (anchored.length === 0) continue;
      const src = readFileSync(p.file, "utf8");
      if (!src.includes(PREFLIGHT_ANCHOR)) {
        missing.push(p.file.replace(REPO_ROOT + "/", ""));
        continue;
      }
      // Ordering: the preflight must precede the first anchored invocation.
      const preflightIdx = src.split("\n").findIndex((l) => l.includes(PREFLIGHT_ANCHOR));
      const firstAnchored = Math.min(...anchored.map((inv) => inv.lineIdx));
      if (!(preflightIdx < firstAnchored)) {
        missing.push(`${p.file.replace(REPO_ROOT + "/", "")} (preflight below first producer)`);
      }
    }
    expect(missing).toEqual([]);
  });

  it("P6: every producer invocation in sync.md is presence-guarded with a known affects= area", () => {
    // #7474. P2 above proves an anchored operand RESIDES in this repo's payload
    // at CI time. It says nothing about the payload on a customer's machine: an
    // identity-valid root missing a producer passes the preflight (P4) and then
    // dies on a bare interpreter error with no marker. The guard makes absence
    // named and non-invoking; this assertion is what stops the guard list from
    // drifting out of sync with the real invocation inventory.
    seen();
    const p = parsed.find((x) => x.file === SYNC_MD);
    const producers = (p?.invocations ?? []).filter(
      // Fence bodies only: sync.md's Phase 0 prose quotes ADR-179's worked
      // examples as inline spans. Those are documentation, not invocations, and
      // demanding guards on them makes the shortest fix "delete the ADR prose".
      (inv) => inv.fenceIdx !== -1 && isAnchored(inv.operand),
    );
    const relOf = (inv: Invocation) => unquote(inv.operand).slice(ANCHOR_PREFIX.length);
    const rels = new Set(producers.map(relOf));

    // Non-vacuity BEFORE comparing: `∅` equals `∅`, so a parser that stopped
    // matching would otherwise report parity it never checked.
    const vacuity: string[] = [];
    if (!p) vacuity.push("sync.md is absent from the parsed command surface");
    if (rels.size < 3) {
      vacuity.push(
        `DERIVED ONLY ${rels.size} DISTINCT PRODUCERS from sync.md (expected >= 3) — ` +
          "the parser stopped matching, so the parity assertion below would be vacuous",
      );
    }
    expect(vacuity).toEqual([]);

    const violations: string[] = [];
    const guarded = new Set<string>();
    for (const inv of producers) {
      const rel = relOf(inv);
      const body = p!.fences[inv.fenceIdx].body;
      // Anchored on the operand itself, not on a bare filename: a comment
      // mentioning the path would otherwise satisfy the check.
      const hasPresenceCheck = body.some(
        (l) => l.includes("[ -f ") && l.includes(inv.operand),
      );
      const marker = body.find((l) =>
        l.includes(`SOLEUR_SYNC_PRODUCER_MISSING producer=${rel}`),
      );
      if (!hasPresenceCheck || !marker) {
        violations.push(
          `PRODUCER NOT GUARDED: ${rel} — in plugins/soleur/commands/sync.md, wrap its ` +
            `invocation so the presence check and the invocation share a subprocess: ` +
            `if [ -f "${ANCHOR_PREFIX}${rel}" ]; then <invoke>; else ` +
            `echo "SOLEUR_SYNC_PRODUCER_MISSING producer=${rel} affects=<area> ` +
            `reason=absent-from-verified-root"; fi`,
        );
        continue;
      }
      guarded.add(rel);
      const declared = marker.match(/\baffects=(\S+)/);
      if (!declared) {
        violations.push(
          `MARKER MISSING affects=: ${rel} — add affects=<area> to its ` +
            "SOLEUR_SYNC_PRODUCER_MISSING line in plugins/soleur/commands/sync.md",
        );
        continue;
      }
      // Comma-joined, mirroring the sibling `SOLEUR_SYNC_TOOLCHAIN_MISSING … affects=c4,coverage`.
      for (const area of declared[1].split(",")) {
        if (!PRODUCER_AREAS.has(area)) {
          violations.push(
            `UNKNOWN affects= AREA ${JSON.stringify(area)} on producer ${rel} — use one of ` +
              `${[...PRODUCER_AREAS].join(", ")}, or add it to PRODUCER_AREAS in this file ` +
              "(a reviewable diff, which is the point)",
          );
        }
      }
    }
    expect(violations).toEqual([]);

    // Parity as SET equality, never a count: a count cannot see a rename.
    expect([...guarded].sort()).toEqual([...rels].sort());
  });

  it("P5: the suite ran every assertion (anti-vacuity floor)", () => {
    // Neutering or deleting an assertion block otherwise leaves the file green.
    // Absolute, ratcheted by hand — never derived from the cases themselves,
    // which would simply descend with a deletion.
    expect(assertions).toBe(9);
  });
});
