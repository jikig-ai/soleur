---
title: "The LUKS wrong-volume alert is blind to the probe's vector-down phone-home fallback"
type: fix
date: 2026-10-29
slug: fix-inngest-luks-wrong-volume-vector-down
branch: feat-one-shot-11526-vector-down-fallback
issue: 11526
priority: p2
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# The LUKS wrong-volume alert is blind to the probe's vector-down phone-home fallback

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No spec.md exists for this branch; the pipeline runs plan before spec here.)

**Does merging this alone mutate production?** Yes — `betterstack-logs-alerts.tf` is under `apps/web-platform/infra/**`, so the merge fires the push-triggered apply, which updates the live exploration's stored SQL in Better Stack. The PR body's first line must state this (the merge click is the authorization act).

## Enhancement Summary

**Deepened on:** 2026-10-29
**Agents used:** none — this deepen ran inside a pipeline subagent with no Task/Agent tool, so the §4 halt gates, the precedent-diff, and the verify-the-negative pass were executed inline by the planning agent (mirroring the sibling #8874 deepen).

### Gate verdicts (all evaluated inline)

- §4.4 Precedent-diff: pass — the OR-arm shape mirrors `ghcr_hostsfile_deny_lost_sql:1368` in the same file; the dual-channel convention is the precedent this change establishes for #11527.
- §4.45 verify-the-negative: every negative claim re-verified by reading the emit site and envelope constructor (no `SYSLOG_IDENTIFIER`, `marker` default, `detail` field set, jq-failure payload shape, parity-suite coverage of the field set).
- §4.5 network-outage: evaluated, skipped — the only trigger matches are the `cloud-init-inngest.yml:502` line reference and the "no `terraform_data` SSH provisioner" negative statement; no SSH/network symptom is addressed and the changed resources carry no provisioner/`connection` blocks.
- §4.55 downtime: skipped — in-place Better Stack exploration update; no host, volume, DB, or deploy-surface touched.
- §4.6 User-Brand Impact: pass (section present, threshold `aggregate pattern`, concrete artifact/vector).
- §4.7 Observability: pass (5 fields populated; `discoverability_test.command` is `grep -c`, an allowlisted verb under the 15s cap, `expected_output` the literal `1`).
- §4.8 PAT-shaped variable: pass (grep clean — `BETTERSTACK_QUERY_*` are ClickHouse read credentials, not GitHub PAT shapes).
- §4.9 UI-wireframe: skipped (no UI-surface files).
- §4.10 Encryption Posture: pass (triggered by `.tf` edit; all fields populated, `does_not_defend` non-empty, no exception needed).
- §4.11 Guard Contract: pass — `scripts/lint-guard-contract.py` green (1 guard entry); assembly is structural (the WHERE clause chokepoint + the guard's extracted `LOCAL_SQL` + the emit-site `stage` authority), not a member list.
- §4.12 Scope Check: pass (exactly one unfenced section; all asks mapped; inferred items carry justifications; split assessment derived from the file lists).
- §4.13 Task Design: skipped (modifies an existing alert; no new workflow/timer/daemon surface).

### Key improvements from the deepen pass

1. **Guard-needle disambiguation made explicit** — the leg-B `detail` devid check makes the bare `data_mount_devid=…') = 0` needle match twice; Phase 1 prescribes retargeting the two existing devid mutation needles to the `message`-extracted form plus a dedicated leg-B devid mutation, so the guard can never green over a dropped leg.
2. **`stage` needle derived, not re-pinned** — mirrors the `MUT_EMITTER` convention: the guard greps `inngest-server-probe-vector-down` from the emit site, so a coordinated rename that misses the `.tf` goes red instead of quiet.
3. **Control E added beyond the issue's A–D** — the leg-B logic is verified on synthetic `raw` literals (wrong devid `1` / live alias `0` / detail-absent `1`) without POSTing to the real source, since `stage='inngest-server-probe-vector-down'` rows are expected ~0 while Vector is healthy.
4. **Self-attested `dt` edge recorded** — the phone-home envelope POSTs its own `dt`; whether the warehouse honors it is unmeasured (#9784 learning), recorded as a residual edge rather than silently assumed.

### New considerations discovered

- The jq-failure fallback payload carries neither `detail` nor `shipper` (`cloud-init-inngest.yml:563`) → it never satisfies leg B's `shipper` conjunct and is silently uncounted. The fail-loud property holds only for rows carrying the `shipper`+`stage` identity with `detail` absent (the schema-drop class). Recorded as a residual edge, per the CTO's T1 dissent.
- `inngest-server-probe-heartbeat.test.sh:126-142` pins `#8516`/`treat_as_zero`/`inngest_server_probe` tokens in this alert's comment region — the comment rewrite is constrained to keep them; added as an AC.
- During a Vector outage the dead-probe heartbeat already pages — leg B does not replace that signal; it keeps the *wrong-volume content check* live under it. Noted in Context.

## Overview

The Better Stack Logs alert `logtail_exploration_alert.inngest_luks_wrong_volume` pages when the dedicated Inngest host's hourly probe row reports `/mnt/data` backed by a by-id alias that is not the LUKS-encrypted volume's — the tripwire for Redis writes landing unencrypted after the cutover. When the Vector shipper is down, the probe emits the same field row through a second channel: a curl-direct phone-home POST (`inngest-boot-phone-home.sh inngest-server-probe-vector-down "<fields>"`, `apps/web-platform/infra/inngest-bootstrap.sh:1316-1317`) whose envelope carries `shipper=cloud-init-phone-home`, `stage=inngest-server-probe-vector-down`, and the field row in `detail` — landing in the SAME Logs source 2457081. The alert's predicate anchors on journald-only signals (the `SYSLOG_IDENTIFIER='inngest-server-probe'` conjunct merged under #8874/PR #11519, plus a start-of-message `SOLEUR_INNGEST_SERVER_PROBE` marker the fallback envelope never carries), so during a Vector outage — exactly when degraded-host states make a wrong-volume mount most plausible — the alert reads zero rows and `treat_as_zero` reports health. #11526 asks for a deliberate accept/reject decision and, on accept, a dual-path predicate that admits the fallback on its own envelope fields. The settled shape is the shared pattern sibling issue #11527 applies to `inngest_luks_key_probe_fail` and #11528 pins in the guard family.

## Research Insights

**Premise Validation (Phase 0.6).** Every cited reference re-verified 2026-10-29: issue #11526 `OPEN`, labeled `meta/machinery`; #8874 `CLOSED`; PR #11519 `MERGED` 2026-10-29T18:44Z carrying the `SYSLOG_IDENTIFIER='inngest-server-probe'` conjunct (verified live in `betterstack-logs-alerts.tf:261`); sibling issues #11527 and #11528 both `OPEN` and out of scope. The emit site (`inngest-bootstrap.sh:1316-1317`), the marker default (`cloud-init-inngest.yml:502` — `marker` falls through to `SOLEUR_INNGEST_BOOT_STAGE` when only two args pass), and the POST target (`cloud-init-inngest.yml:562` — `s2457081`, the same source the exploration queries via `local.vector_prd_source_id = "2457081"`) all match the issue body verbatim. The proposed mechanism (an OR arm on the predicate) is a sibling-proven shape in this very file — `ghcr_hostsfile_deny_lost_sql` carries `OR (startsWith(raw, ...)` arms, and four other SQLs use `OR` conjuncts — not a rejected ADR alternative (ADR-218, the alert family's governing ADR, prescribes live-probing before writing predicates; nothing rules out dual-channel predicates). Collision pre-check: open PR #11559 names #11526 but is THIS branch's own auto-created WIP draft — not a foreign collision; the foreign `test-all.sh` process (pid 815035) belongs to the unrelated in-flight vinngest worktree the brief names.

**Property List (Phase 0.6b).** The asks restated as observable properties: (1) a vector-down phone-home row reporting a wrong `data_mount_devid` counts toward the alert — the fallback leg is a counted row, not a documented blind spot; (2) only the probe's own phone-home rows count on that leg — row identity is pinned by envelope-field equality (`shipper`, `stage`), never a message substring; (3) an unreadable fallback row (missing/renamed `detail`) fails LOUD the same way the journald leg's negated devid check does — an unreadable answer is not a clean one; (4) the change is proven against live warehouse data before it is applied, not just by reading the SQL; (5) the drift guard pins the new conjuncts' source — a revert or rename must redden it, not pass silently.

**Cut List (Phase 0.6b).** Nothing cut — the issue names exactly two mechanism changes (anchor on `detail`/`stage` fields rather than `marker`; restructure the message anchor the fallback cannot satisfy) and both are load-bearing for property (1). No existing mechanism covers property (1): the fallback rows were invisible to the alert by construction before this change (verified: the message anchor at position 1 can never match `SOLEUR_INNGEST_BOOT_STAGE stage=…`).

**Relevant file paths.**

- `apps/web-platform/infra/betterstack-logs-alerts.tf:257-266` — `inngest_luks_wrong_volume_sql` (the predicate being restructured); `:213-268` the comment block whose "three residual edges" third bullet records this exact blind edge (written by PR #11519 knowing this issue would own the fix); `:271-342` the `logtail_exploration` + `logtail_exploration_alert` resources. File header ("TO ADD ANOTHER LOGS ALERT") prescribes live-probing new predicates via `betterstack-query.sh` with a positive control.
- `apps/web-platform/infra/inngest-bootstrap.sh:1316-1317` — the fallback emit: fires `inngest-boot-phone-home.sh inngest-server-probe-vector-down "<full field row>"` only when `vector_active != "active"` AND the emitter is executable — zero steady-state row cost, the row exists exactly in the degraded window.
- `apps/web-platform/infra/cloud-init-inngest.yml:497-575` — the phone-home emitter: envelope `{message, marker, stage, detail, host, dt, shipper:"cloud-init-phone-home"}` POSTed to `https://s2457081.eu-fsn-3.betterstackdata.com/`; `marker` defaults to `SOLEUR_INNGEST_BOOT_STAGE` (the two-arg call never overrides it); the jq-failure fallback payload carries NO `detail` key.
- `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` — the drift guard: 15 presence + 14 `mutate_red` rows, `_floor=29` / `MUT_SKIP` floor 15, instrument self-test + pristine-tree control. Registered in `.github/workflows/infra-validation.yml`.
- `apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh:126-142` — a SECOND guard pinning this alert's comment region: requires `#8516` + `treat_as_zero` + `inngest_server_probe` tokens in the contiguous comment block or resource body, and `on_missing_data = "treat_as_zero"` — any comment rewrite must keep all three tokens and the attribute.
- `apps/web-platform/infra/inngest.test.sh:2253-2264` — the #7695 parity battery: `PROBE_PAYLOAD_PHONE` (the fallback emit) and `PROBE_PAYLOAD_LOGGER` (the journald emit) are asserted BYTE-IDENTICAL and carrying every presence-list field — so `host_role`/`data_mount_devid` are already pinned INTO the fallback payload; a future probe_schema prune (#10290) cannot drop them silently.
- `scripts/lib/inngest-probe-row.sh` — canonical journald-row def (`INNGEST_PROBE_EMITTER`/`INNGEST_PROBE_MARKER`/`inngest_probe_row`); the guard derives needles from it (`MUT_EMITTER`). Leg-B's `stage` literal has no canonical lib — its authority is the emit-site call literal in `inngest-bootstrap.sh`, pinned by `inngest.test.sh:2255`.
- `scripts/betterstack-query.sh` — live-probe transport (raw-SQL mode; hot `remote()` UNION `s3Cluster` archive; `doppler run -p soleur -c prd_terraform`).
- `.github/workflows/apply-web-platform-infra.yml:653-654` — both resources already in the `-target=` allowlist; merging IS the apply path.
- `.github/workflows/scheduled-terraform-drift.yml` — standing post-apply live-vs-declared readback.
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md:46-59` — the standing-alarms row documenting this alert.
- `knowledge-base/engineering/architecture/decisions/ADR-218-*.md` — governing ADR for the alert family (already carries dated amendments for this alert's #6894 birth and its paused-arming reconciler).
- `knowledge-base/engineering/architecture/diagrams/model.c4` — the `inngest -> betterstack` edge (~line 792) describes the Vector journald channel only; the curl-direct phone-home channel into source 2457081 is named on the zot/registry and web-1 edges but not on the inngest edge.

**Institutional learnings applied.**

- `2026-10-29-derive-the-needle-and-verify-the-fallbacks-actual-args.md` (PR #11519, this issue's direct parent): verify the fallback's actual emitted arguments before accepting a coverage claim — done: two args, `marker` defaults to `SOLEUR_INNGEST_BOOT_STAGE`, `message` begins `SOLEUR_INNGEST_BOOT_STAGE stage=…` and can never satisfy the position-1 anchor.
- `2026-10-09-i-carried-a-measured-dt-claim-from-one-emitter-onto-another.md` (#9784): a `dt`-is-ingest-time claim is per-emitter; the phone-home envelope POSTs its own `dt` field, so whether the warehouse honors the self-attested value is UNMEASURED — recorded as a residual edge, not assumed.
- `2026-09-27-a-presence-check-after-source-is-satisfied-by-the-environment.md` (#8846): a log row's identity is its emitter, never its message content — leg-B pins `shipper`+`stage` envelope equality for the same reason.
- `2026-10-15-a-new-nonpaging-marker-moved-a-pin-in-a-suite-the-affected-gate-never-selects.md` (#10356): suites outside `--affected` selection pin adjacent content — checked: `inngest-server-probe-heartbeat.test.sh` pins this alert's comment region (tokens kept) and `terraform-target-parity.test.ts` pins the alias derivation + exploration carries the local (unchanged).
- `2026-07-03-pass-is-not-proof-three-vacuous-green-traps-in-infra-verification.md`: the live-probe controls include a positive control that MUST equal the population, never just "query ran".
- `knowledge-base/engineering/operations/post-mortems/2026-09-25-inngest-watchdog-false-p1-*.md`: the quoting-row class that motivated emitter identity on leg A.
- `scripts/followthroughs/inngest-tls-soak-10136.sh` + `scripts/lint-betterstack-emitter-read.sh:147`: the established phone-home row identity contract — `.marker == SOLEUR_INNGEST_BOOT_STAGE`, `.stage == <stage>`, `.shipper == cloud-init-phone-home` equality on the DECODED envelope.

**External research.** Skipped — the predicate shape is pinned by the issue text, the sibling SQL precedent in the same file, and the canonical envelope contract; nothing external to decide.

## Problem Statement / Motivation

`local.inngest_luks_wrong_volume_sql` counts a row as evidence when (a) it was emitted under `SYSLOG_IDENTIFIER='inngest-server-probe'`, (b) its message *begins with* `SOLEUR_INNGEST_SERVER_PROBE`, (c) the message contains 'host_role=dedicated ', and (d) the message does NOT contain 'data_mount_devid=<the live encrypted alias> '. The probe has a second delivery channel the predicate cannot see: when `vector_active != "active"` — Vector dead, journald→Vector→Better Stack dark — the probe POSTs the identical field row direct to the Better Stack ingest as `{marker:"SOLEUR_INNGEST_BOOT_STAGE", stage:"inngest-server-probe-vector-down", detail:"<field row>", shipper:"cloud-init-phone-home", …}` (`cloud-init-inngest.yml:562`). That row carries no `SYSLOG_IDENTIFIER` (it is not a journald row) and its `message` begins `SOLEUR_INNGEST_BOOT_STAGE`, so it satisfies zero of the identity conjuncts: during a Vector outage the alert evaluates an empty row set, and `on_missing_data = "treat_as_zero"` reads the emptiness as "zero wrong-volume rows" — healthy.

This is a pre-existing blind edge, not a regression from #8874 (CTO ruling on PR #11519, verified by call-site argc). The case for admitting the leg: the fallback exists precisely for the degraded-host states — rebuilds, restores, partial boots — where a wrong-volume mount is most plausible, and the field row the alert needs is already shipped. The case against: during a Vector outage the dead-probe heartbeat (`betteruptime_heartbeat.inngest_server_probe`) already pages on its own, so wrong-volume is never silently missed so much as masked inside the louder outage signal; and a second predicate arm doubles the surface the guard must pin. The deliberate accept/reject decision is recorded as a technical ruling (`decision-challenges.md` row T1); the assumed ruling is ACCEPT for the reasons above.

## Proposed Solution

Restructure the predicate into a two-channel OR: leg A (journald, unchanged conjuncts) OR leg B (the phone-home envelope, pinned by `shipper`+`stage` equality with the field checks evaluated on `detail`):

```sql
  inngest_luks_wrong_volume_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND (
        JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'inngest-server-probe'
        AND position(JSONExtractString(raw, 'message'), 'SOLEUR_INNGEST_SERVER_PROBE') = 1
        AND position(JSONExtractString(raw, 'message'), 'host_role=dedicated ') > 0
        AND position(JSONExtractString(raw, 'message'), 'data_mount_devid=${local.inngest_luks_wrong_volume_alias} ') = 0
        OR (
          JSONExtractString(raw, 'shipper') = 'cloud-init-phone-home'
          AND JSONExtractString(raw, 'stage') = 'inngest-server-probe-vector-down'
          AND position(JSONExtractString(raw, 'detail'), 'host_role=dedicated ') > 0
          AND position(JSONExtractString(raw, 'detail'), 'data_mount_devid=${local.inngest_luks_wrong_volume_alias} ') = 0
        )
      )
    GROUP BY time
  SQL
```

`AND` binds tighter than `OR`, so the parenthesized group parses as `(leg-A conjuncts) OR (leg-B group)` and the `time BETWEEN` filter wraps both — the OR-inside-group form keeps all four leg-A `AND position(...)` lines byte-identical (only the emitter line drops its leading `AND` by becoming the group's first line), and mirrors this file's own `OR (` arms (`ghcr_hostsfile_deny_lost_sql:1368`).

Design choices, each load-bearing:

- **`shipper`+`stage` envelope equality, not `marker`** — nothing emits `marker='SOLEUR_INNGEST_SERVER_PROBE'` (0 rows/48h verified for the issue; `doppler` rows carry no marker field); the fallback's identity fields are `shipper` (the emitter class) and `stage` (the call-site literal), the same triple the `inngest-tls-soak-10136.sh` phone-home consumer selects on.
- **Field checks on `detail`, not `message`** — per the issue's own prescription; `detail` is the isolated field row, while `message` carries the `SOLEUR_INNGEST_BOOT_STAGE stage=…` prefix. Both check names ('host_role=dedicated ', 'data_mount_devid=<alias> ') keep key-anchored, trailing-space form — the emit order guarantees a following field.
- **Negated devid on leg B too** — a phone-home row carrying the `shipper`+`stage` identity whose `detail` is absent yields `position('') = 0` and COUNTS as wrong-volume. Deliberate fail-loud for the schema-drop class, same philosophy as leg A: a malformed fallback row during a Vector outage pages rather than reading healthy. Recorded as a residual edge. (The jq-failure fallback payload is a different shape — it lacks `shipper` too, so it never reaches this check; see Technical Considerations.)
- **No dedup concern** — the fallback fires only when `vector_active != "active"`; the two legs cannot both fire for one probe run (the journald path is down by construction), and even a flap double-count only inflates `value` above the same >0 threshold.

The ruling-dependent arm: if the obtained CTO ruling is REJECT, this plan collapses to a comment-only change — the residual-edges bullet is amended to record the deliberate exclusion and its rationale, and Phases 1.1/2 drop away.

## Technical Considerations

- **Two failure directions, same as #8874.** A syntax error in the heredoc breaks the exploration query (visible as drift/absence, not silence); a wrong leg-B literal (`shipper`/`stage`) makes that arm permanently zero — which `treat_as_zero` reads as healthy in exactly the outage window leg B exists for. The drift guard's presence+mutation rows plus the pre-merge live-probe cover both directions.
- **The jq-failure payload edge.** `cloud-init-inngest.yml`'s payload fallback (`{"message":…,"marker":…,"stage":…,"host":…}` — no `detail`, no `shipper`) never satisfies leg B's `shipper='cloud-init-phone-home'` conjunct, so it is silently uncounted — not counted (CTO T1 dissent correction). The fail-loud property leg B keeps is the narrower schema-drop class: a row carrying the `shipper`+`stage` identity with `detail` absent/renamed still evaluates `position('') = 0` and counts as wrong-volume. The alternative (require `position(detail,'data_mount_devid=')>0`) would reintroduce the fail-quiet schema-drop class leg A's negation exists to kill. Documented in the comment; no predicate carve-out.
- **Self-attested `dt` on leg B is unmeasured.** The phone-home envelope POSTs its own `dt` field; whether the warehouse honors the sender's value over receive-time was never measured (#9784 learning). A severely skewed host clock could place a real wrong-volume row outside the alert's 5400 s window. Residual edge, recorded — the fix (evaluate `ingest_time`) is a bigger change and not part of this issue.
- **`stage` literal has no canonical lib.** Unlike `INNGEST_PROBE_EMITTER` (canonical in `inngest-probe-row.sh`), `inngest-server-probe-vector-down` is a call-site literal; its authority is `inngest-bootstrap.sh:1317` itself, pinned by `inngest.test.sh:2255`. The drift guard derives its stage needle by grepping that emit site — a coordinated rename that misses the .tf goes red, mirroring the `MUT_EMITTER` derivation convention (#8874).
- **`#10290` field-prune interaction.** The parity battery (`inngest.test.sh:2253-2264`) asserts the two emit payloads byte-identical AND every presence-list field present — a schema bump cannot drop `host_role`/`data_mount_devid` from the fallback without reddening that suite. No edit needed there.
- **Sibling-guard token discipline.** `inngest-server-probe-heartbeat.test.sh` requires `#8516`, `treat_as_zero`, `inngest_server_probe` in the alert's comment region and `on_missing_data = "treat_as_zero"` on the resource — the comment rewrite keeps the `#8516` block untouched.
- **No consumer census impact.** `lint-betterstack-emitter-read.sh` (#8875) censuses files invoking `betterstack-query.sh`; a `.tf` declaring SQL stays outside its population.
- **Pre-existing CI red.** `deploy-script-tests` is red on `main` from an unrelated `vinngest` tag/pin drift owned by another in-flight worktree (`cloud-init-inngest-bootstrap.test.sh` AC6) — verification distinguishes pre-existing reds from this diff's at gate time.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality (checked 2026-10-29) | Plan response |
|---|---|---|
| "the probe emits the full field row … via `inngest-boot-phone-home.sh inngest-server-probe-vector-down "<fields>"`" | Confirmed: `inngest-bootstrap.sh:1316-1317`, gated on `vector_active != "active"` + `[ -x ]`. | Leg-B anchors `stage='inngest-server-probe-vector-down'` + `shipper='cloud-init-phone-home'`. |
| "marker falls through to the `SOLEUR_INNGEST_BOOT_STAGE` default … no `SYSLOG_IDENTIFIER`" | Confirmed: `cloud-init-inngest.yml:502` default, envelope has no `SYSLOG_IDENTIFIER` key. | Leg-B never tests `marker`/`SYSLOG_IDENTIFIER`; identity is `shipper`+`stage`. |
| "nothing emits `marker='SOLEUR_INNGEST_SERVER_PROBE'`; verified 0 rows / 48h" | Consistent with the emitter's `marker` contract (default-only) and PR #11519's CTO ruling. | Do not anchor on marker — the issue's own prescription. |
| "a wrong-volume `data_mount_devid` would report zero rows and `treat_as_zero` reads it as healthy" | Confirmed: the current four conjuncts can never match the envelope shape. | Dual-path predicate; `treat_as_zero`/`on_missing_data` unchanged (sibling guard pins it). |

## Implementation Phases

### Phase 1 — Predicate + comments + guard + docs (one commit)

1. `apps/web-platform/infra/betterstack-logs-alerts.tf`: restructure `local.inngest_luks_wrong_volume_sql` to the dual-path shape above. Rewrite the local's "three residual edges" block: the vector-down bullet becomes a CLOSED note naming #11526 and the OR arm; append the new residual edges (identity-pinned detail-absent fail-loud; jq-failure payload silently uncounted per CTO T1 dissent; self-attested `dt` unmeasured per #9784; leg-B literals load-bearing with the stage needle derived by the guard). Extend the `LIVE-PROBED` record with the Phase-2 dated entry (counts filled in Phase 2). `terraform fmt -check` on the file.
2. `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh`:
   - Header "WHAT THIS FILE PROTECTS": add a bullet — the predicate admits the probe's phone-home fallback on its own envelope (`shipper`+`stage` equality, fields read from `detail`), so a Vector outage no longer blinds the alert (#11526).
   - Derive the stage needle: `MUT_STAGE="$(grep -oE 'inngest-server-probe-vector-down' "$REPO/apps/web-platform/infra/inngest-bootstrap.sh" | head -1)"` after the `MUT_EMITTER` derivation, FATAL if empty (mirrors the lib-derivation contract; the emit site is the literal's authority).
   - New presence rows (+5): leg-B shipper equality; leg-B stage equality (needle `${MUT_STAGE}`); `detail`-anchored 'host_role=dedicated '; `detail`-anchored negated devid (`position(JSONExtractString(raw, 'detail'), 'data_mount_devid=… ') = 0`); the OR-arm structure (the extracted `LOCAL_SQL` contains `OR (` between the legs and the closing `)` — pin the two-leg shape, not just the tokens).
   - Retarget three existing mutation needles: the two devid mutations' `old` strings gain the `JSONExtractString(raw, \x27message\x27)` prefix (the bare `data_mount_devid=${alias} \x27) = 0` now matches twice — leg A `message` AND leg B `detail` — so `assert s.count(old) == 1` would FATAL every run); the emitter-conjunct mutations retarget to the new un-ANDed first-line shape (the conjunct line drops its leading `AND` under the parenthesized group).
   - New `mutate_red` rows (+5): (a) leg-B `shipper` conjunct dropped; (b) leg-B `stage` conjunct dropped; (c) `stage` literal flipped to a foreign stage; (d) leg-B `detail` devid check flipped `= 0` → `> 0`; (e) the whole `OR (…)` arm deleted (legs collapse to journald-only).
   - Floors: `29 = 15 presence + 14 mutation` → `39 = 20 presence + 19 mutation`; `MUT_SKIP` floor `15` → `20`. Verify the arithmetic at implementation; deepen-plan re-verifies.
   - Run `bash apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` locally — expect `39 passed, 0 failed`.
3. `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`: extend the `inngest_luks_wrong_volume` standing-alarms row (~:46-59) with one sentence — the predicate admits the vector-down phone-home fallback (`stage=inngest-server-probe-vector-down`, fields in `detail`) so a Vector outage does not blind it; the readback recipe for fallback rows selects `.shipper == "cloud-init-phone-home"` + `.stage` equality (per `inngest-tls-soak-10136.sh`'s envelope contract).
4. `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md`: dated amendment — the third Logs-alert change class: an alert consuming a dual-channel emitter's rows must enumerate every channel the emitter can take (journald AND the curl-direct phone-home), with envelope-field identity on the markerless channel. This is the convention #11527 applies to `inngest_luks_key_probe_fail` and #11528 pins.
5. `knowledge-base/engineering/architecture/diagrams/model.c4`: amend the `inngest -> betterstack` edge description (~:792) to name the second delivery channel — `inngest-boot-phone-home.sh` POSTs `{marker, stage, detail, shipper:"cloud-init-phone-home"}` to the same source 2457081 independent of Vector, and since #11526 the wrong-volume alert's predicate reads BOTH channels. Then `bun test apps/web-platform/test/c4-code-syntax.test.ts apps/web-platform/test/c4-render.test.ts` (or the file's stated runner) must pass.

### Phase 2 — Live-probe the new predicate (pre-merge, required by #11526)

Raw-SQL mode over the hot `remote()` UNION `s3Cluster` archive, `dt`-column window — the file's documented method:

```bash
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  'SELECT count() AS n FROM (
     SELECT dt, raw FROM remote($BS_TABLE)    WHERE dt >= now() - INTERVAL 48 HOUR
     UNION ALL
     SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE dt >= now() - INTERVAL 48 HOUR
   ) WHERE <PREDICATE> FORMAT JSONEachRow'
```

with `<PREDICATE>` successively:

- **A — population:** the unchanged leg-A conjuncts → expect `n > 0` (~49 dedicated rows/48h was yesterday's measurement; establishes the denominator).
- **B — fallback census:** `JSONExtractString(raw,'shipper') = 'cloud-init-phone-home'` grouped by `JSONExtractString(raw,'stage')` → enumerates which phone-home stages exist in the window (vector-down rows are expected ~0 while Vector is healthy; other stages prove the envelope fields resolve on real rows). Also count `stage='inngest-server-probe-vector-down'` alone — record whatever the window holds (0 is the healthy answer; >0 enumerates real past outages).
- **C — quiet control:** the full dual-path predicate with the LIVE alias → expect `n = 0`.
- **D — positive control:** the same predicate with the devid needle swapped to a wrong alias (`scsi-0HC_Volume_0`) → expect `n` = A's count plus any leg-B rows — proves both arms still count rather than silently matching nothing.
- **E — leg-B semantics on synthetic raw (no ingest write):** evaluate the leg-B conjuncts over `SELECT '<literal raw envelope>' AS raw` literals — one with `detail` carrying a wrong devid → expect `1`; one with `detail` carrying the live alias → expect `0`; one carrying the `shipper`+`stage` identity with `detail` absent → expect `1` (the recorded fail-loud schema-drop edge); one in the true jq-failure payload shape (no `shipper`) → expect `0` (the recorded silently-uncounted edge). Verifies leg-B logic without POSTing to the real source.

Record the window and all five numbers into the `.tf` comment block.

### Phase 3 — Apply through the normal path (merge-triggered)

1. PR body carries `Ref #11526`, **not** `Closes` — the live change lands at the merge-triggered apply (the file's own rule: "ARMING HAPPENS ON THE APPLY, NOT AT MERGE").
2. The push-triggered `apply-web-platform-infra.yml` run on the merge SHA applies the exploration (already in the `-target=` allowlist — no workflow edit). Read the apply log: `logtail_exploration.inngest_luks_wrong_volume` updated in place.
3. Post-apply close: once the apply lands, close #11526 with a comment naming the apply run and the Phase-2 numbers (`gh issue close 11526 -c "…"`). `scheduled-terraform-drift.yml`'s `terraform plan -detailed-exitcode` is the continuous backstop; it does not gate closure.
4. Optional same-day sanity: re-run control C once post-apply.

## Files to Edit

- `apps/web-platform/infra/betterstack-logs-alerts.tf` — `local.inngest_luks_wrong_volume_sql` restructured to the dual-path OR; comment block rewritten (closed edge + new residual edges + `LIVE-PROBED` entry).
- `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` — stage-needle derivation, +5 presence rows, +5 `mutate_red` rows, 3 retargeted needles, floors, header bullet.
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` — standing-alarms row gains the dual-channel note.
- `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md` — dated amendment recording the dual-channel predicate convention.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `inngest -> betterstack` edge description names the phone-home channel.

## Files to Create

- None. (`knowledge-base/project/specs/<branch>/tasks.md` and `decision-challenges.md` are pipeline artifacts, not plan deliverables.)

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain none of the planned file paths. (#11388, which overlapped this file in the sibling plan, is `CLOSED`.) Siblings #11527/#11528 touch the same alert family but are explicitly out of scope — #11527 applies the settled pattern to `inngest_luks_key_probe_fail`; #11528 pins whatever conjuncts this change adds (its charter already names "dead-text satisfaction, source wiring, mute knobs, window" gaps in this guard).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the blast radius is a false `soleur-inngest-luks-wrong-volume-prd` page to the ops channel during a Vector outage, or (worse direction) a leg-B that never matches, leaving the alert blind exactly when it matters *if* a wrong-volume state also occurred. No user-facing artifact changes.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure — a read predicate on an existing internal alert; no new credential, no user data surface.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** consistent with the issue's own `User-Impact: aggregate pattern — alarm-integrity erosion on the Inngest observability family` and the sibling #8874 plan — no single user's artifact can be harmed by this diff alone; harm requires compounding (a blind alert missing a real regression, or false pages eroding alarm trust), which is a pattern harm. The store it watches holds all tenants' scheduler state, so a realized incident is inherently class-wide.

## Observability

```yaml
liveness_signal:
  what: "Better Stack Logs alert soleur-inngest-luks-wrong-volume-prd evaluates the dual-path predicate; the probe emits via journald hourly and via phone-home only while Vector is down"
  cadence: "alert evaluation every 300s over a 5400s window; probe emission hourly (OnUnitActiveSec=1h), fallback gated on vector_active != active"
  alert_target: "Better Stack team email (free tier) / betteruptime_policy.uptime escalation (paid tier)"
  configured_in: "apps/web-platform/infra/betterstack-logs-alerts.tf (logtail_exploration_alert.inngest_luks_wrong_volume)"

error_reporting:
  destination: "Better Stack incident → email + push channels declared on the alert resource"
  fail_loud: "count(*) > 0 pages; probe silence is covered by the sibling betteruptime_heartbeat.inngest_server_probe (uptime-alerts.tf), not this alert"

failure_modes:
  - mode: "a fallback row reporting wrong-volume goes uncounted (stage literal drifted, shipper field renamed, or the OR arm dropped)"
    detection: "drift guard presence + mutation rows pin each leg-B conjunct with the stage needle derived from the emit site; a coordinated rename that misses the .tf goes red"
    alert_route: "guard drift → infra-validation.yml CI failure"
  - mode: "a malformed fallback row (no detail) during a Vector outage"
    detection: "this change — the negated devid check on detail counts it as wrong-volume (deliberate fail-loud)"
    alert_route: "incident email — noisy-but-correct, recorded as a residual edge"
  - mode: "applied SQL diverges from declared (apply skipped, partial, or overwritten)"
    detection: "scheduled-terraform-drift.yml terraform plan -detailed-exitcode; the logs-alert arm of heartbeat-live-reconcile.ts"
    alert_route: "drift issue filing + twice-daily reconcile report"

logs:
  where: "Better Stack Logs source soleur-inngest-vector-prd (id 2457081) via journald → Vector, or curl-direct phone-home when Vector is down"
  retention: "hot window ~40min + s3Cluster archive (~90 days per sibling probe comments)"

discoverability_test:
  command: grep -c "JSONExtractString(raw, 'stage') = 'inngest-server-probe-vector-down'" apps/web-platform/infra/betterstack-logs-alerts.tf
  expected_output: "1"
```

## Encryption Posture

```yaml
at_rest:
  - store: "Better Stack Logs warehouse table for source 2457081 (pre-existing; this plan adds no store)"
    mechanism: "provider-managed: Better Stack Telemetry managed ClickHouse (remote() + s3Cluster archive) — unchanged by this diff"
    evidence: "scripts/betterstack-query.sh header (the warehouse read path); no repo-owned disk holds these rows"
    defends_against: "not a store this diff creates — the predicate widens WHICH existing rows count toward an alert"
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

- `apps/web-platform/infra/betterstack-logs-alerts.tf` — `local.inngest_luks_wrong_volume_sql` only: one OR arm + comments. No new resources, providers, variables, or sensitive inputs. Live-probe read credentials are the existing `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` Doppler secrets (`soleur/prd_terraform`), read-only.

### Apply path

Merge-triggered push apply on `apply-web-platform-infra.yml` (`on.push.paths` covers `apps/web-platform/infra/**`; both resources already sit in the main `-target=` allowlist, :653-654). Expected effect: in-place update of `logtail_exploration.inngest_luks_wrong_volume`; the alert resource re-plans unchanged. Blast radius: Better Stack configuration only — zero host impact, zero downtime. Every workflow that can apply this root was enumerated (sharp-edge #8705): `apply-web-platform-infra.yml` is the only applier for `apps/web-platform/infra` (non-`sentry/`); `apply-sentry-infra.yml` covers `infra/sentry/**` only; `scheduled-terraform-drift.yml` runs `plan -detailed-exitcode` read-only; no second push-triggered apply reaches `logtail_exploration.*`.

### Host fan-out

Not applicable — neither changed resource is a `terraform_data` SSH provisioner; no host is contacted.

### Distinctness / drift safeguards

Single `prd` root; `dev` shares no state. Post-apply convergence re-verified by `scheduled-terraform-drift.yml`'s `terraform plan -detailed-exitcode` and the twice-daily `logs-alert` reconciler.

### Vendor-tier reality check

No new Better Stack resources — free-tier limits untouched.

## Architecture Decision (ADR/C4)

### ADR

Amend `ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md` with a dated amendment (its established form — the alert's #6894 birth and paused-arming reconciler already ride dated amendments): the third change class on this alert — an alert consuming a dual-channel emitter's rows must enumerate EVERY channel the emitter can take (journald AND the curl-direct phone-home), pinning envelope-field identity (`shipper`+`stage`) on the markerless channel. Records the accept ruling when landed; #11527 applies the pattern to `inngest_luks_key_probe_fail`. If the ruling is REJECT, the amendment instead records the deliberate exclusion and this plan's other items drop away.

### C4 views

Container view — `model.c4`'s `inngest -> betterstack` edge (~:792) names only the Vector journald channel; it gains the curl-direct phone-home channel (`inngest-boot-phone-home.sh` → source 2457081) now that an alert predicate reads it. Enumeration checked against all three `.c4` files: the external system (Better Stack Logs), the emitter (the Inngest host), and the access relationship (host → Logs source) are already modeled — the only gap is the second delivery channel's existence on this edge, which this amendment closes. Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after the edit.

### Sequencing

The ADR amendment ships in this PR (the convention is true the moment the predicate lands); no `adopting → accepted` soak applies — the convention's truth is the predicate's content, verified pre-merge by the live-probe.

## Guard Contract

### Guard 1 — dual-path predicate on the wrong-volume alert

**Property.** Every row counted by the alert is one of the probe's own rows on EITHER delivery channel — a journald row under `SYSLOG_IDENTIFIER='inngest-server-probe'` beginning with the marker, OR a phone-home envelope under `shipper='cloud-init-phone-home'` at `stage='inngest-server-probe-vector-down'` — and on both legs a wrong `data_mount_devid` counts while the live alias does not.

**Assembly.** The WHERE clause of `local.inngest_luks_wrong_volume_sql` in `apps/web-platform/infra/betterstack-logs-alerts.tf` — the single chokepoint: the exploration's `sql_query` is `replace(trimspace(local…))`, so every counted row flows through this one predicate, and the guard's extracted `LOCAL_SQL` reads exactly that local. Guard side: `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh`, invoked solely by `.github/workflows/infra-validation.yml`. The leg-B `stage` literal's authority is the emit site `apps/web-platform/infra/inngest-bootstrap.sh:1317` (the guard derives `MUT_STAGE` by grepping it — a rename that misses the .tf goes red).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Drop the leg-B `shipper` equality conjunct | RED — leg-B presence row fails (new `mutate_red` row) |
| 2 | Drop the leg-B `stage` conjunct | RED — stage presence row fails (new `mutate_red` row) |
| 3 | Flip the `stage` literal to `inngest-server-probe-other` | RED — derived-needle presence row fails (new `mutate_red` row) |
| 4 | Flip the leg-B `detail` devid check `= 0` → `> 0` (fires on the RIGHT volume via the fallback) | RED — detail-negation presence row fails (new `mutate_red` row) |
| 5 | Delete the whole `OR (…)` arm — legs collapse to journald-only, the #11526 regression | RED — OR-structure presence row fails (new `mutate_red` row) |
| 6 | Guard-side: delete a new presence assertion while the conjunct stays | FATAL — assertion floor: `_ran` drops below the raised floor (dispatch/vacuity row) |
| 7 | Leg-A `message` host_role line gains a `detail` twin in leg B and the 'host_role=dedicated ' substring still matches both | must-PASS — the guard pins each leg's own extraction; a shared substring is permitted duplication, not ambiguity (the devid needles are retargeted per-leg precisely because the bare token WOULD be ambiguous) |

**Anchor.** The stage literal is cross-pinned outside this diff: `inngest.test.sh:2255` greps `inngest-server-probe-vector-down` out of `inngest-bootstrap.sh` for the #7695 parity battery, so a weakening must move the call-site literal AND that suite AND this pair — and the guard derives `MUT_STAGE` from the emit site so the .tf needle follows the rename rather than re-pinning it.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Decide deliberately whether the alert should page on wrong-volume during a Vector outage (accept/reject both defensible)." [issue #11526] | decision-challenges.md row T1 + `## Proposed Solution` ruling arm | mapped |
| 2 | "If accepting: redesign the predicate to admit the fallback — anchor on `detail`/`stage` fields (e.g. `stage = 'inngest-server-probe-vector-down'`), not `marker` … plus restructure the message anchor which the fallback cannot satisfy." [issue #11526] | Phase 1 item 1 / Files-to-Edit `betterstack-logs-alerts.tf` | mapped |
| 3 | "Fresh live-probe controls A–D per the #8874 precedent before apply." [issue #11526] | Phase 2 (controls A–E) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `betterstack-logs-alerts.tf` OR arm + comment rewrite | "redesign the predicate to admit the fallback" | asked |
| `inngest-luks-wrong-volume-alert.test.sh` rows + floors | — | inferred — justification: the drift guard is the only mechanism pinning this SQL's conjuncts; a predicate it does not assert can be reverted silently (identical justification to the sibling plan's guard item) |
| `betterstack-log-query.md` standing-alarms row | — | inferred — justification: the runbook is the documented readback authority for this alert; a predicate shape it does not describe rots the operator's query recipe |
| ADR-218 dated amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` — the dual-channel predicate is the convention #11527 is chartered to apply; the record must not lag the change that creates it |
| `model.c4` edge description | — | inferred — justification: the C4 completeness mandate — the phone-home channel becomes alert-load-bearing on this edge; an edge describing only the Vector path would mislead a reader about what the alert can see |
| Phase 2 live-probe + Phase 3 apply/close | "Fresh live-probe controls A–D per the #8874 precedent before apply" | asked |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform/infra`, `apps/web-platform/test`, `knowledge-base` (one app root + docs)
- Planned files: 5 | Estimated changed lines: ~160
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `local.inngest_luks_wrong_volume_sql` in `apps/web-platform/infra/betterstack-logs-alerts.tf` is the dual-path OR: leg-A conjuncts unchanged (`SYSLOG_IDENTIFIER='inngest-server-probe'`, marker at position 1, 'host_role=dedicated ' on `message`, negated devid on `message`), leg-B conjuncts pinning `JSONExtractString(raw,'shipper') = 'cloud-init-phone-home'` AND `JSONExtractString(raw,'stage') = 'inngest-server-probe-vector-down'` AND 'host_role=dedicated ' on `detail` AND the negated devid on `detail`; the `time BETWEEN` filter wraps both legs.
- [ ] The local's comment block records the #11526 closure of the vector-down blind edge and names the new residual edges (detail-absent fail-loud; unmeasured self-attested `dt`; load-bearing leg-B literals) plus a dated `LIVE-PROBED` entry carrying the Phase-2 counts.
- [ ] `bash apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` exits 0 reporting `39 passed, 0 failed` (floors `39` / `20` under `MUT_SKIP`); the five new `mutate_red` rows each go red on their mutation and the three retargeted needles still land.
- [ ] `bash apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` still exits 0 (the `#8516`/`treat_as_zero`/`inngest_server_probe` citation region is preserved).
- [ ] Phase-2 live-probe executed and recorded: A `> 0`, B enumerates phone-home stages, C `= 0`, D equals A's count plus any leg-B rows, E's three synthetic-raw evaluations return `1`/`0`/`1`.
- [ ] `betterstack-log-query.md`'s standing-alarms row names the dual-channel admission; `ADR-218` carries the dated amendment; `model.c4`'s `inngest -> betterstack` edge names the phone-home channel and `bun test apps/web-platform/test/c4-code-syntax.test.ts apps/web-platform/test/c4-render.test.ts` passes.
- [ ] Post-merge, the `apply-web-platform-infra.yml` run on the merge SHA applies `logtail_exploration.inngest_luks_wrong_volume` (and the alert unchanged) successfully — apply log shows the exploration updated in place.
- [ ] After the apply lands, #11526 is closed with a comment naming the apply run and the Phase-2 numbers; PR body carried `Ref #11526` (never `Closes` — the live change lands post-merge, on the apply).
- [ ] `decision-challenges.md` carries the T1 accept/reject row (obtained ruling or `pending - assumed:`), and the two Operator-reserved holds stand verbatim under `## Operator Holds`.

## Operator Holds

<!-- markdownlint-disable MD034 -->
Delegation: https://github.com/jikig-ai/soleur/issues/10390#issuecomment-6361717901
Envelope: <committed-runbook-path — fill in when the plan phase authors the first Production Envelope; until a readable envelope is committed every hold stands, which is correct here>

- Hold: Operator-reserved: live op=backup verification dispatch — `gh workflow run cutover-inngest.yml -f op=backup` (runbook step 0.5). Not covered by any Scope item: the Scope names only scheduled-terraform-drift.yml, so this file is a scope-mismatch. Non-delegable regardless: the op performs a Hetzner `create_image` snapshot with a READ/WRITE token (.github/workflows/cutover-inngest.yml:8, :100-104) — a write on a third-party system on the Excluded list and explicitly excluded by the operator's recorded words ("any Hetzner/Doppler/Supabase write") — and it runs under the reviewer-gated `inngest-cutover` environment (:104), an approval only a person can give; no Gate kind can discharge it.
- Hold: Operator-reserved: DOPPLER_TOKEN_INFRA_PRIVILEGED seed check — the environment-secret presence probe for the Tier-B token (runbook O3, infra-credential-tiers-8209.md:317, :244). Non-delegable: no delegable command reaches it (`gh secret`/`doppler`/secret-store access are outside the command grammar and on the denylist/never-run list), it touches a third-party secret store, and if the seed is absent the remedy (`doppler configs tokens create` + `gh secret set --env <e>`) is a credential write on the Excluded list.
<!-- markdownlint-enable MD034 -->

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change on an internal alert predicate. The one engineering judgment (accept/reject) routes to the CTO via `decision-challenges.md` row T1 rather than a domain-leader Task: this run has no spawn capability, so the ruling is recorded `pending - assumed: accept` for the parent pipeline to obtain. Product/UX gate: mechanical UI-surface scan of Files to Edit/Create — `.tf`, `.test.sh`, `.md`, `.c4` only, no UI-surface terms — not flagged; tier NONE.

## Test Scenarios

- **Guard RED rows (unit-level, drift guard):** Given a mutated `.tf` copy, when (a) the leg-B `shipper` conjunct is dropped, (b) the `stage` conjunct is dropped or flipped, (c) the `detail` devid check flips `= 0` → `> 0`, or (d) the whole `OR (…)` arm is deleted, then `inngest-luks-wrong-volume-alert.test.sh` reports FAIL on the matching presence row.
- **Guard must-PASS row:** Given a `.tf` copy where leg A's `message`-anchored `host_role` line is reordered after its devid line within leg A, when the guard runs, then it still passes — the contract pins each conjunct's presence, not its ordinal position within a leg.
- **Live-probe controls (integration):** Given `doppler run -p soleur -c prd_terraform` injects `BETTERSTACK_QUERY_*`, when controls A–E run against the ClickHouse hot∪archive table, then A `> 0`, B enumerates stages, C `0`, D = A + leg-B rows, E returns `1`/`0`/`1` — and all numbers land in the `.tf` comment.
- **Apply convergence (integration):** Given the PR merges, when `apply-web-platform-infra.yml` runs on the merge SHA, then the exploration applies cleanly and the subsequent drift `terraform plan` is empty for it.
- **Sibling-guard stability (unit):** Given the comment rewrite, when `inngest-server-probe-heartbeat.test.sh` runs, then the `#8516`-citation and `treat_as_zero` assertions stay green.

## Context

- **Emit order guarantees the trailing space:** the fallback's `detail` field row ends `… data_mount_devid=$data_mount_devid registry_fns=$registry_fns` — `data_mount_devid` and `host_role` are always followed by another field, so the key-anchored trailing-space match holds on `detail` exactly as on `message`.
- **`stage` literal provenance:** the call-site literal lives at `inngest-bootstrap.sh:1317`; `inngest.test.sh:2255` already greps it for the #7695 payload-parity battery — the same suite that asserts the two emit payloads byte-identical (so `host_role`/`data_mount_devid` cannot leave the fallback row without a red suite, including the #10290 schema-bump prune).
- **Why `shipper`+`stage`, not `marker`:** the issue verified `marker='SOLEUR_INNGEST_SERVER_PROBE'` gets 0 rows/48h — the envelope's `marker` is always `SOLEUR_INNGEST_BOOT_STAGE` on this call site (two-arg form, `cloud-init-inngest.yml:502`); `shipper='cloud-init-phone-home'` names the emitter class and `stage` the call site — the same selection shape `inngest-tls-soak-10136.sh` uses.
- **Heartbeat interaction:** during a Vector outage the dead-probe heartbeat already pages — leg B's job is not to replace that signal but to keep the wrong-volume check live *under* it; the two signals say different things (probe-alive vs store-on-right-volume).
- **Pre-existing CI red:** `deploy-script-tests` is red on `main` from an unrelated `vinngest` tag/pin drift (`cloud-init-inngest-bootstrap.test.sh` AC6) owned by another in-flight worktree — distinguish pre-existing reds from this diff's at verification time.
- **AI-generated files:** none — every edit is hand-shaped against pinned literals and existing `mutate_red`/`line_is` recipes.

## References

- Issue: #11526 (this plan's ask, verbatim in Scope Check); sibling shape + CTO ruling: PR #11519 / #8874; pattern consumers: #11527 (out of scope), #11528 (out of scope); emit precedent: #7695 / `inngest.test.sh` parity battery.
- Runbook: `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` (incident runbook URL, unchanged), `betterstack-log-query.md` (standing-alarms row, edited).
- ADR-218 (alert family governance — amended by this plan); ADR-142 (the LUKS cutover this alert watches); ADR-117 (unconditional-emit ordering the fallback `if` sits after).
- Learnings: `2026-10-29-derive-the-needle-and-verify-the-fallbacks-actual-args.md`, `2026-10-09-i-carried-a-measured-dt-claim-from-one-emitter-onto-another.md`, `2026-09-27-a-presence-check-after-source-is-satisfied-by-the-environment.md`.
- Envelope contract precedent: `scripts/followthroughs/inngest-tls-soak-10136.sh`, `scripts/lint-betterstack-emitter-read.sh:147`.
- Sibling plan: `knowledge-base/project/plans/archive/20261029-155548-2026-10-29-fix-inngest-luks-wrong-volume-emitter-plan.md`.
