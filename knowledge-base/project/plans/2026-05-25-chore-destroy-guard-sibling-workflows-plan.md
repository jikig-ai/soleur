---
type: chore
lane: single-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user-incident
closes: 4419
follows: 4420
---

# chore: Extend destroy-guard widening to apply-sentry-infra and apply-web-platform-infra (#4419)

## Overview

PR #4420 (closed #3915) widened the destroy-guard at `.github/workflows/apply-github-infra.yml` to catch nested `required_check` block removals on `github_repository_ruleset` via a path-specific jq filter at `tests/scripts/lib/destroy-guard-filter.jq`. Two sibling apply workflows still carry the pre-fix resource-only counter:

- `.github/workflows/apply-sentry-infra.yml` — counts only `change.actions = ["delete"]` against `sentry_cron_monitor.*` (lines 187-207).
- `.github/workflows/apply-web-platform-infra.yml` — counts only `change.actions = ["delete"]` against the ~70-resource allow-list (lines 315-340).

This PR closes #4419 by:

1. **Surveying** every resource type in the two sibling workflows' apply allow-lists, classifying each as "no nested-block exposure" / "vulnerable nested-block exposure".
2. **For apply-sentry-infra:** documenting that `sentry_cron_monitor` has zero array-of-blocks (it uses `schedule = {...}` object-attribute syntax, not `schedule { ... }` block syntax). Switch to a per-workflow filter file that emits `{resource_deletes, nested_deletes: 0}` for **consistency** with the github-infra wiring, so a future schema change that introduces a nested block has one obvious place to extend.
3. **For apply-web-platform-infra:** five in-scope resource types have nested-block exposure analogous to `required_check`. The highest-impact case (the ACME carve-out at `cloudflare_ruleset.seo_page_redirects.rules[10]`) would silently break Let's Encrypt cert renewal — same single-user-incident threshold as #4420. Write a per-workflow filter `tests/scripts/lib/destroy-guard-filter-web-platform.jq` that counts shrinkage on each.

**Per-workflow filter files** (NOT a shared lib parameterized by resource type) — mirrors #4420's path-specific design. The survey shows two distinct surfaces; the "shared lib" threshold (3+ converging resources across workflows) is not met. Three filter files keep each workflow's nested-block contract obvious to a reviewer reading any single workflow.

## User-Brand Impact

**If this lands broken, the user experiences:** CI failures during `apply-sentry-infra` or `apply-web-platform-infra` runs if a widened filter has a bug. Surfaces as workflow-run failure on the merge commit; operator-noticed within minutes. False positive: legitimate updates trip the guard until operator adds `[ack-destroy]` — friction but not silent regression.

**If this leaks, the user's data is exposed via:** N/A — no PII, no user data. Workflows operate on Terraform plan JSON.

**Brand-survival threshold:** `single-user incident`. The chain this defends:

- **HIGH-impact path:** `apply-web-platform-infra` silently un-requires the ACME carve-out at `cloudflare_ruleset.seo_page_redirects.rules[10]` (the rule whose `(not ssl) and not (... acme-challenge ...)` expression carves out the Let's Encrypt HTTP-01 challenge). Removing that single nested `rules { }` block silently re-fires the 2026-05-18 cert outage post-mortem (PR-β / issue #3976) on the next ~60-day cert renewal. Cert expires → `https://soleur.ai/` 502s → every user lands on a broken cert page. The `sentry_uptime_monitor.soleur_acme_probe` (uptime-monitors.tf:31-60) catches this AT renewal time, not at the un-requiring commit — by then the operator is in incident mode, not preventive mode.
- **SECONDARY path:** `apply-web-platform-infra` silently removes `cloudflare_zero_trust_tunnel_cloudflared_config.web.config.ingress_rule[ssh]` — CI deploy pipeline (`apply-deploy-pipeline-fix.yml`) cannot SSH to the host, every prod deploy breaks. Operator-visible on first deploy attempt; user-visible if the broken deploy lands a release with a bug.
- **LOW-impact path:** `apply-sentry-infra` has no array-of-blocks today. The wiring is consistency-defense-in-depth; no current attack surface.

CPO sign-off required at plan time per the carried-forward `single-user incident` threshold from PR #4420. Same `user-impact-reviewer` agent runs at review time per the conditional-agent block in `plugins/soleur/skills/review/SKILL.md`.

## Research Reconciliation — Spec vs. Codebase

The issue body prescribed surveying `cloudflare_ruleset` and `sentry_cron_monitor`. Reconciliation against the live repo:

- **Sentry resources actually in scope.** `apply-sentry-infra.yml:168-180` targets only `sentry_cron_monitor.*` (11 explicit targets). `sentry_issue_alert.*` and `sentry_uptime_monitor.*` resources EXIST in `apps/web-platform/infra/sentry/{issue-alerts.tf,uptime-monitors.tf}` but are NOT in the auto-apply scope — they are import-only / operator-locally-applied per their file headers. The destroy-guard fix scope is the apply allow-list, not the whole TF root.
- **Sentry TF root location.** The issue body said "apps/sentry/infra/" — that path does NOT exist. Sentry TF lives at `apps/web-platform/infra/sentry/`. The workflow's `INFRA_DIR` env (line 56) confirms.
- **`sentry_cron_monitor` nested-block check.** Inspected `apps/web-platform/infra/sentry/cron-monitors.tf:48-62`: uses `schedule = { crontab = "..." }` — that is HCL object-attribute syntax (a value-assigned map), not a block. JSON plan path: `change.before.schedule.crontab` (string). A `schedule` removal would still be a resource-level delete (the monitor itself), caught by the existing resource-delete counter. **Conclusion: no nested-block exposure today.**
- **Web-platform resource inventory.** The issue body named "Cloudflare, Hetzner, Inngest" generically. Actual in-scope nested-block-bearing resources (cross-referenced against the `-target=` allow-list at apply-web-platform-infra.yml:235-308):
  - `cloudflare_ruleset` — 4 instances (cache_shared_binaries, seo_page_redirects, seo_response_headers, allowlist_ai_crawlers). Repeated `rules { }` blocks; seo_page_redirects has 13 (verified via `grep -c '^  rules {' apps/web-platform/infra/seo-rulesets.tf`). **VULNERABLE.**
  - `cloudflare_zero_trust_tunnel_cloudflared_config.web` — single `config { }` containing three repeated `ingress_rule { }` blocks (tunnel.tf:26-49). **VULNERABLE.**
  - `cloudflare_zone_settings_override.soleur_ai` — single `settings { }` containing single `security_header { }` (cloudflare-settings.tf:14-43). HSTS is the load-bearing field; removing the block silently un-sets HSTS. **VULNERABLE (single-block-shrinkage variant).**
  - `cloudflare_notification_policy.service_token_expiry` — single `email_integration { }` (tunnel.tf:122-132). Removing it disables the 7-day expiry alert. **VULNERABLE (single-block-shrinkage variant).**
  - `cloudflare_zero_trust_access_policy.*` — 2 instances. Single `include { }` block (tunnel.tf:75-77, 111-113). Removing the include leaves a policy with no access criteria — fail-closed (no one gets in) but still semantically destructive. **VULNERABLE.**
  - `cloudflare_bot_management.soleur_ai` — flat attributes only. **Not vulnerable.**
  - `cloudflare_record.*` — flat attributes only (~35 records). **Not vulnerable.**
  - `betteruptime_*`, `doppler_*`, `random_id`, `hcloud_firewall*`, `tls_private_key`, `github_actions_secret` — all flat. **Not vulnerable.**
- **Filter design decision.** Survey shows 5 vulnerable resource types across one workflow + 0 across the other → **two new per-workflow filter files** (not a shared lib). Three files in total:
  - `tests/scripts/lib/destroy-guard-filter.jq` (existing, unchanged, github_repository_ruleset)
  - `tests/scripts/lib/destroy-guard-filter-sentry.jq` (new, no nested surface today)
  - `tests/scripts/lib/destroy-guard-filter-web-platform.jq` (new, covers 5 resource types)
- **Filter contract.** Each emits `{resource_deletes: int, nested_deletes: int}`. Caller sums to `destroy_count`, runs the same `[ack-destroy]` regex byte-identical to PR #4420.
- **Fixture sourcing.** Same posture as #4420 plan AC3: capture one real `terraform plan` per workflow (redacted) as a regression anchor; supplement with synthesized fixtures for the cases real plans rarely produce.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — apply-sentry-infra wired through filter file.** `.github/workflows/apply-sentry-infra.yml` "Terraform plan (cron monitors only)" step replaces its inline single-line `destroy_count=$(...)` with the `counts=$(jq -f ...) ; resource_deletes=...; nested_deletes=...; destroy_count=$((resource_deletes + nested_deletes))` shape from PR #4420 (apply-github-infra.yml:244-265). Filter path: `${GITHUB_WORKSPACE}/tests/scripts/lib/destroy-guard-filter-sentry.jq`. The integer-validation gate (`[[ ! "$resource_deletes" =~ ^[0-9]+$ ]] || [[ ! "$nested_deletes" =~ ^[0-9]+$ ]]`) is preserved. The error-message literal `"on cron monitors"` (originally `"on cron monitors."`) is updated to the two-counter form mirroring apply-github-infra.yml:261: `"on sentry infra (${resource_deletes} resource-level delete(s) + ${nested_deletes} nested-block removal(s))."`. The `[ack-destroy]` regex `(^|$'\n')\[ack-destroy\]($|$'\n')` is byte-identical to apply-sentry-infra.yml:199.

- [ ] **AC2 — apply-web-platform-infra wired through filter file.** `.github/workflows/apply-web-platform-infra.yml` "Terraform plan (allow-list, non-SSH resources only)" step replaces its inline single-line `destroy_count=$(...)` with the same shape as AC1, pointing at `${GITHUB_WORKSPACE}/tests/scripts/lib/destroy-guard-filter-web-platform.jq`. Error message updated to: `"on web-platform infra (${resource_deletes} resource-level delete(s) + ${nested_deletes} nested-block removal(s))."`. `[ack-destroy]` regex byte-identical to apply-web-platform-infra.yml:332.

- [ ] **AC3 — `destroy-guard-filter-sentry.jq` exists and emits the two-counter contract.** File `tests/scripts/lib/destroy-guard-filter-sentry.jq` is committed. Output schema: `{resource_deletes: int, nested_deletes: int}`. Body sets `nested_deletes: 0` with a documenting comment that no resource currently in the sentry apply scope (`sentry_cron_monitor.*`) exposes array-of-blocks. Future `nested_deletes` additions extend this clause with one path-specific block per new vulnerable resource — NO recursive walks.

- [ ] **AC4 — `destroy-guard-filter-web-platform.jq` exists and covers the 5 vulnerable resource types.** File `tests/scripts/lib/destroy-guard-filter-web-platform.jq` is committed. Contract: `{resource_deletes: int, nested_deletes: int}`. `nested_deletes` sums shrinkage on:
  1. `cloudflare_ruleset.*` → `.rules` array length delta.
  2. `cloudflare_zero_trust_tunnel_cloudflared_config.*` → `.config[0].ingress_rule` array length delta.
  3. `cloudflare_zone_settings_override.*` → `.settings[0].security_header` array length delta (single-block-shrinkage: 1 → 0).
  4. `cloudflare_notification_policy.*` → `.email_integration` array length delta.
  5. `cloudflare_zero_trust_access_policy.*` → `.include` array length delta.

  Each resource-type clause uses the same `select(.change.actions? | index("delete") | not)` guard as the github filter to prevent double-counting if the parent is also being deleted. Each clause uses `select(. > 0)` to drop additions (we count shrinkage only). NO recursion (no `walk()`); each path is literal. Each `_count($side)` helper takes a value-arg (jq 1.7+ value-binding form, safe on 1.8.x — NOT the call-by-name filter-arg shape that crashed v1 of #4420).

- [ ] **AC5 — Unit test for sentry filter passes.** `bash tests/scripts/test-destroy-guard-counter-sentry.sh` exits 0. Cases:
  - **T1** `tfplan-sentry-resource-delete.json` — `sentry_cron_monitor` with `change.actions = ["delete"]`. No ack → `1:0:1:1`.
  - **T2** `tfplan-sentry-no-changes.json` — empty `resource_changes`. → `0:0:0:0`.
  - **T3** `tfplan-sentry-resource-delete.json` + `[ack-destroy]` line → `1:0:1:0`.
  - **T4** `tfplan-sentry-real-baseline.json` (captured, redacted) → `0:0:0:0` (regression anchor).
  - **T5** `[ack-destroy]` substring mid-line on T1 fixture → `1:0:1:1` (line-anchor guard).

- [ ] **AC6 — Unit test for web-platform filter passes.** `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` exits 0. Cases:
  - **T1** `tfplan-cf-ruleset-rule-removal.json` — `cloudflare_ruleset.seo_page_redirects` `update`, `before.rules` length=13, `after.rules` length=12. → `0:1:1:1`.
  - **T2** `tfplan-cf-tunnel-ingress-removal.json` — `cloudflare_zero_trust_tunnel_cloudflared_config.web` `update`, `before.config[0].ingress_rule` length=3, `after.config[0].ingress_rule` length=2. → `0:1:1:1`.
  - **T3** `tfplan-cf-zone-settings-header-removal.json` — `cloudflare_zone_settings_override.soleur_ai` `update`, `before.settings[0].security_header` length=1, `after.settings[0].security_header` length=0. → `0:1:1:1`.
  - **T4** `tfplan-cf-notification-integration-removal.json` — `cloudflare_notification_policy` `update`, `before.email_integration` length=1, `after.email_integration` length=0. → `0:1:1:1`.
  - **T5** `tfplan-cf-access-policy-include-removal.json` — `cloudflare_zero_trust_access_policy` `update`, `before.include` length=1, `after.include` length=0. → `0:1:1:1`.
  - **T6** `tfplan-web-platform-no-changes.json` — empty. → `0:0:0:0`.
  - **T7** `tfplan-cf-ruleset-resource-delete.json` — resource-level delete on `cloudflare_ruleset`. → `1:0:1:1` (no nested double-count even though the `select(... | not)` clause would drop it from nested).
  - **T8** `tfplan-web-platform-mixed.json` — 1 resource-level delete on `cloudflare_record` + 1 nested removal on `cloudflare_ruleset` → `1:1:2:1`.
  - **T9** `tfplan-cf-ruleset-rule-addition.json` — `before.rules` length=12, `after.rules` length=13. → `0:0:0:0` (additions ignored by `select(. > 0)`).
  - **T10** `tfplan-web-platform-real-baseline.json` (captured, redacted) → `0:0:0:0` (regression anchor).
  - **T11** `[ack-destroy]` line on T1 fixture → `0:1:1:0`.
  - **T12** `[ack-destroy]` substring mid-line on T1 fixture → `0:1:1:1` (line-anchor guard).

- [ ] **AC7 — `shellcheck` passes** on both new test files. `shellcheck -x tests/scripts/test-destroy-guard-counter-sentry.sh tests/scripts/test-destroy-guard-counter-web-platform.sh` exits 0.

- [ ] **AC8 — `actionlint` passes** on both modified workflows. `actionlint .github/workflows/apply-sentry-infra.yml .github/workflows/apply-web-platform-infra.yml` exits 0.

- [ ] **AC9 — Old single-line filter fully replaced.** Both `git grep -nE 'resource_changes\[\?\]\?.*delete.*length' .github/workflows/apply-sentry-infra.yml` and `git grep -nE 'resource_changes\[\?\]\?.*delete.*length' .github/workflows/apply-web-platform-infra.yml` return zero matches. Each workflow has exactly one `destroy_count=\$\(\(` arithmetic-expansion assignment (the new sum).

- [ ] **AC10 — `[ack-destroy]` regex byte-identical preserved on both.** Two `diff` invocations confirm no regex changes:
  ```bash
  diff <(grep -F '[[ "$HEAD_MSG" =~' .github/workflows/apply-sentry-infra.yml.orig) \
       <(grep -F '[[ "$HEAD_MSG" =~' .github/workflows/apply-sentry-infra.yml)
  ```
  Same for apply-web-platform-infra.yml. (Orig is captured pre-edit; both .yml files keep the original two `[skip-*-apply]` + `[ack-destroy]` regex lines untouched.)

- [ ] **AC11 — CODEOWNERS rows added for new filter + test paths.** `.github/CODEOWNERS` gains four new rows after line 81:
  ```
  /tests/scripts/lib/destroy-guard-filter-sentry.jq        @deruelle
  /tests/scripts/lib/destroy-guard-filter-web-platform.jq  @deruelle
  /tests/scripts/test-destroy-guard-counter-sentry.sh      @deruelle
  /tests/scripts/test-destroy-guard-counter-web-platform.sh @deruelle
  ```
  The existing `tfplan-*.json` glob at line 81 already covers the new fixture files; no fixture-glob edit needed. Verified at plan-time via `grep -E '^/tests/scripts/fixtures/tfplan-\*\.json' .github/CODEOWNERS` returning the existing row.

- [ ] **AC12 — Captured real-CI fixtures committed and redacted.** Two fixtures generated via the operator commands in the test-file header comments (mirrors PR #4420 AC3):
  - `tests/scripts/fixtures/tfplan-sentry-real-baseline.json` — captured from `terraform plan` against `apps/web-platform/infra/sentry/` HEAD with the `-target=` allow-list from apply-sentry-infra.yml.
  - `tests/scripts/fixtures/tfplan-web-platform-real-baseline.json` — captured from `terraform plan` against `apps/web-platform/infra/` HEAD with the `-target=` allow-list from apply-web-platform-infra.yml.

  Both redacted via the same `jq 'del(.variables) | del(.. | .bypass_actors? | .[]?.actor_id?)'` pattern from PR #4420 plus provider-specific extensions: `del(.. | .config[]?.ingress_rule[]?.hostname?)` if a hostname leaks tenancy. Verified via:
  ```bash
  ! grep -qE 'BEGIN [A-Z ]*PRIVATE KEY|ghp_|ghs_|github_pat_|sbp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|sk_(test|live)_[a-zA-Z0-9]{24,}' \
      tests/scripts/fixtures/tfplan-sentry-real-baseline.json \
      tests/scripts/fixtures/tfplan-web-platform-real-baseline.json
  ```

### Post-merge (operator / automation)

- [ ] **AC13 — Close #4419.** `gh issue close 4419 --comment "Fixed in <merge-commit-sha>. Per-workflow destroy-guard filters now cover (1) sentry: no current nested-block exposure documented in destroy-guard-filter-sentry.jq, future schema changes extend that file's nested_deletes clause; (2) web-platform: five vulnerable resource types (cloudflare_ruleset, cloudflare_zero_trust_tunnel_cloudflared_config, cloudflare_zone_settings_override, cloudflare_notification_policy, cloudflare_zero_trust_access_policy) covered in destroy-guard-filter-web-platform.jq. CODEOWNERS rows added for the new filter/test paths. Cap-coupling concern from #4420 resolved across the apply-* workflow trio."`

## Implementation Phases

### Phase 0 — Preconditions

1. **CWD verification.** `pwd` equals `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-4419-destroy-guard-sibling-workflows`. Bash CWD does not persist between tool calls — every command runs with absolute paths or `git -C <abs>` form.
2. **Tooling probe.** `command -v jq actionlint shellcheck terraform` — all four available (verified at plan-time: jq 1.8.1, actionlint + shellcheck in `~/.local/bin/`, terraform via Doppler-wired CI).
3. **Re-read existing apply-sentry-infra.yml** at lines 187-207 (the inline destroy_count block) and apply-web-platform-infra.yml at lines 315-340 to confirm exact byte boundaries before edit. Capture `.yml.orig` copies for AC10's `diff` source.
4. **Re-read PR #4420's destroy-guard-filter.jq** to lift the value-arg `_count($side)` shape verbatim (avoids re-deriving the jq 1.7+ binding form).
5. **Confirm CODEOWNERS line 81 glob** `^/tests/scripts/fixtures/tfplan-\*\.json` covers any new `tfplan-*.json` fixture without a per-file edit.

### Phase 1 — RED (write failing tests + create per-workflow filter stubs)

1. **Create synthesized fixtures** (raw JSON matching `terraform show -json` v1.0 plan schema):
   - **Sentry fixtures:**
     - `tfplan-sentry-resource-delete.json` — single `sentry_cron_monitor.scheduled_terraform_drift` with `change.actions = ["delete"]`, `change.before` populated, `change.after = null`.
     - `tfplan-sentry-no-changes.json` — empty `resource_changes` array.
   - **Web-platform fixtures:**
     - `tfplan-cf-ruleset-rule-removal.json` — `cloudflare_ruleset.seo_page_redirects` `update`. `before.rules` length=13 (model on real seo-rulesets.tf shape — id/expression/action/action_parameters/from_value/target_url filled per the 2026-05-18 ACME carve-out shape); `after.rules` length=12 (Rule 10 ACME carve-out removed — the highest-impact realistic regression).
     - `tfplan-cf-tunnel-ingress-removal.json` — `cloudflare_zero_trust_tunnel_cloudflared_config.web` `update`. `before.config[0].ingress_rule` length=3 (deploy + ssh + catch-all); `after` length=2 (ssh removed — would brick CI deploy pipeline).
     - `tfplan-cf-zone-settings-header-removal.json` — `cloudflare_zone_settings_override.soleur_ai` `update`. `before.settings[0].security_header` length=1; `after` length=0 (HSTS un-set).
     - `tfplan-cf-notification-integration-removal.json` — `cloudflare_notification_policy.service_token_expiry` `update`. `before.email_integration` length=1; `after` length=0.
     - `tfplan-cf-access-policy-include-removal.json` — `cloudflare_zero_trust_access_policy.ci_ssh_service_token` `update`. `before.include` length=1; `after` length=0.
     - `tfplan-web-platform-no-changes.json` — empty.
     - `tfplan-cf-ruleset-resource-delete.json` — `cloudflare_ruleset.allowlist_ai_crawlers` with `change.actions = ["delete"]`.
     - `tfplan-web-platform-mixed.json` — one `cloudflare_record.www` delete + one `cloudflare_ruleset.cache_shared_binaries` nested-removal in the SAME plan.
     - `tfplan-cf-ruleset-rule-addition.json` — `before.rules` length=12, `after.rules` length=13 (proves `select(. > 0)` filters additions).
2. **Captured fixtures** (AC12):
   - **`tfplan-sentry-real-baseline.json`:** operator (or `/work`-time bash) runs the documented command sequence (in test file header):
     ```bash
     cd apps/web-platform/infra/sentry
     SENTRY_AUTH_TOKEN=$(... from GH secret) terraform init -input=false
     SENTRY_AUTH_TOKEN=... terraform plan -no-color -input=false -out=/tmp/tfplan \
       -target=sentry_cron_monitor.scheduled_terraform_drift \
       ... (all 11 targets from apply-sentry-infra.yml:168-180)
     terraform show -json /tmp/tfplan > /tmp/raw.json
     jq 'del(.variables)' /tmp/raw.json > tests/scripts/fixtures/tfplan-sentry-real-baseline.json
     ```
     Verify no token bytes survive with the AC12 grep.
   - **`tfplan-web-platform-real-baseline.json`:** same procedure against `apps/web-platform/infra/` with the full apply-web-platform-infra.yml allow-list. **Important:** uses the canonical Doppler triplet from `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md` — separate `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` export PLUS `doppler run --name-transformer tf-var`.
   - **Redaction extensions for web-platform.** The web-platform plan JSON carries Doppler service tokens (`doppler_secret.*` values), tls private keys (`tls_private_key.ci_ssh`), random_id seeds, Cloudflare API tokens via `cf_api_token_*` variables, and Resend API keys. The redaction expression MUST `del(.variables)` (catches all TF_VAR_*-sourced inputs), `del(.. | .secret_b64?)` (random_id seeds), and `del(.. | .private_key_pem?)` (tls keys). Operator review of the resulting JSON before commit is mandatory — if any field grep-matches the AC12 sentinel regex, add a `del()` and re-capture.

3. **Create `tests/scripts/test-destroy-guard-counter-sentry.sh`** mirroring the shape of `tests/scripts/test-destroy-guard-counter.sh` (same `_run_gate` helper, same `_report` accounting, same byte-identical `[ack-destroy]` regex check). At the top: same fixture-capture header comment block documenting the operator regeneration command.

4. **Create `tests/scripts/test-destroy-guard-counter-web-platform.sh`** with the 12 cases enumerated in AC6, same shape.

5. **At this point:** both test files reference `.jq` filters that don't exist yet → both fail with `jq: error: Could not open file...`. RED state confirmed.

### Phase 2 — GREEN (write the per-workflow filters)

1. **Create `tests/scripts/lib/destroy-guard-filter-sentry.jq`:**

   ```jq
   # Destroy-guard counter for apply-sentry-infra.yml. Path-specific per
   # the #4420 plan-review iteration: NO recursive walk(); each future
   # nested-block-bearing resource type gets its own `select(.type == ...)`
   # clause documented inline. Mirrors tests/scripts/lib/destroy-guard-filter.jq
   # (the github_repository_ruleset case) byte-for-byte where applicable.
   #
   # CURRENT SCOPE: apply-sentry-infra.yml targets only `sentry_cron_monitor.*`
   # resources (see apply-sentry-infra.yml:168-180 -target= list). At the time
   # of this filter's creation (#4419), `sentry_cron_monitor` exposes ZERO
   # array-of-blocks: `schedule = { crontab = "..." }` is HCL object-attribute
   # syntax (a map value), not a block. JSON plan path:
   # `change.before.schedule.crontab` (string). Removing schedule = removing
   # the monitor = resource-level delete, already caught by `resource_deletes`.
   #
   # EXTENDING THIS FILTER: when a future schema change introduces a new
   # nested-block-bearing sentry resource (or when the apply scope widens
   # to include sentry_issue_alert / sentry_uptime_monitor which use list-
   # attributes, NOT blocks), add ONE path-specific clause to the
   # `nested_deletes` array per Schedule-shape. Do NOT introduce walk().
   #
   # Input: `terraform show -json <plan>` document.
   # Output: {resource_deletes: int, nested_deletes: int}.

   {
     resource_deletes: ([.resource_changes[]? | select(.change.actions? | index("delete"))] | length),
     nested_deletes:   0
   }
   ```

   The `nested_deletes: 0` literal is intentional — every future addition is a documented extension of this file, NOT a quiet generalization of the github filter.

2. **Create `tests/scripts/lib/destroy-guard-filter-web-platform.jq`:**

   ```jq
   # Destroy-guard counter for apply-web-platform-infra.yml. Path-specific
   # per #4420; NO recursive walk(). Five resource types have array-of-blocks
   # or single-block surfaces in the current apply allow-list (verified
   # 2026-05-25 via apps/web-platform/infra/*.tf inspection):
   #
   #   1. cloudflare_ruleset.*                              .rules
   #   2. cloudflare_zero_trust_tunnel_cloudflared_config.* .config[0].ingress_rule
   #   3. cloudflare_zone_settings_override.*               .settings[0].security_header
   #   4. cloudflare_notification_policy.*                  .email_integration
   #   5. cloudflare_zero_trust_access_policy.*             .include
   #
   # The HIGHEST-impact case is (1) — removing the ACME carve-out
   # (cloudflare_ruleset.seo_page_redirects.rules[10] at seo-rulesets.tf:240-254)
   # would silently re-fire the 2026-05-18 cert-renewal outage on the next
   # ~60-day Let's Encrypt renewal cycle.
   #
   # SCHEMA STABILITY: `terraform show -json change.before` / `change.after`
   # are documented contracts
   # (https://developer.hashicorp.com/terraform/internals/json-format#change-representation).
   # When a single-block (MaxItems: 1) surface is omitted, Terraform encodes
   # it as an empty array in the JSON plan — that's why .config[0],
   # .settings[0], and .email_integration / .include all index identically.
   #
   # INPUT: `terraform show -json <plan>` document.
   # OUTPUT: {resource_deletes: int, nested_deletes: int}.

   # Each `_count($side)` helper uses `$side` value-binding (jq 1.7+; safe on
   # jq 1.8.x). NOT the call-by-name filter-arg shape that crashed v1 of
   # #4420 on string-key descent. The `($side // {})` null-coalesce keeps
   # the count valid for resources whose `before` or `after` is null
   # (resource-create / resource-delete edges that the outer `select(.. |
   # not)` guard already excludes from this branch).

   def cf_ruleset_rules_count($side):
     ($side // {}) | [.rules[]?] | length;

   def cf_tunnel_ingress_count($side):
     ($side // {}) | [.config[]?.ingress_rule[]?] | length;

   def cf_zone_security_header_count($side):
     ($side // {}) | [.settings[]?.security_header[]?] | length;

   def cf_notif_email_integration_count($side):
     ($side // {}) | [.email_integration[]?] | length;

   def cf_access_policy_include_count($side):
     ($side // {}) | [.include[]?] | length;

   {
     resource_deletes: ([.resource_changes[]? | select(.change.actions? | index("delete"))] | length),
     nested_deletes: (
       [
         # 1. cloudflare_ruleset.rules
         (.resource_changes[]?
          | select(.type == "cloudflare_ruleset")
          | select(.change.actions? | index("delete") | not)
          | (cf_ruleset_rules_count(.change.before) - cf_ruleset_rules_count(.change.after))
          | select(. > 0)),
         # 2. cloudflare_zero_trust_tunnel_cloudflared_config.config[0].ingress_rule
         (.resource_changes[]?
          | select(.type == "cloudflare_zero_trust_tunnel_cloudflared_config")
          | select(.change.actions? | index("delete") | not)
          | (cf_tunnel_ingress_count(.change.before) - cf_tunnel_ingress_count(.change.after))
          | select(. > 0)),
         # 3. cloudflare_zone_settings_override.settings[0].security_header
         (.resource_changes[]?
          | select(.type == "cloudflare_zone_settings_override")
          | select(.change.actions? | index("delete") | not)
          | (cf_zone_security_header_count(.change.before) - cf_zone_security_header_count(.change.after))
          | select(. > 0)),
         # 4. cloudflare_notification_policy.email_integration
         (.resource_changes[]?
          | select(.type == "cloudflare_notification_policy")
          | select(.change.actions? | index("delete") | not)
          | (cf_notif_email_integration_count(.change.before) - cf_notif_email_integration_count(.change.after))
          | select(. > 0)),
         # 5. cloudflare_zero_trust_access_policy.include
         (.resource_changes[]?
          | select(.type == "cloudflare_zero_trust_access_policy")
          | select(.change.actions? | index("delete") | not)
          | (cf_access_policy_include_count(.change.before) - cf_access_policy_include_count(.change.after))
          | select(. > 0))
       ] | add // 0
     )
   }
   ```

3. **Edit `.github/workflows/apply-sentry-infra.yml`** "Terraform plan (cron monitors only)" step. Replace the inline `destroy_count=$(...)` single-line block (lines 192-193) with the same multi-line wiring from apply-github-infra.yml:244-265, pointing at `destroy-guard-filter-sentry.jq`. Preserve byte-identical: `set -uo pipefail` posture (line 167), the existing `-target=` list (168-180), the `[ack-destroy]` regex (199), and the kill-switch + summary blocks. Update the error message literal at line 203 to the two-counter form: `"on sentry infra (${resource_deletes} resource-level delete(s) + ${nested_deletes} nested-block removal(s))."`. Add an inline source-of-truth comment matching apply-github-infra.yml:236-243.

4. **Edit `.github/workflows/apply-web-platform-infra.yml`** "Terraform plan (allow-list, non-SSH resources only)" step. Same shape, replacing lines 318-326 (the single-line `destroy_count=$(...)` + parse-validation block) with the two-counter wiring pointing at `destroy-guard-filter-web-platform.jq`. Update error message at line 336 to: `"on web-platform infra (${resource_deletes} resource-level delete(s) + ${nested_deletes} nested-block removal(s))."`. Preserve byte-identical: the long `-target=` list (235-308), `set -uo pipefail` (line 231), the `[ack-destroy]` regex (332), the existing kill-switch / Doppler-write-token / sync-CI-SSH-token / summary blocks.

5. **Edit `.github/CODEOWNERS`** to add the four new rows after line 81 (AC11). Place them immediately after the existing fixtures glob — same `@deruelle` owner, same protection rationale (mutating these silently neutralises the `[ack-destroy]` gate).

6. **Run `bash tests/scripts/test-destroy-guard-counter-sentry.sh`** — must exit 0 (GREEN).
7. **Run `bash tests/scripts/test-destroy-guard-counter-web-platform.sh`** — must exit 0 (GREEN).
8. **Run `bash tests/scripts/test-destroy-guard-counter.sh`** (existing github filter test) — must still exit 0 (regression check; no edits to that filter or test, but the apply-github-infra workflow remains the reference shape).
9. **Run `shellcheck -x tests/scripts/test-destroy-guard-counter-sentry.sh tests/scripts/test-destroy-guard-counter-web-platform.sh`** — must exit 0.
10. **Run `actionlint .github/workflows/apply-sentry-infra.yml .github/workflows/apply-web-platform-infra.yml`** — must exit 0.

### Phase 3 — Pre-ship sanity

1. **AC9 verification.** `git grep -nE 'resource_changes\[\?\]\?.*delete.*length' .github/workflows/apply-sentry-infra.yml .github/workflows/apply-web-platform-infra.yml` → 0 matches. `git grep -nE 'destroy_count=\$\(\(' .github/workflows/apply-sentry-infra.yml .github/workflows/apply-web-platform-infra.yml` → exactly 2 matches (the new arithmetic-expansion assignment in each file).
2. **AC10 verification.** `diff` both pre-edit `.yml.orig` snapshots against the post-edit files for the `[ack-destroy]` regex line — no output.
3. **AC11 verification.** `grep -nE 'destroy-guard-filter-(sentry|web-platform)' .github/CODEOWNERS` returns 2 matches; `grep -nE 'test-destroy-guard-counter-(sentry|web-platform)' .github/CODEOWNERS` returns 2 matches.
4. **AC12 verification.** `! grep -qE 'BEGIN [A-Z ]*PRIVATE KEY|ghp_|ghs_|github_pat_|sbp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|sk_(test|live)_[a-zA-Z0-9]{24,}' tests/scripts/fixtures/tfplan-sentry-real-baseline.json tests/scripts/fixtures/tfplan-web-platform-real-baseline.json` — exit 0 (no secret bytes survived redaction).
5. **PR body draft** includes `Closes #4419` (`wg-use-closes-n-in-pr-body-not-title-to`) and a Test Plan section enumerating the AC5 + AC6 cases.

## Files to Edit

- `.github/workflows/apply-sentry-infra.yml` — replace inline destroy-guard single-liner with two-counter shape pointing at `destroy-guard-filter-sentry.jq`. Preserve `[ack-destroy]` regex byte-identical; update error message literal.
- `.github/workflows/apply-web-platform-infra.yml` — replace inline destroy-guard single-liner with two-counter shape pointing at `destroy-guard-filter-web-platform.jq`. Preserve `[ack-destroy]` regex byte-identical; update error message literal.
- `.github/CODEOWNERS` — add 4 new rows after line 81 for the new filter + test paths.

## Files to Create

- `tests/scripts/lib/destroy-guard-filter-sentry.jq` — path-specific filter for sentry workflow (no nested surface today; literal `nested_deletes: 0`).
- `tests/scripts/lib/destroy-guard-filter-web-platform.jq` — path-specific filter for web-platform workflow covering 5 resource types.
- `tests/scripts/test-destroy-guard-counter-sentry.sh` — 5-case bash test.
- `tests/scripts/test-destroy-guard-counter-web-platform.sh` — 12-case bash test.
- `tests/scripts/fixtures/tfplan-sentry-resource-delete.json` — synthesized.
- `tests/scripts/fixtures/tfplan-sentry-no-changes.json` — synthesized.
- `tests/scripts/fixtures/tfplan-sentry-real-baseline.json` — captured, redacted (AC12).
- `tests/scripts/fixtures/tfplan-cf-ruleset-rule-removal.json` — synthesized (PR #4395-shape analog for cloudflare_ruleset).
- `tests/scripts/fixtures/tfplan-cf-tunnel-ingress-removal.json` — synthesized.
- `tests/scripts/fixtures/tfplan-cf-zone-settings-header-removal.json` — synthesized.
- `tests/scripts/fixtures/tfplan-cf-notification-integration-removal.json` — synthesized.
- `tests/scripts/fixtures/tfplan-cf-access-policy-include-removal.json` — synthesized.
- `tests/scripts/fixtures/tfplan-cf-ruleset-resource-delete.json` — synthesized.
- `tests/scripts/fixtures/tfplan-web-platform-mixed.json` — synthesized.
- `tests/scripts/fixtures/tfplan-cf-ruleset-rule-addition.json` — synthesized (proves `select(. > 0)` filters additions).
- `tests/scripts/fixtures/tfplan-web-platform-no-changes.json` — synthesized.
- `tests/scripts/fixtures/tfplan-web-platform-real-baseline.json` — captured, redacted (AC12).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --json number,title,body --limit 200 | jq -r --arg p "<path>" '.[] | select(.body // "" | contains($p)) | "#\(.number): \(.title)"'` run at plan-time across the four edited paths returned zero matches. The 77 open code-review issues are all on unrelated surfaces.

## Infrastructure (IaC)

No new infrastructure. This PR modifies two existing CI workflows that run against already-provisioned Terraform roots (`apps/web-platform/infra/sentry/` and `apps/web-platform/infra/`). No new Doppler secrets, no new providers, no new vendor accounts. The new `.jq` filter files are pure jq syntax — no runtime dependencies beyond `jq 1.8.x` already installed on `ubuntu-24.04` runners.

## Observability

```yaml
liveness_signal:
  what: apply-sentry-infra and apply-web-platform-infra workflows run on every push to main touching their respective infra paths
  cadence: per-merge (event-driven)
  alert_target: GitHub Actions UI; failed runs visible in the merge commit's status checks. scheduled-terraform-drift cron at 06:00 / 18:00 UTC is the 12h backstop for drift not caught by per-merge applies.
  configured_in: .github/workflows/apply-sentry-infra.yml, .github/workflows/apply-web-platform-infra.yml
error_reporting:
  destination: GitHub Actions logs (stderr via ::error:: annotations) + workflow-run failure status. sentry_cron_monitor.scheduled_terraform_drift fires if drift detector misses scheduled run.
  fail_loud: yes — destroy-guard step exits non-zero with ::error:: naming destroy_count, resource_deletes, nested_deletes per the two-counter shape inherited from apply-github-infra.yml.
failure_modes:
  - mode: destroy-guard mis-counts nested-block removal on a web-platform resource (the gap this fixes)
    detection: unit test test-destroy-guard-counter-web-platform.sh against synthesized + captured fixtures
    alert_route: CI failure on any PR touching the .jq file or the workflow (CODEOWNERS-gated)
  - mode: jq syntax error in either new filter
    detection: jq exits non-zero with parse error; bash `set -uo pipefail` + integer-validation gate fails the step
    alert_route: Actions log surfaces the jq error directly
  - mode: false positive on a legitimate ruleset rule reorder
    detection: rules-count delta is positive but semantically a reorder, not a removal. operator surfaces during apply.
    alert_route: operator adds `[ack-destroy]` to merge commit; no code change. Documented in Risks R1.
  - mode: filter scope too narrow (a sixth nested-block-bearing resource type lands in the apply allow-list)
    detection: operator surfaces during apply when the destroy goes silently through
    alert_route: file a new tracking issue to widen destroy-guard-filter-web-platform.jq — same extension model as #4419 widens #4420
  - mode: redaction in tfplan-web-platform-real-baseline.json fails to scrub a secret bytestring
    detection: AC12 grep sentinel + manual operator review pre-commit
    alert_route: redaction failure surfaces at the AC12 grep gate before commit; if it lands committed, GitHub push protection + gitleaks scan in CI rejects the push
logs:
  where: GitHub Actions workflow run logs (per-step)
  retention: 90 days (GitHub default)
discoverability_test:
  command: |
    cat tests/scripts/fixtures/tfplan-cf-ruleset-rule-removal.json | jq -f tests/scripts/lib/destroy-guard-filter-web-platform.jq
  expected_output: '{"resource_deletes":0,"nested_deletes":1}'
```

## Domain Review

**Domains relevant:** engineering (only)

### Engineering — assessed inline

**Status:** reviewed (inline; the #4420 plan already ran multi-agent plan-review on the structural pattern this PR inherits — path-specific filter, two-counter `{resource_deletes, nested_deletes}` output, value-arg `_count($side)` shape avoiding jq 1.7+ filter-arg crash class)
**Assessment:** CI/CD defense-layer fix. Path-specific per-workflow filters on a defined surface. No cross-domain implications. CPO sign-off requirement carries forward from the `single-user incident` threshold framed in #4420; review-time `user-impact-reviewer` will enumerate failure modes against the diff.

### Product/UX Gate

Not applicable. **Tier:** NONE. No user-facing surface modified.

## Test Scenarios

### Sentry filter (`test-destroy-guard-counter-sentry.sh`)

| # | Fixture                                  | `HEAD_MSG`                       | `resource_deletes` | `nested_deletes` | `destroy_count` | Expected exit |
| - | ---------------------------------------- | -------------------------------- | ------------------ | ---------------- | --------------- | ------------- |
| 1 | tfplan-sentry-resource-delete.json       | (no ack)                         | 1                  | 0                | 1               | 1 (gate trips)|
| 2 | tfplan-sentry-no-changes.json            | (no ack)                         | 0                  | 0                | 0               | 0             |
| 3 | tfplan-sentry-resource-delete.json       | `feat: x\n\n[ack-destroy]\n`     | 1                  | 0                | 1               | 0 (ack)       |
| 4 | tfplan-sentry-real-baseline.json         | (empty)                          | 0                  | 0                | 0               | 0 (anchor)    |
| 5 | tfplan-sentry-resource-delete.json       | `chore: discuss [ack-destroy] policy inline` | 1      | 0                | 1               | 1 (substring NOT line-anchored) |

### Web-platform filter (`test-destroy-guard-counter-web-platform.sh`)

| # | Fixture                                            | `HEAD_MSG`                       | `resource_deletes` | `nested_deletes` | `destroy_count` | Expected exit |
| - | -------------------------------------------------- | -------------------------------- | ------------------ | ---------------- | --------------- | ------------- |
| 1 | tfplan-cf-ruleset-rule-removal.json                | (no ack)                         | 0                  | 1                | 1               | 1             |
| 2 | tfplan-cf-tunnel-ingress-removal.json              | (no ack)                         | 0                  | 1                | 1               | 1             |
| 3 | tfplan-cf-zone-settings-header-removal.json        | (no ack)                         | 0                  | 1                | 1               | 1             |
| 4 | tfplan-cf-notification-integration-removal.json    | (no ack)                         | 0                  | 1                | 1               | 1             |
| 5 | tfplan-cf-access-policy-include-removal.json       | (no ack)                         | 0                  | 1                | 1               | 1             |
| 6 | tfplan-web-platform-no-changes.json                | (no ack)                         | 0                  | 0                | 0               | 0             |
| 7 | tfplan-cf-ruleset-resource-delete.json             | (no ack)                         | 1                  | 0                | 1               | 1 (no double-count) |
| 8 | tfplan-web-platform-mixed.json                     | (no ack)                         | 1                  | 1                | 2               | 1             |
| 9 | tfplan-cf-ruleset-rule-addition.json               | (no ack)                         | 0                  | 0                | 0               | 0 (additions ignored) |
| 10| tfplan-web-platform-real-baseline.json             | (empty)                          | 0                  | 0                | 0               | 0 (anchor)    |
| 11| tfplan-cf-ruleset-rule-removal.json                | `feat: x\n\n[ack-destroy]\n`     | 0                  | 1                | 1               | 0 (ack)       |
| 12| tfplan-cf-ruleset-rule-removal.json                | `chore: discuss [ack-destroy] policy inline` | 0      | 1                | 1               | 1 (substring NOT line-anchored) |

## Risks

- **R1 — False positive on ruleset rule reorder.** If a future PR reorders `cloudflare_ruleset.seo_page_redirects.rules[]` (e.g., moves Rule 5 below Rule 6 for precedence), Terraform's JSON plan reports it as `before.rules` length=13, `after.rules` length=13 (same length, different content). The filter's `(before_count - after_count)` is 0, so the gate does NOT trip — correct behavior. However, if a PR removes one rule AND adds two (net +1, but one real removal), the filter computes `13 - 14 = -1`, dropped by `select(. > 0)`. **The known-broken case (one real removal, no addition) IS caught.** A clever attacker could mask removal-with-replacement, but the merge commit's CODEOWNERS-gated review on `apps/web-platform/infra/*.tf` is the load-bearing defense — destroy-guard is the second-line. Documented as a known limitation in destroy-guard-filter-web-platform.jq's comment block.
- **R2 — Provider version churn changes the JSON path.** The Cloudflare provider's `cloudflare_ruleset` schema has been stable since v4.x (rules{} repeated block). A hypothetical v5 rename to `policies[]` would silently zero out the filter's `nested_deletes`. **Mitigation:** the `tfplan-web-platform-real-baseline.json` fixture (AC12) is a regression anchor — a provider upgrade that changes the path will surface either (a) directly via the test failing when the captured plan no longer parses to the expected counts, or (b) more likely the workflow itself failing on the upgrade PR before any guard logic runs. Same R2 posture as PR #4420.
- **R3 — `terraform show -json` schema stability.** `change.before` / `change.after` are documented contracts. Low risk; if Terraform breaks this contract, the entire IaC ecosystem breaks with it.
- **R4 — Squash-merge `[ack-destroy]` placement.** Inherits the existing posture documented in PR #4420 R4. The byte-identical `(^|$'\n')\[ack-destroy\]($|$'\n')` regex matches whether the token lands in the PR title or body, as long as the squash-merge commit message contains the line-anchored token.
- **R5 — Real fixture redaction completeness.** The web-platform plan JSON carries more sensitive bytes than the github plan JSON (Doppler service tokens, TLS private keys, random_id seeds, ~12 TF_VAR_* inputs from Doppler). **Mitigation:** the `del(.variables)` expression catches all TF_VAR_*-sourced inputs; additional `del()` on `.. | .secret_b64?` (random_id) and `.. | .private_key_pem?` (tls) covers the resource-attribute path. AC12 enforces the sentinel grep gate. Operator review pre-commit is mandatory. If a future provider adds a new sensitive attribute name, the AC12 sentinel regex needs an extension — the regex is permissive on common shapes (`sk_`, `ghp_`, etc.) and conservative on novel ones; a learning entry should capture any new redaction extension at /work time.
- **R6 — Filter contract drift between the three .jq files.** Three filter files, three workflows, three test files. A future PR that changes one file's output schema (e.g., adds a third counter `comment_deletes`) MUST update both the workflow's inline shell consumer AND the test's `_run_gate` parser AND the matching sibling filter files for consistency. **Mitigation:** all three filter paths live under the CODEOWNERS umbrella; the contract-drift class is a known plan-time concern documented in Sharp Edges below.

## Sharp Edges

- **Single-block-shrinkage is the same gap as array-shrinkage.** Three of the five web-platform resource types — `cloudflare_zone_settings_override.settings[0].security_header`, `cloudflare_notification_policy.email_integration`, `cloudflare_zero_trust_access_policy.include` — have `MaxItems: 1` semantics in the Cloudflare provider schema, but Terraform's JSON plan encodes them as arrays. Removing the single block produces `before: [{...}]`, `after: []` — length delta 1, caught by the same `_count` helpers. NO special-casing is needed in the filter; the survey confirmed each is array-shaped in the JSON output. Documented inline in the filter's header comment so a reviewer doesn't try to "simplify" the helpers into singleton-field shapes.
- **`apply-sentry-infra` filter has `nested_deletes: 0` literal — intentional, NOT a bug.** A reviewer scanning the new file may assume the filter is incomplete. The comment block must explicitly say "current scope has zero array-of-blocks; this is a documented extension point, not a TODO". The choice to wire the filter at all (vs. leaving the workflow's single-line resource-only counter as-is) is for *consistency* — when a future Sentry resource type lands with nested blocks, there is ONE obvious place to extend, and the workflow + test wiring already exists.
- **Plan v2 `Acceptance Criteria → Post-merge → AC10` was the source of this issue.** PR #4420 explicitly carved this out as `gh issue create --title "chore: extend destroy-guard widening to apply-sentry-infra and apply-web-platform-infra"`. The original Plan v2 (`knowledge-base/project/plans/2026-05-25-fix-destroy-guard-nested-block-removal-plan.md`) is the authoritative reference for the design constraints (path-specific, NO recursion, byte-identical `[ack-destroy]` regex).
- **Cap-coupling now closed across the apply-* trio.** After this PR merges, all three production-write apply workflows (apply-github-infra, apply-sentry-infra, apply-web-platform-infra) consume their per-workflow `.jq` filter from `tests/scripts/lib/destroy-guard-filter*.jq`. A future apply-* workflow (e.g., apply-cloudflare-zone-pages.yml or a new vendor IaC root) MUST follow the same pattern: dedicated `destroy-guard-filter-<workflow>.jq`, dedicated `test-destroy-guard-counter-<workflow>.sh`, CODEOWNERS rows. Document this convention in the file headers.
- **The ACME carve-out is the highest-impact single-rule removal.** `cloudflare_ruleset.seo_page_redirects.rules[10]` carries the `(not ssl) and not (... acme-challenge ...)` expression that lets Let's Encrypt HTTP-01 challenges through the always-HTTPS redirect. Silently removing it = next ~60-day cert renewal fails = `https://soleur.ai/` 502s for every user until operator regenerates the cert. The `sentry_uptime_monitor.soleur_acme_probe` is the alerting half but fires AT renewal time, not at the silent un-requiring commit. This filter is the prevention half.

## Non-Goals

- **Generalizing the filter pattern across vendors.** The five vulnerable types in `destroy-guard-filter-web-platform.jq` are all Cloudflare. A future Hetzner / Inngest / Better Stack resource with nested-block exposure would extend this file with a new clause; no generalization to a `(resource_type, nested_path)` registry. Lesson carried from #4420: "no premature generalization".
- **Modifying the `[ack-destroy]` regex or gate semantics.** Byte-identical across all three apply-* workflows. Any future PR that touches the regex must update all three files in lockstep — CODEOWNERS protection is the enforcement gate.
- **Extending CODEOWNERS scope beyond the new filter / test paths.** The existing fixtures glob at line 81 (`/tests/scripts/fixtures/tfplan-*.json`) already covers new fixtures; no glob edit needed.
- **Surveying resources NOT currently in either workflow's apply allow-list.** `sentry_issue_alert.*`, `sentry_uptime_monitor.*`, `hcloud_server`, `hcloud_volume`, `hcloud_ssh_key`, `terraform_data.*` SSH-provisioned resources are all out-of-scope because they are import-only or operator-locally-applied or excluded from the per-merge auto-apply.
- **Closing #4392.** AC20 already closed by #4420; AC19/AC21 are unrelated to this PR.

## References

- **#4419** — this issue (closes)
- **#4420** — closed yesterday; established the path-specific filter pattern this PR extends to siblings. Authoritative reference for jq design (no recursion, value-arg `_count($side)`, `select(.. | not)` to prevent double-counting).
- **#3915** — closed by #4420; root cause issue for the destroy-guard gap class.
- **#4392** — AC20 tracking; AC20 closed by #4420.
- **#4395** — surfaced the `required_check` removal gap empirically.
- **#3976** / **PR-β / 2026-05-18 cert outage post-mortem** — the user-facing failure mode that a `cloudflare_ruleset.seo_page_redirects.rules[10]` ACME-carve-out removal would silently re-fire.
- **`knowledge-base/project/plans/2026-05-25-fix-destroy-guard-nested-block-removal-plan.md`** — #4420's plan; design constraints carried forward.
- **`tests/scripts/lib/destroy-guard-filter.jq`** — github filter (reference shape, unchanged by this PR).
- **`tests/scripts/test-destroy-guard-counter.sh`** — github test (reference shape, unchanged by this PR).
- **`.github/workflows/apply-github-infra.yml:244-265`** — post-#4420 wiring (reference for the workflow-side shell shape).
- **`.github/CODEOWNERS:74-81`** — existing CODEOWNERS rows for the github-infra side (reference for new sibling rows).
- **`apps/web-platform/infra/seo-rulesets.tf:240-254`** — the ACME carve-out rule (the highest-impact single-removal target).
- **`apps/web-platform/infra/sentry/cron-monitors.tf:48-62`** — `sentry_cron_monitor` resource shape proving no array-of-blocks today.
- **`apps/web-platform/infra/tunnel.tf:26-49`** — `cloudflare_zero_trust_tunnel_cloudflared_config` with repeated `ingress_rule {}` blocks.
- **Terraform JSON output format** — https://developer.hashicorp.com/terraform/internals/json-format#change-representation
- **`2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`** — canonical Doppler `terraform plan` invocation triplet for the web-platform fixture-capture command.
- **`hr-tfplan-fixture-redaction-mandatory`** (referenced by `test-destroy-guard-counter.sh:21`) — fixture redaction posture.
