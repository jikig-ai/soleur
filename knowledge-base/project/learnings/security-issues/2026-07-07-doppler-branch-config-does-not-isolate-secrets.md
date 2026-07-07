---
title: 'Doppler branch configs do NOT isolate secrets — true isolation needs a separate project'
date: 2026-07-07
category: engineering
tags: [doppler, secrets, least-privilege, isolation, terraform, zot, registry, tier-limits]
symptoms: [A read token "scoped" to a prd branch config reads the full prd secret set, SUPABASE_SERVICE_ROLE_KEY readable from a supposedly-scoped config, "Your project has reached its limit of 4 environments"]
module: WebPlatform
component: infra
problem_type: security_issue
resolution_type: architecture_fix
root_cause: incorrect_isolation_boundary
severity: high
issues: ['#6122', '#6167']
---

# Doppler branch configs do NOT isolate secrets

## The misconception (asserted 4×, verified 0× before #6122)

Several places in the codebase treated a **Doppler branch config under the `prd`
environment** as a least-privilege boundary — e.g. `prd_registry` (zot),
`prd_git_data`, `prd_kb_drift_walker`, `prd_cla`, and the ADR-088 `prd_ghcr`
claim. The stated belief: a service token scoped to `prd_registry` reads "only
the two ZOT tokens" so "a host compromise reads nothing else."

**This is false.** In Doppler, **every config within an environment resolves
that environment's ROOT config as its base** — branch configs inherit the full
root secret set *unless a secret is explicitly deleted from the branch*. This is
independent of the paid "config inheritance" (`inherits`) feature. Official docs:
<https://docs.doppler.com/docs/branch-configs> — root configs "serv[e] as the
base from which all future configs branch off … secrets will be inherited by
branch configs unless deleted."

## How to VERIFY (empirical, ~30s, reversible)

A `terraform plan` / provider-shape check proves nothing here. Mint an actual
scoped read service token and count what it resolves:

```bash
TOK=$(doppler configs tokens create probe --project soleur --config <cfg> --access read --plain)
# from a dir with NO doppler.yaml:
DOPPLER_TOKEN="$TOK" doppler secrets --only-names --json | jq -r 'keys[]' | grep -vc '^DOPPLER_'
# a prd BRANCH config returns ~116 (the whole prd root, incl SUPABASE_SERVICE_ROLE_KEY);
# an ISOLATED boundary returns exactly its own count.
# revoke by SLUG (not the --plain value):
SLUG=$(doppler configs tokens --project soleur --config <cfg> --json | jq -r '.[0].slug')
doppler configs tokens revoke "$SLUG" --project soleur --config <cfg>
```

`--plain` is NOT a valid flag on `doppler secrets --only-names` — use `--json | jq -r 'keys[]'`.
`doppler configs tokens revoke` takes the slug and needs `--project`/`--config`; there is no `--yes`.

## The fix: a separate PROJECT (not an environment, not a branch config)

True isolation requires a boundary that does not share the `prd` root. Two work:
a dedicated **project** (own roots) or a standalone **environment** (own root).

**Tier trap:** a Doppler project is capped at **4 environments** on the non-Team
tier. `soleur` already has dev/prd/ci/cli = at the cap, so a 5th `registry`
environment is impossible (`doppler environments create` → *"reached its limit of
4 environments. Upgrade to the Team plan"*). **Project creation is NOT tier-capped**
— so the isolation fix for zot (#6122) used a dedicated `soleur-registry` project
whose own `prd` root holds only the two ZOT tokens. A fresh project auto-creates
`dev/dev_personal/stg/prd` root configs. The terraform `doppler_project` resource
(provider `DopplerHQ/doppler ~> 1.21+`) creates it; `var.doppler_token_tf` is a
workplace-scope personal token, so it can create projects.

This is a DIFFERENT tier limit than the config-inheritance paid-feature limit
that sank `doppler_config.prd_ghcr` at apply in #6067 — don't conflate them.

## Fail-closed backstop for host consumers

For a host that reads a Doppler token at boot, add a self-assertion that runs
under the *shipped* token and refuses to start unless it resolves exactly the
expected secrets (count AND identity), before the workload launches. Every other
signal (empty-token guard, heartbeat, `terraform apply`) fails **OPEN** on an
over-scoped token — a 116-secret token still populates the expected vars
non-empty. See `cloud-init-registry.yml` boot self-check.

## Broader remediation

The identical branch-config over-read affects `prd_git_data`,
`prd_kb_drift_walker`, and `prd_cla` (a **live** over-read — created by
`apps/cla-evidence/infra/bootstrap.sh`). Audited in **#6167**.
