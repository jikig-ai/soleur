# Decision Challenges — feat-one-shot-git-data-rung2-boot-evidence

Recorded headless per ADR-084. These are points where the plan-review panel and the planning
session agree that the **stated direction** should change. The stated direction is the default
and was kept; these are surfaced for a decision rather than applied.

## DC-1 — `--window '7 DAY'` versus the script's own `30 DAY` default

**Stated direction.** The brief prescribes the capture invocation verbatim, including
`--window '7 DAY'`.

**The challenge.** Three of five reviewers independently flagged this. The rehearsal ran
2026-09-04; the capture runs 2026-09-09. `7 DAY` clears it by roughly two days. The capture's
own default is `30 DAY` (`WINDOW="30 DAY"` in
`scripts/followthroughs/git-data-rung2-evidence-capture.sh`). Because re-dispatch is forbidden
and widening is free, starting at `30 DAY` would remove the margin, and with it the TRANSIENT
row, the Research Reconciliation row and the Risks bullet the plan currently spends on managing
a two-day gap it created. DHH's framing: "You manufactured a problem and then wrote three
mitigations for it."

**Kept as briefed.** The brief is explicit that the plan must specify this command, and it
already names widening as the remedy. The plan therefore uses `7 DAY` on the first attempt and
documents the ladder (`30 DAY`, then `2 MONTH`) with a floor.

**Decision wanted.** Change the first attempt to `--window '30 DAY'`? It is one token and would
delete three paragraphs of contingency. Nothing else in the plan depends on the value.

## DC-2 — `--out` is strictly worse than omitting it

**Stated direction.** The brief prescribes
`--out apps/web-platform/infra/git-data-rung2-boot-evidence.env`.

**The challenge.** Kieran's finding, verified: the capture defaults `OUT` to
`$(dirname "$CLOUD_INIT")/git-data-rung2-boot-evidence.env`, and `CLOUD_INIT` defaults to
`$REPO_ROOT/apps/web-platform/infra/cloud-init-git-data.yml` where `REPO_ROOT` is derived from
`BASH_SOURCE` — an **absolute** path that resolves correctly from any working directory. The
explicit relative `--out` is the only reason the plan needs a working-directory precondition at
all. Omitting the flag removes a whole class of silent failure (a run from the wrong directory
writes the file somewhere the gate will not look, and the gate then reports HOLD for a reason
unrelated to the evidence).

**Kept as briefed.** The plan keeps `--out` and hardens the precondition into a mechanical
`git rev-parse --show-toplevel` check instead.

**Decision wanted.** Drop `--out` entirely? The default resolves to the identical path.

## Not challenges — applied directly

For the record, the following plan-review findings were mechanical and were applied without
asking: the one-argument gate invocation (mirroring CI), the full exit-path routing table
(rc=2 splits into TRANSIENT and DERIVATION FAULT; rc=78 and the no-sentinel-line case added),
the `CLEAN`-only cross-check rule, `git fetch origin main` before AC2/AC4, the widened AC4
filter, the `if !` form in AC2, `gitleaks` named explicitly in AC5, AC6 encoded as a command,
the divergence set re-derived from `rehearsal.tf` rather than from the gate's allowlist, the
push/CI/post-merge phases, the CPO sign-off step, and the disclosure that this plan does not
follow the runbook's `## After a PASS` artifact-download sequence.

## Review-time: three measured gate defects, deferred to a follow-up PR (not filed)

Found by `pattern-recognition-specialist` at review, all reproduced on HEAD. The CONCUR gate
(`code-simplicity-reviewer`) **DISSENTed** on filing them as a bundled scope-out, and the dissent
was correct on four counts. Recorded here rather than as an issue, so the disposition survives the
session without adding backlog. **Net issue flow for this PR: 0 filed, 0 closed.**

**(b) The exactly-once arm enumerates decorations instead of anchoring.**
`git_data_rung2_rehearsal_gate` counts `^[[:space:]]*(export[[:space:]]+)?KEY[[:space:]]*=`. It
knows `export` and not `declare`/`typeset`/`readonly`/`local`. Measured: a file carrying
`RUNG2_BOOT_REHEARSAL=PASS` plus `declare RUNG2_BOOT_REHEARSAL=FAIL` counts 1 and RELEASES, while
`source` sees `FAIL` — verbatim the divergence-of-meaning that block exists to prevent.
Fix (validated by the dissent): `(^|[[:space:]])`. Enumerating known shapes is what produced the
bug; the in-code comment claiming the tested shapes are exhaustive is provably wrong.

**(c) Nothing asserts the freshness step still exists.**
`git-data-rung2-rehearsal.test.sh` reads `infra-validation.yml` only to parse its `paths:` filter.
Deleting the `Rung-2 evidence freshness` step is caught by nothing — and because that job is not a
required check (already tracked at #6766), its disappearance produces no signal at all.

**(a) The gate's predicate is narrower than its name.** It asserts *a well-formed, template-bound
assertion exists*, not *a rehearsal passed*. `RUNG2_SENTRY_CROSSCHECK` is written by the capture and
read by no gate, while this branch's own `tasks.md` 2.6 makes `CLEAN` an acceptance criterion — i.e.
enforced by human eyeball.

**A premise I asserted and did not check, corrected by the dissent.** I claimed the cheap half of
(a) would require regenerating the evidence file and voiding its capture provenance. False: the
host name is already at line 8 and inside all four embedded queries, and the URL already ends in the
same run id — measured, `33888071954` on both sides. `rehearsal.tf` builds the host name FROM the
run id, so the two strings are already coupled and a gate-side equality is available at zero
evidence-file cost.

*Open design question the follow-up must settle, not skip:* that host name lives in a **comment**,
and the gate strips comments before reading precisely so comments are never load-bearing. Asserting
on it either reverses that decision (read raw text) or promotes it to a key (which does need a
regeneration). Decide deliberately.

**Disposition (accepted from the DISSENT).** (b), (c), and the zero-cost half of (a) go into one
gate-side follow-up PR opened immediately after this merges — no evidence-file change, no
regeneration. The operator constrained *this PR's diff*, not the session, so a follow-up PR honours
the constraint literally without creating backlog. Only the expensive half of (a) — CI `gh api` run
resolution plus promoting `RUNG2_SENTRY_CROSSCHECK` to a gate-required key — would be worth filing
alone, as `architectural-pivot` on the evidence format, and its trigger must be *"before the next
git-data birth dispatch is armed"*, linked as a **blocker on** #7025.

**Why not "dependency on #7025" as the trigger:** it is circular. The gate *is* the mechanism that
holds the birth dispatch, so parking a fail-open hole in the hold behind the thing the hold guards
means the holed gate is exactly what lets the dispatch through. That trigger cannot fire on its own.
