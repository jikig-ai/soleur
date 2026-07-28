---
title: "perf(ci): stop the in-image verify scripts copying node_modules + .terraform into /build"
date: 2026-07-28
issue: 7007
branch: feat-one-shot-7007-in-image-verify-copy-exclusion
lane: cross-domain
type: chore
brand_survival_threshold: none
requires_cpo_signoff: false
plan_review: applied (code-simplicity-reviewer, kieran-rails-reviewer, scoped strong-model consult) — v2
---

# perf(ci): in-image verify scripts copy node_modules + infra/.terraform into /build

`Closes #7007`

> **Lane note.** This branch has no spec directory under `knowledge-base/project/specs/`, so there
> is no `spec.md` to carry `lane:` forward from — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

Two container-side verification helpers copy the entire `apps/web-platform` tree into the
container build dir and then immediately run `npm ci`, which rebuilds `node_modules` from
scratch:

| Script | Line | Current |
| --- | --- | --- |
| `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` | `:42` | `cp -r /src /build && cd /build` |
| `apps/web-platform/scripts/plugin-root-propagation-verify-in-image.sh` | `:39` | `cp -r /src /build && cd /build` |

Both line numbers and the exact shape were verified against the current files (Read, not
paraphrase). `/src` is a read-only bind mount of `$PWD/apps/web-platform`
(`-v "$PWD/$APP_DIR:/src:ro"` at `:37` and `:33` respectively), so the copy drags in
`node_modules` and the gitignored `infra/.terraform` provider cache.

**Measured in-session**, in the pinned image (`node:22-slim@sha256:4f77a690…`) against a warm
tree:

| | wall clock | `/build` size |
| --- | --- | --- |
| **before** — `cp -r /src /build` | **22.96 s** | **2.3 GB** (`node_modules` ~2 GB + `infra/.terraform` 247 MB) |
| **after** — shared exclusion copy (this plan) | **0.48 s** | **35 MB** |

~48× faster and ~2.27 GB less container-layer I/O per invocation, on any machine whose working
tree is warm. The waste is developer-local today — `ci.yml` states the constraint itself in the
canary job (*"No node/bun/npm-ci on the runner: the --verify runs inside a node:22-slim container
… The runner needs only docker (preinstalled) + git"*), so a fresh CI checkout has neither
directory at the time these run. That is why #7007 was filed as `deferred-scope-out` rather than
fixed inline in #7001.

**Corollary that shapes the whole verification design:** because the exclusions are no-ops on a
cold CI checkout, CI can never observe a silently-broken exclusion. The hermetic suite added by
this plan is the *only* thing that can. See §Verification ladder.

## Research Reconciliation — Spec vs. Codebase

The single most important finding: **the fix proposed in the issue body does not work.** It was
executed in-session and falsified.

| Issue-body / prompt claim | Reality (measured) | Plan response |
| --- | --- | --- |
| `( GLOBIGNORE="/src/node_modules:/src/infra/.terraform"; cp -r /src/* /build/; )` excludes both directories. | **Only the `node_modules` half works.** `GLOBIGNORE` filters the expansion of the `/src/*` glob; `/src/infra/.terraform` is never *in* that expansion (only `/src/infra` is), and `cp -r` then recurses into `/src/infra` on its own. Reproduced on a synthetic fixture: `node_modules` absent, `infra/.terraform` **PRESENT**. | Reject the proposed snippet. Use a mechanism that can express a *nested* exclusion — see §Mechanism. Also recorded as a User-Challenge in `specs/<branch>/decision-challenges.md`. |
| The `credential-persist-home-guard.test.sh` pattern is a working precedent for this fix. | It is a working precedent for a **top-level** exclusion only, and its own comment says so verbatim: *"The exclusion is TOP-LEVEL-ONLY by construction … a nested `sub/.terraform` cannot be expressed here at all (measured: a `GLOBIGNORE="$1/.terraform:$1/*/.terraform"` still copies the nested one)."* In that script `$1` **is** the `infra/` dir, so `.terraform` is top-level; here `/src` is `apps/web-platform` and `.terraform` sits one level down. | Cite the precedent for the *dotfile* property (which does transfer) and explicitly for why its *mechanism* does not. Corroborated by learning `2026-07-27-my-ab-could-not-resolve-the-effect-i-concluded-from-it.md` item 7. |
| `GLOBIGNORE` non-null implicitly enables dotfile matching, so dotfiles survive. | **True** — verified on the fixture (`.gitignore` present under the proposed snippet). The property is real; the mechanism it is attached to is not sufficient here. | The replacement mechanism must independently preserve dotfiles. `tar … .` does so by construction (it walks `.`, it does not glob). Asserted by the new suite. |
| `infra/.terraform` is ~162 MB. | **247 MB today** (`du -sh`, warm tree). `node_modules` is ~2 GB — the far larger half, and the one the issue treats as incidental. | Both are excluded. Volatile byte counts are quoted here only; the shipped script comment says "~2 GB" so it does not age into a lie. |
| (unstated) `infra/` is the only terraform root under the app. | `apps/web-platform/infra/sentry/` is a **second** terraform root (`main.tf`, `versions.tf`, `.terraform.lock.hcl` present; not yet initialised). The precedent's comment flags exactly this as a future silent regression. | The chosen exclusion covers **any** `.terraform` component at any depth, so `infra/sentry/.terraform` never becomes a second regression. Pinned by the suite. |
| (unstated) CI will exercise this change. | **It will not.** Neither gate's trigger regex includes the helper `.sh` itself: the canary gate fires on `package-lock.json\|server/agent-runner-sandbox-config.ts\|scripts/sandbox-canary.mjs\|infra/sandbox-canary-argv.json` (`ci.yml`, *Detect capture-input changes*), the propagation gate on `package-lock.json\|server/agent-env.ts\|server/agent-runner-sandbox-config.ts\|scripts/plugin-root-sandbox-propagation-probe.mjs` (*Detect propagation-input changes*). A PR touching only these helpers fires neither. | The plan does **not** rely on the paid gates. See §Verification ladder and the Alternative Considered on expanding the trigger sets. |
| (plan v1, self-inflicted) The worktree has neither `node_modules` nor `infra/.terraform`. | **False.** This worktree *does* carry `apps/web-platform/node_modules` (~2 GB); only `infra/.terraform` is absent. The A/B above was therefore measured against the repo's synced working copy, which has both. | Phase 0.3 corrected. A precondition step that states a false precondition is worse than none — `/work` would read it, find it already false, and improvise. |

## User-Brand Impact

**If this lands broken, the user experiences:** a red `sandbox-canary-capture-gate` /
`plugin-root-propagation-gate` on the *next* PR that touches an SDK/sandbox input — i.e. the
gate that proves `CLAUDE_PLUGIN_ROOT` reaches the sandboxed Bash, and the gate that proves the
deployed bwrap argv matches the committed fixture, would fail to run correctly. Worst realistic
case is a *truncated* `/build` producing a confusing `infra_error` / `canary_infra_error`
verdict rather than a wrong-but-green one; the fail-closed handling in `ci.yml` already reddens
on `does_not_propagate`.

**If this leaks, the user's data/workflow/money is exposed via:** nothing new. The change strictly
*narrows* what enters the container (it removes ~2.27 GB of host content, including the provider
cache, from the container layer). It touches no credential, no persisted store, no network egress.

**Brand-survival threshold:** `none` — CI-only tooling; no user-facing surface, no user data, no
production write path. No sensitive path is touched (the diff is two `scripts/*.sh`, one new
`scripts/lib/*.sh`, one new `scripts/lib/*.test.sh`), so no `threshold: none, reason:` scope-out
bullet is required.

## Mechanism

**v2 (post-review).** The copy does not live inline in either helper. It lives in **one shipped
file** that both helpers invoke, because `/src` is a mount of `apps/web-platform` and the helpers
themselves live inside it — so `/src/scripts/lib/…` is reachable from inside the container.

New file `apps/web-platform/scripts/lib/in-image-copy-src.sh`:

```bash
#!/usr/bin/env bash
# Copy the bind-mounted app tree into the container build dir, minus what the very
# next command discards (#7007).
#
# Called from BOTH in-image verifiers (sandbox-canary-verify-in-image.sh and
# plugin-root-propagation-verify-in-image.sh) as:
#     bash /src/scripts/lib/in-image-copy-src.sh /src /build
# It is a shipped file rather than an inline block in each helper for three reasons:
# the two call sites cannot drift apart; the test can execute the REAL artifact
# instead of a re-derived string; and the copy logic stops living inside a
# single-quoted `docker run ... bash -c` argument, where one apostrophe breaks the
# container invocation and no CI job would notice.
#
# /src is a ro bind of apps/web-platform, so on any warm working tree it carries
# node_modules (~2 GB) and the gitignored infra/.terraform provider cache (~250 MB).
# The caller runs `npm ci` immediately after, which rebuilds node_modules from
# scratch, and nothing in either probe reads .terraform. Measured in the pinned
# node:22-slim image against a warm tree: 22.96 s / 2.3 GB before, 0.48 s / 35 MB after.
#
# NOT GLOBIGNORE (the sibling pattern in infra/credential-persist-home-guard.test.sh):
# that filters glob EXPANSION, so it can only exclude a TOP-LEVEL entry. infra/.terraform
# is one level down, cp -r recurses into infra on its own, and the exclusion silently
# does nothing. Measured on a fixture, not assumed.
#
# Exclusion anchoring is decided by whether the pattern contains a slash, not by a
# remembered --anchored flag:
#   --exclude=./node_modules  has a slash -> matched against the whole member name,
#                             so a future test/fixtures/node_modules survives. This is
#                             only true because the archive is created with `.` as the
#                             member root (`./node_modules/...`); changing that `.` to
#                             `*` or to "$SRC" silently stops the exclusion matching and
#                             the copy reverts to full-fat with no red signal anywhere.
#   --exclude=.terraform      no slash -> matches that component at ANY depth, so it also
#                             covers infra/sentry/ (a second terraform root, not yet
#                             initialised) and never matches .terraform.lock.hcl.
#
# --no-same-owner is load-bearing, not defensive: GNU tar as root defaults to
# --same-owner and would restore the HOST uid/gid off the ro bind mount, so /build
# would stop being root-owned the way cp -r left it. Ownership parity only: tar also
# restores exact modes and mtimes where cp -r applied the umask and stamped fresh
# ones. That delta is accepted (it is strictly more faithful to the source).
#
# pipefail is set HERE rather than in the callers precisely so it has no blast radius
# on the canary caller's `curl -fsSL https://bun.sh/install | bash` pipeline. It is
# load-bearing: with `set -e` alone, a failing PRODUCER tar leaves the consumer to
# extract a truncated stream and exit 0, and npm ci then runs against a partial tree.
set -euo pipefail

SRC="${1:?usage: in-image-copy-src.sh SRC DEST}"
DEST="${2:?usage: in-image-copy-src.sh SRC DEST}"

mkdir -p "$DEST"
if ! tar -C "$SRC" --exclude=./node_modules --exclude=.terraform -cf - . \
     | tar -C "$DEST" --no-same-owner -xf -; then
  echo "FATAL: in-image copy failed ($SRC -> $DEST) - refusing to verify a truncated tree" >&2
  exit 1
fi
```

The `if !` form is deliberate and is the *only* shape in which the FATAL is reachable: `pipefail`
makes the pipeline status non-zero when **either** tar fails, and the `if` condition context
suspends errexit long enough for the diagnostic to print. (Plan v1 used a bare pipeline plus a
`PIPESTATUS` check; two reviewers independently measured that under `set -e` without `pipefail`
the shell dies **at the pipeline**, before the capture — so the FATAL branch was dead code for
every failure mode the plan claimed it covered. That defect is why this section was rewritten.)

Each helper's inline change is then two lines, replacing `cp -r /src /build && cd /build`:

```bash
    bash /src/scripts/lib/in-image-copy-src.sh /src /build
    cd /build
```

Constraints this shape respects, each verified rather than assumed:

- **`tar` exists in the pinned image.** `docker run --rm node:22-slim@sha256:4f77a690… tar --version`
  → `tar (GNU tar) 1.34` (host is 1.35; both produced identical results on the same fixture). `tar`
  is Essential on Debian.
- **`/src` is readable, not executable-required.** The helper is invoked as `bash <path>`, so no
  exec bit is needed and the read-only mount is sufficient.
- **The two call-site lines contain no `'`.** The inner script is a single-quoted argument to
  `docker run … bash -c '…'`; an apostrophe would terminate it. With the copy logic moved out of
  that string, the remaining exposure is two short literal lines, and `bash -n` on each helper
  (suite assertion 7) catches any future unbalanced quote there.
- **In-image ownership verified.** `stat -c "%U %n"` on `/build/package.json`, `/build/.gitignore`,
  `/build/scripts` after the tar copy → all `root`, matching `cp -r`.

### Alternatives considered

| Alternative | Verdict | Why |
| --- | --- | --- |
| The issue's `GLOBIGNORE` one-liner | **Rejected** | Empirically cannot exclude `infra/.terraform` (247 MB — the *only* half the issue names as the motivation). §Research Reconciliation row 1. |
| Two-stage `GLOBIGNORE` (`/src/*` excluding `infra`, then `/src/infra/*` excluding `.terraform`) | **Rejected** | Works for `infra/.terraform`, but is per-level by construction: it would silently miss `infra/sentry/.terraform` the day anyone initialises that root, needing a third stage. Also re-imports the documented colon/glob-metacharacter fragility of `GLOBIGNORE`. |
| Inline the tar block in both helpers (plan v1) | **Rejected at review** | Duplicates ~25 lines of rationale into two single-quoted `bash -c` strings, then needs a byte-identity drift pin, a marker-extraction test harness, a `sed` path substitution, an `eval`, and an apostrophe ban to hold it together. The shared file makes site-drift unexpressible and lets the test run the real artifact. |
| `cp -r` then `rm -rf /build/node_modules /build/infra/.terraform` | **Rejected** | Trivially reviewable, but it pays the 22.96 s / 2.3 GB copy first and then pays again to delete it. The I/O *is* the defect. |
| `rsync -a --exclude=…` | **Rejected** | Not present in `node:22-slim`; would add an `apt-get install rsync` to a path whose whole point is to be fast. |
| Mask the sources at the docker layer (`--tmpfs /src/node_modules`) | **Rejected** | Requires the mountpoint to pre-exist inside a read-only bind. On a fresh CI checkout `node_modules` does not exist, so docker would fail to create it and the gate would break in exactly the environment it must work in. |
| Copy an allow-list of only what the probes read | **Rejected** | Smaller still, but changes what the container filesystem looks like, and the canary's premise is that the captured bwrap argv is a function of the host filesystem. Not worth the blast radius for a p3 chore. |
| `set -o pipefail` in the *callers* instead of the copy script | **Rejected** | Would also change the semantics of the canary's `curl -fsSL https://bun.sh/install \| bash` on line 44. Setting it inside the copy script gets the identical guarantee with zero blast radius. |
| Add the two helper `.sh` files to the gates' trigger regexes so this PR self-exercises | **Rejected — recorded, not silent** | Each future edit to these helpers would burn two paid Haiku turns to re-prove a line already pinned by a hermetic suite and an unpaid in-image rehearsal — and the paid gates validate the *paid turn*, not the copy logic. What the regex would incidentally have covered is the paste/quoting seam, which the shared-file design eliminates structurally. Residual risk is retired by AC6/AC7 (real copy + real `npm ci`, real image, real tree). |

## Verification ladder

Both scripts exit early without `ANTHROPIC_API_KEY` and drive a real, **paid** Haiku turn when it
is present, so the paid end-to-end path will not be run. Three rungs, none of them paid:

- **L1 — hermetic suite (the only guard that can ever fire).** New
  `apps/web-platform/scripts/lib/in-image-copy-src.test.sh`: pure bash + GNU tar, synthesized
  fixture, no docker, no network, no key. It invokes the **real shipped** `in-image-copy-src.sh`
  with fixture paths. Auto-registered by the `apps/web-platform/scripts/lib/*.test.sh` glob in
  `scripts/test-all.sh` (`want_scripts` shard), which CI runs as `bash scripts/test-all.sh scripts`
  — a required `test` context. No orphan-suite risk, no exec bit needed (`run_suite "$f" bash "$f"`).
  Because the exclusions are no-ops on a cold CI checkout, this suite — not the paid gates — is
  what makes a broken exclusion detectable at all.
- **L2 — in-image rehearsal against a warm tree (in-session, recorded in the PR body).** Run the
  shipped copy script inside the pinned `node:22-slim` digest with a warm `/src`, then assert
  (a) `diff -rq --exclude=node_modules --exclude=.terraform /src /build` is clean, (b)
  `npm ci --no-audit --no-fund` succeeds in `/build`, (c) the A/B wall clock. Already run for the
  v1 block: (a) clean, (c) 22.96 s → 0.48 s, plus `tar --version` and the root-ownership check.
  Must be **re-run against the post-edit shipped script**; (b) has never been run and is AC7.
- **L3 — paid end-to-end.** `bash apps/web-platform/scripts/{sandbox-canary,plugin-root-propagation}-verify-in-image.sh`
  with `ANTHROPIC_API_KEY` exported. **NOT RUN.** The PR body must say so in those words rather than
  implying coverage it does not have. See §PR body requirements.

## Files to Edit

- `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` — replace the
  `cp -r /src /build && cd /build` line with the two-line call. Add one sentence to the header
  comment noting `/build` is a filtered copy of `/src` (see the shared script for what is dropped).
- `apps/web-platform/scripts/plugin-root-propagation-verify-in-image.sh` — same two-line call, same
  header sentence. Both header sentences must be added; a one-sided edit is drift.

## Files to Create

- `apps/web-platform/scripts/lib/in-image-copy-src.sh` — the shared copy.
- `apps/web-platform/scripts/lib/in-image-copy-src.test.sh` — the L1 suite.

No other file changes. Specifically **not** edited: `.github/workflows/ci.yml` (trigger sets — see
the last Alternative), `scripts/test-all.sh` (both new files' directory is already globbed), and
`apps/web-platform/infra/credential-persist-home-guard.test.sh` (cited as precedent; its
`GLOBIGNORE` remains correct *for its own top-level case* and must not be "harmonised" with this).

## Implementation Phases

### Phase 0 — preconditions (re-verify; do not inherit)

0.1 Re-read both helpers and confirm the `cp -r /src /build && cd /build` line is still present.
    If it has moved from `:42` / `:39`, anchor on the content, not the number
    (`cq-cite-content-anchor-not-line-number`).
0.2 `docker info >/dev/null` — the L2 rehearsal needs a daemon. If absent, AC6/AC7 cannot run; say
    so explicitly in the PR body rather than skipping silently.
0.3 Pick a warm `/src` for the L2 rehearsal. **This worktree has `node_modules` (~2 GB) but not
    `infra/.terraform`**; the repo's synced working copy at
    `/home/jean/git-repositories/jikig-ai/soleur/apps/web-platform` has both. Mount that path for
    the rehearsal — a **measurement** against a warm tree, not a source read; the edited files are
    read and written in the worktree.
0.4 Confirm `apps/web-platform/scripts/lib/` exists and that `scripts/test-all.sh` still globs
    `apps/web-platform/scripts/lib/*.test.sh` in the `want_scripts` block.

### Phase 1 — RED

Write `apps/web-platform/scripts/lib/in-image-copy-src.test.sh`, and create
`in-image-copy-src.sh` with a deliberately naive body (`mkdir -p "$DEST"; cp -r "$SRC"/. "$DEST"/`).
Run the suite: it must go **RED on assertion 3** (`node_modules` present in the destination). This
is the real RED — a suite that only fails because a file or a comment marker is missing proves it
detects absence, not a wrong implementation (`cq-write-failing-tests-before`).

Suite shape (mirror `apps/web-platform/scripts/sdk-bump-sandbox-gate.test.sh`, the closest
sibling): `set -eu`, `SCRIPT_DIR` resolution, `T="$(mktemp -d)"` with `trap 'rm -rf "$T"' EXIT`
(an owning trap is required — `scripts/lint-trap-tempfile-ownership.py` rule (c) gates new
`mktemp` callers), `pass`/`fail` counters where `fail()` returns 0 so `set -e` cannot abort the
harness before the summary, and a single `[[ "$FAIL" -eq 0 ]] || exit 1` chokepoint. All fixtures
synthesized inline (`cq-test-fixtures-synthesized-only`).

Fixture tree:

```
src/.gitignore  src/.env.example  src/.nvmrc  src/.dockerignore
src/.service-role-allowlist  src/.dependency-cruiser.cjs
src/package.json  src/package-lock.json
src/scripts/sandbox-canary.mjs
src/infra/main.tf  src/infra/.terraform.lock.hcl
src/infra/.terraform/providers/big.bin          <- must be excluded
src/infra/sentry/.terraform.lock.hcl
src/infra/sentry/.terraform/x/y.bin             <- must be excluded (nested-root tripwire)
src/node_modules/pkg/index.js                   <- must be excluded
src/test/fixtures/node_modules/keepme.txt       <- must SURVIVE (anchoring pin)
```

Assertions (7 — deliberately trimmed from v1's 8 after the simplicity review cut the byte-identity
drift pin, the path enumeration subsumed by the whole-tree diff, the marker-count check, and the
`sed`-substitution meta-check, all of which the shared-file design makes moot):

1. **Positive control (anti-vacuity).** The fixture itself contains `node_modules`,
   `infra/.terraform`, `infra/sentry/.terraform` and every dotfile above. Without this the suite
   passes trivially the day the fixture builder breaks — the vacuity class #7001 spent a session on.
2. **Run the real artifact.** `bash "$SCRIPT_DIR/in-image-copy-src.sh" "$SRC" "$DST"` exits 0. No
   extraction, no substitution, no `eval` — the test executes the shipped file.
3. Destination lacks `node_modules`, `infra/.terraform`, `infra/sentry/.terraform`. Asserted on
   *absence against a fixture that has them*, not merely on diff parity — a broken anchor
   (e.g. `.` changed to `*` in the archive root) is a silent perf regression with no other signal.
4. **Whole-tree parity.** `diff -rq --exclude=node_modules --exclude=.terraform "$SRC" "$DST"`
   exits 0, **plus** one explicit check for `test/fixtures/node_modules/keepme.txt` — `diff
   --exclude` matches basename at any depth and would otherwise mask exactly the anchoring
   property assertion 3's `node_modules` line depends on.
5. **Producer-failure control (the reachable-guard test).** `bash in-image-copy-src.sh
   "$T/does-not-exist" "$DST3"` exits non-zero **and** its stderr contains `FATAL:`. This is the
   branch plan v1 shipped as dead code; without this assertion the fix for it is unpinned.
6. **Both call sites migrated.** Neither helper still matches `cp -r /src /build`, and both match
   `in-image-copy-src.sh`. Grepped against the two explicit helper paths (not a directory
   pathspec).
7. **`bash -n`** on both helpers and on `in-image-copy-src.sh`. An unbalanced quote introduced into
   either helper's single-quoted `docker run … bash -c '…'` body breaks the *outer* script's
   parse, so this one builtin covers the whole apostrophe class that v1 needed a bespoke character
   ban for.

### Phase 2 — GREEN

Replace the naive body of `in-image-copy-src.sh` with the §Mechanism body; replace the copy line in
both helpers with the two-line call and add the header sentence to each. Re-run the suite: all
seven assertions pass.

### Phase 3 — L2 rehearsal

Run the shipped copy script inside the pinned image against the warm tree; capture the parity diff,
the `npm ci` result, and the A/B wall clock for the PR body (AC6, AC7, AC8).

### Phase 4 — exit gate

`bash scripts/test-all.sh scripts` (the gate's own invocation — not a hand-picked file list; a
hand-enumerated subset is the #7003 defect class), plus
`python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`, plus whatever form
`scripts/lint-trap-tempfile-ownership.test.sh` uses for its own live run.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** Both helpers migrated, checked by explicit path (a directory pathspec would also match
  the new suite, which legitimately mentions both strings). Run **after** `git add` — `git grep`
  is tracked-only:

  ```bash
  H1=apps/web-platform/scripts/sandbox-canary-verify-in-image.sh
  H2=apps/web-platform/scripts/plugin-root-propagation-verify-in-image.sh
  ! git grep -q -e 'cp -r /src /build' -- "$H1" "$H2"
  [ "$(git grep -l -e 'in-image-copy-src.sh' -- "$H1" "$H2" | wc -l)" -eq 2 ]
  ```

  (`git grep -c` with no match exits 1 and prints nothing, which would abort a `set -e` harness;
  `-q` + `!` is the checkable form. `-e` is used so a future pattern edit starting with `-` cannot
  silently become a flag.)
- **AC2** `bash apps/web-platform/scripts/lib/in-image-copy-src.test.sh` exits 0 and its summary
  reports zero FAIL.
- **AC3** The suite is genuinely falsifiable: the Phase 1 RED transcript (naive `cp -r` body →
  assertion 3 FAIL) and the Phase 2 GREEN transcript are both recorded in the PR body.
- **AC4** `bash scripts/test-all.sh scripts` is green — the gate's own invocation, run over the
  whole shard rather than the new files alone.
- **AC5** `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` is green over
  every changed file (the gate's own `--changed` form, not an enumerated path list).
- **AC6** In-image parity, post-edit, warm tree, pinned digest — spelled out, not sketched:

  ```bash
  docker run --rm -v "<warm-app-dir>:/src:ro" \
    node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d \
    bash -c 'bash /src/scripts/lib/in-image-copy-src.sh /src /build
             diff -rq --exclude=node_modules --exclude=.terraform /src /build
             test ! -e /build/node_modules
             test ! -e /build/infra/.terraform'
  ```

  exits 0.
- **AC7** In the same container and same invocation, `cd /build && npm ci --no-audit --no-fund`
  exits 0 — the actual next command in both helpers, proven against the filtered tree. This is the
  highest-fidelity check in the plan and the only one that exercises the *gate* rather than the
  *filter*; it has never been run and must not be skipped.
- **AC8** The PR body records the measured A/B (before/after wall clock and `/build` size) from the
  pinned image, and states in those words that the **paid** end-to-end path (`ANTHROPIC_API_KEY` +
  a real Haiku turn) was **not run**.

### Post-merge (operator)

None. Every step above is automatable from this session (docker + bash + python3 are all present;
no vendor console, no credential mint, no infrastructure apply).

## Risks & Mitigations

| # | Risk | Likelihood | Mitigation |
| --- | --- | --- | --- |
| R1 | The suite passes vacuously because the fixture stopped containing the excluded dirs. | Medium (the #7001 class) | Assertion 1 is a positive control on the fixture itself; assertion 3 asserts absence against a fixture proven to contain them. |
| R2 | The fix is applied to one helper and not the other. | **Eliminated** | There is one copy implementation. A one-sided migration is caught by assertion 6; a divergent *implementation* is now unexpressible. |
| R3 | The archive root `.` is later changed to `*` or `"$SRC"`, silently un-anchoring `--exclude=./node_modules`; the copy still succeeds, just full-fat. | Low, silent | Assertion 3 fails (a `node_modules` reappears in the destination). Called out explicitly in the script comment because there is no other signal — CI's cold checkout cannot see it. |
| R4 | An apostrophe is introduced into a helper's single-quoted `bash -c` body, breaking the container invocation. Neither paid gate fires on these files, so CI would be silent. | Low, unbounded cost | The copy logic no longer lives in that string (two short literal lines remain), and assertion 7 (`bash -n`) fails on any unbalanced quote in the outer parse. |
| R5 | Producer `tar` fails, the consumer extracts a truncated stream and exits 0, `npm ci` runs against a partial tree and the verdict is wrong rather than absent. | Low | `set -o pipefail` **inside the copy script** (zero blast radius on the callers) plus the `if !` form, which is the only shape where the FATAL diagnostic is reachable. Pinned by assertion 5. Plan v1's `PIPESTATUS` guard was measured to be dead code here — recorded so the shape is not "simplified" back. |
| R6 | `--exclude=.terraform` accidentally drops `.terraform.lock.hcl`. | Low | Falsified in-session on the fixture and in-image against the real tree: both lock files survive (a no-wildcard pattern matches a whole component, not a prefix). Covered by assertion 4. |
| R7 | `--exclude=./node_modules` unexpectedly drops a nested directory named `node_modules`. | Low | Falsified: `test/fixtures/node_modules/keepme.txt` survives. No nested `node_modules` component exists today (`git ls-files … \| grep -c '/node_modules/'` → 0), so this is future-proofing, pinned by assertion 4's explicit line. |
| R8 | `tar -x` as root re-owns `/build` to the host uid off the ro bind mount, changing what `npm ci` sees. | Low | `--no-same-owner`; verified in-image that `/build/package.json`, `/build/.gitignore`, `/build/scripts` are root-owned, matching `cp -r`. **Ownership parity only** — tar also restores exact modes and mtimes where `cp -r` applied the umask and stamped fresh ones. Accepted: strictly more faithful to the source, and AC7 proves `npm ci` is indifferent. |
| R9 | Changing the container filesystem shape perturbs the captured bwrap argv and byte-diff-fails the committed fixture. | Low | The committed `infra/sandbox-canary-argv.json` uses `${CANARY_WS}`/`${CANARY_EMPTY}` placeholders and does not enumerate project subpaths; `node_modules` is rebuilt deterministically by `npm ci` either way, and `.terraform` is absent in CI today, so CI's argv already reflects a tree without it. The mode/mtime delta in R8 is part of this surface. Residual: not provable without the paid turn — stated as such in the PR body. |
| R10 | `tar` absent or behaviourally different in a future base-image bump. | Low | `tar` is Essential on Debian; the image pin is a digest, and both helper headers already say "keep in sync on a base bump". AC6/AC7 re-run against the pinned digest at edit time. |

## Observability

```yaml
liveness_signal:
  what: apps/web-platform/scripts/lib/in-image-copy-src.test.sh reporting 0 FAIL
  cadence: every PR and every merge to main
  alert_target: the required `test` status context (CI scripts shard)
  configured_in: scripts/test-all.sh (apps/web-platform/scripts/lib/*.test.sh glob, want_scripts shard); .github/workflows/ci.yml `bash scripts/test-all.sh scripts`
error_reporting:
  destination: CI job log + red required check. In-container, the copy prints
    "FATAL: in-image copy failed (SRC -> DEST)" to stderr and exits 1, which the caller
    propagates (set -e) into the canary/propagation gate job log.
  fail_loud: true (pipefail + `if !` guard; the diagnostic is reachable for BOTH tar sides,
    which the plan-v1 PIPESTATUS form was measured NOT to be)
failure_modes:
  - mode: producer or consumer tar fails, /build truncated
    detection: FATAL line on container stderr + non-zero exit; pinned by suite assertion 5
    alert_route: the invoking CI gate job reddens (sdk-bump-sandbox-gate.sh / the ci.yml verdict case)
  - mode: exclusion silently stops applying (anchor broken, regression to a full copy)
    detection: suite assertion 3 (destination lacks node_modules/.terraform) against the
      positive-controlled fixture. NOTE this is the only detector -- a cold CI checkout has
      neither directory, so no CI job can observe the regression.
    alert_route: red `test` context
  - mode: dotfiles or lock files silently dropped
    detection: suite assertion 4 (whole-tree diff -rq plus the explicit keepme.txt line)
    alert_route: red `test` context
  - mode: one helper migrated and the other not
    detection: suite assertion 6 (both helpers grep-checked by explicit path)
    alert_route: red `test` context
  - mode: unbalanced quote in a helper's docker bash -c body
    detection: suite assertion 7 (bash -n on both helpers)
    alert_route: red `test` context
logs:
  where: GitHub Actions job logs for the `test` (scripts shard) job and, when the paid gates fire,
    the sandbox-canary-capture-gate / plugin-root-propagation-gate jobs
  retention: GitHub Actions default (90 days)
discoverability_test:
  command: bash apps/web-platform/scripts/lib/in-image-copy-src.test.sh
  expected_output: a PASS/FAIL summary ending with 0 FAIL and exit 0
```

The detection path needs no remote shell access. This is not a blind execution surface (the suite
runs on the runner, not inside the sandbox), so §2.9.2 adds no requirements. No soak-gated or
time-gated close criterion, so §2.9.1 (follow-through enrollment) does not fire.

## Architecture Decision (ADR/C4)

**Not applicable.** No ownership/tenancy boundary moves, no new substrate or integration, no
resolver/dispatch/trust boundary changes, and no existing ADR is extended or reversed — ADR-079
(capture-env == replay-env == deploy-image) is *preserved* by this change, not amended: the copy
still produces the same `/build` contents modulo two directories that are respectively rebuilt
(`node_modules`) and never read (`.terraform`).

**C4 completeness check.** All three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`
are unaffected: this change adds no external human actor (no new correspondent, reviewer, or
recipient), no external system or vendor (no new webhook, outbound API, or third-party store —
the image, the SDK, and the Anthropic API edge are all pre-existing and unchanged), no container
or data store, and no actor↔surface access relationship. The only mutated artifact is the byte
content of a container-local scratch directory that no C4 element models.

## Infrastructure (IaC), Encryption Posture, GDPR

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

- **IaC (§2.8):** skipped — no server, service, cron, vendor account, DNS record, cert, secret,
  firewall rule, or persistent runtime process is introduced. No remote-shell step, no
  secret-manager write, and no vendor-console step appears anywhere in this plan.
- **Encryption posture (§2.11):** skipped — no persistent data store and no new cross-component
  or network connection. The diff is three shell scripts and one shell test.
- **GDPR (§2.7):** skipped — no schema, migration, auth flow, API route, or `.sql` file; no
  LLM/external-API processing of operator data is added (the paid turn already exists and is
  unchanged); no new artifact-distribution surface.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering

**Status:** reviewed
**Assessment:** Contained CI-tooling perf fix with a measured ~48× win and no runtime/product blast
radius. The load-bearing engineering judgements are (a) rejecting the issue's own proposed
mechanism on empirical grounds, (b) choosing an exclusion that survives the second terraform root,
(c) shipping the copy as one artifact both helpers call rather than two pasted blocks, and (d)
designing an unpaid verification ladder for a path whose real gate is paid and does not even fire
on this file. All four are recorded above with the measurement that justifies them.

Product/UX gate: not triggered — no path in `## Files to Edit` or `## Files to Create` matches any
UI-surface term or glob (`scripts/*.sh`, `scripts/lib/*.sh`, `scripts/lib/*.test.sh`); no
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Tier: NONE.

### Plan review (applied)

**Agents invoked:** code-simplicity-reviewer, kieran-rails-reviewer, scoped strong-model consult.
**Decision:** reviewed — all mechanical findings auto-applied into this v2.

Findings applied:

- **P0 (all three, independently measured):** the v1 `PIPESTATUS` guard was dead code under
  `set -e` without `pipefail` — the shell dies at the pipeline before the capture. Rewritten as
  `set -o pipefail` inside a dedicated script plus an `if !` guard, and pinned by suite assertion 5.
- **P0 (kieran):** v1's AC1 used a directory pathspec that the plan's own new test file would
  match, so it would fail the moment the suite was staged; `git grep -c` also exits 1 on no-match
  and would abort a `set -e` harness. Rewritten with explicit paths and `! git grep -q -e`.
- **P1 (advisor + simplicity, converged):** replace the two inline blocks with one shipped
  `scripts/lib/in-image-copy-src.sh` that both helpers call. Collapses ~60% of the net-new lines,
  eliminates marker extraction / `sed` substitution / `eval` / the byte-identity pin / the
  apostrophe ban, removes a `mkdir -p /build`-on-the-runner-root hazard, and lets the suite execute
  the real artifact instead of a re-derived string.
- **P1 (simplicity):** v1's Phase 1 RED failed on a missing comment marker, not a wrong
  implementation. Rewritten to RED against a naive `cp -r` body failing assertion 3.
- **P1 (advisor):** the mutation control must exercise the *producer-tar-failure* case — the only
  reachable branch of the guard — not a generic dotfile mutation. Now assertion 5.
- **P2 (kieran):** Phase 0.3 stated a false precondition (the worktree *does* have `node_modules`);
  the ~2 GB figure appeared as 1.8 / 2.0 / 2.2 GB in three places; `--no-same-owner` gives
  ownership parity but not mode/mtime parity; AC7's `bash -c '<block>; diff'` was not runnable as
  written; the header-comment sentence was prescribed for only one helper. All corrected.
- **P2 (kieran):** cite `ci.yml`'s own "the runner needs only docker + git" comment instead of
  asserting the cold-checkout claim bare. Applied in §Overview.
- **Cuts accepted (simplicity):** byte-identity drift pin + its AC, the path-enumeration assertion
  subsumed by the whole-tree diff, the marker-count assertion, the substitution meta-check, and the
  `ci.yml`-unchanged AC. Assertion count 8 → 7; AC count 10 → 8.

## Open Code-Review Overlap

**None.** Queried all 61 open `code-review` issues (`gh issue list --label code-review --state open
--json number,title,body --limit 200`) and searched each body for
`apps/web-platform/scripts/sandbox-canary-verify-in-image.sh`,
`apps/web-platform/scripts/plugin-root-propagation-verify-in-image.sh`, and `scripts/test-all.sh`.
Zero matches on any of the three.

## PR body requirements

- `Closes #7007` in the body (not the title).
- The measured A/B table from the pinned image.
- A verbatim statement that the paid end-to-end path was **not** exercised: both scripts require
  `ANTHROPIC_API_KEY` and drive a real Haiku turn, and neither CI gate's trigger regex matches
  the changed files, so no paid run occurred in-session or in CI on this PR. What *was* run: the
  hermetic suite (RED→GREEN transcripts), the whole `scripts` shard, and an in-image rehearsal
  against a warm tree proving whole-tree parity and a successful `npm ci` in the filtered `/build`.
- The `decision-challenges.md` entry (the issue's own proposed fix was falsified) — `/ship` folds
  this in and files the `action-required` issue.
- No operator checklist and no operator-action headings — there are none to record, and those
  tokens themselves trip `ship-operator-step-gate.sh`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled above.
- **`GLOBIGNORE` cannot express a nested exclusion — and the precedent that "already ships" says so
  in its own comment.** The issue body, written by an agent reading `credential-persist-home-guard.test.sh`,
  lifted the pattern one directory level up and inverted its correctness. The tell was free: the
  precedent's comment block literally contains *"The exclusion is TOP-LEVEL-ONLY by construction"*
  and *"measured: a `GLOBIGNORE="$1/.terraform:$1/*/.terraform"` still copies the nested one"*.
  Generalisation: when a plan cites a working precedent, the precedent's own stated *scope
  conditions* are part of the citation — read its comments, not just the line you want to copy.
- **`set -e` does not fire before your error handler when the failure is a pipeline.** A guard
  written as `A | B; rc=("${PIPESTATUS[@]}"); [[ … ]] || { echo FATAL; exit 1; }` is dead code under
  `set -e` without `pipefail`: errexit kills the shell *at the pipeline*, so the capture never runs
  and the diagnostic never prints. It fails closed, so nothing goes wrong — it just goes wrong
  silently, which is worse when the whole Observability section is built on that string. Use
  `set -o pipefail` in a scope you own plus `if ! A | B; then …`, and add a test that makes the
  producer fail so the reachable branch is actually exercised.
- **A test that `eval`s a marker-extracted, path-substituted copy of shipped code tests a
  re-derivation, not the artifact.** If the shipped code can be moved into a file the test can
  invoke directly, do that instead — it removes the extraction harness, the substitution, the
  fidelity gap, and (here) an `eval` that would have run `mkdir -p /build` on the CI runner's root
  had the substitution silently failed.
- **A trigger regex that does not name the file you are changing means CI will not exercise your
  change, however green it looks** — and when the optimisation is a no-op in CI's environment
  (a cold checkout has no `node_modules` and no `.terraform`), CI is *structurally* incapable of
  detecting a regression in it. Before writing "CI covers this", grep the trigger set for the
  changed path, then ask whether CI's environment can even express the failure.
- **`tar` exclusion anchoring is decided by whether the pattern contains a slash**, not by an
  `--anchored` flag you remember passing — and `--exclude=./node_modules` is anchored only because
  the archive is created with `.` as its member root. Both facts are one edit away from silently
  reverting the optimisation with no error anywhere, so both live in the script comment and are
  pinned by an absence assertion against a fixture that actually contains the excluded directory.
