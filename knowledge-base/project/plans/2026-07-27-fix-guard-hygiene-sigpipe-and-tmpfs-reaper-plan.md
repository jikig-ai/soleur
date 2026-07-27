<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  ACK JUSTIFICATION (Phase 2.8 reviewed): this plan introduces NO infrastructure.
  It trips iac-plan-write-guard.sh only because it must QUOTE that guard's own
  detection regexes and the shell commands they match. Every occurrence of an
  operator-SSH / systemd / secret-write / crontab literal below is a citation of
  a pattern under repair, never a prescribed step. See "Infrastructure (IaC)".
-->
---
title: "fix: guard hygiene — SIGPIPE race at external-producer grep sites, iac-guard Edit-scope blindness, and tmpfs-guard reaper/alarm/telemetry"
date: 2026-07-27
type: fix
lane: cross-domain
branch: feat-one-shot-6992-iac-guard-sigpipe-fail-open
closes: [6992, 6991]
brand_survival_threshold: none
requires_cpo_signoff: false
---

# Guard hygiene: two guards that reported success while doing nothing

## Overview

Two shell-script guards, both surfaced by the 2026-07-27 `/tmp` tmpfs incident, both
defence-in-depth layers that were silently non-functional while reading as healthy.

- **#6992** — `.claude/hooks/iac-plan-write-guard.sh` was reported to fail OPEN on every
  policy check via a `pipefail` + `grep -q` SIGPIPE race.
- **#6991** — `scripts/tmpfs-guard.sh` cannot see a count-shaped leak, its alarm fires into
  channels nobody reads, and its telemetry is 99% its own test noise.

**The planning phase materially changed the diagnosis of #6992.** The reported mechanism was
measured and does not apply to the named file; a different, deterministic defect in the same
file produces the same symptom, and the SIGPIPE race is real but lives at a *different and
previously unenumerated* set of sites. Both the corrected diagnosis and the evidence are in
"Research Reconciliation" below. The issue's measured symptom stands; only its explanation
was wrong, so neither issue is closable as invalid.

Unifying theme, and the acceptance bar for every change here: **a guard that reports success
while doing nothing is worse than no guard.** Where a fix is possible, prefer the form whose
own failure is self-reporting.

---

## Research Reconciliation — Issue Claims vs. Measured Reality

All measurements taken 2026-07-27 on the target host (bash 5.3.9, GNU grep 3.12,
`pipe-max-size` 1048576, `pipe-user-pages-soft` 16384). Reproduction scripts are re-created
in Phase 0 so every row is re-verifiable at implementation time.

| # | Claim (from issue / prior art) | Measured reality | Plan response |
|---|---|---|---|
| R1 | "Every check in `iac-plan-write-guard.sh` fails open via a `pipefail`+`grep -q` SIGPIPE race." | **REFUTED for this file, by measurement.** All 7 checks use `echo "$content"` — a **bash builtin**. Builtin producers never raise the race: `echo`/`printf` into `grep -q` with match-at-top measured **0/40 pipeline failures at 4 / 16 / 50 / 64 / 128 / 1024 KB**. `PIPESTATUS` is `0 0` at 1 MB. Bash handles EPIPE for its own builtins; it does not die of SIGPIPE the way a forked binary does. | Keep the herestring conversion (cheap, matches repo canon at `plugins/soleur/skills/work/SKILL.md` §"never `grep -q` on a pipe"), but bill it honestly as **shape hygiene, not the bug fix**. Do not claim it fixes the reported symptom. |
| R2 | End-to-end: the guard fails open on forbidden content. | **REFUTED.** Driving the real hook with a 50 KB body: violation → `deny 12/12`; clean → `allow 12/12`; clean+ack → `allow 12/12`; violation+ack → `allow 12/12`. Zero flakes across all arms. | No change needed for the `Write` path. |
| R3 | "The ack escape hatch reads a PRESENT ack as absent — ~9 deny / 3 allow on byte-identical 50 KB input." | **SYMPTOM CONFIRMED; CAUSE DIFFERENT — and it is deterministic, not a race.** `iac-plan-write-guard.sh` derives its scan text as `.tool_input.content // .tool_input.new_string`. On an **`Edit`**, that is the **replacement chunk only, never the file**. Measured: `Edit` with a violation in `new_string` and the ack elsewhere in the file → **deny**; identical `Edit` with the ack inside the chunk → **allow**. A plan author editing successive regions of one acked plan therefore sees an apparently random deny/allow split on "byte-identical" input — exactly the reported 9/3 shape. | **This is the real #6992 defect.** Fix the scan scope (Phase 2). This is the load-bearing change. |
| R4 | (Corollary nobody filed.) | The same Edit-scope blindness is **also a genuine fail-open**: a violation already present in a plan is invisible to every subsequent `Edit` that does not touch it, so a plan can be walked past the guard in pieces. | Folded into the Phase 2 fix — one change closes both directions. |
| R5 | "The SIGPIPE race is the defect class; sweep siblings." | **CONFIRMED, but the discriminating axis is producer class, not input size — and no prior artifact states this.** With an **external** producer the race is real and *non-deterministic at every size*, including tiny inputs: `cat \| grep -q` match-at-top failed **3/20 at 1 KB**, 13/20 at 32 KB, 4/20 at 64 KB, 3/20 at 128 KB. `yes \| grep -q y` → `PIPESTATUS=141 0`, 3/3. Match-at-**bottom** → 0/20 (grep must read all; no early close). | Re-triage the whole sweep on **producer class**. Fix every *external*-producer site (the live bugs). Treat *builtin*-producer sites as inert-but-wrong-shaped: convert opportunistically, grandfather the rest under the Phase 5 lint. This cuts the work from ~95 sites to a small, fully-live set. |
| R6 | Sweep scope: "`.claude/hooks/*.sh` and `scripts/*.sh`". | The issue's glob under-reaches. Repo-wide the shape appears **~135 times in scope** (`.claude/hooks/`, `scripts/`, `plugins/`), ~95 non-test. **Every non-test shell file in scope that has a `set` line sets `pipefail`**; the three without a `set` line are sourced into callers that do. There is no immune-by-declaration site in scope except `plugins/soleur/skills/linear-fetch/scripts/assert-no-linear-telemetry.sh` (`set -eu`, no `pipefail`) and `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh` (no `set` line). | Phase 1 records the full sweep with producer class + failure direction, per AC. Phase 3 fixes the external-producer subset. |
| R7 | Prior art `2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md` describes the same class. | Confirmed and **already canonicalised**: `plugins/soleur/skills/work/SKILL.md` mandates herestring or `grep -c`, and two test files carry verbatim warning comments (`.claude/hooks/pre-merge-rebase.test.sh` §"Herestring, not a pipe"; `.claude/hooks/pre-merge-auto-close-scan.test.sh` §"grep a FILE-free herestring"). Both cite `git log`/`printf` producers. | The rule exists; enforcement does not. Phase 5 adds the missing mechanical gate and corrects the rule text to name the producer-class distinction. |
| R8 | **(Test-methodology hazard, newly found.)** | The interactive Bash tool resolves `grep` to a **Claude Code `ugrep` shim shell function**, and **ugrep `-q` drains its input** — it never early-closes, so the race is *invisible to anyone testing by hand in an agent session*. Hooks and cron run non-interactively and get `/usr/bin/grep` (GNU 3.12), where the race is live. Measured both ways. | **The regression test MUST pin the grep binary** (clean `PATH=/usr/bin:/bin`, `--noprofile --norc`) or it will pass vacuously. This is an explicit AC. It also likely explains why the class survived prior review passes. |
| R9 | "`scripts/lib/scratch-root.sh` already exists — the per-run private scratch root machinery may already be there to build on." | **REFUTED.** `soleur_scratch_root()` has **zero production callers**; the only invoker is its own test file, which is **not registered in `scripts/test-all.sh`**. It landed in the immediately preceding commit (`a5160b29a`) and was never wired. Its own docstring directs the common case *away* from it ("Small-fixture callers should keep using plain `mktemp`"). | The reviewed direction ("per-run private scratch roots reaped by their owner") **has nothing to key on today**. Adopting it would mean migrating hundreds of call sites — out of scope. Phase 6 takes a different route that needs no new convention (see D1). |
| R10 | "`tmp.` is mktemp's default template — 576 bare call sites." | **CONFIRMED, and worse.** Command-position `$(mktemp …)` invocations: **1013 total, 856 bare (84.5%)** producing the default `tmp.XXXXXXXXXX`. Only 48 use a `-t <prefix>` template, and **all 48 prefixes are unique (max frequency 1)**. The "576" figure is a *file* count (`git grep -l mktemp` → 587), not a call-site count. | A prefix allowlist would need 48 entries to cover 4.7% of the population and would grow with every new call site. **Prefix-based leak signatures are not viable.** Confirms the issue's warning; Phase 6 keys on nothing name-derived. |
| R11 | "The alarm must reach the observability layer — a monitored stdout `SOLEUR_*` marker → Better Stack, and/or Sentry." | **NOT REACHABLE AS SPECIFIED, by measurement.** (a) The `SOLEUR_*` marker convention is a **journald** convention consumed by **Vector**, and `vector.toml`'s `include_matches.SYSLOG_IDENTIFIER` is an **exact-value allowlist of 14 tags** that does not include `tmpfs-guard`. (b) **Vector is not installed on this host** (`command -v vector` → not found); it is deployed only to the Hetzner hosts. So `logger -t tmpfs-guard` cannot reach Better Stack even if allowlisted. (c) There is **no Sentry DSN wired into any locally-executing shell script**; every shell→Sentry call in the repo runs on a GitHub runner with an Actions-injected token. (d) `doppler` is at `~/.local/bin` — **not on cron's `PATH`**. (e) `gh` **is** at `/usr/bin/gh`, but authenticates via the **OS keyring**, which is unavailable to a cron job with no unlocked session. | **There is no existing local-cron → remote-observability path, and inventing one is out of scope.** Phase 7 routes the alarm to the surface that provably reaches the operator — the next agent session — and escalates remotely from a context where credentials exist. This is a design decision made against a measured constraint, and it is flagged for challenge at plan-review. |
| R12 | (Constraint nobody flagged.) | `iac-plan-write-guard.sh` **denies** plan text matching `crontab -e` / `sudo crontab` / `edit the crontab`, and `plugins/soleur/skills/plan/SKILL.md` lists crontab edits as a banned operator step. There is **no installer** for the tmpfs-guard cron entry — the live crontab line was hand-installed and is recorded only in a learning file. | The plan **must not** prescribe any crontab change. Every Part-B fix must be a **drop-in replacement at the existing path**, requiring no re-installation. Made an explicit constraint (C1) and an AC. |
| R13 | "Every doc claim keyed on per-entry reap detail is unverifiable." | **CONFIRMED and broader.** Falsified claims found in: `knowledge-base/project/plans/2026-07-27-fix-tmp-tmpfs-mktemp-cleanup-leak-plan.md` §Observability (5 distinct false claims, incl. an AC that greps for a string `logger` never writes and therefore **can never pass**), `.../plans/2026-07-22-fix-testall-worktree-contention-plan.md` §alert_route, and — most seriously — `plugins/soleur/skills/work/SKILL.md` ("tmpfs-guard.sh's cron reaper now bounds the abandoned-scratch growth"), which is **agent instruction loaded every session**. | Correcting these is in scope (Phase 9). A false claim in a per-session instruction file actively misleads every future agent. |

### What this means for issue disposition

Neither issue closes as invalid.

- **#6992** — the reported symptom is real and reproducible; the stated cause is not. The plan
  fixes the *actual* cause (Edit-scope), performs the *requested* sweep (with a corrected and
  more useful triage axis), fixes the *genuinely live* race sites the sweep exposes, and adds
  the regression test the issue asks for. Every acceptance box is satisfied, one of them by a
  better mechanism than proposed.
- **#6991** — all four defects confirmed. Two of the issue's suggested directions (per-run
  scratch roots; `SOLEUR_*` → Better Stack) are blocked by measured facts the issue could not
  have known. The plan states the blockers and routes around them rather than prescribing a
  path that does not exist.

---

## Hypotheses

Recorded per the plan skill's diagnosis discipline. Every verdict below is backed by a
measurement in "Research Reconciliation", not by reasoning. Phase 0 re-runs each probe so a
verdict cannot silently rot between planning and implementation.

| ID | Hypothesis | Verdict | Discriminator |
|---|---|---|---|
| H1 | The 7 `iac-plan-write-guard.sh` checks fail open via SIGPIPE. | **REFUTED** | Builtin producer measured 0/40 at 6 sizes up to 1 MB; hook end-to-end 12/12 correct on 5 arms. |
| H2 | The ack check fails closed via SIGPIPE. | **REFUTED** | Same measurement; ack arm allowed 12/12 on a 50 KB `Write`. |
| H3 | The ack check fails closed because `Edit` scans only `new_string`. | **CONFIRMED** | Ack-outside-chunk → deny; ack-inside-chunk → allow. Deterministic, reproduced directly. |
| H4 | The SIGPIPE race is real somewhere in the swept set. | **CONFIRMED** | External producers: `yes` 3/3 at `141`; `cat` 3–13/20 across 1 KB–128 KB. |
| H5 | The race is gated on input size (>64 KiB pipe buffer). | **REFUTED** | It fires at **1 KB** (3/20). It is a genuine race on writer-exit vs reader-close, not a buffer-capacity threshold. Size raises probability, it is not a gate. |
| H6 | Reduced pipe capacity under `pipe-user-pages-soft` explains sub-64 KB firing. | **NOT NEEDED / UNTESTED** | H5 already explains it without invoking pressure. Recorded so a future reader does not re-derive it as a live theory. |

**Network-outage checklist (plan Phase 1.4):** evaluated and **does not apply**. The trigger
words (`ssh`, `timeout`) occur in this plan only as quoted detection regexes belonging to the
guard under repair. No network path, host, or connectivity failure is in scope.

---

## User-Brand Impact

**If this lands broken, the user experiences:** their machine wedging again — `/tmp` fills,
agent sessions stop being able to write tool output, and work in progress is lost mid-task —
with a janitor and an alarm that both still report healthy. Secondarily, a plan carrying a
real manual-infrastructure step is written unchallenged because the guard's Edit path let it
through a chunk at a time.

**If this leaks, the user's data is exposed via:** nothing. Both scripts are local, read no
user content, and transmit nothing. The plan deliberately does **not** add a network egress
path from the operator's laptop (R11) — adding one would *create* a data-egress surface where
none exists, which `.claude/hooks/README.md` §"External-observability boundary" already rules
out pending DPA review.

**Brand-survival threshold:** `none`. Both targets are developer-workstation tooling with no
customer-facing surface, no persistence of user data, and no production blast radius. The
sensitive-path regex is not touched by any file in "Files to Edit"; no scope-out bullet is
required. Consequently `requires_cpo_signoff: false` and `user-impact-reviewer` is not
invoked.

---

## Constraints

- **C1 — No crontab change.** The fix must be a drop-in replacement at the existing
  `scripts/tmpfs-guard.sh` path. There is no installer, and the guard under repair in Part A
  denies plan text prescribing crontab edits (R12).
- **C2 — No new local→remote egress.** Out of scope by R11 and by the standing DPA boundary.
- **C3 — Cron `PATH` is `/usr/bin:/bin`.** `doppler` is unreachable; `gh` resolves but its
  keyring auth does not survive a cron session. Anything Part B relies on must work with
  neither.
- **C4 — The regression test must pin the `grep` binary** (R8), or it passes vacuously inside
  an agent session.
- **C5 — Planning phase touches only `knowledge-base/project/{plans,specs}/`.** All source
  edits below are implementation-phase work.

---

## Implementation Phases

### Phase 0 — Re-verify every premise (blocking, no edits)

Re-run each probe and paste output into the spec's evidence block. A verdict that no longer
reproduces halts the phase it justifies.

0.1 Producer-class probe, in a **clean non-interactive shell**:
`env -i PATH=/usr/bin:/bin HOME="$HOME" bash --noprofile --norc <probe>`. Assert
`command -v grep` is `/usr/bin/grep` and it reports GNU grep. Confirm builtin `echo` → 0
failures at 1 MB; `yes | grep -q y` → `PIPESTATUS` `141 0`; `cat` of a 1 KB file with
match-at-top → non-zero failure count over 20 runs.
0.2 Hook end-to-end: 5 arms × 12 runs (`Write` × {violation, clean, clean+ack, violation+ack};
1 KB clean). Expect 12/12 correct in all arms.
0.3 Edit-scope probe: ack outside chunk → deny; ack inside chunk → allow.
0.4 `command -v vector` → absent. `grep -c tmpfs-guard apps/web-platform/infra/vector.toml`
→ 0. `env -i PATH=/usr/bin:/bin gh auth status` → confirm it fails without a keyring.
0.5 Re-count `mktemp`: total command-position invocations, bare count, `-t` count, and the
max prefix frequency among `-t` sites. Assert max frequency is 1.
0.6 Confirm `scripts/lib/scratch-root.sh` still has zero production callers.

**Gate:** if 0.1 or 0.3 fails to reproduce, stop and re-diagnose. Do not proceed on a stale
premise.

---

### Part A — issue #6992

### Phase 1 — Sweep and record (satisfies AC-A3)

Run `git grep -nE '\|[[:space:]]*grep[[:space:]]+-q'` over `.claude/hooks/`, `scripts/`, and
`plugins/` — **wider than the issue's glob** (R6). For every non-test hit record: file:line,
`pipefail` status, **producer class (builtin vs external)**, the producer's provenance,
failure direction, and live/inert verdict.

Failure-direction taxonomy — the third form is the subtle one and must be flagged explicitly
wherever it appears:

| Shape | On race | Direction |
|---|---|---|
| `X \| grep -q P && deny` | `deny` skipped | **FAILS OPEN** |
| `if X \| grep -q P; then allow` | bypass skipped | fails closed |
| `if ! X \| grep -q P; then <early-exit>` | `!` inverts the false negative → early-exit fires → **the gate skips its own check** | **FAILS OPEN** |

Deliverable: a table in `knowledge-base/project/specs/<branch>/sweep.md`, plus the
producer-class summary. This table is the input to Phase 3's scope and to Phase 5's allowlist.

### Phase 2 — Fix the real `iac-plan-write-guard.sh` defect (Edit scope) — **load-bearing**

The guard must evaluate the **resulting document**, not the edited fragment.

- For `Write`: unchanged — `tool_input.content` already is the whole document.
- For `Edit`: reconstruct the post-edit document. Read the file at `tool_input.file_path` and
  apply the `old_string`→`new_string` substitution in memory; scan the result. If the file is
  unreadable (new file, path outside the repo), fall back to scanning `new_string` alone and
  **say so in the deny reason** — a degraded scan must never masquerade as a full one.
- The ack check then sees an ack wherever it lives in the document (fixes the fail-closed
  symptom, R3), and a pre-existing violation is no longer invisible to an unrelated edit
  (fixes the fail-open corollary, R4).
- Correct the file's header comment: "Hook exit code: 0 always" is a claim to verify against
  the fixed control flow, not to inherit.

Order matters: this precedes Phase 3 because it changes what the guard scans, and Phase 4's
tests assert against the fixed contract.

### Phase 3 — Fix the genuinely live race sites

Convert **external-producer** sites (`cat`, `git show`, `git log`, `git diff`, `base64 -d`,
`jq`, `awk`, and function wrappers around them) to a non-racing form:

- Producer already in a variable → `grep -q P <<<"$var"` (herestring, no pipe).
- True command producer → capture first (`v="$(cmd)"`, then herestring), or use
  `[ "$(cmd | grep -c P || true)" -gt 0 ]` (`grep -c` reads all input, never early-closes).
- Never `grep -qo` — `-q` wins over `-o` and still early-exits.

Known live set from the sweep (Phase 1 finalises it): `.claude/hooks/pre-merge-rebase.sh`
(`git show` → review-evidence read, fails closed), `.claude/hooks/brand-hex-commit-gate.sh`
(`_committed_content` → `cat`/`git show`, fails closed),
`.claude/hooks/skill-security-scan.sh` and `.claude/hooks/skill-context-queries.sh`
(`git diff` / `awk`), `scripts/update-ci-required-ruleset.sh` and
`scripts/create-ci-required-ruleset.sh` (`base64 -d`, fails closed),
`scripts/watch-live-verify-pass.sh` (`gh | jq`),
`plugins/soleur/skills/review/scripts/emit-review-trailer.sh` (`git log`).

Also convert the 7 builtin-producer sites in `iac-plan-write-guard.sh` — inert today (R1),
but wrong-shaped, and the file is the subject of the issue.

**Every converted site keeps its surrounding control flow byte-for-byte.** A herestring swap
must not alter `&&` chaining, `!` inversion, or exit paths.

### Phase 4 — Regression tests (satisfies AC-A2)

In `.claude/hooks/iac-plan-write-guard.test.sh`:

- **T1 (the AC's test):** drive the guard with a large body (≥64 KB) whose violation sits near
  the top; assert `deny` on **every** iteration of **≥30** runs. Non-determinism means one run
  proves nothing.
- **T2:** same body plus the ack → `allow` on ≥30 runs.
- **T3 (Edit scope, the real bug):** `Edit` whose `new_string` carries a violation while the
  ack lives elsewhere in the file → `allow`. This test **fails before Phase 2 and passes
  after**; it is the RED→GREEN anchor.
- **T4 (Edit fail-open corollary):** file already contains a violation; `Edit` touches an
  unrelated region → `deny`.
- **T5 (C4/R8 — vacuity guard):** the harness asserts `command -v grep` resolves to a GNU grep
  and **not** to a shell function, aborting loudly otherwise. Without T5 the suite passes for
  the wrong reason inside an agent session.

Add a producer-class unit test next to the Phase 5 lint proving `cat | grep -q` can fail and
`echo | grep -q` does not — this is the evidence that keeps the lint's allowlist honest.

### Phase 5 — Mechanical enforcement (the self-reporting piece)

The rule already exists in `plugins/soleur/skills/work/SKILL.md`; nothing enforces it, which
is why ~95 sites accumulated. Add a lint (registered in `scripts/test-all.sh`) that fails on
any **external-producer** `| grep -q` under `pipefail` not present in a checked-in allowlist.

- Seed the allowlist from Phase 1 **minus** everything Phase 3 fixes, so the count can only
  shrink. Per the guard-surface Sharp Edge, the current match count is non-zero and is
  therefore grandfathered explicitly rather than pretending enforcement is future-only.
- The allowlist file carries one line per site with its recorded failure direction — reading
  it *is* the sweep record, so the AC-A3 artifact cannot rot away from the code.
- Correct the `work/SKILL.md` rule text to state the producer-class distinction (R5): the
  current wording implies all piped `grep -q` is equally dangerous, which sends reviewers
  hunting inert builtin sites while live external ones pass unremarked.

---

### Part B — issue #6991

### Phase 6 — A reaper that can see a count-shaped leak (AC-B1)

**Design first, per the issue's instruction.** The reviewed direction (per-run private scratch
roots reaped by their owner) is **not available**: `scratch-root.sh` has zero adopters (R9)
and 84.5% of `mktemp` sites emit the default template (R10). Prefix-guessing is exactly what
the issue forbids.

**D1 — the resolving insight: safety was never coming from the name or the size.** The
existing reaper already clears four independent gates — ownership (own uid), **recursive** age
(nothing anywhere in the tree touched within the floor), liveness (no process cwd and no open
fd inside it, via the single `/proc` pass), and a protected-path denylist. `SCRATCH_MIN_MB` is
**not a safety gate**; it is a *cost* gate that bounds how many trees `du` must walk. Removing
it therefore costs no safety at all — and it is the sole reason the reaper could not see
15,000 × 372-byte files.

So: add a **pressure-tiered second arm** keyed on measured pressure, not on names.

- **Normal tier** — unchanged (100 MB / 24 h). Cheap, conservative, always on.
- **Pressure tier** — engages only when `/tmp` block usage **or inode usage** (`df -i`, the
  count-shaped signal the issue asks for) crosses a high-water mark. It drops the size floor
  entirely and lowers the age floor to a shorter window, while keeping ownership, recursive
  age, liveness, and the protected denylist **fully intact**.
- **Cheaper, not costlier:** with no size floor the pressure arm skips `du` altogether, so it
  avoids the very walk that made the size gate expensive. It is `find` + the existing `/proc`
  set lookup.
- It must skip the guard's **own** two `mktemp -t tmpfs-guard-*` working files.

**Defense-relaxation ceilings** (required whenever a load-bearing floor is relaxed — the
lowered age floor is one). The relaxation is bounded by, and the implementation must encode,
all four: (i) it runs *only* under measured pressure, never on a healthy mount; (ii) ownership
and liveness are never relaxed, so live work and other users' files remain untouchable;
(iii) a per-run cap on entries reaped, so a mis-tuned floor cannot empty `/tmp` in one tick;
(iv) every pressure-tier reap is logged individually, so the arm's behaviour is auditable
rather than inferred.

Deletion keeps the existing `find … -delete` idiom (never `rm -rf`) — a survivor can be an
abandoned `.git`-bearing checkout.

### Phase 7 — An alarm that reaches a human (AC-B2)

**The specified route is unavailable** (R11): no Vector locally, tag not allowlisted, no local
Sentry DSN, `doppler` off cron's `PATH`, and `gh` blocked by keyring auth under cron. Naming
this honestly is required — prescribing a `SOLEUR_*` → Better Stack marker here would produce
a *second* alarm that reports success while reaching no one, which is the exact failure under
repair.

**Route the alarm to the surface that provably reaches the operator: the next agent session.**

- The guard appends to a durable, size-capped alarm state file at a fixed path (outside `/tmp`
  — an alarm store on the filesystem being reaped is self-defeating), recording timestamp,
  usage %, inode %, and reap counts.
- A `SessionStart` hook surfaces a one-line summary ("tmpfs-guard alarmed N times since
  `<ts>`; `/tmp` at X%") into session context. This path needs **no network, no credentials,
  and no `PATH` assumptions** — it cannot fail the way the current one does, and the operator
  works through agent sessions daily.
- **Remote escalation happens from a context where credentials exist.** When the surfaced
  count crosses a threshold, the agent files a deduped `action-required` GitHub issue — the
  repo's established alarm-dedupe pattern, executed where `gh` actually authenticates. This
  keeps a remote artifact without inventing a cron-time egress path (C2).
- Retire `notify-send` from the alarm path, or keep it strictly as a best-effort extra with a
  comment recording that it is a no-op under cron. It must never again be counted as a channel.

### Phase 8 — Log sink, telemetry, and the arithmetic bug (AC-B3, AC-B4)

One change fixes three of the four defects.

- **`guard_log()` wrapper + `TMPFS_GUARD_LOG_SINK` seam** (default `logger`), replacing all
  three hard-coded `logger -t tmpfs-guard` sites. The test harness points it at a
  fixture-scoped file under its own `TESTROOT`, so the suite stops writing to the operator's
  journal (AC-B3). This matches the existing `TMPFS_GUARD_*` seam naming and is the *only*
  seam class not already present — every current seam is a path or a numeric floor, and
  `logger` writes to a socket no path seam can redirect.
- **`echo` → `guard_log` for per-entry reap detail** (both the live and `DRY_RUN` lines). The
  journal gains the per-entry `reaping <path> (<N> MB)` lines that several docs already claim
  exist (AC-B4a, R13).
- **The multi-line arithmetic bug falls out for free** (AC-B4b): once the human-readable lines
  route to the sink instead of stdout, `reap_scratch_entries` emits **only the integer** on
  stdout, so `reaped="$(…)"` captures a clean number and `[[ "$reaped" -eq 0 ]]` stops raising
  a syntax error every 5 minutes. Add a defensive numeric sanitize at the consumer anyway — a
  future stray `echo` must not silently re-break the high-usage branch. Apply the same
  sanitize to `cleaned`, which is safe today only by luck.
- Add a **per-run liveness line** so a healthy run is distinguishable from a dead cron. Today
  the guard logs nothing at all unless it reaps or alarms, so "silent" and "not running" are
  indistinguishable — the property that let this rot unnoticed.
- **Hermeticity:** the suite currently runs `df` against a `TESTROOT` that lives on the real
  `/tmp`, so it branches on live production state. Point the usage probe at a seam so tests
  are deterministic.

### Phase 9 — Correct the falsified documentation (R13)

Ordered by blast radius:

1. `plugins/soleur/skills/work/SKILL.md` — the claim that the cron reaper "bounds the
   abandoned-scratch growth" is **loaded into every agent session** and is false for the
   count-shaped class. Highest priority.
2. `knowledge-base/project/plans/2026-07-27-fix-tmp-tmpfs-mktemp-cleanup-leak-plan.md`
   §Observability — five false claims, including an acceptance criterion that greps for a
   string `logger` never writes and therefore can never pass. Mark corrected in place;
   after Phase 8 most of these become *true*, so update rather than delete.
3. `knowledge-base/project/plans/2026-07-22-fix-testall-worktree-contention-plan.md`
   §alert_route — the named backstop is the 94-times-unheard branch.

### Phase 10 — Learning capture

One learning file. The durable, transferable findings are:

- **The producer-class discriminator**: `pipefail` + `grep -q` is a live race only with an
  **external** producer; bash builtins are immune. This reframes an entire documented defect
  class and is not stated anywhere in the repo today.
- **The race is not size-gated** — it fires at 1 KB. Any "the input is small, it's fine"
  triage is wrong.
- **A `ugrep` shim in agent sessions hides the bug from manual testing** — a test-methodology
  trap that likely explains the class's survival, and a reason to pin binaries in guard tests.
- **A hook that scans `new_string` scans a fragment, not a document** — generalises to every
  PreToolUse guard on `Edit`.
- **"Reviewed direction" is a hypothesis about the codebase, not a fact.** Two of #6991's were
  blocked by measurable repo state (zero adopters; no local Vector).

---

## Files to Edit

**Part A**
- `.claude/hooks/iac-plan-write-guard.sh` — Edit-scope reconstruction (Phase 2); 7 herestring
  conversions (Phase 3); header-comment correction.
- `.claude/hooks/iac-plan-write-guard.test.sh` — T1–T5 (Phase 4).
- External-producer sites finalised by Phase 1, currently: `.claude/hooks/pre-merge-rebase.sh`,
  `.claude/hooks/brand-hex-commit-gate.sh`, `.claude/hooks/skill-security-scan.sh`,
  `.claude/hooks/skill-context-queries.sh`, `scripts/update-ci-required-ruleset.sh`,
  `scripts/create-ci-required-ruleset.sh`, `scripts/watch-live-verify-pass.sh`,
  `plugins/soleur/skills/review/scripts/emit-review-trailer.sh`.
- `plugins/soleur/skills/work/SKILL.md` — producer-class correction to the existing rule.
- `scripts/test-all.sh` — register the Phase 5 lint (and, opportunistically,
  `scripts/lib/scratch-root.test.sh`, which is currently registered nowhere).

**Part B**
- `scripts/tmpfs-guard.sh` — Phases 6, 7, 8.
- `scripts/tmpfs-guard.test.sh` — sink seam, hermetic usage probe, pressure-tier arms.
- `.claude/hooks/` — SessionStart alarm surfacing (Phase 7); extend the existing SessionStart
  hook rather than adding a new one if it already carries context injection.
- `plugins/soleur/skills/work/SKILL.md`,
  `knowledge-base/project/plans/2026-07-27-fix-tmp-tmpfs-mktemp-cleanup-leak-plan.md`,
  `knowledge-base/project/plans/2026-07-22-fix-testall-worktree-contention-plan.md` — Phase 9.

## Files to Create

- `scripts/lint-piped-grep-q.sh` (or equivalent) + its allowlist — Phase 5.
- `knowledge-base/project/specs/feat-one-shot-6992-iac-guard-sigpipe-fail-open/sweep.md` —
  Phase 1 record.
- One learning file under `knowledge-base/project/learnings/` — Phase 10 (directory + topic
  only; the author picks the date at write time).

---

## Acceptance Criteria

### Pre-merge (PR)

**Part A — #6992**
- [ ] **AC-A1** No check in `iac-plan-write-guard.sh` consumes `$content` through a pipe into
      `grep -q`. Verify: the sweep pattern returns 0 hits for that file.
- [ ] **AC-A2** A regression test drives the guard with a ≥64 KB body whose match is near the
      top and asserts the deny fires on **every one of ≥30** runs.
- [ ] **AC-A3** Sibling `| grep -q` sites are swept and recorded with **producer class and
      failure direction per site**, in a checked-in artifact that is also the lint's allowlist
      (so it cannot rot). Sweep spans `.claude/hooks/`, `scripts/`, `plugins/`.
- [ ] **AC-A4** T3 (Edit + ack-elsewhere → `allow`) fails on the pre-Phase-2 code and passes
      after. Demonstrated by running it at both commits.
- [ ] **AC-A5** T4 (pre-existing violation + unrelated Edit → `deny`) passes.
- [ ] **AC-A6** T5 aborts loudly when `grep` resolves to a shell function rather than a GNU
      grep binary — the suite cannot pass vacuously.
- [ ] **AC-A7** Every external-producer site listed in Phase 3 is converted, with surrounding
      control flow unchanged (verify by reading the diff, not by grep count alone).
- [ ] **AC-A8** The Phase 5 lint fails on a deliberately introduced external-producer
      `| grep -q` and passes on the post-fix tree.

**Part B — #6991**
- [ ] **AC-B1** The reaper acts on a count/inode-pressure signal, not size alone, and keys on
      **no name-derived signature** — grep the diff for `tmp.` prefix logic and find none.
      Ownership, recursive age, liveness, and the protected denylist are all still enforced on
      the pressure path.
- [ ] **AC-B2** The relaxation ceilings (i)–(iv) of Phase 6 are each present in code.
- [ ] **AC-B3** A test proves a count-shaped leak (many tiny files, no entry near the old size
      floor) is reaped under simulated pressure and **not** reaped without pressure.
- [ ] **AC-B4** The high-usage alarm reaches a surface that requires no network, credentials,
      or non-default `PATH`; a test asserts the alarm state file is written and the SessionStart
      surfacing renders it.
- [ ] **AC-B5** `tmpfs-guard.test.sh` writes nothing to the production journal. Verify: run the
      suite, then confirm `journalctl -t tmpfs-guard` gained no lines during the run.
- [ ] **AC-B6** Per-entry reap detail reaches the log sink (not bare stdout), and
      `reap_scratch_entries` emits **only** an integer on stdout.
- [ ] **AC-B7** No arithmetic syntax error on a run that reaps ≥1 entry — assert clean stderr.
- [ ] **AC-B8** A healthy run emits a liveness line, so "silent" and "not running" are
      distinguishable.
- [ ] **AC-B9** `scripts/tmpfs-guard.sh` remains a drop-in at its existing path; the PR
      prescribes **no** crontab change (C1).
- [ ] **AC-B10** The three falsified doc claims of Phase 9 are corrected, `work/SKILL.md`
      first.

**Cross-cutting**
- [ ] **AC-X1** PR body contains `Closes #6992` and `Closes #6991`.
- [ ] **AC-X2** `bash scripts/test-all.sh` passes.
- [ ] **AC-X3** Phase 0 probe outputs are pasted into the spec evidence block, so every
      Reconciliation verdict is re-verifiable from the PR alone.

### Post-merge (operator)

None. Both targets are drop-in replacements at existing paths (C1); the tmpfs-guard cron entry
continues to invoke the same path and needs no re-installation. No infrastructure, no secret,
no vendor action.

---

## Open Code-Review Overlap

Checked against open `code-review`-labelled issues for the files in "Files to Edit".

**None.** No open code-review issue names `iac-plan-write-guard.sh`, `tmpfs-guard.sh`, or the
external-producer sites in Phase 3. The two governing issues (#6992, #6991) are `type/bug`,
not `code-review`, and are both closed by this PR. Recorded so the next planner can see the
check ran.

---

## Infrastructure (IaC)

**Not applicable — no infrastructure is introduced, changed, or provisioned.**

Both targets are existing local developer tooling. No server, systemd unit, DNS record, TLS
cert, secret, firewall rule, vendor account, or monitoring webhook is created or modified. No
Terraform root is touched.

The Phase 2.8 detector fires on this document only because the plan must **quote the detection
regexes of the guard it repairs** — the operator-SSH, systemd, secret-write, vendor-dashboard,
and crontab literals appear exclusively as citations of patterns under repair. The ack comment
at the top of this file records that deliberate, audited opt-out.

Two related notes:

- **No crontab change is prescribed** (C1/R12). The existing cron entry invokes
  `scripts/tmpfs-guard.sh`; the fix replaces that file's contents in place.
- **No new egress path** is created from the operator's machine (C2/R11), which keeps this
  change on the safe side of the standing external-observability boundary.

---

## Observability

```yaml
liveness_signal:
  what: "tmpfs-guard emits a per-run line via guard_log on EVERY run, healthy or not (Phase 8)"
  cadence: "every 5 minutes, unchanged"
  alert_target: "durable alarm state file -> SessionStart context injection -> operator's next agent session"
  configured_in: "scripts/tmpfs-guard.sh (guard_log + alarm state file); .claude/hooks/ SessionStart surfacing"

error_reporting:
  destination: "alarm state file read at SessionStart; escalated to a deduped action-required GitHub issue by the agent, from a context where gh authenticates"
  fail_loud: true
  note: "Deliberately NOT logger-only and NOT notify-send. Measured (R11): Vector is absent on this host, tmpfs-guard is not in the vector.toml tag allowlist, no local Sentry DSN exists, doppler is off cron PATH, and gh keyring auth does not survive cron. The prior design counted two channels that reached nobody 94 times in 14 days; this one depends on no network, no credentials, and no PATH assumption."

failure_modes:
  - mode: "cron entry stops firing entirely"
    detection: "the per-run liveness line stops appearing; its absence is now meaningful because a healthy run always emits one (Phase 8)"
    alert_route: "SessionStart surfacing reports the staleness of the alarm state file"
  - mode: "/tmp fills with a count-shaped leak the reaper cannot reclaim"
    detection: "pressure tier engages on inode/block usage and logs per-entry reaps; if it reaps nothing while pressure persists, the alarm state file records the streak"
    alert_route: "SessionStart surfacing -> agent files a deduped action-required issue"
  - mode: "iac-plan-write-guard denies a valid acked plan (the #6992 symptom)"
    detection: "T2/T3 regression tests in CI; the deny reason now distinguishes a full scan from a degraded new_string-only scan (Phase 2)"
    alert_route: "CI failure on scripts/test-all.sh"
  - mode: "a new external-producer `| grep -q` lands and silently disables a gate"
    detection: "Phase 5 lint over the whole tree, with a shrink-only allowlist"
    alert_route: "CI failure on scripts/test-all.sh"
  - mode: "the guard test suite passes vacuously because grep resolved to the ugrep shim"
    detection: "T5 asserts the resolved grep is a GNU grep binary, not a shell function"
    alert_route: "CI failure on scripts/test-all.sh"

logs:
  where: "systemd journal via logger -t tmpfs-guard (production); a fixture-scoped file under TESTROOT during tests (TMPFS_GUARD_LOG_SINK); the durable alarm state file for alarm events"
  retention: "journal per host defaults; alarm state file is size-capped by the guard"

discoverability_test:
  command: "bash scripts/tmpfs-guard.test.sh && bash .claude/hooks/iac-plan-write-guard.test.sh && bash scripts/lint-piped-grep-q.sh"
  expected_output: "all suites pass; journalctl -t tmpfs-guard gains no lines attributable to the test run; the lint reports zero non-allowlisted external-producer sites"
```

No SSH appears in any verification command. Both surfaces are local and directly inspectable
by the operator's agent.

---

## Encryption Posture

**Not applicable.** No persistent data store (volume, bucket, table, queue, cache, backup
target, log sink beyond the existing local journal) and no new cross-component or network
connection is introduced. The alarm state file is local, contains only usage percentages,
timestamps, and counts, and holds no user or secret data. Detection patterns (`.tf`,
`supabase/migrations/*.sql`, `cloud-init*.yaml`, `docker-compose*.yaml`) match nothing in
"Files to Edit".

---

## Architecture Decision (ADR/C4)

**No ADR required.** This plan makes no architectural decision: no ownership or tenancy
boundary moves, no new substrate or integration pattern is introduced, no resolver/dispatch/
trust boundary changes, and no existing ADR is reversed or extended. Both changes are bug
fixes on existing local surfaces.

**C4 views — no impact.** All three model files (`model.c4`, `views.c4`, `spec.c4`) were
reviewed rather than keyword-grepped, per the completeness mandate. Enumerated for this change:
(a) **external human actors** — none; neither guard receives input from or emits output to any
party outside the operator, and no correspondent, reviewer, or recipient is added;
(b) **external systems/vendors** — none added; the plan explicitly *declines* to add a
Better Stack or Sentry edge from the laptop (R11/C2), so no new vendor boundary is crossed;
(c) **containers/data stores** — none; the local alarm state file is developer-workstation
scratch, not a modelled container, and the operator laptop is not a modelled element;
(d) **actor↔surface access relationships** — unchanged; no sharing, ownership, or permission
edge is altered. No element description is falsified by this change.

---

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Both issues are `domain/engineering` (CTO). The work is developer-tooling
correctness with no product, legal, financial, marketing, sales, support, or operations
surface. The three engineering-relevant risks are (1) scope — a 95-site sweep is compressed to
a small live set by the producer-class finding, which is the correct cut; (2) a defense
relaxation in the tmpfs pressure tier, which is bounded by four explicit ceilings and by the
fact that the relaxed floor was a cost gate, not a safety gate; (3) the alarm route departs
from the issue's stated target for measured reasons, and should be challenged at plan-review
to confirm the SessionStart route is accepted over inventing a cron-time egress path.

### Product/UX Gate

Not applicable. Product domain not relevant; the mechanical UI-surface override does not fire —
no path in "Files to Create"/"Files to Edit" matches `components/**/*.tsx`, `app/**/page.tsx`,
`app/**/layout.tsx`, or any UI-surface glob. No user-facing surface, no wireframe required.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The corrected #6992 diagnosis is itself wrong.** | Every verdict rests on a re-runnable measurement, not on reasoning; Phase 0 re-runs all of them and halts on any that no longer reproduces. The Edit-scope cause was reproduced directly, both directions. |
| **Reconstructing the post-edit document in Phase 2 mis-applies the substitution** (multiple matches, `replace_all`, whitespace drift) and denies a valid plan. | Fall back to `new_string`-only scanning on any reconstruction failure, and say so in the deny reason so a degraded scan is never mistaken for a full one. Tests cover both paths. |
| **Reading the target file on every `Edit` slows the hook** or breaks on unreadable paths. | Files in scope are plans/specs (measured avg ~29 KB, max ~120 KB) — trivial to read. Unreadable path falls back as above. |
| **Dropping the size floor makes the pressure tier delete live work.** | The floor was a cost gate, not a safety gate (D1). Ownership, recursive age, liveness, and the protected denylist all still apply, plus the four Phase-6 ceilings. The lowered *age* floor is the only true relaxation and is confined to measured-pressure runs with a per-run cap. |
| **The pressure tier is too slow for a 5-minute cron on a full `/tmp`.** | It is *cheaper* than the normal tier: with no size floor it skips `du` entirely, which was the expensive walk. Verify against a realistic fixture (≥10,000 entries) as part of AC-B3. |
| **The SessionStart alarm route is judged insufficient at review.** | Flagged explicitly for plan-review and deepen-plan. The measured blockers (R11) are documented so the panel can weigh a genuine alternative rather than re-propose the unreachable one. |
| **The Phase 5 lint's allowlist becomes a dumping ground.** | Shrink-only by construction: seeded once from Phase 1 minus Phase 3's fixes; the lint fails on any new entry. The allowlist doubles as the AC-A3 sweep record, so it is read, not ignored. |
| **Scope creep across two issues in one PR.** | Phase boundaries are strict and the phases are independently revertible. Part A's fix set is bounded by the measured live-site list, not by the 95-site shape count. |
| **A later `Edit` to this plan file is denied by the guard** because the ack sits outside the edited chunk (the very bug under repair, R3). | Known hazard. Re-`Write` the whole file rather than `Edit`ing it, or include the ack line in the chunk. This is recorded as first-hand evidence for T3. |

---

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Fix only the 7 `iac-plan-write-guard.sh` sites as the issue literally asks. | Measured inert (R1). It would close the issue while leaving the reported symptom live and every genuinely racing site untouched — the exact "guard reports success while doing nothing" failure this plan exists to end. |
| Convert all ~95 `| grep -q` sites. | ~90% are builtin producers and provably cannot race (R1). Large diff, large review surface, near-zero defect yield. The lint grandfathers them and blocks new ones instead. |
| Close #6992 as invalid, since its stated mechanism is refuted. | The measured 9/3 symptom is real and has a real cause (R3). Closing it would discard a genuine, reproducible fail-closed **and** fail-open defect. |
| Per-run private scratch roots reaped by owner (the issue's reviewed direction). | `scratch-root.sh` has zero adopters and 84.5% of `mktemp` sites use the default template (R9/R10). Adopting it means migrating hundreds of call sites — a separate, much larger piece of work. Deferred; see below. |
| Count-based reaping keyed on the `tmp.` prefix. | Explicitly forbidden by the issue and confirmed unsafe: `tmp.` is the default template at 856 sites (R10). Phase 6 keys on nothing name-derived. |
| Emit a `SOLEUR_*` marker to `logger` and add `tmpfs-guard` to the Vector tag allowlist. | Vector is not installed on this host (R11); the tag would be allowlisted on servers that never see this journal. It would create a second alarm reaching nobody. |
| Have the cron job file a GitHub issue directly. | `gh` resolves under cron but authenticates via the OS keyring, which is unavailable to a cron session (R11/C3). Measured, not assumed. |
| Store a `gh` token on disk so cron can authenticate. | Creates a durable credential on the workstation and a new egress path, against C2 and the standing external-observability boundary, to solve a problem the SessionStart route solves with no credential at all. |

**Deferred, needs a tracking issue at ship time:** migrating bulk-writing `mktemp` call sites
onto `soleur_scratch_root()` so that a per-run private scratch root becomes a real convention
(R9). Re-evaluation trigger: when a second count-shaped leak occurs, or when adopter count
passes a threshold that makes owner-scoped reaping viable. Also note
`scripts/lib/scratch-root.test.sh` is registered in no runner — folded into Phase 5's
`test-all.sh` edit.

---

## Test Scenarios

1. **Producer class** — builtin `echo`/`printf` into `grep -q` never fails on match (≥40 runs,
   ≥1 MB); external `cat`/`yes` into `grep -q` does fail on match-at-top; match-at-bottom never
   fails. Pins the discriminator the whole Part-A scope rests on.
2. **Guard, `Write` path** — violation → deny; clean → allow; clean+ack → allow;
   violation+ack → allow. ≥30 runs each on a ≥64 KB body.
3. **Guard, `Edit` path** — ack elsewhere in file → allow (RED before Phase 2); pre-existing
   violation + unrelated edit → deny; unreadable file → degraded scan with the degradation
   named in the deny reason.
4. **Vacuity guard** — harness aborts when `grep` is a shell function.
5. **Lint** — fails on an injected external-producer site; passes on the fixed tree; allowlist
   entries are accepted but cannot grow silently.
6. **tmpfs pressure tier** — a fixture of ~10,000 tiny files with no entry near the old size
   floor is reaped under simulated pressure, untouched without pressure; a live (open-fd) tree
   and a foreign-uid tree are never reaped in either mode; the per-run cap holds.
7. **tmpfs telemetry** — suite run adds no lines to `journalctl -t tmpfs-guard`; per-entry
   detail lands in the fixture sink; `reap_scratch_entries` stdout is a bare integer; stderr is
   clean on a reaping run; a healthy run emits a liveness line.
8. **Alarm** — state file written on a pressure run, size cap holds, SessionStart surfacing
   renders the summary; nothing requires network or credentials.
