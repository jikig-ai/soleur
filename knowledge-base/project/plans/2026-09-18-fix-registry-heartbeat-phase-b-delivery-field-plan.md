---
title: "fix: give the registry heartbeat a positive Phase-B delivery field so #7960 can close on proof"
type: fix
date: 2026-09-18
slug: fix-registry-heartbeat-phase-b-delivery-field
branch: feat-one-shot-7960-phase-b-delivery-field
issue: 7960
closes: none  # #7960 is closed by the follow-through sweeper on a real PASS AFTER the merge-triggered replace; the PR body uses `Ref #7960`, never `Closes`
pr: 8272
priority: p2
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# fix: give the registry heartbeat a positive Phase-B delivery field so #7960 can close on proof

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

#7960 watches delivery of the #7500 Phase B producer-side redaction of `zot_last_err` (ADR-211,
Layer 1) to the registry host. Its probe, `scripts/followthroughs/zot-last-err-redact-7500.sh`,
refuses any authoritative verdict — `exit 0` closes a credential-leak tracker, `exit 1` publicly
asserts the redaction is broken — without **positive proof** that the host runs the Phase-B
producer. Today the only Phase-B-exclusive token is `zot_last_err_src=suppressed`, which is
sufficient but not necessary (the gate re-tags only when it withheld a zot-produced sample; a
healthy host on the JSON path emits `fallback` forever), and boot-id drift proves a new *boot*,
not a new *host* (the registry reboots as a convergence primitive). So #7960 cannot auto-close by
construction.

Measured 2026-09-18 (read-only live run of the probe via `doppler run -p soleur -c prd_terraform`):
`exit 3 CANNOT ESTABLISH`, newest boot `78111e0e-f299-4273-ab3a-e7a59a69959d`, **265 tier-4 rows
on that boot, 0 carrying header content**. The current host already runs Phase B (it was replaced
2026-09-17 from a tree containing `96f5b6eb5`); the redaction is very likely working and the
tracker cannot prove it. **The replace this plan triggers buys proof, not protection.**

The fix, end to end:

1. **Producer.** Add a constant, always-present field ` err_redact_rev=1` to the `SOLEUR_ZOT_DISK`
   `LINE=` emitter in `apps/web-platform/infra/cloud-init-registry.yml`, in the trusted region
   (immediately after `zot_last_err_src=$ZOT_ERR_SRC`, far ahead of the free-text `zot_last_err=`
   tail). Pin it in the heartbeat's behavioural suite and the boot guard's field list.
2. **Probe.** Key `DELIVERY_PROVEN` on that field read from the trusted region of any row on the
   newest real boot; keep `suppressed` as a secondary, independently-sufficient proof. Boot drift
   no longer feeds any verdict, so `BASELINE_AT_MERGE`, its override, and every drift branch are
   **deleted**: an unproven boot is one honest state, `exit 3`, whose message names the vehicle.
   Tighten the leak discriminator to structure (a header map, an IP-valued `clientIP`), because
   field-keyed proof makes `exit 1` reachable on ordinary prose for the first time.
3. **Tests.** Extend `scripts/followthroughs/zot-last-err-redact-7500.test.sh` from 19 to 27 cases
   and mutation-prove each new guard, including removal of the field requirement.
4. **Records.** Amend ADR-211 (the delivery-proof key and its Adopting→Accepted trigger); update
   #7960's body so its falsification condition names `err_redact_rev`; file three tracked
   follow-ups (the sibling `zot-log-channel-7440.sh` defect, the dispatcher's hard-coded
   #7555/#7556 refusal wording, and the post-PASS legal/ADR docs PR).
5. **Delivery.** Merging changes the rendered user_data bytes AND starts a web-platform release, so
   `registry-host-replace-dispatch.yml` fires and — per its own history — most likely waits out or
   refuses on preflight P3. The plan treats refuse-then-re-fire as the expected path. **The merge
   authorization is the one operator stop**, and it explicitly covers the re-fire and one direct
   recovery dispatch for this delivery. After a verified green replace and a healthy pull path,
   the local probe must read PASS, then `gh workflow run scheduled-followthrough-sweeper.yml`
   closes #7960.

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief / issue | Reality (verified 2026-09-18) | Plan response |
|---|---|---|
| Budget script at `scripts/registry-userdata-budget.sh` | It is `apps/web-platform/infra/registry-userdata-budget.sh` (+ `.test.sh`) | Use the real path everywhere |
| `LINE=` emitter at `cloud-init-registry.yml` ~:577 | Confirmed: exactly one `LINE="SOLEUR_ZOT_DISK …"` assignment, `zot_last_err=$ZOT_LAST_ERR` last | Insert after `zot_last_err_src=$ZOT_ERR_SRC` |
| Probe harness has 19 cases, `MIN_CASES=19` literal | Confirmed; baseline run `19 passed, 0 failed` | Grow to 27, rebind literal |
| Issue body: heartbeat redaction suite has "26 assertions" | Suite reports `cases=33`, `EXPECTED_MIN=33` | Grow to 36 |
| Last sweep: 113 tier-4 rows on the new boot, 0 leaking | Live re-run: 265 tier-4 rows on `78111e0e…`, 0 leaking, exit 3 | Same state, larger sample |
| "Check whether BASELINE_AT_MERGE and boot-drift branches become dead code" | With proof keyed on the field, drift decides no verdict. BASELINE's only remaining job would be a 2-vs-3 heading between merge and replace — a window that historically lasted 8 days (P3 refusal 2026-09-09 → manual re-fire 2026-09-17), during which a convergence reboot flips it anyway, and whose "not yet" wording would be FALSE because the current host already runs Phase B | Delete BASELINE, its override, and every drift branch (the `zot-log-channel-7440.sh` precedent, #7444 R20/F-7) |
| "Before merging confirm the three zot writers idle, or P3 refuses" | Necessary but not sufficient: this PR touches `apps/web-platform/**`, which is a `web-platform-release.yml` push path, so **the merge itself starts a zot writer**. Dispatch history: 2026-09-09 push → failure (P3), 2026-09-17 manual → success | Keep the pre-merge idle check; plan the P3 wait/refuse + re-fire as the normal path |
| `SOLEUR_ZOT_LOG_BOOT` is not Phase-B-specific | Confirmed: introduced by `07cf8ebcb` (#7444); Phase B is `96f5b6eb5` (#7954) | Not used as a key |
| `suppressed` is the only Phase-B-exclusive token | Confirmed: `ZOT_ERR_SRC=suppressed` is set only inside the tier gate | Kept as secondary proof |
| Unrelated PR #7158 edits `cloud-init-registry.yml` + budget script | Draft, last updated 2026-08-11; its only hunk in that file is the zot `keepTags` block, not `LINE=` | No textual conflict; budget interaction is tens of bytes against 18.6 kB headroom |
| Sibling `zot-log-channel-7440.sh` has the same defect class | Confirmed: its sole `exit 1` arm counts leaks over an unscoped `$WINDOW` while delivery evidence comes from a separate 72h boot-marker query. Its tracker #7455 is CLOSED and no open follow-through issue enrolls it — latent | File a separate issue |
| (found in review) the dispatcher's refusal notices | `registry-host-replace-dispatch.yml` hard-codes #7556 as the comment target and "#7555 deadline change is NOT live" as the refusal text, and #7555/ADR-190 in the dispatch reason — a refusal of THIS delivery lands on the wrong tracker with wrong text | Pre-existing; post a pointer on #7960 on refusal, file an issue for the wording |

## Research Insights

### Relevant files

- `apps/web-platform/infra/cloud-init-registry.yml` — `zot-disk-heartbeat.sh` write_files block;
  tier selection + `ZOT_ERR_SRC=fallback|suppressed`, `redact()`/`redact_sample_lines()`,
  `BOOT_ID=` (`[ -n "$BOOT_ID" ] || BOOT_ID=unknown`), and the single `LINE=` + `post()` emit
  chokepoint. The script runs `set -u`. Its journald egress-failure echo
  (`echo "[zot] SOLEUR_ZOT_DISK egress to Better Stack Logs FAILED: $LINE"`) will carry the new
  token too — which is why only the envelope anchor keeps such rows out of the evidence base.
- `scripts/followthroughs/zot-last-err-redact-7500.sh` — envelope anchor, two-hop decode with `dt`
  sort, `NEWEST_BOOT` (MIRRORS `zot_newest_boot`), one awk pass with first-occurrence head cut +
  boot filter (`TIER4_ROWS`), `LEAKY`, `DELIVERY_PROVEN` (suppressed-only today),
  `BASELINE_AT_MERGE`, the verdict chain.
- `scripts/followthroughs/zot-last-err-redact-7500.test.sh` — production double-encoded fixtures,
  `row()`/`foreign()`/`proof()`, `expect <name> <rc> <fixture> <marker>`, probe-must-have-run
  guard, conservation, `MIN_CASES`. `HERE` is `scripts/followthroughs`.
- `scripts/lib/zot-telemetry-parse.sh` — `zot_envelope_anchor`, `zot_trusted_region`,
  `zot_newest_boot`. Not sourced by the probe (documented JSON-row reason); mirrored with labels.
  **Unchanged by this plan.**
- `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` — extracts the heartbeat block to
  `$RAW`, applies the rationale strip to `$HB`, runs it against PATH stubs, captures the POSTed row;
  helpers `assert` and `assert_emit` (whole-body substring), dispatch self-test over both.
- `apps/web-platform/infra/registry-boot-guard.test.sh` — `LINE_ASSIGN` field-presence loop and the
  "zot_last_err is the LAST field" suffix assert; `MIN_ASSERTIONS=103` (104 run today).
- `apps/web-platform/infra/registry-userdata-budget.sh` — offline terraform render, strip, base64gzip.
- `.github/workflows/registry-host-replace-dispatch.yml` — push-to-main trigger on stripped-render
  change (watermark-based), preflight, dispatch of
  `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=registry-host-replace -f reason=…`,
  a 1500 s poll that exits 0 with an "UNVERIFIED" warning when it cannot identify or finish watching
  the apply, refusal artifact posted to #7556.
- `.github/workflows/apply-web-platform-infra.yml` — `registry_host_replace` job
  (`if: github.event_name == 'workflow_dispatch' && inputs.apply_target == 'registry-host-replace'`,
  no environment gate), which logs `zot store volume preserved (0 delete/forget) and private NIC
  re-attached (create present) in the applied plan.`
- `scripts/registry-replace-preflight.sh` — P3 waits (up to 2100 s) then refuses on in-flight or
  queued runs of `web-platform-release.yml`, `build-inngest-config-bundle.yml`,
  `build-inngest-bootstrap-image.yml`.
- `scripts/sweep-followthroughs.sh` + `.github/workflows/scheduled-followthrough-sweeper.yml` — cron
  `0 18 * * *`, `workflow_dispatch` (input `dry_run`, default false), no issue filter; renders exit 2
  as "NOT YET" and exit 3 as "CANNOT ESTABLISH"; exit 1 on an OPEN issue posts a FAIL comment and
  leaves it open; a CLOSED issue carrying the sweeper's own PASS comment is skipped thereafter.
- `knowledge-base/engineering/architecture/decisions/ADR-211-zot-last-err-redaction-at-the-producer-and-the-sink.md` — `status: adopting`.

### Consumer sweep (every parser of `SOLEUR_ZOT_DISK`)

All parsers read by exact key name (`grep -oE 'key=…'`, `awk -F= '$1==k'`), substring, or the
first-occurrence ` zot_last_err=` cut — none is positional, field-counting, adjacency-binding, or a
strict allowlist: `scripts/lib/zot-telemetry-parse.sh`, `scripts/zot-disk-sample.sh`,
`scripts/zot-restart-loop-alarm.sh` (its `zot_last_err_src=\([^ ]*\)` capture stops at the next
space), `scripts/followthroughs/zot-restart-plateau-6288.sh`, `.github/workflows/reusable-release.yml`,
`tests/scripts/test-zot-disk-sample.sh`; marker-only: `registry-heartbeat-poll.sh`,
`registry-replace-preflight.sh`, `zot-inventory-assert-marker.sh`. Byte-budget tests are ceilings.
**No collision:** `git grep 'err_redact_rev\|redact_rev'` returns nothing. The name avoids the
`zot_last_err` prefix; no consumer cuts on a prefix-only `zot_last_err`.

### Budget (measured, not estimated)

`bash apps/web-platform/infra/registry-userdata-budget.sh --json` on the current tree:
`stripped_bytes 39737, stored_bytes 14168, headroom 18600`. The same script on a scratch copy with
the one-token edit: `stripped_bytes 39754 (+17), stored_bytes 14180 (+12), headroom 18588`. TS
budget `REGISTRY_GZIP_BUDGET=20000`; ADR-185 policy ≥ 8,000 B headroom. The token is on a
non-comment line, so the rationale strip keeps it and the dispatch gate sees a real rendered-byte
change — which is what delivers it. The accompanying `#` comment is stripped (0 bytes delivered).

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-09-08-every-field-my-alarm-trusted-came-from-the-region-it-did-not-trust.md` —
  every verdict field must be read before the FIRST ` zot_last_err=`.
- `knowledge-base/project/learnings/2026-09-17-scoping-a-verdict-on-an-unanchored-query-is-a-false-close-primitive.md` —
  authenticate (envelope anchor) before scoping; with no necessary-and-sufficient key, refuse.
- `knowledge-base/project/learnings/2026-08-13-a-rider-is-only-valid-while-its-vehicle-is-still-pending.md` —
  state the falsification condition against the vehicle (the replace), not the calendar.
- `knowledge-base/project/learnings/2026-08-04-my-probe-passed-against-the-outage-it-was-built-to-detect.md` —
  only a signal structurally impossible for the old producer is a positive control.
- `knowledge-base/project/learnings/2026-09-08-every-guard-i-added-to-the-gate-could-not-fail.md` and
  `knowledge-base/project/learnings/2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md` —
  mutation-prove against the real probe; branch markers, not exit codes alone.
- `knowledge-base/project/learnings/2026-09-10-six-instruments-reported-could-not-measure-as-clean.md` —
  a missing field is "could not measure", never clean.
- `knowledge-base/project/learnings/best-practices/2026-07-14-cloud-init-templatefile-escaping-and-ci-deploy-payload-testing.md` —
  measure the rendered, stripped, gzipped payload.

### Related issues / PRs

#7500 (decision), #7954 / `96f5b6eb5` (Phase B), #8244 / `9472c2935` (mixed-boot scoping, exit 3),
#7444 / `07cf8ebcb` (log shipper), #7455 (closed 7440 tracker), #7555/#7556 (dispatcher's
hard-coded delivery), #7530 (clientIP invariant, out of scope), #7158 (unrelated draft), PR #8272.

### Premise Validation

#7960 is OPEN with no closing PR. The cited emitter, probe, harness, parse library, budget script,
dispatch workflow, apply job and preflight exist on this branch (base `4b087c388`). `96f5b6eb5` and
`07cf8ebcb` resolve to the commits the brief attributes. The brief's budget-script path was wrong
(corrected). The ADR corpus was checked for the mechanism: ADR-211 records the suppressed token and
the Adopting trigger; the sibling precedent (`zot-log-channel-7440.sh`, #7444 F-7/R20) already chose
"a key only the new cloud-init can produce" over boot drift and deleted its baseline — this plan
applies the same mechanism. The sweeper renders exit 2 and exit 3 under different headings
(`scripts/sweep-followthroughs.sh`: `2) verdict="NOT YET"`, `3) verdict="CANNOT ESTABLISH"`).

### Property List

- **P1.** The probe exits 0 (closes #7960) only when the graded boot provably runs a Phase-B
  producer AND ≥1 tier-4 row exists on that boot AND no `fallback` row on it carries header content.
- **P2.** The probe exits 1 only when the graded boot provably runs a Phase-B producer AND a
  `fallback` row on that boot carries header *structure* (a header map or an IP-valued `clientIP`) —
  never on prose that merely names the words.
- **P3.** Delivery proof is read only from envelope-anchored rows, from the trusted region, on the
  newest real boot — unforgeable from the free-text tail, a marker-quoting foreign row, the
  producer's own journald echo, or the `unknown` boot sentinel.
- **P4.** Absent proof, the probe says so under a heading that is true in every state it covers,
  and names the vehicle whose completion turns that reading into "investigate".
- **P5.** Every emitted `SOLEUR_ZOT_DISK` row carries the proof field in the trusted region, and
  user_data stays within budget.
- **P6.** Nothing the probe prints on the public issue echoes row content (counts, boot ids and
  proof-source names only).
- **P7.** The delivering replace is verified from the apply run itself (conclusion + store-volume
  assert) and the pull path is healthy afterwards — not inferred from a green dispatcher run.

### Cut List

- *`BASELINE_AT_MERGE` and every drift branch* → P4 → cut: the field makes drift irrelevant to
  every verdict; the only thing BASELINE still bought was a "not yet" heading that is false on the
  current host (already Phase B) and stale after any convergence reboot or multi-day P3 refusal.
  One exit-3 message naming the vehicle serves P4 in every state.
- *Generic user_data content hash via a `templatefile` var* → P5 → cut: cannot order revisions;
  touches `zot-registry.tf` and two budget stubs.
- *Control-plane proof from the dispatcher's success watermark* → P1 → cut: a green dispatcher can
  mean "UNVERIFIED"; it attests an apply, not what the host emits; needs `GH_TOKEN` under `env -i`.
- *A parse-library helper (`zot_delivery_rev`)* → P3 → cut: the probe does not source the library;
  the existing single awk pass is the chokepoint.
- *Per-path producer emit assertions* → P5 → cut to one: there is one `LINE=` and one `post()`.
- *A hash tripwire forcing a revision bump when the gate changes* → P5 → cut: deleting or breaking
  the gate already reddens the existing G1-6/G1-6b/G1-8 behavioural rows; a bump discipline is
  recorded in ADR-211 and the producer comment.
- *A PASS sample floor (e.g. ≥6 tier-4 rows)* → P1 → cut: the leak check is per-row and the proof is
  per-boot; one clean tier-4 row on a proven boot is valid evidence, and correctness is proven
  pre-merge by the redaction suite. Would also force every PASS fixture to grow.

## Design

### The field

- Token: ` err_redact_rev=1`, inserted immediately after `zot_last_err_src=$ZOT_ERR_SRC` in the
  single `LINE=` assignment. A **literal**, never `$VAR`: the script runs `set -u`, and a deleted
  assignment would kill the whole heartbeat before `LINE` is built.
- Contract (a whole-line `#` comment above `LINE=`, stripped at render, and ADR-211): an integer
  revision of the `zot_last_err` redaction gate; any value ≥ 1 means the Phase-B tier gate and
  per-line redaction are present; bump when the gate changes; never decrement or reuse; never keep
  the token while removing the gate.
- The probe's header gains one line: `# PROOF KEY: err_redact_rev (producer: cloud-init-registry.yml LINE=; contract: ADR-211).`

### Probe decision table (after the existing channel / envelope / decode / no-usable-boot guards, unchanged)

Inputs, all on the newest real boot `B`, all from the trusted region (text before the FIRST
` zot_last_err=`): `F` = any row carries `(^| )err_redact_rev=[1-9][0-9]*( |$)`; `S` = any tier-4
row carries `zot_last_err_src=suppressed`; `T` = tier-4 rows (`fallback|suppressed`); `L` =
`fallback` rows whose tail matches the tightened leak structure.

| Row | Proof (`F` or `S`) | `T` | `L` | Exit | Heading / unique marker |
|---|---|---|---|---|---|
| R1 | yes | 0 | – | 2 | stdout/stderr begins `DELIVERY PROVEN (<source>) — no tier-4 row on boot B yet` |
| R2 | yes | >0 | >0 | 1 | `FAIL: delivery proven (<source>) and L of T tier-4 row(s) STILL carry header content` |
| R3 | yes | >0 | 0 | 0 | `PASS: producer delivered (proof: <source>) — T tier-4 row(s) on boot B, none carrying header content` |
| R4 | no | any | any | 3 | `CANNOT ESTABLISH: boot B lacks err_redact_rev …` — reports `T`, `L`; states that this is expected until the registry-host-replace triggered by merging PR #8272 completes, and that after it completes this reading means the field is not reaching the host: investigate, do not wait |

`<source>` is `err_redact_rev`, `suppressed`, or `err_redact_rev+suppressed`. R1 renders under the
sweeper's "NOT YET" heading; accepted in writing because its first line says DELIVERY PROVEN. An
all-`suppressed` boot (T > 0, zero `fallback` rows) passes via R3: the gate withheld every sample,
so there is nothing that could leak — accepted in writing.

**Tightened leak structure (`L`).** Replace `(headers|clientIP)[[:space:]]*[]=:{"]` with
`headers[[:space:]]*[:=][[:space:]]*[[{]` OR `clientIP[[:space:]]*[:=][[:space:]]*[0-9A-Fa-f]`
(header map, or `clientIP` carrying an address). The producer strips quotes (`tr -d '"\\'`), so a
real leak reads `headers:{Cookie:[…]}` / `clientIP:10.0.1.9`. Verified against real data in
Phase 3.4, not assumed.

Implementation notes (for /work):

- **One pass, one trusted region.** Extend the existing awk pass (same first-occurrence cut, same
  boot match) to also count `F` across ALL newest-boot rows, emitted as a sentinel line or via a
  second output — do not add a second awk with its own copy of the cut or the boot filter. `F` must
  NOT be derived from `TIER4_ROWS` (the field is on every row, not only tier-4 rows). Label it
  `MIRRORS zot_trusted_region`.
- Each `exit` in the verdict chain carries a one-line comment naming its row (`# R3: proof, T>0, L==0 -> PASS`).
- Messages interpolate only counts, boot ids, `$WINDOW`, and the proof-source name (P6).
- A comment records why "≥1 row on the newest boot" suffices: a boot's script file cannot change
  mid-boot on a no-SSH, cloud-init-only host.
- Rewrite the header and body prose so nothing describes boot drift as delivery evidence (the
  EXIT CONTRACT lines, "WHY 1 IS NARROW", "DELIVERY IS INFERRED…", "DELIVERY IS ITS OWN QUESTION…",
  the Guard-1 block, the `BASELINE_AT_MERGE` comment blocks). Collapse the header's restatement of
  branch conditions to a pointer at the decision-table comment.

### Deleted (not left reachable)

`BASELINE_AT_MERGE`, `BASELINE`, the `SOLEUR_FT_BASELINE_BOOT` override, Guard 1's
"DELIVERY HAS LANDED" drift arm, the authoritative branch's `NEWEST_BOOT != BASELINE` gate, the
pre-delivery "NOT YET DELIVERED — N leaking" branch, the empty-BASELINE "delivery state UNKNOWN"
branch, the on-baseline "NOT YET DELIVERED" branch, and the terminal "unreachable by construction"
block (R4 is the live final exit). Kept: every channel/envelope/decode guard and the
no-usable-`boot_id` exit 3. The harness's `BASELINE` extraction and the `-u SOLEUR_FT_BASELINE_BOOT`
in `run_probe` go too.

## Implementation Phases

Contract before consumer: the producer field is the contract; the probe and its fixtures consume it.

### Phase 0 — Preconditions (read-only)

1. Baseline suites green: probe harness (19/19), heartbeat redaction suite (33/33), boot guard
   (104 assertions).
2. `bash apps/web-platform/infra/registry-userdata-budget.sh --json` → record.

### Phase 1 — Producer field (RED → GREEN)

1. RED — `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh`, +3 assertions:
   - structural (`assert`): in `$RAW`, `grep -c 'LINE="SOLEUR_ZOT_DISK'` is exactly 1, and that
     line matches ` err_redact_rev=[1-9][0-9]* ` at an offset before ` zot_last_err=`;
   - emit-level (`assert` over the captured row, not `assert_emit`, because `assert_emit` matches the
     whole body): for the `TIER4_HEADERS` fixture under the no-jq PATH (the suppressed path),
     `${out%% zot_last_err=*}` contains ` err_redact_rev=`;
   - must-PASS non-canonical: `assert_emit … "$PANIC_LINE" present "err_redact_rev="` (tier 1).
   Bump `EXPECTED_MIN` 33 → 36. `registry-boot-guard.test.sh`: add `err_redact_rev=` to the
   field-presence loop; bump `MIN_ASSERTIONS` 103 → 104 (105 run). Run both: the new assertions FAIL.
2. GREEN — add ` err_redact_rev=1` after `zot_last_err_src=$ZOT_ERR_SRC` plus the contract comment.
3. Both suites green; budget script re-run (expected stored +12 B); run
   `apps/web-platform/infra/registry-userdata-budget.test.sh` and the `cloud-init-user-data-size`
   test through the package's own runner (read `package.json` `scripts.test` first).

### Phase 2 — Probe harness (RED)

1. Read the proof token FROM the producer:
   `grep -F 'LINE="SOLEUR_ZOT_DISK' "$HERE/../../apps/web-platform/infra/cloud-init-registry.yml" | head -1 | grep -oE 'err_redact_rev=[^ "]+'`.
   Loose on purpose (`[^ "]+`, not `[1-9]…`): a producer value of `0` must reach the fixtures and
   redden N1, not die at extraction. `FATAL` via printf + `exit 1` if empty.
2. `rowf <dt> <boot> <src> <tail>` inserts the token after `zot_last_err_src=`, mirroring the
   producer's field order. Delete the `BASELINE` extraction; use a fabricated `OLDBOOT` uuid.
3. Update changed cases and add new ones (Test Scenarios). Rebind `MIN_CASES=27` (literal; keep
   the `only %s cases ran` FATAL wording).
4. Run: every new/changed case must FAIL against the current probe for the reason it names.

### Phase 3 — Probe change (GREEN)

1. Implement the decision table, the `F` counter in the existing awk pass, the tightened `L`;
   delete everything in §Deleted; rewrite drift-as-proof prose; add the row comments and the
   PROOF KEY header line.
2. Harness 27/27 green; `shellcheck` probe + harness; `bash scripts/guard-vacuity-floor.test.sh`
   green (the rebound floor classifies as FIRES).
3. Mutation-prove every Guard Contract row against scratch copies of the real files; record
   `mutation → case/assertion → got` in the GREEN commit's message (ship folds commit bodies into
   the PR body; no separate knowledge-base artifact).
4. **Leak-regex check against real data (P2 invariant, not proxy).** Read-only:
   `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 10d --grep SOLEUR_ZOT_DISK --limit 5000`,
   anchor + decode as the probe does, restrict to boot `d0107f1f-834b-4acc-bd5a-00e53b61d835`
   (the pre-Phase-B host) `fallback` rows, and count with the OLD and NEW `L` patterns. Required:
   NEW ≥ 1 and NEW == OLD (the tightening loses no real leak). Then the same two counts on boot
   `78111e0e-…` (Phase B): both 0. If the pre-Phase-B rows have aged out, record that and fall back
   to the synthetic fixtures only — never assert the equality without the data.
5. Live read-only probe run: expected `exit 3` with the new R4 message naming `78111e0e-…` and
   "lacks err_redact_rev" (the current host is Phase B without the field).

### Phase 4 — Records and follow-ups

1. **ADR-211 amendment** (in place; `status:` stays `adopting`): a dated
   `### Delivery proof: err_redact_rev (2026-09-18, #7960)` subsection under Decision — the field,
   its contract, why `suppressed` alone was insufficient, why boot drift is not proof and was
   removed from the verdict, the tightened leak structure; amend the Status bullet's trigger to
   "flips to Accepted when the #7960 probe PASSes on a boot proven by `err_redact_rev` (or
   `suppressed`)". Record in Consequences that after that PASS nothing re-grades the warehouse
   stream for regression (the sweeper skips a PASS-closed issue); the producer suite (pre-merge,
   every future edit) and the Layer 2 sink scrub remain.
2. **#7960 body**: draft to
   `knowledge-base/project/specs/feat-one-shot-7960-phase-b-delivery-field/issue-7960-body.md`
   (kept on disk so an interrupted post-merge run can resume) — directive line byte-identical; exit
   contract rewritten to R1–R4; a dated amendment stating the falsification condition: *"after the
   registry-host-replace triggered by merging PR #8272 completes (verified from the apply run), a
   CANNOT ESTABLISH naming a boot that lacks `err_redact_rev` means the field did not reach the
   host — investigate, do not wait."* Applied only after `gh pr view 8272 --json state` = MERGED.
3. **File follow-ups** (labels verified: `type/chore`, `domain/engineering`, `priority/p3-low`):
   (a) `zot-log-channel-7440.sh`'s `exit 1` arm grades an unscoped `$WINDOW` while delivery
   evidence comes from a separate 72h boot-marker span — latent (#7455 closed, not enrolled);
   re-evaluate on re-enrollment. (b) `registry-host-replace-dispatch.yml` hard-codes #7556 as the
   refusal/failure comment target and #7555/ADR-190 in its refusal text and dispatch reason, so any
   other delivery's refusal lands on the wrong tracker with false text. (c) created at merge time,
   see Phase 5.
4. `bash scripts/generate-kb-index.sh` for the new `knowledge-base/` files; commit `knowledge-base/INDEX.md`.

### Phase 5 — Ship and deliver (inside /ship and its post-merge verification)

0. **Resume check** (idempotency): `gh pr view 8272 --json state`, `gh issue view 7960 --json state`,
   and a local probe run decide which step below to resume at; never re-merge or re-dispatch on a
   step already concluded.
1. Pre-merge: writer-idle check (`gh run list --workflow <w> --status in_progress` and
   `--status queued`, for all three zot writers) — necessary, not sufficient (step 3).
2. Pre-merge: file follow-up (c) — the post-PASS docs PR tracker (ADR-211 `status: accepted`; dated
   delivery entries in BOTH `knowledge-base/legal/article-30-register.md` cells carrying the
   "INERT until the next `registry-host-replace`" bracket, as `> **Superseded 2026-09-DD (#7960): …**`
   under the superseded sentence; close the `open_limbs` entry of
   `knowledge-base/legal/audits/2026-09-08-clo-attestation-7500-zot-last-err-redaction.md`), trigger:
   #7960 closed by a sweeper PASS.
3. **THE ONE OPERATOR STOP — explicit authorization** (`hr-menu-option-ack-not-prod-write-auth`;
   a menu acknowledgement is not authorization). State plainly:
   *"Merging PR #8272 changes the registry host's rendered user_data and also starts a
   web-platform release + deploy. That fires registry-host-replace-dispatch.yml, which has no
   environment reviewer and no confirm token: it DESTROYS and RECREATES the production registry
   host. The fleet's only image pull path is down for the replace window; the zot store volume is
   preserved (asserted). The current host already runs the Phase B redaction — this replace buys
   PROOF of it, not new protection. Because the merge starts a zot writer, the dispatcher will most
   likely wait and then refuse on preflight P3; the plan then re-fires it once the release and
   deploy conclude. This authorization covers: (1) the merge, (2) re-firing the dispatcher for this
   merge SHA, and (3) one direct `registry-host-replace` recovery dispatch if the apply fails after
   the destroy. Authorize?"* Merge immediately on the yes (no `--auto`).
4. Apply the #7960 body edit.
5. **Replace, expected path.** Watch (Monitor tool, until-loops, never background sleeps) the
   dispatch run for the merge SHA and the release/deploy runs the merge started.
   - If the dispatcher refuses on P3 (expected): post a pointer comment on #7960 (the dispatcher
     posts to #7556), wait for the three writers to conclude, re-fire with
     `gh workflow run registry-host-replace-dispatch.yml -f reason="P3 refusal resolved: delivering PR #8272 (err_redact_rev) for #7960"`.
   - Identify the dispatched apply run (`apply-web-platform-infra.yml`, `workflow_dispatch`, created
     after the dispatch) and watch IT: `conclusion == success`, and its log contains
     `zot store volume preserved (0 delete/forget)`. A dispatcher "UNVERIFIED" warning, a
     `cancelled` apply, or no apply run is NOT delivered — re-fire. Do not treat a green dispatcher
     run as proof (P7).
   - **5b — apply failed after destroy** (registry likely dark; the dispatcher re-fire could itself
     wait on P3 behind deploys blocked by the outage): recover directly with
     `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=registry-host-replace -f reason="recovery: failed replace delivering PR #8272 (#7960)"`
     (covered by the authorization, once). A second failure is an incident: stop and report.
6. **Pull-path health** (P7): the first two new-boot `SOLEUR_ZOT_DISK` rows show
   `state_status=running`, `ping_rc=0`, and increasing `zot_uptime_s`.
7. **Probe to PASS**: loop the local probe (Monitor until-loop, bounded to 90 min after the apply
   succeeded) until exit 0. On timeout with R1 (proven, no tier-4 yet): leave it to the 18:00 cron
   and report. On R4 after a verified replace: investigate now (is the token in the newest rows'
   trusted region? did the replace render from the merge SHA? is the new boot the replaced host?).
   On `channel_dark`: the new host is not posting — check its Doppler service token delivery.
8. `gh workflow run scheduled-followthrough-sweeper.yml` (side effect accepted: it sweeps every
   open tracker exactly as the daily cron does); watch to completion; verify
   `gh issue view 7960 --json state` = CLOSED with a PASS comment.
9. After PASS: open the docs-only PR that closes follow-up (c). CLO: post-PASS only, never in #8272;
   cite the probe by script name, never by line number.

## Files to Edit

- `apps/web-platform/infra/cloud-init-registry.yml` — the `LINE=` token + one whole-line comment.
- `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` — +3 assertions; `EXPECTED_MIN=36`.
- `apps/web-platform/infra/registry-boot-guard.test.sh` — field list + `err_redact_rev=`; `MIN_ASSERTIONS=104`.
- `scripts/followthroughs/zot-last-err-redact-7500.sh` — decision table, `F` in the existing awk
  pass, tightened `L`, §Deleted, prose rewrite, row comments, PROOF KEY header line.
- `scripts/followthroughs/zot-last-err-redact-7500.test.sh` — producer-extracted token, `rowf`,
  BASELINE removal, changed + new cases, `MIN_CASES=27`.
- `knowledge-base/engineering/architecture/decisions/ADR-211-zot-last-err-redaction-at-the-producer-and-the-sink.md` — amendment.
- `knowledge-base/INDEX.md` — regenerated.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-7960-phase-b-delivery-field/tasks.md` (plan skill).
- `knowledge-base/project/specs/feat-one-shot-7960-phase-b-delivery-field/issue-7960-body.md` (Phase 4.2).

Diff-scope note: the pipeline also writes
`knowledge-base/project/specs/feat-one-shot-7960-phase-b-delivery-field/session-state.md`,
`knowledge-base/project/specs/feat-one-shot-7960-phase-b-delivery-field/decision-challenges.md` and
the regenerated `knowledge-base/INDEX.md`; they are expected in the final diff.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` bodies checked for every path above plus
`zot-last-err-redact-7500` and `zot-telemetry-parse`; zero matches.)

## User-Brand Impact

- **If this lands broken, the user experiences:** either (a) a false PASS that closes #7960 while
  the registry heartbeat ships request-header content (Cookie / X-Api-Key of fleet pull clients)
  into the Logs warehouse — a credential exposure nobody watches any more, because the sweeper
  never re-grades a PASS-closed issue; (b) a false public FAIL on #7960 claiming the redaction is
  broken when a zot message merely names "headers"; or (c) a failed merge-triggered host replace
  that strands the fleet's only image pull path, blocking every deploy and re-pull until recovered.
- **If this leaks, the user's workflow is exposed via:** registry pull/push credentials carried in
  zot request headers, readable by every holder of the `BETTERSTACK_QUERY_*` credentials — a
  supply-chain exposure; the public alarm egress is separately covered by the ADR-211 sink scrub.
- **Brand-survival threshold:** `aggregate pattern` — each failure mode is a fleet-wide platform
  degradation (a lost watch, a false public alarm, a pull-path outage), not one user's data breach.
  The redaction logic itself is unchanged; this plan changes only what proves it is running.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_ZOT_DISK heartbeat row carrying err_redact_rev, graded daily by the follow-through sweeper
  cadence: heartbeat every 5 min; sweeper daily 18:00 UTC plus on-demand workflow_dispatch
  alert_target: public comment on #7960 under the sweeper's NOT YET / CANNOT ESTABLISH / FAIL / PASS heading
  configured_in: apps/web-platform/infra/cloud-init-registry.yml (/etc/cron.d/zot-disk-heartbeat) and .github/workflows/scheduled-followthrough-sweeper.yml
error_reporting:
  destination: sweeper comment on #7960 carrying the probe's stderr (last 4 KB), counts only
  fail_loud: exit 1 posts a FAIL comment and keeps #7960 open (it never closes on 1); exit 3 renders under its own CANNOT ESTABLISH heading
failure_modes:
  - mode: field did not reach the host after a verified replace
    detection: probe reads a newest boot whose trusted region lacks err_redact_rev
    alert_route: exit 3 CANNOT ESTABLISH comment on #7960 naming the boot and the investigate action
  - mode: redaction delivered but not working
    detection: fallback rows on a proven boot whose tail carries a header map or an IP-valued clientIP
    alert_route: exit 1 FAIL comment on #7960
  - mode: heartbeat channel dark or query/auth failure
    detection: zero SOLEUR_ZOT_DISK rows or betterstack-query.sh non-zero
    alert_route: exit 2 TRANSIENT comment (channel_dark / auth failure)
  - mode: merge-triggered replace refused (P3) or apply failed / never observed
    detection: dispatcher refusal step; the dispatched apply run's own conclusion and store-volume log line
    alert_route: the dispatcher's refusal artifact (posts to #7556 today — follow-up b) plus this pipeline's pointer comment on #7960 and a red run
  - mode: apply green but zot dark on the new host
    detection: new-boot rows without state_status=running / ping_rc=0 / growing zot_uptime_s; the existing registry liveness heartbeat monitor
    alert_route: Better Stack heartbeat alert (existing) and a halted Phase 5.6
  - mode: regression after PASS
    detection: none in the warehouse stream (the sweeper skips a PASS-closed issue); the producer suite on any future edit and the Layer 2 sink scrub on the public egress
    alert_route: CI red on the edit; recorded as a known residual in ADR-211
logs:
  where: Better Stack Logs source 2457081 (SOLEUR_ZOT_DISK rows); sweeper output in #7960 comments
  retention: Better Stack source retention for the rows; GitHub issue comments indefinitely
discoverability_test:
  command: bash scripts/followthroughs/zot-last-err-redact-7500.sh
  expected_output: "PASS: producer delivered (proof: err_redact_rev) — N tier-4 row(s) on boot <id>, none carrying header content"
  credentials_required: "BETTERSTACK_QUERY_HOST / BETTERSTACK_QUERY_USERNAME / BETTERSTACK_QUERY_PASSWORD (read-only Logs SQL) — the property is the content of warehouse rows, which have no unauthenticated read path"
```

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file changes; `hcloud_server.registry.user_data` is re-rendered from the edited
template by the existing `base64gzip(replace(templatefile(...), local.registry_rationale_strip, ""))`
chain in `apps/web-platform/infra/zot-registry.tf`. No new variables, providers or secrets.

### Apply path

(c) replace — the only path for this cloud-init-only host (ADR-096), already automated by
`registry-host-replace-dispatch.yml` → `scripts/registry-replace-preflight.sh` →
`apply-web-platform-infra.yml` `registry_host_replace`. Blast radius: the registry host is
destroyed and recreated; the zot store volume is preserved (asserted in the apply log); the fleet's
pull path is down for the replace window. Last exercised green 2026-09-17T11:21Z via manual re-fire.

### Distinctness / drift safeguards

`user_data` is ForceNew with no `ignore_changes` by design; the stored payload stays 18,588 B under
the 32,768 B Hetzner cap and under the 20,000 B TS budget. The dispatcher's watermark coalesces
evicted deliveries, but a green dispatcher run is not proof of delivery (Phase 5.5 verifies the
apply run itself).

### Vendor-tier reality check

No vendor resource is created. Better Stack Logs ingest is unchanged (+17 bytes per row).

## Encryption Posture

```yaml
at_rest:
  - store: betterstack logs source 2457081 (existing; receives the heartbeat row, now +17 bytes of a constant)
    mechanism: provider-managed:Better Stack Logs storage encryption (unchanged by this plan; no new store)
    evidence: knowledge-base/legal/article-30-register.md Better Stack processor row (existing disclosure; this plan adds no data category)
    defends_against: raw-disk or backup-media exposure at the provider
    does_not_defend: any holder of BETTERSTACK_QUERY_* credentials reading row content; a provider-side account compromise
    disclosed_as: knowledge-base/legal/article-30-register.md (PA-8, Better Stack recipient row)
    live_verification: unavailable:provider-managed storage has no customer-side probe
in_transit:
  - connection: registry host zot-disk-heartbeat.sh -> Better Stack Logs ingest (existing, unchanged)
    enforced_at: apps/web-platform/infra/cloud-init-registry.yml post() (curl -fsS against the https betterstack_ingest_url)
    tls: https, curl defaults (TLS 1.2+)
    cert_verification: on
    does_not_defend: content exposure to credential holders at the destination; the redaction layer is what bounds content
    disclosed_as: knowledge-base/legal/article-30-register.md (PA-8)
```

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-211** in place (no new ordinal): `err_redact_rev` as the delivery-proof key, its
contract, the authoritative-verdict rule (proof, never drift), `suppressed` as secondary proof, the
tightened leak structure, the post-PASS regression residual, and the amended Adopting→Accepted
trigger. `status:` stays `adopting`; the flip lands in the post-PASS docs PR (follow-up c).

### C4 views

No C4 impact. Checked against `model.c4`, `views.c4` and `spec.c4`: the actors/systems involved —
the registry host (`zotRegistry`), Better Stack (`betterstack`), GitHub Actions (`github`) and the
public issue reader (`publicReader`) — are modeled, and the edges already exist
(`zotRegistry -> betterstack` "Ships disk-state observability … as one SOLEUR_ZOT_DISK event",
`github -> betterstack` "Polls the SOLEUR_ZOT_DISK … for … follow-through soak probes",
`github -> publicReader`). No element, relationship, access boundary or embedded cardinality
changes. `bash plugins/soleur/test/c4-count-parity.test.sh` → `ALL TESTS PASSED` (2026-09-18).

### Sequencing

True for the probe at merge; true on the host at the replace. The ADR states the target state now;
the status flip is gated on the PASS.

## Guard Contract

### Guard 1 — probe delivery proof and authoritative verdicts

**Property.** The probe exits 0 or 1 only when an envelope-anchored row on the newest real boot
carries `err_redact_rev` ≥ 1 (or a tier-4 `suppressed` row) in the text before its first
` zot_last_err=`; and exits 1 only when a `fallback` row on that boot carries a header map or an
IP-valued `clientIP` in its tail.

**Assembly.** Four chokepoints in `scripts/followthroughs/zot-last-err-redact-7500.sh`: (1) the
`ENVELOPE` anchor filter — the only admission path for rows; (2) `NEWEST_BOOT` — the only boot
selector, excluding `unknown`; (3) the single awk pass — the only place the trusted-region cut and
the boot filter are applied, producing `TIER4_ROWS` and the `F` count; (4) the verdict chain — every
`exit` after the no-usable-boot guard is one of R1–R4. Nothing else may read `err_redact_rev` or
compute a boot filter.

**Mutation matrix.** Each must drive the named case RED:

| # | Mutation (design-derived) | Case → got |
|---|---|---|
| M1 | Remove `err_redact_rev` from the proof (suppressed only) | N1 → 3 |
| M2 | Read `F` from the whole row, not the head | N4 (forged in tail) → 0 |
| M3 | Read `F` across all rows in the window, not the newest boot | N5 (field on older boot only) → 0 |
| M4 | Accept `err_redact_rev=[0-9]+` | N7 (`=0`) → 0 |
| M5 | Require `suppressed` for R2 (FAIL) | N2 → 0 |
| M6 | Guard's own dispatch: force `DELIVERY_PROVEN=0` after computing it | N1, N2, case 1 → 3 (a guard that never proves is vacuous) |
| M7 | Second member after a compliant first: read `F` from the FIRST newest-boot row only | N9 (field only on the LAST newest-boot row) → 3 |
| M8 | Drop the `ENVELOPE` anchor | case 7 (foreign row carrying the token) → 0 |
| M9 | Accept `boot_id=unknown` as a boot | case 5 (`unknown` row carrying the token) → 0 |
| M10 | Derive `F` from `TIER4_ROWS` instead of all newest-boot rows | 3b → 3 |
| M11 | Revert `L` to `(headers|clientIP)[[:space:]]*[]=:{"]` | N11 (prose `invalid headers: …`) → 1 |

**Harness rows.**

- H1 (suite edit → RED): point the producer-token extraction at a non-existent key → the suite
  `FATAL`s before any case runs; it cannot pass on a hardcoded token.
- H2 (must-PASS, non-canonical, contract-permitted): N9 — the field present on only one of several
  newest-boot rows, not the canonical all-rows shape → PASS.

**Anchor.** Fixtures take the token from the producer's `LINE=` assignment, so weakening the key in
the probe requires a matching producer edit that Guard 2 pins independently; a producer rename
reddens this suite (H1), a producer value of `0` reddens N1 (PM4). `MIN_CASES` is paired with a
unique branch marker per case, so a substitution that keeps the count still fails on markers.

### Guard 2 — producer field pin

**Property.** Every `SOLEUR_ZOT_DISK` row the heartbeat POSTs carries `err_redact_rev=<integer ≥ 1>`
before its first ` zot_last_err=`.

**Assembly.** The single `LINE=` assignment (asserted unique) and its single `post()` — the emit
chokepoint every producer path flows through; the redaction suite captures at the POST.

**Mutation matrix.**

| # | Mutation | Assertion that reddens |
|---|---|---|
| PM1 | Delete the token from `LINE=` | structural + emit-level + panic must-PASS + boot-guard field list |
| PM2 | Move it after `zot_last_err=$ZOT_LAST_ERR` | structural order + emit-level `${out%% zot_last_err=*}` + boot-guard "LAST field" |
| PM3 | Add a second `LINE="SOLEUR_ZOT_DISK …"` assignment without the token | structural "exactly one assignment" |
| PM4 | Change the value to `0` | structural value class; probe harness N1 |
| PM5 | Replace the literal with `$ERR_REDACT_REV`, no assignment | emit-level ("NO row was emitted": `set -u` kills the heartbeat) |

**Harness rows.** (a) The existing dispatch self-test, verdict transcript, conservation and
`EXPECTED_MIN`/`MIN_ASSERTIONS` floors cover "0 checked"; if a new helper is introduced it joins the
`for _w in assert assert_emit` dispatch self-test. (b) Must-PASS non-canonical: the tier-1 panic
path carries the token.

**Anchor.** The probe harness consumes the producer's literal (Guard 1 H1/PM4), so the value
cannot be weakened in one file while the other stays green.

## Test Scenarios

### Probe harness — changed cases

- Case 3 (old-boot leaky + new-boot `regex` row, no proof): 2 → **3**, marker `lacks err_redact_rev`.
- Case 4 (single-boot leaky, no proof): 2 "NOT YET DELIVERED" → **3**, marker `lacks err_redact_rev`.
- Case 5 (`unknown` newest row): the `unknown` row now carries the producer token, so a mutation
  accepting `unknown` produces a real false close (M9); expected **3** (newest real boot has no proof).
- Case 7 (foreign marker-quoting row): the `foreign()` row now carries the producer token (the
  producer's own journald echo will); expected **3**; M8 yields 0.
- Case 9 (tier token spoofed in the tail): the new-boot row carries the field, so a successful spoof
  would PASS (0) while the correct reading is R1 (2, `DELIVERY PROVEN`).
- Cases 18/19 (drift, no proof, leaky / clean): stay **3**; marker `lacks err_redact_rev`; rows carry
  no field.
- All markers are unique to their branch (the no-usable-boot exit 3 and R4 both begin
  `CANNOT ESTABLISH:` — pin `lacks err_redact_rev` vs `no usable boot_id`).

### Probe harness — new cases (8 → 27 total)

- 3b: old-boot leaky + new-boot `regex` row carrying the field → 2, `DELIVERY PROVEN`.
- N1 field + clean `fallback`, no `suppressed` → 0 PASS, marker `proof: err_redact_rev`.
- N2 field + a clean `fallback` row followed by a leaking one, no `suppressed` → 1 FAIL.
- N4 field forged only in the untrusted tail → 3.
- N5 field on an older boot only; newest boot lacks it → 3.
- N7 `err_redact_rev=0` on the newest boot → 3.
- N9 field only on the LAST newest-boot row, earlier newest-boot rows lack it, clean → 0 PASS.
- N11 proven boot, `fallback` tail `level:error invalid headers: malformed request` → 0 PASS (prose
  is not structure); existing cases 10–12 keep proving that `headers:{…}` and `clientIP:10.…` are.

### Producer — heartbeat redaction suite (+3 → 36) and boot guard (+1 → 105 run)

- Structural: exactly one `LINE="SOLEUR_ZOT_DISK` assignment; it carries ` err_redact_rev=[1-9][0-9]* `
  before ` zot_last_err=`.
- Emit-level: suppressed (no-jq) path — the POSTed row's text before its first ` zot_last_err=`
  contains ` err_redact_rev=`.
- Must-PASS non-canonical: tier-1 panic path carries `err_redact_rev=`.
- Boot guard: `err_redact_rev=` in the field-presence loop.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `grep -cE 'zot_last_err_src=\$ZOT_ERR_SRC err_redact_rev=1 ' apps/web-platform/infra/cloud-init-registry.yml` = 1, and `grep -cF 'LINE="SOLEUR_ZOT_DISK' apps/web-platform/infra/cloud-init-registry.yml` = 1.
- [ ] `bash apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` → `RESULT: PASS (36/36 assertions)`; `bash apps/web-platform/infra/registry-boot-guard.test.sh` → `105 passed, 0 failed`.
- [ ] `bash scripts/followthroughs/zot-last-err-redact-7500.test.sh` → `27 passed, 0 failed, 27 cases`, `MIN_CASES=27` bound to a literal, FATAL wording contains `only %s cases ran`.
- [ ] The GREEN commit message records M1–M11, H1–H2 and PM1–PM5, each with the case/assertion and the observed result, measured against scratch copies of the real files (H2 records GREEN).
- [ ] `bash scripts/guard-vacuity-floor.test.sh` passes.
- [ ] `grep -nE 'BASELINE|DELIVERY HAS LANDED|unreachable by construction|delivery state UNKNOWN|Phase B cannot be in force|Phase B is inert|boot_id moved past|established independently \(boot_id\)|a replace necessarily produces a new one|!= baseline' scripts/followthroughs/zot-last-err-redact-7500.sh` returns nothing.
- [ ] `grep -nE 'echo .*\$\{?(DECODED|RAWOUT|ENVELOPE|TIER4_ROWS)' scripts/followthroughs/zot-last-err-redact-7500.sh` returns nothing (no row text on the public issue).
- [ ] Every `exit` after the no-usable-boot guard carries an `# R1`–`# R4` comment; `grep -c '^# PROOF KEY: err_redact_rev' scripts/followthroughs/zot-last-err-redact-7500.sh` = 1.
- [ ] Phase 3.4 recorded in the PR body: OLD and NEW `L` counts on the pre-Phase-B boot (NEW ≥ 1 and NEW == OLD) and on `78111e0e…` (both 0) — or an explicit "rows aged out" record.
- [ ] Live read-only probe run → `exit 3` whose message contains `lacks err_redact_rev` and `78111e0e`.
- [ ] `bash apps/web-platform/infra/registry-userdata-budget.sh --json` → `stored_bytes` ≤ 14,200 and `headroom` ≥ 18,500; `apps/web-platform/infra/registry-userdata-budget.test.sh` and the `cloud-init-user-data-size` test pass.
- [ ] ADR-211 carries the dated `err_redact_rev` subsection, the amended trigger and the post-PASS residual; `grep -c '^status: adopting' <ADR-211>` = 1.
- [ ] `issue-7960-body.md` exists, carries the `<!-- soleur:followthrough … -->` directive byte-identical to the live body (`diff` of the extracted line), and names `err_redact_rev` in its falsification condition.
- [ ] Follow-ups (a) and (b) exist and are OPEN (`gh issue view <N> --json state`).
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` → `ALL TESTS PASSED`.
- [ ] PR body uses `Ref #7960` (never `Closes`), states the merge → release + host-replace consequence, and records the operator's explicit authorization covering merge, re-fire and one recovery dispatch.

### Post-merge (automated in the same pipeline, no operator step)

- [ ] Follow-up (c) exists and is OPEN before the merge; `gh issue view 7960 --json body` shows the new body after it.
- [ ] The dispatched `apply-web-platform-infra.yml` run for this delivery concluded `success` and its log contains `zot store volume preserved (0 delete/forget)`.
- [ ] Two new-boot `SOLEUR_ZOT_DISK` rows show `state_status=running`, `ping_rc=0` and increasing `zot_uptime_s`.
- [ ] The local probe exits 0 with `proof: err_redact_rev`.
- [ ] After `gh workflow run scheduled-followthrough-sweeper.yml` completes, #7960's newest sweeper comment is a PASS and `gh issue view 7960 --json state` = `CLOSED`.
- [ ] The docs-only PR closing follow-up (c) is opened after the PASS.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed
**Assessment:** CTO confirmed the replace-on-merge path (`user_data` ForceNew, no `ignore_changes`;
dispatch fires on push to `main`) and the stale baseline; asked for an explicit `=0` case (N7) and
for every drift-as-proof comment to go with its branch (AC grep). #7158 verified textually
independent (its only hunk in the file is `keepTags`). Plan review then removed BASELINE outright
(see Plan Review Revisions).

### Legal

**Status:** reviewed
**Assessment:** CLO: no `/soleur:gdpr-gate` — the token is a constant with no personal data and no
new processing, recipient or egress. Legal-record updates are post-PASS only (follow-up c): dated
supersession entries in BOTH `knowledge-base/legal/article-30-register.md` cells carrying the
"INERT until the next registry-host-replace" bracket, and closing the `open_limbs` limb of the
2026-09-08 CLO attestation; cite by script name/constant. The public #7960 surface receives counts
only, never a raw `zot_last_err` value — especially on a FAIL (AC grep).

### Product/UX Gate

Not applicable — no user-facing surface; no file in the Files lists matches the UI-surface terms.

## Plan Review Revisions (2026-09-18)

Six-seat panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CTO
devex). Applied:

- **BASELINE deleted** (DHH, simplicity; reinforced by architecture's P3-refusal history and
  Kieran's finding that the on-baseline "not yet" text would be false on a Phase-B host). DHH's
  premise that the sweeper renders 2 and 3 identically was checked and is wrong
  (`sweep-followthroughs.sh`), but the deletion stands on the other grounds.
- **Leak structure tightened** (spec-flow P0): field-keyed proof makes exit 1 reachable on prose.
- **Replace path re-planned as refuse-then-re-fire** (architecture P0, Kieran P1): the merge starts a
  zot writer; authorization now covers re-fire and one recovery dispatch; the apply run is verified
  directly; pull-path health added; refusals get a pointer on #7960.
- **Forged-token witnesses** on cases 5 and 7 plus M8–M10 (Kieran P1/P2).
- Trimmed: per-path producer asserts (+6 → +3), mutation rows that re-proved existing behaviour,
  `mutation-results.md` (moved to the GREEN commit message), pre-merge rebaseline steps.
- Added: decision-table row comments and a PROOF KEY header line (CTO), a resume check (CTO),
  follow-up issues for the dispatcher wording and the post-PASS docs PR (architecture, spec-flow),
  a corrected Observability block (spec-flow: exit 1 never reopens; nothing re-grades after PASS).

Declined, with reasons in the Cut List: a PASS sample floor, a gate-hash tripwire, a new ADR for
the "token, not drift" principle. Taste items routed to `decision-challenges.md`.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Keep `BASELINE_AT_MERGE` re-scoped to split "not yet" (2) from "cannot establish" (3) | Its "not yet" is false on the current Phase-B host, stale after any convergence reboot, and meaningful only in a merge→replace window that has lasted 8 days; one R4 message naming the vehicle is true in every state. |
| Key on `SOLEUR_ZOT_LOG_BOOT` | Introduced by the log-shipper change (`07cf8ebcb`), not Phase B. |
| Control-plane proof from the dispatcher watermark | A green dispatcher can be "UNVERIFIED"; attests an apply, not what the host emits; needs `GH_TOKEN` under `env -i`. |
| Content hash of the template as a `templatefile` var | Cannot order revisions; touches `zot-registry.tf` and two budget stubs. |
| `suppressed` as the only key (status quo) | Sufficient but not necessary; #7960 cannot close by construction. |
| A `$ERR_REDACT_REV` variable instead of a literal | Under `set -u` a missing assignment kills the whole heartbeat. |

## Risks & Sharp Edges

- **The merge is irreversible production action** and destroys the only pull-path host. Mitigated
  by the explicit authorization, the existing preflight, the store-preserved assert, the direct
  recovery dispatch (5b), and the pull-path health check.
- **P3 refusal is the expected path**, not an edge case: the merge starts `web-platform-release.yml`.
  Between merge and the delivering replace, the daily sweep posts R4 (CANNOT ESTABLISH) whose text
  says this is expected until the replace completes. That is honest, and it is why the re-fire
  happens in-session rather than being left to chance.
- **A dispatcher "success" can be UNVERIFIED** (poll timeout, apply not identified). Verified from
  the apply run itself; a cancelled or missing apply is re-fired.
- **Concurrent infra merges** share `terraform-apply-web-platform-host`; a later pending apply can
  evict the dispatched one. Phase 5.5 watches the apply run and re-fires on `cancelled`.
- **All-`unknown` boot ids on the new host** would make the newest real boot the old one, so the
  probe reads R4 forever. Pre-existing producer regression class; the no-usable-boot guard only
  covers the all-rows case. Known, recorded.
- **Tier-4 absence after the replace** reads R1 (proven, not graded), not a failure; today's rate
  (265/24h) makes a long gap unlikely.
- **After PASS, nothing re-grades the warehouse stream.** Recorded in ADR-211 and User-Brand
  Impact; the producer suite and the Layer 2 sink scrub remain.
- **#7158** is a stale draft whose hunk is textually independent; if it merges first, re-run the
  budget script and rebase.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan
  or `/work`.
