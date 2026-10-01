---
title: "fix: stop dev-machine disk leaks from test/tooling scratch dirs and package caches"
date: 2026-10-01
slug: fix-dev-machine-disk-leak-scratch-and-cache-cleanup
branch: feat-one-shot-disk-leak-tmp-cleanup
issue: 7004
type: fix
lane: cross-domain
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-10-01. **Method:** halt gates 4.6-4.11 run mechanically, plus targeted
live verification of every load-bearing citation (the plan-review panel of seven agents already
supplied the research fan-out; a second blanket fan-out would duplicate it).

### Key Improvements

1. Corrected a wrong consumer: the registry list is read by `scripts/test-all.sh` (line 917), not a
   non-existent `scripts/test-all-affected.sh`.
2. Verified every function the plan builds on exists (`tc_marker_owner_pid`, `tc_tree_has_live_handles`,
   `tc_classify_entry`, `soleur_scratch_mark_owned`), that the TTL drain seam
   `SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN` exists (and added an `=0` arm), and that both `bunfig.toml`
   preloads sit in the `[test]` section.
3. All cited rule ids resolve to active AGENTS.md rules; guard-contract lint, infra-human-step lint and
   markdownlint are green; no PAT-shaped tokens; `discoverability_test.command` is allowlisted, shell-free
   and finishes well inside the 15 s cap.

### New Considerations Discovered

- No UI surface, no `.tf`/migration/cloud-init/compose file, no regulated data and no serving-surface
  downtime: Phases 4.9 (wireframe), 4.10 (encryption posture), 4.55 (downtime) and the GDPR/IaC gates
  pass by non-trigger. Scratch directories and package caches are developer-host files, not a store
  the plan introduces.

## Overview

On 2026-10-01 a 150G developer root disk reached 95%. The /var/tmp backlog (~33G, ~81k entries, all
created 2026-09-17) predates PR #8738 (ADR-250, merged 2026-09-25), which already landed the
ownership-keyed reclamation machinery: `scripts/lib/scratch-root.sh`, `scripts/soleur-tmp-purge.sh`,
`plugins/soleur/scripts/lib/tmp-classify.sh`, `scripts/tmpfs-guard.sh` Reaper 3, and the session-start
sweep. `scripts/test-all.sh` and `apps/web-platform/infra/run-registered-suites.sh` already open a per-run `soleur-run.<pid>.*` root and
delete it at exit. This plan therefore plans only the **delta** that measurement shows is still leaking:

1. **Direct runner invocations** (an agent or developer running one `bun test` / `vitest` / `pytest` /
   `.test.sh`, the documented inner loop) have no per-process root. Measured on current main: six TS
   suites leak every `mkdtempSync` dir they create (see Research Insights, Measured baseline).
2. **The largest bytes have no committed writer.** `vac<pid>`, `td-<pid>`, `perf-<pid>`, `mut<pid>`,
   `sdkprobe.*` match zero lines in the tree. They are ad-hoc full-repo copies built by review and
   mutation *seat agents* (`td` = the test-design reviewer seat) following prose in
   `plugins/soleur/skills/review/SKILL.md` and `work/SKILL.md`. Prose briefs are not enforced, and the
   classifier treats those names as unattributable, so even the shipped purge retains them.
3. **Trap-clobbered and SIGKILLed allocations** in committed suites (incident sandbox, mutation
   batteries) are not marked owned at creation, so no reaper can claim them.
4. **Caches** (`~/.npm`, `~/.cache/.bun`, `~/.cache/debuginfod_client`, `~/.local/share/mise`,
   `~/.codex/.tmp/marketplaces`) are not written by any Soleur script beyond default package-manager
   behavior. The plan reports and documents them; it does not invent controls (Cut List).

## Research Reconciliation — Spec vs. Codebase

| Task claim | Reality (measured) | Plan response |
|---|---|---|
| "Add a shared helper e.g. scripts/lib/tmpdir.sh that creates the temp root and registers the trap" | `scripts/lib/scratch-root.sh` already provides `soleur_scratch_session_begin` / `_soleur_scratch_cleanup` / `soleur_scratch_mark_owned` (ADR-250). Creating a second helper would fork the trap contract (ADR-129). | Extend the existing lib (sandbox allocator) and add TS/Python equivalents that implement the SAME marker format; no `tmpdir.sh`. |
| "Add a housekeeping command that prunes stale leftovers older than N days and reports sizes" | `scripts/soleur-tmp-purge.sh` (`--dry-run/--apply/--restore/--drain`) exists; it reports per-class counts but not size-by-prefix, not caches, and has no operator-attested class. | Add `--report`, `--older-than-days`, `--attest GLOB` to the existing script. No second purge command. |
| "A lint that fails if a script calls mktemp without cleanup" | `scripts/lint-trap-tempfile-ownership.py` rule (c) already does this for shell, scoped to ADDED lines with a `.highwater` ratchet, wired in `ci.yml:227-229`. | Extend with rule (d) TS/PY allocations and rule (e) hard-coded base literal; keep the highwater ratchet. |
| "perf/mut/vac/td/sdkprobe harnesses are mktemp dirs from committed scripts" | `git grep` for each name returns no writer (`mutbat.*`/`mutbat2.*`/`inngest-zot-mut-*` are the only committed ones, all already trapped). `td` = test-design seat. | Fix the producer where it lives: an agent-facing sandbox allocator + SKILL briefs. |
| "~/.codex/.tmp/marketplaces re-cloned and never pruned" | `git grep` finds no Soleur script that runs `marketplace add/update`; README documents the user-run commands and already prescribes `--sparse` for Codex. The directory is CLI-owned. (This host: 115M.) | Document + report size + printed clear command. No repo control exists to change. |
| "mise holds 22 stale tool versions" | No `.mise.toml`/`.tool-versions` in the repo; `.bun-version` bumped once in 4 months (`f9cd8dc2cb`), `.nvmrc` pins major `22`. Accumulation is the operator's mise across all projects. | Document + printed `mise prune` guidance. |
| "debuginfod growth from Soleur perf/debug runs" | No Soleur script invokes perf/gdb/valgrind/coredumpctl; `git grep -i debuginfod` is empty. | Document `DEBUGINFOD_URLS=` opt-out in the cache runbook section; nothing to set in-repo. |
| Predecessor issue #7004 "still open" | #8738 merged (`09c7cc31cd`) with `Ref #7004`; #8786 (post-merge operator purge on the real host) is open. | This PR does NOT close #7004 (its acceptance includes the operator-host purge tracked by #8786). It posts an AC-mapping comment. Closes #9117 only. |
| Operator verification "`du -sh /var/tmp` unchanged before vs after" | `/var/tmp` is mutated concurrently by other sessions' session-start sweeps: the entry count read 37,379 then 117 within minutes during planning. A raw `du` diff is meaningless on a live host. | Verification protocol (Phase 6) compares entries newer than a T0 stamp, and runs the suites under a private `TMPDIR`. Real `/var/tmp` and `~/.codex/.tmp` are measured only, never deleted from. |

## Research Insights

**Premise Validation.** Checked: #7004 (OPEN, tracks reclamation half), PR #8738 (MERGED 2026-09-25,
`Ref #7004`), ADR-250 (Accepted; Decision + Consequences read — it explicitly states the prefix allowlist
is FROZEN and that unattributable legacy residue "is intended to persist"; this plan amends that for an
operator-attested rung rather than adding allowlist rows), #8786 (OPEN operator step), #9117, #8659, #8800,
#6760. Stale premise found: the task assumes the leak producers are committed scripts; they are not
(see Reconciliation). ADR-corpus mechanism check: heuristic reaping of shared bases is a rejected
alternative (ADR-250 Context); the attest rung is operator-named, quarantine-only, and excludes git
worktrees, so it is not that rejected mechanism.

**Property List.**

- P1: A direct invocation of any test runner leaves no new entry in its TMPDIR base after a normal exit
  or SIGINT/SIGTERM.
- P2: A runner killed by SIGKILL leaves only entries a reaper can attribute (owner marker written at
  creation).
- P3: An agent that needs a mutable full-tree copy can obtain one that is small, owned, and removed
  with one command.
- P4: The operator can see what is stale (by size, by prefix family, with caches) and reclaim the
  unattributable-by-design backlog without any path to deleting a live or registered worktree.
- P5: A new unowned allocation cannot land without CI failing.
- P6: The caches' sources and safe clear commands are documented and measurable.

**Cut List** (mechanism -> property -> what already covers it).

- New `scripts/lib/tmpdir.sh` -> P1 -> `scratch-root.sh` + ADR-250 markers already cover; extend instead.
- New second purge command -> P4 -> `soleur-tmp-purge.sh` covers; extend.
- Per-worker/per-test-file roots in vitest -> P1 -> one root per run suffices and avoids teardown races.
- Hardlink (`cp -al`) or git-worktree sandboxes -> P3 -> hardlinks write through to the live repo
  (#8800 documents exactly that hazard); a detached worktree is a REGISTERED worktree that the
  classifier retains forever when unmerged. `git ls-files | tar` is cheap (302 MB, 0.7 s measured) with
  no registry entry.
- Isolating `npm_config_cache`/`BUN_INSTALL_CACHE_DIR` per run -> P6 -> package caches are
  content-addressed, so repeated installs of one lockfile do not grow them; isolation would only trade
  disk for cold network installs on every run. Measure once in Phase 5 (cache size before/after two
  identical installs into a scratch cache) and record; add isolation only if growth is shown.
- Pinning mise versions / shipping a `.mise.toml` -> P6 -> the repo has no mise config; adding one
  would create the accumulation it is meant to stop.
- Deleting the 33 suites' trap clobber individually (#8659) -> P2 -> structural marker-at-creation
  covers the leak direction; the per-suite trap rewrite stays on #8659.
- Size-shaped heuristic reap of unmarked tmpfs dirs (#7004 comment) -> P4 -> measured and rejected in
  ADR-250; the producer-side allocator is the fix.

**Measured baseline (current main, this host, `TMPDIR=<fresh dir>` per run, entries left after rc=0).**

| Direct run | Entries left | Names |
|---|---|---|
| `bun test plugins/soleur/test/kb-coverage.test.ts` | 10 | `kbcov-*`, `kbcov-wrap-*`, `kbcov-wrap2-*`, `soleur-inc-*` |
| `.../gdpr-gate.test.ts` | 15 | `gdpr-gate-notice-*` x11, `gdpr-gate-scan-notice-*`, `gdpr-gate-incidents-*`, `soleur-inc-*` |
| `.../legal-template-vendor-surface.test.ts` | 4 | `legal-corpus-empty-*`, `legal-corpus-synth-*`, `legal-fallback-*`, `soleur-inc-*` |
| `.../plan-skeleton-checkpoint.test.ts` | 9 | `plan-skeleton-reader-*` x8, `soleur-inc-*` |
| `.../web-platform-runtime-plugin-trigger.test.ts` | 10 | `deploygap-gate-*` x8, `deploygap-nogit-*`, `soleur-inc-*` |
| `.../ship-incident-pir-gate.test.ts` | 10 | `pirgate-*` x8, `pir-gate-awk-*`, `soleur-inc-*` |
| `bash .claude/hooks/grep-rewrite.test.sh` | 1 | `soleur-inc-*` (own `trap` replaces the composed one; #8659 class) |
| `bash tests/scripts/test-weakness-miner.sh` | 5 | `tmp.*` (five bare `mktemp -d`, no cleanup) |
| Clean on direct run (control) | 0 | `hook-tool-kind`, `lint-agents-rule-budget`, `resolve-git-root`, `test-content-publisher`, `orphan-reaper` |

These names are the evidence list's `kbcov-*`, `gdpr-gate-*`, `legal-*`, `plan-skeleton-reader-*`,
`deploygap-*`, `pirgate-*`, `pir-gate-awk-*`. Census: the authoritative shell figure is the lint's own
`python3 scripts/lint-trap-tempfile-ownership.py --census` = 73 class-b files (zero `trap ... EXIT`)
against a recorded highwater of 79 (the file notes 80th/79th entrants, each annotated). The ad-hoc,
comment-unaware greps run at plan time (770 shell files with `mktemp`; 61 with no `trap`; 20 TS/PY
files with no cleanup token) are orientation only and are superseded by the lint's census at work time. Literal-base `mktemp` (bypasses any per-run root): 9 sites, of which the
dev-host ones are `scripts/file-upstream-ask-8160.sh` (its output directory IS the deliverable and is
annotated `lint-trap-ownership: ok`, so it is deliberately left alone) and
`credential-persist-home-guard.bench.sh` (already trapped and marked).

**Cache findings (agent-researched, re-verified).** No `.mise.toml`/`.tool-versions`; `.bun-version`
and `.nvmrc` are the only pins; no `npm_config_cache`/`BUN_INSTALL_CACHE_DIR` override anywhere; 120
`npm ci` call sites install into the default shared cache; `worktree-manager.sh install_deps` runs one
`bun install --frozen-lockfile` or `npm ci --ignore-scripts` per worktree (node_modules is per-worktree
by design; this host: `apps/web-platform/node_modules` 1.7 GB). `~/.codex/.tmp` here is 115M.

**Institutional learnings applied.** ADR-129 (one EXIT trap per shell; a later trap silently replaces an
earlier one; `$(helper)` mutations are lost) — the TS/PY roots therefore never rely on a trap and the
shell side marks at creation. ADR-250 (ownership-keyed; liveness-gated; direct delete only for
schema-named roots on tmpfs; everything else quarantined). Learning
`best-practices/2026-07-18-mktemp-sweep-must-echo-path-for-cross-bash-call-recovery.md` — the sandbox CLI prints the
path and `rm` takes the path, because an agent's cleanup runs in a different Bash call.
`2026-09-08-six-instruments-were-broken-and-three-printed-a-verdict-anyway.md` — artifacts for batteries live in `/var/tmp` or the
worktree, never `/tmp` (kept; the allocator picks the base). `hr-never-run-commands-with-unbounded-output`
— every census/grep in this plan is bounded.

## Open Code-Review Overlap

- #8659 (33 suites replace test-helpers' composed EXIT trap, leak `soleur-inc-*` on direct runs; files:
  `plugins/soleur/test/test-helpers.sh`, `scripts/test-all.sh`): **Acknowledge, partially fold in.** This
  PR marks the incident sandbox owned at creation in `test-helpers.sh` and `test-incident-sandbox.sh` and
  adds the TS/PY session roots, so the leak becomes reaper-eligible and, for TS/PY, removed. It does not
  rewrite the 33 suites' traps; #8659 stays open (its follow-through probe still applies).
- #7942 (two `*.mutation.sh` batteries run in no gate; touches `test-helpers.sh`, `test-all.sh`):
  **Acknowledge** — different concern (gate registration).
- #8800 (census sandbox shares inodes with the live repo; `scripts/lib/test-affected-paths.sh`):
  **Acknowledge** — this plan edits only the registry list in that file. The new sandbox allocator
  deliberately avoids hardlinks/symlinked source for the reason #8800 records.
- #8496 (cleanup-merged never queries `[gone]` branches; `worktree-manager.sh`): **Acknowledge** —
  unrelated; this PR does not touch `cleanup_merged_worktrees` logic.
- #9117 (durable test-all log dir accumulates forever): **Fold in** (`Closes #9117`).
- #6760 (skill-security-scan runtime dir per invocation): **Acknowledge** — #6789 already added a
  7-day startup age-reap; the residue (1,997 dirs in `/run/user`) is bounded by design and the meta file
  is retained as evidence. No change; noted in the cache/housekeeping runbook.

## User-Brand Impact

**If this lands broken, the user experiences:** the single operator losing authored work or a live git
worktree under `/var/tmp` (for example a registered `td-*` review worktree) because a new reclamation
path moved it, or conversely the disk filling again and every Bash call failing with no output (the
2026-09-22 and 2026-10-01 incident shapes).

**If this leaks, the user's workflow is exposed via:** no confidentiality surface — scratch holds repo
copies and fixtures; the exposure is destructive-action blast radius of the new `--attest` rung.
Mitigations are structural: quarantine only (never `rm`), `.git`-bearing entries excluded, same-uid,
live-handle and age conjuncts, over-broad glob refusal, dry-run default.

**Brand-survival threshold:** `single-user incident` (one operator host; a mistaken move of authored
work is the failure). CPO sign-off is required before `soleur:work` begins; `user-impact-reviewer` runs
at review time. CLO/CTO concerns are carried in Domain Review.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-250 (`knowledge-base/engineering/architecture/decisions/ADR-250-ownership-keyed-scratch-reclamation.md`)
via `soleur:architecture` with an "Amendment 1 (2026-10-01)" section, as an in-scope task of Phase 3:

ADR-250 has Context / Decision / Consequences only (no Alternatives table), so the amendment adds an
`## Alternatives Considered` section, adds `Amends: ADR-195` to the header (the attest rung reverses its
report-not-reap default for operator-named globs), and edits Consequences (d) — "the unattributable
residue is intended to persist" — to say it persists *unless the operator names it* via `--attest`.

- **A1.1 Producer coverage.** Every runner chokepoint that Phase 0 measures as leaking (bun preload
  first; vitest `globalSetup`, pytest `conftest.py`, unittest `_git_fixture_env.py` only if the Phase 0
  baseline shows a direct-run leak) binds a per-process `soleur-run.<pid>.*` root when
  `SOLEUR_SCRATCH_SESSION_ROOT` is unset, adopts the parent's root ONLY after validating it (exists, same
  uid, valid marker, live owner pid in the same `ns=`; otherwise creates a fresh root), and removes only
  a root it created. Marker format unchanged (`pid=`, `schema=1`, `ns=`).
- **A1.2 Operator-attested rung.** A new classification rung `attested:<glob>` for `soleur-tmp-purge.sh
  --apply --attest GLOB`: disk-backed bases only, quarantine only, never direct delete, never a
  `.git`-bearing entry, same uid, no live handle, newest mtime in the tree older than `--older-than-days`
  (default 7). Alternatives Considered: rejected "extend the frozen prefix allowlist" (no content
  signature exists for agent-named dirs), rejected "heuristic size/age reap" (ADR-250 Context), rejected
  "documented one-off `find ... -exec mv`" (no worktree/handle safety; recorded as the fallback if the
  rung is cut — see decision-challenges).
- **A1.3 Agent sandbox allocator.** `scripts/soleur-sandbox.sh new|rm` allocates owned work copies on a
  disk-backed base; names `soleur-sbx.<label>.*`. `rm` is added to ADR-250's terminal-delete carve-out
  list (alongside `git worktree remove`, `rmdir`, owner-EXIT cleanup), restricted to the `soleur-sbx.*`
  name pattern AND a valid marker.
- **A1.4 Residual windows** restated: SIGKILL before the marker write (microseconds, atomic
  tmp+rename), marker-only dirs are quarantined (recoverable), not deleted, and a quarantine on the same
  disk frees bytes only at drain (see Phase 3 drain note).

### C4 views

No C4 change. Read `model.c4` (888 lines), `views.c4` (113), `spec.c4` (54) in full-file greps for
actors/systems/containers/relationships. Checked: external human actors (only `founder` Operator,
unchanged and no new access relationship), external systems (no new vendor/edge — npm/bun registries
and the Codex/Claude marketplace CLIs are already outside the model and gain no new edge), containers
and data stores (scratch dirs are ephemeral operator-host files, not a modeled store; `grep -i -c
'scratch|tmpfs|/var/tmp'` on `model.c4` returns 1 unrelated hit), and derived cardinalities
(`bash plugins/soleur/test/c4-count-parity.test.sh` -> `ALL TESTS PASSED`, run at plan time).

### Sequencing

ADR amendment authored in this PR, status of A1.2 "adopting" until the first operator-host purge with
`--attest` is recorded under #8786; not deferred to a follow-up issue.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_TMP_PURGE_REPORT line (per-class counts + bytes + cache sizes) from the purge --report; session-start sweep + Reaper 3 ledger entries"
  cadence: "on session start (sweep, existing) and on demand (--report); 5-minute cadence only where the operator installed the guard timer per the runbook"
  alert_target: "operator terminal (SessionStart hook surfaces the guard report, existing); no Sentry — operator-local CLI surface (observability layer 7)"
  configured_in: "scripts/soleur-tmp-purge.sh, scripts/tmpfs-guard.sh, plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"
error_reporting:
  destination: "stderr SOLEUR_TMP_PURGE FATAL/WARN lines + ledger ~/.local/state/soleur/tmp-purge-ledger.log"
  fail_loud: "non-zero exit (1 usage/fail-closed, 2 lock contention); a refused attest glob exits 1 with the refusal reason"
failure_modes:
  - mode: "attest glob matches a live or registered worktree"
    detection: "classifier refuses (.git-bearing); report lists it under worktree:* with reason; test arm asserts it is untouched"
    alert_route: "report line + ledger SKIP entry"
  - mode: "runner root not removed (SIGKILL / worker OOM)"
    detection: "residue canary asserts zero delta on normal/SIGTERM paths; SIGKILL leaves a marker-bearing soleur-run.<pid>.* root visible in --report as marker:<pid> dead-owner"
    alert_route: "Reaper 3 + session-start sweep reclaim; report shows count"
  - mode: "new unowned allocation lands"
    detection: "lint-trap-tempfile-ownership.py rules (c)/(d)/(e) in ci.yml; census vs highwater"
    alert_route: "CI failure on the PR"
logs:
  where: "ledger file + stdout report; test-all durable log dir (now age-reaped)"
  retention: "ledger append-only (existing); durable test-all logs 14 days (#9117)"
discoverability_test:
  command: "bash scripts/soleur-tmp-purge.sh --report --base scripts/lib"
  expected_output: "SOLEUR_TMP_PURGE_REPORT"
```

## Guard Contract

### Guard 1 — Runner scratch-session chokepoint parity and residue canary

**Property.** No test runner started directly (not through `test-all.sh`) leaves a new entry in its
TMPDIR base after a normal exit or SIGTERM, including entries created by the incident-sandbox helper.

**Assembly.** The runner entrypoints that execute test code, derived from `CHOKEPOINT_FILES` (5 entries:
git-tripwire.ts, the vitest global setup, `tests/conftest.py`, `tests/scripts/_git_fixture_env.py`,
`test-helpers.sh`) AND the separate `PRELOAD_FILES` array (two `bunfig.toml`) in
`.claude/hooks/incident-sandbox-coverage.test.sh` — read from that file, not a second hand-kept list. Only
the chokepoints Phase 0 measures as leaking gain the call, but the canary iterates all of them. The call-order relation is part of
the assembly: the scratch session must be bound BEFORE `ensureIncidentSandbox`, or `soleur-inc-*`
escapes the root. A new runner entrypoint is a new chokepoint, so the canary iterates the registry.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `ensureScratchSession()` call from `plugins/soleur/test/lib/git-tripwire.ts` | RED (bun arm leaves entries) |
| 2 | Delete it from `apps/web-platform/test/global-setup-git-tripwire.ts` | RED (vitest arm) |
| 3 | Delete it from `tests/conftest.py` | RED (pytest arm) |
| 4 | **Reorder:** move `ensureScratchSession()` AFTER `ensureIncidentSandbox()` in git-tripwire.ts | RED (`soleur-inc-*` lands in the base; the property is about the window, not the call's existence) |
| 5 | Add a second chokepoint file (to `CHOKEPOINT_FILES` or `PRELOAD_FILES`) that lacks the call, after a compliant first | RED (registry iteration does not stop at the first member) |
| 6 | Empty the canary's suite list (dispatch) so it runs 0 suites | RED (floor: "0 runners checked" is a failure) |
| 7 | Export `SOLEUR_SCRATCH_SESSION_ROOT` to a valid owned root and run a suite | PASS and the parent root still exists (must-PASS: nesting adopts, never deletes a root it did not create) |
| 8 | Export `SOLEUR_SCRATCH_SESSION_ROOT` to a stale dir (no marker, or dead owner pid) | the runner creates a fresh root instead of adopting (validation is part of the property) |
| 9 | SIGKILL a runner mid-run | a marker-bearing dead-owner root remains and classifies as `marker:<pid>` (the P2 half of the property, not just rc 0 and SIGTERM) |

**Harness rows:**

| # | Mutation to the SUITE (not the guard) | Expected |
|---|---|---|
| H1 | Point the canary's measured base at a nonexistent path | RED (a missing base must not read as empty) |
| H2 | Pre-seed the base with an unrelated entry before the run | PASS (must-PASS differing from the canonical: the canary compares the delta, not absolute emptiness) |
| H3 | Replace a leaf suite command with `true` | RED (each leaf must be proven to have actually created at least one scratch entry during the run; a no-op leaf is vacuous) |

**Anchor.** The leaf-suite list is a stored list compared to the thing it protects; a weakening must
move something outside the commit: the list is derived from the registry above plus the measured-leaker
seed set in this plan, and the registry is asserted by `incident-sandbox-coverage.test.sh` (a merged
suite), so deleting an entry from both in one diff is caught only by that suite's own floor — keep its
count floor, do not lower it.

### Guard 2 — mktemp ownership lint rules (d) and (e)

**Property.** No change adds a tracked non-test script allocation (`mkdtemp*`, `mkstemp`,
`NamedTemporaryFile(delete=False)`, `mktemp`) that has no cleanup construct or owner marker, and no
change adds a `mktemp`/`mkdtemp` call whose base is a hard-coded `/tmp` or `/var/tmp` literal (which
bypasses every per-run root).

**Assembly.** `git ls-files` over `*.sh *.bash *.py *.ts *.mjs *.js`, scoped to ADDED lines against the
merge base in default mode (explicit paths scan the whole file, as the existing rule (c) does); test
files under runner chokepoint directories are structurally owned and counted separately, not exempted by
name. The census population and its `.highwater` are one anchor.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a `.py` script with `tempfile.mkdtemp()` and no `rmtree`/`TemporaryDirectory`/`atexit` | RED |
| 2 | Add a second such file after a compliant one | RED |
| 3 | Add `mktemp -d /var/tmp/x.XXXXXX` to a `.sh` | RED (rule e) |
| 4 | Add a `.ts` script with `mkdtempSync` and no `rmSync` | RED |
| 5 | Make the file walk return zero files (dispatch) | RED (floor on files scanned) |
| 6 | Lower the highwater without removing a population member | RED |
| 7 | Add a file with `mkdtempSync` plus `afterAll(() => rmSync(...))` | PASS (must-PASS, not the canonical) |
| 8 | Add the same allocation with `# lint-trap-ownership: ok <reason>` | PASS; a bare marker with no reason is RED |
| 9 | A cleanup token (`rmSync`, `rmtree`) appearing only inside a comment or a string literal beside an uncleaned allocation | RED (the scanner must LEX: Python via `ast`, TS/JS via a comment/string-masking pass — a line grep is satisfied by its own prose) |
| 10 | An allocation call name appearing only inside a comment or string | PASS (not an allocation) |

**Harness rows:**

| # | Mutation to the SUITE | Expected |
|---|---|---|
| H1 | Make the fixture builder's `git add` silently fail so the "added line" never exists | RED (the suite asserts each RED fixture is detected as ADDED, not merely present) |
| H2 | Run with a fixture that is the canonical clean tree and a second clean tree with different cleanup spelling | both PASS |

**Anchor.** The highwaters are compared against the merge-base copy (a diff that lowers or raises one
must also change the census by exactly that amount). Plan-time measurement: `--check-highwater` reads
the WORKING copy today, so Phase 4 step 3 builds the merge-base comparison and the TS/PY census as
tasks, not as a work-time check.

### Guard 3 — `--attest` rung safety conjunction

**Property.** `soleur-tmp-purge.sh --apply --attest GLOB` moves an entry only if every conjunct holds:
base is `/tmp` or `/var/tmp` on a disk-backed device, same uid, no `.git` file or directory, no live
cwd/fd/mmap handle, mtime older than `--older-than-days`, glob not over-broad, and the destination is
the quarantine root; it never deletes.

**Assembly.** Every move/delete site in `soleur-tmp-purge.sh` apply mode and every classifier rung that
can return a movable class (`tc_classify_entry` callers in purge, Reaper 3 and the session sweep). The
single chokepoint is the quarantine-move function; the attested class must enter apply only through the
same action-time liveness re-walk as marker classes, and Reaper 3 / the sweep must classify attested
leftovers (anything under the quarantine root) as quarantine, never as unattributable candidates.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `.git` exclusion (fixture: a registered worktree named `td-123`) | RED (fixture moved) |
| 2 | Remove the age conjunct (fixture: entry 1 hour old) | RED |
| 3 | Accept glob `*` | RED |
| 4 | Remove the live-handle conjunct (fixture: a process with cwd inside) | RED |
| 5 | A second attested entry holding a live cwd, after a compliant first | RED (the walk does not stop at the first member) |
| 6 | Run `--attest 'vac*'` on a fixture base with zero matches | RED (anti-vacuity: the suite requires at least one fixture entry matched in the positive arm) |
| 7 | Change the destination from quarantine to `rm -rf` | RED |
| 8 | Attested entry old, same uid, no handle, no `.git`, on the sentinel disk base | PASS and appears in quarantine with a ledger row (must-PASS, not canonical) |
| 9 | Attested dir that is a symlink to a dir outside the base, and an entry owned by another uid | RED (refused; each its own fixture) |
| 10 | Globs `?*`, `*foo`, `t*d*`, `[a-z]*`, `a/b` | RED (each refused by the literal-prefix/no-leading-wildcard/no-slash guard) |
| 11 | Old dir whose directory mtime is old but contains a file modified 1 hour ago | RED (age uses the newest mtime in the tree) |
| 12 | Pass an attest glob from Reaper 3 / the session sweep entry points | RED (those callers cannot reach the rung) |

**Harness rows:**

| # | Mutation to the SUITE | Expected |
|---|---|---|
| H1 | Run the positive arm against a tmpfs base | the entry is reported attested-but-tmpfs and untouched (disk-only rule) |
| H2 | Make the suite's sentinel-root builder fail silently | RED (setup failure aborts, not "0 moved = pass") |

**Anchor.** The conjunct list is asserted by behavior (fixtures), not by a stored hash; no stored value
to defend beyond the TTL constants already covered by `tests/scripts/test-tmp-purge.sh`.

## Implementation Phases

Tests come first in every phase (`cq-write-failing-tests-before`): each phase starts by committing the
failing arm, then the fix. Bounded output on every command (`| head`, `--name-only`, `-l`).

### Phase 0 — RED harness (no production changes)

1. `tests/scripts/test-scratch-residue.sh`: for each leaf suite (seed set below plus the registry),
   create a private base under the scratchpad, run the suite with `TMPDIR=<base>` and
   `SOLEUR_SCRATCH_SESSION_ROOT` unset, assert delta == 0 on rc 0 and under SIGTERM; assert each leaf
   created at least one entry (anti-vacuity) by running the same leaf once against a counting shim.
   Expected today: RED for the six TS suites, `grep-rewrite`, `test-weakness-miner`. The baseline also
   measures ONE direct run each of a vitest suite (`apps/web-platform`), a pytest module and a
   `python -m unittest` module; Phase 1 steps 2b/3 are implemented only for runtimes the baseline shows
   leaking (no measured requirement, no chokepoint edit).
2. `tests/scripts/test-soleur-sandbox.sh`, extra arms in `tests/scripts/test-tmp-purge.sh` (`--report`,
   `--attest`, `--older-than-days`), fixtures for lint rules (d)/(e) in
   `scripts/lint-trap-tempfile-ownership.test.sh`'s fixture style.

### Phase 1 — Runner chokepoints (P1, P2)

1. Create `plugins/soleur/test/lib/scratch-session.ts` exporting `ensureScratchSession()`: if
   `SOLEUR_SCRATCH_SESSION_ROOT` is set, adopt it and register nothing; else `mkdtempSync` a
   `soleur-run.<pid>.XXXXXXXX` root under `os.tmpdir()`, write `.soleur-owned` atomically (tmp +
   rename; `pid=<process.pid>`, `schema=1`, `ns=` from `/proc/self/ns/pid`), set
   `process.env.TMPDIR` and `SOLEUR_SCRATCH_SESSION_ROOT`, and remove the root on `process.on("exit")`
   and SIGINT/SIGTERM only if this call created it (signal handlers re-raise so the process keeps its
   128+n exit status; asserted in the canary). `SOLEUR_KEEP_SCRATCH=1` skips removal for debugging a
   failing fixture. Called IN LINE (not hoisted import side effect) so ordering is deterministic. Bun and Node both read `TMPDIR` per `tmpdir()` call
   (verified at plan time with a two-line probe), so no import-order hazard for `os.tmpdir()` callers.
2. Call it first in `git-tripwire.ts` (before line `ensureIncidentSandbox();`; the registration is the
   `[test] preload` in both `bunfig.toml` files, so plain `bun run` is unaffected). 2b (only if Phase 0
   shows a vitest leak): the vitest `global-setup-git-tripwire.ts` (before `ensureIncidentSandbox()`,
   returning a teardown). One root per
   run, not per worker: workers fork after `globalSetup` and inherit `TMPDIR`; the canary proves this for
   both `pool: "forks"` and `WEBPLAT_TEST_USE_THREADS=1`.
3. Python (only if Phase 0 shows a pytest/unittest leak): add `ensure_scratch_session()` next to `ensure_incident_sandbox()` in `tests/conftest.py` and
   `tests/scripts/_git_fixture_env.py`; set `tempfile.tempdir` explicitly (the stdlib caches it) and
   `atexit` removal for a root it created.
4. Bash: in `.claude/hooks/lib/test-incident-sandbox.sh` and `plugins/soleur/test/test-helpers.sh`, call
   `soleur_scratch_mark_owned` on the `soleur-inc-*` dir immediately after `mktemp` (marker-at-creation;
   pid defaults to `$$`, the suite shell), so a replaced trap leaves a reaper-eligible dir.
5. Extend `.claude/hooks/incident-sandbox-coverage.test.sh` with the call-order assertion (scratch
   session before incident sandbox) for each chokepoint that gains the call. Its registry is
   `CHOKEPOINT_FILES` (5 entries) plus the separate `PRELOAD_FILES` array (2 `bunfig.toml`); the plan
   treats both as the assembly, not one list.
6. One marker-contract fixture: a test that the shell writer (`soleur_scratch_mark_owned`), the TS
   writer and (if built) the Python writer each emit a marker that `tc_marker_owner_pid` in
   `tmp-classify.sh` parses to the writer's pid with matching `ns=` — three writers, one parser, one
   fixture, so the formats cannot drift.

### Phase 2 — Agent sandbox allocator (P3, task c)

1. `scripts/lib/scratch-root.sh`: add `soleur_sandbox_new <label> [--link-node-modules]` and
   `soleur_sandbox_rm <dir>`. Allocation: base is FORCED disk-backed (the first of `/var/tmp`,
   `$HOME/.cache` that is not tmpfs/ramfs; fail closed if none — a 302 MB copy on a RAM disk is the
   incident shape), name `soleur-sbx.<label>.XXXXXXXX`, `.soleur-owned` marker whose `pid=` is
   `SOLEUR_SCRATCH_OWNER_PID` or, by a deterministic rule, the first ancestor in the `/proc/<pid>/stat`
   ppid chain whose comm is not a shell/`env` wrapper (fallback `$PPID`); a reused pid makes the dir
   immortal, which is stated as the accepted residual in A1.4. Copy via
   `git ls-files -z --cached --others --exclude-standard | tar --null -T - -cf - | tar -x` (the DIRTY working
   tree is the default — seats mutate uncommitted fixes; tracked tree 302 MB / 0.7 s measured; excludes
   `knowledge-base/` and `.git` by default, so `git diff` is unavailable inside the sandbox by design and
   the brief says so). `node_modules` is NOT linked by default; `--link-node-modules` creates a symlink and
   prints a warning that tool caches (`node_modules/.cache`, `.vite`) and installs write through to the live
   tree (the #8800 hazard). `soleur_sandbox_rm` refuses unless BOTH the name matches `soleur-sbx.*` AND a
   valid marker exists AND the realpath sits under a scratch base (either failing refuses), then `rm -rf`s
   after a same-uid check. No `.git` file, so it never enters the worktree registry.
2. `scripts/soleur-sandbox.sh new|rm` thin CLI (prints the path; `rm` takes the path — the
   cross-Bash-call contract). Register in `scripts/test-all.sh` and `scripts/lib/test-affected-paths.sh`.
3. Brief enforcement, not prose: replace the sandbox guidance in `plugins/soleur/skills/review/SKILL.md`
   (the "Brief every mutating seat's sandbox size and lifetime" bullet) and `plugins/soleur/skills/work/SKILL.md`
   (the instrument/artifact bullet and the self-invoked `.test.sh` `TMPDIR` bullet) with: allocate via
   `bash scripts/soleur-sandbox.sh new <seat>`, remove with `... rm "$SBX"` before the seat returns, name
   the artifacts that must survive (logs) separately in `/var/tmp` via `mktemp`. **Byte budget (measured
   at plan time against `plugins/soleur/test/skill-body-budget.json`, enforced vs the merge base by
   `python3 scripts/lint-skill-body-budget.py --base origin/main`):** `work/SKILL.md` is 361,979 bytes
   against a 362,000 ceiling (21 bytes of headroom) and `review/SKILL.md` 476,028 against 477,000 (972).
   The edits therefore MOVE the detailed guidance into a new linked reference file and leave a pointer
   shorter than the text it replaces (net delta <= 0 in `work`, <= +900 in `review`); never raise a ceiling.
   Do not grow AGENTS.md (`cq-agents-md-tier-gate`).
4. `apps/web-platform/infra/doppler-download-error-channel.mutation.py`: move `shutil.rmtree(sb)` into
   a `finally` (it is skipped on the surviving-mutation `sys.exit(1)` path — the one committed
   mutation harness with a failure-path leak). The two bash batteries
   (`cloud-init-inngest-zot-pull-mutation.test.sh`, `ship-incident-pir-gate-mutation.test.sh`) already
   trap `rm -rf` and are left alone (SIGKILL hardening for them stays with #8659).

### Phase 3 — Report, attest, ADR (P4, task e)

1. `plugins/soleur/scripts/lib/tmp-classify.sh`: add `tc_attested_class <dir> <glob>...` rung, placed
   AFTER every existing rung (so a git worktree, a protected name, a marker and a schema root keep their
   stronger attribution) and BEFORE the final `unattributable`. Checks: realpath under a configured base
   with no symlink traversal, same uid, `-xdev`, no `.git` entry, `tc_tree_has_live_handles` false, no
   process cwd inside or at an ancestor, age (newest mtime anywhere in the tree, not the dir's own
   mtime) >= N days. Glob guard: matched against the BASENAME only, literal prefix of >= 3 characters,
   no leading wildcard, no `/` (so `*`, `?*`, `*foo`, `t*d*`, `[a-z]*` are refused). The function takes
   its globs ONLY as an explicit argument passed by `soleur-tmp-purge.sh`; Reaper 3 and the session sweep
   never pass any, so the shared classifier cannot reach the rung from an automatic trigger.
2. `scripts/soleur-tmp-purge.sh`: add `--report` (read-only: per-class count+bytes, top-N prefix
   families by bytes with the unattributable bucket split so `vac*`/`td-*`/`perf-*`/`mut*`/`sdkprobe.*`
   are visible, with `.git`-bearing and non-`.git` bytes split per family so the operator sees what
   `--attest` can and cannot reach; cache sizes live in the runbook as a one-line `du -sh` command, not
   in the script), `--base DIR` (repeatable seam), `--older-than-days N`, and `--attest GLOB`
   (repeatable; apply mode; disk-backed bases only; per-invocation caps of 500 entries and 20 GiB with the
   remaining count reported so the operator loops; dry-run default). Header line
   `SOLEUR_TMP_PURGE_REPORT`. **Space recovery:** quarantine on the same disk frees nothing until drain;
   the runbook documents the immediate path `SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 bash
   scripts/soleur-tmp-purge.sh --drain` (the existing TTL seam; terminal delete stays scoped beneath the
   quarantine root; the seam is `TTL_SCRATCH="${SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN:-10080}"` in
   `soleur-tmp-purge.sh`, and an arm asserts that `=0` drains a freshly quarantined entry). `--restore` of an attested entry whose original path is occupied refuses with a
   message (asserted).
3. `scripts/tmpfs-guard.sh` Reaper 3 and the session sweep: no behavior change; add a test asserting
   they classify anything under the quarantine root as quarantine and never pass an attest glob.
4. Amend ADR-250 (A1.1-A1.4 above). Extend runbook
   `knowledge-base/engineering/operations/runbooks/tmpfs-guard-install.md` with: the report/attest/drain
   workflow, the recommended attest set measured from the evidence (`vac*`, `td-*`, `perf-*`, `mut[0-9]*`,
   `sdkprobe.*`; `td-*` carrying `.git` is a registered worktree and is removed with
   `git worktree remove`, which the report names), the cache table (source, owner, `du -sh` command, safe
   clear command, regrowth note: `npm cache clean --force`, `bun pm cache rm`, `mise prune`,
   `rm -rf ~/.cache/debuginfod_client`), `DEBUGINFOD_URLS=` opt-out, and that
   `~/.codex/.tmp/marketplaces` is CLI-owned (clear only with no Codex session running). Phase 3 steps
   1-3 and the `--attest` flag form a SEPARABLE unit (Phase 3b); `--report` and the runbook do not depend
   on it.

### Phase 4 — Committed leak sites and the lint (P5, tasks a, b, d)

1. Fix the two MEASURED direct-run shell leakers, each with a RED arm first (the PR body lists each):
   `tests/scripts/test-weakness-miner.sh` (5 bare `mktemp -d`, no cleanup: one root + owning trap placed
   before any `source test-helpers.sh`) and `.claude/hooks/grep-rewrite.test.sh` (its own `trap` after
   sourcing the sandbox lib replaces the composed one: compose via the lib's cleanup function).
   Everything else the census flags is unmeasured and is tracked by #9341 (credential-bearing
   `*-setup.sh` temp files first); the PR does not widen into it.
2. TS suites need no per-file edit (Phase 1 root covers them); add a one-line header comment pointer only
   where a suite builds a very large tree. `test/pre-merge-rebase.test.ts` (repo-root `test/`) is covered
   by the same bun preload — assert it in the canary.
3. `scripts/lint-trap-tempfile-ownership.py`: add rule (e) (literal `/tmp`/`/var/tmp` base on a
   `mktemp`/`mkdtemp`/`mkdtempSync`/`tempfile.mkdtemp` call; cheap and sound) and a deliberately narrow
   rule (d): allocations in NON-test `*.py` (via `ast`, so comments/strings cannot satisfy or trigger it)
   and `*.ts`/`*.mjs`/`*.js` (comment-stripped token match) files that contain no cleanup construct;
   test files under runner chokepoint directories are excluded structurally by the Phase 1 root, not by
   name. Both are added-lines scoped with the existing escape hatch. The existing `--check-highwater`
   reads the WORKING copy of the highwater file and `--census` is shell-only, so this step also (i)
   makes `--check-highwater` compare against the merge-base copy, (ii) adds a separate TS/PY census
   with its own highwater file `scripts/lint-trap-tempfile-ownership-tspy.highwater`, and (iii) keeps the
   `ci.yml` wiring (no new job; extend the existing two invocations).
4. `scripts/lib/test-affected-paths.sh`: map the new suites; `scripts/test-all.sh`: register
   `tests/scripts/scratch-residue`, `tests/scripts/soleur-sandbox`; confirm `lint-orphan-test-suites.sh`
   passes.

### Phase 5 — Durable log GC (#9117) and cache documentation (P6, task f)

1. `scripts/test-all.sh` startup: age-reap `soleur-test-all-logs/<label>-<pid>-<epoch>/` older than 14
   days with one bounded `find -mindepth 1 -maxdepth 1 -mtime +14` limited to that dedicated namespace
   (the one place a delete on a shared base is acceptable: the directory is created only by test-all
   itself); add a test arm.
2. (Cut after review: no cache-growth experiment; the runbook documents each cache and its clear
   command, and the Cut List records why no isolation is added.)

### Phase 6 — Verification protocol (PR body, not a shipped suite)

Record T0 name lists and bounded `du` for `/var/tmp`, `${TMPDIR:-unset}`, `~/.codex/.tmp` (read-only);
run the affected suites and `TEST_GROUP=scripts` with `TMPDIR=<private base>` (the private base must be
empty after each run); at T1 list entries newer than the T0 stamp under the real directories and assert
none carry a Soleur-owned name from this run. `du` totals are reported, not asserted (live host mutated
by other sessions). Real-host destructive pruning is out of scope (#8786).

## Files to Create

- `plugins/soleur/test/lib/scratch-session.ts`
- (conditional on the Phase 0 baseline) the Python `ensure_scratch_session()` and vitest teardown live in the existing files below, not new ones
- `scripts/soleur-sandbox.sh`
- `plugins/soleur/skills/work/references/work-scratch-sandboxes.md` (linked from both SKILL.md edits as `[work-scratch-sandboxes.md](./references/work-scratch-sandboxes.md)`; review links it as `[work-scratch-sandboxes.md](../work/references/work-scratch-sandboxes.md)`, the cross-skill form used by existing `../ship/references/...` links)
- `tests/scripts/test-scratch-residue.sh`
- `tests/scripts/test-soleur-sandbox.sh`

## Files to Edit

- `scripts/lib/scratch-root.sh` (sandbox allocator functions)
- `plugins/soleur/scripts/lib/tmp-classify.sh` (attested rung)
- `scripts/soleur-tmp-purge.sh` (`--report`, `--base`, `--older-than-days`, `--attest`)
- `scripts/tmpfs-guard.sh` (Reaper 3 / sweep treat attested leftovers as quarantine)
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (only if the sweep needs the new class; verify, else untouched)
- `plugins/soleur/test/lib/git-tripwire.ts`, `apps/web-platform/test/global-setup-git-tripwire.ts`
- `tests/conftest.py`, `tests/scripts/_git_fixture_env.py`
- `.claude/hooks/lib/test-incident-sandbox.sh`, `plugins/soleur/test/test-helpers.sh`
- `.claude/hooks/incident-sandbox-coverage.test.sh` (call-order assertion)
- `.claude/hooks/grep-rewrite.test.sh`, `tests/scripts/test-weakness-miner.sh`
- `apps/web-platform/infra/doppler-download-error-channel.mutation.py` (rmtree in `finally`)
- `scripts/lint-trap-tempfile-ownership.py`, `scripts/lint-trap-tempfile-ownership.highwater`, `scripts/lint-trap-tempfile-ownership-tspy.highwater` (new), its test
- `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `plugins/soleur/test/fixture-relative-assert.baseline.txt` (if the baseline gate requires the new suite rows)
- `plugins/soleur/skills/review/SKILL.md`, `plugins/soleur/skills/work/SKILL.md` (verify the skill description word budget is untouched: body-only edits, run `bun test plugins/soleur/test/components.test.ts`)
- `knowledge-base/engineering/architecture/decisions/ADR-250-ownership-keyed-scratch-reclamation.md`
- `knowledge-base/engineering/operations/runbooks/tmpfs-guard-install.md`
- Paths above verified with `git ls-files` at work time (`hr-when-a-plan-specifies-relative-paths-e-g`); the census-driven remainder is #9341, not this PR.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Each of the eight measured-leaker direct runs in the baseline table leaves 0 entries in a private
      `TMPDIR` after rc 0 and after SIGTERM (`bash tests/scripts/test-scratch-residue.sh` green; it was RED before the change).
- [ ] `soleur-inc-*` is created inside the per-process root for bun runs, and for each of vitest, pytest and unittest that Phase 0 measured as leaking (the Phase 0 baseline table is committed in the PR body).
- [ ] A SIGKILLed runner leaves a marker-bearing `soleur-run.<pid>.*` root that `tc_classify_entry` classifies as dead-owner (`marker:<pid>`), and a SIGTERMed runner exits with 128+15 and no root.
- [ ] The marker-contract fixture passes for every writer built (shell, TS, and Python if built).
- [ ] `bash scripts/soleur-sandbox.sh new mut` prints a path under a disk-backed base whose size is below 320 MB (the measured 302 MB tracked tree plus margin; `knowledge-base/` excluded by default shrinks it further), contains no `.git`, carries a valid marker, and `rm` removes it; `rm` refuses an unmarked path, a non-`soleur-sbx.*` name, and a path outside a scratch base; `new` refuses (non-zero) when only a tmpfs base exists.
- [ ] `bash scripts/soleur-tmp-purge.sh --report --base scripts/lib` prints `SOLEUR_TMP_PURGE_REPORT` and per-prefix-family bytes with the `.git`/non-`.git` split, and mutates nothing (asserted by a before/after tree hash).
- [ ] `--attest` never moves a `.git`-bearing, live-handle, young, other-uid, symlink-escaping, over-broad-glob (`*`, `?*`, `*foo`, `t*d*`, `[a-z]*`), or tmpfs-base entry (each is a fixture row in Guard 3, run by `tests/scripts/test-tmp-purge.sh`).
- [ ] Lint rules (d)/(e) pass on main's tree at the recorded highwaters (shell and TS/PY), fail on each Guard 2 fixture (run by the lint's own `.test.sh`); `--check-highwater` compares against the merge base; `ci.yml` job set unchanged.
- [ ] `python3 scripts/lint-skill-body-budget.py --base origin/main` is green: `work/SKILL.md` net delta <= 0 bytes and `review/SKILL.md` <= +900 bytes; no ceiling in `plugins/soleur/test/skill-body-budget.json` is raised.
- [ ] `incident-sandbox-coverage.test.sh` asserts scratch-session-before-incident-sandbox at every chokepoint; its count floor is not lowered.
- [ ] `doppler-download-error-channel.mutation.py` removes its sandbox on the surviving-mutation exit path.
- [ ] Durable test-all log GC removes only `soleur-test-all-logs/*` older than 14 days (arm in `test-all` suite); `Closes #9117`.
- [ ] ADR-250 Amendment 1 present; runbook documents report/attest, each cache's owner and safe clear command, `DEBUGINFOD_URLS=`.
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` and `python3 scripts/lint-guard-contract.py` green; `bun test plugins/soleur/test/components.test.ts` green.
- [ ] PR body lists each leak site fixed (table from Phase 4 + Phase 1 chokepoints), maps #7004's four acceptance bullets (stating that #7004 stays open for #8786), and carries the verification-protocol result.

### Post-merge

- [ ] Operator-host purge and `--attest` application are tracked by existing #8786; no new operator checklist is added here.

## Test Scenarios

1. Direct `bun test` of a TS suite with `TMPDIR` set to a fresh dir, SIGTERM mid-run: root removed.
2. Same under `SOLEUR_SCRATCH_SESSION_ROOT` exported by `test-all.sh`: runner adopts, does not delete the parent's root.
3. SIGKILL a runner: a marker-bearing `soleur-run.<pid>.*` remains; sweep/Reaper 3 classify it dead-owner.
4. Attest fixture matrix: registered worktree `td-123`, 1-hour-old `vac456`, 10-day-old `vac789` (moves), glob `*` (refused), dir with live cwd (skipped), tmpfs base (reported only).
5. `--report` on a base with 70 `soleur-run.*` and a 2 GB `perf-1` fixture: `perf-*` appears as an unattributable family with bytes.
6. Lint fixtures per Guard 2.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Direction sound; reuse of ADR-250 primitives and "document, don't invent" for caches
endorsed. Concerns folded into this plan: attest rung is the only destructive-capable part (realpath +
no symlink traversal, same uid, `-xdev`, `.git` refusal, live-cwd ancestor check, over-broad glob
refusal, per-invocation caps, dry-run default); a same-tmpfs quarantine frees no RAM so attest is
disk-base only; Reaper 3/sweep must not re-attribute quarantine contents; bun preload must bind
`TMPDIR` before `ensureIncidentSandbox` and no-op when `SOLEUR_SCRATCH_SESSION_ROOT` is set;
vitest `globalSetup` runs in the main process, so one root per run, proven by the canary in forks and
threads mode, with an exit-handler fallback; adopt-never-delete for a parent's root; marker-at-creation
(atomic) shrinks the SIGKILL window and the residual is restated in the ADR amendment; the sandbox
copies tracked + optionally dirty files and symlinked `node_modules` is read-only by convention; the
canary must be hermetic and bounded in runtime.

No Product/UX, Legal, Marketing, Finance, Sales, Support or Operations implications (developer-host
tooling, no user-facing surface, no regulated data, no new infrastructure resource).

## Risks and Sharp Edges

- **CPO sign-off is required** (`requires_cpo_signoff: true`, threshold `single-user incident`) before
  `soleur:work`. A plan whose `## User-Brand Impact` is empty or placeholder fails `deepen-plan`.
- **Attest scope creep.** Never extend `--attest` to tmpfs bases or to a "default glob set"; the evidence
  names live only in the runbook as an operator-supplied argument.
- **Pid reuse / owner pid for agent sandboxes.** The Bash-tool parent may be short-lived; a marker-only
  dir is quarantined (recoverable) after the 24 h age floor, never deleted. Document in the allocator.
- **ADR-129.** No new `trap ... EXIT` may be added to a sourced lib; shell callers splice
  `_soleur_scratch_cleanup`. The TS/PY roots use process exit handlers, not shell traps.
- **New `.test.sh` files** install their owning EXIT trap BEFORE `source test-helpers.sh` (the helper
  composes with a prior trap; a later trap replaces it — #8659) and satisfy lint rule (c).
- **Portability.** The classifier and the attest rung are Linux/`/proc`-based (cwd/fd/mmap liveness);
  where `/proc` is absent they fail closed and report, never act. `timeout` uses the repo's
  `timeout` -> `gtimeout` -> bare pattern (`.claude/hooks/git-commit-secret-scan.sh`); no `stat -c`,
  `readlink -f` or `date -d` is introduced without a fallback (BSD/macOS hosts run the plugin).
- **Registration consumers.** New suites are registered where they are read: `scripts/test-all.sh`
  (`run_suite` rows, cf. the existing `tests/scripts/tmp-purge` row) and the
  `AFFECTED_<LABEL>_PATHS` arrays in `scripts/lib/test-affected-paths.sh`, which `scripts/test-all.sh`
  sources (`_AFF_LIB=".../lib/test-affected-paths.sh"`, test-all.sh:917) to select suites for a diff
  (cf. the existing `AFFECTED_TESTS_SCRIPTS_TMP_PURGE_PATHS` array, which lists the suite file and the
  scripts it names); `scripts/lint-orphan-test-suites.sh` and `scripts/test-all-affected.test.sh` must
  stay green. (`scripts/test-all-affected.sh` does not exist; an earlier draft named it.)
- **Canary runtime.** Keep the leaf list small and bounded (the eight measured leakers); do not turn it
  into a second `test-all`.
- **Live host.** Never delete from the operator's real `/var/tmp` or `~/.codex/.tmp` during verification.
- **Skill description budget.** Edits to `review/SKILL.md` and `work/SKILL.md` are body-only; confirm
  with `bun test plugins/soleur/test/components.test.ts` (`cq-skill-description-budget-headroom`).
- **Operator-typed forms.** Any message this change prints that tells the operator to run a command
  (the report's printed clear commands) is plain shell, not a skill invocation.
- **Cache claims.** The cache section is measured on this host (115M `.codex/.tmp`) vs the evidence
  (15G); numbers in the runbook are labelled with date and host class, not asserted as constants.
