# Tasks — R2 has no object versioning: repair the rollback runbook, ADR-006, and the Art. 30 register

Plan: `knowledge-base/project/plans/2026-09-06-chore-r2-rollback-runbook-repair-plan.md`
Issue: #7836 (closes)
Branch: `feat-one-shot-7836-r2-no-object-versioning-rollback`

## Phase 0 — Re-probe (blocking, runs before any edit)

- [ ] 0.1 Export the R2 keys **outside** `--name-transformer tf-var`:
      `export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)`
      and the same for `AWS_SECRET_ACCESS_KEY`.
- [ ] 0.2 Run the probe pair, capturing exit codes on their own line (never through a pipe):
      control `s3api list-objects-v2` (expect rc=0) and `s3api list-object-versions` (expect rc=254
      `NotImplemented`).
- [ ] 0.3 If `list-object-versions` returns rc=0, **STOP** — Cloudflare shipped versioning and the
      plan changes shape from "make the docs true" to "make the claim true". Re-plan, do not edit.
- [ ] 0.4 Record the measured result and its date in the PR body.

## Phase 1 — ADR-006 (the origin of the false claim)

- [ ] 1.1 `## Decision`: drop "with bucket versioning". Keep R2-as-backend, per-app key paths,
      Doppler-first secrets, and the every-new-root rule — all correct and load-bearing.
- [ ] 1.2 `## Consequences`: drop "State loss eliminated via bucket versioning".
- [ ] 1.3 `## Context`: restate "reliable, versioned remote state" as reliable, **locked**, off-host
      remote state — otherwise the ADR reads as a requirement its own decision does not meet (AC6).
- [ ] 1.4 Add the dated amendment note `[2026-09-09 AMENDMENT (#7836): …]` naming the
      `NotImplemented` result, the passing `list-objects-v2` control, and the replacement gesture.
- [ ] 1.5 The note must state the durability gap is **open and tracked** (reference the AC14 issue),
      not that an operator snapshot equals point-in-time recovery.
- [ ] 1.6 Amendment, **not** supersession — the decision did not change; a capability claim attached
      to it was wrong from day one.

## Phase 2 — The runbook (`infra/github/README.md` §`## Phase 5 -- Rollback`)

> Anchor is a literal double hyphen `Phase 5 -- Rollback`, not an em dash.

- [ ] 2.1 Replace steps 1–2 (`list-object-versions`, `copy-object …?versionId=`) with the gesture that
      works: `terraform state pull > /tmp/tfstate.pre-<op>.$(date +%s).json` taken **before** the
      risky apply and kept off-host, restored with `terraform state push`.
- [ ] 2.2 State plainly that R2 provides **no** point-in-time recovery, so taking the snapshot ahead
      of time is the operator's responsibility.
- [ ] 2.3 Fix step 3's command — the AWS keys must be exported **outside**
      `--name-transformer tf-var`, which rewrites `AWS_ACCESS_KEY_ID` to `TF_VAR_aws_access_key_id`
      and breaks R2 backend auth. Preserve the caveat, fix the command (AC3).
- [ ] 2.4 Preserve the `-refresh-only` warning verbatim in meaning (AC4).
- [ ] 2.5 Run every command in the rewritten section as written, read-only where possible.
      `terraform state push` is documented but **never** exercised.

## Phase 3 — Art. 30 register (`knowledge-base/legal/article-30-register.md`, PA12)

- [ ] 3.1 §(f) Retention: remove "prior versions are retained per R2 bucket versioning"; repoint the
      cross-reference at the corrected Phase 5 gesture.
- [ ] 3.2 §(g) TOMs item (4): "R2 backend versioning + TLS" must no longer list versioning. **The TLS
      half is accurate and stays.**
- [ ] 3.3 Use the entry's existing convention: `[2026-09-09 CORRECTION (#7836): this cell previously
      read…]`.
- [ ] 3.4 Record in the PR body that this is a regulated-data surface and that the operator declined
      a separate `/soleur:gdpr-gate` run (AC9) — an explicit decision, not an oversight.

## Phase 4 — Stale spec criteria

- [ ] 4.1 `specs/feat-terraform-state-mgmt/spec.md`: correct the open `- [ ] R2 bucket versioning is
      enabled` — an AC that can never be met.
- [ ] 4.2 `specs/feat-terraform-state-mgmt/tasks.md`: correct the checked
      `- [x] 1.3 Enable bucket versioning — deferred` — marked done for work that never happened.

## Phase 5 — Deferral, sweep, and verification

- [ ] 5.1 File the deferred-capability issue (AC14): automatic **pre-apply** state snapshot to a
      timestamped key in the same bucket, wired into the apply workflows. Include what was deferred,
      why not folded in here, the three re-evaluation criteria from the plan, and a milestone.
- [ ] 5.2 Cross-reference that issue from the ADR-006 amendment note.
- [ ] 5.3 Run the AC10 residual sweep with the **widened** pattern:
      `git grep -in 'versioning\|list-object-versions\|versionId' -- ':!knowledge-base/project/plans' ':!knowledge-base/project/brainstorms' ':!**/archive/**' ':!node_modules'`
      Confirm every survivor is corrected or a deliberate carve-out. The narrow
      `bucket versioning` pattern cannot match PA12 §(g)(4)'s "R2 **backend** versioning".
- [ ] 5.4 Confirm the deliberate carve-outs are untouched: `.github/workflows/apply-sentry-infra.yml`
      (already correct), `specs/feat-one-shot-7650-phase2-sentry-alert-import/tasks.md`, and dated
      plans/brainstorms (point-in-time records).
- [ ] 5.5 AC1: `grep -c 'list-object-versions\|versionId' infra/github/README.md` → `0`.
- [ ] 5.6 AC12: state the measured scope in the PR body — #7836 says every root has an unrunnable
      rollback runbook; **exactly one does**. Four live roots have no rollback section and two have
      no README at all.
- [ ] 5.7 AC13: `markdownlint` passes on every edited file.
- [ ] 5.8 Verify each AC1–AC14 by running its command, not by asserting the phase ran.

## Out of scope (deliberate)

- `.github/workflows/apply-sentry-infra.yml` — already carries the honest form.
- Dated plans, brainstorms, and the #7650 spec tasks — point-in-time records that must cite what was
  believed on their date.
- The pre-apply snapshot capability itself — deferred to the AC14 issue, triaged in the plan's
  `## Alternative Approaches Considered`.
