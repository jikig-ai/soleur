# Verification evidence — #7138

Issue #7138 sets an unusual bar: *"Verified by executing the condition, not by reading the
YAML."* This file is that evidence. Nothing below is an assertion about what the code should
do; every line is a recorded output.

## 1. Execution on GitHub's own expression evaluator (issue AC2)

A GitHub `if:` expression cannot be evaluated off-platform. `act` is a *reimplementation* of
the evaluator (and is absent from this repo and machine), so a green `act` run would prove
act's semantics, not GitHub's. The conditions were therefore executed on GitHub.

- **Run:** <https://github.com/jikig-ai/soleur/actions/runs/30710703476>
- **Event:** `pull_request` — a new workflow added by this PR *does* run on the PR that adds
  it, given its own path in the `paths:` filter (the `gdpr-gate-self-test.yml` shape).
- **Head SHA:** `8e5a052a98ddcd622da3f84f14cd0cb4dc54b8a9`
- **Run conclusion:** `success`
- **Workflow:** `.github/workflows/release-outcome-condition-harness.yml`, whose `email` and
  `mirror` stand-in steps carried **verbatim copies** of the shipped `if:` strings.

> **That workflow file is deleted in this branch and is NOT part of the merged diff.** It
> existed for commits `8e5a052a9..1b9e62c16` so the run above could happen. A permanent,
> deliberately-red, non-required check is the exact shape of the bug `bf4816455` fixed on main
> four commits before this one, so keeping it would have re-introduced that shape — and its
> two by-design-failing arms rendered as red PR checks for exactly as long as it existed. The
> **run** is immutable and remains readable at the URL above; the **durable** guard is
> B1c/B1d/B1e inside the required `test` check.
>
> `git diff 8e5a052a9 -- .github/workflows/web-platform-release.yml` is **empty**, so the
> strings the harness executed are byte-for-byte the strings being merged. That check is what
> makes this evidence transferable; without it the run would attest to a string that no longer
> ships.

### Observed step conclusions — `gh run view 30710703476 --json jobs`

```
probe-A	classify	failure
probe-A	email	success
probe-A	mirror	skipped
probe-B	classify	failure
probe-B	email	success
probe-B	mirror	success
probe-C	classify	success
probe-C	email	skipped
probe-C	mirror	skipped
```

This matches the expected table row-for-row; the `verdict` job asserts it in-run and was
`success`.

| arm | scenario | what it proves |
|---|---|---|
| A | classifier dies, email delivers | the classifier's death alerts the operator, and the mirror **stands down** because the email worked — the two-channel design is preserved |
| B | classifier dies, email does not deliver | the compensating channel **still fires** — this is the #7138 fix |
| C | healthy release, `failed=''` | **negative control** — both channels stay silent |

**Why arm C is the load-bearing row.** A lazy `if: always()` "fix" passes A and B and *fails*
C, because `always()` cannot produce a `skipped` row. Without C the harness could not tell the
correct fix from the lazy one. (Plan revision R11 cut the separate `always()` mutation push:
it would have required opening a throwaway PR, which fires the paid `claude-code-review.yml`.
Arm C's recorded `skipped` already carries the discrimination.)

## 2. Two open questions the plan flagged as "record, do not assume"

**(a) Does GitHub set a declared `env:` key whose expression resolves to empty?** The plan's
first draft claimed the unguarded `${FAILED}` would *crash* the mirror step under `set -u`.
The issue said the opposite. Measured, from arm B's `mirror` step log:

```
FAILED_IS=SET value=''
```

**Set-and-empty, not unset.** `set -u` does not fire. The `${FAILED:-}` guards in this PR are
therefore a consistency change matching every sibling expansion in the step — **not** a crash
fix, and the PR does not claim to be one.

**(b) What does job-level `continue-on-error: true` do?** It has zero precedent in this repo's
70 workflows, so it was observed rather than assumed:

```
probe-A	failure     <- JOB conclusion
probe-B	failure
probe-C	success
verdict	success
run     success     <- RUN conclusion
```

The failing arms redden their **jobs** while the **run** stays green. Two consequences:
`steps.outcome.conclusion` still reports `failure` (arms A/B could not otherwise have run
their email step at all), and — materially — the production `workflow_run` →
`engineering.ci_failed` webhook in `apps/web-platform/app/api/webhooks/github/route.ts` is
gated on `conclusion === "failure"` at the **run** level, so this harness did **not** spawn a
leader agent. That ingress was unenumerated in the plan's first draft (R36).

## 3. Mutation battery — every new assertion seen RED

An assertion never seen red pins nothing. Each mutation was applied to a pristine tree, the
suite run, and the tree restored. **10 mutations, 10 RED, zero survivors.**

| # | mutation | assertions that went RED |
|---|---|---|
| 1 | mirror condition reverted to the #7138 bug | B1c |
| 2 | email condition reverted to the #7138 bug | B1d |
| 3 | `continue-on-error: true` added to the classify step | B1e |
| 4 | `id: mirror` renamed | selector precondition + B1b + B1c + B1d + B1e + M0 |
| 5 | mirror blames the release on a classifier death | M1c, M1e |
| 6 | email third headline removed | B6a, B6b |
| 7 | unconditional closing urgency line restored | B6b |
| 8 | `What stopped` list un-guarded (empty `<ul></ul>`) | B6c |
| 9 | curl stub scans argv for `-d` only | M1b, M1c, M1d, M2a |
| 10 | `run_mirror` env omits `GITHUB_STEP_SUMMARY` | M1a, M1b, M1c, M1d, M1e, M2a |

Mutations 9 and 10 are the ones worth reading twice. They are not tests of the product — they
are tests of the **harness**, and both were defects the plan review caught before any mirror
arm was written:

- **9** — the shipped mirror posts with `--data`; the pre-existing stub captured only `-d`.
  Had it shipped unfixed, four payload assertions would have been **vacuous**, and any
  "no payload was captured" assertion would have passed for every arm, forever.
- **10** — the mirror body writes to `$GITHUB_STEP_SUMMARY`. An env omitting it aborts with
  `GITHUB_STEP_SUMMARY: unbound variable` — *literally the string M1a asserts must be absent*,
  i.e. a false RED that looks exactly like the bug under test.

Mutation 4 is the `cq-assert-anchor-not-bare-token` case: B1e is a **negative** assertion
("the classify step declares no `continue-on-error`"). Selected loosely, a step-id rename
matches nothing, "not found" reads as PASS, and — because both widened conditions key on
`steps.outcome.*` — that rename would silently restore #7138 with every test green. Every
selector now asserts exactly-one cardinality and fails loudly instead.

## 4. The plan's central premise was measured FALSE

The plan justified widening the **email** step on the claim that *"the Sentry mirror pages
nobody"* — that all 29 `sentry_issue_alert` rules in `issue-alerts.tf` are tag-filtered and
none matches `gate:release-outcome`. Plan revision R34 flagged the claim as only partly
established and required verification against the live rules API before Phase 2 was written.

Pulled 2026-08-01 from `GET /api/0/projects/jikigai-eu/web-platform/rules/`:

- **30 live rules, not 29.** The 30th is absent from Terraform:

```json
{
  "name": "Send a notification for high priority issues",
  "conditions": [
    {"id": "...high_priority_issue.NewHighPriorityIssueCondition"},
    {"id": "...high_priority_issue.ExistingHighPriorityIssueCondition"}
  ],
  "filters": [],
  "environment": null,
  "actions": ["sentry.mail.actions.NotifyEmailAction"]
}
```

`filters: []` and `environment: null` mean it matches **any** issue Sentry marks high
priority, in every environment. Sentry derives high priority from `level`, and the mirror
POSTs `level:"error"`. **The mirror does page the operator.** The premise is false.

Consequences, all applied:

1. **DC-1's stated justification is withdrawn.** Phase 2 (widening the email) now rests on the
   argument plan revision R35 supplied independently, which the repo *does* substantiate:
   `release-outcome` is the only alert channel that fires **regardless of which job in the
   release graph failed**. The three other push channels (`deploy`'s inline email,
   `reusable-release.yml`'s `notify-ops-email`, the `notify-gated` Slack post) are all
   job-scoped and structurally silent for a failure outside their own job. That argument
   survives either answer to R34. The secondary argument also holds: a raw Sentry
   high-priority notification is not the plain-language email a non-technical operator can act
   on.
2. **The Phase 7 tracking issue is re-scoped** and filed as **#7142**. It no longer claims
   the event reaches nobody — it records that the only rule routing it is **UI-managed and
   absent from IaC**, which is what ADR-031 and ADR-117 actually care about.
3. **`model.c4` is corrected** rather than edited past: `sentry -> founder` carried a stale
   *"21 of the 22 rules"* (actual: 29 IaC rules, 2 `NoOne` — `byok_cap_exceeded` and
   `byok_art_33_breach`) and omitted the un-codified 30th rule entirely.

This is recorded at length because the falsified premise was the stated basis for a scope
deviation. The deviation still stands; its justification does not.

## 5. Local gates

| gate | result |
|---|---|
| `bash scripts/lint-workflow-step-env-refs.test.sh` | `All tests passed` — 48/48 |
| `python3 scripts/lint-workflow-step-env-refs.py` | `0 findings across 71 workflow file(s)` |
| `actionlint` on both touched/added workflows | no findings (asserted per-file: `scripts/lint-workflows.sh` exits 0 on findings too, so repo-wide "clean" is unfalsifiable — plan revision R38a) |
| `bash scripts/regenerate-c4-model.sh` | `65 elements, 124 relations, 67 views` — the real C4 gate (`c4-code-syntax.test.ts` tests a tokenizer and `c4-render.test.ts` mocks `spawn`; **neither reads `model.c4`**, per R38c) |

## 6. What this PR does NOT close

- **A classify *hang* or a cancelled run still silences both channels** (R39/R20). With
  `timeout-minutes: 5`, a hung classify produces neither `failure` nor a written output, and
  `!cancelled()` is a conjunct of both conditions — so a cancellation structurally blocks the
  compensating step. `!cancelled()` is never executed as `false` in any arm above. This fix
  closes the `conclusion == 'failure'` case only.
- **Resend remains a single point of failure for the push channel** (R19). After this PR the
  only channel that *pages* on a failed release is one Resend email to one address. Resend
  degradation still equals silence — the #7095 shape, one vendor over. The Sentry mirror is a
  genuine second exit (see §4), but only via the un-codified rule the Phase 7 issue tracks.
