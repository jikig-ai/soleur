---
title: "fix: safe-bash git-branch tightening + kb-search support-persona path (#9555, #9559)"
type: fix
date: 2026-10-06
slug: fix-safe-bash-git-branch-support-kb-search
branch: feat-one-shot-9555-9559-safe-bash-kb-search
issue: 9555
closes: [9555, 9559]
priority: p2-medium
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix: safe-bash git-branch tightening + kb-search support-persona path (#9555, #9559)

## Enhancement Summary

**Deepened on:** 2026-10-06
**Sections enhanced:** Observability, Guard Contract, Fix A, Fix B,
Files to Edit, Test Scenarios, Sharp Edges
**Research agents used:** none — executed as a Devin subagent with no
Task/Workflow spawn surface; every deepen-plan phase was run as inline
orchestrator work (per-section research, skill match, learnings filter,
verify-the-negative, post-edit self-audit, review lenses). Halts were
executed mechanically where a mechanical check exists.

### Deepen-pass gate results

- **4.4 precedent-diff** — pass: the two-arm regex reuses the in-file
  `PATH_TOKEN` + `(?!-)` precedent (`safe-bash.ts:127-134`); no
  pattern-bound class (SQL/atomic-write/lock/RPC/cron) in scope.
- **4.45 verify-the-negative** — pass: `grep` exclusion confirmed at
  `safe-bash.ts:39-41`; `plugins/soleur/scripts/ensure-kb-index.sh`
  confirmed absent; deployed plugin root has no `.git` (verified
  `ls -d …/.git` → absent — `git grep` cannot run there anyway);
  `support-escalation.ts:118` confirms the `deny-support-${source}`
  decision slug cited in Observability.
- **4.5 network-outage / 4.55 downtime** — not triggered.
- **4.6 User-Brand Impact** — pass: section present, `none` threshold +
  non-empty sensitive-path scope-out reason.
- **4.7 Observability** — pass: 5/5 fields non-empty; probe verb `rg`
  allowlisted; metachar-free command; literal `expected_output`.
- **4.8 PAT halt** — pass: zero hits.
- **4.9 UI wireframe** — pass-through: zero UI-surface files.
- **4.10 encryption posture** — not triggered (no store/connection).
- **4.11 Guard Contract** — pass: `lint-guard-contract.py` green (2
  entries); assemblies are structural (chokepoint + glob discovery), not
  member lists.
- **4.12 Scope Check** — pass: one unfenced section, all subsections,
  no unmapped rows, `Recommendation: single PR`.

### Key Improvements (deepen pass)

1. `discoverability_test.command` rewritten metachar-free (`-e` patterns,
   no `|` alternation) after reading Check 10's byte-level reject in
   `plan-sharp-edges.md`.
2. Verification commands corrected to `./node_modules/.bin/vitest run` —
   `bunfig.toml` `pathIgnorePatterns = ["**"]` makes `bun test` discover
   nothing under `apps/web-platform`.
3. Guard-2 absence assertion re-anchored from the bare word `bash`
   (false-fails on legitimate prose) to the fenced-```bash-block form.
4. `support-directive.test.ts:28`'s stale title (`"kb-search shells
   out"`) added to the reality-sweep — the falsified premise lived in a
   test name, not only comments.
5. Rule-id citations verified against `AGENTS.md`/migrated-rule registry;
   `cq-ref-removal-sweep` corrected to `cq-ref-removal-sweep-cleanup-
   closures`; `#3252`/`#6121` re-classified as issues (verified live via
   `gh`), not PRs.

### New Considerations Discovered

- `git branch -r <name>`: `-r` with a positional arg is denied-or-error
  on modern git either way; retained in the flag set because bare `-r` is
  a common read — residual risk documented as accepted.
- `deny-support-bash` decision slug verified verbatim at
  `support-escalation.ts:118`; `support_handoff` SSE frame name verified
  at `support-escalation.ts:6`.

## Overview

Two defects deferred from PR #9540's security review (issue #9539) ship in one
focused PR:

- **#9555** — `apps/web-platform/server/safe-bash.ts:131` admits
  `^git\s+branch(?:\s+PATH_TOKEN)*$`, so `git branch <name>` (create),
  `git branch -d|-D <name>` (delete), `git branch -m` (rename), `-c`/`-C`
  (copy), `-u`/`--set-upstream-to`/`--unset-upstream` (config write),
  `-f`/`--force`, `-q` (quiet-create), and `--edit-description` all
  auto-approve as "read-only" at the canUseTool boundary. Measured live:
  `bun -e` against the module returns `isBashCommandSafe("git branch -d
  foo") === true` on this branch. Suspected mechanism behind the stray empty
  `feat-one-shot-prospects-fullscreen-page` branch in the #9539 incident.
- **#9559** — `kb-search` is the single skill loaded for the support persona
  (`SUPPORT_SKILL_ALLOWLIST = {"kb-search"}`), but every shell-out its
  SKILL.md instructs — `git grep -ilE`, `grep -Fxq`, `bash
  scripts/ensure-kb-index.sh --soft`, `bash "${CLAUDE_PLUGIN_ROOT}/…/
  kb-search-cache.sh"` — fails `SAFE_BASH_PATTERNS` /
  `EXACT_LITERAL_SAFE_COMMANDS` (`git grep` is not an allowlisted git verb;
  `grep` and bare `bash <script>` are deliberately excluded; `$`/`\b`/quotes
  trip `SHELL_METACHAR_DENYLIST` before any pattern runs). On a support turn
  a denied Bash call records an escalation (`denySupport` →
  `recordSupportEscalation`), and the route emits a `support_handoff` SSE
  frame at the terminal boundary — a "hand this to an agent" affordance on a
  pure app-help question. The affordance misfires on its main use case.

The fix for #9559 is **option (b)**: a support-persona execution path in
kb-search that uses Read/Grep/Glob tools only. The curated product-help
corpus is committed at `plugins/soleur/knowledge-base/` (INDEX.md,
kb-tags.txt, kb-categories.txt, `project/learnings/*.md` — 16 tracked
files), and ADR-113 already routes support `cwd` + file-tool containment +
sandbox to `pluginPath` with Read/Grep/Glob/LS auto-approved for support —
the infrastructure for the tool-only path exists; only the skill text still
instructs Bash.

## Problem Statement / Motivation

- #9555: a write-shaped command passing the read-only auto-approve gate is a
  misclassification on the **Command-Center hot path** (support-side writes
  were already blocked by `allowWrite: []` at the sandbox FS layer — the
  archived #9539 plan's "Related findings" entry). Every `git branch -d`/`-m`
  /create on an interactive CC turn executes with no review-gate.
- #9559: the ONLY sanctioned support capability is dead on its documented
  path, and its failure mode is the user-facing handoff affordance — the
  worst shape: a confident-looking "this needs an agent" escalation on a
  question the persona exists to answer.
- Bundling rationale: both are small, both are the same deferred batch from
  the same PR's review, and #9555's tightening *helps* the support path —
  after it lands, a support turn emitting `git branch -d` denies+escalates
  (correct: an engineering attempt) instead of auto-approving a doomed write.

## Proposed Solution

### Fix A — `git branch` read-only arms (#9555)

Replace the single `git branch` entry at `safe-bash.ts:131` with a closed
read-only flag set, split into two patterns so positional args require a
list-mode flag:

```ts
// git branch — READ-ONLY forms only (#9555). A bare positional arg CREATES a
// branch; -d/-D delete, -m/-M rename, -c/-C copy, -u/--set-upstream-to and
// --unset-upstream write config, -f/--force overwrites, --edit-description
// writes. -q/--quiet is EXCLUDED from the flag set: `git branch -q <name>`
// still creates silently (a one-keystroke repair of a refused write —
// cf. learning 2026-09-24-every-refusal-i-added-…). All such forms fall
// through to the review-gate. Positional args require ≥1 list-mode flag
// (they are pattern/commit-ish filters then) and must not start with `-`
// (a branch name can't), so a write flag cannot launder in as a pattern
// arg; `*` is outside PATH_TOKEN so only literal prefixes pass.
const GIT_BRANCH_READ_FLAG = String.raw`(?:--list|--show-current|--all|--remotes|--verbose|-[arv]+|--contains|--merged|--no-merged|--points-at|--sort=${PATH_TOKEN}|--format=${PATH_TOKEN}|--abbrev(?:=\d+)?|--column|--no-column|--color(?:=${PATH_TOKEN})?|--no-color|--ignore-case)`;
// Arm 1: bare `git branch` or flag-only forms (incl. --show-current).
new RegExp(String.raw`^git\s+branch(?:\s+${GIT_BRANCH_READ_FLAG})*\s*$`),
// Arm 2: ≥1 list-mode flag, then any mix of flags and non-dash args.
new RegExp(String.raw`^git\s+branch\s+${GIT_BRANCH_READ_FLAG}(?:\s+(?:${GIT_BRANCH_READ_FLAG}|(?!-)${PATH_TOKEN}))*\s*$`),
```

Semantics (the contract the tests pin):

- **Allow:** `git branch`, `git branch -a`, `-r`, `-v`, `-vv`, `-av`,
  `--list`, `--list feat`, `--show-current`, `--merged main`,
  `--contains HEAD~2`, `--no-merged main`, `--points-at HEAD`,
  `--sort=-committerdate`, `--ignore-case --list x`, combinations thereof.
- **Deny (→ review-gate on CC, deny+escalate on support):** `git branch
  foo`, `git branch foo main`, `-d`/`-D`/`--delete`, `-m`/`-M`/`--move`,
  `-c`/`-C`/`--copy`, `-f`/`--force`, `-q`, `-u`/`--set-upstream-to`,
  `--unset-upstream`, `--edit-description`, `git branch --list -d`,
  `git branch --list foo -D`, `git branch --list ../x` (traversal denylist),
  and `git branch -d x` as an `&&` segment (`git status && git branch -d
  x`).
- **Known conservative denials (accepted):** `--format=%(refname:short)`
  (parens outside `PATH_TOKEN`), `git branch foo --list` (flag not
  leading). These hit the review-gate — mildly annoying, never unsafe.
- The FLAG↔arg alternation is non-overlapping on first byte (flags start
  with `-`, args reject it) — same single-branch linear-shape rule the
  #4868 ReDoS review established for the git verbs above it.
- Consumer sweep (per `hr-write-boundary-sentinel-sweep-all-write-sites`):
  `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` runs
  `git branch -D`/`--merged` *inside* a script — the allowlist judges the
  outer `bash <script>` command, unaffected. `fix-issue/SKILL.md:275`
  instructs `git branch -D bot-fix-<N>-<SLUG>` — under CC that now reaches
  the review-gate instead of silently auto-approving; the intended effect.
  `git branch --show-current` (used by plan/compound/git-worktree skills)
  stays auto-approved via Arm 1.

### Fix B — kb-search support-persona tool path (#9559, option b)

`plugins/soleur/skills/kb-search/SKILL.md` gains a support-persona section
placed **at the top of `## Execution`** (before Phase 0 — first thing an
executing agent reads after parsing intent), gated on an observable cue:

> **Support-persona path (no Bash).** If you are running as the **Soleur
> Support** persona — your system prompt identifies you as "Soleur Support"
> and `kb-search` is your only loaded skill — do NOT execute any of the
> `bash`/` ```bash ` blocks in the phases below. On the support surface
> every non-safe-bash Bash call is denied AND records a support escalation
> that renders a false "Ask an agent" handoff at turn end. The corpus is
> already on disk under the session cwd: `knowledge-base/INDEX.md`,
> `knowledge-base/kb-tags.txt`, `knowledge-base/kb-categories.txt`, and
> `knowledge-base/project/learnings/*.md` are committed inside the deployed
> plugin root (all `knowledge-base/…` paths in the support section are
> relative to the support session cwd = plugin root, i.e.
> `plugins/soleur/knowledge-base/` at repo root — not the operator KB,
> which `denyReadExtra` obscures) — there is no index generator to run
> there (the `--soft`
> ensure call is for operator checkouts; skip it silently). If a Bash call
> IS denied with a read-only app-help message, do not retry Bash — switch
> to this path.
>
> | Phase | Tool-path equivalent |
> |---|---|
> | 0 arg parse | unchanged — pure in-context |
> | 1 facet validation | Read `knowledge-base/kb-tags.txt` and/or `kb-categories.txt`; match the flag value case-insensitively as a WHOLE LINE (fixed-string semantics — do not reproduce the `\\b` regex, see #8473); on miss emit the same `No matches. Valid values: …` output |
> | 2 facet filter | Glob `knowledge-base/project/learnings/*.md`, then Read each file's frontmatter (the corpus is ~a dozen files) or Grep `^tags:`/`^category:` lines; AND-combine flags as today |
> | 2.5 paraphrase | still runs inline (Option C is agent-inline); SKIP both `kb-search-cache.sh` calls — the cache needs a write the read-only support sandbox cannot do |
> | 3 keyword search | Tier 1: Grep `knowledge-base/INDEX.md` for the keyword, keep only links rooted at `knowledge-base/project/learnings/` (cap 8); Tier 2: Grep content under `knowledge-base/project/learnings/` excluding `archive/` (cap 12). Same dedupe-by-path merge |
> | 4 display | unchanged |

Supporting doc/comment edits (reality-sweep, per
`cq-ref-removal-sweep-cleanup-closures`):

- `apps/web-platform/server/support-directive.ts` — add one line to
  `SUPPORT_SYSTEM_DIRECTIVE`: kb-search runs through Read/Grep/Glob — no
  shell in this chat (reinforcement at the trusted system-prompt channel);
  fix the stale comments at :16-17 and :51-52 ("Bash is KEPT because
  kb-search shells out via the read-only safe-bash gate") — the support
  path is now tool-only; Bash stays out of `SUPPORT_EXTRA_DISALLOWED_TOOLS`
  (pinned by `support-directive.test.ts:32`) so read-shaped commands still
  pass safe-bash and engineering-shaped attempts still deny+escalate.
- `apps/web-platform/server/cc-dispatcher.ts:~2879` — same stale "kb-search
  shells out" comment → tool-only.
- `apps/web-platform/test/support-directive.test.ts:28` — the test TITLE
  itself embeds the falsified premise: `"extra-disallowed pins the
  write/fan-out surface but KEEPS Bash (kb-search shells out)"` — rename
  the parenthetical to the tool-only framing (the `.not.toContain("Bash")`
  assertion at :32 stays unchanged).
- ADR-113 — Decision item 5(c) says "Bash KEPT — kb-search shells out
  behind the read-only safe-bash gate"; append an amendment noting the
  premise was falsified (#9559): the allowlist never admitted those
  commands, and the support path is Read/Grep/Glob-only.
- `plugins/soleur/skills/kb-search/SKILL.md` — the
  `<!-- stage-2-paraphrase-union-v1 -->` block and the
  `SENSITIVE_QUERY_REGEX` literal MUST stay byte-identical
  (`plugins/soleur/test/kb-search-lockstep.test.sh` asserts byte-equality
  with `scripts/learning-retrieval-bench.sh`).

**Rejected options (from the issue's menu):**

- **(a) support-scoped safe-bash allowlist for kb-search commands** —
  rejected: `grep` is deliberately excluded (`-exec` shells out —
  `safe-bash.ts:39-41`); `bash <script> <model-controlled-arg>` is a new
  arg-bearing injection surface the EXACT_LITERAL set was designed to
  avoid; and the skill's command text itself (`$VAR`, `\b`, quotes) trips
  `SHELL_METACHAR_DENYLIST` *before* any allowlist runs, so (a) also forces
  rewriting every command — strictly heavier than (b) for the same
  property.
- **(c) suppress the escalation record on kb-search-attributable denies** —
  rejected: the Bash call is still denied, so the capability stays dead;
  it only silences the signal and turns the false-positive into an
  invisible dead end.
- **Remove Bash from the support toolset** — rejected: pinned by
  `support-directive.test.ts` (`not.toContain("Bash")`); a schema-removed
  Bash emitted anyway still lands on the generic support deny arm
  (`permission-callback.ts:1226`) which records the same escalation — buys
  nothing over (b).

## Technical Considerations

- **Hot path:** `isBashCommandSafe` runs per Bash call before the
  review-gate; the two `git branch` arms keep the single non-overlapping
  alternation rule (one branch = linear, no `~2^n` backtracking —
  `safe-bash.ts:117-126` documents the PR #4868 ReDoS fix this must not
  regress).
- **Support containment verified:** for `persona:"support"`,
  `agentWorkspacePath = pluginPath` (`cc-dispatcher.ts:2586`) and file-tool
  containment targets it (`cc-dispatcher.ts:2909`), so Read/Grep/Glob under
  `plugins/soleur/knowledge-base/` pass `isPathInWorkspace`;
  `denyReadExtra` obscures only the *operator* KB
  (`<root>/knowledge-base`), not the deployed corpus
  (`agent-runner-query-options.ts:~230`); `allowedTools` auto-approves
  Read/Glob/Grep/LS for support (`cc-dispatcher.ts:2860-2868`).
- **Deployed corpus is committed, not generated:** under the plugin root
  `scripts/ensure-kb-index.sh` does not exist (`plugins/soleur/scripts/`
  has no such file), so Phase 1's regeneration is a no-op there even before
  the deny — the committed INDEX/tags/categories ARE the index for the
  support corpus (ADR-235's untracked-cache caveat applies to the operator
  checkout, not the deployed tree).
- **`git grep` would also fail for a second reason:** the deployed plugin
  root is not a git worktree — the tool path is not just policy-compliant,
  it is the only path that works there.
- **Residual risk (documented, accepted):** a support model that ignores
  the section and still emits the bash forms gets denied+escalated — same
  as today; the fix reduces the false-positive surface to model
  non-compliance, it cannot remove it. The directive line + section
  placement + deny-fallback instruction are the three mitigations.
- **NFR:** no performance/security NFR register entries change; the regex
  stays linear-time.

### Attack Surface Enumeration

All paths where a write-shaped `git branch` could still reach auto-approve
after Fix A:

- `&&` decomposition — each segment re-checked; `git branch -d x` in any
  segment position denies the whole command. Checked.
- Trailing `2>/dev/null` / `2>&1` strip — orthogonal, runs before patterns;
  cannot convert a write form into a match (the stripped command still must
  match an arm). Checked.
- `EXACT_LITERAL_SAFE_COMMANDS` — closed set of two `worktree-manager.sh`
  literals; does not intersect `git branch`. Unchanged.
- `FILE_WRITE_FLAG_DENYLIST` (`--output`) — unrelated to `git branch`
  (no `--output` on branch); unchanged.
- `isBashCommandBlocked` (blocklist) — runs before safe-bash on the raw
  command; unchanged.
- Support persona `denySupport` short-circuit — tightened forms now deny+
  escalate on support instead of executing a doomed write inside
  `allowWrite:[]`. Improvement, not regression.
- Autonomous CC workspaces (`deps.bashAutonomous`) — non-safe commands
  auto-allow there by design; the misclassification mattered most on
  interactive CC (silent auto-approve) and support (doomed write). The fix
  does not alter the autonomous contract.
- **Not a gap:** other git verbs (`log`, `diff`, `show`, `rev-parse`,
  `status`, `config --get`) reviewed — all read-only verbs; `git config` is
  pinned to `--get` only. No sibling write-hole in scope.

## User-Brand Impact

- **If this lands broken, the user experiences:** the support bubble still
  dead-ending a help question into "Ask an agent" (status quo ante — the
  bug persists rather than worsens), or a Command-Center turn spuriously
  prompting a review-gate on a legitimate `git branch --list` read.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  no new exposure — the diff narrows an auto-approve boundary and adds a
  read-tool execution path; nothing new is permitted.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** both fixes are deny-side or
  docs-side; the worst degraded outcome is a spurious gate round-trip or a
  persisted status-quo bug, not a wrong mutation or data exposure — `none`
  matches the archived #9539 plan's precedent on the same subsystem.
- *Scope-out override:* `threshold: none, reason: the diff touches
  apps/web-platform/server/ (a sensitive path) but only to RESTRICT an
  allowlist — a wrong outcome over-denies to the review-gate, it cannot
  widen what auto-approves beyond status quo.`

## Observability

```yaml
liveness_signal:
  what: "Structured permission-decision lines: `deny-support-bash` (denySupport) and `canUseTool-support-bash` denies on support conversations; `auto-approved-safe-bash` allow lines on CC"
  cadence: per-event (each denied/allowed Bash call)
  alert_target: "Better Stack log query on `decision=deny-support-bash` rate — a support persona emitting kb-search shell-outs post-fix is the anomaly"
  configured_in: apps/web-platform/server/support-escalation.ts (denySupport) + apps/web-platform/server/permission-log.ts (existing sinks — no new instrumentation)
error_reporting:
  destination: "pino child logger `permission` → existing log pipeline (Better Stack); permission-decision rows via logPermissionDecision"
  fail_loud: "`deny-support-bash` log lines carrying detail=<command> on support turns post-deploy mean the skill text still reaches for Bash"
failure_modes:
  - mode: "git-branch arm regression re-admits a write form (e.g. PATH_TOKEN tail re-added)"
    detection: "safe-bash.test.ts git-branch battery fails in CI before merge"
    alert_route: "CI red on the PR — never reaches production"
  - mode: "support turn still shelling out (model ignores the tool path)"
    detection: "`deny-support-bash`/`canUseTool-support-bash` decision lines on support conversations persist post-deploy"
    alert_route: "Better Stack log query (operator review cadence)"
  - mode: "deployed corpus moved/renamed (plugins/soleur/knowledge-base/) so the tool path finds nothing"
    detection: "plugins/soleur/test/kb-search-support-path.test.sh corpus-presence assertion fails pre-merge; runtime reads degrade to honest 'no matches'"
    alert_route: "CI red on the PR"
logs:
  where: "stdout pino (`permission` child) + permission-decision ledger"
  retention: "existing Better Stack retention"
discoverability_test:
  command: rg -l -e GIT_BRANCH_READ_FLAG -e Support-persona apps/web-platform/server/safe-bash.ts plugins/soleur/skills/kb-search/SKILL.md
  expected_output: "safe-bash.ts SKILL.md"
  # No `|`/`;`/`&`/`<`/`>`/`$`/backtick anywhere in command — Check 10's
  # shell-active reject is byte-level, so `-e` patterns instead of an
  # alternation. `-l` prints each file matching EITHER pattern; the markers
  # are file-specific, so both paths in stdout iff each carries its marker.
```

## Architecture Decision (ADR/C4)

### ADR

- **Amend `ADR-113` (in-scope task, not a follow-up issue):** Decision item
  5(c) records "Bash KEPT — kb-search shells out behind the read-only
  safe-bash gate". That premise is falsified by #9559 — the allowlist never
  admitted the skill's commands. Add an amendment note to the `## Decision`
  / `## ADR-070 reconciliation` area: support kb-search executes via
  Read/Grep/Glob tools (auto-approved read surface), Bash stays allowed as
  the deny+escalation tripwire for engineering-shaped attempts. This is a
  premise correction on an existing ADR, not a new decision — no new ADR.
- **ADR-093/ADR-235 cross-checks done:** cwd=pluginPath reads are the
  designed mechanism (ADR-093); ADR-235's untracked facet caches do not
  apply inside the deployed plugin tree where the corpus files are
  committed.

### C4 views

Completeness enumeration per the Phase 2.10 mandate (all three model files
read): the change introduces no new container, data store, or external
system — the plugin corpus (`platform.plugin.kb`), the webapp API/dash­board
containers, and the founder actor are already modeled. **One gap found:**
the support-chat **end user** — the external human actor whose "how do I…"
questions this feature exists to serve — has no actor element (`founder`
is a workspace Owner; `betaContact`/`emailSender`/`contributor`/
`publicReader` are unrelated). The support surface shipped under ADR-113
without a model entry.

- **Task:** add `supportUser = actor "End User (Support Chat)"` with
  `#external` + `supportUser -> platform.webapp "asks app-help questions via
  the support bubble"` edge in `model.c4`, and add `supportUser` to the
  `view context` include list in `views.c4` (both edge endpoints must be
  in-view or the edge does not render — the #7332 rule cited in views.c4).
- **Validation:** `apps/web-platform/test/c4-code-syntax.test.ts` +
  `c4-render.test.ts` must pass.

### Sequencing

No ordering constraint — the ADR amend and C4 edit land in the same PR as
the code/doc fix.

## Guard Contract

### Guard 1 — git-branch read-only arms (vitest battery)

**Property.** `isBashCommandSafe` returns true for a `git branch` segment
iff every post-`branch` token is either a member of the closed read-only
flag set, or (reachable only after ≥1 list-mode flag) a non-dash
pattern/commit-ish arg — every create/delete/rename/copy/upstream/force/
quiet/describe form returns false.

**Assembly.** The `git\s+branch`-matching entries of `SAFE_BASH_PATTERNS`
in `apps/web-platform/server/safe-bash.ts` — the single chokepoint every
Bash segment flows through (`isSafeSingleSegment` stage 2, called by
`isBashCommandSafe` per `&&` segment). The test battery lives in
`apps/web-platform/test/safe-bash.test.ts` + the not-auto-approved list in
`permission-callback-safe-bash.test.ts`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `(?:\s+${PATH_TOKEN})*` tail to the branch arm (the original defect) | RED — `git branch -d foo` must be false |
| 2 | Add `d` to the short-flag class (`-[arvd]+`) | RED — `git branch -d foo` false |
| 3 | Add `q` to the short-flag class (quiet is a write modifier, not list-mode) | RED — `git branch -q foo` false |
| 4 | Drop the leading-flag requirement from Arm 2 (positional args always allowed) | RED — `git branch foo` (create) false |
| 5 | Remove the `(?!-)` lookahead on args | RED — `git branch --list -d` false |
| 6 | Empty the flag set / delete both arms | RED — `git branch --show-current` / `git branch` must be true (guard-own-dispatch row: a battery asserting only negatives passes vacuously) |
| 7 | must-PASS non-canonical input: `git branch --no-merged main` and `git branch -av` | PASS rows — prove the arm isn't deny-everything |
| 8 | `git status && git branch -d x` chained | RED — per-segment re-check holds across `&&` decomposition |

**Anchor.** Behavioral suite, not a stored-value comparison — the RED rows
land in the same diff as the regex, so the contract is that the plan's
matrix is written BEFORE the regex and each row is exercised as a named
test case; consistency-only risk is bounded by `litmus: git branch -d foo`
being the incident-derived case a reviewer cannot miss.

### Guard 2 — kb-search support-path presence (shell drift test)

**Property.** `plugins/soleur/skills/kb-search/SKILL.md` documents a
Bash-free support-persona execution path, and the corpus that path reads
(`plugins/soleur/knowledge-base/`) exists committed.

**Assembly.** New `plugins/soleur/test/kb-search-support-path.test.sh`
(auto-discovered by `scripts/test-all.sh` via the `plugins/soleur/test/
*.test.sh` glob at test-all.sh:97): asserts (i) the SKILL.md
support-persona marker/section exists, (ii) the support section contains
no ` ```bash ` fenced block and no line instructing a shell call (an
absence grep on the bare word `bash` would false-fail — the section
legitimately names Bash in prose; anchor on the fenced-block form),
(iii) INDEX.md + kb-tags.txt + kb-categories.txt exist non-empty. Pair
with the existing `kb-search-lockstep.test.sh` (sensitive-regex
byte-equality — must stay green through the edit). Per the
`*.test.sh` sharp edge: the script's owning EXIT trap goes BEFORE
`source test-helpers.sh`, and every negative row carries a positive
control on the same input.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the support-persona section from SKILL.md | RED — marker assertion fails |
| 2 | Insert a fenced ` ```bash ` block inside the support section | RED — no-bash-block assertion fails (section-prose can name `bash` legitimately — the assertion targets the fenced/invocation form) |
| 3 | Remove/rename `plugins/soleur/knowledge-base/INDEX.md` | RED — corpus assertion fails |
| 4 | Empty the test's assertion list (guard-own-dispatch) | RED — script asserts a pass-count floor ≥3 before exiting 0 |
| 5 | must-PASS non-canonical: a 14th learning added to the corpus | PASS — presence checks, not an enumeration |

**Anchor.** The test asserts content + filesystem state in one commit;
there is no stored hash to drift. A diff that weakens both SKILL.md and
the test is bounded by the marker contract being named in the plan and in
the test's own header comment.

## Research Insights

- **Relevant files:**
  `apps/web-platform/server/safe-bash.ts` (allowlist, PATH_TOKEN at :77,
  git verbs at :127-134, `git branch` at :131; `EXACT_LITERAL_SAFE_COMMANDS`
  :164-167; `isSafeSingleSegment` stages :236-264),
  `apps/web-platform/server/permission-callback.ts` (support Bash deny
  :581-599; Skill allowlist :1048+; generic support deny :1226;
  `SUPPORT_BASH_DENY_MESSAGE` :73),
  `apps/web-platform/server/support-escalation.ts` (record/consume/clear
  registry),
  `apps/web-platform/server/support-directive.ts` (`SUPPORT_SKILL_ALLOWLIST`
  :33, `SUPPORT_EXTRA_DISALLOWED_TOOLS` :70-80 — Bash deliberately absent,
  directive text :102-110),
  `apps/web-platform/server/cc-dispatcher.ts` (`agentWorkspacePath =
  pluginPath` :2586; allowedTools support filter :2860-2868; stale
  "kb-search shells out" comment ~:2879; skills pin :2888),
  `apps/web-platform/server/agent-runner-query-options.ts`
  (cwd/sandbox/denyReadExtra derivation :215-245),
  `plugins/soleur/skills/kb-search/SKILL.md` (Phase 1 `git grep`/`grep
  -Fxq`/`ensure-kb-index.sh` :61-104; Phase 2.5 cache script :149-161;
  Phase 3 tier greps :177-183),
  `plugins/soleur/knowledge-base/` (committed support corpus: INDEX.md,
  kb-tags.txt, kb-categories.txt, 13 learnings),
  tests: `apps/web-platform/test/safe-bash.test.ts`,
  `permission-callback-safe-bash.test.ts`,
  `support-directive.test.ts` (pins `!contains("Bash")` :32),
  `plugins/soleur/test/kb-search-lockstep.test.sh` (byte-equality on the
  sensitive-regex block),
  `scripts/test-all.sh` (auto-discovers `plugins/soleur/test/*.test.sh` :97).
- **Premise validation (Phase 0.6):** all cited artifacts verified on this
  branch — `safe-bash.ts:131` pattern present and confirmed live via `bun
  -e` (`git branch -d foo` → `true`); kb-search SKILL.md instructs all four
  non-allowlisted shell-outs; PR #9540 MERGED 2026-10-05; #9539 CLOSED;
  #3820 OPEN (extend-allowlist — complementary, not conflicting); ADR
  corpus grepped for the mechanism — ADR-113 is the governing decision and
  contains the falsified premise this plan amends; no ADR rejects option
  (b). Archived #9539 plan
  (`plans/archive/20261005-182039-…-support-persona-write-dead-end-plan.md`)
  documents the deferral and the sandbox-FS backstop.
- **Institutional learnings applied:**
  `2026-05-05-cc-permissions-bash-allowlist-hardening` (PATH_TOKEN + `(?!-)`
  lookahead precedent reused verbatim),
  `2026-10-05-a-boundary-claim-must-enumerate-every-path-to-the-frame…`
  (finding 6 is literally #9559; the attack-surface enumeration above is
  shaped by its enumerate-every-path rule),
  `2026-09-24-every-refusal-i-added-had-a-one-keystroke-repair…` (why `-q`
  is excluded — quiet modifies creates, it is not a list flag),
  `2026-04-29-u2028-in-typescript-regex-breaks-esbuild` (regex authored
  via `String.raw` escapes, no literal Unicode).
- **Property List (Phase 0.6b):**
  (P1) `git branch` create/delete/rename/copy/upstream/force/quiet/
  describe forms never auto-approve;
  (P2) `git branch` list/read forms keep auto-approving;
  (P3) a support turn running the sanctioned kb-search flow completes
  without a Bash deny, so no false escalation/handoff;
  (P4) deny+escalation remains intact for genuinely out-of-scope support
  Bash attempts;
  (P5) no new persona plumbing — reuse the committed corpus and the
  already-auto-approved Read/Grep/Glob surface.
- **Cut List (Phase 0.6b):**
  option (a) support-scoped allowlist → P3 — cut (grep `-exec` exclusion +
  metachar denylist ordering + arg-bearing `bash` injection surface make it
  strictly heavier than (b));
  option (c) suppress escalation → buys silence not P3 — cut;
  remove Bash from support toolset → cut (pinned by test, no gain);
  new `support-kb-search` skill → cut (allowlist is `{kb-search}`; a second
  skill doubles corpus surface for zero property gain);
  `git branch` positional args always allowed → cut (reintroduces create).
- **Harness limitation disclosure:** this planning session runs as a Devin
  subagent with no Task/Workflow spawn surface — Phase 1 research agents,
  domain-leader fan-out, spec-flow, advisor consult, and plan-review panel
  were executed as inline orchestrator analysis instead of subagent spawns.
  Findings below reflect that substitution.

## Open Code-Review Overlap

- **#3820** (extends the same allowlist with grep/find/rg/sort/uniq):
  **acknowledge** — orthogonal axis (extension vs tightening); whichever
  lands second rebases the `git branch` region. Do NOT fold in — the issue
  explicitly scopes #3820 as distinct.
- **#8473** (`kb-search --tag` `\b` misses 11 tags): **acknowledge** —
  adjacent code region (Phase 1 facet validation); the support tool path
  deliberately uses whole-line fixed-string matching and does not replicate
  the `\b` semantics, but fixing #8473's engineering-path bug is out of
  scope.
- **#9558** (support dispatch mints GH_TOKEN/egress ungated): **defer** —
  adjacent support-persona surface, different files (cc-dispatcher
  credential path); keep on its own cycle.
- **#5641** (agent-native KB read/search tool): **acknowledge** — if it
  lands later it supersedes this plumbing; the tool-only support path is
  compatible either way.

## Files to Edit

- `apps/web-platform/server/safe-bash.ts` — replace the `git branch` entry
  (:131) with `GIT_BRANCH_READ_FLAG` + the two arms; comment block per
  Fix A.
- `apps/web-platform/test/safe-bash.test.ts` — new `describe` for the
  git-branch arms (allow list + deny list incl. `&&` chain and `-q`).
- `apps/web-platform/test/permission-callback-safe-bash.test.ts` — add
  `git branch -d x` / `git branch feat-x` to the not-auto-approved (falls
  through to review-gate) cases; keep `"git branch"` in SAFE_COMMANDS.
- `plugins/soleur/skills/kb-search/SKILL.md` — add the support-persona
  execution-path section at the top of `## Execution`; keep the
  `stage-2-paraphrase-union-v1` marker + `SENSITIVE_QUERY_REGEX` block
  byte-identical.
- `apps/web-platform/server/support-directive.ts` — one directive line
  (kb-search is tool-only, no shell) + fix the two stale "shells out via
  safe-bash" comments (:16-17, :51-52).
- `apps/web-platform/server/cc-dispatcher.ts` — fix the stale "kb-search
  shells out" comment (~:2879).
- `knowledge-base/engineering/architecture/decisions/ADR-113-…md` —
  amendment note correcting the 5(c) premise.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — add
  `supportUser` actor + edge.
- `knowledge-base/engineering/architecture/diagrams/views.c4` — add
  `supportUser` to `view context` include.
- `apps/web-platform/test/support-directive.test.ts` — extend directive
  assertions to pin the new tool-path sentence (e.g. matches
  `/Read.*Grep.*Glob|no shell/i`), rename the stale test title at :28,
  keep all existing assertions.

## Files to Create

- `plugins/soleur/test/kb-search-support-path.test.sh` — Guard 2 drift
  test (auto-discovered by `scripts/test-all.sh`).

## Implementation Phases

1. **Fix A + tests (failing first):** add the deny/allow battery to
   `safe-bash.test.ts` + `permission-callback-safe-bash.test.ts` FIRST
   (red), then swap the `git branch` pattern in `safe-bash.ts` (green).
   `cq-write-failing-tests-before`.
2. **Fix B + directive + comments:** SKILL.md support section, directive
   line, comment fixes in `support-directive.ts`/`cc-dispatcher.ts`,
   `support-directive.test.ts` assertion additions.
3. **Guard 2 test:** `kb-search-support-path.test.sh`.
4. **ADR-113 amendment + C4 model/view update** (+ run c4 tests).
5. **Verify:** `cd apps/web-platform && ./node_modules/.bin/vitest run
   test/safe-bash.test.ts test/permission-callback-safe-bash.test.ts
   test/support-directive.test.ts test/c4-code-syntax.test.ts
   test/c4-render.test.ts` (the web-platform runner is **vitest** —
   `bunfig.toml` sets `pathIgnorePatterns = ["**"]` so `bun test` discovers
   nothing; vitest collects `test/**/*.test.ts`), plus `bash
   plugins/soleur/test/kb-search-lockstep.test.sh`, `bash
   plugins/soleur/test/kb-search-support-path.test.sh`, and the
   mutation-matrix spot-check (`cd apps/web-platform && bun -e 'import
   {isBashCommandSafe} from "./server/safe-bash.ts"; …'` — verified working
   on this branch 2026-10-06).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "tighten the entry to read-only forms (`git branch` bare / `--list` / `-v*` / `--show-current`) and move create/delete/rename to the review-gate path" [#9555] | Fix A / `safe-bash.ts` + tests / Phase 1 | mapped |
| 2 | "kb-search's documented shell-outs hit the support Bash deny — false-positive handoff on help questions … Fix options (pick one): (a)…(b)…(c)…" [#9559] | Fix B (option b chosen; a/c rejected with reasons in Proposed Solution) / `kb-search/SKILL.md` + `support-directive.ts` / Phase 2 | mapped |
| 3 | "This touches the hot path; keep the diff tight." [#9555] | single-pattern swap + comment; no refactor of neighboring entries | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `GIT_BRANCH_READ_FLAG` two-arm regex | "tighten the entry to read-only forms" | asked |
| safe-bash test battery additions | "move create/delete/rename to the review-gate path" (a moved-to-gate claim needs falsifying tests) | inferred — justification: deny-side claims are only verifiable by RED tests; `cq-write-failing-tests-before` |
| kb-search support-persona section | "a support-mode kb-search path that uses Read/Grep/Glob tools only" | asked |
| `SUPPORT_SYSTEM_DIRECTIVE` line + comment fixes | "the corpus is directly readable under cwd=pluginPath" | inferred — justification: the section alone depends on the model reading mid-doc; the trusted directive is the persona's highest-authority channel and the stale comments now lie about the mechanism |
| `kb-search-support-path.test.sh` | — | inferred — justification: drift guard or the contract rots (a future SKILL.md edit silently re-adds bash to the support path); corpus presence is the path's load-bearing precondition |
| ADR-113 amendment | — | inferred — justification: Phase 2.10 — the plan diverges from ADR-113's recorded 5(c) premise; decision records must not lag the change |
| C4 `supportUser` actor | — | inferred — justification: Phase 2.10 completeness mandate — the feature's external actor is unmodeled in all three .c4 files |
| `support-directive.test.ts` assertion | — | inferred — justification: pins the new directive sentence so a future edit can't silently drop the no-shell contract |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `plugins/soleur` (plus
  `knowledge-base/` docs artifacts)
- Planned files: 10 edited + 1 created | Estimated changed lines: ~350
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [x] AC1: `isBashCommandSafe` returns `false` for `git branch <name>`,
  `git branch -d <name>`, `-D`, `-m`, `-M`, `-c`, `-C`, `-f`, `-q`,
  `-u`/`--set-upstream-to`, `--unset-upstream`, and `--edit-description`
  forms, including as an `&&` segment.
- [x] AC2: `isBashCommandSafe` returns `true` for `git branch`,
  `git branch --show-current`, `git branch --list`, `git branch -a`,
  `-r`, `-v`, `-vv`, `--merged main`, `--contains HEAD~2`,
  `--sort=-committerdate`.
- [x] AC3: `kb-search` SKILL.md documents a support-persona execution path
  covering all four phases' tool equivalents, placed before Phase 0, that
  instructs NO Bash calls and names the committed corpus paths.
- [x] AC4: `plugins/soleur/test/kb-search-support-path.test.sh` exists,
  is discovered by `scripts/test-all.sh`, asserts the support section +
  corpus presence + no-bash-in-section, and carries a ≥3 pass-count floor.
- [x] AC5: `kb-search-lockstep.test.sh` stays green (sensitive-regex byte
  equality preserved).
- [x] AC6: `SUPPORT_SYSTEM_DIRECTIVE` tells the support model kb-search is
  tool-only (Read/Grep/Glob); stale "shells out via safe-bash" comments in
  `support-directive.ts` and `cc-dispatcher.ts` are corrected.
- [x] AC7: ADR-113 carries the premise-correction amendment; `model.c4` +
  `views.c4` include `supportUser` and `c4-code-syntax.test.ts` /
  `c4-render.test.ts` pass.
- [x] AC8: `safe-bash.test.ts`, `permission-callback-safe-bash.test.ts`,
  `support-directive.test.ts` all green; no other suite regresses
  (`git branch` bare stays in SAFE_COMMANDS).
- [x] AC9: PR body carries `Closes #9555` and `Closes #9559` plus a
  `## Changelog` section (semver: patch — bug fix).

## Domain Review

**Domains relevant:** Engineering, Support

### Engineering

**Status:** reviewed (orchestrator inline assessment — no Task-spawn
surface in this harness; the CTO-leader lens was applied by hand)
**Assessment:** Touches the canUseTool permission hot path and the
safe-bash allowlist grammar — the highest-review-burden file class in the
repo per its own header comments (ReDoS, traversal, injection history in
PR #4868; issues #3252/#6121). The two-arm flag-set design follows the established
`PATH_TOKEN` + `(?!-)` precedent; main risks are an over-broad flag
admitted (mitigated: closed set, all list-mode) and an under-covered write
form (mitigated: default is deny — unlisted flags fall through to the
gate). No new infrastructure, no new dependencies.

### Support

**Status:** reviewed (orchestrator inline assessment — same substitution)
**Assessment:** #9559 is literally the support persona's main use case.
Option (b) restores the sanctioned capability using the read tools already
auto-approved for support; the deny+escalation tripwire survives untouched
for real engineering attempts. Residual model-non-compliance risk is
documented and accepted. The stale "shells out" comments get corrected in
the same diff so the design record stops lying.

### Product/UX Gate

**Tier:** none — mechanical UI-surface scan of `## Files to Edit`/`Create`
against the ui-surface glob superset returns zero hits (server `.ts`,
SKILL.md, tests, `.c4`, ADR). No user-facing page/component/flow changes;
the support bubble's behavior change is a *removal* of a false affordance.

**Brainstorm-recommended specialists:** none (no brainstorm ran — one-shot
pipeline entry).

## Test Scenarios

- Given a support persona turn, when the model runs kb-search per the new
  section, then every corpus read flows through Read/Grep/Glob
  (auto-approved), zero `denySupport` calls occur, and no
  `support_handoff` frame is emitted at turn end. (Asserted indirectly:
  Guard 2 pins the doc contract; the deny path itself is unchanged code.)
- Given `git branch -d feat-x` on a Command-Center turn, when
  `isBashCommandSafe` runs, then it returns false and the command reaches
  the review-gate (or `denySupport` on support) — pinned by vitest.
- Given `git branch --list -d`, when parsed, then `-d` fails both the flag
  set and the `(?!-)` arg arm → denied.
- Given `git branch -q foo` (quiet-create), when parsed, then `-q` is not
  in the flag set → denied.
- Given `git status && git branch -D x`, when decomposed, then segment 2
  fails → whole command denied.
- Given a future edit re-adding `(?:\s+${PATH_TOKEN})*` to the branch arm,
  when the suite runs, then the deny battery goes RED (Guard 1 row 1).
- Given a future edit deleting the SKILL.md support section, when
  `kb-search-support-path.test.sh` runs, then RED (Guard 2 row 1).
- Given `SENSITIVE_QUERY_REGEX` text drift in SKILL.md, when
  `kb-search-lockstep.test.sh` runs, then it exits non-zero (existing).

## Success Metrics

- `isBashCommandSafe("git branch -d foo")` flips from `true` (measured
  baseline on this branch) to `false`; `git branch`/`--show-current`/`-a`
  stay `true`.
- Post-deploy: `deny-support-bash` log lines carrying kb-search-shaped
  commands (`git grep`, `kb-search-cache.sh`, `ensure-kb-index.sh`,
  `grep -F`) drop to ~0 on support conversations; `support_handoff` emits
  only on genuine out-of-scope attempts.

## Dependencies & Risks

- **Rebase risk with #3820** (extends the same array region): whichever
  lands second resolves a trivial textual conflict; the two are
  complementary.
- **Model non-compliance residual:** the support path is doc-gated; a model
  that still emits bash gets deny+escalate (status quo failure mode, not a
  new one).
- **Corpus drift:** if `plugins/soleur/knowledge-base/` is ever regenerated
  or moved, Guard 2 fails pre-merge; runtime failure mode is an honest
  "no matches" answer (already the skill's documented miss path).
- **Regex shape:** the two arms follow the non-overlapping-alternation rule
  from the #4868 ReDoS review; the deny battery is the regression pin.

## Sharp Edges

- A plan whose `## User-Brand Impact` section omits the threshold or the
  sensitive-path scope-out reason fails `deepen-plan` Phase 4.6 / preflight
  Check 6 — both are filled above (`none` + named reason).
- The `stage-2-paraphrase-union-v1` marker and `SENSITIVE_QUERY_REGEX`
  literal in SKILL.md are byte-pinned by `kb-search-lockstep.test.sh` —
  edits must not touch those lines.
- `git branch -q <name>` is a silent CREATE, not a list flag — `-q` is
  deliberately absent from `GIT_BRANCH_READ_FLAG`; do not "fix" the gap.
- Do not add `grep`/`find` to `SAFE_BASH_PATTERNS` in this PR — that is
  #3820's scope, and `grep -exec`/`-exec` is why they were excluded.
- `hr-when-in-a-worktree-never-read-from-bare`: all verification commands
  run inside this worktree.

## References & Research

- Issues: #9555, #9559 (this PR), #9539/#9540 (origin), #3820, #8473,
  #9558, #5641 (overlap dispositions above)
- `apps/web-platform/server/safe-bash.ts:56-283` — the two-stage regex
  contract (denylists → patterns), PATH_TOKEN/ECHO_TOKEN/GH_ARG shapes
- `apps/web-platform/server/permission-callback.ts:581-599` — support
  Bash deny arm; `:1048-1100` — Skill allowlist arm
- `apps/web-platform/server/cc-dispatcher.ts:2586,2860-2922` — support
  corpus path + tool surface wiring
- `knowledge-base/engineering/architecture/decisions/ADR-113-…md` —
  support-persona scope (Decision item 5 amended here)
- Learnings: `2026-10-05-a-boundary-claim-must-enumerate-every-path-…`
  (finding 6 = #9559), `2026-05-05-cc-permissions-bash-allowlist-…`,
  `2026-09-24-every-refusal-i-added-…`, `2026-04-29-u2028-…esbuild`
- Archived plan:
  `knowledge-base/project/plans/archive/20261005-182039-2026-10-05-fix-support-persona-write-dead-end-plan.md`
  (Related-findings deferral list this PR drains)
