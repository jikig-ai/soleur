---
title: "fix: make the local test-all battery host-portable (green-baseline precondition for #8231)"
date: 2026-09-18
slug: fix-local-test-battery-host-portability
branch: feat-8231-parallel-test-all-next
issue: 8231
closes: [8238, 8250, 8261, 8263, 8266]
lane: cross-domain
type: fix
priority: p2-medium
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

## Overview

Nine registered suites are red on a developer host (Arch/Omarchy, Node 26.8.1, mise shims, a
personal global git config) while `ci.yml` on `main` is green. Every one of them belongs to a
defect class that makes a suite, hook or lint report a verdict about its subject when the actual
cause is the host. Each is owned by an open issue: #8238, #8250, #8261, #8263 and #8266.

This plan fixes those classes where they occur. When it lands, a serial `scripts/test-all.sh` run
on such a host reports every suite as passed, or passed with named, declared skipped arms. That is
the green-baseline precondition the #8231 parallel-scheduler plan
(`knowledge-base/project/plans/2026-09-17-feat-parallel-local-test-all-suites-plan.md`) is
blocked on.

Three of the defects are **not test-only**:

- **Conflict-marker guard.** `.claude/hooks/guardrails.sh`'s guard **fails open** in production on
  any host with `diff.mnemonicprefix=true` or `diff.noprefix=true`. A real commit carrying a lone
  kb-index merge-driver sentinel is allowed. The same configs also make it **over-fire** across
  files, and `diff.relative=true` blinds it when run from a subdirectory.
- **Secret-scan hook, unrunnable tool.** `.claude/hooks/git-commit-secret-scan.sh` treats a
  permanently unrunnable gitleaks as a "transient" error. On such a host every commit bypasses
  the local scan under a mislabelled reason.
- **Secret-scan hook, colour config.** Measured this session: `gitleaks git --pre-commit --staged`
  finds **nothing** in a staged AWS key when the user has `color.ui=always` or
  `color.diff=always`. It returns rc 0 with 0 findings, against rc 1 with 1 finding by default.
  The hook and `lefthook.yml`'s `gitleaks-staged` step both run that command unpinned.

CI's required `gitleaks scan` still gates every push, so the secret-scan defects are lost defence
in depth, not unguarded paths.

`#8231` stays **open**. This PR is `Ref #8231` and closes the five owning issues.

## Research Insights

### Premise Validation (Phase 0.6)

- All five bundled issues and #8231 are **OPEN**, and no PR references them.
- The #8231 blocker ("20 pre-existing red suites") was measured while `bun` was an unrunnable mise
  shim. Re-run 2026-09-18 with bun 1.3.14 healthy: 12 of 21 are now green and 9 are red.
- CI main is green (`gh run list --workflow ci.yml --branch main` → push 2026-09-17T22:25Z
  success).
- **Every cause was verified by a same-tree A/B run:**

| Suite | Host | Neutralised | Neutraliser | Cause |
|---|---|---|---|---|
| `.claude/hooks/guardrails.test.sh` | 122/123 | 123/123 | `GIT_CONFIG_*` `diff.mnemonicprefix=false` | patch parser assumes `b/` |
| `scripts/lint-legal-scope-block-placement.test.sh` | 44/16 | 65/0 | same | patch parser assumes `b/` (reads `+++ w/…`, reports 0 violations) |
| `scripts/lib/scratch-root.test.sh` | FAILED: 2 | pass | `env -u XDG_CACHE_HOME` | `NAME=VALUE` before `--unset` defines a var named `--unset` |
| `gitleaks-merge-commit`, `git-commit-secret-scan`, `code-to-prd` | red | green (#8266 controls) | runnable gitleaks 8.24.2 | resolvable-but-unrunnable tool read as a verdict |
| `_base-notice-frontmatter`, `notice-frontmatter` | rc 127 | — | — | TS-cron-5 hard-calls `/usr/bin/time` |
| `apps/web-platform [repo-wide+component]` | 30/81 failed (3 sampled files) | 81/81 | `--no-experimental-webstorage` | Node ≥25 global `localStorage` shadows happy-dom's |

- `apps/web-platform/infra/registry-userdata-budget.test.sh` (the `bc` site from #8266) is **not**
  among the nine. It runs from the infra runner (`infra-validation.yml`), not from
  `test-all.sh --enumerate all`. It is fixed here because #8266 owns it.
- **Issue-body claims corrected by measurement:**
  - #8261's "jsdom" is actually happy-dom.
  - #8266's `_base-notice-frontmatter.test.sh:313` is actually TS-cron-5 (~:339).
  - #8266 says `notice-frontmatter.test.sh` "wraps" that file. It is actually a parallel copy
    (~:359).
  - #8263's "plausible #7991 regression" is actually `diff.mnemonicprefix`.

### Property List (Phase 0.6b)

- **P1.** A git patch-output consumer that runs on a developer host (hook, lint, gitleaks)
  produces the same verdict regardless of the user's `diff.*`/`color.*` git configuration.
- **P2.** A suite that isolates an environment variable actually isolates it.
- **P3.** A tool that resolves on PATH but cannot run is reported as *tool-unavailable*, never as
  a verdict about the subject it would have measured.
- **P4.** A test arm whose required tool is unavailable SKIPs locally, naming the tool and the
  remediation, and makes the suite FAIL under `CI=true` (ADR-188 / `_skip()` in
  `apps/web-platform/infra/git-data-emit.test.sh`; learning
  `2026-07-15-narrowing-is-not-anchoring-…`). The probe itself must not misreport a working tool
  on a host without GNU `timeout` (stock macOS).
- **P5.** The web-platform vitest suites pass on Node 22 and Node 26, and Node 22 behaviour is
  unchanged.
- **P6.** The nine suites pass on this host. A recorded serial battery run on this host is the
  #8231 evidence, and any other red row is classified.

### Cut List (Phase 0.6b and plan-review)

| Mechanism | Property | Why cut |
|---|---|---|
| Narrow `engines` (#8261 option 1) | P5 | No `engine-strict`, so it produces one install-time `EBADENGINE` warning and fixes nothing |
| Shared `tool-runnable.sh` helper | P3 | **Rationale corrected at review — the recorded reason was false.** "A plugin script cannot source repo `scripts/lib/`" is true and irrelevant: `scripts/lib/` is the wrong home. `plugins/soleur/scripts/lib/` ships INSIDE the plugin, and repo-local hooks already source across that boundary (`.claude/hooks/pre-merge-rebase.sh:32`, `pkill-self-match-guard.sh:82`, `session-rules-loader.sh:67`). A scope-out was then proposed on a new reason and **DISSENTed** by the CONCUR gate, which was right twice over: its premise ("the hook has no external dependencies at the probe point") was false — the hook already sources `lib/incidents.sh:50` and, fail-hard, `lib/hook-input.sh:70` before the probe — and the six copies are three FAILURE POLICIES, not one contract (hook: 124/137 retry ladder; code-to-prd: `exit 2`; four test suites: identical skip contract). Resolution: the test-side contract is extracted to `plugins/soleur/test/lib/gitleaks-probe.sh` and sourced by all four suites; the hook and code-to-prd keep their single-use probes inline, which is the YAGNI-correct call for code used once |
| Runner-level skip exit code | P4 | `exit 77` already has other meanings (`scripts/sentry-issue.sh`, `resolve-debt.test.sh`), and the runner's result classes belong to #8231's scheduler Phase 3 |
| Repo `mise.toml` gitleaks pin | P3 | Fixes this host, not the class; the SKIP message names the remediation |
| `GIT_CONFIG_GLOBAL=/dev/null` exported suite-wide or hook-wide | P1 | No shared chokepoint; collides with `git-fixture-env.sh`'s own `GIT_CONFIG_COUNT`; drops the user's signing/identity config |
| **Census test** `git-patch-parser-pinning.test.sh` (plan v1 Guard 1) | none in P1–P6 (future parsers) | Plan-review: both simplification reviewers said delete it, and the correctness side found its regex missed 3 of its own 7 named files. Both panels firing on one scope → delete |
| `resolve()` partitioner + mutation matrix (v1 Guard 3) | P2 | Only two call sites are misordered; reorder them, and the ambient sentinel makes CI red if either regresses |
| ~~`ship-runbook-ssh-gate.sh` hardening (v1 Phase 1.3)~~ **UNCUT at review — both reasons were false** | P1 | "It does not parse the prefix" is wrong: line 92 reads `git diff --unified=0 … \| grep -E '^\+[^+]'`, i.e. added lines from patch output, so `color.diff=always` empties it and this hard-rule gate (`hr-no-ssh-fallback-in-runbooks`) silently passes an `ssh prod-host` runbook step. "Editing its text reds the required check" only holds if the re-fired baseline entry is left unfixed — measured: after pinning the flags the lint reports **0 new findings**, because the underlying `set -eo pipefail` abort was fixed at source rather than re-baselined. Hardened in this PR |
| End-of-run SKIP summary in `test-all.sh` (CTO F3) | P4 visibility | A runner change; the evidence step lists skipped arms per suite instead |

### Load-bearing findings (content anchors, verified this session)

**Patch-output consumers on developer hosts (P1):**

- `.claude/hooks/guardrails.sh`, block-conflict-markers arm:
  - The staged-diff read `"${CONFLICT_GIT[@]}" diff --cached --no-color --no-ext-diff` already
    has `--no-color --no-ext-diff`.
  - The awk `/^\+\+\+ b\//` sets `path` and resets the per-file `lt`/`eq` counters.
  - It is missing a prefix pin and `--no-relative`.
- `scripts/lint-legal-scope-block-placement.sh`: `git -c core.quotePath=false diff -U0 --no-color
  --diff-filter=d $MERGE_BASE` plus awk `sub(/^b\//…)`. It is missing a prefix pin and
  `--no-ext-diff`.
- `.claude/hooks/git-commit-secret-scan.sh` and `lefthook.yml` (`gitleaks-staged`):
  `gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1`. gitleaks runs `git`
  itself and inherits user colour config (measured: `color.ui=always` → 0 findings). The fix is
  env `GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=color.ui GIT_CONFIG_VALUE_0=never
  GIT_CONFIG_KEY_1=color.diff GIT_CONFIG_VALUE_1=never` on that one invocation.
- **`code-to-prd.sh` Layer 3 is not affected:** it runs `gitleaks detect … --no-git`.
- **Parsers that do not depend on the prefix** still read raw patch lines, so `diff.external`
  can alter them. Each is missing one or both of `--no-color`/`--no-ext-diff` (verify per file):
  - `.claude/hooks/brand-hex-commit-gate.sh`: `git diff "$NAME_REF" -U0 --no-color -- "$f"` then
    awk on `^\+`, needs `--no-ext-diff`. Plan-review claimed it isn't a patch parser; that is
    refuted by this call.
  - `.claude/hooks/context-reviewed-gate.sh`
  - `scripts/lint-trap-tempfile-ownership.py`
  - `apps/web-platform/scripts/check-tc-document-sha.sh`
- **Pin flags:** `--src-prefix=a/ --dst-prefix=b/` beats `diff.mnemonicprefix`, `diff.noprefix`,
  `diff.srcPrefix`/`dstPrefix` (verified by two reviewers on git 2.55). `--default-prefix` needs
  git ≥ 2.41 and is not used. `-c diff.mnemonicprefix=false` does **not** undo
  `diff.noprefix=true`.

**`scratch-root.test.sh` (P2):**

- `resolve()` runs `env "$@" bash -c …`. GNU `env` stops option parsing at the first
  `NAME=VALUE`.
- The two misordered calls are the **"falls back to `$HOME/.cache`"** case
  (`resolve "HOME=$TMP_ROOT/home" --unset=XDG_CACHE_HOME`) and the **"containment"** case
  (`resolve "HOME=$TMP_ROOT/home2" --unset=XDG_CACHE_HOME`).
- The three-unset case (`resolve --unset=HOME --unset=XDG_CACHE_HOME
  --unset=SOLEUR_SCRATCH_ROOT`) is already correctly ordered.
- The file's "does NOT export TMPDIR" case comment already documents this exact defect.

**Tool-runnability sites (P3/P4):**

- **`plugins/soleur/skills/code-to-prd/scripts/code-to-prd.sh`:**
  - Preflight: `command -v gitleaks` → exit 2.
  - The PRD is `cp`'d over the output path **before** Layer 3 runs.
  - Layer 3: `gitleaks detect … --no-git … --exit-code 1 >/dev/null 2>&1`, under the comment
    "Non-zero exit from gitleaks = findings", deletes the PRD and says "found secrets".
  - The `EXIT` trap deletes `GITLEAKS_OUT`, so the "Report at:" path never exists.
  - `mktemp` creates `GITLEAKS_OUT` before gitleaks runs.
  - The header documents exit codes; `SKILL.md` §Redaction describes Layer 3.
- **`.claude/hooks/git-commit-secret-scan.sh`:**
  - **Absent:** warns "gitleaks not installed — skipping scan" (with a `brew install gitleaks`
    suggestion), calls `emit … bypass "gitleaks not installed"`, and allows.
  - **Unrunnable:** reaches the `exit=$scan_rc, empty report` branch ("likely a transient
    gitleaks error").
  - Nothing keys on either string: `rule-metrics-aggregate.sh` groups by `rule_id`/`event_type`
    only.
  - The test (T1–T10) has no absent or empty-report arm.
- **`plugins/soleur/test/gitleaks-rules.test.sh`:**
  - When gitleaks is absent: `HAVE_GITLEAKS=0`, fixture rows skipped, **exit 0 even under CI**.
  - The arity/anchor guards deliberately keep running without gitleaks ("A blanket `exit 0` here
    used to skip the arity/anchor guards too").
- **`plugins/soleur/test/gitleaks-merge-commit.test.sh`:**
  - When gitleaks is absent: `ABORT … exit 2`.
  - T4, P1 (`scan_coupling`) and the `arm_dash_m == "1"` coupling arm decide on `rc`. They pass
    falsely on a binary that exits 1 without scanning. The T3 comment names this defect; only
    T3 was fixed.
  - The rows that expect rc 0 are backed by same-run positive controls (T2/T3 require findings),
    so a no-op scanner still reds the suite.
- **TS-cron-5** in `_base-notice-frontmatter.test.sh` and in its parallel copy
  `notice-frontmatter.test.sh`: `SECS=$( { /usr/bin/time -f "%e" … ; } 2>&1 )` under
  `set -euo pipefail`. TS11/TS12 `/usr/bin/time` uses are `CI=true`-gated.
- **`apps/web-platform/infra/registry-userdata-budget.test.sh`:** `| paste -sd+ - | bc 2>/dev/null
  || echo 0`, so it reports "found 0 assignments" without `bc`.
- **`timeout`:** stock macOS lacks GNU `timeout`. `.claude/hooks/memory-backstop.sh` and
  `supabase-loopback-warn.sh` already guard it (`command -v timeout && TO=(timeout N)`), after a
  hard-coded `timeout` caused exit 127 in a hook before.

**Node 26 (P5):**

- On Node 26, `globalThis.localStorage` is a built-in getter returning `undefined`.
- Vitest 4.1's `getWindowKeys` skips pre-existing global keys unless they are in its own list,
  and that list has `Storage` but not `localStorage`/`sessionStorage`. So happy-dom's storage
  never lands.
- **Fix:** root-level `test.execArgv` guarded on
  `Object.getOwnPropertyDescriptor(globalThis, "localStorage")`. It is truthy on 26; false on
  22.3, 22.4 and 22.12. It does not invoke the getter.
  - `NODE_OPTIONS` is rejected on 22.3.
  - CLI `--execArgv` did not help.
  - `execArgv?: string[]` is typed in vitest 4.1.0.
  - The Dockerfile runs no vitest.
- `kb-share-preview.test.ts`: the mocks of `readPdfMetadata`/`readImageMetadata` never drain the
  stream `maybeFirstPagePreview` opens. The garbage collector then closes the FileHandle: DEP0137
  on 22, a hard error on 26. Destroying the handed-in streams in `afterEach` gives 0 errors under
  forced GC; without it there are 5.

**CI consumers of the gitleaks suites:**

- Only `ci.yml` test-scripts (`test-all.sh scripts`) and `main-health-monitor.yml`
  (`TEST_GROUP=all`) run them, and both install gitleaks 8.24.2 first. So "FAIL under CI" breaks
  nothing.
- Both files carry comments describing the old probe behaviour ("preflights `command -v
  gitleaks`", "three suites hard-ABORT"), which this plan updates.

### Institutional learnings that bind this plan

- `knowledge-base/project/learnings/2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md`:
  FAIL in CI, SKIP only locally.
- `knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md`:
  the skip contract.
- `knowledge-base/project/learnings/2026-09-17-command-v-is-a-resolvability-probe-and-every-guard-i-wrote-to-pin-it-was-narrower-than-its-name.md`:
  resolvability versus runnability. `%q`-quote tool output echoed in messages.
- `knowledge-base/project/learnings/2026-09-18-a-red-baseline-blocker-carries-the-host-toolchain-that-measured-it.md`:
  this session's re-measurement.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality | Plan response |
|---|---|---|
| #8263: scratch-root "host-shape or HEAD-state dependent" | the test's own `env` ordering at two call sites | Reorder them; ambient sentinel |
| #8263: kb-index "plausible #7991 regression" | `diff.mnemonicprefix` (A/B 122→123) | Prefix pin |
| #8238: "arm (a) regressed or fixtures drifted" | neither; the lint reads `+++ w/…` | Prefix pin in the lint |
| #8261: "jsdom" | happy-dom; vitest skips the pre-existing global | Guarded `execArgv` |
| #8266: `/usr/bin/time` at `:313`; notice-frontmatter "wraps" it | TS-cron-5; parallel copy | Fix both copies |
| #8266: `lefthook.yml` gitleaks "fails closed and visibly" | also colour-blind (0 findings under `color.ui=always`); does not run on this host at all (#8271) | Colour pin here; runnability probe left to #8271 |
| Brainstorm: "#8112 is the home for main-red work" | CI main green | Not referenced |

## Open Code-Review Overlap

None (`gh issue list --label code-review --state open` bodies matched no file in `## Files to Edit`).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly, with one exception. A regression
in `code-to-prd.sh`, which ships to plugin users, would make `/soleur:code-to-prd` exit 2 or delete
a PRD wrongly. AC5/AC6 pin both, including on a host without GNU `timeout`.

**If this leaks, the user's data / workflow / money is exposed via:** a secret committed on a
developer host where the local secret scan silently cannot run or silently sees nothing (the
colour case). This plan **narrows** both exposures: an unrunnable binary is labelled truthfully,
and gitleaks' git invocations are colour-pinned. It does not change the hook's documented
fail-open policy, and CI's required secret scan is unchanged.

**Brand-survival threshold:** none

- threshold: none, reason: every credential-adjacent change narrows an existing local-scan blind spot and keeps the hook's documented fail-open semantics; CI's required gitleaks scan, the real gate, is unchanged.

## Implementation Phases

Each fix lands **RED first**, under the condition that exposes it and on CI-shaped runners where
the plan can construct that condition. Where the RED can only be shown on this host, the phase
says so.

### Phase 1 — Patch-output consumers immune to user git config (#8238, #8263 part 1; P1)

1.1 **RED rows**, set on the invocation of the hook, lint or gitleaks under test and never
exported suite-wide (`git-fixture-env.sh` uses `GIT_CONFIG_COUNT` itself). One config per row.

`.claude/hooks/guardrails.test.sh`:
- Lone kb-index sentinel **deny** under `diff.mnemonicprefix=true`, and again under
  `diff.noprefix=true`.
- Cross-file **allow** under `diff.noprefix=true`. Fix this fixture so `<<<<<<<` sits at
  column 0: today `$MK_LT` is mid-line, so the over-fire is untested.
- Lone sentinel **deny** with `diff.relative=true` and the hook run from a subdirectory.

`scripts/lint-legal-scope-block-placement.test.sh`: the arm (a) must-fire rows under
`diff.mnemonicprefix=true` and under `diff.noprefix=true`.

`.claude/hooks/git-commit-secret-scan.test.sh`: the staged-AWS-key **deny** row under
`color.ui=always` and under `color.diff=always`. This needs a runnable gitleaks, so the P4 skip
applies.

1.2 **GREEN.**
- `guardrails.sh`: add `--src-prefix=a/ --dst-prefix=b/ --no-relative` to the staged-diff read.
- Legal lint: add `--src-prefix=a/ --dst-prefix=b/ --no-ext-diff` to its `git diff -U0`.
- `git-commit-secret-scan.sh` and `lefthook.yml` `gitleaks-staged`: prefix the gitleaks call with
  the colour-pin env (`GIT_CONFIG_COUNT=2 … color.ui=never … color.diff=never`). In
  `lefthook.yml` this is an env on the `run:` line. If the user's environment already carries a
  `GIT_CONFIG_COUNT`, append to it rather than clobbering it. /work verifies the hook's
  environment at that point.

1.3 **Defensive, single commit, no new tests:** add the missing `--no-ext-diff` (and
`--no-color` where missing) to the patch-producing call in the four remaining parsers. **Before
editing any line**, grep `scripts/lint-shell-capture-exit.baseline.txt` and the
`lint-shell-trace-credential-refusal` baselines for that file. If the line is baselined, drop
the edit for that file and record why.
- `brand-hex-commit-gate.sh`
- `context-reviewed-gate.sh`
- `lint-trap-tempfile-ownership.py`
- `check-tc-document-sha.sh`

### Phase 2 — `scratch-root.test.sh` isolates what it claims to (#8263 part 2; P2)

2.1 **RED.** At the top of the suite, export `XDG_CACHE_HOME="$TMP_ROOT/ambient-xdg"`, a
sentinel the resolver must never return. Every runner, CI included, now carries the variable, so
the two misordered cases fail everywhere as they do on this host.

2.2 **GREEN.** Move `--unset=XDG_CACHE_HOME` before the `HOME=…` assignment in the
"`$HOME/.cache` fallback" and "containment" cases. Add a one-line comment at `resolve()`
stating the ordering contract and pointing at the TMPDIR case's explanation.

### Phase 3 — A tool that cannot run is not a verdict (#8266, #8250; P3, P4)

**Probe shape** (inline; mirror `memory-backstop.sh`):

```bash
TO=(); if command -v timeout >/dev/null 2>&1; then TO=(timeout 10); elif command -v gtimeout >/dev/null 2>&1; then TO=(gtimeout 10); fi
"${TO[@]}" gitleaks version >/dev/null 2>"$errf"   # runnable ⇔ rc 0
```

On failure, report `rc` and the first stderr line, both `%q`-quoted.

**Remediation text** (every SKIP and bypass message): name the CI pin and a manager-neutral step:
"gitleaks is not runnable here (rc=…, …). CI pins gitleaks 8.24.2 — install that version or pin
it in your version manager". This replaces the hook's `brew install gitleaks`.

**P4 skip, per arm, not per suite:**
- An arm that needs gitleaks calls a `_skip_arm "<suite>: <arm>" "<reason>"` that increments a
  counter and prints `SKIP — <suite>: <arm> — <reason + remediation>`.
- At suite end, if any arm was skipped: under `CI=true`, exit 1 naming the arms; otherwise exit 0
  after printing the skipped-arm list.
- Arms that do not need gitleaks (e.g. `gitleaks-rules`' arity/anchor guards) keep running. Stub
  arms that inject their own `gitleaks` onto PATH never skip.

3.1 **`code-to-prd.sh`.**
- Preflight: the runnability probe replaces `command -v`. Unrunnable → exit 2 with the
  remediation message.
- Layer 3:
  - Scan the staged/rendered file **before** it is copied over the output path, so a failed or
    positive scan never destroys the previous PRD.
  - Capture gitleaks stderr to a temp file.
  - **Findings** means rc 1 **and** `[[ -s "$GITLEAKS_OUT" ]]` **and** `grep -q '"RuleID"'
    "$GITLEAKS_OUT"`. Handle these as today: withhold the new PRD and report the finding count.
  - **Any other non-zero:** withhold the new PRD and exit **2** "secret scan did not complete (rc=…,
    …)". Never say "found secrets".
  - A failed deletion still exits 3.
- Stop printing a report path the `EXIT` trap deletes; print the finding count instead (a durable
  unredacted report would persist secrets).
- Update the header's exit-code table and `plugins/soleur/skills/code-to-prd/SKILL.md`
  (§Redaction Layer 3; §Preconditions: "runnable `gitleaks`").

3.2 **`git-commit-secret-scan.sh`.**
- Run the runnability probe after the absent check. An unrunnable binary takes the absent
  branch's semantics: warn with remediation, `emit git-commit-secret-scan bypass "gitleaks
  unrunnable (rc=N)"`, allow.
- The empty-report branch stays for a *runnable* binary that exits non-zero with no report.
- Header: name the three cases, and note that where lefthook runs its own gitleaks step, the
  commit may still be blocked there (so a `bypass` row is not proof the commit landed).

3.3 **Suites** — replace resolvability with runnability and route through `_skip_arm`:
- `gitleaks-rules.test.sh`: the fixture arms. Its arity/anchor guards keep running.
- `gitleaks-merge-commit.test.sh`: replace `ABORT … exit 2`.
- `git-commit-secret-scan.test.sh`: the arms needing a real gitleaks.
- `code-to-prd.test.sh`: the baseline arm.

3.4 **Oracle fix in `gitleaks-merge-commit.test.sh`.** T4, P1 (`scan_coupling`) and the
`arm_dash_m` coupling arm decide on the parsed report's RuleIDs, as T3 does, not on `rc`.

3.5 **`/usr/bin/time` (#8250).** In both TS-cron-5 copies, measure with two `$EPOCHREALTIME` reads
converted to integer microseconds by the `${t%.*}`/`${t#*.}` split. **Fail the case**, not pass
it, if either read is not of the form `digits.digits` (a locale radix or old bash would otherwise
make `< 6 s` pass vacuously). Keep the `< 6 s` assertion. The RED (rc 127) is demonstrable only on
a host without GNU time, because the call is an absolute path. The CI-visible gate is the static
check in AC9.

3.6 **`bc` (registry-userdata-budget).** Replace `| paste -sd+ - | bc 2>/dev/null || echo 0` with
`| awk '{s+=$1} END{print s+0}'`.
*Landed on `main` by #8272 first (the #7960 sibling), semantically identical; this branch's copy
was dropped at rebase in favour of the merged one, so the file is no longer in this PR's diff.
AC10 is still satisfied — by main.*

### Phase 4 — web-platform vitest on Node 22 and 26 (#8261; P5)

4.1 **`apps/web-platform/vitest.config.ts`:** root `test.execArgv` =
`Object.getOwnPropertyDescriptor(globalThis, "localStorage") ? ["--no-experimental-webstorage"] :
[]`. Add a comment naming the vitest `getWindowKeys` mechanism and the Node versions measured.
Confirm projects inherit it (`extends: true`), and merge if any project sets its own `execArgv`.
Verify under the forks pool and `WEBPLAT_TEST_USE_THREADS=1`.

4.2 **`apps/web-platform/test/kb-share-preview.test.ts`:** capture each stream handed to the
mocked metadata readers and `destroy()` it in `afterEach`. **RED:** run under `--expose-gc` with
`gc()` in `afterEach`: 5 errors before, 0 after.

4.3 **Unchanged:** `engines`; product code in `server/kb-share.ts`.

### Phase 5 — Evidence (P6)

5.1 Run each of the nine suites alone on this host, with its real global git config, Node 26, the
mise shims, and no `bc`/`/usr/bin/time`. Record rc and skipped arms.

5.2 Full serial battery:
```
TEST_TIMING_LOG=<f> TEST_GROUP=all bash scripts/test-all.sh 2>&1 | tee <log>
```
- Record the `[contention]` preamble.
- Re-run any `FAIL`/`KILLED`/`TRIPWIRE` row that is **not** one of the nine alone. If it passes
  alone, classify it as contention; otherwise it is host divergence (fold it in) or a new defect
  (file it; the precondition is then **not** claimed).
- If the run is refused (rc 4), wait at most 2 h, then record the refusal and ship on 5.1 alone.
  Phases 1 and 3.2 carry the production value and must not stall behind the battery.

5.3 Append a section to
`knowledge-base/project/specs/feat-one-shot-8231-parallel-test-all/acceptance-evidence.md`:
- host facts;
- registration count and timing-log class counts that sum to it;
- the per-suite skipped-arm list (from the `SKIP — <suite>: <arm>` lines) with reasons, naming
  which suites **never exercised gitleaks on this host**;
- the classification of any other red row.

Update that file's `## Status` row "Phase 1 onward" to "precondition met <date>, this PR", or
"not met" with the reason.

## Files to Edit

- `.claude/hooks/guardrails.sh`: prefix pin + `--no-relative`
- `.claude/hooks/guardrails.test.sh`: config rows; column-0 cross-file fixture
- `scripts/lint-legal-scope-block-placement.sh`: prefix pin + `--no-ext-diff`
- `scripts/lint-legal-scope-block-placement.test.sh`: config rows
- `.claude/hooks/git-commit-secret-scan.sh`: colour pin; runnability probe → absent-branch semantics; remediation text; header
- `.claude/hooks/git-commit-secret-scan.test.sh`: colour rows; absent / unrunnable / empty-report / no-`timeout` arms; `_skip_arm`
- `lefthook.yml`: colour pin on `gitleaks-staged`
- `.claude/hooks/brand-hex-commit-gate.sh`, `.claude/hooks/context-reviewed-gate.sh`, `scripts/lint-trap-tempfile-ownership.py`, `apps/web-platform/scripts/check-tc-document-sha.sh`: defensive `--no-ext-diff`/`--no-color` (subject to the baseline check)
- `scripts/lib/scratch-root.test.sh`: ambient sentinel; reorder two cases; contract comment
- `plugins/soleur/skills/code-to-prd/scripts/code-to-prd.sh`: probe; scan-before-copy; Layer 3 classification; exit table
- `plugins/soleur/skills/code-to-prd/SKILL.md`: Layer 3 and Preconditions text
- `plugins/soleur/skills/code-to-prd/test/code-to-prd.test.sh`: unrunnable arm; Layer-3-did-not-complete arm; previous-PRD-preserved arm; no-`timeout` arm; `_skip_arm`
- `plugins/soleur/test/gitleaks-rules.test.sh`: runnability probe; `_skip_arm`
- `plugins/soleur/test/gitleaks-merge-commit.test.sh`: runnability probe; `_skip_arm`; T4/P1/`arm_dash_m` RuleID oracle
- `plugins/soleur/test/_base-notice-frontmatter.test.sh`, `plugins/soleur/test/notice-frontmatter.test.sh`: TS-cron-5 `$EPOCHREALTIME`
- ~~`apps/web-platform/infra/registry-userdata-budget.test.sh`: awk sum~~ — landed via #8272 on main; not in this diff
- `apps/web-platform/vitest.config.ts`: guarded `execArgv`
- `apps/web-platform/test/kb-share-preview.test.ts`: `afterEach` destroy
- `.github/workflows/ci.yml`, `.github/workflows/main-health-monitor.yml`: comments describing the gitleaks probe/abort behaviour
- `knowledge-base/project/specs/feat-one-shot-8231-parallel-test-all/acceptance-evidence.md`: evidence section; status row

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

1. `guardrails.test.sh` passes on this host. Its new rows are:
   - lone-sentinel deny × {mnemonicprefix, noprefix}
   - cross-file allow × noprefix
   - lone-sentinel deny under `diff.relative=true` from a subdirectory

   On a scratch copy of `guardrails.sh` with the pin tokens removed, the prefix rows fail and the
   relative row fails (mutation recorded in the PR body).
2. `lint-legal-scope-block-placement.test.sh` reports `failed: 0` on this host. Its
   mnemonicprefix and noprefix rows fail on a scratch copy of the lint without the prefix pin.
3. With a runnable gitleaks, `git-commit-secret-scan.test.sh`'s staged-AWS-key rows deny under
   `color.ui=always` and under `color.diff=always`, and fail on a scratch copy of the hook
   without the colour pin. The same `GIT_CONFIG_*` env appears on `lefthook.yml`'s
   `gitleaks-staged` `run:` line.
4. `scratch-root.test.sh` passes. On a scratch copy with either reordered case restored to
   `"HOME=…" --unset=…` order, it fails, with or without `XDG_CACHE_HOME` in the caller's
   environment, because of the ambient sentinel.
5. `code-to-prd.sh`, with a PATH built from symlinks to only the tools the script needs plus a
   stub `gitleaks`:
   - (a) stub `version` exits 1 with a mise-shaped error → exit 2, message contains `not runnable`
     and `8.24.2`, never `found secrets`.
   - (b) stub `version` exits 0, `detect` exits 1 with no report → exit 2 `did not complete`,
     never `found secrets`, and the **previous** PRD at the output path is byte-identical
     afterwards.
   - (c) stub `detect` writes a report containing `"RuleID"` and exits 1 → exit 1, finding count
     printed, previous PRD preserved.
   - (d) a real runnable gitleaks with `timeout` absent from PATH → the scan runs (not exit 2).
   - No path printed after `Report at:` fails `[[ -e ]]`.
6. `git-commit-secret-scan.test.sh` has passing arms, each asserting the allow decision **and**
   the incidents-row prefix:
   - absent (`gitleaks not installed`);
   - unrunnable (`gitleaks unrunnable`);
   - runnable-empty-report (`gitleaks exit=`);
   - runnable-with-`timeout`-absent (scan runs, no bypass row).

   The unrunnable and absent messages contain `8.24.2` and do not contain `brew install`.
7. For each of `gitleaks-rules`, `gitleaks-merge-commit`, `git-commit-secret-scan`,
   `code-to-prd.test.sh`, run with no runnable gitleaks:
   - without `CI`: exit 0, at least one `SKIP — <suite>: <arm>` line, and (for `gitleaks-rules`)
     the arity/anchor guard lines still print PASS;
   - with `CI=true`: exit 1 naming the skipped arms.
8. `gitleaks-merge-commit.test.sh` T4, P1 and the `arm_dash_m` arm FAIL against a stub whose
   `version` exits 0 and whose scan exits 1 writing no report. On `main` today they PASS.
9. Both notice-frontmatter suites pass on this host (no GNU time). `git grep -n '/usr/bin/time'
   plugins/soleur/test/_base-notice-frontmatter.test.sh
   plugins/soleur/test/notice-frontmatter.test.sh` returns only lines inside `CI=true`-gated
   blocks. A unit row feeds the elapsed-time parser a comma-radix value and asserts the case
   **fails**.
10. `registry-userdata-budget.test.sh` passes with a PATH built from symlinks excluding `bc`, and
    contains no `| bc`.
11. On Node 26.8.1: `cd apps/web-platform && npm run test:ci -- --project repo-wide --project
    component` and `--project unit` pass with 0 errors. CI's Node 22 `test-webplat` shards stay
    green.
12. **(a)** Each of the nine suites exits 0 when run alone on this host (Phase 5.1 record in the
    evidence file). **(b)** The Phase 5.2 battery log and timing log are recorded, with every
    non-nine red row classified per 5.2. This AC is about recording and classification, not
    about zero rows, so a sibling process cannot flip it.
13. `ci.yml` and `main-health-monitor.yml` gitleaks comments describe the new probe and skip
    behaviour (no stale "`command -v gitleaks`" or "hard-ABORT" text for these suites).
14. PR body: `Ref #8231`; `Closes #8238`, `Closes #8250`, `Closes #8261`, `Closes #8263`,
    `Closes #8266`, each on its own line in the body, none in the title.

### Post-merge (operator)

None.

## Observability

```yaml
liveness_signal:
  what: git-commit-secret-scan emits an incidents row for every bypass, with a case-specific prefix
  cadence: per commit attempted through the hook
  alert_target: .claude/.rule-incidents.jsonl, aggregated into knowledge-base/project/rule-metrics.json by compound (ADR-091)
  configured_in: .claude/hooks/lib/incidents.sh (emit wrapper in the hook)
error_reporting:
  destination: stderr warn with remediation text plus the incidents row; code-to-prd exit 2 with rc and first stderr line
  fail_loud: gitleaks suites exit 1 under CI=true naming skipped arms
failure_modes:
  - mode: gitleaks unrunnable on a developer host
    detection: incidents row prefix "gitleaks unrunnable (rc=N)"
    alert_route: compound Phase 1.5 ingests bypass rows
  - mode: CI runner loses gitleaks
    detection: gitleaks suites exit 1 under CI=true
    alert_route: CI test-scripts shard (required test check)
  - mode: a user git config blinds a patch consumer
    detection: config rows in guardrails.test.sh, lint-legal test, git-commit-secret-scan.test.sh
    alert_route: CI test-scripts shard
logs:
  where: suite stdout in the test-all.sh run log; TEST_TIMING_LOG rows
  retention: CI job logs (GitHub default); local run logs are the operator's
discoverability_test:
  command: bash .claude/hooks/guardrails.test.sh
  expected_output: a final Total line with Fail 0
```

## Guard Contract

### Guard 1 — config rows over the patch-output consumers

**Property.** The kb-index deny, the cross-file allow, the legal arm (a) verdict, and the
secret-scan deny are each identical under default config and under each of
`diff.mnemonicprefix=true`, `diff.noprefix=true`, `diff.relative=true` (guardrails only), and
`color.ui/color.diff=always` (secret scan only).

**Assembly.** The three consumers that parse git patch output on developer hosts and whose
verdict is security- or gate-relevant: `guardrails.sh`, the legal lint, and gitleaks as invoked
by the hook. `lefthook.yml`'s gitleaks step shares the hook's command and carries the same pin
(AC3). The four defensive parsers in Phase 1.3 are pinned without rows.

**Mutation matrix.**

| # | Edit | Must |
|---|---|---|
| M1 | Remove the prefix pin from `guardrails.sh` | mnemonicprefix and noprefix deny rows RED |
| M2 | Remove `--no-relative` from `guardrails.sh` | relative row RED |
| M3 | Remove the prefix pin from the legal lint | arm (a) rows RED under both prefix configs |
| M4 | Remove the colour pin from the hook | colour deny rows RED |
| M5 | Pin only `color.ui` (a second setting, `color.diff`, left unpinned) | `color.diff=always` row RED |

**Harness rows.**
- H1: each config row asserts, inside the child, that `git config --get <key>` returns the
  injected value. A misspelled key must go RED, not silently test default config.
- H2 (must-PASS non-canonical): the legal lint under `diff.algorithm=histogram`, a config the
  contract does not care about, passes.

**Anchor.** Not applicable. No stored value is compared.

### Guard 2 — tool-unavailable is never a verdict

**Property.** For every gitleaks consumer in scope, an unrunnable gitleaks yields
*tool-unavailable*. It never yields a subject verdict, and a runnable gitleaks is never
misreported as unrunnable for lack of `timeout`.

**Assembly.** The probe sites are:
- `code-to-prd.sh`: preflight and Layer 3;
- `git-commit-secret-scan.sh`;
- the four suites' `_skip_arm` probes;
- the RuleID oracles (T4, P1, `arm_dash_m`).

Census command: `git grep -l gitleaks -- '*.sh' 'lefthook.yml'`, minus CI-only workflow steps
that install a pinned binary first.

**Mutation matrix.**

| # | Edit | Must |
|---|---|---|
| M1 | `code-to-prd.sh` preflight reverted to `command -v` | AC5(a) RED: exit 2 now comes from Layer 3 as `did not complete`, not the preflight message |
| M2 | Layer 3 treats any non-zero as findings | AC5(b) RED (`found secrets` printed) |
| M3 | The probe uses bare `timeout` without the fallback | AC5(d) and AC6's no-`timeout` arm RED |
| M4 | Hook: unrunnable routes to the empty-report branch | AC6 unrunnable arm RED (wrong prefix) |
| M5 | `_skip_arm` exits 0 under `CI=true` | AC7 RED |
| M6 | T4 fixed but P1 left on `rc` (a second oracle after a compliant first) | AC8 RED on P1 |

**Harness rows.**
- H1: the stub is on PATH. An arm removes it and must observe "absent". This proves the other
  arms' stubs are actually used.
- H2 (must-PASS non-canonical): a runnable stub whose `version` prints a different version
  string than 8.24.2 is still classified runnable.

**Anchor.** Not applicable.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed. Brainstorm and 2026-09-17 plan carry-forward, plus a plan-review CTO devex
pass (F1–F7; F1, F2, F4 and F5 folded in, F3 cut, F6 noted in Phase 5.2).
**Assessment:** Internal verification machinery, developer-host hooks, and one plugin-distributed
script. No UI, store or infrastructure. The credential-adjacent changes narrow local-scan blind
spots without changing policy.

## Test Scenarios

1. **Given** `diff.mnemonicprefix=true`, **when** a lone `<<<<<<< kb-index:` sentinel is staged in
   `knowledge-base/INDEX.md`, **then** guardrails denies.
2. **Given** `diff.noprefix=true`, **when** `<<<<<<< ours` (column 0) is in `a.md` and `=======`
   in `b.md`, **then** guardrails allows.
3. **Given** `diff.relative=true` and a hook run from a subdirectory, **when** the lone sentinel
   is staged, **then** guardrails denies.
4. **Given** `color.ui=always`, **when** a staged file contains an AWS key, **then** the
   secret-scan hook denies.
5. **Given** `diff.mnemonicprefix=true`, **when** the legal lint sees a scope block violating arm
   (a), **then** it exits 1.
6. **Given** any caller environment, **when** scratch-root's fallback case runs, **then** the
   child sees `XDG_CACHE_HOME` unset.
7. **Given** an unrunnable gitleaks, **when** code-to-prd runs, **then** it exits 2 naming the
   tool and the 8.24.2 pin, and the previous PRD is untouched.
8. **Given** a runnable gitleaks whose scan errors, **when** code-to-prd runs, **then** it exits 2
   "did not complete" and the previous PRD is untouched.
9. **Given** a working gitleaks and no `timeout` binary, **when** code-to-prd or the hook runs,
   **then** the scan runs.
10. **Given** an unrunnable gitleaks, **when** a commit passes the hook, **then** it is allowed
    with a `gitleaks unrunnable` bypass row.
11. **Given** no runnable gitleaks and `CI=true`, **when** a gitleaks suite runs, **then** it
    exits 1 naming the skipped arms. **Given** no `CI`, **then** it exits 0 listing them and
    runs its non-gitleaks arms.
12. **Given** a stub that reports a version but whose scan exits 1 with no report, **when**
    `gitleaks-merge-commit.test.sh` runs, **then** T4, P1 and `arm_dash_m` fail.
13. **Given** no GNU time, **when** TS-cron-5 runs, **then** it measures with `$EPOCHREALTIME`
    and asserts `< 6 s`. **Given** a comma-radix value, **then** the case fails.
14. **Given** no `bc`, **when** registry-userdata-budget runs, **then** it counts the real
    assignments.
15. **Given** Node 26.8.1, **when** the web-platform projects run, **then** they pass with 0
    errors. **Given** Node 22, **then** `execArgv` is `[]`.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The prefix flags interact with `core.quotePath` quoting in the legal lint | Keep the existing `-c core.quotePath=false`; the config rows run the full argv |
| The `GIT_CONFIG_COUNT` colour pin clobbers a user's own env-injected git config | Append to an existing `GIT_CONFIG_COUNT` when set (Phase 1.2) |
| The `execArgv` guard is wrong on unmeasured Node 24/25 | The guard keys on exactly the condition that breaks vitest (the global's presence); the evidence records only the versions measured |
| Phase 1.3 edits a baselined line and reds the required `test` check | Mandatory baseline grep before each edit; drop the file if baselined (the `ship-runbook-ssh-gate.sh` precedent) |
| The battery is refused or contended and stalls the security fixes | Bounded 2 h wait; AC12(b) records rather than demands zero rows; Phases 1 and 3.2 may ship ahead as their own PR if AC12(a) is blocked |
| Changing code-to-prd's copy order alters its output-path semantics for users | AC5(b)/(c) pin previous-PRD preservation; the success path still writes the same file |

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Run the failing suites under `GIT_CONFIG_GLOBAL=/dev/null` | Greens the tests while the production hook stays fail-open |
| Census test over all patch parsers (plan v1) | Cut in plan-review (see Cut List) |
| `NODE_OPTIONS=--no-experimental-webstorage` in `test-all.sh` | Rejected by Node 22.3 ("not allowed in NODE_OPTIONS"); unknown on 20.16 |
| Whole-suite skip when gitleaks is unavailable | Would disarm `gitleaks-rules`' arity/anchor guards, which deliberately run without gitleaks |
| Persist the gitleaks report for code-to-prd findings | Persists unredacted secrets on disk |

## Non-Goals / Out of Scope

- The #8231 scheduler (its plan Phases 1–5 stay under #8231).
- #8271 (lefthook fails open when not on PATH). When fixed, `gitleaks-staged` will need the same
  runnability probe. That dependency is recorded as a comment on #8271, not built here.
- #8274 (`cron-compound-promote` diff allowlist).
- #8045 and decision-challenge UC-1.
- `engines`; Node 20/24/25 claims.
- TS11/TS12 `/usr/bin/time` (`CI=true`-gated; CI runners ship GNU time).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting
  deepen-plan or `/work`.
- Config-row env (`GIT_CONFIG_COUNT`/`KEY_n`/`VALUE_n`) goes on the invocation under test, never
  exported suite-wide. `git-fixture-env.sh` owns its own `GIT_CONFIG_COUNT=1`.
- On this host the "default" config is not default (the global config sets
  `mnemonicprefix=true`). Any row that means "default" must set `GIT_CONFIG_GLOBAL=/dev/null` on
  that one invocation.
- Tool-absence tests must build PATH from symlinks to the exact tools needed. Removing one PATH
  entry does not remove a tool that lives in `/usr/bin` beside `git` and `jq`, and `/usr/bin/time`
  is called by absolute path.
- `$EPOCHREALTIME` requires bash ≥ 5 (`test-all.sh` already requires it). Integer microseconds
  only; never `bc` or float arithmetic, which would reintroduce a missing-tool dependency.
