---
title: "chore(ops): mirror community-monitor secrets prd_scheduled to prd Doppler"
type: fix
date: 2026-05-26
classification: ops-only-prod-write
lane: procedural
brand_survival_threshold: none
github_issue: 4466
parent_issue: 3948
---

# chore(ops): Mirror community-monitor secrets prd_scheduled -> prd Doppler

## Enhancement Summary

**Deepened on:** 2026-05-26
**Sections enhanced:** 3 (IaC justification, Acceptance Criteria, Risks)
**Gates passed:** Phase 4.6 (User-Brand Impact), Phase 4.7 (Observability — skip: pure-docs), Phase 4.8 (PAT halt — no match)

### Key Improvements
1. Verified `DOPPLER_TOKEN_WRITE` is scoped to `prd_terraform` only — cannot write to `prd`; AC3 automation-infeasibility justification confirmed
2. Verified all 7 secrets consumed at `cron-community-monitor.ts:261-267` via `buildSpawnEnv` allowlist; runtime injection confirmed at `inngest-bootstrap.sh:147`
3. Confirmed IaC-routing-ack is correct — vendor-minted credentials do not fit `doppler_secret` + `random_id` TF pattern

### Deepen-Plan Verification Results
- PR #4460: MERGED — title matches (community-monitor Inngest migration)
- Issue #3948: OPEN — title matches (TR9 group-(c) agent-loop crons)
- Issue #4466: OPEN — title matches (mirror secrets follow-up)
- Labels `semver:patch`, `priority/p1-high`, `domain/operations`: all exist
- Code refs `cron-community-monitor.ts:261-267`, `inngest-bootstrap.sh:147`: verified at HEAD
- Learning refs: both files exist at cited paths
- No AGENTS.md rule IDs cited (none to verify)
- No PAT-shaped variables detected

## Overview

TR9 PR-11 (#4460) migrated `scheduled-community-monitor` from GitHub Actions to the
Inngest cron substrate. The GHA workflow consumed secrets from `prd_scheduled` Doppler
config; the Inngest handler on Hetzner consumes `prd` Doppler config
(`inngest-bootstrap.sh:147`: `doppler run --project soleur --config prd`).

Seven community-platform secrets exist in `prd_scheduled` but NOT in `prd`. Until
mirrored, the daily 08:00 UTC fire detects "platforms disabled" and files a
`[Scheduled] Community Monitor - FAILED` issue.

| Secret | prd_scheduled | prd |
|--------|:---:|:---:|
| `DISCORD_WEBHOOK_URL` | present | missing |
| `DISCORD_BOT_TOKEN` | present | missing |
| `DISCORD_GUILD_ID` | present | missing |
| `BSKY_HANDLE` | present | missing |
| `BSKY_APP_PASSWORD` | present | missing |
| `LINKEDIN_ACCESS_TOKEN` | present | missing |
| `LINKEDIN_PERSON_URN` | present | missing |

### Why not Terraform?

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

These 7 secrets are **vendor-minted external credentials** (Discord bot token, Bluesky
app password, LinkedIn OAuth token) — NOT Terraform-generatable random values. They
were created by the operator in each platform's dashboard and stored in `prd_scheduled`
via the Doppler UI/CLI. The codebase precedent for TF-managed Doppler secrets
(`inngest.tf` `doppler_secret` resources) is for **TF-generated** values (via
`random_id`) with `ignore_changes = [value]`.

Adding 7 `doppler_secret` resources with empty-string defaults + `terraform import`
would create IaC-managed shells around secrets whose lifecycle is entirely
vendor-dashboard-driven (rotation happens at Discord/Bluesky/LinkedIn, not via
`terraform taint`). The cost/complexity of maintaining these in state exceeds the
benefit for secrets that rotate on vendor-specific schedules.

The Doppler CLI mirror approach is the correct IaC-compliant pattern for this class:
**one-time cross-config copy of vendor-minted credentials**.

## User-Brand Impact

- **If this lands broken, the user experiences:** daily GitHub issues titled `[Scheduled] Community Monitor - FAILED` — the accepted failure mode documented in #4466. No silent data loss.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user data exposure — these are operator-owned platform credentials (Discord bot, Bluesky account, LinkedIn page). Leak vector is Doppler config access, already governed by workspace-level RBAC.
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: operator-owned platform API credentials with no user PII; leak blast radius is service disruption, not user data exposure`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: PR body contains `Ref #4466` (not `Closes` — issue closure is post-merge after verification)
- [ ] AC2: This plan file is committed on the feature branch

### Post-merge (operator)

- [ ] AC3: Run the Doppler CLI mirror loop (issue recipe) to copy all 7 secrets from `prd_scheduled` to `prd`:
  ```
  Automation: not feasible because Doppler CLI requires operator-authenticated session
  with workplace-level write access; no CI pipeline has prd write credentials for
  arbitrary secret creation. The existing DOPPLER_TOKEN_WRITE (apps/web-platform/infra/
  doppler-write-token.tf) is scoped to a single config, not cross-config copy.
  ```
- [ ] AC4: Verify count — `doppler secrets -p soleur -c prd --only-names` returns all 7 community secrets (grep count = 7)
- [ ] AC5: Round-trip equality probe — `diff` between `prd_scheduled` and `prd` values for at least `DISCORD_WEBHOOK_URL` returns empty (no diff)
- [ ] AC6: Next 08:00 UTC Inngest fire succeeds (no FAILED issue created). Verify via `gh issue list --label scheduled-community-monitor --state open --json number,title,createdAt`
- [ ] AC7: Close #4466 after AC6 is verified: `gh issue close 4466 --reason completed`

## Implementation Phases

### Phase 1: Create plan + PR (code change)

This is a **docs-only PR** — the only committed artifact is this plan file. The actual
remediation is a post-merge operator action (Doppler CLI commands).

1. Commit this plan file
2. Open PR with `Ref #4466` in body, label `semver:patch` + `priority/p1-high` + `domain/operations`
3. Mark PR ready for review

### Phase 2: Post-merge operator action (Doppler CLI)

Run the resolution recipe from #4466 in an operator-authenticated Doppler session:

```bash
for K in DISCORD_WEBHOOK_URL DISCORD_BOT_TOKEN DISCORD_GUILD_ID BSKY_HANDLE BSKY_APP_PASSWORD LINKEDIN_ACCESS_TOKEN LINKEDIN_PERSON_URN; do
  V=$(doppler secrets get "$K" -p soleur -c prd_scheduled --plain 2>/dev/null)
  if [[ -n "$V" ]]; then
    printf '%s' "$V" | doppler secrets set "$K" -p soleur -c prd >/dev/null
    echo "mirrored $K"
  else
    echo "WARN: $K missing in prd_scheduled (skipped)"
  fi
done
```

Verification:

```bash
# Count: expect 7
doppler secrets -p soleur -c prd --only-names | grep -cE \
  "^DISCORD_(WEBHOOK_URL|BOT_TOKEN|GUILD_ID)$|^BSKY_(HANDLE|APP_PASSWORD)$|^LINKEDIN_(ACCESS_TOKEN|PERSON_URN)$"

# Round-trip equality:
diff <(doppler secrets get DISCORD_WEBHOOK_URL -p soleur -c prd_scheduled --plain) \
     <(doppler secrets get DISCORD_WEBHOOK_URL -p soleur -c prd --plain)
# Expect: empty diff
```

### Phase 3: Post-fire verification

After the next 08:00 UTC Inngest cron fire:

```bash
# Check no new FAILED issue was created
gh issue list --label scheduled-community-monitor --state open \
  --search 'Community Monitor - FAILED in:title' --json number,title,createdAt

# If clean, close the tracking issue
gh issue close 4466 --reason completed
```

## Open Code-Review Overlap

None

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling operational remediation.

## Test Scenarios

- Given all 7 secrets present in `prd_scheduled`, when the mirror loop runs, then all 7 appear in `prd` with identical values
- Given the next 08:00 UTC Inngest fire, when `cron-community-monitor.ts` calls `buildSpawnEnv()`, then `process.env.DISCORD_WEBHOOK_URL` (et al.) are populated and `community-router.sh platforms` detects all 3 platforms enabled
- Given a secret contains special characters (`?`, `&`, `=`, `.`), when piped via `printf '%s'` to `doppler secrets set`, then the value is preserved verbatim (the stdin form avoids shell expansion)

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `prd_scheduled` secrets were rotated/expired since original storage | Low | Medium — platforms fail auth | Verify each platform after mirror: Discord webhook ping, Bluesky login probe, LinkedIn token introspect |
| CI deploy restarts Inngest unit before secrets are mirrored | Low | Low — same accepted failure mode (FAILED issue) | Mirror secrets BEFORE the next `ci-deploy.sh` run, or accept one more FAILED issue |
| `doppler secrets set` stdin form mangles special chars | Very Low | Medium — silent auth failure | Issue recipe uses `printf '%s'` (no trailing newline) and `--plain` (raw value); round-trip diff in AC5 catches mangling |

## Research Insights

**Doppler CLI stdin form verification:**
- The `printf '%s' "$V" | doppler secrets set "$K"` stdin form is the correct pattern for preserving special characters. The `--plain` flag on `doppler secrets get` outputs the raw value without JSON encoding. Per `knowledge-base/project/learnings/2026-03-25-doppler-secret-audit-before-creation.md`, always audit all configs before declaring secrets missing — the issue already did this (verified `prd_scheduled` has all 7).

**DOPPLER_TOKEN_WRITE scope verification:**
- `apps/web-platform/infra/doppler-write-token.tf:42` shows `config = "prd_terraform"` — the CI write token is scoped to `prd_terraform` only, confirming that no automated pipeline can perform the cross-config copy from `prd_scheduled` to `prd`. The operator's personal Doppler CLI session (workplace-scope auth) is required.

**Inngest restart semantics:**
- Per `inngest-bootstrap.sh:147`, the Inngest systemd unit uses `doppler run --project soleur --config prd` which materializes secrets at process start. After mirroring, the next CI deploy (`ci-deploy.sh`) restarts the unit and picks up new secrets. No manual restart is required — the next deploy or the next cron fire (whichever comes first) will consume the mirrored secrets.

## References

- Issue: #4466
- Parent PR: #4460 (TR9 PR-11 community-monitor Inngest migration)
- Parent umbrella: #3948 (TR9 group-(c) agent-loop crons)
- Consumer: `apps/web-platform/server/inngest/functions/cron-community-monitor.ts:261-267` (`buildSpawnEnv` allowlist)
- Runtime injection: `apps/web-platform/infra/inngest-bootstrap.sh:147` (`doppler run --project soleur --config prd`)
- Learning: `knowledge-base/project/learnings/2026-03-25-doppler-secret-audit-before-creation.md`
- Learning: `knowledge-base/project/learnings/2026-05-18-plan-baked-in-operator-ssh-violated-iac-rule.md`
