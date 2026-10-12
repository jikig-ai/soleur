---
title: "sandbox masked-/proc suite: assert parity with the real docker run tuples and the vendored argv tail"
type: chore
date: 2026-10-12
slug: test-sandbox-masked-proc-suite-parity
branch: feat-one-shot-10065-sandbox-proc-suite-parity
issue: 10065
closes: 10065
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# sandbox masked-/proc suite: assert parity with the real docker run tuples and the vendored argv tail

## Overview

The production-posture docker suite for the sandbox /proc mask (`apps/web-platform/infra/sandbox-masked-proc-docker.test.sh`,
merged in #10043, Ref #9860) proves the shipped bwrap shim works under docker's default masked /proc. It proves that in a
container whose run options and vendor argv tail it hand-writes itself, so it certifies the suite's own copy of production,
not production. This plan makes the suite derive both from the real sources and adds the arms the review of #10043 found
missing (the five bullets of #10065):

1. The three app-container `docker run` tuples (canary and prod in `ci-deploy.sh`, first boot in `cloud-init.yml`) are parsed
   closed-world. Any option outside the declared set (`--cap-add`, `--pid=host`, `--security-opt systempaths=unconfined`, an
   `-e PATH=...`, a splat) turns the suite red, and the suite's own container is started from the parsed posture.
2. The vendor argv tail the isolation arm replays is taken from the committed canary fixture, and the fixture is pinned to the
   vendored builder two independent ways that do not run through the `sdk-bump-verified` trailer: the builder's literal pushes in
   both vendored platform binaries, and the live spawn the SDK hands the shim.
3. The two spawn paths that bypass the PATH shim (outer wrap `BWRAP_PATH`, C4 render `BWRAP_BIN`, both `/usr/bin/bwrap`) run
   under the masks in the suite, and their binary constants and spawn-site set are pinned.
4. A shim that covers the vendor bind (appends `--tmpfs /proc`) instead of dropping it fails the isolation arm.
5. The suite's base image follows the Dockerfile stage graph (runner -> cli-tools) instead of the first `FROM`, and PATH order
   (`/usr/local/bin` before `/usr/bin`) is asserted statically and in the running container.

No production behavior changes: the diff adds tests, one fixture, one helper, and registrations. Nothing here touches a docker
flag, shim logic, the Dockerfile, or a deploy path (two prose corrections: the shim header comment and ADR-075).

## Research Reconciliation — Spec vs. Codebase

Verified against `origin/main` (b102edd4c6) on 2026-10-12.

| Issue / brief claim | Reality on main | Plan response |
|---|---|---|
| "the suite hard-codes its own docker tuple" | True: `start_container` (suite L164-170) writes `--init -u 1001 --tmpfs ... --security-opt apparmor=... --security-opt seccomp=...` by hand; `-u 1001` is a literal. | Derive from the parsed prod tuple and from the Dockerfile `useradd --uid` (Phase 3). |
| "an appended --cap-add, --pid=host, or systempaths=unconfined stays green" | True for the suite. Elsewhere only spelling-specific greps exist: `sandbox-canary-soak.test.sh` L126-130 matches the literal `--cap-add SYS_ADMIN`; `ci-deploy.test.sh` L2731-2773 asserts only `apparmor=soleur-bwrap` on the mocked `DOCKER_RUN_ARGS`. `--cap-add=SYS_ADMIN`, `--cap-add NET_ADMIN`, `--pid=host` all pass both. | Closed-world grammar, not a deny list (Phase 2). The two existing greps stay as-is. |
| "first-boot tuple" is one of three | True. cloud-init L787 differs from ci-deploy: no `--init`, no `--memory`, adds `-e SOLEUR_EGRESS_REAPER=1` and `-v /var/lib/soleur/egress-tokens`. | Compare the security posture projection across the three; benign runtime options (memory, init, log driver, per-tuple env and volume sets) are classified, not equated. |
| "the vendored builder's live argv tail; the fixture is a projection" | True. `sandbox-canary-argv.json` is the normalized capture (`--dev /dev --unshare-pid --unshare-user --cap-drop ALL --cap-add CAP_SETFCAP --bind /proc /proc` tail); suite L244 hand-builds `--tmpfs /proc --dev /dev --bind /proc /proc`. The builder is plain minified JS in both `claude-agent-sdk-linux-x64/claude` and `claude-code-linux-x64/claude` (0.3.284 / the pinned CLI): `...push("--dev","/dev"),X.push("--unshare-pid");...X.push("--unshare-user",...caps(...)),!flag)X.push("--proc","/proc");else X.push("--bind","/proc","/proc")`; a 243 MB scan for it takes about 1 s. | Static literal-list extraction from both binaries plus live-spawn tail equality (Phase 6). Creds-free; the existing live harness `sandbox-proc-mask-runtime.test.ts` already records the spawn through a PATH wrapper with a scripted API stub. |
| "the sdk-bump gate has a trailer bypass" | True and wider than the word suggests: `sdk-bump-sandbox-gate.sh` accepts `grep -qiE "\bsdk-bump-verified\b"` anywhere in any commit body between the base and HEAD (not a parsed trailer), and the capture section only runs when `SANDBOX_CANARY_GATE_ENABLED=1`, which the always-on `lockfile-sync` job leaves off. | Do not change the ack parser. Add checks that do not read the ack at all (Phase 6). Recorded as a decision under Non-Goals. |
| "outer-wrap and C4-render spawn paths" | Both spawn `/usr/bin/bwrap` by absolute path and bypass the shim (`agent-outer-wrap.ts` `BWRAP_PATH`, `c4-render.ts` `BWRAP_BIN`). The outer fixture carries `--bind /proc /proc` with zero `--unshare-*`; the C4 argv has no /proc token (so it is mask-safe today, and a `--proc /proc` added to it would EPERM under the masks exactly like #9860). Neither is exercised under masks by the suite. `agent-outer-wrap.test.ts` pins the outer fixture to the builder; nothing pins a C4 argv fixture. | New C4 argv fixture plus pin test, docker replay of both under the masks (Phase 5, shape decided by measurement M1/M2). |
| "a shim that masks over instead of dropping passes the isolation arm" | Consistent with the code: the isolation arm observes only "sibling ABSENT" and "0 pid dirs", both true under a tmpfs cover. Whether any behavioral probe separates cover from drop is unmeasured (the recursive root bind may already carry a procfs under the vendor tmpfs). | Phase 0 measurement M3 decides; the argv-level discriminator (recorder as `SOLEUR_BWRAP_REAL`) is the guaranteed arm. |
| "the cli-tools stage base image, and PATH order" | Partly stale. `test/c4-likec4-version-pin.test.ts` L266-298 already pins `cli-tools` and `deps` to the same pinned digest and `runner FROM cli-tools`. What remains: the suite takes BASE from the first `FROM node:22-slim@sha256` line (the `deps` stage), not from the lineage `runner` ships; PATH order is asserted nowhere (the Dockerfile has no `ENV PATH`, so the order is whatever the base image sets). | Resolve BASE through the stage graph; assert PATH statically (no reordering `ENV PATH`) and live (`command -v bwrap` == `/usr/local/bin/bwrap` for uid 1001). |

## Research Insights

**Premise Validation.** Issue #10065 is open; its parent PR #10043 and the fix PRs #10039 and #9938 are merged. No cited blocker is
closed or stale. Every cited file exists on main: the suite, `ci-deploy.sh`, `cloud-init.yml`, `agent-outer-wrap-argv.json`,
`c4-render.ts` (`BWRAP_BIN` at the exported constant), `sandbox-canary-argv.json`, `sdk-bump-sandbox-gate.sh`. ADR corpus: ADR-075 (L196,
L332) records `systempaths=unconfined` as the rejected posture ("Why not systempaths=unconfined"); this plan turns that
rejection into a mechanical check and does not re-open it. No ADR rejects tuple-parity checking.

**Property List** (what the issue buys, one observable sentence each):

- P1. A posture-changing option appended to any of the three app-container tuples turns CI red.
- P2. The suite's container posture is derived from the real tuple, not copied.
- P3. The tail the isolation arm replays is the vendor's actual tail, checked without reading the ack trailer.
- P4. The outer-wrap and C4-render spawns run under the masks in CI, and their binaries and spawn-site set are pinned.
- P5. A shim that covers rather than drops the vendor bind fails the isolation arm.
- P6. The suite's base image is the shipped lineage and PATH puts `/usr/local/bin` before `/usr/bin`.

**Cut List** (mechanisms the ask names that an existing mechanism already covers, or that buy no property):

- Tightening the `sdk-bump-verified` ack into a parsed trailer: buys nothing P3 needs once the live-tail checks do not read it, and
  trailer parsing has its own learned traps (`2026-09-26-trailer-key-must-sit-in-the-last-contiguous-trailer-block.md`). Cut.
- Re-asserting `cli-tools FROM == deps FROM` in the suite: already pinned by `c4-likec4-version-pin.test.ts`. Cut; the suite only
  derives BASE through the same graph.
- Capturing the live argv through the creds-gated `--capture` path: the existing scripted-stub harness records the same spawn with
  no credential. Cut.
- Mocking `docker` to trace `DOCKER_RUN_ARGS` through `ci-deploy.sh` (the `ci-deploy.test.sh` mechanism): heavier than parsing the
  tuple text, and the text parse fails closed on any token it cannot classify (splats included). Cut.

**Institutional learnings applied** (paths under `knowledge-base/project/learnings/`):

- `2026-10-09-a-guard-keyed-on-option-spellings-was-bypassed-by-the-spellings-i-did-not-list.md`: closed-world, not deny list;
  both `--opt value` and `--opt=value`, `--security-opt=systempaths=...`.
- `2026-10-11-docker-consumes-systempaths-client-side-so-an-absent-securityopt-entry-proves-nothing.md`: never assert systempaths via
  `docker inspect` SecurityOpt; the runtime control arm (masks really present) is the attribution, `HostConfig.MaskedPaths` the
  inspect-side proof.
- `2026-10-08-a-pin-copied-into-three-suites-had-one-detector-and-two-silent-copies.md`: derive, never copy.
- `2026-10-12-a-regex-guard-over-shell-text-cannot-be-closed-pin-the-artifact-and-the-confound-was-my-own-push.md`: after two bypass
  rounds a text guard stops converging; hence closed-world tokenization (`shlex`) with an unknown-token failure instead of regex
  rules, plus the artifact-level runtime arm.
- `2026-10-11-a-control-that-fails-early-proves-nothing-about-the-checks-after-it.md` and
  `2026-10-10-my-must-pass-arm-passed-wherever-its-mutation-landed-and-nothing-noticed-the-arms-could-be-deleted.md`: one control per
  check, attributed by its own diagnostic; every arm needs an arm-deletion row.
- `2026-10-11-a-fake-that-ignores-its-selectors-lets-every-selector-mutation-pass.md`: the recorder `SOLEUR_BWRAP_REAL` must refuse
  argv it does not model.
- `security-issues/bwrap-masked-proc-drop-not-cover-shim-20261011.md`: drop-not-cover is the shim's defining property; verify on the
  production binary and posture (bwrap 0.8.0, masks), never the dev bwrap.
- `2026-10-04-a-new-suite-is-invisible-to-repo-ratchets-until-tracked-and-my-fix-moved-the-event-behind-a-hang.md`: `git add` a new
  test file before running the orphan, guard-vacuity or fixture-relative ratchets.
- `2026-10-11-my-tests-pinned-the-helper-and-the-regex-ran-on-the-event-loop-i-never-timed.md` (the brief's pointer): bound every
  regex input; here the tuple parser caps a logical line before `shlex`, and the binary scan extracts a bounded window before any
  regex.

**Plan-time census of the protected surface** (a guard must not be specified against a surface it would already fail). A throwaway
`shlex` prototype run over both files on 2026-10-12 found exactly 4 command-position `docker run` sites: `ci-deploy.sh` L2787 (the cosign
verify, written `if "${verify_env[@]}" docker run --rm ...`, so the census must match `docker run` after a wrapper expansion, not only at
line start), L4259 (canary), L4604 (prod, `if docker run ... "$VERIFIED_REF"; then`), and `cloud-init.yml` L787 (first boot, image
`"$(cat /run/soleur-image-ref)"`, which `shlex` keeps as one token). Option inventory per app tuple: `-d --name --log-driver --restart
[--memory --memory-swap] [--init] --security-opt x2 --tmpfs --env-file --add-host -e (4-5 names) -v (2-3 specs) -p (1-2)`. The grammar in
Phase 2 admits all of these and nothing else, so it reports zero violations on the unmodified tree (a guard that failed on day one would
need grandfathering; this one does not). The prototype lives in the scratchpad only and is not part of the diff.

**Registration ratchets a new infra suite hits** (from the brief and verified in tree): `run-registered-suites.sh` L391 `PRIVILEGED_WHY`
and `run-registered-suites.test.sh` T2e (only for a PRIVILEGED suite; the new unit suite is unprivileged and the existing docker suite
is already listed), `apt-bounded.test.sh` L26/L291 `SPECS` and its census (`CENS_DOCK_RE` + `CENS_APT_RE`: any infra `*.test.sh` holding
a docker verb and apt text must be a declared consumer or an EXEMPT line), `scripts/guard-vacuity-floor.test.sh` L912 `PROMOTED_FILES`
(floor literal adjacent to its use), `plugins/soleur/test/fixture-relative-assert.test.sh` (operands provably absolute or guarded),
`.claude/hooks/grep-q-pipe-guard.test.sh` (`FILES_8855` plus its pin count for any file sourcing `lib/mutation-scorer.sh`;
`grep -q` over here-strings, never a pipe), `lint-orphan-test-suites.sh`. `BASELINE_DECLARED_PROBES` (preflight discoverability) is
counted per plan that declares `credentials_required`; this plan declares none, so no bump.

## Open Code-Review Overlap

None. (Queried open `code-review` issues against every planned path: the suite, `ci-deploy.sh`, `cloud-init.yml`, the shim, the
Dockerfile, `c4-render.ts`, the canary fixture, `sdk-bump-sandbox-gate.sh`, `guard-vacuity-floor.test.sh`, `apt-bounded.test.sh`.)

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly (no runtime path changes). A false-green suite lets a drifted
  production tuple (an added capability, host pid namespace, unmasked /proc) or a covering shim ship while CI reports the sandbox
  isolation guard as healthy; a false-red suite blocks merges on the infra and webplat checks until fixed.
- **If this leaks, the user's workflow data and credentials are exposed via:** cross-tenant `/proc/<pid>/environ` reads. Tenants share
  uid 1001 in one container and the /proc mask is the barrier (#9723); a guard that stops detecting its regression is the exposure vector.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** carried forward from the #9860 brainstorm and the 2026-10-11 plans for the same boundary: one
  tenant reading another's environment is a single-user incident, and the guard is what keeps that boundary honest; this diff adds
  guards only, so it does not raise the tier.

CPO sign-off carries from the 2026-10-11 brainstorm (`knowledge-base/project/brainstorms/2026-10-11-sandbox-proc-shim-h6-brainstorm.md`,
CPO+CLO+CTO) for the same boundary; `soleur:engineering:review:user-impact-reviewer` runs at review time against this section.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed (carry-forward)
**Assessment:** CI guard and test infrastructure on an existing security boundary; no product surface, no data model, no new
infrastructure resource, no vendor. The CTO lens was applied at brainstorm time for this boundary (launcher, egress and credential
blocking work is out of scope here: no launcher, egress or credential path is edited). No Product/UX gate (no UI-surface file in the
file lists). No legal or compliance surface (no personal data, no schema, no auth path).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "canary/prod/first-boot docker run tuples in ci-deploy.sh and cloud-init.yml: an appended --cap-add, --pid=host, or systempaths=unconfined must turn the suite red" [brief] | Phase 2 (parser + unit battery), Phase 3 (suite arms, derived container) | mapped |
| 2 | "the vendored builder's live argv tail (the fixture is a projection; the sdk-bump gate has a trailer bypass)" [brief] | Phase 4 (fixture-derived tail), Phase 6 (builder literals + live spawn) | mapped |
| 3 | "the outer-wrap and C4-render spawn paths (agent-outer-wrap-argv.json, c4-render.ts BWRAP_BIN)" [brief] | Phase 5 | mapped |
| 4 | "a shim that masks over instead of dropping the vendor bind (--tmpfs /proc appended) must fail the isolation arm" [brief] | Phase 4 (`shim-cover` seam, recorder arm) | mapped |
| 5 | "the cli-tools stage base image, and PATH order (/usr/local/bin before /usr/bin)" [brief] | Phase 3 (base lineage, PATH arms) | mapped |
| 6 | "a new infra suite needs its registrations (PRIVILEGED_WHY, T2e, apt-bounded SPECS, guard-vacuity PROMOTED_FILES, fixture-relative guard, grep -q here-strings) or CI reds one ratchet at a time" [brief] | Phase 7 | mapped |
| 7 | "Run tests and mutation batteries in an allocated sandbox (scripts/soleur-sandbox.sh new/run-isolated/rm; the sandbox has no .git)" [brief] | Phase 8 | mapped |
| 8 | "Do NOT run the full local battery (CI owns it)" [brief] | Phase 8 (targeted runs only) | mapped |
| 9 | "Out of scope: release provenance work, the flaky cron-egress-ghcr-probe clock-boundary rows, wiring lint-shell-capture-exit/grep-q-pipe-guard into pre-commit" [brief] | Non-Goals | mapped |
| 10 | "Any production write needs explicit operator go-ahead (gh pr merge, workflow_dispatch of apply-deploy-pipeline-fix.yml, re-running the release deploy job, any Doppler write)" [brief] | Phase 9 (ship constraints; this diff performs none) | mapped |
| 11 | "cap line length before any regex on tenant text; pass a null error plus message (never a real Error) to the Sentry mirror" [brief] | — | descoped — justification: no Sentry mirror site and no tenant text in this diff; the line-cap lesson is applied to the tuple parser and the binary window anyway (Phase 2, Phase 6) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `infra/lib/docker-run-tuple.py` | "an appended --cap-add, --pid=host, or systempaths=unconfined must turn the suite red" | asked |
| `infra/docker-run-tuple.test.sh` (unit + mutation battery) | "Run tests and mutation batteries in an allocated sandbox" | asked |
| suite edits (derived container, arms) | "hard-codes its own docker tuple and replays a captured argv fixture" | asked |
| `test/sandbox-vendored-argv-tail.test.ts` | "the vendored builder's live argv tail" | asked |
| `test/sandbox-proc-mask-runtime.test.ts` edit | "the vendored builder's live argv tail" | asked |
| `infra/c4-render-sandbox-argv.json` + `test/c4-render-argv-fixture.test.ts` | "the outer-wrap and C4-render spawn paths" | asked |
| `recorder` arm and `shim-cover` seam | "a shim that masks over instead of dropping the vendor bind (--tmpfs /proc appended) must fail the isolation arm" | asked |
| registrations (`PROMOTED_FILES`, `FILES_8855`, `SPECS`, floor literal) | "or CI reds one ratchet at a time" | asked |
| `.github/workflows/infra-validation.yml` timeout and comment | "a sudo bash step in infra-validation.yml" is where the suite runs; the new arms add wall time | inferred — justification: the step's `timeout-minutes: 10` is the only bound on the suite and the added arms must stay inside it |
| `test/docker-run-tuple-posture.test.ts` (required-lane wrapper) | "an appended --cap-add, --pid=host, or systempaths=unconfined must turn the suite red" | inferred — justification: the infra-validation jobs are advisory (not in the required check set), so without a wrapper in the required `test` aggregator the asked-for red does not block a merge |
| `measurements.md` (Phase 0) | "re-check the plan's premise against origin/main before work" | asked |

### Split Assessment

- Subsystems touched: 4 — apps/web-platform, scripts, .claude, knowledge-base (plus one .github workflow edit)
- Planned files: 8 create, 10 edit | Estimated changed lines: ~1000
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the `scripts/` and `.claude/` edits are one-line registrations that the new suites force (the brief's
  "CI reds one ratchet at a time"), and the arms share one suite file, one CI step and one registration set, so a split would pay the
  ratchet cycle twice (the architecture panel disputed this; recorded in `decision-challenges.md`). Natural seam: Phase 2-3 (tuple
  parity, deterministic, independent of every measurement, ~450 lines) versus Phases 4-6 (isolation, spawn paths, live tail, shaped by
  Phase 0). Commit in that order so either half is shippable alone, and ship Phases 2-3 alone if M3 or M1/M2 stop Phases 4-5.

## Architecture Decision (ADR/C4)

The guards themselves decide nothing: a test-only parity guard on an existing boundary. One correction is EXPECTED to be in scope
(Deepen-Plan Findings D1, from the security review): the shim header (L53-56) and ADR-075 (L196, L332) say dropping the tail bind
"removes the mount object entirely" and that a cover leaves a live procfs object; with the recursive `--ro-bind / /` in the vendor argv the
container's procfs sits beneath the tmpfs after a drop as well, so the rationale is wrong for the main vendor argv (it holds for the
hook-sandbox builder, which has no root bind). This PR therefore corrects ADR-075 (a `## Decision` clarification plus an Alternatives
Considered row recording that cover and drop differ only for a process holding CAP_SYS_ADMIN, which production never grants) and the shim
header comment (comment lines only, see AC15), and Phase 0 M3 confirms the mount stack with `mountinfo`. If M3 contradicts D1, only the
corrections change, not the guards. ADR-122 (boot-time delivery of the seccomp and AppArmor profiles) is the record
for the host paths the tuples reference. C4 completeness check (all three of
`model.c4`, `views.c4`, `spec.c4` considered): external actors (tenant agent processes, the Agent SDK vendor binary), external
systems (none added), containers (the web-platform container already modeled; no new store or edge), access relationships (unchanged);
no derived cardinality in edge prose moves, since the diff adds no workflow, monitor or heartbeat. `plugins/soleur/test/c4-count-parity.test.sh`
is run once at Phase 8 to back the "no C4 impact" statement.

## Guard Contract

### Guard 1 — app-container docker run tuple posture (closed world)

**Property.** Every `docker run` that starts the web-platform app container on a host (canary, prod, first boot) carries the declared
security posture and no option, environment name, volume or port outside the declared closed set.

**Assembly.** Members: the canary tuple and prod tuple in `ci-deploy.sh`, the first-boot tuple in `cloud-init.yml`. The chokepoint is
`docker-run-tuple.py`, which (a) censuses every command-position `docker run` in both files and classifies each as an app tuple
(`--name soleur-web-platform*`) or an explicitly named exempt site (the cosign verify `--rm` run), failing `UNCLASSIFIED_DOCKER_RUN`
on anything else, (b) tokenizes with `shlex` after joining continuations and stripping the statement's `if`/`; then`, (c) classifies every token
through one arity table into POSTURE, BENIGN-with-allowed-values, or unknown (unknown fails with its spelling, so `--opt value`,
`--opt=value`, `-e PATH=...`, `"${SPLAT[@]}"` and `$(...)` in option position all fail), and (d) asserts the posture projection
equal across the three and equal to what the suite starts its own container with. Count floor: exactly 3 app tuples, not "at least
one"; a repo-wide `git grep` for `--name soleur-web-platform` finds no start site outside the three. Residuals stated, not claimed closed:
`--env-file` content and the `NODE_OPTIONS` value.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | append `--cap-add NET_ADMIN` to the prod tuple (space form) | RED `UNKNOWN_OPTION --cap-add` |
| 2 | append `--cap-add=SYS_ADMIN` to the first-boot tuple only, after canary and prod stay compliant (equals form, second member after a compliant first) | RED `UNKNOWN_OPTION --cap-add` naming `cloud-init.yml` |
| 3 | append `--pid=host` to the canary tuple, then `--pid host` variant | RED both |
| 4 | append `--security-opt systempaths=unconfined` to prod, then `--security-opt=systempaths=unconfined` | RED `POSTURE_VALUE` both |
| 5 | rename `--name soleur-web-platform` in the prod tuple so the census sees 2 app tuples (the guard's own dispatch: a parser finding fewer tuples must not exit 0) | RED `TUPLE_COUNT want 3 got 2` |
| 6 | add a fourth `docker run ... soleur-web-platform ...` site to `ci-deploy.sh` (assembly drift: a new start site) | RED `UNCLASSIFIED_DOCKER_RUN` or `TUPLE_COUNT` |
| 7 | append `-e PATH=/usr/bin:/usr/local/bin` to canary (PATH-order lever), then `-e LD_PRELOAD=/x` | RED `ENV_NAME` both |
| 8 | splat or substitution in option position: `"${EXTRA_DOCKER_OPTS[@]}"` before the image | RED `UNPARSEABLE_OPTION` |
| 9 | delete `--security-opt apparmor=soleur-bwrap` from one tuple | RED `POSTURE_DIVERGENCE` |
| 10 | `--security-opt seccomp=unconfined`, `--privileged`, `--device`, `--userns host`, `--ipc host`, `--network host`, `--read-only`, `--sysctl` (one row per option, driven by a loop over the closed-world's complement sample) | RED each |
| 11 | tuple text moved into a heredoc or wrapped in a function so the census sees zero sites | RED `TUPLE_COUNT want 3 got 0` |

**Harness rows.** H1 (an edit to the suite, not the guard, that must drive it RED): the battery is re-run against a copy of the helper
whose unknown-option arm is replaced by allow-all (`sed` into `$WORK`, never a seam in the shipped helper). Against that copy rows
1-4 and 7-10 must be reported NOT KILLED and the battery must exit 1; against the real helper the same rows are KILLED. A battery that
stays green against the allow-all copy is itself vacuous. H2 (ledger): `passes + fails` equals
the rows executed and the row count is pinned as a literal beside its use. Must-PASS rows that are NOT the canonical files: P1 the
same posture with options reordered and `--restart=unless-stopped` in equals spelling; P2 a different `--memory` value; P3 an extra
benign comment block between continuation lines; P4 CRLF-free but tab-indented continuation (cloud-init indentation). A guard that
rejects everything fails P1-P3 (P3 is the real prod shape `if docker run ... "$VERIFIED_REF"; then`).

**Anchor.** The closed set lives in the helper and the tuples live in the files it parses; one diff can edit both, so the parity
check proves consistency, not integrity. What outside the commit also has to move for a weakening to pass: for the one option the
repo has already rejected (`systempaths=unconfined`) the suite's runtime control arm, which fails when docker's masks are absent,
independent of any allowlist edit; for the rest, review of a file whose only job is this set, plus the posture-projection digest the
unit battery pins as a literal (so a posture change is a visible two-line diff in a second file).

### Guard 2 — isolation arm discriminates drop from cover, on the vendor's actual tail

**Property.** The argv the real bwrap receives from the shim carries no argv-requested procfs mount at /proc (dropped, not covered) and
its last /proc mount is the vendor `--tmpfs /proc`, for the vendor's actual setup tail, and that tail is what the suite replays. (Not
"no procfs mount object exists": the recursive `--ro-bind / /` carries the container's procfs beneath the tmpfs either way, see
Deepen-Plan Findings D1. The operative barrier against reaching it is the vendor's `--cap-drop ALL`, pinned by Guard 2 row 11.)

**Assembly.** Three tail sources that must agree, chained by equality: (1) the builder literal pushes in BOTH vendored binaries
(`@anthropic-ai/claude-agent-sdk-linux-x64`, `@anthropic-ai/claude-code-linux-x64`; the agent runner and the cron CLI path), (2) the
live spawn argv the SDK hands the PATH shim (`sandbox-proc-mask-runtime.test.ts`), (3) the committed fixture
`sandbox-canary-argv.json`, from which the suite derives its isolation argv with `jq`. Two chokepoints for the drop property: the
recorder (`SOLEUR_BWRAP_REAL` stand-in inside the container, the argv the real bwrap would have received) and the behavioral arms
(sibling absent, zero pid dirs, real-bwrap discrimination).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `MUTATE=shim-cover`: shim wrapper appends `--tmpfs /proc` and keeps the vendor `--bind /proc /proc` | RED recorder arm (`DROP_FAILED`); behavioral arms stay green, which is why the recorder exists |
| 2 | fixture tail edited to add `--tmpfs /proc` after the bind | RED vitest `TAIL_DRIFT` (live vs fixture) |
| 3 | synthetic binary buffer with an extra `.push("--tmpfs","/proc")` after the bind push | RED extractor row `TAIL_LITERALS` |
| 4 | the same synthetic edit applied to the second binary only (claude-code) after the SDK binary stays compliant | RED naming the second binary |
| 5 | anchor absent or present twice in a buffer (builder refactor, minifier change) | RED `TAIL_ANCHOR found 0` and `found 2`, never "0 checked, exit 0" |
| 6 | fixture lacks `--bind /proc /proc` or `--tmpfs /proc` (the suite's own derivation dispatch) | RED `FIXTURE_TAIL` before any docker call |
| 7 | `MUTATE=shim-bypass` (existing) | RED discrimination |
| 8 | recorder arm deleted from the suite (arm-deletion row: the ledger floor catches it) | RED floor |
| 11 | the cap segment loses `--cap-drop ALL` (literal count per binary drops to 0) or gains a `--cap-add` other than `CAP_SETFCAP` (synthetic buffer, and a live-spawn tail with an added `--cap-add CAP_SYS_ADMIN`) | RED `CAP_BARRIER` |
| 9 | `CI=1` and the vendored platform binary path resolves to nothing (the conditional-skip arm: a skipped test exits 0, so the CI-side assertion that the rows RAN is part of the guard) | RED `BINARY_MISSING`, never a skip |
| 10 | a synthetic buffer carrying a second `"--proc","/proc"` site (a new builder or a refactor) on a binary pinned at 1 site | RED `PROC_SITE_COUNT want 1 got 2`, naming the inspect-and-update steps |

**Harness rows.** Must-PASS non-canonical: a shim run whose vendor argv carries unrelated extra mount tokens
(`--ro-bind /etc/hostname /etc/hostname`) before the tail, and a vendor stream with no `--tmpfs /proc` of its own (the shim appends
one): both must pass the recorder arm. The recorder refuses argv it does not model (unknown option arity aborts the arm) so a
selector-ignoring fake cannot make rows 1 and 7 pass. The property is order-free by construction (no argv-requested procfs mount remains, so no ordering of the argv can add one);
row 1 is the cover-after case and the matrix therefore carries no reorder row.

**Anchor.** The vendored binary pinned by `package-lock.json` integrity: a fixture or test edit cannot change what the binary pushes,
so rows 2-5 are independent of the PR diff and of the ack trailer. The recorder compares against the shim's own contract, which a
single PR could edit together with the shim; the behavioral discrimination arm (real bwrap leaks, shim does not) is the second leg.

### Guard 3 — spawn paths that bypass the shim

**Property.** Every production bwrap spawn that does not go through the PATH shim runs `/usr/bin/bwrap` by absolute path and starts
under docker's default masks without a procfs-mount refusal.

**Assembly.** Spawn sites: `agent-outer-wrap.ts` (`BWRAP_PATH`, a `spawn` and a `spawnSync` of different shapes), `c4-render.ts`
(`BWRAP_BIN`, nested in a bash launch argv) and `scripts/sandbox-canary.mjs` (absolute and bare `bwrap`), found by a LITERAL census over
`apps/web-platform/server/**` and `scripts/**` for the constants and the `/usr/bin/bwrap` literal (not a "first spawn argument" scan,
which would see one site or pass vacuously); the expected list names each file. Argv sources: `buildOuterWrapArgv` (fixture `agent-outer-wrap-argv.json`, already pinned by
`agent-outer-wrap.test.ts`) and `buildLikeC4SandboxArgv` (new fixture `c4-render-sandbox-argv.json`, pinned by a new test).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | add `--proc /proc` to `buildLikeC4SandboxArgv` | RED fixture pin (vitest) and, with the fixture regenerated, RED docker replay `mount proc` |
| 2 | `BWRAP_BIN = "bwrap"` (PATH-resolved, would go through the shim) | RED constant pin and literal census |
| 3 | third file in `server/` spawning bwrap by a new constant or the literal | RED literal census |
| 4 | outer fixture gains `--proc /proc` | RED outer-wrap docker replay (shape per M1) |
| 5 | scan finds zero spawn sites (renamed export, moved file) | RED `SPAWN_SITES want 2 got 0` |

**Harness rows.** Must-PASS: the committed fixtures regenerated by the pin test's documented command produce byte-identical files;
a C4 argv with an extra `--ro-bind` for a hosted-toolcache node (the contract's H3 case in `c4-render-sandbox.test.ts`) passes the
docker replay. Harness-edit row: removing the docker replay arm drops the ledger below the floor.

**Anchor.** The literal census reads the server and scripts trees, not the fixtures, so a fixture-only edit cannot hide a new spawn site.

### Guard 4 — suite image lineage and PATH precedence

**Property.** The suite's container runs the base image digest and the PATH order the `runner` stage ships.

**Assembly.** Dockerfile stage graph (`deps`, `builder`, `cli-tools`, `runner`; `runner FROM cli-tools`), every `FROM`, any `ENV PATH`
or `ENV` that touches PATH, the shim `COPY`, `USER`; the live container PATH for uid 1001.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `cli-tools` FROM a different digest or tag | RED `BASE_LINEAGE` (suite) |
| 2 | `ENV PATH=/usr/bin:/usr/local/bin:$PATH` added to `runner` | RED `PATH_ORDER` static |
| 3 | `runner` retargeted `FROM builder` (stage graph walk must not stop at the first `FROM`) | RED `BASE_LINEAGE` |
| 4 | shim mounted at `/usr/bin/bwrap` instead of `/usr/local/bin/bwrap` in the suite container | RED live `command -v bwrap` arm |
| 5 | Dockerfile with no stage named `runner` or an empty graph | RED, never a default base |

**Harness rows.** Must-PASS: a Dockerfile that adds an `ENV PATH=/usr/local/bin:/usr/bin:$PATH` (compliant order) passes; stage
names in different case or with `AS` lowercase pass. Anchor: `c4-likec4-version-pin.test.ts` pins the same graph from the vitest side
(an independent reader of the same file), so the suite's derivation and the pin test must both be edited to weaken it.

## Deepen-Plan Findings (2026-10-12)

Enhancement summary. Sources: the plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CTO devex, CPO),
then security-sentinel and test-design-reviewer, plus inline measurements (a `shlex` prototype of the Phase 2 grammar over the real
tuples; bounded `python3 -I` mmap reads of both vendored binaries; `gh` checks). Cited issues were resolved live: #10043, #10039, #9938
merged; #9860 and #9723 closed; #10110 is the open draft PR; the AGENTS rule id `cq-write-failing-tests-before` is active; labels
`priority/p3-low`, `type/chore`, `domain/engineering`, `meta/machinery` exist. A local docker daemon is present (Server 29.7.2), so Phase 0
is runnable. Scale: the plan-review panel already fanned out 7 specialist agents on this exact plan one step earlier, so this pass
added two targeted specialists plus measurements instead of re-running the whole roster.

**D1 [security, P1] drop and cover are not behaviorally distinct for the main vendor argv.** The vendor argv begins `--ro-bind / /` (one push
per binary), bwrap binds recursively, so the container's procfs is beneath the vendor `--tmpfs /proc` after a drop and after a cover
alike (the shim's own comments at L110-114 and L629-631 already say a root bind re-exposes procfs). A process without CAP_SYS_ADMIN cannot
reach it (`umount` is EPERM; nested-userns copies are locked mounts; `/proc` is an empty tmpfs, so there is no `/proc/self/*` to use; the
shim sweeps inherited fds). The barrier is `--cap-drop ALL`, which the plan now pins (`CAP_BARRIER`). The recorder arm remains the only
guaranteed discriminator and it measures "no argv-requested procfs mount", which is the shim's contract, not a kernel-level absence.
Consequences applied: Guard 2 property reworded; ADR-075 and the shim header comment corrected in this PR (expected, not conditional);
Phase 4.4 becomes the "umount refused under the vendor caps" arm (a positive control with caps retained must succeed, otherwise the
refusal is not attributable to the cap drop).

**D2 [security, P2] the CLI's second builder is the hook sandbox.** Closed by evidence (Phase 6.1). Not reachable from tenant input on
the agent runner; fails closed under the masks; counts pinned 2/1/2.

**D3 [Kieran and security, P1] census and grammar gaps.**

- The `docker run` census also covers `docker create`, `docker container run`, global-option forms (`docker -H x run`), `"$DOCKER" run`,
  `sudo` and absolute-path spellings, and any docker verb naming the app image ref or `--name soleur-web-platform*`. Existing
  `docker create` sites at `cloud-init.yml` L538/681/724 and `ci-deploy.sh` L4170/4783 are named exemptions only if they do not start the
  app. Scope stays the web host's two files plus a repo-wide `git grep` for the app name and image ref; other hosts' containers
  (`egress-gateway-bootstrap.sh`, the zot registry) are out of the closed set by name.
- Value expressions are allowlisted per option and exact (`--memory "$CANARY_MEMORY_CAP"`, `-e SOLEUR_HOST_ID="$HOST_ID"`,
  `-e NODE_OPTIONS="$..._NODE_OPTIONS"`, `--env-file "$ENV_FILE"` or `"$TMPENV"`, the two image expressions). Any other `$`, backtick or
  `${` in a tuple line (a `templatefile` interpolation included) is `UNPARSEABLE_OPTION`. The `NODE_OPTIONS` assignment lines
  (`ci-deploy.sh` L4249-4250) are pinned to the `--max-old-space-size=` form.
- Attached or combined short spellings (`-ePATH=x`, `-v/h:/c`, `-u0`, `-dit`) match no whole-token arity entry and are
  `UNKNOWN_OPTION`; a valueless `-e NAME` is refused; a second `--security-opt apparmor=` or `seccomp=` is `DUPLICATE_OPTION` (docker
  keeps the last, so a set-valued projection hides it).
- The prototype run on 2026-10-12 confirmed zero violations on the three real tuples, identical security-opt and tmpfs projections, and
  the image forms `$VERIFIED_REF` (after stripping `; then`) and `$(cat /run/soleur-image-ref)`.

**D4 [spec-flow, P0] the guard was advisory.** Fixed by the required-lane wrapper (`test/docker-run-tuple-posture.test.ts`) and the
extra `paths:` entries (Phase 7.5-7.6). Residual, stated: `--env-file` content (Doppler prd) can still carry a key the shim reads
(`SOLEUR_BWRAP_REAL`, `SOLEUR_BWRAP_SECCOMP_BPF`) or PATH; the `overlay_github_app_key` hijack list refuses PATH, LD_* and similar when
the overlay runs, but whether it covers `SOLEUR_BWRAP_*` was not confirmed. `measurements.md` records the answer from `ci-deploy.sh`
L3160-3190 at work time, and the Guard 4 live PATH arm proves the suite container only.

**D5 [test-design, P0 and P1] matrix hardening.** Applied as work-phase requirements for the rows and arms they name:

- Guard 4 gains a static row on the Dockerfile `COPY` destination (shim to `/usr/bin/bwrap` is RED) and a `MUTATE=shim-path` seam for the
  live arm; the existing wire pin (suite L139) is the base.
- Guard 1's "posture equals what the suite starts" is a tautology once the suite derives from the tuple. Add a `docker inspect` arm on the
  running suite container asserting `HostConfig.CapAdd` empty, `PidMode` empty, `User`, the apparmor and seccomp entries and a non-empty
  `MaskedPaths` (never assert systempaths through `SecurityOpt`: docker consumes it client-side).
- Placement assertions on every Guard 1 row that edits one of near-identical tuples: the FAIL line must name the intended file and tuple,
  and the diff of the mutated copy must be confined to that tuple's line range (a first-match `sed` would otherwise edit the canary block
  and grade a row about the wrong tuple).
- The M1 fallback needs a positive token (`"arm":"outer-wrap"` plus a verdict) and an unconditional instrument control (the same harness
  fed `--proc /proc` must produce the refusal), or it passes on any unrelated failure.
- H1 gets matching stubs for the census (a fixed `tuples=3` must leave rows 5, 6 and 11 NOT KILLED) and for posture-value checks. Add
  rows for `apparmor=unconfined` and `seccomp=unconfined` as value rewrites and for `TRAILING_ARGS`, and pin row 6 to one token.
- The recorder arm gets an instrument control (a recorder that records nothing, or is bypassed, must go red: the argv must be non-empty
  and contain the fixture `--dev` tail) and path-normalization rows (`/proc/`, `//proc`, `--bind-try`, `--dev-bind`, `--ro-bind /proc /proc`).
- Arm-deletion rows for every new docker arm (PATH live, BASE_LINEAGE, outer replay, FIXTURE_TAIL), and one row proving `MIN_ASSERTIONS`
  is exact (delete one assertion, expect red). FIXTURE_TAIL, BASE_LINEAGE and the tuple check run before any docker call; a `docker`
  stub on PATH with an empty call log proves it.
- Guard 3 consistency: the literal census names three files (outer-wrap, c4-render, `sandbox-canary.mjs`), not two. The C4 fixture pin
  is a change detector, so add a direct assertion that the built argv has no procfs-mount token, and replace "empty stderr" in the
  replay with exit 0 plus an output sentinel (bwrap warnings make stderr flaky).
- Guard 4 `ENV PATH` rows: the legacy `ENV PATH /usr/bin:...` form, a multi-variable `ENV A=1 PATH=...` and a mutant
  `ENV PATH=/usr/bin:$PATH` must go RED; the compliant spelling must pass; add a `USER` and uid derivation row.

**D6 [plan-review, applied].** Cuts accepted: the cross-artifact checks, the line cap, the ADR addendum as an unconditional item (it is now
a correction, D1), M6 and M7, the self-grep of the suite. Dissent recorded without being applied (operator scope is the default):
`knowledge-base/project/specs/feat-one-shot-10065-sandbox-proc-suite-parity/decision-challenges.md`.

## Implementation Phases

### Phase 0 — Measurements (before any assertion shape is fixed)

Run in an allocated sandbox with a docker daemon (`bash scripts/soleur-sandbox.sh new sbx-10065`, then `run-isolated`; if the
isolated PID namespace cannot reach the docker socket, run the docker steps from the worktree and say so in the record). Local runs use
`SOLEUR_SANDBOX_DOCKER_APPARMOR=unconfined` (refused under CI, prints `APPARMOR_OVERRIDE`), so these measurements cover the docker-mask
delta; the AppArmor half is CI's. Record results in `knowledge-base/project/specs/feat-one-shot-10065-sandbox-proc-suite-parity/measurements.md`
with the image digest and `bwrap --version` (the M3 outcome is a security finding and must outlive the session). Phases 1-3 and 6 do not
depend on any measurement and proceed regardless. M3 is a hard gate for Phase 4 (see its row); M1 and M2 gate only the docker replays in
Phase 5, whose static pins ship either way.

| # | Measure (suite image, uid 1001, default masks) | Decides |
|---|---|---|
| M1 | First reconcile what bwrap prod ships (the Dockerfile reverts the file-cap arm and audits zero file-cap binaries, `agent-outer-wrap.ts` L655 says prod bwrap "elevates", ADR-075 mentions a file-cap bwrap): the suite image uses plain Debian bubblewrap and never builds the `runner` stage, so say in the record what the replays do and do not prove. Then `node /app/scripts/sandbox-canary.mjs --replay-outer`: verdict and reason | Phase 5a: assert `"verdict":"pass"` plus `"arm":"outer-wrap"`, or, if the plain Debian bwrap cannot take the outer table unprivileged (the prod posture elevates), assert only "no `mount proc`/procfs refusal and not `sandbox_broken` with `bwrap_operation_not_permitted`" and record why |
| M2 | `buildLikeC4SandboxArgv` output (a stage dir under `$WORK`, fd 9 on the committed `.bpf`, fd 3 to `/dev/null`) through `/usr/bin/bwrap -- /usr/bin/true` | Phase 5b: whether the replay is a plain pass assertion, and what `--seccomp 9`/`--json-status-fd 3` need from the harness |
| M3 | First `command -v umount` in the image (Debian splits `mount` out of util-linux; if absent, the behavioral arm uses `python3`-free alternatives or is dropped and recorded). With the shim and with the cover mutant, vendor tail argv WITH caps retained and WITH the vendor's `--cap-drop ALL --cap-add CAP_SETFCAP`: after `umount /proc` inside the sandbox, is the sibling visible, and does `umount` succeed at all? Cheap first proof: `bwrap --ro-bind / / --unshare-user --unshare-pid -- cat /proc/self/mountinfo` should list a procfs with no `--proc` and no tail bind. The recursive `--ro-bind / /` carries a procfs beneath the vendor tmpfs (the security review's expected outcome, D1), in which case drop and cover are behaviorally identical for any process without CAP_SYS_ADMIN and the cap drop is the operative barrier | Phase 4: add a behavioral cover-vs-drop arm only if it separates the two; otherwise add the "uncover refused under the vendor caps" arm (umount must fail EPERM) and keep the recorder as the cover discriminator. Record the finding either way. If drop and cover are behaviorally identical, stop Phase 4 at the recorder arm and the "uncover refused under the vendor caps" arm, open a security issue (ADR-075 and the shim header rest on "dropping removes the mount object entirely", which the recursive root bind would falsify), amend ADR-075 in this PR, and rewrite Guard 2's property to name the cap drop as the operative barrier; the "no ADR decision" statement above then no longer holds. Time-box M3 to one run |
| M4 | The real shim with `SOLEUR_BWRAP_REAL` pointing at a mounted recorder script, inside the container, with the fixture-derived argv | Phase 4: the recorder works under the shim's fd sweep and `--args` handling |
| M5 | `docker exec -u 1001 <ctr> sh -c 'echo "$PATH"; command -v bwrap; type -a bwrap'` in the suite image | Phase 3: the literal PATH the live arm compares |

If Docker is unusable in the sandbox, stop and report after Phases 1-3 and 6; do not proceed to Phases 4-5 on assumed measurements for
M1-M4, since their assertion shapes depend on them (see `2026-10-11-a-green-sandbox-probe-and-a-silent-log-were-both-measuring-something-else.md`).

### Phase 1 — RED first (cq-write-failing-tests-before)

1.1 Create `apps/web-platform/infra/docker-run-tuple.test.sh` with the Guard 1 battery rows and the must-PASS rows, against a helper
that does not exist yet; confirm every row fails for the right reason (missing helper), then proceed. Sources
`lib/mutation-scorer.sh` for row attribution (`mutation_scorer_failed_on <log> <fail-line-ERE> <needle>...`); runs in `$WORK` with
`assert_fixture_dir` first (copy the guard from `lib/apt-bounded.sh`: an empty or root-like TMPDIR must end the shell before any
`rm -rf`).
1.2 Create `apps/web-platform/test/docker-run-tuple-posture.test.ts`, `test/sandbox-vendored-argv-tail.test.ts` and
`test/c4-render-argv-fixture.test.ts` skeletons asserting the Guard 1, 2 and 3 rows; they fail until Phases 2, 5 and 6.

### Phase 2 — Tuple parser and unit battery (P1)

2.1 `apps/web-platform/infra/lib/docker-run-tuple.py` (stdlib only, run as `python3 -I`):

- `check [--root DIR]` prints `docker-run-tuple:ok tuples=3 posture=<12 hex of sha256(posture projection)>` or one
  `FAIL <TOKEN>: <detail>` line per violation (exit 1). `--root` defaults to the helper's own `../..` so the Check 10 probe runs from
  anywhere; the battery points it at mutated copies.
- `posture --tuple canary|prod|first-boot [--root DIR]` prints the docker options the suite should start its container with, one per
  line, after running the same checks (a suite that cannot parse stops there).
- Logical lines are joined on backslash-newline, comment lines dropped, indentation stripped, then `shlex.split`. The statement's
  leading `if` and trailing `; then` are stripped before classification (the prod tuple tokenizes as `... '$VERIFIED_REF;' 'then'`,
  measured on the real file; a must-PASS row carries the `if docker run ... ; then` form). Options are classified through one arity table; `--opt=value` and `--opt value`
  normalize to the same record. Option classes: POSTURE (`--security-opt apparmor=...`, `--security-opt seccomp=...`, `--tmpfs /tmp:...`,
  `--init`), BENIGN with value allowlists (`--name`, `--log-driver`, `--restart`, `--memory`, `--memory-swap`, `--env-file`,
  `--add-host`, `-e` names `{INNGEST_BASE_URL, CRON_WORKSPACE_ROOT, SOLEUR_HOST_ID, NODE_OPTIONS, SOLEUR_EGRESS_REAPER}`, `-v` specs per
  tuple, `-p` specs, `-d`), everything else `UNKNOWN_OPTION <spelling>`. Any `--security-opt` value other than the two declared
  names is `POSTURE_VALUE`. The image expression must be the last token and one of the known forms (`"$VERIFIED_REF"`,
  `"$(cat /run/soleur-image-ref)"`); anything after it is `TRAILING_ARGS`.
- A shell-expansion token in option position (`$`, backtick, `${...[@]}`) that is not one of the three known value expressions is
  `UNPARSEABLE_OPTION`.
- Census: command-position `docker run` in `ci-deploy.sh` and `cloud-init.yml` (comments and assertion strings excluded by a
  statement-position test, same discipline as `apt-bounded.test.sh` `_CMDPOS`); each site is an app tuple, the named cosign-verify
  exemption, or `UNCLASSIFIED_DOCKER_RUN file:line`.
- Census scope: besides the two files, `git grep` for `--name soleur-web-platform` and a command-position `docker run` over
  `apps/web-platform/infra/**` (non-test) and `.github/workflows/**` finds any third start site; an unlisted hit is
  `UNCLASSIFIED_DOCKER_RUN`. Out of the closed set by design (stated residuals, not claimed closed): the content of `--env-file`
  (Doppler prd; `ci-deploy.sh` `overlay_github_app_key` refuses runtime-hijack names such as PATH and LD_* only when that overlay runs)
  and the value of `-e NODE_OPTIONS=...`.

2.2 Make the Phase 1 battery pass; keep every mutation inside `$WORK` copies (files `cp`'d from the tree, mutated with `sed`/`awk`
into the copy, never in place). Harness rows H1/H2 and the must-PASS rows P1-P3 included. Floor literal `MIN_ROWS` adjacent to its
`if`.

### Phase 3 — Suite: derived container, base lineage, PATH (P2, P6)

3.1 `sandbox-masked-proc-docker.test.sh`: call `docker-run-tuple.py check` before the docker environment checks (static red must not
need a daemon); on FAIL print the tokens and `die`. `SANDBOX_MASKED_PROC_SRC_ROOT` (battery only) points `--root` at mutated copies and is
refused when `CI` is set, same shape as the AppArmor override.
3.2 `start_container` builds its options from `posture --tuple prod`, mapping the host seccomp path to `$SECCOMP` and the apparmor value to
`$APPARMOR_OPT_VALUE`; `-u` comes from the Dockerfile's `useradd --uid` (assert `USER soleur` is the last `USER`). The control and
positive-control arms keep their call-site `--security-opt systempaths=unconfined` argument by design; the derivation is pinned by Guard 1
(a hand-written option in `start_container`'s body would not reach the mutation rows that edit the real tuple).
3.3 BASE: resolve the stage `runner` is `FROM` (one hop, bounded loop of 8) to its image reference carrying `@sha256:`; fail
`BASE_LINEAGE` when there is no `runner` stage, the hop does not end at an image, or a direct-image stage digest differs. (The stage
graph itself is already pinned by `c4-likec4-version-pin.test.ts`; this only makes the suite read the same lineage.)
3.4 PATH: static (`ENV PATH` absent, or `/usr/local/bin` before `/usr/bin`; this is the arm that sees a `runner`-stage `ENV PATH`, which
the suite's container, built from the base image, cannot) and live arm after `start_container`: `docker exec -u 1001`
`command -v bwrap` equals `/usr/local/bin/bwrap` and `type -a bwrap` lists it before `/usr/bin/bwrap` (M5 supplies the literal).
3.5 Raise `MIN_ASSERTIONS` to the new total (the literal stays adjacent to its `if`).

### Phase 4 — Isolation arm: fixture-derived tail, recorder, cover mutant (P3, P5)

4.1 Derive `ISO_ARGV` from `sandbox-canary-argv.json` with `jq`: the prefix is the fixture's own `--ro-bind / /` and `--tmpfs /proc`
pairs (the fixture's `--unshare-net` is deliberately not carried: the arm measures /proc visibility, and a netns changes nothing about
it; say so in the suite header), the tail is every token from the LAST `--dev` to the end, then the
`--cap-add CAP_SETFCAP` pair is removed for the uid-1001 replay (the builder adds it only for euid 0 with setfcap; the fixture was
captured as root), leaving `--cap-drop ALL` alone (a behavior change against today's argv, covered by M3). Fail `FIXTURE_TAIL` (before any docker call) when the fixture lacks the
`--dev`, the tail `--bind /proc /proc` or the `--tmpfs /proc` pair.
4.2 Recorder: a script under `$WORK` mounted read-only, set as `SOLEUR_BWRAP_REAL` for one `docker exec`, writing NUL-separated argv to
the container tmpfs and then `exec /usr/bin/bwrap "$@"`. The arm asserts the recorded
argv has no `--proc`, no bind-family token whose source or destination normalizes to `/proc`, and exactly one `--tmpfs /proc`.
4.3 `MUTATE=shim-cover` seam (battery only): a wrapper that appends `--tmpfs /proc` and keeps the vendor bind, then execs the real
shim. Header seam list updated.
4.4 Per M3 (expected outcome, D1: cover and drop do not differ behaviorally): the "umount of the mask is refused under the vendor
caps" arm, with a positive control (caps retained, `umount` succeeds, so the refusal is attributable to the cap drop); a behavioral
cover-vs-drop arm only if M3 unexpectedly separates them. Either way a sentence in the suite header naming what the behavioral arms do
and do not discriminate, and the shim header comment and ADR-075 corrections (comment and prose only).

### Phase 5 — Spawn paths under the masks (P4)

5.1 Outer wrap (per M1): `node /app/scripts/sandbox-canary.mjs --replay-outer` in the masked container with the verdict assertion
M1 selects, plus a non-vacuity token from the output (`"arm":"outer-wrap"`).
5.2 C4 render (per M2): `apps/web-platform/infra/c4-render-sandbox-argv.json` (schema `c4-render-bwrap-v1`, `{{STAGE}}` and
`{{NODE}}` placeholders, `_comment` stating it is generated by the pin test and never hand-edited, the same convention as
`agent-outer-wrap-argv.json`). `test/c4-render-argv-fixture.test.ts` regenerates it from `buildLikeC4SandboxArgv` and fails on
difference, with the regeneration command in the failure message; it also pins `BWRAP_BIN === "/usr/bin/bwrap"`,
`BWRAP_PATH === "/usr/bin/bwrap"`, and a literal census: every occurrence of `BWRAP_BIN`, `BWRAP_PATH` or a `"/usr/bin/bwrap"` / bare `bwrap` spawn target across
`apps/web-platform/server/**` and `apps/web-platform/scripts/**` is in an expected list (`c4-render.ts` spawns bash with bwrap nested in
argv, `agent-outer-wrap.ts` has a `spawn` and a `spawnSync` of different shapes, and `scripts/sandbox-canary.mjs` spawns it too, so a
"first spawn argument" scan would count 1 or pass vacuously).
5.3 The suite replays the C4 argv with the same fd 9 and fd 3 setup the launcher uses (the committed `.bpf`), under the masks, asserting
exit 0 and an empty stderr.
5.4 If M1 or M2 shows an arm cannot run in the unprivileged suite image, keep the static pins (constants, census, fixture pin), record
the measured reason in the suite header and `measurements.md`, open a tracking issue for the missing runtime replay (milestone and labels
of #10065) in the same PR, and do not write a weaker runtime assertion that passes for the wrong reason.

### Phase 6 — Vendored builder tail, creds-free (P3)

6.1 `apps/web-platform/test/helpers/vendored-bwrap-tail.ts`: `extractBuilderTail(buf: Buffer)`; exported, pure, takes a buffer so the
mutation rows feed synthetic ones. It finds the anchor `.push("--dev","/dev"),` (exactly one occurrence, else `TAIL_ANCHOR found N`),
takes a window of at most 4 KiB, and collects, in order, the consecutive string-literal arguments of each `.push(` call up to the
`.push("--",` call. Expected literal sequence: `[--dev /dev] [--unshare-pid] [--unshare-user]` then the two mutually exclusive branches
`[--proc /proc]` and `[--bind /proc /proc]` (the extractor asserts both branches are present, not a five-item sequence; the
`...caps(...)` spread is opaque and covered by the live-spawn row). Per-binary census of procfs-mount sites: counts of
`"--proc","/proc"`, `"--bind","/proc","/proc"` and `"--unshare-pid"` are pinned per binary (measured 2026-10-12: SDK 0.3.284 = 1/1/1;
CLI 2.1.293 = 2/1/2). The CLI's second site is a different builder (the hook sandbox, `/run/claude-hook/apply-seccomp`, an array-literal
form with a fresh `--proc /proc`); it is not a tail-shaped site, so it is pinned by count only. Resolved by the security review (D2): it exists only in the CLI binary
(`/run/claude-hook` appears twice there and never in the SDK binary), has no `--ro-bind / /`, so its `--proc` is a pidns-scoped procfs and
no cross-tenant exposure; the shim drops its `--proc` for any destination and appends the tmpfs mask, so under docker's masks a hook
sandbox fails closed (availability only, no exposure); the agent runner spawns the SDK binary with `settingSources: []`, and no remote
or `--cloud` spawn exists in `server/` or `scripts/`. Two extra anchors pin that: the second `--proc` site sits inside the
`/run/claude-hook` function, and `"--ro-bind","/","/"` stays at one push per binary. The `"--cap-drop","ALL"` literal is pinned at one
per binary and the only `--cap-add` literal is `CAP_SETFCAP` (`CAP_BARRIER`). A new procfs-mount site in any bump reds the count, with a message naming the inspect-and-update steps. The Dockerfile's
global `@anthropic-ai/claude-code@2.1.293` is the same pin as `package.json` (`claude-cli-pin-knows-models.test.ts` enforces it), so the
node_modules binary stands for it. A file reader scans the platform binary in chunks with a
64 KiB overlap (no `readFileSync` of 243 MB); the platform package is resolved as `@anthropic-ai/<pkg>-linux-x64`.
6.2 `test/sandbox-vendored-argv-tail.test.ts`: real-binary rows for both packages (skipped only when the platform is not linux-x64 and
`CI` is unset; under `CI` an absent binary fails), the synthetic mutation rows, the fixture-tail equality row (the fixture's tail from
its last `--dev`, with the `--proc`/`--bind` alternation resolved to the branch the sandbox config selects), and the guard that the test
never reads the ack trailer or any git state.
6.3 `test/sandbox-proc-mask-runtime.test.ts`: add the live-tail row: for the recorded setup spawn, the tokens from the last `--dev` to
the `--` boundary equal the fixture tail with the cap segment normalized (the SDK's `BV()` returns `--cap-drop ALL` only when the process is not root with
setfcap, and adds `--cap-add CAP_SETFCAP` otherwise; the fixture was captured as root, so a non-root CI run records a shorter tail:
compare the literal tokens, require `--cap-drop ALL`, and require every `--cap-add` to be `CAP_SETFCAP`; a normalization that
ignored the segment would let an added `--cap-add CAP_SYS_ADMIN` through). The existing row only checks the relative order of `--tmpfs /proc` and
`--bind /proc /proc`. On `TAIL_DRIFT` the message names the creds-gated `--capture` as the only fixture regenerator (no creds-free
path exists, by design) and says to inspect the new builder first.
Runs where bwrap and socat exist (`C4_BWRAP_REQUIRED=1` in CI makes absence a failure).

### Phase 7 — Registrations, CI wiring, record

7.1 `git add` every new file first, then run the orphan, guard-vacuity and fixture-relative ratchets (they only see tracked files).
7.2 `scripts/guard-vacuity-floor.test.sh` `PROMOTED_FILES`: add `apps/web-platform/infra/docker-run-tuple\.test\.sh` and keep
`sandbox-masked-proc-docker` listed; each promoted file carries a literal floor adjacent to its use. Expect a sync conflict on this line:
keep main's alternation and append this plan's entry.
7.3 `.claude/hooks/grep-q-pipe-guard.test.sh`: `FILES_8855` gains `apps/web-platform/infra/docker-run-tuple.test.sh` and the `PIN_8855`
count moves by one; no `x | grep -q` anywhere in the new files (here-strings, or `grep -c`).
7.4 `apps/web-platform/infra/apt-bounded.test.sh`: re-run; if the docker suite gains a literal `docker run` site, bump its `SPECS`
declared-unmounted count (prefer reusing `start_container` so the count does not move); if the new unit suite quotes `docker run` and
apt text as DATA, add an `EXEMPT` line with the reason.
7.5 `.github/workflows/infra-validation.yml`: refresh the step comment (what the suite now proves), add `apps/web-platform/package-lock.json`,
`apps/web-platform/server/c4-render.ts` and `apps/web-platform/server/agent-outer-wrap.ts` to the `pull_request` `paths:` (an SDK bump or a
spawn-constant edit otherwise never runs the docker replays), and keep the docker step's `timeout-minutes: 10` unless the first CI run
needs more (the job-level bound is 15; raise the step only with a measured CI wall time, no local figure). The unit suite needs no workflow edit (globbed onto the
matrix legs); confirm with `bash scripts/test-all.sh --print-selection`.
7.6 `apps/web-platform/test/docker-run-tuple-posture.test.ts` (new): a vitest wrapper that runs `python3 -I docker-run-tuple.py check` on the
real tree and requires exit 0 plus the `docker-run-tuple:ok tuples=3` line. The infra-validation jobs are ADVISORY (not in the required
check set; `infra-validate-required` carries a do-not-make-required note and the workflow has no `merge_group` trigger), so on their own
they would not stop an appended `--cap-add` from merging; the webplat vitest shards run under the required `test` aggregator.
7.7 `sandbox-canary-soak.test.sh` L126-130 stay (narrower, harmless); no edit.

### Phase 8 — Verification (sandbox, targeted; no full battery)

All runs in an allocated sandbox (`soleur-sandbox.sh new` / `run-isolated` / `rm`; the sandbox has no `.git`, so anything that calls
`git` runs in the worktree instead, and the plan notes which). Order: unit battery (`bash apps/web-platform/infra/docker-run-tuple.test.sh`),
`tsc --noEmit` from `apps/web-platform` (`./node_modules/.bin/tsc --noEmit`), then the vitest files by path (`./node_modules/.bin/vitest run test/sandbox-vendored-argv-tail.test.ts test/c4-render-argv-fixture.test.ts
test/sandbox-proc-mask-runtime.test.ts test/docker-run-tuple-posture.test.ts test/c4-likec4-version-pin.test.ts` from `apps/web-platform`), the docker suite locally with the
AppArmor override (baseline green first, then each `SANDBOX_MASKED_PROC_MUTATE` value and each `SANDBOX_MASKED_PROC_SRC_ROOT` mutated
copy red, each attributed by its own diagnostic), `guard-vacuity-floor`, `lint-orphan-test-suites`, `fixture-relative-assert`,
`apt-bounded.test.sh`, `grep-q-pipe-guard.test.sh`, `plugins/soleur/test/c4-count-parity.test.sh`, `scripts/lint-guard-contract.py` on this
plan. The docker suite under the real `soleur-bwrap` AppArmor profile is only provable in CI (`infra-validation.yml`); a failure there
is a real finding about production.

### Phase 9 — Ship constraints

Draft PR #10110 exists. After a rebase conflict on `PROMOTED_FILES`, re-derive rather than hand-merge: take main's line, add this plan's
entries, then re-run `guard-vacuity-floor.test.sh` (its floor ratchet compares against the list). Mark ready only after the verification above. `gh pr merge 10110 --auto` (no `--squash`) after the operator's
go-ahead; the queue handles the merge: never sync a queued PR, one re-arm on a dequeue, then stop and report. Poll with Monitor, never
sleep. This diff performs no production write: no deploy workflow dispatch, no re-run of a release deploy job, no Doppler write. PR body:
`Closes #10065`; do not claim the AppArmor-profile result until CI shows it.

## Files to Create

- `apps/web-platform/infra/lib/docker-run-tuple.py`: closed-world tuple parser, census, posture projection (P1, P2).
- `apps/web-platform/infra/docker-run-tuple.test.sh`: unit and mutation battery for it (Guard 1), unprivileged, globbed onto the matrix legs.
- `apps/web-platform/infra/c4-render-sandbox-argv.json`: generated C4 render argv fixture (Phase 5b, shape confirmed by M2).
- `apps/web-platform/test/helpers/vendored-bwrap-tail.ts`: pure builder-tail extractor and chunked binary scanner.
- `apps/web-platform/test/sandbox-vendored-argv-tail.test.ts`: Guard 2 builder and fixture rows.
- `apps/web-platform/test/c4-render-argv-fixture.test.ts`: Guard 3 fixture pin, constants, literal census.
- `apps/web-platform/test/docker-run-tuple-posture.test.ts`: required-lane wrapper for the tuple check.
- `knowledge-base/project/specs/feat-one-shot-10065-sandbox-proc-suite-parity/tasks.md` and `measurements.md` (Phase 0 record).

## Files to Edit

- `apps/web-platform/infra/sandbox-masked-proc-docker.test.sh`: derived container, static parity call, base lineage, PATH arms, fixture-derived isolation argv, recorder arm, `shim-cover` seam, outer-wrap and C4 replays, floor literal, header.
- `apps/web-platform/test/sandbox-proc-mask-runtime.test.ts`: live-tail equality row.
- `scripts/guard-vacuity-floor.test.sh`: `PROMOTED_FILES` entry (expect a sync conflict; keep main's).
- `.claude/hooks/grep-q-pipe-guard.test.sh`: `FILES_8855` entry and `PIN_8855`.
- `apps/web-platform/infra/apt-bounded.test.sh`: `SPECS` count or `EXEMPT` line only if its census demands it.
- `.github/workflows/infra-validation.yml`: step comment and three `pull_request` `paths:` entries.
- `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md`: a `## Decision` clarification and an Alternatives Considered row (drop versus cover differ only for a process holding CAP_SYS_ADMIN; D1).
- `apps/web-platform/infra/bwrap-shim/bwrap`: header comment lines only (L53-56 rationale, D1); no code line changes (AC15).

Verified path globs: `apps/web-platform/infra/*.test.sh` matches 100+ tracked files (`git ls-files`), so the unit suite is globbed;
`apps/web-platform/test/*.test.ts` is the vitest root (`sandbox-proc-mask-runtime.test.ts` lives there). The vendored binaries resolve
at `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude` and `.../claude-code-linux-x64/claude`.

## Observability

```yaml
liveness_signal:
  what: the infra-validation.yml step "Run sandbox masked-/proc docker regression" and the globbed docker-run-tuple suite on every deploy-script-tests leg, plus the webplat vitest shards that run the tail and fixture tests
  cadence: every pull request and merge-queue run that touches infra or web-platform paths
  alert_target: a red `test` aggregator (required) for the vitest wrapper and tail rows; a red advisory infra-validation job for the docker suite and the shell battery, plus the notify-main-failure job on a main failure
  configured_in: .github/workflows/infra-validation.yml and .github/workflows/ci.yml

error_reporting:
  destination: GitHub Actions check status and job log; there is no runtime path and no Sentry mirror site in this diff
  fail_loud: literal tokens on a FAIL line (UNKNOWN_OPTION, POSTURE_VALUE, TUPLE_COUNT, UNCLASSIFIED_DOCKER_RUN, TAIL_DRIFT, TAIL_ANCHOR, FIXTURE_TAIL, DROP_FAILED, BASE_LINEAGE, PATH_ORDER, DOCKER_UNAVAILABLE, APPARMOR_UNAVAILABLE) and a nonzero exit; the suites never self-skip

failure_modes:
  - mode: the parser finds fewer tuples than exist (renamed container, moved block) and exits 0
    detection: TUPLE_COUNT floor of exactly 3 and the census of every command-position docker run
    alert_route: red check on the PR
  - mode: the extractor finds no builder anchor after an SDK bump or minifier change
    detection: TAIL_ANCHOR with the found count, in the webplat vitest shard on the bump PR
    alert_route: red check on the PR, independent of any sdk-bump-verified trailer
  - mode: the docker environment is unusable on the runner
    detection: a literal token and exit 1, never a skip
    alert_route: red step in infra-validation.yml
  - mode: the suite passes with arms deleted
    detection: ledger floor literal beside its use, guard-vacuity-floor promotion, arm-deletion mutation row
    alert_route: red guard-vacuity-floor check

logs:
  where: GitHub Actions job logs for the three jobs above
  retention: the repository's Actions log retention (90 days by default)

discoverability_test:
  command: python3 apps/web-platform/infra/lib/docker-run-tuple.py check
  expected_output: docker-run-tuple:ok
```

## Acceptance Criteria

### Functional

- [ ] AC1. Appending any of `--cap-add X`, `--cap-add=X`, `--pid=host`, `--pid host`, `--security-opt systempaths=unconfined`,
  `--security-opt=systempaths=unconfined`, `-e PATH=...` to ANY of the three app tuples turns `docker-run-tuple.py check` and the docker
  suite red, each attributed to its own token (Guard 1 rows 1-4, 7). Verified by `docker-run-tuple.test.sh` against mutated copies.
- [ ] AC2. `check` reports exactly 3 app tuples and fails (not passes) on 0, 2 or 4 (rows 5, 6, 11).
- [ ] AC3. The suite's container options come from `posture --tuple prod`; no literal `--security-opt`/`--cap-` remains in
  `start_container`; `-u` derives from the Dockerfile.
- [ ] AC4. The isolation argv is derived from `sandbox-canary-argv.json`; a fixture without the tail bind, the `--tmpfs /proc` pair or
  `--dev` fails `FIXTURE_TAIL` before any docker call.
- [ ] AC5. `MUTATE=shim-cover` turns the isolation arm red via the recorder arm (`DROP_FAILED`); the unmutated shim passes; the other
  five existing seams stay red.
- [ ] AC6. The builder literal list is extracted from BOTH vendored binaries and equals the expected sequence; synthetic buffers with an
  extra push, a missing anchor and a duplicate anchor fail with distinct tokens; a mutation applied to the second binary only fails.
- [ ] AC7. The live spawn tail recorded by `sandbox-proc-mask-runtime.test.ts` equals the fixture tail.
- [ ] AC8. `BWRAP_BIN` and `BWRAP_PATH` are pinned to `/usr/bin/bwrap`; the literal census matches its expected file list; the C4 argv
  fixture matches `buildLikeC4SandboxArgv`.
- [ ] AC9. For each of M1 and M2, exactly one of: (a) the replay runs under the masks in the docker suite with a pass assertion, or (b)
  `measurements.md` records the measured refusal and a tracking issue exists for the missing replay. The branch taken is named in the PR body.
- [ ] AC10. BASE resolves through `runner -> cli-tools`; `ENV PATH` reordering fails statically; `command -v bwrap` for uid 1001 is
  `/usr/local/bin/bwrap` in the live container.

### Quality gates

- [ ] AC11. `scripts/lint-guard-contract.py` passes on this plan; every Guard Contract matrix row has a corresponding battery row or
  test, listed in `tasks.md`.
- [ ] AC12. The registrations in Phase 7 are in place and each ratchet is green when run alone: `guard-vacuity-floor`,
  `lint-orphan-test-suites`, `fixture-relative-assert`, `apt-bounded.test.sh`, `grep-q-pipe-guard.test.sh`,
  `run-registered-suites.test.sh` (T2e unchanged), `c4-count-parity.test.sh`.
- [ ] AC13. No new `x | grep -q` pipe, no negated grep (`! grep -q`: use `grep -c` or an explicit `[[ $rc -eq 1 ]]`, so a pattern that fails to compile cannot read as "nothing found") and no unguarded `rm -rf` operand in any new shell file; each new suite carries a literal floor
  beside its use.
- [ ] AC14. The first CI run of the docker step finishes inside its `timeout-minutes` (read from the run, not from a local figure).
- [ ] AC15. The diff changes no production behavior: `git diff --quiet origin/main...HEAD -- apps/web-platform/Dockerfile
  apps/web-platform/infra/ci-deploy.sh apps/web-platform/infra/cloud-init.yml apps/web-platform/server` exits 0 (three-dot,
  merge-base form; a sibling merge touching these paths must not flip it), and the shim is changed at most in comment lines:
  `git diff -U0 origin/main...HEAD -- apps/web-platform/infra/bwrap-shim/bwrap` has no added or removed line that is not a `#` comment
  (the header correction below is the only expected edit).
- [ ] AC16. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean with the new TypeScript files, and the new vitest files
  match the runner's include glob (`test/**/*.test.ts`, `vitest.config.ts`); the helper under `test/helpers/` is imported, not collected.
- [ ] AC17. PR body says `Closes #10065`, states that the AppArmor-profile half is proven only by the CI run, and does not claim it earlier.

## Test Scenarios

- Given the prod tuple with `--cap-add NET_ADMIN` appended, when `docker-run-tuple.test.sh` runs the checker on the copy, then it exits
  1 with `UNKNOWN_OPTION --cap-add` (unit).
- Given only the first-boot tuple mutated (canary and prod compliant), when the checker runs, then the failure names `cloud-init.yml`
  (unit, second-member row).
- Given a tuple using `--cap-add=SYS_ADMIN` spelling, when the checker runs, then it fails the same way (unit).
- Given the three real files, when the checker runs, then it prints `docker-run-tuple:ok tuples=3` (unit, must-PASS).
- Given reordered options and `--restart=unless-stopped`, when the checker runs, then it passes (unit, must-PASS non-canonical).
- Given the docker suite with `MUTATE=shim-cover`, when it runs locally with the AppArmor override, then the recorder arm fails with
  `DROP_FAILED` and the behavioral arms report as before (integration).
- Given a synthetic binary buffer with an extra `.push("--tmpfs","/proc")` after the bind push, when `extractBuilderTail` runs, then it
  returns the extended list and the equality row fails (unit).
- Given the real SDK binary, when the tail extractor runs, then it returns exactly the expected literal groups (and the per-binary procfs-site counts) in a bounded time, with an explicit per-test timeout (unit).
- Given the live spawn recorded through the PATH wrapper, when its tail is compared to the fixture, then they are equal (integration).
- Given `buildLikeC4SandboxArgv` with `--proc /proc` added, when the pin test runs, then it fails and names the regeneration command
  (unit).
- Given the C4 fixture replayed through `/usr/bin/bwrap` under docker's masks, when the suite runs, then it exits 0 (integration; or the
  measured M2 refusal recorded per AC9).
- Given `if docker run ... "$VERIFIED_REF"; then` (the real prod shape), when the checker runs, then it parses it as one app tuple (unit,
  must-PASS).
- Given a Dockerfile `ENV PATH=/usr/bin:/usr/local/bin:$PATH`, when the suite's static arm runs, then it fails `PATH_ORDER` (unit via
  `SANDBOX_MASKED_PROC_SRC_ROOT` copy).

## Non-Goals

- Making the infra-validation jobs required checks: the workflow documents them as advisory and carries a do-not-make-required note; the
  required-lane vitest wrapper carries the tuple check instead.
- Changing the `sdk-bump-verified` ack parser (word anywhere versus trailer): a decision, not a deferral. Once the live-tail checks do not
  read the ack, tightening it buys no property this issue names, and the trailer-parsing traps are documented in the learnings.
- Release provenance work, the flaky `cron-egress-ghcr-probe` clock-boundary rows, and wiring `lint-shell-capture-exit` or
  `grep-q-pipe-guard` into pre-commit: out of scope per the brief.
- The observed first-boot versus ci-deploy differences (no `--init`, no `--memory`, the egress-reaper env and token volume exist only on
  first boot): classified as benign runtime options in the grammar, not asserted equal and not changed here.
- Any docker flag, shim logic, Dockerfile or deploy-path change. The only non-test edits are prose corrections (the shim header comment
  and ADR-075, D1). If M3 or review shows the drop-versus-cover choice should be revisited as a design question (for example a rule that
  the vendor root bind must not be recursive), that is a separate decision the security review owns.

## Risks and Sharp Edges

- The argv-level recorder proves "no procfs mount requested", which is the definition of drop; it is not proof that the kernel exposes
  nothing. M3 states what the behavioral arms can and cannot separate, and the suite header repeats it so nobody reads more into the
  green than it measured.
- Minified identifier names change every SDK bump; the extractor keys on string literals and structure only. A builder refactor that
  moves the pushes will fail `TAIL_ANCHOR` loudly on the bump PR; that red is the intended prompt to re-attest, not a flake.
- Docker-suite wall time grows (two extra replays, one extra exec). M6 and Phase 7.5 bound it; the image build and apt budget are unchanged.
- The unit battery copies `ci-deploy.sh` (about 5000 lines); copy once per mutation family and mutate with line-anchored `sed`, not whole-file
  regex, to stay inside the leg's time budget.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold fails
  `deepen-plan` Phase 4.6; this one carries the threshold and both lines.
- `lane:` defaulted to `cross-domain` (TR2 fail-closed): this branch has no `spec.md`.

## References

- Issue #10065; parent PR #10043 (suite), #10039 (shim drop fix), #9860 (incident), #9938 (canary DIAG), #9723 (isolation guarantee).
- `knowledge-base/project/plans/2026-10-11-fix-agent-sandbox-proc-mask-systempaths-plan.md` (the suite's plan; its stated limit names this issue).
- `knowledge-base/project/plans/2026-10-11-fix-sandbox-shim-procfs-under-masked-proc-plan.md`, ADR-075 (L196, L332), ADR-079, ADR-122.
- `knowledge-base/engineering/operations/post-mortems/agent-sandbox-proc-mount-eperm-postmortem.md`.
- Files: `apps/web-platform/infra/{sandbox-masked-proc-docker.test.sh,ci-deploy.sh,cloud-init.yml,bwrap-shim/bwrap,sandbox-canary-argv.json,agent-outer-wrap-argv.json}`,
  `apps/web-platform/{Dockerfile,scripts/sandbox-canary.mjs,scripts/sdk-bump-sandbox-gate.sh,server/c4-render.ts,server/agent-outer-wrap.ts}`,
  `apps/web-platform/test/{sandbox-proc-mask-runtime.test.ts,bwrap-shim.test.ts,c4-likec4-version-pin.test.ts,agent-outer-wrap.test.ts}`.
