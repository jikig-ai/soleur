# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-07-31-docs-art30-register-claude-eval-fleet-and-ci-surface-plan.md`
- Status: recovered from partial-artifact (planning subagent died on `API Error: Connection closed mid-response`; the plan body, `tasks.md` and `decision-challenges.md` were already on disk, so only the Session Summary emission was lost)

### Errors
- Planning subagent terminated early on an API connection error. Recovery per the one-shot
  partial-artifact protocol: on-disk artifacts inspected and validated rather than re-running
  `/soleur:plan` from scratch.
- The subagent's final in-flight action was a corrective pass over four possessives it had
  over-applied with a blanket `sed`. **Verified complete by the pipeline runner**: no `PA-32`
  line references the CI surface and no `PA-33` line references community/republication, and
  all fifteen `PA-3x` possessives read correctly in context. No curly-apostrophe or
  malformed-possessive residue.
- **Scope verified clean**: `git diff a6856bb0d..HEAD --name-only` is empty and the only
  untracked paths are under `knowledge-base/project/{plans,specs}/`. The subagent did NOT
  breach its plan-only mandate — `article-30-register.md`, `anthropic.md` and
  `compliance-posture.md` are all untouched.

### Repairs applied by the pipeline runner
- Plan frontmatter was emitted **below** the H1, which breaks YAML frontmatter parsing (repo
  convention places `---` at line 1). Moved the H1 beneath the frontmatter block.
- Added `closes: 7100` to the frontmatter alongside the existing `issue: 7100`.

### Decisions
- **Three register entries, not two** (D1): PA-31 (Anthropic-egressing Inngest fleet, internal
  egress), PA-32 (community observation and republication, public output), PA-33 (Jikigai-keyed
  Anthropic surface in GitHub Actions CI). Publication is a distinct Art. 4(2) operation and
  cannot share a `(d)` recipients or `(f)` retention cell with internal egress.
- **PA-31 is scoped by an egress predicate, not by helper name** (D2) — `spawnClaudeEval`
  undercounts because `cron-daily-triage` and `cron-follow-through-monitor` call
  `resolveClaudeBin()` directly. Verified membership is a 21-member union proven by two
  independent predicates that must agree byte-for-byte.
- **PA-33 keys on the `secrets.ANTHROPIC_API_KEY` reference, not on `claude-code-action`** (D8) —
  two live callers reach Anthropic via a step-level `env:` with no action involved, so an
  action-scoped entry would be false on the day it was written.
- **D9 (most consequential): Art. 6(1)(f) is NOT available for the republication limb as
  implemented.** Necessity fails and is dispositive; Art. 17 is not implementable against
  append-only git history plus 2 forks; PA-30's own LIA already rejected git-committed PII as
  an Art. 17 impossibility. The record must state this rather than assert a basis the
  processing does not have. Remediations R1–R5 are filed as a blocking follow-up issue because
  they are source edits outside this PR's docs-only scope.
- **Art. 14 is engaged, undischarged and overdue** (D5), backdated to ~2026-03-19.
- The plan corrects several claims carried in the issue and in the two downstream legal
  records rather than propagating them (13 not 15 `spawnClaudeEval` callers; 3 not 2 HTTP
  callers; 20 not 17 substrate importers; 5 `.github/` secret consumers, only 3 of which use
  `claude-code-action` and one of those disabled).

### Components Invoked
- `soleur:plan`, `soleur:deepen-plan` (inside the planning subagent, via the Task tool)
- Pipeline runner: workspace readiness gate, Linear preflight (no-op), open-issue collision
  check + body/title/git-log probes, premise validation, `worktree-manager.sh create`,
  `worktree-manager.sh draft-pr` (PR #7110), partial-artifact recovery and validation
