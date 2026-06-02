import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";

/**
 * Source-grep write-boundary sentinel (migration 059 / messages.workspace_id).
 *
 * Migration 059 made `messages.workspace_id` NOT NULL with an INSERT policy
 * `messages_workspace_member_insert` WITH CHECK
 * `is_workspace_member(workspace_id, auth.uid())`. EVERY interactive
 * `messages` INSERT must therefore populate `workspace_id` — omitting it
 * yields NULL → RLS reject → "An unexpected error occurred." (the outage).
 *
 * This test mechanically reads every server TypeScript file, finds every
 * `.from("messages").insert(<object-or-var>)`, and asserts the inserted
 * payload carries a `workspace_id` key. Service-role inserts bypass RLS but
 * are still swept (they already set it — `insert-draft-card.ts` is the
 * exemplar). A new insert site that omits `workspace_id` fails CI here.
 *
 * `hr-write-boundary-sentinel-sweep-all-write-sites`.
 */

// review (P3): scan every dir where a `messages` INSERT could live, not just
// server/. Today all interactive inserts are under server/, but a future
// insert added under app/api/ or inngest/ must be caught too. The matcher
// only fires on `.from("messages").insert(`, so widening the walk is safe
// (SELECT/UPDATE on messages elsewhere never match). Each dir is guarded for
// existence so the test stays green if a dir is absent.
const SCAN_DIRS = ["server", "app", "inngest", "lib"].map((d) =>
  resolve(__dirname, "..", "..", d),
);
const SERVER_DIR = resolve(__dirname, "..", "..", "server");

/** Recursively collect every `.ts` file under `dir`. No-op if `dir` is absent. */
function collectTsFiles(dir: string): string[] {
  const out: string[] = [];
  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch {
    return out; // dir absent — guarded per SCAN_DIRS comment
  }
  for (const entry of entries) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      out.push(...collectTsFiles(full));
    } else if (entry.endsWith(".ts") && !entry.endsWith(".d.ts")) {
      out.push(full);
    }
  }
  return out;
}

/**
 * Given source text, return the list of `messages` INSERT findings:
 * `{ index, payload }` where `payload` is the raw inserted argument source
 * (an object literal, a variable name, or the buildRow(...) call). The
 * matcher follows a single variable / function-return one hop to resolve the
 * payload's `workspace_id` presence (covers cc-dispatcher's `buildRow`).
 */
interface InsertFinding {
  /** The raw `.insert(` argument source (best-effort, balanced-paren). */
  argSource: string;
  /** Resolved payload source after a single hop (var decl / buildRow body). */
  resolvedPayload: string;
}

/** Extract the balanced-paren argument source starting at `openParenIdx`. */
function extractBalancedArg(src: string, openParenIdx: number): string {
  let depth = 0;
  for (let i = openParenIdx; i < src.length; i++) {
    const ch = src[i];
    if (ch === "(") depth++;
    else if (ch === ")") {
      depth--;
      if (depth === 0) return src.slice(openParenIdx + 1, i);
    }
  }
  return src.slice(openParenIdx + 1);
}

function findMessagesInserts(src: string): InsertFinding[] {
  const findings: InsertFinding[] = [];
  // Match `.from("messages").insert(` (allow whitespace/newlines between).
  const re = /\.from\(\s*["']messages["']\s*\)\s*\.insert\s*\(/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) {
    const openParen = re.lastIndex - 1;
    const argSource = extractBalancedArg(src, openParen);
    findings.push({ argSource, resolvedPayload: resolvePayload(argSource, src) });
  }
  return findings;
}

/**
 * Resolve the payload source for `workspace_id` detection. If the insert
 * argument is an inline object literal (`{ ... }`), use it directly. If it is
 * a bare identifier (e.g. `row` from `buildRow(...)`), find the value
 * threaded into that identifier OR the body of a `buildRow`-style function
 * that constructs the row — a single hop covers every real site.
 */
function resolvePayload(argSource: string, fullSrc: string): string {
  const trimmed = argSource.trim();
  if (trimmed.startsWith("{")) return trimmed;
  // Bare identifier: `const <id> = <expr>` or a builder function body.
  const idMatch = trimmed.match(/^[A-Za-z_$][\w$]*/);
  if (!idMatch) return trimmed;
  const id = idMatch[0];
  // (a) `const <id> = buildRow(...)` → inspect the builder fn body.
  const builderCall = new RegExp(
    `(?:const|let|var)\\s+${id}\\s*=\\s*([A-Za-z_$][\\w$]*)\\s*\\(`,
  ).exec(fullSrc);
  if (builderCall) {
    const fnName = builderCall[1];
    const fnBody = extractFunctionBody(fullSrc, fnName);
    if (fnBody) return fnBody;
  }
  // (b) `const <id> = { ... }` → the literal it was assigned.
  const literalAssign = new RegExp(
    `(?:const|let|var)\\s+${id}\\s*(?::[^=]+)?=\\s*({)`,
  ).exec(fullSrc);
  if (literalAssign) {
    const braceIdx = literalAssign.index + literalAssign[0].length - 1;
    return extractBalancedBrace(fullSrc, braceIdx);
  }
  return trimmed;
}

/** Return the source of the named function's body (best-effort). */
function extractFunctionBody(src: string, fnName: string): string | null {
  const declRe = new RegExp(`function\\s+${fnName}\\s*\\(`);
  const m = declRe.exec(src);
  if (!m) return null;
  // Find the opening `{` after the param list.
  const parenIdx = src.indexOf("(", m.index);
  const argEnd = matchingParen(src, parenIdx);
  const braceIdx = src.indexOf("{", argEnd);
  if (braceIdx === -1) return null;
  return extractBalancedBrace(src, braceIdx);
}

function matchingParen(src: string, openIdx: number): number {
  let depth = 0;
  for (let i = openIdx; i < src.length; i++) {
    if (src[i] === "(") depth++;
    else if (src[i] === ")") {
      depth--;
      if (depth === 0) return i;
    }
  }
  return src.length;
}

function extractBalancedBrace(src: string, openIdx: number): string {
  let depth = 0;
  for (let i = openIdx; i < src.length; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}") {
      depth--;
      if (depth === 0) return src.slice(openIdx, i + 1);
    }
  }
  return src.slice(openIdx);
}

/** Does the resolved payload assign `workspace_id`? */
function payloadHasWorkspaceId(payload: string): boolean {
  // Matches all three field forms:
  //   - `workspace_id: value`  (object key)
  //   - `workspace_id =`/`row.workspace_id =`  (builder-function assignment)
  //   - `workspace_id,` / `workspace_id }`  (ES6 shorthand property, e.g.
  //      insert-draft-card.ts's `const workspace_id = …; insert({ workspace_id })`).
  return /workspace_id\s*[:=]/.test(payload) ||
    /(?:^|[{,]\s*)workspace_id\s*(?:,|\n|\}|$)/.test(payload);
}

describe("messages INSERT write-boundary sweep — workspace_id present (mig 059)", () => {
  it("every server `.from(\"messages\").insert(...)` payload carries workspace_id", () => {
    const files = SCAN_DIRS.flatMap((d) => collectTsFiles(d));
    const violations: string[] = [];
    let totalFindings = 0;

    for (const file of files) {
      const src = readFileSync(file, "utf8");
      for (const finding of findMessagesInserts(src)) {
        totalFindings += 1;
        if (!payloadHasWorkspaceId(finding.resolvedPayload)) {
          violations.push(
            `${file}: insert payload missing workspace_id → ${finding.argSource.slice(0, 80)}`,
          );
        }
      }
    }

    // Guard against a vacuous pass (regex matching nothing). Floor = the 5
    // known insert sites today: cc-dispatcher user + assistant(buildRow),
    // agent-runner saveMessage + sendUserMessage, and the service-role
    // insert-draft-card exemplar. If a site is intentionally removed, lower
    // this floor deliberately (do not let it silently drop to a tight equality).
    expect(totalFindings).toBeGreaterThanOrEqual(5);
    expect(violations).toEqual([]);
  });

  it("NEGATIVE CONTROL: a synthetic insert lacking workspace_id is flagged", () => {
    // Proves the matcher is non-vacuous: a payload WITHOUT workspace_id must
    // be reported as a violation (otherwise the sweep could silently pass).
    const syntheticMissing = `
      await tenant.from("messages").insert({
        id: randomUUID(),
        conversation_id: conversationId,
        role: "user",
        content: rawUserMessage,
      });
    `;
    const findings = findMessagesInserts(syntheticMissing);
    expect(findings).toHaveLength(1);
    expect(payloadHasWorkspaceId(findings[0].resolvedPayload)).toBe(false);

    // And a synthetic insert WITH workspace_id must pass.
    const syntheticPresent = `
      await tenant.from("messages").insert({
        id: randomUUID(),
        conversation_id: conversationId,
        workspace_id: conversationWorkspaceId,
        role: "user",
        content: rawUserMessage,
      });
    `;
    const ok = findMessagesInserts(syntheticPresent);
    expect(ok).toHaveLength(1);
    expect(payloadHasWorkspaceId(ok[0].resolvedPayload)).toBe(true);
  });

  it("exemplar insert-draft-card.ts passes the sweep (already correct)", () => {
    const draftCard = readFileSync(
      join(SERVER_DIR, "messages", "insert-draft-card.ts"),
      "utf8",
    );
    const findings = findMessagesInserts(draftCard);
    expect(findings.length).toBeGreaterThanOrEqual(1);
    for (const f of findings) {
      expect(payloadHasWorkspaceId(f.resolvedPayload)).toBe(true);
    }
  });
});
