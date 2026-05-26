---
title: "Tasks — Tenant provisioning skills"
plan: knowledge-base/project/plans/2026-05-26-feat-tenant-provisioning-skills-plan.md
---

# Tasks: Tenant Provisioning Skills

## Phase 0: Shared Setup
- [x] 0.1 Add `provisioning/` to `.gitignore`

## Phase 1: provision-doppler (#3771)
- [x] 1.1 Create `plugins/soleur/skills/provision-doppler/SKILL.md` (12-word description, Art. 32 pre-condition, Sharp Edges)
- [x] 1.2 Create `plugins/soleur/skills/provision-doppler/scripts/provision-doppler.sh`
  - [x] 1.2.1 Arg parsing: `<tenant-slug>`, `<tenant-org>`, `<tenant-repo>`, `--dry-run`
  - [x] 1.2.2 DPA gate: `test -f` + status-column `awk` validation
  - [x] 1.2.3 Idempotency pre-check: `doppler projects | grep "$SLUG"`
  - [x] 1.2.4 Generate `provisioning/<slug>/doppler.tf` (inline R2 backend + `doppler_project` + `doppler_config`)
  - [x] 1.2.5 `--dry-run` mode: print TF, API curl, copy-pasteable apply command
  - [x] 1.2.6 Emit copy-pasteable compound TF apply (credential re-entry pattern)
  - [x] 1.2.7 Operator gate: `read -p "TF apply complete?"`
  - [x] 1.2.8 Verify TF apply: `doppler projects get "$SLUG"`
  - [x] 1.2.9 OIDC service-account via Doppler API curl (two-claim binding)
  - [x] 1.2.10 Smoke-test: verify service account exists + print OIDC local-test limitation warning
  - [x] 1.2.11 Trap handler for teardown on failure
  - [x] 1.2.12 Bootstrap credential revocation reminder on success
- [x] 1.3 Verify: `provision-doppler --dry-run test-tenant test-org test-repo` produces correct output

## Phase 2: provision-cloudflare (#3770)
- [x] 2.1 Create `plugins/soleur/skills/provision-cloudflare/SKILL.md` (12-word description)
- [x] 2.2 Create `plugins/soleur/skills/provision-cloudflare/scripts/provision-cloudflare.sh`
  - [x] 2.2.1 Arg parsing, DPA gate, idempotency check
  - [x] 2.2.2 Generate `provisioning/<slug>/cloudflare.tf` (4 permission groups + sensitive output block)
  - [x] 2.2.3 `--dry-run` mode with full preview
  - [x] 2.2.4 Emit compound apply + operator gate
  - [x] 2.2.5 Token extraction pipeline: `terraform output -raw | (read -r T; curl verify)` (no scrollback)
  - [x] 2.2.6 Trap handler + teardown + revocation reminder
- [x] 2.3 Verify: `provision-cloudflare --dry-run test-tenant zone-id acct-id` correct output

## Phase 3: provision-hetzner (#3769)
- [x] 3.1 Create `plugins/soleur/skills/provision-hetzner/SKILL.md` (13-word description)
- [x] 3.2 Create `plugins/soleur/skills/provision-hetzner/scripts/provision-hetzner.sh`
  - [x] 3.2.1 Arg parsing, DPA gate, guided Console instructions
  - [x] 3.2.2 Write-class smoke-test with trap: `probe-provision-<slug>`, cx11, cleanup on EXIT/INT/TERM
  - [x] 3.2.3 Distinct error messages for create-fail vs delete-fail
  - [x] 3.2.4 Teardown on every non-zero exit
- [x] 3.3 Verify: `provision-hetzner --dry-run test-tenant` correct output

## Phase 4: provision-github (#3772)
- [x] 4.1 Create `plugins/soleur/skills/provision-github/SKILL.md` (12-word description)
- [x] 4.2 Create `plugins/soleur/skills/provision-github/scripts/provision-github.sh`
  - [x] 4.2.1 Arg parsing, DPA gate, idempotency check (`gh repo view`)
  - [x] 4.2.2 Resolve org-id: `gh api /orgs/<org> --jq .id`
  - [x] 4.2.3 Generate `provisioning/<slug>/github.tf` with `token` auth block + reviewer deployment policy
  - [x] 4.2.4 Emit compound apply + operator gate
  - [x] 4.2.5 Human consent gate for App install (with numeric org-id URL)
  - [x] 4.2.6 Verify install permissions via `gh api`
  - [x] 4.2.7 Teardown + bypass_actors sweep reminder
- [x] 4.3 Verify: `provision-github --dry-run test-tenant test-org reviewer` correct output

## Phase 5: Runbook Update
- [x] 5.1 Add skill references + TF notes to runbook Steps 1, 2, 3, 4, 7

## Verification
- [x] 6.1 `bun test plugins/soleur/test/components.test.ts` passes (budget: ~1943/1950)
- [x] 6.2 All 4 `--dry-run` modes produce complete operator preview
- [x] 6.3 All 4 DPA gates reject missing file, invalid status, and missing slug
