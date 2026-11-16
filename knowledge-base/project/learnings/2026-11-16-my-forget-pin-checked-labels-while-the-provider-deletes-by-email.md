---
title: My forget pin checked labels while the provider deletes by email
date: 2026-11-16
category: integration-issues
module: apps/web-platform/infra
tags: [terraform, removed-block, better-stack, guard-design, mutation-testing, closed-set]
issue: 12813
---

# Learning: a destroy guard must be keyed on what the provider deletes by, and read files the way Terraform does

## Problem

PR #12813 handed the Better Stack member for the operations mailbox (`ops@`) (now the org's sole Admin, set in the vendor UI) out of Terraform with `removed { from = betteruptime_team_member.ops  lifecycle { destroy = false } }`. The provider manages non-admin members only and its Delete is `DELETE /api/v2/team-members?email=…`, so any path that puts that email back in state and later removes it deletes the only Admin.

The first FIX B pin asserted (a) no member is labelled `ops` or contains that member's email literal, (b) a `removed` block with that `from` exists somewhere in the root, (c) the `-target` is in the saved plan. A self-run mutation battery was green. The review panel then found:

- **Two P1 survivors (test-design seat):** the `removed` block moved to `.ops-forget.tf` (Terraform ignores dotfiles; the test's `readdirSync` and the census's `os.listdir` both read it), and the block wrapped in a heredoc behind a quote-confusing string (`"${"\""}"`) that flips both strippers' string state so the heredoc body is read as code. Both keep the test AND census Guard G4a green while Terraform plans a DELETE. The two "independent" guards shared one file reader and one string model, so they shared every blind spot.
- **The property was never expressible by the pin (structural seat):** labels and literals cannot cover an `import` block, a `local.`/`var.` email, `OPS@`, unquoted HCL labels, a module, a `.tf.json`, or another root. The provider keys on email; the guard keyed on spelling.

## Solution

- **(a) closed set, repo-wide:** no tracked `.tf`/`.tf.json` anywhere (`git ls-files`) may contain the token `betteruptime_team_member` in comment-stripped code, except the forget's `from` line in `uptime-alerts.tf`. Every bypass above names the type, so one token check covers them all, including roots that run untargeted `terraform destroy`.
- **(b) pinned to the file Terraform loads:** exactly one live `removed` block in `uptime-alerts.tf`, outside every heredoc found by a RAW scan that ignores quotes, with `destroy = false` asserted in place; no dotfile `.tf` in the root.
- **(c)** the exact `-target` operand (a keyed `ops[0]` passed the base-address check).
- `listInfraTfFiles` and census `tf_files` skip dotfiles, as Terraform does.
- Stale `betteruptime_team_member` removed from `scripts/encryption-posture-ledger.json`, so a re-declared member also reds that lint.
- 13/13 reviewer mutations red afterwards (measured in-session, not committed as a harness), re-driven against the final tree in a throwaway `git worktree` (tracked-file scans need a real repo; a `git archive` sandbox makes `git ls-files` fail).

## Key Insight

State the property in the provider's terms first ("nothing may put this email in state"), then ask what INPUTS reach it. A guard over a subset of the spellings is a guard over a subset of the property, and a second guard that reads files with the same reader is not a second guard. When the property is "no resource of type T", the cheapest complete pin is a closed set over every file the tool would load, not a search for the bad instance.

## Session Errors

1. **Appended `PANEL_SHA=…` to the worktree's `.git` file** (`echo … >> <worktree>/.git`). In a worktree `.git` is a FILE (`gitdir: …`), so every review seat's `git -C` failed until it was rewritten. — Recovery: rewrote the single `gitdir:` line; scratch state went to the scratchpad. — Prevention: never redirect into `.git` in a worktree; put session markers in the scratchpad.
2. **Local affected gate contended** (SIBLING_RUN_DETECTED, 332/762 suites queued). — Recovery: stopped on the operator's call; CI's required `test` context is the gate; touched-file suites run directly. — Prevention: on a contended box, run the suites that reference the diff and record the deferral in session-state.
3. **Mutation H2 MISMATCH from the file-level #5566 untargeted-resource guard.** — Recovery: scope the run with `-t 'FIX B handed'`. — Prevention: grade a describe's mutations with `-t` on that describe; file-level guards answer a different question.
4. **Cost-model note cited the 2026-09-29 note instead of the 2026-09-28 review.** — Recovery: corrected. — Prevention: quote the cited note's own date line, not memory.
5. **Read `PUSH=1` as a failed push** when it was grep's exit code. — Recovery: `git ls-remote` showed the remote at HEAD. — Prevention: capture `RC=$?` immediately after the command whose status matters.
6. **AC13 note predicted "404 → no change"** from a probe that was not the provider's read; apply run 43870657893 showed the Read still succeeds for ops@ as Admin, so the merge plans a `["forget"]`. — Recovery: correction appended in session-state. — Prevention: predict a plan from a CI plan log of the same address, not from a hand probe of a guessed endpoint shape.
7. **FIX B pin narrower than the property** (labels and literals vs delete-by-email; dotfile and heredoc survivors). — Recovery: closed set + raw heredoc scan + dotfile skip, 13/13 mutations red. — Prevention: plan sharp edge routed to `plugins/soleur/skills/plan/references/plan-sharp-edges.md`.
8. **`gh issue create` refused three times by the filing gate** (no milestone/exit; a `$VAR` `--body-file`; `User-Impact:` with an unmeasured `Fix-Size:`). — Recovery: body written with the Write tool to a literal path, `--milestone "Post-MVP / Later"`, a whole-line `Mandated-By:`. — Prevention: write the body file first, literal absolute path, and pick the exit before the first call.
9. **Published a vendor invoice number in a public repo** (copied from the brief into ledger, cost model and plan). — Recovery: removed everywhere (a repo-wide `git grep` for the invoice number returns 0). — Prevention: invoice/account identifiers are support-desk ownership proofs; ledger amounts and dates, never invoice numbers.
10. **Cost-model note called itself a line-and-anchor update but left the line and subtotal stale.** — Recovery: row split 68.00 + 20.60, subtotal 359.47 → 380.07, downstream re-derivation deferred explicitly with user counts shown. — Prevention: follow the precedent the note cites literally (line AND subtotal move now).
11. **`c4-render-tenant-config.test.ts` 13 failures locally** — `likec4` not installed in this worktree; the file renders synthetic fixtures and never reads `model.c4`. — Recovery: recorded; CI is the gate. — Prevention: one-off environment.
12. **Semgrep count 41 → 42 on an untouched pre-existing line (5766).** — Recovery: line-mapped; zero findings in the PR's hunks. — Prevention: compare findings by line-in-hunk, never by total count.
13. **Bash cwd reset after `cd` into a scratch worktree outside the working directories.** — Recovery: absolute paths. — Prevention: use `git -C` / absolute paths for scratch trees.
14. **Forwarded from planning (session-state):** write-guard wording, issue-filing gate, infra-steps lint, ruling-gate format, markdownlint and a wait-loop syntax error, each hit and resolved during planning. — Prevention: covered by the respective gates' own messages.

## Tags

category: integration-issues
module: apps/web-platform/infra
