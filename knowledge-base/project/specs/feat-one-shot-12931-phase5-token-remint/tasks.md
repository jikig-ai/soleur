# Tasks: Phase 5 token slice - re-mint the old-login read tokens (Ref #12931)

Plan: `knowledge-base/project/plans/2026-11-27-chore-cf-phase5-old-login-token-remint-plan.md`.
Rulings: `knowledge-base/project/specs/feat-one-shot-12931-phase5-token-remint/decision-challenges.md`.
The work phase runs only reads and repository edits; every production act is an `## Operator Holds` line.

## Phase 1: Setup and evidence (read-only)

- [x] 1.1 Re-run the facts reads: verify id prefixes of every holder, the three `cloudflare-readonly.sh` reads on the
  new zone, the names-only census of all Doppler projects (never print a value).
- [x] 1.2 Post the `P5-TOKEN-FACTS` comment on #12931 (Ref only; each search's scope named).
- [x] 1.3 Post the `P5-GH-SECRET` comment on #12983 (repoint the repo secrets to a least-privilege Load Balancing
  read token before Load Balancing returns).

## Phase 2: Tests first

- [x] 2.1 Write `tests/scripts/test-cf-old-login-token-remint-bootstrap.sh` (fixture repo, PATH-stubbed `doppler`,
  `curl`, `gh`; synthesized sentinels) with the Guard 1-3 rows, harness rows and Test Scenarios; a `--mutants` mode.
- [x] 2.2 Register it: `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh` (glob edge), then
  `python3 scripts/regenerate-shard-manifest.py --incremental --write` for both TSVs.

## Phase 3: Core implementation

- [x] 3.1 Generate `bootstrap.sh` with `soleur:operator-bootstrap` (template, v2 header, manifest block, four stages
  `inventory`, `swap`, `holder-copies`, `verify`; account-then-user verify; `SOLEUR_P5_*` markers; `REVOKE_READY`).
- [x] 3.2 Write `knowledge-base/engineering/operations/runbooks/cloudflare-old-login-token-remint.md` (twelve
  sections, hold lines verbatim, Orient step first).
- [x] 3.3 Edit `plugins/soleur/agents/engineering/infra/infra-security.md` (new ids, source line, account verify
  fallback), then regenerate its three harness copies with `sync-grok-agent-compat.ts`, `sync-cursor-name-map.ts`
  and `sync-opencode-adapter.ts` (each then `--check`); never hand-edit the copies.
  Measured at work time: the three copies are pointer stubs that carry no ids; all three `--check` runs exit 0 with
  no regenerated change.
- [x] 3.4 Edit the `cloudflare-readonly.sh` header (drop `2027-02-07`, name `expires_on`).
- [x] 3.5 Edit the `scheduled-followthrough-sweeper.yml` comment (measured fact plus the #12983 precondition).

## Phase 4: Verification

- [x] 4.1 Run AC1-AC9 commands; run `cloudflare-readonly.test.sh`, `components.test.ts`, the new suite and its
  `--mutants`, `lint-orphan-test-suites.sh`, `actionlint`, markdownlint on every edited `.md`.
- [x] 4.2 Confirm the migration runbook is untouched (`git diff --quiet origin/main...HEAD -- <runbook>`).
- [ ] 4.3 PR body: `Ref #12931`, `Ref #12937`, the `## Operator Holds` list, follow-ups #13085 and #13086.

## Phase 5: Post-merge (operator holds; each on its own typed go, except the batched mint go)

- [ ] 5.1 Mint sitting: confirm no Playwright capture flags, read permission groups and old policies, post
  `P5-SCOPE`, mint the three tokens account-owned and named `<key>-soleur-<YYYYMMDD>`, read their policies back
  (exact resource keys), stage `_NEXT`.
- [ ] 5.2 Delete the old `CF_API_TOKEN_AUDIT` copies in `dev_personal` and `dev_scheduled` (CTO F20), then `swap`,
  `holder-copies`, `verify` (three `REVOKE_READY` lines).
- [ ] 5.3 Revoke sitting (old-account-owner login): three revokes, then the three `_PREV` deletes, then the full drift
  run; post `P5-REVOKED` and `P5-PAGERULES-FATE`.
- [ ] 5.4 At migration runbook Phase 3 step 5 (after #12937 clears): the `CF_API_TOKEN_PURGE_PREV` revoke and delete.
