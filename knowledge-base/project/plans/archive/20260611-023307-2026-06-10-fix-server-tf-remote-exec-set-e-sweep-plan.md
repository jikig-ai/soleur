---
title: "fix(infra): server.tf remote-exec set -e gating sweep"
date: 2026-06-10
type: fix
issue: 5101
lane: cross-domain
brand_survival_threshold: none
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan contains ZERO manual/operator infrastructure steps.
     Every systemctl/shell string in this document is a QUOTE of existing Terraform
     remote-exec inline content in apps/web-platform/infra/server.tf being audited;
     the only change is adding "set -e" to those .tf-managed scripts. Apply path is
     the existing auto-apply workflow (see ## Infrastructure (IaC)). -->

# fix(infra): server.tf remote-exec `set -e` gating sweep (#5101)

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed; no spec.md exists for this one-shot branch at plan time).

## Enhancement Summary

**Deepened on:** 2026-06-10 (inline passes — pipeline context without Task tool; every verification executed directly against the repo/live state rather than via spawned agents)
**Sections enhanced:** Hypotheses (Network-Outage Deep-Dive table), Risks (precedent-diff entry), User-Brand Impact (sensitive-path scope-out bullet), Premise Validation (#5046 state), Post-merge AC (rule-ID correction)

### Key Improvements

1. **Live-verified the prescribed awk guard** against current server.tf — produced exactly `blocks=13 ok=2` with 11 FAIL lines, one per audited block. The RED state is confirmed, not assumed.
2. **Verify-the-negative pass executed:** the claim "no `!`-prefixed pipelines exist in the 11 swept blocks" was grep-confirmed (`grep -n '"\!' server.tf` → zero matches outside cron's own probe), so plain `set -e` suffices and no `if/exit-1` rewrites are needed.
3. **Phase 4.4 precedent-diff recorded** (Risks #5): cron_egress_firewall (server.tf:736-742, 784-819) is the canonical gated-block shape; drift-guard precedent is `bwrap-userns-sysctl.test.sh` + named infra-validation step.
4. **Rule-ID audit:** corrected a truncated citation (`wg-after-a-pr-merges-to-main` → `wg-after-a-pr-merges-to-main-verify-all`); all other cited IDs (`hr-ssh-diagnosis-verify-firewall`, `cq-write-failing-tests-before`, `wg-use-closes-n-in-pr-body-not-title-to`) verified active in AGENTS.md.
5. **Gates 4.6/4.7/4.8 passed:** User-Brand Impact present with valid threshold + explicit sensitive-path scope-out bullet (added — `apps/[^/]+/infra/` and `infra-validation` workflow match the canonical regex); Observability 5-field schema complete, no-SSH discoverability command; zero PAT-shaped variables.

### New Considerations Discovered

- Parent epic #5046 is CLOSED (Ref-only citation — no premise staleness; recorded in Premise Validation).
- All knowledge-base file citations in the plan resolve on disk (broken-citation sweep returned zero).

## Overview

Terraform joins each `remote-exec` provisioner's `inline` list into ONE shell script with **no implicit errexit**; the provisioner fails only on the **last** command's exit status. The 7 pre-existing SSH `terraform_data` provisioners in `apps/web-platform/infra/server.tf` (disk_monitor_install, resource_monitor_install, fail2ban_tuning, journald_persistent, docker_seccomp_config, apparmor_bwrap_profile, orphan_reaper_install) therefore run their intermediate assertions decoratively — `docker_seccomp_config` and `apparmor_bwrap_profile` end in always-true `echo`s, and `fail2ban_tuning` gates only because its `test` asserts happen to be last. PR #5089 fixed the same defect in the NEW `cron_egress_firewall` provisioner (`"set -e"` first + explicit `if/exit-1` probes) and deliberately deferred the siblings to their own cycle (issue #5101). This plan is that cycle.

**Work:** (1) audit every inline command in each block for benign non-zero exits, (2) add `"set -e",` as the first inline element of every un-gated `remote-exec` block, (3) lock the invariant with a CI drift guard so future provisioners cannot regress.

**Done condition (from #5101):** `grep -c '"set -e",' apps/web-platform/infra/server.tf` ≥ 9. After this sweep the count is **13** (11 newly gated blocks + the 2 `cron_egress_firewall` blocks already gated). The follow-through probe `scripts/followthroughs/server-tf-provisioner-set-e-sweep-5089.sh` (verified on disk; counts the same grep) auto-closes #5101 on PASS — and the PR body's `Closes #5101` closes it at merge regardless; the probe then no-ops.

**Live verification path (verified, not assumed):** `.github/workflows/apply-web-platform-infra.yml` fires `on: push: branches: [main]` with paths filter `apps/web-platform/infra/**` (lines 66-72) — **this PR's merge triggers it automatically**. Its token-gated SSH apply step (lines 464-531) `-target=`s exactly the 8 SSH siblings (the 7 + cron_egress_firewall), which show as "will be created" in CI state, so all 10 swept blocks in the 7 resources re-run live with `set -e` on merge day. No operator action.

Ref #5046. Ref PR #5089.

## Premise Validation

Checked 2026-06-10: issue #5101 is **OPEN** (`gh issue view 5101` → state OPEN); PR #5089 is **MERGED** (2026-06-10T13:43Z); parent epic #5046 is **CLOSED** (Tier-2 complete — cited as `Ref` only, not a dependency, so no staleness); `apps/web-platform/infra/server.tf` exists with `grep -c '"set -e",'` = **2** (the two cron_egress_firewall blocks); `scripts/followthroughs/server-tf-provisioner-set-e-sweep-5089.sh` exists, is executable, and greps for `'"set -e",'` with a ≥ 9 PASS threshold and `earliest=2026-06-12T00:00:00Z`; `.github/workflows/apply-web-platform-infra.yml` exists (named-workflow gate: `ls` verified). No stale premises.

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality (verified by grep/read) | Plan response |
|---|---|---|
| "7 provisioners" need `set -e` | Those 7 resources contain **10** `remote-exec` blocks (fail2ban_tuning, journald_persistent, docker_seccomp_config each have 2). Plus an **11th** un-gated block in `infra_config_handler_bootstrap` (server.tf:444) that the issue's enumeration missed — same defect class (its `visudo -cf` "fail the provisioner on a bad file" comment is currently false without `set -e`). | Sweep all **11** blocks. The bridge block is an explicit scope extension (see below), justified per the plan-skill rule "validate N by grepping — never trust the issue's enumerated list". |
| Done = grep count ≥ 9 | After sweeping 11 blocks: count = 13 | Probe passes with headroom; AC pins the exact count 13. |
| "Verify via the next apply-web-platform-infra.yml SSH apply" | Workflow fires automatically on merge of this PR (paths filter `apps/web-platform/infra/**`); SSH apply `-target=`s the 8 siblings | Post-merge verification is fully automated; ship-phase checks the run via `gh run list`. |
| (not in issue) bridge apply path | `infra_config_handler_bootstrap` is applied by `apply-deploy-pipeline-fix.yml` (`-target=` at lines 215-230), whose paths filter (ci-deploy.sh, webhook.service, …) does NOT include server.tf | Bridge block's live verification rides the next natural `apply-deploy-pipeline-fix.yml` run. Low risk: every command in that block is a hard requirement (no benign non-zero — see audit table). |

## Hypotheses (network-outage checklist — trigger: "SSH" + terraform apply on `remote-exec` resources)

This plan changes no connection, firewall, or sshd configuration — only inline shell gating. The checklist is included because the **apply path is SSH-dependent**, so a post-merge apply failure must be triaged L3→L7 before blaming the new `set -e` lines:

1. **L3 firewall allowlist (CI path).** Opt-out with artifact: the CI SSH apply does NOT traverse the `:22 admin_ips` ingress rule — it rides the Cloudflare Tunnel via `.github/actions/cf-tunnel-ssh-bridge` (server.tf:354-364 comments; apply-web-platform-infra.yml:107). A CI handshake failure is a stale `ci_ssh` CF Access token or a missing CI key in root's `authorized_keys` (`terraform_data.root_authorized_keys`, operator-local-apply only) — **not** admin-IP drift.
2. **L3 firewall allowlist (operator-local path).** Operator-local applies dial the direct IP; handshake succeeds iff operator egress IP ∈ `var.admin_ips` (firewall.tf). A `connection reset by peer` there is admin-IP drift → `/soleur:admin-ip-refresh`, runbook `knowledge-base/engineering/operations/runbooks/admin-ip-drift.md` (per `hr-ssh-diagnosis-verify-firewall`). No operator-local apply is planned; CI is the prescribed path.
3. **L3 DNS/routing.** Opt-out with artifact: `connection.host` is the literal `hcloud_server.web.ipv4_address` (server.tf:86 et al.) — no DNS resolution on the apply path.
4. **L7 TLS/proxy.** N/A — SSH transport, not HTTPS; the CF tunnel leg is owned by the existing `cf-tunnel-ssh-bridge` composite action, unchanged here.
5. **L7 service layer (the only layer this PR touches).** A provisioner abort AFTER a successful handshake with an error line naming an inline command is the new gating working as designed — read the failing command from the workflow log and triage per the audit table below (fix-forward with an explicit guard if the non-zero is benign, fix the host state if not).

### Network-Outage Deep-Dive (deepen-plan Phase 4.5 verification)

Layer-by-layer status of the checklist entries above (resource-shape trigger fired: the plan drives `terraform apply` on `terraform_data` resources carrying `provisioner "remote-exec"` + `connection { type = "ssh" }`):

| Layer | Status | Artifact |
|---|---|---|
| L3 firewall allow-list (CI) | verified — bypassed by design | CF Tunnel route: `apply-web-platform-infra.yml:107` + `.github/actions/cf-tunnel-ssh-bridge`; server.tf:354-364 documents that CI SSH never traverses the `:22 admin_ips` rule |
| L3 firewall allow-list (operator-local) | opt-out with artifact | No operator-local apply is planned (CI is the apply path); if one occurs, `hcloud firewall` diff vs `curl -s https://ifconfig.me/ip` per runbook `admin-ip-drift.md` BEFORE any sshd hypothesis |
| L3 DNS/routing | opt-out with artifact | `connection.host = hcloud_server.web.ipv4_address` (literal IP, server.tf:86/125/163/239/404/598/647/675/727) — no DNS on the apply path |
| L7 TLS/proxy | N/A | SSH transport; the HTTPS leg (CF Access service token for the tunnel) is owned by the unchanged `cf-tunnel-ssh-bridge` action |
| L7 application | verified by construction | This PR's only behavioral delta is post-handshake script gating; any new failure signature is an inline-command non-zero named in the terraform log, not a connectivity fault |

No gaps to close before implementation — the plan makes zero connectivity-surface changes.

## Inline Audit — every command in every un-gated block

Guard-need audit per #5101 step 1. "Guarded" = already carries `|| handler` / `|| true` (under `set -e`, the left side of `||` is errexit-exempt; the line's exit is the handler's — existing guards keep working). **No `!`-prefixed pipelines exist in any of these blocks** (those are errexit-exempt under POSIX and would need `if/exit-1` rewrites — only cron_egress_firewall uses that shape, already fixed in #5089).

All commands named below are quotes of existing `.tf`-managed inline content, not operator steps.

| # | Block (server.tf line) | Commands | Benign non-zero exits? | Action |
|---|---|---|---|---|
| 1 | disk_monitor_install (97) | chmod / printf-redirect / chmod / 2× `cat` heredoc / daemon-reload / enable-now / list-timers | None — `list-timers` exits 0 unconditionally (diagnostic); all others must succeed | add `"set -e",` |
| 2 | resource_monitor_install (136) | identical shape to #1 | None | add `"set -e",` |
| 3 | fail2ban_tuning, install block (175) | `dpkg -s … \|\| { apt-get … }` ; `dpkg -s … \|\| { echo FATAL; exit 1; }` | Both lines already explicitly guarded | add `"set -e",` |
| 4 | fail2ban_tuning, config block (195) | chown / chmod / `reload \|\| restart` / diag `\|\| true` / 3× `test` asserts | reload fallback + diag already guarded; the 3 `test` asserts become load-bearing for the first time only if a future edit appends commands after them — gating now is the durable fix | add `"set -e",` |
| 5 | journald_persistent, mkdir block (252) | `mkdir -p` | None (single command — gated today by construction; `set -e` added for the file-wide invariant) | add `"set -e",` |
| 6 | journald_persistent, config block (263) | chown / chmod / mkdir / `systemd-tmpfiles --create --prefix` / service restart / `journalctl --flush` / diag `\|\| true` / `test -d` / `journalctl --header \| grep -q` / is-active `test` | diag already guarded. `systemd-tmpfiles` non-zero here means journal-dir perms/ACLs failed — a REAL failure that must gate (do NOT add `\|\| true`) | add `"set -e",` |
| 7 | **infra_config_handler_bootstrap (444) — scope extension** | base64-render / chown / chmod / chown / chmod / `visudo -cf` / `install` / `rm -f` / webhook service restart / 3× `test -x` / 3× `grep -q` / is-active `test` | None — every command is a hard requirement; the block's own comment claims `visudo -cf` "fail[s] the provisioner on a bad file", which is only true WITH `set -e` | add `"set -e",` |
| 8 | docker_seccomp_config, mkdir block (604) | `mkdir -p` | None | add `"set -e",` |
| 9 | docker_seccomp_config, sysctl block (615) | echo-redirect / `cat` heredoc / daemon-reload / enable-now / final `echo` | None — the final informational `echo` stays (everything before it now gates) | add `"set -e",` |
| 10 | apparmor_bwrap_profile (658) | `apparmor_parser -r` / `echo` | None — `-r` (replace) exits 0 on already-loaded profiles; a parse failure must gate (currently swallowed by the trailing `echo`) | add `"set -e",` |
| 11 | orphan_reaper_install (686) | chmod / 2× heredoc / daemon-reload / enable-now / list-timers | None | add `"set -e",` |

**Result:** zero new `|| true` guards are needed — the existing blocks already guard their genuinely-benign non-zeros (a sign the original authors knew the intent; only the gating was missing). The sweep is purely additive: 11 lines, each `"set -e",` as the first inline element, matching the #5089 precedent at server.tf:792 verbatim (indentation per `terraform fmt`).

**Exit-code-semantics verification note:** the audited commands target the live host and cannot be locally re-executed; the issue's own design designates the post-merge live apply as the verification (the apply workflow fires on this PR's merge). The two commands whose exit semantics the audit leans on (`list-timers` always-0; `apparmor_parser -r` 0-on-replace) have both been exercised on every prior apply of these provisioners as last-or-passing commands.

## Files to Edit

1. **`apps/web-platform/infra/server.tf`** — add `"set -e",` as the first inline element of the 11 blocks enumerated above (lines 97, 136, 175, 195, 252, 263, 444, 604, 615, 658, 686; line numbers pre-edit). No other lines change.
2. **`.github/workflows/infra-validation.yml`** — add one named step to the `deploy-script-tests` job (after "Run cron-egress firewall drift-guard", the established one-step-per-guard pattern at lines 132-165): `- name: Run server.tf remote-exec set -e drift-guard` / `run: bash apps/web-platform/infra/server-tf-set-e.test.sh`.

## Files to Create

3. **`apps/web-platform/infra/server-tf-set-e.test.sh`** — drift guard (sibling precedent: `bwrap-userns-sysctl.test.sh`, a token-anchored guard over server.tf). Pseudo-shape:

```bash
#!/usr/bin/env bash
# Drift-guard: every `provisioner "remote-exec"` inline block in server.tf
# must open with "set -e", (first non-comment element). Terraform joins
# inline into ONE script with NO implicit errexit (#5089/#5101) — without
# set -e every intermediate assertion is decorative.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_TF="$SCRIPT_DIR/server.tf"

# Flag-based awk (NOT /start/,/end/ ranges — self-match trap): arm on
# `provisioner "remote-exec"`, then on `inline = [`, then the first
# non-comment line must be "set -e", . Comments may legally sit between
# `inline = [` and the first element (docker_seccomp_config does this).
out="$(awk '
  /provisioner "remote-exec"/ { armed = 1 }
  armed && /inline = \[/      { inlist = 1; armed = 0; next }
  inlist {
    if ($0 ~ /^[[:space:]]*#/) next
    blocks++
    if ($0 ~ /^[[:space:]]*"set -e",$/) ok++
    else printf "FAIL block %d: first element is not \"set -e\": %s\n", blocks, $0
    inlist = 0
  }
  END { printf "blocks=%d ok=%d\n", blocks, ok }
' "$SERVER_TF")"
echo "$out"
blocks="$(sed -n 's/^blocks=\([0-9]*\) ok=[0-9]*$/\1/p' <<<"$out")"
ok="$(sed -n 's/^blocks=[0-9]* ok=\([0-9]*\)$/\1/p' <<<"$out")"
# Vacuous-pass protection: parser drift that finds 0 blocks must FAIL.
[[ "$blocks" -ge 13 ]] || { echo "FAIL: expected >= 13 remote-exec blocks, parsed $blocks (parser drift?)"; exit 1; }
[[ "$blocks" -eq "$ok" ]] || { echo "FAIL: $((blocks - ok)) block(s) lack set -e gating"; exit 1; }
echo "PASS: all $blocks remote-exec inline blocks open with set -e"
```

(The /work phase MUST run this guard in its RED state against unedited server.tf and read every failure line — expected: 11 FAIL lines, `blocks=13 ok=2` — before applying the sweep. The field-extraction lines above are illustrative; the implementer should verify the actual parse with the RED run, per the "run a new guard in its RED state" learning.)

<!-- verified: 2026-06-10 — the awk body above was live-executed against the current server.tf at plan time and produced exactly `blocks=13 ok=2` with 11 FAIL lines, one per audited block (1:disk_monitor, 2:resource_monitor, 3:fail2ban-install, 4:fail2ban-config, 5:journald-mkdir, 6:journald-config, 7:handler-bootstrap, 8:seccomp-mkdir, 9:seccomp-sysctl, 10:apparmor, 11:orphan_reaper). The prescribed RED state is confirmed, not assumed. -->

## Implementation Phases

Ordered contract-before-consumer; TDD per `cq-write-failing-tests-before`:

- **Phase 1 — Drift guard, RED.** Create `apps/web-platform/infra/server-tf-set-e.test.sh`. Run it; assert it FAILS with exactly 11 `FAIL block` lines and `blocks=13 ok=2`. A guard that does not fail here is itself broken — fix the guard before proceeding.
- **Phase 2 — server.tf sweep, GREEN.** Add `"set -e",` as the first inline element of the 11 audited blocks. Re-run the guard → PASS (`blocks=13 ok=13`). Run `grep -c '"set -e",' apps/web-platform/infra/server.tf` → 13. Run `bash scripts/followthroughs/server-tf-provisioner-set-e-sweep-5089.sh` → exit 0. Run `terraform fmt -check` and `terraform init -backend=false && terraform validate` in `apps/web-platform/infra/` (terraform verified installed at `~/.local/bin/terraform`).
- **Phase 3 — CI wiring.** Add the named guard step to `infra-validation.yml`'s `deploy-script-tests` job. Validate with `actionlint .github/workflows/infra-validation.yml` (actionlint verified installed; workflow file, not composite action — actionlint is the right tool here).
- **Phase 4 — Existing-suite sweep.** Run the sibling guards that read server.tf (`bwrap-userns-sysctl.test.sh`, `cron-egress-firewall.test.sh`, `infra-config-handler-bootstrap.test.sh`, `journald-config.test.sh`) — all anchor on tokens the sweep does not remove, so all must still PASS.

## Acceptance Criteria

### Pre-merge (PR)

1. `grep -c '"set -e",' apps/web-platform/infra/server.tf` returns **13** (satisfies the issue's ≥ 9 done condition with the bridge-block extension).
2. `bash apps/web-platform/infra/server-tf-set-e.test.sh` exits 0 and prints `PASS: all 13 remote-exec inline blocks open with set -e`. RED-state evidence (11 FAIL lines against pre-sweep server.tf) is captured in the /work transcript.
3. `git diff main -- apps/web-platform/infra/server.tf` contains **only added lines**, each matching `^\+\s*"set -e",$` (11 of them) — no existing command line modified or removed (verify: `git diff main -- apps/web-platform/infra/server.tf | grep -E '^-' | grep -v '^---'` is empty).
4. `terraform fmt -check` (in `apps/web-platform/infra/`) exits 0; `terraform init -backend=false && terraform validate` exits 0.
5. `actionlint .github/workflows/infra-validation.yml` exits 0, and `grep -A1 'server.tf remote-exec set -e drift-guard' .github/workflows/infra-validation.yml` shows the `run: bash apps/web-platform/infra/server-tf-set-e.test.sh` line.
6. Sibling server.tf guards still pass: `bash apps/web-platform/infra/bwrap-userns-sysctl.test.sh && bash apps/web-platform/infra/cron-egress-firewall.test.sh && bash apps/web-platform/infra/infra-config-handler-bootstrap.test.sh && bash apps/web-platform/infra/journald-config.test.sh` all exit 0.
7. `bash scripts/followthroughs/server-tf-provisioner-set-e-sweep-5089.sh` exits 0 (probe PASS against the branch's server.tf).
8. PR body contains `Closes #5101` (as instructed by the issue pipeline; the follow-through probe becomes a no-op on the closed issue), plus `Ref #5046` and `Ref PR #5089`, plus a `## Changelog` section; semver label `semver:patch`.

### Post-merge (automated — no operator steps)

9. `apply-web-platform-infra.yml` fires automatically on merge (paths filter `apps/web-platform/infra/**`) and its SSH apply succeeds. Verification: `gh run list --workflow=apply-web-platform-infra.yml --limit 1 --json conclusion,headSha` shows `success` for the merge SHA. Automation: ship-phase post-merge verification via `gh` CLI (placement 2 per the automation-feasibility gate).
10. If the apply FAILS at a newly-gated command: triage per the Hypotheses section (L3 handshake vs. L7 command failure), then fix-forward (explicit `if/exit-1` or host-state fix via a follow-up `.tf` change) — the failure is the silent-green defect surfacing loudly, which is this change working as designed. The issue is already closed via `Closes`; a failed apply opens its own loop via the workflow-failure signal (`wg-after-a-pr-merges-to-main-verify-all` applies).
11. `infra_config_handler_bootstrap`'s gated block live-verifies on the next natural `apply-deploy-pipeline-fix.yml` run (fires on ci-deploy.sh / webhook.service / cat-deploy-state.sh edits). Automation: not separately triggerable without a content change to its trigger files; deferred to the next natural run by design — failure there surfaces as a workflow failure, same loop as AC10.

## Open Code-Review Overlap

One open `code-review` issue references `apps/web-platform/infra/server.tf`:

- **#2197** (refactor(billing): SubscriptionStatus type + single-instance throttle doc) — references server.tf only as the hypothetical site of a future `count = 2` on `hcloud_server`. **Acknowledge:** different concern entirely; this PR adds no `count`/`for_each` and does not touch the `hcloud_server` resource. #2197 remains open, no update needed.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the blast surface is the CI infra-apply pipeline. Worst case, a newly-gated intermediate command aborts the apply mid-provisioner; the host retains its current working configuration (all swept commands are idempotent re-asserts of already-applied state) and the workflow fails loudly. No user-facing flow, page, or data path changes.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure vector — the diff adds shell `set -e` statements to existing provisioner scripts; no secrets, no data surfaces, no auth changes.
- **Brand-survival threshold:** none — reason: operator/CI-facing infra apply gating only; failure mode is a loud CI abort with zero user-visible effect, and the change strictly converts silent failures into loud ones.
- threshold: none, reason: the diff touches sensitive paths (`apps/web-platform/infra/`, `infra-validation` workflow) but adds only shell errexit gating to existing Terraform-managed provisioner scripts plus a read-only CI drift guard — no secrets, no auth, no data surfaces, no deploy-behavior change beyond failing loudly instead of silently. (Explicit scope-out per preflight Check 6 / deepen-plan Phase 4.6 — sensitive-path regex matches `apps/[^/]+/infra/` and `.github/workflows/*infra-validation*.yml`.)

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (inline — pipeline context; no Task tool available in this planning subagent, so the CTO-lens assessment was performed in-pass rather than via agent spawn)
**Assessment:** Pure infrastructure-hardening change inside an existing Terraform root. Follows the in-repo precedent exactly (#5089 cron_egress_firewall block, server.tf:784-792, including the rationale comment). Risk concentrates at first post-merge apply (latent intermediate failures surfacing); blast radius is an aborted apply, not a degraded host, because every swept command re-asserts existing state. The drift guard converts a one-time sweep into a permanent invariant, which is the correct CTO-level response to a defect class that recurred 7 times. No new dependencies, providers, or resources.

**Product/UX Gate:** not applicable — no UI-surface files in Files to Edit/Create (mechanical override scanned: `.tf`, `.sh`, `.yml` only); Product tier NONE.

**GDPR gate (Phase 2.7):** skipped — no regulated-data surface (no schemas, migrations, auth flows, API routes, `.sql`), and none of the (a)-(d) cross-controller triggers fire.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/server.tf` only — 11 added inline strings inside existing `terraform_data` provisioners. **No new resources, no provider changes, no version-pin changes, no new variables, no sensitive values.** `triggers_replace` expressions untouched (they key on artifact file hashes + server id, not on inline content).

### Apply path

- **Existing auto-apply workflow (no manual steps).** Merge to main fires `apply-web-platform-infra.yml` (paths `apps/web-platform/infra/**`); its token-gated SSH apply `-target=`s the 8 SSH siblings, which are absent from CI state ("will be created" — documented expected behavior, #1409/#4844), so all 7 issue-scoped resources re-provision with the gated scripts on merge. The bridge resource re-provisions on the next `apply-deploy-pipeline-fix.yml` run. **No taint, no `-replace`, no operator SSH, no downtime** (sub-second journald/webhook daemon re-asserts are the heaviest operations, identical to every prior apply).

### Distinctness / drift safeguards

- No state-shape change; the "will be created" drift-report behavior is unchanged. The new drift guard (`server-tf-set-e.test.sh`) is a SOURCE-side invariant: it prevents future provisioners from shipping un-gated, complementing the existing probe-string guards (`cron-egress-firewall.test.sh`) which only `set -e` makes load-bearing.

### Vendor-tier reality check

- N/A — no vendor resources created or modified.

## Observability

```yaml
liveness_signal:
  what: apply-web-platform-infra.yml run conclusion for the merge SHA (the SSH apply re-runs every gated provisioner)
  cadence: per merge touching apps/web-platform/infra/** (this PR triggers one) + workflow_dispatch escape hatch
  alert_target: GitHub Actions workflow-failure notification (existing channel for this workflow)
  configured_in: .github/workflows/apply-web-platform-infra.yml
error_reporting:
  destination: terraform provisioner abort -> failed workflow run with the failing inline command named in the job log
  fail_loud: yes — that is the entire point of the change; set -e converts silent intermediate failures into apply aborts
failure_modes:
  - mode: newly-gated intermediate command exits non-zero on the live host at first post-merge apply
    detection: apply-web-platform-infra.yml run failure; log line names the command
    alert_route: GitHub Actions failure notification -> triage per Hypotheses section (L3 handshake vs L7 command)
  - mode: future provisioner added without set -e (regression of the invariant)
    detection: server-tf-set-e.test.sh fails in infra-validation.yml on the PR
    alert_route: red PR check (pre-merge, cannot land)
  - mode: drift-guard parser drift (awk finds < 13 blocks)
    detection: guard's vacuous-pass floor fails the test loudly
    alert_route: red PR check
logs:
  where: GitHub Actions run logs for apply-web-platform-infra.yml / infra-validation.yml
  retention: GitHub default (90 days)
discoverability_test:
  command: gh run list --workflow=apply-web-platform-infra.yml --limit 1 --json conclusion,headBranch
  expected_output: latest run with conclusion success after merge (no ssh anywhere in the verification path)
```

## Risks & Mitigations

1. **A latent intermediate failure surfaces at first gated apply** (most plausible candidates: `systemd-tmpfiles`, `apparmor_parser -r`, unit enable). *Mitigation:* every provisioner has applied repeatedly with its last-command assertions passing (is-active/test/grep asserts), implying healthy units; if one does surface, the apply aborts loudly, host config is unchanged (idempotent re-asserts), and the fix-forward is a scoped explicit guard — exactly the audit→guard loop #5101 prescribes. This risk IS the feature.
2. **Mid-block abort leaves partial host state** (e.g., journald restarted but a later assert fails). *Mitigation:* this failure class already exists today whenever a LAST command fails; `set -e` adds no new class, it only moves detection earlier. All blocks re-run idempotently on the next apply.
3. **The 8 siblings are NOT actually re-created at merge** (if they were present in R2 state with unchanged triggers, provisioners would not re-run and live verification would defer). *Mitigation:* the issue, the workflow header (lines 16-31), and every resource's own comment assert the "will be created" CI-state behavior; even in the contrary case, the text-level done condition and follow-through probe still PASS, and the gating takes effect on the next natural re-provision — strictly better than status quo either way.
4. **awk guard brittleness against future HCL formatting.** *Mitigation:* flag-based parser (not `/start/,/end/` ranges, per the awk self-match sharp edge) + the ≥ 13 block-count floor makes parser drift fail loud, never silently green.
5. **Precedent-diff (deepen-plan Phase 4.4 — pattern-bound behavior).** Canonical in-repo precedent for `set -e`-gated inline blocks: `cron_egress_firewall`, server.tf:736-742 (pre-`file` block) and server.tf:784-819 (post-`file` block with rationale comment). Side-by-side: the precedent puts `"set -e",` as the literal first list element with a block comment above `inline = [` explaining the no-implicit-errexit join; this plan reproduces exactly that shape in all 11 blocks. The precedent's second distinctive element — explicit `if cmd; then echo FAILED; exit 1; fi` probes — is deliberately NOT reproduced because it exists solely for `!`-prefixed-pipeline errexit exemption, and a live grep confirmed zero `"!`-prefixed inline elements outside the cron block (verified 2026-06-10: `grep -n '"\!' server.tf` → no matches; the only `if !` is cron's own probe at line 813). Drift-guard precedent: `bwrap-userns-sysctl.test.sh` (token-anchored server.tf guard wired as a named `infra-validation.yml` step).

## Test Scenarios

1. **RED:** guard vs. unedited server.tf → exit 1, 11 `FAIL block` lines, `blocks=13 ok=2`.
2. **GREEN:** guard vs. swept server.tf → exit 0, `blocks=13 ok=13`.
3. **Vacuous-pass:** guard vs. a file where the awk parses 0 blocks (simulated by pointing at an empty temp file during guard development) → exit 1 via the block-count floor.
4. **Follow-through parity:** `scripts/followthroughs/server-tf-provisioner-set-e-sweep-5089.sh` → exit 0 on the branch.
5. **No-regression:** 4 sibling server.tf guards + `terraform fmt -check` + `terraform validate` + `actionlint` all pass.

## Alternative Approaches Considered

| Alternative | Verdict |
|---|---|
| Sweep only the 7 issue-named resources (9 or 12 count, depending on per-resource vs per-block) | Rejected — leaves the bridge block (444) carrying a comment that lies about its own gating, and forces the drift guard to carry an exclusion list. Full-file invariant is simpler and grep-verified (the issue's enumeration was stale per plan-time grep). |
| Skip the drift guard; rely on the follow-through probe | Rejected — the probe is a one-shot closure mechanism (and moot once `Closes` fires); without a CI guard the 8th future provisioner regresses the same way the last 7 did. Also `cq-write-failing-tests-before` would leave this change with zero tests. |
| Rewrite assertions as explicit `if/exit-1` probes (full #5089 parity) | Rejected — #5089 needed `if/exit-1` only for `!`-prefixed pipeline probes (errexit-exempt under POSIX). No such pipelines exist in the 11 swept blocks; plain commands gate correctly under `set -e`. Minimal diff wins. |

No deferrals requiring tracking issues (the bridge-block extension is folded in, not deferred).

## PR Body Reminder

`Closes #5101` (explicit pipeline instruction; in body, not title, per `wg-use-closes-n-in-pr-body-not-title-to`), `Ref #5046`, `Ref PR #5089`, `## Changelog` section, `semver:patch`.
