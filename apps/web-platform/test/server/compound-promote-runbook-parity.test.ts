// WikiSkill Phase 2 (#10550), review round -- the runbook names every closed `create_detail` token the code can emit,
// and (the reverse direction) every token the runbook's `create_detail` table lists is one the code can emit.
// Own file: it reads the runbook, which lives outside apps/web-platform (so it is a REPO_WIDE suite, see
// test/repo-wide-suites.ts). Window: the three create modules, each read whole; the runbook, read whole.
//
// MATCHING IS EXACT. A detail token counts as documented only when the runbook contains it as a whole backticked
// token (`token`). A token the code builds from a template (`instruction-risk:${label}`, `failed-${stage}`) is
// documented through its PREFIX FORM: the code yields the prefix (`instruction-risk:`, `failed-`) and the runbook must
// contain a backticked string that starts with that prefix and continues with a `<placeholder>` (`failed-<stage>`)
// or, for a `:` prefix, a concrete `prefix:rule` example.
import { describe, expect, it, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const SERVER_DIR = join(__dirname, "..", "..", "server");
const CREATE_MODULE = join(SERVER_DIR, "compound-promote-create.ts");
const CREATE_ARM = join(SERVER_DIR, "compound-promote-create-arm.ts");
const CREATE_GATES = join(SERVER_DIR, "compound-promote-create-gates.ts");
const RUNBOOK = join(__dirname, "..", "..", "..", "..", "knowledge-base", "engineering", "operations", "runbooks", "compound-promote-runbook.md");

/** The census at HEAD of this change: a floor, so a census that silently finds fewer tokens reads RED, not clean. */
export const TOKEN_FLOOR = 104;

const code = (f: string): string => readFileSync(f, "utf-8").split("\n").map((l) => l.replace(/^\s*\/\/.*$/, "").replace(/^\s*\*.*$/, "").replace(/^\s*\/\*\*.*$/, "")).join("\n");

export interface Tokens {
  /** Whole tokens the code emits as a `detail`. */
  exact: string[];
  /** Prefixes of templated details (`failed-` for `failed-${stage}`, `instruction-risk:` for `instruction-risk:${label}`). */
  prefixes: string[];
}

/**
 * Detail literals. The call shapes that put a closed token in a refusal:
 *   - `fail(cls, "tok"`, `refusal(cls, "tok"`, `refuse(cls, "tok"` -- the second argument;
 *   - the gates' own constructors `scanRefusal("tok"`, `readmeRefusal("tok"`, `collectRefusal("tok"` -- the first;
 *   - `detail: "tok"` -- an object literal that carries one (the scan evaluation, the open-PR probe).
 * Templates: a backtick string starting with a slug then `${` in the detail position of the same call shapes, or a
 * `const detail = ... \`failed-${` assignment.
 */
export function detailTokens(src: string): Tokens {
  const exact: string[] = [];
  const prefixes: string[] = [];
  const FIRST_ARG_HELPERS = "scanRefusal|readmeRefusal|collectRefusal|gitFail";
  for (const m of src.matchAll(/\b(?:fail|refusal|refuse)\(\s*"[a-z-]+",\s*"([^"$]+)"/g)) exact.push(m[1]);
  for (const m of src.matchAll(new RegExp(`\\b(?:${FIRST_ARG_HELPERS})\\(\\s*"([^"$]+)"`, "g"))) exact.push(m[1]);
  for (const m of src.matchAll(/\bdetail:\s*"([a-z][a-z0-9-]*)"/g)) exact.push(m[1]);
  // a two-way literal in the detail position: `collectRefusal(missing ? "path-missing" : "path-not-regular", index)`
  for (const m of src.matchAll(new RegExp(`\\b(?:${FIRST_ARG_HELPERS})\\(\\s*[A-Za-z_.]+\\s*\\?\\s*"([a-z-]+)"\\s*:\\s*"([a-z-]+)"`, "g"))) exact.push(m[1], m[2]);
  for (const m of src.matchAll(/\b(?:fail|refusal|refuse)\(\s*"[a-z-]+",\s*`([a-z][a-z-]*[-:])\$\{/g)) prefixes.push(m[1]);
  // `const detail = a ? \`failed-${x}\` : \`not-committed-${y}\`;` -- EVERY template of the statement
  for (const stmt of src.matchAll(/\bdetail\s*=[^;]*;/g)) for (const t of stmt[0].matchAll(/`([a-z][a-z-]*[-:])\$\{/g)) prefixes.push(t[1]);
  return { exact, prefixes };
}

/** The tokens of all three modules, de-duplicated. */
export function collectTokens(sources: readonly string[]): Tokens {
  const all = sources.map(detailTokens);
  return { exact: [...new Set(all.flatMap((t) => t.exact))].sort(), prefixes: [...new Set(all.flatMap((t) => t.prefixes))].sort() };
}

const escapeRe = (s: string): string => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** Which tokens does the runbook NOT document? Exact backticked tokens only; a prefix needs a backticked prefix form. */
export function findMissing(tokens: Tokens, runbook: string): string[] {
  const missing: string[] = [];
  for (const t of tokens.exact) if (!runbook.includes(`\`${t}\``)) missing.push(t);
  for (const p of tokens.prefixes) {
    // `failed-<stage>` / `rendered-<file>:...` (a placeholder) or `instruction-risk:skill` / `empty:<file>` (a `:` prefix and its rule)
    const form = p.endsWith(":") ? new RegExp("`" + escapeRe(p) + "[a-z<][^`]*`") : new RegExp("`" + escapeRe(p) + "<[a-z-]+>[^`]*`");
    if (!form.test(runbook)) missing.push(`${p}*`);
  }
  return missing;
}

/**
 * The tokens the runbook's "`create_detail` values by class" table lists: per row, per comma-separated item, the
 * LEADING backticked token (an item's parenthetical may mention ops, numbers and fields; those are not details).
 */
export function runbookTableTokens(runbook: string): string[] {
  const start = runbook.indexOf("`create_detail` values by class");
  if (start < 0) return [];
  const rows: string[] = [];
  for (const line of runbook.slice(start).split("\n").slice(1)) {
    if (line.trim() === "" && rows.length > 0) break;
    if (line.startsWith("|") && !line.startsWith("|---") && !line.includes("`create_detail` values")) rows.push(line);
  }
  const out: string[] = [];
  for (const row of rows) {
    const cell = row.split("|")[2] ?? "";
    if (/^\s*`[a-z-]+` \(extra\)\s*$/.test(row.split("|")[1] ?? "")) continue; // the "(extra)" row documents Sentry causes, not details
    // split at top-level commas / "and" so a parenthetical with commas stays attached to its item
    let depth = 0;
    let item = "";
    const items: string[] = [];
    for (const ch of cell) {
      if (ch === "(") depth += 1;
      if (ch === ")") depth -= 1;
      if (ch === "," && depth === 0) {
        items.push(item);
        item = "";
      } else item += ch;
    }
    items.push(item);
    for (const it of items) {
      const lead = /^\s*(?:and\s+)?`([^`]+)`/.exec(it);
      if (lead) out.push(lead[1]);
    }
  }
  return out;
}

/** Runbook table tokens the code cannot emit: not an exact code token, not under a code prefix, not a documented `<field>:<rule>` form. */
export function findStale(tableTokens: readonly string[], tokens: Tokens): string[] {
  const exact = new Set(tokens.exact);
  return tableTokens.filter((t) => {
    if (exact.has(t)) return false;
    if (tokens.prefixes.some((p) => t.startsWith(p))) return false;
    // `<field>:<rule>` and `rendered-<file>:<...>` are the documented FORMS of tokens the code builds from model-field
    // labels (the labels and rules are closed sets in create.ts, covered by its own tests); a bare placeholder is not stale.
    if (t.includes("<")) return false;
    return true;
  });
}

describe("every closed refusal detail token in the create modules is in the runbook", () => {
  beforeEach(() => {
    expect.hasAssertions();
  });
  const runbook = readFileSync(RUNBOOK, "utf-8");
  const tokens = collectTokens([CREATE_MODULE, CREATE_ARM, CREATE_GATES].map(code));

  it("the census is not vacuous: it finds at least TOKEN_FLOOR tokens and the known template prefixes", () => {
    expect(tokens.exact.length).toBeGreaterThanOrEqual(TOKEN_FLOOR);
    expect(tokens.prefixes).toEqual(expect.arrayContaining(["instruction-risk:", "failed-", "not-committed-"]));
  });

  it("every detail literal appears, as an exact backticked token, in the runbook; every templated prefix has its prefix form", () => {
    expect(findMissing(tokens, runbook)).toEqual([]);
  });

  it("mutation: a token the runbook does not name, and a token that is only named without backticks, are both RED", () => {
    expect(findMissing({ exact: [...tokens.exact, "a-token-no-runbook-names"], prefixes: tokens.prefixes }, runbook)).toEqual(["a-token-no-runbook-names"]);
    // exact matching: `origin-failed` as bare text (no backticks) must not satisfy the check
    const unticked = runbook.replaceAll("`origin-failed`", "origin-failed");
    expect(unticked).not.toBe(runbook);
    expect(findMissing(tokens, unticked)).toContain("origin-failed");
    // a loose match would accept a token merely contained in a longer backticked string
    const longer = runbook.replaceAll("`origin-failed`", "`origin-failed-elsewhere`");
    expect(findMissing(tokens, longer)).toContain("origin-failed");
    // a templated prefix with no documented form is RED
    expect(findMissing({ exact: [], prefixes: ["brand-new-prefix-"] }, runbook)).toEqual(["brand-new-prefix-*"]);
  });

  it("reverse: every token the runbook's `create_detail` table lists is one the code can emit (a stale token is RED)", () => {
    const table = runbookTableTokens(runbook);
    expect(table.length).toBeGreaterThan(100); // non-vacuity: the table parse found its rows
    expect(findStale(table, tokens)).toEqual([]);
  });

  it("mutation: a stale runbook token is found by the reverse check", () => {
    expect(findStale([...runbookTableTokens(runbook), "no-strings"], tokens)).toEqual(["no-strings"]);
  });
});

describe("the runbook documents every closed Sentry extra token the create arm can set (extra.cause, extra.stage)", () => {
  beforeEach(() => {
    expect.hasAssertions();
  });
  const runbook = readFileSync(RUNBOOK, "utf-8");
  const arm = readFileSync(CREATE_ARM, "utf-8");

  it("every DEADLINE_STAGES token of the arm is a backticked token of the runbook", () => {
    const list = /export const DEADLINE_STAGES = \[([^\]]+)\] as const/.exec(arm)?.[1] ?? "";
    const stages = [...list.matchAll(/"([a-z-]+)"/g)].map((m) => m[1]);
    expect(stages.length).toBeGreaterThanOrEqual(12); // non-vacuity: the parse found the list
    expect(stages.filter((t) => !runbook.includes(`\`${t}\``))).toEqual([]);
  });

  it("every cause literal the arm builds for itself (not from an error object) is a backticked token of the runbook", () => {
    // `cause: "non-array"` (the listing) and the gitCause / originCause return literals
    const literals = new Set<string>();
    for (const m of arm.matchAll(/\bcause:\s*"([a-z-]+)"/g)) literals.add(m[1]);
    for (const m of arm.matchAll(/\breturn "([a-z-]+)";/g)) literals.add(m[1]);
    const mustHave = ["non-array", "bad-output", "timeout", "signal", "spawn", "symlink-refused", "set-url-failed"];
    for (const t of mustHave) expect(literals.has(t), `the arm no longer builds cause ${t}`).toBe(true);
    expect(mustHave.filter((t) => !runbook.includes(`\`${t}\``))).toEqual([]);
  });
});
