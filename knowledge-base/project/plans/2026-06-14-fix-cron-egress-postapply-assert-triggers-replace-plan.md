---
title: "fix(infra): fold cron_egress_firewall post-apply assertion block into triggers_replace"
issue: 5289
type: fix
classification: infra-refactor
lane: cross-domain
brand_survival_threshold: none
date: 2026-06-14
---

# fix(infra): fold the `cron_egress_firewall` post-apply assertion block into `triggers_replace` 🛠️

## Overview

`terraform_data.cron_egress_firewall` (`apps/web-platform/infra/server.tf`) keys its `triggers_replace.config_hash` on the **9 delivered artifact files** + `hcloud_server.web.id`, but **not** on the inline `remote-exec` **post-apply assertion block** (the 2nd `remote-exec`, `server.tf:802-885`). An edit to that block alone leaves the hash unchanged → terraform sees `0 changed` → the new assertion never runs on the live host until an *unrelated* delivered-file change or a VM replacement re-provisions the resource.

PR #5280 demonstrated this exactly: it added the `ASSERT-FAILED: <name>` self-reporting sentinels, and its merge apply ([run 27500866477](https://github.com/jikig-ai/soleur/actions/runs/27500866477), merge `c9b8f0c06`) reported `Apply complete! Resources: 0 added, 0 changed, 0 destroyed` — the sentinels are in the repo but never executed on the host.

**Chosen approach: #1 (extract the assertion block to a delivered script).** Move the 2nd-`remote-exec` body into a new `cron-egress-postapply-assert.sh`, `file()`-provision it like the loader/resolver, fold `file("${path.module}/cron-egress-postapply-assert.sh")` into the `config_hash` join, and reduce the 2nd `remote-exec` to running the delivered script. This makes the block hashed (re-fires on change), directly unit-testable (vs. `awk`-extracting HCL strings), and consistent with the existing loader/resolver/orphan-reaper delivery pattern. This is the issue's **recommended** approach.

**Why not the alternatives:**
- **#2 (hash the inline block via a `local`/`templatefile`)** keeps the assertion logic embedded in HCL — the test suite would still `awk`-slurp `server.tf` (the brittle pattern the current `Phase 2.1` checks already exhibit), and the block stays un-unit-testable.
- **#3 (`sha256(file("server.tf"))`)** rejected by the issue as too broad — every unrelated `server.tf` edit would re-provision the firewall (a flush+repopulate of the live `SOLEUR-EGRESS` chain).

## Research Reconciliation — Spec vs. Codebase

No separate spec file exists (direct-to-plan path; no brainstorm). The issue body is the spec. Every cited artifact was verified against the worktree (premise validation below). One material divergence vs. the issue's framing was found and is folded in:

| Issue claim | Reality (verified) | Plan response |
|---|---|---|
| "Keep the `ASSERT-FAILED` sentinels + the `cron-egress-firewall.test.sh` drift-guards (update them to read the new script)." | The drift-guards are **deeper than a grep retarget**: `cron-egress-firewall.test.sh` Phase 2.1 (lines 388-468) `awk`-extracts the assertion block **from `$SERVER_TF`** and runs ~25 assertions on it (sentinel count ≥15, no-unguarded-command, journalctl-tail, 5 protected sentinels, runbook-name parity). ALL must retarget from `$SERVER_TF` to the new script. | Phase 3 rewrites the extraction source. The block markers (`chmod +x …` start / `echo host-egress-ok` end) become the **whole script body**, simplifying extraction to "read the file" rather than `awk`. |
| (implicit) extraction is hash-neutral | `server-tf-set-e.test.sh` requires **`>= 13` remote-exec inline blocks** each opening with `"set -e"`. Extraction removes one inline block (or replaces its body with a single `bash <script>` line). The floor and the `set -e`-ownership move into the script. | Phase 2 keeps a (now 1-line) 2nd `remote-exec` that runs `bash /usr/local/bin/cron-egress-postapply-assert.sh` with `set -e` first; the extracted **script** also opens with `set -e`. Phase 3 re-checks the `>= 13` floor against the post-edit count and adjusts the floor + comment with evidence if the count drops to 12. |
| (implicit) cloud-init unaffected | `cloud-init.yml` (fresh-host mirror) does **not** carry the assertion block today — it only `write_files` the loader/resolver/allowlists and `enable --now`s the units. The post-apply assertions run only via the SSH `remote-exec`. | Phase 4: mirror the new script into `cloud-init.yml write_files` for parity (the drift-guard's "cloud-init fresh-host mirror" section already pins loader/resolver/allowlist; add the assert script so a fresh host carries it). Fresh-host **execution** of the assertions stays out of scope (cloud-init runs pre-deploy, before a container exists — the container probes would WARN-skip exactly as the SSH block already handles). |

### Premise Validation

All issue references hold on the worktree (= `origin/main` + this branch's empty diff so far). Checked: PR #5280 — **MERGED** `2026-06-14T13:48:58Z` (the surfacing PR, confirmed). `apps/web-platform/infra/server.tf` — exists; `terraform_data.cron_egress_firewall` at `:719`, `triggers_replace.config_hash` at `:724` (9 `file()` artifacts + `server_id`), 2nd `remote-exec` assertion block at `:802-885`. `cron-egress-firewall.test.sh` — exists (473 lines), Phase 2.1 `awk`-extracts the block from `$SERVER_TF` (`:388-468`). `server-tf-set-e.test.sh` — exists, floor `>= 13` blocks. Apply workflow `.github/workflows/apply-web-platform-infra.yml:531` `-target=terraform_data.cron_egress_firewall` (SSH-block apply, run via `infra-validation.yml:167`). Runbook `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md` — exists (sentinel-name parity target). No ADR rejects extract-to-delivered-script (it is the established loader/resolver/orphan-reaper pattern). No open `code-review` issue touches this surface (the one `server.tf` hit, #2197, is billing). **Nothing stale.**

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing directly — this is a host-side firewall provisioning correctness fix. The worst realistic failure is the one-time `triggers_replace` re-provision flushing+repopulating the live `SOLEUR-EGRESS` chain incorrectly, which (if the loader's availability-ordering were violated) could momentarily drop a cron's egress and miss a scheduled check-in. The loader populates sets **before** installing the default-drop (asserted in `cron-egress-firewall.test.sh`), so there is **no egress gap** by design.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — no data path, no secret, no regulated surface. The change moves an assertion block from inline HCL to a delivered `.sh`; it neither reads nor writes user data.

**Brand-survival threshold:** none, reason: pure infra-provisioning refactor of a self-asserting firewall block; no user-facing artifact, no data path, no secret. The one transient risk (re-provision flush) is covered by the loader's existing availability-ordering invariant and verified green post-apply by the very block being moved.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — script exists & is byte-equal to the moved block.** `apps/web-platform/infra/cron-egress-postapply-assert.sh` exists, opens with `set -e` as its first executable line, and its body is the verbatim assertion sequence (`chmod +x …` through `echo host-egress-ok`) previously inline at `server.tf:824-883`. Verify: `bash -n apps/web-platform/infra/cron-egress-postapply-assert.sh` exits 0.
- [ ] **AC2 — config_hash folds the new script.** `git grep -n 'file("\${path.module}/cron-egress-postapply-assert.sh")' apps/web-platform/infra/server.tf` returns exactly 1 hit **inside the `config_hash = sha256(join(",", [ … ]))` list** (so an edit to the script changes the hash → re-provisions). Verify the hit sits between `:724` and `:734` (the join list), not in the `file` provisioner block.
- [ ] **AC3 — script delivered via `file` provisioner.** `server.tf` carries a `provisioner "file" { source = "${path.module}/cron-egress-postapply-assert.sh"; destination = "/usr/local/bin/cron-egress-postapply-assert.sh" }`, ordered AFTER the 9 artifact `file` provisioners and the setup `remote-exec`, BEFORE the run `remote-exec`.
- [ ] **AC4 — 2nd remote-exec runs the script.** The final `remote-exec` inline is `["set -e", "chmod +x /usr/local/bin/cron-egress-postapply-assert.sh", "bash /usr/local/bin/cron-egress-postapply-assert.sh"]` (or equivalent that `chmod +x`es then executes it). It opens with `set -e` (satisfies `server-tf-set-e.test.sh`).
- [ ] **AC5 — set-e floor holds.** `bash apps/web-platform/infra/server-tf-set-e.test.sh` exits 0. If the parsed block count dropped from 14→13 (assertion-block body collapsed to a 1-line runner), the floor `>= 13` still passes unchanged; if it dropped to 12, the floor and its inline comment are updated **with evidence** in the same commit.
- [ ] **AC6 — drift-guard retargeted & green.** `cron-egress-firewall.test.sh` Phase 2.1 extracts the assertion block from `cron-egress-postapply-assert.sh` (NOT `$SERVER_TF`). `bash apps/web-platform/infra/cron-egress-firewall.test.sh` reports `RESULT: N passed, 0 failed`. All ≥15 sentinels, the 5 protected sentinels, the journalctl-tail surface, runbook-name parity, and the non-vacuity probe still pass against the new source.
- [ ] **AC7 — server.tf delivery anchor for the new script.** `cron-egress-firewall.test.sh` "-- server.tf delivery --" section gains a `source = "${path.module}/cron-egress-postapply-assert.sh"` delivery assert AND a `file("${path.module}/cron-egress-postapply-assert.sh")` trigger-fold assert, mirroring the 9 existing artifact pairs.
- [ ] **AC8 — cloud-init mirror.** `cloud-init.yml` `write_files` the new script to `/usr/local/bin/cron-egress-postapply-assert.sh`, and `cron-egress-firewall.test.sh` "-- cloud-init fresh-host mirror --" gains a matching `assert_grep`. `bash apps/web-platform/infra/cloud-init.test.sh` (if present) or `cron-egress-firewall.test.sh` green.
- [ ] **AC9 — full infra suite green.** `bash .github/workflows/infra-validation.yml`-listed shell tests for this surface pass locally: `cron-egress-firewall.test.sh`, `server-tf-set-e.test.sh`, and `cd plugins/soleur && ../../node_modules/.bin/vitest run test/terraform-target-parity.test.ts` (the apply-target parity union) all exit 0.
- [ ] **AC10 — `terraform fmt` + `validate` clean.** `cd apps/web-platform/infra && terraform fmt -check` passes on `server.tf`; `terraform validate` (against the existing root, no new providers) parses with no error.
- [ ] **AC11 — PR body uses `Ref`, not `Closes`.** Per the ops-remediation class, the PR body says `Ref #5289` (NOT `Closes #5289`) — the live re-provision happens **post-merge** at `apply-web-platform-infra.yml` apply time; `#5289` is closed in the post-merge step after the apply reports the block green. (Threshold is `none`, but the resource only re-fires when prod applies, so the closure is post-apply.)

### Post-merge (operator / automated)

- [ ] **AC12 — re-provision applied & green.** The merge to `main` touching `apps/web-platform/infra/**` triggers `apply-web-platform-infra.yml`; its `-target=terraform_data.cron_egress_firewall` apply reports `1 added/changed` (the resource replaced because `config_hash` now includes the script). The 2nd `remote-exec` runs `cron-egress-postapply-assert.sh` and exits 0 (all sentinels green). **Automation:** read the apply run's conclusion via `gh run list --workflow apply-web-platform-infra.yml --limit 1 --json conclusion,databaseId` + `gh run view <id> --log` grep for `Apply complete` and absence of `ASSERT-FAILED:`. NOT operator dashboard-watching.
- [ ] **AC13 — close the issue.** After AC12 confirms green apply, `gh issue close 5289 --comment "<apply-run-url> re-provisioned the resource; post-apply assertion block ran green on the live host"`.

## Implementation Phases

### Phase 1 — Read & RED (tests first)
1. `Read` `server.tf:719-886`, `cron-egress-firewall.test.sh` (esp. `:379-468` Phase 2.1), `server-tf-set-e.test.sh`, `cloud-init.yml` cron-egress section.
2. **Write failing assertions FIRST** (`cq-write-failing-tests-before`): in `cron-egress-firewall.test.sh`, add the new delivery/trigger-fold asserts (AC7), the cloud-init mirror assert (AC8), and retarget Phase 2.1 extraction to `cron-egress-postapply-assert.sh` (AC6). Run the suite — it must FAIL (script + delivery + trigger-fold absent).

### Phase 2 — Extract & wire (`server.tf` + new script)
1. Create `apps/web-platform/infra/cron-egress-postapply-assert.sh`: shebang `#!/usr/bin/env bash`, `set -e` first, then the verbatim lines `server.tf:824-883` (the `chmod +x …` through `echo host-egress-ok` sequence, including the `ASSERT-FAILED` sentinels, journalctl tails, container probes, and the fresh-host WARN-skip branch). Preserve the leading comments as script-header comments.
2. In `server.tf`: add `file("${path.module}/cron-egress-postapply-assert.sh")` to the `config_hash` join list (AC2); add the `provisioner "file"` for it after the 9 artifact deliveries (AC3); replace the 2nd `remote-exec` body with the 3-line runner (`set -e` / `chmod +x` / `bash /usr/local/bin/cron-egress-postapply-assert.sh`) (AC4).
3. `terraform fmt server.tf`; `terraform validate`.

### Phase 3 — Retarget drift-guards & GREEN
1. Confirm `cron-egress-firewall.test.sh` Phase 2.1 now extracts from the script (the whole script body IS the block, so extraction simplifies to reading the file between `set -e` and `echo host-egress-ok`, or just reading the file). Keep the `>=15` sentinel floor, the unguarded-command check, the 5 protected sentinels, journalctl-tail, runbook-name parity, and the non-vacuity probe — all now sourced from the script.
2. Re-run `server-tf-set-e.test.sh`; if the block count fell below the floor, update the `>= 13` floor + comment with evidence (AC5).
3. Run all three suites → GREEN (AC9).

### Phase 4 — Cloud-init mirror & docs
1. Add the script to `cloud-init.yml write_files` (mode `0755`, path `/usr/local/bin/cron-egress-postapply-assert.sh`) (AC8). Note: cloud-init does NOT execute the assertions (no container at fresh-host time — the WARN-skip branch handles it); this is artifact-parity only.
2. Verify the runbook `cron-egress-blocked.md` still documents every sentinel name (parity test enforces this; no rename introduced, so it should pass unchanged — confirm).

### Phase 5 — Ship
1. `terraform fmt -check`, full suite green, push, open PR with `Ref #5289` (AC11), split AC into Pre-merge / Post-merge subsections.

## Infrastructure (IaC)

This is a **pure-edit refactor against already-provisioned infra** — no new Terraform root, no new vendor, no new secret, no new server. It extends the existing `apps/web-platform/infra` root.

### Terraform changes
- **Files:** `apps/web-platform/infra/server.tf` (existing root — modify `terraform_data.cron_egress_firewall`), `apps/web-platform/infra/cron-egress-postapply-assert.sh` (new delivered artifact, mirrors the loader/resolver/orphan-reaper `file()`+`config_hash` pattern), `apps/web-platform/infra/cloud-init.yml` (fresh-host mirror).
- **Providers:** none added. No version-pin changes.
- **Sensitive variables:** none. The block reads no secret (it `nft list`s, `docker exec`s a curl probe, `systemctl`s units). `var.ci_ssh_private_key` is the pre-existing SSH connection key, unchanged.

### Apply path
- **(c) taint + `terraform apply -replace`** — `terraform_data.cron_egress_firewall` is replaced on the next apply because `config_hash` now folds the script. This is the issue's documented **one-time re-provision**. It is a pure on-host re-provision (no `when=destroy` provisioner), flush+repopulating the live `SOLEUR-EGRESS` chain. **Blast radius:** the loader's availability-ordering (sets populate before default-drop installs, asserted in `cron-egress-firewall.test.sh:133`) guarantees **no egress gap**. **Downtime:** none expected; verify the post-apply block green afterward (AC12). The apply is already `-target=terraform_data.cron_egress_firewall`-scoped in `apply-web-platform-infra.yml:531`, so no unrelated resource is touched.

### Distinctness / drift safeguards
- `dev != prd`: this resource only exists in the web-platform prd infra root; there is no dev mirror. No `lifecycle.ignore_changes` change. The `triggers_replace` map already excludes `user_data`-class churn by construction (it lists explicit `file()` hashes + `server_id`).
- State note: `triggers_replace` values land in `terraform.tfstate` (the R2-backed encrypted backend already in use); the script content is hashed, not stored verbatim.

### Vendor-tier reality check
- N/A — no vendor resource created; Hetzner/Cloudflare/Sentry tiers unaffected.

## Observability

```yaml
liveness_signal:
  what: "cron-egress-resolve.timer Sentry Crons check-in (sentry_checkin ok) every resolve tick; unchanged by this PR"
  cadence: "per resolve.timer fire (existing schedule)"
  alert_target: "Sentry Crons monitor (slug in cron-monitors.tf, parity-asserted by cron-egress-firewall.test.sh:326)"
  configured_in: "apps/web-platform/infra/cron-egress-resolve.sh + sentry/cron-monitors.tf"
error_reporting:
  destination: "terraform apply log (GitHub Actions run for apply-web-platform-infra.yml) — the 2nd remote-exec surfaces ASSERT-FAILED:<name> sentinels on the LAST output lines when the block fails; cron runtime failures page via cron-egress-alarm@.service OnFailure= (Sentry status=error + Resend email)"
  fail_loud: true
failure_modes:
  - mode: "post-apply assertion fails on re-provision (ruleset inert / containment broken)"
    detection: "ASSERT-FAILED:<name> sentinel on the apply run's last output lines (stdout suppressed otherwise)"
    alert_route: "apply workflow run goes red; gh run view --log greps the sentinel name → cron-egress-blocked.md runbook row (no SSH, hr-no-ssh-fallback-in-runbooks)"
  - mode: "script edit silently no-ops (the bug this PR fixes)"
    detection: "config_hash now folds the script → terraform reports the resource as changed; CI plan diff is non-empty"
    alert_route: "apply-web-platform-infra.yml plan step shows 1 to change; AC12 reads gh run conclusion"
  - mode: "re-provision flush drops a cron's egress"
    detection: "cron-egress-resolve Sentry Crons missed check-in (dead-timer detection) + egress-blocked: journal log → resolver Sentry event"
    alert_route: "Sentry Crons monitor + cron-egress-alarm@.service email"
logs:
  where: "GitHub Actions apply run log (sentinels); host journalctl -u cron-egress-firewall.service (loader die tail, surfaced into the apply log by the firewall-restart sentinel)"
  retention: "GitHub Actions default log retention (90d); journald per host journald-soleur.conf"
discoverability_test:
  command: "gh run list --workflow apply-web-platform-infra.yml --limit 1 --json conclusion,databaseId && gh run view <id> --log | grep -E 'Apply complete|ASSERT-FAILED:'"
  expected_output: "'Apply complete! Resources: 1 ... changed' with NO 'ASSERT-FAILED:' line (block ran green on the live host)"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. No UI surface (no path under `components/**`, `app/**/page.tsx`, etc. in Files to Edit/Create). No Product/UX gate. No regulated-data surface (no schema/migration/auth/API-route/`.sql` touched), so GDPR gate (Phase 2.7) skipped.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` was queried for the three planned file paths; the only hit on `server.tf` (#2197) is a billing/`SubscriptionStatus` scope-out unrelated to the egress firewall. `cron-egress-firewall.test.sh` and `cron-egress-postapply-assert.sh` returned zero.

## Files to Create

- `apps/web-platform/infra/cron-egress-postapply-assert.sh` — the extracted post-apply assertion block (verbatim `server.tf:824-883`), `set -e` first.

## Files to Edit

- `apps/web-platform/infra/server.tf` — fold `file(".../cron-egress-postapply-assert.sh")` into `config_hash` join; add `file` provisioner for the script; collapse 2nd `remote-exec` to the 3-line runner.
- `apps/web-platform/infra/cron-egress-firewall.test.sh` — retarget Phase 2.1 extraction from `$SERVER_TF` to the new script; add delivery + trigger-fold asserts (AC7); add cloud-init mirror assert (AC8).
- `apps/web-platform/infra/server-tf-set-e.test.sh` — re-verify/adjust the `>= 13` block-count floor + comment if the inline block count drops (AC5).
- `apps/web-platform/infra/cloud-init.yml` — `write_files` the new script for fresh-host parity.
- `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md` — confirm sentinel-name parity holds (no rename introduced; verify only — edit only if the parity test newly fails).

## Risks & Mitigations

- **One-time re-provision flush.** Mitigated by the loader's availability-ordering (sets before default-drop), asserted in `cron-egress-firewall.test.sh:133-137`; no egress gap. Verify green post-apply (AC12).
- **`set -e` semantics move into the script.** The script must open with `set -e` (terraform's inline-join errexit reasoning applies equally to a `bash script.sh` invocation — the script is its own shell). Mitigated by AC1 (`bash -n` + `set -e` first) and the `server-tf-set-e.test.sh` runner-line check (AC5). **Precedent:** the loader/resolver/orphan-reaper scripts are all standalone `set -e`/`set -uo pipefail` scripts delivered via `file()` and hashed — this is the established pattern, not novel.
- **Drift-guard extraction simplification could over/under-match.** The block's start/end markers (`chmod +x …` / `echo host-egress-ok`) become the whole script, so extraction is "read the file" — strictly simpler and less brittle than the current `awk`-slurp of `$SERVER_TF`. Mitigated by AC6 (full suite green, including the non-vacuity probe).
- **Block-count floor false-FAIL.** If terraform-fmt or a future block reorder shifts the count, `server-tf-set-e.test.sh` floor (`>= 13`) may need an evidence-bearing bump. Handled inline at AC5.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above; threshold `none` with reason — diff touches an infra surface but no sensitive path under preflight Check 6.1's regex, so the `threshold: none, reason: …` scope-out form is satisfied.)
- The `cron-egress-firewall.test.sh` Phase 2.1 block carries a `>= 15` sentinel **floor** with slack — when retargeting, do NOT let a sentinel get silently dropped under the slack. The `UNGUARDED` command-detection regex (`:409`) is the real guard; keep it pointed at the script.
- `server-tf-set-e.test.sh` parses `provisioner "remote-exec"` blocks by `awk` flag-state; the collapsed 2nd `remote-exec` (now 3 lines) is still a remote-exec block that must open with `"set -e",` — do not accidentally make it `script =` (the test's known fail-closed limit treats a `script =` provisioner as a dangling arm).
- Cloud-init mirrors the **artifact**, not its **execution** — the post-apply container probes have no container to probe at fresh-host time and WARN-skip; do NOT add an `enable`/`runcmd` that runs the assert script in cloud-init.

## Test Scenarios

- **T1 (re-fire on script edit):** after the PR, a 1-char edit to `cron-egress-postapply-assert.sh` produces a non-empty `terraform plan` diff (resource changed) — the core bug fixed. Verified structurally by AC2 (script in `config_hash` join).
- **T2 (drift-guard green on new source):** `cron-egress-firewall.test.sh` `RESULT: N passed, 0 failed` with Phase 2.1 reading the script.
- **T3 (set-e floor):** `server-tf-set-e.test.sh` PASS.
- **T4 (parity union):** `terraform-target-parity.test.ts` PASS (apply-target set unchanged — no new resource address).
- **T5 (fmt/validate):** `terraform fmt -check` + `terraform validate` clean.
- **T6 (post-apply live):** AC12 — apply run reports `1 changed`, no `ASSERT-FAILED:`.
