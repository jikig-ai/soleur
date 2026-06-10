# Learning: Better Stack quota warnings — measure per-source first; host metrics through a generic HTTP sink count as log ingest

## Problem

Better Stack emailed "your organization is at 80% of plan quota" (free tier: 3 GB/mo logs, 3-day retention + 30 GB metrics). The email names no source, no quota type, and no number — and Better Stack has no public usage API, so the dashboard email is the only push signal.

## Solution

Diagnose with data already reachable from the repo, no dashboard eyeballing:

1. **Enumerate sources** via the Telemetry API (`BETTERSTACK_API_TOKEN`, Doppler `soleur/prd_terraform`): `GET https://telemetry.betterstack.com/api/v1/sources`. This surfaced a leftover **"Onboarding • Real-time flights" demo source** (created at account onboarding, 3652-day retention) that nobody remembered — deleted via `DELETE /api/v1/sources/<id>` (HTTP 204).
2. **Measure per-source volume** via `scripts/betterstack-query.sh` (ClickHouse HTTP SQL): daily row counts grouped by kind. Verdict: host metrics were >99% of rows (~196k/day from a 30s `host_metrics` scrape across ~100 series) vs ~50 journald WARN+ rows/day. The "logs" quota was being consumed almost entirely by **metrics shipped as JSON events through the generic HTTP sink** (`[sinks.betterstack]` is `type = "http"` because the native sink doesn't exist — Vector PR #19274 closed unmerged).
3. **Remediate at the source, not the wallet**: `scrape_interval_secs` 30 → 300 (−90%) + `devices.excludes = ["loop*", "dm-*"]` on the disk/filesystem collectors (snap loop + device-mapper pseudo-devices are pure noise on a Hetzner cx33). Free tier kept; ledger upgrade trigger ("first paying customer") not fired.

## Key Insight

When a vendor quota warning arrives, the per-source measurement is one query away and almost always names a single dominant producer — fix that producer before considering a paid tier. Specifically for Better Stack: metric events sent through the generic HTTP logs sink are billed against the **logs** ingestion quota, so a "logs quota" warning can be 99% metrics. Also: Better Stack's onboarding demo source lingers in every account with 10-year retention — delete it.

## Session Errors

1. **Cross-region ClickHouse cluster miss** — querying the demo source's table failed with `CLUSTER_DOESNT_EXIST`: the minted query connection reaches only the region cluster of the source it was provisioned around (eu-fsn-3); the demo source lived in eu-nbg-2. **Recovery:** used Telemetry API source metadata instead. **Prevention:** noted in `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` — `remote()` table access is per-region; sources in other regions need their own connection.
2. **`&&`-chained process-substitution diff silently produced no output** for the final check in a long compound command. **Recovery:** re-ran the check standalone — passed. **Prevention:** run load-bearing verification diffs as standalone commands, not as the tail of a 8-step `&&` chain.
3. **`gh issue create` denied by the milestone-required hook.** **Recovery:** re-ran with `--milestone "Post-MVP / Later"`. **Prevention:** already hook-enforced (working as designed).
4. **`sed` bulk-checkbox edit over-marked a not-yet-done task** (4.1 PR body). **Recovery:** unmarked immediately. **Prevention:** prefer targeted Edit calls over broad sed ranges for checkbox state.
5. **CI `enforce` job (legal-doc cross-document gate) failed with `fatal: origin/main...HEAD: no merge base`** — checkout/fetch-depth flake, pre-existing, diff touches no legal surface. **Recovery:** fresh push retriggers; verify green at ship. **Prevention:** if it recurs, file a workflow issue for fetch-depth in that gate rather than working around it in a feature PR.

## Tags

category: integration-issues
module: observability / better-stack / vector
