---
title: "fix: parallel-worktree test-all.sh contention — headroom, leak reaping, and a self-announcing queue"
date: 2026-07-22
type: fix
issue: 6789
branch: feat-one-shot-6789-testall-concurrency-false-reds
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix: parallel-worktree `test-all.sh` contention produces false REDs

> **Lane note:** no `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed) per the plan skill's carry-forward rule.

## Enhancement Summary

**Deepened on:** 2026-07-22 · **Gates run:** 4.4, 4.5, 4.55, 4.6, 4.7, 4.8, 4.9 (no halt fired)

### Key improvements from the deepen pass

1. **Deleted a whole hand-rolled lock from scope.** The precedent diff found `session-state.sh` already provides a git-common-dir-anchored, timeout-bounded, kill-switched, fail-open `flock` wrapper. Phase 3 now reuses it and modifies nothing shared.
2. **Made the lock advisory (timeout ⇒ proceed, never abort).** This collapses the plan's highest-blast-radius risk: no failure mode of this change can now prevent a test run.
3. **Removed an untestable acceptance criterion.** Measured that `flock` auto-releases on holder death, so the prescribed "stale-holder detection" was dead code defending an unreachable state. Replaced with an assertion of the property (AC5b).
4. **Decoupled the holder announcement from the lock**, after finding the primitive writes no holder metadata — the Phase 1 sibling scan supplies it and keeps working when the lock is disabled.

### New considerations discovered

- `.scan-meta.json` is **GDPR Art. 32 evidence** with a documented post-exit consumer — so the leak fix must age-reap, not trap-delete (R1, AC8). A naive "add the missing trap" would have shipped a silent compliance regression.
- The occupancy is dominated by **three** entries (3.1 GiB), not the 4 294 small ones (160 MB) — the intuitive fix would have recovered 4.5 % of the problem.

## Overview

Two sessions in sibling worktrees cannot run `scripts/test-all.sh` concurrently without risking failures that look like real regressions. The only mitigation today is prose in `plugins/soleur/skills/work/SKILL.md` telling the agent to run `ps -ef | grep test-all` and wait — detection guidance for a human, not isolation.

This plan does four things, in dependency order:

1. **Recover the exhausted shared resource.** The contended resource is the machine-global **4 GiB `/tmp` tmpfs**, measured at **86 % full** — and it is RAM-backed, so its occupancy directly reduces the memory both concurrent runs compete for.
2. **Reap the leaks at source**, bounded by a measured priority (three entries hold 88 % of the occupancy; 4 294 entries hold 4.5 %).
3. **Make a contended run self-identifying** so a false RED is never again diagnosed as a regression.
4. **Replace the manual `ps` ritual** with an advisory, self-announcing, escapable queue.

The recorded cause in `work/SKILL.md` is corrected as part of the fix — **both halves of the "known pair" are refuted by measurement**, and the real defect at one of those same paths is a leak, not a collision.

---

## Research Reconciliation — Recorded Cause vs. Measured Reality

| Recorded claim (`work/SKILL.md:688`) | Measured reality | Plan response |
|---|---|---|
| `skill-security-scan`'s `.scan-meta.json` is a shared path that collides across worktrees | **Refuted.** `run-scan.sh:179-181` PID-scopes it to `${XDG_RUNTIME_DIR:-/tmp}/skill-security-scan-$$`. `git log -S'skill-security-scan-$$'` returns **one** commit — `5da50856d` (#3524), the skill's original commit. It was PID-scoped from birth; the attribution was **wrong when written**, not stale-after-a-fix. | Rewrite the prose (Phase 4). Record the correct mechanism. |
| The semgrep bootstrap is the other half of "the known pair" | **Refuted by reachability.** `ensure-semgrep.sh` is invoked only by `review/SKILL.md:240`, `review.workflow.js:65`, and the `semgrep-sast` agent body — all agent-driven. A grep over the *exact* suite globs `test-all.sh` enumerates returns **zero** hits. No suite reached by `test-all.sh` can run the bootstrap. | Remove from the prose (Phase 4). No lock needed for it. |
| *(implied)* the failure mode is a path collision | **Refuted.** Both implicated suites document their own contention mode as a **timeout**, in-repo: `skill-security-scan.test.ts:177-179` — *"under contention this exceeds bun-test's 5000ms default per-test timeout (#4096)"*; `vitest.config.ts` — *"#3817 confirmed the … flake class is worker-pool resource contention"*, with observed *"isolated → 6-14s contended"*. Both already raised their timeouts rather than fixing a path. | Treat as a **resource** problem (Phases 1-3), not a naming problem. |
| *(new — not in the issue's candidate list)* | **`.scan-meta.json`'s directory leaks.** `meta_dir` (`run-scan.sh:179-181`) is created with `mkdir -p` and covered by **no cleanup trap**. Measured: **12 780** leaked `skill-security-scan-<pid>` directories. | Age-reap (Phase 2b) — **not** an `EXIT` trap; see the compliance constraint below. |

**Premise Validation.** `#6789` is OPEN (`gh issue view 6789` → `state: OPEN`, milestone *Post-MVP / Later*, labels `type/chore`, `priority/p3-low`, `domain/engineering`). Cited siblings #2349, #4605, #3702 are referenced by the issue as *related but distinct* and are not blockers. No premise is stale.

---

## Hypotheses

Ordered as the issue asked. Verdicts state the **discriminator that decided them** — a verdict with no available discriminator is recorded as UNKNOWN, not as a refutation by reasoning.

| # | Hypothesis | Verdict | Discriminator |
|---|---|---|---|
| H1 | semgrep bootstrap interleaves on machine-global installer state | **REFUTED** | Mechanical reachability: zero test suites under `test-all.sh`'s globs invoke `ensure-semgrep.sh`. Not reasoning — a grep over the runner's own enumeration. |
| H2 | `.scan-meta.json` path collides across worktrees | **REFUTED** | `git log -S` shows PID-scoping present in the original commit; `$$` differs per process. |
| H3 | **Resource oversubscription on a shared, RAM-backed, capacity-limited `/tmp`** | **CONFIRMED as present and material; NOT established as the sole cause** | Direct measurement (below) + two suites' own in-repo documentation of timeout-under-contention. The one datum not yet captured is a *measured concurrent two-run failure* — Phase 1's instrumentation exists to capture exactly that. |
| H4 | A remaining fixed-path tempfile in a reachable suite | **UNKNOWN — not refuted** | Fixed `/tmp` literals in reachable suites are injection canaries asserting *absence* (`/tmp/ctxq_pwn`, `/tmp/phase_surface_pwn`, `/tmp/PWNED_RULES_LOADER.json`). Those are false-**GREEN** risks under concurrency, not false-RED. A shared *derived* path remains possible; Phase 1's per-suite tempfile delta is the probe that would surface it. |

### Measurements taken (2026-07-22, this machine)

```
/tmp                      tmpfs  4.0G  3.5G used (86%)  603M avail   7402 entries
  /tmp/tmp.t03Q1anpIr            1.8G   (abandoned full repo scratch clone, Jul 20 18:08)
  /tmp/tmp.FzpzHkBfED            919M   (repo/repo2/repo3/probe/trace scaffolding)
  /tmp/test-repo                 385M   (fixed-path repo checkout, Jul 19 22:24)
  -> 3 entries = 3.1G = ~88% of occupancy
  4294 small tmp.* entries       160M   = ~4.5% of occupancy
  4240 leaked bare tmp.XXXXXX:   2353 on 07-20, 1430 on 07-21, 465 on 07-22
  45 leaked skill-scan-input-*:  all dated 07-20  (the #6726 incident date)

/run/user/1001            tmpfs  3.1G   66M used (3%)
  12780 leaked skill-security-scan-<pid>/ dirs (run-scan.sh meta_dir, no trap)

RAM 30G total / ~6G available   Swap 1G total / 1G used (EXHAUSTED)
16 cores, load 7.55 9.42 9.63
vitest `run` default maxForks ≈ availableParallelism()-1 = 15 -> two runs ≈ 30 forks
```

**Isolated control run** of the suite that failed 4× under contention in #6726:

```
bun test plugins/soleur/test/skill-security-scan.test.ts
  -> 22 pass / 0 fail in 117.85s        (matches #6726's reported isolated 22/0)
  -> leaked +16 /tmp entries, +2 skill-scan-* artifacts, in ONE isolated run
```

### What the measurements establish

- The contended resource is **not a name, it is a capacity**: every suite's `mktemp` lands in the same 4 GiB tmpfs. Two runs draw on one budget already 86 % consumed.
- Because tmpfs is RAM-backed, its 3.5 GiB occupancy is 3.5 GiB of RAM withheld from a machine with ~6 GiB available and **swap fully exhausted** — which is precisely the condition under which the two suites' documented timeout-flake class fires.
- The 4 GiB cap is **deliberate**: it is Layer 3 of the 2026-03-28 tmpfs guard (`knowledge-base/project/learnings/2026-03-28-tmpfs-guard-cron-defense-in-depth.md`), added so a runaway file could not consume all system memory. The cap is correct; what is missing is a reaper for the class of artifact now filling it.
- `scripts/tmpfs-guard.sh` **is live** (`*/5 * * * *` in crontab) but scopes to `/tmp/claude-<uid>/**/*.output` files > 200 MB only. It has a high-usage branch that *warns* and does not clean — which is why /tmp sat at 86 % while a guard ran every five minutes.

---

## User-Brand Impact

**If this lands broken, the user experiences:** at worst, today's behaviour plus a noisy banner. The Phase 3.2 advisory decision (timeout ⇒ proceed, never abort) means no failure mode of this change can prevent a test run from happening. The two residual ways to land broken are an over-eager reaper deleting live scratch state (R3) and a cleanup change breaking the override-artifact path (R1) — both carry their own ACs.

**If this leaks, the user's data is exposed via:** no new exposure surface. One adjacent compliance surface is touched read-carefully, not widened: `.scan-meta.json` is referenced by the GDPR Art. 32 override-artifact mechanism (`skill-security-scan/references/override-mechanism.md`), so its reaping is age-bounded rather than trap-deleted (see Risks R1).

**Brand-survival threshold:** `none`

- `threshold: none, reason: local developer test-runner tooling on the operator's own machine; no product runtime surface, no user data, no tenant boundary, and no deployed artifact is altered by this change.`

---

## Implementation Phases

### Phase 1 — Instrumentation first (ships ahead of every fix in this plan)

The probe must land before any remediation, because H3 is *confirmed as material* but **not** established as the sole cause, and H4 is genuinely UNKNOWN. Shipping a fix first would destroy the conditions the probe exists to observe.

- **1.1** Add a contention preamble to `scripts/test-all.sh`, emitted before the first `run_suite`:
  - `/tmp` headroom (`df -k /tmp` → used %, avail MB) and the same for `${XDG_RUNTIME_DIR}`.
  - Sibling detection: enumerate other live `test-all.sh` processes and resolve each to its worktree via `/proc/<pid>/cwd`. Report path + pid + elapsed.
  - Machine pressure: `nproc`, `/proc/loadavg`, `MemAvailable`, swap free.
- **1.2** Add a matching epilogue recording the **`/tmp` entry-count and byte delta across the whole run**, plus a per-suite delta appended to the existing `TEST_TIMING_LOG` channel (the script already has this mechanism — extend the record, do not invent a second one). A suite with a non-zero entry delta is a leaker; this is the probe for H4.
- **1.3** **Fail loud and attributable, do not fail silently.** When `/tmp` avail is below a floor at start, or a sibling run is detected, print a clearly-marked banner naming the condition. The banner must state *which* condition fired so the reader is never left inferring.

> **Ordering is load-bearing.** 1.1-1.3 contain no behavioural fix; they only observe. Do not fold them into a commit that also changes cleanup or locking.

### Phase 2 — Recover and bound the headroom

Priority follows the measurement, not the entry count.

- **2a — the dominant driver (88 % of occupancy).** Extend `scripts/tmpfs-guard.sh` from `.output`-only to also reap **stale, large, own-uid** `/tmp` scratch entries. Reuse the guard's existing structure — it already has `fuser` active-handle respect, a usage-percentage escalation, and `logger`/`notify-send` reporting. Constraints:
  - Gate on **all three** of age, size, and ownership. Never reap by a single dimension.
  - Respect active file handles below the escalation threshold, exactly as the `.output` path already does.
  - Never touch `/tmp/claude-<uid>/` session dirs of *running* sessions — `cleanup_claude_tmp` in `worktree-manager.sh` already owns that boundary; do not duplicate or contradict it.
- **2b — bound the unbounded leak.** `run-scan.sh` `meta_dir` (`:179-181`) grows one directory per invocation forever (12 780 measured). Fix by **age-reaping older siblings at startup**, *not* by an `EXIT` trap — see R1. The newest artifact must always survive the process that wrote it.
- **2c — pin the per-run escape path.** The isolated control run leaked **+2** `skill-scan-*` artifacts despite the `EXIT` trap at `run-scan.sh:95`. Use Phase 1.2's per-suite delta to identify the escape path before changing the trap. Do not guess at the mechanism; the probe exists to answer this.
- **2d — ratchet, do not sweep.** `scripts/lint-trap-tempfile-ownership.py` + `.highwater` (currently `102`, live census `100`) already fences this class under ADR-129's accept. Lower the highwater to match whatever the census reads after 2a-2c. Do **not** attempt to pay off all 100 accepted files — that is the exact dynamic ADR-129 documents as "how a gate gets switched off."

### Phase 3 — Advisory, self-announcing queue

Replaces the manual `ps -ef | grep test-all` ritual. Its value does not depend on which resource is contended, so it is safe to ship under either H3 or H4.

- **3.1 Reuse the existing primitive — do not write a new lock.** `.claude/hooks/lib/session-state.sh` already provides `acquire_lock` / `release_lock` / `with_lock <name> <timeout_s> -- <cmd>`, and it already supplies every property this phase needs (see the precedent diff in Research Insights below): git-common-dir anchoring via `_session_state_root()` (so all worktrees of one repo share one lock), `flock -w <timeout>`, a `SOLEUR_DISABLE_SESSION_STATE` kill switch, a double-source guard, and idempotent re-acquisition. `test-all.sh` sources it and calls `acquire_lock` **internally** rather than being wrapped by a caller — self-enforcing, and no caller can forget.
- **3.2 The lock is ADVISORY: on timeout, proceed with a banner — never abort.** This is the load-bearing safety property. Aborting would convert today's 10-minute wait into a hard failure, which is strictly worse than the status quo. Proceeding-with-announcement preserves today's worst case (an interleaved run) while making it **attributable**, which is the actual defect being fixed. It also means the lock **cannot wedge a session** under any failure mode, which collapses most of R2.
- **3.3 Announcement comes from the Phase 1 sibling scan, not from the lock.** `_acquire_lock_impl` opens the lock file and `flock`s it but writes **no holder metadata**, so the holder's identity is not recoverable from the primitive. Do **not** extend the shared primitive to add it — Phase 1.1's `/proc/<pid>/cwd` sibling scan already produces exactly this information, is needed for the preamble regardless, and keeps working when the lock is disabled. Print `waiting on <worktree> (pid N, running Xs)` from the scan, refreshed during the wait so a long queue never looks like a hang.
- **3.4 Size the timeout to a full suite, not to `with_lock`'s 30 s default.** A `test-all.sh` run is minutes, not seconds; a 30 s timeout would make the advisory path fire on essentially every genuine overlap.
- **3.5 Exempt CI.** Gate acquisition on the absence of `CI`. CI shards run one job per runner; a lock there buys nothing and risks wedging a matrix. `test-all.sh` is already CI-aware via `TEST_GROUP`.
- **3.6 Do NOT implement stale-holder detection.** Measured (see Research Insights): `flock` is kernel-managed and inode-bound, and the kernel releases the lock automatically once the last fd holder dies. A "dead pid still holds the lock" state is **unreachable** with real `flock`; code defending against it would be dead code, and an AC asserting it would be untestable. Stale detection is only required for hand-rolled `mkdir`/PID-file schemes. Assert the property instead of implementing it.

### Phase 4 — Correct the recorded attribution

- **4.1** Rewrite the sibling-worktree paragraph at `plugins/soleur/skills/work/SKILL.md:688`. It must: drop both refuted causes; name the real mechanism (shared RAM-backed tmpfs capacity + process oversubscription, surfacing as timeouts); and point at the Phase 1 banner and Phase 3 queue instead of the `ps` ritual.
- **4.2** Keep the paragraph's genuinely-correct halves: confirm-three-ways before accepting "flake", and never delete another session's `/tmp` artifacts (now partly automated by 2a, but the manual prohibition stands).
- **4.3** Write the learning capturing the transferable lesson: *a documented cause is a claim with an author and a date, not a fact — re-derive before building on it.* Directory + topic only; the author picks the date at write time.

### Phase 5 — ADR

- **5.1** Author **ADR-133** (129-132 are taken; ordinal is **provisional** — `/ship` re-verifies against `origin/main` before merge, and a sibling PR can claim it mid-pipeline). Decision: *the local test runner serialises across worktrees via a git-common-dir advisory lock, and the shared tmpfs is treated as a managed, reaped resource rather than an unbounded scratch space.* Record the two refuted hypotheses in `## Alternatives Considered` so the next reader does not re-derive them.
- **5.2** If the ordinal is renumbered, sweep the whole feature artifact set in the same edit: `grep -rn 'ADR-133' knowledge-base/project/{plans,specs}/` — the plan, `tasks.md`, and any AC naming the ordinal, not just the ADR body.

---

## Architecture Decision (ADR/C4)

### ADR

**ADR-133** (provisional) — as described in Phase 5.1.

### C4 views

**No C4 impact.** Per the completeness mandate, this conclusion is supported by an enumeration against all three model files (`model.c4`, `views.c4`, `spec.c4`), not by a keyword grep:

- **External human actors:** none added. The only actor is the operator running tests on their own laptop — already outside the modelled product boundary, and not a data subject of any modelled store.
- **External systems / vendors:** none. No inbound webhook, outbound API, or third-party store is introduced. `flock` is a kernel primitive; `tmpfs` is a local mount.
- **Containers / data stores:** none. The `/tmp` tmpfs is a developer-machine resource, not a product container. The C4 model scopes the product runtime (web hosts, workspaces volume, Postgres stores, agent surfaces) — local developer tooling is deliberately not modelled, and adding it would misrepresent the boundary.
- **Actor↔surface access relationships:** none change. No ownership, tenancy, or trust boundary is touched.
- **Falsified descriptions:** none — no existing element description becomes untrue.

### Sequencing

None. The decision is true the moment the lock and the reaper land.

---

## Files to Edit

| File | Change |
|---|---|
| `scripts/test-all.sh` | Phase 1 preamble/epilogue + Phase 3 lock acquisition (sources `.claude/hooks/lib/session-state.sh`; **does not modify it**) |
| `scripts/tmpfs-guard.sh` | Phase 2a — extend reaper scope beyond `.output` |
| `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh` | Phase 2b age-reap; Phase 2c trap fix (probe-informed) |
| `scripts/lint-trap-tempfile-ownership.highwater` | Phase 2d ratchet down to post-fix census |
| `plugins/soleur/skills/work/SKILL.md` | Phase 4.1-4.2 corrected attribution |

## Files to Create

| File | Purpose |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-133-*.md` | Phase 5.1 |
| `knowledge-base/project/learnings/<topic>.md` | Phase 4.3 (directory + topic only; date chosen at write time) |
| A `.test.sh` covering the lock's decision arms | See Test Scenarios |

## Open Code-Review Overlap

**None.** Queried `gh issue list --label code-review --state open --limit 200` and matched each of `scripts/test-all.sh`, `plugins/soleur/skills/work/SKILL.md`, `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh`, `scripts/tmpfs-guard.sh` against every issue body via standalone `jq --arg`. Zero matches on all four.

---

## Observability

```yaml
liveness_signal:
  what: "test-all.sh contention preamble — /tmp headroom %, sibling-run count, load/MemAvailable"
  cadence: "every test-all.sh invocation (local); every CI test-* job"
  alert_target: "run stdout + TEST_TIMING_LOG record"
  configured_in: "scripts/test-all.sh"
error_reporting:
  destination: "stderr banner + logger(1) from tmpfs-guard.sh (existing channel)"
  fail_loud: true
failure_modes:
  - mode: "tmpfs saturation at run start"
    detection: "preamble reads df -k /tmp avail below floor"
    alert_route: "named stderr banner before suite 1 + non-zero-delta record in TEST_TIMING_LOG"
  - mode: "concurrent sibling run in another worktree"
    detection: "live test-all.sh pids resolved to worktrees via /proc/<pid>/cwd"
    alert_route: "'waiting on <worktree> (pid N, running Xs)' announcement, refreshed during the wait"
  - mode: "a suite leaks tempfiles (the H4 probe)"
    detection: "per-suite /tmp entry-count delta appended to TEST_TIMING_LOG"
    alert_route: "non-zero delta attributes the leak to a named suite label"
  - mode: "lock holder died holding the lock"
    detection: "recorded pid in lock file is not live"
    alert_route: "stale-holder message + automatic acquisition (never a silent block)"
  - mode: "unbounded meta_dir growth"
    detection: "count of skill-security-scan-* dirs under XDG_RUNTIME_DIR"
    alert_route: "startup age-reap bounds it; tmpfs-guard high-usage warn is the backstop"
logs:
  where: "run stdout; TEST_TIMING_LOG when set; logger(1)/syslog for tmpfs-guard"
  retention: "TEST_TIMING_LOG per-run (caller-owned); syslog per host policy"
discoverability_test:
  command: "bash scripts/test-all.sh scripts 2>&1 | head -20"
  expected_output: "contention preamble naming /tmp avail %, sibling count, and load before the first '--- <suite> ---' line"
```

No `ssh` appears in any verification path — this is local developer tooling by construction.

---

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering

**Status:** reviewed
**Assessment:** Local test-infrastructure change with no product runtime surface. Three engineering risks dominate and are each addressed above: (1) a lock is the one change that can wedge a session — mitigated by a mandatory triad of kill switch, bounded wait, and stale-holder detection, plus CI exemption; (2) a cleanup change on `.scan-meta.json` can silently break a GDPR Art. 32 evidence path — mitigated by age-reaping instead of trap-deletion (R1); (3) the temptation to sweep 100 accepted tempfile-debt files instead of ratcheting — explicitly rejected per ADR-129's own reasoning. The probe-first ordering is the correctness-critical constraint, not a nicety.

Product/UX Gate: not applicable — no UI surface in `Files to Edit` or `Files to Create`, and no user-facing page, flow, or component. The mechanical UI-surface override does not fire.

---

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** `scripts/test-all.sh` prints a contention preamble before the first `--- <suite> ---` line, naming `/tmp` avail %, sibling-run count, and machine load. Verified by `bash scripts/test-all.sh scripts 2>&1 | head -20`.
- **AC2** With a sibling `test-all.sh` running, the preamble names the sibling's **worktree path and pid** — not merely "a sibling is running".
- **AC3** `SOLEUR_DISABLE_SESSION_STATE=1 bash scripts/test-all.sh scripts` completes without acquiring the lock. Asserted in the new `.test.sh`, not by eyeball.
- **AC4** **A lock held past the timeout results in the run PROCEEDING with a banner, not aborting** — the advisory property (Phase 3.2). Asserted with a synthesized live holder and a short timeout override; the assertion is on the exit code being success **and** the banner text being present. *(This AC replaces an earlier "stale-holder detection" criterion, which was dropped as untestable: `flock` auto-releases on holder death, so the state it defended against is unreachable. See Research Insights.)*
- **AC5** With `CI` set, no lock is acquired. Asserted in the new `.test.sh`.
- **AC5b** After a holder is `SIGKILL`ed, the next acquisition succeeds without any stale-detection code path — asserting the kernel-release property Phase 3.6 relies on, so a future refactor to a hand-rolled lock scheme reddens here rather than silently reintroducing the hang.
- **AC6** `plugins/soleur/skills/work/SKILL.md` no longer asserts `.scan-meta.json` collision or the semgrep bootstrap as contention causes. Verify by asserting the **presence of the corrected mechanism sentence**, not by an absence-grep for the old tokens — the corrected prose legitimately discusses both refuted causes when explaining why they were refuted, so a bare absence-grep would false-fail a correct file.
- **AC7** `python3 scripts/lint-trap-tempfile-ownership.py --census` is **≤** the value in `.highwater`, and `.highwater` is not raised.
- **AC8** `run-scan.sh` still prints `.scan-meta.json written to: <path>` and the file exists **after** the process exits — the override-mechanism contract is intact. This AC is the regression guard for R1 and must fail if a naive `EXIT` trap is introduced.
- **AC9** `bash scripts/test-all.sh` exits 0 with the same suite count as before the change (the runner's own summary line), confirming no suite was dropped or double-registered.
- **AC10** The new `.test.sh` is registered by an explicit `run_suite` line in `scripts/test-all.sh` and passes `bash scripts/lint-orphan-test-suites.sh` — an unregistered suite is an orphan that gates nothing (the #5417 class this runner warns about in its own comments).
- **AC11** ADR-133 exists, and its `## Alternatives Considered` records both refuted hypotheses (H1, H2) with their discriminators.

### Post-merge (operator)

None. Every step above is automatable in-session: `tmpfs-guard.sh` is already installed in crontab and its scope change takes effect on the next 5-minute tick with no operator action; the lock, preamble, reaper and prose all ship as repo files.

---

## Risks & Mitigations

**R1 — Reaping `.scan-meta.json` could break a GDPR Art. 32 evidence path.** `override-mechanism.md` instructs the operator to reference the **path** to the redacted `.scan-meta.json` in an override artifact, and `run-scan.sh:216` prints that path for exactly this purpose. A naive `trap 'rm -rf "$meta_dir"' EXIT` would delete the artifact the moment the scan finished, silently breaking the override flow. **Mitigation:** age-reap older siblings at startup; never delete the artifact the current process just wrote. AC8 is the regression guard. *Pre-existing adjacent gap, noted not fixed:* `$XDG_RUNTIME_DIR` is cleared on logout, so a long-lived path reference in an override artifact is already fragile independent of this change — out of scope here, and not worsened by age-reaping.

**R2 — A lock could wedge every session.** Originally the highest-blast-radius item in the plan; **largely dissolved by the Phase 3.2 advisory decision.** Because a timeout causes the run to *proceed with a banner* rather than abort, there is no failure mode in which the lock prevents a test run from happening — the worst case degrades to today's behaviour, plus an attribution banner. Residual mitigations: the `SOLEUR_DISABLE_SESSION_STATE` kill switch (AC3), CI exemption (AC5), and the kernel-release property (AC5b). Note the primitive already fails **open** in the two hostile cases — `_session_state_require_flock` returns 99 when `flock(1)` is absent, and `_session_state_root` falls back to an orphan path when `git rev-parse` fails — so a missing dependency degrades rather than blocks.

**R3 — Reaping by a single dimension deletes live work.** Age alone would delete a long-running session's scratch dir; size alone would delete a small but active one. **Mitigation:** gate on age **and** size **and** ownership, and respect active file handles below the escalation threshold — reusing the logic `tmpfs-guard.sh` already applies to `.output` files.

**R4 — H3 is confirmed material but not proven sole.** Fixing headroom may not eliminate every false RED if H4 (a shared derived path) is also live. **Mitigation:** Phase 1's per-suite tempfile delta is precisely the probe for H4, and it ships first. If the probe attributes a non-zero delta to a suite after Phase 2, that is a new finding to act on — not a reason to have skipped the probe.

**R5 — Serialization has a real cost.** A queued second run waits for a full suite. **Mitigation:** the wait is announced and bounded rather than silent; the kill switch allows an explicit opt-out; and Phase 2's headroom recovery reduces how often the lock is the binding constraint. A concurrency cap (e.g. bounding vitest's ~15 forks) is deliberately **not** prescribed here — the data to choose its value is what Phase 1 collects, and picking it now would be exactly the unmeasured guess this plan exists to avoid.

---

## Research Insights (deepen-plan pass, 2026-07-22)

### Precedent diff — lock acquisition (Phase 4.4 gate)

The plan prescribes a lock, which is a pattern-bound behaviour with existing in-repo precedent. Two precedents were grepped and diffed:

| Property this plan needs | `agent-token-tee.sh` (canonical flock idiom) | `session-state.sh` (`acquire_lock`/`with_lock`) | Verdict |
|---|---|---|---|
| Cross-worktree scope | No — locks a per-file path | **Yes** — `_session_state_root()` anchors to `git rev-parse --git-common-dir` | session-state |
| Bounded timeout | `flock -w 5` | `flock -w "$timeout_s"`, caller-supplied | session-state (5 s is far too short for a suite) |
| Kill switch | `SOLEUR_DISABLE_AGENT_TOKEN_TEE` | `SOLEUR_DISABLE_SESSION_STATE` | either |
| Fails open on missing `flock(1)` | n/a | **Yes** — `_session_state_require_flock` → 99 | session-state |
| Safe to source from a non-hook script | n/a | **Yes** — double-source guard at top | session-state |
| Writes holder metadata for announcement | No | **No** — opens + flocks, writes nothing | **neither** → use the Phase 1 sibling scan |

**Conclusion:** adopt `session-state.sh` wholesale for the lock; source the announcement from Phase 1's `/proc/<pid>/cwd` scan. **No new lock primitive, and no modification to the shared one.** This deletes an entire hand-rolled lock implementation from the plan's scope.

### Measured: `flock` auto-releases on holder death

Prescribing stale-holder detection would have been dead code. Probed with a validated positive control:

```
free lock          -> ACQUIRED   (control: proves the probe command is valid)
holder alive       -> BLOCKED
holder SIGKILLed   -> no fd holders remain -> ACQUIRED
```

The kernel releases an inode-bound `flock` once the last fd holder exits, including on `SIGKILL`. Phase 3.6 therefore *asserts* the property (AC5b) instead of defending against an unreachable state.

### Gate dispositions

- **Phase 4.4 precedent-diff:** applied above.
- **Phase 4.5 network-outage:** trigger words matched (`timeout` ×5, `ssh` ×1) but this is a **false-positive trigger** — the checklist is authoritative for L3→L7 *network* diagnosis, and this plan has no network hop at any layer: every mechanism is local process scheduling, filesystem capacity, and kernel advisory locking on one machine. The single `ssh` occurrence is the Observability section's *negative* assertion that no verification path uses SSH. No L3/L7 verification entries are owed. Telemetry deliberately **not** emitted — recording an `applied` event for a false-positive trigger would corrupt the weekly aggregate.
- **Phase 4.55 downtime/cutover:** no trigger — no host replace, no lock-taking DDL, no serving-surface restart.
- **Phase 4.6 user-brand impact / 4.7 observability / 4.8 PAT-shaped / 4.9 UI wireframe:** all pass; no halt fired.
- **#3689 wrapper-vs-hook check:** `grep -rlnE 'test-all' .claude/hooks/*.sh` matches only `.test.sh` fixtures, never a live PreToolUse hook — so no hook gate can be bypassed here. Moot in any case, since Phase 3.1 acquires the lock *inside* `test-all.sh` rather than wrapping it.

## Sharp Edges

- **A documented cause is a claim with an author and a date, not a fact.** Both halves of `work/SKILL.md`'s "known pair" were refuted in minutes by two mechanical checks — `git log -S` on the allegedly-colliding path, and a reachability grep over the runner's own suite globs. Neither required judgement. Run both before building on any recorded attribution.
- **Refute by mechanism, not by plausibility.** H1 was refuted because no suite *can* invoke the bootstrap (reachability), not because interleaving seemed unlikely. H3 was **not** promoted to "sole cause" despite strong support, because the deciding datum — a measured concurrent failure — has not been captured. State UNKNOWN when the discriminator is unavailable.
- **The entry count is not the occupancy.** 4 294 leaked entries hold 160 MB; **three** entries hold 3.1 GiB. A remediation aimed at the many small files would have recovered 4.5 % of the problem while feeling thorough. Sort by bytes before choosing what to reap.
- **A guard that warns is not a guard that guards.** `tmpfs-guard.sh` ran every five minutes throughout, with a high-usage branch that fired `logger`/`notify-send` and cleaned nothing outside its `.output` scope — which is how `/tmp` reached 86 % under active monitoring. When extending a guard, check whether its non-clean branch is load-bearing or merely reassuring.
- **Verify what consumes an artifact before you delete it.** `.scan-meta.json` looks like scratch state and is in fact GDPR Art. 32 evidence with a documented post-exit consumer. The `hr-verify-repo-capability-claim-before-assert` check turned a one-line "add the missing trap" into an age-reap — and prevented shipping a silent compliance regression.
- **A probe with no positive control will confidently answer the wrong question — and a wrong probe reads exactly like a real finding.** Establishing whether `flock` needs stale-holder detection took three attempts. Attempt 1 used `flock -w 1 -x -c true "$LOCK"`, which is malformed (`-c` consumes `true`, leaving `$LOCK` as a stray argument), so it failed for *usage* reasons and reported `BLOCKED` in **both** arms — a coherent-looking result that would have justified building stale detection. Attempt 2 chased a real but irrelevant confound (a child `sleep` inheriting fd 9). Only attempt 3, which first acquired a **known-free** lock to prove the probe command itself worked, produced the true answer. Any probe whose negative result would change the plan's design must carry a positive control that fails when the probe is broken; otherwise "it didn't work" and "the thing isn't true" are indistinguishable. This is the same class as the plan's own §Hypotheses discipline, turned on the plan author.
- **A `plan`-authored plan cannot verify its own runtime claims.** Every number in this plan was measured on this machine on 2026-07-22 and is reproducible with the commands shown. Numbers will drift; re-measure before treating any of them as current.

---

## Test Scenarios

A new `.test.sh` covering the lock's decision arms, registered by an explicit `run_suite` line (AC10):

1. **Lock acquired when free** — a single run acquires and releases cleanly. Include a **positive control** that the probe command itself is valid against a free lock; without it, a malformed invocation reads as "blocked" (see Sharp Edges — this bit the plan author twice).
2. **Sibling announced** — with a synthesized live holder, the waiter prints the holder's worktree path and pid, sourced from the Phase 1 scan (not from the lock file).
3. **Advisory timeout proceeds** — a held lock past the timeout yields a **successful** run plus the banner, never an abort (AC4).
4. **Kill switch honoured** — `SOLEUR_DISABLE_SESSION_STATE=1` skips acquisition entirely (AC3).
5. **CI exempt** — with `CI` set, no acquisition occurs (AC5).
6. **Kernel release after SIGKILL** — the next acquisition succeeds with no stale-detection path (AC5b).
7. **Mutation control** — each arm must be shown to FAIL when its guard is removed. An arm that passes against a gutted implementation is asserting nothing.

Fixtures are synthesized (`cq-test-fixtures-synthesized-only`) — no real session pids, no live worktrees, no writes outside the test's own temp dir. Per the runner's own authoring guidance, avoid `producer | grep -q` under `pipefail` (SIGPIPE 141 on an early match flakes to a false negative); grep a file directly or use `grep -Ec`.
