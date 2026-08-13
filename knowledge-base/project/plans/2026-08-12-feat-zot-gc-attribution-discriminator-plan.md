---
title: "Registry log-channel follow-ups: attribution lead, first-tick softening, stale-arm correction"
date: 2026-08-12
slug: feat-zot-gc-attribution-discriminator
branch: feat-zot-gc-discriminator-probe-grace
issue: 7456
refs: [7456, 7341, 7455]
lane: cross-domain
type: fix
domain: engineering
priority: p3
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Registry log-channel follow-ups

**[Rewritten 2026-08-13 after a five-agent plan-review panel.]** The previous revision proposed a
standalone `scripts/zot-gc-attribution.sh` with an exit-1 stall verdict, a shared parse helper, and
a clock-gated `awaiting_first_tick` verdict. The panel established that design was not defensible.
The superseded plan is preserved in this file's git history; §Plan Review Findings records why.

## Overview

Four small, verified fixes against #7456 item (b) and the delivery probe, all landing in files that
already exist, are already tested, and are already scheduled:

1. **Attribution lead** inside `zot-fill-rate-7341.sh`'s `FAIL)` arm — best-effort, informational,
   structurally unable to change the exit code.
2. **First-tick softening** on `zot-log-channel-7440.sh` — gated on the literal
   `log_shipper_last_ok_age_s == "-1"`. No clock, no `dt` plumbing, no new verdict name.
3. **Stale-arm correction** — the `not_delivered` arm still tells an operator to wait for step-6 of
   an ordered path that closed on 2026-08-12.
4. **`rc=3` credential message** stops being swallowed by `run_query()`, bounded for a public
   comment.

Plus the ADR-184 `## Consequences` correction and #7456's ADR citation.

Items (a) root-fs LUKS (dated 2027-02-11) and (c) rate-cap retune remain on #7456, which this PR
**does not close** (`Refs`, not `Closes`).

## Plan Review Findings — why the previous design was cut

Five agents; every finding below independently verified against the code before acceptance.

### The discriminator could never run

`scripts/sweep-followthroughs.sh:25` sets `SCRIPTS_ROOT="scripts/followthroughs"` and canonicalizes
each directive's `script=` with `realpath`, rejecting anything outside. The previous plan placed the
script outside that directory **and** cut the follow-through tracker, the Better Stack alarm, and
the `workflow_dispatch` lever. Nothing could invoke it. Its Observability block claimed
`alert_route: exit 1` while declaring `alert_target: none new`.

### Its headline verdict had three independent false-positive paths

| Path | Mechanism |
|---|---|
| **Header injection** | `sanitize()` (`cloud-init-registry.yml:839`) strips only `"` and `\`, so `,` `:` `{` `}` survive. A request header rendering `message:executing gc … for /var/lib/zot/x/phantom` injects a phantom repo that never completes → stalled → exit 1. The producer's own `is_cap_exempt` comment requires matching the **parsed `message` field, never the whole line** (#7444 F-5), and C15 pins it for counts — extracting a *name* is strictly more exposed than counting. |
| **Shipper-side row loss** | Cap-exempt rows have their **own** 17-per-tick ceiling; past it they drop. A `redact()` failure, a sanitize-to-empty, a POST "stop at the hole", or `cursor_invalidated` each removes a completion while its start survives — byte-indistinguishable from a stall. |
| **`--limit` truncation** | `betterstack-query.sh` is `ORDER BY dt DESC LIMIT n` inside, `ASC` outside — it takes the **newest** rows. Over a ≥6h window the channel carries ~1/min liveness lines, so any plausible limit binds and drops oldest-first: starts vanish while completions remain. |

A probe whose stall verdict has three ways to lie, on the surface whose User-Brand Impact is *"a
probe that cries wolf trains the operator to discount the only channel reporting on the fleet's sole
container-image pull path"*, is self-refuting.

### The clock the design needed does not exist

`decode_messages()` drops `dt` at hop one; the boot marker payload
(`SOLEUR_ZOT_LOG_BOOT boot_id=… host=… shipper_cron=… journald_storage=…`) carries no timestamp; and
`grep -c '\bdate\b|EPOCHSECONDS'` on the probe returns **0** — it reads no clock at all. The
`indeterminate` rule, the span floor, and the whole grace arm were time arithmetic with no clock.
Worse, the previous AC6 pinned a fixture to a fixed `dt`, so the assertion would **invert
permanently** as the date advanced.

### A false premise, and my own error

I recorded *"`zot-log-channel-7440.sh` … has no `.test.sh`"*. It has
`tests/scripts/test-zot-log-channel-probe.sh` — 497 lines, ~55 cases, registered at
`scripts/test-all.sh:1053`, cited in the probe's own footer. My check was
`ls scripts/followthroughs/zot-log-channel-7440.test.sh`: one of the repo's **two** test-naming
conventions, read as absence. `scripts/test-all.sh:1042` carries the anchored instruction
*"ONLY this fixture suite belongs in this file."* Four of five agents caught it.

Two further scope traps this closes: `scripts/lint-orphan-test-suites.sh` globs `scripts/*.test.sh`
only, so a suite created under `scripts/followthroughs/` can be unregistered and stay green; and
`scripts/lint-followthrough-varq-ban.sh` is followthroughs-only and non-recursive, so the previous
AC11 was vacuous for a script at `scripts/`.

### My Cut List's justification was false

It read *"standing detection is already bought by `zot-fill-rate-7341.sh`."* That probe is a
follow-through: its PASS **closes #7341** (`sweep-followthroughs.sh:203`, `:477`), and the sweeper
lists `--state open`. Detection is engineered to self-terminate on the first healthy reading.
Recorded as a successor issue rather than solved here.

## Implementation Phases

### Phase 1 — Attribution lead in the detector that already fires

`scripts/followthroughs/zot-fill-rate-7341.sh`, `FAIL)` arm (`:262`). That arm already names both
hypotheses (zot#4235, orphaned `.uploads/`) and names **no tool**. The same file already carries the
precedent at `:125`:

```
echo "  Discriminator for producer-silent vs fresh-host vs creds: scripts/zot-restart-loop-alarm.sh"
```

Append a best-effort attribution lead after the verdict is decided:

- Query the envelope-anchored gc classes over the trailing window.
- Print: gc starts, completions, **repositories with unmatched starts**, `PatchBlobUpload` count,
  and the `SOLEUR_ZOT_LOG_DROPPED` count in the same window.
- Frame every number as a **lead, not a verdict** — the drop count is printed precisely because
  row loss is indistinguishable from a stall, so the operator sees the confound rather than a
  confident wrong answer.
- On any query error print `attribution_unavailable` and continue.

**Structural constraints (each closes a panel finding):**

- It runs **after** the verdict and **cannot** change the exit code (`|| true`, no `set -e` path).
- Anchor with the trailing delimiter: `^SOLEUR_ZOT_LOG shipper=zot-log-shipper host=<host> ` —
  the space is part of the contract (`zot-log-channel-7440.sh:166`), without which
  `host=soleur-registry-2` matches.
- Extract from the **parsed `message` field**, never the whole line (#7444 F-5), so a header-borne
  `executing gc` cannot inject a repository.
- Bound the printed output; this text is posted verbatim to a **public** issue comment.

### Phase 2 — First-tick softening (no clock)

`scripts/followthroughs/zot-log-channel-7440.sh`. The `delivered_but_silent` arm already prints
*"last_ok_age_s=-1: the shipper has never delivered a row, so this is a never-worked state, not a
regression."* Promote that above the `THIS IS THE STATE THAT MEANS ACT, NOT WAIT` sentence and
soften that sentence when the literal `-1` holds.

- Gate on the **literal string `-1`**, never on emptiness — C3b's fixture (`control_row_predelivery`)
  has no `log_shipper_*` fields at all and asserts `delivered_but_silent`; reading absent as
  "never ticked" reddens the merge-blocking shard.
- No new verdict name, no exit-code change, no boot-recency read, no `dt` decode.

### Phase 3 — Stale-arm correction

The `not_delivered` arm (`:328`) and the header (`:16`) still read *"Delivery rides the step-6
`registry-host-replace` of the **open** zot-pin ordered path."* #7287 closed 2026-08-12T20:39Z and
the host has been replaced. An operator who has just dispatched a replace is currently told to wait
for a step that no longer exists. Replace with the delivered state and the real remaining wait
(the shipper's first `4-59/5` tick).

### Phase 4 — `rc=3` credential message

`run_query()` (`:140`) uses `2>/dev/null`, which destroys `betterstack-query.sh`'s rc=3 credential
message — the likeliest first-run failure (#7435 plumbing finding). Capture and surface it, bounded
by the sibling's form (`zot-fill-rate-7341.sh` uses `head -c 600 "$qerr"`) because this output
reaches a public comment.

### Phase 5 — Tests, ADR, citation

- Grace + stale-arm cases go into **`tests/scripts/test-zot-log-channel-probe.sh`** (existing);
  raise its `>= 70` assertion floor. **No new suite, no new registration.**
- Attribution-lead cases go into `scripts/followthroughs/zot-fill-rate-7341.test.sh` (existing,
  20/20, registered at `scripts/test-all.sh:849`); raise its floor.
- Write the failing cases **before** the edits (`cq-write-failing-tests-before` — the previous plan
  inverted this).
- **ADR-184:** correct `## Consequences` only. Its claim that the gc ratio and `PatchBlobUpload`
  counts are "readable rather than sampled" is refined by measurement: per-repo pairing is available
  on the start/complete pair; `garbage collected blobs` is **bare**; the payload is comma-separated
  `key:value` with unescaped colons in values. **Do not touch the frontmatter `status:` or
  `## Status flip condition`** — #7455 is amending exactly those concurrently, so the scope
  restriction makes any conflict textual rather than semantic.
- Correct #7456's ADR-179 → ADR-184 citation.

## Files to Edit

- `scripts/followthroughs/zot-fill-rate-7341.sh` — attribution lead in the `FAIL)` arm
- `scripts/followthroughs/zot-fill-rate-7341.test.sh` — attribution cases, floor raised
- `scripts/followthroughs/zot-log-channel-7440.sh` — softening, stale arm, rc=3
- `tests/scripts/test-zot-log-channel-probe.sh` — softening + stale-arm cases, floor raised
- `knowledge-base/engineering/architecture/decisions/ADR-184-registry-host-container-log-shipper.md`

## Files to Create

None. (The previous revision created three files; the panel established each was either duplicate,
uninvokable, or unnecessary.)

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` against every target path
returns zero matches.

## User-Brand Impact

**If this lands broken, the user experiences:** a registry probe that either cries wolf on a healthy
host or prints a confident wrong attribution during an incident.

**If this leaks, the user's data is exposed via:** probe stdout posted verbatim to a **public**
GitHub issue comment by the sweeper. Every phase that widens output (Phase 1's lead, Phase 4's
stderr) is explicitly bounded for that reason.

**Brand-survival threshold:** `single-user incident`.

## Architecture Decision (ADR/C4)

**ADR:** amend ADR-184 `## Consequences` only (scope restriction above). No new ADR — this
corrects a claim in an existing one.

**C4:** **no impact.** Read against `model.c4` (688 lines), `views.c4`, `spec.c4`. No external human
actor, external system, container/data-store, or access relationship is added: `betterstack` is
already modeled as a ClickHouse-queryable Logs warehouse "polled from GitHub Actions via
`betterstack-query.sh` for … follow-through soak probes", and its description already names the
#7440/ADR-184 shipper edge. Every change here is inside already-modeled scripts. (This conclusion
held only *conditionally* in the previous revision, which would have added a CI vehicle; cutting the
vehicle makes it unconditional.)

## Encryption Posture

**Skipped** — no persistent store, no new cross-component connection.

## Guard Contract

### Guard 1 — the attribution lead cannot affect the verdict

**Property.** For every input, the exit code of `zot-fill-rate-7341.sh` is identical with and
without the attribution lead.

**Assembly.** Every exit path of that script — the chokepoint is the single `case` on the computed
verdict; the lead is appended strictly downstream of it.

| # | Mutation | Expected |
|---|---|---|
| 1 | Make the attribution query fail (stub non-zero) | **exit code unchanged**; prints `attribution_unavailable` |
| 2 | Make the attribution query hang/return garbage | **exit code unchanged** |
| 3 | Remove the `|| true` guard so the lead can abort the script | **RED** |
| 4 | Add a **second** verdict arm that also prints the lead, without the guard | **RED** (covers all arms, not the first) |

### Guard 2 — the softening does not weaken escalation

**Property.** A host with delivery evidence, zero envelope rows, and `last_ok_age_s` **not** the
literal `-1` still reports `delivered_but_silent` with its ACT-NOT-WAIT framing.

**Assembly.** Both paths that set `delivered=1` (`boot_marker`, `reporter_carries_shipper_fields`)
and the single verdict emit site.

| # | Mutation | Expected |
|---|---|---|
| 1 | `last_ok_age_s` **absent** (C3b's `control_row_predelivery`) | **still** `delivered_but_silent` — not softened |
| 2 | `last_ok_age_s=42` | **still** `delivered_but_silent` |
| 3 | Soften on emptiness rather than the literal `-1` | **RED** (C3b reddens) |
| 4 | Delivery evidence via the **second** arm with `-1` | softened — covers both members |

## Observability

```yaml
liveness_signal:
  what: existing SOLEUR_ZOT_LOG / SOLEUR_ZOT_DISK channels — unchanged by this plan
  cadence: shipper 5-minute one-shot (cron 4-59/5); sweeper daily 18:00 UTC
  alert_target: unchanged — zot-fill-rate-7341.sh on #7341; no new route is claimed
  configured_in: apps/web-platform/infra/cloud-init-registry.yml (untouched)
error_reporting:
  destination: probe stdout/stderr, mirrored by the sweeper into a public issue comment
  fail_loud: true — betterstack-query.sh rc=3 is surfaced (Phase 4), bounded to 400 bytes
failure_modes:
  # LAYER: this host runs no Vector and no Sentry. Every signal below lands on the layer-6
  # synchronous consumer — the sweeper's GH Actions run log plus the verbatim issue comment it
  # posts (last 4 KB of stdout+stderr). There is no other route, and none is claimed.
  - mode: attribution query fails or times out during an incident
    detection: prints attribution_unavailable with the query rc and bounded stderr
    alert_route: layer 6 — sweeper run log + issue comment on #7341; verdict unaffected
  - mode: attribution parses zero gc rows (dead shipper, host rename, row-shape drift)
    detection: rows_in/rows_decoded/rows_envelope printed; the arm states it is NOT an all-clear
    alert_route: layer 6 — points the operator at zot-log-channel-7440.sh
  - mode: a repo completes fewer gc cycles than it starts (intermittent zot#4235)
    detection: per-repo done/started ratio, not a set difference
    alert_route: layer 6 — named in the FAIL comment beside the drop count
  - mode: shipper never ticked vs shipper dead — NOT separable on this row
    detection: last_ok_age_s=-1 is the reporter default; ACT framing is never suppressed
    alert_route: layer 6 — first-tick note is additive, so escalation is preserved
  - mode: shipper never completes a first tick after a replace
    detection: log_shipper_last_ok_age_s == -1 with delivery evidence present
    alert_route: delivered_but_silent, softened framing (Phase 2)
  - mode: query credentials unset
    detection: betterstack-query.sh rc=3, no longer swallowed
    alert_route: TRANSIENT with the credential message surfaced
logs:
  where: Better Stack Logs source 2457081
  retention: ~3 days; the attribution window must stay inside it
discoverability_test:
  # The live probe needs warehouse credentials AND its PASS arm is untouched by this change, so a
  # credentialed run would verify a property this PR does not alter. The fixture suite is
  # credential-free and exercises all four changes (softened arm, stale arm, rc=3, and — via its
  # sibling — the attribution lead). No credentials_required waiver is claimed.
  command: bash tests/scripts/test-zot-log-channel-probe.sh
  expected_output: "=== 82 passed, 0 failed ==="
```

### Soak follow-through enrollment

**Not required.** No criterion here is time-gated. `zot-fill-rate-7341.sh` remains enrolled on
#7341 (`earliest=2026-08-14`).

## Domain Review

**Domains relevant:** Engineering.

### Engineering

**Status:** reviewed — five-agent panel (Kieran, architecture-strategist, spec-flow-analyzer,
code-simplicity-reviewer, DHH), findings in §Plan Review Findings, all independently verified
against the code before acceptance.

**Assessment:** Internal observability on an infra host. The panel's decisive contribution was
establishing that the previously planned mechanism was both uninvokable and unable to support its
own headline verdict; scope is now four small edits in already-tested, already-scheduled files.

## Acceptance Criteria

### Pre-merge

- **AC1** — With the attribution lead stubbed to fail, `zot-fill-rate-7341.sh` returns the same exit
  code as without it, for every verdict arm.
- **AC2** — The lead prints the `SOLEUR_ZOT_LOG_DROPPED` count alongside the gc counts, so row loss
  is visible next to any unmatched start.
- **AC3** — The lead's row matching uses the envelope anchor **including the trailing space**, and
  extracts from the parsed `message` field; a fixture with a header-borne `executing gc` injects no
  repository.
- **AC4** — A host with `last_ok_age_s` absent still reports `delivered_but_silent` (C3b preserved).
- **AC5** — A host with the literal `last_ok_age_s=-1` reports the softened framing, same exit code.
- **AC6** — The `not_delivered` arm no longer references an open ordered path or step-6.
- **AC7** — `run_query()` surfaces `betterstack-query.sh` rc=3, bounded to 400 bytes.
- **AC8** — No new test file and no new `run_suite` registration:
  `git status --porcelain | grep -c '^A.*\.test\.sh'` returns 0, and `scripts/test-all.sh` is
  unchanged except for assertion floors.
- **AC9** — Assertion floors raised in both existing suites; both suites green.
- **AC10** — `shellcheck` clean on both edited probes and both edited suites.
- **AC11** — ADR-184's frontmatter `status:` and `## Status flip condition` are byte-identical to
  `origin/main` (the #7455 conflict guard).
- **AC12** — `bash scripts/test-all.sh` green.

### Post-merge

- **AC13** — #7456's ADR-179 citation corrected to ADR-184.
- **AC14** — Successor issues filed (below).

## Successor Issues to File

1. **Rate-cap retune (c) needs a trigger.** #7456 keeps the item; nothing schedules a read. The
   delivery probe prints `dropped_rows=N` with no threshold. File with the drop-count query in the
   body and a date.
2. **Standing detection expires when #7341 closes.** `zot-fill-rate-7341.sh` PASS closes the issue
   and the sweeper lists `--state open`; the only remaining backstop is the ≥85% absence heartbeat,
   which is the incident rather than a leading indicator.
3. **Two false claims in `model.c4`'s `zotRegistry` description** — "the LIVE host still runs
   v2.1.2" (observed digest `95a837a0afac` = v2.1.20) and "the LIVE device is still plaintext ext4
   … vehicle shipped UNFIRED" (the recut fired 2026-08-10). Separate PR: that file carries
   whole-file-count ACs.
4. **`scripts/followthroughs/*.test.sh` is invisible to `lint-orphan-test-suites.sh`**, which globs
   `scripts/*.test.sh` only — a suite there can be created, never registered, and stay green.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Standalone `scripts/zot-gc-attribution.sh` with an exit-1 stall verdict | **Rejected** — uninvokable (sweeper path restriction), and the verdict had three independent false-positive paths. §Plan Review Findings. |
| `awaiting_first_tick` as a distinct clock-gated verdict | **Rejected** — no clock exists on that path; same exit code either way; the automated caller samples the 10-minute window ~0.7% of the time. |
| Shared parse helper in `scripts/lib/zot-telemetry-parse.sh` | **Rejected** — one consumer, a different stream from the library's two `SOLEUR_ZOT_DISK` consumers, and its spec omitted the anchor's trailing delimiter. |
| A dispatch-only workflow on the #7343 shape | **Deferred** — a real vehicle, but it buys standing attribution the inline lead already provides at the moment of failure. Revisit via successor issue 2. |
