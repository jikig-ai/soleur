---
category: engineering
tags: [ci, github-actions, pull-request-target, rulesets, break-glass, incident]
date: 2026-08-19
---

# Break-Glass: a self-sealing required check

Operations runbook for the deadlock in which a **required status check cannot be repaired by
any pull request**, because the check itself blocks every PR — including the one that fixes it.

Filed as **Condition D1** of the CLO ruling at
[`knowledge-base/legal/audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md`](../../../legal/audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md).

**Cross-references:**
- Executable preflight: [`scripts/preflight-required-check-bypass.sh`](../../../../scripts/preflight-required-check-bypass.sh)
- Detection guard: [`scripts/lint-workflow-install-sites.sh`](../../../../scripts/lint-workflow-install-sites.sh) clause 3
- Adjacent runbook: [cla-signature-evidence-retrieval.md](./cla-signature-evidence-retrieval.md)

**Fixtures in examples below are synthetic where they name values you must substitute.** The
2026-08-16 timestamps and PR numbers are real and are cited as precedent, not as templates.

---

## 1. The mechanism

A workflow triggered on **`pull_request_target`** executes the workflow file from the **base
branch**, never the PR head. This is a deliberate security property, not a bug — it is *why*
the trigger may hold secrets, since a fork PR cannot rewrite the code that reads them.

The consequence: **if such a workflow breaks on `main`, and it produces a required check, no
PR can repair it.** Every PR is evaluated against the broken base-branch copy. The remediation
PR fails the very check it repairs. Closed loop.

The sanctioned exit is a **ruleset bypass actor**. Verify one exists before assuming it does —
a ruleset with an empty `bypass_actors` array has no exit at all.

## 2. Know the surface before you need it

The deadlock is only possible where a required check is produced by a `pull_request_target`
workflow. That intersection is small, and it is worth knowing cold:

```bash
scripts/preflight-required-check-bypass.sh --surface
```

As of 2026-08-19 that returns:

| Required check | Produced by | Ruleset |
|---|---|---|
| `cla-check` | `cla.yml` | CLA Required |
| `cla-evidence` | `cla-evidence.yml` | CLA Required |

Nothing else in the repo can deadlock this way — every other required check is produced by a
`pull_request`, `merge_group`, or `push` workflow, all of which run the **head** copy.

**Do not compute this surface with `grep -l pull_request_target .github/workflows/`.** Measured:
that returns five files on this repo, three of which only *mention* the trigger in a comment.
The `on:` block is what decides, which is why the script parses it.

## 3. Diagnosis

You are in this scenario if **all** of the following hold:

1. A required check is failing on every open PR, including brand-new ones.
2. Re-running it does not help, and pushing to the PR does not help.
3. The workflow producing it is on the `--surface` list above.
4. The failing step is the same on every PR — this is a base-branch defect, not a PR defect.

Signature to look for: the workflow's runs on `main` show `skipped`, not `failure`.
`pull_request_target` does not fire on push, so **a broken base copy is invisible on `main`**.
That is how #7566 merged green and broke every downstream PR simultaneously.

## 4. The exposure checklist — run BEFORE any bypass

This is the reusable asset from #7597. The bypass is not the lesson; the measurement that
authorised it is.

```bash
scripts/preflight-required-check-bypass.sh \
  --check <context> --since <first-failing-run-ISO8601> --until <restoration-ISO8601>
```

Omit `--until` only while the outage is still live. The window has two ends; an open-ended
window sweeps every merge to now and reports `REAL` for a long-since repaired incident —
correct arithmetic, wrong question.

The script measures what can be measured and **refuses to guess at the rest**. Its exit codes:

| Exit | Verdict | Meaning |
|---|---|---|
| 0 | NIL | The automated probes found no exposure. One manual item remains (below). |
| 1 | REAL | Something measurable happened in the window. The zero-loss precedent does not apply. |
| 2 | UNKNOWN | A probe could not be answered. **Treat as REAL.** |

**Exit 2 is not a soft failure.** An unanswerable probe is not a clean probe — that is ADR-192's
finding, learned from this same subsystem: a query returning nothing because the channel was
never instrumented is indistinguishable from one returning nothing because the event never
happened, and the first reads as safety. The script therefore never collapses UNKNOWN into NIL.

### The four items, and why each mattered for #7597

1. **Is the artifact this check writes already written?** For a per-period canonical record
   under conditional PUT, look for a `409` in the last good run's output. If the record exists,
   every run in the window is a no-op and the loss is nil. If the period has rolled over and no
   record exists, **the loss is real and this precedent does not apply.**
   *This item is not automated* — the script cannot reliably extract a conditional-PUT status
   code from a job log, and it says so rather than pretending. Open the last successful run.
2. **Did any merges land during the window?** Automated. Zero merges means zero unrecorded
   events. For #7597 this measured **0**.
3. **Was the write path ever reached?** Automated. For a multi-trigger workflow, check whether
   the *other* trigger's runs were `skipped`. A path never invoked cannot have dropped anything.
4. **Did the enforcing gate stay green?** Distinguish the **sidecar** from the **instrument**.
   For #7597, `cla-evidence` is a sidecar to `cla-check`; the latter never failed, so the
   enforceable control held throughout. The script enumerates the sibling required checks; the
   sidecar/instrument judgement is yours, because it is semantic.

The outcome for #7597 was a **merge-control availability failure, not an evidence failure**. No
records were lost and no backfill was owed or even possible — the target key was occupied and
under Object Lock.

## 5. Executing the bypass

Only after §4 returns exit 0 and item 1 is confirmed by eye.

1. Confirm a bypass actor exists on the ruleset (`--surface` prints them).
2. Merge the remediation PR through the bypass.
3. Record the justification in `knowledge-base/legal/audits/` **and** a commit trailer.

## 6. What NOT to do

- **Do not add `continue-on-error` to the broken step.** The workflow's own comment forbids
  swallowing non-zero under `cq-silent-fallback-must-mirror-to-sentry`, and it converts a loud
  outage into a silent one — strictly worse, because the next occurrence is undetectable.
- **Do not write incident prose into the evidence store.** It is schema-validated,
  content-addressed and Object-Locked; narrative degrades its evidentiary character. The
  justification belongs in `knowledge-base/legal/audits/` plus a commit trailer.
- **Do not reason "we are already non-compliant, so one more does not matter."** That treats an
  accumulating harm as a sunk cost and licenses indefinite continuation.
- **Do not skip §4 because the last incident measured nil.** The nil finding rested on a
  quarter-specific fact — the canonical record already existing. Early in a quarter, the same
  outage loses real evidence. The precedent is the *method*, not the verdict.

## 7. The detection gap — closed 2026-08-19

The 2026-08-16 break was invisible on `main` because `pull_request_target` does not fire on
push, so every post-merge run showed `skipped`. #7566 merged green and broke every downstream
PR.

`scripts/lint-workflow-install-sites.sh` clause 3 asserts that any step invoking `bun ` is
preceded by a `setup-bun` step in the same job — which is exactly the #7566 defect. **It did not
catch it.** Measured by restoring the broken file and re-running: `scanned 83 workflow file(s)
… OK`.

The cause was the recurring one: the clause named the property *"any step invoking `bun `"* but
matched only two **positions** — a `run:` line, and a line whose first token is `bun`. The
broken call site was `payload=$(bun run …)`, a command substitution, which is neither.

Clause 3 now enumerates shell **command positions** structurally (`$(`, backquote, and
pipeline/list separators) rather than accumulating the shape that most recently bit. Plain
whitespace is deliberately excluded so that a `bun` *mention* inside an `::error::` string is
not treated as an invocation. The historical broken tree now goes RED naming the job; the live
tree stays green.

**This closes the specific interpreter/setup defect, not the general class.** A required
`pull_request_target` check can still break on `main` for a reason no lint models. §2 and §4
are the standing controls; §7 removes one recurring cause.

## 8. Precedent

| Date | Incident | Outcome |
|---|---|---|
| 2026-08-16 | #7566 removed `Setup Bun` from `cla-evidence.yml`, left two `bun run` sites; required `cla-evidence` broke on every PR | Exposure measured NIL; #7597 landed via admin bypass; CLO ruling APPROVED, conditions discharged |
