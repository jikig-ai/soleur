---
title: "fix: run-registered-suites.sh is flaky under its default -P — give it diagnostics, fix the collision we can prove, attribute the rest"
issue: 7376
branch: feat-one-shot-7376-suite-runner-parallel-flake
date: 2026-08-10
lane: cross-domain
type: bug
brand_survival_threshold: none
status: draft
---

# fix: `run-registered-suites.sh` parallel flake (#7376)

> No `spec.md` exists for this branch, so it carries no `lane:` — defaulted to `cross-domain`
> (TR2 fail-closed).

## Overview

`apps/web-platform/infra/run-registered-suites.sh` runs **93** registered infra suites
concurrently at `-P min(nproc, 6)` — `-P 4` on the 4-vCPU public-repo GitHub runner. On an
**unchanged tree** the same suite set produces different failure sets. Per PR #7371's body (the
most recent measurement): **8 executions, 4 failed, 6 distinct suites implicated.** Each named
suite passes individually and all 93 pass sequentially.

The work splits into three buckets by **what is actually known**, and the plan keeps them apart:

**Certain — fix now, no measurement required.**

1. **The observability gap.** The executor is `bash "{}" >/dev/null 2>&1`
   (`run-registered-suites.sh:181`) and prints only `PASS <path>` / `RED  <path>`. A CI failure
   carries **no diagnostic output at all** — which is why characterising this took eight
   executions, and why issue #7374's body is 21 `PASS` lines and a count.
2. **A live-tree collision that is provable by reading.** `run-registered-suites.test.sh` **is
   itself a registered suite** (`infra-validation.yml:1057`), so it runs concurrently with the
   other 92. At `:97-103` it creates `zzz-run-registered-suites-fixture.test.sh` **inside the live
   `apps/web-platform/infra/`**, `git add -N`s it, then deletes it. Meanwhile
   `credential-persist-home-guard.test.sh:643,756,988` copies that live directory and `diff -rq`s
   the copy against the **still-live source** — so a file appearing or vanishing mid-window yields
   `Only in …` → RED.
3. **A FALSE GREEN in the runner's own exit logic.** `:185-192` derives the verdict as
   `RED=$(grep -c '^RED' "$LOG")` … `(( RED == 0 ))`. A child whose wrapping `bash -c` is killed
   (OOM under `-P 4` — i.e. exactly hypothesis H2) emits **neither** `PASS` nor `RED`. So `RED=0`,
   **the runner exits 0**, and the summary prints `91 passed, 0 failed (of 93)` — the two numbers
   visibly disagree and **nothing asserts they must match**. A suite can vanish and the gate goes
   green. This is a pre-existing defect independent of this change, it is the failure mode most
   likely to have masked evidence for H2, and the fix is one line:
   `(( PASS + RED == ${#SUITES[@]} ))`, with a diagnostic naming the missing suites.

Items 2 and 3 are bugs on inspection whether or not they caused any of the 8 observed failures;
neither needs permission from a measurement to be fixed.

**Refuted — do not build for it.** The strongest hypothesis research produced (H1, a
`pipefail`/SIGPIPE class documented *in this repo*) was **refuted by measurement inside this
session**. It is written up in full below rather than deleted, because the episode is this plan's
best argument for its own shape: a hypothesis with in-repo documentation, a prior fix in one of
the failing suites, ~450 candidate sites and a flawless narrative fit turned out to be unreachable
by roughly 12× on the one variable nobody had measured. Committing to it would have bought a
mass rewrite, a new linter, a closed issue, and a still-flaky runner.

**Unknown — attribute, then fix.** The remaining hypotheses (H2/H3/H4) need the datum that
`:181` currently destroys. The instrument makes it obtainable; a local repro loop reads it.

**Delivery: one PR by default.** An earlier draft split instrument-then-fix across PRs on
ADR-133's "instrumentation ships ahead of every fix". That rule was formed where the author did
not control the measuring environment; here we do — the evidence source is a **local**
`taskset -c 0-3` loop, which needs the instrument in the *working tree*, not on `main`. Splitting
would also park an instrument on `main` that observes nothing, because CI is pinned `JOBS: 1`.
See **Delivery & Split Trigger** for the one condition that reverses this.

## Premise Validation

| Cited premise | Probe | Result |
|---|---|---|
| Issue #7376 open, unresolved | `gh issue view 7376 --json state,closedByPullRequestsReferences` | **Holds** — `OPEN`, no closing PR |
| #7307 monitor hardening merged (so the flake now files P1s) | `gh issue view 7307` | **Holds** — `CLOSED`; shipped as PR #7371 |
| #7374 is an instance | `gh issue view 7374` | **Holds** — body is 21 `PASS` lines + a count, no suite named. Exactly what the observability gap produces |
| "92 registered suites" | `run-registered-suites.sh --list` | **STALE** — **93** today. Never hardcode; `main-health-monitor.yml:408-409` also still says 92 |
| "6 executions, 2 failed, 3 suites" (issue body) | PR #7371 body | **STALE** — superseded by **8 / 4 / 6**. `main-health-monitor.yml:290` carries a third, intermediate figure (7/3/4). Phase 0 re-derives |
| `JOBS=1` is the current stopgap | `grep -n 'JOBS: 1' main-health-monitor.yml` | **Holds** — at **both** `:304` (tests step, which nests the runner) and `:323` (infra step) |
| ADR-133 already decided this class | Read ADR-133 | **Holds, but does NOT transfer** — see R3 |

No premise was fabricated; two were stale and are corrected above.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| R1. "The runner's `\| tee` masks the suite exit code; it needs `set -o pipefail`" (asserted by the learnings-research pass) | **False.** `:91` already sets `set -uo pipefail`, and the exit status is derived at `:185-192` by **counting `^RED` lines in `$LOG`**, not from the pipeline | **Do not "fix" this.** Recorded so it is not re-litigated at review — the general "`\|tee` masks exit codes" pattern makes this a tempting non-defect. The real `\|tee` defect belonged to `main-health-monitor.yml` and #7371 already fixed it |
| R2. "Suites copy a 162 MB `.terraform` tree per mutation" | **Already mitigated** — `credential-persist-home-guard.test.sh:138,143,152`. And **no `.terraform` exists in a fresh checkout**; CI's `deploy-script-tests` runs no `terraform init` | Weakens H2. But `zot-image-staleness-mutation.test.sh:25,63` copies the whole tree **19×** via `cp -a "$SRC/."` with **no** exclusion — carried as an H2 sub-probe |
| R3. ADR-133 measured this class and found "capacity, not a colliding path" | **Different machine, different mount.** ADR-133 measured a 4 GiB **RAM-backed `/tmp`** at 86% full, swap exhausted, on the operator workstation, for **cross-worktree** overlap. This is a 4-vCPU **hosted runner** on disk-backed `/var/tmp`, single run | ADR-133's verdict is a **prior, not evidence**. Its *method* transfers; its conclusion does not |
| R4. `test-all.sh` is a parallel peer needing a shared width primitive | **Refuted.** `test-all.sh` has no `xargs -P` and no `&` fan-out — it is sequential. Its only parallelism is the nested call to *this* runner | No shared primitive (one consumer). See Architecture Decision |
| R5. The three named suites are the heavy ones | **Refuted by measurement (this session).** `inngest` **2 s / 16.6 KB / rc=0**; `soleur-host-bootstrap-observability` **2 s / 9.1 KB / rc=0**; `web-host-provisioner-parity-mutation` **89 s / 7.1 KB / rc=0** | The first two are among the *cheapest* suites. Reshapes H2 from "the failing suite is heavy" to "the failing suite was a **victim** of heavy neighbours" |
| R6. `soleur-host-bootstrap-observability` collides on shared state | **Near-refuted.** Zero `mktemp`, zero `$TMPDIR`, zero temp files, zero docker, zero terraform, zero network, zero ports, zero writes. It only *reads* six tracked files | Its possibility space is tiny, which makes it the sharpest probe in the set |

## Research Insights (deepen pass, 2026-08-10)

### Institutional learnings that apply

| Learning | Applied as |
|---|---|
| `2026-08-10-pipe-buf-atomicity-does-not-apply-to-the-file-i-was-redirecting-into.md` — **same repo, same day.** `generate-kb-index.sh` used `xargs -P4 … > "$file"` under a comment asserting PIPE_BUF safety; four children shared one file description, tore lines mid-flush, and fabricated ~14 values into a committed artifact a validation gate then enforced | Phase 1 item 3's **two-clause** invariant, and a Sharp Edge. Our children are safe **only** because their stdout is `\| tee "$LOG"`. This plan adds per-suite file writes to that same runner — the highest-risk refactor available to the implementer |
| `2026-07-26-a-green-test-run-is-only-evidence-for-what-it-actually-ran.md` (#6730) — *"nearly every defect was a property **asserted** rather than **measured**"*, in a PR whose own comments said "MEASURED, not assumed" | The whole plan's shape. Every hypothesis carries a confirmation criterion; H1 was refuted by measurement rather than argument; AC11 requires a baseline denominator rather than asserting a fix |
| ADR-133 (`test-all.sh` tmpfs contention) — *"Instrumentation ships ahead of every fix"*, and two recorded colliding-path hypotheses **both refuted by measurement** | The probe-first ordering, and R3's insistence that ADR-133's *conclusion* is a prior rather than evidence for a different machine and mount |
| `test-failures/2026-06-10-parallel-load-flake-two-mechanisms-and-vacuous-absence-waits.md` — one flake symptom, two unrelated mechanisms; falsify each against the error shape | Phase 4's arm-selection rules: more than one arm may fire; a reproduced failure matching no arm is a new hypothesis, not a forced fit |

### Verified this pass

- **Sentinel `| ` is collision-free.** No registered suite emits a line beginning with `| ` — zero
  `echo`/`printf` sites construct one, and empirical runs of `inngest` and
  `soleur-host-bootstrap-observability` produced 0 such lines. The sentinel can therefore be
  stripped from the monitor's tail without eliding genuine suite output.
- **The runner's summary path is a pipe** (`xargs … | tee "$LOG"`, `:180-183`), so the PIPE_BUF
  argument is sound *as currently written* — and only as currently written.
- **No in-repo precedent exists** for per-suite log capture in a parallel bash runner. The closest
  sibling, `scripts/generate-kb-index.sh`, is the cautionary case above rather than a pattern to
  copy. Phase 1 is therefore novel-by-necessity: state that in the header and pin it with tests.

## Hypotheses

The discriminating datum — which assertion inside the failing suite went red — is discarded by
`:181` and is unobtainable from the repo. **H2/H3/H4 are therefore `UNKNOWN`**; a verdict for them
written now would be reasoning presented as measurement.

**H1 is the exception, and only because it was refuted on a variable that does not need the
missing datum** — pipe capacity is a property of the call sites, measurable from the repo, and it
rules the mechanism out regardless of what the failing suites were doing. Refutation from
available evidence is legitimate; *confirmation* still requires the instrument.

Each hypothesis carries an explicit **confirmation criterion**, so Phase 2 has a stopping rule.

### H1 — `pipefail` + `producer | grep -q` → SIGPIPE(141) makes a MATCHING test read FALSE

**Status: REFUTED by measurement. The mechanism is real and reproducible; no site in the
registered set can reach it.**

Under `set -o pipefail`, `grep -q` exits at its **first match** and closes the pipe; a
still-writing producer takes **SIGPIPE (141)**, and pipefail propagates 141 — so the `if` reads
**FALSE though the pattern matched**. The repo documents this in **two** places already
(`soleur-host-bootstrap-observability.test.sh:88-91` (#7024) — *"Intermittent by nature — it needs
the producer to still be writing"* — and `doppler-download-error-channel.test.sh:508-511`), and
fixed two sites in one of the three named failing suites via capture-then-herestring.

**Mechanism reproduced this session, with controls:**

```console
$ bash -c 'set -o pipefail; seq 1 1000000 | grep -q "^1$"; echo "rc=$? PIPESTATUS=${PIPESTATUS[*]}"'
rc=141 PIPESTATUS=141 0          # grep MATCHED (0); producer SIGPIPE'd (141); pipefail propagated
$ bash -c 'set -o pipefail; _c="$(seq 1 1000000)"; grep -q "^1$" <<<"$_c"; echo "rc=$?"'
rc=0                             # capture-then-herestring: the blessed fix
$ bash -c 'set -o pipefail; seq 1 5 | grep -q "^1$"; echo "rc=$?"'
rc=0                             # negative control
```

**But the threshold is the pipe capacity, and it is deterministic on both sides.** Sweeping
producer size (match always on line 1, 5 trials each):

| producer bytes | rc (×5) |
|---|---|
| 292 / 1,892 / 3,893 / 8,893 / **23,893** | `0 0 0 0 0` |
| **108,894** / 588,895 | `141 141 141 141 141` |

The boundary is the **64 KiB default pipe capacity** (`/proc/sys/fs/pipe-max-size` reports 1 MiB
as the *ceiling*; the default is 65536). Hence:

> **If a producer's TOTAL output is ≤ 64 KiB it writes everything into the pipe buffer without
> ever blocking and exits 0 — regardless of consumer timing or CPU load. Such a site is immune by
> construction.**

**Measured against the actual suspect sites — every one is far under:**

| Site | Producer output | Verdict |
|---|---|---|
| `…observability.test.sh:783` — `awk '/cat > …/,/^VINEOF$/' "$BOOT"` | **5,170 B** | immune |
| `…observability.test.sh:792-794` — `awk '/cat > "$UNIT" <</,/^UNITEOF$/' "$BOOT"` | **841 B** | immune |
| `web-host-provisioner-parity-mutation.test.sh:229,806` — `grep -F "[FAIL]" "$OUT"` | guard total **1,266 B**; **0** `[FAIL]` lines on green | immune |
| worst case: whole-file producers over `$BOOT` / `$CI` | **57,303 B** / **51,028 B** — both **under** 64 KiB | immune |

**And no site anywhere clears the bar.** Files above 64 KiB exist (`ci-deploy.sh` 212 KB,
`workspaces-cutover.sh` 176 KB, `server.tf` 114 KB), but scanning all ~450 `| grep -q` sites
(459 occurrences across 52 files by one regex, 426/53 by another — the exact count is not
load-bearing) for a producer that streams one of them returns **0 matches**; only one site pipes
an unbounded-ish producer at all (`cron-egress-firewall.test.sh:472`, an `echo` of a small var).

An earlier risk model classified sites by *shape* — "does the producer keep streaming after the
match?" — and rated the `awk` ranges HIGH. **That model was wrong.** Shape is not the operative
variable; total output versus 64 KiB is. The shape heuristic is recorded because it is the
intuitive-but-incorrect one a reviewer will reach for.

**Re-opening condition (not a Phase 2 task):** a captured failure whose assertion pattern **is**
present in the file it inspects, whose pipeline records `PIPESTATUS[0] == 141`, **and** whose
producer emits > 64 KiB. Absent all three, spend no Phase 2 time here.

**Why it stays in the plan:** it explained every observation and predicted nothing measurable —
precisely the shape this repo's discipline exists to catch. Deleting it invites its rediscovery.

### H2 — Global capacity exhaustion (OOM / disk / fd) under `-P 4`

**Status: UNKNOWN.** Weakened by R2 and R5 (two of three named suites are 2 s and < 30 MB RSS).
Not refuted — the failing suite may be a victim, not the consumer. Pressure sources:
`zot-image-staleness-mutation` (19 unguarded whole-tree copies) and `git-data-runcmd-rehearsal`
(6 × `docker run` + `apt-get`, 4 × `truncate -s 10G` sparse images).

**Confirmation criterion:** a captured suite exits **137** (SIGKILL/OOM) or **124** (timeout), or
its log carries `No space left on device`. **Refuted only across ≥ 1 reproduced failure** — i.e.
every captured *failure* exits 1 with an ordinary assertion message. On an all-green loop both
halves of that test hold trivially, so a zero-failure run licenses **no verdict at all**, only
`UNKNOWN` plus the Split Trigger.

### H3 — Shared-state collision on a fixed path or name

**Status: PARTIALLY ESTABLISHED — one instance is provable by reading and is fixed in this PR
regardless of attribution (Overview, bucket 1). The rest is UNKNOWN.**

| Candidate | Site | Status |
|---|---|---|
| **A registered suite mutates the live tree and `.git/index` that other suites read** | `run-registered-suites.test.sh:97-103` (registered at `infra-validation.yml:1057`) vs `credential-persist-home-guard.test.sh:643,756,988`, which copies the live dir then `diff -rq`s against the still-live source. Also `inngest.test.sh:451,457,1097` walk the live dir | **Provable by reading — fix now** |
| Hardcoded `/tmp/rung2`, ignoring `$TMPDIR` | `git-data-rung2-rehearsal.test.sh:763,956`; its own `:693` comment says these arms **"CANNOT RUN CONCURRENTLY"** | UNKNOWN — only the (non-concurrent) workflow shares the path today, but it proves the isolation assumption is not universal |
| `mktemp` pinned to `/tmp`, bypassing the runner's `TMPDIR=/var/tmp` | `canary-bundle-claim-check.test.sh:154,189,338,363`; `cloud-init-inngest-bootstrap.test.sh:105` | UNKNOWN — lands on the shared tmpfs the runner steers away from |
| `mktemp -u` (TOCTOU) | `verify-tunnel-ingress-origin-infradir.test.sh:40` | UNKNOWN |

**Cleared by the audit:** docker names are already `$$`-scoped
(`cloud-init-plugin-seed.test.sh:37-38`); **no** `TF_PLUGIN_CACHE_DIR` anywhere; every real port
bind is ephemeral (`bind(…,0)`); `:8099` is container-internal; no `sudo`, `killall`, `/etc`
writes, or `git stash/checkout/worktree` in the registered set.

**Confirmation criterion:** a captured failure whose text is a path/`Only in …`/missing-file error
rather than a content assertion, naming a resource in the table above.

**Note the sweep does NOT cover its own top candidate.** The `TMPDIR`-ignoring-write sweep finds
rows 2-4; row 1 (the live-tree + `.git/index` mutation) uses no `TMPDIR` at all, so a clean sweep
**does not refute H3**. Row 1 is being fixed on inspection precisely because no sweep would have
caught it.

### H4 — CPU starvation trips an in-suite polling deadline

**Status: UNKNOWN.** Refuted for the three *named* suites — none has a `sleep`, `timeout` or
polling loop, and `inngest.test.sh`'s wall-clock arithmetic is one-sided (delay only helps). Live
candidates among the other 90: `canary-bundle-claim-check.test.sh:95-103` (**4 s** hard FATAL
readiness poll), `git-data-emit.test.sh:83` (5 s), `web-git-data-probe.test.sh:77-95` (10 s poll
**and a 40 s self-terminating listener**), `web-zot-consumer-probe.test.sh:111-116`.

**Confirmation criterion:** a captured failure naming a readiness/bind timeout, **and** the
suite's recorded elapsed time far exceeding its solo baseline.

**That baseline does not exist yet for 90 of the 93 suites** (R5 measured three). Phase 3 must
therefore run **one sequential `JOBS=1` pass** first and keep its per-suite elapsed times as the
baseline table — otherwise "far exceeding its solo baseline" is unusable and H4 cannot be decided
either way. The instrument's elapsed field makes this pass nearly free.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — CI-only tooling with no runtime
path into the product. The realistic harm is to the **operator**: a regression either re-arms
spurious P1 `ci/main-broken` issues at ~1-in-3 (retraining the operator to ignore the one alarm
watching `main`), or makes the infra gate noisier so it stops being run at all — the exact failure
`run-registered-suites.sh` was built to end (#6730).

**If this leaks, the user's data is exposed via:** the new diagnostic output is the only new
exposure surface, and it is real. `main-health-monitor.yml` captures the runner's stdout and posts
an excerpt into a **public** GitHub issue behind a fixed-prefix `sed` redaction pass (`:473-481`).
Mitigated architecturally (Risk 2): line-prefixing keeps the published excerpt **byte-identical**
to today's, so no new distribution surface is created.

**Brand-survival threshold:** `none`.
*Scope-out (required because the diff touches `apps/web-platform/infra/`):*
`threshold: none, reason: the change is confined to a CI/local test harness and its suites; it
reads no user data, has no runtime path into the product, and creates no store or connection.`

## Delivery & Split Trigger

**Default: one PR** — instrument + the provable collision fix + evidence + whatever the evidence
names. The evidence source is a local `taskset -c 0-3` loop, which needs the instrument in the
working tree, not on `main`.

**Split trigger (the only one):** if the local loop fails to reproduce a failure in ≥ 20
iterations, **stop and split**. Ship the instrument + the provable collision fix alone, then
harvest real CI failures over subsequent runs before choosing any further arm. A local 4-core pin
does not reproduce shared-runner IO contention or cgroup throttling, so a non-reproduction
locally **establishes nothing** and must not be written up as a refutation of anything.

## Implementation Phases

### Phase 0 — Preconditions (no code)

1. Re-derive the failure corpus from CI (`gh run list --workflow=main-health-monitor.yml`;
   `gh run view <id> --json jobs`) and **name all 6 implicated suites**. Record in the PR body.
2. Take the derived suite count from `--list` (93 today) — never hardcode it.
3. Confirm the local toolchain matches CI's (`terraform`, `docker`, `python3`, `jq`, `cloud-init`
   — all verified present this session).
4. Confirm `taskset -c 0-3 nproc` returns `4` (verified), so the runner computes `JOBS=4` — a
   faithful 4-core-equivalent repro.

### Phase 1 — The instrument

Edit `apps/web-platform/infra/run-registered-suites.sh`.

1. **Per-suite capture.** Allocate a per-run log dir (`mktemp -d`); each `xargs` child redirects
   its suite's stdout+stderr to its own file. Key the filename on the **sanitised full path**, not
   `basename` — unique across the 93 today, but nothing asserts it stays so.
2. **Exit code and elapsed time**, recorded per suite. `rc` is `$?` in the subshell that already
   redirects — zero extra machinery. For elapsed, reuse `test-all.sh:38-41,153`'s `EPOCHREALTIME`
   idiom **including its bash-3 fallback guard**; seconds precision is sufficient (the H4
   discriminator compares against solo baselines of 2 s vs 89 s), so degrade to seconds rather
   than adding a `date +%s%N` dependency.
3. **Summary lines unchanged.** The child still emits `PASS <path>` / `RED  <path>` **first** and
   in the same byte shape. The invariant has **two** clauses and both are load-bearing:
   *(i) the summary line stays under `PIPE_BUF` (4096)*, and *(ii) **the children's stdout remains
   a PIPE***. Today's shape satisfies (ii) — `xargs … | tee "$LOG"` — and that is the only reason
   the atomicity holds. **PIPE_BUF atomicity is a property of pipes and does not apply to regular
   files at all.** If the implementer "tidies" the pipeline into `xargs … > "$LOG"` while adding
   file capture — a natural-looking refactor once you are already writing files — every child
   inherits the same open file description, block-buffered flushes land mid-line, and the
   `PASS`/`RED` lines tear. See Sharp Edges and
   `knowledge-base/project/learnings/2026-08-10-pipe-buf-atomicity-does-not-apply-to-the-file-i-was-redirecting-into.md`,
   which is that exact defect, in this repo, committed the same day as this plan.
4. **Dump from the parent, single-threaded, strictly after `xargs` returns, and strictly BEFORE
   the final summary block.** Never from inside a child — multi-line concurrent writes are not
   atomic. Per RED suite: a banner with `rc` and elapsed, then the excerpt.
5. **Select the excerpt by ANCHORING ON THE SUITE'S OWN FAILURE MARKER — never a blind tail.**
   These suites do not stop at the first failed assertion: `web-host-provisioner-parity-mutation`
   runs 43 `expect_red` arms plus 7 probes, so a failure at arm 5 is hundreds of lines from EOF and
   a `tail -40` would show only trailing passes — destroying the exact datum Phase 3 needs, *on a
   successful reproduction*.

   **The marker set MUST be derived from the corpus, not intuited.** A first draft of this plan
   used `^\[FAIL\]`, `^  FAIL`, `^no ` and was **measured wrong**: only **10 of 93** suites print
   `[FAIL]`, **78** print a bare `FAIL:` / `FAIL -` at column 0, and **`^no ` matches nothing at
   all** — it was derived from the `no()` *helper's name*, never from its output (its body is
   `echo "[FAIL] $1" >&2`). That draft would have silently degraded ~85% of the corpus to the
   blind tail it was written to prevent, including `git-data-emit` and `git-data-runcmd-rehearsal`
   — the plan's own H2/H4 candidates.

   Measured coverage: `^\[FAIL\]` → 10/93; `^(\[FAIL\]|FAIL[ :-])` → 42/93;
   **`^[[:space:]]*(\[FAIL\]|FAIL\b)` → 85/93**. Use the last, re-derive it at implementation
   time, and add the conformance test in item 12. Take matched lines **plus trailing context**
   plus the last few lines, capped at a **named constant** (40) — the cap must bind *after*
   selection, or one suite with 10,000 `[FAIL]` lines dumps all of them.
   If nothing matches, fall back to the tail **and say which selection was used**.
6. **Capture stdout AND stderr, in the right order.** 101 emit sites across the suites write their
   failure marker to **stderr** (`no() { … >&2; }`). The redirection must be `>"$f" 2>&1`, never
   `2>&1 >"$f"` — the inverted form sends stderr to the *old* stdout and loses every marker, and
   the item-5 selector would then find nothing on most of the corpus while looking healthy.
7. **Prefix EVERY line the parent emits after `xargs` returns** — the dump, **the `rc`/elapsed
   banner, and the retained-log-dir path**. Not just "dumped lines": an unprefixed banner reaches
   the monitor's `tail -30` and lands in the public issue body, and AC4's negative check cannot
   see it. Use an unconditional prefixer (`sed 's/^/| /'`, not `sed 's/^\(.\)/| \1/'`, which
   leaves blank lines bare and therefore unfiltered).
8. **Teach the monitor's tail to skip the sentinel — and scope it.** `main-health-monitor.yml`'s
   `SUMMARY="${SUMMARY}$(tail -30 "$file")"` sits **OUTSIDE** its `if [[ -n "$hits" ]]` block
   (`:436`), so it runs on every non-success step; prefixing alone does **not** keep dumped bytes
   out of the issue body. Three constraints on the fix, all verified:
   - **It trips an existing gate.** `plugins/soleur/test/main-health-monitor-workflow.test.sh`
     check (10) (`:246-255`) flags any line matching `\|\s*(tail|head)\b` that lacks `PIPESTATUS`
     and lacks the literal `grep -E`. `grep -v '^| ' … | tail -30` matches all three conditions →
     **the test reds**, and AC6 requires it to pass. Amend check (10) deliberately, with a comment
     saying why the producer's status is irrelevant for a display filter. Do **not** spell it
     `grep -E -v` to slip past the substring exemption.
   - **The sentinel collides on the *tests* half.** The loop covers **both** `/tmp/tests-output.txt`
     and `/tmp/infra-output.txt`. `scripts/expenses-verify-by-check.test.sh:49,50,53` emits
     markdown tables at column 0 (`| Service | Provider | …`), which a blanket `grep -v '^| '`
     would strip from the tests-step excerpt — deleting an existing signal. **Scope the filter to
     the infra capture only**, or choose a sentinel no shell output produces (`SOLEUR| `, or a
     leading `\x1f`). Zero of the 93 infra suites emit `^| ` (verified), but that invariant is
     unenforced — pin it in the conformance test (item 12).
   - **It is errexit-safe only because pipefail is off** in that step (`main-health-monitor.yml:24`
     documents "errexit ON, pipefail OFF"). Add a comment at the new line, because adding
     `shell: bash` later would make a fully-filtered file abort the filer and file nothing.
9. **Assert the accounting.** Add `(( PASS + RED == ${#SUITES[@]} ))`, failing loudly and naming
   the missing suites. Closes the pre-existing false green (Overview item 3).
10. **Elapsed time — no silent-zero fallback.** Use `EPOCHREALTIME`, seconds precision. **Do NOT
    import `test-all.sh`'s bash-3 guard**: the runner already uses `mapfile` (`:121`, `:152`), so
    bash 3.2 dies at derivation and the branch is unreachable dead code — and its behaviour is to
    resolve elapsed to **0 silently**, which would put a silent-wrong-value in the field whose only
    job is H4's "far exceeding the solo baseline". Fail loud or omit the branch.
11. **Record a per-suite START OFFSET, not just elapsed.** R5 reshaped H2 into "the failing suite
    was a *victim* of heavy neighbours" — and `rc` + `elapsed` cannot name the neighbours. Without a
    start offset there is no way to reconstruct which of the 93 overlapped the victim's failure
    window, so H2-as-victim is **not falsifiable** and Phase 4's H2 arm would be selected from the
    a-priori docker/terraform list rather than from evidence. That is the exact error the H1
    write-up exists to prevent. The code already captures a start value to compute elapsed; this is
    one extra printed field, not a new probe.
12. **Corpus-conformance test (the highest-value test in this plan).** Iterate `--list`; for each
    suite extract its failure-emit literal and assert it matches the runner's marker ERE; assert
    no suite emits a line matching the chosen sentinel at column 0. Fail loudly **naming the
    suite**. This converts a silent 85%-degradation into a red test the day a 94th suite lands
    with a new marker shape. It needs no suite execution — `--list` plus one grep per suite.
13. **Log lifetime.** Retain the dir on non-zero exit and print its path; reap on success.
   Initialise the variable **before** the `trap` references it, and use `${LOGDIR:-}` inside it
   (`set -u` is active at `:91`). Note in the header that retention serves the **local** repro
   only — a hosted runner is destroyed with its filesystem, so nothing should later try to surface
   this path in CI.
14. **Add an `INFRA_DIR` seam** beside the existing `INFRA_WF` one. The derivation regex hardcodes
   the `apps/web-platform/infra/` prefix, so today a fixture suite can only be registered by
   **physically creating an executable file in the live infra directory** — the very defect Phase 2
   removes. Parameterising the prefix lets Phase 5's fixtures live under a `mktemp -d`. Without
   this seam, the test suite reintroduces the collision it is testing the fix for.
15. **Add a `SUT="${SUT:-apps/web-platform/infra/run-registered-suites.sh}"` seam** in the test
    (it is hardcoded at `run-registered-suites.test.sh:13`). AC1 requires the new assertions to
    fail against the **pre-change** runner, and with `hr-never-git-stash-in-worktrees` in force
    there is otherwise no way to point the test at the old binary.
16. **Prose sweep — anchored on the real strings, which are NOT `>/dev/null 2>&1`.** Verified
    locations: `run-registered-suites.sh:42-43` (*"the executor below runs each suite as `bash
    "{}" >/dev/null 2>&1` and prints `PASS`"*); `main-health-monitor.yml:408-409` (*"discards each
    suite's own output"*, wrapped across two lines, plus *"with 92 suites"*); and
    `main-health-monitor.yml:136` (*"SAME 92 suites"*). Note the monitor contains **zero**
    occurrences of the literal `dev/null 2>&1`, so any sweep grepping for that token cannot see
    the monitor half at all. This is the self-denying-registration defect the header records for
    #7103.

**Deliberately NOT in Phase 1:** a capacity preamble (`/tmp` + `$TMPDIR` headroom, load, docker
daemon state) and a cgroup `oom_kill` counter. A reading at t=0 cannot describe the peak of 4
concurrent suites — the same argument this plan uses to reject width-derivation — and the disk-exhaustion
signature (`No space left on device`) lands in the captured log for free. The `oom_kill` counter is
redundant with `rc=137` except where the OOM killer takes a *child*, and on a hosted runner the
cgroup v1/v2 path may silently read nothing: a blind reading indistinguishable from a healthy one,
which is the precise trap this plan flags elsewhere. If H2 survives Phase 2, add it there as one
line.

### Phase 2 — Fix the provable collision (no measurement gate)

Independent of every hypothesis. **Order matters — 2.2 is the load-bearing half.**

**2.2 (do this first): make `credential-persist-home-guard.test.sh` diff against a frozen
snapshot** rather than the still-live source (`:643,756,988`). This alone closes the race for
*every* concurrent tree-mutator, present and future, and is unconditionally correct.

**2.1 (constrained — read before attempting): relocating T5's fixture may be infeasible as
stated.** `report_orphans()` enumerates candidates with
`git ls-files 'apps/web-platform/infra/**/*.test.sh'` (`:155`) and cross-references them with
`git grep … -- .github/workflows/ scripts/`. **Both are index/repo-bound, so a `mktemp -d` fixture
is invisible to the function under test** — T5 would assert nothing. The `INFRA_DIR` seam
(Phase 1 item 14) fixes the *derivation* prefix but not this, because the orphan scan's input is
`git ls-files`, not a directory walk. So one of:

- **(a) Extend the seam to the orphan scan's file-list source** (inject the candidate list, so T5
  can drive it from a fixture root). Cleanest, slightly larger.
- **(b) Keep the live-tree fixture but make it collision-safe** — `$$`-scoped filename so two
  concurrent runs cannot fight, accepting that the file still transiently appears in the tree.
  Safe *once 2.2 lands*, because no suite then diffs the live tree.
- **(c) Do nothing to T5.** Legitimate if 2.2 lands: the mutation is only harmful to a suite that
  reads the live tree mid-run.

Note the `.git/index` mutation (`git add -N` / `git rm --cached`) is **not** itself the hazard —
git writes the index via `index.lock` + atomic rename, so concurrent readers see either the old or
the new index, never a torn one. **The hazard is the file's transient appearance in the working
tree**, which is what 2.2 neutralises. Do not spend effort hardening the index path.

### Phase 3 — Measure and attribute

1. **Baseline pass:** one sequential `JOBS=1` run, keeping per-suite elapsed times (H4's missing
   denominator) and confirming a green sequential set.
2. **Pre-fix parallel baseline:** `taskset -c 0-3 bash …/run-registered-suites.sh`, n ≥ 20, on the
   tree **before** the Phase 2 collision fix. This is AC11's denominator; without it the post-fix
   loop proves nothing.
3. Repeat post-fix, n ≥ 20.
4. Read **exit codes first** — 137/124 settles H2 and H4 before any log is opened.
5. For each captured failure, apply that hypothesis's **confirmation criterion** verbatim.
   **Do not use "the suite passes when re-run standalone" as a discriminator** — the Overview
   records that *every* named suite already passes standalone, so all four hypotheses predict it
   and it separates nothing. It is a precondition of the bug, not evidence about its cause.
6. Run the `TMPDIR`-ignoring-write sweep across all 93 suites (H3 rows 2-4 only; see H3's note).
7. **Attribute every distinct failing suite** and record verdict + evidence per hypothesis.
   Honour the Split Trigger if nothing reproduces.

### Phase 4 — Fix every class the evidence confirms

Not "pick an arm" — the 6-suite spread is consistent with **more than one** class, and a
single-arm framing risks shipping the H3 fix while an H2 race keeps firing at low rate.

- **If H3 (remaining candidates):** per-run-scope the named resource (`/tmp/rung2`,
  `/tmp`-pinned `mktemp`, `mktemp -u`).
- **If H2:** serialise the heavy class — the 2 docker + 5 terraform suites at width 1, the rest at
  4. **Do not derive width from measured capacity**: a harness whose width varies with its
  environment makes its own flake irreproducible, and a `-P 1` fallback would silently blow the
  monitor's derived `timeout-minutes` and file a self-inflicted P1.
- **If H4:** raise the specific suite's readiness deadline, or class-serialise it.
- **If H1 re-opens** (all three re-opening conditions met): rewrite the offending sites to
  capture-then-herestring. A linter for this class is **out of scope — file as a follow-up issue**:
  the mechanism cannot currently fire, and a new rule would need either a mass rewrite of ~450
  sites or a baseline file (this repo's convention — `scripts/lint-shell-capture-exit.baseline.txt`,
  `scripts/lint-trap-tempfile-ownership.highwater`), neither justified by a defect that is
  presently unreachable.

**Arm-selection rules (the branches a four-`if` list silently omits):**

- **More than one arm may fire.** H3 itself predicts multiple mechanisms across a 6-suite spread.
  Ship every class the evidence confirms; do not stop at the first. If two arms are both large,
  split them across PRs and say which AC gates which.
- **No arm matches.** A reproduced failure with `rc=1`, an ordinary assertion message, no path
  error and normal wall time maps to **none** of H1-H4. That is a **new hypothesis**, not an
  unlucky reading: record it, name its discriminator, and re-enter Phase 3 rather than forcing it
  into the nearest arm.
- **The failing set differs from Phase 0's six.** Expected, not anomalous — attribute what
  reproduces and note the delta; do not discard a reproduction for being off-list.

**The PR body must state explicitly what was and was not established**, including every hypothesis
still UNKNOWN.

### Phase 5 — Tests and record

Extend `apps/web-platform/infra/run-registered-suites.test.sh` using its existing `INFRA_WF`
fixture seam (~2 s, no 25-minute run) — see Test Scenarios. Amend **ADR-133** with the single
clause that is durable (see Architecture Decision). Any new suite file must be registered in
`infra-validation.yml` or `.github/scripts/test/test-infra-suite-registration.sh` fails a required
check.

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/run-registered-suites.sh` | Phase 1 instrument; `INFRA_DIR` seam; prose sweep at `:42-43` |
| `apps/web-platform/infra/run-registered-suites.test.sh` | `SUT` seam (`:13`); move the orphan fixture out of the live tree (`:97-103`); Phase 5 assertions |
| `apps/web-platform/infra/credential-persist-home-guard.test.sh` | Snapshot-diff instead of diffing against the live source (`:643,756,988`) |
| `.github/workflows/main-health-monitor.yml` | **Behaviour change** — filter the sentinel out of the unconditional `tail -30` at `:436`. Plus prose sweep at `:408-409` and `:136` (the "discards each suite's own output" claim and two stale "92 suites"). **Leave `JOBS: 1` at `:304`/`:323` alone** |
| `plugins/soleur/test/main-health-monitor-workflow.test.sh` | Pin the tail-filter invariant (AC4) beside existing check (8); **amend check (10)** with a rationale comment (AC4b) — the new filter matches its offender pattern; leave check (12) intact |
| `apps/web-platform/infra/workspaces-luks-header.test.sh` | Blank `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` in the `run_s7` subshell (`:384`) so the FAIL path cannot print an ambient key |
| `knowledge-base/engineering/architecture/decisions/ADR-133-*.md` | One-clause amendment |
| *Phase-4-conditional:* `git-data-rung2-rehearsal.test.sh:763,956`; `canary-bundle-claim-check.test.sh:154,189,338,363`; `cloud-init-inngest-bootstrap.test.sh:105`; `verify-tunnel-ingress-origin-infradir.test.sh:40` | Selected by Phase 3 |

## Files to Create

None. (A `| grep -q` linter is deliberately deferred to a follow-up issue — Phase 4.)

## Acceptance Criteria

### Pre-merge (PR)

1. **Mutation matrix, not a pre-change copy.** `SUT=<pre-change-copy>` is **vacuous by
   construction**: T1-T4 all require the new `INFRA_DIR` seam, which the old runner lacks, so it
   either derives ZERO and exits 2 (`:128-132`) — satisfying every "no dump appeared" assertion
   trivially, red for the wrong reason — or runs the live 93 suites for 25 minutes. Instead mutate
   a copy of the **current** runner and assert each mutant is killed, inside the suite so it runs
   in CI forever: anchored-selection→`tail`, drop the prefix, skip the dump, invert
   retain/reap, drop the cap, invert the capture order to `2>&1 >"$f"`, delete the
   `PASS+RED==count` assertion. Each names the AC it must kill. Add a fail-closed guard: if `SUT`
   is set and not executable, `exit 2` (else a typo silently tests the default).
2. A RED suite's own output appears in runner stdout, **≤ the named cap constant** (drop the `~`;
   put the number in the runner and assert against it), with `rc`, `elapsed` and `start offset` —
   and the excerpt **contains the failing assertion line**. Asserted on ONE fixture run that
   combines all three traps: fails **early**, emits its marker **on stderr** at **column 0**, then
   emits ≥ 100 passing lines. AC2 and AC3 must share that single run — split across two fixtures
   the conjunction does not hold.
3. **Excerpt invariant:** over the full output of a run with ≥ 1 RED suite,
   `grep -cE '^(RED |\[FAIL\])'` equals the number of genuine `RED` lines. **Use exactly this ERE**
   — `'^(RED \|\[FAIL\])'` is a different, always-zero regex (`\|` is a *literal pipe* in ERE), and
   would pass vacuously. Verified against a fixture emitting `[FAIL]` at column 0 (10 registered
   suites do). The expected count must be a **literal from the fixture** (1 RED suite → expect 1),
   never recomputed by grepping the same output — that is `x == x`. AC3 detects only *excess*
   matches; a runner that dumps nothing passes it, which is why it must share AC2's run.
4. **Published-surface invariant — a WHITELIST, not an absence check.** "`$SUMMARY` contains no
   `^| ` line" is satisfied by a filter that drops everything, and is blind to the plan's own
   unprefixed output. Assert instead that `$SUMMARY` is **byte-identical to the pre-change
   `$SUMMARY`** for the same outcome set, and **positively** that it still contains
   `=== registered infra suites: N passed, M failed` — the property Risk 1's ordering depends on,
   which nothing currently pins. Note `main-health-monitor-workflow.test.sh` parses the YAML with
   python regex and **never executes the shell**, so asserting the literal `grep -v '^| '` appears
   is a *spelling* check: to pin the effect, extract the excerpt block and run it against a fixture
   capture. Otherwise state plainly that AC4 pins the filter's **presence**, not its **effect** —
   and that the GDPR clearance depends on the effect.
4b. **Check (10) is amended deliberately, with a rationale comment**
   (`main-health-monitor-workflow.test.sh:246-255`): the new filter matches its offender pattern
   (`| tail` without `PIPESTATUS`, without literal `grep -E`) and would otherwise red the PR. Not
   worked around by spelling it `grep -E -v`.
4c. **The tests-half excerpt is unchanged.** `scripts/expenses-verify-by-check.test.sh:49,50,53`
   emits markdown tables at column 0; assert the tests-step excerpt is byte-identical to today's,
   proving the sentinel filter did not strip a legitimate existing signal.
5. A fully green run emits **no** dump (no `^| ` lines at all) and exits 0.
6. `bash plugins/soleur/test/main-health-monitor-workflow.test.sh` passes, including existing
   check (12) (`JOBS: 1` on both steps) and the new pins from AC4.
7. The live-tree collision is closed: `run-registered-suites.test.sh` creates and removes **no**
   file under `apps/web-platform/infra/` during its run (assert by diffing a directory listing
   snapshotted across the suite), **and** `credential-persist-home-guard.test.sh` diffs against a
   frozen snapshot rather than the live source.
8. Prose sweep complete, anchored on the **verified real strings**, not on `dev/null 2>&1` (which
   appears zero times in the monitor): `run-registered-suites.sh:42-43`,
   `main-health-monitor.yml:408-409` and `:136`. Assert that neither file still claims suite output
   is discarded, and that neither says "92 suites" where it means the derived count.
9. `bash scripts/test-all.sh` green (it nests the runner at default `-P` via `test-all.sh:801`).
10. Hypothesis verdicts in the plan/PR body are **measured**, each against its stated confirmation
    criterion. **Floor:** H2 and H4 must each reach CONFIRMED or REFUTED, or the PR must state
    which reproduction the plan failed to obtain and why — "still UNKNOWN" is only acceptable with
    that explanation.
11. **Proof of fix, with a denominator.** Record a **pre-fix baseline** on the unmodified tree:
    the same `taskset -c 0-3` loop, same n. Then ≥ 20 consecutive green post-fix runs at the
    **default** parallelism (`JOBS=4`). *If the baseline reproduced 0 failures, AC11 proves only
    "no regression" — say exactly that, do not claim the flake is fixed, and honour the Split
    Trigger.* Two further limits must be stated rather than glossed: `taskset` bounds **CPU only**,
    not RAM, disk or `/var/tmp` headroom, so **AC11 cannot validate an H2 fix**; and the instrument
    itself changes I/O and scheduling, so a green post-fix loop is partly an observer effect unless
    the baseline was run with the instrument present.
12b. **The corpus-conformance test passes** (Phase 1 item 12): every registered suite's failure
    literal matches the runner's marker ERE, and no suite emits the sentinel at column 0. Failure
    names the suite.
12c. **The accounting assertion is present and mutation-proven**: `PASS + RED == ${#SUITES[@]}`,
    with a fixture where a child is killed mid-run proving the runner now exits non-zero.
13. **Redaction widening ships in this PR** (Risk 2): JWT `eyJ…`, `sbp_v0_`, `rk_live_`/`whsec_`,
    `dp.scim.`/`dp.audit.`, Sentry DSN + `sntrys_`, `Authorization: Basic|Bearer`, and the PEM
    **range** form replacing the header-only rule. Asserted against a synthesized token corpus —
    never real values (`cq-test-fixtures-synthesized-only`).
12. `JOBS: 1` at `main-health-monitor.yml:304` and `:323` unchanged (already enforced by check (12)
    — this AC is belt-and-braces and exists mainly to flag that the *follow-up* PR must delete
    that check).

**If the Split Trigger fires,** ACs 1-9 gate the instrument PR; ACs 10-11 move to the follow-up
fix PR. Note AC9 is itself nondeterministic on the instrument PR (it nests the flaky runner) — on
that PR, treat an AC9 failure naming a suite as *evidence*, not as a gate failure, and record it.

### Post-merge (operator)

None. Removing the `JOBS=1` stopgap is deliberately not in this PR.

**The soak that gates it is deadlocked today, and the follow-up must break the deadlock
explicitly:** removing `JOBS=1` requires a soak of the fix on the default path, but the only place
CI runs the runner at default `-P` is the monitor itself — pinned `JOBS: 1` at both `:304` and
`:323`, covering the standalone step and the nested `test-all.sh:801` invocation. So the follow-up
PR must do all three: (a) add a `continue-on-error`, **non-issue-filing** probe job at `-P 4` to
gather CI-grade evidence, or accept local-loop evidence and say so; (b) remove the two `JOBS: 1`
pins; (c) **delete check (12)** from `main-health-monitor-workflow.test.sh`, which currently
asserts those pins and would otherwise red the follow-up. *(Automation: a normal PR, not an
operator action.)*

## Observability

```yaml
liveness_signal:
  what: "run-registered-suites.sh `N passed, M failed (of 93)` epilogue, plus a bounded per-suite diagnostic on every RED"
  cadence: "every invocation (local, infra-validation.yml, main-health-monitor.yml)"
  alert_target: "main-health-monitor.yml filer (P1 ci/main-broken issue)"
  configured_in: "apps/web-platform/infra/run-registered-suites.sh; .github/workflows/main-health-monitor.yml"
error_reporting:
  destination: "GitHub Actions run log (public repo) + the monitor's filed issue body (redacted excerpt)"
  fail_loud: "yes — non-zero exit when any suite REDs; zero-derivation and missing-workflow exit 2"
failure_modes:
  - mode: "a suite REDs under parallelism"
    detection: "per-suite rc + elapsed + bounded log tail, printed by the runner itself"
    alert_route: "monitor excerpt names the suite via the existing `^RED ` line"
  - mode: "a suite is OOM-killed or times out"
    detection: "per-suite rc == 137 / 124, recorded in the dump banner"
    alert_route: "same"
  - mode: "disk or tmpfs exhaustion"
    detection: "`No space left on device` in the captured suite log"
    alert_route: "same"
  - mode: "a suite self-skips for a missing tool and prints PASS"
    detection: "pre-existing `Assert toolchain present` step, ordered before the suite steps"
    alert_route: "job fails"
logs:
  where: "per-run log dir (path printed; retained on failure, reaped on success) + the Actions run log"
  retention: "GitHub Actions default (90d). The on-disk dir serves the LOCAL repro only — a hosted runner is destroyed with its filesystem"
discoverability_test:
  # Note the runner exits NON-ZERO on RED by design, so `; echo rc=$?` is part of the
  # demonstration — without it a successful diagnosis is indistinguishable from a broken command.
  command: "taskset -c 0-3 bash apps/web-platform/infra/run-registered-suites.sh; echo rc=$?"
  expected_output: "on any RED: a named suite with rc, elapsed and a prefixed excerpt anchored on its failing assertion, then rc=1 — no ssh"
```

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-133 with one clause; do not open a new ADR.** The clause: *ADR-133's "capacity, not a
colliding path" verdict was measured on a RAM-backed `/tmp` workstation under cross-worktree
overlap and does not transfer to a hosted runner on disk-backed `/var/tmp`.* This exists to stop
the next reader citing ADR-133 as evidence about a different machine. Nothing else is durable:
"the instrument-before-fix ordering held again" is not an architectural decision, and a Phase 3
finding is either durable enough for its own ADR or not ADR material.

**Explicitly rejected: a shared parallelism/width primitive.** Per R4, `test-all.sh` is sequential
and has no width to govern — such a primitive would have exactly one consumer. The correct split
is **observation shared** (`scripts/lib/test-contention.sh` already owns headroom probes),
**policy local** (the `-P` value stays in `run-registered-suites.sh`).

### C4 views
**No C4 impact.** Enumerated against all three model files (`model.c4` 656 lines, `views.c4` 70,
`spec.c4` 54), not a keyword grep: **no external human actor** added (the developer/operator is an
existing actor); **no external system or vendor** added — CI already exists as
`github = system "GitHub"` (`model.c4:230`, *"Source control, CI/CD, issue tracking, and
releases"*) and this change is entirely **inside** that modeled system; **no container or data
store** (the per-run log dir is ephemeral scratch); **no access relationship** changes. No `.c4`
element description is falsified.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Four findings materially changed the plan. (1) An instrument shipped alone to
`main` would observe **nothing**, because CI is pinned `JOBS: 1` at `:304`/`:323` — which,
combined with the simplicity review, collapsed the split into a single PR with an explicit Split
Trigger. (2) Dumping raw suite output would inject `^[FAIL]` (10 registered suites emit it at
column 0) into the monitor's excerpt **and its issue title** — an AP-021/ADR-166 violation;
answered by mandatory line-prefixing (Risk 1, AC3). (3) Exit code and wall time are near-free and
were promoted to the first read in Phase 3 — though note the simplicity review's correction that
`rc` **cannot** separate H1 from H3 (both yield `rc=1`), so the captured log remains the
deliverable, not a luxury. (4) Auto-derived width rejected — a harness whose width varies with the
environment makes its own flake irreproducible. Also supplied: the log-lifetime trap, and the
`test-all.sh:801` nested second `-P` site.

**Product/UX Gate:** not applicable — Product not flagged; the mechanical UI-surface override did
not fire (no path in Files to Edit matches a UI-surface glob).

## Open Code-Review Overlap

**None.** All 64 open `code-review` issues were queried; no body references
`run-registered-suites`, `main-health-monitor.yml`, `scripts/lib/test-contention.sh`,
`inngest.test.sh`, or `web-host-provisioner-parity-mutation`.

## GDPR / Compliance Gate

No regulated-data surface (no schema, migration, auth flow, API route or `.sql`).

**Trigger (d) — *new artifact distribution surface* — DOES fire. Its clearance has now been
withdrawn TWICE, on two different mistakes, and the second is the instructive one.**

1. *First draft:* cleared on "the published issue body stays byte-identical" — false, because
   `main-health-monitor.yml:436`'s `tail -30` is unconditional. Fixed by the sentinel filter
   (Phase 1 item 8) + AC4.
2. *Second draft:* re-cleared **on the issue body again** — but the issue body was never the new
   surface. Today the 93 suites' output goes to `/dev/null` and reaches **no** surface at all.
   After this change ~40 lines × N RED suites reach a **world-readable GitHub Actions run log**
   with 90-day retention. That is the genuinely new distribution surface, and the sentinel filter
   does nothing for it *by design*. The plan had even rejected "upload logs as a CI artifact"
   because *"public-repo artifacts are public too"* — the identical objection, not carried across.

**Cleared on the corrected premise**, which rests on a measured bound rather than a mitigation:
the monitor's infra step runs with **no `secrets.*` in its env** (`main-health-monitor.yml:316-329`),
and a sweep of all 93 suites found no `set -x`, no whole-env dump, no read of `~/.docker/config.json`
/ `~/.config/doppler` / `.netrc` / private keys, no tfvars/tfstate/`terraform output`, and only two
real external invocations — both `terraform console` in an `mktemp -d` with placeholder inputs
(`cloud-init-inngest-bootstrap.test.sh:340,344`, `git-data-render-strip-parity.test.sh:214`). So the
run-log surface carries no live credential **today**.

**That is an observed property, not a gate.** `cq-test-fixtures-synthesized-only` scopes to
`__goldens__/**`, `**/*.snap`, `apps/web-platform/test/fixtures/**` (`AGENTS.rules.md:128`) — it does
**not** cover `apps/web-platform/infra/*.test.sh`, and its hook (`secret-scan.yml`/gitleaks) inspects
committed files, saying nothing about runtime output. A future suite can violate this with no check
firing. Say so in the PR body rather than implying a gate exists.

## Encryption Posture

Not applicable — no persistent store and no new cross-component connection.

## Risks & Mitigations

**Risk 1 — Corrupting the monitor's excerpt and its issue title (highest).** 10 registered suites
emit `[FAIL]` at column 0. `main-health-monitor.yml:430` greps `^RED |^\[FAIL\]` with `head -20`
to build the issue body, `:436` `tail -30` expects the summary, and `HAS_FAIL_MARKER` (`:413`,
`:457`) drives the issue **title** — so a dumped `[FAIL]` during a *timeout* would title an issue
with a cause the job never measured, the AP-021/ADR-166 defect #7371 exists to remove.
**Mitigation:** prefix every dumped line so no dumped byte matches either anchor; dump **before**
the final summary block so `tail -30` still ends on the count; pin both in tests (AC3, AC5).

**Risk 2 — Secret exposure into a public issue.** The redaction set at `:473-481` is prefix-keyed
and misses Hetzner tokens (64-char hex, no prefix), Cloudflare tokens (~40-char base62), and the
**body** of a PEM key (only the `BEGIN` header is rewritten).

> **An earlier draft of this plan claimed line-prefixing gave "zero delta to the published
> surface". That was FALSE, and the GDPR clearance rested on it.** `main-health-monitor.yml:436`
> appends `$(tail -30 "$file")` to `$SUMMARY` **outside** the `if [[ -n "$hits" ]]` block, so it
> runs on every non-success step regardless of any anchor. Prefixed dump lines would have landed
> in the public issue body verbatim. Recorded rather than quietly corrected, because the mistake
> is the instructive part: the mitigation was verified against the *anchor* path and not against
> the *unconditional* one 6 lines below it.

**Mitigation (two parts, both required):** (i) #7374's complaint is that the operator gets no
suite *name*, and names come from the `^RED ` lines that already exist — dumps answer *why* and
belong in the run log; (ii) **the monitor's tail must filter the sentinel**
(`grep -v '^| ' "$file" | tail -30`, Phase 1 item 7). Only with (ii) is the published body
genuinely unchanged. Additionally, all now tracked by ACs rather than prose:
- **Cap** the dump at the named constant; never dump `env`.
- **Widen the redaction set** (AC13). Measured gaps beyond the three already named: **JWTs
  (`eyJ…`) are unmatched** — the highest-value miss, since OIDC id_tokens and Supabase
  `service_role` keys wear that shape; `sbp_v0_…` fails because `_` is outside the rule's
  `[A-Za-z0-9]`; Stripe `rk_live_`/`whsec_`, Doppler `dp.scim.`/`dp.audit.`, the Sentry DSN
  (the URL rule requires a `:password@`, which a DSN lacks) and `sntrys_`, and
  `Authorization: Basic|Bearer` are all missed.
- **Fix the PEM rule, which is currently an ANTI-mitigation.** `:481` rewrites only the
  `-----BEGIN…-----` header, stripping the one marker that makes a leaked body recognisable to a
  human or a scanner while leaving the base64 and the `-----END-----` intact. It needs a range
  form: `sed -E '/-----BEGIN [A-Z ]*PRIVATE KEY-----/,/-----END [A-Z ]*PRIVATE KEY-----/c\<redacted-private-key-block>'`.
  `sed` is line-based, so nothing spanning a newline is catchable any other way.
- **Close the one real emit site.** `workspaces-luks-header.test.sh:384` echoes
  `kid=$AWS_ACCESS_KEY_ID` and `:391` prints that output **on the FAIL path** — exactly the path
  the new dump captures. A local `doppler()` stub supplies `stub-…` today, and
  `infra-validation.yml:1442-1447` exports real AWS creds into `$GITHUB_ENV` in a *different* job,
  so the isolation is one job-move away. One-line fix: prefix the subshell
  `AWS_ACCESS_KEY_ID= AWS_SECRET_ACCESS_KEY=`.
- **Masking does not help here.** GitHub masks registered secrets in the *run-log stream* only.
  The monitor `tee`s to a file inside its own process tree and posts it via `gh --body-file`, an
  HTTPS call that never traverses the log stream. The `sed` is a single layer with nothing behind
  it — and this repo is public, so the run log is world-readable regardless.

**Risk 3 — Deleting the evidence.** Extending `trap 'rm -f "$LOG"' EXIT` to `rm -rf "$LOGDIR"`
would delete the artifact Phase 3 exists to collect, on exactly the runs that matter.
**Mitigation:** retain on non-zero exit; reap on success; `${LOGDIR:-}` under `set -u`.

**Risk 4 — Interleaved output.** Only if the dump is emitted from inside an `xargs` child.
**Mitigation:** dump from the parent, single-threaded, after `xargs` returns. Keep the summary line
under `PIPE_BUF` so it stays atomic, and document that as the invariant.

**Risk 5 — Non-reproduction read as refutation.** A local 4-core pin does not reproduce
shared-runner IO contention or cgroup throttling. **Mitigation:** the Split Trigger, and AC11's
explicit caveat that 20 green runs prove "no regression" unless a pre-fix baseline reproduced.

**Risk 6 — Wall-clock regression.** Any class-serialisation lengthens the run. **Mitigation:**
measure against `deploy-script-tests`' cold sequential figure (n=25, max 459 s) and the monitor's
derived ceilings before changing any width.

## Test Scenarios

All four use the `INFRA_WF` **and the new `INFRA_DIR`** seams, so fixture suites live under a
`mktemp -d` and **never in the live infra directory** (~2 s total).

> **Why `INFRA_DIR` is not optional.** The derivation regex hardcodes the
> `apps/web-platform/infra/` prefix, so without the seam these fixtures could only be registered by
> creating executable files **in the live tree** — reproducing, three times over, the exact defect
> Phase 2 exists to remove. A test that recreates the bug it is guarding is worse than no test.

| # | Scenario | Expected |
|---|---|---|
| T1 | Fixture workflow: 1 PASS + 1 RED suite, where the RED suite fails **early** and then emits ≥ 100 further passing lines | `RED  <path>` in exact byte shape; the dump is present, prefixed, ≤ ~40 lines, carries `rc` + elapsed, and **contains the early failing assertion** (the blind-tail trap); log dir retained and path printed; exit non-zero |
| T2 | Fixture suite emitting `[FAIL]` at column 0, dumped | `grep -cE '^(RED &#124;\[FAIL\])'` over the whole output counts genuine `RED` lines only. **The ERE alternation must be a bare `&#124;`** — writing `\|` (as a markdown-escaped table cell tempts) makes it a literal pipe that matches nothing and passes vacuously; measured: correct form 2, escaped form 0-and-exit-1 |
| T3 | Monitor excerpt logic applied to a capture containing dumped lines | `$SUMMARY` contains **no** `^&#124; ` line — the `tail -30` sentinel filter works (AC4) |
| T4 | All-green fixture run | No dump (no `^&#124; ` lines); log dir reaped; exit 0; `--list` still emits no `^(PASS&#124;RED) ` lines (existing T2c) |

AC11's 20× full-suite `taskset` loop is a proof-of-fix procedure, not a fixture test — it cannot
live in a 2-second suite and is deliberately absent from this table.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| Keep `JOBS=1` everywhere and close #7376 | **Rejected.** It is the recorded stopgap, not a fix; the default `-P` path is what every local invocation and the nested `test-all.sh` path use |
| Commit to H1 and rewrite the `\| grep -q` sites | **Rejected — refuted by measurement.** Every site is ≥ 12× under the 64 KiB threshold |
| Cap `-P` by available memory (the issue's own suggestion 3) | **Rejected as the default.** It presupposes H2, and "available memory at t=0" is the wrong metric — the failure is the *peak* of 4 concurrent suites. Retained only as a class-serialisation arm |
| Ship instrument and fix in separate PRs | **Rejected as the default.** The evidence source is a local loop needing the instrument in the working tree, not on `main`; and an instrument on `main` observes nothing under `JOBS: 1`. Retained behind the Split Trigger |
| A capacity preamble on every run | **Rejected.** A t=0 reading cannot describe the peak — the same argument that rejects width-derivation — and the disk signature lands in the captured log for free |
| A shared width primitive across both runners | **Rejected** (R4) — one consumer |
| Upload per-suite logs as a CI artifact | **Rejected as primary.** Public-repo artifacts are public too, and it puts diagnosis a download away. Bounded, prefixed stdout is simpler and leaves the issue body unchanged |
| Ship a `\| grep -q` linter now | **Deferred to a follow-up issue.** The defect is unreachable today, and the rule needs a mass rewrite or a baseline file |

## Sharp Edges

- **Do not "add `set -o pipefail`" to the runner** — it is already at `:91`, and the exit status
  comes from counting `^RED` lines, not the pipeline (R1). Anyone working from the general
  "`| tee` masks exit codes" pattern will propose this; it is a non-defect here.
- **Do not remove `JOBS: 1` from `main-health-monitor.yml`** in this PR. Both `:304` and `:323`
  stay. Removing it to obtain data re-arms ~1-in-3 spurious P1 filing.
- **A producer under 64 KiB cannot SIGPIPE.** Before anyone re-proposes the `| grep -q` rewrite,
  measure the producer's total output. The mechanism is real; the sites are immune. See H1.
- **The runner's header documents its own executor.** Changing `bash "{}" >/dev/null 2>&1`
  falsifies that prose in two header locations and twice more in `main-health-monitor.yml` (one of
  which also carries a stale "92 suites"). Sweep all of them, or the file reproduces the #7103
  defect it documents — a registered runner denying its own registration.
- **A suite's `[FAIL]` is not the runner's `RED`.** The runner emits `RED  <path>` (two spaces);
  `grep FAIL` over its log returns zero hits on a failing run and reads as clean (#7220). Any new
  assertion must anchor on `^RED `.
- **`run-registered-suites.test.sh` is itself registered** (`infra-validation.yml:1057`) and runs
  concurrently with the other 92. Anything it does to the filesystem, it does *while the other
  suites are reading that filesystem*.
- **`report_orphans()` is expensive** — `git ls-files` plus one `git grep` per suite over the whole
  repo, and the test calls `--list` four times (~372 multithreaded `git grep` on a 4-core box). Do
  not add `--list` invocations casually.
- **A new suite file must be registered in `infra-validation.yml`** or
  `.github/scripts/test/test-infra-suite-registration.sh` fails a required, path-filter-free check.
- **`PIPE_BUF` atomicity is a property of PIPES, not files — ask what is on the other side of the
  `>`.** The runner's children are safe *only* because their stdout is `| tee "$LOG"`. Change that
  to `> "$LOG"` and all four children share one open file description; `awk`/`bash` block-buffer in
  ~4096-byte flushes whose boundaries land mid-line, and another child's flush lands in the gap.
  `scripts/generate-kb-index.sh` shipped exactly this defect — its comment even asserted
  *"lines are always smaller than PIPE_BUF (4 KB), so atomic writes hold … no shared append
  target"* while redirecting to a file — and it fabricated ~14 corrupted values into a committed
  artifact that a validation gate then enforced. Fixed the same day this plan was written
  (`knowledge-base/project/learnings/2026-08-10-pipe-buf-atomicity-does-not-apply-to-the-file-i-was-redirecting-into.md`).
  This plan adds per-suite file writes to a runner whose summary path is a pipe; keep the two
  separate and do not merge them.
- **The monitor's `tail -30` is UNCONDITIONAL.** It sits outside the `if [[ -n "$hits" ]]` block
  (`main-health-monitor.yml:436`), so anchoring dumped output away from `^RED `/`^[FAIL]` does
  **not** keep it out of the public issue body. Any change to what the runner prints must be
  checked against **both** the anchor path (`:430`) and the tail path (`:436`). An earlier draft of
  this plan got this wrong and cleared the GDPR gate on it.
- **`\|` inside an ERE is a literal pipe, not alternation.** `grep -cE '^(RED \|\[FAIL\])'` matches
  **nothing** and exits 1 — a verification that passes vacuously. Markdown tables tempt this
  escaping; the plan uses `&#124;` in table cells so the shipped regex stays bare.
- **The runner counts `grep -c '^RED'` without a trailing space** (`:185`) while every downstream
  consumer anchors on `^RED ` *with* one. Harmless today because dumped lines are prefixed, but do
  not let any content reach `$LOG` that could begin with `RED`.
- **"It passes when run standalone" is not evidence.** Every named suite already does; all four
  hypotheses predict it. It is the bug's precondition, not a discriminator.
- **`taskset` bounds CPU only.** It does not bound RAM, disk, or `/var/tmp` headroom, so a local
  4-core loop **cannot** validate a capacity (H2) fix, and a local non-reproduction refutes
  nothing.
