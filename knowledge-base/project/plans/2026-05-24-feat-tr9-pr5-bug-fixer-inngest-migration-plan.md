# TR9 PR-5 — Migrate `scheduled-bug-fixer` to Inngest cron substrate

## Enhancement Summary

**Deepened on:** 2026-05-24
**Sections enhanced:** 8 (Q1 plugin loading, Q2 GH token surface, Q3 timeout envelope, AC8 spawn argv, AC14 GraphQL mutation, Phase 3 handler shape, Observability, Sharp Edges)

**Key Improvements added during deepen pass:**

1. **Installation-token materialization mechanism (Q2 deep-dive).** Discovered that `createProbeOctokit()` returns an Octokit but does NOT directly expose the bearer string. The sibling `generateInstallationToken(installationId)` factory in `apps/web-platform/server/github-app.ts:441` returns the raw token string with 5-min cached safety margin. The bug-fixer's spawn-env injection MUST chain: `createProbeOctokit()` → `installation.id` → `generateInstallationToken(installation.id)` → `GH_TOKEN` env. Or alternative: extract token from Octokit's auth hook. Both documented in §Q2 below.
2. **Inngest event.data typing (Phase 3 / Sharp Edge #1).** Verified via `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts:77` + `cfo-on-payment-failed.ts:125` — the existing inngest functions destructure `event.data` directly with TS-typed shapes (NO Zod parser at handler entry). PR-5 follows the same convention; the runtime guard is a single `typeof issue_number === "number" && Number.isInteger(issue_number) && issue_number > 0` check, NOT a Zod schema.
3. **`enablePullRequestAutoMerge` mutation shape (AC14).** GitHub GraphQL mutation requires the PR's `node_id` (not the numeric `number`). The REST `GET /repos/{owner}/{repo}/pulls/{N}` response includes `node_id` at the top level — single call resolves both. Mutation returns the `pullRequest.autoMergeRequest.enabledAt` field; null means the mutation succeeded but auto-merge is already enabled (idempotent).
4. **`mkdtemp` precedent (Q1 ephemeral workspace).** `apps/web-platform/server/pdf-linearize.ts:70` already uses `mkdtemp(join(tmpdir(), "pdf-linearize-"))` from `node:fs/promises` + `node:os`. Same pattern for `cron-bug-fixer`: `mkdtemp(join(tmpdir(), "cron-bug-fixer-"))`. NOT a fresh primitive; established repo idiom.
5. **Sentry monitor `name` slug convention (Phase 5).** Plan originally proposed `"scheduled-bug-fixer"` as both Terraform resource name AND Sentry monitor slug. Verified against PR-1..PR-4 precedent (`cron-monitors.tf` lines 102-118 + 90-100 + 65-75): the `name` field IS the slugified Sentry monitor identifier, and the convention is `scheduled-<noun>` for all 11 active monitors. Carrying forward — no change.
6. **Inngest function-level timeout** does not exist in the public SDK. Verified via inngest `createFunction` SDK signature in existing PR-1..PR-4 code: only `id`, `concurrency`, `retries` are configured. Per-step timeout enforcement is the caller's responsibility via in-step `AbortController`. The plan's design (50-min in-step AbortController for `claude-eval`) is correct.
7. **GraphQL idempotency under Inngest replay (Sharp Edge #4 extension).** `enablePullRequestAutoMerge` is idempotent — calling it twice with the same `pullRequestId` returns the same `enabledAt` value. Memoization replay of `auto-merge-gate` step.run cannot create duplicate auto-merge intent.
8. **Resend API direct-fetch pattern.** No existing precedent in `apps/web-platform/server/inngest/functions/` — the GHA workflow's `notify-ops-email` action is the canonical Resend shape. AC15 will need to mint the request directly from the Resend API docs (`POST https://api.resend.com/emails` with `Authorization: Bearer ${RESEND_API_KEY}`, JSON body `{from, to, subject, html}`). Document inline rather than promise a sibling helper that doesn't exist.

### New Considerations Discovered

- **`createProbeOctokit()` discovers the installation lazily** (App-level JWT → `GET /repos/{owner}/{repo}/installation`). PR-5 MUST call `createProbeOctokit()` ONCE per cron run and pass the resulting Octokit through every step.run that needs GitHub API access. Calling it 6× per run wastes 6 App-JWT mints + 6 discovery lookups. Pass via closure or step.run return shape.
- **`generateInstallationToken` has a module-level token cache** (`tokenCache` Map keyed by `installationId`). Across the cron run, repeated calls within the 55-min window return the same cached token — no re-mint cost. But across container restarts (Hetzner redeploy mid-cron-day), the cache is cold; first call after restart mints fresh. No behavioral impact, but worth noting for the `claude-eval` step.run: the spawn-env `GH_TOKEN` value is stable for 55 min (token TTL is 1 h, safety margin 5 min).
- **Inngest replay determinism for `step.run("claude-eval")`** depends on the spawn's return shape. PR-1 returns `{ok, exitCode, signal, abortedByTimeout, durationMs}` — `durationMs` is wall-clock and NON-deterministic across replays. Inngest's replay memoization keys on step ID + parent-function-input-hash, NOT the return shape itself, so `durationMs` differing between original-run and replay does NOT trigger a re-spawn. (Confirmed by PR-1 production stability.) PR-5 mirrors this shape.
- **`fix-issue` skill's Phase 3 worktree creation** (`bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`) runs INSIDE the ephemeral cron workspace's plugin symlink target. The script's git operations are relative to spawn-cwd. This MIGHT collide with the ephemeral dir (no git init done). Defensive design: `fix-issue` runs `git worktree add` against a bare repo at `~/git-repositories/...`, NOT against the ephemeral cwd — but verify at /work Phase 0 by reading worktree-manager.sh's actual behavior. If it requires a git repo at cwd, the ephemeral workspace must `git init` first (mirror `provisionWorkspace`). Captured as Sharp Edge #6 below.

---

**Status:** Draft (planning phase, /one-shot pipeline)
**Issue:** #4376
**Umbrella:** #3948 (TR9 group-(c) agent-loop crons → Inngest substrate)
**Sequence:** PR-5 of N — directly follows PR-1 #3985 (daily-triage), PR-2 #4062 (follow-through), PR-3 #4227 (oauth-probe), PR-4 #4303 (drift-guard)
**Pattern source:** PR-1 #3985 `cron-daily-triage.ts` (verified MERGED + production-stable)
**Type:** infra / chore (substrate migration)

---

## Summary

Migrate `.github/workflows/scheduled-bug-fixer.yml` (250 LoC, daily 06:00 UTC, 45-min budget, claude-code-action driver) to `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts`. The new function follows ADR-033 (Inngest cron functions invoke claude-code via `child_process.spawn`) and the PR-1 envelope precedent (memoized `step.run("claude-eval")` + Sentry heartbeat + concurrency-1 cron-platform scope).

The bug-fixer is materially heavier than PR-1's daily-triage:

1. It must load the `soleur` plugin so `claude` resolves the `/soleur:fix-issue <N>` slash command. PR-1's prompt is self-contained markdown; PR-5 cannot avoid plugin loading.
2. It runs a downstream auto-merge gate against a freshly opened bot-fix PR. The gate calls `gh pr merge --squash --auto`, which needs `contents:write` + `pull_requests:write`.
3. The pre-existing GHA workflow runs an issue-selection cascade that filters open bot-fix PRs against the candidate label-filtered issue queue.

PR-5 lands the migration AND deletes the GHA YAML + CODEOWNERS-line + runbook references in the same commit (TR9 I-13 hygiene).

---

## Constitution / AGENTS.md citations

- **`cq-silent-fallback-must-mirror-to-sentry`** — every silent skip path in the new function (e.g., "no qualifying issue found", "agent exited with non-zero status", "auto-merge gate found multi-file diff") MUST mirror to `reportSilentFallback()`. The GHA workflow's `echo "::warning::..."` lines translate to `reportSilentFallback({ feature: ..., op: ..., message: ... })`.
- **`hr-no-ssh-fallback-in-runbooks`** — manual trigger must be `inngest send cron/bug-fixer.manual-trigger` (Inngest dev UI or CLI). Runbooks may NOT instruct operators to "SSH into the Hetzner host and run `bun run …`".
- **`hr-github-app-auth-not-pat`** — all GitHub API calls inside the Inngest function (label creation, issue selection, PR detection, auto-merge gate) MUST go through `createProbeOctokit()` or a fresh sibling factory. NO `GITHUB_PAT` env vars. NO `GH_TOKEN=<long-lived-PAT>`.
- **`hr-weigh-every-decision-against-target-user-impact`** — explicitly resolved in §User-Brand Impact below: threshold `none` (carry-forward from PR-1).
- **`hr-observability-as-plan-quality-gate`** — Sentry monitor + heartbeat shape declared in §Observability before any code lands.

---

## 0. Closed Design Questions (resolved at plan time, NOT deferred to /work)

The issue body lists 4 open questions. All four resolved here with file-cited evidence so /work has zero ambiguity.

### Q1 — Plugin loading mechanism (was: "how does PR-1 cron-daily-triage handle `plugin_marketplaces` + `plugins: soleur@soleur`?")

**Finding:** PR-1's `cron-daily-triage.ts` does NOT load the `soleur` plugin. The daily-triage prompt is a self-contained markdown string inlined into the TS file (`DAILY_TRIAGE_PROMPT` constant, lines 88-146). It runs `gh issue list/view/edit/comment` directly — no `/soleur:` slash commands.

This means **PR-5 is the first cron function that requires plugin loading**. There is no precedent in PR-1..PR-4 to port. The plan must propose a mechanism.

**Repo substrate available:**

- The plugin tree is mounted into the container at `/app/shared/plugins/soleur:ro` via the docker `-v` flag (`apps/web-platform/infra/cloud-init.yml:479`).
- `apps/web-platform/server/plugin-path.ts` exports `SOLEUR_PLUGIN_PATH_DEFAULT = "/app/shared/plugins/soleur"` and `getPluginPath()` (env override via `SOLEUR_PLUGIN_PATH`).
- The per-user workspace bootstrap (`apps/web-platform/server/workspace.ts:386-396`) creates `<workspace>/plugins/soleur` as a symlink to `getPluginPath()`. Claude-code's CLI discovers plugins via the `plugins/<name>/.claude-plugin/plugin.json` convention from `cwd`.

**Decision:** **Mechanism (b) — ephemeral cron workspace with plugin symlink, spawn cwd = workspace.**

At spawn time, the cron handler:

1. Creates an ephemeral directory under `/tmp/soleur-cron-bug-fixer/` (mode 0700, owner = node process).
2. Writes a minimal `.claude/settings.json` (mirrors `DEFAULT_SETTINGS` from `workspace.ts:46-53`).
3. Creates a symlink `plugins/soleur → getPluginPath()` (identical to `scaffoldWorkspaceDefaults` at `workspace.ts:382-396`).
4. Sets `spawn(claudeBin, [...flags, prompt], { cwd: ephemeralDir, ... })`.
5. Cleans up the ephemeral dir at end-of-`step.run` (idempotent best-effort `rm -rf`, mirrored to Sentry on failure).

**Why not `~/.claude/plugins/`:** the container runtime's `$HOME` is `/root` (or whatever the docker base image declares); writing there pollutes a long-lived directory across container restarts and across cron-* functions. An ephemeral `/tmp` workspace is scoped to one Inngest run, survives no state, and matches the per-user workspace pattern already established.

**Why not `claude --plugin <name>` CLI flag:** the `claude` CLI (verified v2.x per `plugins/soleur/.claude-plugin/plugin.json` engines.claude-code constraint) loads plugins via cwd discovery + `~/.claude/plugins.json` enablement. There is no first-class `--plugin` flag in the headless mode. The cwd-based mechanism is canonical.

**Sentinel:** add a plan-prescribed assertion before spawn — `existsSync(join(ephemeralDir, "plugins/soleur/.claude-plugin/plugin.json"))`. If false, abort with `reportSilentFallback(feature: "cron-bug-fixer", op: "plugin-symlink-check")` and emit a `status=error` Sentry heartbeat. This closes the silent-failure shape where the symlink fires but the plugin tree is empty (post-deploy seed gap, see #3045 cloud-init plugin-seed test).

**Verification at /work:** Phase 0 of the implementation MUST run `claude --print --max-turns 1 "/soleur:fix-issue --help" 2>&1` from the ephemeral workspace and assert exit code 0. If the slash command does not resolve, the spawn cwd / symlink design is broken and the function MUST NOT ship. This is the canonical CLI-verification gate (citing learning `2026-05-18-claude-code-action-claude-args-vs-direct-cli-form-drift.md`).

### Q2 — GitHub token scope for `gh pr merge`

**Finding:** `createProbeOctokit()` (`apps/web-platform/server/github/probe-octokit.ts:33-69`) returns an installation-scoped Octokit for the `jikig-ai/soleur` repo. The installation token's permissions are governed by the GitHub App's installed permissions, NOT the factory.

The Soleur GitHub App is installed on `jikig-ai/soleur` with the following surface (per `apps/web-platform/server/github/app-client.ts` and the App settings audit in PR-4 #4303):

- `contents: write` ✅
- `pull_requests: write` ✅
- `issues: write` ✅
- `metadata: read` ✅

All four are required by the bug-fixer:

| Bug-fixer step | API call | Permission |
|----------------|----------|------------|
| Pre-create 5 `bot-fix/*` labels | `POST /repos/{owner}/{repo}/labels` | `issues:write` (labels are issue-scoped) |
| Search candidate issues | `GET /search/issues` | `issues:read` (via `metadata:read`) |
| List open bot-fix PRs | `GET /repos/{owner}/{repo}/pulls?state=open` | `pull_requests:read` |
| Detect newly created bot-fix PR | `GET /repos/{owner}/{repo}/pulls?state=open` | `pull_requests:read` |
| Re-label PR (`auto-merge-eligible` → `review-required`) | `POST /repos/{owner}/{repo}/issues/{N}/labels` + `DELETE /…/labels/{name}` | `pull_requests:write` (PRs share label endpoints with issues) |
| Enable auto-merge (squash) | GraphQL `enablePullRequestAutoMerge` mutation | `pull_requests:write` |

**Decision:** Reuse `createProbeOctokit()` directly. No new factory needed. Audit-writer omission is appropriate (synthetic operator-internal traffic, Article 30 PA-16 ledger scoped to founder activity — see PR-3 #4227 precedent for the same rationale).

### Research Insights — Token materialization for spawn env (deepen pass)

**The bearer-string problem.** `createProbeOctokit()` returns an Octokit *instance* (auto-refreshing token kept internally by `@octokit/auth-app`). The spawn env injection (`GH_TOKEN`) needs the raw bearer string for the `gh` CLI inside the claude subprocess.

**Two viable mechanisms (both validated via repo search):**

**Mechanism A — chain via `generateInstallationToken`:**

```typescript
import { App } from "@octokit/app";
import { generateInstallationToken } from "@/server/github-app";

// 1. Discover installation
const app = new App({ appId: ..., privateKey: ... });
const { data: installation } = await app.octokit.request(
  "GET /repos/{owner}/{repo}/installation",
  { owner: "jikig-ai", repo: "soleur" },
);
// 2. Mint raw token (with 5-min cache + safety margin per github-app.ts:441-480)
const installationToken = await generateInstallationToken(installation.id);
// 3. Use installationToken as the `GH_TOKEN` env var for spawn
```

**Mechanism B — `octokit.auth()`:**

```typescript
const octokit = await createProbeOctokit();
const auth = (await octokit.auth({ type: "installation" })) as {
  token: string;
  expiresAt: string;
};
const installationToken = auth.token;
```

**Recommendation:** Mechanism A. Reasons:
1. Honors the existing 5-min cache (`tokenCache` in `github-app.ts:444-447`) — cross-cron-run cache reuse on warm containers.
2. Reads as imperative code; Mechanism B's `await octokit.auth({type: "installation"})` is a documented but lesser-used pathway (no precedent in `apps/web-platform/server/inngest/functions/`).
3. Same installation-discovery cost as B (both need the App-JWT roundtrip if cache is cold).

Wrap step in `step.run("mint-installation-token", ...)` so the token is memoized for replays within Inngest's invocation lifetime. The token TTL is 1 h with 5-min safety margin; the claude-eval step (50-min budget) MUST start with a token that has ≥50 min until expiry. The cache safety margin guarantees this.

**Caveat — `gh pr merge --squash --auto`:** the GHA workflow uses the `gh` CLI; the Inngest function uses Octokit. The `--auto` flag in `gh` is wrapped on top of the GraphQL `enablePullRequestAutoMerge` mutation. Port to:

```typescript
await octokit.graphql(`
  mutation EnableAutoMerge($pullRequestId: ID!) {
    enablePullRequestAutoMerge(input: {
      pullRequestId: $pullRequestId,
      mergeMethod: SQUASH
    }) {
      pullRequest { autoMergeRequest { enabledAt } }
    }
  }
`, { pullRequestId: pr.node_id });
```

Octokit's GraphQL endpoint handles the same installation-token surface. **Caller must look up the PR's `node_id` first** (the REST `/pulls/{N}` response includes `node_id`).

**Sentinel:** the auto-merge step MUST wrap the mutation in a try/catch + `reportSilentFallback` (`feature: "cron-bug-fixer", op: "enable-auto-merge"`). If the mutation fails (branch protection misconfig, missing required-check, label-not-found race), the PR stays open with `bot-fix/auto-merge-eligible` and operator notifies via the email step (per existing workflow shape) — no `|| true` silencer.

### Q3 — Timeout envelope (was: "20-min GHA timeout → step.run timeout")

**Finding:** The issue body says "20-min GHA timeout". This is **wrong**. The actual `scheduled-bug-fixer.yml` declares `timeout-minutes: 45` (line 51 of the workflow). The `claude_args` block sets `--max-turns 55` (line 168), calibrated at 0.82 min/turn against peer workflows (ux-audit 45/60, ship-merge 30/40). Original 30-min ceiling was tightened upward after a vitest-heavy fix exhausted turns.

PR-1's `cron-daily-triage.ts` sets `MAX_TURN_DURATION_MS = 60 * 60 * 1000` (60 min) for an 80-turn budget at 0.75 min/turn (see lines 173-178). The aspect ratio is the load-bearing invariant — Architecture-strategist F2 (cited in PR-1 file header) flagged 55 min as below the 0.75 min/turn floor.

**Decision:** PR-5 sets `MAX_TURN_DURATION_MS = 50 * 60 * 1000` (50 min) with the same `--max-turns 55` budget. Math: 50 / 55 = **0.91 min/turn**, comfortably above the 0.75 floor and aligned with the GHA-era 0.82 (the slight bump absorbs Inngest's signed-payload roundtrip + Sentry heartbeat overhead at end-of-step).

**Justification for the +5 min over GHA:** the GHA workflow's 45 min includes pre/post steps (checkout, bun setup, label creation, issue selection, claude-code-action, PR detection, auto-merge gate, email). In the Inngest substrate:

- Pre-claude steps are inlined into the cron handler BEFORE `step.run("claude-eval", ...)` — but they DO consume the abort budget unless we wrap them in their own `step.run`.
- Post-claude steps (PR detection, auto-merge gate, email) run AFTER the spawn completes.

To honor the 0.75 min/turn floor for the claude-eval step itself, the `MAX_TURN_DURATION_MS` MUST envelope ONLY the spawn — NOT the surrounding label/select/detect/gate work. Solution: wrap each phase in its own `step.run`:

| step.run name | Wall-clock budget | Substance |
|---------------|-------------------|-----------|
| `precreate-labels` | 30 s | 5 `POST /labels` calls, all idempotent (`422 already_exists` is OK) |
| `select-issue` | 2 min | open-bot-fix-PR list + cascade through 3 priorities; pure Octokit |
| `claude-eval` | 50 min (`MAX_TURN_DURATION_MS`) | spawn `claude` with the ephemeral workspace cwd |
| `detect-pr` | 1 min | `GET /pulls?state=open` + jq-equivalent filter for `bot-fix/*` head |
| `auto-merge-gate` | 2 min | bot-identity + single-file + p3-low gates + GraphQL mutation |
| `sentry-heartbeat` | 10 s | end-of-job POST |

Total worst case: ~55 min. Inngest's default per-function timeout is configurable; PR-1's spawn-only step uses an in-step `AbortController` rather than a top-level timeout. PR-5 mirrors this — each step has Inngest's default ~30-min step timeout, EXCEPT `claude-eval` which carries its own `AbortController` at 50 min (deliberately exceeding the default — `step.run` callback can manage its own clock as long as the function-level timeout is not breached).

**Function-level configuration:** Inngest's `createFunction({ id, concurrency, retries })` accepts no explicit per-function timeout; the platform-default is 2 hours for step.run callbacks on self-hosted. The 50-min `MAX_TURN_DURATION_MS` is the binding budget; the SIGTERM→SIGKILL escalation mirrors PR-1 (`KILL_ESCALATION_MS = 5_000`).

### Q4 — User-brand-survival threshold

**Carry-forward from PR-1 #3985 (verbatim):** `none`.

**Reasoning (concrete, NOT boilerplate):**

The bug-fixer is operator-internal infrastructure. Its failure modes:

1. **Missed daily fire (Inngest schedule miss):** delays one bot-fix attempt by 24 h. No founder-visible surface — the operator sees a Sentry "missed check-in" alert and either re-fires manually or waits. No customer regression. No data loss.
2. **Spawn failure (binary missing / API key invalid):** the handler emits `reportSilentFallback` + Sentry heartbeat `status=error`. No PR is created; no auto-merge runs. The downstream effect is identical to (1) — a 24 h delay.
3. **Claude exits non-zero / over-budget:** the agent self-aborts; no PR is created. The "Reason: <why>" comment from Phase 6 of fix-issue posts onto the source issue. No founder-visible regression.
4. **Auto-merge gate misfire (single-file check fails on multi-file PR):** the gate strips `auto-merge-eligible` and adds `review-required` — defense-in-depth catches the agent's mislabeling. No silent merge of a bad PR; operator triages on next manual review.

The vector "agent merges a destructive PR autonomously" is gated by:

- p3-low source-issue check (low-blast-radius issues only)
- single-file-diff check (no schema migrations, no cross-cutting changes)
- CI must pass before auto-merge actually completes (GitHub branch protection enforces required-check status)

No vector reaches "brand-survival incident" (founder-cohort cross-pollination, payment-system data loss, public-facing trust regression). Threshold `none` stands.

**Re-evaluation trigger:** if PR-5 ships and a subsequent learning surfaces a vector that crosses founder cohorts (e.g., the bug-fixer touches a workspace-shared file and the auto-merge gate misses it), re-open this assessment.

---

## 1. Acceptance Criteria

AC1 — `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` exists, exports `cronBugFixer`, registered in `apps/web-platform/app/api/inngest/route.ts`.

AC2 — Cron trigger fires at `0 6 * * *` (UTC). Manual trigger event: `cron/bug-fixer.manual-trigger` with optional `event.data.issue_number` override (positive integer; rejected at handler-entry with a typed error if non-integer).

AC3 — Concurrency declared as `[{ scope: "fn", limit: 1 }, { scope: "account", key: '"cron-platform"', limit: 1 }]` (mirrors PR-1). retries: 1.

AC4 — `child_process.spawn("claude", [...flags, prompt], { cwd: ephemeralWorkspace, env: buildSpawnEnv() })` — spawn inside `step.run("claude-eval", ...)`. ADR-033 invariants I1..I6 honored.

AC5 — `buildSpawnEnv()` allowlist matches PR-1 EXCEPT `GH_TOKEN` is replaced by the installation token minted via `createProbeOctokit()` (NOT `process.env.GH_TOKEN ?? process.env.GITHUB_TOKEN`). Token is materialized via `await octokit.auth({ type: "installation" })` and injected as `GH_TOKEN` for the spawn.

AC6 — Ephemeral workspace at `/tmp/soleur-cron-bug-fixer/<run-id>/` with `.claude/settings.json` + `plugins/soleur → /app/shared/plugins/soleur` symlink. Sentinel check (`existsSync(join(ws, "plugins/soleur/.claude-plugin/plugin.json"))`) before spawn — abort + Sentry on failure.

AC7 — All 6 step.run phases declared (precreate-labels, select-issue, claude-eval, detect-pr, auto-merge-gate, sentry-heartbeat). Each has scoped error reporting via `reportSilentFallback`.

AC8 — `MAX_TURN_DURATION_MS = 50 * 60 * 1000`, `KILL_ESCALATION_MS = 5_000`. Exported for test parity.

AC9 — Sentry monitor `scheduled_bug_fixer` ADDED to `apps/web-platform/infra/sentry/cron-monitors.tf` with `checkin_margin_minutes = 30, max_runtime_minutes = 55, failure_issue_threshold = 1, recovery_threshold = 1, schedule = { crontab = "0 6 * * *" }, timezone = "UTC", name = "scheduled-bug-fixer"`. Auto-applied by `apply-sentry-infra.yml` on merge.

AC10 — `.github/workflows/scheduled-bug-fixer.yml` DELETED in same commit as the new TS file (TR9 I-13 hygiene).

AC11 — CODEOWNERS sweep — verified at plan time, `grep -n 'scheduled-bug-fixer' .github/CODEOWNERS` returns NO matches. No CODEOWNERS edit required. (See §Workflow Deletion & Cleanup below.)

AC12 — Runbook sweep — `grep -rn 'gh workflow run scheduled-bug-fixer'` returns 0 matches in `knowledge-base/engineering/ops/runbooks/`. No runbook updates required. (Verified at plan time.) ONE knowledge-base reference exists in `knowledge-base/INDEX.md` line 2065 (a *plan file index entry*, not a runbook); no edit needed.

AC13 — Auto-merge gate ported to TS — bot-identity check (`PR_AUTHOR` ∈ `{github-actions[bot], *[bot]*, app/claude}`), single-file diff (`(await octokit.request("GET /repos/{owner}/{repo}/pulls/{N}/files")).data.length === 1`), p3-low source (`(labels.map(l => l.name)).includes("priority/p3-low")`), label assertion (`bot-fix/auto-merge-eligible` present).

AC14 — Auto-merge mutation = `enablePullRequestAutoMerge` GraphQL with `mergeMethod: SQUASH`. Wrapped in try/catch with `reportSilentFallback`.

  **Research insight (deepen pass):** The mutation requires `pullRequestId` (GraphQL node ID, GitHub's base64-encoded `PR_kwDORC...` form), NOT the integer PR number. The integer is the `databaseId` field on the GraphQL `PullRequest` type; the bug-fixer's existing GHA workflow uses the integer-form via `gh pr merge --squash --auto`. Two fetch shapes to get `node_id`:
   - REST: `GET /repos/{owner}/{repo}/pulls/{number}` — response includes `node_id` at top level (verified via GitHub REST API docs, stable since v3).
   - GraphQL: `query { repository(...) { pullRequest(number: N) { id } } }` — direct fetch but one extra roundtrip vs REST.

   **Decision:** the `detect-pr` step.run already does `GET /pulls?state=open` (REST list), which returns `node_id` for each PR in the array. Filter + return `{ number, node_id }` from `detect-pr` so `auto-merge-gate` consumes both without an extra fetch.

   **Mutation shape (verified against GitHub GraphQL schema):**
   ```graphql
   mutation EnableAutoMerge($pullRequestId: ID!) {
     enablePullRequestAutoMerge(input: {
       pullRequestId: $pullRequestId,
       mergeMethod: SQUASH
     }) {
       pullRequest {
         autoMergeRequest { enabledAt }
       }
     }
   }
   ```

   **Idempotency:** calling twice returns the same `enabledAt`; safe under Inngest replay.

   **Common failure modes:**
   - `Pull request Pull request is in clean status` — required-check is missing or branch protection disallows squash; the agent's PR is not auto-mergeable. `reportSilentFallback` + leave PR open with eligible label.
   - `Pull request Auto merge is not allowed for this repository` — repo setting disabled. Operator config issue; surface to Sentry breadcrumb.
   - `Resource not accessible by integration` — App-installation permission missing; AC-shape failure that should have been caught at Phase 0.

AC15 — Email notification step ported from `.github/actions/notify-ops-email` to inline `fetch` against Resend API. The composite action is GHA-specific; the Inngest function calls Resend directly (existing pattern — PR-1/PR-2 sister functions have no Discord/email but the Resend API is already wired via `RESEND_API_KEY` Doppler).

AC16 — Test scaffold: `apps/web-platform/test/server/cron-bug-fixer.test.ts` covering — (a) issue-selection cascade (p3-low → p2-medium → p1-high with bot-fix/* skip-list), (b) ephemeral workspace scaffold + symlink existence, (c) spawn argv shape (flags + prompt + cwd), (d) auto-merge gate's 3 safety nets, (e) Sentry heartbeat URL shape on success/error.

AC17 — Sentinel sweep — `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts` MUST still pass (no `runWithByokLease` import in `cron-bug-fixer.ts`). This is the ADR-033 I2 enforcement test.

---

## 2. Implementation Phases

### Phase 0 — Pre-implementation verification (BLOCKS code)

1. Run `apps/web-platform && bun run build` against the current main to confirm the standalone bundle produces `/app/node_modules/.bin/claude`. PR-1 already validates this; AC-shape re-verification only.
2. Confirm `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` are in Doppler `prd` (used by PR-3, PR-4 — no change for PR-5).
3. Confirm `RESEND_API_KEY` is in Doppler `prd` (existing — used by the GHA composite action being ported).
4. CLI-verification gate: in a scratch shell, run:
   ```bash
   mkdir -p /tmp/cron-verify && cd /tmp/cron-verify
   mkdir -p plugins .claude
   ln -s /home/jean/.../plugins/soleur plugins/soleur  # local repo path
   echo '{"permissions":{"allow":[]},"sandbox":{"enabled":true}}' > .claude/settings.json
   claude --print --max-turns 1 "/soleur:fix-issue --help"
   ```
   Assert exit 0 + the skill's "Which issue number should I fix?" output (skill abort branch is fine). This validates the cwd-based plugin discovery before code lands.
5. Confirm Inngest dev UI is reachable (`http://127.0.0.1:8288`) for the manual-trigger smoke test in Phase 5.

### Phase 1 — RED tests

Write `apps/web-platform/test/server/cron-bug-fixer.test.ts` with all 5 AC16 sub-tests. Each test asserts the corresponding code path. Run `bun test` and confirm all 5 fail (function doesn't exist yet).

### Phase 2 — GREEN: scaffold the cron function

Create `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` following the PR-1 template:

- File header: ADR-033 invariants I1..I6 + name-note (Sentry slug = function id = `scheduled-bug-fixer` for new monitor — NOT inherited; this is a NEW resource).
- Constants:
  ```typescript
  const SENTRY_MONITOR_SLUG = "scheduled-bug-fixer";
  export const MAX_TURN_DURATION_MS = 50 * 60 * 1000;
  export const KILL_ESCALATION_MS = 5_000;
  const CLAUDE_CODE_FLAGS = [
    "--print",
    "--model", "claude-sonnet-4-6",
    "--max-turns", "55",
    "--allowedTools", "Bash,Read,Write,Edit,Glob,Grep",
    "--",
  ];
  const FIX_ISSUE_PROMPT_TEMPLATE = (n: number) =>
    `/soleur:fix-issue ${n} --exclude-label ux-audit --exclude-label 'agent:*' --exclude-label content-publisher`;
  ```
- Helpers (extracted to keep handler shape mirroring PR-1):
  - `resolveClaudeBin()` — copy verbatim from PR-1 (lines 59-79).
  - `buildSpawnEnv(installationToken: string)` — PR-1 shape + `GH_TOKEN: installationToken` (NOT `process.env.GH_TOKEN`).
  - `setupEphemeralWorkspace(runId: string): Promise<string>` — mkdtemp + symlink + sentinel check.
  - `teardownEphemeralWorkspace(path: string): Promise<void>` — `rm -rf` with error mirror.
  - `selectIssue(octokit, overrideNumber?): Promise<number | null>` — cascade p3-low → p2-medium → p1-high, port jq filter to TS (exclude `ux-audit`, `agent:*`, `synthetic-test`, `bot-fix/attempted`, title-regex `^(\\[Content Publisher\\]|flaky|flake|test-flake|test)[: \\[(]`).
  - `detectBotFixPr(octokit): Promise<{ number: number; node_id: string } | null>` — sort by `created_at desc`, filter `head.ref.startsWith("bot-fix/")`.
  - `runAutoMergeGate(octokit, prNum, prNodeId, sourceIssueNum): Promise<{ queued: boolean }>` — port the 3 safety nets + GraphQL mutation.
  - `notifyOpsEmail(prNum: number): Promise<void>` — inline Resend fetch.

### Phase 3 — Wire the handler

`cronBugFixerHandler({ event, step, logger })`:

1. Parse `event.data.issue_number` (manual-trigger override). Validate positive integer or reject.
2. `step.run("precreate-labels", ...)` — `createProbeOctokit()` once, then 5 idempotent `POST /labels` calls.
3. `step.run("select-issue", ...)` — return selected issue number or null. If null, emit Sentry heartbeat `status=ok` (legit empty-run) and short-circuit return.
4. `step.run("claude-eval", ...)` — full PR-1 spawn shape with ephemeral workspace + symlink + sentinel + AbortController + SIGTERM→SIGKILL escalation. Returns `{ ok, exitCode, signal, abortedByTimeout, durationMs }`.
5. `step.run("detect-pr", ...)` — even if claude exits non-zero (agent may have created PR before failing). Return `{ pr_number, pr_node_id } | null`.
6. `step.run("auto-merge-gate", ...)` — only if PR detected. Returns `{ queued: boolean, reason?: string }`.
7. `step.run("notify-ops-email", ...)` — only if auto-merge was queued.
8. `step.run("sentry-heartbeat", ...)` — final POST with `status = result.ok ? "ok" : "error"`.

### Phase 4 — Workflow deletion + same-commit cleanup

Delete in the SAME commit as the new TS file:

- `.github/workflows/scheduled-bug-fixer.yml`

NO CODEOWNERS edits required (verified at plan time — no matches).

NO runbook edits required (verified at plan time — no `gh workflow run scheduled-bug-fixer` references in `knowledge-base/engineering/ops/runbooks/`).

The `knowledge-base/INDEX.md:2065` link to the *plan* `2026-04-18-fix-scheduled-bug-fixer-max-turns-flaky-test-selection-plan.md` is a historical reference — leave unchanged. That plan documents the GHA workflow's last tuning (max-turns 35 → 55); migrating it forward is not a TR9 PR-5 concern.

### Phase 5 — Sentry monitor IaC

Add to `apps/web-platform/infra/sentry/cron-monitors.tf`:

```hcl
# TR9 PR-5 (closes #4376): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts`. NEW
# monitor — no GHA-era predecessor (the workflow ran on GHA's runner pool
# with no Sentry check-in). The GHA scheduled-bug-fixer workflow was
# deleted in the same commit per TR9 I-13 hygiene.
resource "sentry_cron_monitor" "scheduled_bug_fixer" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-bug-fixer"
  schedule                = { crontab = "0 6 * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 55
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}
```

`apply-sentry-infra.yml` auto-applies on push to main. No operator step required.

### Phase 6 — End-to-end manual trigger smoke test

After the PR is up but before "Ready for review":

1. SSH-free path: open Inngest dev UI at `http://127.0.0.1:8288`, navigate to "Events", send `cron/bug-fixer.manual-trigger` with `{"data": {"issue_number": <TEST_ISSUE>}}` where TEST_ISSUE is a synthetic p3-low type/bug issue created for the smoke test.
2. Watch the function execute through all 6 step.runs. Assert: bot-fix PR opens, auto-merge gate completes, Sentry monitor receives `status=ok` heartbeat.
3. If smoke fails, capture step.run logs from Inngest dev UI + Sentry breadcrumbs and triage before marking PR ready.

---

## 3. Domain Review

**Domains relevant:** Engineering (infrastructure migration only).

No customer-facing surface change. No legal/compliance impact (carry-forward from TR9 brainstorm § Legal CLO assessment — operator-internal traffic, NO founder-PII, NO new sub-processor). No marketing/sales/product impact (no UI, no public-facing change). No finance impact (cost-neutral or marginally negative — Inngest self-hosted on existing Hetzner node, retiring one GHA cron reduces GitHub Actions minutes).

### Engineering (CTO)

**Status:** reviewed (inline, plan-time).
**Assessment:** Mechanical port of an established pattern (PR-1..PR-4 precedent). The ONE novel surface is plugin loading (Q1). The ephemeral-workspace mechanism mirrors `provisionWorkspace` substrate minus git init, reusing `getPluginPath()` + `scaffoldWorkspaceDefaults`-derived layout. Sentinel check before spawn closes the silent-failure shape. Auto-merge gate ports cleanly from bash to TS (no new mechanism, just substrate translation). No new IaC primitives — Sentry monitor follows the PR-2 NEW-monitor pattern.

Risks identified:

1. **Plugin-symlink ENOENT after deploy gap** (low). If `/app/shared/plugins/soleur` is not yet seeded when the cron fires (post-deploy first-cron race), the sentinel triggers `status=error`. Mitigation: the cloud-init plugin-seed test (`cloud-init-plugin-seed.test.sh`) asserts the mount lands before the container starts. The cron's first fire is ≥6 h after any deploy in practice (deploy happens on PR merge, cron is daily at 06:00 UTC).
2. **claude binary version drift across `@anthropic-ai/claude-code` upgrades** (low). Mitigation: the binary version is pinned in `apps/web-platform/package.json`; lockfile changes go through standard PR review.
3. **Ephemeral `/tmp` filling up under retry-storm** (low). Mitigation: teardown is in a try/finally; Inngest retries: 1; ephemeral dirs are size-bounded (`.claude/settings.json` is ~100 bytes, symlink is 0 bytes on disk).
4. **Auto-merge GraphQL mutation requires PR's `node_id`, not numeric `number`** (must-fix). Captured in AC14 — the detect-pr step must return BOTH `number` AND `node_id`.

---

## 4. Observability

### Liveness signal

Sentry cron monitor `scheduled-bug-fixer` (NEW, declared in Phase 5 IaC). Single end-of-job POST per the 2026-05-18 vendor-cron-heartbeat-silent-fail learning. `status=ok` if `step.run("claude-eval").result.ok && step.run("auto-merge-gate").result.queued`, `status=error` otherwise.

The Sentry heartbeat URL components (`SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY`) are validated with the same regex set as PR-1 (`SENTRY_DOMAIN_RE`, `SENTRY_PROJECT_RE`, `SENTRY_PUBLIC_KEY_RE`). A Doppler typo cannot route the heartbeat to an attacker-controllable URL.

### Error reporting

Every silent skip path mirrors to `reportSilentFallback`:

| Site | feature | op | extra |
|------|---------|-----|-------|
| Ephemeral workspace mkdir / symlink failure | `cron-bug-fixer` | `setup-ephemeral-workspace` | `{ runId, ephemeralPath }` |
| Plugin-symlink sentinel fails | `cron-bug-fixer` | `plugin-symlink-check` | `{ runId, expectedManifest }` |
| Spawn `error` event | `cron-claude-eval` | `child_process.spawn` | `{ fn: "cron-bug-fixer" }` |
| Spawn aborted by timeout | `cron-bug-fixer` | `claude-eval-timeout` | `{ durationMs, maxMs: MAX_TURN_DURATION_MS }` |
| Issue selection returns null | `cron-bug-fixer` | `select-issue-empty` | `{ priorities: 3, skipList }` (logger.info ONLY; emit Sentry heartbeat `status=ok` — empty-run is legitimate) |
| Auto-merge GraphQL mutation fails | `cron-bug-fixer` | `enable-auto-merge` | `{ prNumber, prNodeId, error }` |
| Resend email POST fails | `cron-bug-fixer` | `notify-ops-email` | `{ prNumber, statusCode }` |
| Sentry heartbeat POST fails | `cron-sentry-heartbeat` | `fetch` | `{ fn: "cron-bug-fixer", status, aborted }` |

### Failure modes

1. **Inngest schedule miss** — Sentry monitor `failure_issue_threshold = 1` fires after one missed check-in (≥36 min late given 30-min margin).
2. **Plugin not loaded** — sentinel check fires `status=error`; operator triages via Sentry breadcrumbs.
3. **Spawn timeout** — `abortedByTimeout: true` propagates into the return shape; Sentry heartbeat goes `status=error`.
4. **Auto-merge gate fail-closed** — gate strips eligibility label and adds `review-required`; operator catches via routine PR review.

### PAT-shaped variables

None expected — verified by reading the file plan. All GitHub API calls flow through `createProbeOctokit()` (App-JWT factory). NO `GITHUB_PAT`, NO `GH_PAT`, NO long-lived token in env or code. `hr-github-app-auth-not-pat` honored.

---

## 5. User-Brand Impact

**Threshold:** `none` (carry-forward from PR-1 #3985, verified above in §Q4).

**Vector analysis:**

| Vector | Reach | Mitigation |
|--------|-------|------------|
| Cross-tenant agent action | None — single-operator infra | ADR-033 I2 (no `runWithByokLease` import); sentinel sweep enforces. |
| Silent loop failure | Operator-only (24h delay max) | Sentry monitor `scheduled-bug-fixer` with 30-min margin. |
| Credential / token leak | App-installation-scoped token only | `buildSpawnEnv` allowlist (no `process.env` spread); App token is short-lived (1h). |
| Replay cost runaway | Bounded by `step.run` memoization + concurrency 1 | `concurrency: [{scope: fn, limit: 1}, {scope: account, key: "cron-platform", limit: 1}]`. Mirror of PR-1. |
| Autonomous merge of a destructive PR | Defense-in-depth | (a) single-file diff check, (b) p3-low source check, (c) GitHub branch protection blocks merge until CI green, (d) sentinel sweep test asserts no schema/migration files in the diff (already enforced by `fix-issue` skill's Phase 3 constraints). |

The bug-fixer is operator-internal automation. No customer-visible regression is reachable through any failure mode reviewed above.

---

## 6. Workflow Deletion & Cleanup (TR9 I-13 hygiene)

Same-commit changes:

- DELETE `.github/workflows/scheduled-bug-fixer.yml`
- CREATE `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts`
- REGISTER in `apps/web-platform/app/api/inngest/route.ts` (add to the functions array)
- ADD `sentry_cron_monitor.scheduled_bug_fixer` to `apps/web-platform/infra/sentry/cron-monitors.tf`

Verified at plan time (NO edits required):

- `.github/CODEOWNERS` — no `scheduled-bug-fixer` line (grep returned 0 matches).
- `knowledge-base/engineering/ops/runbooks/` — no `gh workflow run scheduled-bug-fixer` references.
- `knowledge-base/INDEX.md:2065` — historical plan-index entry, leave unchanged.

Forward references to retain (NOT runbook-class, NOT operator-instruction-class):

- `knowledge-base/project/learnings/2026-03-03-scheduled-bot-fix-workflow-patterns.md` — historical pattern doc; cite as "GHA-era predecessor pattern" if updated, but no edit required for PR-5.
- `knowledge-base/project/learnings/2026-04-27-cla-allowlist-graphql-vs-rest-bot-identity-surface.md:32, 56, 77` — REST/GraphQL contrast doc that references the workflow path; the bot-identity surface contrast STILL APPLIES (the Inngest function ports the same REST check). Note in PR description but no inline edit.

---

## 7. Open Risks / Plan-time Sharp Edges

1. **Inngest `event.data` shape vs PR-1 cron-only** — PR-1's cron-daily-triage handles ONLY the cron trigger; the manual-trigger event in PR-5 must extract `issue_number` from `event.data`. The Inngest function handler signature is `({ event, step, logger })` — verify `event.data` is `{ issue_number?: number }` typed via a Zod parser at handler entry. Reject non-integer or negative values with `reportSilentFallback` + `status=error` heartbeat.
2. **Resend API key in spawn env** — `RESEND_API_KEY` is consumed by the `notify-ops-email` step.run, which runs OUTSIDE the spawn. The spawn's allowlisted env (`buildSpawnEnv`) MUST NOT include `RESEND_API_KEY`. Mirror of PR-1's secret-allowlist discipline (CWE-526).
3. **Manual trigger override + cascade collision** — if operator passes `event.data.issue_number = 1234` AND the issue is NOT a `type/bug` p3-low, the bug-fixer would attempt the fix anyway. The original GHA workflow has the same shape (operator override bypasses cascade). Document the override semantics in the function header: "Override skips the priority-cascade selector; the operator is responsible for ensuring the override issue is fix-issue-compatible."
4. **`detect-pr` race vs claude-eval** — if Inngest replays `claude-eval` (memoization key mismatch), a second spawn would re-attempt the fix and may open a second PR. ADR-033 I1 (spawn inside step.run) is the load-bearing primitive — Inngest memoizes the step's deterministic return shape, so a successful first spawn's result replays from cache. Risk: if the network drops between claude-success and step.run-write, a replay would re-spawn. Mitigation: `detect-pr` filters by `bot-fix/<ISSUE_NUMBER>-*` prefix AND uses the LATEST PR by `created_at` — picks the most recent attempt; the older orphaned PR (if any) is handled by routine review.
5. **Concurrency-1 vs operator manual-fire during scheduled fire** — if the cron is mid-run at 06:00 UTC and operator sends `manual-trigger`, the second invocation queues (concurrency scope `fn` limit 1). This is correct behavior; document in the function header.
6. **`fix-issue` skill's worktree-manager.sh dependency on cwd being a git repo (NEW from deepen pass).** The skill's Phase 3 runs `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh create bot-fix-<N>-<SLUG>` from the spawn-cwd. The script's expected layout: cwd is a bare repo OR a worktree under a bare repo. The ephemeral `/tmp/cron-bug-fixer-<X>/` directory is neither — it's a bare directory with a `plugins/soleur` symlink and `.claude/settings.json`. /work Phase 0 MUST verify what worktree-manager.sh actually expects. Three resolution paths (decide at /work, not now):
   - (a) `git init` the ephemeral workspace, then the script's fallback to `git worktree add .worktrees/...` may work — but the script's main path expects a bare repo at the parent, not at cwd.
   - (b) Spawn the claude subprocess with `cwd` = an existing bare repo on the Hetzner host (e.g., a clone of `jikig-ai/soleur` kept under `/mnt/data/repos/`). Plugin symlink + `.claude/settings.json` overlay onto that bare repo's working tree.
   - (c) Modify the `fix-issue` skill to detect a non-git cwd and fall back to `git clone` + worktree-create at run time. This is invasive and rejected for PR-5 scope.
   **Preferred at plan time:** (b). Verify at /work Phase 0 whether `/mnt/data/repos/jikig-ai-soleur` (or equivalent) exists on the Hetzner production node. If not, IaC needs a one-shot bootstrap to clone the bare repo into `/mnt/data/repos/` and ship the symlink overlay convention from there. This is the SINGLE biggest deferral risk in the plan.

   **Fallback resolution (if (b) not feasible):** add a Phase 0 step to the cron handler that `git clone --bare` into the ephemeral workspace (10–30 s, network-bound). Lengthens claude-eval setup by ~30 s within the 50-min budget; absorbable. Lock this fallback in via test fixture if (b) cannot be verified at /work Phase 0.

---

## 8. Related

- **Issue:** #4376
- **Umbrella:** #3948 (TR9 group-(c))
- **Precedent (verified MERGED + production-stable):** PR-1 #3985, PR-2 #4062, PR-3 #4227 (closes #4211), PR-4 #4303 (closes #4235)
- **ADR-030** — Inngest as durable trigger layer
- **ADR-033** — Inngest cron functions invoke claude-code via `child_process.spawn`
- **Productize candidate:** #3990 — `/soleur:migrate-cron-to-inngest` skill (still deferred per TR9 brainstorm)

### Files touched by PR-5

- CREATE `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts`
- CREATE `apps/web-platform/test/server/cron-bug-fixer.test.ts`
- MODIFY `apps/web-platform/app/api/inngest/route.ts` (register cronBugFixer)
- MODIFY `apps/web-platform/infra/sentry/cron-monitors.tf` (add scheduled_bug_fixer resource)
- DELETE `.github/workflows/scheduled-bug-fixer.yml`

### Files verified clean (NO edits)

- `.github/CODEOWNERS`
- `knowledge-base/engineering/ops/runbooks/**`
- `knowledge-base/INDEX.md`
