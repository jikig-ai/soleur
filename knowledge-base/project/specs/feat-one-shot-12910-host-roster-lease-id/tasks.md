# Tasks: feat-one-shot-12910-host-roster-lease-id

Plan: `knowledge-base/project/plans/2026-11-18-fix-host-roster-key-lease-host-id-web2-pre-heal-plan.md` (#12910).
Decisions: `decision-challenges.md` (R1-R4, T1-T11). TDD: failing test first. Single test files only. Scratch goes under `/var/tmp`.

## Phase 1: Setup

- [ ] 1.1 Re-run the read-only roster check (plan Phase 5) and record the booleans in `session-state.md`.
- [ ] 1.2 Confirm the Hetzner metadata `hostname` endpoint path against Hetzner's server-metadata docs.

## Phase 2: Core Implementation

- [ ] 2.1 Verified placement id (plan Phase 1)
  - [ ] 2.1.1 Tests first in `test/host-identity.test.ts`: every `source` value, the T1 collision case, the canary empty IP, and `HOST_KEY_RE` matching `hetzner-176328334`.
  - [ ] 2.1.2 Create the leaf `server/host-roster.ts` (move the pure `loadHostRoster`); `session-router.ts` re-exports it.
  - [ ] 2.1.3 In `server/host-identity.ts`, add `HOST_KEY_RE` and `describeHostIdentity()`, make `resolveHostId()` delegate to it, and rewrite the header comment.
  - [ ] 2.1.4 In `server/index.ts`, add the boot `host_identity source=<enum>` line and the production `reportSilentFallback`.
  - [ ] 2.1.5 Add a production-shaped roster case to `test/session-router.test.ts` and rewrite the roster doc comment.
- [ ] 2.2 Deploy-side key (plan Phase 2)
  - [ ] 2.2.1 Tests first in `infra/ci-deploy.test.sh`: the `file://` metadata fixtures, the exact inverse (`soleur-web-1` gives rc 1), and the stickiness cases.
  - [ ] 2.2.2 Add `resolve_host_key` (3 retries, exact inverse, regex), the T3 abort before the canary, `HOST_KEY`, and the `log_host_key` single `logger` call.
  - [ ] 2.2.3 Add `-e SOLEUR_HOST_KEY="$HOST_KEY"` to prod and `-e SOLEUR_HOST_KEY=` to the canary.
  - [ ] 2.2.4 Give `docker-run-tuple.py` per-surface `SOLEUR_HOST_KEY` values, and add kill rows plus a canary-empty row to `docker-run-tuple.test.sh`.
- [ ] 2.3 Gate A.3 (plan Phase 3)
  - [ ] 2.3.1 Tests first: Guard 1 rows 1-8 and the web-3 must-PASS row in `infra/lb-weight-gate.test.sh`.
  - [ ] 2.3.2 Add the four new A.3 codes to `lb-weight-gate.sh` and update the header and parity comment.
  - [ ] 2.3.3 Derive `SOLEUR_WEB_HOSTS` from `variables.tf` in `lb-weight-gate-with-marker.sh`, add it to `GATE_ENV_ALLOW`, and extend `lb-weight-gate-with-marker.test.sh`.
- [ ] 2.4 Self-stop narrowing (plan Phase 4)
  - [ ] 2.4.1 Tests first: (a) a cold heal emits nothing, (b) a post-heal absent strand is not masked, (c) an escaping pointer emits once.
  - [ ] 2.4.2 Move the emit after the heal and gate it on the re-probed escaping `file-pointer`. Update the "emit sites" comment.
  - [ ] 2.4.3 Add the one-line `isWorkspacesPopulated` comment in `readiness.ts`.
- [ ] 2.5 Add the ADR-068 addendum via `soleur:architecture` (plan Phase 6).

## Phase 3: Testing

- [ ] 3.1 Add Guard 2 (section C8) to `infra/web-hosts-generic.test.sh`: the round-trip census, the 2-key floor, regex parity, the `soleur-web-1` row and no `create_before_destroy`. Raise `MIN_CASES`.
- [ ] 3.2 Run each touched test file alone, and run `inngest-inventory.test.sh` (AC8).
- [ ] 3.3 Run `technical-ruling-gate.sh --branch` (AC10) and repeat the roster read on merge day (AC9).
- [ ] 3.4 Post-merge (plan Phase 7):
  - [ ] 3.4.1 After the pipeline-fix apply, redeploy via `web-platform-release.yml`.
  - [ ] 3.4.2 Verify AC12 in Better Stack, and keep web-2 at weight 0 until it holds (AC12b).
  - [ ] 3.4.3 After the owner-authorized serve, verify AC13.
