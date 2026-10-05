# Decision Challenges — feat-one-shot-7264-git-data-boot-diagnostics-t1-t4

Recorded per ADR-084. These challenge the operator's **stated direction**, so they were
surfaced rather than applied.

## Resolutions — operator ruled 2026-08-11, all three RESOLVED

| # | Challenge | Ruling |
|---|---|---|
| **UC-A** | T-3 not buildable as specified | **Option (a) — narrow to the real defect.** Add the mirrored non-vacuity assert to `runcmd-all.code.sh`; no shared bash library. |
| **UC-B** | T-4 delivers T-1's stated deliverable | **Option (a) — re-scope T-1 as a second-channel fallback.** See the interaction note below. |
| **UC-C** | Panel split on the PR cut line | **Split T-4 out.** PR 1 = T-2 + T-3 + T-1; PR 2 = T-4, gated on the Doppler residency check. |

**Interaction between UC-B and UC-C, resolved in the plan.** Because UC-C moves T-4 to a
follow-up PR, T-1 is **not** redundant in PR 1: with T-4 absent, the five parent-shell stages
still reach Sentry only, so T-1 is the *primary* fix for #7116. It becomes the second channel
once T-4 lands. The plan therefore places the Sentry arm at **both** the `boot_complete`-missing
branch (the #7116 fix) and the two TRANSIENT exit paths (the Better-Stack-unreachable case).

A second consequence: with T-4 deferred, PR 1 carries **no new ADR ordinal** — only an ADR-152
addendum — so the 177/178 collision risk does not apply to it.

---

## UC-A — T-3 is not buildable as specified, and its stated rationale does not hold

**decisionClass:** user-challenge
**Raised by:** dhh-rails-reviewer, code-simplicity-reviewer (independently, same scope)
**Status:** OPEN — awaiting operator decision

**Operator's stated direction.** "T-3 FIRST — extract a shared comment-stripped render
slicer. Create `tests/scripts/lib/git-data-render-slice.sh` exposing
`_render_code_slice <stage|all>` (~30 lines). It replaces the THIRD independent
re-implementation … Source it from both suites. Doing this first makes T-2 a one-line
migration, not a three-file one."

**Measured finding.** Two of the three cited call sites are **not bash**.
`apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh:105-123` sits inside a
`python3 <<PY … PY` heredoc (terminator at `:124`); `luks-stage.code.sh` and
`runcmd-all.code.sh` are Python list comprehensions over `d["runcmd"]`, already parsed in
memory, whose entire duplicated logic is `re.match(r'^\s*#', l)`. A bash library cannot be
sourced from inside a Python heredoc. Migrating them would require writing entries to disk,
shelling out to the library, and reading results back — strictly worse than the one-liner.

Only `_luks_slice` (`git-data-luks.test.sh:76-79`, 4 lines) and `_b2_strip`
(`rehearsal:439`, one `sed`) are real bash consumers, and the plan explicitly leaves
`_b2_strip` alone. So the shared surface is **one** 4-line function, and the library was
specified to carry six configuration axes (marker-pair extraction, single-entry selection
with cardinality assert, whole-list concatenation, two strip modes, optional `#!` exemption,
non-vacuity probe) to preserve differences it was created to remove.

The sequencing rationale also does not hold: T-2's edit set is
`modules/git-data-userdata/main.tf` + `git-data-userdata-budget.sh` + an ADR. It touches no
slicer, so T-3 does not make T-2 "a one-line migration".

**What the defect actually is.** `luks-stage.code.sh` carries
`assert "mkfs.ext4" in _code`; `runcmd-all.code.sh` carries no non-vacuity assert at all, so
an empty slice would let its four arms (R3(3b), R3(3c), R3(3d), R3(2d)) pass vacuously. That
is a real, narrow defect worth fixing.

**Options.**
- **(a) Narrow T-3 to the real defect** *(recommended by both reviewers)* — add the mirrored
  non-vacuity assert to `runcmd-all.code.sh`; skip the library. Cost: ~2 lines.
- **(b) Build the library for `_luks_slice` only** — honest but thin: one caller, no sharing.
- **(c) Build as directed** — requires the Python sites to shell out to bash; the reviewers
  judge this strictly worse than the status quo.

**Additional, independent of the above:** code-simplicity recommends **swapping T-2 before
T-3**, because once T-2 lands the rehearsal's render arrives comment-free and the strip
parameter inside the B/C slicers becomes inert. Extracting after T-2 means the library is
derived from the inputs that will actually exist.

---

## UC-B — T-4 already delivers T-1's stated deliverable; T-1 needs re-scoping, not re-ordering

**decisionClass:** user-challenge
**Raised by:** spec-flow-analyzer (P0-1)
**Status:** OPEN — awaiting operator decision

**Operator's stated direction.** "T-1 … Converts TRANSIENT to FAIL for most of the surface
and protects the two-dispatch cap. Should let #7116 close."

**Measured finding.** After T-4 bakes the Better Stack token, the emitter reaches Better
Stack unconditionally, so a fatal at any of the five parent-shell stages lands in `host_out`
and the **existing** FAIL arm at `git-data-rung2-evidence-capture.sh:298` fires. The plan
concedes this in its own AC9 ("no new reader code in the capture script for those stages").
So T-1's stated deliverable — converting TRANSIENT to FAIL for those five stages — is
performed by T-4, one phase earlier.

This is not a correctness contradiction; it is an ordering-induced redundancy in the
*rationale*. T-1 retains real, distinct value, but it is a different value than stated:
**a second channel for the case T-4 cannot cover — Better Stack itself unreachable.**

**Consequence if not re-scoped.** As written, T-1's arm would be placed at the
`boot_complete`-missing branch (`:306`), but the two paths where Sentry is the only surviving
channel — transport rc≠0 (`:252`) and zero-row anchor (`:271`) — both exit **before**
`host_out` is queried. T-1 would therefore be unreachable in precisely the situation that is
its only residual justification.

**Options.**
- **(a) Re-scope T-1 as a second-channel fallback** *(recommended)* — place the Sentry arm on
  the two TRANSIENT exit paths, rewrite the Overview and AC12 accordingly, and attribute the
  five-stage conversion to T-4.
- **(b) Ship T-1 before T-4** — then T-1 genuinely performs the conversion and T-4 becomes the
  redundant one. Contradicts the operator's stated dependency order.
- **(c) Drop T-1** — leaves no coverage when Better Stack is unreachable.

Whether this still closes #7116 depends on the choice: under (a), #7116 is closed by T-4 with
T-1 hardening it.

---

## UC-C — the panel disagrees with the operator's proposed split line

**decisionClass:** user-challenge
**Raised by:** dhh-rails-reviewer vs. soleur:engineering:cto (they disagree with each other)
**Status:** OPEN — awaiting operator decision

The operator asked to be told rather than assumed-for. The panel did not converge:

- **DHH:** split **T-1** out. T-2 is the change that can boot a host dark; do not put a Sentry
  query arm in the same diff as a cloud-init header near-miss.
- **CTO:** split **T-4** out — it carries the only security surface, the only ADR reversal,
  and a merge-blocking Doppler write (AC10) with a "stop and re-scope" trapdoor at Phase 3
  step 1. If residency fails mid-PR, the already-green T-2/T-3 stall behind it. The CTO notes
  T-2 alone touches `main.tf`, so the infra apply fires either way.

**Options.** (a) one PR; (b) split T-1 (DHH); (c) split T-4 (CTO); (d) T-2+T-3 first, then
T-4, then T-1. If one PR is kept, the CTO recommends running Phase 3 step 1 (residency check)
**before** Phase 1 so the trapdoor fires at zero sunk cost.
