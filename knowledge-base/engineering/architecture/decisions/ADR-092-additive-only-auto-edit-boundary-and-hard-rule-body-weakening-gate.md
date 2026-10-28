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
the always-loaded rule corpus + skill `SKILL.md` files — i.e. it can edit the file where every
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
body lines across the rule corpus (`AGENTS.rules.md`; three change-class sidecars
until ADR-151 — see Amendment). The CI gate
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

- `infra/github/ruleset-ci-required.tf` (auto-applied on merge by
`apply-github-infra.yml`) + `scripts/required-checks.txt` (canonical set-parity) and
auto-enrolled in the required-check drift-guard cron (which reads the canonical JSON).
The ack is **tamper-evidence + a required human-review gate, NOT full
segregation-of-duties** (ARCH-P1-d): a solo operator may weaken + ack across one
CODEOWNERS-reviewed PR. **Live-enforcement note (verified 2026-07-06):** CODEOWNERS
review is NOT currently enforced on `main` (no ruleset requires PR reviews / code-owner
review; no branch protection — the CODEOWNERS header itself flags this as a pending
operator follow-up). So the LIVE control today is the required `rule-body-lint` CI check
- the deliberate, reasoned, hash-bound ack authoring — not a second-reviewer gate. The
CODEOWNERS rows on the gate's load-bearing files become teeth the day branch protection
is enabled.

**4. Recursion invariant.** The gate's own control surface — `lint-rule-bodies.py`, the
manifest, the ack file, `ci.yml`, `lefthook.yml`, this ADR, the `.c4` model — stays
OUTSIDE `TARGET_ALLOW_RE`, so a proposer cannot weaken a rule and rewrite the gate that
would catch it in the same draft. Pinned by a test that **imports** the live
`TARGET_ALLOW_RE` symbol AND asserts the real catch property (a synthetic weakening /
tag-drop to the rule corpus IS blocked by `--check`) — not the vacuous ∉ tautology.

## Consequences

- **Every hard-rule/workflow-gate body change now costs a WORM ack.** Intended friction:
  a weakening becomes a deliberate, reasoned, permanently-logged act rather than a
  silent diff. The three-step workflow is edit → `--write` (regenerate manifest) →
  append ack.
- **Bot-PR fabrication residual (CTO ruling 2026-07-06, Option A).** `rule-body-lint` is
  a 15368 context, so canonical set-parity forces it into `required-checks.txt`, which
  the bot composite action FABRICATES a green for (no per-check review, #6049). This is
  a residual over a **null set today**: the bot action's `ALLOWED_PATHS` =
  {weakness-digest.md, rule-metrics.json} makes `AGENTS.rules.md` physically
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

## Amendment — ADR-151 (2026-07-28)

Two changes, both consequences of collapsing the three change-class sidecars into
one unconditional `AGENTS.rules.md`:

1. **The "cross-sidecar decoy (last-file-wins)" threat class (F1) no longer
   exists.** It required a SECOND sidecar in which a same-id decoy body could win
   the union merge and mask a weakening of the real, runtime-loaded body. With one
   corpus there is no second file, so the collision detector in
   `lint-rule-bodies.py` had no failing input left and was DELETED rather than
   left as a green gate that cannot fail. A duplicate id *within* the corpus is
   still caught by `lint-rule-ids.py`'s per-file duplicate check.
2. **The gate's scope is now "body lines in `AGENTS.rules.md`"**, not "across all
   three sidecars".

**Disclosed migration gap (SE-1).** `SIDECARS` is head-side, so across the single
commit performing the merge, `git show <base>:AGENTS.rules.md` resolves to nothing
and the base map is empty — the gate passes VACUOUSLY for that one commit. This
was accepted knowingly, with an all-101 body-hash identity snapshot as the
compensating proof (the committed manifest covers only the 74 `^(hr|wg)-` bodies,
so it could not have proven the other 27 unchanged). Splitting the file move and
the constant into separate commits would have been worse: every gated body would
read as DELETED and demand ~74 WORM acks.

## Amendment — server-derived additive edit (2026-10-19, #10552)

**Who authors the diff changed.** The compound-promote proposer used to ask the model for a
unified diff. Three consecutive weekly runs each failed `git apply` in a different way (no hunk,
wrong hunk counts, unparseable hunk header) because the model was asked for line-numbered output
about a file it was never shown, so no proposal ever reached the additive-boundary gates this ADR
defines. The model now returns an anchor line and the lines to insert; the server splices them into
the HEAD text of an allowlisted target and derives the diff with git. The additive boundary is
therefore **additive by construction at the point the diff is authored**, and is still asserted in
code (`isAdditiveDiff` refuses any removed line as `edit-derive-failed`) and, unchanged, by
`diffRemovesHardRule` and the shrink floor downstream.

**Two granularities, stated so they are not confused.** The boundary this ADR gates is at the
rule-set level (no existing rule body is weakened or removed). The new construction is at the line
level (nothing but insertions can be produced). The line-level property implies the rule-set one for
the edits the cron can now make; it does not replace the body-weakening gate for human edits.

**Compensating controls on model-authored text.** Because the inserted text lands in the
always-loaded corpus, it is constrained in code rather than by prompt: printable ASCII only,
caps of 20 lines and, per line, 600 characters for `AGENTS.rules.md` (pinned by a test to the corpus lint's `PER_RULE_CAP`) or 1000 for `SKILL.md`, with a 500-character target stated in the prompt (corrected on the merge of PR #11157, #10552; this sentence previously said 500; the diff-size gate still bounds the whole diff at 16,384 characters), no credential-shaped substring (the credential tail of
`PII_REGEX`, parity-pinned by a test, plus a private-key header and a bearer credential), no bare
`---`, and no code fence, HTML comment, harness preprocessing marker, link or image other than a relative
`./` / `../` one, URL (`://`) or command substitution (`$(`), and no `[mandates-filing]`-style enforcement tag. Source learnings are
deduplicated and restricted to corpus paths before the cluster hash, the commit trailers and the PR body. For `AGENTS.rules.md` every
line is exactly one rule bullet with ONE new id of class `cq-`, `rf-`, `pdr-` or `cm-` (the grammar
`scripts/lint-rule-ids.py` accepts, minus the classes this ADR reserves for human review): a model
cannot mint an `hr-` or `wg-` rule, and no `hr-` or `wg-` token may appear anywhere in an inserted line. A
`SKILL.md` anchor inside the frontmatter or a fenced block is refused.

**The draft is single-file, so its CI starts red.** `lint-rule-ids` requires an `AGENTS.md` pointer
for every rule body, and the cron edits one file only. The draft PR body names the exact
`- [id: <slug>]` line for the reviewer to add; extending the cron to write `AGENTS.md` was considered
and rejected because it would widen the write boundary this ADR keeps narrow (CTO ruling,
2026-10-19).

**New refusal members** (`EDIT_REFUSAL_REASONS`, seven): `edit-target-unreadable`,
`edit-target-too-large`, `edit-invalid`, `edit-anchor-not-found`, `edit-anchor-ambiguous`,
`edit-target-duplicate`, `edit-derive-failed`. `diff-underivable-apply` is retained for a derived
diff that git then rejects, which is a server defect. The marker field set is unchanged.

**C4.** No change: the same Inngest function calls the same external systems. The "C4 views
deferred" bullet above stays accurate.

## Amendment — server-enforced promotion quorum (2026-10-20)

**Where the "5" is enforced changed.** The loop promises a cluster only when at least five source
learnings back it, but that number lived only in the phase-1 prompt and as the literal `/5` in the
draft PR trailer `Threshold-Hit: N/5`; the server never checked it, so a two-learning cluster could
open a draft PR whose own trailer read `2/5`. The quorum is now enforced in code by the exported
constant `PROMOTION_QUORUM` in `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`.
It is a code constant on purpose, not a field of `promotion-config.yml`: a config-only change must not
be able to weaken what may be proposed into the always-loaded corpus. Changing its value needs an
amendment to this ADR and the matching line in `compound-promote-runbook.md`. The phase-1 prompt, the
check and the trailer denominator all read it, and census Guard 1d pins one declaration and those
three reads (it pins consistency, not the value; a value-pin test makes a change a visible diff).

**The check.** It is the first statement that can refuse inside `draftAdditiveEdit`: it counts the
cluster's DISTINCT source learnings that are keys of the collected corpus (exactly the set phase 2
would show the model, after the PR #10553 normalisation) and refuses a count below the quorum as
`quorum-not-met` (Sentry cause `below-quorum`). It runs before `readEditTarget`, so no git read
happens, and before the phase-2 model call, so nothing is spent. It subsumes the former
`edit-invalid`/`no-source` cause (zero sources is below any positive quorum), which is deleted. The
draft callback itself still checks the API key and reads the always-loaded files before it reaches the
drafter; those are not model calls and are accepted. Order for one cluster: duplicate target
(`edit-target-duplicate`, handler body), then `target-path-refused` (first check in the draft step),
then `quorum-not-met`, then the git reads and the model call.

**Why inside the draft step, not beside it.** The refusal rides the existing memoized
`draft-edit-<hash8>` step, so it reuses the one `DraftOutcome` -> `record()` -> marker `refusals[]` path
and the Sentry event fires once per step, not once per replay. A handler-body predicate would re-fire
the Sentry call on every replay, and a second memoized step would break census Guard 3b, which allows
exactly one `Promise<DraftOutcome>` callback.

**Vocabulary and observability.** `quorum-not-met` is a new member of the refusal vocabulary but not an
`edit-*` one: `EDIT_REFUSAL_REASONS` stays at seven (Guard 1b pins that prefix), as `target-path-refused`
before it. Sentry reuses op `draft-edit-refused` with tags `reason` and `cause`, plus two bare-integer
`extra` fields, `source_count` (distinct resolved) and `proposed_count` (the model's raw list length
before normalisation), which separate "the model proposed too few" from "normalisation dropped paths the
corpus does not hold". The outcome-marker field set is unchanged (`compound-promote-marker.ts` is not
edited). The follow-through probe for #10552 classes the reason N: a quorum refusal is a model-side
outcome, never proof (PASS) and never a server defect (FAIL).

**Known consequences, stated so they are not rediscovered.** A refused cluster still occupies one of the
week-cap proposal slots (the phase-1 answer is sliced to the remaining cap, minus one on an `allow_create` run since 2026-10-27, before the server normalises
it), and still counts in the headroom divisor `proposals.length - clusterIndex`, so a valid first
cluster can be offered a smaller headroom share. Moving the filter ahead of the slice was rejected: it
needs the corpus-key check inside the phase-1 step (replay risk) and would hide refusals from the marker.
With `remaining = 2` and a model answer of `[thin, thin, valid]`, the valid cluster is dropped by the
slice with no refusal recorded for it. The gate counts distinct corpus paths, not relatedness or
distinct content (a repository writer can inflate the count with copies or symlinked files; that is
inherent to a count-based gate and outside the threat model of an operator-reviewed, never-auto-merged
loop), so `Threshold-Hit: 5/5` is a floor, and the human review of every draft PR is unchanged. A
`draft-edit-*` step memoized by an older deploy resumes on the new code with its stored outcome, so a
sub-quorum cluster it had already drafted still opens one PR; the window is one weekly run.

**Deferral closed.** This overturns the line "Server-side quorum of 5 source learnings: unchanged
(pre-existing)" recorded in the #10552 decision record (Review round 2 dispositions); the revisit
trigger named there (#8293) stays open and is not something this change waits on.

**C4.** No change (CTO ruling 2026-10-20): the same Inngest function calls the same external systems;
model call volume only falls.

## Amendment — create-only new-skill path (2026-10-26, #10550)

*Dated, append-only; no earlier section is edited. Conditioned on the merge of the pull request that carries the create arm of `cron-compound-promote` (#10550, WikiSkill Phase 2): until then none of this describes a deployed state. The arm is dark-launched: it is reachable only on a manual trigger with `input: "patterns"` AND `allow_create: true` (default off); the scheduled run and a manual `input: "corpus"` run are unchanged.*

**What is amended, and what is not.** The ADR's `## Decision` item 1 already names a new skill section as the safe primitive, and the 2026-10-19 amendment covers insertion into an EXISTING allowlisted target only. This amendment adds a second, separate admission path that may CREATE a brand-new skill. It does not loosen the first. `checkDiffPaths`, `TARGET_ALLOW_RE` and `isAdditiveDiff` are untouched and keep refusing any status other than `M`, any structural operation and any path off the target: the edit arm still never accepts status `A`, and a test pins that. `AGENTS.rules.md` and `AGENTS.md` are not written by the create arm, so the hard-rule body-weakening gate and the hash manifest have nothing to weaken.

**The closed path set.** A create may commit exactly six paths, all with status `A` or, for the three shared files, `M`, and nothing deleted:

- `plugins/soleur/skills/<slug>/SKILL.md` (new, markdown only)
- `plugins/soleur/skills/<slug>/PURPOSE.md` (new, markdown only)
- `plugins/soleur/cursor/skills/soleur-<slug>/SKILL.md` (new, the Cursor stub)
- `README.md` and `plugins/soleur/README.md` (modified, digit-only count changes produced by `scripts/sync-readme-counts.sh`)
- `knowledge-base/project/learnings/promotion-log.md` (modified, one appended ledger row)

A seventh path, a script, a hook, a config file or anything outside this set is refused. The set is derived by one exported function, `createPathList(slug)`, read by the persistence call and the tests and pinned against this text; there is no second path-set check to drift from it.

**Who authors the bytes.** The model never authors a file or a diff. One model call returns structured fields; the server renders SKILL.md, PURPOSE.md (from the template `plugins/soleur/skills/skill-creator/templates/purpose.md`) and the stub, and fixes the frontmatter (exactly `name` and `description`), the headings, the single link to `./PURPOSE.md`, the Grok invoke block and the attribution text. Every model string must pass a shape ALLOWLIST (plain printable ASCII; no backticks, fences, URLs, link syntax, `[id:`, rule-id tokens, `soleur:` tokens or leading command forms; claim words refused case-insensitively), an instruction-risk phrase denylist (destructive or privileged commands in any flag spelling, code-execution and network tools, reading or sending secrets and credential files, overriding earlier instructions or safeguards, acting without review or confirmation), then the PII and credential checks, and the screens run again over the rendered files; the denylist is applied to each line alone, and the slug is exempt from it except when it is exactly one destructive token. The Origin and Patterns addressed sections of PURPOSE.md are not model text: the server renders them from the validated pattern slug, the evidence count and the run date (the model schema has no such fields), and the only model prose in PURPOSE.md is the patch-rejection reason, which sits under the same denylist and screens.

**A new checkCreate with its own closed verdict union.** The create arm has its own chokepoint, `checkCreate`, feeding the single create-arm `safeCommitAndPr` call in `exactPaths` mode with `expectedContent` (the digest precedent of #7122), `allowedPaths: []`, a draft PR, the label `self-healing/auto`, no auto-merge (`mergeMode: "none"`) and a fixed `CREATE (new skill)` PR-body line. Every refusal is the single reason `create-refused` with a closed `class`; ADR-054 (`safeCommitAndPr` is the sole write path) is honoured, not changed.

**Gates on the new path.** The arm runs in two steps and the order below is the order the code runs, exported once as `CREATE_STAGE_ORDER` and pinned to this text by the parity suite. Step A (`create-propose`), in order: the week cap (shared with the edit arm, edit loop first; on an `allow_create` run the loop is held to the free slots minus one, so the arm always has a slot, amended 2026-10-27), a non-empty pattern index, a pattern the edit loop already recorded this run is not offered (nothing offerable is a clean no-action; since 2026-10-28 a pattern the ledger already owns is not offered either, and an empty offer on that account is `all-owned`), the clone being present, one open create at a time, the budget and collision populations measured from the clone, including the open pull request path scan (a readable cap and total, failing closed), the input-size ceiling (refuse, never truncate), the API key, then ONE model call with no retry. Step A runs with the installation token on disk but spawns no script. After the call comes `checkCreate`, whose gates run in this order: schema validation; slug format; shape, instruction-risk and claim-word checks over every model string; the PII and credential screen over every model string; the ledger (a pattern with an existing proposal, or a hash already used in this run, is suppressed for create too); slug collision (skill, agent, command stem, Cursor stub directory, open pull request paths); prefer-patch (the model must name an existing nearest skill, it must rank in the server's top three by overlap and the top overlap score must be under the calibrated threshold); the description budget (a readable cap and total, at least the minimum and at most 30 words, and within `cap - total`). Step B (`create-persist`), in order: the branch-taken check, before the clone is touched; then it sets the installation token, runs `git fetch --depth=1 origin main` and `git reset --hard FETCH_HEAD` to refresh the clone, strips the token from `remote.origin.url`, re-runs `checkCreate` on the refreshed tree, renders the three files and runs the rendered-output gate (size caps, PII and credential screens, link and frontmatter shape, no fences, and the instruction-risk scan over the model-derived segments of SKILL.md and PURPOSE.md, each line alone; the fixed server templates are exempt and a golden test proves them clean; the stub check is renderer self-consistency; parity with the real generator is CI `cursor-name-map --check`); then `soleur:skill-security-scan` on BOTH files, accepted only on exit 0 and a first line exactly `# skill-security-scan verdict: LOW-RISK`; the README sync (changed set exactly the two README paths); the bytes-differ check (the bytes on disk are the bytes gated); it restores the token with `setOriginToken`, fetches once more, runs the base-moved check, the slug-appeared check (a skill or Cursor stub directory with the new slug that landed on main during the gates), the branch-exists check (the head branch is already on the remote with no open pull request; the arm names it and never deletes it), and only then the commit. The scan runs with `SKILL_SECURITY_SCAN_OFFLINE=1` as the CI quality guard does. A faked green scan is the #8203 class, so only the synthetic `skill-security-scan PR gate` and `test` checks are excluded from the create PR; every other synthetic check the helper posts remains synthetic and proves nothing about the create, and the reviewer sees the repository's real checks.

**Token handling and base moved.** Step A runs with the installation token on disk but spawns no script. In Step B the token is stripped from `remote.origin.url` after the first authenticated fetch and before any script spawns, and restored (`setOriginToken`) only for the final fetch and the single `safeCommitAndPr` call; a test asserts `.git/config` carries no `x-access-token` at script-spawn time. The edit loop's token handling is untouched, a recorded known limit. Step B has one time budget, and `deadline` covers the pre-commit phase only, not `safeCommitAndPr` and not the final cleanup. Because a depth-1 clone can be stale and a create must not revert a merged edit, Step B refreshes the clone to the current main before it re-checks and renders; just before the commit it compares the origin/main blob ids of `README.md`, `plugins/soleur/README.md`, `promotion-log.md` and the budget cap file with the ones it used and returns `persist/base-moved` on any difference (blob-scoped, so an unrelated merge does not refuse).

**Description budget (no net growth).** The proposer never trims a sibling description, which would reopen the multi-file class of #8274. The budget is freed beforehand by human-reviewed trims in the preparing commit, and `SKILL_DESCRIPTION_WORD_BUDGET` in `plugins/soleur/test/components.test.ts` is LOWERED to the pre-trim measured total (2436 on 2026-10-26, from 2443), so total model-visible description words stay at or under 2436, enforced by CI at the cap value until a human changes the cap, and the freed 30 words are a reserve. A create is refused unless its description has at least the minimum and at most 30 words and fits in `cap - total`, counted exactly as `components.test.ts` counts (model-visible skills only, ADR-236), failing closed when the cap or a description cannot be parsed. The cap file is outside the six-path set, so the proposer cannot move it. A later human bump of the cap remains possible; a merge-base ratchet lint was cut (CTO ruling, 2026-10-26) because human new-skill pull requests legitimately bump the cap today.

**What this does and does not prove (stated plainly).** "A created skill may not restate or relax an `hr-*` rule" is enforced only by the token and phrase gate (no rule-id tokens, no claim words) plus the human reviewer of the draft pull request. It is not provable deterministically. The unit suite proves the gates are consistent with each other and with this text; it does not prove integrity. The controls are the DRAFT pull request, `mergeMode: "none"`, the LOW-RISK scan and the human reviewer of every draft; the instruction-risk denylist is a tripwire, not a control (a paraphrase evades it). A created skill is model-invocable by default and the arm does not render `disable-model-invocation`; the fixed reviewer checklist asks whether the description would trigger on unrelated prompts, and a reviewer may add `disable-model-invocation: true` by hand before merge. A published skill cannot be recalled from installed copies, so the brand-survival threshold stays `single-user incident`.

**Residuals accepted.** A pattern repeatedly refused for budget or scan writes no ledger row and is retried once headroom frees. The overlap threshold is calibrated on synthesized fixtures and synthetic negatives, not on a production corpus. No skill is created in production by the pull request that adds this arm; a live create is a separate, operator-authorized act.

**C4.** No change: the same Inngest function calls the same external systems (a second call on the existing Anthropic edge and the existing GitHub write path). The skill-count prose in `model.c4` is hand-mirrored by the periodic audit and is not gated.

**Amendment, 2026-10-28 (#10550): a ledger-owned pattern is not offered to the model.** The ledger check in `checkCreate` runs after the single model call, so a pattern the ledger already owned could win that call and end the run `no_action` while the other patterns were never evaluated (live-fire 2026-10-28: one owned of seven). The gate-list clause above carries the new order; it is folded into the `same-run` stage phrase, so `CREATE_STAGE_ORDER` has no id of its own for it and the behaviour tests, not the parity suite, pin its position. Pre-filtered hashes are not counted in `ledger_suppressed`, which still counts clusters dropped. The filter removes patterns and adds no text to the prompt, so it does not reopen ADR-300's rejected "tell the model which clusters were rejected" alternative (PR-derived text in a prompt is an injection path). An empty offer ends the step before the clone check and the open-create lookup. The effect on whether a create PR opens is unmeasured until a live-fire.
