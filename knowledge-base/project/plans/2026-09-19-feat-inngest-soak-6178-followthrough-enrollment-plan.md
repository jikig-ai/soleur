---
title: "feat(6178): enroll the ADR-100 Phase-4 soak in the follow-through sweeper"
date: 2026-09-19
slug: feat-inngest-soak-6178-followthrough-enrollment
branch: feat-one-shot-6178-soak-followthrough
issue: 6178
closes: none
type: feat
priority: p1
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
status: draft
lane: cross-domain
---

# feat(6178): enroll the ADR-100 Phase-4 soak in the follow-through sweeper

## Enhancement Summary

**Deepened on:** 2026-09-19
**Sections enhanced:** Research Reconciliation, Technical Considerations (request shape, exit contract, seams, output shape), Phase 2/3/7, Guard Contract, Observability, Dependencies & Risks
**Research agents used:** verify-the-negative (14 claims, all confirmed by grep/execution), git-history attribution (10 claims), security-sentinel, test-design-reviewer, observability-coverage-reviewer, architecture-strategist, pattern-recognition-specialist, learnings-researcher

### Key Improvements

1. **The 09-15 anchor class was misstated.** Run 34974655656 logged `anchor_source=floor(override)` and a `2.6 exactly-once VERIFIED (QUALIFIED)` verdict (population scoped to the 52 crons) — not an fsm-anchored proof. The probe output and the ADR addendum now inherit both qualifications verbatim, and the P2-a scope caveat (dedicated-host index only; not a web-host double-fire detector) is carried in the ACTION REQUIRED text with the second evidence the operator holds before flipping (web-1's quiesced shape).
2. **A registry-drift gate closes the last false-clean path.** A cron registered after 09-15 has a UUID outside the pinned population and would never be queried. One extra HMAC GET to `/hooks/inngest-registry-probe` (measured live: 200, `function_count=70`, all 52 population ids present) pins `REGISTRY_COUNT=70` and asserts population ⊆ registry; drift → exit 3 `registry_drift`.
3. **Two ★ mutation rows did not red the case they named** (row 19 used `false`, which does not exit without `-e`; row 4 depends on operand order). Rewritten with a `set -u` abort and a paired C5b/C5c assertion; C7 asserts the FATAL body verbatim so it cannot pass via `jq_failed`; the invariant helper and the negative-assertion helper get instrument self-tests; every harness run pins `INNGEST_SOAK_NOW_EPOCH` so no case measures the wall clock.
4. **A wrong HMAC returns HTTP 500 `Error occurred while evaluating hook rules.`**, measured live — not a 4xx. The `slice_unreadable` remedy and a new `cause=hmac_mismatch` classification reflect that; the body excerpt is classified (`body_class=`) and printable-filtered rather than dumped raw.
5. **Security ordering:** the xtrace refusal fires on `$-` with `${VAR:+x}` tests only (never `-n "$VAR"`), every host-supplied `functionID`/`startedAt` is shape-validated before it is printed on a public issue, and the population regex is `LC_ALL=C`-pinned inside the probe.

### New Considerations Discovered

- `workflow_dispatch --ref <branch>` runs the BRANCH's workflow YAML and sweeper, not main's; the dry run is acceptable (write-collaborator gated, `dry_run=true`, `contents: read`) but is preceded by a `git diff --quiet origin/main -- <sweeper files>` precondition so it exercises the production sweeper.
- The sweeper has no `sentry-heartbeat`; a sweep that never fires on 09-22 is invisible. Pre-existing, out of this PR's allowed edits — deferred as #8349.
- Three mechanisms are novel in the probe corpus and are declared as such in the header: the rc-filtering EXIT trap (14 probes trap EXIT for cleanup only; none rewrites `$?`), the `run_jq` helper with a `site=` token (per-site capture is precedented in 7922/8097; the helper is not), and the `remedy=` output key (0 precedents; siblings use prose tails).
- Modifications to existing cron files since SOAK_FROM (`cron-compound-promote.ts`, `cron-content-vendor-drift.ts`) did not add functions (registry 70 → 70); the registry gate, not a git-log heuristic, is the staleness canary.

## Overview

The ADR-100 dedicated-host cutover completed on 2026-09-15 and its seven-day exactly-once soak ends
at 2026-09-22T13:23:00Z. The soak is what flips ADR-100 from `adopting` to `accepted` and what
releases the four pre-cutover rollback snapshots, but nothing takes the day-7 reading except a
person remembering to dispatch `op=verify`. This plan builds the notify-only follow-through probe
the original Phase 4.1 prescribed and never delivered: a sweeper-run script that GETs the on-host
doublefire probe in population slices, buckets the runs the way `op=verify` 2.6 does, separates
the one already-explained catch-up bucket from anything new, and reports NOT YET / CANNOT
ESTABLISH / ACTION REQUIRED without ever closing the tracker itself. It enrolls #6178 with the
directive and label, adds the day-3.5 reading to ADR-100 as an addendum, and leaves the status
flip to the operator on the day-7 reading.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

PR body linkage: `Ref #6178` (never `Closes` — the tracker's close is the operator's decision on
the day-7 reading, and a `Closes` would auto-close it at merge, three days before the soak ends).

## Research Reconciliation — brief vs. codebase

Phase 0.6 premise validation, run 2026-09-19T03:00–03:40Z. Everything below was measured with a
command, not paraphrased.

| Brief claim | Reality (measured) | Plan response |
|---|---|---|
| "ADJACENT OPEN PR #8321 … read its diff so the new script conforms to the lints it introduces" | `gh pr view 8321 --json state,mergedAt` → `MERGED` at 2026-09-19T03:03:39Z. The branch was cut from `3e2a3b47e`, one commit behind; `git merge origin/main` (commit `61d82c336`) brought `scripts/lint-followthrough-varq-ban.sh` rule 3, `scripts/followthrough-predicate-parity.test.sh`, the fence-stripping `ship-soak-followthrough-gate.sh`, and the sweeper's `parse_directive` onto this branch. | The new script is written against the merged lints (§Technical Considerations → Lint conformance). The sweeper, its workflow, and the convention runbook are NOT edited — the brief's constraint stands and is now also unnecessary (no adjacent edit to collide with). |
| Archived plan at `…/plans/archive/2026-09-18-154358-2026-07-07-feat-extract-inngest-dedicated-host-plan.md` §"Soak follow-through (4.1)" (the brief's path) | No such archive path on `origin/main` or this branch. The plan is still live at `knowledge-base/project/plans/2026-07-07-feat-extract-inngest-dedicated-host-plan.md`; its line "**Soak follow-through (4.1):** `scripts/followthroughs/inngest-double-fire-6178.sh` exits 0 when no `(function_id, scheduled_tick)` group has > 1 run …" prescribed a PASS/FAIL (0/1) probe named `inngest-double-fire-6178.sh`. | Build `inngest-soak-6178.sh` (the brief's name) under the NOTIFY-ONLY vocabulary instead: the close authorises an ADR flip and a snapshot release, which is an operator decision (convention runbook §Author workflow, "trackers that must never be closed by a probe"). The 07-07 plan is not edited; the ADR addendum records the name and the vocabulary change. |
| "The 52 cron function UUIDs are in the run log of 34974655656 … and 35415585389" | Extracted with `gh run view <id> --log \| grep -oE 'function_ids=\[[0-9a-f,-]+\]' \| head -1`: 52 ids from each run, byte-identical sets, all UUID-shaped, no duplicates. `gh api repos/jikig-ai/soleur/actions/variables` → `total_count: 0`; the `CUTOVER_DOUBLEFIRE_FUNCTION_IDS` variable was deleted after each run (#6178 comment 5738682595 says so). | The population file's provenance header cites both run ids and the extraction command; the run log is the only durable source. |
| "the 7-day window for 52 crons is ≈1350 runs ≈ 14 pages, i.e. at the cap" | Read-only 5-slice GET this session (`doppler run -c prd_terraform`, from=2026-09-15T12:40:00Z, 11/11/11/11/8 ids in file order): HTTP 200 on every slice, 0–3 s each, 826 distinct runs at 2026-09-19T03:30Z (server `total_count` per slice = 15/547/12/47/205). Per-function density: one id at 260 runs (the `*/20` minter), five at 86–87 (hourlies), five at 14–21, the rest ≤ 7, and 22 of 52 with zero runs so far. | Slicing is by population, as the brief requires, but the layout is chosen from the measured density (§Technical Considerations → Slicing), not from the even-split estimate. The measured page rate (~0.5 s/page from the workstation) leaves the on-host 90 s deadline far away; the FATAL arm is still built because the deadline is the host's, not the client's. |
| "Reading taken 2026-09-19T02:40Z … 820 runs, 2 groups >1, BOTH in bucket 1491374" | Reproduced from the 03:30Z read with the op=verify jq: exactly two groups, `26e6836b-…` count=4 and `2e625d3c-…` count=2, both bucket 1491374 (= 2026-09-17T12:40:00Z–13:00:00Z, `date -u -d @$((1491374*1200))`). | The explained set is pinned as (functionID, bucket, max-count) triples, not as a bare bucket (§Technical Considerations → Explained set). |
| "SOAK_FROM=2026-09-15T12:40:00Z (anchor − 2 periods)" | Anchor 13:23:00Z − 2×1200 s = 12:43:00Z; the runs used `bucket_floor(anchor) − 2×period` = 13:20 − 40 min = 12:40:00Z (`doublefire_from()` in `scripts/cutover-inngest.sh`, and the run log's `from=2026-09-15T12:40:00Z`). | SOAK_FROM is pinned at 12:40:00Z with the bucket-floor derivation written next to it, so the day-7 window is a superset of the 09-15 and 09-19 windows. |
| "The soak started at the 2026-09-15 `op=verify` pass" (implicitly a full exactly-once proof) | `gh run view 34974655656 --log \| grep -oE 'anchor_source=[a-z()]+'` → `anchor_source=floor(override)`; the verdict line is `2.6 exactly-once VERIFIED (QUALIFIED) — no double-fire found, but this is NOT a full exactly-once proof: population scoped to function_ids=[…52 ids…]`. Per the runbook's trust ladder, `override` is the weakest anchor class. | The probe's output and the ADR addendum say the 09-15 pass was QUALIFIED (override anchor + scoped population) and that the day-7 reading inherits both qualifications; neither is presented as an fsm-anchored proof. ADR-146 (trust anchor) is cited. |
| "`op=resume` run 35223389582" | `gh run view 35223389582 --log \| grep -oE 'op=[a-z-]+'` → `op=resume` (×3), created 2026-09-17T12:50:04Z, success. PR #8252's body documents the 76-minute window but does not name the run id — the attribution comes from the run log and #6178 comment 5738682595. | Cite the run log, not the PR body, for the run id. |
| Registry membership of the population | Read-only GET `/hooks/inngest-registry-probe` (same HMAC/CF headers): HTTP 200, `{registry_empty:false, function_count:70, function_ids:[70]}`; all 52 population ids ⊆ registry (`comm -23` → 0). Registry was 70 on 09-15 and 09-19 too. | `REGISTRY_COUNT=70` is pinned; the probe GETs the registry once and refuses (`registry_drift`) on any other count or on a population id missing from it. |
| Four `inngest-cutover-pre-*` hcloud images 398857857, 406654994, 407991378, 411798619 | Read-only `GET /v1/images?type=snapshot` via `HCLOUD_TOKEN` from `prd_terraform`: all four present (06-18, 07-09, 07-13, 07-23; 23.0 + 26.9 + 8.9 + 23.8 GB). | The ACTION REQUIRED text names them verbatim; nothing in this plan deletes them. |
| `follow-through` label | `gh label list` → exists. | Applied at ship time with `gh issue edit 6178 --add-label follow-through`. |
| Doppler `prd_terraform` carries the three secrets | `doppler secrets --only-names -p soleur -c prd_terraform` lists `WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`; the sweeper workflow already forwards the same three names (its `env:` block, "#5875 canary-promotion-5875.sh"). | Local runs use `doppler run -p soleur -c prd_terraform --`; no workflow edit. |

Mechanism check against the ADR corpus (Phase 0.6 step 4): `grep -rlE 'follow-?through|sweeper'
knowledge-base/engineering/architecture/decisions/` hits ADR-030/031/033/046/052/077/081/082/096 —
all cite the sweeper as the standing mechanism; none rejects a notify-only probe. The follow-through
sweeper IS the repo's decided mechanism for time-gated closes (convention runbook §Trigger →
verification mapping, "Soak" row).

## Problem Statement

`op=verify` proved exactly-once on 2026-09-15 and again on 2026-09-19, but each reading was a
dispatch somebody remembered to make, with two repo variables set and then deleted by hand. The
soak's close criterion (seven days, zero double-fire outside the explained catch-up bucket) lives
in ADR-100 prose and an issue comment. The daily follow-through sweeper exists precisely so a
time-gated close is evaluated by a machine on the day it becomes evaluable; #6178 is not enrolled,
so on 2026-09-22 nothing fires. `ship`'s Soak-Gated Follow-Through Enrollment Gate would block
this very PR at `gh pr ready` for that reason (`.claude/hooks/ship-soak-followthrough-gate.sh`
denies when a soak signal names an open, unenrolled `Ref #N`).

## Proposed Solution

One notify-only probe, one exit-code harness, one committed population file, one issue-body
directive, one ADR addendum. No changes to the sweeper, its workflow, the convention runbook, any
`.tf`, `cloud-init*.yml`, or `hooks.json.tmpl`; no SSH; no destructive dispatch.

```text
sweeper (daily 18:00Z, from 2026-09-22 once earliest= has passed)
  └─ env -i PATH HOME WEBHOOK_DEPLOY_SECRET CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET
       scripts/followthroughs/inngest-soak-6178.sh
         ├─ read population file (52 ids, density-sorted) → 5 slices (round-robin, ≤11 ids)
         ├─ per slice: GET /hooks/inngest-doublefire-probe?from=SOAK_FROM&function_ids=<csv>
         │     200 + .runs array + no FATAL + total_count>0 + runs>0 + deduped>=total_count
         │     else → exit 3 CANNOT ESTABLISH naming the slice
         ├─ union → dedupe by run id → bucket (functionID, floor(startedAt/1200))
         ├─ groups>1 → split: explained (pinned triples) | unexplained
         └─ now < SOAK_END → exit 2 NOT YET (interim reading, unexplained listed loudly)
            now ≥ SOAK_END → exit 5 ACTION REQUIRED (flip+release+close | investigate)
```

The sweeper renders exit 2/3/5 as NOT YET / CANNOT ESTABLISH / ACTION REQUIRED in the comment
heading (`scripts/sweep-followthroughs.sh`, the static rc→word map in `run_one`), and never closes
on any of them. Closing #6178, flipping the ADR, and releasing the snapshots stay operator verbs.

## Technical Considerations

### Slicing (population, never time)

- The hook `inngest-doublefire-probe` in `apps/web-platform/infra/hooks.json.tmpl` forwards ONLY
  `from` and `function_ids` (`pass-environment-to-command` has two `url` sources). There is no
  `until`, so the window is open-topped and the only cost lever is the population.
- The on-host `apps/web-platform/infra/inngest-doublefire-probe.sh` aborts with a body beginning
  `inngest-doublefire-probe: FATAL …` on `deadline` (`PREFLIGHT_DEADLINE_S=90`), `window_too_wide`
  (page-1 `totalCount` vs `affordable_runs`), `page_ceiling`, transport exhaustion, and a
  non-array `.data.runs.edges`; it never emits a truncated run set. Any such body arrives with a
  non-200 (the hook has `include-command-output-in-response-on-error`), but the probe treats a
  `FATAL` substring as CANNOT ESTABLISH regardless of the status code, so a future 200-with-FATAL
  cannot read clean.
- Layout: the population file lists the 52 ids sorted by the measured 09-15→09-19 run count,
  heaviest first (ties by id). The probe computes `N_SLICES = ceil(52 / SLICE_MAX)` = 5 and deals
  line `i` (0-based) into slice `i mod 5` (`awk '(NR-1)%n==k'`, mawk-safe). Measured result of
  that dealing on the 03:30Z counts: slices of 11/11/10/10/10 ids carrying 369/123/112/111/111
  runs — the `*/20` minter and each hourly land in different slices, and every slice holds at
  least one hourly, so no slice can be empty at day 7. Forecast for the heaviest slice at day 7:
  ≈ 369 × 7 / 3.6 ≈ 720 runs ≈ 8 pages, under the ~14-page cap even at the runbook's pessimistic
  8 s/page; measured from the workstation the same slice took 3 s.
- `SLICE_MAX=11` and `POPULATION_SIZE=52` are pinned constants; a file with any other line count
  or any non-UUID line is CANNOT ESTABLISH (exit 3, "population file malformed"), so a truncated
  or edited file never yields a quietly-smaller population.
- Re-ordering the file is allowed only by re-measuring (the header says so); the sort IS the
  balancing lever and there is no hand-arranged grouping to drift.
- **Registry-drift gate (architecture F2).** The population is pinned to the 09-15 registry
  (70 functions, 52 crons). A cron registered after 09-15 would carry a UUID outside the file and
  its runs would never be queried — a false-clean path no per-slice gate can see. Before the
  slice loop the probe GETs `https://deploy.soleur.ai/hooks/inngest-registry-probe` (same HMAC +
  CF headers; `{registry_empty, function_count, function_ids}`; measured 2026-09-19: 200,
  `function_count=70`, all 52 ids present) and refuses with `reason=registry_drift
  function_count=<n> missing_from_registry=<k>` (exit 3) unless `function_count == REGISTRY_COUNT
  (70)` AND every population id ∈ `.function_ids`. A `git log` heuristic over
  `apps/web-platform/server/inngest/` was considered and rejected: two cron files were modified
  after SOAK_FROM without adding a function, so it would force CANNOT ESTABLISH forever.

### Request shape (copied from `canary-promotion-5875.sh` and the op=verify 2.6 arm)

```bash
SIG="$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_DEPLOY_SECRET" | sed 's/.*= //')"
code=$(curl --disable --noproxy '*' --proto '=https' -sS --max-time 120 -o "$body_file" -w '%{http_code}' -X GET \
  -H "X-Signature-256: sha256=$SIG" \
  -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
  -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
  "https://deploy.soleur.ai/hooks/inngest-doublefire-probe?from=${SOAK_FROM}&function_ids=${csv}")
curl_rc=$?
```

Branch on `curl_rc != 0` FIRST (`reason=slice_unreadable … curl_rc=<n>`), then on `code != 200`.
No `|| echo 000` after the substitution: curl already prints `000` via `-w` on a transport
failure, so the append would produce `code=000000` (measured by the review). `--proto '=https'`
follows `send-failed-alert-probe-8097.sh`, the corpus precedent for the `-o`/`-w` shape
(`canary-promotion-5875.sh` is the HMAC-over-empty-body precedent only).

**Host-supplied bytes are untrusted before they reach a public comment (security P1-2).** The
sweeper republishes stdout+stderr verbatim under the `github-actions` identity; its
`sanitize_probe_output` neutralises `<!--` and long backtick runs only. So after the `.runs` type
check and before ANY print, every run must satisfy `.id` string, `.functionID` matching the
strict UUID regex, and `.startedAt` matching `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$` (or null) —
otherwise `reason=slice_unreadable cause=bad_run_shape` (exit 3). Only validated tokens are ever
printed; the raw body excerpt is classified rather than dumped (see the `slice_unreadable` row).

Verified live this session (5 slices, all 200). Body to a file, code on stdout — the response can
exceed an argv-safe size (the on-host probe's own #6736 note), so the run set never passes through
a shell variable on its way to jq; each slice's `.runs` array is appended to a spool file and the
union is `jq -s '[.[][]]' spool > runs.json` (verified: two `{runs:[…]}` objects piped through
`jq -s '[.[].runs[]]'` yield both runs — `jq -s 'add'` on OBJECTS is a key-merge that keeps only
the LAST slice, the false-clean shape the review caught; never use `add` here). `SIG`, the secret, and the CF headers are never printed; the probe emits ids, buckets,
counts, and slice numbers only (AC-NOBODY).

### Bucketing and dedupe (byte-for-byte from `scripts/cutover-inngest.sh` op=verify 2.6)

```bash
jq -c '.runs |= (if length > 0 and all(.[]; (.id | type) == "string") then unique_by(.id) else ([ .[] | select(.startedAt == null) ] + ([ .[] | select(.startedAt != null) ] | unique_by([.functionID, .startedAt]))) end)'
jq -c --argjson period 1200 '[ .runs[] | select(.startedAt != null) | { fn: .functionID, bucket: ((.startedAt | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) / $period | floor) } ] | group_by([.fn, .bucket]) | map(select(length > 1)) | map({ functionID: .[0].fn, bucket: .[0].bucket, count: length })'
```

The null-`startedAt` exclusion is counted and printed, never silent (the 2.6 arm's rationale: a run
that has not started cannot be half of a double-fire; `fromdateiso8601` throws on null).

### Explained set

Pinned as triples, not as a bare bucket:

```bash
EXPLAINED='[{"functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","bucket":1491374,"count":4},
            {"functionID":"2e625d3c-0207-569f-b10b-567bc685ad5e","bucket":1491374,"count":2}]'
```

A group is explained iff its `(functionID, bucket, count)` EQUALS a triple — exact, not `<=`:
bucket 1491374 is historical and immutable (no run can acquire a past `startedAt`), so a count
of 5 for the minter would mean the burst plus one more run, which is precisely a double-fire
hiding under a cap (CTO finding B). A third function in bucket 1491374, or the minter at count
3 or 5, is UNEXPLAINED (a count BELOW the pin is not modelled as a separate "erosion" reason: it
renders as UNEXPLAINED → "investigate", which is not clean, and the window-head check below is
the retention canary — age-based erosion that removed 09-17 would have removed 09-15 first). Dedupe is by run id ONLY: a run lacking a string `.id` is
`reason=slice_unreadable` (exit 3) rather than the op=verify `(functionID, startedAt)` fallback,
because that fallback can shift counts and the explained pin is exact. The attribution string
printed beside the explained groups: "2026-09-17T12:40–13:00Z catch-up after the 76-minute
no-scheduler window (PR #8252, op=resume run 35223389582): cron-ghcr-token-minter (`*/20`) ×4 and
cron-anthropic-credit-probe (`47 * * * *`) ×2 = exactly the ticks each missed, each fired once on
resume — one scheduler draining its backlog, not two schedulers; recorded on #6178 comment
5738682595". Bucket indices are printed with their ISO window (`date -u -d @$((bucket*1200))`).

### Exit contract (notify-only; never 0, never 1)

| Condition | Exit | Sweeper heading | Output |
|---|---|---|---|
| `set -x` active AND any of the three credentials bound — tested as `case "$-" in *x*)` FIRST and then ONLY with `[ -n "${VAR:+x}" ]` (expands to a literal `x`); a `-n "$VAR"` test would itself print the value under `-x` before the refusal fires (security P1-1; the 7674 sibling's exact spelling) | 78 | TRANSIENT | `[FATAL] refusing to trace with a live credential set (see #7797)` |
| any credential unset/empty | 3 | CANNOT ESTABLISH | `reason=credentials_unprovisioned missing:<names>` |
| population file missing / not 52 UUID lines | 3 | CANNOT ESTABLISH | `reason=population_malformed` |
| `INNGEST_SOAK_NOW_EPOCH` set but not digits | 3 | CANNOT ESTABLISH | `reason=bad_now_override` |
| registry GET: curl rc≠0 / HTTP≠200 / shape not `{function_count:<int>, function_ids:[…]}` | 3 | CANNOT ESTABLISH | `reason=registry_unreadable curl_rc=<n> http=<code> body_class=<…> remedy=same as slice_unreadable` |
| registry: `function_count != 70` or any population id ∉ `function_ids` | 3 | CANNOT ESTABLISH | `reason=registry_drift function_count=<n> missing_from_registry=<k> remedy=a function was registered or removed since 09-15; the pinned population no longer covers the registry — do not flip; re-derive the cron population (gh workflow run cutover-inngest.yml -f op=registry-probe is read-only) and re-measure` |
| slice: curl rc≠0 / HTTP≠200 / `FATAL` in body / `.runs` not array / a run with a malformed `id`/`functionID`/`startedAt` | 3 | CANNOT ESTABLISH | `reason=slice_unreadable slice=<k>/<n> curl_rc=<n> http=<code> cause=<hmac_mismatch\|cf_access\|probe_fatal\|bad_run_shape\|transport\|other> body_class=<hook-rule-mismatch\|cf-access-html\|probe-fatal\|json\|other> body_len=<n> body=<probe-fatal only: the extracted reason=… pages_scanned=… tokens; otherwise the first 200 chars passed through LC_ALL=C tr -cd '[:print:]'> remedy=retry next sweep; hmac_mismatch = WEBHOOK_DEPLOY_SECRET rotated (shared with #5875); cf_access = the CF-Access pair; probe_fatal names the host's own reason and the slice to re-sort, and more than a week after day 7 it is the expected page-budget horizon, not a broken probe`. Measured live 2026-09-19: a wrong HMAC returns **HTTP 500** with body `Error occurred while evaluating hook rules.` (that is `hmac_mismatch`); only a bad CF pair returns a 4xx HTML page (`cf_access`) |
| slice: `total_count` is not a non-negative integer (the on-host probe emits the enum string `"unknown"` when page-1 `totalCount` did not parse — the scan never learned its own scale; bash `[[ unknown -gt 0 ]]` is silently 0, so the check is a regex, never an arithmetic test) | 3 | CANNOT ESTABLISH | `reason=total_count_unknown slice=<k>/<n> remedy=re-run next sweep; if it repeats: doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 24h --grep SOLEUR_INNGEST_PREFLIGHT_GATE --limit 20` |
| slice: `total_count == 0` or `runs == 0` | 3 | CANNOT ESTABLISH | `reason=slice_vacuous slice=<k>/<n> remedy=gh workflow run cutover-inngest.yml -f op=registry-probe (read-only) and compare its ids against scripts/followthroughs/inngest-soak-6178.function-ids.txt` |
| slice: deduped < total_count | 3 | CANNOT ESTABLISH | `reason=slice_incomplete slice=<k>/<n> deduped=<a> total_count=<b> remedy=re-run next sweep; if it repeats the host's pagination is truncating (same preflight-marker query)` |
| (folded into the row above as `cause=bad_run_shape`: a null `functionID` would merge different functions into one spurious group under `group_by`; a null `.id` defeats the dedupe) | 3 | CANNOT ESTABLISH | `… cause=bad_run_shape remedy=the host probe's projection changed; re-run, then compare its emitted shape against op=verify 2.6` |
| union: distinct runs < `RUN_FLOOR=800` | 3 | CANNOT ESTABLISH | `reason=population_thin runs=<n> remedy=re-run next sweep; if it repeats, the host's run index has a mid-window hole — read the SOLEUR_INNGEST_PREFLIGHT markers: doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 24h --grep SOLEUR_INNGEST_PREFLIGHT --limit 20`. Derivation: 826 distinct runs were measured at day 3.6, so the day-7 expectation is ≈1600; a floor at half the day-3.6 count catches a hole that lost more than half the window while tolerating any single cron's retirement. No active-function floor: 22 of 52 ids are legitimately at zero and any such floor is a guess about which weekly crons wake |
| union: `min(startedAt)` over all runs > SOAK_FROM + 2×1200 s (window-head coverage; measured 2026-09-19T03:30Z: global min = 2026-09-15T12:40:00.08Z = SOAK_FROM exactly, the minter's first tick) | 3 | CANNOT ESTABLISH | `reason=index_eroded min_started=<iso> remedy=the host's run index no longer reaches the window's head; any 09-15/16 double-fire would be gone too — do not flip; read the preflight markers (same betterstack-query line as population_thin)` |
| any jq/curl/date call site returns non-zero (a `startedAt` with a `+00:00` offset, a malformed body that slipped the shape guard), or a computed `bucket` is not `^[0-9]+$` before `date -u -d @$((bucket*1200))` (an arithmetic error would otherwise continue into the verdict — security P2-7) | 3 | CANNOT ESTABLISH | `reason=jq_failed rc=<n> site=<label>` — captured at EVERY call site; a failing pipeline never continues into a decision |
| any other exit reaches the EXIT trap (unbound variable under `set -u`, a stray `false`) | 3 | CANNOT ESTABLISH | `reason=unmapped_exit rc=<original>` — the trap allows only {2,3,5,78} through; everything else, INCLUDING 0 and 1, is rewritten to 3 (CTO finding D) |
| now < SOAK_END | 2 | NOT YET | interim reading: runs, slices, explained groups, UNEXPLAINED groups (if any: "investigate now, do not wait for day 7"), days elapsed |
| now ≥ SOAK_END, no unexplained group | 5 | ACTION REQUIRED | (every verdict row below and the NOT YET row above are PRECEDED by the same reading block: `window=<SOAK_FROM>..now slices=<n>/<n> runs=<distinct> active_fns=<m> null_started=<z> explained=<e> UNEXPLAINED=<u> days_elapsed=<d.d>`) |
| now ≥ SOAK_END, no unexplained group (continued; the verdict line and the scope caveat are the LAST two lines of output so they survive the sweeper's `tail -c 4000` — architecture F7) | 5 | ACTION REQUIRED | "SOAK CLEAN outside the explained bucket … dispatch the ADR-100 `adopting → accepted` flip PR, release the four `inngest-cutover-pre-*` hcloud images (398857857, 406654994, 407991378, 411798619), close #6178" |
| now ≥ SOAK_END, ≥1 unexplained group | 5 | ACTION REQUIRED | "SOAK NOT CLEAN … investigate the listed groups before flipping" + the groups |

Every exit-5 output (both arms) ends with these two lines, in this order, after the reading block
and the verbs: (1) `SCOPE: this reading is the dedicated host's (10.0.1.40) run index only — it is
NOT a web-host double-fire detector (op=verify P2-a); before flipping, hold web-1's quiesced shape
too: doppler run -p soleur -c prd_terraform -- bash scripts/inngest-host-state.sh` and (2) the
verdict line. The SOAK CLEAN verbs are ordered "flip ADR-100 → release the four snapshots → close
#6178 LAST" and say why: a notify-only probe never exits 1, so a group found after the close is
dropped by the closed-set path — closing last keeps the probe reporting until the destructive
verbs are done (architecture F3). The accepted P2-c residual is printed once: two runs of one
tick started more than 20 minutes apart land in different buckets and read clean (the host's
projection carries no `queuedAt`); the reading is a soak reading over the startedAt proxy, not a
complete exactly-once proof (architecture F4).

`set -uo pipefail` only — no `set -e` (an errexit abort exits 1 = the sweeper's FAIL verb, the
7674 sibling's header explains). No `${VAR:?}` anywhere (rule 1 of the varq-ban lint). Credential
absence is 3, not 2: for a notify-only probe "could not measure" is CANNOT ESTABLISH by definition,
and NOT YET must stay reserved for a measured reading.

The never-0/never-1 invariant is STRUCTURAL, not stylistic, and it has TWO layers because a
trap alone does not see a failing `jq`. Layer 1: EVERY jq/curl/date call whose output feeds a
decision goes through `run_jq()` / explicit `rc=$?` capture and exits 3 with
`reason=jq_failed rc=<n> site=<label>` on any non-zero status — under `set -uo pipefail` WITHOUT
`set -e`, `DUPES=$(… | jq …)` on a `startedAt` such as `2026-09-18T03:00:00+00:00`
(`fromdateiso8601` throws) sets `DUPES=""` and the script CONTINUES; `jq length` on empty input
prints nothing, `DUPE_COUNT` is empty, zero groups → a false SOAK CLEAN (measured by the review:
rc 0, `D=[]`). Layer 2: ONE `on_exit()` function, installed ONCE (`trap on_exit EXIT`) right after
`set -uo pipefail` with `WORK=""` pre-declared, that first removes `$WORK` (if set) and then reads
the saved `$?`, lets {2,3,5,78} through, and rewrites anything else to 3 with
`reason=unmapped_exit rc=<original>` — the backstop for a `set -u` abort or a stray `false`. Bash
keeps a SINGLE EXIT trap: a later `trap 'rm -rf "$WORK"' EXIT` would silently REPLACE the filter,
and a `set -u` abort would then exit 1 (= FAIL, and a reopen in closed mode). C23 (the `+00:00`
run) expects `reason=jq_failed`, and matrix row 19's `false` companion is what proves the trap. `set -u` aborts exit 1, `jq` runtime errors exit
5 (which the sweeper would render as ACTION REQUIRED), and `grep -q`/`jq -e` return 1 on
no-match — none of those may ever reach the sweeper as a verdict.

Anchor provenance (CTO finding F, corrected by the attribution pass; runbook §"Scan window +
trust anchor", ADR-146): `SOAK_FROM` is an `override`-class anchor — `bucket_floor(2026-09-15T13:23:00Z)
− 2×1200 s`, where 13:23:00Z is the 09-15 `op=verify` pass (run 34974655656). That pass was
ITSELF QUALIFIED: its log reads `anchor_source=floor(override)` and `2.6 exactly-once VERIFIED
(QUALIFIED) — … population scoped to function_ids=[…]`. The day-7 reading therefore inherits two
qualifications — an operator-typed anchor and a 52-cron population — and is a SOAK reading over
the post-verify window, not a re-proof of the coexistence region. The probe's output and the ADR
addendum both say so in one sentence, and the ACTION REQUIRED text reads "SOAK CLEAN (window
anchored on the 09-15 verify pass, run 34974655656, itself a QUALIFIED verdict: override anchor,
population scoped to these 52 crons)".

Horizon of the probe after day 7 (advisor finding 3, numbers corrected by review): the
open-topped window keeps growing at ≈102 runs/day in the heaviest slice. The host's page-1
feasibility gate refuses above `afford_pages × PAGE_SIZE` = (90 s / `PREFLIGHT_SEC_PER_PAGE`=5) × 100
= 1 800 runs (`apps/web-platform/infra/inngest-doublefire-probe.sh`), which the heaviest slice
reaches around 2026-10-03; the 90 s wall-clock deadline binds EARLIER only if the host pages
slower than 5 s/page (the runbook's 8 s/page observation would put it near 2026-09-27). The
ACTION REQUIRED text and the FATAL remedy both carry one sentence: "this reading stays takeable
for roughly one to two weeks after day 7; after that the heaviest slice outgrows the host's page
budget and the probe reports CANNOT ESTABLISH until #6178 is closed — that is expected, not a
broken probe".

Pagination on the host is CURSOR-based (`runs(first, after, …)` with `pageInfo.endCursor`,
`orderBy STARTED_AT ASC` — `apps/web-platform/infra/inngest-doublefire-probe.sh` `GQL_QUERY`), so
runs that start while a slice is being paged are appended after the cursor, never shifted past
it; `deduped >= total_count` (page-1 count) therefore holds on an open-topped window, exactly as
the op=verify 2.6 COMPLETENESS FLOOR relies on.

### Test seams (unreachable from a tracker body)

`INNGEST_SOAK_NOW_EPOCH` (validated as digits by one `[[ =~ ^[0-9]+$ ]]` line, else exit 3
`reason=bad_now_override` — needed because `[[ abc -lt N ]]` silently reads a non-numeric word as
0 and would render NOT YET; no dedicated harness case), `INNGEST_SOAK_POPULATION_FILE` (default
`$REPO_ROOT/scripts/followthroughs/inngest-soak-6178.function-ids.txt`; parsed with
`LC_ALL=C grep -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'` — the loose
`[0-9a-f-]{36}` would admit a line of dashes and a non-C collation drifts bracket ranges; the
count after `sort -u` must equal 52 — security P1-3), and a PATH-stubbed `curl`
(the URL is a pinned constant, never an env seam, so a local misconfiguration cannot redirect the
CF-Access headers to another host). The sweeper runs probes under `env -i` forwarding only the
directive's `secrets=` names, and its Guard 3 refuses a name absent from the workflow `env:` block,
so none of the seams is settable from an issue body. `openssl` stays real in tests (HMAC over an
empty body is deterministic and offline).

### Lint conformance (all merged with #8321 and now on this branch)

- `scripts/lint-followthrough-varq-ban.sh` rule 1 (no `${VAR:?}` on executable lines), rule 2 (the
  retired Sentry credential name appears nowhere under `scripts/followthroughs/`, comments
  included), rule 3 (every repo-relative path in a variable assignment must be git-tracked in the
  same checkout — the population-file default is tracked by this PR; the `*.test.sh` is skipped by
  rule 3's glob).
- `scripts/lint-orphan-test-suites.sh`: the suite must appear in `scripts/test-all.sh` as
  `run_suite "<label>" bash scripts/followthroughs/inngest-soak-6178.test.sh` (path in COMMAND
  position). Registered next to the 7674 line in the same shard.
- `scripts/lint-trap-tempfile-ownership.py` rule (c): every `mktemp` in the new files has an
  owning `trap … EXIT` in the same file.
- `scripts/followthrough-exec-bit.test.sh`: both new `.sh` files are `chmod +x`.
- `scripts/followthrough-predicate-parity.test.sh` and the fence rules: the directive is appended
  at column 0, outside any fence, in the canonical single-line form; the #6178 body has no fences
  today (`grep -c '^\`\`\`'` = 0), so appending cannot land inside one.
- `.claude/hooks/ship-soak-followthrough-gate.sh` (fires on `gh pr ready`): it reads `Ref #N` from
  the PR body + this plan (fences stripped) and requires each OPEN one to carry the label, an
  unfenced column-0 directive, and an on-disk `script=`. This plan therefore names only #6178 with
  the `Ref` keyword; every other tracker is cited as a bare `#N`.

## Files to Create

| Path | Purpose |
|---|---|
| `scripts/followthroughs/inngest-soak-6178.sh` | The notify-only probe (header: WHY, credential posture, anchor provenance, `RETIREMENT:` line listing the three files + the test-all.sh line, stating "delete no earlier than #6178's close + 14 days (the sweeper's closed-set lookback) or accept a daily `missing in repo HEAD` stderr line until then; the ADR addendum stays — it is history", EXIT CONTRACT with the never-0/never-1 statement, the xtrace refusal, then `set -uo pipefail`). |
| `scripts/followthroughs/inngest-soak-6178.test.sh` | Exit-code harness: PATH-stubbed curl that asserts argv and serves per-slice fixtures, `assert_never_close_verb` on every run, instrument self-test, anti-vacuity floor equal to the pass count, pass+fail==checks conservation. |
| `scripts/followthroughs/inngest-soak-6178.function-ids.txt` | 52 UUIDs, one per line, density-sorted; `#` provenance header (source runs 34974655656 + 35415585389, extraction command, the deleted repo variable, the 03:30Z per-id counts for the top six, the dealing rule, "reorder only by re-measuring"). |

## Files to Edit

| Path | Edit |
|---|---|
| `scripts/test-all.sh` | One `run_suite "scripts/inngest-soak-6178" bash scripts/followthroughs/inngest-soak-6178.test.sh` line with a two-line WHY comment, placed after the `inngest-host-not-serving-7674` registration. |
| `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` | Append `## Addendum — 2026-09-19 (#6178) — the soak reading at day 3.5 and what the day-7 probe measures` after the 2026-09-18 addendum. Frontmatter untouched (`status: adopting` stays). |
| GitHub issue #6178 (not a file) | At ship time: fetch the body with `gh issue view 6178 --json body --jq .body > body.md`, append two blank lines + the directive at column 0, `gh issue edit 6178 --body-file body.md --add-label follow-through`. Append only; the fetched body is diffed against the edited one before the edit (`diff` must show only added lines). |

Not edited, by decision: `scripts/sweep-followthroughs.sh`, `.github/workflows/scheduled-followthrough-sweeper.yml`,
`knowledge-base/engineering/operations/runbooks/followthrough-convention.md` (the three secrets are
already forwarded; #8321's edits are merged), `knowledge-base/project/plans/2026-07-07-feat-extract-inngest-dedicated-host-plan.md`
(historical), `apps/web-platform/infra/*` (constraint).

## Implementation Phases

### Phase 0 — preconditions (verify, do not assume)

- `git log --oneline -1 origin/main` shows `3ea78bd59` (#8321) as an ancestor of HEAD
  (`git merge-base --is-ancestor 3ea78bd59 HEAD`). Already true after the plan-time merge.
- `bash scripts/lint-followthrough-varq-ban.sh` is clean on the tree before any edit.
- `command -v jq curl openssl awk` all resolve; `jq --version` ≥ 1.6 (needs `fromdateiso8601`,
  `unique_by`, `group_by`).
- The three secrets resolve locally: `doppler run -p soleur -c prd_terraform -- bash -c 'for v in
  WEBHOOK_DEPLOY_SECRET CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET; do [[ -n "${!v}" ]] && echo
  "$v set"; done'` prints three lines (names only, never values).

### Phase 1 — population file

Regenerate from the run log (the durable source), sort by measured density, write the header:

```bash
gh run view 34974655656 --log | grep -oE 'function_ids=\[[0-9a-f,-]+\]' | head -1 \
  | sed 's/function_ids=\[//; s/\]//' | tr ',' '\n' | sort > /tmp/ids-a.txt
gh run view 35415585389 --log | grep -oE 'function_ids=\[[0-9a-f,-]+\]' | head -1 \
  | sed 's/function_ids=\[//; s/\]//' | tr ',' '\n' | sort > /tmp/ids-b.txt
diff /tmp/ids-a.txt /tmp/ids-b.txt && [[ "$(wc -l < /tmp/ids-a.txt)" == 52 ]]
```

Order: the density ranking measured at plan time (this plan's Research Insights carry the
ranked list). The file is exactly: header comment lines, then 52 UUID lines, heaviest first.
Verification: `grep -vE '^\s*(#|$)' <file> | grep -cE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'` = 52
and `sort -u` count = 52 and the set equals `/tmp/ids-a.txt`.

### Phase 2 — RED: the harness first

Write `inngest-soak-6178.test.sh` mirroring `inngest-host-not-serving-7674.test.sh` (helpers,
instrument self-test, floor keyed on `passes`, conservation check) and the curl stub from
`send-failed-alert-probe-8097.test.sh` (honours `-o <file>` and `-w '%{http_code}'`, logs argv to
`calls.log`). The stub additionally: exits 64 unless argv carries `-X GET`, `X-Signature-256: sha256=`,
`CF-Access-Client-Id:`, `CF-Access-Client-Secret:`, and the URL prefix
`https://deploy.soleur.ai/hooks/inngest-doublefire-probe?from=2026-09-15T12:40:00Z&function_ids=`;
exits 64 if the `function_ids` CSV holds more than 11 ids; serves `$FIX/slice-<k>.json` with
`$FIX/slice-<k>.code` (default 200) by call ordinal; honours `$FIX/curl.rc` for a transport failure.
`run()` ALWAYS exports `INNGEST_SOAK_NOW_EPOCH` (default `1790000000`, before SOAK_END) so no case
reads the wall clock (cq-ac-must-not-depend-on-concurrent-sessions — after 09-22 an unpinned run
would silently flip 2→5 and still pass); it resets `calls.log` and the stub's ordinal counter
before every invocation, and it is the ONLY launcher — C13's `bash -x` goes through `run()` too,
so `assert_never_close_verb` is reached for rc 78 and for the trap arm. Two fixture helpers:
`slice_fixture <k> <ids...>` and `append_runs <k> <json-array>` (extra runs may carry any
functionID; the probe has no foreign-id check) plus a `--no-window-head` flag for C5e.
`slice_fixture` emits `{runs:[…], total_count:N}` with one run per (id, hourly tick) over the
PINNED default window 2026-09-18T00:00Z–16:00Z, with `startedAt` precision MIXED on every run
(none / `.08Z` / `.101119Z` — the measured global minimum is `12:40:00.08Z` and vendor rows carry
microseconds), so the `sub()` regex is exercised permanently rather than by a hand-run variant (away from bucket
1491374, so the explained triples are the ONLY runs in that bucket), run ids ULID-shaped and
unique, and `total_count` = the DISTINCT-id count of the runs it emits (so a deliberately
duplicated row — C11 — stays complete: `deduped == total_count`); C10 passes an explicit
`total_count` override (9 over 5 distinct runs) to reach `slice_incomplete`. Every default slice
is non-vacuous and complete, the union exceeds `RUN_FLOOR` (16 ticks × 52 ids = 832 runs), and
it carries one run at 2026-09-15T12:40:00Z for window-head coverage. Cases (each drives a distinct RED when the probe is mutated — see Guard
Contract):

- H1 instrument self-test drives BOTH verdict helpers (`expect` and `expect_absent`) to a
  guaranteed mismatch and requires `fails` to move by exactly 1 each; H2 stub refuses argv without
  the signature header; H3 `assert_never_close_verb 0 SELFTEST 2>/dev/null` must move `fails` by
  exactly 1 (rolled back; then `pass "INSTRUMENT: invariant fires on rc 0"`) — without H3 a harness
  edit deleting the invariant call from `run()` leaves everything green.
- C1 clean, now < SOAK_END → 2, output has `NOT YET` and `interim`.
- C2 clean, now = SOAK_END → 5, output has `SOAK CLEAN`, `adopting`, `398857857`, `411798619`, `close #6178`, `QUALIFIED`, `NOT a web-host double-fire detector`, the reading block (`runs=`, `slices=5/5`), and NOT `investigate`; the LAST line of output is the verdict line and the second-to-last is the `SCOPE:` line (asserted on `tail -n 2`), and both survive `tail -c 4000`.
- C3 exactly the two explained groups, now ≥ SOAK_END → 5 clean; output names the bucket as `explained` and NOT `UNEXPLAINED`.
- C4 explained + one group in bucket 1491375 → 5 with `investigate` and the unexplained id + bucket; explained still listed separately.
- C4b same as C4 but now < SOAK_END → 2, output still has `UNEXPLAINED` and `investigate now`.
- C5 a third function in bucket 1491374 → unexplained. C5b the minter at count 5 → unexplained.
- C6 slice 3 HTTP 500 with a JSON body → 3, output has `slice=3/5` and `cause=other`. C6b slice 3
  HTTP 500 with body `Error occurred while evaluating hook rules.` → 3 with `cause=hmac_mismatch`.
  C6c slice 3 HTTP 403 with an HTML body → 3 with `cause=cf_access` and NO `<` character in the
  output. C7 slice 2 HTTP 200 with body `inngest-doublefire-probe: FATAL preflight scan aborted
  reason=deadline pages_scanned=14 …` → 3 with `reason=slice_unreadable`, `cause=probe_fatal`,
  `slice=2/5`, and the extracted `reason=deadline pages_scanned=14` tokens — asserting
  `slice_unreadable` (not merely rc 3) is what stops a deleted FATAL check from passing via
  `jq_failed`; the FATAL check precedes any jq parse.
- C0 registry: the stub serves `registry.json` (`function_count:70`, the 52 ids + 18 others) for
  the first call; C0b `function_count:71` → 3 `registry_drift`; C0c one population id missing
  from `function_ids` → 3 `registry_drift missing_from_registry=1`; C0d registry HTTP 500 → 3
  `registry_unreadable` and `calls.log` shows no slice request.
- C8 slice 4 `{"runs":null,"total_count":7}` → 3. C9 slice 1 `{"runs":[],"total_count":0}` → 3 `slice_vacuous`. C10 slice 5 deduped 5 < total_count 9 → 3 `slice_incomplete`.
- C11 one run repeated on two "pages" (same id twice) → rc 2 with `explained=0 UNEXPLAINED=0`
  (no group). C12 a null-startedAt run → rc 2, `null_started=1`, `UNEXPLAINED=0`. C12b a run with
  `functionID: "not-a-uuid"` → 3 `bad_run_shape`; C12c a run with `startedAt: "2026-09-18 03:00"`
  (no `T`/`Z`) → 3 `bad_run_shape`.
- C13 `bash -x` with `WEBHOOK_DEPLOY_SECRET` set → 78. C14 `CF_ACCESS_CLIENT_SECRET` empty → 3 `credentials_unprovisioned`, and the stub's `calls.log` is empty (no request was made).
- C15 chunking: `calls.log` has exactly 5 requests, every request carries ≤ 11 ids, the union of
  the requested ids equals the 52-line population, and every request is pinned to
  `from=2026-09-15T12:40:00Z` (slice sizes are NOT pinned — the dealer is an implementation
  detail; the property is complete coverage under the cap).
- C16 population file with 51 lines → 3 `population_malformed`, no request made. C17 `curl.rc`=7 → 3.
- C18 slice 2 with one run lacking `.id` → 3 `bad_run_shape`; C18b one run with `functionID: null`
  → 3 `bad_run_shape`. C9b slice 1 with `total_count: "unknown"` and 40 runs → 3
  `total_count_unknown` (not `slice_vacuous`).
- C23 a run with `startedAt: "2026-09-18T03:00:00+00:00"` (offset form; `fromdateiso8601` throws,
  jq exits 5) → rc 3 with `reason=jq_failed` — proves a failing jq cannot fall through to a clean
  verdict and that rc 5 never escapes as ACTION REQUIRED. C20 all five slices valid but only 300
  runs in total → 3 `population_thin`.
- C22 the population file contains a `#`-prefixed `total_count` measurement line and blank lines
  between header and ids → still parsed as 52 ids (the header grammar is a must-PASS variant).
- C5c the minter at count 3 in bucket 1491374 → 5 with `UNEXPLAINED` (below the pin is not clean
  and not a bespoke reason) — C5b and C5c are asserted as a PAIR because a `==`→`<=` mutation reds
  only one of them depending on operand order; C5e a fixture whose earliest `startedAt` is 2026-09-16 → 3
  `index_eroded` (window-head coverage).
- Default fixtures include one run at 2026-09-15T12:40:00Z (the measured global minimum) for
  window-head coverage; the explained triples appear only in the cases that name them.
- Fixture density: each default slice fixture carries 16 hourly ticks per id, so the union is
  832 distinct runs — above `RUN_FLOOR` with no group.
- INVARIANT: `assert_never_close_verb` after every run (inside `run()`); FLOOR = the measured pass count; `passes + fails == checks`.
- The "real endpoint via doppler run" scenario is Phase 6 / AC10, not a harness case.

Run it against an absent probe: it must FATAL at "probe not found" (exit 1) — that is the RED.

### Phase 3 — GREEN: the probe

Write `inngest-soak-6178.sh` to the §Technical Considerations contract. The header declares the
three corpus-novel mechanisms as such (pattern review): the rc-filtering EXIT trap ("no
precedent; 14 probes trap EXIT for cleanup only and `git-data-rung2-evidence-capture.sh` reads
`$?` without rewriting"), the `run_jq` helper with `site=` (per-site capture is precedented by
7922's `|| cannot_establish` and 8097's `if ! x=$(…)`; the helper is not), and the `remedy=`
output key (0 precedents; 7922/7674 use prose tails). Keep 7922's `WHY -uo AND NOT -euo`
sub-heading verbatim. The trap is EXIT-only (an INT/TERM arm would rewrite a signal kill to 3).
Structure: header →
xtrace refusal → `set -uo pipefail` → `WORK=""` + `trap on_exit EXIT` (the ONLY trap in the
file: cleanup + rc filter) → constants → seams → credential check → population parse → registry GET + drift gate →
slice loop (spool file)
→ dedupe/bucket jq → explained split → date branch → exit. `mktemp -d` assigned to `WORK`
(rule (c) of the trap lint is satisfied by the single trap). `chmod +x`. Run the suite to green; then apply the INVARIANT rows
of the mutation matrix (those marked ★) by hand, one at a time, confirming each reds and
reverting; the remaining rows are covered by harness cases and are not hand-run.

### Phase 4 — register and lint

Add the `run_suite` line to `scripts/test-all.sh`; run `bash scripts/lint-orphan-test-suites.sh`,
`bash scripts/lint-followthrough-varq-ban.sh`, `bash scripts/followthrough-exec-bit.test.sh`,
`python3 scripts/lint-trap-tempfile-ownership.py` (the same invocation CI uses — read its
`--help` first), and `bash scripts/followthrough-predicate-parity.test.sh` (untouched by this PR,
must stay green).

### Phase 5 — ADR-100 addendum

Append after the 2026-09-18 addendum, matching the heading grammar of the last five
(`## Addendum — YYYY-MM-DD (#N) — <claim>`). Content, in this order: the day-3.5 reading (run
35415585389, 820 runs, the two groups, bucket 1491374 = 12:40–13:00Z 09-17); the attribution
(PR #8252's 76-minute no-scheduler window, `op=resume` run 35223389582, routine_runs shows each
missed tick fired once); why the startedAt-bucket proxy flags it (Decision 7 buckets by start
instant, so a backlog drained in one burst places several ticks' runs in one bucket — the proxy
cannot distinguish catch-up from double-fire, only attribution against routine_runs can); this
session's 03:30Z re-read (826 runs, same two groups); what the day-7 probe measures (population
slices, same bucketing, explained triples pinned, notify-only exit 5 that names the flip, the four
snapshot ids, and the close as OPERATOR verbs); the anchor provenance (`from` = bucket_floor(09-15 verify pass) − 2 periods; run 34974655656
was itself `anchor_source=floor(override)` and `VERIFIED (QUALIFIED)` with the population scoped
to these 52 crons — cite ADR-146; the day-7 reading inherits both qualifications and is a soak
reading, not a re-proof); the framing that the explained set is an operator-attributed,
immutable, historical EXCEPTION to Decision 7's bucket criterion — the proxy over-approximates
(a backlog drain violates the criterion without violating exactly-once) and the flip condition
is "the criterion holds outside that one bucket" (architecture F6); the P2-a scope sentence
(dedicated-host index only; web-1's quiesced shape is the second evidence) and the P2-c
residual (two runs of one tick started >20 min apart read clean); the registry pin (70
functions on 09-15, 09-19, and at probe time, else `registry_drift`); the premature-close
hazard and the close-LAST ordering (a notify-only probe drops a group found after the close);
and the sentence that the status stays `adopting` until the day-7 reading is clean outside the
explained set. Say "replaces the 07-07 plan's prescription", not "supersedes" (that word is
reserved for addenda superseding addenda in this ADR). The 07-07 plan's `inngest-double-fire-6178.sh`
PASS/FAIL prescription is recorded as superseded by the notify-only form and why. Do not touch
the frontmatter. `python3 scripts/lint-infra-no-human-steps.py <ADR path>` must stay OK.

### Phase 6 — live interim reading (read-only; the "script reaches the probe" verification)

```bash
doppler run -p soleur -c prd_terraform -- bash -c '
  env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME="$HOME" \
    WEBHOOK_DEPLOY_SECRET="$WEBHOOK_DEPLOY_SECRET" CF_ACCESS_CLIENT_ID="$CF_ACCESS_CLIENT_ID" \
    CF_ACCESS_CLIENT_SECRET="$CF_ACCESS_CLIENT_SECRET" \
    scripts/followthroughs/inngest-soak-6178.sh; echo "rc=$?"'
```

Expected: `rc=2`, five slices each 200 and non-vacuous, ≥ 826 distinct runs, exactly the two
explained groups, zero UNEXPLAINED. This is the sweeper's own `env -i` shape, so it exercises the
FHS PATH and the absence of every other variable. Record the per-slice `total_count` line in the
population file's header as "measured at <UTC>" — that is the day-7 feasibility evidence.

### Phase 7 — enrollment at ship time (before `gh pr ready`, after the branch is pushed)

1. `gh issue view 6178 --json body --jq .body > "$W/body.md"`; `cp "$W/body.md" "$W/body.orig.md"`.
2. `printf '\n\n<!-- soleur:followthrough script=scripts/followthroughs/inngest-soak-6178.sh earliest=2026-09-22T13:23:00Z secrets=WEBHOOK_DEPLOY_SECRET,CF_ACCESS_CLIENT_ID,CF_ACCESS_CLIENT_SECRET -->\n' >> "$W/body.md"`.
3. `diff "$W/body.orig.md" "$W/body.md"` shows only `>` lines (append, never rewrite).
4. Immediately re-fetch: `gh issue view 6178 --json body --jq .body > "$W/body.live.md"`;
   `cmp "$W/body.orig.md" "$W/body.live.md"` must be byte-equal, else ABORT and restart from
   step 1 — `gh issue edit --body-file` is a blind full-body PUT and a concurrent edit (triage
   bot, operator) between view and edit would be overwritten; the re-fetch shrinks that window
   from the whole session to one round-trip (it does not close it — the parser readback and the
   dry-run dispatch below are the actual evidence of enrollment). Then
   `gh issue edit 6178 --body-file "$W/body.md" --add-label follow-through`.
5. Readback (GitHub normalises trailing whitespace on a body PUT, so no byte-equality): the live
   body's LAST non-blank line is the directive
   (`gh issue view 6178 --json body --jq .body | grep -v '^\s*$' | tail -1 | grep -c '^<!-- soleur:followthrough script=scripts/followthroughs/inngest-soak-6178.sh '` = 1);
   `... --jq '[.labels[].name]' | grep -c follow-through` = 1; and the body passes the sweeper's
   own parser: `gh issue view 6178 --json body --jq .body | (source scripts/sweep-followthroughs.sh >/dev/null 2>&1; parse_directive)`
   prints `script scripts/followthroughs/inngest-soak-6178.sh`, `earliest 2026-09-22T13:23:00Z`,
   and the `secrets` line (the same source-then-call shape `followthrough-predicate-parity.test.sh` uses).
6. Dry-run dispatch on the branch ref. `workflow_dispatch --ref <branch>` runs the BRANCH's
   workflow YAML and the branch's `scripts/sweep-followthroughs.sh` with every secret in the
   workflow `env:` (security P2-5) — acceptable here (write-collaborator gated, `contents: read`,
   `dry_run=true` suppresses comments) and it also executes every OTHER enrolled probe past its
   `earliest`. Precondition so the run exercises the production sweeper:
   `git diff --quiet origin/main -- .github/workflows/scheduled-followthrough-sweeper.yml scripts/sweep-followthroughs.sh`
   (exit 0). Then: `gh workflow run scheduled-followthrough-sweeper.yml --ref feat-one-shot-6178-soak-followthrough -f dry_run=true`,
   then `gh run watch` and `gh run view <id> --log | grep 'issue #6178'` must show
   `directive found (script=scripts/followthroughs/inngest-soak-6178.sh earliest=2026-09-22T13:23:00Z secrets=WEBHOOK_DEPLOY_SECRET,CF_ACCESS_CLIENT_ID,CF_ACCESS_CLIENT_SECRET)`
   followed by `earliest=2026-09-22T13:23:00Z not yet reached … — skipping`, and NO `not executable`,
   `refused`, or `INSIDE A CODE FENCE` line. The earliest gate sits before the probe exec and before
   Guard 3 in `run_one`, so the dry run proves directive parse + path canonicalisation + exec bit;
   Phase 6 is what proves the probe reaches the host. Both are required.
7. The daily 18:00Z sweep between enrollment and merge logs
   `issue #6178: script 'scripts/followthroughs/inngest-soak-6178.sh' missing in repo HEAD — leaving issue open`
   on stderr only (no comment, run stays green — `run_one` in `scripts/sweep-followthroughs.sh`)
   if it runs before the merge lands; the PR merges in the same session, so the window is
   minutes. If ship slips past 2026-09-22T13:23Z the earliest gate is already open and the
   dry-run dispatch EXECUTES the probe: the expected log is then
   `issue #6178: scripts/followthroughs/inngest-soak-6178.sh exit=<2|3|5>` followed by
   `DRY_RUN — would comment with verdict=<word>`, not `not yet reached`.

## Research Insights

### Premise Validation (Phase 0.6)

Checked by command: #6178 OPEN (labels enhancement/priority/p1-high/type/chore/domain/engineering,
no `follow-through`, no directive, no fences in the body, 38 lines); PR #8252 MERGED 2026-09-17T21:01:57Z;
PR #8321 MERGED 2026-09-19T03:03:39Z (stale "OPEN" premise — see Research Reconciliation); the
archived-plan path is stale (plan still live at its original path); ADR-100 `status: adopting`,
last addendum 2026-09-18 (#7695); the 52 ids identical across both run logs; no repo/environment
variable holds them; the four hcloud snapshot ids exist; the `follow-through` label exists; the
three secrets exist in Doppler `prd_terraform` and in the sweeper workflow `env:`.

### Property List (Phase 0.6b)

1. On the first sweep at or after 2026-09-22T13:23:00Z, a machine reads the dedicated host's cron
   runs over the whole soak window and posts a heading the operator can act on, without any human
   remembering.
2. A reading that examined nothing, or examined part of the population, can never render as clean.
3. The 2026-09-17 catch-up bucket, and only that bucket at EXACTLY its recorded counts (minter
   4, credit-probe 2), is reported as explained; any other group — including those two functions
   at any other count in that bucket — is reported as unexplained.
4. The probe never closes #6178, never reopens it, and never prints a credential.
5. The action the operator must take is named in the probe's output, including the four snapshot
   ids, so no dashboard read is needed.
6. ADR-100 records the day-3.5 reading and its attribution, and stays `adopting`.

### Cut List (Phase 0.6b)

- Adaptive bisection of a slice on a FATAL response → property 2 → cut: the density-sorted
  round-robin layout keeps the heaviest slice at ≈8 pages by measurement, and a FATAL already
  names the slice; a re-sort PR is the remedy.
- A `CUTOVER_*` repo-variable round-trip (set, dispatch `op=verify`, delete) driven by the probe →
  property 1 → cut: the deploy webhook is reachable directly with the three already-forwarded
  secrets, and `op=verify` would also run the P2-16 missed-tick enumeration and other arms the
  soak reading does not need.
- Editing the sweeper workflow to add secrets → cut: the three names are already in its `env:`.
- Reusing `inngest-doublefire-reading-6617.sh` (operator-typed `RESULT:` verdict) → property 1 →
  cut: it reads a human verdict; this probe must take the reading itself.
- A per-verdict comment dedup in the sweeper → cut: convention says an indefinite-horizon probe
  belongs in a drift workflow; this probe's horizon is the operator's action within days.
- (plan-review) An ADR-`status:` self-quieting arm → no property → cut: the operator's close
  already quiets the probe (closed mode is silent on 2/3/5).
- (plan-review) A `foreign_function_id` subset check → no property → cut: a hook that drops the
  filter either FATALs (already 3) or returns a complete population five times (a correct reading).
- (plan-review) `ACTIVE_FLOOR` → property 2 already covered by `RUN_FLOOR` + per-slice gates →
  cut: 22 of 52 ids are legitimately at zero.
- (plan-review) REQUIRED presence of the explained triples → property 2 already covered by the
  window-head check → cut; below-pin renders UNEXPLAINED.

### Files and anchors

- `scripts/sweep-followthroughs.sh` — `run_one` (earliest gate before exec; `env -i` allowlist;
  rc→word map `2) verdict="NOT YET"` / `3) "CANNOT ESTABLISH"` / `5) "ACTION REQUIRED"`; closed
  mode: only rc 1 reopens); `parse_directive` (fence-aware, column-0 anchor).
- `.github/workflows/scheduled-followthrough-sweeper.yml` — `dry_run` input; the three secrets
  under "#5875 canary-promotion-5875.sh".
- `scripts/followthroughs/canary-promotion-5875.sh` — HMAC-over-empty-body GET shape.
- `scripts/followthroughs/inngest-host-not-serving-7674.sh` / `.test.sh` — header grammar,
  xtrace refusal, `passes`-keyed floor, conservation check, stub that asserts argv.
- `scripts/followthroughs/ccla-representative-icla-7922.sh` / `.test.sh` — first notify-only probe;
  `assert_never_close_verb` (fails on rc 0 or 1) applied after every run.
- `scripts/followthroughs/send-failed-alert-probe-8097.test.sh` — PATH-stubbed curl honouring
  `-o`/`-w` and logging argv.
- `scripts/cutover-inngest.sh` — op=verify 2.6: retry loop, `.runs` shape guard, dedupe, null
  startedAt notice, VACUOUS and INCOMPLETE gates, DUPES jq, verdict qualifiers.
- `apps/web-platform/infra/inngest-doublefire-probe.sh` — FATAL arms, `total_count` emission,
  `{runs, total_count}` body; `apps/web-platform/infra/hooks.json.tmpl` — the hook's two `url`
  params.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` §"Scan window + trust anchor".
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` §Author workflow
  (notify-only sub-vocabulary, RETIREMENT line, credential posture, varq ban), §"Enrolling on a
  PRE-EXISTING issue".
- `scripts/lint-followthrough-varq-ban.sh` rules 1–3; `scripts/lint-orphan-test-suites.sh`
  (`run_suite … bash <path>.test.sh` extraction); `scripts/lint-trap-tempfile-ownership.py` rule (c).
- `plugins/soleur/skills/ship/SKILL.md` §"Soak-Gated Follow-Through Enrollment Gate" and
  `.claude/hooks/ship-soak-followthrough-gate.sh` (`Ref|Tracks #N` extraction; fence-stripped
  enrollment check).

### Measured density ranking (2026-09-15T12:40Z → 2026-09-19T03:30Z, read-only)

Runs per id, descending — this is the population file's line order (ties by id):
26e6836b-97ad-503f-8b08-490d8a2f4ce8 260; 11bb44a3-ae8d-57b0-8d41-e76e57f0277a 86;
2e625d3c-0207-569f-b10b-567bc685ad5e 87; 4b7b1e68-aaab-52f8-843e-8f0741dd93cc 87;
6b2bdeb4-142e-5375-bfaa-74b2ea2d6bfc 87; fe1a4bd6-8d09-5882-955f-77fd72ed5c50 87;
d5cb880f-edd2-5338-abd8-6d088825a9d9 21; 08e8a43f-dda0-50ad-adc8-ebefe1ecc850 14;
0a7dd3fa-8416-5f14-a873-3efb1507a515 14; 8e71b0c6-8505-5320-8d17-c4c2533898f0 14;
a16fe7ce-33a7-5c17-b30b-20f7dead3e72 14; 209d5706-72bd-561c-88dc-92d7e23c1849 7;
e6cf7aa2-9e11-52ac-b375-8f0983ccea20 4; then thirteen ids at 3 (080d1cfc, 2d7430ac, 336185fc,
4241e23a, 5af2e6bd, 5c666c87, 7478e515, 821230d0, 8fb2368b, 96fed0d0, 9d6047b9, f266f0c9,
f3fd1789), 9a26ac57 at 2, three at 1 (10223fd3, 24c8ec31, 2db4c67d), and 22 at 0. Sort key:
`-count, id` (the four 87s sort by id after the 86: 2e625d3c, 4b7b1e68, 6b2bdeb4, fe1a4bd6 —
so the file's second line is 2e625d3c, not 11bb44a3; the dealing puts 26e6836b/11bb44a3 in
different slices either way). Regenerate from the responses rather than transcribing.

### Institutional learnings applied

- `2026-06-02-followthrough-gh-probe-needs-secrets-gh-token-env-i-strips-it.md` — `env -i`
  forwards only `secrets=`; Phase 6 replicates that shape locally.
- `2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of.md`
  and `2026-08-04-my-probe-passed-against-the-outage-it-was-built-to-detect.md` — the fixtures
  model the vendor's real shape (`{runs,total_count}` with `startedAt` at microsecond precision
  and a `FATAL` body arriving on non-200), and the matrix is written before the probe.
- `test-failures/2026-09-02-my-fake-curl-put-the-seam-above-everything-the-vendor-validates.md` —
  the stub validates argv (headers, method, `from=`, id count) as the hook and CF Access would.
- `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md` — no
  `curl -f`; the status code is read from `-w` and 401/403/500 all land in CANNOT ESTABLISH.
- `2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md` — `Ref #6178`,
  never `Closes`.
- `2026-07-19-a-wall-clock-break-in-a-replayed-body-and-a-plan-premise-that-would-have-overridden-the-operator.md`
  — exit-code semantics are quoted from the sweeper, not assumed; the closed-set path reopens on
  rc 1 only, which this probe never returns.
- `2026-03-10-jq-generator-silent-data-loss.md` — dedupe/bucketing uses `unique_by`/`group_by`
  over arrays, never generator joins.
- `2026-09-17-followthrough-directive-on-existing-issue-three-silent-traps.md` — the three
  silent traps of enrolling an EXISTING issue (missing label, bare `script=` name, indefinite
  daily comments); Phase 7's checklist is that learning's checklist, and the horizon here is
  bounded by the operator's close.
- `2026-03-24-gh-api-paginate-concatenated-arrays.md` — `jq -s 'add // []'` is correct for
  concatenated ARRAYS (which is why the spool holds `.runs` arrays, never the response objects).
- `2026-03-09-shell-api-wrapper-hardening-patterns.md` / `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`
  — a `jq` failure inside `$(…)` under `pipefail` without `-e` does not stop the script; every
  site captures rc.

## Open Code-Review Overlap

- #7942 "Two mutation batteries in plugins/soleur/test/ are named *.mutation.sh and run in no
  gate" names `scripts/test-all.sh` — **Acknowledge.** Different concern (naming of plugin
  batteries); this PR adds one `run_suite` line under the followthroughs block and does not
  touch the plugin test section.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly on the day it lands — the
  probe only posts a heading on #6178. The indirect failure is a false SOAK CLEAN that leads the
  operator to flip ADR-100 and release the rollback snapshots while two schedulers are live, which
  every user would then feel as duplicated cron effects (double Discord/email sends, a second
  `cron-workspace-gc` pass, double `cron-action-required-sla` filings) with the pre-cutover rollback
  path gone.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the sweeper republishes
  probe output verbatim on a PUBLIC issue. The probe emits function UUIDs, bucket indices, and
  counts only (already public in the cutover run logs); the HMAC secret, its signature, and the
  CF-Access pair are never written to stdout/stderr, and the xtrace refusal (exit 78) covers the
  one channel that would echo them.
- **Brand-survival threshold:** `aggregate pattern` — a wrong verdict harms every user at once via
  duplicated cron side effects, not one user's data; the destructive verbs (flip, release, close)
  remain manual and are named, never executed, by the probe.

## Observability

```yaml
liveness_signal:
  what: "the sweeper's daily comment on #6178 headed NOT YET / CANNOT ESTABLISH / ACTION REQUIRED (verdict word from scripts/sweep-followthroughs.sh run_one), plus the run's own log line `issue #6178: scripts/followthroughs/inngest-soak-6178.sh exit=<rc>`"
  cadence: "daily at 18:00 UTC from 2026-09-22 (earliest gate), until the operator closes #6178; then the closed-set path re-evaluates for 14 days without ever reopening (rc 1 is never returned)"
  alert_target: "the operator via the #6178 issue comment — the operator (deruelle) is the issue author, so GitHub routes the comment as a notification — and the scheduled-followthrough-sweeper.yml run status (layer 6: workflow run log + issue comment)"
  configured_in: ".github/workflows/scheduled-followthrough-sweeper.yml (cron + env) and the directive appended to the #6178 body"

error_reporting:
  destination: "the same issue comment: exit 3 renders CANNOT ESTABLISH with reason=<enum> slice=<k>/<n> in the folded output; a directive/secret fault is the sweeper's own REQUIRED SECRET MISSING / DIRECTIVE INSIDE CODE FENCE comment and a red run"
  fail_loud: "any non-200, FATAL body, non-array .runs, vacuous or incomplete slice exits 3 (never 2, never 0); a missing credential exits 3 with reason=credentials_unprovisioned; xtrace with a live credential exits 78"

failure_modes:
  - mode: "probe never runs, LOUD sub-case: directive inside a fence, or a `secrets=` name absent from the workflow env"
    detection: "the sweeper comments DIRECTIVE INSIDE CODE FENCE / REQUIRED SECRET MISSING on #6178 and reds the run (layer 6)"
    alert_route: "red sweeper run + #6178 comment"
  - mode: "probe never runs, SILENT-GREEN sub-case: script missing on main, exec bit lost, path not canonical (`fail()` is stderr-only + return; the run stays green)"
    detection: "pre-merge only — scripts/followthrough-exec-bit.test.sh, lint-followthrough-varq-ban.sh rule 3, the Phase 7 step 5 parser readback and step 6 dry-run dispatch; post-merge the RETIREMENT line is the only guard against deletion (layer 6, run log stderr)"
    alert_route: "CI red before merge; none after merge — accepted, the window is minutes"
  - mode: "the sweep itself does not fire on 2026-09-22 (Actions outage, workflow disabled)"
    detection: "none today — the sweeper has no sentry-heartbeat (pre-existing gap, out of this PR's allowed edits); deferred as #8349"
    alert_route: "none until #8349 lands; the operator's Phase 7 T2 pre-announcement (if adopted) is the only expectation-setting signal"
  - mode: "one slice exceeds the on-host page budget at day 7 (density shifted)"
    detection: "HTTP non-200 with a `FATAL … reason=deadline|window_too_wide` body → exit 3 naming the slice (layer 6); the SOLEUR_INNGEST_PREFLIGHT_TIMEOUT marker on the host's journald → Better Stack source 2457081 via the `inngest-doublefire-probe` tag allowlisted in apps/web-platform/infra/vector.toml (layer 3; readable with `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 24h --grep SOLEUR_INNGEST_PREFLIGHT --limit 20`)"
    alert_route: "CANNOT ESTABLISH heading on #6178; remedy is a re-measured re-sort of the population file"
  - mode: "a credential rotated (HMAC or CF Access pair)"
    detection: "measured live: HMAC mismatch → HTTP 500 body `Error occurred while evaluating hook rules.` (`cause=hmac_mismatch`); CF pair → 4xx HTML (`cause=cf_access`) → exit 3 (layer 6)"
    alert_route: "CANNOT ESTABLISH heading on #6178; the same three credentials serve #5875's canary-promotion-5875.sh, which reports the same day"
  - mode: "a cron registered after 09-15 (outside the pinned population)"
    detection: "the registry GET's `function_count != 70` or a population id missing → exit 3 `registry_drift` (layer 6)"
    alert_route: "CANNOT ESTABLISH heading on #6178"
  - mode: "a real double-fire outside the explained set"
    detection: "exit 5 with `SOAK NOT CLEAN` and the (functionID, bucket, count) list (layer 6)"
    alert_route: "ACTION REQUIRED heading on #6178 — the operator investigates before any flip"
  - mode: "vacuous read (mis-scoped ids after a registry change)"
    detection: "per-slice total_count>0 and runs>0 gate → exit 3 reason=slice_vacuous"
    alert_route: "CANNOT ESTABLISH heading on #6178"

logs:
  where: "the sweeper workflow run log (Actions, 90-day retention) and the last 4 KB of probe output inside the #6178 comment (permanent); on-host preflight markers in journald → Better Stack source 2457081"
  retention: "Actions logs 90 days; issue comments indefinitely; Better Stack per its plan retention"

discoverability_test:
  command: "bash scripts/followthroughs/inngest-soak-6178.test.sh"
  expected_output: "a final line `inngest-soak-6178: <N> passed, 0 failed` with <N> equal to the suite's FLOOR, exit 0"
```

## Guard Contract

### Guard 1 — the soak probe's verdict

**Property.** The probe's exit code is 5 with `SOAK NOT CLEAN` whenever, over the complete
52-function population and the full window from SOAK_FROM, any (functionID, 1200 s bucket) group
holds more than one distinct run and is not one of the two pinned explained triples; it is 3
whenever any slice could not be read completely and non-vacuously; it is 2 only for a complete
reading taken before SOAK_END; and it is never 0 or 1.

**Assembly.** Every path that turns bytes into the exit code: the population parser
(`grep -vE '^\s*(#|$)'` + the UUID regex + the `POPULATION_SIZE=52` count) and the round-robin
dealer (`(NR-1) % N_SLICES == k`); the single `curl` call site inside the slice loop and its
four acceptance checks (code, `FATAL`, `.runs` type, `total_count`); the per-slice dedupe and the
`deduped >= total_count` floor; the spool → `jq -s '[.[][]]'` union; the dedupe/bucket/group jq
(copied from op=verify 2.6); the explained-split jq over the `EXPLAINED` constant; the
`now`/`SOAK_END` comparison (`INNGEST_SOAK_NOW_EPOCH` or `date -u +%s`); the global
`RUN_FLOOR` gate and the window-head check; the per-call-site `jq_failed` capture; the `EXIT` trap
that rewrites every rc outside {2,3,5,78} to 3; and the `exit` statements — every literal exit
in the file is in {2,3,5,78} and `grep -E '^\s*exit (0|1)\b'` returns nothing (several contract
rows legitimately share one exit site, so no exit-count equality is asserted).

**Mutation matrix:** (★ = invariant row, hand-run at AC6; unstarred rows are proven by the
harness case alone)

| # | Mutation (probe or harness) | Case that reddens |
|---|---|---|
| 1 ★ | `exit 5` in the clean branch → `exit 0` | C2 (rc), plus `assert_never_close_verb` |
| 2 ★ | `exit 3` in the slice-unreadable arm → `exit 1` | C6/C7 (rc) + the invariant |
| 3 ★ | delete the `FATAL` substring check (rely on the status code alone) | C7 — asserts `reason=slice_unreadable cause=probe_fatal`, so the mutated probe's `jq_failed` exit (the FATAL body is not JSON) reds rather than passes |
| 4 ★ | `count == .count` in the explained predicate → `count <= .count`, AND separately → `count >= .count` | C5b + C5c as a PAIR (each direction reds exactly one of them) |
| 5 | pin the explained set as a bare bucket (`bucket == 1491374`) | C5 (third function in the bucket reads explained) |
| 6 ★ | swap `<` for `<=` in `now < SOAK_END` | C2 (now == SOAK_END must be 5, reads 2) |
| 7 ★ | remove the per-slice `total_count > 0 && runs > 0` gate | C9 (empty slice reads clean) |
| 8 ★ | remove `deduped >= total_count` | C10 |
| 9 | `unique_by(.id)` → identity (no dedupe) | C11 (page-overlap duplicate becomes a group) |
| 10 ★ | replace `run_jq` (rc capture) with a bare `$(… \| jq …)` at the DUPES site | C23 (a throwing jq falls through to CLEAN instead of `jq_failed`) |
| 11 | `SLICE_MAX=11` → `26` | C15 (stub exits 64 on a 26-id request → 3, and call count 2 ≠ 5) |
| 12 | `POPULATION_SIZE=52` → `51` | C16 inverted (the 52-line file now malformed) and C1 (3 instead of 2) |
| 13 ★ | stop at the first slice (`break` after k=1) | C15 (1 call, union incomplete) — the "second member" row |
| 14 | delete the credential check | C14 (a request is made with empty headers; stub exits 64 → 3 for the wrong reason: assert `credentials_unprovisioned` AND empty calls.log) |
| 15 | HARNESS: `expect()` never calls `fail()` | H1 instrument self-test exits 1 |
| 16 | HARNESS: stub no longer asserts the signature header | H2 (stub must exit 64 on argv without it) |
| 17 | HARNESS: delete any case | FLOOR (pinned to the measured pass count) |
| 18 | HARNESS: `run()` stops exporting `INNGEST_SOAK_NOW_EPOCH` | C1/C11/C12 keep passing before 09-22 and silently flip after — so this row is proven by a `grep -c 'INNGEST_SOAK_NOW_EPOCH=' inngest-soak-6178.test.sh` ≥ 1 assertion inside the suite (H4), not by a date |
| 19 ★ | install `trap 'rm -rf "$WORK"' EXIT` after `on_exit` (the second-trap defect), then replace the slice-unreadable `exit 3` with `: "$SOAK_UNBOUND_PROBE_VAR"` (a `set -u` abort, raw rc 1 — `false` does NOT exit without `-e`, so the earlier form of this row isolated nothing) | C6: with `on_exit` intact it reads 3 `reason=unmapped_exit rc=1`; with the replaced trap it reads 1 and `assert_never_close_verb` fires |
| 20 | `RUN_FLOOR=800` → `0` | C20 (300 runs read clean) |
| 21 | `total_count` check written as `[[ "$tc" -gt 0 ]]` instead of the regex | C9b (`unknown` reads as 0 → wrong reason) |
| 22 | replace the `all(.[]; (.id\|type)=="string")` refusal with the op=verify fallback | C18 (a run without id is silently deduped by (fn, startedAt)) |
| 23 | delete the window-head coverage check | C5e |
| 24 ★ | `jq -s '[.[][]]'` union → spool whole objects and `jq -s 'add'` | C15/C1 (only the last slice survives; `RUN_FLOOR` reds and the union check reds) |
| 25 ★ | delete the registry GET / drift gate | C0b/C0c (a 71-count or a missing id reads clean) |
| 26 | `${VAR:+x}` in the xtrace test → `-n "$VAR"` | C13: the traced output contains the fixture credential value (`grep -c 'p-secret'` must be 0) |
| 27 | delete the run-shape validation | C12b/C12c (a malformed functionID/startedAt is printed) |
| 28 | HARNESS: delete the `assert_never_close_verb` call from `run()` | H3 (the invariant helper is never exercised) |
| 29 | HARNESS: `expect_absent()` never calls `fail()` | H1 (drives it to a guaranteed mismatch) |

**Anchor.** The explained triples and the four snapshot ids are literal constants inside the probe
and are repeated in the ADR addendum and in #6178 comment 5738682595 — three independently
reviewed records; a weakening edit to the constants is visible in the PR diff against
`origin/main` and contradicts the ADR text in the same PR. The population file's set identity is
pinned by the count AND by the union check in C15 against the committed file, not by `>= N` alone.

### Guard 2 — enrollment of #6178

**Property.** From the merge of this PR until the operator closes #6178, every daily sweep at or
after 2026-09-22T13:23:00Z executes `scripts/followthroughs/inngest-soak-6178.sh` from the
default branch with exactly the three declared secrets and posts its verdict on #6178.

**Assembly.** The `follow-through` label on #6178; the column-0, unfenced directive in the #6178
body carrying `script=`, `earliest=`, `secrets=`; the on-disk executable at the canonical path on
`main`; the three names in the sweeper workflow `env:`; the sweeper's `parse_directive` and
`run_one` (earliest gate, Guard 3, `env -i`). The oracle for the directive grammar is
`scripts/followthrough-predicate-parity.test.sh` (authority = the sweeper).

**Mutation matrix:**

| # | Mutation | What reddens |
|---|---|---|
| 1 | directive appended inside a ```html fence | Phase 7 step 5 readback (`parse_directive` prints nothing); the next sweep comments DIRECTIVE INSIDE CODE FENCE and reds |
| 2 | `script=inngest-soak-6178.sh` (bare name) | readback step 5 (`script` line missing the canonical prefix); the sweeper's path canonicalisation refuses silently — which is why the readback is required |
| 3 | label omitted | readback step 5 (`grep -c follow-through` = 0); the sweeper never enumerates the issue |
| 4 | `secrets=` lists a fourth name absent from the workflow env | dry-run dispatch after earliest would comment REQUIRED SECRET MISSING; pre-earliest, the readback's `secrets` line is diffed against the three names |
| 5 | HARNESS: readback grep loosened to `soleur:followthrough` anywhere | a fenced directive would pass the readback — step 5 uses the sweeper's own parser, not a grep |

**Anchor.** Enrollment is verified by the sweeper's own parser (`parse_directive` sourced from
`scripts/sweep-followthroughs.sh`) and by a dry-run dispatch of the real workflow, not by a
restated regex.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** see the CTO findings recorded below in "CTO assessment" (spawned with the
design summary and the measured numbers; verdicts A–F).

No product, marketing, sales, legal, finance, support, or operations implications: the change is
an operator-facing verification script, an ADR addendum, and an issue-body directive; no
user-facing surface, no vendor, no expense, no legal document. The mechanical UI-surface override
does not fire (no `components/**`, `app/**`, or UI path in Files to Create/Edit).

### deepen-plan pass (8 agents; applied)

verify-the-negative: 14/14 claims confirmed by grep or execution. attribution: 9/10 confirmed;
the tenth (run 35223389582 = `op=resume`) confirmed from the run's own log rather than PR #8252's
body; AND the 09-15 anchor class corrected to `floor(override)` / QUALIFIED. security-sentinel:
P1 xtrace-test spelling, P1 host-bytes-before-print shape validation, P1 `LC_ALL=C` UUID regex,
P2 body-excerpt classification, P2 `--ref` wording + sweeper-diff precondition, P2 bucket regex
— all applied. test-design (8.3/10 → fixed): ★ rows 4 and 19 did not red their cases; C7 could
pass via `jq_failed`; invariant and negative helpers lacked self-tests; wall-clock dependence;
builder under-specified; mixed-precision fixtures — all applied. observability: layer tags, the
measured 500-on-HMAC-mismatch, `body_class`, loud/silent split of mode 1, the un-heartbeated
sweeper (deferred #8349), participant routing — all applied. architecture: P2-a caveat + web-1
evidence, registry-drift gate (validated live: 70/70, 52 ⊆ registry), close-LAST ordering, P2-c
residual, anchor-class correction, Decision-7 framing, verdict-last output, ADR-146 — all
applied. pattern-recognition: three novel mechanisms declared in the header; `--proto '=https'`;
`WHY -uo AND NOT -euo` sub-heading. learnings: four learnings folded (above).

### plan-review panel (DHH, Kieran, code-simplicity, CTO-devex; consolidated)

Simplification and correctness panels fired on the same four mechanisms → deleted: the
ADR-accepted self-quieting arm (+ its seam, C21, two matrix rows), the REQUIRED-presence half of
`index_eroded` (below-pin now renders UNEXPLAINED; the window-head check stays as the retention
canary), the `foreign_function_id` subset check, and `ACTIVE_FLOOR`. Kieran P0 ×2 applied:
`jq -s 'add'` on objects keeps only the last slice → `jq -s '[.[][]]'`; a failing jq never
reaches the EXIT trap under `set -uo pipefail` → per-call-site rc capture (`jq_failed`). Kieran
P1/P2 applied: curl `-w` + `|| echo 000` double-print; Property 3 text vs `==`; unsatisfiable
exit-count equality; whole-file `status:` grep (moot after the cut); horizon recomputed from
`PREFLIGHT_SEC_PER_PAGE`; window-head threshold measured live (global min = SOAK_FROM); byte-equal
readback replaced. Simplicity/CTO-devex applied: slice sizes no longer pinned (property is
"5 calls, ≤11 each, union == 52"); hand-run mutation set reduced to the 12 ★ invariant rows;
one `remedy=` per `reason=` with a literal command where one exists; `RETIREMENT:` carries the
close+14 d timing. Kept against DHH alone (single panel, no correctness objection):
`POPULATION_SIZE=52` (a dropped id would silently shrink the verified population; C15's union
check reads the same file so cannot catch it) and `RUN_FLOOR=800` (derivation now inline). Taste
findings from the named panel are persisted to `decision-challenges.md` (T1–T3), not applied.

### SpecFlow analysis (Phase 3; 10 findings, all applied)

P0: a second `trap … EXIT` would replace the rc filter (→ single `on_exit`, C23, matrix 19).
P1: ADR-accepted arm placement + case-insensitive match (moot — the arm was cut by plan-review); premature
close is unrecoverable (→ AC11 PR sweep + ADR sentence); `total_count` may be `"unknown"` (→
`total_count_unknown`, C9b, matrix 21); C11 collided with `slice_incomplete` (→ builder emits
`total_count` = distinct ids; C10 overrides); default fixture window overlapped bucket 1491374
(→ pinned 2026-09-18T00–16Z); blind full-body PUT on the issue (→ re-fetch + `cmp` before edit,
byte-equal readback). P2: null `functionID` merges groups (→ refusal + C19b); log strings and the
clock-dependent AC14 (→ actual `missing in repo HEAD` string; AC14 accepts both arms); ACTION
REQUIRED lacked the reading and per-reason remedies (→ reading block before every verdict,
`remedy=` per `reason=`). (The `foreign_function_id` subset check it also suggested was later cut by plan-review.)

### Advisor consult (Step 4.5, semantic tier `advisor`; applied / challenged)

- Verdict: approach right (notify-only with a structural never-0/never-1 trap, population
  slicing, exact explained triples, hard-fail on partial reads). Weakness: the sweeper's first
  production execution of the probe is the day-7 verdict.
- **A. `earliest=` at enrollment time instead of SOAK_END** — both signals agree, but it changes
  the operator's stated directive (`earliest=2026-09-22T13:23:00Z`), so it is a **User-Challenge**
  persisted to `knowledge-base/project/specs/feat-one-shot-6178-soak-followthrough/decision-challenges.md`
  (headless arm); the plan keeps the operator's value.
- **B. Explained triples REQUIRED + window-head coverage** — window-head applied (`index_eroded`, exit 3); the REQUIRED-presence half was later cut by plan-review (below-pin renders UNEXPLAINED, which is not clean).
- **3.** Cursor pagination verified (no `deduped < total_count` race); the post-day-7 horizon is
  stated in the ACTION REQUIRED text.

### CTO assessment (spawned 2026-09-19, blocking; verdicts applied above)

- **A. Slicing — ok.** Round-robin over a density-sorted file is the minimal choice; consecutive
  chunks would concentrate the heaviest crons in slice 1; adaptive bisection adds state the
  PATH-stubbed seams cannot cover deterministically. Mis-ordering fails loud (exit 3 naming the
  slice); headroom is ~30× (0–3 s measured vs the 90 s in-script deadline).
- **B. Explained pin — concern, applied.** Bucket 1491374 is historical and immutable, so the
  counts are pinned EXACTLY (== 4, == 2), not `<=`; a run without a string `.id` is refused
  (exit 3) instead of the `(functionID, startedAt)` fallback.
- **C. Daily exit 5 — ok.** The sweeper documents its no-dedup contract; the optional
  self-quieting arm was adopted here and later cut by plan-review (no property; the operator's
  close already quiets the probe).
- **D. Post-close — concern, applied.** The closed path reopens only on rc 1, but `jq -e`/`grep -q`
  return 1 and jq runtime errors return 5; an `EXIT` trap maps every unmapped rc to 3, with
  mutation rows 10 and 19 (C23) proving rc 1 and rc 5 are unreachable as verdicts.
- **E. Non-vacuity — ok, floor added.** `RUN_FLOOR=800` distinct runs (half the day-3.6
  measurement) so a partial run-index outage cannot read clean-but-thin; the `ACTIVE_FLOOR` it also
  proposed was cut by plan-review (22 of 52 ids are legitimately at zero).
- **F. ADR-100 / runbook fidelity — concern, applied.** `SOAK_FROM` is an `override`-class
  anchor derived from the 09-15 `op=verify` pass; the probe output and the ADR addendum state the
  derivation and that the day-7 reading is a soak reading over the post-verify window, not a
  re-proof of the coexistence region.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `scripts/followthroughs/inngest-soak-6178.sh` exists, is executable, begins with the
      header grammar of `inngest-host-not-serving-7674.sh` (WHY, credential posture, `RETIREMENT:`,
      EXIT CONTRACT stating never-0/never-1), refuses xtrace with a live credential (exit 78), and
      uses `set -uo pipefail` (no `set -e`): `grep -c '^set -uo pipefail$'` = 1, `grep -c 'set -e'` = 0
      on non-comment lines.
- [ ] AC2 `grep -E '^\s*exit (0|1)\b' scripts/followthroughs/inngest-soak-6178.sh` returns nothing;
      every `exit` maps to a row of the §Exit contract table.
- [ ] AC3 The pinned constants are literal in the probe: `SOAK_FROM=2026-09-15T12:40:00Z`,
      `SOAK_END=2026-09-22T13:23:00Z`, `PERIOD=1200`, `SLICE_MAX=11`, `POPULATION_SIZE=52`, the two
      explained triples with exact `count` 4 and 2 on bucket 1491374, `RUN_FLOOR=800`, `REGISTRY_COUNT=70`, and the four image ids
      398857857 / 406654994 / 407991378 / 411798619 in the ACTION REQUIRED text
      (`grep -c 398857857` = 1 on an executable line).
- [ ] AC4 `scripts/followthroughs/inngest-soak-6178.function-ids.txt` has a `#` provenance header
      naming runs 34974655656 and 35415585389 and the extraction command, then exactly 52 UUID
      lines, no duplicates, set-equal to the run-log extraction, ordered by the measured density
      ranking (heaviest first, ties by id).
- [ ] AC5 `bash scripts/followthroughs/inngest-soak-6178.test.sh` exits 0 and prints
      `inngest-soak-6178: <N> passed, 0 failed` with `<N>` equal to its FLOOR; `<N>` ≥ 40.
- [ ] AC6 Every ★ row of Guard 1's mutation matrix (13 rows) was applied one at a time and
      reddened the named case (record the rc/first-line pairs in the PR body's test section); each
      revert restores green. Unstarred rows are covered by their harness cases.
- [ ] AC7 `scripts/test-all.sh` carries
      `run_suite "scripts/inngest-soak-6178" bash scripts/followthroughs/inngest-soak-6178.test.sh`
      and `bash scripts/lint-orphan-test-suites.sh` is clean.
- [ ] AC8 `bash scripts/lint-followthrough-varq-ban.sh` is clean (rules 1–3, including rule 3 on
      the population-file default path); `bash scripts/followthrough-exec-bit.test.sh` and
      `bash scripts/followthrough-predicate-parity.test.sh` are green; the trap-tempfile lint's
      CI invocation is green.
- [ ] AC9 ADR-100 has the new addendum heading
      `## Addendum — 2026-09-19 (#6178) — the soak reading at day 3.5 and what the day-7 probe measures`
      after the 2026-09-18 addendum, the frontmatter line `status: adopting` is unchanged
      (`git diff origin/main -- <ADR> | grep -c '^[-+]status:'` = 0), and
      `python3 scripts/lint-infra-no-human-steps.py <ADR path>` is OK.
- [ ] AC10 Phase 6 live run (the `env -i` shape via `doppler run`) returned `rc=2`, the registry GET 200 with `function_count=70`, five slices,
      ≥ 826 distinct runs, exactly the two explained groups and zero UNEXPLAINED; the per-slice
      `total_count` line is recorded in the population file header with its UTC timestamp.
- [ ] AC11 The PR body says `Ref #6178` and contains no `Closes|Fixes|Resolves #6178`; the only
      `Ref`/`Tracks` targets in the PR body and this plan (fences stripped) are #6178 and #8252
      (merged, so ignored by the gate). Ship-time sweep of OTHER open PRs:
      `gh pr list --state open --search "6178 in:body" --json number,body --jq '.[] | select(.body | test("(?i)(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]+#6178")) | .number'`
      prints nothing (measured 2026-09-19: nothing across all states). A premature close of #6178
      before 09-22 would silence the probe permanently — the closed-set path returns silently on
      rc 2/3/5 — and the ADR addendum says so in one sentence.
- [ ] AC12 No file under `apps/web-platform/infra/`, no `*.tf`, `scripts/sweep-followthroughs.sh`,
      `.github/workflows/scheduled-followthrough-sweeper.yml`, or the convention runbook appears in
      `git diff --name-only origin/main`.
- [ ] AC13 Diff scope: `git diff --name-only origin/main` is a subset of {the three new files,
      `scripts/test-all.sh`, the ADR, this plan, `knowledge-base/project/specs/feat-one-shot-6178-soak-followthrough/*`,
      `knowledge-base/INDEX.md`, any learning file the compound step writes, and any file the
      review step's fold-ins touch under the same paths}.
- [ ] AC14 (ship-time, before `gh pr ready`) #6178 carries the `follow-through` label and the
      directive at column 0; `parse_directive` (sourced from the sweeper) prints the three lines;
      the dry-run dispatch on the branch ref logs `directive found (script=scripts/followthroughs/inngest-soak-6178.sh earliest=2026-09-22T13:23:00Z secrets=WEBHOOK_DEPLOY_SECRET,CF_ACCESS_CLIENT_ID,CF_ACCESS_CLIENT_SECRET)`
      then EITHER `earliest=2026-09-22T13:23:00Z not yet reached … skipping` (dispatch before SOAK_END)
      OR `… exit=<2|3|5>` + `DRY_RUN — would comment with verdict=<NOT YET|CANNOT ESTABLISH|ACTION REQUIRED>`
      (dispatch at/after SOAK_END) for issue #6178, with no `missing in repo HEAD`/`not executable`/
      `refused`/`INSIDE A CODE FENCE` line.

### Post-merge (automated — no operator step)

- [ ] AC15 The first scheduled sweep after 2026-09-22T13:23:00Z (2026-09-22T18:00Z) posts a
      comment on #6178 headed `### Sweeper run: ACTION REQUIRED (exit 5, …)` or
      `CANNOT ESTABLISH (exit 3, …)`; never `PASS`, never `FAIL`. Verified by the sweep itself;
      the operator's subsequent flip/release/close is the ADR-100 decision this plan deliberately
      leaves human, and it is not an acceptance criterion of this PR.

## Test Scenarios

- Given the committed population file and five 200 fixtures with one run per (id, hourly tick),
  when the probe runs with `INNGEST_SOAK_NOW_EPOCH` = 2026-09-20T00:00:00Z, then rc=2 and the
  output contains `NOT YET`, `runs=`, `slices=5/5`, `explained=0`, `UNEXPLAINED=0`.
- Given the same fixtures plus the two explained groups and `INNGEST_SOAK_NOW_EPOCH` =
  1790083380 (SOAK_END), then rc=5 and the output contains `SOAK CLEAN`, `explained=2`, the
  attribution string, `adopting → accepted`, all four image ids, and `close #6178`.
- Given one extra group in bucket 1491375, then rc=5 with `SOAK NOT CLEAN`, `UNEXPLAINED=1`,
  the functionID and `2026-09-17T13:00:00Z`, and `investigate`.
- Given slice 3 returns 500 with body `inngest-doublefire-probe: FATAL preflight scan aborted reason=deadline pages_scanned=14 …`,
  then rc=3 with `reason=slice_unreadable slice=3/5 http=500` and the first 200 body characters on
  one line.
- Given `bash -x` and `WEBHOOK_DEPLOY_SECRET` bound, then rc=78 and no request in `calls.log`.
- Given the real endpoint via `doppler run`, then rc=2 today and the two explained groups only.

## Dependencies & Risks

- **The on-host deadline is measured from the host, not the client.** The workstation's 0.5 s/page
  says nothing binding about the runner at day 7; the FATAL arm and the per-slice naming exist for
  that case, and a re-sort (Phase 1 rerun with fresh counts) is the remedy. Likelihood low: the
  heaviest slice forecasts ≈ 8 pages against a ~14-page cap.
- **Weekly crons wake up inside the window.** The 22 zero-run ids include Monday crons that fire
  on 2026-09-21; they add ≤ 1–2 runs each and cannot create a group on their own.
- **The sweeper comments daily after day 7 until the operator acts.** Accepted: the horizon is
  the operator's own action (flip + release + close) within days; the convention reserves drift
  workflows for indefinite horizons.
- **Closed-set re-evaluation.** After #6178 closes, the sweeper re-runs the probe for 14 days in
  closed mode; only rc 1 reopens, and the probe never returns 1. The ADR-accepted arm sits before
  any GET, so once the flip lands the closed-mode runs make no request at all.
- **A premature close is unrecoverable by the probe.** If #6178 is closed before 2026-09-22 (a
  `Closes #6178` in any PR body — the 07-07 plan's own vocabulary), closed mode returns silently
  on rc 2/3/5 and the day-7 reading is never posted. AC11 sweeps open PRs at ship time; the ADR
  addendum records the hazard.
- **Order of enrollment vs. merge.** Enrolling before merge means the 18:00Z sweep could find the
  script absent on `main` (stderr-only, no comment). The window is minutes because ship merges in
  the same session; if a merge slips past 18:00Z, the log line is expected and harmless.
- **CF Access or the webhook secret rotates before day 7.** Exit 3 names it — HMAC mismatch is
  HTTP 500 `Error occurred while evaluating hook rules.` (measured), the CF pair is a 4xx HTML
  page; the same secrets serve `canary-promotion-5875.sh`, so a rotation would already surface on
  that tracker.
- **The sweep itself does not fire on 09-22.** The sweeper has no `sentry-heartbeat`; "no
  comment" is indistinguishable from "swept and found nothing". Pre-existing and outside this
  PR's allowed edits — deferred as #8349 (re-evaluate on 2026-09-23 if no comment appeared).
- **A cron registered mid-soak.** Outside the pinned population → never queried → the registry
  drift gate refuses (`registry_drift`) rather than reading clean. Registry was 70 on 09-15,
  09-19, and at plan time; the two cron files modified since SOAK_FROM added no function.

## Sharp Edges (for the implementer)

- A plan whose `## User-Brand Impact` section is empty, contains only draft-marker text, or omits
  the threshold fails `deepen-plan` Phase 4.6 — the section above is complete; keep it so.
- Never write `Ref #<open-issue>` for anything but #6178 in the PR body: the ship-soak gate would
  demand that tracker's enrollment too.
- Keep the directive on ONE line at column 0. The multi-line canonical form is also honoured, but a
  stray fence between its lines is the exact defect the parity oracle pins; one line has no inside.
- Do not `curl -f`: a 401/403 must reach the status-code branch as CANNOT ESTABLISH.
- Never echo `$SIG`, the secret, or the CF pair — not even in a "debug" line; the sweeper republishes
  stdout+stderr on a public issue.

## References

- ADR-100 `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`
  (Decision 7; addenda 2026-09-15 and 2026-09-18).
- #6178 comment 5738682595 (day-3.5 reading and attribution); PR #8252 (the 76-minute
  no-scheduler window; `op=resume` run 35223389582); runs 34974655656 (soak start) and
  35415585389 (day-3.5 reading).
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`;
  `knowledge-base/engineering/operations/runbooks/inngest-server.md` §"Scan window + trust anchor".
- `knowledge-base/project/plans/2026-07-07-feat-extract-inngest-dedicated-host-plan.md` (Phase 4.1
  as originally prescribed).
