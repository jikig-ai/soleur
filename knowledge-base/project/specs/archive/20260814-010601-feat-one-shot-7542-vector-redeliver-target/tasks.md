# Tasks — `apply_target=vector-redeliver`

Derived from
`knowledge-base/project/plans/2026-08-13-infra-vector-redeliver-apply-target-plan.md`.
Phase order is load-bearing: the gate is a contract consumed by both the workflow and the test,
so it lands before either consumer.

## Phase 0 — Preconditions

- [ ] 0.1 Re-run the premise probe: `gh run list --workflow=apply-web-platform-infra.yml --branch main --limit 3`
      still shows the destroy-guard halt with `Plan: 5 to add, 1 to change, 1 to destroy`.
- [ ] 0.2 Read `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` and determine
      whether it enumerates member jobs (open check F4). If it does, the new job must be
      registered there.
- [ ] 0.3 Confirm `scripts/betterstack-query.sh` CLI shape via `--help` and one existing caller;
      capture the exact query dialect for the runbook (CLI-verification gate).
- [ ] 0.4 Confirm the cat-deploy-state webhook invocation shape and that its payload carries
      `vector_journal_tail` and `journald_storage.persistent`.
- [ ] 0.5 Confirm no ADR is required (see plan Architecture Decision: the trigger does not fire).

## Phase 1 — The gate (contract first)

- [ ] 1.1 Create `tests/scripts/lib/vector-redeliver-gate.sh`, modelled on
      `tests/scripts/lib/inngest-host-replace-gate.sh`.
- [ ] 1.2 Idempotent `plan-gate-preamble.sh` source behind the `declare -F` guard.
- [ ] 1.3 `plan_gate_assert_readable` + `plan_gate_assert_classifiable` as the function's first
      statements, each `|| return 1`.
- [ ] 1.4 Single `jq -n --slurpfile p` emitting four counters: `vector_out_of_scope_changes`,
      `host_destroyed`, `nested_removals`, `journald_delivered`.
- [ ] 1.5 `allow` is the single-member list `["terraform_data.journald_persistent"]`, matched with
      `IN(.address; allow[])`.
- [ ] 1.6 `journald_delivered` counts sorted actions `["create","delete"]` **or** `["create"]`
      (F2 — the stranded-recovery shape).
- [ ] 1.7 `plan_gate_assert_numeric` over all four counters before any comparison.
- [ ] 1.8 PASS iff `oos==0 && host_destroyed==0 && nested_removals==0 && journald_delivered==1`.
- [ ] 1.9 Distinct ABORT messages per mode, including the "nothing to redeliver — the committed
      vector.toml already matches state" message for `journald_delivered==0`.

## Phase 2 — Mutation-matrix suite

- [ ] 2.1 Create `tests/scripts/test-vector-redeliver-gate.sh` using
      `tests/scripts/lib/gate-suite-harness.sh` for synthesized fixtures.
- [ ] 2.2 Implement PASS cases T1–T4 (replace shape, bare-create shape, no-op siblings, `read`
      data-source entry).
- [ ] 2.3 Implement RED cases M1–M8, one assertion per named counter/message.
- [ ] 2.4 Implement the wiring assertions T13/T14 and the non-vacuity floor T15.
- [ ] 2.5 Register in `scripts/test-all.sh` gate cluster.

## Phase 3 — Workflow job

- [ ] 3.1 Add `vector-redeliver` to the `apply_target` `options:` list and a short clause to its
      description. Do NOT touch the `confirm` input description.
- [ ] 3.2 Add the `vector_redeliver` job with
      `if: github.event_name == 'workflow_dispatch' && inputs.apply_target == 'vector-redeliver'`.
- [ ] 3.3 `concurrency: {group: web-1-swap, cancel-in-progress: false}` (F4). No `environment:`.
- [ ] 3.4 Job header comment: real gate chain (menu-ack dispatch = authorization; `confirm` =
      typo-guard; plan-reading gate = mechanical protection), plus the `REDELIVER-VECTOR` token.
- [ ] 3.5 Steps in order: checkout → setup-terraform → Doppler CLI → typo-guard → ephemeral SSH
      pubkey → backend creds → init → plan `-target=terraform_data.journald_persistent` → gate →
      CF Tunnel SSH bridge → apply the saved `tfplan`.
- [ ] 3.6 Verify the gate step precedes the bridge step (AC12) and the apply consumes the saved
      plan (AC13).

## Phase 4 — Runbook

- [ ] 4.1 Create `knowledge-base/engineering/operations/runbooks/vector-redeliver.md` matching the
      `ci-ssh-token-replace.md` shape (H1, bullet metadata block, no YAML frontmatter).
- [ ] 4.2 Heading set: When to fire this / Preconditions / Fire it / What it does, and what
      protects each step / If it fails / After it succeeds / Known residual.
- [ ] 4.3 `## If it fails` follows the L3→L7 order from the plan's `## Hypotheses`; no sshd or
      fail2ban hypothesis first.
- [ ] 4.4 `## After it succeeds` carries both off-host verifications; zero `ssh ` invocations.
- [ ] 4.5 `## Known residual` records the deliberate no-`-replace` limitation.
- [ ] 4.6 No runbooks index exists — no index edit required.

## Phase 5 — Guard-suite sweep

- [ ] 5.1 Run `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` (NOT in test-all.sh).
- [ ] 5.2 Run `bun test plugins/soleur/` (covers stock-preflight-coverage + terraform-target-parity).
- [ ] 5.3 Run `plugins/soleur/test/terraform-target-parity.test.ts` (F1).
- [ ] 5.4 Run `bash tests/scripts/test-destroy-guard-regex-parity.sh`.
- [ ] 5.5 Run `actionlint` on the workflow; `bash -c` each new `run:` snippet.
- [ ] 5.6 Run `bash scripts/test-all.sh`.

## Phase 6 — Ship

- [ ] 6.1 PR body uses `Closes #7542`.
- [ ] 6.2 **Merge commit carries a line containing exactly `[skip-web-platform-apply]`** (AC23).
- [ ] 6.3 **Merge commit must NOT carry `[ack-destroy]`** (AC24).

## Phase 7 — Post-merge (dispatch-gated)

- [ ] 7.1 Dispatch `apply_target=vector-redeliver confirm=REDELIVER-VECTOR reason=...`; confirm
      the gate line reports all-zero counters with `journald_delivered=1`.
- [ ] 7.2 Off-host verification: Better Stack shows the #7228 `SyslogIdentifier`s from web-1, and
      the cat-deploy-state webhook reports `vector_journal_tail` non-empty +
      `journald_storage.persistent=true`.
- [ ] 7.3 `gh issue close 7542` only after 7.1 and 7.2 both hold.
