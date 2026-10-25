---
title: "fix: 33 test suites replace test-helpers' composed EXIT trap and leak the incident sandbox (#8659)"
type: fix
date: 2026-10-25
slug: fix-8659-exit-trap-sandbox
branch: feat-one-shot-8659-exit-trap-sandbox
issue: 8659
closes: 8659
lane: cross-domain
---

# fix: EXIT-trap replacement leaks the incident-telemetry sandbox on direct suite runs (#8659)

## Overview

`plugins/soleur/test/test-helpers.sh` mints an incident-telemetry sandbox (`mktemp -d -t
soleur-inc-XXXXXX`) when `INCIDENTS_REPO_ROOT` is unset, exports it, and composes its cleanup
with any EXIT trap already installed. Two defects, both measured in the issue:

- **(A) Replacement.** A suite that installs `trap … EXIT` AFTER `source test-helpers.sh`
  replaces the composed trap. `scripts/test-all.sh` exports its own `INCIDENTS_REPO_ROOT`, so
  CI never saw it; every DIRECT invocation of an offending suite leaks one `soleur-inc-*` dir.
  The follow-through probe (`scripts/followthroughs/test-helpers-sandbox-trap-8644.sh`)
  measured 33 suites at 3fe2fce615.
- **(B) Ordering.** The composed trap is `<prior>; _soleur_sb_cleanup` and runs under the
  caller's `set -e`: a failing prior command aborts the trap before cleanup runs
  (measured: `bash -c 'set -e; trap "false; echo SECOND-RAN" EXIT; exit 0'` exits 1, never
  prints `SECOND-RAN`).

The probe's awk matches a LITERAL `source …test-helpers.sh` line, so a suite sourcing through
a variable is not counted. Manual sweep found exactly one live offender:
`fixture-dir-operand-assert.test.sh` (`source "$HELPERS"`, then `trap 'rm -rf -- "$TMP_ROOT"'
EXIT INT TERM`). `git-fixture-containment.test.sh` also sources via `$HELPERS` but only inside
a generated CHILD script that installs no EXIT trap — no defect; the suite's own top-level
`trap 'cleanup' EXIT`/`trap 'cleanup; exit 130' INT TERM HUP` are installed where no sandbox
exists (the suite must not source the helpers; it controls the tripwire).

## Fix Shape

**`test-helpers.sh` (one line + comments).** Compose cleanup FIRST:
`trap "_soleur_sb_cleanup${_soleur_prior_body:+; $_soleur_prior_body}" EXIT`. Running
`_soleur_sb_cleanup` first makes it unconditional — its own `return 0` can never trip
errexit — and keeps the prior body verbatim in tail position, so the prior's own exit
semantics are preserved exactly (a failing prior still aborts the trap at the same point and
the exit status still reflects it). The composition stays re-composable and idempotent: a
second `source` re-wraps as `_soleur_sb_cleanup; _soleur_sb_cleanup[; prior]`, and
`_soleur_sb_cleanup` is a repeat-safe `rm -rf` on `_SOLEUR_SB_OWNED`.

**Per-suite disposition.** Preferred shape (issue §Proposed Fix 2, matching the
`vendor-bundle-coverage.test.sh` / `proc.test.sh` / `sync-pr-behind.test.sh` precedent):
install the suite's owning trap BEFORE the `source` line so the helper composes over it.
Two subtleties govern the moved body:

1. The trap can now fire DURING the source itself (the git-location tripwire in
   `lib/git-fixture-env.sh` exits 97; `test-all.sh` classifies 97 as `[TRIPWIRE]`). A body
   that dereferences a not-yet-assigned variable (`rm -rf "$WORK"`) aborts under `set -u`
   and masks the refusal as a generic rc 1. Every moved body gets an unset/empty guard:
   `[[ -z "${VAR:-}" ]] || rm -rf "$VAR"` (rc 0 when unset), or the `${arr[@]+"${arr[@]}"}`
   zero-word expansion for array owners (verified on this host: `rm -rf` with no operands
   exits 0; both guard forms verified to preserve the caller's exit status).
2. Suites whose trap lifecycle is intentionally mid-file (per-section fixture installed
   late, or `trap - EXIT` disarmament) keep their traps in place and call
   `_soleur_sb_cleanup` — guarded by `declare -F` because the function is only defined when
   the helpers minted the sandbox (inherited `INCIDENTS_REPO_ROOT` leaves it undefined —
   verified: a failing `declare -F … && fn` tail in an EXIT trap does NOT flip the exit
   status). Placed FIRST in the body so a failing `rm` cannot skip it — the same ordering
   rule as the fixed composition.

## Per-Suite Disposition

**Move trap before `source` (guarded body):** `_base-notice-frontmatter` (array →
`${_TMP_OWNED[@]+"${_TMP_OWNED[@]}"}`), `boundary-prefix` (PG_TMP, mid-file), `c4-from-components`,
`c4-model-freshness`, `check-deps-adapter-drift` (EXIT INT TERM HUP), `compaction-state-hook`
(EXIT INT TERM HUP), `domain-model-headless-append`, `domain-model-init`, `drain-prs` (VTMP,
mid-file in T7), `ext-filter-detect-hook` (SANDBOX, EXIT INT TERM HUP), `generate-kb-index`,
`gitleaks-merge-commit`, `go-session-gates`, `harvest-debt`,
`lint-bot-synthetic-completeness`, `lint-bot-synthetic-statuses`, `lint-distribution-content`,
`notice-frontmatter` (trap was mid-file at ~L450; moved up with `${RC_DIR:-}` guard, mid-file
line deleted), `pr-overlap-preflight` (TMP), `required-checks-canonical-parity` (trap was
inside Test 2; moved up), `resolve-debt`, `ship-pir-action-items-gate`,
`vendor-drift-classify` (trap was inside TS8; moved up), `worktree-manager-bare-sync`,
`worktree-manager-feature-spec-dir`, `worktree-manager-heal-stale-branch`,
`worktree-manager-hook-deps`, `worktree-manager-porcelain-sigpipe`,
`worktree-manager-safe-branch-sanitization`, `worktree-manager-sandbox-tmp-sweep`,
`worktree-manager-stale-lock-diag`.

**Move trap before `source`, verbatim body (owner already bound pre-source):**
`worktree-manager-install-bounded` — a post-measurement drift suite the issue's list of 33
predates; it self-exports `INCIDENTS_REPO_ROOT` inside `TEST_DIR`, so the helpers install no
trap at all and the probe flags it on syntax only. `TEST_DIR` is bound before the source
line, so the unguarded `rm -rf "$TEST_DIR"` body moves unchanged.

*Note:* the probe measured 71 sourcing consumers at fix time, not the issue's 33 — five
suites landed after the measurement (`boundary-prefix`, `drain-prs`,
`ext-filter-detect-hook`, `pr-overlap-preflight`, `worktree-manager-install-bounded`). All
are converted above.

**Move function + trap before `source` (body made unset-safe):**
`gdpr-gate-glob-liveness` (`cleanup`), `hosted-ship-shallow-merge-base` (`cleanup`),
`ship-battery-owed` (`FIXTURE_ROOTS=()` + `cleanup_fixture_roots` + trap moved as a block;
function already returns 0 explicitly).

**Move guarded compound trap before `source`:** `worktree-manager-atomic-config`,
`worktree-manager-bare-in-dotgit-layout` (`chmod -R u+w` stays `|| true`-protected inside the
guard so the post-`rm` semantics are unchanged).

**Keep mid-file traps; call `_soleur_sb_cleanup` first in each (the issue's alternative,
per `auto-close-scanner` / `roadmap-reconcile` precedent):** `vendor-pin-integrity` —
three sites: the TS3 trap, the `trap - EXIT` disarmament (becomes a cleanup-only trap so the
sandbox is still removed while `TMP_FILE` is intentionally not), and the TS9 trap.

**Variable-sourced (probe-blind), moved before `source "$HELPERS"` unchanged in shape:**
`fixture-dir-operand-assert` — the `TMP_ROOT=$(mktemp -d …)` / `readonly` / `trap … EXIT INT
TERM` block moves as a unit above the source line; the body needs no guard because the block
assigns before it arms, and the earlier `--write-baseline` exit path stays above the block.

## Files to Edit

- `plugins/soleur/test/test-helpers.sh` — composition ordering + both comment blocks (the
  marker comment's "33 suites replace" claim and the composition block's ordering note).
- `.claude/hooks/lib/test-incident-sandbox.sh` — the declared sibling copy of the
  composition block; same one-line ordering fix so the "one pattern across all sites"
  comment stays true (the file's own comment asserts parity).
- `plugins/soleur/scripts/alpha-metrics.test.sh`, `emit-decision.test.sh` — comment-only:
  they documented the old `(<prior>; _soleur_sb_cleanup)` order.
- The 39 suites above (33 issue-listed + 5 post-measurement drift + `fixture-dir-operand-assert`).

## Guard Contract

### Guard 1 — The composed EXIT trap removes the sandbox regardless of prior-trap outcome

**Property.** When `test-helpers.sh` mints `soleur-inc-*` (unset `INCIDENTS_REPO_ROOT`), the
installed EXIT trap runs `_soleur_sb_cleanup` even when the pre-existing trap body fails
under the caller's `set -e`; the prior body's own commands, ordering and failure semantics
are otherwise unchanged, and re-sourcing keeps the composition idempotent.

**Assembly.** Exactly one composition site exists — the `""` arm of the
`case "${INCIDENTS_REPO_ROOT:-}"` in `plugins/soleur/test/test-helpers.sh`:
`_SOLEUR_SB_OWNED` assignment, the `_soleur_sb_cleanup` definition (`[ -n … ] && rm -rf …;
return 0`), and the single `trap "…" EXIT` line that embeds `_soleur_prior_body`. There is no
second mint path (`/?*) :` and the non-absolute arm exit 1 mint nothing). Verified:
`grep -n '_soleur_sb_cleanup\|trap.*EXIT' plugins/soleur/test/test-helpers.sh`.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore `<prior>; _soleur_sb_cleanup` ordering | `bash -c 'set -e; trap "false" EXIT; source plugins/soleur/test/test-helpers.sh; exit 0'` leaves a `soleur-inc-*` dir in `$TMPDIR` (RED — cleanup skipped) |
| 2 | Drop `_soleur_sb_cleanup` from the composed trap | Any direct suite run with unset `INCIDENTS_REPO_ROOT` leaks; `ls -d ${TMPDIR:-/tmp}/soleur-inc-*` count grows (RED) |
| 3 | Make `_soleur_sb_cleanup` not `return 0` (e.g. trailing `false`) | `bash -c 'set -e; source plugins/soleur/test/test-helpers.sh; exit 0'` exits non-zero and/or fails to clean (RED) |
| 4 | Emit the composition with the prior wrapped in `{ set +e; …; }` | Prior-failure propagation is lost: `trap "false" EXIT` prior no longer yields rc 1 — the defect-B fix must NOT erase the prior's semantics (RED by behavior check) |

### Guard 2 — No test-helpers consumer installs an after-source EXIT trap without sandbox cleanup

**Property.** Every `plugins/soleur/test/*.test.sh` that sources `test-helpers.sh` — by a
literal `source …test-helpers.sh` line OR through a variable (`$HELPERS`) — either installs
its owning EXIT trap BEFORE the source line (helper composes over it) or calls
`_soleur_sb_cleanup` inside its own cleanup. A direct run (`INCIDENTS_REPO_ROOT` unset) of
any converted suite leaves zero `soleur-inc-*` dirs in `$TMPDIR`.

**Assembly.** `scripts/followthroughs/test-helpers-sandbox-trap-8644.sh` walks
`plugins/soleur/test/*.test.sh`, marks literal-sourcing suites (`src`), flags any after-source
`trap … EXIT`/`trap … 0` in a file lacking `_soleur_sb_cleanup` (`late && !ok`), and enforces
an anti-vacuity floor of ≥20 sourcing suites. The probe is blind to variable-sourced files by
construction; the manual sweep covers them (`grep -n 'HELPERS=' plugins/soleur/test/` →
`fixture-dir-operand-assert`, `git-fixture-containment` — the latter's `$HELPERS` source lives
in a generated child with no own EXIT trap, so it is clean).

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Move any converted suite's `trap … EXIT` line back below the `source` line and drop `_soleur_sb_cleanup`/the pre-source position | probe exits 1 naming the suite (RED) |
| 2 | In `vendor-pin-integrity.test.sh`, revert the TS9 trap to bare `trap 'rm -rf "$TMP_TS9"' EXIT` while the other two `_soleur_sb_cleanup` mentions remain | probe stays green (file-level `ok`) but a direct run leaks — caught by the TMPDIR-count acceptance check, documented blind spot (RED by leak test) |
| 3 | Add a NEW suite that sources `test-helpers.sh` and installs `trap 'rm -rf "$X"' EXIT` after it | probe exits 1 (RED) |
| 4 | Delete ≥15 suites' `source` lines so `sourcing < 20` | probe exits 3 CANNOT ESTABLISH — the anti-vacuity floor (RED) |

## Acceptance Criteria

- [ ] `bash scripts/followthroughs/test-helpers-sandbox-trap-8644.sh` exits 0.
- [ ] `bash -c 'set -e; trap "false" EXIT; source plugins/soleur/test/test-helpers.sh; exit 0'`
      exits non-zero (prior semantics preserved) and leaves no `soleur-inc-*` in `$TMPDIR`;
      `trap -p EXIT` after source shows `_soleur_sb_cleanup` ahead of the prior body.
- [ ] Direct run of ≥3 converted suites with `INCIDENTS_REPO_ROOT` unset: `$TMPDIR`
      `soleur-inc-*` count unchanged.
- [ ] All 33 converted suites + `fixture-dir-operand-assert` still pass green on this host.

## Out of Scope

- The `#7005` pipefail/`grep -q` sweep over the same directory (coordination note in the
  issue): this change touches only trap lines and their immediate comments.
- `git-fixture-containment.test.sh` — verified clean (see Overview).
- A re-source of `test-helpers.sh` mints a second sandbox and re-points `_SOLEUR_SB_OWNED`;
  the first sandbox is then unreachable by the trap (pre-existing, unchanged by this fix —
  no suite double-sources).
