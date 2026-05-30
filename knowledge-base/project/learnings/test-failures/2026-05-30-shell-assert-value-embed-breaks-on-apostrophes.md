---
title: "Shell .test.sh assert helpers must reference block vars BY NAME, not embed their value"
date: 2026-05-30
category: test-failures
module: apps/web-platform/infra
tags: [shell, bash, eval, test-helpers, inngest, quoting]
issue: 4652
---

# Learning: shell `assert` value-embedding breaks on apostrophes in the asserted block

## Problem

The repo's `.test.sh` `assert(description, condition)` helpers run the condition via
`eval "$condition"`. A common pattern builds the condition by **embedding a captured
multi-line block's VALUE** inside single quotes:

```bash
BLOCK=$(awk '/start/,/end/' "$FILE")
assert "block non-empty" "[[ -n '$BLOCK' ]] && printf '%s\n' \"\$BLOCK\" | grep -q X"
#                                  ^^^^^^^ value-embedded inside single quotes
```

When `$BLOCK` contains an apostrophe (`inngest-server.service's`, `#4204's`) or a
single quote (a systemd `ExecStart=... bash -c '...'` line), the embedded value
closes the single-quote context early and `eval` dies with
`syntax error in conditional expression: unexpected token`. The assert reports
FAIL even though the underlying property holds.

Hit twice this session: the **pre-existing** `inngest.test.sh` heartbeat assert
(apostrophes in unit-block comments) AND the **new** server-unit assert I added
(single quotes in the `inngest start` ExecStart). The same class also breaks
`cloud-init-inngest-bootstrap.test.sh` AC5 (filed #4665).

## Solution

Reference the variable **by name** (double-quoted) so it is expanded at `eval`
time as a single argv token, never re-parsed as quoted source:

```bash
assert "block non-empty" "[[ -n \"\$BLOCK\" ]] && printf '%s\n' \"\$BLOCK\" | grep -q X"
#                                ^^^^^^^^ by-name reference — survives any content
```

The sibling asserts in the same file that already used `printf '%s\n' \"\$BLOCK\"`
(by-name) never broke — only the `[[ -n '$BLOCK' ]]` value-embed form did.

## Key Insight

In a `.test.sh` `assert` whose condition is `eval`'d, **never interpolate a
captured block's VALUE into the condition string**. Pass it by NAME (`\"\$VAR\"`)
so the content is opaque to the shell parser. Value-embedding is a latent landmine
that detonates the first time the asserted artifact gains an apostrophe or a quote —
and shell heredoc bodies (systemd units, sudoers, JSON) routinely contain both.

Corollary (same session): a precise assert must NOT carry a broad `|| grep <word>`
fallback — it makes the check vacuously pass on any comment line mentioning the word.

## Session Errors

1. **Planning subagent: general-purpose Task type unavailable** — Recovery: research done directly (Read/Bash/Context7). Prevention: planning subagents should not assume nested Task availability; inline the research.
2. **`hr-all-infrastructure-provisioning-servers` gate blocked planning prose** containing `systemctl` — Recovery: added `<!-- iac-routing-ack: ... -->` + rephrase. Prevention: IaC-routed plans should carry the ack marker up front (already a documented gate).
3. **`inngest.test.sh` value-embed eval broke on apostrophes/quotes** — Recovery: switched to by-name `[[ -n "$BLOCK" ]]`; fixed the pre-existing heartbeat assert too. Prevention: this learning; never value-embed blocks in `eval`'d assert conditions.
4. **`$INSTALL_PATH` unbound in an assert description under `set -u`** — Recovery: removed the bootstrap-var reference from the test description. Prevention: test files must not reference variables defined only in the SUT script.
5. **cloud-init-inngest-bootstrap.test.sh 2 pre-existing AC5 failures** (broken awk over-read + same fragile eval) — Recovery: confirmed pre-existing (reproduced on `origin/main`), not CI-gated; filed #4665 rather than fixing an unrelated subsystem inline. Prevention: triage at value-shape before assuming real drift.
6. **`gh issue create` blocked for missing `--milestone`** — Recovery: re-ran with `--milestone "Post-MVP / Later"`. Prevention: operational issues always pass `--milestone`.
7. **`git stash list` blocked** by `hr-never-git-stash-in-worktrees` — Recovery: used `git show <ref>:<path>`. Prevention: inspect old code with `git show`, never `git stash`.
8. **Stale `origin/main` ref** made `git diff --stat origin/main` list unrelated deletions — Recovery: re-diffed vs `HEAD`/base SHA to confirm the true change set before committing. Prevention: trust `git status` + `git diff HEAD` for the working-tree change set; treat `--stat origin/main` as advisory when the local ref may lag.
9. **Vacuous `|| grep resume` fallback** introduced in an assert — Recovery: test-design review agent caught it; removed the fallback. Prevention: assert the precise command, no catch-all `|| grep <word>` fallback.
