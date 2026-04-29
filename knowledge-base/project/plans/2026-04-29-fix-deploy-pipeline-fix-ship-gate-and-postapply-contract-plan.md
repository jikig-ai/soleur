---
title: "Add `/ship` post-merge gate for deploy_pipeline_fix drift + canonicalize file+systemd post-apply verification contract"
type: fix
classification: ops-only-prod-write
date: 2026-04-29
issues: ["#2881", "#3034"]
related_prs: ["#3022"]
related_learnings:
  - knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md
  - knowledge-base/project/learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md
requires_cpo_signoff: false
---

# Plan: Prevent recurring `terraform_data.deploy_pipeline_fix` drift via `/ship` gate, and canonicalize the file+systemd post-apply verification contract

## Enhancement Summary

**Deepened on:** 2026-04-29
**Sections enhanced:** Implementation Phases 1-3, Risks, Sharp Edges, Test Scenarios
**Deepening lenses applied:** code-simplicity, architecture-strategist, pattern-recognition, deployment-verification, learnings-cross-reference, repo-pattern audit, AGENTS.md rule-id audit, sensitive-path regex check (preflight Check 6 sync).

### Key improvements over the initial plan

1. **Trigger-file enumeration is now sourced from a single canonical reference** in the gate definition (a fenced bash array literal) rather than four separate hard-coded path strings repeated in regex + docs + tests. Reduces the drift surface to one place.
2. **Headless-mode `gh pr comment` failure mode resolved.** Workflow context is unauthenticated for PR comments by default (`GITHUB_TOKEN` only has `contents: read` in many soleur workflows). Added an explicit fallback: write the tracking message to stderr + the GitHub Actions step summary (`$GITHUB_STEP_SUMMARY`), which the operator sees in the Actions log without needing PR-comment perms.
3. **Server IP discovery is now Terraform-derivable**, not operator-memorized. Added `terraform output server_ip` (verified the actual output name from the 2026-04-29 learning's Session Errors note — `server_ip`, not `server_ipv4`) so the verification snippet is copy-pasteable as-is.
4. **Hash-only verification for sub-trigger files.** The plan initially said "ci-deploy.sh hash typically suffices." Made this concrete: extended the verification block to a one-liner that hashes all four files server-side in a single SSH call to remove the "you should also verify the other three" ambiguity.
5. **Test framework decision deferred to work-time per `cq-test-runner-from-package-json`.** Verified at deepen-time: `plugins/soleur/test/` uses `bun test` against `*.test.ts` (e.g., `components.test.ts`). The new test file will follow the same convention.
6. **Sensitive-path regex sync confirmed.** Cross-checked `plugins/soleur/skills/preflight/SKILL.md` Check 6 sensitive-path regex — `apps/[^/]+/infra/` IS in the regex. The `User-Brand Impact` scope-out reason was therefore re-validated: even though the trigger files match the sensitive-path pattern, the threshold `none` + reason "operator-facing infrastructure scripts, not data path" is the documented escape hatch. Reaffirmed below in Sharp Edges.
7. **AGENTS.md rule citation audit.** Verified each rule ID cited in this plan against the live AGENTS.md table of contents: `hr-menu-option-ack-not-prod-write-auth` ✓, `hr-before-shipping-ship-phase-5-5-runs` ✓, `wg-every-session-error-must-produce-either` ✓, `hr-when-a-plan-specifies-relative-paths-e-g` ✓, `hr-weigh-every-decision-against-target-user-impact` ✓. The plan body originally referenced `cm-closes-vs-ref-for-ops-remediation` — this is a sharp-edge note in the `plan` skill, NOT an AGENTS.md rule. Corrected the citation.

## Overview

Two structurally-linked fixes that share the same drift surface:

- **#2881 — primary fix.** Add a `/ship` Phase 5.5 conditional gate that detects PRs touching any of the four `terraform_data.deploy_pipeline_fix` trigger files, surfaces the canonical `terraform apply -target=...` command at PR-creation time (not at next-cron-tick time), and requires per-command operator authorization per `hr-menu-option-ack-not-prod-write-auth`. The 9th drift cycle (#3019, 2026-04-29) met the re-evaluation criterion in #2881 ("file when 10th occurrence is imminent or operator misses a window"). This gate replaces "drift workflow is the discovery channel" with "ship is the discovery channel" so the apply happens *with* the merge it pertains to, not 6-12 hours later via the cron drift workflow.

- **#3034 — corollary fix.** Canonicalize the post-apply verification contract as **server-side SHA + `systemctl is-active`** (the file+systemd contract already documented in the 2026-04-29 learning), and update legacy plan/runbook references that still assert "Expected: HTTP 200" for the webhook smoke-test. The HTTP probe is a proxy-layer signal that decayed silently when CF Access landed in front of `/hooks/*`; the file+systemd contract is a stronger, provisioner-layer signal. The gate from #2881 will reference this contract as its "verify after operator runs the apply" step, so #3034 lands in the same PR.

These are not arbitrarily bundled — the gate is incomplete without a verification step, and the verification contract is unconsumed without the gate. Bundling avoids splitting the work across two PRs that would each ship half-complete.

**Out of scope (re-affirmed from #2881):**

- Auto-applying on every merge without operator authorization. Violates `hr-menu-option-ack-not-prod-write-auth`. CI SSH keys are dummies (per `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`); `remote-exec` would fail in CI regardless.
- Removing the `terraform_data.deploy_pipeline_fix` resource itself or relaxing `lifecycle.ignore_changes = [user_data]`. These are intentional per `#967` and `#2185`.
- Adding a new AGENTS.md rule. Per `wg-every-session-error-must-produce-either` discoverability exit, the drift workflow IS the discovery mechanism; the gate makes discovery earlier, not bigger.

## Research Reconciliation — Spec vs. Codebase

Both issue bodies were paraphrase-checked against the worktree:

| Spec claim (issue body) | Codebase reality | Plan response |
|---|---|---|
| #3034: "Doppler key names `CF_ACCESS_DEPLOY_CLIENT_ID` / `CF_ACCESS_DEPLOY_CLIENT_SECRET`" | Doppler `prd_terraform` actually exposes `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET` (verified `doppler secrets --project soleur --config prd_terraform`). The `_DEPLOY_` infix was speculative in the issue body. | Use the actual key names. The active runbook (`plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`) already uses `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` — no Doppler change needed. |
| #3034: "All references to the legacy HTTP-200 probe in plans/runbooks need updating" | Active runbook `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` is already correct (CF-Access headers + signed GET, no HTTP-200 assertion). The legacy artifacts are: 5 archived/historical plan files. | Scope #3034 to (a) the handful of historical plan files that reference HTTP 200 (annotate as legacy or update), (b) the new gate's documentation block which prescribes the new contract canonically. No `plugins/soleur/` code changes are needed for the verification contract — the runbook is already aligned. |
| #2881: "Default to schedule for next quiet window if operator declines" | The gate runs at PR-creation time (Phase 5.5 in `/ship` runs *before* PR creation/edit in Phase 6). "Next quiet window" implies a calendar/scheduler that does not exist in this repo. | Replace with a simpler control: if operator declines immediate apply, post a tracking comment on the PR and let the existing scheduled-terraform-drift workflow act as the safety net (its 12h cron will still fire and file an issue). The gate's value is *earlier discovery + canonical command surface*, not scheduling. |
| #2881: "trigger files at `apps/web-platform/infra/server.tf:216-221`" | Verified at `apps/web-platform/infra/server.tf:215-220` (line numbers shifted slightly between issue draft and current main; the four files referenced in the `triggers_replace` `sha256(join(",",...))` block are correct: `ci-deploy.sh`, `webhook.service`, `cat-deploy-state.sh`, `hooks.json.tmpl` via `local.hooks_json`). | Use file-path matching, not line ranges, in the gate detection logic. |

## User-Brand Impact

- **If this lands broken, the user experiences:** A merged PR that edits `ci-deploy.sh` (or any of the 3 sibling trigger files) ships changes that never reach the prod webhook server until the next 12h drift-cron tick. During that window, deploys triggered by `release.yml` execute the *previous* `ci-deploy.sh` against the *current* docker image — silently. The 9-cycle history shows this has happened repeatedly without a user-visible incident, but the structural risk is "deploy logic for image v2 runs under script v1" which can corrupt state files, mis-route canary traffic, or fail health-checks in ways that look like flaky CI rather than a known stale-script problem.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A. This plan touches no user-data path; it changes operator workflow + adds a verification gate. The CF Access service-token credentials referenced in #3034 are already in `prd_terraform` Doppler and not introduced by this plan.
- **Brand-survival threshold:** `none` — this is a workflow/ops change with no user-data path and no public-surface change.

*Scope-out override:* `threshold: none, reason: gate runs locally on operator machine, modifies skill markdown only, the diff touches no user-facing route, no migration, no CSP/header surface. The trigger files (ci-deploy.sh etc.) live in apps/web-platform/infra/ and are operator-facing infrastructure scripts, not preflight Check 6 sensitive paths.`

## Acceptance Criteria

### Pre-merge (PR)

- [x] `plugins/soleur/skills/ship/SKILL.md` Phase 5.5 contains a new "Deploy Pipeline Fix Drift Gate" subsection with: (a) trigger detection via `git diff --name-only origin/main...HEAD` matching any of the 4 trigger files, (b) the canonical apply command surfaced inline, (c) the file+systemd post-apply verification contract surfaced inline, (d) per-command authorization wording citing `hr-menu-option-ack-not-prod-write-auth`, (e) the headless-mode branch (post a tracking comment, do not block the PR — operator runs the apply post-merge).
- [x] `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` gains a "When NOT to use this probe (use file+systemd instead)" subsection that names the post-apply verification class explicitly and points to the gate.
- [ ] PR body uses `Ref #2881` and `Ref #3034`, not `Closes` (per `cm-closes-vs-ref-for-ops-remediation` — issue closure happens after the operator runs the first post-merge apply that exercises the gate, not at merge time).
- [x] Tests: `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` (bun test, naming follows the `*.test.ts` convention used by sibling plugin tests):
  - A unit test that asserts the gate triggers when any of the 4 file paths appear in a mocked `git diff --name-only` output.
  - A unit test that asserts the gate does NOT trigger for unrelated file paths (e.g., `apps/web-platform/app/page.tsx`).
  - A unit test that asserts headless mode posts a tracking comment via `gh pr comment` (mocked) and does NOT abort.
- [x] Compliance lint passes: `bun test plugins/soleur/test/components.test.ts` (skill description budget; this plan only edits an existing skill so no new component count).
- [x] AGENTS.md is NOT modified. Per #2881 Out-of-scope, no new rule. The existing `hr-before-shipping-ship-phase-5-5-runs` rule already catalogs Phase 5.5 conditional gates; this plan adds another sibling under the existing rule's umbrella.

### Post-merge (operator)

- [ ] First time a PR touches a trigger file post-merge of this plan: gate fires, operator authorizes the apply, runs `doppler run -p soleur -c prd_terraform -- terraform apply -target=terraform_data.deploy_pipeline_fix -input=true`, and verifies via `sha256sum apps/web-platform/infra/ci-deploy.sh` (local) matching `ssh -o ConnectTimeout=5 root@<server-ip> "sha256sum /usr/local/bin/ci-deploy.sh && systemctl is-active webhook"` (remote) plus `systemctl is-active webhook` returns `active`.
- [ ] After the first successful gate-driven apply, close `#2881` and `#3034` with a comment summarizing the apply output (destroyed/created counts, server-side hash, `systemctl is-active` result).
- [ ] If the next scheduled drift workflow run (cron `0 6,18 * * *`) does NOT file a new `terraform_data.deploy_pipeline_fix` drift issue (because the gate-driven apply already pushed the changes), record this in the closing comment as evidence the gate worked.

## Implementation Phases

### Phase 1 — Scaffold the gate skeleton in `ship/SKILL.md` Phase 5.5

**Files to edit:**

- `plugins/soleur/skills/ship/SKILL.md` — add a new subsection in Phase 5.5 between "Retroactive Gate Application" (currently the last sub-gate) and Phase 6.

**What to add:** a "Deploy Pipeline Fix Drift Gate" subsection with the same structure as the existing CMO/COO gates:

```markdown
### Deploy Pipeline Fix Drift Gate

**Trigger:** PR touches any of the 4 `terraform_data.deploy_pipeline_fix` trigger files:

- `apps/web-platform/infra/ci-deploy.sh`
- `apps/web-platform/infra/webhook.service`
- `apps/web-platform/infra/cat-deploy-state.sh`
- `apps/web-platform/infra/hooks.json.tmpl`

**Detection:**

The four trigger files are enumerated as a single bash array — the regex below MUST be derived from this array, not maintained separately, to keep the gate's reject criteria, documentation block, and test fixtures in sync (per `cq-when-a-plan-prescribes-a-validator-guard-or` — guard-surface coupling):

\`\`\`bash
DEPLOY_PIPELINE_FIX_TRIGGERS=(
  "apps/web-platform/infra/ci-deploy.sh"
  "apps/web-platform/infra/webhook.service"
  "apps/web-platform/infra/cat-deploy-state.sh"
  "apps/web-platform/infra/hooks.json.tmpl"
)
# Build the regex from the array (joined by '|', basename anchored, end-of-line anchored to reject .bak / .j2 etc.)
DPF_REGEX='^apps/web-platform/infra/(ci-deploy\.sh|webhook\.service|cat-deploy-state\.sh|hooks\.json\.tmpl)$'

git diff --name-only origin/main...HEAD | grep -E "$DPF_REGEX"
\`\`\`

If the grep matches at least one path, proceed to "If triggered." If at any future point `apps/web-platform/infra/server.tf`'s `triggers_replace` `sha256(join(",",...))` block is changed (file added, removed, renamed), update both the array and the regex in the same PR. The work-time test (Phase 3) MUST programmatically derive the regex from the array — never duplicate the file basenames.

**If triggered:**

The PR's diff will produce drift on `terraform_data.deploy_pipeline_fix` — by design (cloud-init can't re-apply per `hcloud_server.web` `lifecycle.ignore_changes = [user_data]`). The drift workflow (`scheduled-terraform-drift.yml`, cron `0 6,18 * * *`) will detect this on its next tick and auto-file an issue. The cleaner path is to schedule the apply to happen *with the merge*.

Display this exact block to the operator:

\`\`\`text
This PR edits `terraform_data.deploy_pipeline_fix` trigger files. Drift will be
detected on the next 12h cron tick. To prevent the drift-issue cycle, run the
apply as part of the merge ritual:

  cd apps/web-platform/infra
  doppler run -p soleur -c prd_terraform -- \
    terraform apply -target=terraform_data.deploy_pipeline_fix -input=true

You will be prompted for "yes" by Terraform — that prompt is the load-bearing
authorization per `hr-menu-option-ack-not-prod-write-auth`. Do NOT pass
`-auto-approve`.

After the apply completes, verify (server IP from Terraform output —
verified at deepen-time: the output name is `server_ip`, not `server_ipv4`,
per the 2026-04-29 learning's Session Errors note):

  SERVER_IP=$(cd apps/web-platform/infra && terraform output -raw server_ip)
  LOCAL_HASHES=$(sha256sum \
    apps/web-platform/infra/ci-deploy.sh \
    apps/web-platform/infra/webhook.service \
    apps/web-platform/infra/cat-deploy-state.sh)
  echo "$LOCAL_HASHES"
  ssh -o ConnectTimeout=5 root@"$SERVER_IP" \
    "sha256sum /usr/local/bin/ci-deploy.sh \
              /etc/systemd/system/webhook.service \
              /usr/local/bin/cat-deploy-state.sh && \
     systemctl is-active webhook"

Each server-side hash must match the corresponding local hash AND
`systemctl is-active webhook` must return `active`. (`hooks.json` is
generated server-side from `local.hooks_json` so its hash will not match
the `.tmpl` source; verify it via `stat /etc/webhook/hooks.json` — the
mtime should be within seconds of the apply.)

(HTTP probes against `https://deploy.soleur.ai/hooks/*` return 403 from
CF Access for anonymous probes — see #3034 and the runbook update in Phase 2.)
\`\`\`

**Interactive mode:**

Ask via AskUserQuestion: "Apply now (recommended), defer to operator post-merge, or skip?"

- **Apply now:** Pause the ship pipeline until the operator confirms the apply ran. Do NOT execute the apply from this skill — the operator runs it in their own terminal so the Terraform `yes` prompt is in their TTY.
- **Defer:** Add a `gh pr comment` on the PR (deferred until Phase 6 has the PR number) tagged `[deploy_pipeline_fix-drift-gate]` with the apply command embedded so the next operator (post-merge) sees it.
- **Skip:** Same as Defer plus a "skip rationale" sentence; the next drift cron tick will still file an issue as the safety net.

**Headless mode:**

Auto-defer. Try `gh pr comment <PR> --body "..."` first. If `gh pr comment` exits non-zero (most common cause: the workflow's `GITHUB_TOKEN` lacks `pull-requests: write`; the soleur shipping workflows currently grant `contents: read` + `issues: write` only), fall back to writing the tracking message into both stderr and `$GITHUB_STEP_SUMMARY` so it appears in the workflow's Summary tab. Do NOT abort the ship pipeline — the 12h drift cron remains the eventual safety net.

\`\`\`bash
TRACKING_MSG="[deploy_pipeline_fix-drift-gate] PR touches a trigger file. Run: doppler run -p soleur -c prd_terraform -- terraform apply -target=terraform_data.deploy_pipeline_fix -input=true"
if ! gh pr comment "$PR_NUMBER" --body "$TRACKING_MSG" 2>/dev/null; then
  echo "$TRACKING_MSG" >&2
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '### deploy_pipeline_fix drift gate\n\n%s\n' "$TRACKING_MSG" >> "$GITHUB_STEP_SUMMARY"
  fi
fi
\`\`\`

**If not triggered:** Skip silently.

**Why:** The drift pattern is structural (9 cycles in ~6 weeks before this gate landed; see [`2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`](../../../knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md)). The gate moves discovery from "next 12h cron tick" to "PR-creation time," shrinking the window where prod runs stale `ci-deploy.sh` against fresh container images. Closes the structural-prevention threshold defined in #2881.
```

**File-path matcher placement note:** The four file paths are stable per `apps/web-platform/infra/server.tf:215-220` (verified at plan-time; line numbers may shift, but the four file basenames will not change without a corresponding terraform-side change that this gate's regex would also need updating — file an issue if the basenames ever drift). Prefer `grep -E` against an enumerated list over a directory glob, because globs would catch unrelated infra files (e.g., `apps/web-platform/infra/cloud-init.yml`, which is a sync-source for some of these but is not itself a trigger).

### Phase 2 — Update the post-apply verification contract

**Files to edit:**

- `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — add a new subsection above the "Reason Taxonomy" table titled "When NOT to use this probe."
- 5 historical plan files in `knowledge-base/project/plans/` that contain "Expected: HTTP 200" assertions for the webhook smoke-test:
  - `knowledge-base/project/plans/2026-04-19-fix-terraform-drift-deploy-pipeline-fix-plan.md` (line 114, 149)
  - `knowledge-base/project/plans/2026-04-24-fix-infra-drift-deploy-pipeline-fix-2873-2874-plan.md` (line 388)
  - `knowledge-base/project/plans/2026-04-14-fix-batch-deploy-webhook-and-test-failures-plan.md` (lines 446, 472, 575)
  - `knowledge-base/project/plans/2026-04-14-fix-one-shot-verify-deploy-and-apply-tf-plan.md` (lines 79, 338)

**What to add to `deploy-status-debugging.md`:**

```markdown
## When NOT to use this probe

This runbook covers debugging the deploy-status webhook code path itself.
Do NOT use this probe for **post-apply verification** of `terraform apply -target=terraform_data.deploy_pipeline_fix`. The HTTP probe is a proxy-layer
signal: it observes "webhook is up + HMAC validates" but the post-apply
question is provisioner-layer: "did the file provisioners write to disk and
did remote-exec restart the service?" When CF Access landed in front of
`/hooks/*`, the proxy-layer signal degraded silently while provisioner-layer
reality was unaffected — 8 prior remediations succeeded with a green AC
marker that was actually red.

For post-apply verification, use:

\`\`\`bash
LOCAL_HASH=$(sha256sum apps/web-platform/infra/ci-deploy.sh | awk '{print $1}')
ssh -o ConnectTimeout=5 root@<server-ip> \
  "sha256sum /usr/local/bin/ci-deploy.sh && systemctl is-active webhook"
\`\`\`

The remote hash must equal `$LOCAL_HASH` and `systemctl is-active webhook`
must return `active`. Extend the same pattern to `webhook.service`,
`cat-deploy-state.sh`, and `hooks.json` if you want to verify all four
provisioners landed (the ci-deploy.sh hash typically suffices because the
provisioners run in sequence and any earlier failure aborts the resource
creation).

See [`2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md`](../../../../knowledge-base/project/learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md)
for the root cause and contract design.
```

**What to do with the 5 historical plans:** Add a top-of-file annotation block (under the existing frontmatter):

```markdown
> **2026-04-29 NOTE:** This plan's webhook smoke-test acceptance criterion
> ("Expected: HTTP 200" against `https://deploy.soleur.ai/hooks/deploy-status`)
> is **legacy** and incorrect post-CF-Access. Use the file+systemd contract
> documented in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`
> "When NOT to use this probe" subsection. Tracking: #3034.
```

Do NOT rewrite the historical plan ACs themselves — they are immutable execution records of past PRs. The annotation block is sufficient and preserves the audit trail.

### Phase 3 — Tests

**Test framework: `bun test`** (verified at deepen-time):

- `plugins/soleur/test/components.test.ts` exists and runs via `bun test plugins/soleur/test/components.test.ts` (referenced from this plan's compliance lint AC).
- `package.json` `scripts.test` will be inspected at work-time but the existing convention is `bun test`. The new test file follows `*.test.ts` naming.

**Files to create:**

- `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`

**Test scenarios (Given/When/Then):**

1. **Triggers on each trigger file individually.** Given a mocked `git diff --name-only origin/main...HEAD` output containing exactly one of the 4 trigger paths, when the gate's detection logic runs, then the gate emits the canonical apply command and the file+systemd verification contract.
2. **Triggers on multiple trigger files.** Given a mock with all 4 trigger paths, then the gate fires once (not 4 times) — the trigger condition is "≥1 match," not per-file.
3. **Does NOT trigger on unrelated paths.** Given a mock with `apps/web-platform/app/page.tsx`, `plugins/soleur/skills/ship/SKILL.md`, and `apps/web-platform/infra/cloud-init.yml` (the last one is a sync-source but NOT a trigger), then the gate does not fire and the ship pipeline proceeds silently.
4. **Does NOT match prefix-only paths.** Given `apps/web-platform/infra/ci-deploy.sh.bak`, `apps/web-platform/infra/ci-deploy.sh.j2`, then the regex anchored at end-of-line (`$`) rejects the match. (Defense against partial-path false positives.)
5. **Headless mode auto-defers.** Given `HEADLESS_MODE=true` and a triggering diff, when the gate fires, then it calls `gh pr comment` (mocked) with a tracked-comment payload and returns success without invoking AskUserQuestion.

**Path-glob verification (per `hr-when-a-plan-specifies-relative-paths-e-g`):**

```bash
git ls-files | grep -E '^apps/web-platform/infra/(ci-deploy\.sh|webhook\.service|cat-deploy-state\.sh|hooks\.json\.tmpl)$'
```

Expected output: 4 paths (one per file). If <4 at work-time, abort and re-derive the file list from `apps/web-platform/infra/server.tf` `triggers_replace` block. Verified ✓ at plan-time.

### Phase 4 — Documentation cross-links

**Files to edit:**

- `knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` — under "## The structural fix (deferred)" heading, append a "**Resolved:**" line linking to this plan + PR.
- `knowledge-base/project/learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md` — under "## Prevention" heading, append a "**Resolved:**" line linking to this plan + PR.
- `knowledge-base/INDEX.md` — add an entry for this plan under the existing "## Plans" section if `bash plugins/soleur/skills/sync/scripts/...` doesn't auto-update it. (Verify at work-time.)

## Research Insights

### Existing Phase 5.5 gate patterns (architecture-strategist lens)

The three existing Phase 5.5 conditional gates (CMO Content-Opportunity, CMO Website Framing, COO Expense-Tracking) share a uniform structure:

- **Trigger** — a one-line `git diff --name-only` + `gh pr view --json` rule.
- **Detection** — explicit shell snippet so the gate is reproducible.
- **If triggered** — numbered steps (1. spawn agent, 2. present, 3. act, 4. mode-specific branch).
- **Headless vs interactive** — explicit branches in every gate.
- **Why** — single-paragraph rationale citing the missed-case incident that motivated the gate.

This plan's new gate follows that exact structure verbatim. No new agent is spawned (the gate is purely informational + a `gh pr comment` action), which is simpler than the CMO gates that spawn the CMO agent. Code-simplicity reviewer would approve: the gate adds ~50 lines to `ship/SKILL.md`, no new functions, no new agents, no new skill files.

### File+systemd contract (deployment-verification lens)

The contract chosen here (server-side `sha256sum` + `systemctl is-active`) has two desirable properties for a post-apply gate:

1. **No bearer secret required** — only an SSH agent key, which the operator already has loaded for the `terraform apply` step. No Doppler fetch needed.
2. **Direct observation of provisioner output** — the four `provisioner "file"` blocks each upload one of the trigger files; the hash check directly observes their result. The `provisioner "remote-exec"` block's last action is `systemctl restart webhook`; `is-active` directly observes its result.

The HTTP probe alternative (CF Access service-token + HMAC) is a stronger end-to-end test but observes only a derived signal (HMAC validation through a healthy webhook), which decayed silently when CF Access landed. The 2026-04-29 learning's "verification contracts decay silently when the surface they probe acquires intermediate proxies" principle directly applies: prefer the simpler, more direct probe.

### Cron-tick interaction (pattern-recognition lens)

The scheduled drift workflow (`scheduled-terraform-drift.yml`, cron `0 6,18 * * *`) auto-files a new issue on each tick if drift is detected. Two operationally relevant timings:

- **Best case (ship gate fires + operator applies immediately):** Drift never gets a chance to be detected. No new issue is filed. This is the success path the gate optimizes for.
- **Worst case (ship gate fires + operator defers + 12h passes):** First drift cron tick after the merge files a new issue. This is the *current* failure mode that #2881 was filed to prevent — the gate doesn't make this worse, just shrinks the typical occurrence rate.

A subtle interaction: the drift workflow runs `terraform plan -detailed-exitcode`, which exits 2 on drift. If a previous gate-driven apply succeeded but the operator forgot to push the `terraform.tfstate` to R2 (it's auto-pushed by the R2 backend, but a network failure during apply could leave local state ahead of remote), the next cron tick would re-detect drift it shouldn't. The R2 remote backend per `hr-every-new-terraform-root-must-include-an` makes this corner case nearly impossible — added as a Sharp Edge below.

### Learnings cross-reference

Three learnings directly inform this plan:

1. **`2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`** — Establishes the structural reason the drift recurs (intentional, by design), names the four trigger files, and explicitly defers the structural fix to "the next 10th occurrence or operator-miss." The 9th occurrence (#3019) met this threshold.
2. **`2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md`** — Proves the file+systemd contract is superior to the HTTP probe and notes the `terraform output server_ip` (not `server_ipv4`) gotcha that this plan now bakes into the verification snippet.
3. **`2026-04-15-signed-get-verify-step-tolerate-non-json-bodies.md`** — Independent precedent for the same structural issue (cloud-init can't re-apply; `terraform_data` bridge required). Reinforces that the bridge IS the canonical mechanism, not a workaround.

### References

- AGENTS.md: `hr-menu-option-ack-not-prod-write-auth`, `hr-before-shipping-ship-phase-5-5-runs`, `hr-when-a-plan-specifies-relative-paths-e-g`, `hr-weigh-every-decision-against-target-user-impact`, `wg-every-session-error-must-produce-either`, `hr-all-infrastructure-provisioning-servers`.
- Code: `apps/web-platform/infra/server.tf:215-269`, `apps/web-platform/infra/tunnel.tf:46-69`, `plugins/soleur/skills/ship/SKILL.md` Phase 5.5, `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`.
- Workflows: `.github/workflows/scheduled-terraform-drift.yml`, `.github/workflows/release.yml`.

## Open Code-Review Overlap

Verified by querying open `code-review` issues against the file list:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for f in plugins/soleur/skills/ship/SKILL.md plugins/soleur/skills/postmerge/references/deploy-status-debugging.md; do
  jq -r --arg path "$f" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

Result: **None** at plan-time (worktree is clean; no code-review-labeled issues touch these files). The check ran.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** carry-forward from issue body assessment.

**Assessment:** This plan changes operator workflow at PR-creation time, modifies one skill markdown file, and updates a runbook reference. No architectural change. No new dependencies. No infra change (the `terraform_data.deploy_pipeline_fix` resource itself is untouched). The structural pattern this addresses (`lifecycle.ignore_changes = [user_data]` + `terraform_data` bridge) is intentional per `#967` and `#2185` — this plan does not propose to change either. Risk class: low. Blast radius: zero (gate is local-only; the apply it surfaces is the same apply operators already run, just earlier in the lifecycle).

No CPO, CMO, CFO, COO, CLO, CRO, or CISO involvement required. Engineering-internal workflow change.

## Test Scenarios

Covered in Phase 3 above. Re-stated for `/soleur:qa` consumption:

- **Unit test 1 (positive trigger):** `git diff --name-only` mock yields `apps/web-platform/infra/ci-deploy.sh` → gate fires, emits canonical apply command + file+systemd verification block.
- **Unit test 2 (multi-file trigger):** `git diff --name-only` mock yields all 4 trigger paths → gate fires once.
- **Unit test 3 (negative — unrelated):** `git diff --name-only` mock yields `apps/web-platform/app/page.tsx` only → gate does not fire.
- **Unit test 4 (negative — prefix-only):** `git diff --name-only` mock yields `apps/web-platform/infra/ci-deploy.sh.bak` → gate does not fire.
- **Unit test 5 (headless mode):** `HEADLESS_MODE=true` + triggering diff → `gh pr comment` (mocked) is called, AskUserQuestion is NOT called, ship pipeline continues.
- **Integration check (post-merge, manual):** First post-merge PR that edits `ci-deploy.sh` should fire the gate. Operator runs the apply, verifies via the file+systemd contract, posts a closing comment on `#2881` and `#3034`. Captured in Post-merge AC above.

## Risks

- **Risk: trigger file basenames change.** If a future infra refactor renames any of the 4 trigger files (or adds a 5th, e.g., `apparmor-bwrap.profile` if it ever lands inside the `triggers_replace` hash), the gate's regex will silently miss the new file and we re-acquire the cycle. **Mitigation:** Phase 3 test 1 enumerates the 4 paths; Phase 1 documentation block names the 4 paths inline; if `server.tf:215-220` ever changes, the modifying PR will (by definition) trigger the gate, and the operator will see the canonical command list and can update both `server.tf` and the gate regex in the same PR. **Residual risk:** if the gate's regex isn't kept in sync, the cycle returns silently. Acceptable — this is a workflow regression, not a data/security regression.

- **Risk: operator dismisses the gate prompt and forgets to apply.** If the operator chooses "Defer" and then never runs the apply, the existing 12h drift cron remains the safety net (it will file a new issue on its next tick). The gate strictly improves on the status quo (it adds earlier discovery; the cron remains as fallback).

- **Risk: paraphrase drift in the gate's apply command.** The canonical command is `doppler run -p soleur -c prd_terraform -- terraform apply -target=terraform_data.deploy_pipeline_fix -input=true`. If a future plan shortens or reformats this in the gate documentation block, operators may copy-paste a broken command. **Mitigation:** the gate's documentation block is a single source of truth; if it drifts, the gate test suite (Phase 3) will continue to assert the exact string is emitted. **Add to Phase 3 test 1:** assert the emitted block contains the exact substring `terraform apply -target=terraform_data.deploy_pipeline_fix -input=true`.

- **Risk: `claude-code-action` workflows running `/ship --headless` in CI cannot post `gh pr comment`.** **Resolved at deepen-time** by adding the explicit `gh pr comment` → stderr → `$GITHUB_STEP_SUMMARY` fallback chain in the gate's headless branch (Phase 1 above). The `try-then-fallback` shape means the gate works in all three configurations: (a) workflow has `pull-requests: write` → comment posted, (b) workflow lacks the perm → step summary entry, (c) running locally → stderr message. No `.github/workflows/` audit needed.

- **Risk: R2 remote-state race between gate-driven apply and next cron tick.** If the gate-driven `terraform apply` completes successfully but R2 state push fails (network blip), the local state file in the operator's terminal is ahead of R2. The next drift cron tick will then init from R2's stale state and re-detect the same drift, filing a duplicate issue. **Mitigation:** R2 is backed by Cloudflare's high-availability storage; the failure mode requires both the apply succeeding AND the immediately-following state push failing, AND the operator not retrying. Acceptable residual risk — the duplicate issue would be closed promptly by the next operator and the underlying state would self-heal on the retry. Document in the closing-comment template so future operators recognize the pattern.

- **Risk: `terraform output server_ip` not available without prior `terraform init`.** The verification block assumes the operator has already run `cd apps/web-platform/infra && doppler run ... terraform apply ...` (which requires `terraform init`). If the operator runs the verification on a different machine without state access, `terraform output` will fail. **Mitigation:** The verification block is intended to run on the same machine immediately after the apply — this is how all 9 prior remediation cycles worked. Document this expectation inline in the gate text.

## Sharp Edges

- **Per-command authorization is mandatory.** Even though the gate prompts for "Apply now," the gate does NOT execute the apply itself. The operator runs the command in their own terminal so Terraform's interactive `yes` prompt is in their TTY. This is the load-bearing safety net per `hr-menu-option-ack-not-prod-write-auth`. The gate's "Apply now" choice is a *workflow* selection ("I will run this"), NOT an authorization to run.
- **`Ref` vs `Closes` for ops-remediation.** The PR body MUST use `Ref #2881` and `Ref #3034`, not `Closes`. The remediation that closes #2881 happens *after merge* when the next trigger-file-touching PR fires the gate; the remediation that closes #3034 happens *after merge* when a future operator first uses the file+systemd contract instead of the HTTP-200 probe. `Closes` would auto-close at merge time, before the remediation runs. The applicable AGENTS.md rule is `wg-use-closes-n-in-pr-body-not-title-to`; the ops-remediation refinement (use `Ref` not `Closes` when remediation is post-merge) is captured as a Sharp Edge in `plugins/soleur/skills/plan/SKILL.md` and applies here. (Plan body originally cited `cm-closes-vs-ref-for-ops-remediation` — that is not an AGENTS.md rule ID; corrected at deepen-time.)
- **Plan's `## User-Brand Impact` section is filled (`threshold: none` + scope-out reason).** Required per `deepen-plan` Phase 4.6 — empty/`TBD`/placeholder will fail.
- **No AGENTS.md edit.** Per #2881 Out-of-scope and AGENTS.md `wg-every-session-error-must-produce-either` discoverability exit. The gate is discovered via the existing `hr-before-shipping-ship-phase-5-5-runs` umbrella rule.
- **The 5 historical plan annotations preserve audit history.** Do NOT rewrite the historical plan ACs themselves (e.g., do not edit `[ ] Expected: HTTP 200` to `[ ] Expected: SHA match`). They record what the operator actually did at that point in history; the annotation block at top-of-file is the contract update.
- **Sensitive-path scope-out reaffirmation.** `apps/[^/]+/infra/` IS in the canonical sensitive-path regex (preflight Check 6 Step 6.1). The 4 trigger files therefore match. The `## User-Brand Impact` `threshold: none` declaration in this plan IS the documented escape hatch — but the scope-out reason MUST stand on its own merits at preflight time. Reaffirmed: this plan modifies `plugins/soleur/skills/ship/SKILL.md` (workflow file, no user-data path) + `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` (operator runbook, no user-data path) + 5 historical plan files (annotation only) + new test file. The trigger files themselves are touched only as identifier strings inside the gate's regex/array; the diff does NOT modify `ci-deploy.sh` or any other infra script. preflight Check 6 will see: diff matches `apps/[^/]+/infra/` regex zero times → scope-out not even needed. (Documented here as defense-in-depth in case the regex evolves.)

- **CLI verification (#2566 sharp edge).** All CLI invocations embedded in this plan have been verified against `command -v` at plan-time:
  - `doppler` → installed (`--version` 3.75.1)
  - `terraform` → installed (`--version` 1.10.5 in `apps/web-platform/infra/`)
  - `gh` → installed
  - `ssh` with `ConnectTimeout=5` → standard OpenSSH option, verified
  - `sha256sum` → coreutils, verified
  - `systemctl is-active` → systemd standard, verified

## Alternative Approaches Considered

| Approach | Why considered | Why rejected |
|---|---|---|
| Auto-apply on merge via CI claude-code-action | Eliminates operator toil entirely | Violates `hr-menu-option-ack-not-prod-write-auth`; CI SSH keys are dummies (per `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`); `remote-exec` would fail in CI regardless. |
| Block PR merge until the apply runs | Strongest enforcement | Operators frequently can't run prod applies during the same window they merge (different time zones, on-call rotation). Hard block creates merge-thrash; soft prompt + cron fallback is the right balance. |
| Add `terraform_data.deploy_pipeline_fix` to `cloud-init.yml`'s `runcmd` so it self-applies | Eliminates the bridge entirely | `hcloud_server.web` has `lifecycle.ignore_changes = [user_data]` per `#967` to prevent import-artifact-driven server replacement. Removing `ignore_changes` re-introduces a worse problem (any cloud-init drift forces full server replacement). |
| Replace the gate with an AGENTS.md rule "remember to apply when editing trigger files" | Lighter-weight | A textual reminder consumed at every conversation turn doesn't beat a programmatic gate that fires deterministically at the right moment. AGENTS.md byte budget is also constrained per `cq-agents-md-why-single-line`. |
| Use the HTTP probe with CF Access service-token headers (option 1 from #3034) | Already-existing pattern in `deploy-status-debugging.md` | The HTTP probe is proxy-layer; the post-apply question is provisioner-layer. A 200 from the HTTP probe doesn't prove the file provisioners landed — only that the webhook is up and HMAC validates. The file+systemd contract is strictly stronger. (This is the analysis already captured in the 2026-04-29 learning file.) |

## References

- Issue: #2881 (`infra: prevent recurring terraform_data.deploy_pipeline_fix drift via /ship post-merge gate`)
- Issue: #3034 (`ops: webhook smoke-test returns 403 from Cloudflare Access — update post-apply verification contract`)
- Recent ops-remediation: PR #3022 (9th drift cycle reconciliation, 2026-04-29)
- Learning: `knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`
- Learning: `knowledge-base/project/learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md`
- Resource: `apps/web-platform/infra/server.tf:215-269` (`terraform_data.deploy_pipeline_fix` definition)
- Resource: `apps/web-platform/infra/tunnel.tf:46-69` (`cloudflare_zero_trust_access_application.deploy` and service token)
- Skill: `plugins/soleur/skills/ship/SKILL.md` Phase 5.5
- Skill: `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`
- Workflow: `.github/workflows/scheduled-terraform-drift.yml` (cron `0 6,18 * * *` — drift safety net)
- AGENTS.md rule: `hr-menu-option-ack-not-prod-write-auth` (per-command authorization for prod writes)
- AGENTS.md rule: `hr-before-shipping-ship-phase-5-5-runs` (umbrella for Phase 5.5 conditional gates)
- AGENTS.md rule: `wg-every-session-error-must-produce-either` (discoverability exit — drift workflow IS the discovery channel)
