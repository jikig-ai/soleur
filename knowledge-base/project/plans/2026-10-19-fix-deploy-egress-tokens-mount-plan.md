---
title: "fix: deploy-started web container lacks the egress-tokens mount and reaper flag"
date: 2026-10-19
slug: deploy-egress-tokens-mount
branch: feat-one-shot-deploy-egress-tokens-mount
issue: 10457
type: fix
lane: cross-domain
---

# fix: deploy-started web container lacks the egress-tokens mount and reaper flag

Spec lacks valid `lane:` (no spec.md for this branch) - defaulted to cross-domain (TR2 fail-closed).

## Overview

The web container that a normal deploy starts from `apps/web-platform/infra/ci-deploy.sh` has no
bind mount of the host session-token directory `/var/lib/soleur/egress-tokens` and no
`SOLEUR_EGRESS_REAPER=1`, while the fresh-host start in `apps/web-platform/infra/cloud-init.yml`
carries both. Inside the container (uid 1001, path absent in the image) the forwarder's
`mkdir /var/lib/soleur/egress-tokens` fails with EACCES, so an entitled session (the Jikigai
canary workspace is the only prod workspace with `web_egress=true`) degrades to zero egress and
no gateway row is produced. This blocks the egress audit canary
(`knowledge-base/engineering/operations/runbooks/egress-audit-enable.md`).

The tuple checker (`apps/web-platform/infra/lib/docker-run-tuple.py`) is closed-world on the
**allowed** side only: it flags options outside the declared set, never a **missing** declared
member. It also declares the asymmetry (prod has only `_VOLS`; only first-boot has the token
volume and the REAPER env) as expected, so the parity test stayed green while prod lacked the
mount. The fix therefore has two halves: put the mount and flag on the prod start, and make the
checker require every declared member so this omission class reds.

PR body: closes #10457 (the open tracker for the same EACCES) and states that this fix replaces
filing a new issue (the issue-filing hook refused it as fix-inline size). Delivery: a normal
deploy redeploys the container; no manual host edit (see Delivery).

## Research Insights

Local research was done directly (strong local context; no external research needed - this is a
docker flag plus an in-repo checker). Key findings:

- Bug sites: `ci-deploy.sh` canary `docker run` (name `soleur-web-platform-canary`) and prod
  `docker run` (name `soleur-web-platform`, inside `if docker run -d \ ... "$VERIFIED_REF"; then`);
  first-boot reference is `cloud-init.yml` (`-e SOLEUR_EGRESS_REAPER=1` and
  `-v /var/lib/soleur/egress-tokens:/var/lib/soleur/egress-tokens`).
- `docker-run-tuple.py` `TUPLES` spec: canary/prod `volumes: set(_VOLS)`, first-boot
  `_VOLS | {token mount}` and `env` with `SOLEUR_EGRESS_REAPER`. `check_value` (`-v`, `-e`, `-p`
  arms) only tests membership in the allowed set. The posture digest (`digest()`) covers only
  apparmor, seccomp and tmpfs, so adding volumes/env does NOT change `EXPECTED_POSTURE`
  (`e959fc801d99`, pinned in `docker-run-tuple.test.sh` and `test/docker-run-tuple-posture.test.ts`).
- Host dir: `server.tf` `terraform_data` blocks for web-1 (~line 2856) and web-2 (~line 2944) run
  `mkdir -p /var/lib/soleur/egress-tokens` then `chown 1001:1001` and `chmod 0711`. Ownership lives
  on the host inode, so it holds whichever side created the directory first.
- Server side is already correct: `server/index.ts` gates `reapOrphanEgressForwarders()` on
  `SOLEUR_EGRESS_REAPER==="1"`; `agent-runner-sandbox-config.ts` puts the token dir in `denyRead`
  for every session (it only takes effect once the path exists in the container, so the mount also
  turns that deny live). The failure is already mirrored to Sentry
  (`cc-dispatcher.ts`, `reportSilentFallback`, op `web-egress-forwarder-spawn`).
- ADR-278 "Canary isolation" bullet: only the prod container sets REAPER; the canary's `/proc`
  cannot see prod forwarders. Its wording calls the deploy canary "a second consumer of the shared
  token dir", which contradicts the intended state and is amended here.
- Delivery plumbing: `ci-deploy.sh` is a trigger file of `terraform_data.deploy_pipeline_fix`
  (+ `deploy_pipeline_fix_web2`), auto-applied on merge by `apply-deploy-pipeline-fix.yml`;
  `apps/web-platform/**` also fires `web-platform-release.yml`. `cloud-init.yml` does not embed
  `ci-deploy.sh`, and this plan does not edit cloud-init (no user_data change, no host replace).
- Institutional learnings: `2026-10-12-a-closed-world-shell-parser-needs-closed-exempt-grammars-and-carried-quote-state.md`
  (pin row counts as literals; closed grammars); `2026-03-20-docker-nonroot-user-with-volume-mounts.md`
  (bind-mount ownership must match the container uid).

### Premise Validation

Checked: issue #10457 is OPEN and describes exactly this EACCES (so the PR closes it rather than
filing a new one); the cited files exist on `origin/main` (`ci-deploy.sh`, `cloud-init.yml`,
`lib/docker-run-tuple.py`, `docker-run-tuple.test.sh`, `server.tf` dir provisioning); the Better
Stack evidence is in the brief and the Sentry mirror op exists in code. Held: all of it. Draft PR
#10501 (Inngest TLS, different subsystem) edits the same three planned files
(`ci-deploy.sh`, `docker-run-tuple.py`, `docker-run-tuple.test.sh`) - found by the planned-file
anchor re-probe; edits here stay minimal and localized (see Sharp Edges). ADR corpus: ADR-278 is
consistent with the fix (prod sets REAPER and mounts the dir); it does not reject any mechanism
used here. Stale premise: none.

### Property List and Cut List (Phase 0.6b)

Properties: (P1) the deploy-started prod container has a writable token dir and the REAPER flag;
(P2) the canary has neither; (P3) a future omission or addition of a declared member on any of the
three tuples fails a committed test; (P4) the delivery needs no manual host edit.

Cut list (mechanism -> property -> what already covers it):
- ensure/verify host dir in `ci-deploy.sh` (sudo install or stat marker) -> P1 -> `server.tf`
  already provisions the dir on web-1/web-2 and spawn failure is already mirrored to Sentry; a new
  sudo grant would need the root bridge. Cut (CTO ruling R3).
- new per-tuple `required_*` spec fields -> P3 -> making the existing declared sets exact buys the
  same property with no second spec to drift. Cut (CTO ruling R2).
- canary mount -> P2 -> not a requirement (canary serves probes only). Cut (CTO ruling R1).

## Decision Classes

All technical forks were ruled by the CTO agent on 2026-10-19; rows are persisted in
`knowledge-base/project/specs/feat-one-shot-deploy-egress-tokens-mount/decision-challenges.md`.
No money, scope, schedule, authorization or brand item exists in this plan.

## Implementation Phases

Order is RED first, per `cq-write-failing-tests-before`. Rows named K24-K26 and P12 are the new
battery rows in `apps/web-platform/infra/docker-run-tuple.test.sh`.

### Phase 1 - RED tests (no production code change)

1. In `docker-run-tuple.test.sh` add "declared member missing" kill rows that drop a member the
   tuples ALREADY carry today, expecting the new token `MISSING_DECLARED` and the member name on a
   `FAIL` line (they are RED against the current checker, which exits 0 on them):
   K24a prod drops `-v /mnt/data/workspaces:/workspaces`; K24b prod drops the SECOND declared
   volume (plugin mount, ro) while the first stays; K24c prod drops `-e SOLEUR_HOST_ID=...`;
   K24d prod drops one of its two `-p` ports (keeps the ports kind non-vacuous). One row per member
   kind is enough: the arm is one generic loop (simplicity review, taste, applied).
2. Add an independent real-tree assertion in `ci-deploy.test.sh` (it already captures
   `DOCKER_RUN_ARGS:` lines for canary and prod via the mock docker, see the
   `assert_cron_workspace_root` block; select the prod line by `--name soleur-web-platform ` with the
   trailing space so the canary name does not match): the prod line carries
   `-v /var/lib/soleur/egress-tokens:/var/lib/soleur/egress-tokens` and `-e SOLEUR_EGRESS_REAPER=1`.
   RED against the current tree. The canary-lacks half is not repeated here (K26a pins it). This is the anchor that does not
   depend on the checker's own spec (see Guard Contract).
3. Run both suites; confirm the new rows are RED for the stated reason.

### Phase 2 - the checker arm (GREEN for K24)

In `docker-run-tuple.py`:
- Record the volumes, env names and ports a tuple declares in `Record` (populated in
  `check_value`, the single dispatcher for `-v`, `-e`/`--env`, `-p`).
- Add one separate function `check_declared(app_sites)` returning
  `FAIL MISSING_DECLARED: <kind> <member> missing from <file> <tuple> (declared in TUPLES)` for
  every declared `volumes`, `env` name and `ports` member not seen. Skip a site whose tokenization
  failed OR whose `option_viols` already contain an `UNPARSEABLE_OPTION` (K12's comment-mid-tuple
  loses the options after the comment without a tokenization failure; a second block of lines would
  only be noise). Record the env name before the value check so K07f stays one line.
- Phase 2 is GREEN for the K24 rows only; the real tree stays green until Phase 3 changes the spec.
- Register it in `run_checks` with one line; add a `HINTS["MISSING_DECLARED"]` entry; add the token
  to the module docstring token list.
- Keep the diff localized (separate function, one registration line) because draft PR #10501 edits
  the same file.

### Phase 3 - the state change in the spec (RED for the real tree)

In `TUPLES`: prod `volumes` becomes `_VOLS | {egress token mount}` and prod `env` gains
`"SOLEUR_EGRESS_REAPER": {"1"}`. Canary is unchanged. Re-run: the real-tree rows (C1, C2, C3) and
the Phase 1 item 2 assertion must now be RED with `MISSING_DECLARED` naming exactly the prod mount
and prod REAPER env - this reproduces the production bug in the committed tree.

### Phase 4 - the fix (GREEN)

In `ci-deploy.sh`, prod `docker run` only, add two lines beside the existing `-e` and `-v` lines
(same shape as the first-boot lines):

```
        -e SOLEUR_EGRESS_REAPER=1 \
        -v /var/lib/soleur/egress-tokens:/var/lib/soleur/egress-tokens \
```

Put the short comment ABOVE the `if docker run -d \` line (as the existing tmpfs comment is), never between the continued option lines: a comment line inside a backslash-continued tuple ends the bash command (that is exactly what K12 asserts). The comment says: the host dir is owned 1001:1001 0711 by server.tf; the REAPER flag
is prod-only (ADR-278 canary isolation), the canary run gets neither. Do not touch the canary run.

### Phase 5 - remaining battery rows (GREEN)

Add to `docker-run-tuple.test.sh`: K25a prod drops the token mount, K25b prod drops
`SOLEUR_EGRESS_REAPER`, K25c first-boot drops the mount (the property must hold on the cloud-init
file too; its tuple already declares both members in `TUPLES`, so `cloud-init.yml` is unchanged)
(each expects `MISSING_DECLARED` plus the file/tuple needle, with `!` needles proving no
wrong-tuple attribution); K26a canary gains `-e SOLEUR_EGRESS_REAPER=1` (expects the existing
`ENV_NAME` token) - the one row that pins P2. Must-PASS row: P12 prod with the token mount moved
ahead of the workspaces volume and REAPER spelled `--env SOLEUR_EGRESS_REAPER=1` (permitted
non-canonical order and spelling). H1: add `h1_stub declared check_declared '[]'` over K24a-d and
K25a-c so the battery proves it is not vacuous for the new arm. Bump `MIN_ROWS` to the new measured
literal (it is pinned exactly: run once, read the printed count, set it). Confirm `EXPECTED_POSTURE`
is unchanged in both pinning files.

### Phase 6 - documentation and ADR

Amend ADR-278 "Canary isolation" bullet with one sentence: the deploy canary neither mounts the
token dir nor sets `SOLEUR_EGRESS_REAPER`, and `lib/docker-run-tuple.py` pins both (and rewrite
"second consumer of the shared token dir" so it no longer implies the canary mounts it). No new ADR.

### Phase 7 - verify and ship (stop before merge)

Run the verification list under Acceptance Criteria; open the PR with `Closes #10457` in the body
(not the title), the "replaces filing an issue" sentence, and the Delivery description. Stop before
merge for the user's explicit go-ahead (standing rule).

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` - prod `docker run` only (two lines + comment).
- `apps/web-platform/infra/lib/docker-run-tuple.py` - `Record`, `check_value`, new `check_declared`,
  `run_checks`, `HINTS`, docstring tokens, `TUPLES["prod"]`.
- `apps/web-platform/infra/docker-run-tuple.test.sh` - rows K24/K25/K26, P12, H1 stub, `MIN_ROWS`.
- `apps/web-platform/infra/ci-deploy.test.sh` - the independent prod-has/canary-lacks assertion.
- `knowledge-base/engineering/architecture/decisions/ADR-278-opt-in-open-web-egress-via-dedicated-connect-gateway.md`
  - canary isolation sentence.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-deploy-egress-tokens-mount/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-deploy-egress-tokens-mount/tasks.md`

Not touched: the egress audit rollup code, `cloud-init.yml`, `server.tf`, `agent-runner-sandbox-config.ts`
(its `denyRead` of the token dir for every session must stay - it is what keeps sessions out of the
credential dir that is now bind-mounted), `test/docker-run-tuple-posture.test.ts` (digest unchanged).

## Open Code-Review Overlap

To be re-run at deepen time against the final file list (query `gh issue list --label code-review`
bodies for the five paths above). Draft PR #10501 overlaps `ci-deploy.sh`, `docker-run-tuple.py`
and `docker-run-tuple.test.sh` - acknowledged: keep edits minimal and localized, expect a trivial
textual merge (`MIN_ROWS` literal and the `TUPLES` block are the likely conflict points; whichever
PR lands second re-measures `MIN_ROWS`).

## Delivery

No manual host edit and no host replace (`hr-prod-host-config-change-immutable-redeploy` governs
config on a running host; here the change is a container start flag delivered by the deploy
pipeline, and `cloud-init.yml` / `user_data` is untouched).

1. Merge to main. `apply-deploy-pipeline-fix.yml` (path filter on the deploy-pipeline trigger files,
   `ci-deploy.sh` is one) auto-applies `terraform_data.deploy_pipeline_fix` and the web-2 sibling,
   pushing the new `ci-deploy.sh` to `/usr/local/bin/ci-deploy.sh` on web-1 and web-2.
2. `web-platform-release.yml` (`apps/web-platform/**`) builds and deploys; the deploy runs
   `ci-deploy.sh`, which stops and removes the old prod container, asserts the single-replica
   invariant (ADR-027), then starts the new prod container with the mount and the REAPER flag. The
   new container's boot reaper therefore cannot see a live sibling's forwarders (the old container is
   gone), and tokens left on the host after the stop are exactly what it should revoke.
3. Ordering risk, bounded: if the release deploy runs with the OLD `ci-deploy.sh` before the
   pipeline-fix apply lands, behavior is unchanged (still degraded, no regression); the next deploy
   (or a `workflow_dispatch` re-run of the release) carries the fix. Host dir presence: `server.tf`
   already provisions it on web-1 and web-2. (Review correction: a dir that docker creates root-owned
   because the provisioner never ran is NOT self-corrected by this PR - the `chown` lives in
   `terraform_data.egress_gateway(_web2)`, which re-runs only when the gateway artifacts change. That case is
   loud, not silent: the forwarder's write throws EACCES and it is mirrored to Sentry.)
4. Post-deploy verification without SSH (`hr-no-dashboard-eyeball-pull-data-yourself`): use
   `scripts/betterstack-assert-absence.sh` (with its positive control) for the EACCES marker
   `permission denied, mkdir '/var/lib/soleur/egress-tokens'` over the window after the deploy, and
   query Sentry for zero new `web-egress-forwarder-spawn` events; the egress audit canary runbook's
   first-gateway-row step then proceeds. Do not use `docker inspect` as a proxy for these.

## User-Brand Impact

**If this lands broken, the user experiences:** the opted-in workspace's agent web fetches keep
failing and the session continues with zero egress (fail-closed, already the current behavior); a
wrong mount could in the worst case stop the prod container from starting, which would be a visible
deploy failure, not silent data loss.

**If this leaks, the user's data is exposed via:** the token directory holds live gateway bearer
credentials (a file's existence is the credential). The bind mount makes that directory visible
inside the multi-tenant agent container; a sandboxed session reading a sibling's token file would
be able to ride that session's gateway attribution. Mitigations already in place: dir mode 0711
owned by uid 1001 (names unlistable to others), and `denyRead` of the token dir for EVERY session
in `agent-runner-sandbox-config.ts` (untouched; it only becomes effective once the path exists in
the container, so this change turns it live). The first-boot tuple already runs this same
configuration.

**Brand-survival threshold:** single-user incident (Ruled by CTO agent, 2026-10-19: the mount makes
live per-session gateway bearer credentials visible inside the multi-tenant agent container; the only
barriers are the 0711 mode and the `denyRead` in `agent-runner-sandbox-config.ts`, which has never
been live because the path did not exist in the container. A cross-tenant read hits exactly one named
user, so the stricter threshold applies; keep it even after the proof below passes).

**Verification requirement (CTO R5):** before this is called done, prove a sandboxed session cannot
read or list `/var/lib/soleur/egress-tokens` against the real mount. Test proof in the PR (sandbox
config asserts `denyRead` covers the dir for every session) plus a post-deploy probe from a sandboxed
Bash session (list and read both denied). `soleur:engineering:review:user-impact-reviewer` runs at
review.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add the mount and SOLEUR_EGRESS_REAPER=1 to the PROD docker run in ci-deploy.sh" [brief] | Phase 4 / Files to Edit `ci-deploy.sh` | mapped |
| 2 | "decide with evidence whether the canary run also needs them" [brief] | Research Insights + CTO ruling R1 (canary unchanged); K26a pins it | mapped |
| 3 | "update the matching tuples in docker-run-tuple.py and the docker-run-tuple.test.sh so the parity test pins the new state (RED test first)" [brief] | Phases 1-3 and 5 / Files to Edit `docker-run-tuple.py`, `docker-run-tuple.test.sh` | mapped |
| 4 | "keep every other registry/ratchet green" [brief] | Acceptance Criteria verification list, `MIN_ROWS` literal | mapped |
| 5 | "describe the delivery (a normal deploy redeploys the container; this is a prod host config path so no manual host edits)" [brief] | `## Delivery` | mapped |
| 6 | "Do not touch the egress audit rollup code." [brief] | Files "Not touched" + diff-subset AC | mapped |
| 7 | "the PR body should say it replaces filing an issue" [brief] | Phase 7 / PR body AC | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Files to Edit `ci-deploy.sh` (prod run) | "add the mount and SOLEUR_EGRESS_REAPER=1 to the PROD docker run in ci-deploy.sh" | asked |
| Files to Edit `docker-run-tuple.py` (exact declared sets arm) | "update the matching tuples in docker-run-tuple.py ... so the parity test pins the new state" | asked |
| Files to Edit `docker-run-tuple.test.sh` (K24-K26, P12, H1, `MIN_ROWS`) | "update the matching tuples in docker-run-tuple.py and the docker-run-tuple.test.sh" | asked |
| Files to Edit `ci-deploy.test.sh` (independent prod assertion) | — | inferred — justification: the tuple checker's spec and the tuple text can be edited in one diff, so without an assertion that does not read the checker's spec the guard proves consistency only (Guard Contract Anchor) |
| Files to Edit ADR-278 (canary-isolation sentence) | — | inferred — justification: the ADR currently calls the canary a second consumer of the token dir, which contradicts the ruled state; recorded architecture must not lag the change (CTO ruling R4) |
| `check_declared` exactness over volumes, env names and ports | "so the parity test pins the new state" | asked |
| `decision-challenges.md`, `tasks.md` | "Persist every decision as a row of the `| Item | Class | Ruling |` table" | asked |

### Split Assessment

- Subsystems touched: 2 — apps/web-platform/infra, knowledge-base/engineering/architecture
- Planned files: 5 edited + 2 created | Estimated changed lines: ~150 (mostly test rows)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] Phase 1 rows and the `ci-deploy.test.sh` assertion were observed RED before any production
      change (record the failing output lines in the PR body).
- [ ] `bash apps/web-platform/infra/docker-run-tuple.test.sh` passes with the new `MIN_ROWS`
      literal; `python3 -I apps/web-platform/infra/lib/docker-run-tuple.py check` prints
      `docker-run-tuple:ok tuples=3 posture=e959fc801d99` (digest unchanged).
- [ ] The canary `docker run` is byte-unchanged; adding REAPER to it reds the checker (K26a).
- [ ] `bash apps/web-platform/infra/ci-deploy.test.sh` passes including the new assertion.
- [ ] Other suites that read the same files stay green: `bash apps/web-platform/infra/sandbox-masked-proc-docker.test.sh`
      static arms (tuple check line), `apps/web-platform/test/docker-run-tuple-posture.test.ts`,
      `bash scripts/guard-vacuity-floor.test.sh`, `bash apps/web-platform/infra/lib/mutation-scorer-consumers.test.sh`,
      `bash plugins/soleur/test/c4-count-parity.test.sh`, the ADR ordinal and markdown lint on the ADR edit.
- [ ] ADR-278 canary-isolation sentence amended; no new ADR; no `.c4` change.
- [ ] No change to `cloud-init.yml`, `server.tf`, the sandbox config or any egress audit rollup file:
      `git diff --name-only origin/main` is a subset of the Files to Edit + Files to Create lists plus
      the pipeline-written artifacts (this plan, `specs/feat-one-shot-deploy-egress-tokens-mount/{tasks,session-state}.md`,
      the generated `knowledge-base/INDEX.md` if it regenerates).
- [ ] PR body: `Closes #10457`, the "replaces filing an issue" sentence, the Delivery description;
      PR left unmerged pending the user's explicit go-ahead.
- [ ] Post-deploy (owned by the follow-through, after merge): zero new EACCES rows and zero new
      `web-egress-forwarder-spawn` Sentry events after the deploy, proven with the absence helper's
      positive control.

## Test Scenarios

- Mutation M1: delete the prod token mount line -> `MISSING_DECLARED` (K25a).
- Mutation M2: delete prod REAPER env -> `MISSING_DECLARED` (K25b).
- Mutation M3: add REAPER or the mount to the canary -> `ENV_NAME` / `UNKNOWN_OPTION` (K26).
- Mutation M4: drop an unrelated declared member (workspaces volume, host id env, a port) ->
  `MISSING_DECLARED` (K24), proving the arm is general, not special-cased to the egress pair.
- Must-PASS: reordered options and `--env` spelling (P12).

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** CTO agent ruled on 2026-10-19 (see Decision Classes): canary gets neither mount nor
REAPER; declared volume/env/port sets become exact via one new arm; no ci-deploy host-dir ensure
step; ADR-278 amended in the same PR. Flagged risk: delivery ordering (bounded, see Delivery) and
that `denyRead` must not be weakened.

No product, marketing, legal or finance implications: no user-facing surface, no new processing
activity or data category (the token directory and its TOMs are already recorded in the Article 30
register amendment for #9534), no spend. GDPR gate skipped: no schema, auth flow, API route or
`.sql` file is touched and none of triggers (a)-(d) fires.

## Observability

```yaml
liveness_signal:
  what: no new `web-egress-forwarder-spawn` Sentry events and no EACCES mkdir rows for the token dir after the deploy; first `soleur-egress-gw` allow row for the opted-in workspace
  cadence: per entitled dispatch (event-driven); the absence assertion is read once post-deploy
  alert_target: Sentry (feature cc-dispatcher, op web-egress-forwarder-spawn) and Better Stack app-container logs
  configured_in: apps/web-platform/server/cc-dispatcher.ts (reportSilentFallback) - unchanged by this plan
error_reporting:
  destination: Sentry via reportSilentFallback, mirrored to Better Stack
  fail_loud: yes - a spawn failure is reported and the session continues zero-egress by design (fail-closed)
failure_modes:
  - mode: host token dir absent or wrong owner at deploy time (docker creates a missing bind source as root)
    detection: same Sentry op web-egress-forwarder-spawn EACCES event
    alert_route: none in code (review correction: no Sentry alert RULE for op web-egress-forwarder-spawn exists in the repo; the event is mirrored but not paged - tracked in the bundled follow-up)
  - mode: new ci-deploy.sh not yet on the host when the release deploys
    detection: the post-deploy absence assertion still reports the EACCES marker
    alert_route: follow-through step re-runs the release deploy
  - mode: a future edit drops the mount or flag from a tuple
    detection: docker-run-tuple.py check MISSING_DECLARED in CI (infra-validation)
    alert_route: red CI check on the PR
logs:
  where: Better Stack (app container, journald -> Vector) and Sentry
  retention: per the existing Better Stack and Sentry plans (unchanged)
discoverability_test:
  command: python3 -I apps/web-platform/infra/lib/docker-run-tuple.py check
  expected_output: docker-run-tuple:ok
```

## Guard Contract

### Guard 1 - declared members of every app tuple are present

**Property.** Every volume, environment name and port that a tuple's declared spec in `TUPLES` lists
appears in the committed `docker run` that the spec names, so an omission on any of the three
start sites reds a committed test instead of passing as "expected asymmetry".

**Assembly.** The property quantifies over three tuples (canary and prod in `ci-deploy.sh`,
first-boot in `cloud-init.yml`) times three member kinds (`-v` volumes, `-e`/`--env` names, `-p`
ports). The chokepoint is `check_value` in `docker-run-tuple.py`, the single dispatcher for those
options, feeding `Record`, consumed by one arm `check_declared` registered in `run_checks`.
Tuples whose tokenization fails produce an empty `Record` and are skipped by the arm (they are
already red through `UNPARSEABLE_OPTION`). Start sites outside the three declared tuples are the
census arm's job (`check_count`, `check_census_extra`), unchanged.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | prod drops the token mount (K25a) | declared volume missing; every other arm still passes (precondition satisfied, property fails) |
| 2 | prod drops REAPER env (K25b) | declared env name missing |
| 3 | prod drops the SECOND declared volume while the first stays (K24b) | the arm must not stop at the first member |
| 4 | prod drops one of two ports (K24d) | second-member check on ports |
| 5 | first-boot drops the mount (K25c) | the property holds for the cloud-init file too |
| 6 | the arm is stubbed to return nothing (H1 `declared`) over K24a-d and K25a-c | own-dispatch row: a vacuous arm leaves these rows NOT KILLED, which the suite requires |
| 7 | canary gains REAPER (K26a) | pins P2 through the existing closed set |
| 8 | spec weakening: remove the egress pair from `TUPLES["prod"]` and from `ci-deploy.sh` in one diff | the checker stays green (consistency only, see Anchor) but the independent `ci-deploy.test.sh` assertion (Phase 1 item 2) goes RED |

**Harness rows.** Suite-side edit that must go RED: `MIN_ROWS` pinned exactly (deleting a new row
reds floor drift); the H1 stub row above. Must-PASS non-canonical inputs: P12 (reordered options,
`--env` spelling), which is not the canonical tuple text, so an arm that rejects everything fails it.

**Anchor.** The stored value is the `TUPLES` spec; the thing it protects is the tuple text in
`ci-deploy.sh`. One diff can edit both, so the checker proves consistency, not integrity. What must
also move for a weakening to pass: the independent assertion in `ci-deploy.test.sh` (a different
file, asserting the real prod argv through the mock docker, not through the checker's spec), the
ADR-278 canary-isolation sentence, and the unchanged first-boot tuple in `cloud-init.yml`.
`EXPECTED_POSTURE` is deliberately not the anchor (it excludes volumes and env by design).

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-278 (no new ADR): `## Boundary mechanics` "Canary isolation" bullet gains the sentence
that the deploy canary neither mounts the token dir nor sets `SOLEUR_EGRESS_REAPER` and that
`lib/docker-run-tuple.py` pins both; the phrase "a second consumer of the shared token dir" is
reworded. This is a clarification of the intended state, not a new decision.

### C4 views

No C4 impact. Checked in `model.c4`, `views.c4` and `spec.c4`: external human actors - none added
(the opted-in workspace owner and the agent session are existing); external systems/vendors - none
added (the public internet and the gateway are modeled: `platform.webapp.egressForwarder ->
platform.infra.egressGw -> publicInternet`, with the token-directory ro-mount already described on
`egressGw`); containers/data stores - the host token directory is already described within
`egressGw`, no new store; actor-to-surface access relationships - unchanged. No derived cardinality
moves, so `plugins/soleur/test/c4-count-parity.test.sh` is run as the check.

### Sequencing

The ADR sentence is authored now (describes the state this PR ships); nothing is deferred.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6; this one is filled (single-user incident).
- Draft PR #10501 edits `ci-deploy.sh`, `docker-run-tuple.py` and `docker-run-tuple.test.sh`.
  Conflict points: `MIN_ROWS`, the `TUPLES` block, `run_checks`. After either lands, the other
  rebases and re-measures `MIN_ROWS` (do not guess it).
- `MISSING_DECLARED` exactness also applies to `ports` and to the canary/first-boot tuples; verified
  against the current tree that every tuple already carries its full declared set (prod and canary
  carry all of `_COMMON_ENV` plus `NODE_OPTIONS`; first-boot declares two env names), so the new arm
  is green before the spec change.
- Rows that lose options without failing tokenization (K12) or leave a bare duplicate site (K13n) emit extra `MISSING_DECLARED` lines; harmless for positive-only needles (verified by prototype: full battery passes), but keep the skip on `UNPARSEABLE_OPTION` sites. Select the `ci-deploy.test.sh` prod line with the trailing-space `--name soleur-web-platform ` and assert the selection is non-empty. Prototype-measured `MIN_ROWS` was 223 for the earlier, larger row set; re-measure after the cuts. P12 is three chained mutators (`m_del` the mount, `m_ins_at` it before the workspaces volume, `m_repl` REAPER to `--env`).
- Do not make the new tuple lines depend on a shell variable: the checker rejects expansions in
  option position (`UNPARSEABLE_OPTION`); use the literal strings.
- Never read the real prod env-file or Doppler values while verifying; the absence assertion needs
  only the query transport credentials injected by its own wrapper.

## Review-Round Amendments (2026-10-19, 11-seat panel + CTO rulings R6-R15)

Scope grew beyond the original "4 lines + tuple". Everything below was found by the review panel at `f3d0f70fb1`
and ruled by the CTO agent (`decision-challenges.md` rows 6-15). The PR is HELD as draft until the merge-blocking set
lands and the pre-merge proofs below are recorded.

1. **In-process Glob/Grep gap (R6, P1, merge-blocking).** `extractToolPath` never saw Glob `pattern` / Grep `glob`, so
   an absolute one listed the (now mounted) token dir with no `path`. A token FILE NAME is the credential. Fixed in this
   PR: new `server/tool-pattern-checker.ts` (`patternEscapesWorkspace`, deny by syntax: absolute, `~`, `..` segment,
   per brace/comma alternative; Grep regex `pattern` is content and is NOT checked), wired into `sandbox-hook.ts` and
   `permission-callback.ts`; RED-first tests in `tool-pattern-checker.test.ts`, `sandbox-hook.test.ts`,
   `permission-callback-sdk-tools.test.ts`. A new module (not a new export in `tool-path-checker.ts`) because 30+ test
   files mock that module with closed factories. Hashed token file names stay a follow-up.
2. **Token file mode (R8, P1, merge-blocking).** Measured against the pinned `ubuntu/squid@sha256:6a097f68...`: the auth
   helper runs as `proxy` (uid 13) and gets `Permission denied` on a `0600` uid-1001 token file (OK on `0644`, OK as
   root), so every session token would have been rejected even with the mount. Fixed: `egress-forwarder.ts` writes
   `0644` + explicit `chmodSync`; RED-first test in `web-egress.test.ts`. The host cron probes had masked this (root
   writes, default umask). `egress-gateway-bootstrap.sh` is NOT touched (gateway artifact hash).
3. **Boot reaper vs host probe tokens (R10).** The reaper skips `probe-*` files younger than 10 minutes (stale ones are
   still swept); test in `web-egress.test.ts`.
4. **Mask under a real bind mount (R7).** Local docker repro (alpine + bubblewrap, `--security-opt seccomp=` the repo's
   `seccomp-bwrap.json`, uid 1001, populated 0711 bind-mounted dir): the app-side process lists the token and
   `.gw-target`; an UNMASKED bwrap sandbox still sees them (positive control); with `--tmpfs` over the mount the listing
   is empty, reads are ENOENT, `.gw-target` is hidden, a write lands in the sandbox-private tmpfs and the host dir is
   untouched. AppArmor was NOT enabled on the repro host: the AppArmor interaction is unverified locally. `/workspaces`
   is already a bind mount that the same sandbox tmpfs-masks in production, which is the precedent that makes this
   non-blocking by itself.
5. **Wording (R12, R13).** The canary mount omission is least privilege, not a restoration (history: the original
   design mounted it on the canary; a merge-conflict resolution deleted all of it). "Neither" is proven for the start
   ARGV only; env-file injection and `EGRESS_TOKEN_DIR` are stated residuals in the checker docstring and ADR-278.
6. **Checker tests (R15).** K27a-h (canary/first-boot members, two-members-at-once, tokenization failure), K26a-b into
   the H1 stub, set-safe `declared - set(got)`, and `check_declared` no longer piles MISSING_DECLARED onto a tuple that
   already reds UNPARSEABLE_OPTION. `MIN_ROWS=233`.
7. **Post-deploy gate (R9), replaces tasks 7.5/7.6 as the ordering.** (a) `docker inspect` prod shows the mount and
   `SOLEUR_EGRESS_REAPER=1`, canary shows neither. (b) From a NON-entitled test workspace, with a positive control that
   a `probe-*` token exists host-side: sandboxed Bash `ls`/`cat`/`touch` in the dir, in-process Glob with an absolute
   pattern, in-process Grep with an absolute `glob`, and Read/Write/Edit of `.gw-target` are all denied or empty.
   (c) Only then enable the entitled dispatch and require the first `soleur-egress-gw` allow row. Mint NO real token and
   do NOT run the egress-audit-enable runbook's first entitled dispatch until (b) is green. The Better Stack
   absence check alone is vacuous when no entitled session dispatches.
8. **Flipped inline after the second-reviewer gate DISSENTed (cost-of-filing, 1 file each):** `.gw-target` is ignored
   unless its host is in 172.31.100-103.0/24 (`GW_SUBNET_RE` in `egress-forwarder.ts`), and token-file paths are scrubbed
   from the three `rmSync` error reports (`withoutTokenPath`), each with a RED-first test in `web-egress.test.ts`.
9. **Deferred (one checklist tracker, R14, date trigger):** the agent-visible 'web access enabled but unavailable'
   addendum, the missing Sentry alert rule for `web-egress-forwarder-spawn`, the toggle's missing runtime state, hashed
   token file names together with the stale `egress-gateway-bootstrap.sh` comment (gateway artifact hash), and extending
   the checker's CENSUS gaps (control flow, `docker rename|start|restart|update` verbs, indirect docker word, start
   sites outside the scanned set). Scalar posture-flag required-ness was flipped inline (item 10).
10. **Scalar posture flags are now required per tuple (CTO withdrew E4 after the second-reviewer DISSENT):** `-d`,
   `--log-driver`, `--restart`, `--env-file`, `--add-host` on all three tuples; `--init`, `--memory`, `--memory-swap` on
   canary and prod (first-boot has none by design). Before this, deleting `--env-file` (prod with zero secrets) or
   `--memory` passed the checker at rc 0. Rows K28a-i; `MIN_ROWS=251`.
