# Runbook — Cloudflare whole-list entrypoint drift audit (#6767 / ADR-135)

## What this is

The **retrospective** half of #6767. A `kind = "zone"` / `kind = "root"`
`cloudflare_ruleset` owns its phase entrypoint as a **whole-list replacement**.
The **prospective** hazard (a future create-from-absent clobbering a live
dashboard entrypoint) is stopped by the standing **pre-apply gate** — the
"Pre-apply entrypoint gate" step in `apply-web-platform-infra.yml`, source
`tests/scripts/lib/preapply-entrypoint-gate.sh --gate`. This runbook covers the
**read-only audit** that confirms nothing was *already* lost and that no live
entrypoint has drifted from state.

Per `hr-no-dashboard-eyeball-pull-data-yourself`: the findings are pulled by CI
and posted to **#6767** as the system-of-record — never eyeballed in the CF
dashboard.

## Method

The audit is `preapply-entrypoint-gate.sh --audit [--live]`:

- **Static** (runnable anywhere, no creds): enumerates every declared
  `cloudflare_ruleset` in `apps/web-platform/infra/*.tf`, classifies zone vs
  account, and prints the entrypoint class + phase per ruleset.
- **Live** (CI only, read-only): control-probes a known-populated phase
  (`http_request_dynamic_redirect`, expect HTTP 200), then `GET`s each declared
  ruleset's live entrypoint (`zones/<zone>/…` or `accounts/<acct>/…`) and reports
  the live rule count. GETs only — **no import, no apply**.

The correction context (from the #6767 author): the four other in-repo
`kind = "zone"` rulesets (`seo_page_redirects`, `seo_response_headers`,
`allowlist_ai_crawlers`, `cache_shared_binaries`) plus `bulk_redirects`
(`kind = "root"`) are **already in state** — `terraform plan` refreshes their
entrypoints on every run, so a dashboard-added rule surfaces as ordinary drift.
Their exposure is retrospective (anything added before their own first apply is
already gone), which is exactly what this audit confirms.

### Static parity table

| Ruleset | kind | entrypoint class |
|---|---|---|
| `cache_shared_binaries` | zone | `zones/<zone>/rulesets/phases/http_request_cache_settings/entrypoint` |
| `seo_page_redirects` | zone | `zones/<zone>/rulesets/phases/http_request_dynamic_redirect/entrypoint` |
| `seo_response_headers` | zone | `zones/<zone>/rulesets/phases/http_response_headers_transform/entrypoint` |
| `seo_config_settings` | zone | `zones/<zone>/rulesets/phases/http_config_settings/entrypoint` |
| `allowlist_ai_crawlers` | zone | `zones/<zone>/rulesets/phases/http_request_firewall_custom/entrypoint` |
| `bulk_redirects` | root | `accounts/<acct>/rulesets/phases/http_request_redirect/entrypoint` |

(Regenerate authoritatively with `bash tests/scripts/lib/preapply-entrypoint-gate.sh --audit`.)

## How to run the live audit

It runs via a **guarded, read-only dispatch** — its own concurrency group, no
`terraform apply`, `issues: write` via a GitHub App installation token:

```bash
gh workflow run apply-web-platform-infra.yml \
  -f apply_target=entrypoint-audit \
  -f reason='#6767 retrospective entrypoint drift audit'
gh run watch "$(gh run list --workflow=apply-web-platform-infra.yml --limit 1 --json databaseId -q '.[0].databaseId')"
```

The `entrypoint_audit` job posts its findings to #6767. `/ship` runs this
in-session and blocks PR-ready on the comment landing — it is NOT a deferred
post-merge checkbox (`wg-block-pr-ready-on-undeferred-operator-steps`).

## Reading the results

For each ruleset the live table shows `HTTP` + `live rule count`:

- **live rule count == the count in the resource's `rules` block** → in sync.
- **live > declared** → a dashboard-added rule exists that state does not know
  about. If the resource is in state, the next `plan` shows it as drift (adopt or
  reconcile). If it is a *new* phase not yet applied, the pre-apply gate would
  block its first apply — adopt via the singular v4 import block the gate prints.
- **404** → empty phase (no ruleset) — safe.
- **non-200/404** → an ambiguous read; re-run (the gate treats this as
  fail-closed on the apply path).

## Results

The live-audit results are produced by the CI run above (creds are not available
at `/work`). See the audit comment on **#6767** for the current findings.
