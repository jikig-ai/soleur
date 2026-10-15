---
title: "fix: dormant follow-through regression detectors + Inngest raw-key/ledger reconciliation"
type: fix
date: 2026-10-15
slug: fix-dormant-probe-ledger-10321-10136
branch: feat-one-shot-10321-10136-dormant-probe-ledger
issue: 10321
closes: 10321
lane: cross-domain
---

# fix: dormant follow-through regression detectors + Inngest raw-key/ledger reconciliation

## Overview

Two p3 issues sharing the zot + Inngest private-network surface, one PR.

- **#10321 (observability):** `scripts/followthroughs/zot-log-channel-7440.sh`'s header claims it
  stays "enrolled as a REGRESSION detector" after tracker #7455 closed. It has not run since
  ~2026-08-27 — `scripts/sweep-followthroughs.sh` reads open `follow-through` issues plus closed
  ones inside `CLOSED_LOOKBACK_DAYS=14` (`sweep-followthroughs.sh:48`, `:983-987`), so a probe on a
  tracker closed-as-COMPLETED on 2026-08-13 fell out of the read set two weeks later. Its single
  `exit 1` arm — a credential-shape scan over shipped `SOLEUR_ZOT_LOG` rows on Better Stack source
  2457081 — is the only automated reader of what the registry shipper's `redact()` actually emits.
  The fix is the dormant-detector *contract*: the standing credential-shape check moves to a
  Terraform-managed Better Stack Logs alert (the pattern the CTO already ruled for the sibling
  clientIP invariant, #7530 → `registry_clientip_not_rfc1918` in open PR #10320), the probe header
  is corrected, the follow-through convention gains the rule that a check meant to outlive its
  tracker is not a probe, and the other dormant probes' headers are audited and corrected.
- **#10136 (security):** `apps/web-platform/lib/inngest/list-runs.ts` sends
  `Authorization: Bearer ${signingKey}` — the **raw** signing key — on the app→inngest run-list
  reads over the plain-HTTP hop to `10.0.1.40:8288`, while the ledger row says "the raw signing key
  never crosses the wire". The inngest server accepts the hashed form (`signkey-prod-<sha256>`) —
  verified at source (`pkg/authn/signing_key_strategy.go` `HandleSigningKey` at v1.45.1, the pinned
  CLI version, compares the presented key against BOTH the plaintext and hashed forms of the
  trusted key) — so the code fix is: hash the bearer the way the Inngest SDK's `hashSigningKey`
  does, and reconcile the ledger's `does_not_defend` wording (raw-key claim + step-outputs scope,
  whose transport is attributed to the Cloudflare serve-URL leg per #9139, not this link).
- Out of scope: TLS on the private hops (CLO ruling due 2026-10-24; the Inngest row is not
  renewable past 2026-11-12 without TLS or a CLO acceptance based on a measured nftables re-read —
  both gated on authority this pipeline lacks), the `hcloud_volume.git_data` ledger row (owned by
  open PR #10352), all `docs/legal/**` (CLO hold), any Terraform-managed-infra or Doppler write,
  and reopening the dead tracker #7455.

## Problem Statement / Motivation

A follow-through probe's enrollment lifetime is bounded by its tracker's state: open trackers are
swept daily; trackers closed as COMPLETED are swept only for `CLOSED_LOOKBACK_DAYS=14` more days
(the closed-set exists to catch premature closes — `sweep-followthroughs.sh` closed arm: exit 1 →
reopen, everything else → no-op); after that the probe file is dead code. A probe whose lasting
value is a *regression* arm (exit 1 on a condition that can re-emerge after the PASS) therefore
silently stops doing the thing its header promises. Seven such probes are dormant today (audit
below). For `zot-log-channel-7440.sh` the dormant arm is load-bearing: it reads every shipped
`SOLEUR_ZOT_LOG` row for (a) an `Authorization` header value that is neither zot's `******` mask
nor the shipper's `REDACTED` marker, (b) a Doppler token prefix `dp.(pt|st|sa|ct).`, (c) a bcrypt
`$2[aby]$` hash prefix — a leak there is a supply-chain exposure (the zot push/pull credential).

Separately, the Inngest hop's ledger row over-claims: (i) `list-runs.ts` sends the raw
`INNGEST_SIGNING_KEY` (`signkey-prod-<64hex>` per `inngest-host.tf:163`) as the Bearer on two fetch
calls (`/v1/events`, `/v1/events/:id/runs`) — the raw key DOES cross the wire; (ii) the row lists
"step outputs" among the plaintext payload, but the CTO code read attributes step execution to the
Cloudflare serve-URL step-call leg (#9139), so the link's payload claim is broader than the
evidence supports. #10326 recorded both discrepancies without fixing them; this plan fixes the
code and reconciles the ledger text.

## Research Reconciliation — Spec vs. Codebase

| Issue-brief claim | Verified reality (2026-10-15) | Plan response |
|---|---|---|
| "#10136's three exceptions are pending renewal" | Stale: merged PR #10132 already renewed all three to `expires_on=2026-11-12` with `tracking_issue=#10136` | Plan renews nothing; it reconciles wording only |
| "the raw signing key never crosses the wire" (ledger, Inngest row) | False: `list-runs.ts` sends `Bearer ${signingKey}` raw on two fetches | Hash the bearer to `signkey-prod-<sha256>` (SDK parity) |
| "probe stays enrolled as a REGRESSION detector" (zot-log-channel header) | False: tracker #7455 closed 2026-08-13; dormant since ~2026-08-27 | Correct header; move the standing check to a Better Stack alert |
| "re-opened tracker with open-ended lookback" as a vehicle option | Would fight the sweeper's deliberate `closed:>=` bound and REOPEN_MAX=3 semantics | Not chosen; alert vehicle assumed (pending CTO confirm — decision-challenges) |
| zot rows "can be accepted on qualified wording after a measured nftables re-read" (CLO 10-13) | The re-read is an infra read; no terraform/dispatch rights in this PR | Listed as operator-gated residual on #10136, not a plan task |
| "step outputs" cross `10.0.1.40:8288` | CTO code read puts step execution on the Cloudflare serve-URL leg (#9139) | Narrow the ledger wording; mark step-output transport not asserted on this link |

## Research Insights

### Premise validation (Phase 0.6)

Every cited artifact was re-verified live before research: #10321 OPEN, #10136 OPEN, #7455
CLOSED-COMPLETED 2026-08-13T18:46:29Z, #7456/#7530/#8698/#9139 OPEN; PR #10132 MERGED, PR #10326
MERGED, PR #10352 OPEN (draft, edits `scripts/encryption-posture-ledger.json` `hcloud_volume.git_data`
at_rest row + ADR-239 — this plan does not touch that row), PR #10356 OPEN (draft; its plan file
`2026-10-15-fix-argv-bearer-pr-c-...-plan.md` lists only `apps/web-platform/infra/{inngest-bootstrap,
web-zot-consumer-probe,inngest-consumer-probe,web-private-nic-guard}*.sh`, `tests/scripts/
test-argv-bearer-sweep.sh`, ADR-280, ADR-232 — **no overlap** with this plan's file list), PR
#10320 OPEN (larger overlap risk: edits `betterstack-logs-alerts.tf`, ADR-184, ADR-218,
`apply-web-platform-infra.yml`, `infra-validation.yml`, `betterstack-send-failed-alert-mutation.test.sh`,
creates `registry-clientip-alert-7530.sh` + runbook `registry-clientip-rfc1918-7530.md` — the exact
pattern this plan reuses; sequencing rule below). `ADR-184` is `status: accepted` and at line ~321
carries the enrollment statement this PR corrects. `inngest` npm package exports map does NOT
expose `helpers/strings.js` (`hashSigningKey` is internal), so the transform is replicated (~8
lines) with a comment pinning parity to the SDK.

### Server-side verification (definitive — settles the hash-vs-raw fork)

`inngest/inngest` v1.45.1 (the version pinned by `inngest-cli.provenance.md`),
`pkg/authn/signing_key_strategy.go` `HandleSigningKey`: the presented bearer is normalized
(`^signkey-\w+-` stripped) and compared via `subtle.ConstantTimeCompare` against BOTH
`normalizedTrustedKey` AND `HashedSigningKey(normalizedTrustedKey)` — "user can provide either
plain text or hashed so we need to check against" (source comment). Sending
`Bearer signkey-prod-<sha256-of-hex-decoded-key>` authenticates identically to the raw key. The
SDK's own server-bound calls already send the hashed form (`InngestCommHandler.js:1387`
`authToken: this.hashedSigningKey`; `helpers/strings.js:84` `hashSigningKey` = prefix +
`sha256(hex-decode(key))`). The fix is therefore a wire-exposure removal with zero auth-behavior
change — no server-side change, no Doppler change, no rotation required by this fix itself
(rotation is a separate operator decision since the raw key may already have been logged in-flight
by intermediaries; recorded as a residual on #10136 for CLO visibility).

### Property List (Phase 0.6b)

1. A credential-shaped row landing on Better Stack source 2457081 from the registry plane pages a
   human **after** #7455's close — the check must not depend on issue state.
2. `zot-log-channel-7440.sh`'s header states its true enrollment (on-demand/manual grader; the
   standing check is the alert), not "stays enrolled".
3. The same audit applies to every other probe whose header implies post-close detection.
4. `list-runs.ts` never puts the raw signing key on the wire.
5. The ledger's Inngest `does_not_defend` claims only what the code read supports.
6. The convention doc gains the rule that prevents recurrence: a check meant to outlive its
   tracker is a standing alert, not a follow-through probe.

### Cut List (Phase 0.6b)

- **Scheduled workflow re-running the probe directly** — property 1 is already covered by the
  Better Stack alert pattern (ADR-218, 13 existing `logtail_exploration_alert` resources + #10320's
  14th); a second cron substrate would duplicate the sweeper's credential forwarding for a weaker
  signal (a failed GHA run vs a Better Stack page). Cut.
- **Sweeper read-surface change (`regression=1` open-ended closed-set)** — re-opens the exact
  "re-litigate ancient history" hazard `CLOSED_LOOKBACK_DAYS` bounds (sweep-followthroughs.sh:45-48),
  touches 1097 lines of shared machinery for a check an alert expresses more directly, and ADR-218's
  pending amendment already articulates "why an alert and not a follow-through probe". Cut (recorded
  as the rejected alternative in the CTO-pending row).
- **Reopening #7455** — explicitly disallowed by the issue.
- **`doppler`-side or server-side key change** — verified unnecessary (`HandleSigningKey` accepts
  hashed form).

### Institutional learnings applied

- `2026-07-07-followthrough-and-shape-gate-silent-falseness.md` — verification code is the
  highest-leverage silent-false-green site; the alert's own drift suite is a deliverable, and the
  new test mutates COPIES via env-overridable paths (the `REGSTORE_TF`/`REGSTORE_WF` pattern).
- `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` — the alert
  SQL anchors on the direct-POST envelope shape `startsWith(raw, '{"message":"SOLEUR_ZOT_LOG ')`,
  never a bare substring (a journald row quoting the marker must not match).
- `2026-05-31-inngest-v1-loopback-gated-and-halt-on-stale-premise.md` — the `/v1/*` loopback
  gating was measured on the co-located deployment; on the dedicated host the app still sends the
  request (and therefore the credential) regardless of whether `/v1` answers — the exposure is in
  the REQUEST, so hashing fixes it either way. Whether `/api/dashboard/runs` currently returns
  data at all on the dedicated host is a separate verified-dead-route question (#9073 covers the
  sibling read-surface claim); recorded as a residual note, not scope.
- `2026-09-11-a-filer-with-no-honest-exit-takes-the-free-one-at-any-price.md` — the audit set is
  defined by tracker state, enumerated mechanically (below), not intuited from script names.

### Dormant-probe audit (issue ask (c) — enumerated, not intuited)

Method: for every `scripts/followthroughs/*.sh` (non-test), extract the tracker `#N` from its
header and read `gh issue view N --json state,closedAt,stateReason`. Trackers closed as COMPLETED
older than `CLOSED_LOOKBACK_DAYS=14` (today: 2026-10-15) make the probe dormant:

| Probe | Tracker | Closed | Header claim vs reality | Disposition |
|---|---|---|---|---|
| `zot-log-channel-7440.sh` | #7455 | 2026-08-13 | "stays enrolled as a REGRESSION detector" — false | Header corrected; standing check → new alert |
| `dashboard-cold-tiers-8978.sh` | #8978 | 2026-09-29 | "the regression class is watched *continuously*" — false post-close | Header status note |
| `inngest-watchdog-functions-query-6407.sh` | #6407 | 2026-07-14 | soak-gate framing; exit-1 arm described as the regression the soak closes | Header status note (dormant by design post-PASS; flag for retire-at-next-touch) |
| `web2-standby-soak-6459.sh` | #6459 | 2026-08-14 | exit-1 arm = dark-standby regression verdict | Header status note (web-2's liveness is now carried by its armed heartbeats, not this file) |
| `cla-evidence-hardening-3950.sh` | #3950 | 2026-06-02 | part (a) "regression guard" runs only while invoked | Header status note |
| `inngest-zot-client-authz-6500.sh` | #6500 | 2026-09-24 | already honest ("the sweeper … no longer runs this probe") | No change — cited as the correct pattern |
| `luks-monitor-host-timer-8706.sh` | #8706 | 2026-10-01 | `RETIREMENT:` line instructs deleting script + suite once #8706 closes | Delete script + `.test.sh` + remove the `follow-through` label on #8706 (its own instruction; lookback expired 10-15) |

Re-verify this table at work time (`for` loop + `gh issue view`); a tracker closed in the
interim joins the audit.

### Related issues/PRs

- Refs: #7455 (dead tracker), #7456 (post-delivery follow-ups — unchanged), #7530 (sibling
  clientIP invariant → alert precedent), #9139 (step-call leg modelling), #8698 (shared decoder —
  unchanged), #10138, #9757/#10093/#10120 (#10356's arc — no file overlap), #8408 (#10320 batch).
- Conventions: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`,
  ADR-218 (Logs alerts are Terraform-managed), ADR-184 (the shipper ADR carrying the stale claim).

## Proposed Solution

**Part A — dormant-detector contract (#10321).** Move the credential-shape check to a standing,
Terraform-managed Better Stack Logs alert `registry_zot_log_credential_shape`
(`logtail_exploration` + `logtail_exploration_alert`, name `soleur-registry-zot-log-credential-shape-prd`)
mirroring `registry_store_not_luks`'s structure and `registry_clientip_not_rfc1918`'s paging
semantics (per the #10320 plan: check 300s / query 900s / recovery 1800s, `value = 0` +
`higher_than` — one credential-shaped row is a page, no count floor). The predicate replicates the
probe's three shapes over `SOLEUR_ZOT_LOG` envelope rows on `local.vector_prd_source_id`
(source 2457081): (a) any `Authorization:[…]` value that is neither `***`-masked nor `REDACTED`
(ClickHouse `extractAll` + `arrayExists`; the probe's per-occurrence decoy walk translates to the
all-values extract), (b) `dp\.(pt|st|sa|ct)\.` followed by ≥16 token-charset chars, (c)
`\$2[aby]\$[0-9][0-9]\$`. Unlike the probe the alert grades **every** matching row, not just the
newest boot's span — that is the correct regression semantics (any leaked shape = incident);
the probe's boot-scoping existed to attribute delivery, which a standing detector doesn't need.
The probe file stays (its decode/grading machinery is still the best manual deep-dive tool);
its header is corrected to state the standing check lives in the alert and that the sweeper no
longer invokes it. `followthrough-convention.md` gains the contract clause. The audit table's
dispositions land (header notes; #8706's probe deleted per its own RETIREMENT).

**Part B — #10136 in-repo scope.** (1) `list-runs.ts`: add a local `hashSigningKey`
(`signkey-[\w]+-` prefix preserved, `sha256(hex.decode(rest))` re-appended — a comment pins parity
to `node_modules/inngest/helpers/strings.js`, which the package exports map does not expose) and
send `Authorization: Bearer ${hashSigningKey(signingKey)}` on both fetches; a new vitest file pins
the transform and asserts the raw key never appears in the emitted header. (2) Ledger
`connections[]` Inngest row: `does_not_defend` rewritten — the hashed-signing-key claim becomes
true post-fix (dated), "step outputs" narrowed to event payloads with step-output transport marked
"not asserted on this link (tracked in #9139)"; the three `referred to the 2026-10-24 CLO ruling`
exception strings stay verbatim (recorded-as-history per #10326's disposition; the ruling is still
future-dated). (3) No edit to `hcloud_volume.git_data`, no `docs/legal/**` edits, no infra mutation.
(4) PR body + a comment on #10136 enumerate residuals: TLS remediation, the measured nftables
re-read (proposed as the verification evidence; execution operator-gated), the 2026-10-24 CLO
re-ruling, NFR-026 still reading Implemented, the possible need to rotate `INNGEST_SIGNING_KEY`
(now-visible exposure window: the raw key rode plaintext requests until this fix deploys — a CLO/
operator call, not in-scope), and whether `/api/dashboard/runs` reaches `/v1/*` on the dedicated
host at all (sibling question #9073).

**Sequencing with open siblings.** This plan's `betterstack-logs-alerts.tf`, workflow and
mutation-test edits MUST be authored against `origin/main` as it stands after #10320 merges (the
alert-count assertion it bumps, the `Standing alarms` runbook row and the ADR-218 amendment all
name counts/#7530 artefacts that move under #10320). If #10320 is still open at work time: author
against current main, place the new alert block at the end of the `logtail` section (new lines,
not interleaved edits), and carry the rebase note in the PR body. The ledger `connections[]` rows
and PR #10352's `hcloud_volume.git_data` stores-row edit are disjoint regions of the same file —
different JSON object; conflict risk is low but the file is shared, so the work phase diffs the
merged main's version of that row set before editing.

## Technical Considerations

- **Attack surface enumeration (security fix):** the Inngest read path's credential surface is
  exactly the two `fetch` calls in `list-runs.ts` (`/v1/events`, `/v1/events/:id/runs`) — both take
  `Authorization: Bearer ${signingKey}` today and both take the hashed value post-fix. Other
  consumers of `INNGEST_SIGNING_KEY` on the app side: the SDK client (`server/inngest/client.ts`)
  already sends the hashed form as `authToken` (verified above). The `INNGEST_EVENT_KEY` send path
  (`/e/<key>`) is a different credential, unchanged and already named in the row. TR7
  (`test/lint/inngest-key-server-only.test.ts`) greps `app/(dashboard)/**` + `components/**` for the
  env-var name — `lib/inngest/` is outside its roots; no sweep needed, verified.
- **`hashSigningKey` replica correctness:** `signkey-prod-<64hex>` → `signkey-prod-<sha256>`;
  a non-`signkey-`-prefixed value or non-hex body must fail closed (throw a named error, matching
  the SDK's `hex.decode` failure) rather than send a malformed bearer — the test covers both.
- **Alert predicate expressiveness:** ClickHouse `match()` is RE2 — no lookahead. The masked-value
  exemption is expressed as `NOT match(value, '^(\*+|REDACTED)')` over `extractAll` output; a
  literal `Authorization:[]` empty value is benign and excluded. The drift suite asserts each arm
  by mutating copies of the `.tf` (never the tracked file) through env-overridable paths.
- **Better Stack free-tier count:** #10320's plan records the possibility that the vendor refuses
  the 14th alert ("if Better Stack refuses the fourteenth alert that refusal is the free-tier
  count-cap measurement"). This plan adds the 15th — apply-time capacity is operator-gated; the
  `### Vendor-tier reality check` subsection names it, and a refusal is surfaced as the apply
  output, not hidden.
- **Alert vs probe grading semantics:** the probe's exit-1 arm was boot-scoped because it doubled
  as the delivery grader; the alert deliberately has no boot notion. The probe's *CANNOT ESTABLISH*
  arm for credential shapes outside the gradable span is the alert's normal firing shape — the
  alert does not need to attribute a generation.

## Implementation Phases

### Phase 1 — Inngest raw-key fix + test (code)

1. `apps/web-platform/lib/inngest/list-runs.ts`: add `hashSigningKey` (module-private,
   `node:crypto` `createHash`), compute once, use on both fetches. Update the module header
   comment: the raw key no longer reaches the wire on this path; cite the server-side acceptance
   (`pkg/authn/signing_key_strategy.go` `HandleSigningKey` at v1.45.1) and the ledger row. Keep
   the "THAT IS A LIVE QUESTION" paragraph — the `/v1` reachability question is #9073's, unchanged.
2. New `apps/web-platform/test/lib/inngest-list-runs-signing-key.test.ts` (vitest): stub `fetch`;
   with `INNGEST_SIGNING_KEY=signkey-prod-<64-hex fixture>` assert every captured `Authorization`
   equals `signkey-prod-<sha256(fixture)>` and contains no substring of the raw key; non-prefixed
   hex key → bare sha256 bearer; non-hex key → thrown error, no request emitted. Verify the
   fixture vector against the SDK's own `hashSigningKey` (compute with `node` using
   `apps/web-platform/node_modules/inngest/helpers/strings.js` semantics, hard-code the digest).

### Phase 2 — Ledger wording reconciliation (data)

3. `scripts/encryption-posture-ledger.json`, `connections[]`, the
   `web-platform app (web hosts) <-> dedicated inngest host` row ONLY:
   - `does_not_defend`: replace "the hashed signing key (Bearer signkey-prod-<sha256>), event
     payloads and step outputs; … The raw signing key never crosses the wire (Inngest->app
     requests carry only an HMAC)." with wording that is true post-fix and correctly scoped:
     the app→inngest direction carries the hashed signing key (`signkey-prod-<sha256>`) on
     run-list reads — true as of this PR — plus `INNGEST_EVENT_KEY` and event payloads; step
     outputs' transport is "not asserted on this link (step execution is attributed to the
     Cloudflare serve-URL leg, #9139)". Dated.
   - The `exception.justification` strings ("referred to the 2026-10-24 CLO ruling") are left
     verbatim on all three rows — history per #10326's disposition.
   - Do not touch `hcloud_volume.git_data` or any other row. `lint-encryption-posture.py` must
     pass post-edit (the polarity gap #10326 noted — published-disclosure vs `not-publicly-claimed`
     — is unchanged: the value stays `not-publicly-claimed`).

### Phase 3 — Standing alert for the credential-shape check (infra)

4. `apps/web-platform/infra/betterstack-logs-alerts.tf`: append at the end of the logtail section —
   `local.registry_zot_log_credential_shape_sql`, `logtail_exploration.registry_zot_log_credential_shape`,
   `logtail_exploration_alert.registry_zot_log_credential_shape` (`soleur-registry-zot-log-credential-shape-prd`,
   `local.vector_prd_source_id`, source 2457081 anchor `startsWith(raw, '{"message":"SOLEUR_ZOT_LOG ')`).
   Comment block documents the three shapes, the probe lineage (#7455/#10321), and why an alert
   and not a probe (ADR-218 signal class; dormant-probe contract).
5. `.github/workflows/apply-web-platform-infra.yml`: two `-target=` lines beside the sibling
   (`logtail_exploration.registry_zot_log_credential_shape`,
   `logtail_exploration_alert.registry_zot_log_credential_shape`) — untargeted resources are never
   applied (#5566).
6. New `apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh` modelled on
   `registry-store-not-luks-alert.test.sh` (mutations on COPIES via `REGCREDSHAPE_TF`/`_WF` env
   overrides); register the suite in `.github/workflows/infra-validation.yml` (step + any `paths:`
   entry it reads).
7. `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`: bump the
   `values = [local.vector_prd_source_id]` source-count assertion by one — **re-measure the on-main
   value at work time** (13 today; #10320 makes it 14; this PR makes it 15 — assert whatever main
   carries plus one, with the pre/post values in the PR body).
8. `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`: row under "Standing
   alarms over this source". New runbook
   `knowledge-base/engineering/operations/runbooks/registry-zot-credential-shape-10321.md`:
   what fires it, the rotate-first rule (the affected credential rotates BEFORE the `redact()` fix,
   per the probe's own "Next:" text), counts-only reading (never echo a matched value — same rule
   as the probe's public-comment posture), and the three shape definitions.

### Phase 4 — Dormant-detector contract + audit (docs/scripts)

9. `scripts/followthroughs/zot-log-channel-7440.sh` header: replace the "stays enrolled as a
   REGRESSION detector" claim with the true state — the sweeper's read set excludes it since
   ~2026-08-27 (`--state open` + 14-day closed lookback); the standing credential-shape check lives
   in `logtail_exploration_alert.registry_zot_log_credential_shape`; this file remains the manual
   deep-grader (runnable with `BETTERSTACK_QUERY_*` env under `scripts/betterstack-query.sh`).
10. `ADR-184-registry-host-container-log-shipper.md`: dated amendment — the enrollment paragraph
    (~line 321) is corrected: the dedicated tracker closed and the sweeper's lookback expired, so
    the probe is dormant; regression detection moved to the standing alert.
11. `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`: new clause in the
    sharp-edges list — a tracker closed on PASS drops its probe out of the sweep after
    `CLOSED_LOOKBACK_DAYS` (14) days; a check meant to outlive its tracker is NOT a follow-through
    probe — enroll it as a standing alert (ADR-218 pattern) and say so in the probe's header; a
    probe whose header claims post-close detection while its tracker is closed is a defect class
    (#10321).
12. Audit dispositions from the Research Insights table (re-verified at work time):
    `dashboard-cold-tiers-8978.sh`, `inngest-watchdog-functions-query-6407.sh`,
    `web2-standby-soak-6459.sh`, `cla-evidence-hardening-3950.sh` each gain a dated header status
    note ("tracker #N closed <date>; sweeps ended <date+14d>; this file is dormant by design —
    any standing check it implies lives in <named successor or none>"). Delete
    `scripts/followthroughs/luks-monitor-host-timer-8706.sh` + `.test.sh` per its own `RETIREMENT:`
    line and remove the `follow-through` label on #8706 (comment noting the retirement).
    `inngest-zot-client-authz-6500.sh` unchanged (already honest).
13. `ADR-218`: dated amendment — 15th managed Logs alert (re-derive the count at write time);
    signal class: credential-shape content match over producer-anchored rows; the note that a
    follow-through probe's enrollment dies with its tracker's lookback.

### Phase 5 — Residuals and close-out

14. PR body: `Closes #10321`, `Ref #10136`, `Ref #7455`, `Ref #7530`, `Ref #9139`; a
    `## Residuals on #10136` block listing every not-done item (TLS, nftables re-read, CLO
    10-24 re-ruling, NFR-026, signing-key-rotation decision, `/v1` reachability under #9073);
    a `## Sequencing` note on the #10320/#10352/#10356 overlap reads.
15. Post-merge comment on #10136 recording what this PR changed and what remains (no close).
    `gh issue edit 8706 --remove-label follow-through` + retirement comment (per the probe's own
    instruction). Post-merge: verify the next `scheduled-followthrough-sweeper.yml` run is clean
    (the deleted probe's directive is gone with the label); verify `terraform plan` shows only the
    two new `logtail` resources pending — the APPLY itself is operator-gated.

## Files to Edit

- `apps/web-platform/lib/inngest/list-runs.ts`
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` (count bump; re-measure)
- `apps/web-platform/infra/betterstack-logs-alerts.tf` (append-only at the logtail section end)
- `.github/workflows/apply-web-platform-infra.yml` (two `-target=` lines)
- `.github/workflows/infra-validation.yml` (suite registration)
- `scripts/encryption-posture-ledger.json` (the Inngest `connections[]` row only — NOT `hcloud_volume.git_data`)
- `scripts/followthroughs/zot-log-channel-7440.sh` (header comment only)
- `scripts/followthroughs/dashboard-cold-tiers-8978.sh`, `inngest-watchdog-functions-query-6407.sh`,
  `web2-standby-soak-6459.sh`, `cla-evidence-hardening-3950.sh` (header status notes only)
- `knowledge-base/engineering/architecture/decisions/ADR-184-registry-host-container-log-shipper.md` (dated amendment)
- `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md` (dated amendment)
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` (contract clause)
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (standing-alarms row)

## Files to Create

- `apps/web-platform/test/lib/inngest-list-runs-signing-key.test.ts`
- `apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh`
- `knowledge-base/engineering/operations/runbooks/registry-zot-credential-shape-10321.md`
- `knowledge-base/project/specs/feat-one-shot-10321-10136-dormant-probe-ledger/{tasks.md,decision-challenges.md}` (pipeline artifacts)

## Files to Delete

- `scripts/followthroughs/luks-monitor-host-timer-8706.sh` and `scripts/followthroughs/luks-monitor-host-timer-8706.test.sh` (per the script's own `RETIREMENT:` instruction — tracker #8706 closed 2026-10-01; verify no `git grep -l` consumer remains at work time)

## User-Brand Impact

- **If this lands broken, the user experiences:** the audit viewer's Inngest run panel (the Art. 15
  access route behind `GET /api/dashboard/runs`) keeps returning 502 or starts failing in a new way
  if the hashed bearer were rejected — mitigated by the verified server-side dual acceptance
  (HandleSigningKey compares both forms at the pinned version); the alert path landing broken means
  a registry-plane credential leak stays invisible again — mitigated by the drift suite.
- **If this leaks, the user's data is exposed via:** a passive on-net reader of `10.0.1.0/24`
  holding a sniffed raw `INNGEST_SIGNING_KEY` could, combined with private-IP origin, read Inngest
  run/event data (user content) — the pre-fix exposure this PR removes going forward; rotation of
  the already-flown key is the flagged residual. A real credential shape on source 2457081 that the
  dormant probe never saw is the observability exposure the alert removes.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the zot push credential protects the image supply chain
  and the Inngest hop carries user content — one leaked row is one user's exposure; the probe's own
  header already declared `single-user incident`.

CPO sign-off note: the threshold resolves to `single-user incident`, so `soleur:engineering:review:user-impact-reviewer` runs at review time (review-skill conditional-agent block). Plan-time CPO sign-off per Phase 2.6: the change reduces exposure and adds no user-facing surface; flagged for the review-phase verifier.

## Observability

```yaml
liveness_signal:
  what: "logtail_exploration_alert.registry_zot_log_credential_shape (created by the merge-SHA push apply — see Apply path) + SOLEUR_ZOT_LOG rows continuing to arrive on source 2457081 (the alert's silence-with-dark-channel gap is covered by the existing registry heartbeats: betteruptime_heartbeat.registry_prd and the ci/zot-telemetry-silent arm)"
  cadence: "Better Stack evaluation per the alert's check_period (300 s) over a 900 s query window"
  alert_target: "operator email via the alert's incident_cause/runbook wiring (same channel as registry_store_not_luks)"
  configured_in: "apps/web-platform/infra/betterstack-logs-alerts.tf (new resources + -target= lines in .github/workflows/apply-web-platform-infra.yml)"

error_reporting:
  destination: "the alert pages directly (Better Stack); app-side fetch failures keep reporting to Sentry via route.ts's Sentry.captureException (surface audit-runs-proxy) — unchanged"
  fail_loud: "a credential-shaped SOLEUR_ZOT_LOG row fires the alert with a runbook pointer; a broken exploration query errors the alert rather than silently passing"

failure_modes:
  - mode: "alert predicate too narrow (a fourth credential shape appears)"
    detection: "the probe file remains the manual deep-grader; the runbook names the three shapes and the audit cadence"
    alert_route: "manual re-grade + follow-up issue; the alert cannot see shapes it was never taught (named residual)"
  - mode: "alert resource declared but never applied (untargeted)"
    detection: "the mutation suite asserts both -target= lines exist in apply-web-platform-infra.yml"
    alert_route: "CI failure on the suite"
  - mode: "Better Stack refuses the 15th alert at apply (vendor tier cap)"
    detection: "apply job failure output names the refusal"
    alert_route: "operator-gated apply decision; recorded on #10321"
  - mode: "hashed bearer rejected by a future inngest version bump"
    detection: "list-runs fetch fails -> 502 + Sentry captureException on surface audit-runs-proxy"
    alert_route: "Sentry issue on the existing tag"

logs:
  where: "the probe's manual output (stderr) when invoked; the alert's incident record in Better Stack; app errors in the existing pino/Sentry path"
  retention: "Better Stack source 2457081 retains 90 d hot + archive (register #7772)"

discoverability_test:
  command: "grep -c 'createHash' apps/web-platform/lib/inngest/list-runs.ts"
  expected_output: "1"
```

## Encryption Posture

```yaml
at_rest: []   # no new store; no store row edited (hcloud_volume.git_data is PR #10352's)
in_transit:
  - connection: "web-platform app (web hosts) -> dedicated inngest host 10.0.1.40:8288 (run-list reads)"
    enforced_at: "apps/web-platform/lib/inngest/list-runs.ts (Authorization header)"
    tls: "none (plain HTTP on the Hetzner private network by design, ADR-100) — unchanged; TLS is the 2026-10-24 CLO ruling's concern, not this PR's"
    cert_verification: "off"
    does_not_defend: "a passive on-net attacker reads INNGEST_EVENT_KEY, the HASHED signing key (post-fix; raw pre-fix), event payloads; step-output transport not asserted on this link (#9139)"
    disclosed_as: "not-publicly-claimed (unchanged pending the CLO re-ruling)"
exception:
  justification: "unchanged private-network-only plaintext exception, renewed to 2026-11-12 by #10132 pending the 2026-10-24 CLO ruling; this PR changes only the credential FORM on the wire"
  tracking_issue: "#10136"
  reevaluate_when: "unchanged (the row's own text)"
  expires_on: "2026-11-12"
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/betterstack-logs-alerts.tf` — one `local` SQL, one `logtail_exploration`,
  one `logtail_exploration_alert`. Provider `logtail` already pinned in `main.tf` (ADR-218); no new
  provider, variable, or secret.
- `.github/workflows/apply-web-platform-infra.yml` — two `-target=` lines (an untargeted resource
  is never applied, #5566).

### Apply path

- **Merging this PR mutates production observability exactly once, automatically:**
  `apply-web-platform-infra.yml` is push-triggered on `main` for `apps/web-platform/infra/**`
  (`on.push.paths`, lines 16-20), and the `-target=` lines added in Phase 3 put the new pair in
  the apply job's filter — so the merge-SHA push run creates `logtail_exploration` +
  `logtail_exploration_alert` `registry_zot_log_credential_shape` with no dispatch and no
  operator step. That is the intended outcome (the standing check goes live at merge), stated
  here so it is not a surprise: the only post-merge prod change is two Better Stack alert
  objects. This PR performs no manual apply, no `workflow_dispatch`, no Doppler write. Blast
  radius: two alert resources only — no host, volume, firewall, or credential is touched;
  deleting the pair removes only the alarm. Other workflows that can apply the same root: the
  `workflow_dispatch` arm of the same file (operator-gated) — enumerated, no other workflow
  reaches this root.

### Host fan-out

- None — no `terraform_data` SSH provisioner, no host touch.

### Distinctness / drift safeguards

- Alert name `soleur-registry-zot-log-credential-shape-prd` is distinct from every existing
  resource; SQL anchored to `local.vector_prd_source_id` only (dev source unaffected).
- The mutation suite runs on COPIES (`REGCREDSHAPE_TF`/`REGCREDSHAPE_WF` env overrides) — the
  tracked files are never written, so a concurrent sibling-PR edit cannot be clobbered.

### Vendor-tier reality check

- #10320's plan records the possibility that Better Stack's free tier rejects a 14th alert; this
  is the 15th. If apply refuses on count grounds, the refusal is the measurement — surface it on
  #10321 and pick between a paid-tier decision (operator: money) and the rejected sweeper-route
  alternative (CTO re-ruling) rather than silently shrinking the predicate.

## Guard Contract

### Guard 1 — `registry_zot_log_credential_shape` alert predicate

**Property.** Every `SOLEUR_ZOT_LOG` envelope row on source 2457081 carrying any of the three
credential shapes fires the alert — an unmasked `Authorization` value, a `dp.(pt|st|sa|ct).` token
prefix with a substantive run, or a bcrypt `$2[aby]$` hash.

**Assembly.** The predicate in `registry_zot_log_credential_shape_sql` is the chokepoint — all
rows enter through the `startsWith(raw, '{"message":"SOLEUR_ZOT_LOG ')` anchor and the three shape
disjuncts; the resource pair plus BOTH `-target=` lines is the second assembly (an untargeted
resource never exists, #5566); the infra-validation registration is the third (a suite that never
runs guards nothing). Not covered, named: credential shapes outside the three patterns, rows the
shipper's rate cap never emitted, a leak on a different source, and Better Stack evaluator downtime
(the heartbeats' concern, not this alert's).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the bcrypt disjunct (`$2[aby]$` arm) — a bcrypt-bearing row no longer fires | RED |
| 2 | Drop the mask exemption (`NOT match(value, '(\*+\|REDACTED)')`) — every masked row pages; assert the suite's masked fixture stays green-PASS so the exemption is load-bearing | RED |
| 3 | Remove the envelope anchor (`startsWith(raw, '{"message":"SOLEUR_ZOT_LOG ')`) — a journald row QUOTING the marker now matches | RED |
| 4 | Remove either `-target=` line — the resource is declared but never applied | RED |
| 5 | Suite row (harness): the mutation harness writes to the tracked file instead of a copy — assert it refuses / operates on `REGCREDSHAPE_TF` only | RED on real file, then assert tracked file untouched |
| 6 | Must-PASS, non-canonical: a fixture row with `Authorization:[******]` AND `dp.st.x` (insubstantive run <16 chars) — both shapes present, neither qualifying — must not fire | GREEN |

### Guard 2 — hashed-bearer wire assertion

**Property.** No request `listInngestRunsForFounder` emits carries the raw signing key anywhere in
its `Authorization` header.

**Assembly.** The two `fetch` calls in `list-runs.ts` are the chokepoint (both verified: only call
sites in the module); the header composition is the single field the property quantifies over.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert one fetch to `Bearer ${signingKey}` — only one of two call sites raw | RED |
| 2 | `hashSigningKey` returns the input unchanged — both calls send raw | RED |
| 3 | Test asserts only `startsWith('signkey-prod-')` (dispatch checks shape, not the hash) — a `signkey-prod-<rawhex>` passthrough survives | RED (asserts exact digest equality, not shape) |
| 4 | Must-PASS, non-canonical: `INNGEST_SIGNING_KEY` without the `signkey-prod-` prefix (bare hex) — SDK semantics: bare sha256 bearer, still never the raw value | GREEN |

## Architecture Decision (ADR/C4)

### ADR

- `ADR-218` (`native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider`):
  dated amendment — the managed-alert census gains `registry_zot_log_credential_shape` (re-derive
  the ordinal count at write time; #10320 adds the 14th, this adds the next) and its signal class:
  credential-shape content match over producer-anchored envelope rows. The amendment records the
  dormant-probe rule it codifies (#10321): a check meant to outlive its tracker is an alert, not a
  probe.
- `ADR-184` (`registry-host-container-log-shipper`): dated amendment correcting the ~line-321
  enrollment paragraph — the dedicated tracker closed and the sweeper's lookback expired; the
  probe is dormant and the regression arm is discharged by the standing alert.
- No NEW architectural decision: this plan applies the already-decided alert substrate (ADR-218)
  and corrects a stale ADR claim — an amendment task, not a new ordinal.

### C4 views

- All three model files read (`model.c4`, `views.c4`, `spec.c4`): `betterstack` system exists
  (model.c4:458) including the `logtail_exploration_alert` naming convention already cited inside
  its description (`inngest_luks_wrong_volume`); the registry→betterstack shipper edge and the
  `hetzner -> betterstack` edges exist; no new external actor, external system, container, or
  actor↔surface relationship is introduced (the alert is a resource inside the modeled vendor
  system; the Inngest link and actors are already modeled). Conclusion: **no C4 impact** —
  enumeration checked: external actors (none added), external systems (Better Stack already
  modeled), data stores (none added), access relationships (unchanged). The `does_not_defend`
  wording change does not alter the `hetzner`/inngest edges' technology strings (they already say
  the hop is plain HTTP).

### Sequencing

- The ADR-218/ADR-184 amendments land in this PR, not a follow-up issue.

## Domain Review

**Domains relevant:** Legal (CLO-held compliance surfaces — ledger wording is a posture record
adjacent to the 2026-10-24 ruling), Engineering/infra (alert substrate, sweeper contract).

### Legal

**Status:** reviewed (inline — the planning subagent cannot spawn `soleur:legal:clo`; the
CLO-ruling context is read directly from the issue record)
**Assessment:** no `docs/legal/**` edit (CLO hold honored); ledger `disclosed_as` stays
`not-publicly-claimed`; the exception strings' "referred to the 2026-10-24 CLO ruling" text is
preserved as history per #10326's recorded disposition; the raw-key exposure window and the
rotation question are surfaced as residuals on #10136 for the CLO's 10-24 re-ruling rather than
decided here (legal-risk = operator/CLO class). The GDPR/compliance gate's advisory read: no new
processing activity, no new data sink, no regulated-schema change — the fix *reduces* exposure of
a credential adjacent to user-content reads.

### Product/UX Gate

**Tier:** none — no user-facing surface created or modified (a server-only header value changes
form; `components/**/*.tsx`/`app/**/page.tsx`/`app/**/layout.tsx` untouched; the mechanical
UI-surface scan of Files to Edit/Create returns zero matches).

**Brainstorm-recommended specialists:** none (no brainstorm preceded this pipeline run).

## Open Code-Review Overlap

None (open `code-review`-labelled issues were queried by body-contains against every planned
path — `apps/web-platform/lib/inngest/list-runs.ts`, `betterstack-logs-alerts.tf`,
`encryption-posture-ledger.json`, the followthrough scripts — no match; the relevant collision
surface is sibling PRs #10320/#10352/#10356, handled under Proposed Solution → Sequencing).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "correct the false header claim in zot-log-channel-7440.sh (and ADR-184 if it repeats it)" [issue #10321] | Phase 4 items 9-10 | mapped |
| 2 | "decide the standing vehicle for the credential-shape check … a Better Stack alert on shipped rows … a scheduled workflow, or a re-opened tracker with open-ended lookback" [issue #10321] | Phase 3 items 4-8; decision-challenges row 1 | mapped |
| 3 | "audit the OTHER probes under scripts/followthroughs/ whose headers claim regression-detector status after their tracker closed" [issue #10321] | Research Insights audit table + Phase 4 items 11-12 | mapped |
| 4 | "Fix the dormant-detector contract — the sweeper's read surface OR the probe's enrollment — NOT by reopening the dead tracker" [issue #10321] | Phase 4 item 11 (convention clause) + Phase 3 (alert) | mapped |
| 5 | "hash the bearer the way the Inngest client does (investigate how the client hashes: signkey-prod-<sha256>), or move the read to TLS" [issue #10136 via #10326 comment] | Phase 1 items 1-2 (hash; TLS is CLO-residual) | mapped |
| 6 | "step-outputs wording in the ledger is broader than the CTO code read supports … reconcile or mark transport 'not asserted'" [issue #10136 via #10326 comment] | Phase 2 item 3 | mapped |
| 7 | "the three ledger exception strings still say 'referred to the 2026-10-24 CLO ruling' — left as history" [issue #10136 via #10326 comment] | Phase 2 item 3 (explicitly left verbatim) | mapped |
| 8 | "scope the PR to what is fixable in-repo … and record the rest as explicit residuals on #10136" [brief] | Phase 5 items 14-15 | mapped |
| 9 | "do not touch that row [hcloud_volume.git_data]; no docs/legal edits; no terraform apply, no workflow dispatch, no Doppler writes" [brief] | Constraints restated in Overview + Phase 2/3/5 boundaries | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| New `logtail_exploration`/`_alert` pair | "a Better Stack alert on shipped rows (registry_store_not_luks / registry_clientip_not_rfc1918 pattern)" (#10321) | asked |
| `hashSigningKey` replica + test | "hash the bearer the way the Inngest client does" (#10136 comment) | asked |
| Ledger wording reconciliation | "reconcile or mark transport 'not asserted'" (#10136 comment) | asked |
| Convention clause + per-probe header notes | "audit the OTHER probes … whose headers claim regression-detector status" (#10321) | asked |
| luks-monitor-host-timer-8706.sh deletion | — | inferred — justification: the script's own `RETIREMENT:` line instructs deletion on tracker close and the audit enumerated it; alternative (leave dormant) keeps dead weight the file itself says to remove |
| `followthrough-convention.md` edit | — | inferred — justification: the dormant-detector contract fix needs a written home or the next probe repeats the claim (#10321 root cause) |
| ADR-218/ADR-184 amendments | — | inferred — justification: plan Phase 2.10, recorded architecture must not lie about probe enrollment |
| Runbook + betterstack-log-query row | — | inferred — justification: every standing alert in this file family carries its runbook entry (registry_store_not_luks pattern) |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform`, `scripts`, `knowledge-base`, `.github`
- Planned files: 19 (edit+create+delete) | Estimated changed lines: ~700 (predominantly the two new suites + runbook + header prose)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: **single PR** — the subsystem-root count trips the threshold on paper, but the
  two issues share the zot+Inngest surface by design (the brief fixes the pairing), and splitting
  the dormant-detector fix from the ledger/code reconciliation would put two #10136-bound edits in
  series for no isolation gain; the diff is mostly comments, one JSON value, and two test files.

## Acceptance Criteria

- [ ] `grep -n 'stays enrolled as a REGRESSION detector' scripts/followthroughs/zot-log-channel-7440.sh` prints nothing; a dated correction names the alert as the standing check and the sweeper's read-set bound (open + `CLOSED_LOOKBACK_DAYS`) as the enrollment truth.
- [ ] `apps/web-platform/infra/betterstack-logs-alerts.tf` declares `logtail_exploration.registry_zot_log_credential_shape` + `logtail_exploration_alert.registry_zot_log_credential_shape` (name `soleur-registry-zot-log-credential-shape-prd`, `local.vector_prd_source_id`, `SOLEUR_ZOT_LOG` envelope anchor, the three shape disjuncts, paging semantics mirroring `registry_store_not_luks`/`registry_clientip_not_rfc1918`).
- [ ] `.github/workflows/apply-web-platform-infra.yml` carries both `-target=` lines; `.github/workflows/infra-validation.yml` registers `registry-zot-credential-shape-alert.test.sh`; `bash apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh` is green, and every mutation row was observed RED against the unmutated-meaning mutation first.
- [ ] `bun test`/`vitest` run of `apps/web-platform/test/lib/inngest-list-runs-signing-key.test.ts` is green; the stubbed fetch sees only `signkey-prod-<sha256(fixture)>` and never the fixture raw key (negative assertion included).
- [ ] `apps/web-platform/lib/inngest/list-runs.ts` contains no `Bearer ${signingKey}` (raw) site: `grep -n 'Bearer \${signingKey}' apps/web-platform/lib/inngest/list-runs.ts` prints nothing.
- [ ] `python3 scripts/lint-encryption-posture.py` passes; `jq` on the ledger shows the Inngest `connections[]` row's `does_not_defend` names the hashed bearer as post-fix truth with a date, narrows "step outputs" to event payloads + "not asserted on this link (#9139)", and leaves `expires_on: 2026-11-12`, `tracking_issue: #10136`, `disclosed_as: not-publicly-claimed` unchanged; `git diff` on the file touches only that one row.
- [ ] `hcloud_volume.git_data` row, `docs/legal/**`, all `stores[]` rows: untouched — `git diff --name-only origin/main...HEAD` (merge-base, not the moving tip) contains none of them.
- [ ] `followthrough-convention.md` gains the dormant-detector clause; each audited dormant probe's header carries a dated status note or the file is deleted (`luks-monitor-host-timer-8706.{sh,test.sh}` gone, `git grep -l luks-monitor-host-timer-8706` prints nothing outside planning artifacts and the #8706 issue).
- [ ] ADR-218 and ADR-184 carry dated amendments; `bash scripts/check-adr-ordinals.sh` passes (no ordinal claimed).
- [ ] `npx markdownlint-cli2` on touched markdown; `bash scripts/lint-orphan-test-suites.sh` clean; `python3 scripts/lint-shell-trace-credential-refusal.py` clean for touched shell files; `python3 scripts/lint-guard-contract.py <this plan>` passes.
- [ ] PR body: `Closes #10321`; `Ref` (not Closes) #10136; `## Residuals on #10136` enumerating TLS remediation, the nftables re-read (gated on authority the pipeline lacks), the 2026-10-24 CLO re-ruling, NFR-026, the signing-key-rotation question, and the `/v1` reachability question (#9073); a `## Sequencing` note naming the #10320/#10352/#10356 overlap reads.
- [ ] This PR performs no Terraform-managed-infra write, no workflow dispatch, no Doppler write, and no `docs/legal` edit — verified by `git diff --name-only origin/main...HEAD` (no `.tf` semantics changes beyond the additive alert pair already covered above; no `docs/legal/**` path).

## Test Scenarios

- Given a `SOLEUR_ZOT_LOG` envelope row carrying `Authorization:[dp.st.<real-token-run>]` when the alert SQL evaluates then the row matches (unit — the suite's fixture row through `extractAll`/shape arms on the SQL text).
- Given a row carrying only `Authorization:[******]` and `REDACTED` values when evaluated then no match (unit — mask exemption).
- Given a journald row that *quotes* `SOLEUR_ZOT_LOG … Authorization:[secret]` (contamination shape per the field-isolation learning) when evaluated then no match (unit — envelope anchor).
- Given `INNGEST_SIGNING_KEY=signkey-prod-<64-hex>` when `listInngestRunsForFounder` runs with a stubbed fetch then both requests carry `Bearer signkey-prod-<sha256>` and the raw key appears nowhere in emitted headers (unit).
- Given `INNGEST_SIGNING_KEY` as bare hex (no `signkey-` prefix) when the function runs then the bearer is the bare sha256 per SDK semantics (unit).
- Given `INNGEST_SIGNING_KEY` non-hex when the function runs then a named error is thrown and zero requests are emitted (unit — fail closed).
- Given the sweeper's closed-set query when #8706's label is removed then the issue is no longer enumerated (post-merge verification — read the next sweep's log).

## Success Metrics

- The credential-shape check is live independent of any issue's state (the alert exists post-apply;
  pre-merge its declaration + `-target=` wiring + suite are the verifiable artifact).
- Zero `Authorization`/`dp.`/bcrypt-shaped rows on source 2457081 attributable to `SOLEUR_ZOT_LOG`
  over the first 7 days post-apply (read via `scripts/betterstack-query.sh`, operator-gated).
- `list-runs.ts` emits only hashed bearers; ledger wording matches shipped reality.
- No probe under `scripts/followthroughs/` claims post-close detection it does not have.

## Dependencies & Risks

- **Sibling PR #10320** edits `betterstack-logs-alerts.tf`, the apply workflow, the mutation suite
  count, ADR-218 and ADR-184 — same-file overlap. Mitigation: append-only region, re-measure the
  count assertions and amendment text at work time, rebase after it merges if it lands first.
- **Sibling PR #10352** edits `scripts/encryption-posture-ledger.json` (`hcloud_volume.git_data`
  row). Disjoint region; `git diff` must show only the Inngest `connections[]` row changed.
- **Sibling PR #10356** — verified zero file overlap (its file list is `apps/web-platform/infra/*`
  probe scripts + `tests/scripts/test-argv-bearer-sweep.sh` + ADR-280/232 only).
- **Vendor tier cap** — a 15th alert may be refused at apply; the refusal surfaces at the
  operator-gated apply, not silently in CI.
- **The `/v1` reachability question** — if `/v1/*` is loopback-gated on the dedicated host the way
  #4708 measured on the co-located one, `GET /api/dashboard/runs` may already be dead there; the
  hashed-bearer fix is correct either way (the credential rides the request, not the response) and
  the reachability question is #9073's — recorded as a residual, not fixed here.
- **Key rotation** — the raw key may already be in flight on recorded plaintext requests; rotation
  is an operator/CLO decision (credential rotation + legal-risk class), listed as a residual.

## References & Research

- Probe contract: `scripts/sweep-followthroughs.sh` (open arm `:839-895`; closed arm `:680-770`;
  lookback `:48`, `:983-987`), `scripts/followthroughs/zot-log-channel-7440.sh` (header `:1-60`;
  leak arms `:326-360`, `:555-600`), `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`.
- Alert pattern: `apps/web-platform/infra/betterstack-logs-alerts.tf` (`registry_store_not_luks`
  `:364-437`; paging-semantics comment `:1021-1103`), `apps/web-platform/test/infra/registry-store-not-luks-alert.test.sh`,
  ADR-218; the #7530 alert shape in open PR #10320's plan (`2026-10-14-fix-registry-phase2-batch-htpasswd-stdin-clientip-alert-plan.md`).
- Signing key: `apps/web-platform/node_modules/inngest/helpers/strings.js:84-95` (`hashSigningKey`),
  `InngestCommHandler.js:1387` (`authToken: this.hashedSigningKey`), `inngest-host.tf:163`
  (`signkey-prod-${random_id…}`), upstream `pkg/authn/signing_key_strategy.go` `HandleSigningKey`
  at tag `v1.45.1` (dual raw-or-hashed acceptance, constant-time compare).
- Ledger: `scripts/encryption-posture-ledger.json` `connections[]` Inngest row; CLO ruling
  2026-10-13 and #10326 comment 2026-10-14 on issue #10136; PRs #10132, #10326 (merged), #10352,
  #10356, #10320 (open siblings).
- Learnings: `2026-07-07-followthrough-and-shape-gate-silent-falseness.md`,
  `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md`,
  `2026-05-31-inngest-v1-loopback-gated-and-halt-on-stale-premise.md`,
  `2026-09-24-my-probe-accepted-more-evidence-than-its-absence-queries-could-see.md`.

## Enhancement Summary (deepen-plan)

Deepened in-place on 2026-10-15 by the planning subagent (agent fan-out unavailable in this
harness — the Task spawn tool does not exist here; all mechanical gates ran inline and the
adequacy reads were done in-session).

### Gates verified

- **4.6 User-Brand Impact** — section present, threshold `single-user incident`, concrete
  artifact + exposure vector named. PASS.
- **4.7 Observability** — trigger fires (`.tf` + `lib/` files); 5-field block present;
  `discoverability_test.command` = `grep` (allowlisted verb, no shell metachars, <15 s);
  `expected_output` is the literal `1`. PASS.
- **4.8 PAT-shaped variables** — regex sweep clean (no `var.*_token`/`TF_VAR_(GH|GITHUB)_`/literal
  token shapes; `BETTERSTACK_*`/`GH_TOKEN` appear only as existing-secret names in prose). PASS.
- **4.9 UI wireframe** — N/A: no `components/**`, `app/**/page.tsx`, or `layout.tsx` in the file
  lists; Product tier NONE. PASS.
- **4.10 Encryption Posture** — section present; `in_transit` entry carries tls/cert_verification/
  does_not_defend/disclosed_as; `cert_verification: off` carries an `exception` block with
  `tracking_issue` + `expires_on`. PASS.
- **4.11 Guard Contract** — `python3 scripts/lint-guard-contract.py` green (2 guards); adequacy
  read: Guard 1's assembly names the predicate chokepoint + the `-target=` wiring + the
  registration step (structural, not member enumeration); matrix has a dispatch row (untargeted
  resource), a second-member row (masked+insubstantive must-PASS), and a harness row (mutation on
  tracked file refused). Guard 2 binds to the two fetch call sites. PASS.
- **4.12 Scope Check** — exactly one unfenced section; 9 ask rows all `mapped`; 4 `inferred`
  provenance rows each carry a dependency/safety justification; Split Assessment derives counts
  from the file lists. PASS.
- **`lint-infra-no-human-steps.py`** — two initial flags (actor + infra-imperative co-occurrence
  in the out-of-scope bullet and the closing AC) fixed by rewording; now clean.

### Key improvements applied during deepening

- Answered "does merging THIS alone mutate production?" explicitly in §Apply path: the
  push-triggered `apply-web-platform-infra.yml` run creates the two `logtail` resources at merge —
  intended and stated, with the blast-radius bound and the other apply-bearing workflow enumerated.
- Negative-scope ACs rebound to `git diff --name-only origin/main...HEAD` (merge-base, not the
  moving tip).
- Server-side auth acceptance upgraded from "verify at work time" to source-verified:
  `pkg/authn/signing_key_strategy.go` `HandleSigningKey` at v1.45.1 accepts raw OR hashed bearer —
  the hash-the-bearer fix carries zero auth-behavior risk; recorded in decision-challenges.md as
  evidence-resolved rather than pending.
- Dormant-probe audit executed at plan time (7 trackers closed outside the 14-day lookback
  enumerated with closedAt dates and per-probe dispositions) rather than deferred to work.

### New considerations discovered

- PR #10320 (open) is the dominant collision surface — same `.tf`, both apply/validation workflows,
  the mutation-test count, ADR-218, ADR-184 — the plan's sequencing rule (append-only region +
  re-measure counts at work time) absorbs it.
- The 15th managed Logs alert may hit Better Stack's free-tier count cap (flagged by #10320's own
  plan for the 14th); the refusal path is routed to #10321 rather than hidden.
- `/v1/*` reachability of the dedicated Inngest host is an open sibling question (#9073); the fix
  is correct regardless because the credential rides the request, not the response.
