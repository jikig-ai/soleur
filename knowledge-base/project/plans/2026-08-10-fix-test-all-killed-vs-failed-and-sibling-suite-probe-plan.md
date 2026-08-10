---
title: "fix: test-all.sh must report a KILLED suite as UNRESOLVED, and the sibling probe must see a directly-run suite"
date: 2026-08-10
type: fix
issue: 7424
branch: feat-one-shot-7424-killed-vs-failed-suite-reporting
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
status: reviewed
review_panel: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, cto (devex), strong-model advisor
---

# fix: `test-all.sh` must report a KILLED suite as UNRESOLVED, and the sibling probe must see a directly-run suite

Closes #7424.

> Spec directory did not exist at plan time and carried no `lane:` — defaulted to `cross-domain` (TR2 fail-closed).
> Two review findings argue against operator-stated scope and were **not** applied; they are
> recorded in [`decision-challenges.md`](../specs/feat-one-shot-7424-killed-vs-failed-suite-reporting/decision-challenges.md).

## Overview

`scripts/test-all.sh` has two result classes, `[ok]` and `[FAIL]`. A suite **terminated by a
signal** renders byte-identically to one that **failed an assertion**, and both increment the same
`failed` counter. On 2026-08-10 that produced
`[FAIL] tests/scripts/registry-gate-mutation-battery (560931ms)` on a run where the battery caught
every mutation and left no surviving mutant — the block simply ended with bash's
`Terminated                 "$@"` notice. The suite was byte-identical to `origin/main` and CI
passed it on a clean runner.

The default reading of that line is "the mutation battery on the gate authorizing an irreversible
destroy of production's sole image store is failing." That is the most alarming possible
misreading, and the runner supplies no way to reach the correct one.

Three changes:

1. **A signal-shaped exit becomes its own result class.** `run_suite` captures the exit code (it
   currently does not — R1), classifies it, renders `[KILLED]`, keeps it out of the failure count,
   names it in the summary, and exits with a distinct code. A killed suite is **unresolved** —
   "could not measure" — not red.
2. **The sibling probe gains a second, separately-named scope.** `SIBLING_SUITE_DETECTED` answers
   "is another *suite* in flight?" while `SIBLING_RUN_DETECTED` keeps its exact current semantics.
3. **Long suites get a declared time budget**, so nine minutes is a stated fact rather than a
   surprise.

### What this plan deliberately does NOT determine

**What sent the SIGTERM.** OOM/reaper kill, a wrapper timeout, and a stray signal from a concurrent
session were not distinguished, and nothing here distinguishes them. Per ADR-166 no message this
plan ships may name a cause the runner did not measure. Every hypothesis stays `UNKNOWN` below, and
the `[KILLED]` line says so in words.

### Concurrency constraint

#7376 (`run-registered-suites.sh` flaky under its default `-P`) is **OPEN** with a live session —
worktree `.worktrees/feat-one-shot-7376-suite-runner-parallel-flake`, draft PR #7423 (verified
2026-08-10: only two plan artifacts, no code). **No edit here touches
`apps/web-platform/infra/run-registered-suites.sh`.** Its contract is *read* (R4) and never written.

---

## Premise Validation

| Cited premise | Probe | Result |
| --- | --- | --- |
| #7424 open, unresolved | `gh issue view 7424` | **HOLDS** — `OPEN`, no closing PR |
| #7376 open, PR #7423 draft + code-free | `gh issue view 7376`; `gh pr diff 7423 --name-only` | **HOLDS** — 2 files, both plan artifacts |
| Worktree `feat-fix-7378-sigstore-bundle-index` exists (the invisible sibling) | `git worktree list` | **HOLDS** |
| `run_suite` at col 0 with a col-0 closing brace | `sed -n '143p;188p'` | **HOLDS** — required by the sandbox regex (R2) |
| Sibling matching is argv-position based | read `tc_siblings` | **HOLDS** — verbatim as the issue describes |
| Prior-art learning exists | `ls …2026-08-10-my-sweep-missed-two-red-suites…md` | **HOLDS** |
| Mechanism vs ADR corpus | read ADR-133, ADR-166 | **HOLDS** — neither rejects a result-taxonomy change; ADR-166 *constrains wording* |
| `commit f50003946` is the cited provenance | `git log --oneline` | **HOLDS** |

Nothing cited was stale. One issue-body claim was **wrong** (R1).

---

## Research Reconciliation — claim vs. measured codebase

| Claim | Reality (measured) | Plan response |
| --- | --- | --- |
| **R1.** "`test-all.sh` already captures each suite's exit code" (issue, item 1) | It does **not**. `run_suite` uses `if ! "$@"; then …` — a boolean test; `$?` is read nowhere. | Introduce the capture. `local rc=0` on its own line, then `"$@" \|\| rc=$?`, verified live to capture 1/137/143/255 under `set -euo pipefail` — including through `env VAR=x bash -c '…'` — without aborting. |
| **R2.** (implicit) `run_suite` may be freely restructured | `scripts/test-all-infra-coverage-notice.test.sh` rewrites its body via `re.search(r'^run_suite\(\) \{.*?^\}', s, re.S\|re.M)` and asserts `_infra_in_diff=0` / `_infra_detect_ok=0` occur exactly once. | Keep `run_suite() {` and its `}` at column 0 with **no intermediate column-0 `}`** (AC13). |
| **R3.** "exit 143 means SIGTERM" | `bash -c 'exit 143'` also yields 143. `$?` cannot distinguish a signal death from a literal `exit(143)`. | The `[KILLED]` line reports the **raw rc** as the measurement and `128+N` as a *decode*, and states the ambiguity. It never asserts a signal death as fact. |
| **R4.** "`kill -l` is the decode AND the bounds check" *(my own plan-v1 claim)* | **FALSE, measured:** `kill -l 0` → `EXIT` (rc 0); `kill -l 32`/`33` → **rc 0 with EMPTY output** (glibc-internal SIGCANCEL/SIGSETXID); `kill -l 143` → `TERM` (masks values >64). So rc 128 and rc 160/161 would have classified as `killed`, the latter rendering `= SIG` with a blank name. | Classifier requires a **non-empty** decoded name; `rc > 128` is load-bearing, not redundant; the numeric `<= 192` upper bound stays as defence-in-depth against the masking behaviour. Table gains rows **160, 161, 192**. |
| **R5.** "every new marker must be registered in `MARKER_RE`" *(research-agent claim)* | **FALSE.** That drift guard scans exactly two files — `worktree-manager.sh`, `git-repo-readiness-diag.sh` — for `SOLEUR_*`/`NO_GIT_REPOSITORY`/`worktree wedge:` sentinels. Neither is in scope. | Dropped. No `MARKER_RE` edit. |
| **R6.** "the ADR-166 lint bans six constructions in `scripts/**`" *(my own plan-v1 claim)* | **Incomplete on both axes.** The live `CLAIM` regex also carries `this means (a\|the\|that)`, `which is the <x-y> shape`, `serving is fine`, `not an outage`, `= the EDGE`, the verbs `are\|were`, and the adjectives `only\|underlying\|true` — and the adjective group is **optional**, so bare "is the cause"/"is the fix" are banned. Scope is `DIRS = [".github/workflows", ".github/actions", "scripts", "apps/web-platform/infra"]` over `.yml/.yaml/.sh`, excluding `*.test.sh` and `/tests?/`. | Never restate the list. §2.3 instructs reading the live regex. **Good news the v1 plan missed:** the workflow LEDE in Phase 6 *is* inside the lint's scope, so AC10 covers it — no separate prose check needed. The new `.test.sh` suite is excluded from the lint, which is why its wording assertion was cut as redundant. |
| **R7.** `main-health-monitor.yml` greps `^RED \|^\[FAIL\]` for `HAS_FAIL_MARKER` | A `[KILLED]` line matches neither → falls to the `else` arm, titled "did not complete", lede "usually a step or job timeout". **That same grep also builds `SUMMARY`**, so on a killed-only run the issue body gets only `tail -30` and names **no suite**. | **Fold in** — a separate grep that sets its own flag *and* appends its hits to `SUMMARY`, plus a fourth arm. Without it this PR makes the monitor name an unmeasured cause. |
| **R8.** "no false green is reachable" *(my own plan-v1 threshold justification)* | **FALSE.** `plugins/soleur/skills/test-fix-loop/SKILL.md` terminates on `\| All tests pass \| Zero failures \| … report success \|` — it reads output, not the exit code. A killed-only run parses zero failures → the agent stages fixes and **reports success**. | **Fold in** the third arm there. The threshold justification is rewritten: the invariant is *closed by enumerated fold-ins and pinned by AC7*, not "unreachable by construction". |
| **R9.** `work/SKILL.md` states the reap discriminator as a binary | A third state now exists: the **suite** died while the **runner survived** — `[KILLED]` lines, a terminal marker, and rc=3. | **Fold in** the third arm. |

---

## Open Code-Review Overlap

Query run 2026-08-10 over 64 open `code-review` issues, `jq --arg path … contains($path)` per edited
file. **None** name any file this plan touches.

---

## Hypotheses

The Phase-1.4 network gate fired on the token `timeout`. **Inapplicable**: no network path, no
remote host, no connectivity surface, and no sshd/firewall change is proposed — so the L3→L7
ordering has nothing to order, and `hr-ssh-diagnosis-verify-firewall` telemetry is deliberately
**not** emitted (emitting `applied` for a rule that did not apply is false telemetry, the class
ADR-166 exists to stop). The table stays because the honest disposition of the cause hypotheses is
itself a deliverable.

| # | Hypothesis for what terminated the battery | Discriminator that would settle it | Verdict |
| --- | --- | --- | --- |
| H1 | Kernel/cgroup OOM killer | a kernel-log OOM line correlated to the suite's pid at the kill instant | **UNKNOWN** — not captured; unavailable retrospectively |
| H2 | Wrapper/harness wall-clock timeout | the wrapper's own timeout diagnostic in the same log | **UNKNOWN** — none present, which is *consistent with* but not *evidence for* either arm |
| H3 | Stray signal from a concurrent session | the sender's audit record; `/proc` state at kill time | **UNKNOWN** |
| H4 | The suite terminated itself (`exit 143`) | indistinguishable from H1–H3 via `$?` alone — **measured** | **UNKNOWN** |

**No verdict may be raised without the named discriminator.** A plan that resolved these by
reasoning would reintroduce the defect one layer up.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a `test-all.sh` run whose summary misstates the
result — a real assertion failure re-labelled `[KILLED]` and dropped from the failure count, or a
clean suite labelled `[KILLED]`. Downstream, the operator's `ci/main-broken` issue carries the wrong
title, and an autonomous `test-fix-loop` could stage fixes and report success on an unresolved run.

**If this leaks:** nothing. No secret is read, no network path opened, no store written; `[KILLED]`
uses the stderr channel `[FAIL]` already uses, and the health monitor's existing redaction pass
covers the issue body unchanged.

**Brand-survival threshold:** `aggregate pattern`.

Justification — **corrected after review (R8)**. The failure mode that would earn `single-user
incident` is a false green. Plan v1 claimed it was "unreachable by construction"; that was wrong.
Two agent-level readers terminate on **parsed output**, not the exit code: `test-fix-loop`
("zero failures → report success") and, in a weaker form, any poll anchored on the terminal marker.
The invariant is therefore not free — it is **closed by the Phase-6 fold-ins and pinned by AC7's
executed mutation arm**. With those in place the residual harm is *misattribution on a run that is
still red*, a diagnosis-quality cost compounding across sessions — `aggregate pattern`. If the
Phase-6 fold-ins were cut, this threshold would have to be re-elected.

---

## Blast Radius (measured)

**Process-level consumers** — every invoker of `scripts/test-all.sh`:

| Invoker | Depends on exit code | Parses stdout |
| --- | --- | --- |
| `lefthook.yml` (`bun-test` pre-commit) | binary non-zero | no |
| `ci.yml` — `test-webplat` / `test-bun` / `test-scripts` | step exit = job result | no |
| `main-health-monitor.yml` — tests + infra steps | `${PIPESTATUS[0]}`, re-raised | **yes** (R7) |
| `plugins/soleur/scripts/grok-pre-push-gate.sh` | binary non-zero | no — but **re-emits** `[FAIL] <name>` for any non-zero step |

All are binary zero/non-zero, so exit `3` is safe for every one; exiting `0` on a killed suite would
silently green lefthook, all three CI shards, the grok gate and the monitor. The aggregate `test`
job reads *job results*, and `test` is the required context.

**Agent-level consumers** — readers that terminate on parsed output, not exit code. These are the
ones plan v1 missed:

| Reader | What it reads | Consequence untreated |
| --- | --- | --- |
| `test-fix-loop/SKILL.md` | "zero failures → stage fixes, report success" | **false green** (R8) — folded in |
| `work/SKILL.md` reap discriminator | `[FAIL]` + terminal marker vs. neither | killed reads as a harness reap (R9) — folded in |
| `work/SKILL.md` banner enumeration | closed list `SIBLING_RUN_DETECTED` / `LOW_TMP_HEADROOM` | new banner undocumented — folded in |
| `one-shot/SKILL.md` poll guidance | `^=== N/N suites passed ===$` | safe (killed run is `N<M`, so it never falsely matches green) — **no edit**, stated here so the check is recorded |
| `git-worktree/SKILL.md` | "a killed run and a finished run are indistinguishable **from the process table**" | still true — that sentence is about `/proc`, not runner output — **no edit** |

`TEST_TIMING_LOG` has no automated consumer in-repo, so a third field-3 state is free.

---

## Architecture Decision (ADR/C4)

This changes the repo's **test-result taxonomy and exit contract** — two result classes become
three, and a new non-zero exit appears. ADR-133 documents the contention layer around this runner
and says nothing about what its results mean, so a future engineer reading only the ADRs would be
misled.

### ADR

**Create `ADR-175-test-runner-result-taxonomy-unresolved-is-not-failed.md`**. Decision: *a suite
whose exit is signal-shaped with a decodable signal name is an UNRESOLVED result — its own marker,
excluded from the failure count, named in the summary, surfaced as a distinct non-zero exit code;
the runner never names what terminated it.* `## Alternatives Considered` carries A1–A5 below.
`## Consequences` must state the wrapper-absorption limit (R4 in Risks) and that exit 3 is a
**top-level-only** contract.

> **Ordinal is PROVISIONAL.** 174 is the highest on this branch; `adr-ordinals` is not a required
> check, so a sibling PR can claim 175 and the collision surfaces only post-squash. `/ship`'s
> ADR-Ordinal Collision Gate re-derives it against freshly-fetched `origin/main`. **On any
> renumber, sweep the whole artifact set in the same edit:**
> `grep -rn 'ADR-175' knowledge-base/project/{plans,specs}/feat-one-shot-7424-*/` plus this body and
> AC16 — a renumber reaching only the ADR file leaves an AC asserting a nonexistent path.

### C4 views

**No C4 impact**, enumerated against all three model files (read in full, not keyword-grepped):

- **(a) External human actors** — the four modelled are `founder`, `emailSender`, `betaContact`,
  `contributor`. A contributor running the local test runner is not a modelled relationship at any
  level; the runner has no element.
- **(b) External systems** — `github` is modelled and already carries CI edges (`-> tunnel`,
  `-> ghcr`, `-> betterstack`, `-> sentry`, `-> sigstore`). No new vendor edge; the monitor already
  files issues and posts a Sentry check-in, and neither behaviour changes.
- **(c) Containers / data stores** — none created, renamed, or re-described.
- **(d) Actor↔surface access relationships** — none change.

No `.c4` edit, hence no `views.c4` include and no re-run of the c4 syntax/render tests.

### Sequencing

True the moment the code merges — no soak, no `status: adopting`. ADR-175 ships in this PR.

---

## Observability

```yaml
liveness_signal:
  what: "the terminal marker `=== N/M suites passed ===`, plus a
         `=== M suites: P passed, F failed, K killed (unresolved) ===` breakdown line
         emitted only when K > 0"
  cadence: "once per test-all.sh invocation (every local exit gate, every CI shard,
            every main-health-monitor fire)"
  alert_target: "run stdout + stderr; GitHub Actions job status; the ci/main-broken issue"
  configured_in: "scripts/test-all.sh (summary block); .github/workflows/main-health-monitor.yml"

error_reporting:
  destination: "exit code (0 pass / 1 failed / 3 killed-only) consumed by ci.yml's three shard
                jobs -> the required `test` context, by lefthook, and by grok-pre-push-gate.sh;
                plus the ci/main-broken issue, whose body now carries the [KILLED] lines"
  fail_loud: true   # killed-only exits 3 -> non-zero -> the required check reds. No arm
                    # yields exit 0 with killed > 0; AC7 proves it by mutation, not by grep.

failure_modes:
  - mode: "a suite is terminated by a signal while the runner survives"
    detection: "`[KILLED] <label> (exit=<rc>, ...)` on stderr + the breakdown line + exit 3;
                TEST_TIMING_LOG field 3 = KILLED when the log is enabled"
    alert_route: "required `test` context reds; main-health-monitor files ci/main-broken titled
                  'terminated before it could report', with the [KILLED] lines in the body"
  - mode: "the classifier returns an unrecognized class (degradation or a future edit)"
    detection: "`WARNING: suite_exit_class returned unrecognized class ...` on stderr"
    alert_route: "counted as FAILED -> exit 1 -> required check reds (fail-closed, never passed)"
  - mode: "the runner ITSELF is terminated (whole process group), so nothing classifies"
    detection: "absence of the terminal marker -- the pre-existing documented discriminator"
    alert_route: "unchanged by this plan; explicitly out of reach (Risks R3)"
  - mode: "a sibling worktree is running an individual suite directly during this run"
    detection: "`[contention] BANNER SIBLING_SUITE_DETECTED: ...` on stderr before suite 1,
                each sibling resolved to its worktree via /proc/<pid>/cwd"
    alert_route: "advisory stderr banner (same contract as SIBLING_RUN_DETECTED -- observe only)"
  - mode: "a suite exceeds its declared time budget"
    detection: "`[budget] <label> ran <X>ms against its declared <Y>ms budget` on stderr"
    alert_route: "advisory stderr line; never changes status or exit code"

logs:
  where: "run stdout + stderr; TEST_TIMING_LOG when set; GitHub Actions run logs;
          the two capture files main-health-monitor.yml tees into"
  retention: "GitHub Actions default (90d); TEST_TIMING_LOG is caller-owned per run"

discoverability_test:
  command: "bash scripts/test-all-killed-classification.test.sh"
  expected_output: "table-driven classifier rows incl. the 160/161 empty-name boundary; a [KILLED]
                    line for the self-terminating fixture; exactly one [FAIL]; a killed-bucket
                    breakdown line; runner exit 3 on the killed-only arm; and two mutation arms
                    that must RED. Runs on the local filesystem; needs no remote host, no credential."
```

### Soak follow-through enrollment

**Not applicable.** No acceptance criterion is time-gated; nothing closes on a soak window.

### Affected-surface observability

Not a blind surface (no bwrap sandbox, no container readiness gate, no cron worker). The runner
writes to the operator's terminal and the CI job log; both are directly readable.

---

## Domain Review

**Domains relevant:** Engineering (CTO lens) only.

### Engineering

**Status:** reviewed — 5-reviewer panel (DHH, Kieran, code-simplicity, CTO devex, strong-model
advisor). 3 P0s and 12 P1/P2s applied; 2 findings against operator-stated scope recorded in
`decision-challenges.md` rather than applied.

**Assessment:** the load-bearing risks are (1) mis-bucketing a real failure as unresolved — closed
by requiring a non-empty decoded signal name, a fail-closed `*)` arm, and the executed mutation arm
in AC7; (2) breaking a widely-consumed marker line — closed by preserving `=== N/M suites passed ===`
byte-shape and gating the breakdown line on `killed > 0`; (3) a banner that fires on every run —
closed by ancestry/pgid cancellation plus an explicit no-sibling negative control.

**Product/UX Gate:** skipped. No file in Files to Create/Edit matches the UI-surface glob superset
(`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`) or term list; the mechanical
override did not fire.

**Brainstorm-recommended specialists:** none (no brainstorm preceded this plan).
**Skipped specialists:** none.

## Compliance gates

- **GDPR / 2.7:** skipped — no schema, migration, auth flow, API route or `.sql`; no LLM/external
  processing of operator data; no new distribution surface; threshold is not `single-user incident`.
- **IaC / 2.8:** **reviewed and skipped.** No server, service, scheduled job, vendor account, DNS
  record, certificate, secret or firewall rule. Every touched file is a repo-local shell script,
  bash suite, workflow YAML or markdown doc, and every phase step runs on the contributor's own
  checkout. The Phase-2.8 detection token set — remote-shell invocations, unit-manager commands,
  secret-store writes, state imports, vendor-dashboard wording — matches nothing in the phases.
  <!-- iac-routing-ack: plan-phase-2-8-reviewed -->
- **Encryption Posture / 2.11:** skipped — no persistent store, no new cross-component connection,
  no `.tf` / `supabase/migrations/*.sql` / `cloud-init*.yml` / `docker-compose*.yml`.

---

## Implementation Phases

### Phase 0 — Preconditions

0.1 Branch is `feat-one-shot-7424-killed-vs-failed-suite-reporting`; `git status --porcelain` empty.

0.2 Re-measure the classifier oracle on this host (do not inherit the plan's numbers):

```bash
for n in 0 15 31 32 33 64 65; do
  if out=$(kill -l "$n" 2>&1); then printf 'n=%-3s rc=0 out="%s"\n' "$n" "$out"
  else printf 'n=%-3s rc=1 REJECT\n' "$n"; fi
done
kill -l 143   # must print TERM — proof that kill -l MASKS values > 64
```

Expected: `0 → EXIT`, `15 → TERM`, `31 → SYS`, **`32`/`33` → rc 0 with EMPTY output**, `64 → RTMAX`,
`65 → REJECT`, `143 → TERM`. If 32/33 are non-empty on this host, the classifier still holds (the
non-empty test simply never fires there) — but record the difference.

0.3 Re-verify the sandbox anchors the edit must not break:

```bash
grep -n '^run_suite() {' scripts/test-all.sh          # exactly 1
grep -c '^_infra_in_diff=0$' scripts/test-all.sh      # exactly 1
grep -c '^_infra_detect_ok=0$' scripts/test-all.sh    # exactly 1
awk 'NR>=143 && NR<=210 && /^}/ {print NR": "$0}' scripts/test-all.sh  # first col-0 } is run_suite's
```

0.4 Capture pre-edit gate baselines: `bash scripts/lint-diagnosis-claims.sh` (expect `OK — 1 …
(baseline 1)`), `python3 scripts/lint-shell-capture-exit.py --baseline …` (expect `0 new findings`),
`bash scripts/lint-orphan-test-suites.sh` (expect `none`).

### Phase 1 — RED: the classifier, as a stub

The classifier lives **inline in `scripts/test-all.sh`**, not in a `scripts/lib/` file. Reason,
measured: `scripts/test-all-infra-coverage-notice.test.sh` builds its sandbox with
`cp "$TARGET" "$out"` — a **single-file** copy. A sourced lib would be absent under test, the
degradation path would fire, and the KILLED assertions would silently test the fallback instead of
the classifier. Inlining removes the sourcing, the degradation stub, and two files.

1.1 Add `suite_exit_class()` to `scripts/test-all.sh` as a **stub** (`printf 'failed\n'`), above
    `run_suite`, outside the `run_suite() { … }` brace range.

1.2 Create `scripts/test-all-killed-classification.test.sh` with **Part A** only for now: extract
    the function from `scripts/test-all.sh` by anchored range
    (`sed -n '/^suite_exit_class() {/,/^}/p'`, with an `assert count == 1` on the opening anchor),
    source it in a subshell, and table-drive:

    `0, 1, 2, 124, 126, 127, 128, 129, 130, 134, 136, 137, 139, 141, 143, 159, 160, 161, 192, 193, 255`

    **160/161 and 192 are load-bearing rows** and were absent from plan v1: 160/161 are the
    `kill -l` empty-name case, 192 the numeric upper bound. Expected: `0 → ok`;
    `129,130,134,136,137,139,141,143,159,192 → killed`; **everything else → `failed`**, including
    `128` (`kill -l 0` succeeds with `EXIT`), `160`, `161`, `193`, `255`, and `124`.

    > `124` stays `failed` deliberately: GNU `timeout` returns it from *its own* exit, so it is an
    > attributed verdict by a named tool. Precedent: `scripts/lint-workflows.sh`'s rc `case`
    > classifies 124 as HUNG *by name*. Folding it into the unattributed `killed` bucket would lose
    > the attribution this plan exists to add.

    Add a `MIN_ASSERTIONS` floor (the sibling suites' anti-vacuity idiom) so a stranded run cannot
    read as clean. Run it now and confirm it **REDs** against the stub.

### Phase 2 — GREEN: classify, render, count, exit

2.1 Fill in `suite_exit_class`. The `kill -l` call must be guarded so it cannot abort the runner
    under `set -e`, and the decoded name must be **non-empty**:

```bash
suite_exit_class() {
  local rc="$1" name
  (( rc == 0 )) && { printf 'ok\n'; return 0; }
  if (( rc > 128 && rc <= 192 )); then
    name=$(kill -l $(( rc - 128 )) 2>/dev/null) || name=""
    [[ -n "$name" ]] && { printf 'killed\n'; return 0; }
  fi
  printf 'failed\n'
}
```

Every guard is load-bearing and was measured (R4): `rc > 128` because `kill -l 0` succeeds with
`EXIT`; `<= 192` because `kill -l` **masks** values above 64 (`kill -l 143` → `TERM`); `-n "$name"`
because signals 32/33 succeed with empty output. Do not "simplify away" any of the three.

2.2 Initialize the counter beside the existing `failed=0` / `suites=0`:

```bash
killed=0
```

Under `set -u` an uninitialized `killed` would abort **after** the terminal marker but **before**
the exit arm — producing exit 0 on a run that had failures. This line is not cosmetic.

2.3 Rewrite `run_suite`'s status block. The default arm is the fail-closed half:

```bash
  local rc=0
  "$@" || rc=$?
  local status="failed"
  status="$(suite_exit_class "$rc" 2>/dev/null)" || status="failed"
  case "$status" in
    ok)     ;;
    failed) failed=$((failed + 1)) ;;
    killed) killed=$((killed + 1)) ;;
    *)      echo "WARNING: suite_exit_class returned unrecognized class '$status' for rc=$rc; counting as FAILED." >&2
            status="failed"; failed=$((failed + 1)) ;;
  esac
```

Without `ok)` and `*)`, any unexpected value increments neither counter and
`$((suites - failed - killed))` counts the suite as **passed** — the exact false green this plan
exists to prevent. Constraints (AC13): `run_suite() {` and its `}` stay at column 0 with **no new
column-0 `}`** between them.

2.4 Render. `[ok]` and `[FAIL]` keep their **exact current text** — every monitor, learning and
skill anchored on `^\[FAIL\]` must keep working byte-for-byte. The new line:

```
[KILLED] <label> (exit=<rc>, signal-shaped 128+<n> = SIG<NAME>, <ms>ms) — UNRESOLVED, not a failure: this runner did not measure what terminated it, and exit <rc> is also what a suite calling exit(<rc>) reports.
```

**Before writing this string, read the live `CLAIM` regex in `scripts/lint-diagnosis-claims.sh`**
and check the line against it. Do not work from a restated list — plan v1's list was incomplete on
both the phrase set and the optional-adjective structure (R6). The lint's scope covers
`scripts/*.sh`, so `scripts/test-all.sh` is gated by AC10.

2.5 `TEST_TIMING_LOG` field 3 becomes `KILLED` for the killed arm, preserving the labelled
    `tmp_delta=<N>` trailing field. Update the header's format contract comment
    (`"<label>\t<elapsed_ms>[\tFAIL]"`) in the same edit.

2.6 Summary and exit contract:

```bash
echo "=== $((suites - failed - killed))/$suites suites passed ==="
if (( killed > 0 )); then
  echo "=== $suites suites: $((suites - failed - killed)) passed, $failed failed, $killed killed (unresolved) ==="
fi
...
if (( failed > 0 )); then
  exit 1
elif (( killed > 0 )); then
  exit 3
fi
```

The first line keeps its byte shape (`^=== N/M suites passed ===$`) — anchored by four skills and
~30 learnings. The breakdown line is gated on `killed > 0`, so a clean run's output is byte-identical
to today's. Document the contract in a header block modelled on `scripts/zot-restart-loop-alarm.sh`'s
`EXIT CONTRACT`:

```
#   0  every registered suite passed
#   1  >= 1 suite FAILED (an assertion verdict) — failure dominates when both are present
#   3  0 failures and >= 1 suite KILLED — UNRESOLVED, not measured, and NOT green
#      3 is a TOP-LEVEL contract only: a nested runner returning 3 into run_suite classifies
#      as a plain FAIL, because rc=3 is not signal-shaped. Do not adopt 3 in a nested runner
#      without revisiting this.
```

### Phase 3 — the integration half: does the RUNNER render it?

3.1 Extend `scripts/test-all-killed-classification.test.sh` with **Part B**, following
    `scripts/test-all-infra-coverage-notice.test.sh`: `TARGET` overridable so the suite can be
    pointed at a mutated copy and proved to RED; `mktemp -d` sandbox with `trap … EXIT`;
    pass/fail counters; the `MIN_ASSERTIONS` floor.

3.2 Sandbox mechanism — a `python3` heredoc mutating a **copy**, with `assert s.count(<anchor>) == 1`
    on every anchor so a rename fails loudly rather than silently no-op'ing. Keep `run_suite`, the
    summary block and the exit block **intact and under test**; replace everything between the
    `tc_acquire "test-all"` line and the `tc_epilogue "${_TC_RUN_START_ENTRIES:-0}"` line with
    fixture `run_suite` calls whose scripts are written into the sandbox: `ok` (`true`),
    `assertfail` (`exit 1`), `selfterm` (`kill -TERM $$; sleep 5`). The fixture signals **itself**,
    so there is no timing race.

3.3 Arms:
    - **A1** killed-only: exactly one `^\[KILLED\]` naming `selfterm`; zero `^\[FAIL\]`;
      `failed` count 0; the breakdown line reports `1 killed (unresolved)`; runner exit **3**.
    - **A2** mixed (one `exit 1` + one self-SIGTERM): both markers; exit **1**.
    - **A3** clean: the tail matches the pre-change shape — one
      `^=== [0-9]+/[0-9]+ suites passed ===$` and **no** breakdown line — diffed against the tail
      produced by `git show origin/main:scripts/test-all.sh` run through the same sandbox, which is
      the only way "byte-identical" is checkable inside the PR.
    - **A4** `[ok]` / `[FAIL]` literals unchanged.
    - **A5** mutation control: a copy whose `suite_exit_class` always returns `failed` → A1 must RED.
    - **A7** mutation control for the exit contract: a copy with the `killed)` arm removed → the
      killed-only run must exit **0**, and the suite must RED. This is what makes AC7 a proof
      instead of an assertion.

    *(Plan v1's A6 — grepping the emitted line against the ADR-166 ban list — is cut. The lint
    already scans `scripts/test-all.sh`, so A6 duplicated AC10; both simplification reviewers
    flagged it.)*

3.4 Register in the second `want_scripts` block next to `scripts/test-all-infra-coverage-notice`
    (both shell out to `python3`), in the exact shape `scripts/lint-orphan-test-suites.sh` greps for:

```bash
  run_suite "scripts/test-all-killed-classification" bash scripts/test-all-killed-classification.test.sh
```

    with a preceding comment stating why it is registered explicitly, matching every neighbour.

### Phase 4 — widen the sibling probe (`SIBLING_SUITE_DETECTED`)

4.1 Parameterise the scan: `tc_siblings [mode]`, `mode` defaulting to `run`. The run matcher is
    **moved, not modified** — byte-identical predicate, same argv-position discipline, same
    rejected-alternatives comment block. The default keeps every existing caller (including the 73
    assertions in `scripts/test-contention.test.sh`) working unchanged; **that suite passing
    unmodified is the regression proof that `SIBLING_RUN_DETECTED` semantics did not move** (AC5).

4.2 The `suite` matcher, same discipline:
    - `argv[0]` basename matches `*.test.sh`, **or** matches `test-*.sh` and is **not**
      `test-all.sh`; **or**
    - `argv[0]` is a shell (`bash|sh|dash|zsh|ksh`) **and** some later argv element is a
      whitespace-free token whose basename satisfies the same predicate.

    Document inline, alongside the existing rejected-alternatives list, the three known scope edges
    — all measured, none fatal:
    - the `test-all.sh` exclusion is load-bearing: the runner itself matches `test-*.sh`, so without
      it every full run would also count as a suite sibling and the banner would fire on every solo
      run — the "a banner that always fires carries no information" failure the original comment
      block exists to prevent;
    - the predicate is deliberately over-broad in one direction (`scripts/lib/test-contention.sh`
      matches `test-*.sh`; it is sourced, never executed, so this is latent);
    - and under-broad in another (`tests/hooks/test_incidents.sh` uses an underscore and matches
      neither rule; `timeout N bash <suite>` and `env VAR=x bash <suite>` put a non-shell at
      `argv[0]`, both real shapes in this repo). Ancestry cancellation (4.3) is what keeps the
      under-broad cases from mattering for the run-child case.

4.3 **Cancel sibling-run children by ancestry/pgid, not by cwd.** Plan v1 used a cwd set-difference;
    review measured three ways it produces a wrong count:
    - suites routinely `cd` into a `mktemp -d` sandbox, so the same worktree appears under two
      unequal cwd strings and the difference **fails to cancel** — double-reporting the worktree the
      difference existed to protect;
    - `tc_siblings` substitutes the literal `<unreadable>` for any cwd it cannot read, so all such
      processes share one pseudo-"worktree" — a single unreadable run match would subtract **every**
      unreadable suite match;
    - a run launched as `env … bash scripts/test-all.sh` or `timeout … bash scripts/test-all.sh`
      has a non-shell `argv[0]`, so **no run match exists at all** while its suite children match —
      reporting a full run as "a worktree running an individual suite".

    Instead: for each suite match, walk its ppid chain with the existing `_tc_ppid` helper under the
    same 64-step guard; drop it if any ancestor satisfies the **run** predicate. Fall back to "some
    run match shares this pid's pgrp" via the existing `_tc_pgrp` for the wrapper case (measured: a
    `run_suite` child inherits the runner's pgid under a non-interactive shell). Ancestry is
    invariant under `cd`, immune to `<unreadable>`, and reaches through `env`/`timeout` wrappers.

    Do **one** `/proc` walk and classify each pid into both buckets. Plan v1 called `tc_siblings`
    twice, producing two non-atomic snapshots over which a difference can be computed on
    inconsistent sets.

    Own-suite children cannot self-match: `tc_preamble` runs before the first `run_suite`, and the
    existing `self_pgrp` exclusion covers this run's children in any case. State both inline so a
    later "call the preamble mid-run" edit meets the reasoning.

4.4 Emit, matching the existing banner style:

```
[contention] suite siblings: N other worktree(s) running an individual test suite
[contention]   -> pid <p> in <cwd> (running <e>s)
[contention] BANNER SIBLING_SUITE_DETECTED: an individual test suite is running in N other worktree(s) (listed above). This runner competes with it for the same tmpfs capacity. Confirm a failure three ways — isolated re-run, the matching CI gate, and a clean full re-run once the sibling exits — before accepting it as real.
```

    `SIBLING_RUN_DETECTED`'s line and condition are **not touched**.

4.5 Arms in `scripts/test-contention.test.sh`, using the existing `make_fake_proc` synthetic procfs
    (extended so `argv[0]` is parameterisable — today it hardcodes `bash`):
    fires for `bash tests/scripts/test-foo.sh`; fires for `./scripts/foo.test.sh` as `argv[0]`;
    does **not** fire for `bash scripts/test-all.sh`; does **not** fire for a whitespace-bearing
    `bash -c` string; **T11** a run + its suite child → counted once, run banner only; **T11b**
    `env VAR=x bash scripts/test-all.sh` + a suite child → counted once, run banner only (the
    wrapper case cwd could not handle); **T11c** `<unreadable>` cwd on both a run and a suite match
    → no cross-cancellation; **T13** no siblings → **neither** banner fires.

### Phase 5 — declared time budgets

> Two reviewers recommend cutting this phase outright and a third found its AC vacuous. It is
> **operator-stated scope** (issue item 3), so it is kept with the vacuity closed, and the
> recommendation is recorded as **UC-1** in `decision-challenges.md` for the operator to decide.

5.1 Add `_suite_budget_ms <label>` as a **`case` statement**, not `declare -A`. Reason (corrected):
    *not* bash 3.2 portability — `scripts/lib/test-contention.sh` already uses `mapfile -t -d ''`
    (bash 4.4+) and is sourced unconditionally, so the runner cannot run on 3.2 anyway. The real
    reason is simpler: a `case` needs no initialization ordering, no associative-array declaration
    at the top of a 866-line script, and zero churn at the 131 `run_suite` call sites.

5.2 After the elapsed computation, when a budget is declared and exceeded, emit an advisory line.
    It **never** changes status or exit code:

```
[budget] <label> ran <X>ms against its declared <Y>ms budget — expected-long suite, declared here so a long run is a stated fact rather than a surprise.
```

5.3 **Measure, do not guess.** The incident's `560931ms` is elapsed **at the kill**, mid-way through
    the engine-mutation phase — a *lower bound* on the clean duration and useless as a budget.
    Measure standalone with no sibling load:

```bash
TEST_TIMING_LOG=/var/tmp/7424-timing.tsv bash tests/scripts/test-registry-gate-mutation-battery.sh
```

    Set each budget at a stated multiple of the measured clean duration and write the measurement,
    the date and the multiple into the comment beside the value. **If the battery is itself killed
    during measurement** — the live possibility this whole plan is about — do **not** ship an empty
    lookup: record the attempt and defer Phase 5 to the Phase-7.2 tracking issue. An empty `case`
    would satisfy a naive AC while delivering none of item 3, which is why AC15 requires at least
    one non-empty declared budget.

### Phase 6 — fold-in consumers

6.1 `.github/workflows/main-health-monitor.yml`:
    - a **second, separate** grep that sets its own flag **and appends its hits to `SUMMARY`**:

```bash
killed_hits=$(grep -E '^\[KILLED\]' "$file" | head -20) || killed_hits=""
if [[ -n "$killed_hits" ]]; then
  HAS_KILLED_MARKER=1
  SUMMARY="${SUMMARY}${killed_hits}"$'\n'
fi
```

      The append is not optional. The existing `hits` variable feeds **both** `HAS_FAIL_MARKER`
      **and** `SUMMARY`, so a killed-only run would otherwise produce an issue body containing only
      `tail -30` — and the runner emits the contention epilogue plus up to four multi-line infra
      NOTE blocks after the summary, so a `[KILLED]` line 200 suites earlier falls outside that
      window. The operator would get an issue titled "terminated" that names **no suite**.
    - **Do not** add `[KILLED]` to the existing `grep -E '^RED |^\[FAIL\]'`: it would set
      `HAS_FAIL_MARKER` (re-labelling an unresolved run "tests failing" — the conflation this PR
      removes) and would break assertion (8) of the pinning suite, whose regex ends on the literal
      `^\[FAIL\]'`.
    - a **fourth** classification arm, ordered after the failure arm so failure dominates:

```
TITLE="CI: main-branch health check was terminated before it could report"
HEADING="Run did not complete — a suite was terminated"
LEDE="At least one suite exited with a signal-shaped status (128+N). The runner reports this as unresolved: it did not measure what terminated the suite, so this issue is not a statement that main is broken."
```

    - **fix the pre-existing third-arm LEDE** in the same edit. It currently reads *"This is usually
      a step or job timeout"* — a cause the job did not measure, in the very file whose own comment
      block states the ADR-166 rule. The lint's `CLAIM` regex has no `usually` pattern, which is why
      it survives; that makes it a genuine miss rather than an accepted exception. One line, same
      file, same defect class as the work in hand (`rf-review-finding-default-fix-inline`).

6.2 `plugins/soleur/test/main-health-monitor-workflow.test.sh`: assertion (8) stays **unchanged**.
    Add (8b) — the workflow greps `^\[KILLED\]` into a distinct variable, appends those hits to
    `SUMMARY`, and carries a fourth title/lede arm naming no cause — with a `bad()` message
    explaining what regresses without it.

6.3 `plugins/soleur/skills/work/SKILL.md` — two edits:
    - the reap-vs-failure discriminator gains a third arm: a **suite** killed while the runner
      survived leaves `[KILLED]` lines, a terminal marker **and** rc=3, distinguishable from both a
      real failure and a harness reap of the runner itself;
    - the closed banner enumeration `SIBLING_RUN_DETECTED` / `LOW_TMP_HEADROOM` gains
      `SIBLING_SUITE_DETECTED`.

6.4 `plugins/soleur/skills/test-fix-loop/SKILL.md` — **the false-green fold-in (R8).** Its
    termination table fires on "All tests pass | Zero failures", which a killed-only run satisfies:
    the loop would stage fixes and report success on a run that measured nothing. Add the third
    state — a run with `[KILLED]` lines or rc 3 is **unresolved**: do not report success, do not
    stage, re-run the killed suite in isolation.

6.5 Recorded as **checked, no edit needed** (so the next reader does not re-derive it):
    `one-shot/SKILL.md`'s `^=== N/N suites passed ===$` poll is safe — a killed run is `N < M`, so
    it can never falsely match green. `git-worktree/SKILL.md`'s "a killed run and a finished run are
    indistinguishable" sentence is about the **process table**, not runner output, and stays true.
    `grok-pre-push-gate.sh` re-emits `[FAIL] <step-name>` for any non-zero step; that label means
    "this step did not pass", which remains true for exit 3 — noted, not changed.

### Phase 7 — ADR + deferral

7.1 Write ADR-175 per §Architecture Decision.

7.2 File **one** tracking issue for deferred parity. Triple test (`wg-defer-only-after-inline-triage`)
    run 2026-08-10 and passed on all three arms: **(1)** inline-first fails —
    `run-registered-suites.sh` is PR #7423's live target; **(2)** concrete trigger exists — "#7376
    merges" (verified `OPEN`); **(3)** plausible within 6 months — live session, open draft PR.
    Scope: signal classification in the wrapper surfaces R4 names, plus Phase 5's budgets if
    measurement was deferred. Verify labels exist (`gh label list --limit 200`) before filing.

### Phase 8 — verification

8.1 `bash scripts/test-all-killed-classification.test.sh`
8.2 `bash scripts/test-contention.test.sh`
8.3 `bash scripts/test-all-infra-coverage-notice.test.sh` (proves the `run_suite` anchors survive)
8.4 `bash scripts/lint-orphan-test-suites.sh`
8.5 `bash scripts/lint-diagnosis-claims.sh` (live count ≤ highwater 1; covers both `test-all.sh`
    and the workflow LEDE)
8.6 `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
8.7 `bash plugins/soleur/test/main-health-monitor-workflow.test.sh`
8.8 Full-suite exit gate: `bash scripts/test-all.sh` on a clean tree; read the terminal marker.

---

## Files to Edit

| Path | Change |
| --- | --- |
| `scripts/test-all.sh` | inline `suite_exit_class`; `killed=0` beside `failed=0`/`suites=0`; `run_suite` rc capture + 4-arm `case` incl. fail-closed default; `[KILLED]` render; `TEST_TIMING_LOG` field-3 `KILLED` + header contract comment; breakdown line; `exit 3` arm + EXIT CONTRACT block; `_suite_budget_ms` `case` + `[budget]` line; one `run_suite` registration |
| `scripts/lib/test-contention.sh` | `tc_siblings [mode]` (run matcher moved unchanged); `suite` matcher + scope-edge comments; single-walk ancestry/pgid cancellation; `SIBLING_SUITE_DETECTED` banner |
| `scripts/test-contention.test.sh` | parameterise `make_fake_proc`'s `argv[0]`; 8 new arms incl. T11b/T11c/T13; every existing arm passes unchanged |
| `.github/workflows/main-health-monitor.yml` | `^\[KILLED\]` grep into its own flag **+ SUMMARY append**; fourth arm; fix the pre-existing "usually a step or job timeout" LEDE; existing `^RED \|^\[FAIL\]` grep byte-unchanged |
| `plugins/soleur/test/main-health-monitor-workflow.test.sh` | assertion (8b); (8) unchanged |
| `plugins/soleur/skills/work/SKILL.md` | third arm in the reap discriminator; banner enumeration gains `SIBLING_SUITE_DETECTED` |
| `plugins/soleur/skills/test-fix-loop/SKILL.md` | third termination state — unresolved ≠ pass |

## Files to Create

| Path | Purpose |
| --- | --- |
| `scripts/test-all-killed-classification.test.sh` | Part A: table-driven classifier over 21 rows incl. 160/161/192. Part B: sandbox proof the **runner** renders KILLED, excludes it from the failure total, exits 3 — plus mutation arms A5/A7 |
| `knowledge-base/engineering/architecture/decisions/ADR-175-test-runner-result-taxonomy-unresolved-is-not-failed.md` | the decision, A1–A5, and the wrapper-absorption + top-level-exit-3 consequences |

*(Plan v1's `scripts/lib/suite-exit-class.sh` and `scripts/lib/suite-exit-class.test.sh` are **not**
created — see Phase 1.)*

---

## Acceptance Criteria

All pre-merge. **No post-merge operator steps.**

1. **AC1 — killed renders distinctly.** The self-SIGTERM fixture yields exactly one
   `^\[KILLED\] selfterm ` and zero `^\[FAIL\] selfterm`.
2. **AC2 — killed is excluded from the failure total.** On the killed-only arm `failed` is 0 and the
   killed suite counts as neither passed nor failed in `=== N/M suites passed ===`; the breakdown
   line reports `1 killed (unresolved)`.
3. **AC3 — killed-only is not green.** Runner exit is **3**, asserted on the captured rc.
4. **AC4 — failure dominates.** Mixed arm exits **1**, both markers present.
5. **AC5 — `SIBLING_RUN_DETECTED` unchanged.** `bash scripts/test-contention.test.sh` passes with
   every pre-existing arm **unmodified**. *(Plan v1's "git diff shows moved lines only" clause is
   dropped: git renders a moved block as delete+add, so no diff invocation can check it.)*
6. **AC6 — the new probe fires on a directly-run suite and only then.** Arms prove: fires for
   `bash tests/scripts/test-foo.sh` and for `./scripts/foo.test.sh` as `argv[0]`; does not fire for
   `bash scripts/test-all.sh`; does not fire for a whitespace-bearing `bash -c` string; a run + its
   suite child counts once (run banner only); an `env`-wrapped run + its suite child counts once;
   `<unreadable>` cwds do not cross-cancel; no siblings → neither banner.
7. **AC7 — no false green, proved by mutation.** Arm A7: a copy with the `killed)` arm removed makes
   the killed-only run exit 0, and the suite REDs. Arm A5: a copy whose classifier always returns
   `failed` makes A1 RED. *(Plan v1's grep-based AC is dropped — a grep cannot establish a negative
   existential over control flow, and the property was in fact violable by the missing `case`
   default a grep would never see.)*
8. **AC8 — the terminal marker's byte shape is preserved.** On `killed == 0` the tail is diffed
   against the tail produced by running `git show origin/main:scripts/test-all.sh` through the same
   sandbox, and the diff is empty.
9. **AC9 — `[ok]` / `[FAIL]` literals unchanged**, asserted against the literal strings.
10. **AC10 — the ADR-166 lint stays green.** `bash scripts/lint-diagnosis-claims.sh` exits 0 with a
    live count ≤ the committed highwater `1`; the highwater is **not** raised. Its `DIRS` covers
    both `scripts/test-all.sh` and `.github/workflows/main-health-monitor.yml`, so this single
    command gates every new message this PR ships.
11. **AC11 — shell-capture lint green.** `0 new findings`; the baseline file is **not** edited.
12. **AC12 — no orphan suite.** `bash scripts/lint-orphan-test-suites.sh` prints
    `orphan test suites: none`; its `EXCLUSIONS` array stays empty.
13. **AC13 — sandbox anchors survive.** `bash scripts/test-all-infra-coverage-notice.test.sh` passes,
    and `grep -n '^run_suite() {'` returns exactly one line whose matching close brace is the first
    subsequent column-0 `}`.
14. **AC14 — the monitor names no unmeasured cause, and names the suite.** A `^\[KILLED\]` grep
    exists in a variable distinct from `HAS_FAIL_MARKER`; **its hits are appended to `SUMMARY`**, so
    a killed-only fixture log yields an issue body containing the `[KILLED]` line; the existing
    `grep -E '^RED |^\[FAIL\]'` is byte-unchanged; the fourth arm's LEDE contains no banned
    construction and does not contain the word `timeout`; the pre-existing third-arm LEDE no longer
    asserts a timeout. `bash plugins/soleur/test/main-health-monitor-workflow.test.sh` passes with
    (8) unmodified and (8b) present.
15. **AC15 — budgets are declared and measured, or explicitly deferred.** Either
    `_suite_budget_ms tests/scripts/registry-gate-mutation-battery` returns a **non-empty integer**
    and every declared value carries a comment naming the measured wall-clock, the date and the
    multiple — **or** Phase 5 is recorded as deferred to the Phase-7.2 issue with the measurement
    attempt noted. An empty `case` shipped silently satisfies neither branch. T14 proves the emitter
    independently via a fixture with a 0 ms budget.
16. **AC16 — the ADR ships with the code.** `ADR-175-*.md` exists; its `## Decision` states the
    three-class taxonomy and the 0/1/3 contract; `## Consequences` states the wrapper-absorption
    limit and that 3 is top-level-only; `## Alternatives Considered` carries A1–A5. After any
    ship-time renumber, `grep -rn 'ADR-175'` over the plan, spec dir and ADR body returns zero stale
    hits.
17. **AC17 — deferral tracked.** The Phase-7.2 issue exists with its re-evaluation criterion, filed
    with labels verified present.
18. **AC18 — full-suite exit gate.** `bash scripts/test-all.sh` on a clean tree reaches its terminal
    marker with zero `[FAIL]` and zero `[KILLED]`, and fires neither `SIBLING_RUN_DETECTED` nor
    `SIBLING_SUITE_DETECTED`. *(Scoped to the two sibling banners: `LOW_TMP_HEADROOM` is a property
    of the machine, not of this change. Precondition: no sibling run in flight.)*

---

## Test Scenarios

| # | Scenario | Expected |
| --- | --- | --- |
| T1 | Fixture runs `kill -TERM $$` | `[KILLED] … (exit=143, signal-shaped 128+15 = SIGTERM, …)`; failure count unchanged; exit 3 |
| T2 | Fixture runs `exit 1` | `[FAIL] …` byte-identical to today; exit 1 |
| T3 | One `exit 1` + one self-SIGTERM | both markers; exit **1** |
| T4 | `exit 255` | `[FAIL]` — not signal-shaped |
| T5 | `exit 127` (command not found) | `[FAIL]` — a verdict, not a termination |
| T6 | `suite_exit_class 128` | `failed` — `kill -l 0` returns `EXIT`, so the `> 128` guard is what excludes it |
| T6b | `suite_exit_class 160` / `161` | `failed` — `kill -l 32`/`33` succeed with an **empty** name; a blank `SIG` is a claim the runner cannot make |
| T7 | `suite_exit_class 193` | `failed` — above the valid range |
| T7b | `suite_exit_class 192` | `killed` (`RTMAX`) — the inclusive upper bound |
| T8 | Clean run | tail diff-empty vs `origin/main`; no breakdown line; exit 0 |
| T8b | Classifier returns an unrecognized class | `WARNING:` emitted, counted as FAILED, exit 1 — never passed |
| T9 | Sibling `bash tests/scripts/test-foo.sh` in another cwd | `SIBLING_SUITE_DETECTED` fires; `SIBLING_RUN_DETECTED` does not |
| T10 | Sibling `bash scripts/test-all.sh` | `SIBLING_RUN_DETECTED` fires; `SIBLING_SUITE_DETECTED` does **not** |
| T11 | One worktree with a runner **and** its suite child | counted once, run banner only |
| T11b | `env VAR=x bash scripts/test-all.sh` + suite child | counted once, run banner only (ancestry reaches through the wrapper) |
| T11c | `<unreadable>` cwd on both a run and a suite match | no cross-cancellation |
| T12 | `bash -c 'grep -rn x tests/scripts/test-foo.sh'` | neither banner (whitespace-token guard) |
| T13 | No siblings | neither banner |
| T14 | Suite exceeds a 0 ms declared budget | `[budget] …` emitted; status and exit code unchanged |

---

## Risks & Mitigations

**R1 — a real failure is misclassified as unresolved.** A suite legitimately exiting 143 buckets as
`killed`; `$?` cannot distinguish it. *Mitigation:* the window is narrow and every guard measured
(`> 128`, `<= 192`, non-empty name); the exit code is still non-zero so nothing greens (AC7); and
the `[KILLED]` line states the ambiguity in its own text.

**R2 — the new banner fires on solo runs.** The documented failure mode of the original probe.
*Mitigation:* the `test-all.sh` exclusion, the inherited self/ancestor/pgid exclusions, ancestry
cancellation, and an explicit no-sibling negative control (T13).

**R3 — the runner itself is killed.** If the signal reaches the whole process group, `test-all.sh`
dies too and emits no marker. This fix covers only *suite died, runner survived* — which is what the
incident showed (bash's `Terminated "$@"` came from the surviving runner reporting its foreground
child). *Mitigation:* stated in the ADR and in the `work/SKILL.md` third arm; the pre-existing
"absence of the terminal marker" discriminator still covers it.

**R4 — wrapper absorption: the KILLED class is only visible when the process `run_suite` forks is
itself the one that dies.** Generalised after review. Three in-repo wrappers swallow the signal
shape: `apps/web-platform/infra/run-registered-suites.sh` (returns a plain 1);
`.github/scripts/test/run-all.sh`; and — most consequentially — the **webplat** registration
`env … bash -c 'cd apps/web-platform && npm run test:ci …'`, because `npm` does not propagate
`128+N` for a signal-killed child. An OOM kill of the vitest/node process, the single most plausible
instance of the class this plan reports, still surfaces as `[FAIL]`. *(Measured and worth keeping:
`env VAR=x bash -c '…'` **does** propagate — `env` execs rather than forks.)* *Mitigation:* stated
as a limit in the ADR's Consequences; parity is the Phase-7.2 issue, deferred because
`run-registered-suites.sh` is #7376's live target.

**R5 — the `run_suite` edit breaks the existing sandbox suite.** *Mitigation:* AC13 + the Phase-0.3
pre-check + running that suite in Phase 8.

**R6 — wording drifts into the ADR-166 ban list on a later edit.** *Mitigation:* the lint covers
both edited surfaces (AC10), and §2.4 instructs reading the live regex rather than a restated list
that can go stale.

**R7 — the `case`-vs-`declare -A` choice loses its rationale.** *Mitigation:* the reason is recorded
in Phase 5.1 and is **not** bash-3.2 portability (the sourced contention lib already requires 4.4+,
so that premise was wrong); it is initialization order and zero call-site churn.

---

## Alternatives Considered

| # | Alternative | Why rejected |
| --- | --- | --- |
| **A1** | Keep one bucket; only change the `[FAIL]` text for signal-shaped exits | Leaves the failure count wrong, so `N/M suites passed` still misreports and the exit code still says red for a result nobody measured. The count is what readers and monitors act on. |
| **A2** | Exit **1** for killed-only (no new code) | Free, but throws away the machine-readable half of the distinction — the conflation moved from the marker to the exit code. All consumers were measured binary, so exit 3 is safe, and `zot-restart-loop-alarm.sh` is the in-repo precedent for a named multi-code contract. Exit 2 was unavailable: `test-all.sh` already uses it for the `TEST_GROUP` usage error. |
| **A3** | A separate `scripts/lib/suite-exit-class.sh` with its own auto-globbed unit suite | Measured fatal: the sandbox suite copies **one file**, so the lib would be absent under test and the degradation stub would silently defeat every KILLED assertion — the guard would be testing its own fallback. Inlining also deletes the stub, two files, and a whole failure mode. |
| **A4** | A self-killing watchdog aborting at the declared budget (issue item 3's literal "fail with its own diagnostic") | Requires guessing the upstream killer's timing, which this plan explicitly does not know, and trades a possibly-completing measurement for a guaranteed non-result. Adopted instead: declare and report, which delivers item 3's real value (attribution) without self-inflicting the outcome. Recorded as a deviation from the issue's literal wording. |
| **A5** | Widen the existing `SIBLING_RUN_DETECTED` matcher to cover suites | The issue asks for a separate banner and is right: the two answer different questions, and merging them would silently change what an existing `SIBLING_RUN_DETECTED` line means in every log and learning that cites one. |

---

## Sharp Edges

- **`kill -l` is NOT a validity oracle.** Measured 2026-08-10, bash 5.3.9/Linux: `kill -l 0` → `EXIT`
  (rc 0); `kill -l 32` and `kill -l 33` → **rc 0 with empty output** (glibc-internal
  SIGCANCEL/SIGSETXID); `kill -l 143` → `TERM`, i.e. it **masks** values above 64. All three guards
  in `suite_exit_class` are therefore load-bearing. Anyone "simplifying away the redundant `> 128`
  check because `kill -l` already bounds it" breaks the classifier — plan v1 said exactly that and
  it was wrong.
- **`$?` cannot distinguish a signal death from `exit(128+N)`.** `bash -c 'exit 143'` → 143,
  identical to a real SIGTERM. Upgrading the `[KILLED]` line from "signal-shaped" to "was killed by
  SIGTERM" asserts something the runner did not measure — an ADR-166 violation whether or not the
  lint regex happens to catch that phrasing.
- **A `case` over a classifier needs a default arm.** Without `*)`, an unrecognized class increments
  neither counter and the suite silently counts as **passed**. Fail closed: count it FAILED and warn.
- **Never restate the ADR-166 ban list.** Read the live `CLAIM` regex in
  `scripts/lint-diagnosis-claims.sh`. Plan v1's six-item paraphrase omitted five phrases, two verbs,
  three adjectives, and the fact that the adjective group is optional (so bare "is the cause" is
  banned). The highwater is a **ratchet, not a registry**: current value 1, and one new hit is a
  hard CI failure.
- **The sandbox suite copies ONE file.** Anything `scripts/test-all.sh` sources is absent under test.
  That is why the classifier is inline, and it is a trap for any future extraction.
- **Cancel sibling-run children by ancestry, never by cwd.** Suites `cd` into `mktemp` sandboxes,
  `<unreadable>` collapses distinct processes into one pseudo-worktree, and `env`/`timeout` wrappers
  hide a run entirely while its children stay visible. Ancestry is invariant under all three.
- **Do not fold `[KILLED]` into the monitor's existing `grep -E '^RED |^\[FAIL\]'`.** Two things
  break: the run gets labelled "tests failing", and the pinning suite's assertion (8) — whose regex
  ends on the literal `^\[FAIL\]'` — fails. Use a second grep, and remember it must append to
  `SUMMARY` too or the issue names no suite.
- **Exit 3 is a top-level contract only.** A nested runner returning 3 into `run_suite` classifies as
  a plain FAIL (3 is not signal-shaped). Decide that now rather than relitigating it.
- **`=== N/M suites passed ===` is load-bearing across ~30 learnings and 4 skills.** Keep its byte
  shape; gate the breakdown line on `killed > 0`. But note the *reader contract* changes: `N < M` no
  longer implies at least one `[FAIL]`. The direction is safe (a killed run still reds), and the
  affected agent-facing docs are enumerated in §Blast Radius.
- **`test-fix-loop` terminates on parsed output, not the exit code.** Any change to what "zero
  failures" means must reach it, or an autonomous loop reports success on a run that measured
  nothing.
- **The `560931ms` figure is elapsed-at-kill, not a duration.** A lower bound on the suite's clean
  wall-clock; never use it to set a budget.
- **`run-registered-suites.sh` is off-limits in this PR** — the live target of open #7376 / draft
  PR #7423. Read its contract; do not write it. Do not reuse or reset that branch.
