---
title: "chore(machinery): session-start bare-repo-root CWD gate — detect, mark, and redirect misanchored sessions"
type: fix
date: 2026-10-15
slug: chore-bare-root-cwd-session-gate
branch: feat-bare-root-anchor-gate
issue: 10383
closes: 10383
priority: p3-low
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# chore(machinery): session-start bare-repo-root CWD gate

## Overview

Sessions that start with their working directory at this repository's bare
root are treated by every existing check as if they were in a valid checkout:
the readiness probe reports READY on a bare root by design, the rules loader
injects the corpus and writes session manifests there, and the tracked overlay
that `sync_bare_files` deliberately maintains makes the root look like a real
worktree. The only bare-root CWD guard lives inside `soleur:go` Step 1, so any
session that never routes through `go` — a bare `claude` invocation, a
`devin acp` session — runs unrestricted against what is not a working tree,
accumulates scratch, and can read a stray `.env` as project configuration.
This plan adds a session-start-level detection arm that identifies the
bare-root CWD, emits a telemetry-visible `SOLEUR_BARE_ROOT_CWD` marker, and
injects a redirect instruction that sends file-touching work into a linked
worktree while leaving legitimate bare-root maintenance commands free to run.

## Problem Statement / Motivation

Measured live on 2026-10-15 (#10383): the bare root carries a ~791k-file /
~16 GB overlay plus accumulated scratch (`.env`, `appB.log`, `other.log`,
`_site/`, `node_modules/`, `tmp/`, `todos/`, `spike/`), and live processes
(`claude --plugin-dir ./plugins/soleur/`, `devin`/`devin acp`) hold it as
their CWD — including this planning session's own shell, which spawned at the
bare root (`is-bare-repository=true`, `--show-toplevel` empty). The overlay is
self-legitimizing: `plugins/soleur/` materialized at the root is what makes
`--plugin-dir ./plugins/soleur` resolve, `.claude/` makes project hooks load,
and each session's housekeeping writes make the next "checkout" more
convincing.

Two facts reshape the issue's framing and bound the fix:

1. **The tracked overlay is deliberate, not debris.**
   `worktree-manager.sh` `sync_bare_files` (~line 4474) maintains an exact
   `checkout-index` mirror of HEAD at the bare root — the `.mcp.json` refresh
   (`wg-at-session-start-after-cleanup-merged`) and the `--plugin-dir` anchor
   (ADR-179) both depend on it. The defect is the *untracked scratch
   accumulation plus sessions doing file-touching work there*, not the mirror.
   Deleting the whole overlay (the issue's item-3 cleanup) would break those
   mechanisms; it is out of this PR's scope and filed as a follow-up.
2. **`git rev-parse --is-bare-repository` is not a safe discriminator**
   (ADR-173; `bare-head-self-heal.sh` header): under a masked/corrupt config
   it reports `true` for a normal clone, and it is `false` inside a linked
   worktree of a bare repo — exactly the two misclassification directions.
   The issue proposes gating on it verbatim; the proven predicate already in
   the repo is `core.bare=true` read from the config FILE plus a gitdir
   identity check.

The gap is a session-start one: `go.md` Step 1's bare-repo CWD guard
(`plugins/soleur/commands/go.md:536`) only reaches sessions that route
through `/soleur:go`. Sessions anchored at the bare root that never invoke
`go` have no check at all — yet `session-rules-loader.sh` already fires for
them (registered under `.claude/settings.json` and `.devin/config.json`),
injects the full corpus, and writes `.claude/.session-manifests/` at the bare
root on every one of those sessions.

## Research Insights

**Premise Validation (Phase 0.6).** Every cited artifact was verified live in
this worktree: `git-repo-readiness-diag.sh:53` emits
`SOLEUR_GIT_REPO_READY=true` when `wt_out==true || bare_out==true` (bare root
READY by design — `cleanup-merged` legitimately runs there);
`SOLEUR_GIT_BARE_POISON` (worktree-manager.sh:1095) is emitted by
`ensure_bare_config` and covers shared-config poison (`wt_override`,
`extensions.worktreeConfig`), not CWD-anchored-at-bare-root; `go.md` Step 1
carries the only CWD guard and is routing-scoped; `session-rules-loader.sh`
resolves `REPO_ROOT` to the bare root via the envelope `cwd` fallback
(lines 173-185), passes the `--is-inside-work-tree` check (rc 0 at a bare
root, line 191), injects the corpus from the overlay, and writes the session
manifest there (line 381). Issue #10383 is OPEN. Adjacent open issues
verified: #3206 (PreToolUse block-bare-repo-read — complementary, not a
duplicate), #10218 (sync_bare_files commit stamp), #7384, #7411.

**Property List (Phase 0.6b).** Observable outcomes the fix must produce:

- P1 — a session whose CWD is the bare repo root is detected at session
  start, not only inside `/soleur:go` routing.
- P2 — the detection is visible: a `SOLEUR_BARE_ROOT_CWD` marker greppable in
  session output and registered with the marker-telemetry mirror.
- P3 — a misanchored session receives an instruction routing file-touching
  work into a worktree while legitimate bare-root maintenance
  (`git worktree list`, `cleanup-merged`, the `.mcp.json` refresh) stays
  allowed.
- P4 — masked config, linked-worktree, true-bare (`git init --bare`),
  plain-clone, non-repo, and symlinked-`.git` CWDs never produce the marker
  or the redirect.

**Cut List (Phase 0.6b).** Mechanisms proposed or adjacent, cut before
design:

- Hard PreToolUse deny on bare-root file access → the *refuse* arm is open
  issue #3206's scope (block-bare-repo-read); this PR ships detection +
  advisory redirect (P1–P3) and defers hard enforcement.
- Auto-create a worktree at session start → a hook cannot `cd` the session
  and creating branches unasked violates least-surprise; the redirect is an
  instruction naming the existing `--yes create <name>` path, which covers
  P3.
- Emitting `SOLEUR_BARE_ROOT_CWD` from `worktree-manager.sh`/`cleanup-merged`
  → `cleanup-merged` at the bare root is the *legitimate* maintenance case;
  marking it would make the marker meaningless (conflates P1 with normal
  operation). The loader arm and the readiness diag are the honest sites.
- Overlay/scratch deletion → not a mechanism for P1–P4; it is
  operator-authorized host surgery that also conflicts with the maintained
  mirror. Follow-up issue filed (see Non-Goals).
- Plugin-level `hooks.json` `""`-matcher arm for cross-repo bare roots →
  this repo's `.claude/hooks/` loader already reaches both measured
  misanchored harnesses (Claude via settings.json, Devin via
  `.devin/config.json` `""` matcher); customer-machine bare roots are a
  different population. Deferred to the extension follow-up.
- Suppressing `.claude/.session-manifests/` writes at the bare root → the
  manifest is the durable forensic record of the misanchor (SOC 2 CC6.1
  evidence); ~100 bytes vs. losing the record. Keep writing.

**Repo research (sequential inline — no subagent surface on this harness;
`Reviewed-Coverage: sequential-fallback`).** Detection predicate precedent:
`bare-head-self-heal.sh:44-51` — `.git` real dir, non-symlink;
`core.bare=true` from `git config --file`; `--absolute-git-dir` identity.
Loader integration precedent: `BARE_HEAL_OUT` child call
(`session-rules-loader.sh:315-319`) — timeout-guarded, first-line prefix
filter, appended last in the envelope (lines 466-468). Telemetry channel:
`apps/web-platform/server/git-lock-marker-telemetry.ts:162` MARKER_RE scans
agent Bash output; its drift guard
(`apps/web-platform/test/git-lock-marker-telemetry.test.ts:297`) walks
`plugins/soleur/skills/*/scripts/*.sh` + `SKILL.md`, so a new sentinel echoed
by `git-repo-readiness-diag.sh` (in the scan set) REQUIRES MARKER_RE
registration — `.claude/hooks/*.sh` is outside the scan (context-only
producer). Harness reach: Devin local fires only the `""` SessionStart
matcher (measured, `devin/INSTRUCTIONS.md`); `.devin/config.json` binds
`session-rules-loader.sh` under `""`; cloud fires no hooks and never anchors
at this host's bare root. Learnings: `2026-10-06` (probe rc folding; the
`./`-vs-root-relative bare spelling), `2026-05-19` (bare-root `git ls-files`
ghost-absence; the same go.md Step 1 citation), `2026-03-13`/`2026-03-18`
(bare-layout failure modes; `sync_bare_files` provenance).

**External research:** skipped — repo-internal machinery with in-repo
precedent; no new technology, API, or security surface.

**Community discovery / functional overlap:** no uncovered stacks (bash +
TypeScript, both covered); no community artifact plausibly covers this
repo-local layout gate. Skipped.

**Research Reconciliation — Spec vs. Codebase.** The spec dir
`knowledge-base/project/specs/feat-bare-root-anchor-gate/` exists but is
empty (no spec.md); nothing to reconcile. One issue-body divergence
reconciled above: the proposed `--is-bare-repository` gate is superseded by
the config-FILE predicate per ADR-173.

**Open Code-Review Overlap.** #8496 (`worktree-manager.sh` — cleanup-merged
[gone]-branch gh queries): acknowledge — different concern, this PR does not
touch the reaper. #8540 (`commands/go.md` — Grok shim review): acknowledge —
unrelated section; this PR touches only the Step 1 guard paragraph's
cross-reference text, not the eval-gated routing block.

**Skill description budget:** no `SKILL.md` `description:` edits planned.
Skip.

## Proposed Solution

Two detection surfaces sharing one predicate, one redirect channel:

1. **`.claude/hooks/bare-root-cwd-guard.sh`** (new child hook, modeled on
   `bare-head-self-heal.sh`): detects "CWD is a bare repo ROOT in this
   layout" via the config-FILE predicate; on detection prints one
   `SOLEUR_BARE_ROOT_CWD source=session-start` marker plus a bounded
   `[bare-root-cwd]` redirect block; prints nothing otherwise; always
   exits 0.
2. **`session-rules-loader.sh` integration**: a timeout-guarded child call
   beside `BARE_HEAL_OUT` (same `command -v timeout` conditional — `timeout`
   is absent on stock macOS, so the existing guarded-array pattern is
   reused, not a bare `timeout` call); captures the helper's output,
   sanitizes it, appends it to the envelope after the heal marker. Both
   existing SessionStart registrations (`.claude/settings.json`,
   `.devin/config.json`) reach it with zero registration changes.
3. **`git-repo-readiness-diag.sh` marker arm**: in the READY branch, when
   `bare_out==true && wt_out!=true`, re-verify with the same config-FILE
   predicate and echo `SOLEUR_BARE_ROOT_CWD source=readiness-diag`. The
   READY verdict itself is unchanged — bare roots stay ready *for
   maintenance* by design.
4. **Telemetry registration**: `SOLEUR_BARE_ROOT_CWD` added to MARKER_RE
   (MIRRORED-NOT-PAGED — the detected state is informational and already
   handled; paging on it would page on the operator's own local sessions).

The redirect text (bounded, sanitized path) tells the session: the CWD is a
bare repo root with a synced overlay, not a worktree; route file-touching
work through `worktree-manager.sh --yes create <name>` and `cd` into the new
worktree; repo-maintenance commands (`git worktree list`,
`worktree-manager.sh cleanup-merged`, the `.mcp.json` refresh) are legitimate
here; the root's `.env` is not project configuration and must not be read.

## Technical Considerations

- **Predicate (load-bearing).** `[[ -d "$root/.git" && ! -L "$root/.git" ]]`
  AND `git config --file "$root/.git/config" --type=bool --get core.bare == true`
  AND `git rev-parse --absolute-git-dir == "$root/.git"`. This rejects:
  plain clones (no `core.bare`), `git init --bare` dirs (no `.git` child),
  linked worktrees (`.git` is a file; gitdir resolves under
  `<common>/worktrees/`), masked-config clones (config read fails → no
  detection, fail-safe direction per ADR-173), symlinked `.git`
  (prompt-injection posture shared with the loader's corpus check).
- **Predicate parity.** The same conjunction is inlined in the readiness
  diag (the plugin script cannot depend on a repo hook). A parity test pins
  the two copies — duplicated predicate drift is a known class.
- **Fail-open contract.** Helper absent/stale/non-zero: the loader still
  emits its full envelope (identical to the `bare-head-self-heal.sh`
  contract — "a missing helper is the same fail-open path"). The guard is
  advisory detection, never a session blocker.
- **Envelope position.** The marker+block appends AFTER the tmpfs/heal
  trailing block (lines 466-468 positional contract — lines 1-3
  STAMP/manifest/session-context are asserted positionally by existing
  tests; appends go last).
- **Marker payload.** The telemetry-mirrored line carries `source=` only —
  no filesystem path (operator paths reach Better Stack otherwise; the
  in-context block may name the path because it is session-local).
- **Manifest write stays** at the bare root (decision: the manifest is the
  forensic record of the misanchor; suppressing it loses evidence for the
  very condition being measured).
- **Sanitization.** Redirect block path field: `tr -d '\000-\037'` + length
  cap (mirrors the MCP-roster/worktree-path clamps already in the loader).
- **Timeout portability.** Reuse the `command -v timeout` conditional-array
  pattern (BARE_HEAL_TO), never a bare `timeout` invocation (stock macOS
  lacks it — sharp-edge #8231).
- **No `set -e`.** Explicit `|| exit 0` arms only (sibling-hook convention;
  a hook crash must never starve the corpus).

## Implementation Phases

### Phase 1 — detection helper + its battery

- Create `.claude/hooks/bare-root-cwd-guard.sh` (predicate + marker +
  bounded redirect block; `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
  GIT_INDEX_FILE ...` same as the sibling; `dir="${1:-$PWD}"`).
- Create `.claude/hooks/bare-root-cwd-guard.test.sh` sourcing
  `plugins/soleur/test/lib/git-fixture-env.sh` (synthesized fixtures only;
  any owning EXIT trap placed BEFORE `source test-helpers.sh`; every
  negative row paired with a positive control on the same input shape):
  `mk_bare_root` → fires; `mk_true_bare` → silent; `mk_plain` → silent;
  linked worktree of a bare repo → silent; masked-config normal clone →
  silent; symlinked `.git` → silent; non-repo dir → silent; explicit `dir`
  arg honored; marker/block line shape asserted.

### Phase 2 — loader integration

- Edit `.claude/hooks/session-rules-loader.sh`: guarded-timeout child call
  next to `BARE_HEAL_OUT`; capture, bound, sanitize output; append to
  `OUT_BODY` after the heal marker; add the job to the header enumeration
  (item 11).
- Edit `.claude/hooks/session-rules-loader.test.sh`: bare-root envelope
  contains marker + redirect lines; worktree envelope does not; missing
  helper → valid envelope, no marker.
- Edit `.claude/hooks/README.md`: sibling subsection under "Bare-root HEAD
  self-heal" documenting the arm's contract.

### Phase 3 — readiness-diag marker + telemetry mirror

- Edit `plugins/soleur/skills/git-worktree/scripts/git-repo-readiness-diag.sh`:
  READY branch emits `SOLEUR_BARE_ROOT_CWD source=readiness-diag` when bare
  && not-inside-worktree AND the config-FILE predicate holds.
- Create `plugins/soleur/test/git-repo-readiness-diag.test.sh`: bare-root
  fixture → READY + marker; worktree fixture → READY only; masked config →
  READY, no marker.
- Edit `apps/web-platform/server/git-lock-marker-telemetry.ts`: add
  `SOLEUR_BARE_ROOT_CWD\b.*` to MARKER_RE + MIRRORED-NOT-PAGED comment
  block (records the context-only `.claude/hooks/` producer explicitly).
- Edit `apps/web-platform/test/git-lock-marker-telemetry.test.ts`:
  mirror row for the marker.
- Create `scripts/bare-root-cwd-guard-probe.sh` (the Observability
  discoverability probe below): builds a throwaway `mk_bare_root`-shape
  dir under `mktemp -d`, runs the guard, prints the marker; ~30 lines,
  exits 0 after printing, cleans up.

### Phase 4 — decision record + deferred filings

- Amend `knowledge-base/engineering/architecture/decisions/ADR-099-git-surface-topology.md`:
  idiom-rule addition (sessions anchored at a bare root are detected at
  session start and redirected to a worktree; the tracked overlay is a
  maintained `sync_bare_files` mirror, not deletable scratch) + an
  Alternatives-considered row (marker+context redirect vs. PreToolUse deny
  vs. auto-worktree vs. plugin-level arm).
- File follow-up issue A: bare-root scratch cleanup — operator-authorized:
  stop the anchored sessions, enumerate tracked-but-unmerged content
  (the issue's `diff HEAD` tool), then remove untracked scratch while
  preserving the maintained mirror (`.mcp.json`, `plugins/`,
  `.claude/` semantics per ADR-179).
- File follow-up issue B: extend bare-CWD detection to a plugin-level
  `""`-matcher SessionStart arm (cross-repo coverage) and audit sibling
  SessionStart scripts (`ensure-kb-index.sh`, `memory-backstop-resolve.sh`,
  `supabase-loopback-warn.sh`) for their own bare-root write behavior.
- Small `commands/go.md` doc touch: Step 1 guard paragraph notes the
  session-start gate now emits the redirect earlier (one sentence; outside
  the `eval-gate:block:go-routing` region).
- `knowledge-base/project/specs/feat-bare-root-anchor-gate/decision-challenges.md`
  rows (headless channel) + `tasks.md` generation.

## Files to Create

- `.claude/hooks/bare-root-cwd-guard.sh`
- `.claude/hooks/bare-root-cwd-guard.test.sh`
- `plugins/soleur/test/git-repo-readiness-diag.test.sh`
- `scripts/bare-root-cwd-guard-probe.sh`
- `knowledge-base/project/specs/feat-bare-root-anchor-gate/decision-challenges.md`

## Files to Edit

- `.claude/hooks/session-rules-loader.sh`
- `.claude/hooks/session-rules-loader.test.sh`
- `.claude/hooks/README.md`
- `plugins/soleur/skills/git-worktree/scripts/git-repo-readiness-diag.sh`
- `apps/web-platform/server/git-lock-marker-telemetry.ts`
- `apps/web-platform/test/git-lock-marker-telemetry.test.ts`
- `plugins/soleur/commands/go.md` (one-sentence doc touch, Step 1 paragraph)
- `knowledge-base/engineering/architecture/decisions/ADR-099-git-surface-topology.md`

## User-Brand Impact

- **If this lands broken, the user experiences:** either the status quo (a
  misanchored session goes unmarked — the helper fails open by contract) or
  a false-positive redirect block injected into a legitimate bare-root
  maintenance session — advisory text, the maintenance commands still run.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing new — the telemetry-mirrored marker carries only `source=`
  (no path, no content); the redirect block names the operator's own CWD
  inside their own session context and reaches no sink.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal dev-machine machinery;
  worst case restores pre-fix behavior or prints advisory text.

*Scope-out override:* `threshold: none, reason: the only sensitive-path
touch is apps/web-platform/server/git-lock-marker-telemetry.ts — a one-token
MARKER_RE pattern addition carrying no user data, credentials, or auth
surface.`

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_BARE_ROOT_CWD marker in session output; mirrored to Better Stack via git-lock-marker telemetry where the hosted extractor runs (Bash-tool output); context-only on CLI session starts"
  cadence: "per session start (loader arm) / per readiness-gate run (diag arm)"
  alert_target: "none — informational marker, MIRRORED-NOT-PAGED by design"
  configured_in: "apps/web-platform/server/git-lock-marker-telemetry.ts MARKER_RE; .claude/hooks/session-rules-loader.sh"
error_reporting:
  destination: "existing marker pipeline (Better Stack mirror + Sentry breadcrumb) for Bash-emitted markers; session transcript otherwise"
  fail_loud: "a failing helper prints nothing and the loader still emits its envelope — the marker's absence is the only signal, caught by the fixture suites in CI"
failure_modes:
  - mode: "guard helper absent/stale (bare-root copy predates it)"
    detection: "loader fails open with no marker; .claude/hooks/session-rules-loader.test.sh row asserts the fail-open envelope; CI red on regression"
    alert_route: "CI failure"
  - mode: "masked/corrupt .git/config making --is-bare-repository lie"
    detection: "config-FILE predicate refuses detection; masked-config fixture row in both suites"
    alert_route: "CI failure"
  - mode: "predicate drift between the hook copy and the diag copy"
    detection: "parity test asserting the two predicate blocks agree"
    alert_route: "CI failure"
logs:
  where: "session transcripts (all harnesses), .claude/.session-manifests/ forensic rows, Better Stack marker mirror (hosted agent Bash output)"
  retention: "transcript/manifest lifetime; Better Stack retention"
discoverability_test:
  command: bash scripts/bare-root-cwd-guard-probe.sh
  expected_output: SOLEUR_BARE_ROOT_CWD
```

## Encryption Posture

Not applicable — no persistent data store and no new cross-component or
network connection; the marker rides the existing telemetry channel.

## Architecture Decision (ADR/C4)

- **ADR — amend `ADR-099-git-surface-topology`** (the topology authority):
  add an idiom rule recording that a session anchored at a bare repo root is
  detected at session start (`SOLEUR_BARE_ROOT_CWD` + redirect context),
  that file-touching work belongs in a linked worktree while repo
  maintenance stays legitimate there, and that the tracked overlay is a
  maintained `sync_bare_files` mirror — not deletable scratch. Add an
  Alternatives-considered row: PreToolUse deny (deferred — #3206),
  auto-worktree-create (rejected — cannot cd the session), plugin-level
  `""`-matcher arm (deferred — extension follow-up), do-nothing (rejected —
  the measured 16G overlay).
- **C4 views — no model change.** Enumeration performed against all three
  files (`model.c4`, `views.c4`, `spec.c4`): no new external human actor
  (the misanchored session is the existing founder/agent actor), no new
  external system or vendor, no new container or data store (the guard
  writes nothing new — the marker rides the existing telemetry edge), and
  no changed actor↔surface relationship. The new arm lives inside the
  already-modeled repo-local hook engine surface (`platform.engine.hooks`,
  whose description covers the SessionStart path) — no element or `view
  include` needs adding, and no element description is falsified.
- **Sequencing** — the ADR amendment lands in this PR alongside the
  mechanism it records.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** assessed inline (no subagent surface on this harness —
`Reviewed-Coverage: sequential-fallback`; the CTO-spawned technical rulings
this change needs are recorded as `pending - assumed:` rows in
`decision-challenges.md`)
**Assessment:** internal session-start machinery for the repo's own
worktree topology; detection predicate reuses the proven
`bare-head-self-heal.sh` contract; blast radius is bounded to
context-injection (fail-open, advisory).

### Product/UX Gate

**Tier:** none — no UI-surface file in Files to Create/Edit (mechanical
scan: no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, no
shared UI-surface terms).
**Pencil available:** N/A (no UI surface)

## GDPR / Compliance Gate

Trigger (d) checked: a `plugins/soleur/` payload file ships via plugin
update. Assessment (inline — the `soleur:gdpr-gate` agent is not spawnable
on this harness): the marker is a fixed literal + `source=` token with no
personal data; the in-context redirect names the operator's own CWD inside
their own session only. No special-category data, no new processing
activity, no Art. 30 trigger. No critical findings.

## Infrastructure (IaC)

None — no server, service, cron, vendor account, DNS, cert, secret, or
firewall change. The deferred bare-root cleanup is recorded as a follow-up
issue, not a plan phase.

## Guard Contract

### Guard 1 — bare-root CWD detector (`bare-root-cwd-guard.sh` + loader dispatch + diag arm)

**Property.** A session whose CWD is a bare repo root in this layout gets a
`SOLEUR_BARE_ROOT_CWD` marker and redirect context at session start; no
non-bare-root CWD produces either.

**Assembly.** The dispatch chokepoint is SessionStart invocation of
`.claude/hooks/session-rules-loader.sh` (registered in
`.claude/settings.json` AND `.devin/config.json` — two registrations, both
pre-existing) plus the `git-repo-readiness-diag.sh` READY arm invoked from
`go.md` Step 0.0; the predicate assembly is the three-term config-FILE
conjunction enumerated in Technical Considerations.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Remove the child call in session-rules-loader.sh → bare-root envelope loses the marker (dispatch vacuity) | RED |
| 2 | Weaken the predicate to `git rev-parse --is-bare-repository` alone → masked-config plain-clone fixture emits a false marker | RED |
| 3 | Drop the `--absolute-git-dir == $root/.git` term → a linked worktree of a bare repo emits the marker (second-member-of-must-not-fire row) | RED |
| 4 | Drop the `! -L "$root/.git"` term → a bare-root-shaped dir whose `.git` is a symlink emits the marker (the loader's own prompt-injection posture — symlinked git internals are rejected, not trusted) | RED |
| 5 | Suite harness: `mk_bare_root` fixture skips `git config core.bare true` → the fires-on-bare row goes red (proves the positive row is not vacuous-pass) | RED (of the mutated suite) |
| 6 | Guard precondition satisfied but property fails: helper prints non-marker junk or exits 1 → loader still emits a valid envelope with zero marker (fail-open must-PASS, not a green-by-accident row) | PASS (explicit contract row) |
| 7 | Diag arm: emit the marker but remove it from MARKER_RE → the telemetry drift guard's producer scan collects `SOLEUR_BARE_ROOT_CWD` from `skills/*/scripts/*.sh` and finds no extractor match | RED |

**Anchor.** The marker literal is produced in two files and consumed by
MARKER_RE; a single diff could rename both, so the anchor is the drift
guard's *derived* census (`test/git-lock-marker-telemetry.test.ts` walks the
producer tree) plus the parity test pinning the two predicate copies.

### Guard 2 — telemetry mirror registration

**Property.** Every `SOLEUR_BARE_ROOT_CWD` line a producer emits (any
`source=` variant) is matched by the hosted marker extractor, and no wedge
classification is attached (informational, never paged).

**Assembly.** MARKER_RE in
`apps/web-platform/server/git-lock-marker-telemetry.ts` is the single
chokepoint the extractor applies; producers are the census of `echo`/`printf`
senders under `plugins/soleur/skills/*/scripts/*.sh` + `SKILL.md` (the drift
guard's own scan).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Remove `SOLEUR_BARE_ROOT_CWD` from MARKER_RE → drift guard + the added mirror row go red | RED |
| 2 | Add the marker to WEDGE_RE instead → paging classifier mis-files an informational marker; the comment contract (MIRRORED-NOT-PAGED) is violated | RED |
| 3 | Emit a second `source=` variant the extractor's branch on `source=` can't discriminate → a `source=readiness-diag` line must match while a prose line containing the token mid-sentence must not (anchor the alternation at line start) | RED |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Gate session-start on git rev-parse --is-bare-repository at the harness level, not just in go.md Step 1" | Phase 1-2 (bare-root-cwd-guard.sh + loader arm); predicate upgraded to the config-FILE conjunction per ADR-173 | mapped |
| 2 | "emit a diagnostic marker and either redirect the session into a fresh worktree (existing --yes create <name> path) or refuse file-touching intents with a pointer to the guard" | FR marker + redirect context (Phases 1-2); the `refuse` arm is descoped — #3206 owns the PreToolUse deny | mapped (refuse arm descoped — justification below) |
| 3 | "the same hook site could carry a SOLEUR_BARE_ROOT_CWD marker so misanchored sessions are at least visible in telemetry" | Phase 3 (diag emission + MARKER_RE + drift-guard row) | mapped |
| 4 | "Cleanup path once anchoring is fixed: stop the sessions holding the root as CWD, then remove the overlay + scratch" | — | descoped — justification: operator-authorized host surgery on live sessions plus the tracked overlay is a deliberately maintained sync_bare_files mirror; filed as follow-up issue A |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.claude/hooks/bare-root-cwd-guard.sh` | "a new session-start hook arm" | asked |
| `session-rules-loader.sh` arm | "Gate session-start … at the harness level" | asked |
| `git-repo-readiness-diag.sh` marker | "SOLEUR_BARE_ROOT_CWD marker so misanchored sessions are at least visible in telemetry" | asked |
| MARKER_RE + telemetry test | "visible in telemetry" | asked |
| `.claude/hooks/bare-root-cwd-guard.test.sh`, loader test rows, `git-repo-readiness-diag.test.sh` | — | inferred — justification: the repo's guard-authoring contract (Guard Contract gate + fixture-battery conventions) requires the suites that pin the detector |
| `scripts/bare-root-cwd-guard-probe.sh` | — | inferred — justification: the Observability discoverability_test must name a committed repo-relative probe whose first token is allowlisted |
| `.claude/hooks/README.md` edit | — | inferred — documentation parity with the sibling arm (bare-head-self-heal has a subsection; the roster comment enumerates loader jobs) |
| ADR-099 amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; the redirect-vs-refuse fork and the overlay-is-maintained correction belong in the topology authority |
| `commands/go.md` doc touch | — | inferred — keeps the routing-level guard text coherent with the new earlier layer |
| `decision-challenges.md` | — | inferred — headless decision-class channel required by the pipeline contract |
| Follow-up issues A + B | "Cleanup path once anchoring is fixed" | asked (deferral tracked, not executed) |

### Split Assessment

- Subsystems touched: 4 — `.claude`, `plugins/soleur`, `apps/web-platform`, `knowledge-base`
- Planned files: 13 | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the 4-root spread is one mechanism (detect →
  mark → mirror → record); a split would strand the marker unmirrored or the
  guard undispatched, and the diff is under 500 lines.

## Acceptance Criteria

- [ ] `bash .claude/hooks/bare-root-cwd-guard.sh <fixture>` on a
  `mk_bare_root`-shaped dir prints a line starting
  `SOLEUR_BARE_ROOT_CWD source=session-start` followed by a bounded
  `[bare-root-cwd]` redirect block naming the `--yes create` path; rc 0.
- [ ] The same script on `mk_true_bare`, `mk_plain`, a linked worktree of a
  bare repo, a masked-config clone, a symlinked-`.git` dir, and a non-repo
  dir prints nothing and exits 0.
- [ ] A SessionStart envelope produced with `cwd` at a bare-root fixture
  contains the `SOLEUR_BARE_ROOT_CWD` marker and the redirect block in
  `additionalContext`, and the corpus line still reports `loaded: N of M`
  with N > 0; an envelope at a worktree fixture contains neither.
- [ ] With the helper renamed away, the loader still emits a valid envelope
  (fail-open contract) and no marker.
- [ ] `git-repo-readiness-diag.sh` at a bare-root fixture prints
  `SOLEUR_GIT_REPO_READY=true` AND `SOLEUR_BARE_ROOT_CWD
  source=readiness-diag`; at a worktree fixture it prints READY only; at a
  masked-config fixture it prints READY without the marker.
- [ ] `extractGitLockMarkers` in
  `apps/web-platform/server/git-lock-marker-telemetry.ts` matches a sample
  `SOLEUR_BARE_ROOT_CWD …` line, and the drift-guard suite passes with the
  diag's new emission.
- [ ] `bash scripts/bare-root-cwd-guard-probe.sh` prints
  `SOLEUR_BARE_ROOT_CWD` within 15 seconds with no credentials.
- [ ] ADR-099 carries the new idiom rule and the Alternatives row; no
  `ADR-<n>` ordinal is claimed.
- [ ] Follow-up issues #10391 (scratch cleanup) and #10392 (extension arm +
  sibling SessionStart audit) are filed and linked from this plan.
- [ ] `git grep -l 'SOLEUR_BARE_ROOT_CWD'` covers: the helper, the diag,
  MARKER_RE, both test files, the probe script.

## Test Scenarios

All scenarios are fixture-deterministic (no ambient machine state):

- **unit** — Given a `mk_bare_root` dir, when the guard runs, then the
  marker + redirect block print and rc is 0.
- **unit** — Given each non-bare fixture (true-bare, plain clone, linked
  worktree, masked-config, symlinked `.git`, non-repo), when the guard
  runs, then stdout is empty and rc is 0.
- **unit** — Given a bare-root fixture, when the loader hook runs with an
  envelope `cwd` there, then `additionalContext` contains the marker and
  the corpus stamp reports a nonzero count.
- **unit** — Given the helper deleted, when the loader runs at the bare
  fixture, then the envelope is still valid JSON and contains no marker.
- **unit** — Given a bare-root fixture, when `git-repo-readiness-diag.sh`
  runs, then stdout contains READY and `SOLEUR_BARE_ROOT_CWD
  source=readiness-diag`; given a masked-config fixture, then READY
  without the marker.
- **unit** — Given a sample marker line, when `extractGitLockMarkers`
  parses it, then one marker is returned and `wedged` classification does
  not fire.
- **integration** — `bash scripts/bare-root-cwd-guard-probe.sh` builds the
  fixture and prints the marker end-to-end under a 15 s bound.

## Non-Goals

- PreToolUse hard-deny on bare-root reads/writes — tracked by #3206.
- Deleting or shrinking the maintained `sync_bare_files` overlay; the
  scratch cleanup is follow-up issue A (operator-authorized, sessions
  stopped first).
- Auto-creating a worktree or `cd`-ing the session from the hook.
- Emitting the marker from `worktree-manager.sh`/`cleanup-merged` (that
  call path is the legitimate bare-root case).
- Plugin-level `hooks.json` arm, Codex/Grok/Concierge coverage — follow-up
  issue B.
- Suppressing `.claude/.session-manifests/` writes at the bare root.
- Changes to `wg-at-session-start-*` rule bodies or AGENTS.md corpus.

## Context

- Detection predicate precedent: `.claude/hooks/bare-head-self-heal.sh:44-51`
- Loader integration point: `session-rules-loader.sh` lines ~315-319 and
  the envelope tail at ~466-468
- Marker registry: `apps/web-platform/server/git-lock-marker-telemetry.ts:162`
- Drift guard: `apps/web-platform/test/git-lock-marker-telemetry.test.ts:297`
- Topology ADRs: ADR-099, ADR-173, ADR-179
- Related issues: #10383 (this), #3206, #10218, #7384, #7411, #8496, #8540

## Sharp Edges (recorded against this plan)

- `timeout` is absent on stock macOS: the loader arm reuses the existing
  `command -v timeout` conditional-array pattern, never a bare call.
- Negated-grep checks must still fail on rc 2 — the suites compare
  `grep -c` counts or use explicit `[[ $rc -eq 1 ]]` arms.
- The issue's proposed `--is-bare-repository` gate is superseded by the
  config-FILE predicate (ADR-173 masked-config false-`true`); the plan
  records the divergence rather than implementing the unsafe literal.
- Synthesized fixtures only (`cq-test-fixtures-synthesized-only`); any
  owning EXIT trap sits BEFORE `source test-helpers.sh`; every negative
  fixture row carries a positive control on the same input shape.
- The `## User-Brand Impact` section is complete and the
  `discoverability_test.expected_output` is a literal the probe prints —
  both halt gates at deepen-plan are written to pass.

## Enhancement Summary (deepen-plan pass)

Halt-gate results on this plan, verified mechanically on 2026-10-15:

- Phase 4.6 User-Brand: PASS — section present, threshold `none` +
  non-empty scope-out reason for the `apps/web-platform/server/` touch.
- Phase 4.7 Observability: PASS — all 5 fields populated; probe is
  `bash scripts/bare-root-cwd-guard-probe.sh` (allowlisted verb, <15 s,
  literal `SOLEUR_BARE_ROOT_CWD` expected output, no SSH, not suite-shaped).
- Phase 4.8 PAT sweep: PASS — zero hits.
- Phase 4.9 UI wireframe: SKIP — no UI-surface file.
- Phase 4.10 Encryption posture: SKIP — no new store/connection; section
  present declaring N/A.
- Phase 4.11 Guard Contract: PASS — `lint-guard-contract.py` scanned 2
  guard entries, no rejections.
- Phase 4.12 Scope Check: PASS — exactly one `## Scope Check`, every ask
  mapped or descoped-with-justification, no `status: BLOCKED`.

Research/review fan-outs (per-section agents, review panel) ran
**sequential inline** — this harness exposes no subagent tool;
`Reviewed-Coverage: sequential-fallback` applies and technical rulings are
`pending - assumed:` rows in `decision-challenges.md`.

## References

- Issue: #10383
- Deferred follow-ups filed: #10391 (bare-root scratch cleanup,
  operator-authorized), #10392 (plugin-level arm + sibling SessionStart audit)
- Adjacent: #3206 (hard-deny arm), #10218 (mirror stamp), #7384, #7411
- Learnings: `2026-10-06-a-guard-folded-its-probe-error-into-untracked-and-my-fix-broke-the-bare-root.md`, `2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification.md`, `2026-03-13-bare-repo-stale-files-and-working-tree-guards.md`, `2026-03-18-bare-repo-cleanup-stale-script-and-fetch-refspec.md`
