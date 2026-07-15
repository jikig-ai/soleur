// Guards agent-facing guidance against prescribing DETERMINISTIC /tmp scratch paths.
//
// THE DEFECT THIS EXISTS FOR. A path like `/tmp/<script>.log` is a pure function of the
// script name, so EVERY concurrent session that follows the guidance writes to the SAME
// file. Parallel worktrees are this repo's documented workflow (14 were live when this was
// written), so the collision is the normal case, not the edge case. Observed 2026-07-15: a
// full-suite run's log was truncated mid-run by a sibling session and came back holding a
// DIFFERENT worktree's absolute paths. The exit code was still that run's own, but the log —
// the artifact you read to learn WHICH suite failed — belonged to someone else. The
// dangerous inverse is reading a sibling's GREEN log and concluding your own run passed.
//
// WHY THE ANCHOR IS THE HAZARD, NOT THE SYNTAX. The obvious guard — grep for `> /tmp/…` — is
// wrong twice, and this file's first draft was wrong in exactly the way it faulted:
//   1. A redirect-only anchor is blind to `curl -o /tmp/x`, `cp f /tmp/x.bak`, `tee`,
//      `unzip -d /tmp`. It also matches `cp <file> /tmp/<file>.bak` only BY ACCIDENT — the
//      `>` it "finds" is the closing bracket of the `<file>` placeholder, not a redirect.
//      Normalize that away and the guard silently returns 0 on the highest-severity site.
//   2. A `[A-Za-z0-9_.-]` path class is blind to `/tmp/<script>.log` — the very line that
//      caused the class — because `<` and `>` are not in it.
// So: match a /tmp/ path at a PATH BOUNDARY, reached by a write verb, with each verb family
// as its OWN alternation. `>` never does double duty.
//
// WHAT IS NOT A DEFECT. A scratch file written and read back inside ONE Bash call is fine —
// nothing outlives the command, so nothing can be clobbered by a sibling. The defect is a
// deterministic path that OUTLIVES its command. Waivers below are content-addressed and each
// carries a reason; "it's not a defect" is not an accepted reason where a real (if narrow)
// race exists — say that it is accepted and why.
//
// DOCUMENTED LIMITATIONS (deliberate, not oversights):
//   - Scope is `skills/*/SKILL.md`. Sibling prescriptive shell outside that glob is NOT
//     scanned (e.g. `skills/incident/scripts/dry-run.sh`). Widening the glob is a separate
//     change; a follow-up tracks it.
//   - This cannot see paths an agent IMPROVISES at runtime — the ~30 ad-hoc `/tmp/*.log`
//     paths in `.claude/logs/approvals.jsonl` were never written in any SKILL.md. Only a
//     PreToolUse Bash hook can reach those; a follow-up tracks it.
//   - No markdown-fence awareness. A hazard inside a ```text block still matches. That is
//     deliberate: an explicit waiver with a reason beats a silent skip.
//   - A /tmp string in VALUE position with no write verb reaching it is deliberately NOT a
//     hazard — e.g. `"screenshot_ref": "/tmp/anti-slop/no-screenshot.png"` in
//     `skills/frontend-anti-slop/SKILL.md` is a schema example documenting a sentinel value,
//     not an instruction to write there. It needs no waiver precisely because the write-verb
//     anchor already excludes it. If such a value ever becomes a write target, the verb
//     alternations will catch it.
import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { discoverSkills } from "./helpers";

// discoverSkills() returns paths relative to plugins/soleur — NOT the repo root. Rooting at
// the repo root ENOENTs on every read.
const PLUGIN_ROOT = resolve(import.meta.dir, "..");

// A /tmp/ path at a PATH BOUNDARY. The boundary is what excludes `${GITHUB_WORKSPACE}/tmp/…`
// (preceded by `}`, so not a boundary) — a variable-rooted path is already session-scoped and
// is COMPLIANT, not an offender. The class carries `<` `>` `$` `{` `}` `*` so placeholder and
// variable-bearing forms (`/tmp/<script>.log`, `/tmp/issue-$name.url`) are visible.
const TMP_PATH = String.raw`/tmp/[A-Za-z0-9_.<>\${}*/-]+`;
const BOUNDARY = String.raw`(?:^|[\s"'=])`;

// Each write family is its OWN alternation so `>` is never load-bearing for a non-redirect.
const HAZARDS: ReadonlyArray<readonly [string, RegExp]> = [
  ["redirect", new RegExp(String.raw`(?:>>?|&>|\d>)\s*"?` + TMP_PATH, "g")],
  ["flag", new RegExp(String.raw`(?:-o|--output)\s+"?` + TMP_PATH, "g")],
  [
    "verb",
    new RegExp(String.raw`\b(?:cp|mv|tee|install)\b[^\n]*?` + BOUNDARY + `"?` + TMP_PATH, "g"),
  ],
  ["unzip-d", new RegExp(String.raw`\bunzip\b[^\n]*?-d\s+"?` + TMP_PATH, "g")],
  // Read-side stdin redirect. A READ from a deterministic /tmp path is a hazard in its own
  // right (you may read a SIBLING's file), and it is also how a half-applied sweep leaves a
  // dangling reader: fix the writer to a unique path, miss the reader, and the reader now
  // consumes a file nothing writes. That regression was made and caught by hand while
  // sweeping this very PR — pinned here so the next sweep cannot repeat it.
  ["read-redirect", new RegExp(String.raw`<\s*"?` + TMP_PATH, "g")],
];

/**
 * Pure. Returns the exact offending substrings in `text`.
 *
 * Exported and unit-tested against committed fixtures because the whole guard hinges on this
 * function's breadth. After the sweep every surviving real site matches the NARROW class, so
 * without fixtures the `<>` class and the flag/verb alternations would be load-bearing for
 * ZERO committed assertions — someone narrows the regex, the suite stays GREEN, and the guard
 * is silently dead.
 */
export function findHazards(text: string): string[] {
  const out: string[] = [];
  for (const line of text.split("\n")) {
    // Variable-rooted scratch is already session-scoped. Skip before matching so a compliant
    // line cannot be dragged in by an unrelated verb earlier on the same line.
    if (/\$\{?[A-Za-z_][A-Za-z0-9_]*\}?\/tmp\//.test(line)) continue;
    for (const [, re] of HAZARDS) {
      re.lastIndex = 0;
      for (const m of line.matchAll(re)) out.push(m[0].trim());
    }
  }
  return out;
}

// Content-addressed waivers: keyed by (file, EXACT offending text) — never by line number.
// Phases 1-3 shift line numbers, and a position-keyed waiver would silently absolve whatever
// future offender happens to land on that line.
type Waiver = { file: string; text: string; reason: string };
const ALLOWLIST: readonly Waiver[] = [
  // NOTE: `text` must be the EXACT hazard substring findHazards() returns (the match ends at
  // the path — it does not carry trailing context like `2>&1`). A waiver written with extra
  // context never matches and the site reports as an offender.
  {
    file: "skills/work/SKILL.md",
    text: "> /tmp/log",
    reason:
      "Quotes the background-task exit trap it is warning about. The line's subject IS the broken shape; rewriting it would destroy the warning.",
  },
  {
    file: "skills/work/SKILL.md",
    text: "> /tmp/body.md",
    reason:
      "Quotes the heredoc-with-hook-denial trap it is warning about. Same reason as above: the broken shape is the subject.",
  },
  {
    file: "skills/preflight/SKILL.md",
    text: "> /tmp/A.txt",
    reason:
      "Written and consumed inside ONE && chain, so it does not outlive its command. A concurrent preflight could still clobber it: narrow, self-limiting, accepted — NOT 'not a defect'.",
  },
  {
    file: "skills/preflight/SKILL.md",
    text: "> /tmp/B.txt",
    reason: "Same && chain as /tmp/A.txt above; same accepted narrow race.",
  },
];

describe("scratch-path-collision (#6486)", () => {
  test("findHazards catches every write family — narrowing the class or dropping a verb goes RED", () => {
    // RED fixtures. Synthesized, never captured (cq-test-fixtures-synthesized-only).
    expect(findHazards("prefer `bash x > /tmp/<script>.log 2>&1`")).toHaveLength(1); // placeholder class
    expect(findHazards('bash x > /tmp/mutant.log 2>&1')).toHaveLength(1); // literal
    expect(findHazards("cp somefile /tmp/fixed.bak")).toHaveLength(1); // NO redirect at all
    expect(findHazards("curl -fsSL https://x -o /tmp/fixed.html")).toHaveLength(1); // flag
    expect(findHazards("unzip -q rclone.zip -d /tmp/unpacked")).toHaveLength(1); // unzip -d
    expect(findHazards('echo "$u" > "/tmp/issue-$name.url"')).toHaveLength(1); // var-bearing leaf
    expect(findHazards("done < /tmp/candidates.txt")).toHaveLength(1); // read-side / dangling reader
  });

  test("findHazards does NOT match compliant or non-prescriptive forms", () => {
    expect(findHazards('bash x > "$log" 2>&1')).toEqual([]); // mktemp-captured
    expect(findHazards('cat "$PREFLIGHT_TMP/x.txt"')).toEqual([]); // workspace-scoped var
    expect(findHazards("cp a ${GITHUB_WORKSPACE}/tmp/ux-audit/a.png")).toEqual([]); // var-rooted
    expect(findHazards("the runner writes its log under /tmp/foo.log")).toEqual([]); // bare prose
  });

  test("no skill prescribes a deterministic /tmp scratch path", () => {
    const skills = discoverSkills();
    // Non-vacuity: an empty glob would make every assertion below pass silently.
    expect(skills.length).toBeGreaterThan(0);

    const offenders: string[] = [];
    for (const rel of skills) {
      const text = readFileSync(resolve(PLUGIN_ROOT, rel), "utf-8");
      const lines = text.split("\n");
      for (const hazard of findHazards(text)) {
        if (ALLOWLIST.some((w) => w.file === rel && hazard.includes(w.text))) continue;
        const n = lines.findIndex((l) => l.includes(hazard)) + 1;
        offenders.push(`${rel}:${n}  ${hazard}`);
      }
    }

    if (offenders.length > 0) {
      throw new Error(
        `Deterministic /tmp scratch path(s) prescribed — concurrent sessions will clobber each other:\n` +
          offenders.map((o) => `  ${o}`).join("\n") +
          `\n\nFix: capture a unique path and echo it, e.g.\n` +
          `  log=$(mktemp -t <name>.XXXXXXXX.log); <cmd> > "$log" 2>&1; rc=$?; echo "EXIT=$rc LOG=$log"\n` +
          `Use a workspace/git-dir-scoped dir instead when a LATER, separate Bash call must find\n` +
          `the artifact by name. If the path genuinely cannot collide, add it to ALLOWLIST in\n` +
          `${import.meta.file} with a reason.`,
      );
    }
  });

  test("every waiver still resolves — a stale waiver cannot silently absolve a future offender", () => {
    for (const w of ALLOWLIST) {
      const text = readFileSync(resolve(PLUGIN_ROOT, w.file), "utf-8");
      expect(text.includes(w.text), `stale waiver: ${w.file} no longer contains ${w.text}`).toBe(
        true,
      );
      expect(w.reason.length, `waiver for ${w.file} needs a reason`).toBeGreaterThan(20);
    }
  });
});
