# Tasks — fix #6771: CI workflow FILENAME satisfies the infra-imperative sentinel

Plan: `knowledge-base/project/plans/2026-07-20-fix-lint-infra-workflow-filename-false-positive-plan.md`
Branch: `feat-one-shot-6771-lint-infra-workflow-filename-fp`
Lane: `procedural`

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- No infrastructure in this change: a CI lint script and its test fixtures only. -->

## Phase 1 — RED: regression tests first

- [x] 1.1 Read `scripts/lint-infra-no-human-steps.test.sh` end to end; note the `mkcase` /
      `run_case` helpers and the trailing `MIN_CASES=30` cardinality guard.
<!-- lint-infra-ignore start: tasks 1.2-1.8 SPECIFY TEST FIXTURES for the linter under
     repair. Each quoted string is scanner input paired with the exit code it must produce —
     the sentinel's own test corpus, not steps anyone performs. -->
- [x] 1.2 Append the negative control: a case whose body cites `apply-web-platform-infra.yml`
      beside the word `operator`, using the #6749 repro text verbatim. Expect exit **0**.
- [x] 1.3 Append the positive control: a case asserting a human personally runs
      `terraform apply` during the window. Expect exit **1**.
- [x] 1.4 Append the filename-class breadth case: a line citing a hypothetical
      `reboot-web-hosts.yml` beside `operator`. Expect exit **0**.
- [x] 1.5 Append the glob-form case. Shipped as F4 using `reboot-*.yml`, NOT the plan's
      `destroy-*.yml`: bare `destroy` is not an imperative (it requires a terraform/tofu
      prefix), so a `destroy-*` fixture passes with or without the `*` in the char class
      and pins nothing. Rationale recorded at the F4 site. Expect exit **0**.
- [x] 1.6 Append the anchored-`-target` case: an actor line containing
      `` `terraform -target=x apply` `` performed by hand. Expect exit **1**.
- [x] 1.7 Append the adjacency-hazard guard: `The operator runs terraform pipeline.yml applies cleanly.`
      Expect exit **0**. This case is the ONLY mechanical detector of an empty-string
      substitution in 2.2 — do not drop it.
- [x] 1.8 Append the actor-side neutralization case: a line citing a hypothetical
      `operator-digest.yml` beside `terraform apply`. Expect exit **0**.
- [x] 1.8b Append the `.yaml` long-form case: `reboot-web-hosts.yaml` beside `operator`.
      Expect exit **0**. Load-bearing — an implementation whose fast path tests only
      `".yml"` passes every other case here and is still broken for `.yaml`.
<!-- lint-infra-ignore end -->
- [x] 1.9 Raise `MIN_CASES` from 30 to **39**. The plan said 37 ("plus 7 new"), but
      tasks 1.2-1.8b enumerate **8** cases (1.8b was added during deepen-plan and the
      arithmetic was not re-run), and F9 makes 9. Derived from the as-written file, not
      the prose. A guard left at the old floor is a guard that has stopped guarding.
- [x] 1.10 Run `bash scripts/lint-infra-no-human-steps.test.sh`. Expect **exactly three**
      RED: 1.2 (negative control), 1.4 (breadth), 1.8 (actor-side) — 1.5/1.8b share the
      breadth mechanism. Tasks 1.3, 1.6, 1.7 already pass today; they are regression
      guards, not new coverage. Record the RED output.

## AMENDMENT — CTO ruling supersedes Phase 2.1 and most of Phase 3

The plan made **option 2** (anchoring `-target … apply` on terraform/tofu/opentofu
adjacency) the primary fix, on a measured "~45 latent false positives removed".
That premise is empirically false and the anchor was **reverted**.

Measured at production scan scope (`SCAN_DIRS` only), all arms on one tree:

| arm | unique flagged | removes |
|---|---|---|
| baseline (`origin/main`) | 478 | — |
| option 1 only (filename neutralization) | 470 | 8 |
| option 1 + 2 (anchor) | 429 | 41 more |

Reading the 41: roughly **40% are GENUINE human-run infra steps**, silenced
because the natural phrasing omits the tool name — `runbooks/git-data-luks-cutover-5274.md:50`
("a FULL operator apply"), `2026-07-07-fix-zot-doppler-registry-isolation-plan.md:410`
("stage the operator apply", already CTO-ruled genuinely operator-run),
`2026-05-20-infra-apply-web-platform-infra-workflow-plan.md` ("operator … applies
the new resource manually").

Ruling: **ship option 1 only** — the order the issue author originally proposed.
False positive = author friction; false negative = a non-technical operator meets
an un-automated infra step. Resolve toward sensitivity. A carve-out is at least
auditable; a silent miss is not.

Consequences for the tasks below:
- **2.1 is REVERTED** (the anchor is gone; the imperative keeps its original form
  with a comment recording why it must stay un-anchored).
- **Phase 3 is re-derived**: 2 regions are freed under option-1-only semantics,
  not 7. The 7-region sweep was validated under the anchored script and 5 of
  those files flagged again once the anchor was removed.
- **F9 replaced**: it asserted bare `-target` must NOT flag (wrong under the
  ruling). It is now a positive control lifted verbatim from the cutover runbook,
  containing no `terraform` token — the fixture whose absence let the anchor pass
  review, mutation-verified to go RED if the anchor returns.

## Phase 2 — GREEN: the fix

- [~] 2.1 REVERTED per CTO ruling (see AMENDMENT) — In `scripts/lint-infra-no-human-steps.py`, anchor the last `IMPERATIVE_RES` entry
      on the tool: `r"-target\b.*?\bappl(?:y|ies|ied)\b"` →
      `r"\b(?:terraform|tofu|opentofu)\b.*?-target\b.*?\bappl(?:y|ies|ied)\b"`.
- [x] 2.2 Add module-level `YAML_FILENAME_RE = re.compile(r"\b[\w.*-]+\.ya?ml\b", re.IGNORECASE)`
      and `_neutralize_filenames(text)`. The fast path MUST test **both** `".yml"` and
      `".yaml"` — a `.yml`-only check is silently broken for `.yaml` while every `.yml`
      fixture still passes. Substitute `"_"` — **never** `""` (see plan §Sharp Edges:
      deleting the span can create matches by adjacency).
- [x] 2.3 In `scan_text` step 5, compute `scan = _neutralize_filenames(raw)` **once** and pass
      it to both `_has_actor` and `_has_imperative`. Do NOT neutralize inside the predicates —
      that is the measured 32 s → 75 s regression.
- [x] 2.4 Amend the module docstring's "Detection is on the RAW line" paragraph to record the
      exception AND why it is not a contradiction: a backtick span can contain a command, so
      stripping it would hide real imperatives; a filename never can — it names automation,
      it does not instruct (#6771). Follow the `_normalize` shape at `scripts/lint-rule-bodies.py:97`
      (module-level pure `str -> str` with a one-line docstring).
- [x] 2.5 Re-run `bash scripts/lint-infra-no-human-steps.test.sh` — all cases green, `FAIL=0`.

## Phase 3 — Carve-out sweep

- [x] 3.1 Re-locate each of the 7 regions by its start-marker **content anchor**, not the line
      number in the plan table (numbers drift as edits land).
- [x] 3.2 Remove the paired ignore comments (keeping body prose). The plan's 7-region
      list was derived under the anchored script; under option-1-only only **2** regions
      are freed, verified by removing each region's markers and linting the WHOLE file:
      `2026-07-18-fix-6649-workspaces-luks-escrow-autonomy-plan.md` (region 2 of 3) and
      `feat-one-shot-6297-anthropic-key-missing-false-page/tasks.md` — the latter being
      the carve-out PR #6749 added for this exact defect, which is the one the issue cites.
      The plan's other 5 named regions still flag and are correctly retained.
- [~] 3.3 SUPERSEDED (that region is retained anyway under option-1-only) — Do NOT remove the earlier region in
      `2026-07-12-feat-inngest-op-arm-no-ssh-doppler-arm-flip-plan.md` — it scans clean in
      isolation but still flags in context via the adjacency rule. Add a one-line inline note
      recording why it is retained.
- [x] 3.4 After each removal, run the linter on the **whole file** (not the region body) and
      confirm exit 0. In-context verification is the only valid check here.

## Phase 4 — Verify

- [x] 4.1 `bash scripts/lint-infra-no-human-steps.test.sh` → exit 0, `FAIL=0`, `TOTAL` matches
      the new `MIN_CASES` (**39**, derived — see 1.9).
- [x] 4.2 Full scan violation count drops by **8** (478 -> 470), NOT the ~49 the plan
      predicted — ~49 was the opt1+opt2 figure and opt2 was reverted (see AMENDMENT).
      Compute the delta on this machine in this run; do NOT assert absolute counts, the
      corpus drifts (this PR adds its own plan + spec into scan dirs) and observed
      baselines vary 32-73 s across hosts.
- [x] 4.3 Run BOTH scripts on the **pre-sweep tree** (before Phase 3) and confirm the
      post-fix hit set is a strict **subset** — zero newly-flagged lines. Doing this after
      the sweep corrupts the comparison: removing carve-outs legitimately adds hits under
      the old script.
- [x] 4.4 Time both arms in the same run; assert post-fix ≤ **1.25×** the baseline measured
      alongside it. No absolute second-count.
- [x] 4.5 `bash scripts/test-all.sh` passes.
- [x] 4.6 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` is clean
      on this PR's own diff — this PR edits files under the scan dirs and must not trip its
      own gate.
- [x] 4.7 Confirm both new artifacts (this file and the plan) lint clean under the patched
      script; they quote fixture prose and rely on their ignore regions.

## Out of scope

- The ~52 other `lint-infra-ignore` regions: measured, each still flags post-fix — they
  suppress genuine co-occurrence unrelated to this defect. No follow-up issue.
- The marker-in-prose meta-trap (writing the literal start comment opens a real region).
  Recorded in the plan's Sharp Edges; open a follow-up only if it recurs.
