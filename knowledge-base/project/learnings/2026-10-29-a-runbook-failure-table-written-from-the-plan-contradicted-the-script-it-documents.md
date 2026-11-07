# Learning: a runbook failure table written from the plan contradicted the script it documents

## Problem

The #10540 key-rotation route shipped with docs (runbook, ADR-307, plan) written from the plan's prose. When the docs pass finally read `scripts/inngest-key-rotate.sh` and `--print-contract`, five claims were false for the code on the branch:

1. "Every failure after a write is recovered with `converge`." A failed or unverifiable phase 1 (`apply_failed`, `copy_unreadable`, `value_unchanged` from `apply1`) has no `converge` source (`converge_source_missing`); the script's own stop sentence says to re-dispatch `rotate`.
2. "`converge` has no age limit." The script bounds the source at 24 hours (`KR_CONVERGE_MAX_AGE_S=86400`, `converge_stale`) and reads only the newest earlier `rotate` run.
3. "The link flag is read through `doppler run --preserve-env ... --name-transformer tf-var`." It is read with `doppler secrets get INNGEST_LINK_TLS --plain`.
4. "Better Stack rows are pinned to `host=soleur-inngest` and `host_role=dedicated`." The `tls-health` reader pins only the `host` field, on `cloud-init-phone-home` rows. Those rows reach Better Stack by direct phone-home, not through the Vector journald shipper the plan's Observability block cited.
5. "Any session may dispatch `mode=plan`." Its `apply1` job runs under the `infra-privileged` environment, so it needs a reviewer approval and loads Tier-B credentials.

## Solution

Re-derive every row of a failure or verdict table from the code that emits it: `--print-contract` for the token list, then `grep` each token to its emitting job and read the surrounding stop sentence. The runbook table now has a Where column (job) and splits the recovery by phase. ADR-307 gained an Amendments section; the plan's Observability block gained the phase-1-failure and reboot-POST/action-failure modes.

## Key Insight

A verdict table is a claim about code. Reading the plan, the ADR and the workflow header only agrees with other prose. The token list printed by the script is the authority for what exists, and the emitting call site is the authority for what each one means and what recovery follows. When two documents disagree, the code decides, and every document that restated the claim is a twin to sweep by SUBJECT (the converge bound, the flag read, the host pin), not by phrasing.

## Session Errors

- **Docs carried five claims the script contradicts (above)** — Recovery: re-derived from `scripts/inngest-key-rotate.sh`, corrected runbook, ADR-307, decision-challenges R4, plan. Prevention: when a plan or ADR enumerates verdicts or recovery, add a pre-commit step of `--print-contract` diff against the table's token column.
- **A backgrounded multi-suite subshell piped to `tail` lost its output** (the harness reported only the first echo; the run was gone). Recovery: re-ran the suites from a script that appends `name rc=N` lines to an rc file. Prevention: for any run longer than the tool timeout, write per-suite rc files, never pipe a long-running subshell through `tail`.
- **`bash scripts/lint-agents-rule-budget.py`** (interpreter typo, a python file run by bash) hung until moved to the background. Recovery: stopped it and ran with `python3` under `timeout`. Prevention: one-off; take the interpreter from the shebang.
- **Hook rejections:** `sleep` in a foreground wait, `ps | grep -c`, `pgrep -f` self-matching, and a `gh issue create` with no user-visible consequence (needed `Mandated-By:`). Recovery: until-loops on rc files, `list_runs`, and the Mandated-By line. Prevention: already hook-enforced.
- **`scripts/test-all.sh --affected` queued behind sibling worktrees' runs (position 4 of the lock queue, load ~30).** Recovery: ran the named suites directly and kept the affected run queued. Prevention: none needed beyond the contention preamble.
- **Duplicate Monitor watchers armed on one file (hook warned each time).** Recovery: stopped the extra ones. Prevention: arm one watcher per path and wait on it.

## Tags
category: workflow-issues
module: inngest-key-rotate
