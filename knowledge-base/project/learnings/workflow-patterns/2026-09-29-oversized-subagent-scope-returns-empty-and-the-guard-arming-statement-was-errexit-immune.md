# Learning: an oversized subagent brief returns empty — and a guard's arming statement under `set -e` must never be a non-final `&&` operand

Date: 2026-09-29 (session of 2026-09-28)
Branch: feat-one-shot-9123-web1-reboot-unlock — PR #9179 / issue #9123

## Problem

Two failures of the same shape inside one one-shot run, one at pipeline level and one inside the code under review:

1. A work-phase subagent briefed to run the whole `soleur:work` skill (≈360 KB SKILL.md) over a 54 KB plan returned a completion with an **empty report and zero implementation commits** — the only artifact was a merge of origin/main it made during pre-flight. Nothing failed loudly; the pipeline simply produced nothing. The planning subagent before it had the same empty-report symptom but had left its artifact on disk (recoverable via the `## Acceptance Criteria` predicate in one-shot's partial-artifact contract).

2. A review seat found the production analogue inside the diff itself: the gate writer's arming step read `mount --bind / "$p" && _m=1`. Under `set -e`, a **non-final `&&` operand that fails does not trigger errexit** — the list short-circuits, `_m` stays unset, and the writer falls through to `chattr +i` the unmounted scratch dir, printing "covered inode is immutable" as success while the gate was never armed. The arming statement of a fail-closed gate was itself fail-open. Extends the class in `2026-09-25-the-errexit-model-must-be-judged-at-the-commands-position`: it is not enough that errexit is judged at the command's position — a flag-capture written as a `&&` tail is *by construction* never reached on failure, so the guard reports armed in the arm where it did nothing.

## Solution

1. Decompose oversized subagent scopes **upfront**, not after an empty completion: deliverables → suite → records as sequential, tightly-bounded passes, each with an explicit file list, return contract, and a verification sweep by the parent (the binding-items rule — positively grep each item landed, never trust a prohibition sweep or the agent's own claim). All three scoped passes completed with full reports and real commits.
2. The guard fix is syntactic: `mount --bind / "$p" || { echo '…refusing'; exit 54; }`, plus `-L` symlink refusal and a `st_dev` device-identity assert before `chattr`, plus a suite fixture that drives `mount_rc` nonzero and asserts **no chattr call** — a guard's arming step needs a mutation row proving the unarmed path refuses, not just the armed path succeeding.

## Key Insight

- An empty subagent completion is a *scope-size signal*, not a transient: retry the same shape and it fails the same way; split the scope and every pass completes.
- `set -e` coverage in provisioners is a per-statement property. Any `cmd && var=1` "record the success" idiom silently continues on the failure it exists to gate. Write `cmd || { refuse }` and pin the refusal with a stub knob (`mount_rc`), because a hardcoded `exit 0` stub makes the defect invisible to the suite — the stub's own fidelity is part of the guard.

## Tags

subagent-decomposition, errexit, guard-arming, mutation-battery, one-shot-pipeline, terraform-provisioner, shell-semantics
