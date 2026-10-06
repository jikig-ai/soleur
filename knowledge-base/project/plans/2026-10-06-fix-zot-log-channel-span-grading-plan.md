---
title: "fix: zot-log-channel-7440.sh grades its exit 1 over a different span than its delivery evidence"
type: fix
date: 2026-10-06
slug: fix-zot-log-channel-span-grading
branch: feat-one-shot-8278-zot-log-channel-span
issue: 8278
closes: 8278
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix: zot-log-channel-7440.sh grades its exit 1 over a different span than its delivery evidence

## Overview

`scripts/followthroughs/zot-log-channel-7440.sh` has the same defect class #7960 had
(PR #8272 / ADR-211 "Delivery proof"): its verdict and its delivery evidence come
from different spans. The single `exit 1` arm grades credential-shaped leaks over an
unscoped 30-minute window (`--since "$WINDOW" --no-archive`), while delivery evidence
comes from a separate `SOLEUR_ZOT_LOG_BOOT` marker query over `--since 72h` with the
archive arm. Nothing ties the graded rows to the boot whose delivery was established,
so a replace straddling the window — one happened 2026-09-20, recorded in the issue —
can make a public FAIL or a close rest on evidence about a different host generation.

This plan ports the settled fix shape to this probe: both decoded channels carry `dt`
through as a TSV column, the control rows' trusted head (cut at ` zot_last_err=`)
supplies the newest real boot, and **one awk pass** produces every verdict-keyed
value — the boot scope, the delivery proof, the counts, and the leak grade — over
exactly the rows that boot produced. Delivery is keyed on `log_shipper_post_fail=`
and the boot-stamped `SOLEUR_ZOT_LOG_DROPPED`/`SOLEUR_ZOT_LOG_BOOT` rows on that same
boot — tokens only the delivered producer can emit — never on a marker read from a
different span. The defect is latent today (tracker #7455 is CLOSED, no open issue
enrols the script); the operator elected to fix it now rather than on re-enrollment.

*Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).*

## Problem Statement / Motivation

Issue #8278. The probe's three evidence sources have three spans:

| Evidence | Query today | Span |
|---|---|---|
| Leak grade (`exit 1` arm, `envelope_hits`) | `--grep SOLEUR_ZOT_LOG --since 30m --no-archive` | unscoped 30 m |
| Delivery (`n_boot > 0` → `delivered=1`) | `--grep SOLEUR_ZOT_LOG_BOOT --since 72h` (+archive) | 72 h, any boot |
| Control / reporter fields (`log_shipper_*`) | `--grep SOLEUR_ZOT_DISK --since 30m --no-archive` | `tail -1` of 30 m |

The harm class, stated in the issue: a window that straddles a replace mixes two
host generations in the graded set — pre-replace rows are graded against a boot the
delivery evidence does not name. Measured non-hypothetical: the registry host was
replaced 2026-09-20 (run 35489418603) and the boot id changed; only the fact that
nothing enrols the probe kept the mis-spanned grade from posting. The same split
falsified the 7500 probe's first post-replace run (#7960) and was fixed by scoping
both operands to the newest real boot inside one pass.

Secondary defect the same pass removes: the `SOLEUR_ZOT_LOG_BOOT` marker is emitted
once per *instance* (runcmd is per-instance; this host reboots as a NIC-guard
convergence primitive) and expires with the source's ~3-day retention, so on any
host older than three days the current primary delivery evidence is permanently
absent. Delivery must key on tokens emitted continuously by the delivered producer.

## Research Insights

**Files read / relevant paths.**

- `scripts/followthroughs/zot-log-channel-7440.sh` — the subject. `run_query`
  (line ~174) pins `--since "$WINDOW" --no-archive` for every query; the boot
  marker is fetched separately at line ~218 (`--since 72h`, archive arm);
  `delivered=1` at line ~272 keys on `n_boot>0` or `log_shipper_post_fail=` on the
  *newest* control row (`tail -1`); the leak grade at lines ~291-315 scans
  `envelope_hits` unscoped.
- `scripts/followthroughs/zot-last-err-redact-7500.sh` (PR #8272, 392 lines) —
  primary reference: envelope-anchor → decode `dt`+`message` to sorted TSV →
  `NEWEST_BOOT` from trusted heads → **one awk pass** (`want=$NEWEST_BOOT`, head
  cut at ` zot_last_err=`, tail kept for the leak grade) → integer guard →
  decision table R1-R4 with exit 3 for unproven delivery.
- `scripts/followthroughs/registry-luks-live-8386.sh` — closer sibling (same
  `SOLEUR_ZOT_DISK` heartbeat): host-scope on the trusted head before boot
  selection, producer-liveness via `dt`, Guard Contract rule in its header: *"A
  second pass over the same rows, a field read outside this pass, or a read past
  the tail cut is the defect this file's Guard Contract forbids."*
- `apps/web-platform/infra/cloud-init-registry.yml` — producer. Line ~1760:
  `ship "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOST_NAME_V $clean"` —
  envelope rows carry **no `boot_id`** (only `SOLEUR_ZOT_LOG_DROPPED` at line ~1573
  and `SOLEUR_ZOT_LOG_BOOT` at ~2635 do). `BOOT_ID` is computed at line ~1285.
  `SOLEUR_ZOT_DISK` line ~1012 carries `boot_id=` in the trusted head before
  ` zot_last_err=` and the `log_shipper_*` reporter fields.
- `scripts/betterstack-query.sh` — emits JSONEachRow, `raw` double-encoded, `dt`
  ingest-assigned (the one field the producer cannot set), `LIMIT=100` default —
  siblings pass 5000 explicitly.
- `.github/workflows/registry-host-replace-dispatch.yml` — `push:` to main on
  `apps/web-platform/infra/cloud-init-registry.yml` (and `.tf` render inputs)
  re-renders user_data and dispatches a production host replace on a rendered
  diff. **Any template edit self-delivers via a destructive replace of the sole
  image-pull path.**
- `tests/scripts/test-zot-log-channel-probe.sh` — 582-line fixture suite,
  `ZOT_LOG_7440_QUERY_BIN` stub dispatching on `--grep`; ≥70-assertion floor +
  harness canary; fixtures currently emit a single fixed `dt` per row.
- Sibling consumers of the same envelope — **collision surface**: `zot-upload-ceiling-7556.sh`
  (`PFX = "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry "` then
  `body = line[len(PFX):]` parsed by regexes anchored `^\{time:` — enrolled on
  tracker #7556, live) and `zot-fill-rate-7341.sh` (same prefix-strip, field-scanning
  `message:` — tolerant). Inserting `boot_id=` into the envelope **head** breaks
  7556's classifiers outright; a **suffix** (`... $clean boot_id=$BOOT_ID`, last
  field trusted) survives all three consumers' anchored-at-start parsers.

**Institutional learnings applied.**

- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-*.md` — the fixture
  suite is the guard's harness; mutation matrix below is design-derived, not
  code-derived.
- `2026-08-20-the-channel-was-silent-on-the-path-it-was-built-for.md` — order/lifetime
  properties need rows observed *inside* the window, not deletes.
- `2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself.md` — anchor:
  the probe posts to a public issue; the fixture corpus and the ≥70-assertion floor
  are the anchors, and both must move with the diff.
- `followthrough-convention.md` §affected-rows — pin each signal to its emitter at
  offset 0 and to its row shape; the source is multi-tenant and quoteable.
- `2026-07-19-a-wall-clock-break-*.md` — a probe's exit code is a contract the
  sweeper consumes; new exit 3 maps to CANNOT ESTABLISH (issue stays open).

**Premise Validation (Phase 0.6).** #8278 OPEN (labels incl. `blocked`,
`priority/p3-low`); PR #8272 MERGED 2026-09-18; ADR-211 exists with the "Delivery
proof" section; both scripts exist at the cited paths; tracker #7455 CLOSED;
zero open issues carry a `soleur:followthrough` directive naming the script
(re-verified: open citers are #9373, #7456, #8698, #7530, #7959 — prose only);
`.github/workflows/scheduled-followthrough-sweeper.yml` already exports the three
`BETTERSTACK_QUERY_*` names — no workflow edit needed. `registry-host-replace-dispatch.yml`
push trigger confirmed. Nothing stale.

**Property List (Phase 0.6b).**

1. The `exit 1` grade and the delivery proof are computed over the same span:
   the newest real boot, from one pass — no verdict-keyed value read outside it.
2. Delivery keys on a token only the delivered producer can emit (a reporter
   field absent pre-delivery, or a boot-stamped LOG-channel row on that boot) —
   never boot drift, never a marker from a different span.
3. When the newest boot cannot be established, the probe refuses to grade:
   CANNOT ESTABLISH, never PASS and never FAIL.
4. No regression to the enrolled siblings that parse the same envelope
   (`zot-upload-ceiling-7556.sh`, `zot-fill-rate-7341.sh`).

**Cut List (Phase 0.6b).**

- New `shipper_rev=` field on the envelope → buys property 2's "producer-only
  token" → already covered by `log_shipper_post_fail=` (delivered-reporter-only)
  and `boot_id=` on DROPPED/BOOT rows; a revision token adds nothing `boot_id`
  does not already provide on a cloud-init-per-instance host. **Cut.**
- Separate `SOLEUR_ZOT_LOG_BOOT` 72h query → buys nothing under property 1; its
  span mismatch is the defect. **Cut** (marker rows still flow through the single
  `--grep SOLEUR_ZOT_LOG` arm whenever they are in-window — substring match).
- Second "verification" pass over the same rows → the property is one pass;
  **cut** by construction.

**External research:** skipped — the fix shape is fully settled by two in-repo
reference implementations; external research adds nothing.

**CLI-verification:** no new CLI invocations are prescribed for docs; existing
`betterstack-query.sh` flags (`--since`, `--no-archive`, `--limit`, `--grep`) are
already used by the subject script.

## Proposed Solution

Port the ADR-211 / 8386 shape to this channel **without touching the producer**,
using the `dt` column to bind the graded set to the newest real boot:

1. **One query per channel, same window, same flags.** Keep `--grep SOLEUR_ZOT_LOG
   --since "$WINDOW" --no-archive --limit "$LIMIT"` (returns envelope +
   `SOLEUR_ZOT_LOG_DROPPED` + `SOLEUR_ZOT_LOG_BOOT` rows — substring match) and
   `--grep SOLEUR_ZOT_DISK` (control). **Delete the separate `--since 72h` boot-marker
   query and the `BOOT_MARKER` delivery arm.**

2. **Carry `dt` through decode.** Replace `decode_messages` (which discards `dt`)
   with the sibling's two-hop `jq` emit `[.dt, <channel-tag>, .message] | @tsv`,
   sorted — `dt` is ingest-assigned, the only field the producer cannot set, and
   is the sort/boundary key.

3. **Derive `NEWEST_BOOT` and the boundary from host-scoped stamped rows only.**
   Control rows are host-scoped on the head cut at ` zot_last_err=` (mirrors
   `zot_trusted_region`). `NEWEST_BOOT` = `boot_id` (class `[0-9a-fA-F-]+`, which
   excludes the producer's `unknown` sentinel) on the newest-`dt` **host-scoped**
   stamped row — control rows always qualify; a `SOLEUR_ZOT_LOG_BOOT` marker
   carries `host=` and also qualifies. `SOLEUR_ZOT_LOG_DROPPED` rows carry
   `boot_id` but **no `host=` field**, so they cannot be host-verified and must
   never *select* the boot or the boundary — they corroborate and count only on
   a boot already derived (one contaminating unscoped row must not get to choose
   the evidence base). Boundary `B0` = earliest `dt` among host-scoped stamped
   rows carrying `NEWEST_BOOT`; an in-window BOOT marker on that boot tightens
   `B0` to ~provision time. No usable `boot_id` on any host-scoped row → exit 3.

4. **One awk pass, all verdict fields.** Inputs: the sorted TSVs of both channels.
   Per row: classify (control / envelope / dropped / boot-marker), cut the trusted
   head (` zot_last_err=` for control rows; the fixed envelope head for LOG rows;
   LOG-row `boot_id`/`host=` read only from stamped-row fields, never from the
   free-text payload), scope to `b == NEWEST_BOOT` for stamped rows and
   `dt >= B0` for envelope rows, and emit ONE summary line: `n_env n_env_pre
   n_drop n_zot_tok gc_* n_auth_leak n_shape_leak postfail_present postfail_val
   last_ok_age dropped_cum drop_seq n_ctl newest_boot B0`. Envelope rows carry no
   `boot_id`, so their scope is the boundary, not a field — the exact residual
   recorded under Alternative Approaches.

5. **Delivery key.** `delivery_evidence` names a same-boot source only:
   `log_shipper_post_fail=` present on a control row of `NEWEST_BOOT`
   (delivered-reporter-only token — the F-7 key, now boot-scoped), a
   `SOLEUR_ZOT_LOG_DROPPED`/`SOLEUR_ZOT_LOG_BOOT` row on `NEWEST_BOOT`, or the
   graded envelope rows themselves (a shipped row on the graded boot is the
   producer's own output — the strongest evidence). Printed evidence strings name
   the source (`postfail_on_boot`/`drop_row_on_boot`/`boot_marker_on_boot`/
   `envelope_on_boot`).

6. **Verdict chain, same arms, boot-scoped.** Guards unchanged → exit 2. Awk
   summary missing/non-integer → **exit 3** (new for this probe; sweeper renders
   CANNOT ESTABLISH — a branch that refuses to assert a delivery state must not
   ship under a heading that asserts one). No usable `boot_id` → exit 3. The
   `control_missing` arm is preserved ahead of boot derivation (`n_env>0` with
   `n_ctl==0` → exit 2: the envelope proves the read path answers while the
   heartbeat's silence masks a separate live incident). Leak grade on the
   bounded set → exit 1 (message names `boot=` and counts only — the existing
   no-row-text rule stands). **Unscopeable leak rows:** a credential-shaped
   envelope row that falls outside the graded scope — or rows present when no
   boot can be derived — is exit 3 CANNOT ESTABLISH naming the ungraded count,
   never a false FAIL on unattributed evidence and never a silent clean.
   Zero-envelope arms (`channel_dark`/`delivered_but_silent`/`not_delivered`),
   `envelope_without_zot_content`, `below_expected_floor`, PASS — all computed
   on the newest-boot set; the delivered/not_delivered discriminator is
   `postfail_present` on that boot.

7. **Floor over the bounded span.** `FLOOR_ROWS` is `EXPECTED_ROWS/4` where
   `EXPECTED_ROWS` is `min(WINDOW_MIN, bounded-span-minutes)` — a mid-window
   boundary would otherwise post a systematic false `below_expected_floor` for
   ~30 minutes after every replace (spec-flow catch).

8. **Header rewritten** to state the Guard Contract in the sibling's form: a
   second pass over the same rows, a field read outside the pass, or a read past
   the trusted cut is the defect this file forbids; plus the exit-3 addition and
   the deletion of the 72h arm.

## Technical Considerations

- **Trusted-region asymmetry is deliberate.** Control-row verdict fields come only
  from the head before ` zot_last_err=`; envelope rows contribute *counts and the
  leak grade*, which must read the untrusted payload (that is what the grade
  measures) but never contribute `boot_id`/`host=`/reporter values.
- **A crafted `zot_last_err=` tail cannot supply a boot or a proof token** — the
  leftmost cut lands before it; the leak grade reads tails, which is correct.
- **Multi-tenant source residual, unchanged and recorded:** source 2457081 is
  shared; any ingest-token holder can synthesize producer-shaped rows. The prefix
  + `host=` + `dt`-boundary scope is the same authority the siblings accept for
  FAIL/NOT-YET verdicts; the probe never auto-closes on weaker evidence than the
  family already accepts.
- **Boundary precision ±5 min** (heartbeat cadence): an envelope row in the
  [replace, first-heartbeat) gap is conservatively *excluded* — ungraded rather
  than mis-graded. Recorded; the per-row-stamp alternative eliminates it (below).
- **`dt` is the only producer-independent field** — no host clock is consulted
  (the probe has none today and gains none; first-tick softening still keys on the
  literal `last_ok_age_s=-1` reporter value, read on the newest boot).
- **`@tsv` is load-bearing**: it escapes an embedded newline to `\n`, so one
  warehouse row can never split into two awk records — dropping it hands a crafted
  row a fully-trusted synthetic head.
- **POSIX awk only** (no interval expressions, no `[[:classes:]]`, no gawk
  extensions) — the runner awk is mawk; the integer guard is what keeps a dialect
  error on the CANNOT-ESTABLISH side, never a false close.

## Alternative Approaches Considered

| Option | Verdict | Why |
|---|---|---|
| **A — add `boot_id=` to the envelope (producer change), per-row binding** | **Rejected for this PR** | The literal reading of the issue's parenthetical and the only design where each graded row self-certifies. Costs: (a) the template diff triggers `registry-host-replace-dispatch.yml` on merge — a destructive replace of the fleet's sole image-pull path, forced by a p3 fix to a latent script; (b) inserting the field into the envelope **head** breaks the **enrolled** `zot-upload-ceiling-7556.sh` (`body=line[len(PFX):]` must match `^\{time:`), a live regression posting daily TRANSIENT on tracker #7556 until patched; the **suffix** form (`$clean boot_id=$BOOT_ID`, `$NF` trusted) survives all three consumers but still costs (a) plus a transition window where every envelope row is unstamped and the probe cannot grade at all; (c) on a cloud-init-per-instance host `boot_id` disambiguates producer generations exactly as a `shipper_rev` would. Worth filing as a follow-up only if per-row binding is ever needed, folded into a template change that rides an already-scheduled replace. |
| **B — probe-only, `dt`-bounded newest-boot scope (chosen)** | **Adopted** | Satisfies properties 1-4 with zero producer change, zero blast radius on enrolled siblings, effective on the live host the day the sweeper next runs — and the auto-replace a template diff would force is spent on nothing this fix needs. Faithful to the named references: control rows use the identical ` zot_last_err=` head cut and one-pass shape; the leak grade reads untrusted payload exactly as 7500 reads the tail. Residual: ±5-min boundary precision vs per-row binding. |
| **C — keep both queries; only intersect spans (grade `dt >=` marker `dt`)** | Rejected | Retains the second span the issue names as the defect, keeps the retention hole (marker gone >3 days ⇒ undeliverable verdicts forever), and still binds nothing per-row. |
| **D — defer to re-enrollment (the `blocked` trigger)** | Rejected | Operator direction in the one-shot brief: fix now; the 2026-09-20 comment itself records a real straddle and says the fix is owed *before* re-enrolment. |

## Implementation Phases

### Phase 1 — Probe rewrite (`scripts/followthroughs/zot-log-channel-7440.sh`)

- Carry `dt` + channel tag through both decoders (`jq … @tsv | sort`); keep
  `@tsv` and `fromjson?` discipline and the QUERYFAIL/stderr contract.
- Delete the `boot_raw`/`boot_hits`/`n_boot` 72h arm and `BOOT_MARKER` as a
  delivery input (marker rows still classify inside the LOG set when in-window).
- Add the host-scope + `NEWEST_BOOT`/boundary derivation and the ONE awk pass
  emitting the summary line; integer guard → exit 3.
- Rewrite the verdict chain on the summary fields; keep every existing reason
  token, the counts-only FAIL arm, the first-tick `-1` softening, the
  `envelope_without_zot_content` and floor arms (floor over the bounded span).
- New header: Guard Contract statement, exit-contract table including exit 3,
  why `--since 72h` is gone, why `dt` is the boundary key, the ±5-min residual.

### Phase 2 — Fixture suite (`tests/scripts/test-zot-log-channel-probe.sh`)

- `row()` gains a `dt` parameter (fixtures need distinct timestamps); stub keeps
  the `--grep` dispatch, drops the separate BOOT arm only if the probe drops the
  query; new fixture helpers: `boot_marker_row(boot,dt)`, `dropped_row(boot,dt)`,
  envelope rows at chosen `dt`s, control rows on two boots.
- New cases (RED targets — see Guard Contract): straddle window pre-boundary leak
  → no exit 1; post-boundary leak → exit 1 naming `boot=`; delivery keyed on same
  boot only (post_fail on old boot only → `not_delivered`); no `boot_id` anywhere
  → exit 3; forged `zot_last_err=` tail carrying ` boot_id=`/`log_shipper_post_fail=`
  → verdict unaffected; awk-guard vacuity → exit 3; `unknown` boot sentinel never
  scopes; in-window BOOT marker tightens the boundary.
- Update existing cases that pinned the old evidence string `boot_marker(n)` /
  `reporter_carries_shipper_fields`, the `since=72h` stub assertion, and any
  single-`dt` fixture that now needs a span.
- Assertion floor + canary stay load-bearing; floor raised to the new count.

### Phase 3 — ADR-184 addendum

- Short amendment to `knowledge-base/engineering/architecture/decisions/ADR-184-*.md`:
  the recorded PASS/`delivery evidence: boot_marker(1)` text at the 2026-08-12
  amendment is now historical; record the one-pass newest-boot grading shape, the
  exit-3 addition, and the retired 72h marker arm. No new ADR (the mechanism is
  ADR-211's existing decision applied to a second channel).

## Files to Edit

- `scripts/followthroughs/zot-log-channel-7440.sh` — the rewrite above.
- `tests/scripts/test-zot-log-channel-probe.sh` — fixtures + new cases + floor.
- `knowledge-base/engineering/architecture/decisions/ADR-184-*.md` — addendum.

## Files to Create

- None.

## Explicitly NOT in this diff

- `apps/web-platform/infra/cloud-init-registry.yml` — untouched, so
  `registry-host-replace-dispatch.yml` does **not** fire a replace for this PR.
- `scripts/followthroughs/zot-upload-ceiling-7556.sh`, `zot-fill-rate-7341.sh` —
  untouched; their enrolled/live behaviour is preserved by construction.
- `.github/workflows/scheduled-followthrough-sweeper.yml` — env already wired.
- No `soleur:followthrough` directive is added anywhere; the script stays
  unenrolled until its own trigger fires.

## User-Brand Impact

- **If this lands broken, the user experiences:** either a false `FAIL:
  credential_shape_in_channel` comment on a public issue (alarm noise naming the
  registry credential path), or — the worse direction — a probe that passes or
  fails to fire while a real registry push credential sits exposed in a public
  log channel: the credential guards the fleet's sole image-pull path, so a
  missed leak is a supply-chain exposure, not a log-hygiene defect.
- **If this leaks, the user's [data / workflow / money] is exposed via:** a
  silently-misspanned grade that never reopens the tracker while a leaked
  registry credential (write access to the image store every deploy pulls from)
  remains valid — every holder of `BETTERSTACK_QUERY_*` can read the rows.
- **Brand-survival threshold:** `single-user incident` — consistent with the
  script header's own declared threshold for the exit-1 carve-out (a leaked
  registry push credential is a supply-chain incident for the whole fleet).
- **Threshold decision (challengeable):** the probe is defense-in-depth (the
  producer's `redact()` is the primary control, pre-merge tested), so `none`
  under-reads it; `aggregate pattern` over-reads a single-credential blast
  radius.

CPO sign-off: required at plan time per `requires_cpo_signoff: true`; in this
headless pipeline it is recorded here and `soleur:engineering:review:user-impact-reviewer`
runs at review time.

## Observability

The deliverable *is* an observability probe; its own failure modes are what this
section covers.

```yaml
liveness_signal:
  what: probe verdict line (PASS/TRANSIENT/FAIL/CANNOT ESTABLISH) rendered by the sweeper onto the tracker issue; fixture suite in CI asserts every arm stays reachable
  cadence: daily (sweeper cron) when enrolled; per-PR (fixture suite) always
  alert_target: tracker issue comment (enrolled) / CI check failure (always)
  configured_in: .github/workflows/scheduled-followthrough-sweeper.yml + tests/scripts/test-zot-log-channel-probe.sh

error_reporting:
  destination: sweeper-posted issue comment (public) + CI log
  fail_loud: exit 1 posts FAIL verbatim; exit 3 renders CANNOT ESTABLISH so a broken probe never reads as a clean channel

failure_modes:
  - mode: mis-spanned grade (the defect this fixes)
    detection: straddle fixtures in the suite (pre-boundary leak must not exit 1; post-boundary must)
    alert_route: CI check failure pre-merge; CANNOT ESTABLISH comment post-merge
  - mode: probe cannot establish the newest boot (all boot_id absent/unknown, or awk produces no counts)
    detection: exit 3 branch with named reason in the posted comment
    alert_route: tracker issue comment, stays open
  - mode: enrolled-sibling regression from an envelope-shape change
    detection: this plan makes none — 'Explicitly NOT in this diff' pins the template and both sibling probes untouched; 7556/7341 suites run unchanged
    alert_route: their own fixture suites + live trackers

logs:
  where: sweeper workflow log (gh run) + issue-comment verbatim stdout
  retention: Actions retention; issue comments permanent

discoverability_test:
  command: grep -m1 'CANNOT ESTABLISH' scripts/followthroughs/zot-log-channel-7440.sh
  expected_output: "CANNOT ESTABLISH"
  credentials_required: BETTERSTACK_QUERY_* — the property (verdicts graded against live warehouse rows on the newest boot) has no unauthenticated substitute; the fixture suite verifies the arms pre-merge and is deliberately NOT the discoverability command (a suite cannot finish inside the 15s Check-10 cap)
```

## Guard Contract

### Guard 1 — one-pass, newest-boot-scoped verdict

**Property.** Every value a verdict keys on — the boot scope, the delivery proof,
every count, and the leak grade — is produced by one awk pass over the decoded
`dt`-carrying rows of both channels, and no row outside the newest real boot's
scope influences any exit code.

**Assembly.** The chokepoint is the single awk pass; every input row must flow
through `query → envelope anchor → decode-to-TSV → sort → pass`. Members: the
`SOLEUR_ZOT_LOG` result set (envelope + `SOLEUR_ZOT_LOG_DROPPED` +
`SOLEUR_ZOT_LOG_BOOT` rows via substring match) and the `SOLEUR_ZOT_DISK` result
set. There is exactly one second producer of verdict values and it is the
defect: any `grep`/`tail`/variable read of the raw sets outside the pass.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Grade `envelope_hits` unscoped (restore today's behaviour) — a fixture with a leak-shaped row *before* the boundary and clean rows after | RED (probe must not exit 1; mutation exits 1) |
| 2 | The pass emits no summary line (dialect break) — integer guard must fire | RED (must exit 3; a vacuous guard exits 0/2) |
| 3 | A second boot's stamped rows appear after compliant first-boot rows — delivery evidence must name the *newest* boot only | RED (evidence or scope on the older boot) |
| 3b | A `SOLEUR_ZOT_LOG_DROPPED` row (no `host=` field, cannot be host-verified) carrying a *different*, newer `boot_id` than every host-scoped row — it must not select `NEWEST_BOOT` or move the boundary | RED if unscoped stamped rows can choose the evidence base |
| 4 | Control row whose `zot_last_err=` tail carries ` boot_id=FAKE` + ` log_shipper_post_fail=` — the head cut must ignore it | RED if tail text can select the boot or supply the proof token |
| 5 | An in-window `SOLEUR_ZOT_LOG_BOOT` marker on `NEWEST_BOOT` — boundary must tighten so pre-marker envelope rows leave the graded set | RED if the marker is ignored for the boundary |
| 6 | `log_shipper_post_fail=` present only on *old*-boot control rows, zero on newest | RED if delivery reads proven (arm must be `not_delivered`-class, not delivered) |
| 7 | Harness: assert the suite fails when the probe prints the FAIL arm without the `boot=` token — an anti-vacuity row on the verdict message, not only the exit code | RED if message-shape assertions are absent |
| 8 | must-PASS (non-canonical): a stamped `SOLEUR_ZOT_LOG_DROPPED` row and an unstamped envelope row on the same boot — the envelope row still grades (rows without stamps are bounded, not dropped) | PASS required |

### Guard 2 — public-comment discipline (counts-only, no row text)

**Property.** Nothing posted to the public issue contains row payloads — the FAIL
arm emits counts and `boot=`; the PASS arm emits counts; payload-bearing fields
never reach stdout/stderr.

**Assembly.** Every `echo`/`printf` in the probe (the only write path to the
comment) plus the suite's C13-class assertions; the chokepoint is the summary
line — the pass must never emit rows, only scalars.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Echo one raw envelope row in any verdict arm | RED (suite asserts no payload markers in output) |
| 2 | The awk pass prints rows instead of the summary line | RED (integer guard rejects non-scalars) |
| 3 | A second `echo` added after the FAIL counts, printing `auth_leaks` content | RED |

**Anchor.** The fixture corpus is synthesized (`cq-test-fixtures-synthesized-only`)
and the ≥70-assertion floor + harness canary are the anchors: any edit that
removes assertions without updating the floor, or neuters `assert()`, fails the
run. The floor must be raised to the post-change count in the same diff.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "scope the leak grade to the same newest real boot the delivery evidence names (read `boot_id` from the trusted region of each graded row)" [issue #8278] | Proposed Solution steps 3-4; FR-1/FR-2; Phase 1 | mapped — implemented via `dt`-boundary scope over control-row trusted heads; see Alternative A for the literal per-row-stamp reading and its costs |
| 2 | "key delivery on a token only the delivered producer can emit" [issue #8278] | Proposed Solution step 5; FR-3 | mapped |
| 3 | "grade and delivery proof from one awk pass scoped to the newest real boot" [pipeline brief] | Proposed Solution step 4; Guard Contract Guard 1 | mapped |
| 4 | "do NOT re-defer it" [pipeline brief] | Alternative D rejected; the whole plan | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `scripts/followthroughs/zot-log-channel-7440.sh` rewrite | "scope the leak grade to the same newest real boot the delivery evidence names" | asked |
| `tests/scripts/test-zot-log-channel-probe.sh` fixtures/cases | "the fix shape the issue and comments prescribe" — the fixture suite is how a probe's arms are verified in this repo (`hr`-adjacent: failing tests before code is `cq-write-failing-tests-before`) | inferred — justification: a probe change with no fixture diff is unverifiable; the repo's own convention (`tests/scripts/test-zot-log-channel-probe.sh` exists for exactly this probe) makes the test edit inseparable |
| ADR-184 addendum | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`-adjacent record-keeping; ADR-184's amendment block quotes the old `boot_marker(1)` evidence string verbatim and would lie about the live grading shape after this lands |
| Exit 3 (CANNOT ESTABLISH) added to the contract | "delivery keyed on a token only the delivered producer can emit" | inferred — justification: an unmeasurable delivery state must not render under a NOT-YET heading that asserts a wait; 7500/8386 set the family precedent |

### Split Assessment

- Subsystems touched: 3 — `scripts`, `tests`, `knowledge-base`
- Planned files: 3 | Estimated changed lines: ~450 (probe ~300, suite ~130, ADR ~20)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Open Code-Review Overlap

None. Queried 87 open `code-review` issues (2026-10-06) against every planned
path plus the bare script name: zero bodies match.

## Domain Review

**Domains relevant:** engineering (infrastructure/CI tooling). Assessment was
performed inline — this process has no subagent-spawn capability, so no domain
leader Tasks were invoked; the 8-domain semantic sweep found no user-facing,
marketing, finance, legal, operations, support, or product surface.

### Engineering

**Status:** reviewed (inline — no subagent spawn available in this harness)
**Assessment:** CTO/devex lens — the change conforms a bespoke follow-through
probe to the shape two in-repo siblings already settled; the riskiest seam is
the sibling-probe collision surface, mapped above and excluded from the diff.

**Domains relevant:** none besides engineering — infrastructure/tooling change
with no user-facing surface. Product/UX Gate: not triggered (no UI-surface file
in Files to Edit/Create — verified against the ui-surface term set).

## Architecture Decision (ADR/C4)

- `### ADR` — No new ADR. The mechanism (delivery proof keyed on a producer-only
  token, verdicts scoped to the newest real boot, one pass) is ADR-211's existing
  `## Decision` applied to a second channel — an application, not a new decision
  or a divergence. `knowledge-base/engineering/architecture/decisions/ADR-184-*.md`
  gets a short addendum recording the new grading shape (its amendment block
  quotes the retired `boot_marker(1)` evidence verbatim).
- `### C4 views` — **No C4 impact.** Checked `model.c4`, `views.c4`, `spec.c4`:
  (a) external human actors — none new (the sweeper is CI, not a user role);
  (b) external systems — `betterstack` is already modeled including its shared
  multi-tenant Logs source 2457081 and the "polled from GitHub Actions via
  betterstack-query.sh … follow-through soak probes" edge (model.c4 `betterstack`
  description); (c) containers — `zotRegistry` host already modeled; (d)
  relationships — no new edge: the probe runs inside the existing
  `scheduled-followthrough-sweeper.yml` (GitHub system → Better Stack, already
  drawn). No element description is falsified by this change.
- `### Sequencing` — N/A.

## Research Reconciliation — Spec vs. Codebase

No spec exists for this branch (one-shot path, no brainstorm). The issue body's
claims were reconciled directly against the tree: the envelope carries no
`boot_id` (verified at `cloud-init-registry.yml` ~1760) — which is exactly why
Alternative A is a producer change and the chosen design binds by `dt` boundary;
`SOLEUR_ZOT_LOG_DROPPED`/`SOLEUR_ZOT_LOG_BOOT` do carry it (~1573/~2635).

## Acceptance Criteria

### Functional Requirements

- [ ] FR-1: `zot-log-channel-7440.sh` contains no `--since 72h` query and no
  `n_boot`-driven `delivered=` arm; `grep -n '72h\|BOOT_MARKER'` returns no
  load-bearing hit.
- [ ] FR-2: every verdict-keyed value (boot scope, delivery proof, all counts,
  leak grade) comes from one awk pass over `dt`-sorted TSV; no `boot_id` or
  `log_shipper_*` value is read from the raw sets outside the pass.
- [ ] FR-3: delivery evidence names a same-boot source only — control-row
  `log_shipper_post_fail=` on `NEWEST_BOOT`, a `SOLEUR_ZOT_LOG_DROPPED`/
  `SOLEUR_ZOT_LOG_BOOT` row on `NEWEST_BOOT`, or the graded envelope rows
  themselves — and verdicts print `boot=<id>` + the named source.
- [ ] FR-4: the leak grade (exit 1) covers only envelope rows at `dt >=` the
  newest-boot boundary; envelope rows before it are counted as `n_env_pre` and
  never graded.
- [ ] FR-5: `NEWEST_BOOT` unset (no `[0-9a-fA-F-]+` boot_id on any stamped row)
  or a non-integer pass summary → exit 3 CANNOT ESTABLISH; never exit 0 or 1.
- [ ] FR-6: `FLOOR_ROWS` is computed over the bounded span, not the full window,
  when the boundary falls inside it.
- [ ] FR-7: all existing reason tokens and exit-2 arms are preserved (modulo the
  boot-scope now named in their text); the counts-only, no-row-text output
  discipline is unchanged.
- [ ] FR-8: probe header states the one-pass/trusted-region Guard Contract and
  the updated exit table including exit 3.

### Non-Functional Requirements

- [ ] NFR-1: no edit to `apps/web-platform/infra/cloud-init-registry.yml`,
  `zot-upload-ceiling-7556.sh`, `zot-fill-rate-7341.sh`, or the sweeper workflow
  (`git diff origin/main --name-only` excludes all four).
- [ ] NFR-2: POSIX-awk-only pass (no intervals/`[[:classes:]]`/gawk extensions).
- [ ] NFR-3: probe still runs under `env -i` + the three `BETTERSTACK_QUERY_*`
  names only; no new secrets, no workflow edit.

### Quality Gates

- [ ] QG-1: `bash tests/scripts/test-zot-log-channel-probe.sh` — all cases green
  including the new straddle/forgery/vacuity cases; assertion floor updated.
- [ ] QG-2: `bash apps/web-platform/infra/zot-log-shipper.test.sh` green
  unchanged (producer untouched).
- [ ] QG-3: `bash -n` clean on the probe; `shellcheck` no new findings.
- [ ] QG-4: ADR-184 addendum landed in the same diff.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given a window whose pre-boundary envelope rows carry a Doppler-shaped token
  and post-boundary rows are clean, when the probe runs, then it does NOT exit 1
  (the pre-boundary rows are outside the graded set) and reports `n_env_pre>0`.
- Given a leak-shaped envelope row at `dt >=` the newest-boot boundary, when the
  probe runs, then it exits 1 with `reason=credential_shape_in_channel` naming
  `boot=<id>` and counts only.
- Given control rows carrying `log_shipper_post_fail=` only on an *older* boot
  and zero envelope rows on the newest boot, when the probe runs, then
  `reason=not_delivered`-class — never `delivered_but_silent`.
- Given rows whose `zot_last_err=` tail contains ` boot_id=FAKE` and
  ` log_shipper_post_fail=`, when the probe runs, then the boot scope and the
  delivery proof are unaffected (the head cut holds).
- Given a `SOLEUR_ZOT_LOG_BOOT` marker on `NEWEST_BOOT` inside the window, when
  the probe runs, then the boundary tightens to the marker's `dt` and pre-marker
  envelope rows are ungraded.
- Given no `[0-9a-fA-F-]+` boot_id on any row (all `unknown` or absent), when the
  probe runs, then exit 3 — not 0, not 1, not 2.
- Given an awk that emits a partial/non-integer summary, when the probe runs,
  then exit 3 (vacuity guard), never a silent PASS.

### Regression Tests

- Given the C3d drift fixture (drifted boot_id, pre-delivery reporter), then
  `not_delivered` — drift still proves nothing.
- Given the C9 echo-row fixture (heartbeat rows quoting `zotregistry.dev`), then
  no PASS — the positive envelope anchor still holds.
- Given `log_shipper_post_fail=unknown` on the newest boot, then
  `shipper_state_unreadable` on `delivered_but_silent`, unchanged semantics.

### Edge Cases

- Reboot (not replace) mid-window: the new boot's rows grade; pre-reboot rows are
  `n_env_pre` — acceptable because the producer code is identical across an
  instance's reboots; recorded residual.
- Boundary inside the window: `FLOOR_ROWS` computed over the bounded span — no
  systematic post-replace false `below_expected_floor`.
- Window older than BOOT-marker retention (>3 d): verdicts unaffected — the
  marker is no longer load-bearing.

### Integration Verification

- `bash tests/scripts/test-zot-log-channel-probe.sh` expects `=== <N> passed, 0 failed ===`.
- `git diff origin/main --name-only -- apps/web-platform/infra/cloud-init-registry.yml`
  expects empty output (no replace fires).

## Success Metrics

- The `exit 1` arm can only fire on rows produced by the same boot whose delivery
  was established — the defect class is structurally unreachable, matching the
  post-#7960 state of `zot-last-err-redact-7500.sh`.
- Zero open-issue directive state changed; the probe stays latent until its own
  re-enrollment trigger, now with the fix already landed.

## Dependencies & Risks

- `scripts/betterstack-query.sh` JSONEachRow + `dt` contract (unchanged consumer).
- The `SOLEUR_ZOT_DISK` heartbeat continues to carry `boot_id=` and
  `log_shipper_*` in its trusted head — a producer-side rename breaks the
  derivation; the suite's trusted-head cases cover the reading side.
- Residual: ±5-min boundary precision vs per-row stamps (Alternative A) — a
  pre-replace envelope row inside the first-heartbeat gap could in principle be
  graded with the new boot; direction is fail-loud for exit 1 and conservative
  for PASS, and the window is ~minutes once per replace.
- No host replace, no enrolment change, no secret change.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, placeholder, or omits the
  threshold fails deepen-plan Phase 4.6 — it is filled above.
- The boundary derivation must never let a `zot_last_err=` tail or an envelope
  payload supply `boot_id`/`host=`/`log_shipper_*` — one fixture per forgery, not
  a comment.
- Do not "simplify" the integer guard or the `@tsv` carry-through: both are
  load-bearing (dialect error → false close; record split → synthetic trusted
  head).
- The fixture suite's floor must move with the diff in the same commit — a floor
  left at the old count is a vacuity hole.
- If a future edit adds `boot_id=` to the envelope (Alternative A), the sibling
  prefix-strip parsers (`zot-upload-ceiling-7556.sh`, `zot-fill-rate-7341.sh`) must
  be updated in the same PR and `registry-host-replace-dispatch.yml` will fire a
  production replace on merge.

## References & Research

- Issue: #8278 (this fix); #7960 (same defect class, fixed by PR #8272);
  tracker #7455 (CLOSED); related-but-not-overlapping: #7456, #7556, #7530,
  #7959, #8698, #9373.
- Reference implementations: `scripts/followthroughs/zot-last-err-redact-7500.sh`
  (PR #8272); `scripts/followthroughs/registry-luks-live-8386.sh`;
  ADR-211 `### Delivery proof: err_redact_rev`; ADR-184 (channel decision record).
- Producer: `apps/web-platform/infra/cloud-init-registry.yml` ~1012 (heartbeat
  row), ~1285 (`BOOT_ID`), ~1573 (DROPPED row), ~1760 (envelope), ~2635 (BOOT
  marker).
- Convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`;
  sweeper: `.github/workflows/scheduled-followthrough-sweeper.yml`;
  delivery trigger: `.github/workflows/registry-host-replace-dispatch.yml`.
