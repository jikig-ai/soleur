---
title: "feat: CLEAN_STRAY mode for the workspaces-luks cutover (Ref #6588)"
date: 2026-07-19
type: feat
lane: single-domain
branch: feat-one-shot-6588-luks-clean-stray-mode
issue: 6588
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-119 (amendment)
revision: v2 (post 3-agent plan review — architecture-strategist, spec-flow-analyzer, code-simplicity)
---

# feat: CLEAN_STRAY mode for the workspaces-luks cutover (Ref #6588)

## Overview

Commit `bec339250` (merged 2026-07-19, PR #6704) added a **detect-and-refuse stray
guard** to `prepare_staging_target` in `apps/web-platform/infra/workspaces-cutover.sh`.
It fires when `$STAGING` (`/mnt/data-luks`) is a non-mountpoint AND non-empty — the
residue the 2026-07-19 run left on web-1's **root disk** when a swallowed staging mount
sent the whole rsync to the wrong target.

The guard is correct and stays. But it sits **above** the `DRY_RUN` short-circuit (it is
a read-only assert that runs in both arms by design), so it `die()`s on **every**
dispatch — including every rehearsal. No dispatch shape both reaches the host and
survives the guard. The cutover is fully wedged.

This plan adds an explicitly-gated **`CLEAN_STRAY=1` mode** — a standalone operator
entrypoint that removes the stray, structurally mirroring the existing `ROLLBACK=1` mode
— so the stray becomes remediable and the dry-run path unwedges by **remediation**, not
by weakening the guard.

The stray is **user data** (workspace source code). Deleting it is a deliberate,
documented **AP-009 deviation**, not routine cleanup. That framing drives the design.

> **v2 note.** A 3-agent review panel independently converged on three P0s in v1:
> (1) the redundancy proof reused a function that could never pass; (2) `rollback` +
> `clean_stray` together silently ran a rollback instead of the deletion; (3) the human
> whose approval *is* the authorization could not see what they were approving. All
> three are resolved below. The v1 approach is retained in
> `## Alternative Approaches Considered` so the reasoning is not lost.

---

## Research Reconciliation — Spec vs. Codebase

| Claim | Codebase reality (verified) | Plan response |
|---|---|---|
| The stray guard blocks every dispatch including dry runs | **CONFIRMED.** The guard block (`# --- Stray guard: DETECT and REFUSE, never delete.`) `die()`s ~30 lines **above** the `DRY_RUN` short-circuit. | Unwedge by remediation, not by moving the guard (D4). |
| Mirror ROLLBACK's "same environment/approval posture" | **PARTIALLY FALSIFIED.** The shape is worth mirroring; the *gate* is defective. `environment:` keys on `dry_run` only, and `dry_run` **defaults to `true`** — so `rollback=true, dry_run=true` is **ungated** while the mode block runs `DRY_RUN=0 rollback`, defeating `rollback()`'s own dry-run early-return. A fully ungated production `umount $MOUNT` + `cryptsetup close` + container restart, behind only a typo-guard token. | Mirror the shape; **do not** inherit the gate. Fix the hole in the same edit (D1b). Reviewer rated this a live P1 on `main`. |
| T4c forbids any `rm` in this file's tested surface | **CONFIRMED but narrow.** T4c's `nhas '^rm '` is scoped to a `run_case` invoking **`prepare_staging_target`** only. | Deletion goes in a separate `clean_stray()`. T4c needs **zero** edits (D2). |
| `verify_byte_identity()` can prove the stray is redundant | **FALSIFIED — this was v1's central error.** The function hardcodes `--delete` and counts `*deleting` lines, so run `$STAGING`→`$MOUNT` it itemizes every canonical file absent from the partial stray — a deterministically enormous count. It also `die()`s rather than returning a count, and proves *equality*, not *subset*. | Redundancy proof redesigned as a **top-level entry subset check** (D3). |
| A backup/escrow of the stray is needed before deletion | **Rejected — see D3.** | Provenance + subset check + pre-approval receipt, not a third copy. |
| AP-009 is a Linear issue | **FALSIFIED.** `principles-register.md`: `AP-009 \| Never delete user data \| constitution.md (Architecture/Never) \| advisory \| NFR-030`. | Treated as an architecture principle (D5). |
| `principles-register.md` should carry a deviation entry | **FALSIFIED.** The register's schema is `\| ID \| Title \| Canonical Source \| Enforcement \| Related NFRs \|` — there is no deviations column, no `Deviation` string anywhere in the file, and **no reference to ADR-055** despite ADR-055 carrying the canonical AP-009 deviation. The established convention is: deviations live in ADRs; the register is not amended. | **Register edit dropped.** The ADR-119 addendum is the record (D5). |
| ADR-119 has four dated addenda | **FALSIFIED** — it has three. | AC anchors on the new heading's distinguishing text, since a `## Addendum (2026-07-19)` heading **already exists** (the C1-verify one) and would self-satisfy a naive check. |
| The prior PR "removed the stray-copy deletion entirely" | **CONFIRMED** — `bec339250`'s body says its 5-agent review "removed the stray-copy deletion entirely"; the guard comment says "Deletion is a separate, single-purpose PR (it is user data: AP-009)." | This plan **is** that PR. Prior intent honoured. |

---

## User-Brand Impact

<!-- lint-infra-ignore start -->

**If this lands broken, the user experiences:** their workspace source code is deleted
from web-1. If the deletion targets the wrong path (`$MOUNT` instead of `$STAGING`), or
runs while `$STAGING` is a *mountpoint* (the real LUKS volume), the operator loses the
**canonical** copy — an unrecoverable loss of every user's in-progress work.

A second, subtler mode: the operator dispatches a deletion, a **rollback** runs instead,
the run exits green, and the stray is still there (v1's P0-1). The user's data survives,
but the host takes a gratuitous outage and the operator believes a remediation succeeded
that did not.

**If this leaks, the user's data is exposed via:** the deletion receipt. An
implementation that logs per-path detail publishes workspace directory structure (repo
names, branch names, potentially customer identifiers) into the Actions run log and the
Sentry drift channel — broader audiences than the data itself. This is not hypothetical:
`emit_verify_diff` emits **one marker row per differing path** (capped at
`VERIFY_DIFF_CAP=40`) to both channels, which is precisely why v1's reuse of the C1
verify machinery was a leak as well as a correctness bug.

- **Brand-survival threshold:** `single-user incident`

CPO sign-off required at plan time; `user-impact-reviewer` invoked at review time.

---

<!-- lint-infra-ignore end -->

## Hypotheses

Not a diagnostic plan. One honest UNKNOWN, which drives D3:

- **UNKNOWN — the stray's actual content.** Nobody has enumerated it; no run has been
  allowed to complete since the guard merged. The design must **not** assume the stray
  is a clean subset of `$MOUNT`. Note the corollary the v1 review surfaced: the stray is
  a *partial* copy from an aborted rsync, and `$MOUNT` has been written continuously
  since (the script's own quiesce comments establish that the redis AOF is live). So any
  control built on *full-content equality* refuses forever. The control must ask the
  question provenance actually leaves open — "does the stray contain a top-level entry
  that canonical does not?" — not "are these byte-identical?"

---

## Decisions

### D1 — CLEAN_STRAY gets ROLLBACK's *shape*, not ROLLBACK's *gate*

| Surface | ROLLBACK (existing) | CLEAN_STRAY (new) |
|---|---|---|
| Env default | `ROLLBACK="${ROLLBACK:-0}"` | `CLEAN_STRAY="${CLEAN_STRAY:-0}"` |
| Workflow input | `rollback` boolean, `default: false` | `clean_stray` boolean, `default: false` |
| Env plumb | `ROLLBACK: ${{ inputs.rollback && '1' \|\| '0' }}` | `CLEAN_STRAY: ${{ inputs.clean_stray && '1' \|\| '0' }}` |
| `.env` line | `ROLLBACK=%s` in the `printf` | `CLEAN_STRAY=%s` appended |
| Mode block | after `trap cleanup EXIT`, before the L3 gates, ends `exit 0` | same slot, immediately after — **behind the mutual-exclusion guard (D1c)** |

The `environment:` expression becomes:

```yaml
environment: ${{ (!inputs.dry_run || inputs.clean_stray || inputs.rollback) && 'workspaces-luks-cutover' || '' }}
```

**Verified fail-closed for all 8 combinations.** Because the inputs are declared
`type: boolean` and read via `inputs.*` (not `github.event.inputs.*`, which yields the
*strings* `"true"`/`"false"` and would make `!inputs.dry_run` always false), the operands
are real booleans. GHA `&&`/`||` return operand *values*: `true && 'X'` → `'X'`;
`false && 'X'` → `false`, then `false || ''` → `''`. The ungated branch is reached
**only** for `dry_run=true ∧ clean_stray=false ∧ rollback=false`. A non-`workflow_dispatch`
context yields null inputs → `!null` = true → gated. **Never invert the operands.**

**Requirement 2 is enforced at three layers**, cheapest first (the v1 ordering was
backwards — the cheap layer ran last, after a human had already been paged):

1. **Workflow, pre-gate** — a validation step co-located with the confirm-token check
   fails a `clean_stray=true, dry_run=true` dispatch **before** the environment gate, so
   no reviewer is woken for a run that cannot proceed.
2. **Workflow, gate** — the `environment:` expression above.
3. **Script** — the mode block refuses if `DRY_RUN=1` accompanies `CLEAN_STRAY=1`,
   rather than silently forcing `DRY_RUN=0` the way ROLLBACK does. The refusal message
   names the remedy ("untick dry_run"), because `dry_run` defaults to **true** and the
   natural dispatch — tick `clean_stray`, change nothing else — lands here.

### D1b — the ROLLBACK gate hole, and its siblings, are fixed in the same edit

`dry_run` is used as a **proxy for "which mode"** across this workflow. That synonymy was
true when the file was written and this change breaks it.

**Deepen-plan verified the count.** `inputs.dry_run` appears **7 times**, of which **4 are
functional** (non-comment): lines 88, 117, 200, 305. An earlier draft of this plan claimed
three and missed the fourth — the verify-the-negative sweep caught it. All four are now
accounted for:

| # | Expression | Today | Becomes | Why |
|---|---|---|---|---|
| 1 | `environment:` (`:88`) | `!inputs.dry_run` | `!dry_run \|\| clean_stray \|\| rollback` | Closes the ungated-rollback hole. |
| 2 | Loopback validation gate `if:` (`:117`) | `!inputs.dry_run` | `!dry_run && !rollback && !clean_stray` | Otherwise a `clean_stray` dispatch runs a full `apt-get install cryptsetup-bin` + losetup/mkfs LUKS suite, and a **red unrelated suite blocks the deletion permanently**. Same defect already applies to `rollback`: an emergency recovery gated behind a multi-minute validation of a path rollback does not use. |
| 3 | `DRY_RUN` env plumb (`:200`) | `inputs.dry_run && '1' \|\| '0'` | **unchanged** | Correct as-is — this occurrence genuinely means `dry_run`, not "which mode". |
| 4 | `Cutover summary` `DRY:` (`:305`) | `inputs.dry_run` | augmented with mode + magnitude (FR17) | Otherwise a deletion's permanent artifact reads `Dry run: false` and nothing else — and a rollback dispatched with `dry_run=true` reads `Dry run: **true**` on a run that performed a **real** rollback. |

Plus the **Hetzner volume lookup** in the Run step, unconditional today, which must be
skipped when `clean_stray`: it hard-fails unless *exactly one*
`soleur-web-platform-data-luks` volume exists, while `clean_stray()` runs **above**
`FRESH_DEV`/`read_key` and needs no device at all. Post-incident that volume may be
detached — the cleanup path would be unreachable for an entirely unrelated reason.
`WORKSPACES_LUKS_DEV` is omitted from the `.env` on that arm.

Each change only ever makes a destructive arm *harder* to reach, removes an irrelevant
precondition, or improves the permanent record. **None removes an approval.** All are
called out in the PR body, not folded in silently.

### D1c — mutual exclusion between modes (v1 P0-1)

<!-- lint-infra-ignore start -->

The ROLLBACK block ends in `exit 0`, so a CLEAN_STRAY block placed after it is
**unreachable** whenever `ROLLBACK=1`. The operator who ticks both types
`DELETE-STRAY-USER-DATA-AP-009`, gets a **rollback** (`umount $MOUNT`, `cryptsetup
close`, `docker stop`, `resume_writers`), the run exits **0**, and the stray is
untouched. Per the script's own `_PREPARE_ABORT_NOTE`, a rollback with no freeze held
"would umount the LIVE plaintext volume at ${MOUNT} and cause a gratuitous outage."

The most likely operator to tick both is exactly the one who has read "the cutover is
wedged, try the recovery modes." Mitigations, both layers:

- **Script:** a mutual-exclusion refusal **before both** mode blocks —
  `ROLLBACK=1` + `CLEAN_STRAY=1` → `emit_drift clean_stray_mode_conflict` + `die`.
- **Workflow:** a pre-gate validation step fails the dispatch when both are ticked.

<!-- lint-infra-ignore end -->

### D2 — T4c reconciliation: a separate function, zero test edits

The deletion lives in a standalone `clean_stray()` invoked **only** from the CLEAN_STRAY
mode block — never from `prepare_staging_target`, never from the main body.

- **T4c is not edited, weakened, or deleted.** Its `run_case` invokes
  `prepare_staging_target`, which still issues no `rm` on any path. The detect-and-refuse
  invariant stays mechanically enforced for every non-CLEAN_STRAY arm — achieved *by
  construction* rather than by narrowing an assertion.
- The T4 comment gains **one appended sentence** pointing at `clean_stray()` and the
  ADR-119 addendum, so a future reader does not read T4c as a whole-file prohibition.
  Comment only; the assertion is untouched.
- **The new tests must NOT mirror T4c's `nhas '^rm '` idiom.** `workspaces-luks-harness.sh`
  makes `rm` a **passthrough recorder** (`rm() { rec "rm $*"; command rm "$@"; }`), so
  *every* `rm` in the traced scope is recorded — including any temp-file cleanup. New
  refusal assertions must be scoped to the target: `nhas "^rm -rf $WORKSPACES_STAGING"`.
  Mirroring the bare idiom here would burn a full RED/GREEN cycle on a false failure.

### D3 — redundancy: top-level subset, not content equality (v1's P0)

v1 proposed reusing `verify_byte_identity()`. All three reviewers independently
falsified it:

- It hardcodes `--delete` and counts `*deleting` lines → run `$STAGING`→`$MOUNT` it
  itemizes every canonical path absent from the partial stray. Deterministically
  enormous. **`clean_stray()` would refuse on every real invocation, making AC14 — the
  plan's entire goal — unreachable.**
- It `die()`s rather than returning a count, so "refuse if non-zero" cannot be
  implemented by calling it. Making it return would mean refactoring the most
  safety-critical function on the freeze path, inside a PR about deleting a directory.
- It proves **equality**, not **subset** — the wrong predicate.
- Even with `--delete` removed, `-aHAX --checksum` compares perms, owner, times,
  hardlinks, ACLs and xattrs, and the counter deliberately counts attribute-only codes.
  The stray is on the **root filesystem**; canonical is on the Hetzner data volume —
  different filesystems, plausibly different xattr/ACL support, mtimes from an
  interrupted transfer, and continuous live writes. Spurious refusals indistinguishable
  from real non-redundancy.
- On non-zero diff it calls `emit_verify_diff`, emitting **one marker row per differing
  path** to log *and* syslog — the exact leak this plan's User-Brand Impact forbids,
  firing on the guaranteed path.

**Chosen instead:** the safety that actually covers the catastrophic mode is FR5
(`$STAGING` is a non-mountpoint) + FR6 (`_same_dev` + `$MOUNT` healthy) — deterministic,
~8 lines, already-hardened primitives. On top of that, a **top-level entry subset
check**: assert every `-maxdepth 1` entry name in `$STAGING` also exists in `$MOUNT`, and
refuse otherwise. This:

- asks the question provenance leaves genuinely open (did something *other than* the
  misdirected rsync write here?) rather than one live writes guarantee will fail;
- reuses the enumeration the receipt needs anyway;
- emits counts and top-level names only — no recursive listing, no per-path leak;
- is ~5 lines rather than an rsync engine.

**Provenance is the primary evidence, and it is strong:** nothing ever wrote to
`$STAGING` except the misdirected rsync of `$MOUNT` — no service, no mount, no container
points at it. The guard's own comment states it: "This is a DUPLICATE; the canonical data
is at $MOUNT." The subset check is a cheap falsifier for that claim, not a re-derivation
of it.

**The decisive control remains the human**, which is why D6 restructures the workflow so
the approver actually sees the magnitude before approving.

### D4 — the guard is not moved or relaxed

The dry-run path unwedges because the stray **is gone**, not because the guard stopped
firing. A rehearsal over a live stray must keep reporting red: it genuinely cannot
certify the staging path while a root-disk duplicate sits at `$STAGING`. Moving the guard
below the `DRY_RUN` short-circuit would make every future rehearsal green over the exact
defect that caused this incident. Requirement 4 is satisfied by **remediation**, and
AC14 is written that way.

*(Considered and rejected: a 3-line change making the guard non-fatal in the dry-run arm
with a distinct marker, which would unwedge rehearsals today without any deletion. It is
genuinely separable and would decouple urgency — but the stray must be gone before the
real freeze regardless, so the deletion path is required either way, and shipping a
rehearsal that proceeds over a live stray re-opens exactly the certification gap D4
exists to hold shut.)*

### D5 — AP-009 deviation artifact: amend ADR-119; do **not** touch the register

- **Amend ADR-119**, do not write a new ADR. CLEAN_STRAY exists *only* because the
  ADR-119 cutover created the stray; it is not an independent architectural decision. It
  becomes `## Addendum (2026-07-19): the stray-copy carve-out (CLEAN_STRAY, #6588)`,
  matching the file's three existing dated addenda.
- The addendum carries an ADR-055-shaped bullet — **`AP-009 (Never delete user data):
  Deviation — documented carve-out.`** — stating what is deleted, why it is not data
  loss (provenance-established duplicate; canonical retained at `$MOUNT`), the guardrails
  (mountpoint + `_same_dev` refusals, subset check, environment gate, distinct confirm
  token, pre-approval receipt), and the scope limit (this path, this mode).
- **No `principles-register.md` edit.** The register has no deviations column, contains
  no `Deviation` string, and does not reference ADR-055 despite ADR-055 carrying the
  canonical AP-009 deviation. The convention is: deviations live in ADRs. v1's proposed
  edit conflated the *Canonical Source* column (where AP-013 points at ADR-027 because
  ADR-027 *is* that principle's source) with a deviation reference — different semantics.
  Putting ADR-119 in AP-009's Canonical Source cell would be actively wrong; AP-009's
  source is `constitution.md`. Adding a `Deviations` column touches every row and is its
  own decision, out of scope here.

### D6 — the AP-009 deviation must be legible to the **approver**, not just the dispatcher

v1 aimed all three legibility surfaces at the *dispatcher*. But the workflow's own header
is explicit: "the `environment: workspaces-luks-cutover` gate is the ONLY human
authorization" and "the typed `confirm` token is a typo-guard, **NOT** the authorization."

The GitHub environment-approval UI shows workflow name, actor and ref — **not the
dispatch inputs**. After D1's expression change, a routine cutover, a rollback, and a
user-data deletion all resolve to the same gated environment. The approver could not tell
them apart, and the magnitude is computed host-side — i.e. only *after* approval. That is
a literal instance of "the operator sees the AP-009 deviation only after the delete,"
which hard requirement 3 forbids.

**Resolution — split the job in two:**

- **`probe` job (ungated).** Resolves the mode, reaches web-1 read-only, computes and
  emits the magnitude (`stray_bytes`, `stray_entries`, top-level entry names) and the
  subset-check result, and writes the **AP-009 deviation banner + magnitude** to
  `$GITHUB_STEP_SUMMARY`. Issues **no** `rm`. Safe to run in any arm.
- **`delete` job (gated, `needs: probe`).** Carries `environment:` and performs the
  deletion.

The approver opens the run, reads the summary the probe already wrote, and approves with
the magnitude in front of them. This single restructure resolves all three of v1's
legibility/dead-end defects (approver blindness, the wasted approval on a guaranteed
refusal, and the "refusal with no next action" dead end — the probe *is* the read-only
inspection arm).

Dispatch-time surfaces are retained on top:

1. **A distinct confirm token** — `DELETE-STRAY-USER-DATA-AP-009`, not the cutover's
   `CUTOVER-WORKSPACES-LUKS`. The operator physically types "user data" and the principle
   ID; a pasted cutover token cannot reach a deletion.
2. **The input description names the deviation** — states that this deletes user data
   from the root disk, that it is a documented AP-009 deviation (linking the ADR-119
   addendum), and that it requires `dry_run=false`.

The PR body carries the same AP-009 deviation statement (hard requirement 3).

---

## Functional Requirements

- **FR1** — `CLEAN_STRAY="${CLEAN_STRAY:-0}"` is defined alongside `ROLLBACK`; a
  `clean_stray()` function is added, defined **above** the `BASH_SOURCE` sourcing guard
  (`if [ "${BASH_SOURCE[0]:-$0}" != "$0" ]; then return 0`) so the test suite can source
  it; and the CLEAN_STRAY mode block is placed in the same slot as ROLLBACK's (after
  `trap cleanup EXIT`, before the L3 gates), terminating in `exit 0`. That slot is safe
  because `cleanup()`'s rollback condition requires `FREEZE_HELD`, which is unset there.
  `prepare_staging_target` is **not** modified.
- **FR2** — A mutual-exclusion refusal precedes **both** mode blocks: `ROLLBACK=1` with
  `CLEAN_STRAY=1` emits `clean_stray_mode_conflict` and dies (D1c).
- **FR3** — The mode block refuses if `DRY_RUN=1` accompanies `CLEAN_STRAY=1`, emitting
  `clean_stray_dryrun_conflict`. The message names the remedy ("untick dry_run"). It does
  **not** force `DRY_RUN=0`.
- **FR4** — `clean_stray()` refuses unless `$STAGING` is a **non-mountpoint** and
  **non-empty** (the guard's own predicate). A mountpoint is the real LUKS volume and
  must never be `rm`'d. An already-empty `$STAGING` emits an `already_clean` marker and
  exits **0** — re-dispatch is the most likely operator action after an ambiguous run
  log, and the file already establishes this principle at `rollback()`'s mapper guard
  ("a recovery-path signal that cries wolf gets ignored").
- **FR5** — `clean_stray()` refuses if `$MOUNT` is not a mountpoint, if its source is not
  a block device, or if `$MOUNT` and `$STAGING` resolve to the same device (`_same_dev`).
- **FR6** — `clean_stray()` performs the **top-level subset check** (D3): every
  `-maxdepth 1` entry name in `$STAGING` must exist in `$MOUNT`. Otherwise it emits
  `clean_stray_not_subset` (naming the offending entries, top-level only) and refuses.
  It does **not** call `verify_byte_identity()`.
- **FR7** — Before the first `rm`, `clean_stray()` emits an AP-009 deviation banner plus
  magnitude (`stray_bytes`, `stray_entries`, top-level entry names) and the subset-check
  result, on both the log and the `logger` marker channel, under a **distinct marker
  name** `SOLEUR_WORKSPACES_LUKS_CLEAN_STRAY` — never the existing
  `SOLEUR_WORKSPACES_LUKS_STAGING_TARGET`, whose `result=`/`reason=` vocabulary is
  asserted by the T-series and the `record_arm` coverage matrix.
- **FR8** — The deletion removes the contents of `$STAGING` **dotfile-inclusively**
  (`find "$STAGING" -mindepth 1 -maxdepth 1 -exec rm -rf {} +`, never `"$STAGING"/*`),
  leaving `$STAGING` itself in place as an empty non-mountpoint directory. A workspace
  tree is full of `.git`/`.cache`; a glob-based removal leaves the guard correctly still
  firing after a "successful" run.
- **FR9** — A post-deletion assertion confirms `$STAGING` is empty; a terminal marker
  records the outcome. A partial removal emits `clean_stray_incomplete`.
- **FR10** — The workflow gains a `clean_stray` boolean input (`default: false`) whose
  description names the AP-009 deviation and the `dry_run=false` requirement (D6),
  plumbed through the same `printf` `.env` path as `ROLLBACK`.
- **FR11** — A pre-gate validation step, co-located with the confirm-token check, fails
  the dispatch when `clean_stray && dry_run` or when `clean_stray && rollback` — before
  any reviewer is paged and before the bridge is raised.
- **FR12** — The confirm-token step requires `DELETE-STRAY-USER-DATA-AP-009` when
  `clean_stray` is true and `CUTOVER-WORKSPACES-LUKS` otherwise. Comparison stays a
  literal comparison against an env-passed value — never interpolated into the condition.
- **FR13** — The workflow is split into an ungated `probe` job and a gated `delete` job
  (`needs: probe`), with the probe writing the AP-009 banner + magnitude + subset result
  to `$GITHUB_STEP_SUMMARY` before the approval gate (D6). The probe issues no `rm`.
- **FR14** — The `dry_run`-as-mode-proxy expressions are corrected per D1b (4 functional
  occurrences at `:88`, `:117`, `:200`, `:305` — `:200` stays unchanged — plus the
  Hetzner volume lookup):
  `environment:`, the loopback-validation-gate `if:`, and the Hetzner volume lookup.
- **FR15** — ADR-119 gains the dated addendum with the ADR-055-shaped AP-009 deviation
  bullet. **`principles-register.md` is not edited** (D5).
- **FR16** — T4c is **not** edited; its surrounding comment gains one sentence pointing
  at `clean_stray()` and the ADR-119 addendum. The `dry_run` input's "COVERS / does NOT
  cover" description gains a clause noting `clean_stray` is refused in that arm, and the
  workflow header comment block is refreshed where this change makes it stale.
- **FR17** — The `Cutover summary` step reports the **mode** (not just `Dry run:`) plus
  the magnitude and subset result. Today it prints `**Dry run:** ${DRY}` only — so a
  deletion's permanent artifact would read "Dry run: false" and nothing else, and AC15
  asks the operator to transcribe magnitude figures from somewhere.

---

## Implementation Phases

Phase order is load-bearing: the contract ships before its consumer, and tests precede
implementation (`cq-write-failing-tests-before`).

### Phase 0 — Preconditions (verify, do not assume)
1. Confirm the stray guard still precedes the `DRY_RUN` short-circuit.
2. Confirm T4c's `run_case` still invokes `prepare_staging_target` only.
3. **Read `workspaces-luks-harness.sh`'s `rm` recorder** and confirm the
   `$STAGING`-scoped assertion shape the new tests need (D2).
4. Confirm `clean_stray()`'s required position relative to the `BASH_SOURCE` guard.
5. Re-confirm `verify_byte_identity()` hardcodes `--delete` and `die()`s — the premise
   behind D3's redesign. If either has changed, D3 is revisited before coding.

### Phase 1 — RED: tests for `clean_stray()`
Added to `workspaces-luks-staging.test.sh`. **All refusal assertions use
`nhas "^rm -rf $WORKSPACES_STAGING"`, not the bare `^rm ` idiom** (D2).
- **T4d** — non-mountpoint non-empty `$STAGING`, healthy `$MOUNT`, subset holds →
  deletes and emits the success marker. Fixture **includes a dotfile entry**, asserted
  removed (FR8).
- **T4e** — `$STAGING` is a **mountpoint** → refuses, no `rm`.
- **T4f** — a top-level entry present in `$STAGING` but **absent** from `$MOUNT` →
  refuses with `clean_stray_not_subset`, no `rm` (FR6).
- **T4g** — `CLEAN_STRAY=1` with `DRY_RUN=1` → refuses, no `rm` (FR3).
- **T4h** — `CLEAN_STRAY=1` with `ROLLBACK=1` → refuses with `clean_stray_mode_conflict`,
  no `rm`, **and no rollback** (FR2 / D1c).
- **T4i** — `_same_dev($MOUNT, $STAGING)` → refuses, no `rm` (FR5).
- **T4j** — already-empty `$STAGING` → `already_clean`, exit 0, no `rm` (FR4).
- **T4c is left byte-identical.** Confirm it still passes.

### Phase 2 — GREEN: `clean_stray()` + mode blocks
Implement FR1–FR9 in `workspaces-cutover.sh`.

### Phase 3 — Workflow
Implement FR10–FR14, FR16, FR17 in `.github/workflows/workspaces-luks-cutover.yml`: the
input, pre-gate validation, conditional confirm token, the probe/delete job split, the
three corrected `dry_run`-proxy expressions, the `.env` plumb, the summary, and the
header/`dry_run`-description refresh.

### Phase 4 — ADR
Implement FR15: the ADR-119 addendum.

### Phase 5 — Test comment + full suite
Implement FR16's test-comment half. Run the full staging suite and the loopback suite.

---

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — `bash apps/web-platform/infra/workspaces-luks-staging.test.sh` passes,
  including T4/T4b/**T4c** unchanged and new T4d–T4j.
- **AC2** — The workflow's `jobs.delete.environment` value, parsed as **YAML** (never
  grepped — the header comments discuss this expression at length and a grep passes
  vacuously), equals the exact expected literal string
  `${{ (!inputs.dry_run || inputs.clean_stray || inputs.rollback) && 'workspaces-luks-cutover' || '' }}`.
  Exact-string equality catches operand inversion, which is the actual risk; it needs no
  GHA-semantics simulator.
- **AC3** — Parsed as YAML: the loopback-gate step's `if:` contains all of
  `!inputs.dry_run`, `!inputs.rollback`, `!inputs.clean_stray`; the `probe` job carries
  **no** `environment:` key; the `delete` job declares `needs: probe`.
- **AC4** — `actionlint .github/workflows/workspaces-luks-cutover.yml` is clean, and each
  modified `run:` body passes `bash -n` **when extracted** (`bash -n` on the `.yml` itself
  parses YAML as bash and proves nothing).
- **AC5** — A `clean_stray=true, dry_run=true` dispatch fails at the pre-gate validation
  step. Verified by running that step's extracted shell against the input combination and
  asserting non-zero exit — the real script, not a model of it.
- **AC6** — ADR-119 contains the heading
  `## Addendum (2026-07-19): the stray-copy carve-out (CLEAN_STRAY, #6588)` **and** the
  literal `AP-009 (Never delete user data): Deviation` **within that section's body**
  (extracted flag-based, not via an awk `/start/,/end/` range, which self-matches on the
  start line). Anchoring on the bare `## Addendum (2026-07-19)` prefix would self-satisfy:
  a 2026-07-19 addendum already exists.
- **AC7** — `git diff` shows **no** change to `principles-register.md` (D5) and **no**
  change to the T4c assertion line containing
  `the stray guard runs NO rm — it detects and refuses`.
- **AC8** — `clean_stray()` emits under `SOLEUR_WORKSPACES_LUKS_CLEAN_STRAY` and issues
  no recursive path enumeration: its body contains no `find` without `-maxdepth 1`
  reaching the log or marker channel (FR7 / User-Brand Impact).

### Post-merge (operator — automation-gated)

- **AC9** — Dispatch `clean_stray=true, dry_run=false`, token
  `DELETE-STRAY-USER-DATA-AP-009`. The **probe** job writes the AP-009 banner, magnitude
  and subset result to the step summary **before** the approval gate. Approve at the
  environment reviewer gate; the `delete` job emits the pre-`rm` banner and the
  post-deletion assertion. *Automation: the dispatch is `gh workflow run`-able; the
  environment reviewer approval is the sole human gate — it is the C19/AC20b
  authorization on user-data deletion, and automating it away would remove the control
  this plan rests on.*
- **AC10** — **Requirement 4.** After AC9, dispatch `dry_run=true` (all else false) and
  confirm it runs past `prepare_staging_target`, emitting
  `SOLEUR_WORKSPACES_LUKS_STAGING_TARGET … result=dryrun reason=ok` — the guard no longer
  wedges the rehearsal. Verified via `gh run view`; no SSH.
- **AC11** — `gh issue comment 6588` records the remediation with the magnitude figures
  from the AC9 run. The PR body uses `Ref #6588`, **not** `Closes` — issue closure stays
  with the epic.

---

## Observability

```yaml
liveness_signal:
  what: SOLEUR_WORKSPACES_LUKS_STAGING_TARGET with result=dryrun reason=ok on a rehearsal dispatch (proves the unwedge); SOLEUR_WORKSPACES_LUKS_CLEAN_STRAY on a cleanup dispatch
  cadence: per dispatch (workflow_dispatch only — no scheduled cadence)
  alert_target: GitHub Actions run log + step summary + syslog via `logger -t $LUKS_LOG_TAG`
  configured_in: apps/web-platform/infra/workspaces-cutover.sh (clean_stray, emit_staging_target)

error_reporting:
  destination: emit_drift -> the workspaces-luks Sentry drift channel (feature=workspaces-luks op=workspaces-luks-drift)
  fail_loud: true — every refusal path calls emit_drift with a distinct named reason before die()

failure_modes:
  - mode: clean_stray invoked while $STAGING is a mountpoint (would delete the real LUKS volume)
    detection: mountpoint predicate; emits reason=clean_stray_staging_is_mountpoint before die
    alert_route: emit_drift + non-zero workflow exit
  - mode: $MOUNT and $STAGING are on the same filesystem
    detection: stat -c %d comparison on the two DIRECTORIES; emits reason=clean_stray_same_device.
      NOT _same_dev/findmnt — the mountpoint refusal upstream guarantees $STAGING is not a mount
      target, so a findmnt-sourced operand is always empty and that check would be dead code.
    alert_route: emit_drift + non-zero workflow exit
  - mode: the stray holds a path canonical does not (provenance falsified)
    detection: relative-path subset check to depth 2 (where user identity lives — a depth-1 check
      is vacuous on the real host, whose top level is workspaces/ plugins/ redis/); emits
      reason=clean_stray_not_subset carrying a COUNT, never the offending names (they are per-user
      workspace ids and the marker channel is a wider audience than the data)
    alert_route: emit_drift + non-zero workflow exit
  - mode: a probe binary clean_stray depends on is absent (mountpoint/findmnt/find/stat/du)
    detection: command -v loop before any guard runs; emits reason=clean_stray_tool_missing.
      Without it, `mountpoint -q` exits 127 and the catastrophic-mode `if` reads FALSE.
    alert_route: emit_drift + non-zero workflow exit
  - mode: a filesystem is mounted BENEATH $STAGING (rm -rf would descend into live data)
    detection: findmnt -rno TARGET prefix scan; emits reason=clean_stray_nested_mount
    alert_route: emit_drift + non-zero workflow exit
  - mode: the preflight probe cannot read web-1, so the approver would see an EMPTY magnitude banner
    detection: probe rc + `state=` shape assertion; the step FAILS and writes
      "PROBE FAILED — DO NOT APPROVE" to the step summary rather than degrading to a green step
    alert_route: workflow step failure before the environment gate is reached
  - mode: CLEAN_STRAY=1 dispatched with DRY_RUN=1 (requirement-2 violation attempt)
    detection: pre-gate workflow step, then mode-block predicate; emits reason=clean_stray_dryrun_conflict
    alert_route: workflow step failure before the gate; emit_drift + non-zero exit at the script layer
  - mode: CLEAN_STRAY=1 dispatched with ROLLBACK=1 (rollback would silently win)
    detection: mutual-exclusion refusal before both mode blocks; emits reason=clean_stray_mode_conflict
    alert_route: workflow step failure before the gate; emit_drift + non-zero exit at the script layer
  - mode: rm partially fails, leaving $STAGING non-empty
    detection: post-deletion emptiness assertion; emits reason=clean_stray_incomplete
    alert_route: emit_drift + non-zero exit; the guard correctly keeps refusing

logs:
  where: GitHub Actions run log + step summary + web-1 syslog via logger -t $LUKS_LOG_TAG
  retention: GitHub Actions default (90d); syslog per host journald retention

discoverability_test:
  command: gh run list --workflow=workspaces-luks-cutover.yml --limit 1 --json databaseId --jq length
  expected_output: "1"
  # Runnable TODAY and pipe-free (the preflight Check-10 executor refuses shell-active tokens, and
  # `gh run view --log` errors on an in-progress run — on the clean_stray arm the run sits pending
  # environment approval for an unbounded window, i.e. exactly when an operator would reach for it).
  # What this proves: the cutover workflow's run surface is queryable with NO ssh. The marker itself,
  # SOLEUR_WORKSPACES_LUKS_CLEAN_STRAY, lands in two places once a cleanup dispatch has completed:
  #   (a) the run log  — gh run view <run-id> --log --job cutover   (job must be COMPLETED)
  #   (b) Better Stack — the host emits it via `logger -t $LUKS_LOG_TAG` (luks-monitor), which
  #       vector.toml already allowlists by SYSLOG_IDENTIFIER, so no new sink wiring is owed.
  # Refusal arms surface via: gh run view <run-id> --log-failed
```

No `ssh` appears in any verification command (`hr-no-ssh-fallback-in-runbooks`).

### Soak follow-through

None — no time-gated close criterion. AC10 either passes on the next rehearsal or it
does not.

---

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-119** with `## Addendum (2026-07-19): the stray-copy carve-out (CLEAN_STRAY,
#6588)`, carrying the ADR-055-shaped AP-009 deviation bullet (D5). An in-scope task of
this plan, not a follow-up.

### C4 views

**No C4 impact.** Verified at implementation time by reading all three model files
(`diagrams/{model.c4,views.c4,spec.c4}`) against the completeness mandate:

- **External human actors** — none added. The dispatching operator and the approving
  reviewer are both the existing operator actor; no new correspondent or recipient.
- **External systems / vendors** — none added. No vendor edge is touched. Note this is a
  *consequence of D3*: v1's escrow alternative **would** have added an R2 data-store edge,
  which is part of why it was rejected.
- **Containers / data stores** — none added. `$STAGING` is a directory on an existing
  host's root disk, already inside the web-1 boundary; content is removed from it.
- **Actor↔surface access relationships** — none changed. The operator already had
  dispatch access via the same environment gate; CLEAN_STRAY is a new *mode* of an
  existing modelled relationship at the same trust boundary. The probe/delete job split
  is an internal workflow decomposition, not a new boundary.

If the Phase 4 read contradicts any line above, the C4 edit becomes in-scope and this
section is corrected — the enumeration is the deliverable, not the "None".

### Sequencing

The addendum describes the carve-out as adopted on merge; no soak-gated status flip.

---

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Infrastructure/shell change on a sole-copy-user-data path. Risk
concentrates in three places: (1) the gate expressions, where `dry_run` had been serving
as a proxy for "which mode" in three places — corrected together in D1b, since fixing one
and leaving two would leave the same class of bug in the same file; (2) mode reachability,
where an `exit 0` in an earlier block silently swallowed a later mode (D1c) — a class that
a gate-resolution truth table structurally cannot catch, because the *gate* resolves
correctly and the *script* then does the wrong thing; (3) the deletion predicate, mitigated
by FR4/FR5/FR6 and dedicated refusal tests. The v1→v2 revision replaced a
verification-by-machinery control that could not pass with a provenance-plus-cheap-falsifier
control plus a genuine human review surface — the right direction for a principle whose
spirit is "do not lose the user's work" rather than "never issue `rm`".

### Product/UX Gate

Not applicable — Product domain not relevant. No path in `## Files to Edit` matches the
UI-surface term list or glob superset; the change is shell + workflow YAML + an ADR.

---

## Infrastructure (IaC)

**Not applicable.** No new infrastructure: no server, service, cron, DNS record, cert,
secret, firewall rule or vendor account. The change modifies an existing
`workflow_dispatch` workflow and an existing script running on an already-provisioned host
over the already-provisioned CF Tunnel SSH bridge with already-provisioned credentials. No
Terraform root is touched; no `TF_VAR_*` added. The `workspaces-luks-cutover` environment
already exists with a required-reviewer set.

Note the `concurrency: web-1-swap` group is `cancel-in-progress: false`, so a wedged
cutover run can block the remediation that unwedges it — worth knowing at dispatch time,
but not a change this plan makes.

---

## GDPR / Compliance

Canonical regex surfaces (schemas, migrations, auth flows, API routes, `.sql`) untouched,
but trigger **(b)** fires: threshold is `single-user incident`. Invoke
`/soleur:gdpr-gate` at implementation time against the deletion path and the marker emit.

Preliminary read: the change **reduces** processing surface — it deletes an
unauthorised-by-design duplicate from a root disk, a storage-limitation improvement, not a
new processing activity. No Art. 30 entry warranted (no new purpose, recipient, retention
period, territory or controller). The live concern is the receipt, bounded by AC8 and by
D3's rejection of the per-path `emit_verify_diff` channel.

---

## Files to Edit

- `apps/web-platform/infra/workspaces-cutover.sh` — FR1–FR9.
- `apps/web-platform/infra/workspaces-luks-staging.test.sh` — T4d–T4j; one appended
  comment sentence near T4. **T4c's assertion is not edited.**
- `.github/workflows/workspaces-luks-cutover.yml` — FR10–FR14, FR16, FR17.
- `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`
  — FR15 addendum.

## Files to Create

None. `clean_stray()` lives in `workspaces-cutover.sh` beside `rollback()` — a sibling
file would break the single-file content-carrier model the workflow's tar bundle depends
on.

## Open Code-Review Overlap

To be populated at implementation time by querying open `code-review`-labelled issues
against the four files above (Phase 1.7.5). Not yet run — the file list was finalized in
this revision.

---

## Risks & Mitigations

<!-- lint-infra-ignore start -->

| Risk | Mitigation |
|---|---|
| The deletion targets `$MOUNT` instead of `$STAGING` | FR4 (non-mountpoint), FR5 (`_same_dev` + `$MOUNT` health), T4e/T4i. |
| A gate expression is written with inverted operands, silently ungating a destructive arm | AC2 asserts exact-string equality on the parsed YAML value. |
| An earlier mode's `exit 0` silently swallows CLEAN_STRAY, running a rollback instead | FR2 mutual exclusion at both layers; T4h; FR11 pre-gate step. |
| The approver authorizes a user-data deletion without seeing what it deletes | FR13's probe/delete split writes magnitude + AP-009 banner to the step summary **before** the gate. |
| The subset check refuses spuriously and re-wedges the operator | Top-level names only — no content, mtime, xattr or ACL comparison, so live writes to `$MOUNT` cannot trip it. The probe job doubles as the read-only inspection arm when it does refuse. |
| The stray holds unique data | Provenance (nothing else ever wrote there) is primary; the subset check is a cheap falsifier; the human approver reading the magnitude is decisive. |
| A glob-based `rm` leaves dotfiles, so the guard keeps firing after a "successful" run | FR8 mandates the `find -mindepth 1 -maxdepth 1 -exec` form; T4d's fixture includes a dotfile. |
| Deleting `$STAGING` itself breaks the next run's `mkdir -p` | FR8 removes contents only; FR9 asserts the resulting state. |
| The receipt publishes workspace structure to a wider audience than the data | AC8 bounds enumeration to `-maxdepth 1`; D3 rejects the per-path `emit_verify_diff` channel; `_vscrub` applied as elsewhere. |
| Fixing the ROLLBACK/loopback/volume-lookup gates changes behaviour operators rely on | Each only makes a destructive arm harder to reach or removes an irrelevant precondition; never removes an approval. Called out in the PR body. |

---

<!-- lint-infra-ignore end -->

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| **Reuse `verify_byte_identity()` for the redundancy proof (v1's FR7)** | Hardcodes `--delete`, counts `*deleting`, `die()`s instead of returning, proves equality not subset, and leaks per-path rows. Would refuse deterministically on the real host, making the plan's own goal unreachable. Replaced by D3. |
| Escrow the stray to R2 before deleting | Creates a **third** copy of user data on a new egress path with its own retention/DSAR/Art. 30 obligations — arguably a worse AP-009 outcome. The existing escrow path is sized for a ~2 MB LUKS header, not a bulk dataset. |
| Delete unconditionally with a loud message | Asserts the redundancy claim rather than leaving it falsifiable. |
| A separate single-purpose cleanup workflow | Would duplicate ~40 lines of subtle, security-load-bearing plumbing (CF Tunnel bridge, persistent-`STATE_DIR` `mktemp`, tar content-carrier, 0600 stdin `.env` with shred trap) **and** create a second workflow that can reach web-1 as root and `rm -rf`. Worse, not cheaper. |
| **A separate single-purpose cleanup SCRIPT, shipped by the same tar bundle** (surfaced at review, not considered in v1/v2) | Genuinely cheaper than the rejected separate *workflow*: it costs one filename in the existing explicit tar list plus one conditional selecting which file to `bash`, reuses the bridge / `.env` / shred trap / concurrency group / reviewer gate, and inherits every helper via the `BASH_SOURCE` sourced-detection guard that already exists for the verify harness. Its real payoff is structural — `assert_mode_exclusive()` and T4h exist *only* because both modes share one main body in which ROLLBACK's `exit 0` shadows the block below it; separate entrypoints make the modes exclusive **by construction** and delete a guard, a drift reason, a test case, and a class of operator error. **Not adopted here** because the deletion is a one-shot remediation of a specific incident rather than a standing verb, and co-location keeps the stray guard, its magnitude probe, and the deletion that resolves it readable in one place — but the correctness tax is real and this row records it. Revisit if a third mode (`CONFIRM_WIPE`) lands in the same body. |
| Move the stray guard below the `DRY_RUN` short-circuit | Makes every future rehearsal green over the exact defect that caused this incident (D4). |
| Make the guard non-fatal in the dry-run arm with a distinct marker | Genuinely separable and would unwedge rehearsals in a 3-line PR — but the stray must go before the real freeze regardless, so the deletion path is needed either way, and it re-opens the certification gap D4 holds shut. |
| Add a `--force` escape hatch to `prepare_staging_target` | Puts the `rm` inside the function T4c protects, forcing T4c to be weakened — exactly what the constraint forbids. |
| A new ADR instead of amending ADR-119 | Strands the carve-out from the decision that necessitated it (D5). |
| Add an AP-009 deviation row to `principles-register.md` | No deviations column exists, no precedent (ADR-055 is not referenced there either); the convention is that deviations live in ADRs (D5). |
| Reuse the `CUTOVER-WORKSPACES-LUKS` confirm token | Lets a muscle-memory dispatch reach a user-data deletion (D6). |

Nothing above is deferred to a later phase, so no deferral tracking issues are required.

---

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- **`dry_run` was a proxy for "which mode" in three expressions.** Fixing one and leaving
  two leaves the same bug class in the same file. Grep for `inputs.dry_run` across the
  workflow and account for every occurrence.
- **`rm` is a passthrough recorder in the test harness** — every `rm` in traced scope is
  recorded, including temp-file cleanup. Refusal assertions must be `$STAGING`-scoped
  (`nhas "^rm -rf $WORKSPACES_STAGING"`), never the bare `^rm ` idiom T4c uses.
- **A gate-resolution truth table cannot catch mode-reachability bugs.** In v1's P0-1 the
  gate resolved *correctly* and the script then did the *wrong thing*. Assert a defined
  script-side outcome per input combination, not just a gate branch.
- **`bash -n` on a workflow `.yml` parses YAML as bash.** Use `actionlint` for the YAML
  and `bash -n` only on extracted `run:` bodies.
- **awk `/start/,/end/` ranges self-match on the start line** — AC6's section extraction
  must use the flag-based form.
- **A `## Addendum (2026-07-19)` heading already exists in ADR-119.** Any AC anchoring on
  that prefix alone self-satisfies before a single edit.
- **`rm -rf "$STAGING"/*` misses dotfiles.** A workspace tree is full of them; the guard
  correctly keeps firing after the "successful" run, and the remaining stray is now a
  strict subset that behaves differently on retry.

---

## Downtime & Cutover (deepen-plan Phase 4.55)

**Trigger evaluated: does not fire — but the near-miss is worth recording.**

- **Infra reboot/replace class** — not triggered. No `hcloud_server` attribute changes, no
  `server_type`/`location`/`placement_group_id` edit, no `-/+` replace. No Terraform root
  is touched at all.
- **Database lock class** — not triggered. No migration, no DDL, no backfill.
- **Deploy/router class** — not triggered. `clean_stray()` performs no `umount`, no
  `cryptsetup close`, no `docker stop`, and no `systemctl` action. It deletes contents of
  a directory on the **root filesystem** that no service, mount, or container references.
  `$MOUNT` is untouched by construction, and FR5 refuses if `$STAGING` resolves to the
  same device.

**Zero-downtime by construction**, therefore, with one important qualification: the
*plan's own P0-1 defect class* was a downtime bug. `rollback=true` + `clean_stray=true`
would have executed `rollback()` — `umount "$MOUNT"`, `cryptsetup close`, `docker stop`,
`resume_writers` — on a host where no freeze was held, which the script's own
`_PREPARE_ABORT_NOTE` describes as "a gratuitous outage." D1c's mutual exclusion is
therefore not merely a correctness fix; it is the availability control for this change.
FR2, FR11 and T4h are the mechanisms; there is no residual downtime to justify and no
maintenance window is required.

One operational note, not a change this plan makes: the workflow's
`concurrency: web-1-swap` group is `cancel-in-progress: false`, so an in-flight wedged
cutover run can block the very remediation that unwedges it. Worth knowing at dispatch
time.

---

## Precedent Diff (deepen-plan Phase 4.4)

Pattern-bound behaviors in this plan and their in-repo precedents:

| Pattern | Precedent | Conformance |
|---|---|---|
| Operator-entrypoint mode block | `ROLLBACK=1` block in `workspaces-cutover.sh` (after `trap cleanup EXIT`, before the L3 gates, ends `exit 0`) | **Conforms in shape, deliberately diverges in two places**, both documented: (a) it does **not** force `DRY_RUN=0` — it refuses instead (FR3), because forcing is what makes ROLLBACK's ungated arm dangerous; (b) it sits behind a mutual-exclusion guard (FR2), because ROLLBACK's `exit 0` would otherwise render it unreachable. |
| Emit marker + `emit_drift` before `die` | `emit_staging_target` / `emit_freeze_holders` — bare `echo` at column 0 plus `logger -t "$LUKS_LOG_TAG"`, `_vscrub` on every interpolated value, marker emitted **before** `die` so evidence survives (T2c) | Conforms. FR7 uses the same shape under a **new** marker name (`SOLEUR_WORKSPACES_LUKS_CLEAN_STRAY`) rather than overloading `SOLEUR_WORKSPACES_LUKS_STAGING_TARGET`, whose `result=`/`reason=` vocabulary is pinned by the T-series and the `record_arm` coverage matrix. |
| Device-identity assertion before a destructive act | `_same_dev()` + `[ -b … ]` guards used before `luksFormat`/`mkfs` | Conforms. FR5 reuses `_same_dev` directly; deepen-plan confirmed it fails closed on empty args and on a non-block second argument. |
| Idempotent re-dispatch on a recovery path | `rollback()`'s mapper guard — "a recovery-path signal that cries wolf gets ignored" | Conforms. FR4's `already_clean` + `exit 0` on an empty `$STAGING` applies the same principle. |
| Magnitude in the operator message | the stray guard's own `stray_bytes` / `stray_entries` (`du -s --block-size=1`, `find -mindepth 1 -maxdepth 1 -printf`) | Conforms — FR7 reuses the identical probe form, which is also already proven tolerable on a many-GB tree since the guard runs it on every dispatch. |

**Scheduled-work pattern check:** N/A — this plan introduces no scheduled job. The
workflow remains `workflow_dispatch`-only.

**Novel pattern (no precedent):** the top-level subset check (FR6). No sibling in this
repo performs a name-level subset assertion before a delete. Flagged for reviewer
scrutiny — this is deliberate, since the precedent that *did* exist
(`verify_byte_identity`) was falsified as unusable for this predicate (D3).

---

## Verify-the-Negative Sweep (deepen-plan Phase 4.45)

15 negative/structural claims probed against the code. **14 CONFIRM, 1 CONTRADICTS.**

Confirmed: `verify_byte_identity` hardcodes `--delete` (`:226`), counts `*deleting`
(`:242`), and `die()`s rather than returning (`:237`, `:246`); `emit_verify_diff` emits
one row per differing path capped at `VERIFY_DIFF_CAP` (`:192`, `:209`); the ROLLBACK
block ends `exit 0` (`:941-944`); the harness `rm` is a passthrough recorder
(`workspaces-luks-harness.sh:214`); `dry_run`/`rollback` are `type: boolean`
(`:46`, `:52`); `principles-register.md` contains neither "Deviation" nor "ADR-055";
ADR-055 carries the exact literal `AP-009 (Never delete user data): Deviation` (`:171`);
ADR-119 has exactly three `## Addendum` headings, one already prefixed
`## Addendum (2026-07-19)`; `_same_dev` fails closed (`:701-707`); the guard's magnitude
probe uses the cited `du`/`find` forms (`:753`, `:756`); T4c's `run_case` invokes only
`prepare_staging_target` (`:154-158`); the `BASH_SOURCE` guard is at `:933` with the
ROLLBACK block after it.

**Contradiction found and fixed:** the plan claimed **three** functional `inputs.dry_run`
positions in the workflow. There are **four** — the `Cutover summary` step's
`DRY: ${{ inputs.dry_run }}` at `:305` was missed. D1b and FR14 are corrected above; FR17
already covered the remedy, so the fix was a counting error in the prose, not a gap in
the deliverable. Recorded because "N call sites" claims in this plan are load-bearing and
this one was wrong on first pass.

---

## Enhancement Summary

**Deepened on:** 2026-07-19
**Rounds:** plan v1 → 3-agent review → v2 → deepen-plan gates → v2.1

### Gate results

| Gate | Result |
|---|---|
| 4.4 Precedent diff | Recorded above — 5 conforming patterns, 1 novel (flagged) |
| 4.45 Verify-the-negative | 14 CONFIRM / 1 CONTRADICTS (fixed) |
| 4.5 Network-outage deep-dive | Not triggered — no SSH/connectivity symptom in the problem statement |
| 4.55 Downtime & cutover | Evaluated; does not fire. Zero-downtime by construction |
| 4.6 User-Brand Impact | PASS — section present, threshold `single-user incident` |
| 4.7 Observability | PASS — all 5 fields present, no placeholders, no `ssh` in `discoverability_test` |
| 4.8 PAT-shaped variable | PASS — no matches |
| 4.9 UI wireframe | Skipped — no UI surface in Files to Edit/Create |
| Rule-ID citations | 2/2 resolve to active `[id: …]` entries in AGENTS.md |
| KB path citations | 1/1 resolves on disk |

### Key improvements over v1

1. **The redundancy proof was falsified and replaced.** v1's reuse of
   `verify_byte_identity()` would have refused on every real invocation, making the
   plan's own goal unreachable. Replaced with a top-level subset check (D3).
2. **A silent mode-swallowing bug was caught.** `rollback` + `clean_stray` would have run
   a rollback — a gratuitous outage — while reporting green and skipping the deletion
   (D1c).
3. **The approver, not just the dispatcher, now sees the AP-009 deviation.** The
   probe/delete job split puts magnitude and the deviation banner in the step summary
   *before* the approval gate (D6).
4. **Two more `dry_run`-as-mode proxies were found** beyond the `environment:` expression
   — the loopback gate and the Hetzner volume lookup — plus a fourth occurrence in the
   summary step found by the verify-the-negative sweep (D1b).
5. **The `principles-register.md` edit was dropped** after verifying the register has no
   deviations column and no ADR-055 reference; the established convention is that
   deviations live in ADRs (D5).

### Residual risks for the implementer

- The subset check (FR6) is a novel pattern with no in-repo precedent — scrutinize.
- New tests must NOT mirror T4c's bare `^rm ` assertion idiom; the harness records every
  `rm`. Scope to `$STAGING`.
- AC6 must anchor on the new addendum heading's full text; a `## Addendum (2026-07-19)`
  heading already exists and would self-satisfy a prefix match.
