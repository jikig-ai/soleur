# ADR-092: Additive-only auto-edit boundary + hard-rule body-weakening gate

- **Status:** Provisional
- **Date:** 2026-07-06
- **Issue:** [#6103](https://github.com/jikig-ai/soleur/issues/6103) (prerequisite for the Self-Harness Layer 2 auto-proposer [#6038](https://github.com/jikig-ai/soleur/issues/6038))
- **Lineage:** [ADR-054](./ADR-054-safe-commit-and-pr-sole-write-path-for-bot-cron-prs.md) (bot-PR write path) · [ADR-069](./ADR-069-validation-gated-classifier-skill-edits.md) (sibling validation gate) · [ADR-027-stateless-self-modifying-cron](./ADR-027-stateless-self-modifying-cron.md)

## Status

**Provisional.** This ADR delivers #6038's criteria 2 (this decision record) + 3 (owner
= a required CI check) and closes the landmine #6038 named ("close the
`cq-rule-ids-are-immutable` gap first"), but the auto-proposer BUILD it guards is
soak-gated and cannot ship before ~2026-08-05 (criterion 1 needs ≥1 month of #6037
digests). **Revisit trigger:** the first #6037 weakness digest with ≥N samples
(~2026-08-05), when a machine actually writes rule bodies and digest evidence can tune
thresholds. The deferred half (deontic-strength lexer, LLM-judge, C4 `rulebodygate`
component, lefthook mirror) lands with the proposer PR — see Alternatives Considered.

## Context

#6038 will add a Layer-2 auto-proposer that drafts PRs editing the harness's own
guardrails. Its write target (`TARGET_ALLOW_RE` in `cron-compound-promote.ts`) is
`AGENTS.core.md` + skill `SKILL.md` files — i.e. it can edit the file where every
`hr-*` hard-rule and `wg-*` workflow-gate BODY lives. The Goodhart risk (plan
`## User-Brand Impact`, brand-survival threshold *single-user incident*): a proposer —
or a careless human — reworders `hr-gdpr-gate-on-regulated-data-surfaces` from
mandatory to advisory, the eval-gate (ADR-069, which measures skill-arm fixture
pass-rate, not guardrail coverage) stays green, and the protection preventing a
user-data / secret-leak incident is silently disabled.

A 4-agent plan panel (spec-flow, architecture-strategist, security-sentinel,
code-simplicity) + an operator User-Challenge decision (2026-07-06) cut the original
design to a **minimal v1**. The key insight: the *load-bearing* control is not a
classifier of "did this edit weaken the rule" (that is the reward-hackable half — it
misses no-hedge scope-narrowing, and it guards a machine writer that does not exist
yet). The load-bearing control is **forcing a deliberate, audit-logged human ack on
EVERY hard-rule/workflow-gate body change**, which closes the silent-weakening gap for
*all* rules today at ~half the build surface.

## Decision

**1. Additive-only boundary (append-only at the rule-SET level).** Adding a NEW rule
(new id) or a new skill section is the safe primitive — eligible for an auto draft-PR.
Any *edit or deletion* of an existing `hr-*`/`wg-*` **body** is human-only, gated by a
per-change ack. "Add a rule" is always safe; "revise/remove a rule" never is.

**2. Body-weakening gate (`scripts/lint-rule-bodies.py`).** A committed `sha256`
body-hash manifest (`.claude/rule-body-hashes.txt`) over the union of `hr-*`/`wg-*`
body lines across all three sidecars (`AGENTS.{core,docs,rest}.md`). The CI gate
`--check --base <merge-base>` **re-derives** every hash itself (never trusts the
committed manifest value — a hand-edited/stale manifest is BLOCKED), diffs each body
against its state at `git merge-base origin/main HEAD` (NOT `origin/main` tip), and
requires a matching per-change ack for every changed or deleted body. The ack is a
hash-bound line `<id>|<sha256>|<date>|<PR>|<reason>` (`DELETED` token for deletions)
in the append-only WORM file `.claude/rule-weakening-acks.txt`; the `<sha256>` must
equal the NEW body hash, so a stale ack for an earlier weakening does not satisfy a
later, different one. `[compliance-tier]`/`[hook-enforced]`/`[skill-enforced]` tags on
the old∪new body escalate to a louder mandatory-human-review annotation, but the ack
is required for ALL hard-rule/workflow-gate bodies regardless (the headline threat rule
`hr-gdpr-gate` is `[hook-enforced]`, not `[compliance-tier]` — a tag-scoped gate would
have missed it). Normalization before hashing collapses whitespace runs (a re-indent
is a no-op); enforcement-tag ORDER is deliberately NOT normalized (fail toward an ack
— a robust mid-prose tag-order normalizer risks masking a real tag DROP, the far worse
false-negative). Baseline: 72 gated bodies (43 `hr-*` + 29 `wg-*`); calibration is
zero findings on a clean tree.

The gate closes four reward-hack / masking classes surfaced at multi-agent review
(each reproduced end-to-end, then blocked):
- **SECTIONS-oracle narrowing:** the gate parses BOTH base and head sidecars with
  the UNION of base-side and head-side `SECTIONS` (read from
  `scripts/_agents_md_sections.py` in the tree under check). Narrowing `SECTIONS`
  while weakening a body in the same diff cannot hide the body from the base parse.
  `_agents_md_sections.py` is a pinned gate-control file (CODEOWNERS + the recursion
  ∉ list).
- **Cross-sidecar decoy (last-file-wins):** a gated id appearing in two sidecars is
  fail-closed (exit 2) — otherwise a same-id decoy carrying the strong text in a
  second sidecar could mask a weakening of the real, runtime-loaded body.
- **Ack-replay:** the ack must be NEWLY added in this diff (`head_acks −
  base_acks`), so reverting a body to any previously-acked form does not pass on a
  stale historical ack.
- **Reason-less ack:** an ack is valid only in the full 5-field shape with a
  non-empty reason — the "deliberate, reasoned" property is enforced, not advisory.

**Accepted residual (rename-and-clone, ADR threat model):** retiring `hr-x` and
adding `hr-x-v2` with a weakened body is scored as a DELETION of `hr-x` (needs a
`hr-x|DELETED|…` ack + an edit to `retired-rule-ids.txt`) plus an ADDITIVE new rule
(allowed; a security-tagged additive fires the annotation). The semantic weakening
is not surfaced AS a weakening — but both the DELETED ack and the new rule are
visible in the diff, and full semantic-equivalence detection is the deferred lexer's
job (#6038). Documented so it is a conscious residual, not a blind spot.

**3. Owner = a required CI check + the ack (#6038 criterion 3), de-ceremonialized for a
solo operator.** `rule-body-lint` is an always-run `ci.yml` job wired as the 18th
required context in `scripts/ci-required-ruleset-canonical-required-status-checks.json`
+ `infra/github/ruleset-ci-required.tf` (auto-applied on merge by
`apply-github-infra.yml`) + `scripts/required-checks.txt` (canonical set-parity) and
auto-enrolled in the required-check drift-guard cron (which reads the canonical JSON).
The ack is **tamper-evidence + a required human-review gate, NOT full
segregation-of-duties** (ARCH-P1-d): a solo operator may weaken + ack across one
CODEOWNERS-reviewed PR. **Live-enforcement note (verified 2026-07-06):** CODEOWNERS
review is NOT currently enforced on `main` (no ruleset requires PR reviews / code-owner
review; no branch protection — the CODEOWNERS header itself flags this as a pending
operator follow-up). So the LIVE control today is the required `rule-body-lint` CI check
+ the deliberate, reasoned, hash-bound ack authoring — not a second-reviewer gate. The
CODEOWNERS rows on the gate's load-bearing files become teeth the day branch protection
is enabled.

**4. Recursion invariant.** The gate's own control surface — `lint-rule-bodies.py`, the
manifest, the ack file, `ci.yml`, `lefthook.yml`, this ADR, the `.c4` model — stays
OUTSIDE `TARGET_ALLOW_RE`, so a proposer cannot weaken a rule and rewrite the gate that
would catch it in the same draft. Pinned by a test that **imports** the live
`TARGET_ALLOW_RE` symbol AND asserts the real catch property (a synthetic weakening /
tag-drop to `AGENTS.core.md` IS blocked by `--check`) — not the vacuous ∉ tautology.

## Consequences

- **Every hard-rule/workflow-gate body change now costs a WORM ack.** Intended friction:
  a weakening becomes a deliberate, reasoned, permanently-logged act rather than a
  silent diff. The three-step workflow is edit → `--write` (regenerate manifest) →
  append ack.
- **Bot-PR fabrication residual (CTO ruling 2026-07-06, Option A).** `rule-body-lint` is
  a 15368 context, so canonical set-parity forces it into `required-checks.txt`, which
  the bot composite action FABRICATES a green for (no per-check review, #6049). This is
  a residual over a **null set today**: the bot action's `ALLOWED_PATHS` =
  {weakness-digest.md, rule-metrics.json} makes `AGENTS.{core,docs,rest}.md` physically
  unreachable by every bot PR, so no bot can weaken a body under the fabricated green.
  The residual goes LIVE only when #6038's auto-proposer adds an AGENTS path to
  `ALLOWED_PATHS` — and the #6049 Phase-4 ceiling guard STRUCTURALLY forces that PR to
  reproduce `rule-body-lint --check` over the bot diff first. Recorded in
  `required-checks.txt` (CODEOWNERS-gated comment) + the `action.yml` Phase-4
  preflight-TODO. Rejected alternatives (B) reproduce-now and (C) fold-into-`test` — see
  below.
- **C4 views deferred.** A single CI lint script is below the C4 component threshold, and
  the honest edges ("auto-proposer → gate → rule corpus") reference elements that do not
  exist in the model yet — inventing them breaks `c4-code-syntax.test.ts` and violates
  ADR-069's no-invented-edge precedent. The `rulebodygate` component + its real edge land
  when the auto-proposer actor is modeled (with #6038).
- **Ordinal 091 is provisional** — re-verify the next-free ordinal at ship and sweep
  planning docs on any renumber. The two-file ADR-027 ordinal collision (…-stateless-
  self-modifying-cron + …-process-local-state) is pre-existing and out of scope; this
  ADR cites the stateless-cron file by name.

## Alternatives Considered

- **Deontic-strength lexer as the gate (original design half).** DEFERRED to the #6038
  proposer PR — it is the reward-hackable half (misses no-hedge scope-narrowing), it
  guards a machine writer that does not exist until #6038, and its thresholds need soak
  evidence (NG2/NG5). Blocking every body edit pending a human ack is strictly stronger
  today.
- **LLM-judge gate.** Rejected — same reward-hackable class; advisory-only; belongs with
  the proposer.
- **Lefthook-only (mirror `lint-rule-ids.py`).** Rejected — bot PRs and `--no-verify`
  skip lefthook; the required CI check is the load-bearing gate. A lefthook mirror is a
  deferred convenience.
- **Ack scoped to `[compliance-tier]` rules only.** Rejected — the headline threat rule
  `hr-gdpr-gate` is `[hook-enforced]`, not `[compliance-tier]`; a tag-scoped gate misses
  it. Ack is required for all `hr-*`/`wg-*` bodies; tags only make the CI message louder.
- **CI wiring, Option B — reproduce `rule-body-lint` in the bot action's Phase-4 ceiling
  now (earned, not fabricated green).** Rejected — premature surface on a load-bearing
  shared security action for a window that cannot open until #6038 (the #6049 guard
  enforces the sequencing). YAGNI.
- **CI wiring, Option C — fold the gate into the existing required `test` context (no new
  required context).** Rejected — carries the SAME bot-fabrication residual (`test` is
  fabricated too), yet fails the "owner = a dedicated required check" criterion and trades
  away the ABI/anti-deletion strength (a standalone required context that stops reporting
  → merge blocked) for a smaller surface — the wrong trade for a single-user-incident
  guardrail whose value is being hard to silently remove.
