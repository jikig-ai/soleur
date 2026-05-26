---
title: "Tasks — Tenant provisioning skills"
plan: knowledge-base/project/plans/2026-05-26-feat-tenant-provisioning-skills-plan.md
---

# Tasks: Tenant Provisioning Skills

## Phase 0: Shared Setup
- [ ] 0.1 Add `provisioning/` to `.gitignore`

## Phase 1: provision-doppler (#3771)
- [ ] 1.1 Create `plugins/soleur/skills/provision-doppler/SKILL.md` (12-word description, Art. 32 pre-condition, Sharp Edges)
- [ ] 1.2 Create `plugins/soleur/skills/provision-doppler/scripts/provision-doppler.sh`
  - [ ] 1.2.1 Arg parsing: `<tenant-slug>`, `<tenant-org>`, `<tenant-repo>`, `--dry-run`
  - [ ] 1.2.2 DPA gate: `test -f` + status-column `awk` validation
  - [ ] 1.2.3 Idempotency pre-check: `doppler projects | grep "$SLUG"`
  - [ ] 1.2.4 Generate `provisioning/<slug>/doppler.tf` (inline R2 backend + `doppler_project` + `doppler_config`)
  - [ ] 1.2.5 `--dry-run` mode: print TF, API curl, copy-pasteable apply command
  - [ ] 1.2.6 Emit copy-pasteable compound TF apply (credential re-entry pattern)
  - [ ] 1.2.7 Operator gate: `read -p "TF apply complete?"`
  - [ ] 1.2.8 Verify TF apply: `doppler projects get "$SLUG"`
  - [ ] 1.2.9 OIDC service-account via Doppler API curl (two-claim binding)
  - [ ] 1.2.10 Smoke-test: verify service account exists + print OIDC local-test limitation warning
  - [ ] 1.2.11 Trap handler for teardown on failure
  - [ ] 1.2.12 Bootstrap credential revocation reminder on success
- [ ] 1.3 Verify: `provision-doppler --dry-run test-tenant test-org test-repo` produces correct output

## Phase 2: provision-cloudflare (#3770)
- [ ] 2.1 Create `plugins/soleur/skills/provision-cloudflare/SKILL.md` (12-word description)
- [ ] 2.2 Create `plugins/soleur/skills/provision-cloudflare/scripts/provision-cloudflare.sh`
  - [ ] 2.2.1 Arg parsing, DPA gate, idempotency check
  - [ ] 2.2.2 Generate `provisioning/<slug>/cloudflare.tf` (4 permission groups + sensitive output block)
  - [ ] 2.2.3 `--dry-run` mode with full preview
  - [ ] 2.2.4 Emit compound apply + operator gate
  - [ ] 2.2.5 Token extraction pipeline: `terraform output -raw | (read -r T; curl verify)` (no scrollback)
  - [ ] 2.2.6 Trap handler + teardown + revocation reminder
- [ ] 2.3 Verify: `provision-cloudflare --dry-run test-tenant zone-id acct-id` correct output

## Phase 3: provision-hetzner (#3769)
- [ ] 3.1 Create `plugins/soleur/skills/provision-hetzner/SKILL.md` (13-word description)
- [ ] 3.2 Create `plugins/soleur/skills/provision-hetzner/scripts/provision-hetzner.sh`
  - [ ] 3.2.1 Arg parsing, DPA gate, guided Console instructions
  - [ ] 3.2.2 Write-class smoke-test with trap: `probe-provision-<slug>`, cx11, cleanup on EXIT/INT/TERM
  - [ ] 3.2.3 Distinct error messages for create-fail vs delete-fail
  - [ ] 3.2.4 Teardown on every non-zero exit
- [ ] 3.3 Verify: `provision-hetzner --dry-run test-tenant` correct output

## Phase 4: provision-github (#3772)
- [ ] 4.1 Create `plugins/soleur/skills/provision-github/SKILL.md` (12-word description)
- [ ] 4.2 Create `plugins/soleur/skills/provision-github/scripts/provision-github.sh`
  - [ ] 4.2.1 Arg parsing, DPA gate, idempotency check (`gh repo view`)
  - [ ] 4.2.2 Resolve org-id: `gh api /orgs/<org> --jq .id`
  - [ ] 4.2.3 Generate `provisioning/<slug>/github.tf` with `token` auth block + reviewer deployment policy
  - [ ] 4.2.4 Emit compound apply + operator gate
  - [ ] 4.2.5 Human consent gate for App install (with numeric org-id URL)
  - [ ] 4.2.6 Verify install permissions via `gh api`
  - [ ] 4.2.7 Teardown + bypass_actors sweep reminder
- [ ] 4.3 Verify: `provision-github --dry-run test-tenant test-org reviewer` correct output

## Phase 5: Runbook Update
- [ ] 5.1 Add skill references + TF notes to runbook Steps 1, 2, 3, 4, 7

## Verification
- [ ] 6.1 `bun test plugins/soleur/test/components.test.ts` passes (budget: ~1943/1950)
- [ ] 6.2 All 4 `--dry-run` modes produce complete operator preview
- [ ] 6.3 All 4 DPA gates reject missing file, invalid status, and missing slug
