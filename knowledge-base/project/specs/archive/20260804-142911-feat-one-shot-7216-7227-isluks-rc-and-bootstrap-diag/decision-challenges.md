# Decision Challenges — feat-one-shot-7216-7227-isluks-rc-and-bootstrap-diag

Surfaced by `/soleur:plan-review` (6-agent panel) on 2026-08-03. Recorded here because the
session is headless (one-shot pipeline, plan invoked inside a Task subagent), so these were NOT
auto-applied. `ship` Phase 6 renders this file into the PR body and files an `action-required`
issue.

---

## UC-1 — User-Challenge: the batching rationale is factually wrong for 4 of the 7 files

**Operator's stated direction:** "Fix #7216 and #7227 together in one PR — both harden
`apps/web-platform/infra/cloud-init-git-data.yml` and its file()-bound payloads, and every edit
to those files re-hashes RUNG2_TEMPLATE_SHA256, so they must land as a single template change
before the rung-2 rehearsal is dispatched (spend cap: two paid dispatches)."

**What two reviewers independently found** (dhh-rails-reviewer P0; code-simplicity-reviewer #7):
the stated *reason* does not hold for most of the diff. `git_data_rung2_user_data_sha256`
(`tests/scripts/lib/git-data-birth-readiness-gate.sh`) hashes the template, the
`modules/git-data-userdata/*.tf` files, and the nine `file()`-bound payloads. Of the plan's seven
files to edit, **four are in none of those sets**:

- `scripts/followthroughs/git-data-rung2-evidence-capture.sh`
- `tests/scripts/test-git-data-rung2-evidence-capture.sh`
- `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`
- `.github/workflows/infra-validation.yml`

Verified: none of those paths is reachable from `_payload_refs()` or the module `*.tf` glob.
So **#7227 item 4 has zero paid-dispatch coupling to #7216.** It carries 4 of 7 files, 2 of the
floor raises, and ACs 8-10 — roughly 40% of the review surface of a PR whose other half decides
whether a live encrypted store gets reformatted.

**The challenge:** split into PR-A (hash-coupled: the template + its two guards, one dispatch)
and PR-B (hash-neutral: the capture script, its test, the rehearsal guard, the CI path filter —
ships any time, costs nothing).

**Disposition taken in the plan: NOT applied. The plan stays one PR, per the operator's explicit
direction.** The operator's stated direction is the default (ADR-084), and "one PR" was an
instruction, not an inference. What the plan DID change is the *rationale*: the Overview now says
the batching is (a) hash-coupled for files 1-3 and (b) a deliberate operator choice for files
4-7, rather than claiming the hash forces all seven.

**What the operator should decide:** whether to keep the single PR (simpler to track, one review,
one merge) or take the split (sharper review attention on the store-destroying defect, and PR-B
can merge immediately without waiting on the paid rehearsal). Either is defensible; the plan is
written so the split is a clean cut along Phase boundaries if wanted — PR-B = Phases 1.3, 1.4,
3.3, 3.4, 4 and ACs 8-10.

---

## T-1 — Taste: give the evidence-capture script a Sentry arm (closes the #7116 mis-report)

**Source:** cto (F1, rated HIGH).

The plan's `## Observability` section originally claimed "the rung-2 rehearsal workflow fails its
job on any `level:fatal` for the rehearsal `host_name`." **That is false for every stage this
plan improves.** Verified chain:

1. The emitter's Better Stack block is gated on `BETTERSTACK_LOGS_TOKEN`, which only exists
   under `doppler run`. Parent-shell fatals therefore reach **Sentry only**.
2. `scripts/followthroughs/git-data-rung2-evidence-capture.sh` issues **zero** Sentry queries —
   it polls Better Stack SQL exclusively (its own header declines the capability:
   "scripts/sentry-issue.sh is id-shaped; the API is not").
3. So for `gitdata_runcmd_early`, `sshd_config`, `volume_mount`, `gitdata_doppler_dl` and
   `gc_timer`, the capture script returns **TRANSIENT, not FAIL** — which is issue **#7116**,
   already OPEN, and named in `git-data-rung2-rehearsal.yml` as a documented dispatch-burner
   ("attempt 1 of run 30649892865 was that mis-report, one attempt before the real FAIL").

**Applied to the plan:** the false Observability claim is corrected and #7116 is cited (that part
is mechanical). **Not applied:** adding the Sentry arm itself. `scripts/sentry-issue.sh` already
ships with a read-only `SENTRY_ISSUE_RO_TOKEN` in Doppler `soleur/prd`, so the capability exists
and the blocker is tooling shape, not API access — but building it is scope the operator did not
request, and it would grow the hash-neutral half of an already-large PR.

**Recommendation:** worth doing, and it is the highest-leverage item any reviewer raised — it
converts TRANSIENT→FAIL for the majority of the surface this PR touches, which directly protects
the two-dispatch cap. Suggest filing against #7116 and doing it BEFORE the rehearsal dispatch.

---

## T-2 — Taste: extend the render-strip contract to the template body (~14 kB recovered)

**Source:** cto (F2), measured.

`git_data_rationale_strip` in `modules/git-data-userdata/main.tf` is applied only to the nine
`file()`-bound payloads, never to the `templatefile()` body. Measured by the reviewer:

```
cloud-init-git-data.yml raw            : 37,363 B
  of which full-line comments          : 24,340 B  (65%)
stored contribution (gzip + base64)    : 19,292 B
same, with comments stripped           :  5,168 B   -> ~14,124 B recovered
```

That would take headroom from 6,800 B to ~20,900 B. Hazard survey came back clean (one `#!` line
at the emitter's shebang, already protected by the existing `[^!\n]` guard).

**Not applied.** Putting a byte optimisation on the same paid dispatch as a store-destroying-bug
fix risks burning dispatch #2 on something cosmetic.

**The sequencing note IS applied to the plan's Sharp Edges:** because this PR already re-hashes
`RUNG2_TEMPLATE_SHA256`, a strip PR merged **before** any dispatch costs **zero** marginal
dispatches — one rehearsal attests the final template. It is sequencing, not batching, that makes
it free. Needs an ADR (it extends ADR-152's strip contract to a new input class and changes what
`git-data-render-strip-parity.test.sh` compares).

---

## T-3 — Taste: extract a shared comment-stripped render slicer

**Source:** cto (F3), echoed by code-simplicity-reviewer.

Phase 3.2's `runcmd-all.code.sh` is the **third** independent re-implementation of "extract the
render, strip comments, classify sites" — after `_luks_slice` (`git-data-luks.test.sh`) and
`luks-stage.code.sh` (`git-data-runcmd-rehearsal.test.sh`). The plan's own Sharp Edges warns that
every new predicate must *remember* to read the stripped form. That is a shared-helper problem,
not a discipline problem.

**Not applied** (scope). Suggested shape: `tests/scripts/lib/git-data-render-slice.sh` exposing
`_render_code_slice <stage|all>`, ~30 lines, sourced by both suites. Building it before T-2 would
make T-2's migration a one-line change instead of a three-file one.

---

## T-4 — Taste: bake the Better Stack ingest token so one reader covers all stages

**Source:** cto (F5).

"Boot-stage diagnostics on a host you cannot reach" has been built three times here (Sentry baked
DSN, Better Stack child channel, Better-Stack-polling capture script) with a fourth still missing
(#7116). The generic shape is one sink, one reader; this is two sinks and a reader for one of
them — and that split is the root cause of both T-1 and #7116.

**Not applied.** Baking the Better Stack token the way `sentry_dsn` is already baked would let
the parent shell reach both sinks and let the *existing* reader cover all nine stages with zero
new reader code. Costs a second baked credential in `user_data` (a real security trade) plus
bytes — which is precisely what T-2's recovered 14 kB would fund. Needs an ADR (it changes the
emitter's channel-split contract, ADR-147 territory).
