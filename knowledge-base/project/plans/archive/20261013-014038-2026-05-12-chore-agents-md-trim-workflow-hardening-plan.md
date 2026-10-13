---
type: chore
issue: 3682
parent_pr: 3681
lane: procedural
requires_cpo_signoff: false
---

# AGENTS.md trim workflow hardening — three independent skill/rule edits

**Issue:** #3682
**Source:** PR #3681 review surfaced 3 workflow gaps; none recurring, all preventable.

## Enhancement Summary

**Deepened on:** 2026-05-12
**Sections enhanced:** 4 (Acceptance Criteria, Phase 1, Phase 2, Phase 3)
**Research applied:** rule-ID verification (5/5 cited IDs active, 0 retired), byte-budget headroom check, work skill precedent grep (canonical `git rev-list "origin/${BRANCH}..HEAD" --count` form vs. plan v1's `git log | wc -l`), session-rules-loader regex re-verification, compound step 8 sub-bullet placement.

### Key Improvements

1. **Edit 1 entry-guard form switched** from `git log | wc -l` to the canonical `git rev-list "origin/${BRANCH}..HEAD" --count` (precedent: `plugins/soleur/skills/ship/SKILL.md:619`). The `wc -l` form is portable but bash-dependent; `--count` returns a clean integer that `set -euo pipefail` can compare without a `tr -d` strip.
2. **Edit 3a byte budget — superseded post-review.** Original plan: insert "preserving per-issue mechanism labels..." into the rule body and trim redundant prose to fit the 600 B cap. Post-review (pattern-recognition + code-quality flagged duplication with the `[skill-enforced: compound step 8]` tag): the clause was DEDUPLICATED out of the rule body and into the `[skill-enforced: compound step 8 (Why-line trim semantics + loader-class-fit)]` tag suffix. Final byte length: 578 B (was 572 pre-edit; cap 600). Single source of truth for the trim semantics now lives in `compound/SKILL.md` step 8 (Edit 3b).
3. **Loader-class-fit grep target pinned to lines 88-115.** The classification regex block in `session-rules-loader.sh` (`DOCS_RE`/`CODE_RE`/`INFRA_RE` + class-selection branch) is the canonical source. Edit 2 instructs the planner to grep this exact line range, not paraphrase the regex.
4. **All cited rule IDs verified active.** `wg-plan-prescribed-skills-must-run-inline`, `wg-every-session-error-must-produce-either`, `cq-agents-md-why-single-line`, `cq-agents-md-tier-gate`, `hr-weigh-every-decision-against-target-user-impact` — all present in AGENTS.md, none in `scripts/retired-rule-ids.txt`.
5. **PR #3681 confirmed OPEN at deepen time.** The source learning `2026-05-12-agents-md-trim-loader-class-fit-verification.md` does NOT exist on `main` — it lands with #3681. This plan must therefore not gate on its existence; reference it by future path only and let compound at Phase 4 reconcile.

### New Considerations Discovered

- **Sequencing risk with PR #3681:** if #3682 merges before #3681, the source learning's path will not exist. Mitigation: use `[ref to land in #3681]` rather than asserting existence.
- **`wg-*` demotion CPO sign-off carry-forward.** PR #3496 condition 3 limits demotion to `wg-*`; this plan's Edit 2 enforces the loader-class-fit check ON TOP of that limit (the limit says "only `wg-*` may move"; Edit 2 says "even among `wg-*`, only those whose trigger surface fits the rest sidecar's load classes"). Both gates fire — Edit 2 is additive, not a replacement.
- **Edit 1 dual-mode safety.** Phase 4 has TWO invocation modes (one-shot orchestrator, direct invocation). Both end at `## Work Phase Complete`. The entry-guard runs BEFORE the mode branch, so it covers both paths.

## Overview

Three independent edits across three skills/rule bodies, each closing a defect class
that PR #3681 surfaced but did not fully prevent re-occurrence:

1. **`plugins/soleur/skills/work/SKILL.md` Phase 4 entry-guard.** Assert at least one
   commit beyond `origin/<branch>` exists before emitting `## Work Phase Complete`.
   Otherwise downstream review agents analyze an empty `git diff origin/main...HEAD`
   and the handoff produces no signal.
2. **`plugins/soleur/skills/plan/SKILL.md` + `deepen-plan/SKILL.md` loader-class-fit
   verification.** When a plan proposes a `wg-*` core→rest demotion, grep
   `.claude/hooks/session-rules-loader.sh` (lines 88-115 — the `DOCS_RE`/`CODE_RE`/
   `INFRA_RE` regex block + class-selection branch) and assert: "Can the situation
   that triggers this rule occur during a session that the loader classifies as
   `docs-only`?" If yes → keep in core (body-trim if budget requires).
3. **`cq-agents-md-why-single-line` rule body + `compound/SKILL.md` step 8 guidance.**
   Why-line trims must preserve per-issue mechanism labels (the words AFTER each
   `#N`); trim redundant prose only.

The three edits are **independent in mechanism but bundled by topic** (workflow
hardening for AGENTS.md trim plans). Each could ship as its own PR, but the
issue framing (#3682) explicitly bundles them as a single follow-up surface.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| Source learning at `knowledge-base/project/learnings/2026-05-12-agents-md-trim-loader-class-fit-verification.md` | File does not exist on `main` (PR #3681 still OPEN at plan + deepen time, verified `gh pr view 3681 --json state` → `OPEN`). | Reference learning by future path only. Do NOT gate on its existence. Compound at Phase 4 will write the canonical version of the learning if PR #3681 merges first; otherwise this PR's compound writes it. |
| `.claude/hooks/session-rules-loader.sh` exists and classifies `docs-only` via file extension regex | Confirmed at lines 88-90: `DOCS_RE='\.(md|markdown|txt|njk|html)$\|^\.github/.*\.md$'`; `CODE_RE`/`INFRA_RE` separately at 89-90; class selection at 103-115: `docs-only` fires when `HAS_DOCS=1 && HAS_CODE=0 && HAS_INFRA=0`. | Edit 2 grep target pinned to lines 88-115. Verified loader IS the authoritative class table. |
| `wg-plan-prescribed-skills-must-run-inline` lives in core | Confirmed `AGENTS.core.md:54`. | Edit 2 protects its core placement and any future similar `wg-*` whose trigger surface intersects docs-only sessions. |
| `cq-agents-md-why-single-line` body lives in `AGENTS.docs.md` | Confirmed `AGENTS.docs.md:6`; current byte length 572 B (cap 600). | Edit 3a modifies `AGENTS.docs.md` with a +28 B addition that fits the headroom. |
| Compound step 8 emits the `[CRITICAL]` warning at >22k bytes | Confirmed `compound/SKILL.md:227`. | Edit 3b augments the same step with the Why-line semantic-label preservation hint. |
| All cited rule IDs are active | Verified: `wg-plan-prescribed-skills-must-run-inline`, `wg-every-session-error-must-produce-either`, `cq-agents-md-why-single-line`, `cq-agents-md-tier-gate`, `hr-weigh-every-decision-against-target-user-impact` — all present in AGENTS.md, none in `scripts/retired-rule-ids.txt`. | No fabrication-class citations to fix. |

## User-Brand Impact

**If this lands broken, the user experiences:** A future AGENTS.md trim PR
silently demotes a `wg-*` rule that fires on docs-only sessions, dropping a
load-bearing workflow gate (e.g., `wg-plan-prescribed-skills-must-run-inline`)
on plan-only edits. The plan looks correct, the demote passes review, the rule
goes silent on docs-only sessions, and a future deferred-skill-invocation
incident recurs without any rule body to point at it.

**If this leaks, the user's data/workflow/money is exposed via:** Not applicable
— this is a workflow-hardening edit on internal skill/rule bodies. No
regulated-data surface, no auth/payments touched, no schema change.

**Brand-survival threshold:** none, reason: AGENTS.md/skill workflow hardening
— no regulated-data surface, no operator-facing payments/auth/data flows. None
of `apps/web-platform/{server,supabase,app/api,middleware}`, no
`apps/*/infra/`, no `**/doppler*`, no auth/byok/stripe path is touched.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **Edit 1 (work/SKILL.md Phase 4 entry-guard).** Before emitting
  `## Work Phase Complete`, the skill body prescribes (canonical form per
  `plugins/soleur/skills/ship/SKILL.md:619`):
  ```bash
  BRANCH=$(git branch --show-current)
  N=$(git rev-list "origin/${BRANCH}..HEAD" --count 2>/dev/null || echo 0)
  if [[ "$N" == "0" ]]; then
    echo "[work-phase-4-guard] no commits beyond origin/${BRANCH}; running incremental commit logic from Phase 2 step 3 first." >&2
    # invoke incremental commit (Phase 2 step 3) then re-check
    N=$(git rev-list "origin/${BRANCH}..HEAD" --count 2>/dev/null || echo 0)
    if [[ "$N" == "0" ]]; then
      echo "[work-phase-4-guard] empty diff vs origin/${BRANCH}; handing off to review with empty diff is a no-op — investigate before continuing." >&2
      exit 1  # HALT — do NOT emit "## Work Phase Complete"
    fi
  fi
  ```
  The guard runs BEFORE the Invocation Mode branch (one-shot vs. direct), so
  it covers both modes. The `exit 1` form ensures one-shot orchestrators see
  the failure rather than silently continuing.
- [ ] **Edit 2 (plan/SKILL.md + deepen-plan/SKILL.md loader-class-fit verify).**
  Each skill body adds a checklist item under their respective AGENTS.md-edit
  guidance section: "When a plan proposes any AGENTS.md core→rest demotion
  (`wg-*` only — `hr-*` may not be demoted per CPO sign-off PR #3496), verify
  loader-class fit by grepping `.claude/hooks/session-rules-loader.sh` lines
  88-115 (the `DOCS_RE`/`CODE_RE`/`INFRA_RE` regex block + class-selection
  branch). For each demotion candidate, classify its trigger surface (does it
  fire on plan/learning/spec edits, or only on code/infra?). If `docs-only`
  is in the trigger surface but the rest sidecar does NOT load on docs-only,
  KEEP in core (body-trim instead). Cite the grep output + class-table
  mapping in the plan body."
- [ ] **Edit 2 placement (plan/SKILL.md):** insert as a checklist item at
  the end of section 2 "Issue Planning & Structure" → "Content Planning"
  bulleted list (after the existing AGENTS.md-rule headroom check at
  `plugins/soleur/skills/plan/SKILL.md:716`). The headroom check is the
  natural anchor — both fire on AGENTS.md edits.
- [ ] **Edit 2 placement (deepen-plan/SKILL.md):** insert as a quality-check
  item at the end of section "Quality Checks" (after the existing rule-ID
  verification check at line 557). Same anchor logic — the rule-ID-verify
  check already covers AGENTS.md citations; loader-class-fit covers
  AGENTS.md placement.
- [ ] **Edit 3a (`cq-agents-md-why-single-line` body).** AGENTS.docs.md:6 rule
  body adds the clause "preserving per-issue mechanism labels (text after each
  `#N`)" inside the existing one-sentence cap. Verify with
  `awk '/cq-agents-md-why-single-line/ {print length($0)}' AGENTS.docs.md`
  → must return ≤600. (Pre-edit: 572. Insertion ≤80 B. Post-edit: ≤652. If
  over, trim the `<!-- rule-threshold: 115 -->` HTML comment OR the trailing
  `**Why:** #3493 sidecar split; #2865 bytes-first; #2686 prior.` to fit.)
- [ ] **Edit 3b (compound/SKILL.md step 8 guidance).** Add a one-line bullet
  AFTER the `[CRITICAL]` warning at compound/SKILL.md:227 and BEFORE the
  `[WARNING] longest rule` bullet: "When trimming Why-lines to fit the
  budget, preserve per-issue mechanism labels (text after each `#N`); strip
  redundant prose only. Correct: `#2618 per-command-ack; #2880 non-interactive
  exec.` Over-trimmed: `#2618; #2880.` (loses the per-issue mechanism
  distinction)."
- [ ] **Lint/test passes:** `python3 scripts/lint-rule-ids.py` exit 0;
  `bash scripts/lint-agents-compound-sync.sh` exit 0;
  `python3 scripts/lint-agents-enforcement-tags.py` exit 0;
  `bash .claude/hooks/session-rules-loader.test.sh` (14/14).
- [ ] **AGENTS.md byte budget unchanged or improved.** `wc -c AGENTS.md AGENTS.core.md`
  must remain ≤22000 (critical threshold). Edit 3a adds ≤80 bytes to AGENTS.docs.md
  (NOT always-loaded — the +80 B does not count against the 22k always-loaded
  cap). Other edits touch skill bodies only.
- [ ] **PR body uses `Closes #3682`** (not `Ref` — this PR fully closes the issue).
- [ ] **Loader-class-fit verification dry-run.** During implementation, dry-run
  the new Edit 2 checklist item against PR #3681's plan
  (`knowledge-base/project/plans/2026-05-12-chore-agents-payload-over-22k-trim-plan.md`,
  if it lands by then) and confirm the demotion of
  `wg-plan-prescribed-skills-must-run-inline` would be flagged.

### Post-merge (operator)

- [ ] None. All three edits are skill/rule body changes; no infra apply, no
  external service config, no DB migration.

## Implementation Phases

### Phase 1 — Edit 1 (work/SKILL.md Phase 4 entry-guard)

**Files to Edit:**

- `plugins/soleur/skills/work/SKILL.md` — modify §Phase 4 / Invocation Mode
  section (around lines 494-520) to insert an entry-guard block BEFORE the
  `#### Invocation Mode` subsection. Reuses Phase 2 step 3 incremental commit
  logic (lines ~290-345).

**Approach:**

1. Add a `#### Phase 4 Entry-Guard` subsection AFTER `#### Playwright-First Audit`
   (currently ends at line ~508) and BEFORE `#### Invocation Mode` (currently
   line ~510). The guard runs before the mode branch so both paths (one-shot
   and direct) get the same protection.
2. Specify the canonical `git rev-list "origin/${BRANCH}..HEAD" --count` check
   (NOT `git log | wc -l` — `wc -l` requires a `tr -d` strip and bash-portable
   integer comparison; `--count` returns a clean integer ready for `[[ "$N" == "0" ]]`).
3. Branch on `N==0`: invoke Phase 2 step 3's stage+commit flow (`git add` files
   per logical unit, `git commit -m "<conventional message>"`). Re-check.
4. On second `N==0`: emit explicit `[work-phase-4-guard] empty diff` warning,
   then `exit 1` (HALT). Do NOT emit `## Work Phase Complete`. The hard-fail
   ensures one-shot orchestrators see the failure as a non-zero exit and stop
   the pipeline rather than silently continuing into review.

### Research Insights (Phase 1)

**Best Practices (verified live):**

- The canonical form `git rev-list "origin/${BRANCH}..HEAD" --count` lives at
  `plugins/soleur/skills/ship/SKILL.md:619` and at the PreToolUse hook
  `.claude/hooks/ship-unpushed-commits-gate.sh`. Reuse the same form here for
  consistency — operators reading work/SKILL.md should not see a different
  shape than ship/SKILL.md for the same primitive.
- `git rev-list ... --count` returns `0` when the upstream is missing
  (e.g., a brand-new branch never pushed). The `2>/dev/null || echo 0`
  fallback covers that edge.
- `set -euo pipefail` interaction: `--count` returns clean integer; `wc -l`
  returns whitespace-padded; comparing `$N` to `"0"` requires the clean form.

**Edge Cases:**

- **First-push branch.** When the branch has never been pushed, `origin/${BRANCH}`
  doesn't exist; `git rev-list` errors. The `|| echo 0` returns 0, which then
  triggers the guard's HALT. This is correct behavior — a never-pushed branch
  with zero commits beyond origin's nonexistent ref means "nothing to review."
  But: if the branch HAS commits but was never pushed, the operator should
  push first (the Phase 2 incremental-commit path handles this).
- **Bare-repo / worktree edge.** The host worktree convention places the
  branch HEAD in the worktree's `.git` link; `git rev-list` resolves correctly
  via the worktree's git dir. No special-case needed.
- **One-shot pipeline mode.** `exit 1` from inside the work skill must
  propagate back to the one-shot orchestrator. The orchestrator already
  treats non-zero exits as halt signals (per the existing one-shot SKILL.md
  contract — see e25aa7fe and prior).

### Phase 2 — Edit 2 (plan + deepen-plan loader-class-fit verify)

**Files to Edit:**

- `plugins/soleur/skills/plan/SKILL.md` — section 2 "Issue Planning &
  Structure" → "Content Planning" checklist (anchor at line 716, the
  AGENTS.md-rule headroom check). Insert AFTER that bullet.
- `plugins/soleur/skills/deepen-plan/SKILL.md` — "Quality Checks" section
  (anchor at line 557, the rule-ID verification check). Insert AFTER that
  bullet.

**Approach:**

1. Both skills add the same checklist item (avoid drift via cross-reference):

   > **Loader-class-fit verification (AGENTS.md core→rest demotion).** When a
   > plan proposes any AGENTS.md `core→rest` demotion (`wg-*` only — `hr-*`
   > may not be demoted per CPO sign-off PR #3496 condition 3), verify
   > loader-class fit:
   > `sed -n '88,115p' .claude/hooks/session-rules-loader.sh` to read the
   > `DOCS_RE`/`CODE_RE`/`INFRA_RE` regex block AND the class-selection
   > branch (`docs-only` fires when `HAS_DOCS=1 && HAS_CODE=0 && HAS_INFRA=0`;
   > `code` or `infra` triggers `core+rest` load). For each demotion
   > candidate, classify its trigger surface: does it fire on plan/learning/
   > spec edits (docs-only), or only on code/infra? If `docs-only` is in
   > the trigger surface but the rest sidecar does NOT load on docs-only,
   > KEEP in core (body-trim instead). Cite the `sed` output + the
   > class-fit determination in the plan body.

2. Add a Sharp Edges entry to plan/SKILL.md "Sharp Edges" section:
   > When a plan proposes AGENTS.core.md → AGENTS.rest.md demotion, the
   > loader's class table (`.claude/hooks/session-rules-loader.sh:104-115`)
   > determines whether the demoted rule is reachable from the same session
   > class that originally triggered it. Demoting a rule whose trigger fires
   > on `docs-only` sessions silently drops it on plan-only / learning-only /
   > knowledge-base PRs. **Why:** PR #3681 — `wg-plan-prescribed-skills-must-run-inline`
   > demoted core→rest before pattern-recognition reviewer caught the gap;
   > `/work` runs on docs-only PRs and `AGENTS.rest.md` does not load there.

**Why deepen-plan AND plan:** Plan owns the initial draft; deepen-plan owns
the multi-agent review pass. Either can be the entry point for an AGENTS.md
trim plan. Both must enforce the gate so the check fires whether the operator
runs `/soleur:plan` only or `/soleur:plan` followed by `/soleur:deepen-plan`.

### Research Insights (Phase 2)

**Best Practices (verified live):**

- The loader regex block (lines 88-90) is the single source of truth for
  `docs-only`/`code`/`infra` classification. Paraphrasing it in the plan/
  deepen-plan body would create a drift surface — when the loader's regex
  changes (e.g., adding `.yaml` to `DOCS_RE`), the planner's mental model
  silently goes stale. Pinning the grep to `sed -n '88,115p' <loader>` keeps
  the planner reading the canonical source every time.
- The class-selection branch at lines 104-115 includes a critical fallback:
  `multi-class / empty / explicit override → load everything (fail-closed)`.
  A docs-only-classified session that touches a `.sh` AND a `.md` becomes
  multi-class and loads `core+docs-only+rest` — but a pure `.md`-only
  session does NOT load `rest`. This is the failure mode #3681 caught.

**Anti-patterns to avoid:**

- Do NOT paraphrase the loader regex into the plan/deepen-plan body. The
  regex MUST be re-read at gate-fire time.
- Do NOT skip the gate "because the rule is small." Body size is unrelated
  to load-bearing class-fit.

### Phase 3 — Edit 3 (Why-line semantic-label preservation)

**Files to Edit:**

- `AGENTS.docs.md` (line 6, `cq-agents-md-why-single-line` rule body).
- `plugins/soleur/skills/compound/SKILL.md` (line ~227, step 8 `[CRITICAL]`
  warning block).

**Approach:**

1. **AGENTS.docs.md:6 rule body augmentation (final form post-review).** Modify the rule's `[skill-enforced:]` tag from:
   > [skill-enforced: compound step 8]
   to:
   > [skill-enforced: compound step 8 (Why-line trim semantics + loader-class-fit)]

   AND drop the redundant `Rule count advisory.` sentence (-22 B; covered by `<!-- rule-threshold: 115 -->` HTML comment + `[ADVISORY] rule count` warning in compound step 8) AND the second `(compound step 8)` parenthetical inside the `Targets:` clause (-18 B; the `[skill-enforced:]` tag already cites compound step 8 once at the top of the rule). Net delta: +6 B (538 → 578). Cap 600. Headroom: 22 B post-edit.

   **Original draft (superseded):** insert "preserving per-issue mechanism labels (text after each `#N`)" into the rule body itself (+60 B), then offset with the same trims above. Pattern-recognition + code-quality reviewers flagged duplication with the `[skill-enforced: compound step 8]` tag (the rule body was restating what the tag pointed at). Final form moves the semantic clue into the tag suffix and lets compound step 8 own the trim-semantics directive verbatim.

   Verify post-edit with `awk '/cq-agents-md-why-single-line/ {print length($0)}' AGENTS.docs.md` ≤ 600.

2. **compound/SKILL.md step 8 augmentation.** After the `[CRITICAL]` warning
   block at line 227 and before the `[WARNING] longest rule` bullet at line 228,
   add a sub-bullet:
   > **Why-line trim semantics:** preserve per-issue mechanism labels (text
   > after each `#N`); strip redundant prose only. Correct: `#2618 per-command-ack;
   > #2880 non-interactive exec.` Over-trimmed: `#2618; #2880.` (loses the
   > per-issue mechanism distinction that downstream readers use to map a rule
   > to its triggering incident class).

### Research Insights (Phase 3)

**Best Practices (verified live):**

- The `**Why:**` field is the rule's semantic-provenance trail. `#N` alone is
  a number; `#N <mechanism-label>` is a typed pointer that lets a future
  operator map a rule to its triggering incident class without opening every
  PR. Stripping the mechanism strips the type.
- The rule body cap (~600 B) is a BYTES policy, not a SEMANTIC policy. The
  trim policy must encode that distinction explicitly so future trims know
  which bytes are load-bearing (mechanism labels) and which are not
  (redundant prose, stale ancestor `#N` references like #2686).
- Compound step 8's `[CRITICAL]` block is the natural anchor for this hint
  because it fires when the operator is ACTIVELY trimming. Adding the hint
  to AGENTS.docs.md alone (without compound) would mean the trim-time
  guidance lives in a sidecar that's only loaded on docs-only sessions —
  which IS the trim session class, but the redundancy of having it in BOTH
  places is intentional: the rule body documents the policy; compound step 8
  shows it at trim-time.

**Edge Cases:**

- **What if a `**Why:**` field has no `#N` references?** Some rules cite
  learning files directly (`**Why:** see knowledge-base/project/learnings/...`).
  The mechanism-label rule applies only to PR/issue numbered references.
  Phrase the directive as "where present" (the proposed clause "preserving
  per-issue mechanism labels (text after each `#N`)" already implies this —
  no `#N`, no obligation).
- **What about `(retired)` markers?** Some `**Why:**` fields cite retired
  rule IDs as historical context (e.g., `**Why:** supersedes cq-foo-bar (retired 2026-04-23).`).
  These are NOT per-issue mechanism labels and need not be preserved on
  trim — the retired-rule registry is the canonical retirement source.

## Test Strategy

- **No new unit tests** — all three edits are skill/rule body changes;
  test coverage is via the existing AGENTS.md linters and the loader test suite.
- **Existing test coverage:**
  - `python3 scripts/lint-rule-ids.py` — verifies rule-ID immutability (no
    rule deletions, no retired-ID resurrections).
  - `bash scripts/lint-agents-compound-sync.sh` — verifies AGENTS.md ↔ compound
    SKILL.md anchor parity.
  - `python3 scripts/lint-agents-enforcement-tags.py` — verifies
    `[skill-enforced:]` / `[hook-enforced:]` tags resolve.
  - `bash .claude/hooks/session-rules-loader.test.sh` (14 tests) — verifies
    loader classification + sidecar load.
- **Manual verification:**
  - **Edit 1:** simulate empty-diff state in a throwaway worktree
    (`git reset --hard origin/<branch>` then re-enter the work skill at
    Phase 4 mentally) and confirm the guard would HALT rather than emit
    the marker. Do NOT do this on the actual feature branch.
  - **Edit 2:** dry-run the new checklist item against PR #3681's plan
    (when it lands or against its current draft) and confirm the demotion
    of `wg-plan-prescribed-skills-must-run-inline` would be flagged BEFORE
    merge — the gate is correct iff it would have caught #3681's miss.
  - **Edit 3a:** run `awk '/cq-agents-md-why-single-line/ {print length($0)}' AGENTS.docs.md`
    pre- and post-edit; confirm ≤600 B.
  - **Edit 3b:** spot-check `bash scripts/lint-agents-compound-sync.sh`
    still passes (the new sub-bullet is inside step 8, not a new step).

## Open Code-Review Overlap

Files this plan touches:
- `plugins/soleur/skills/work/SKILL.md`
- `plugins/soleur/skills/plan/SKILL.md`
- `plugins/soleur/skills/deepen-plan/SKILL.md`
- `plugins/soleur/skills/compound/SKILL.md`
- `AGENTS.docs.md`

Query (verified at plan time, MUST be re-run at /work time — corpus may shift):

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for f in plugins/soleur/skills/work/SKILL.md plugins/soleur/skills/plan/SKILL.md plugins/soleur/skills/deepen-plan/SKILL.md plugins/soleur/skills/compound/SKILL.md AGENTS.docs.md; do
  jq -r --arg path "$f" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

Disposition: **None known at plan time.** /work MUST re-run and either fold-in,
acknowledge, or defer per the plan-skill `## Open Code-Review Overlap`
contract.

## Domain Review

**Domains relevant:** none (workflow/tooling change — no product, no
compliance, no engineering-architecture surface beyond skill bodies).

No cross-domain implications detected — internal AGENTS.md/skill workflow
hardening. CTO/CPO/CLO sign-off not required (per brainstorm-domain-config
USER_BRAND_CRITICAL=false; threshold `none`).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- Edit 1 (work Phase 4 entry-guard) MUST use the canonical
  `git rev-list "origin/${BRANCH}..HEAD" --count` form, not
  `git log | wc -l`. The `wc -l` form is whitespace-padded and requires a
  `tr -d` strip; the canonical form returns a clean integer that
  `set -euo pipefail` can compare directly. Precedent:
  `plugins/soleur/skills/ship/SKILL.md:619`,
  `.claude/hooks/ship-unpushed-commits-gate.sh`.
- Edit 2 (loader-class-fit verify) MUST grep
  `.claude/hooks/session-rules-loader.sh` lines 88-115 ITSELF, not paraphrase
  the classification regex. The loader's regex is the canonical source of
  truth — paraphrasing creates a drift surface (when the loader's regex
  changes, the plan/deepen-plan body silently goes stale). Pin the grep with
  `sed -n '88,115p'` so the planner re-reads the canonical source each time.
- Edit 3a (Why-line semantic preservation) — verify
  `cq-agents-md-why-single-line` rule body stays ≤600 B AFTER the addition.
  Current body is at 572 B; the +60 B addition pushes it OVER cap by ~32 B.
  Mandatory trim of `Rule count advisory.` (-22 B) and tightening the
  trailing `**Why:**` (-30 B) restores headroom. If the trim sequence
  fails to fit, fall back to the `<!-- rule-threshold: 115 -->` HTML comment
  removal (informational only).
- The 3 edits SHOULD land in a single PR per the issue framing (#3682) — but
  each commit MAY be separate (per-edit commit isolation makes review-comment
  threading clean). Use Phase 2 incremental commit policy.
- **PR #3681 sequencing.** If #3681 merges before #3682, the source learning
  `2026-05-12-agents-md-trim-loader-class-fit-verification.md` will exist on
  `main` and this plan's compound at Phase 4 should reference it rather than
  write a duplicate. If #3682 merges first, this plan's compound writes the
  canonical learning. Either order is fine; the compound at Phase 4 must
  check existence first (`ls knowledge-base/project/learnings/*loader-class-fit*`)
  before writing.

## Out of Scope (Explicitly Deferred)

- **Pre-commit hook for AGENTS.md rule-budget + skill-enforced anchor parity.**
  Tracked at #3684 (deferred per PR #3681 review F6).
- **Rule retirement via 8w telemetry.** Tracked at #3683 (post 2026-07-04).
- **Rewriting `cq-agents-md-tier-gate` placement gate semantics.** PR #3681
  is the validation case for the existing gate; rewriting it is a separate
  concern.
- **Changing the loader's classification regex.** The loader is the canonical
  source of truth — this plan adds a verification step that READS the loader,
  it does not modify it. If the docs-only/code/infra split is wrong (e.g.,
  `.yaml` should be docs-only), that's a separate plan against the loader.
- **Generalizing the entry-guard to other skill phases.** Edit 1 covers
  work/SKILL.md Phase 4 only. Other skills with similar handoff markers
  (review/SKILL.md, ship/SKILL.md) MAY benefit from the same guard, but each
  is a separate plan with its own anchor analysis.

## Files to Edit

- `plugins/soleur/skills/work/SKILL.md` — §Phase 4 entry-guard subsection,
  inserted between `#### Playwright-First Audit` (~line 508) and
  `#### Invocation Mode` (~line 510). (Edit 1)
- `plugins/soleur/skills/plan/SKILL.md` — §Issue Planning checklist
  (anchor: line 716 AGENTS.md-rule headroom bullet) + §Sharp Edges entry.
  (Edit 2)
- `plugins/soleur/skills/deepen-plan/SKILL.md` — §Quality Checks (anchor:
  line 557 rule-ID verification bullet). (Edit 2)
- `plugins/soleur/skills/compound/SKILL.md` — §step 8 [CRITICAL] block
  sub-bullet, inserted between line 227 ([CRITICAL] threshold) and line 228
  ([WARNING] longest rule). (Edit 3b)
- `AGENTS.docs.md` — `cq-agents-md-why-single-line` rule body (line 6) +
  trim of `Rule count advisory.` and tightening of trailing `**Why:**` to
  fit 600 B cap. (Edit 3a)

## Files to Create

- None.

## References

- **Issue:** #3682
- **Source PR:** #3681 (AGENTS.md trim 24,622 → 21,985 B) — verified OPEN at
  deepen time via `gh pr view 3681 --json state` → `OPEN`.
- **Source learning (lands with #3681):**
  `knowledge-base/project/learnings/2026-05-12-agents-md-trim-loader-class-fit-verification.md`
  — does NOT exist on `main` at deepen time; reference by future path only.
- **CPO sign-off basis:** PR #3496 condition 3 (`wg-*` only may be demoted
  core→rest, never `hr-*`).
- **Loader spec:** `knowledge-base/project/specs/feat-agents-md-change-class-loader/spec.md`
- **Loader implementation:** `.claude/hooks/session-rules-loader.sh` (lines
  88-115 = classification regex + class-selection branch).
- **Compound rule-budget step:** `plugins/soleur/skills/compound/SKILL.md:195-260`
  (step 8). Insertion point: between line 227 ([CRITICAL]) and line 228
  ([WARNING] longest rule).
- **AGENTS.docs.md `cq-agents-md-why-single-line` rule:** line 6, current
  byte length 572 (cap 600).
- **AGENTS.core.md `wg-plan-prescribed-skills-must-run-inline` rule (the
  protected case):** line 54.
- **Canonical entry-guard form precedent:**
  `plugins/soleur/skills/ship/SKILL.md:619`,
  `.claude/hooks/ship-unpushed-commits-gate.sh`.
- **Rule-ID verification corpus:** AGENTS.md (active),
  `scripts/retired-rule-ids.txt` (retired). All cited IDs verified active at
  deepen time.
