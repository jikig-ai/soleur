# Decision challenges — feat-one-shot-8760-pin-redeploy-rerun-carryover

Plan: `knowledge-base/project/plans/2026-09-27-fix-pin-redeploy-gate-ignores-carried-over-jobs-plan.md`.
The plan was reviewed headless (plan-review: DHH, Kieran, code-simplicity, CTO). Mechanical findings
were applied. The choices below were not, because each would change the direction the brief set.
Each can still be taken.

## DC-1 (user-challenge): drop the timestamp discriminator and keep only the deploy-evidence check

- **Raised by:** DHH P1 and code-simplicity P1.
- **Argument:** the deploy-evidence check (a release created after the apply finished has a
  successful `deploy`) is enough on its own to make a skip safe. The `startedAt` comparison only
  limits which followers the rule reaches. Dropping it removes the source argv change, the
  timestamp parsing, one fixture file and about six test rows.
- **Why not applied:** the brief names `startedAt < run_started_at` as the discriminator and asks
  for fixtures built from that measured shape. Dropping it would also widen the skip to git-data
  jobs that re-executed in the new attempt.
- **To take it:** remove CARRIED conjuncts 2 to 4 and keep the `attempt >= 2` check.

## DC-2 (user-challenge): annotate only, or close #8760 as won't-fix

- **Raised by:** CTO P1, DHH P2 and code-simplicity P2.
- **Argument:** the defect has occurred zero times in the last 500 runs, and its cost is one
  idempotent release. An alternative is to print that a job was carried over, keep redeploying,
  and add about 4 test rows instead of about 20.
- **Why not applied:** the brief asks for a fix and for `Closes #8760` when the fix fully resolves
  the issue.

## DC-3 (taste): keep the ADR-237 clause, the workflow comment sentence and the C4 parity AC

- **Raised by:** DHH P2 and code-simplicity P2, who suggested cutting them.
- **Why kept:** PT5 reads the verdict tokens that ADR-237 and the follower workflow cite. The
  existing `plan_only` clause is the precedent for recording gate semantics in the ADR. Each
  addition is one sentence.

## DC-4 (taste): a parity row instead of a shared sourced library for `EVENT_ARM`/`DEPLOY_JOB`

- **Raised by:** DHH, CTO and code-simplicity. Each named a shared library as one of the options.
- **Chosen:** parity row H3. It pins that the values in the two files are equal, without editing
  `track.sh` or its sparse-checkout path.
