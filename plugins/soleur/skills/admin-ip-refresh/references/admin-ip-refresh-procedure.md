# admin-ip-refresh -- Procedure

Detailed procedure for the `admin-ip-refresh` skill. Kept out of SKILL.md to preserve the skill-description token budget.

## Inputs

- Flags: `--dry-run`, `--verify`, `--fast` (see SKILL.md for semantics).
- Environment: `doppler` and `curl` on PATH; `doppler` CLI must already be authenticated.

## Outputs

- On no-drift: exit 0, one line summary: `No drift. Current IP X.X.X.X/32 is in ADMIN_IPS (list length N).`
- On drift detected + `--dry-run`: exit 0, diff printed, no writes.
- On drift detected + operator ack: Doppler mutated, `terraform` invocation emitted, exit 0.
- On detection failure (all three IP services failed): exit 3.
- On Doppler read/write error: exit 4.
- On operator refusal: exit 5.

## Step 1 -- Detect egress IP (three-service fallback)

Query IP providers in order, accept the first response that passes validation. Strict timeouts prevent the skill from hanging on a degraded service.

```bash
detect_egress_ip() {
  local services=(
    "https://ifconfig.me/ip"
    "https://api.ipify.org"
    "https://icanhazip.com"
  )
  for svc in "${services[@]}"; do
    local ip
    ip="$(curl -fsS --connect-timeout 5 --max-time 10 "$svc" 2>/dev/null \
         | tr -d '[:space:]')" || continue
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      IFS=. read -r a b c d <<<"$ip"
      if (( a<=255 && b<=255 && c<=255 && d<=255 )); then
        echo "$ip"
        return 0
      fi
    fi
  done
  return 1
}
```

Exit 3 (fail-closed) if all three services fail. Do not silently no-op -- a scheduled invocation with a silent no-op would hide a genuine outage.

## Step 2 -- Read current ADMIN_IPS

```bash
current_raw="$(doppler secrets get ADMIN_IPS -p soleur -c prd_terraform --plain 2>/dev/null)" || {
  echo "error: failed to read ADMIN_IPS from Doppler prd_terraform" >&2
  exit 4
}
```

Parse `current_raw` as a JSON list. If empty or missing, abort with: "ADMIN_IPS is not set in Doppler prd_terraform. Bootstrap it before running this skill."

## Step 3 -- Diff

- Compose `candidate="${egress}/32"`.
- If `candidate` is in the parsed list: print `No drift. Current IP ${candidate} is in ADMIN_IPS (list length N).` and exit 0.
- If `candidate` is NOT in the parsed list:
  - Print the pre-image list.
  - Print the post-image list (current list with `candidate` appended).
  - Continue to Step 4.

## Step 4 -- Warn on list-length invariants

- **Post-image length == 1 (P1 warning).** Print:
  > WARNING: `ADMIN_IPS` will have a single entry after this refresh. A single-entry list has no rotation margin -- the next ISP/NAT rotation will lock SSH out. Recommend adding a second known-good CIDR (home + mobile hotspot + travel) before shipping.
  >
  > Type `understood` to acknowledge and proceed, or Ctrl-C to abort.

  Require literal `understood` input before proceeding.

- **Post-image length > 10 (P2 warning).** Print:
  > NOTICE: `ADMIN_IPS` will have N entries. Stale entries should be pruned -- review and remove CIDRs you do not recognize in a follow-up pass.

  Do not require acknowledgment; continue.

## Step 5 -- Operator go-ahead prompt

Print the exact invocation the skill will run:

```bash
# Skill will run:
doppler secrets set ADMIN_IPS -p soleur -c prd_terraform --silent \
  < <temp-file>
```

Prompt the operator: `Proceed with Doppler write? Type "yes" to confirm.` Accept only literal `yes`. On anything else, print "Aborted. No changes made." and exit 5.

Per AGENTS.md `hr-menu-option-ack-not-prod-write-auth`: prod-scoped Doppler mutations do NOT take `--yes`/`--force`/`--auto-approve`. Operator ack is explicit and per-command.

If running under `--dry-run`, skip Steps 5-7 entirely and exit 0 after Step 4.

## Step 6 -- Write Doppler

Compose the new JSON list, write to a 0600 temp file, pipe via stdin, `shred -u` the temp file on exit. Never pass the list as a CLI argument -- it would leak into `ps auxf` and shell history.

```bash
umask 077
tmp="$(mktemp -t admin-ips.XXXXXX)"
trap 'shred -u "$tmp" 2>/dev/null || rm -f "$tmp"' EXIT

# Write the new list to the temp file:
printf '%s\n' "$new_list_json" > "$tmp"

# Mutate (--silent prevents value echo):
doppler secrets set ADMIN_IPS -p soleur -c prd_terraform --silent < "$tmp" \
  || { echo "error: Doppler write failed" >&2; exit 4; }
```

**Verify the write.** Re-read via `doppler secrets get ADMIN_IPS --plain` and compare byte-for-byte to `new_list_json`. Doppler's write-after-write consistency is strong for single-secret mutations, but the verify step is cheap insurance.

**Audit-trail URL.** Print:

```text
Doppler activity log: https://dashboard.doppler.com/workplace/projects/soleur/configs/prd_terraform/activity
```

## Step 7 -- Emit Terraform invocations

Default output (full-graph `plan` + `apply`):

```bash
cd apps/web-platform/infra

# Preview the change:
doppler run --project soleur --config prd_terraform \
  --name-transformer tf-var -- \
  terraform plan

# Apply (Terraform will prompt for confirmation -- do NOT pass --auto-approve):
doppler run --project soleur --config prd_terraform \
  --name-transformer tf-var -- \
  terraform apply
```

Under `--fast`, also emit the narrow-target form with a warning:

```text
# Fast-recovery form (skips dependency graph; use only for acute recovery):
cd apps/web-platform/infra
doppler run --project soleur --config prd_terraform \
  --name-transformer tf-var -- \
  terraform plan -target=hcloud_firewall.web
doppler run --project soleur --config prd_terraform \
  --name-transformer tf-var -- \
  terraform apply -target=hcloud_firewall.web
```

Per HashiCorp guidance, `-target` is for rare/recovery cases, not habitual use.

## Step 8 -- Verify prompt

Ask: `Did you run terraform apply? [yes / no / skip]`.

- `yes`: exit 0. Suggest running `/soleur:admin-ip-refresh --verify` in a follow-up session to confirm the firewall rule matches.
- `no`: print a reminder that Doppler and firewall are now out of sync; the scheduled drift check (tracked separately) will catch it within 24 hours.
- `skip`: exit 0 without reminder. Recorded as a session gap.

## Nested `doppler run` rationale

The `apps/web-platform/infra/` Terraform root hydrates variables via `doppler run --name-transformer tf-var`. `TF_VAR_ADMIN_IPS` is the renamed form of `ADMIN_IPS`. Running `terraform apply` directly (without `doppler run`) leaves the variable undefined and the apply fails at plan time. See AGENTS.md `cq-when-running-terraform-commands-locally`.

## Exit codes

- `0` -- success (no drift OR drift corrected + operator acked + invocation emitted).
- `3` -- all three IP-detection services failed.
- `4` -- Doppler read or write failed.
- `5` -- operator refused the mutation.

Non-zero exit codes are intentional so a future scheduled cron invocation (tracked as a deferred issue) does not silently no-op.

## CLI verification

Per AGENTS.md `cq-docs-cli-verification`:

- `curl -fsS --connect-timeout N --max-time N <url>` -- <!-- verified: 2026-04-19 source: curl --help all | grep -E "connect-timeout|max-time|fail|silent|show-error" -->
- `doppler secrets get <KEY> -p <proj> -c <config> --plain` -- <!-- verified: 2026-04-19 source: https://docs.doppler.com/docs/accessing-secrets -->
- `doppler secrets set <KEY> -p <proj> -c <config> --silent` (stdin form) -- <!-- verified: 2026-04-19 source: https://docs.doppler.com/docs/setting-secrets -->
- `doppler run --project <proj> --config <config> --name-transformer tf-var -- <cmd>` -- <!-- verified: 2026-04-19 source: AGENTS.md cq-when-running-terraform-commands-locally -->
- `doppler configure get token --plain` -- <!-- verified: 2026-04-19 source: doppler configure get --help -->
- `hcloud firewall describe <name>` -- <!-- verified: 2026-04-19 source: hcloud firewall describe --help -->
- `terraform plan [-target=<addr>]` -- <!-- verified: 2026-04-19 source: https://developer.hashicorp.com/terraform/cli/commands/plan -->
- `terraform apply [-target=<addr>]` -- <!-- verified: 2026-04-19 source: https://developer.hashicorp.com/terraform/cli/commands/apply -->
