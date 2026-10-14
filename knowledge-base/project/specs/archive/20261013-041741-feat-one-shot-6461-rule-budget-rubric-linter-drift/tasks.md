# Tasks — feat-one-shot-6461-rule-budget-rubric-linter-drift

Derived from
[`knowledge-base/project/plans/2026-07-20-chore-reconcile-agents-rule-budget-rubric-with-linter-plan.md`](../../plans/2026-07-20-chore-reconcile-agents-rule-budget-rubric-with-linter-plan.md).

`Closes #6461`

Lane: `cross-domain` (no `spec.md` present — defaulted fail-closed).

**Plan-quoted numbers are preconditions to verify, not facts.** Re-measure in Phase 0 before relying
on any figure below.

---

## Phase 0 — Preconditions

- [ ] 0.1 Run `cd "$(git rev-parse --show-toplevel)" && python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md 2>&1`.
      Expect `[WARN] B_ALWAYS=22900 … (AGENTS.md=6072 + AGENTS.core.md=16828)`, exit 0.
      **Note stdout alone is empty at WARN tier** — this is why `2>&1` is mandatory (FR1).
- [ ] 0.2 Run `bash scripts/lint-agents-rule-budget.test.sh` — expect 20/20 pass.
- [ ] 0.3 Run `bash scripts/rule-metrics-aggregate.sh` — expect the `0 rule-carrying incident lines`
      no-op line (the incidents log is operator-machine-local; it does not exist in a worktree).
- [ ] 0.4 Record raw bytes: `wc -c AGENTS.md AGENTS.core.md` → expect 6072 + 16901 = **22973 raw**
      (vs 22900 frontmatter-stripped). Both numbers are needed; do not conflate them (TR5).
- [ ] 0.5 **TR3 — verify every extraction pattern returns exactly one match** against its real target
      file, before freezing any of them into the guard:
      - `MAX_ALWAYS_LOADED_BYTES = ([0-9]+)` in `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`
      - `ALWAYS_LOADED_CAP=([0-9]+)` in `scripts/compound-promote.sh`
      - ASCII-safe `([0-9]+) warn` / `([0-9]+) critical` / `cap at ~([0-9]+) bytes` in `AGENTS.docs.md`
        (**not** the multibyte `≤`, per `cq-regex-unicode-separators-escape-only`)
      - `([0-9]+)-byte critical cap` in `plugins/soleur/skills/plan/SKILL.md`
      - `^B_ALWAYS_(WARN|REJECT) = ([0-9]+)` and `^PER_RULE_CAP = ([0-9]+)` in the linter
      A pattern matching zero lines makes the guard vacuous — this is the single highest-risk step.
- [ ] 0.6 Confirm no `AGENTS*.md` file will be staged (FR7) — `scripts/lint-agents-enforcement-tags.py`
      is **pre-existing red** (12 unresolved anchors) and would block the commit. See Sharp Edge 1.

---

## Phase 1 — Correct the consumers (FR5)

- [ ] 1.1 `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`: **split the
      conflated constant.**
      - `MAX_ALWAYS_LOADED_BYTES = 23000` — post-apply hard gate (L580-587: Sentry mirror +
        `git checkout -- .` revert). Mirrors the commit gate.
      - `PROPOSE_ALWAYS_LOADED_BUDGET = 20000` — LLM proposal hint (L433). Leaves trim headroom.
- [ ] 1.2 Same file: fix the prompt label — it currently says `the warn cap is ${…}`. After the split
      the proposal hint genuinely *is* the warn budget. Ensure the post-apply gate's Sentry
      `extra.cap` reports the **reject** constant and is not mislabelled.
- [ ] 1.3 Same file: add comments naming `scripts/lint-agents-rule-budget.py` as source of truth,
      `scripts/lint-agents-compound-sync.sh` as the enforcing guard, the **raw-vs-stripped 73 B
      skew** (TR5.2), and the ADR-092/AP-017 additive-envelope note (Sharp Edge 8).
- [ ] 1.4 `scripts/compound-promote.sh`: mirror the same two-constant split, label fix and comments.
- [ ] 1.5 `scripts/compound-promote.test.sh`: update the assertion `9:18000` → `9:23000` **and** the
      stale `# … Cap is 18000.` comment. **Same commit as 1.4** — the test asserts the constant, so
      a split commit leaves an intermediate red.
- [ ] 1.6 `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`: correct the
      `18000-byte warn / 22000-byte critical` prose **and** the `18k` prose (a digit-only grep
      misses it).
- [ ] 1.7 `plugins/soleur/skills/plan/SKILL.md` (site 9): keep the correct `23000`, but correct the
      raw `B_ALWAYS = $(wc -c < AGENTS.md) + $(wc -c < AGENTS.core.md)` recipe to state the
      frontmatter-stripped basis (same method bug as site 3).

---

## Phase 2 — Rewrite the rubric (FR1 / FR1b / FR2 / FR3)

Region: `plugins/soleur/skills/compound/SKILL.md`, from `8. **Rule budget count.**` through the
`B_TOTAL is informational only` paragraph.

- [ ] 2.1 Replace the hand-rolled `B_INDEX`/`B_CORE`/`B_ALWAYS` math with the linter invocation,
      **including `2>&1` and `cd "$(git rev-parse --show-toplevel)"`** (FR1).
- [ ] 2.2 **FR1b degrade path.** Wrap in an existence check mirroring the block's existing aggregator
      handling. Define agent behaviour for: linter absent, `python3` absent, linter **exit 2**
      (`AGENTS.md missing`), and linter **exit 1** (malformed frontmatter) — the last two emit **no**
      verdict line at all. `compound` is a distributed skill that also runs against consumer repos
      where none of this infrastructure exists.
- [ ] 2.3 **FR2 — retain:** `B_TOTAL`, rule count `A`, longest rule `L`, constitution count `C`; the
      `<!-- rule-threshold: 115 -->` sentinel; and **the `emit_incident cq-agents-md-why-single-line
      applied` telemetry block** (it produces `.claude/.rule-incidents.jsonl`, which
      `rule-metrics-aggregate.sh` consumes — dropping it makes Deferral 2 unanswerable).
- [ ] 2.4 **FR3.1 — retain both tiers' guidance:** the CRITICAL guardrails (`retired-rule-ids.txt`;
      only `wg-*` demotable, never `hr-*`, per #3496; preserve per-issue mechanism labels) **and**
      the WARNING guardrails (placement gate; route already-enforced/domain-scoped insights to a
      skill/agent, not `AGENTS.core.md`).
- [ ] 2.5 **FR3.2 — tier remap (easy to get backwards).** Attach the shrink/demote guidance to the
      linter's **WARN** tier, not REJECT. The tree is at 22900 = WARN; REJECT means the commit is
      already blocked, so guidance parked there never reaches an agent.
- [ ] 2.6 **FR3.3 — de-stale:** replace `sed -n '88,115p' .claude/hooks/session-rules-loader.sh`
      (real block ≈167-190) with the content anchor
      `grep -n 'DOCS_RE=' -A 25 .claude/hooks/session-rules-loader.sh`
      (`cq-cite-content-anchor-not-line-number`). Remove the `(22k)` prose form.

---

## Phase 3 — Extend the guard (FR4 / FR4b / FR4c / FR6 / TR2)

- [ ] 3.1 Write `scripts/lint-agents-compound-sync.test.sh` per the plan's **Test Scenarios** table
      (`mktemp -d` throwaway trees, `assert_exit` / `assert_contains`, following
      `scripts/lint-agents-rule-budget.test.sh`).
      **T2-T6 are RED-first** — confirm they fail against the unextended guard.
      **T1, T7, T8 are regression-pins that pass by construction — do not "fix" them.**
- [ ] 3.2 Extend `scripts/lint-agents-compound-sync.sh` with the **table-driven** site loop (one
      array entry per site — not five bespoke assertions).
- [ ] 3.3 Loop requirements: (a) empty extraction **or missing target file** → hard failure with a
      diagnostic naming the path; (b) **accumulate all mismatches, print every diagnostic, exit
      non-zero once** (the script currently early-exits on first mismatch, which makes T2
      unachievable); (c) diagnostics **state the unit** (raw vs frontmatter-stripped); (d) ASCII-safe
      patterns; (e) assert numbers, not prose; (f) resolve paths via `git rev-parse --show-toplevel`
      (`test-all.sh` and lefthook invoke from different CWDs, and the guard now crosses into
      `apps/web-platform/`); (g) **`PER_RULE_CAP` is asserted, not dropped** — `600` is restated in
      `AGENTS.docs.md` and `compound/SKILL.md`.
- [ ] 3.4 **FR4b — guard the originating file.** Assert `compound/SKILL.md` (i) contains the linter
      invocation string **including `2>&1`**, and (ii) contains no threshold literal in step 8's
      **tier-decision region** — region-scoped, because the retained `emit_incident` snippet
      legitimately contains `~600 bytes`. Without this the file that caused #6461 leaves the sync
      graph and the bug can recur verbatim.

---

## Phase 4 — Wire into CI and pre-commit (FR4c)

- [ ] 4.1 `scripts/test-all.sh`: add `run_suite` entries for the guard and its unit suite (alongside
      the existing `lint-agents-rule-budget-live` / `-unit` lines) so both gate PRs via the required
      `test` check.
- [ ] 4.2 `lefthook.yml`: extend the `agents-compound-sync` glob to **explicitly enumerate**
      `AGENTS.docs.md` (**missing today** — the sentinel moved there post-#3493 and the glob never
      followed), `scripts/lint-agents-rule-budget.py`, the cron TS path,
      `scripts/compound-promote.sh`, `plugins/soleur/skills/plan/SKILL.md`, plus the **self-glob** of
      `scripts/lint-agents-compound-sync.sh` and its new test.

---

## Phase 5 — Verify (Acceptance Criteria)

- [ ] 5.1 `bash scripts/lint-agents-compound-sync.sh` → exit 0.
- [ ] 5.2 `bash scripts/test-all.sh scripts` → exit 0 (AC11).
- [ ] 5.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → exit 0 (AC12).
      **Not** `npm run -w …` — the repo root declares no `workspaces`.
- [ ] 5.4 `bash scripts/compound-promote.test.sh` → exit 0 (AC6).
- [ ] 5.5 Linter still `[WARN] B_ALWAYS=22900`, exit 0 — unchanged, since no `AGENTS*.md` was touched.
- [ ] 5.6 Walk AC1-AC14. Apply the **AC-shape rules**: negative assertions as `! grep -qE …` (never
      "`grep -c` returns 0", which exits 1 on pass); patterns cover `(18|20|22|23)000`, `\b(18|20|22|23)k\b`
      and `\b2[0-9],[0-9]{3}\b`; negative greps are region-scoped, never whole-file.
- [ ] 5.7 Confirm `git diff --name-only origin/main...HEAD` contains **no** `AGENTS*.md` (FR7).

---

## Phase 6 — Follow-ups

- [ ] 6.1 File Deferral 1 — trim `B_ALWAYS` to restore promotion headroom (criterion: `B_ALWAYS ≤ 20000`).
- [ ] 6.2 File Deferral 2 — establish a trustworthy `rules_unused_over_8w` denominator
      (98 unused of **101 tagged**, not of the 202-rule registry) before any pruning campaign.
- [ ] 6.3 File Deferral 3 — 12 unresolved `[skill-enforced:]` anchors **and** the fact that
      `scripts/lint-agents-enforcement-tags.py` is lefthook-only (not in CI), so it fails to gate.
- [ ] 6.4 File Deferral 4 — stale 18000 in `tools/migration/{split-sidecars,classify-rules}.sh`.
- [ ] 6.5 File Deferral 5 — port the frontmatter strip (`scripts/lib/frontmatter-strip/SPEC.md`,
      which is explicitly a multi-implementation contract) into the promote consumers so the
      comparison is unit-exact rather than 73 B conservative.
- [ ] 6.6 Verify every label exists (`gh label list --limit 200`) before `gh issue create`.

---

## Verification commands (canonical forms)

```bash
cd "$(git rev-parse --show-toplevel)"

# always-loaded budget — 2>&1 is mandatory (WARN/REJECT go to stderr)
python3 scripts/lint-agents-rule-budget.py \
  AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md 2>&1

# the new cross-file sync guard + its suite
bash scripts/lint-agents-compound-sync.sh
bash scripts/lint-agents-compound-sync.test.sh

# full scripts shard (what CI's test-scripts job runs)
bash scripts/test-all.sh scripts

# typecheck the edited cron
cd apps/web-platform && ./node_modules/.bin/tsc --noEmit
```
