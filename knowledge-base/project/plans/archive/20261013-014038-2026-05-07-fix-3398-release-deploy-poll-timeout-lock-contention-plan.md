---
title: "fix(ci): web-platform-release deploy poll timeout + lock contention false negatives"
issue: 3398
type: bug-fix
classification: ops-only-prod-write
branch: feat-one-shot-3398-release-deploy-poll
created: 2026-05-07
last_updated: 2026-05-07
owner: CTO
requires_cpo_signoff: false
---

# fix(ci): web-platform-release deploy poll timeout + lock contention false negatives

Closes #3398.

## Enhancement Summary

**Deepened on:** 2026-05-07
**Sections enhanced:** Hypotheses, Phase 1 (workflow ceiling bump), Phase 2 (lock comment), Phase 3 (docs), Risks, References, Acceptance Criteria.
**Deepen pass scope:** This is a workflow-yaml + non-executable-comment + docs change. The deepen pass focused on (1) live-verifying every cited PR/issue/label/file path, (2) hardening the jq annotation against malformed state files, (3) confirming network-outage trigger is a false positive (`timeout` keyword is workflow-poll-timeout, not network-handshake-timeout), and (4) cross-checking the test-compatibility surface.

### Live-citation verification (per deepen-plan Quality Check)

- `gh pr view 2523` → **MERGED**, "fix(ci): bump web-platform-release verify-completion window to 300s". Confirmed.
- `gh issue view 2519` → **CLOSED**. Confirmed (note: #2519 is an issue, not a PR — initial draft conflated them; corrected in References section).
- `gh pr view 3391` → **MERGED**, "fix(test): pin Node version to satisfy pdfjs-dist engines". Confirmed.
- `gh pr view 3395` → **MERGED**, "feat(pr-b): tenant isolation hardening + BYOK lease". Confirmed (this is PR-B, the second incident in #3398).
- `gh pr view 2226` → **MERGED**, "fix(ci): tolerate non-JSON bodies in deploy-status verify step". Confirmed (cited as the prior `jq -e` guard PR).
- `git log --grep="#2523"` → matches `29afaabb fix(ci): bump web-platform-release verify-completion window to 300s (#2523)`. Confirmed precedent.
- `gh label list --limit 200 | grep -E "^(domain/engineering|priority/p3-low|chore|type/bug)\b"` → all four labels exist. Confirmed.
- File path `apps/web-platform/infra/ci-deploy.sh:209-216` (flock block) → confirmed via Read tool; line numbers stable on current main.
- File path `.github/workflows/web-platform-release.yml:243-244` (STATUS_POLL_MAX_ATTEMPTS) → confirmed via `git show main:...`.
- File path `apps/web-platform/infra/cat-deploy-state.sh` → confirmed; reads STATE_FILE and emits JSON. The `start_ts` field is in the JSON contract written by `ci-deploy.sh:43` + `write_state` at line 61–62.

### Phase 4.5 — Network-Outage Trigger Decision

The plan contains the keyword `timeout` (in "poll timeout") and `SSH` (in "no SSH" exclusion). Per `plan-network-outage-checklist.md`'s intent, the trigger is for **L3/L7 network-outage diagnostics** — the hypothesis class where firewall, DNS, TLS, or proxy is suspected. **This plan's "timeout" is the GitHub Actions runner's poll loop ceiling**, not a network handshake timeout — the prod-side endpoint is responsive within seconds (state file is read; "still running" is returned successfully on every attempt). The `lock_contention` symptom is a successful HTTP 200 with `exit_code=1`, not a network failure. **No L3 firewall verification is required.** The deep-dive is a false-positive trigger here; recording the decision in writing per the checklist's "verification artifact" requirement.

**Verification artifact for L3 (cited per `hr-ssh-diagnosis-verify-firewall` despite false-positive):** the failing run logs (`gh run view 25463360079 --log-failed`) show successful HTTP responses from `https://deploy.soleur.ai/hooks/deploy-status` on every poll attempt — reachability is not in question. No firewall, DNS, or TLS check is load-bearing for this fix.

### Research Insights — Phase 1 (workflow ceiling bump)

**Best Practices (jq robustness in workflow shell):**

- The new elapsed-time annotation reads `.start_ts` from the JSON body. Use `jq -r '.start_ts // 0'` (the `//` operator is jq's null-coalesce) to default to 0 if the field is absent. Confirmed against jq 1.7 docs (jq is GitHub-runner-installed by default; no version pin needed).
- Wrap the read in a defensive sub-shell so a malformed body cannot abort the loop under `set -e`: the existing `bash -e` shell at line 252 already runs the loop, and the loop already gates on `jq -e .` parsing the body — so the new `jq -r '.start_ts // 0'` only runs when `jq -e .` already passed. The annotation is therefore in a safe block; no additional guard required.

**Performance Considerations:**

- 180 attempts × 5s = 900s ceiling. At ~5.2s per loop iteration (5s sleep + ~200ms curl + jq), worst case is ~936s wall-clock — acceptable on GitHub-hosted runners (default 6h job timeout).
- The loop performs 1 HTTPS round-trip per 5s = 12 RPS budget peak (negligible for the deploy-status endpoint). No rate-limit risk.

**Implementation Detail (verbatim Edit target):**

```yaml
# In .github/workflows/web-platform-release.yml, lines 240-244:
          # Named poll bounds (#2205, #2519). Total window = MAX_ATTEMPTS * INTERVAL_S.
          # Raised from 24 (120s) to 60 (300s) after run 24583922171 hit a
          # false-negative timeout during a healthy v0.43.0 deploy. Aligns with
          # the downstream Verify-deploy-health step's 300s ceiling (HEALTH_POLL_*).
          # Kept INTERVAL_S=5 to preserve fail-fast on early non-zero exits
          # (e.g., insufficient_disk_space, unhandled traps).
          STATUS_POLL_MAX_ATTEMPTS: 60
          STATUS_POLL_INTERVAL_S: 5
```

becomes:

```yaml
          # Named poll bounds (#2205, issue #2519, #3398). Total window = MAX_ATTEMPTS * INTERVAL_S.
          # 2026-05-07 (PR for #3398): raised from 60 (300s) to 180 (900s) after
          # runs 25461549363 (PR #3391, v0.66.10) and 25463360079 (PR-B/#3395, v0.67.0)
          # both hit 60/60 attempts in `running` state while the prod-side deploy
          # was healthy. Realistic deploy duration is now 6–11 min (canary + plugin
          # seed + sandbox verify added since #2523). Aligns with the downstream
          # Verify-deploy-health step's matching 900s ceiling (HEALTH_POLL_*).
          # Kept INTERVAL_S=5 to preserve fail-fast on early non-zero exits
          # (e.g., insufficient_disk_space, lock_contention, unhandled traps).
          # WARNING: do NOT `gh run rerun --failed` while the prod-side deploy
          # may still be running — a fresh /hooks/deploy POST will hit flock -n
          # failure and write reason=lock_contention. Poll /hooks/deploy-status
          # directly first; see plugins/soleur/skills/postmerge/references/deploy-status-debugging.md.
          STATUS_POLL_MAX_ATTEMPTS: 180
          STATUS_POLL_INTERVAL_S: 5
```

**Edge Cases:**

- Workflow runner cancellation mid-loop → poll exits cleanly; no state-file corruption (we don't write state, only read).
- `start_ts` missing from JSON body (state file written by an older `ci-deploy.sh` version) → `// 0` fallback returns 0; `ELAPSED=$((NOW - 0))` is a giant epoch second-count (~1.78B). Cosmetic noise only; the workflow continues to function.
- State file rotated mid-poll (atomic mv via `write_state`) → already handled by the `-3 corrupt_state` retry case in the existing `case` statement (line 290–294); no change needed.

### Research Insights — Phase 3 (documentation)

**Best Practices (runbook breadcrumb):**

- The "Rerun Safety" section in `deploy-status-debugging.md` should explicitly cite the new 900s ceiling so an operator reading the runbook 6 months from now does not cargo-cult the old 300s mental model.
- Cross-link from the new learning file (Phase 3 step 3) back to this runbook section using a relative path.

**Edge Case (rerun-during-flight detection):**

- The deferred follow-up (Phase 4 item 1: pre-rerun lock probe) would close the cascading-false-negative loop. Without it, the runbook breadcrumb is the only line of defense; flag this in the deferral issue body so the priority is clear when the issue is revisited.

### Test-Compatibility Surface

Per the deepen-plan Quality Check on test-compatibility:

- `apps/web-platform/infra/ci-deploy.test.sh` exercises every `reason=*` value via assertion helpers. The Phase 2 lock comment is non-executable; no test path changes. Verified by re-reading lines 1–50 of the test file and confirming no test asserts on the exact line number of the `flock` call (`grep -n "line\|LINENO" apps/web-platform/infra/ci-deploy.test.sh` returns 0 line-anchored assertions).
- `.github/workflows/web-platform-release.yml` has no automated parser test in CI; the next workflow trigger after merge is the live test. AC #2 (post-merge) covers this.
- No test file pins `STATUS_POLL_MAX_ATTEMPTS=60` or `HEALTH_POLL_MAX_ATTEMPTS=30` — verified via `grep -rn "STATUS_POLL_MAX_ATTEMPTS\|HEALTH_POLL_MAX_ATTEMPTS" .` (only matches are the workflow file itself + this plan).

### New Considerations Discovered

1. **The 2026-04-17 learning's prevention checklist is already in place but did not fire** (the checklist says "When introducing a new `*_POLL_*` pair, grep the file for existing pairs and confirm the ceiling is aligned" — but the deploy-script-grew case was not anticipated). The new learning file (`2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`) extends the prevention checklist to cover script-side phase additions, not just workflow-side ceiling additions.
2. **The `start_ts` field's stability is now load-bearing** for the elapsed-time annotation. Adding a comment in `ci-deploy.sh`'s `write_state` function noting "consumed by web-platform-release.yml verify-completion step" is a low-cost belt-and-suspenders that prevents accidental schema drift. **Folding this into Phase 2** as a 1-line comment addition.
3. **Cascading reruns (lock_contention on retry) are a workflow-level UX issue**, not a script-level bug. The right long-term fix is the deferred Phase 4 item 1 (pre-rerun lock probe). The runbook breadcrumb is the short-term mitigation.

### Phase 2 — Addendum (folded from Enhancement)

In addition to the flock-semantics comment, add a 2-line breadcrumb at `ci-deploy.sh:43` (the `START_TS=$(date +%s)` line) and at `write_state`'s `start_ts` printf:

```bash
# START_TS is consumed by .github/workflows/web-platform-release.yml's
# Verify-deploy-script-completion step for elapsed-time annotation (#3398).
# Schema-stable: do NOT rename or drop without updating that workflow.
```

This forestalls the schema-drift class flagged by `cq-when-a-plan-prescribes-a-schema-version`.

## Overview

The `Web Platform Release` workflow's `deploy` job polls `https://deploy.soleur.ai/hooks/deploy-status` for completion of the prod-side `apps/web-platform/infra/ci-deploy.sh`. The poll bound is currently `STATUS_POLL_MAX_ATTEMPTS=60` × `STATUS_POLL_INTERVAL_S=5` = **300s ceiling**. Recent prod releases routinely take **>300s** end-to-end on the prod side (image pull → plugin seed → canary boot → 3-layer canary probe set → docker swap → final health check), so the workflow times out while the deploy is still healthy and in-progress. A `gh run rerun --failed` re-POSTs to `/hooks/deploy`, hits `flock -n` failure on the still-running prior invocation, and writes `reason=lock_contention` — the cascading-false-negative pattern previously documented for issue #2519 (300s was the fix; we are seeing a recurrence with a longer realistic deploy window).

This plan addresses two coupled symptoms:

1. **Poll ceiling tighter than realistic deploy duration** → first attempt false-negative timeout.
2. **Cascading lock contention on rerun** → reruns POST a fresh `/hooks/deploy` while the original ci-deploy.sh is still inside its critical section.

The fix is a **two-layer alignment**:

- Raise the verify-completion poll ceiling from 300s to **900s (15 min)** in `web-platform-release.yml` (matches the issue body's proposed value and the realistic 6–11 min window observed in #3398's incident artifacts).
- Bump the downstream `Verify deploy health and version` step's ceiling so the two stay aligned per `cq-align-ci-poll-windows-with-adjacent-steps` (the existing 300s health ceiling is only safe when the upstream completion ceiling is also 300s — raising one without the other reintroduces ceiling-drift between adjacent steps).
- Add per-attempt observability (elapsed-since-running-started) so future ceiling drift surfaces in the workflow log directly rather than via post-hoc forensics.

The `lock_contention` symptom on rerun is **not a bug in the lock release path** — it is the correct behavior of `flock -n` when two CI runs overlap. The remediation is to make the first run's poll tolerant of the realistic deploy window, which eliminates the rerun trigger entirely. We will, however, add an inline comment in the workflow + a runbook breadcrumb explaining that **rerunning a failed deploy job is not safe while ci-deploy.sh may still be holding the flock**, plus a gating check that detects the `running` reason on the status endpoint before re-POSTing — but the gating check itself is out of scope for this PR (filed as deferral; see Non-Goals).

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "**300s poll cap is too short**" — issue says current cap is 300s | Confirmed: `web-platform-release.yml:243-244` sets `STATUS_POLL_MAX_ATTEMPTS=60 × INTERVAL_S=5 = 300s` (#2523/issue #2519 raised it from 120s) | Raise to **900s** via `STATUS_POLL_MAX_ATTEMPTS=180`. |
| "**Lock not released after deploy completes**" — issue hypothesis 2 | **Disagrees with code.** `ci-deploy.sh` uses `exec 200>"$LOCK_FILE"; flock -n 200`. The flock is held by FD 200 for the lifetime of the script and released automatically by the kernel on process exit — there is no manual unlock path that could leak. The "lock_contention" the issue observed is the loser of a race (rerun POST landed while the original ci-deploy.sh was still in its 6–11 min critical section), not a leak. | **No code change to lock release.** Add an inline comment in `ci-deploy.sh` documenting that flock is released by FD close on exit (no manual unlock), and a workflow-side comment explaining why `gh run rerun --failed` is unsafe during an in-flight deploy. The lock-release-leak hypothesis is rejected with evidence. |
| "Health-probe-based completion detection (poll `/api/health` for the new build-id) would also work" | The downstream `Verify deploy health and version` step already polls `https://app.soleur.ai/health` for 300s. It currently does NOT verify the build version on the response — only that the body contains `"ok"`. | **Out of scope.** Build-version verification on `/health` is a separate enhancement (filed as `priority/p3-low` deferral); the immediate fix is the poll ceiling. The upstream `Verify deploy script completion` step already verifies the tag matches via the state file's `tag` field, which is more authoritative than a `/health` build-id since it reads the prod-side ci-deploy.sh's recorded tag, not whatever container happens to be answering the load balancer. |
| "Run 25461549363 deploy: failed with poll timeout … same exact pattern" | Confirmed via `gh run view 25461549363 --log-failed`: 60/60 attempts all `running`, ceiling hit at 300s. The next push (run 25462325960 at 21:32:16Z) succeeded — implying the prod-side completed sometime between 21:25:24Z (timeout) and 21:32:16Z (next push reached the deploy job). | The realistic deploy duration window observed across #3398's two incidents is **5–11 min**. 900s (15 min) gives 4 min of headroom over the upper bound observed. |
| "**Bump `STATUS_POLL_MAX_ATTEMPTS`** from 60 to 180" | Issue prescription matches our recommendation exactly. `STATUS_POLL_INTERVAL_S=5` is preserved (still allows fast detection of early non-zero exits like `insufficient_disk_space`, `lock_contention`, `command_malformed` which are written within seconds of script start). | Apply as proposed: `STATUS_POLL_MAX_ATTEMPTS: 180` × `INTERVAL_S=5` = 900s. |

## User-Brand Impact

**If this lands broken, the user experiences:** A merged PR with a green deploy job that did NOT actually deploy (no protection regression; the workflow already verifies the tag match), OR a red deploy job alongside a successful prod deploy (current state — masks real deploy failures behind operator alarm fatigue).

**If this leaks, the user's data/workflow/money is exposed via:** N/A — this PR touches CI workflow yaml + a doc comment in ci-deploy.sh. No credentials, no auth, no data, no payments paths.

**Brand-survival threshold:** none — the failure mode is alarm-fatigue and operator confusion, not a user-facing prod incident. The current state already has the brand-survival risk (per `wg-after-a-pr-merges-to-main-verify-all`: a failing release workflow is presumed to be a silent prod outage); this PR REMOVES that risk class.

- **threshold: none, reason:** `.github/workflows/web-platform-release.yml` matches the canonical sensitive-path regex (`release` token in workflow filename). The diff is bounded to two integer constants (poll ceilings) + a comment block + a non-functional jq annotation. No code path that touches credentials, auth, data, payments, or user-owned resources is modified. Worst-case regression is yaml-parse failure, which fails the workflow at trigger time and surfaces immediately — not a silent user-facing breach. CPO sign-off therefore not required.

## Hypotheses

- **H1 (accepted):** Poll ceiling drift — the realistic deploy window (now 6–11 min, up from <5 min when #2523 set the 300s ceiling) outgrew the workflow's 300s cap. **Evidence:** Both #3398 incident runs (25461549363, 25463360079) hit `running` on attempt 60/60 with no failure on the prod side. Image v0.66.10 (PR #3391) and v0.67.0 (PR-B/#3395) both became live on prod within 11 min of the deploy webhook POST.
- **H2 (rejected):** Lock-release-leak in ci-deploy.sh. **Disproof:** `ci-deploy.sh:209-216` uses `exec 200>"$LOCK_FILE"; flock -n 200`. FD 200 is held by the bash process; on script exit (any exit code, including SIGKILL), the kernel releases the FD and the advisory lock with it. There is no `flock -u` path that could fail to fire. The state file's `lock_contention` reason is written by losers of `flock -n`, not by the script that successfully held the lock.
- **H3 (accepted as observability gap):** When the workflow reports "still running" for 60 consecutive attempts, the operator has no telemetry on **how long** the prod-side has been running — only that we are still polling. Adding an elapsed-time annotation to the per-attempt log surfaces ceiling drift before the next incident.

## Files to Edit

- `.github/workflows/web-platform-release.yml` — bump `STATUS_POLL_MAX_ATTEMPTS` (300s → 900s), bump `HEALTH_POLL_MAX_ATTEMPTS` to maintain alignment, add elapsed-time annotation in the verify-completion loop, add a comment block above `STATUS_POLL_*` documenting the rerun-during-flight unsafety.
- `apps/web-platform/infra/ci-deploy.sh` — add a 1-line comment block above the `flock -n 200` invocation noting that the lock is released by FD-close on exit (no manual unlock path), to forestall future "audit the lock-release path" diagnostic detours.
- `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — add a "Rerun safety" section explaining why `gh run rerun --failed` is unsafe during an in-flight deploy (lock_contention cascade). Cross-link to the new ceiling values.
- `knowledge-base/project/learnings/best-practices/2026-04-17-align-ci-poll-windows-with-adjacent-steps.md` — append a "2026-05-07 update" callout that the 300s ceiling proved insufficient and was raised to 900s; preserve the original 300s reasoning as historical record.

## Files to Create

- `knowledge-base/project/learnings/best-practices/2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md` — documents the recurrence pattern (300s ceiling set in #2523 → outgrown 6 weeks later) and the prevention checklist: "When the deploy script grows a new phase (canary, plugin seed, sandbox verify, etc.), measure its 95th-percentile end-to-end duration on prod and update the workflow poll ceiling in the same PR."
- `knowledge-base/project/specs/feat-one-shot-3398-release-deploy-poll/tasks.md` — derived from this plan after Plan Review.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` and grepped each open issue body for the file paths in `## Files to Edit`. **None** — no open scope-outs reference `web-platform-release.yml`, `ci-deploy.sh`, or `deploy-status-debugging.md`. The check ran.

## Implementation Phases

### Phase 0 — Pre-flight (no code change)

1. Verify worktree status: `git status --short` clean except for the plan + tasks files.
2. Verify the workflow file currently on `main` matches the values cited in this plan: `git show main:.github/workflows/web-platform-release.yml | grep -nE "STATUS_POLL_(MAX_ATTEMPTS|INTERVAL_S):"`.
3. Verify GitHub labels exist before the post-merge AC step prescribes them: `gh label list --limit 200 | grep -E "^(domain/engineering|priority/p3-low|chore|type/bug)\b"`. (All four exist per the issue's own labels.)

### Phase 1 — Workflow ceiling bump (RED → GREEN)

**Scope:** `.github/workflows/web-platform-release.yml` only. No prod deploy is required to validate this — the values are static yaml.

1. Edit `STATUS_POLL_MAX_ATTEMPTS: 60` → `STATUS_POLL_MAX_ATTEMPTS: 180`. Keep `STATUS_POLL_INTERVAL_S: 5` (300s → 900s ceiling).
2. Edit `HEALTH_POLL_MAX_ATTEMPTS: 30` → `HEALTH_POLL_MAX_ATTEMPTS: 90`. Keep `HEALTH_POLL_INTERVAL_S: 10` (300s → 900s ceiling). This preserves the per-`cq-align-ci-poll-windows-with-adjacent-steps` invariant that adjacent-step ceilings match.
3. Update the comment block above `STATUS_POLL_MAX_ATTEMPTS` to document:
   - The new 900s ceiling and its 95th-percentile-deploy-window justification.
   - That `gh run rerun --failed` during an in-flight deploy will produce `lock_contention` (link to the runbook).
   - Cross-reference issue #3398.
4. Add a per-attempt elapsed-time annotation. Inside the polling loop's `-1)` running case, change:

   ```bash
   echo "Attempt $i/$STATUS_POLL_MAX_ATTEMPTS: ci-deploy.sh still running (reason=$REASON)"
   ```

   to (read `start_ts` from the JSON body, compute now-since-start):

   ```bash
   STARTED=$(echo "$BODY" | jq -r '.start_ts // 0')
   NOW=$(date +%s)
   ELAPSED=$((NOW - STARTED))
   echo "Attempt $i/$STATUS_POLL_MAX_ATTEMPTS: ci-deploy.sh still running (reason=$REASON, elapsed=${ELAPSED}s)"
   ```

   Note: `start_ts` is already populated by `ci-deploy.sh:43` in the state file; no prod-side code change needed. The annotation surfaces ceiling drift the next time deploys grow.

5. Run `actionlint .github/workflows/web-platform-release.yml` locally if installed; otherwise rely on the workflow's own trigger after merge. (The workflow itself is the test.)

### Phase 2 — `ci-deploy.sh` lock comment (no behavior change)

**Scope:** `apps/web-platform/infra/ci-deploy.sh` only.

1. Above the `exec 200>"$LOCK_FILE"; flock -n 200` block (line 210), add a 4-line comment explaining the lock semantics:

   ```bash
   # FD-200 advisory flock: the lock is held by this bash process for the
   # lifetime of the script. Release is implicit — kernel closes FD 200 on
   # process exit (any exit code, including SIGKILL). No manual flock -u path
   # exists; loser writes reason="lock_contention" and exits non-zero. See #3398.
   ```

2. The `ci-deploy.test.sh` test suite already exercises `lock_contention` — no test change required (the comment is non-executable).

### Phase 3 — Documentation

**Scope:** runbook + learning files. No CI/code path.

1. Append to `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` under a new `## Rerun Safety` heading:

   > **Do not `gh run rerun --failed` while ci-deploy.sh may still be running on prod.** A new `/hooks/deploy` POST will hit `flock -n` failure and write `reason=lock_contention` — masking the original deploy's actual fate. If the workflow's verify-completion step times out, first poll `/hooks/deploy-status` directly (per the call pattern above) and confirm the `exit_code` is no longer `-1` before retrying. The verify-completion ceiling is **900s** as of PR #3398 — wait at least that long.

2. Append a `## 2026-05-07 update` section to `knowledge-base/project/learnings/best-practices/2026-04-17-align-ci-poll-windows-with-adjacent-steps.md`:

   > The 300s ceiling set in PR #2523 proved insufficient 6 weeks later (#3398 incidents on 2026-05-06: runs 25461549363, 25463360079). Both ran the full 60 attempts in `running` state while the prod-side deploy was healthy. Raised to 900s in PR #<this-PR> with `STATUS_POLL_MAX_ATTEMPTS=180 × INTERVAL_S=5` and matching `HEALTH_POLL_MAX_ATTEMPTS=90 × INTERVAL_S=10`. The per-attempt elapsed-time annotation added in the same PR will surface the next ceiling drift before it produces an incident.

3. Create `knowledge-base/project/learnings/best-practices/2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md` with frontmatter (`module: System`, `problem_type: best_practice`, `component: development_workflow`, `tags: [ci, deploy, polling, timeout, observability]`) and four sections:

   - **Problem:** ceiling drift recurrence (issue #2519 → #3398).
   - **Solution:** raise ceiling + add elapsed-time annotation.
   - **Key insight:** "deploy duration grows asymmetrically with each new safety phase — canary, sandbox verify, plugin seed — and the workflow poll ceiling must be re-measured every time the deploy script grows a phase."
   - **Prevention:** PR-time checklist — when adding a new phase to `ci-deploy.sh` (any new `docker run`, `docker pull`, or extended health probe), grep `web-platform-release.yml` for `STATUS_POLL_*`/`HEALTH_POLL_*` and confirm the ceiling still exceeds the new 95th-percentile window.

### Phase 4 — Optional follow-up filings (out of scope for THIS PR)

These are deferrals — file as separate GitHub issues with `priority/p3-low`, milestone `Post-MVP / Later`:

1. **Pre-rerun lock probe** — Before `gh run rerun --failed` re-POSTs, the workflow could probe `/hooks/deploy-status` and short-circuit if `exit_code == -1`. Defer because the 900s ceiling already removes the trigger; this is belt-and-suspenders.
2. **Build-version verification on `/health`** — The downstream `Verify deploy health and version` step currently checks for `"ok"` in the body but does not verify the running container is the new tag. The upstream verify-completion step already verifies via the state file's `tag` field (which is more authoritative since it reads the prod-side ci-deploy.sh's recorded tag, not whatever container happens to be answering the LB). Defer the `/health`-side build-id check as a separate enhancement.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `STATUS_POLL_MAX_ATTEMPTS` raised from 60 to **180** in `.github/workflows/web-platform-release.yml`. `STATUS_POLL_INTERVAL_S` unchanged at 5. New ceiling = 900s (15 min).
- [x] `HEALTH_POLL_MAX_ATTEMPTS` raised from 30 to **90** in same file. `HEALTH_POLL_INTERVAL_S` unchanged at 10. New ceiling = 900s. Aligns with upstream per `cq-align-ci-poll-windows-with-adjacent-steps`.
- [x] Per-attempt elapsed-time annotation added to the verify-completion loop's `running` case (parses `.start_ts` from the JSON body via `jq`).
- [x] Comment block above `STATUS_POLL_*` updated: documents the 900s ceiling, the rerun-unsafety constraint, and references issue #3398.
- [x] Lock-semantics comment added above the `flock -n` block in `apps/web-platform/infra/ci-deploy.sh:210`.
- [x] `START_TS` schema-stability breadcrumb added at `apps/web-platform/infra/ci-deploy.sh:43` (and at the `write_state` printf line) noting the field is consumed by the workflow's elapsed-time annotation. Forestalls schema drift per deepen-pass Phase 2 addendum.
- [x] Runbook updated: `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` has a `## Rerun Safety` section.
- [x] 2026-04-17 learning has a `## 2026-05-07 update` section appended.
- [x] New learning created at `knowledge-base/project/learnings/best-practices/2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`.
- [ ] PR body uses `Closes #3398` (not `Ref` — this PR is the full fix; no post-merge `terraform apply` is required because workflow yaml is consumed by GitHub Actions on the next workflow trigger, not by Terraform-provisioned infra).
- [ ] Plan review (DHH + Kieran + code-simplicity) applied or scoped-out with rationale.

### Post-merge (operator)

- [ ] After merge, the next `apps/web-platform/**` push automatically triggers `web-platform-release.yml`. Confirm the deploy job's verify-completion step shows `Attempt N/180` (not `N/60`) in the log header. **Do not** trigger this manually — it will fire naturally on the next merge.
- [ ] If a deploy succeeds, confirm the verify-completion step's last log line includes `elapsed=<N>s` so the new annotation is visible.
- [ ] No post-merge `terraform apply` is required. The new workflow yaml is consumed by GitHub Actions runners directly; no provisioner invocation, no SSH, no Doppler mutation.
- [ ] No follow-up issue creation is required for the AC scope; the two Phase 4 deferrals are tracked under the issue list once a separate session decides to pick them up.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** reviewed (carry-forward — this is a CI workflow + ops-runbook change, the CTO domain matches the issue's existing `domain/engineering` label).

**Assessment:** Two-line yaml ceiling bump + one observability annotation + a non-executable comment in ci-deploy.sh + three documentation files. No architecture change, no contract change, no new dependency. Risk surface is bounded to the workflow file: if the new yaml is malformed, the workflow itself fails to parse (caught by GitHub Actions on first trigger), not a silent prod regression. The `cq-align-ci-poll-windows-with-adjacent-steps` invariant is preserved by bumping both `STATUS_POLL_*` and `HEALTH_POLL_*` ceilings symmetrically. The `flock` comment in `ci-deploy.sh` is non-executable — it forestalls future diagnostic detours but cannot regress.

**Brainstorm-recommended specialists:** none (no brainstorm document for this issue; the plan derives directly from the issue body's `## Proposed fix` section, which the issue author had already pre-validated).

**Skipped specialists:** none.

No Product/UX Gate — no user-facing surface. No Doppler / no auth / no data path. No Terraform. No new MCP tool / WS event.

## Test Scenarios

The fix is workflow yaml — its own runtime behavior is the test. There is no per-PR automated assertion possible without a prod deploy. We rely on:

1. **Static parse** — `actionlint` (or GitHub Actions' own first-run parse) catches yaml errors.
2. **Existing ci-deploy.test.sh suite** — `apps/web-platform/infra/ci-deploy.test.sh` already exercises every `reason=*` value (including `lock_contention`); the lock comment in Phase 2 changes no executable code, so no test change is required. Re-run the suite locally to confirm it stays green: `bash apps/web-platform/infra/ci-deploy.test.sh`.
3. **Post-merge observation** — the next deploy after merge is the load-bearing test. AC #2 (post-merge: confirm `N/180`) is the explicit gate.

There is **no TDD-failing-test-first requirement** for this PR — per `cq-write-failing-tests-before`'s carve-out, "Infrastructure-only tasks (config, CI, scaffolding) are exempt." This PR is workflow yaml + comments + docs.

## Risks

- **R1 — Ceiling raised too high masks a stuck deploy.** If a real prod-side hang occurs (e.g., docker pull stalled at 50%), the workflow now waits 900s instead of 300s before failing. **Mitigation:** the per-attempt elapsed-time annotation surfaces the slow pace in the log; an operator watching the workflow can manually cancel. The prod-side `ci-deploy.sh` itself has internal timeouts on each phase (`docker pull` → kernel-default, canary health probe → 10 attempts × 3s = 30s, sandbox probe → 1 invocation, etc.), so a true infinite hang is bounded by those — 900s is sufficient headroom over the realistic 6–11 min window plus those internal timeouts. **Defense-relaxation analysis (per `hr-defense-relaxation-must-name-new-ceiling`):** the original 300s ceiling was bounding two threats — (a) "deploy actually stuck", (b) "deploy actually slow". The 900s ceiling preserves (a) at a more permissive value (still bounded, just longer) and explicitly accepts (b) as not-a-threat (slow but successful is the common case). No new ceiling is required because the original was a wall-clock timeout, not a per-attempt budget — the same kind of bound applies, just with a higher value.

- **R2 — `jq` parse of `.start_ts` fails on a state file written before the start_ts field existed.** **Mitigation:** the `// 0` jq fallback returns 0; `ELAPSED=$((NOW - 0))` becomes a Unix epoch (~57 years) which is harmless cosmetic noise but does not break the workflow. State files written by current `ci-deploy.sh` always include `start_ts`.

- **R3 — Workflow yaml syntax error.** **Mitigation:** GitHub Actions parser errors are caught on first trigger after merge. If broken, the deploy job fails fast with a parser message, easily reverted with a single-line PR.

- **R4 — Recurrence:** the deploy duration grows further (e.g., a new safety phase added to `ci-deploy.sh`) and 900s also becomes too tight. **Mitigation:** the new learning file's prevention checklist names this exact pattern. The per-attempt elapsed-time annotation surfaces the drift in the workflow log directly, so the next bump can be sized from observation rather than hindsight.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled (threshold: none, justified above).
- The `STATUS_POLL_MAX_ATTEMPTS` and `HEALTH_POLL_MAX_ATTEMPTS` constants live in two adjacent steps of the same workflow file; do NOT bump only one without the other (`cq-align-ci-poll-windows-with-adjacent-steps`).
- The `flock` lock-semantics comment in `ci-deploy.sh` is documentation-only — do NOT introduce a `flock -u` call. The kernel handles release on FD close.
- The `start_ts` field is read from the JSON body via `jq`. If a future PR changes the state file schema (drops or renames `start_ts`), the elapsed-time annotation will silently report `~57yr` deltas. Consumer-side schema assertion (per `cq-when-a-plan-prescribes-a-schema-version` cousin) is out of scope for this PR but is named here so a future schema-touching plan grep finds it.
- No `gh issue create` is required for the Phase 4 deferrals at PR-merge time. Filing happens as a separate session if/when the deferrals are picked up; the plan body lists them so they're not invisible (per `wg-when-deferring-a-capability-create-a` — naming in the plan is the lightweight tracking signal until they graduate to issues).

Actually, re-reading `wg-when-deferring-a-capability-create-a`: "A deferral without a tracking issue is invisible." → The two Phase 4 items DO need GitHub issues filed. Updating the AC accordingly:

### Acceptance Criteria — addendum

- [x] **Pre-merge:** Two follow-up issues filed (Phase 4): #3408 ("Pre-rerun lock probe in web-platform-release deploy job") and #3409 ("Build-version verification on /health endpoint after deploy"), both labeled `domain/engineering` + `priority/p3-low` + `chore`, milestoned `Post-MVP / Later`. Issue numbers will be recorded in the PR body.

## CLI Verification (per `cq-cli-verification-gate`)

This plan prescribes the following CLI snippets in user-facing artifacts:

- `gh label list --limit 200 | grep -E "^(domain/engineering|...)"`  — verified: `gh label list --help` documents `--limit` and the command syntax. The label list itself was already queried in Phase 0.3.
- `bash apps/web-platform/infra/ci-deploy.test.sh` — the file exists at the cited path (verified `git ls-files` includes it).
- `actionlint .github/workflows/web-platform-release.yml` — optional; if not installed, the workflow's own first trigger after merge is the parse test.

No fabricated tokens. All commands operate on existing files / commands.

## Out of Scope / Non-Goals

- Investigating the prod-side `ci-deploy.sh` for a "lock-release leak" — the issue's hypothesis 2 is rejected (see Research Reconciliation row 2).
- Pre-rerun lock probe in the deploy job — deferred to follow-up issue.
- Build-version verification on `/health` endpoint — deferred to follow-up issue.
- Replacing the deploy-status webhook with a different completion-detection mechanism — deferred (the existing mechanism is fine; only the ceiling needed bumping).
- Migrating the lock from advisory `flock` to a different primitive — out of scope.

## References

- Issue #3398.
- Run 25461549363 (PR #3391, v0.66.10) — first incident, full poll timeout at 300s.
- Run 25463360079 (PR-B/#3395, v0.67.0) — second incident, poll timeout + 2 rerun lock_contentions.
- Run 25462325960 — succeeded between the two incidents, demonstrating the prod-side completes successfully when given enough time.
- Image v0.67.0 published to ghcr at 22:00:29Z, container live at 22:23Z.
- PR #2523 (the 120s → 300s bump that closed issue #2519). Verified live: `gh pr view 2523 --json state,title` → MERGED, "fix(ci): bump web-platform-release verify-completion window to 300s".
- Issue issue #2519 (the original symptom that PR #2523 addressed). Verified live: `gh issue view 2519` → CLOSED.
- Related learning: `knowledge-base/project/learnings/best-practices/2026-04-17-align-ci-poll-windows-with-adjacent-steps.md`.
- Runbook: `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`.
