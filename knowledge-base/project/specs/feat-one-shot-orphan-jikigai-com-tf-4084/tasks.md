---
plan: knowledge-base/project/plans/2026-05-19-infra-cleanup-remove-orphan-jikigai-com-tf-plan.md
issue: 4084
pr: 4088
lane: single-domain
---

# Tasks — infra(cleanup): remove orphan jikigai-com.tf

## Phase 1 — Delete orphan IaC (atomic single commit)

- 1.1. `git rm apps/web-platform/infra/jikigai-com.tf`
- 1.2. Edit `apps/web-platform/infra/variables.tf` — remove the `# --- jikigai.com (LinkedIn Page Verifications, #4046) ---` section comment (lines ~154-159) AND the three variable blocks `cf_zone_id_jikigai_com` (lines ~161-164), `cf_api_token_jikigai_com` (lines ~166-170), `linkedin_page_verification_txt` (lines ~172-176)
- 1.3. Edit `apps/web-platform/infra/main.tf` — remove line 20: `configuration_aliases = [cloudflare.jikigai_com]`. Keep the surrounding `cloudflare = { source = "cloudflare/cloudflare", version = "~> 4.0" }` block
- 1.4. From `apps/web-platform/infra/`, run `terraform fmt -check` — exit 0
- 1.5. From `apps/web-platform/infra/`, run `terraform validate` — exit 0 (this is the catch for the `main.tf:20` removal pairing)
- 1.6. Run `git grep -nE 'jikigai-com\.tf|cf_(api_token|zone_id)_jikigai_com|linkedin_page_verification_txt|cloudflare\.jikigai_com|jikigai_com_redirects|linkedin_verification' apps/web-platform/infra/` — zero matches
- 1.7. Commit: `infra(cleanup): remove orphan jikigai-com.tf (#4084)` with body `Closes #4084` / `Ref #4081` / post-merge note about #4052
- 1.8. Push to feat-one-shot-orphan-jikigai-com-tf-4084 (PR #4088 already open as draft)

## Phase 2 — PR review + ready

- 2.1. Run `/soleur:review` against PR #4088
- 2.2. Resolve any review findings (expected: minimal — file deletion is mechanically simple)
- 2.3. Run `/soleur:qa` if applicable (no test scaffolding to exercise; ACs are mechanical)
- 2.4. `gh pr ready 4088`
- 2.5. `gh pr merge 4088 --squash --auto`

## Phase 3 — Post-merge verification

- 3.1. After CI green + merge, run the canonical Doppler triplet from `apps/web-platform/infra/`:
  ```bash
  export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
  export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
  terraform init -input=false
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan
  ```
- 3.2. Expected result: `No changes. Your infrastructure matches the configuration.` on the soleur.ai-only resource set. Any unrelated drift goes to a separate issue per `hr-menu-option-ack-not-prod-write-auth` — do not expand this PR's scope at apply time
- 3.3. Close sibling issue #4052:
  ```bash
  gh issue close 4052 --reason "not planned" --comment "Closing — based on the same incorrect premise as #4084 (jikigai.com DNS is on Google Cloud DNS, not Cloudflare). The acceptance criteria (enumerate jikigai.com DNS records via Cloudflare MCP) is unworkable for the same reason. Resolved alongside #4084 by removing the orphan jikigai-com.tf entirely (PR #4088)."
  ```
- 3.4. Optional hygiene: verify no leftover Doppler stubs — `doppler secrets --project soleur --config prd_terraform 2>&1 | grep -iE 'JIKIGAI_COM|LINKEDIN_PAGE_VERIFICATION'` returns zero. (Already confirmed zero at plan time per issue body, this is a fail-safe.)

## Phase 4 — Compound learnings

- 4.1. Run `/soleur:compound` to capture any session learnings. Candidate learning: "Issue-body enumerations of orphan-code surfaces can undercount — always grep for the alias name across the full IaC root (`main.tf`'s `configuration_aliases`, etc.) before freezing the file list."
- 4.2. Run `/soleur:ship`
