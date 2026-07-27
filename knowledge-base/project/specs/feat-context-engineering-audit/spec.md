---
title: "Context-governance instrument fixes (Claude-5 context-engineering audit)"
date: 2026-07-27
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-07-27-context-engineering-claude5-audit-brainstorm.md
branch: feat-context-engineering-audit
pr: 7006
---

# Spec — Context-governance instrument fixes

> **CORRECTION (2026-07-27, post-review): FR7 is WITHDRAWN, and FR2 was cut.**
>
> **FR7 — my finding was wrong.** I reported the six `-auto-approve` sites as a
> "literal inversion" of `hr-menu-option-ack-not-prod-write-auth`. They are not.
> Three review agents converged, and two measurements settle it:
> 1. `terraform apply -input=true` with no TTY does **not** hang — it exits
>    immediately with `Error: error asking for approval: EOF` (measured: rc=1,
>    0s). My "hangs forever" rationale — repeated in this document, the commit
>    messages and the issue — was false. The old form failed **closed**.
> 2. `.claude/hooks/prod-write-defer-gate.sh` is a registered PreToolUse hook
>    that **defers** any agent-run `terraform apply` (measured), so the agent
>    never runs it unattended regardless of the flag.
>
> Those commands are run by a human at a real terminal (`admin-ip-refresh`
> SKILL.md Step 7: *"for the operator to run. Do NOT execute them."*), where
> Terraform's native prompt **is** the per-command gate. "Do NOT pass
> `-auto-approve`" was correct guidance. All six sites are reverted to `main`.
>
> **FR2 (stamp byte figure) — cut.** It was the only reason the `CORPUS` loop
> existed, and that loop introduced two P1s of its own (a false over-strip
> warning, and a denominator that collapsed onto the numerator so a truncated
> corpus stamped as 100%). The denominator now derives from the `AGENTS.md`
> index — a fixed expected set — which is simpler and strictly more honest.
>
> What ships: FR1, FR6, FR8, FR9, FR11.


## Problem Statement

Anthropic's Claude-5 context-engineering guidance prescribes a rules diet Soleur already
ran (36% of rules retired, discoverability litmus landed 2026-04-23). The audit found no
warrant for a further deletion campaign, but did find that **the instruments governing
context are misreporting**, in the same direction — they understate real footprint and
overstate coverage:

1. `session-rules-loader.sh:247` computes its total-rule denominator with the glob
   `AGENTS*.md`, which matches the index *and* the bodies, double-counting every rule.
   The session stamp reads `(101 of 202 rules)` — apparently 50% — when 100% of the
   corpus is loaded.
2. Consequently nobody has observed that progressive disclosure is **8.7% effective**:
   70% of PRs are multi-class and load all three sidecars (43.5 KB), because Soleur's own
   inflow gates put a `.md` in nearly every code PR.
3. `scripts/lint-agents-rule-budget.py` gates `B_ALWAYS` on `AGENTS.md + AGENTS.core.md`
   only (22,900 B), which is **53% of the 43,513 B** actually injected in the fail-open
   case. The governance ceiling protects a figure that is not the real one.
4. The skill-description budget is **exceeded by 33.3%** (2,400 words across 95 skills
   against an enforced 1,800 cap, headroom −600) with no gate having fired.
4b. The article's first-named anti-pattern — **conflicting messages** — is live and
   unaudited: 4 rule↔rule contradictions, 4 rule↔skill drifts (one a literal inversion),
   and 4 skill citations of rule ids that do not exist. `scripts/lint-rule-ids.py`
   validates id integrity only and cannot see any of them.
5. `scripts/rule-prune.sh:167` exempts only `[hook-enforced]`/`[skill-enforced]` rules
   from retirement proposals — **not `[compliance-tier]`** — so the quarterly pruner can
   propose retiring a rule cited by the Art. 30 register or the published DPD.
6. `knowledge-base/legal/article-30-register.md:417` cites `hr-block-pr-ready-on-undeferred-operator-steps`,
   which does not exist (real id is `wg-`). A register citation is already dangling.

## Goals

- Make every context-governance instrument report a true number.
- Surface the real progressive-disclosure effectiveness so future decisions rest on it.
- Close two latent compliance defects found incidentally.
- Restore the skill-description budget to within its enforced cap.

## Non-Goals

- **No rule deletions.** Explicitly out of scope (brainstorm decision; #6794 forbids
  pruning on `rules_unused_over_8w`).
- **No change to the class axis or sidecar split.** Deferred until the fixed instrument
  has produced observations.
- **No softening of any `[compliance-tier]` or `**Why:** #NNNN` rule.**
- **No adoption of auto-memory.** `hr-never-write-to-claude-code-memory-claude` stands.
- Fixing the 11 shipped plugin files that reference root-only governance paths — separate
  issue (see FR6 note).

## Functional Requirements

**FR1 — Loader denominator counts rules once.**
`session-rules-loader.sh:247` must count rule bodies only, excluding the `AGENTS.md`
index. Change the glob from `AGENTS*.md` to the three body sidecars. After the fix, a
fail-open session must stamp `(101 of 101 rules)`.

**FR2 — Stamp reports byte footprint, not just rule count.**
The stamp must additionally report loaded bytes against total corpus bytes, e.g.
`43513/43513 B`. Rule count alone cannot express that a docs-only session loads 62% of
the bytes; bytes are the quantity the harness cost scales with.

**FR3 — Budget gate measures the real fail-open footprint.**
`lint-agents-rule-budget.py` must report `B_FAILOPEN` (all four files, frontmatter-stripped)
alongside the existing `B_ALWAYS`. `B_ALWAYS` keeps its 20,000/23,000 thresholds as the
hard gate; `B_FAILOPEN` is reported for visibility this iteration and **must not** gate —
introducing a second blocking ceiling at 43.5 KB would immediately REJECT and wedge the
repo. Thresholding it is a follow-up decision, not this PR's.

**FR4 — Skill-description budget restored under cap.**
Reduce total skill `description:` frontmatter from **2,400 words to ≤1,800 (−600 minimum)**
across 95 skills. Trim the longest first (`invoice` 39w, `flag-delete` 37w, `drain-prs` 35w,
`trigger-cron` 34w, `cf-token-scope` 34w, `schedule` 33w, `resolve-parallel` 33w,
`reproduce-bug` 33w). Each trimmed description must retain its disambiguating trigger
terms — these are the routing surface, and over-trimming causes mis-routing. Per
`cq-skill-description-budget-headroom`.

**FR7 — Resolve the `-auto-approve` inversion (highest operational severity).**
`hr-menu-option-ack-not-prod-write-auth` `[compliance-tier]` mandates: ack first, **THEN
run with `-auto-approve`**. `plugins/soleur/skills/ship/SKILL.md:821` ("Do NOT pass
`-auto-approve`") and `plugins/soleur/skills/admin-ip-refresh/SKILL.md:42` ("no `--yes`,
no `-auto-approve`") state the inverse **while citing that rule id**. Because the Bash tool
is non-interactive (`hr-the-bash-tool-runs-in-a-non-interactive`), following the skills
makes the command block on an unanswerable TTY prompt. Reconcile in favour of the rule —
it is compliance-tier and register-cited, so the skills are what must change. If either
skill has a genuine reason to withhold `-auto-approve`, that exception must be stated in
the rule, not contradicted in the skill.

**FR8 — Resolve the rule↔rule contradiction.**
`wg-when-an-audit-identifies-pre-existing` ("file them") vs
`wg-when-deferring-a-capability-create-a` ("document in-place; file ONLY when the triple
test passes"). Add an explicit precedence clause to whichever rule is narrower so the
overlapping case — a pre-existing issue found in audit that the agent elects to defer —
has one answer. Do not delete either rule.

**FR9 — Repair the 4 dead rule citations.**
Skills cite `cq-minimalism-ladder-generation-bias`, `cq-pencil-collapse-auto-recover`,
`cq-when-a-plan-prescribes-a-validator-guard-or`, `cq-when-a-pr-has-post-merge-operator-actions`
— none exist in `AGENTS.md`. For each, either point at the surviving rule or remove the
citation. Cross-check `scripts/retired-rule-ids.txt`: if the id was retired, the citation
should point at the breadcrumb, not a live rule.

**FR5 — `rule-prune.sh` exempts compliance-tier rules.**
Add `[compliance-tier]` to the exemption predicate at `scripts/rule-prune.sh:167`, so the
pruner can never propose retiring a rule whose id is cited by a legal artifact.

**FR6 — Dangling register citation corrected.**
`article-30-register.md:417`: `hr-block-pr-ready-on-undeferred-operator-steps` →
`wg-block-pr-ready-on-undeferred-operator-steps`. Verify the corrected id resolves against
`AGENTS.md` before commit.

## Technical Requirements

**TR1 — Regression test for FR1/FR2.**
Extend `.claude/hooks/session-rules-loader.test.sh`: assert the stamp's `N of M` has
`M == 101` and that `M` equals the body-sidecar rule count computed independently. This
test must fail against the current implementation before the fix (per `cq-write-failing-tests-before`).

**TR2 — Class-share measurement is reproducible.**
Land the 80-PR classification as a script so the 8.7%-effective figure can be re-measured
rather than re-derived by hand. It must consume the loader's own `DOCS_RE`/`CODE_RE`/`INFRA_RE`
rather than copying them, so the two cannot drift.

**TR3 — No behaviour change to class selection.**
FR1–FR3 are reporting-only. The set of rules loaded for any given changeset must be
byte-identical before and after. Assert by diffing loader output across the three class
paths on fixed inputs.

**TR4 — Budget lint stays green.**
`python3 scripts/lint-agents-rule-budget.py` must not regress from `[WARN]` to `[REJECT]`.
Current headroom is 100 B; no FR here adds sidecar bytes.

**TR5 — Rule-id integrity preserved.**
`scripts/lint-rule-ids.py` must exit 0. FR6 changes a citation in a legal document, not a
rule id; `cq-rule-ids-are-immutable` is unaffected.

## Acceptance Criteria

- [ ] Fail-open session stamps `(101 of 101 rules)` plus a byte figure.
- [ ] `session-rules-loader.test.sh` covers the denominator; fails pre-fix, passes post-fix.
- [ ] `lint-agents-rule-budget.py` reports both `B_ALWAYS` and `B_FAILOPEN`; verdict still `[WARN]`.
- [ ] Skill descriptions total ≤1,800 words (from 2,400).
- [ ] `rule-prune.sh --dry-run` proposes zero `[compliance-tier]` rules.
- [ ] `article-30-register.md:417` cites a rule id that exists in `AGENTS.md`.
- [ ] Loader output byte-identical across all three class paths (TR3).
- [ ] `ship/SKILL.md:821` and `admin-ip-refresh/SKILL.md:42` no longer contradict
      `hr-menu-option-ack-not-prod-write-auth`.
- [ ] The audit-vs-defer overlap resolves to exactly one instruction.
- [ ] Zero skill citations of non-existent rule ids (`grep` each cited id against `AGENTS.md`
      ∪ `scripts/retired-rule-ids.txt`).
- [ ] **Zero rules added or deleted.** FR8 may add a precedence clause to an existing rule
      body; FR7 may add an exception clause. Both must keep `B_ALWAYS` under 23,000 —
      only 100 B of headroom exists, so a clause that does not fit forces a `wg-*`
      demotion, prescribed in the plan rather than improvised at implementation time.

## Follow-ups (not this PR)

- **Rule↔skill semantic-drift auditor.** Nothing audits this today; that absence is why
  all 12 conflicts are live. Capability gap — file for engineering.
- **Classifier-axis re-cut.** Excluding `knowledge-base/**` from `DOCS_RE` would save
  ~17 KB on ~70% of sessions, but risks PR #3681's silent-missing-rule failure mode.
  Requires an ADR (`/soleur:architecture create`), and should follow at least one
  observation window on the *fixed* instrument — deciding on today's numbers would repeat
  the mistake this spec exists to correct.
- **11 shipped plugin files referencing root-only governance paths**
  (`AGENTS.core.md`, `session-rules-loader.sh`, `scripts/lint-agents-rule-budget.py`),
  which do not exist in an installed tenant repo (`marketplace.json:18` scopes the package
  to `./plugins/soleur`). `compound` step 8 and `grok-fidelity-gate.sh` both invoke them.
