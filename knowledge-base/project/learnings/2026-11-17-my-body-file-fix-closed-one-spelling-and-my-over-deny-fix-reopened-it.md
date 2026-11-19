---
title: My body-file fix closed one spelling, and my over-deny fix reopened it
date: 2026-11-17
category: security-issues
module: apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs
tags: [cron-containment, argument-injection, gh-cli, flag-parsing, fix-rounds, review]
issues: [12824, 12847]
---

# Learning: a deny gate on a CLI flag must cover every spelling the CLI's parser accepts

## Problem

PR #12847 (#12824) confined cron agents' writes and moved their executed code to a read-only
mount. The first fix round found a P1: `gh issue create --body-file <path>` let a prompt-injected
cron post any file the Read gate refuses (ux-audit's live `storage-state.json`, a spawn HOME's
`.claude/` transcripts, `hosts.yml`, `/run/secrets`) to a public issue. gh reads that file itself,
so the Read gate never sees it.

The fix took four rounds, and two of them were caused by the fix itself:

1. **Round 1** added a secret-path check on the `--body-file` token. The hook already said, 360
   lines higher, "`-F` is --body-file for `gh issue create`". The short form, the attached form
   (`-F<path>`), the `=` form (`-F=<path>`) and the clustered form (`-wF <path>`) all still
   allowed the file. Two seats found it independently, one by calling the real `decide()`.
2. **Round 2** covered `-F` in all four spellings, plus `--input` and `--recover`. It still
   missed `--input=<path>` and `--recover=<path>`.
3. **Round 3** closed the `=` forms. It also "fixed" an over-deny, where a title or body starting
   with `-F` was refused: the `-F` gates were skipped when the previous token was a gh value
   flag. **That skip reopened the P1.** In `--title --label -F<path>`, pflag takes `--label` as
   the title and then parses `-F<path>` as the body-file flag. The round-4 seat measured gh
   2.104.0 offline and saw it try to open the file.
4. **Round 4** removed the skip and accepted the fail-safe over-deny.

## Solution

`argumentInjectionReason` now refuses a Read-gate secret path for `--body-file`, `--input`,
`--recover`, and `-F` on every gh subcommand except `gh api`, where `-F` is a field flag. It also
refuses the `=` spellings of `--input` and `--recover`, and refuses an attached or clustered `-F`
on every token, whatever the path. Each deny row asserts its reason. The `--input` rows use an
allowlisted endpoint with an allowed control, so a row cannot pass because an earlier rule
denied it. The refusal is counted off-host as `body-file-secret-path`.

## Key Insight

- **Enumerate the parser's spellings, not the flag's name.** For a pflag/getopt CLI, one flag
  has at least five spellings: `--long v`, `--long=v`, `-s v`, `-sv`, and `-xs v` (clustered).
  The `=` form of an attached short flag (`-s=v`) is a sixth. Write the gate as a table over
  those spellings, one test row each, before the first fix commit, not one per review round.
- **A skip keyed on token position over a flag parser is unsound.** "The previous token is a
  value flag, so this token is a value" fails when the previous token is itself a value. Any
  token can be consumed as the value of the one before it, so position cannot be decided
  without running the parser. Prefer the fail-safe over-deny, and say in the deny reason what to
  do instead (use a body file).
- **The over-deny fix is part of the security surface.** A change that relaxes a deny is the
  change that reopens it, so it gets the same adversarial review as the gate. This is the
  "fix commit is the least-audited surface" rule applied to a relaxation.

This is the same class as `2026-11-16-seven-fix-rounds-each-found-the-next-bash-expansion-the-hook-read-differently.md`:
a hook that reads a command differently from the program that runs it. There, the program was
bash; here, it was gh's flag parser.

## Session Errors

1. **Ran review-scan-gate from the main checkout path instead of the worktree.** Recovery: re-ran
   from the worktree root. **Prevention:** run every review script from
   `git rev-parse --show-toplevel` of the worktree, and read the `files=` count against the
   range's own source count before trusting the receipt.
2. **A plugin-loader check change broke existing fixtures.** Recovery: updated the fixtures to
   the new contract. **Prevention:** grep every test that builds the changed object before
   tightening a runtime check, and run them in the same edit.
3. **Spawn-time plugin-root resolve hit the 30 s sentinel wait and timed out tests.** Recovery:
   community-monitor got a no-wait snapshot (`pluginSeedSnapshot`). **Prevention:** a helper
   that sleeps is not safe to reuse on a hot path. Split the read from the wait.
4. **A top-level `readFileSync` import broke a test file that mocks `node:fs`.** Recovery:
   `await vi.importActual("node:fs")` inside the test. **Prevention:** grep the test file for
   `vi.mock("node:fs"` before adding an fs import to it.
5. **The filing hook needs the `--body-file` to exist at a literal absolute path first.**
   Recovery: wrote the body with the Write tool, then ran `gh issue create` as a separate call.
   **Prevention:** write the body file in its own tool call, never in the same shell line as the
   filing.
6. **Heartbeat slug miscount (12, then 13; measured 15).** Recovery: re-measured and posted a
   correction on #12859. **Prevention:** the existing measure-once rule. Count with a command at
   the scope you will claim, before the first write.
7. **The full `SECRET_PATH_PATTERNS` over-blocked ux-audit's own bodies under `tmp/ux-audit/`.**
   Recovery: `BODY_FILE_SECRET_PATTERNS` leaves that one entry out, and says what that gives
   up. **Prevention:** before reusing a deny list for a new purpose, list the legitimate writers
   of each entry's paths.
8. **The P1 fix covered `--body-file` but not `-F`, which the same file documents as identical.**
   Recovery: rounds 2 and 3. **Prevention:** the Key Insight table. Grep the file for every alias
   of the flag before writing the first fix.
9. **The round-3 over-deny fix reintroduced the P1 (chainable value-flag skip).** Recovery: round
   4 removed it. **Prevention:** never skip a deny by token position over a flag parser. A
   relaxation goes through the same security seat as the gate.
10. **A null-equals-reseed rule leaked onto the resolver baseline and onto a loader cron spawned
    with `loadPlugin: false`.** Recovery: `seedPending` marks only the no-wait snapshot, and the
    snapshot runs only for non-loader plugin-root crons. **Prevention:** when one function reads
    two kinds of baseline, give each kind a field, not a shared sentinel value.
11. **An `--input` test row was vacuous: the allowlist denied it first.** Recovery: rows assert
    their deny reason and carry an allowed control. **Prevention:** every deny row asserts the
    reason, never only the verdict.
12. **A comment and AC21 claimed "the only setter under server/"; the pin test scoped to
    `server/inngest`, and `server/agent-env.ts` sets its own.** Recovery: corrected in QA.
    **Prevention:** a scope claim in prose names the same scope as the test that pins it.
13. **Ran fix rounds 3 and 4 as targeted rounds; the review reference caps targeted rounds at two
    and escalates a third to the full class panel over the cumulative fix diff.** Recovery: ran
    the full-panel escalation over `PANEL_SHA..HEAD` before ship. **Prevention:** run
    `pipeline-tally.sh show` before each fix round and read `fix_rounds`; at 2, the next round is
    the full class panel, not a targeted one.

## Tags

category: security-issues
module: cron-bash-allowlist-hook
