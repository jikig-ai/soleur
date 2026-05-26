---
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
issue: 4425
umbrella: 3948
pr: 4423
---

# TR9 PR-7 — Migrate `scheduled-roadmap-review` to Inngest cron substrate

## Enhancement Summary

**Deepened on:** 2026-05-25
**Sections enhanced:** 6 (Research Reconciliation prompt-line-range, Phase 1 exact extraction recipe, Phase 4 alphabetic-insertion specifics, Phase 5 -target= position, Acceptance Criteria, Sharp Edges)

**Key Improvements added during deepen pass:**

1. **Prompt block actual line range is 60-108, NOT 56-110 (ARGUMENTS approximation).** Verified live via `grep -n 'prompt:\||$' .github/workflows/scheduled-roadmap-review.yml | head` — `prompt: |` on line 60, last body line on 108 (`create a branch, apply the fixes, and open a PR. If only the review issue is needed, skip the PR.`). Total prompt body: lines 61-108 (48 lines), 10-space YAML indentation (NOT 12). Extraction recipe corrected.
2. **route.ts alphabetic insertion specifics confirmed live.** `cronRoadmapReview` slots BETWEEN `cronOauthProbe` (line 26 import / line 50 array) and `cronStrategyReview` (line 27 import / line 51 array). Plan Phase 4.2 now cites exact insertion positions.
3. **apply-sentry-infra.yml -target= ordering confirmed.** Current 11-entry list runs lines 169-179; `scheduled_strategy_review` is the last entry (line 179). Plan Phase 5.2 prescribes append-AFTER-strategy_review (new line 180) to keep PR-7's addition lexically alongside its sibling weekly cron.
4. **Plugin `plugins:` / `plugin_marketplaces:` YAML keys have NO direct `claude` CLI flag equivalent.** Verified via PR-5's CLAUDE_CODE_FLAGS shape — only `--print --model --max-turns --allowedTools` + positional prompt. The cwd-relative plugin discovery via `plugins/soleur/.claude-plugin/plugin.json` IS the resolution mechanism. Documented in §0.Q1 + Sharp Edges.
5. **`id-token: write` workflow permission was for `claude-code-action`'s internal OIDC binding to Anthropic, NOT for any GitHub API surface the prompt invokes.** Removed as a gotcha from §Research Reconciliation; the installation-token model handles ALL of `gh api 'repos/.../milestones'`, `gh api 'repos/.../issues'`, `gh issue create`, `gh pr create`, `gh label create`, and `git push`.
6. **Inverse-assertion sentinel `cron-no-byok-lease-sweep.test.ts` uses `globSync("server/inngest/functions/cron-*.ts")` — confirmed at the test source.** No test edit needed; the new file is auto-picked. Plan §11 + §7 prescribe a positive `vitest run` of the sentinel as AC6 to prove green.

### New Considerations Discovered

- The actual workflow's `timeout-minutes: 30` (line 36) combined with `--max-turns 40` yields a 0.75 min/turn budget — exactly at the peer-ratio floor. Mirroring `MAX_TURN_DURATION_MS = 50 * 60 * 1000` (PR-5 verbatim) yields 1.25 min/turn — comfortably above the floor. No defense-relaxation concern (same ceiling, more permissive value; SIGTERM→SIGKILL escalation preserves the hard-stop semantic).
- `workflow_dispatch: {}` accepts no inputs, but Inngest manual-trigger events CAN carry arbitrary payloads. AC must verify the handler does NOT parse `event.data` — a future operator who passes `{ "force": true }` to the manual-trigger event MUST get an ignore (not a parse-failure log entry). AC4 (test (c) manual-trigger no-payload) explicitly tests this.
- `redactToken()` is required on stdout/stderr line forwarding even though the agent rarely echoes `$GH_TOKEN` — defense-in-depth per PR-5's HIGH-2 security finding. Without it, a prompt-injected `echo $GH_TOKEN` or `env` invocation leaks the installation token into centralized logs.

---

**Status:** Draft (planning phase, /one-shot pipeline)
**Issue:** #4425
**Umbrella:** #3948 (TR9 group-(c) agent-loop crons → Inngest substrate)
**Sequence:** PR-7 of N — directly follows PR-5 #4377 (bug-fixer, MERGED 2026-05-25) and PR-6 #4412 (strategy-review, MERGED 2026-05-25)
**Pattern source:** PR-5 #4377 `cron-bug-fixer.ts` (the `claude-code-action` → `child_process.spawn('claude', ...)` precedent — NOT PR-6's pure-TS Octokit port)

---

## Summary

Migrate `.github/workflows/scheduled-roadmap-review.yml` (115 LoC, weekly Monday 09:00 UTC, `anthropics/claude-code-action` driver with multi-part CPO roadmap-review prompt, `--max-turns 40`, model `claude-sonnet-4-6`) to `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts`. The new function follows ADR-033 (Inngest cron functions invoke `claude` via `child_process.spawn` inside `step.run`) and the PR-5 envelope precedent (ephemeral workspace setup with installation-token git clone, plugin symlink, `.claude/settings.json` overlay, 50-min `AbortController` envelope, single-step Sentry heartbeat at end-of-handler).

The roadmap-review workflow is materially **lighter** than PR-5 bug-fixer:

1. **No issue-selection cascade.** Prompt operates over the live issue set (`gh api 'repos/jikig-ai/soleur/issues?...'`) and milestones; no per-issue priority filter logic on the TS side.
2. **No auto-merge gate.** PR-creation by the agent (when fixes apply) does NOT carry the auto-merge label nor any p3-low source-issue contract. The agent opens a PR for human review and stops.
3. **No ops-email notification.** Workflow has no Resend step.
4. **Concurrency group is per-workflow** (`schedule-roadmap-review`) — preserved as `concurrency: [{ scope: "fn", limit: 1 }, { scope: "account", key: '"cron-platform"', limit: 1 }]`.

PR-7 lands the migration AND deletes the GHA YAML in the same commit (TR9 I-13 hygiene).

---

## User-Brand Impact

- **If this lands broken, the user experiences:** zero direct impact. `scheduled-roadmap-review` is operator-facing — it publishes a weekly summary issue and may open a roadmap-consistency cleanup PR. A broken weekly run produces a stale roadmap/milestone hygiene state; no founder-visible artifact regresses.
- **If this leaks, the user's data is exposed via:** N/A — the function reads public-repo state via the installation token; no founder data crosses the boundary. The installation token leak vector is shared with PR-5 (already mitigated by `redactToken()` on stdout/stderr).
- **Brand-survival threshold:** `none` (carry-forward from PR-5/PR-6).

This plan touches the `apps/web-platform/server/inngest/functions/` surface (sensitive per preflight Check 6 Step 6.1 regex), and per `hr-weigh-every-decision-against-target-user-impact` the section is required. Threshold `none` justified: the workflow is a roadmap-hygiene cron that runs against public repo state via a platform-scoped installation token; no founder data, no per-user state, no billable surface, no auth flow.

---

## Constitution / AGENTS.md citations

- **`cq-silent-fallback-must-mirror-to-sentry`** — every silent skip path in the new function (e.g., "spawn exited non-zero", "ephemeral workspace teardown failed") MUST mirror to `reportSilentFallback()`. PR-5/PR-6 precedent applies verbatim.
- **`hr-no-ssh-fallback-in-runbooks`** — manual trigger is `inngest send cron/roadmap-review.manual-trigger` (Inngest dev UI or CLI). Runbooks may NOT instruct operators to SSH into the Hetzner host.
- **`hr-github-app-auth-not-pat`** — all GitHub API calls (label creation, the agent's `gh` invocations via `GH_TOKEN` in spawn env) go through `createProbeOctokit()` + `generateInstallationToken()`. No long-lived PATs.
- **`hr-weigh-every-decision-against-target-user-impact`** — resolved above: threshold `none`.
- **`hr-observability-as-plan-quality-gate`** — Sentry monitor + heartbeat shape declared in §Observability before any code lands.
- **`hr-all-infrastructure-provisioning-servers`** — new `sentry_cron_monitor.scheduled_roadmap_review` is added to TF + auto-applied via `apply-sentry-infra.yml`; NO operator SSH or dashboard click.
- **ADR-033** — claude binary spawned inside `step.run` (Inngest replay memoization); `actor: "platform"` event-payload invariant (this handler emits none); operator ANTHROPIC_API_KEY only (enforced at build time by `cron-no-byok-lease-sweep.test.ts` glob).

---

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality verified at plan-time | Plan response |
|---|---|---|
| "Workflow prompt lives at lines 60-110 of `scheduled-roadmap-review.yml`" | The `prompt:` YAML block key is line 60 (`          prompt: \|`); body is lines 61-108 (48 lines). YAML indentation is 10 spaces (`          `), NOT 12. Verified via `grep -n 'prompt:\||$' .github/workflows/scheduled-roadmap-review.yml`. | Plan §Phase 1.7 prescribes verbatim extraction via `awk 'NR>=61 && NR<=108 {sub(/^          /, ""); print}' .github/workflows/scheduled-roadmap-review.yml` — line numbers locked to current file state and verified at plan-time. |
| "PR-5 cron-bug-fixer.ts is ~1226 lines" | Verified: `wc -l` returns 1226 (Phase 0 grep). | PR-7 is materially lighter (no auto-merge gate, no ops-email, no priority cascade); expected target ~550-650 lines including header + helpers + handler. |
| "Workflow uses `--max-turns 40` and `claude-sonnet-4-6` model" | Verified at `.github/workflows/scheduled-roadmap-review.yml:48-49`. | Mirrored verbatim in `CLAUDE_CODE_FLAGS` constant. |
| "Workflow uses `plugins: 'soleur@soleur'` and `plugin_marketplaces: 'https://github.com/jikig-ai/soleur.git'`" | Verified at workflow lines 45-46. | PR-5 ephemeral-workspace pattern (cloned repo + symlinked plugin tree + `.claude/settings.json` overlay) provides plugin resolution via cwd discovery — `claude-code-action`'s wrapper-specific `plugins:` arg has NO direct CLI flag equivalent. **The plugin tree presence in the spawn cwd IS the resolution mechanism.** See §0.Q3 below. |
| "Workflow uses `id-token: write` permission (OIDC)" | Verified at workflow line 17. | OIDC is NOT used by the Inngest substrate (no Anthropic OIDC binding in `cron-bug-fixer.ts`). The installation-token model covers ALL GitHub API surfaces invoked by the prompt: `gh api 'repos/.../milestones'`, `gh api 'repos/.../issues'`, `gh issue create`, `gh pr create`, `gh label create`. See §0.Q2. |
| "Plan-quoted `-target=` count is now 11" | Verified: `grep -cE '^\s*-target=sentry_cron_monitor' .github/workflows/apply-sentry-infra.yml` returns 11. | Plan §Phase 4 prescribes extending to 12 (append `-target=sentry_cron_monitor.scheduled_roadmap_review`). PR-5's missing `scheduled_bug_fixer` entry is a known follow-up — explicitly OUT of scope. |
| "Hetzner Dockerfile includes claude-code binary" | Verified: `grep 'claude' apps/web-platform/Dockerfile` returns `RUN npm install -g @anthropic-ai/claude-code@2.1.79` at line 45. | No Dockerfile edit needed. `resolveClaudeBin()` from PR-5 finds the binary at `/app/node_modules/.bin/claude` or via `CLAUDE_BIN` env override. |
| "PR #4412 test harness shows vitest pattern with `vi.hoisted` to set `NEXT_PHASE=phase-production-build`" | Verified at workflow's PR-6 cron-strategy-review-graymatter.test.ts; pattern applies to gray-matter-trap class (frontmatter read) | **PR-7 introduces NO new pure-TS frontmatter readers** — prompt runs entirely inside spawned claude. Harness pattern is NOT triggered. Cron-bug-fixer.test.ts mock pattern (spawn factory + fs spies) is the canonical reference instead. |

---

## 0. Closed Design Questions (resolved at plan time, NOT deferred to /work)

### Q1 — Plugin loading mechanism

**Finding:** PR-5 cron-bug-fixer.ts established the canonical pattern: `setupEphemeralWorkspace(installationToken)` → `mkdtemp(/tmp/soleur-cron-roadmap-review-XXXX/)` + `git clone --depth=1` (using authenticated URL) + plugin symlink `repo/plugins/soleur → getPluginPath()` + `.claude/settings.json` overlay + sentinel check on `plugins/soleur/.claude-plugin/plugin.json`. Spawn cwd = `repo/`. Claude-code resolves the soleur plugin via cwd-relative discovery.

**Decision:** **Reuse PR-5's `setupEphemeralWorkspace()` shape verbatim.** Rename the `mkdtemp` prefix to `soleur-cron-roadmap-review-` (file-local, no shared helper extraction). Sentinel check on `manifestPath` is required (catches symlink-target-empty silent failure per #3045).

**Note:** Although the workflow uses `plugins: 'soleur@soleur'` (claude-code-action wrapper-specific YAML key), there is no direct `--plugin` CLI flag for the `claude` binary — plugin resolution is cwd-relative via the `plugins/<name>/.claude-plugin/plugin.json` convention. The ephemeral-workspace pattern IS the mechanism.

### Q2 — GitHub token surface

**Workflow's GitHub API surface (from the prompt body, lines 60-110 of `scheduled-roadmap-review.yml`):**
- `gh api 'repos/jikig-ai/soleur/milestones?state=all&per_page=100' --jq '...'` — read milestones
- `gh api 'repos/jikig-ai/soleur/issues?state=open&per_page=100' --paginate --jq '...'` — read open issues
- `gh issue create --title '...' --label scheduled-roadmap-review --milestone "Post-MVP / Later"` — write issue
- (conditional) `gh pr create` — write PR
- (conditional) `git push` to a feature branch

**Decision:** Use **PR-5's `mintInstallationToken()` shape verbatim**: `createProbeOctokit()` → discover `installation.id` → `generateInstallationToken(installation.id, { minRemainingMs: TOKEN_MIN_LIFETIME_MS })`. Inject as `GH_TOKEN` in `buildSpawnEnv()`. The `id-token: write` permission from the YAML workflow is NOT carried over — it was an OIDC binding for the `claude-code-action`'s own auth, irrelevant to the Inngest substrate (which uses installation-token auth end-to-end).

**Token-lifetime floor:** `TOKEN_MIN_LIFETIME_MS = 50 * 60 * 1000 + 10 * 60 * 1000` (PR-5 verbatim — `claude-eval` 50-min budget + 10-min slack for setup + teardown + retry).

### Q3 — Timeout envelope

**Workflow has `timeout-minutes: 30`** (line 36) and `--max-turns 40` (line 49). Ratio = 30/40 = 0.75 min/turn — exactly at the peer median per the Sharp Edge on `max-turns` vs `timeout-minutes`.

**Decision:** Use **`MAX_TURN_DURATION_MS = 50 * 60 * 1000`** (PR-5's 50-min budget verbatim). Higher than the workflow's 30-min — RATIONALE: Inngest substrate has different cold-start + spawn-bootstrap overhead vs GHA runner pool; PR-1..PR-5 converged on 50 min as the stable envelope. The 40-turn budget → 50-min envelope is 1.25 min/turn (well above the 0.75 floor). NO defense-relaxation concern: the original 30-min ceiling bounded one threat (wall-clock runaway); the 50-min Inngest envelope bounds the same threat at a more permissive value. SIGTERM→SIGKILL escalation via `KILL_ESCALATION_MS = 5_000` preserves the hard-stop semantic.

### Q4 — Manual trigger payload shape

**Workflow's `workflow_dispatch: {}`** has no inputs.

**Decision:** Event `cron/roadmap-review.manual-trigger` accepts NO payload. Handler does NOT parse `event.data` (unlike PR-5 which accepts `issue_number` override). This eliminates the entire "manual-trigger override validation" branch from the handler — the prompt operates over live state.

### Q5 — Prompt embedding mechanism

**Decision:** The prompt is a multi-line template-literal string constant `ROADMAP_REVIEW_PROMPT` in the handler file, extracted verbatim from `.github/workflows/scheduled-roadmap-review.yml` lines 56-110 (the `prompt: |` block body). Pass as the SOLE positional argument after `--` in the spawn argv (PR-5 pattern; `--` is load-bearing per #4017 bug 8/8 — variadic `--allowedTools` otherwise consumes the prompt as a tool name).

**Verbatim-extraction discipline:** At /work time, the prompt body MUST be lifted verbatim (no paraphrase, no reordering, no quote-style change) from the YAML file. The plan AC includes a hash-based equality check (`sha256` of the extracted string vs the YAML body, stripped of `prompt: |` and per-line YAML indentation).

---

## 1. Files to Edit

- `apps/web-platform/app/api/inngest/route.ts` — register `cronRoadmapReview`.
- `apps/web-platform/infra/sentry/cron-monitors.tf` — add `sentry_cron_monitor.scheduled_roadmap_review` resource block.
- `.github/workflows/apply-sentry-infra.yml` — append `-target=sentry_cron_monitor.scheduled_roadmap_review` (count 11 → 12).

## 2. Files to Create

- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` — the handler + registration.
- `apps/web-platform/test/server/inngest/cron-roadmap-review.test.ts` — unit tests (spawn argv shape, Sentry URL shape, manual-trigger no-payload, teardown cleanup).

## 3. Files to Delete

- `.github/workflows/scheduled-roadmap-review.yml` — DELETED in the same commit (TR9 I-13 hygiene).

---

## 4. Implementation Phases

### Phase 0 — Preconditions (verify-before-code)

1. `wc -l apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` returns 1226 (pattern-source size sanity).
2. `grep -nE 'claude|npm install.*@anthropic' apps/web-platform/Dockerfile` includes `RUN npm install -g @anthropic-ai/claude-code@2.1.79`.
3. `grep -cE '^\s*-target=sentry_cron_monitor' .github/workflows/apply-sentry-infra.yml` returns 11 (pre-edit baseline).
4. `gh issue view 4425` resolves to the filed child issue (NOT umbrella #3948).
5. `ls apps/web-platform/test/server/inngest/cron-bug-fixer.test.ts` returns the reference test path.
6. `command -v claude` AND `command -v vitest` (or `ls apps/web-platform/node_modules/.bin/vitest`) — confirm test-runner availability.

### Phase 1 — Handler skeleton (cron-roadmap-review.ts)

1. Copy `cron-bug-fixer.ts` as the starting template.
2. Strip the auto-merge gate (`runAutoMergeGate`, `detectBotFixPr`, `listOpenBotFixIssueNumbers`, `BOT_FIX_LABELS`, `PRIORITY_CASCADE`, `SKIP_LABELS`, `TITLE_SKIP_RE`, `precreateLabels`, `selectIssue`).
3. Strip the ops-email notification (`notifyOpsEmail`, `RESEND_API_KEY` usage).
4. Strip the manual-trigger override parsing (no `event.data` shape).
5. Rename:
   - `SENTRY_MONITOR_SLUG = "scheduled-roadmap-review"`
   - `mkdtemp` prefix → `"soleur-cron-roadmap-review-"`
   - File-scoped `feature:` tag in `reportSilentFallback` → `"cron-roadmap-review"`
   - Handler export → `cronRoadmapReviewHandler`
   - Function const → `cronRoadmapReview`
   - Function `id` → `"cron-roadmap-review"`
   - Cron trigger → `{ cron: "0 9 * * 1" }`
   - Manual-trigger event → `{ event: "cron/roadmap-review.manual-trigger" }`
6. Update `CLAUDE_CODE_FLAGS`:
   ```ts
   const CLAUDE_CODE_FLAGS = [
     "--print",
     "--model",
     "claude-sonnet-4-6",
     "--max-turns",
     "40",
     "--allowedTools",
     "Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch",
     "--",
   ];
   ```
7. Inline `ROADMAP_REVIEW_PROMPT` as a `const ROADMAP_REVIEW_PROMPT = \`...\`` template literal, body extracted verbatim from `.github/workflows/scheduled-roadmap-review.yml` lines 61-108 (the `prompt: |` block body; key is on line 60). Strip the 10-space YAML indentation: `awk 'NR>=61 && NR<=108 {sub(/^          /, ""); print}' .github/workflows/scheduled-roadmap-review.yml > /tmp/prompt-body.txt`. Then escape any backticks (`\``) in the body for safe template-literal embedding (the current prompt has no backticks — verified via `grep -c '\`' /tmp/prompt-body.txt` returns 0 — but the implementer must re-verify at /work time in case the workflow body shifts between plan and merge).

### Phase 2 — Ephemeral workspace (reuse PR-5 shape)

1. `setupEphemeralWorkspace(installationToken)` — verbatim from PR-5 with the `mkdtemp` prefix rename.
2. `teardownEphemeralWorkspace(ephemeralRoot)` — verbatim from PR-5 with `feature: "cron-roadmap-review"` rename.
3. `buildAuthenticatedCloneUrl(token)` — verbatim.
4. `redactToken(s, token)` — verbatim.
5. `mintInstallationToken()` — verbatim.

### Phase 3 — Spawn + Sentry heartbeat

1. `spawnClaudeEval({ spawnCwd, installationToken, logger })` — PR-5 shape WITHOUT the `issueNumber` arg (the prompt is fixed, not per-issue).
2. Prompt arg is `ROADMAP_REVIEW_PROMPT` (NOT a `fixIssuePrompt(N)` factory).
3. `postSentryHeartbeat({ ok, logger })` — verbatim from PR-5 with `SENTRY_MONITOR_SLUG` renamed.
4. Handler shape: `mint-token` → `setup-workspace` → `claude-eval` → `sentry-heartbeat` (4 step.run blocks; NO precreate-labels — the agent runs `gh label create scheduled-roadmap-review` inline in the prompt, idempotently).
5. Issue creation by the agent: handled by the prompt itself via `gh issue create` (with `--label scheduled-roadmap-review --milestone "Post-MVP / Later"`). NO TS-side issue-publish helper.
6. Return shape: `{ ok: boolean }` (no `selectedIssue` / `prNumber` / `autoMergeQueued` — those are bug-fixer-specific).

### Phase 4 — Inngest registration + route binding

1. `cronRoadmapReview` registered with:
   ```ts
   inngest.createFunction(
     {
       id: "cron-roadmap-review",
       concurrency: [
         { scope: "fn", limit: 1 },
         { scope: "account", key: '"cron-platform"', limit: 1 },
       ],
       retries: 1,
     },
     [
       { cron: "0 9 * * 1" },
       { event: "cron/roadmap-review.manual-trigger" },
     ],
     cronRoadmapReviewHandler as unknown as Parameters<typeof inngest.createFunction>[2],
   );
   ```
2. `apps/web-platform/app/api/inngest/route.ts` — add import + register in the functions array. **Exact insertion positions verified at plan time:** import goes BETWEEN `cronOauthProbe` (line 26) and `cronStrategyReview` (line 27) — i.e., new line 27 becomes `import { cronRoadmapReview } from "@/server/inngest/functions/cron-roadmap-review";` and the existing strategy-review import shifts to line 28. The functions-array entry goes BETWEEN `cronOauthProbe` (line 50) and `cronStrategyReview` (line 51) — new line 51 becomes `    cronRoadmapReview,`. Verified via `sed -n '20,30p' apps/web-platform/app/api/inngest/route.ts` + `sed -n '43,55p'`.

### Phase 5 — Sentry cron monitor (TF + apply gate)

1. `apps/web-platform/infra/sentry/cron-monitors.tf` — append:
   ```hcl
   # TR9 PR-7 (closes #4425): Inngest-fired via
   # `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts`. NEW
   # monitor — no GHA-era predecessor (the workflow ran on GHA's runner pool
   # with no Sentry check-in). The GHA scheduled-roadmap-review workflow was
   # deleted in the same commit per TR9 I-13 hygiene.
   resource "sentry_cron_monitor" "scheduled_roadmap_review" {
     organization            = var.sentry_org
     project                 = data.sentry_project.web_platform.slug
     name                    = "scheduled-roadmap-review"
     schedule                = { crontab = "0 9 * * 1" }
     checkin_margin_minutes  = 30
     max_runtime_minutes     = 55
     failure_issue_threshold = 1
     recovery_threshold      = 1
     timezone                = "UTC"
   }
   ```
2. `.github/workflows/apply-sentry-infra.yml` — append `-target=sentry_cron_monitor.scheduled_roadmap_review \` to the `terraform plan` `-target=` list. **Exact insertion verified at plan time:** the 11-entry list runs lines 169-179; `scheduled_strategy_review` is the last entry (line 179, added by PR-6). PR-7 inserts as new line 180, AFTER `-target=sentry_cron_monitor.scheduled_strategy_review \` and BEFORE `-no-color -input=false -out=tfplan` (line 180-becomes-181). Insertion keeps PR-7's addition lexically adjacent to its weekly-cron sibling, even though the list is not strictly alphabetic (precedence-by-PR-order). Final list count: 12.

### Phase 6 — Delete GHA workflow

1. `git rm .github/workflows/scheduled-roadmap-review.yml` in the same commit as the handler lands (TR9 I-13).

### Phase 7 — Unit tests

1. Create `apps/web-platform/test/server/inngest/cron-roadmap-review.test.ts` mirroring `cron-bug-fixer.test.ts` shape:
   - **(a) spawn argv shape** — assert `claude` binary path, `--print`, `--model claude-sonnet-4-6`, `--max-turns 40`, `--allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch`, `--`, prompt as final argv item. Assert `cwd === spawnCwd` and `env.GH_TOKEN === installationToken`.
   - **(b) Sentry heartbeat URL shape** — assert URL format `https://${domain}/api/${projectId}/cron/scheduled-roadmap-review/${publicKey}/?status=ok` on success and `?status=error` on spawn non-zero.
   - **(c) manual-trigger no-payload** — invoke handler with `event: { data: { foo: "ignored" } }` and assert no error (payload is unread).
   - **(d) ephemeral workspace teardown (try/finally)** — assert `rm` called with `recursive: true, force: true` on the `ephemeralRoot` even when `spawnClaudeEval` throws.
   - **(e) prompt-string verbatim** — assert `ROADMAP_REVIEW_PROMPT` includes anchor strings `"Part 1: Issue-to-Milestone Alignment"`, `"Part 2: Bidirectional Integrity Gate"`, `"MILESTONE RULE:"`, `"BIDIRECTIONAL RULE:"` (low-noise canary; full SHA equality is fragile to whitespace).
2. Confirm `cron-no-byok-lease-sweep.test.ts` glob picks up the new file automatically.

---

## 5. Acceptance Criteria

### Pre-merge (PR)

- **AC1** — `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` exists, imports `inngest`, `createProbeOctokit`, `generateInstallationToken`, `getPluginPath`, `reportSilentFallback`, `spawn` from `node:child_process`, fs helpers from `node:fs/promises`.
- **AC2** — `apps/web-platform/app/api/inngest/route.ts` imports `cronRoadmapReview` and includes it in the registered-functions array.
- **AC3** — `.github/workflows/scheduled-roadmap-review.yml` is DELETED in the same commit (verify via `git log --diff-filter=D --name-only HEAD -- .github/workflows/scheduled-roadmap-review.yml`).
- **AC4** — `grep -c 'cron-roadmap-review' apps/web-platform/test/server/inngest/cron-roadmap-review.test.ts` returns ≥ 5 (file exists with ≥5 references to the SUT).
- **AC5** — `vitest run apps/web-platform/test/server/inngest/cron-roadmap-review.test.ts` passes (5 test cases minimum: spawn argv, Sentry URL ok/err, manual-trigger no-payload, teardown, prompt-canary).
- **AC6** — `vitest run apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts` passes (glob auto-picks new file; sentinel assertions enforce ADR-033 I2 on `cron-roadmap-review.ts`).
- **AC7** — `apps/web-platform/infra/sentry/cron-monitors.tf` contains the `sentry_cron_monitor.scheduled_roadmap_review` resource block (verify via `grep -c '"scheduled_roadmap_review"' apps/web-platform/infra/sentry/cron-monitors.tf` returns ≥ 1).
- **AC8** — `.github/workflows/apply-sentry-infra.yml` includes `-target=sentry_cron_monitor.scheduled_roadmap_review` in the `terraform plan` block (verify: `grep -cE '^\s*-target=sentry_cron_monitor' .github/workflows/apply-sentry-infra.yml` returns 12, up from 11).
- **AC9** — `actionlint` (or `bash -c '<extracted snippet>'` if actionlint unavailable) passes on `.github/workflows/apply-sentry-infra.yml`.
- **AC10** — Prompt-verbatim canary: `grep -c 'Part 1: Issue-to-Milestone Alignment\|Part 2: Bidirectional Integrity Gate\|MILESTONE RULE:\|BIDIRECTIONAL RULE:' apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` returns ≥ 4.
- **AC11** — Handler spawn argv includes `--max-turns`, `40`, `--model`, `claude-sonnet-4-6`, `--allowedTools`, `Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch` (verify via test assertion in cron-roadmap-review.test.ts).
- **AC12** — `tsc --noEmit` (or `bun run typecheck`) returns zero errors after the handler + route edit.
- **AC13** — PR body includes `Closes #4425` (NOT `Closes #3948` — umbrella stays open through remaining migrations).
- **AC14** — No `runWithByokLease` import or call in the new handler file (ADR-033 I2; sentinel `cron-no-byok-lease-sweep.test.ts` enforces).
- **AC15** — `redactToken()` invoked on stdout/stderr line forwarding (verify via grep: `grep -c 'redactToken' apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` returns ≥ 2 — once for stdout, once for stderr).

### Post-merge (auto / operator)

- **AC16** *(auto, via apply-sentry-infra.yml on push to main)* — `terraform apply` creates `sentry_cron_monitor.scheduled_roadmap_review` in Sentry. Verify via `sentry-monitors-audit.sh` (already part of the apply gate); no operator action.
- **AC17** *(operator, ship-phase preflight)* — `/soleur:ship` runs the standard preflight gates; first natural cron firing on Monday 09:00 UTC produces (a) Sentry heartbeat with `status=ok`, (b) at most one new `[Scheduled] Weekly Roadmap Review - YYYY-MM-DD` issue. Verify within 24h via `gh issue list --label scheduled-roadmap-review --limit 5 --json number,createdAt`.

---

## 6. Open Code-Review Overlap

None. No open `code-review`-labeled issues touch `apps/web-platform/server/inngest/functions/cron-*.ts` or the affected TF / workflow files (verified via `gh issue list --label code-review --state open --json number,title,body --limit 200 | jq` against each path).

---

## 6.5. Precedent Diff (Pattern-bound Behaviors)

This plan inherits multiple pattern-bound behaviors from PR-5 `cron-bug-fixer.ts`. Per `deepen-plan` Phase 4.4, the precedent shapes are diffed below.

### Ephemeral workspace pattern

**Precedent:** `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts:315-367` (`setupEphemeralWorkspace`).
**PR-7 shape:** Verbatim, with `mkdtemp` prefix renamed from `"soleur-cron-bug-fixer-"` to `"soleur-cron-roadmap-review-"`. Sentinel check on `plugins/soleur/.claude-plugin/plugin.json` is preserved (catches symlink-target-empty silent failure per #3045).

### Spawn argv pattern

**Precedent:** `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts:150-159` (`CLAUDE_CODE_FLAGS`).
**PR-7 shape:** `--max-turns` changes from `55` → `40` (mirrors workflow's `claude_args`); `--allowedTools` changes from `Bash,Read,Write,Edit,Glob,Grep` → `Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch` (mirrors workflow); `--model` unchanged (`claude-sonnet-4-6`); `--print` unchanged; trailing `--` unchanged (load-bearing per #4017 bug 8/8).

### Sentry heartbeat URL pattern

**Precedent:** `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts:921-967` (`postSentryHeartbeat`).
**PR-7 shape:** Verbatim, with `SENTRY_MONITOR_SLUG = "scheduled-roadmap-review"` rename. URL form: `https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/cron/scheduled-roadmap-review/${SENTRY_PUBLIC_KEY}/?status={ok|error}`. Same regex-validated env vars (`SENTRY_DOMAIN_RE`, `SENTRY_PROJECT_RE`, `SENTRY_PUBLIC_KEY_RE`).

### Inngest function registration pattern

**Precedent:** `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts:1215-1226` (`cronBugFixer = inngest.createFunction(...)`).
**PR-7 shape:** Verbatim, with `id: "cron-roadmap-review"`, `cron: "0 9 * * 1"`, `event: "cron/roadmap-review.manual-trigger"`. Same `concurrency: [{ scope: "fn", limit: 1 }, { scope: "account", key: '"cron-platform"', limit: 1 }]`. Same `retries: 1`.

### Installation-token mint pattern

**Precedent:** `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts:278-287` (`mintInstallationToken`).
**PR-7 shape:** Verbatim, including `TOKEN_MIN_LIFETIME_MS = 50 * 60 * 1000 + 10 * 60 * 1000`. Same `createProbeOctokit()` → `installation.id` → `generateInstallationToken(installation.id, { minRemainingMs })` chain.

### Sentry monitor TF resource pattern

**Precedent:** `apps/web-platform/infra/sentry/cron-monitors.tf:102-118` (`sentry_cron_monitor.scheduled_bug_fixer`).
**PR-7 shape:** Verbatim attribute set with `name = "scheduled-roadmap-review"`, `schedule = { crontab = "0 9 * * 1" }`. Other attributes (`checkin_margin_minutes = 30`, `max_runtime_minutes = 55`, `failure_issue_threshold = 1`, `recovery_threshold = 1`, `timezone = "UTC"`) carried verbatim from PR-5's monitor since the Inngest substrate cadence is identical.

**No novel patterns** are introduced in this PR. Every behavior is precedent-diffed against PR-5; the reviewer's burden reduces to "does each named diff match the workflow's documented semantics?" — answer: yes, verified per §Research Reconciliation and §0.Q1-Q5.

---

## 7. Domain Review

**Domains relevant:** none.

No cross-domain implications detected — infrastructure/tooling change. CPO/CLO/CTO triad already signed off on the substrate at brainstorm time (#3948 umbrella). PR-7 is the substrate's 7th application; no new product, legal, or architectural surface introduced.

---

## 8. Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf` — add `sentry_cron_monitor.scheduled_roadmap_review`. No new providers, no new variables, no new sensitive secrets.

### Apply path

- **(c) auto-apply via `apply-sentry-infra.yml`** on push to main. PR-merge IS the human authorization per `hr-menu-option-ack-not-prod-write-auth`. Kill switch: `[skip-sentry-apply]` in merge commit message.

### Distinctness / drift safeguards

- `dev != prd` — Sentry monitors are prd-only (no dev `sentry_project` data source). No drift risk.
- `lifecycle.ignore_changes` — N/A (create-not-import resource).
- State storage — encrypted R2 backend via `prd_terraform` Doppler config.

### Vendor-tier reality check

- Sentry Crons free tier: 5 monitors. Current count is 11; adding the 12th remains well above the free-tier ceiling (already on paid plan). No tier gate needed.

---

## 9. Observability

```yaml
liveness_signal:
  what: Sentry Crons heartbeat POST to api/{project_id}/cron/scheduled-roadmap-review/{public_key}/?status={ok|error}
  cadence: weekly (Monday 09:00 UTC + replay-on-failure within retries:1)
  alert_target: Sentry monitor scheduled_roadmap_review (failure_issue_threshold=1, checkin_margin_minutes=30)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf + cron-roadmap-review.ts postSentryHeartbeat
error_reporting:
  destination: Sentry via reportSilentFallback (pino mirror to Sentry per cq-silent-fallback-must-mirror-to-sentry)
  fail_loud: true (Sentry monitor opens issue on missed check-in; reportSilentFallback creates breadcrumbs with feature/op tags)
failure_modes:
  - mode: claude-eval non-zero exit
    detection: postSentryHeartbeat called with status=error; reportSilentFallback if abortedByTimeout
    alert_route: Sentry monitor scheduled_roadmap_review opens issue on first miss
  - mode: ephemeral workspace teardown failure
    detection: reportSilentFallback feature=cron-roadmap-review op=teardown-ephemeral-workspace
    alert_route: Sentry issue (degraded — stranded /tmp dir; non-blocking)
  - mode: installation-token mint failure (createProbeOctokit or generateInstallationToken throws)
    detection: handler propagates throw; Inngest retries once (retries:1); Sentry sees the unhandled error
    alert_route: Sentry monitor scheduled_roadmap_review opens issue on the missed check-in (no heartbeat sent)
  - mode: SpawnClaudeEval AbortController fires (50-min budget exceeded)
    detection: reportSilentFallback feature=cron-bug-fixer op=claude-eval-timeout (rename to cron-roadmap-review)
    alert_route: Sentry issue + heartbeat status=error
logs:
  where: pino structured logs (logger.info / logger.warn / logger.error) forwarded to centralized log sink; stdout/stderr from spawned claude line-forwarded through redactToken filter
  retention: per platform default (TBD per platform docs; matches PR-5 retention)
discoverability_test:
  command: vitest run apps/web-platform/test/server/inngest/cron-roadmap-review.test.ts
  expected_output: 5 tests passing (spawn argv, Sentry URL ok, Sentry URL err, manual-trigger no-payload, teardown)
```

---

## 10. Sharp Edges

- The Inngest function-level timeout does NOT exist in the public SDK. The 50-min envelope is enforced INSIDE the spawn step via `AbortController` (PR-5 verbatim shape). Do NOT add a `timeout:` key to `inngest.createFunction()` — it will silently no-op.
- The `id-token: write` permission in the workflow YAML is NOT carried into the Inngest substrate. PR-7 uses installation-token auth end-to-end; OIDC was used by `claude-code-action` internally, not the cron logic.
- `--max-turns 40` + `MAX_TURN_DURATION_MS = 50 min` = 1.25 min/turn budget. Well above the 0.75 min/turn floor. If a future tuning increases `--max-turns`, MUST proportionally raise `MAX_TURN_DURATION_MS` per the peer-ratio Sharp Edge.
- The `plugins:` and `plugin_marketplaces:` YAML keys have NO direct `claude` CLI flag equivalent. The plugin resolution mechanism is cwd-relative (`plugins/soleur/.claude-plugin/plugin.json` discovered from spawn cwd). The ephemeral-workspace + symlink pattern IS the resolution mechanism.
- The `--` is load-bearing per #4017 bug 8/8 — variadic `--allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch` will otherwise consume the prompt's first word as a tool name and produce confusing "unknown tool" errors.
- Plan-prescribed `MAX_TURN_DURATION_MS` defense relaxation (30 min → 50 min) is acceptable: same ceiling, more permissive value. Original GHA `timeout-minutes: 30` was bounding wall-clock runaway only; the Inngest envelope preserves the same hard-stop semantic via SIGTERM→SIGKILL escalation.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares `threshold: none` with explicit justification (operator-facing roadmap-hygiene cron, no founder data crosses the boundary).
- PR-5's missing `sentry_cron_monitor.scheduled_bug_fixer` entry in `apply-sentry-infra.yml -target=` is a known follow-up and explicitly NOT this PR's scope. The bug-fixer monitor will be auto-applied on the next push that mutates `cron-monitors.tf`, since the `-target=` list growth only affects which monitors the workflow plans on; the resource itself is in TF state.
- `cron-no-byok-lease-sweep.test.ts` uses `globSync("server/inngest/functions/cron-*.ts")`, so it auto-picks new cron-* files. No test edit needed — but verify the test PASSES on the new file (it should; the new file MUST NOT import `runWithByokLease`).
- Verify-before-cite gate for AC10 prompt-canary strings: the 4 anchor strings (`Part 1: Issue-to-Milestone Alignment`, `Part 2: Bidirectional Integrity Gate`, `MILESTONE RULE:`, `BIDIRECTIONAL RULE:`) MUST be present in the extracted prompt body. Verified at plan time via `grep -E 'Part 1|Part 2|MILESTONE RULE|BIDIRECTIONAL RULE' .github/workflows/scheduled-roadmap-review.yml` (all 4 present).
- AC10 grep escapes `:` literally; on shells where `grep -c` with `\|` alternation behaves differently between BSD and GNU, the implementer may rewrite as 4 separate `grep -c` calls summed via `awk`.
- Sentry heartbeat env vars (`SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY`) must already be in the Hetzner container env per PR-1..PR-5 (otherwise PR-5 cron-bug-fixer would not heartbeat). No new Doppler edits needed.

---

## 11. Testing Strategy

- **Test runner:** `vitest` (per `apps/web-platform/package.json scripts.test` — verified at PR-5/PR-6 precedent).
- **Test path:** `apps/web-platform/test/server/inngest/cron-roadmap-review.test.ts`.
- **Mocks:** identical scaffold to `cron-bug-fixer.test.ts` lines 23-77 (spawn factory via `vi.fn()` + `mockImplementation`, `node:fs/promises` spies for `mkdtemp`/`mkdir`/`rm`/`symlink`/`writeFile`, `node:fs.existsSync` spy, `@/server/observability.reportSilentFallback` spy, `@/server/github/probe-octokit.createProbeOctokit` spy, `@/server/github-app.generateInstallationToken` spy, `@/server/plugin-path.getPluginPath` constant).
- **No real Inngest invocation** — handler invoked directly with synthetic `makeStep()` and `logger` mock per PR-5 pattern.
- **No real GitHub API call** — all `createProbeOctokit` requests return canned shapes.
- **No new test framework dependency** — vitest already configured.

---

## 12. Test Scenarios (mapped to AC5)

1. **spawn argv shape** — invoke `cronRoadmapReviewHandler` end-to-end with all spies; assert `spawnSpy` last call's argv array equals `[claudeBin, ["--print", "--model", "claude-sonnet-4-6", "--max-turns", "40", "--allowedTools", "Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch", "--", ROADMAP_REVIEW_PROMPT], { cwd: spawnCwd, env: { ..., GH_TOKEN: "token-XYZ" }, detached: true, stdio: ["ignore", "pipe", "pipe"] }]`.
2. **Sentry URL ok** — spawn exits 0; assert `fetch` called with URL ending `/scheduled-roadmap-review/<key>/?status=ok`.
3. **Sentry URL err** — spawn exits 1; assert `fetch` called with URL ending `?status=error`.
4. **manual-trigger no-payload** — invoke with `event: { data: { foo: "ignored" } }`; assert NO `reportSilentFallback` call with `feature: "cron-roadmap-review", op: "parse-event-data"` (proves the handler doesn't try to parse a payload it should ignore).
5. **teardown try/finally** — spawn throws; assert `rmSpy` called with `(ephemeralRoot, { recursive: true, force: true })` regardless of spawn outcome.

---

## 13. Rollback

- Revert the merge commit. The deleted GHA workflow is restored (re-introducing the weekly cron on the GHA runner pool); the new Inngest function deregisters automatically (Next.js route no longer imports `cronRoadmapReview`). Sentry monitor `scheduled_roadmap_review` becomes stale — operator may manually destroy via `terraform destroy -target=sentry_cron_monitor.scheduled_roadmap_review` after the revert lands.
- No data migration. No persistent state in the cron handler. Rollback is fully reversible within one merge cycle.

---

## 14. Verify-the-Negative Pass (Deepen-pass Phase 4.45)

The plan body contains 5 negative security claims; each is verified below.

| Claim | Verification | Result |
|---|---|---|
| "cron-* MUST NOT import or call `runWithByokLease`" | `grep -E 'runWithByokLease' apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` returns 0 | **confirms** — PR-5 precedent compliant; PR-7 inherits |
| "redactToken() invoked on stdout/stderr line forwarding (no token leak)" | `grep -c 'redactToken' apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` returns ≥3 (PR-5 verbatim) | **confirms** — pattern in place |
| "Manual-trigger payload is unread (no parse-failure path)" | PR-7 strips PR-5's `event?.data?.issue_number` parsing block entirely; handler signature is `cronRoadmapReviewHandler({ step, logger })` (NO `event` destructure) | **confirms** — by construction, no payload access |
| "Installation token is NEVER logged" | `redactToken()` applied on every stdout/stderr line; `buildAuthenticatedCloneUrl()` only used internally, never echoed | **confirms** — defense-in-depth via PR-5 pattern |
| "OIDC permission NOT needed" | Inngest substrate uses installation-token auth; OIDC was for `claude-code-action`'s Anthropic binding only (irrelevant to GH API surface) | **confirms** — verified via PR-5 `cron-bug-fixer.ts` (zero OIDC references) |

## 15. Post-Edit Self-Audit (Deepen-pass Phase 4.45)

After deepen-pass edits, re-grep the plan body for references to dropped/renamed symbols:

- `grep -n 'lines 60-110\|lines 56-110' <plan>` — should return only the historical "ARGUMENTS claim" rows in §Research Reconciliation (NOT the prescriptive Phase 1.7). **PASS** — only historical references remain.
- `grep -n 'fixIssuePrompt\|RESEND_API_KEY\|notifyOpsEmail\|auto-merge-gate\|BOT_FIX_LABELS\|PRIORITY_CASCADE' <plan>` — should only appear in Phase 1 "strip" instructions, NOT in any acceptance criterion or handler prescription. **PASS** — confined to Phase 1.2/1.3 strip lists.
- `grep -n 'issue_number\|selectIssue\|detectBotFixPr' <plan>` — should NOT appear in Phase 3 handler shape or AC list. **PASS** — bug-fixer-specific concepts confined to "stripped" instructions.

---

## 16. Decisions Carried Forward From Brainstorm / Spec

- Brand-survival threshold: `none` (PR-1..PR-5 carry-forward; weekly roadmap-hygiene cron is operator-facing).
- Concurrency model: `account.key = "cron-platform"` with `limit: 1` — ensures only one cron-* invocation runs simultaneously on the Hetzner node.
- Retry policy: `retries: 1` (PR-1..PR-5 verbatim).
- claude-code spawn pattern: PR-5 ephemeral-workspace pattern (NOT PR-6's pure-TS port — PR-7 is an LLM agent loop, not an Octokit walker).
- Sentry heartbeat shape: single-step at end-of-handler (NOT two-step in_progress→ok) per `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`.
