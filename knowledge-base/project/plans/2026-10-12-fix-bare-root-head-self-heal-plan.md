---
title: "fix: self-heal a dangling bare-root HEAD at SessionStart"
date: 2026-10-12
slug: bare-root-head-self-heal
branch: feat-one-shot-bare-head-self-heal
lane: single-domain
type: fix
detail_level: more
requires_cpo_signoff: false
---

# fix: self-heal a dangling bare-root HEAD at SessionStart

## Overview

In this repo's layout the root (`/data/git-repositories/jikig-ai/soleur`) has `core.bare=true` with
`gitdir .git`, and every feature branch lives in a linked worktree. After a PR merged and its
branch was deleted, the root's `.git/HEAD` was left as `ref: refs/heads/<deleted-branch>`. A
symbolic HEAD that names a missing ref is not an error to git, but it makes `git rev-parse HEAD`
fail and `--abbrev-ref HEAD` print the literal `HEAD`, so the `[session-context] branch:` line in
the SessionStart snapshot read `HEAD (unknown)`. The same dangling HEAD also breaks
`worktree-manager.sh sync-bare-files` (it runs `git read-tree HEAD`, `worktree-manager.sh:4460+`),
which is how the bare root's on-disk copies of hooks and `AGENTS*.md` go stale. It was fixed by hand
with `git symbolic-ref HEAD refs/heads/main`.

This plan makes the SessionStart loader repair that state itself, with zero model tokens and one
greppable marker line, and nothing else.

**Locating the hook (done):** the hook that prints `[session-context] branch:` is
`.claude/hooks/session-rules-loader.sh` (the `WS_BRANCH` assignment, "Session-context snapshot
(#5319)" block). It is registered once in `.claude/settings.json` SessionStart (matcher
`startup|resume|clear|compact`) and once in `.devin/config.json`. No `plugins/soleur/hooks`
SessionStart hook prints that line.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "Add to the existing SessionStart hook" | The right place is the loader, but **not as a second `settings.json` entry**: Claude Code runs a matcher's hooks concurrently, so a sibling hook cannot be ordered before the loader's `WS_BRANCH` read, and a new registration also needs a `devin-dispositions.tsv` row (`devin-matcher-parity.test.sh`). | Call a small helper script **from inside the loader**, before `WS_BRANCH`. No new registration, no TSV row, Devin sessions get the heal for free (the loader is already bound in `.devin/config.json`). |
| "print exactly one marker line" | A SessionStart hook's stdout is a single JSON envelope; a bare line on stdout would corrupt it. | The helper prints the marker on its own stdout; the loader captures it and appends it to `additionalContext` as a trailing line (same placement rule as the tmpfs-guard block). The helper is directly testable as "stdout is exactly one line". |
| "no-op in worktrees" | Verified: in a linked worktree `git config core.bare` still reads `true` (shared config) but `git rev-parse --is-bare-repository` reads `false`, and `--git-dir` != `--git-common-dir`. A worktree's own HEAD is a different file than the root HEAD. | Gate on `--is-bare-repository == true` AND `git-dir == git-common-dir` (belt and braces). |
| "git rev-parse HEAD fails" | Measured on git 2.55: a dangling symbolic HEAD makes `rev-parse --abbrev-ref HEAD` print `HEAD` with rc 0 (not fail), so the loader's `\|\| echo "(unknown)"` guard never fires. | Not a defect to fix here; the heal removes the trigger. Test asserts on the observable (`branch: main`). |

## Research Insights

- **Premise validation:** no issues/PRs cited. Cited paths verified present on this branch:
  `.claude/hooks/session-rules-loader.sh`, `.claude/settings.json` SessionStart block,
  `.claude/hooks/session-rules-loader.test.sh`. ADR corpus grep for `symbolic-ref` / `dangling HEAD`
  hits only ADR-207 and ADR-258 (unrelated write-boundary / reaper decisions); no ADR rejects an
  automatic bare-root HEAD repair.
- **Loader constraints (header + README "Sharp Edges"):** `set -uo pipefail` with `trap ERR ->
  emit_core_only_fallback`; `set -e` is deliberately off; every external call needs a `|| ...`
  guard because the ERR trap fires on a failing command substitution in assignment position
  (a past comment claimed otherwise and was disproved in place). A non-zero exit or ERR-trap path
  degrades the session to the fallback envelope. The new call must therefore be a child process
  whose failure is swallowed.
- **Positional contract:** envelope line 1 stamp, line 2 manifest, lines 3-5 `[session-context]`,
  rule bodies after, tmpfs alarm block LAST. Existing tests assert lines 3-5 positionally. The
  marker is appended at the end so a healthy session's envelope is byte-identical to today's.
- **Bare-root files are a synced mirror:** `sync_bare_files` extracts every tracked file from HEAD
  into the root. The new helper reaches the root only after that sync, and the sync needs a
  resolving HEAD. Bootstrap order is therefore: merge -> next successful root sync lands loader +
  helper -> from then on drift self-heals. A stale root loader without the helper keeps today's
  behaviour (helper call fails open). Documented in the README, not engineered around.
- **Test infrastructure:** `scripts/test-all.sh` auto-registers `.claude/hooks/*.test.sh` by glob;
  `plugins/soleur/test/lib/git-fixture-env.sh` provides the tripwire + hermetic git env for fixtures
  (see `constraint-scaffold/test/bite-proof.test.sh` for the sourcing pattern);
  `incident-sandbox-coverage.test.sh` only constrains suites that reach `emit_incident` (this one
  does not), but sourcing `lib/test-incident-sandbox.sh` is the hook-suite convention and costs
  nothing.
- **Open Code-Review Overlap:** None (`gh issue list --label code-review` bodies searched for
  `session-rules-loader.sh`, its test, and the hooks README: no matches).

### Property List (Phase 0.6b)

1. A bare root whose HEAD names a non-resolving branch is repaired to `refs/heads/main` at session start.
2. A HEAD that resolves (main or not), a non-bare repo, a linked worktree, a detached HEAD, and a repo without `refs/heads/main` are never modified.
3. A repair is observable as exactly one greppable line; a non-repair emits nothing.
4. The hook can never fail or degrade because of the repair, and the repair costs no model tokens.

### Cut List (Phase 0.6b)

- Second `settings.json` SessionStart registration -> buys property 1 but cannot be ordered before `WS_BRANCH` and adds a Devin TSV row -> cut; call from the loader.
- Incident-ledger row / persistent heal log -> buys "monitorable" beyond property 3 -> cut; the marker in session context and transcripts is the signal the brief asked for. Revisit only if the marker proves insufficient.
- Guardrail hook blocking `git symbolic-ref` / `git branch -m` at the root -> explicitly out of scope; follow-up only if the marker recurs (see Non-Goals).
- AGENTS.md / AGENTS.rules.md rule -> forbidden by the brief (per-session token cost).
- Healing worktree HEADs or non-main targets (e.g. "last good branch", `origin/HEAD`) -> brief fixes the target to `main`; cut.

## Scope Check

Ask-to-plan mapping: heal only when bare + dangling (Phase 1 helper) / only if `main` exists
(Phase 1) / one marker line (Phase 1 + Phase 2) / idempotent, silent no-op when healthy, no-op
non-bare and worktree, never touch a resolving HEAD (Phase 1, tests H2-H5, H7) / fail-open (Phase 1
`exit 0` everywhere, Phase 2 child-process call, tests H9, L3) / zero model tokens (pure bash+git) /
shell test with the five named cases (Phase 3) / no AGENTS rule (Non-Goals). No `inferred` items
beyond README + loader-header documentation (Phase 4), which the repo's header convention for the
loader requires.

## User-Brand Impact

**If this lands broken, the user experiences:** a session that boots with a degraded or missing
rules corpus (the loader is the only injector of `AGENTS.rules.md`) or that keeps reporting
`branch: HEAD` at the bare root. Worst plausible regression is the helper call erroring the
loader; the ERR-trap fallback still injects the corpus, and the helper runs as a child process
whose failure is swallowed.

**If this leaks, the user's [data / workflow / money] is exposed via:** no data surface. The helper
reads ref names and writes one symbolic ref in the local repo; the ref name echoed into the marker
is control-character-stripped and length-capped before it enters agent context.

**Brand-survival threshold:** aggregate pattern

Rationale for not `single-user incident`: no credentials, user data, or tenant boundary is
touched, and the one shared-blast-radius component (the loader) is protected by the child-process
isolation, the ERR trap, and a loader-level fail-open test (L3).

## Implementation Phases

### Phase 1 — Helper `.claude/hooks/bare-head-self-heal.sh` (new, mode 100755)

Contract: `bare-head-self-heal.sh [dir]` (default `$PWD`). Always exit 0. Prints one line
`SOLEUR_BARE_HEAD_HEALED from=<old-ref> to=refs/heads/main` on stdout only when it performed the
repair; prints nothing otherwise. All git via `git -C "$dir"`, stderr discarded.

Decision chain (each step `|| exit 0`, ordered cheapest-first so a normal non-bare checkout costs
one `git` fork):

1. `[[ "$(git -C "$dir" rev-parse --is-bare-repository)" == true ]]` — excludes non-bare repos and
   linked worktrees (verified: `false` inside a worktree of a bare root).
2. `rev-parse --absolute-git-dir` equals `rev-parse --path-format=absolute --git-common-dir` —
   second, independent worktree exclusion (a worktree's HEAD is not the root's HEAD).
3. `old=$(git symbolic-ref -q HEAD)` rc 0 and non-empty, `old == refs/*` — a detached HEAD, or a
   corrupt one, exits here untouched.
4. `git show-ref --verify -q "$old"` succeeds -> HEAD resolves (main or not) -> exit 0 untouched.
5. `git show-ref --verify -q refs/heads/main` fails -> nothing safe to point at -> exit 0 untouched.
6. `git symbolic-ref HEAD refs/heads/main` (git's own plumbing, takes `HEAD.lock`, handles
   packed-refs/reftable). On failure (lock held, read-only fs) exit 0 with NO marker — a marker
   claims a repair that happened.
7. `printf` the marker with `old` passed through `tr -d '\000-\037' | cut -c1-200`.

No `set -e`; `set -uo pipefail` only, matching the loader. No network, no model call.

Concurrency: two sessions starting together both reach step 6 with the same target; the second
writes the identical value, and the loser of a `HEAD.lock` race exits silently. Idempotent by
construction.

### Phase 2 — Loader wiring `.claude/hooks/session-rules-loader.sh`

- Immediately before the `WS_BRANCH=$(...)` line (so the branch line reflects the repaired HEAD):
  `HEAL_OUT=$(bash "$(dirname "${BASH_SOURCE[0]}")/bare-head-self-heal.sh" "$REPO_ROOT" 2>/dev/null || true)`
  then `BARE_HEAL_MARKER=$(printf '%s\n' "$HEAL_OUT" | { grep -m1 '^SOLEUR_BARE_HEAD_HEALED ' || true; })`.
  Both assignments carry their own `|| true` (ERR-trap safety, per the file's CORRECTION note). The
  `grep` filter means a stub/helper that prints anything else cannot inject lines into context.
  Hook-relative helper path, same convention as the `strip.sh` source at the top of the file.
- Append `${BARE_HEAL_MARKER:+$'\n'$BARE_HEAL_MARKER}` to `OUT_BODY` after `${TMPFS_ALARM_BLOCK}`
  (trailing placement; healthy envelope unchanged).
- Add job 10 to the header's "what deleting the hook costs" enumeration.

### Phase 3 — Tests `.claude/hooks/bare-head-self-heal.test.sh` (new, mode 100755)

Synthesized fixtures only (`mktemp -d`, throwaway repos, no real refs). Source
`lib/test-incident-sandbox.sh` first and `plugins/soleur/test/lib/git-fixture-env.sh` for the
tripwire and hermetic env; skip with `UNRESOLVED:` + exit 3 if git/jq missing (same as the loader
suite). Fixture builders: `mk_bare_root` (normal repo with one commit on `main`, optionally extra
branch `feat`, then `git config core.bare true` — reproduces the real "stale files + `.git` dir +
core.bare" layout), `mk_true_bare` (`git init --bare` + pushed commit, gitdir == dir), and
`dangle` (`git symbolic-ref HEAD refs/heads/gone`).

Helper cases:

| # | Fixture | Assert |
|---|---|---|
| H1 | bare root, HEAD -> `gone` (missing), main exists | stdout is exactly `SOLEUR_BARE_HEAD_HEALED from=refs/heads/gone to=refs/heads/main` (one line), `symbolic-ref HEAD` == main, rc 0 |
| H2 | H1 after healing, run again | stdout empty, HEAD still main (idempotent) |
| H3 | bare root, HEAD -> main (healthy) | stdout empty, HEAD unchanged |
| H4 | bare root, HEAD -> existing `feat`, main exists | stdout empty, HEAD still `feat` (never touches a resolving HEAD) |
| H5 | NON-bare repo, HEAD -> `gone`, main exists | stdout empty, HEAD still `gone` |
| H6 | bare root, HEAD -> `gone`, no `refs/heads/main` | stdout empty, HEAD still `gone` |
| H7 | linked worktree of a bare root whose root HEAD dangles; run with dir = worktree | stdout empty, root HEAD still `gone` |
| H8 | bare root, detached HEAD | stdout empty, HEAD detached unchanged |
| H9 | not-a-repo dir; and bare root with `HEAD.lock` pre-created | rc 0, stdout empty (no false marker), HEAD unchanged |
| H10 | true bare (`git init --bare`, gitdir == dir), HEAD -> `gone`, main exists | heals (second bare shape) |

Loader-integration cases (run `session-rules-loader.sh` with `{"cwd": <bare root fixture>}`, the
loader's own `setup_repo` fixture shape plus `core.bare true`):

| # | Fixture | Assert |
|---|---|---|
| L1 | bare root, HEAD dangling | `additionalContext` line 3 is `[session-context] branch: main \| ...`, marker line present exactly once and after the rule bodies, second invocation has no marker |
| L2 | bare root, healthy | `additionalContext` contains no `SOLEUR_BARE_HEAD_HEALED` |
| L3 | temp copy of the loader beside a STUB helper that prints junk and exits 7 | loader rc 0, envelope is valid JSON with all fixture rules loaded, no junk/marker in context (fail-open + the `grep` filter) |

Test-bites verification (done during `work`, not committed): for each of the following mutations
of the helper the named case(s) must go RED, then restore — drop step 1 (H5), drop step 2 (H7),
drop step 4 (H3/H4), drop step 5 (H6), print the marker before the `symbolic-ref` write (H9),
remove the `grep` filter in the loader (L3). The suite must also assert a non-vacuous floor: the
case counter equals the number of declared cases, and an `ASSERT`-count of zero exits non-zero
(pattern from `git-fixture-env-shell.test.sh`).

### Phase 4 — Docs

- `.claude/hooks/README.md`, "Rule-corpus loader" section: add a "Bare-root HEAD self-heal"
  subsection — what it does, the exact marker, the no-op list, the bootstrap-order note
  (needs one root sync after merge), how to grep (`SOLEUR_BARE_HEAD_HEALED` in session transcripts
  / `additionalContext`), and the **follow-up trigger**: if the marker shows up repeatedly, the
  drift source is a root-level `git checkout`/`branch -m`/`gh pr merge --delete-branch` and a
  guardrail blocking `git symbolic-ref HEAD` / `git branch -m` at the bare root should be filed
  then (out of scope now).
- Nothing in `AGENTS.md` / `AGENTS.rules.md`.

## Files to Create

- `.claude/hooks/bare-head-self-heal.sh` (mode 100755)
- `.claude/hooks/bare-head-self-heal.test.sh` (mode 100755)

## Files to Edit

- `.claude/hooks/session-rules-loader.sh` (helper call before `WS_BRANCH`, trailing marker, header job 10)
- `.claude/hooks/README.md` (loader section: self-heal subsection)

No change to `.claude/settings.json`, `.devin/config.json`, `devin-dispositions.tsv`, or
`scripts/test-all.sh` (the `.claude/hooks/*.test.sh` glob already registers the new suite).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash .claude/hooks/bare-head-self-heal.test.sh` passes (H1-H10, L1-L3).
- [ ] `bash .claude/hooks/session-rules-loader.test.sh` still passes unchanged (positional line contract intact).
- [ ] `bash .claude/hooks/settings-hook-exec-bit.test.sh` and `bash .claude/hooks/devin-matcher-parity.test.sh` pass (no registration change).
- [ ] `git ls-files -s .claude/hooks/bare-head-self-heal.sh .claude/hooks/bare-head-self-heal.test.sh` shows mode `100755` for both.
- [ ] `git diff --name-only origin/main...HEAD` shows no `AGENTS.md` / `AGENTS.rules.md` and no `settings.json`.
- [ ] Each Phase 3 mutation turns the named case RED (recorded in the PR description).
- [ ] README subsection names the marker string verbatim and the follow-up trigger.
- [ ] Marker format is exactly `SOLEUR_BARE_HEAD_HEALED from=<ref> to=refs/heads/main`.

### Post-merge (operator)

- [ ] None required. (After the next `sync-bare-files` the root carries the new loader + helper; if the root HEAD is dangling at that moment the sync itself fails, so heal it once by hand as before — the helper prevents recurrence, it cannot bootstrap itself past a broken sync.)

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_BARE_HEAD_HEALED line in SessionStart additionalContext, emitted only on an actual repair; a healthy session is silent by design, so absence is the healthy state, not a liveness gap"
  cadence: per session start, only when drift exists
  alert_target: none required — operator greps transcripts; promote to a guardrail only if it recurs
  configured_in: .claude/hooks/bare-head-self-heal.sh, wired by .claude/hooks/session-rules-loader.sh
error_reporting:
  destination: none — fail-open by contract (a failed repair prints no marker and leaves HEAD as found)
  fail_loud: false (deliberate: a SessionStart helper must never degrade the rules load)
failure_modes:
  - mode: HEAD.lock held / read-only fs, repair not performed
    detection: next session still shows `branch: HEAD` and no marker
    alert_route: none (self-retries each session)
  - mode: helper missing at a stale bare root
    detection: `branch: HEAD` persists after merge; resolved by the next sync-bare-files
    alert_route: operator notices the branch line
logs:
  where: session transcript / additionalContext
  retention: Claude Code transcript retention
discoverability_test:
  command: bash .claude/hooks/bare-head-self-heal.test.sh
  expected_output: "0 failed"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — local developer-tooling change to a SessionStart hook.

## Test Scenarios

See Phase 3 tables (H1-H10, L1-L3) and the test-bites mutation list.

## Non-Goals

- A guardrail hook blocking `git symbolic-ref HEAD` / `git branch -m` at the bare root. Possible follow-up **only if** the marker shows repeated drift; no tracking issue now because the trigger is observational, not a known gap (record the trigger in the README).
- Healing to anything other than `refs/heads/main`; healing worktree HEADs; healing a detached HEAD.
- Hardening `sync_bare_files` against a dangling HEAD (separate script, separate concern; the self-heal removes its trigger).
- Any AGENTS.md / AGENTS.rules.md rule.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or placeholder fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern` with rationale.
- Do NOT register the helper as its own SessionStart hook: concurrent hook execution makes the branch line racy and it adds a Devin disposition row.
- Every external call added to the loader needs its own `|| true`: the ERR trap fires on a failing command substitution even in assignment position.
- `git config core.bare` is `true` inside linked worktrees (shared config); only `rev-parse --is-bare-repository` and the git-dir/common-dir comparison distinguish the root from a worktree.
- Marker string interpolates a ref name read from `.git/HEAD`: strip control characters and cap length before it enters `additionalContext`.
- Fixtures that call `git` must use the hermetic env from `git-fixture-env.sh`; an inherited `GIT_DIR` from a worktree hook environment would otherwise point the fixture at the real repo (rc=97 tripwire).
