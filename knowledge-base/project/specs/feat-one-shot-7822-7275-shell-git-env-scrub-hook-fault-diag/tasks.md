# Tasks — shell git-fixture containment, and a diagnosable hook_self_fault

Derived from
`knowledge-base/project/plans/2026-09-08-fix-shell-git-env-scrub-and-hook-fault-diagnosis-plan.md`.
Ships as three PRs; PR 1 must merge before PR 2 begins.

lane: cross-domain
brand_survival_threshold: single-user incident

---

## Phase 0 — preconditions (measure; do not assume)

- [ ] 0.1 Re-run the `PIPESTATUS`-through-command-substitution probe. Paste the table into PR 1.
      If `jq_rc` is not always 0, **stop** — R6 has not reproduced.
- [ ] 0.2 Re-run the jq return-code table (`''`, `garbage {{`, truncated, non-object root, compile
      error) against the installed jq. Paste it. The enum mapping is pinned to these values.
- [ ] 0.3 Re-derive the ratchet baseline (currently 3) and the `plugins/soleur/test/*.test.sh`
      adoption count (currently 47 of 81). If either moved, update the sweep list and the baseline.
- [ ] 0.4 Re-run `scripts/rule-metrics-aggregate.sh` against a **copy** of the live incidents log
      under `INCIDENTS_REPO_ROOT`. Never the real repo root — it writes before it rejects.
- [ ] 0.5 Confirm #7849, #7942 and #7835 are still open.

---

## PR 1 — repair the discriminator (Phase B1, ships alone)

- [ ] 1.1 Write the failing cases FIRST, driven through **stdin** (a second `jq` is forbidden by the
      contract): empty stdin observes rc 0; a truncated document `{"a":"x"` observes rc 5. Both must
      fail against current code. Record before/after readings.
- [ ] 1.2 Capture jq's return code **inside** the command substitution using `$?`, not
      `PIPESTATUS` — jq is the last pipeline element, and `PIPESTATUS[1]` encodes a positional
      invariant that breaks when anyone appends a filter.
- [ ] 1.3 Implement the parse precedence: strip sentinel → split on RS → **check the slot count
      first** → on a correct count, never read the return code → on a wrong count, read the trailing
      digits, requiring `^[0-9]+$`.
- [ ] 1.4 Add the byte-exactness case (AC5): for a fixed happy-path envelope, all five published
      globals are byte-identical pre- and post-change, **including a value with a trailing newline
      and a value ending in the literal `X`**. This is the `HOOK_FILE_PATH` corruption a slot-count
      assertion structurally cannot see.
- [ ] 1.5 Add the forged-separator case (AC2): a `tool_input.command` containing a literal U+001E
      yields `separator` — never a success, never a forged return code.
- [ ] 1.6 Replace the comment "jq's EXIT CODE already makes the only distinction that matters" with
      the precedence rule. That comment is what let the dead branch survive review.
- [ ] 1.7 Run the full `hook-input-contract.test.sh` battery plus `scripts/test-all.sh`.
- [ ] 1.8 Ship PR 1 and merge before starting PR 2.

---

## PR 2 — classification and telemetry (Phases B2–B4). `Closes #7275`

### 2.1 Enum split

- [ ] 2.1.1 Map rc 0-with-no-output → `empty`; rc 5 → `baddoc`; rc 3 and other non-zero →
      `internal`.
- [ ] 2.1.2 Ship `internal` as a **documented defensive default**, not a peer the suite pretends to
      exercise — rc 3 is unreachable with one constant program. Assert only the reachable members.
- [ ] 2.1.3 Add the static compile assertion: a contract-test case asserting `_HOOK_INPUT_JQ`
      compiles, failing when a token in it is broken. This is the only thing that catches `internal`
      before it ships.
- [ ] 2.1.4 Verify the aggregator is undisturbed: a log carrying only the new ids exits 0 with
      `orphan_rule_ids == []` and renders the per-reason breakdown. No aggregator edit expected.

### 2.2 Type vector (ADR-157 conformance)

- [ ] 2.2.1 Extend the single jq program so the status token carries `ok` or
      `bad:<type>,<type>,<type>,<type>,<type>`. Record count stays exactly 6; field order unchanged.
- [ ] 2.2.2 Route the vector through the existing detail-suffix channel — `reason_key="${reason%%:*}"`
      already strips it for the aggregation key. No new incident-row field.
- [ ] 2.2.3 Add the canary case: `["curl","-H","Authorization: Bearer sk-LEAKCANARY"]` must produce
      no occurrence of `LEAKCANARY` in any log, stdout or stderr, while the reason names `array`.

### 2.3 Ask posture

- [ ] 2.3.1 Scope unconditional escalation to the intersection of the model-controlled reason classes
      and the hooks gating destructive/infrastructure operations. Exclude `jq_missing`
      (self-referential repair) and `internal` (our bug — fail open loudly).

### 2.4 Decisions and documentation

- [ ] 2.4.1 Write a **new ADR** declaring `Extends: ADR-156, ADR-157, ADR-165` /
      `Supersedes: nothing`. Do NOT amend ADR-157's decision in place. Cite
      `prod-write-defer-gate.sh` as the existing unrecorded narrowing.
- [ ] 2.4.2 Verify the ordinal across **every `origin/*` ref**, not `origin/main`, and re-run the
      probe immediately before merge. On renumber, sweep the plan, this file and any AC naming it.
- [ ] 2.4.3 Add an **errata note only** to ADR-157 correcting its claim that the exit-code
      distinction is made.
- [ ] 2.4.4 Split ADR-165's `unparseable` row into `empty` and `baddoc`.
- [ ] 2.4.5 Update `.claude/hooks/README.md` (reason enum + posture table).
- [ ] 2.4.6 Fix the `hooks` container description in
      `knowledge-base/engineering/architecture/diagrams/model.c4`, which asserts a uniform ADR-157
      posture that 2.3.1 falsifies.
- [ ] 2.4.7 Run `plugins/soleur/test/c4-count-parity.test.sh` and require it green.

### 2.5 Guard 5 mutation battery

- [ ] 2.5.1 Create `.claude/hooks/lib/hook-input-classification.mutation.sh` covering M1–M6 and
      H1–H3 from the plan's Guard Contract. M1 (restoring the shipped `PIPESTATUS` defect) is the
      single most valuable row — today nothing reddens on it.

---

## PR 3 — shell containment (Phases A1–A5). `Closes #7822 #7835 #7942`

### 3.1 Adoption ratchet (write before the sweep)

- [ ] 3.1.1 Create `plugins/soleur/test/shell-fixture-containment.test.sh`: enumerate
      `plugins/soleur/test/*.test.sh` suites that create a git fixture, issue a git write verb, and
      carry neither the tripwire nor a prefix scrub. Compare the live count against a committed
      baseline; assert non-increasing.
- [ ] 3.1.2 Both sides must come from the **same enumeration in the same run** — that is what makes
      it stable under predicate drift.
- [ ] 3.1.3 Fail closed when the enumeration yields zero members. Report via `printf >&2` +
      `exit 1` directly, never through the suite's own verdict helpers (ADR-193).
- [ ] 3.1.4 Cover mutation rows M1–M6 and harness rows H1–H3, including M6 (computing the baseline
      side after the sweep mutates the tree — the order property a delete-only battery never tests).

### 3.2 Sweep the three measured suites

- [ ] 3.2.1 `plugins/soleur/test/gitleaks-merge-commit.test.sh` — source `test-helpers.sh`.
- [ ] 3.2.2 `plugins/soleur/test/harvest-debt.test.sh` — source `test-helpers.sh`.
- [ ] 3.2.3 `plugins/soleur/test/roadmap-reconcile.test.sh` — source `test-helpers.sh`.
- [ ] 3.2.4 Drop the ratchet baseline to the new measured value in the same commit.

### 3.3 Vacuity repairs (the semantic half — this is the load-bearing work)

Each case asserting "no repository here" gains a positive precondition: `git rev-parse --git-dir`
must **fail** in the fixture directory before the subject is invoked.

- [ ] 3.3.1 `.claude/hooks/guardrails.test.sh` — **whole-suite**, and the one that cannot be
      deferred. `decision_of()` depends on the `mktemp -d` CWD not being a repo so branch resolution
      is empty and block-commit-on-main no-ops (isolation added by #5192).
- [ ] 3.3.2 `.claude/hooks/session-rules-loader.test.sh` — T13, T23, T30, T31.
- [ ] 3.3.3 `scripts/check-pa-22.test.sh` — self-documented inverted vacuity.
- [ ] 3.3.4 `scripts/lint-legal-registers.test.sh` — the operand case + 12 dependent red-arms.
- [ ] 3.3.5 `scripts/skill-security-scan-step-body.test.sh` — the root-commit arm (`HEAD^1`).
- [ ] 3.3.6 `apps/web-platform/infra/workspaces-luks-loopback.test.sh` — the `fatal:`-shape fsck arms.
- [ ] 3.3.7 `apps/web-platform/test/ci/service-role-allowlist-gate.test.sh` — **handle individually,
      do not batch.** It mutates the live index with `git add -f` and has no fixture repo, so under
      a hostile env its `git rm --cached -f` cleanup may not undo what it did.

### 3.4 Hostile-environment regression test

- [ ] 3.4.1 Build a victim repo, set hostile `GIT_DIR` + `GIT_INDEX_FILE`, drive a swept suite
      through a **child process** started under that env.
- [ ] 3.4.2 Assert HEAD, ref set and staged-file list unchanged **as a triple** — with `GIT_DIR`
      scrubbed, an absolute `GIT_INDEX_FILE` still retargets `git add` while HEAD stays put.

### 3.5 Mutation-battery registration (closes #7942)

- [ ] 3.5.1 Register every `plugins/soleur/test/*.mutation.sh` in `scripts/test-all.sh`. The new
      `.test.sh` needs no registration — `SUITE_GLOBS` already carries
      `plugins/soleur/test/*.test.sh` (`scripts/test-all.sh:78`).
- [ ] 3.5.2 Assert the registered set equals the tracked set, so the next battery cannot enter the
      same hole.

### 3.6 Deferrals stay owned

- [ ] 3.6.1 File the orphan-gate issue carrying R9, R10 (rotation starvation), the 12 measured orphan
      ids, the reject-before-write fix, the derive-from-three-authorities remedy, and the note that
      the Ask-3 consumer must not be a hard CI gate under ADR-091's local-producer model.
- [ ] 3.6.2 Update #7849 with the new adoption count and the twelve measured exposed TS files.
- [ ] 3.6.3 Close #7835 only if its shell half is met, re-pointing its TS half at #7849.
- [ ] 3.6.4 Verify `scripts/lint-agents-rule-budget.py` reports a `B_ALWAYS` no larger than before.
      No new AGENTS.md rule — the corpus is at its ratchet.
