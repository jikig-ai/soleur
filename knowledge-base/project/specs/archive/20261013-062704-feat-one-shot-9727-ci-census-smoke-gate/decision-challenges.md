# Decision challenges: feat-one-shot-9727-ci-census-smoke-gate

Taste items from plan review, none of which argues the operator's stated scope should change. Each records the default taken.

## Declined: a `--last <N>h` window option on the census (CTO devex lens)

- Finding: typing two ISO timestamps is the most error-prone step; a `--last 6h` option is about five lines of `date -u`.
- Default taken: not built. The script header documents the `date -u` recipe for a closed window. The issue asks for a small script, and the option
  can be added by the first stage that finds the recipe tiresome.

## Adopted in a different form: list freshness (Kieran, security-sentinel, architecture-strategist, spec-flow-analyzer)

- Finding: `pulls/N/files` may lag a `synchronize` push, and a re-run reads the current PR rather than the run's SHA.
- First default (plan review): accept the risk. Reversed at deepen-plan because three reviewers independently rated it and `smoke-tests` never runs on `merge_group`, so nothing
  re-reads the list later. Adopted: compare the listed entry count with the event's own `changed_files` (no extra API call) and emit `true` on any mismatch. A `.head.sha`
  comparison was not adopted; a stale list with an equal count remains an accepted residual.

## Declined: a label or `workflow_dispatch` that forces the smoke matrix (CTO devex lens)

- Default taken: not built. Touching a subject file is the documented way to force smoke, and the ADR amendment states the rollback.

## Adopted in part: widen `SUBJECT_RE` and keep a small step-body test (CTO devex lens, DHH)

- Adopted: the test is reduced to a named list, an operand anchor and five fail-open rows. Not adopted: widening `.gitleaks.toml` to a `.gitleaks*`
  prefix, because `.gitleaksignore` is named explicitly and a prefix would also match unrelated future files.

## Review round 2026-10-08: dispositions that stay with the operator's stated direction

- **Reversed:** list freshness. A `.head.sha` comparison and a `>= 3000` cap rule are now built (security-sentinel, user-impact, structural enumeration). Closes the equal-count residual recorded above.
- **Kept (taste): no weekly smoke arm.** History, user-impact and architecture each noted the lost drift canary. The issue allowed dropping the claim, and a schedule arm changes non-PR behaviour that S1 promised not to touch; recorded as an accepted residual in the ADR amendment and the runbook, and handed to S5 (#9730) to decide with measurements.
- **Kept (operator direction): `Closes #9727`.** The post-merge census and canary cannot exist at merge time; their owner is S2 (#9512), recorded in the ADR amendment and the plan. A new tracking issue was not filed, so net issue flow stays at -1.
- **Declined (simplicity P3):** deleting the 49 named-list rows, the shim self-tests and the exact-count tripwires wholesale. Kept the ones that pin a plan property; removed the ones the review showed redundant (redundant name-extraction arm, `timeout`/`runs-on` pins, floor-shape retests, vestigial `assert_fixture_dir` copy, 13 rename-destination rows).
- **Declined (test-design P3):** an `if:` truth-table evaluator. The plan's Cut List removed it (it models GitHub's expression semantics with the author's own reading); the exact-string pin plus the Phase 6 canary stay the evidence.
- **Declined (quality P3):** moving the 45-line jq program to a `.jq` file; taste, with no property behind it.
- **Declined (agent-native P3):** a distinct exit code for API failure; exit 2 with a reason on stderr is the documented contract.
