# Learning: Hetzner Cloud API returns catalog EUR + inventory, never billed USD; and enforce (don't assume) a one-marker-per-row invariant

## Problem

#6602 needed to correct unverified Hetzner estimates in `knowledge-base/operations/expenses.md`
against ground truth, then ship a scheduled gate that flags any estimate row whose `verify_by`
date has passed. Two non-obvious facts shaped the work:

1. **Which Hetzner figures are API-reachable at all** — the ledger had priced volumes on a stale
   `~$0.044/GB` basis and was missing two Primary IPv4 rows (#6589 gap), and it wasn't obvious
   which of those the Cloud API could authoritatively correct vs. which stay estimates.
2. A greedy marker extractor in the new checker silently read only the FIRST marker when a row
   carried two — a latent fail-open in a gate whose entire job is to fail loud.

## Solution

### Hetzner Cloud API capability boundary (verified live 2026-07-17, `HCLOUD_TOKEN` in Doppler `prd_terraform`)

`https://api.hetzner.cloud/v1` returns **catalog EUR + inventory**, and **404s on billing**:

| Endpoint | Returns | Use |
|---|---|---|
| `/v1/pricing` → `.pricing.volume.price_per_gb_month.net` | **EUR 0.0572/GB/mo** | volume $ = GB × 0.0572 × ~1.08 FX |
| `/v1/pricing` → `.pricing.server_types[]` | cx33 EUR 8.49, cx23 5.49, cpx22 19.49 | host $ = EUR × ~1.08 |
| `/v1/pricing` → `.pricing.primary_ips[] type=ipv4` | EUR 0.50/mo (all locations) | IPv4 $ = 0.50 × ~1.08 = 0.54 |
| `/v1/servers`, `/v1/primary_ips`, `/v1/volumes` | live inventory (name, type, size, assignee) | count/type drift + missing-row detection |
| `/v1/invoices`, `/v1/billing` | **404** | billed USD is NOT reachable via a Cloud API token |

**Consequence:** every Hetzner amount derived from the API is a **catalog-EUR × FX estimate**, never a
billed figure. Billed USD (VAT, FX drift, IPv4 line items, traffic overage, per-hour proration) lives only
on the invoice PDF emailed to the operator's ops intake mailbox. So the honest pattern is: **correct count/type/catalog-EUR
from the API, keep billed USD as an estimate + a machine-readable `verify_by` marker dated to the next
invoice cycle.** The account here is VAT-exempt (`vat_rate: 0.0`), so net == gross.

The ledger's implied `~$0.044/GB` volume basis corresponds to ~EUR 0.0407/GB — stale vs the live
EUR 0.0572/GB. Repricing all four volumes at the host rows' ~1.08 FX moved them 0.88→1.24 (20 GB),
2.64→3.71 (60 GB), 0.48→0.62 (10 GB): a +$1.93/mo correction the plan had estimated at only ~$0.35/mo.

### One-marker-per-row: enforce, don't assume

The checker `scripts/expenses-verify-by-check.sh` extracts a marker per ledger line with a greedy
`grep -oE '<!-- *estimate .*-->'`. On a row with two markers, the greedy `.*-->` collapses both into one
blob and the field parser's `head -1` reads only the first `verify_by` — an expired second marker is
silently masked. The fix counts `<!-- estimate` occurrences per line and classifies `>1` as an anomaly
(exit 2), enforcing the invariant the parser previously only assumed. Caught by review, not the author.

## Key Insight

- **Before asserting a vendor API "returns X", probe the exact endpoint — a project-scoped token routinely
  reaches catalog + inventory while billing/invoice endpoints 404.** Correct only what the API authoritatively
  returns; mark the rest as an estimate with a dated re-verify trigger rather than hardening a catalog figure
  into a "verified" number.
- **A marker/comment parser with a greedy terminator has a latent fail-open on repeated markers per unit
  (line/cell/block).** For any gate that must fail loud, count the occurrences and treat "more than the
  invariant allows" as an anomaly — same class as anchoring a body-grep on syntax rather than a bare token.

## Session Errors

1. **`set -e` + `grep|head` inside `$(...)` aborted the checker mid-parse** (the broken-candidate RED test
   returned rc=1 + empty output instead of the anomaly's exit 2). Recovery: wrap each extractor pipeline
   `{ … | head -1; } || true`. Prevention: already covered by AGENTS.md's accumulate-then-exit foot-gun —
   apply it to command substitutions, not just top-level commands.
2. **`awk 'match(str, re, arr)'` (3-arg gawk form) failed** with a syntax error on this host's mawk when
   summing the COGS table. Recovery: used python for the numeric extraction. Prevention: don't assume gawk;
   prefer python/grep for table arithmetic in throwaway verification.
3. **Background `nohup … &` inside a `run_in_background` Bash double-backgrounded**, so the harness's
   "completed exit 0" notification reported the launcher's exit and the log was a mid-run snapshot.
   Recovery: ran `TEST_GROUP=scripts` foreground and grepped the log for the suite's own summary.
   Prevention: already covered by AGENTS.md ("a backgrounded task notification reports the trailing
   echo's/launcher's exit") — never trust a bg exit code without grepping the runner's own summary line.
4. **Greedy `.*-->` masked a second marker + the `verify_by==today` boundary was unpinned** (review-surfaced,
   not a runtime error). Recovery: added a one-marker-per-row anomaly guard + a today-dated boundary fixture,
   both fixed inline. Prevention: the two Key Insights above.

## Tags
category: reference
module: operations/expenses, scripts/expenses-verify-by-check
