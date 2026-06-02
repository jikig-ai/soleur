---
feature: ci-tunnel-apply-generalize
issue: 4844
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-06-02
type: feat
brainstorm: knowledge-base/project/brainstorms/2026-06-02-ci-tunnel-apply-generalize-brainstorm.md
spec: knowledge-base/project/specs/feat-ci-tunnel-apply-generalize/spec.md
deferred: 4847
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# Plan — Generalize the CF Tunnel CI-apply pattern to the 7 on-host hardening resources (#4844)

## Overview

PR #4830 (merged) proved a CF Tunnel SSH bridge that lets a GitHub runner SSH to the prod
Hetzner host (egress IP NOT in `var.admin_ips`) and auto-apply on-host Terraform provisioners.
That bridge lives **inline** in `apply-deploy-pipeline-fix.yml` and `-target`s only 2 resources.
This plan generalizes it (parts 1+2 of #4844; part 3 deferred to #4847):

1. **Extract** the inline bridge into a reusable composite action `.github/actions/cf-tunnel-ssh-bridge/` (setup steps only; teardown stays caller-side `if: always()`).
2. **Retrofit** the 7 sibling `terraform_data.*` resources in `server.tf` with the dual-context connection block, append them to `apply-web-platform-infra.yml`'s `-target=` set behind the bridge so they auto-apply on merge instead of drifting.
3. **Guard** the `-target` allowlist with a self-healing `bun:test` parity test.
4. **Fix** the stale header comment in `apply-web-platform-infra.yml`.
5. **Verify** CODEOWNERS coverage (already present — see Reconciliation).

Authorization model: the **reviewed, CODEOWNERS-gated merge IS the human prod-write
authorization** (consistent with #4830 and `hr-menu-option-ack-not-prod-write-auth`). Unattended
drift auto-apply (no merge gate) is explicitly out of scope → #4847.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue/spec) | Codebase reality | Plan response |
|---|---|---|
| 7 siblings "land via `apply-deploy-pipeline-fix.yml`" (its header) | That workflow `-target`s only `deploy_pipeline_fix` + `infra_config_handler_bootstrap`; the 7 drift | Fix the stale header comment (Phase 4); premise of #4844 confirmed |
| `apparmor_bwrap_profile` AND `docker_seccomp_config` coupled via `deploy_pipeline_fix` `depends_on` | Only `apparmor_bwrap_profile` has the edge (`server.tf:502`); `docker_seccomp_config` is comment-only | Coupling resolved incidentally by Phase 3 (dual-context retrofit gives apparmor the explicit key it needs) |
| TR4: "verify CODEOWNERS covers infra `.tf` + profile files" | Already covered: `.github/CODEOWNERS` pins `/apps/web-platform/infra/`, `/.github/workflows/`, `/.github/workflows/apply-web-platform-infra.yml` (all profile files live under the infra dir) | Phase 6 = verify-only; optional new row for `.github/actions/cf-tunnel-ssh-bridge/` (default `* @deruelle` already covers it) |
| All 7 siblings already have the #4829 dual-context connection block | FALSE — all 7 still use `agent = true` only; only `infra_config_handler_bootstrap` (server.tf:390-396) has dual-context | Phase 3 retrofits all 7 |
| `apply-web-platform-infra.yml` applies inline (no saved plan) | Saves `-out=tfplan` (L237), applies `tfplan` (L370); destroy-guard between (L336-359) | Bridge must be LIVE across plan AND apply; teardown after L370 |

## Hypotheses (L3→L7 — `hr-ssh-diagnosis-verify-firewall`)

This is a feature plan, but the apply path's correctness turns on the same L3-first ordering as an
SSH outage: the 7 resources are excluded *today* precisely because the runner egress IP is not in
`var.admin_ips`. The bridge is the L3 workaround; verify it before assuming any service-layer issue.

1. **L3 — firewall/egress (the load-bearing layer).** The GitHub runner egress IP is NOT in `var.admin_ips` and cannot be (5000+ rotating IPs). The bridge bypasses this by routing SSH through the CF Tunnel + CF Access `ci_ssh` token to `127.0.0.1:2222`, transparent to Terraform's Go SSH client only via `iptables -t nat OUTPUT REDIRECT` (NOT `~/.ssh/config` — Go client ignores it; see `2026-05-20-terraform-go-ssh-client-ignores-ssh-config-multi-agent-catch.md`). Verification: the bridge is already proven for `infra_config_handler_bootstrap` in #4830; Phase 2 re-uses the identical mechanism. [verified: #4830 merged, mechanism unchanged]
2. **L3 — DNS/routing.** `cloudflared access tcp --hostname ssh.${APP_DOMAIN_BASE}` resolves via CF edge; `APP_DOMAIN_BASE` has a `soleur.ai` fallback (the #4840 hotfix). [verified: #4840 merged]
3. **L7 — CF Access service-token expiry.** The `ci_ssh` token expires after 8760h with an opaque 403. Existing expiry monitoring applies (`2026-03-21-cloudflare-service-token-expiry-monitoring.md`); a failed readiness loop fails the job loudly. [carry-forward; reuse existing monitor]
4. **L7 — sshd/host.** Only reached if L3 holds. The 7 provisioners are short (`file` + `remote-exec` `systemctl`). Opt-out of deeper sshd hypotheses: the bridge already lands `infra_config_handler_bootstrap` over the same sshd daily; no sshd drift hypothesis is warranted. [opt-out artifact: #4830 production history]

## Implementation Phases

### Phase 0 — Preconditions (no edits)
- Confirm `var.ci_ssh_private_key` is declared and unencrypted (used by `infra_config_handler_bootstrap`). [verified this session]
- Confirm test runner: `bun:test` via `bash scripts/test-all.sh` (sibling: `ship-deploy-pipeline-fix-gate.test.ts`).
- Confirm the 7 sibling connection-block line numbers: 76-81 (`disk_monitor_install`), 114-119 (`resource_monitor_install`), 151-156 (`fail2ban_tuning`), 226-231 (`journald_persistent`), 572-577 (`docker_seccomp_config`), 608-613 (`apparmor_bwrap_profile`), 635-640 (`orphan_reaper_install`).

### Phase 1 — Create composite action (contract; no consumer yet)
- Create `.github/actions/cf-tunnel-ssh-bridge/action.yml` (`using: composite`). **Setup steps only**, extracted verbatim from `apply-deploy-pipeline-fix.yml` lines 182-309: install cloudflared (SHA-pinned via `CLOUDFLARED_VERSION`/`CLOUDFLARED_SHA256` inputs), pull `CI_SSH_ACCESS_TOKEN_ID/SECRET` from Doppler (read-only `doppler secrets get`), decode key → `TF_VAR_ci_ssh_private_key` (heredoc + per-line `::add-mask::`), `SERVER_IP=$(terraform output -raw server_ip)` (reads R2 state post-init; guard empty → fail), start `cloudflared access tcp` 127.0.0.1:2222 + 15s readiness loop, `iptables -t nat OUTPUT REDIRECT -d $SERVER_IP`.
- **Secrets as explicit `inputs:`** (composite actions cannot read `secrets.*`): `doppler-token`, `infra-dir`, `cloudflared-version`, `cloudflared-sha256`. Re-export to `env:` inside each step (`sentry-heartbeat`/`notify-ops-email` convention). Outputs exported to `$GITHUB_ENV` (job-scoped, visible to the caller's later steps — proven by the inline version: `apply-deploy-pipeline-fix.yml:267` writes `SERVER_IP`, read by teardown at L348): `SERVER_IP`, `CLOUDFLARED_PID`, `TF_VAR_ci_ssh_private_key`, `TUNNEL_SERVICE_TOKEN_ID/_SECRET`.
- **No standalone README** (no peer action carries one — `sentry-heartbeat`/`notify-ops-email` etc. have zero). Document the SHA-recompute-against-real-binary discipline AND the caller-side-teardown contract (callers MUST add an `if: always()` teardown with `[[ -n "${SERVER_IP:-}" ]]` / `[[ -n "${CLOUDFLARED_PID:-}" ]]` guards) as header comments inside `action.yml`, next to the code they constrain.
- **Do NOT teardown inside the action** (composite actions can't register a post-job hook without a JS `post:`); teardown is caller-side.

### Phase 2 — Rewire `apply-deploy-pipeline-fix.yml` (consumer; no behavior change)
- Replace inline bridge setup steps (182-309) with `- uses: ./.github/actions/cf-tunnel-ssh-bridge` + the input forwards (`doppler-token: ${{ secrets.DOPPLER_TOKEN }}`, etc.).
- Keep the existing `if: always()` teardown step (339-363) caller-side (deletes NAT rule, kills cloudflared, dumps log). Regression-free: same 2 `-target`s.
- **Fix the now-stale CAVEAT comment (lines 46-54)** (Kieran P2): after Phase 3 gives `apparmor_bwrap_profile` the explicit dual-context key, the documented "profile co-change → `publickey` failure on the agent-less runner" failure mode no longer applies. Update/remove the CAVEAT so a future reader doesn't trust a coupling warning that Phase 3 resolved.

### Phase 3 — `server.tf`: dual-context retrofit (contract: resources become CI-applyable)
- For each of the 7 sibling connection blocks, add `private_key = var.ci_ssh_private_key` and change `agent = true` → `agent = var.ci_ssh_private_key == null`. Operator-local apply (var unset → `agent = true`) stays byte-equivalent. This also gives `apparmor_bwrap_profile` the explicit key it needs when pulled in via `deploy_pipeline_fix`'s `depends_on` (resolves the latent coupling).

### Phase 4 — `apply-web-platform-infra.yml`: two-apply, token-gated (consumer) [shape B]
The 80 non-SSH resources stay in the existing saved-`tfplan` apply (unchanged); the 7 SSH
resources get a SEPARATE token-gated `-target` apply behind the bridge, AFTER the post-apply token
sync. This resolves SpecFlow 5b (fresh-rebuild bootstrap inversion), 4a (decoupled blast radius),
and 1c (bridge idle window). `terraform plan` does NOT open SSH (provisioners are apply-time), so
the bridge is NOT needed during plan — only the second apply.

- **Step order in the `apply` job:** `terraform init` (L209) → plan (L218, **80 non-SSH targets only — do NOT add the 7 here**) → destroy-guard (L336-359) → apply saved `tfplan` (L370) → existing post-apply token sync (L397-432, produces `CI_SSH_ACCESS_TOKEN_ID/_SECRET` in Doppler) → **NEW token-presence gate** → **NEW SSH apply (gated)**.
- **NEW token-presence gate step:** `doppler secrets get CI_SSH_ACCESS_TOKEN_ID --plain 2>/dev/null || true`; if empty/absent, set `ssh_apply_skip=true` and `::warning::` "first-bootstrap: SSH resources deferred to next run after token sync" (mirrors the existing `skip_sync` bootstrap-cycle guard at L384-395). If present, `ssh_apply_skip=false`.
- **NEW SSH apply (only if `ssh_apply_skip != 'true'`):** `- uses: ./.github/actions/cf-tunnel-ssh-bridge` (brings up tunnel + NAT + key) → `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply -auto-approve -input=false -target=terraform_data.disk_monitor_install -target=… (all 7)` → caller-side `if: always()` teardown with `[[ -n "${SERVER_IP:-}" ]]` / `[[ -n "${CLOUDFLARED_PID:-}" ]]` guards (SpecFlow 1a). AWS R2 creds exported via `doppler secrets get --plain` BEFORE the tf-var run (TR2).
- **Cross-workflow concurrency (SpecFlow 5a):** a `server.tf` change already fires BOTH workflows (apply-web-platform-infra paths `apps/web-platform/infra/**` ∩ apply-deploy-pipeline-fix paths `…/server.tf`). The R2 state lock serializes terraform ops and both SSH applies are hash-gated idempotent (overlap on `apparmor_bwrap_profile` via `deploy_pipeline_fix`'s `depends_on` is a redundant no-op, not corruption). Mitigation evaluated at deepen-plan: either give both workflows a SHARED concurrency group (serializes at GHA level, prevents two concurrent tunnels to the same host root) OR document the ownership boundary. Default: shared concurrency group `terraform-apply-web-platform-host` on both SSH-applying workflows.
- Fix the stale header comment (lines 16-27): the 7 resources now apply HERE (the token-gated SSH step) over the bridge, not "via apply-deploy-pipeline-fix.yml".

### Phase 5 — Parity-guard test (self-healing)
- Create `plugins/soleur/test/terraform-target-parity.test.ts` (`bun:test`; auto-discovered by `scripts/test-all.sh:168` → `bun test plugins/soleur/`). Glob **ALL** `apps/web-platform/infra/*.tf` (NOT server.tf only — `root_authorized_keys` lives in `ci-ssh-key.tf`; Kieran P1 / SpecFlow 2a). For every `terraform_data` resource with BOTH a `connection { type = "ssh" }` and a `provisioner` block, assert it appears in the UNION of: `apply-web-platform-infra.yml` `-target=` set ∪ `apply-deploy-pipeline-fix.yml` `-target=` set ∪ exclusion allowlist (`root_authorized_keys`, operator-local). FAIL if any SSH-provisioned resource is in none.
- **Parser robustness (SpecFlow 2c — P0):** strip `#` comments line-wise BEFORE matching. `server.tf:305` is a *comment* containing the literal `connection{type="ssh"}`; a naive matcher would false-count it (and mask the count bug). Prefer `terraform show -json`/`hcl2json` if available; else regex on comment-stripped text.
- **Count:** 9 SSH-provisioned resources = 8 in `server.tf` (7 siblings + `infra_config_handler_bootstrap`) + `root_authorized_keys` in `ci-ssh-key.tf`. `deploy_pipeline_fix` is `local-exec` (no `connection` block — confirmed) → correctly excluded by the SSH predicate; do NOT count it. Sentinel: `expect(sshProvisionedResources.length).toBeGreaterThanOrEqual(9)`.
- **Documented limitation (SpecFlow 2b):** the test is one-directional (every SSH resource ∈ union). It does NOT catch a stale/typo'd `-target=` (terraform exits 0 on "no resources matched"). Note this in the test header; reverse-direction guard is out of scope.

### Phase 6 — CODEOWNERS
- Already covered (verify only): `/apps/web-platform/infra/`, `/.github/workflows/`, `/.github/workflows/apply-web-platform-infra.yml` all pin `@deruelle`.
- **Add** the explicit row `/.github/actions/cf-tunnel-ssh-bridge/ @deruelle` — matches the file's documented load-bearing-files-get-explicit-rows convention (the bridge is the security-critical root-SSH mechanism). One decisive line, not a hedged discussion.

### Phase 7 — Verify
- Run `bash scripts/test-all.sh` (includes the new parity test + destroy-guard suite).
- `actionlint` the two workflows (NOT the composite `action.yml` — wrong schema, emits spurious errors per `2026-05-18-composite-action-extraction-inline-on-multi-file-rollout.md`); `bash -c` the extracted `run:` snippets.

## Files to Create
- `.github/actions/cf-tunnel-ssh-bridge/action.yml` — composite action (setup only; SHA-recompute + caller-teardown contract in header comments — no README)
- `plugins/soleur/test/terraform-target-parity.test.ts` — `bun:test` `-target` parity guard (globs all infra `*.tf`, comment-stripped parse)

## Files to Edit
- `apps/web-platform/infra/server.tf` — 7 connection blocks → dual-context (L76-81, 114-119, 151-156, 226-231, 572-577, 608-613, 635-640)
- `.github/workflows/apply-deploy-pipeline-fix.yml` — replace inline bridge with `uses:`; keep caller teardown; **fix now-stale CAVEAT comment L46-54** (Kieran P2); add shared concurrency group (5a)
- `.github/workflows/apply-web-platform-infra.yml` — token-gated SSH apply behind the bridge AFTER the post-apply token sync (shape B); caller teardown with `-n` guards; 7 `-target=` lines on the NEW SSH apply (NOT the main plan); fix stale header comment; add shared concurrency group (5a)
- `.github/CODEOWNERS` — add `/.github/actions/cf-tunnel-ssh-bridge/ @deruelle` row

## Acceptance Criteria

### Pre-merge (PR) — grep/run-checkable post-conditions
- AC1. `grep -c 'secrets\.' .github/actions/cf-tunnel-ssh-bridge/action.yml` == 0 (secrets are `inputs:`, never `secrets.*` inside a composite action); `using: composite` present.
- AC2. `apply-deploy-pipeline-fix.yml` references `uses: ./.github/actions/cf-tunnel-ssh-bridge`, retains its `if: always()` teardown, and the CAVEAT block (old L46-54) no longer warns about the apparmor publickey failure Phase 3 resolved.
- AC3. `grep -c 'agent = var.ci_ssh_private_key == null' apps/web-platform/infra/server.tf` == 8 (7 siblings + bootstrap; baseline is 1). (Do NOT grep bare `agent = true` — comment text at L377/382 matches.)
- AC4. In `apply-web-platform-infra.yml`: the main plan/apply does NOT contain the 7 new `-target=` lines; a SEPARATE token-gated SSH-apply step contains all 7, runs the bridge `uses:` step + an `if: always()` teardown with `-n` guards, and is positioned AFTER the post-apply token-sync step. Stale header comment fixed.
- AC5. Token-gate: the SSH-apply step is conditioned on `CI_SSH_ACCESS_TOKEN_ID` presence and emits `::warning::` + skips (does not fail the job) when absent (first-bootstrap path).
- AC6. `plugins/soleur/test/terraform-target-parity.test.ts` passes on current state (sentinel ≥9 met by globbing all infra `*.tf` with comment-stripped parse) AND fails on a synthetic in-test fixture string adding an un-targeted SSH resource (verify via fixture, not by editing real `.tf`).
- AC7. Both SSH-applying workflows share one concurrency group (5a). `bash scripts/test-all.sh` passes (parity + destroy-guard + ship-gate suites green).

### Post-merge (CI — automated)
- AC8. On the merge commit, `apply-web-platform-infra.yml` runs to conclusion=success and the token-gated SSH step applies the 7 siblings (or `::warning::`-skips on first bootstrap). Verify (NO ssh): `gh run list --workflow=apply-web-platform-infra.yml --limit 3 --json conclusion,headSha`.
- AC9. Editing one hardening file (e.g. `fail2ban-sshd.local`) in a follow-up PR auto-applies on merge with no operator-local `terraform apply`.
- AC10. PR body uses `Ref #4844` (NOT `Closes` — issue closes only after AC8 confirms the post-merge apply landed; ops-remediation class per `wg-use-closes-n-in-pr-body-not-title-to`). `gh issue close 4844` after AC8.

## Open Code-Review Overlap

2 open scope-outs incidentally name planned files; both **Acknowledged** (different concerns, no conflict):
- #2197 (billing SubscriptionStatus / Sentry breadcrumb) — incidental `server.tf` mention; unrelated to the connection-block edit. Remains open.
- #3321 (CODEOWNERS coverage for `knowledge-base/project/learnings/`) — a different CODEOWNERS region than the optional `.github/actions/` row; no conflict. Remains open.

## User-Brand Impact

- **If this lands broken, the user experiences:** host hardening (fail2ban/seccomp/apparmor) silently fails to apply or applies wrong on merge → the single prod host serving all user data is left under-hardened or, worst case, an apply error blocks the deploy pipeline.
- **If this leaks, the user's data is exposed via:** the CI SSH key or CF Access `ci_ssh` token leaking through workflow logs/PR artifacts → root on the prod host. Mitigated by per-line `::add-mask::` on the key, secrets-as-inputs (no `secrets.*` echo), and CODEOWNERS-gated merge as the sole human checkpoint.
- **Brand-survival threshold:** single-user incident.

`requires_cpo_signoff: true` — CPO reviewed the approach at brainstorm (carry-forward, Domain Review below). `user-impact-reviewer` runs at PR-review time (review skill conditional-agent block).

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm `## Domain Assessments`)

### Engineering (CTO)
**Status:** reviewed
**Assessment:** Composite action is correct (shared job network namespace for iptables + apply). Blast radius MEDIUM — credential radius unchanged (root already reachable via the live bridge); hardening files become CI-writable, so CODEOWNERS is the load-bearing replacement checkpoint (already satisfied). Only `apparmor_bwrap_profile` has the `depends_on` edge; dual-context retrofit resolves it incidentally. Parts 1+2 ship together; part 3 deferred (#4847) + ADR.

### Product (CPO)
**Status:** reviewed
**Assessment:** Low product relevance; operator-burden lens real (non-technical operator can't run terraform locally). Part 2 captures ~90% of value (resources change only via merged PRs). Slice approved; Post-MVP milestone correct.

### Legal (CLO)
**Status:** reviewed
**Assessment:** LOW relevance, no user-PII surface. PERMITTED-WITH-GUARDRAILS; no specialist, no legal-doc lockstep (GDPR-Policy lockstep explicitly N/A). Both guardrails (WORM audit trail, break-glass pause) apply only to deferred part 3 (#4847), not this PR.

### Product/UX Gate
**Tier:** none — no UI surface. No `## Files to Create`/`Edit` path matches the UI-surface term list. Mechanical override did not fire.
**Pencil available:** N/A (no UI surface).

**Brainstorm-recommended specialists:** ADR via `/soleur:architecture` — recommended by CTO for **part 3 only** (deferred to #4847); not invoked here.

## Infrastructure (IaC)

This plan is IaC-positive: it MOVES operator-local `terraform apply` INTO CI (the opposite of the `hr-all-infrastructure-provisioning-servers` anti-pattern). No operator-run SSH session, vendor-dashboard click, or Doppler write step is introduced — secret reads are read-only `doppler secrets get`. `terraform-architect` not spawned (the design already routes every change through Terraform + CI; reviewed per Phase 2.8, ack comment in frontmatter).

### Terraform changes
- `apps/web-platform/infra/server.tf` — 7 `terraform_data.*` connection blocks gain `private_key = var.ci_ssh_private_key` + `agent = var.ci_ssh_private_key == null`. No new resources, no new providers, no new variables (`var.ci_ssh_private_key` already declared). Sensitive var: `TF_VAR_ci_ssh_private_key` (set by the bridge action from Doppler `prd_terraform` `DEPLOY_SSH_PRIVATE_KEY`).

### Apply path
- (c-adjacent) CI auto-apply on merge over the CF Tunnel SSH bridge. The 7 `terraform_data` provisioners are idempotent (`file` push + `systemctl`); `triggers_replace` hashes gate re-runs. Expected downtime: none (config push, no host restart). Blast radius: MEDIUM (see User-Brand Impact).

### Distinctness / drift safeguards
- `dev != prd`: the bridge targets `hcloud_server.web` (prd host) only; no dev equivalent. Operator-local apply stays byte-equivalent (dual-context `agent = true` when key var unset). Secrets land in `terraform.tfstate` (encrypted R2 backend — unchanged).

### Vendor-tier reality check
- cloudflared + CF Access `ci_ssh` service token already provisioned (#4177/#4830). No free-tier limit affects resource creation. No new tier gate.

## Observability

```yaml
liveness_signal:
  what: apply-web-platform-infra.yml run conclusion on merges touching apps/web-platform/infra/**
  cadence: per-merge (path-filtered)
  alert_target: GitHub Actions failure notification + existing notify-ops-email/sentry-heartbeat steps
  configured_in: .github/workflows/apply-web-platform-infra.yml (existing failure handling)
error_reporting:
  destination: GitHub Actions job logs + the workflow's existing sentry-heartbeat step
  fail_loud: apply step exits non-zero (no continue-on-error); bridge readiness loop exits non-zero on token/tunnel failure
failure_modes:
  - mode: CF Access ci_ssh token expired/missing
    detection: cloudflared readiness loop fails within 15s then job fails loudly
    alert_route: GitHub Actions failure + existing CF service-token expiry monitor
  - mode: resource added to server.tf but not to -target set
    detection: terraform-target-parity.test.ts fails in CI pre-merge
    alert_route: PR check failure (blocks merge)
  - mode: teardown skipped then orphaned iptables NAT rule on runner
    detection: caller-side if:always() teardown; ephemeral runner discards state anyway
    alert_route: teardown step log (tail of cloudflared.log)
logs:
  where: GitHub Actions run logs (cloudflared.log tail dumped in teardown step)
  retention: GitHub default (90 days)
discoverability_test:
  command: gh run list --workflow=apply-web-platform-infra.yml --limit 5 --json conclusion,headSha,createdAt
  expected_output: most recent run on an infra-touching merge shows conclusion=success
```

## Risks & Mitigations
- **Tunnel idle window (SpecFlow 1c).** Resolved by shape B: the bridge is up ONLY for the short token-gated SSH `-target` apply (7 idempotent provisioners), NOT across the 80-target non-SSH plan/apply. Idle window is now comparable to the proven #4830 sibling.
- **Cross-workflow concurrency (SpecFlow 5a — P0).** A `server.tf` change fires both apply workflows (pre-existing dual trigger). The R2 state lock serializes terraform ops; both SSH applies are hash-gated idempotent (apparmor overlap is a redundant no-op). Mitigation: shared concurrency group on both SSH-applying workflows prevents two concurrent tunnels to the same host root. (deepen-plan architecture-strategist to confirm the group name / coupling trade-off.)
- **First-bootstrap inversion (SpecFlow 5b — P1).** Resolved by shape B: the token-gated SSH step runs AFTER the post-apply token sync and `::warning::`-skips when tokens are absent, so a from-scratch rebuild self-heals on the next run instead of dead-ending.
- **Partial apply / mid-inline-list failure (SpecFlow 4a/4b).** A failure in SSH resource #4 leaves #1-3 applied; `triggers_replace` hashes make re-runs idempotent and `terraform_data` taints a failed-provisioner resource for full re-run. Blast radius decoupled by shape B (a tunnel flake fails only the SSH apply, not the 80 DNS/secret resources). Recovery relies on the taint mechanism — note in /work.
- **Hardening files CI-writable.** A malicious/buggy PR editing a profile auto-applies on merge. Mitigation: CODEOWNERS-gated merge is the checkpoint (already pinned). Credential blast radius unchanged (root already reachable via the live bridge).
- **`-target` allowlist drift.** A future resource silently no-ops if not appended. Mitigation: the new parity test (Phase 5). Known limitation: one-directional (a stale/typo'd `-target` is not caught — terraform exits 0 on no-match).

## Non-Goals
- Part 3 (unattended drift auto-apply) — deferred to #4847 (no merge gate; x==x tautology; needs WORM audit + break-glass + ADR).
- `terraform_data.root_authorized_keys` — stays operator-local (firewall chicken-and-egg).
- No change to `var.admin_ips` (the firewall); the tunnel is the access path.

## Test Scenarios
- Parity test rejects an un-targeted SSH-provisioned resource (synthetic in-test fixture).
- Parity test passes on current state — 9 SSH-provisioned resources all covered: 7 siblings + `infra_config_handler_bootstrap` in `server.tf` (the 7 in apply-web-platform-infra's SSH `-target` set, bootstrap in apply-deploy-pipeline-fix's set), `root_authorized_keys` in `ci-ssh-key.tf` (exclusion allowlist). `deploy_pipeline_fix` is `local-exec`/non-SSH → not counted.
- Parser does NOT false-match the `connection{type="ssh"}` comment at `server.tf:305` (comment-stripped before matching).
- `apply-deploy-pipeline-fix.yml` regression: still applies its 2 targets via the extracted action.
- Operator-local `terraform plan` (key var unset) shows no diff on the connection blocks (byte-equivalent via `agent = true` fallback).
- First-bootstrap simulation: tokens absent → SSH-apply step `::warning::`-skips, job still succeeds; non-SSH apply + token sync still run.

## Plan Review Findings (4-agent panel + SpecFlow — applied)

| Reviewer | Finding | Severity | Disposition |
|---|---|---|---|
| SpecFlow | 2c: parser false-matches the `connection{type="ssh"}` comment at server.tf:305 | P0 | **Applied** — Phase 5 strips `#` comments before matching |
| SpecFlow | 5a: server.tf change fires both apply workflows (state-lock + same-host) | P0 | **Applied** — shared concurrency group on both SSH-applying workflows (Phase 4; deepen-plan confirms) |
| Kieran/SpecFlow | 2a: `≥9` sentinel unreachable parsing server.tf alone; deploy_pipeline_fix mis-counted | P1 | **Applied** — Phase 5 globs all infra `*.tf`; recount excludes local-exec |
| SpecFlow | 5b: fresh-rebuild bootstrap inversion (bridge needs tokens this workflow produces) | P1 | **Applied** — shape B token-gated SSH apply after token sync |
| SpecFlow | 4a/1c: coupled blast radius + long idle window | P1 | **Applied** — shape B decouples SSH apply; bridge up only for it |
| SpecFlow | 1a: teardown must replicate `-n` guards on SERVER_IP/CLOUDFLARED_PID | P1 | **Applied** — Phase 4 + AC4 require the guards |
| Kieran | P2: stale CAVEAT in apply-deploy-pipeline-fix.yml:46-54 after Phase 3 | P2 | **Applied** — added to Phase 2 / Files to Edit |
| SpecFlow | 2b: parity test is one-directional (stale/typo'd -target uncaught) | P2 | **Accepted as documented limitation** (Phase 5 + Risks) |
| DHH | Over-structured phases; ceremony ACs (AC5/AC10 narrative) | MEDIUM | **Applied** — ACs collapsed to grep/run-checkable; AC10 kept as load-bearing Ref-not-Closes one-liner |
| Simplicity | Drop the composite-action README (no peer action has one) | MEDIUM | **Applied** — folded into action.yml header comments |
| Simplicity/DHH | CODEOWNERS discussed in 4 places | LOW | **Applied** — decisive single row added (Phase 6) |
| DHH | Scope is sound; abstraction + parity test both load-bearing | — | No change (confirmed keep) |

Kieran verdict: APPROVE-with-one-blocking-fix (the P1 parity scope — applied). DHH: ship the work, trim the plan (done). Simplicity: minor tweaks only (done). Open architectural item for deepen-plan: confirm the 5a shared-concurrency-group name + coupling trade-off.
