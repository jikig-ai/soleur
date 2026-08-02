# Tasks — net-issue-flow mandated-filing exemption

```yaml
lane: cross-domain
plan: knowledge-base/project/plans/2026-08-02-feat-net-issue-flow-mandated-filing-exemption-plan.md
challenges: knowledge-base/project/specs/feat-one-shot-net-issue-flow-mandated-filing-exemption/decision-challenges.md
```

> **Read `decision-challenges.md` before starting.** Two recorded User-Challenges (DC-2: is the
> whole mechanism proportionate; DC-1: should the second rule be tagged) may change the shape of
> Phases 1–3. Phase 0 and Phase 0.5 are valuable regardless of how they resolve.

## Phase 0 — Preconditions (verify, never assume)

- [ ] 0.1 `bash plugins/soleur/test/net-issue-flow.test.sh` → record assertion count (expect **23**, ALL PASS). **Do NOT measure with `grep -cE '(^|[; ])pass '` — measured, it returns 24**, because the `fail` message on the `--limit 500` case contains the words *"must pass"*. Use `grep -cE '(^|[;[:space:]])pass "'`. A floor pinned at 24 reds the suite immediately.
- [ ] 0.2 `bash .claude/hooks/ship-net-issue-flow-gate.test.sh` → ALL PASS
- [ ] 0.3 `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` → record `B_ALWAYS` (expect `[OK] 42547`)
- [ ] 0.4 Measure both target rule bodies against the 600 B `PER_RULE_CAP` (expect 313 B / 364 B → 331 B / 382 B)
- [ ] 0.5 **Wall clock:** `time bash plugins/soleur/skills/ship/scripts/net-issue-flow.sh <PR>` ×3. Record. Budget for the finished gate is **≤6 s**. Expect ~7.7–8.1 s today — this is P0-0.
- [ ] 0.6 Read the last rows of `.claude/rule-weakening-acks.txt` for the exact ack shape
- [ ] 0.7 **(recommended, DC-1)** Measure the day-zero exemption rate: of issues filed against merged PRs in the last 30 days, what fraction would satisfy `Mandated-By` + `Refs` + OPEN? Put the number in DC-1.

## Phase 0.5 — FR0: fix the pre-existing fail-open (BLOCKING PREREQUISITE)

- [ ] 0.5.1 `.claude/hooks/ship-net-issue-flow-gate.sh`: `timeout 8` → `timeout 25`
- [ ] 0.5.2 Same file: emit `emit_incident net-issue-flow warn "gate timed out — failed open"` when `RC == 124`, **before** the `[[ "$RC" -eq 1 ]] || exit 0` line
- [ ] 0.5.3 Add a hook-suite case asserting an RC=124 run emits the warn row
- [ ] 0.5.4 Re-run 0.2

## Phase 1 — Corpus contract (must precede the consumer)

- [ ] 1.1 `AGENTS.rules.md`: append ` [mandates-filing]` to the **bodies** of `wg-block-pr-ready-on-undeferred-operator-steps` and `wg-when-deferring-a-capability-create-a` (ids immutable — bodies only)
- [ ] 1.2 `scripts/lint-rule-bodies.py`: append `"[mandates-filing]"` to `SECURITY_TAG_MARKERS` (FR2b — closes the new-rule-id ack hole)
- [ ] 1.3 `python3 scripts/lint-rule-bodies.py --write` to regenerate `.claude/rule-body-hashes.txt`
- [ ] 1.4 Append one ack row per rule to `.claude/rule-weakening-acks.txt` (`<id>|<sha256>|<date>|<PR>|<reason>`, non-empty reason). **WORM + needs a real PR number** — open the PR first or write at ship time
- [ ] 1.5 `python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"` → exit 0
- [ ] 1.6 Re-run 0.3 → still `[OK]`

## Phase 2 — RED tests (before any gate logic)

- [ ] 2.1 Add a stubbed `git` on PATH beside the existing stubbed `gh` (**not** an env-var corpus seam — that is a production self-grant vector)
- [ ] 2.2 TR7a: worktree corpus derives exactly the 2 expected ids
- [ ] 2.3 TR7b: fixture corpora prove per-line matching and reject a loose regex
- [ ] 2.4 Positive fixtures: valid claim + companion + OPEN; **CRLF** body
- [ ] 2.5 Negative fixtures (each exit 1): unknown id; real-but-untagged id; **`cq-*` ungated-prefix** id; retired id; prefix-extension `…-steps-v2`; malformed; **two `Mandated-By:` lines**; fenced claim; prose mention; bare `#N` companion only; fenced companion; no companion; `Refs #71590` vs `#7159`; CLOSED issue; **absent `state`**; **merge-base unresolvable**
- [ ] 2.6 TR6: assertion floor `>=` baseline 23 (**not** `==`)
- [ ] 2.7 Confirm RED for the right reasons; note which negatives pass vacuously pre-implementation

## Phase 3 — GREEN: gate logic (all inside the single existing `jq` pass)

- [ ] 3.1 FR1: per-line marker match, ids restricted to `^(hr|wg)-`, SHA-guarded merge-base. **A bare `:path` must never reach `git show`** (it reads the staged index)
- [ ] 3.2 FR1b: print `Mandating rules: N  (<ids>, merge-base <sha>)` — the **ids**, not just a count; distinguish "read failed" from "read OK, zero tagged"
- [ ] 3.3 FR3: claim predicate — exactly one anchored `Mandated-By:` line with `\r` in the bracket classes, `ascii_downcase` before set membership, `(Tracks|Refs)[[:space:]]+#<N>([^0-9]|$)` companion, `.state == "OPEN"` positive equality
- [ ] 3.4 FR4: fence-strip **both** corpora; hoist the PR-body strip above the companion match
- [ ] 3.5 FR5: new formatter (`_fmt` cannot carry pairs); `Exempt:` line always emitted; **`Rejected:` line per non-exempt FILED issue naming the cause**; `NET = FILED - EXEMPT - CLOSING`
- [ ] 3.6 FR6: `_emit bypass` under `net-issue-flow-mandated-filing--<rule-id>` with `flipped=true|false`
- [ ] 3.7 Re-run both suites and **re-measure wall clock** against the ≤6 s budget

## Phase 4 — Mutation battery (record in `mutation-evidence.md`)

- [ ] 4.1 Delete the exemption block entirely (headline mutation) → suite reds
- [ ] 4.2 Drop the `^(hr|wg)-` restriction → `cq-*` case reds
- [ ] 4.3 Drop the SHA guard → the merge-base-unresolvable case reds (proves the index fallback is caught)
- [ ] 4.4 Drop `\r` from the anchors → CRLF case reds
- [ ] 4.5 Accept two claim lines → two-claim-line case reds
- [ ] 4.6 Drop the companion right boundary → `#71590` case reds
- [ ] 4.7 Drop the OPEN check → CLOSED case reds
- [ ] 4.8 Drop fence-strip on either corpus → the matching fenced case reds
- [ ] 4.9 Make a corpus read failure yield the full id set → that case reds
- [ ] 4.10 Delete one whole test case → floor reds
- [ ] 4.11 Re-time after the battery

## Phase 5 — Writers and docs

- [ ] 5.1 FR8: reframe **both** remedy blocks (the hook's `REASON` heredoc **and** `net-issue-flow.sh`'s own `(a)/(b)/(c)`). Drop "architectural-pivot deferral"; add `(d)` mandated-filing; placeholder-only `<rule-id>`; add the **untagged-rule dead-end message**. Preserve all four hook-suite needles
- [ ] 5.2 FR10: ship/SKILL.md remedy template → `--body-file` so `Mandated-By:` lands on its own line. **Additive only** — keep `deferred-automation` and `type/chore`. Do **not** rename the `[skill-enforced: ship Phase 5.5 Undeferred Operator-Step Gate]` anchor
- [ ] 5.2b **FR10b: `work/SKILL.md` gets the same treatment.** Its `gh issue create --label type/chore --body "deferred-automation backlog item; re-evaluate when: …; playwright-attempt: …"` block is a **live writer** with the identical double-quoted-`\n` defect, and it is the site that files most mandated issues. Skipping it ships a reader with no writer
- [ ] 5.2c **FR12: `review/SKILL.md`** — its prose *"a PR that opens more issues than it closes is a workflow failure"* is falsified by `NET = FILED - EXEMPT - CLOSING`. Reword to name the exemption
- [ ] 5.3 FR11: ship Phase 6 body template must preserve every `(Tracks|Refs) #N` line and every `gate-override` marker
- [ ] 5.4 FR6 readout: add `summary.gate_exemptions` to Stage C of `scripts/rule-metrics-aggregate.sh`. **If this is cut, strike the attribution framing from the ADR and PR body**
- [ ] 5.5 Fix the `rule_id net-issue-flow` lookup instruction in `scripts/followthroughs/filed-per-pr-soak-6769.sh` (it will miss both new ids)
- [ ] 5.6 ship/SKILL.md: correct `18 assertions` → the real count, and the fail-open `transient` → `warn`
- [ ] 5.7 Re-run the hook suite

## Phase 6 — ADR

- [ ] 6.1 Author `ADR-155` (ordinal **provisional** — re-verify against `origin/main`; on renumber sweep the plan **and** this file). Required sections: the cross-gate-authority class boundary; the untaggable filing-site class; the corrected ack-gate scope (`^(hr|wg)-` only; CODEOWNERS review not enforced — it is a self-authored, hash-bound CI attestation); the **AP-017 deviation**; and the honest-limitation list (file-before-PR and `Closes`-without-closing are cheaper and unattributed)

## Phase 7 — Exit gate

- [ ] 7.1 Full suite; `bash scripts/test-all.sh scripts`
- [ ] 7.2 `python3 scripts/lint-rule-ids.py`; `python3 scripts/lint-agents-enforcement-tags.py`
- [ ] 7.3 `bash scripts/rule-metrics-aggregate.sh` → must not exit 5; `summary.gate_exemptions` present
- [ ] 7.4 **Re-measure wall clock** (final AC11 check)
- [ ] 7.5 Enrol the automated follow-through: assert the merge-base derivation returns 2 once merged (unverifiable pre-merge by construction)
- [ ] 7.6 PR body: state that **this PR carries the blanket override** (its own decision-challenge issue makes it net-positive), and argue the ADR-131 position honestly per D5
