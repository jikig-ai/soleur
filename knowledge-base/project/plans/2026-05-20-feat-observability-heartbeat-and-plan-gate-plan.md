---
title: "observability: Better Stack heartbeat fix + plan-skill observability gate"
type: feat
date: 2026-05-20
issue: 4116
branch: feat-one-shot-observability-heartbeat-4116
lane: cross-domain
classification: ops-remediation
requires_cpo_signoff: false
---

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** 7 (Research Reconciliation, Proposed Solution Part 1, Workflow Gate, AGENTS.md budget, Apply path, Risks, Sharp Edges)
**Quality checks applied:** AGENTS.md rule-ID active/retired sweep, AGENTS.md byte-cap budget probe, GitHub label/PR/issue verification, cloud-init `doppler` install-path grep, `inngest.test.sh` shape inspection, loader-class fit (`.claude/hooks/session-rules-loader.sh:88-126`).

### Key Improvements (from deepen pass)

1. **`doppler` install-path discrepancy surfaced.** Cloud-init installs `doppler` to `/usr/local/bin/doppler` (`apps/web-platform/infra/cloud-init.yml:290`), but `inngest-server.service` line 137 references `/usr/bin/doppler`. The plan now prescribes `command -v doppler`-resolved path interpolated at bootstrap time, NOT a hardcoded path. This corrects a latent class-of-bug the original plan would have re-shipped.
2. **AGENTS.core.md is ALREADY over the 22 000-byte cumulative cap** (`B_ALWAYS=24499 > 22000`, output of `python3 scripts/lint-agents-rule-budget.py`). The plan now includes an explicit `Phase 4.0` to land **before** the new rule edit: either (a) retire one `wg-*` rule via `scripts/retired-rule-ids.txt` per `cq-rule-ids-are-immutable`'s retirement protocol, OR (b) demote one already-skill-enforced `wg-*` rule from `core` to `rest` after loader-class-fit verification. Without this prework, the rule add will fail CI lint and force a workflow regression.
3. **Original rule body was 879 bytes — over the 600-byte cap (`cq-agents-md-why-single-line`).** The deepened plan ships a trimmed 487-byte form that preserves the load-bearing semantics (5-field schema + SSH disallowance + skill-enforced tag + Why citation).
4. **PR/issue/SHA citations resolved live.** Issue #4116 confirmed `OPEN` via `gh issue view 4116 --json state`. No PR #4116 yet (the deepen check `gh pr view 4116` returns `Could not resolve to a PullRequest` — confirms #4116 is exclusively an issue number).
5. **Labels verified.** `domain/engineering`, `bug`, `priority/p2-medium` confirmed via `gh label list --limit 200`. No new labels prescribed.
6. **Loader-class fit verified.** `core` placement is correct (rule fires on docs-only edits when plan-skill SKILL.md changes AND on code/infra edits when feature plans land — only `core` is loaded across all three classes per `.claude/hooks/session-rules-loader.sh:115-126`). Demotion to `rest` would silently no-op on docs-only plan edits.
7. **`inngest.test.sh` already exists** with TF-shape assertions; the new tests extend the existing harness (no new test file needed).
8. **Cloud-init Doppler install path checked.** `/usr/local/bin/doppler` is canonical (cloud-init); `/usr/bin/doppler` in the existing `inngest-server.service` is either (a) reliant on an unverified PATH symlink, OR (b) a latent bug. Phase 0 of the deepened plan adds a `which doppler` host-side verification step before writing the new HEARTBEAT_UNIT.

### New Considerations Discovered

- The plan's own `## Observability` block uses `https://deploy.soleur.ai/hooks/deploy-status` as the discoverability test endpoint, which is gated by Cloudflare Access. The discoverability-test command MUST work for any operator with CF-Access credentials; document that as the canonical operator-context, NOT a special-case.
- A trim-or-retire decision on AGENTS.core.md is now blocking the new rule's landing. Plan-review should weigh this as P1 — without it, the lint fails CI at PR open time.

# observability: Better Stack heartbeat fix + plan-skill observability gate

Three-part plan:

1. **Bug #9 fix** — `inngest-heartbeat.service` has been failing every 60s since 2026-05-19T16:21Z because `inngest-heartbeat.sh` reads `$INNGEST_HEARTBEAT_URL` from `/etc/default/inngest-server` (where the substrate-fix in PR #4085 only writes Doppler bootstrap env). Wrap the heartbeat script in `doppler run` to mirror the pattern already used by `inngest-server.service` (line 137 of `inngest-bootstrap.sh`).
2. **Workflow gate** — add a `## Observability` block to the plan-skill issue templates, a corresponding plan-skill phase (`Phase 2.9 Observability Quality Gate`) that refuses to ship a plan with TODO/placeholder/SSH-only observability, and AGENTS.md hard rule `hr-observability-as-plan-quality-gate` in `AGENTS.core.md` (loaded on every session).
3. **Backfill** — populate the new `## Observability` block in the two TR9 cron specs (`feat-cron-follow-through-monitor-tr9`, `feat-agent-loop-crons-inngest-tr9`) so the gate isn't retroactively bypassed.

## Overview

Issue #4116 (post-mortem of #4017 substrate cascade) names a single bug instance (broken Better Stack heartbeat) AND the structural workflow gap that lets the bug class survive: plan-time review weighs features on functionality, security, and IaC axes but never asks "what tells the operator this is broken WITHOUT SSH?". The fix is two-layered — repair the heartbeat itself, then codify the gate so the next plan can't ship in the same blind spot.

The bug is the cheapest possible witness: a heartbeat resource the operator pays for (Better Stack), wired into Terraform (`apps/web-platform/infra/inngest.tf:108`), provisioned at apply time, broken at first execution because the env-injection assumption in `inngest-bootstrap.sh:179` (heartbeat.service `EnvironmentFile=/etc/default/inngest-server`) is decoupled from the env-population assumption (line 226-230 writes only `DOPPLER_TOKEN`, `DOPPLER_CONFIG_DIR`, `DOPPLER_ENABLE_VERSION_CHECK`). The systemd `EnvironmentFile=` directive does not error on missing keys — it loads what's there and silently leaves `$INNGEST_HEARTBEAT_URL` empty. `curl` with empty URL errors `(3) URL rejected: Malformed input to a URL function` every 60s for 16+ hours.

Same env-injection class as #4017 substrate bugs #3 and #5 (`DOPPLER_TOKEN` missing from `/etc/default/inngest-server`, fixed by reading from sibling `/etc/default/webhook-deploy`). The pattern is now identified: `EnvironmentFile=` decoupled from the env-population path is a structural trap; the canonical pattern is `doppler run` wrapping at ExecStart time so the prd Doppler config is the source of truth, exactly as `inngest-server.service` already does (line 137).

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim                                                                                    | Reality (file:line)                                                                                                                                                                            | Plan response                                                                                                                  |
| --------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| "Wrap `inngest-heartbeat.sh` in `doppler run`"                                                       | `inngest-bootstrap.sh:165-169` writes a HEARTBEATSCRIPTEOF script that `exec /usr/bin/curl … "$INNGEST_HEARTBEAT_URL"`. The `doppler` CLI is installed by cloud-init (referenced at line 137). | Recommended fix: change `ExecStart=` in `HEARTBEAT_UNIT` to invoke `doppler run --project soleur --config prd -- $HEARTBEAT_SCRIPT`; keep `EnvironmentFile=` for `DOPPLER_TOKEN/DOPPLER_CONFIG_DIR/DOPPLER_ENABLE_VERSION_CHECK`. Mirrors `inngest-server.service` exactly. |
| "AGENTS.md rule `hr-observability-as-plan-quality-gate`"                                            | `AGENTS.core.md` currently has 33 hard rules + 22 workflow gates; loader-class fit per `.claude/hooks/session-rules-loader.sh:88-126`.                                                          | New rule lives in `AGENTS.core.md` (always-loaded); fires on plan-skill edits (docs-only class) AND on every feature plan irrespective of class. Sibling rules: `hr-all-infrastructure-provisioning-servers`, `hr-no-dashboard-eyeball-pull-data-yourself`. |
| "Plan skill template … checks for the `## Observability` block and refuses to proceed without it"   | `plugins/soleur/skills/plan/references/plan-issue-templates.md` has MINIMAL/MORE/A-LOT templates; `plugins/soleur/skills/plan/SKILL.md` has section 2.6 (`User-Brand Impact`), 2.7 (GDPR), 2.8 (IaC). | Add Phase 2.9 `Observability Quality Gate` in `plan/SKILL.md` (mirrors 2.6/2.7/2.8 structure). Insert `## Observability` template into all three detail levels of `plan-issue-templates.md`. Add deepen-plan halt condition (Phase 4.x) symmetric to the User-Brand-Impact halt (Phase 4.6). |
| "Backfill TR9 cron migrations (PR-1 + PR-2) with the observability block in their respective spec docs" | Specs at `knowledge-base/project/specs/feat-cron-follow-through-monitor-tr9/spec.md` AND `knowledge-base/project/specs/feat-agent-loop-crons-inngest-tr9/spec.md`.                              | Backfill `## Observability` block into both spec.md files in this PR (small, additive — no plan-skill flow change needed for these already-merged features). |
| "Existing observability inventory complete in issue body"                                            | Issue table lists 6 surfaces. Verified: `apps/web-platform/sentry.{client,server,edge}.config.ts` exist; `apps/web-platform/infra/sentry/cron-monitors.tf` exists; `betteruptime_heartbeat.inngest_prd` at `inngest.tf:108`; `cat-deploy-state.sh` at `apps/web-platform/infra/`; webhook deploy URL `https://deploy.soleur.ai/hooks/deploy-status`. | No corrections. Inventory accurate. |
| "Same env-injection bug class as #4017 substrate bugs #3 + #5"                                      | `inngest-bootstrap.sh:208-234` reads `DOPPLER_TOKEN` from sibling `/etc/default/webhook-deploy`; writes only 3 keys to `/etc/default/inngest-server`. `INNGEST_HEARTBEAT_URL` is in Doppler prd (see `inngest.tf:163-173`) but never materialized in any `/etc/default/*` file. | Confirmed. The fix collapses both leaves into one: `doppler run` wrapping at ExecStart removes the need to materialize prd secrets into `/etc/default/*` at all. |

## Open Code-Review Overlap

Querying `gh issue list --label code-review --state open --limit 200`. Files this plan will edit:

- `apps/web-platform/infra/inngest-bootstrap.sh`
- `apps/web-platform/infra/inngest.test.sh`
- `plugins/soleur/skills/plan/SKILL.md`
- `plugins/soleur/skills/plan/references/plan-issue-templates.md`
- `plugins/soleur/skills/deepen-plan/SKILL.md`
- `AGENTS.core.md`
- `knowledge-base/project/specs/feat-cron-follow-through-monitor-tr9/spec.md`
- `knowledge-base/project/specs/feat-agent-loop-crons-inngest-tr9/spec.md`

Operator runs the query at plan-finalization time. No overlap expected on `inngest-bootstrap.sh` (PR #4085 was 5 days ago); no overlap expected on plan/deepen-plan SKILL.md (no open code-review label on these surfaces); confirm at `/work` Phase 0. Records `None` here pending the live query.

## Problem Statement

**Concrete bug (operator-visible).** `inngest-heartbeat.service` has been emitting `curl: (3) URL rejected: Malformed input to a URL function` every 60 seconds since 2026-05-19T16:21Z. The script reads `$INNGEST_HEARTBEAT_URL` directly from `EnvironmentFile=/etc/default/inngest-server`, but PR #4085 (substrate cascade fix) writes only `DOPPLER_TOKEN`, `DOPPLER_CONFIG_DIR`, and `DOPPLER_ENABLE_VERSION_CHECK` into that file. The Better Stack heartbeat (`betteruptime_heartbeat.inngest_prd`, defined in `inngest.tf:108`) — the ONLY external liveness signal for the self-hosted Inngest server — has been silently dark for 16+ hours.

The heartbeat is currently `paused = true` (`inngest.tf:129`), set at apply time to avoid a false alert before first ping. The operator never unpaused it because the heartbeat-fire failure was masked by the pause. Two failure modes telescoped: (a) heartbeat-pause-not-unpaused leaves the resource dark by design, (b) heartbeat-script-broken would have surfaced as a `(3)` failure if the pause had been lifted. Even after we fix the script, the Better Stack pause must be lifted for the signal to reach an inbox.

**Structural workflow gap.** The substrate cascade work (#4017 → #4085 → #4093 → #4104 → #4111) addressed five distinct env-injection / config-cascade bugs but none of those PRs surfaced the broken heartbeat. Reason: no plan-time review step asks "what tells the operator this is broken WITHOUT SSH?". Sentry cron monitors (`apps/web-platform/infra/sentry/cron-monitors.tf`) cover the daily-triage + follow-through fires; container `HEALTHCHECK` covers the Docker app; nothing covers the Inngest server's external liveness between cron fires. The features that introduced these dark zones (PR-F #3940 for Inngest, PR-1/PR-2 for the TR9 crons) all passed their own AC chains — observability dark zones are not part of any AC.

The fix at the plan-time-gate layer is to require every feature to declare its observability surface in a structured `## Observability` block (per issue body schema) and refuse to ship a plan with `TODO`, `manual operator check`, or "SSH and run X" in any required field.

## Proposed Solution

### Part 1: Bug #9 (Heartbeat script fix)

Modify `apps/web-platform/infra/inngest-bootstrap.sh:172-181` to wrap the heartbeat script's ExecStart in `doppler run`, mirroring `inngest-server.service`'s pattern at line 137. **Important deepen-pass finding**: cloud-init installs `doppler` to `/usr/local/bin/doppler` (`apps/web-platform/infra/cloud-init.yml:290`), while `inngest-server.service:137` hardcodes `/usr/bin/doppler`. Either there is a PATH symlink already in place (verifiable on the host with `readlink -f /usr/bin/doppler 2>/dev/null`) or `inngest-server.service` is also latently broken in a way that hasn't surfaced. The deepened plan resolves this by sniffing the install path at bootstrap time:

```diff
- cat > "$HEARTBEAT_UNIT" <<HEARTBEATEOF
- [Unit]
- Description=Inngest server heartbeat ping to Better Stack
- After=network-online.target
-
- [Service]
- Type=oneshot
- EnvironmentFile=/etc/default/inngest-server
- ExecStart=${HEARTBEAT_SCRIPT}
- HEARTBEATEOF
+ # Resolve the doppler binary path at bootstrap time. Cloud-init installs to
+ # /usr/local/bin/doppler, but inngest-server.service:137 hardcodes /usr/bin/
+ # doppler — interpolating the actual path here avoids inheriting that latent
+ # discrepancy.
+ DOPPLER_BIN="$(command -v doppler 2>/dev/null || true)"
+ if [[ -z "$DOPPLER_BIN" ]]; then
+   log "ERROR: doppler CLI not found on PATH — cloud-init must install /usr/local/bin/doppler before bootstrap"
+   exit 1
+ fi
+
+ cat > "$HEARTBEAT_UNIT" <<HEARTBEATEOF
+ [Unit]
+ Description=Inngest server heartbeat ping to Better Stack
+ After=network-online.target
+
+ [Service]
+ Type=oneshot
+ EnvironmentFile=/etc/default/inngest-server
+ ExecStart=${DOPPLER_BIN} run --project soleur --config prd -- ${HEARTBEAT_SCRIPT}
+ HEARTBEATEOF
```

Optional follow-up: replace the hardcoded `/usr/bin/doppler` at line 137 (existing `inngest-server.service`) with the same `${DOPPLER_BIN}` interpolation in the same PR — pattern parity, zero behavior change for hosts where `/usr/bin/doppler` already resolves. File scope-out issue if the operator wants this split.

Why `doppler run` vs. materializing `INNGEST_HEARTBEAT_URL` into `/etc/default/inngest-server`:

- **Single source of truth.** Doppler prd is already the canonical store for `INNGEST_HEARTBEAT_URL` (`doppler_secret.inngest_heartbeat_url_prd` at `inngest.tf:163`). Materializing into a host file duplicates the value and creates a drift surface (rotate in Doppler, host file stale).
- **Pattern parity.** `inngest-server.service` already uses `doppler run --project soleur --config prd -- /usr/bin/bash -c '…'` for the same reason. Heartbeat unit should match.
- **No new failure mode at bootstrap.** `doppler` CLI is already installed by cloud-init and verified by the existing inngest-server.service start. If `doppler` is broken, `inngest-server.service` is also broken — heartbeat-pre-server-start is the right ordering already.

The bootstrap script's bug-fix delivery is automated via the existing build → tag → OCI image → deploy webhook → bootstrap re-run pipeline (`build-inngest-bootstrap-image.yml` is triggered by `vinngest-v*.*.*` tags; the deploy webhook fires `ci-deploy.sh inngest …` which re-runs the bootstrap idempotently on the host). No `ssh root@` step needed.

**Heartbeat pause lift.** After the bootstrap re-run lands and the script is verified emitting `200 OK` against Better Stack, the operator unpauses the `betteruptime_heartbeat.inngest_prd` resource via the Better Stack UI. The TF `lifecycle.ignore_changes = [paused]` at `inngest.tf:135-137` prevents subsequent applies from reverting the unpause. This is a post-merge step (not automatable via the existing TF apply — `paused = true` in the TF body is the *initial* state, and UI-unpause is the documented runbook path).

### Part 2: Workflow gate

**New plan-skill phase: `Phase 2.9 — Observability Quality Gate`** (insert in `plan/SKILL.md` after Phase 2.8 IaC routing gate). Body:

> Every plan whose Files-to-Edit set includes a code-class file under `apps/*/server/`, `apps/*/src/`, `plugins/*/scripts/`, OR introduces ANY new infrastructure surface (per Phase 2.8 trigger set) MUST emit a `## Observability` section per the schema below. The plan MUST NOT contain `TODO`, `manual operator check`, `SSH and run X`, or any operator-keyboard verb in the `discoverability_test` field. A feature that requires SSH to verify observability is a feature without observability.
>
> Plans for pure-docs changes (no Files-to-Edit in code/infra classes) skip this gate silently.

**Schema** (verbatim from issue body, lightly normalized):

```yaml
liveness_signal:
  what:            # e.g. "Better Stack heartbeat / Sentry cron monitor / Docker HEALTHCHECK"
  cadence:         # e.g. "60s / daily / per-run"
  alert_target:    # e.g. "operator email / Sentry issue / Discord ops channel"
  configured_in:   # path to TF/yaml/code where this is set up (e.g. apps/web-platform/infra/inngest.tf:108)

error_reporting:
  destination:     # Sentry project + DSN env var (e.g. "Sentry web-platform via SENTRY_DSN")
  fail_loud:       # what HTTP / log line tells the operator something is wrong

failure_modes:
  - mode:          # e.g. "Inngest queue depth > 100 SCHEDULED runs"
    detection:     # how is it noticed (NOT operator-eyeball)
    alert_route:   # who gets paged

logs:
  where:           # journalctl unit / docker logs / external aggregator path
  retention:       # how long until lost

discoverability_test:
  command:         # a single command the operator can run locally to read the observability state
  expected_output: # the canonical "everything OK" output
```

**Plan-issue-templates additions.** Add the `## Observability` block (with schema) to all three detail levels in `plugins/soleur/skills/plan/references/plan-issue-templates.md`, placed between `## User-Brand Impact` and `## Acceptance Criteria` (mirrors the User-Brand-Impact placement convention).

**Deepen-plan halt condition.** Add a `Phase 4.7 Observability Gate Verification` to `plugins/soleur/skills/deepen-plan/SKILL.md` symmetric to the User-Brand-Impact halt (Phase 4.6). If the plan body lacks `## Observability` OR any of the required fields contains `TODO`, `TBD`, `placeholder`, `manual operator check`, or an `ssh ` token, deepen-plan halts and emits an actionable error.

**AGENTS.md hard rule** (new, in `AGENTS.core.md`). Deepen-pass shrunk this from the original 879-byte draft (which exceeded `cq-agents-md-why-single-line`'s 600-byte cap) to a 487-byte form that preserves the load-bearing semantics:

> Every plan touching production code/infra MUST declare a `## Observability` block (liveness_signal, error_reporting, failure_modes, logs, discoverability_test) with a `discoverability_test.command` that runs without SSH [id: hr-observability-as-plan-quality-gate] [skill-enforced: plan Phase 2.9 + deepen-plan Phase 4.7]. Pure-docs plans skip. **Why:** #4116 — Better Stack heartbeat broken for 16+ hours; no plan-time gate asked "what tells the operator this is broken WITHOUT SSH?".

Byte count: 487 ≤ 600 (per `cq-agents-md-why-single-line`). Full schema details live in `plan/SKILL.md` Phase 2.9 — the rule is a pointer per the canonical pattern.

**CRITICAL deepen-pass finding — AGENTS.core.md is OVER BUDGET pre-rule-add.** Running `python3 scripts/lint-agents-rule-budget.py` at deepen-time emits:

```
[REJECT] B_ALWAYS=24499 > 22000 (AGENTS.md=4960 + AGENTS.core.md=19539).
Retire a rule via scripts/retired-rule-ids.txt or demote a wg-* rule
from AGENTS.core.md to AGENTS.rest.md.
```

The lint also flags two pre-existing rules over the per-rule 600-byte cap:
- `AGENTS.core.md:15` (1371 bytes) — `hr-tagged-build-workflow-needs-initial-tag-push`
- `AGENTS.core.md:55` (1039 bytes) — `wg-after-marking-a-pr-ready-run-gh-pr-merge`

These are pre-existing infractions (not introduced by this PR), but adding a new rule on a failing baseline is impossible — CI will reject any AGENTS.core.md edit until the cumulative budget is restored.

**Pre-rule trim plan (new Phase 4.0 below).** Choose ONE of:

- **Option (a) — Retire one rule.** Candidates: `wg-at-session-start-after-cleanup-merged` is single-action and already documented in `git-worktree/SKILL.md`; could be retired with a learning-file replacement. Cost: register in `scripts/retired-rule-ids.txt` per `cq-rule-ids-are-immutable`.
- **Option (b) — Demote one `wg-*` rule from core to rest** after loader-class-fit verification. Candidates with `[skill-enforced:]` tags that don't fire on docs-only PRs: `wg-after-a-pr-merges-to-main-verify-all` (already `[skill-enforced: ship Phase 7]`). Loader-class check: ship runs on code/infra change-class → `core+rest` loads → demotion is safe.
- **Option (c) — Body-trim the two oversized rules.** `hr-tagged-build-workflow-needs-initial-tag-push` (1371 → ~550 bytes by moving the long `Why:` body to its existing learning file) AND `wg-after-marking-a-pr-ready-run-gh-pr-merge` (1039 → ~500 bytes). Net byte recovery: ~1360 bytes, well above the 487 needed for the new rule.

**Recommended option: (c) body-trim.** Lowest blast-radius — doesn't change rule activation (no demotion), doesn't retire institutional knowledge (no retirement), restores both budget invariants in one stroke. Plan Phase 4.0 captures this. Plan-review should weigh in.

**Loader-class fit verification** (per the `hr-when-a-plan-specifies-relative-paths-e-g` and the `2026-05-15-multi-stage-premise-validation-compounds-and-agents-sidecar-loader-class-fit.md` learning):

- Rule fires at plan-time (plan-skill `SKILL.md` edits are `.md` → docs-only class — loads `core+docs-only`).
- Rule ALSO fires for any feature plan touching code/infra (code-class → `core+rest`; infra-class → `core+rest`).
- ⇒ AGENTS.core.md is the only sidecar that ALWAYS loads across all three classes. Placement in `core` is the only correct choice. `rest` would silently no-op for pure-docs plan edits; `docs-only` would silently no-op for code/infra plan edits.

### Part 3: Backfill TR9 cron specs

Add `## Observability` block to:

1. `knowledge-base/project/specs/feat-cron-follow-through-monitor-tr9/spec.md` (PR-2 scheduled-follow-through cron — Sentry cron monitor `scheduled-follow-through` at `apps/web-platform/infra/sentry/cron-monitors.tf`, weekday 09:00 UTC).
2. `knowledge-base/project/specs/feat-agent-loop-crons-inngest-tr9/spec.md` (PR-1 scheduled-daily-triage cron — Sentry cron monitor `scheduled-daily-triage`, daily 04:00 UTC).

Both specs already exist (merged features); the backfill is small + additive and lands in the same PR to demonstrate the schema with two worked examples. The PR body cites them as canonical observability-block exemplars.

## Alternative Approaches Considered

| Approach                                                                                                                | Rejected because                                                                                                                                                                                                                                |
| ----------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **(a)** Materialize `INNGEST_HEARTBEAT_URL` into `/etc/default/inngest-server` at bootstrap time                       | Duplicates the Doppler value into a host file; creates drift surface; breaks the existing pattern that `inngest-server.service` uses (`doppler run` wrapping).                                                                                  |
| **(b)** Embed `INNGEST_HEARTBEAT_URL` directly into the heartbeat unit's `Environment=` directive                       | Embeds a sensitive URL into a world-readable systemd unit; defeats the existing `sensitive = true` flag on the TF output (`inngest.tf:170`) and the indirection-via-script-file rationale documented at `inngest-bootstrap.sh:160-164`.       |
| **(c)** Replace Better Stack heartbeat with a Sentry cron monitor                                                       | Sentry cron monitors fire on per-cron schedule, not on continuous 60s liveness. Pattern-mismatch — `inngest-server.service` is a daemon, not a cron. Sentry cron monitors are the right pattern for the TR9 scheduled jobs (already in place). |
| **(d)** Defer the workflow gate to a separate PR after the bug fix                                                     | Loses the worked example — the issue body explicitly lists the gate as the load-bearing piece; splitting would weaken the AC chain ("rule added without the bug that motivated it"). The bug fix + the gate are co-load-bearing in one PR.       |
| **(e)** Make the new AGENTS.md rule a workflow-gate (`wg-*`) instead of a hard-rule (`hr-*`)                            | `wg-*` rules are demote-able to `rest`; this rule fires on docs-only plan edits as well as code/infra. Only `core`-tier `hr-*` placement loads on all three classes. Per `cq-agents-md-tier-gate`, cross-class session invariants are `hr-*`. |
| **(f)** Skip the heartbeat pause-lift step and revert the TF `paused = true` to `false`                                 | Plan author cannot test the script-fix's effect on Better Stack before merge — the TF apply happens post-merge and the pause-lift is the only check that the script is actually emitting `200 OK`. UI-unpause is the documented runbook path.   |

## User-Brand Impact

- **If this lands broken, the user experiences:** No direct user-facing artifact. The broken heartbeat is operator-only observability; the Inngest server itself (which processes CFO autonomous-draft from Stripe webhooks, agent-loop crons, daily-triage) continues to run. The risk is *operator-blind to a future Inngest server crash* — if Inngest goes down between cron fires, the operator won't know until the next user-visible workflow (e.g., a Stripe webhook handoff) fails, by which point user-impact has accumulated.
- **If this leaks, the user's [data / workflow / money] is exposed via:** No leak path. The fix uses `doppler run` to materialize `INNGEST_HEARTBEAT_URL` at process-start (existing pattern); the URL stays sensitive in Doppler. No new exposure surface.
- **Brand-survival threshold:** `aggregate pattern`. Operator-only observability dark zones aggregate over time (PR-F shipped a dark heartbeat 2 days ago; the substrate cascade made it worse, not better). The brand-survival concern is "operator runs in the dark on critical infrastructure for weeks", not "single user incident". Per the lifecycle staging in `plan/SKILL.md` 2.6 Step 3, `aggregate pattern` does not require per-PR CPO sign-off.

## Infrastructure (IaC)

### Terraform changes

None. The only TF surface in scope (`inngest.tf:108-138`) is unchanged. The fix is in `inngest-bootstrap.sh` (which is the IaC-managed host-resident script, delivered via OCI image build + deploy webhook — not via `terraform apply`).

### Apply path

Per `plan/SKILL.md` Phase 2.8, the apply path is the existing **idempotent bootstrap re-run** pattern (option (b) in the IaC section's three apply paths):

1. PR merges. `build-inngest-bootstrap-image.yml` is NOT auto-triggered (it fires on `vinngest-v*.*.*` tag push, not on main-merge).
2. Post-merge, operator (or ship-skill Phase 7) pushes a `vinngest-v<bumped-version>` tag → builds OCI image with the fixed bootstrap script embedded.
3. Operator (or ship-skill) fires the deploy webhook: `curl -s https://deploy.soleur.ai/hooks/deploy --data '{"target":"inngest","tag":"vX.Y.Z"}'` (canonical form documented at `apps/web-platform/infra/hooks.json.tmpl`).
4. `ci-deploy.sh`'s `case "inngest")` branch pulls + runs the OCI image; the image's entrypoint is the fixed `inngest-bootstrap.sh` which (a) detects the existing version mismatch path, (b) writes the new HEARTBEAT_UNIT, (c) `systemctl daemon-reload` + `systemctl restart inngest-heartbeat.timer`.
5. Within 60 seconds, the heartbeat script fires successfully (`doppler run` resolves `$INNGEST_HEARTBEAT_URL` from prd). Better Stack receives the ping but, since `paused = true`, does not record it visibly yet.
6. Operator unpauses `betteruptime_heartbeat.inngest_prd` via Better Stack UI. TF `lifecycle.ignore_changes = [paused]` prevents revert.
7. Within next 60 seconds, Better Stack records the ping; the heartbeat shows green in the Better Stack dashboard AND in the `inngest_prd` resource state.

Expected wall-clock downtime: zero (the bootstrap re-run pauses + restarts `inngest-server.service` for ~5s for version-bump drain, but the *heartbeat* unit is independent; heartbeat fires at next-timer-tick after `systemctl restart` ≤ 60s).

### Distinctness / drift safeguards

- `paused = true` is initial-state only; `lifecycle.ignore_changes = [paused]` is already in place.
- `INNGEST_HEARTBEAT_URL` is `lifecycle.ignore_changes = [value]` (`inngest.tf:171`) — URL stable per heartbeat resource lifetime.
- No `dev` heartbeat resource exists (alpha-internal scope; dev environment shares Doppler `dev` config but has no Better Stack heartbeat). No `dev != prd` precondition added.

### Vendor-tier reality check

Better Stack free tier supports `betteruptime_heartbeat` (already in use). `betteruptime_policy` requires paid tier (gated by `var.betterstack_paid_tier`, default `false`). No tier changes required by this plan.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `inngest-bootstrap.sh` `HEARTBEAT_UNIT` block uses `ExecStart=/usr/bin/doppler run --project soleur --config prd -- ${HEARTBEAT_SCRIPT}` (verified via `grep -nE '^ExecStart=' apps/web-platform/infra/inngest-bootstrap.sh | grep -c 'doppler run'` returns `2` — server + heartbeat).
- [ ] `inngest.test.sh` extended with a unit-shape test: assert the generated `HEARTBEAT_UNIT` contains `doppler run` (RED→GREEN).
- [ ] `plugins/soleur/skills/plan/SKILL.md` Phase 2.9 exists (header `### 2.9. Observability Quality Gate`); body names the 5 required schema fields; declares pure-docs skip exception.
- [ ] `plugins/soleur/skills/plan/references/plan-issue-templates.md` MINIMAL/MORE/A-LOT templates each contain a `## Observability` section between `## User-Brand Impact` and `## Acceptance Criteria` (verified via three separate `grep -c '## Observability'` invocations returning `1` each in their respective fence blocks).
- [ ] `plugins/soleur/skills/deepen-plan/SKILL.md` Phase 4.7 exists with the halt-condition body (TODO/TBD/placeholder/manual/ssh detection).
- [ ] `AGENTS.core.md` contains the new rule with `[id: hr-observability-as-plan-quality-gate]` AND `[skill-enforced: plan Phase 2.9 + deepen-plan Phase 4.7]` tags; rule body ≤ 600 bytes (per `cq-agents-md-why-single-line`).
- [ ] **AGENTS.md budget restored.** Phase 4.0 trim work GREEN: `python3 scripts/lint-agents-rule-budget.py` exits 0 with `B_ALWAYS ≤ 22000` AND no per-rule body exceeds 600 bytes. Verified by running the lint after Phase 4.0 commit AND after Phase 4 commit (rule add). Both runs must pass independently.
- [ ] `python3 scripts/lint-rule-ids.py` passes (rule ID format, retired-ID non-resurrection check).
- [ ] `bash inngest.test.sh` passes with the two new heartbeat tests GREEN.
- [ ] `knowledge-base/project/specs/feat-cron-follow-through-monitor-tr9/spec.md` and `feat-agent-loop-crons-inngest-tr9/spec.md` each contain a `## Observability` section with all 5 schema fields filled (no TODO/TBD).
- [ ] PR body uses `Ref #4116` (NOT `Closes #4116`) per the ops-remediation guideline (Closes is set in post-merge step 4 below).

### Post-merge (operator)

Per the `plan/SKILL.md` automation-feasibility gate, steps 1-4 are automatable via `gh` / OCI tag push; step 5 (Better Stack UI unpause) is the only genuinely operator-driven step.

- [ ] **Automation: tag push.** `git tag vinngest-vX.Y.Z && git pushed --tags` (ship-skill Phase 7 handles this). Triggers `build-inngest-bootstrap-image.yml`. Automatable via `gh release create` in ship.
- [ ] **Automation: deploy webhook fire.** `curl -fsS -X POST https://deploy.soleur.ai/hooks/deploy --data '{"target":"inngest","tag":"vX.Y.Z"}'`. Automatable via ship-skill Phase 7 if a `deploy-inngest` follow-up automation is added (file scope-out issue if not in scope this PR).
- [ ] **Automation: verify heartbeat-service exit status.** `gh workflow run apply-deploy-pipeline-fix.yml` style — or, post-bootstrap, fire a `gh api repos/jikig-ai/soleur/actions/workflows/<workflow>.yml/runs` poll. For Inngest-bootstrap-specific verification: `curl -fsS https://deploy.soleur.ai/hooks/deploy-status | jq '.last_deploy.target == "inngest" and .last_deploy.exit_code == 0'` returns `true`. Automatable via ship Phase 7.
- [ ] **Automation: close #4116.** Once Better Stack heartbeat is unpaused AND green, run `gh issue close 4116 --comment "Resolved via PR #<N>. Heartbeat green at <timestamp>."`. Ship-skill Phase 7 default close path.
- [ ] **Operator-driven (NOT automatable):** unpause `betteruptime_heartbeat.inngest_prd` via Better Stack UI. Automation: not feasible because Better Stack's Terraform provider does not expose a runtime "unpause" API the way the UI does (provider's `paused` is config-time only, and TF `lifecycle.ignore_changes` is precisely what prevents the operator-unpause from being reverted). The Better Stack free tier API does not document a programmatic unpause endpoint. Cheapest manual: 30 seconds in the Better Stack UI. Future improvement: file follow-up issue to evaluate `curl -X PATCH https://uptime.betterstack.com/api/v2/heartbeats/<id> -d '{"paused":false}'` against the documented v2 REST API.

## Test Scenarios

### Unit (RED → GREEN at `/work` Phase 1)

- **Given** the existing `inngest.test.sh` test harness, **when** the test asserts that the generated heartbeat unit body contains the substring `doppler run --project soleur --config prd`, **then** the test FAILS against current `inngest-bootstrap.sh` (RED) and PASSES after the Phase 1 edit (GREEN). Test name: `test_heartbeat_unit_uses_doppler_run`.
- **Given** a fresh `inngest-bootstrap.sh` execution in a fixture container, **when** the script writes `$HEARTBEAT_UNIT`, **then** the file contents include exactly one `ExecStart=` line and it begins with `/usr/bin/doppler run`. Test name: `test_heartbeat_unit_execstart_shape`.

### Integration (post-merge bootstrap re-run)

- **Given** the new OCI image is deployed via webhook, **when** `systemctl restart inngest-heartbeat.timer`, **then** the next `systemctl status inngest-heartbeat.service` invocation within 90s shows `Main process exited, code=exited, status=0/SUCCESS` (NOT `status=3/NOTIMPLEMENTED`). Operator-verifiable via `cat-deploy-state.sh` deploy-status payload extension OR `journalctl -u inngest-heartbeat.service --since "2 minutes ago" | grep -c 'status=0/SUCCESS'` returns `≥ 1`.
- **Given** the heartbeat service is firing 200 OK pings, **when** the operator unpauses the Better Stack resource, **then** Better Stack's dashboard shows the heartbeat as "Up" within 60 seconds, and the `betteruptime_heartbeat.inngest_prd` last-ping-at timestamp in `terraform refresh` output advances each minute.

### Workflow-gate verification

- **Given** the new Phase 2.9 in `plan/SKILL.md`, **when** the plan-skill drafts a plan whose Files-to-Edit includes any `apps/*/server/*.ts` path, **then** the plan-skill MUST emit a `## Observability` section in the draft. Manually verifiable by re-running `plan` against any open code-change issue post-merge and confirming the section appears.
- **Given** the new Phase 4.7 in `deepen-plan/SKILL.md`, **when** deepen-plan runs against a draft plan whose `## Observability.discoverability_test.command` field contains the string `ssh root@`, **then** deepen-plan halts and prints an actionable error containing the substring `discoverability_test.command must not require SSH`. Verifiable via a fixture plan in `plugins/soleur/skills/deepen-plan/test/` (add as part of Phase 3 task).
- **Given** the new `hr-observability-as-plan-quality-gate` rule in `AGENTS.core.md`, **when** `python3 scripts/lint-agents-rule-budget.py AGENTS.core.md` runs, **then** the script returns exit 0 (rule fits within budget headroom).

### Regression

- **Given** the existing `inngest-server.service` start path, **when** the bootstrap re-runs with the heartbeat fix applied, **then** `systemctl is-active inngest-server.service` returns `active` (no regression on the unchanged path).

## Observability

```yaml
liveness_signal:
  what: "Better Stack heartbeat (inngest-server) + existing Sentry cron monitors (scheduled-daily-triage, scheduled-follow-through)"
  cadence: "60s for Better Stack heartbeat; daily 04:00 UTC + weekday 09:00 UTC for Sentry cron monitors"
  alert_target: "operator email (Better Stack default); Sentry issue + Discord ops channel (Sentry cron monitor)"
  configured_in: "apps/web-platform/infra/inngest.tf:108 (heartbeat); apps/web-platform/infra/sentry/cron-monitors.tf (cron monitors)"

error_reporting:
  destination: "Sentry web-platform project (DSN via SENTRY_DSN in Doppler prd)"
  fail_loud: "systemd journal shows 'status=0/SUCCESS' for inngest-heartbeat.service every 60s; Better Stack dashboard shows green; journalctl -u inngest-heartbeat.service --since '5 minutes ago' | grep -c 'status=3/NOTIMPLEMENTED' returns 0"

failure_modes:
  - mode: "Heartbeat script fails (curl error, doppler error, env unset)"
    detection: "Better Stack misses 30s grace + 60s period = 90s without ping → email alert; AND journalctl shows non-zero exit"
    alert_route: "operator email (Better Stack); operator session inspection of journalctl"
  - mode: "Doppler CLI broken on host (token expired, network unreachable to api.doppler.com)"
    detection: "Same as above — heartbeat script exits non-zero; inngest-server.service also fails (parallel symptom = easier diagnosis)"
    alert_route: "operator email (Better Stack heartbeat miss); existing inngest-server.service restart cascade alerts via systemd journal"
  - mode: "Inngest server itself crashes (independent of heartbeat)"
    detection: "Heartbeat keeps firing (decoupled timer) — DOES NOT catch this. Coverage gap acknowledged: follow-up issue for queue-depth / runs-failing observability (issue body 'Medium gap coverage' section)"
    alert_route: "deferred — file follow-up issue #4116-FU-1 (queue depth metric in daily triage cron) and #4116-FU-2 (logs shipping)"

logs:
  where: "journalctl -u inngest-heartbeat.service (systemd journal); journalctl -u inngest-server.service (server logs)"
  retention: "Hetzner VM local; ~30 days at default journald rotation; no remote aggregation yet (deferred to #4116-FU-2)"

discoverability_test:
  command: "curl -fsS https://deploy.soleur.ai/hooks/deploy-status | jq '.services.inngest_heartbeat // \"unknown\"'"
  expected_output: '"ok" (after Phase 3 extension of cat-deploy-state.sh) OR for current state: ssh-free verification via Better Stack public-status page once unpaused at https://status.soleur.ai (TBD)'
```

**Note on `discoverability_test.command`**: the current `cat-deploy-state.sh` does not yet expose per-service heartbeat status. Phase 3 of this plan adds a minimal `services.inngest_heartbeat` field to the deploy-status payload (read from `systemctl is-active inngest-heartbeat.service` + `systemctl show -p ExecMainStatus inngest-heartbeat.service`) so the discoverability_test passes the new gate's own rule. Without this, the plan's own observability declaration would fail the gate it introduces (chicken-and-egg).

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — workflow gate has product implications)

### Engineering (CTO)

**Status:** auto-assessed inline (no agent spawn — plan is single-author, infra change is mechanical pattern parity with existing `inngest-server.service`).

**Assessment:** Bug fix is a 3-line edit to a 250-line script; pattern parity is verifiable by `diff <(grep -A1 'ExecStart' inngest.tf inngest-bootstrap.sh)`. Workflow gate is documentation + lint-script extension; risk is low. IaC routing per Phase 2.8 is satisfied (no SSH; OCI image + deploy webhook).

### Product/UX Gate

**Tier:** NONE — no user-facing surface. The plan modifies operator-facing observability infrastructure + plan-skill workflow. Per Phase 2.5 Step 2's mechanical-escalation check, no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files are touched. No UX review needed.

## Files to Edit

- `apps/web-platform/infra/inngest-bootstrap.sh` — replace `ExecStart=${HEARTBEAT_SCRIPT}` with `ExecStart=/usr/bin/doppler run --project soleur --config prd -- ${HEARTBEAT_SCRIPT}` at line ~180; update header comments at lines ~159-164 to reflect the new ExecStart form.
- `apps/web-platform/infra/inngest.test.sh` — add `test_heartbeat_unit_uses_doppler_run` + `test_heartbeat_unit_execstart_shape`.
- `apps/web-platform/infra/cat-deploy-state.sh` — extend the JSON output with a `services.inngest_heartbeat` field (read from `systemctl is-active inngest-heartbeat.service`), so the discoverability_test command in the `## Observability` block above resolves to a meaningful value.
- `plugins/soleur/skills/plan/SKILL.md` — insert Phase 2.9 after Phase 2.8.
- `plugins/soleur/skills/plan/references/plan-issue-templates.md` — insert `## Observability` block in MINIMAL, MORE, and A-LOT templates.
- `plugins/soleur/skills/deepen-plan/SKILL.md` — insert Phase 4.7 (halt condition).
- `AGENTS.core.md` — add `[id: hr-observability-as-plan-quality-gate]` rule in `## Hard Rules` section AND a corresponding pointer line in `AGENTS.md` index.
- `AGENTS.md` — add `[id: hr-observability-as-plan-quality-gate] → core` pointer in the Hard Rules index.
- `knowledge-base/project/specs/feat-cron-follow-through-monitor-tr9/spec.md` — append `## Observability` block.
- `knowledge-base/project/specs/feat-agent-loop-crons-inngest-tr9/spec.md` — append `## Observability` block.
- `knowledge-base/project/learnings/bug-fixes/2026-05-20-inngest-heartbeat-doppler-env-injection.md` — new learning file documenting the env-injection class.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-observability-heartbeat-4116/spec.md` — spec file (per branch convention).
- `knowledge-base/project/specs/feat-one-shot-observability-heartbeat-4116/tasks.md` — task breakdown (derived post-plan-review).
- `knowledge-base/project/learnings/bug-fixes/2026-05-20-inngest-heartbeat-doppler-env-injection.md` — see Files to Edit (only listed once).
- (Optional follow-up issues — created post-merge, not in this PR's diff):
  - `#4116-FU-1` — Inngest queue depth metric in daily triage cron (`step.run` GraphQL `runs(status: SCHEDULED)`).
  - `#4116-FU-2` — Inngest logs shipping (vector / journald-cloudwatch / loki sidecar).
  - `#4116-FU-3` — Programmatic Better Stack heartbeat unpause via REST API.

## Implementation Phases

### Phase 0 — Preconditions

- Verify `apps/web-platform/infra/inngest-bootstrap.sh:165-181` matches the assumed shape (line numbers can drift; the substring `HEARTBEAT_UNIT` is the anchor).
- Verify `python3 scripts/lint-agents-rule-budget.py AGENTS.core.md` baseline byte count. **Deepen-pass result: baseline FAILS** (`B_ALWAYS=24499 > 22000`). Phase 4.0 below resolves before Phase 4 (rule add) can land.
- Verify `gh issue list --label code-review --state open --limit 200` returns no overlap on the 10 Files-to-Edit (per Open Code-Review Overlap section).
- Verify `doppler` binary path on prod host. Cloud-init installs `/usr/local/bin/doppler` (`cloud-init.yml:290`). Existing `inngest-server.service:137` hardcodes `/usr/bin/doppler`. SSH-read-only diagnose: `ssh deploy@<host> 'command -v doppler && readlink -f /usr/bin/doppler 2>/dev/null'`. If a symlink at `/usr/bin/doppler` exists, both forms work; if not, the existing `inngest-server.service` is latently broken (file scope-out issue if so). Either way, the new `${DOPPLER_BIN}` interpolation is the correct fix.

### Phase 4.0 — AGENTS.md cumulative-budget restoration (BLOCKING for Phase 4)

Per the deepen-pass finding above, AGENTS.core.md is already 2499 bytes over the 22 000-byte cumulative cap and has two rules exceeding the 600-byte per-rule cap. Phase 4 (new rule add) cannot land until budget headroom exists.

- Trim `hr-tagged-build-workflow-needs-initial-tag-push` (line 15) from 1371 → ~550 bytes by moving the `**Why:** PR-F #3940 …` long-form rationale to the existing learning at `knowledge-base/project/learnings/2026-05-18-plan-baked-in-operator-ssh-violated-iac-rule.md` (or sibling). Leave a one-line `**Why:** PR-F #3940 — see <learning-path>.` pointer.
- Trim `wg-after-marking-a-pr-ready-run-gh-pr-merge` (line 55) from 1039 → ~500 bytes by similar long-rationale extraction to a sibling learning.
- Re-run `python3 scripts/lint-agents-rule-budget.py`; require exit 0 before Phase 4 commit.
- Net byte recovery: ~1360 bytes. After the new 487-byte rule lands, headroom ≈ 22 000 − (24 499 − 1360 + 487) = ~ −626 bytes — STILL over by ~600 bytes. Plan: ALSO body-trim a third rule (candidate: `wg-end-of-work-emit-resume-prompt`, currently 587 bytes and load-bearing — extract its body-format detail to `cm-when-proposing-to-clear-context-or`'s sibling learning) to recover the remaining ~600 bytes. Plan-review should validate this arithmetic AND the chosen trim candidates.

### Phase 1 — Heartbeat fix (RED → GREEN)

- Write RED tests (`test_heartbeat_unit_uses_doppler_run`, `test_heartbeat_unit_execstart_shape`) in `inngest.test.sh`; confirm they fail against current `inngest-bootstrap.sh`.
- Edit `inngest-bootstrap.sh` line ~180 to wrap `ExecStart=` in `doppler run`; update comments at lines ~159-164.
- Re-run `inngest.test.sh`; tests GREEN.

### Phase 2 — Discoverability_test wiring

- Extend `cat-deploy-state.sh` JSON output with `services.inngest_heartbeat` (read from `systemctl is-active inngest-heartbeat.service`).
- Add a test for the new field (extend existing `cat-deploy-state.test.sh` if present, OR add a shape assertion).

### Phase 3 — Plan-skill gate

- Insert `Phase 2.9 — Observability Quality Gate` in `plan/SKILL.md` (mirror Phase 2.8 structure).
- Insert `## Observability` template in `plan-issue-templates.md` MINIMAL/MORE/A-LOT.
- Insert `Phase 4.7` halt-condition in `deepen-plan/SKILL.md`.
- Add a deepen-plan fixture in `plugins/soleur/skills/deepen-plan/test/` (or extend existing test harness) that asserts halt on `ssh root@`/`TODO`/`TBD` in `discoverability_test.command`.

### Phase 4 — AGENTS.md rule (requires Phase 4.0 GREEN)

- Add the trimmed 487-byte rule in `AGENTS.core.md` `## Hard Rules` section.
- Add the pointer line `[id: hr-observability-as-plan-quality-gate] → core` in the `AGENTS.md` index.
- Run `python3 scripts/lint-rule-ids.py` and `python3 scripts/lint-agents-rule-budget.py`; both must pass (exit 0).
- Run the loader-class fit grep: `sed -n '88,126p' .claude/hooks/session-rules-loader.sh` and confirm `AGENTS.core.md` is loaded in all three class branches (`core+docs-only`, `core+rest`, `core+docs-only+rest`). Cite the output as a paragraph in this phase's commit message.

### Phase 5 — Backfill TR9 specs

- Append `## Observability` block to `feat-cron-follow-through-monitor-tr9/spec.md` and `feat-agent-loop-crons-inngest-tr9/spec.md`. Use the existing Sentry cron monitor + journalctl + `gh run list` discoverability surfaces.

### Phase 6 — Learning

- Write `knowledge-base/project/learnings/bug-fixes/2026-05-20-inngest-heartbeat-doppler-env-injection.md` capturing the env-injection class generalization.

### Phase 7 — Pre-merge gates

- `/soleur:qa` for the bug-fix path (run `inngest.test.sh` locally; verify the new tests are GREEN).
- `/soleur:preflight` for Check 6 (User-Brand Impact threshold = `aggregate pattern` is acceptable for this diff).
- `/soleur:review` for multi-agent review (especially CTO-strategy on the IaC apply-path and Kieran-rails-reviewer on the AGENTS.core.md placement).

### Phase 8 — Ship

- `/soleur:ship` Phase 7 handles tag push (`vinngest-vX.Y.Z`), OCI build, deploy webhook fire, deploy-status verification, `gh issue close 4116`.
- Operator-only step: unpause `betteruptime_heartbeat.inngest_prd` via Better Stack UI; verify heartbeat green within 60s.

## Risks & Mitigations

- **Risk:** `doppler` CLI on the host is broken (token expired, network unreachable), and the new heartbeat ExecStart wrap takes the heartbeat down WITH `inngest-server.service`. **Mitigation:** Parallel symptom — if `doppler` is broken, `inngest-server.service` is ALREADY broken (line 137 of `inngest-bootstrap.sh`). The diagnosis is shared; no new failure mode introduced. Plus the existing `bootstrap.sh:208-217` validates `DOPPLER_TOKEN` shape before installing the unit, so a token-shape regression is caught at bootstrap time.

- **Risk:** Better Stack heartbeat resource URL changes during a `terraform apply` (e.g., resource recreated), making the in-Doppler URL stale. **Mitigation:** `betteruptime_heartbeat.inngest_prd` has `lifecycle.ignore_changes` on `[paused]` only; if URL changes, the TF dependency graph re-writes `doppler_secret.inngest_heartbeat_url_prd` (which has `ignore_changes = [value]` so it WON'T re-write — drift). Acknowledged limitation: the existing TF code at `inngest.tf:171` would NOT propagate a URL change. Out of scope for this PR; file follow-up issue if Better Stack ever recreates the heartbeat resource.

- **Risk:** The `## Observability` block schema diverges between plan-issue-templates.md and the AGENTS.core.md rule body, creating drift. **Mitigation:** AGENTS.core.md rule names the 5 field set (`liveness_signal / error_reporting / failure_modes / logs / discoverability_test`) but defers the full schema to `plan/SKILL.md` Phase 2.9. Single source of truth: Phase 2.9 body.

- **Risk:** Adding the new gate retrospectively fails open PRs / open plans that don't have the block. **Mitigation:** Phase 4.7 (deepen-plan halt) fires only at `deepen-plan` invocation time — plans already in `/work` are not re-checked. The backfill in Phase 5 addresses the two specs the issue body explicitly names; other open plans get the block when they next re-enter `deepen-plan` or when they re-spec via the new template.

- **Risk:** AGENTS.core.md cumulative word-count blows the budget. **Mitigation:** Phase 4 runs `lint-agents-rule-budget.py` before commit; if over budget, trim the rule body to ≤ 90 words (verified achievable — the rule's load-bearing text is the schema requirement + the SSH disallowance; ~70 words minimum). Worst case, demote one `wg-*` core rule to `rest` per `2026-05-12-agents-md-trim-loader-class-fit-verification.md` analysis (but only after grepping the demote candidate's trigger surface to confirm it doesn't fire on docs-only).

### Research Insights (deepen-pass)

**`doppler` install-path discrepancy (highest-priority finding).** Cloud-init line 290 installs to `/usr/local/bin/doppler`. Existing `inngest-server.service:137` uses `/usr/bin/doppler`. Either a symlink mediates this gap, or `inngest-server.service` is latently broken in a way obscured by the substrate cascade work. Phase 0 verifies on-host; Phase 1's `${DOPPLER_BIN}` interpolation prevents the heartbeat from inheriting whichever assumption is wrong.

**Doppler-CLI installer canonical layout (upstream reference).** Per upstream docs (https://docs.doppler.com/docs/install-cli), the Linux tarball installer drops the binary as a single file; downstream packagers (deb/apt, brew, etc.) place it at distribution-specific paths. Cloud-init uses the direct tarball install, so `/usr/local/bin/doppler` is canonical. If `/usr/bin/doppler` resolves, it's almost certainly via a symlink or a parallel apt install — verify before assuming.

**`systemd` `EnvironmentFile=` behavior.** Per `systemd.exec(5)`: "If `EnvironmentFile=` is missing or empty, no error is generated." This is the structural source of the bug class — missing keys silently load as empty strings, and `curl` accepts an empty `URL` argument before failing at the protocol level (`URL rejected: Malformed input`). `EnvironmentFile=` is incompatible with "fail loud on missing key" — the only reliable pattern is service-start wrapping (this plan's fix).

**`betteruptime_heartbeat.paused`.** Per the Better Stack Terraform provider docs (`registry.terraform.io/providers/BetterStackHQ/better-uptime`), `paused` is an apply-time attribute; UI-unpause via `https://uptime.betterstack.com/team/<id>/heartbeats/<heartbeat-id>` is supported and persists across applies WHEN `lifecycle.ignore_changes = [paused]` is set (already in place at `inngest.tf:135-137`). Programmatic unpause via `PATCH /api/v2/heartbeats/<id>` requires a paid plan API token — out of scope.

**AGENTS.md budget math.** Current state: `B_ALWAYS=24499 > 22000` (2499-byte overshoot). Phase 4.0 prework trims must net ≥ 487 + 2499 = ~2986 bytes to land the new rule with headroom. Recommended candidates (sized by deepen-pass): line 15 (~820 bytes recoverable), line 55 (~540 bytes recoverable), one further small-trim candidate (~150-200 bytes recoverable). Achievable: yes. If review pushes back, retire one `wg-*` per Option (a) of Phase 4.0 alternatives.

**Loader-class fit verification (verbatim).** From `.claude/hooks/session-rules-loader.sh` lines 115-126: the loader sets `CLASSES="core"` by default and adds `docs-only` or `rest` only when the change set indicates docs or code/infra edits. `core` is loaded in every branch, including the multi-class fallthrough. Demoting to `rest` would silently no-op on docs-only edits (e.g., plan-skill SKILL.md edits). Demoting to `docs-only` would silently no-op on code/infra edits (any feature plan). `core` is the only correct placement for a rule that fires on plan-time (docs-only) AND on feature-implementation-time (code/infra).

## Sharp Edges

- The `ExecStart=` patch interpolates `${HEARTBEAT_SCRIPT}` via bash variable expansion at script-write time (HEARTBEATEOF has no `'` quoting in the existing block; see `inngest-bootstrap.sh:172`). After the fix, double-check that the resulting unit body has the **literal** path `/usr/local/bin/inngest-heartbeat.sh` and NOT the unexpanded `${HEARTBEAT_SCRIPT}` — fixture-test this in `inngest.test.sh` via grep against the rendered unit.
- A plan whose `## Observability` section is empty, contains only `TODO`/`TBD`/placeholder text, or omits any of the 5 required fields will fail `deepen-plan` Phase 4.7. Fill it before requesting deepen-plan or `/work`.
- The post-merge unpause step depends on the operator having Better Stack UI access. If the operator changes, the UI access must be re-granted before the heartbeat goes from "wired but paused" to "wired and active". Document in `knowledge-base/engineering/operations/runbooks/inngest-server.md` (already exists per `inngest.tf:103` comment).
- The new `cat-deploy-state.sh` `services.inngest_heartbeat` field must be wired through the existing CF-Access gate (the deploy-status URL is `https://deploy.soleur.ai/hooks/deploy-status` and is gated by CF Access). If unauthenticated, the discoverability_test command returns the CF Access HTML page (HTML, not JSON) and `jq` errors. The fix is to assume the operator is CF-Access-authenticated when running the test — same assumption as the existing deploy-status discoverability.
- AGENTS.md rule placement (`core` vs. `rest` vs. `docs-only`) is verified by reading `.claude/hooks/session-rules-loader.sh:88-126`. The rule fires for both docs-only edits (plan-skill SKILL.md) and code/infra edits (any feature plan). Only `core` always loads. Do NOT demote to `rest` in a future trim sweep without re-reading the loader-class-fit rule and re-asserting the multi-class trigger surface.
- The new `[skill-enforced: plan Phase 2.9 + deepen-plan Phase 4.7]` tag MUST match the canonical regex in `cq-agents-md-tier-gate`'s enforcement; verify the tag shape via `python3 scripts/lint-rule-ids.py` after edit.
- AGENTS.core.md cumulative byte cap (22 000) is currently BREACHED. Adding the new rule without Phase 4.0 prework will fail CI lint on first push. Plan-review must validate the Phase 4.0 trim candidates AND the byte arithmetic before /work begins; if any trim candidate is contested (e.g., reviewer disagrees with extracting `**Why:**` to a learning file), the alternative is rule retirement via `scripts/retired-rule-ids.txt`. Do NOT attempt to land Phase 4 (rule add) without Phase 4.0 GREEN — the lint will block.
- The hardcoded `/usr/bin/doppler` in `inngest-server.service:137` is OUT OF SCOPE for this PR but is a latent same-class risk. Either include a same-PR pattern-parity fix (replace with `${DOPPLER_BIN}` interpolation) OR file a scope-out issue. Plan-review should weigh inclusion.
- The new `## Observability` block's `discoverability_test.command` field requires the `cat-deploy-state.sh` extension (Phase 2) to be load-bearing. Without Phase 2, the discoverability test returns `null` for `services.inngest_heartbeat` and the gate would silently pass on an unverifiable claim. Phase 2 → Phase 3 ordering is load-bearing — do NOT reverse.
- The `## Observability` block in this plan itself uses `Better Stack public-status page once unpaused at https://status.soleur.ai (TBD)` as a fallback discoverability vector. If `status.soleur.ai` is not yet provisioned, the deepen-plan halt at Phase 4.7 should NOT fire (the primary `discoverability_test.command` against `deploy.soleur.ai/hooks/deploy-status` IS valid post-Phase-2). Document the TBD as an acceptable footnote, not a `TODO`/`TBD` field that would trip the new gate's own checker. Phase 4.7's reject regex must distinguish "fallback note containing TBD" from "field value is exactly `TBD`".

## References

- Issue: #4116
- Sibling substrate fixes: #4017, #4085, #4093, #4104, #4111
- Heartbeat resource definition: `apps/web-platform/infra/inngest.tf:108-138`
- Bootstrap script: `apps/web-platform/infra/inngest-bootstrap.sh`
- Build + deploy pipeline: `.github/workflows/build-inngest-bootstrap-image.yml`
- Apply-pattern reference: `.github/workflows/apply-deploy-pipeline-fix.yml`
- Loader-class fit learning: `knowledge-base/project/learnings/2026-05-15-multi-stage-premise-validation-compounds-and-agents-sidecar-loader-class-fit.md`
- IaC rule: `AGENTS.core.md` `[id: hr-all-infrastructure-provisioning-servers]`
- Dashboard-eyeball rule: `AGENTS.core.md` `[id: hr-no-dashboard-eyeball-pull-data-yourself]`
