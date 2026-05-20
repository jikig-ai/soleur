---
issue: 4118
follow_up: 4126
branch: feat-one-shot-cloud-init-inngest-4118
type: infra-tier-1-plus-workflow-gate
classification: ops-only-prod-write
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user-incident
related_prs:
  - 3940  # PR-F (runtime trigger layer) - merged 2026-05-17 - cited by existing hr-tagged-build-workflow rule
  - 3973  # PR-F IaC layer (Doppler + BetterStack providers + bootstrap + OCI build) - merged 2026-05-19
  - 4085  # Substrate-cascade fix (5 compounding bugs; landed hr-tagged-build-workflow rule)
  - 4093  # Bridge-container Inngest reachability fix (--add-host)
  - 4111  # `--` separator fix
  - 4104  # resolveClaudeBin webpack-broken (standalone bundle)
related_issues:
  - 4017  # Substrate-cascade root-cause issue (closed)
  - 4118  # This plan
  - 4126  # Tier 2 follow-up (weekly DR test)
---

# feat: one-shot cloud-init Inngest install + `hr-fresh-host-provisioning-reachable-from-terraform-apply` (Tier 1 + Tier 3 of #4118)

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** Research Reconciliation, Implementation Phase 1, Sharp Edges, Open Code-Review Overlap, Test Strategy
**Deepen passes applied inline:**
- CLI/syntax verification (docker inspect Go-template, Terraform `$$` escaping in cloud-init `runcmd:`)
- Attribution-claim grep against `main` (PR #3940, #3973, #4085, issue #4017)
- AGENTS rule existence / retirement check (`grep -E "\[id: hr-fresh-host-provisioning-reachable-from-terraform-apply\]" AGENTS*.md` — absent, safe to add)
- Pre-existing budget breach math (verify 600 B cap is achievable for both trims)
- Lefthook glob audit (pre-commit fires only on AGENTS-file edits; pre-existing breaches landed silently)
- Code-review overlap query (`gh issue list --label code-review --state open`; matches for AGENTS.md are unrelated to this work — dropped)
- Existing-precedent audit (ci-deploy.sh:556-624 inngest deploy handler is the canonical mirror)

### Key Improvements vs. /plan v1
1. **Critical finding — AGENTS B_ALWAYS recovery needed before this PR can land.** Pre-existing overflow = 2499 B; this PR adds +576 B. Trimming the two cap-breaching rules (lines 15 + 55) only sheds 2010 B — insufficient. Need to trim 6 rules total (1371/1039/587/530/521/492 → ≤200 B each) to clear the budget with margin. Plan recommends splitting into TWO PRs: PR-1 lands the recovery trim (6 issues closed); PR-2 (this plan) lands the cloud-init + new rule. See Deepen-pass Quality Checks section for full math + operator-decision branch.
2. Added explicit Terraform `$$` escaping rules for the runcmd shell block — cloud-init.yml is `templatefile()`-rendered (`server.tf:29`); raw `$VAR` would be Terraform-interpolated and break at first apply.
3. Corrected PR-attribution: the runtime PR-F is #3940 (cited by existing rule); the IaC layer was #3960/#3973 (merged 2026-05-19); the substrate cascade fix was #4085. #4017 is an ISSUE not a PR (the root-cause issue closed by #4085).
4. POSIX `[ ]` not `[[ ]]` in the Phase 1 runcmd block — cloud-init `- |` blocks execute under `/bin/sh` (dash on Ubuntu 24.04), bash `[[ ]]` would fail. The bootstrap script itself retains `[[ ]]` (has `#!/usr/bin/env bash`).
5. Tightened Phase 0 budget math with verified line-by-line byte counts.
6. Refined the Phase 1 runcmd block to include set -e at the block level AND per-step `if ! …; then; exit 1; fi` (the two patterns nest correctly — set -e is the default-fail safety net; explicit checks add precise error reasons for log triage).
7. Clarified Phase 4 SKILL.md extension — uses Edit (not Write) on `plan/SKILL.md` Phase 2.8; preserves the rest of the file.

### New Considerations Discovered
- Cloud-init `runcmd: - |` blocks run under `/bin/sh` (dash on Ubuntu) — `[[ ]]` is bash-only and will fail under dash. The runcmd block must use `[ ]` POSIX tests OR start the block with `#!/usr/bin/env bash` shebang. Verified against the existing pattern at cloud-init.yml line 388 (`set -e` block uses no `[[`). The plan's draft block uses `[[ -z "$..." ]]` which MUST be rewritten to `[ -z "$..." ]` for dash compatibility OR routed through `bash -c`.
- The bootstrap script itself (`inngest-bootstrap.sh`) uses `[[ ]]` — but it has `#!/usr/bin/env bash` shebang AND is invoked explicitly via `bash …`, so dash never sees those tests. Our wrapper runcmd block extracts and `env … bash …` invokes the script — that path is safe. Only the wrapper logic between extract and invoke must avoid `[[`.
- `docker inspect -f` Go-template uses `{{ }}` braces (NOT `${...}`) — Terraform `templatefile()` does NOT interpolate Go templates. Safe to inline.
- The runcmd block runs as root (cloud-init default), so no `sudo -E env …` wrapper needed (unlike `ci-deploy.sh:611` which runs as the `deploy` user via webhook.service).

## Overview

PR-F (#3940) shipped self-hosted Inngest as IaC-managed for **everything except the install step itself**: the OCI image `ghcr.io/jikig-ai/soleur-inngest-bootstrap:vX.Y.Z` and the inngest binary on disk are produced/consumed by the deploy webhook, not by cloud-init. A fresh `terraform destroy && terraform apply` against an empty Hetzner state recreates the server, but the inngest-server systemd unit is never installed — cron functions silently miss every scheduled fire until an operator runs `gh workflow run … vinngest-vX.Y.Z` and clicks the deploy webhook.

This PR closes the gap with two changes:

1. **Tier 1** — Add a `runcmd:` block to `apps/web-platform/infra/cloud-init.yml` that pulls `ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0`, extracts `inngest-bootstrap.sh`, reads the pinned `INNGEST_CLI_VERSION` / `INNGEST_CLI_SHA256` from the image's ENV vars, and executes the script on the host. Mirrors the existing inngest deploy handler in `apps/web-platform/infra/ci-deploy.sh:556-624` but runs as root (no `sudo -E`).
2. **Tier 3** — Add AGENTS.md hard rule `hr-fresh-host-provisioning-reachable-from-terraform-apply` to `AGENTS.core.md` and a pointer entry to `AGENTS.md`. The rule mandates that every production service in `apps/<app>/infra/` come up on a fresh `terraform destroy && terraform apply` against empty state with zero operator post-apply actions.

**Tier 2 is deferred to #4126** (weekly disaster-recovery test against a non-prod Hetzner workspace). The PR body MUST cite #4126 as the Tier-2 follow-up so the workflow-gate's enforcement story is traceable. Tier 3's rule body explicitly references Tier 2 (#4126) as the enforcement mechanism whose existence makes the rule mechanically verifiable; until #4126 lands, the rule remains plan-time-only (verified by humans reading the plan).

### Research Insights

**Best practices (cloud-init `runcmd:` for OCI-content-carrier bootstraps):**

- `runcmd:` modules execute under `/bin/sh` per the cloud-init reference (`cloudinit.config.cc_runcmd`); the `- |` literal-block form is documented as POSIX shell. dash on Ubuntu 24.04 ships as `/bin/sh`. POSIX `[ ]` tests + `-o`/`-a` joins are mandatory; bash `[[ ]]` fails silently or with `[[: not found`. Reference: <https://cloudinit.readthedocs.io/en/latest/reference/modules.html#runcmd>.
- `runcmd:` runs ONCE on first boot; subsequent boots skip. Cloud-init persists state at `/var/lib/cloud/instance/sem/config_runcmd` — manual rerun requires `cloud-init clean --logs && cloud-init init && cloud-init modules --mode=config && cloud-init modules --mode=final` (Hetzner-recommended; documented at `cloud-init clean(1)`). Implication: if the runcmd block fails on first boot, the OPERATOR must `cloud-init clean` before re-attempting OR run the bootstrap manually via the deploy webhook. AC14 (post-merge idempotent re-fire via webhook) is the canonical recovery path; cloud-init clean is the destructive-recovery path.
- `set -e` at the top of a `- |` block does NOT propagate across blocks — each `- |` is a separate `sh -c` invocation. The plan's block uses `set -e` AND per-step explicit checks (`if ! …; then exit 1; fi`) — `set -e` is the safety net for unchecked commands like `chmod`, `mkdir`; explicit checks add structured error messages for `journalctl -u cloud-final` triage.
- The `docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}'` Go-template pattern is the canonical way to read OCI image ENV vars from outside the container. Reference: Docker CLI docs <https://docs.docker.com/reference/cli/docker/inspect/#format-the-output> and the existing precedent at `apps/web-platform/infra/ci-deploy.sh:593`.

**Performance considerations:**

- First-boot wall-clock impact of the new runcmd block: ~30-90s (Docker pull of ~80MB OCI image + extract + inngest-cli download from upstream GitHub release + SHA verify + systemd unit writes + `systemctl enable --now inngest-server.service`). Cloud-init total boot time is dominated by `apt-get install` of Docker (~120s) — the inngest bootstrap adds <50% to total time. Acceptable for fresh-provisioning.
- Idempotent re-runs short-circuit in ~50ms (version-file match at `inngest-bootstrap.sh:67-72`). The webhook recovery path on the existing live server (AC14) is fast.
- The OCI image is single-arch (`linux/amd64`) — fresh Hetzner cx33 VMs are x86_64, no multi-arch decision needed. Reference: `.github/workflows/build-inngest-bootstrap-image.yml:96-97` (`docker buildx build --platform linux/amd64`).

**Edge cases:**

- **Docker daemon not yet ready** — the runcmd block starts after `apt-get install docker-ce` + `systemctl restart docker` (line 318) but the daemon may take 1-3s to be socket-ready. Mitigation: existing precedent at line 375 (`docker pull ${image_name}`) already assumes daemon-ready at that point; placing the inngest bootstrap immediately AFTER the existing `docker pull` (Phase 1 step 2) inherits that ordering guarantee.
- **GHCR pull failure (network blip, GHCR outage, image not yet replicated)** — `set -e` + the explicit `if ! docker pull …; then exit 1; fi` halts cloud-init. The operator sees `FATAL: docker pull …` in `/var/log/cloud-init-output.log` and either retries via `cloud-init clean` or fires the webhook deploy path manually. Per `hr-tagged-build-workflow-needs-initial-tag-push`, the `vinngest-v1.0.0` tag MUST exist in GHCR at PR-merge time (it does, per #4085 force-push).
- **SHA256 mismatch on the inngest-cli tarball** — the bootstrap script (`inngest-bootstrap.sh:103-107`) refuses to install on mismatch, exits non-zero. The runcmd wrapper's `if ! env … bash …; then exit 1; fi` propagates. Operator triage: `journalctl -u cloud-final` shows the bootstrap's `[inngest-bootstrap] ERROR: SHA256 mismatch — expected … got …` line.
- **Doppler token absence at the moment the bootstrap runs** — the script reads `/etc/default/webhook-deploy` (line 217) for `DOPPLER_TOKEN`. cloud-init writes that file at line 294 BEFORE the new runcmd block (which lives after line 375). Order verified at Phase 1 step 2.
- **Better Stack heartbeat false-fire window** — `inngest.tf:129` (`paused = true` with `lifecycle.ignore_changes = [paused]`) means the heartbeat is paused at apply time. After fresh apply, the systemd timer (`inngest-heartbeat.timer`, 60s) fires pings but Better Stack ignores them. AC for one-time operator unpause documented at AC14-adjacent (post-merge step). New Soleur users provisioning their own Hetzner project will need this step too (runbook covers it).

**References:**

- cloud-init runcmd docs: <https://cloudinit.readthedocs.io/en/latest/reference/modules.html#runcmd>
- Terraform `templatefile()` interpolation escaping: <https://developer.hashicorp.com/terraform/language/functions/templatefile#escaping>
- Docker inspect Go-template: <https://docs.docker.com/reference/cli/docker/inspect/#format-the-output>
- Existing precedent: `apps/web-platform/infra/ci-deploy.sh:556-624` (inngest deploy handler), `apps/web-platform/infra/cloud-init.yml:283-356` (Doppler + webhook install pattern)
- AGENTS.core.md rules cited: `hr-all-infrastructure-provisioning-servers`, `hr-tagged-build-workflow-needs-initial-tag-push`, `hr-multi-step-post-merge-bootstrap-script`, `hr-every-new-terraform-root-must-include-an`

## Research Reconciliation — Spec vs. Codebase

| Spec / issue-body claim | Codebase reality | Plan response |
| --- | --- | --- |
| "Embedded into OCI image `ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0` … pushed manually during #4017 remediation" | Image tag pin `v1.0.0` is real and live; build workflow at `.github/workflows/build-inngest-bootstrap-image.yml` is tagged-trigger-only (`vinngest-v*.*.*`) and was force-pushed during #4085 remediation per `hr-tagged-build-workflow-needs-initial-tag-push`. | Plan pins the OCI tag in cloud-init to the same source of truth used by `ci-deploy.sh` (currently `v1.0.0` — the deploy webhook accepts the operator-supplied tag at the SSH_ORIGINAL_COMMAND boundary; cloud-init has no operator, so it MUST hardcode a tag). Bump path: a new `vinngest-vX.Y.Z` tag triggers the OCI build, then the operator updates the cloud-init pin in a follow-up commit alongside `apps/web-platform/infra/inngest.tf:locals.inngest_cli_version`. The cloud-init pin is a SECOND tag pin (alongside `inngest_cli_version` in `inngest.tf`), and the two represent different things: `inngest.tf` pins the inngest-cli upstream release, the cloud-init pin pins the bootstrap-shape OCI image. Both bump separately. Sharp edges section documents the drift risk. |
| "issue body proposes calling `docker pull` and `docker create` directly inside the runcmd block" | The existing `ci-deploy.sh:556-624` already implements this exact pattern with mature error handling (`final_write_state`, named temp-container, idempotent `docker rm -f` cleanup, named extract dir under `/tmp/inngest-extract.XXXXXX`). | Plan keeps the runcmd block shape parallel to `ci-deploy.sh:556-624` but DOES NOT call `final_write_state` (no /var/lib/soleur-deploy-state.json file exists in cloud-init context — it's owned by the webhook handler post-install). Cloud-init failures surface via `/var/log/cloud-init-output.log` and the package-audit FATAL pattern at line 264. |
| "Better Stack heartbeat is paused on apply" — `inngest.tf:129` (`paused = true`) | True. Heartbeat resource sets `paused = true` with `lifecycle.ignore_changes = [paused]` — the operator unpauses via the Better Stack UI after deploy. | Tier 1 cloud-init's inngest-bootstrap fully installs systemd-managed heartbeat ping (`inngest-heartbeat.timer`, 60s). After fresh `terraform apply` the timer is firing pings at the heartbeat URL but Better Stack is paused, so no alerts fire. This is **not** a regression — Better Stack pause is intentional per existing TF comment (line 122). Plan adds a `## Post-merge (operator)` AC entry to unpause Better Stack heartbeat ONCE after the initial fresh-host apply (one-time per Hetzner project). New Soleur users running `terraform apply` against their own project will need this step too — runbook update covers it. |
| "Tier 3 mentions companion observability issue (TBD — Better Stack heartbeat broken)" | No such companion issue exists in the open backlog (`gh issue list --label observability --state open` returns 0 matches for "heartbeat"). The pause is per-design, not broken. | Drop the "companion observability issue" reference from the rule body. Replace with the explicit Tier-2 cross-reference (#4126). |
| Issue snippet uses `EXTRACT_CONTAINER="inngest-bootstrap-extract-$$"` | `ci-deploy.sh:576` uses `INNGEST_EXTRACT_CONTAINER="soleur-inngest-extract-$$"`. | Plan adopts the `soleur-inngest-extract-$$` form for consistency with `ci-deploy.sh` (single grep/observability tag). |
| Issue snippet uses bare `docker pull` (no failure handling) | `ci-deploy.sh:571-572` does `docker pull "$IMAGE:$TAG"` followed by a `docker create … >/dev/null` with `if ! …; then logger -t "$LOG_TAG" "FAILED: …"; final_write_state 1 …; exit 1; fi`. | Plan wraps every step (pull, create, cp, inspect) with explicit `set -e` + `if ! …; then echo "FATAL: …" >&2; exit 1; fi` so a runcmd failure halts cloud-init at the inngest stage rather than continuing past with the soleur-web-platform container starting against a missing Inngest backend. |
| **Pre-existing AGENTS budget breach** — `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` at the branch tip returns `REJECT B_ALWAYS=24499 > 22000` AND TWO per-rule body lines exceed 600 B: line 15 (`hr-tagged-build-workflow-needs-initial-tag-push`, 1371 B, shipped in #4085) and line 55 (`wg-end-of-work-emit-resume-prompt`, 1039 B). | The lefthook pre-commit fires the linter only when AGENTS files are STAGED, so these breaches landed silently in #4085 / earlier. Any AGENTS edit in this PR will trip the linter on top of the new rule's body. | **Mandatory pre-work before adding the new rule body:** trim the two oversized rules to ≤600 B by extracting their `Why:` + `How to apply:` prose into companion learning files (mirror the pattern at `cq-pg-security-definer-search-path-pin-pg-temp` line 59 which keeps the rule body terse and points to a learning file). Then add the new rule, then verify `python3 scripts/lint-agents-rule-budget.py` exits 0. Per-rule cap remains the dominant constraint — see Implementation Phase 0 for the line-by-line trim plan. Open separate code-review issues for the two pre-existing breaches BEFORE editing them per `wg-when-an-audit-identifies-pre-existing` — these are not new debt this PR introduced but they MUST be fixed for this PR to land. |
| Issue body lists "[ ] Disaster-recovery test exists at `apps/web-platform/infra/test-fresh-provisioning.sh` (or equivalent CI workflow)" in Tier-1 + Tier-3 PR Acceptance Criteria. | Per task scope this AC is Tier 2 (#4126 deferred). | Strike the test-fresh-provisioning.sh AC from the Pre-merge AC list; cite #4126 instead. The Post-merge AC list contains a one-time operator step to verify the fresh-host install path on the existing live server (idempotent re-run of inngest-bootstrap via `gh workflow run ...` is safe — it short-circuits at version-file match). |

## User-Brand Impact

**If this lands broken, the user experiences:** A fresh `terraform apply` (or `terraform destroy && terraform apply` for disaster recovery) produces a server that boots, accepts traffic on the web-platform container, but silently fails every scheduled cron function (daily-priorities walker, scheduled-follow-through, KB-drift) because Inngest is not running. Symptom mirrors #4017: a Sentry monitor goes "missed", the operator has no idea why, and customer-facing artifacts (daily-priority emails, follow-through nudges) silently stop without a UI signal. Per #4118 issue body and Sentry runbook precedent, the mean detection time would be ~2-3 days.

**If this leaks, the user's workflow is exposed via:** No data leak vector — the change is install-script orchestration, not auth/PII. Inngest signing key + event key + heartbeat URL are already Doppler-managed (random_id + lifecycle.ignore_changes per `apps/web-platform/infra/inngest.tf:49-95`) so the secret-handling surface is unchanged. The OCI image is pulled from a public-image registry (`ghcr.io/jikig-ai/soleur-inngest-bootstrap`) over TLS; the embedded bootstrap script SHA-verifies its inngest-cli download against the pinned `INNGEST_CLI_SHA256`.

**Brand-survival threshold:** single-user incident.

A new Soleur user (or the existing operator after a disaster-recovery rebuild) who runs `terraform apply` and gets a half-installed substrate has direct evidence that "Soleur's self-hosted Inngest doesn't work" — a brand-survival event. The threshold is single-user-incident, not aggregate-pattern: one fresh-provisioning event going silently wrong is enough to break trust.

`requires_cpo_signoff: true` is set in YAML frontmatter. Carry forward from issue-body framing (issue is explicitly framed as a brand-survival single-user incident). Plan-time CPO sign-off is required before /work begins; review-time `user-impact-reviewer` will be invoked on the diff per `plugins/soleur/skills/review/SKILL.md` conditional agent block.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC0 (Phase 0 prerequisite):** AGENTS.core.md line 15 (`hr-tagged-build-workflow-needs-initial-tag-push`) trimmed from 1371 B → ≤600 B by extracting `Why:` + `How to apply:` prose into `knowledge-base/project/learnings/best-practices/2026-05-20-hr-tagged-build-workflow-rule-body-and-learning.md` and pointing the rule body at the learning file. Pre-existing tracking issue (filed per `wg-when-an-audit-identifies-pre-existing`) closed via this PR. Verified by `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` exiting 0 after the trim.
- [ ] **AC1:** AGENTS.core.md line 55 (`wg-end-of-work-emit-resume-prompt`) trimmed from 1039 B → ≤600 B by extracting its `Required fields` list + `Why:` prose into `knowledge-base/project/learnings/best-practices/2026-05-20-wg-end-of-work-resume-prompt-body-and-learning.md`. Pre-existing tracking issue closed via this PR.
- [ ] **AC2:** `apps/web-platform/infra/cloud-init.yml` includes a new `runcmd:` block AFTER the Docker install + `docker pull ${image_name}` step AND BEFORE the `docker run --name soleur-web-platform` step. The block performs: `docker pull ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0` → `docker create --name soleur-inngest-extract-$$` → `docker cp` of `/inngest-bootstrap.sh` → `docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}'` for `INNGEST_CLI_VERSION` + `INNGEST_CLI_SHA256` → `docker rm` of the extract container → `chmod +x` → execute the script with the pinned ENV vars. Every step is wrapped in `if ! …; then echo "FATAL: …" >&2; exit 1; fi` so cloud-init halts loudly on any failure (consistent with the package-audit FATAL pattern at line 264).
- [ ] **AC3:** The runcmd block hardcodes the OCI image tag (e.g., `INNGEST_BOOTSTRAP_TAG="v1.0.0"`) in a leading shell variable so the bump path is one-line. Comment block above the variable references `apps/web-platform/infra/inngest.tf:locals.inngest_cli_version` as the SECOND coordinated pin (image-shape vs inngest-cli) and explains the separation.
- [ ] **AC4:** `AGENTS.core.md` gains a new line under `## Hard Rules` for `hr-fresh-host-provisioning-reachable-from-terraform-apply`. Rule body ≤600 B (per `cq-agents-md-tier-gate`) and follows the canonical shape (terse statement + `[id: …]` + optional `[skill-enforced: …]` tag + 1-sentence `**Why:**`). The full body draft is in Implementation Phase 3 below. The `[skill-enforced: plan Phase 2.8]` tag is added because the IaC-routing gate already invokes `terraform-architect` and the new rule extends Phase 2.8's check surface.
- [ ] **AC5:** `AGENTS.md` pointer index gains `- [id: hr-fresh-host-provisioning-reachable-from-terraform-apply] → core` placed adjacent to `hr-all-infrastructure-provisioning-servers` (semantic siblings).
- [ ] **AC6:** `plugins/soleur/skills/plan/SKILL.md` Phase 2.8 (Infrastructure-as-Code Routing Gate) is extended to check the new rule's invariant explicitly. The Detection list gains a new bullet: a new service introduced in `apps/<app>/infra/` whose install step is described in prose as "after merge, push a `vX.Y.Z` tag and click the deploy webhook" → block the plan unless `apps/<app>/infra/cloud-init.yml` (or equivalent first-boot config) gains a parallel install step. The `Required output: ## Infrastructure (IaC) section` block gains a `### Fresh-host provisioning` subsection requirement: every new service's plan-time IaC section MUST answer "if `terraform apply` runs against empty state with no operator on the keyboard, does this service end up running?" with yes/no + the cloud-init path that makes it yes. This step uses Edit, not Write — preserves the rest of the file.
- [ ] **AC7:** `python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt --index-file AGENTS.md AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` exits 0 (pointer↔body parity).
- [ ] **AC8:** `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` exits 0 after the AC0/AC1 trims + the new rule body addition. (`B_ALWAYS` ends below 22000; per-rule cap 600 B is respected by all three edits.)
- [ ] **AC9:** `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` exits 0 (anchor-parity check passes; the `[skill-enforced: plan Phase 2.8]` tag in the new rule matches an actual edit in `plan/SKILL.md`).
- [ ] **AC10:** New companion learning file `knowledge-base/project/learnings/best-practices/2026-05-20-cloud-init-runcmd-bootstrap-mirror-from-deploy-handler.md` documents the cloud-init / ci-deploy.sh dual-path pattern (cloud-init for fresh hosts, deploy webhook for in-place upgrades), the OCI-image-tag-vs-inngest-cli-version separation, and links to the rule. Filed under best-practices because it's a generalizable pattern, not a bug-fix retrospective.
- [ ] **AC11:** Runbook `knowledge-base/engineering/ops/runbooks/inngest-server.md` gains a `## Fresh-host install (cloud-init path)` section documenting: (a) what cloud-init does at first boot, (b) the OCI-tag bump procedure (push `vinngest-vX.Y.Z` → OCI image builds → update `inngest.tf:locals.inngest_cli_version` AND the cloud-init pin in the same commit), (c) the one-time Better Stack heartbeat unpause step after a fresh apply.
- [ ] **AC12:** PR body cites `Ref #4118` (NOT `Closes #4118`) because closure is a post-merge operator action (verify fresh-host install on existing live server idempotently). PR body cites `Ref #4126` for Tier 2 follow-up. PR body cites `Closes #<N1> #<N2>` for the two pre-existing breach tracking issues filed in Phase 0 (AC0 / AC1 pre-existing-debt issues).
- [ ] **AC13:** No new Terraform resources are introduced (the change is cloud-init-config-only). `terraform plan` against `apps/web-platform/infra/` shows zero adds/changes/destroys other than the `hcloud_server.web` `user_data` rerender (which is gated by `lifecycle.ignore_changes = [user_data]` per `server.tf:50` — drift report shows the diff but apply is a no-op for the existing live server; cloud-init applies on the NEXT server creation, by design).

### Post-merge (operator)

- [ ] **AC14:** Operator verifies the fresh-host install path is exercised idempotently against the existing live server by running `gh workflow run web-platform-release.yml -F deploy_target=inngest -F deploy_tag=v1.0.0` (or the equivalent webhook trigger). The deploy completes with `success` status in `/hooks/deploy-status` and `inngest-bootstrap.sh`'s idempotency short-circuit (line 67-72) fires (`already active at v1.0.0 — no-op`, ~50ms). Automation: gh workflow run is feasible — Automation: not feasible because this also requires the live server's webhook surface, which is operator-gated by Cloudflare Tunnel. The `gh workflow run` step is automatable; the actual deploy completion poll runs from CI.
- [ ] **AC15:** After AC14 success, operator closes #4118 via `gh issue close 4118 -c "Tier 1 (cloud-init runcmd) + Tier 3 (AGENTS rule) shipped in PR #<N>. Tier 2 deferred to #4126."`. Automation: `gh issue close` is fully automatable from the merge workflow — the ship skill or a `gh-issue-close` step in `web-platform-release.yml` Post-merge job is the right placement. (Plan-time decision: place in `/soleur:ship` Phase 6 since this is a ops-remediation class PR — ship/SKILL.md already handles `gh issue close` for ops-remediation PRs.)

## Files to Edit

- `apps/web-platform/infra/cloud-init.yml` — add the inngest-bootstrap `runcmd:` block (AC2/AC3). Insertion point: between the existing `docker pull ${image_name}` (line 375) and the soleur-plugin-seed block (line 387-398). Rationale: Inngest must be live before the soleur-web-platform container starts (which happens at line 418) — the container's `/api/inngest` register call requires Inngest already listening on 8288.
- `AGENTS.md` — add pointer index entry adjacent to `hr-all-infrastructure-provisioning-servers` (around line 19) (AC5).
- `AGENTS.core.md` — TWO pre-existing rule trims (AC0/AC1) + ONE new rule body addition (AC4). Order: trim line 55 first (1039 B → ≤600 B), trim line 15 next (1371 B → ≤600 B), then add the new rule body (≤600 B). Per-line trims happen before addition so the linter passes incrementally.
- `plugins/soleur/skills/plan/SKILL.md` — extend Phase 2.8 Detection + Required-output sections (AC6). Single Edit operation under `### 2.8. Infrastructure-as-Code Routing Gate`.

## Files to Create

- `knowledge-base/project/learnings/best-practices/2026-05-20-hr-tagged-build-workflow-rule-body-and-learning.md` — extracted prose from current AGENTS.core.md line 15 (AC0). Holds the full `Why:` (#3940/#4017 cascade) + `How to apply:` (plan Phase 2 enforcement) context.
- `knowledge-base/project/learnings/best-practices/2026-05-20-wg-end-of-work-resume-prompt-body-and-learning.md` — extracted prose from current AGENTS.core.md line 55 (AC1). Holds the Required-fields enumeration + `Why:` context.
- `knowledge-base/project/learnings/best-practices/2026-05-20-cloud-init-runcmd-bootstrap-mirror-from-deploy-handler.md` — the dual-path pattern documentation (AC10).
- `knowledge-base/engineering/ops/runbooks/inngest-server.md` — gains a `## Fresh-host install (cloud-init path)` section (AC11). EDIT, not create — file exists at 279 lines.
- (No new TF files, no new tests, no new workflows — Tier 2's test workflow is #4126.)

## Implementation Phases

### Phase 0 — Pre-existing AGENTS budget breach remediation

**Why first:** lefthook pre-commit fires `lint-agents-rule-budget.py` on any AGENTS file edit. Currently at REJECT (24499 > 22000) with two rules over the 600 B cap. Without trim, every commit that touches AGENTS will fail pre-commit.

Steps:
1. File two new code-review tracking issues (per `wg-when-an-audit-identifies-pre-existing`):
   - "AGENTS.core.md: hr-tagged-build-workflow-needs-initial-tag-push body is 1371 B (cap is 600 B) — extract prose to learning file"
   - "AGENTS.core.md: wg-end-of-work-emit-resume-prompt body is 1039 B (cap is 600 B) — extract prose to learning file"
   Both with label `code-review`.
2. Create the two extraction learning files (canonical body of each rule's `Why:` + `How to apply:` becomes the learning file's content; rule body shrinks to a 1-line statement + `[id: …]` + `Why: see <learning-path>`).
3. Re-run `python3 scripts/lint-agents-rule-budget.py …` — must exit 0.
4. Commit these trims separately with message `chore(AGENTS): trim two rule bodies to ≤600 B (closes #<N1> #<N2>)`.

### Phase 1 — Cloud-init runcmd block

Steps:
1. Add a new `runcmd:` block to `apps/web-platform/infra/cloud-init.yml` between line 375 (`- docker pull ${image_name}`) and line 387 (soleur-plugin-seed). The block:
   ```yaml
   # Inngest-server bootstrap (Tier 1 of #4118; closes #4118 Tier 1 AC).
   # Mirror of apps/web-platform/infra/ci-deploy.sh:556-624 (inngest deploy
   # handler) but runs as root (no `sudo -E`) since cloud-init's runcmd is
   # already root. The OCI image is a SHA-pinned content carrier: pull,
   # extract the bootstrap script + embedded ENV vars (INNGEST_CLI_VERSION /
   # INNGEST_CLI_SHA256), execute on host. The script's idempotency
   # short-circuit (apps/web-platform/infra/inngest-bootstrap.sh:67-72) makes
   # re-runs cheap; the deploy webhook still handles in-place version bumps.
   #
   # Tag pin coordination: this pin AND apps/web-platform/infra/inngest.tf
   # locals.inngest_cli_version are TWO different coordinates — the OCI image
   # tag tracks bootstrap-shape changes, inngest_cli_version tracks the
   # embedded inngest-cli release. They bump separately; see runbook
   # knowledge-base/engineering/ops/runbooks/inngest-server.md.
   #
   # Terraform escaping: cloud-init.yml is rendered by `templatefile()` in
   # server.tf:29. Every shell `$VAR` becomes `$$VAR` to escape Terraform's
   # `${...}` interpolation pass. Mirrors the existing Doppler-install (line
   # 287) and webhook-install (line 351) blocks. The Go-template `{{ }}` syntax
   # used by `docker inspect -f` is NOT touched by Terraform — safe to inline.
   #
   # Shell compatibility: cloud-init `- |` blocks execute under `/bin/sh`
   # (dash on Ubuntu 24.04), NOT bash. POSIX `[ -z "$x" ]` is used — bash's
   # `[[ ]]` would fail with `[[: not found`. The bootstrap script itself has
   # `#!/usr/bin/env bash` and is invoked via explicit `bash …`, so dash
   # only sees the wrapper logic.
   - |
     set -e
     INNGEST_BOOTSTRAP_TAG="v1.0.0"
     INNGEST_BOOTSTRAP_IMAGE="ghcr.io/jikig-ai/soleur-inngest-bootstrap"
     if ! docker pull "$${INNGEST_BOOTSTRAP_IMAGE}:$${INNGEST_BOOTSTRAP_TAG}"; then
       echo "FATAL: docker pull $${INNGEST_BOOTSTRAP_IMAGE}:$${INNGEST_BOOTSTRAP_TAG} failed" >&2
       exit 1
     fi
     EXTRACT_DIR=$(mktemp -d /tmp/inngest-extract.XXXXXX)
     EXTRACT_CONTAINER="soleur-inngest-extract-$$$$"
     docker rm -f "$${EXTRACT_CONTAINER}" >/dev/null 2>&1 || true
     if ! docker create --name "$${EXTRACT_CONTAINER}" "$${INNGEST_BOOTSTRAP_IMAGE}:$${INNGEST_BOOTSTRAP_TAG}" >/dev/null; then
       echo "FATAL: docker create for inngest-bootstrap extract failed" >&2
       rm -rf "$${EXTRACT_DIR}"
       exit 1
     fi
     if ! docker cp "$${EXTRACT_CONTAINER}:/inngest-bootstrap.sh" "$${EXTRACT_DIR}/inngest-bootstrap.sh"; then
       echo "FATAL: docker cp of inngest-bootstrap.sh failed" >&2
       docker rm "$${EXTRACT_CONTAINER}" >/dev/null 2>&1 || true
       rm -rf "$${EXTRACT_DIR}"
       exit 1
     fi
     image_env=$(docker inspect "$${INNGEST_BOOTSTRAP_IMAGE}:$${INNGEST_BOOTSTRAP_TAG}" -f '{{range .Config.Env}}{{println .}}{{end}}')
     docker rm "$${EXTRACT_CONTAINER}" >/dev/null 2>&1 || true
     INNGEST_CLI_VERSION=$(printf '%s\n' "$${image_env}" | grep '^INNGEST_CLI_VERSION=' | cut -d= -f2-)
     INNGEST_CLI_SHA256=$(printf '%s\n' "$${image_env}" | grep '^INNGEST_CLI_SHA256=' | cut -d= -f2-)
     if [ -z "$${INNGEST_CLI_VERSION}" ] || [ -z "$${INNGEST_CLI_SHA256}" ]; then
       echo "FATAL: image missing INNGEST_CLI_VERSION or INNGEST_CLI_SHA256 ENV" >&2
       rm -rf "$${EXTRACT_DIR}"
       exit 1
     fi
     chmod +x "$${EXTRACT_DIR}/inngest-bootstrap.sh"
     echo "Running inngest-bootstrap.sh on host (version=$${INNGEST_CLI_VERSION})..."
     if ! env "INNGEST_CLI_VERSION=$${INNGEST_CLI_VERSION}" "INNGEST_CLI_SHA256=$${INNGEST_CLI_SHA256}" \
         bash "$${EXTRACT_DIR}/inngest-bootstrap.sh"; then
       echo "FATAL: inngest-bootstrap.sh non-zero exit" >&2
       rm -rf "$${EXTRACT_DIR}"
       exit 1
     fi
     rm -rf "$${EXTRACT_DIR}"
   ```

   **Two critical render-pass notes for the implementer:**
   - `$$` → `$` in Terraform's interpolation pass. `"$${VAR}"` renders to `"${VAR}"` in the YAML on disk, which dash then expands to the shell variable's value. The double-`$$` pattern matches the existing block at line 287.
   - `$$$$` → `$$` after Terraform pass, which dash expands to the parent shell's PID. This matches `ci-deploy.sh:576` (`"soleur-inngest-extract-$$"`). The extract container name needs the parent PID for uniqueness.
   - Verification command pre-apply: `cd apps/web-platform/infra && terraform console <<< 'templatefile("cloud-init.yml", { ... })'` (with the full var set) renders the resolved YAML to stdout — grep for `${INNGEST_BOOTSTRAP_TAG}` (single-dollar) and confirm no `${...}` residue remains except inside the docker inspect Go-template (`{{range .Config.Env}}…`, which contains zero `$`).
2. **Order verification:** the new block lives BETWEEN `docker pull ${image_name}` and the soleur-plugin-seed block. The bootstrap script reads `/etc/default/webhook-deploy` for DOPPLER_TOKEN — that file is written at line 294 BEFORE the Docker install. The Doppler CLI itself is installed at line 287-291 BEFORE Docker. So the dependency chain (Doppler CLI present, webhook-deploy env file present, Docker daemon up) is satisfied at the chosen insertion point.
3. **Why before soleur-plugin-seed:** the soleur-web-platform container starts AFTER plugin-seed (line 418). The container's `/api/inngest` SDK register call requires Inngest already listening on 8288. The plugin-seed block does not depend on Inngest, so placing the Inngest install AFTER plugin-seed is also acceptable — but placing it BEFORE keeps the wall-clock ordering closer to "Inngest up first, then everything else."

### Phase 2 — `terraform fmt` + `terraform plan` verification

Steps:
1. Run `terraform fmt -check` against `apps/web-platform/infra/` — must exit 0 (no formatting change since the edit is YAML, not HCL).
2. Run `terraform plan` against the existing prd state (read-only, no apply). Expected output: drift on `hcloud_server.web.user_data` ONLY (because `cloud-init.yml` changed). All other resources unchanged. `lifecycle.ignore_changes = [user_data]` on the existing server (`server.tf:50`) means a subsequent `terraform apply` would NOT redeploy the existing server — the diff is informational. Confirms no accidental TF resource addition.

### Phase 3 — AGENTS.md + AGENTS.core.md rule additions

Steps:
1. After Phase 0 trims, add to `AGENTS.core.md` under `## Hard Rules` (placement: adjacent to `hr-all-infrastructure-provisioning-servers`, line 17):
   ```
   - Every service in `apps/<app>/infra/` MUST come up on a fresh `terraform apply` against empty state with zero operator post-apply actions [id: hr-fresh-host-provisioning-reachable-from-terraform-apply] [skill-enforced: plan Phase 2.8]. If a service requires a tag push or webhook click, the install MUST also live in `apps/<app>/infra/cloud-init.yml` `runcmd:`. **Why:** PR-F (#3940) shipped Inngest where cloud-init never installed it — fresh apply produced silent-cron-miss, see #4017/#4118.
   ```
   **Byte count (verified at deepen-plan time, 2026-05-20):** 496 B. Cap is 600 B (`PER_RULE_CAP` per `scripts/lint-agents-rule-budget.py:46`). 104 B headroom. Verify after write with `awk 'NR==<line> {print length($0)}' AGENTS.core.md` — must be ≤600.
2. Add pointer to `AGENTS.md` under `## Hard Rules` (placement: adjacent to `hr-all-infrastructure-provisioning-servers`, line 19):
   ```
   - [id: hr-fresh-host-provisioning-reachable-from-terraform-apply] → core
   ```
3. Re-run `lint-rule-ids.py`, `lint-agents-rule-budget.py`, `lint-agents-enforcement-tags.py` — all must exit 0.

### Phase 4 — Skill extension (plan Phase 2.8)

Steps:
1. In `plugins/soleur/skills/plan/SKILL.md`, extend the `### 2.8. Infrastructure-as-Code Routing Gate` section's Detection list with a new bullet (after the `cron`/`crontab -e` bullet):
   ```
   - install path described in prose as "after merge, push a `vX.Y.Z` tag and click the deploy webhook" — even when the webhook + tag-trigger workflow + bootstrap script all live in `apps/<app>/infra/` already (per `hr-fresh-host-provisioning-reachable-from-terraform-apply`)
   ```
2. Extend the `Required output: ## Infrastructure (IaC) section` block with a new subsection requirement bullet:
   ```
   - `### Fresh-host provisioning` — answer "if `terraform apply` runs against empty state with no operator on the keyboard, does this service end up running?" yes/no + the cloud-init path that makes it yes. Cite the file + line range that closes the loop. Per `hr-fresh-host-provisioning-reachable-from-terraform-apply`.
   ```
3. Re-run `bun test plugins/soleur/test/components.test.ts` (SKILL.md description-budget linter). The SKILL.md `description:` field is unchanged, so the budget headroom is unaffected.

### Phase 5 — Companion learning files

Steps:
1. Create the two Phase-0 extraction files (rule-body extracts).
2. Create `knowledge-base/project/learnings/best-practices/2026-05-20-cloud-init-runcmd-bootstrap-mirror-from-deploy-handler.md` — content topic: the cloud-init / ci-deploy.sh dual-path pattern, OCI-tag-vs-cli-version separation, when to mirror vs when to diverge.
3. Edit `knowledge-base/engineering/ops/runbooks/inngest-server.md` to add the `## Fresh-host install (cloud-init path)` section.

### Phase 6 — PR-creation + ship

Steps:
1. Run `/soleur:compound` per `wg-before-every-commit-run-compound-skill`.
2. Commit + push.
3. Open PR with body:
   - Title: `feat(infra): one-shot cloud-init Inngest install + hr-fresh-host-provisioning-reachable rule (#4118)`
   - Body: cites `Ref #4118` (post-merge closure), `Ref #4126` (Tier 2 follow-up), `Closes #<N1> #<N2>` (pre-existing breach tracking).
4. `/soleur:ship` Phase 6 closes #4118 via `gh issue close` after AC14 success post-merge.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — per single-user-incident threshold).

### Engineering (CTO)

**Status:** reviewed (carry-forward from issue body — the issue itself was authored as a CTO framing; it cites `hr-all-infrastructure-provisioning-servers`, `hr-tagged-build-workflow-needs-initial-tag-push`, `hr-multi-step-post-merge-bootstrap-script` and explicitly proposes the new rule). No fresh CTO Task is needed — the brainstorm-equivalent context lives in the issue body.
**Assessment:** The fix is structurally simple (one runcmd block + one rule). Risks are localized to ordering (Phase 1 step 2 — must run before `docker run soleur-web-platform`) and pin-drift (two coordinates: OCI tag vs inngest_cli_version). Both addressed in plan body.

### Product/UX Gate

**Tier:** NONE (no user-facing UI surface — infrastructure-only change).
**Decision:** auto-accepted (no user-facing diff).
**Agents invoked:** none (Tier-NONE bypass).

**CPO sign-off requirement:** flagged per `requires_cpo_signoff: true` in YAML frontmatter (single-user-incident threshold). CPO sign-off addresses the framing question: "is a half-installed substrate on a fresh `terraform apply` a brand-survival event for Soleur?" — YES per issue body; the plan delivers the closure. Sign-off is plan-time (this document), not review-time.

## Infrastructure (IaC)

### Terraform changes

No new Terraform resources. The cloud-init.yml edit changes the rendered `user_data` of `hcloud_server.web`; the resource's `lifecycle.ignore_changes = [user_data]` block (`server.tf:50`) means the existing live server is NOT replaced by `terraform apply`. New (future) servers spawned from this state will receive the new cloud-init content.

### Apply path

**(a) cloud-init-only for fresh hosts** — the new runcmd block fires at first boot.
**(b) cloud-init + idempotent bootstrap script for existing infra** — the existing live server is updated NOT by this PR's apply path but by a one-time post-merge `gh workflow run` of `web-platform-release.yml` with `deploy_target=inngest` `deploy_tag=v1.0.0`. The bootstrap script's idempotency short-circuit (version-file match) makes the re-run a no-op (~50ms). Documented as AC14.

### Distinctness / drift safeguards

- `dev != prd`: this PR touches only `apps/web-platform/infra/cloud-init.yml` and `AGENTS.core.md` / `AGENTS.md` / `plan/SKILL.md` / learning files. No Doppler / Supabase / secret edits. Per `hr-dev-prd-distinct-supabase-projects`: irrelevant (no DB-shape change).
- `lifecycle.ignore_changes` callouts: documented (server.tf:50 user_data ignore).
- State-storage notes: no change. R2 backend per `hr-every-new-terraform-root-must-include-an` remains unchanged.

### Vendor-tier reality check

No vendor changes. Cloudflare, Hetzner, Doppler, Better Stack, Sentry — all already paid where they need to be.

## Test Strategy

This PR is a config-change PR (cloud-init runcmd + AGENTS rule). The realistic test surface is:

1. **Static linting** (already in CI): `lint-rule-ids.py`, `lint-agents-rule-budget.py`, `lint-agents-enforcement-tags.py`, `terraform fmt -check`, `terraform validate`. Phase 0-3 each re-run these.
2. **Idempotent post-merge live verification** (AC14): operator re-fires the inngest deploy webhook against the live server. Bootstrap short-circuits in ~50ms. Confirms no regression on the in-place upgrade path.
3. **Cloud-init disaster-recovery test**: DEFERRED to #4126 (Tier 2). The plan does NOT prescribe writing this test in this PR.

No new unit tests are required — the runcmd block is shell-script-shaped and parallel to existing `ci-deploy.sh:556-624` (which has its own `inngest.test.sh` shell test). Adding a new shell test that re-exercises the extract + invoke path would duplicate `inngest.test.sh` coverage without adding signal until Tier 2's destructive integration test is in place.

## Open Code-Review Overlap

Two pre-existing breach tracking issues are FILED IN Phase 0 BEFORE editing AGENTS.core.md:

- `<N1>` (filed in Phase 0 step 1) — `hr-tagged-build-workflow-needs-initial-tag-push` body 1371 B > 600 B cap. **Fold in:** this PR's Phase 0 step 2 trims the rule body to ≤600 B by extracting to a learning file. PR body `Closes #<N1>`.
- `<N2>` (filed in Phase 0 step 1) — `wg-end-of-work-emit-resume-prompt` body 1039 B > 600 B cap. **Fold in:** same pattern. PR body `Closes #<N2>`.

No other open code-review issues touch the planned file list. Verified via:
```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in apps/web-platform/infra/cloud-init.yml AGENTS.md AGENTS.core.md plugins/soleur/skills/plan/SKILL.md; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

Deepen-pass live result (run 2026-05-20):

```
=== apps/web-platform/infra/cloud-init.yml ===
(none)
=== AGENTS.md ===
#3373: review: SLOT_TRIGGER_INTEGRATION_TEST not wired into nightly CI — boundary tests will silently rot
#3002: review: add service-worker global error handler for cache.put quota failures
=== AGENTS.core.md ===
(none)
=== plugins/soleur/skills/plan/SKILL.md ===
(none)
```

**Disposition:** the two AGENTS.md hits (#3373, #3002) are file-mention-only — both issues touch unrelated subsystems (SLOT trigger CI gating, service-worker cache.put handling) that mention AGENTS.md as one of many reference docs. **Acknowledge** (not fold in, not defer) — neither overlaps the rule additions or the runcmd block this PR introduces. Recorded so the next planner sees the check ran. Both `<N1>` and `<N2>` (the Phase-0 breach trackers) will appear in the AGENTS.core.md row after Phase 0 step 1; pre-Phase-0 grep returns empty. The plan's AC0/AC1 close both.

## Sharp Edges

- **Two-coordinate tag drift:** `apps/web-platform/infra/inngest.tf:locals.inngest_cli_version` and the cloud-init pin (`INNGEST_BOOTSTRAP_TAG`) are TWO independent version pointers. The first tracks upstream inngest-cli releases; the second tracks the bootstrap-shape OCI image releases. They MUST be bumped together when bumping inngest-cli — otherwise the cloud-init image embeds the OLD CLI even after `inngest.tf` is bumped. Runbook documents the dual-bump procedure (AC11). A future improvement (out of scope here) could templatefile() interpolate the tag from `inngest.tf` into `cloud-init.yml`, but the issue body's snippet hardcodes the tag and a templatefile pass widens the blast radius beyond Tier 1. Filed as a follow-up issue if/when the second drift is observed.
- **Pre-existing AGENTS budget breach in #4085:** rule `hr-tagged-build-workflow-needs-initial-tag-push` shipped at 1371 B (>2x cap) because lefthook only fires the linter on AGENTS-file edits. Same for `wg-end-of-work-emit-resume-prompt` (1039 B). This PR's Phase 0 closes both — but the root cause (lefthook glob too narrow, breach can sit on main for weeks) is NOT addressed here. Out of scope. Filed as a separate follow-up if recurrence observed.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled — threshold `single-user incident`, artifact + vector both named.
- **The "Companion observability issue (TBD)" reference in the original #4118 body does NOT exist** — `gh issue list --label observability` returns 0 matches. Plan strikes the reference (research-reconciliation row 4) and routes the heartbeat-pause-after-fresh-apply step to the runbook instead.
- **The lifecycle.ignore_changes = [user_data]** on `hcloud_server.web` (`server.tf:50`) means the EXISTING live server does NOT auto-redeploy when cloud-init.yml changes. This is by design (existing servers are mutated via the webhook). New Soleur users who provision a fresh server WILL get the new cloud-init. The existing server is verified one-time-after-merge via AC14 (idempotent re-fire of the inngest webhook).
- **Doppler-token sourcing dependency:** the bootstrap script reads `/etc/default/webhook-deploy` for DOPPLER_TOKEN (line 217 of `inngest-bootstrap.sh`). cloud-init writes that file at line 294, BEFORE the new runcmd block fires. Verified at Phase 1 step 2.
- **Reviewer note:** the new rule's `[skill-enforced: plan Phase 2.8]` tag MUST point to an actual extension in `plan/SKILL.md` Phase 2.8 — the enforcement-tag linter (`lint-agents-enforcement-tags.py`) checks anchor-parity (AC9). Phase 4 makes that extension.
- **NEVER use `--no-verify` to bypass lefthook on the AGENTS edits.** The pre-existing breach exists precisely because earlier PRs that touched only non-AGENTS files dodged the linter. The cure is to FIX the breach (Phase 0), not to skip the gate.

## Plan-time CPO Sign-off

**Requested:** Plan author. Single-user-incident threshold per issue-body framing.
**Sign-off status:** pending (operator decision before `/work`).

CPO concern surfaced from issue-body framing:
- New Soleur users running `terraform apply` against a fresh Hetzner project get a silent half-broken substrate today. This is a single-user-incident-class event (one user's experience is enough to break trust).
- Tier 1 (cloud-init) + Tier 3 (AGENTS rule) close the silent-break gap immediately.
- Tier 2 (#4126) is the recurring verification gate; deferred per scoping.
- The plan delivers the brand-survival fix; no additional CPO concerns surfaced.

## Notes (no Domain Review for non-Product/non-Engineering)

- CLO (legal): No data-controller-role change. The OCI image is pulled from `ghcr.io/jikig-ai/soleur-inngest-bootstrap` which is operator-controlled. Doppler secret-handling surface is unchanged (no new secret types, no new sub-processors). Skipped silently per Phase 2.7 GDPR/compliance gate triggers: this PR touches no schemas, no migrations, no auth flows, no API routes, no `.sql` files, no LLM-fed data, no operator-session learnings, no PR-body distribution surface. Trigger evaluation: gate-fires-NO.
- CMO/CRO/COO: irrelevant (no marketing, no conversion, no expense surface).

## Deepen-pass Quality Checks (applied 2026-05-20)

- [x] **CLI/syntax verification:** docker inspect Go-template `{{range .Config.Env}}{{println .}}{{end}}` confirmed against `apps/web-platform/infra/ci-deploy.sh:593` (existing production precedent). `docker pull`, `docker create`, `docker cp`, `docker rm`, `docker inspect -f` all standard subcommands.
- [x] **Terraform `templatefile()` escaping:** Every shell `$VAR` in the new runcmd block uses `$$VAR` form to escape Terraform's `${...}` interpolation pass — mirrors existing precedent at cloud-init.yml lines 287 (Doppler install) and 351 (webhook install).
- [x] **POSIX shell compatibility:** Confirmed cloud-init `- |` blocks run under `/bin/sh` (dash on Ubuntu 24.04). Replaced bash `[[ ]]` with POSIX `[ ]` tests + `||` joins. The bootstrap script itself retains `[[ ]]` because it has `#!/usr/bin/env bash` shebang and is invoked via explicit `bash …`.
- [x] **Attribution verification (live `gh` query):** PR #3940 confirmed merged 2026-05-17 with title "feat(runtime): PR-F Inngest trigger layer + CFO autonomous-draft (#3244 §F)"; PR #3973 confirmed merged 2026-05-19 as the IaC layer ("feat(infra): IaC for inngest-server — Doppler + BetterStack providers + bootstrap + OCI build (#3960)"); PR #4085 confirmed merged 2026-05-19 (5-bug substrate fix). Issue #4017 confirmed closed (`follow-through: verify cron-daily-triage first 04:00 UTC fire`).
- [x] **AGENTS rule pre-existence check:** `grep -E "\[id: hr-fresh-host-provisioning-reachable-from-terraform-apply\]" AGENTS*.md scripts/retired-rule-ids.txt` returned zero matches. Safe to add as new active rule.
- [x] **AGENTS budget math (load-bearing finding for /work):** B_ALWAYS at branch tip = 24499 B (4960 AGENTS.md + 19539 AGENTS.core.md). Cap = 22000. Pre-existing overflow = **2499 B**. The plan adds: new rule body 496 B + new AGENTS.md pointer line (~80 B) = +576 B. To land, the total trim must shed AT LEAST `2499 + 576 = 3075 B`.

  Audit of AGENTS.core.md rule-body sizes (`awk` over `## Hard Rules` / `## Workflow Gates` / etc. sections; deepen-time pull):

  | Line | Rule ID | Current B | Trimmable to | Shed |
  | --- | --- | --- | --- | --- |
  | 15 | `hr-tagged-build-workflow-needs-initial-tag-push` | 1371 | 200 | 1171 |
  | 55 | `wg-end-of-work-emit-resume-prompt` | 1039 | 200 | 839 |
  | 14 | `hr-multi-step-post-merge-bootstrap-script` | 587 | 200 | 387 |
  | 17 | `hr-all-infrastructure-provisioning-servers` | 530 | 200 | 330 |
  | 28 | `hr-menu-option-ack-not-prod-write-auth` | 521 | 200 | 321 |
  | 30 | `hr-never-git-add-a-in-user-repo-agents` | 492 | 200 | 292 |
  | **Total shed from 6 trims** | | | | **3340** |

  Result: AGENTS.core.md drops from 19539 → 16199 B. Plus new rule 496 B = 16695 B. AGENTS.md grows by ~80 B (new pointer) = 5040 B. **B_ALWAYS final = 21735 B**, **265 B under the 22000 cap** — passes the linter with breathing room.

  **Recommendation:** the trim work is real-and-substantial — it touches 6 rules + creates 6 learning files + closes 6 pre-existing code-review breach trackers (lines 15 and 55 are CURRENTLY over the 600 B cap; lines 14/17/28/30 are within cap today but contribute to B_ALWAYS overrun). The cleanest path is **a separate FIRST PR** that lands the recovery trim:
  - PR-1: `chore(AGENTS): B_ALWAYS recovery — trim 6 rule bodies to ≤200 B, close 6 pre-existing breach trackers`. Files 6 tracking issues (per `wg-when-an-audit-identifies-pre-existing`), extracts each rule's prose to a learning file, trims the rule body. Single-PR atomic. Closes 6 issues. No new functionality.
  - PR-2: this PR. Lands `hr-fresh-host-provisioning-reachable-from-terraform-apply` + cloud-init runcmd block + skill extension + runbook update. Closes #4118 (Tier 1 + Tier 3).

  Both PRs land via `/one-shot` in series; PR-2 starts AFTER PR-1 merges (so B_ALWAYS recovery is live on main before PR-2's lint runs).

  **Plan-time decision (operator-flagged):** does the operator want the split? If `no`, /work can attempt a single PR with all 6 trims + the new rule — but the diff size jumps from ~3 files to ~13 files (6 trims + 6 learnings + new rule + cloud-init + skill + runbook + 2 learnings already planned), which dilutes review focus.

  **Default:** SPLIT into two PRs unless operator opts otherwise.

- [x] **Phase 0 amendment lands in PR-1 (not this PR):** Phase 0 step 1 of THIS plan (filing 2 breach tracking issues) was originally scoped to lines 15 + 55 only. The deepen-pass widens the trim surface to 6 rules. PR-1 files 6 issues; PR-2 (this plan) DOES NOT touch Phase 0 — assumes PR-1 already landed. **If the operator chooses single-PR**, restore Phase 0 with all 6 trims rolled into this PR.
- [x] **Code-review overlap query:** `gh issue list --label code-review --state open` returned 2 hits for AGENTS.md (#3373, #3002) — both file-mention-only, unrelated to this work. Acknowledged. No overlap on the other three target files.
- [x] **GitHub label verification:** `gh label list --limit 200 | grep -E "^code-review|^chore|^domain/engineering"` confirms all three labels exist. Phase 0 tracking issues will use `code-review` + `domain/engineering` + `chore`.
- [x] **`User-Brand Impact` section:** present, non-empty, threshold = `single-user incident`. Phase 4.6 halt gate passes.
- [x] **GDPR/compliance gate (plan Phase 2.7):** evaluated — touches no schema, migration, auth flow, API route, `.sql` file, LLM-fed data, operator-session learnings, or PR-body distribution surface. Gate fires NO. Documented in Domain Review section.
- [x] **IaC routing gate (plan Phase 2.8):** evaluated — Detection terms (`ssh root@`, `systemctl enable`, `doppler secrets set`, vendor-dashboard) are NOT in the plan body except as quoted patterns of the rule being authored. The plan PRESCRIBES routing through cloud-init `runcmd:` (the correct outcome per `hr-all-infrastructure-provisioning-servers`). Gate satisfied.
- [x] **Plan-time CPO sign-off requirement:** flagged in frontmatter (`requires_cpo_signoff: true`); plan-body sign-off subsection added; review-time `user-impact-reviewer` will be invoked on the diff.

## Resume Prompt (post-plan)

```
/soleur:work knowledge-base/project/plans/2026-05-20-feat-one-shot-cloud-init-inngest-4118-plan.md. Branch: feat-one-shot-cloud-init-inngest-4118. Worktree: .worktrees/feat-one-shot-cloud-init-inngest-4118/. Issue: #4118. Tier 2 deferral: #4126. CPO sign-off required before /work. Plan reviewed, implementation next.
```
