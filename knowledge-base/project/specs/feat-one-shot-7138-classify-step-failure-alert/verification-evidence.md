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
> B1a–B1f inside the required `test` check.
>
> After merge and branch deletion this repo squash-merges, so `8e5a052a9` is reachable only
> via `refs/pull/7139/head` — recover it with `git fetch origin refs/pull/7139/head` before
> re-running that diff.
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

An assertion never seen red pins nothing. Each mutation is applied to a pristine copy, the
suite run, and the tree restored and diffed byte-for-byte. The control (unmutated) run is
executed **first**: a red baseline would make every result below noise rather than evidence.

### Round 1 — as first written (10 mutations, 10 RED)

| # | mutation | went RED |
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

**That round was green and it was not sufficient.** It measured the mutations I thought of.
Five review agents then reproduced four defects it could not express, because every mutation
in it perturbs bytes the assertions already read. The axes it never touched: deleting an
`env:` DECLARATION, swapping a discriminator between two correlated predicates, sweeping a
value space (`R_DEPLOY`), and deleting an assertion outright.

### Round 2 — after review (11 mutations, 10 RED, 1 intentional survivor)

| # | mutation | went RED |
|---|---|---|
| N-1 | email step drops its `CLASSIFIER:` env declaration | B1a-email, B6a, B6b, B6g |
| N-2 | mirror step drops its `CLASSIFIER:` env declaration | B1a-mirror, M1b, M3a |
| N-3 | email gate reverts to `R_DEPLOY != 'failure'` | B6i[skipped], B6i[cancelled], B6i[unset] |
| N-4 | mirror keys its narrative on `CLASSIFIER`, discarding the job list | M2a, M3a |
| N-5 | run-link hint stops tracking the list it points at | B6e |
| N-6 | classify step loses its `timeout-minutes` | B1f |
| N-7 | deploy-success branch reasserts "nothing reaches production" | B3c |
| N-8 | successful send records `delivered=0` | B8a |
| N-9 | an assertion block is deleted | **the floor** (`ran 66, floor is 67`) |
| N-10 | harness fabricates `CLASSIFIER` instead of deriving it | B3a |
| N-11 | env reader drops the final declared key | *survives — by design* |

**N-11 is a deliberate survivor, not a gap.** The trailing-newline defect is fixed at BOTH
ends — the extractor emits a terminating newline, and the reader tolerates its absence.
Either alone suffices, so neutering one cannot fail. Neutering both would, and that is two
independent edits.

**N-9 is the one that matters most.** Before the floor existed, deleting B1c/B1d/B1e left the
suite at `45/45, exit 0` — the exit contract is `FAIL > 0`, so silence and success were
indistinguishable and every other row in both tables was unpinned at the top level.

**Two false results were caught during this round and are recorded because they are the
failure mode of mutation testing itself:**

- A sandbox copy of the test file placed outside the repo broke its `SCRIPT_DIR` resolution,
  so extraction never ran and the trace showed an empty environment. That is a **red
  baseline**, which voids the measurement rather than producing a finding.
- An N-2 attempt used an `||` fallback whose FIRST anchor matched, so the mutation inserted a
  comment and never removed the declaration. It reported SURVIVED. A mutation that does not
  mutate is **un-run**, never evidence — re-run with a verified anchor, it went RED.

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

`filters: []` and `environment: null` mean no tag gate and no environment gate. The
action is `NotifyEmailAction` with `targetType: IssueOwners` and
`fallthroughType: ActiveMembers` — and since this project has no ownership rules, the
fallthrough is what actually reaches a human. Sentry derives high priority from `level`,
and the mirror POSTs `level:"error"`. **The mirror does page the operator.** The premise
is false.

**One qualification, added at review.** The rule's conditions are
`NewHighPriorityIssueCondition` and `ExistingHighPriorityIssueCondition` — *first-seen*
and *escalated-to*. Neither matches a plain recurrence of an issue that is already high
priority. So a repeat of an identical event is silent on this route, which is precisely
the case a release-alert channel has to survive. That is recorded on #7142, and it is why
a codified `gate:release-outcome` rule is still worth having even though the default rule
pages today.

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
3. **`model.c4` is corrected** rather than edited past: `sentry -> founder` carried a
   stale *"21 of the 22 rules"* and omitted the un-codified 30th rule entirely. The
   actual figures are **29 IaC rules, 28 `ActiveMembers`, 1 `NoOne`** (`byok_cap_exceeded`
   only). My first correction said 2 `NoOne`, having attributed a `NoOne` mention that is
   a **comment** inside `byok_art_33_breach`'s block; two review agents caught it by
   parsing `fallthrough_type` assignments instead of grepping the bare token. That is the
   anchor-on-syntax-not-a-bare-token class, committed while correcting a stale count.

This is recorded at length because the falsified premise was the stated basis for a scope
deviation. The deviation still stands; its justification does not.

## 5. Local gates

| gate | result |
|---|---|
| `bash scripts/lint-workflow-step-env-refs.test.sh` | `All tests passed` — **69/69** (48 before review) |
| `python3 scripts/lint-workflow-step-env-refs.py` | `0 findings across 70 workflow file(s)` |
| `actionlint` on the one touched workflow | no findings (asserted per-file: `scripts/lint-workflows.sh` exits 0 on findings too, so repo-wide "clean" is unfalsifiable — plan revision R38a) |
| `shellcheck -S warning` on the test file | clean |
| `bash scripts/regenerate-c4-model.sh` | `65 elements, 124 relations, 67 views` — the real C4 gate (`c4-code-syntax.test.ts` tests a tokenizer and `c4-render.test.ts` mocks `spawn`; **neither reads `model.c4`**, per R38c) |

## 6. What this PR does NOT close

- **A classify *hang* or a cancelled run still silences both channels** (R39/R20). With
  `timeout-minutes: 5`, a hung classify produces neither `failure` nor a written output, and
  `!cancelled()` is a conjunct of both conditions — so a cancellation structurally blocks the
  compensating step. `!cancelled()` is never executed as `false` in any arm above. This fix
  closes the `conclusion == 'failure'` case only.
- **The only IaC-defended paging channel is one Resend email to one address** (R19). A
  second exit does exist — the Sentry mirror pages via the default rule in §4 — but that
  route is UI-managed, absent from Terraform, and silent on a repeat of an identical
  event. An earlier draft of this section said Resend was the *only* channel that pages,
  which contradicts §4 of this same file; corrected at review.
- **The mirror's own death before its POST is visible only as a red job**, which is also
  what a successful mirror fire looks like (the step ends `exit 1` by design). The
  discriminator is whether the Sentry event and the step-summary line exist.

## 7. What multi-agent review changed (and what it caught that I did not)

Eight agents reviewed the branch. Four independently reproduced the same P1, by execution.

**The headline reassured on releases that never rolled out.** The classifier-death branch
was gated `CLASSIFIER == 'failure' && R_DEPLOY != 'failure'`. But `deploy` has five upstream
`needs:`, so `skipped` — not `failure` — is the dominant failed-release state. Measured
against the shipped body:

```
CLASSIFIER=failure R_DEPLOY=skipped    -> [RELEASE STATUS UNKNOWN] ... we could not tell
CLASSIFIER=failure R_DEPLOY=cancelled  -> [RELEASE STATUS UNKNOWN] ...
CLASSIFIER=failure R_DEPLOY=failure    -> [RELEASE FAILED] production was NOT updated
```

`needs.deploy.result` sits in that step's own `env:` and is unaffected by the classifier
dying, so the truth was available on every path and the gate discarded it. One sub-case was
a **strict regression against `main`**: with `failed != ''` populated, `main` sent
"[RELEASE FAILED] production was NOT updated" where this branch sent "UNKNOWN". The gate is
now positive (`== 'success'`), which also restores the fail-open direction the file's own
comment mandates. B6h/B6i sweep every value of `R_DEPLOY`, not the two I imagined.

**My tests pinned the inversion.** B6 passed `rdep=unset` and asserted the reassuring
subject, so the suite actively enforced the defect. Retargeted.

**The harness fabricated the environment it was supposed to verify.** `run_step`/`run_mirror`
hardcoded their env lists and injected `CLASSIFIER`, so deleting `CLASSIFIER:` from either
step reverted the whole fix at 48/48 green — #7136's class recurring for the new variable.
Both now derive from the step's own `env:` block. Fixing that surfaced a fail-open inside the
fix: the key file had no trailing newline, so `while read` dropped the LAST key and the
harness supplied a key the workflow no longer declared. Fixed at both ends.

**My fixtures sampled one diagonal of a 2×2.** Over (`CLASSIFIER`, `FAILED` non-empty) I
instantiated only the two cells where the predicates are perfectly correlated, so swapping
the discriminator to `-z FAILED` in either body survived everything. The missing cell is the
state the workflow's own comment names as its entire justification — and in it the mirror
asserted "the classifier died before it could record which jobs failed" about a run where it
demonstrably had. The mirror now answers the two questions with two independent fields.

**A correction I made was itself wrong.** Correcting `model.c4`'s stale `NoOne` count, I
reported 2 (`byok_cap_exceeded` and `byok_art_33_breach`) from an `awk` that matched the bare
token `NoOne` — which appears in a **comment** inside the second block. Parsing
`fallthrough_type` assignments gives 28 `ActiveMembers` / 1 `NoOne`. Two agents caught it.
That is the anchor-on-syntax-not-a-bare-token rule, broken while fixing a stale count.

**An argument was struck, not weakened.** DC-1 led with "release-outcome is the only channel
that fires regardless of which job failed". True of the **job** — and both the email and the
mirror are steps *inside* that job, so it argues equally for the mirror-only fix. Removed.

**A residual I called unclosable was closable.** I attributed the classify-hang gap to
`!cancelled()`. The proximate cause is that the only `timeout-minutes` was job-level, so a
hang burned the budget and neither alert step was ever scheduled. A step-level timeout turns
a hang into the failure this PR now catches; B1f pins it.
