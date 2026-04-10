# Agent Instructions

This repository contains the Soleur Claude Code plugin. Detailed conventions live in `knowledge-base/project/constitution.md` -- read it when needed. This file contains only rules the agent will violate without being told on every turn.

## Hard Rules

- Never `git stash` in worktrees [hook-enforced: guardrails.sh guardrails:block-stash-in-worktrees]. Commit WIP first, then merge. Use `git show <commit>:<path>` to inspect old code without modifying working tree state.
- MCP tools (Playwright, etc.) resolve paths from the repo root, not the shell CWD. Always pass absolute paths to MCP tools when in a worktree.
- When a command exits non-zero or prints a warning, investigate before proceeding. Never treat a failed step as success.
- Always read a file before editing it. The Edit tool rejects unread files, but context compaction erases prior reads -- re-read after any compaction event.
- When a plan specifies relative paths (e.g., `source "$SCRIPT_DIR/../../..."`), trace each `../` step to verify the final target before implementing. Plans have prescribed wrong paths that were implemented verbatim and only caught by review agents.
- The host terminal is Warp. Do not attempt automated terminal manipulation via escape sequences (cursor position queries, TUI rendering, and similar sequences are intercepted by Warp's tmux control mode and silently fail).
- The Bash tool runs in a non-interactive shell without `sudo` access. Do not attempt commands requiring elevated privileges -- provide manual instructions instead.
- Exhaust all automated options before suggesting manual steps. Priority chain: (1) Doppler (`doppler secrets get <KEY> -p soleur -c dev --plain`, check `prd`/`ci`/`prd_terraform` configs too), (2) MCP tools (`ToolSearch`), (3) CLI tools (`gh`, `hcloud`, `supabase` — install with `curl`/`tar` to `~/.local/bin` if missing), (4) REST APIs (`curl`/`WebFetch`), (5) Playwright MCP (bootstraps credentials — retrieve token, store in Doppler, then switch to CLI/API), (6) manual handoff. Only prompt for credentials not found in any Doppler config.
- Never label any step as "manual" without first attempting automation. Browser tasks → Playwright MCP first (only CAPTCHAs and OAuth consent are genuinely manual). Post-merge steps → verify each cannot be automated (`terraform apply`, `ssh`, `gh secret set`, `gh workflow run`). Plans that say "manual" when the tool is available are a workflow violation.
- All infrastructure provisioning (servers, volumes, firewalls, DNS) goes through Terraform — never vendor APIs or manual SSH. SSH is read-only diagnosis only (`printenv`, `docker inspect`, `journalctl`); fixes go into Terraform config. Vendor APIs are permitted only for read-only checks or account-level tasks Terraform cannot cover. Patterns live in `apps/web-platform/infra/`.
- Every new Terraform root must include an R2 remote backend (`soleur-terraform-state` bucket, key `<app-name>/terraform.tfstate`). Copy from `apps/web-platform/infra/main.tf`. Local state is never acceptable.
- In GitHub Actions `run:` blocks, never use heredocs or multi-line shell strings that drop below the YAML literal block's base indentation. Heredoc bodies and terminators at column 0 break YAML parsing entirely (GitHub shows "workflow file issue", zero jobs run). Multi-line `--body`/`--comment` args spanning lines have the same problem. Use `{ echo "..."; } > file` for multi-line file content and shell variables with `$'\n'` for multi-line CLI args. **Why:** In #974, indented heredoc content rendered as `<pre>`. In #1358, left-aligned heredoc content and multi-line `--body` args broke the YAML parser, causing every push to trigger a failing "Main Health Monitor" run with zero jobs.
- GitHub Actions workflow notifications must use email via `.github/actions/notify-ops-email`, not Discord webhooks. Discord is for community content only. For custom bodies, construct HTML in a preceding step and pass as the `body` input.
- New skills, agents, or user-facing capabilities must include CPO and CMO at minimum in brainstorm domain assessment [skill-enforced: brainstorm Phase 0.5]. CTO is included when the capability has architectural implications.
- Before shipping, `/ship` Phase 5.5 runs conditional domain leader gates (CMO content-opportunity, CMO website framing, COO expense-tracking) [skill-enforced: ship Phase 5.5]. These trigger on file-path matches, semver labels, and new service signups.
- When a workflow concludes with an actionable next step, execute it — don't list it as "next action" and stop. Use Playwright MCP, `xdg-open`, CLI tools, or APIs to drive completion. Only hand off for credentials/payment at the exact page.
- Before asserting GitHub issue status, verify via `gh issue view <N> --json state` and check `knowledge-base/` for existing artifacts. Unverified status claims create false urgency.
- Never run commands with unbounded output in subagents — pipe through `| head -n 500` or `| tail -n 200`. Subagent stdout goes to tmpfs; unbounded output fills it and crashes all sessions.
- Never use `sleep` >= 2 seconds in foreground Bash calls — Claude Code blocks it. For polling loops (PR state, CI runs, workflow status), use the **Monitor tool** with a shell loop that emits one line per check: `while true; do result=$(...); echo "$result"; [[ done ]] && break; sleep 15; done`. The sleep runs inside the monitored process, not in a foreground Bash call. For one-shot delayed checks (e.g., wait before listing runs), use `Bash` with `run_in_background: true`. **Why:** The agent tried `sleep 10 && gh pr view` in a foreground Bash call and got blocked, stalling the merge pipeline.
- Never write to Claude Code memory (`~/.claude/projects/*/memory/`) or local-only locations. All knowledge goes into committed repo files: AGENTS.md (hard rules), constitution.md (conventions), `knowledge-base/project/learnings/` (learnings via /compound), `.mcp.json` (MCP configs). Test: "If a new Soleur user clones this repo, do they get this improvement?" If no, it belongs in the repo.

## Workflow Gates

- When moving GitHub issues between milestones, deferring features, changing priorities, or making any roadmap decision, update `knowledge-base/product/roadmap.md` in the same action. The roadmap document is the canonical product truth -- if it contradicts the issue tracker, neither can be trusted. Never change a milestone assignment without updating the corresponding roadmap phase table. **Why:** In the #1064 roadmap session, tag-and-route was deferred from P1 to P3 but the roadmap document was not updated, creating three conflicting sources of truth (roadmap, milestones, conversation). The CPO had to flag this on re-review.
- Every feature listed in a roadmap phase table MUST have a linked GitHub issue. When adding a feature to the roadmap, create the issue in the same action — even for trigger-gated phases where work has not started. Issues can be created with minimal scope and refined later, but they must exist so the milestone is never empty and work is trackable. When creating a new roadmap phase or milestone, verify every feature row has an Issue column entry before committing. **Why:** In the 2026-04-03 milestone audit, Phase 5 had 5 features defined in the roadmap but zero GitHub issues — the milestone existed as an empty shell for weeks because the workflow only enforced issues → milestones (every issue must have a milestone) but not milestones → issues (every milestone must have issues).
- When a research sprint produces recommendations, run the cascade-validate loop [skill-enforced: work Phase 2.5]. "Findings written" is NOT done — "findings applied, validated, and all documents reflect the final state" is done.
- When fixing a workflow gate's detection logic, retroactively apply the fixed gate to the case that exposed the gap [skill-enforced: ship Phase 5.5 Retroactive Gate Application]. "Gate fixed" is not done — "gate fixed AND missed case remediated" is done.
- Zero agents until user confirms direction. Present a concise summary first, ask if they want to go deeper, only then launch research. Exception: passive domain routing (see below).
- Before every commit, run compound (`skill: soleur:compound`). Do not ask whether to run it -- just run it.
- Never bump version files in feature branches. Version is derived from git tags — CI creates GitHub Releases with `vX.Y.Z` tags at merge time via semver labels. Set labels with `/ship`. Do NOT edit `plugin.json` version (frozen sentinel) or `marketplace.json` version.
- Use `/ship` to automate the full commit/push/PR workflow. It enforces review and compound gates.
- After marking a PR ready, run `gh pr merge <number> --squash --auto` to queue auto-merge, then poll `gh pr view <number> --json state --jq .state` until MERGED, then `cleanup-merged`. Never stop at "waiting for CI" -- actively poll and merge in the same session.
- After a PR merges to main, verify all release/deploy workflows succeed before ending the session [skill-enforced: ship Phase 7]. A merged PR with a failing release workflow is a silent production outage.
- At session start, from any active worktree (not the bare repo root): run `bash ../../plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged && git worktree list`. If no worktree exists for the current task, run `git worktree list` from the bare root, then create a worktree with `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create <name>` before doing any work. The repo root is a bare repository -- never run `git pull`, `git checkout`, or other working-tree commands from the bare root.
- At session start, refresh `.mcp.json` at the bare repo root: `git show main:.mcp.json > .mcp.json`. Claude Code reads `.mcp.json` from the CWD on startup to discover MCP servers (Playwright, etc.). Bare repos have no working tree, so this file must be manually kept in sync with the tracked version. Without this step, MCP servers added in feature branches are unavailable until the next session.
- When a test runner crashes (segfault, OOM, abort), never dismiss it as "known" or "unrelated". Either fix the root cause, file a GitHub issue to track it, or document a concrete workaround. A crash without a tracking issue is a workflow violation.
- When tests fail and are confirmed pre-existing (same on main), create a GitHub issue to track them before proceeding. Pre-existing failures without tracking issues normalize a red suite.
- When an audit identifies pre-existing issues, create GitHub issues to track them before fixing. Don't just note them in conversation -- file them.
- When deferring a capability, create a GitHub issue (what, why, re-evaluation criteria) milestoned to the target phase or "Post-MVP / Later". A deferral without a tracking issue is invisible.
- When a workflow gap causes a mistake, fix the skill or agent first — a learning is not a fix. Only record a learning when no code change can address the gap.
- Use `Closes #N` in PR **body** (not title) to auto-close issues. For partial work, use `Ref #N` — never `Closes #N partially` (GitHub ignores qualifiers and auto-closes regardless).
- After merging a PR that adds or modifies a GitHub Actions workflow, trigger a manual run (`gh workflow run <file>.yml`), poll until complete (`gh run view <id> --json status,conclusion`), and investigate failures before moving on. New workflows must be verified working, not just syntactically valid.
- When a PR includes database migrations (`supabase/migrations/`), verify they are applied to production before closing the issue. Test via Supabase REST API. A committed-but-unapplied migration is a silent deployment failure.
- When a feature creates external resources (Cloud tasks, Doppler configs, DNS, infrastructure), validate each resource produces correct output BEFORE shipping. Never ship without running each new service and verifying output.
- For user-facing pages with a Product/UX Gate, specialists (ux-design-lead, copywriter) must produce artifacts before implementation. Code implements from approved artifacts, not brainstorm notes.

## Code Quality

- Write failing tests BEFORE implementation code when a plan includes Test Scenarios or Acceptance Criteria [skill-enforced: work Phase 2 TDD Gate]. Infrastructure-only tasks (config, CI, scaffolding) are exempt.
- Always run `npx markdownlint-cli2 --fix` on changed `.md` files before committing. Re-read after `replace_all` on Markdown tables to verify cell spacing.
- Ensure dependencies are installed at the correct package level (not just root) before tests or CI. Check subdirectories like `agent-browser/` or app-level packages.
- For production debugging, use observability tools — never SSH for logs. Priority: (1) Sentry API (`SENTRY_API_TOKEN` from Doppler `prd`), (2) Better Stack, (3) `/health` endpoint. SSH is for infrastructure provisioning only.
- When lefthook hangs in a worktree (>60s), kill (`pkill -f "lefthook run"`), verify checks manually, commit with `LEFTHOOK=0`. Known lefthook/worktree bug.
- Playwright MCP uses `--isolated` mode (`.mcp.json`). If singleton lock fails, kill Chrome processes. Do not remove `--isolated` — required for parallel sessions.
- After completing a Playwright task, call `browser_close` [hook-enforced: browser-cleanup-hook.sh].
- Before pushing `package.json` changes, verify deps are in the correct `package.json` (app-level, not just root) and both `bun.lock` and `package-lock.json` are regenerated if both exist (Dockerfile uses `npm ci`).
- Doppler service tokens are per-config — use config-specific GitHub secret names (`DOPPLER_TOKEN_PRD`, `DOPPLER_TOKEN_CI`), never bare `DOPPLER_TOKEN`. The `-c` flag is silently ignored with service tokens. See `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`.
- When running terraform commands locally with Doppler, always use `doppler run --name-transformer tf-var` to match CI behavior. Export `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` separately for the R2 backend — the name transformer renames them to `TF_VAR_*` which the backend ignores.

## Review & Feedback

- After merging, read files from the merged branch (`git show main:<path>`), not the bare repo directory (stale).
- Never skip QA/review before merging. Full pipeline: plan → implement → review → QA → compound → ship.
- Before shipping, verify: (1) review comments resolved, (2) QA run with screenshots if UI, (3) tests pass locally.
- When a reviewer or user says to keep a feature/phase, do not remove it without explicit confirmation.

## Passive Domain Routing

- When a user message contains a clear, actionable domain signal unrelated to the current task (expenses, legal commitments, marketing mentions, sales leads, etc.), read `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` and spawn the relevant domain leader as a background agent (`run_in_background: true`) using the Assessment Question to detect relevance and the Task Prompt to delegate. Continue the primary task without waiting.
- Do not route on trivial messages ("yes", "continue", "looks good") or when the domain signal IS the current task's topic (e.g., do not route to CTO during an engineering brainstorm about architecture).

## Communication

- Challenge reasoning instead of validating. No flattery. If something looks wrong, say so.
- Delegate verbose exploration (3+ file reads, research, analysis) to subagents. Keep main context for edits and user-facing iteration.
