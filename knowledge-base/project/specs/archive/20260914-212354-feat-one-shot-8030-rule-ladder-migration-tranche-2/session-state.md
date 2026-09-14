# Session State

## Plan Phase

- Plan file: `knowledge-base/project/plans/2026-09-14-chore-rule-ladder-rescope-migration-tranche-2-plan.md`
- Status: recovered from partial-artifact — the plan+deepen subagent was terminated by an account-level
  weekly Opus rate limit (HTTP 429, resets 2026-09-16 20:00 Europe/Paris) mid-way through the deepen
  rewrite of Deliverable C + the Guard Contract. The plan body was already on disk and carries
  `## Acceptance Criteria`, so the one-shot partial-artifact predicate selects "continue", not "re-plan".
  The agent was resumed via SendMessage to finish the in-flight edit and emit its Session Summary.
- Draft PR: #8175. Target: `closes: 8030` (single issue).

### Errors

- Plan+deepen subagent terminated early: `rate_limit` / HTTP 429, weekly limit, model `claude-opus-5`.
  Recovery: partial-artifact check per one-shot's recovery block → plan complete → resumed the same
  agent rather than re-spawning (a re-spawn would re-pay the whole research fan-out).
  **Prevention:** on a 429 from a subagent, check the on-disk artifact against the skill's own
  completion predicate BEFORE re-invoking — `plan` persists its body and `## Research Insights`
  before the expensive tail, so a crash is usually recoverable rather than a redo.
- Constraint carried forward: if the Opus weekly limit is still in force at Step 4, the review panel
  cannot spawn. `/review` Gate 2a then applies — declare the degraded coverage in the first line of
  the summary and pass `--agents-ran 0 --agents-expected <N> --mode inline-fallback` to the trailer.
  Preferred alternative: re-spawn the seats with a non-Opus `model` override rather than accept
  inline-fallback on a corpus-governance diff.

### Decisions

- Collision re-probe after planning (one-shot Step 0a.5's "target the PLAN discovers" clause): plan
  targets only #8030, which the pre-worktree gate already cleared. The body-probe hit #8029 intersects
  on `knowledge-base/project/rule-metrics.json`, but #8029 is the predecessor that FILED #8030 and
  shipped only the instrument repair (`closingIssuesReferences: []`); #8030 is the residual it names.
  Verified as a citation, not a collision.
- Scope check on the planning subagent: `git status --porcelain` shows only the plan file modified —
  no edits to `AGENTS.rules.md`, `scripts/`, or `plugins/`. The plan-only mandate held.

### Recovery of the two rate-limited agents

- **Plan+deepen agent** — resumed via SendMessage; confirmed its in-flight Deliverable C / Guard Contract
  edit had already landed, fixed a fixture-id placeholder, re-measured A11 as 574 B — WRONG: at /work the line is byte-identical to the plan's replacement and measures 596 B (the architecture reviewer was right); budget is 43343 → 42640 (−703), not 42618 (−725) — committed
  and pushed (`c78288928`). Session Summary received.
- **`kieran-rails-reviewer`** — spawned by the planning agent and killed by the same limit before
  returning; its id was not reachable from this session, so its one concrete deliverable (the
  literal-verbatim sweep over the A1–A12 anchor cells) was run by the lead instead: **12/12 present**.
  A1 is a two-anchor cell (each present once); A8 is verbatim but hard-wraps across runbook lines
  121→122. Recorded as tasks.md 1.4. One defect found by the same pass: a blank line between rows A9
  and A10 split the anchor table so A10–A12 would not render — fixed.

### Architecture review findings — FOLDED into the plan (2026-09-14)

Every checkable claim was re-verified by the lead before folding (aggregator reads
`migrated-rule-ids.txt` 0×; CODEOWNERS omits the three registry/lint files; `lint-rule-bodies.py`
`SIDECARS = ("AGENTS.rules.md",)`; `skill-creator`/`heal-skill` 0 domain-assessment mentions;
`COVERED_DIRS` includes `scripts/`, `MIN_FIRING_SUITES=38`). Dispositions: #1 → Deliverable C body-hash
field + matrix 15/15b/15c + CODEOWNERS + AC18 + task 2.3b; #2 → verdict kept CHECK with the
skill-creator/heal-skill pointer mitigation + AC20 + task 3.5b; #3 → ack wording + step 10 (c2) + AC21 +
task 3.8b; #4 → `MIN_FIRING_SUITES` 38→39 + AC19 + task 2.5; #5 → already applied by the planning agent;
#6 → A10 gains the dedicated-reviewed-PR clause; #7 → already applied (non-`plugins/soleur/` paths are a
finding); #8 → recorded as an advisory risk for ship Phase 5.5's ADR gate.

Original findings as returned:

1. **P1 — the registry-as-pointer model exits AP-017's body-weakening gate for migrated `hr-*`/`wg-*`
   bodies.** `scripts/lint-rule-bodies.py` hashes bodies only in `AGENTS.rules.md`; CODEOWNERS pins
   that file plus the hash/ack files, but not `scripts/migrated-rule-ids.txt`,
   `scripts/retired-rule-ids.txt`, `scripts/lint-rule-ids.py`, or the home files. After migration a
   body at its skill-local home can be weakened with no ack, and Guard 1 only asserts the `[id: …]`
   marker is present inside the section — a rewritten body passes. Tranche 1 set this precedent for
   `wg-*`; this tranche is the first to move `hr-*` through it. Proposed fix: add a 5th registry
   column carrying the sha256 of the whitespace-normalised body, emitted by the guard's own
   `--print-hash <id>` mode and verified per row (both existing readers parse only `^id\s*\|`, so the
   grammar is unaffected — re-run the parity case); add a mutation row "edit one word of a migrated
   body → RED"; pin `/scripts/migrated-rule-ids.txt` and `/scripts/lint-migrated-rule-ids.sh` in
   CODEOWNERS beside the ADR-092 block.
2. **P2 — contested verdict:** `hr-new-skills-agents-or-user-facing` was graded CHECK; the agent argues
   KEEP under the plan's own criterion (an independent path exists — `skill-creator` and `heal-skill`
   mention neither domain assessment nor the CPO, so a session creating a skill directly is nudged only
   by the always-loaded line). Either keep it, or migrate with a mitigation recorded in the verdict row
   (one-line pointers from both skills to the new home). The sibling verdict on
   `hr-before-shipping-ship-phase-5-5-runs` is agreed.
3. **P2 — false consumer claim in the `scripts/migrated-rule-ids.txt` header.**
   `scripts/rule-metrics-aggregate.sh` never reads the migrated registry; the orphan exemption comes
   from the paired `retired-rule-ids.txt` row, and migrated ids are absent from `$enriched`, so their
   `SOLEUR_RULE_APPLIED` events are hook-accepted and then reported in no field. Rewrite the header's
   consumer list and soften the ack/registry wording.
4. **P2 — the new suite lands inside `scripts/guard-vacuity-floor.test.sh`'s COVERED scope**
   (`^(scripts/|plugins/soleur/test/)`). Write the `CASES` floor in AP-023 shape (direct
   `printf` + `exit 1`, never through `fail`), add `bash scripts/guard-vacuity-floor.test.sh` exit 0 to
   AC13, and ratchet `MIN_FIRING_SUITES` 38 → 39 in the same commit.
5. **P2 — fixture-root convention.** Siblings use env vars, not a `--root` flag
   (`LINT_AGENTS_SYNC_ROOT`, `RULE_METRICS_ROOT`, `INCIDENTS_REPO_ROOT`). Use
   `ROOT="${LINT_MIGRATED_RULE_IDS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"` — the `$SCRIPT_DIR/..`
   default also sidesteps the `GIT_DIR`-under-lefthook class (#7833). `--min-rows` may stay a flag.
6. **P2 — A10 turns compound's Route-Learning step into an inline seven-file migration procedure**,
   including authoring a CODEOWNERS WORM ack, on a path that runs at every ship. Reword to: file it (or
   add to the plan) and walk the checklist in the `scripts/migrated-rule-ids.txt` header **in a
   dedicated reviewed PR — never as a side edit of a compound run**. Same pointer for A11.
7. **P2 — Guard 1's reverse scan is `plugins/`-only while rows admit any path.** Either RED on any row
   whose path is not under `plugins/`, or derive the reverse-scan roots from the union of `dirname` of
   every row path.
8. **P2 (advisory) — no ADR records the third corpus state** ("active but not in the corpus"). Tranche 1
   introduced it; this tranche extends it to `hr-*` and adds a guard, so ADR-092/AP-017's scope is now
   implicitly narrower than its text. Consider an ADR or an ADR-092 amendment. Not a blocker.

Positive notes from the same review: after A11, `cq-agents-md-tier-gate` names the registry from the
always-loaded corpus, so the "registry is the pointer" claim holds only because of that edit — keep A11
in scope. The eval-harness gate on `brainstorm-domain-config.md` is block-scoped to the
`lane-inference` markers, so inserting a new H2 above `## Lane Inference` is a no-op for it.

### Components Invoked

- `soleur:one-shot` (Steps 0a, 0a.5, 0b, 0c, 1-2)
- `soleur:plan`, `soleur:deepen-plan` (in the plan+deepen subagent)
- `soleur:engineering:review:architecture-strategist` (plan-review seat)

## Review Phase (2026-09-14)

Nine seats on Sonnet (the Opus weekly limit was still in force), all report-only: code-simplicity and
architecture (design pass), then git-history, pattern-recognition, security, data-integrity,
agent-native, code-quality, test-design, and a structural-enumeration seat in place of performance-oracle.

- **Structural-cause roll-up:** security P1-1 (edit + re-hash in one commit stays green), security P2-1
  (verbatim-at-migration unverified) and structural §3/§5 (drop a row, swap in a fabricated id) are one
  gap — the registry certified itself with no external anchor. Fixed by `rule-body-lint --check`
  diffing the registry against the merge-base (`ee83a0b53`) plus identity against retired-rule-ids.txt
  (`bd6645657`). The structural seat mapped the instances but not the shared anchor.
- **Fixed inline:** the anchor above; uniqueness (row / banner / `[id:]` tag), repo-wide banner scan,
  NBSP refusal, reverse-scan line numbers (`bd6645657`); test survivors — verdict-helper self-test,
  intermediate symlink, `--print-hash`, env inheritance (`bd6645657`); merge conflict on
  `MIN_FIRING_SUITES` resolved to 40, not 39 (`f9bb01b97`); actionable skill-creator/heal-skill pointers;
  rule-prune.sh PR body no longer frames zero events as retirement evidence (pinned by tp5b); plan P3s.
- **No change, with rationale:** agent-native "merge-pr/drain-prs/fix-issue lose visibility" — the body
  only DESCRIBES ship Phase 5.5, so nothing an agent outside ship could act on was removed; "direct file
  write creates a skill" — the rule constrains an assessment's composition, and a session running none
  violates nothing; security P1-2 (no ruleset requires human review) — pre-existing, and code-owner
  review on a single-owner repo would block the owner's own merges; the machine gate plus the
  mandatory-human-review annotation is the ADR-092-consistent control; rule-metrics.json at 100 rules —
  a cron snapshot.
- **Residual documented:** text adjacent to a callout but outside its blockquote (guard header).

### Errors

- My pre-panel `git merge-tree` returned clean; #8149 merged to main during the review and produced a
  real conflict the code-quality seat found. **Prevention:** re-run the merge-tree probe immediately
  before applying review fixes, not only before spawning the panel.
- Mutation M2 survived the first battery: case 17b's needle `occurs 2 times` also matched the
  tag-count finding. **Prevention:** a RED needle must name the check (its unique message prefix), never
  a phrase two checks share.
