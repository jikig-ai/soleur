---
name: go
description: Unified entry point that classifies intent and routes to the right workflow skill
argument-hint: "[what you want to do]"
---

# Soleur Go

Unified entry point for all Soleur workflows. Classify the user's intent and route to the correct skill.

## User Input

<user_input> #$ARGUMENTS </user_input>

**If the user input above is empty**, ask: "What would you like to do? Describe what you need and I'll route you to the right workflow."

Do not proceed until there is input from the user.

## Step 0.0: Workspace Readiness Gate

Before the session-start preamble and before any routing, confirm a usable git repository exists. Run the readiness probe (it decides readiness AND, on failure, emits a `SOLEUR_GIT_REPO_DIAG` forensic line that the server-side telemetry hook mirrors to Better Stack — so a not-ready workspace is self-diagnosable without a manual probe):

```bash
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/git-repo-readiness-diag.sh 2>&1 \
  || { git rev-parse --is-bare-repository 2>/dev/null || true; git rev-parse --is-inside-work-tree 2>/dev/null || true; }
```

The `||` fallback runs the bare inline probes if the script is unavailable (e.g. a repo-less workspace whose plugin symlink was not scaffolded). Readiness = the output contains `SOLEUR_GIT_REPO_READY=true` (script path) OR a bare `true` (fallback path).

If the output shows `SOLEUR_GIT_REPO_READY=false` (or, on the fallback, **neither** probe printed `true`), the workspace has no usable git checkout. In the Soleur web (Concierge) environment this happens when a connected repository is still cloning in the background, or its setup failed (the CWD is then a repo-less `/workspaces/<id>`), OR the `.git` is present but git rejects it (a corrupt/masked config — the emitted `SOLEUR_GIT_REPO_DIAG config_parse_rc`/`err=` fields distinguish these). **Every** route (`go`/`brainstorm`/`plan`/`one-shot`/`fix`/`drain`) will fail: worktree creation, knowledge-base artifact writes, and the session-start preamble all need a real repo. Do NOT run the preamble, do NOT route, do NOT improvise filesystem exploration. STOP and reply with this honest, no-wait message:

> Your workspace isn't ready yet — its repository is still being set up, or its setup didn't finish. Please try again in a moment. If this keeps happening: if your project lives in a **team workspace**, switch to that workspace and try again; if this is your own workspace, check that a repository is connected in **Settings → Repository**.

This gate is deterministic and fires on the first action, so a not-ready workspace produces a clear message instead of a long flail. (The runtime's `worktree_enter_failed` detector only catches a narrow repeated-`cd … && pwd` loop — #5313 — not the general "no repo, agent tries many different commands" case the Concierge no-repo session hit.)

## Step 0: Session-Start Preamble

Before any other work, run the session-start gates from AGENTS.md (`wg-at-session-start-run-bash-plugins-soleur` + `wg-at-session-start-after-cleanup-merged`):

```bash
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged && \
  git worktree list && \
  git show main:.mcp.json > .mcp.json 2>/dev/null || true
```

The script works from either the bare root or any worktree. The `.mcp.json` refresh is harmless inside a worktree (file gets overwritten on next session-start from the new CWD). Skip silently on first error — do not block routing on session-start hygiene.

See `knowledge-base/project/learnings/2026-05-11-bundle-brainstorm-deliberate-revert-and-fixture-source-record.md` Session Errors #1-#2 for the gap this closes.

## Step 1: Worktree Context

Run `pwd`. If the path contains `.worktrees/`, extract the feature name and mention it:

"You're in worktree **feat-[name]**. Want to continue working on this, or start something new?"

If the user wants to continue the current feature, delegate to `soleur:work` via the **Skill tool** with the user input as arguments. Then stop.

**Bare-repo CWD guard.** If `pwd` is NOT inside `.worktrees/` AND `git rev-parse --is-bare-repository` returns `true`, the CWD is a bare-repo root with no working tree. Any Edit/Write to files visible at this path lands on stray untracked content not on any branch, and `node_modules` is not hydrated so typecheck/dev-server commands fail. For file-touching intents (the `fix`/`implement`/`drain`/`review` rows in Step 2), do NOT edit in place — route through `/one-shot` (Grok) or `soleur:one-shot` (Claude) so a proper worktree is created via `worktree-manager.sh`. For read-only intents (questions, exploration, `clo-attestation`, `legal-threshold`), proceed without worktree creation. See `knowledge-base/project/learnings/2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification.md`.

## Step 2: Classify and Route

### Step 2.0: Harness adapter (never improvise)

Before applying the routing table, detect the active harness and use the correct invocation surface. Canonical implementation: `plugins/soleur/lib/harness.ts`.

| Harness | Skills | Agents | Entry command |
|---------|--------|--------|---------------|
| Claude Code | **Skill tool** — `soleur:<skill>` | **Task tool** — `subagent_type` | `/soleur:go` |
| Grok Build | **Slash command** — `/<skill>` (e.g. `/one-shot`) | **spawn_subagent** | `/go` (not `/soleur:go`) |

**Routing contract (never improvise):** when a table row names `soleur:<skill>` or an agent, invoke it via the harness adapter (`invokeSkill` / `spawnAgent` semantics in `harness.ts` — or `routingInstructions()`). Pass the original user input as args/prompt. **Do NOT** improvise workflow steps, explore the filesystem as a substitute, or hand-roll plan/work/review phases when a registered route exists.

**Grok Build harness:** entry is `/go` (slash command); agents via `spawn_subagent`. Map `soleur:<skill>` → `/<skill>` (strip prefix) at invocation time. **Agent spawn keys:** Grok matches `subagent_type` to the `.grok/agents/` **filename stem** (colons → hyphens), e.g. `soleur:product:cpo` → `soleur-product-cpo`. Colon form is listed in some error catalogs but is **rejected** at spawn — always use `spawnAgent()` / `agentIdToGrokSubagentType()`. See `lib/harness.ts:detectHarness`, `formatSkillInvocation`, `spawnAgent`.

**Self-reference (Phase C #6323 / epic #6320):** This document + the eval-harness Grok arm were produced and shipped by invoking `/go 6320 implement and ship the next open feature` (next open = Phase C #6323) inside worktree `feat-one-shot-6323-grok-phase-c` (draft PR #6329). The routing contract above is the enforceable spec exercised by this very run. Edits to the go-routing block are gated by eval-harness (see `gated-skills.json` + `eval-gate:block:go-routing`).

If harness is unknown and Skill/slash tools are unavailable, STOP and suggest `grok inspect` + `grok --trust` (Grok) or `claude --plugin-dir ./plugins/soleur` (Claude).

Analyze the user input and classify intent using semantic assessment:

<!-- eval-gate:block:go-routing:start -->
| Intent | Trigger Signals | Routes To |
|--------|----------------|-----------|
| fix | The user describes broken behavior, errors, regressions, or something that needs fixing | `soleur:one-shot` |
| drain | "fix all issues labeled X", "drain the Y backlog", "close all label:Z", "clean up the X backlog" | `soleur:drain-labeled-backlog` |
| drain-prs | "drain the open PRs", "review and merge all open PRs", "merge all the green PRs", "clear the PR queue/backlog", "triage open pull requests" — draining open PULL REQUESTS (not labeled issues, which is the `drain` row above; not a single named PR, which is the `review` row below) | `soleur:drain-prs` |
| clo-attestation | The user input is `#N` (or a bare number) AND `gh issue view N` returns a body containing `clo_routable: true` OR matches ALL of: `type:\s*manual`, `manual_because:\s*subjective-design-call`, AND at least one external legal-source signal (`eur-lex\.europa\.eu`, `leginfo\.legislature\.ca\.gov`, `congress\.gov`, `federalregister\.gov`, `legislation\.gov\.uk`, `laws-lois\.justice\.gc\.ca`, OR a `Art\.\s*[0-9]+` / `§\s*[0-9]+` statute citation in the body). Must fire BEFORE the `review` row. | `clo` agent (Task spawn; the agent's prompt receives the full issue body + the verification question(s) extracted from the body) |
| review | "review PR", "check this code", PR number reference (when `#N` resolves via `gh pr view N` — confirm PR-vs-issue type before routing) | `soleur:review` |
| legal-threshold | The user input mentions an inbound vendor MSA, DSAR (data subject access request) / right-to-be-forgotten / data deletion request / account deletion request / data export request / "what data do you have on me", AI vendor terms / vendor AI review, OSS license question (GPL/AGPL/SSPL/copyleft), OR a personal-data exposure / unauthorized access / PII leak that crosses a statutory clock (GDPR Art. 33 72h) — events that exceed founder-grade compliance helping and warrant a downstream specialist | `clo` agent (Task spawn; the Assess phase emits the threshold catalog from `knowledge-base/legal/recommended-tools.md`) |
| incident | The user describes a live or recent production incident (outage, customer-impact, Sentry alert) needing classification + PIR. NOTE: pure data breaches without an operational outage route to `legal-threshold` above (statutory clock takes precedence); use `incident` for ops-postmortem scope (uptime, latency, error-rate). | `soleur:incident` |
| implement | User asks to **implement**, **build**, or **ship** a scoped feature, issue, or phase (e.g. "implement Phase F", "#6325 implement", "ship this feature") — concrete deliverables, not open-ended exploration | `soleur:one-shot` |
| default | Everything else — features, exploration, questions, generation, vague scope without implement/build/ship intent | `soleur:brainstorm` |
<!-- eval-gate:block:go-routing:end -->

### Step 2.1: Post-route invocation fidelity (Grok Build — never bypass)

<!-- workflow-fidelity:block:go-post-route:start -->
When Step 2 routes to a **pipeline skill** (`soleur:one-shot`, `soleur:brainstorm`, `soleur:drain-labeled-backlog`, `soleur:drain-prs`):

0. **You are still in `/go`, not in the pipeline skill.** Routing is classification + dispatch only. The `/go` handler does **not** run pipeline phases, create worktrees for implementation, or write product code — even if you "know what the skill would do next."
1. **Your very next action** MUST invoke that skill via the harness adapter — Grok: slash command (`/brainstorm <args>`, `/one-shot <args>`, …); Claude: Skill tool (`soleur:brainstorm`, `soleur:one-shot`, …). Do **not** read the skill's SKILL.md and execute a subset of its steps with Write/Edit/Shell yourself.
2. **Do NOT end your turn** after routing, worktree creation, brainstorm artifacts, or a pushed draft PR. Those are mid-pipeline checkpoints, not deliverables.
3. **`brainstorm` deliverable:** brainstorm doc + spec + handoff to `/plan` (or `/one-shot` shortcut when requirements are clear). **FORBIDDEN:** product code during brainstorm.
4. **`one-shot` deliverable:** merged PR + `<promise>DONE</promise>` (Step 8). Pushed code on a draft PR without review/ship is a **protocol violation**, not completion.
5. **Lifecycle handoff skills (standalone or under orchestrators):** `plan` → `/work`; `work` → `/review` → `/qa` (when structural UI gate fires) → `/compound` → `/ship`. Never substitute ad-hoc tool loops. Each skill's exit summary is a **continuation gate**, not a stopping point.
6. **Canonical contract:** `plugins/soleur/lib/workflow-fidelity.ts` (`PIPELINE_SKILLS`, `IMPLEMENTATION_TAIL`, `HANDOFF_SKILLS`) + `routingInstructions()` in `harness.ts`.
<!-- workflow-fidelity:block:go-post-route:end -->

If intent is clear, route without confirmation:

- **Claude Code:** invoke via the **Skill tool** (`soleur:<skill>`, args = original user input). Agents: **Task tool** with `subagent_type` and prompt = original user input.
- **Grok Build:** invoke via **slash command** (`/<skill>` with args appended). Agents: **spawn_subagent** with the agent id and prompt = original user input.

Map `soleur:<skill>` cells in the table to Grok `/<skill>` at invocation time (strip the `soleur:` prefix). **Exception:** rows whose `Routes To` cell names an agent (e.g., `clo`) instead of a `soleur:<skill>` skill spawn that agent — never substitute a manual workflow. When extending this table, prefer routing to a skill when one exists; route to an agent only when no skill wraps the desired behavior.

**PR-vs-issue type resolution (when `#N` or a bare number is the input):** Before evaluating the `clo-attestation` and `review` rows, run `gh issue view N --json body,title,state 2>/dev/null` to determine whether `N` is an issue. If `gh issue view` succeeds AND the body satisfies the `clo-attestation` predicate, route to clo. If `gh issue view` succeeds but no `clo-attestation` match, route to `soleur:review` only after confirming `gh pr view N` ALSO succeeds (otherwise the input is a non-attestation issue — route to default/brainstorm with the issue body as context). This ordering closes the gap that caused `/soleur:go #3998` to mis-route an issue to PR review. See `knowledge-base/project/learnings/workflow-patterns/2026-05-18-clo-attestation-auto-route-instead-of-human-task.md`.

When routing to `soleur:drain-labeled-backlog`, extract the label value from the user's message. If the user used a bare name (e.g., "security"), resolve it to the namespaced form by running `gh label list --limit 100 | grep -i <name>` before invoking — `gh` rejects an invalid `--label` with a clear error, so verify against the live label set. Pass the resolved label via `--label <resolved>` in the skill arguments.

If intent is truly ambiguous, use the **AskUserQuestion tool** with 4 options: Brainstorm (Recommended), Fix (one-shot), Drain (labeled backlog), Review.

## Sharp Edges

- **NAME-relative worktree detection (Linear-ID-keyed entry).** Step 1 only checks whether `pwd` is currently inside a worktree (CWD-relative). If the user input contains a Linear ID (`SOL-\d+`) and `git worktree list` shows a sibling worktree named after that ID (e.g., `.worktrees/feat-one-shot-sol-39-*` or `.worktrees/feat-fix-sol-39-*`), surface that state BEFORE routing to one-shot — routing fresh would collide with the existing branch and orphan any open draft PR. Present a 4-option `AskUserQuestion` (continue / review existing PR / restart fresh / brief). If "restart fresh" is chosen, follow up with a SECOND `AskUserQuestion` enumerating cleanup scope (full nuke / soft nuke / cancel) so destructive actions get explicit per-step approval. See `knowledge-base/project/learnings/2026-05-12-soleur-go-restart-fresh-from-existing-wip.md`.
- **Worktree-recovery PR-merge probe.** When the user asks to resume/recover a stale worktree (e.g., after a laptop crash, branch switched away, phantom staged files), run `gh pr list --head <branch> --state all --json number,state` BEFORE proposing "reset to remote branch". A remote feature branch existing is NOT proof the work is open — squash merges leave the source branch intact. If `state == MERGED`, the recovery path is clean-and-remove (`git reset --hard HEAD` → `git worktree remove` → `git push origin --delete <branch>`), not reset-to-remote (which would silently re-introduce pre-merge state). See `knowledge-base/project/learnings/workflow-patterns/2026-05-19-worktree-recovery-check-pr-merge-status-first.md`.
- **Worktree-plan-vs-issue alignment (`#N` entry → "Continue in that worktree").** When the input is an issue `#N` and a topically-named worktree already exists, NAME-relevance is NOT issue-relevance. Before offering "Continue in that worktree", grep the worktree's planning artifact (`knowledge-base/project/plans/*`, `specs/feat-*/spec.md` frontmatter `closes:`) for the input issue number. If the worktree's plan targets a DIFFERENT (sibling) issue, surface that mismatch in the `AskUserQuestion` options (offer a fresh worktree for `#N` vs. continuing the existing one for `#M`). Issues that a body explicitly splits into a "separate PR" / "follow-up PR" must not be silently co-located. See `knowledge-base/project/learnings/2026-05-29-brand-hex-commit-gate-and-go-worktree-plan-mismatch.md`.
- **Grok Build bypass guard (#6325 class).** If you routed to `soleur:one-shot` and find yourself writing product code or running `git commit` before `/review` and `/ship` ran, STOP — you inlined the pipeline. Invoke `/one-shot <args>` (or continue the active one-shot Steps 3–8), never "implement then report done."
- **Brainstorm / plan / work bypass guard (#6320 lifecycle).** If you routed to `soleur:brainstorm` and wrote product code, or finished brainstorm/plan artifacts without invoking `/plan` or `/work`, or pushed from `/work` without `/review` → `/ship`, STOP — invoke the mandated successor from `workflow-fidelity.ts` (`BRAINSTORM_CHILD_SKILLS`, `IMPLEMENTATION_TAIL`).
- **Scrub closed `#N` contextual citations before invoking one-shot.** When routing to `soleur:one-shot`, the args you construct must use `#N` form ONLY for OPEN work-target issues. A *contextual* citation of a prior merged PR/issue ("structural causes already fixed in #4577", "supersedes #1234") trips one-shot's Step 0a.5 closed-issue collision abort — the gate cannot distinguish a work target from a citation. Rephrase such citations to date-anchored prose ("the apex-canonical reconciliation merged 2026-05-29") before invoking. **Scrub the QUOTED TITLES too, not just your prose** — a decision-challenge/follow-up issue routinely carries the predecessor `#N` inside its own title (`decision-challenge: … while fixing #6572`), so an args block that quotes that title verbatim to say which issue to close re-imports the closed ref and the gate aborts on args that read as fully scrubbed. Grep your constructed args for `#[0-9]+` and confirm every survivor is an OPEN work target before invoking. **Why:** #6578 — two aborts, prose scrubbed on the first, the title quote missed on both. See `knowledge-base/project/learnings/2026-06-15-gsc-crawled-not-indexed-remediation-is-internal-linking.md` and `knowledge-base/project/learnings/workflow-patterns/2026-05-25-one-shot-closed-issue-gate-fires-on-contextual-refs.md`.
- **An issue that claims the bug is external ("not in this repo", "vendor/bot backend", "no code here") is a claim to VERIFY, not a fact to route on** (`hr-verify-repo-capability-claim-before-assert` applied to routing). Before deflecting such an issue as out-of-scope or dispatching it to a non-existent external service, `git grep -l "<verbatim symptom string the issue quotes>" main` — a named "bot"/"GitHub App" is frequently the *identity* an in-repo automation authenticates as, not a separate codebase, and its user-visible comment strings are string literals in the code that emits them. If the grep resolves, route to `one-shot` and have the plan/PR body correct the misframing. See `knowledge-base/project/learnings/workflow-patterns/2026-07-06-issue-claims-bug-is-external-verify-with-literal-grep-before-routing.md` (#6132 — "external soleur-ai bot" was the in-repo `cron-follow-through-monitor.ts`).
- **An operational "do the real cutover / run the workflow / flip it live" request routes to a gated `workflow_dispatch`, NOT to `soleur:one-shot`.** When the work's *mechanism* already merged and the ask is to EXECUTE it in production (a cutover, a migration apply, a plaintext wipe), the deliverable is dispatching the gated `workflow_dispatch` — verify readiness first (target state exists, dry-run rehearsal green, escrow/preconditions proven), confirm the GitHub `environment:` required-reviewer set is **non-empty** (a zero-reviewer environment auto-approves — DP-11 F8), then `gh workflow run <wf>.yml -f dry_run=false`. Dispatching QUEUES the irreversible step for the operator's environment approval; it does not bypass the human gate, so proceed without a redundant confirmation once the operator has asked. The **code FIX that FOLLOWS a safe-abort** (a fail-closed gate that discarded its evidence, a missing precondition) is the one-shot task — not the cutover itself. See `knowledge-base/project/learnings/workflow-patterns/2026-07-19-real-cutover-routes-to-workflow-dispatch-and-failclosed-gate-must-self-report.md`.
- **Diagnostic / incident / verification loops: self-pull from the observability layer — never ask the operator to fetch.** When any route surfaces a failure to diagnose, pull the errors/telemetry yourself: Better Stack `SOLEUR_*` markers via `scripts/betterstack-query.sh` (creds in Doppler `prd_terraform`) and Sentry. Never ask the operator to paste error output, run probes (`grep`/`stat`/`git config`), or eyeball logs — the operator decides, they do not retrieve. If a needed diagnostic signal is missing from telemetry, ADD a monitored stdout `SOLEUR_*` marker in the emitting code so the next occurrence self-reports — do not escalate to the operator for it. **And when a component reports SUCCESS but its downstream effect is absent (a webhook 2xx with no handler run, a deploy exit-0 with no state change, a run "succeeded" on a stale artifact), ship THAT component's OWN error channel FIRST (its unit/binary journald → the vector allowlist) BEFORE black-box reproduction — a success-code that fires regardless of command success is a silent-failure anti-pattern, and verify gates must assert against the EXPECTED source-of-truth count, not the artifact's self-reported total.** Cite `hr-no-dashboard-eyeball-pull-data-yourself`. See `knowledge-base/project/learnings/workflow-patterns/2026-07-08-self-pull-observability-in-diagnostic-loops-never-ask-operator-to-fetch.md` (#5934 worktree-wedge) and `knowledge-base/project/learnings/2026-07-11-webhook-202-but-handler-never-ran-e2big-ship-component-error-channel-first.md` (#6178 — webhook 202 while fork/exec died E2BIG; hours of manual repro before the unshipped webhook journald named it).
