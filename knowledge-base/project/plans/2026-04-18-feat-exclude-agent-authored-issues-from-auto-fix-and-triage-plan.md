# feat: exclude agent-authored issues from auto-fix and auto-triage

**Issue:** #2344
**PR:** #2533 (draft)
**Branch:** `feat-exclude-agent-issues-auto`
**Worktree:** `.worktrees/feat-exclude-agent-issues-auto/`
**Milestone:** Phase 3: Make it Sticky (from #2344)
**Priority:** `priority/p2-medium`
**Type:** `type/feature`
**Domain:** `domain/engineering`, `domain/product`

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** Overview, Implementation Phases, Risks, Acceptance Criteria, Test Scenarios
**Research inputs:** `2026-03-03-scheduled-bot-fix-workflow-patterns.md`, `2026-04-15-brainstorm-calibration-pattern-and-governance-loop-prevention.md`, live inspection of `.github/workflows/scheduled-bug-fixer.yml` and `scheduled-daily-triage.yml`, live tracker state for `ux-audit` + `agent:*` labels

### Key Improvements

1. **Corrected jq clause logic.** Investigation found that of the 5 currently open/closed `ux-audit` issues, only #2341 carries `agent:ux-design-lead`. The rest have the stream tag only. An `agent:*`-only filter would regress; the clause MUST keep OR-logic: `ux-audit` OR any `agent:*`. This is now called out explicitly as a non-trivial correctness property.
2. **Surfaced the `gh --jq` pitfall.** Per `2026-03-03-scheduled-bot-fix-workflow-patterns.md`, `gh issue list --jq` does NOT support jq's `--arg`/`--argjson` — those flags get parsed as unknown `gh` arguments. The plan's canonical clause uses only hard-coded string literals (`"ux-audit"`, `"agent:"`) so this is not an issue in-scope, but the reference doc now warns future adopters.
3. **Locked FIFO-preserving ordering.** `scheduled-bug-fixer.yml` relies on `sort_by(.createdAt) | .[0]` to process the oldest issue first. The generalized filter MUST preserve that sort; the implementation phase pseudocode is now explicit.
4. **Hardened shell-escape safety.** The canonical clause uses `select(length > 0)` / `any(startswith("agent:"))` forms; `!=` comparisons are avoided because they get mangled by GitHub Actions `run:` YAML quoting (per the same 2026-03-03 learning).
5. **Clarified wildcard parsing.** The skill-level `--exclude-label` flag accepts `agent:*` only if the trailing `*` is the literal terminator — not a shell glob that bash expands against the filesystem. Documented in the skill Phase 0 pseudocode.

### New Considerations Discovered

- **Retroactive label gap.** The open `ux-audit` issues #2378, #2379, #2352, #2351 don't carry `agent:ux-design-lead`. The stream tag is load-bearing for these; removing `ux-audit` from the clause in a future "DRY-up" refactor would silently regress. Plan codifies this as a stream-tag guarantee, not a transitional mechanism.
- **Defense-in-depth asymmetry.** The scheduler filter and the skill-level short-circuit are intentionally redundant for the auto-fix path, BUT the skill-level check is the ONLY guard for manual invocations (`claude /soleur:fix-issue <ux-audit-issue>`). Without the skill check, a well-meaning operator running the skill manually on a `ux-audit` issue would burn an auto-merge attempt on governance-excluded work. Elevated from "defense-in-depth nice-to-have" to a first-class behavior.

## Overview

Turn the ad-hoc `ux-audit` filter that currently exists in two scheduled workflows into a **first-class, documented governance pattern** for excluding agent-authored GitHub issues from automation loops (auto-fix, auto-triage, and any future issue-consuming workflows).

Today the load-bearing rule from the brainstorm (`2026-04-15-brainstorm-calibration-pattern-and-governance-loop-prevention.md` — "Exclude label from auto-fix and auto-triage workflows … row 5 is the load-bearing one. Without it the other four are just speed bumps.") lives as a single hard-coded label (`ux-audit`) sprinkled across two jq filters. The next agent-authored stream (e.g. `ux-audit` on a different surface, `seo-audit`, `legal-audit`, CodeQL-to-issues expansions, scheduled community monitor findings) has to re-discover the pattern and copy/paste the filter. That's exactly how governance loops get re-introduced.

Goal: make exclusion declarative at two layers:

1. **`fix-issue` skill** accepts `--exclude-label` as a first-class option that any caller (scheduled-bug-fixer, future schedulers, manual invocation) can pass to avoid picking up agent-authored issues.
2. **Auto-consuming workflows** (`scheduled-daily-triage`, `scheduled-bug-fixer`, and any future ones) share a single canonical exclusion list derived from a documented convention: `ux-audit` (legacy), plus the `agent:*` label family that already tags `agent:ux-design-lead` issues and is the documented convention for future agent-authored streams.

Non-goals (kept out of scope):

- Changing the `ux-audit` skill or any agent's labeling behavior (those already label correctly — see `scheduled-ux-audit.yml` labels `ux-audit` + `agent:ux-design-lead`).
- Building a generic "agent-authored detection" layer (e.g. parsing PR author metadata). Label-based exclusion is the documented mechanism (brainstorm pattern 2, row 4–5).
- Adding new agent-authored issue streams. This plan makes the opt-in available; adopters land in their own PRs.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #2344) | Reality in codebase | Plan response |
|---|---|---|
| "Add `--exclude-label ux-audit` to `fix-issue` skill" | `fix-issue` SKILL.md takes exactly one input (`$ARGUMENTS` = issue number). It does not accept flags or an exclude list today. Filtering happens **upstream in `scheduled-bug-fixer.yml`**, not in the skill. | Add the `--exclude-label` flag as a real skill-level option (parsed from `$ARGUMENTS`) so manual invocations and future callers can pass it. Keep upstream workflow-level filters too — defense-in-depth matches the existing auto-merge-gate pattern. |
| "any auto-triage workflow" | Only one exists: `scheduled-daily-triage.yml`. It already excludes `ux-audit` via an inline jq filter. | Generalize the filter to exclude the entire documented label family (`ux-audit` + `agent:*`) and extract it into a canonical jq snippet reused across workflows. |
| "Document the pattern as a first-class opt-in for other agent-authored issue streams" | Pattern documented only in one learning file (`2026-04-15-brainstorm-calibration-pattern-...md`). No runbook or convention page exists. | Add a short reference doc — `plugins/soleur/skills/fix-issue/references/agent-authored-exclusion.md` — and cross-link from the learning, from `scheduled-ux-audit.yml` top comment, and from the two consumer workflows. |
| Issue says: "Blocker-for-merge of #2341" | #2341 is already **CLOSED** (shipped) with hard-coded `ux-audit` exclusion in both consumer workflows. The governance loop is already broken in practice. | This is a hardening PR that generalizes an already-working mitigation — not an outage fix. Priority stays `priority/p2-medium`. |

## Files to edit

- `plugins/soleur/skills/fix-issue/SKILL.md` — add `## Inputs` section describing accepted args, add `## Phase 0: Parse arguments` that extracts `--exclude-label` values into `$EXCLUDE_LABELS`, teach Phase 1 to short-circuit with a benign exit message when the issue carries any excluded label.
- `.github/workflows/scheduled-bug-fixer.yml` — replace the single hard-coded `ux-audit` jq clause (line 106) with a loop that excludes both `ux-audit` AND any label starting with `agent:`. Pass `--exclude-label ux-audit --exclude-label agent:*` to the skill invocation as defense-in-depth.
- `.github/workflows/scheduled-daily-triage.yml` — replace the single-label jq filter (line 76) with the same canonical pattern.
- `knowledge-base/project/learnings/2026-04-15-brainstorm-calibration-pattern-and-governance-loop-prevention.md` — add a "See also" link to the new reference doc so the institutional learning points at the enforcement surface.

## Files to create

- `plugins/soleur/skills/fix-issue/references/agent-authored-exclusion.md` — canonical opt-in doc: label convention (`agent:<role>` + stream-specific tag like `ux-audit`), which workflows honor it, how to add a new stream, how to test.
- `plugins/soleur/skills/fix-issue/references/exclude-label-jq-snippet.md` — the exact jq clause referenced from both workflows, so the next editor touches one file when the list changes.

No new top-level files, no schema changes, no migration, no dependencies.

## Implementation Phases

### Phase 1 — Skill surface: parse `--exclude-label` in fix-issue

Edit `plugins/soleur/skills/fix-issue/SKILL.md`:

- Add `## Inputs` section (before `## Constraints`):
  - `$ARGUMENTS` accepts one of: `<issue-number>` OR `<issue-number> --exclude-label <label> [--exclude-label <label> …]`.
  - Bare numbers still work (backward compatible with existing `scheduled-bug-fixer.yml` prompt: `Run /soleur:fix-issue $ISSUE_NUMBER`).
- Add `## Phase 0: Parse arguments`:
  - Extract issue number (first positional arg).
  - Collect all `--exclude-label <val>` pairs into an `$EXCLUDE_LABELS` array (shell; shown as pseudocode in the skill markdown).
- In `## Phase 1: Read and Validate`, after fetching the issue JSON, add an **agent-authored short-circuit** check:
  - If any label in the issue intersects `$EXCLUDE_LABELS` (exact match), exit with a benign message: `"Issue #N carries excluded label '<label>'. fix-issue will not operate on agent-authored issues."` No failure-handler label, no PR, no comment — the scheduler already skipped it upstream; this is defense-in-depth for manual invocations.
  - Wildcard support: if an exclude-label arg ends in `*` (e.g. `agent:*`), treat it as a prefix match. Document this explicitly.

Test manually (no shell-level tests exist for the skill; behavior tested via the workflow dry-run in Phase 3):

- `claude /soleur:fix-issue 2378 --exclude-label ux-audit` on an actual `ux-audit` issue should print the benign exit and create nothing.
- `claude /soleur:fix-issue <normal-bug>` (no flags) should behave exactly as today.
- `claude /soleur:fix-issue <agent-authored-issue> --exclude-label 'agent:*'` short-circuits via the prefix-match branch.

**Research Insights — skill-level wildcard parsing:**

- The `*` is treated as a **trailing marker** only; matching is implemented as `label.startswith(pattern_without_star)`. A pattern without a trailing `*` is matched as an exact equality. Mid-string wildcards (`ag*ent:*`) are NOT supported — document this as a non-feature to avoid silently accepting malformed inputs.
- Shell-quoting guidance for callers: pass `--exclude-label 'agent:*'` (single-quoted) or `--exclude-label "agent:*"` (double-quoted in contexts with no `agent:` filename on disk). Without quoting, bash will glob-expand `agent:*` against the CWD; it usually resolves to the literal string because no such files exist, but the plan should not rely on that. `scheduled-bug-fixer.yml`'s invocation uses single quotes already.
- The skill is prompt-executed, not compiled — the "parser" is actually the agent following instructions. Keep the pseudocode simple: "collect values; for each, if it ends in `*`, prefix-match the label list; otherwise exact-match."

### Phase 2 — Canonical jq snippet + workflow adoption

Create `plugins/soleur/skills/fix-issue/references/exclude-label-jq-snippet.md`:

- Contains the canonical clause (two forms — one for list-then-filter, one inline) that excludes any issue whose labels include `ux-audit` OR any label starting with `agent:`.
- Documented as copy-paste into `gh issue list --jq …` consumers.

Example canonical clause (the doc should present this verbatim, with a comment block explaining each branch):

```jq
# Exclude agent-authored issues (see plugins/soleur/skills/fix-issue/references/agent-authored-exclusion.md).
# - ux-audit: legacy stream-specific tag still in active use. Load-bearing: 4 of 5
#   current ux-audit issues (#2378, #2379, #2352, #2351) lack agent:ux-design-lead
#   because they were filed by follow-up sessions, not the ux-audit skill itself.
#   Dropping this branch would silently regress.
# - agent:*: canonical agent-authored prefix; adopted by any future agent-native skill
#   that files issues. Required for new streams; the ux-audit skill itself already
#   applies it on first-filed issues per plugins/soleur/skills/ux-audit/SKILL.md:141.
map(select(
  (.labels | map(.name) | index("ux-audit") | not) and
  (.labels | map(.name) | any(startswith("agent:")) | not)
))
```

**Research Insights:**

**Correctness properties (must hold after every edit to the clause):**

- Both branches are OR'd via `and (... not)` — an issue is kept iff it has NEITHER tag. Removing either branch regresses real tracker state as of 2026-04-18.
- The filter preserves input order. In `scheduled-bug-fixer.yml` it is composed with `sort_by(.createdAt) | .[0].number` AFTER the filter — the FIFO contract from `2026-03-03-scheduled-bot-fix-workflow-patterns.md` (§3) is preserved only because filtering happens before sort. When copying the clause into a new workflow, put it BEFORE any `sort_by` and BEFORE any `.[0]`/`last` reduction.
- `startswith("agent:")` is a jq string method, not a regex. No anchoring concern (`startswith` is implicitly left-anchored). The colon is a literal character; no escaping needed.

**`gh --jq` pitfall (from 2026-03-03 learning):**

- `gh issue list --jq '<expr>'` accepts one jq expression STRING. It does NOT forward jq flags (`--arg`, `--argjson`). Any variable substitution MUST use `export VAR=...; --jq '... $ENV.VAR ...'`, never `--arg`.
- This plan's canonical clause has zero variable substitution — only hard-coded literals `"ux-audit"` and `"agent:"`. The pitfall is documented in `agent-authored-exclusion.md` for future adopters who might want to parameterize the label list.

**Shell-escaping safety (from same 2026-03-03 learning §3):**

- Avoid `!= ""` inside `gh --jq` expressions embedded in YAML `run:` blocks — the `!` gets mangled by shell history expansion under some runners. Use `select(length > 0)` when operating on strings and `| not` to negate predicates.
- The canonical clause uses only `index(...) | not` and `any(...; startswith(...)) | not` — both predicate-negation forms with no bare `!`.

Edit `.github/workflows/scheduled-daily-triage.yml`:

- Line 76: replace the inline `index("ux-audit") | not` clause with the canonical clause above.
- Update the surrounding comment to cite `agent-authored-exclusion.md` rather than explaining the filter inline.

Edit `.github/workflows/scheduled-bug-fixer.yml`:

- Line ~100–107: extend the per-priority `gh issue list --jq` to exclude the same label family. Match `scheduled-daily-triage.yml` — same clause verbatim.
- In the `Fix issue` step (line ~129), append `--exclude-label ux-audit --exclude-label agent:*` to the skill prompt so the skill independently verifies (defense-in-depth): `Run /soleur:fix-issue ${{ steps.select.outputs.issue }} --exclude-label ux-audit --exclude-label 'agent:*'`.

### Phase 3 — Documentation + cross-links

Create `plugins/soleur/skills/fix-issue/references/agent-authored-exclusion.md`. Contents:

1. **Why this exists.** One-paragraph summary of the governance loop (cite the 2026-04-15 learning). Emphasize: label-based exclusion is the load-bearing mechanism.
2. **Label convention.** Every agent-native skill that files GitHub issues MUST apply:
   - A **stream tag** (e.g. `ux-audit`) identifying the source agent/skill — matches the existing `ux-audit` label.
   - An **`agent:<role>` label** (e.g. `agent:ux-design-lead`, `agent:ticket-triage`) identifying the authoring agent.
   - Reference `scheduled-ux-audit.yml` lines 58–63 as the canonical example.
3. **Workflows that honor exclusion.** List `scheduled-bug-fixer.yml` and `scheduled-daily-triage.yml` with the exact lines that filter. Any future issue-consuming workflow MUST include the canonical jq clause from `exclude-label-jq-snippet.md` and the `--exclude-label ux-audit --exclude-label 'agent:*'` flag on any `fix-issue` invocation.
4. **Adding a new agent-authored stream.** 5-bullet checklist:
   - Apply both the stream tag AND `agent:<role>` label at `gh issue create` time.
   - If the stream tag is new (not `ux-audit`), add it to the canonical jq clause in `exclude-label-jq-snippet.md` AND to both consumer workflows.
   - Default milestone `Post-MVP / Later` (brainstorm pattern 2, row 1).
   - Add per-run cap and global cap to the authoring skill.
   - Announce the new stream in the PR description so reviewers verify the exclusion.
5. **How to test.** Three manual checks: run the authoring skill end-to-end in dry-run, run daily-triage with a workflow_dispatch, run the bug-fixer manually with the new stream's label on a test issue to confirm it's skipped.

Edit `knowledge-base/project/learnings/2026-04-15-brainstorm-calibration-pattern-and-governance-loop-prevention.md`:

- Append a "Routed to definition" block at the bottom citing `plugins/soleur/skills/fix-issue/references/agent-authored-exclusion.md` as the enforcement surface.

Edit `.github/workflows/scheduled-ux-audit.yml`:

- Top-of-file comment: add a one-line pointer to `agent-authored-exclusion.md` so future editors see the governance contract from here too.

### Phase 4 — Verify

1. **Run `markdownlint-cli2 --fix`** on the three new/modified `.md` files (targeted paths per [cq-markdownlint-fix-target-specific-paths]).
2. **Syntax-check workflow YAML** with `actionlint` or `yamllint` locally (the two modified workflows — the jq change is a string, not YAML structure, but we still want to eyeball indentation).
3. **Unit-test the canonical jq clause against live tracker data** BEFORE any workflow_dispatch. Run locally:

   ```bash
   gh issue list --state open --limit 200 --json number,title,labels | \
     jq 'map(select(
       (.labels | map(.name) | index("ux-audit") | not) and
       (.labels | map(.name) | any(startswith("agent:")) | not)
     )) | length'
   # Compare against:
   gh issue list --state open --limit 200 --json number | jq length
   # The difference should equal the count of open ux-audit + agent:* issues.
   ```

   Then enumerate the dropped issues to confirm each one is a genuine agent-authored exclusion — no false positives. This is the cheapest unit test of the whole change and catches jq syntax/logic errors before burning a CI minute.
4. **Manual workflow_dispatch of `scheduled-daily-triage.yml`** in the PR branch (after push) to confirm the generalized filter doesn't regress — no `ux-audit` or `agent:*` issues should be re-triaged, and no untriaged non-agent issue should be dropped.
5. **Manual workflow_dispatch of `scheduled-bug-fixer.yml`** with `inputs.issue_number` set to an actual `ux-audit` issue (e.g. #2378). Expected: the skill's Phase 1 short-circuit logs the benign exit message and no PR is opened. Confirms the defense-in-depth skill-level guard fires even when the scheduler's upstream filter is bypassed via explicit `issue_number` input.
6. **Regression check for normal p3-low bug flow:** trigger `scheduled-bug-fixer.yml` without `issue_number` input against a real `priority/p3-low` `type/bug` issue. Expected: unchanged behavior — the skill runs, opens a PR, labels it, auto-merge gate evaluates.
7. **Post-merge verification** (per [wg-after-merging-a-pr-that-adds-or-modifies]): wait for the next natural `scheduled-daily-triage` cron (04:00 UTC) and `scheduled-bug-fixer` cron (06:00 UTC) runs on main; confirm both complete green.

All six verifications before merge + the post-merge cron check are per [wg-when-a-feature-creates-external] (every new/changed mechanism is exercised once before merge) and [wg-after-merging-a-pr-that-adds-or-modifies] (post-merge workflow validation).

## Acceptance Criteria

- [ ] `plugins/soleur/skills/fix-issue/SKILL.md` parses `--exclude-label` (multi-value, supports `*` suffix wildcard for prefix matching like `agent:*`; rejects mid-string wildcards) and exits benignly when the issue carries any excluded label.
- [ ] Backward compatibility: `claude /soleur:fix-issue <number>` (bare) still works and behaves as before (confirmed by the first manual test in Phase 4).
- [ ] `scheduled-bug-fixer.yml` selection step excludes `ux-audit` AND any `agent:*` label via the canonical jq clause, preserving the existing `sort_by(.createdAt) | .[0]` FIFO contract.
- [ ] `scheduled-bug-fixer.yml` invokes the skill with `--exclude-label ux-audit --exclude-label 'agent:*'` (defense-in-depth).
- [ ] `scheduled-daily-triage.yml` uses the same canonical jq clause, verbatim.
- [ ] `plugins/soleur/skills/fix-issue/references/agent-authored-exclusion.md` exists and documents: the label convention, which workflows honor it, the `gh --jq` pitfall, the load-bearing role of the `ux-audit` branch, the 5-bullet "add a new agent-authored stream" checklist, and the manual test plan.
- [ ] `plugins/soleur/skills/fix-issue/references/exclude-label-jq-snippet.md` exists, contains the canonical clause with correctness-property comments, and is referenced from both consumer workflows' comment blocks.
- [ ] The 2026-04-15 governance learning file carries a "Routed to definition" pointer to the new reference.
- [ ] Phase 4 step 3 jq unit-test: local `gh issue list | jq '<canonical-clause>'` drops exactly the expected `ux-audit` + `agent:*` issues, no false positives.
- [ ] Manual `workflow_dispatch` runs of `scheduled-daily-triage.yml` and `scheduled-bug-fixer.yml` (with and without `ux-audit` issues in the queue) produce expected behavior.
- [ ] Manual regression: a real `priority/p3-low` `type/bug` issue is still fixable end-to-end via `scheduled-bug-fixer.yml`.
- [ ] Post-merge: next natural `scheduled-daily-triage` and `scheduled-bug-fixer` cron runs on main complete green within 24h of merge.

## Test Scenarios

Infrastructure/tooling changes have no code-level tests. The skill-level change is test-exempt under [cq-write-failing-tests-before] (infrastructure/tooling-only task). Verification is the 6-step Phase 4 manual plan above PLUS a cheap jq-level fixture test documented here:

**Fixture test (runnable locally without network):**

```bash
cat <<'EOF' | jq 'map(select(
  (.labels | map(.name) | index("ux-audit") | not) and
  (.labels | map(.name) | any(startswith("agent:")) | not)
))'
[
  {"number": 1, "title": "normal bug",       "labels":[{"name":"type/bug"},{"name":"priority/p3-low"}]},
  {"number": 2, "title": "ux-audit finding", "labels":[{"name":"ux-audit"},{"name":"domain/product"}]},
  {"number": 3, "title": "agent finding",    "labels":[{"name":"agent:ux-design-lead"},{"name":"type/feature"}]},
  {"number": 4, "title": "both labels",      "labels":[{"name":"ux-audit"},{"name":"agent:ux-design-lead"}]},
  {"number": 5, "title": "bug mentions agent","labels":[{"name":"type/bug"},{"name":"priority/p2-medium"}]}
]
EOF
```

Expected output: issues #1 and #5 only (normal bug; "agent" in title is not a label). Issues #2, #3, #4 all dropped. Use this fixture as a copy-paste regression check any time the clause changes.

Run this fixture test at implementation time as part of Phase 4 step 3, BEFORE committing the workflow edits. It catches jq syntax errors (missing parens, wrong operator precedence) in under a second, without a `git push` + workflow_dispatch round-trip.

## Risks

- **Wildcard parsing in the skill (`agent:*`) is a new surface.** Risk: the glob-to-prefix translation in the skill's Phase 0 parser is subtle. Mitigation: the skill is markdown-level pseudocode that the agent interprets at runtime — the prompt explicitly says "treat trailing `*` as prefix match, reject mid-string wildcards." No regex injection risk because the exclude-label args come from workflow YAML or a developer's CLI, not untrusted input. Shell-glob expansion risk is mitigated by documenting the single-quote invocation form and using it in `scheduled-bug-fixer.yml`.
- **Label convention drift.** If a future agent-authored skill forgets the `agent:<role>` label, the exclusion silently fails. Mitigation: the 5-bullet checklist in `agent-authored-exclusion.md` is the contract; reviewer of any new agent-native PR must verify both labels are applied. A follow-up CI lint (tracked separately, not this PR) could assert any new `gh issue create` with a stream-tag also sets an `agent:*` label — deferred because we have 1 active stream today and the checklist is sufficient friction.
- **jq clause generalization could accidentally skip legitimate issues.** Example misreads: a non-agent issue mentioning `agent` in the title but not in a label; an issue labeled `domain/agents` if we ever add such a domain. Mitigation: Phase 4 step 3 runs the filter against the live tracker before merge and enumerates the dropped issue list for visual confirmation. The `startswith("agent:")` anchor (colon is mandatory) narrows the match to the label family deliberately; generic "agent" mentions in titles/bodies aren't affected.
- **Skill defense-in-depth collides with scheduler filter.** If the scheduler already filters and the skill ALSO skips, there's zero observable behavior change on the happy path. That's the intent; the short-circuit fires only for manual invocations (`claude /soleur:fix-issue <N>` with no flags, OR with `--exclude-label` flags) and for `workflow_dispatch` with an explicit `issue_number` input that bypasses selection filtering. Tested in Phase 4 step 5.
- **Retroactive stream-tag dependency.** 4 of 5 current `ux-audit` issues lack `agent:ux-design-lead` because they were filed by follow-up sessions, not the `ux-audit` skill itself. The `ux-audit` branch of the jq clause is therefore load-bearing for existing tracker state — a well-meaning cleanup that "DRYs up" the clause by keeping only `agent:*` would silently regress. Mitigation: `exclude-label-jq-snippet.md` calls this out with a date-stamped note; the clause must be changed together with a one-shot retroactive label sweep if the `ux-audit` branch is ever removed.
- **`gh --jq` does not forward jq flags.** Per `2026-03-03-scheduled-bot-fix-workflow-patterns.md`: `gh issue list --jq` rejects `--arg`/`--argjson`. The canonical clause uses only hard-coded literals so it's safe. If a future adopter parameterizes the excluded label set (e.g. for a per-repo config), they MUST use `export VAR=...; jq '... $ENV.VAR ...'` via a pipe — NOT `gh issue list --jq ... --arg VAR ...`. Documented in `agent-authored-exclusion.md`.

## Open Code-Review Overlap

None. Scanned `gh issue list --label code-review --state open` (64 open). No open code-review issue mentions `plugins/soleur/skills/fix-issue/SKILL.md`, `scheduled-bug-fixer.yml`, or `scheduled-daily-triage.yml`.

## Domain Review

**Domains relevant:** engineering, product

### Engineering (CTO)

**Status:** reviewed (planner assessment; governance/tooling change inside existing CI surfaces — no new architecture, no new dependencies, no infrastructure provisioning).
**Assessment:** The change is well-bounded: one skill markdown edit, two workflow string edits, two small reference docs. The defense-in-depth pattern (filter upstream + re-check in the skill) matches the existing auto-merge-gate pattern in `scheduled-bug-fixer.yml` (lines 157–212 re-check file count and priority even though the skill already applied the label). No architectural implications; CTO full invocation not required.

### Product (CPO)

**Tier:** NONE.
**Rationale:** The plan adds a skill flag and a jq filter. It discusses agent-authored issue flows but implements zero user-facing surface (no new pages, no new components, no modal, no UI text). Mechanical escalation rule (new `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`) — no matches. CPO full invocation skipped.

No wireframes, no copywriter review, no spec-flow-analyzer invocation.

## Alternatives Considered

| Approach | Rejected because |
|---|---|
| Hard-code a second label (`ux-audit` and `codeql-auto`) in each workflow when we hit the next agent-authored stream | This is exactly the pattern #2344 is trying to prevent. |
| Detect agent authorship via PR author (`[bot]` suffix) instead of label | PRs and issues are different objects — issues have no author slug; even if they did, authorship is set by the agent's token, which can change. Labels are stable and declarative. |
| Build a dedicated "agent-issue-registry" workflow that re-labels daily | Over-engineered for the current footprint (1 active agent-authored stream). The label-convention approach scales to N streams with zero new moving parts. |
| Put the jq clause directly in `AGENTS.md` as a hard rule | AGENTS.md is for rules the agent would violate without prompting on every turn. A jq snippet belongs in a reference doc. AGENTS.md gets a pointer in the existing "When deferring a capability, create a GitHub issue" gate family if needed, but not required for this PR. |

## Deferral Tracking

None. This plan consumes a deferral (#2344 was itself a deferral from #2341's brainstorm) and introduces no new ones.

## PR Metadata (for /ship)

- **Title:** `feat(governance): exclude agent-authored issues from auto-fix and auto-triage`
- **Body closes:** `Closes #2344`
- **Semver label:** `semver:patch` (additive governance hardening; no new agent, skill, or user-facing capability — the `fix-issue` skill's input surface extension is backward compatible).
- **Labels:** `type/feature`, `domain/engineering`, `domain/product`, `priority/p2-medium` (inherited from #2344).
- **Changelog section:**

  ```markdown
  ## Changelog

  - Added `--exclude-label` option to the `fix-issue` skill (backward compatible).
  - Generalized the agent-authored exclusion filter in `scheduled-bug-fixer.yml` and `scheduled-daily-triage.yml` to cover `ux-audit` and any `agent:*` label.
  - Documented the governance pattern in `plugins/soleur/skills/fix-issue/references/agent-authored-exclusion.md` as a first-class opt-in for future agent-native issue streams.
  ```
