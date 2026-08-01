# Tasks — fix: the soak-enrollment gate matches a token, not a claim (#7056, #7087)

Plan: [`knowledge-base/project/plans/2026-08-01-fix-ship-soak-gate-matches-token-not-claim-plan.md`](../../plans/2026-08-01-fix-ship-soak-gate-matches-token-not-claim-plan.md)

Lane: `cross-domain` (spec.md absent — TR2 fail-closed default)
Brand-survival threshold: `none`

> **Read §Plan Review Revisions first.** The plan's first draft proposed a very different
> matcher (claim-shaped alternatives + a gate-name strip). It was measured to silence 28
> of 50 real enrolments and is **rejected**. If any instinct during implementation is to
> "shape the claim" or "strip the gate's name", that path has been tried and measured.

---

## Phase 0 — Preconditions (no edits)

- [ ] **0.1** Baseline both suites green: `bun test plugins/soleur/test/ship-soak-followthrough-enrollment-gate.test.ts` (expect 14 pass / 0 fail) and `bun test plugins/soleur/test/ship-incident-pir-gate.test.ts`.
- [ ] **0.2** **Re-measure the two baselines every AC is relative to.** Recall of the shipped regex over the ground-truth enrolled set `grep -rlE 'scripts/followthroughs/[a-z0-9-]+\.sh' knowledge-base/project/plans/*.md` (plan time: **42/50**) and its FP count over the 40 most recent plans (plan time: **21/40**). Record both — AC1 and AC2 are relative, not absolute.
- [ ] **0.3** Read `scripts/ship-incident-pir-gate.sh` end to end. Mirror `set -uo pipefail`, herestring-not-pipe for `grep -q`, and its exit discipline. Do **NOT** mirror (a) its fence awk — it has no `END` check and fails *open* on an unbalanced fence; (b) its `${CLAUDE_PLUGIN_ROOT:-.}/../../scripts/` path — it resolves to the main checkout from a worktree and to two levels above the repo from a plain root.

## Phase 1 — RED: fixtures, harness, and the measurement runner first

`cq-write-failing-tests-before`.

- [ ] **1.1** Create `plugins/soleur/test/fixtures/ship-soak-signal-gate/` (named after the **script**, per the PIR precedent).
- [ ] **1.2** Author 12 **synthesized** plan-shaped fixtures (`cq-test-fixtures-synthesized-only`; no real emails, prod-shape UUIDs, or tokens; never copy #7034's or #7072's real plan):
  - [ ] `real-soak-declaration.md` — **FIRE**
  - [ ] `soak-disposition-not-applicable.md` — **QUIET** (#7056 pair)
  - [ ] `soak-filename-backticked.md` — **QUIET** (inline-code strip)
  - [ ] `soak-filename-bare.md` — **QUIET** (the structural delimiter; #7087's real fix)
  - [ ] `negated-criterion-soak.md` — **QUIET** (`no post-deploy soak`, `no 7-day soak`)
  - [ ] `negation-span-not-line.md` — **FIRE** (`Soak enrollment: none yet — the 14-day soak begins at deploy.`)
  - [ ] `negation-adjacent-real-soak.md` — **FIRE** (`no P0 incidents during the 7-day soak`)
  - [ ] `enrollment-heading-fires.md` — **FIRE** (`### Soak follow-through enrollment (Phase 2.9.1)`)
  - [ ] `fenced-claim-quiet.md` — **QUIET**
  - [ ] `unbalanced-fence-real-soak.md` — **FIRE** (fail-closed fallback)
  - [ ] `binary-corpus-real-soak.md` — **FIRE** (NUL byte; pins `grep -a`)
  - [ ] `backticked-declaration-known-bypass.md` — **QUIET** (named, accepted residual)
- [ ] **1.3** Add the `spawnSync` harness: FIRE ⇒ `status === 0` and stdout contains `SOAK-SIGNAL: yes`; QUIET ⇒ `status === 1` **exactly** (never merely non-zero); assert empty stderr both directions. Feed each fixture independently via stdin.
- [ ] **1.4** Add the **measurement runner** for AC1/AC2 — scores any candidate matcher against the ground-truth enrolled set and the FP window in one pass. Must exist **before** any regex is written; it is what makes the recall floor executable.
- [ ] **1.5** Confirm RED.

## Phase 2 — GREEN: the script owns the regex AND every strip

**Ordering is load-bearing** — the contract producer precedes its consumers.

- [ ] **2.1** Create `scripts/ship-soak-signal-gate.sh`. Header comment: what it is, the #7056/#7087 false positives it retires, the three-valued exit contract, the accepted backtick-bypass residual, the "an unenrolled prose soak has no other mechanical detector in the repo" consequence, and why each strip stage exists.
- [ ] **2.2** `SOAK_RE` — **one alternative changed** from what ships today: the bare noun gains a structural left-delimiter `(^|[^[:alnum:]_-])soak`. Everything else byte-identical. No claim-shaping.
- [ ] **2.3** Strip pipeline, all owned here: fences (indent-tolerant `/^[[:space:]]*```/` **with** `END { if (f) exit 2 }` and a fail-closed fallback to the unstripped body) → inline `` `code` `` spans (**single-quoted** `sed`, carry the `# shellcheck disable=SC2016` note) → `NEGATION_RE` **span** removal. No gate-name strip.
- [ ] **2.4** `NEGATION_RE` applied via `sed -E "s@…@@g"` — **span, not line**. Delimiter must be `@` (the regex contains `n/a`, so `s/…/…/` is a syntax error). Inline the case classes (`[Ss]oak`) — `sed` has no `-i`.
- [ ] **2.5** Match with `grep -aiE` under `LC_ALL=C.UTF-8`, then again under `LC_ALL=C`. `-a` on **every** grep in the script.
- [ ] **2.6** Exit contract: **0** = signal → `SOAK-SIGNAL: yes` plus the matched lines; **1** = clean no-signal, empty stdout; **2** = harness fault. Check each stage's status — do not infer fault from an empty haystack.
- [ ] **2.7** `chmod +x`. Confirm GREEN on all 12 fixtures.
- [ ] **2.8** Run the AC18 mutation matrix; commit the table (`mutant-id | operator | target | expected-killer-fixture`). Every fixture must appear as an expected killer at least once, or be deleted. Operators must include `widen-bound` and `swap-span-for-line`, not just deletion.
- [ ] **2.9** Run the measurement runner: AC1 recall `>= baseline - 1`, AC2 `new < old && new >= 1`.

## Phase 3 — Wire the two consumers

- [ ] **3.1** Hook: resolve the script via `"$(git rev-parse --show-toplevel)/scripts/ship-soak-signal-gate.sh"`.
- [ ] **3.2** Hook: **delete the local fence-strip awk** from the `CORPUS` build — the script owns it. Keep only body fetch + plan resolution + append. Guard the plan path: `[[ "$PLAN" == *..* ]] && PLAN=""`.
- [ ] **3.3** Hook: branch on exit in a `case` — 0 → enrollment check; 1 → exit 0; ≥2 → stderr + `emit_incident … fault` → exit 0. Missing/unreadable script → stderr + `emit_incident` → exit 0. Never let `set -eo pipefail` see the clean `exit 1`.
- [ ] **3.4** Hook: fold the script's stdout hit-lines into the deny `REASON`. Decide and state whether line numbers refer to the stripped haystack (blank stripped lines to keep offsets true) or whether to emit matched text without numbers. Silently wrong numbers are worse than none.
- [ ] **3.5** Hook: move the override check **after** the strips and anchor it to a standalone line — `grep -qE '^[[:space:]]*<!--[[:space:]]*gate-override:[[:space:]]*soak-followthrough-enrollment[[:space:]]*-->[[:space:]]*$'` — and `emit_incident … override` when it fires. Today it is an unanchored substring grep on the **raw** body, so any PR quoting the token self-bypasses the whole gate.
- [ ] **3.6** Hook: fix the truncated `emit_incident` reason string (currently `"PRs adding operator-only routes, cross-origin form-POST, c"` — belongs to a different rule, cut mid-word).
- [ ] **3.7** `plugins/soleur/skills/ship/SKILL.md`: same invocation, same anchored override check (the twins currently disagree — the SKILL has no mechanical override or env check at all). Keep `COMBINED` assembly minus the fence awk. Add the `**Why:**` sentence citing #7056 + #7087 and the measured recall/FP numbers.

## Phase 4 — Docs, seam test, retroactive application

- [ ] **4.1** `.claude/hooks/README.md`: replace the byte-identity bullet with single-ownership, the three-valued exit contract, the named backtick-bypass residual, and the "no other mechanical detector" consequence.
- [ ] **4.2** Delete the `soakRe()` scraper and the byte-identity parity test. Replace the two prose assertions with anchors a comment cannot satisfy (`ship-soak-signal-gate.sh` **and** `SOAK-SIGNAL` in `gateSection`); add both to the mutation matrix.
- [ ] **4.3** Add `.claude/hooks/ship-soak-followthrough-gate.test.sh` driving the **hook** end-to-end with a `gh` stub on `PATH` (precedent: `.claude/hooks/ship-unpushed-commits-gate.test.sh`). Cover: quoted-override-does-not-bypass, missing scanner → fail-open + stderr + telemetry, scanner exit 2 → fault arm, signal + unenrolled → deny JSON containing hit lines, signal + enrolled → allow. Register in `scripts/test-all.sh`.
- [ ] **4.4** Retroactive application (AC21): `knowledge-base/project/plans/2026-07-28-chore-collapse-agents-change-class-sidecars-plan.md` (#7034) and `knowledge-base/project/plans/2026-07-29-chore-triage-seven-orphan-infra-suites-plan.md` (#7072) each exit 1. Read-only — do not copy into `fixtures/`.
- [ ] **4.5** Full suite: `bash scripts/test-all.sh`.

## Phase 5 — Ship

- [ ] **5.1** Verify all 22 Acceptance Criteria.
- [ ] **5.2** PR body carries `Closes #7056` and `Closes #7087` (body, not title — `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] **5.3** PR body records: measured recall (before → after) over the ground-truth set, FP count (before → after), the mutation matrix, and the AC21 result. Note #7034/#7072 are **PRs**, not issues.
- [ ] **5.4** Remove the `deferred-scope-out` label from #7087 at merge.
- [ ] **5.5** Post-merge operator steps: **none**.

---

## Notes for the implementer

- **Recall is the primary axis.** Draft 1 scored the best false-positive number in the whole comparison and was the worst design in it. Run the measurement runner (task 1.4) before believing any matcher change.
- The plan's regex literals are a **verified starting point**, not a frozen contract. Task 2.9 re-measures. The fixture matrix plus AC1/AC2 are the contract.
- Do not add a second drift guard for the regex — the point is one copy, so parity is unrepresentable rather than asserted. Equally, do not describe the enrollment-triad duplication as closed: it is out of scope and stated as such.
- This gate's precision bias is deliberately the **opposite** of `ship-incident-pir-gate.sh`'s fail-toward-PIR posture. The rationale — and the correction of the false "four backstops" argument — is in the plan's §Domain Review. Do not harmonize them.
