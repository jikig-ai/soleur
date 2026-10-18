# Closeout evidence: heartbeat-URL argv item (Ref #9757)

Measured 2026-10-18 on `origin/main`. No heartbeat URL, token or digest appears in this file; each reading cites a PR number, a workflow run id or a content anchor.

## 1. The three transport lines are on main behind a shape guard

| Script (under `apps/web-platform/infra/`) | Transport anchor | Guard anchor | Landed by |
|---|---|---|---|
| `inngest-bootstrap.sh` | `printf 'url = "%s"\n' "$INNGEST_HEARTBEAT_URL" \| /usr/bin/curl ... --config -` | the `_hb_ok` case block that refuses an unsafe URL with exit 2 before curl runs | PR #10356 (merged 2026-10-15) |
| `web-git-data-probe.sh` | `_hb_curl()` feeding `printf 'url = "%s"\n' "$URL"` to `curl ... --config -` | `_hb_url_ok()` checked before every call | PR #10086 (merged 2026-10-12) |
| `luks-monitor.sh` | `curl ... --config - ... < <(printf 'url = "%s"\n' "$hb_url")` | `hb_url_ok()` checked before the push loop | PR #10086 (merged 2026-10-12) |

Last commit touching any of the three on main: PR #10356, 2026-10-15, which predates this plan. Nothing drifted since.

## 2. The ratchet is green

`bash tests/scripts/test-argv-bearer-sweep.sh` on this tree: `=== 823 passed, 0 failed ===`, exit 0. The S6-HB stage has an empty allowlist, so any heartbeat script that reverted to a path-bearing argv would turn it red. The plan recorded 6 converted of 16 derived heartbeat scripts; the 10 others are not in this item's file set.

## 3. Delivery to a host (transport only)

`web-git-data-probe.sh`: the push run `38303163269` (workflow `Apply web-platform infra`, event `push`, head = PR #10086's merge commit, which is an ancestor of main) concluded `success` and replaced `terraform_data.git_data_probe_install`, re-running its three `file` provisioners and its `remote-exec` provisioner (creation complete after 8s). That is delivery of the converted probe to its host.

`inngest-bootstrap.sh`: PR #10356's own post-merge verification covered its delivery; that reading was not repeated here, so no delivery claim is made for it in this file.

## 4. What is NOT claimed

- `luks-monitor.sh` is delivered through the operator-applied `workspaces-luks.tf` root, and its monitor (`betteruptime_heartbeat.workspaces_luks` in `uptime-alerts.tf`) carries `ignore_changes = [paused]`: it stays paused until the operator unpauses it at cutover. No luks delivery or liveness is claimed; the transport is on main and unverified on any host. This becomes a named residual on #10093.
- The Better Stack monitor read for `soleur-git-data-prd` was not taken. It is optional, never a delivery proof, and a down monitor would be a finding for #10093, not a blocker.
- Not claimed: the whole umbrella item as "done". The tick is scoped to "transport (argv)".

## 5. Out of scope (CTO ruling, `decision-challenges.md`)

A residual-fix PR (an unlimited refusal marker and an unset-URL WARN in `web-git-data-probe.sh`) and a new live-evidence verifier were rejected: both need a production apply plus ratchet bumps, and the item as written is already satisfied.
