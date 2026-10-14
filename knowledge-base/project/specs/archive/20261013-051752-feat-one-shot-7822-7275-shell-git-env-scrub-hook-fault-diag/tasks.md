# Tasks — shell git-fixture containment, and a diagnosable hook_self_fault

Derived from
`knowledge-base/project/plans/2026-09-08-fix-shell-git-env-scrub-and-hook-fault-diagnosis-plan.md`.
Two PRs. PR 1 must merge before PR 2 begins.

lane: cross-domain
brand_survival_threshold: single-user incident

---

## Phase 0 — preconditions (measure; do not assume)

- [ ] 0.1 Re-run the `PIPESTATUS`-through-command-substitution probe. If `jq_rc` is not always 0 on
      the machine of record, **stop** — R6 has not reproduced and the design must be re-derived.
- [ ] 0.2 Re-run the strip-before-split probe and paste its table into PR 1: happy=6 fields/rc 0,
      empty stdin=0/rc 0, `garbage {{`=0/rc 5, escaped-RS=7/rc 0, valid+trailing-garbage=6/rc 5.
      The whole probe must run under `set -euo pipefail`.
- [ ] 0.3 Re-derive the sweep set with the pinned predicate (creates a git fixture, issues a git
      write verb, carries none of: a `source` of `test-helpers.sh`, `exit 97`, a `GIT_` prefix
      scrub). The count moved three times during planning — do not trust the plan's list.
- [ ] 0.4 Re-run `scripts/rule-metrics-aggregate.sh` against a **copy** of the live incidents log
      under `INCIDENTS_REPO_ROOT`. Never the real repo root — it writes before it rejects.
- [ ] 0.5 Confirm #7849 and #7835 are still open. (#7942 is OUT OF SCOPE — see session-state.md
      §Scope decision. Also confirm PR #7879 is still open; if it has merged, re-check whether the
      A1/A2 sets moved before editing.)

---

## PR 1 — the classifier (Phases B1–B2). `Ref #7275` (NOT `Closes`: Asks 2 and 3 are deferred)

### 1.1 Repair the discriminator (B1)

- [ ] 1.1.1 Write the failing cases FIRST, through **stdin** (a second `jq` is forbidden by the
      contract): empty stdin observes rc 0; `{"a":"x"` observes rc 5. Both must fail against current
      code. Record before/after readings for the PR body.
- [ ] 1.1.2 Capture jq's return code **inside** the command substitution using `$?`, not
      `PIPESTATUS` — jq is the last pipeline element, and `PIPESTATUS[1]` encodes a positional
      invariant that breaks when anyone appends a filter.
- [ ] 1.1.3 **Strip before split.** `jq_rc=${raw##*RS}`; `body=${raw%RS*}`; split `$body`. Do NOT
      append the rc and then split — that makes the happy path 7 fields AND makes the zero-field arm
      structurally unreachable, so every payload fault would be misreported as `internal`.
- [ ] 1.1.4 Keep the sentinel `printf` as the **last command inside the substitution**; under
      `set -euo pipefail` a non-zero final status kills the hook at the assignment.
- [ ] 1.1.5 Require `type == "object"` on the document root before the accessors. Today a `null`
      root returns 0 with all five fields empty — a silent full disarm with no incident row.
- [ ] 1.1.6 Classify a non-zero return code even when the field count is correct (valid envelope +
      trailing garbage → 6 fields, rc 5). Leaving it unclassified is a fault-suppression channel.
- [ ] 1.1.7 A trailing field failing `^[0-9]+$` is classified `internal`, never a payload class.
- [ ] 1.1.8 Replace the comment "jq's EXIT CODE already makes the only distinction that matters".
      Write the true invariant: the rc is final by construction because it is printed after jq exits
      in the same subshell; the count is read first so a forged separator degrades to `separator`.
- [ ] 1.1.9 Byte-exactness battery (AC4): `/tmp/aX`, `/tmp/f1` (trailing digit), `5` (all digits),
      `ls\n` (trailing newline), **absent `file_path` so slot 5 is empty**, and one payload carrying
      both an `X`-terminated value and an escaped RS. Place the pathological value in slot 5 and in
      slot 1. Assert `no-memory-write.sh` and `kb-domain-allowlist-guard.sh` still resolve
      `TARGET="${HOOK_FILE_PATH:-$HOOK_CMD}"` to the command on the empty-slot payload.

### 1.2 Split the reason enum (B2)

- [ ] 1.2.1 zero fields + rc 0 → `empty`; zero fields + rc 5 → `baddoc`; rc 3 → `internal:rc3`;
      partial block → `internal:count`.
- [ ] 1.2.2 Keep the two `internal` arms **distinguishable**. A broken program emits nothing, so
      after the strip it yields zero fields and rc 3 — but a partial block yields 1..n-1 fields and
      no rc signal. A bare `internal` would let the count branch satisfy the assertion while the
      rc-3 arm stayed dead. Add a positive control proving rc-3 is reachable.
- [ ] 1.2.3 Verify the aggregator is undisturbed: a log carrying only the new ids exits 0 with
      `orphan_rule_ids == []` and renders the per-reason breakdown.
- [ ] 1.2.4 Update `scripts/rule-metrics-aggregate.sh`'s inline enum roster and the
      `hook-input-unparseable` fixture in its test — **documentation only**, no behavioural change.
- [ ] 1.2.5 Update `.claude/hooks/README.md`'s reason enum.
- [ ] 1.2.6 Add the **errata note only** to ADR-157 correcting its claim that the exit-code
      distinction is made. Do NOT amend its decision, and do NOT claim a new ordinal — the posture
      work that would have needed one is deferred.
- [ ] 1.2.7 Assert `hook_input_emit_ask`'s stdout parses under `jq empty` for every producible
      reason. A malformed envelope is silently ignored by Claude Code, so the tool would run with
      neither a prompt nor guards.

### 1.3 Mutation battery

- [ ] 1.3.1 Create `plugins/soleur/test/hook-input-classification-mutation.test.sh` covering M1–M12
      and H1–H6 from the plan's Guard Contract. Note the name: `*-mutation.test.sh`, **not**
      `*.mutation.sh` — the former is already matched by `SUITE_GLOBS`' `plugins/soleur/test/*.test.sh`
      so it is gated on arrival with no edit to `scripts/test-all.sh`; the latter is the ungated hole.
      **Not** under `.claude/hooks/lib/` either — that path is outside the glob entirely.
- [ ] 1.3.2 Scope every mutant to a **line range** with its placement asserted. The file carries two
      byte-identical `HOOK_INPUT_REASON="internal"` assignments and three occurrences of
      `unparseable` (one classifier, two log strings); a file-wide `sed` hits the wrong one.
- [ ] 1.3.3 Run an unmutated GREEN control first and abort if the baseline is red.
- [ ] 1.3.4 M2 is the new load-bearing row: strip the rc **after** the split → must redden.

---

## PR 2 — shell containment (Phases A1–A3). `Closes #7822 #7835`

### 2.1 Vacuity repairs (the semantic half — do this first)

Each case gains a **three-part** precondition run under the subject's own env and CWD: the probe
*succeeds* in a known repo, *fails* in the fixture dir, and the failure text names
`not a git repository`. A bare non-zero exit is satisfied by `git` missing, the dir not existing, or
EACCES.

- [ ] 2.1.1 `.claude/hooks/guardrails.test.sh` — **whole-suite, cannot wait.** Its precondition is
      **not** repo-ness: `decision_of()` depends on *branch resolution being empty* so
      block-commit-on-main no-ops (#5192). A detached HEAD in a real repo also yields an empty
      branch. Assert branch resolution is empty AND the gate is observed to no-op.
- [ ] 2.1.2 `scripts/skill-security-scan-step-body.test.sh` — assert **`HEAD^1` is unresolvable**,
      not repo-ness.
- [ ] 2.1.3 `.claude/hooks/session-rules-loader.test.sh` — T13, T23, T30, T31.
- [ ] 2.1.4 `scripts/check-pa-22.test.sh` — prefer asserting the SUT's own resolution names the
      fixture.
- [ ] 2.1.5 `scripts/lint-legal-registers.test.sh` — the operand case + 12 dependent red-arms.
- [ ] 2.1.6 ~~`apps/web-platform/infra/workspaces-luks-loopback.test.sh`~~ — **DROPPED.** Open PR
      #7879 edits this file; leave it to that PR. Do not touch it.
- [ ] 2.1.7 `plugins/soleur/test/proc.test.sh` — the `NOGIT="$(mktemp -d)"` case.
- [ ] 2.1.8 `apps/web-platform/test/ci/service-role-allowlist-gate.test.sh` — **handle
      individually.** It mutates the live index with `git add -f` and has no fixture repo, so under
      a hostile env its `git rm --cached -f` cleanup may not undo what it did.
- [ ] 2.1.9 For `.claude/hooks/` suites the remedy is the precondition **only** — no suite there
      carries the tripwire, and the tree's pattern is an inline byte-pinned copy, not a cross-tree
      `source`.

### 2.2 Sweep the measured suites (A2)

- [ ] 2.2.1 Source `test-helpers.sh` in each member of the re-derived sweep set (planning measured
      five: `gitleaks-merge-commit`, `harvest-debt`, `roadmap-reconcile`,
      `fixture-dir-operand-assert`, `proc`).
- [ ] 2.2.2 Verify each still passes. Sourcing is **not** additive — `test-helpers.sh` carries
      `set -euo pipefail` and a `PASS`/`FAIL` harness that two of the five do not use.
- [ ] 2.2.3 Record the new adoption count in #7849.

### 2.3 Containment regression test (A3)

- [ ] 2.3.1 Create `plugins/soleur/test/shell-fixture-containment.test.sh`. Auto-registers via
      `SUITE_GLOBS`.
- [ ] 2.3.2 **Refusal arm:** tripwire armed + hostile `GIT_DIR`/`GIT_INDEX_FILE` → assert the child
      exits **97**.
- [ ] 2.3.3 **Containment arm:** tripwire disarmed via `SOLEUR_GIT_TRIPWIRE_ALLOW=1` + hostile env →
      assert the child exits **0** AND the victim's HEAD, refs and staged list are unchanged as a
      triple. This is the arm where the scrub is actually under test.
- [ ] 2.3.4 Demonstrate that a victim-state-only version passes with an entry-point `unset`
      removed — that is the false-green the two arms exist to exclude.
- [ ] 2.3.5 Victim path passes an `assert_fixture_dir`-class operand guard; the hostile `GIT_DIR`
      must never resolve under `$PWD`.

### 2.4 CUT — mutation-battery registration (was A4, #7942)

- [x] 2.4.1 **CUT.** `scripts/test-all.sh` and `plugins/soleur/test/test-helpers.sh` are edited by
      open PR #7879; this PR must not contend for them. #7942 stays open on its own trigger.
- [ ] 2.4.2 Instead, create the new battery as
      `plugins/soleur/test/hook-input-classification-mutation.test.sh` so the existing
      `plugins/soleur/test/*.test.sh` glob gates it with **no** edit to `scripts/test-all.sh`.
- [ ] 2.4.3 Assert the PR's diff touches neither `scripts/test-all.sh` nor
      `plugins/soleur/test/test-helpers.sh`.

### 2.5 Deferrals stay owned

- [ ] 2.5.1 File the follow-up issue carrying: the orphan gate (reject **before** the write; derive
      "known" from `AGENTS.md` + `scripts/retired-rule-ids.txt` + hook-declared ids; the 12 measured
      orphan ids; rotation starvation, R10); the type vector with its measured defects (cannot emit
      `null`; composing the reason from jq output removes the closed-enum property that keeps two
      unescaped sinks safe, one of which can flip `ask` into `allow`); the ask posture (`empty` is a
      *persistent* class and must be excluded alongside `jq_missing`; multi-hook `ask` is unprobed;
      policy belongs at the call site via a flag, not a roster in the parse library; it needs a new
      ADR declaring `Extends`, never an in-place amendment; the `prod-write-defer-gate.sh` precedent
      is false); and the consumer redesign (not a hard CI gate — ADR-091 makes the producer local).
      Note #7219 (open) as the responder-set sweep the posture work will need.
- [ ] 2.5.2 Update #7849 with the new adoption count and the twelve measured exposed TS files.
- [ ] 2.5.3 Close #7835 only if its shell half is met, re-pointing its TS half at #7849.
- [ ] 2.5.4 Verify `scripts/lint-agents-rule-budget.py` reports a `B_ALWAYS` no larger than before.
      No new AGENTS.md rule — the corpus is at its ratchet.
