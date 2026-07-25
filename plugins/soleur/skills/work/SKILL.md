---
name: work
description: "This skill should be used when executing work plans efficiently while maintaining quality and finishing features."
---

<!-- work-anti-bypass-protocol:start -->
## Anti-bypass protocol (load-bearing — especially Grok Build)

You are the **implementation orchestrator** for standalone `/work` and one-shot Step 3:

- **FORBIDDEN:** Pushing a branch and reporting "done" without `/review` → `/compound` → `/ship`.
- **FORBIDDEN:** Treating `## Work Phase Complete` as a turn boundary when you own the pipeline (see Invocation Mode below).
- **REQUIRED (Grok Build):** Invoke `/review`, `/compound`, `/ship` via slash commands — never hand-roll ship steps.
- **Deliverable:** merged PR (standalone) or return to parent one-shot (pipeline mode).

See `plugins/soleur/lib/workflow-fidelity.ts` (`IMPLEMENTATION_TAIL`) and Phase 4 Invocation Mode below.
<!-- work-anti-bypass-protocol:end -->

# Work Plan Execution Command

Execute a work plan efficiently while maintaining quality and finishing features.

## Introduction

This command takes a work document (plan, specification, or todo file) and executes it systematically. The focus is on **shipping complete features** by understanding requirements quickly, following existing patterns, and maintaining quality throughout.

## Headless Mode Detection

If `$ARGUMENTS` contains `--headless`, set `HEADLESS_MODE=true`. Strip `--headless` from `$ARGUMENTS` before processing the remainder as a plan path. Pipeline mode (file path detection) already covers all prompt bypasses for work's own prompts — `--headless` is only needed for forwarding to child skills in Phase 4.

## Input Document

<input_document> #$ARGUMENTS </input_document>

<decision_gate>
**API budget.** This skill executes a work plan iteratively across many phases. Tier A (Agent Teams) carries ~7x per-task token cost; Tier B (Subagent Fan-Out) is moderate; Tier C is single-agent. Total cost scales with plan length, chosen tier, and per-task RED/GREEN/REFACTOR cycles. Soleur does not bill or proxy these calls — Anthropic does, against the key in your session. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this loop against your own budget.

The tier offer fires inline at the right phase. Decline if running an unfamiliar plan against a tight budget.
</decision_gate>

## Execution Workflow

### Phase 0: Load Knowledge Base Context (if exists)

**Load project conventions:**

```bash
# Load project conventions
if [[ -f "CLAUDE.md" ]]; then
  cat CLAUDE.md
fi
```

**Clean up merged worktrees (silent, runs in background):**

Navigate to the repository root, then run `bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged`. Report cleanup results: how many worktrees were cleaned up, which branches remain active.

**Check for knowledge-base directory and load context:**

Check if `knowledge-base/` directory exists. If it does:

1. Run `git branch --show-current` to get the current branch name
2. If the branch starts with `feat-`, read `knowledge-base/project/specs/<branch-name>/tasks.md` if it exists

**If knowledge-base/ exists:**

1. Read `CLAUDE.md` if it exists - apply project conventions during implementation
2. If `# Project Constitution` heading is NOT already in context, read `knowledge-base/project/constitution.md` - apply principles during implementation. Skip if already loaded (e.g., from a preceding `/soleur:plan`).
3. Detect feature from current branch (`feat-<name>` pattern)
4. Read `knowledge-base/project/specs/feat-<name>/tasks.md` if it exists - use as work checklist alongside TodoWrite
4.5. Read `lane:` from spec.md if present. Guard file existence first:

   ```bash
   spec_path="knowledge-base/project/specs/feat-${branch_name}/spec.md"
   if [[ -f "$spec_path" ]]; then
     LANE=$(awk '/^lane:/ { gsub(/^lane:[[:space:]]*"?|"?$/, ""); print; exit }' "$spec_path")
     case "$LANE" in
       single-domain|cross-domain|procedural) ;;
       "") LANE="" ;;  # legacy spec; silent skip in announce
       *) echo "work: invalid lane value '$LANE' in spec; ignoring."; LANE="" ;;
     esac
   fi
   ```

   Lane is **non-binding in skill logic** — `work` code does not branch on `LANE`. Operators MAY use the announced lane as a heuristic when picking work Tier 0/A/B/C in Phase 2; binding behavior is deferred per Non-Goal #2.
5. Announce: `"Loaded constitution and tasks for \`feat-<name>\`"` — append `" (lane=<value>)"` when `LANE` is non-empty.

**If knowledge-base/ does NOT exist:**

- Continue with standard work flow (use input document only)

### Phase 0.5: Pre-Flight Checks

Run these checks before proceeding to Phase 1. A FAIL blocks execution with a remediation message. A WARN displays and continues. If all checks pass, proceed silently.

**Environment checks:**

1. Run `git branch --show-current`. If the result is empty (detached HEAD), FAIL: "Detached HEAD state -- checkout a feature branch or create a worktree." If the result is the default branch (main or master), FAIL: "On default branch -- create a worktree before starting work. Run: `bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh feature <name>`"
2. Run `pwd`. If the path does NOT contain `.worktrees/`, WARN: "Not in a worktree directory. You can create one via `git-worktree` skill in Phase 1."
3. Run `git status --short`. If output is non-empty, WARN: "Uncommitted changes detected. Consider committing or stashing before starting new work."
4. Probe for stashed changes WITHOUT invoking `git stash` (the `hr-never-git-stash-in-worktrees` hook denies even the read-only `git stash list`). Use `git rev-parse --verify --quiet refs/stash` — a zero exit means a stash exists; WARN: "Stashed changes found. Review stash list to avoid forgotten work." A non-zero exit means no stash; continue silently.

**Scope checks:**

5. If a plan file path was provided as input (ends in `.md` or starts with a path-like pattern), verify it exists and is readable. If not, FAIL: "Plan file not found at the specified path." If the input appears to be a text description rather than a file path, WARN: "Input appears to be a description, not a file path. Scope validation limited."
6. Run `git diff --name-only HEAD...origin/main` to identify files that diverged between this branch and main. If output is non-empty, WARN: "Branch has diverged from main in [N] files: [file list]. Consider merging main before starting." If the git command fails (e.g., offline, no remote), skip this check silently. **For plans that edit AGENTS.\* (high-collision file class), `plugins/soleur/skills/ship/SKILL.md` (Phase 5.5 gates), OR any path under `docs/legal/**` / `knowledge-base/legal/**` (legal-doc cross-document gate; weekly compliance PRs collide on the same 4-file set), FAIL HARD instead of WARN — fetch + rebase BEFORE Phase 1 (`git fetch origin main && git rebase origin/main`); sibling PRs landing mid-session reliably obsolete plan-quoted budget baselines and trim-target line numbers. Applying-then-rebasing duplicates sibling work and requires full reassessment.** See `knowledge-base/project/learnings/best-practices/2026-05-20-rebase-before-applying-agents-md-plan-edits.md` and `knowledge-base/project/learnings/2026-05-25-closed-field-list-must-classify-at-value-shape-not-column-name.md` §Session Errors #5 (PR #4351 — 10 commits behind including #4353 legal-doc lockstep; caught at review time, not Phase 0.5).
7. If a plan file was provided (check 5 passed), scan for a `## Domain Review` or `## UX Review` heading (both are accepted for backward compatibility). If NEITHER heading found: scan the plan content for UI file patterns (page.tsx, layout.tsx, template.tsx, .jsx, .vue, .svelte, .astro, +page.svelte, app/, pages/, components/, layouts/, routes/). If UI patterns found, WARN: "Plan references UI files but has no Domain Review section. Consider running /soleur:plan to add domain review before implementing." If either heading IS present: pass silently.

**Design artifact checks:**

8. Check if prior phases produced design artifacts. Search the repo for design files matching the feature name: `git ls-files '*.pen' '*.fig' '*.sketch' | grep -i "<feature-name>"` and check `knowledge-base/product/design/` for related files. If design artifacts exist AND the current tasks include UI/page implementation (patterns: `.njk`, `.html`, `.tsx`, `.jsx`, `.vue`, `.svelte`, `pages/`, `components/`, `layouts/`): store the artifact paths as `DESIGN_ARTIFACTS` for use in Phase 2.

**Specialist review checks:**

9. If a plan file was provided (check 5 passed) and a `## Domain Review` section exists with a `### Product/UX Gate` subsection: check whether domain leader assessments recommended specialists (copywriter, ux-design-lead, conversion-optimizer) that are NEITHER listed in `**Agents invoked:**` NOR in `**Skipped specialists:**`. If the `**Decision:**` field says `reviewed (partial)`, WARN: "Domain review was partial — some specialist agents failed. Review the Domain Review section before proceeding." If any recommended specialist is missing from both fields: **Interactive mode:** FAIL with message listing the missing specialists and options: (a) "Run \<specialist\> now" — invoke the specialist agent directly, update the plan file's `**Agents invoked:**` field, then continue; (b) "Skip with justification" — prompt for reason, add to the plan file's `**Skipped specialists:**` field, then continue. **Pipeline mode (headless/one-shot):** auto-invoke each missing specialist agent. If the agent succeeds, add to `**Agents invoked:**`. If it fails, add to `**Skipped specialists:**` with note `(auto-skipped — agent unavailable in pipeline)` and WARN. Do not FAIL in pipeline mode. If all recommended specialists are accounted for (in `**Agents invoked:**` or `**Skipped specialists:**`): pass silently.

   **UX-skip-on-UI-plan hard gate (within check 9):** Determine "UI plan" by matching the plan's `## Files to Create` AND `## Files to Edit` against the shared UI-surface term list + glob superset (`plugins/soleur/skills/brainstorm/references/ui-surface-terms.md`) — NOT just `*.tsx/*.jsx`. The superset includes `*.njk`, `*.html`, `*.vue`, `*.svelte`, `*.astro`, and email templates, so an Eleventy/Svelte/email UI surface does not slip the gate (`wg-ui-feature-requires-pen-wireframe`). On a UI plan, FAIL when EITHER: (a) `ux-design-lead` appears in `**Skipped specialists:**`, OR (b) the plan has **no `### Product/UX Gate` subsection at all** (the gate was never run). Message: "Plan touches a UI surface but has no committed `.pen` (ux-design-lead skipped or gate never ran). Invoke the specialist or provide an explicit override naming the specific UI surfaces being shipped without review." This overrides the "all accounted for → pass silently" branch. A documented skip — or absent gate — on a UI plan is a process gap, not process compliance. See `knowledge-base/project/learnings/workflow-patterns/2026-05-26-ux-design-review-skip-must-fail-hard-on-ui-plans.md`.

   **UX artifact commit checkpoint (after each specialist in check 9):** After each specialist agent completes successfully (interactive "Run specialist now" or pipeline auto-invoke), commit the output:

   1. Run `git status --short` to discover new/modified files from the specialist
   2. Stage specialist output files: `git add <discovered files>`
   3. Commit: `git commit -m "wip: <specialist-name> artifacts for <feature-name>"`

   Each specialist gets its own commit so partial progress is preserved if a later specialist fails. Do not commit on specialist failure.

**On FAIL:** Display the failure message with remediation steps and stop. Do not proceed to Phase 1.

**On WARN only:** Display all warnings together and proceed to Phase 1.

**On all pass:** Proceed silently to Phase 1.

### Phase 1: Quick Start

**Pipeline detection:** If `$ARGUMENTS` contains a file path (ends in `.md` or matches a path-like pattern), this skill is running in **pipeline mode** (invoked by one-shot or another orchestrator). In pipeline mode, skip all interactive approval gates and proceed directly. If `$ARGUMENTS` is empty or a plain text description, this is **interactive mode** — keep the approval gates below.

1. **Read Plan and Clarify**

   - Read the work document completely
   - Review any references or links provided in the plan
   - Before proceeding, verify the plan does not contradict conventions in AGENTS.md and constitution.md: file format (markdown tables not YAML), kebab-case naming, directory structure (agents recurse, skills flat), required frontmatter fields, shell script conventions
   - **Plan-quoted numbers are preconditions to verify, not facts.** When the plan quotes a current measurement (`bun test … reports X`, `wc -c < AGENTS.md = N`, "cumulative ~Y words; ~Z headroom", `git ls-files | wc -l`), re-run the measurement at /work start before depending on it. Plans authored hours-or-days earlier observe a moving target; parallel branches landing in `main` invalidate the measurement. PR #3501 plan claimed `~186 word headroom` against an actual `15` and required inline trim of the gate description. See `knowledge-base/project/learnings/2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`.
   - **A plan-quoted tool-flag VALUE/UNIT is a claim to verify against the PINNED tool's source/`--help` — the unit is the highest-risk part.** When the plan names a CLI/config flag value (`--postgres-conn-max-idle-time 30`, a timeout, a size, a percent), resolve the pinned version and read that version's flag registration for type + **unit** + default + validation before writing it — a wrong unit (minutes/seconds/ms, bytes/KB, count/%) passes typecheck AND the binary's own validation, so only the source catches it. The plan is authoritative for *intent* (e.g. "drain idle conns fast"), never the literal value. **Why:** #6258 — the plan's `SECS=30` for `--postgres-conn-max-idle-time` was seconds-intent, but the inngest v1.19.4 flag is an IntFlag in MINUTES (default 5) → `30` = 30 min, defeating the drain; corrected to `1`. See `knowledge-base/project/learnings/best-practices/2026-07-09-plan-quoted-tool-flag-value-and-unit-are-claims-verify-against-pinned-source.md`.
   - **Plan hypotheses about a symptom's mechanism (and its route/file classifications) are starting points, not the work-list — trace the ACTUAL producer before coding.** For a symptom-named bug (a 404, an empty state), grep the literal producer (`notFound()`, the `404` response, the empty-state component) and walk the redirect/call chain to the exact determining condition, confirming or falsifying each plan hypothesis against code. Code-tracing is a valid substitute for a plan-prescribed live repro when the repro needs hard-to-synthesize state. Verify route classifications by reading the route's exported HTTP methods (a "read route" with no GET is a write route). **Why:** #4543 follow-up — the plan's two 404 hypotheses + its "redirect lands on /dashboard" reconciliation were all wrong; a 4-file trace (`invite-actions` → `settings/team/page.notFound()` → null-org resolver → `accept-invite` never set active workspace) found the real cause. See `knowledge-base/project/learnings/bug-fixes/2026-06-01-symptom-root-cause-trace-the-actual-redirect-not-the-plan-hypothesis.md`.
   - **A short-circuit guard that returns early to skip a code path must sit AFTER any recovery mechanism that lives inside that path.** Before adding a "detect bad state → skip the expensive path → show a fallback" branch where the plan prescribes a placement, grep for where the *recovery* for that bad state actually runs; if recovery is entangled inside the path you're skipping, the early-return amputates it and dead-ends the user. An honest "X is gone" fallback is a *post-recovery-failure* concept — placing it pre-recovery makes the message a lie in exactly the recoverable case. The placement-time companion to "trace the ACTUAL producer". **Why:** #5240 — the plan's pre-dispatch `.git` probe (FR2/FR3) would have skipped the in-dispatch `ensureWorkspaceRepoCloned` self-heal, dead-ending connected-repo resume; reverted + descoped. See `knowledge-base/project/learnings/best-practices/2026-06-14-short-circuit-guard-must-sit-after-the-recovery-it-gates.md`.
   - **A fail-loud/short-circuit guard for state-class X must not nest under a precondition that only holds for a DIFFERENT state class — and a self-noticed plan-vs-goal gap gets fixed at write-time, not deferred to review.** When the plan nests "flag bad-state X and refuse to proceed" inside an enclosing gate you inherited from an adjacent branch (a staleness/age check, an auth check, a size check) that belongs to a *different* state class, the guard silently narrows to "refuse only when X *also* satisfies the unrelated gate" — undercutting the plan's own stated goal. Ask: does the enclosing condition belong to the SAME class the guard protects? If you notice the gap while coding, fix it inline (a ≤10-line correctness fix is not an architecture fork — reserve CTO routing for genuine forks); implementing the plan's literal placement and waiting for review to catch it is the wasteful path. **Why:** #5907 — the non-regular-lock `UNREMOVABLE` emit was nested under the regular-lock staleness gate, so a *fresh* non-regular `config.lock` slipped straight into the doomed `git config` EEXIST write; 3 review agents converged on a gap noticed at write-time. See `knowledge-base/project/learnings/best-practices/2026-07-02-fail-loud-guard-must-not-nest-under-a-different-state-class-gate.md`.
   - **On resume, a `session-state.md` `### Decisions` entry is INTENT, not an accomplishment — verify each against the live artifact before treating it as done.** The section is written in the past tense by a session that was still mid-flight, so a decision reading "met the intent via a correcting comment on #N" / "filed the follow-up" / "re-titled the issue" records what the author RESOLVED to do, and the step is exactly what a mid-task death (API timeout, compaction, crash) leaves undone — the resume then inherits the *claim* without the *act*. Cheapest gate: for every Decisions line naming an outward-facing artifact, probe it (`gh issue view N --json comments --jq '[.comments[]|select(.body|test("<cite>"))]|length'`, `gh issue view N --json title`, `ls <path>`) and re-open it in the task list on a zero. This is the outward-facing sibling of the artifact rule below (which covers FILES the contaminated session wrote); a GitHub comment leaves no working-tree trace at all, so nothing else surfaces its absence. **Why:** #6497 — `session-state.md` recorded a #6416 correcting comment as met; `gh issue view 6416` showed ZERO comments citing #6497, and the resumed session nearly shipped the claim in its PR body. See `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`.
   - **On resume, prior-session artifacts are UNVERIFIED — not work-in-progress to extend.** When `session-state.md` documents that the originating session's tool layer was contaminated/degraded (batched output, warnings prepended to `Read` results), the contamination taints every FILE that session wrote, not just the status claims it retracted ("applied"/"GREEN"). Re-derive each artifact from its authoritative source: read the real migration/file it claims to mirror and rewrite it as a verbatim delta (diff to prove byte-identity), then re-establish status from scratch (apply + verify the live DB; re-run RED→GREEN). For SQL, a misread `RETURNS` type is a free tripwire — `CREATE OR REPLACE` cannot change a function's return type, so any "applied GREEN" against a return-type-changed body is self-evidently false. **Why:** #4709 — 089 was authored against a misread of 088 (`RETURNS void` vs `integer`, dropped NULL-auth + 22023 gates); caught only by reading the real 088 body. See `knowledge-base/project/learnings/2026-06-01-resumed-session-artifacts-from-contaminated-tool-layer-are-unverified.md`.
   - **Counts written into the artifact (workflow header, script comment, AC expected-N) must be derived from the as-written file, not from plan-prose estimates.** Plan §Phase X says "~40 resources after expansion" → /work runs the grep → the actual count goes into the workflow header comment AND into AC4's expected N. Cheapest gate: after writing the artifact, re-run the canonical count command against the as-written file (`grep -cE '^[[:space:]]+-target=' <workflow>`, `wc -l <list>`, etc.) and copy the integer into every comment/AC reference. Plan-prose mental tallies drift by ±1-2 during expansion; multi-agent review reliably catches it (P3 polish) but the inline grep at write-time is free. **Why:** PR #4122 — workflow header carried "68 explicit targets" from plan §Phase 0.3 mental tally while `grep` returned 67; caught by `code-quality-analyst` + `pattern-recognition-specialist` at review. See `knowledge-base/project/learnings/best-practices/2026-05-20-plan-time-pr-vs-issue-disambiguation-and-self-derived-counts.md`.
   - **Re-running the count is necessary but NOT sufficient — publish the COMMAND next to the number, because a prose predicate does not pin a count.** Stating the filter ("N sites, where site = `<predicate>`") reads like rigour and is not: the prose leaves per-line-vs-per-match, unique-vs-all, marker position, and language-correct-markers free, each worth 10–30%. A number pinned to prose rots exactly like a citation pinned to a line number — both name a referent without fixing it — so the fix is the same: anchor on content (the command), not on a description. If the figure is load-bearing, also show the conclusion survives the plausible range. **Why:** #6517/PR #6527 — a reviewer *measured* and adopted "**403**, where site = a line in a code file bearing a comment marker AND citing `<path>.<src-ext>:<N>`" as canonical; at /work, **18 faithful readings of that exact prose returned 319–583 and never 403** (two independent resolvers also disagreed on the sibling counts). Shipped as `~360` + a `git grep … | wc -l`; the conclusion was invariant across the whole range (0.17–0.31%), which is *why* the false precision survived a 5-agent panel — nothing depended on it. See `knowledge-base/project/learnings/2026-07-16-advisory-first-precedent-is-a-claim-to-measure-and-a-coordinate-citation-carries-no-claim.md` Session Errors #3.
   - **Discrete-enumeration re-lockstep (when applicable).** When the plan asserts paraphrased lockstep across discretely-enumerated documents — e.g., "files in lockstep at sections (a)-(N)", "all 7 entries match in both files", "list is (i) through (v) on both sides" — run a fresh `grep -cE '^- \*\*\([a-z]\)\*\* '` (or equivalent, using `[a-z]` NOT `[a-N]`) across each file BEFORE the first letter-inserting Edit. Counts AND letter-sets must match; anything else means the plan's lockstep claim is paraphrase-from-stale-read. PR #3755 (#3708): plan asserted DPD §(a)-(k) lockstep; canonical actually had §(l) DSAR; AC1 caught the §(l) collision but the cheaper gate is re-lockstep at /work-start. See `knowledge-base/project/learnings/2026-05-14-discrete-enumeration-relockstep-and-pr-introduced-asymmetry.md`.
   - **Sequential-section insertion anchor.** When inserting a new `### N.M`-numbered section, the Edit anchor MUST target the LAST `### N.M` block before the desired slot (not the lexically-adjacent one). Confirm with `grep -nE '^### [0-9]+\.[0-9]+ ' <file> | tail -3`; the new `M` must be greater than the picked anchor's `M`. PR #3755 (#3708): §5.10 was anchored on §5.9-Resend's block start and landed BEFORE §5.9. One-grep prevention. Same learning file.
   - **Write-boundary sentinel sweep (when applicable).** If the plan introduces a sentinel/guard that asserts a property at write sites (e.g., `assertWriteScope` for cross-tenant integrity, GDPR write-boundary checks), enumerate ALL write sites where the property applies — not just diff sites. Run `git grep -nE '\.from\("<table>"\)\.insert\(' <scope>` (or the equivalent for the boundary type) at Phase 0 and verify every match is sentinel-gated, then file follow-up tasks for any uncovered sites BEFORE entering Phase 1. See `knowledge-base/project/learnings/2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md`; hard rule `hr-write-boundary-sentinel-sweep-all-write-sites`. **Why:** PR-A2 #3603 — sentinel placed at assistant-row write but not user-row write at `cc-dispatcher.ts:1008`; same service-role-bypass surface.
   - **Type-widening cross-consumer grep (when applicable).** When the PR widens a producer-side shared type whose payload crosses an `unknown`/`any`/jsonb boundary (compiler cannot enforce optionality at the consumer), `git grep -nE '<field-name-pattern>' apps/` across every consumer and verify each respects the new optionality. For `Message`-class fields the canonical grep is `git grep -nE '\bmessage\.usage\.(input_tokens|output_tokens|completed_actions)\b' apps/` (adapt per field family). See learning `2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md`; hard rule `hr-type-widening-cross-consumer-grep`. **Why:** PR-A2 #3603.
   - **Id-shape/format-guard fixture blast-radius (when applicable).** When the PR adds a shape/format guard (UUID allowlist, regex, length check) to an id that is DB-sourced AND flows through a shared resolver (`workspacePathForWorkspaceId`, an active-workspace resolver, any `join(root, id)` path builder), the guard THROWS on every test fixture that fabricated that id with a short non-UUID literal. Before sizing the change as "1 file", grep the fixture surface — `git grep -nE '"(user-1|ws-[A-Za-z0-9]|owner-[A-Z]|[a-z]+-workspace)"' apps/web-platform/test/` — and trace which hits reach the guarded function; size the fixture sweep at plan time, not at GREEN. The fix is realistic UUID fixtures (`cq-test-fixtures-synthesized-only`), never a looser guard. **Why:** #5344 — a "1 source + 1 test file" estimate broke ~34 fixture files. See `knowledge-base/project/learnings/2026-06-15-id-shape-guard-test-fixture-blast-radius-and-syntactic-sast.md`.
   - **Sweep-class fixes use grep-enumerated work-lists, not intuited ones.** When a plan declares a multi-file sweep with a verification grep (e.g., AC5-style `git grep -nE '<pattern>' <scope> | grep -vE '<safe-form>' | wc -l = 0`), run the grep ONCE at Phase 0 to enumerate the authoritative work-list (capture it via `targets=$(mktemp)` and write the hits there — never a fixed `/tmp` name a sibling session would clobber), fix each line, then re-run the grep after each batch. The plan's narrative enumeration of "files X, Y, Z" is a starting hypothesis; the grep result is the work-list. Same applies to regex widenings: enumerate the configs/verbs/paths invoked by the IN-SCOPE runbooks, not the configs the incident occurred against — the incident is one data point; the trap-class config-set is the full union of every config the runbooks touch. **Why:** PR #4031 — initial sweep handled 9 named runbook hits but missed 2 buried in deeper sections of the same files; widened regex covered `(prd|prd_terraform|dev|ci)` per the plan's leak-footprint enumeration but missed `prd_orchestration` which 2 in-scope runbooks operate against. Pattern-recognition + security-sentinel caught both at multi-agent review. See `knowledge-base/project/learnings/best-practices/2026-05-18-sweep-class-fixes-grep-enumerated-not-intuited.md`.
   - **A plan-prescribed cross-file drift guard ("all N files reference all M tokens") must be verified against each file's ACTUAL token usage before writing the assertion.** A family of parsers is rarely homogeneous — a secondary member often shares only a subset (e.g. a wipe-gate that checks only `--postgres-uri` and never parses redis). Run `grep -cF -- "$tok" "$file"` for every (file, token) pair at Phase 0 and let the matrix define the per-file token set; asserting the full set on a file that uses a subset false-fails a correct codebase. The plan is authoritative for the guard's intent, never its exact token/file set (same class as `hr-when-a-plan-specifies-relative-paths-e-g`). Corollary: plan-quoted AC verify commands are preconditions to re-derive, not facts — a `git diff origin/main | grep -c 'ssh '` proxy false-positives on self-referential prose + branch-divergence in cited-but-unedited files; scope it to the changed code files. **Why:** #5553 — the drift-guard spec required 4 tokens on all 3 ExecStart parsers, but `inngest-wiped-volume-verify.sh` references only 2; scoped per-file at /work. See `knowledge-base/project/learnings/best-practices/2026-06-18-cross-file-drift-guard-verify-per-file-token-usage.md`.
   - **Architectural-fork decisions route to the CTO agent, NOT the operator (HARD GATE — both modes).** When mid-work you discover the plan's prescribed mechanism is structurally blocked or contradicted by the code (a plan-vs-codebase contradiction surfaced by tracing the ACTUAL producer) AND the resolution is an *engineering/architecture* decision with material trade-offs — schema/audit substrate, data model, technology choice, security model, or which load-bearing module to disturb — route the BINDING decision to the `soleur:engineering:cto` agent (`Agent` tool, `subagent_type: soleur:engineering:cto`). Do NOT surface it to the operator via `AskUserQuestion`: the operator is non-technical, and architecture is the CTO's call. Reserve operator escalation for *product / scope / preference* decisions (what to build, never how). Hand the CTO the discovered evidence (`file:line`), the candidate options with trade-offs, and the plan's `brand_survival_threshold`; then implement exactly what it returns and record the decision + rejected alternatives in an ADR (`/soleur:architecture`). This is a routing rule, not an approval gate — it fires in pipeline mode too. **Why:** #5325 — /work found the plan's `action_sends`-reuse mechanism (deepen P0-1) was structurally blocked (NOT NULL `message_id` FK with no agent-path message id; UI-only `scope_grants` creation); the substrate choice (dedicated WORM table vs gate-only vs full reuse) is an architecture decision that was first (wrongly) offered to the operator before being routed to the `cto` agent, which ruled. See `knowledge-base/project/learnings/workflow-patterns/2026-06-15-architectural-fork-decisions-route-to-cto-not-operator.md`.
   - **Emergent PRODUCT/SCOPE/PREFERENCE decisions classify via the taxonomy, and headless never pauses on them.** For a mid-work decision that is NOT an architecture fork (those route to the CTO agent, above) — dropping/deferring operator-requested scope, a user-visible behavior choice, a money/compliance call — classify it Mechanical / Taste(user-legible) / User-Challenge per [decision-principles.md](../brainstorm-techniques/references/decision-principles.md) (ADR-084). Mechanical + technical-taste: auto-decide silently. A user-legible Taste or a User-Challenge (both against the operator's stated direction) in a headless/one-shot run: keep the operator's stated direction as the default and **persist** it to `knowledge-base/project/specs/<branch>/decision-challenges.md` (append; alongside `session-state.md`) — never a mid-pipeline pause. `ship` Phase 6 renders that artifact into the PR body and files the `action-required` issue the operator actually sees. The one exception to no-pause: a security/feasibility regression halts terminally before merge (see the reference doc).
   - **Interactive mode only:** If anything is unclear or ambiguous, ask clarifying questions now. Get user approval to proceed. **Do not skip this** - better to ask questions now than build the wrong thing.
   - **Pipeline mode:** Skip clarifying questions and approval. Proceed directly to step 2.

2. **Setup Environment**

   First, check the current branch by running `git branch --show-current`. Then determine the default branch by running `git symbolic-ref refs/remotes/origin/HEAD` and extracting the branch name. If that fails, check whether `origin/main` exists (fallback to `master`).

   **If already on a feature branch** (not the default branch):
   - **Interactive mode only:** Ask: "Continue working on `[current_branch]`, or create a new branch?"
   - **Pipeline mode:** Continue on current branch without asking.
   - If continuing, proceed to step 3
   - If creating new, follow the worktree creation instructions below

   **If on the default branch**, you MUST create a worktree before proceeding. Never edit files on the default branch -- parallel agents cause silent merge conflicts, and this repo uses `core.bare=true` where `git pull` and `git checkout` are unavailable.

   Create a worktree for the new feature:

   ```bash
   SOLEUR_SKILL_NAME=work SOLEUR_EXPECTED_DURATION_MIN=240 \
     bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh --yes create feature-branch-name
   ```

   Then `cd` into the worktree path printed by the script. The worktree manager handles bare-repo detection, branch creation from latest origin/main, .env copying, and dependency installation. The env vars wire a session lease so sibling cleanup-merged invocations refuse to reap this worktree.

   **Phase Exit (release lease).** At the end of the workflow — after `/soleur:ship` returns OR if you exit without shipping — release the lease so a sibling `cleanup-merged` can reap the worktree once it's actually merged:

   ```bash
   bash .claude/hooks/lib/session-state.sh release_lease "$(basename "$PWD")"
   ```

   The release is a no-op if the lease was already removed by the multi-signal trap (EXIT/INT/TERM/HUP fires on abnormal exit). Stale leases get swept after 24 hours regardless.

   Use a meaningful name based on the work (e.g., `feat-user-authentication`, `fix-email-validation`).

3. **Create Todo List (TDD-First Structure)**

   Structure tasks as RED/GREEN/REFACTOR units, not as "implement everything, then test":

   - For each feature requirement with Acceptance Criteria or testable behavior:
     - Create a **RED task**: "Write failing test for [feature]" — the test file with at least one failing test
     - Create a **GREEN task**: "Implement [feature] to pass tests" — blocked by its RED task
     - Group these as a TDD unit with `blockedBy` dependency (GREEN blocked by RED)
   - Infrastructure-only tasks (config files, CI, scaffolding, legal docs) are exempt from RED/GREEN pairing — create them as standalone tasks
   - Place a final "Run full test suite and lint" task at the end, blocked by all other tasks
   - Keep tasks specific and completable

   **Anti-pattern to avoid:** Creating a task list like `[implement A, implement B, implement C, ..., write tests, lint]`. This structure guarantees TDD violation because the agent executes tasks in order. The correct structure is `[RED: test A, GREEN: implement A, RED: test B, GREEN: implement B, ..., lint]`.

   **Post-creation validation (HARD GATE):** After creating all tasks, scan the task list for any non-exempt implementation task (GREEN) that does NOT have a corresponding RED test task in its `blockedBy` list. If found, restructure the task list before proceeding. Do not start Phase 2 with an invalid task structure. **Why:** In PR #2428, the agent created flat tasks ("Fix X", "Write tests") and started implementation before tests — the user had to intervene and force a restructure. The anti-pattern instruction was not enough without a validation gate.

### Phase 2: Execute

**Output discipline (all tiers).** Long execution phases blow the response-token ceiling and truncate mid-pipeline, losing the thread. Keep inline output bounded: when a command's output is large (full diffs, build logs, test dumps), write it to a file and reference the path rather than pasting it — never echo a diff over ~200 lines inline (`d=$(mktemp -t <task>.XXXXXXXX.diff); git diff > "$d"; echo "DIFF=$d"` then summarize, citing the path). After each task or logical unit, emit a one-line `## Work Phase <N> complete` checkpoint marker so an interrupted run has a clear resume point. This complements hard rule `hr-never-run-commands-with-unbounded-output` (which forbids unbounded *commands*); this is about bounding your own *narration* of them.

1. **Execution Mode Selection** (HARD GATE — must complete before executing ANY task)

   **Do NOT execute any task before completing this analysis.** Analyze independence first, select the execution tier, then begin. Starting sequential execution "because the first tasks feel simple" is a workflow violation — it forfeits parallelization savings on the remaining tasks.

   Before starting the sequential task loop, check for parallelization opportunities:

   **Step 0: Tier 0 pre-check (Lifecycle Parallelism)**

   Read the plan. Apply a single judgment: "Does this plan have distinct code and test workstreams that can be assigned to separate agents with non-overlapping file scopes?"

   - If yes (interactive mode): offer Tier 0 to the user
   - If yes (pipeline mode): auto-select Tier 0 without prompting
   - If declined or ineligible: fall through to Step 1 below

   **Read `plugins/soleur/skills/work/references/work-lifecycle-parallel.md` now** for the full Tier 0 protocol (offer/auto-select, generate contract, spawn 2 agents, collect/commit, test-fix-loop, docs). If Tier 0 executes, proceed directly to Phase 3 after completing Step 06 of the protocol. If declined, fall through to Step 1.

   ---

   **Step 1: Analyze independence**

   Read the TaskList. Identify tasks that have no `blockedBy` dependencies and reference
   different files or modules (no obvious file overlap). Count the independent tasks.

   If fewer than 3 independent tasks exist, skip to **Tier C: Sequential** below.

   If 3+ independent tasks exist, proceed through the tiers in order (A, then B, then C).
   Each tier either executes or falls through to the next.

   ---

   **Pipeline mode override:** If running in pipeline mode (plan file argument detected in Phase 1), auto-select Tier 0 if eligible (Step 0 above). If Tier 0 is ineligible, skip Tier A entirely and auto-accept Tier B without prompting. Do not present "Run as Agent Team?" or "Run in parallel?" questions -- proceed directly to Step B2 of the Subagent Fan-Out protocol if 3+ independent tasks exist, otherwise fall through to Tier C.

   ---

   **Tier A: Agent Teams** (highest capability, ~7x token cost)

   **Read `plugins/soleur/skills/work/references/work-agent-teams.md` now** for the full Agent Teams protocol (offer, activate, spawn teammates, monitor/commit/shutdown). If declined or failed, fall through to Tier B.

   ---

   **Tier B: Subagent Fan-Out** (fire-and-gather, moderate cost)

   **Read `plugins/soleur/skills/work/references/work-subagent-fanout.md` now** for the full Subagent Fan-Out protocol (offer, group/spawn, collect/integrate). If declined, fall through to Tier C.

   ---

   **Tier C: Sequential** (default)

   Proceed to the task execution loop below.

2. **Task Execution Loop**

   **Design Artifact Gate (before first UI task):** If `DESIGN_ARTIFACTS` was set in Phase 0.5, spawn the `ux-design-lead` agent with the artifact paths and ask it to produce an **implementation brief** (see ux-design-lead "Wireframe-to-Implementation Handoff" workflow). The brief is a structured description of every section, its content, and its layout — this becomes the binding input for all UI tasks. Do not write any markup until the brief is received.

   **UX artifact commit checkpoint (after Design Artifact Gate):** After the implementation brief is received, commit before proceeding to UI tasks:

   1. Run `git status --short` to discover the implementation brief and any generated design files
   2. Stage output files: `git add <discovered files>`
   3. Commit: `git commit -m "wip: UX implementation brief for <feature-name>"`

   This checkpoint ensures the implementation brief survives session crashes.

   For each task in priority order:

   ```text
   while (tasks remain):
     - Mark task as in_progress in TodoWrite
     - Read any referenced files from the plan
     - If task creates UI/pages: verify implementation brief exists (HARD GATE)
     - TDD GATE: (see below)
     - Look for similar patterns in codebase
     - RED: Write failing test(s) for this task's acceptance criteria
     - GREEN: Write minimum code to make the test(s) pass
     - REFACTOR: Improve code while keeping tests green
     - Run full test suite after changes
     - Mark task as completed in TodoWrite
     - Mark off the corresponding checkbox in the plan file ([ ] → [x])
     - Evaluate for incremental commit (see below)
   ```

   **No mid-plan pause gates (HARD GATE).** A multi-phase plan
   (`tasks.md` Phase 0 through Phase N) is a SINGLE execution unit.
   Do NOT insert "Pause for review or continue?" prompts between
   phases. Do NOT end a turn after one phase commits with "Continue
   into Phase N+1 next turn?". The skill's Phase 4 handoff is the
   only sanctioned stopping point — until then, chain straight
   through every phase the plan defines, including phases the plan
   labels "Pre-merge verification" or "Post-merge (operator)" if
   they're automatable per the next gate. **Why:** the founder is a
   solo operator; every "continue or pause?" is a context switch
   that defeats the entire point of a multi-phase plan. Pipeline
   mode (file-path arg in Phase 1) means pipeline mode for the WHOLE
   plan, not per-phase.

   **Operator-step automation gate (HARD GATE).** Before treating
   any task in `tasks.md` as "operator-driven" (apply migration,
   verify pg_cron, verify Storage bucket, run end-to-end smoke,
   `gh pr ready`, `gh pr merge --auto`), check whether it is
   automatable via a loaded MCP server or CLI:

   - Supabase migrations + `cron.job` queries + Storage bucket
     existence + RLS spot-checks → `mcp__plugin_supabase_supabase__*`
     **with Doppler `DATABASE_URL_POOLER` fallback when MCP is
     unavailable** — see "Supabase fallback chain" below. When a
     migration needs a SECURITY DEFINER RPC (e.g. to bypass an RLS /
     column-grant restriction), start from
     [`sql-security-definer-rpc-scaffold.sql`](./references/sql-security-definer-rpc-scaffold.sql)
     — it encodes the `search_path` pin + 4-role REVOKE + `auth.uid()`
     authorization pin that `test/migration-rpc-grants.test.ts` enforces.
   - `gh pr ready` / `gh pr merge --squash --auto` / `gh issue close`
     → Bash via `gh` CLI
   - End-to-end UI flow → Playwright MCP (`mcp__playwright__*`)
   - Cloudflare DNS / WAF / Workers → `mcp__plugin_soleur_cloudflare__*`
   - Live Stripe state → `mcp__plugin_soleur_stripe__*`

   If automatable, EXECUTE it inline as part of the work pipeline —
   never list it back to the operator. The /ship skill already
   handles `gh pr ready` + auto-merge + migration verification (see
   `plugins/soleur/skills/ship/SKILL.md`); chain to `/soleur:ship`
   at Phase 4 and let it run. For migration **apply** to dev (vs
   verify), invoke `mcp__plugin_supabase_supabase__apply_migration`
   inline at the phase where the migration lands, not as a
   post-merge todo. **Why:** see ship/SKILL.md:1027 ("Every 'please
   run this manually' is a context switch") and ship/SKILL.md:1177
   (PR #1375 — migration verification was left as a manual
   "post-merge todo" instead of being executed; deployed code
   expected the new schema and broke). Same class as the
   Playwright-first audit in Phase 4: if a tool exists, use it.

   **Supabase fallback chain (when MCP OAuth fails).** The Supabase
   MCP OAuth flow at `https://api.supabase.com/v1/oauth/authorize`
   intermittently rejects valid URLs at the dashboard `auth_id`
   handoff (cause: external — Supabase-side). When that happens, do
   NOT fall back to "paste this SQL into the dashboard SQL editor"
   handoff — that's a manual-step rationalisation that violates
   `hr-never-label-any-step-as-manual-without`. Instead walk down the
   `hr-exhaust-all-automated-options-before` priority chain:
   (1) Doppler `DATABASE_URL_POOLER` — already provisioned for every
   env; the migration apply path. (2) Verify the project ref in the
   URL matches the plan's stated dev/prd refs — Doppler is the
   source of truth (plan-quoted project refs are preconditions to
   verify, never facts; the plan can drift). (3) Rewrite the URL's
   port `:6543` → `:5432` so the pooler runs in session mode (multi-
   statement DDL works; transaction mode rejects with SQLSTATE 42601
   "cannot insert multiple commands into a prepared statement").
   (4) Apply via `pg` (node-pg, bun-installed in `/tmp` if missing)
   wrapped in `BEGIN; <migration>; COMMIT;`. The direct DB host
   `db.<ref>.supabase.co:5432` is IPv6-only and typically
   unreachable from operator/CI networks; the pooler is IPv4.
   (5) Post-apply, verify schema via the same connection — RLS
   enabled, policy_count, trigger names, RPC signatures + SECURITY
   DEFINER flag, UNIQUE constraints. Write the verification artifact
   to `knowledge-base/project/specs/feat-<name>/migration-checklist.md`.
   **Why:** PR #3853 / #3205 — Supabase MCP OAuth was rejecting URLs
   at the auth_id handoff; the agent first proposed "paste SQL into
   dashboard" (manual-step violation), then pivoted to Playwright-
   first audit on dashboard navigation (correct), then discovered
   Doppler had the working `DATABASE_URL_POOLER` and applied via
   pg directly — the path it should have taken at step 1.
   **Session stickiness:** once the MCP OAuth handoff has failed even
   once in the current session, treat Doppler `DATABASE_URL_POOLER` as
   the default for ALL subsequent Supabase operations this session — do
   not re-attempt the OAuth flow per-operation. Re-probing a known-flaky
   external auth each time is the wasted-cycle trap; the fallback is not
   slower once you are already authenticated to Doppler.

   **Pre-apply collision check (always, even on first attempt).**
   Before invoking pg apply (or `supabase migration up`) against any
   shared env, run `git fetch origin main && git ls-tree origin/main
   -- apps/web-platform/supabase/migrations/ | awk '{print $4}' |
   grep -oE '^[0-9]{3}_[^.]+' | sort -u`. For each LOCAL migration
   file the branch introduces, assert no DIFFERENT filename with the
   same 3-digit prefix exists in that list. A collision means a
   sibling PR is landing the same number window; renumber FIRST,
   then apply under the final filename. **Why:** PR #4225 — applied
   053–057 in the morning; PR #4251 landed `054_schema_migrations_
   content_sha.sql` 10 hours later and main's CI drift probe flagged
   the entire branch; the recovery (renumber 054→058, 055→059, 056→060,
   057→061 + reconcile `public._schema_migrations` on both dev + prd
   via `git hash-object` content_sha) took ~30 min and could have been
   zero-cost if the operator had grepped origin/main first.

   **The collision window extends through `/ship`, not just work-time.** This
   check at work-start is necessary but NOT sufficient: a sibling migration can
   land on main DURING the (often 30–90 min) ship phase — especially under a
   fast-moving-main burst where `/ship` Phase 7 performs repeated `git merge
   origin/main` auto-syncs on `OPEN BEHIND`. Each sync that pulls in a sibling
   `supabase/migrations/NNN_*.sql` sharing your prefix is a silent collision the
   BEHIND loop pushes straight to CI (where the migration drift/shape gate fails,
   ~16 min later). After ANY ship-time sync whose merge output lists
   `supabase/migrations/`, re-run the prefix check above and renumber-during-ship
   (`git mv` both up/down + update every in-repo reference: migration headers,
   code comments, plan/tasks/learning) BEFORE the next push. **Why:** PR #5760 —
   `114_disk_io_top_wal_statements` (a #5739-sibling) landed mid-ship; my
   `114_prune_cron_job_run_details` collided and surfaced only at CI after ~6
   auto-syncs; recovery was a renumber to 115. See
   `knowledge-base/project/learnings/workflow-patterns/2026-06-30-migration-number-collision-mid-pipeline.md`.

   **Tracking row in the SAME transaction as the migration body.**
   The project's canonical `apps/web-platform/scripts/run-migrations.sh`
   writes `INSERT INTO public._schema_migrations (filename, content_sha)
   VALUES ('<basename>', '<git-hash-object>')` in the same transaction
   as the migration SQL. The Doppler+pg fallback MUST mirror this —
   bare `BEGIN; <migration>; COMMIT;` produces a phantom-applied state
   where the schema reflects the migration but `_schema_migrations`
   does not, and the next deploy attempts re-apply (failing on
   non-idempotent statements like `CREATE TRIGGER`). The reconciliation
   pattern (UPSERT with `ON CONFLICT (filename) DO UPDATE SET
   content_sha = EXCLUDED.content_sha`) is the recovery shape — but
   doing it inline is cheaper.

   **PostgREST schema cache reload via session-mode pooler does NOT
   work.** `NOTIFY pgrst, 'reload schema'` over a `:5432` pooler
   connection does not reach PostgREST's `LISTEN` (PgBouncer
   multiplexes; LISTEN/NOTIFY channel scope is bound to backend
   process identity, not session). 90 attempts over 5 minutes
   returned `PGRST205`. After a direct-pg apply: either wait for the
   natural ~10-min schema poll cycle, OR use the Supabase Management
   API to restart PostgREST. The direct DB host
   (`db.<ref>.supabase.co:5432`) is IPv6-only and typically
   unreachable from operator networks, so the canonical "NOTIFY via
   direct connection" workaround documented upstream isn't available.

   **Storage-bucket migrations: `down.sql` cannot DELETE storage tables;
   column-takeover proof is permissive-vs-restrictive, not name-count.**
   Supabase installs a platform `BEFORE DELETE` trigger (`protect_objects_delete`
   → `storage.protect_delete()`) that blocks direct `DELETE FROM storage.objects`
   AND `storage.buckets` ("Direct deletion from storage tables is not allowed").
   So a bucket migration's `down.sql` reverts only SQL-droppable objects
   (policies → function → column) — NOT the bucket/objects (Storage-API/operator
   teardown; 019/042 precedent ship none; 071's `DELETE FROM storage.buckets` is
   a dormant bug). Runtime cleanup uses `service.storage.from(b).remove([...])`
   (allowed). And when verifying "no client can write column X" (read-proxy
   trust), assert no **PERMISSIVE** INSERT/UPDATE/DELETE/ALL policy (a
   RESTRICTIVE `FOR ALL` like `workspaces_jti_not_denied` only denies, never
   grants) + a behavioral authenticated `UPDATE` affecting **0 rows**. The
   pooler also presents a self-signed CA chain → transient node-pg verify
   scripts use `ssl:{rejectUnauthorized:false}` (dev-only, mirrors
   run-migrations.sh `sslmode=require`; no committed code disables TLS verify).
   See `knowledge-base/project/learnings/2026-06-04-supabase-bucket-migration-down-and-rls-takeover-proof.md` (#4916).

   **TDD Gate (HARD GATE):** Before writing ANY implementation code for a task, determine if the task has testable behavior:

   Emit rule-application telemetry (records that the TDD gate was reached — see AGENTS.md `cq-write-failing-tests-before`):

   ```bash
   source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
     emit_incident cq-write-failing-tests-before applied \
     "Write failing tests BEFORE implementation code whe"
   ```

   1. **Check:** Does the plan have a "Test Scenarios" or "Acceptance Criteria" section that covers this task? If yes, this task requires test-first.
   2. **Exempt:** Infrastructure-only tasks (config files, CI workflows, scaffolding directories, dependency installs) are exempt. If the task only creates/modifies config, it skips to Infrastructure Validation below.
   3. **Enforce:** For non-exempt tasks, write the failing test file FIRST. The test must:
      - Import the component/function/module that will be created (the import will fail — that is correct)
      - Assert the specific behavior from the acceptance criteria
      - Be runnable via the project's test command (even if it fails due to missing implementation)
   4. **Verify RED:** Run the test. It must fail (missing module, assertion failure, etc.). If it passes, the test is not testing new behavior — rewrite it. **For gating/sequencing primitives (semaphores, locks, queues, ordering guarantees), the test must distinguish gate-absent from gate-present: add an intermediate-state assertion that would fail without the primitive (e.g., `count === 2` while two slots are held) in addition to the final-state assertion. A test that passes identically with and without the primitive isn't testing the primitive.** See `knowledge-base/project/learnings/test-failures/2026-04-18-red-verification-must-distinguish-gated-from-ungated.md`. **Test-environment fidelity:** if the SUT's buggy code lives behind a guard (`if [[ -d "$X" ]]`, `if (cache.has(key))`, etc.), the harness MUST seed the precondition the guard requires — otherwise both buggy and fixed paths short-circuit identically and any negative-space assertion passes vacuously. See `knowledge-base/project/learnings/test-failures/2026-04-22-red-test-must-simulate-suts-preconditions.md`. **Early-exit shadowing:** if the SUT has a guarded fast path (substring strip like `replaceAll(arg, "")`, cache-hit, env-flag short-circuit) that handles a superset of inputs the slow path under test handles, RED inputs MUST choose identities ONLY the slow path can produce. Sharing a fixture across the fast/slow boundary lets the fast path scrub first and the regex/branch under test never fires — the assertion passes without testing the fix. Add an invariant guard test asserting the fast/slow fixtures do not collide. See `knowledge-base/project/learnings/2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md`. **In-component state machines (RTL):** when the gate-under-test is component-local state (`useState`/`useRef`/`useReducer`), drive the SUT through state transitions with `result.rerender(<C />)` — never `unmount()` + fresh `render()`. Remount resets the in-component bookkeeping that IS the gate, producing vacuous green. See `knowledge-base/project/learnings/test-failures/2026-05-11-rerender-not-remount-for-in-component-state-machine-tests.md`. **Laundered-target resolvability (normalizer/strip/prefix-mangle security fixes):** a regression guard for an anchored-strip / path-canonicalization / allowlist-key fix is vacuous unless the fixture makes the LAUNDERED (mis-normalized) target resolvable to an observable effect — if the downstream gate rejects it for an *unrelated* reason (nonexistent skill/row/file), the test passes identically with and without the fix. Litmus: under the buggy impl, does this input produce a DIFFERENT output than under the correct one? See `knowledge-base/project/learnings/test-failures/2026-07-05-security-fix-regression-guard-must-make-the-laundered-target-resolvable.md`. **Fixture-space cardinality (ask this per contract sentence, and note that your own passing mutation battery cannot answer it):** for each property the test claims, name the SET it quantifies over and count how many distinct members the FIXTURE instantiates — one member is a sample, not a proof, and code-mutation coverage does not detect a fixture-space gap. Three shapes recur: (a) a **temporal** contract (a wait/retry/debounce/convergence) sampled only by STATIC fixtures probes t=0 and t=∞ but never the transition — the case the guard exists for — so deleting the loop's `break` stays green; drive it with a stateful stub that changes on the Nth invocation and assert the success arm was reached VIA the loop; (b) a **bidirectional** guard (`-w`, an ordering, a comparison) must be fixtured in the direction where the weaker implementation gives a FALSE POSITIVE, not the direction that fails either way; (c) a stub that ignores `argv`, or a `sleep`/clock stubbed to a no-op, silently voids the call-shape and budget contracts — validate `"$*"` in the stub and COUNT the stubbed calls against the design's bound. **Why:** #6441 — a 7-mutation battery reported 7/7 RED while nine unimagined mutations (loop-`break` deleted, `grep -qwF`→`-qF`, `addr show`→`link show`, bound 30→1, `sleep 2`→`600`) all survived. See `knowledge-base/project/learnings/2026-07-19-my-own-mutation-battery-was-the-false-confidence.md`.
   5. **Only then:** Write the minimum implementation to make the test pass (GREEN).
   6. **Refactor:** Improve code while keeping tests green.

   Skipping this gate — writing implementation before tests — is a workflow violation equivalent to committing directly to main. The rationalization "this is simple enough to not need test-first" is exactly the reasoning TDD is designed to prevent.

   - When adding MCP tools to an existing registration block in agent-runner.ts, verify each tool's prerequisites are independent of the block's guard condition. Write a test that validates the new tool works WITHOUT the existing block's prerequisites (e.g., Plausible tools work without GitHub installation).

   - When adding route handler tests that require `vi.mock()`, create a separate test file from existing unit tests that import the real module. Vitest hoists all `vi.mock()` calls to the top of the file, clobbering real imports for the entire file regardless of describe block scope.
   - When creating test files with `vi.mock()` factories that reference shared variables, use `vi.hoisted()` from the start -- vitest hoists `vi.mock` to the top of the file before `const`/`let` declarations execute.
   - When a NEW shared module will be imported (directly or transitively) by files that already have test suites mocking a node builtin (`vi.mock("node:child_process")` with spawn-only factories is the common case), do NOT destructure that builtin's exports at module top level (`promisify(execFile)` crashes EVERY sibling suite at import). Lazy-import inside the function that uses it. **Why:** #5091 — `_cron-safe-commit.ts`'s top-level `promisify(execFile)` broke 28 cron-bug-fixer tests at module load. See `knowledge-base/project/learnings/2026-06-10-bot-cron-safe-commit-substrate-symlink-removal.md`.
   - Before adding a `vi.mock("<module>")` to an EXISTING test file, grep the file for a pre-existing mock of the same module (`grep -n 'vi.mock' <file> | grep <module-basename>`) and wire your spy into that block instead. Vitest registers one mock per resolved module per file; a duplicate does not error — it silently picks one, and your hoisted spy captures zero calls. **Why:** PR #5090 — a new egress-posture-log spy was added as a second `@/server/logger` mock while the factory test already mocked it ~150 lines down; cost 4 debug cycles. See `knowledge-base/project/learnings/bug-fixes/2026-06-10-sandbox-network-plane-not-token-plane-error-shape-triage.md`.
   - A WHOLESALE `vi.mock("<module>", () => ({...}))` replaces the ENTIRE module, dropping every export the factory omits — so a module with multiple named exports (`@/server/logger` exposes `default` AND `createChildLogger`; observability, db-helper, supabase wrappers similarly) breaks any REAL sibling in the SUT's import graph that consumes a different export. Default to `vi.mock(spec, async (importOriginal) => ({ ...await importOriginal(), <override> }))`; reserve wholesale factories for modules you fully replace — or skip the mock entirely if the thing under test already mocks the export's consumer. Detection is free: run the FULL test file (never `-t "<new test>"` alone) — the RED run surfaces unexpected sibling failures naming the missing export. **Why:** #5689 — a wholesale `@/server/logger` mock dropped `createChildLogger` (used by `probe-octokit.ts` via `_cron-shared`), breaking 10 unrelated arm-2 tests. See `knowledge-base/project/learnings/test-failures/2026-06-29-wholesale-module-mock-drops-named-exports-needed-by-transitive-siblings.md`.
   - A partial `vi.mock(spec, async (importOriginal) => ({ ...actual, B: spy }))` override only changes what **importERS** see — it does NOT intercept a call made by a REAL sibling function `A` (kept via `...actual`) to `B` **within the same module**; `A` references `B` through the module's internal lexical binding, not the export object. Symptom: the spy reports 0 calls even though the path clearly runs `B`. To observe `B` while keeping `A` real, mock the deeper boundary `B` itself crosses (`fetch`, the DB client, `child_process`) and assert there. Decision rule: **mock the seam the unit under test does not own.** **Why:** #5728 — overriding `postSentryHeartbeat` didn't intercept the real `finalizeOutputAwareHeartbeat`'s internal call; fixed by keeping it real + stubbing `fetch` + asserting the POST URL. See `knowledge-base/project/learnings/test-failures/2026-06-30-partial-module-mock-does-not-intercept-intra-module-calls.md`.
   - When mocking `child_process.spawn`, `fetch`, or any constructor returning an event-emitter-like object, use `mockImplementation(() => factory(...))` rather than `mockReturnValue(factory(...))`. `mockReturnValue` evaluates the factory eagerly at test-setup time; any `queueMicrotask` / `setTimeout` / `setImmediate` scheduled inside the factory fires BEFORE the SUT attaches its listeners, producing empty event data or an "uncaught error" test timeout. See `knowledge-base/project/learnings/test-failures/2026-04-17-vitest-mockReturnValue-eager-factory-async-event-race.md`.
   - A `vi.fn(() => value)` mock declared with a ZERO-parameter implementation cannot be invoked via a `(...args) => mock(...args)` forwarder (the standard `vi.mock` factory shape) — `tsc` rejects the spread with TS2556 "A spread argument must either have a tuple type or be passed to a rest parameter", even though the vitest run is GREEN (vitest type-checks test files lazily). Give the impl a rest param: `vi.fn((..._args: unknown[]) => value)`, matching sibling `vi.fn()` mocks. Only a standalone `./node_modules/.bin/tsc --noEmit` catches it. **Why:** #5817 — `execFileSyncMock = vi.fn(() => Buffer.from(""))` passed 36/36 tests but failed tsc. See `knowledge-base/project/learnings/test-failures/2026-07-01-vitest-zero-arg-mock-cannot-take-spread-suite-green-tsc-red.md`.
   - When the SUT `await`s something (`mkdtemp`, a config read, a lock) BEFORE it calls the mocked `spawn`/`fetch` and attaches listeners, emit the child's `close`/`error`/`data` events from INSIDE the spawn mock (`spawnMock.mockImplementation(() => { queueMicrotask(emit); return child; })`), NOT from a sibling top-level `queueMicrotask` in the test body. A test-level microtask scheduled right after calling the SUT fires during the pre-spawn `await` gap — before listeners exist — so the settle-once promise never resolves and the test times out (16s). The emit must be scheduled relative to when `spawn` is actually invoked. **Why:** PR #4970 — adding `await mkdtemp` before `spawn` in `c4-render.ts` timed out 6 tests until the emit moved inside the mock; see `knowledge-base/project/learnings/best-practices/2026-06-05-external-cli-exit-0-is-not-proof-validate-the-artifact.md`.
   - When using `vi.doMock("specifier", () => { throw new Error("X") })` to simulate a module-init failure, do NOT assert on the inner error message via the SUT's caller. Vitest wraps factory throws with its own synthetic Error (`"[vitest] There was an error when mocking a module..."`) and the inner string is unobservable. Assert on the SUT's observable contract (return shape, observability mirror call) instead — the throw is a *trigger*, not a *contract*. See `knowledge-base/project/learnings/2026-05-07-vitest-domock-factory-throw-wrapped-message.md`.
   - To prove a cache-hit skips work (not just that the response status is correct), wrap the real implementation in a spy via `vi.importActual` rather than stubbing the return value: `vi.mock("@/module", async () => { const actual = await vi.importActual(...); return { ...actual, expensiveFn: (...args) => { spy(...args); return actual.expensiveFn(...args); } })`. Stubbed returns break any downstream behavior that depends on the real output (hash-match, SQL row shape, etc.); wrapping preserves the contract while exposing call counts for assertions like `expect(spy).toHaveBeenCalledTimes(1)` across a HEAD+GET sequence. **Why:** In PR #2515, verifying that HEAD populates `shareHashVerdictCache` so a follow-up GET skips the SHA-256 drain required counting `hashStream` calls, not stubbing its return — a stubbed return would have broken the post-drain hash-equality check and masked the very regression the test was meant to catch.
   - When testing decorative images (alt="") with happy-dom, use container.querySelector instead of screen.getAllByRole("img", { hidden: true }) -- happy-dom excludes presentational elements from role queries even with hidden: true.
   - When asserting against a conditional render branch in a component test, grep the test file's `vi.mock(...)` factories for the inputs the branch reads and confirm the mock returns values that activate the target branch. Mocks that simplify (e.g., `getDisplayName: (id) => id.toUpperCase()`) often skip production branches like `leader.title.includes(displayName)` — assertions on the skipped branch fail for non-bug reasons. **Why:** PR #3427 — see `knowledge-base/project/learnings/2026-05-07-test-assertion-must-verify-mock-activates-branch.md`.
   - A wait-on-ABSENCE (`await vi.waitFor(() => expect(queryByTestId(x)).toBeNull())`) is vacuous — it passes on the FIRST tick, before the async work resolves, so it never proves "absent AFTER the state commit." Anchor the wait on a positive settle signal (e.g., a `.finally(() => { settled = true; })` flag on the mocked response body), then assert absence. Also: vitest's `vi.waitFor` and RTL's `waitFor`/`findBy*` have independent 1 s defaults and independent config surfaces — a global RTL `asyncUtilTimeout` bump does not touch `vi.waitFor` call sites. **Why:** #5113 — see `knowledge-base/project/learnings/test-failures/2026-06-10-parallel-load-flake-two-mechanisms-and-vacuous-absence-waits.md`.
   - An intermittent absence-wait that times out at the **FULL (explicit) timeout** is a component/state RACE, not a timeout-floor problem — raising the timeout cannot fix it. Discriminator: if the failing `vi.waitFor` site already carries an explicit `{ timeout }`, the floor is irrelevant; trace the component's effect ordering. A passive effect that resets state on EVERY render where a condition holds (`if (cond) setX(false)`) rather than on a `prev→curr` transition races any user action that should win (React runs passive effects AFTER commit, so it can land after the click and undo it) — gate such effects on the transition via a `prevValue` ref. **Why:** #5796 — see `knowledge-base/project/learnings/test-failures/2026-06-30-vi-waitfor-floor-vs-component-rearm-race.md`.
   - When testing a fallback ladder or mode option (primary-then-degrade, retry-then-cache, mergeMode direct→arm-auto-merge), assert the FIRST rung was *attempted* (the primary call fired), not just the fallback's effect — an effect-only assertion passes identically against an option-ignoring implementation whose default path yields the same end state. **Why:** PR #5133 — two mergeMode-direct fallback tests passed against the pre-#5111 helper; see `knowledge-base/project/learnings/2026-06-11-pipeline-consolidation-behavior-preserving-migration-traps.md`.
   - When adding `sessionStorage` usage to React components, ensure the component's test file includes `sessionStorage.clear()` in its `beforeEach` block. Shared jsdom environments leak sessionStorage between tests, causing ordering-dependent failures.
   - When adding a React-context-dependent hook (`useTheme`, `useRouter`, any provider-gated hook) OR a new provider import to a SHARED component, grep `test/` for every file that renders that component DIRECTLY (not via a `vi.mock` of its module) and add the provider stub in the SAME commit. `tsc` and the component's own test pass; sibling direct-render tests fail at RUNTIME with `<hook> must be used inside <Provider>`. **Why:** PR #5217 — `C4Canvas` gained `useTheme()`; `c4-fullscreen.test.tsx` (the only direct `<C4Canvas>` renderer) broke 8 tests until stubs for `theme-provider` + `@mantine/core` were added. See `knowledge-base/project/learnings/2026-06-12-likec4-mantine-color-scheme-seam-and-vendored-theme-preservation.md`.
   - To reproduce a provider's SSR-hydration "no-bootstrap" state in jsdom (lazy `useState` initializer landed on a server fallback like `"system"` WHILE durable storage holds the real value AND the DOM attribute is absent), do NOT use a `Storage.prototype.getItem` call-count spy — it bleeds across tests in the shared jsdom worker (passes in isolation, fails in-suite) and a leftover DOM attribute pollutes later inits. Instead use REAL localStorage (empty at init) and write the stored value from inside the `matchMedia.matches` getter (fires during the resolved-state initializer — after both init storage reads, before the first-mount effect); scrub the attribute + clear storage inside the mount helper and `cleanup()` in `afterEach`. Pair it with a precondition self-check (`if (!released) throw`) so a future init refactor that stops touching `matchMedia` fails as a clear FIXTURE error, not a phantom SUT regression. A naive client-only mount masks the bug (initializer reaches the durable value directly → vacuous green). **Why:** PR #5312 — see `knowledge-base/project/learnings/test-failures/2026-06-15-ssr-hydration-no-bootstrap-theme-test-gate.md`.
   - When asserting on `vi.getTimerCount()`, remember that `vi.useFakeTimers()` mocks every timer-like API by default — including `requestAnimationFrame`, `setImmediate`, `queueMicrotask`, `requestIdleCallback`. The count is a SUM across all fake timer types, not just `setTimeout`. Prefer stability assertions (`count before N extra calls === count after`) over magnitude assertions (`count === 1`) so refactors that add a well-behaved rAF or microtask don't falsely read as leaks. See `knowledge-base/project/learnings/test-failures/2026-04-17-vitest-getTimerCount-counts-requestAnimationFrame.md`.
   - When a component exports an interface that a test harness consumes (e.g., `ChatInputQuoteHandle`), have the test import it via `type X = ExportedInterface` — never shadow with a local duplicate. Duplicate interfaces silently drift when the exported type gains a method; the `tsc --noEmit` failure surfaces only at build time.
   - When adding a new npm dependency, check the installed major version (`node -e "console.log(require('<pkg>/package.json').version)"`) and read the type definitions before using API from docs or training data. Library APIs change across major versions (e.g., `react-resizable-panels` v4 uses `Group`/`Separator`/`orientation`/`useDefaultLayout`, not v2's `PanelGroup`/`PanelResizeHandle`/`direction`/`autoSaveId`).
   - For sizing APIs from third-party libraries, always pass **explicit units as strings** (e.g., `"18%"`, `"100px"`, `"1rem"`) rather than bare numbers. Docstrings may claim a default unit but runtime parsers often treat numbers as pixels. **Why:** `react-resizable-panels` v4 doc said "Percentage of the parent Group (0..100)" for numeric sizes, but the runtime treated `18` as 18px, producing a ~18px-wide sidebar in production. Explicit units make intent visible at the call site and survive library version upgrades.

   **Test environment setup:** If the project's test runner cannot run the type of test needed (e.g., React component tests require jsdom but vitest is configured for node), set up the test environment BEFORE starting the task. This is part of RED — the test infrastructure must exist for the test to fail properly.

   - When configuring bun preload scripts that register DOM globals (e.g., happy-dom), use dynamic `await import()` for all subsequent dependencies — static ES imports are hoisted before any imperative code, causing libraries like @testing-library/react to initialize without DOM globals. See `knowledge-base/project/learnings/test-failures/2026-04-03-bun-test-dom-preload-execution-order.md`.
   - Never write a literal `*/` inside a `/* … */` / `/** … */` block comment — it closes the comment early. The trap is documenting a regex that ends in `*/` (`/--[^\n]*/g`, `foo/**/*`): esbuild/tsc then parses the trailing prose as code and reports `Expected ";" but found <token>` at a line deep inside the docstring (a red herring — the real cause is the stray `*/` upstream). Describe the regex in prose or use a `//` line comment; `grep -nF '*/' <file>` after authoring confirms every hit is real code. **Why:** #5920 — a `*/g` in a JSDoc comment broke collection of `byok-rpc-body-markers.test.ts`. See `knowledge-base/project/learnings/build-errors/2026-07-03-jsdoc-block-comment-closed-early-by-regex-star-slash.md`.
   - When a test file calls a SUT that lazy-imports a heavy module (`pdfjs-dist`, `sharp`, `puppeteer`, `playwright`, `@xenova/transformers`, `onnxruntime`), pre-warm the module in `beforeAll(async () => { await import("<module>"); }, 30_000)`. The cold-start cost (~5-10s on CI runners) otherwise lands on the first `it()` and blows the default 5s vitest timeout — the second test in the same file runs at warm ~9ms because subsequent calls hit the module cache. Cheapest detection: `git grep -lE '(pdfjs-dist|sharp|puppeteer|playwright|@xenova/transformers|onnxruntime)' -- '*.test.ts'` and check for sibling `beforeAll`. **Why:** PR #3681 `pdf-text-extract.test.ts` cold-start flake (7s vs 9ms, #3687).
   - When uploading files via Playwright MCP, save files to repo-accessible paths (not `/tmp/`). Playwright MCP restricts file access to the repo root. When Google Search Console offers Cloudflare auto-verification, prefer "Any DNS provider" manual flow — the popup OAuth flow opens an external tab that crashes the Playwright browser context.
   - **Vendor-token extraction via Playwright MUST use `browser_evaluate(filename: ...)` from the FIRST attempt** — the return value otherwise enters the conversation transcript and the token is leaked even after revocation. AND the `filename` parameter JSON-encodes the result (surrounding quotes), so the canonical pipe is `python3 -c "import sys,json; sys.stdout.write(json.loads(open('<path>').read()))" | doppler secrets set <KEY> --no-interactive`. Validate via the vendor's API (HTTP 200 + length check) before shredding the file — some vendors silently tolerate quoted tokens via `Authorization: Bearer "abc"`, but Terraform's HCL parser does not. For `●●●`-masked UI tokens (Doppler personal tokens), click the in-page copy button via `browser_evaluate`, then `xclip -selection clipboard -o > <path>`; clear with `xclip -i </dev/null`. **Doppler TF var storage convention:** drop the `TF_VAR_` prefix from the secret name — `--name-transformer tf-var` ADDS the prefix at injection time (`DOPPLER_TOKEN_TF` → `TF_VAR_doppler_token_tf`; storing the already-prefixed `TF_VAR_DOPPLER_TOKEN_TF` produces `TF_VAR_tf_var_doppler_token_tf`). See [`2026-03-21-doppler-tf-var-naming-alignment.md`](../../../../knowledge-base/project/learnings/2026-03-21-doppler-tf-var-naming-alignment.md). **Why:** PR #3973 (#3960) — full pattern + recovery flow at [`2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md`](../../../../knowledge-base/project/learnings/2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md).
   - After any `Write` whose hook output emits a warning (security, style, rule), immediately `Read` the file to verify the full content landed. PreToolUse hooks that print error output but return non-blocking status can still cause partial writes — detecting this only when tests fail wastes a debug round. See `knowledge-base/project/learnings/2026-04-15-kb-share-binary-files-lifecycle.md`.
   - When adding source-reading regex tests (`readFileSync(path)` + `expect(src).toMatch(...)`) as a negative-space regression gate after an extraction, put them in a standalone `*.test.ts` file — never add them to an existing test file that already mocks `node:fs` or `node:path`. The existing `vi.mock("node:fs", ...)` factory likely omits `readFileSync`, and the new test will fail at collection with "No `readFileSync` export is defined" before any assertion runs. Also trim the gate to only the assertion that cannot be expressed behaviorally — usually the negative "symbol-not-present" check. Positive assertions (import regex, await-call regex) duplicate coverage that mock-based behavioral tests already provide and are brittle to barrel re-exports, aliases, and whitespace. See `knowledge-base/project/learnings/best-practices/2026-04-17-regex-on-source-delegation-tests-trim-to-negative-space.md`.
   - **NARROWING THE SCOPE IS NOT THE FIX — ANCHOR ON SYNTAX.** The bash body-grep rule below generalizes to EVERY source-reading assertion (`readFileSync` + `toContain`/`toMatch` over `.tf`/`.yml`/`.ts`), and the obvious correction — slice a narrower region — FAILS when a file puts explanatory comments INSIDE the construct: there is then no scope that holds the config but no prose. Anchor on something a comment cannot produce (`^\s*key\s*=` — a comment line starts with `#`; a call shape `Fn\(\s*arg`), never a bare word. Treat every `toContain` of a token that also appears in a nearby comment as guilty until mutation-tested, and give every slice helper an explicit lower bound plus an `indexOf === -1` guard (`slice(-1)` yields the last character, so `.not.toMatch()` against it always passes). **Why:** #6456 shipped FOUR — `/value\s*=\s*2/` matched its own "WHY value = 2 AND NOT 3" comment; `toContain("IssueOwners")` matched an in-body comment while the entire `actions_v2` block was deleted (the rule then paged nobody — the outcome the test was named for) and stayed 10/10 green; a boundless `scopeResource` swallowed the next resource's comment so a GROUPING-anchor check was satisfied by the pointer to the paragraph it was meant to find. All four were read-and-believed; only mutation caught them. Count failures from the runner's summary line after stripping ANSI — `grep -cE '^\s+×'` always returns 0. See `knowledge-base/project/learnings/2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md`.
   - When adding a static-grep assertion over a SCRIPT BODY (a `.sh`/`.test.sh` body-grep gate, an AC `grep -n … | head -1` order check), anchor it on the syntactic write/call construct (`rest/v1/<table>`, a function-call shape) — NEVER a bare token (`<table>`, `<flag-name>`) that the same file also names in a COMMENT or header-inventory. A body-grep sees comments too, so the moment a task requires both a "must / must-not contain X" assertion AND documenting X in a comment, they collide: a negative `! grep -qE 'X'` false-FAILs on the explanatory comment, and a `grep -n X | head -1` order check returns the comment line, not the code. Reword forbidden-literal comments to drop the literal. Same class as the source-reading-regex rule above, for bash. **Why:** PR for #5501 — `seed-live-verify-user.sh`'s `user_session_state` upsert: the test's `! grep '/rpc/set_current_workspace_id'` tripped on a comment naming the RPC, and the AC3 bare `grep user_session_state` matched the new header-inventory line. See `knowledge-base/project/learnings/test-failures/2026-06-17-grep-assertion-over-script-body-false-matches-own-comments.md`.
   - When a drift-guard test EXTRACTS a substring (regex over SKILL.md/source) to compare against an **exact-equality production Set** (an allowlist, a carve-out, a canonical-literal set), the extraction must (a) span the SAME command/token boundaries the production checker uses — capture the FULL command, not a salient prefix; a verb-terminated `(?:list|ls)\b` lets `… list --json` extract the bare `… list` (a member) and pass GREEN while the real command is a non-member — and (b) match EVERY shape the producer can legitimately emit (optional `bash ` prefix, env-prefixed direct-exec) — an unmatched shape silently escapes the guard, it is not caught drift. Litmus: mentally mutate the producer (add a flag, drop the prefix, change the anchor) and confirm the test goes RED for each; `.trim()` the extract to mirror the checker's own normalization. Do NOT assert a failure *consequence* in the docstring you haven't traced in the gate code (e.g. "DENIED on server" when the path only degrades to the review-gate). **Why:** PR #6152 (#6121) — the plugin-root list/ls coupling test's regex false-GREENed on trailing-arg + no-`bash` drift; caught by test-design + user-impact review. See `knowledge-base/project/learnings/best-practices/2026-07-07-drift-guard-extraction-must-mirror-production-checker-boundaries-and-all-emission-shapes.md`.
   - When a bun-test file mutates `process.env.*` or `globalThis.*`, capture originals at module top-level (before any `describe`) and restore in `afterEach` using `delete` when the original was `undefined` — `bun test` runs every file in a single OS process, so mutations leak to sibling files and to any `spawnSync` subprocess launched after the mutation. Vitest isolates files in workers by default; bun does not, and has no built-in `stubEnv`/`unstubAllEnvs` equivalent. **Why:** PR #2579 — `bot-fixture-helpers.test.ts` stubbed `SUPABASE_URL` in `beforeEach` with no restore, causing 4 integration tests in `bot-fixture.test.ts` (same run) to ConnectionRefused against the stub host. See `knowledge-base/project/learnings/test-failures/2026-04-18-bun-test-env-var-leak-across-files-single-process.md`.
   - When a vitest test asserts a `process.env.X === "true"`-gated default-off path, add `vi.stubEnv("X", "")` to `beforeEach` regardless of whether the current Doppler/CI config injects the var. `vi.unstubAllEnvs()` reverts `vi.stubEnv` writes only — it CANNOT delete a process-inherited env var (Doppler dev / CI secrets / `direnv` / devcontainer envs). The test passes locally with plain `npx vitest run` and fails deterministically under `doppler run -p soleur -c dev -- npx vitest run` when the dev config flips the flag on. Tests that need the flag on continue to call `vi.stubEnv("X", "true")` in their own `it()` bodies — the local stub overrides the beforeEach default (overwrite-semantics). **Why:** PR #4141 (#4128) — `cc-dispatcher.test.ts > T-W4-basic-off` failed 1/1 under Doppler dev because `CC_PERSIST_USAGE=true` injection survived `unstubAllEnvs()`. See `knowledge-base/project/learnings/test-failures/2026-05-20-vitest-unstub-does-not-clear-process-inherited-env-vars.md`.
   - When a test uses retry-on-flake logic (network, LLM non-determinism, timing), collect every attempt into an array and assert the invariant across ALL attempts — not just the last. Early-return after retry silently drops first-attempt failures. If the retry exists to force a precondition (tool invocation, tool output presence), assert the precondition WAS met on the final attempt; a refusal on retry is a hard failure, not a silent pass. **Why:** PR #2610 FR2-smoke/FR8/FR9 originally used `if (!condition) { retry; return; }` which let attempt-1 leaks slip through. See `knowledge-base/project/learnings/test-failures/2026-04-19-retry-once-early-return-masks-first-attempt-failures.md`.
   - When adding Eleventy `_data/*.js` files: (a) name the file in camelCase matching a valid JS identifier — kebab-case filenames produce hyphenated template variables that Nunjucks dotted access cannot resolve; (b) keep the module **default-export-only** — sibling `export` statements silently disable Eleventy's data-module registration (no error, no warning, the benchmark log omits the file); attach test helpers as properties on the default export. Verify each new `_data/*.js` appears in the build's `Benchmark ... (Data) ...` log. **Why:** PR #2596 — see `knowledge-base/project/learnings/build-errors/2026-04-18-eleventy-data-module-loading-and-nunjucks-null-test.md`.
   - Nunjucks has **no** `is null` / `is not null` test — the parser accepts `{% if x is not null %}` but evaluates it unpredictably for numeric values. To distinguish `undefined` / `null` / `0`, precompute a boolean in the `_data/*.js` module (e.g., `{ stars, showStars: stars != null }`) or accept a truthy guard. **Why:** PR #2596 — see same learning file.
   - When a work task ports a TS regex normalizer to SQL (or vice versa) for a backfill migration, run every fixture from the TS unit test file through the SQL expression BEFORE committing the migration. Cheapest shape: a `WITH fixtures AS (VALUES (<input>, <expected>), ...) SELECT input, expected, <sql-expr> AS actual, expected = <sql-expr> AS ok FROM fixtures` query. The WHERE-clause idempotence guard (`col <> <normalized-expr>`) is necessary but not sufficient — it only catches drift on re-runs, not on first apply. Idempotence fixtures must include at least one repeated-suffix case per strip-class (`.git.git`, trailing `//`) so a `\.git$` that should be `(\.git)+$` is forced to fail. **Why:** PR #2817 — migration 031 had a P1 operator-precedence bug (`.git` stripped before trailing `/`) and a P2 non-idempotency bug (`bar.git.git`), both caught only at multi-agent review. See `knowledge-base/project/learnings/best-practices/2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md`.

   **IMPORTANT**: Always update the original plan document by checking off completed items. Use the Edit tool to change `- [ ]` to `- [x]` for each task you finish. This keeps the plan as a living document showing progress and ensures no checkboxes are left unchecked.

3. **Incremental Commits**

   After completing each task, evaluate whether to create an incremental commit:

   | Commit when... | Don't commit when... |
   |----------------|---------------------|
   | Logical unit complete (model, service, component) | Small part of a larger unit |
   | Tests pass + meaningful progress | Tests failing |
   | About to switch contexts (backend → frontend) | Purely scaffolding with no behavior |
   | About to attempt risky/uncertain changes | Would need a "WIP" commit message (exception: UX artifacts use `wip:` prefix) |
   | UX specialist produces artifacts (wireframes, copy, brief) | Specialist is still generating (mid-output) |
   | Domain leader review cycle completes (feedback applied) | Review feedback not yet incorporated |
   | Brand guide alignment pass completes | Alignment still in progress |

   - When lefthook hangs during commit in a worktree (common with `core.bare=true` repos), verify typecheck and tests pass manually, then use `LEFTHOOK=0 git commit`. Always check for stalled lefthook processes (`pgrep -fa lefthook`) before retrying.
   - **`LEFTHOOK=0` also bypasses the `c4-model-regenerate` pre-commit hook.** If the diff edits a `.c4` file, run `bash scripts/regenerate-c4-model.sh` and stage the updated `model.likec4.json` BEFORE the `LEFTHOOK=0` commit — otherwise `c4-model-freshness.test.sh` (full-suite-only, not the touched-file loop) reds. `c4-render.test.ts`/`c4-code-syntax.test.ts` do NOT check the committed artifact. **Why:** #6549 — a `model.c4` edit committed under `LEFTHOOK=0` shipped a stale `model.likec4.json`.
   - After a `git mv old new`, never `git add old` (the pre-rename path) — the stale pathspec exits fatal `pathspec 'old' did not match` and ABORTS the entire `git add`, silently dropping every other path, so the commit captures only the rename (`0 insertions`). Stage the NEW path (or `git add -A <dir>`) and verify `git show --stat HEAD` shows the full expected file set before trusting the commit; a rename-only stat on a content change is the tell. **Why:** #6448 — a `git add …/docker-daemon.json` after renaming it to `.tmpl` produced a rename-only first commit; fixed by `--amend`.
   - **When a commit needs a machine-readable trailer (`Allowlist-Widened-By:`, `Signed-off-by:`, `Reviewed-by:`, etc. — anything downstream parses via `git log --format='%(trailers:key=NAME,valueonly)'`), keep the FINAL paragraph as a pure contiguous block of `Token: value` lines.** Two silent-drop shapes: (a) blank line between the new trailer and `Co-Authored-By:` makes the former part of the body, not a trailer; (b) ANY non-key:value line in the final paragraph (e.g., `Closes #3877.`, `Refs #3874 (precedent).`) invalidates the WHOLE block — both legitimate trailer lines below it drop silently. Put `Closes`/`Refs`/`Fixes` in mid-body prose; GitHub auto-close still works anywhere in the body. Verify locally with `git interpret-trailers --parse < <(git log -1 --format=%B)` — empty output for a trailer that should exist is a hard fail. See `knowledge-base/project/learnings/2026-05-16-git-trailer-parser-requires-contiguous-key-value-block.md`.

   **Heuristic:** "Can I write a commit message that describes a complete, valuable change? If yes, commit. If the message would be 'WIP' or 'partial X', wait."

   - **Commit each verified unit IMMEDIATELY — a worktree sync can revert uncommitted work with no warning.** `worktree-manager.sh` carries a "Syncing on-disk files from git HEAD" pass that restores tracked files to HEAD, and `.claude/hooks/guardrails.sh` can invoke it mid-session; anything verified-but-uncommitted is silently lost. Never hold verified work in the working tree across a long-running background job (a full test-all, a review agent). Where an edit must be followed by a commit, do BOTH IN ONE Bash call (`cat > file <<'EOF' … EOF; git add …; git commit`) so no window exists. Corollary: a reconciliation script that silently no-ops on a missing anchor (`python str.replace`, `sed s///`) will print success against a reverted file — assert the anchor (`assert old in s`) or the edit is unverified. **Why:** #6578 — two full re-applications of verified work; the revert was caught only because a re-run printed numbers that contradicted a result verified minutes earlier.

   **UX artifact heuristic:** "Did a specialist just produce or revise artifacts? If yes, commit with `wip: UX <description> for feat-X`. UX artifacts are high-effort and low-recoverability -- err on the side of committing too often rather than too rarely."

   The `wip:` prefix is intentional -- UX artifacts are valuable at every revision stage, and WIP commits are squashed on merge with no impact on final git history. Do not run compound before UX WIP commits -- compound runs once in Phase 4.

   **Compound-before-commit scope:** AGENTS.md Workflow Gates says "Before every commit, run compound." Within this skill, that rule applies to the **final Phase 4 commit** (the one that closes the feature), not to Phase 2 incremental commits. Running compound per incremental commit is recursive (compound creates commits) and defeats the point of incremental checkpoints. A single compound at Phase 4 covers the whole feature's session-error inventory and learnings.

   **Commit workflow:**

   ```bash
   # 1. Verify tests pass (use project's test command)
   # Examples: bin/rails test, npm test, pytest, go test, etc.

   # 2. Stage only files related to this logical unit (not `git add .`)
   git add <files related to this logical unit>

   # 3. Commit with conventional message
   git commit -m "feat(scope): description of this unit"
   ```

   **Handling merge conflicts:** If conflicts arise during rebasing or merging, resolve them immediately. Incremental commits make conflict resolution easier since each commit is small and focused.

   **Note:** Incremental commits use clean conventional messages without attribution footers. The final Phase 4 commit/PR includes the full attribution.

4. **Follow Existing Patterns**

   - The plan should reference similar code - read those files first
   - Match naming conventions exactly
   - Reuse existing components where possible
   - Follow project coding standards (see CLAUDE.md)
   - When in doubt, grep for similar implementations
   - **An acceptance checkbox is a CLAIM — never bulk-toggle `- [ ]` → `- [x]`, and never append to a markdown table row past its closing pipe.** Two write-time foot-guns that both convert unverified work into work that reads as verified. (a) A bulk checkbox replace marks every AC "verified" at once with zero verification performed; run each AC's command and let the output decide (in #6781 a bulk toggle marked 15 ACs done and AC13 was then measured FALSE). This is the `session-state.md` decisions-are-intent rule applied to your own artifact in the same session. (b) Appending prose after a table row's trailing `|` creates a cell beyond the header count, and GFM **discards** it — so the text survives in raw markdown, passes any grep-based AC, and renders as though the edit never happened. That shipped an Article 30 statutory-register amendment that displayed as unamended. Cheapest gate after any table-row edit: `awk '{n=gsub(/\|/,"|"); print NR, n}' <file>` and compare the row's pipe count against a sibling row. See `knowledge-base/project/learnings/2026-07-21-the-guard-i-shipped-could-never-have-fired-and-my-fake-certified-it.md`.
   - **Before writing a new format, date, or util helper in any app, `ls` + grep the app's canonical `lib/` directory (e.g., `apps/web-platform/lib/`) for equivalents.** Canonical helpers are often single-purpose small files named by verb (`relative-time.ts`, `format-currency.ts`); typecheck and tests will not catch duplicated logic. See `knowledge-base/project/learnings/2026-04-17-grep-lib-before-writing-format-helpers.md`.
   - **When the plan says "mirror precedent X 1:1" but the new table/RPC reuses a precedent column for a NEW role X never had (a fencing token, a WORM-audit row, a portability-export field), enumerate the new role's invariants and check each against the precedent's lifecycle — a passing 1:1 mirror is NOT proof of correctness.** A precedent's guarantees hold only for the role it was built for: `acquire_conversation_slot` (029) is a concurrency slot, so its DELETE-on-release is correct there but silently breaks a *fencing-token* contract (the next acquire resets `lease_generation` to the column default → the git-data `reject gen < max` fence inverts into a write outage). The fix lives at the lock service, never the resource server; route the data-model fork to the `cto` agent. tsc + the precedent-cloned ACs pass green — only `architecture-strategist`, prompted with the downstream contract (the ADR), catches it. **Why:** #5274 PR A — DELETE-on-release vs ADR-068 §3 monotonic-max; CTO ruled tombstone-on-release. See `knowledge-base/project/learnings/best-practices/2026-06-30-precedent-mirror-for-new-role-breaks-fencing-token-monotonicity.md`.
   - **When the plan's specified path is wrong and you correct it during implementation, immediately `git grep` the corrected path's basename across the diff scope and fix EVERY secondary citation in the same edit cycle.** The plan often appears as an authoritative path source in multiple secondary artifacts (Article 30 register entries, runbooks, ADRs, README references); fixing only the primary landing site leaves a silent drift the reviewer must catch. The plan is authoritative for intent, never for paths (`hr-when-a-plan-specifies-relative-paths-e-g`). **Why:** PR #4287 — plan §6.2 named `knowledge-base/engineering/runbooks/cron-retention-monitor.md`; runbook landed at the correct `engineering/operations/runbooks/...` but the PA-20 Article 30 entry cited the plan's wrong path; caught at multi-agent review by `git-history-analyzer`. See `knowledge-base/project/learnings/2026-05-22-or-semantics-allowlist-inverse-lint-and-keyset-cursor-tiebreak.md`.
   - **When you DELETE an entity from an enumeration in prose, grep the SAME sentence/cell/bullet for clauses whose SUBJECT was that entity — a claim family is removed whole or not at all.** Deleting the head silently re-points its dependent clauses at whatever remains, which can make a FALSE claim strictly worse: bound to a named phantom (`…web-2 plus a dedicated git-data host. Stored workspace git data sits on a LUKS-encrypted volume…`) the tail reads as a claim about *that host*; unbound it reads as a claim about the **live** substrate. Litmus: after removing X from "…A, B, and X. X does P, Q, R." — ask *what does "does P" now attach to?* If the answer changed, you rewrote a claim you never meant to touch. Verify mechanically (per-file clause counts byte-identical to `main`), never by eye. Prose sibling of `cq-ref-removal-sweep-cleanup-closures`. **Why:** #6538/PR #6568 — removing a never-provisioned git-data host left its LUKS encryption-at-rest clause dangling onto `hcloud_volume.workspaces` (plain `ext4`), converting a scoped falsehood into a live false Art. 32 claim on the published privacy policy; 4 review agents converged, the edit cycle never saw it. See `knowledge-base/project/learnings/2026-07-16-removing-a-false-claim-can-strengthen-the-false-claim-that-leaned-on-it.md`.
   - **Sweep the SEMANTIC quantity, not its formatted representation.** A stale-figure sweep anchored on exact literals (`grep -E '176\.11|595\.82|92\.81'`) misses the same quantities written as rounded prose (`~$176/mo`, `4 paying users`, `~93%`) — and rounded prose is where *outward-facing summary sections* live, so the miss lands on the highest-consequence text. Enumerate the derived figures first (subtotal → each break-even → each margin → each rounded restatement), then grep per figure. Same root as `cq-assert-anchor-not-bare-token`. **Why:** #6538 — a "clean" sweep left §6 Pricing Gate asserting the exact `~93%` framing §5 retired one screen above.
   - **Before offering the operator options on a governed surface, read the governing rubric — an option the rubric forbids is not a choice, it is a trap.** Consent/versioning/retention surfaces carry signed policies (`knowledge-base/legal/tc-version-bump-policy.md`) that pre-decide the option space; presenting a forbidden option gets it chosen, then retracted. **Why:** #6538 — offered "repin SHA, no `TC_VERSION` bump" for a T&C edit; the CLO-signed rubric makes Tier 3 (no bump) *typos/whitespace/markdown only* and Tier 2 clarifying **BUMP REQUIRED**, tie-break *"if unsure, treat as clarifying"*. The operator's real intent (no forced re-acceptance) was served by not editing the T&C at all.
   - **When you INSERT or DELETE lines in a doc, every `path.md:N`/`:N-M` line-number citation pointing INTO that doc (from the plan, tasks.md, PIR, ADRs, sibling runbooks — including files this PR isn't "about") goes stale below the edit point.** After the insertion, `grep -rn '<doc-basename>:[0-9]' knowledge-base/` and fix every hit in the SAME edit cycle; for churn-prone targets, prefer an insertion-stable section/anchor reference over a bare line range. tsc/tests are blind to prose offsets — review catches it as a P2 round-trip. **Why:** #5548 — a 10-line runbook §A callout shifted `:71-74`→`:81-84` and `:126`→`:132` across plan/tasks/PIR; caught by pattern-recognition + code-quality. See `knowledge-base/project/learnings/best-practices/2026-06-18-doc-insertion-stales-cross-artifact-line-citations.md`.
   - **Plan-prescribed redaction filters for captured-real fixtures are intent, never authority. Audit the filter against every secret-class the artifact can contain before executing it.** When a plan instructs "capture real provider output → run jq redaction → commit as fixture" (terraform-show-json, supabase log dumps, sentry event payloads, vendor API captures), the prescribed jq filter is a starting point — not a sufficient scrub. Same shape as `hr-when-a-plan-specifies-relative-paths-e-g`: plan is authoritative for intent (which fields to scrub), never for completeness (which fields exist). Concretely: for `terraform show -json` captures, **always** prepend `del(.variables)` regardless of the plan's prescribed filter — terraform-show-json embeds plan-input variables verbatim including `sensitive=true` declarations (`sensitive` masks render-time text output, NOT JSON serialization). After redaction, run a mandatory canonical scan: `! grep -qE 'BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9_]{20,}|ghs_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-ant-api03-[A-Za-z0-9_-]{20,}|sk_(test|live)_[A-Za-z0-9]{20,}|sbp_[A-Za-z0-9]{20,}|xoxb-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|dp\.(pt\|st\|sa\|ct)\.[A-Za-z0-9_-]{40,}' <fixture>` — must return rc=1 (no matches). A token-prefix-only scan (the plan's typical `no token values, no actor IDs` framing) misses PEM headers. **Why:** PR #4420 — the captured-real fixture initially shipped with the full GitHub App RSA private key embedded under `.variables.github_app_private_key.value`; caught at post-implementation multi-agent review by `security-sentinel` AFTER 9 other agents had read the file. Full incident post-mortem at `knowledge-base/project/learnings/security-issues/2026-05-25-terraform-show-json-leaks-sensitive-variables-into-fixtures.md`. Backstop: PreToolUse hook `git-commit-secret-scan.sh` runs gitleaks on the staged index at every `git commit` regardless of `.git/hooks/pre-commit` installation state.
   - **Before writing data-layer tests that use new PostgREST operators, read the shared mock helper (e.g., `apps/web-platform/test/helpers/mock-supabase.ts`) to confirm it covers every operator the code under test uses.** If not, extend it at the START of Phase 2, not after the first cryptic test failure.
   - **When a change adds or edits a Supabase embedded `.select(\`…\`)` against an UNTYPED client, neither `tsc` nor a select-arg-discarding mock catches a non-existent column — it ships green and errors with Postgres 42703 at runtime (silently returns `[]`). Add an arg-capturing select-string test (capture `chain.select.mock.calls[i][0]`, assert no `auth.users`-only column like `raw_user_meta_data`) AND/OR an opt-in `*.integration.test.ts` vs dev. The embed FK target `users` resolves to `public.users`, NOT `auth.users`.** See `knowledge-base/project/learnings/2026-06-01-untyped-supabase-select-nonexistent-column-ships-green.md` (#4715/#4713).
   - **A supabase-js `.update()/.delete().eq(...)` returns NO error when the WHERE matches 0 rows — a write whose success path returns 200 WITHOUT reading back what it wrote silently no-ops (the active id has no row / a stale resolved-id).** Append `.select("id")` and assert `data.length === 1` (`!== 1`, not `< 1`) → fail loud + distinct Sentry breadcrumb instead of a false success. A sound robustness guard — but do NOT assume a 0-rows no-op is the cause of a "didn't persist"-shaped bug without a live read proving the row is actually absent (see the cautionary case below). Mirrors `.update().select()` precedents in `account-delete.ts`/`ws-handler.ts`. See `knowledge-base/project/learnings/bug-fixes/2026-06-08-supabase-update-eq-zero-rows-silent-noop-and-code-trace-repro.md`.
   - **A route that 302-redirects a browser asset (`<img>`/`<script>`/`<link>`) to a SIGNED STORAGE URL must emit it on a host present in the matching CSP fetch directive.** `createServiceClient` signs against `SUPABASE_URL` (raw `<ref>.supabase.co`), but CSP `img-src` is built from `NEXT_PUBLIC_SUPABASE_URL` (the public custom domain) — so the redirect target is silently CSP-blocked in the browser (`onError` → fallback) while server-side `curl` succeeds (no CSP). Rewrite the signed URL's origin to `NEXT_PUBLIC_SUPABASE_URL` before redirecting; grep `createSignedUrl` whose result reaches the browser and confirm its host is in the CSP directive. **Why:** #4996→#5012 — workspace logo persisted + served 200 but never displayed; the 302 host was absent from `img-src`. See `knowledge-base/project/learnings/bug-fixes/2026-06-08-supabase-update-eq-zero-rows-silent-noop-and-code-trace-repro.md`.
   - **When extending a Supabase wrapper module (e.g., `apps/web-platform/server/conversation-writer.ts`) with a new chained method (`.eq`, `.select`, `.in`, `.maybeSingle`, etc.), grep `apps/web-platform/test/` for every supabase mock chain — both shared helpers (`test/helpers/*-mocks.ts`) AND inline `vi.mock("@supabase/supabase-js", ...)` setups — and extend each one in the same edit cycle.** `tsc` is silent on chain-shape drift; only the full vitest suite catches it. Recursive-by-default mock chains (every chained call returns the same chain object) survive future extensions transparently. Same class as `cq-raf-batching-sweep-test-helpers` and `cq-preflight-fetch-sweep-test-mocks` but for the data-layer fluent API. See `knowledge-base/project/learnings/best-practices/2026-04-27-wrapper-extension-test-mock-chain-sweep.md`.
   - **When source-SWAPPING the data source a shared hook reads (e.g. `use-conversations` repo scope moved from `users.repo_url` to `fetch("/api/workspace/active-repo")`), the test blast radius is {tests importing the hook} − {tests that `vi.mock` the hook away}.** Derive it via `git grep -l '<hookName>' apps/web-platform/test/` minus the `vi.mock("@/hooks/<hook>"` set, and stub the NEW source in every one. Never name-filter that list by topic — page-level renderers (`command-center.test.tsx`, `start-fresh-onboarding.test.tsx`) render the real hook without the feature word in their filename, so a topical grep silently drops them and they fail only at the full-suite exit gate. **Why:** PR #5317. See `knowledge-base/project/learnings/best-practices/2026-06-15-hook-source-swap-sweep-all-real-hook-renderers-not-name-filtered.md`.
   - **When adding a SECOND `.on()` registration to a Supabase Realtime channel chain (e.g. adding an `event: "INSERT"` handler beside an existing `"UPDATE"`), every test whose channel mock returns a non-chainable subscribe-only stub from `.on()` (`vi.fn().mockReturnValue({ subscribe })`) breaks with `on is not a function`.** Same blast radius as the `.from()`-chain sweep above, for the realtime channel API: `git grep -l '<hookName>' apps/web-platform/test/` minus the `vi.mock("@/hooks/<hook>")` set, and make each channel mock chainable (`.on()` returns the channel object) in the same edit cycle. `tsc` is silent; only the full vitest suite catches it. Relatedly, a new realtime event handler that maintains a client list must scope-guard on the SAME columns the list query filters on (a subset surfaces rows the refetch drops). **Why:** PR #5391. See `knowledge-base/project/learnings/best-practices/2026-06-16-realtime-event-guard-must-equal-fetch-query-scope.md`.
   - **When an ADR/migration relocates a state column AND migrates SOME consumers to a new resolver (e.g. ADR-044's `users → workspaces` + service-role `resolveActiveWorkspaceKbRoot`), the migration is NOT done until `git grep <oldResolver>` returns 0 — WRITE routes (`kb/share`, `kb/upload`) are consumers too and are easy to miss because the READ routes already "work."** An unmigrated write route keeps the old resolver's divergent failure surface (here: a tenant-scoped read of stale `users.workspace_status` → silent 503), and if that route has un-mirrored failure branches the divergence is invisible until a user hits it. Pair the consumer-sweep with an observability pass over the unmigrated route's silent returns (mirror each to Sentry with `reason=<code>`) BEFORE/with the swap so the fix is confirmed, not assumed; and when the new resolver returns an id that downstream code reuses, thread the ONE resolved id through all sites (a second independent resolve re-introduces divergence). **Why:** PR #4953 — share/upload left on `resolveUserKbRoot` after ADR-044. See `knowledge-base/project/learnings/best-practices/2026-06-05-adr-resolver-migration-must-sweep-write-routes-not-just-read-routes.md`.
   - **When a change adds real parsing/validation of an input (a private key via `createPrivateKey`, a JWT, a config blob) that runs BEFORE a mocked constructor/boundary, sweep every test that stubs that input — not just the test for the file you edited.** Mocking the downstream SDK (`vi.mock("@octokit/app")`) no longer shields tests from malformed placeholder fixtures once real parsing runs first; bogus stub keys (`"…BEGIN RSA PRIVATE KEY…\nfake\n…"`) start throwing at parse time. Grep `git grep -lE '<ENV_OR_FIXTURE_NAME>' -- 'test/**'`, and for each hit decide whether it exercises the REAL factory (replace the stub with a synthesized real value via `generateKeyPairSync`, per `cq-test-fixtures-synthesized-only`) or mocks the factory wholesale (fixture irrelevant — no change). See `knowledge-base/project/learnings/2026-05-29-credential-parsing-before-mocked-sdk-breaks-stub-key-fixtures.md`. Redundant mutations mask trigger regressions — production signup silently breaks while the test keeps passing. Turn the setup step into a canary: read the row the trigger should have created, assert it exists. See `knowledge-base/project/learnings/security-issues/2026-04-18-rls-for-all-using-applies-to-writes.md`.
   - **When extracting a pure reducer out of a React hook, migrate ALL companion state (refs the reducer reads or writes) to the reducer's state boundary in the same change.** A half-extraction — pure function plus mutable ref inside a `setState` updater — advertises purity the call site doesn't honor and recreates the StrictMode/concurrent-rendering hazard the extraction was meant to eliminate. See `knowledge-base/project/learnings/best-practices/2026-04-14-pure-reducer-extraction-requires-companion-state-migration.md`.
   - **When extracting an `async` body out of a `useEffect` into a `useCallback`/helper for reuse, carry the effect's CLEANUP-scoped state with it (cancellation flag, AbortController, interval/timeout/subscription teardown).** The lift looks mechanical but strips the callback of the effect lifecycle — a stale fetch can resolve after the precondition changed and clobber newer state. Restore via a liveness predicate the caller owns (the effect passes `() => active` and flips it on cleanup; synchronous callers default to always-current). tsc + happy-path tests pass; only a stale-response test or multi-agent review catches it. **Why:** PR #4947 — `checkShare` extraction in `share-popover.tsx` dropped the `cancelled` guard. See `knowledge-base/project/learnings/best-practices/2026-06-04-extracting-fetch-effect-to-usecallback-drops-cancellation-guard.md`.
   - **When extracting a module-level `export const NAME = ...` binding to a new module and re-exporting from the source, grep the source file for internal `NAME` references and add a sibling `import { NAME } from "./new-module"` — the re-export alone does NOT put `NAME` back in local scope.** `tsc --noEmit` flags this as TS2304 but ESM-friendly bundlers may silently swap in `undefined`. Same class as `cq-ref-removal-sweep-cleanup-closures` but for module-level bindings. **Why:** #2653 — see `knowledge-base/project/learnings/2026-04-19-enoent-on-optional-mount-should-not-alarm.md` session errors.
   - **When extracting inline logic into a NEW module, the new module's STATIC import graph loads wherever it is statically imported — a symbol previously reached via lazy `await import()` becomes eager.** Importing a heavy module just for one symbol (an error class for `instanceof`, a constant) drags its module-init side effects (top-level `createChildLogger`, `promisify(execFile)`, client construction) into every consumer's test-collection graph and crashes sibling tests with incomplete mocks. Use `import type` + duck-type (`err.name === "ByokLeaseError" && err.cause === "escape"`) or a lazy thunk. ALSO: a new `server/**` file importing `createServiceClient` must be added to `.service-role-allowlist` in the same commit, and you MUST run the EXISTING tests that exercise the extracted code path (`vitest run test/<donor>-*.test.ts`) — the new file's own test + `tsc` passing is not sufficient; the full-suite exit gate is what catches it. **Why:** PR #5409 — `auto-sync-trigger.ts` extraction pulled `byok-lease`'s static graph into `/api/repo/setup` and missed the allowlist. See `knowledge-base/project/learnings/best-practices/2026-06-16-extracting-helper-from-route-pulls-heavy-static-graph-and-misses-existing-tests.md`.
   - **When a caller of `reportSilentFallback` runs in an environment where the "error" path is a known degraded state (e.g., `readdir` on an optional mount that doesn't exist in dev/CI), filter the error code before paging.** ENOENT on a configured-but-optional path is not a silent fallback — it's a documented zero, and routing it through Sentry exposes every request to any bug in the alarm pipeline itself. Only page on truly unexpected errors (EACCES, I/O, pathological). **Why:** #2653 — same learning file.
   - **After any content-move or template port that preserves `{{ site.url }}<path>` interpolations from the source, build the site and grep rendered output for host-letter concatenation artifacts.** `{{ site.url }}` + path-without-leading-slash produces `https://soleur.aiblog/...` when `site.url` has no trailing slash — Eleventy emits it without warning; source-grep cannot detect it (the source diff is plausibly "consistent with the original"). Cheapest gate: `grep -oE "https://${HOST}[a-zA-Z]" _site/<page>/index.html` — every hit is broken. **Why:** #2705 — see `knowledge-base/project/learnings/best-practices/2026-04-21-eleventy-site-url-concatenation-broken-without-leading-slash.md`.
   - **When editing a `"use client"` component or a `lib/` module reachable from client code, never import from `@/server/observability` or any `@/server/*` module that transitively pulls `pino`.** `next.config.ts` `serverExternalPackages` only externalizes for the server chunk; pino will bundle into the browser. Use `@/lib/client-observability` (a thin `@sentry/nextjs`-only shim) or add a new shim with the same signature. Verify with `grep -rn "@/server" <new-or-edited-file>`. **Why:** PR #2860 — see `knowledge-base/project/learnings/2026-04-23-render-time-scrub-sentinels-and-client-bundle-boundaries.md`.
   - **Any textual tokenize-scrub-restore pipeline (stash regex matches under placeholders, scrub the remainder, restore from an index) must use a per-call random sentinel (≥24 bits of entropy) and THROW on out-of-range restore indices.** Human-readable placeholders (` PRESERVED_N `, `__TOKEN_N__`) are a substitution oracle — assistant-controlled prose containing the literal splices in stashed content, and `?? ""` fallback silently deletes the literal. Pattern: `SOLEUR_PRES_${8hexchars}_${i}`. **Why:** PR #2860 — same learning file.
   - **Debounce/throttle "not-yet-fired" sentinels must be `undefined` or `-Infinity`, never `0`.** Combined with `vi.useFakeTimers({ now: 0 })`, a `0` default produces `Date.now() - 0 >= threshold` = false on the first fire, starving the very path the debounce was supposed to time. Use `if (last === undefined || now - last >= THRESHOLD_MS)`. **Why:** same learning file, session error #3.
   - **When the diff touches `bun.lock` AND the bump is intended to be transitive-only (e.g., a Dependabot security bump), use the surgical-lockfile-edit pattern in [work-lockfile-bumps.md](./references/work-lockfile-bumps.md) as the first attempt.** Never `bun update <pkg>` (elevates the target to a direct dep) or bare `bun update` (bumps every direct caret-ranged dep). Validate with `bun install --frozen-lockfile`. **Why:** PR #3488 — three failed bun invocations rediscovered the constraint at task time.
   - **When a new call site needs coverage by a boundary-enforcing drift-guard whose walk array (`*_DIRS`/`*_PATHS`/`*_GLOBS`) does NOT include the new file's directory, extract the call site into the existing scope — do NOT widen the walk.** The guard encodes an architectural convention ("auth verbs live in `app/(auth)` + `components/auth/`", "CSRF coverage applies to `app/api/`", etc.). Widening the array to absorb one new call site (e.g., adding `app/(dashboard)` because a single `(dashboard)/layout.tsx` calls `signOut`) inverts the convention into "any file in this whole route group that happens to call the verb must carry the guard's tags." The shortest path leaves a worse architecture. Refactor to a hook/util living in the existing scope (`components/auth/use-sign-out.ts`) so the guard's directional rule is preserved. **Why:** PR #3576 — see `knowledge-base/project/learnings/2026-05-11-drift-guard-scoping-extract-call-site-not-widen-walk.md`.
   - **When a migration changes a SECURITY DEFINER RPC's signature for which prod callers exist, prefer overloading (additive `CREATE OR REPLACE` with a new parameter list) over `DROP FUNCTION` + `CREATE`.** Postgres distinguishes overloads by parameter list; supabase-js sends named-arg PostgREST envelopes that route to whichever overload matches by parameter name. Overloading is rolling-deploy-safe: (a) prd-schema-without-app keeps the v1 signature alive for old pods; (b) prd-app-without-schema keeps writes succeeding because the v1 signature still exists. DROP+CREATE creates a window where one direction silently zeros the write path. Drop the v1 in a follow-up migration after the old build ages out. **Why:** PR #3626 — see `knowledge-base/project/learnings/2026-05-12-stub-handlers-as-silent-undercount-vectors.md`.
   - **When a grant-flip / SECURITY DEFINER migration mirrors a precedent that ships a paired `apps/web-platform/supabase/verify/NNN_*.sql` runtime sentinel, carry the verify sentinel forward in the SAME PR.** The migration-shape regex test asserts the GRANT *text* exists but cannot catch a *live* GRANT mismatch post-apply (`2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`); the `verify/` sentinel (run by CI's `verify-migrations` job via `has_function_privilege('authenticated', …) = false`) is the only runtime guard for the privilege-escalation class. Cheapest gate: `ls apps/web-platform/supabase/verify/<precedent-NNN>_*.sql` when copying the precedent — if present, author the sibling `verify/<new-NNN>_*.sql` alongside the migration. **Why:** PR #4768 (#4765) — `verify/092` was forgotten at work-time and caught by `pattern-recognition-specialist` at review; see `knowledge-base/project/learnings/security-issues/2026-06-01-caller-override-rpc-needs-service-role-only-grant.md`.
   - **Stub event handlers ("wire in Stage N when X lands") in dispatcher/router code are silent telemetry-loss vectors.** A no-op handler that satisfies the type system, sits next to fully-wired siblings, and has no error path is invisible to skim-review and Sentry alike. Either throw `Error("handler not yet wired: <name>")` until the wiring lands, OR fan out to an instrumentation counter so a "stub still present" alert can fire. **Why:** same PR #3626 — `cc-dispatcher.ts:1202` `onResult` shipped as a no-op for 3 weeks (originally added 2026-04-24 #2858), under-counting API cost by 60-90% for every cc-soleur-go conversation while the legacy path's wiring made the surface look complete.
   - **When extending or mirroring a parallel runner/dispatcher/writer path (e.g., cc-dispatcher mirroring agent-runner), grep BOTH role-side persistence calls in the new path AND the reference path before declaring the implementation done.** If the new path has only one role's `from("messages").insert(...)` (or equivalent persist) and the reference has multiple, the asymmetry will land as a UI bug downstream via the resume hydration code (`api-messages.ts` → reducer state → `isClassifying`-style gates). Cheapest gate at work time: `grep -n "saveMessage\|messages.*insert" <new-path>` + `grep -n "saveMessage" <reference-path>`. Role-count parity must match or the divergence must be documented with rationale. **Why:** PR #3286 — cc-dispatcher persisted only the user role; agent-runner.ts:1079 persisted both; the gap surfaced as a "Continue thread" routing-chip regression that PR #3251 made visible. See `knowledge-base/project/learnings/integration-issues/2026-05-05-cc-dispatcher-assistant-persistence-asymmetry.md`.
   - **A new server→client WS turn-boundary lifecycle hook (turn-reset, per-turn binding, telemetry, cost gate) must be wired into BOTH turn-boundary entry points — the legacy fan-out (`sendUserMessage` → `dispatchToLeaders`) AND cc-soleur-go (`dispatchSoleurGoForConversation`), which `break`s before `sendUserMessage` and NEVER calls `registerSession`.** Any state normally populated by `registerSession` (e.g. a userId→conversationId binding) must be set explicitly on the cc path. Cheapest gate: `grep -n "<your new hook>\|resetTurn\|registerSession" apps/web-platform/server/*.ts` and confirm a call on BOTH lineages — cc-soleur-go is the dominant production path (#3270), so wiring only the legacy path silently breaks the feature for nearly all traffic with green CI. **Why:** PR #5290 (#5273) — `streamReplayBuffer.resetTurn` + the active-turn binding were wired only in `sendUserMessage`; cc gap-emitted frames were silently dropped (empty replay) until multi-agent review caught it. See `knowledge-base/project/learnings/integration-issues/2026-06-14-ws-lifecycle-hook-must-cover-both-legacy-and-cc-soleur-go-turn-boundaries.md`.

5. **Test Continuously**

   - **RED**: Write a failing test before implementing any new behavior
   - **GREEN**: Write the minimum code to make the test pass
   - **REFACTOR**: Improve code while keeping tests green
   - Run the full test suite after each RED/GREEN/REFACTOR cycle. When running test suites via Bash, always capture both failure details AND summary in a single run — use `grep -E "(FAIL|ERROR|Test Files|Tests )"` or `| tail -30`, never `| tail -10` which discards failure names and forces a wasteful second run. **Why:** In PR #2430, `| tail -10` discarded failing test names, requiring a full re-run just to identify which 2 of 1580 tests failed.
   - The agent harness's `bash -c` does NOT inherit `set -o pipefail`, so `bash <test-script> 2>&1 | tail -N` reports `tail`'s exit (always 0) and silently swallows the test runner's non-zero exit. For aggregate test scripts whose pass/fail signal is load-bearing ([scripts/test-all.sh](../../../../scripts/test-all.sh), `bun test`, `pytest`, `go test ./...`), prefer `log=$(mktemp -t <script>.XXXXXXXX.log); bash <script> > "$log" 2>&1; rc=$?; echo "EXIT=$rc LOG=$log"` and inspect `rc` explicitly; only then `tail` or `grep` `"$log"` for context. **Why:** PR #4011 — a `bash test-all.sh 2>&1 | tail -40` invocation reported exit 0 while the runner exited 1 (3 pre-existing failed suites); the false-pass nearly chained through to ship. See `knowledge-base/project/learnings/2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md` §1.
   - **`mktemp`, never a name derived from the script.** A path built from the script name is a pure function of it, so every concurrent session writes the SAME file — and parallel worktrees are this repo's documented workflow. Observed 2026-07-15: a full-suite log was truncated mid-run by a sibling session and came back holding a DIFFERENT worktree's absolute paths; `rc` was still correct, but the log — the artifact you read to learn WHICH suite failed — was someone else's. Echo `LOG=$log` so the path is recoverable, and keep `rc` as the pass/fail signal: a clobbered log costs a re-run, but reading a SIBLING's green log and concluding your own run passed is the failure that ships. `$$` is not a fix either (predictable across concurrent runs in shared shells — `token-efficiency-report.sh:36-56` rejected it for the same reason). Use a workspace/git-dir-scoped path instead only when a LATER, separate Bash call must find the artifact by name.
   - When running test/lint/budget commands from inside a worktree pipeline, chain `cd <worktree-abs-path> && <cmd>` in a single Bash call, or use absolute paths. CWD *does* persist between Bash calls, but relying on ambient CWD is fragile: any intervening call that `cd`s elsewhere (a prior `cd "$(mktemp -d)" && git clone ...`) silently redirects everything after it to the wrong tree — and in this repo the bare repo root holds stale synced copies of tracked files, so the failure surfaces as wrong pass/fail counts that look like real regressions rather than a missing-file error. **Why:** PR #2683 `bun test` reported 1005/1 (baseline-state result) from bare root after a *drifted* CWD; worktree re-run was 1006/0. See `knowledge-base/project/learnings/bug-fixes/2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md` session errors.
   - **The invariant a suite enforces on the SUT applies to the HARNESS — grep the test file for the shape it forbids.** A suite written to forbid `X | grep -q` under `pipefail` (SIGPIPE → 141) used exactly that at 12 of its own assertion sites; on every NEGATIVE assertion (`if ! calls | grep -q …`) the 141 fails **OPEN**, so those cases and their mutation twins reported green while the property was violated — and the same shape in the `undef()` vacuity guard (whose sentinel is line 1, so the match is *always* early) let "must exit non-zero" cases pass against a script where the functions did not exist. Predicates must grep a FILE directly (`grep -qE -- "$pat" "$CALLS"`) or use bash `[[ == ]]`; never a pipe. Two adjacent vacuity traps from the same session: a multi-MB fixture passed via `env` exceeds the argv limit (E2BIG) so the subshell dies BEFORE any precondition (pass large fixtures by file), and a stub ending in `return 0` swallows the producer SIGPIPE its mutation exists to reproduce (`return $?`). Give every happy-path case a `CASE_RC` positive control — assertions that read a calls-file populated before an unrelated `die` pass without the function ever succeeding. **Why:** #6588 — the class was documented one day earlier and recurred in the file meant to pin it. See `knowledge-base/project/learnings/2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md`.
   - When AUTHORING a `set -euo pipefail` accumulate-then-`exit` `.test.sh` (the `pass()`/`fail()`/`fails` convention), three foot-guns pass a naïve GREEN run and only bite on drift/edge inputs: (a) a deliberately-nonzero command (`diff`/`grep`/`comm`) inside a command substitution (`x="$(diff <(…) <(…) | tr …)"`) makes `set -e` abort BEFORE `fail()` prints — wrap it `… || true` inside the `$(...)` and gate on `[[ -z "$x" ]]`; (b) a loop derived from a data source (registry/array/file via `done < <(node …)`) silently `exit 0`s with ZERO coverage on an empty/unreadable source — process-substitution failure escapes `set -e`, so add a minimum-cardinality guard (`n=0; …; n=$((n+1)); …; [[ "$n" -lt 1 ]] && fail`); (c) a verify-the-verifier negative that injects a CONSTANT guaranteed-absent tests the coreutil (`diff(A+x,A)≠∅` is always true), not the gate — route real data through the production idiom and assert the injected token on the specific diff side. Mutation-test every drift class and confirm a CLEAR MESSAGE prints, not just `exit 1`. **Why:** PR #5721 (#5703) — all three surfaced authoring `registry-completeness.test.sh`; (a) caught by self-mutation-test (truncated log), (b)+(c) by multi-agent review. See `knowledge-base/project/learnings/test-failures/2026-06-29-bash-accumulate-then-exit-gate-test-three-footguns.md`.
   - In a `set -o pipefail` gate, `producer | grep -q PATTERN` flakes to a FALSE NEGATIVE when the match is EARLY and the producer streams (`sed` from a `strip_comments`, or a `printf` of a >64 KB body): `grep -q` closes the pipe on first match, the producer takes SIGPIPE (141), and `pipefail` makes the pipeline exit non-zero *even though grep matched* — so `&& echo 1` is skipped. Invisible on the first green run and on append-mutations (match lands at EOF, no early close); only a `holds` pattern matching near the top flakes. Use a herestring (`grep -Eq PATTERN <<<"$var"` — no pipe) or `grep -Ec` (`[ "$(… | grep -Ec PATTERN || true)" -gt 0 ]` — reads all input), never `grep -q` on a pipe. **Why:** #6649 — `workspaces-luks-header.test.sh` H4/H11 passed then failed with no change. See `knowledge-base/project/learnings/test-failures/2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md`.
   - A golden-parity / "compare new-impl vs old-impl" `.test.sh` must pin its OLD baseline to a **frozen committed fixture** (`test/fixtures/legacy-*.sh`), NEVER to `git show <mainbranch>:<the-file-this-PR-replaces>` — that file BECOMES the new implementation at merge, so the baseline flips and the suite reddens on `main` for the next contributor (green on the branch, a merge-time time-bomb). Same class as the worktree-vs-main-CWD trap. Also pin `LC_ALL=C` on any `sort`+`comm` set-diff (a locale sort makes `comm` read its input as unsorted → undefined diff → the parity guard runs blind). **Why:** #5987 — Test 5a/9 fetched `git show main:redact-sentinel.sh` as the "old engine"; caught by `code-quality-analyst` at review. See `knowledge-base/project/learnings/test-failures/2026-07-05-parity-baseline-must-not-be-git-show-main-of-the-replaced-file.md`.
   - For a `run_in_background: true` Bash whose body is `<cmd> > /tmp/log 2>&1; echo "EXIT=$?"`, the harness's task-completion notification reports the exit of the **trailing `echo`** (always 0) and the real command's output landed in `/tmp/log`, NOT the background task's output file — so a "completed (exit code 0)" notification is NOT proof the command passed. Either drop the redirect (let the bg output file capture stdout/stderr directly), or ALWAYS grep the redirected log for the runner's own summary (`vitest "Tests N failed"`, `playwright "N failed"`, `Failed to compile`) before trusting a background pass. **Why:** #5512 — `next build` and the full `vitest run` both reported a misleading bg "exit code 0" while the redirected logs held the real failures (a build route-table line and 3 Doppler-env flakes respectively).
   - When the project pins a test runner via `devDependencies` (e.g., `vitest@3.2.4`), invoke `./node_modules/.bin/<tool>` — never `npx <tool>`. `npx` resolves to its own cache and silently major-version-jumps (e.g., installing vitest 4.x against a vitest 3.2.4 config), producing `Could not resolve 'vitest/config'` and `Unexpected JSX expression` parse errors that look like real regressions. **Why:** PR #3186 — `npx vitest` installed 4.x and rolldown rejected the project's JSX config; switching to `./node_modules/.bin/vitest` (3.2.4) restored a passing run. See `knowledge-base/project/learnings/2026-05-04-plan-precedent-search-must-include-lib-helpers.md` session errors.
   - Fix failures immediately -- never move to the next task with failing tests
   - When a class becomes hard to test (too many dependencies), extract an interface and inject dependencies. See the `/atdd-developer` skill for detailed TDD guidance.

6. **Infrastructure Validation**

   When any task modifies files in `apps/*/infra/`, run these checks after each change (in addition to or instead of the app test suite):

   1. **cloud-init schema**: For each modified `cloud-init.yml`:
      `cloud-init schema -c <file>` -- validates YAML syntax AND cloud-init schema in one step. Warnings about missing datasource are expected; only non-zero exit codes are failures. If `cloud-init` is not installed locally, warn and continue.
      - **When the `cloud-init.yml` is a Terraform `templatefile()` (interpolated in `server.tf`/`git-data.tf`/etc.), `cloud-init schema` on the RAW file always fails on the un-rendered `${...}` — validate the RENDERED output instead.** Render via `terraform console` (`printf 'templatefile("<abs>", { <full var map> })\n' | terraform -chdir="$(mktemp -d)" console`), strip the `<<EOT … EOT` wrapper, then `cloud-init schema -c <rendered>`. In the source template, shell `${VAR}`/`${VAR:-x}` must be `$${...}` (double-dollar escapes the TF interpolation) and `%{` must NOT appear at all — **including inside comments** (TF's directive scanner does not skip prose). Run the render after every edit; it catches both escaping traps. See `knowledge-base/project/learnings/best-practices/2026-07-14-cloud-init-templatefile-escaping-and-ci-deploy-payload-testing.md`.

   2. **Terraform format**: For each infra directory with modified `.tf` files:
      `terraform fmt -check <dir>` -- exit 0 means formatted; exit 3 means violations. Fix with `terraform fmt <dir>`.

   3. **Terraform validate**: For each infra directory with modified `.tf` files:
      `terraform init -backend=false` then `terraform validate` -- catches HCL syntax errors and undefined references without requiring provider credentials.

   4. **Field-type verification for version-pinned providers**: when writing HCL for a provider pinned below the registry's latest major (e.g., `cloudflare ~> 4.0`), verify field TYPES via `terraform providers schema -json` from a SCRATCH dir pinned to the exact version (minimal `required_providers` main.tf + `terraform init`) -- `validate` silently coerces wrong primitives (v4 `cloudflare_list` redirect items take `"enabled"`/`"disabled"` STRING enums, not booleans; registry/context7 docs show the latest major's syntax). The scratch dir matters: `providers schema` inside the real infra dir demands full backend init. **Why:** PR #5082 -- drafted booleans validated green and would have failed only at apply, behind a BLOCKING token-widen step that would have masked the diagnosis. See `knowledge-base/project/learnings/2026-06-09-cloudflare-bulk-redirects-v4-schema-and-phase-order.md`.

   These checks replace the "tests may be skipped" exemption for infra files. If any check fails, fix before proceeding to the next task.

   - **A fail-closed guard deciding on a LIVE API response must treat that response as adversarial input — a `200` is not proof of shape, and a `404` is trustworthy only per-URL-scheme.** Two fail-open seams recur: (a) a count over `.result.<field>` written as bare `jq '… | length'` reads a degraded/error `200` body (`{"result":null}`, `{"success":false}`, or a missing key) as `0 == empty == PASS` — jq's `null|length` is `0` and `jq -e` exits 0 on numeric `0`, so the intended "unparseable → fail-closed" branch never fires; gate on `if type=="array" then length else error` first. (b) a control probe that proves "`404` means empty" validates only the URL scheme it actually ran against — if the gate builds two schemes (`zones/$z/…` AND `accounts/$a/…`), a zone-only control leaves the account `404` seam wide open; add a per-scheme control (e.g. `GET accounts/$a/rulesets`, memoized) requiring `200` before trusting that scheme's `404`. And every fail-closed branch (incl. `known-after-apply` null URL fields serialized as `null` in the plan JSON) needs an isolating fixture that goes RED when only that guard is neutered. **Why:** #6767/PR #6833 — a green 31-assertion suite shipped both seams + 3 vacuous fail-closed branches; caught only by the multi-agent review panel. See `knowledge-base/project/learnings/2026-07-23-live-api-fail-closed-guard-counts-degraded-200-as-empty-and-control-probe-must-cover-every-scheme.md`.

   - **`[^\n]` in a POSIX ERE is a bracket expression excluding backslash and the LETTER `n` — not "any char but newline".** grep is line-oriented, so `.*` is the correct "rest of the line". The failure is silent and asymmetric: `grep -qE 'curl[^\n]*-m'` cannot cross `-o /dev/null` (it contains an `n`), so the POSITIVE assert fails loudly (fixable) while every NEGATIVE assert (`! grep -qE '…[^\n]…'`) passes VACUOUSLY — a broken regex never matches, so the guard reports clean forever. Sweep any `[^\n]` in a `.test.sh`/`toMatch` and replace with `.*`; mutation-test each negative assert to prove it can still fail. **Why:** #6537 — four structural asserts were silently unmatchable and two were vacuous negatives.
   - **In a Terraform `templatefile`, `%{` is a DIRECTIVE and must be escaped `%%{` — including inside comments** (the directive scanner does not skip prose; `hr-when-a-plan-specifies-relative-paths-e-g`'s sibling for template escaping). So a `curl -w '%{http_code}'`, a printf `%{...}`, or a doc comment quoting one makes the render fail outright — caught only by rendering, never by `terraform validate` on the `.tf`. Pair with the existing `$${VAR}` shell-escape rule and re-run the render (`.github/scripts/validate-infra-templates.sh <infra-dir>`) after every template edit. **Why:** #6537 — `-w '%{http_code}'` in `cloud-init-registry.yml`.
   - When a `terraform_data` remote-exec `inline` block carries assertions or probes, `"set -e"` MUST be the first element — terraform joins `inline` into ONE script with NO implicit errexit and fails only on the LAST command's exit, so any assert before a trailing `echo` is decorative (silent-green). `!`-prefixed pipelines are errexit-EXEMPT: write enforcement probes as explicit `if cmd; then echo FAILED; exit 1; fi`. **Why:** PR #5089 — the cron-egress provisioner's "merge-precondition" probes couldn't fail the apply; 5 review agents concurred; sibling sweep tracked in #5101.
   - When writing a token-anchored drift guard over HCL, match attributes with `attr[[:space:]]*=[[:space:]]*` (never single-space `attr = `) — `terraform fmt` re-aligns equals signs when a block gains a second attribute, silently blinding the guard to new blocks. Mutation-test by APPENDING a synthetic violating block (fmt-aligned, un-gated) to a copy, not just by removing a token from an existing well-formed one; and enumerate the invariant's targets across the whole infra directory's `*.tf`, not only the file the issue names. **Why:** PR #5132 (#5101) — `inline = \[` false-PASSed a fmt-aligned ungated block, and a same-defect block sat un-swept in sibling ci-ssh-key.tf; both caught only at multi-agent review.
   - When a test encodes a cross-file numeric inequality (budget/window drift guards), extract EVERY operand by shape from its source file — exactly-one count check + `^[0-9]+$` validation per extraction, region-scoped when the pattern recurs (awk range over the owning unit/function); a single hardcoded term re-creates the silent-drift class the guard exists to catch. For `${N:-DEFAULT}` shapes take `tail -1` of the digit runs (the default is the LAST run, not the first). **Why:** PR #5146 (#5145) — a copied `+180` TimeoutStopSec literal left one of three files unguarded; 4 review agents concurred. See `knowledge-base/project/learnings/2026-06-11-cross-file-drift-guards-extract-every-operand-by-shape.md`.
   - When cloud-init has `lifecycle { ignore_changes = [user_data] }`, changes to cloud-init templates are never applied to existing servers. Use a `terraform_data` provisioner with `remote-exec` to bridge the gap. Verify systemd services use `EnvironmentFile=` directives (not `/etc/environment`) for token injection.
   - When fixing syscall-level issues in Docker containers, test with `--privileged` first to establish a working baseline, then remove privileges one at a time. Docker's seccomp `includes.caps` is compile-time (evaluated when building BPF filter), not runtime -- processes gaining capabilities inside user namespaces do NOT gain access to capability-gated seccomp rules.
   - When a `terraform_data` provisioner writes a systemd unit or config file via `remote-exec` heredoc, extract the content to a standalone file and use `file()` in both `triggers_replace` and a `file` provisioner. Inline heredoc strings desync from the trigger hash -- partial strings in `triggers_replace` silently skip re-provisioning when the unit content changes.
   - When CLONING a `file` provisioner block, the destination's parent-dir existence is part of the precedent's ENVIRONMENT, not its copied HCL — Terraform's `file` (scp) does NOT create remote parents. Before reusing a `file`-provisioner shape, ask "what guarantees the destination dir exists on the host?"; if the precedent relied on a package (`/etc/fail2ban/jail.d/`) or an earlier provisioner creating it, add a `mkdir -p` `remote-exec` BEFORE the `file` provisioner. `/etc/<tool>.conf.d/` drop-in dirs are the recurring trap — many are NOT shipped by the base package (e.g. `/etc/systemd/journald.conf.d/` is absent on Ubuntu). `terraform validate`/`fmt` + static tests pass green; the failure is apply-time scp `No such file or directory`. **Why:** PR #4800 (#4792) — cloned `disk_monitor_install`'s shape but the journald drop-in dir didn't exist; caught at review. See `knowledge-base/project/learnings/integration-issues/2026-06-02-cloned-ssh-file-provisioner-does-not-inherit-target-dir-guarantee.md`.
   - When adding or removing files from a `triggers_replace` hash in `server.tf`, grep for `TRIGGER_FILES` in `plugins/soleur/test/` and `DEPLOY_PIPELINE_FIX_TRIGGERS` in `plugins/soleur/skills/ship/SKILL.md` — update all three locations in the same commit. The drift guard test catches this post-merge but costs a hotfix PR. **Why:** #4492 added 2 files to `triggers_replace` without updating the test array; CI failed post-merge (#4493 hotfix).
   - When adding a new `sudo <cmd>` (or any command) to a deploy/provision script exercised by a mock-PATH shell test (`ci-deploy.test.sh` et al., whose mock `sudo` strips the prefix and `exec`s the real binary), the harness needs a `create_mock_<cmd>` in `create_base_mocks` — and it must be a **pass-through** that no-ops ONLY for the host effect it cannot reproduce (e.g. `/mnt/*` volume paths) and delegates every other invocation to the real binary (fail loud `exit 1` if none found, never silent `exit 0`). A blanket no-op silently breaks sibling calls to the same command whose dirs the script later writes into. Symptom: a one-line script change makes MANY unrelated assertions fail at once (a `set -e` abort) — confirm by running unmodified origin/main files in an isolated dir before blaming the env. **Why:** #4886 — `sudo mkdir -p /mnt/data/workspaces/.cron` had no mock → real `mkdir` ENOENT'd on host `/mnt/data` → 33/79 failures. See [[2026-06-03-new-sudo-command-in-mocked-deploy-test-needs-passthrough-mock]].
   - When a `.test.sh` drift-guard asserts "the resource DELIVERS file X" by grepping a bare path, anchor the assertion to the delivery construct (`destination = "…/X"` AND `source = "${path.module}/X"`), NOT the bare path — a path that also appears in the block's `chown`/`chmod`/`test -x` lifecycle lines makes a bare-path grep pass vacuously even after the `provisioner "file"` delivery block is deleted. Prove non-vacuity by mutating out the delivery block and watching the guard go red. Also: invoke terraform with `terraform -chdir=<dir> <subcommand>` (never rely on a persisted `cd` — the Bash tool's CWD drifts unpredictably across calls). **Why:** #4811 — AC4 grepped `/usr/local/bin/infra-config-apply.sh` (recurs 4× in-block) and stayed green with delivery deleted; three terraform calls failed on CWD confusion. See [[2026-06-02-drift-guard-bare-path-grep-vacuous-and-terraform-cwd]].
   - Comment-prose sibling of the above: a `.test.sh` drift-guard whose grep target is a bare literal/boolean (`agent = true`, `enabled = false`) can false-PASS by matching that literal inside an explanatory COMMENT in the same awk-extracted block — and stays green-blind after the real config line changes. Anchor on a token only the real config line can carry (a `var.<name>` reference, an HCL operator like `== null`), never the bare literal. When fixing one named drift-guard, run a sibling-query audit (`grep -rln "<stale phrase>" apps/web-platform/infra/*.test.sh`) — false-passing siblings are invisible until grepped. **Why:** #4864 — `journald-config.test.sh` asserted literal `agent = true` (stale post-#4845's dual-context `agent = var.ci_ssh_private_key == null`); the sibling `infra-config-handler-bootstrap.test.sh` false-passed by matching the `#4829` comment prose. See [[2026-06-03-drift-guard-assertion-false-passes-on-comment-prose]].
   - When flipping a bash `${VAR:-default}` value, the consumer sweep MUST include surfaces that depend on the default by OMISSION (a CI step / cron / test that never exports the var) — a `grep VAR` finds explicit readers, never the unset-fallback consumers. Pin the old default explicitly at each such surface in the same PR, AND add one test that runs with the var genuinely unset (`env -i`), since a suite that always pins the var cannot detect a silent default revert. **Why:** #4806 — flipping `SOLEUR_DEFER_DRYRUN:-1` → `:-0` would have false-FAILed `test-pretooluse-hooks.yml` Test 6, which asserted `would_defer` while relying on the hardcoded default. See [[2026-06-02-env-default-flip-breaks-implicit-ci-consumer]].
   - When referencing `cloudflare_zero_trust_access_service_token.*.client_secret` (or any provider-managed credential attribute) in a Terraform `environment {}` block, check the provider docs for write-only attributes. The Cloudflare provider's `client_secret` is available at creation but empty on subsequent `terraform refresh`. Use Doppler variables instead of state references for credentials. **Why:** #4492 → #4494.
   - When HMAC-signing a payload and sending it via curl, always use `--data-binary @file` (not `-d @file`). curl's `-d` strips newlines from the file content, creating a mismatch between what `openssl dgst` hashed (with newlines) and what the server receives (stripped). **Why:** #4492 → #4495.
   - When writing a webhook handler that runs inside a systemd service's mount namespace (`ProtectSystem=strict`), cross-check every destination path against the service unit's `ReadOnlyPaths`/`ReadWritePaths` at implementation time. SSH provisioners run outside the namespace; webhook handlers run inside. `terraform validate` and sandbox test suites do not catch namespace conflicts. **Why:** #4492 P1 review finding.
   - When adding a new `apps/web-platform/infra/*.test.sh`, register it as a named step in `.github/workflows/infra-validation.yml` in the SAME commit — that workflow runs explicit `run: bash …/<x>.test.sh` steps, NOT a glob (and the repo-root test-all runner does not cover `infra/` either), so an unregistered infra test silently never gates. Grep the workflow for sibling `*.test.sh` steps and add yours alongside; backfill any orphan suites you find. Also verify the next-free ADR number from the directory (`ls knowledge-base/engineering/architecture/decisions | grep -oE 'ADR-[0-9]+' | sort -t- -k2 -n | tail -1`) — a plan-quoted ADR number is stale once a sibling PR lands one. **Why:** #5417 — resource-monitor/cat-deploy-state were orphan suites; plan's "ADR-061" was already taken. The same applies in reverse for a new `tests/scripts/test-*.sh`: nothing auto-discovers that directory either (test-all.sh's `*.test.sh` glob excludes it AND cannot match the `test-*` prefix), so it needs an explicit `run_suite` line in [scripts/test-all.sh](../../../../scripts/test-all.sh). Whichever directory you add a gate to, grep its registration site and confirm the new file appears in the run log — "it will be picked up automatically" is false by default here, and the failure is always silent-and-green. **Why:** #3366/PR #6520 — the harness carrying that PR's entire "the gate cannot silently pass" claim ran in ZERO runners; deleting the fail-open rung it existed to catch shipped green, and test-all.sh already documented this trap six lines above where the registration belonged.
   - Registration is not environment: **read the JOB BODY of any runner you register a suite into** and confirm every external binary the suite needs is installed there. A registration claim can be true in every clause (the glob matches, the job runs it, the context is required) and the suite still cannot execute. Corollary: a REQUIRED, path-filter-free, `merge_group` job is a shared resource — never add `apt-get` to one to satisfy a single suite (it puts a package-mirror dependency on the merge-queue critical path for every PR in the repo); relocate the suite to a job that already carries the tooling and record the dependency contract where the auto-glob lives. **Why:** #6454 — `.github/scripts/test/test-*.sh` auto-globs into `guard-script-fixture-tests` (required, bare `ubuntu-latest` + checkout); a terraform/cloud-init-dependent suite exited 6 on all 22 fixtures and red the required check for every PR. See `knowledge-base/project/learnings/2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md` §8.

7. **Track Progress**
   - Keep TodoWrite updated as you complete tasks
   - Note any blockers or unexpected discoveries
   - Create new tasks if scope expands
   - Keep user informed of major milestones

8. **GDPR / Compliance Gate (single pass, end of Phase 2)**

   [skill-enforced: gdpr-gate at work Phase 2 exit]

   After the per-task RED/GREEN/REFACTOR loop completes and before Phase 2.5, run `/soleur:gdpr-gate` once against the cumulative diff `git diff origin/main...HEAD` (after `git fetch origin main` — the local `main` ref lags in bare-repo worktrees and pollutes the diff with unrelated merged branches). Same advisory-only output and Critical-finding escalation as plan Phase 2.7. **Never per-task** — token budget is ≤4k per invocation, single pass per phase per ADR-026 TR3.

   Skip silently if the cumulative diff does not match the `hr-gdpr-gate-on-regulated-data-surfaces` canonical regex.

9. **Full-Suite Exit Gate (single pass, end of Phase 2)**

   [skill-enforced: work Phase 2 exit]

   Before entering Phase 3, run `bash scripts/test-all.sh` once. Touched-file tests are the inner loop; `test-all.sh` is the exit gate — it discovers orphan test suites (sibling files covering the same script — e.g., an untouched `tests/scripts/test-rule-metrics-aggregate.sh` alongside the touched `rule-metrics-aggregate.test.sh`) that the touched-file set never sees. Symmetric to the ship Phase 5.5 Review-Findings Exit Gate; catches the gap that PR #3512 surfaced post-merge-queue when an untouched orphan suite's fixture broke under a tightened predicate. **Why:** see issue #3533.

   **Sibling-worktree contention produces a FALSE RED — the runner now self-identifies it.** Parallel worktrees are this repo's documented workflow, so two sessions can run `test-all.sh` simultaneously. The contended resource is NOT a colliding path — it is CAPACITY: every suite's `mktemp` lands in the same machine-global, RAM-backed 4 GiB `/tmp` tmpfs, so a second run competes for the memory the first is holding, and the failure both implicated suites document in-repo is a TIMEOUT (`skill-security-scan.test.ts` #4096; `vitest.config.ts` #3817/#4128), never a path collision. **The previously-recorded cause — `skill-security-scan`'s `.scan-meta.json` plus the semgrep bootstrap as "the known pair" — was refuted by measurement (#6789):** `run-scan.sh` PID-scopes `.scan-meta.json` and has since its original commit (so it cannot collide across worktrees; its real defect was an *unbounded meta_dir leak*, now age-reaped), and the semgrep bootstrap is unreachable from any suite `test-all.sh` runs. You no longer run `ps` by hand: `test-all.sh` prints a contention preamble (`/tmp` headroom, sibling runs resolved to their worktrees via `/proc/<pid>/cwd`, machine load) and fires a named `SIBLING_RUN_DETECTED` / `LOW_TMP_HEADROOM` banner when either condition holds, and an advisory git-common-dir lock serializes concurrent runs (proceeding with a `LOCK_CONTENDED_PROCEEDING` banner on timeout, never aborting). When a banner fires, still confirm three ways (isolated re-run, the corresponding CI gate's status, a clean full re-run once the sibling exits) rather than accepting "flake"; and never delete another session's `/tmp` artifacts to reclaim space — `/tmp` is a shared tmpfs, so write large logs to `/var/tmp` instead (`tmpfs-guard.sh`'s cron reaper now bounds the abandoned-scratch growth that fed the pressure). **Why:** #6726 — 4 `skill-security-scan` failures were pure contention (isolated re-run 22/0, CI green throughout); #6789 re-derived the actual cause and shipped the self-identification above.

   **Doppler-env false-positive caveat (`TEST_GROUP=webplat`).** Running the webplat shard under `doppler run -c dev` injects feature flags + live vendor creds that CI does not, which can flip untouched files into code paths their unit mocks don't cover (e.g. a delegation flag routes `team-membership-resolver.ts` into a `byok_delegations` query → `unmocked table`) — the `vi.unstubAllEnvs`-can't-clear-inherited-env class. Before treating a webplat failure as a regression, re-run the failing file **without** Doppler (CI-equivalent); if it passes there and `gh run list --workflow=ci.yml --branch main` is green, it's a pre-existing env-only flake, not your diff. **Why:** #4660 (filed #4663). **Inverse (Doppler masks a CI-only FAILURE):** a new webplat test that imports any `server/inngest/*` module (or anything transitively loading `server/inngest/client.ts`) throws an `INNGEST_SIGNING_KEY missing at startup` error at module-eval unless guarded by a hoisted `vi.hoisted(...)` block that sets the `NEXT_PHASE` env to `phase-production-build` BEFORE the import (mirror the sibling `cron-compound-promote.test.ts`). Running the file under `doppler run` injects the key → it passes locally while CI's `test-webplat` (no inngest env) errors at **collection** → the required `test` context reds. Always run a new inngest-importing test CI-equivalent (no Doppler) before trusting green. **Why:** #6103 — the ADR-092 recursion test passed 4/4 under Doppler and would have wedged the merge; caught by review. See `knowledge-base/project/learnings/security-issues/2026-07-06-body-hashing-guardrail-gate-fail-open-classes.md`.

   **Legal-doc edits have TWO independent mirror gates — a new heading needs the Eleventy mirror in the same PR.** When the diff adds a `## `/`### ` heading to a canonical `docs/legal/*.md`, `apps/web-platform/test/legal-doc-consistency.test.ts` (full-suite-only — the touched-file loop never runs it) FAILS on source↔mirror section-heading-sequence drift unless the SAME heading is added to `plugins/soleur/docs/pages/legal/<doc>.md`. This is a DIFFERENT, stricter gate than `apps/web-platform/scripts/check-tc-document-sha.sh` (whose mirror *body-equivalence* step is T&C-only and explicitly defers non-T&C docs) — passing the SHA guard does NOT imply heading parity. Prose added *inside* an existing section needs no mirror heading; a NEW section does. Catch it at the full-suite exit gate (and `rc=$?` + grep the log — a backgrounded runner can report exit 0 with a real failure). **Why:** #5370 — a new gdpr-policy `### 3.12` passed the SHA guard but turned the full suite red until the mirror heading was synced. See [[2026-06-15-two-legal-mirror-gates-and-always-build-mcp-registered-list-desync]].

   **Feature-branch-CWD blind spot for `.claude/hooks/*.test.sh` (run once from a simulated `main` CWD).** A hook test whose outcome depends on a CWD/branch-resolved gate (`block-commit-on-main` via `git rev-parse --abbrev-ref HEAD`, `git worktree list` counts, `symbolic-ref HEAD`) passes on the `feat-*`/`fix-*` worktree every local run uses, but post-merge CI runs on the merged `main` commit and can fail ONLY there (`block-commit-on-main` denies a `git commit`-shaped fixture input → masks the gate under test). The local 104/104 is NOT authoritative for these. When the diff touches `.claude/hooks/*.test.sh`, run the suite once from a throwaway committed-`main` CWD (`d=$(mktemp -d); git -C "$d" init -q -b main && git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i; (cd "$d" && bash <repo>/.claude/hooks/<file>.test.sh)`). Fix-side: isolate the test from the orthogonal gate by running the hook from a non-git/pinned-branch CWD, not the ambient process CWD. **Why:** #5192 — guardrails AC1/AC3/AC4 passed 104/104 locally, turned main red, fixed in #5209. See [[2026-06-12-hook-test-passes-on-worktree-fails-on-main-cwd]].

### Phase 2.5: Research Validation Loop (knowledge-base deliverables only)

Rule source: AGENTS.md — migrated 2026-04-21 (PR #2754). When a research sprint produces recommendations, run the cascade-validate loop [id: wg-when-a-research-sprint-produces] [skill-enforced: work Phase 2.5]. **"Findings written" is NOT done — "findings applied, validated, and all documents reflect the final state" is done.** The full body of that rule lives here; AGENTS.md retains a one-line pointer preserving the `[id: ...]` tag.

**Trigger:** This phase runs when the plan's deliverables are knowledge-base research artifacts (findings, analysis, audits, research briefs) that produce recommendations targeting other existing documents. Skip for code-only plans.

**Detection:** After Phase 2 completes, scan the outputs for recommendation patterns — "should rewrite," "needs updating," "add to," "change X in Y.md," or any finding that names a specific target file. If found, enter the loop.

**The loop:**

```text
while (recommendations exist that haven't been applied):
  1. CASCADE: Apply all recommendations to their target artifacts
     - Rewrite questions in interview guides
     - Update framings in brand guide
     - Add alternatives to pricing strategy
     - Any finding that names a file → edit that file
  2. VALIDATE: Re-run the same research methodology against updated artifacts
     - Use the same personas/parameters as the original run
     - Produce a before/after comparison (original → current)
  3. CHECK: Did the validation surface NEW weak spots or recommendations?
     - If yes → apply fixes, loop back to step 2
     - If no (at synthetic ceiling) → exit loop
  4. UPDATE BRIEF: Update the research brief with final validated results
     - Executive summary reflects current state, not original findings
     - Recommendations marked as "Applied" with results
     - Add Cascade Status section tracking all changes to all files
  5. SUMMARIZE: Present founder summary
     - Key findings table
     - All files changed table (file, what changed, before/after metrics)
     - Remaining limitations (structural, not fixable)
```

**Exit condition:** The loop exits when a validation round produces no new actionable recommendations — only structural limitations that can't be fixed by rewording (e.g., a persona's archetype inherently produces flat responses to a specific question type).

**Max iterations:** 3 rounds. If the third round still produces actionable recommendations, present them to the user rather than looping indefinitely. Synthetic-on-synthetic validation has diminishing returns.

**Why this matters:** Without this loop, research sprints produce findings that sit in briefs without updating the documents they target. The founder has to manually ask "was any action taken?" after each round. This loop makes cascade + validate + re-cascade automatic.

### Phase 3: Quality Check

1. **Run Core Quality Checks**

   Always run before submitting:

   ```bash
   # Run full test suite (use project's test command)
   # Examples: bin/rails test, npm test, pytest, go test, etc.

   # Run linting (per CLAUDE.md)
   # Use linting-agent before pushing to origin
   ```

   - **For `apps/web-platform`, `npm run lint` (= `next lint`) is NOT a functioning gate — do not treat its non-zero/interactive exit as a regression.** There is no eslint config in the repo, so `next lint` (deprecated, removed in Next 16) drops into an interactive "configure ESLint?" prompt and exits 1; CI does not run lint at all (`grep -rn 'next lint\|eslint' .github/workflows/` is empty). `tsc --noEmit` + the full `vitest run` are the authoritative quality gates CI and review enforce. Standing up an eslint flat config is a separate, deliberate decision — never bolt it onto an unrelated feature/drain PR. See `knowledge-base/project/learnings/2026-06-05-web-platform-lint-gate-is-non-functional-tsc-vitest-are-authoritative.md`.

   - **Run the project's pinned TypeScript binary in the app package — `cd <app-package> && ./node_modules/.bin/tsc --noEmit` (or `bun x tsc --noEmit`), never bare `npx tsc`.** `npx tsc` resolves against its own cache and can silently install a wrong/major-jumped (or typo-squatted) `typescript`, producing false type errors unrelated to your change — the same supply-chain/version-drift failure class as the pinned-`./node_modules/.bin/vitest` rule above (PR #3186). Vitest type-checks test files lazily, so TS errors in tests pass the suite locally but fail CI; a standalone pass with the *project's* compiler catches them at the work-phase gate instead of deferring to review.
   - **A running `next dev` server poisons local `tsc --noEmit`:** dev-server-generated `.next/types` can fail TS2344 (`OmitWithTag`) on pre-existing non-route exports in layout/route files your diff never touched. Before trusting a typecheck failure that points into `.next/types`, stop the dev server and `rm -rf .next`, then re-run — clean checkouts (CI) are unaffected. See `knowledge-base/project/learnings/integration-issues/2026-06-09-qa-seed-schema-drift-and-playwright-admin-session.md`.
   - **When extracting enforcement logic (auth, CSRF, validation) from route files into a shared helper, update negative-space tests in the same commit.** Route-level detection must prove helper invocation AND failure early-return — not just import presence. Add direct assertions on the helper file for every invariant that moved into it. See `knowledge-base/project/learnings/best-practices/2026-04-15-negative-space-tests-must-follow-extracted-logic.md`.
   - **When adding git operations that contact remotes in Next.js API routes, include the credential helper pattern from `session-sync.ts`** (search `credential.helper`). Bare `git pull`/`git push`/`git fetch` fail silently on private repos. See `knowledge-base/project/learnings/integration-issues/kb-upload-missing-credential-helper-20260413.md`.
   - **When creating a new `apps/web-platform/app/api/**` route authenticated by anything OTHER than a Supabase session cookie (shared secret, HMAC, SDK signature — any non-browser caller: cron, webhook, operator/agent curl), add its exact path to `PUBLIC_PATHS` in `apps/web-platform/lib/routes.ts` in the SAME commit (narrow exact-match, never broaden to a parent prefix) + a `middleware.test.ts` membership assertion.** Otherwise Supabase middleware 307→/login the cookie-less caller before the route's own auth gate runs — the route is unreachable in prod. Route unit tests call `POST(request)` directly and CANNOT catch this (#4017, #4587, kb-drift-ingest precedent). See `knowledge-base/project/learnings/integration-issues/2026-06-01-new-internal-api-route-needs-public-paths-registration.md`.

2. **Consider Reviewer Agents** (Optional)

   Use for complex, risky, or large changes:

   - **code-simplicity-reviewer**: Check for unnecessary complexity
   - **kieran-rails-reviewer**: Verify Rails conventions (Rails projects)
   - **performance-oracle**: Check for performance issues
   - **security-sentinel**: Scan for security vulnerabilities

   Run reviewers in parallel with Task tool:

   ```text
   Task(code-simplicity-reviewer): "Review changes for simplicity"
   Task(kieran-rails-reviewer): "Check Rails conventions"
   ```

   Present findings to user and address critical issues.

3. **Final Validation**
   - All TodoWrite tasks marked completed
   - All tests pass
   - Linting passes
   - Code follows existing patterns
   - Figma designs match (if applicable)
   - No console errors or warnings

### Phase 4: Handoff

Implementation is complete. Before handing off, run the **Playwright-first audit**, then determine invocation mode.

#### Playwright-First Audit

Scan any "next steps", "setup instructions", or "to use this" text you are about to output. For each step that involves a browser action (account creation, credential generation, settings configuration, form submission, vendor support tickets, OAuth flow, portal navigation):

1. **Classify:** Is this step automatable via Playwright MCP, or is it genuinely manual (CAPTCHA, interactive OAuth consent, hardware MFA token, payment-card entry)?
2. **If automatable:** Do not list it as a manual step. Either execute it now via Playwright MCP, or note it as "automatable via Playwright — will execute next."
3. **If genuinely manual:** Drive the flow via Playwright up to the manual gate (e.g., navigate to the OAuth consent screen), then hand off only that single interaction to the user.

If you catch yourself writing phrases like "set up X in the browser", "go to the portal and...", "manually configure...", "paste this ticket body into the support form", or "the operator pastes + submits" — stop and attempt Playwright first. This audit is mandatory; skipping it is a deviation.

**Attempt-evidence is mandatory before ANY "operator-only" / "manual" / "not automatable" classification (HARD GATE).** A browser step may be labeled operator-only ONLY after a real Playwright MCP attempt that reached the actual gate — never from an a-priori assertion. Phrases like "MFA-gated", "no API path", "requires dashboard access", or "operator must do this in the browser" are predictions, NOT observations; on their own they are non-compliant. **This applies even when an upstream PLAN or ADR pre-declares the step operator-gated (e.g. `automation-status: UNVERIFIED`, or an `Automation: not feasible because <X>` line whose `<X>` is an a-priori "no creation API / vendor limit" assertion): a plan/ADR claim is NOT a substitute for your own Playwright attempt — treat any plan-declared operator-gated browser/vendor-dashboard step as UNVERIFIED and attempt it before honoring the handoff.** A vendor dashboard mint runs under an authenticated session and is presumptively automatable (#5480 — the plan + ADR-065 asserted the Resend key mint "operator-gated, no API"; a Playwright attempt reached the authenticated dashboard with a working create form and NO human gate; see `knowledge-base/project/learnings/workflow-patterns/2026-06-17-vendor-dashboard-mint-presumed-playwright-automatable.md`). The classification MUST be accompanied by an evidence line in this exact shape:

```
playwright-attempt: navigated <URL>; reached <specific gate observed>; <why it blocks autonomy>
```

where `<specific gate observed>` is a concrete, named gate the run actually hit — one of: `CAPTCHA/Turnstile challenge`, `email-OTP`, `SMS-OTP`, `authenticator-TOTP`, `WebAuthn/passkey/Touch-ID prompt`, `push-MFA (Duo/Okta/Authy)`, `payment-card iframe`, `hardware-token tap`, or `tool-instability: <observed symptom>` (e.g., "browser context closed mid-form ≥N times; SPA form state did not survive reconnect"). "I assume it needs MFA" is not a gate observation; "navigated to the password screen, entered creds, hit a WebAuthn passkey prompt the browser cannot synthesize" is. **`api-probe-403` alone never qualifies** — a 403 from a *narrowly-scoped* token (e.g. a Terraform token that lacks token-management permission) does not prove the dashboard path is operator-only; you must still attempt the browser. Exhaust the credential space first (a Global API Key or a token with the write scope may exist in Doppler) before concluding no API path exists.

**Two distinct dispositions once attempt-evidence exists:**

- **`operator-only` (a true human gate):** the observed gate is one only a human can clear (CAPTCHA, OTP/TOTP, passkey, push-MFA, payment-card, hardware token). Drive Playwright up to that single interaction, hand off ONLY that interaction, then resume autonomously. This is the legitimate handoff.
- **`attempted-blocked-on-tool` (a tool/environment failure):** the gate is mechanically automatable but the tool could not complete it (repeated browser-context crashes, an MCP server that is down, a headless run where the interactively-authenticated MCP is absent). This is NOT operator-only — record it distinctly so it is fixed/retried rather than permanently handed to the operator. Capture the exact resume state (URL, the precise remaining clicks, any partially-completed form) so the next stable session finishes it without re-deriving. Do NOT file a `deferred-automation` operator issue for this class — file a `type/chore` issue tagged `tooling`/`flaky` describing the instability, with the resume recipe.

The `playwright-attempt:` line is what the ship operator-step gate and the Post-Merge Self-Audit consume to distinguish a real gate from an un-attempted deferral. See `knowledge-base/project/learnings/workflow-patterns/2026-06-10-playwright-attempt-evidence-before-operator-only.md`.

**Vendor support ticket submissions are Playwright-driveable** — they are NOT operator-handoff by default. Most vendor support surfaces today are Intercom / Zendesk / HelpScout chat widgets (`help.<vendor>.io`, `support.<vendor>.com`, `<vendor>.zendesk.com`) where the AI assistant routes to a human team. The full submission flow — opening the widget, accepting cookies, starting a conversation, sending the ticket body, requesting human escalation if the AI gives a stock policy answer — runs entirely under Playwright. The only legitimate manual gates are:

- **Email-OTP verification** when the vendor sends a one-time passcode to the operator's inbox before routing to a human reviewer.
- **SMS-OTP** — same shape as email-OTP but delivered to the operator's phone (e.g., banks, telcos, account-recovery flows). Same handoff: "check your messages for the code, tell me the digits."
- **Authenticator-app TOTP** — operator reads a rolling 6-digit code from Authy / 1Password / Google Authenticator / Microsoft Authenticator. Playwright cannot reach the authenticator source.
- **WebAuthn / passkey / U2F browser prompts** — the OS or browser surfaces a native dialog (passkey selection, Touch ID, Windows Hello) that Playwright cannot synthesize. Distinct from hardware MFA: passkeys are software-resident and increasingly the default on Google / GitHub / Stripe / Apple.
- **Push-based MFA** (Duo Push, Okta Verify, Authy Push, Microsoft Authenticator notification) — operator approves on a separate device; no DOM interaction available to Playwright.
- **Payment-card entry** in Stripe / similar widgets (cross-origin iframe sandbox; even if Playwright could reach in, card entry is the explicit operator decision-and-ack point).
- **CAPTCHA / "I am not a robot"** challenges (intentional bot-detection).
- **Hardware MFA token tap** — physical YubiKey / Titan / Solokey touch (operator-side device).

Never quote OTP digits, TOTP codes, or any other ephemeral authentication value in a committed file — capture only the fact-of-verification + UTC timestamp. The specific code is dead immediately, but quoting it normalizes "paste secrets into the runbook" as a pattern and the next vendor's code may NOT be single-session (some flows reuse codes within a TTL window).

Drive the flow up to one of these gates, hand off the single interaction (e.g., "check your inbox for the OTP and tell me the code"), then resume. Never list "operator pastes + submits" as a step — that's a Playwright-first-audit violation. Vendor support tickets typically do not return a numeric ticket ID; capture (a) the submission UTC timestamp, (b) the AI-classifier auto-title (often surfaced in the messages list), and (c) any human-team routing label as the audit baseline. The conversation thread on the vendor side IS the canonical ticket; async response arrives via email to the operator. **Why:** PR #3946 PR-γ §17 Sentry refund + forensics tickets — the original plan listed them as "NOT Playwright-driveable" (operator handoff to paste-and-submit); after operator pushback, both tickets were driven via Sentry's Intercom widget at `help.sentry.io` with only the email-OTP step handed off. See learning `knowledge-base/project/learnings/2026-05-17-vendor-support-tickets-are-playwright-driveable.md`.

#### Phase 4 Entry-Guard

Before emitting `## Work Phase Complete` (one-shot mode) or chaining into the post-implementation pipeline (direct mode), assert at least one commit exists beyond `origin/<branch>`. An empty diff hands review agents nothing to analyze and produces no signal. Run BEFORE the Invocation Mode branch so both paths are covered.

**Procedure (distinct exit codes signal distinct operator actions):**

1. Probe the commit count:

   ```bash
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   if [[ -z "$BRANCH" || "$BRANCH" == "HEAD" ]]; then
     echo "[work-phase-4-guard] detached HEAD — checkout a feature branch before chaining to review." >&2
     exit 1
   fi
   N=$(git rev-list "origin/${BRANCH}..HEAD" --count 2>/dev/null || echo 0)
   ```

2. If `N == 0`, **stop and run Phase 2 step 3** (stage logical-unit files, write conventional commit message). Do not chain through this block as a single bash invocation — the commit is an explicit action the agent must perform between probes:

   ```bash
   if [[ "$N" == "0" ]]; then
     echo "[work-phase-4-guard] no commits beyond origin/${BRANCH} — pause and run Phase 2 step 3 incremental commit before continuing." >&2
     exit 2  # PAUSE — orchestrator should re-enter Phase 4 after the commit lands
   fi
   ```

3. After the incremental commit lands, re-enter the Phase 4 entry-guard. If `N == 0` on the second probe (commit failed silently or no diff exists), HALT:

   ```bash
   if [[ "$N" == "0" ]]; then
     echo "[work-phase-4-guard] empty diff vs origin/${BRANCH} after Phase 2 step 3 — investigate before continuing." >&2
     exit 1  # HALT — do NOT emit "## Work Phase Complete"
   fi
   ```

**Form rationale.** `git rev-parse --abbrev-ref HEAD` matches `ship/SKILL.md:619` precedent and returns the literal `HEAD` on detached state (vs. `git branch --show-current` which returns empty), so the detached-HEAD guard catches both shapes. `git rev-list ... --count` returns a clean integer ready for `[[ "$N" == "0" ]]`; the `wc -l` shape requires a `tr -d` strip and is whitespace-padded. Precedent: `plugins/soleur/skills/ship/SKILL.md:619`, `.claude/hooks/ship-unpushed-commits-gate.sh`. **Distinct exit codes** (`2 = pause-and-commit`, `1 = halt-and-investigate`) let one-shot orchestrators distinguish the two recovery paths rather than treating both as opaque non-zero failures.

#### Post-Merge Section Self-Audit (HARD GATE)

After drafting the PR body and BEFORE `gh pr ready` / `gh pr merge --auto`, scan every line under headings matching `^##\s+(Post-?merge|Operator|Follow-?ups?)` (case-insensitive). For each bullet, classify and resolve **before** marking ready:

| Pattern | Action |
|---|---|
| Doppler/env-var verification | Inline-execute via `doppler secrets get <KEY> -p soleur -c <env> --plain`; if missing, set from a known source via `doppler secrets set` or update the handler to read the existing canonical name. |
| `Within Nh of merge: file <issue>` | File the issue NOW via `gh issue create` using the template the bullet describes; replace the bullet with `Done: #<num>`. |
| `gh issue close` / `gh issue comment` on existing issues | Run NOW via `gh` CLI. |
| Sentry / Better Stack / monitor verification | Replace with the monitor's own auto-page mechanism (`failure_issue_threshold = 1` is the verification — no operator gaze required per `hr-no-dashboard-eyeball-pull-data-yourself`). If active verification is still wanted, create a one-time scheduled workflow via `/soleur:schedule create --once --at <date>` with a self-disabling `verify-and-close-or-file-issue` body. |
| Genuinely operator-only (CAPTCHA, SSO consent, payment-card entry, hardware MFA, K-bis-style first-onboarding) | **Requires a `playwright-attempt:` evidence line** (see Phase 4 Playwright-First Audit) proving a real attempt reached a true human gate — an a-priori "MFA-gated"/"dashboard-only" assertion does NOT qualify. With evidence: file a `type/chore` issue carrying the literal `deferred-automation` sentinel via `gh issue create --label type/chore --body "deferred-automation backlog item; re-evaluate when: <criterion>; playwright-attempt: <evidence>" ...`, then add `Tracks #N` to the bullet in the PR body. |
| Automatable but the tool failed (`attempted-blocked-on-tool`: browser crashes, MCP down, headless-absent MCP) | NOT operator-only — file a `type/chore` issue tagged `tooling`/`flaky` (NOT `deferred-automation`) with the `playwright-attempt:` evidence + exact resume recipe (URL, remaining clicks, partial form state). Retry in a stable session; do not permanently hand to the operator. |
| Anything else | Inline-execute. Default-deny on "operator should later …" phrasing. |

After resolution, re-scan; the section MUST contain zero unaccompanied operator/manual bullets. The `ship-operator-step-gate.sh` PreToolUse hook enforces this mechanically at `gh pr ready` / `gh pr merge --auto` — the gate's deny message lists each undeferred match. Override via `SOLEUR_SKIP_OPERATOR_STEP_GATE=1` is reserved for the rare attestation case.

**Why:** PR #4227 (TR9 PR-3) shipped with a "Post-merge" section listing four operator items (Doppler secrets check, T+90 min Sentry verify, T+24h auto-resolve verify, file follow-up issue within 48h) — all four were inline-automatable; the agent had hard rules forbidding the deferral (`hr-exhaust-all-automated-options-before`, `hr-never-label-any-step-as-manual-without`, `wg-block-pr-ready-on-undeferred-operator-steps`) and still wrote the bullets. The gate existed at `/ship` Phase 5.5 but the agent reached `gh pr ready` directly. This self-audit + the hook close both halves of that bypass. See `knowledge-base/project/learnings/best-practices/2026-05-21-post-merge-section-self-audit.md`.

#### Follow-up Filing Net-Flow Gate (HARD GATE)

`/work` files follow-up issues HERE (Post-Merge Self-Audit, deferral tracking, discovered-bug capture) — which is BEFORE `/ship` Phase 5.5's Net-Issue-Flow Surfacing runs, and is bypassed entirely when `/ship` is hand-rolled. So the cost-of-filing + net-flow discipline (PR #4452) must ALSO fire at this filing site, not only at ship.

Before issuing ANY `gh issue create` for a follow-up in this phase, run the gate:

1. **Cost-of-filing, per candidate filing** (mirrors `review/SKILL.md` §CONCUR): if the deferred work is **≤100 changed lines AND ≤4 files**, do it inline (fold into THIS PR if unmerged; otherwise it is genuinely a follow-up). Only file when the work is genuinely larger, a separate work-stream/Non-Goal, an operator-only step, or a **discovered defect in a different subsystem** (the last MUST stay its own issue — never bury a possible-P1 bug in a consolidated tracker).
2. **Consolidate deferred-FEATURE follow-ups into ONE tracker.** Multiple `deferred-scope-out` follow-ups from the same PR (ADR + future-feature + sibling-upstream …) collapse into a single "**\<feature\> (#N): post-MVP follow-ups**" issue with a checklist. Discovered bugs stay separate.
3. **Surface the net count BEFORE filing.** Compute and print: `Closing: <count of Closes #N in PR body> / Filing: <new issues> / Net: <signed>`. If `Net > 0`, state one sentence per filing on why it could not be inlined or consolidated. Net-positive backlog growth from a single feature PR is the smell this gate exists to catch.

This is the `/work`-side mirror of `/ship` Phase 5.5 Net-Issue-Flow Surfacing — together they cover both the filing site (here) and the merge boundary (ship). **Why:** PR #4580 (#4579) filed **4** follow-ups for **1** closed issue (net +3) during this self-audit; the agent hand-rolled `/ship` so Phase 5.5's surfacing never fired, and there was no filing-site gate. Three were consolidatable into one tracker (#4613); the net should have been +1. See `knowledge-base/project/learnings/workflow-patterns/2026-05-29-net-issue-flow-gate-at-filing-site-not-just-ship.md`.

#### Invocation Mode

**If invoked by one-shot** (the conversation contains `soleur:one-shot` skill output earlier): Output exactly `## Work Phase Complete` and then **immediately invoke** `skill: soleur:review` (step 4 of the one-shot sequence). Do NOT end your turn after outputting the marker — you ARE the orchestrator, so you must continue executing one-shot steps 4 through 10 in order. The marker is a progress signal, not a stopping point.

**If invoked directly by the user** (no one-shot orchestrator): Continue through the post-implementation pipeline automatically. Do NOT stop and wait — the earlier learning "Workflow Completion is Not Task Completion" applies. Run these steps in order, forwarding `--headless` if `HEADLESS_MODE=true`:

1. `skill: soleur:review` (or `skill: soleur:review --headless` if headless) — catch issues before shipping
2. `skill: soleur:resolve-todo-parallel` — resolve any review findings (no `--headless` needed; this skill has no interactive prompts)
2.5. **Structural-UI visual gate (#4834 / ADR-049).** If the diff (`git diff --name-only origin/main...HEAD` — the branch-vs-main merge-base diff; do NOT use `origin/<branch>...HEAD`, which only sees unpushed commits and returns 0 files once the branch is pushed) touches `apps/web-platform/app/(dashboard)/**`, `apps/web-platform/components/dashboard/**`, or any `layout.tsx`, run `skill: soleur:qa` (or `--headless`) BEFORE shipping — its auth-seeded headless Playwright nav-states gate catches the CSS-layout regressions jsdom structurally cannot (the #4810 class). This is the step whose absence let direct `/work` skip the browser check that one-shot runs at its step 5.5 — wiring it here closes that asymmetry. Do NOT fire on leaf-component or content-only `.tsx` diffs. This is a scope boundary, not a stopping point: do not announce or return control here — continue executing the next step.
3. `skill: soleur:compound` (or `skill: soleur:compound --headless` if headless) — capture learnings before committing
3.5. Display: "Tip: After shipping, run `/clear` to reclaim context headroom for the next task."
4. `skill: soleur:ship` (or `skill: soleur:ship --headless` if headless) — commit, push, create PR, merge

---

## Key Principles

### Start Fast, Execute Faster

- Get clarification once at the start, then execute
- Don't wait for perfect understanding - ask questions and move
- The goal is to **finish the feature**, not create perfect process

### The Plan is Your Guide

- Work documents should reference similar code and patterns
- Load those references and follow them
- Don't reinvent - match what exists

### Test As You Go

- Run tests after each change, not at the end
- Fix failures immediately
- Continuous testing prevents big surprises

### Quality is Built In

- Follow existing patterns
- Write tests for new code
- Run linting before pushing
- Use reviewer agents for complex/risky changes only

### Review Before You Ship

- Use `skill: soleur:review` after completing implementation
- Catches issues before they reach PR reviewers
- Faster feedback than waiting for human review
- Builds confidence that your code is solid

### Compound Your Learnings

- Use `skill: soleur:compound` before creating a PR
- Document debugging breakthroughs, non-obvious patterns, and framework gotchas
- Even "simple" implementations can yield valuable insights
- Future-you and teammates will thank present-you

### Ship Complete Features

- Mark all tasks completed before moving on
- Don't leave features 80% done
- A finished feature that ships beats a perfect feature that doesn't

## Quality Checklist

Before entering Phase 4, verify these Phase 2-3 items are complete:

- [ ] All clarifying questions asked and answered
- [ ] All TodoWrite tasks marked completed
- [ ] Tests pass (run project's test command)
- [ ] New source files have corresponding test files
- [ ] Linting passes (use linting-agent)
- [ ] Code follows existing patterns
- [ ] Figma designs match implementation (if applicable)

After Phase 4 handoff (one-shot only), the same agent continues executing one-shot steps 4-10 (`/review`, `/qa`, `/compound`, `/ship`, `/test-browser`, `/feature-video`).

## When to Use Reviewer Agents

**Don't use by default.** Use reviewer agents only when:

- Large refactor affecting many files (10+)
- Security-sensitive changes (authentication, permissions, data access)
- Performance-critical code paths
- Complex algorithms or business logic
- User explicitly requests thorough review

For most features: tests + linting + following patterns is sufficient.

## Common Pitfalls to Avoid

- **Analysis paralysis** - Don't overthink, read the plan and execute
- **Skipping clarifying questions** - Ask now, not after building wrong thing
- **Ignoring plan references** - The plan has links for a reason
- **Testing at the end** - Test continuously or suffer later
- **Forgetting TodoWrite** - Track progress or lose track of what's done
- **80% done syndrome** - Finish the feature, don't move on early
- **Over-reviewing simple changes** - Save reviewer agents for complex work
- **Silent plan omissions** - When dropping a conditional plan item, document why in the commit or plan
- **Research without cascade-validate loop** - For knowledge-base research deliverables, Phase 2.5 enforces: cascade findings into source artifacts → re-run validation → cascade again if new weak spots emerge → update brief with final results → present founder summary. "Findings written" is not "done" — "findings applied, validated, and all documents reflect the final state" is done. See Phase 2.5.
- **Missing founder summary** - After completing research, analysis, or audit work, present a concise summary: key findings table + all files changed table (file, what changed, before/after metrics if applicable). The founder needs to review what changed, not just what was discovered.
- **Incomplete replace_all** - After any `replace_all` Edit operation, grep the file to verify zero remaining matches before proceeding to the next task. `replace_all` can miss occurrences with different surrounding context (whitespace, indentation).
- **Encoded-blob value sweep** - When removing a value from a file that contains base64, hex, JSON-string-escape, or URL-encoded forms (JWT fixtures, encoded config snapshots, request payloads), source-form `grep` is insufficient. After substitution, decode each blob and grep the **decoded** form for the removed value. **Why:** PR #3054 — `replace_all "ifsccnjhymdmidffkzhl"` returned 0 source hits but `JWT_LOG_INJECT_U2028`'s base64 payload still encoded the dev Supabase ref; the secret scanner would have re-fired. See `knowledge-base/project/learnings/security-issues/2026-04-29-jwt-fixture-reminting-decode-verify.md`.
- **Synthesized secret-SHAPE fixtures trip GitHub Push Protection — split them across concatenation.** A fake value with a REAL token shape (`sk_live_…`, `ghp_…`, `sk-ant-…`, `AKIA…`) still matches GitHub's secret-scanning regex and blocks the push (`GH013 … Push cannot contain secrets`) even though it is synthetic per `cq-test-fixtures-synthesized-only`. Build sentinel fixtures via concatenation so no contiguous token literal exists in source while the runtime value keeps the redactor-matching shape: `const STRIPE = "sk_" + "live_0123…"`. Push scans every commit in range, so a working-tree fix is insufficient — purge the literal from history (no `rebase -i` in this env: `git reset --soft <pre-feature-base>`, re-`git add` the fixed files, recommit; verify `git diff --cached | grep -E '<token-regex>'` is empty first). **Why:** PR #5042 — a synthesized `sk_live_…` debug-redaction fixture blocked the push. See `knowledge-base/project/learnings/2026-06-08-debug-mode-stream-redaction-and-pushprotection.md`.
- **Local verification without Doppler** - For env-var-reading apps, use a single Bash call: `cd <abs-path> && doppler run -p soleur -c dev -- npm run <script>` (for `apps/web-platform`, `cd apps/web-platform && doppler run -p soleur -c dev -- npm run dev`). Prevents: (a) skipping `doppler run` (missing secrets), (b) invoking transitive binaries under `doppler run` (not on PATH), (c) relying on ambient CWD from a prior call (fragile — CWD persists, but an intervening `cd` can silently redirect it). If port 3000 is already bound by another dev server (the user may have one running), start on an alternate port via `PORT=3099 doppler run ... npm run dev` rather than killing the existing process. (ex-`cq-for-local-verification-of-apps-doppler`; #2350 hit all three failure modes in sequence; PR #3199 added the alt-port fall-through after the stale `./scripts/dev.sh` reference broke startup)
- **Closes-after-apply deferral missed in commit messages** - When a plan's `## Risks` (or `## Sharp Edges`) section names an explicit Closes-after-apply deferral (issue stays open until a post-merge PM step proves green — workflow first-run, terraform apply, deploy probe, etc.), commit messages AND PR body MUST default to `Ref #N`, not `Closes #N`, regardless of whether the commit body's `Closes` placement is technically `wg-use-closes-n-in-pr-body-not-title-to`-legal. Auto-close fires at merge time, decoupled from whether the proof artifact actually lands green. Detection: grep the plan for `Closes-after-apply`, `manual close after`, `Ref #N` + `close manually`, `type: ops-remediation`, or any explicit per-PM closure-link instruction. On match, emit `Ref #N` + 1-line WARN. The author manually `gh issue close N --comment "<run URL>"` post-PM. **Why:** PR #3551 — initial commit message used `Closes #3060` against plan §R6's `Ref #3060 + manual close after PM1 confirms first green run` directive; caught pre-push via self-audit, amended. See `knowledge-base/project/learnings/2026-05-11-plan-r6-closes-after-apply-deferral-pattern.md`.
- **Meta-content describing close behavior auto-closes the issue on merge, and hand-rolled merges bypass the scanner that catches it.** GitHub's close-keyword parser is word-boundary based, so the hyphen in `auto-closes #N` matches `\bcloses\b #N` (negated `does not close #N` matches too); on a squash merge it reads the **branch commit body**, not just the PR description. When a commit/PR legitimately *describes* close behavior (a follow-through script's docstring, "the sweeper auto-closes #N"), it fires anyway. Two guards: (1) any merge path that skips `/ship` (admin-merge, hand-rolled `gh pr merge`, GitHub UI) MUST still run `plugins/soleur/skills/ship/scripts/auto-close-scan.sh` over `git log origin/main..HEAD --format=%B`; (2) write close-behavior prose without the bare `<keyword> #N` adjacency — "auto-resolves issue #N", "the sweeper will close issue #N". File *contents* are safe (GitHub parses messages + PR bodies, not diffs). **Why:** #5689 — the #5717 squash-commit body "sweeper auto-closes #5689" auto-closed the still-open soak-gated issue; the admin-merge bypassed `/ship` Phase 6's auto-close scan. See `knowledge-base/project/learnings/2026-06-29-auto-closes-meta-content-in-commit-body-trips-github-autoclose-on-hand-rolled-merge.md`.
- **Parallel `gh issue create` scrambles ID-to-title mapping** - When a /work task files N related GitHub issues (e.g., a deferral-issues batch), `gh issue create ... &` + `wait` returns URLs in completion order, not start order. The first `gh` job to FINISH gets `#N`, the next gets `#N+1`, etc. — independently of which title started first. Worse, a transient GraphQL error on one parallel job is easy to misattribute to the wrong title. **Either serialize the calls** (~1.5–3s each is cheap for ≤5 issues), **or write each result to a name-keyed file under a per-run scratch dir** (`d=$(mktemp -d -t gh-issues.XXXXXXXX); echo "$url" > "$d/issue-$short_name.url"`) so the title→ID mapping is explicit. Key the dir per-run, not per-issue-name: a bare name-keyed path in a shared scratch namespace is a pure function of the issue name, so a sibling session filing a like-named issue overwrites the mapping this recipe exists to keep straight. **Always run `gh issue view <N> --json title` reconciliation before citing IDs in any artifact** (agent body, README, SKILL.md, plan). The cost of catching wrong IDs at PR review is ~30 minutes of recovery (close duplicate, file missing, edit artifacts, force-push); the cost of post-creation reconciliation is N seconds. **Why:** PR #4288 — 5 deferral issues filed in parallel; 3 of 5 IDs ended up inverted in the agent body, 1 was dropped (GraphQL error), 1 was a duplicate retry. See `knowledge-base/project/learnings/2026-05-22-parallel-gh-issue-create-scrambles-id-mapping-and-review-agent-producer-consumer-symmetry.md`.
- **Never heredoc an issue-body into the SAME Bash command as a hook-gated `gh issue create`** - A PreToolUse hook denial (e.g. the `--milestone`-required gate) rejects the ENTIRE Bash tool call, so a preceding `cat > /tmp/body.md <<EOF … EOF` in the same command never runs — the corrected retry then fails `no such file`. Write the body with the **Write tool** (or a separate Bash step) FIRST, then run `gh issue create --body-file <path> --milestone <m>` as its own command. **Why:** filing #4730 — first `gh issue create` was denied for a missing `--milestone`, taking its inline heredoc down with it. See `knowledge-base/project/learnings/bug-fixes/2026-06-01-best-effort-cron-monitor-liveness-not-success-and-offhost-visible-warn.md`.
- **A green "full suite" that never ran the suites gating your directory, and a background wrapper whose exit code is not the command's** — two independent ways to read a pass that did not happen. (a) [scripts/test-all.sh](../../../../scripts/test-all.sh) does **not** cover `apps/web-platform/infra/` (those gate via `infra-validation.yml`), so its `rc=0` is not evidence for an infra change. When a diff changes a LITERAL, `git grep` for suites asserting it and run every suite registered in the workflow that gates the changed directory — a sibling can pin your expression byte-for-byte and go RED while your own suites stay green. Prefer re-keying such a sibling onto the invariant's SHAPE and leaving the exact-string pin in ONE place, rather than replicating the literal across two files with no parity test. (b) For `run_in_background` of the form `cmd > log 2>&1; echo $? > rc`, the harness notification reports the **trailing echo / wrapper**, not the command — "completed (exit code 0)" fires while the suite is still running. Verify with the explicit rc FILE **plus** a `pgrep` **plus** log-size growth over a ≥20s window; and after a foreground timeout, kill the surviving child before relaunching or two concurrent suites race on one worktree. **Why:** #6588/PR #6716 — an infra sibling (`workspaces-luks-header.test.sh` H17) went red unnoticed behind a green `test-all.sh`, and the bg notification lied twice in one session.
- **Emitting a forward-looking sentence as the last thing in a turn.** "Continuing to compound → ship" at the end of a response is not a handoff, it is an abandoned pipeline — the operator has to ask whether it happened. A phase-complete marker (`## Work Phase Complete`, `## Review Phase Complete`) is a CHECKPOINT: the next tool call in the SAME response must be the successor skill invocation. Stating an intention is not performing it. **Why:** #6588/PR #6716 — review completed, the turn ended on "continuing", and the operator had to prompt for the rest of the pipeline.
- **Relaunching a long-running background bash before verifying it died** - When a `run_in_background: true` task seems unresponsive, do NOT relaunch until ALL three checks confirm death: (1) broad `ps -ef \| grep -E '<substring>' \| grep -v grep` (never `pgrep -fa 'pattern$'` — anchored patterns miss processes wrapped in `doppler run -- bash ...`), (2) cache/output file size stopped growing over a 30+ second window, (3) the harness's `<task-notification>` has fired with a definitive `status` field. Log file `mtime` is NOT a liveness signal — long-running scripts buffer output between API calls. Relaunching prematurely concurrent-runs against the same API key and wastes paid spend. **Why:** PR #4156 — bench 1 was running fine the whole ~75 min, but `pgrep` with anchored pattern + stale log mtime led to two redundant bench launches (extra ~$2-3 Anthropic spend). See `knowledge-base/project/learnings/workflow-issues/2026-05-20-long-running-bench-verify-process-before-relaunch.md`.
