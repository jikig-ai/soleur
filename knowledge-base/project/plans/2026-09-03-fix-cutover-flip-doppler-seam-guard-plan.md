---
title: "inngest-cutover-flip.service: a Doppler secret NAME is an arbitrary-command-as-root path"
date: 2026-09-03
slug: fix-cutover-flip-doppler-seam-guard
branch: feat-one-shot-7761-cutover-flip-seam-guard
issue: 7761
type: bug
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

`inngest-cutover-flip.sh` reads several test-fixture command seams out of its process
environment and executes their values. Its unit starts the script through `doppler run`
against the `prd` config with no `User=`, so every secret in that Doppler config arrives
as an environment variable in a root process. A secret whose name matches one of those
seams therefore selects the command the flip unit executes — inside the same code path
that performs the Redis flush and records the flush latch.

This plan hardens the seams so that a value arriving by that route is refused, while the
test harness — which controls the whole environment — keeps working.

No `spec.md` exists for this branch, so `lane:` could not be carried forward and is defaulted to
`cross-domain` (TR2 fail-closed). `closes:` is deliberately absent from the frontmatter: the fix is
not delivered by the merge — see the note under `## Acceptance Criteria` on `Ref` versus `Closes`.

## Research Insights

### Premise Validation (Phase 0.6)

Every reference the issue body cites was re-checked this session.

| Cited | Probe | Result |
|---|---|---|
| `#7761` | `gh issue view 7761 --json state` | OPEN — the target is live |
| `#7754` | `gh pr view 7754 --json state,mergedAt` | MERGED 2026-09-02 (the probe fix that surfaced this) |
| `#7695` | `gh issue view 7695 --json state` | OPEN — inngest volume recut |
| `#7228` | `gh issue view 7228 --json state` | CLOSED — the dark-bind incident |
| `#6178` | `gh issue view 6178 --json state` | OPEN — the dedicated-host cutover is incomplete |
| "byte-identical to `main`" | `git diff origin/main -- <script> <unit>` | Empty diff — confirmed pre-existing |
| `inngest-cutover-flip.service` / `.sh` | direct read | Both present at the cited paths |

Mechanism-vs-ADR check: `grep` over `knowledge-base/engineering/architecture/decisions/` for the
proposed mechanism's keywords returns no ADR that decided a seam-gating approach, and no ADR whose
rejected-alternatives table contains one. ADR-100, ADR-106, ADR-146 and ADR-150 govern the cutover
FSM's behaviour, not its environment trust boundary. The mechanism is unconsidered, not rejected.

### Property List and Cut List (Phase 0.6b)

The ask proposes two mechanisms. Restated as properties:

- **P1** — a party whose only capability is write access to a Doppler config cannot cause any
  `doppler run`-wrapped unit to execute or source a command of their choosing.
- **P2** — the same party cannot defeat the cutover FSM's safety predicates: the monotonic
  anti-double-`FLUSHALL` latch, the post-flush `DBSIZE == 0` assertion, the verify probe's target,
  and the done-owner marker.
- **P3** — every existing fixture seam still works for the two test suites that drive it.
- **P4** — a seam added to a covered script later does not silently re-open P1 or P2.

Mechanisms weighed against what is already on `main`:

| Mechanism | Property | Already covered on `main`? |
|---|---|---|
| `doppler run --only-secrets <list>` on the unit | P1, P2, P4 for that unit | **Yes, as an established pattern** — `apps/web-platform/infra/cloud-init-registry.yml:1273` already runs `doppler run --project soleur-registry --config prd --only-secrets BETTERSTACK_LOGS_TOKEN --no-fallback -- /usr/local/bin/zot-log-shipper.sh`. This is prior art in this repo, not a novel mechanism. |
| In-script fixture-marker gate on the seam set | P1, P2 regardless of caller; P4 with a drift assertion | No. `grep` found no script in the repo that validates a seam value's shape or gates a seam on a marker before use. |
| Seam value must be an absolute path under a fixture-only prefix | subset of P1 | **Cut.** Redundant once the marker gate holds: the marker cannot be satisfied without a file on the host, and a party who cannot create a file also cannot place a binary under the prefix. Keeping both would be two mechanisms for one property. |
| A marker whose *name* Doppler cannot represent (e.g. lowercase) | P1 | **Cut — rests on an unverified premise.** See "Doppler name rules" below. |

### Doppler capability verification

Two claims were probed; they did not come back the same.

- **`doppler run --only-secrets` — VERIFIED.** Present in the installed CLI (v3.75.3) per
  `doppler run --help`. It *excludes* every unlisted secret rather than merely prioritising the
  listed ones, and the default on a listed-but-absent secret is to exit non-zero — the opposite
  behaviour is the opt-in `--no-exit-on-missing-only-secrets`. The mechanism is therefore
  fail-closed on drift.
- **Doppler secret-NAME constraints — UNVERIFIED.** No authoritative statement was found on
  whether lowercase, hyphens, or a leading digit are accepted, nor whether any such rule is
  enforced by the API or only by the dashboard. A dashboard-only rule is not a security boundary.
  **Consequence for this plan:** any design that gates the seams on a marker whose *name* Doppler
  supposedly cannot represent is disqualified. The marker must instead rest on something Doppler
  demonstrably cannot do at all — create a file on the host.

### The seam inventory is wider than the issue names

The issue names three seams. A repo-wide sweep (excluding `knowledge-base/` and `*.test.sh`)
found **no production setter for any seam** — every one is fixture-only, and therefore every one
is Doppler-suppliable. In `apps/web-platform/infra/inngest-cutover-flip.sh`:

*Command seams — the value is executed:*

| Seam | Site |
|---|---|
| `CUTOVER_FLAG_SET_CMD` | `:84` `"$CUTOVER_FLAG_SET_CMD" "$value"` |
| `CUTOVER_SYSTEMCTL_CMD` | `:94` |
| `CUTOVER_CURL_CMD` | `:162` |
| `CUTOVER_REDIS_CLI_CMD` | `:324` |
| `CUTOVER_LOGGER_CMD` | `:292`, `:311`, `:354`, `:467` — `"${CUTOVER_LOGGER_CMD:-logger}"`, ungated default-substitution. Note `record_flush_latch` uses a **bare** `logger` at `:427`, `:434`, `:442`, so the seam is not the only logger path — no security gap, since bare is the safe form, but the inventory is not "every logger call" |

*Value and path seams — no execution, but each defeats a named safety property:*

| Seam | Site | What it defeats |
|---|---|---|
| `INNGEST_CUTOVER_LATCH` | `:387` | Repoint the monotonic latch at a path that will never exist and the "already flushed" predicate reads false — a **second `FLUSHALL` against a live Redis, with no code execution at all** |
| `INNGEST_CUTOVER_LATCH_MOUNT` | `:390` | The script uses `${VAR-default}` so an explicitly *empty* value disables the mount gate "for tests". A Doppler secret with an empty value does exactly that |
| `CUTOVER_REDIS_DBSIZE` | `:334` | Short-circuits the post-flush `DBSIZE == 0` assertion — an unflushed Redis certifies as clean |
| `CUTOVER_HEALTH_URL`, `CUTOVER_GQL_URL` | `:132`, `:133` | Point the verify probe at a chosen endpoint — a dark host certifies as serving and reaches terminal `done` |
| `CUTOVER_DONE_OWNER_MARKER` | `:240` | Defeats the #7228 host-identity marker |
| `CUTOVER_VERIFY_WINDOW_S`, `CUTOVER_VERIFY_INTERVAL_S`, `INNGEST_CUTOVER_STATE`, `CUTOVER_FLIP_FLAG` | `:146`, `:147`, `:62`, `:69` | Timing, state-slot path, FSM input |

A guard scoped to the five command seams alone would leave `INNGEST_CUTOVER_LATCH` open, i.e. it
would carry a name about privilege escalation while its assembly stopped short of the
data-destruction path in the same file.

### Sibling instances of the same class

The sweep found the defect is not unique to this unit. Every row below is a `doppler run`-wrapped
unit with **no `User=`** whose script takes a command out of the environment:

| Unit | Config | Script and seam |
|---|---|---|
| `container-restart-monitor.service:28` | `soleur/prd` | `container-restart-monitor.sh:58-61` — `ENV_FILE` reaches `set -a; . "$ENV_FILE"`. **Sourcing**, so no executable bit and no separate binary are needed |
| `cron-egress-firewall.service:35` | `soleur/prd` | `cron-egress-nftables.sh:32,134` — `RESOLVE_SCRIPT` |
| `cron-egress-resolve.service:32` | `soleur/prd` | `cron-egress-resolve.sh:46,325` — `LOADER` |
| `git-data-gc.service:42` | `soleur/prd_git_data` | `git-data-gc.sh:14` — `GIT_DATA_EMIT` reaches `"$EMIT"` at eight call sites |

Also noted, under `User=deploy` rather than root: the doppler-wrapped `ExecStartPre` at
`inngest-bootstrap.sh:1089` runs `inngest-server-flip-guard.sh`, whose `GUARD_UNIT_FILE`,
`GUARD_POSTGRES_URI` and `GUARD_DONE_OWNER_MARKER` seams let a config writer defeat the
arm-atomicity guard that blocks a prod-URI start.

**The "not affected" claim in the issue holds, and the repo already knows why.** The probe unit
from #7754 is authored at `inngest-bootstrap.sh:719` and is deliberately *not* doppler-wrapped;
its own comment at `:713-717` states the reason in the issue's own terms — `doppler run` injects
every secret in the config as an env var, which would make the fixture seams settable by anyone
with Doppler write access. The pattern is understood in this codebase; the flip unit is the
instance that did not follow it.

### Test harness and CI registration

- `apps/web-platform/infra/inngest-cutover-flip.test.sh` — stubs every seam inside a `mktemp -d`
  and passes them on one `env` line to `bash "$TARGET"`. Counters `PASS`/`FAIL`, helpers
  `assert_eq` / `assert_contains` / `assert_absent` / `assert_logger`, and a vacuity floor
  `MIN_ASSERTIONS=102` that must be raised in lockstep when cases are added.
- `apps/web-platform/infra/inngest-cutover-latch.test.sh` — a **second** suite that drives the
  same seams (`:158-174`). Any marker the fix introduces must be set here too, or this suite goes
  red for the right reason in the wrong place.
- Registration: `run-registered-suites.sh:208-210` *derives* its suite list by grepping
  `.github/workflows/infra-validation.yml` for `run: bash …/*.test.sh`. A suite absent from that
  workflow runs in no runner at all while reading as coverage. Both cutover suites are already
  registered (`infra-validation.yml:796-803`), so extending them needs no workflow edit; a *new*
  suite file would.

### Drift couplings that must not break

- `inngest-server-flip-guard.test.sh` awk-derives the FSM's `start_server` states from
  `inngest-cutover-flip.sh` and asserts a subset relation against the guard's ALLOW list. The
  workflow documents this as a deliberate tripwire (`infra-validation.yml:816-822`): a legitimate
  refactor *will* red it. The fix must not disturb the textual shape that derivation reads.
- `scripts/cutover-inngest.sh:160-177` greps a fixed set of `"reason":"<token>"` literals out of
  the marker stream. A new refusal token is invisible to the operator's no-SSH channel until it is
  added there.

### Existing precedent to copy

- Shape-guard idiom: `git-data-transport-wrapper.sh:58-85` — fail-closed metacharacter and
  traversal rejection *before* any `readlink`, then `readlink -f` canonicalisation with a
  containment check against a root, then a direct-child check as defence in depth.
- Test-mode marker idiom: `INFRA_CONFIG_TEST_MODE` in `infra-config-apply.sh:666,866`, with the
  suite exporting it at `infra-config-apply.test.sh:90`. Note the recorded failure mode at
  `infra-config-apply.test.sh:1765-1768`: an *inverted* guard left all 171 assertions green,
  which is why a reachability arm exists.

### Applicable institutional learnings

- `knowledge-base/project/learnings/2026-09-02-i-built-a-host-discriminator-out-of-an-absence-and-fixtured-the-absence.md`
  — a discriminator built on an absence is fixturable to be vacuous: the fixture omits the thing,
  the test passes, production has it. Directly cautions against gating on "the seam is unset".
- `knowledge-base/project/learnings/2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md`
  and `2026-06-02-fixture-bare-substring-marker-over-slurp-and-orphan-test-infix.md` — infra suites
  are enumerated, not globbed; an unregistered suite reads as coverage while running nowhere.
- `knowledge-base/project/learnings/2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of.md`
  — a mutation battery only catches mutations its author imagined; fixtures chosen for legibility
  exclude the states where the guard matters.
- `knowledge-base/project/learnings/2026-05-11-drift-guard-scoping-extract-call-site-not-widen-walk.md`
  — put the guard at one chokepoint rather than letting each call site grow its own validation.
- `knowledge-base/project/learnings/2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md`
  — a RED fixture must be reachable only by the branch under test.
- `knowledge-base/project/learnings/2026-07-08-inngest-cutover-authoring-review-and-observability-allowlist.md`
  — this FSM's pre/post-side-effect windows are where its past defects lived.

### Open code-review overlap

`gh issue list --label code-review --state open` returned 63 issues; none names any file this plan
edits. Recorded so the next planner can see the check ran.


### The host is live and the timer is firing (measured, not assumed)

The issue reads as latent — "the host serves nothing today". The scheduler is indeed braked, but the
unit carrying the defect is not:

- `hcloud_server.inngest` exists (`inngest-host.tf:273`, no `count`/gate) and the host is up on the
  private network. Its creation is gated only by the dispatch-only `-target=` allowlist in
  `apply-web-platform-infra.yml`, not by a variable.
- `INNGEST_CUTOVER_FLIP` currently reads `rolled-back`, so `inngest-server.service` is held stopped
  by the flip guard's brake.
- **`inngest-cutover-flip.timer` is never disabled — that is a deliberate invariant**
  (`OnBootSec=30s`, `OnUnitActiveSec=30s`; the P0-1 rationale at `inngest-cutover-flip.sh:36-39`).
  So `doppler run --config prd -- inngest-cutover-flip.sh` runs **as root every 30 seconds on a
  live production host**, taking the `noop-rolled-back` arm.

The primitive is armed and firing. What is currently absent is an exploit, not an exposure.

Measured live secret names in `soleur-inngest/prd` (`doppler secrets --only-names`): seven
non-`DOPPLER_` names — `BETTERSTACK_LOGS_TOKEN`, `INNGEST_CUTOVER_FLIP`, `INNGEST_DIAGNOSTIC_BOOT`,
`INNGEST_EVENT_KEY`, `INNGEST_POSTGRES_URI`, `INNGEST_REDIS_PASSWORD`, `INNGEST_SIGNING_KEY` — plus
`DOPPLER_CONFIG`, `DOPPLER_ENVIRONMENT`, `DOPPLER_PROJECT`. No seam name is present. **High
severity, low current likelihood.**

### The largest hole is not any of the fifteen seams

`doppler run` injects a name of the writer's choosing, and bash honours names this script never
mentions. A secret named **`BASH_ENV`** is sourced by bash *before line 1 executes*. `PATH`
re-points every production arm — `systemctl`, `redis-cli`, `curl`, `logger`, `jq`, `mountpoint`,
`doppler` — *after* any in-script `unset`. `LD_PRELOAD` and `IFS` likewise.

This is decisive: **no in-script guard can close this class**, because it runs too late by
construction. It is the reason the injection-side bound is not optional and not merely
defence-in-depth.

Countervailing fact, and the reason the seam enumeration still matters: the enumerated set is
**closed and provably complete**. Every parameter expansion in the script resolves to exactly
sixteen externally-supplied names — the fifteen seams plus the two real production inputs
`INNGEST_CUTOVER_FLIP` and `INNGEST_REDIS_PASSWORD`. Nothing else. A closed set is what makes both
an enumerated unset list and a completeness tripwire defensible.

### The unit is the only root-`doppler run` unit in the repo with no sandboxing

`git-data-gc.service:57-66` is its structural twin — root, `doppler run`, `Environment=HOME=/root`
— and carries `ProtectSystem=strict`, `PrivateTmp=yes`, `NoNewPrivileges=yes`, `ReadWritePaths=`.
Its comment at `:58-60` even names `inngest-cutover-flip.service` in its list of root-doppler units.
`inngest-redis.service` and `webhook.service` are hardened too. The flip unit copied the
`HOME=/root` line and none of the rest. `ProtectHome` is deliberately **not** set anywhere here:
that same comment records that it masks `/root` and breaks the Doppler CLI.

### Couplings verified against the code this session

| Coupling | Constraint on this change |
|---|---|
| `inngest.test.sh:1570-1571` | Asserts `grep -qF 'doppler run --config prd'` matches **contiguously** and `^ExecStart=.*--project` does not. New flags must go **after** `--config prd`, and no `--project` may be added |
| `inngest-server-flip-guard.test.sh:383-402` | Derives FSM `start_server` sites by walking `flip.sh` and attributing the nearest preceding `flag_set`; pins `EXPECTED_START_SITES=2`. Add no `start_server` site, and insert no `flag_set` between `flag_set flushed` (`:496`) and `start_server` (`:497`) |
| `cutover-inngest-workflow.test.sh:1511-1530` | Enforces emitter ⊆ the `--grep` reason set in `scripts/cutover-inngest.sh:160-177`, extracting quoted literals from `emit_state` calls. A reason emitted through a **variable** slips the extraction silently |
| `cutover-inngest-workflow.test.sh:265-285` | F.2 disjointness: each flip asset must be present on an OCI/cloud-init surface and **absent** from every webhook/config-bundle surface. Routing this fix through the pull bundle reds CI by design |
| `apps/web-platform/infra/vector.toml:198` | The `inngest-cutover-flip` logger tag is already allowlisted, so a raw `logger` line needs no Vector change |
| `run-registered-suites.sh:192` | Derives its suite list from `infra-validation.yml`; an unregistered suite runs in no runner while reading as coverage |
| `cat-inngest-cutover-state.sh:15,24` | A second production **reader** of `INNGEST_CUTOVER_STATE` and `INNGEST_CUTOVER_LATCH` with byte-identical defaults. Irrelevant to an in-script gate, but these two names cannot be refactored into a shared helper without touching it |
| Four test call sites | `inngest-cutover-flip.test.sh:146,288,329` and one at `inngest-cutover-latch.test.sh:158-176`, all `env VAR=… bash "$TARGET"`. `:288` and `:329` are separate re-execs that do **not** route through `run_flip`, so a marker added only at `:146` leaves six assertions red |
| `cutover-inngest-workflow.test.sh:1511-1528` | A **third** coupled suite: derives the emitter reason vocabulary from `flip.sh` and asserts `emitter ⊆ grep set`, with a non-vacuity floor of ≥ 6 non-`noop` reasons at `:1521`. The raw-logger choice keeps this suite untouched; an `emit_state` reason would force an edit here and in `cutover-inngest.sh` |
| Assertion floors have **zero** headroom | Measured this session: flip suite `102 passed` against `MIN_ASSERTIONS=102` (`:630`); latch suite `45 passed` against `LATCH_MIN_ASSERTIONS=45` (`:354`). Any assertion added must raise its floor; any removed reds immediately |

### Guard placement is a hard constraint, and the obvious position is wrong

Lines `62, 132, 133, 146, 147, 240, 387, 390` are column-1 top-level assignments evaluated at
source time; every remaining seam is read inside a function body and therefore deferred until
`run_flip` at `:588`. So a single chokepoint does exist — but **not** immediately after
`set -Eeuo pipefail` at `:58`. `LOG_TAG` is `readonly` at `:60`, so a gate at `:59` that references
`$LOG_TAG` for its marker is an unbound-variable fatal under `set -u`: the script dies with no
marker and no flag transition.

**The correct position is after `readonly SERVER_UNIT` (`:61`) and before `STATE_FILE` (`:62`)**,
the first seam read. That covers all fifteen.

Two consequences of sitting there:

- `emit_state` (defined at `:341`) does not exist yet, so the gate cannot use it — which turns out
  to be fortunate, see the marker fork below.
- **The ERR trap is not installed yet.** `trap on_unexpected_exit ERR` is at `:523`, inside
  `run_flip`. Any non-zero status inside the gate kills the script under `set -Eeuo pipefail` with
  no marker and no transition — exactly the #5934 telemetry-blind class the FSM header at `:40-47`
  exists to prevent. The gate must therefore be written to never return non-zero incidentally:
  `n=$((n+1))` rather than `(( n++ ))` (which returns 1 when `n` is 0), no `[[ … ]] && …` as the
  last statement of a loop body, and a `[[ -f … && -r … ]]` predicate before any read of the
  sentinel rather than an unguarded `head`.

### The refusal marker has only one safe emitter

Emitting through `emit_state` is **disqualified, and dangerously so**: `emit_state` truncates the
state slot (`printf '%s\n' "$json" > "$STATE_FILE"`, `:352`), and
`flush_already_performed`'s legacy-compatibility disjunct reads exactly that slot for
`.flag == "done"` (`:401-404`). On a host carrying only the legacy slot and no latch file — the arm
fixtured alone at `inngest-cutover-latch.test.sh:239-246` — a single refusal marker would **erase
the only record that a `FLUSHALL` ever ran**, and the next `armed` would flush a live production
Redis. That is the #7228 P0-5 catastrophe, re-introduced by the guard meant to prevent it.

So the refusal is a **raw `logger -t inngest-cutover-flip` line**. It writes no state slot, needs no
`emit_state`, and deliberately stays outside the FSM reason vocabulary — which also means
`scripts/cutover-inngest.sh`'s `--grep '"reason":"…"'` set needs no edit, because a raw line is not
the JSON those greps match. Admitting a token there would be dead code.

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| The seams at risk are `CUTOVER_REDIS_CLI_CMD`, `CUTOVER_SYSTEMCTL_CMD`, and the flag-read seam | Fourteen seams are Doppler-suppliable, several of which defeat safety predicates with no execution at all — notably `INNGEST_CUTOVER_LATCH`, which gates the anti-double-`FLUSHALL` latch | The in-script gate covers all fifteen. Scoping to the named three would leave a data-destruction path open in the same file |
| "A name-shape guard is enough" | It is not. `BASH_ENV`, `PATH`, `LD_PRELOAD` and `IFS` are honoured by bash without the script naming them, and `BASH_ENV` is sourced before line 1 | The injection-side bound is the primary control; the in-script gate is the part that travels with the file |
| "the host serves nothing today" | The scheduler is braked, but the flip timer is never disabled by design and the unit runs as root every 30s on a live host | Severity is high with low current likelihood, and rollout is in scope rather than deferred |
| Suggested direction: gate the seams in the script | Already-accepted repo patterns exist on both sides — `--only-secrets` at `cloud-init-registry.yml:1273` and `registry-zot-inventory.yml:387-389`, and a fail-closed **name allowlist for this exact Doppler project** at `cloud-init-inngest.yml:604-611` | Adopt both. The allowlist framing is the strongest one available: this change is the **runtime half of a control the repo already accepted at provision time** |
| The probe seam in the sibling unit is not affected | Confirmed. `inngest-bootstrap.sh:715-717` records the identical reasoning for keeping that unit unwrapped | Out of scope, untouched |
| Nothing said about other units | Four more `doppler run`-wrapped root units take a command out of the environment, one of which *sources* it | The injection-side bound extends to them; the in-script gate does not |

## Alternatives Considered

Three reviewers (DHH, code-simplicity, CPO) converged on cutting M1 entirely. That challenge is
recorded below and in `decision-challenges.md`; the resolution adopted here keeps the operator's
requested mechanism but replaces its implementation with one that costs almost nothing.

| Approach | Distinct property | Verdict |
|---|---|---|
| **M2 — `doppler run --only-secrets` on the unit** | Closes the entire injection class **including names nobody enumerated** — the only mechanism here that reaches `BASH_ENV`, `PATH`, `LD_PRELOAD` and `IFS`, because it filters before `exec`. Costs **zero** test changes: both suites invoke `bash "$TARGET"` directly, never through `doppler run` | **Adopted. This is the fix.** |
| **M1 — in-script gate, keyed on argv** | Defends the script on any invocation path, and is what a reviewer reading `flip.sh` alone can see. Retained because the issue asked for it; reshaped because the sentinel form was not worth its cost | **Adopted, reshaped** — see below |
| **M3 — systemd sandboxing** | Converges the unit on the shape every sibling root-`doppler run` unit already has | **Adopted for `NoNewPrivileges` and `ProtectSystem`; `PrivateTmp` is gated on a Phase 0 measurement** |
| **Guard 2 — unit-shape bound** | P1/P4 at repo scale, and the answer to "a refactor could delete `--only-secrets`" | **Adopted as an extension of an existing scanner**, not a new suite |
| C — marker whose *name* Doppler cannot represent | Same as M1 | **Rejected.** Rests on a premise about Doppler name validation that no authoritative source establishes, and that cannot be probed without a write to a live config |
| D — seam values restricted to a fixture-only path prefix | Subset of M1 | **Cut as redundant** |
| E — re-run the cloud-init boot allowlist as an `ExecStartPre` | Detects a foreign name at poll time | **Rejected.** Puts a Doppler API round-trip on the 30-second path to a destructive operation |
| F — add `User=` to the unit | Reduces blast radius | **Rejected as the fix.** Root is explicit and justified at `inngest-cutover-flip.service:42-45`; it would leave the class intact at lower privilege |
| G — rename every seam to a `CUTOVER_SEAM_*` prefix | Structural gate coverage | **Not adopted.** The prefix-scoped derivation achieves it without a rename touching three files |
| **H — `--no-fallback` alongside `--only-secrets`** | None | **Cut.** See below |

### M1, reshaped: argv instead of a sentinel file

The sentinel protocol was the expensive part of this plan, and it was expensive for a property argv
buys for free. `inngest-cutover-flip.sh` takes **no top-level positional arguments** — every `$1`,
`$@` and `$*` in the file is function-local (`:82`, `:94`, `:162`, `:263`, `:324`, `:343`, `:424`).
So the gate's predicate becomes:

```bash
[[ ${1:-} == --fixture-seams ]]
```

This is strictly better than the sentinel on every axis that mattered:

- **Unforgeable by *any* environment writer**, not merely a non-root one — argv is not the
  environment. The whole forgery analysis, the ownership and mode checks, and M1's dependence on
  `PrivateTmp` all disappear.
- **Zero filesystem syscalls in the pre-ERR-trap window.** The gate runs ~460 lines before
  `trap on_unexpected_exit ERR` is installed at `:523`, and the sentinel form put a `stat` and a
  file read in exactly that window — the one place this FSM must never die silently. A single
  `[[ ]]` cannot fail.
- **Four call-site edits, not a fixture protocol.** The suites already invoke `bash "$TARGET"` at
  `inngest-cutover-flip.test.sh:159,293,334` and `inngest-cutover-latch.test.sh:176`; each gains one
  argument and every existing assertion behaves identically.

### The observation problem dissolves with it

An earlier revision added `PATH` shadowing of six real binaries so refusal cases would be
observable, because a refusal unsets the harness's own instruments. That was the single most
dangerous item in the plan: `infra-validation.yml:167` runs `ubuntu-24.04`, which has a real
`systemctl`, and the workflow comment at `:794` records the existing safety property in as many
words — *"It mocks systemctl + redis inside a `mktemp -d`, so no real Redis is reached and no
FLUSHALL is executed."* That guarantee comes precisely from seaming commands explicitly and never
touching `PATH`. Shadowing would have inverted it on the suite that drives `run_preflush_flip`.

It is also unnecessary. A refusal is observable as **the absence of the seam's own side effect**: set
`CUTOVER_SYSTEMCTL_CMD` to a stub that writes a canary file, omit `--fixture-seams`, and assert the
canary does not exist. No instrument is needed to observe an absence. And the refusal cases drive
the `noop-unset` arm (`:580-581`), which touches neither `systemctl` nor `redis-cli`, so nothing
destructive is reachable even in principle.

**`PATH` shadowing is cut in full.**

### H — why `--no-fallback` is cut

The flag disables reading *and* writing the fallback file. The plan argues at length that this unit
must never hard-fail, because its 30-second poll is the only control channel on a braked host —
that is why `--no-exit-on-missing-only-secrets` is adopted. `--no-fallback` reinstates the same
hard-fail on a different axis: a Doppler API blip now stops the poll. It buys no property here. The
fallback file lives at `DOPPLER_CONFIG_DIR=/tmp/.doppler` (`inngest-bootstrap.sh:783`), root-owned
and unreachable by a party whose only capability is Doppler config write, and `--only-secrets`
filters the injected set regardless of source. The cited prior art
(`cloud-init-registry.yml:1273`) is a five-minute log shipper with no control-channel role.

### The standing challenge: should M1 exist at all?

Recorded rather than resolved, because it argues against the direction the issue itself proposed.

**The case for cutting it.** There is exactly one production caller of this script
(`inngest-cutover-flip.service:54`); every other reference is a test harness, a comment, or the
install path. So M1's coverage is a strict subset of M2's on the only path that exists, and M1's
last remaining justification — "a refactor could delete `--only-secrets` from the unit" — is
precisely what Guard 2 mutation row 1 asserts. By the plan's own cut rule, applied to mechanism D,
that is two mechanisms for one property.

**The case for keeping it.** The issue asked for a seam gate in the script, and after the argv
reshape M1 costs roughly fifteen lines plus four one-argument call-site edits — no sentinel, no
`PATH` shadowing, no new suite, no pre-trap filesystem work, and no change to any of the 147
existing assertions. At that price, defence that travels with the file against a root-exec primitive
on a destructive path is cheap enough to keep, and the reviewers' objections were to the sentinel
implementation far more than to the idea.

**Disposition:** keep M1 in its argv form as the plan's default, and surface the cut as a
User-Challenge for the operator rather than deciding it here.

## Architecture Decision (ADR/C4)

### ADR

**Amend `ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` rather than mint a new
ADR.** ADR-100 owns this host's trust model and already carries a Decision-6a amendment from #7228,
and this change is a divergence from its recorded boundary rather than an unrelated decision. The
amendment's line: *a Doppler config is an untrusted **name**-space for host units, not only an
untrusted value-space* — so a `doppler run` unit enumerates what it injects, and a script whose
behaviour an environment value can redirect gates that value on something the secrets store cannot
produce.

This supersedes the earlier intent to mint a new ordinal, which also removes the ordinal-collision
risk this plan previously carried.

The amendment must also record the invariant's **stated limit**, so it is a known boundary rather
than a future red build: `--only-secrets` cannot bound a unit whose secret *name* is per-host,
because the tracked unit cannot name it and the flag is fail-closed on an absent name. The four
indirect-name probe units are the exemption class, and they need a different mechanism if they are
ever to be bounded.

Two facts confirm the amendment is the right vehicle. ADR-100 already carries dated
`## Addendum — <date> (#N) — <title>` sections with `###` subsections, so there is an established
shape to follow rather than invent. And its addendum of 2026-08-25 (#7674) already records
**"Code delivery to the dedicated host is REPLACE-ONLY (a standing constraint)"** — the same
conclusion this plan's Apply Path reaches independently from
`cutover-inngest-workflow.test.sh`'s disjointness guard and the cloud-init install block. The
delivery constraint is therefore not a new claim this plan is making; it is an existing recorded
constraint this plan is obeying, which is exactly the kind of continuity that belongs in an
amendment rather than a fresh ADR.

### C4 views

Container view. `model.c4:578` carries the `doppler -> inngest` edge, and its description presents
the dedicated `soleur-inngest` project isolation as the safety property. That is falsified in one
respect: isolation bounds *which* secrets exist, not what a writer to that project can cause the
host to do. The edit records the distinction and the new per-unit bound.

Completeness enumeration, checked by reading all three model files rather than a keyword grep:

- **External human actors** — none added. The party is a Doppler config writer, an authority over an
  already-modelled system, not a new actor.
- **External systems** — Doppler is modelled (`model.c4:252`). No new vendor.
- **Containers / data stores** — `inngest` (`:192`), `inngestPostgres` (`:196`), `inngestRedis`
  (`:200`) all modelled. No new store.
- **Access relationships that change** — one: `doppler -> inngest` (`:578`). Siblings
  `doppler -> hetzner` (`:506`) and `doppler -> zotRegistry` (`:584`) were read and need no change;
  `:584` already describes a three-secret admitted set, which is the shape this change adopts.
- **Rendering** — `views.c4:37` already includes `platform.infra.inngest`, so no `include` line is
  added. `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` run after the edit.

### Sequencing

The ADR amendment and the C4 edit land in this PR. The decision is true the moment the unit and
script change.

## Infrastructure (IaC)

### Terraform changes

No resource, variable, or provider is added. The only `.tf`-adjacent edits are the two image digest
pins in `cloud-init-inngest.yml`, which are `user_data` inputs rather than new resources.

### Apply path

The flip assets are **not** in the infra-config pull bundle, and that is enforced rather than
incidental: `cutover-inngest-workflow.test.sh:265-285` asserts each flip asset is present on an
OCI/cloud-init surface and absent from every webhook surface. They are baked into the inngest
bootstrap image, extracted by `docker cp` at `cloud-init-inngest.yml:816-819`, and installed by
`inngest-bootstrap.sh:855-871`.

Chosen path (b) — cloud-init plus a re-provision, because the install block runs from cloud-init
once per instance:

1. Merge the code change.
2. Push a `vinngest-vX.Y.Z` tag; `build-inngest-bootstrap-image.yml` (`on.push.tags`) builds and
   pushes the image.
3. Bump **both** hard-coded digest pins together — `cloud-init-inngest.yml:677` (GHCR) and `:721`
   (zot mirror).
4. Dispatch `apply-web-platform-infra.yml` with `apply_target=inngest-host`. `hcloud_server.inngest`
   carries no `lifecycle.ignore_changes=[user_data]`, so the `user_data` change forces the replace.

Every step is dispatchable (`git push`, `gh workflow run`); none is a hand-off.

**Blast radius, and why the window is favourable.** The host is at `rolled-back` and serving
nothing, so the replace costs no availability. The `/mnt/data` volume re-attaches rather than being
recut, so the monotonic anti-double-`FLUSHALL` latch survives — measured and recorded at
`scripts/cutover-inngest.sh:1555`. The boot isolation self-check re-runs on replace and passes
against today's seven admitted names.

### Distinctness / drift safeguards

Each `--only-secrets` list is derived from its script's own environment read-set and cross-checked
against the boot allowlist at `cloud-init-inngest.yml:604-611`, not hand-written. Because
`--no-exit-on-missing-only-secrets` removes the loud failure, Guard 1's completeness tripwire and
Guard 2's row 3 are the mechanisms that keep list and read-set in step. `--no-fallback` is set so a
stale local fallback file cannot re-supply withheld names.

### Vendor-tier reality check

Not applicable. No vendor resource is created; `--only-secrets` is a flag on the already-installed
Doppler CLI (v3.75.3).

## User-Brand Impact

- **If this lands broken, the user experiences:** a scheduler host whose flip unit fails on its
  30-second poll and — in the worst mode — fails *invisibly*. The unit's only control channel is its
  own marker stream, so a failure that stops the script before it emits leaves the operator with
  silence rather than a stalled state to read. Delivery compounds it: the fix reaches the host only
  through a destroy-and-recreate of `hcloud_server.inngest`, and a failed create strands the host
  entirely. The anti-double-`FLUSHALL` latch survives only if `/mnt/data` re-attaches as modelled,
  and #7695 — *nothing clears a standing flush latch today* — is still open, so a latch mishandled
  across the replace means the next `armed` flushes a live Redis. Beyond the flip unit, an
  `--only-secrets` list that omits a name its script reads is **silent at run time**, and two of the
  affected sibling units are `cron-egress-firewall` and `cron-egress-resolve`, which load the host's
  egress nftables allowlist.
- **If this leaks, the user's data and workflow are exposed via:** a root shell on the dedicated
  scheduler host, obtained by anyone who can write a secret *name* into `soleur-inngest/prd`. The
  sharpest exposure is present-tense and does not wait for the cutover: `INNGEST_POSTGRES_URI` has
  carried the **prod** DSN since 2026-07-23, because `op=arm` overwrites it and `op=rollback` has no
  inverse for that write (`inngest.tf:249-253`, ADR-100 addendum 2026-08-20). That DSN reaches the
  live inngest config and run-history database as the postgres owner (`model.c4:198`). The same
  shell reads `INNGEST_REDIS_PASSWORD` and sits inside the code path that runs `FLUSHALL` against
  the durable queue, which carries inbound-email triage payloads — Article 30 Processing Activity 27
  — so third-party correspondent personal data transits the host, and the queue's AOF is plaintext
  at rest on `/mnt/data` (a ledgered exception, tracking #6894). What isolation *does* hold is worth
  recording: the measured secret set contains no `SUPABASE_SERVICE_ROLE`, so the main application
  database is out of reach. ADR-100's project isolation is doing its job on that axis.
- **Brand-survival threshold:** `single-user incident`

`requires_cpo_signoff: true`, and this sign-off was obtained at plan time: **signed off, with
conditions**. The reviewer's substantive note is that by the ladder's own definition this exposure
is closer to `aggregate pattern` — a `FLUSHALL` destroys in-flight jobs for every tenant, and the
email payloads belong to correspondents who are not Soleur users at all; the tenant count being one
today is an adoption-stage accident, not a property of the blast radius. The label nevertheless
stays `single-user incident`, because the ladder is **inverted at this rung**: `single-user
incident` requires CPO sign-off, fires `user-impact-reviewer` at review, and blocks `gh pr ready` on
a degraded review, while `aggregate pattern` fires none of the three. Relabelling upward would buy
strictly weaker enforcement. That inversion is a defect in the ladder rather than in this plan, and
it is filed as a follow-up rather than worked around here.

`user-impact-reviewer` is invoked at review time.

## Implementation Phases

Scope note: this plan ships **one host's fix**. The four sibling units found by the sweep move to a
follow-up issue — see "Why the siblings split out" below.

### Phase 0 — preconditions, measured not assumed

1. Re-read the live secret names with `doppler secrets --only-names -p soleur-inngest -c prd` and
   confirm no seam name has appeared since this plan was written.
2. Read the FSM state and confirm the timer is live, through the no-shell channel:
   `doppler secrets get INNGEST_CUTOVER_FLIP -p soleur-inngest -c prd --plain`, plus a
   `scripts/betterstack-query.sh` read of the flip marker stream. A Better Stack read-path outage is
   not evidence about the host; the Doppler read works through it.
3. Confirm that withholding the config's `DOPPLER_PROJECT` / `DOPPLER_CONFIG` /
   `DOPPLER_ENVIRONMENT` **secrets** breaks nothing. The conclusion held under review, but the
   mechanism is **not** what an earlier draft of this plan cited, so check it rather than inherit it:
   for *this* host the env file is pre-created by `cloud-init-inngest.yml`, not by the
   `inngest-bootstrap.sh` heredoc (`inngest-bootstrap.sh:793-800` says so; the heredoc itself is at
   `:781-786`). That file carries `DOPPLER_TOKEN`, `DOPPLER_CONFIG_DIR`,
   `DOPPLER_ENABLE_VERSION_CHECK` and `DOPPLER_PROJECT` — and **no `DOPPLER_CONFIG` and no
   `DOPPLER_ENVIRONMENT`**, so the claim that the withheld secrets duplicate EnvironmentFile values
   is false for two of the three. What makes the withholding safe is simpler and should be verified
   directly: `--config prd` is on the command line, and the script's secret-write child passes
   `--project` and `--config` explicitly at `:86-87`. Excluding `INNGEST_POSTGRES_URI`, which the
   flip script never reads, is a real narrowing.
4. **`PrivateTmp` is not optional here, and the spelling is load-bearing.**
   `inngest.test.sh:200` states the house rule in as many words — *"#6536 ROUND 2: EVERY
   doppler-wrapped unit MUST set `PrivateTmp=true`"* — and `:232` asserts
   `^PrivateTmp=true$` by regex. `/etc/default/inngest-server` sets
   `DOPPLER_CONFIG_DIR=/tmp/.doppler`, and `inngest-bootstrap.sh:372-388` records why that path is
   *only* safe under a private `/tmp`. So adopt it, spelled **`true`**, not the `yes` that
   `git-data-gc.service:64` uses — that file is the lone `yes` in the repo and every inngest-family
   unit uses `true`. What remains to measure is the consequence, not the decision: a fresh private
   `/tmp` per start means the Doppler fallback cache cannot persist across fires, so record the
   per-fire fetch behaviour on a 30-second cadence and confirm it is acceptable.
5. Run both cutover suites green and record the floors. Measured this session: flip `102 passed`
   against `MIN_ASSERTIONS=102`, latch `45 passed` against `LATCH_MIN_ASSERTIONS=45`. Zero headroom
   on both.

### Phase 1 — failing tests first

Write both guards' mutation matrices as executable cases before either guard exists, so each matrix
is derived from the design rather than from what the implementation turns out to look like. Every
row red at the end of this phase.

### Phase 2 — the in-script gate (the contract, before its consumers)

In `inngest-cutover-flip.sh`, **after `readonly SERVER_UNIT` (`:61`) and before `STATE_FILE`
(`:62`)** — the first seam read, and the earliest position at which `$LOG_TAG` is safe to reference
under `set -u`:

- Gate on **argv**: the seams are honoured only when the script was invoked with
  `--fixture-seams`. `inngest-cutover-flip.sh` takes no top-level positional arguments — every `$1`,
  `$@` and `$*` in the file is function-local (`:82`, `:94`, `:162`, `:263`, `:324`, `:343`, `:424`)
  — so the argument is free, and it is unforgeable by any environment writer because argv is not the
  environment.
- Otherwise `unset` all **fifteen** seam names and count what was unset. `unset` is the single
  operation that restores all three expansion idioms in this file — `${V:-d}`, `${V-d}` at `:390`,
  and `${V+x}` at `:69` and `:334` — to their production arm, which is why one chokepoint replaces
  fifteen call-site checks. Do **not** unset `INNGEST_CUTOVER_FLIP` or `INNGEST_REDIS_PASSWORD`;
  they are the real inputs.
- When at least one seam was present and the flag absent, emit a **raw**
  `logger -t inngest-cutover-flip "SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED …"` line. Raw, not
  `emit_state`: that function does not exist yet at this point in the file, and keeping the event out
  of the FSM reason vocabulary avoids the `cutover-inngest.sh` parity coupling entirely. The tag is
  already allowlisted at `vector.toml:198`, so no Vector change is needed.
- The block runs ~460 lines before `trap on_unexpected_exit ERR` is installed at `:523`, so under
  `set -Eeuo pipefail` any stray non-zero exits the script silently — no marker, no transition, the
  #5934 class this FSM exists to prevent. The argv form helps by construction (a `[[ ]]` test cannot
  fail and touches no filesystem), but the unset loop still must use `n=$((n+1))` rather than
  `(( n++ ))`, and must not end a loop body with `[[ … ]] && …`.
- **The gate must never touch `PATH`, `BASH_ENV`, `IFS` or `LD_PRELOAD`.** Those are `--only-secrets`'
  job, and sanitising them here would silently blind the refusal tests rather than redden them.
- Add no `start_server` call site, and insert no `flag_set` between `flag_set flushed` (`:496`) and
  `start_server` (`:497`).

### Phase 3 — harness

**(a) Pass the flag at all four call sites.** `bash "$TARGET"` becomes
`bash "$TARGET" --fixture-seams` at `inngest-cutover-flip.test.sh:159`, `:293`, `:334` and
`inngest-cutover-latch.test.sh:176`. `:293` and `:334` are separate re-execs that do not route
through `run_flip`, so editing only the first leaves six assertions red. All 147 existing assertions
then behave exactly as they do today.

**(b) Observe a refusal as an absence, not through an instrument.** A refusal case sets a seam to a
stub that writes a canary file, omits `--fixture-seams`, and asserts the canary does **not** exist.
Nothing needs to be observed *through* the seams the gate just unset, so no `PATH` shadowing is
introduced — which matters, because `infra-validation.yml:167` runs `ubuntu-24.04` with a real
`systemctl`, and the workflow comment at `:794` records the existing safety property in as many
words: *"It mocks systemctl + redis inside a `mktemp -d`, so no real Redis is reached and no
FLUSHALL is executed."* That guarantee comes from seaming commands explicitly and never touching
`PATH`.

**(c) Refusal cases drive only the no-op arms.** With the seams unset, the host-path defaults
(`STATE_FILE` → `/var/lock/…`, `LATCH_FILE` → `/mnt/data/…`, `DONE_OWNER_MARKER` → `/var/lib/…`) are
unreachable on a runner: `record_flush_latch`'s `mkdir -p` at `:432` and `record_done_owner`'s at
`:247` both fail, and the verify seams fall back to a 240-second window (`:146-147`). So a refusal
case runs with the flag **absent**, taking the `noop-unset` arm (`:581-582`), which touches neither
`systemctl` nor `redis-cli` nor the latch, completes immediately, and cannot reach anything
destructive. Forward-flip regression continues to run **with** `--fixture-seams`, exactly as today.
Clean up `/var/lock/inngest-cutover-flip.state` in `setup_case`/`teardown_case` so a refusal case's
fallback slot write cannot bleed into a later case.

Raise `MIN_ASSERTIONS` and `LATCH_MIN_ASSERTIONS` by exactly the number of assertions added.

### Phase 4 — bound the injection at the unit

Rewrite the flip unit's `ExecStart` in the repeated-flag form the repo already uses
(`registry-zot-inventory.yml:387-389`), with every new flag **after** `--config prd` so
`inngest.test.sh:1570-1571`'s contiguous-substring assertion still matches and no `--project`
appears: `--only-secrets INNGEST_CUTOVER_FLIP`, `--only-secrets INNGEST_REDIS_PASSWORD`, and
`--no-exit-on-missing-only-secrets`. That last flag diverges from house convention and carries a
comment naming `noop-unset` as the reason. **`--no-fallback` is deliberately not set** — see
Alternatives, row H.

### Phase 5 — systemd sandboxing

Add `NoNewPrivileges=yes`, `ProtectSystem=strict` and `PrivateTmp=true`, converging the unit on the
shape `git-data-gc.service:57-66` already has — this unit copied only the `HOME=/root` line. Do not
add `ProtectHome`: `git-data-gc.service:63-64` records that it masks `/root` and breaks the Doppler
CLI.

**The writable-path directives are the sharp edge of this phase, and the obvious spelling is wrong
twice over.** Neither `/var/lib/inngest-cutover` nor `/mnt/data/inngest-cutover` exists on a fresh
host; their only creators are the lazy `mkdir -p` inside the script itself at `:247` and `:432`.

- Naming a non-existent directory in `ReadWritePaths=` makes systemd fail mount-namespace setup, so
  the unit dies on **every** 30-second fire after the replace — no marker, on the one host with no
  other control channel. That is this plan's own worst case, delivered by this plan, on the first
  boot of the change.
- `-`-prefixing does **not** rescue it. The path is then simply not made writable, so under
  `ProtectSystem=strict` the script's own `mkdir -p` hits a read-only filesystem and the FSM aborts
  `latch-unrecordable` on every fire instead.

The correct shape is `StateDirectory=inngest-cutover`, under which systemd itself creates and
read-write-mounts `/var/lib/inngest-cutover`, plus `ReadWritePaths=/var/lock /mnt/data`, naming the
mount rather than the subdirectory the script creates inside it. Since `/mnt/data` is mounted
`nofail`, the absent-mount case is covered by scenario 19 rather than left to inspection.

Nothing in CI currently catches this class: the repo's only `systemd-analyze verify` gate is scoped
to git-data units (`infra-validation.yml:1465-1468`), which is why AC10 and scenario 19 add one for
this unit.

### Phase 6 — record

Amend ADR-100 and apply the `model.c4:578` description correction, then run the C4 tests.

### Phase 7 — full battery

Run the whole infra suite set, not the shards this diff touches: Guard 2's scan, the
`inngest-server-flip-guard` awk lockstep, the F.2 disjointness guard, `inngest.test.sh`'s unit-string
assertions and the reason-vocabulary parity assert all live outside the touched-file set.

### Phase 8 — rollout, in scope

Merging changes nothing on the live host, so the change is not delivered until this phase runs.

1. Push a `vinngest-vX.Y.Z` tag; `build-inngest-bootstrap-image.yml` (`on.push.tags`) builds the
   image.
2. Bump **both** digest pins together — `cloud-init-inngest.yml:677` (GHCR) and `:721` (zot mirror).
3. Dispatch `apply-web-platform-infra.yml` with `apply_target=inngest-host`. `hcloud_server.inngest`
   carries no `lifecycle.ignore_changes=[user_data]`, so the `user_data` change forces the replace.
4. **Commit the post-replace status probe as part of this PR**, rather than assembling the check in
   session. `scripts/followthroughs/inngest-host-not-serving-7674.sh` reports a not-serving shape for
   a correctly-braked host, so it is the wrong probe here. A production host destroy-and-recreate
   whose verification cannot be re-run is an unauditable change; the probe is a deliverable, not a
   convenience. It asserts: `INNGEST_CUTOVER_FLIP` still reads `rolled-back`, at least two
   `noop-rolled-back` markers carry timestamps after the replace, and the flush latch is intact.
5. Close #7761 once the probe passes.

### Why the siblings split out

The sweep found four more `doppler run`-wrapped root units whose scripts take a command from the
environment: `container-restart-monitor.service:28`, `cron-egress-firewall.service:35`,
`cron-egress-resolve.service:32` and `git-data-gc.service:42`. Bundling their fix here was the
plan's original intent and is wrong, for a reason the plan already argues elsewhere:

- **Phase 8 delivers none of them.** They install via `soleur-host-bootstrap.sh` (web hosts) and
  `cloud-init-git-data.yml` (the git-data host); `apply_target=inngest-host` touches neither. They
  would merge green and sit undeployed — and web-1 carries `lifecycle{ignore_changes=[user_data]}`
  and has never re-run cloud-init, so "until the next re-provision" is indefinite. That reproduces
  inside this PR exactly the failure mode Phase 8 exists to prevent, for four units, silently, while
  the ADR records a mitigation deployed on one host of five.
- **The risk profiles differ in kind.** This PR's unit gates an irreversible `FLUSHALL` on a host
  carrying a prod DSN. None of the four does. The plan's own sentence — *"none of them gates an
  irreversible destructive operation"* — is the argument for the split.
- **Three of the four read `SENTRY_*` and `RESEND_API_KEY` and exist to alert.** With
  `--no-exit-on-missing-only-secrets`, a mis-derived list disables alerting silently, and their
  `ExecStart` already carries a fallback arm that runs the script with zero injected secrets — so
  "the script's non-seam read-set" is not a derivable quantity there the way it is here, and the
  boot-allowlist cross-check does not apply (they target `soleur/prd` and `soleur/prd_git_data`).
- **Their lists are genuinely hard to author, and getting one wrong is worse than leaving it
  unbounded for now** — the indirect-loop-list read and the value-based LUKS redactor above are both
  in this set.

The follow-up is nevertheless **high value, not housekeeping**, and the reason should not be lost:
`prd_git_data` declares only two secrets of its own (`git-data-luks.tf:86-92,118-128`) but is a
Doppler **branch config under the `prd` environment**, and a branch config inherits the entire root
set — a verified, still-open finding
(`knowledge-base/project/learnings/security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md`,
audited under #6167). So `git-data-gc.service` today injects roughly 129 secrets, including
`SUPABASE_SERVICE_ROLE_KEY`, into a script running on the host that holds every connected user's
source code. That makes it the largest single narrowing available anywhere in this class, and it is
also the one sibling whose failure would be **loud** — it alone has no conditional wrap and no
fallback arm, so a bad list fails the unit and fires `OnFailure=git-data-gc-failure.service`.
Sequence it first in the follow-up. While there, correct the now-false least-privilege comment at
`git-data-luks.tf:36-42`.

They get their own issue, with per-unit read-set derivation and their own delivery path.

## Files to Edit

- `apps/web-platform/infra/inngest-cutover-flip.sh` — the argv gate
- `apps/web-platform/infra/inngest-cutover-flip.service` — bounded injection + sandboxing
- `apps/web-platform/infra/inngest-cutover-flip.test.sh` — `--fixture-seams` at three call sites, refusal cases, floor
- `apps/web-platform/infra/inngest-cutover-latch.test.sh` — `--fixture-seams` at one call site, floor
- `apps/web-platform/infra/cloud-init-inngest.yml` — both image digest pins (`:677`, `:721`)
- `.github/workflows/infra-validation.yml` — register the Guard 2 suite
- `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` — amendment
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `:578` edge description

## Files to Create

- `apps/web-platform/infra/doppler-injection-bound.test.sh` — Guard 2
- `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh` — the Phase 8 post-replace probe

## Acceptance Criteria

Every criterion is a post-condition on file state or command output over a fixture this plan
controls. None asserts the absence of an ambient signal, and none can be flipped by a process this
plan does not mention (`cq-ac-must-not-depend-on-concurrent-sessions`).

### Pre-merge (PR)

1. `bash apps/web-platform/infra/inngest-cutover-flip.test.sh` exits 0, results line reads
   `0 failed`, `PASS` at or above the raised `MIN_ASSERTIONS`.
2. `bash apps/web-platform/infra/inngest-cutover-latch.test.sh` exits 0, results line reads
   `0 failed`, `PASS` at or above the raised `LATCH_MIN_ASSERTIONS`.
3. Both floors increased by exactly the number of assertions added, verified by diffing each literal
   against its green run's `PASS` count.
4. `bash apps/web-platform/infra/doppler-injection-bound.test.sh` exits 0 and reports a scanned-unit
   count at or above its floor, with a per-surface breakdown covering all four authoring surfaces.
5. Every row of both mutation matrices, applied to a scratch copy, drives its named suite to a
   non-zero exit. Recorded as a table of row → suite → observed exit code.
6. `grep -c 'doppler-injection-bound.test.sh' .github/workflows/infra-validation.yml` returns 1, and
   `bash apps/web-platform/infra/run-registered-suites.sh` lists it among the suites it derived.
7. `grep -qF 'doppler run --config prd' apps/web-platform/infra/inngest-cutover-flip.service`
   succeeds and `grep -cE '^ExecStart=.*--project'` on that file returns 0.
8. The unit's `ExecStart` carries `--only-secrets INNGEST_CUTOVER_FLIP`,
   `--only-secrets INNGEST_REDIS_PASSWORD` and `--no-exit-on-missing-only-secrets`, all after
   `--config prd` and before the `--`, and does **not** carry `--no-fallback`.
9. The unit contains `NoNewPrivileges=yes` and `ProtectSystem=strict`, does not contain
   `ProtectHome`, and every `ReadWritePaths=` entry naming a directory not created by cloud-init,
   Terraform or the bootstrap carries the `-` prefix.
10. `systemd-analyze verify` on the unit reports no error.
11. The gate appears at a line number greater than that of `readonly SERVER_UNIT` and less than that
    of the `STATE_FILE=` assignment — asserted by shape, not a hardcoded number.
12. Running the script **without** `--fixture-seams` and with a command seam pointed at a
    canary-writing stub leaves the canary absent; running it **with** the flag creates the canary.
13. `bash apps/web-platform/infra/inngest-server-flip-guard.test.sh` exits 0.
14. `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` exits 0, and
    `git diff --stat origin/main -- scripts/cutover-inngest.sh` is empty.
15. `bash apps/web-platform/infra/inngest.test.sh` exits 0.
16. The full infra battery runs green.
17. ADR-100 carries the amendment, and `git diff origin/main --name-only` shows no new
    `ADR-*.md` file.
18. `model.c4:578`'s description no longer presents project isolation as the safety property, and
    `c4-code-syntax.test.ts` and `c4-render.test.ts` pass.
19. `lint-guard-contract.py` and `lint-infra-no-human-steps.py` pass against this plan.
20. The PR body carries `Ref #7761`, not `Closes #7761`.
21. A follow-up issue exists for the four sibling units, and another for the threshold-ladder
    inversion recorded under User-Brand Impact.

### Post-merge (automated, Phase 8)

22. The `vinngest-vX.Y.Z` tag is pushed and the image build completes green.
23. Both digest pins reference the same new digest, asserted by comparing the two literals to each
    other.
24. `apply_target=inngest-host` completes green.
25. `bash scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh` exits 0 — it asserts
    `INNGEST_CUTOVER_FLIP` still reads `rolled-back`, at least two `noop-rolled-back` markers carry
    post-replace timestamps, and the flush latch is intact.
26. `gh issue close 7761` runs only after 25 holds.

**On `Ref` versus `Closes`.** The merge does not deliver the fix — the script and unit reach the host
only through the image build and replace in Phase 8, which run after the tag is on `main`. A
`Closes` would auto-close at merge, before the remediation ran.

## Guard Contract

### Guard 1 — the argv seam gate and its completeness tripwire

**Property.** No environment value can select a command the flip script executes, or a path, URL or
verdict it trusts, unless the script was invoked with `--fixture-seams` — and the set of names the
gate covers equals the set of seam names the script actually reads.

**Assembly.** One gate block between `:61` and `:62`, ahead of every seam read. Coverage is
structural rather than a snapshot: a tripwire derives the seam-name set from the script by shape and
asserts it equals the gate's unset list plus `{INNGEST_CUTOVER_FLIP}`. Three constraints, each of
which the naive form gets wrong:

- **Scope to the `CUTOVER_` and `INNGEST_CUTOVER_` prefixes.** Unscoped, it sweeps in
  `${INNGEST_REDIS_PASSWORD:-}` (`:326`) and would force it into the unset list, breaking
  `redis-cli -a ""` against a password-protected Redis. `INNGEST_CUTOVER_FLIP` is inside the prefix,
  which is why the expected set is the unset list **plus** that one name — exactly 16 prefix-scoped
  names, 15 of them seams. The argv form contributes nothing here, and that is one of its
  advantages: a sentinel keyed on `CUTOVER_FIXTURE_ROOT` would have put the gate's *own input*
  inside the derivation's prefix, making the expected set 17 and reddening the tripwire on the first
  green run of the thing it guards.
- **Strip comments first.** `:66` and `:388` carry `${VAR+x}` and `${VAR-…}` in prose.
- **Match the whole expansion grammar, not the three idioms this file happens to use today.**
  `INNGEST_CUTOVER_LATCH_MOUNT` at `:390` is `${NAME-default}` deliberately (`:389`), so a shape
  covering only `:-` and `+x` misses precisely the seam whose empty value disables the mount gate.
  But stopping at those three repeats the same mistake one level up: `${NAME:+…}`, `${NAME:=…}`,
  `${NAME:?…}`, bare `${NAME}` and bare `$NAME` are all invisible to it, and a future author using
  any of them re-opens P4 silently. Match `${NAME` followed by `}` or any of
  `:-`, `-`, `:+`, `+`, `:=`, `=`, `:?`, `?`, **plus** bare `$NAME`. The bare forms are redundant in
  today's file — all ten bare reads also appear in a default form — but that is a property of this
  file today, not of the shape.

**Companion assertion — the prefix scope's own blind spot.** Because the derivation is
prefix-scoped, a future seam named outside both prefixes is invisible to it, and property P4 would
not hold. The tripwire is therefore paired with an assertion that **no unprefixed externally-supplied
expansion appears in command position** anywhere in the script. Without this pairing, Alternative G's
rejection does not stand.

**Mutation matrix.**

| # | Edit to the system under test | Must go |
|---|---|---|
| 1 | Delete the gate block entirely | RED |
| 2 | Remove exactly one name from the unset list, leaving the rest correct — the second-member row | RED, at the tripwire |
| 3 | Add a new read in an idiom the derivation does **not** already cover — e.g. `${CUTOVER_NEW_THING:+x}` or a bare `$CUTOVER_NEW_THING` — without adding it to the list. Using `${…:-}` here would make the row pass by construction, since that idiom is already matched; the row must test the grammar's edge, not its centre | RED, at the tripwire |
| 4 | Add a new **unprefixed** seam read in command position — the companion-assertion row | RED |
| 5 | Move the gate below `STATE_FILE` (`:62`) — the order row. Specified against line 62, not "after `read_flag`": `read_flag` at `:67` is only a definition and its seam is not evaluated until `:525`, so a gate moved below it still precedes every deferred read and would stay green | RED |
| 6 | Make the argv predicate always true | RED |
| 7 | Flag absent but zero names unset — the gate's own dispatch, against a floor on the unset count | RED |
| 8 | Have the gate sanitise `PATH` or `BASH_ENV` — the row that keeps the gate from silently blinding its own refusal tests instead of reddening them | RED |

**Harness rows.**

- Delete one RED case's assertion → red at the `MIN_ASSERTIONS` floor.
- Must-PASS non-canonical: a case passing `--fixture-seams` with seams pointed at a second,
  differently-named `mktemp -d` → passes. Without this the matrix cannot distinguish a correct gate
  from one that refuses everything.

### Guard 2 — every `doppler run` unit bounds its injected set

**Property.** Every unit in this repo whose `ExecStart`, `ExecStartPre` or `ExecStartPost` passes
through `doppler run`, and whose target script uses an environment value in **command position**
(executed or sourced), enumerates its secrets with `--only-secrets` — or appears in an
explicitly-reasoned ack list whose cardinality is pinned.

Four scoping decisions the naive property gets wrong, each verified against the repo:

- **`ExecStartPre` counts.** The flip-guard is delivered as
  `ExecStartPre=/usr/bin/doppler run …` (`inngest-bootstrap.sh:1089`), and this plan's own research
  names its `GUARD_UNIT_FILE` / `GUARD_POSTGRES_URI` seams. A scan anchored on `^ExecStart=` misses
  the one instance the plan documented as vulnerable — while the guard exists precisely because
  "the failure mode is a sixth nobody enumerated."
- **The literal `doppler run` is not the population.** Five units never contain that string: they
  resolve the binary first, as
  `D="$(command -v doppler || true)"; … exec "$D" run --project soleur --config prd -- …` —
  `cron-egress-firewall.service:35`, `cron-egress-resolve.service:32`,
  `cron-egress-alarm@.service:23`, `container-restart-monitor.service:28`, and the web-host
  `vector.service` (`soleur-host-bootstrap.sh:741`). A grep for the literal misses roughly a third
  of the population, and the floor row would still pass on what remained.
- **`runcmd` invocations are excluded.** The boot isolation self-check at
  `cloud-init-inngest.yml:604-611` must see *all* names to do its job; demanding a bound there would
  self-defeat the provision-time control this change is the runtime half of.
- **An exemption class is required, not optional.** Four probe units resolve their own secret by
  indirect expansion over a per-host key name that Terraform bakes in and the tracked unit never
  contains — `export WEB_ZOT_CONSUMER_URL="${!WEB_ZOT_CONSUMER_URL_KEY}"`
  (`web-zot-consumer-probe.service:38`, `inngest-consumer-probe.service:40`,
  `web-git-data-probe.service:28`, `web-private-nic-guard.service:29`; the key expands to e.g.
  `WEB_ZOT_CONSUMER_URL_WEB_1` per `server.tf:683,734,820,871`). A literal `--only-secrets` list in a
  tracked unit **cannot name a secret whose name is per-host**, and because the flag is fail-closed
  on a listed-but-absent name, the same unit shipped to a second web host would break — on the
  multi-host path the fleet is actively opening. This is a real limit of the invariant, not a false
  positive to be predicated away, and it belongs in the ADR as a stated boundary rather than being
  discovered by a red build.

**Known false positives, each needing a must-PASS row:** `inngest-bootstrap.sh:991` (`inngest start`
— and note its SQLite fail-safe arm substitutes `unset INNGEST_POSTGRES_URI` at `:1076`, which is
load-bearing *because* the name is present in the injected environment, so a list omitting it would
silently change that arm's meaning), the two `vector.service` bodies, and `inngest-redis.service:31`.

**Assembly.** A shape scan over unit definitions on all four authoring surfaces — standalone
`*.service`, `*.sh` heredocs, `*.tf` heredocs, and cloud-init `content: |` blocks. **Lift the
enumerator rather than writing one:** `credential-persist-home-guard.test.sh:571-605`'s
`enumerate_units()` covers exactly these four surfaces and carries two non-obvious behaviours a fresh
scanner gets wrong silently — the `.tf` `\n`-unescape (terraform inline arrays are `\n`-escaped
single-line strings a naive scanner reads as one line and matches nothing, failing open) and the
in-place `.terraform/` prune at `:580`. Copy it and its helpers (`mk_unit` `:506-520`,
`heredoc_units` `:532-534`, `cloudinit_blocks` `:536-562`), swapping the sandboxing predicate for a
`doppler run` one. It must be copied, not sourced: `run-registered-suites.sh:422-434` records that
infra suites are inlined by policy (ADR-177 §A3) because the sandbox is a single-file copy. Take the
ack-list-with-reasons, ack-cardinality and per-population floor discipline from
`inngest.test.sh:1617-1730`.

**Mutation matrix.**

| # | Edit to the system under test | Must go |
|---|---|---|
| 1 | Drop `--only-secrets` from the flip unit | RED |
| 2 | Add a new `doppler run`-wrapped unit with an exec-seam script and no bound — the second-member row | RED |
| 3 | Remove one name from a unit's list while its script demonstrably reads that secret — the row covering the residual `--no-exit-on-missing-only-secrets` introduces, which is otherwise silent at run time. It checks an **authored** list against a lower bound of names the script provably reads; it is not, and cannot be, a complete derivation (see below) | RED |
| 4 | Move `--only-secrets` after the `--`, where it is a child argument rather than a `doppler run` flag | RED |
| 5 | Make the scan match zero units — the guard's own dispatch, against a per-surface floor | RED |
| 6 | Replace a secret list with the empty string | RED |
| 7 | Remove an entry from the ack list without bounding its unit — the cardinality row | RED |

**Harness rows.**

- A must-RED fixture that is a `\n`-escaped unit inside a **`.tf` heredoc**. Without it the surface
  this repo has already been burned on stays untested, and rows 2 and 5 are satisfiable by a scanner
  that misses `.tf` entirely.
- Remove the floor assertion itself → red under the anti-vacuity contract (ADR-193).
- Must-PASS non-canonical: a unit using the conditional `command -v doppler` wrap with
  `--only-secrets` inside the `exec` arm → passes. The contract is the bound, not one spelling.

**Coupling to Guard 1.** Row 3's "non-seam read-set" is defined by subtracting Guard 1's unset list
from the script's read-set. Guard 2 consumes that list rather than re-deriving it; otherwise a naive
read-set would demand every seam appear in `--only-secrets`, the inverse of the intent.

**The lists are authored and commented, never derived — and this is the single most important
correction review made to this plan.** Two independent exhaustive derivations over the same two
sibling scripts produced *different* answers, in both directions, and both misses are silent under
`--no-exit-on-missing-only-secrets`:

- `cron-egress-resolve.sh:149-157` reads three names by **indirect expansion over a literal loop
  list** — `for var in SENTRY_INGEST_DOMAIN NEXT_PUBLIC_SUPABASE_URL SUPABASE_URL; do
  val="${!var:-}"`. No `$NEXT_PUBLIC_SUPABASE_URL` expansion exists anywhere in the file, so any
  grep-shaped derivation sees bare loop-list tokens and drops them. Omitting them does not fail
  loud: `:154-155` logs a warning and forces the tick additive-only with pruning suspended — an
  egress firewall that quietly stops pruning.
- `git-data-emit`'s redactor is **value-based**, because the LUKS passphrase is high-entropy and
  matches no pattern (`cloud-init-git-data.yml:142-150`). Under a list of
  `BETTERSTACK_LOGS_TOKEN` alone, `_devalue` degrades to `cat`, and repack stderr rides into the
  emit's detail argument (`git-data-gc.sh:138,142`) — so a passphrase appearing in git's stderr
  would ship **unredacted to Sentry and Better Stack**.

So a derivation cannot carry the loudness the fail-open flag gives up. Every list is written by a
human, carries a comment naming why each entry is there, and Guard 2 checks it against a lower
bound rather than claiming to reproduce it.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_INNGEST_CUTOVER_* markers on the logger tag inngest-cutover-flip; the new seam-refusal marker rides the same tag"
  cadence: "every 30s while the flip timer is active, which is always, by the P0-1 invariant"
  alert_target: "Better Stack Logs source 2457081, read by scripts/betterstack-query.sh"
  configured_in: "apps/web-platform/infra/inngest-cutover-flip.sh; tag allowlisted at apps/web-platform/infra/vector.toml:198"

error_reporting:
  destination: "journald -> on-host Vector shipper -> Better Stack Logs source 2457081 (the no-shell channel for this host, and the layer covering every on-host mode below); CI-side failures surface through infra-validation.yml"
  fail_loud: "partially, stated precisely — the seam refusal emits its own marker before continuing on real sources; a doppler run that cannot resolve a listed secret now WARNS rather than exits, because --no-exit-on-missing-only-secrets is required to keep the designed noop-unset state working. Guard 2 row 3 restores loudness for that case at CI time rather than run time"

failure_modes:
  - mode: "A Doppler secret name collides with a seam name on the running host"
    detection: "the SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED marker, emitted from inside the unit"
    alert_route: "journald -> Vector -> Better Stack source 2457081 (layer: on-host Vector shipper)"
  - mode: "A Doppler secret name bash honours without the script naming it (BASH_ENV, PATH, LD_PRELOAD, IFS)"
    detection: "not detectable in-script by construction — prevented by --only-secrets withholding the name before exec; the boot allowlist at cloud-init-inngest.yml:604-611 catches it on the next provision"
    alert_route: "prevention plus the provision-time FATAL; no runtime alert is claimed"
  - mode: "A unit's --only-secrets list omits a secret its script reads, silent at run time"
    detection: "Guard 2 mutation row 3"
    alert_route: "infra-validation.yml job failure on the PR"
  - mode: "The gate refuses a seam the harness legitimately set"
    detection: "both cutover suites go red"
    alert_route: "infra-validation.yml job failure on the PR"
  - mode: "A future seam is added without being added to the gate list, prefixed or unprefixed"
    detection: "Guard 1's completeness tripwire and its companion unprefixed-expansion assertion"
    alert_route: "infra-validation.yml job failure on the PR"
  - mode: "The hardened unit fails systemd namespace setup after the replace and never fires"
    detection: "absence of fresh noop-rolled-back markers post-replace, plus systemd-analyze verify pre-merge (AC10)"
    alert_route: "the Phase 8 committed probe, plus the existing inngest heartbeat for host-level silence"

logs:
  where: "Better Stack Logs source 2457081 via the host's Vector journald shipper; GitHub Actions job logs for the CI guards"
  retention: "as configured for source 2457081; CI logs per GitHub retention"

discoverability_test:
  command: "bash apps/web-platform/infra/inngest-cutover-flip.test.sh"
  expected_output: "a final results line reading 0 failed, with the passed count at or above the raised MIN_ASSERTIONS floor"
```

## Test Scenarios

1. Seam set, no `--fixture-seams`, flag absent — the canary is not written; the script takes
   `noop-unset` and exits 0.
2. Same, and the raw refusal marker is emitted on the `inngest-cutover-flip` tag.
3. No seam set, no flag — the ordinary production path emits **no** refusal marker.
4. `--fixture-seams` present — all 147 existing assertions behave exactly as today.
5. `INNGEST_CUTOVER_LATCH` set without the flag — the gate unsets it, proven by the tripwire and by
   the absence of any write to the caller-named path. (The forward-flip latch behaviour itself stays
   under the existing `--fixture-seams` cases; a refusal case must not drive the destructive arm.)
6. `INNGEST_CUTOVER_LATCH_MOUNT` empty without the flag — the gate unsets it, so the mount gate at
   `:425`/`:466` reverts to `/mnt/data`.
7. `CUTOVER_REDIS_DBSIZE=0` without the flag — the gate unsets it, so the `:481` assert reads a real
   value.
8. `CUTOVER_FLIP_FLAG` set-but-empty without the flag — the `${VAR+x}` set-versus-absent distinction
   at `:69` resolves to the production `INNGEST_CUTOVER_FLIP` read, because `unset` means absent.
9. `INNGEST_CUTOVER_STATE` repointed without the flag — the gate unsets it and no file appears at
   the caller-named path.
10. A new unprefixed seam read added in command position — the companion assertion reds.
11. `--fixture-seams` under a second differently-named temp root — seams honoured (must-PASS
    non-canonical).
12. Unit shape: `doppler run --config prd` matches contiguously, no `--project`, new flags after
    `--config prd`, no `--no-fallback`.
13. Unit shape: a fixture unit with `--only-secrets` after the `--` is rejected.
14. Unit shape: a fixture unit with no `--only-secrets` and an exec-seam script is rejected.
15. Unit shape: a `\n`-escaped unit inside a `.tf` heredoc with no bound is rejected.
16. Unit shape: an `ExecStartPre=` doppler unit with no bound is rejected.
17. Unit shape: a `runcmd` doppler invocation is **not** flagged.
18. Guard 2 reports a scanned count at or above its floor on every one of the four surfaces.
19. `systemd-analyze verify` passes on the hardened unit, and a fixture unit whose `ReadWritePaths`
    names a missing directory without the `-` prefix fails it.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `ReadWritePaths` names a directory that does not exist, so the unit fails namespace setup on every fire after the replace | The `-` prefix on both lazily-created paths, plus AC10's `systemd-analyze verify` and scenario 19's negative fixture |
| `PrivateTmp` defeats the Doppler fallback cache on a 30-second cadence, given `DOPPLER_CONFIG_DIR=/tmp/.doppler` | Phase 0 step 4 measures it before adoption; the argv gate does not depend on it, so it can be dropped without weakening the fix |
| The unit's list omits a secret its script needs, and `--no-exit-on-missing-only-secrets` makes that silent | Guard 2 row 3 compares the list against the derived read-set at CI time; the list is derived, not hand-written, and cross-checked against the boot allowlist |
| The gate returns non-zero in the window before the ERR trap at `:523` | The argv predicate cannot fail and touches no filesystem; Phase 2 additionally pins the unset loop's constructs |
| A refusal case reaches the destructive arm on a CI runner | Refusal cases run with the flag absent and drive only `noop-unset`; no `PATH` shadowing is introduced, so `infra-validation.yml:794`'s stated "no real Redis, no FLUSHALL" property is preserved rather than inverted |
| Guard 1's derivation matches production reads, or misses an unprefixed future seam | Prefix-scoped with the expected set pinned as unset-list ∪ `{INNGEST_CUTOVER_FLIP}`, paired with the companion unprefixed-expansion assertion (matrix row 4) |
| Guard 2 is built fresh and silently misses `.tf` units | The enumerator is lifted from `credential-persist-home-guard.test.sh:571-605`, and a `\n`-escaped `.tf` fixture is a required must-RED harness row |
| `inngest.test.sh`'s contiguous `doppler run --config prd` assertion breaks | All new flags go after `--config prd`; AC7 and scenario 12 assert it |
| The flip-guard awk lockstep reds | The gate is additive and top-of-file, adds no `start_server` site, and inserts no `flag_set` between `:496` and `:497` |
| Both assertion floors sit at zero headroom | Phase 0 records the measured baselines (102 and 45); Phase 3 raises each by exactly the number added |
| The change merges green and is never delivered | Phase 8 is in scope, and its probe is a committed artifact rather than an in-session check |
| A failed host create strands the scheduler | The host is braked and serving nothing, so the window costs no availability; `/mnt/data` re-attaches rather than being recut, and the probe asserts the latch afterwards |

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed

**Assessment.** A CTO ruling, a SpecFlow pass, a scoped strong-model consult and a five-agent review
panel each reshaped this plan. The material changes, all folded in and all re-verified against the
code before adoption:

1. **The host is live and the timer fires every 30 seconds**, so this is armed rather than latent —
   high severity, low current likelihood (the config holds seven names and none is a seam).
2. **An in-script guard structurally cannot reach `BASH_ENV`, `PATH`, `LD_PRELOAD` or `IFS`**, so the
   injection-side bound is the primary control rather than a co-equal option.
3. **A plain fail-closed `--only-secrets` list would stop the poll** on a pre-arm host, because
   `INNGEST_CUTOVER_FLIP` is legitimately absent in the designed `noop-unset` state.
4. **The sentinel-file marker was replaced by an argv check.** This was the largest single
   simplification: it is unforgeable by any environment writer rather than merely a non-root one, it
   performs no filesystem work in the pre-ERR-trap window, it removes the gate's own knob from the
   tripwire's derivation prefix, and it costs four one-argument call-site edits.
5. **`PATH` shadowing was cut in full.** It would have inverted the safety property
   `infra-validation.yml:794` documents — that the suite reaches no real Redis and runs no real
   `FLUSHALL` — on the very suite that drives the destructive arm, on a runner with a real
   `systemctl`. A refusal is observable as the absence of a seam's own side effect, which needs no
   instrument.
6. **`--no-fallback` was cut.** It buys no property here and reinstates the hard-fail that
   `--no-exit-on-missing-only-secrets` was adopted to avoid.
7. **`ReadWritePaths` would have killed the unit on every fire after the replace.** Neither
   lazily-created directory exists on a fresh host, and `-`-prefixing does not rescue it under
   `ProtectSystem=strict`. Corrected to `StateDirectory=` plus the mount.
8. **The four sibling units split into a follow-up**, because the rollout phase delivers none of
   them and their secret lists are not safely derivable.
9. **`--only-secrets` lists are authored and commented, never derived.** Two independent exhaustive
   derivations disagreed on the same two scripts, and both misses are silent under the fail-open
   flag — one of them disabling a LUKS-passphrase redactor.
10. **The record belongs as an amendment to ADR-100**, which owns this host's trust model, rather
    than as a new ordinal — and must state the invariant's limit for per-host indirect secret names.

The framing the plan now leads with also came from review: a fail-closed **name** allowlist for this
Doppler project already exists at `cloud-init-inngest.yml:604-611` but runs only in `runcmd`, so
this change is the runtime half of a control the repo already accepted at provision time.

**Capability gap, now in scope:** there is no read-only status verb for this host, and
`scripts/followthroughs/inngest-host-not-serving-7674.sh` reports a not-serving shape for a
correctly-braked one. Rather than defer it, the rollout phase commits its own probe — a production
host replace whose verification cannot be re-run is unauditable.

### Product

**Status:** reviewed — **signed off with conditions**, which are applied above.

CPO signed off on the approach and on the sequencing, with a sharper argument than the plan
originally made: this fix is a **hard prerequisite** of the #6178 cutover, not a sibling. At the
moment of flip the host stops serving nothing, the `FLUSHALL` path becomes live-queue-destroying,
and the cheap replace window closes. It is not merely a good window — it is the only cheap one.

Conditions C1 (impact-section corrections, including re-anchoring the leak statement on the prod
DSN), C2 (canonical bullet form, a ship-time blocker) and C3 (commit the rollout probe) are applied.
C4 — the threshold-ladder inversion — is recorded as a follow-up. A roadmap milestone drift was also
flagged: #7761 sits in *Post-MVP / Later* while #6178, which it gates, is *Phase 4*.

### Product/UX Gate

Not applicable. The mechanical UI-surface scan over `## Files to Edit` and `## Files to Create`
matches nothing — every path is infra shell, a systemd unit, cloud-init, a workflow, a C4 model, an
ADR, or a probe script. Product is NONE on the UI axis by both the semantic sweep and the mechanical
override; the Product review above is the brand-survival sign-off, not a design review.

### Decisions surfaced rather than applied

Four findings argue that a direction the issue or the task brief stated should change, so they are
recorded in
`knowledge-base/project/specs/feat-one-shot-7761-cutover-flip-seam-guard/decision-challenges.md`
rather than auto-applied: whether the in-script gate should exist at all (three reviewers say no),
the sibling split, the threshold-ladder inversion, and the fact that this PR cannot close #7761 at
merge without producing a false-resolved state.

## GDPR / Compliance Gate (Phase 2.7)

**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**

Invoked under expansion trigger (b) — a `single-user incident` brand-survival threshold — not by the
canonical path regex, which matches none of this plan's files (no schema, migration, auth flow, API
route or `.sql`).

**Findings against the five mandatory v1 checks: zero.** `GDPR-Art-6`, `GDPR-Art-5e`, `GDPR-Art-17`,
`GDPR-Art-17-caller` and `GDPR-Art-9` all require a schema column or foreign key; this change adds
none. `GDPR-Chapter-V` requires a new non-EEA vendor env var or SDK; none is added, and Doppler is
already a recorded vendor. No Critical finding, so the operator-acknowledgment escalation flow does
not fire.

**Art. 32 note (Suggestion, no action required by this plan).** The defect being fixed *is* a
security-of-processing gap over personal data, worth stating rather than leaving implicit: the
Inngest queue carries inbound-email triage payloads — Article 30 Processing Activity 27 — so
third-party correspondent content transits the host this unit can be made to execute code on, and
the queue's AOF is plaintext at rest on `/mnt/data` (a ledgered exception tracking #6894). This plan
narrows that exposure and creates none. No new processing activity, personal-data category,
recipient or sub-processor, so **no Article 30 amendment** is required.

**Gate-internal staleness, pre-existing and already tracked.** `notice-frontmatter.sh days-stale`
returns 116 (past the 90-day `POSTURE_FAIL` line) and `cron-run-stale` returns 999 — the known-inert
state tracked in open issue **#7255**, where the drift-detection job moved from a GitHub Actions
workflow to an Inngest cron and the filename-keyed probe can no longer find it. Both are gate-state
signals about the vendored rule bundle, unrelated to this change, and both already carry a tracking
issue. The per-judgment operator-attested-mode banner correctly does not fire, because no
regulated-data path matched.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned 63 issues and none references any
file in the Files to Edit or Files to Create lists.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, carries only placeholder text, or omits the
  threshold fails `deepen-plan` Phase 4.6. It is filled above.
- Infra suites are enumerated in `.github/workflows/infra-validation.yml`, not globbed. A new suite
  not registered there runs in no runner while reading as coverage.
- `MIN_ASSERTIONS` is derived from a green run and must be raised in lockstep, never guessed.
- `--no-exit-on-missing-only-secrets` diverges from house convention on purpose. Its comment names
  `noop-unset` as the reason; deleting the flag as hygiene stops the 30-second poll on a pre-arm
  host.
- The two image digest pins at `cloud-init-inngest.yml:677` and `:721` must move together. Bumping
  one leaves the host pulling a different image than the plan believes it deployed.
- The gate sits in a window where the ERR trap does not yet exist. A stray non-zero there is a
  silent death with no marker — the one failure shape this FSM is built to never have.
- Do not "tidy" the raw refusal `logger` line into `emit_state`. `emit_state` truncates the state
  slot, and that slot is the legacy half of the anti-double-`FLUSHALL` latch.
- Do not add `readlink -f` canonicalisation to the fixture-root check. It buys no property the
  ownership and mode checks do not already buy, and adds a failure mode inside the pre-trap window.
