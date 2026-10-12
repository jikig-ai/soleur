---
title: "fix: reap session-scoped mktemp artifacts leaking into /tmp (count-shaped)"
type: fix
date: 2026-10-12
slug: fix-mktemp-tmp-leak
branch: feat-one-shot-10017-mktemp-tmp-leak
issue: 10017
closes: [10017, 9341]
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-10-12
**Gate results:** Phase 4.6 User-Brand (pass — `none`, no sensitive-path
diff), 4.7 Observability (pass — verb allowlisted, literal output,
probe script committed in-PR), 4.8 PAT (no hits), 4.9 UI-wireframe
(no UI files — skip), 4.10 Encryption (trigger word `queue` is
`merge-queue` prose — no new store/connection — skip), 4.11 Guard
Contract (`lint-guard-contract.py` green, 1 entry, structural assembly),
4.12 Scope Check (one unfenced section, all rows mapped/justified, no
BLOCKED marker). 4.5 network-outage and 4.55 downtime: no trigger.

**Verify-the-negative pass:** `rung2-archive` sole producer confirmed
(`git-data-birth-readiness-gate.sh:1447` — zero other hits outside
tests/docs/classifier); `_tmp` consumed only in-function; bare `tmp.*`
protected-class confirmed in `tmp-classify.sh` + `soleur-tmp-purge.sh`
contracts; `trap … EXIT|RETURN` census regex confirmed to cover RETURN
(`TRAP_EXIT` at lint :194); cited lines
`browser-snapshot-credential-guard.test.sh:153-158`, `#6991`,
`#7208`, `#3595`, ADR-129/176/250, `cq-write-failing-tests-before`,
`hr-all-infrastructure-provisioning-servers` all verified live.

**Precedent-diff (Phase 4.4):** systemd user units — precedent
`scripts/tmpfs-guard.{service,timer}` (optional, `~/.config/systemd/user/`,
`Type=oneshot`, `WantedBy=timers.target`, TMPDIR pin comment) — new units
mirror it 1:1. Owning-trap-with-explicit-rm precedent —
`.claude/hooks/browser-snapshot-credential-guard.test.sh:153-158`.
Provable-operand precedent — `assert_fixture_dir` in
`tests/scripts/test-scratch-residue.sh`. List-mode precedent —
`--census-detail` counter dump on the same `census_all` pass.
Scheduled-work check: the units are host-local user timers, not repo
cron — the Inngest/GHA-Actions precedent check does not reach them.

**Key refinement:** tmpfiles.d `e`/`d` lines accept glob paths, but `e`
cleans a directory's *contents* by age — not the top-level entry itself
— so a literal `e /tmp/rung2-archive.*` rule reaps payload bytes while
leaving the count-shaped dir shells it was meant to bound; a scoped
`d /tmp`/`e /tmp` age sweep remains the rejected shared-base trade.
This independently lands the Phase-4 assumption on the purge-timer form
(recorded in `decision-challenges.md`).

**Agent fan-out:** no Task/Agent tool in this subagent context —
research, review, and domain agents were applied inline by the
orchestrator (verified greps, ADR reads, standing-check audit) and the
gaps recorded, not claimed as independent review.

## Overview

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

The operator host's tmpfs `/tmp` accumulated ~7,700 top-level entries in two
days of agent-pipeline activity (#10017): ~7,000 bare `tmp.*` files from
`mktemp` call sites that run during agent sessions without an owning cleanup
trap, plus ~650 `rung2-archive.*` directories left one-per-gate-call by the
git-data birth-readiness gate library. The tmpfs-guard count alarm detects the
growth but is deliberately detect-only for this shape (shared `/tmp` has no
value proxy for bare `tmp.*`), and Reaper 3's ownership-keyed reclamation does
not reach unattributed `tmp.*` files — so the fix is producer-side. This plan
censuses every `mktemp` allocation under `plugins/soleur/**`, `scripts/**`, and
`.claude/hooks/**`, attaches an owning trap or explicit removal where the
artifact is session-scoped (ADR-129 upgrade trigger: the operator workstation
is a long-lived host), closes the rung2-archive leak at its single producer
site, and evaluates the optional systemd-tmpfiles age rule as a residual
safety net. Deferred to #7004: per-run private scratch roots (`TMPDIR`
redirection), which would make the whole class un-attributable-by-accident
rather than cleaned-up-by-design.

## Research Insights

### Premise Validation (Phase 0.6)

- `#10017` OPEN — target issue live. `#9341` OPEN (deferred class-b census
  pay-down; its named candidates all sit inside this plan's enumerated census
  dirs — dispositions required, `Closes #9341` if the census covers them).
  `#7004` OPEN — per-run scratch roots, explicitly deferred out of scope.
  `#6760` OPEN — skill-security-scan runtime dirs, needs a retention policy,
  deliberately NOT absorbed. `#6752` OPEN — three class-c/d sites inside the
  accepted population; census must disposition each. `#6734` CLOSED (second-
  EXIT-trap sweep of class-c/d + 121 class-b files — precedent for paying
  down the accepted population when a site runs on a long-lived host).
  `#9534` CLOSED.
- Cited artifacts verified on-disk: `scripts/lint-trap-tempfile-ownership.py`
  (with `--census`, highwater ratchet = 70), the 2026-10-11 workflow-issues
  learning file, `tests/scripts/lib/git-data-birth-readiness-gate.sh:1440`
  (the sole `rung2-archive.*` producer), `scripts/soleur-tmp-purge.sh`,
  `plugins/soleur/scripts/lib/tmp-classify.sh`, `scripts/tmpfs-guard.sh`
  (Reapers 1-3 + count alarm), `scripts/lib/scratch-root.sh`
  (`soleur_scratch_session_begin`), `scripts/tmpfs-guard.{service,timer}`,
  runbook `knowledge-base/engineering/operations/runbooks/tmpfs-guard-install.md`.
- Mechanism-vs-ADR check: `trap … EXIT`/`RETURN` ownership is the
  ADR-129-sanctioned mechanism — its "accepted population" clause carries an
  explicit upgrade trigger ((a) site starts running on a long-lived host),
  which this issue IS (operator workstation, no runner teardown, ~2k
  entries/hour). Moving the rung2-archive dir under an owned/reaped root or
  deleting it at the producer is ADR-250-native. systemd-tmpfiles is not in
  the ADR corpus's rejected set; `soleur-tmp-purge.sh`'s own contract already
  delegates bare `tmp.*` to "systemd-tmpfiles' 30d/10d aging". No stale
  premise found.

### Mechanism Minimality (Phase 0.6b)

**Property list**

1. Session-scoped `mktemp` artifacts created by agent-session scripts/hooks
   are removed by their producer's exit path — the `tmp.*` file class stops
   growing during pipelines.
2. `rung2-archive.*` dirs stop accumulating one-per-gate-call on the
   operator host (either reaped at source or routed under an owned root).
3. A residual safety net reaps stragglers the producers miss.

**Mechanism → property coverage**

| Proposed mechanism | Property | Already covered by? |
|---|---|---|
| Per-site owning trap / explicit removal (census) | 1 | Lint rule (c) gates NEW lines only; the accepted population is unfenced debt — gap confirmed |
| Producer-side cleanup (or owned-root move) at `git-data-birth-readiness-gate.sh:1447` | 2 | Reaper 3 reaps prefix class only past a 24h floor → steady-state ~1 day's accumulation; producer-side removal is the gap |
| systemd-tmpfiles age rule (optional) | 3 | Count alarm detects only; Reaper 2 is size-gated; Reaper 3 never touches unattributable `tmp.*` — residual class has no reaper. Optional per issue |

**Cut list:** none — all three issue-named mechanisms map to uncovered
properties. #7004 per-run scratch roots cut (deferred upstream, not this
plan's invention).

### Relevant file paths

- `scripts/lint-trap-tempfile-ownership.py` — authoritative census
  (`--census`; class-b population = 70 tracked `*.sh` files with `mktemp`
  and zero owning trap; rules (a) subshell-append, (c) new-line gate,
  (d)/(e) non-shell allocation). `scripts/lint-trap-tempfile-ownership.highwater`
  ratchets the population — it must DROP by the number of files this fix
  removes from the population.
- `tests/scripts/lib/git-data-birth-readiness-gate.sh:1440` —
  `_git_data_rung2_hash_at_sha()`: single producer of `rung2-archive.*`;
  `_tmp` is used ONLY inside the function (archive-extract → link-sweep →
  hash) — nothing downstream consumes it; called once, at :1911, inside
  `$( )`. Carries a `lint-trap-ownership: ok` annotation trading a bounded
  leak against an unprovable `rm -rf` operand, plus a `.soleur-owned`
  marker write for Reaper 3.
- Session-scoped untrapped sites already surfaced (census seeds, NOT the
  full list — the lint census is authoritative):
  `.claude/hooks/git-commit-secret-scan.sh:194-196` (3 allocs, runs per
  commit attempt), `.claude/hooks/pre-merge-auto-close-scan.sh:141,143`
  (2 bare `mktemp`), `.claude/hooks/ship-operator-step-gate.sh:109`,
  `.claude/hooks/ship-soak-followthrough-gate.sh:106,161,216`,
  `.claude/hooks/memory-backstop-mutation-battery.sh:22,59`,
  `scripts/watch-live-verify-pass.sh:103` (watcher — matches issue's
  "ship-phase watchers" evidence), `scripts/audit-bot-codeql-coverage.sh:330`,
  `plugins/soleur/scripts/taste-profile-update.sh:171` (allocates beside
  the profile, not /tmp — verify),
  `plugins/soleur/scripts/sync-pr-behind.sh:199,350` (already annotated;
  leaked file evidence was a resync-script COPY staged by a consumer,
  verify the consumer).
- DO-NOT-TOUCH landmines (verified by #6752): `.claude/hooks/lib/session-state.sh`
  (fd-held locks; trap never armed at source time; ~34 hooks source it —
  a speculative trap has enormous blast radius) and
  `apps/web-platform/infra/workspaces-cutover.sh` (trap would clobber the
  LUKS rollback path on an irreversible cutover). #6752's three sites
  (`scripts/learning-retrieval-bench.sh`, `scripts/weekly-analytics.sh`,
  `plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh`)
  are in the enumerated census dirs — disposition each (fix if
  session-run, annotate if bounded).
- Reclamation machinery (already shipped, do not rebuild):
  `scripts/tmpfs-guard.sh` Reaper 3 + `scripts/soleur-tmp-purge.sh` +
  `plugins/soleur/scripts/lib/tmp-classify.sh` (`prefix:rung2-archive`
  class exists — keep it; stragglers and other producers still classify).
- #9341 named candidates to disposition: `plugins/soleur/skills/community/scripts/{x,discord,linkedin,bsky}-setup.sh`,
  `scripts/audit-bot-codeql-coverage.sh`,
  `plugins/soleur/skills/skill-security-scan/scripts/run-self-test.sh`,
  `scripts/lint-rule-bodies.py`, `scripts/lint-workflow-local-action-checkout.py`,
  and the remainder of the `--census` population.

### Institutional learnings applied

- `2026-05-18-sweep-class-fixes-grep-enumerated-not-intuited`: the census
  grep/lint output IS the work checklist — enumerate authoritatively,
  re-run after batches, done when zero. Applies directly to the census
  phase AC.
- Same learning, Gap 3: `set -euo pipefail` + tail-of-script cleanup
  leaves the artifact on ANY mid-script abort — only a trap covers the
  window. Prefer `trap … EXIT` (top-level scripts) or `trap … RETURN`
  (functions/sourced libs) over appending an `rm` at the tail.
- `2026-10-11` learning (this issue): mitigation was a manual age-filtered
  sweep; producers still leak — this plan is the producer-side fix.
- ADR-129 subtleties for the census: (a) a `trap … RETURN` counts as
  ownership; (b) a SOURCED library must NOT install `trap … EXIT` (it
  would REPLACE the caller's) — annotate or restructure instead; (c) a
  second `trap … EXIT` in one script silently replaces the first — extend
  an existing cleanup function instead.
- ADR-250: marker (`pid=`/`schema=1`/`ns=`) + `soleur-run.<pid>.*` schema
  dirs reap directly on tmpfs; marker-only dirs quarantine.

### Research decision

No external research — internal shell-tooling fix on a repo that already
carries the lint, classifier, reapers, ADRs, and a measured incident
record. Community-discovery stack check: no uncovered stack signatures
(pubspec/Cargo/go.mod/etc. absent) — skipped. Functional-overlap agent
spawn: no Task/Agent tool available in this subagent context — the
surface is proprietary pipeline scripts, overlap implausible; recorded,
not blocking.

## Problem Statement / Motivation

On 2026-10-11 the tmpfs-guard count alarm fired: `/tmp` held ~7,710
top-level entries at 34% usage — a **count-shaped** leak that the
size-based reaper cannot reclaim (its floor deliberately keeps sub-MB
entries out of scope) and that Reaper 3 cannot reach (bare `tmp.*` files
are the protected/unattributable class by design — `soleur-tmp-purge.sh`
explicitly delegates them to systemd-tmpfiles aging, which on the
measured host either does not run on tmpfs `/tmp` or ages far too slowly:
the leak grew at ~2,000 entries/hour). Sampling attributed ~7,000 `tmp.*`
files to pipeline tooling — ship-phase resync scripts, drafted commit
messages, hook scratch — created in ~6/sec bursts during skill runs, plus
~650 `rung2-archive.*` dirs (one per `_git_data_rung2_hash_at_sha` call).

Every producer is a `mktemp` call with no owning cleanup trap, inside the
population ADR-129 accepted *for short-lived CI scripts*. The defect
premise changed: these scripts now run inside long-lived agent sessions
on the operator workstation — exactly the ADR-129 upgrade trigger (a).
Unbounded, top-level entry exhaustion kills running sessions
mid-pipeline; the manual age-filtered sweep (the only mitigation to date)
reclaims a symptom while the producers continue.

## Proposed Solution

Producer-side cleanup, in four phases, driven by an authoritative census
rather than intuition (learning `2026-05-18`).

### Phase 1 — Authoritative census + disposition ledger

1. Extend `scripts/lint-trap-tempfile-ownership.py` with a population-list
   mode (e.g. `--census-files`) that prints every class-b (`*.sh`,
   `mktemp`, zero `trap … EXIT|RETURN`) and rule-e (literal `/tmp`|
   `/var/tmp` base) member path — the population must be printed by the
   SAME implementation that counts it; a parallel grep defines a second
   census. Extend `scripts/lint-trap-tempfile-ownership.test.sh` for the
   new mode.
2. Run it against `plugins/soleur/**`, `scripts/**`, `.claude/hooks/**`
   (the issue's enumerated scope; the rung-2 producer under `tests/` is
   pulled in by direction 2 regardless) and write the per-file
   disposition ledger to
   `knowledge-base/project/specs/feat-one-shot-10017-mktemp-tmp-leak/mktemp-census.md`:
   each file gets run-context (agent-session / CI-only / operator-manual /
   sourced-library) + disposition (`trap-EXIT`, `trap-RETURN`,
   `extend-cleanup`, `annotate-bounded`, `do-not-touch`) + one-line basis.
   Mandatory rows: the six #9341-named candidates, #6752's three sites,
   and the two landmines (`session-state.sh`, `workspaces-cutover.sh` —
   `do-not-touch`, carrying #6752's verified rationale verbatim).

### Phase 2 — Session-scoped trap sweep

**Amendment (work-phase, 2026-10-12):** the issue's enumerated scope
(`plugins/soleur/**`) includes SKILL.md/references prose that INSTRUCTS
the agent to run `mktemp` — the incident's own evidence (28–34KB
resync-script copies, drafted commit messages) is prose-instructed
allocation, not tracked scripts. `--census-files` cannot see `.md` call
sites, so the ledger carries a second section enumerating them by grep;
each gets `add-cleanup-instruction` (post-consumption `rm` / paired
`trap … EXIT` where the artifact is same-call) or `bounded-persistence`
(cross-call artifacts whose consumption point is recorded). Five seed
`.claude/hooks/*.sh` files the plan listed as "untrapped" already carry
owning `trap … EXIT` — the census is authoritative, they are
already-clean and need no edit.

For every census row dispositioned `trap-*`:

- Top-level script: single owning `trap 'rm -rf "$tmp"' EXIT` (or `rm -f`
  for files) registered at the allocation site — and where the script
  already registers an EXIT trap, EXTEND that cleanup path instead (a
  second `trap … EXIT` silently replaces the first — ADR-129).
- Function / sourced library: `trap … RETURN` (counts as ownership per
  ADR-129) or per-call-site registration in the PARENT scope — never an
  EXIT trap that would clobber the consumer's.
- `rm` operand provably absolute: assert the path is `/*`-rooted before
  delete (the `assert_fixture_dir` idiom) — `mktemp -t` output is only
  absolute when `TMPDIR` is.
- Where the allocation already carries `lint-trap-ownership: ok` and the
  fix makes it owned, remove the now-stale annotation.
- Each fixed file gets a residue assertion in its own `*.test.sh` (run
  the producer under a private `TMPDIR`, assert the base gains zero
  entries — the `test-scratch-residue.sh` delta-arm shape), and runnable
  producers join that suite's leaf registry where the harness supports it.
  Any owning EXIT trap in a new/edited `.test.sh` goes BEFORE
  `source test-helpers.sh` (Sharp Edge #8644 — lint rule (c) and the
  helper's own fixture root both bind there).

### Phase 3 — `rung2-archive.*` producer fix

`tests/scripts/lib/git-data-birth-readiness-gate.sh:1440` —
`_git_data_rung2_hash_at_sha()`: the extracted tree is consumed ONLY
inside the function (verified: single caller at :1911, no downstream
path references). Replace the bounded-leak trade with an owning
`trap … RETURN` that asserts `$_tmp` is absolute before `rm -rf` —
covering every return path including the symlink-refusal early return.
Before writing the fix, run a 3-line bash probe confirming a `RETURN`
trap set inside a function executes when that function runs under
`$( )` command substitution (the :1912 call shape) — Sharp Edge
#9045: trap semantics are measured, never reasoned. The trap body MUST
self-disarm (`trap - RETURN` inside the handler): a `RETURN` trap is
NOT scoped to the function that set it — it fires on every subsequent
function return in the same shell, so an un-disarmed copy re-runs
`rm -rf "$_tmp"` (or worse, re-reads a reassigned `$_tmp`) for the rest
of that shell's life.
Drop the `.soleur-owned` marker write (a dir removed at return needs no
post-mortem attribution) and rewrite the annotation comment so it no
longer claims the dir "deliberately outlives the call". Keep
`prefix:rung2-archive` in `tmp-classify.sh` — stragglers and any other
producer still classify. Extend `tests/scripts/test-git-data-birth-readiness-gate.sh`
with a no-residue assertion on the hash path.

### Phase 4 — Belt-and-braces residual reaper (optional per issue)

Ship optional systemd **user** units `scripts/soleur-tmp-purge.service` +
`scripts/soleur-tmp-purge.timer` running `soleur-tmp-purge.sh --apply`
(+ `--drain`) on a daily cadence, mirroring the `tmpfs-guard.{service,timer}`
optional-unit precedent, and extend runbook
`knowledge-base/engineering/operations/runbooks/tmpfs-guard-install.md`
with install steps + a note on the systemd-tmpfiles alternative and why
attribution-based reclamation was preferred over a blanket `/tmp` age
rule (the #6991 measurement: age/size cannot separate leaked artifacts
from authored work on a shared base; the classifier can, for the classes
it owns). Verified at deepen time: `e`/`d` lines accept glob paths but
an `e` rule cleans the matched directory's *contents* by age — the
`rung2-archive.*` entry shells would remain, so a literal tmpfiles
route cannot even express the count-shaped fix; the purge timer is the
correct belt. Recorded as a pending technical ruling in
`decision-challenges.md`.

### Phase 2b — Prose-instructed allocation sweep (amendment)

For every `mktemp`-instructing line in `plugins/soleur/**/*.md` and
`.claude/hooks/*.md` (enumerated in the ledger's prose section): where the
artifact is consumed within the workflow, amend the instruction so the
consuming step also removes it (`rm -f "$f"` after `--body-file`/`cp`/read),
or pair the allocation with a `trap … EXIT` where same-shell semantics are
documented; where the artifact must persist past its producing call
(detached-run logs, cross-call body files), record `bounded-persistence`
with the consumption point. Never weaken a fenced example's own trap
guidance.

### Phase 5 — Ratchet + verification

- Decrement `scripts/lint-trap-tempfile-ownership.highwater` by exactly
  the number of files leaving the class-b population (the lint's
  merge-base delta check enforces arithmetic honesty).
- `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater`
  green; census count printed in the PR body.
- PR body: `Closes #10017`; `Closes #9341` per the disposition-ledger
  coverage (decision-challenges row); `Refs #6752 #6760 #7004`.

## Technical Considerations

- **ADR-129 upgrade trigger (a) is the authority for this sweep.** The
  accepted class-b population is fenced for NEW lines, not fixed
  file-by-file — but criterion (a) ("starts running on a long-lived
  host") is precisely the operator-workstation/agent-session context.
  The fix does not amend the ADR; it applies its own escape clause.
- **One EXIT trap per shell** — extending an existing cleanup function
  is the fix when a script already traps; registering a second
  `trap … EXIT` silently replaces the first.
- **Command substitution runs in a subshell** — helpers that build
  cleanup lists must register in the PARENT scope (rule (a) class).
- **Sourced libraries never install `trap … EXIT`** — the trap replaces
  the caller's; use RETURN-scoped ownership or caller-side registration.
- **`rm` operands must be provably absolute** — `mktemp -t` resolves
  under `TMPDIR`; an inherited relative `TMPDIR` yields a relative path.
  Assert `/*` before `rm -rf` (or hold the fd, per
  `browser-snapshot-credential-guard.test.sh:153-158` precedent).
- **`tmp.*` is a protected class in `tmp-classify.sh`** — no reaper will
  ever move bare `tmp.*` files; only producer-side removal shrinks them.
- **`#6752` landmines are load-bearing do-not-touch** — `session-state.sh`
  (fd-held locks, never-armed trap, ~34 consumers) and
  `workspaces-cutover.sh` (LUKS rollback path). The census ledger records
  them `do-not-touch` with the verified rationale.
- **Boundary with #6760** — `skill-security-scan` *runtime dirs* need a
  retention policy (#6760, out of scope); `run-self-test.sh`'s bare
  `mktemp` file IS in scope. Different artifacts, different fix.
- **NFR:** none new — performance (cleanup is trivial per-call), no new
  attack surface; removes a shared-fs exhaustion vector.

## User-Brand Impact

- **If this lands broken, the user experiences:** agent sessions dying
  mid-pipeline when `/tmp` entry-count exhausts — failed commits, lost
  in-flight work; or, if a cleanup path is wrong, deleted scratch still
  in use (worse: a hook that deletes an artifact a later gate reads).
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  no new exposure — the change deletes operator-own scratch earlier than
  before; no data crosses a trust boundary.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal dev-host tooling —
  the blast radius is the operator's own `/tmp`, and the failure modes
  are workflow interruption, not user-facing artifacts or data.

## Infrastructure (IaC)

The optional Phase-4 units target the **operator workstation** — the same
non-Terraform surface as the existing optional `tmpfs-guard.{service,timer}`
user units (precedent: runbook `tmpfs-guard-install.md`). No Terraform
root manages this host; no `apps/*/infra/` file is touched. The
deliverable is repo files + runbook install steps, identical in shape to
the shipped precedent — `hr-all-infrastructure-provisioning-servers` is
satisfied because nothing is provisioned anywhere new.

## Observability

```yaml
liveness_signal:
  what: "tmpfs-guard count watermark — growth-above-floor alarm on /tmp top-level entries"
  cadence: "every 5 min via the optional tmpfs-guard.timer (installed per runbook on the operator host)"
  alert_target: "~/.local/state/soleur/tmpfs-guard-alarms.log (operator-visible alarm file, 200-line cap) + guard log"
  configured_in: "scripts/tmpfs-guard.sh (count-signal block, ~:560-640) + scripts/tmpfs-guard.timer"
error_reporting:
  destination: "tmpfs-guard alarm_record → $HOME/.local/state/soleur/tmpfs-guard-alarms.log"
  fail_loud: "alarm line '$TMP_ROOT grew to N top-level entries (+growth above watermark, trigger 5000)'"
failure_modes:
  - mode: "census regrowth — a new session-run producer lands post-fix without a trap"
    detection: "class-b highwater ratchet goes RED in CI (count can only shrink; a raise needs a PR-body reason)"
    alert_route: "CI lint-bot-statuses + count alarm on the host"
  - mode: "a fixed site keeps leaking (trap clobbered by a later trap registration)"
    detection: "per-file residue assertion in its own .test.sh + scratch-residue leaf"
    alert_route: "suite failure, CI"
logs:
  where: "~/.local/state/soleur/tmpfs-guard-alarms.log + tmp-purge ledger ~/.local/state/soleur/tmp-purge-ledger.log"
  retention: "200-line cap / append ledger"
discoverability_test:
  command: bash scripts/tmp-leak-census-probe.sh
  expected_output: ratchet-ok
```

`scripts/tmp-leak-census-probe.sh` is committed in this PR (a ~10-line
script: run `--census`, read the highwater's first numeric token, print
`ratchet-ok` iff census ≤ highwater). The wrapped form is required —
preflight Check 10 rejects any `|`, `;`, `&`, `<`, `>`, `$` or backtick
in the command string, so the comparison cannot be inlined (Sharp Edge
#6500/PR #8488).

## Guard Contract

The deliverable adds one new guarded mechanism — the census file-list
mode on the existing lint (the lint itself is the guard; the new mode is
a second read on the same predicate). The trap sweep and highwater
decrement ride existing guards, so no second entry.

### Guard 1 — lint `--census-files` population listing

**Property.** The emitted file list is exactly the class-b / rule-e
population the counting census derives — printed by the same
implementation, so list and count can never diverge.

**Assembly.** `census_all`/`Tree` in
`scripts/lint-trap-tempfile-ownership.py` — the single chokepoint every
population number already flows through (`--census`, `--census-detail`,
`--check-highwater`); the listing mode iterates the same per-file
predicate results rather than re-grepping.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Add an untrapped `mktemp` line to a tracked `*.sh` member — the file must appear in `--census-files` output | RED if absent |
| 2 | Return an empty file list while the count stays non-zero (dispatch vacuity — a mode that prints nothing and exits 0) | RED — suite asserts count(list) == `--census` count |
| 3 | Give a SECOND `*.sh` file an owning `trap … RETURN` — both the count and the list must drop it, not just the first | RED if it remains |
| 4 | Mutate the SUITE: assert a known-fixture member path is listed (harness must-PASS on a member that differs from the canonical bad fixture — e.g. an annotated-escape file, which the census counts regardless of escape) | PASS, guards harness vacuity |
| 5 | Edit the class-b predicate in one direction only (e.g. drop the `RETURN` alternative from `TRAP_EXIT`) — list and count must move together | RED if they diverge |

**Anchor.** The list's integrity derives from the same `git ls-files`
tree walk the count uses — a weakening must corrupt the shared
`census_all` pass, which the existing `--check-highwater` merge-base
delta check independently bounds.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.
The mechanical UI-surface override did not fire (no `components/**/*.tsx`,
`app/**/page.tsx`, `app/**/layout.tsx` in Files to Create).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Census `mktemp` call sites under `plugins/soleur/**`, `scripts/**`, `.claude/hooks/**` and add `trap 'rm -rf \"$tmp\"' EXIT` where the artifact is session-scoped" [#10017] | Phase 1 census + ledger; Phase 2 trap sweep; Files-to-Edit census set | mapped |
| 2 | "Make the rung-2 archive step clean up (or move under a reaped dir)" [#10017] | Phase 3 — `_git_data_rung2_hash_at_sha` RETURN-trap fix | mapped |
| 3 | "Consider a systemd-tmpfiles age rule (`d /tmp` / `e /tmp`) as a belt-and-braces reaper for anything missed" [#10017] | Phase 4 — optional user units + runbook; tmpfiles documented as the alternative | mapped — "consider" is satisfied by the evaluated decision record |
| 4 | "Keep #7004 (tmpfs-guard per-run scratch roots) deferred — out of scope" [brief] | Non-Goals entry | mapped |
| 5 | "if this work covers its scope, carry `Closes #9341` into the PR body" [brief] | Phase 5 PR-body requirement + census-ledger AC covering all named candidates | mapped |
| 6 | "#6760 … needs retention policy, not trap" / "do NOT absorb" [brief] | Non-Goals + Technical-Considerations boundary note | mapped |
| 7 | "#6752 (class-c/d tempfile-ownership sites) — evaluate in census whether they are in the enumerated scope" [brief] | Phase 1 mandatory ledger rows | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Census + disposition ledger (`mktemp-census.md`) | "Census `mktemp` call sites under `plugins/soleur/**`, `scripts/**`, `.claude/hooks/**`" | asked |
| `--census-files` lint list mode | — | inferred — the enumeration must come from the same implementation that counts (learning `2026-05-18`: grep-enumerated, not intuited); no existing flag prints members |
| Per-site owning traps (Phase 2) | "add `trap 'rm -rf \"$tmp\"' EXIT` where the artifact is session-scoped" | asked |
| `rung2-archive` RETURN-trap fix (Phase 3) | "Make the rung-2 archive step clean up (or move under a reaped dir)" | asked |
| `soleur-tmp-purge.{service,timer}` + runbook (Phase 4) | "Consider a systemd-tmpfiles age rule … as a belt-and-braces reaper for anything missed" | asked — "consider" discharges via evaluated alternative, not mandatory adoption |
| `tmpfs-guard-install.md` runbook edit | — | inferred — install path for the optional units; precedent requires it live in the runbook |
| Highwater decrement + `--check-highwater` | — | inferred — the ratchet is the only thing that keeps the pay-down paid; fixing files without lowering it leaves the lint asserting a stale ceiling |
| Residue assertions in per-file suites + `test-scratch-residue.sh` leaves | — | inferred — repo convention (cq-write-failing-tests-before) + the measured-canary precedent #9341 invokes |
| `do-not-touch` ledger rows (session-state.sh, workspaces-cutover.sh) | — | inferred — #6752 verified a speculative fix at either site is worse than the leak; recording prevents a repeat attempt |

### Split Assessment

- Subsystems touched: 4 — `plugins/soleur`, `scripts`, `.claude`, `tests`
- Planned files: ~14 named + the session-scoped subset of the 70-file
  census (estimate ≤ 30 total) | Estimated changed lines: ~400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800
  estimated lines — subsystem roots and file count both sit AT the
  boundary; per-file deltas are 1–10 lines, so estimated lines stays
  well under 800
- Recommendation: single PR — every edit serves one property (owning
  cleanup); a split would only separate the census from its dispositions

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10017-mktemp-tmp-leak/mktemp-census.md`
  — the disposition ledger (Phase 1 output)
- `scripts/tmp-leak-census-probe.sh` — the Check-10-safe observability
  probe (see `## Observability`)
- `scripts/soleur-tmp-purge.service`, `scripts/soleur-tmp-purge.timer`
  — optional user units (Phase 4)

## Files to Edit

- `scripts/lint-trap-tempfile-ownership.py` — `--census-files` list mode
- `scripts/lint-trap-tempfile-ownership.test.sh` — list-mode coverage
- `scripts/lint-trap-tempfile-ownership.highwater` — ratchet decrement
- `tests/scripts/lib/git-data-birth-readiness-gate.sh` — rung2-archive fix
- `tests/scripts/test-git-data-birth-readiness-gate.sh` — residue assertion
- `tests/scripts/test-scratch-residue.sh` — leaf-registry extension for
  runnable fixed producers
- `knowledge-base/engineering/operations/runbooks/tmpfs-guard-install.md`
  — Phase-4 install steps + tmpfiles-alternative note
- Census-driven set (seeds confirmed session-scoped at plan time; the
  ledger may add or drop rows): `.claude/hooks/git-commit-secret-scan.sh`,
  `.claude/hooks/pre-merge-auto-close-scan.sh`,
  `.claude/hooks/ship-operator-step-gate.sh`,
  `.claude/hooks/ship-soak-followthrough-gate.sh`,
  `.claude/hooks/memory-backstop-mutation-battery.sh`,
  `scripts/watch-live-verify-pass.sh`,
  `scripts/audit-bot-codeql-coverage.sh`,
  `plugins/soleur/skills/community/scripts/{x,discord,linkedin,bsky}-setup.sh`,
  `plugins/soleur/skills/skill-security-scan/scripts/run-self-test.sh`,
  `plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh`,
  `scripts/learning-retrieval-bench.sh`, `scripts/weekly-analytics.sh`,
  `plugins/soleur/scripts/taste-profile-update.sh`,
  `scripts/lint-rule-bodies.py`, `scripts/lint-workflow-local-action-checkout.py`
- Each fixed file's own `*.test.sh` companion (residue assertion)

## Open Code-Review Overlap

2 open scope-outs touch files in `## Files to Edit`:

- `#7208` (memory backstop post-merge hardening) names
  `.claude/hooks/memory-backstop-mutation-battery.sh`. **Acknowledge** —
  different concern (backstop hardening, not tempfile ownership); the
  trap addition is ~3 lines at the allocation sites and does not collide
  semantically. Implementer: if #7208 lands first, rebase the edit.
- `#3595` (bot-workflow YAML-aware enumeration) names
  `scripts/audit-bot-codeql-coverage.sh`. **Acknowledge** — orthogonal
  refactor of `enumerate_workflows()` vs a trap at `:330`; no semantic
  overlap, different review cycle.

## Acceptance Criteria

<!-- headless run: no founder_check block per plan-founder-check.md -->

- [ ] `python3 scripts/lint-trap-tempfile-ownership.py --census-files` (or
  the shipped list-mode flag) prints the class-b + rule-e membership, and
  its suite asserts list-count == `--census` count.
- [ ] `mktemp-census.md` exists under the spec dir with a disposition row
  for EVERY class-b member under `plugins/soleur/**`, `scripts/**`,
  `.claude/hooks/**`, plus mandatory rows for the six #9341 candidates,
  the three #6752 sites, and both landmines (`do-not-touch` + rationale).
- [ ] Every file dispositioned `trap-*` in the ledger carries an owning
  `trap … EXIT` or `trap … RETURN` (or parent-scope registration) — no
  file gains a second EXIT trap.
- [ ] The class-b census count drops by the number of files fixed, and
  `scripts/lint-trap-tempfile-ownership.highwater` is decremented to
  match; `--check-highwater` is green.
- [ ] `_git_data_rung2_hash_at_sha` leaves no `rung2-archive.*` entry in
  its TMPDIR base on success OR on any error path (residue assertion in
  `tests/scripts/test-git-data-birth-readiness-gate.sh`).
- [ ] Each fixed file's own test suite gains a residue assertion (private
  `TMPDIR`, zero new base entries) where the harness supports it; all
  companion suites pass.
- [ ] `scripts/soleur-tmp-purge.{service,timer}` exist and the runbook
  documents install + the evaluated tmpfiles alternative — OR the
  recorded ruling reverses to a scoped tmpfiles rule with equal coverage.
- [ ] No edit touches `.claude/hooks/lib/session-state.sh` or
  `apps/web-platform/infra/workspaces-cutover.sh`.
- [ ] No edit touches `skill-security-scan` runtime-dir creation paths
  (#6760 boundary) — only `run-self-test.sh`'s bare tempfile.
- [ ] PR body carries `Closes #10017` and — per the decision-challenges
  ruling — `Closes #9341`.

## Test Scenarios

- Given a session-scoped script with a new owning trap, when it exits
  normally under a private `TMPDIR`, then the base gains zero entries
  (`unit`, per-file `.test.sh` residue arm).
- Given the same script killed via SIGTERM mid-run, when the trap is
  armed, then the artifact is still removed — kill leaves at most the
  pre-trap window (`unit`).
- Given `_git_data_rung2_hash_at_sha` called inside `$( )`, when it
  returns `OK|<sha>` or any `RUN_HASH_UNCOMPUTABLE` path, then no
  `rung2-archive.*` dir persists in the base (`unit`,
  `test-git-data-birth-readiness-gate.sh`).
- Given a `*.sh` file that already registers `trap … EXIT`, when the
  sweep adds cleanup, then it extends that function rather than adding a
  second `trap … EXIT` line (grep assertion per file) (`unit`).
- Given `--census-files` output, when piped to `wc -l`, then it equals
  `python3 scripts/lint-trap-tempfile-ownership.py --census` (`unit`,
  lint suite).
- Given the merged tree, when `python3 scripts/lint-trap-tempfile-ownership.py
  --check-highwater` runs in CI, then exit 0 (`integration`).

## Success Metrics

- Operator-host `/tmp` top-level `tmp.*` entry count stops growing during
  pipeline runs (post-merge observation vs the ~2,000/hour baseline).
- `rung2-archive.*` top-level count returns to ~0 rather than ~325/day.
- Class-b census: 70 → (70 − fixed-count), ratcheted down.

## Dependencies & Risks

- **Risk — trap clobbering.** A site that adds a second `trap … EXIT`
  silently disarms the first. Mitigation: per-file grep assertion +
  ADR-129 extend-cleanup rule; census ledger records which files already
  trap.
- **Risk — deleting a live artifact.** A trap fires on exit; an artifact
  a LATER process consumes (books file, deliverable dir) must stay.
  Mitigation: the ledger's run-context column; dispositions
  `annotate-bounded`/`do-not-touch` exist precisely for these
  (`file-upstream-ask-8160.sh` output-is-deliverable precedent).
- **Risk — scope creep into #6752/#6760/#7004 territory.** Mitigation:
  Non-Goals + mandatory ledger rows bound the census to the enumerated
  dirs.
- **Dependency — #9341 closure** depends on the ledger covering all its
  named candidates (scope ruling recorded in decision-challenges.md).

## Non-Goals

- #7004 per-run private scratch roots (`soleur_scratch_session_begin`
  adoption) — deferred upstream; this plan cleans producers, not the
  TMPDIR topology.
- #6760 `skill-security-scan` runtime-dir retention policy.
- Fixing bounded CI-only class-b members outside the enumerated dirs —
  dispositioned `annotate-bounded` in the ledger, not edited.
- Promoting the advisory lint to blocking (an ADR-129 deferred follow-up
  with merge-queue blast radius).

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Blanket `systemd-tmpfiles` `d /tmp`/`e /tmp` age rule | The #6991 measurement: on a shared `/tmp`, age/size cannot separate leaked artifacts from authored work (~1,500 false candidates in a dry-run); the count-shaped class needs producer-side ownership |
| Widen Reaper 2 to count-triggered deletion | Same rejected trade — `tmp.*` is protected precisely because it is unattributable; the alarm is deliberately detect-only |
| Adopt `soleur_scratch_session_begin` per-run roots everywhere | #7004, explicitly deferred — zero adopters today; producer traps shrink the class without a TMPDIR migration |
| Delete `rung2-archive` dirs via purge-floor reduction | Lowering `TMP_CLASSIFY_AGE_FLOOR_MIN` shortens but does not close the window, and it loosens every class's floor, not just this one |
| Fix all 70 class-b files | #6752 documents sites where a trap is actively harmful; the ADR accepts bounded CI-only sites — the sweep is scoped to session-scoped members of the enumerated dirs |

## References

- Issue: #10017 (this work), #9341 (class-b pay-down), #7004 (scratch
  roots — deferred), #6760 (retention policy — excluded), #6752 (three
  remaining sites + two landmines), #6734 (sweep precedent)
- ADR-129 (cleanup ownership), ADR-250 (ownership-keyed reclamation),
  ADR-176 (plan checkpoints)
- Learning `2026-10-11` (the incident), `2026-05-18` (grep-enumerated
  sweeps)
- `scripts/lint-trap-tempfile-ownership.py`, `scripts/tmpfs-guard.sh`,
  `scripts/soleur-tmp-purge.sh`, `plugins/soleur/scripts/lib/tmp-classify.sh`
