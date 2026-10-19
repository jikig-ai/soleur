# Closeout evidence: heartbeat-URL argv item (Ref #9757)

Measured 2026-10-18 on `origin/main`. No heartbeat URL, token or digest appears in this file; each reading cites a PR number, a workflow run id or a content anchor.

## 1. The three transport lines are on main behind a shape guard

| Script (under `apps/web-platform/infra/`) | Transport anchor | Guard anchor | Landed by |
|---|---|---|---|
| `inngest-bootstrap.sh` | `printf 'url = "%s"\n' "$INNGEST_HEARTBEAT_URL" \| /usr/bin/curl ... --config -` | the `_hb_ok` case block, which refuses before curl runs (exit 2 on an empty URL, exit 0 on a shape or control-byte refusal so the missed beat is the alarm) | PR #10356 (merged 2026-10-15) |
| `web-git-data-probe.sh` | `_hb_curl()` feeding `printf 'url = "%s"\n' "$URL"` to `curl ... --config -` | `_hb_url_ok()`, checked once before the attempts | PR #10086 (merged 2026-10-12) |
| `luks-monitor.sh` | `curl ... --config - ... < <(printf 'url = "%s"\n' "$hb_url")` | `hb_url_ok()`, checked before the push loop | PR #10086 (merged 2026-10-12) |

PR #10356 also converted `web-zot-consumer-probe.sh`, `inngest-consumer-probe.sh` and `web-private-nic-guard.sh`. Last commit touching any of the three scripts on main: PR #10356, 2026-10-15, which predates this plan.

## 2. The ratchet is green

`bash tests/scripts/test-argv-bearer-sweep.sh` on this tree (re-run by the quality reviewer): `=== 823 passed, 0 failed ===`, exit 0. The S6-HB stage has an empty allowlist (ceiling 0). It derives 16 `infra/*.sh` files that name a heartbeat; 6 of them are manifest-pinned to exactly one guarded stdin line each (the three above plus the three probes in section 1), and the other 10 are held only to the no-argv rule. The scanner is a documented text heuristic: it matches the variable names `$URL`, `$hb_url` and `*HEARTBEAT_URL`, so a URL renamed to another variable and put back on argv would not trip it. It is the repo's argv gate, not a proof about every possible spelling.

## 3. Delivery to a host (transport only)

`web-git-data-probe.sh`: push apply run `38303163269` (workflow `Apply web-platform infra`, head = PR #10086's merge commit, an ancestor of main) concluded `success`, and its log shows `terraform_data.git_data_probe_install` replaced, its three `file` provisioners and one `remote-exec` provisioner running, and `Creation complete after 8s`. The remote-exec output is suppressed as sensitive and the host is not named, so this shows the provisioners ran and the resource was created; the content on the host was not read.

`inngest-bootstrap.sh`: PR #10356's merge commit carried a successful push apply (run `38791101231`, head `1c0cf63dd3`). The script is a carrier: hosts pick up its heartbeat body only through an image tag and pin bump. Per-resource re-delivery and host rollout were not read here, so no delivery claim is made for it.

## 4. What is NOT claimed

- `luks-monitor.sh`: its installer `terraform_data.luks_monitor_install` is in the auto-applied SSH target list and the script is also baked into the fresh-host cloud-init list. Only the heartbeat monitor (`betteruptime_heartbeat.workspaces_luks`) and its URL secret are operator-applied, and that monitor is paused (`ignore_changes = [paused]`) until cutover. Whether the installer re-ran on a given apply was not read, and the paused monitor cannot show delivery. No luks delivery or liveness is claimed; this becomes a named residual on #10093.
- Live hosts that were not re-delivered (web-2 and the inngest host, #10093 residual 1) keep the argv scripts until a fresh boot, replace or image deploy. The tick is therefore about the source and the transport on main, not about every live host.
- Residual exposure channels outside "transport (argv)": the URL stays in the script's process environment (root-only) for its lifetime, and `inngest-heartbeat.sh` and `web-git-data-probe.sh` do not refuse xtrace.
- The Better Stack monitor read for `soleur-git-data-prd` was not taken; it is optional and never a delivery proof.
- Not claimed: the whole umbrella item as "done". The tick is scoped to "transport (argv)".

## 5. Out of scope (CTO ruling, `decision-challenges.md`)

A residual-fix PR (an unlimited refusal marker and unset-URL WARN in `web-git-data-probe.sh`) and a new live-evidence verifier were rejected: both need a production apply plus ratchet bumps, and the item as written is satisfied in source.
