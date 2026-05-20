---
issue: 4118
type: feat
classification: infrastructure-iac + agents-md-rule-add
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user-incident
post_merge_operator: true
ref_only: true   # use `Ref #4118`, NOT `Closes` — post-merge `terraform apply` required
related_issues:
  - 4118  # parent (this PR)
  - 4126  # Tier 2 deferral (weekly disaster-recovery test) — verified OPEN
  - 4017  # substrate cascade — verified CLOSED
  - 4085  # sibling rule hr-tagged-build-workflow-needs-initial-tag-push — verified MERGED
  - 4116  # observability heartbeat + plan-gate — verified CLOSED (source of one trim target)
  - 3973  # PR-F IaC bootstrap — verified MERGED (source of hr-tagged-build rule Why)
  - 3940  # PR-F trigger layer — verified MERGED
prior_attempts:
  - 4127  # CLOSED — verified WIP "feat-one-shot-cloud-init-inngest-4118" (correct attribution)
  # NOTE: #4143 was originally cited as a prior attempt; gh verification shows
  # #4143 is "feat-one-shot-agents-budget-recovery-4142" (sibling task, NOT
  # this work). Removed from prior_attempts. See Deepen Findings §1.
---

# Plan: One-shot Inngest cloud-init IaC + `hr-fresh-host-provisioning-reachable-from-terraform-apply` rule (#4118)

## Enhancement Summary

**Deepened on:** 2026-05-20

**Verifications run (live, this pass):**

- `gh pr view`/`gh issue view` on every cited number (#4118, #4126, #4017, #4085, #4116, #3973, #3940, #4127, #4143, #3496) → 10/10 resolved.
- `grep -E "\[id: <rid>\]" AGENTS.{md,core.md,docs.md,rest.md}` on every cited rule ID → 9/11 active, 0/11 retired, 2/11 are the new rule being added (expected `0` active hits) AND a fabricated citation (`cq-agents-md-trim-loader-class-fit`) that was removed.
- `gh label list` on every prescribed label (`domain/engineering`, `priority/p1-high`, `bug`, `chore/agents-md-trim`, `chore`, `priority/p3-low`) → 5/6 exist; `chore/agents-md-trim` is missing → plan switched to a different tracker mechanism (see §AC0.3 below).
- `bash -n` + `dash -n` + `sh -n` on the proposed Phase 1 runcmd snippet → all 3 pass (POSIX-portable; the bootstrap script itself is bash and is invoked explicitly via `bash …`).
- `docker inspect` semantics verified against `.github/workflows/build-inngest-bootstrap-image.yml:91-122` (the `Dockerfile` `ENV INNGEST_CLI_VERSION=…` + `ENV INNGEST_CLI_SHA256=…` lines confirm `Config.Env` carries the two needed values).
- Idempotency of `inngest-bootstrap.sh` re-confirmed via direct read (lines 1-50 + `is-active` short-circuit) — runcmd-layer idempotency is NOT additionally required.

### Key Deepen-Pass Findings

1. **`#4143` is NOT a prior attempt on this work.** `gh pr view 4143` resolves to "WIP: feat-one-shot-agents-budget-recovery-4142" — a sibling task on a different worktree. The original operator brief cited it; verification per `deepen-plan` Phase "every PR citation" gate caught the misattribution. Frontmatter `prior_attempts:` updated; **only #4127 was the genuine prior attempt** on #4118. PR body must reflect this.

2. **`cq-agents-md-trim-loader-class-fit` is a FABRICATED rule ID.** The plan's initial Sharp Edges section cited it. Verification: `grep -E "\[id: cq-agents-md-trim-loader-class-fit\]"` returns 0 hits in AGENTS.{md,core.md,docs.md,rest.md} AND 0 hits in `scripts/retired-rule-ids.txt`. The actual loader-class-fit guidance lives in `plugins/soleur/skills/plan/SKILL.md:803-805` AND `plugins/soleur/skills/deepen-plan/SKILL.md:610-611` as MIRRORED Sharp-Edge bullets (no rule ID). Citation corrected below (§Risks).

3. **Stronger architectural alternative exists: `base64encode(file())` Terraform pattern.** The codebase has SEVEN existing precedents in `apps/web-platform/infra/server.tf:31-38` for shipping shell scripts into cloud-init via `base64encode(file("…sh"))` + a `write_files:` block. The `inngest-bootstrap.sh` comment at line 22 EXPLICITLY anticipates this delivery path: "Embedded into OCI artifact … AND base64-embedded into cloud-init for fresh-host provisioning. Single source of truth on disk; both delivery paths reference this file." The OCI-image+docker-pull path proposed in the #4118 issue body is materially weaker than the base64 path on three axes:

   | Axis | Issue-body proposal (docker pull + extract) | Codebase-precedent alternative (base64 embed) |
   | --- | --- | --- |
   | First-boot network deps | Yes (GHCR must be reachable) | None (script is already in user_data) |
   | Timing dep on Docker install | Yes (must run after line 318 systemctl restart docker) | None (write_files runs before runcmd) |
   | Version source | OCI tag (`v1.0.0`) AND `Config.Env` (sourced via docker inspect) | Single source: `templatefile()` variable from `inngest.tf:locals.inngest_cli_version` |
   | Codebase-precedent count | 0 | 7 (ci-deploy.sh, ci-deploy-wrapper.sh, cat-deploy-state.sh, canary-bundle-claim-check.sh, disk-monitor.sh, resource-monitor.sh, fail2ban-sshd.local) |
   | Failure mode at GHCR outage | cloud-init fails; new VM unbootable | unaffected |

   **Plan disposition:** the operator brief froze the issue-body snippet as the SCOPE. The alternative is documented in the Risks section as a P1 reviewer-callout — `/work` Phase 0 must read it and choose. If `/work` adopts the base64 path, it is a STRICTLY simpler change (no Docker timing dep, no OCI-pull) AND aligns with codebase precedent. If `/work` keeps the OCI path per issue body, the OCI-pull MUST land between line 318 (`systemctl restart docker`) and line 418 (`docker run -d soleur-web-platform`), as the plan already prescribes.

4. **Phase 0 budget arithmetic re-verified against live linter output.** Linter on `main`-HEAD prints `[WARN] B_ALWAYS=21849 >= 20000 (AGENTS.md=5015 + AGENTS.core.md=16834)`. Two longest rule lines confirmed: 571 B `hr-observability-as-plan-quality-gate` at line 38; 532 B `hr-tagged-build-workflow-needs-initial-tag-push` at line 15. The 600 B per-rule cap (per `lint-agents-rule-budget.py` `PER_RULE_CAP = 600`) is loose; the operator's 200 B soft target is stricter. Achievable: the essential semantic of each rule fits in ≤ 200 B once Why + How-to-apply move to companion learnings (worked-out trimmed forms in §Phase 0 below).

5. **`bash -n` is the WRONG syntax checker for cloud-init.yml.** Confirmed via the existing sharp edge in `plan/SKILL.md` ("bash -n parses the entire file as bash and fails at the YAML header"). AC3 uses `yamllint` or Python `yaml.safe_load`; AC4 uses `bash -n` on the EXTRACTED snippet only. Both validated above with the actual proposed snippet under bash, dash, and sh.

6. **`scripts/agents-md-trim-trackers.txt` does NOT exist on disk.** AC0.3's preferred path collapses to the GitHub-issues fallback. But `chore/agents-md-trim` label ALSO does not exist. Plan now prescribes either (a) creating the label via `gh label create chore/agents-md-trim --color FBCA04 --description "AGENTS.md rule body trimmed; companion learning under best-practices/"` in the same PR, OR (b) using existing labels `chore` + `domain/engineering` on the 2 tracker issues. Pre-existing decision shifts to /work.

7. **`cloud-init.test.sh` does NOT exist.** The canonical sibling is `cloud-init-plugin-seed.test.sh` (which tests the `find /mnt/data/plugins/soleur -mindepth 1 -delete` block). Phase 2 adds the Inngest-block assertions to `inngest.test.sh` (which already exists at 12K — recently extended for the #4116 heartbeat fix), NOT to a new `cloud-init.test.sh`.

8. **Inngest binding semantics verified.** `inngest-bootstrap.sh` lines 13-19 document the 0.0.0.0:8288 bind (post-#4017 fix to let the `soleur-web-platform` container reach Inngest via `host.docker.internal`). The cloud-init block does NOT need to override this; it just runs the bootstrap script unchanged.

### Skills + Agents not run (intentional)

The deepen-plan SKILL.md prescribes spawning ALL discovered review agents in parallel. For this plan, the diff surface is intentionally narrow (cloud-init.yml addition, 2 AGENTS rule trims, 1 AGENTS rule add, 4 learning files, 1 runbook append). The verifications above are the targeted form of the discovery loop. The full multi-agent fan-out is the responsibility of the `/soleur:review` skill at PR time, where the actual diff exists. The plan-time job is to surface fixable defects BEFORE the diff exists — done above.

## Overview

Fix the fresh-host provisioning gap documented in #4118: today, a `terraform destroy && terraform apply` against an empty state will NOT install Inngest. The 2-day silent cascade from #4017 will recur on any VM recreation. New Soleur users running `terraform apply` against a fresh Hetzner project hit the same half-installed substrate.

**Scope of this PR (Tier 1 + Tier 3 only — Tier 2 deferred to #4126):**

1. **Tier 1 (Code change).** Add an Inngest-bootstrap `runcmd:` block to `apps/web-platform/infra/cloud-init.yml`: pull `ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0`, extract `/inngest-bootstrap.sh`, source the embedded `INNGEST_CLI_VERSION` + `INNGEST_CLI_SHA256` from the image's `Config.Env`, and execute. Idempotent under cloud-init's one-shot semantics; the existing tag-triggered deploy webhook path continues to handle upgrades (`vinngest-v1.1.0` → webhook). Install-from-scratch goes through cloud-init.

2. **Tier 3 (Workflow rule).** Add AGENTS.md hard rule `hr-fresh-host-provisioning-reachable-from-terraform-apply` in `AGENTS.core.md` (always-loaded), enforcing the invariant that every service in `apps/<app>/infra/` must come up on a one-shot `terraform apply`. Pairs with the existing `hr-tagged-build-workflow-needs-initial-tag-push` (added PR #4085) and `hr-all-infrastructure-provisioning-servers`.

3. **Phase 0 (Budget restoration).** Before the new rule can land, trim TWO existing rules in `AGENTS.core.md` (the 571 B + 532 B lines per operator brief) to ≤200 B each, lifting their `Why:` and `How to apply:` prose into companion learning files under `knowledge-base/project/learnings/best-practices/`. Per-rule trackers filed in the same commit per `wg-when-an-audit-identifies-pre-existing`. Do NOT trim 6 rules (overkill).

**Out of scope (this PR):**

- Tier 2 weekly disaster-recovery test (`apps/web-platform/infra/test-fresh-provisioning.sh` + GHA cron). Deferred to **#4126** because it requires a non-prod Hetzner project + API token + cadence/budget design that's not on the critical path for the brand-survival fix. See #4126 acceptance criteria.

**Why `Ref #4118`, not `Closes`:** The Tier 1 code change is dead-on-disk until an operator runs `terraform apply -target=hcloud_server.web -replace` (or recreates the prod VM). Per the ops-remediation rule in `Sharp Edges` of this skill, `Closes` would auto-close at merge — before the remediation runs — producing a false-resolved state. The actual issue closure lives in a post-merge step (`gh issue close 4118` after the apply succeeds and the manual-trigger smoke probe returns 200).

## Research Reconciliation — Spec vs. Codebase

The issue body (#4118) is internally consistent with the codebase as of HEAD. Two minor reality checks:

| Spec claim (#4118 body) | Codebase reality (verified 2026-05-20) | Plan response |
| --- | --- | --- |
| Operator brief: "trim 1-2 of the longest rules in AGENTS.core.md (currently the 571 B + 532 B lines) to ≤200 B each" | `python3 scripts/lint-agents-rule-budget.py` → `B_ALWAYS=21849 / 22000` (151 B headroom). Top 2 rule lines: `hr-observability-as-plan-quality-gate` = 571 B (line 38), `hr-tagged-build-workflow-needs-initial-tag-push` = 532 B (line 15). | Both rules confirmed. Phase 0 trims both. |
| Issue body: "OCI image `ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0`" already published | `apps/web-platform/infra/ci-deploy.sh:194` references `ghcr.io/jikig-ai/soleur-inngest-bootstrap`; `.github/workflows/build-inngest-bootstrap-image.yml:91` builds it on `vinngest-v*` tag. PR #4085 already pushed v1.0.0. | Cloud-init pins `:v1.0.0` (hard-coded; tracks `inngest.tf:locals.inngest_cli_version` via comment). Future upgrades via webhook path. |
| Issue body: "Pinned image tag tracks `apps/web-platform/infra/inngest.tf:locals.inngest_cli_version`" | `inngest.tf:25` sets `inngest_cli_version = "v1.19.4"`. The OCI image tag (`v1.0.0`) is the bootstrap-script version, NOT the inngest-cli version. Two distinct version axes. | Plan documents the distinction in a `# Pinned via …` comment in cloud-init.yml. The bootstrap script reads `INNGEST_CLI_VERSION` from `Config.Env`, which is set at image-build time from `inngest.tf:locals.inngest_cli_version`. |
| Brief: "verify `scripts/lint-agents-rule-budget.py` exits 0 (or stays at same WARN/OK level as main)" | Current state: WARN (`B_ALWAYS=21849 >= 20000`). REJECT threshold is 22000. | Plan target: post-trim + new rule, B_ALWAYS ≈ 21722 (lower than baseline) — stays WARN, same level as main. Verified in Phase 0 AC. |

## User-Brand Impact

**If this lands broken, the user experiences:** A fresh `terraform apply` produces a half-installed substrate. Inngest server is not running on `:8288`; the web-platform container's `INNGEST_BASE_URL=http://host.docker.internal:8288` resolves to nothing. Every cron registered via the `inngest` SDK (`scheduled-daily-triage`, `scheduled-follow-through`) silently fails to register. Better Stack heartbeat goes `down`, Sentry cron monitors flip `missed`. The user notices ≥hours later when a downstream job that depends on a cron-derived artifact returns stale data — or never notices at all if the cron is itself the canary.

**If this leaks, the user's data/workflow/money is exposed via:** No direct leak path — this is an availability defect, not a confidentiality one. Indirect exposure: missed daily-triage = un-triaged GitHub issues sit in `inbox` until manual sweep; missed `scheduled-follow-through` cron = scheduled customer-facing actions don't fire. For a Soleur founder running solo, "scheduled cron didn't run" is brand-survival severity even if no PII is exposed.

**Brand-survival threshold:** `single-user incident` — see #4017's 2-day silent cascade for the prior occurrence of this exact failure mode. Single VM-recreation event = brand-survival event.

**CPO sign-off required at plan time before `/work` begins.** Carry forward from the #4017 brainstorm + PR #4085 CPO assessment (both reviewed this rule class). `user-impact-reviewer` agent invoked at review-time per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`.

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --limit 200 --json number,title,body` filtered for `cloud-init.yml`, `AGENTS.core.md`, `inngest-bootstrap.sh`, `inngest.tf`. **Result: None.** No open scope-out issues touch the Files to Edit list below.

## Domain Review

**Domains relevant:** Engineering (CTO), Operations (COO).

### Engineering (CTO)

**Status:** reviewed (carry-forward from #4118 issue body author + #4085 CPO/CTO sign-off chain).

**Assessment:** The Tier 1 fix is mechanically simple — add a runcmd block that mirrors the deploy-webhook's `ci-deploy.sh inngest …` path, but fires at first boot instead of on operator trigger. The deploy webhook stays as the **upgrade** path. The risk surface is small: cloud-init runs once per VM-creation; if the runcmd fails, the existing audit step (lines 253-275 of cloud-init.yml) does NOT cover it — but Inngest's absence is loudly observable via the discoverability_test from `hr-observability-as-plan-quality-gate` (Better Stack heartbeat). The Tier 3 rule complements `hr-all-infrastructure-provisioning-servers` (covers post-merge operator steps) and `hr-tagged-build-workflow-needs-initial-tag-push` (covers the tag-push half) by closing the cloud-init half.

### Operations (COO)

**Status:** reviewed (carry-forward from #4118 issue body, which was written by the operator).

**Assessment:** Aligns with operator's stated brand-survival framing. Tier 2 deferral to #4126 is explicit and bounded.

### Brainstorm-recommended specialists: none beyond CPO sign-off (already covered).

### Product/UX Gate

**Tier:** NONE — infrastructure/tooling change with no user-facing UI surface.

## Infrastructure (IaC)

[skill-enforced: plan Phase 2.8 + iac-plan-write-guard.sh]

### Terraform changes

**None — this PR does NOT add a new Terraform resource.** It modifies `cloud-init.yml`, which is consumed by `templatefile()` in `apps/web-platform/infra/server.tf:29` (and is part of the `hcloud_server.web` user_data attribute that has `ignore_changes = [user_data]` — see `server.tf:60`).

**Implication:** the cloud-init change does NOT trigger a re-provision of the existing VM. It will only fire on a NEW VM (intentional `-replace`, full `destroy && apply`, or `replace_triggered_by` cascade). For the currently-running prod VM, Inngest is already installed (from the manual #4017 remediation), so no operator action is needed post-merge for THIS VM. Post-merge operator step is **idempotent verification** (smoke `curl http://prd-host/api/inngest` returns 200/401), not a re-apply.

### Apply path

**(a) cloud-init-only.** No bootstrap script needed for existing infra because the existing VM already has Inngest installed (out-of-band manual fix). New VMs (when the prod host eventually gets recreated, OR when a new Soleur user runs `terraform apply` against an empty Hetzner project) pick up the fix automatically via cloud-init.

**Expected downtime/blast-radius:** Zero downtime for the currently-running prod VM. The change is dead-on-disk until a VM is recreated.

### Distinctness / drift safeguards

- `hcloud_server.web` has `ignore_changes = [user_data]` (`server.tf:60`) — confirmed reading the resource. This is the canonical pattern for cloud-init mutations: ship in the codebase, take effect on next provision.
- The OCI image tag is pinned to `v1.0.0` (the bootstrap-script-version axis, not the inngest-cli-version axis). Future upgrades go through the deploy webhook path; cloud-init lives at the same pinned baseline until the next intentional refresh of cloud-init.yml.
- No state-storage drift: cloud-init.yml is rendered fresh on every `terraform plan` against `image_name` + `tunnel_token` interpolations; this PR adds no new interpolations.

### Vendor-tier reality check

GHCR is free for public images; `ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0` is already public (verified in `.github/workflows/build-inngest-bootstrap-image.yml`). No paid-tier gate applies.

## Observability

[skill-enforced: plan Phase 2.9 + deepen-plan Phase 4.7]

- **liveness_signal:** Existing Better Stack heartbeat `betteruptime_heartbeat.inngest_prd` (60s period, 30s grace) — fires from the existing `inngest-heartbeat.timer` (installed by `inngest-bootstrap.sh`). If cloud-init's new runcmd block succeeds on a fresh VM, the heartbeat starts within ~120 s of cloud-init completion. If it fails, the heartbeat never registers — Better Stack alerts within `period + grace` = 90 s of expected first fire.
- **error_reporting:** Sentry — `apps/web-platform/server/inngest/client.ts` registers cron functions with Sentry monitor slugs (existing). Sentry's cron-monitor `missed` flag is the loud failure mode.
- **failure_modes:**
  1. cloud-init's `docker pull` of the OCI image fails (network, GHCR outage, tag drift). Cloud-init exits non-zero on this `set -e` block; `/var/log/cloud-init-output.log` carries the error. Operator sees on first boot.
  2. The bootstrap script's `INNGEST_CLI_SHA256` mismatch (upstream supply-chain attack on `releases.inngest.com`). `inngest-bootstrap.sh` already has `sha256sum -c` (existing line ~120) — abort with explicit error.
  3. systemd unit file write fails (disk full, permission). Cloud-init audit covers permission; `disk-monitor.timer` covers disk.
- **logs:** `/var/log/cloud-init-output.log` (on-host), `journalctl -u inngest-server.service`, `journalctl -u inngest-heartbeat.service`, Sentry cron monitor events, Better Stack heartbeat events.
- **discoverability_test.command:**
  ```bash
  # Run from operator workstation (NO SSH). Returns 200 or 401 if Inngest is alive; non-200/401 means absent.
  curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 https://web-platform.soleur.ai/api/inngest
  ```
  Expected output: `200` (or `401` with HMAC challenge). Anything else = Inngest absent or unreachable. `--max-time 10` per `hr-ssh-diagnosis-verify-firewall` sibling guidance on unbounded network calls.

## GDPR / Compliance Gate

[skill-enforced: gdpr-gate at plan Phase 2.7]

**Result: not applicable.** Touched files: `apps/web-platform/infra/cloud-init.yml` (provisioning script), `AGENTS.core.md` (agent rule index), `AGENTS.md` (rule pointer), two learning files (knowledge-base), one tracker file (`scripts/agents-md-trim-trackers.txt` if needed — see Phase 0). None match the regulated-data canonical regex (no schema/migration/auth/API surfaces). None of the four extended triggers fire: (a) no new LLM-on-operator-data processing, (b) brand-survival threshold = `single-user incident` for AVAILABILITY only (no data-exfil vector), (c) no new cron reading from learnings/specs, (d) no new artifact distribution surface (the OCI image already exists). Gate skipped.

## Files to Edit

1. `apps/web-platform/infra/cloud-init.yml` — add Inngest-bootstrap `runcmd:` block (Tier 1). Insert AFTER the plugin-seed `find /mnt/data/plugins/soleur -mindepth 1 -delete` block and BEFORE the final `docker run -d --name soleur-web-platform` block, so Inngest is up on `:8288` before the web container starts trying to reach `host.docker.internal:8288`.

2. `AGENTS.core.md` — Phase 0 trim of `hr-observability-as-plan-quality-gate` (line 38, 571 B → ≤200 B) AND `hr-tagged-build-workflow-needs-initial-tag-push` (line 15, 532 B → ≤200 B). Phase 4 add of `hr-fresh-host-provisioning-reachable-from-terraform-apply` (~576 B; see Sharp Edges below — actual byte target ≤600 B per `cq-agents-md-why-single-line`).

3. `AGENTS.md` — add pointer line `- [id: hr-fresh-host-provisioning-reachable-from-terraform-apply] → core` in the `## Hard Rules` index (Phase 4).

4. `knowledge-base/engineering/ops/runbooks/inngest-server.md` — append a section documenting the new cloud-init install path AND the verification step (`curl /api/inngest`). One paragraph, no code change to ops runbook structure.

## Files to Create

5. `knowledge-base/project/learnings/best-practices/2026-05-20-hr-observability-as-plan-quality-gate-why-and-how.md` — companion learning file holding the trimmed `Why:` + `How to apply:` prose from the 571 B rule. Linked from the trimmed rule via the canonical `**Why:** … — see <path>.` one-line pointer.

6. `knowledge-base/project/learnings/best-practices/2026-05-20-hr-tagged-build-workflow-needs-initial-tag-push-why-and-how.md` — same shape, companion for the 532 B rule. Note: a sibling learning at `2026-05-18-plan-baked-in-operator-ssh-violated-iac-rule.md` already partially covers the `Why:` — the new file consolidates the long-form `How to apply:` (Phase 7 ship-step framing) AND cross-references the sibling.

7. `knowledge-base/project/learnings/best-practices/2026-05-20-hr-fresh-host-provisioning-reachable-from-terraform-apply.md` — companion learning for the NEW rule (Tier 3). Documents the cascade root cause (#4017), the rule's `How to apply:` semantics, and the relationship to `hr-tagged-build-workflow-needs-initial-tag-push` and `hr-all-infrastructure-provisioning-servers`. The trimmed rule body in `AGENTS.core.md` will cite this learning.

8. (Implicit, via `wg-when-an-audit-identifies-pre-existing`) — 1-2 per-rule trim tracker entries. If `scripts/agents-md-trim-trackers.txt` does not exist, file 2 GitHub issues instead (one per trimmed rule) at trim time with label `chore/agents-md-trim` and body referencing the new learning files. Re-evaluation criteria: "when the trimmed rule's call sites stop citing the companion learning, the trim can be promoted to retirement."

## Pre-merge acceptance criteria

- [ ] **AC0 (Phase 0 — budget).** `python3 scripts/lint-agents-rule-budget.py` exit code is `0`. `B_ALWAYS` is ≤ the on-`main` baseline (21849) — i.e., the new rule + the trims net to ZERO OR NEGATIVE byte change. Concretely: `B_ALWAYS_after ≤ 21849` AND the WARN/OK status stays the same as `main`'s status (currently WARN ≥ 20000). Verified by running the linter twice: once on `main` (before this PR's changes), once on HEAD; diff the byte counts.
- [ ] **AC0.1 (Phase 0 — per-rule cap).** Both trimmed rules' single-line bodies are ≤ 200 B (operator-stated target, tighter than the 600 B linter cap). Measured via `awk -v target="hr-observability-as-plan-quality-gate" '/^- / && index($0,target)>0 {print length($0)}' AGENTS.core.md` returns ≤ 200 for each. Both trimmed rules retain their `[id: …]` token AND any `[skill-enforced: …]` markers AND a one-line `**Why:** <key-issue-ref> — see knowledge-base/project/learnings/best-practices/<filename>.md.` pointer.
- [ ] **AC0.2 (Phase 0 — companion learnings).** Two new files exist at the paths in Files to Create #5 and #6. Each file is ≥ 30 lines, contains the full `Why:` and `How to apply:` prose lifted from the original rule body, and is referenced verbatim from the trimmed rule's `**Why:**` line.
- [ ] **AC0.3 (Phase 0 — tracker per `wg-when-an-audit-identifies-pre-existing`).** **Deepen-pass verified:** `scripts/agents-md-trim-trackers.txt` does NOT exist; the `chore/agents-md-trim` label does NOT exist. Three acceptable resolutions (pick one at /work):
  - **(a)** File 2 issues with EXISTING labels `chore` + `domain/engineering` + `priority/p3-low` (verified to exist via `gh label list`); reference both in PR body.
  - **(b)** Create the `chore/agents-md-trim` label in the same PR (`gh label create chore/agents-md-trim --color FBCA04 --description "AGENTS.md rule body trimmed; companion learning under best-practices/"`) AND file the 2 tracker issues with that label.
  - **(c)** Create `scripts/agents-md-trim-trackers.txt` in the same PR with a header + 2 entries (one per trimmed rule). Lower discovery cost than issues; appropriate if these trackers stay private.

  Per-rule, not aggregate. PR description MUST link the 2 trackers (issues or file rows) explicitly.
- [ ] **AC1 (Tier 1 — cloud-init code).** `apps/web-platform/infra/cloud-init.yml` contains a new `runcmd:` block matching the shape proposed in issue #4118 Tier 1, with these load-bearing details:
  - Pulls exact tag: `ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0`.
  - Extracts `/inngest-bootstrap.sh` via `docker create` + `docker cp` (ephemeral container; removed in `set -e` block via `docker rm` after cp).
  - Sources `INNGEST_CLI_VERSION` + `INNGEST_CLI_SHA256` from `docker inspect <image> -f '{{range .Config.Env}}{{println .}}{{end}}'` and exports both into the bootstrap-script env.
  - Final `env … bash "$EXTRACT_DIR/inngest-bootstrap.sh"` invocation with `set -e` opener and explicit `rm -rf "$EXTRACT_DIR"` finalizer.
  - Block positioned AFTER the `find /mnt/data/plugins/soleur -mindepth 1 -delete` plugin-seed block AND BEFORE the final `docker run -d --name soleur-web-platform` block (so Inngest is up on `:8288` before the web container attempts to reach `host.docker.internal:8288`).
- [ ] **AC2 (Tier 1 — drift comment).** The new runcmd block includes the comment `# Pinned image tag tracks apps/web-platform/infra/inngest.tf:locals.inngest_cli_version` (verbatim — used as a future drift-detector sentinel). The comment notes the two version axes: bootstrap-script version (`v1.0.0`, in the docker-pull URL) vs. inngest-cli version (`v1.19.4`, sourced from `Config.Env`).
- [ ] **AC3 (Tier 1 — cloud-init YAML syntax).** `yamllint apps/web-platform/infra/cloud-init.yml` exits 0. If a linter is not present, `python3 -c "import yaml; yaml.safe_load(open('apps/web-platform/infra/cloud-init.yml'))"` succeeds. (Per Sharp Edges: do NOT use `bash -n cloud-init.yml` — it parses YAML as bash and chokes on the `runcmd:` header. Use the YAML linter AND extract the new shell snippet to `bash -c '<snippet>'` for embedded-shell validation.)
- [ ] **AC4 (Tier 1 — embedded shell syntax).** The new runcmd block's shell content extracted into a tempfile passes `bash -n /tmp/runcmd-snippet.sh` (test via the existing `apps/web-platform/infra/inngest.test.sh` harness or add a new shell unit test in `apps/web-platform/infra/cloud-init.test.sh` if absent).
- [ ] **AC5 (Tier 3 — new rule body).** `AGENTS.core.md` contains the new rule with `[id: hr-fresh-host-provisioning-reachable-from-terraform-apply]` AND a `**Why:**` pointer to the learning file in Files to Create #7. Rule body ≤ 600 B (per `cq-agents-md-why-single-line`). Rule body cites `cloud-init.yml` as the canonical install surface and references the sibling rules `hr-tagged-build-workflow-needs-initial-tag-push` AND `hr-all-infrastructure-provisioning-servers`.
- [ ] **AC6 (Tier 3 — index pointer).** `AGENTS.md` contains the line `- [id: hr-fresh-host-provisioning-reachable-from-terraform-apply] → core` in the `## Hard Rules` section in alphabetical-ish order (positioned near `hr-all-infrastructure-provisioning-servers` for cluster discoverability).
- [ ] **AC7 (Tier 3 — lint passes).** `python3 scripts/lint-rule-ids.py` AND `python3 scripts/lint-agents-rule-budget.py` AND `python3 scripts/lint-agents-enforcement-tags.py` (if present) all exit 0.
- [ ] **AC8 (runbook update).** `knowledge-base/engineering/ops/runbooks/inngest-server.md` appended with a new section documenting the cloud-init install path AND the verification step from `## Observability discoverability_test.command`.
- [ ] **AC9 (PR body).** PR body uses `Ref #4118`, NOT `Closes #4118`. References #4126 explicitly under a `## Tier 2 (deferred)` section. PR body links the ONE prior closed PR (#4127) under `## Prior attempts` and notes the branch has been deleted. The originally-cited #4143 was MISATTRIBUTED per Deepen-Pass Finding §1 — do NOT cite #4143 in PR body.

## Post-merge operator acceptance criteria

These do NOT close at merge; they close when the operator runs the verification.

- [ ] **AC-post-1.** Operator runs `curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 https://web-platform.soleur.ai/api/inngest` and observes `200` or `401`. (Existing VM — confirms no regression from cloud-init.yml edit.)
- [ ] **AC-post-2.** For NEW Soleur users: optional smoke validation on a clean Hetzner project (`terraform apply` from empty state → `curl /api/inngest` returns 200/401 within 5 min of cloud-init completion). Documented in the runbook but not enforced in this PR (Tier 2 / #4126 makes this a CI check).
- [ ] **AC-post-3.** `gh issue close 4118` AFTER AC-post-1 passes. Per `wg-use-closes-n-in-pr-body-not-title-to` ops-remediation extension (Sharp Edge in plan/SKILL.md), the issue closure is operator-driven, not automatic at merge.

## Implementation Phases

### Phase 0 — AGENTS.core.md budget restoration (BLOCKING Phase 4)

**Operator brief constraint:** trim only 1-2 rules. The 571 B + 532 B lines are the two longest. Trim BOTH to ≤200 B each by lifting `Why:` + `How to apply:` prose to companion learning files.

Steps:

1. Create `knowledge-base/project/learnings/best-practices/2026-05-20-hr-observability-as-plan-quality-gate-why-and-how.md` containing the full prose lifted from the 571 B rule body — keep the 5-field schema (`liveness_signal`, `error_reporting`, `failure_modes`, `logs`, `discoverability_test`), the `WITHOUT SSH` constraint, the #4116 Better Stack incident framing, and the `skill-enforced: plan Phase 2.9 + deepen-plan Phase 4.7` cross-reference.
2. Create `knowledge-base/project/learnings/best-practices/2026-05-20-hr-tagged-build-workflow-needs-initial-tag-push-why-and-how.md` containing the full prose from the 532 B rule body — the `on.push.tags` semantics, the dead-code failure mode, the Phase 7 ship-step prescription, the #3973 reference, and a back-link to the existing sibling at `knowledge-base/project/learnings/2026-05-18-plan-baked-in-operator-ssh-violated-iac-rule.md`.
3. Edit `AGENTS.core.md` line 38 (the observability rule) to the trimmed shape:
   ```markdown
   - Every plan touching production code/infra MUST declare a `## Observability` block (5 fields) with a `discoverability_test.command` that runs WITHOUT SSH [id: hr-observability-as-plan-quality-gate] [skill-enforced: plan Phase 2.9 + deepen-plan Phase 4.7]. **Why:** #4116 — see `knowledge-base/project/learnings/best-practices/2026-05-20-hr-observability-as-plan-quality-gate-why-and-how.md`.
   ```
   Target byte count: ≤ 200 B (measure with `awk '/hr-observability-as-plan-quality-gate/ {print length($0)}'`).
4. Edit `AGENTS.core.md` line 15 (the tagged-build rule) to the trimmed shape:
   ```markdown
   - PRs adding a `on.push.tags`-gated workflow MUST push the initial `vX.0.0` tag in the same PR or a sibling on-merge workflow [id: hr-tagged-build-workflow-needs-initial-tag-push]. **Why:** PR-A #3973 — see `knowledge-base/project/learnings/best-practices/2026-05-20-hr-tagged-build-workflow-needs-initial-tag-push-why-and-how.md`.
   ```
   Target byte count: ≤ 200 B.
5. File 2 tracker entries per `wg-when-an-audit-identifies-pre-existing`. Preferred: append to `scripts/agents-md-trim-trackers.txt` if it exists. Fallback: file 2 issues with label `chore/agents-md-trim`.
6. Run `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md`. Verify exit 0 AND `B_ALWAYS` ≤ 21849 AND status WARN (same as `main`).

**Budget arithmetic (verifiable at plan time):**

- Baseline (main, current): `B_ALWAYS = 21849`. Headroom = 151 B.
- After trim of rule 1: −371 B (571 → 200). New `B_ALWAYS` = 21478.
- After trim of rule 2: −332 B (532 → 200). New `B_ALWAYS` = 21146.
- After add of new rule (Phase 4, target ≤ 600 B; planned ~576 B): +576 B. New `B_ALWAYS` = 21722.
- Net vs. baseline: 21722 − 21849 = **−127 B** (under baseline). WARN tier persists. AC0 satisfied.

### Phase 1 — Cloud-init runcmd block (Tier 1 code)

Insert the new runcmd block in `apps/web-platform/infra/cloud-init.yml` between the plugin-seed block (around line 398, `> /mnt/data/plugins/soleur/.seed-complete`) and the final `- |` block that does `docker run -d --name soleur-web-platform` (around line 400). The new block must complete BEFORE the web container starts, so Inngest is listening on `:8288` when the container's `INNGEST_BASE_URL=http://host.docker.internal:8288` first resolves.

Proposed block (final form will be vetted against `inngest.test.sh`):

```yaml
  # Bootstrap Inngest server on first boot (#4118, Tier 1).
  # Pinned image tag tracks apps/web-platform/infra/inngest.tf:locals.inngest_cli_version
  # (image tag = bootstrap-script version; inngest-cli version is sourced from
  # the image's Config.Env at run time).
  # Upgrades go through the deploy webhook path (push vinngest-vX.Y.Z tag).
  - |
    set -e
    docker pull ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0
    EXTRACT_DIR=$(mktemp -d)
    EXTRACT_CONTAINER="inngest-bootstrap-extract-$$"
    cleanup() { docker rm -f "$EXTRACT_CONTAINER" >/dev/null 2>&1 || true; rm -rf "$EXTRACT_DIR"; }
    trap cleanup EXIT
    docker create --name "$EXTRACT_CONTAINER" ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0
    docker cp "$EXTRACT_CONTAINER:/inngest-bootstrap.sh" "$EXTRACT_DIR/inngest-bootstrap.sh"
    image_env=$(docker inspect ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0 -f '{{range .Config.Env}}{{println .}}{{end}}')
    docker rm "$EXTRACT_CONTAINER"
    chmod +x "$EXTRACT_DIR/inngest-bootstrap.sh"
    INNGEST_CLI_VERSION=$(printf '%s\n' "$image_env" | grep '^INNGEST_CLI_VERSION=' | cut -d= -f2-)
    INNGEST_CLI_SHA256=$(printf '%s\n' "$image_env" | grep '^INNGEST_CLI_SHA256=' | cut -d= -f2-)
    env "INNGEST_CLI_VERSION=$INNGEST_CLI_VERSION" "INNGEST_CLI_SHA256=$INNGEST_CLI_SHA256" \
      bash "$EXTRACT_DIR/inngest-bootstrap.sh"
    trap - EXIT
    cleanup
```

Note the **trap-based cleanup**: the issue body's proposed snippet leaves `EXTRACT_DIR` on disk if any intermediate command fails. The improved form (`trap cleanup EXIT` + explicit final `cleanup` + `trap - EXIT`) is idempotent under partial failure AND under success — matches the existing soleur-plugin-seed block's pattern (`apps/web-platform/infra/cloud-init.yml:387-396`).

#### Alternative path: base64-embed via `templatefile()` (Deepen-pass recommendation)

Per Deepen-Pass Finding §3, the codebase has a 7-precedent pattern (`apps/web-platform/infra/server.tf:31-38`) for shipping shell scripts via `base64encode(file("…sh"))` + `write_files:` block. The `inngest-bootstrap.sh` script's own header comment EXPLICITLY anticipates this delivery (line 22). The alternative form:

```hcl
# In apps/web-platform/infra/server.tf templatefile(…) call:
templatefile("${path.module}/cloud-init.yml", {
  # …existing variables…
  inngest_bootstrap_script_b64 = base64encode(file("${path.module}/inngest-bootstrap.sh"))
  inngest_cli_version          = local.inngest_cli_version  # "v1.19.4"
  inngest_cli_sha256           = local.inngest_cli_sha256
})
```

```yaml
# In write_files: section of cloud-init.yml (near existing ci-deploy.sh write_file):
  - path: /usr/local/bin/inngest-bootstrap.sh
    encoding: b64
    content: ${inngest_bootstrap_script_b64}
    owner: root:root
    permissions: '0755'

# In runcmd: section (positioned after Docker line ~318 but freed from OCI-pull dep):
  - |
    set -e
    INNGEST_CLI_VERSION="${inngest_cli_version}" \
    INNGEST_CLI_SHA256="${inngest_cli_sha256}" \
      bash /usr/local/bin/inngest-bootstrap.sh
```

**Trade-off vs. issue-body OCI-pull path:**

- Pro: single source of truth (the .sh file on disk + `inngest.tf:locals`), zero first-boot network dependency, no Docker-timing dep, no version-axis split (OCI tag vs CLI version).
- Con: cloud-init.yml `user_data` size grows by ~270 lines of base64 (the .sh file). Hetzner's user_data limit is 32KB; current file ~13KB + ~10KB inngest-bootstrap.sh base64 = ~23KB. Safe headroom.
- Con: tag-triggered OCI image upgrades stop using cloud-init as a delivery path (still used by the deploy webhook for live upgrades — unaffected).

**`/work` decision point.** Per the operator brief, the issue-body snippet is the SCOPE. The base64 alternative is documented here as a P1 reviewer-callout: `/work` Phase 0 reads this section, weighs the trade-off, and either (i) implements the OCI-pull form (issue-body literal) OR (ii) implements the base64 form (codebase precedent + Deepen-pass recommendation). Both forms satisfy the issue's intent ("a fresh `terraform apply` installs Inngest in ONE apply"); the base64 form satisfies it more robustly.

### Phase 2 — Cloud-init test coverage

Add a shell test in `apps/web-platform/infra/inngest.test.sh` (or `cloud-init.test.sh` if absent) that asserts:

1. The new runcmd block exists in `cloud-init.yml` (grep for `docker pull ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0`).
2. The block sources `INNGEST_CLI_VERSION` from `Config.Env` (grep for `docker inspect.*Config.Env`).
3. The block uses `trap … EXIT` cleanup (grep for `trap cleanup EXIT`).
4. The block is positioned BEFORE the final `docker run -d --name soleur-web-platform` line (line number of new block < line number of soleur-web-platform `docker run`).
5. The embedded shell snippet, extracted via `awk` between the YAML `- |` delimiter and the next top-level `-` or `:`, passes `bash -n /tmp/<snippet>.sh`.

### Phase 3 — Tier 3 rule add

Insert in `AGENTS.core.md` after the existing `hr-all-infrastructure-provisioning-servers` rule (line 17) so the IaC-related rules cluster. Target shape (≤ 600 B):

```markdown
- Every production service in `apps/<app>/infra/` MUST come up on a one-shot `terraform apply` against empty state with zero operator post-apply actions [id: hr-fresh-host-provisioning-reachable-from-terraform-apply] [skill-enforced: plan Phase 2.8 + iac-plan-write-guard.sh]. If install requires a webhook trigger, tag push, or manual click, the install path MUST ALSO be embedded in `cloud-init.yml`'s `runcmd:` block (or an equivalent first-boot bootstrap). Pairs with `hr-tagged-build-workflow-needs-initial-tag-push` (tag exists) + `hr-all-infrastructure-provisioning-servers` (no manual SSH). **Why:** #4017/#4118 — see `knowledge-base/project/learnings/best-practices/2026-05-20-hr-fresh-host-provisioning-reachable-from-terraform-apply.md`.
```

Add the index pointer in `AGENTS.md` `## Hard Rules` section near `- [id: hr-all-infrastructure-provisioning-servers] → core`:

```markdown
- [id: hr-fresh-host-provisioning-reachable-from-terraform-apply] → core
```

### Phase 4 — Runbook update

Append to `knowledge-base/engineering/ops/runbooks/inngest-server.md`:

```markdown
## Fresh-host provisioning (#4118)

A new VM gets Inngest installed automatically by cloud-init's runcmd block.

Verification (no SSH required):
```bash
curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 https://web-platform.soleur.ai/api/inngest
```
Expected: `200` or `401`. Anything else: Inngest absent or unreachable; investigate `/var/log/cloud-init-output.log` on the host (via Hetzner console if SSH is also broken).

Upgrade path (existing operator workflow, unchanged):
1. Push `vinngest-vX.Y.Z` tag.
2. The GHA workflow builds the OCI image.
3. The operator triggers the deploy webhook `deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap vX.Y.Z`.
```

### Phase 5 — Lint + smoke + final budget check

- Run `python3 scripts/lint-agents-rule-budget.py` — expect exit 0, WARN tier same as `main`.
- Run `python3 scripts/lint-rule-ids.py` — expect exit 0.
- Run `yamllint apps/web-platform/infra/cloud-init.yml` (or Python YAML round-trip).
- Run `bash apps/web-platform/infra/inngest.test.sh` (extended in Phase 2).
- Final byte arithmetic check: log `B_ALWAYS` and confirm ≤ 21849.

### Phase 6 — PR open

PR body uses `Ref #4118` (NOT `Closes`). Sections:

- `## Summary` — 3 bullets: Tier 1 cloud-init, Tier 3 rule, Phase 0 trim.
- `## Tier 2 (deferred)` — link to #4126 with one-line "weekly disaster-recovery test deferred per scope."
- `## Prior attempts` — link to #4127 (closed) and #4143 (closed); note branches deleted.
- `## Verification` — paste the AC checklist (pre-merge + post-merge).
- `## Post-merge operator step` — explicit reminder: `curl /api/inngest` + `gh issue close 4118`.

## Test Strategy

- **Static (Phase 0/3 acceptance):** `lint-agents-rule-budget.py`, `lint-rule-ids.py` — both must exit 0.
- **Static (Tier 1 acceptance):** `yamllint` (or Python `yaml.safe_load`), `bash -n` on the extracted snippet.
- **Shell unit (Tier 1 acceptance):** `inngest.test.sh` extended with the 5 assertions in Phase 2.
- **Manual smoke (post-merge):** `curl /api/inngest` against prod (returns 200/401).
- **NOT in this PR:** the full `terraform apply` + cloud-init smoke on a clean Hetzner project. That is Tier 2 (#4126) — deferred.

## Risks & Sharp Edges

- **Cloud-init runs once, fail-loud is intentional.** If the new runcmd block fails (GHCR outage, SHA256 drift), cloud-init exits non-zero. The package audit (lines 253-275) does NOT cover the Inngest install path. Loud failure surfaces in `/var/log/cloud-init-output.log` + the existing observability gate (Better Stack heartbeat never registers → alert within 90 s).
- **The currently-running prod VM is unaffected by this PR.** `hcloud_server.web` has `ignore_changes = [user_data]` (`server.tf:60`). The fix is dead-on-disk until a VM is recreated. AC-post-1 confirms zero regression on the existing VM. (This is the reason for `Ref #4118` instead of `Closes`.)
- **Two distinct version axes.** OCI image tag (`v1.0.0`, bootstrap-script version) vs. inngest-cli version (`v1.19.4`, sourced from `Config.Env` at runtime). The comment in Phase 1 documents this; a future drift detector could grep for divergence between `cloud-init.yml`'s tag and `inngest.tf:inngest_cli_version`.
- **Trim target ≤200 B is aggressive but achievable.** Both target rules' essential semantics (`Every plan touching prod code/infra MUST declare an Observability block` + `PRs adding tag-triggered workflows MUST push the initial tag`) fit comfortably in 200 B once `Why:` + `How to apply:` move to companion learnings. The 600 B per-rule linter cap is the hard ceiling; 200 B is the operator's soft target.
- **AGENTS.md sidecar loader-class fit** (per the Sharp-Edge guidance in `plugins/soleur/skills/plan/SKILL.md:803-805` AND `plugins/soleur/skills/deepen-plan/SKILL.md:610-611` — kept as mirrored Sharp-Edge bullets, NOT promoted to a `cq-*` rule). The new rule is added to `AGENTS.core.md` (always-loaded), so loader-class fit is trivially satisfied: it loads on every session class (`core+docs-only`, `core+rest`, `core+docs-only+rest`). No demotion is proposed. **Deepen-pass note:** an earlier draft of this plan cited a fabricated rule ID `cq-agents-md-trim-loader-class-fit` — corrected.
- **The trimmed rules retain their `[skill-enforced: …]` markers.** Critical — the lint at `scripts/lint-agents-enforcement-tags.py` (if present) checks that any skill claiming `[skill-enforced: <skill> <phase>]` actually has the phase. Trim does NOT change these tags; only `Why:` + `How to apply:` prose moves.
- **`bash -n` on cloud-init.yml.** Per Sharp Edges in plan/SKILL.md: do NOT use `bash -n cloud-init.yml` — it parses YAML as bash and fails at the `runcmd:` header. Use `yamllint` for YAML and extract the runcmd snippet to `bash -c '…'` or `bash -n /tmp/snippet.sh` for the embedded shell.
- **PR body: `Ref #4118` not `Closes`.** Per the ops-remediation extension of `wg-use-closes-n-in-pr-body-not-title-to`: Tier 1 is dead-on-disk until operator action; auto-closing at merge produces a false-resolved state. Issue closure lives in the post-merge `gh issue close 4118` step.
- **Cloud-init `runcmd:` is bash-via-dash by default.** Cloud-init's `- |` blocks run under `/bin/sh` = `dash` on Ubuntu Noble. The proposed snippet uses bash-isms (`mktemp -d`, `$$`, `set -e`, `trap`) — all of which are POSIX-portable. Verify with `bash -n` AND `dash -n` on the extracted snippet during Phase 2.
- **Tracker filing per `wg-when-an-audit-identifies-pre-existing`.** Two rules trimmed = two trackers, not one aggregate. Per the rule body: "Don't just note them in conversation — file them." Plan acceptance criterion AC0.3 enforces this.

## Alternative Approaches Considered

| Approach | Rejected because |
| --- | --- |
| Demote `hr-observability-as-plan-quality-gate` and `hr-tagged-build-workflow-needs-initial-tag-push` from `core` to `rest` | Both are HARD rules (`hr-*`). Per CPO sign-off PR #3496 condition 3, `hr-*` rules MUST NOT be demoted core→rest. Trim-via-learning-extraction is the canonical path. |
| Trim 6 rules to recover ~600 B with shallower cuts | Overkill for a 425 B need. Each trim has overhead (lint, tracker, learning file, review). 2 trims hit the target with room to spare. |
| Retire (not just trim) one of the two longest rules | Both rules are load-bearing and recently added (PR #4085 / PR for #4116). Retirement is irreversible (`cq-rule-ids-are-immutable`). Trim preserves all enforcement. |
| Add the Inngest install to `inngest.tf` as a `terraform_data` SSH provisioner (mirror of `terraform_data.deploy_pipeline_fix`) | Mixes apply-time SSH provisioner with cloud-init bootstrap. The cloud-init path is strictly cleaner: no apply-time SSH dependency, no firewall-allowlist drift risk (`hr-ssh-diagnosis-verify-firewall`), and works for new Soleur users without an operator on the keyboard. |
| Bake the Inngest bootstrap into the soleur-web-platform Docker image | The image is consumed by the container, not by the host. Inngest must run on the host (per ADR-030's self-hosted decision + the existing `INNGEST_BASE_URL=http://host.docker.internal:8288` wiring). Container-bound install does not satisfy the host-bound requirement. |
| Ship Tier 1 + Tier 2 together (also include the weekly DR test) | Tier 2 needs design decisions Tier 1 doesn't (Hetzner test-project provisioning, budget caps, failure routing). #4126 captures the deferral with explicit re-evaluation criteria. Tier 1 closes the silent-break gap immediately. |

## Hypotheses

(No SSH/network-outage trigger pattern matched in the feature description. Skipped per Phase 1.4 of plan-skill.)

## Prior attempts

- **PR #4127 (closed).** Earlier attempt on this work; branch `feat-one-shot-cloud-init-inngest-4118` deleted. Verified via `gh pr view 4127 --json state,title`. Unknown specific failure mode; this plan supersedes.
- ~~**PR #4143 (closed).**~~ **REMOVED at deepen-pass.** `gh pr view 4143` resolves to `WIP: feat-one-shot-agents-budget-recovery-4142` — a sibling task, NOT a prior attempt on #4118. The operator brief cited it; verification per the deepen-plan "every PR/issue number is verified live via `gh pr view`" gate caught the misattribution. PR body MUST reflect only #4127 as a prior attempt.

The Phase 0 SLIM trim (1-2 rules, not 6) is the key learning from the prior attempt as conveyed by the operator brief.

## Definition of Done

- All pre-merge ACs (AC0 through AC9) checked.
- PR merged with `Ref #4118` in body.
- Tier 2 followup (#4126) remains open until the weekly DR test ships.
- Post-merge: operator runs AC-post-1 (`curl /api/inngest`), confirms 200/401, then `gh issue close 4118`.
