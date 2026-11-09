# Tasks — feat-one-shot-12443-operator-authorizes-class

Derived from `knowledge-base/project/plans/2026-11-09-chore-hold-taxonomy-operator-authorizes-plan.md` (closes #12443; deferral tracked as #12479).

## Phase 1 — evaluator + contract

- [ ] 1.1 `plugins/soleur/skills/ship/scripts/hold-gate-eval.sh`: add `authorizes_hold()` (normalized prefix `operatorauthorize`, first-16 alnum compare, start-of-words only), an `AUTHORIZE` verdict printing `Say go and I run it: <words> - only you can say go`, skip it in `classify_no_delegation` like reserved, and handle it in the eval loop as always-standing/exit-2 with gates never probed. Update the header comment's grammar paragraph.
- [ ] 1.2 `plugins/soleur/skills/ship/references/operator-holds.md`: §1 format block + class paragraph (both prefixes, executor split, lifecycle: cleared by the operator's go, then the agent runs the act and the line is removed or rewritten); §2 exit-2 wording; §3 "What this does not cover"; §5 prints list.
- [ ] 1.3 `plugins/soleur/test/fixtures/hold-gate-eval/plan-authorizes-web-acceptance.md` (new synthesized fixture: authorizes hold first, `web-acceptance`-gated sibling whose key is absent from `apps/web-platform/server/legal-acceptance/texts/`).
- [ ] 1.4 `plugins/soleur/test/hold-gate-eval.test.sh`: new arms mirroring 4c/4e — verdict line, exit 2, spelling variants, mid-line negative, gates-never-probed, the two-class fixture, authorizes-only → exit 3.

## Phase 2 — classification sites

- [ ] 2.1 `plugins/soleur/commands/go.md` Step 1.5: split the set-aside into operator-authorizes (`Operator-authorizes:` + `ask me before`/`explicit go-ahead`/`operator approval` phrases) vs operator-executes (`Operator-reserved:`); classification-route render "say go and I run it"; the standing-delegation bullet's conversion rule gains the second write target.
- [ ] 2.2 `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md`: §1 never-delegable tail split (authorization-holds → `Operator-authorizes:`; decision-reserving + founder-physical → `Operator-reserved:` → Undeferred gate only for executes); §8.1c Needs-you render two line forms, exact command shown in-session per hr-menu-option-ack.
- [ ] 2.3 `plugins/soleur/agents/engineering/cto.md`: step 2 Scope drafting from the epic's full remaining grammar-compatible chain; step 3 two-token write rule; step 9 executor split (`Operator-authorizes:` → in-session go path, not the Undeferred gate).
- [ ] 2.4 `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md`: §6 `{SCOPE_ITEMS}` full-remaining-chain drafting rule (acts whose target token doesn't yet exist are named in words; Scope re-verified at each act boundary — a gap fails closed to the authorizes path); §9 carve-out paragraph adds the new token, hard-limits paragraph names the class, Records' unverified-gated merge/deploy hold becomes `Operator-authorizes:` (decision point from the plan — review may keep `Operator-reserved:`).

## Phase 3 — pin tests + probe + ADR

- [ ] 3.1 `plugins/soleur/test/go-hold-routing.test.sh`: update `classification-route`/`operator-reserved-format`/`reserved-conversion` + add authorizes-class properties to `ALL_PROPS`.
- [ ] 3.2 `plugins/soleur/test/cto-interface-selector.test.sh`: refresh anchors where cto.md text moves.
- [ ] 3.3 `plugins/soleur/test/technical-ruling-owner-list.test.sh`: rows asserting the authorizes Needs-you line form.
- [ ] 3.4 `plugins/soleur/test/components.test.ts`: PAIRS anchor refreshes + `PAIRS_FLOOR` bump as needed.
- [ ] 3.5 `plugins/soleur/test/operator-authorizes-probe.sh` (new; bash+grep only; NOT `*.test.sh`): greps the four wiring sites and prints `operator-authorizes: wired`.
- [ ] 3.6 `knowledge-base/engineering/architecture/decisions/ADR-289-standing-delegation-and-production-envelope.md`: amendment — fourth class, denylist-bounds-standing-approval-only clarification, Scope drafting rule.
- [ ] 3.7 Non-goal guard: `git diff origin/main -- plugins/soleur/scripts/delegation-verify.sh` empty; §5 Excluded sentence byte-identical.

## Phase 4 — verification

- [ ] 4.1 Run all touched suites per the plan's Acceptance Criteria (hold-gate-eval, go-hold-routing, cto-interface-selector, technical-ruling-owner-list, components.test.ts via bun, delegation-verify.test.sh, probe).
