# Tasks: feat-one-shot-3924 — R2 Lock Rules GDPR override driver

Derived from `knowledge-base/project/plans/2026-05-17-feat-r2-lock-rules-gdpr-override-plan.md` (post-deepen).

## Phase 0 — Preconditions

- [ ] **0.1** Confirm worktree + branch (`feat-one-shot-3924`, `.worktrees/feat-one-shot-3924`).
- [ ] **0.2** Verify deps on PATH: `bash`, `jq`, `curl`, `aws`, `doppler`, `gh`, `openssl`, `shellcheck`. Add `bash -n` as gate (no install needed; built-in).
- [ ] **0.3** Read canonical Lock Rule shape from `apps/cla-evidence/infra/object_lock.tf:31-86`. Confirm `MIN_LOCK_SECONDS=315360000` at `apps/cla-evidence/infra/main.test.sh:33`.
- [ ] **0.4** `gh pr list --state open --search "cla-evidence runbook"` — confirm no scope-overlapping PR.

## Phase 1 — RED Tests

- [ ] **1.1** Write `apps/cla-evidence/scripts/fixtures/lock-rule-canonical.json` with canonical 1-rule body matching `object_lock.tf:33-40` (id, enabled:true, prefix:"", condition:{type:"Age", maxAgeSeconds:315360000}).
- [ ] **1.2** Write `apps/cla-evidence/scripts/gdpr-override.test.sh` with 11 cases (a-k):
    - [ ] 1.2.a — Shape A happy path (`--shape=enabled-false`).
    - [ ] 1.2.b — Shape B happy path (`--shape=age-1s`).
    - [ ] 1.2.c — Shape C happy path (`--shape=narrow-prefix --I-have-verified-precedence`).
    - [ ] 1.2.d — GET success:false → abort before PUT, no tombstone, do revoke.
    - [ ] 1.2.e — DELETE 403 → best-effort restore, no tombstone, do revoke.
    - [ ] 1.2.f — Restore fails after DELETE → CRITICAL annotation, no self-revoke (operator needs token).
    - [ ] 1.2.g — Missing required env vars → exit 64 with `::error::usage:`.
    - [ ] 1.2.h — Shape C without `--I-have-verified-precedence` → exit 64.
    - [ ] 1.2.i — PRIOR_SHA not 64-char hex → exit 64 before any PUT.
    - [ ] 1.2.j — Token-value fingerprint never appears in BASH_XTRACEFD output (anchored on value, not env-var name).
    - [ ] 1.2.k — DELETE stub env does NOT contain CF_ADMIN_TOKEN; PUT stub env DOES.
- [ ] **1.3** Run suite — confirm RED. Commit `test(cla-evidence): RED gdpr-override dry-run suite (#3924)`.

## Phase 2 — GREEN Driver

- [x] **2.1** Scaffold `apps/cla-evidence/scripts/gdpr-override.sh` (set -euo pipefail; color helpers; step counter — match `bootstrap.sh`).
- [x] **2.2** Implement arg parsing: `--help`, `--dry-run`, `--shape={enabled-false|age-1s|narrow-prefix}`, `--I-have-verified-precedence`, env validation.
- [x] **2.3** Implement admin-token verify (`curl /user/tokens/verify`), capture `result.id` for self-revoke; validate `status == "active"`.
- [x] **2.4** Install `trap '_cleanup_partial_override "$snapshot"' ERR` BEFORE the PUT-disable (pattern from `sentinel-pr.sh:167-192`).
- [x] **2.5** GET lock rules; jq-assert `success:true && rule_count >= 1 && maxAgeSeconds >= 315360000` BEFORE proceeding (mirrors `main.test.sh:96-110`). Save canonical snapshot to `$WORK/snapshot.json`.
- [x] **2.6** PUT modified rules per `--shape=`. Body always wrapped as `{"rules":[...]}` (bare-array → HTTP 400).
- [x] **2.7** DELETE object via `doppler run -p soleur -c prd_cla -- aws s3api delete-object --bucket "$R2_CLA_EVIDENCE_BUCKET" --key "$TARGET_KEY"`. Bearer token NOT present in this step's env.
- [x] **2.8** PUT-restore from `$WORK/snapshot.json` (byte-equal). Verify via `bash apps/cla-evidence/infra/main.test.sh --live --strict-rule-count`.
- [x] **2.9** Clear `trap - ERR` only after restore succeeds.
- [x] **2.10** Write tombstone via `doppler run -p soleur -c prd_cla -- aws s3api put-object` using §7.4 schema (`schema_version:"1.0"`). PRIOR_SHA validation enforced at entry.
- [x] **2.11** Self-revoke admin token (`curl -X DELETE /user/tokens/{id}`). Skip if PUT-restore failed.
- [x] **2.12** Extend `apps/cla-evidence/infra/main.test.sh` to recognise `--strict-rule-count` flag.
- [x] **2.13** Run test suite until all 11 cases PASS. Run `bash -n` + `shellcheck` (AC13). Commit `feat(cla-evidence): gdpr-override.sh driver + dry-run suite (#3924)`.

## Phase 3 — Runbook Rewrite

- [x] **3.1** Read full runbook; note §7.2, §7.4, §7.5, §7.6, §7.7 verbatim (preserved unchanged).
- [x] **3.2** Drop runbook-header stale banner (lines ~7-9).
- [x] **3.3** Rewrite §7.1: admin-token mint scope (Account → R2 → Edit + User → API Tokens → Edit), env-var export, driver `--help` reference, copy-pasteable invocation.
- [x] **3.4** Rewrite §7.3: canonical driver invocation + 5-bullet flow enumeration; drop all `<details>` historical blocks.
- [x] **3.5** Run cross-artifact drift gate (AC13b): `git grep -nl 'Object Lock Governance\|--bypass-governance-retention' knowledge-base/engineering/ops/runbooks/ docs/ apps/ plugins/` — assert zero hits outside learnings/plans/specs.
- [x] **3.6** Re-verify legal-prose parity (AC8) via awk flag-pattern diff.
- [x] **3.7** Commit `docs(runbook): rewrite cla-evidence §7 admin-override for R2 Lock Rules (#3924)`.

## Phase 4 — Verification

- [x] **4.1** Regression-run dry-run suite (all 11 cases PASS; also covered now by `scripts/test-all.sh` discovery → 61/61 suites total).
- [x] **4.2** Walk AC1 → AC15 in order; tick every box (AC15 deferred to post-merge per Plan §AC15 — not automatable).
- [x] **4.3** Run `bash -n` + `shellcheck` final pass (driver + test + main.test.sh — all clean).
- [x] **4.4** PR #3939 updated in lieu of `gh pr create` (PR was pre-existing as `WIP: feat-one-shot-3924`): title set to `feat(cla-evidence): R2 Lock Rules GDPR override driver (#3924)`; body contains `Closes #3924` (not in title); 5 labels applied (`domain/legal`, `domain/engineering`, `type/chore`, `priority/p2-medium`, `follow-through`). Still in draft — mark ready when CI confirms green.

## Post-merge (operator, conditional)

- [ ] **PM.1** First live execution — only when a real GDPR Art. 17 erasure lands AND CLO confirms Art. 17(3)(e) carveout inapplicable. Capture run log to incident ticket.
