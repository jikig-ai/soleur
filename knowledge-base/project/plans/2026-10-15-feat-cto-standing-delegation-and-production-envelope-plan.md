---
title: "feat: CTO-owned autonomy tooling - Standing Delegation, Production Envelope, overlap preflight, go hold routing"
type: feat
date: 2026-10-15
slug: cto-standing-delegation-and-production-envelope
branch: feat-one-shot-cto-standing-delegation-envelope
issue: 10333
closes: []
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: CTO-owned autonomy tooling - Standing Delegation, Production Envelope, overlap preflight, go hold routing

> **Review-fix round supersedes parts of this plan (2026-10-15).** This file records what was planned; the shipped behaviour is
> ADR-288 and `decision-challenges.md` rows RF-R1 to RF-R4 (Ruled by CTO agent, 2026-10-15). Where a passage below disagrees,
> the ADR wins. Superseded: (R1) `Gate: command` and `Gate: run-green` are deferred, the grammar is `pr-merged` and
> `no-inflight-run` only; (R2) the pre-ask hook delegation arm (Phase 5, Guard 3, FR5) was removed and the hook restored to
> `origin/main`; (R3) the ship gate enforces execution receipts for rows carrying `ran <ISO>`; (R4) the overlap preflight stays,
> hardened, without the `--issue` signal. Verifier decisions V1 to V5: a closed command allowlist, scope and epic binding, the
> envelope read from git HEAD (never the working tree), and `--audit` requires `--at <ISO>`; `--self-check` and `keywords` are
> deleted and the Excluded paragraph is a fixed sentence. The amended rule names the closed command set (merge, ready, dispatch,
> PR creation for a revert).

## Enhancement Summary

**Deepened on:** 2026-10-15
**Sections enhanced:** Phase 2 (verifier), Phase 3 (hold evaluator), Phase 5 (hook), Phase 6 (preflight), Phase 7 (agent selector), Guard Contract, Acceptance Criteria
**Research and review inputs:** CTO rulings T1-T7, C1, C2; scoped advisor consult (ADR-083); CPO plan-time sign-off; plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CTO devex lens); deepen halts 4.6-4.12 run mechanically; live GitHub and baseline-gate probes below.

### Key Improvements

1. The verifier gained a `render` subcommand (the real owner of "the skill writes the record"), an `--audit` mode (a legitimate past act must not fail its own audit row after the epic closes), a committed-envelope requirement, a closed non-delegable command denylist, epic-issue binding and a bounded retry that is never converted into a pass.
2. The overlap preflight gained a graduated exit table: only a duplicate or a designated vehicle stops a merge; shared files alone are informational (exit 13), so routine hot files and this branch's own overlap with #9745 and #7390 never stall unrelated work. The 100-file field cap on `gh pr list` is handled by a paginated re-read that fails to exit 2.
3. The CTO agent gained an interface selector keyed on what existing callers actually send (a question plus "Do NOT use AskUserQuestion"), so the five existing spawn surfaces keep their shape.
4. The CPO conditions made the confirmation name the delegated acts, embed the exact question as the quote, widen the jargon test to every user-facing string, add an in-session stall sentence, a stop path and a per-act epic comment.
5. Nine review items that revisit CTO rulings or the brief's scope are persisted as `taste` / `operator (scope)` rows (R1-R9 in `decision-challenges.md`), not silently applied.

### New Considerations Discovered

- The live canonical delegation predates `Confirmation:` and keeps its envelope inline, so it verifies `invalid`; it is re-recorded at first use through `render` (an operator-confirmed act, outside this PR's ACs).
- The hook arm is repo-local; Soleur users elsewhere get the verifier, the gate and the hold evaluator, not that backstop.
- A hook-written receipt of the operator's answer is the cheapest strict route if shared-identity self-authorization is ever observed (follow-up issue 3).

### Pinned live facts (resolved in this pass, not from memory)

```text
$ gh api repos/jikig-ai/soleur/issues/comments/6188015049 --jq '{type:.user.type, login:.user.login, assoc:.author_association, created:.created_at, updated:.updated_at, issue_url:.issue_url, app:.performed_via_github_app}'
{"app":null,"assoc":"MEMBER","created":"2026-10-15T08:37:44Z","issue_url":"https://api.github.com/repos/jikig-ai/soleur/issues/9757","login":"deruelle","type":"User","updated":"2026-10-15T08:37:44Z"}
$ gh api repos/jikig-ai/soleur/collaborators/deruelle/permission --jq .permission
admin
$ gh pr list --state open -L 2 --json number,files,commits --jq '.[0]|keys'
["commits","files","number"]
$ jq --version; jq -n '"2026-10-15T23:59:59Z"|fromdateiso8601'; jq -n '"2026-10-15"|fromdateiso8601'
jq-1.8.2
1792108799
jq: error ... date "2026-10-15" does not match format "%Y-%m-%dT%H:%M:%SZ"
```

Baselines green before any edit (so a later red is this PR's): `lint-skill-body-budget.py --base origin/main` OK (ship 183 B, one-shot 1150 B of headroom), `lint-rule-bodies.py --check` OK, `go-routing-table-parity.test.sh` 42 passed, `sync-cursor-name-map.ts --check` ok. Deepen halts: User-Brand Impact present (`single-user incident`), Observability present with an allowlisted-verb, shell-inert, offline probe, no PAT-shaped variable, no UI-surface file, no `.tf`/migration/cloud-init file (Encryption Posture not triggered), `lint-guard-contract.py` green over 6 guards, one unfenced Scope Check with zero `unmapped` rows, every cited rule id resolves to an active rule, every prescribed label exists (`domain/engineering`, `action-required`, `priority/p2-medium`, `priority/p3-low`, `type/chore`).

References, not closures: `Ref #10333` (only its collision-pre-check bullet is built here; the bounded-default lead-gate bullets stay open), `Ref #9757` (the epic whose delegation record is the canonical example). The PR body must NOT carry `Closes`.

## Overview

The founder said (2026-10-15, verbatim, recorded in the epic's delegation record): "the CTO should own the decision and be able to proceed autonomously to complete the arc/epic, please also improve our workflow and skills to that effect as Soleur users aren't technical so they wouldn't know what to do anyway. Let's also see if the CTO skill should be improved or new skills created under the CTO so the process is higher quality and autonomous".

Ruled by CTO agent, 2026-10-15: build four things now, in ONE PR, and nothing else. Production-mutating stays on the operator-only list as a CATEGORY but becomes satisfiable by a recorded Standing Delegation (an epic-issue comment, first line `<!-- soleur-delegation v1 -->`, authored by a repo admin, verbatim operator quote, act classes, exclusions, expiry = epic closed or 30 days, revocation = delete the comment) plus a CTO-authored `## Production Envelope` (exact command, blast radius, machine-checkable preconditions, verification commands, abort and rollback, stop conditions; the executed command is byte-identical to the envelope's). The design point: Soleur users are non-technical, so after ONE plain-language outcome confirmation at epic start, every technical or production-safety decision is the CTO's, executed inside a recorded envelope with automated gates. Sessions with no recorded delegation behave exactly as today.

Not built here (ruled): the production-change skill (separate follow-up issue, filed by this PR) and any epic-driver skill (rejected; its hold-as-gate and checklist conventions live in the CTO agent's "Own the epic" interface).

What ships:

1. `plugins/soleur/agents/engineering/cto.md` rewritten with a **Rule** interface and an **Own the epic** interface (frontmatter description byte-identical, T6).
2. `plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh` (+ test), wired into one-shot's collision gate and ship's merge-arming step (not review).
3. `soleur:go` hold routing in `plugins/soleur/commands/go.md`, outside the eval-gated block (T5), with holds becoming `Gate:` predicates that ship Phase 6 evaluates via a new `hold-gate-eval.sh` (T4), fail closed.
4. Doctrine and enforcement: the `hr-menu-option-ack-not-prod-write-auth` amendment, `technical-ruling-delegation.md` section 1/3/7 edits, a delegation arm in `technical-ruling-gate.sh`, a delegation-deny arm in `pre-ask-technical-fork-gate.sh`, one shared verifier `delegation-verify.sh`, one format reference `standing-delegation.md` (T7), ADR, compound learning. `prod-write-defer-gate.sh` and `guardrails.sh` stay byte-unchanged.

## Research Insights

### Premise Validation (Phase 0.6)

- `#10333` is OPEN; its body is a workflow issue about the bounded default lead gate, with ONE bullet ("Plan and review preflight: `gh pr list --state open --search <issue number>`") that matches this ask. The brief narrows it (one-shot and ship arming, NOT review), so this PR is `Ref`, never `Closes`.
- `#9757` is OPEN and its delegation comment exists (author `deruelle`, marker on line 1, verbatim quote, three numbered Scope items, Excluded list, Envelope for act 1, `Expiry:` 2026-11-14 = created + 30 d, `Revoke:`). It is used as the SHAPE for synthesized fixtures only; no test embeds its URL.
- Cited paths exist on `origin/main`: `cto.md`, `technical-ruling-delegation.md` (sections 1, 3, 6, 7), `technical-ruling-gate.sh`, `pre-ask-technical-fork-gate.sh`, `commands/go.md` (the "go skill source of truth": `skills/go/SKILL.md` is a Devin shim that declares `commands/go.md` the AUTHORITY), `plugins/soleur/cursor/agents/soleur-engineering-cto.md`.
- Mirrors: `agents.manifest.json`, `.grok/agents/soleur-engineering-cto.md` and the cursor stub embed the agent DESCRIPTION. T6 keeps it byte-identical, so none regenerates; AC proves it with the two `--check` generators.
- ADR corpus grep (`technical-ruling`, `hr-menu-option-ack-not-prod-write-auth`, `delegation`): ADR-084 owns the decision-class taxonomy; no ADR rejects a standing authorization record. The new ADR extends ADR-084 and does not supersede it.
- Hidden constraints found by reading the enforcers (not in the brief): the ship SKILL.md body ceiling has 183 bytes of headroom and one-shot's 1150 (`plugins/soleur/test/skill-body-budget.json`, ratchets down only); hard-rule body edits need `lint-rule-bodies.py --write` plus an append-only ack row; `B_ALWAYS` is 44069 against a 46000 critical line; new test suites need shard-manifest and duration rows; `commands/go.md` carries an eval-gated routing block.
- Live overlap (dogfooding the feature): open PR #9745 edits `plugins/soleur/commands/go.md` and `help.md`; open WIP PR #7390 edits `AGENTS.rules.md`. Neither is the same work. Rebase risk only; the preflight output for this branch must list both.

### Property List and Cut List (Phase 0.6b)

Properties the ask buys:

- P1 An autonomous agent can run a production act only if the operator's own recorded words cover it and a CTO-authored envelope shows that exact command.
- P2 Revoking (deleting or editing the comment), expiring, or closing the epic stops the autonomy with no code change.
- P3 Any state the machinery cannot evaluate leaves the old behaviour (hold stands, question is asked, gate fails).
- P4 A non-technical user is asked once, in plain language, and never a technical question.
- P5 Two sessions never both carry the same change; the CTO-designated vehicle wins and a skill never edits another session's PR.
- P6 The CTO agent returns a binding ruling in a fixed shape, and owns the epic through a checklist whose items close only on verified evidence.

Mechanism cuts (mechanism -> property -> what already covers it):

- A new `epic-driver` skill -> P6 -> cut by the ruling; the "Own the epic" interface covers it.
- A new `production-change` skill -> P1 -> cut by the ruling (follow-up issue).
- A local pinned copy of the delegation -> P2 -> cut by T1 (cannot see revocation).
- An act-class label trusted without a byte match -> P1 -> cut by T3.
- A new PreToolUse hook to enforce byte-identical execution -> P1 -> cut: `prod-write-defer-gate.sh` and `guardrails.sh` are ruled unchanged; byte identity is enforced by the verifier call the CTO makes immediately before executing and audited at ship by the gate row. Residual stated below.
- A new routing-table row in the eval-gated go block -> P3/P4 -> cut by T5 (a paragraph outside the block).
- Regenerating three agent mirrors -> n/a -> cut by T6.
- Capability grep result: no existing script parses a delegation, evaluates `Gate:` lines or compares open PRs by patch (`grep -rn "soleur-delegation\|Gate:" plugins/soleur .claude/hooks scripts` returns only this plan family), so the three scripts are new rather than a duplicate.

### Institutional learnings applied

- `workflow-patterns/2026-10-14-a-briefs-own-wording-was-the-fourth-carrier-of-the-technical-fork-rule.md` - "ask the operator" in a brief is the trigger to spawn the CTO; enumerate every carrier before strengthening an enforcer (drives T5: the hold paragraph matches the literal tokens, and a miss is safe).
- `2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md` - a menu letter is not authorization; the amended rule keeps "show the exact command" and "menu acks do NOT extend".
- `2026-10-04-an-allow-list-of-line-shapes-is-not-a-closed-sequence-and-a-text-matching-hook-stops-delegated-agents-silently.md` - `prod-write-defer-gate.sh` matches command text; acts it recognises (terraform apply, git push main, doppler writes, operator-ack scripts) STILL defer to the harness approval, and a delegation does not bypass that. The delegation therefore covers acts such as `gh pr merge`, `gh workflow run`, revert PRs; hook-gated forms stay per-command. Stated in `standing-delegation.md`.
- `2026-10-13-a-classifier-that-reads-absent-as-skip-fails-open-on-name-drift.md`, `2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md` - absent or unparseable reads as IN DOUBT, and every verdict line says what was and was not examined.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`, `2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of.md` - the Guard Contract below is derived from the design before the scripts exist.
- `2026-09-25-gh-stub-must-mirror-real-cli-flags.md` - the `gh` stubs in the three new suites reject flags the real CLI lacks.
- `2026-04-18-agents-md-byte-budget-and-why-compression.md` - the rule edit moves detail to the reference and keeps the line under ~600 bytes.
- `2026-06-29-eval-gate-target-validity-and-three-map-drift.md` - the go routing block must stay byte-identical so the gate is a no-op; the test pins it against the merge base.

## Open Code-Review Overlap

None. (Queried `gh issue list --label code-review --state open` against `cto.md`, `technical-ruling-delegation.md`, `technical-ruling-gate.sh`, `pre-ask-technical-fork-gate.sh`, `commands/go.md`, `AGENTS.rules.md`, `ship/SKILL.md`, `one-shot/SKILL.md`: no body names any of them.)

## Research Reconciliation - Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "Change plugins/soleur/commands/go.md or the go skill source of truth (find it)" | `skills/go/SKILL.md` is a Devin entry shim; its body says the AUTHORITY is `commands/go.md`. | Edit `commands/go.md` only. |
| "the routing block is eval-gated, follow eval-gate rules" | `gated-skills.json` registers `go-routing`; an edit INSIDE the markers triggers the promptfoo gate; text outside does not. | T5: new paragraph outside the markers; `go-routing-table-parity.test.sh` plus a new base-anchored block-hash row keep it honest. |
| "Keep description within the skill/agent description budget" | Agent descriptions total 2772 words vs a ~2500 target; no enforcing test; skill budget (`SKILL_DESCRIPTION_WORD_BUDGET`) is skills only. | T6: description byte-identical, zero added words. |
| "check whether the cursor agent stub and any other generated mirror must be regenerated" | The stub, the manifest and the `.grok` stub embed the description only. | None regenerate; AC runs `sync-grok-agent-compat.ts --check` and `sync-cursor-name-map.ts --check`. |
| "evaluated by ship Phase 6" | Phase 6 step 5 already evaluates `## Operator Holds` in PROSE and says an unevaluable hold STANDS. | T4: keep that semantics, make it mechanical via `hold-gate-eval.sh`; the prose path remains the no-delegation behaviour. |
| "Wire it into ... ship's merge-arming step" | The arm is Phase 6.5 `### CI Status Check`, just before `gh pr merge --squash --auto`, inside the `merge-main` lock block. | Insert the preflight call immediately before the lock block; detail in a ship reference because of the 183-byte ceiling headroom. |
| "hr rule: single line, within the byte budget" | Rule line is 402 bytes; per-rule cap ~600; total `B_ALWAYS` 44069 (warn >=44000, critical >=46000). | Draft line is 586 bytes (+184); total becomes ~44253, still under critical. |

## User-Brand Impact

- **If this lands broken, the user experiences:** an agent merging a pull request or dispatching a workflow on their repository that they never authorized (a false-valid delegation), or the opposite - an autonomous epic that stalls with no plain-language message because a gate cannot evaluate and says nothing.
- **If this leaks, the user's workflow is exposed via:** the delegation comment itself (verbatim operator words and the act list sit in a public issue on a public repo) and PR titles echoed by the overlap preflight (attacker-authored text on a public repo); titles are shown as data, never placed in a question option or a command.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one unauthorized production act on one user's repository ends trust in "the CTO owns it", which is the product claim; `aggregate pattern` would under-weight a single wrong merge.

`requires_cpo_signoff: true` (CPO reviews at plan time, below); `soleur:engineering:review:user-impact-reviewer` runs at review.

## Architecture Decision (ADR/C4)

Detection fires: the plan makes a trust-boundary change (a new authorization path for an operator-only category) and extends ADR-084.

### ADR

Create via `soleur:architecture`: **ADR-288 "Standing delegation and production envelope"** (ordinal provisional; ship's ADR-Ordinal Collision Gate re-verifies against `origin/main`, and on a renumber sweep `grep -rn 'ADR-288' knowledge-base/project/{plans,specs}/feat-one-shot-cto-standing-delegation-envelope/`). Decision: production-mutating authorization is satisfiable by a verified Standing Delegation plus a CTO Production Envelope; alternatives considered: (a) keep per-command operator go-ahead only (rejected: non-technical users cannot judge a command; stalls every epic), (b) a pinned local delegation file (rejected: cannot see revocation), (c) trust an act-class label (rejected: self-attestation), (d) a dedicated epic-driver or production-change skill (rejected/deferred by ruling), (e) a PreToolUse hook that enforces byte-identical execution (rejected: `prod-write-defer-gate.sh` and `guardrails.sh` ruled unchanged; residual stated). (f) a `delegated-exec.sh` wrapper that verifies and runs in one step (rejected, CTO ruling C1: it hides the inner command from the unchanged text-matching guards `prod-write-defer-gate.sh` and `guardrails.sh` and is an execution surface itself); (g) a GitHub App identity or web-UI posting for the delegation comment (rejected, CTO ruling C2: no App identity exists for local-session comment writes and users are non-technical). Consequences and residuals, each stated in the ADR in one sentence: the delegation is posted through the same `gh` identity, so the `Confirmation:` line, the 40-character quote, the 30-day cap and edit-as-revocation are tamper-evidence and an audit trail, NOT prevention - a same-identity agent can still forge one; byte-identical execution depends on the CTO running the line the verifier printed (a receipt-checking PreToolUse hook that keeps the guards seeing the real command text is the stricter future direction, tracked as a follow-up issue); acts matched by `prod-write-defer-gate.sh` still defer to the harness prompt. What would flip the identity ruling: an App identity usable for local-session writes, one observed self-authorization, or a hook-written receipt of the operator's answer to the confirmation question that the comment must cite (architecture finding 1 - the cheapest strict route). The ADR also records: the hook arm is repo-local; `updated_at` behaviour from the throwaway-comment probe; and an `Amended by ADR-288` pointer is added to ADR-084 (whose closed operator-only list this extends) with an AC that greps every carrier of the production-mutating authorization wording - `hr-technical-fork-is-not-an-operator-question` is left byte-unchanged because it says "category".

### C4 views

All three of `model.c4`, `views.c4`, `spec.c4` were read. Actors/systems/relationships checked: external human actor - `founder` (already modeled; it records the delegation, no new actor); external system - `github` (already modeled; the verifier and ship gates read issue comments and PR lists through it); containers - `platform.engine.hooks` (Hook Engine) and `platform.plugin.cto` / `ship` / `go` components (already modeled); access relationship that changes - a hook now makes a READ-ONLY call to GitHub, which is new for the hooks container (its description says it "sends nothing and writes nothing" for the guards). In-scope edits: (1) `cto` component description in `model.c4` gains "technical rulings and epic ownership under a recorded Standing Delegation"; (2) amend the plugin-side `plugin -> github` edge description (the verifier, hold evaluator and overlap preflight read issue comments, runs and open changes through `gh`, read-only) and add `platform.engine.hooks -> github "Reads the epic's Standing Delegation comment to decide a deny; read-only, 5 s cap, any failure allows the question (ADR-288)" { technology "GitHub REST (gh api)" }` and confirm both endpoints are already in the `containers` view include list (add to `views.c4` only if the render test says the edge is dropped); (3) the Hook Engine description gets one sentence on the delegation arm. Run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (no skill or agent is added, so the counts "103 skills" / "67 agents" must NOT move).

### Sequencing

The ADR describes the target state and is `status: adopting` until the first real delegated act has run end to end (the #9757 epic); the flip is mechanical and is not a deferral.

## Files to Create

- `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md` - the single format source (T7): delegation record v1 template, `## Production Envelope` template, `Gate:` v1 grammar, the epic-start plain-language confirmation wording, the non-delegable list, residuals.
- `plugins/soleur/scripts/delegation-verify.sh` and `plugins/soleur/scripts/delegation-verify.test.sh` - the shared verifier (T1-T3); test auto-registers under the `plugins/soleur/scripts/*.test.sh` glob.
- `plugins/soleur/skills/ship/scripts/hold-gate-eval.sh` and `plugins/soleur/test/hold-gate-eval.test.sh` (T4).
- `plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh` and `plugins/soleur/test/pr-overlap-preflight.test.sh`.
- `plugins/soleur/skills/ship/references/operator-holds.md` and `plugins/soleur/skills/ship/references/pr-overlap.md` - carry the long procedure so `ship/SKILL.md` grows by pointers only (byte ceiling).
- `plugins/soleur/test/go-hold-routing.test.sh` - hold paragraph present with both tokens and fail-closed wording; `go-routing` block byte-identical to the merge base.
- `plugins/soleur/test/fixtures/standing-delegation/` - synthesized delegation comments (valid, edited, expired, non-admin, no-marker, bot author, too-long expiry, foreign repo), envelopes (valid, no rollback, wrong delegation, two sections), plan files with `## Operator Holds`, and canned `gh` JSON. No live URL anywhere.
- `knowledge-base/engineering/architecture/decisions/ADR-288-standing-delegation-and-production-envelope.md` (via `soleur:architecture`).
- `knowledge-base/project/learnings/workflow-patterns/2026-10-15-the-founder-said-the-cto-owns-the-decision-and-soleur-users-are-not-technical.md` (compound learning recording the instruction and the design answer).
- `knowledge-base/project/specs/feat-one-shot-cto-standing-delegation-envelope/{decision-challenges.md,tasks.md}` (the former is already written by this phase).
- Three follow-up GitHub issues filed at ship (each with milestone from `knowledge-base/product/roadmap.md`, a re-evaluation criterion and `Ref #9757`): (1) "production-change skill under the CTO" (deferred by the 2026-10-15 ruling; criterion: first delegated act has run end to end under ADR-288); (2) "delegated-act digest in soleur:operator-digest" (CPO condition 5; criterion: two delegated epics have closed); (3) "receipt-checking PreToolUse hook so execution, not the question, is the authorization point" (CTO ruling C1 flip direction; criterion: one observed run of a line that differed from the verified one, or the next hook-surface slice).

## Files to Edit

- `plugins/soleur/agents/engineering/cto.md` - body rewrite; frontmatter byte-identical.
- `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md` - section 1 (production-mutating satisfiable by delegation+envelope; non-delegable list), section 3 (brief template becomes a pointer to the agent's Rule interface), section 6 (the gate's new row shape), section 7 canonical example (add an `Authorized by delegation` row the suite feeds to the gate).
- `plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh` and `plugins/soleur/test/technical-ruling-gate.test.sh` (+ fixtures dir `plugins/soleur/test/fixtures/technical-ruling-gate/`).
- `.claude/hooks/pre-ask-technical-fork-gate.sh` and `.claude/hooks/pre-ask-technical-fork-gate.test.sh`; `.claude/hooks/README.md` if it lists per-arm behaviour.
- `plugins/soleur/commands/go.md` - one paragraph outside the eval-gated block.
- `plugins/soleur/skills/ship/SKILL.md` - at most +183 net bytes: a pointer in Phase 6 step 5 (Operator Holds) and a pointer before the `merge-main` lock block in Phase 6.5; move or compress existing adjacent prose into the new references to make room. `plugins/soleur/skills/ship/references/decision-challenges-render.md` - one line on the delegation row.
- `plugins/soleur/skills/one-shot/SKILL.md` - at most +1150 net bytes in Step 0a.5: the preflight call and the CTO-designates-the-vehicle rule.
- `AGENTS.rules.md` (rule `hr-menu-option-ack-not-prod-write-auth`), `.claude/rule-body-hashes.txt` (regenerated by `python3 scripts/lint-rule-bodies.py --write`), `.claude/rule-weakening-acks.txt` (append one ack row).
- `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` (via `python3 scripts/regenerate-shard-manifest.py --incremental --write`).
- `knowledge-base/engineering/architecture/diagrams/model.c4` (and `views.c4` only if the render test requires).
- Deliberately NOT edited: `.claude/hooks/prod-write-defer-gate.sh`, `.claude/hooks/guardrails.sh`, `plugins/soleur/agents/engineering/cto.md` frontmatter, `agents.manifest.json`, `.grok/agents/soleur-engineering-cto.md`, `plugins/soleur/cursor/agents/soleur-engineering-cto.md`, the `go-routing` block, `plugins/soleur/skills/review/SKILL.md`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Rewrite plugins/soleur/agents/engineering/cto.md: add a 'Rule' interface (binding four-heading output Decision/Rationale/Rejected alternatives/Dissent, stricter-default when evidence is thin, evidence bar, no menus, headless-run contract)" | Phase 7, `cto.md` | mapped |
| 2 | "an 'Own the epic' interface (Standing Delegation record, Production Envelope authoring, machine-checkable Gate: predicates for holds, tick checklist items, close an epic only on the last verified item)" | Phase 7, `cto.md` + `standing-delegation.md` | mapped |
| 3 | "Point plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md section 3's brief template at the agent instead of restating it." | Phase 7 | mapped |
| 4 | "Also check whether plugins/soleur/cursor/agents/soleur-engineering-cto.md and any other generated mirror must be regenerated." | Phase 7 + AC (no regeneration; `--check` proves it) | mapped |
| 5 | "Add plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh (+ test)" | Phase 6 | mapped |
| 6 | "the vehicle already designated by a CTO ruling wins and the other carves out; a skill never edits another session's PR" | Phase 6 verdict table | mapped |
| 7 | "Wire it into the existing collision gate at the start of one-shot and into ship's merge-arming step (NOT review)." | Phase 6 wiring | mapped |
| 8 | "Output must be plain-language for non-technical users." | Phase 6 output contract + jargon test | mapped |
| 9 | "soleur:go hold routing: a resume/handoff brief containing 'HOLDS' or 'ask the operator' routes the holds to the CTO and a delegation record" | Phase 8 | mapped |
| 10 | "with a recorded Standing Delegation the holds become automated Gate: predicates evaluated by ship Phase 6 (fail closed: a hold whose predicate or delegation cannot be evaluated still stands); without one, current behaviour (ask once, name the action)" | Phase 3 `hold-gate-eval.sh` + Phase 8 + ship pointer | mapped |
| 11 | "amend hr-menu-option-ack-not-prod-write-auth in AGENTS.rules.md (keep id and compliance-tier tag, single line, within the byte budget ...)" | Phase 9 | mapped |
| 12 | "Update technical-ruling-delegation.md section 1 (production-mutating stays an operator-only category but is satisfiable by delegation+envelope; non-delegable list ...)" | Phase 7 | mapped |
| 13 | "Update plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh to accept an 'operator (production-mutating)' row whose ruling is 'Authorized by delegation <comment url>, envelope <path>' (still requires the row; fail closed if the link is unreadable)" | Phase 4 | mapped |
| 14 | ".claude/hooks/pre-ask-technical-fork-gate.sh to deny an AskUserQuestion asking authorization for an act covered by a valid delegation; add tests for each; leave prod-write-defer-gate.sh and guardrails.sh unchanged" | Phase 5 + AC | mapped; SUPERSEDED by R2 (arm removed) |
| 15 | "Write an ADR via soleur:architecture ('Standing delegation and production envelope') and a compound learning recording the founder's instruction." | Phase 10 | mapped |
| 16 | "this PR touches plugins/soleur/** so it must NOT be merged while the registry host replace workflow (registry-host-replace-dispatch) is running; end at a green, ready PR and check for an in-flight replace run before arming merge" | `## Operator Holds` + ship | mapped |
| 17 | "the operator confirms once in plain language (a legitimate AskUserQuestion), the skill writes the record; everything technical after is the CTO's" | Phase 1 items 4-5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `cto.md` rewrite | asks 1-2 | asked |
| `technical-ruling-delegation.md` edits | "Update technical-ruling-delegation.md section 1" and "Point ... section 3's brief template at the agent" | asked |
| `pr-overlap-preflight.sh` + test + wiring | asks 5-8 | asked |
| `commands/go.md` paragraph + `go-hold-routing.test.sh` | "Change plugins/soleur/commands/go.md ... and its tests" | asked |
| `technical-ruling-gate.sh` / hook edits + tests | asks 13-14 | asked |
| `AGENTS.rules.md` + manifest + ack | ask 11 | asked (manifest and ack rows are the enforcement contract of `lint-rule-bodies.py`: the gate fails without them) |
| ADR, learning, C4 edit | ask 15 | asked (C4 edit: plan Phase 2.10 mandates the model update as a deliverable of the same plan) |
| `delegation-verify.sh` | "fail closed if the link is unreadable" and "deny an AskUserQuestion asking authorization for an act covered by a valid delegation" | inferred - justification: the gate, the hook and the pre-execution check each need the same validity decision; three copies would drift (CTO ruling T1/T3 chose one shared verifier) |
| `hold-gate-eval.sh` | "the holds become automated Gate: predicates evaluated by ship Phase 6" | inferred - justification: an automated predicate needs an executable evaluator; prose re-evaluation by the model is the failure mode the holds exist to prevent (CTO ruling T4) |
| `standing-delegation.md` | "Standing Delegation record, Production Envelope authoring, machine-checkable Gate: predicates" | inferred - justification: the format must live in one place the verifier, gate and agent cite, and `agents/` may hold only agent definitions (#8317; CTO ruling T7) |
| `ship/references/operator-holds.md`, `pr-overlap.md` | "Wire it into ... ship's merge-arming step" | inferred - justification: `ship/SKILL.md` has 183 bytes of headroom under a ratcheting ceiling, so the procedure must live in references |
| `scripts/suite-shard-legs.tsv` / `suite-durations.tsv` rows | "add tests for each" | inferred - justification: `test-all-weight-drift` and the shard totality check fail for an unregistered suite |
| Follow-up issue for the production-change skill | "separate follow-up issue for production-change" | asked |
| Two further follow-up issues (digest, receipt-checking hook) | "Let's also see if the CTO skill should be improved or new skills created under the CTO" | inferred - justification: the CPO condition and the CTO flip direction would otherwise be untracked deferrals (`wg-defer-only-after-inline-triage` requires a tracking issue) |
| `Confirmation:` line, 40-character quote, execution log and stop path | "after the one plain-language outcome confirmation at epic start, every technical or production-safety decision is the CTO's" | inferred - justification: CPO conditions 1-2 and 4-5 and CTO ruling C2 make the confirmation auditable and the autonomy stoppable by a non-technical operator |

### Split Assessment

- Subsystems touched: 5 - `plugins/soleur`, `.claude`, `knowledge-base`, `scripts`, `AGENTS.rules.md` (root file)
- Planned files: ~36 | Estimated changed lines: ~2600 (about 1500 are tests and fixtures)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the brief says "in ONE PR" and the CTO ruling made the four items interdependent (the gate, hook and hold evaluator all call the one verifier, and the rule text points at the reference). If a split is ever forced the seams are: A verifier + gate + hook + doctrine, B overlap preflight, C cto.md + go routing.

## Implementation Phases

Order is test-first (`cq-write-failing-tests-before`): in every phase the suite and its fixtures are written and shown RED before the script exists. Each script uses `set -uo pipefail`, no `sed -i`, bash 3.2 and mawk portable, fixtures synthesized, writes only under `mktemp -d`, and prints a plain-language reason on stderr with a machine token on stdout.

### Phase 1 - The format reference (`standing-delegation.md`)

1. Delegation record v1: line 1 exactly `<!-- soleur-delegation v1 -->`; `## Standing delegation - epic #<N> (recorded <date>)`; a blockquote (lines starting with `>`) under "Operator instruction, verbatim" (the exact question text the operator was shown plus their answer; >= 40 characters); a `**Confirmation:**` line carrying the operator's answer text (option label or free-text reply) exactly as the calling skill received it; numbered `**Scope**` items (each an act class; an item that names an exact command embeds it in backticks); `**Excluded (still operator-only):**` list that MUST mention all of: user-data loss or sole-copy destruction, money, legal-risk, brand, scope, force-push to main, bypassing required checks or rulesets, editing this delegation, credential rotation that can lock users out, third-party or tenant systems, any act whose rollback is not named; `**Expiry:**` line carrying an ISO date no later than created_at + 30 days (the epic closing also ends it); `**Revoke:**` "delete or edit this comment". Editing is treated as revocation (verifier: `updated_at` must equal `created_at`); the operator re-records instead.
2. `## Production Envelope` template (lines, in the section): `Delegation: <comment url>`, `Scope item: <n>`, `Command:` + one fenced block (one command per line), `Blast radius:`, `Preconditions:` with one or more `Gate:` lines, `Verification:` commands (against telemetry, not eyeballing), `Abort:`, `Rollback:` (named, tested; text `none`/`n/a`/`unknown` fails), `Stop conditions:`. A file may hold several envelope sections; each heading may carry a hyphen and a title suffix and is addressed `path#<title substring>`; more than one section with no anchor is `parse-ambiguous`.
3. `Gate:` v1 grammar, one predicate per line, closed set: `Gate: pr-merged <N>`, `Gate: no-inflight-run <workflow-file>`, ~~`Gate: run-green <workflow-file> <sha>`, `Gate: command <repo-relative script and args> => <literal expected output>`~~ (SUPERSEDED by R1: both deferred; the first real consumer re-adds them, only by CTO ruling). Adding a kind is a CTO ruling plus a test row.
4. The epic-start confirmation, in plain language (a legitimate AskUserQuestion issued by the CALLING skill - the CTO agent is headless and never asks): outcome in business terms in at most three sentences, then the delegated acts named in plain words ("merge and release changes to your live product, and undo them if something goes wrong"), then the promise: "I will only come back to you for money, what is in or out of scope, how it looks or reads, legal exposure, anything that could lose your customers' data, or anything I am not allowed to do for you. You can tell me to stop at any time. Is that OK?" Yes writes the record; the blockquote under "Operator instruction, verbatim" is the EXACT question text shown plus the answer the operator gave (so a bare "Yes" is never the whole quote; the verifier rejects a quote shorter than 40 characters). No keeps today's behaviour (ask once, naming the action, at each operator-class step). CPO conditions 1-2.
5. Executable template (devex finding 7): a test extracts the delegation record and envelope templates from this reference, instantiates them with fixture values and asserts `delegation-verify.sh` returns `valid`, so the document, the verifier and the fixtures cannot drift apart silently.
6. Visibility and stopping (CPO conditions 4-5): after EVERY delegated act the CTO posts one plain sentence on the epic ("Merged <title> under your standing approval; it is live and healthy", or "Rolled back <title> because <plain reason>"); every stall (an unevaluable gate, a hold that stands, an overlap that stops a merge, a non-delegable act) emits one plain in-session sentence to the operator in addition to any issue; a conversational "stop" / "tell me to stop" from the operator makes the agent delete the delegation comment (deleting reduces authority and is allowed; editing it is non-delegable). The plain wording for these messages lives in this reference and is covered by the jargon test below. A delegated-act digest inside `soleur:operator-digest` is a follow-up issue (merged-change titles already reach that digest today).
7. Stall, re-confirm, resume (spec-flow finding 7): when the verifier says `edited`, `expired`, `epic-closed` or the comment is gone, the agent says in one plain sentence what happened, the CTO returns the epic-start wording for the calling skill to ask again, and a Yes re-records through `delegation-verify.sh render` and resumes from the first unticked checklist item. The live comment on the canonical epic predates this verifier: it has no `Confirmation:` line and its envelope is inline in the comment, so it verifies as `invalid` (`no-confirmation`) and must be re-recorded through the loop above at the first use - an operator-confirmed act that is NOT part of this PR's acceptance criteria. Reading it once with `verify` is an informational smoke check of the live JSON shape (Integration Verification), not an AC.
8. Boundaries: acts that `prod-write-defer-gate.sh` recognises still defer to the harness approval prompt; a delegation does not bypass it. The residual that the delegation is posted through the same `gh` identity is mitigated by the verbatim quote, the 30-day cap and edit-as-revocation. Byte-identical execution is checked by the CTO calling the verifier with `--command` immediately before running; the gate row audits it at ship.

### Phase 2 - `delegation-verify.sh` (+ test, RED first)

CLI: `delegation-verify.sh verify --delegation <comment-url> [--envelope <path[#title]>] [--command <line>]... [--audit --at <ISO UTC>]` (SUPERSEDED: a bare `--audit` is a usage error, V5), `delegation-verify.sh render --epic <N> --question-file <f> --answer-file <f> --scope-file <f> --expiry <ISO date>` (prints the delegation comment body from the template to stdout; the calling skill posts it with `gh issue comment <N> --body-file` and reads it straight back through `verify`, and a record that does not verify is deleted and the epic stays on today's behaviour - this is the real owner of 'the skill writes the record', spec-flow finding 1) and ~~`delegation-verify.sh --self-check`~~ (SUPERSEDED: deleted in the review-fix round) (offline; checks `jq`, parses a built-in sample, prints `delegation-verify: ready`). `--command` without `--envelope` is a usage error. stdout: one line `delegation: valid|invalid|unverifiable reason=<token>`; with `--command` and `valid` it also prints `verified-command: <the exact envelope line>` and `verified-sha256: <hex>` so the CTO copies the line byte for byte (CTO ruling C1); stderr: a plain sentence. Exit 0 valid, 1 invalid, 2 unverifiable/usage. Never exit 0 on an unexamined input. Exit 2 always blocks its caller (ship gate, hold evaluator) and is never retried into a pass; the hook alone treats it as 'ask the question'. Portability (these scripts run on users' machines): no bare `timeout` (use the repo's timeout, gtimeout, bare fallback as in `.claude/hooks/git-commit-secret-scan.sh`), no `date -d` / `stat -c` / `sed -i` / `readlink -f` (date arithmetic through jq `fromdateiso8601`; hashing through `sha256sum`, else `shasum -a 256`, else `openssl dgst -sha256`), bash 3.2 and mawk safe.

`--audit` (used only by the ship-time gate; SUPERSEDED in part: the envelope is read from git HEAD, never the working tree (V4), `--audit` needs `--at` and enforces `created <= at <= expiry` (V5), and only `epic-closed` is skipped; spec-flow finding 9, simplicity finding 1, Kieran finding 4) skips the two authorization-time checks `expired` and `epic-closed` - a delegated act that ran legitimately must not fail its own audit row after the epic closes - and keeps every structural and provenance check (including `edited` and `expiry-too-long`); the hook, the hold evaluator and the CTO's pre-execution call never use it, and the gate's archive-lookup mode checks row shape only (no network). Every API call retries once after 2 s on a transport error (never into a pass; a persistent failure is exit 2, the caller says one plain stall sentence and the CTO arms a bounded re-check with Monitor instead of filing an issue for a transient outage). Parsing: one trailing `\r` is stripped per body line (web-UI comments carry CRLF; the `--command` argument stays strict); the `Expiry:` date is read as `<date>T23:59:59Z` UTC and the 30-day cap is compared by calendar date (`jq` `fromdateiso8601` needs the full timestamp). Epic binding (Kieran finding 3): the comment's `issue_url` from `GET /repos/{o}/{r}/issues/comments/{id}` must name the issue number in the URL, and that issue must not be a pull request (`wrong-issue`, `epic-is-pr`). Precondition probe before relying on `updated_at == created_at` (Kieran finding 10): on a throwaway comment on the PR, post, add a reaction, read, delete, and record the observed behaviour in the ADR; `edited` carries a plain re-record message. Checks, each with its own reason token (the suite asserts each): URL shape and same-repo (`bad-url`, `wrong-repo`); comment readable (`comment-unreadable`, `api-error`); marker on line 1 (`no-marker`); author type `User` and login equals repo owner login OR collaborator permission `admin` (`bot-author`, `not-admin-author`; T2); `updated_at == created_at` (`edited`); verbatim quote block of >= 40 characters (`no-quote`, `quote-too-short`); a non-empty `Confirmation:` line (`no-confirmation`); numbered Scope item `n` exists when an envelope is given (`no-scope-item`); Excluded list complete - ten fixed anchor keywords defined in `standing-delegation.md`, each required as a case-insensitive substring (`excluded-incomplete`; Kieran finding 11); ISO Expiry present, not past, <= created + 30 d (`expiry-missing`, `expired`, `expiry-too-long`); epic issue still OPEN (`epic-closed`); envelope file exists, one section selected, Delegation line equals the URL, all parts present, Rollback named (`envelope-missing`, `parse-ambiguous`, `envelope-delegation-mismatch`, `envelope-incomplete`, `rollback-unnamed`); the envelope file is tracked and unmodified at HEAD (`envelope-not-committed` - the verified text is the committed text and the PR-body gate row records its sha256; architecture finding 3); each `--command` first passes a closed non-delegable denylist (`non-delegable-command`: any `git push`, any `--admin`, `gh api` writes to rulesets or branch protection, secret-store writes through `doppler secrets` set or delete, `terraform` or `tofu` apply, destroy or import, `rm -r`, `gh repo delete`, `gh secret`; a text backstop for the Excluded list, spec-flow finding 11) and then equals, byte for byte, a FULL line of the Command block (`command-not-in-envelope`; a prefix, a substring, trailing whitespace or CRLF difference is a mismatch - T3). No test seam in production code (DHH finding 1: an env switch that makes the chokepoint answer `valid` is a forge-a-delegation switch): the suite stubs `gh` on `PATH` with canned JSON and rejects any argv the real CLI would not accept. Network calls cap at 5 s each.

### Phase 3 - `hold-gate-eval.sh` (+ test)

CLI: `hold-gate-eval.sh --plan <plan.md>` evaluates `## Operator Holds`; `hold-gate-eval.sh --file <envelope.md> --section "Production Envelope"` evaluates an envelope's `Preconditions:` gates. One shared gate-line parser serves both modes (the plan's hold section is just a section selector). Plan holds format: optional `Delegation: <url>` and `Envelope: <path>` lines, then items `- Hold: <the operator's words, verbatim>` each followed by indented `Gate:` lines the CTO wrote (architecture finding 6: the operator's wording stays beside the gates so a weakened gate is visible in review; whether a gate faithfully encodes a hold remains the CTO's authoring and review's check - stated in the ADR). A non-blank section that parses to zero `- Hold:` items (legacy prose holds) is exit 2, never exit 0 (Kieran finding 5). Parsing: `=>` splits at its FIRST occurrence with both sides trimmed and the expected side compared after normalising a single trailing newline; script arguments come from the charset `[A-Za-z0-9._/@=:+-]`, are passed as an array and are never `eval`ed; the `command` byte-identity check runs after a fresh `git fetch origin main`, and the probe must be self-contained (it may not source a file the PR edits); `pr-merged` requires state MERGED on the base branch `main` and `git merge-base --is-ancestor <merge sha> HEAD`; `no-inflight-run` makes three separate `gh run list --status` calls (queued, in_progress, waiting) and needs all three empty. Exit 0 every hold discharged (or no holds recorded: section absent/empty is a no-op, as ship step 5 already says); 1 at least one hold STANDS; 2 cannot evaluate (treated as STANDS by the caller); 3 no delegation recorded (the caller keeps today's prose evaluation). When a delegation is cited it is verified through `delegation-verify.sh` first; anything but `valid` leaves every hold standing. A hold with no `Gate:` line stands and is reported "needs a person" (ship routes it to the Undeferred Operator-Step Gate). Predicate rules per T4: `command` scripts are repo-relative, no `..`, no symlink escape, tracked at HEAD and byte-identical to `origin/main` (so a probe cannot ship in the PR that relies on it), 30 s cap, no `ssh`, exact literal compare. Output is one plain, jargon-free line per hold ("Waiting for the earlier change to go live: still waiting"; the hold's own plain sentence is what is printed) plus a final machine line `holds: N discharged: M standing: K`; the same jargon test as the preflight applies to the human lines, and a standing hold also yields one plain in-session sentence from the caller.

### Phase 4 - `technical-ruling-gate.sh` delegation arm (+ tests)

In `check_artifact`, a row whose Class is `operator (production-mutating)` and whose Ruling matches `^Authorized by delegation <comment-url>, envelope <path>$` is validated through `delegation-verify.sh verify --delegation <url> --envelope <path>`: `valid` passes; `invalid` -> `[FAIL] ...: delegation-invalid - <plain reason>` exit 1; `unverifiable` -> exit 2 (could not measure, never a pass). The same shape on any other Class (`operator (money)`, `technical`, `taste`, a bare row) is `bad-ruling-shape`: a delegation can authorize only production-mutating acts. A plain `operator (production-mutating)` row naming an action still passes exactly as today (the row remains required; no row, no pass). New reasons: `delegation-invalid`, `delegation-unverifiable`. `TRG_EXEC_LOG` logs `delegation <idx>` per examined delegation row. Every unfenced table is scanned, as today.

### Phase 5 - `pre-ask-technical-fork-gate.sh` delegation arm (+ tests) - SUPERSEDED (REMOVED by CTO ruling R2)

A new arm, judged per question over the QUESTION TEXT only (never option labels, consistent with the existing arms): cue = the text carries a verb from `AUTHZ_VERB_RE` AND names a delegation comment URL, an envelope path, or the words `Authorized by delegation` (T1). Spans are extracted from the RAW payload (`__HI_RAW`), never from the lowercased, whitespace-squeezed `RULING_ROWS` or `QUESTION_CORPUS` that the cue test uses (Kieran finding 1: byte identity cannot survive the existing normalisation), and a Guard 3 row uses a mixed-case, double-space command. Only then run `delegation-verify.sh verify` with a 5 s cap, passing every backtick-quoted span and every fenced line in the question as `--command`. Span rule (DHH finding 2): spans that do not look like a command (the first word is not one of `gh git terraform tofu doppler bash sh curl kubectl docker npm bun python3 node`) are ignored; the arm denies only when at least one command-shaped span exists, EVERY command-shaped span is a byte-identical full line of the envelope's Command block, and the verifier says `valid` - one uncovered act in the same question keeps the question asked. A mixed-span fixture row pins this. `valid` -> deny with: the act is inside the recorded delegation and envelope, run it yourself byte-identical, do not ask; add the one-line plain wording for the operator-facing log. Anything else (no cue, `invalid`, `unverifiable`, verifier missing, `gh`/`jq` missing, timeout) -> the question proceeds to the existing arms unchanged (announced on stderr when the cue fired but verification did not complete). `SOLEUR_ACK_TECHNICAL_FORK=1` keeps its meaning. An `emit_incident` row records each deny. The hook arm is repo-local (`.claude/settings.json`, not the shipped plugin `hooks.json`), so Soleur users elsewhere receive the verifier, the gate and the hold evaluator but not this backstop - stated in the ADR (architecture finding 9); the hook resolves the verifier at `plugins/soleur/scripts/` from the repo root and the suite proves it. The arm is placed after the expert arm and before the technical-ruling arm; the existing arm order comments are updated.

### Phase 6 - `pr-overlap-preflight.sh` + wiring

CLI: `pr-overlap-preflight.sh [--mode start|merge] [--pr <N>] [--files "<f ...>"] [--issue <N>]... [--vehicle <N>]` (SUPERSEDED: `--issue` is dropped, R4). Defaults: current PR from `gh pr view`, files from `git diff --name-only origin/main...HEAD`, vehicle from `--vehicle <N>` ONLY (DHH finding 5: parsing prose out of a ruling row would feed a merge-stopping exit code from free text; the calling agent reads the CTO ruling and passes the number). It lists OPEN PRs other than the current one (`gh pr list --state open -L 200 --json number,title,url,isDraft,files,commits`; the `files` and `commits` fields are capped at 100 per PR, so a PR that returns 100 of either is re-read with `gh api repos/{o}/{r}/pulls/<N>/files --paginate`, and a failure of that read is exit 2, never clear - Kieran finding 6) that (a) change a file in the set, (b) carry the same edit (per-file `git patch-id --stable` over the other PR's `gh pr diff`, computed only for PRs that share a file, capped at 20 diffs with an explicit "looked at N of M"), or (c) carry a commit with the same subject (ignoring `chore: initialize`, `WIP`, merge commits). Exit: 0 clear; 10 overlap and the designated vehicle is the OTHER change (this one carves out); 11 overlap and THIS change is the vehicle (the others carve out; informational); 12 a duplicate (same edit or same-subject change) with no designated vehicle (the calling agent spawns the CTO to designate one and records the ruling - never an operator question, `hr-technical-fork-is-not-an-operator-question`); 13 shared files only, no vehicle designated (informational: the notice is printed and nothing stops, because a routine shared file such as `AGENTS.rules.md` must not block unrelated work - spec-flow finding 10, simplicity finding 3, Kieran finding 2; this branch's own overlap with #9745 and #7390 is exactly that case); 2 could not check (printed as "I could not check", never "clear"). The script only reads: it never comments on, edits, closes or pushes to another PR (a skill never edits another session's PR).

Output contract (plain language, no jargon - CPO condition 3): the human block names each overlapping change by its quoted title (control characters stripped, 80 characters) and link, with the plain file names and one of "makes the same edit as yours" / "has a change with the same title", then a "What this means" sentence and the single next step; it never prints a change number, SHA or patch id. A separate last line `SOLEUR_OVERLAP exit=<code> prs=<n,n> vehicle=<n|none>` carries the machine detail for the agent (the jargon test excludes that one line). Titles are data: printed, never executed, never placed in an AskUserQuestion option. The suite asserts none of `patch-id`, `SHA`, `HEAD`, `rebase`, `merge-base`, `stdout`, `diff`, `commit`, `draft`, `PR`, `pull request`, `branch`, `unarmed` or a `#<digits>` token (`merge` and `rollback` are not on the list: the CPO-approved confirmation says "merge and release changes" and "undo" replaces rollback; titles are cleaned before printing - control characters stripped, a trailing `(#N)` and the conventional-commit prefix removed, 80 characters - and the test uses a realistic title such as one ending in `(#10188)`) appears in the human block - matched as whole words (uppercase tokens case-sensitively, so ordinary words such as `approach` never trip it) and run ONLY over strings the plan emits (the preflight human block, the hold evaluator human lines, the confirmation/stall/execution-log templates); the ship stall wording is rewritten to avoid `unarmed` (for example "finished but not yet queued to go live"). When the preflight stops a merge (exit 10 or 12) the agent says one plain sentence to the operator in-session (for example "Another open change already covers this work, so I am holding mine back and will not touch theirs").

Hold timing (architecture finding 7, Kieran finding 5): `operator-holds.md` evaluates the holds at the draft exit AND again immediately before arming in Phase 6.5 through the same single pointer the preflight uses - a predicate such as `no-inflight-run` is true only at that instant, and a fixture row pins the re-check. Wiring (headless-safe): `one-shot/SKILL.md` Step 0a.5 gains one paragraph (<= 1150 bytes) running `--mode start` after the existing OPEN-PR probes with the `#N` refs as `--issue`, and again with `--files` at the existing post-planning re-probe; exit 12 makes the calling agent spawn the CTO to designate the vehicle (the script never spawns anything). `ship/SKILL.md` Phase 6.5 runs `--mode merge` immediately before the `merge-main` lock block: 10 and 12 stop arming (finished but not yet queued to go live, naming the change, with the CTO spawned at 12); 11, 13 and 0 continue (13 prints its notice); 2 retries once then continues with the visible notice. `review/SKILL.md` is NOT edited. The procedure text lives in `ship/references/pr-overlap.md`.

### Phase 7 - `cto.md` and `technical-ruling-delegation.md`

`cto.md` body (frontmatter untouched): keep the existing Assess/Recommend/Sharp Edges (it remains the brainstorm/plan domain leader), and add the interface selector (architecture finding 4: existing callers - one-shot's inline copy, `work`, `review`, `plan`, the closing-message gate - send a question plus "Do NOT use AskUserQuestion" and none sends a fixed phrase): a spawn prompt starting `Own the epic` selects the epic interface; a prompt that carries a question, options or the words `Do NOT use AskUserQuestion` or `BINDING` selects **Rule**; anything else (brainstorm and plan domain-assessment prompts) stays Assess/Recommend. `technical-ruling-delegation.md` section 3 keeps ONE line stating the four-heading contract so the `Ruled by CTO agent` row shape has a single visible source, and a test spawns each existing caller's phrase against the selector text. Add:

- **Rule**: binding output with exactly the four headings `Decision:` `Rationale:` `Rejected alternatives:` `Dissent:` (several rows -> one block per `Item <id>:`); ONE option, never a menu; evidence bar (cite file:line or command output; a claim not verified is labeled `unverified` and a ruling that rests on one chooses the STRICTER option and names the evidence that would flip it); never asks (headless: nobody can answer, `Do NOT use AskUserQuestion`); with no `Agent` tool it still rules; a "surface it" or "OPEN DECISION" brief is the trigger, not an exemption; the operator-only list is closed and the ruling splits mixed items; fail-safe default when user data is at stake.
- **Own the epic**: (1) read the epic and find a delegation by its marker; none -> return the business-terms outcome statement and the plain confirmation wording for the caller to ask (the agent never asks); (2) turn every hold into a `Gate:` line; (3) author a `## Production Envelope` per production act, run `delegation-verify.sh verify ... --command`, then `hold-gate-eval.sh --file ... --section "Production Envelope"`, execute the command byte-identical, run the Verification commands, and on a stop condition run Abort/Rollback; (4) tick checklist items only with cited evidence; (5) close the epic only on the last verified item (closing expires the delegation); (6) a non-delegable act or an unevaluable gate -> stop, file one `action-required` issue naming the ACTION (no technical question). The format details are linked from `standing-delegation.md`, not restated.
- Names siblings by registry id (`soleur:legal:clo`), no harness-specific tool tokens that the harness-parity census rejects.

`technical-ruling-delegation.md`: section 1 keeps `production-mutating` in the closed list and adds "satisfiable by a recorded Standing Delegation plus a CTO Production Envelope" with the non-delegable list verbatim from the ruling; section 3 replaces the copied brief block with a short field list (Question, Evidence, Options, Brand-survival threshold, Disqualifying facts) plus "the agent's Rule interface defines the reply shape and the stricter default - do not restate them"; sections 6/7 add the `Authorized by delegation` row shape and one canonical-example row that the suite feeds to the gate in its fixture seam.

### Phase 8 - `commands/go.md` hold routing

Add one paragraph "Hold routing (pre-route)" between Step 1 and the `<!-- eval-gate:block:go-routing:start -->` marker, OUTSIDE the block: if the input is a resume or handoff brief containing the literal `HOLDS` or `ask the operator`, never call AskUserQuestion for a technical hold; spawn `soleur:engineering:cto` in "Own the epic" mode; with a recorded Standing Delegation (found by the marker on the epic) holds are written as `Gate:` lines under `## Operator Holds` and ship Phase 6 evaluates them through `hold-gate-eval.sh` (fail closed: an unevaluable predicate or delegation leaves the hold standing); without one, today's behaviour with one improvement: classify, rule the technical items, then ask the operator the single epic-start confirmation first (spec-flow finding 3 - Yes records the delegation through `delegation-verify.sh render` and the holds become gates; only on No does the operator get one plain question per operator-class item, naming the ACTION), then route normally with the original input. The same paragraph carries the stop trigger: when an active delegation exists and the operator says to stop or take back the standing approval, delete the comment and say so in one plain sentence; the CTO re-runs the verifier immediately before every act so a stop between verification and execution cannot be raced past by more than that instant. The executor of a delegated act is the agent session that holds the envelope (the CTO subagent for epic acts); ship's own auto-merge arming of its PR is not a delegated act and gains no verifier call. `go-hold-routing.test.sh` asserts: both tokens present, the paragraph sits outside the markers, "fail closed" and "ask once" wording present, and the block between the markers hashes equal to `git show $(git merge-base origin/main HEAD):plugins/soleur/commands/go.md` (anchored outside the commit). `go-routing-table-parity.test.sh` and `go-session-gates.test.sh` stay green.

### Phase 9 - Doctrine

Replace the body of `hr-menu-option-ack-not-prod-write-auth` (id and `[compliance-tier]` kept, one line, one `**Why:**` sentence, <= ~600 bytes). Draft (585 bytes before the scope and wording fixes below; re-measure with `wc -c`, cap ~600):

```text
- For destructive writes against shared prod (terraform/tofu/kubectl apply, migrations, deploys), show the exact command, wait for explicit per-command go-ahead, THEN run with `-auto-approve`/`--yes`/`--force` [id: hr-menu-option-ack-not-prod-write-auth] [compliance-tier]. Go-ahead = the operator's, or - for merge, dispatch and revert only, never a hook-gated form - a recorded Standing Delegation (epic comment, repo admin, marker `<!-- soleur-delegation v1 -->`) plus a CTO Production Envelope showing that command, run byte-identical; none = unchanged. Menu acks and prior approvals do NOT extend to new commands. **Why:** #2618; #2880.
```

Then `python3 scripts/lint-rule-bodies.py --write`, append the ack row `hr-menu-option-ack-not-prod-write-auth|<new sha256>|2026-10-15|<PR>|<reason: not a weakening - the per-command go-ahead is unchanged for sessions with no delegation; the second path requires the operator's own recorded words plus an envelope showing the byte-identical command>`, and run the four AGENTS lints (below). `cq-agents-md-tier-gate`: the rule keeps only the invariant; the record format and envelope live in `standing-delegation.md`.

### Phase 10 - ADR, C4, learning, manifests

`soleur:architecture create` the ADR; edit `model.c4`; write the learning; run `python3 scripts/regenerate-shard-manifest.py --incremental --write`; file the production-change follow-up issue; open the PR with `Ref #10333`, `Ref #9757`, the `## Changelog` section and `semver:minor` (a new reference, new scripts, no new skill or agent).

## Guard Contract

### Guard 1 - delegation-verify.sh (the validity chokepoint)

**Property.** The verifier reports `valid` only when a marker-first, unedited, unexpired, admin-authored comment on THIS repo's still-open epic carries a verbatim quote, the cited Scope item and a complete Excluded list, and (when asked) a complete envelope whose Command block contains the asked command as a byte-identical full line.

**Assembly.** One chokepoint: `plugins/soleur/scripts/delegation-verify.sh`, called by `technical-ruling-gate.sh`, ~~`pre-ask-technical-fork-gate.sh`~~ (removed, R2), `hold-gate-eval.sh` and the CTO's pre-execution check; the conjunct list is structural (URL/repo, readable, marker, author type, author authority, unedited, quote, scope item, excluded list, expiry present/not past/<= 30 d, epic open, envelope present/one section/delegation match/all parts/rollback named, per-command full-line match). A caller that re-implements any conjunct is the defect; the three-caller wiring suite asserts each caller invokes the script and nothing else decides.

**Anchor.** The values compared live on GitHub (comment body, timestamps, author, permission, issue state) are outside the commit; one diff cannot forge them. The envelope file and the asked command are both agent-controlled, so the verifier proves identity and completeness, not that Scope item `n` semantically permits the command - that residual belongs to the CTO's authoring and to review, and is stated in the ADR.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the author-authority conjunct (accept any author) | RED: non-admin fixture returns `invalid not-admin-author` no longer |
| 2 | Run the verifier with no subcommand / empty fixture dir (the guard's own dispatch) | RED: must exit 2 `unverifiable`, never 0 with "0 checked" |
| 3 | Envelope with two Command lines where the FIRST matches and the SECOND is the asked-for variant with a trailing space | RED: only an exact full-line match passes; a check that stops at the first line is the defect |
| 4 | Treat `updated_at != created_at` as acceptable | RED: edited fixture must be `invalid edited` |
| 5 | Raise the Expiry cap or skip it when the date is missing | RED: `expiry-too-long` and `expiry-missing` fixtures |
| 6 | Make an API error return 0 / skip the epic-open check on error | RED: error fixture must exit 2 |
| 7 | Accept a delegation URL from another repository | RED: `wrong-repo` |
| 8 | Drop the `Confirmation:` conjunct, or accept a quote under 40 characters | RED: `no-confirmation` / `quote-too-short` fixtures |
| 9 | Print `verified-command` for a command that did not match | RED: stdout for a mismatch carries no `verified-command` line |
| 10 | Skip the denylist, the committed-envelope check or the issue-binding check (`non-delegable-command`, `envelope-not-committed`, `wrong-issue`/`epic-is-pr`) | RED: one fixture per conjunct |
| 11 | Make `--audit` skip a structural check (not only `expired`/`epic-closed`) | RED: an audit-mode fixture with an edited comment must still be `invalid edited` |

**Harness rows:** (H1) neuter the suite's `assert` helper to a no-op: the instrument self-test (a control assertion that must FAIL) reds the suite before any case runs; (H2) must-PASS inputs that are NOT the canonical fixture: a delegation with three Scope items and an envelope bound to item 3, CRLF line endings in the comment body, extra blank lines and a different epic/comment id, and a second envelope section selected by `#title`.

### Guard 2 - technical-ruling-gate.sh delegation arm

**Property.** A `Authorized by delegation` ruling passes only on a `production-mutating` operator row whose link the verifier calls `valid`; an unreadable link is exit 2, and the plain operator row and the technical-row rules behave exactly as before.

**Assembly.** Every unfenced `| Item | Class | Ruling |` table (the gate already scans all of them), in all three modes (`<path>`, `--branch`, archive lookup), every row class (technical, taste, operator, bare operator), and the single call site of the verifier inside `check_artifact`.

**Anchor.** The verifier's live GitHub reads; the row text alone is never trusted.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Make the arm return pass without calling the verifier | RED: invalid-delegation fixture must exit 1 |
| 2 | Drop the `TRG_EXEC_LOG delegation` line / skip rows (dispatch floor) | RED: the delegation fixture must log >= 1 examined delegation row |
| 3 | Table with two delegation rows, first valid, second invalid | RED: must exit 1 (stopping at the first row is the defect) |
| 4 | Accept the shape on an `operator (money)` row | RED: `bad-ruling-shape` |
| 5 | Map `unverifiable` to a pass | RED: unreadable-link fixture must exit 2 |
| 6 | Honour the `Authorized by delegation` text when it sits outside a table row (free prose, or a stray row after a blank line) | RED: only a recognised table row counts - the row stays required, and a stray one is exit 2 as today |

**Harness rows:** (H1) a mutant of the script (`# mut:` marker lines, as today) per mutation above, the unmutated control first; (H2) must-PASS: a plain `operator (production-mutating)` row naming an action, with no delegation, differing from the canonical delegation fixture.

### Guard 3 - pre-ask-technical-fork-gate.sh delegation arm - SUPERSEDED (REMOVED by CTO ruling R2)

**Property.** The hook denies an AskUserQuestion for delegation reasons only when the question text names a covered act in a verified delegation; every other state leaves the question to the existing arms.

**Assembly.** Each question in a multi-question payload (judged alone, over question text only), the cue (verb + delegation URL/envelope path/phrase), the verifier call, and the position of the arm relative to the expert, technical-ruling, authority and investigative arms.

**Anchor.** Live verification through the shared verifier; the question text cannot assert validity.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Verifier stub returns valid for everything and the cue gate is removed | RED: an ordinary "Approve the merge of PR 12?" question with no delegation reference must still be allowed |
| 2 | Hook invoked with the verifier file missing (dispatch) | RED: must ALLOW and announce on stderr, never deny and never silently skip |
| 3 | Two-question payload: question 1 ordinary, question 2 names a valid covered command | RED: must deny (judging only the first or the concatenation is the defect) |
| 4 | Option label alone carries the delegation URL | RED if denied: labels are buttons and must not trigger |
| 5 | Verifier times out | RED if denied: must allow |
| 6 | Move the arm after the authority short-circuit | RED: a covered permission-shaped question must still be denied |

**Harness rows:** (H1) the suite's existing instrument self-test plus a control that must FAIL; (H2) must-PASS: a covered act written without backticks and a question that merely mentions the word "delegation" with no verb.

### Guard 4 - hold-gate-eval.sh

**Property.** A hold is discharged only if a verified delegation is cited and every one of its `Gate:` predicates is a known kind that evaluates true now; any other state leaves it standing.

**Assembly.** The four predicate kinds and their evaluators, the `command` restrictions (repo-relative, tracked at HEAD, byte-identical to `origin/main`, 30 s, no ssh), the plan parser (holds and gates) and the envelope-section mode.

**Anchor.** `origin/main` content for `command` scripts and live `gh` state for the others; the plan text cannot assert either.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Treat an unknown predicate kind as passing | RED: unknown-kind fixture must leave the hold standing |
| 2 | Plan with holds but a parser that finds zero gates, exit 0 (own dispatch) | RED: must exit 1 `needs a person`, never "0 checked, exit 0" |
| 3 | Hold with two gates, first true, second false | RED: must stand (stopping at the first is the defect) |
| 4 | `command` script differs from `origin/main` or is an untracked file | RED: must stand |
| 5 | Delegation cited but verifier says invalid / unavailable | RED: all holds stand |
| 6 | No delegation recorded | RED if it evaluates: must exit 3 (today's behaviour) |
| 7 | A non-blank holds section that parses to zero holds returns 0 | RED: must exit 2 |
| 8 | Evaluate the `command` byte-identity against a stale `origin/main` | RED: fixture where origin/main moved after the last fetch |

**Harness rows:** (H1) neutered `gh` stub that always answers success must not make the false-predicate fixtures pass (fixtures choose the answers, the stub rejects unknown argv); (H2) must-PASS: a plan with three holds in mixed order and an envelope-mode run.

### Guard 5 - pr-overlap-preflight.sh

**Property.** No other open change that edits a file in the set, carries the same edit, or carries a same-subject commit goes unreported, and a check that could not run never reads as clear.

**Assembly.** Three signals x two modes x the data sources (`gh pr list` files and commits, `gh pr diff` for patch identity), the 200-PR list cap and the 20-diff cap (both disclosed), and the vehicle resolution (flag, then the ruling row).

**Anchor.** Live `gh` data; the vehicle comes from a CTO ruling row, which the gate already requires to be a `Ruled by CTO agent` cell.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the same-file signal | RED: shared-file fixture |
| 2 | `gh pr list` fails but the script prints "no overlap" (own dispatch) | RED: must exit 2 and print "I could not check" |
| 3 | A non-overlapping PR first in the list, an overlapping one second | RED: second must still be reported |
| 4 | Swap vehicle handling (always exit 10) | RED: this-change-is-vehicle fixture must exit 11 |
| 5 | Print a patch-id or SHA in the output | RED: jargon assertion |
| 6 | Add any `gh pr comment|edit|close` or `git push` call | RED: the stub rejects every write verb and the suite asserts zero write calls |
| 7 | Trust the 100-file cap (no paginated re-read) | RED: a 100-file fixture whose overlap is beyond the first page must be reported, and a failed re-read exits 2 |
| 8 | Treat shared-file-only overlap as blocking | RED: exit 13, nothing stops |

**Harness rows:** (H1) stubs reject unknown argv so a call-shape regression reds; (H2) must-PASS: same-subject-only overlap and a draft PR, differing from the same-file canonical.

### Guard 6 - go hold routing and the eval-gated block

**Property.** The `go-routing` block is byte-identical to the merge base, and the hold-routing paragraph exists outside it with both trigger tokens and fail-closed wording.

**Assembly.** `commands/go.md` is the only authority; `skills/go/SKILL.md`, the grok symlink, codex and cursor stubs read it. Members: block text, paragraph location, tokens, wording.

**Anchor.** `git show <merge-base>:plugins/soleur/commands/go.md` (outside the commit).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Edit one table cell inside the markers | RED: block hash differs from base |
| 2 | Delete the hold paragraph (own dispatch: suite extracting zero paragraphs) | RED: floor of 1 |
| 3 | Move the paragraph inside the markers | RED |
| 4 | Remove the `ask the operator` token while `HOLDS` remains | RED (a second member after a compliant first) |

**Harness rows:** (H1) the base ref unresolvable is a FAIL not a skip; (H2) must-PASS: whitespace-only change outside the block.

## Operator Holds

This section is read by ship Phase 6 step 5, not from conversation. It carries no `Delegation:` line: no Standing Delegation is recorded for this PR, so `hold-gate-eval.sh --plan` exits 3 before any other check and the prose path below applies. The `Gate:` line is recorded so the hold becomes mechanical on the day a delegation is cited. The same hold is evaluated a second time right before arming (ship Phase 6.5).

- Hold: do not arm merge while a registry host replace is running (this PR touches `plugins/soleur/**`).
  Gate: no-inflight-run registry-host-replace-dispatch.yml
- Hold: the rule file, its hash manifest and the ack file are owned by the code owner in `.github/CODEOWNERS`, and the ack row asks for that owner's human review of the widened go-ahead (`hr-menu-option-ack-not-prod-write-auth`); before arming, read the repository ruleset (`gh api repos/jikig-ai/soleur/rulesets`) for `require_code_owner_review`. If it is on, the owner's approval is an authorization to name in plain words (Class `operator (schedule)`), never a technical question.
  Evaluation today (no delegation is recorded for this PR): the usual prose path - run `gh run list --workflow registry-host-replace-dispatch.yml --status in_progress --limit 5`, then repeat it with `queued`, `waiting`, `requested` and `pending`; all five empty discharges it; a failed probe leaves it standing. Record the outputs in the PR body.

## Observability

Pure developer tooling that runs on the operator's or a Soleur user's own machine (observability layer 7, `cli-stdout-artifact`). There is no hook arm any more (CTO ruling R2) and no server-side surface. Every failure mode below names the stdout marker AND a durable artifact: stdout alone does not survive the session, so a mode whose only signal is stdout says so and is advisory.

```yaml
liveness_signal:
  what: "delegation-verify.sh prints one stdout verdict line per call (delegation: valid|invalid|unverifiable reason=<token>); hold-gate-eval.sh prints its own 'delegation: <state> reason=<token>' line on any stand and a final 'holds: N discharged: M standing: K' line; each delegated act leaves a receipt comment on the epic. The gate no longer echoes a SOLEUR_RULE_APPLIED marker (a script's stdout is not scanned by the capture hook)"
  cadence: "per call; per delegated act"
  alert_target: "cli-stdout-artifact: the in-session tool result the agent reads, plus the PR body (the 'holds:' line and each verifier verdict) and the epic's receipt comments"
  configured_in: "plugins/soleur/scripts/delegation-verify.sh, plugins/soleur/skills/ship/scripts/hold-gate-eval.sh, plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh"
error_reporting:
  destination: "stderr plain-language sentence plus the stdout verdict token; exit 1 invalid, exit 2 unverifiable; ship refuses to ready past exit 1 or 2"
  fail_loud: "[FAIL] <file>:<line>: delegation-invalid|delegation-unverifiable|receipt-missing|receipt-mismatch|receipt-unreadable - <plain reason>"
failure_modes:
  - mode: "GitHub API unreachable or rate-limited while verifying, or no timeout tool on the host"
    detection: "cli-stdout-artifact: verifier stdout 'delegation: unverifiable reason=api-error' (or 'reason=tool-missing'); the hold evaluator repeats it as 'delegation: unverifiable reason=<token>'"
    alert_route: "cli-stdout-artifact: ship blocks on gate exit 2; durable artifact: the 'holds: N discharged: M standing: K' line and the verdict recorded in the PR body"
  - mode: "delegation revoked (comment deleted or edited) or expired mid-epic"
    detection: "cli-stdout-artifact: next verify prints 'delegation: invalid reason=edited|expired|epic-closed' or 'unverifiable reason=comment-unreadable'; hold-gate-eval leaves every hold standing"
    alert_route: "durable artifact: the CTO files one action-required issue naming the stalled action; cli-stdout-artifact in the session"
  - mode: "a delegated act ran but left no matching receipt on the epic, or the receipt does not match the envelope"
    detection: "cli-stdout-artifact: gate exit 2 with reason receipt-missing, receipt-mismatch or receipt-unreadable; durable artifact: the 'Authorized by delegation ..., ran <ISO>' row in decision-challenges.md and the receipt comment on the epic"
    alert_route: "durable artifact: ship stays blocked until the receipt exists; the stronger independent check is #10361"
  - mode: "envelope outside the allowlist, scope or epic (command-not-delegable, scope-mismatch, epic-mismatch, envelope-uncommitted)"
    detection: "cli-stdout-artifact: verifier stdout 'delegation: invalid reason=<token>' on the CTO's pre-execution call"
    alert_route: "durable artifact: the committed envelope section and the PR body verdict; the act does not run"
  - mode: "hold cannot be evaluated (unknown or removed gate kind, zero holds parsed, missing tool)"
    detection: "cli-stdout-artifact: hold-gate-eval exit 2 and the plain sentence naming the hold that stands"
    alert_route: "durable artifact: the PR body 'holds:' line; ship does not arm"
  - mode: "overlap preflight cannot list PRs or hits its run deadline"
    detection: "cli-stdout-artifact: exit 2 or a partial-comparison disclosure and the sentence 'I could not check', never 'clear' (stdout is the only signal here; the check is advisory and fails open with a visible notice)"
    alert_route: "cli-stdout-artifact: one-shot continues with the notice, ship retries once then continues with the notice"
logs:
  where: "session tool results; the PR body (each verifier verdict, the hold-probe outputs and the 'holds:' line); the epic's delegation and receipt comments; decision-challenges.md"
  retention: "session lifetime / PR lifetime / epic lifetime"
discoverability_test:
  command: bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch
  expected_output: "rows examined"
```

The discoverability test is a read of the committed `decision-challenges.md` (the record of every delegated act and ruling for this branch): no network and no credentials while the artifact carries no delegation row, which is the case on this branch. It exits 0 and prints the row count, and it would print `[FAIL]` with the reason token for a malformed or unreceipted delegation row.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

### Functional Requirements

- [ ] FR1 `cto.md` carries the Rule and Own-the-epic interfaces; its frontmatter is byte-identical to `origin/main` (`git diff origin/main -- plugins/soleur/agents/engineering/cto.md` shows no hunk above the second `---`); `bun plugins/soleur/scripts/sync-grok-agent-compat.ts --check` and `bun plugins/soleur/scripts/sync-cursor-name-map.ts --check` pass with zero regenerated files.
- [ ] FR2 `technical-ruling-delegation.md` section 3 no longer contains the copied brief block or the phrase "Reply with exactly these four headings"; it links the agent; section 1 lists the non-delegable set verbatim; `components.test.ts` link tests stay green.
- [x] FR3 `delegation-verify.sh` implements every reason token in Phase 2; each has a fixture row. (`--self-check` was deleted in the review-fix round; the executable-template test replaces it.)
- [x] FR4 `technical-ruling-gate.sh` accepts a valid `Authorized by delegation <url>, envelope <path>` row on `operator (production-mutating)` only; invalid -> exit 1; unreadable -> exit 2; the section-7 canonical example still passes; the existing 29 KB suite stays green.
- [ ] ~~FR5 the hook denies a covered, verified, permission-shaped question~~ WITHDRAWN by CTO ruling R2: the hook arm was removed and `pre-ask-technical-fork-gate.sh` and its suite are byte-identical to `origin/main`.
- [x] FR6 `hold-gate-eval.sh` exits 0/1/2/3 as specified, fails closed on unknown kind, unreadable probe, invalid delegation and timeout.
- [ ] FR7 `pr-overlap-preflight.sh` prints plain-language output, exits 0/10/11/12/2 as specified, performs zero write calls, and is invoked from one-shot Step 0a.5 and ship Phase 6.5 only (`grep -n pr-overlap-preflight plugins/soleur/skills/review/SKILL.md` is empty).
- [ ] FR8 `go.md` hold paragraph present outside the markers; `go-routing` block hash equals the merge base; `go-routing-table-parity.test.sh` and `go-session-gates.test.sh` green; no eval run is required (gated block unchanged).
- [ ] FR9 `hr-menu-option-ack-not-prod-write-auth` keeps its id, `[compliance-tier]`, one line, <= 600 bytes; `python3 scripts/lint-agents-rule-budget.py`, `lint-agents-enforcement-tags.py`, `lint-rule-ids.py` and `lint-rule-bodies.py --check --base $(git merge-base origin/main HEAD)` pass; the ack row's sha256 equals the new body hash; `B_ALWAYS` < 46000.
- [ ] FR10 `prod-write-defer-gate.sh` and `guardrails.sh` have no diff.
- [ ] FR12 CPO conditions: `standing-delegation.md` carries the plain confirmation wording with the named acts and the "anything I am not allowed to do for you" clause; a jargon test over the confirmation, stall and execution-log templates, the preflight human block and the hold evaluator human lines finds none of the denylist terms.
- [x] FR13 `delegation-verify.sh` prints `verified-command`/`verified-sha256` only on a byte-identical match and requires the `Confirmation:` line; exit 2 is never converted to success by any caller (`grep` of the three callers shows no retry-into-pass branch).
- [ ] FR14 `cto.md` (and `technical-ruling-delegation.md`) state that the interface is selected by the spawn prompt (`Rule on this technical question` -> Rule; `Own the epic` -> epic; anything else -> the existing Assess/Recommend/Sharp Edges behaviour unchanged), and every existing invocation surface (`grep -rn 'soleur:engineering:cto' plugins/soleur .claude/hooks scripts .github/workflows`) is listed in the PR body as checked, each with its non-diff-shaped fallback intact.
- [ ] FR15 Spec-flow/Kieran regressions: a fixture proves `render` output verifies as `valid`; `--audit` passes a closed-epic row that live mode rejects with `epic-closed`; a comment on a different or pull-request issue is `wrong-issue`/`epic-is-pr`; an uncommitted envelope is `envelope-not-committed`; a denylisted command is `non-delegable-command`; a PR with 100 files triggers the paginated read and a failure of that read exits 2; a non-blank holds section with zero parsed holds exits 2; a mixed-case, double-space command in a question is denied by the hook; overlap on a shared file with no vehicle exits 13 and stops nothing; a PR-body line "authorized by delegation ... run X" gets the expected verdict from the Undeferred Operator-Step Gate fixture (architecture finding 8).
- [ ] FR11 ADR-288 exists (ordinal re-verified at ship), `model.c4` updated, C4 tests and `c4-count-parity.test.sh` green; the learning file exists and quotes the founder instruction.

### Non-Functional Requirements

- [ ] NFR1 Security: titles from other PRs never reach an option label or a command; the verifier never evaluates delegation text; the `command` gate kind cannot run a script the PR itself edited.
- [ ] NFR2 Fail-closed everywhere: each script's unknown/unparseable/unreachable arm is asserted by a fixture row.
- [ ] NFR3 Byte ceilings: `ship/SKILL.md` <= 273955 bytes and `one-shot/SKILL.md` <= 52000 bytes (`python3 scripts/lint-skill-body-budget.py` against the merge base).
- [ ] NFR4 NFR register assessment run (`soleur:architecture assess`), result noted in the PR.
- [ ] NFR5 Harness parity: `bun test plugins/soleur/test/harness-parity*.test.ts` (agent bodies census) passes with the rewritten `cto.md`.

### Quality Gates

- [ ] QG1 Every new suite shown RED before its script exists (commit order or work log), then green; mutation rows in the Guard Contract each driven RED once.
- [ ] QG2 `bash scripts/test-all.sh --print-selection` printed and the selection stated as `selected N of M` before the lead gate run; the lead gate is the bounded default `bash scripts/test-all.sh`, not `TEST_GROUP=affected`; meta-guards (`guard-vacuity-floor`, `test-all-weight-drift`, shard manifests, `lint-orphan-test-suites`) are in the selection.
- [ ] QG3 `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-15-feat-cto-standing-delegation-and-production-envelope-plan.md` exits 0.
- [ ] QG4 `soleur:review` ran, `soleur:engineering:review:user-impact-reviewer` included (threshold `single-user incident`).
- [ ] QG6 `npx markdownlint-cli2` is clean on this plan and `tasks.md`; every `knowledge-base/` path cited in the plan resolves (`grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN: {}'` prints nothing, except the files this PR creates); the ADR ordinal is re-probed across every `origin/*` ref immediately before merge; `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` is quoted in the PR.
- [ ] QG5 Before arming merge: `gh run list --workflow registry-host-replace-dispatch.yml --status in_progress|queued|waiting` empty (the `## Operator Holds` item); the PR is left ready and unarmed otherwise.

## Domain Review

**Domains relevant:** engineering, product (advisory, no UI surface)

### Engineering

**Status:** reviewed
**Assessment:** The CTO agent ruled the design (Items C and D, 2026-10-15) and the seven residual forks T1-T7 (recorded in `decision-challenges.md`); its dissents (byte-identical matching is brittle to quoting; literal-token go triggers miss paraphrased handoffs; a gate probe cannot ship in the PR that relies on it; an admin who is not the operator would pass T2) are accepted residuals, each fail-safe.

### Product/UX Gate

**Tier:** advisory (no file under a UI-surface glob is created or edited; the only user-facing surface is the wording of the plain-language confirmation and the overlap output)
**Decision:** auto-accepted (pipeline)
**Agents invoked:** soleur:product:cpo (sign-off for the `single-user incident` threshold, see below)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO sign-off (Phase 2.6 step 3): approved with conditions, all folded into this plan - (1) the confirmation names the delegated acts and embeds the exact question text plus the answer as the quote (Phase 1 item 4, verifier `quote-too-short`/`no-confirmation`); (2) the "only come back for" promise covers acts the agent is not permitted to do (Phase 1 item 4); (3) the jargon denylist is widened and applied to the preflight, the hold evaluator and the stall messages (Phase 6, Phase 3); (4) every stall emits one plain in-session sentence (Phase 1 item 5, Phase 6 wiring); (5) a conversational stop path (agent deletes the comment) and a per-act epic comment exist, the digest is follow-up issue 2. Scoped advisor consult (ADR-083): it proposed a verify-and-run wrapper and an App-identity check; the CTO ruled both out (C1, C2 in `decision-challenges.md`) and the consult's smaller point (exit 2 always blocks, never retried into a pass) is folded into Phase 2. The legal/regulated-data check: no schema, auth flow, API route or `.sql` file is touched; the delegation record stores the operator's own words on their own repository, with no new processor, so `soleur:gdpr-gate` is advisory-only here and its output is attached to the plan-review notes.

## Test Scenarios

Layers: all unit/integration shell suites; no e2e.

### Acceptance Tests (RED phase targets)

- Given a valid synthesized delegation and envelope, when `delegation-verify.sh verify --delegation <u> --envelope <e> --command "gh pr merge 123 --squash"` runs, then exit 0 and `delegation: valid reason=ok`.
- Given a ruling row `| T | operator (production-mutating) | Authorized by delegation <u>, envelope <e> |`, when the gate runs, then `[PASS]`; with the delegation edited, then `[FAIL] ...: delegation-invalid - ...` exit 1; with the API stub failing, then exit 2.
- Given a question "Approve running `gh pr merge 123 --squash` per envelope <e> (delegation <u>)?" and a valid delegation, when the hook runs, then the output carries `permissionDecision":"deny"`; with the verifier stubbed unverifiable, then no deny and a stderr note.
- Given a plan whose hold has `Gate: pr-merged 123` and a cited valid delegation and PR 123 merged, when `hold-gate-eval.sh --plan` runs, then exit 0 and "holds: 1 discharged: 1 standing: 0"; with PR 123 open, exit 1; with no delegation line, exit 3.
- Given two open PRs where #200 shares `a.sh` with the current branch and #201 does not, when the preflight runs with `--vehicle 200`, then exit 10 and the output names #200 and `a.sh` in plain words; with `--pr 200`, exit 11; with no vehicle, exit 12; with `gh pr list` failing, exit 2 and "I could not check".
- Given the repo's `go.md`, when `go-hold-routing.test.sh` runs, then the block hash equals the merge base and the paragraph holds both tokens.

### Regression Tests

- The existing `technical-ruling-gate.test.sh`, `pre-ask-technical-fork-gate.test.sh`, `go-routing-table-parity.test.sh`, `go-session-gates.test.sh`, `components.test.ts`, `lint-agents-*` and shard/orphan guards stay green unmodified except for the added rows.

### Edge Cases

- Comment body with CRLF; envelope with two sections and `#title` anchor; Expiry exactly created + 30 d (pass) and + 31 d (fail); a PR title containing control characters, backticks and an instruction-shaped sentence (printed inert, truncated); a PR with more than 100 changed files; `--files` empty; a detached HEAD; a plan with no `## Operator Holds`.

### Integration Verification (for `soleur:qa`)

- **API verify:** `bash plugins/soleur/scripts/delegation-verify.sh verify --delegation "$DELEGATION_URL" --envelope "$ENVELOPE_PATH"` against the real epic comment during the first delegated act (post-merge, expects `delegation: valid reason=ok` until the comment's expiry date).
- **Cleanup:** none (read-only).

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Keep per-command operator go-ahead only | Rejected: a non-technical user cannot judge a command; every epic stalls on the question the founder said Soleur must not ask. |
| Local pinned delegation file | Rejected (T1): cannot see revocation or expiry. |
| Trust a CTO-written act-class label | Rejected (T3): self-attestation. |
| New `epic-driver` / `production-change` skills | Rejected / deferred by the ruling. |
| New PreToolUse byte-identical enforcer | Rejected: `prod-write-defer-gate.sh` and `guardrails.sh` ruled unchanged; residual stated. |
| Routing-table row for holds inside the eval-gated block | Rejected (T5): eval cost and routing risk for a pre-route concern. |
| Prose-only hold evaluation | Rejected (T4): not machine-checkable. |

## Risks and Mitigations

- A false-valid verifier is the single-user incident. Mitigation: one chokepoint, seven mutation rows plus harness rows, live GitHub anchor, fail-closed default in all three callers.
- The delegation is posted through the same `gh` identity (accepted residual): verbatim quote, 30-day cap, edit-as-revocation, admin-author check.
- Byte ceilings on `ship/SKILL.md` (183 bytes of headroom) / `one-shot/SKILL.md` (1150) can fail CI after a late edit: procedure lives in references; the FIRST task of Phases 6 and 3 is to draft the exact insertion text and count its bytes (`printf '%s' "<text>" | wc -c`) before touching either file; make room by moving the Phase 6 step 5 `**Why:**` sentence and the "Record each condition's verdict ..." sentence (about 600 bytes together, measure first) into `ship/references/operator-holds.md`, leaving a pointer; re-run `lint-skill-body-budget.py --base origin/main` after every SKILL.md edit.
- `B_ALWAYS` crosses no new threshold (44069 -> ~44253 of 46000); if a later rebase adds rules and trips it, trim the Why/prose of unrelated rules, never this one's invariant.
- Rebase conflicts: #9745 (`go.md`, `help.md`) and #7390 (`AGENTS.rules.md`) are open; the preflight output for this very branch lists them.
- Merge timing: do not arm while a registry host replace is running (Operator Holds).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's threshold is `single-user incident`.
- `lint-rule-bodies.py --check` compares against the MERGE BASE; run it with `--base $(git merge-base origin/main HEAD)`, never `HEAD`.
- The `command` Gate kind requires the probe script to be on `origin/main` already: a probe for this epic's gates must land in an earlier PR, otherwise that hold stays a person-hold.
- Do not add a `version` key anywhere; no manifest changes are expected.
- Test fixtures are synthesized (`cq-test-fixtures-synthesized-only`): never the live epic URL or the live comment text.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` ratchets fixture-relative assertions; new suites should use `$REPO_ROOT`-anchored paths.
