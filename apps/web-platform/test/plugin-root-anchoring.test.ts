import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync, existsSync, statSync, realpathSync } from "node:fs";
import { resolve } from "node:path";

/**
 * plugin-root-anchoring.test.ts — #7442, extended by #7450.
 *
 * Guards two customer-facing surfaces so no producer invocation can resolve
 * against the caller's working directory. On any repo that is not this monorepo,
 * a CWD-relative operand resolves into the CUSTOMER's tree — and on a name
 * collision, executes THEIR file.
 *
 *   1. `plugins/soleur/commands/ ** /*.md` — every producer invocation (#7442).
 *   2. `plugins/soleur/skills/ ** /SKILL.md` — the SECRET-GATE SUBSET only
 *      (#7450 / ADR-179 §R5). These are gates whose exit code decides whether
 *      secrets are emitted, and `review/SKILL.md` instructs `gh pr checkout`, so
 *      on the review path the git root IS the reviewed party's tree.
 *
 * Canonical form: bare `${CLAUDE_PLUGIN_ROOT}/<payload-relative-path>`, QUOTED.
 * Rejected: `${CLAUDE_PLUGIN_ROOT:-…}` and `${CLAUDE_PLUGIN_ROOT:?…}`. Neither is
 * the literal token, so neither is substituted; the `:-` form then expands to a
 * customer-controlled relative path (the reported bug). Measured 2026-08-12
 * (#7450): the loader substitutes the bare token at DELIVERY time — `go.md` ships
 * `${CLAUDE_PLUGIN_ROOT}` and arrives carrying the absolute installed root while
 * the shell environment has no such variable — which is why the exact-literal
 * requirement is a fact rather than an inference.
 *
 * WHY THE SKILLS AXIS NEEDS ITS OWN EXTRACTOR. The command surface invokes
 * producers directly (`bash "${CLAUDE_PLUGIN_ROOT}/scripts/x.sh"`), so a
 * runner-position operand rule sees the anchor. The skills gate surface uses
 * assignment-then-invoke:
 *
 *     SENTINEL="${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh"
 *     bash "$SENTINEL"
 *
 * The anchor lives in the ASSIGNMENT. A runner-operand rule would certify
 * `bash "$SENTINEL"` as compliant while the assignment above it pointed anywhere,
 * so the skills axis matches gate-script references in CODE CONTEXT instead.
 * Code context (fence bodies + inline spans) is also what keeps markdown link
 * targets — `[redact-sentinel.sh](../incident/scripts/redact-sentinel.sh)`, of
 * which there are several — from being read as execution paths.
 *
 * DELIBERATELY OUT OF SCOPE — stated rather than implied:
 *   - The NON-gate `plugins/soleur/skills/ ** ` sites (~105 `${CLAUDE_PLUGIN_ROOT:-…}`
 *     occurrences plus some bare-CWD-relative `bash plugins/soleur/scripts/…`)
 *     remain deferred to #7453. Only the gate subset is enforced here.
 *   - `preflight/SKILL.md` carries two UNCONDITIONAL `$(git rev-parse --show-toplevel)`
 *     anchors (`parse-form-a.awk`, `probe-verb-gate.sh`). Same threat shape,
 *     arguably worse, but not secret-emission gates — routed to #7453 with a
 *     severity flag (#7450 DC-1). Their falsified rationale comment was corrected.
 *   - Shipped `.sh`/`.ts` under `plugins/soleur/ ** /scripts/` are not scanned.
 *   - `redact-sentinel.test.sh` pins the corpus-wide negative instead; it is a
 *     `.test.sh`, so it is outside this file's SKILL.md axis by construction.
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

/**
 * Used by P7 only. P6 (presence-guard parity) deliberately spans the WHOLE command
 * surface — go.md carried the same gap and is the higher-traffic file. What is
 * sync-specific is the MARKER GRAMMAR: `SOLEUR_SYNC_PRODUCER_MISSING` with a
 * `producer=`/`affects=` vocabulary that go.md's own marker families do not share.
 */
const SYNC_MD = resolve(COMMANDS_DIR, "sync.md");

/**
 * The area each producer's `affects=` token MUST declare — a mapping, not a set.
 *
 * A membership-only check (`AREAS.has(area)`) is satisfied by ANY permutation once
 * the producer count equals the area count, which it does here (3 and 3). Measured:
 * swapping the c4 guard to `affects=domain-model` passed. The operator message
 * interpolates `<area>` from this token, so a swap tells the user the wrong step of
 * their sync did not run — a confidently wrong statement about their own project.
 *
 * Closed BY CONSTRUCTION: adding a producer means editing this file, which is a
 * reviewable diff — the same anti-laundering property as MONOREPO_ONLY_AREAS.
 *
 * NOTE: `coverage` is a PSEUDO-area — it is not one of sync.md's dispatchable
 * `<sync_area>` values (`conventions|architecture|testing|debt|project|c4|
 * domain-model|all`). It names the end-of-run coverage summary, which no
 * operator invokes directly. Recorded so the mismatch reads as deliberate.
 */
const PRODUCER_AREA: ReadonlyMap<string, string> = new Map([
  ["scripts/generate-c4-from-components.ts", "c4"],
  ["scripts/write-kb-coverage.ts", "coverage"],
  ["scripts/domain-model-drift.sh", "domain-model"],
]);

/**
 * The area VALUES, for markers that declare a blast radius without naming one
 * producer (`SOLEUR_SYNC_TOOLCHAIN_MISSING tool=bun affects=c4,coverage`).
 */
const KNOWN_AREAS: ReadonlySet<string> = new Set(PRODUCER_AREA.values());

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
/**
 * `srcOverride` lets the same parser run over a SYNTHESIZED corpus. Without it the
 * skills-axis predicates below could only ever be pointed at a 100%-compliant tree,
 * which makes `violations` structurally `[]` and every assertion vacuous — the defect
 * recorded as #7450 review-finding A13. Real files still read from disk.
 */
function parse(
  file: string,
  srcOverride?: string,
): {
  invocations: Invocation[];
  fences: Fence[];
  fencesBalanced: boolean;
  hasBashFence: boolean;
} {
  const lines = (srcOverride ?? readFileSync(file, "utf8")).split("\n");
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
  /**
   * Counts a DECIDED assertion.
   *
   * The floor must certify that assertions RAN, not that blocks ran. A `seen()` at the
   * top of an `it` is satisfied by a block whose body was gutted (measured: replacing
   * P6's assertion with `void violations` left the suite green at the full count), and
   * moving it to the bottom is satisfied by deleting the assertion above it. Counting
   * inside the assertion is the only placement a deletion cannot survive.
   */
  const check = <T>(actual: T) => {
    assertions += 1;
    return expect(actual);
  };

  it("P0: every command file's fences are balanced", () => {
    // An unbalanced fence silently drops every invocation after it, which makes
    // all downstream assertions vacuous rather than failing.
    check(parsed.filter((p) => !p.fencesBalanced).map((p) => p.file)).toEqual([]);
  });

  it("P3: any file with a bash fence yields at least one invocation", () => {
    // Per-file, not global: a global `>= 1` floor stays green while one file
    // contributes and another has been blinded.
    const blind = parsed
      .filter((p) => p.hasBashFence && p.invocations.length === 0)
      .map((p) => p.file.replace(REPO_ROOT + "/", ""));
    check(blind).toEqual([]);
  });

  it("P1: every producer operand is bare-anchored or monorepo-gated", () => {
    const violations: string[] = [];
    for (const p of parsed) {
      for (const inv of p.invocations) {
        if (isAnchored(inv.operand)) continue;
        if (monorepoGatedArea(inv, p.fences)) continue;
        violations.push(`${inv.file.replace(REPO_ROOT + "/", "")}: ${inv.line}`);
      }
    }
    check(violations).toEqual([]);
  });

  it("P1b: no :- or :? default on CLAUDE_PLUGIN_ROOT in the command surface", () => {
    const violations = files
      .filter((f) => {
        const src = readFileSync(f, "utf8");
        return src.includes("${CLAUDE_PLUGIN_ROOT:-") || src.includes("${CLAUDE_PLUGIN_ROOT:?");
      })
      .map((f) => f.replace(REPO_ROOT + "/", ""));
    check(violations).toEqual([]);
  });

  it("P1c: every anchored operand is quoted", () => {
    // An unquoted expansion word-splits on an install path containing a space
    // (measured: `/mnt/c/Users/First Last/…`), and the split prefix is what gets
    // executed. The preflight cannot see this — it passes, then the run breaks.
    const unquoted = allInvocations
      .filter((inv) => isAnchored(inv.operand) && !/^["']/.test(inv.operand))
      .map((inv) => `${inv.file.replace(REPO_ROOT + "/", "")}: ${inv.line}`);
    check(unquoted).toEqual([]);
  });

  it("P2: every anchored operand resides INSIDE the plugin payload", () => {
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
    check(bad).toEqual([]);
  });

  it("P3b: every MONOREPO_ONLY_AREAS member is exercised by a live gated site", () => {
    const exercised = new Set<string>();
    for (const p of parsed) {
      for (const inv of p.invocations) {
        const area = monorepoGatedArea(inv, p.fences);
        if (area) exercised.add(area);
      }
    }
    check([...MONOREPO_ONLY_AREAS].filter((a) => !exercised.has(a))).toEqual([]);
  });

  it("P4: every command file with an anchored producer carries the fail-closed preflight", () => {
    // ADR-179 decision 2 mandates this per command file, and it is the half of
    // the safety argument that carries the bare form. Without this assertion the
    // whole preflight block is deletable with the suite green.
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
    check(missing).toEqual([]);
  });

  it("P6: every anchored invocation in the command surface is presence-guarded", () => {
    // #7474. P2 above proves an anchored operand RESIDES in this repo's payload
    // at CI time. It says nothing about the payload on a CUSTOMER's machine: a
    // root that is genuinely ours but does not carry the file passes the identity
    // preflight (P4), and the invocation then dies on a bare interpreter error
    // with no marker and no attribution.
    //
    // Scope is the WHOLE command surface, deliberately. Scoping this to sync.md
    // would have exempted go.md — the higher-traffic entry point, run at every
    // session start — which carried the identical gap.
    const violations: string[] = [];
    let checked = 0;
    for (const p of parsed) {
      for (const inv of p.invocations) {
        // Fence bodies only: Phase 0 prose quotes ADR-179's worked examples as
        // inline spans. Those are documentation, not invocations, and demanding
        // guards on them makes the shortest fix "delete the ADR prose".
        if (inv.fenceIdx === -1 || !isAnchored(inv.operand)) continue;
        checked += 1;
        const fence = p.fences[inv.fenceIdx];
        // The guard must PRECEDE the invocation it guards, not merely share a fence
        // with it. A `some()` over the whole fence accepted this, measured:
        //
        //     bun "${CLAUDE_PLUGIN_ROOT}/scripts/x.ts"      <- hoisted out, unguarded
        //     if [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/x.ts" ]; then
        //       bun "${CLAUDE_PLUGIN_ROOT}/scripts/x.ts"
        //     else … fi
        //
        // — which is #7474 reintroduced (the hoisted line dies on the bare interpreter
        // error, then the guard below politely reports the same file missing) with the
        // suite fully green. This assertion's own remedy text promises the invocation
        // and its check "share a subprocess"; ordering is the cheapest thing that
        // actually tests it.
        //
        // Anchored on `[` + `-f` at STATEMENT start, so a `#` comment quoting the guard
        // cannot satisfy it — `includes("[ -f ")` alone could.
        const relIdx = inv.lineIdx - (fence.startIdx + 1);
        const guardIdx = fence.body.findIndex(
          (l) => /^\s*(?:if\s+)?\[\s+-f\s+/.test(l) && l.includes(inv.operand),
        );
        if (guardIdx === -1 || guardIdx >= relIdx) {
          violations.push(
            `INVOCATION NOT PRESENCE-GUARDED: ${p.file.replace(REPO_ROOT + "/", "")}: ` +
              `${inv.line} — wrap it so the presence check and the invocation share a ` +
              `subprocess: if [ -f ${inv.operand} ]; then <invoke>; else <emit a marker>; fi`,
          );
        }
      }
    }
    // Absolute, hand-ratcheted. A floor DERIVED from the parse would simply
    // descend with a parser that stopped matching, reporting parity it never
    // checked.
    check(checked).toBeGreaterThanOrEqual(8);
    check(violations).toEqual([]);
  });

  it("P7: every sync.md producer guard emits a marker with a known affects= area", () => {
    // P6 proves each invocation is guarded. This proves the guard SAYS something
    // useful when it fires, and that the guard list cannot drift out of sync with
    // the real invocation inventory.
    const p = parsed.find((x) => x.file === SYNC_MD);
    const producers = (p?.invocations ?? []).filter(
      (inv) => inv.fenceIdx !== -1 && isAnchored(inv.operand),
    );
    const relOf = (inv: Invocation) => unquote(inv.operand).slice(ANCHOR_PREFIX.length);
    const rels = new Set(producers.map(relOf));

    // Non-vacuity BEFORE comparing: `∅` equals `∅`.
    const vacuity: string[] = [];
    if (!p) vacuity.push("sync.md is absent from the parsed command surface");
    if (rels.size < 3) {
      vacuity.push(
        `DERIVED ONLY ${rels.size} DISTINCT PRODUCERS from sync.md (expected >= 3) — ` +
          "the parser stopped matching, so the parity assertion below would be vacuous",
      );
    }
    check(vacuity).toEqual([]);

    const violations: string[] = [];
    const marked = new Set<string>();
    // Blast-radius markers that name no single producer are checked for membership only.
    const checkKnownAreas = (csv: string, where: string) => {
      // Comma-joined, mirroring `SOLEUR_SYNC_TOOLCHAIN_MISSING … affects=c4,coverage`.
      for (const area of csv.split(",")) {
        if (!KNOWN_AREAS.has(area)) {
          violations.push(
            `UNKNOWN affects= AREA ${JSON.stringify(area)} on ${where} — use one of ` +
              `${[...KNOWN_AREAS].join(", ")}, or add it to PRODUCER_AREA in this file ` +
              "(a reviewable diff, which is the point)",
          );
        }
      }
    };

    for (const inv of producers) {
      const rel = relOf(inv);
      const body = p!.fences[inv.fenceIdx].body;
      const marker = body.find((l) =>
        l.includes(`SOLEUR_SYNC_PRODUCER_MISSING producer=${rel}`),
      );
      if (!marker) {
        violations.push(
          `GUARD EMITS NO MARKER: ${rel} — its else-branch in ` +
            `plugins/soleur/commands/sync.md must echo ` +
            `"SOLEUR_SYNC_PRODUCER_MISSING producer=${rel} affects=<area> ` +
            `reason=absent-from-verified-root"`,
        );
        continue;
      }
      marked.add(rel);
      // `[^\s"]+`, not `\S+`: the marker is inside a shell double-quoted string,
      // so `\S+` swallows the closing quote and every area reads as unknown.
      const declared = marker.match(/\baffects=([^\s"]+)/);
      if (!declared) {
        violations.push(
          `MARKER MISSING affects=: ${rel} — add affects=<area> to its ` +
            "SOLEUR_SYNC_PRODUCER_MISSING line in plugins/soleur/commands/sync.md",
        );
        continue;
      }
      const expected = PRODUCER_AREA.get(rel);
      if (expected === undefined) {
        violations.push(
          `PRODUCER NOT IN THE AREA MAP: ${rel} — add it to PRODUCER_AREA in this file ` +
            "with the area its absence degrades (a reviewable diff, which is the point)",
        );
      } else if (declared[1] !== expected) {
        violations.push(
          `WRONG affects= AREA on ${rel}: declares ${JSON.stringify(declared[1])}, ` +
            `expected ${JSON.stringify(expected)} — the operator message interpolates this ` +
            "token, so a swap tells the user the wrong step of their sync did not run",
        );
      }
    }

    // The sibling toolchain marker shares this affects= vocabulary. Validating
    // only one of the two lets them drift with nothing red.
    const sibling = readFileSync(SYNC_MD, "utf8").match(
      /SOLEUR_SYNC_TOOLCHAIN_MISSING[^\n]*?\baffects=([^\s"]+)/,
    );
    if (!sibling) {
      violations.push(
        "SIBLING MARKER NOT FOUND: expected a SOLEUR_SYNC_TOOLCHAIN_MISSING … affects=<areas> " +
          "line in plugins/soleur/commands/sync.md — if it was renamed, update this assertion",
      );
    } else {
      checkKnownAreas(sibling[1], "SOLEUR_SYNC_TOOLCHAIN_MISSING");
    }

    check(violations).toEqual([]);
    // Parity as SET equality, never a count: a count cannot see a rename.
    check([...marked].sort()).toEqual([...rels].sort());
  });

  it("P8: go.md's guards name the absence they skip on", () => {
    // P6 proves go.md's invocations are guarded; P7 is sync.md-scoped. Between them,
    // go.md's ATTRIBUTION half was pinned by nothing — measured, deleting both `else`
    // branches (leaving `if [ -f … ]; then <invoke>; fi`) left the whole suite green.
    // That is exactly the defect #7474 exists to fix — a guard that skips silently —
    // reintroducible on the surface that runs at EVERY session start.
    //
    // go.md deliberately reuses its own marker families rather than SOLEUR_SYNC_*: these
    // are not sync producers, and SOLEUR_GIT_REPO_DIAG is already mirrored by
    // apps/web-platform/server/git-lock-marker-telemetry.ts.
    const GO_MD = resolve(COMMANDS_DIR, "go.md");
    const REQUIRED: ReadonlyArray<{ producer: string; marker: string }> = [
      {
        producer: "skills/git-worktree/scripts/git-repo-readiness-diag.sh",
        marker: "SOLEUR_GIT_REPO_DIAG source=probe-unreachable reason=absent-from-verified-root",
      },
      {
        producer: "skills/git-worktree/scripts/worktree-manager.sh",
        // The reason= is load-bearing, not decoration: this fence ALSO carries the
        // pre-existing identity-failure arm `SOLEUR_SESSION_START_SKIPPED
        // reason=plugin-root-unverified`, so pinning the bare marker name is satisfied
        // by that sibling — measured, deleting this else-branch passed.
        marker: "SOLEUR_SESSION_START_SKIPPED reason=absent-from-verified-root",
      },
    ];
    const p = parsed.find((x) => x.file === GO_MD);
    const violations: string[] = [];
    if (!p) violations.push("go.md is absent from the parsed command surface");

    for (const { producer, marker } of REQUIRED) {
      const inv = (p?.invocations ?? []).find(
        (i) => i.fenceIdx !== -1 && unquote(i.operand) === `${ANCHOR_PREFIX}${producer}`,
      );
      if (!inv) {
        violations.push(
          `GO.MD INVOCATION MISSING: ${producer} — this assertion pins its guard; if the ` +
            "invocation was intentionally removed, remove its entry from REQUIRED here too",
        );
        continue;
      }
      const emits = p!.fences[inv.fenceIdx].body.some((l) => l.includes(marker));
      if (!emits) {
        violations.push(
          `GO.MD GUARD IS SILENT: ${producer} — its else-branch must echo ${JSON.stringify(marker)} ` +
            "so a torn install is NAMED rather than skipped without a word, in plugins/soleur/commands/go.md",
        );
      }
    }
    check(violations).toEqual([]);
  });

  it("P5: the suite ran every assertion (anti-vacuity floor)", () => {
    // Neutering or deleting an assertion otherwise leaves the file green.
    // Absolute, ratcheted by hand — never derived from the assertions themselves,
    // which would simply descend with a deletion.
    //
    // Counts DECIDED assertions (see `check`), not `it` blocks: a per-block counter is
    // satisfied by a block whose body was gutted.
    expect(assertions).toBe(14);
  });
});

/* -------------------------------------------------------------------------- *
 * #7450 — the skills SECRET-GATE subset (ADR-179 §R5).
 * -------------------------------------------------------------------------- */

const SKILLS_DIR = resolve(REPO_ROOT, "plugins/soleur/skills");

/**
 * Gate scripts not discoverable by the shape below. CLOSED, deliberately:
 * widening it is a reviewable diff, which is the ADR-155 / ADR-179-decision-6
 * closed-vocabulary shape reused here rather than a self-serve syntactic marker.
 *
 * NAMED RESIDUAL: a new gate script matching neither the shape nor this set is
 * not auto-covered.
 */
const GATE_SCRIPT_EXTRAS: ReadonlySet<string> = new Set(["token-efficiency-report.sh"]);

/**
 * Discovery shape for the script axis.
 *
 * WIDENED past `redact-*.sh` (#7450 review): the engine behind the incident shim is
 * `redact-engine.py` and the operator-digest egress gate is `digest-scrub.sh`.
 * Neither is referenced from any SKILL.md today — both are reached BASH_SOURCE-relative
 * or via `$GITHUB_WORKSPACE`, which is layout-invariant per ADR-178 and NOT the #7450
 * vector. They are admitted to the POPULATION precisely because that is the property
 * nothing asserted: review-finding §F records `code-to-prd` as "not an uncovered gate …
 * but it IS outside the guard's population, so nothing asserts it stays that way".
 * Being in the population means the day one of them acquires a SKILL.md reference, the
 * anchoring rule applies to it without anyone remembering to widen this file.
 */
const GATE_SCRIPT_RE = /^(?:redact-.+\.(?:sh|py)|digest-scrub\.sh)$/;

/**
 * The gate references this corpus is expected to contain, as an IDENTITY SET.
 *
 * Replaces a `>= 4` floor (#7450 review-finding A10). A floor fails OPEN on
 * additions: it is loud on a removal but the first legitimate fifth site converts
 * zero slack into slack, and from then on the bare-basename detection can be
 * deleted with the count still satisfied. Pinning the identity makes BOTH directions
 * a reviewable diff, and makes the cardinality a consequence rather than a separate
 * hand-ratcheted number that can drift away from the thing it counts.
 *
 * Sorted `<repo-relative SKILL.md> -> <basename>` with duplicates retained, so a
 * second reference from the same file is also a diff. Derived with:
 *   git grep -noE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9._/-]*(redact-[A-Za-z0-9._-]*\.(sh|py)|digest-scrub\.sh|token-efficiency-report\.sh)' \
 *     -- 'plugins/soleur/skills/ * /SKILL.md'    (spaced: a literal glob would close this comment)
 */
const EXPECTED_GATE_REFS: readonly string[] = [
  "plugins/soleur/skills/compound/SKILL.md -> token-efficiency-report.sh",
  "plugins/soleur/skills/incident/SKILL.md -> redact-sentinel.sh",
  "plugins/soleur/skills/legal-generate/SKILL.md -> redact-sentinel.sh",
  "plugins/soleur/skills/linear-fetch/SKILL.md -> redact-linear-urls.sh",
];

/**
 * The skills whose gate authorises a SECRET-bearing action, and which therefore
 * MUST carry the ADR-179 decision-2 identity preflight.
 *
 * Pinned rather than derived. G5 previously self-disarmed via
 * `if (gateRefs(f, secret).length === 0) continue` — so removing a skill's anchored
 * reference removed its obligation to carry the preflight at the same time
 * (#7450 review-finding A11). Deriving the population from the very thing the guard
 * polices is the circularity; the equality assertion below keeps the pin honest in
 * the other direction.
 */
const SECRET_GATE_SKILLS: readonly string[] = [
  "plugins/soleur/skills/incident/SKILL.md",
  "plugins/soleur/skills/legal-generate/SKILL.md",
  "plugins/soleur/skills/linear-fetch/SKILL.md",
];

function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Discovered ON DISK, so a newly added `redact-foo.sh` is covered without editing
 * this file — the script axis is derived, not a snapshot.
 *
 * `.test.sh` is excluded: `redact-linear-urls.test.sh` matches the discovery shape
 * but is a suite, not a gate. Requiring it to be reached through the anchor would
 * assert an execution property of a test harness.
 */
function secretGateScripts(): Set<string> {
  const out = new Set<string>();
  for (const skill of readdirSync(SKILLS_DIR, { withFileTypes: true })) {
    if (!skill.isDirectory()) continue;
    const scriptsDir = resolve(SKILLS_DIR, skill.name, "scripts");
    if (!existsSync(scriptsDir)) continue;
    for (const e of readdirSync(scriptsDir, { withFileTypes: true })) {
      if (!GATE_SCRIPT_RE.test(e.name) || e.name.endsWith(".test.sh")) continue;
      // `isFile()` is FALSE for a symlink, so a symlinked gate script would drop
      // out of the population silently. stat follows the link.
      const full = resolve(scriptsDir, e.name);
      if (e.isFile() || (e.isSymbolicLink() && existsSync(full) && statSync(full).isFile())) {
        out.add(e.name);
      }
    }
  }
  return out;
}

/**
 * Every SKILL.md, not the four filenames this was written against.
 *
 * Symlink-tolerant in both directions (#7450 review): `Dirent.isFile()` and
 * `isDirectory()` both report FALSE for a symlink, so a symlinked SKILL.md — or a
 * skill directory that is a symlink — silently left the scanned corpus, taking every
 * assertion about it along. Cycles are broken on the resolved path.
 */
function skillFiles(): string[] {
  const out: string[] = [];
  const visited = new Set<string>();
  const walk = (dir: string) => {
    const real = realpathSync(dir);
    if (visited.has(real)) return;
    visited.add(real);
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const full = resolve(dir, e.name);
      if (!existsSync(full)) continue; // dangling symlink
      const st = statSync(full);
      if (st.isDirectory()) walk(full);
      else if (st.isFile() && e.name === "SKILL.md") out.push(full);
    }
  };
  walk(SKILLS_DIR);
  return [...new Set(out)].sort();
}

interface GateRef {
  /** repo-relative */
  file: string;
  seg: string;
  lineIdx: number;
  script: string;
  /** THIS occurrence is reached through the bare anchor. */
  anchored: boolean;
  /** THIS occurrence's anchored operand is double-quoted. */
  quoted: boolean;
  /** A bare basename in COMMAND position — a CWD-relative invocation. */
  bareCommand: boolean;
}

/**
 * Gate-script references in CODE CONTEXT — fence bodies and inline spans only.
 * Scoping to code context is what excludes markdown link targets such as
 * `[redact-sentinel.sh](../incident/scripts/redact-sentinel.sh)`, which are
 * documentation and not execution paths.
 *
 * PER-OCCURRENCE, not per-line (#7450 review-findings A1/A9). The previous form
 * emitted one record per (line, script) and asked whether the LINE contained a
 * compliant reference anywhere. Two measured consequences, both green:
 *
 *   - intra-line multiplicity — `SENTINEL="${CLAUDE_PLUGIN_ROOT}/…"; [[ -x "$SENTINEL" ]] ||
 *     SENTINEL="$(git rev-parse --show-toplevel)/…"` is the removed fallback pattern
 *     rewritten as a one-liner, and the compliant half certified the hostile half;
 *   - comment launder — appending `# ${CLAUDE_PLUGIN_ROOT}/…/redact-sentinel.sh` to a
 *     hostile line certified it, because a body-grep cannot tell an explanation from
 *     an occurrence.
 *
 * Deciding each occurrence on the text that PRECEDES it (`head`, suffix-anchored)
 * closes both: a compliant occurrence elsewhere on the line — in code or in a
 * comment — is simply a different occurrence with its own verdict.
 */
function gateRefsIn(rel: string, src: string, gates: Set<string>): GateRef[] {
  const lines = src.split("\n");
  const { fences } = parse(rel, src);
  const inFence = (i: number) => fences.some((f) => i > f.startIdx && i < f.endIdx);
  const out: GateRef[] = [];

  for (let i = 0; i < lines.length; i++) {
    const fenced = inFence(i);
    const segments = fenced
      ? [lines[i]]
      : [...lines[i].matchAll(/`([^`]+)`/g)].map((m) => m[1]);

    for (const seg of segments) {
      for (const g of gates) {
        // (1) PATH-form occurrences. A leading `/` is required so a bare prose
        //     mention of the basename is not read as a path.
        for (const m of seg.matchAll(new RegExp(String.raw`/${escapeRe(g)}`, "g"))) {
          const end = m.index! + m[0].length;
          const head = seg.slice(0, end);
          const am = head.match(
            new RegExp(String.raw`\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9._/-]*${escapeRe(g)}$`),
          );
          const anchored = am !== null;
          // Quoting is decided on THIS occurrence's own delimiters, not on the
          // presence of a quote somewhere on the line.
          const quoted =
            anchored && head[head.length - am![0].length - 1] === '"' && seg[end] === '"';
          out.push({
            file: rel,
            seg: seg.trim(),
            lineIdx: i,
            script: g,
            anchored,
            quoted,
            bareCommand: false,
          });
        }

        // (2) BARE-BASENAME occurrences in COMMAND position — `cd <dir> && bash
        //     redact-sentinel.sh`. Measured to yield ZERO refs under the path-form
        //     scan (#7450 review-finding A11), which made it invisible to the
        //     anchoring assertion AND disarmed the preflight requirement with it.
        //     Fence context only: prose backticks legitimately name the basename
        //     ("`redact-sentinel.sh` is a thin shim over…").
        if (!fenced) continue;
        const bareRe = new RegExp(
          String.raw`(?:^|\||&&|;|\bthen\b|\bdo\b|\$\()\s*(?:\w+=\S*\s+)*(?:${RUNNERS})\s+["']?${escapeRe(g)}\b`,
          "g",
        );
        for (const _m of seg.matchAll(bareRe)) {
          out.push({
            file: rel,
            seg: seg.trim(),
            lineIdx: i,
            script: g,
            anchored: false,
            quoted: false,
            bareCommand: true,
          });
        }
      }
    }
  }
  return out;
}

/**
 * The preflight's OWN logical statement.
 *
 * G5 previously accepted ANY `exit 2` below the preflight line in the same fence
 * (#7450 review-finding A2). Every secret gate carries a SECOND fail-closed check
 * immediately below — `[[ -r "$SENTINEL" ]] || { …; exit 2; }` — so converting the
 * identity preflight's own halt to `true; }` left the suite green while the gate
 * became fail-OPEN on exactly the check ADR-179 decision 2 exists for. Co-location
 * was being asserted; dispatch was not.
 *
 * Walks back over `\`-continuations to the statement start, then forward until brace
 * depth returns to zero with no continuation pending — i.e. the end of the
 * preflight's own `|| { … }` arm, and nothing after it.
 */
function preflightStatement(body: string[], relIdx: number): string[] | null {
  let start = relIdx;
  while (start > 0 && /\\\s*$/.test(body[start - 1])) start -= 1;

  const out: string[] = [];
  let depth = 0;
  for (let i = start; i < body.length; i++) {
    const l = body[i];
    out.push(l);
    for (const ch of l) {
      if (ch === "{") depth += 1;
      else if (ch === "}") depth -= 1;
    }
    if (i >= relIdx && depth <= 0 && !/\\\s*$/.test(l)) return out;
  }
  return null;
}

/**
 * Synthesized hostile corpora (`cq-test-fixtures-synthesized-only`).
 *
 * Every assertion in this block otherwise quantifies over a 100%-compliant tree, so
 * `violations` is structurally always `[]` and the predicates are unfalsifiable
 * (#7450 review-finding A13). Measured consequence: `reachedThroughAnchor` could be
 * replaced with `return true` and the suite stayed green (A3).
 *
 * These are the POSITIVE CONTROL. Each hostile fixture must be flagged and the
 * compliant one must not, so the predicate is proven to DISCRIMINATE rather than
 * merely to pass.
 */
const ANCHOR_FIXTURES: ReadonlyArray<{
  name: string;
  src: string;
  /** null = must produce no violation. */
  mustFlag: "anchor" | "quoting" | "bare-command" | null;
}> = [
  {
    name: "compliant: quoted bare anchor in a bash fence",
    src: '```bash\nbash "${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh" x\n```\n',
    mustFlag: null,
  },
  {
    name: "compliant: prose backtick mention of the basename is documentation",
    src: "`redact-sentinel.sh` is a thin shim over the hardened engine.\n",
    mustFlag: null,
  },
  {
    name: "hostile: git-root anchor (the #7450 vector verbatim)",
    src: '```bash\nbash "$(git rev-parse --show-toplevel)/plugins/soleur/skills/incident/scripts/redact-sentinel.sh" x\n```\n',
    mustFlag: "anchor",
  },
  {
    name: "hostile: intra-line multiplicity — compliant and hostile on ONE line (A1)",
    src:
      "```bash\n" +
      'SENTINEL="${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh"; ' +
      '[[ -x "$SENTINEL" ]] || SENTINEL="$(git rev-parse --show-toplevel)/skills/incident/scripts/redact-sentinel.sh"\n' +
      "```\n",
    mustFlag: "anchor",
  },
  {
    name: "hostile: comment launder — a compliant path in a trailing comment (A9)",
    src:
      "```bash\n" +
      "bash ./scripts/redact-sentinel.sh x " +
      "# ${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh\n" +
      "```\n",
    mustFlag: "anchor",
  },
  {
    name: "hostile: anchored but UNQUOTED (A8)",
    src: "```bash\nbash ${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh x\n```\n",
    mustFlag: "quoting",
  },
  {
    name: "hostile: bare basename in command position, CWD-relative (A11)",
    src: '```bash\ncd "$dir" && bash redact-sentinel.sh x\n```\n',
    mustFlag: "bare-command",
  },
];

describe("plugin-root anchoring — skills secret-gate subset (#7450)", () => {
  const secret = secretGateScripts();
  const gates = new Set<string>([...secret, ...GATE_SCRIPT_EXTRAS]);
  const files = skillFiles();
  const rel = (f: string) => f.replace(REPO_ROOT + "/", "");
  const refs = files.flatMap((f) => gateRefsIn(rel(f), readFileSync(f, "utf8"), gates));

  let assertions = 0;
  /**
   * Counts a DECIDED assertion — same contract as the command surface's `check`.
   * A `seen()` at the top of an `it` certifies that a BLOCK ran, which a gutted body
   * satisfies; and anything appended BELOW the floor block is outside the count
   * entirely (#7450 review-finding A5, measured green at 17 tests).
   */
  const check = <T>(actual: T) => {
    assertions += 1;
    return expect(actual);
  };

  it("G0: gate-script discovery is non-empty, typed, and every extra exists on disk", () => {
    // If discovery silently yielded nothing, every assertion below quantifies
    // over an empty set and passes.
    check(secret.size).toBeGreaterThanOrEqual(3);
    check([...gates].filter((g) => g.endsWith(".test.sh"))).toEqual([]);
    // An extra naming a script that no longer exists is a silently-empty axis:
    // the closed set keeps asserting a name nothing can match.
    const ghosts = [...GATE_SCRIPT_EXTRAS].filter(
      (g) =>
        !readdirSync(SKILLS_DIR, { withFileTypes: true }).some((s) =>
          existsSync(resolve(SKILLS_DIR, s.name, "scripts", g)),
        ),
    );
    check(ghosts).toEqual([]);
  });

  it("G1: every scanned SKILL.md has balanced fences", () => {
    // An unbalanced fence drops every reference after it, making the scan
    // vacuous rather than failing.
    check(files.filter((f) => !parse(f).fencesBalanced).map(rel)).toEqual([]);
  });

  it("G2: every gate-script OCCURRENCE is reached through the bare anchor", () => {
    const violations = refs
      .filter((r) => !r.bareCommand && !r.anchored)
      .map((r) => `${r.file}:${r.lineIdx + 1}: ${r.seg}`);
    check(violations).toEqual([]);
  });

  it("G2b: no gate script is invoked by bare basename (CWD-relative)", () => {
    const violations = refs
      .filter((r) => r.bareCommand)
      .map((r) => `${r.file}:${r.lineIdx + 1}: ${r.seg}`);
    check(violations).toEqual([]);
  });

  it("G3: the gate-reference population is exactly the pinned identity set", () => {
    // DEDUPED, because this assertion is about the identity SET — which (file, script) pairs
    // exist — not about how many times each is written. Per-OCCURRENCE coverage is G2/G2b's
    // job (they filter over every ref, which is finding A1's fix) and G4/G4b's, so nothing is
    // lost here: a second occurrence of an already-pinned pair is still individually checked
    // for anchoring, quoting, containment and existence.
    //
    // The distinction is load-bearing rather than cosmetic. `linear-fetch` must re-derive
    // `SCRUBBER` in its Phase D fence because each fenced block is a separate Bash call and
    // shell state does not persist — omitting that is what bricked the skill (#7450 review).
    // An occurrence-counting comparison rejects the correct code while a NEW pair, which is
    // the thing this assertion exists to catch, still reds.
    const found = [
      ...new Set(refs.filter((r) => !r.bareCommand).map((r) => `${r.file} -> ${r.script}`)),
    ].sort();
    check(found).toEqual([...EXPECTED_GATE_REFS]);
  });

  it("G4: every gate reference resides INSIDE the plugin payload and exists", () => {
    const bad: string[] = [];
    for (const r of refs) {
      if (!r.anchored) continue; // non-anchored refs are already reported by G2/G2b
      const m = r.seg.match(
        new RegExp(String.raw`\$\{CLAUDE_PLUGIN_ROOT\}/([A-Za-z0-9._/-]*${escapeRe(r.script)})`),
      );
      if (!m) continue;
      const abs = resolve(PAYLOAD_ROOT, m[1]);
      if (!abs.startsWith(PAYLOAD_ROOT + "/")) bad.push(`ESCAPES PAYLOAD: ${r.seg}`);
      else if (!existsSync(abs)) bad.push(`NOT RESIDENT: plugins/soleur/${m[1]}`);
    }
    check(bad).toEqual([]);
  });

  it("G4b: every anchored operand is quoted", () => {
    // The header declares the canonical form QUOTED and the command surface
    // enforces it at P1c; the skills axis asserted it nowhere, and an unquoted
    // operand word-splits on any root containing a space (#7450 review-finding A8).
    const unquoted = refs
      .filter((r) => r.anchored && !r.quoted)
      .map((r) => `${r.file}:${r.lineIdx + 1}: ${r.seg}`);
    check(unquoted).toEqual([]);
  });

  it("G5: the SECRET-gate population is exactly as pinned", () => {
    // Both directions: a new skill that references a secret gate without being
    // listed here, and a listed skill whose reference was removed. Deriving the
    // population from the references alone is what let a removal silently retire
    // the preflight obligation along with the reference it was attached to.
    const derived = files
      .filter((f) => gateRefsIn(rel(f), readFileSync(f, "utf8"), secret).length > 0)
      .map(rel)
      .sort();
    check(derived).toEqual([...SECRET_GATE_SKILLS]);
  });

  it("G5b: every SECRET-gate skill's identity preflight halts in its OWN arm", () => {
    // ADR-179 decision 2. `[[ -r "$SENTINEL" ]]` is a SHAPE check of exactly the
    // kind ADR-179 §(a) measured as bypassable — with an ambient CLAUDE_PLUGIN_ROOT
    // pointing at an attacker-chosen directory, a `test -d` preflight PASSED and the
    // hostile payload executed. The preflight must verify plugin IDENTITY, and the
    // halt asserted here must be the one BOUND to that verification.
    const missing: string[] = [];
    for (const relPath of SECRET_GATE_SKILLS) {
      const f = resolve(REPO_ROOT, relPath);
      const lines = readFileSync(f, "utf8").split("\n");
      const { fences } = parse(f);
      const pIdx = lines.findIndex((l) => l.includes(PREFLIGHT_ANCHOR));
      if (pIdx === -1) {
        missing.push(`${relPath} (no identity preflight)`);
        continue;
      }
      const fence = fences.find((fc) => pIdx > fc.startIdx && pIdx < fc.endIdx);
      if (!fence) {
        missing.push(`${relPath} (identity preflight is not inside a code fence)`);
        continue;
      }
      const stmt = preflightStatement(fence.body, pIdx - (fence.startIdx + 1));
      if (!stmt) {
        missing.push(`${relPath} (preflight statement does not terminate in its fence)`);
        continue;
      }
      if (!stmt.some((l) => /\bexit 2\b/.test(l))) {
        missing.push(
          `${relPath} (preflight present, but its OWN arm does not exit 2 — ` +
            "a sibling halt elsewhere in the fence does not make this check fail-closed)",
        );
      }
    }
    check(missing).toEqual([]);
  });

  it("G5c: a preflight whose own arm does not halt is REJECTED (positive control)", () => {
    // The A2 control, committed rather than run once as a mutation. Every real gate
    // carries a SECOND fail-closed check below the identity preflight, so "is there an
    // `exit 2` after the preflight line, in this fence?" was satisfied by the SIBLING
    // check's halt — measured green with the identity preflight's own arm converted to
    // `true; }`. These two fixtures differ ONLY in that arm; if `preflightStatement`
    // ever widens back to fence scope, the second one starts passing and this reds.
    const armed = [
      '[ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] \\',
      "  && grep -q '\"name\"' \"${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json\" \\",
      '  || { echo "halt" >&2',
      "       exit 2; }",
      'SENTINEL="${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh"',
      '[[ -r "$SENTINEL" ]] || { echo "not readable" >&2',
      "       exit 2; }",
    ];
    const failOpen = armed.map((l, i) => (i === 3 ? "       true; }" : l));

    const haltsInOwnArm = (body: string[]) => {
      const idx = body.findIndex((l) => l.includes(PREFLIGHT_ANCHOR));
      const stmt = preflightStatement(body, idx);
      return stmt !== null && stmt.some((l) => /\bexit 2\b/.test(l));
    };

    check(haltsInOwnArm(armed)).toBe(true);
    // The sibling `[[ -r ]]` halt is still present below — it must NOT satisfy this.
    check(haltsInOwnArm(failOpen)).toBe(false);
  });

  it("G6: the predicates discriminate — synthesized hostile corpora are flagged", () => {
    // Positive control. Without it every assertion above is a statement about a
    // compliant tree and cannot fail; measured, `reachedThroughAnchor` -> `return true`
    // kept the whole block green.
    const wrong: string[] = [];
    for (const fx of ANCHOR_FIXTURES) {
      const got = gateRefsIn("FIXTURE/SKILL.md", fx.src, gates);
      const flagged =
        got.some((r) => r.bareCommand)
          ? "bare-command"
          : got.some((r) => !r.anchored)
            ? "anchor"
            : got.some((r) => r.anchored && !r.quoted)
              ? "quoting"
              : null;
      if (flagged !== fx.mustFlag) {
        wrong.push(`${fx.name}: expected ${fx.mustFlag ?? "no violation"}, got ${flagged ?? "none"}`);
      }
    }
    check(wrong).toEqual([]);
  });

  it("G6b: the fixture corpus itself covers every predicate", () => {
    // A fixture set that drifted to all-compliant would make G6 vacuous in turn.
    const covered = new Set(ANCHOR_FIXTURES.map((f) => f.mustFlag));
    check([...covered].sort()).toEqual([null, "anchor", "bare-command", "quoting"].sort());
  });

  it("G8: no operator-config auto-approval carries a rejected anchor form", () => {
    // ADR-179 decision 8. `.claude/settings.json` is operator config, so decision 1's
    // "plugin markdown" scope did not reach it — and a `permissions.allow` match executes
    // with NO prompt at all, which makes it the cheapest exploitation shape in the corpus.
    // The entry this replaced was measured DEAD (every git-worktree site emits the `:-`
    // form, so it matched nothing Soleur emits); it was removed for the second reason,
    // which is that an agent reading settings.json learns the sanctioned shape from it.
    const settingsPath = resolve(REPO_ROOT, ".claude/settings.json");
    check(existsSync(settingsPath)).toBe(true);
    const settings = JSON.parse(readFileSync(settingsPath, "utf8")) as {
      permissions?: { allow?: string[]; deny?: string[] };
    };
    const allow = settings.permissions?.allow ?? [];
    // Population floor: an empty allow-list would satisfy the ban vacuously.
    check(allow.length).toBeGreaterThanOrEqual(5);
    check(allow.filter((e) => e.includes("$(git rev-parse") || e.includes("${CLAUDE_PLUGIN_ROOT:-"))).toEqual(
      [],
    );
  });

  it("G7: the suite ran every assertion (anti-vacuity floor)", () => {
    // Absolute, ratcheted by hand — never derived from the assertions themselves,
    // which would simply descend with a deletion. Counts DECIDED assertions.
    //
    // NOTE: an in-file floor dies with the block it counts — deleting this whole
    // `describe` was measured GREEN at 9 tests (#7450 review-finding A4). The
    // CROSS-FILE floor that survives that deletion lives in Guard 2,
    // `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` Test 20, which
    // runs in a DIFFERENT test-all shard (`want_scripts` vs `want_webplat`).
    expect(assertions).toBe(18);
  });
});
