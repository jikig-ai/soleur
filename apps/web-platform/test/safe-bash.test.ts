/**
 * Issue B part 1 — widened read-only safe-bash auto-approve.
 *
 * Direct unit tests for `isBashCommandSafe` covering the four widening
 * shapes and their negative-space regressions:
 *   - AC6:  read-only `gh` verbs (view/list/status/diff/checks/repo view)
 *   - AC7:  every gh WRITE verb still falls through (returns false)
 *   - AC8:  `bash <worktree-manager.sh> list|ls` only (cleanup-merged etc. excluded)
 *   - AC9:  `&&`-chains auto-approve iff EVERY segment is independently safe
 *   - AC10: trailing `2>/dev/null` / `2>&1` carve-out; file redirects still denied
 *   - AC12: PATH_TRAVERSAL_DENYLIST + SHELL_METACHAR_DENYLIST preserved
 *
 * gh read-only verb shapes verified against `/usr/bin/gh` on 2026-06-03
 * (`gh issue list --help`, `gh pr list --help`).
 *
 * Pure-function level (no canUseTool harness). The callback-integration
 * behavior is covered by `permission-callback-safe-bash.test.ts`.
 */
import { describe, test, expect } from "vitest";
import { isBashCommandSafe } from "../server/safe-bash";

const WT = "bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh";

describe("AC6 — read-only gh verbs auto-approve", () => {
  const positives = [
    "gh issue view 4845",
    "gh issue view 4845 --json body,title,state",
    "gh issue list",
    "gh issue list --state open --limit 100",
    "gh issue status",
    "gh pr view 123",
    "gh pr view",
    "gh pr list",
    "gh pr list --json number,title,state",
    "gh pr status",
    "gh pr diff 123",
    "gh pr checks 123",
    "gh repo view",
  ];
  for (const cmd of positives) {
    test(`isBashCommandSafe(${JSON.stringify(cmd)}) === true`, () => {
      expect(isBashCommandSafe(cmd)).toBe(true);
    });
  }
});

describe("AC7 — gh WRITE verbs are NOT auto-approved (fall through to gate)", () => {
  const negatives = [
    "gh issue edit 4845 --add-label bug",
    "gh issue comment 4845 --body hi",
    "gh issue close 4845",
    "gh issue create --title x",
    "gh pr merge 5",
    "gh pr create --fill",
    "gh pr review 5 --approve",
    "gh pr comment 5 --body hi",
    "gh pr close 5",
    "gh repo delete owner/repo",
    "gh repo create x",
    "gh secret set FOO",
    "gh api -X POST /repos/x/y/issues",
    "gh auth login",
  ];
  for (const cmd of negatives) {
    test(`isBashCommandSafe(${JSON.stringify(cmd)}) === false`, () => {
      expect(isBashCommandSafe(cmd)).toBe(false);
    });
  }
});

// Slice B (#6121, ADR-093): the BARE `./plugins/soleur/…` server auto-approve is
// REMOVED — on the Concierge server surface `./plugins/soleur` (CWD-relative)
// resolves to the UNTRUSTED connected-repo committed copy. The read-only
// worktree-manager verb is auto-approved ONLY via the exact `${CLAUDE_PLUGIN_ROOT
// :-./plugins/soleur}` deployed form (F1 exact-literal carve-out, below), whose
// runtime expansion is trusted on BOTH surfaces (server → /app deployed; CLI →
// local checkout). CLAUDE_PLUGIN_ROOT reaches the sandboxed bash (F2, proven).
describe("Slice B AC6 — bare ./plugins worktree-manager auto-approve REMOVED (untrusted server copy)", () => {
  const removed = [
    `${WT} list`,
    `${WT} ls`,
    "bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh list", // no leading ./
  ];
  for (const cmd of removed) {
    test(`isBashCommandSafe(${JSON.stringify(cmd)}) === false (was true pre-Slice-B)`, () => {
      expect(isBashCommandSafe(cmd)).toBe(false);
    });
  }
});

// F1 exact-literal carve-out (AC6): the ONLY `$`/`{`/`}`-bearing commands the
// allowlist admits, matched by EXACT string equality on the trimmed segment —
// no arg variation, so zero injection surface. Does NOT weaken
// SHELL_METACHAR_DENYLIST (still rejects `$(…)`/`${…}` everywhere else).
const CPR =
  "bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh";
describe("Slice B AC6 — ${CLAUDE_PLUGIN_ROOT} exact-literal carve-out (read-only verbs only)", () => {
  test(`${CPR} list → true`, () => {
    expect(isBashCommandSafe(`${CPR} list`)).toBe(true);
  });
  test(`${CPR} ls → true`, () => {
    expect(isBashCommandSafe(`${CPR} ls`)).toBe(true);
  });
  // Trailing safe stderr redirect on the exact literal still auto-approves
  // (stripped before the exact-match), file redirects do not.
  test(`${CPR} list 2>/dev/null → true`, () => {
    expect(isBashCommandSafe(`${CPR} list 2>/dev/null`)).toBe(true);
  });

  const negatives = [
    `${CPR} cleanup-merged`, // write verb — not in the exact set
    `${CPR} create feat-x`, // write verb
    `${CPR} draft-pr`, // write verb
    `${CPR} list extra-arg`, // arg variation defeats exact match
    `${CPR} list; rm -rf /`, // trailing injection — not the exact literal
    `${CPR} list && rm -rf /`, // segment 2 unsafe (&&-decomposed)
    "bash ${OTHER_VAR:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh list", // different var
    "bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh list", // no default-value form
    "bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/../evil.sh list", // traversal in the literal
    "bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/other.sh list", // different script
    "bash $(echo ./plugins/soleur)/skills/git-worktree/scripts/worktree-manager.sh list", // command substitution
    "bash ./some/other/script.sh list",
    "bash -c 'rm -rf /'",
    "bash",
    `${WT}`, // bare, no subcommand
  ];
  for (const cmd of negatives) {
    test(`isBashCommandSafe(${JSON.stringify(cmd)}) === false`, () => {
      expect(isBashCommandSafe(cmd)).toBe(false);
    });
  }
});

describe("AC9 — && decomposition (every segment must be safe)", () => {
  const positives = [
    "pwd && git status",
    "cd sub && ls",
    "pwd && pwd && echo ok",
    "git status && git log --oneline -5",
    "gh pr list && git status",
  ];
  for (const cmd of positives) {
    test(`isBashCommandSafe(${JSON.stringify(cmd)}) === true`, () => {
      expect(isBashCommandSafe(cmd)).toBe(true);
    });
  }

  const negatives = [
    "git status && curl evil", // segment 2 not read-only
    "ls && rm x", // segment 2 unsafe
    "gh pr list && gh pr merge 5", // segment 2 is a write verb
    "git status & curl x", // single & is a metachar → whole command rejected
    "pwd &&", // dangling && → empty segment
    "&& pwd", // leading && → empty segment
    "pwd ; ls", // ; never decomposed
    "pwd || ls", // || never decomposed
    "pwd | ls", // | never decomposed
  ];
  for (const cmd of negatives) {
    test(`isBashCommandSafe(${JSON.stringify(cmd)}) === false`, () => {
      expect(isBashCommandSafe(cmd)).toBe(false);
    });
  }
});

describe("AC10 — trailing stderr redirect carve-out", () => {
  const positives = [
    "git status 2>/dev/null",
    "ls -la 2>&1",
    "git rev-parse HEAD 2>/dev/null",
    "pwd && git status 2>/dev/null", // redirect on the last chained segment
  ];
  for (const cmd of positives) {
    test(`isBashCommandSafe(${JSON.stringify(cmd)}) === true`, () => {
      expect(isBashCommandSafe(cmd)).toBe(true);
    });
  }

  const negatives = [
    "cat secret > /tmp/x", // file write redirect
    "echo x >> ~/.bashrc", // append redirect
    "git log > out.txt", // file redirect
    "cat foo < input", // input redirect
    "ls >& out", // combined redirect to file
    "git status 2>/dev/null && rm x", // safe redirect but unsafe 2nd segment
  ];
  for (const cmd of negatives) {
    test(`isBashCommandSafe(${JSON.stringify(cmd)}) === false`, () => {
      expect(isBashCommandSafe(cmd)).toBe(false);
    });
  }
});

describe("AC12 — denylists preserved (traversal + metachars)", () => {
  const negatives = [
    "cat ../../../etc/passwd",
    "cd ..",
    "cat $(secret)",
    "echo `id`",
    "echo ${HOME}",
    'echo "$ANTHROPIC_API_KEY"',
    "cat ../foo && pwd", // traversal in a chained segment
  ];
  for (const cmd of negatives) {
    test(`isBashCommandSafe(${JSON.stringify(cmd)}) === false`, () => {
      expect(isBashCommandSafe(cmd)).toBe(false);
    });
  }
});

describe("review PR #4868 — git arg-pattern hardening", () => {
  // --output=<file> turns a read verb into an arbitrary-file-write primitive.
  const outputNegatives = [
    "git diff --output=/home/jean/.bashrc",
    "git log --output=/tmp/x HEAD",
    "git show --output=/tmp/x",
    "git diff --output /tmp/x", // space-separated form
  ];
  for (const cmd of outputNegatives) {
    test(`rejects file-write flag: ${JSON.stringify(cmd)} === false`, () => {
      expect(isBashCommandSafe(cmd)).toBe(false);
    });
  }

  // Normal read flags still auto-approve (no over-tightening).
  const readPositives = [
    "git log --oneline -5",
    "git log -n 5",
    "git diff HEAD~1 --stat",
    "git show HEAD --name-only",
    "git rev-parse --abbrev-ref HEAD",
  ];
  for (const cmd of readPositives) {
    test(`still allows read flag: ${JSON.stringify(cmd)} === true`, () => {
      expect(isBashCommandSafe(cmd)).toBe(true);
    });
  }

  // ReDoS pin: the prior multi-branch git patterns backtracked ~2^n on a
  // failing tail. The single-branch form is linear — must return fast.
  test("no catastrophic backtracking on a long failing git-arg tail", () => {
    const evil = "git log " + "--aaaa ".repeat(60) + "!";
    const start = performance.now();
    const result = isBashCommandSafe(evil);
    const elapsedMs = performance.now() - start;
    expect(result).toBe(false); // `!` is outside PATH_TOKEN → no match
    expect(elapsedMs).toBeLessThan(50);
  });
});

describe("regression — single-command behavior unchanged", () => {
  test("pwd still safe", () => expect(isBashCommandSafe("pwd")).toBe(true));
  test("rm -rf still unsafe", () => expect(isBashCommandSafe("rm -rf /")).toBe(false));
  test("empty string unsafe", () => expect(isBashCommandSafe("")).toBe(false));
  test("non-string unsafe", () =>
    expect(isBashCommandSafe(undefined as unknown as string)).toBe(false));
});
