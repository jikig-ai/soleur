# Tasks: founder approval cards (#12011)

Plan: `knowledge-base/project/plans/2026-11-03-feat-founder-approval-cards-plan.md`. Four PRs; this branch carries PR-A.

## PR-A — CLI approval card and Method label (branch feat-founder-approval-cards, PR #12012)

- [x] 0.1 Spike (API surface verified 2026-11-03, see plan Research Insights; the live email round trip needs the founder's inbox and stays open as a PR-B precondition): prove an email code can be sent and verified on a throwaway Supabase client on the dev project without touching the user's session (`signInWithOtp` with `shouldCreateUser: false`, then `verifyOtp({type:'email'})`); identical response on send success and failure; record the call shape in the plan's Research Insights
- [x] 1.1 Create `plugins/soleur/skills/brainstorm-techniques/references/approval-card.md` (structure, consequence-before-choices, no default on Enter, `y` refused, frame-18 messages, three-way decision table, reserved classes, `method` vocabulary, assurance-wording ban list, pointer to the `go.md` headless issue)
  - [x] 1.1.1 Link it from `standing-delegation.md` epic-start section
- [x] 2.1 Write failing tests first: `delegation-verify.test.sh` rows for `Method:` (tty-ack valid, `web-session` invalid, unknown invalid, absent valid, verdict identical with and without, admin check not skipped, bot author still rejected, parser removed) with fixtures `delegation-method-tty-ack.md` and `delegation-method-unknown.md`
- [x] 2.2 Implement `render --method tty-ack` and the `Method:` parser in `delegation-verify.sh`
- [x] 3.1 Add the decision-table test (TTY with account, headless with account, no account) for the card messages
- [x] 4.1 Run `bash plugins/soleur/scripts/delegation-verify.test.sh` and the standing-delegation fixtures; run the forbidden-wording grep over `approval-card.md`
- [x] 4.2 Open follow-up work: confirm migration number 184 against `origin/main` before PR-B

## PR-B — Database record, text registry, ADR, C4, legal documents (dark; starts after the spike passes and PR-A merges)

- [x] 5.1 Failing tests first: `migration-184-legal-acceptance.test.ts` (static shape) and behavioural tests for every Guard 3 mutation row
- [x] 5.2 `184_legal_acceptance.sql`, `.down.sql` (refuses while rows exist), `verify/184_legal_acceptance.sql`
- [x] 5.3 Text registry `server/legal-acceptance/texts/` and `canonical.ts`; shared hash fixture asserted in bash and vitest
- [x] 5.4 Art. 30 activity, LIA, attestation record, compliance-posture row, DSAR exclusions, note-field notice; run `soleur:gdpr-gate`
- [x] 5.5 ADR-319 (re-verify ordinal), ADR-309 pointer, read all three `.c4` files, C4 edits, run C4 tests

## PR-C — Web screens and in-place check (behind `approval-queue`)

- [ ] 6.1 Failing tests first: routes (reauth, decide), service, card (states, lock, keyboard, mobile)
- [ ] 6.2 Reauth route and decide route per plan Phase C1
- [ ] 6.3 Page, card, reauth dialog (email code), state derivation, copy file under the CLO sign-off gate
- [ ] 6.4 Sentry alert rule in `apps/web-platform/infra/sentry`

### PR-C carry-over from the PR-B review (ADR-319, CTO ruling 2026-11-04)

- [ ] 6.5 The card route issues the intent with `issue_legal_reauth` (server knows the registry; version comes from the registry entry), requires a web session, and NEVER mints an intent for a runtime-audience token; reopening a card reuses the live intent, a resend passes `p_resend`
- [ ] 6.6 Return the same response for a known and an unknown address on the email-code send (spike: unknown address answers 422 `otp_disabled`); dev OTP is 8 digits, prod 6
- [ ] 6.7 Embed or COPY `server/legal-acceptance/texts/` into the production image (esbuild bundle + Dockerfile copy only `dist/server`) and test the deployed path before any card is built
- [ ] 6.8 Call `claim_legal_reauth_attempt` before the auth service and `mark_legal_reauth_verified` with the returned event id after; add a per-user (not per-key) attempt ceiling and shorten the auth OTP expiry
- [ ] 6.9 Record sequence in the route: the session id passed to issue/claim/mark equals the JWT `session_id` (or `ses_id`) the database reads; sign the throwaway OTP session out; verify the code on a throwaway client so the founder's own session id does not change (the intent is bound to it); derive `p_session_id` exactly as the SQL reads it (`session_id`, else `ses_id`, empty string = absent); handle `code_stale` from claim and `code_expired` from record by reopening the card (a new intent)
- [ ] 6.10 Define the undo of a mistaken Decline (new text version) and show it in the card copy; the deletion/redaction path for a retained row and its note is a counsel + engineering item (PA-40 item 17)

## PR-D — Verify endpoint and gate kind

- [ ] 7.1 Failing tests first: Guard 1 mutation rows and harness rows in `hold-gate-eval.test.sh`; endpoint tests
- [ ] 7.2 Verify endpoint, parameterised `internal-auth.ts`, Terraform secrets, `.env.example`
- [ ] 7.3 `web-acceptance` kind in `hold-gate-eval.sh` with input validation and held-reason output

## Post-merge

- [ ] 8.1 ADR-319 `adopting` -> `accepted` after the first real acceptance
- [ ] 8.2 CLO gate cleared and counsel review before enabling beyond canary
- [ ] 8.3 UX test with a non-technical, non-legal founder (CLI and web)
- [ ] 8.4 Correct roadmap CP2 and place #12011
