---
feature: wire-fix-constraints-dispatcher
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-30-feat-wire-fix-constraints-dispatcher-plan.md
closes: [5791]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks: Wire the `/soleur fix constraints` recovery comment-dispatcher (#5791)

## Phase 0 — Preconditions
- [ ] 0.1 Confirm `id-token: write` decision (RESOLVED at deepen-plan — both in-repo claude-code-action users carry it; include on the fix job).
- [ ] 0.2 Confirm `.github/actions/anthropic-preflight/action.yml` `ok` output + `scripts/extract-api-spend.sh` arg shape (both present).
- [ ] 0.3 Re-confirm no `.github/workflows/fix-constraints.yml` / `references/fix-constraints*.template` exists.

## Phase 1 — The dispatcher (repo-root, dogfooding)
- [ ] 1.1 Create `.github/workflows/fix-constraints.yml` — THREE jobs (preflight / fix / notify-on-skip):
  - issue_comment trigger; exact-match command; author_association gate; `concurrency: fix-constraints-${{ github.event.issue.number }}`, `cancel-in-progress: false`. (AC1–AC4)
  - per-job permissions (NO top-level block — job-level replaces): preflight=contents:read, fix=contents:write+pull-requests:write+id-token:write, notify=pull-requests:write. (AC1, SEC-F6)
  - fix job: `checkout persist-credentials:false` (SEC-P1) → commenter-permission gate `gh api .../permission ∈ {admin,write}` (SEC-P2/AC8c) → head==base/isCrossRepository guard (FR3/AC6) → `gh pr checkout` head ref → claude-code-action (pinned SHA `ab8b1e6…`, `--model claude-sonnet-4-6 --max-turns 20 --allowedTools Bash,Read,Write,Edit,Glob,Grep`; agent EDITS only) → API-spend capture → RE-RUN constraint-gates.sh to verify (SEC-F3/AC8d) → commit + push via explicit `x-access-token` credential to PR head ONLY (FR4/AC7/AC8b) → deterministic outcome comment (recovered/no-change/still-red). (AC5,AC7,AC8,AC8b,AC8d)
  - notify-on-skip job: `always()`, depends on preflight+fix, re-checks PR+command+author gate, fires when `needs.fix.result != 'success'`; stays silent on intended-silent paths (SEC-F2/AC8e).
- [ ] 1.2 Lint: `actionlint .github/workflows/fix-constraints.yml`; `bash -c` on extracted `run:` snippets (NOT `bash -n` on the .yml).

## Phase 2 — Tenant emission (skill template + emitter)
- [ ] 2.1 Add `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-workflow.template` (`__TARGET_DIR__`-parameterized runner path). (AC9)
- [ ] 2.2 Wire `plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh`: `FIXWORKFLOW` path, refuse-if-exists loop, worktree-copy path (~L108), `sed __TARGET_DIR__` emit (~L151), `log:` line (~L153).
- [ ] 2.3 Add emitter self-test under `plugins/soleur/skills/constraint-scaffold/test/` asserting fix-constraints.yml is emitted + refuse-on-overwrite (mirror `boundary.test.sh`). (AC9)

## Phase 3 — Wording sweep (flip "planned/not yet wired" → "wired"; "blocked on #5791 and #5778" → "blocked on #5778"; keep "informational/non-blocking")
- [ ] 3.1 Emitted dogfooding copies: `apps/web-platform/scripts/constraint-gates.sh` (header L9–10 + 5 `::error::` L38,42,79,86,88), `apps/web-platform/.dependency-cruiser.cjs` (L7–8), `apps/web-platform/.github/workflows/constraint-gates.yml` (L9), `.github/workflows/constraint-gates.yml` (L10–11, L18). In each `::error::`, render the command as a BARE copy-pasteable line, NOT backticked (SEC-F5/AC8f).
- [ ] 3.2 Source templates: `references/shared-runner.template` (L9–10 + 5 `::error::`), `references/depcruise-config.template` (L7–8), `references/constraint-gates-workflow.template` (L9). Same bare-command rendering (AC8f).
- [ ] 3.3 Skill: `plugins/soleur/skills/constraint-scaffold/SKILL.md` (recovery model L35–40; "What it emits" table — add fix-constraints.yml row + update the constraint-gates.yml row wording).
- [ ] 3.4 EXCLUDE the historical learnings file `2026-06-30-constraint-scaffold-verify-every-assumed-capability-...md` (point-in-time record). (AC10)

## Phase 4 — ADR-071 amend + C4 confirm
- [ ] 4.1 Amend `ADR-071-l1-constraint-gates.md` L34–40: dispatcher wired (`.github/workflows/fix-constraints.yml`, #5791); promotion gated on #5778 only. (AC13)
- [ ] 4.2 Read all three `.c4` files; confirm no model change (founder/github/anthropic already modeled); fix any falsified description; run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 5 — Verification + post-merge
- [ ] 5.1 Run repo test suite (per `package.json scripts.test`) + constraint-scaffold self-tests green. (AC14)
- [ ] 5.2 Residual-zero greps: `not yet wired` / `planned (#5791` / `blocked on #5791` → 0 over swept set; legit ADR-070 refs untouched. (AC10/AC11/AC12)
- [ ] 5.3 PR body: `Ref #5791` (NOT `Closes`). (AC15)
- [ ] 5.4 POST-MERGE (automatable via `gh`): `gh issue edit 5791` → ADR-070→ADR-071 in body; then `gh issue close 5791`. (AC16)
- [ ] 5.5 Do NOT promote the gate to a required check (NG1; still blocked on #5778). (AC17)
- [ ] 5.6 POST-MERGE functional smoke (SEC-F8/AC18): scratch PR trips the gate → comment exact `/soleur fix constraints` → confirm recovered + outcome comment; confirm near-miss/unauthorized/un-fixable paths behave as designed. The workflow can't run from the feature branch (issue_comment = default-branch only). Do NOT close #5791 until smoke passes.

## Notes
- CPO sign-off required at plan time (single-user-incident threshold). `security-sentinel` + `user-impact-reviewer` at review time.
- Model/SHA pins mirrored from `claude-code-review.yml` / `test-pretooluse-hooks.yml` — do NOT drift; pin freshness owned by `model-launch-review`.
