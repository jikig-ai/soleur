# Tasks: route technical rulings to the CTO agent

Plan: `knowledge-base/project/plans/2026-10-11-feat-route-technical-rulings-to-cto-agent-plan.md`

Branch: `feat-one-shot-cto-technical-rulings`. Draft PR: 10049.

## Phase 0: Setup and measurements

- 0.1 Run `git fetch origin main`; record `wc -c` of the lifecycle SKILL.md files (go, one-shot, plan, work, review, ship, brainstorm) and the ceilings in `plugins/soleur/test/skill-body-budget.json`.
- 0.2 Record baselines: `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` (B_ALWAYS 43166 at plan time), `bun test plugins/soleur/test/components.test.ts`, `bash .claude/hooks/pre-ask-technical-fork-gate.test.sh`.
- 0.3 Create the tracking GitHub issue for this work (the PR body gets `Closes #<N>`, never the title).
- 0.4 File the two tracked deferral issues: plugin port of the technical-ruling pre-ask gate, and the chat-prose Stop-hook arm (each with a re-evaluation trigger and a roadmap milestone).
- 0.5 Grep `plugins/soleur/test`, `scripts` and `.claude/hooks` for anchors in the `work` CTO/CLO bullets and `review` step 4 text that Phase 4 will move; confirm no test pins them.

## Phase 1: RED tests (write first, watch fail)

- 1.1 Hook cases R1-R10 in `.claude/hooks/pre-ask-technical-fork-gate.test.sh`, including reason assertions (`soleur:engineering:cto`, `technical-ruling-delegation.md`) and a V4 structural row.
- 1.2 `plugins/soleur/test/technical-ruling-gate.test.sh` plus `plugins/soleur/test/fixtures/technical-ruling-gate/*.md` covering Guard 1 mutation rows 1-9, harness rows, and the absent-file and unreadable-file cases.
- 1.3 New "Technical-ruling delegation wiring" describe block in `plugins/soleur/test/components.test.ts` (Guard 3).
- 1.4 Rule-line byte check via `lint-agents-rule-budget.py`.

## Phase 2: Reference and taxonomy

- 2.1 Create `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md` (nine sections in the plan).
- 2.2 Rewrite `decision-principles.md` section Precedence; add the `Class:` item schema; link the new reference.

## Phase 3: Ship gate

- 3.1 Implement `plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh` (modes: path, `--branch`, `--pr-body <file>`; exits 0, 1, 2).
- 3.2 Create `plugins/soleur/skills/ship/references/decision-challenges-render.md` (moved step 2.5 body plus the gate remedy procedure); rewrite step 2.5 to render by `Class:`.
- 3.3 Add `### Technical-Ruling Gate (mandatory)` to ship Phase 5.5.

## Phase 4: Skill pointers (net bytes per file at or below zero)

- 4.1 work: replace the CTO and CLO HARD GATE bullets with one pointer; move their text into the reference.
- 4.2 review: step 1 item 4 becomes a pointer.
- 4.3 plan: pointer in Plan Review step 2 and Step 4.5; replace stale line-number pointers with content anchors.
- 4.4 brainstorm, go: one-sentence pointers.
- 4.5 one-shot: inline three-line rule and the override in the plan and work subagent prompts.
- 4.6 Re-run `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`; lower ceilings to the new sizes.

## Phase 5: Hook arm

- 5.1 Add the ruling arm after the expert arm and ahead of `AUTHORITY_RE`; deny reason names the CTO and the reference; update the header contract paragraph.

## Phase 6: Rule, hashes, ADR

- 6.1 Amend the rule body in `AGENTS.rules.md` (at or under 590 bytes); run `python3 scripts/lint-rule-bodies.py --write`; append the ack line to `.claude/rule-weakening-acks.txt`.
- 6.2 Run `lint-rule-ids.py`, `lint-agents-enforcement-tags.py`, `lint-rule-bodies.py --check`.
- 6.3 Amend ADR-084 (Decision, Consequences, Alternatives considered); run `scripts/check-adr-ordinals.sh` and `plugins/soleur/test/c4-count-parity.test.sh`.

## Phase 7: Verify, compound, ship

- 7.1 Run every command in the plan's Acceptance Criteria once, including the Observability probe and `npx markdownlint-cli2` on the plan and this file.
- 7.2 Run `soleur:review`; fix findings in-PR.
- 7.3 Run `soleur:compound` (learning: carrier versus hook, byte ceilings, self-classification risk).
- 7.4 Run `soleur:ship`; the PR body names the rule-body ack as the one item needing the owner's CODEOWNERS review.
