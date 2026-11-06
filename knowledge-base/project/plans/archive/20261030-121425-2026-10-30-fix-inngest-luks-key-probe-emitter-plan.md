---
title: "infra(observability): inngest_luks_key_probe_fail SQL anchors the marker but pins no emitter"
type: fix
date: 2026-10-30
slug: fix-inngest-luks-key-probe-emitter
branch: feat-one-shot-11527-luks-key-probe-emitter
issue: 11527
priority: p3
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# infra(observability): inngest_luks_key_probe_fail SQL anchors the marker but pins no emitter

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No spec.md exists for this branch; the pipeline runs plan before spec here.)

## Enhancement Summary

**Deepened on:** 2026-10-30
**Agents used:** none — this deepen ran inside a pipeline subagent with no Task/Agent tool, so the §4 halt gates, the precedent-diff, and the verify-the-negative pass were executed inline by the planning agent (mirroring both sibling runs).

### Gate verdicts (all evaluated inline)

- §4.4 Precedent-diff: pass — the emitter-OR shape mirrors the shipped `inngest_luks_wrong_volume_sql` (:306-331) in the same file; the marker-override arm is the convention ADR-218's 2026-10-29 amendment names for this issue.
- §4.45 verify-the-negative: every negative claim re-verified by reading the emit sites and envelope constructor (`luks_probe_finish` dual-emit unconditional; `detail` key-absent on journald rows; exactly-1 `luks-key-probe` emit site; no third marker emitter).
- §4.5 network-outage: evaluated, skipped — no SSH/network symptom; the changed resource carries no provisioner/`connection` block.
- §4.55 downtime: skipped — in-place Better Stack exploration update; no host, volume, DB, or deploy-surface touched.
- §4.6 User-Brand Impact: pass (section present, threshold `aggregate pattern`, concrete artifact/vector).
- §4.7 Observability: pass (5 fields populated; `discoverability_test.command` is `grep -c`, an allowlisted verb under the 15 s cap, `expected_output` the literal `1`).
- §4.8 PAT-shaped variable: pass (grep clean — `BETTERSTACK_QUERY_*` are ClickHouse read credentials, not GitHub PAT shapes).
- §4.9 UI-wireframe: skipped (no UI-surface files).
- §4.10 Encryption Posture: pass (triggered by `.tf` edit; all fields populated, `does_not_defend` non-empty, no exception needed).
- §4.11 Guard Contract: pass — `scripts/lint-guard-contract.py` green (1 guard entry); assembly is structural (the WHERE clause chokepoint + the guard's extracted `FAIL_SQL` + the emit-site literal authorities), not a member list.
- §4.12 Scope Check: pass (exactly one unfenced section; all asks mapped; inferred items carry justifications; split assessment derived from the file lists).
- §4.13 Task Design: skipped (modifies an existing alert; no new workflow/timer/daemon surface).

### Key improvements from the deepen pass

1. **`detail=''` fail-loud arm placed inside leg B, not top-level** — the empty-disjunct learning measured that a conjunct-only predicate cannot deliver detail-absent fail-loud, and `detail` is key-absent on journald rows (a top-level `OR detail=''` would admit every leg-A row); the token check is therefore leg-scoped (`message` on A, `detail` on B), equivalent on every real row since leg-B `message` ≡ marker + `stage=luks-key-probe` + detail. Recorded as decision-challenges row D2 `pending - assumed:`.
2. **Derived needles, call-form anchored** — `MUT_TAG` from `readonly LOG_TAG=`, `MUT_STAGE` from the bounded first arg of the phone-home call form, `MUT_SHIPPER` from the payload builder; exactly-1 emit-site cardinality verified live (`inngest-cutover-flip.sh:953` is the sole `luks-key-probe` caller).
3. **Dual-emit caveat made explicit** — unlike the sibling's vector-gated fallback, this probe dual-emits unconditionally, so `value` can read 2 for one event; harmless under `higher_than 0`, recorded per the amendment's dedup caveat.
4. **Inert-probe enumeration caveat** — the probe is merged-but-inert until #11266 delivers, so control A may read 0 real rows; the synthetic control E carries leg-semantics verification and the foreign-emitter census is still the enumeration the issue asks for.

### New considerations discovered

- The jq-failure fallback payload carries no `shipper`/`detail` → silently uncounted under the emitter OR (same boundary as the sibling's T1 dissent); recorded as a residual edge in the `.tf` comment requirement.
- Two existing `token=fail_` mutation needles become dual-occurrence under the new shape (message + detail forms) — retargeted to the `message`-extracted needle per the sibling's measured lesson.
- `scripts/followthroughs/inngest-luks-keeper-dark-11265.sh` is a sibling consumer of the same marker with the position-1 anchor — unaffected (independent query), recorded for census completeness.

## Overview

The Better Stack Logs alert `logtail_exploration_alert.inngest_luks_key_probe_fail` pages when the dedicated Inngest host's LUKS key-continuity probe reports a `token=fail_*` verdict — the key the host holds no longer opens the volume's LUKS2 header. Its predicate (`local.inngest_luks_key_probe_fail_sql` in `apps/web-platform/infra/betterstack-logs-alerts.tf`) anchors the `SOLEUR_INNGEST_LUKS_KEY_PROBE` marker at message position 1 and matches `token=fail_`, but pins no emitter — the same latent class the sibling wrong-volume alert fixed under the ADR-218 dual-channel convention, complicated here by the probe's deliberate dual-path emit (journald tag `inngest-cutover-flip` plus a curl-direct phone-home whose message begins with the marker via the arg-3 override). #11527 asks for a live emitter enumeration, a predicate that admits exactly the two real delivery paths, drift-guard extension, and the dated LIVE-PROBED record.

## Research Insights

**Premise Validation (Phase 0.6).** Every cited reference re-verified 2026-10-30: issue #11527 is `OPEN` (`domain/engineering`, `meta/machinery`, `priority/p3-low`); `local.inngest_luks_key_probe_fail_sql` exists at `apps/web-platform/infra/betterstack-logs-alerts.tf:427-433` with exactly the two conjuncts the issue describes — marker at message position 1 plus `token=fail_`, no emitter pin (the issue's `:350-356` line range is stale; the local moved down-file after the #11526 leg-B merge). The dual-path emit evidence matches the ADR-218 amendment's citation: `apps/web-platform/infra/inngest-cutover-flip.sh:952` journald (`logger -t "$LOG_TAG"`, `LOG_TAG="inngest-cutover-flip"` at :102) and `:953` phone-home (`inngest-boot-phone-home.sh "luks-key-probe" "$row" SOLEUR_INNGEST_LUKS_KEY_PROBE` — the arg-3 marker override), both unconditional inside `luks_probe_finish` (every run dual-emits, unlike the sibling's vector-gated fallback); `cloud-init-inngest.yml` builds `{message:($m+" stage="+$s+" "+$d), marker:$m, stage:$s, detail:$d, host:$h, dt:$t, shipper:"cloud-init-phone-home"}` so the phone-home `message` begins with the marker and the position-1 anchor reads both channels — while its jq-failure fallback payload carries NO `shipper`/`detail` (silently-uncounted edge). PR #11519 `MERGED` 2026-10-29T18:44Z (the #8874 sibling fix); the dual-path OR convention shipped 2026-10-29 as squash f9f4f2b2 (PR #11559, Ref #11526); #11388 `CLOSED`; #11528 `OPEN` and out of scope; #11266 `OPEN` — the probe is merged-but-inert until the owner delivers the signed bundle, so the live enumeration's real-probe population may read 0 (the alert is presence-only by design). Mechanism check vs the ADR corpus: the proposed OR-over-emitter-identity is the shape ADR-218's 2026-10-29 amendment (#11526) explicitly rules for this issue — marker-override arm, not a rejected alternative. Collision pre-check (`collision-precheck.sh 11527`, exit 10): open PR #11601 names #11527 but is THIS branch's own auto-created draft; the foreign `test-all.sh` processes (pids 1394271, 1471263, 1471423, 1471876, 1471909) belong to the unrelated in-flight `feat-11556-required-check-time` worktree. Open `code-review` issues: none touch the planned files (checked `gh issue list --label code-review --state open`, all four paths).

**Property List (Phase 0.6b).** The asks restated as observable properties: (1) a row counted by this alert is always one the probe itself emitted — a row that merely *quotes* the marker under any other emitter (the `doppler` event-log class #8846 measured on the sibling) can never satisfy the predicate; (2) BOTH delivery channels the emitter can take are admitted — the journald path under `SYSLOG_IDENTIFIER='inngest-cutover-flip'` and the phone-home path under `shipper='cloud-init-phone-home' AND stage='luks-key-probe'` — so a Vector outage does not blind the alert; (3) the change is proven against live warehouse data before it is applied, not just by reading the SQL; (4) the drift guard pins the new conjuncts' source — a revert or rename must redden it, not pass silently.

**Cut List (Phase 0.6b).** Nothing cut — the issue names exactly two mechanism requirements (live emitter enumeration; a predicate that pins the row set without dropping the phone-home path) and both are load-bearing for properties (1)-(2). No existing mechanism covers them: the position-1 marker anchor excludes today's quoting rows only as an accident of webhook payload formatting (`{`-prefixed), not a control.

**Relevant file paths.**

- `apps/web-platform/infra/betterstack-logs-alerts.tf:427-433` — `inngest_luks_key_probe_fail_sql` (the predicate being pinned); `:405-436` the `#9927 item 2` comment block whose SQL RULES paragraph prescribes the position-1 anchor and `dt`-column window filter; `:439-519` the `logtail_exploration` + `logtail_exploration_alert` resources (`threshold`/`higher_than 0`, `check_period 300`, `query_period 900`, `recovery_period 3600`, `treat_as_zero`, `paused = false`, email+push — params measured live per the #11427 422 saga). The merged sibling `inngest_luks_wrong_volume_sql` at `:306-331` is the shipped dual-path OR precedent in this file.
- `apps/web-platform/infra/inngest-cutover-flip.sh:102, 943-956` — `LOG_TAG="inngest-cutover-flip"` and `luks_probe_finish`: `logger -t "$LOG_TAG" "SOLEUR_INNGEST_LUKS_KEY_PROBE ${row}"` then `inngest-boot-phone-home.sh "luks-key-probe" "$row" SOLEUR_INNGEST_LUKS_KEY_PROBE` — both unconditional; `row = "token=${tok} rc=${rc} at=${at}"`, `at=` literals `died|key|mount|status|uuid|mem|shield|kdf` (single-word, never `token=fail_`-bearing). Closed token set `ok|fail_passphrase|fail_header|fail_key_absent|indeterminate` pinned by the guard.
- `apps/web-platform/infra/cloud-init-inngest.yml` (~:497-575) — the phone-home emitter: arg-3 marker override contract; jq envelope carries `shipper:"cloud-init-phone-home"` + `stage`/`detail`; the jq-failure payload carries neither `shipper` nor `detail`; POST target is the same source 2457081.
- `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` — the drift guard: `FAIL_CANON` whole-SQL whitespace-insensitive equality (:103), 30 presence + 30 mutation rows, `PRESENCE_ROWS=30`/`MUT_ROWS=30`, instrument self-test + pristine-tree control, marker-based census pinning exactly `inngest_luks_key_probe_fail`, NEGATIVE rows pinning the dead-man's absence (D12). Baseline: `60 passed, 0 failed` (measured 2026-10-30). Registered in `.github/workflows/infra-validation.yml:897`.
- `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` — the sibling guard that shipped the dual-path assertions: call-form-anchored `MUT_STAGE` derivation, `MUT_SHIPPER` from the payload builder, per-leg needles, OR-structure presence row, reserved-token cardinality check.
- `.github/workflows/apply-web-platform-infra.yml:655-656` — both key-probe resources already in the `-target=` allowlist; merging IS the apply path.
- `scripts/betterstack-query.sh` — live-probe transport: raw-SQL mode with `$BS_TABLE`/`$BS_TABLE_S3` over `remote()` + `s3Cluster`; `SELECT dt, raw` in BOTH union arms (`SELECT *` hits TYPE_MISMATCH — the archive carries extra columns); credentials via `doppler run -p soleur -c prd_terraform` (read-only).
- `.github/workflows/scheduled-terraform-drift.yml` — standing post-apply live-vs-declared readback (`terraform plan -detailed-exitcode`).
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (~:26-34) — the standing-alarms row for this alert; the wrong-volume row above it already carries the dual-channel note this change mirrors.
- `knowledge-base/engineering/architecture/decisions/ADR-218-*.md` (~:560-620) — the 2026-10-29 amendment "the dual-channel predicate convention" that rules this issue's fork and names #11527 by number.
- `knowledge-base/engineering/architecture/diagrams/model.c4:792` — the `inngest -> betterstack` edge: names the phone-home channel, the key-probe marker's dual emit, and that the wrong-volume alert reads both channels since #11526 — the key-probe alert's own dual-channel read is the gap this change closes in the text.
- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md:604` — the row contract (`token=<tok> rc=<n> at=<literal>`, two delivery channels, no key/UUID/device id/hash/stderr).
- `scripts/followthroughs/inngest-luks-keeper-dark-11265.sh` — a sibling CONSUMER of the marker (the keeper-dark probe); reads with the same position-1 anchor; out of scope, unaffected — noted so the census of marker consumers is complete.

**Institutional learnings applied.**

- `learnings/security-issues/2026-10-29-call-form-anchored-needles-and-the-empty-disjunct-fail-loud.md` (#11526/PR #11559): derive guard needles from the CALL FORM with a bounded arg, never a bare-substring grep; pin the reserved `stage` token's emit-site cardinality to exactly 1; a conjunct-only predicate cannot deliver a detail-absent fail-loud — only an explicit `detail = ''` disjunct admits the absence into the counted set (measured E3=0 under conjuncts, 1 with the disjunct on the sibling).
- `learnings/security-issues/2026-10-29-derive-the-needle-and-verify-the-fallbacks-actual-args.md` (#8874/PR #11519): derive the emitter needle from the canonical source (here `LOG_TAG` at the emit site, not a re-pinned literal) so a coordinated rename that misses the `.tf` goes red; verify the fallback's actual args before accepting a coverage claim.
- `2026-09-27-a-presence-check-after-source-is-satisfied-by-the-environment.md` (#8846): a log row's identity is its emitter, never its message content — the `doppler` event log on the same host quotes probe text verbatim (measured 50 quoting rows vs 6 real rows in one 6h window on the sibling).
- `2026-10-09-i-carried-a-measured-dt-claim-from-one-emitter-onto-another.md` (#9784): the phone-home envelope POSTs its own `dt`; whether the warehouse honors the self-attested value is unmeasured — recorded residual edge.
- `2026-07-03-pass-is-not-proof-three-vacuous-green-traps-in-infra-verification.md`: the live-probe controls include a positive control that must equal the emitter-OR row count, never just "query ran".

**External research.** Skipped — the predicate shape is pinned by the ADR-218 amendment (which names this issue), the shipped sibling SQL in the same file, the envelope contract, and the issue text; nothing external to decide. Community/functional discovery (Phases 1.5/1.5b): no uncovered stacks and no community-tool overlap for a repo-internal alert predicate; no spawn capability exists at this level regardless — recorded, not silently skipped. Network-outage check (Phase 1.4): no trigger patterns — no SSH/network symptom is addressed and the changed resource carries no provisioner/`connection` block.

**Does merging this alone mutate production?** Yes — `betterstack-logs-alerts.tf` is under `apps/web-platform/infra/**`, so the merge fires the push-triggered apply, which updates the live exploration's stored SQL in Better Stack. The PR body's first line must state this (the merge click is the authorization act).

## Problem Statement / Motivation

`local.inngest_luks_key_probe_fail_sql` counts a row as evidence when (a) its message *begins with* the `SOLEUR_INNGEST_LUKS_KEY_PROBE` marker and (b) the message contains `token=fail_`. What it never checks is **who emitted the row** — the defect class #8846 measured live on the sibling probe (50 quoting `doppler` event-log rows vs 6 real probe rows in one 6h window) and #8873 fixed in every bash/jq/python consumer; the sibling wrong-volume alert's SQL was the last unpinned consumer until #8874 added the journald conjunct and #11526 added the phone-home leg. This alert is the remaining same-class residual (#11527).

The key probe is deliberately dual-path, which is why this is NOT a one-line conjunct like #8874's: `luks_probe_finish` in `inngest-cutover-flip.sh` emits every verdict row twice — `logger -t inngest-cutover-flip` (the journald path Vector ships) AND `inngest-boot-phone-home.sh "luks-key-probe" "$row" SOLEUR_INNGEST_LUKS_KEY_PROBE` (the curl-direct path, independent of Vector at the credential level). A pure `SYSLOG_IDENTIFIER = 'inngest-cutover-flip'` conjunct would drop the phone-home rows — exactly the rows that survive a Vector outage, which is also the window in which a LUKS/key failure is most plausible. The fix needs the emitter enumeration first (which emitters actually carry marker-anchored rows), then a predicate that admits exactly those paths and nothing else.

Today the position-1 anchor alone saves the alert only because every quoting row happens to begin with `{` — a webhook-payload formatting accident, not a control. The first quoting row whose message begins with the marker text and contains `token=fail_` (an event-log echo of a probe line, a reshaped webhook payload) satisfies both conjuncts and pages on a forgery; the same unpinned row set can also mask — a mis-authored predicate change is invisible until it false-pages or goes quietly blind.

## Proposed Solution

Apply the ADR-218 2026-10-29 amendment's dual-channel convention in its **marker-override arm** — the arm the amendment names for this exact issue: because the fallback caller passes `SOLEUR_INNGEST_LUKS_KEY_PROBE` as the phone-home arg-3 override, the phone-home `message` itself begins with the marker, so the position-1 anchor and the `token=fail_` check read BOTH channels with no marker OR-leg. The emitter pin is an OR over emitter identity — leg A the journald tag, leg B the phone-home envelope's `shipper`+`stage` equality:

```sql
  inngest_luks_key_probe_fail_sql = <<-SQL
    SELECT toDateTime({{end_time}}) AS time, count(*) AS value
    FROM {{source}}
    WHERE dt BETWEEN {{start_time}} AND {{end_time}}
      AND position(JSONExtractString(raw, 'message'), 'SOLEUR_INNGEST_LUKS_KEY_PROBE') = 1
      AND (
        JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'inngest-cutover-flip'
        AND position(JSONExtractString(raw, 'message'), 'token=fail_') > 0
        OR (
          JSONExtractString(raw, 'shipper') = 'cloud-init-phone-home'
          AND JSONExtractString(raw, 'stage') = 'luks-key-probe'
          AND (
            JSONExtractString(raw, 'detail') = ''
            OR position(JSONExtractString(raw, 'detail'), 'token=fail_') > 0
          )
        )
      )
  SQL
```

`AND` binds tighter than `OR`, so the parenthesized group parses as `(leg-A conjuncts) OR (leg-B group)` and the `dt BETWEEN` filter plus the position-1 marker anchor wrap both — the same parenthesized shape the merged sibling uses.

Design choices, each load-bearing:

- **Marker + token semantics preserved on both channels.** Leg A reads `token=fail_` on `message` (the journald row IS the plain-text marker line). Leg B reads `token=fail_` on `detail` — the envelope's isolated field carrying `token=<tok> rc=<n> at=<literal>`; `message` on that channel is `SOLEUR_INNGEST_LUKS_KEY_PROBE stage=luks-key-probe <detail>`, so the two reads are equivalent on every real row and `detail`-anchoring is the sibling convention (fields out of `detail`, never `marker`). `indeterminate` still never pages — it matches neither `token=fail_` check.
- **`shipper`+`stage` envelope equality for leg-B identity, not `marker`** — the marker field IS `SOLEUR_INNGEST_LUKS_KEY_PROBE` on this call site (arg-3 override), but `stage='luks-key-probe'` pins the call site itself while `shipper='cloud-init-phone-home'` pins the emitter class — the `inngest-tls-soak-10136.sh` envelope contract and the convention the amendment records. A foreign emitter would have to forge the whole `shipper`+`stage` envelope, which requires the ingest credential — the same trust boundary as any phone-home emit.
- **The `detail = ''` disjunct (D2-assumed arm).** A `shipper`+`stage` row whose `detail` is empty or absent carries the emitter's identity but no verdict — the schema-drop / degraded-emit class the sibling's measured T4 ruling counts as fail-loud ("unreadable answer ≠ clean answer"; `position('') = 0` otherwise rejects it before any field check — `learnings/security-issues/2026-10-29-call-form-anchored-needles-and-the-empty-disjunct-fail-loud.md`). The disjunct is INSIDE leg B because `detail` is key-absent on journald rows — a top-level `OR detail = ''` would admit every leg-A row regardless of token. This is the recorded caveat whose shape the live enumeration settles: if the enumeration or review prefers the strict shared form (drop the `detail = '' OR` fragment and hoist the token check back to a shared `message` conjunct), the alternative is `AND position(message,'token=fail_')>0` top-level plus the bare emitter OR — recorded in `decision-challenges.md` row D2.
- **No per-run dedup needed.** This emitter dual-emits UNCONDITIONALLY (unlike the sibling's vector-gated fallback): every probe run lands one row on each channel, so a failing verdict can read `value = 2`. Harmless under `operator = "higher_than", value = 0` — the threshold assumption the amendment requires recording when copying the convention.
- **jq-failure envelope stays uncounted (recorded edge).** The payload fallback (`{"message","marker","stage","host"}` — no `shipper`, no `detail`) satisfies the marker anchor but never the `shipper` conjunct — silently uncounted, same boundary the sibling's CTO T1 dissent recorded. The `dt` field is self-attested and unmeasured (#9784) — same residual edge.

Then live-probe the new predicate before merge, land it through the merge-triggered apply, and read it back through drift detection.

## Technical Considerations

- **Two failure directions, same as the sibling.** A syntax error in the heredoc breaks the exploration query (visible as drift/absence, not silence); a wrong leg literal (`SYSLOG_IDENTIFIER`/`shipper`/`stage`) makes that arm permanently zero — which `treat_as_zero` reads as healthy in exactly the degraded window leg B exists for. The drift guard's derived-needle presence + mutation rows plus the pre-merge live-probe cover both.
- **The `inngest-cutover-flip` tag is multi-purpose.** The same script emits the 30 s cutover FSM heartbeat under this tag (JSON strings); leg A admits every journald row under it but the shared marker + token conjuncts scope the count to probe fail rows — the emitter pin's job is excluding FOREIGN emitters, which equality on `SYSLOG_IDENTIFIER` does.
- **Whole-window aggregate, no GROUP BY, `dt` column filter** — unchanged invariants the existing presence rows already pin; the restructure keeps them true.
- **Emit-site needles, not re-pinned literals.** Leg A's literal derives from `readonly LOG_TAG="inngest-cutover-flip"`; leg B's `stage` derives from the bounded first arg of the phone-home call form at `inngest-cutover-flip.sh:953`; `shipper` derives from the payload builder's `shipper:"…"` in `cloud-init-inngest.yml`. A coordinated rename that misses the `.tf` goes red instead of re-pinning stale (the two 2026-10-29 learnings).
- **`stage` literal cardinality.** `stage` is positional `$1` on the shared `inngest-boot-phone-home.sh` helper with ~16 call sites across emit scripts; `luks-key-probe` must have exactly ONE emit site (the FLIP file's `:953`) — a second emitter passing the same stage is a leg-B identity collision the predicate cannot see. The guard pins the count.
- **Sibling-consumer stability.** `scripts/followthroughs/inngest-luks-keeper-dark-11265.sh` reads the same marker with the position-1 anchor (independent query, unaffected); `betterstack-alert-structure.test.sh` derives the exploration↔alert set dynamically (unaffected); `inngest-cutover-flip.test.sh`/`inngest-cutover-latch.test.sh` exercise the emit path (unchanged). `inngest-luks-key-probe-alert.test.sh`'s existing NEGATIVE rows (dead-man absent, D12) and the marker-based census (`KEY_PROBE_EXPLORATIONS='inngest_luks_key_probe_fail'`) are unaffected — the OR adds no new resource.
- **Inert-probe caveat.** The probe is merged-but-inert until #11266 delivers the signed bundle: the live enumeration may measure zero real probe rows (expect quoting rows under foreign emitters to be the only hits, if any). Controls A/B/D record whatever the window holds; the synthetic control E carries the leg-semantics verification regardless of window emptiness — the alert is presence-only by design and its first real row is its own positive control post-delivery.
- **Pre-existing CI red.** `deploy-script-tests` is red on `main` from an unrelated `vinngest` tag/pin drift (`cloud-init-inngest-bootstrap.test.sh` AC6) owned by another in-flight worktree — verification distinguishes pre-existing reds from this diff's at gate time.
- **No consumer census impact.** `scripts/lint-betterstack-emitter-read.sh` (#8875) censuses files that *invoke* `betterstack-query.sh`; a `.tf` that only declares SQL stays outside its population.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality (checked 2026-10-30) | Plan response |
|---|---|---|
| "local … (`betterstack-logs-alerts.tf:350-356`, added by #11260 on 2026-10-27) anchors `SOLEUR_INNGEST_LUKS_KEY_PROBE` at position 1 with a `token=fail_` conjunct but pins no emitter" | Confirmed at `:427-433` (line numbers drifted after the #11526 leg-B merge): exactly the two conjuncts, no emitter pin. | Add the emitter OR as prescribed. |
| "journald tag `inngest-cutover-flip` (`infra/inngest-cutover-flip.sh:952`) PLUS a markerless-`SYSLOG_IDENTIFIER` phone-home leg (`:953`)" | Confirmed: `:952` logger under `LOG_TAG='inngest-cutover-flip'` (:102); `:953` phone-home with arg-3 marker override — the phone-home message BEGINS with the marker, so "markerless" refers to the envelope carrying no `SYSLOG_IDENTIFIER`, not no marker. | Position-1 anchor reads both channels (marker-override arm of the convention); leg-B identity on `shipper`+`stage`. |
| "an OR over the journald tag and the phone-home `stage` field" | Matches the ADR-218 amendment's ruled shape for this issue — cited, not re-derived. | Implement the OR over emitter identity. |
| "the companion issue on the wrong-volume alert's fallback redesign" | #11526 — shipped 2026-10-29 (squash f9f4f2b2) as the dual-channel predicate convention amendment this plan applies. | Mirror its shipped SQL shape and guard recipe. |

## Implementation Phases

### Phase 1 — Predicate + comment + guard + docs (one commit)

1. `apps/web-platform/infra/betterstack-logs-alerts.tf`: restructure `local.inngest_luks_key_probe_fail_sql` to the emitter-OR shape in Proposed Solution (marker anchor + `dt` filter shared; leg A `SYSLOG_IDENTIFIER='inngest-cutover-flip'` + `token=fail_` on `message`; leg B `shipper='cloud-init-phone-home'` + `stage='luks-key-probe'` + `detail = '' OR token=fail_` on `detail`). Extend the local's comment block: the SQL RULES paragraph gains the emitter-identity sentence (the row set is pinned to the probe's two real emitters per the ADR-218 dual-channel convention — a marker-quoting row under any other emitter can never count, the `{`-prefix exclusion was incidental per #8846); record the residual edges (jq-failure payload silently uncounted — no `shipper`; `detail=''` fails loud inside leg B only; self-attested `dt` unmeasured; `value` may read 2 for one event under `higher_than 0`); scaffold the dated `LIVE-PROBED` entry (Phase 2 fills counts). `terraform fmt -check` on the file.
2. `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh`:
   - Header "WHY EACH ROW EXISTS": add a bullet — the row set is pinned to the probe's two emitters (`inngest-cutover-flip` journald tag OR `shipper='cloud-init-phone-home'` + `stage='luks-key-probe'` envelope), so a marker-quoting row under any other emitter can never count and a Vector outage cannot blind the alert (#11527).
   - `FAIL_CANON` rewritten to the new whitespace-stripped canonical form.
   - Derived needles (call-form anchored, FATAL-on-empty, mirroring the sibling guard): `MUT_TAG` from `readonly LOG_TAG="…"` in `$FLIP`; `MUT_STAGE` from the bounded first arg of the `inngest-boot-phone-home.sh` call form in `$FLIP`; `MUT_SHIPPER` from `shipper:"…"` in `apps/web-platform/infra/cloud-init-inngest.yml`.
   - New presence rows (+6): leg-A `SYSLOG_IDENTIFIER` equality (needle `${MUT_TAG}`); leg-B `shipper` equality (`${MUT_SHIPPER}`); leg-B `stage` equality (`${MUT_STAGE}`); leg-B `detail`-anchored `token=fail_`; leg-B `detail = ''` fail-loud disjunct; the OR-arm structure (`OR (` grouping the two emitter identities under the shared conjuncts — pin shape, not just tokens).
   - Reserved-token cardinality: exactly 1 emit site passes `luks-key-probe` as the phone-home helper's first arg across the emit scripts (non-comment lines).
   - Retarget the two existing mutation needles whose `old` strings now match twice (the `token=fail_` conjunct text occurs on both `message` and `detail`): pin them to the `message`-extracted form (the sibling's measured dual-occurrence lesson).
   - New `mutate_red` rows (+7): (a) leg-A emitter conjunct dropped; (b) leg-A literal flipped to `'doppler'`; (c) leg-B `shipper` conjunct dropped; (d) leg-B `stage` conjunct dropped; (e) `stage` literal flipped to a foreign stage; (f) the whole `OR (…)` emitter arm deleted (predicate collapses to leg-A only); (g) `detail = '' OR` disjunct neutralized (the fail-loud arm silently dropped).
   - Floors: `PRESENCE_ROWS=30` → `36`, `MUT_ROWS=30` → `37`, `_floor 60` → `73`, `MUT_SKIP` floor `30` → `36`; verify the arithmetic at implementation (deepen-plan re-verifies).
3. Run `bash apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` locally — expect `73 passed, 0 failed`. Run `bash apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` and `bash apps/web-platform/infra/betterstack-alert-structure.test.sh` — both must stay green (adjacent guards).
4. `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`: extend the `inngest_luks_key_probe_fail` standing-alarms row (~:26-34) with the dual-channel note — the predicate pins both emitters (journald tag OR `shipper`+`stage` envelope), the readback for phone-home rows selects `.shipper == "cloud-init-phone-home"` + `.stage == "luks-key-probe"`, and a page whose row carries empty `.detail` is the fail-loud degraded-emit arm.
5. `knowledge-base/engineering/architecture/diagrams/model.c4`: amend the `inngest -> betterstack` edge (~:792) so the key-probe sentence notes the alert's predicate reads BOTH emitters since #11527 (the edge already names the channel and the marker's dual emit). Then `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` must pass (the runner the sibling PR verified; `bunfig.toml` blocks `bun test` discovery).

### Phase 2 — Enumerate emitters + live-probe the new predicate (pre-merge, required by #11527)

Raw-SQL mode over the hot `remote()` UNION `s3Cluster` archive, 48 h, `dt`-column window, `SELECT dt, raw` in BOTH arms (`SELECT *` hits TYPE_MISMATCH — the archive carries extra columns):

```bash
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  'SELECT count() AS n FROM (
     SELECT dt, raw FROM remote($BS_TABLE)    WHERE dt >= now() - INTERVAL 48 HOUR
     UNION ALL
     SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE dt >= now() - INTERVAL 48 HOUR
   ) WHERE <PREDICATE> FORMAT JSONEachRow'
```

with `<PREDICATE>` successively:

- **A — the enumeration (issue AC #1):** `position(JSONExtractString(raw,'message'),'SOLEUR_INNGEST_LUKS_KEY_PROBE') = 1` GROUP BY `JSONExtractString(raw,'SYSLOG_IDENTIFIER')`, `JSONExtractString(raw,'shipper')`, `JSONExtractString(raw,'stage')` → every emitter carrying marker-anchored rows in the window. The new OR must cover every REAL probe emitter here and exclude every foreign one; record whatever the window holds (real probe rows may be 0 while the bundle is undelivered — the alert is presence-only by design).
- **B — phone-home stage census:** `JSONExtractString(raw,'shipper') = 'cloud-init-phone-home'` GROUP BY `JSONExtractString(raw,'stage')` → which stages exist (proves the envelope fields resolve on real rows); plus the `stage='luks-key-probe'` count alone.
- **C — quiet control:** the full new predicate → expect `n = 0` (no `fail_` rows; probe inert or healthy).
- **D — coverage control:** `position(message,MARKER)=1 AND (the emitter OR)` vs the bare `position(message,MARKER)=1` count from A's total — the difference is exactly the foreign-emitter class the pin excludes; equal is the clean answer, a positive difference enumerates excluded quoting rows.
- **E — leg semantics on synthetic raw (no ingest write):** evaluate the full WHERE over `SELECT '<literal raw envelope>' AS raw` literals — (E1) journald `SYSLOG_IDENTIFIER='inngest-cutover-flip'` + `token=fail_passphrase` row → `1`; (E2) same with `token=ok` → `0`; (E3) phone-home envelope `shipper`+`stage` + `detail='token=fail_header rc=1 at=kdf'` → `1`; (E4) same with `token=ok` → `0`; (E5) `shipper`+`stage` with `detail` absent/empty → `1` (the D2 fail-loud arm; under the strict shared form this is `0` and becomes a recorded exclusion); (E6) the jq-failure payload shape (no `shipper`) → `0` (recorded silently-uncounted edge); (E7) a `SYSLOG_IDENTIFIER='doppler'` row whose message begins with the marker and contains `token=fail_` → `0` (the forgery class the fix kills).

Record the window and all numbers into the `.tf` `LIVE-PROBED` comment block.

### Phase 3 — Apply through the normal path (merge-triggered)

1. PR body first line states the merge-mutates-production disclosure; body carries `Ref #11527`, **not** `Closes` — the live change lands at the merge-triggered apply ("ARMING HAPPENS ON THE APPLY, NOT AT MERGE"; the sibling's CTO T2 ruling for the identical situation).
2. The push-triggered `apply-web-platform-infra.yml` run on the merge SHA applies the exploration (already in the `-target=` allowlist, :655-656 — no workflow edit). Read the apply log: `logtail_exploration.inngest_luks_key_probe_fail` updated in place.
3. Post-apply close, gated on apply success (CTO D3 ruling): once the `apply-web-platform-infra.yml` run on the merge SHA concludes `success`, `gh issue close 11527 -c "<apply run + Phase-2 numbers>"`. If the apply fails, leave #11527 OPEN and comment the failed run URL — an unconditional close reproduces the `Closes` failure mode the `Ref` keyword exists to avoid. `scheduled-terraform-drift.yml`'s `terraform plan -detailed-exitcode` over this root is the continuous backstop; it does not gate closure.
4. Optional same-day sanity: re-run control C once post-apply.

## Files to Edit

- `apps/web-platform/infra/betterstack-logs-alerts.tf` — `local.inngest_luks_key_probe_fail_sql` restructured to the emitter-OR; comment block extended (emitter-identity sentence, residual edges, `LIVE-PROBED` entry).
- `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` — `FAIL_CANON` rewrite, derived needles (`MUT_TAG`/`MUT_STAGE`/`MUT_SHIPPER`), +6 presence rows, +7 `mutate_red` rows, ~2 retargeted needles, cardinality pin, floors, header bullet.
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` — standing-alarms row gains the dual-channel note.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `inngest -> betterstack` edge sentence notes the key-probe alert reads both emitters since #11527.

## Files to Create

- None. (`knowledge-base/project/specs/<branch>/tasks.md` and `decision-challenges.md` are pipeline artifacts, not plan deliverables.)

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain none of the four planned file paths (checked 2026-10-30). #11388, which overlapped this file family in the sibling plans, is `CLOSED`. Sibling #11528 (drift-guard coverage gaps on `inngest_luks_wrong_volume`) touches the same guard family but is explicitly out of scope — it enumerates wrong-volume gaps; whatever conjuncts this change adds to the key-probe guard are this issue's own scope.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the blast radius is a false `soleur-inngest-luks-key-probe-fail-prd` page to the ops channel (or, worse direction, a leg that never matches leaving the alert blind to a real key-loss *if* a second, independent fault also occurred). No user-facing artifact changes.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure — a read predicate on an existing internal alert; no new credential, no user data surface.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** consistent with the issue's own `User-Impact: aggregate pattern — a forged marker-quoting row could page the wrong-volume sibling class` and both sibling plans on the same alert family — no single user's artifact can be harmed by this diff alone; the credible harm is compounding (a blind or forged-paged alert eroding alarm trust on the store that holds all tenants' scheduler state), which is a pattern harm.

## Observability

```yaml
liveness_signal:
  what: "Better Stack Logs alert soleur-inngest-luks-key-probe-fail-prd evaluates the emitter-OR predicate; the probe emits via journald AND phone-home per run (dual-emit, unconditional)"
  cadence: "alert evaluation every 300s over a 900s window; probe emission first-tick then daily while ok / hourly while not ok"
  alert_target: "Better Stack team email (free tier) / betteruptime_policy.uptime escalation (paid tier)"
  configured_in: "apps/web-platform/infra/betterstack-logs-alerts.tf (logtail_exploration_alert.inngest_luks_key_probe_fail)"

error_reporting:
  destination: "Better Stack incident → email + push channels declared on the alert resource"
  fail_loud: "count(*) > 0 pages; probe silence is owned by the deferred dead-man (D12 / #11266 prerequisite), and during a Vector outage the dead-probe heartbeat already pages"

failure_modes:
  - mode: "a marker-quoting row under a foreign emitter reaches the count (the #8846 defect class)"
    detection: "this change — the emitter OR (leg-A SYSLOG_IDENTIFIER equality OR leg-B shipper+stage envelope equality); drift guard presence + mutation rows pin each conjunct with derived needles"
    alert_route: "guard drift → infra-validation.yml CI failure; a live false page → incident email"
  - mode: "a phone-home row carrying shipper+stage identity with detail absent (schema drop / degraded emit)"
    detection: "the detail = '' disjunct inside leg B counts it (deliberate fail-loud); the jq-failure payload carrying no shipper is silently uncounted (recorded edge)"
    alert_route: "incident email — noisy-but-correct, recorded as a residual edge"
  - mode: "applied SQL diverges from declared (apply skipped, partial, or overwritten)"
    detection: "scheduled-terraform-drift.yml terraform plan -detailed-exitcode; the logs-alert arm of the live reconcile"
    alert_route: "drift issue filing + twice-daily reconcile report"

logs:
  where: "Better Stack Logs source soleur-inngest-vector-prd (id 2457081) via journald → Vector under SYSLOG_IDENTIFIER=inngest-cutover-flip, or curl-direct phone-home (shipper=cloud-init-phone-home, stage=luks-key-probe)"
  retention: "hot window ~40min + s3Cluster archive (~90 days per sibling probe comments)"

discoverability_test:
  command: grep -c "JSONExtractString(raw, 'stage') = 'luks-key-probe'" apps/web-platform/infra/betterstack-logs-alerts.tf
  expected_output: "1"
```

## Encryption Posture

```yaml
at_rest:
  - store: "Better Stack Logs warehouse table for source 2457081 (pre-existing; this plan adds no store)"
    mechanism: "provider-managed: Better Stack Telemetry managed ClickHouse (remote() + s3Cluster archive) — unchanged by this diff"
    evidence: "scripts/betterstack-query.sh header (the warehouse read path); no repo-owned disk holds these rows"
    defends_against: "not a store this diff creates — the predicate narrows WHICH existing rows count toward an alert"
    does_not_defend: "a leaked BETTERSTACK_QUERY_* pair still reads the same rows; unchanged, pre-existing"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: a query-predicate edit carries no new at-rest invariant to verify"
in_transit:
  - connection: "CI/operator shell -> Better Stack ClickHouse HTTP SQL API (the live-probe read path)"
    enforced_at: "scripts/betterstack-query.sh — https://$BETTERSTACK_QUERY_HOST with curl --fail-with-body"
    tls: "https; system curl default TLS negotiation"
    cert_verification: "on"
    does_not_defend: "credential theft still reads the warehouse (pre-existing, unchanged)"
    disclosed_as: "not-publicly-claimed"
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/betterstack-logs-alerts.tf` — `local.inngest_luks_key_probe_fail_sql` only: an emitter-OR restructure + comment. No new resources, providers, variables, or sensitive inputs. Live-probe read credentials are the existing `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` Doppler secrets (`soleur/prd_terraform`), read-only.

### Apply path

Merge-triggered push apply on `apply-web-platform-infra.yml` (`on.push.paths` covers `apps/web-platform/infra/**`; both resources already sit in the main `-target=` allowlist, :655-656). Expected effect: in-place update of `logtail_exploration.inngest_luks_key_probe_fail`; the alert resource re-plans unchanged (`exploration_id` reference, not content). Blast radius: Better Stack configuration only — zero host impact, zero downtime. `apply-web-platform-infra.yml` is the only applier for this root (non-`sentry/`); `scheduled-terraform-drift.yml` runs `plan -detailed-exitcode` read-only.

### Host fan-out

Not applicable — neither changed resource is a `terraform_data` SSH provisioner; no host is contacted.

### Distinctness / drift safeguards

Single `prd` root; `dev` shares no state. Post-apply convergence re-verified by `scheduled-terraform-drift.yml`'s `terraform plan -detailed-exitcode` and the twice-daily `logs-alert` reconciler.

### Vendor-tier reality check

No new Better Stack resources — the free-tier limits that gate `betteruptime_policy` and the query_period ceiling measured in the #11427 422 saga are untouched (the alert's existing `check_period 300` / `query_period 900` pair is unchanged).

## Architecture Decision (ADR/C4)

### ADR

None required — this plan APPLIES the already-ruled convention: the ADR-218 amendment "2026-10-29 (#11526): the dual-channel predicate convention" names #11527 as the consumer and rules this fork (marker-override arm: the position-1 anchor reads both channels; the emitter pin is an OR over emitter identity). Cited, not re-ruled; no new decision, reversal, or extension is made here.

### C4 views

Container view — `model.c4`'s `inngest -> betterstack` edge (~:792) already names the phone-home channel, the key-probe marker's dual emit, and the wrong-volume alert's dual-channel read; it gains one clause noting the key-probe alert's predicate reads BOTH emitters since #11527. Enumeration checked against all three `.c4` files: no new external actor (the probe is host-internal), no new external system (Better Stack Logs, source 2457081, already modeled), no new container/data-store, and the only access-relationship gap is the alert-consumer clause this edit closes. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` after the edit.

### Sequencing

The C4 clause ships in this PR (the consumer relationship is true the moment the predicate lands); no `adopting → accepted` soak applies.

## Guard Contract

### Guard 1 — emitter-OR on the key-probe alert predicate

**Property.** Every row counted by the alert is one of the probe's own rows on EITHER delivery channel — a journald row under `SYSLOG_IDENTIFIER='inngest-cutover-flip'` whose message begins with the marker and carries `token=fail_`, OR a phone-home envelope under `shipper='cloud-init-phone-home'` at `stage='luks-key-probe'` whose `detail` carries `token=fail_` or is absent — and no marker-quoting row under any other emitter can satisfy it.

**Assembly.** The WHERE clause of `local.inngest_luks_key_probe_fail_sql` in `apps/web-platform/infra/betterstack-logs-alerts.tf` — the single chokepoint: the exploration's `sql_query` is `replace(trimspace(local…))`, so every counted row flows through this one predicate, and the guard's extracted `FAIL_SQL` reads exactly that local. Guard side: `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh`, invoked solely by `.github/workflows/infra-validation.yml`. The literals' authorities are outside the pair: `LOG_TAG` at `inngest-cutover-flip.sh:102` (leg A), the bounded first arg of the `inngest-boot-phone-home.sh` call at `:953` (leg-B `stage`), and the `shipper:"…"` payload builder in `cloud-init-inngest.yml` (leg-B `shipper`) — the guard derives all three needles from those sites.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Drop the leg-A `SYSLOG_IDENTIFIER='inngest-cutover-flip'` conjunct | RED — emitter presence row fails (new `mutate_red` row) |
| 2 | Flip the leg-A literal to `'doppler'` | RED — derived-needle presence row fails (new `mutate_red` row) |
| 3 | Drop the leg-B `shipper` or `stage` conjunct | RED — leg-B presence rows fail (two new `mutate_red` rows) |
| 4 | Flip the `stage` literal to a foreign stage | RED — derived-needle presence row fails (new `mutate_red` row) |
| 5 | Delete the whole `OR (…)` emitter arm — predicate collapses to leg-A only, the #11527 regression | RED — OR-structure presence row fails (new `mutate_red` row) |
| 6 | Neutralize the `detail = '' OR` disjunct — the fail-loud arm silently dropped | RED — disjunct presence row fails (new `mutate_red` row) |
| 7 | Guard-side: raise `PRESENCE_ROWS` by one while assertions stay | FATAL — assertion floor: `_ran` drops below the raised floor (dispatch/vacuity row, existing `mutate_floor_red`) |
| 8 | Reorder the two leg-A conjuncts within the leg | must-PASS — the contract pins each conjunct's presence and the OR structure, not ordinal position inside a leg |

**Anchor.** The three identity literals are cross-pinned outside this diff: `LOG_TAG` drives the journald emit the existing guard already pins (`"${MARKER} ${row}"` presence row + the FLIP-side marker-rename mutation), the `stage` arg is pinned by the existing `"luks-key-probe" "$row" ${MARKER}` presence row plus the new exactly-1 cardinality check, and `shipper` is the envelope builder's own literal — a coherent weakening must move the emit sites AND this pair, and a rename that misses the `.tf` reddens on the derived needles.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Enumerate the key-probe's delivery paths live (48h hot∪archive window via `scripts/betterstack-query.sh`)." [issue #11527] | Phase 2 (controls A–E; A is the enumeration) | mapped |
| 2 | "Pin the row set so marker-quoting rows under foreign emitters can never count, without dropping the phone-home path." [issue #11527] | Phase 1 item 1 / Files-to-Edit `betterstack-logs-alerts.tf` | mapped |
| 3 | "Extend `inngest-luks-key-probe-alert.test.sh` with presence + mutation coverage for the new conjunct(s)." [issue #11527] | Phase 1 item 2 / Files-to-Edit `inngest-luks-key-probe-alert.test.sh` | mapped |
| 4 | "Record a dated LIVE-PROBED entry in the `.tf` comment per the #8874 convention." [issue #11527] | Phase 1 item 1 (comment) + Phase 2 (numbers) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `betterstack-logs-alerts.tf` emitter OR + `LIVE-PROBED` comment | asks 2, 4 | asked |
| `inngest-luks-key-probe-alert.test.sh` rows + floors | ask 3 | asked |
| Phase 2 enumeration + live-probe | ask 1 | asked |
| `betterstack-log-query.md` standing-alarms row | — | inferred — justification: the runbook is the documented readback authority for this alert; a predicate shape it does not describe rots the operator's query recipe (identical justification to the sibling plan) |
| `model.c4` edge clause | — | inferred — justification: the C4 completeness mandate — the edge names the wrong-volume alert's dual-channel read but not this alert's; an edge describing only the sibling would mislead about which alerts read the phone-home channel |
| Phase 3 apply/close | — | inferred — justification: the issue's own convention (`Ref` + post-apply close) — the apply path IS the remediation ("ARMING HAPPENS ON THE APPLY, NOT AT MERGE") |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform/infra`, `apps/web-platform/test`, `knowledge-base` (one app root + docs)
- Planned files: 4 | Estimated changed lines: ~130
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `local.inngest_luks_key_probe_fail_sql` in `apps/web-platform/infra/betterstack-logs-alerts.tf` is the emitter-OR form: shared `dt BETWEEN` filter + position-1 marker anchor; leg A `JSONExtractString(raw,'SYSLOG_IDENTIFIER') = 'inngest-cutover-flip'` AND `token=fail_` on `message`; OR leg B `JSONExtractString(raw,'shipper') = 'cloud-init-phone-home'` AND `JSONExtractString(raw,'stage') = 'luks-key-probe'` AND (`detail = ''` OR `token=fail_` on `detail`) — pending the D2 ruling on the `detail=''` arm; no `LIKE`, no `GROUP BY`, no `indeterminate`, no `raw` prefilter.
- [ ] The local's comment block carries the emitter-identity sentence, the recorded residual edges (jq-failure payload uncounted; `detail=''` arm semantics; self-attested `dt`; `value` ≤ 2 inflation under `higher_than 0`), and a dated `LIVE-PROBED` entry with the Phase-2 measurements.
- [ ] `bash apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` exits 0 reporting `73 passed, 0 failed` (floors `73` / `36` under `MUT_SKIP`); the seven new `mutate_red` rows each go red on their mutation and the retargeted needles still land.
- [ ] Phase-2 executed and recorded: A enumerates every emitter carrying marker-anchored rows (GROUP BY `SYSLOG_IDENTIFIER`/`shipper`/`stage`), B enumerates phone-home stages, C `= 0`, D's coverage delta is 0 or enumerates excluded foreign rows, E returns `1/0/1/0/1/0/0` under the shipped form.
- [ ] `betterstack-log-query.md`'s standing-alarms row names the dual-channel pin; `model.c4`'s `inngest -> betterstack` edge notes this alert reads both emitters and the C4 tests pass.
- [ ] Post-merge, the `apply-web-platform-infra.yml` run on the merge SHA applies `logtail_exploration.inngest_luks_key_probe_fail` successfully (apply log shows the exploration updated in place).
- [ ] After the apply lands, #11527 is closed with a comment naming the apply run and the Phase-2 numbers; PR body carried `Ref #11527` (never `Closes` — the live change lands post-merge, on the apply).
- [ ] `decision-challenges.md` carries the D1–D3 rows (obtained rulings or `pending - assumed:`), and the two Operator-reserved holds stand verbatim under `## Operator Holds`.

## Operator Holds

<!-- markdownlint-disable MD034 -->
Delegation: https://github.com/jikig-ai/soleur/issues/10390#issuecomment-6361717901
Envelope: <committed-runbook-path — fill in when the plan phase authors the first Production Envelope; until a readable envelope is committed every hold stands, which is correct here>

- Hold: Operator-reserved: live op=backup verification dispatch — `gh workflow run cutover-inngest.yml -f op=backup`. Not covered by any Scope item: the Scope names only scheduled-terraform-drift.yml, so this file is a scope-mismatch. Non-delegable regardless: the op performs a Hetzner `create_image` snapshot with a READ/WRITE token (.github/workflows/cutover-inngest.yml:8, :100-104; scripts/cutover-inngest.sh:1902-1913) — a write on a third-party system on the Excluded list and explicitly excluded by the operator's recorded words ("any Hetzner/Doppler/Supabase write") — and it runs under the reviewer-gated `inngest-cutover` environment (:104), an approval only a person can give; no Gate kind can discharge it.
- Hold: Operator-reserved: DOPPLER_TOKEN_INFRA_PRIVILEGED seed check — the environment-secret presence probe for the Tier-B token on `inngest-cutover` (runbook O3, infra-credential-tiers-8209.md:322; census row :163). Non-delegable: no delegable command reaches it (`gh secret`/`doppler`/secret-store access are outside the command grammar and on the denylist/never-run list), it touches a third-party secret store, and if the seed is absent the remedy (`doppler configs tokens create` + `gh secret set --env <e>`) is a credential write on the Excluded list.
<!-- markdownlint-enable MD034 -->

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change on an internal alert predicate. The technical forks (the emitter-OR shape; the `detail=''` fail-loud arm) route to the CTO via `decision-challenges.md` rows D1/D2 rather than a domain-leader Task: this run has no spawn capability, so D1 cites the already-recorded ADR-218 amendment ruling and D2 is recorded `pending - assumed:` for the parent pipeline to obtain. Product/UX gate: mechanical UI-surface scan of Files to Edit/Create — `.tf`, `.test.sh`, `.md`, `.c4` only, no UI-surface terms — not flagged; tier NONE.

## Test Scenarios

- **Guard RED rows (unit-level, drift guard):** Given a mutated `.tf` copy, when (a) the leg-A emitter conjunct is dropped or flipped to `'doppler'`, (b) the leg-B `shipper`/`stage` conjunct is dropped or the stage flipped, (c) the whole `OR (…)` arm is deleted, or (d) the `detail = '' OR` disjunct is neutralized, then `inngest-luks-key-probe-alert.test.sh` reports FAIL on the matching presence row.
- **Guard must-PASS row:** Given a `.tf` copy where leg A's two conjuncts are reordered within the leg, when the guard runs, then it still passes — the contract pins each conjunct's presence and the OR structure, not ordinal position.
- **Live-probe controls (integration):** Given `doppler run -p soleur -c prd_terraform` injects `BETTERSTACK_QUERY_*`, when controls A–E run against the ClickHouse hot∪archive table, then A enumerates emitters, B enumerates stages, C `0`, D's delta enumerates the excluded class, and E returns `1/0/1/0/1/0/0` — and all numbers land in the `.tf` comment.
- **Apply convergence (integration):** Given the PR merges, when `apply-web-platform-infra.yml` runs on the merge SHA, then the exploration applies cleanly and the subsequent drift `terraform plan` is empty for it.
- **Adjacent-guard stability (unit):** Given the comment rewrite, when `inngest-luks-wrong-volume-alert.test.sh` and `betterstack-alert-structure.test.sh` run, then both stay green.

## Context

- **Why leg B needs `shipper` AND `stage`, not either alone:** `shipper` names the emitter class (every phone-home POST carries it) and `stage` names the call site (`luks-key-probe` is positional `$1`); either alone admits other phone-home stages or other shippers' rows. The exactly-1 cardinality pin makes `luks-key-probe` a reserved token.
- **Why `detail` for leg-B field reads:** the envelope's `message` is `marker + ' stage=' + stage + ' ' + detail` — `detail` is the isolated `token=… rc=… at=…` row; `at=` literals (`died|key|mount|status|uuid|mem|shield|kdf`) are single-word and never carry `token=fail_`, so `detail`-anchored and `message`-anchored `token=fail_` checks are equivalent on every real row — `detail` is the tighter, conventional read.
- **Dual-emit is unconditional here** (unlike the sibling's vector-gated fallback): `luks_probe_finish` calls both the logger and the phone-home on every run — leg-B rows are a parallel copy, so a failing verdict can read `value = 2`; harmless under `higher_than 0` (recorded per the amendment's dedup caveat).
- **Pre-existing CI red:** `deploy-script-tests` is red on `main` from an unrelated `vinngest` tag/pin drift (`cloud-init-inngest-bootstrap.test.sh` AC6) owned by another in-flight worktree — distinguish pre-existing reds from this diff's at verification time.
- **AI-generated files:** none — every edit is hand-shaped against pinned literals and the existing `mutate_red`/`edit()` recipes.

## References

- Issue: #11527 (this plan's ask, verbatim in Scope Check); defect class: #8846 / PR #8873; sibling fixes: #8874 (PR #11519, merged 2026-10-29) and #11526 (PR #11559, squash f9f4f2b2) — the dual-channel convention this plan applies; out of scope: #11528, #11266.
- Runbooks: `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (standing-alarms row, edited), `inngest-luks-cutover-6894.md` (row contract :604, unchanged).
- ADR-218 (alert family governance — the 2026-10-29 dual-channel amendment rules this fork); ADR-282 (the LUKS protection set this alert watches); ADR-142 (the LUKS cutover).
- Learnings: `2026-10-29-call-form-anchored-needles-and-the-empty-disjunct-fail-loud.md`, `2026-10-29-derive-the-needle-and-verify-the-fallbacks-actual-args.md`, `2026-09-27-a-presence-check-after-source-is-satisfied-by-the-environment.md`, `2026-10-09-i-carried-a-measured-dt-claim-from-one-emitter-onto-another.md`.
- Sibling plans: `knowledge-base/project/plans/archive/20261029-224921-2026-10-29-fix-inngest-luks-wrong-volume-vector-down-plan.md`, `20261029-155548-2026-10-29-fix-inngest-luks-wrong-volume-emitter-plan.md`; original probe plan `20261027-112122-2026-10-26-feat-inngest-luks-key-continuity-probe-plan.md` (D4/D12 rulings).
