---
title: "fix: repo-write-boundary samples .git/shallow, the one repository-wide mutation git status cannot see"
date: 2026-09-21
slug: fix-repo-write-boundary-shallow-dimension
branch: feat-one-shot-7924-git-shallow-dimension
issue: 7924
closes: 7924
lane: cross-domain
type: fix
---

## Enhancement Summary

**Deepened on:** 2026-09-21 (deepen-plan pass, run inline — no Task/Agent harness in this
environment; all gates executed by the orchestrator, findings cited below).
**Sections enhanced:** 5 (The Change §1 sketch, Research Insights measured-facts, Risks &
Mitigations, Observability, Files Deliberately NOT Edited).

### Key Improvements

1. **Sketch corrected against its own precedent.** The original `_repo_boundary_dim_shallow` draft
   carried `_repo_boundary_digest "$(cat -- "$f")"` — a `cat` failure inside `$()` yields `""` and
   the digest still returns 0, manufacturing `present` on an unreadable file: the exact
   "capture failure must degrade the DIMENSION, never manufacture a verdict" class
   `_repo_boundary_dim_config`'s comment polices. The sketch now probes the digest tool up front
   (sibling precedent) and takes `cat`'s status through the assignment.
2. **Empirically-false claim corrected.** The plan asserted a *plain* `git fetch` can append graft
   entries on an already-shallow repo. Fixture-verified false on git 2.55.0 (fetch fills history,
   it does not sever it; fetching from a shallow remote *rejects* the ref absent `--update-shallow`).
   The digest requirement stands — a depth-bounded fetch on an already-shallow repo is the
   presence-same mutation — but every "plain fetch appends" justification is rewritten, including the
   #7922 followthrough probe's adjudication (now clean, not conditional).
3. **Fourth producer added.** `scripts/plugin-delivery-canary.sh:342` (`git -C "$root" fetch
   --depth 1`, `$root` = live toplevel, suite registered at `test-all.sh:1815`) survived the first
   census only because it was `head`-truncated; the untruncated re-run caught it. Scratch-repo fix +
   AC9b + suite arm now in scope.
4. **Observability probe defended against the Check-10 suite-shape detector** with a measured 9.0s
   runtime and the runner-wiring coverage citation, instead of letting the `*.test.sh` command sit
   as an unexamined regex hit.
5. **Citation fixes:** `test-all.sh`'s lone `fetch` mention is prose at `:73`, not `:3053`.

### New Considerations Discovered

- `refs/replace/**` is already in the lib's not-inspected heredoc — the Non-Goals deferral list is
  accurate, no new carve-out needed.
- All three cited AGENTS rule IDs resolve (`wg-architecture-decision-is-a-plan-deliverable` is
  migrated-but-active per `scripts/migrated-rule-ids.txt`); all cited issue numbers verified live
  (#7924 OPEN, #7922 OPEN, #7795/#7910 CLOSED); all cited learnings/ADR files exist.
- `git rev-parse --path-format` confirmed git ≥ 2.31 (RelNotes 2.31.0).

## Overview

`scripts/test-all.sh` wraps the battery in a before/after repository-state boundary
(`scripts/lib/repo-write-boundary.sh`) and treats a suite that writes into the live repository as
FATAL. `_repo_state` samples four measured dimensions — `head`, `worktree`, `config` (the shared
`--local` file), `refs` (heads+tags) — plus `wt`, the sibling-worktree set the classifier uses as a
harm-partition input. It does **not** sample `.git/shallow`.

That file lives in the git **common dir** — the object-store directory every linked worktree shares —
so a suite (or a script under test) that runs `git fetch --depth=N` truncates history visibility for
the **entire repository, including sibling worktrees belonging to other sessions**, and nothing sees
it: the boundary does not sample the dimension, and `git status --porcelain` cannot see an untracked
`.git/` internal either. Issue #7924 calls it the single most consequential repository-wide mutation
a test can make, and it is invisible to both instruments that exist to catch repository-wide
mutation. It already happened once in the wild: a `ccla-add.sh` ledger fetch left a worktree
`--is-shallow-repository true`, which silently corrupted an epoch derivation (`git log -S<anchor>`
returned the graft commit's date, not the introducing commit's).

**The change:** add `shallow` as a sixth manifest dimension — presence plus content hash when present
— resolved through `git rev-parse --git-common-dir` (never `--git-dir`, which on a linked worktree
points at the per-worktree dir and would miss the shared file entirely). Any delta classifies FATAL in
every regime: this is a shared-store write, but unlike the ADR-207 softened cells there is **no**
routine producer of a shallow flip (the only ones that exist are fixed in this same PR), and the harm
lands on *this* run's evidence — a mid-run shallow flip changes what `git log` answers inside the
window itself. Gated first on a sweep of current offenders: four battery-reachable producers exist —
three are the same `cla-signatures` ledger fetch, the fourth is `plugin-delivery-canary.sh`'s
materialize-reference fetch — and each is redirected into a scratch repo that never touches the live
common dir.

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Verified | Result |
|---|---|---|
| Issue #7924 open | `gh issue view 7924 --json state` → `OPEN`, labels `priority/p2-medium`, `type/chore` | premise holds |
| `scripts/lib/repo-write-boundary.sh` exists with `_repo_state` sampling head/worktree/config/heads+tags | `git show origin/main:` → 752-line lib; `_repo_state` at `:224`; manifest rows `head worktree config refs wt` | premise holds |
| `_repo_state` does NOT sample `.git/shallow` | `grep -n 'shallow\|git-common-dir'` over the lib → **zero hits** | premise holds |
| `apps/cla-evidence/scripts/ccla-add.sh` uses `--depth=1` | `:337` `git fetch --no-tags --depth=1 -q origin '+refs/heads/cla-signatures:refs/remotes/origin/cla-signatures'` | premise holds |
| `.git/shallow` lives in the common dir, shared by worktrees | measured live on this worktree (git 2.55.0): `--git-dir` → `.git/worktrees/feat-one-shot-7924-...`; `--git-common-dir` → `/data/git-repositories/jikig-ai/soleur/.git` | premise holds |
| Proposed mechanism vs ADR corpus | ADR-207 (`repo-write-boundary` harm partition) read in full — it owns this lib's design record; a new dimension is consistent with it, and its §3 exemption ledger is where the FATAL-vs-REPORT decision must be recorded | amendment required, no conflict |

**One premise the issue understated:** it names `ccla-add.sh` as "one known example". The sweep —
re-run **untruncated** (`git grep -nE 'git[[:space:]][^|;&]*\b(fetch|clone|pull|repack)\b[^|;&]*--(depth|deepen|shallow-since|shallow-exclude|unshallow|update-shallow)' origin/main`, 14 raw hits, each adjudicated) after a `| head` cut on the first pass hid a hit — found **four** battery-reachable producers:

| # | Site | Context | Battery-reachable? |
|---|---|---|---|
| 1 | `apps/cla-evidence/scripts/ccla-add.sh:337` | SUT + operator-facing script; fetch runs in the **caller's** repo | yes — driven by suite #2 |
| 2 | `apps/cla-evidence/test/ccla-add.test.sh:56` | suite harness preamble, cwd = live checkout | yes — registered at `scripts/test-all.sh:2716` |
| 3 | `apps/web-platform/test/cla-evidence/roster-entry-gate.test.ts:~226` | `execFileSync("git", ["fetch","--no-tags","--depth=1", ...], { cwd: repoRoot })` in `readRealLedger` | yes — REPO_WIDE_SUITES, runs in `test-webplat` |
| 4 | `scripts/plugin-delivery-canary.sh:342` | `git -C "$root" fetch --no-tags --depth 1 origin "$sha"` where `$root` is `git rev-parse --show-toplevel` — the **live** repo; its own comment already owns the live-repo write for tags (`:333-340`) | yes — `plugin-delivery-canary.test.sh` registered at `test-all.sh:1815`; fires when the delivered sha is absent locally |

Producers 1-3 fire only when `git show origin/cla-signatures:signatures/cla.json` fails — i.e. on a
checkout where that orphan branch was never fetched (every fresh CI checkout — `actions/checkout`
single-branch does not carry it) and on any operator worktree that has not fetched it. Producer 4
fires only when the delivered commit is missing from the local object store — rarer, but exactly the
case the canary exists to measure.

**A fifth site adjudicated as a non-producer, not fixed:** `scripts/followthroughs/
ccla-representative-icla-7922.sh:307` (the #7922 probe) runs a **plain** fetch — no `--depth`, plus
`--no-write-fetch-head` — into the live repo. A plain fetch cannot create or append `.git/shallow`
on either a non-shallow or an already-shallow repo (verified on the `mktemp` fixture above; its
`:239` comment — "the ledger fetch below writes `.git/shallow`" — overstates: a residue from before
its `:112` note dropped `--depth=1`). What it still writes is objects and
the `refs/remotes/origin/cla-signatures` ref — both already in the not-inspected/adjudicated set —
so the new dimension never flags it. Its suite (`:2723`) is fully fixture-hermetic — bare origin
fixtures under `mktemp`, probe run with cwd inside the fixture — so the suite never touches the live
common dir. Adjudicated clean, not edited.

**Out of scope, verified non-battery-reachable or non-live-repo:**

- `.github/workflows/*` `fetch-depth:` settings and `.github/actions/dev-migration-drift-probe` /
  `apply-github-infra.yml` `git fetch --depth=1` — disposable GH-hosted checkouts; the boundary only
  watches `scripts/test-all.sh` runs.
- `git clone --depth=1` sites in `apps/web-platform/server/inngest/functions/*.ts` — clones into
  per-fire temp dirs on the production Inngest host; a clone writes `.git/shallow` into the **clone**,
  never the source repo.
- `plugins/soleur/test/hosted-ship-shallow-merge-base.test.sh` — hermetic: clones into its own
  `mktemp` root; asserts `fetch --unshallow` behavior inside the fixture.
- `plugins/soleur/skills/git-worktree/test/*.test.sh`, `.claude/hooks/pre-merge-rebase*.test.sh` —
  all fetches target `mktemp` fixture repos (`-C "$work"`, `-C "$LOCAL"`).
- `apps/web-platform/scripts/cla-evidence/validate-roster.ts:49-50` — operator-facing remediation text
  already prescribes `git fetch --no-tags origin +refs/...` **without** `--depth`; a plain fetch does
  not create `.git/shallow` on a non-shallow repo.

### Measured facts established at plan time

- `git rev-parse --git-common-dir` on this linked worktree prints an **absolute** path; on a top-level
  checkout it prints the relative `.git`. `--path-format=absolute` (git ≥ 2.31) makes it unconditional.
  Repo requires worktree-capable git (≥ 2.5) everywhere this lib runs.
- This checkout is currently **not** shallow (`--is-shallow-repository` → `false`; no
  `.git/shallow` in the common dir).
- `.git/shallow` content is a newline-separated SHA list, appended in fetch order — order is state, so
  the content digest is over the raw bytes, never a sorted projection.
- `.git/shallow` mutation semantics, verified on `mktemp` fixtures (git 2.55.0): a **plain** `git
  fetch` of an unconnected orphan branch writes NO shallow file on a non-shallow repo and appends NO
  graft entry on an already-shallow one (fetch fills history, it does not sever it); fetching from a
  shallow remote does not propagate either — git *rejects* the ref ("shallow roots are not allowed
  to be updated") unless `--update-shallow` is passed. The file moves on `fetch
  --depth/--deepen/--shallow-since/--shallow-exclude/--update-shallow` and on `fetch --unshallow`
  (removes it). The content digest is what catches a *depth-bounded* fetch on an already-shallow
  repo — presence alone is unchanged there. This is why the issue asks for "presence, and content
  hash if present".
- Manifest-enumeration assertion at `scripts/lib/repo-write-boundary.test.sh:149` compares against
  `config head refs worktree wt ` (sorted) — `shallow` sorts between `refs` and `worktree`.
- `MIN_ASSERTIONS=57` floor at `repo-write-boundary.test.sh:1208`; conservation check
  `passes+fails == asserted` at `:1196`.
- `repo_boundary_next_action` mapping pinned per-dimension at `:729` (`_want` assoc over
  `head worktree config refs`) and substring-checked at `:461`.
- `repo_boundary_render_not_inspected` ends in a **hardcoded heredoc** (`repo-write-boundary.sh:709-739`)
  listing unmeasured surfaces — `.git/shallow` is currently absent from it (the gap itself); sibling
  unsampled neighbor `.git/objects/info/grafts` (the deprecated grafts mechanism — also silently rewrites
  visible history) is the honest addition.
- The lib's own header comment says "the four dimensions" (`:128`) and `render_not_inspected` says "of
  the five dimensions" (`:692`) — literal counts that must move with the change.
- `scripts/test-all.sh` itself runs **no** `git fetch` (grep returns only the `:73` prose comment
  about linear-fetch suites); the BEFORE/AFTER `_repo_state` calls are at `:1651` and `:2997`,
  classify at `:3001`, FATAL render at `:3017`/`:3098-3104`. The function contract check at
  `:571-581` names six public functions — the new dimension function is private
  (`_repo_boundary_dim_*`), so that list does not move.
- No other file outside `scripts/lib/repo-write-boundary.test.sh` enumerates the dimension set
  (grepped `scripts/`, `.claude/hooks/`, `apps/`).

### Test surface

`scripts/lib/repo-write-boundary.test.sh` (1219 lines, 57+ assertions) already ships the fixture
machinery this change needs: `new_probe` (`git init` + seed commit under `mktemp`), `pgit` (hermetic
git with GLOBAL/SYSTEM config pinned empty), `state()` (runs `_repo_state` with the probe as cwd,
salted digest fixed), `classify_in`, `sibling_probe`-style linked-worktree fixtures (arm 20 at `:358`
runs `git -C "$p" worktree add`), instrument self-test, `MIN_ASSERTIONS` floor, and per-arm `[FATAL]
fixture setup failed` precondition guards (`require_tag` pattern at `:103`).

### Institutional learnings that bind

- `2026-08-27-i-committed-the-defect-class-i-was-closing-eleven-times.md` — this lib's own origin
  learning: the fix reproduced the defect class it was closing. Every helper here is held to that
  standard (subshell-safe, stdin-safe, digest-probed).
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — the Guard
  Contract below is written BEFORE the guard, with mutation rows, not `command → output` scenarios.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — harness rows:
  a suite-side edit and a non-canonical must-PASS are mandatory, not optional.
- `2026-09-10-i-graded-lines-when-the-unit-was-the-command.md` — the offender-fix assertions grade the
  *command* (scratch-dir-scoped clone), not the presence of `--depth` on a line.
- `2026-09-19-cleanup-on-failure-is-a-property-of-the-window-not-the-arms.md` — the scratch clone
  introduces a new temp dir into `ccla-add.sh`; its cleanup must hang off the existing `TMP_FILES` /
  `trap cleanup EXIT` discipline (`:314-324`), which already documents that the trap must return 0.
- AGENTS.md `hr-write-boundary-sentinel-sweep-all-write-sites` — the offender sweep enumerates ALL
  battery-reachable shallow writers, not just the one the issue named.
- `2026-09-07` plan for #7795 (`2026-09-07-fix-repo-write-boundary-tag-shared-store-softening-plan.md`)
  — the sibling change to this same lib; this plan mirrors its structure because it survived five
  review seats.

### Conventions

- Bash in `scripts/lib/` is a **sourced lib**: no `pipefail`, no owned `EXIT` trap (ADR-129), herestrings
  and process substitutions over tempfiles, values digested with the per-run `REPO_BOUNDARY_SALT`.
- Claims are **rendered from the check**: the inspected list is generated from the manifest, so adding
  the dimension propagates the operator-facing claim for free — and the not-inspected heredoc is the
  known hardcoded exception (debt recorded in the #7795 plan §Alternative Approaches).
- Severity is a three-class partition: FATAL / REPORT / UNMEASURABLE (ADR-207), keyed on attribution.
- Test arms are `ck`-counted, floor-guarded, and assert observed verdict lines (never absence-only).

### Property List (Phase 0.6b)

- **P1** A suite that creates, removes, or content-changes `.git/shallow` in the repository's common
  dir between the two samples is classified FATAL.
- **P2** The dimension resolves through `--git-common-dir`, so a write issued from a **sibling**
  worktree is still observed from this worktree's snapshot (the file is shared).
- **P3** The rendered "inspected:" claim names the dimension when measured at both boundaries — free,
  by the manifest-driven renderer.
- **P4** No battery-reachable command still performs a shallow-capable write into the live repository:
  every producer either fetches full (no `--depth`, no `.git/shallow` write on a non-shallow repo) or
  fetches inside a scratch repo it owns.
- **P5** An unreadable/absent common dir degrades the dimension to `not-measured` (UNMEASURABLE),
  never to a manufactured verdict.

### Cut List (Phase 0.6b)

- **Static shallow-authorship lint** (a `battery-tag-authorship.test.sh` analogue) — *cut.* That guard
  exists because ADR-207 cell 6's safety rests on a set the classifier cannot inspect. This plan adds
  **no softened cell**: the property is decidable at runtime by the dimension itself, so the static
  bound buys nothing. If a future change ever softens `shallow` to REPORT, its own guard contract must
  add the static bound then.
- **`.git/objects/info/grafts` as a seventh dimension** — *cut to a documented residual.* The
  deprecated grafts file is the same defect class (invisible history rewrite in the common dir) but is
  outside #7924's scope; it lands in the not-inspected heredoc and the deferred-issue list, not in
  this diff.
- **`refs/remotes/**` / loose-object sampling** — already listed not-inspected; unchanged.

### Value proposition (Phase 0.6c)

Not a cost- or performance-saving justification — the change adds one file read + one digest per
snapshot; no measurement burden falls on this gate.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --json number,title,body --limit 200` was
queried (2026-09-21) and each planned path — `scripts/lib/repo-write-boundary.sh`,
`scripts/lib/repo-write-boundary.test.sh`, `apps/cla-evidence/scripts/ccla-add.sh`,
`apps/cla-evidence/test/ccla-add.test.sh`, `apps/web-platform/test/cla-evidence/roster-entry-gate.test.ts`
— was searched in issue bodies via `jq --arg`. Zero matches.

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (no brainstorm ran; one-shot pipeline path). The reconcilable
claims are the issue's:

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "`ccla-add.sh` is one known example" | **Four** battery-reachable producers exist (table above — the untruncated census added `plugin-delivery-canary.sh:342`, which a `head`-truncated first pass missed) | all four fixed in scope |
| "`--depth=1` is load-bearing there for a different reason" | the fetch exists to read ONE file off an orphan branch; depth bounds the fetch size | preserved — the scratch clone keeps `--depth=1`, just pointed at a throwaway repo |
| "resolve through `--git-common-dir`, not `--git-dir`" | verified: on a linked worktree `--git-dir` → `.git/worktrees/<n>` (no `shallow` inside); `--git-common-dir` → the shared `.git` | `_repo_boundary_dim_shallow` uses `--path-format=absolute --git-common-dir`; a linked-worktree fixture arm pins it |
| FATAL-vs-soften unspecified | ADR-207 partitions by attribution; common-dir writes are sibling-writable in principle | **FATAL unconditionally** — decision + rationale recorded as an ADR-207 amendment (§Architecture Decision) |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this is the repo's own test
battery gate. The operator-facing failure is a battery that passes while a suite silently shallow-
truncated the shared repository, surfacing later as wrong history-derived output (the measured
instance: an epoch derivation returning the graft commit's date).

**If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — the
dimension reads a file of commit SHAs and digests it under the per-run salt; nothing is published.

**Brand-survival threshold:** none — internal dev/CI tooling only; no sensitive-path diff (the change
touches `scripts/lib/`, `apps/cla-evidence/`, `apps/web-platform/test/` — none match the canonical
`SENSITIVE_PATH_RE` at `plugins/soleur/skills/preflight/SKILL.md:493`).

## The Change

### 1. The dimension — `_repo_boundary_dim_shallow` (new, in `scripts/lib/repo-write-boundary.sh`)

```bash
_repo_boundary_dim_shallow() {
  # .git/shallow lives in the COMMON dir — shared by every worktree of the
  # checkout — so it is resolved through --git-common-dir, NEVER --git-dir: on a
  # linked worktree --git-dir is .git/worktrees/<n>, a per-worktree path that
  # carries no shallow file and would read "absent" while the shared repo is
  # shallow underneath it (#7924). --path-format=absolute because the bare form
  # returns a relative ".git" on a top-level checkout.
  local common f raw
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || return 1
  [[ -n "$common" ]] || return 1
  f="$common/shallow"
  # Absent is a legitimate measured state — decide it BEFORE the probes so an
  # absent file cannot be masked by a degraded tool.
  [[ -e "$f" ]] || { printf 'absent\n'; return 0; }
  # `_repo_boundary_dim_config` precedent: probe the digest tool up front — a
  # missing sha256sum must degrade the DIMENSION to not-measured, never digest
  # "" and call it a state.
  _repo_boundary_digest probe >/dev/null 2>&1 || return 1
  # The ASSIGNMENT carries cat's status: an existing-but-unreadable/non-regular
  # path is a capture failure, not a digest of "". `_repo_boundary_digest
  # "$(cat …)"` inline would swallow the failure — the substitution yields "" on
  # cat's non-zero and digest still returns 0, manufacturing `present`.
  raw="$(cat -- "$f")" || return 1
  printf 'present\t'
  _repo_boundary_digest "$raw" || return 1
}
```

Body line: `shallow\tabsent` or `shallow\tpresent\t<digest>`. Content is digested under the per-run
salt exactly like the other dimensions — the SHAs are not secret, but the digest keeps the body
bounded and uniform, and presence-vs-content is carried by the `absent`/`present` token the
classifier reads, not by the digest.

### 2. `_repo_state` wiring

After the `refs` block and before the `wt` block (measured dimensions first, classification input
last):

```bash
  if shallow="$(_repo_boundary_dim_shallow)"; then
    manifest+=$'manifest\tshallow\tmeasured\n'
    body+="shallow"$'\t'"$shallow"$'\n'
  else
    manifest+=$'manifest\tshallow\tnot-measured\n'
  fi
```

### 3. The classify arm — FATAL in every regime

A dedicated block after the head/worktree loop, gated on `unmeasurable` like the others:

| Transition | Verdict | Detail names |
|---|---|---|
| `absent` → `present:<d>` | FATAL | ".git/shallow was CREATED — the whole repository, every worktree, is now shallow" |
| `present:<d>` → `absent` | FATAL | ".git/shallow was REMOVED (the `git fetch --unshallow` shape)" |
| `present:<d1>` → `present:<d2>` | FATAL | "graft set CHANGED — a depth-bounded fetch on an already-shallow repo moved the boundary" |

**No `shared_store` softening.** Stated against ADR-207's own standard, which grants a softened cell
only where a sibling *routinely* produces the shape: post-fix, **no routine producer of a shallow
delta exists** — the four that did are removed in this PR. And unlike a sibling ref move, the harm is
not merely unattributable, it lands on this run: a mid-window shallow flip changes what `git log` and
friends answer for every suite still to run, inside this worktree and every sibling. A REPORT would
print-and-pass a corruption of the evidence base itself. A sibling running a *pre-fix* checkout's
`ccla-add.sh` mid-battery can still false-FATAL a run — that window closes at merge, and the FATAL is
true in the meaningful sense (the run's history reads were compromised).

### 4. Rendered surfaces

- `_repo_boundary_dim_prose`: `shallow) printf 'repository shallow state (.git/shallow in the shared common dir)'`.
- `repo_boundary_next_action`: `shallow) printf 'git rev-parse --is-shallow-repository; cat "$(git rev-parse --git-common-dir)/shallow"; git fetch --unshallow origin   # a suite ran a --depth/--shallow fetch into this repo'`.
- `repo_boundary_render_not_inspected` heredoc: add `- .git/objects/info/grafts (the deprecated grafts
  mechanism — a second invisible history rewrite, still unsampled)`; `.git/shallow` itself is now
  inspected, so nothing is removed.
- Comment-count corrections: `--- the four dimensions ---` (`:128`) and `of the five dimensions`
  (`:692`) become accurate ("measured dimensions" phrasing that does not recount — the `wt` row is a
  classification input, which is why the counts were already drifting).

### 5. The offender fixes (the issue's gate)

All four producers keep their shallow bound — moved into a **scratch repo** so the shallow file lands
in a throwaway repo:

- `apps/cla-evidence/scripts/ccla-add.sh` — the fallback at `:336-338` becomes: `mktemp -d` scratch
  registered with the existing `TMP_FILES`/cleanup-trap discipline (the trap's must-return-0 contract
  at `:316-324` is preserved — a dir needs `rm -rf`, so the cleanup gains a `TMP_DIRS` sibling array),
  resolve the remote URL once (`git remote get-url origin`, die-2 with the existing honest message if
  absent), then `git clone -q --depth=1 --no-tags --single-branch --branch cla-signatures "$url"
  "$scratch/repo"` and copy `signatures/cla.json` out of the clone into `$LEDGER_FILE`. Nothing in the
  caller's repo is written: no ref, no objects, no `.git/shallow`.
- `apps/cla-evidence/test/ccla-add.test.sh` — the harness preamble at `:55-62` gets the same scratch-
  clone shape to populate `$WORK/ledger.json` (which the suite already feeds the SUT via
  `CCLA_ADD_LEDGER`, so the SUT's fast path and fallback are both bypassed under test).
- `apps/web-platform/test/cla-evidence/roster-entry-gate.test.ts` — `readRealLedger`'s fallback
  (`cwd: repoRoot` fetch at `:226`) becomes an `execFileSync` `git clone --depth=1 --no-tags
  --single-branch --branch cla-signatures <remote-url> <mkdtemp>` + `readFileSync` of
  `signatures/cla.json` from the clone, with the temp dir under `os.tmpdir()` and removed in
  `finally`. `cleanGitEnv()` stays on every spawn.
- `scripts/plugin-delivery-canary.sh` — `materialize_reference`'s fallback fetch (`:342`) needs the
  delivered `$sha` *inside* a repo it can `git archive` from. Redirect the whole materialize path for
  the missing-sha case into a scratch repo under the canary's existing `$SCRATCH` (`git init` +
  `git remote add origin "$(git -C "$root" remote get-url origin)"` + `git fetch --no-tags --depth 1
  origin "$sha"` + `git archive "$sha" -- "$PLUGIN_SUBDIR" | tar -x`), so neither the shallow write
  nor the object write touches the live repo. The `cat-file -e` check stays pointed at `$root` — the
  scratch path is only for the absent-sha fallback, preserving the fast path exactly.

### 6. Test arms (`scripts/lib/repo-write-boundary.test.sh`)

New arms (numbering continues the suite's `--- N.` convention; exact numbers derived at /work):

1. **created → FATAL**: probe repo, `pgit -C "$p" fetch` a shallow ref OR directly `pgit -C "$p"
   rev-parse --git-common-dir` + `echo $sha > common/shallow` between `state` calls → exactly one
   `^FATAL[[:space:]]+shallow` line naming CREATED.
2. **linked-worktree resolution (the load-bearing arm)**: `git -C "$p" worktree add` a second
   checkout; take `state` **inside the linked worktree**; write `shallow` into the **main** repo's
   common dir mid-window → FATAL. This is the arm that reddens if the dimension ever resolves
   `--git-dir`.
3. **content change on already-shallow → FATAL**: pre-seed `common/shallow` with one SHA before both
   snapshots; append a second SHA mid-window → FATAL naming CHANGED.
4. **removed → FATAL**: pre-seed; `rm` mid-window → FATAL naming REMOVED.
5. **sibling present, still FATAL**: `sibling_probe`-style fixture (non-empty `elsewhere`) + shallow
   creation → FATAL, pinning §3's no-softening decision.
6. **common dir unreadable → UNMEASURABLE**: dimension function fails (fixture: `git-common-dir`
   unresolvable) → `shallow: not-measured` in the manifest, `UNMEASURABLE` in classify, no FATAL.
7. **must-PASS, non-canonical**: shallow written into a **different** repo's common dir mid-window
   (`git -C "$other" fetch --depth=1` against a fixture remote) → clean; the dimension reads THIS
   repo's common dir only.
8. **harness-honesty**: the created-arm asserts it *observed* a `FATAL\tshallow` line — an absence-
   only assertion passes on an empty verdict.

Plus: the existing manifest-enumeration arm (`:149`) updated to `config head refs shallow worktree wt `; the
next-action iteration lists at `:461` and `:729` extended with `shallow` (`_want[shallow]` anchors on
`unshallow`/`is-shallow-repository`); rendered-inspected anchor list gains the shallow prose string;
`MIN_ASSERTIONS` raised by the executed-arm count derived at /work.

## Files to Edit

- `scripts/lib/repo-write-boundary.sh` — `_repo_boundary_dim_shallow` (new); `_repo_state` wiring;
  `repo_boundary_classify` shallow arm; `_repo_boundary_dim_prose`; `repo_boundary_next_action`;
  not-inspected heredoc (`info/grafts` line); the two literal dimension-count comments.
- `scripts/lib/repo-write-boundary.test.sh` — manifest assertion; next-action loops + `_want`;
  rendered-inspection anchor list; ~8 new arms; `MIN_ASSERTIONS` bump.
- `apps/cla-evidence/scripts/ccla-add.sh` — scratch-clone ledger fallback + `TMP_DIRS` cleanup.
- `apps/cla-evidence/test/ccla-add.test.sh` — scratch-clone ledger acquisition.
- `apps/web-platform/test/cla-evidence/roster-entry-gate.test.ts` — scratch-clone `readRealLedger`.
- `scripts/plugin-delivery-canary.sh` — scratch-repo materialize fallback (§5 last bullet).
- `scripts/plugin-delivery-canary.test.sh` — an arm pinning the scratch-repo fetch shape (the fetch's
  `-C`/destination operand is under `$SCRATCH`, never the live toplevel).
- `knowledge-base/engineering/architecture/decisions/ADR-207-repo-write-boundary-harm-partition.md`
  — amend: the sampled-dimension set gains `shallow`; the "what was NOT softened" enumeration gains a
  row with the rationale above.

## Files Deliberately NOT Edited

Kept out of `## Files to Edit` so a path extraction cannot read them as targets.

- `.github/workflows/*.yml` (`fetch-depth: 1` / `git fetch --depth=1` sites) — disposable CI checkouts;
  the boundary does not watch them and the workflow file edits would ride a test-gate PR for nothing.
- `plugins/soleur/test/hosted-ship-shallow-merge-base.test.sh` and every
  `plugins/soleur/skills/git-worktree/test/*.test.sh` clone/fetch — hermetic fixtures that write
  shallow only into their own `mktemp` clones; verified during the sweep.
- `apps/web-platform/scripts/cla-evidence/validate-roster.ts` — its operator-facing remediation string
  already prescribes a `--no-tags` fetch **without** `--depth`, which does not write `.git/shallow` on
  a non-shallow repo; editing it would also widen this PR into the roster validator's own test
  contract.
- `apps/web-platform/server/inngest/functions/*.ts` `--depth=1` clones — production Inngest host,
  per-fire temp clones; unreachable by this boundary and untouched by the issue.
- `scripts/followthroughs/ccla-representative-icla-7922.sh` — the #7922 probe's **plain** live-repo
  fetch is shallow-safe on any repo state (a plain fetch cannot create or append `.git/shallow` —
  fixture-verified; its own `:239` comment overstates). Its suite is fixture-hermetic.
- `tests/scripts/test-git-data-birth-readiness-gate.sh` (`:1940` `git clone --depth 1 file://…`),
  `plugins/soleur/test/hosted-ship-shallow-merge-base.test.sh` (`:48`), `scripts/dogfood/
  grok-gpu-bootstrap.sh` (`:221` — a provisioning clone into a fresh workspace, not the live repo),
  `event-ship-merge.ts` (`--unshallow` on the production host) — all adjudicated non-live-repo or
  non-battery during the census.
- `scripts/battery-tag-authorship.test.sh` — tag-author bound only; no shallow analogue is added (see
  Cut List).

## Files to Create

None besides this plan's own artifacts. The ADR deliverable is an **amendment** to ADR-207, not a new
ordinal — the decision extends an existing ADR's design record rather than making a new one.

## Implementation Phases

### Phase 1 — RED: pin the dimension before it exists

Write the new suite arms (§6) against the current lib: manifest-enumeration, shallow-created,
worktree-resolution, content-change, removal, sibling-regime, not-measured, must-PASS,
harness-honesty. They fail now — the dimension does not exist. Run
`bash scripts/lib/repo-write-boundary.test.sh` and record the failing arm list.

### Phase 2 — GREEN: the dimension

Implement §1–§4 in `scripts/lib/repo-write-boundary.sh` until the suite exits 0 with the raised
`MIN_ASSERTIONS` floor.

### Phase 3 — remove the four battery-reachable producers

§5 fixes in `ccla-add.sh`, `ccla-add.test.sh`, `roster-entry-gate.test.ts`, and
`plugin-delivery-canary.sh`. Each keeps its depth bound inside a scratch repo; each is asserted by its
own suite anchoring on the command shape (the fetch/clone target is the scratch dir — graded per
`2026-09-10-i-graded-lines`, not a `--depth` grep).

### Phase 4 — the ADR amendment

Amend ADR-207 per §Architecture Decision.

### Phase 5 — verification

`TEST_GROUP=scripts bash scripts/test-all.sh` (the shard that owns this suite) exits 0 with no
`[FATAL]` boundary block; `bash apps/cla-evidence/test/ccla-add.test.sh` and the roster-entry-gate
vitest pass; `python3 scripts/lint-guard-contract.py` and `scripts/lint-infra-no-human-steps.py` pass
on this plan; `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0.

## Guard Contract

### Guard 1 — the `shallow` boundary dimension

**Property.** A `.git/shallow` creation, removal, or graft-set change in the repository's **common
dir** between the BEFORE and AFTER samples classifies `FATAL` — in every regime, including when
sibling worktrees exist — and the dimension appears in the rendered inspected list whenever it was
measured at both boundaries. No shallow delta is ever silent, and no shallow delta is ever softened.

**Assembly.** The property quantifies over: `_repo_boundary_dim_shallow` (the sampler —
`--path-format=absolute --git-common-dir` resolution, the `-e` presence test, the salted content
digest); `_repo_state`'s manifest+body wiring (the dimension only exists to the classifier if the
manifest row is emitted); the `shallow` arm of `repo_boundary_classify` and its `unmeasurable` gate;
`_repo_boundary_dim_prose` and `repo_boundary_next_action` (the rendered claim and the remedy — a
FATAL whose next-action names nothing is the claim-outruns-content defect this lib exists to close);
and the single consumer chain in `scripts/test-all.sh` — BEFORE sample `:1651`, AFTER sample `:2997`,
classify `:3001`, FATAL→`failed`→`exit 1`. There is one classifier and one consumer; both are named.

**Mutation matrix.**

| Mutation | Why it must fail (RED) |
|---|---|
| **Own dispatch:** `_repo_state` omits the `shallow` manifest/body row, or `_repo_boundary_dim_shallow` returns 0 unconditionally | the manifest-enumeration arm reddens immediately; and no shallow arm can ever observe a delta — the guard reports nothing while claiming the dimension. Suite must also trip `MIN_ASSERTIONS`/conservation if arms are deleted outright. |
| **Wrong root:** resolve `--git-dir` (or `--absolute-git-dir`) instead of `--git-common-dir` | the linked-worktree arm (§6.2) must go RED: on a linked worktree the per-worktree git dir has no `shallow`, so the sampler reads `absent` while the shared repo is shallow — the exact miss the issue names. |
| **Presence-only:** drop the content digest so `present` is a constant | the graft-change arm (§6.3) must go RED — a fetch that appends boundary SHAs on an already-shallow repo becomes invisible. |
| **Softening:** route the arm through `shared_store` (REPORT when siblings exist) | the sibling-regime arm (§6.5) must go RED — the no-softening decision is the contract, not an implementation detail. |
| **Asymmetric arm:** classify only `absent→present` | the removal arm (§6.4) must go RED — `git fetch --unshallow` is the same repository-wide mutation in the other direction. |
| **Cross-boundary cwd:** resolve the common dir at *classify* time instead of inside the snapshot | a reorder/lifetime row: the property is about the measurement window — re-deriving at classify time re-opens the "classification input read after the window closes" class ADR-207 §2 forbids; the state is what the sampler emitted, so a classify-time `cat` of the file would read post-window content. Caught by the worktree-resolution arm only if the sampler owns the read. |
| **Degrade collapse:** treat a non-existent common dir as `absent` rather than capture failure | the not-measured arm (§6.6) must go RED — `absent` is a legitimate measured state; conflating it with capture failure manufactures a clean baseline on a broken read. |

**Harness rows.**

| Harness edit (the SUITE, not the guard) | Required outcome |
|---|---|
| Neuter §6.1's fixture so `.git/shallow` is never written | must be RED — the arm asserts an observed `FATAL\tshallow` line, not the absence of one (§6.8). |
| Delete the new arms outright | must be RED via `MIN_ASSERTIONS` bump + `passes+fails == asserted` conservation at `:1196`. |
| Write the shallow file with a relative `--git-common-dir` assumption in the fixture | must RED legibly: fixture asserts `[[ -d $common ]]` before writing, hard-failing setup like `require_tag` does, so a pathological git reports FIXTURE error not a phantom SUT pass. |
| **Must-PASS, non-canonical:** shallow flip in a *different* repository's common dir (§6.7) | must PASS clean — proves the dimension reads the snapshot repo's own common dir rather than flagging any shallow write anywhere on the machine. |

**Anchor.** The comparison is snapshot-to-snapshot within one run — the BEFORE body line is the stored
reference, carried inside the run's own state (a lib swap between boundaries is already visible via
the manifest-pairing UNMEASURABLE arm). There is no out-of-commit registry to drift against; what must
move together is the sampler + the suite, and that pairing is pinned by the manifest-enumeration arm
and the `MIN_ASSERTIONS` floor in the same diff.

## Observability

The strict Phase 2.9 trigger set (`apps/*/server`, `apps/*/src`, `apps/*/infra`, `plugins/*/scripts`,
or new infrastructure) does not match `scripts/lib/`, `apps/cla-evidence/`, or `apps/web-platform/test/`,
and this plan introduces no production surface. The block is supplied anyway — same precedent as the
#7795 change — because the deliverable is a guard whose failure mode is silence.

**Layer citation (`hr-observability-layer-citation`).** Layers 1-6 N/A (no server surface, route,
Inngest function, cron, or host); layer 7 N/A (the lib runs under this repo's own `scripts/test-all.sh`,
not a customer-shipped `plugins/` artifact). The covering channel is the **synchronous runner exit code
plus the CI job log**; every `alert_route` below resolves to it.

```yaml
liveness_signal:
  what: the boundary epilogue `scripts/test-all.sh` prints after the AFTER snapshot — `[FATAL] A SUITE
        WROTE TO THE LIVE REPOSITORY` with per-dimension `[shallow]` detail lines, plus the rendered
        inspected list naming the shallow dimension
  cadence: every `scripts/test-all.sh` invocation — local battery, CI test job
  alert_target: the runner's exit code (1 whenever any FATAL is present), surfaced as CI job status
  configured_in: scripts/test-all.sh:1651 (BEFORE), :2997 (AFTER), :3001 (classify), :3017/:3098-3104 (render)
error_reporting:
  destination: the runner's stderr epilogue and the non-zero exit propagated to the CI job
  fail_loud: yes — a FATAL increments `failed`, which alone drives `exit 1`
failure_modes:
  - mode: the dimension is never wired — manifest row absent, deltas invisible while the claim grows
    detection: manifest-enumeration arm + the rendered-inspected anchor arm in
        scripts/lib/repo-write-boundary.test.sh
    alert_route: suite exit 1 → scripts/test-all.sh exit 1 → CI test job failure
  - mode: the sampler resolves the per-worktree dir on a linked worktree and reads "absent" forever
    detection: the linked-worktree fixture arm (§6.2)
    alert_route: same
  - mode: a suite flips shallow on an operator's already-shallow repo and only the graft list moves
    detection: the content-change arm (§6.3); operationally self-announcing via the FATAL epilogue
        naming the transition
    alert_route: same
  - mode: the suite goes vacuous — arms deleted, floor still green
    detection: MIN_ASSERTIONS bump + passes+fails == asserted conservation; this suite is counted as
        firing by scripts/guard-vacuity-floor.test.sh
    alert_route: same
  - mode: residual — an operator machine whose repo is ALREADY shallow before the run sees FATAL on any
        suite fetch that appends graft entries. Accepted: the mutation is real and shared-store-wide;
        remediation is `git fetch --unshallow`, named verbatim by repo_boundary_next_action.
    detection: the FATAL block itself names `.git/shallow` and the transition
    alert_route: human read of the epilogue — no exit-code distinction between this and a suite-authored flip
logs:
  where: runner stdout/stderr; CI runs captured in the GitHub Actions job log
  retention: GitHub Actions default retention; local runs terminal-scoped
discoverability_test:
  command: bash scripts/lib/repo-write-boundary.test.sh
  expected_output: "repo-write-boundary.test.sh:" and "0 failed"
```

**Probe honesty (deepen-plan §4.7 false-hit argument, stated so the suite-shape proxy is not
silently ignored).** Check 10's cap detector regex-flags `*.test.sh` commands as presumed-suites
that outrun the 15s sandbox cap. Measured here: the suite completes in **9.0s wall** on this host
(57 assertions, git 2.55.0 — `time bash scripts/lib/repo-write-boundary.test.sh`, run during
deepen). The margin is thin, and it is the right command anyway: the signal being discovered is the
boundary's own verdict path, and a `grep`-for-the-literal probe would verify a string, not the wired
guard — the #7795 sibling plan reached the same conclusion and shipped the same command. The runner-
level half of the chain (FATAL → `failed` → `exit 1`) is already pinned by the suite's existing
sandboxed-`test-all.sh` arms (`repo-write-boundary.test.sh:~375-450`), so no new runner arm is added.

## Architecture Decision (ADR/C4)

**ADR-207 is amended, not superseded.** `wg-architecture-decision-is-a-plan-deliverable` fires because
the change extends that ADR's design record: the sampled-dimension set and the exemption ledger are
both part of its `## Decision`. The amendment adds:

- `shallow` to the sampled-dimension enumeration, resolved through `--git-common-dir` — the first
  dimension whose target lives in the common dir rather than the worktree;
- a new row in §3's **"What was NOT softened"** list: `shallow` deltas stay FATAL in every regime,
  with the two-part rationale — (a) the ledger's admission test is "a sibling *routinely* produces
  it" and post-sweep no routine producer of a shallow flip exists; (b) unlike a softened ref move,
  the harm lands on this run's own evidence (history reads change inside the window);
- one line correcting the dimension count wherever the ADR numbers the set.

`### Sequencing` — none; the decision is true at merge.

**C4: no impact**, checked against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) — not by grepping the
feature's noun but by enumerating: (a) **external human actors** — none added; (b) **external
systems/vendors** — none; the scratch clone still talks to `origin`, an edge already modeled; (c)
**containers/data stores** — none; `.git/shallow` is a file inside an existing store, not a modeled
element (the model does not descend to `scripts/test-all.sh` internals — verified: zero hits for
`test-all|repo-write|boundary|battery|shallow` across all three files); (d) **access relationships** —
none change. Cardinality backstop: no workflow/cron/monitor slug is added, so embedded edge
cardinalities do not move; `plugins/soleur/test/c4-count-parity.test.sh` is prescribed as an AC.

## Acceptance Criteria

### Pre-merge (PR)

All criteria are pre-merge; this plan has no post-merge steps.

1. `bash scripts/lib/repo-write-boundary.test.sh` exits 0, its final line reports `0 failed`, and its
   assertion floor equals **`57 + <new arms>`** — derived at /work, never a hardcoded pass count
   (the #7795 plan's AC1 precedent).
2. The manifest-enumeration arm asserts exactly `config head refs shallow worktree wt ` — anchored,
   so a dropped dimension is RED, not absent.
3. A probe fixture whose only mid-window delta is a **created** `.git/shallow` in the common dir
   yields exactly one `^FATAL[[:space:]]+shallow` line naming the CREATED transition.
4. A **linked-worktree** fixture — `state` taken inside `git worktree add`'d checkout, `shallow`
   written into the main repo's common dir — yields `^FATAL[[:space:]]+shallow`. This is the arm
   that dies if the dimension ever resolves `--git-dir`.
5. A fixture pre-seeded shallow whose graft file gains one SHA mid-window yields `^FATAL[[:space:]]+shallow`
   naming the CHANGED transition; one whose file is removed yields REMOVED.
6. A sibling-worktree fixture (non-empty `elsewhere`) + shallow creation still yields `FATAL` —
   pinning the no-softening decision.
7. A fixture where `git rev-parse --git-common-dir` is unresolvable yields `shallow: not-measured` in
   the manifest and an `UNMEASURABLE` classify line — never a manufactured `absent`→FATAL.
8. A run whose only shallow write lands in a **different** repo's common dir yields zero FATAL lines
   (the must-PASS row).
9. `apps/cla-evidence/scripts/ccla-add.sh` contains no `git fetch` or `git clone` whose target is the
   caller's repository: the ledger fallback's clone destination is under a `mktemp` dir cleaned by the
   script's own trap — asserted by a suite arm anchored on the command shape, not on the `--depth`
   token.
9b. `scripts/plugin-delivery-canary.sh`'s `materialize_reference` performs its missing-sha fetch and
   `git archive` inside a repo under `$SCRATCH` — asserted by an arm in
   `scripts/plugin-delivery-canary.test.sh` anchored on the command shape (the fetch's `-C` operand /
   the archive's `-C` operand resolves under `$SCRATCH`, never the `git rev-parse --show-toplevel`
   result). The suite exits 0.
10. `apps/cla-evidence/test/ccla-add.test.sh` and
    `apps/web-platform/test/cla-evidence/roster-entry-gate.test.ts` acquire the ledger identically —
    scratch clone under a temp dir — and both suites exit 0 in their respective groups.
11. `TEST_GROUP=scripts bash scripts/test-all.sh` exits 0 with no `[FATAL]` boundary block; on a
    checkout where `origin/cla-signatures` is absent, running the ccla-add suite leaves
    `git rev-parse --is-shallow-repository` printing `false`.
12. `python3 scripts/lint-guard-contract.py` passes against this plan file;
    `python3 scripts/lint-infra-no-human-steps.py` passes against it;
    `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0.
13. The ADR-207 amendment is committed: `grep -n 'shallow'
    knowledge-base/engineering/architecture/decisions/ADR-207-*.md` names the dimension and the
    not-softened row.
14. Sweep AC (hr-write-boundary-sentinel-sweep-all-write-sites): re-run the **untruncated** census
    `git grep -nE 'git[[:space:]][^|;&]*\b(fetch|clone|pull|repack)\b[^|;&]*--(depth|deepen|shallow-since|shallow-exclude|unshallow|update-shallow)' -- . ':(exclude)knowledge-base/project/plans/2026-09-21-fix-repo-write-boundary-shallow-dimension-plan.md' ':(exclude)knowledge-base/project/specs/feat-one-shot-7924-git-shallow-dimension/'`
    (the exclusions are load-bearing: this plan and its tasks.md quote `--depth` invocations in
    prose and would self-hit) and adjudicate every hit — each remaining shallow-capable invocation
    on a battery-reachable path must have its receiving repository inside a suite-owned
    `mktemp`/`mkdtemp`/`$SCRATCH` root, or be named in this plan's adjudicated-not-edited list. A
    `| head`-truncated grep does not satisfy this AC — that is how `plugin-delivery-canary.sh:342`
    was nearly missed at plan time.

## Test Scenarios

Every scenario is a `mutation → guard reddens` pair (ADR-180); `command → output` lives in the ACs.

| # | Mutation applied to the design | Guard that must redden |
|---|---|---|
| T1 | dimension function returns success with empty output | manifest arm + every shallow arm (vacuous) |
| T2 | `--git-dir` substituted for `--git-common-dir` | linked-worktree arm |
| T3 | digest replaced by literal `present` token | graft-change arm |
| T4 | arm gated on `-z "$shared_store"` inversion (softened) | sibling-regime arm |
| T5 | only `absent→present` classified | removal arm |
| T6 | `-e` weakened to `-f` (unreadable path reads as absent) | not-measured arm |
| T7 | new arms deleted | `MIN_ASSERTIONS` floor + conservation check |
| T8 | offender fix reverted to in-place `--depth=1` fetch in `ccla-add.sh` | AC9's command-shape arm in `ccla-add.test.sh` + a real battery run would FATAL on `shallow` — the guard catching its own motivating offender |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Operator machines where the repo is already shallow: a suite's depth-bounded fetch now moves the graft set → FATAL | self-announcing + `repo_boundary_next_action` names `git fetch --unshallow`; arguably correct — the mutation is real (a *plain* fetch cannot move the file — fixture-verified — so only shallow-capable invocations trip it) |
| **Precedent diff (deepen-plan §4.4):** the new dim follows the `_repo_boundary_dim_config`/`_repo_boundary_dim_refs` sibling contract — stdout = the state value, rc 0 = measured, rc 1 = not-measured, digest tool probed up front, no tempfile/EXIT trap (ADR-129). Deviations from precedent, deliberate: (a) resolves `--git-common-dir` not `--git-dir` (the point of the change); (b) two-token state (`absent` / `present\t<digest>`) vs config's per-key list — a file whose *existence* is the signal, closer to a `refs` measured-empty case than to a key listing | the mutation matrix's degrade-collapse row pins the rc contract; the linked-worktree arm pins deviation (a) |
| A sibling worktree running a pre-fix `ccla-add.sh` mid-battery false-FATALs a run | transient window, closes at merge; the FATAL is true (the run's history evidence was corrupted) |
| `git rev-parse --git-common-dir` returns a relative path on some git version | `--path-format=absolute` (git ≥ 2.31); worktree support already forces ≥ 2.5 |
| Scratch clone in `ccla-add.sh` needs `origin` URL resolution | `git remote get-url origin` with the existing honest `die` fallback; a missing remote is the same failure class the script already names |
| `.git/shallow.lock` mid-fetch read | a torn read still digests *something* different → FATAL — correct direction (a mutation was in flight) |

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Drop `--depth=1` and keep fetching into the live repo | **Rejected.** A plain fetch does not move `.git/shallow` (fixture-verified), so dropping depth would clear THIS dimension — but it keeps writing `refs/remotes/origin/cla-signatures` + objects + FETCH_HEAD into the shared store to read one file, and it drops the fetch-size bound the flag exists for. The scratch clone removes *all* live-repo writes, not just the shallow one. |
| Sample `.git/shallow` via `--git-dir` | **Rejected** — the issue's core point: per-worktree path, misses the shared file. Pinned by the linked-worktree arm. |
| Soften under `shared_store` like refs | **Rejected** — see §The Change 3 and the ADR-207 amendment; no routine producer exists post-sweep, and the harm lands on this run's evidence. |
| Static battery authorship lint for shallow writers | **Cut** (Phase 0.6b) — no softened cell means nothing the classifier can't inspect; the runtime dimension is the guard. |
| Assert shallow absence per-suite (the #7910 pattern) | **Rejected as the fix** — one suite protecting itself is what the issue already cites as insufficient; the shared guard is the deliverable. |

## Non-Goals / Deferrals

- `.git/objects/info/grafts` and other unsampled common-dir surfaces (`refs/notes`, `refs/replace`,
  packed-refs internals): documented in the not-inspected heredoc; a follow-up tracking issue naming
  the grafts residual is filed at work time (re-evaluation trigger: any future issue about invisible
  history rewrites).
- `refs/remotes/**` sampling: residual carried forward from the #7795 plan's own deferral, unchanged.
- CI-side `fetch-depth` hygiene: out of this boundary's reach by construction.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal test-runner/tooling change on the repo's own battery
gate. Assessed against all 8 domain rubrics inline (pipeline context — no domain-leader fan-out
available); the nearest-adjacent domain is Engineering/devex, whose interest is fully covered by the
suite arms and the ADR amendment rather than a separate review seat.

## Sharp Edges

- A plan whose `## User-Brand Impact` section omits the threshold fails deepen-plan Phase 4.6 — filled
  above (`none`, with the sensitive-path check named).
- `repo_boundary_render_not_inspected` is a **hardcoded heredoc** — the only place the claim is not
  rendered from the manifest. Do not let the new dimension need a manual listing anywhere else; the
  inspected side is free, the not-inspected side gains `info/grafts` only.
- `--git-common-dir` is relative on a top-level checkout — `--path-format=absolute` is load-bearing,
  not tidiness.
- `[[ -f ]]` vs `[[ -e ]]`: a non-regular or unreadable `shallow` path must degrade to not-measured,
  never read as `absent` — `absent` is a verdict, not a fallback. **Superseded at review, see the
  addendum below:** not-measured renders UNMEASURABLE — a non-blocking row — for a node git itself
  treats as a real availability change. The shipped answer is a third measured state, `unreadable`.
- The scratch clone keeps `--depth=1` **inside** the clone — an assertion anchored on "no `--depth`
  token in the file" would be both unachievable and wrong; grade the command's destination operand.
- `ccla-add.sh`'s EXIT trap must keep returning 0 — the new `TMP_DIRS` cleanup slot must not turn the
  documented exit codes (2/3/4) into a bare 1.

## Review amendments (as-built, post-panel)

The 9-seat review panel (PR #8510) found the following against the shape prescribed above; the
implementation was amended before merge rather than annotating around it.

- **The `unreadable` measured state replaces `not-measured` for an existing-but-unreadable node.**
  The sketch above (`[[ -e ]]` + `cat`) had three measured failure modes: `cat` on a FIFO blocks
  forever; `-e` follows links so a dangling symlink reads as `absent` (a real node laundered into
  "nothing there"); and returning 1 for an existing non-regular node renders UNMEASURABLE — a
  non-blocking row — even though git itself reads an unreadable shallow file as *not shallow*, a
  real availability change. The sampler now requires `-f && -r` for `present`, emits `unreadable`
  for `[[ -e || -L ]]`, and reserves `return 1` for common-dir/digest-tool failure. `cat --` was
  dropped for `cat` (the `--` is a GNUism BSD `cat` rejects).
- **`repo_boundary_next_action` takes the transition detail as `$2`.** The prescribed single string
  ran `git fetch --unshallow` for every transition — but on a REMOVED verdict the repo is already
  complete and `--unshallow` exits 128 ("does not make sense"), so the remedy could not execute in
  exactly the state it was for. REMOVED/non-regular transitions now prescribe diagnosis
  (`is-shallow-repository`, `ls -l`, `worktree list`, `fsck`); CREATED/CHANGED keep `--unshallow`.
- **Manifest pairing is the union of both snapshots.** The loop iterated the before manifest only;
  a dimension present in `after` but not `before` fell through to the shallow comparator with an
  empty before-value and fabricated a FATAL. After-only dimensions now emit UNMEASURABLE — once.
- **Producers extract the committed blob, not the checkout.** `cp` of a checked-out `cla.json`
  inherited the clone's `core.autocrlf`/smudge filters and any post-checkout hook; all ledger
  consumers now `git show HEAD:signatures/cla.json`. The canary fetches the SHA **directly by
  URL** — a `remote add` would persist a credential-bearing URL into the scratch repo's
  `.git/config` — and validates `DELIVERED_SHA` as `^[0-9a-f]{40}$` before it reaches the fetch
  refspec or the `git archive` operand. `--` separators precede URL/path operands.
- **The runner's recovery block is gated to head/worktree FATALs** — the ref-surgery recipe is
  irrelevant to a shallow verdict and its `next:` line now carries the real remedy.
- **Suite additions beyond the plan's arm list:** stable `present→present` must-PASS (the plan's
  arms were all-delta — a "present always FATALs" mutant survived them), same-cardinality graft
  swap (the append-only arm passed a `wc -l`-keyed mutant), FIFO and dangling-symlink fixtures,
  the after-only-manifest union arm, the `wt` prose arm, and the foreign-repo arm's positive
  write-witness. Floors: `repo-write-boundary` 66→72, `ccla-add` 118→125, canary 122→126.
- **Doc corrections folded in:** the ADR's "first common-dir dimension" claim (false — `config`
  and `refs` already read shared state) and the `ccla-representative-icla-7922.sh` claim that its
  plain fetch writes `.git/shallow` (it carries no depth flag) were both corrected.
