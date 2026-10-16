# Pipe-guard selection measurement, 2026-10-16 (origin/main ee8644bded)

Command per path: `bash scripts/test-all.sh --print-selection --paths=<path>`. That command prints one `AFFECTED_SELECTED` line for **every** suite
(about 630 lines; the count varies with the path); a path selects the guard only when the line naming `.claude/hooks/grep-q-pipe-guard.test.sh` has `1` in its third tab-separated field.
An earlier version of this file counted the existence of that line and reported 98 of 98 selected; that was wrong. Controls for the corrected run:
`bogus/not-a-path.txt` gives bit 0 and `scripts/cutover-inngest.sh` gives bit 1.

Population: the guard's own pairs (`pj_join_pairs`), 98 producer files and 97 owner suites. The declared edge regex (field 5 of the `AFFECTED_SELECTED`
line) matches 47 of the producers and 64 of the owner suites; a spot check of 8 of those paths (4 producers, 4 owner suites) gave bit 1 for all 8. The other 51
producers and 33 owner suites were each run through `--print-selection`; every one gave bit 0, with 0 `AFFECTED_FALLBACK` and rc 0.

Result: the guard is NOT selected for 51 of 98 producer files and 33 of 97 owner suites. Tracked in #10447.

| Kind | Path | rc | selected bit | fallback |
|---|---|---|---|---|
| producer | `.github/actions/bot-pr-with-synthetic-checks/action.yml` | 0 | 0 | 0 |
| producer | `.github/actions/cf-tunnel-registry-bridge/action.yml` | 0 | 0 | 0 |
| producer | `.github/actions/cf-tunnel-ssh-bridge/action.yml` | 0 | 0 | 0 |
| producer | `.github/actions/infra-credentials/action.yml` | 0 | 0 | 0 |
| producer | `.github/scripts/mint-inngest-bootstrap-tag.sh` | 0 | 0 | 0 |
| producer | `.github/scripts/validate-infra-templates.sh` | 0 | 0 | 0 |
| producer | `.github/workflows/apply-deploy-pipeline-fix.yml` | 0 | 0 | 0 |
| producer | `.github/workflows/apply-git-data-root-key.yml` | 0 | 0 | 0 |
| producer | `.github/workflows/apply-github-infra.yml` | 0 | 0 | 0 |
| producer | `.github/workflows/apply-inngest-rls.yml` | 0 | 0 | 0 |
| producer | `.github/workflows/board-status-sync.yml` | 0 | 0 | 0 |
| producer | `.github/workflows/build-inngest-config-bundle.yml` | 0 | 0 | 0 |
| producer | `.github/workflows/canary-status.yml` | 0 | 0 | 0 |
| producer | `.github/workflows/ci.yml` | 0 | 0 | 0 |
| producer | `.github/workflows/deploy-inngest-image.yml` | 0 | 0 | 0 |
| producer | `.github/workflows/git-data-cutover.yml` | 0 | 0 | 0 |
| producer | `.github/workflows/git-data-rung2-rehearsal.yml` | 0 | 0 | 0 |
| producer | `.github/workflows/infra-validation.yml` | 0 | 0 | 0 |
| producer | `.github/workflows/restart-inngest-server.yml` | 0 | 0 | 0 |
| producer | `.github/workflows/reusable-release.yml` | 0 | 0 | 0 |
| producer | `.github/workflows/rule-audit.yml` | 0 | 0 | 0 |
| producer | `.github/workflows/scheduled-terraform-drift.yml` | 0 | 0 | 0 |
| producer | `plugins/soleur/hooks/browser-snapshot-credential-guard.sh` | 0 | 0 | 0 |
| producer | `plugins/soleur/hooks/destructive-command-guard.sh` | 0 | 0 | 0 |
| producer | `plugins/soleur/hooks/operator-stage-approval.sh` | 0 | 0 | 0 |
| producer | `plugins/soleur/scripts/lib/operator-script.sh` | 0 | 0 | 0 |
| producer | `plugins/soleur/skills/community/scripts/lib/hmac-sha1-b64.sh` | 0 | 0 | 0 |
| producer | `plugins/soleur/skills/community/scripts/linkedin-setup.sh` | 0 | 0 | 0 |
| producer | `plugins/soleur/skills/community/scripts/x-community.sh` | 0 | 0 | 0 |
| producer | `plugins/soleur/skills/community/scripts/x-setup.sh` | 0 | 0 | 0 |
| producer | `plugins/soleur/skills/flag-create/scripts/create.sh` | 0 | 0 | 0 |
| producer | `plugins/soleur/skills/flag-set-role/scripts/flip.sh` | 0 | 0 | 0 |
| producer | `plugins/soleur/skills/operator-digest/scripts/provision-operator-digest-repo.sh` | 0 | 0 | 0 |
| producer | `plugins/soleur/skills/skill-security-scan/scripts/lib.sh` | 0 | 0 | 0 |
| producer | `scripts/content-publisher.sh` | 0 | 0 | 0 |
| producer | `scripts/followthroughs/ci-push-dedupe-soak-9512.sh` | 0 | 0 | 0 |
| producer | `scripts/followthroughs/workspaces-plaintext-hold-9348.sh` | 0 | 0 | 0 |
| producer | `scripts/followthroughs/zot-log-channel-7440.sh` | 0 | 0 | 0 |
| producer | `scripts/inngest-liveness-classify.sh` | 0 | 0 | 0 |
| producer | `scripts/inngest-probe-heartbeat-feeder.sh` | 0 | 0 | 0 |
| producer | `scripts/lint-dual-lockfile.sh` | 0 | 0 | 0 |
| producer | `scripts/lint-followthrough-varq-ban.sh` | 0 | 0 | 0 |
| producer | `scripts/probe-github-app-mint.sh` | 0 | 0 | 0 |
| producer | `scripts/rotate-supabase-db-credential.sh` | 0 | 0 | 0 |
| producer | `scripts/rule-audit.sh` | 0 | 0 | 0 |
| producer | `scripts/sentry-alert-live-fidelity.sh` | 0 | 0 | 0 |
| producer | `scripts/ship-incident-pir-gate.sh` | 0 | 0 | 0 |
| producer | `scripts/supabase-advisor-scan.sh` | 0 | 0 | 0 |
| producer | `scripts/sweep-followthroughs.sh` | 0 | 0 | 0 |
| producer | `scripts/verify-agent-security-slice1.sh` | 0 | 0 | 0 |
| producer | `scripts/watch-registration-narrowing-9564.sh` | 0 | 0 | 0 |
| owner | `.github/scripts/test/fixtures-validate-infra-templates.sh` | 0 | 0 | 0 |
| owner | `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh` | 0 | 0 | 0 |
| owner | `plugins/soleur/skills/community/test/community-argv.test.sh` | 0 | 0 | 0 |
| owner | `plugins/soleur/test/destructive-command-guard-hook.test.sh` | 0 | 0 | 0 |
| owner | `plugins/soleur/test/flag-detach-shared.test.sh` | 0 | 0 | 0 |
| owner | `plugins/soleur/test/flag-org-scoping-pr2.test.sh` | 0 | 0 | 0 |
| owner | `plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh` | 0 | 0 | 0 |
| owner | `plugins/soleur/test/inngest-config-bundle-mirror.test.sh` | 0 | 0 | 0 |
| owner | `plugins/soleur/test/operator-9321-stages.test.sh` | 0 | 0 | 0 |
| owner | `plugins/soleur/test/operator-ack-guard.test.sh` | 0 | 0 | 0 |
| owner | `plugins/soleur/test/operator-agent-runnable.test.sh` | 0 | 0 | 0 |
| owner | `plugins/soleur/test/operator-digest-provision.test.sh` | 0 | 0 | 0 |
| owner | `plugins/soleur/test/operator-script.test.sh` | 0 | 0 | 0 |
| owner | `plugins/soleur/test/operator-stage-approval-hook.test.sh` | 0 | 0 | 0 |
| owner | `plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh` | 0 | 0 | 0 |
| owner | `plugins/soleur/test/ship-followthrough-directive.test.sh` | 0 | 0 | 0 |
| owner | `scripts/check-cloudflare-token-drift.test.sh` | 0 | 0 | 0 |
| owner | `scripts/check-web-host-escrow-config.test.sh` | 0 | 0 | 0 |
| owner | `scripts/ci-demand-census.test.sh` | 0 | 0 | 0 |
| owner | `scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh` | 0 | 0 | 0 |
| owner | `scripts/followthroughs/web2-luks-live-6931.test.sh` | 0 | 0 | 0 |
| owner | `scripts/followthroughs/workspaces-plaintext-hold-9348.test.sh` | 0 | 0 | 0 |
| owner | `scripts/followthroughs/zot-soak-6122.test.sh` | 0 | 0 | 0 |
| owner | `scripts/inngest-probe-heartbeat-feeder.test.sh` | 0 | 0 | 0 |
| owner | `scripts/lint-dual-lockfile.test.sh` | 0 | 0 | 0 |
| owner | `scripts/lint-workflow-local-action-checkout.test.sh` | 0 | 0 | 0 |
| owner | `scripts/marketplace-drift-check.test.sh` | 0 | 0 | 0 |
| owner | `scripts/rotate-supabase-db-credential.test.sh` | 0 | 0 | 0 |
| owner | `scripts/ship-incident-pir-gate-mutation.test.sh` | 0 | 0 | 0 |
| owner | `scripts/sweep-followthroughs.test.sh` | 0 | 0 | 0 |
| owner | `scripts/test-content-publisher.sh` | 0 | 0 | 0 |
| owner | `scripts/test-jaccard-duplicates.sh` | 0 | 0 | 0 |
| owner | `scripts/watch-registration-narrowing-9564.test.sh` | 0 | 0 | 0 |

## Re-measure recipe

Run from the repo root of a tree with no uncommitted tracked change. The check reads the selected bit, never the presence of the line:

```bash
PJ_ALL="$(git ls-files)"; . <(sed -n '/^# PJ-DERIVE-BEGIN/,/^# PJ-DERIVE-END/p' .claude/hooks/grep-q-pipe-guard.test.sh)
pj_join_pairs | LC_ALL=C sort -u | cut -f1,3 | tr '\t' '\n' | sort -u > paths.txt
for control in bogus/not-a-path.txt scripts/cutover-inngest.sh; do echo "$control"; done > controls.txt
cat controls.txt paths.txt | while read -r p; do
  out="$(bash scripts/test-all.sh --print-selection --paths="$p" 2>&1)"
  bit="$(printf '%s\n' "$out" | awk -F'\t' '$1=="AFFECTED_SELECTED" && $2==".claude/hooks/grep-q-pipe-guard.test.sh" {print $3; exit}')"
  printf '%s\t%s\n' "${bit:-NONE}" "$p"
done
```

The two controls must print `0` (bogus path) and `1` (`scripts/cutover-inngest.sh`); if they do not, the run is void. Count the rows whose first column is `0` for the not-selected population.
