# Tasks — feat-one-shot-6997-7002-7024-gate-preamble-actionlint-sigpipe

Derived from
[`knowledge-base/project/plans/2026-07-28-fix-fail-open-gate-preamble-actionlint-deadlock-sigpipe-assertions-plan.md`](../../plans/2026-07-28-fix-fail-open-gate-preamble-actionlint-deadlock-sigpipe-assertions-plan.md)
(v3, post six-agent plan-review).

`Closes #6997` · `Closes #7002` · `Closes #7024`

> **Read the plan's § Verified Facts and § Plan-Review Revisions before starting.** Six reviewers falsified
> five of the original premises, including two of three "RED-first" claims and the derivation command
> ADR-149 publishes. Working from the issue text instead of the plan will reproduce those errors.

---

## Phase 0 — Preconditions and issue filing

- [x] **0.1** Run the corrected derivation and paste the output into the PR body. Expect **11** paths.
      **`xargs -r` and the `^\s*` call anchor are both load-bearing** — the `grep -L` form goes vacuous once
      gates carry the `declare -F` guard, and a bare `xargs` on an empty stage makes `grep -L` read stdin.
      ```bash
      grep -l "local plan_json" tests/scripts/lib/*gate*.sh \
        | xargs -r grep -LE '^\s*plan_gate_assert_readable'
      ```
      If the count is not 11, **stop and re-plan** — the tiering is keyed to it.
- [x] **0.2** Record the pre-work baseline: `TEST_GROUP=scripts bash scripts/test-all.sh`.
      Expect **225/225 green, ~417 s**. Zero pre-existing failures ⇒ any later red is ours.
- [x] **0.3** Reproduce the actionlint hang and the pipe buffer. **Never read `$?` after a pipe** —
      `actionlint … > /tmp/al.out 2>&1; rc=$?`.
- [x] **0.4** Read `tests/scripts/test-git-data-host-birth-gate.sh:664-760` and
      `tests/scripts/test-plan-gate-preamble.sh`. Task 1.5 extracts that harness — **do not write a new one**.
- [x] **0.5** Read `.claude/hooks/grep-q-pipe-guard.test.sh`. Task 7.5 edits its pathspec, nothing more.
- [x] **0.6** File the four deferral issues (plan Non-Goals 1-4). Tasks 5.1/5.2 and 1.6 must cite real
      numbers, so this cannot be left to the end.
  - [x] 93 actionlint findings census (SC2016 ×62 benign; SC2086 ×5 / SC2015 ×2 carry real risk)
  - [x] Tier-2 residual holes — **record that `stock-preflight-gate.sh` is sourced 8×**, plus the concrete
        re-evaluation trigger and the two rejected alternatives
  - [x] Gate-call-site rc lint, with the **corrected census** (19 `if !` sites + the `bash …-gate.sh` shape
        at `:712`), scoped to `.github/workflows/**`
  - [x] (cross-link only) comment on **#7005** — see 9.2

## Phase 1 — Helper, harness, drift check *(blocking precondition for Phase 3)*

- [x] **1.1** RED first: add a `"actions": [["delete"]]` arm to `tests/scripts/test-plan-gate-preamble.sh`;
      run against the **unmodified** helper; record the failure.
- [x] **1.2** Add `and all(.change.actions[]; type == "string")` to `plan_gate_assert_classifiable`.
      **ADDITIVE — do NOT remove `(.change.actions | length) > 0`** (already at `:104`). `all` over an empty
      stream is vacuously true, so only `length > 0` rejects `"actions": []`. Say so in the comment.
- [x] **1.3** Add `?` to the offender-extraction filter at `:106` (currently bare `.change.actions`).
      Without it a scalar `.change` makes the extraction raise → jq exits 5 → `2>/dev/null` swallows it →
      the ABORT names **no offender**.
- [x] **1.4** **Consumer-regression gate:** `test-plan-gate-preamble.sh` **and**
      `test-git-data-host-birth-gate.sh` both green **before Phase 3 opens**.
- [x] **1.5** Extract `tests/scripts/lib/gate-suite-harness.sh` (`mk_plan`, `rc_entry`, `rc_noactions`,
      `check`, `mutate_and_check`, `mutate_layered` + their `cmp -s` floors). **Migrate
      `test-git-data-host-birth-gate.sh` onto it first** — its 55 arms must stay green, which makes the
      migration self-proving. Build the D1-D6 corpus **once per run**, not per suite.
- [x] **1.6** Add the drift check **inside `test-plan-gate-preamble.sh`** (~10 lines, no new file):
      corrected derivation; empty except a two-element exclusion array citing the Non-Goal 2 issue;
      **≥ 12 files scanned**; and no `tests/scripts/lib/*.sh` carrying `local plan_json` outside the
      `*gate*` glob.

## Phase 2 — Degraded-plan fixtures *(in the shared harness)*

- [x] **2.1** Add **D5** (`"actions": []`) and **D6** (`.change` = scalar `42`) explicitly to
      `test-plan-gate-preamble.sh`. D1-D4 equivalents already exist there (`:77`, `:83`, `:89`, `:99`,
      `:107-120`).
- [x] **2.2** Expose D1-D6 from the shared harness for per-gate use. **Fixtures are synthesized, never
      captured** (`cq-test-fixtures-synthesized-only`).

## Phase 3 — Retrofit the 8 live gates *(7 Tier-1 + `web-host-birth`)*

Order by blast radius: `git-data-host-replace`, `workspaces-luks-recut`, `workspaces-luks-cutover`,
`registry-luks-recut`, `registry-region-migrate`, `registry-host-replace`, `inngest-host-replace`,
then `web-host-birth`.

- [x] **3.1** Per gate, four arms via the shared harness (~10 lines each):
  - **A1 = D5** → ABORT · **A2 = D6** → ABORT · **A3 = happy** → still PASS · **A4 = `mutate_layered`**
  - **Anchor A1/A2/A4 on preamble-distinctive text** (`unclassifiable plan entry`,
    `Fail-closed: an unreadable plan is not evidence of a safe one`) **plus** the gate name.
    **A gate-name-only anchor binds nothing** — the gates' own pre-existing aborts also carry it.
  - **A1/A2 RED pre-retrofit; A3 GREEN before and after; A4 only meaningful after 3.2.**
    *(Do NOT use D1/D2 — all nine gates already abort on them.)*
- [x] **3.2** Add the guarded source at file scope (copy `git-data-host-birth-gate.sh:72-77`, resolving via
      `${BASH_SOURCE[0]}`).
- [x] **3.3** Add the asserts as the **first statements inside the gate function**, with `|| return 1` on
      each. *(Reason: they consume `$plan_json`, a function parameter that does not exist at file scope —
      **not** because file scope fails open; `set -e` is re-enabled before every source.)*
- [x] **3.4** Route every counter through `plan_gate_assert_numeric`, **replacing** any hand-rolled
      `^[0-9]+$` loop. Add **A5** where this changes a gate.
- [x] **3.5** Delete the redundant inline checks **and migrate the suite messages that assert them** —
      `test-registry-luks-recut-gate.sh:284,287` assert the gate's own `plan JSON not found` /
      `jq evaluation failed`. **Sweep all eight suites for those two strings first.**
- [x] **3.6** Re-run: all arms green, all pre-existing arms green.
- [x] **3.7** `web-host-birth-gate.sh` — **RED-prove D5 and D6 first**; D5 is the measured `web-1` hole and
      the pre-fix PASS must be recorded.

## Phase 4 — `web2-retire-gate.sh` *(blast radius zero — last)*

- [x] **4.1** Retrofit per 3.2-3.6. **No new suite.** Add A1-A4 to
      `tests/scripts/test-destroy-guard-counter-web-platform.sh` (already sources it via
      `WEB2_RETIRE_GATE_LIB`, already registered). Note in the gate header that it is **test-only**.

## Phase 5 — Prose corrections

- [x] **5.1** `plan-gate-preamble.sh` header — post-retrofit counts; **replace the published derivation
      command** with the corrected one and explain why `grep -L` goes vacuous; keep "re-derive, do not
      remember"; name the residual two citing the Non-Goal 2 issue; add the caller-must-check-rc line.
- [x] **5.2** `ADR-149-…md` `## Consequences` (`:233`) — same counts and command, **and correct the
      sentence at `:247-248`** claiming the three carry equivalent checks / "pure deletion". Record the
      8× call-site count for `stock-preflight-gate.sh`.
- [x] **5.3** Re-run the quoted command; the quoted output must match.
- [x] **5.4** Author the new ADR via
      `/soleur:architecture create 'Extract cutover-inngest run body to a checked-in script'`.

## Phase 6 — #7002 extraction *(two commits)*

**Commit 6a — verbatim. Nothing else in this commit.**

- [x] **6.1** Parse `git show origin/main:.github/workflows/cutover-inngest.yml` with python3+PyYAML;
      record the `run:` scalar's SHA-256 and byte count. **Measure — do not hardcode.**
- [x] **6.2** Create **`scripts/cutover-inngest.sh`** = shebang + the parsed scalar **byte-for-byte**.
      No dedent, no normalization. The body's existing `set -euo pipefail` travels with it — **do not add a
      second**. *(`scripts/`, not `.github/scripts/` — that tree is six `check-*` PR-quality guards feeding
      a required check.)*
- [x] **6.3** Reduce the step to `run: bash "${GITHUB_WORKSPACE}/scripts/cutover-inngest.sh"`, keeping
      `name:` and `env:`. **`if:`/`timeout-minutes:` are job-level, not step-level.**
      **Same commit:** rewrite the checkout step's name and comment to state it is required by **all** ops.
- [x] **6.4** Re-parse both sides; assert **byte-identical, no normalization**.

**Commit 6b — triage.**

- [x] **6.5** `shellcheck scripts/cutover-inngest.sh` completes; record findings; fix correctness only.
- [x] **6.6** `timeout 60 actionlint .github/workflows/cutover-inngest.yml` → rc ∈ {0,1}, never 124.
- [x] **6.7** Baseline = **the other 68 workflows** (main's full-corpus run *hangs*). Findings newly visible
      on `cutover-inngest.yml` are **not** regressions — record separately.
- [x] **6.8** Confirm `apply-inngest-rls-dev-workflow.test.sh:8` and `scan-workflow.test.sh:6` still hold.

## Phase 7 — #7024

- [x] **7.1** Build the **synthetic** RED harness: a **>65,536-byte** producer with an early match; assert
      the pipeline status is **141**. *(The real inputs cannot produce it — 16,892 B vs a 65,536 B buffer.)*
- [x] **7.2** Apply the blessed forms: herestring, or `[ "$(producer | grep -Ec 'PAT' || true)" -gt 0 ]`.
      **The `|| true` is required.**
- [x] **7.3** `phase-16.test.sh` — convert all 11 sites (L93, L202, L300, L302, L304, L306, L320, L335,
      L337, L339, L356). **Leave `:294-295`'s `| head -1`** to #7005; label it *deferred fail-open*.
- [x] **7.4** `test-sentry-full-root-apply.sh` — rewrite `_has_executable_target` to drop the pipe; convert
      L116/L128-129/L139 to herestrings; **add a top-injection mutation arm** (documented green-both-ways).
- [x] **7.5** Extend `.claude/hooks/grep-q-pipe-guard.test.sh`'s pathspec at `:33` by one line + update its
      header scope note. **Do not promote it to `scripts/`** — the pattern matches comments and would match
      its own probe at `:50`.

## Phase 8 — Durable guard

- [x] **8.1** Add the **actionlint hang guard** to `ci.yml` beside the existing `Lint …` steps: install
      actionlint (pinned release), `timeout 120`, fail **only** on `rc=124`. RED-proof it against
      `origin/main`'s pre-extraction workflow.
- [x] **8.2** Add `scripts/lint-workflows.sh` (~20 lines, **no `.test.sh`**): `timeout`-wrapped, never
      piped into `head`/`tail`, prints `rc`, distinguishes 124, **exits 0 on both 0 and 1**.

## Phase 9 — Exit gate

- [ ] **9.1** `bash scripts/test-all.sh` green across all shards vs the 0.2 baseline (**225/225, 416.9 s**).
- [ ] **9.2** Comment on **#7005** with removed sites, re-scoped remainder, and **corrected corpus numbers**
      (583 `*.test.sh`, not 157). All deferrals `Refs #<N>` — **never `Closes`**.
- [ ] **9.3** PR body = **one-shot measurements only** (~1 screen). Per-arm RED/GREEN evidence stays in CI —
      the shared harness prints it.
- [ ] **9.4** Append to `decision-challenges.md` (exists: DC-1…DC-5).
- [ ] **9.5** PR body carries `Closes #6997`, `Closes #7002`, `Closes #7024`, each on its own line, plus the
      note that **#7024's title has the fail-open/fail-closed direction backwards**.

---

## Traps this plan already paid for

| Trap | Rule |
|---|---|
| `xargs` on an empty stage | always `-r` — otherwise `grep -L` reads **stdin** |
| `grep -L <symbol>` as an "is it called?" check | it is a **presence** check; the `declare -F` guard satisfies it. Anchor `^\s*<symbol>` |
| Anchoring a mutation arm on the gate name | the gate's **own** aborts carry it — anchor on preamble-distinctive text |
| `grep -c` / `git grep` in an absence-AC | they exit **1** on zero matches — `\|\| true` or compare a captured count |
| Normalizing whitespace in a "verbatim move" diff | normalization hides the exact error it should catch — parse the YAML scalar, compare bytes |
| Reading `$?` after a pipe | reports the **tail's** status |
| Demanding `rc=141` from a real `grep -q` site | needs a producer **larger than the 65,536-byte buffer** |
| Appending a mutation match at the bottom | `grep -q` only early-closes on an **early** match |
| Narrow `-q` in the ban pattern | misses `-Eq`/`-iq`/`-Fq` — use `-[A-Za-z]*q` |
| "Tier 2 = low priority" | `stock-preflight` is tier-2 and sourced **8×**; `web2-retire` is tier-1 and sourced **0×** |

---

## Plan deviations found by measurement during /work

Every one of these was a plan claim that measurement falsified. They are recorded here
rather than silently absorbed, because asserting an unmeasured property is the defect
class all three issues are about.

| # | Plan said | Measured | What changed |
|---|---|---|---|
| D1 | Task 1.3: a scalar `.change` makes the offender-extraction raise, so add `?` to `.change.actions` | **False.** jq's `or` short-circuits, so the `(.change \| type) != "object"` disjunct already guards it; the `?` is a no-op on every shape tested | Fixed the REAL blank-offender hole instead: a non-object ELEMENT of `resource_changes` (raises one level up, at `.change`). Guarded the element type + `.address? // "<entry with no address>"` |
| D2 | `registry-luks-recut`'s counter list (derived from its abort message) | `arm` is a STRING discriminant, never in the original numeric loop | Dropped from the `plan_gate_assert_numeric` call. All 9 gates' assert lists then diffed against their original loops: 9/9 exact |
| D3 | Task 6.2 / V10: the cutover body has no `::add-mask::` | **4 live `printf '::add-mask::'` calls** | Extraction still safe, but for a different reason than asserted — workflow commands are parsed from the STEP's stdout, which a child inherits. Recorded in ADR-150 |
| D4 | Task 8.1: `timeout 120 actionlint .github/workflows/` | actionlint takes FILES; a directory exits **3** | The prescribed guard would print "rc=3 … acceptable" and pass having linted NOTHING. Fixed with a `*.yml` glob, a catch-all `*)` rc arm, and a ≥40 file floor |
| D5 | V12 / DC-5: SIGPIPE is "structurally unreachable" in `test-sentry-full-root-apply.sh`; 10/10 runs returned 0 | **2 of 100 runs return 141.** Under-buffer size makes the race narrow, not impossible — `grep -q` exits first and the producer's unfinished write takes EPIPE | Reclassified from latent shape to **live fail-open** (~2%, in a positive predicate, on the #6074 destroy-reachability guard). The 10-run sample had ~82% chance of missing it |
| D6 | Task 6.8: the two suites asserting "actionlint runs in ZERO workflows" need no edit | True for their *logic*, but Phase 8.1 makes the CLAIM false | Corrected the prose in both suites and in ADR-030; rationale for those guards is unchanged and restated |
| D7 | Plan §V15 / Task 0.2: scripts shard is "225/225 in ~417 s" | 225/225 confirmed; runtime far longer under load + a blocked sibling run | Suite count was right; the timing figure is not a usable baseline |
| D8 | Task 7.1: build a synthetic >65,536-byte producer | A `cat`-based producer yields 141 in **0/50** runs; `grep -v` yields it in **50/50** | The producer family matters. T4 uses the production shape; a `cat` probe would have been vacuous |
| D9 | Plan §V3: 19 gate call sites + one at `:712` = 20 | **21** — there is a second `bash …-gate.sh` at `:4193` | Preamble header records all three shapes accurately |
