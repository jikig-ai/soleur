# Decision Challenges — feat-one-shot-10990-bootstrap-aws-creds

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Adopt the canonical nested `doppler run` loader (outer `soleur-infra-privileged/prd` tf-var, inner `prd_terraform --preserve-env`) for `bootstrap-live-verify.sh`'s apply leg, vs. the minimal `AWS_*` source swap only | technical | pending - assumed: adopt the nested loader — the issue's Fix cites the runbook's canonical local invocation which IS the nested form, and `doppler_token_tf` (the provider write token for `doppler_secret.live_verify_user_password`) exists in Tier B and is plantable in Tier A; no CTO spawn capability on this harness |
| Guard placement: extend `tests/scripts/test-infra-privileged-tier-census.sh` with an `.sh` state-writer limb vs. a new standalone suite | technical | pending - assumed: extend the census — its AC7b already claims the same property over workflows; `.sh` writers are the uncovered member class, and the suite owns the fixture/mutation machinery and is already registered with `apps/` in its affected-paths set |
| Fold the stale-recipe fix in `plugins/soleur/skills/plan/references/plan-sharp-edges.md:140` into this PR vs. defer to a follow-up | technical | pending - assumed: fold in — the mandated `hr-write-boundary-sentinel-sweep-all-write-sites` sweep covers prescribing surfaces; the entry instructs every future drift-remediation plan to reproduce this exact defect |
