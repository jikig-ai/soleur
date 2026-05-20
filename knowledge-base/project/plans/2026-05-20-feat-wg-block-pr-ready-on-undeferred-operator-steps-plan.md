---
lane: procedural
requires_cpo_signoff: false
---

# feat: add workflow gate `wg-block-pr-ready-on-undeferred-operator-steps`

Closes #4117. Adds `/ship` Phase 5.5 pre-flight that blocks PR-ready when the PR body contains "operator runs"-class steps without a `Tracks #NNNN` / `Refs #NNNN` companion linking to an OPEN `type/chore` (or `type/feature`) issue carrying the `deferred-automation` / `automation gap` sentinel.

Enforces existing hard rule `hr-never-label-any-step-as-manual-without` at the `gh pr ready` boundary. Mirrors the precedent of `wg-after-marking-a-pr-ready-run-gh-pr-merge`.

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** 6 (Detection regex, Phase 3 budget reckoning, Self-block risk, AC, Sharp Edges, Test Strategy)
**Live verifications run:** `gh issue view 3244 4066 4114 4115 4117` (states + titles); `python3 scripts/lint-agents-rule-budget.py` (current B_ALWAYS=24499, cap=22000); `sed -n '88,126p' .claude/hooks/session-rules-loader.sh` (loader-class semantics); regex self-application against the plan body (18 hits with original regex, 5 hits with the tighter list-anchored variant); top-10 longest-rule audit via `awk` (L15=1372 B, L55=1040 B both over 600 B cap pre-existing); `head -40 .claude/hooks/lib/incidents.sh` (emit_incident contract).

### Key Improvements

1. **Detection regex hardened to list-anchored form.** Original whole-line regex produced 18 false-positives against the plan body itself (and would do similar in the PR body). The tighter list-anchored regex (`^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+...`) reduces this to 5, all of which are genuine list-shape declarations. Prose-style references to the word "operator" inside paragraph text are now correctly excluded.
2. **Phase 3 budget reckoning made concrete with numbers.** Pre-existing B_ALWAYS=24499 (cap 22000) means the lefthook BUDGET linter is failing TODAY on every AGENTS*.md commit. Two existing rules already exceed the 600 B per-rule cap (L15=1372 B, L55=1040 B). Plan now quantifies the budget gap (≥2499 B to reclaim BEFORE this PR's adds; ≥2700 B INCLUDING) and walks the three valid paths (retire, demote, trim) with byte-impact numbers.
3. **Loader-class-fit analysis added for demotion candidates.** Original plan recommended demoting `wg-after-a-pr-merges-to-main-verify-all` core→rest. Deeper analysis of `.claude/hooks/session-rules-loader.sh` lines 88-126 shows `rest` does NOT load on `docs-only` change-sets — and docs-only PRs (AGENTS.md edits, learning files) still merge and trigger release workflows, where the rule needs to fire. Demotion would silently no-op for that class. Plan now recommends the BODY-TRIM path on the two over-cap rules (L15 down to ~580 B, L55 down to ~580 B) as the cleaner option, reclaiming ~1232 B; combined with the retirement of one stale `wg-*` (operator picks) for the remaining gap.
4. **Recursive-self-block risk fleshed out with concrete data.** This PR's body will contain ~2 list-anchored AC-PM1 mentions after the regex tightening. Plan now prescribes a Phase 5.4 dry-run AND a canonical PR-body authoring convention (use prose-style "AC-PM1" mid-paragraph, not numbered-list-leading `**AC-PM1**`, when the reference is descriptive rather than declarative).
5. **`emit_incident` contract verified.** The helper in `.claude/hooks/lib/incidents.sh` takes `(rule_id, event, command_snippet)` — the plan's gate body call is well-formed. No drift.
6. **All 5 cited issue/PR numbers verified live.** #3244 (CLOSED — umbrella), #4066 (MERGED — PR-H), #4114 (OPEN, type/chore, sentinel present), #4115 (OPEN, type/feature, sentinel present), #4117 (OPEN, this issue).

### New Considerations Discovered

- The `cq-agents-md-tier-gate` loader-class-fit rule is the cheapest catch-time for the demotion-vs-trim choice; plan now cites it explicitly in §Phase 3.
- The pre-existing B_ALWAYS breach was likely introduced by PR-H itself (#4066) — the rule `hr-tagged-build-workflow-needs-initial-tag-push` at L15 was added there and is 1372 B (more than 2× the 600 B per-rule cap). This is a separate cleanup candidate that the operator MAY fold in.
- The detection regex MUST NOT match the literal string `Operator runs` inside a fenced code block (markdown ```text``` block), because the gate body's own documentation in `ship/SKILL.md` quotes the regex's anchor patterns. Plan now adds a `awk` pre-filter step that strips fenced code blocks from the PR body before regex application.

## Overview

**Problem (verbatim from issue body, paraphrased for plan brevity):** PR-H (#3244 / #4066) violated `hr-never-label-any-step-as-manual-without`. The PR body declared 3 post-merge operator steps (`terraform apply` for 3 tf files, GitHub App creation, Doppler `prd_kb_drift_walker` bootstrap) without filing deferred-automation issues alongside. The gap was only caught post-merge. Filed-too-late: #4114 (terraform apply automation), #4115 (App Manifest flow). Failure mode: silent-manual-step accretion.

**Proposal:** Option α — pre-flight check in `plugins/soleur/skills/ship/SKILL.md` Phase 5.5. Runs regex over `gh pr view --json body`, prompts operator with structured 3-choice when matches lack a `Tracks #NNNN` companion (file new / cite existing OPEN / override with attestation). Clean choke point, no CI minutes. Option β (GitHub Action) explicitly deferred.

## User-Brand Impact

- **If this lands broken, the user experiences:** silent-no-op gate — operators continue shipping PRs with un-tracked operator steps, the rule remains honor-system, and the `/ship` skill ceremony performs without changing behavior. False sense of enforcement is worse than no gate.
- **If this leaks, the user's data/workflow/money is exposed via:** N/A — this is a workflow-quality gate, not a data-handling change. No regulated data surface, no auth flow, no payment.
- **Brand-survival threshold:** `aggregate pattern`. The accreting manual-step debt is corrosive over time (operator burnout, weekend pages, dropped post-merge steps) but no single failure is a brand-ending event. The first manifestation (PR-H) was caught and remediated before any user-visible damage. CPO sign-off is NOT required at plan time.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| "regex over PR body via `gh pr view --json body`" using `(?i)` flag | Bash `[[ =~ ]]` uses ERE — no `(?i)` modifier. `grep -iE` is the right tool. The regex set is sound; only the engine choice changes. | Switch syntax to `grep -iE` in detection step; drop `(?i)` from anchors (use `grep -i` flag instead). |
| "linked issue contains sentinel `deferred-automation` or `automation gap`" | Verified against #4114 (contains `deferred-automation backlog item`) and #4115 (contains `deferred-automation backlog item`). Both OPEN. #4114 = type/chore, #4115 = type/feature. | Sentinel regex confirmed grep-able: `'deferred-automation|automation gap'` against `gh issue view <N> --json body --jq .body`. |
| "Add gate to `Phase 5.5`" | Phase 5.5 exists in `plugins/soleur/skills/ship/SKILL.md:270` (`## Phase 5.5: Pre-Ship Review Gates`) with multiple `### ...Gate` subsections, terminated by `## Phase 6.4: Unpushed-Commits Gate` at line 608. Natural insertion point is between "### Retroactive Gate Application" (line 583) and "## Phase 6.4". | Plan §Files to Edit inserts new `### Undeferred Operator-Step Gate (mandatory)` subsection at line 607 (immediately before `## Phase 6.4`). |
| "Cross-reference the new gate ID in `hr-never-label-any-step-as-manual-without`'s `Why:` line" | The rule body at `AGENTS.core.md:13` does NOT currently have a `Why:` clause — it's a flat rule body. Adding `[skill-enforced: ship Phase 5.5 + ...]` enforcement tag follows the existing pattern (`hr-all-infrastructure-provisioning-servers` line 17 uses `[skill-enforced: plan Phase 2.8 + iac-plan-write-guard.sh]`). | Plan adds `[skill-enforced: ship Phase 5.5 Undeferred Operator-Step Gate]` tag AND a `**Why:** see wg-block-pr-ready-on-undeferred-operator-steps` clause. Both are mechanically grep-discoverable. |
| Issue allows Option β GitHub Action | Explicitly deferred per issue body. | Plan §Out of Scope lists Option β; plan §Acceptance is α-only. |
| **PRE-EXISTING BUDGET BREACH** (not in spec) | `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` returns `[REJECT] B_ALWAYS=24499 > 22000`. Lefthook fires on every AGENTS*.md commit. Lines 15 and 55 also exceed the 600 B per-rule cap. | **Plan §Files to Edit MUST account for this.** AGENTS.core.md edit (cross-ref + enforcement tag on `hr-never-label-any-step-as-manual-without`) adds ~85 B to the rule, pushing B_ALWAYS to ~24585 — still way over 22000. The pre-existing breach is NOT this PR's problem to solve in totality, but the lefthook will block the commit. See §Sharp Edges and §Open Code-Review Overlap for the disposition. |

## Files to Edit

1. **`plugins/soleur/skills/ship/SKILL.md`** — insert new `### Undeferred Operator-Step Gate (mandatory)` subsection between "Retroactive Gate Application" (currently ends at line 606) and `## Phase 6.4: Unpushed-Commits Gate` (currently line 608). Add the subsection to the Final Checklist (line 250) by appending `- [ ] Undeferred operator-step gate passed (Phase 5.5 gate)`.

2. **`AGENTS.core.md`** — edit line 13 (`hr-never-label-any-step-as-manual-without` rule body):
   - Add `[skill-enforced: ship Phase 5.5 Undeferred Operator-Step Gate]` enforcement tag (mirrors pattern at line 17 / line 21 / line 28 / line 29).
   - Append `**Why:** see wg-block-pr-ready-on-undeferred-operator-steps; PR-H #4066 trigger case.` at the end of the rule body line. This is the grep-discoverable cross-reference required by the issue's acceptance criterion ("future drift between the rule and the gate is grep-discoverable").
   - Final rule line length verified ≤ 600 B before commit.

3. **`AGENTS.md`** (pointer index) — add new line in `## Workflow Gates` section:
   - `- [id: wg-block-pr-ready-on-undeferred-operator-steps] → core` — placed after line 64 (`wg-end-of-work-emit-resume-prompt → core`) to keep ship-boundary gates adjacent.

4. **`AGENTS.core.md`** — append new workflow gate to `## Workflow Gates` section (immediately after line 55, the `wg-end-of-work-emit-resume-prompt` block). New rule body (target ≤ 580 B to stay under 600 cap):
   ```
   - At `gh pr ready` boundary, `/ship` Phase 5.5 blocks PR-ready when the PR body contains undeferred operator-action references [id: wg-block-pr-ready-on-undeferred-operator-steps] [skill-enforced: ship Phase 5.5 Undeferred Operator-Step Gate]. Detection: regex over `gh pr view --json body` for "operator runs/creates/...", `AC-PM\d+`, "manual gate", "post-merge operator"; each match needs a `Tracks #NNNN` / `Refs #NNNN` companion to an OPEN `type/chore`/`type/feature` issue carrying sentinel `deferred-automation` or `automation gap`. **Why:** PR-H #4066 — `hr-never-label-any-step-as-manual-without` was honor-system; #4114/#4115 filed post-merge.
   ```
   Body byte count target: ≤580 B. Verify with `wc -c` before commit.

5. **`plugins/soleur/test/ship-undeferred-operator-step-gate.test.ts`** (new file, NOT under Files to Create because the convention in `plugins/soleur/test/` co-locates `<gate>.test.ts` files at the test root) — bun:test fixture covering:
   - **TC-1 (self-test, structure):** ship/SKILL.md contains `### Undeferred Operator-Step Gate` subsection and references the gate ID.
   - **TC-2 (regex correctness, positive):** synthetic PR body fixture with two `Operator runs ...` lines and one `AC-PM1` reference; gate regex matches all 3.
   - **TC-3 (regex correctness, negative):** synthetic PR body with `Refs #4114` companion line within 1 line of one of the operator-action lines; gate considers that one resolved, flags the other two.
   - **TC-4 (PR-H counterfactual):** static fixture mirroring PR #4066's "Post-merge operator tasks" section verbatim (AC-PM1-AC-PM6, no `Tracks` companions); regex flags ≥3 matches (covering the 3 unfiled steps in the issue body).
   - **TC-5 (sentinel detection):** mock issue body containing `deferred-automation` matches; one without doesn't.
   - **TC-6 (cross-reference invariant):** `AGENTS.core.md` rule body of `hr-never-label-any-step-as-manual-without` contains the literal string `wg-block-pr-ready-on-undeferred-operator-steps` (grep-discoverable drift detector).

6. **`plugins/soleur/test/fixtures/ship-undeferred-operator-step-gate/`** (new directory) — two fixture files:
   - `pr-h-counterfactual.md` — verbatim copy of PR #4066's "Post-merge operator tasks" section (already fetched at plan time; static).
   - `mixed-tracked-untracked.md` — synthetic PR body: two un-tracked + one tracked operator step, used by TC-2/TC-3.

## Files to Create

- `knowledge-base/project/learnings/best-practices/2026-05-20-tagged-build-workflow-needs-initial-tag-push.md` — receives the verbose `**Why:**` + `**How to apply:**` content trimmed out of `AGENTS.core.md:15` per Phase 3.2.a. Source content is the current L15 rule body's `**Why:**` clause (`PR-F #3940 shipped ...`) and `**How to apply:**` clause (`during /plan Phase 2, when ...`).
- Beyond that, no NEW files — the test file + fixtures are listed in §Files to Edit (5, 6).

## Additional Fold-In Files to Edit (per Phase 3.2.a)

7. **`AGENTS.core.md:15`** (`hr-tagged-build-workflow-needs-initial-tag-push`) — trim from 1372 B to ≤580 B. Replace the body's verbose `**Why:**` + `**How to apply:**` clauses with: `**Why:** see knowledge-base/project/learnings/best-practices/2026-05-20-tagged-build-workflow-needs-initial-tag-push.md; PR-F #3940 trigger case.`
8. **`AGENTS.core.md:55`** (`wg-end-of-work-emit-resume-prompt`) — trim from 1040 B to ≤580 B. Move the "Required fields" enumeration to `plugins/soleur/skills/work/SKILL.md` §Resume Prompt (verify the section exists; if not, create it with the trimmed content). Body becomes a one-sentence canonical statement + `**Why:** see work/SKILL.md §Resume Prompt; convention-not-codified drifted across sessions.`
9. **`plugins/soleur/skills/work/SKILL.md`** (potentially) — receive the trimmed "Required fields" content from L55 if the §Resume Prompt section does not already contain it. Verify with `grep -n "§Resume Prompt\|Required fields:" plugins/soleur/skills/work/SKILL.md`.
10. **`scripts/retired-rule-ids.txt`** — append at least one entry: `<wg-id> | 2026-05-20 | #<this-PR-number> | <breadcrumb to replacement / rationale>`. Operator picks the `wg-*` to retire from the candidate list in Phase 3.2.a.
11. **`AGENTS.md`** — remove the pointer-index entry for any retired `wg-*` (mirrors removal from `AGENTS.core.md`).

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json`; for each planned file path (`plugins/soleur/skills/ship/SKILL.md`, `AGENTS.core.md`, `AGENTS.md`) run `jq -r --arg path "<path>" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json`.

**Run-time deferral:** the operator who runs `/work` from this plan MUST execute the above commands against live state before Phase 0; freezing scoped-out issue numbers in a plan written days before /work-time is brittle (the issue list rotates).

**Default disposition rule:** any `code-review` issue whose body names `AGENTS.core.md` rule-body bloat or AGENTS budget overruns is **Acknowledged** (different concern from this gate; this plan adds ~85 B to a rule body within the 600 B cap; the B_ALWAYS aggregate breach is a separate cleanup PR — see §Sharp Edges). Any `code-review` issue naming `ship/SKILL.md` Phase 5.5 structural changes is **Fold in** with explicit `Closes #N` in the PR body.

## Domain Review

**Domains relevant:** Engineering (workflow tooling). No CMO/CPO/CFO/CLO/CRO/COO/CCO implications — this is a procedural gate-tightening change with no user-visible surface, no marketing artifact, no legal text, no expense.

Procedural gate per `lane: procedural` — single-domain (Engineering). The CTO leader's plan-time concern would be (a) is the detection regex correct, (b) is the choke point right, (c) does the gate match the rule it claims to enforce. All three are addressed in §Implementation Phases.

No cross-domain blast radius. No Product/UX Gate trigger (no new user-facing surface; this lives entirely inside the `/ship` skill which is operator-tool-only).

## GDPR / Compliance Gate

**Trigger evaluation:**

- Canonical regex (`^(apps/web-platform/supabase/migrations/|apps/web-platform/lib/auth/|apps/web-platform/server/.*auth.*\.(ts|tsx|js)|apps/web-platform/app/api/.*\.(ts|tsx)$|.*\.sql$)`) — none of the planned files match.
- Expansion triggers (a)-(d): (a) no new LLM/external-API processing of operator-session data, (b) brand-survival threshold is `aggregate pattern` not `single-user incident`, (c) no new cron/workflow reading from `learnings/` or `specs/`, (d) no new artifact distribution surface.

**Verdict:** SKIP — no regulated-data surface touched, none of the expansion triggers fire.

## Infrastructure (IaC)

**Trigger evaluation:** plan touches `plugins/soleur/skills/ship/SKILL.md`, `AGENTS.core.md`, `AGENTS.md`, and one bun:test file. Zero SSH wording, zero `terraform apply`, zero `systemctl`, zero vendor-dashboard wording, zero `doppler secrets set`. No new infrastructure resource introduced.

**Verdict:** SKIP — pure docs/test change. No `## Infrastructure (IaC)` section required.

## Implementation Phases

### Phase 0 — Preconditions (run by /work, not at plan time)

0.1. **Re-verify lefthook budget state.** Run `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md`. If `B_ALWAYS` exceeds 22000 BEFORE this PR's edits, the operator MUST either (a) execute the disposition recorded in §Sharp Edges (file a paired demotion/trim PR first and merge it), or (b) explicitly accept that this PR will fail the lefthook budget linter at commit time and reach for the linter override path (currently none — see §Sharp Edges for the open question). The plan body strongly prefers (a).

0.2. **Re-verify issue state.** `gh issue view 4114 --json state,labels` and `gh issue view 4115 --json state,labels` to confirm both still OPEN, still labeled `type/chore` / `type/feature` respectively, AND bodies still contain `deferred-automation` sentinel. If any has been closed in the interim, the PR-H counterfactual fixture (TC-4) needs to swap to the next OPEN deferred-automation issue.

0.3. **Re-verify Phase 5.5 boundary.** `grep -n "^## Phase 6.4\|^### Retroactive Gate Application" plugins/soleur/skills/ship/SKILL.md` to confirm insertion-point line numbers haven't shifted. If they have, recompute the insertion point.

0.4. **Re-verify codebase regex precedent.** `grep -nE "grep -iE" plugins/soleur/skills/ship/SKILL.md plugins/soleur/skills/*/SKILL.md | head -5` to confirm `grep -iE` is the prevailing shell-side regex form in skill bodies (it is — see existing Phase 5.5 gates around lines 460, 487).

### Phase 1 — TDD: write failing tests first (RED)

1.1. Create `plugins/soleur/test/fixtures/ship-undeferred-operator-step-gate/pr-h-counterfactual.md` containing the verbatim "Post-merge operator tasks" section of PR #4066 (already captured via `gh pr view 4066 --json body --jq .body` at plan time; the literal 6 bullets `AC-PM1`-`AC-PM6`). NO `Tracks` companion lines on any of them.

1.2. Create `plugins/soleur/test/fixtures/ship-undeferred-operator-step-gate/mixed-tracked-untracked.md`:
   ```markdown
   ## Post-merge operator tasks

   - **AC-PM1** Operator runs `terraform apply` against `infra/foo.tf`. Tracks #4114
   - **AC-PM2** Operator creates GitHub App at github.com/settings/apps/new
   - Operator paste-runs the bootstrap script.
   ```
   Exactly one tracked, two untracked. TC-2/TC-3 expects gate flags exactly 2.

1.3. Create `plugins/soleur/test/ship-undeferred-operator-step-gate.test.ts` skeleton modeled on `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` (bun:test, `import.meta.dir`, `resolve(REPO_ROOT, ...)`, `beforeAll` to load file contents). Define the 6 test cases (TC-1 .. TC-6) above. All must initially fail.

1.4. Run `bun test plugins/soleur/test/ship-undeferred-operator-step-gate.test.ts`. Confirm all 6 fail (RED gate).

### Phase 2 — Implement the gate body (GREEN)

2.1. In `plugins/soleur/skills/ship/SKILL.md`, insert immediately before `## Phase 6.4: Unpushed-Commits Gate`:

```markdown
### Undeferred Operator-Step Gate (mandatory)

Enforces hard rule `hr-never-label-any-step-as-manual-without` at the
`gh pr ready` boundary. Blocks PR-ready when the PR body contains
"operator runs"-class steps without a `Tracks #NNNN` / `Refs #NNNN`
companion linking to an OPEN `type/chore` (or `type/feature`) issue
that carries the `deferred-automation` / `automation gap` sentinel.

Emit rule-application telemetry (records the gate fired):

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident wg-block-pr-ready-on-undeferred-operator-steps applied \
  'At gh pr ready boundary, /ship Phase 5.5 blocks PR-ready when'
```

**Detection.** Capture the PR body once, **strip fenced code blocks** (the gate's own documentation will quote the regex), then run a multi-pattern grep with LIST-ANCHORED patterns. Bash ERE has no `(?i)` modifier — use `grep -iE`.

```bash
PR_BODY=$(gh pr view --json body --jq .body)

# Strip fenced code blocks (```...```) — the gate body and the AC section
# in the PR will quote the regex and the AC-PM tokens; those quotations
# inside ``` fences MUST NOT count as undeferred declarations.
PR_BODY_STRIPPED=$(printf '%s' "$PR_BODY" | awk '
  /^```/ { in_fence = !in_fence; next }
  !in_fence { print }
')
PR_BODY_FILE=$(mktemp); printf '%s' "$PR_BODY_STRIPPED" > "$PR_BODY_FILE"

# LIST-ANCHORED regex: a match requires the LINE to start with a
# bullet (`-`/`*`), a numbered-list marker (`1.`), or a checklist box
# (`- [ ]`/`- [x]`). This excludes prose mid-paragraph mentions of
# "operator" or "AC-PM" that are descriptive, not declarative.
# Deepen-plan reduced 18 → 5 false-positives against the plan body
# with this anchoring.
DETECT_RE='^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+(\[[[:space:]xX]\][[:space:]]+)?(\*\*)?(AC-PM[0-9]+|operator[[:space:]]+(run|create|provision|configure|paste|copies?)s?|manual[[:space:]]+gate|post-merge[[:space:]]+operator)'

MATCHES=$(grep -niE "$DETECT_RE" "$PR_BODY_FILE" || true)
MATCH_COUNT=$(printf '%s\n' "$MATCHES" | grep -c . || true)
```

**Why list-anchored:** PR bodies routinely discuss operator behavior in prose (e.g., "the operator's choice", "the operator runs the script ONCE post-merge per the prior convention"). Only DECLARATIVE list-shape entries (`- Operator runs ...` or `- [ ] **AC-PM3** Operator creates ...`) are operator-step accretion vectors. Prose mentions are review-noise.

**Rule.** For each match, the same line OR the following line MUST contain
`(Tracks|Refs) #NNNN`. Extract every `#NNNN` referenced via `Tracks`/`Refs`
within ±1 line of any match, then for each, verify the linked issue is
OPEN, labeled `type/chore` or `type/feature`, AND its body contains
the sentinel `deferred-automation` or `automation gap` (case-insensitive).

```bash
TRACKED_REFS=$(grep -nE '(Tracks|Refs)[[:space:]]+#[0-9]+' "$PR_BODY_FILE" \
  | grep -oE '#[0-9]+' | tr -d '#' | sort -u)

UNDEFERRED=()
for line_no in $(printf '%s\n' "$MATCHES" | awk -F: '{print $1}'); do
  ctx=$(sed -n "${line_no}p;$((line_no+1))p" "$PR_BODY_FILE")
  refs=$(printf '%s' "$ctx" | grep -oE '(Tracks|Refs)[[:space:]]+#[0-9]+' || true)
  if [ -z "$refs" ]; then
    UNDEFERRED+=("$line_no")
    continue
  fi
  # For each ref on the matched line, verify the linked issue qualifies.
  ok=0
  for n in $(printf '%s' "$refs" | grep -oE '[0-9]+'); do
    state=$(gh issue view "$n" --json state --jq .state 2>/dev/null || echo "")
    [ "$state" = "OPEN" ] || continue
    labels=$(gh issue view "$n" --json labels --jq '[.labels[].name] | join(",")' 2>/dev/null || echo "")
    [[ "$labels" =~ (^|,)type/(chore|feature)(,|$) ]] || continue
    body=$(gh issue view "$n" --json body --jq .body 2>/dev/null || echo "")
    if printf '%s' "$body" | grep -qiE 'deferred-automation|automation gap'; then
      ok=1; break
    fi
  done
  [ "$ok" = 1 ] || UNDEFERRED+=("$line_no")
done
```

**If `${#UNDEFERRED[@]}` is 0:** Pass silently.

**If `${#UNDEFERRED[@]}` > 0:** Halt and present the structured prompt
(3-option choice). The operator chooses one:

1. **File deferred-automation issues now.** For each undeferred match,
   the skill prompts for an issue title + 1-paragraph re-evaluation
   criterion, then runs `gh issue create --label type/chore --title <...>
   --body "<...>\n\nThis is a deferred-automation backlog item per
   wg-block-pr-ready-on-undeferred-operator-steps. Re-evaluate when: <...>"`.
   Update the PR body with `Tracks #NNNN` companions. Re-run detection.
2. **Cite an existing OPEN issue.** Operator pastes `#NNNN` per match.
   Skill verifies state/labels/sentinel and updates the PR body.
3. **Override with operator-attestation.** Operator pastes a 1-paragraph
   justification (rare; e.g., first non-Soleur tenant onboarding triggers
   a one-off K-bis upload). Skill appends a `<!-- gate-override:
   wg-block-pr-ready-on-undeferred-operator-steps -->` HTML comment
   followed by the attestation text to the PR body, then proceeds.

**Headless mode:** abort with the same structured error. No
auto-file/auto-override in headless — operator must run interactively
to make the choice.

**Why:** PR-H #4066 violated `hr-never-label-any-step-as-manual-without`
(3 unfiled deferred-automation steps; #4114 + #4115 filed too late).
This gate moves enforcement from honor-system to mechanical.
```

2.2. Append to the Phase 5 Final Checklist (currently lines 240-255) one new line:

```text
- [ ] Undeferred operator-step gate passed (Phase 5.5 gate)
```

2.3. In `AGENTS.core.md` line 13 (the `hr-never-label-any-step-as-manual-without` rule body), edit to add `[skill-enforced: ship Phase 5.5 Undeferred Operator-Step Gate]` immediately after `[id: hr-never-label-any-step-as-manual-without]`, AND append at end of the body line: ` **Why:** see wg-block-pr-ready-on-undeferred-operator-steps; PR-H #4066 trigger case.`

   **Pre-commit length check:** `awk 'NR==13' AGENTS.core.md | wc -c` must return ≤601 (600 + newline). Adjust by trimming the parenthetical `(operator pastes, Soleur drives)` to `(operator pastes)` if needed (saves 18 B).

2.4. In `AGENTS.core.md` `## Workflow Gates` section, append the new rule body (target ≤580 B):

```text
- At `gh pr ready` boundary, `/ship` Phase 5.5 blocks PR-ready when the PR body contains undeferred operator-action references [id: wg-block-pr-ready-on-undeferred-operator-steps] [skill-enforced: ship Phase 5.5 Undeferred Operator-Step Gate]. Detection: regex over `gh pr view --json body` matches "operator runs/creates/...", `AC-PM\d+`, "manual gate", "post-merge operator"; each needs a `Tracks #NNNN`/`Refs #NNNN` companion to an OPEN `type/chore`/`type/feature` issue with sentinel `deferred-automation` or `automation gap`. **Why:** PR-H #4066 — honor-system gap; #4114/#4115 filed post-merge.
```

   **Pre-commit length check:** length of that line ≤601 B.

2.5. In `AGENTS.md` `## Workflow Gates` pointer-index block (currently lines 43-64), append after line 64:

```text
- [id: wg-block-pr-ready-on-undeferred-operator-steps] → core
```

2.6. Run `bun test plugins/soleur/test/ship-undeferred-operator-step-gate.test.ts`. All 6 tests pass (GREEN).

### Phase 3 — AGENTS budget reckoning (gate this PR explicitly)

3.1. Run `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md`. Current state (verified live at deepen-plan time, 2026-05-20):

   ```text
   [REJECT] B_ALWAYS=24499 > 22000 (AGENTS.md=4960 + AGENTS.core.md=19539).
   AGENTS.core.md:15: ERROR: rule body exceeds 600 B (actual=1372).
     [hr-tagged-build-workflow-needs-initial-tag-push]
   AGENTS.core.md:55: ERROR: rule body exceeds 600 B (actual=1040).
     [wg-end-of-work-emit-resume-prompt]
   ```

   This PR's edits add: ~+95 B (`AGENTS.core.md:13` cross-ref edit), ~+580 B (new `wg-block-pr-ready-on-undeferred-operator-steps` rule body), ~+62 B (`AGENTS.md` pointer-index entry). Total post-PR projection: B_ALWAYS ≈ 25236. **Bytes to reclaim to satisfy the linter: 25236 − 22000 = 3236 B.**

3.2. **Decision gate (operator-facing, halt point):** the lefthook will refuse the commit. Three valid paths, ranked by total-system cost:

   **3.2.a (PREFERRED — fold-in cleanup): trim the two over-cap rules AND retire one stale `wg-*` in THIS PR.**

   The two over-cap rules at L15 and L55 each violate `cq-agents-md-why-single-line` (600 B per-rule cap, separately enforced). They're already an open compliance failure — trimming them as part of this gate-tightening PR is thematically appropriate (the rule we're enforcing is about workflow discipline). Concrete edits:
   - **L15 `hr-tagged-build-workflow-needs-initial-tag-push`** (1372 B → ≤580 B = reclaim ≥792 B). Move the verbose `**Why:**` and `**How to apply:**` clauses (everything after the rule statement) into a new learning file at `knowledge-base/project/learnings/best-practices/2026-05-20-tagged-build-workflow-needs-initial-tag-push.md`. Rule body becomes: one-sentence canonical statement + `**Why:** see learning <path>; PR-F #3940 trigger case.` Pattern: same as the deep-trim already applied to `hr-multi-step-post-merge-bootstrap-script` at L14 (588 B — within cap because the body references a learning file rather than inlining all context).
   - **L55 `wg-end-of-work-emit-resume-prompt`** (1040 B → ≤580 B = reclaim ≥460 B). Same treatment: move the multi-paragraph `Required fields` enumeration into `plugins/soleur/skills/work/SKILL.md` §Resume Prompt (already exists; verify) and leave a one-sentence canonical body in AGENTS.core.md + `**Why:** see work/SKILL.md §Resume Prompt; convention-not-codified drifted across sessions.`

   Combined L15+L55 trim reclaim: ≥1252 B. Still 1984 B short.

   **Retire one stale `wg-*`.** Per the linter's first hint: `Retire a rule via scripts/retired-rule-ids.txt`. Operator nominates a candidate and adds an entry `<id> | 2026-05-20 | #<this-PR> | <breadcrumb>` to `scripts/retired-rule-ids.txt`. Retirement candidates (operator chooses one or more):
   - `wg-when-an-audit-identifies-pre-existing` (L51, ~210 B) — the rule body says "create GitHub issues to track them before fixing"; this is now also covered by `wg-when-deferring-a-capability-create-a` (L52) AND by the new `wg-block-pr-ready-on-undeferred-operator-steps`. Likely redundant.
   - `wg-when-fixing-a-workflow-gates-detection` (L44, ~339 B) — "retroactively apply the fixed gate to the case that exposed the gap"; the present PR could itself retroactively apply this concept to PR-H, but that's already encoded in the §Test Strategy TC-4 counterfactual. Operator decides.
   - Any other `wg-*` rule the operator judges no longer load-bearing.

   The operator's choice goes into `scripts/retired-rule-ids.txt` in the SAME commit as the L15+L55 trim AND this PR's adds. Combined byte budget: ≥1252 (trim) + ≥210 (retire smallest candidate) + reclaim from sidecar overhead = ≥1462. Still ~522 B short.

   **Final reclaim step: AGENTS.md pointer-index trim.** The pointer-index lines for L15's trimmed rule and L55's trimmed rule are unchanged. The retired-rule pointer-index entry is removed (saves ~50 B). For the remaining ~470 B, retire ONE additional `wg-*` rule per the same procedure.

   This entire fold-in is one PR. The fold-in is justified because: (1) the lefthook is failing today AND this PR's commits trip it, (2) per `wg-when-an-audit-identifies-pre-existing` (the rule we're considering retiring), the pre-existing breach is itself an audit finding that requires inline filing, (3) the alternative (file 4 separate PRs) violates `hr-multi-step-post-merge-bootstrap-script` in spirit (collapse multi-step remediation into one).

   **3.2.b (DEPRECATED — sibling demotion PR): NOT recommended.** The original plan recommendation. Loader-class-fit analysis (per `cq-agents-md-tier-gate` and verified at deepen-plan time against `.claude/hooks/session-rules-loader.sh:88-126`) shows that demoting `wg-after-a-pr-merges-to-main-verify-all` core→rest breaks the `docs-only` change-class load (`rest` only loads when `HAS_CODE=1 || HAS_INFRA=1`; pure docs PRs that still trigger release workflows would lose the rule). Same gap applies to every other `wg-*` whose trigger surface includes docs-only changes. The ONLY `wg-*` rule that could safely demote is one whose trigger truly never fires on docs-only sessions — and that class is empty in the current core rule set. **Reject 3.2.b.**

   **3.2.c (DEPRECATED — bypass with `--no-verify`):** violates `hr-when-a-command-exits-non-zero-or-prints` in spirit. REJECT unless the operator has explicit cause filed as a `code-review` issue.

3.3. After 3.2.a edits land in this PR's commit (L15+L55 trim + retired-rule-ids.txt entry + this PR's adds), run `python3 scripts/lint-agents-rule-budget.py ...` AND `python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md`. Both must exit 0. If either fails, iterate on the trim depth or retire one more `wg-*`.

3.4. **Worktree-state caveat.** The deepen-plan analysis ran on the worktree at commit `21793f5d`. If main advances and brings new core rules between now and /work time, the byte numbers above shift. /work Phase 0.1 MUST re-run the linter and recompute the deficit before applying Phase 3.

### Phase 4 — Self-test + counterfactual proof

4.1. **TC-4 PR-H counterfactual.** Load `plugins/soleur/test/fixtures/ship-undeferred-operator-step-gate/pr-h-counterfactual.md`. Run the detection regex from §2.1. Confirm the regex flags ≥3 matches (AC-PM1/AC-PM2/AC-PM3 — the 3 that the issue body explicitly names as unfiled-then-filed; AC-PM4/AC-PM5/AC-PM6 also flag because they too lack `Tracks #NNNN`). The acceptance criterion says "would have caught all 3 unfiled steps" — the regex catches them and then some, which is correct (Type II/false-positive on AC-PM4-6 is acceptable because those were also unfiled-at-merge-time — the operator would have been prompted to file or override for those too).

4.2. **Cross-reference invariant.** Run `grep -F wg-block-pr-ready-on-undeferred-operator-steps AGENTS.core.md`. Must return ≥2 hits (the new wg-* rule body itself, AND the cross-ref appended to `hr-never-label-any-step-as-manual-without`). TC-6 enforces this.

4.3. **Telemetry sanity.** The `emit_incident` line in the new gate body matches the canonical `wg-*` rule ID — `incidents.sh` will tag the recording correctly. Manually verify by `grep -nE 'emit_incident wg-block-pr-ready-on-undeferred-operator-steps' plugins/soleur/skills/ship/SKILL.md` returns 1 hit.

### Phase 5 — /compound + commit + push + PR description

5.1. Run `/soleur:compound` per `wg-before-every-commit-run-compound-skill`. The likely learning: "Skill-side workflow gates need a paired AGENTS budget reckoning at plan time — adding any new core rule when B_ALWAYS already exceeds 22000 requires a paired demotion PR or the commit is blocked." File under `knowledge-base/project/learnings/best-practices/`.

5.2. Stage explicit paths only (per `hr-never-git-add-a-in-user-repo-agents`): `plugins/soleur/skills/ship/SKILL.md`, `AGENTS.core.md`, `AGENTS.md`, `plugins/soleur/test/ship-undeferred-operator-step-gate.test.ts`, `plugins/soleur/test/fixtures/ship-undeferred-operator-step-gate/`.

5.3. Commit with semver:patch (this is a quality gate, not a new user-facing capability — `wg-*` additions are patch).

5.4. Push, `gh pr ready`, then `gh pr merge --auto --squash` per `wg-after-marking-a-pr-ready-run-gh-pr-merge`.

   **Recursive-gate caveat:** this PR's own body MUST NOT trip the new gate. The PR body contains the word "operator" several times (in descriptions of the gate's behavior) — verify that the detection regex's anchors (`(^|[[:space:]]|[-*0-9.])operator[[:space:]]+(run|create|...)s?\b`) do not match phrasing like "the operator's PR body" or "operator-attestation". A pre-flight dry-run against this very PR body before `gh pr ready` is the canonical self-test.

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 — gate body exists in ship/SKILL.md.** `grep -nE '^### Undeferred Operator-Step Gate' plugins/soleur/skills/ship/SKILL.md` returns exactly 1 hit, in the line range 583-608 (between Retroactive Gate Application and Phase 6.4).
2. **AC2 — gate body contains the 3-option structured prompt.** `grep -nE '1\.\s+\*\*File deferred-automation issues|2\.\s+\*\*Cite an existing|3\.\s+\*\*Override with operator-attestation' plugins/soleur/skills/ship/SKILL.md` returns 3 hits.
3. **AC3 — gate body contains the canonical LIST-ANCHORED detection regex AND the fenced-code-block strip.** `grep -nF 'DETECT_RE=' plugins/soleur/skills/ship/SKILL.md` returns ≥1 hit AND the line contains all 5 anchor patterns AND the line starts with `^[[:space:]]*([-*]|[0-9]+\.)` (list-anchored, not whole-line). Separately, `grep -nE 'in_fence = !in_fence' plugins/soleur/skills/ship/SKILL.md` returns ≥1 hit (the `awk` strip for fenced code blocks). Both anchors are required — without the list-anchor, prose-style "operator" mentions trip the gate; without the fence-strip, documentation-class PRs that embed example snippets trip on their own quotations.
4. **AC4 — cross-reference invariant.** `grep -cF 'wg-block-pr-ready-on-undeferred-operator-steps' AGENTS.core.md` returns ≥2 (rule definition + cross-ref in hr-never-label).
5. **AC5 — pointer-index entry.** `grep -F '[id: wg-block-pr-ready-on-undeferred-operator-steps] → core' AGENTS.md` returns 1 hit.
6. **AC6 — per-rule byte cap.** `awk 'NR==13' AGENTS.core.md | wc -c` ≤601. New `wg-*` rule line ≤601 B. (Verifies `cq-agents-md-why-single-line` compliance for both edited rules.)
7. **AC7 — B_ALWAYS budget.** `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` exits 0. Achieved INLINE in this PR via Phase 3.2.a (L15 + L55 trim + ≥1 `wg-*` retirement). Verified via post-trim re-run reported in PR body.
7b. **AC7b — over-cap rules brought under cap.** Verified by linter stderr containing zero "rule body exceeds 600 B" lines AFTER Phase 3.2.a trim. Specifically: L15 (`hr-tagged-build-workflow-needs-initial-tag-push`) and L55 (`wg-end-of-work-emit-resume-prompt`) both ≤600 B.
7c. **AC7c — retired-rule registry updated.** `tail -1 scripts/retired-rule-ids.txt` returns an entry of shape `<retired-id> | 2026-05-20 | #<this-PR> | <breadcrumb>` for at least one `wg-*` retirement.
8. **AC8 — rule-id lint.** `python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` exits 0 (no duplicates, no orphans, retirement entries valid).
9. **AC9 — bun:test green.** `bun test plugins/soleur/test/ship-undeferred-operator-step-gate.test.ts` reports 6/6 pass.
10. **AC10 — PR-H counterfactual concretely demonstrated.** TC-4 fixture proves the regex flags ≥3 matches against PR #4066's verbatim "Post-merge operator tasks" section. Per `cq-test-fixtures-synthesized-only`, the fixture is a static checked-in copy at plan-write time (not a live `gh` call at test-run time).
11. **AC11 — no recursive self-block.** The PR body for this PR, when fed through the new gate's detection regex, either (a) produces zero matches, or (b) every match has a `Tracks #NNNN` / `Refs #NNNN` companion to an OPEN issue carrying the sentinel. Verify before `gh pr ready`.
12. **AC12 — `Ref #4117` in PR body.** Per `wg-use-closes-n-in-pr-body-not-title-to` — this PR is a code-only change (no post-merge operator step), so `Closes #4117` is acceptable in body, not title. The issue auto-closes at merge.

### Post-merge (operator)

13. **AC-PM1 (skill-enforced sanity).** Within 7 days of merge, the next operator who runs `/ship` on a branch whose PR body contains an `Operator runs ...` line without a `Tracks` companion gets prompted with the new gate. (Manual operator verification; no automated post-merge probe — the gate is a /ship-skill-time choke point, not a CI workflow.) Tracks: this single AC-PM exists, but is itself automatable only via post-merge synthetic operator session — DEFERRED to `wg-block-pr-ready-on-undeferred-operator-steps` self-application; not auto-filed because it's a one-shot smoke-test, not a recurring automation gap. Per `hr-never-label-any-step-as-manual-without`, AC-PM1 is the rare class of "subjective decisions requiring human judgment" — the operator must subjectively assess whether the gate prompt was usable.

## Test Strategy

- **Unit/structural:** bun:test against `plugins/soleur/skills/ship/SKILL.md` text per the ship-deploy-pipeline-fix-gate.test.ts pattern (`import { describe, test, expect, beforeAll } from "bun:test"`).
- **Regex correctness:** synthetic fixtures (TC-2, TC-3, TC-4) — never live `gh` calls in tests per `cq-test-fixtures-synthesized-only`.
- **Cross-reference drift:** TC-6 enforces grep-discoverability of the wg-block-* ID inside `hr-never-label-any-step-as-manual-without`'s rule body.
- **Budget linter:** `scripts/lint-agents-rule-budget.py` is the canonical gate; this plan does NOT add a new gate-test for it (the existing linter is the gate). HOWEVER, this plan ADDS Phase 3.2.a inline trim work that brings the linter under cap — verify by running the linter as part of Phase 4 self-test.
- **No integration test against live `gh issue view`** — TC-5 mocks the issue body as a string fixture; live API calls in tests are a flakiness vector.
- **TC-7 (list-anchor false-positive test, NEW):** synthetic PR body containing prose-style `the operator runs a separate audit` and `AC-PM1 is the operator's check` — gate flags 0 matches. Proves the list-anchor correctly excludes prose-style mentions.
- **TC-8 (fenced-code-block strip test, NEW):** synthetic PR body containing a fenced ` ```text - **AC-PM1** Operator runs `terraform apply` ``` ` block — gate flags 0 matches. Proves documentation/code-block content is excluded.
- **TC-9 (over-cap rule trim verification, NEW):** static assertion that `AGENTS.core.md:15` and `AGENTS.core.md:55` rule bodies are each ≤600 B (matches the `cq-agents-md-why-single-line` invariant). Implements as `awk 'NR==15 || NR==55 { if (length > 600) exit 1 }' AGENTS.core.md` inside a `Bun.spawn` test.

## Sharp Edges

- **AGENTS budget pre-existing breach.** B_ALWAYS is at 24499 (cap 22000) BEFORE this PR's edits. The lefthook on AGENTS*.md commits will reject. This plan's Phase 3 explicitly halts for operator decision (3.2.a paired demotion PR is the recommended path). DO NOT bypass with `--no-verify` without filing a follow-up `code-review` issue documenting the breach and the choice.
- **Phase 5.5 insertion-point drift.** If a sibling PR (e.g., a CMO/COO gate addition) lands on main while this branch is open, the insertion-point line number (currently 607) will shift. Rebase + recompute via `grep -n "^## Phase 6.4" plugins/soleur/skills/ship/SKILL.md`.
- **Recursive self-application of the new gate.** This PR's body contains the literal word "operator" in many places. Phase 5.4 prescribes a dry-run of the regex against the PR body before `gh pr ready`. If the regex unexpectedly matches a benign sentence, tighten the regex anchors (the leading `(^|[[:space:]]|[-*0-9.])` is designed to require a list-bullet or whitespace before "operator", which excludes mid-sentence usage like "the operator's choice").
- **Bash ERE has no `(?i)`.** The issue body's spec used `(?i)` PCRE prefix. The plan uses `grep -iE` instead. Functionally equivalent for the chosen patterns. Update any plan-prescribed regex audit to use `grep -iE` not bash `[[ =~ ]]`.
- **`Tracks #NNNN` proximity rule.** The plan defines proximity as "same line OR following line". This is a deliberate narrow window — wider windows (e.g., "anywhere in the PR body") risk false-positive coverage by an unrelated `Tracks` reference earlier in the body. Operator self-discipline + the 3-option override clause cover the rare legit case where the companion lives elsewhere.
- **Sentinel string `deferred-automation` vs `automation gap`.** Both are accepted (per the issue body). The codebase already uses `deferred-automation` in #4114/#4115. The "or `automation gap`" alternate is a forward-compatibility hedge.
- **AC-PM1 in this PR's own acceptance criteria.** AC-PM1 references the new gate's self-application. Per the gate's own logic, AC-PM1 needs a `Tracks #NNNN` companion. The plan explicitly notes AC-PM1 is "subjective operator decision" per `hr-never-label-any-step-as-manual-without`'s "subjective decisions requiring human judgment" carve-out and does NOT need a deferred-automation companion. The gate's structured-prompt option (3) "operator-attestation" is the canonical escape valve for this class.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.**

### Research Insights

**Detection regex — list-anchored form (deepen-plan finding):**

- Self-application against the plan body proved the original whole-line regex `(^|[[:space:]]|[-*0-9.])operator...` produced 18 false-positives, including every prose-style mention of "operator" inside paragraphs. List-anchored `^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+...` reduced this to 5. All 5 are genuine list-shape entries (3 are inside the §Phase 1 fixture content — those won't appear in the PR body; 2 are bullet-list AC references that WILL appear and require either fenced-code-block protection or operator-attestation per §Sharp Edges).
- The detection ALSO strips fenced markdown code blocks via `awk` pre-filter. This is required because `ship/SKILL.md` (and downstream operator-facing docs that quote the gate) embed example PR-body snippets inside ` ```text ` fences for documentation purposes. Without the strip, every doc-PR that touches `ship/SKILL.md` would trip the gate on its own quoted examples.

**`emit_incident` contract (verified live):**

```bash
# .claude/hooks/lib/incidents.sh shape:
emit_incident <rule_id> <event> [<command_snippet>] [<hook_event=PreToolUse>] [<kind=rule_event>]
# Writes JSONL to <repo-root>/.claude/.rule-incidents.jsonl under flock.
# Snippet capped at 1024 chars to stay under 4KB kernel write boundary.
```

The plan's `emit_incident wg-block-pr-ready-on-undeferred-operator-steps applied '<snippet>'` invocation matches this contract.

**Loader-class-fit (verified against `.claude/hooks/session-rules-loader.sh:88-126`):**

```bash
DOCS_RE='\.(md|markdown|txt|njk|html)$|^\.github/.*\.md$'
CODE_RE='\.(ts|tsx|js|jsx|py|go|rs|swift|kt|java|c|cpp|cs|php|sh|bash|zsh|rb)$'
INFRA_RE='\.tf$|^apps/[^/]+/infra/|\.github/workflows/|/?Dockerfile|/migrations/.*\.sql$'

# Class selection:
# - multi-class       → core docs-only rest  (fail-closed for cross-class)
# - docs-only         → core docs-only
# - code OR infra     → core rest
# - empty CHANGES     → core docs-only rest  (fail-closed)
```

For THIS PR's diff (ship/SKILL.md=.md, AGENTS.core.md=.md, AGENTS.md=.md, .test.ts=code, fixtures/*.md=.md): `HAS_DOCS=1 && HAS_CODE=1` → multi-class → loads ALL. So when this PR is in /work, the new `wg-*` rule is visible in core (correct). For FUTURE /ship sessions, if the operator's branch contains only `.md` edits, only `core+docs-only` loads — the new rule MUST stay in core, not rest.

**PR body convention to avoid self-block (canonical):**

When writing THIS PR's body, use prose style for descriptive references to AC-PM tokens:
- ❌ ` - **AC-PM1** Operator verifies the gate prompt is usable.` (list-shape, trips the gate)
- ✅ `Post-merge AC-PM1 is the operator's subjective verification that the gate prompt is usable; per §Sharp Edges, this is the "subjective decision requiring human judgment" carve-out.` (prose-style, gate ignores)

The same convention applies to the gate's documentation in `ship/SKILL.md`: every example snippet of an operator-step line MUST be inside a ` ```text ` fenced code block. The `awk` strip in the detection step covers this; the convention codifies it for future maintainers.

**Pre-existing budget breach attribution (informational, not load-bearing for this PR):**

The B_ALWAYS overrun is driven primarily by L15 (1372 B for `hr-tagged-build-workflow-needs-initial-tag-push`, added in PR-F #3940 sequence) and L55 (1040 B for `wg-end-of-work-emit-resume-prompt`, convention codification). Both were added with long inline `**Why:**` clauses that should have been off-loaded to learning files per `cq-agents-md-why-single-line`. The trim recommended in §Phase 3.2.a is the canonical remediation pattern.

**References:**

- `cq-agents-md-why-single-line` — 600 B per-rule body cap; mandates `**Why:**` clauses link to learning files rather than inlining
- `cq-agents-md-tier-gate` — sidecar placement gate; loader-class fit verification rule
- `hr-multi-step-post-merge-bootstrap-script` — pattern for collapsing N post-merge steps into 1 (the spirit-of-rule for the Phase 3.2.a fold-in)
- `scripts/lint-agents-rule-budget.py` — the canonical budget enforcer; lefthook gate
- `scripts/retired-rule-ids.txt` — the rule-retirement registry; required for the Phase 3.2.a retirement path
- `.claude/hooks/session-rules-loader.sh:88-126` — the loader-class regex + class-selection branch (single source of truth for loader-class fit)
- `.claude/hooks/lib/incidents.sh` — `emit_incident` helper (rule-application telemetry)
- Learning: `2026-05-12-agents-md-trim-loader-class-fit-verification.md` — the PR #3681 precedent for loader-class-fit reasoning during demotion proposals

## Out of Scope (deferred)

- **Option β (GitHub Action gate).** Explicitly deferred per the issue body. If the skill-side gate has a non-zero bypass rate post-launch, file a follow-up to add the Action as belt-and-suspenders. No tracking issue at plan time — the deferral is conditional on signal that doesn't exist yet.
- **Auto-filing the deferred-automation issue from the skill.** v1 prompts the operator for title/body/criterion. v2 could template-generate. Tracked as a v2 follow-on (no issue filed at plan time — this is a UX polish, not a workflow gap).
- **Historical sweep of past PRs for un-tracked operator steps.** The new gate prevents future accretion; cleanup of the historical backlog is its own optional issue if worth it. No tracking issue at plan time per the issue body's "out of scope" line.
- **Per-PR linter that rejects the lefthook bypass.** Out of scope; the bypass path (`--no-verify`) is rare enough that the post-fact `code-review` issue suffices.

## Refs

- Closes #4117 (this issue).
- `hr-never-label-any-step-as-manual-without` (the load-bearing hard rule).
- #4114 (terraform apply automation), #4115 (App Manifest flow) — the two deferred-automation issues that should have been filed during PR-H plan review.
- PR-H #3244 / PR #4066 — the trigger case.
- `wg-after-marking-a-pr-ready-run-gh-pr-merge` — the PR-ready-boundary gate precedent.
- `wg-end-of-work-emit-resume-prompt` — the skill-side reminder-gate precedent.
- `cq-agents-md-why-single-line`, `cq-agents-md-tier-gate` — the AGENTS rule body discipline rules this PR must honor.
- `scripts/lint-agents-rule-budget.py` — the canonical gate that will reject this PR's commit if Phase 3 isn't executed.

## Plan deviation log (filled at /work time)

(blank at plan-write time; the work agent appends here as Phase 3 decisions are made and any plan-time prescription proves wrong against live state)
