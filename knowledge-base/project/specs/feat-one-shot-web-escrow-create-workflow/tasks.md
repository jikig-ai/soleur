# Tasks - feat-one-shot-web-escrow-create-workflow

Derived from `knowledge-base/project/plans/2026-10-04-feat-web-escrow-create-workflow-plan.md`.
Lane: `cross-domain` (spec lacks a valid `lane:`, defaulted fail-closed). Brand-survival threshold: `single-user incident`.
Offline only: no workflow dispatch, no enabling of `apply-web-platform-infra.yml`, no Doppler or Cloudflare write, no production write.
PR body: `Refs #9377` and `Refs #8609`, never `Closes`. No agent `--admin` merge. Do NOT edit `apply-web-platform-infra.yml`,
`server.tf`, any `git-data*.tf`, `workspaces-luks-header-web.tf`.

## Phase 0 - Baselines and failing suite (RED first)

- [ ] 0.1 Rebase onto `origin/main`; record baseline results of the targeted suites in plan Phase 6 (note any pre-existing red).
- [ ] 0.2 Re-read the learnings the plan cites (the plan dropped researcher entries that did not match their files; re-verify the rest before relying on them).
- [ ] 0.3 Create `apps/web-platform/infra/web-escrow-create-workflow.test.sh` from the forget suite's structure: instrument self-test, structural rows T1-T24 (T20 as one parsed hygiene pass), behavioral rows (validate, gate fixtures, names stub, re-read), mutation battery (Guard 1: 9 rows, Guard 2: 5 rows), pass floor. Confirm RED (workflow absent).

## Phase 1 - Names reader

- [ ] 1.1 Check whether a names-only mode in `scripts/check-web-host-escrow-config.sh` is smaller than a reader; default is not to edit it.
- [ ] 1.2 Create `scripts/web-escrow-create-names.sh` (xtrace refusal, non-empty `TF_VAR_doppler_token_tf` else exit 2, `--only-names` listing of `prd_workspaces_luks_web` tokenised as the checker's `read_names` does, exit 3 on unreadable/empty/no NAME header, redacted 300-byte failure line, names to the out-file only).

## Phase 2 - The workflow

- [ ] 2.1 Create `.github/workflows/apply-web-escrow-create.yml` with the header (including "first-create legality ends once a web-class volume is formatted (#9372 rebirth)", the displacement note, and the never-dispatched-by-the-pipeline note) and steps validate, checkout, setup-terraform, loader, secrets check, dummy ssh public key, backend credentials, init, plan (five targets), gate, names, apply (`if: inputs.plan_only != true`), re-read (same guard), summary (`if: always()`).
- [ ] 2.2 Gate: shared jq filter (plan_ok true, seven counters numeric and zero), inverted allow-set with optional `.change.actions?`, named abort messages including the `doppler_config` message and recovery pointer.
- [ ] 2.3 Suite GREEN; actionlint clean for the new file (`bash scripts/lint-workflows.sh .github/workflows/apply-web-escrow-create.yml`).

## Phase 3 - Registration

- [ ] 3.1 `python3 scripts/regenerate-shard-manifest.py --group infra --incremental --write` (new rows in `suite-shard-legs.tsv` and `suite-durations.tsv`).
- [ ] 3.2 Add the suite to `PROMOTED_FILES` in `scripts/guard-vacuity-floor.test.sh` with a comment in the sibling form; run it.
- [ ] 3.3 Run `.github/scripts/test/test-infra-suite-registration.sh`.

## Phase 4 - Parity-test edits (flag for explicit review in the PR body)

- [ ] 4.1 Edit A: `EXEMPT_PAIR_WORKFLOW` constant, rewritten "NO other workflow FILE" row, new exempt-file structure row. Leave the "NO other job" row and every apply-job row byte-identical.
- [ ] 4.2 Edit B: add the workflow to `MAIN_ROOT_TF_WORKFLOWS`; `found.length` 3 to 4.
- [ ] 4.3 Run `bun test plugins/soleur/test/terraform-target-parity.test.ts`; check `git diff` hunks are only A and B. Rebase again before review and before ready (open PR #9348 touches the file).

## Phase 5 - Documents

- [ ] 5.1 ADR-263: append `## Addendum — 2026-10-04 (#9377)` (D9, rejected alternatives, gate shape, first-create expiry sentence, displacement, counters note, retirement note, CLO follow-through, GDPR gate reminder). Conditional tense for anything not yet run; no claim that web-2 is encrypted.
- [ ] 5.2 `web-host-birth.md` and `web-host-replace.md`: additive subsection under Step 0 (order of steps, green plan-only meaning, expected preflight failure before the mint, recovery decision rule for a names-present abort, `doppler_config` abort, apply failure, supersession step); correct the "push-apply has not created it" attribution; do not edit the checker's CAUSE text. Expect textual conflicts with draft PR #9474.
- [ ] 5.3 C4: read all three `.c4` files, enumerate actors/systems/stores/relationships; reword the `doppler -> hetzner` edge clause (unconditional); regenerate `model.likec4.json` with `scripts/regenerate-c4-model.sh`; run `c4-model-freshness.test.sh`, `c4-render.test.ts`, `c4-count-parity.test.sh`.
- [ ] 5.4 Post the retirement checklist comment on #9372 (every coupled artifact); link it from the ADR addendum.

## Phase 6 - Targeted verification (no full battery)

- [ ] 6.1 Run: the new suite; parity test; `test-infra-privileged-tier-census.sh` (edit only if it flags the new file); `workflow-file-size.test.ts`; `guard-vacuity-floor.test.sh`; `test-infra-suite-registration.sh`; `web-1-swap-concurrency-parity.test.sh`; `c4-count-parity.test.sh`; `web-host-escrow-preflight-census.test.ts`; `lint-guard-contract.py` on the plan; `lint-encryption-posture.py`.
- [ ] 6.2 `git diff --name-only origin/main` shows none of the forbidden files.
- [ ] 6.3 Open the PR body checklist: Refs only, parity-test edits flagged, vectors A-F, "nothing dispatched; each live step needs the owner's per-step authorization".
- [ ] 6.4 Do NOT dispatch any workflow. Post-merge verification is read-only (`gh workflow view` state).
