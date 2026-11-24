# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-11-23-fix-cf-dns-import-normalize-gate-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=0 from this parent after planning (the planning subagent's own CTO consults are recorded in decision-challenges.md)

### Errors

- The job suite first showed 19 failures from the planner's own 280 s timeout. Uncapped it gave 172 passed, 0 failed in 585 s.
- technical-ruling-gate rejected one class spelling; corrected to `operator (production-mutating)`. The gate passes on 20 rows.
- markdownlint reported 2 MD038 issues, fixed.
- lint-encryption-posture.py takes no plan path, so the plan's Encryption Posture section is not linted by it.
- A loopback-mock terraform apply was not run because the brief forbids terraform apply. The PATCH body is known from source only.
- The collision pre-check exited 10 on draft PR 12958, a tunnel PR that names the same epic. It touches no gate, job, imports or runbook file.

### Decisions

- Admit `["update"]` only for an import-class `cloudflare_record` with the exact measured shape, bound to its pinned id and a live read taken after the plan. The retry shape also needs the pre-plan state id to match the pin. It logs as `import-normalize`.
- Read all 26 records on every `redirects-dns` plan and again after any apply that carried an admitted record. Any difference halts.
- Bound the apply with one INT at 1100 s only when the gate admitted a record. `zone-rest` keeps today's argv.
- Fix all four security-sentinel findings S1-S4.
- Open for the owner before the first `rehearsal=false` dispatch: observe the first PATCH or accept it unobserved.

### Components Invoked

- Skills: soleur:plan, soleur:deepen-plan
- Agents: soleur:engineering:cto, soleur:product:cpo, soleur:engineering:review:dhh-rails-reviewer, soleur:engineering:review:kieran-rails-reviewer, soleur:engineering:review:code-simplicity-reviewer, soleur:engineering:review:architecture-strategist, soleur:product:spec-flow-analyzer, soleur:engineering:review:security-sentinel

## Operator Constraints

- constraint: Do NOT merge, stop with the PR ready for the owner review, because it widens a production safety gate.
- constraint: Do NOT dispatch any workflow, write Doppler, call a Cloudflare write endpoint, run terraform apply, or SSH anywhere.
- constraint: Never print a token value.
- constraint: Ref only, never a closing keyword, the issue stays open.
- constraint: Do not fire the gh-pages cert reissue manual trigger with probeOnly false until Phase 3 step 5.

## Review Phase

- Panel SHA: `1f063556b9`. Class `code`, tier `single-user incident` (source: plan), design-risk no. 13 of 13 seats returned.
- Seats: security-sentinel, data-integrity-guardian, architecture-strategist, performance-oracle, pattern-recognition-specialist, code-quality-analyst, git-history-analyzer, agent-native-reviewer, user-impact-reviewer, test-design-reviewer, structural-enumeration (general-purpose), code-simplicity-reviewer, semgrep-sast.
- Scan receipt: `SOLEUR_REVIEW_SCAN_GATE ok engine=shellcheck files=4 rules=0 findings=15`. No clean-SAST claim: no semgrep rule ran. All 15 are in the two suites and classified intended or false positive.
- CI on the panel SHA: `cloud-init-inngest-bootstrap.test.sh` also fails on `main` (pin v1.1.73 against tag v1.1.74); `test` is held red on drafts until the ready run.
- Structural-cause roll-up: (1) post-write outcomes have no single routing table (R1-R7, R11, R21); (2) the guard's window is narrower than its stated property (R13); (3) suite fixtures have one record shape and one direction (R14).
- dedup: 74 raw -> 25 unique.

| Key | Sev | Canonical defect | Reporting seats | Disposition |
|---|---|---|---|---|
| R1 | P1 | `reread=unreadable` routed to the wrong-value restore and to conflicting Halt bullets | architecture, agent-native, performance, user-impact, code-quality | fix |
| R2 | P2 | Gate prints an unreadable record as `differs`, naming all 26 | agent-native, architecture | fix |
| R3 | P2 | Runbook wrong-value trigger omits `rehearsal-refused` | agent-native, architecture | fix |
| R4 | P2 | `import-normalize-reread-failed` drops the `failing=` outage route | architecture, pattern | fix |
| R5 | P2 | Runbook blames `cron-gh-pages-cert-reissue` for a `proxied` difference it cannot cause | agent-native, architecture, user-impact | fix |
| R6 | P2 | Diagnostic tokens have no action; Step 2 "fix the record" contradicts the Halt | agent-native, architecture | fix |
| R7 | P2 | Owner-path steps (observe first PATCH, restore edit) cannot be executed as written | agent-native | CTO |
| R8 | P2 | Live read stops retrying after about 11 s of its 90 s deadline | performance | fix |
| R9 | P2 | A live `comment` in terraform output is parsed as a workflow command | security | CTO |
| R10 | P2 | Plan and PR body misstate what merging deploys (#12937 blocks the release, or a 29-commit backlog ships) | user-impact | fix |
| R11 | P3 | Retry text has the failed-write case backwards; `imports=` explanation wrong | data-integrity, architecture | fix |
| R12 | P3 | Completion predicate counts an unnormalized record as migrated | data-integrity | CTO |
| R13 | P2 | Guard window: non-managed mode, duplicate address, non-import record class, duplicate pin, no-op id unbound, `data` uncompared, live `result.id` unbound at the gate | structural, test-design, architecture | CTO |
| R14 | P2 | Test gaps: create row, omitted fields, plan-side direction, state id, real record shapes, bound value, strict curl fake, `TMPDIR` depth, reason tokens | test-design | fix |
| R15 | P3 | Time bounds: start floor, bound scope (dissent from F14), unbounded plan, INT is 1100 s plus the Doppler fetch (dissent from F11) | performance, code-quality | CTO |
| R16 | P3 | A failed `NORM_COUNT` grep disables the bound and the re-read | code-quality | fix |
| R17 | P3 | A mixed re-read hides the unreadable record from the refusal | agent-native, pattern, simplicity | fix |
| R18 | P3 | `reread_records` does not guard its pin lookup | pattern | fix |
| R19 | P3 | `LIVE_READ_SH` repeats the API base | pattern | fix |
| R20 | P3 | Header contracts disagree with the code | code-quality, architecture, agent-native | fix |
| R21 | P3 | Runbook routing: `apply-budget-exhausted`, `verify=skipped`, success line, exit 124, `zone-rest` | architecture, agent-native | fix |
| R22 | P2 | Ledger and ADR do not record the superseded 2026-11-19 ruling or the new hand-edit exception | git-history, architecture | fix |
| R23 | P3 | NS and ACME records unnamed in User-Brand Impact and the Halt order | user-impact | fix |
| R24 | P3 | Simplifications S1-S8 | simplicity | fix where the guard keeps its property |
| R25 | P2 | Skip marker might not survive a squash | git-history | no change: the repo's squash message is `COMMIT_MESSAGES`, so branch commit bodies are carried |
| R26 | P2 | One apply writes all 26 records before any check of a written value | coverage | Q9: no canary, stated in the PR body and the owner's token |
| R27 | P2 | Nothing checks that `api` or mail records resolve after the write | coverage | Q10: runbook before-and-after comparison |
| R28 | P3 | The failure alert depends on the DNS records it reports | coverage | Q11: alert workflow and corrected email |

- R24 disposition: take S1, S6 (via R17) and S8. Keep S2, S3, S4, S5 and S7: they are redundant checks or helpers on a production safety gate, and removing them saves about 10 lines of temporary code while re-anchoring mutation rows.
- Rulings: `decision-challenges.md` rows Q1-Q11. Full implementation shapes and seat reports were saved to `/var/tmp/review-13019-*.md` for this session only.

### Fix Rounds

- Round 1 (`1f063556b9..1a221b9493`) closed R1-R24, R26-R28 by ruling. Five targeted seats then reviewed it (security, architecture, data-integrity, agent-native, test-design; shellcheck run by the lead).
- Round 2 (`1a221b9493..c4d703ebb7`) closed that round's findings: 1 rated P1 and P2 by two seats (a failed read could restore a superseded first-write decision), 8 further P2s and the P3s.
- Verification seat at `c4d703ebb7`: every P1 and P2 closed, no new P1 or P2, four new P3s. Three fixed in `bcdf3e5bda`.
- Declined: printing the recreated record's full id. The runbook limits printed ids to 8 characters; the full id is read from the zone by name and type.
- Left as stated residuals: U9 (no digest binds the graded plan to the applied plan), the unbounded init, forget and plan stages (Q3), and the `%` encoding of `_err` in `preapply-entrypoint-gate.sh` (pre-existing; a live ruleset value can add lines to an annotation, and no command runs).
- Never exercised against a real API or runner: the restore and recreate blocks, the first PATCH, the alert's `workflow_run` trigger, and the `completedAt` read.
- Final local suites at `bcdf3e5bda`: gate 344, job 285, runbook 165, completion 119, scope 110, fixture-relative 63, workflow parity 415, pipe guard green.

## QA and Compound

- QA: the plan's Test Scenarios carry no `Browser:`, `API verify:` or `Cleanup:` steps, so automated QA was skipped by design; the suites above cover them.
- Compound: learning `2026-11-24-the-recovery-steps-my-fixes-added-were-the-least-reviewed-code-in-the-pr.md`, 17 session errors.
- Route-to-definition: skipped for this PR. The brief scopes it to the DNS gate fix and it widens a production safety gate, so no skill file is edited here.
- Residuals are recorded in the plan's `## Dependencies & Risks` instead of a new issue: the code is temporary, so a standalone issue fails the `wg-defer-only-after-inline-triage` test.
- Archival is deferred to ship, which still reads this spec directory.
