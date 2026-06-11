# Learning: terraform fmt alignment blinds token-anchored drift guards; file-scoped sweeps miss sibling-file blocks

## Problem

PR #5132 (#5101) swept `"set -e",` into all 11 un-gated `remote-exec` inline blocks in `apps/web-platform/infra/server.tf` and added a drift guard (`server-tf-set-e.test.sh`) asserting every block opens with `set -e`. Two gaps survived implementation and were caught only at multi-agent review:

1. **fmt-alignment blindness (P2).** The guard's awk matched `/inline = \[/` — exactly one space around `=`. `terraform fmt` aligns equals signs across attributes within a block, so a future provisioner carrying a second attribute (e.g. `on_failure = continue`) gets `inline     = [` and becomes invisible to the parser. The ≥13 block-count floor only catches whole-parser drift; with 13 existing blocks still matching, an invisible 14th un-gated block **passed silently** (mutation-demonstrated) — exactly the silent-green class the guard exists to prevent.
2. **File-scoped sweep gap (P3).** The plan correctly re-derived the issue's "7 provisioners" as 11 blocks by grepping — but scoped the grep to `server.tf` because the issue title named that file. A 14th `remote-exec` block with the same defect sat in the sibling `apps/web-platform/infra/ci-ssh-key.tf`, outside both the sweep and the guard.

## Solution

1. Widen the match to `inline[[:space:]]*=[[:space:]]*\[` and mutation-test by **appending a synthetic violating block** (fmt-aligned, un-gated) to a copy of the file — not just by removing a `set -e` from an existing well-formed block. Removal-mutations only exercise shapes the file already contains.
2. Skip comment lines globally (`/^[[:space:]]*#/ { next }` before the arming rules) so a future doc comment quoting `provisioner "remote-exec"` + `inline = [` cannot create a phantom block (extends the #4864 comment-prose class to awk arming tokens).
3. When a sweep's invariant is "every X in this Terraform root," enumerate with `grep -rn 'inline = \[' <dir>/*.tf` across the whole root, not just the file the issue names. The `ci-ssh-key.tf` block was gated inline at review (1 line; all intermediate commands hard requirements, final append already `||`-guarded).

## Key Insight

A token-anchored guard is only as strong as its weakest regex against the *formatter's* canonical output space, not the file's current shape. `terraform fmt` re-aligns `=` whenever an attribute set changes — so any single-space `attr = ` anchor over HCL is a latent false-pass. Mutation-test new guards with synthetic violations covering formatter-reachable shapes (alignment, comments, same-line lists), and scope invariant sweeps to the directory, not the named file: the issue's enumeration is a hypothesis at file granularity too.

## Session Errors

1. **IaC-routing hook false positive on plan Write** (plan subagent) — the hook flagged quoted `systemctl` strings that were quotes of existing `.tf`-managed inline content, not operator steps. Recovery: added the hook's documented `<!-- iac-routing-ack: ... -->` comment. **Prevention:** none needed — the ack mechanism is the designed escape hatch for quoted-infra-prose plans.
2. **Two self-introduced typos during plan editing** (plan subagent) — fixed immediately. **Prevention:** one-off; no action.
3. **No Task tool in pipeline planning subagent** — plan-review/deepen research agents could not spawn; passes ran inline and were documented as such. **Prevention:** known pipeline limitation, already documented in the plan skill's pipeline mode; verify inline passes execute the same gates.
4. **CWD drift broke repo-root-relative paths** — `cd apps/web-platform/infra && sed …` persisted the CWD; the next call's `apps/web-platform/...` paths ENOENT'd. Recovery: explicit `cd <worktree-root> && …`. **Prevention:** already covered by work SKILL.md ("chain `cd <worktree-abs-path> && <cmd>` in a single Bash call"); treat every repo-root-relative command as needing its own `cd` prefix after any call that changed directory.
5. **Host `grep` is ugrep; GNU-isms fail** — `grep -vE '^\+\+\+'` exited with `error at position 5` (ugrep rejects leading unescaped-looking `+` sequences GNU grep accepts) and `grep` warnings differ. Recovery: POSIX-safe bracket forms (`'^-[^-]'`, `'^+[^+]'`). **Prevention:** on this host prefer bracket-class patterns over escaped metacharacter runs in diff-filtering greps; or write `command grep` patterns POSIX-conservatively.

## Tags

category: test-failures
module: infra
