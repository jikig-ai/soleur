---
title: "fix(infra): make the workspaces-luks escrow rehearsal fully autonomous + get the escrow probe GREEN (#6649)"
issue: 6649
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-119 (addendum)
created: 2026-07-18
branch: feat-one-shot-6649-luks-escrow-autonomy
---

# fix(infra): workspaces-luks escrow rehearsal — fully autonomous + escrow probe GREEN (#6649)

## Enhancement Summary

**Deepened:** 2026-07-18 · **Agents:** security-sentinel, architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer, observability/verify-negative Explore · **Hard gates:** 4.6 (user-brand) PASS, 4.7 (observability) PASS, 4.8 (PAT-shaped) pass-with-benign-Hetzner-token-false-positive, 4.9 (UI-wireframe) N/A.

**Key improvements from the review:**
1. **P1 — token classification corrected:** explicit `-target=doppler_service_token.workspaces_luks` + REMOVE it from `OPERATOR_APPLIED_TOKEN_EXCLUSIONS` (mirror inngest; #5566 silent-un-applied rule) — was "reconcile a comment."
2. **P1 — `.env` on tmpfs would defeat the shred:** relocate to `STATE_DIR` (F7) + consolidate write→trap→run into one `bash -c` (closes the un-trapped-file window).
3. Autonomy gate CONFIRMED sound (freeze-reachable ⟺ gated; empty-string-env affects only autonomy, never safety); split-job recorded as the auditability-preferred fallback.
4. Reachability preconditions (A–F) enumerated — the probe is reached only if the volume is attached, aws-cli installs, and 4 header secrets exist (all post-merge-verified).
5. Two latent P1 host bugs confirmed + fixed (`HOME=/root` on the service unit; `DOPPLER_TOKEN` bake for the daily probe).

See `## Deepen-Plan Review Synthesis` for the full verdict list; taste/scope dissents in `knowledge-base/project/specs/feat-one-shot-6649-luks-escrow-autonomy/decision-challenges.md`.

## Overview

The `/workspaces` LUKS cutover (ADR-119, epic #6588) has a working escrow *design* — `workspaces-cutover.sh` already carries `load_escrow_creds` + `escrow_probe` (the DRY_RUN-safe probe-PUT + negative over-scope probe) and the R2 escrow S3 token is minted with its akid/secret in Doppler `prd_workspaces_luks`. But the rehearsal cannot reach the probe, and every rehearsal blocks on a human. Four host-provisioning + execution-model gaps remain (all verified against the current worktree, not paraphrased):

1. **BLOCKER 3 — content-carrier execution.** The cutover workflow pipes the whole script via `${WEB_HOST_SSH} "$WEB_HOST" "sudo … bash -s" < workspaces-cutover.sh` (`workspaces-luks-cutover.yml:130-131`). Under `set -uo pipefail`, `${BASH_SOURCE[0]}` (`workspaces-cutover.sh:63`, `:475`, `:477-478`) is unbound when the body arrives on stdin — so the emit sibling is never sourced (`emit_drift` degrades to log-only, the Sentry `feature=workspaces-luks op=workspaces-luks-drift` channel goes dark) and the real arm cannot install the luks-monitor units. On a host without `/usr/local/bin/workspaces-luks-emit.sh` already installed (the pre-cutover state), line 63's `||` branch dereferences the unbound `${BASH_SOURCE[0]}` and the script dies immediately — the observed `rc=1` at "Run workspaces-luks cutover".
2. **BLOCKER 4 — the prd_workspaces_luks token never reaches the host script.** `read_key` (`:68/:247`) and the `read_header_*`/`load_escrow_creds` reads (`:74-121`) all run host-side as `doppler secrets get … --config prd_workspaces_luks`, but the workflow's SSH invocation passes only `DRY_RUN`/`ROLLBACK` into the `sudo` env (`:130`) — no Doppler credential reaches the host, and the workflow's own `DOPPLER_TOKEN` is `prd_terraform`-scoped (cannot read `prd_workspaces_luks`). The ONLY credential that can is `doppler_service_token.workspaces_luks` (`workspaces-luks.tf:118-123`, scoped to `prd_workspaces_luks`), which is created but **published nowhere** — no `github_actions_secret`, no bake.
3. **BLOCKER 5 — `WORKSPACES_LUKS_DEV` unset.** `prepare_luks_target` (`:252-253`) dies `WORKSPACES_LUKS_DEV unset or absent` — it runs in BOTH arms and BEFORE `escrow_probe` (`:280`), so fixing blocker 4 alone still never reaches the probe.
4. **AUTONOMY — the human gate sits on the rehearsal.** The cutover job declares `environment: workspaces-luks-cutover` at job level (`workspaces-luks-cutover.yml:62`), whose reviewer set is `[54279]` (`workspaces-luks.tf:207-209`). Every dry-run rehearsal waits on a human approval, even though the dry-run performs NO irreversible operation (freeze/flip are behind `DRY_RUN != 1`; the wipe is a separate `CONFIRM_WIPE` dispatch). We move the gate onto the real freeze arm only, keeping the C19/AC20b human authorization on the irreversible operation.

This is a `single-user incident` brand-survival plan: the surface is sole-copy user source code, and the escrow proof this rehearsal exercises is the ONLY defense against the ADR-119 terminal failure (passphrase/header loss ⇒ unreadable forever). The autonomy change touches the authorization boundary on that irreversible path, so security-sentinel + architecture-strategist review is a hard gate (see `## Architecture Decision`).

## Research Reconciliation — Spec vs. Codebase
<!-- lint-infra-ignore start (automated CI -target apply + SSH-bridge format prose; OPERATOR_APPLIED_* identifier + -target…apply co-occurrence is a false positive) -->

| Task-prescribed claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "tar-pipe … then run `sudo bash /path/workspaces-cutover.sh`" for BOTH cutover.yml AND verify.yml | `verify.yml:81` runs `sudo /usr/local/bin/luks-monitor` (read-only), and its header contract is "MUTATES NOTHING". Running `workspaces-cutover.sh` there would open the real device (`prepare_luks_target`) — breaking the read-only invariant. `WEB_HOST_SSH` already lands as **root** (`-l root`). | Ship the SAME bundle to both hosts, but each runs its correct entrypoint: cutover.yml → `bash <dir>/workspaces-cutover.sh`; verify.yml → `bash <dir>/luks-monitor` (read-only, preserving the MUTATES-NOTHING contract). `sudo` is dropped — `WEB_HOST_SSH` is `ssh … -l root`, so `sudo` is redundant AND its `env_reset` scrubs `HOME`/the sourced env; running the file directly as root preserves `HOME=/root` (needed for `doppler`). This is a deliberate, security-preserving deviation from the literal wording. **Security review must confirm verify.yml stays read-only.** |
| "add a `github_actions_secret WORKSPACES_LUKS_BOOT_TOKEN` in workspaces-luks.tf … provisioned by the DEFAULT allow-list apply" | Confirmed viable. `apply-web-platform-infra.yml:361` already targets `github_repository_environment.workspaces_luks_cutover` in the DEFAULT allow-list. `workspaces-luks.test.sh` A11 counts only `doppler_secret`/`doppler_service_token`/`random_password`/`hcloud_volume` cardinality + forbids `config = "prd"`; a `github_actions_secret` matches none, and `github_repository_environment` already coexists → **A11 stays green.** | Add `github_actions_secret.workspaces_luks_boot_token` to `workspaces-luks.tf`; add `-target=github_actions_secret.workspaces_luks_boot_token` to the DEFAULT allow-list (NOT the scoped cutover `-target` set at `:2660-2664`). |
| (task did not mention) parity-test invariant on the token — **[CORRECTED by deepen-plan architecture review, P1]** | `terraform-target-parity.test.ts:686-688` rule: "Do NOT grow `OPERATOR_APPLIED_TOKEN_EXCLUSIONS` for a token that feeds a github_actions_secret — that is the #5566 silent-un-applied class and MUST be targeted." The `inngest_arm_write` precedent targets BOTH `doppler_service_token.inngest_arm_write` AND `github_actions_secret.doppler_token_inngest_arm` explicitly, and does NOT exclude the token. Publishing `doppler_service_token.workspaces_luks.key` reclassifies it from operator-applied-host-token to **CI-published token**. | **Mirror inngest exactly:** add an EXPLICIT `-target=doppler_service_token.workspaces_luks` to the DEFAULT allow-list (alongside the `github_actions_secret` target) AND **REMOVE** `doppler_service_token.workspaces_luks` from `OPERATOR_APPLIED_TOKEN_EXCLUSIONS`. Do NOT rely on `-target` transitivity + a self-contradicting exclusion (a comment reconciliation alone is insufficient — the classification changed). /work: verify the interaction with the general 5-resource `OPERATOR_APPLIED_EXCLUSIONS` and the scoped cutover gate (the gate asserts only `vc/ac/sc` creates, not a token create, so a pre-created token is fine; the scoped `-target` set at `:2660-2664` still lists the token — idempotent). |
| BLOCKER 4c: "persist the token to /etc/default/luks-monitor … so the daily probe works" | cloud-init bakes `/etc/default/luks-monitor` with ONLY `SOLEUR_SENTRY_DSN` (`cloud-init.yml:422-424`) — NO `DOPPLER_TOKEN`. AND `luks-monitor.service` has NO `Environment=HOME=/root`; a root systemd unit running `doppler` dies `$HOME is not defined` (learning `2026-07-18-web-1-root-doppler-unit-needs-home-…`). | Real arm persists `DOPPLER_TOKEN=<boot token>` into `/etc/default/luks-monitor` (0600 root, preserving the baked DSN). **Also add `Environment=HOME=/root` to `luks-monitor.service`** — a latent bug that would make the daily timer probe fail even with the token present. |
| conditional environment `${{ inputs.dry_run && '' || 'X' }}` (the "obvious" form) | This is **inverted**: `''` is falsy, so `true && '' → ''` then `'' || 'X' → 'X'` ⇒ ALWAYS gated. | Use the fail-closed complement `${{ !inputs.dry_run && 'workspaces-luks-cutover' || '' }}` (truth table in `## Architecture Decision`). This mirrors the existing `DRY_RUN: ${{ inputs.dry_run && '1' || '0' }}` logic (`:110`) — same boolean coercion the file already trusts. |
| `hcloud_volume.workspaces_luks.id` → by-id device | `cloud-init.yml:573-574` mounts `/mnt/data` via `/dev/disk/by-id/scsi-0HC_Volume_${workspaces_volume_id}` — the confirmed convention. Volume name literal is `soleur-web-platform-data-luks` (`workspaces-luks.tf:166`). The Hetzner token variable `hcloud_token` ← Doppler `HCLOUD_TOKEN` in `prd_terraform` (`main.tf:88`, `variables.tf:15`) — a Hetzner API token, NOT a GitHub PAT (no GitHub-App alternative applies). | Derive the id via the hcloud API by volume name using `HCLOUD_TOKEN` (workflow already holds a `prd_terraform` `DOPPLER_TOKEN`); construct `WORKSPACES_LUKS_DEV=/dev/disk/by-id/scsi-0HC_Volume_<id>`. Terraform-output is the documented fallback. |
<!-- lint-infra-ignore end -->

**Premise validation (Phase 0.6):** #6649 is OPEN (title: "wire WORKSPACES_HEADER_BUCKET + R2 creds into the workspaces-luks freeze path"). The prior `#6649` plan (`2026-07-18-fix-6649-workspaces-luks-header-escrow-wiring-plan.md`) delivered ONLY the header-escrow bucket/creds + probe machinery — it does NOT touch content-carrier, boot-token delivery, `WORKSPACES_LUKS_DEV`, or the autonomy gate. All four blockers here are fresh. Every cited file/line/symbol was read directly and holds.

## User-Brand Impact

**If this lands broken, the user experiences:** a `dry_run=true` rehearsal that still cannot prove the escrow path (probe never reached), so the FIRST real freeze runs against an unproven escrow — and if the passphrase/header escrow is in fact unusable, every user's checked-out source code becomes unreadable forever the moment the plaintext backstop is wiped. A subtler failure: the autonomy change mis-gates and lets a real freeze (`dry_run=false`) run WITHOUT the human authorization.
**If this leaks, the user's data is exposed via:** the boot token (`WORKSPACES_LUKS_BOOT_TOKEN`) resolves ~116 `prd` secrets (branch-config inheritance, workspaces-luks.tf:77-89) — a leak of it is a full-prd credential exposure. Its exposure surfaces, each mitigated/scoped-out (review-completeness, #6649):
- *In transit to the host:* delivered ONLY over a mode-0600 root env file via stdin (never `sudo VAR=val`, never argv), shredded on a host-local EXIT trap. Guard: H14 (sudo-independent argv-leak forbiddance).
- *Repo-level GitHub Actions secret* (`github_actions_secret.workspaces_luks_boot_token`): readable by any default-branch workflow. Scope-out: mirrors the accepted `doppler_token_inngest_arm` precedent; fork PRs receive no secrets; main-write == operator trust; and web-1 already carries a full-prd `DOPPLER_TOKEN`, so a repo-secret-exfil attacker gains no net-new capability.
- *Persistent 0600-root copy at `/etc/default/luks-monitor`* (written only in the real freeze arm, for the daily timer probe): outside the `docker run --env-file` TMPENV path, so the CWE-522 container boundary holds; born 0600 via `umask 077` (no world-readable window); mirrors the baked `SOLEUR_SENTRY_DSN` + sibling root-doppler units.
- *Root host mutation on the ungated dry-run:* `ensure_aws` runs `apt-get install` + a SHA256-pinned aws-cli installer as root on every autonomous rehearsal (additive, idempotent, no service restart — full scope-out in `## Architecture Decision`).
- **Brand-survival threshold:** single-user incident

CPO sign-off required at plan time (headless: recorded in frontmatter `requires_cpo_signoff: true`; `user-impact-reviewer` runs at review-time per the review skill's conditional-agent block). security-sentinel + architecture-strategist confirm the autonomy change preserves C19/AC20b.

## Hypotheses (network-outage gate)

The feature description matches SSH/timeout keywords, but this is NOT a connectivity diagnosis. Per the task context and `2026-07-18-cutover-bridge-dryrun-guard-…` the L3/L4 layers are **verified green**: the CF-Tunnel SSH bridge reaches web-1 (private `10.0.1.10`), the bridge runs unconditionally on the dry-run path (`workspaces-luks-cutover.yml:88-93`), and `workspaces-cutover.sh` already runs ON the host. The observed `rc=1` is at **L7 (the script body)** — BASH_SOURCE unbound / missing Doppler token / missing device — not a firewall, DNS, or routing failure. No firewall/`admin_ips`/fail2ban change is proposed or needed (`hr-ssh-diagnosis-verify-firewall` satisfied: firewall confirmed not the cause).

## Implementation Phases

### Phase 0 — Preconditions (grep/verify, no code)
- Confirm `WEB_HOST_SSH` format is `ssh -i <keyfile> -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -l root` (`.github/actions/cf-tunnel-ssh-bridge/action.yml`) — lands as root, pipes tar + stdin.
- Confirm the scoped cutover `-target` set (`apply-web-platform-infra.yml:2660-2664`) is EXACTLY the five workspaces_luks resources — the new `github_actions_secret` must NOT be added there (the sourced `workspaces_luks_cutover_gate` would abort it as `out_of_scope`).
- Verify (WebFetch GitHub Actions docs) that a job `environment:` evaluating to an EMPTY string runs with no environment gate. If NOT confirmed, use the split-job fallback (`## Architecture Decision`).

### Phase 1 — BLOCKER 3: content-carrier → file execution (RED test first)
1. Harden `workspaces-cutover.sh`: replace every `${BASH_SOURCE[0]}` with `${BASH_SOURCE[0]:-}` (`:63`, `:475`, `:477`, `:478`) and, where a bare-empty dirname would resolve to `.`, anchor on `SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"` computed once near the top so file-execution is unambiguous. (`luks-monitor.sh:29` is NOT hardened — code-simplicity: it is always run as a file, so `${BASH_SOURCE[0]}` is never unbound; dropped from scope to keep the change minimal.)
2. In `workspaces-luks-cutover.yml`'s "Run workspaces-luks cutover" step: replace the `bash -s < script` pipe with:
   - **[security P1 — F7]** `REMOTE_DIR=$(${WEB_HOST_SSH} "$WEB_HOST" 'mkdir -p /var/lib/workspaces-luks && chmod 700 /var/lib/workspaces-luks && mktemp -d -p /var/lib/workspaces-luks')` — the bundle + `.env` land on the **persistent `STATE_DIR`, NOT `mktemp -d`'s default `/tmp`**. A tmpfs `/tmp` makes the `shred` a no-op against the raw device — the exact F7 anti-pattern the script already fixed for the LUKS header at `workspaces-cutover.sh:296-297`. The boot token is a full-prd-capable secret, so its temp file MUST be shreddable.
   - `tar czf - -C "$INFRA_DIR" workspaces-cutover.sh workspaces-luks-emit.sh luks-monitor.sh luks-monitor.service luks-monitor.timer | ${WEB_HOST_SSH} "$WEB_HOST" "tar xzf - -C '$REMOTE_DIR'"`
   - **[security P2 — close the write→trap window]** Write the `.env` (Phase 2/3) AND arm the shred trap AND run the script in a SINGLE remote `bash -c`, so the trap covers the `.env`'s ENTIRE lifetime (no window where the 0600 token file exists un-trapped). Because the script now runs as a file, host stdin is free for the `.env` payload: `printf 'DOPPLER_TOKEN=%s\nWORKSPACES_LUKS_DEV=%s\nDRY_RUN=%s\nROLLBACK=%s\n' … | ${WEB_HOST_SSH} "$WEB_HOST" "bash -c 'install -m600 /dev/stdin \"$REMOTE_DIR/.env\"; trap \"shred -u \\\"$REMOTE_DIR/.env\\\" 2>/dev/null || rm -f \\\"$REMOTE_DIR/.env\\\"\" EXIT; set -a; . \"$REMOTE_DIR/.env\"; set +a; bash \"$REMOTE_DIR/workspaces-cutover.sh\"'"` — NO `sudo` (bridge lands `-l root`; dropping sudo preserves `HOME=/root` for `doppler`; execution is `bash <file>`, so a `noexec` mount is irrelevant). Env-file fields are metacharacter-free (dp.st token / `/dev/disk/by-id/…` path / `0`/`1`) so `set -a; . .env` is injection-safe — a Sharp Edge constraint to preserve.
   - Preserve the existing `set +e`/`rc=$?`/`::error::` diagnostic and the `[[ -n "${WEB_HOST_SSH:-}" ]]` guard (diff field-by-field per learning `2026-03-20-ssh-forced-command-workflow-refactoring-drops-parameters`).
   - **[spec-flow/arch P2]** The nested-quoting of this assembled command is fragile — the Phase-5 mutation test MUST exercise the ASSEMBLED command string (that `install`+`trap`+`bash <file>` all appear in one remote invocation), not merely grep for `tar xzf`.
3. Add an `if: always()` teardown step that SSHes `rm -rf "$REMOTE_DIR"` (belt-and-suspenders; the `.env` is shredded by the trap even on SSH drop).
4. In `workspaces-luks-verify.yml`: tar-pipe `luks-monitor.sh` + `workspaces-luks-emit.sh` to a `STATE_DIR` temp dir, deliver the boot token via the **SAME 0600-stdin-env-file + host-local shred-trap discipline** (security/arch P2 — verify.yml widens the token to a second workflow, so it must not regress the delivery discipline), run `bash <dir>/luks-monitor` sourcing the `.env` — replacing `sudo /usr/local/bin/luks-monitor`. Keeps read-only (luks-monitor mutates nothing; verified) and removes the dependency on a prior cutover having installed the binary. **NOTE (scope dissent recorded):** code-simplicity flagged verify.yml as cuttable (it runs an already-installed file, no BASH_SOURCE bug; not on #6649's dry-run-green critical path). Kept per the task's explicit "BOTH workflows" direction + the genuine token-delivery bug (manual `sudo luks-monitor` has no `EnvironmentFile`, so `doppler` fails); dissent logged in `decision-challenges.md`.

### Phase 2 — BLOCKER 4: deliver the prd_workspaces_luks boot token
1. **(a) Publish the token.** Add to `apps/web-platform/infra/workspaces-luks.tf` (mirrors `inngest-arm-write-token.tf`; repo-level — the TF GitHub App cannot write environment secrets):
   ```hcl
   resource "github_actions_secret" "workspaces_luks_boot_token" {
     repository      = "soleur"
     secret_name     = "WORKSPACES_LUKS_BOOT_TOKEN"
     plaintext_value = doppler_service_token.workspaces_luks.key
     # NO lifecycle.ignore_changes — a -replace rotation of the token propagates the new key here.
   }
   ```
<!-- lint-infra-ignore start (DEFAULT-apply -target reclassification prose; OPERATOR_APPLIED_TOKEN_EXCLUSIONS identifier co-occurs with -target…apply — automated CI, not a human step) -->
   **[architecture P1 — mirror the inngest precedent exactly; #5566 silent-un-applied class]** Add TWO explicit `-target` lines to the DEFAULT allow-list in `apply-web-platform-infra.yml` (near `:361`): `-target=doppler_service_token.workspaces_luks` AND `-target=github_actions_secret.workspaces_luks_boot_token` — exactly as `inngest_arm_write` + `doppler_token_inngest_arm` are both targeted. Then **REMOVE `doppler_service_token.workspaces_luks` from `OPERATOR_APPLIED_TOKEN_EXCLUSIONS`** in `terraform-target-parity.test.ts` — the rule at `:686-688` forbids excluding a token that feeds a `github_actions_secret` ("MUST be targeted"), because publishing `.key` reclassifies it from operator-applied-host-token to CI-published token. Do NOT rely on `-target` transitivity + a self-contradicting exclusion (a comment reconciliation is insufficient — the classification changed). **/work MUST verify against the inngest precedent side-by-side** the interaction with (i) the general 5-resource `OPERATOR_APPLIED_EXCLUSIONS` and (ii) the scoped cutover gate (`workspaces-luks-cutover-gate.sh` asserts only `vc/ac/sc` creates, not a token create, so a token already in state from the DEFAULT apply is fine; the scoped `-target` set at `apply-web-platform-infra.yml:2660-2664` still lists the token — idempotent).
   Update the stale `workspaces-luks.tf:190-210` env-gate comment AND the `workspaces-luks-cutover.yml:9-16` workflow comment block (the "environment gate ... covers every dispatch / is the ONLY human authorization" prose) to say the environment is applied ONLY to the real freeze arm (dry-run rehearsals run ungated for autonomy; the reviewer set stays non-empty for the freeze). Both doc sites must be reconciled, not just line 62.
<!-- lint-infra-ignore end -->
2. **(b) Inject into the host script env.** In cutover.yml, add step env `WORKSPACES_LUKS_BOOT_TOKEN: ${{ secrets.WORKSPACES_LUKS_BOOT_TOKEN }}` + a fail-loud presence check. Write the `.env` file:
   ```
   printf 'DOPPLER_TOKEN=%s\nWORKSPACES_LUKS_DEV=%s\nDRY_RUN=%s\nROLLBACK=%s\n' \
     "$WORKSPACES_LUKS_BOOT_TOKEN" "$LUKS_DEV" "$DRY_RUN" "$ROLLBACK" \
     | ${WEB_HOST_SSH} "$WEB_HOST" "install -m600 /dev/stdin '$REMOTE_DIR/.env'"
   ```
   NEVER `sudo VAR=val bash` (leaks the token into the host process list). Shredded on the host-local EXIT trap (Phase 1.2).
3. **(c) Persist for the daily timer (real arm only).** In `workspaces-cutover.sh`, in the `DRY_RUN != 1` arm (near the luks-monitor unit install, `:474-482`), write `DOPPLER_TOKEN=<the boot token from env>` into `/etc/default/luks-monitor` (0600 root) preserving the baked `SOLEUR_SENTRY_DSN`, so `luks-monitor.service`'s `EnvironmentFile` supplies the token to the daily probe. Add `Environment=HOME=/root` to `luks-monitor.service` (a root doppler unit dies without it).

### Phase 3 — BLOCKER 5: derive + pass WORKSPACES_LUKS_DEV
1. In cutover.yml, before writing the `.env`, resolve the volume id:
   ```
   HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN --plain -p soleur -c prd_terraform)
   VID=$(curl -fsS --max-time 15 -H "Authorization: Bearer $HCLOUD_TOKEN" \
     'https://api.hetzner.cloud/v1/volumes?name=soleur-web-platform-data-luks' | jq -r '.volumes[0].id')
   [[ "$VID" =~ ^[0-9]+$ ]] || { echo "::error::could not resolve workspaces_luks volume id"; exit 1; }
   LUKS_DEV="/dev/disk/by-id/scsi-0HC_Volume_${VID}"
   ```
   (Fallback documented: `terraform init` + `terraform show -json | jq …hcloud_volume.workspaces_luks.id`.) `curl --max-time` is pinned (`hr-never-run-commands-with-unbounded-output` / dig-timeout Sharp Edge). Pass `WORKSPACES_LUKS_DEV=$LUKS_DEV` through the Phase 2 `.env`.

### Phase 4 — AUTONOMY: gate only the freeze arm
1. Change `workspaces-luks-cutover.yml:62` from `environment: workspaces-luks-cutover` to `environment: ${{ !inputs.dry_run && 'workspaces-luks-cutover' || '' }}` (fail-closed; truth table in `## Architecture Decision`). Fallback: split into `rehearse` (`if: ${{ inputs.dry_run }}`, no environment) + `freeze` (`if: ${{ !inputs.dry_run }}`, static `environment: workspaces-luks-cutover`) jobs.
2. Amend ADR-119 (`## Architecture Decision`).

### Phase 5 — Tests (write RED first, `cq-write-failing-tests-before`)
Extend `apps/web-platform/infra/workspaces-luks-header.test.sh` (it already loads `$YML`=cutover.yml, `$SH`=script) with mutation-tested assertions:
- The cutover Run step runs the script as a FILE from a tar-shipped dir (asserts `tar xzf` + `bash "$REMOTE_DIR/workspaces-cutover.sh"`; RED on a `bash -s <` re-introduction).
- The boot token is delivered via `install -m600 /dev/stdin` and NEVER via `sudo` argv nor `DOPPLER_TOKEN=…` on a command line (extend the H7 `p_creds_not_in_workflow` family to also forbid a bare `sudo DOPPLER_TOKEN=` / `sudo WORKSPACES_LUKS_BOOT_TOKEN=` argv form).
- The `.env` is shredded on an EXIT trap.
- `WORKSPACES_LUKS_DEV` is passed to the host.
- The environment expression is fail-closed: gate present unless `dry_run` is exactly true (assert the literal `!inputs.dry_run && 'workspaces-luks-cutover'`).
- `luks-monitor.service` carries `Environment=HOME=/root` and `EnvironmentFile=-/etc/default/luks-monitor`.
- `reviewers.users` in `workspaces-luks.tf` stays non-empty (learning `2026-07-17-workflow-env-gate-references-unprovisioned-environment-auto-approves` — two independent checks).
- Confirm `workspaces-luks.test.sh`, `web-1-swap-concurrency-parity.test.sh`, `terraform-target-parity.test.ts`, and `test-workspaces-luks-cutover-gate.sh` still pass (run `bash apps/web-platform/infra/workspaces-luks.test.sh` etc.).

## Files to Edit
- `.github/workflows/workspaces-luks-cutover.yml` — tar-pipe bundle + file execution; boot-token + `WORKSPACES_LUKS_DEV` via 0600 stdin env file; conditional environment; volume-id derivation; teardown.
- `.github/workflows/workspaces-luks-verify.yml` — tar-pipe `luks-monitor.sh`+emit; boot-token delivery; run `bash <dir>/luks-monitor` (read-only).
- `apps/web-platform/infra/workspaces-cutover.sh` — `${BASH_SOURCE[0]:-…}` hardening; persist `DOPPLER_TOKEN` to `/etc/default/luks-monitor` (real arm); optional `systemctl is-enabled luks-monitor.timer` fail-loud assert after the `install … || true` unit installs (real arm) so a silently-missing unit fails the freeze loud.
- `apps/web-platform/infra/luks-monitor.service` — add `Environment=HOME=/root`.
- `apps/web-platform/infra/workspaces-luks.tf` — add `github_actions_secret.workspaces_luks_boot_token`; reconcile the env-gate comment (`:190-210`) for the conditional/split gate.
- `.github/workflows/apply-web-platform-infra.yml` — add TWO `-target` lines to the DEFAULT allow-list: `doppler_service_token.workspaces_luks` + `github_actions_secret.workspaces_luks_boot_token` (NOT the scoped `:2660-2664` set).
- `plugins/soleur/test/terraform-target-parity.test.ts` — **REMOVE** `doppler_service_token.workspaces_luks` from `OPERATOR_APPLIED_TOKEN_EXCLUSIONS` (it is now CI-published; #5566 rule at `:686-688`).
- `apps/web-platform/infra/workspaces-luks-header.test.sh` — new mutation-tested assertions (Phase 5).
- `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md` — authorization-model addendum.

## Files to Create
- (none — all changes extend existing files.)

## Acceptance Criteria

### Pre-merge (PR)
- `${BASH_SOURCE[0]}` no longer appears un-guarded in `workspaces-cutover.sh`/`luks-monitor.sh` (`grep -n 'BASH_SOURCE\[0\]}' ` shows only `:-`-guarded forms).
- cutover.yml runs the script as a FILE from a tar-shipped temp dir; no `bash -s <` pipe remains; `install -m600 /dev/stdin` is the token-delivery mechanism; no `sudo DOPPLER_TOKEN=`/`sudo WORKSPACES_LUKS_BOOT_TOKEN=` argv form exists; the `.env` EXIT-trap shred is present.
- `workspaces-luks.tf` declares `github_actions_secret.workspaces_luks_boot_token` referencing `doppler_service_token.workspaces_luks.key` with no `ignore_changes`; `apply-web-platform-infra.yml` DEFAULT allow-list carries the matching `-target`; the scoped cutover `-target` set is unchanged (still exactly five).
- `workspaces-luks-cutover.yml` environment expression is `${{ !inputs.dry_run && 'workspaces-luks-cutover' || '' }}` (or the split-job fallback with a static `environment:` on the freeze job); `reviewers.users` stays `[54279]`.
- `luks-monitor.service` carries `Environment=HOME=/root`; the real arm persists `DOPPLER_TOKEN` to `/etc/default/luks-monitor` 0600 root.
- New `workspaces-luks-header.test.sh` assertions are mutation-tested (each predicate goes RED on the drift it names); all existing suites green (`workspaces-luks.test.sh`, `web-1-swap-concurrency-parity.test.sh`, `terraform-target-parity.test.ts` via vitest, `test-workspaces-luks-cutover-gate.sh`).
- ADR-119 addendum recorded; security-sentinel + architecture-strategist confirm C19/AC20b is preserved (freeze remains gated; only the reversible dry-run is ungated).
- PR body uses `Ref #6649` (NOT `Closes` — closure is post-merge after the probe goes green, per the ops-remediation Sharp Edge).

### Post-merge (autonomous — zero operator steps)
- (i) Trigger the DEFAULT apply (`gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun -f reason='publish WORKSPACES_LUKS_BOOT_TOKEN (#6649)'`, or the merge push) → `WORKSPACES_LUKS_BOOT_TOKEN` GH secret published; `hcloud_volume_attachment.workspaces_luks` live (by-id device exists on web-1). Verify via the apply run log + `gh secret list`. Automatable via `gh` CLI.
- (ii) Confirm `config prd_workspaces_luks` contains `WORKSPACES_HEADER_BUCKET`, `WORKSPACES_HEADER_R2_ENDPOINT`, `WORKSPACES_HEADER_R2_ACCESS_KEY_ID`, `WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY` (all four; `load_escrow_creds` is fail-loud) via `doppler secrets --config prd_workspaces_luks` read.
- (iii) `gh workflow run workspaces-luks-cutover.yml --ref main -f dry_run=true -f confirm=CUTOVER-WORKSPACES-LUKS` — MUST run with NO human approval wait (autonomy) and reach `escrow_probe`.
- (iv) On the escrow probe-PUT + negative over-scope probe GREEN (read the verdict from Better Stack / Sentry `feature=workspaces-luks op=workspaces-luks-drift` and the run log — NEVER SSH-eyeball), close #6649: `gh issue close 6649 --comment "<run URL> — escrow probe green"`.

## Infrastructure (IaC)
### Terraform changes
- `apps/web-platform/infra/workspaces-luks.tf`: +1 resource `github_actions_secret.workspaces_luks_boot_token` (provider `integrations/github`, already pinned). Sensitive value = `doppler_service_token.workspaces_luks.key` (lands in `terraform.tfstate` on the R2 encrypted backend — same as every other token). No new `TF_VAR_*`.
### Apply path
- (a) cloud-init-only for FUTURE hosts (out of scope — web-1 is `ignore_changes=[user_data]`, unrebuildable); (b) the running host is provisioned by `workspaces-cutover.sh` writing `/etc/default/luks-monitor` (real arm) — this is the "idempotent bootstrap on already-running host" path. The `github_actions_secret` lands via the DEFAULT `apply-web-platform-infra.yml` apply (existing IaC boundary). Blast radius: publishes one GH Actions secret; zero host downtime.
### Distinctness / drift safeguards
- The scoped cutover apply gate (`workspaces-luks-cutover-gate.sh`) is unchanged (terraform-side; unrelated to the GH environment). `-target` is transitive: the DEFAULT apply's `-target=github_actions_secret.workspaces_luks_boot_token` pulls `doppler_service_token.workspaces_luks` transitively — a benign create (or no-op if already in state); the scoped gate does not require the token create, so no conflict.
### Vendor-tier reality check
- github/doppler/hcloud providers already in use; no free-tier limit affects a `github_actions_secret` or a read-scoped service token.

## Observability
```yaml
liveness_signal:
  what: dry-run cutover run reaching escrow_probe GREEN (probe-PUT + negative over-scope) + the daily luks-monitor.timer heartbeat post-cutover
  cadence: on-dispatch (rehearsal) / daily (steady-state probe)
  alert_target: Better Stack heartbeat (WORKSPACES_LUKS_HEARTBEAT_URL) + Sentry issue alert (feature=workspaces-luks ∧ op IS_IN workspaces-luks-drift)
  configured_in: workspaces-cutover.sh escrow_probe + luks-monitor.sh + workspaces-luks-emit.sh
error_reporting:
  destination: Sentry direct-curl envelope (workspaces-luks-emit.sh), feature=workspaces-luks op=workspaces-luks-drift
  fail_loud: yes — this PR RESTORES the Sentry channel that BLOCKER 3 darkened (emit sibling now sourced because the script runs as a file with its siblings co-located)
failure_modes:
  - {mode: escrow probe-PUT fails, detection: emit_drift escrow_probe_put_failed → Sentry, alert_route: sentry_issue_alert}
  - {mode: over-scoped token reaches tfstate bucket, detection: emit_drift escrow_creds_overscoped, alert_route: sentry_issue_alert}
  - {mode: boot token missing/unreadable, detection: workflow fail-loud presence check + emit_drift doppler_unreachable/header_*_unreadable, alert_route: workflow ::error:: + Sentry}
  - {mode: WORKSPACES_LUKS_DEV unresolved, detection: workflow volume-id regex guard (fail before SSH), alert_route: workflow ::error::}
  - {mode: daily probe dark (post-cutover), detection: Better Stack heartbeat miss (Persistent=true), alert_route: Better Stack policy}
logs:
  where: GitHub Actions run log (probe verdict) + journald SyslogIdentifier=luks-monitor → Vector → Better Stack
  retention: GH Actions default / Better Stack retention
discoverability_test:
  command: gh workflow view workspaces-luks-verify.yml
  expected_output: "workspaces-luks verify"
  # The above is the SSH-free, pre-merge-runnable probe that the read-only verify surface (this
  # feature's no-SSH discoverability artifact) is registered + queryable. The escrow-specific GREEN
  # verdict is inherently POST-MERGE (needs the merged workflow + published boot-token secret + the
  # dry-run rehearsal): read it from the cutover run log (`escrow probe OK — PUT/read-back/delete`)
  # AND Sentry (feature=workspaces-luks op=workspaces-luks-drift) — NEVER by SSH-eyeballing the host.
```
Affected-surface note (§2.9.2): the host script runs on web-1 (an operator-blind surface). Its `emit_drift` events carry the nine discriminating `WL_*` fields in ONE envelope — this PR is what makes that channel actually fire (BLOCKER 3 fix), so the blind surface becomes observable.

## Architecture Decision (ADR/C4)
### ADR
Amend `ADR-119-luks-at-rest-for-the-live-workspaces-volume.md` with an **Authorization-Model addendum**: the `workspaces-luks-cutover` GitHub Environment gate (the sole human authorization on the irreversible freeze — C19/AC20b, DP-11 F8) is applied by the workflow **conditionally**, ONLY on the real freeze arm (`dry_run=false`). The dry-run rehearsal runs ungated because it performs NO irreversible operation — verified against `workspaces-cutover.sh`: `luksFormat`/`luksOpen` (`:257/:263-264`), FREEZE (`:376`), repoint (`:439`), and the `CONFIRM_WIPE` wipe (separate dispatch) are ALL behind `DRY_RUN != 1`; the dry-run reaches only `ensure_aws` (additive), `escrow_probe` (a namespaced `.probe/<run-id>` PUT/head/rm), device `blkid` reads, and manifest enumeration — all reversible. **Explicit acknowledgment (architecture P2):** the removed gate also covered `ensure_aws` (`:86-101`), which runs `apt-get install unzip` + a SHA256-pinned aws-cli installer AS ROOT on the sole prod host — so the autonomy change moves a root host-package mutation from gated to ungated. It is additive, SHA256-pinned (`:95`), and idempotent (a present `aws` short-circuits), so it is accepted; but the ADR addendum states this explicitly rather than framing the dry-run as side-effect-free. The AWSCLI_SHA256/AWSCLI_VERSION pin (`:55-56`) must be current for the autonomous dry-run to succeed (reachability GAP B). The fail-closed expression `${{ !inputs.dry_run && 'workspaces-luks-cutover' || '' }}` guarantees the gate is present whenever `DRY_RUN='0'`:

| `inputs.dry_run` | `!inputs.dry_run` | environment | freeze reachable? | gated? |
|---|---|---|---|---|
| true | false | `''` (none) | no (`DRY_RUN='1'`) | n/a — nothing irreversible |
| false | true | `workspaces-luks-cutover` | yes (`DRY_RUN='0'`) | **YES** |
| null/unset | true | `workspaces-luks-cutover` | yes (`DRY_RUN='0'`) | **YES** (fail-closed) |

This is a divergence from the ADR's current "the environment gate covers every dispatch"; the addendum records the decision + the reversibility proof. **security-sentinel + architecture-strategist MUST confirm** the irreversible path stays gated and the empty-string-environment behavior is verified (else split-job fallback with a static `environment:`).
### C4 views
No C4 impact. Enumeration (all three `.c4` files to be read at /work per the completeness mandate, and confirmed already-modeled or out-of-boundary): external human actor = the operator/founder reviewer (@deruelle, id 54279 — the existing solo-founder actor); external systems = GitHub Actions environment gate, web-1 host, Cloudflare R2 escrow bucket, Doppler `prd_workspaces_luks`, Hetzner volume API — all infra-CI vendors outside the app C4 container view; no new data store; no app-level access-relationship change. The change is a CI authorization-timing refinement, not an app-architecture change.
### Sequencing
The ADR addendum ships in THIS PR (describes the now-true state); it is not deferred.

## Domain Review
**Domains relevant:** Engineering (infra + security). Product: NONE (no UI-surface file — nothing under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`).

### Engineering / Security
**Status:** reviewed (framing). **Assessment:** This is an infra/CI/security change on the LUKS-at-rest authorization + escrow path. The mandated review is at plan-review (escalated to +architecture-strategist +spec-flow-analyzer at single-user-incident threshold) and deepen-plan (security-sentinel via the domain triad). The load-bearing security questions: (1) the boot token never reaches a host process list or workflow argv (0600 stdin env file, shred-on-EXIT, no `sudo VAR=val`); (2) the autonomy change keeps the irreversible freeze gated (truth table above); (3) verify.yml stays read-only. GDPR gate (2.7): the change alters no data processing — it makes an existing at-rest-encryption rehearsal autonomous; advisory-only, no regulated-data surface added.

### Product/UX Gate
Skipped — no UI surface (mechanical UI-surface override did not fire).

## Open Code-Review Overlap
None — no open `code-review` issue body references any of the nine files in scope (checked 2026-07-18 via `gh issue list --label code-review`).

## Test Scenarios
1. **File-execution restores the emit channel:** run the bundle as a file with `/usr/local/bin/workspaces-luks-emit.sh` absent → `emit_drift` still reaches Sentry (sibling sourced from the temp dir); a re-introduced `bash -s <` form → RED assertion.
2. **Token never in argv:** mutation appending `sudo DOPPLER_TOKEN=${{ secrets.WORKSPACES_LUKS_BOOT_TOKEN }} bash …` → the extended H7 predicate goes RED.
3. **Fail-closed gate:** the environment expression with `dry_run` null/false → gated; only `dry_run=true` → ungated (assert the literal expression; a `dry_run && '' || 'X'` inversion → RED).
4. **Device regex guard:** a non-numeric volume-id API response → workflow fails before SSH (no partial run).
5. **Daily probe env:** `luks-monitor.service` without `Environment=HOME=/root` → RED (the doppler-`$HOME` failure mode).
6. **Read-only verify:** verify.yml runs `luks-monitor` (not `workspaces-cutover.sh`) — assert no device-opening call reachable from verify's entrypoint.

## Reachability Preconditions (dry-run → escrow_probe)

Spec-flow confirmed the ordered death chain the four fixes remove: `:63` (BLOCKER 3) → `:248` KEY (BLOCKER 4 token) → `:253` `WORKSPACES_LUKS_DEV` (BLOCKER 5, checked BEFORE the escrow reads) → `:279` escrow creds (BLOCKER 4 token) → `:280` probe. After the fixes the code deaths are gone, but the probe is reached only if these INFRA/HOST preconditions also hold (each maps to a post-merge verification step — they are acknowledged sequencing dependencies, not unhandled logic):

| Gap | Precondition | Severity | Covered by |
|---|---|---|---|
| A | `hcloud_volume_attachment.workspaces_luks` LIVE on web-1 so the by-id device node physically exists (`:253` `[ -e "$FRESH_DEV" ]`) | HIGH | Post-merge step (i) — the DEFAULT apply attaches it |
| B | web-1 outbound HTTPS to `awscli.amazonaws.com` + apt for `unzip`, AND a current `AWSCLI_SHA256` pin — `ensure_aws` (`:86-101`) dies otherwise, BEFORE the probe | HIGH | New verification note (below); pin currency checked at /work Phase 0 |
| C | all four `WORKSPACES_HEADER_*` secrets present in `prd_workspaces_luks` (`load_escrow_creds` fail-loud `:110-113`) | MEDIUM | Post-merge step (ii) |
| D | the fresh volume carries raw or `crypto_LUKS` (not a stray fs signature) — `:261` dies even in dry-run | MEDIUM | Fresh volume born raw (no `format` attr, workspaces-luks.tf A4) |
| E | `HOME=/root` for the host `doppler` read — handled by DROPPING `sudo` (bridge lands `-l root`); a regression to `sudo` without `-H` reintroduces a misleading "empty WORKSPACES_LUKS_KEY" death | LOW (load-bearing) | Phase 1.2 drops sudo; Phase 5 asserts no `sudo` in the run step |
| F | `/mnt/data` mounted at run time (`:240` L3 gate) | LOW | Steady state |

GAP A and GAP B are the two most likely to leave a "blockers-fixed" dry-run still dying short of the probe; both are verified by the post-merge autonomous sequence before #6649 is closed.

## Deepen-Plan Review Synthesis

Deepened 2026-07-18 with 5 parallel agents (security-sentinel, architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer, observability/verify-negative Explore) + the 4.6/4.7/4.8/4.9 hard gates. Verdicts + corrections folded in above:

- **Autonomy gate — CONFIRMED SOUND (security-sentinel).** Decisive property: the env gate and `DRY_RUN` derive from the SAME `inputs.dry_run` operand, so **freeze-reachable ⟺ gated** in every input case (including `dry_run` null/string). The empty-string-environment vendor behavior affects ONLY whether the DRY-RUN is ungated (the autonomy goal) — NOT whether the freeze is gated (the freeze arm always evaluates to the literal `'workspaces-luks-cutover'`, never empty). So C19/AC20b is preserved regardless of empty-string handling; Phase 0's WebFetch check confirms autonomy is *achieved*, not safety.
- **Mechanism (architecture-strategist P2):** prefers SPLIT-JOB (static literal `environment:` on the freeze job) for static auditability at single-user-incident threshold. Kept conditional-environment as primary (task's first-listed option + minimal diff + the freeze arm is always a literal string) with split-job as the documented fallback if Phase 0 empty-string verification fails or the PR-time security reviewer prefers it. Dissent logged in `decision-challenges.md`.
- **Token classification (architecture-strategist P1) — CORRECTED.** Explicit `-target` for `doppler_service_token.workspaces_luks` + de-exclude from `OPERATOR_APPLIED_TOKEN_EXCLUSIONS` (mirror inngest; #5566 rule). See Phase 2.1 + Research Reconciliation.
- **`.env` on tmpfs (security-sentinel P1) — CORRECTED.** `.env`+bundle on `STATE_DIR` (F7), write+trap+run consolidated into one `bash -c`. See Phase 1.2.
- **HOME=/root + token bake (verify-negative Explore, both P1-latent) — CONFIRMED needed.** Sibling root-doppler units (`web-git-data-probe.service:15` etc.) all set `Environment=HOME=/root` with dedicated tests (`web-git-data-probe.test.sh:120-121`); Phase 5 mirrors that assertion.
- **Reachability (spec-flow) — 6 preconditions** enumerated in the section above.
- **Scope (code-simplicity):** dropped `luks-monitor.sh` hardening (always a file); `.env`-on-STATE_DIR resolves the shred-vs-rm tension in favor of a meaningful shred; the tf-published-volume-id alternative (`github_actions_variable`) is recorded as a considered option but hcloud-API-runtime kept per the task direction (logged in `decision-challenges.md`); verify.yml kept per the task's explicit "both workflows" direction (dissent logged).
- **Root package install ungated (architecture P2)** — `ensure_aws` acknowledged in the ADR addendum + GAP B.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6. It is filled above.
- The env-file fields (`DOPPLER_TOKEN`, `WORKSPACES_LUKS_DEV`, `DRY_RUN`, `ROLLBACK`) MUST stay metacharacter-free — `set -a; . .env; set +a` parses the file as shell, so a value containing whitespace/`;`/`$` would break parsing or inject. Current values are safe; preserve this as a constraint if fields are added.
- The `.env` (full-prd token) MUST live on `STATE_DIR` (persistent fs), never `mktemp -d`'s tmpfs default, or the shred is a no-op against the raw device (F7, workspaces-cutover.sh:296-297). This is a P1 the deepen review caught.
- Empty-string GitHub Actions `environment:` = ungated is a third-party-behavior claim — verify against GH docs at /work (Phase 0); split-job fallback if unconfirmed. Do NOT ship the conditional environment unverified.
- The naive `${{ inputs.dry_run && '' || 'X' }}` is INVERTED (`''` is falsy). Use `!inputs.dry_run && 'X' || ''`. Grep the final workflow to confirm the correct form landed.
- Doppler SERVICE token ignores `--config` (learning `2026-03-29-doppler-service-token-config-scope-mismatch`) — the boot token's built-in scope IS `prd_workspaces_luks`, so the script's `--config prd_workspaces_luks` reads resolve correctly; do not "fix" the flag away.
- `-target` is transitive (learnings `2026-07-03`/`2026-07-17`): the DEFAULT apply's `-target=github_actions_secret.workspaces_luks_boot_token` pulls the token; benign (create allowed on the default path). Do NOT add the secret to the scoped cutover `-target` set — the gate would abort it `out_of_scope`.
- `WEB_HOST_SSH` lands as root; keeping `sudo` re-scrubs `HOME`/the sourced env → the host `doppler` read dies `$HOME is not defined`. Drop `sudo` (or use `sudo -H` and source inside).
- The `.env` shred trap must be HOST-LOCAL (in the outer remote `bash -c`), so a dropped SSH session still shreds the token — mirrors the DP-6 host-side EXIT trap.
