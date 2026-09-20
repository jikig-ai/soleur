# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-09-20-feat-kb-glossary-rejected-register-plan.md`
- Status: complete (plan → plan-review → deepen-plan, all gates pass; HEAD `dfe303c82` pushed)
- Scope verified by the parent: `git diff origin/main...HEAD --name-only` lists only `plans/`, `specs/<branch>/` and the hook-regenerated `knowledge-base/INDEX.md` — no product code touched during planning.

### Errors
None fatal. Six recoverable, each fixed and recorded as a numbered revision in the plan:

1. Two tool calls denied by hooks: `iac-plan-write-guard.sh` matched prose *describing the absence* of infrastructure patterns (the #7003 class), and a `bash` call was blocked for containing a secret-write literal. Both fixed by rewording — never via the `iac-routing-ack` opt-out, which would have asserted a reviewed infrastructure step that does not exist.
2. A standing-AC check was declared clean on ambient machine state but never tested against a sibling branch moving a shared constant. Nine ACs now pin absolute literals.
3. The first rule-pointer design was unreachable (see Decisions).
4. A liveness probe pointed the lint at the one path its glob excludes, so it would have stayed green with every entry check deleted.
5. Five stale references survived the revisions (the pre-relocation battery path ×3; the removed `requester` field's legal values ×2).
6. R28 — the naming decision was never propagated: `register` appeared 64× and "the store" 19× still naming the new artifact, including the `title:` frontmatter and Overview, while `tasks.md` already used the corrected names, so plan and task list disagreed. Caught by an independent pass, not by the author's own sweep (which grepped for dropped symbols rather than made decisions).

### Decisions
- **The rule pointer lands in the hook, and rung 5 alone was insufficient.** `cq-agents-md-tier-gate` routes an already-enforced rule's body into its enforcer, so the pointer became rung 5 of `pre-ask-technical-fork-gate.sh` — zero `B_ALWAYS` bytes, no WORM ack. But the classifier evaluates `AUTHORITY_RE` first and wins outright, matching `cost|budget|price|scope|schedule`; an accountant question carries one, so the hook would allow and rung 5 would never fire. A dedicated `EXTERNAL_EXPERT_RE` arm now precedes that short-circuit, and AC11 became a behavioural deny assertion.
- **Four briefed premises were stale.** Bundle 1 shipped `operator-rephrase`, not `operator-explain` — and its `## Vocabulary` already reserves the slot naming #8289, making the rewrite mandatory. ADR-231 is claimed on a sibling ref, so this bundle's ordinal is **232**. `triage/SKILL.md` triages local `todos/`. The Tier-1 audit entry never landed.
- **Zero external filers reframed G2.** Three authors across a 300-issue sample, all internal; `wontfix` never used in 3,182 closures. v1 is an internal dedup index and is **advisory-only** — severing a verified path where a false entry became a permanently-closed issue attributed to a human decision that never happened.
- **Two deliverables had no producer.** `compound`/`compound-capture` and a fourth `triage` Step 2 branch now supply them; the questionnaire gained an address and a return leg.
- **Two scope challenges surfaced, not applied** (DC-2 cut `kb-glossary` as a skill; DC-3 defer the store). Defaults held; `ship` Phase 6 files them from `decision-challenges.md` (DC-1…DC-6, 180 L).

### Components Invoked
- Skills: `soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`
- Research: `repo-research-analyst`, `learnings-researcher`, `functional-discovery`, two `Explore` deepen passes
- Domain review: `cto`, `cco`, `clo`, `cpo`, `cmo`
- Plan-review panel: `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`
- Gates passed: plan 0.6, 0.6b, 0.6c, 0.7, 1.7, 1.7.5, 1.8, 2.5–2.12; deepen 4.4, 4.45, 4.6–4.11

## Collision Gate
- Step 0a.5 (pre-plan): #8289 OPEN, `closedByPullRequestsReferences` empty, zero linked PRs in any state. Body-probe hits #6664 (merged 2026-07-18) and #3940 (merged 2026-05-17) both predate the issue (created 2026-09-18) and intersect none of its named paths → citations, not collisions. Title probe and `git log --grep` empty. Duplicate-open-issue search over glossary / ubiquitous language / rejected request / questionnaire / out-of-scope surfaced nothing on this scope (#6008 is product-onboarding questionnaires, unrelated).
- Post-plan re-probe (this step, against the plan's `closes: 8289`): still OPEN, still no linked PR, and no open PR other than this branch's own #8405 references it.
- ADR ordinal re-derived across every `origin/*` ref: highest is ADR-231 (claimed on a sibling ref), so this bundle uses **ADR-234**. Re-derive again immediately before merge.

## Work Phase

- Status: complete. Merge-base `f9cd8dc2cb91bde560e34e6c4d1dfa02c113a159`; 42 files staged.
- Execution: Tier B fan-out, three write-only agents on disjoint file sets (Phase 2 glossary / Phase 3
  no-list+reader / Phase 4 questionnaire). The lead ran Phase 0, Phase 1 (ADR-234), Phase 5 wiring, the
  ratchets, and committed everything from one known SHA — no agent ran a git write command.

### Battery owed — `scripts/test-all.sh --capacity` reported CAPACITY_CONTENDED

The shard exit gate was NOT run. Measured at Phase 2 exit: `CAPACITY_CONTENDED
reason=sibling_runs,sibling_suites measured_runs=3 measured_suites=1` — three sibling full-gate runs in
`feat-one-shot-8308-go-gates-plugin-root`, `feat-one-shot-8339-poll-block-pipe-rc` (×2) and
`feat-one-shot-auto-inngest-pin-bump` (×2), two of them past 3400s. Per ADR-183 the merge gate is CI's
required `test` context, not any local run. Substitute set actually executed, all green:

**Repo-global ratchets (the class a file-selected set structurally cannot see), each by its own invocation:**
`guard-vacuity-floor` · `lint-trap-tempfile-ownership --changed` · `lint-rule-bodies --check --base` ·
`fixture-relative-assert` · `fixture-dir-operand-assert` · `fixture-env-adoption` ·
`lint-skill-body-budget --base` · `lint-orphan-test-suites` · `check-adr-ordinals` ·
`lint-guard-contract` · `c4-count-parity` · `generate-kb-index --check`.

**Vocabulary-derived** (tokens the diff introduces, per the #7941 blind spot — the diff adds new
`SOLEUR_RR_*` markers, so the marker drift guard is in scope and was run):
`debug-probe-residue` · `components.test.ts` · `pre-ask-technical-fork-gate.test.sh` ·
`lint-rejected-register.test.sh` · `agent-originality.test.ts`.

**Coupled surfaces:** `eval-gate` · `extract-block` · `registry-completeness` (go.md + projection) ·
`notice-frontmatter` + `_base-notice-frontmatter` (NOTICE) · `kb-index-merge-driver` ·
`generate-kb-index` · `kb-domain-allowlist-guard` (new KB dirs) · `operator-digest-skill` ·
`fanout-suite-scope` · `gdpr-gate-glob-liveness` + `gdpr-gate-self-test` ·
`lint-skill-body-budget.test.sh` · `markdown-lint.test.sh` · `workflow-fidelity` ·
`slash-name-uniqueness` · `kb-coverage` · `legal-template-vendor-surface` · `harness-parity` +
`harness-parity-tree` · markdown-lint over all 31 changed `*.md` (20 in scope, 11 under
`.markdownlintignore`).

Two suites were re-run **after** `git add`, deliberately: `lint-orphan-test-suites` and
`guard-vacuity-floor` both derive their population from `git ls-files`, so a green run over untracked
files proves nothing about them. That re-run is what surfaced the vacuity finding below.

### Errors and findings — the lead's, not the agents'

1. **The plan's mandated floor spelling would have shipped a guard the guard-guard cannot see.** The
   plan prescribes `[[ "$cases" -lt "$MIN_CASES" ]] && { … }` verbatim. `floor_lines_of()` in
   `scripts/guard-vacuity-floor.test.sh` matches `^[[:space:]]*(el)?if[[:space:]]+…`, so that shape puts
   the suite outside the ratchet's population, its ratchet and its mutation loop — and that file's own
   header names this as the one failure direction it cannot bound. Converted to `if` openers (the plan is
   authoritative for intent — a DIRECT floor, never routed through the verdict helper — not for syntax).
   `set -e` not firing on a failing non-final AND-OR member is a second, free reason.
2. **Then the ratchet reddened, and it was right.** With the suite in scope it reported the floor EXITS 0
   under a neutered assertion machinery. Cause: `cases`/`axes` are read back from `$IDS_FILE`, so they
   floor CARDINALITY; neuter the machinery and `$IDS_FILE` is still written, so both read 16/5 over a
   suite that asserted nothing. Fixed by adding a third floor over `asserted` — incremented at the CALL
   SITE, never inside a verdict helper, so it is the one quantity that collapses to 0 exactly then.
   `MIN_ASSERTIONS=40` is the measured runtime count, not the static one: `grep -cE '^[[:space:]]*ck$'`
   gives **31** call sites because several sit inside per-row loops, so the static recipe would have left
   nine assertions droppable. Ordered LAST of the three so a deleted row still trips the specific
   "battery shrank" message.
3. **The floor still scored CONSTRUCTION, not FIRES, until the diagnostic moved ahead of the ledger
   append.** The ratchet's mutant slices the floor block out of the file, so `$VERDICT_LOG` is unbound
   there and `set -u` aborted on the append before the FATAL line reached stderr. All three floors now
   print to stderr first. `guard-vacuity-floor` 23/23, firing population **142 → 143**;
   `MIN_FIRING_SUITES` 42 → 43.
4. **`fixture-relative-assert` reddened on 3 new rows** — the documented repo-global-ratchet class. Fixed
   in the CODE, not by regenerating the baseline (plan Phase 0.6.6): `${d:?}` on 20 fixture-dir parent
   references plus `${f:?}`/`${g:?}` on the two flagged operands. All three fixture rules now scan
   SITES=0 over the suite.
5. **The plan's API-budget disclosure named the wrong command.** Its ~144 calls is
   `promptfoo --repeat 3`, the manual measurement. The GATE is 270 (`--dry-run`, measured before
   spending). Actual spend **405** including one aborted run. Run at the calibrated `repeat: 5` rather
   than lowered to hit the planned figure, because fewer repeats weakens the pooled `target_rate >= 0.5`
   test the verdict rests on.
6. **`eval-gate.cjs` cannot run whenever the baseline is imperfect** — `execFileSync` throws on
   promptfoo's non-zero-on-any-assertion-failure exit, which for a probabilistic classifier is always
   (`main` scores 81.48%), and it reports that as `{"accept":false,"error":…}` — a could-not-measure
   wearing a measured-bad's clothes, while its own `computeVerdict()` carries
   `MIN_TRUSTED_CORPUS_RATE = 0.5` precisely for that case. Measured through a scratchpad copy with that
   one line tolerant; the committed gate is unchanged (`diff` confirms). Verdict **ACCEPT**: corpus
   0.7917 == 0.7917 with all 8 per-task rates byte-identical, target task **0.0 → 0.667**. Filed as a
   follow-up.
7. **A plan gap: the `go.md` edit requires regenerating the eval-harness projection** or
   `extract-block.test.sh` reds. The plan never mentions it. `gen-skill-prompt.cjs --all` run; only
   `go-skill.txt` moved, and re-running it after the `ticket-triage` edits landed confirmed
   `triage-skill.txt` regenerates byte-identically — so the severity block those markers wrap is
   untouched and the ~108-call `ticket-triage` eval is correctly not a gate for this diff.
8. **`EXTERNAL_EXPERT_RE` was correctly widened past the plan's token list, then over-fired.** AC-11's
   own question ("capex or opex") contains none of the 11 planned tokens, so the arm needed the
   profession's terms of art. Two additions were measured as false positives: `\btax` accepts
   **"taxonomy"** (it rejects "syntax" only because there is no word boundary before "tax" there, and the
   comment beside the regex asserted the opposite), and `statutory` is ambient in this repo's compliance
   prose while identifying no profession — on an arm that denies AHEAD of the authority short-circuit,
   both would have refused legitimate authorization questions. Narrowed to
   `\btax(es|ation|able|payer)?\b`, `statutory` cut, pinned by a new negative-control case **D5**
   (inventory 13 → 14) and mutation-proven in place: control 14/14, mutant 13/14 naming both false
   positives, restore byte-identical, post-restore 14/14.
9. **The vendor-mark grep was wrong twice, and both were found by running it.** `grep -vF` cannot apply
   the sanctioned-form filter (it is a regex, with `[^ ]*` for the peer path), so the filter removed
   nothing and every legitimate attribution comment reported as a violation — whose instinctive "fix" is
   deleting an attribution. And the scope is ADDED LINES, not the tree: the first cut returned 33 hits,
   every one pre-existing. Final: control 5 sanctioned comments seen and filtered, 0 unsanctioned.
10. **`gdpr-gate` produced one finding and it was applied.** `rejected/README.md:54` classified `why` as
    "the internal reason… for the team" while the same file 15 lines later states the repository is
    public and git keeps every version. The `why`/`public_note` split is a tone-of-reply boundary, not a
    confidentiality one. Reworded. 0 of 46 staged paths match the canonical regulated-data regex, so all
    five mandatory checks are N/A and no Critical fired.

### Decisions the lead took that differ from the plan text

- **Task 0.6 discharged at the Phase 2 exit, not Phase 0.** One `gdpr-gate` pass over the cumulative
  diff rather than one against the plan document plus one over the diff. The diff CONTAINS the plan file
  as an added path, and the questionnaire deliverable the Phase 0 placement existed to interrogate is
  present as code rather than as description — so the single pass is strictly more informative, and
  ADR-026 TR3 caps the skill at one pass per phase.
- **ADR-234 follows ADR-230's live shape** (Status / Context / Decision / Enforcement sites /
  Alternatives Considered / Consequences), not the template's 8-section rich block. The rubric's
  trigger 5 is hit, but the two most recent ADRs on `main` carry no YAML frontmatter at all and the
  template itself warns that an 8-section ADR with four `None` stanzas is worse than a terse one.
- **`## Alternatives Considered` carries FIVE rows, and row 2's framing is the plan's R9 correction, not
  its prose.** The plan's own row still says `deferred-scope-out` is "opposite polarity"; measured, it
  CONVERGES on `not_planned` after 90 days via `cron-stale-deferred-scope-outs.ts` with no human in the
  loop. Row 3 says nine distinct heading spellings across 234 ADRs, not the plan's five.
- **Task 1.5's stop-and-re-scope check passes on a measurement, not an argument.**
  `gh issue list --state all --search "server-side playwright in:title"` returns `[]` — the seed refusal
  is real, dated and recorded by three domain leaders, and no issue exists for a `not-planned` sweep to
  find at any keyword quality.
- **Attribution placement in the two reference docs, corrected.** An earlier revision of this bullet
  said BOTH `glossary-format.md` and `rejected-request-register.md` carry the attribution on line 1
  "because reference `.md` files in this repo carry no frontmatter". That is true of
  `glossary-format.md` (line 1) and **false of `rejected-request-register.md`**, which opens with a
  `title`/`applies_to` fence and carries its attribution on line 6, after the closing fence — i.e.
  exactly what AC-19 prescribes. Re-measured at HEAD: 7 of 110 reference `.md` files carry
  frontmatter, and this PR added one of them — the very file the claim was about. So AC-19 is
  unsatisfiable only where no fence exists; where one does, the rule applies and is followed. The
  line-1 precedent for the fenceless case is `brainstorm-techniques/references/phase-boundaries.md`.
- **Two paths outside `## Files to Edit`** are in the diff and are pipeline-written in the same sense as
  `INDEX.md`: `plugins/soleur/skills/eval-harness/prompts/go-skill.txt` (finding 7) and
  `scripts/guard-vacuity-floor.test.sh`'s `MIN_FIRING_SUITES` (finding 3).
