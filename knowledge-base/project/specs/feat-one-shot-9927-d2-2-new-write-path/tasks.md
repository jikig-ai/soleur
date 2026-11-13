# Tasks - #9927 step D2-2 (Ref #12158)

- [x] File revisit tracker #12738 for the new token
- [ ] `apps/web-platform/infra/inngest-arm-write-token.tf`: `doppler_service_token.inngest_cutover_write` + `output "inngest_cutover_write_token"` (sensitive)
- [ ] `.github/workflows/apply-web-platform-infra.yml`: `-target=doppler_service_token.inngest_cutover_write`
- [ ] `.github/workflows/cutover-inngest.yml`: new-secret export step + `write_token_stale` check step (rollback/resume only)
- [ ] `scripts/cutover-inngest.sh`: rollback/resume arms consume `DOPPLER_TOKEN_INNGEST_CUTOVER_WRITE`
- [ ] `knowledge-base/project/specs/feat-one-shot-9927-d2-2-new-write-path/relay-inngest-write-token.sh` (generated-operator-script v2)
- [ ] `tests/scripts/test-relay-inngest-write-token-12158.sh` + registration
- [ ] `tests/scripts/test-infra-privileged-tier-census.sh`: environment-scoped-name clause
- [ ] `apps/web-platform/infra/cutover-inngest-workflow.test.sh`: new pins + floor bump
- [ ] `scripts/followthroughs/inngest-write-token-revisit-12738.sh` + `.test.sh` + registration
- [ ] ADR-241 amendment log entry; `inngest-server.md` runbook note
- [ ] Affected tests green; PR to merge; verify apply run names the new resource
- [ ] Post-merge: enrol tracker #12738 (directive + label); report next owner-go (relay run + live proof)
