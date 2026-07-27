<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  ACK JUSTIFICATION (Phase 2.8 reviewed): this plan introduces NO infrastructure.
  It trips iac-plan-write-guard.sh only because it must QUOTE that guard's own
  detection regexes and the shell commands they match. Every occurrence of an
  operator-SSH / systemd / secret-write / crontab literal below is a citation of
  a pattern under repair, never a prescribed step. See "Infrastructure (IaC)".
-->
---
title: "fix: guard hygiene — iac-guard MultiEdit bypass + Edit-scope ack blindness, live SIGPIPE sites, and tmpfs-guard reaper/alarm/telemetry"
date: 2026-07-27
type: fix
lane: cross-domain
branch: feat-one-shot-6992-iac-guard-sigpipe-fail-open
closes: [6992, 6991]
brand_survival_threshold: none
requires_cpo_signoff: false
revision: v2 (post plan-review — 3 P0 and 4 P1 findings applied; see Plan Review Revisions)
---

# Guard hygiene: two guards that reported success while doing nothing

## Overview

Two shell-script guards, both surfaced by the 2026-07-27 `/tmp` tmpfs incident, both
defence-in-depth layers that were silently non-functional while reading as healthy.

- **#6992** — `.claude/hooks/iac-plan-write-guard.sh`, reported to fail OPEN on every policy
  check via a `pipefail` + `grep -q` SIGPIPE race.
- **#6991** — `scripts/tmpfs-guard.sh`: cannot see a count-shaped leak, its alarm fires into
  channels nobody reads, and its telemetry is 99% its own test noise.

**Planning materially changed both diagnoses, and plan-review then falsified three of v1's own
load-bearing claims.** The evidence is in "Research Reconciliation" (issue claims) and "Plan
Review Revisions" (v1's claims). Read both before implementing — several fixes that look
obvious are measurably wrong.

Headline corrections:

- The SIGPIPE mechanism **does not apply** to the file #6992 names (bash builtin producers
  cannot raise it). The real defects there are an **Edit-scope blindness** and — found at
  review — a **complete MultiEdit bypass** that is a larger, unreported fail-open than the one
  the issue filed.
- Dropping `SCRATCH_MIN_MB`, which v1 argued was safe, would have **deleted a live Chrome IPC
  socket directory**. Measured, not theorised. The floor is load-bearing in a way nobody had
  noticed.

Unifying theme and acceptance bar: **a guard that reports success while doing nothing is worse
than no guard.** Every fix below is judged against whether its own failure would be visible.

---

## Research Reconciliation — Issue Claims vs. Measured Reality

Measured 2026-07-27 on the target host (bash 5.3.9, GNU grep 3.12, `pipe-max-size` 1048576).
Phase 0 re-runs each probe so no verdict rots between planning and implementation.

| # | Claim (issue / prior art) | Measured reality | Plan response |
|---|---|---|---|
| R1 | "Every check in `iac-plan-write-guard.sh` fails open via a `pipefail`+`grep -q` SIGPIPE race." | **REFUTED for this file, by measurement.** All 7 checks use `echo "$content"` — a **bash builtin**. Builtin producers never raise the race: `echo`/`printf` into `grep -q`, match-at-top, measured **0/40 failures at 4/16/50/64/128/1024 KB**; `PIPESTATUS` `0 0` at 1 MB. Bash handles EPIPE for its own builtins. | Convert the 7 sites anyway (cheap, matches repo canon in `plugins/soleur/skills/work/SKILL.md`), billed honestly as **shape hygiene, not the bug fix**. |
| R2 | End-to-end the guard fails open on forbidden content. | **REFUTED.** Real hook, 50 KB body: violation → `deny 12/12`; clean → `allow 12/12`; clean+ack → `allow 12/12`; violation+ack → `allow 12/12`. Zero flakes. | No change needed on the `Write` path. |
| R3 | "The ack reads as absent — ~9 deny / 3 allow on byte-identical 50 KB input." | **SYMPTOM CONFIRMED; CAUSE DIFFERENT, and deterministic.** The guard scans `.tool_input.content // .tool_input.new_string`. On an **`Edit`** that is the **replacement chunk only**. Measured: ack outside the chunk → deny; ack inside → allow. An author editing successive regions of one acked plan sees an apparently random split on "identical" input. | **The real #6992 defect.** Fixed in Phase 2 by the narrow ack lookup, not by whole-document rescanning (see PR-2). |
| R4 | (Corollary nobody filed.) | Edit-scope blindness is also a fail-open: a violation already in a plan is invisible to later edits. | Partially closed by Phase 2; the general form is deferred with a tracking issue — the full fix (delta scanning) has a measured 274-file blast radius (PR-2). |
| R5 | "The SIGPIPE race is the defect class; sweep siblings." | **CONFIRMED — but the discriminating axis is producer class, not input size, and no prior artifact says so.** External producers race **non-deterministically at every size**: `cat \| grep -q` match-at-top failed **3/20 at 1 KB**, 13/20 at 32 KB, 4/20 at 64 KB, 3/20 at 128 KB. `yes \| grep -q y` → `141 0`, 3/3. Match-at-**bottom** → 0/20. | Re-triage the sweep on **producer class**; fix external-producer sites (the live bugs); treat builtin sites as inert-but-wrong-shaped. Cuts the work from ~95 sites to ~8 live ones. |
| R6 | Sweep scope `.claude/hooks/*.sh` + `scripts/*.sh`. | Under-reaches: ~135 in-scope hits across `.claude/hooks/`, `scripts/`, `plugins/`, ~95 non-test. Every non-test in-scope file with a `set` line sets `pipefail`. | Phase 1 sweeps the wider scope and records producer class + direction. |
| R7 | Prior art documents the class. | Confirmed and **already canonicalised** in `work/SKILL.md`, with verbatim warnings in `.claude/hooks/pre-merge-rebase.test.sh` and `.claude/hooks/pre-merge-auto-close-scan.test.sh`. | The rule exists; enforcement does not. Phase 5 (reduced) closes the gap and corrects the rule to name the producer-class distinction. |
| R8 | **(Test-methodology hazard, newly found.)** | The interactive Bash tool resolves `grep` to a Claude Code **`ugrep` shim shell function**, and **ugrep `-q` drains its input** — the race is invisible to anyone testing by hand in an agent session. Hooks and cron get `/usr/bin/grep` (GNU 3.12), where it is live. | **Tests must pin the grep binary** (clean `PATH=/usr/bin:/bin`, `--noprofile --norc`) or pass vacuously. Explicit AC. Likely explains why the class survived prior reviews. |
| R9 | "`scripts/lib/scratch-root.sh` already exists — build on it." | **REFUTED.** `soleur_scratch_root()` has **zero production callers**; its only invoker is its own test file, which is registered in no runner. It landed in the previous commit (`a5160b29a`) and was never wired. | "Per-run private scratch roots reaped by their owner" has nothing to key on. Out of scope; deferred with a tracking issue. |
| R10 | "`tmp.` is the default template — 576 bare call sites." | **CONFIRMED, and worse.** Command-position `$(mktemp …)`: **1013 total, 856 bare (84.5%)**. Only 48 use `-t <prefix>`, and **all 48 prefixes are unique**. "576" was a *file* count (`git grep -l` → 587). | **Prefix-based leak signatures are not viable.** Phase 6 keys on nothing name-derived. |
| R11 | "The alarm must reach a `SOLEUR_*` marker → Better Stack, and/or Sentry." | **NOT REACHABLE AS SPECIFIED.** (a) `SOLEUR_*` is a **journald** convention consumed by **Vector**, whose `include_matches.SYSLOG_IDENTIFIER` is an **exact-value allowlist of 14 tags** excluding `tmpfs-guard`. (b) **Vector is not installed on this host.** (c) No Sentry DSN is wired into any locally-executing shell script. (d) `doppler` is at `~/.local/bin` — off cron's `PATH`. (e) `gh` is at `/usr/bin/gh` but authenticates via the **OS keyring**, unavailable under cron. | No local-cron → remote-observability path exists, and inventing one is out of scope (C2). Phase 7 routes to the surface that provably reaches the operator. |
| R12 | (Constraint nobody flagged.) | `iac-plan-write-guard.sh` **denies** plan text matching crontab-edit patterns, and `plan/SKILL.md` bans crontab steps. There is **no installer** — the live cron line was hand-installed, recorded only in a learning file. | **No crontab change may be prescribed.** Every Part-B fix must be a drop-in at the existing path (C1). |
| R13 | "Doc claims keyed on per-entry reap detail are unverifiable." | **CONFIRMED and broader** — false claims in two merged plans and, most seriously, in `plugins/soleur/skills/work/SKILL.md`, which is **agent instruction loaded every session**. | Phase 9 corrects the session-loaded claim. The historical-plan corrections were cut at review as ceremony. |

### Issue disposition

Neither issue closes as invalid. **#6992**'s symptom is real and reproducible; its stated cause
is not. The plan fixes the actual cause, performs the requested sweep on a better axis, fixes
the genuinely live race sites, adds the requested regression test, and closes a larger
bypass the issue never knew about. **#6991**'s four defects are all confirmed; two of its
suggested directions are blocked by measured facts it could not have known, and the plan states
the blockers rather than prescribing a path that does not exist.

---

## Plan Review Revisions (v1 → v2)

Plan-review falsified three v1 claims by direct measurement. Recorded in full because two of
them would have shipped active harm, and because the *pattern* — a plan refuting the issue's
assumptions and then confidently substituting its own — is the lesson.

| ID | v1 claim | Measured refutation | v2 response |
|---|---|---|---|
| **PR-1** | *"`SCRATCH_MIN_MB` is a cost gate, not a safety gate. Removing it costs no safety at all."* | **FALSE, and dangerous.** Reviewer ran all four surviving gates by hand against `/tmp/com.google.Chrome.mhBY3H`, which holds `SingletonSocket` for a **live** Chrome: ownership ✓, top-level age ✓, recursive age ✓ (tree entirely stale), denylist ✓ (`com.google.Chrome.*` matches nothing), symlink ✓, liveness ✓ (**0 hits**). It would have been deleted. Root cause: `_build_inuse_top` works by `readlink` on `/proc/<pid>/fd/*`, and **a unix-domain socket fd readlinks to `socket:[inode]`, never to its path** — the scan is architecturally blind to socket-held directories, and `fuser` is skipped for directories. | **The size floor is load-bearing** — it is the only thing excluding the entire small-entry population, which is where sockets, locks, and IPC dirs live. Phase 6 now **reduces** the floor rather than removing it, and first **fixes the liveness blindness** (`/proc/net/unix`, `fuser` on directories, widened denylist). |
| **PR-2** | *"On `Edit`, reconstruct the post-edit document and scan the result."* | **Would brick 274 files.** Across live plan/spec files: 4194 total, 357 contain a violation, 172 contain the ack, **274 contain a violation and no ack** — every one denied on every future edit. It silently converts policy from "did this edit introduce a violation?" to "does the document contain one?", retroactively. Trains authors to paste the ack reflexively, destroying the escape hatch. | **Narrow the fix.** Phase 2 now does an **ack lookup against the on-disk file** (two lines; closes R3 completely) plus the MultiEdit matcher fix. Whole-document delta scanning is recorded as the considered alternative and deferred with a tracking issue. |
| **PR-3** | *"The pressure arm skips `du`, so it is cheaper than the normal tier."* | **Inverted ~100x.** `du` runs over the **entire** candidate set *before* the floor is applied by `awk` — the floor never bounded `du`. What it bounds is the **per-candidate recursive `find`**. Measured on this host (17,898 top-level uid-owned entries): batched `du` = **0.76 s** for 4,841 entries (~2.8 s extrapolated); per-candidate `find` = **5.29 s** for 300 entries (**~316 s ≈ 5.3 min** extrapolated) — exceeding the entire cron interval, at 29% usage. | **Keep the batched `du`**; batch the recursive-age pass the same way (one `find … -printf` over the root, not 17,898 forks). Add `flock` — the guard has none today, so overlapping runs would race each other's deletes. |
| **PR-4** | *"Trigger the pressure tier on `df -i` inode usage."* | **Would never fire.** On a host *currently carrying the leak*: `df -h /tmp` → 29%, `df -i /tmp` → **7%** (268,438 of 3,992,059). tmpfs charges a full page per file, so blocks exhaust long before inodes can. The tier would sit disengaged through exactly the scenario it exists for — shipping a second guard that reports success while doing nothing. | Trigger on the **count-shaped signal directly**: top-level entry count under `$TMP_ROOT`. One `find \| wc -l`. Threshold pinned against measured current state so engagement is proven. |
| **PR-5** | *(v1 missed entirely.)* | **The guard is bypassed by MultiEdit today, unconditionally.** `.claude/settings.json` registers this hook with matcher `Write\|Edit`, while three sibling hooks in the same file use `Write\|Edit\|MultiEdit\|NotebookEdit`; the hook's own `case` also allows anything else. **Any plan written via MultiEdit skips the IaC guard entirely.** | **Folded into Phase 2 and promoted to the headline fail-open.** This is a larger hole than the one #6992 filed. |
| **PR-6** | *"The multi-line `-eq` raises a syntax error every 5 minutes."* | **Understated — it is a hard abort.** Under `set -euo pipefail`, `[[ "tmpfs-guard: reaping …\n1" -eq 0 ]]` parses `tmpfs` as a variable name; `set -u` makes it fatal. `main` exits 1 and **the high-usage alarm branch never executes** — and only on a run that reaped something while usage ≥ 70%, i.e. exactly the run that matters. | Severity corrected in Phase 8 and in AC-B7. Return contract changed from "stdout carries the count" to **globals** — a stray `echo` can then never break arithmetic again. |
| **PR-7** | *v1 Part B order 6 → 7 → 8.* | **Inverted.** Phase 6's ceiling (iv) and its tests both consume `guard_log()` and the usage-probe seam, which are Phase 8. Shipping 6 before 8 also *regresses production*: new per-entry logging lands in `reaped` and triggers the PR-6 hard abort. | **Part B reordered 8 → 6 → 7.** |
| **PR-8** | *v1 Phase 5: a lint script + ~95-entry allowlist.* | ~250 lines of permanent CI infrastructure whose day-one allowlist grandfathers ~95 entries and therefore asserts nothing, policing a class the same plan measures at near-zero live yield. | **Reduced** to a plain checked-in sweep record plus a minimal assertion in the existing runner. The full lint is deferred to its own issue. |
| **PR-9** | *v1 Phase 7's third tier: agent files a deduped GitHub issue at a threshold.* | Not a mechanism — agent behaviour, no code, no named threshold, no dedupe key, no AC. A channel that would report success while reaching no one. | **Cut.** State file + existing SessionStart hook only. `notify-send` deleted outright rather than kept as a hedge. |
| **PR-10** | *v1 AC set (18 ACs).* | Several unverifiable, tautological, or restating phase instructions. | Rewritten per the table in Acceptance Criteria. |

**Dissent recorded, not applied:** plan-review recommended **splitting into two PRs**. The
directive for this work is one PR closing both issues, so the plan keeps the single-PR shape.
The reviewer's reasoning is sound (no shared file, mechanism, test, or failure mode) and is
persisted to `decision-challenges.md` for the operator rather than silently discarded.

---

## Hypotheses

Every verdict rests on a measurement, not on reasoning. Phase 0 re-runs each probe.

| ID | Hypothesis | Verdict | Discriminator |
|---|---|---|---|
| H1 | The 7 `iac-plan-write-guard.sh` checks fail open via SIGPIPE. | **REFUTED** | Builtin producer 0/40 at six sizes to 1 MB; hook 12/12 correct on 5 arms. |
| H2 | The ack check fails closed via SIGPIPE. | **REFUTED** | Ack arm allowed 12/12 on a 50 KB `Write`. |
| H3 | The ack fails closed because `Edit` scans only `new_string`. | **CONFIRMED** | Ack-outside-chunk → deny; ack-inside → allow. Deterministic. |
| H4 | The SIGPIPE race is real somewhere in the swept set. | **CONFIRMED** | `yes` 3/3 at `141`; `cat` 3–13/20 across 1 KB–128 KB. |
| H5 | The race is gated on input size (>64 KiB pipe buffer). | **REFUTED** | Fires at **1 KB**. A genuine writer-exit/reader-close race, not a buffer threshold. |
| H6 | Reduced pipe capacity under `pipe-user-pages-soft` explains sub-64 KB firing. | **NOT NEEDED** | H5 explains it without invoking pressure. Recorded so it is not re-derived. |
| H7 | Ownership + age + liveness + denylist suffice without a size floor. | **REFUTED** | A live Chrome IPC socket directory clears all four (PR-1). |
| H8 | `df -i` is a usable count-pressure trigger on tmpfs. | **REFUTED** | 7% inodes at 17,898 leaked entries (PR-4). |
| H9 | The guard is reachable only via `Write` and `Edit`. | **REFUTED** | `MultiEdit` bypasses it entirely (PR-5). |

**Network-outage checklist (Phase 1.4 / 4.5):** evaluated, **does not apply**. Trigger words
occur only as quoted detection regexes belonging to the guard under repair. No network path,
host, or connectivity failure is in scope.

---

## User-Brand Impact

**If this lands broken, the user experiences:** their machine wedging again — `/tmp` fills,
agent sessions cannot write tool output, work in progress is lost — with a janitor and alarm
that still report healthy. In the worst v1 shape, *the fix itself* would have deleted a live
browser's IPC socket, killing a running application mid-session (PR-1). Secondarily, a plan
carrying a real manual-infrastructure step ships unchallenged via the MultiEdit bypass.

**If this leaks, the user's data is exposed via:** nothing. Both scripts are local, read no
user content, and transmit nothing. The plan deliberately does **not** add a network egress
path from the laptop (R11/C2) — doing so would *create* a data-egress surface where none
exists, which `.claude/hooks/README.md` §"External-observability boundary" rules out pending
DPA review.

**Brand-survival threshold:** `none`. Developer-workstation tooling, no customer-facing
surface, no user data, no production blast radius. No file in "Files to Edit" matches the
sensitive-path regex, so no scope-out bullet is required; `requires_cpo_signoff: false` and
`user-impact-reviewer` is not invoked.

---

## Constraints

- **C1 — No crontab change.** Drop-in replacement at the existing path; no installer exists and
  Part A's guard denies plan text prescribing crontab edits (R12).
- **C2 — No new local→remote egress** (R11 + the standing DPA boundary).
- **C3 — Cron `PATH` is `/usr/bin:/bin`.** `doppler` unreachable; `gh` resolves but its keyring
  auth does not survive cron. Part B may rely on neither.
- **C4 — Tests must pin the `grep` binary** (R8) or pass vacuously in an agent session.
- **C5 — No unbounded per-candidate work.** Any pass over `/tmp` candidates must be batched;
  the 5-minute cron interval is a hard ceiling (PR-3).
- **C6 — Planning touches only `knowledge-base/project/{plans,specs}/`.**

---

## Implementation Phases

### Phase 0 — Re-verify premises (blocking, no edits)

Re-run and paste output into the spec evidence block. A verdict that no longer reproduces halts
the phase it justifies.

0.1 **Producer class**, clean shell (`env -i PATH=/usr/bin:/bin bash --noprofile --norc`):
assert `grep` is `/usr/bin/grep` (GNU); builtin `echo` → 0 failures at 1 MB; `yes | grep -q y`
→ `PIPESTATUS 141 0`; `cat` of a 1 KB file, match-at-top → non-zero failures over 20 runs.
0.2 **Edit-scope**: ack outside chunk → deny; ack inside → allow.
0.3 **MultiEdit bypass**: confirm `.claude/settings.json`'s matcher for this hook lacks
`MultiEdit` while sibling hooks include it (PR-5).
0.4 **Socket liveness blindness**: pick a live socket-holding directory under `/tmp`; confirm it
clears ownership, recursive age, denylist, and `_INUSE_TOP` liveness (PR-1). **If this no longer
reproduces, Phase 6's ordering assumption changes — do not skip.**
0.5 **Cost model**: time batched `du --files0-from` vs per-candidate recursive `find` over the
current candidate set; confirm the per-candidate form extrapolates past the cron interval (PR-3).
0.6 **Trigger signal**: record `df -h /tmp`, `df -i /tmp`, and the top-level entry count.
Confirm inode % is far below any plausible high-water mark (PR-4).

**Gate:** if 0.1, 0.2, or 0.4 fails to reproduce, stop and re-diagnose.

---

### Part A — issue #6992

### Phase 1 — Sweep and record (AC-A3)

Sweep `git grep -nE '\|[[:space:]]*grep[[:space:]]+-q'` over `.claude/hooks/`, `scripts/`, and
`plugins/` — wider than the issue's glob (R6). Record per non-test hit: file:line, `pipefail`
status, **producer class (builtin vs external)**, provenance, failure direction, live/inert.

Direction taxonomy — the third form is the subtle one and must be flagged wherever it appears:

| Shape | On race | Direction |
|---|---|---|
| `X \| grep -q P && deny` | `deny` skipped | **FAILS OPEN** |
| `if X \| grep -q P; then allow` | bypass skipped | fails closed |
| `if ! X \| grep -q P; then <early-exit>` | `!` inverts the false negative → early-exit fires → **the gate skips its own check** | **FAILS OPEN** |

Deliverable: `knowledge-base/project/specs/<branch>/sweep.md`.

### Phase 1.5 — Land the failing tests RED (before Phase 2)

Per `cq-write-failing-tests-before` and AC-A4, T3/T4 must exist and fail against unmodified
code, demonstrated at that commit. Writing them after the fix cannot prove RED→GREEN.

### Phase 2 — Fix the real #6992 defects — **load-bearing**

Two changes, both narrow. v1's whole-document reconstruction is **not** taken (PR-2).

- **2a — Close the MultiEdit bypass (PR-5).** Add `MultiEdit` to this hook's matcher in
  `.claude/settings.json` (matching its three siblings) and to the hook's own `tool_name` case.
  Fold `edits[]` into the scanned text. This is the largest fail-open in Part A and was not in
  the issue.
- **2b — Find the ack wherever it lives (R3).** Check the ack literal against the `new_string`
  **and** against the on-disk file. Two lines; closes the reported symptom completely, with
  zero retroactive blast radius:

  ```bash
  ack='<!-- iac-routing-ack: plan-phase-2-8-reviewed -->'
  if grep -qF "$ack" <<<"$content" \
     || { [ -f "$file_path" ] && grep -qF "$ack" "$file_path"; }; then
  ```

  Resolve a relative `file_path` against the hook's existing `PROJECT_DIR`, and guard the read
  so a failure cannot trip `set -e` and change the hook's "exit 0 always" contract.
- **Not taken:** whole-document delta scanning (compare pre/post match counts, deny only on an
  *increase*). It is the correct general fix for R4 and elegantly satisfies AC-A1 via `grep -c`,
  but it needs `replace_all` handling, a glob-safe substitution (unquoted `${doc/$old/$new}`
  treats `*`, `?`, `[` as globs and silently returns the document **unchanged** — a silent
  fail-open), and MultiEdit sequencing. Deferred with a tracking issue rather than rushed into
  a bug-fix PR.
- Correct the header's "Hook exit code: 0 always" comment against the final control flow.

### Phase 3 — Fix the genuinely live race sites

Convert **external-producer** sites (`cat`, `git show`, `git log`, `git diff`, `base64 -d`,
`jq`, `awk`, and wrappers around them):

- Value already in a variable → `grep -q P <<<"$var"`.
- True command producer → capture first, or `[ "$(cmd | grep -c P || true)" -gt 0 ]`.
- Never `grep -qo` — `-q` wins over `-o` and still early-exits.

Live set from the sweep (Phase 1 finalises): `.claude/hooks/pre-merge-rebase.sh`,
`.claude/hooks/brand-hex-commit-gate.sh`, `.claude/hooks/skill-security-scan.sh`,
`.claude/hooks/skill-context-queries.sh`, `scripts/update-ci-required-ruleset.sh`,
`scripts/create-ci-required-ruleset.sh`, `scripts/watch-live-verify-pass.sh`,
`plugins/soleur/skills/review/scripts/emit-review-trailer.sh`.

Also convert the 7 builtin sites in `iac-plan-write-guard.sh` (inert per R1, but wrong-shaped
and the file is the issue's subject) — satisfies AC-A1. **Surrounding control flow stays
unchanged at every site**; each touched hook's existing test suite must pass untouched.

### Phase 4 — Regression tests (AC-A2, AC-A4..A6)

- **T1** (the AC's test) — ≥64 KB body, violation near the top → `deny` on every one of ≥30
  runs. *Annotate: issue-requested; passes pre- and post-fix per R1/R2, so it verifies
  no-regression, not the fix.*
- **T2** — same body + ack → `allow` on ≥30 runs.
- **T3** (RED anchor, from Phase 1.5) — `Edit`, violation in `new_string`, ack elsewhere in the
  file → `allow`.
- **T4** — MultiEdit carrying a violation → `deny` (fails before 2a, passes after).
- **T5** (C4/R8 vacuity guard) — assert `grep` resolves to a GNU grep **binary**, not a shell
  function; abort loudly otherwise.
- **T6** — producer-class behaviour: `cat | grep -q` can fail, `echo | grep -q` does not. This
  is the single executable home for that measurement (Phase 0.1 is the pre-flight; do not also
  restate it as prose elsewhere).

### Phase 5 — Record and nudge (reduced from v1 per PR-8)

- Commit `sweep.md` as the AC-A3 record.
- Add a **minimal assertion** to the existing `scripts/test-all.sh` surface that the
  external-producer count does not grow beyond the recorded baseline. No new script, no
  bespoke allowlist format.
- Correct the `work/SKILL.md` rule text to name the **producer-class distinction** (R5) — the
  current wording sends reviewers hunting inert builtin sites while live external ones pass.
- **Deferred:** the full lint + per-site allowlist, as its own issue.

---

### Part B — issue #6991 — order is 8 → 6 → 7 (PR-7)

### Phase 8 — Log sink, telemetry, return contract (AC-B5..B8) — **first**

Phase 6 consumes `guard_log()` and the usage seam, and shipping 6 first actively regresses
production (PR-6/PR-7).

- **`guard_log()` + `TMPFS_GUARD_LOG_SINK` seam** (default `logger`), replacing all three
  hard-coded `logger -t tmpfs-guard` sites. Tests point it at a fixture-scoped file under their
  own `TESTROOT`, so the suite stops writing to the operator's journal (AC-B5). This is the only
  seam class not already present — every existing seam is a path or a numeric floor, and
  `logger` writes to a socket no path seam can redirect.
- **`echo` → `guard_log`** for per-entry reap detail (live and `DRY_RUN`) — the journal gains the
  `reaping <path> (<N> MB)` lines several docs already claim exist (AC-B4a, R13).
- **Return contract → globals, not stdout** (PR-6). `reap_scratch_entries` and
  `reap_output_files` set `REAP_COUNT` / `REAP_MB` and `return 0`; `main` reads the globals and
  drops the command substitution entirely. This removes the subshell, the parsing, and the need
  for a sanitize — a stray `echo` can never again break arithmetic. If any sanitize survives it
  must **log loudly**, never silently default to 0.
- **Severity note for the implementer:** the current bug is a **hard abort**, not a warning —
  `set -u` makes the multi-line arithmetic fatal, `main` exits 1, and the high-usage alarm
  branch never runs, precisely on a high-usage run that reaped something.
- **Per-run liveness line** so "silent" and "not running" become distinguishable.
- **Hermetic usage probe** — the suite currently runs `df` against a `TESTROOT` on the real
  `/tmp` and so branches on live production state; put it behind a seam.
- **`flock`** — the guard has none (PR-3); overlapping runs would race each other's deletes.

### Phase 6 — A reaper that can see a count-shaped leak, safely (AC-B1..B3)

**Design first.** The reviewed direction (per-run private scratch roots) is unavailable (R9),
and prefix signatures are forbidden and unviable (R10). v1's answer — drop the size floor — is
**refuted** (PR-1). The corrected design has a hard prerequisite.

**6a — Fix the liveness blindness FIRST. Nothing else in Phase 6 may land before this.**
`_build_inuse_top` sees only paths reachable by `readlink` on `/proc/<pid>/fd/*`, and a
unix-domain socket fd readlinks to `socket:[inode]` — so socket-held directories are invisible,
and `fuser` is skipped for directories entirely. Three changes:

1. Parse **`/proc/net/unix`** (which carries the filesystem path) into the same `_INUSE_TOP`
   map. One file read — cheaper than the existing fd walk.
2. Run `fuser` on directories too (drop the `[[ ! -d ]]` gate).
3. Widen the protected denylist to the non-scratch classes empirically present in `/tmp`:
   `com.google.Chrome.*`, `.org.chromium.*`, `dbus-*`, `pulse-*`, `.mount_*`, `tmux-*`, `ssh-*`,
   `.X*-lock`. Re-review against a live `/tmp` listing rather than assuming the current
   9-entry list is complete.

Also correct the SAFETY header's "no open file handle" claim, which is currently overstated.

**6b — Reduce the floor; do not remove it.** Keep a small size floor (order 1 MB) under
pressure. Sockets and lockfiles are ~0 bytes, so even a tiny floor preserves the accidental
protection PR-1 exposed while still catching the 15,000 × 372-byte class. Removing it outright
is not justified by any acceptance criterion.

**6c — Trigger on the count-shaped signal directly** (PR-4). `df -i` on tmpfs is dead as a
trigger (7% at 17,898 entries). Use the **top-level entry count** under `$TMP_ROOT` — one
`find | wc -l`. Pin the threshold against the measured current state so engagement is proven,
not assumed.

**6d — Keep work batched** (PR-3/C5). Retain the batched `du --files0-from` (it is ~2.8 s at
full scale and it supplies the `size_mb` that the per-entry log lines and `reaped_mb` accounting
require — v1's design silently lost both). Batch the recursive-age check the same way: one
`find "$TMP_ROOT" -mindepth 1 -mmin -N -printf '%H\n' | sort -u` pass yields the fresh-tree set
in one process instead of ~17,900 forks.

**6e — Ceilings on the age relaxation.** The lowered age floor is the only genuine defense
relaxation; it is bounded by: (i) it runs only under measured count pressure; (ii) ownership and
liveness are never relaxed — **and 6a is what makes that claim true**; (iii) a per-run cap on
entries reaped; (iv) every pressure reap is logged individually via `guard_log`.

Deletion keeps `find … -delete` (never `rm -rf`) — a survivor may be a `.git`-bearing checkout.

### Phase 7 — An alarm that reaches a human (AC-B4)

The specified route is unavailable (R11). Naming that honestly is required: prescribing a
`SOLEUR_*` → Better Stack marker here would produce a *second* alarm reaching no one.

- Append to a durable, size-capped alarm state file at a fixed path **outside `/tmp`** (an alarm
  store on the mount being reaped is self-defeating): timestamp, usage %, entry count, reap counts.
- Surface a one-line summary at `SessionStart` by extending the **existing** hook. No network, no
  credentials, no `PATH` assumptions. **Emit nothing when the state file records zero alarms** —
  a healthy machine must not tax every session's context.
- **Delete `notify-send`** from all three call sites. It is a no-op under cron and keeping it as
  a "best-effort extra" is how the current dead channel came to exist.
- **Not taken (PR-9):** threshold-triggered agent-filed GitHub issues. No named threshold, no
  dedupe key, no code, no AC — agent behaviour dressed as a channel.

### Phase 9 — Correct the session-loaded doc claim (AC-B10)

`plugins/soleur/skills/work/SKILL.md` claims the cron reaper "bounds the abandoned-scratch
growth". It is **loaded into every agent session** and is false for the count-shaped class.

*Cut at review as ceremony:* corrections to the merged 2026-07-27 and 2026-07-22 plan documents.
Historical plans record what was planned; nobody re-runs their ACs.

### Phase 10 — Verify, capture, ship

Full suite; learning file; deferred tracking issues; PR body closing both.

---

## Files to Edit

**Part A** — `.claude/hooks/iac-plan-write-guard.sh` (2a/2b + 7 herestrings + header);
`.claude/settings.json` (MultiEdit matcher); `.claude/hooks/iac-plan-write-guard.test.sh`
(T1–T6); the eight external-producer sites listed in Phase 3;
`plugins/soleur/skills/work/SKILL.md` (producer-class correction); `scripts/test-all.sh`
(baseline assertion).

**Part B** — `scripts/tmpfs-guard.sh` (Phases 8, 6, 7); `scripts/tmpfs-guard.test.sh`;
the existing SessionStart hook under `.claude/hooks/`;
`plugins/soleur/skills/work/SKILL.md` (Phase 9 — note both parts touch this file).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-6992-iac-guard-sigpipe-fail-open/sweep.md`
- One learning file under `knowledge-base/project/learnings/` (directory + topic only; the
  author picks the date at write time).

---

## Acceptance Criteria

### Pre-merge (PR)

**Part A — #6992**
- [ ] **AC-A1** No check in `iac-plan-write-guard.sh` consumes `$content` through a pipe into
      `grep -q`; the sweep pattern returns 0 hits for that file.
- [ ] **AC-A2** A regression test drives the guard with a ≥64 KB body, match near the top, and
      asserts deny on **every one of ≥30** runs. *(Issue-requested; verifies no-regression, not
      the fix — see R1/R2.)*
- [ ] **AC-A3** `sweep.md` records file:line, **producer class**, and failure direction for every
      hit across `.claude/hooks/`, `scripts/`, `plugins/`.
- [ ] **AC-A4** T3 fails at the pre-Phase-2 commit and passes after, demonstrated at both.
- [ ] **AC-A5** A `MultiEdit` payload carrying a violation is denied; the hook's matcher in
      `.claude/settings.json` includes `MultiEdit`.
- [ ] **AC-A6** T5 aborts loudly when `grep` resolves to a shell function rather than a GNU grep
      binary — the suite cannot pass vacuously.
- [ ] **AC-A7** Every external-producer site in Phase 3 is converted, **and each touched hook's
      existing test suite passes unchanged** (the tests encode the control flow).
- [ ] **AC-A8** The `test-all.sh` baseline assertion fails when a new external-producer
      `| grep -q` is introduced.

**Part B — #6991**
- [ ] **AC-B1** The reaper engages on a **top-level entry-count** signal (not `df -i`, which
      measures 7% while the leak is present), and its behaviour is proven by AC-B3 rather than
      by grepping for absent prefix logic.
- [ ] **AC-B2** Liveness sees socket-held directories: a fixture directory held open only by a
      unix-domain socket is **not** reaped, in both normal and pressure modes. *(This is the
      PR-1 regression test; without it Phase 6 is unsafe.)*
- [ ] **AC-B3** A count-shaped leak (many tiny files, none near the old size floor) is reaped
      under simulated pressure and **not** reaped without it; a live (open-fd) tree, a
      socket-held tree, and a foreign-uid tree are never reaped in either mode; the per-run cap
      holds.
- [ ] **AC-B4** A pressure run over a ≥10,000-entry fixture completes **well inside the
      5-minute cron interval**, with the measured bound recorded. *(PR-3.)*
- [ ] **AC-B5** `tmpfs-guard.test.sh` writes nothing to the production journal: run the suite,
      confirm `journalctl -t tmpfs-guard` gained no lines.
- [ ] **AC-B6** Per-entry reap detail reaches the log sink, and the reaper functions return their
      count via globals — no command substitution remains in `main`.
- [ ] **AC-B7** On a run that reaps ≥1 entry with usage ≥ 70%, `main` exits 0 **and the
      high-usage branch is evaluated** (today it hard-aborts under `set -u`).
- [ ] **AC-B8** A healthy run emits a liveness line; a run with zero alarms injects nothing into
      SessionStart context.
- [ ] **AC-B9** The alarm state file is written on a pressure run, the size cap holds, and the
      SessionStart surfacing renders the summary.
- [ ] **AC-B10** `work/SKILL.md` no longer claims the cron reaper bounds abandoned-scratch growth.

**Cross-cutting**
- [ ] **AC-X1** PR body contains `Closes #6992` and `Closes #6991`.
- [ ] **AC-X2** `bash scripts/test-all.sh` passes.

### Post-merge (operator)

None. Both targets are drop-in replacements at existing paths (C1); the cron entry invokes the
same path and needs no re-installation. No infrastructure, secret, or vendor action.

---

## Open Code-Review Overlap

**None.** No open `code-review`-labelled issue names `iac-plan-write-guard.sh`,
`tmpfs-guard.sh`, or the Phase 3 sites. The two governing issues are `type/bug`. Recorded so the
next planner can see the check ran.

---

## Infrastructure (IaC)

**Not applicable — no infrastructure is introduced, changed, or provisioned.** Both targets are
existing local developer tooling; no server, systemd unit, DNS record, cert, secret, firewall
rule, vendor account, or webhook is created or modified, and no Terraform root is touched.

The Phase 2.8 detector fires on this document only because it must **quote the detection regexes
of the guard it repairs**. The ack at the top records that deliberate, audited opt-out.

- **No crontab change is prescribed** (C1/R12) — the fix replaces the file's contents in place.
- **No new egress path** is created (C2/R11), keeping this on the safe side of the standing
  external-observability boundary.

---

## Observability

```yaml
liveness_signal:
  what: "tmpfs-guard emits a per-run line via guard_log on EVERY run, healthy or not (Phase 8)"
  cadence: "every 5 minutes, unchanged"
  alert_target: "durable alarm state file -> SessionStart context injection -> operator's next agent session"
  configured_in: "scripts/tmpfs-guard.sh (guard_log + alarm state file); the existing SessionStart hook under .claude/hooks/"

error_reporting:
  destination: "alarm state file, read and rendered at SessionStart"
  fail_loud: true
  note: "Deliberately NOT logger-only and NOT notify-send. Measured (R11): Vector is absent on this host, tmpfs-guard is not in the vector.toml tag allowlist, no local Sentry DSN exists, doppler is off cron PATH, and gh keyring auth does not survive cron. The prior design counted two channels that reached nobody 94 times in 14 days. A threshold-triggered GitHub issue was considered and cut (PR-9) because it was agent behaviour with no code, threshold, or test behind it."

failure_modes:
  - mode: "cron entry stops firing entirely"
    detection: "the per-run liveness line stops appearing; its absence is meaningful now that a healthy run always emits one (Phase 8)"
    alert_route: "SessionStart surfacing reports staleness of the alarm state file"
  - mode: "/tmp fills with a count-shaped leak the reaper cannot reclaim"
    detection: "entry-count pressure trigger engages and logs per-entry reaps; a persistent streak with zero reaps is recorded in the alarm state file"
    alert_route: "SessionStart surfacing"
  - mode: "the reaper deletes a live socket-held directory"
    detection: "AC-B2 regression test; /proc/net/unix liveness pass plus fuser-on-directories (Phase 6a)"
    alert_route: "CI failure on scripts/test-all.sh"
  - mode: "a pressure run overruns the 5-minute cron interval and overlapping runs race deletes"
    detection: "AC-B4 wall-clock bound on a >=10,000-entry fixture; flock makes overlap impossible rather than merely unlikely"
    alert_route: "CI failure on scripts/test-all.sh"
  - mode: "a plan bypasses the IaC guard entirely via MultiEdit"
    detection: "AC-A5 asserts both the settings.json matcher and a denied MultiEdit payload"
    alert_route: "CI failure on scripts/test-all.sh"
  - mode: "iac-plan-write-guard denies a valid acked plan (the #6992 symptom)"
    detection: "T2/T3 regression tests"
    alert_route: "CI failure on scripts/test-all.sh"
  - mode: "a new external-producer `| grep -q` lands and silently disables a gate"
    detection: "the test-all.sh baseline assertion over the recorded sweep count"
    alert_route: "CI failure on scripts/test-all.sh"
  - mode: "the guard test suite passes vacuously because grep resolved to the ugrep shim"
    detection: "T5 asserts the resolved grep is a GNU grep binary, not a shell function"
    alert_route: "CI failure on scripts/test-all.sh"

logs:
  where: "systemd journal via logger -t tmpfs-guard (production); a fixture-scoped file under TESTROOT during tests (TMPFS_GUARD_LOG_SINK); the durable alarm state file for alarm events"
  retention: "journal per host defaults; alarm state file is size-capped by the guard"

discoverability_test:
  command: "bash scripts/tmpfs-guard.test.sh && bash .claude/hooks/iac-plan-write-guard.test.sh && bash scripts/test-all.sh"
  expected_output: "all suites pass; journalctl -t tmpfs-guard gains no lines attributable to the test run; the external-producer baseline assertion reports no growth"
```

No SSH in any verification command. Both surfaces are local and directly inspectable.

---

## Encryption Posture

**Not applicable — no persistent data store and no cross-component or network connection is
introduced.** Detection patterns (`.tf`, `supabase/migrations/*.sql`, `cloud-init*.yaml`,
`docker-compose*.yaml`) match nothing in "Files to Edit".

The one new artifact is the local alarm state file:

```yaml
at_rest:
  - store: "tmpfs-guard alarm state file (local, operator workstation)"
    mechanism: "none — plaintext on the operator's existing local filesystem; inherits whatever full-disk encryption the workstation already has"
    evidence: "content is limited to timestamps, usage percentages, entry counts, and reap counts (Phase 7)"
    defends_against: "nothing additional; it is not a security control"
    does_not_defend: "local disk theft or any local process reading the file — both already true of every other file on the workstation, and the file holds no user data, no secret, and no content"
    disclosed_as: "not disclosed — developer-workstation telemetry, never transmitted and never leaving the machine"
    live_verification: "read the file; confirm it contains only numeric counters and timestamps"
in_transit:
  - connection: "none — the file is never transmitted"
    tls: "n/a"
    cert_verification: "n/a"
    does_not_defend: "n/a — there is no connection; the plan explicitly declines to create one (C2/R11)"
    disclosed_as: "n/a"
```

---

## Architecture Decision (ADR/C4)

**No ADR required.** No ownership or tenancy boundary moves, no new substrate or integration
pattern, no resolver/dispatch/trust boundary change, and no existing ADR reversed or extended.
Both changes are bug fixes on existing local surfaces.

**C4 views — no impact.** All three model files (`model.c4`, `views.c4`, `spec.c4`) were reviewed
rather than keyword-grepped. Enumerated: (a) **external human actors** — none added; neither
guard receives from or emits to any party outside the operator; (b) **external systems/vendors**
— none added, and the plan explicitly *declines* a Better Stack or Sentry edge from the laptop
(R11/C2); (c) **containers/data stores** — none; the alarm state file is workstation scratch, not
a modelled container, and the laptop is not a modelled element; (d) **actor↔surface access
relationships** — unchanged. No element description is falsified.

---

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Both issues are `domain/engineering` (CTO); developer-tooling correctness with no
product, legal, financial, marketing, sales, support, or operations surface. Three risks carried
into v2: (1) **safety** — Phase 6 was actively dangerous in v1 and is now gated on the 6a
liveness fix landing first; (2) **cost** — the reaper's per-candidate walk must stay batched or
it overruns the cron interval; (3) **scope** — plan-review recommended splitting into two PRs,
which the single-PR directive overrides; the dissent is persisted rather than dropped.

### Product/UX Gate

Not applicable. Product domain not relevant and the mechanical UI-surface override does not fire —
no path in Files to Create/Edit matches any UI-surface glob. No wireframe required.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Phase 6 deletes live application state** (the v1 defect, PR-1). | 6a lands first and is a hard prerequisite: `/proc/net/unix` liveness, `fuser` on directories, widened denylist. The floor is reduced, not removed. AC-B2 is a dedicated regression test with a socket-held fixture. |
| **A pressure run overruns the 5-minute cron and overlapping runs race deletes** (PR-3). | Keep batched `du`; batch the recursive-age pass; add `flock`. AC-B4 pins a measured wall-clock bound on a ≥10,000-entry fixture. |
| **The pressure tier never engages** (PR-4). | Trigger on top-level entry count, not `df -i`. Threshold pinned against measured current state (17,898 entries at 29% blocks / 7% inodes). |
| **The denylist is incomplete** — removing/reducing the floor widens the candidate set by orders of magnitude, which is exactly when an unlisted name gets reaped. | 6a.3 re-reviews the denylist against a live `/tmp` listing rather than assuming the 9-entry list is complete. Stated as an assumption to test, not asserted away. |
| **Phase 2 makes 274 existing files un-editable** (the v1 design, PR-2). | Not taken. The narrow ack lookup has zero retroactive blast radius. |
| **The deferred delta-scan design is silently forgotten**, leaving R4 open. | Tracking issue filed at ship time, with the `replace_all` / glob-safety / MultiEdit-sequencing requirements recorded so the next attempt does not rediscover them. |
| **An unquoted bash substitution silently returns the document unchanged** (a fail-open) if the delta design is later attempted. | Recorded in Phase 2's "Not taken" note: use a literal-split (`jq … split/join`), never `${doc/$old/$new}`. |
| **Both parts edit `plugins/soleur/skills/work/SKILL.md`.** | Noted in Files to Edit; sequence the two edits or make them in one pass. |
| **Single PR spanning two unrelated issues** raises review surface. | Phase boundaries are strict and each part is independently revertible. Reviewer dissent recorded in `decision-challenges.md`. |
| **A later `Edit` to this plan file is denied** because the ack sits outside the edited chunk — the very bug under repair. | Known hazard. Re-`Write` the whole file rather than `Edit`ing it. First-hand evidence for T3. |

---

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Fix only the 7 `iac-plan-write-guard.sh` sites, as #6992 literally asks. | Measured inert (R1). Would close the issue while leaving the reported symptom live and the MultiEdit bypass wide open. |
| Convert all ~95 `\| grep -q` sites. | ~90% are builtin producers and provably cannot race. Large diff, near-zero defect yield. |
| Whole-document delta scanning on `Edit`. | Correct general fix for R4, but 274 live files would be denied on every edit (PR-2), and it needs `replace_all`, glob-safe substitution, and MultiEdit sequencing. Deferred with a tracking issue. |
| Close #6992 as invalid since its mechanism is refuted. | The 9/3 symptom is real and reproducible with a real cause (R3), and the investigation surfaced a larger bypass (PR-5). |
| Remove `SCRATCH_MIN_MB` outright (v1's design; also plan-review's simplification). | **Measured dangerous** — deletes live socket-held directories (PR-1). Reduced, not removed. |
| Per-run private scratch roots reaped by owner (the issue's reviewed direction). | `scratch-root.sh` has zero adopters and 84.5% of `mktemp` sites use the default template (R9/R10). Requires migrating hundreds of call sites. Deferred. |
| Count-based reaping keyed on the `tmp.` prefix. | Forbidden by the issue and confirmed unsafe — `tmp.` is the default at 856 sites (R10). |
| `SOLEUR_*` marker to `logger` + Vector tag allowlist. | Vector is not installed on this host (R11); the tag would be allowlisted on servers that never see this journal. A second alarm reaching nobody. |
| Cron job files a GitHub issue directly. | `gh` resolves under cron but authenticates via the OS keyring, unavailable to a cron session (R11/C3). Measured. |
| Store a `gh` token on disk so cron can authenticate. | Creates a durable workstation credential and a new egress path (C2) to solve what SessionStart solves with no credential. |
| A dedicated lint script + per-site allowlist (v1 Phase 5). | ~250 lines of permanent CI infrastructure whose day-one allowlist grandfathers ~95 entries and asserts nothing (PR-8). Reduced to a baseline assertion; full lint deferred. |

**Deferred — tracking issues required at ship time:**
1. Whole-document delta scanning for the guard (closes R4 generally).
2. Migrating bulk `mktemp` call sites onto `soleur_scratch_root()` (R9); also register
   `scripts/lib/scratch-root.test.sh`, currently in no runner.
3. The full external-producer `| grep -q` lint with a per-site allowlist (PR-8).

---

## Test Scenarios

1. **Producer class** — builtin `echo`/`printf` into `grep -q` never fails on match (≥40 runs,
   ≥1 MB); external `cat`/`yes` does fail on match-at-top; match-at-bottom never fails.
2. **Guard, `Write`** — violation → deny; clean → allow; clean+ack → allow; violation+ack →
   allow. ≥30 runs each on a ≥64 KB body.
3. **Guard, `Edit`** — ack elsewhere in the file → allow (RED before Phase 2).
4. **Guard, `MultiEdit`** — violation in any edit → deny (RED before Phase 2a).
5. **Vacuity guard** — harness aborts when `grep` is a shell function.
6. **Reaper safety** — a socket-held directory, an open-fd tree, and a foreign-uid tree are never
   reaped in either mode. A ~10,000-file count-shaped leak is reaped under pressure, untouched
   without it. Per-run cap holds. Wall clock well inside 5 minutes.
7. **Telemetry** — suite adds no lines to `journalctl -t tmpfs-guard`; per-entry detail lands in
   the fixture sink; no command substitution remains in `main`; a reaping run at ≥70% usage exits
   0 with the high-usage branch evaluated; a healthy run emits a liveness line.
8. **Alarm** — state file written on a pressure run, size cap holds, SessionStart renders the
   summary, and a zero-alarm state injects nothing.
