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
deepened: 2026-07-28 (learnings-researcher, claim-verification pass, test-design-reviewer, architecture-strategist) — v3
---

# perf(ci): in-image verify scripts copy node_modules + infra/.terraform into /build

`Closes #7007`

> **Lane note.** This branch has no spec directory under `knowledge-base/project/specs/`, so there
> is no `spec.md` to carry `lane:` forward from — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-07-28 · **Rounds:** plan-review (3 agents) → deepen (4 agents) · **Version:** v3

### Key improvements over v1

1. **The fix specified in the issue was falsified and replaced.** `GLOBIGNORE` cannot express a
   nested exclusion, so the issue's own snippet leaves `infra/.terraform` (247 MB) in place.
2. **The error guard was dead code and is now live.** v1's `PIPESTATUS` form never ran under
   `set -e`; v2 moved the copy into its own script with `set -o pipefail` + an `if !` guard.
3. **The copy became one shipped artifact instead of two pasted blocks**, deleting the
   marker-extraction / `sed` / `eval` test harness, the byte-identity pin, and the apostrophe trap.
4. **The producer-failure control now discriminates.** Measured: a missing `$SRC` fails *both* tars
   and passes with or without `pipefail`; an *unreadable member* gives `PIPESTATUS=(2 0)` → exit 2
   with `pipefail`, exit **0** without. Only the second stimulus can fail when the fix is removed.
5. **The canary gate's diagnostic hole was found and closed.** `sdk-bump-sandbox-gate.sh` captures
   the verify command as `"$(bash -c "$VERIFY_CMD" 2>/dev/null | tail -1 || true)"` — a copy FATAL
   was invisible. One redirect deleted; the residual ack-fallback degradation is documented and
   filed rather than silently claimed as fail-loud.

### New considerations discovered

- The stated tar-anchoring rule in v2's comment was **empirically false** (measured below).
- `sdk-bump-sandbox-gate.sh` carries a *second, internal* trigger regex, so the rejected
  "add the helpers to `ci.yml`'s regex" alternative would have cost **one** paid turn, not two —
  and its canary half would have been structurally inert.
- `apps/web-platform/scripts/lib/` has a **source-don't-execute** convention this file must
  deliberately diverge from, and say so.

## Overview

Two container-side verification helpers copy the entire `apps/web-platform` tree into the
container build dir and then immediately run `npm ci`, which rebuilds `node_modules` from
scratch:

| Script | Line | Current |
| --- | --- | --- |
| `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` | `:42` | `cp -r /src /build && cd /build` |
| `apps/web-platform/scripts/plugin-root-propagation-verify-in-image.sh` | `:39` | `cp -r /src /build && cd /build` |

Both lines and the `-v "$PWD/$APP_DIR:/src:ro"` mounts (`:37` / `:33`) were re-verified against the
current files in the deepen pass. `/src` is a read-only bind mount of `$PWD/apps/web-platform`, so
the copy drags in `node_modules` and the gitignored `infra/.terraform` provider cache.

**Measured in-session**, in the pinned image (`node:22-slim@sha256:4f77a690…`) against a warm tree:

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
cold CI checkout, CI can never observe a silently-broken exclusion by running the real path. The
hermetic suite added by this plan is the *only* thing that can.

## Research Reconciliation — Spec vs. Codebase

Every row was executed or grepped, not reasoned about.

| Claim | Reality (measured) | Plan response |
| --- | --- | --- |
| `( GLOBIGNORE="/src/node_modules:/src/infra/.terraform"; cp -r /src/* /build/; )` excludes both directories. | **Only the `node_modules` half works.** `GLOBIGNORE` filters the expansion of the `/src/*` glob; `/src/infra/.terraform` is never *in* that expansion (only `/src/infra` is), and `cp -r` then recurses into `/src/infra` on its own. Reproduced on a synthetic fixture: `node_modules` absent, `infra/.terraform` **PRESENT**. | Reject the snippet. Recorded as a User-Challenge in `specs/<branch>/decision-challenges.md`. |
| `credential-persist-home-guard.test.sh` is a working precedent for this fix. | Working precedent for a **top-level** exclusion only; its own comment says so verbatim — *"The exclusion is TOP-LEVEL-ONLY by construction … a nested `sub/.terraform` cannot be expressed here at all (measured: a `GLOBIGNORE="$1/.terraform:$1/*/.terraform"` still copies the nested one)."* There `$1` **is** `infra/`; here `/src` is `apps/web-platform`. | Cite it for the *dotfile* property (which transfers) and explicitly for why its *mechanism* does not. |
| A slashed tar pattern (`--exclude=./node_modules`) is "matched against the whole member name", i.e. anchored. **(This was v2's own claim.)** | **False.** Measured: `--exclude=infra/.terraform` excluded **both** `./infra/.terraform` **and** a planted `./deep/a/infra/.terraform`. `--exclude` defaults to `--no-anchored` and matches at any `/`-delimited component boundary regardless of slashes. `./node_modules` is root-only *solely* because a literal `./` component exists only at the archive root. | Rewrite the shipped comment. The behaviour is right; the stated rule was wrong and would mislead the next person writing a slashed pattern. |
| `infra/.terraform` is ~162 MB. | **247 MB today**; `node_modules` ~2 GB. | Volatile counts live here only; the shipped comment says "~2 GB". |
| `infra/` is the only terraform root under the app. | `apps/web-platform/infra/sentry/` is a **second** root (`main.tf`, `versions.tf`, `.terraform.lock.hcl`; no `.terraform` yet). | `--exclude=.terraform` covers any depth, verified against a planted `deep/a/infra/.terraform` too. |
| CI will exercise this change. | **No.** Neither `ci.yml` trigger regex names the helpers — capture: `apps/web-platform/(package-lock\.json\|server/agent-runner-sandbox-config\.ts\|scripts/sandbox-canary\.mjs\|infra/sandbox-canary-argv\.json)`; propagation: `apps/web-platform/(package-lock\.json\|server/agent-env\.ts\|server/agent-runner-sandbox-config\.ts\|scripts/plugin-root-sandbox-propagation-probe\.mjs)`. **And** `sdk-bump-sandbox-gate.sh` carries a *second, internal* `capture_trigger` regex over the same three paths — so even forcing the job to start would leave the canary capture a no-op. | Do not rely on the paid gates. Cost of the rejected alternative corrected from "two paid turns" to **one**. |
| A copy failure surfaces in the gate job log. | **Only on the propagation path.** `ci.yml` runs that helper under `set -euo pipefail` with unredirected stderr. The canary path goes through `sdk-bump-sandbox-gate.sh`: `verdict_json="$(bash -c "$VERIFY_CMD" 2>/dev/null \| tail -1 \|\| true)"` — stderr discarded, exit swallowed, empty verdict → `::warning::` + `require_capture_ack=1`. | Delete the `2>/dev/null` (safe: `$( )` captures stdout only; the suite injects `SDK_GATE_VERIFY_CMD` and asserts nothing on stderr). The residual ack-fallback degradation is documented and filed, not papered over. |
| (v1, self-inflicted) The worktree has neither `node_modules` nor `infra/.terraform`. | **False** — it has `node_modules` (~2 GB); only `infra/.terraform` is absent. | Phase 0.3 corrected. |
| `apps/web-platform/scripts/lib/*.test.sh` is auto-registered. | **True** — `scripts/test-all.sh` globs it in the `want_scripts` block and runs `run_suite "$f" bash "$f"`, so no exec bit is needed. CI invokes `bash scripts/test-all.sh scripts`. | L1 suite lands there. |
| No nested `node_modules` component is tracked under the app. | **True** — `git ls-files apps/web-platform \| grep -c '/node_modules/'` → `0`. | Anchoring is future-proofing; pinned by a survivor assertion. |
| `sandbox-canary-argv.json` might enumerate project subpaths. | **It does not** — only `/`, `/proc`, `/dev`, `/dev/null`, `${CANARY_WS}`, `${CANARY_EMPTY}`. Its `_comment` records that `normalizeCapturedArgv()` drops host paths, and ADR-079 grounds the invariant in the **base OS filesystem**. | R9 tightened from "not provable" to "provably outside the projection surface". |

## User-Brand Impact

**If this lands broken, the user experiences:** a red `plugin-root-propagation-gate`, or a silently
ack-degraded `sandbox-canary-capture-gate`, on the *next* PR that touches an SDK/sandbox input —
i.e. the gate proving `CLAUDE_PLUGIN_ROOT` reaches the sandboxed Bash, and the gate proving the
deployed bwrap argv matches the committed fixture. Worst realistic case is a truncated `/build`
producing a confusing `infra_error` / ack-fallback rather than a wrong-but-green verdict; `ci.yml`
already reddens fail-closed on `does_not_propagate`.

**If this leaks, the user's data/workflow/money is exposed via:** nothing new. The change strictly
*narrows* what enters the container (removing ~2.27 GB of host content, including the provider
cache, from the container layer). It touches no credential, no persisted store, no network egress.

**Brand-survival threshold:** `none` — CI-only tooling; no user-facing surface, no user data, no
production write path. No changed path matches the canonical sensitive-path regex (verified: all
four are `apps/web-platform/scripts/…`), so no `threshold: none, reason:` scope-out bullet is
required.

## Mechanism

The copy does not live inline in either helper. It lives in **one shipped file** that both helpers
invoke — `/src` is a mount of `apps/web-platform` and the helpers live inside it, so
`/src/scripts/lib/…` is reachable from inside the container.

New file `apps/web-platform/scripts/lib/in-image-copy-src.sh` (mode 644 — invoked as `bash <path>`,
matching the sibling library and `run_suite`'s own invocation style):

```bash
#!/usr/bin/env bash
# Copy the bind-mounted app tree into the container build dir, minus what the very
# next command discards (#7007).
#
# Use:   bash /src/scripts/lib/in-image-copy-src.sh /src /build
# Called from BOTH in-image verifiers: sandbox-canary-verify-in-image.sh and
# plugin-root-propagation-verify-in-image.sh.
# Pinned by: apps/web-platform/scripts/lib/in-image-copy-src.test.sh (auto-discovered
# by the apps/web-platform/scripts/lib/*.test.sh glob in scripts/test-all.sh).
#
# EXECUTED, not sourced -- a deliberate divergence from the sibling library
# (supabase-ref-resolver.sh, which is sourced, defines one function, returns rather
# than exits, and sets no shell options at file scope). Sourcing this would leak
# `set -o pipefail` into the canary caller, whose next lines include a
# `curl -fsSL https://bun.sh/install | bash` pipeline. Scoping pipefail to this file
# is the entire reason the exit guard below can be trusted; do not harmonise it with
# the sibling by converting it to a sourced function.
#
# WHY the exclusions: /src is a ro bind of apps/web-platform, so on any warm working
# tree it carries node_modules (~2 GB) and the gitignored infra/.terraform provider
# cache (~250 MB). The caller runs `npm ci` immediately after, which rebuilds
# node_modules from scratch, and nothing in either probe reads .terraform. Measured
# in the pinned node:22-slim image against a warm tree: 22.96 s / 2.3 GB before,
# 0.48 s / 35 MB after.
#
# NOT GLOBIGNORE (the sibling pattern in infra/credential-persist-home-guard.test.sh):
# that filters glob EXPANSION, so it can only exclude a TOP-LEVEL entry.
# infra/.terraform is one level down, cp -r recurses into infra on its own, and the
# exclusion silently does nothing. Measured on a fixture, not assumed.
#
# ANCHORING -- read this before editing either pattern. GNU tar --exclude defaults to
# --no-anchored and matches at ANY /-delimited component boundary; a slash in the
# pattern does NOT anchor it (measured: --exclude=infra/.terraform also excluded a
# planted deep/a/infra/.terraform). So:
#   --exclude=.terraform      matches that component at any depth -- intended. Covers
#                             infra/ and infra/sentry/ (a second terraform root, not
#                             yet initialised). Never matches .terraform.lock.hcl,
#                             because the pattern has no wildcard and must match a
#                             whole component.
#   --exclude=./node_modules  is root-only ONLY because a literal ./ component exists
#                             just once, at the archive root -- which holds solely
#                             because the archive is created with `.` as its member
#                             root below. Change that `.` to `*` or to "$SRC" and the
#                             exclusion silently stops matching: the copy still
#                             succeeds, just full-fat, with no error anywhere. CI
#                             cannot see that regression (a cold checkout has no
#                             node_modules); the test suite is the only detector.
#
# --no-same-owner is load-bearing, not defensive: GNU tar as root defaults to
# --same-owner and would restore the HOST uid/gid off the ro bind mount, so DEST would
# stop being root-owned the way cp -r left it. Ownership parity only -- tar also
# restores exact modes and mtimes where cp -r applied the umask and stamped fresh ones
# (measured as root, umask 022: cp -r -> 644 + mtime now; tar -> 664 + mtime
# preserved). Accepted: strictly more faithful to the source, and provably outside the
# canary fixture projection surface (see ADR-079 Fidelity note).
#
# pipefail is set HERE rather than in the callers precisely so it has no blast radius
# on the canary caller`s bun-install pipeline. It is load-bearing and measured: on an
# unreadable member the pipeline gives PIPESTATUS=(2 0) -- WITH pipefail the guard
# fires (exit 2), WITHOUT it the shell exits 0 and DEST is silently truncated while
# npm ci carries on against a partial tree.
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

The `if !` form is the *only* shape in which the FATAL is reachable: `pipefail` makes the pipeline
status non-zero when either tar fails, and the `if` condition context suspends errexit long enough
for the diagnostic to print. (v1 used a bare pipeline plus a `PIPESTATUS` check; two reviewers
independently measured that under `set -e` without `pipefail` the shell dies *at the pipeline*,
before the capture — so the FATAL branch was dead code for every failure mode v1 claimed.)

Each helper's inline change is two lines, replacing `cp -r /src /build && cd /build`:

```bash
    bash /src/scripts/lib/in-image-copy-src.sh /src /build
    cd /build
```

Constraints, each verified rather than assumed:

- **`tar` exists in the pinned image** — `docker run --rm node:22-slim@sha256:4f77a690… tar --version`
  → `tar (GNU tar) 1.34` (host 1.35; identical results on the same fixture). `tar` is Essential on
  Debian.
- **`/src` is readable, not executable-required** — invoked as `bash <path>`, so the read-only mount
  suffices and no exec bit is needed.
- **No trust or bootstrap problem.** The container already runs `/build/scripts/sandbox-canary.mjs`
  — a copy of the same checkout — as root. Executing `/src/scripts/lib/*.sh` is the same principal
  and provenance, one step earlier. Both gate jobs are gated on
  `head.repo.full_name == github.repository`, so fork-authored code never reaches this path, and
  `/src` is mounted before the `bash -c` body (the only prior commands are `apt-get`).
- **`APP_DIR` is env-overridable** (`SANDBOX_CANARY_APP_DIR` / `PLUGIN_ROOT_PROBE_APP_DIR`; no
  non-default caller today). The `/src` contract therefore widens from "any directory" to "a
  directory carrying its own copy tool at `scripts/lib/in-image-copy-src.sh`" — stated in both
  helper headers.
- **In-image ownership verified** — `stat -c "%U %n"` on `/build/package.json`, `/build/.gitignore`,
  `/build/scripts` after the tar copy → all `root`, matching `cp -r`. Now pinned by AC6.

### Alternatives considered

| Alternative | Verdict | Why |
| --- | --- | --- |
| The issue's `GLOBIGNORE` one-liner | **Rejected** | Empirically cannot exclude `infra/.terraform` — the only half the issue names as motivation. |
| Two-stage `GLOBIGNORE` | **Rejected** | Per-level by construction: misses `infra/sentry/.terraform` the day that root is initialised, needing a third stage. Also re-imports the documented colon/glob-metacharacter fragility. |
| Inline the tar block in both helpers (v1) | **Rejected at review** | Duplicates ~25 lines of rationale into two single-quoted `bash -c` strings, then needs a byte-identity pin, marker extraction, `sed` substitution, an `eval`, and an apostrophe ban to hold it together — and the `eval` would have run `mkdir -p /build` on the CI runner root had substitution silently failed. |
| `cp -r` then `rm -rf` the two dirs | **Rejected** | Pays the 22.96 s / 2.3 GB copy, then pays again to delete. The I/O *is* the defect. |
| `rsync -a --exclude=…` | **Rejected** | Absent from `node:22-slim`; would add an `apt-get install` to a path whose point is to be fast. |
| Mask at the docker layer (`--tmpfs /src/node_modules`) | **Rejected** | Needs the mountpoint to pre-exist inside a read-only bind. A fresh CI checkout has no `node_modules`, so docker would fail to create it — breaking the gate in exactly the environment it must work in. |
| Allow-list only what the probes read | **Rejected** | Smaller, but changes the container filesystem shape, and the canary's premise is that captured argv is a function of that filesystem. Not worth the blast radius for a p3 chore. |
| `set -o pipefail` in the *callers* | **Rejected** | Would change the canary caller's `curl -fsSL https://bun.sh/install \| bash` semantics. Setting it inside the copy script gives the identical guarantee with zero blast radius. |
| Add the helpers to the gates' `ci.yml` trigger regexes | **Rejected — cost corrected** | Would start the canary job, but `sdk-bump-sandbox-gate.sh`'s **internal** `capture_trigger` regex covers only `agent-runner-sandbox-config.ts`, `sandbox-canary.mjs`, `sandbox-canary-argv.json` (plus a detected SDK bump), so the capture would no-op: the true cost is **one** paid Haiku turn (propagation only) and the canary half would be a gate that structurally cannot fire. That is a worse trade than v1 assumed, not a better one. |
| A docker arm inside the L1 suite, self-skipping when `docker info` fails | **Considered, declined** | It would exercise the *image's* tar 1.34 rather than the runner's 1.35, closing R10 mechanically. But `ubuntu-latest` has docker, so it would run on every `scripts`-shard invocation and add a `node:22-slim` pull to a shard that is otherwise pure-bash. Declined because R10's trigger is a **deliberate human edit** to a digest pin (not drift), and that edit is exactly when AC6/AC7 re-run; assertion 8 additionally pins the two helpers' digests to each other so a one-sided bump reddens. Revisit if a base bump ever ships without an AC6/AC7 transcript. |
| Un-swallow the canary gate's ack-fallback (`\|\| true`) so a copy failure reddens | **Scoped out, filed** | The `2>/dev/null` deletion (diagnosability) is folded in — safe, since `$( )` captures stdout only and the suite asserts nothing on stderr. Changing `\|\| true` would alter the gate's *designed* ack-fallback posture (an explicit "a soft-degraded capture must never REMOVE the ack requirement" comment sits directly above it) and cannot be verified without the paid path. See §Scope-outs. |

## Verification ladder

Both helpers exit early without `ANTHROPIC_API_KEY` and drive a real, **paid** Haiku turn when it
is present, so the paid end-to-end path will not be run. Three rungs, none paid:

- **L1 — hermetic suite (the only guard that can ever fire).**
  `apps/web-platform/scripts/lib/in-image-copy-src.test.sh`: pure bash + GNU tar, synthesized
  fixture, no docker, no network, no key. It invokes the **real shipped** script with fixture
  paths. Auto-registered by the `apps/web-platform/scripts/lib/*.test.sh` glob in
  `scripts/test-all.sh` (`want_scripts` shard), run by CI as `bash scripts/test-all.sh scripts` — a
  required `test` context. Because the exclusions are no-ops on a cold CI checkout, this suite is
  what makes a broken exclusion detectable at all.
- **L2 — in-image rehearsal against a warm tree** (in-session, recorded in the PR body). Run the
  shipped script inside the pinned digest, then assert whole-tree parity, root ownership, and that
  `npm ci --no-audit --no-fund` succeeds in `/build`. Parity, `tar --version`, ownership and the A/B
  were already run for the v1 block; the `npm ci` rung has **never** been run and is AC7.
- **L3 — paid end-to-end.** **NOT RUN.** The PR body must say so in those words.

## Files to Edit

- `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` — replace the
  `cp -r /src /build && cd /build` line with the two-line call; add a header sentence noting
  `/build` is a filtered copy of `/src` (naming `scripts/lib/in-image-copy-src.sh`) and that
  `$APP_DIR` must therefore carry that file.
- `apps/web-platform/scripts/plugin-root-propagation-verify-in-image.sh` — same two-line call, same
  header sentence. Both headers; a one-sided edit is drift.
- `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh` — delete the `2>/dev/null` in
  `verdict_json="$(bash -c "$VERIFY_CMD" 2>/dev/null | tail -1 || true)"` so a copy FATAL reaches
  the job log. Nothing else on that line changes; `|| true` stays (see §Scope-outs).
- `knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`
  — one-line addendum to the Fidelity note: whoever next regenerates the fixture runs `--capture`
  in this container, where `/build` is now a *filtered* copy of the checkout; the exclusions are
  outside the argv projection surface (the fixture carries only `/`, `/proc`, `/dev`, `/dev/null`,
  `${CANARY_WS}`, `${CANARY_EMPTY}`). This is an addendum to an existing ADR, not a new decision.

## Files to Create

- `apps/web-platform/scripts/lib/in-image-copy-src.sh` — the shared copy (mode 644).
- `apps/web-platform/scripts/lib/in-image-copy-src.test.sh` — the L1 suite (mode 644).

Specifically **not** edited: `.github/workflows/ci.yml` (trigger sets — see Alternatives),
`scripts/test-all.sh` (the directory is already globbed), and
`apps/web-platform/infra/credential-persist-home-guard.test.sh` (its `GLOBIGNORE` remains correct
*for its own top-level case* and must not be "harmonised" with this).

## Implementation Phases

### Phase 0 — preconditions (re-verify; do not inherit)

0.1 Re-read both helpers; confirm `cp -r /src /build && cd /build` is still present. Anchor on
    content, not on `:42` / `:39` (`cq-cite-content-anchor-not-line-number`).
0.2 `docker info >/dev/null` — the L2 rehearsal needs a daemon. If absent, AC6/AC7 cannot run; say
    so explicitly in the PR body rather than skipping silently.
0.3 Pick a warm `/src`. **This worktree has `node_modules` (~2 GB) but not `infra/.terraform`**;
    the repo's synced working copy at `/home/jean/git-repositories/jikig-ai/soleur/apps/web-platform`
    has both. Mount that for the rehearsal — a measurement, not a source read.
0.4 Read `apps/web-platform/scripts/lib/supabase-ref-resolver.sh` before writing the new file, so
    the source-vs-execute divergence is deliberate and documented rather than accidental.

### Phase 1 — RED

Write `in-image-copy-src.test.sh`, and create `in-image-copy-src.sh` with a deliberately naive body
(`mkdir -p "$DEST"; cp -r "$SRC"/. "$DEST"/`).

**Expected RED set is {3, 5, 6}**, of which **3 is the load-bearing one** (a genuine behavioural
failure: `node_modules` present). 5 fails because `cp` prints `cannot stat`, not `FATAL:`; 6 fails
because the helpers are migrated in Phase 2. An implementer handed a 3-failure transcript against a
plan predicting 1 would reasonably suspect the suite is broken — hence the explicit set.

Suite shape (mirror `apps/web-platform/scripts/sdk-bump-sandbox-gate.test.sh`): `set -eu`,
`SCRIPT_DIR` resolution, `T="$(mktemp -d)"` with `trap 'rm -rf "$T"' EXIT` (an owning trap is
required — `scripts/lint-trap-tempfile-ownership.py` **RULE (c) — MKTEMP WITH NO OWNING TRAP**
gates new callers), `pass`/`fail` counters where `fail()` returns 0 so `set -e` cannot abort the
harness before the summary, and a single `[[ "$FAIL" -eq 0 ]] || exit 1` chokepoint. All fixtures
synthesized inline (`cq-test-fixtures-synthesized-only`).

Two bash footguns to respect, both from institutional learnings: any deliberately-nonzero command
inside a command substitution needs `|| true` (or `if ! …` / `|| rc=$?`) or `set -e` aborts before
`fail()` prints; and never `producer | grep -q` under `pipefail` (early match SIGPIPEs the
producer) — use `grep <<<"$var"` or a count comparison.

**Shared path arrays — single source, so assertions 1/3/4 cannot drift apart**, each with a
minimum-cardinality guard so a builder regression fails loud instead of looping zero times:

```
EXCLUDED_PATHS=( node_modules infra/.terraform infra/sentry/.terraform )   # >= 3
SURVIVE_PATHS=( .gitignore .env.example .nvmrc .dockerignore
                .service-role-allowlist .dependency-cruiser.cjs
                package.json package-lock.json scripts/sandbox-canary.mjs
                infra/main.tf infra/.terraform.lock.hcl
                infra/sentry/.terraform.lock.hcl
                test/fixtures/node_modules/keepme.txt )                    # >= 13
```

Fixture: every `SURVIVE_PATHS` entry with distinct non-empty content, plus a file under each
`EXCLUDED_PATHS` entry.

Assertions (8):

1. **Positive control (anti-vacuity).** Every `EXCLUDED_PATHS` and `SURVIVE_PATHS` entry exists in
   the fixture, and both arrays meet their cardinality floors. Without this the suite passes
   trivially the day the builder breaks — the vacuity class #7001 spent a session on.
2. **Run the real artifact.** `bash "$SCRIPT_DIR/in-image-copy-src.sh" "$SRC" "$DST"` exits 0. No
   extraction, no substitution, no `eval`.
3. Every `EXCLUDED_PATHS` entry is **absent** from `$DST`. **SKIP (not pass) if assertion 2
   failed** — an empty `$DST` satisfies every absence check, and a summary that reports "pass" in
   that state actively misleads.
4. **Whole-tree parity + content.** `diff -rq --exclude=node_modules --exclude=.terraform "$SRC"
   "$DST"` exits 0, **and** every `SURVIVE_PATHS` entry passes `cmp "$SRC/$p" "$DST/$p"`. `cmp`,
   not `test -e`: truncation is the headline failure mode, and a 0-byte survivor passes existence.
   The `--exclude` flags mask basename matches at any depth in both directions, which is exactly
   why `test/fixtures/node_modules/keepme.txt` must be in `SURVIVE_PATHS`. Also SKIP if 2 failed.
5. **Producer-failure control — the discriminating stimulus.** Plant a `chmod 000` file inside the
   fixture `$SRC`, then run the script: assert non-zero exit **and** `FATAL:` on stderr. Guard with
   `[ "$(id -u)" -ne 0 ]` and emit a **loud SKIP** if root (root reads anything, which would make
   it vacuous in a container dev-run). Measured justification: `PIPESTATUS=(2 0)` — with `pipefail`
   the guard fires (exit 2), without it the shell exits **0** and `$DST` is silently truncated. A
   *missing* `$SRC` fails both tars and passes with or without `pipefail`, so it does **not**
   discriminate and must not be used as the control.
6. **Both call sites migrated — anchored on the invocation, not the filename.** Assert the exact
   literal `bash /src/scripts/lib/in-image-copy-src.sh /src /build` appears in each helper, and
   that neither matches `^[[:space:]]*cp -[aRrP]` at all. A bare `in-image-copy-src.sh` grep is
   vacuous by this plan's own design — the mandated header sentence names the file, so the positive
   half would pass with the call site gone (`cq-assert-anchor-not-bare-token`).
7. **`bash -n`** on both helpers and on `in-image-copy-src.sh`. An unbalanced quote in either
   helper's single-quoted `docker run … bash -c '…'` body breaks the *outer* parse, so one builtin
   covers the whole apostrophe class.
8. **Base-image digest parity.** Both helpers pin the same `node:22-slim@sha256:…`. Both headers
   already say "keep in sync on a base bump"; nothing enforced it. One line makes it load-bearing
   and reddens a one-sided bump.

### Phase 2 — GREEN

Replace the naive body with the §Mechanism body; migrate both helpers; add both header sentences;
delete the `2>/dev/null` in `sdk-bump-sandbox-gate.sh`; add the ADR-079 Fidelity addendum. Re-run
the suite: all eight assertions pass.

### Phase 3 — mutation proof

Delete `set -o pipefail` from the shipped script in a scratch copy and re-run the suite: assertion 5
must go RED. Restore. Without this run, R5's central claim is asserted, not tested. Record the
transcript (AC3).

### Phase 4 — L2 rehearsal

Run AC6 and AC7 against the warm tree in the pinned digest; capture parity, ownership, `npm ci`, and
the A/B numbers for the PR body.

### Phase 5 — exit gate

`bash scripts/test-all.sh scripts` (the gate's own invocation — a hand-enumerated subset is the
#7003 defect class, per `knowledge-base/project/learnings/2026-07-28-my-ac-verified-four-paths-while-ci-verified-five.md`),
plus `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`, plus the live form
used by `scripts/lint-trap-tempfile-ownership.test.sh`.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** Both helpers migrated, checked by explicit path (a directory pathspec would also match the
  new suite, which legitimately mentions both strings). Run **after** `git add` — `git grep` is
  tracked-only:

  ```bash
  H1=apps/web-platform/scripts/sandbox-canary-verify-in-image.sh
  H2=apps/web-platform/scripts/plugin-root-propagation-verify-in-image.sh
  ! git grep -q -e 'cp -r /src /build' -- "$H1" "$H2"
  [ "$(git grep -l -e 'bash /src/scripts/lib/in-image-copy-src.sh /src /build' -- "$H1" "$H2" | wc -l)" -eq 2 ]
  ```

  (`git grep -c` with no match exits 1 and prints nothing, which would abort a `set -e` harness;
  `-q` + `!` is the checkable form. `-e` is used so a future pattern starting with `-` cannot
  silently become a flag.)
- **AC2** `bash apps/web-platform/scripts/lib/in-image-copy-src.test.sh` exits 0, zero FAIL, and its
  summary shows assertion 5 as **run** (not SKIP) — a root-context run that silently skips the only
  discriminating control does not satisfy this AC.
- **AC3** Three transcripts in the PR body: (a) Phase 1 RED with the naive body — failures **{3, 5,
  6}**; (b) Phase 2 GREEN — 8/8; (c) Phase 3 mutation — `pipefail` deleted, assertion 5 RED.
- **AC4** `bash scripts/test-all.sh scripts` is green.
- **AC5** `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` is green over
  every changed file (the gate's own `--changed` form).
- **AC6** In-image parity + ownership, post-edit, warm tree, pinned digest:

  ```bash
  docker run --rm -v "<warm-app-dir>:/src:ro" \
    node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d \
    bash -c 'bash /src/scripts/lib/in-image-copy-src.sh /src /build
             diff -rq --exclude=node_modules --exclude=.terraform /src /build
             test ! -e /build/node_modules
             test ! -e /build/infra/.terraform
             stat -c "%U %n" /build/package.json /build/.gitignore /build/scripts'
  ```

  exits 0 and every `stat` line reads `root` (this is what pins R8's mitigation; v2 left it resting
  on an in-session memory).
- **AC7** In the same container and invocation, `cd /build && npm ci --no-audit --no-fund` exits 0 —
  the actual next command in both helpers, against the filtered tree. Highest-fidelity check in the
  plan and the only one exercising the *gate* rather than the *filter*; never run before.
- **AC8** The PR body records the A/B (before/after wall clock and `/build` size) from the pinned
  image, and states in those words that the **paid** end-to-end path (`ANTHROPIC_API_KEY` + a real
  Haiku turn) was **not run**.
- **AC9** The scope-out issue from §Scope-outs is filed, with the labels verified to exist via
  `gh label list --limit 200`, and its number referenced in the PR body.

### Post-merge (operator)

None. Every step is automatable from this session (docker, bash, python3, `gh` all present; no
vendor console, no credential mint, no infrastructure apply).

## Risks & Mitigations

| # | Risk | Likelihood | Mitigation |
| --- | --- | --- | --- |
| R1 | Suite passes vacuously because the fixture stopped containing the excluded dirs. | Medium (the #7001 class) | Assertion 1 is a positive control over the shared arrays with cardinality floors; assertion 3 asserts absence against a fixture proven to contain them. |
| R2 | Fix applied to one helper and not the other. | **Eliminated** | One copy implementation; a divergent *implementation* is unexpressible. One-sided *migration* caught by assertion 6, one-sided *digest bump* by assertion 8. |
| R3 | The archive root `.` is later changed to `*` or `"$SRC"`, silently un-anchoring `--exclude=./node_modules`; the copy still succeeds, full-fat. | Low, silent | Assertion 3 fails. Called out in the script comment because there is no other signal — CI's cold checkout cannot see it. |
| R4 | An apostrophe enters a helper's single-quoted `bash -c` body, breaking the container invocation. Neither paid gate fires on these files. | Low, unbounded cost | The copy logic no longer lives in that string; assertion 7 (`bash -n`) fails on any unbalanced quote in the outer parse. **Residual:** the *inner* body's own syntax is checked by nothing, here or in CI — accepted rather than rebuilding the extraction harness the review just deleted. |
| R5 | Producer `tar` fails, the consumer extracts a truncated stream and exits 0, `npm ci` runs against a partial tree. | Low | `set -o pipefail` inside the copy script (zero caller blast radius) plus the `if !` form. **Pinned by assertion 5 and proven by the Phase 3 mutation run**, not by assertion alone. Measured: `PIPESTATUS=(2 0)`; exit 2 with pipefail, exit 0 without. |
| R6 | `--exclude=.terraform` drops `.terraform.lock.hcl`. | Low | Falsified on the fixture and in-image; both lock files survive (a no-wildcard pattern matches a whole component). Covered by assertion 4's `cmp` over `SURVIVE_PATHS`. |
| R7 | `--exclude=./node_modules` drops a nested `node_modules`. | Low | Falsified: `test/fixtures/node_modules/keepme.txt` survives. None tracked today (`grep -c '/node_modules/'` → 0), so this is future-proofing, pinned as a `SURVIVE_PATHS` entry. |
| R8 | `tar -x` as root re-owns `/build` to the host uid off the ro bind. | Low | `--no-same-owner`, now pinned by AC6's `stat -c %U`. Ownership parity only — mode/mtime are restored exactly rather than umask-filtered (measured: `cp -r` → 644 + fresh mtime; `tar` → 664 + preserved). Accepted: more faithful, and outside the fixture projection surface (R9). |
| R9 | The `/build` content/mode/mtime delta perturbs the captured bwrap argv and byte-diff-fails the committed fixture. | Low | `sandbox-canary-argv.json` contains only `/`, `/proc`, `/dev`, `/dev/null`, `${CANARY_WS}`, `${CANARY_EMPTY}` — zero project-relative tokens — and its `_comment` records that `normalizeCapturedArgv()` drops host paths; ADR-079 grounds the invariant in the **base OS filesystem**. The delta is provably outside the projection surface. The ADR-079 addendum tells the next fixture-regenerator that `/build` is now filtered. |
| R10 | `tar` absent or behaviourally different after a base-image bump. | Low | The base is a **digest pin**, so the trigger is a deliberate edit, not drift — and that edit is exactly when AC6/AC7 re-run. Assertion 8 reddens a one-sided bump. A self-skipping docker arm in the suite was considered and declined (see Alternatives). |
| R11 | `tar -c` exits non-zero on `file changed as we read it`; with `pipefail` a race that `cp -r` tolerated becomes a FATAL. Candidate churners in a warm tree: `.next/`, `tsconfig.tsbuildinfo`. | Low | Cannot occur in CI (cold checkout, no dev server, no concurrent build). Locally it requires a writer inside `apps/web-platform` during a deliberate run of a creds-gated script, and the new behaviour is a **loud** failure where `cp -r` would have produced a torn file silently. `--warning=no-file-changed` was considered and **not** prescribed: the race could not be reproduced in-session, so its effect on the exit status is unverified — and suppressing a truncation signal is what R5 exists to prevent. **REVISED at review.** Two corrections. (a) The dismissal was backwards: CI is exactly where this change is INERT (a cold checkout has no `node_modules`/`.terraform`), so "cannot occur in CI" argues nothing — local is the only place the optimisation acts, and local is where the race lives. (b) `--warning=no-file-changed` was measured: it suppresses the MESSAGE and still exits 1, so it could never have worked. The shipped fix discriminates on tar's overloaded STATUS instead (2 = error -> FATAL; 1 = warning -> WARN, copy is complete), and `.next`/`out` are now excluded outright — removing the dominant churner as well as the largest local cost. |
| R12 | A copy FATAL is invisible on the **canary** path and degrades the gate to an ack-fallback a commit trailer satisfies. | Medium (pre-existing) | The `2>/dev/null` deletion puts the FATAL in the job log. The residual — `\|\| true` still swallows the exit, so the gate warns rather than reddens — is a deliberate pre-existing design ("a soft-degraded capture must never REMOVE the ack requirement") and is filed, not silently inherited. See §Scope-outs. |

## Scope-outs

**SO-1 — the canary gate's verify failure degrades to an ack-fallback rather than reddening.**
`apps/web-platform/scripts/sdk-bump-sandbox-gate.sh` captures the verify command as
`verdict_json="$(bash -c "$VERIFY_CMD" 2>/dev/null | tail -1 || true)"`. This plan deletes the
`2>/dev/null` (diagnosability — safe, since `$( )` captures stdout only and the suite injects
`SDK_GATE_VERIFY_CMD` without asserting on stderr). It does **not** touch `|| true`: an explicit
comment directly above states the ack-fallback is intentional ("a soft-degraded capture must never
REMOVE the ack requirement"), so any change there is a behaviour change to a paid gate that cannot
be verified without the paid path.

*Inline triage performed:* the diagnosability half is fixed inline; only the posture question is
deferred. *File at `/work` time* with `deferred-scope-out`, `domain/engineering`,
`priority/p3-low`, `type/chore` (verify each exists via `gh label list --limit 200` first).
*What:* decide whether a non-zero `$VERIFY_CMD` exit should redden the canary gate instead of
falling back to the ack. *Re-evaluate when:* a verify failure is ever observed in the wild, or the
ack trailer is used to pass a PR whose capture failed for an infrastructural reason.

## Observability

```yaml
liveness_signal:
  what: apps/web-platform/scripts/lib/in-image-copy-src.test.sh reporting 0 FAIL, with assertion 5 RUN (not SKIP)
  cadence: every PR and every merge to main
  alert_target: the required `test` status context (CI scripts shard)
  configured_in: scripts/test-all.sh (apps/web-platform/scripts/lib/*.test.sh glob, want_scripts shard); .github/workflows/ci.yml `bash scripts/test-all.sh scripts`
error_reporting:
  destination: CI job log + red required check. In-container the copy prints
    "FATAL: in-image copy failed (SRC -> DEST)" to stderr and exits 1. On the PROPAGATION
    path ci.yml runs the helper under `set -euo pipefail` with unredirected stderr, so the
    job reddens and the FATAL is visible. On the CANARY path sdk-bump-sandbox-gate.sh wraps
    the helper in `$(... | tail -1 || true)`; this plan deletes its `2>/dev/null` so the
    FATAL reaches the log, but `|| true` still converts the failure into an ack-fallback
    warning rather than a red gate (scope-out SO-1).
  fail_loud: partial -- fail-closed on the propagation JOB; diagnostic-but-degraded on the
    canary gate. CORRECTED at review: neither in-image gate is a branch-protection
    required context (infra/github/ruleset-ci-required.tf lists 21, and neither is
    among them), so a red propagation job does NOT block a merge. The only required
    context in play is the `test` aggregator that carries the hermetic suite.
failure_modes:
  - mode: producer or consumer tar fails, DEST truncated
    detection: FATAL on container stderr + non-zero exit; pinned by suite assertion 5 and
      proven by the Phase 3 pipefail-mutation run
    alert_route: propagation JOB reddens (advisory, not merge-blocking); canary gate emits
      ::warning:: + requires the ack trailer
  - mode: exclusion silently stops applying (anchor broken, regression to a full copy)
    detection: suite assertion 3 against the positive-controlled fixture. NOTE this is the
      ONLY detector -- a cold CI checkout has neither directory, so no CI job can observe
      the regression by running the real path.
    alert_route: red `test` context
  - mode: dotfiles, lock files or survivors dropped or truncated
    detection: suite assertion 4 (whole-tree diff -rq plus cmp over SURVIVE_PATHS)
    alert_route: red `test` context
  - mode: one helper migrated and the other not, or a one-sided base-image digest bump
    detection: suite assertions 6 and 8 (invocation-anchored grep; digest parity)
    alert_route: red `test` context
  - mode: unbalanced quote in a helper's docker bash -c body
    detection: suite assertion 7 (bash -n on both helpers). Residual: the inner body's own
      syntax is checked by nothing.
    alert_route: red `test` context
  - mode: canary verify fails for any reason and the gate degrades to the ack trailer
    detection: the FATAL line on container stderr, adjacent to the ::warning:: in the
      workflow run log (observability layer 6). NOTE the ::warning:: ANNOTATION itself
      renders verdict='' reason='' and does not carry the cause; the cause is in the raw log.
    alert_route: reviewer reading the job log; tracked by scope-out SO-1
logs:
  where: GitHub Actions job logs for the `test` (scripts shard) job and, when the paid gates
    fire, the sandbox-canary-capture-gate / plugin-root-propagation-gate jobs
  retention: GitHub Actions default (90 days)
discoverability_test:
  command: bash apps/web-platform/scripts/lib/in-image-copy-src.test.sh
  expected_output: a PASS/FAIL summary ending with 0 FAIL and exit 0
```

The detection path needs no remote shell access. Not a blind execution surface (the suite runs on
the runner, not inside the sandbox), so §2.9.2 adds no requirements. No soak-gated or time-gated
close criterion, so §2.9.1 does not fire.

## Architecture Decision (ADR/C4)

**No new ADR.** No ownership/tenancy boundary moves, no new substrate or integration, no
resolver/dispatch/trust boundary change. ADR-079 (capture-env == verify-env == replay-env == the
deploy runtime base image) is **preserved**, not amended: the copy still produces the same `/build`
contents modulo two directories that are respectively rebuilt (`node_modules`) and never read
(`.terraform`), and the fixture's projection surface excludes both.

**One addendum, in scope, not deferred** (`wg-architecture-decision-is-a-plan-deliverable`): a
single line on ADR-079's Fidelity note recording that `/build` is now a filtered copy, so the next
person regenerating the fixture with `--capture` reads it there rather than in this plan.

**C4 completeness check.** All three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` are unaffected: no
external human actor (no new correspondent, reviewer, or recipient), no external system or vendor
(the image, the SDK, and the Anthropic API edge are pre-existing and unchanged), no container or
data store, and no actor↔surface access relationship. The only mutated artifact is the byte content
of a container-local scratch directory no C4 element models. Independently confirmed against the
principles register: no AP-NNN deviation.

## Infrastructure (IaC), Encryption Posture, GDPR

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

- **IaC (§2.8):** skipped — no server, service, cron, vendor account, DNS record, cert, secret,
  firewall rule, or persistent runtime process is introduced. No remote-shell step, no
  secret-manager write, and no vendor-console step appears anywhere in this plan.
- **Encryption posture (§2.11):** skipped — trigger evaluated, not assumed. No `.tf`,
  `supabase/migrations/*.sql`, `cloud-init*.yml`, or `docker-compose*.yml` in Files to
  Edit/Create, and no persistent store or cross-component connection is introduced. The one
  store-shaped noun in the plan (`.terraform` *provider cache*) is a pre-existing read-only
  artifact being **excluded**, not created.
- **GDPR (§2.7):** skipped — no schema, migration, auth flow, API route, or `.sql` file; no new
  LLM/external-API processing of operator data (the paid turn already exists and is unchanged); no
  new artifact-distribution surface.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering

**Status:** reviewed
**Assessment:** Contained CI-tooling perf fix with a measured ~48× win and no runtime/product blast
radius. The load-bearing engineering judgements are (a) rejecting the issue's own mechanism on
empirical grounds, (b) an exclusion that survives the second terraform root at any depth, (c)
shipping the copy as one artifact both helpers call, (d) an unpaid verification ladder for a path
whose real gate is paid and does not fire on this file, and (e) stating the canary gate's
observability posture precisely instead of uniformly. All five carry the measurement that justifies
them.

Product/UX gate: not triggered — no path in Files to Edit/Create matches any UI-surface term or
glob; no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`. Tier: NONE.

### Plan review (v2) and deepen pass (v3) — applied

**Agents:** code-simplicity-reviewer, kieran-rails-reviewer, scoped strong-model consult (v2);
learnings-researcher, claim-verification pass, test-design-reviewer, architecture-strategist (v3).
**Decision:** reviewed — all mechanical findings auto-applied.

v2 (plan review):

- **P0 ×3, independently measured:** the `PIPESTATUS` guard was dead code under `set -e` without
  `pipefail`. Rewritten as a dedicated script with `set -o pipefail` + an `if !` guard.
- **P0:** AC1 used a directory pathspec the plan's own new test file would match, and `git grep -c`
  exits 1 on no-match. Rewritten with explicit paths and `! git grep -q -e`.
- **P1, converged:** replace two inline blocks with one shipped `scripts/lib/in-image-copy-src.sh`.
  Collapsed ~60% of net-new lines and removed a `mkdir -p /build`-on-the-runner-root hazard.
- **P1:** the RED failed on a missing marker, not a wrong implementation. Rewritten.
- **P1:** the mutation control must exercise producer-tar-failure.
- **P2:** false Phase 0.3 precondition; three different `node_modules` sizes; `--no-same-owner` is
  ownership-only; AC7's `bash -c '<block>; diff'` was not runnable; header sentence prescribed for
  one helper only. All corrected.
- **Cuts accepted:** byte-identity pin, path-enumeration assertion, marker-count assertion,
  substitution meta-check, `ci.yml`-unchanged AC.

v3 (deepen):

- **Architecture F1 (P0):** `sdk-bump-sandbox-gate.sh` discards the verify command's stderr and
  swallows its exit — the Observability claim was wrong for the canary path. `2>/dev/null` deleted
  inline; the residual ack-fallback filed as SO-1. Same finding corrected the rejected
  trigger-regex alternative's cost from two paid turns to one, plus a structurally inert canary half.
- **Architecture F5 (P0):** the shipped comment's tar-anchoring rule was empirically false.
  Re-measured (`--exclude=infra/.terraform` also excluded `deep/a/infra/.terraform`) and rewritten.
- **Test-design (P0):** assertion 5's stimulus did not discriminate — a missing `$SRC` passes with
  or without `pipefail`. Replaced with an unreadable member (`PIPESTATUS=(2 0)` measured), plus a
  root-guard and a Phase 3 mutation run required by AC3.
- **Test-design (P1):** assertion 3 passed vacuously against an empty `$DST`; survivors were checked
  by existence rather than content; assertions 1/3/4 could drift. Fixed with shared arrays,
  cardinality floors, `cmp`, and SKIP-on-upstream-failure.
- **Test-design + Architecture F3 (P1):** assertion 6 was vacuum-prone by this plan's own design —
  the mandated header sentence satisfies a bare filename grep. Re-anchored on the full invocation
  plus a `cp -[aRrP]` ban.
- **Test-design (P1):** the predicted RED set was wrong ({3} vs the actual {3, 5, 6}).
- **Architecture F2 (P2):** R10 rested on an unenforced promise. Docker-arm alternative named and
  declined with reason; assertion 8 (digest parity) added as the cheap mechanical half.
- **Architecture F4 (P2):** `scripts/lib/` is a source-don't-execute convention. The divergence is
  correct but was undocumented — now stated in the header, along with the test file name and the
  auto-discovery glob, matching the sibling's own header style. Mode 644 for both new files.
- **Architecture F6 (P2):** `tar -c` exits non-zero on a mid-read change where `cp -r` did not →
  new risk R11, with `--warning=no-file-changed` explicitly **not** prescribed (unverified in
  session, and it would suppress a truncation signal).
- **Architecture F7 (P2):** R9 was more pessimistic than its own citations; tightened, and the
  ADR-079 Fidelity addendum added as an in-scope deliverable.
- **Learnings:** `|| true` (or `if !`) required around deliberately-nonzero commands in command
  substitutions under `set -e`; never `producer | grep -q` under `pipefail` (SIGPIPE flake);
  minimum-cardinality guards on data-derived loops; assert destination state, not the verb. All
  folded into the Phase 1 suite shape.

## Open Code-Review Overlap

**None.** Queried all 61 open `code-review` issues (`gh issue list --label code-review --state open
--json number,title,body --limit 200`) and searched each body for
`apps/web-platform/scripts/sandbox-canary-verify-in-image.sh`,
`apps/web-platform/scripts/plugin-root-propagation-verify-in-image.sh`, and `scripts/test-all.sh`.
Zero matches.

## PR body requirements

- `Closes #7007` in the body (not the title).
- The measured A/B table from the pinned image.
- All three transcripts from AC3 (RED / GREEN / pipefail-mutation).
- A verbatim statement that the paid end-to-end path was **not** exercised: both helpers require
  `ANTHROPIC_API_KEY` and drive a real Haiku turn, and neither CI gate's trigger regex matches the
  changed files, so no paid run occurred in-session or in CI on this PR. What *was* run: the
  hermetic suite, the whole `scripts` shard, and an in-image rehearsal against a warm tree proving
  whole-tree parity, root ownership, and a successful `npm ci` in the filtered `/build`.
- The SO-1 scope-out issue number.
- The `decision-challenges.md` entries — `/ship` folds these in and files the `action-required` issue.
- No operator checklist and no operator-action headings — there are none, and those tokens trip
  `ship-operator-step-gate.sh`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. It is filled above.
- **`GLOBIGNORE` cannot express a nested exclusion — and the precedent that "already ships" says so
  in its own comment.** The issue body, written by an agent reading
  `credential-persist-home-guard.test.sh`, lifted the pattern one directory level up and inverted
  its correctness. The tell was free: the precedent's comment literally contains *"The exclusion is
  TOP-LEVEL-ONLY by construction"*. Generalisation: when a plan cites a working precedent, the
  precedent's stated **scope conditions** are part of the citation — read its comments, not just the
  line you want to copy.
- **A guard that cannot fail when its fix is removed is not a test, it is a restatement.** Assertion
  5 originally used a missing source directory — which fails *both* tars and therefore returns
  non-zero and prints FATAL with or without the `pipefail` fix it was said to pin. The only way to
  know was to run the mutation: delete the fix, re-run, and require the assertion to go red. If a
  plan says "assertion N pins guard G", the plan must also require the transcript that shows N red
  when G is deleted.
- **`set -e` does not fire before your error handler when the failure is a pipeline.** `A | B;
  rc=("${PIPESTATUS[@]}"); [[ … ]] || { echo FATAL; exit 1; }` is dead code without `pipefail`:
  errexit kills the shell *at the pipeline*. It fails closed, so nothing goes wrong — it just goes
  wrong silently, which is worse when an Observability section is built on that string.
- **A test that `eval`s a marker-extracted, path-substituted copy of shipped code tests a
  re-derivation, not the artifact.** If the code can move into a file the test invokes directly, do
  that — it deletes the extraction harness, the substitution, the fidelity gap, and (here) an `eval`
  that would have run `mkdir -p /build` on the CI runner's root had substitution silently failed.
- **A grep assertion whose passing token the plan itself mandates elsewhere in the same file is
  vacuous on arrival.** The header sentence naming `in-image-copy-src.sh` satisfies a bare-filename
  grep even with the call site deleted. Anchor on the full invocation
  (`cq-assert-anchor-not-bare-token`).
- **`tar --exclude` is `--no-anchored` by default; a slash does not anchor it.** `--exclude=./x` is
  root-only only because a literal `./` component exists once, at the archive root — which holds
  solely while the archive is created with `.` as its member root. Both facts are one edit away from
  silently reverting the optimisation with no error anywhere.
- **A trigger regex that does not name the file you are changing means CI will not exercise your
  change** — and when the optimisation is a no-op in CI's environment, CI is *structurally*
  incapable of detecting a regression in it. Grep the trigger set for the changed path, then ask
  whether CI's environment can even express the failure. Check for a **second** regex inside the
  invoked script: `ci.yml` starting a job is not the same as the job doing the work.
- **"The failure surfaces in the job log" is a claim about the caller, not the callee.** The same
  script called from two places had one fail-closed consumer and one that discarded stderr and
  swallowed the exit with `2>/dev/null … || true`. Read every caller before writing
  `error_reporting.destination`.
