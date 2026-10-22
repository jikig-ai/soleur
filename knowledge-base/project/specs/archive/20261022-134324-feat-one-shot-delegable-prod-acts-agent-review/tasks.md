# Tasks: delegable envelope acts and agent review language

Plan: `knowledge-base/project/plans/2026-10-22-chore-delegable-envelope-acts-and-agent-review-language-plan.md`

Constraints: the PR stops before merge (no `gh pr merge`, no `--auto`, no postmerge); no production touch; no workflow dispatch; no Doppler access; no new issue; run test suites one at a time with stdin from `/dev/null`; say "unavailable" or "disruption", never the banned word.

## Phase 1 — Runbook (`knowledge-base/engineering/operations/runbooks/inngest-server.md`)

- 1.1 Redefine the A2 row as the flip_verify handshake plus a post-flip re-run expecting `result=pass`.
- 1.2 Strike A2 from the A3 preconditions; add the post-flip A2 re-run to A3's success evidence.
- 1.3 Fix the last sentence of "Calling the handshake hook (A2)": answers only after the CA is installed (placeholder, https arm, `verified_rc=77` expected).
- 1.4 Add the Done paragraph (A0, A1, A1b with run ids, iid, tls-health values) and the general line that a replace whose user_data already carries the TLS listener satisfies A1.
- 1.5 Rewrite the intro and the A0, A1, A3, A4 authority cells: a valid recorded Standing Delegation, or an in-session per-command go typed by the owner naming the command; rename the column; state no delegation is recorded as of 2026-10-22; state a delegated run needs its own committed envelope with a space-free `reason` token.
- 1.6 State the owner-human list (A1b environment approval, A5, A6, A7, money, sole-copy data loss, force-push or ruleset bypass, ask-me-before holds); leave the failed-replace rule unchanged.
- 1.7 Consistency sweep: the "authorization is procedural" paragraph and the act A1 reference in the replacement sequence.

## Phase 2 — Hold routing (F2)

- 2.1 Extend `plugins/soleur/commands/go.md` Step 1.5 (outside the eval-gated block): list sources, production-holds definition, exclusions, attached ask-once, headless deduplicated issue. Keep every pinned token; no `plugins/soleur/` prefix inside the paragraph.
- 2.2 Widen the `plugins/soleur/skills/one-shot/SKILL.md` pointer; keep the two grepped substrings.
- 2.3 Add positive and negative rows to `plugins/soleur/test/go-hold-routing.test.sh` with violation tokens and mutation rows.
- 2.4 Run `cto-interface-selector.test.sh` after the go.md edit.

## Phase 3 — Ship gate (F1)

- 3.1 Add the `Delegated act (CTO, Standing Delegation <comment-url>): ...` paragraph and the prose verification step to the Undeferred Operator-Step Gate section of `plugins/soleur/skills/ship/SKILL.md`; leave the regex and options untouched.
- 3.2 Add two rows to `.claude/hooks/ship-operator-step-gate.test.sh` (delegated form passes; operator-verb bullet citing a delegation still blocks).
- 3.3 Add the same two cases plus a skill-text assertion to `plugins/soleur/test/ship-undeferred-operator-step-gate.test.ts`.

## Phase 4 — Review language (F3)

- 4.1 fix-issue: agent review via the drain-prs needs-review tier; fix the stale pointer to `cron-bug-fixer.ts`.
- 4.2 model-launch-review: CTO agent ruling for items 2 to 6; spend and billing constant stay operator authorization.
- 4.3 sync.md rule prune: CTO ruling, default keep, zero hits never evidence, exclusion list.
- 4.4 deepen-plan: conflicting advice goes to the CTO agent.
- 4.5 plan skill: name the file and concern for a closer review pass.
- 4.6 test-fix-loop: commit through ship; manual commit does not skip review.
- 4.7 runbook bug-fixer gate table rows.
- 4.8 review skill Introduction paragraph citing the two rules by id.

## Phase 5 — Verification

- 5.1 Run the suites in plan order, one at a time, each with `</dev/null`.
- 5.2 Run the infra-step lint and markdownlint on every edited Markdown file; read exit codes on their own line.
- 5.3 Residual grep for the retired review phrases; merge-base diff proves AGENTS files, rulesets and workflows are untouched.
- 5.4 PR body: first line says merging mutates no production system; `Ref #10205`, `Ref #10136`; stop before merge.

## Deepen-plan hardening (applies inside Phases 1 to 3)

- H.1 Runbook intro: verifier exit 0 for form (a), owner's own session turn for form (b), delegable list A0/A1/A3/A4 (A2 under A3), unlisted acts owner-human, A1 delegable only without confirm or rollback_ack inputs and without sole-copy loss, A1b approval never delegable, "satisfies A1" carries its tls-health evidence.
- H.2 go.md Step 1.5: authorAssociation check on the epic body, plan-path rules, Scope items from the CTO and the owner only, trigger never discharges a hold, headless dedupe against owner or bot issues keyed on the epic number, order ask then render then verify then worktree then CTO writes holds and envelope.
- H.3 ship form: cite the envelope, run verify with `--envelope`, `--audit --at` for acts that already ran, exclusion clause, a failed verify makes the bullet an operator step.
