# Tasks — enforcement-tag linter grammar + CI wiring + mandates-filing untag

Plan: `knowledge-base/project/plans/2026-08-03-fix-enforcement-tag-linter-grammar-and-mandates-filing-untag-plan.md`
Branch: `feat-one-shot-7174-7172-mandates-filing-and-enforcement-tag-lint` · PR #7194
Closes: #7174, #7172, #6751, #4622

Phase order is load-bearing — the grammar contract must land before its consumers.

## Phase 0 — Preconditions

- [ ] 0.1 Pin the baseline: `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.rules.md 2>&1 | tail -3` → expect `FAIL: 13`
- [ ] 0.2 Pin the suite baseline: `bash scripts/lint-agents-enforcement-tags.test.sh` → expect `Total: 9  Pass: 7  Fail: 2`, both on T1
- [ ] 0.3 Confirm ADR-160 is still the next free ordinal against `origin/main`

## Phase 1 — Linter grammar (RED first)

- [ ] 1.1 Write failing test cases in `scripts/lint-agents-enforcement-tags.test.sh` for each variant below, plus a matching negative for each
- [ ] 1.2 Skip non-body lines (body = `- ` at column 0); fixes the `AGENTS.rules.md:8` legend false positive
- [ ] 1.3 `/`-joined skill lists: every named skill must exist, anchor must resolve in at least one
- [ ] 1.4 Narrow the `/` rejection in `resolve_anchor` to the anchor only; keep `..` rejected unconditionally
- [ ] 1.5 `+`-joined enforcer segments: resolve each against its own namespace (skill heading / hook dir / agent name)
- [ ] 1.6 File-form enforcers (`components.test.ts SYMBOL`, `workflow-fidelity.ts`): resolve as repo file, require the symbol if given
- [ ] 1.7 `§X.Y` → `### X.Y` normalization, mirroring the existing `Phase X.Y` variant
- [ ] 1.8 Resolve `brainstorm Phase 2 budget checkpoint` — prefer a grammar variant; only if unreachable, tighten the tag text (then Phase 3 needs a second ack row)
- [ ] 1.9 Exit condition: linter reports `OK` with **zero** `AGENTS.rules.md` edits so far

## Phase 2 — Vacuity floor + default

- [ ] 2.1 Add the floor: zero hook+skill tags across all scanned files → ERROR naming the paths, exit 1 (precedent: `MIN_ASSERTIONS` in `plugins/soleur/test/net-issue-flow.test.sh`)
- [ ] 2.2 Flip the argparse default to `["AGENTS.md", "AGENTS.rules.md"]`
- [ ] 2.3 Document in the docstring that a lone `AGENTS.md` invocation now trips the floor by design
- [ ] 2.4 Test: tag-free fixture exits 1

## Phase 3 — `[mandates-filing]` untag (#7174)

- [ ] 3.1 Remove ` [mandates-filing]` from the `wg-when-deferring-a-capability-create-a` body — one line, mandate text untouched
- [ ] 3.2 Check the ADR-155 header prose (`AGENTS.rules.md:10-17`); correct only if it asserts a count or names both rules
- [ ] 3.3 Sweep for prose over-stating the tagged set: `net-issue-flow.sh`, `ship-net-issue-flow-gate.sh`, ADR-155, both test files
- [ ] 3.4 `python3 scripts/lint-rule-bodies.py --write` to regenerate `.claude/rule-body-hashes.txt`
- [ ] 3.5 Append the ack row (`<id>|<sha256>|<date>|7194|<reason>`); reason records the **decisive** evidence (nothing writes the claim), not the refuted "gate becomes advisory" framing
- [ ] 3.6 Update `decision-challenges.md` DC-1 → resolved with disposition
- [ ] 3.7 Update `discovered-defects.md` DD-1 → resolved **and correct its diagnosis** per the plan's reconciliation table

## Phase 4 — Wiring (#6751, #4622)

- [ ] 4.1 Register `lint-agents-enforcement-tags-unit` in `scripts/test-all.sh` (mirror `lint-rule-ids` at `:277-278`)
- [ ] 4.2 Register `lint-agents-enforcement-tags-live` with the explicit two-file invocation
- [ ] 4.3 Remove the allowlist entry at `scripts/lint-orphan-test-suites.sh:24`
- [ ] 4.4 Leave `lefthook.yml:87` unchanged — already correct

## Phase 5 — ADR + learning

- [ ] 5.1 Write `ADR-160-enforcement-tag-grammar-conforms-to-the-corpus.md` with the two rejected alternatives
- [ ] 5.2 Write the learning: an issue's diagnosis is a hypothesis; fix the ungated side; preserve the #7174 measurement with its stated method and bounds

## Phase 6 — Verification (all ACs)

- [ ] 6.1 AC1–AC3: linter green on the lefthook invocation, the bare default, and exact `12 hook + 32 skill` counts
- [ ] 6.2 AC4–AC6: suite `Fail: 0` with more cases; floor fires; negative case preserved
- [ ] 6.3 AC7–AC9: corpus greps + `lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"`
- [ ] 6.4 AC10: both net-issue-flow suites green; any two-rule hard-coding updated deliberately
- [ ] 6.5 AC11–AC12: orphan gate green post-removal; `bash scripts/test-all.sh` green
- [ ] 6.6 AC13–AC14: exactly one `AGENTS.rules.md` body line changed (two only if 1.8 changed the tag)
- [ ] 6.7 AC15–AC17: citation gate clean, ADR ordinal free, PR body carries all four `Closes`
