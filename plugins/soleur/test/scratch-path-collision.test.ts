// Guards agent-facing guidance against prescribing a literal, deterministic `/tmp` path.
//
// Why: ADR-009 amendment — a worktree isolates the working tree, NOT process-level scratch.
// `/tmp` is one namespace shared by every worktree, so a path built from a stable input (a
// script name, an issue name) collides by construction across concurrent sessions.
//
// The anchor is the PATH, not the write verb. An earlier revision of this guard enumerated
// write families (`>`, `-o`, `cp|tee`, `unzip -d`) and was consequently blind to every READ —
// `cat`, `rm`, `--body-file`, an awk positional, and bare prose. It certified its own diff
// green while that diff left five readers pointing at paths nothing wrote. Breadth of write
// syntax was never the property worth pinning: a literal `/tmp/<name>` in prescriptive
// guidance is the hazard, whichever direction the data flows.
//
// Waivers are content-addressed and exact-matched, each with a reason. A `/tmp` string that
// no concurrent session can collide on (a schema example, the harness's own fixed dir) is
// waived explicitly rather than carved out by a narrower regex — a silent exemption is how
// the previous revision hid its misses.
import { Glob } from "bun";
import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { discoverSkills } from "./helpers";

// discoverSkills() returns paths relative to plugins/soleur — rooting at the repo root ENOENTs.
const PLUGIN_ROOT = resolve(import.meta.dir, "..");

// A literal /tmp/ path. The leading `(?<![\w}])` boundary is what makes a variable-rooted
// path (`${GITHUB_WORKSPACE}/tmp/x`) COMPLIANT rather than an offender — the char before
// `/tmp/` there is always `}`, and such a path is already session-scoped. The lookbehind
// excludes ONLY `\w` and `}`: excluding `{` too (an earlier revision did) hid a real
// hazard — brace-expansion `{/tmp/a,/tmp/b}` writes to a literal `/tmp/a`, so its first
// element must stay visible. `<` `>` `$` `{` `}` `*` `_` are in the class so placeholder and
// variable-bearing leaves (`/tmp/<script>.log`, `/tmp/issue-$name.url`, `/tmp/_lock`) match.
const TMP_PATH = /(?<![\w}])\/tmp\/[A-Za-z0-9_.<>${}*/-]+/g;

/** Pure. Returns every literal /tmp path in `text`. Exported for unit test. */
export function findHazards(text: string): string[] {
  return (text.match(TMP_PATH) ?? []).map((m) => m.trim());
}

// Exact-matched (never substring): a `includes`-based waiver for `/tmp/log` would also absolve
// a future `/tmp/log-something-else`, which is not content-addressing.
type Waiver = { file: string; text: string; reason: string };
const ALLOWLIST: readonly Waiver[] = [
  {
    file: "skills/work/SKILL.md",
    text: "/tmp/log",
    reason:
      "Quotes the background-task exit trap it warns about. The broken shape IS the subject; rewriting it destroys the warning. Nothing executes it.",
  },
  {
    file: "skills/work/SKILL.md",
    text: "/tmp/body.md",
    reason:
      "Quotes the heredoc-with-hook-denial trap it warns about. Same reason: the broken shape is the subject, and nothing executes it.",
  },
  {
    file: "skills/frontend-anti-slop/SKILL.md",
    text: "/tmp/anti-slop/no-screenshot.png",
    reason:
      "A JSON schema example documenting a sentinel value meaning 'no screenshot'. It is data in a documented shape, never a path anything writes or reads.",
  },
  // worktree-manager.sh's cleanup_claude_tmp() reaps the Claude Code harness's OWN
  // task-output dir. The code form is load-bearing (it MUST name the real path to reap it);
  // the three comment forms document that same real path for a human reader. This is not a
  // scratch path the script prescribes creating — it is the harness's fixed, session-scoped
  // (`<session>`) tmpfs dir, which cannot collide across worktrees.
  {
    file: "skills/git-worktree/scripts/worktree-manager.sh",
    text: "/tmp/claude-$uid",
    reason:
      "Load-bearing: cleanup_claude_tmp() reaps the Claude Code harness's real task-output dir at this exact path. Not a scratch path this script creates.",
  },
  {
    file: "skills/git-worktree/scripts/worktree-manager.sh",
    text: "/tmp/claude-<uid>/<project>/<session>/tasks/.",
    reason:
      "Comment documenting the harness's real task-output dir. Session-scoped (`<session>`), so it cannot collide; not a prescribed scratch path.",
  },
  {
    file: "skills/git-worktree/scripts/worktree-manager.sh",
    text: "/tmp/claude-<uid>",
    reason: "Comment referencing the same harness dir cleanup_claude_tmp() reaps. Documentation, not a prescribed scratch path.",
  },
  {
    file: "skills/git-worktree/scripts/worktree-manager.sh",
    text: "/tmp/claude-<uid>/",
    reason: "Comment referencing the same harness dir (menu help text). Documentation, not a prescribed scratch path.",
  },
  {
    file: "skills/linear-fetch/scripts/persist-safe-integration.test.sh",
    text: "/tmp/wt",
    reason:
      "Test-fixture template: an illustrative WORKING DIRECTORY inside a synthesized prompt that mirrors the one-shot subagent shape. Input data under test, not a prescribed scratch path.",
  },
  {
    file: "skills/plan/SKILL.md",
    text: "/tmp/.doppler",
    reason:
      "Incident prose (#6536): names doppler's own real cache dir as the diagnosed root cause (the heartbeat unit lacked PrivateTmp=true). Documents a system path, does not prescribe writing scratch there.",
  },
  // The agent-browser CLI uses a fixed /tmp/agent-browser/ cache dir of its own; these two
  // sites are the documented command to CLEAR that stale cache, not a scratch path this
  // guidance invents. The path is the tool's, unfixable from a SKILL.md.
  {
    file: "skills/agent-browser/SKILL.md",
    text: "/tmp/agent-browser/*",
    reason:
      "The `rm -rf` clears the agent-browser CLI's own hardcoded cache dir. Tool-defined path, not a scratch path this guidance prescribes.",
  },
  {
    file: "skills/feature-video/scripts/check_deps.sh",
    text: "/tmp/agent-browser/*",
    reason:
      "Echoes the same agent-browser cache-clear hint as agent-browser/SKILL.md. Tool-defined path, printed as a remediation tip.",
  },
];

describe("scratch-path-collision (#6486)", () => {
  test("findHazards catches reads and writes alike, and exempts variable-rooted paths", () => {
    // Synthesized (cq-test-fixtures-synthesized-only). The READ fixtures are the ones that
    // matter: the previous write-anchored revision returned [] for every one of them while
    // they were live in this PR's own diff.
    // toEqual, never toHaveLength: a length check is content-blind, so dropping `$`/`{`/`}`
    // from the class would truncate a match to `/tmp/issue-` and still "pass" at length 1.
    expect(findHazards("bash x > /tmp/<script>.log 2>&1")).toEqual(["/tmp/<script>.log"]);
    expect(findHazards("curl -o /tmp/fixed.html https://x")).toEqual(["/tmp/fixed.html"]);
    expect(findHazards("cat /tmp/resp.$$ 2>/dev/null && echo")).toEqual(["/tmp/resp.$$"]); // READ
    expect(findHazards("rm -f /tmp/resp.$$")).toEqual(["/tmp/resp.$$"]); // READ/destroy
    expect(findHazards("gh issue create --body-file /tmp/body.md")).toEqual(["/tmp/body.md"]);
    expect(findHazards("write the hits to `/tmp/sweep-targets.txt`")).toEqual([
      "/tmp/sweep-targets.txt",
    ]); // bare prose — no write verb anywhere
    expect(findHazards('echo "$u" > "/tmp/issue-$name.url"')).toEqual(["/tmp/issue-$name.url"]);
    // Pin `_` in the class: it is a first-class filename char, so dropping it must go RED
    // (a leaf STARTING with `_` is missed entirely otherwise — `[class]+` fails at position 0).
    expect(findHazards("cat /tmp/my_output.log")).toEqual(["/tmp/my_output.log"]); // `_` mid-leaf
    expect(findHazards("rm -f /tmp/_lock")).toEqual(["/tmp/_lock"]); // `_` at leaf start
    // Brace expansion writes to a literal `/tmp/a`; the `{` before it must NOT exempt it.
    expect(findHazards("cp {/tmp/a,/tmp/b} d")).toEqual(["/tmp/a", "/tmp/b}"]);
    expect(findHazards("cp a /var/tmp/b")).toEqual([]); // boundary: /var/tmp is not /tmp
    // A waiver is exact-matched, so a high-collision prefix cannot absolve its neighbours.
    expect(findHazards("bash a > /tmp/logfile-new.txt")).toEqual(["/tmp/logfile-new.txt"]);

    expect(findHazards('bash x > "$log" 2>&1')).toEqual([]); // mktemp-captured
    expect(findHazards('cat "$PREFLIGHT_TMP/x.txt"')).toEqual([]); // git-dir-scoped
    expect(findHazards("cp a ${GITHUB_WORKSPACE}/tmp/ux-audit/a.png")).toEqual([]); // var-rooted
  });

  test("no skill prescribes a literal /tmp scratch path", () => {
    const scripts = Array.from(new Glob("skills/*/scripts/*.sh").scanSync(PLUGIN_ROOT));
    const skills = discoverSkills();
    // Assert both populations independently: one combined length check would stay green if
    // the scripts glob silently resolved to nothing.
    expect(skills.length).toBeGreaterThan(0);
    expect(scripts.length).toBeGreaterThan(0);

    const offenders: string[] = [];
    for (const rel of [...skills, ...scripts]) {
      const text = readFileSync(resolve(PLUGIN_ROOT, rel), "utf-8");
      const lines = text.split("\n");
      for (const hazard of findHazards(text)) {
        if (ALLOWLIST.some((w) => w.file === rel && w.text === hazard)) continue;
        offenders.push(`${rel}:${lines.findIndex((l) => l.includes(hazard)) + 1}  ${hazard}`);
      }
    }

    if (offenders.length > 0) {
      throw new Error(
        `Literal /tmp scratch path(s) prescribed — concurrent sessions share /tmp and will ` +
          `read or clobber each other's artifacts:\n` +
          offenders.map((o) => `  ${o}`).join("\n") +
          `\n\nCapture a unique path and echo it so it stays findable:\n` +
          `  log=$(mktemp -t <name>.XXXXXXXX.log); <cmd> > "$log" 2>&1; rc=$?; echo "EXIT=$rc LOG=$log"\n` +
          `Use "$(git rev-parse --absolute-git-dir)" instead when a LATER, separate Bash call\n` +
          `must find the artifact by name AND no concurrent agent shares this worktree.\n` +
          `Fix READS too — a reader left on the old path consumes a sibling's file.\n` +
          `If the path genuinely cannot collide, add it to ALLOWLIST with a reason.`,
      );
    }
  });

  test("every waiver still resolves — a stale waiver cannot absolve a future offender", () => {
    for (const w of ALLOWLIST) {
      const text = readFileSync(resolve(PLUGIN_ROOT, w.file), "utf-8");
      expect(findHazards(text), `stale waiver: ${w.file} no longer contains ${w.text}`).toContain(
        w.text,
      );
    }
  });
});
