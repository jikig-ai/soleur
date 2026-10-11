# CPO plan-time sign-off, #9776 (hosted autonomous ask)

Threshold: single-user incident. Basis: my third pass (ADR-277 "Addendum: CPO third pass", T12, CPO3-R1, CPO3-R2) and `cto-ruling.md` (RULING 1, persona/owner/cache, Rollout).
State checked 2026-10-10: #9776 OPEN (milestone "Post-MVP / Later"); #9603 OPEN.

## Verdict: APPROVED WITH CONDITIONS (CPO4-R1 to CPO4-R8). Plan may proceed to work. Merge is blocked until R3 and R4 are met.

My decision stands: ask for default-branch force-push/delete and `terraform|tofu destroy` only, `bash_autonomous` default unchanged, recursive delete out of scope. The CTO design implements that decision. Items (a), (c), (d), (f) went further than my words, and I rule on each below.

## Rulings

| Item | Ruling | Reason / condition |
|---|---|---|
| (a) Cache laundering removed in non-autonomous mode | APPROVED (explicit) | A prior "Approve all git push" or "terraform" grant silently approving `push --force origin main` or `terraform destroy` is the same defect as CPO3-R1. Leaving it open in the non-autonomous mode would leave a single-user incident path. Cost: some users get a card they previously did not. See R6. |
| (b) Approve/Reject only, per exact command, nothing durable | APPROVED | This is the right shape. An "Approve all" on a destroy family is the laundering path itself. See R2 for the card contents. |
| (c) Fail toward ask (unresolved default, implicit destination, `--mirror`) | APPROVED | Force pushes are rare; one extra click beats erased history. `--mirror` overwrites every remote ref including the default branch, same harm, so it is in scope although the hook's D1 omits it. It must be marked `hostedOnly` in the parity corpus. Tuning thresholds in R5. |
| (d) Non-owner members get the same ask and can approve | ACCEPTED as a recorded residual | Matches today's behaviour for every gate; building owner-only approval is new authz surface in a P1 security PR. Record it in ADR-282 with the revisit trigger "first workspace with more than one active member using autonomous mode". Not a blocker. |
| (e) Support persona keeps its deny | APPROVED | Deny with escalation is stricter than an ask. Test row required (already in the CTO matrix). |
| (f) Unparseable command containing `push`/`destroy` asks | APPROVED | The false-positive cost is small and bounded to commands that cannot be read. |
| (f) `gh api -X DELETE .../git/refs/heads/<default>` and `gh repo delete` | CONDITIONAL: see R4 | Same harm as a default-branch deletion, but my scope was the git-push forms, and reachability is unverified. |
| (f) Other residuals (variable-built names, aliases, scripts, terragrunt/pulumi, `git update-ref`, recursive rm) | ACCEPTED as recorded residuals | Named in ADR-282 and never contradicted by copy (R3). |
| (g) No feature flag, rollback by revert | APPROVED | The change fails toward ask, and a flag is a one-click way to reopen the P1 exposure. Revert triggers are defined in R5, so rollback is a decision rule and not a judgment call. |
| (h) Banner/toggle gains "pauses to ask" | APPROVED on framing, wording gated on CLO (R3) | See below. |
| (h) Already-acked owners do not see the new banner | ACCEPTED | The change only narrows the exposure they consented to; their consent is over-broad, not invalid. Nothing here is a consent defect. The settings toggle copy changes for everyone who opens it, and the ask card explains itself when it first appears (R2). |
| (i) T&C/AUP lag one legal bump | APPROVED | The sentence "does not guarantee that it will stop, or ask you first about ..." stays true; the parenthetical is date-anchored. The only effect of editing now is a forced Terms re-acceptance for every user, which is not worth it. Condition: CLO confirms in the CLO ruling that the lag understates protection and so is not a misstatement. Carry the parenthetical fix in ADR-282 follow-ups and the plan Non-Goals (the C3 precedent). |
| (j) Versioned ack deferred, no issue now | CONFIRMED | Narrowing needs no re-ack (CLO Q2 + CTO RULING 2). Trigger recorded in R8. |

## Product framing for (h)

The claim is "Soleur's hosted agent pauses and asks you first for these specific actions", not "Soleur protects your repository". The assurance:
- must stay hedged: it may not recognise every way of writing those commands;
- must keep "no blocklist is perfect" and the "other commands that look safe could still change or delete files" sentence;
- must name only what the lane covers: default-branch force-push/delete and `terraform destroy`. It must not say or imply "destructive commands", "deletes", "protects", "prevents", "safe", "recursive delete", or repository deletion;
- must be one sentence, identical in banner and toggle, and ship in the same build as the gate.

## Sign-off conditions

- **CPO4-R1 Scope lock.** The lane covers the D1 git-push family (force, delete, `--mirror`, `--all` with force), `terraform|tofu destroy` and `apply -destroy`, and the fail-closed rule. No recursive delete, no new ask classes, no `bash_autonomous` default change, no `AGENT_ENV_OVERRIDES` edit. Any widening comes back to me.
- **CPO4-R2 Card and rejection contract.** The card names the cause in plain words ("Soleur paused this because it would overwrite or delete your default branch" / "would destroy infrastructure") and says approval applies to this command only. A Reject, a timeout and an abort all deny. The deny text handed to the agent tells it not to retry or respell the command (parity with D4 for matched destructive commands). Test row for the deny text.
- **CPO4-R3 Copy gate (merge blocker).** CLO verbatim sign-off on the banner and toggle sentence, LOCKED-copy tests updated with the same bytes, no edit to `docs/legal/terms-and-conditions.md`, AUP or `TC_VERSION`. No wording the CLO has not seen ships.
- **CPO4-R4 gh residual fact check (merge blocker, small).** Before merge the CTO states, from code (agent env + sandbox image), whether a `gh` binary and a token with ref-delete (contents write) or admin scope reach the agent. If `gh api -X DELETE` on `git/refs/heads/*` is reachable, it goes in THIS PR as one more classifier family: it is the same harm, and the copy I approved in (h) would otherwise be read as covering it. If not reachable, record the evidence in ADR-282 and leave it as a residual. `gh repo delete` follows the same test: in if reachable, otherwise a residual. In either case add the keyword-only near-miss telemetry for `gh` + `delete` so a miss is measured.
- **CPO4-R5 Storm and tuning rule (replaces "watch for a storm").** ADR-282 records the initial thresholds before merge: revert (not tune) if, in the first 24 h, any one rule id accounts for more than 25 percent of hosted Bash calls from a single workspace, or `destroy-classifier-error` is non-zero without a fix inside 24 h. Tune (do not revert) if `git-push-unknown-default` is more than 10 percent of asks over 7 days (the default-branch lookup is then the defect) or the fail-closed-keyword plus raw-scan share is more than 25 percent. The measured numbers are written into the ADR-277 addendum, as CPO3-R3 requires for its own classes.
- **CPO4-R6 Non-autonomous behaviour change disclosed.** The PR body and the changelog entry state that a previously granted "Approve all git push" or "terraform" no longer covers the destroy forms. No in-app notice is needed.
- **CPO4-R7 Close-out discipline.** CPO3-R1 is marked closed in the ADR-277 addendum only after the post-merge verification below passes. CPO3-R2 is closed by the CLO-signed copy. The C2 supersede-UPDATE status question from #9792 stays with the operator and does not gate this PR. Roadmap hygiene: #9776 is on "Post-MVP / Later" although ADR-277 calls it P1; reassign it to the active phase milestone when the PR opens.
- **CPO4-R8 Ack trigger recorded.** ADR-282 states: any change that widens what hosted autonomous mode may do without asking (relaxing the lane, adding a flag that bypasses it, enabling the hook's weaker modes) first requires the versioned acknowledgement design from the CTO ruling. No issue is filed now; the trigger lives in ADR-282 and the plan Non-Goals.

## Post-merge measurement required before #9603 may claim hosted coverage

All of the following, with data pulled by API (hr-no-dashboard-eyeball):
1. Dev hosted, throwaway repo, acked autonomous workspace: `git push --force origin <default>`, `terraform destroy`, and one `bash -lc` variant each produce the card, a pino `decision:"destroy-ask"` line and a Sentry `hosted-destroy-ask` event carrying the rule id and no command text. Also run: a non-owner member session (same card), a pre-granted `git push` batch grant (still gated), and a plain `git push origin feat-x` (no card).
2. Prod: the telemetry stream exists and 7 days of per-rule ask counts, outcome counts (approved/rejected/expired), near-miss events and `default-branch-resolve` failures are recorded in the ADR-277 addendum. Zero unexplained `destroy-classifier-error` and no R5 threshold tripped. Low prod ask volume is acceptable; the claim rests on item 1 plus the CI corpus, not on prod destroy attempts.
3. CI evidence: hook-parity superset test, mutation matrix (all killed or justified) and the real-factory test (AC-14) green on the merged commit.
4. The #9603 wording is limited to: "hosted agents pause and ask before force-pushing over or deleting a default branch and before `terraform destroy`", with the same hedge as the banner. It does not claim approval gating of destructive actions in general. #9603's own criteria still apply (#9545 egress audit log, CLO review, Art. 30/DPD/Privacy updates in the same PR).

## Capability gaps
None blocking.
