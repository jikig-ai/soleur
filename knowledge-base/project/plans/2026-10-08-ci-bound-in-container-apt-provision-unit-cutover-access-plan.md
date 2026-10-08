---
title: "ci(infra): bound the in-container apt cycle in the provision-unit and cutover-access suites"
type: ci
date: 2026-10-08
slug: bound-in-container-apt-provision-unit-cutover-access
branch: feat-one-shot-9395-bound-in-container-apt
issue: 9395
closes: 9395
priority: p3-low
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# ci(infra): bound the in-container apt cycle in the provision-unit and cutover-access suites


## Enhancement Summary

**Deepened on:** 2026-10-08
**Method:** halt gates 4.6-4.12 run mechanically, plus targeted verification instead of a blanket agent fan-out (the plan-review panel of four seats had already read the sources). Research agents used: learnings-researcher, functional-discovery (no overlap found), and the plan-review panel (DHH, Kieran, code-simplicity, CTO devex lens).

### Key Improvements

1. Panel findings folded in: multi-line `bash -c` body for the PU site (A10 anchors its call and source regexes to line start), exact arm tail, `local rc`, lib-presence guard, Tier B rc classification (125 skip; 97/98/126/127/137/124 FAIL), cutover budget raised to 270 s, ADR note shrunk to two lines, real-stall reproduction and most matrix rows cut.
2. Verified by execution on 2026-10-08: the widened docker grammar counts 1 / 6 / 1 / 2 sites in ownership / rehearsal / cutover / PU and does not match the message strings `"docker run failed"`; the existing raw-apt regex misses `timeout -k 5 30 apt-get install` (so the widening is needed); the per-suite `g_ok` regex matches `$T` and not `$W`/`$TMP`; the `IFS=: read` spec parse yields file, count and variable.
3. Healthy apt cost measured in the pinned image: Tier B packages 20 s, cutover packages 55 s.

### New Considerations Discovered

- The `discoverability_test` command prints nothing on the pre-change tree (it greps for the helper call the plan adds); it is satisfied by Phase 2, so it must be run after the conversion, not before.
- Issue #8744 is still open; the PR uses `Refs #8744`, never a closing keyword.

## Overview

Two infra test suites still run an in-container apt cycle bounded only by attempt count, while the git-data
suites already share the elapsed-time bound in `apps/web-platform/infra/lib/apt-bounded.sh` (#9379). This plan
moves the Tier B image build of `cloud-init-inngest-provision-unit.test.sh` and the runtime arm of
`git-data-cutover-access.test.sh` onto that helper, and extends the derived assembly row (A10) of
`apt-bounded.test.sh` so both new consumers are bound to their arm, mount, source line and return-code
handling. No arm becomes skip-eligible, and the cutover suite's assertion accounting does not move. One behaviour
change is deliberate: a Tier B image-build failure that is neither the apt decline nor docker's own rc 125 (for
example rc 97, 98, 126, 127, 137) becomes a counted Tier B FAIL instead of a silent skip.

## Research Insights

**Premise validation (Phase 0.6).** Issue #9395 is open with no closing PR. `lib/apt-bounded.sh`,
`apt-bounded.test.sh` (19 rows, green, ~30 s) and the two already-converted consumers (`git-data-ownership`,
`git-data-runcmd-rehearsal`) exist on `main`. Both target apt cycles still exist exactly as the issue describes
(PU Tier B: `sh -c 'for _ in 1 2 3; do apt-get ...'`, no host timeout; cutover: attempt-count loop inside a
`timeout -k 10 480 docker run`). PR #9783 is open (not merged) and edits the PU suite at two places (see
Technical Considerations). PR #9466 is not touched. No ADR rejects the mechanism: ADR-188's 2026-10-01
amendment is the decision this extends. Healthy apt cost was measured today in the pinned image: Tier B
packages `update=8s install=12s total=20s`; cutover packages `update=9s install=46s total=55s`.

**Property list (Phase 0.6b).**

- P1: every in-container apt cycle in the two suites ends within a stated number of apt-seconds, whatever apt does.
- P2: expiry yields the shape apt exhaustion already produced (scrubbed tail, cause line, bare `FIXTURE_APT_FAILED`, rc 100), so the cutover arm stays fail-closed under `CI=true` (#8744) and Tier B stays an ADR-188 skip.
- P3: a missing lib, missing mount or unarmed state is a loud harness defect, never readable as the decline.
- P4: the assembly guard binds both new sites, so an edit that quietly drops the bound turns A10 red.
- P5: the cutover suite's exact accounting (`FLOOR=549`, `MUTANT_FLOOR=115`, `RUNTIME_ROWS=27`) is unchanged.

**Cut list.** (a) A host `timeout -k` around the PU Tier B `docker run`: buys a pull-stall bound, which is not a
property the ask names; cut, recorded as a non-goal. (b) A `GDC_APT_BUDGET_S` suite seam to simulate a decline:
a dot-prefixed temporary copy with a one-second budget buys the same proof without a seam. (c) New rows in
`apt-bounded.test.sh`: A10 is extended instead, floor stays 19. (d) Bumping the Tier B image tag `v1`: the committed image gains only an ephemeral `/tmp/apt-fixture.log` that the
boot run's `--tmpfs /tmp` masks, so cached images stay valid. (e) A real-stall reproduction through the consumers
(blackholed archive hosts): it re-proves the helper, which #9379 already measured; the consumers are proved by
forced-decline runs. (f) A dedicated population-census guard with its own matrix: the census stays, as a few lines inside A10. Existing mechanism that already buys P1-P3: the shared
helper itself (authority grepped: `apps/web-platform/infra/lib/apt-bounded.sh`).

**Institutional learnings applied.**
`2026-10-02-a-shared-apt-budget-must-be-charged-in-apt-seconds-and-a-count-census-is-not-a-binding.md` (bind each
site to its exact mount token, adjacent arm, source line and pass-through rc; a battery that mutates only the
helper cannot see consumer edits; run the real host half; prove the bound against real docker, first).
ADR-188 (decline is a skip only where it already was; #8744 keeps the cutover arm hard).
`2026-10-04-a-new-suite-is-invisible-to-repo-ratchets-until-tracked-and-my-fix-moved-the-event-behind-a-hang.md` (stage the edited suites before running
repo-global ratchets, which read `git ls-files`).

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| "extend the derived assembly row in apt-bounded.test.sh" is enough | A10's docker-site regex only recognises `docker run` after `^`, `&&`, `\|\|` or `;`. The cutover site is `timeout -k 10 480 docker run` and the PU site is `if ! docker run`; both are invisible today (`total=0`). The arm-adjacency check demands the next line start with `docker run`; the arm-line check hardcodes `"$TMP/aptstate"` (cutover uses `$T`, PU uses `$W`); the call census is `-eq 6`; the raw-apt regex does not understand `timeout -k N N apt-get` (measured: `timeout -k 5 30 apt-get install -y curl` counts 0). | Phase 1 widens the site grammar, makes the arm variable a per-suite spec field, restructures the PU site into command position, and sets the census to 8. |
| cutover: "any change needs its own assertion accounting" | The change adds and removes no `pass`/`fail`/skip row; every skip path adds `RUNTIME_ROWS` regardless of why the container declined. | Accounting is proved, not asserted: unchanged `FLOOR`/`MUTANT_FLOOR`/`RUNTIME_ROWS`, and the exact-floor check passing on a docker-present run, a forced-decline run and a forced-decline `CI=true` run (Phase 3). |
| PU "suite bound 540 s" | `run-registered-suites.sh` bounds the PU suite at 540 s and the cutover suite at 600 s; the PU Tier B build has no host timeout at all. | The helper bounds apt only. Budgets are sized from measurement (150 s / 270 s); a pull stall is a recorded non-goal. |
| PU Tier B treats any build failure as the ADR-188 skip | With the helper, rc 97 / 98 / 137 are harness defects that must not become a skip (helper contract). | Tier B skips on the marker or docker rc 125 only; anything else (97, 98, 126, 127, 137, 124) is a counted Tier B FAIL that prints the rc and the log tail. This tightens, never loosens. |

## Problem Statement / Motivation

One stalled apt fetch inside a fixture container can consume a whole suite budget and surface as a bare
`rc=124` with an empty log (the #9379 incident class). The two suites are not red today; the issue asks to
revisit only if either shows `rc=124` or a stalled apt. This closes the remaining gap before it fires, using
the helper that already encodes the measured behaviour (budget in apt-seconds, 90 s per-attempt cap).

## Proposed Solution

Each site follows the pattern in `git-data-ownership.test.sh` (host: arm, mount; container: source, call, pass
the rc through).

**Cutover-access suite** (`apps/web-platform/infra/git-data-cutover-access.test.sh`):

1. Next to the `UBUNTU_BASE` read (anchor `UBUNTU_BASE="$(sed -nE`): `APT_LIB="${DIR}/lib/apt-bounded.sh"`,
   `APT_BUDGET_S=270`, a `[ -r ]` guard that fails with `FAIL SETUP` and exit 1, `# shellcheck source=` and
   `. "$APT_LIB"`. Sizing: this arm fails closed under `CI=true` on a decline (#8744), so the budget must survive
   two capped 90 s stalls plus a healthy cycle (55 s measured on 2026-10-08) with margin, not 3.3x of healthy.
   270 s plus the container's non-apt time (the whole suite measures 87.5 s in `suite-durations.tsv`, so well under
   100 s) stays far inside the 480 s host bound. A comment next to the constant records the measured figure and date.
2. In the `drive.sh` heredoc (anchor `# Bounded apt (#8744)` through the `FIXTURE_APT_FAILED; exit 100; }` line):
   replace the loop with `. /work/apt/apt-bounded.sh || exit 97` and
   `gd_apt_install_bounded openssh-server openssh-client netcat-openbsd iproute2 git || exit $?`, each on its own line.
3. At the run site (anchor `_cname="gdc-access-`): keep `_cname=` first, then
   `gd_apt_state_arm "$T/aptstate" "$APT_BUDGET_S" || { echo "FIXTURE-FAIL: the shared apt budget could not be armed" >&2; exit 2; }`
   immediately before `timeout -k 10 480 docker run`, add `-v "$GD_APT_STATE:/work/apt"` to its options, and call
   `gd_apt_state_summary` right after `docker rm -f`. The arm failing is a harness defect before any container
   exists, so it ends the suite loudly with `exit 2` (as the ownership and rehearsal suites do) rather than
   counting a row; it cannot disturb the floor because the verdict is never reached.
4. The result classification (`FIXTURE_APT_FAILED` or rc 125 -> `_runtime_skip`, which fails under `CI=true`;
   anything else -> "driver did not complete", `SKIPPED += RUNTIME_ROWS - 1`) is not touched. Worst case is now
   270 s of apt plus non-apt time, inside the 480 s host bound.

**Provision-unit suite** (`apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`, Tier B build):

1. After the `tb_ok()` definition (not at the top of the file, see Technical Considerations):
   `APT_LIB="${SCRIPT_DIR}/lib/apt-bounded.sh"` and `APT_BUDGET_S=150` (20 s healthy measured on 2026-10-08, recorded
   in a comment; one 90 s-capped stall plus a healthy retry fits). Add `rc` to `tierb()`'s `local` line.
2. Inside the `docker image inspect` miss branch, restructure the build into command position, so the site is
   visible to A10 and the rc is captured. Guard `[ -r "$APT_LIB" ] || { ...; exit 2; }`, then `. "$APT_LIB"`, then the
   arm with the exact tail A10 pins, then (comments are stripped by A10, so a `# shellcheck disable=SC2016`
   line may sit between arm and docker line):

   ```text
   gd_apt_state_arm "$W/aptstate" "$APT_BUDGET_S" || { echo "FIXTURE-FAIL: the shared apt budget could not be armed" >&2; exit 2; }
   docker run --name "$ctr-build" -v "$GD_APT_STATE:/work/apt" "$UBUNTU_BASE" bash -c '
     export DEBIAN_FRONTEND=noninteractive
     . /work/apt/apt-bounded.sh || exit 97
     gd_apt_install_bounded --no-install-recommends systemd systemd-sysv dbus jq || exit $?
   ' > "$W/tierb-apt.log" 2>&1
   rc=$?
   gd_apt_state_summary
   ```

   The quoted script is multi-line on purpose: A10's call and source regexes are anchored to the start of a line,
   as in the ownership and rehearsal suites.
3. Classification: `rc != 0` -> `docker rm -f` the build container, then skip (`tb_skip "ADR-188 arm_skip: ..."`,
   message carries `grep -a FIXTURE_APT_CAUSE "$W/tierb-apt.log" | tail -1`) only when
   `grep -qx FIXTURE_APT_FAILED "$W/tierb-apt.log"` or `rc == 125` (docker could not create the container);
   any other rc is a Tier B FAIL in the `tb_unbootable` shape (`TB_FAIL=$((TB_FAIL + 1))`, `TIERB_RESULT="FAIL: ..."`)
   printing the rc and the last two log lines. `rc == 0` proceeds to `docker commit` unchanged. The unrelated
   `docker run -d ... --privileged` boot site stays unmounted.

**Assembly guard** (`apps/web-platform/infra/apt-bounded.test.sh`, A10, still one row, floor stays 19): see
Guard Contract. Mechanics: parse the spec with `IFS=: read -r f want_unmounted sv <<<"$spec"`; define the docker-site
grammar and the raw-apt grammar ONCE as named variables at the top of the A10 block and use them in the site count,
the adjacency awk, the raw check and the census; build the `g_ok` regex from `sv`; assert a short positive/negative
sample list against the shared docker grammar (bare, `timeout -k N N`, `if !`, versus a message string) so a grammar
edit fails with the sample that broke; make the failure message name the suite, the violated property and, for the
census, the offending file with the two remediation steps (add it to the spec list, convert it to the helper);
reword the pass text to `8 mounted sites + 2 declared unmounted`.

## Files to Edit

- `apps/web-platform/infra/git-data-cutover-access.test.sh` (setup block, `drive.sh` heredoc apt block, run site). `FLOOR`, `MUTANT_FLOOR`, `RUNTIME_ROWS` untouched.
- `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` (Tier B build block and the two definitions after `tb_ok()` only).
- `apps/web-platform/infra/apt-bounded.test.sh` (A10 and its header comment).
- `knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md` (two-line addition inside the existing 2026-10-01 amendment: two more consumers and their budgets; no new amendment section, no frontmatter change).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9395-bound-in-container-apt/tasks.md` (derived from this plan).

No suite, registration file, shard file or workflow is created or edited: presence under
`apps/web-platform/infra/` is registration, and no suite is added.

## Open Code-Review Overlap

None. Queried open `code-review` issues for all four planned paths and the helper; no body names them.

## Implementation Phases

### Phase 0: Preflight

- `git fetch origin main`; if PR #9783 has merged, rebase onto `origin/main` before touching the PU suite (anchors in this plan are content anchors, not line numbers).
- Record baselines before editing: `bash apps/web-platform/infra/apt-bounded.test.sh | tail -2` (19 passed) and `bash apps/web-platform/infra/git-data-cutover-access.test.sh | tail -3` (note the exact `N passed, 0 failed, S skipped` totals; `N + S` must equal 549).

### Phase 1: Guard first (RED)

1. Extend A10 per the Guard Contract (new consumer specs with per-suite arm variable, shared grammar variables and samples, census `-eq 8`, population check).
2. Run `bash apps/web-platform/infra/apt-bounded.test.sh`: A10 must FAIL naming both unconverted suites (`mounted=0`, `raw-apt` greater than 0). Behaviour rows A1-A19 stay green. This is the failing test that precedes the consumer edits.

### Phase 2: Convert the consumers (GREEN)

1. Cutover suite edits, then PU suite edits, exactly as in Proposed Solution.
2. `bash apps/web-platform/infra/apt-bounded.test.sh` -> `19 passed, 0 failed`; A10 text reads `8 mounted sites + 2 declared unmounted`.
3. `shellcheck` the three edited scripts (`# shellcheck source=lib/apt-bounded.sh` on both sourcing lines, `SC2016` disable above the PU docker line).

### Phase 3: Prove it against real docker (measured, not inferred)

1. Cutover suite, docker present: totals identical to the Phase 0 baseline; the log shows one `GD_APT: spent=..s of budget=270s across N apt attempt(s)` line.
2. Forced decline. `sed 's/^APT_BUDGET_S=270$/APT_BUDGET_S=1/'` into a dot-prefixed temporary copy in the same directory (not matched by the `*.test.sh` glob, untracked), run it, delete it in the same command. Local: `SKIP runtime arm (27 rows)`, exit 0, floor check passes. With `CI=true`: `FAIL runtime arm: ... CI=true`, exit non-zero, floor check still passes (`SKIPPED += RUNTIME_ROWS - 1`). This is the fail-closed proof.
3. PU suite: run once with the cached Tier B image removed (`docker rmi` of the local `soleur-pu-tierb:<tag>` image only) so the build path executes; expect `Tier B: ran: T6 T9 T10 T11 T12 T15 all PASS` and one `GD_APT:` line. Then one forced-decline run (the same one-second-budget temporary copy, with `CI=true`, image removed again): expect `SKIP (Tier B): ADR-188 arm_skip` and `tierb=skipped` (the apt decline stays a skip under CI).

### Phase 4: Mutation battery and ratchets

1. Drive the Guard Contract matrix (throwaway battery in the scratchpad, results in the PR body per the #9379 precedent): every RED row must land (assert the mutation applied) and turn A10 red; the must-PASS row must stay green.
2. `git add` the edited suites, then run the repo-global ratchets that scan them: `bash scripts/guard-vacuity-floor.test.sh` and `bash plugins/soleur/test/fixture-env-adoption.test.sh` (expected unchanged-green; they read `git ls-files`).

### Phase 5: Record

- ADR-188 two-line addition. PR body: `Closes #9395`; `Refs #8744` and `Refs #9379`. It must not close #8211, #9377 or #8609 (use `Refs` if mentioned).

## Technical Considerations

- **Collision with PR #9783.** It edits the PU suite at (1) the top, right after `SCRIPT_DIR=` (adds the `UBUNTU_BASE` read) and (2) the Tier B heading (deletes the `UBUNTU_BASE=` literal). This plan's PU hunks are the two definitions after `tb_ok()` and the build block inside `tierb()`, both well clear of those hunks (no shared context), so the merge is textual-conflict-free in either order. Both use `$UBUNTU_BASE` unchanged. Nothing here touches `git-data-ownership` or `git-data-rehearsal`, which #9783 also edits (A10 only reads their text). After #9783 lands the pin differs, so the cached Tier B image tag changes and the build path runs on the next CI run, which is the point of Phase 3.3.
- **Why Tier B uses `bash -c` not `sh -c`.** The helper is bash (`BASH_SOURCE`, `local -a`); `ubuntu:24.04` ships bash. `--no-install-recommends` is passed as a helper argument and lands before the package list in `apt-get install`.
- **Budgets.** Healthy cost measured today (20 s, 55 s). The per-attempt cap (90 s) and 3 attempts are the helper's. Cutover total worst case: 270 s apt plus non-apt time (under 100 s) against a 480 s host bound and a 600 s suite bound. PU: 150 s apt against the 540 s suite bound; Tier B runs last and a decline there is a skip, not a red leg.
- **Sourcing in the cutover suite** redefines `assert_fixture_dir` with the identical bytes the suite already carries; confirm the fixture-dir scanners accept it (the ownership suite already does the same).
- **No architectural decision** (the design was decided in ADR-188's 2026-10-01 amendment; this extends its consumer set), so the ADR/C4 gate is skipped; the ADR note is a record.
- **Non-goals.** Host-side `timeout` for the PU build `docker run` (an image-pull stall is not an apt stall); making any arm skip-eligible; changing `lib/apt-bounded.sh`.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly; a CI leg for infra test suites that no end user sees goes red or silently drops its real-systemd evidence, delaying an infra merge.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector; the helper's existing credential scrub is reused and no secret enters either suite.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, because both suites are host-side test fixtures with no user data, no production write and no credential, and neither is in the red set today.

`threshold: none, reason: the touched apps/web-platform/infra paths are CI test suites run against throwaway ubuntu containers; no production host, secret or user data is read or written.`

## Observability

```yaml
liveness_signal:
  what: the GD_APT summary line printed per suite run plus the wiring of the helper call in both suites
  cadence: per CI run of the deploy-script-tests leg
  alert_target: the CI leg result (red under CI for the cutover arm, named SKIP for Tier B)
  configured_in: apps/web-platform/infra/lib/apt-bounded.sh
error_reporting:
  destination: suite stdout and stderr in the CI job log (no Sentry surface exists for test fixtures)
  fail_loud: FIXTURE_APT_CAUSE line then the bare FIXTURE_APT_FAILED line, emitted from inside the container
failure_modes:
  - mode: apt stalls or the shared budget is spent
    detection: in-container FIXTURE_APT_CAUSE line (cause, stage, attempt, attempt_secs, spent_before, budget, rc) plus the bare marker
    alert_route: cutover arm FAILs under CI=true via _runtime_skip; Tier B prints a named SKIP carrying the cause line
  - mode: the state mount or the lib is forgotten at a site
    detection: rc 98 with "GD_APT: no armed apt budget" or rc 97, neither the decline marker
    alert_route: cutover "driver did not complete" FAIL; Tier B counted FAIL; A10 red before merge
  - mode: apt is OOM-killed or fails with a non-decline rc
    detection: rc passes through (137 etc.) with no marker
    alert_route: same hard FAIL arms as above, never a skip
logs:
  where: CI job log of the deploy-script-tests leg; locally the suite stdout
  retention: the CI provider's job-log retention
discoverability_test:
  command: grep -l gd_apt_install_bounded apps/web-platform/infra/git-data-cutover-access.test.sh apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh
  expected_output: cloud-init-inngest-provision-unit.test.sh
```

## Guard Contract

### Guard 1 — A10 derived assembly row covers every apt-bearing docker site of all four consumer suites

**Property.** In each consumer suite, every `docker run` site is either a declared unmounted site or is armed immediately before it, mounts the exact state token read-write, sources the lib, calls the helper with a pass-through rc, and no raw apt/dpkg/pip remains in command position; and no other infra suite combines a docker-run site with apt text.

**Assembly.** Four suites (`git-data-ownership`, `git-data-runcmd-rehearsal`, `git-data-cutover-access`, `cloud-init-inngest-provision-unit`) by spec `file:want_unmounted:statevar`. Chokepoints the members must flow through: (1) the docker-site grammar, defined once as a named variable (`^`, `;`, `&`, `|`, `(`, `{`, `!`, `then/do/if/exec`, optional `VAR=` words, optional `timeout [-k N] N`) and applied to the comment-stripped continuation-joined text, with positive and negative sample lines asserted against it; (2) the exact mount token; (3) the arm line, with the suite's own variable, directly preceding the site; (4) the source line; (5) the pass-through rc on every call; (6) the raw-apt grammar, defined once and widened to `timeout -k N N`; (7) the population census: the `*.test.sh` glob of the infra directory, files that hold a docker-run site (grammar 1) AND apt `update`/`install` text must all be declared consumers, and all four consumers must be seen by the glob. A site missed by (1) is invisible to (2)-(6), which is why (1) carries its own samples. Measured on today's tree: the docker-plus-apt intersection is exactly PU, cutover and rehearsal (ownership already has no apt text); the other docker suites (`ci-deploy`, `cloud-init-plugin-seed`, `zot-config-deadlines`) carry no apt text, and the apt-text suites (`cron-egress-firewall`, `soleur-host-bootstrap-observability`, `workspaces-luks-provision`, `zot-log-shipper`, `cloud-init-inngest-bootstrap`) carry no docker-run site, so there is no exemption list; `apt-bounded.test.sh` itself has no command-position docker site.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Cutover or PU: delete the mount from the docker line; or change it to `/work/apt2` or `...:/work/apt:ro` | RED |
| 2 | Cutover or PU: delete the `gd_apt_state_arm` line, or insert a statement between it and the docker line; PU arms `"$T/aptstate"` instead of `"$W/aptstate"` | RED |
| 3 | Cutover or PU: change the call tail to `\|\| exit 100`, then to `\|\| true`; delete the `. /work/apt/apt-bounded.sh \|\| exit 97` line | RED |
| 4 | PU: restore a raw `sh -c 'for ...; apt-get update ...; apt-get install ...'`; cutover: add `timeout -k 5 30 apt-get install -y curl` (the `-k` form hides from today's raw regex) | RED |
| 5 | A10's own dispatch: revert only the docker-site grammar while the consumers stay converted (`total` reads 0, and the sample list fails); drop `$CUT` then `$PU` from the spec list (census 7, then 6, not 8) | RED |
| 6 | Second member after a compliant first: add an unmounted apt-installing `docker run` to PU (declared unmounted stays 1) and a second one to cutover (declared unmounted stays 0) | RED |
| 7 | Population: in a scratch copy of the infra directory, add a fifth suite with `if ! docker run ... sh -c 'apt-get install -y curl'`; and point the glob at an empty directory (no consumer seen) | RED |
| 8 | Harness row (edit to the suite, not the guard): set one spec's `want_unmounted` to the wrong value, e.g. `$PU:0:W` | RED |
| 9 | Must-PASS, not the canonical: cutover `timeout -k 5 300 docker run` (different numbers); PU options wrapped over extra continuation lines with a comment between arm and docker line; PU packages reordered with `--no-install-recommends` last; a fifth scratch suite with docker-run sites and no apt text, and one with apt text in a string and no docker-run site | GREEN |

**Anchor.** The consumer list and the `-eq 8` census are stored values a single diff could edit together with the sites. Set identity comes from the population census, which is derived from the tree (glob), independent of the stored list: removing a consumer from the list while it still holds docker plus apt text turns A10 red, and the census also requires all four consumers to be seen by the glob so an empty or misrooted glob cannot report clean. Removing the apt text entirely satisfies the property.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "bound the in-container apt cycle in two infra test suites" [brief] | Phase 2 cutover and PU edits | mapped |
| 2 | "source the shared helper in-container (`. /work/apt/apt-bounded.sh \|\| exit 97`, then `gd_apt_install_bounded <pkgs> \|\| exit $?`)" [brief] | Proposed Solution, cutover step 2 and PU step 2 | mapped |
| 3 | "arm the shared state with `gd_apt_state_arm`, and mount it" [brief] | Proposed Solution, cutover step 3 and PU step 2 | mapped |
| 4 | "extend the derived assembly row in apt-bounded.test.sh" [brief] | Phase 1, Guard 1 | mapped |
| 5 | "its `_runtime_skip` fails under CI, its assertion floor is exact, and the fail-closed rule must be preserved, so any change needs its own assertion accounting" [brief] | Phase 3 steps 1-2, Research Reconciliation row 2 | mapped |
| 6 | "targeted test suites only (the two suites above plus apt-bounded.test.sh and any shard/registration test the change trips)" [brief] | Phase 4 step 2 (ratchets), no full battery | mapped |
| 7 | "Do NOT edit any file under .github/workflows" [brief] | Files to Edit has none | mapped |
| 8 | "The PR body may use `Closes #9395`; it must NOT close #8211, #9377 or #8609" [brief] | Phase 5 | mapped |
| 9 | "the plan must avoid colliding with its hunks and the work phase should rebase onto it if it has merged" [brief] | Phase 0, Technical Considerations | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `git-data-cutover-access.test.sh` edits | "bound the in-container apt cycle in two infra test suites" | asked |
| `cloud-init-inngest-provision-unit.test.sh` edits | "bound the in-container apt cycle in two infra test suites" | asked |
| `apt-bounded.test.sh` A10 extension | "extend the derived assembly row in apt-bounded.test.sh" | asked |
| Shared grammar variables and samples, per-suite arm variable, census 8 | asks 4 | asked |
| Population census inside A10 | — | inferred — justification: the Guard Contract gate requires assembly to be structural; a hand-listed consumer set is a snapshot, and a fifth docker-plus-apt suite would escape the bound with A10 green (two reviewers disagreed on cutting it; kept to a few lines, see decision-challenges.md) |
| Tier B skip-or-FAIL classification | asks 2 | asked |
| Phase 3 forced-decline runs | asks 5 | asked |
| ADR-188 two-line addition | — | inferred — justification: the amendment names the consumer suites and budgets; leaving it saying "both git-data suites" makes the recorded design lie about the consumer set |
| `tasks.md` | — | inferred — justification: the plan skill derives it; it is a pipeline artifact |

### Split Assessment

- Subsystems touched: 2 — apps/web-platform, knowledge-base
- Planned files: 5 | Estimated changed lines: ~150
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `bash apps/web-platform/infra/apt-bounded.test.sh` prints `=== apt-bounded: 19 passed, 0 failed ===`; A10 reports `8 mounted sites + 2 declared unmounted`.
- [ ] Before the consumer edits, A10 with the new specs FAILS naming both suites (the RED step is recorded in the PR body).
- [ ] The cutover suite with docker present: `N passed, 0 failed, S skipped` with `N + S = 549`, identical to the pre-change baseline; `FLOOR`, `MUTANT_FLOOR`, `RUNTIME_ROWS` unchanged in the diff.
- [ ] Forced-decline temporary copy of the cutover suite: locally `SKIP runtime arm (27 rows)`, exit 0; with `CI=true` a `FAIL runtime arm ... CI=true` row and non-zero exit; both pass the exact-floor check. Temporary copies are deleted.
- [ ] PU suite with the Tier B image removed first: Tier B builds through the helper and prints `ran: ... all PASS`; the forced-decline copy under `CI=true` prints `SKIP (Tier B): ADR-188 arm_skip` with `tierb=skipped`; a non-decline build failure (rc 97/98/126/127/137) is a counted FAIL that prints the rc and log tail.
- [ ] No raw `apt-get`/`apt`/`dpkg` remains in command position in either edited suite; both container scripts source the lib on its own `|| exit 97` statement and pass the rc through (`|| exit $?`).
- [ ] Mutation matrix of both guards: every RED row of Guard 1 lands and turns A10 red, the must-PASS row stays green; results in the PR body.
- [ ] `shellcheck` is clean on the three edited scripts; `scripts/guard-vacuity-floor.test.sh` and `plugins/soleur/test/fixture-env-adoption.test.sh` pass with the edited suites staged.
- [ ] `git diff --name-only origin/main...HEAD` lists no path under `.github/workflows`, no registration or shard file, no `lib/apt-bounded.sh`, and nothing outside the four planned files plus the pipeline's own plan, `tasks.md` and session-state artifacts; the main checkout's `.mcp.json` is untouched.
- [ ] PR body: `Closes #9395`, `Refs #8744`, `Refs #9379`; does not close #8211, #9377 or #8609.

## Test Scenarios

- Given the new consumer specs and unconverted suites, when A10 runs, then it fails (RED) naming `git-data-cutover-access.test.sh` and `cloud-init-inngest-provision-unit.test.sh`.
- Given a healthy archive, when the cutover runtime arm runs, then totals match the baseline and one `GD_APT:` line reports spent under budget.
- Given apt that cannot finish inside the budget, when the cutover arm runs locally, then it prints the counted SKIP; under `CI=true` it fails, and the floor holds in both.
- Given apt that cannot finish inside the budget, when Tier B builds its image, then it prints the named ADR-188 SKIP in both environments; given rc 97/98/137, then Tier B counts a FAIL.
- Given a fifth infra suite with a docker-run site and raw apt, when A10 runs, then it fails naming that file and the two remediation steps.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: CI test-suite hardening in an infrastructure test directory, no user-facing surface, no data or contractual change.

## Dependencies & Risks

- **A10 regex fragility.** Widening the grammar could make a previously invisible site in the two older consumers appear. Measured: the widened regex counts 1 (ownership) and 6 (rehearsal) sites, equal to today's; if the work phase sees otherwise, that is a real finding to fix, not an exemption to add.
- **Budget too tight on a slow day.** Cutover then fails closed under CI (by design, #8744) with an attributable cause line; Tier B skips with the cause. Budgets (270 s / 150 s) cover two capped 90 s stalls plus a healthy cycle for cutover (55 s measured) and one stall plus a healthy retry for Tier B (20 s measured); both are tunables, not contracts.
- **Tier B tightening.** A non-decline build failure now fails instead of skipping. Intended (helper contract: rc 97/98/137 must not read as the decline); the FAIL prints the rc and log tail. How often today's Tier B skips for non-apt reasons was not measured; the PR body says so.
- **Docker daemon needed for Phase 3.** Present on the planning machine; if absent in the work environment, Phase 3 results come from CI and the PR says so.
- **#9783 merge order.** No textual conflict either way; rebase if it lands first.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase 4.6; this plan fills it (`none`, with the sensitive-path scope-out line because `apps/web-platform/infra/` matches the preflight regex).
- The mutation matrices are throwaway batteries run in the scratchpad against copies; do not commit them (#9379 precedent).
- The `discoverability_test` grep returns nothing before Phase 2 (it looks for the helper call the plan adds); run it after the conversion, where it must print the PU suite path.
- Do not run the full battery; targeted suites only. Do not touch `.github/workflows`, PR #9466 or its worktree.

## References & Research

- `apps/web-platform/infra/lib/apt-bounded.sh` (helper contract), `git-data-ownership.test.sh` (reference consumer: setup block, `drive.sh` call, arm and mount)
- `knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md` (2026-10-01 amendment)
- `knowledge-base/project/learnings/2026-10-02-a-shared-apt-budget-must-be-charged-in-apt-seconds-and-a-count-census-is-not-a-binding.md`
- Related: #9379 (helper), #8744 (cutover arm stays fail-closed), #9383, PR #9783 (adjacent PU hunks), issue #9395
