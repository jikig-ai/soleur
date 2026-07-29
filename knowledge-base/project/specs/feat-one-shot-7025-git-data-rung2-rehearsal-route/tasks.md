# Tasks — gated rung-2 rehearsal route for the git-data birth (#7025)

Plan: `knowledge-base/project/plans/2026-07-29-feat-git-data-rung2-rehearsal-route-plan.md`
Branch: `feat-one-shot-7025-git-data-rung2-rehearsal-route` · PR #7066 · Issue #7025

**Hard constraints for every phase:** do NOT clear the DO-NOT-DISPATCH banner. Do NOT commit
`git-data-rung2-boot-evidence.env`. Do NOT tick ADR-149 item 7. Do NOT edit
`cloud-init-git-data.yml` or any of its nine `file()`-bound payloads (any edit invalidates the
rung-2 hash and, post-birth, costs a destructive host replace under ADR-115).

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Re-derive the live user_data hash (10 inputs) and pin the value in the PR body.
- [ ] 0.2 Read `apps/web-platform/infra/main.tf`; record the exact `terraform` + provider
      version pins the rehearsal root must mirror, and the R2 backend block shape.
- [ ] 0.3 Run `bash scripts/betterstack-query.sh --help`; pin the verified Mode-1 invocation
      form (raw SQL as first positional, no `--since`) into the plan's Research Insights.
- [ ] 0.4 `git grep -c 'REHEARSE-GIT-DATA'` → confirm 0 pre-existing occurrences.
- [ ] 0.5 Read `tests/scripts/test-git-data-birth-readiness-gate.sh` in full before editing the
      lib it exercises (`hr-always-read-a-file-before-editing-it`).

## Phase 1 — Shared hash helper (contract change; lands FIRST)

- [ ] 1.1 RED: add a failing test for `git_data_rung2_user_data_sha256 <cloud-init-path>` to
      `tests/scripts/test-git-data-birth-readiness-gate.sh`.
- [ ] 1.2 GREEN: extract the derivation from `git_data_rung2_rehearsal_gate` into the new
      function in `tests/scripts/lib/git-data-birth-readiness-gate.sh`. Preserve the `< 10`
      fail-closed floor and the ABORT message wording verbatim.
- [ ] 1.3 Re-point `git_data_rung2_rehearsal_gate` at the helper (no inlined duplicate).
- [ ] 1.4 Verify: `bash tests/scripts/test-git-data-birth-readiness-gate.sh` exits 0, and the
      gate still HOLDS (exit 1) with no evidence file present.

## Phase 2 — Evidence-capture script

- [ ] 2.1 RED: `tests/scripts/test-git-data-rung2-evidence-capture.sh` with a stubbed
      `betterstack-query.sh` covering all three states (0 PASS / 1 FAIL / 2 TRANSIENT).
- [ ] 2.2 GREEN: `scripts/followthroughs/git-data-rung2-evidence-capture.sh`.
      - Anchors on `stage:bootcmd_start` BEFORE reading an absent `boot_complete` as a dark
        boot (never read silence as evidence of absence).
      - Captures all three artifacts, each recorded **with the query that retrieved it**.
      - Computes the hash by calling the Phase-1 helper — never hand-rolled.
      - Writes the evidence file ONLY on PASS; supports `--verify-only`.
      - Emits a comment block enumerating every render-var divergence from prod.
- [ ] 2.3 Verify: no evidence file is produced on the FAIL and TRANSIENT arms.

## Phase 3 — Parameterize the #6982 follow-through probe

- [ ] 3.1 Add `--host-name` (default `soleur-git-data`) to
      `scripts/followthroughs/git-data-birth-emitter-6982.sh`.
- [ ] 3.2 Verify: invoking with no arguments still queries `soleur-git-data` byte-for-byte —
      the scheduled sweeper passes no arguments.

## Phase 4 — Rehearsal Terraform root

- [ ] 4.1 Create `apps/web-platform/infra/rung2-rehearsal/{main,variables,rehearsal,outputs}.tf`.
      Backend key `web-platform/rung2-rehearsal.tfstate` (`hr-every-new-terraform-root-must-include-an`).
- [ ] 4.2 No `default` on any secret-bearing variable (`hr-tf-variable-no-operator-mint-default`).
- [ ] 4.3 Render from `${path.module}/../cloud-init-git-data.yml` + the same nine payloads.
      Duplicate `local.git_data_rationale_strip` byte-for-byte.
- [ ] 4.4 Zero-rule deny-all `hcloud_firewall` + attachment; real throwaway plaintext AND LUKS
      volumes (a stub id makes `luks_mounted=no`, i.e. the FAIL arm).
- [ ] 4.5 Extend `apps/web-platform/infra/git-data-render-strip-parity.test.sh` to the third copy.
- [ ] 4.6 Verify AC7: `grep -cE 'hcloud_(server|volume|firewall)\.git_data\b|terraform_remote_state'
      apps/web-platform/infra/rung2-rehearsal/*.tf` == 0.

## Phase 5 — Gated workflow

- [ ] 5.1 `.github/workflows/git-data-rung2-rehearsal.yml`, `workflow_dispatch` only.
- [ ] 5.2 Inputs: `confirm` (typo-guard `REHEARSE-GIT-DATA`), `dry_run` (default **true**),
      `fault_injection` (default **false**).
- [ ] 5.3 `environment: web-platform-infra-apply` (non-empty reviewer set, DP-11 F8);
      `concurrency: git-data-rung2-rehearsal`, `cancel-in-progress: false`.
- [ ] 5.4 SHA-pin every action; route untrusted inputs through `env:`, never `${{ }}` inside a
      `run:` body.
- [ ] 5.5 `dry_run=true` arm: render + plan + assert the plan creates only rehearsal addresses
      and destroys nothing. Stop there.
- [ ] 5.6 `dry_run=false` arm: apply → poll → capture → teardown `if: always()` → post-teardown
      Hetzner API assertion that no rehearsal-prefixed server survives.
- [ ] 5.7 Evidence lands as a workflow artifact + a PR. **Never** auto-commit to `main`.
- [ ] 5.8 Verify: `actionlint .github/workflows/git-data-rung2-rehearsal.yml` clean; embedded
      `run:` shell checked via `bash -c '<snippet>'` (never `bash -n` on the `.yml`).

## Phase 6 — Tests + CI registration

- [ ] 6.1 `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` (root purity, input
      defaults, environment declaration, no-prod-target).
- [ ] 6.2 Register it as a `run: bash …` step in `.github/workflows/infra-validation.yml` —
      the suite list is DERIVED from that workflow.
- [ ] 6.3 Extend `plugins/soleur/test/terraform-target-parity.test.ts`: the rehearsal root is
      outside every shared-root `-target` set; the new workflow targets no prod `git_data` address.
- [ ] 6.4 Verify: `bash apps/web-platform/infra/run-registered-suites.sh --list` lists the new
      suite with ZERO orphans; then the full run exits 0.

## Phase 7 — Docs, ADR, C4, premise reconciliation

- [ ] 7.1 `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md` — no SSH
      anywhere in the runbook (`hr-no-ssh-fallback-in-runbooks`).
- [ ] 7.2 Amend ADR-149: rehearsal route exists + shipped unfired; DC-6 (separate root, with
      the two rejected alternatives); the hash-vs-render-vars scope limit; item 8 stays OPEN.
- [ ] 7.3 Fix `gitDataStore`'s description in
      `knowledge-base/engineering/architecture/diagrams/model.c4` — it still claims prose holds
      the route. Then run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] 7.4 Update the `git-data-birth.md` banner **text** (route now exists + how to run it).
      **Do NOT clear the banner.**
- [ ] 7.5 Comment on #7025 recording both corrected premises (rung-2 gate is the binding hold;
      item 7 is dispositioned NOT SATISFIABLE AS WRITTEN, so #7025 owns item 8).

## Exit gate

- [ ] E.1 All 14 pre-merge ACs verified by running each gate's OWN invocation — never a
      hand-enumerated reconstruction of its input set.
- [ ] E.2 Confirm `git-data-rung2-boot-evidence.env` is absent and BOTH interlocks still HOLD.
- [ ] E.3 `bash scripts/test-all.sh` + `bash apps/web-platform/infra/run-registered-suites.sh`
      both green (test-all does NOT cover the infra suites — both are required).
