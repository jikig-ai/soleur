## Post-merge operator tasks

- [ ] **AC-PM1** Create GitHub App per `knowledge-base/operations/runbooks/github-app-provisioning.md` (single manual gate; deferred-automation issue tracked).
- [ ] **AC-PM2** Run canonical Terraform apply triplet: `infra/github-app.tf` + `infra/kb-drift.tf` + `infra/alerts-github-webhook.tf` (operator holds Doppler `prd_terraform` + Cloudflare zone access).
- [ ] **AC-PM3** Doppler `prd_kb_drift_walker` bootstrap (KB_DRIFT_INGEST_SIGNING_KEY + KB_DRIFT_INGEST_URL + KB_DRIFT_OPERATOR_FOUNDER_ID).
- [ ] **AC-PM4** Flip `SOLEUR_FR5_GITHUB_ENABLED=true` in Doppler `prd` **AFTER** PR-G #3947 ships.
- [ ] **AC-PM5** Install GitHub App on test repo; push fake PR; verify Today card within 60s.
- [ ] **AC-PM6** Flip umbrella #3244 AC line 6 `[x]`.
