---
title: "fix: Drop mem_used_mb from the zot SOLEUR_ZOT_DISK reporter (keep mem_total_mb)"
issue: 6292
ref_issue: 6288
branch: feat-one-shot-6292-drop-mem-used-mb
type: ops-observability
classification: infra-config-change
lane: single-domain
brand_survival_threshold: none
date: 2026-07-10
---

# fix: Drop `mem_used_mb` from the zot registry `SOLEUR_ZOT_DISK` reporter (keep `mem_total_mb`) 🔭

## Overview

The zot-registry OOM telemetry work (#6288, merged 2026-07-09) enriched the deny-all-ingress,
no-SSH registry host's `SOLEUR_ZOT_DISK` self-report line with a host-memory pair —
`mem_used_mb` + `mem_total_mb` — over the explicit objection of three headless plan reviewers
(fable advisor, DHH, code-simplicity), who flagged both as low-value. The plan kept them (the
operator's stated direction is the default) and surfaced the dissent as **decision-challenge
#6292** with three options.

**The operator has now decided (#6292, option 2): drop `mem_used_mb`, keep `mem_total_mb`.**

Rationale (operator-confirmed):

- **`mem_used_mb` is host page-cache-confounded dead weight.** A ~35 GB store boot-scan pins the
  host page cache, so host "used" reads near-total regardless of whether zot's *anonymous* memory
  ever starved. OOM confirmation already keys on the page-cache-free container signals
  (`zot_anon_mb` gauge + the monotonic `zot_oom_kills` counter + `exit_code=137` + the journald
  `oom_kills_5m` backstop), so `mem_used_mb` corroborates nothing the decode path uses.
- **`mem_total_mb` earns its place** — it self-verifies the cx33 host-memory bump landed on a
  no-SSH host (reads ~8000 vs ~4000 after the immutable redeploy) and pins the host tier for
  interpreting the OOM decode rows. **KEEP.**

This is a small, well-bounded field removal on an existing observability surface: remove one
`key=value` token from the emitted line, remove its two dead `/proc/meminfo` computations, update
the structural test's field list, and sweep the living ops/observability prose that would
otherwise read as if `mem_used_mb` is still emitted. It is **not** an architectural decision and
introduces **no** new infrastructure.

The reporter line goes from 18 → 17 space-separated tokens (17 → 16 `key=value` fields) in `SOLEUR_ZOT_DISK`.

## Research Reconciliation — Spec vs. Codebase

| Claim (task / issue) | Reality (verified on this branch) | Plan response |
|---|---|---|
| Reporter emits `SOLEUR_ZOT_DISK` with `mem_used_mb` | `cloud-init-registry.yml:224` `LINE=` carries `mem_used_mb=$MEM_USED`; computed at `:176,:178` from `/proc/meminfo` | Remove the token + the two computations; keep `MEM_TOTAL_KB`/`MEM_TOTAL`/`mem_total_mb`. |
| A followthrough probe consumes `mem_used_mb` | `scripts/followthroughs/zot-restart-plateau-6288.sh` gates on `zot_anon_mb`/`exit_code`/`oom_kills_5m`/`zot_restarts` — `mem_used_mb` appears **only in comments** (`:8` field list, `:19-21` rationale) | Comment-only edit; **zero** logic/soak-semantics change. |
| "decode-table / alarm docs reference it" | The OOM decode prose (`ADR-096:148-151`, postmortem alarm rows) keys on `zot_oom_kills`/`exit_code=137`/`oom_kills_5m` — it references host `mem_used` only as a *rejected* confirmation signal, never as an emitted decode key. `betterstack-log-query.md` decode list (`:167`) omits both mem fields. | No decode-key edit. ADR-096:151 rationale KEPT (contrasts against the *concept*, does not claim emission) — verify-only. Postmortem `:58` (`mem_used_mb`/`mem_total_mb` context) reframed as historical + dropped-per-#6292. |
| Merging the `.yml` edit could force-replace the prod registry host | `hcloud_server.registry` is **not** in `apply-web-platform-infra.yml`'s push/`manual-rerun` `-target` allow-list (`:297-327`); it is `-replace`-gated behind the `registry-host-replace` dispatch (`:102`). No `lifecycle.ignore_changes=[user_data]` (`zot-registry.tf:274`) | Merge is safe (no auto-replace). Apply reaches the host only via the `registry-host-replace` dispatch (immutable redeploy). See `## Infrastructure (IaC)`. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — `SOLEUR_ZOT_DISK` is an
internal operator telemetry line shipped to Better Stack Logs; the registry serving path (image
pull/push, GHCR atomic fallback) is untouched. A broken edit's worst case is a malformed telemetry
line or a red `registry-boot-guard.test.sh`, both operator-only and caught pre-merge.

**If this leaks, the user's data is exposed via:** N/A — the change *removes* a host-memory
integer from the stream. It adds no data-processing surface and touches no personal data.

**Brand-survival threshold:** none.

- `threshold: none, reason: internal infra telemetry field removal on a no-SSH registry host — no
  user-facing surface, no regulated/personal data, no auth/API/schema path; the removed field is a
  host-memory integer.`

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)

- [ ] 0.1 Confirm the emit site: `grep -n 'mem_used_mb=\$MEM_USED' apps/web-platform/infra/cloud-init-registry.yml` → one hit at the `LINE="SOLEUR_ZOT_DISK …` assignment.
- [ ] 0.2 Confirm `MEM_USED` and `MEM_AVAIL_KB` have **no** consumers other than the removed token: `grep -n 'MEM_USED\|MEM_AVAIL_KB' apps/web-platform/infra/cloud-init-registry.yml` → only the def+use pair (`:176`, `:178`) and the `LINE=` token (`:224`). (`MEM_TOTAL_KB`/`MEM_TOTAL` MUST remain — they feed `mem_total_mb`.)
- [ ] 0.3 Confirm merge safety: `hcloud_server.registry` is absent from the push/`manual-rerun` `-target` allow-list in `.github/workflows/apply-web-platform-infra.yml` (grep the `-target=` block `:290-330`; registry replace is dispatch-only, choice `registry-host-replace` at `:102`).
- [ ] 0.4 Baseline the structural test green **before** the edit: `bash apps/web-platform/infra/registry-boot-guard.test.sh` (records the field-loop currently asserting `mem_used_mb=`).

### Phase 1 — Reporter: drop the field + its dead computations (`cloud-init-registry.yml`)

- [ ] 1.1 In the `LINE="SOLEUR_ZOT_DISK …"` assignment (`:224`), delete the `mem_used_mb=$MEM_USED ` token only. **Keep** `mem_total_mb=$MEM_TOTAL`, `zot_anon_mb`, `zot_oom_kills`, `state_status`, `oom_killed`, `exit_code`, `oom_kills_5m`, `boot_id`, `zot_last_err` exactly as-is.
- [ ] 1.2 Delete the two now-dead computations: `MEM_AVAIL_KB=…` (`:176`) and the `MEM_USED=…` branch (`:178`). **Keep** `MEM_TOTAL_KB=…` (`:175`) and the `MEM_TOTAL=…` branch (`:177`).
- [ ] 1.3 Rewrite the `(2a)` comment block (`:169-174`): drop the `# NOTE (#6288 User-Challenge): mem_used_mb is page-cache-confounded …` lines (`:171-174`); retain the `mem_total_mb self-verifies the cx33 bump (~8000 vs ~4000)` note (`:170`); update the header (`:169`) from "Host memory pressure CONTEXT" to a total-only framing (e.g. `# (2a) Host total memory from /proc/meminfo — cx33-bump self-verification (~8000 vs ~4000).`). Add a one-line provenance breadcrumb: `# (#6292) mem_used_mb dropped — page-cache-confounded; OOM confirmation keys on zot_anon_mb/zot_oom_kills below.`

### Phase 2 — Structural test: prune the field + brace-escape loops (`registry-boot-guard.test.sh`)

- [ ] 2.1 In the `for f in …` `SOLEUR_ZOT_DISK`-field loop (`:96-100`), remove `mem_used_mb=` from the list. **Keep** `mem_total_mb=` and every other field token.
- [ ] 2.2 In the `#6288 new-field brace-escaping` `for v in …` loop (`:127-129`), remove `MEM_AVAIL_KB` and `MEM_USED` (they no longer appear in `$CI`; the `single==double` count assertion would pass at `0==0`, but a stale name in the loop is misleading). **Keep** `MEM_TOTAL_KB`, `MEM_TOTAL`, and all other vars.
- [ ] 2.3 Re-run `bash apps/web-platform/infra/registry-boot-guard.test.sh` → green. The `mem_total_mb=` field assertion and the container-field ordering assertions still pass; no `mem_used_mb` assertion remains.

### Phase 3 — Living observability/ops docs sweep (prevent dangling "still-emitted" reads)

- [ ] 3.1 `scripts/followthroughs/zot-restart-plateau-6288.sh` — comment-only, no logic change:
  - `:8` field-list comment: change `mem_*_mb` → `mem_total_mb` (the reporter no longer emits `mem_used_mb`).
  - `:19-21` "WHY zot_anon_mb, not host mem_used_mb" rationale: keep the zot_anon_mb page-cache-free justification, but reframe so it doesn't read as if `mem_used_mb` is an emitted field (e.g. "…not host used-memory (`mem_used_mb`, dropped #6292 — page-cache-confounded)…"). The probe gates on `zot_anon_mb`, so soak semantics are untouched — no re-run needed.
- [ ] 3.2 `knowledge-base/engineering/operations/post-mortems/zot-registry-restart-loop-oom-postmortem.md` (`:58`): the Resolution line "Enriched the reporter with `mem_used_mb`/`mem_total_mb` (context)" is a historical #6288 record. Preserve history **and** currency: keep `mem_total_mb` as context and append a parenthetical `(mem_used_mb subsequently dropped, #6292 — page-cache-confounded)`.
- [ ] 3.3 `knowledge-base/engineering/architecture/decisions/ADR-096-…zot.md` (`:151`): "not the page-cache-confounded host `mem_used` …" is design rationale for the confirmation-signal *choice*; it contrasts against host used-memory as a concept and does **not** assert the field is emitted. **Default: KEEP unchanged** (verify-only). If, on reading `:148-152` in context, it reads as "currently emitted", append `(field dropped #6292)`; otherwise leave it — avoid gratuitous ADR churn. No change to the ADR `## Decision`.
- [ ] 3.4 Decode-table / alarm docs: confirm the OOM decode path (ADR-096 confirmation prose, postmortem alarm rows, `betterstack-log-query.md:167` decode list) lists **no** `mem_used_mb` decode key → **no edit expected**. Verify via `grep -n 'mem_used' knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` returns nothing.

### Phase 4 — Point-in-time carve-out (DO NOT EDIT)

These are historical records that MUST retain their `mem_used_mb` references; they are excluded
from the residual-grep AC (mirrors the `**/archive/**` + own-migration-artifact carve-out
convention):

- `knowledge-base/project/plans/2026-07-09-fix-zot-restart-loop-oom-telemetry-plan.md`
- `knowledge-base/project/specs/feat-one-shot-6288-zot-restart-loop-oom-telemetry/{tasks.md,session-state.md,decision-challenges.md}`
- `knowledge-base/project/learnings/**/2026-07-0*-*oom-telemetry*.md` and sibling 2026-07 zot learnings
- `knowledge-base/project/plans/archive/**`, `knowledge-base/project/specs/archive/**`
- This feature's OWN artifacts: this plan, `specs/feat-one-shot-6292-drop-mem-used-mb/tasks.md`, its `session-state.md`, and any `decision-challenges.md`.

## Files to Edit

- `apps/web-platform/infra/cloud-init-registry.yml` — remove `mem_used_mb=$MEM_USED` token (`:224`) + `MEM_AVAIL_KB`/`MEM_USED` computations (`:176`,`:178`) + reword `(2a)` comment (`:169-174`).
- `apps/web-platform/infra/registry-boot-guard.test.sh` — drop `mem_used_mb=` from the field loop (`:96-100`) + `MEM_AVAIL_KB`/`MEM_USED` from the brace-escape loop (`:127-129`).
- `scripts/followthroughs/zot-restart-plateau-6288.sh` — comment-only field-list + rationale reword (`:8`, `:19-21`).
- `knowledge-base/engineering/operations/post-mortems/zot-registry-restart-loop-oom-postmortem.md` — reframe `:58` context line (historical + dropped-per-#6292).
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` — `:151` verify-only (KEEP default; optional `(dropped #6292)` note).

## Files to Create

- None (spec `tasks.md` + `session-state.md` are created by the plan/work lifecycle, not a code deliverable).

## Open Code-Review Overlap

None. (No open `code-review` issue references these files — verify at work-time with the `gh issue list --label code-review` two-stage `jq --arg` check over the Files-to-Edit paths.)

## Infrastructure (IaC)

### Terraform changes
`cloud-init-registry.yml` is rendered into `hcloud_server.registry.user_data` via
`base64gzip(templatefile(...))` in `zot-registry.tf:248`. No `.tf` resource, provider, or variable
is added or changed. No new secret, vendor, DNS record, or persistent process is introduced.

### Apply path
**(c) scoped `-replace` (immutable redeploy) — the only path to a no-SSH host.** The registry host
is deny-all-ingress with no SSH bootstrap, and `zot-registry.tf` deliberately omits
`lifecycle.ignore_changes=[user_data]` (`:274`), so a cloud-init edit is a `user_data` diff that
`ForceNew`-replaces the host. The change reaches the running host only via the sanctioned
`gh workflow run apply-web-platform-infra.yml -f apply_target=registry-host-replace` dispatch
(guarded, destroy-checked, store volume preserved + re-attached; brief replace outage fully masked
by the GHCR atomic fallback → zero user impact). It is **not** auto-applied on merge (the registry
host is outside the push `-target` allow-list — this is the intended maintenance-window gating
shared with `inngest-host`/`git-data` cloud-init edits).

**Sequencing / proportionality (operator decision surfaced, not auto-fired):** the host was just
replaced on 2026-07-09 (`registry-region-migrate`, cx33/hel1). Because `mem_used_mb` is
*cosmetically dead but entirely harmless*, forcing a **dedicated** standalone replace solely to
drop one telemetry key is disproportionate. **Recommended default:** merge the source (source of
truth becomes correct) and let the field removal ride the **next** `registry-host-replace`
performed for any reason; the pending `user_data` drift until then is the accepted maintenance-
window pattern. If the operator wants the stream clean immediately, dispatch
`registry-host-replace` on demand — the exact command + verification are in the post-merge AC.

### Distinctness / drift safeguards
- `dev != prd`: the registry host is prd-only (isolated Doppler `soleur-registry/prd`); no dev
  counterpart. No change to secret wiring.
- **Pending-drift note:** until the next `registry-host-replace`, the scheduled Terraform drift
  detector will report a `user_data` diff on `hcloud_server.registry`. This is expected and
  self-clears on the next replace (same as any gated cloud-init edit). Do not "remediate" it with
  an unplanned apply.

## Downtime & Cutover

**Offline-inducing operation:** `terraform apply -replace='hcloud_server.registry'` via the
`registry-host-replace` dispatch (Hetzner destroys + re-creates the host — a `ForceNew` replace).
**Surface affected:** the self-hosted zot container registry. Note this is an **internal CI/deploy
substrate** (serves image pulls/pushes to the release pipeline over the private net), **not** an
end-user-facing serving surface — the Concierge/web platform never talks to it directly.

**Zero-downtime evaluation (defaults to zero-downtime):**

1. **Default = no replace at all for this PR.** `mem_used_mb` is cosmetically dead but *harmless*
   while still emitted, so the recommended path (see `## Infrastructure (IaC)` sequencing) is to
   merge the source and let the field drop **ride the next `registry-host-replace` performed for
   any reason** — zero dedicated replace ⇒ zero downtime attributable to this change. The pending
   `user_data` drift until then is the accepted maintenance-window pattern.
2. **When a replace does run, it is already an effectively-zero-user-impact blue-green cutover:**
   the **GHCR atomic fallback fully masks** the brief registry-unavailability window (every pull/
   push falls through to GHCR — the mechanism proven in #6288/#6293), and the zot **store volume is
   a separate `hcloud_volume` resource preserved + re-attached** to the fresh host (the new host is
   born from cloud-init; the old host is retired only after — blue-green-shaped). No CI/deploy job
   sees a hard failure; at worst a pull momentarily sources from GHCR.

**Residual downtime:** none user-facing. The only unavailability is the seconds-to-minutes registry
window during a replace, fully GHCR-masked. It is **operator-timed** (maintenance-window dispatch,
guarded + destroy-checked) — not auto-fired on merge. Because there is no user-facing outage, no
bounded-window operator sign-off is required beyond the operator choosing when to dispatch (or
bundling with the next registry maintenance). **HALT condition not met:** this section names the
operation, defaults to the zero-downtime path, and justifies the (zero-user-impact) residual.

**Network-Outage checklist (4.5) — N/A.** The "no-SSH" / "deny-all-ingress" wording is a
*descriptive property* of the host, not a connectivity symptom under diagnosis. `hcloud_server.registry`
has **no** `provisioner "file"`/`remote-exec` and **no** `connection { type = "ssh" }` block
(cloud-init-only provisioning), so there is no apply-time SSH dependency and the L3→L7 firewall/DNS
checklist does not apply.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_ZOT_DISK self-report line to Better Stack Logs every 5 min (unchanged); the disk-<85% PUSH heartbeat and the private-net /v2/ liveness heartbeat are untouched"
  cadence: "every 5 min via /etc/cron.d/zot-disk-heartbeat"
  alert_target: "existing betteruptime heartbeats (registry_prd liveness, registry_disk_prd disk) — no alarm keys on mem_used_mb, so none change"
  configured_in: "apps/web-platform/infra/cloud-init-registry.yml + zot-registry.tf"
error_reporting:
  destination: "Better Stack Logs (payload) + journald breadcrumb on egress failure (retry-once-then-breadcrumb, unchanged)"
  fail_loud: true
failure_modes:
  - mode: "malformed line after token removal (stray space / dropped mem_total_mb)"
    detection: "registry-boot-guard.test.sh field-loop asserts mem_total_mb= present and mem_used_mb= absent; run in CI pre-merge"
    alert_route: "CI red on the structural test"
  - mode: "field removed in source but still emitted by the running host (unapplied cloud-init)"
    detection: "in-surface probe: betterstack-query.sh --grep SOLEUR_ZOT_DISK on the newest boot_id shows mem_used_mb absent + mem_total_mb present"
    alert_route: "post-apply verification query (below); Terraform drift detector flags the pending user_data diff until the replace"
logs:
  where: "Better Stack Logs (SOLEUR_ZOT_DISK stream) + journald on the registry host"
  retention: "Better Stack Logs default retention (unchanged)"
discoverability_test:
  command: "betterstack-query.sh --grep SOLEUR_ZOT_DISK | head -1   # then eyeball: mem_total_mb present, mem_used_mb absent, line still parses"
  expected_output: "newest-boot_id line contains 'mem_total_mb=' and 'zot_anon_mb=' and NOT 'mem_used_mb='"
```

(No `## Observability` reject-condition trips: every field is populated, and the discoverability
command is SSH-free.)

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 `grep -c 'mem_used_mb' apps/web-platform/infra/cloud-init-registry.yml` == **0**.
- [ ] AC2 `grep -c 'MEM_USED\|MEM_AVAIL_KB' apps/web-platform/infra/cloud-init-registry.yml` == **0** (dead computations removed).
- [ ] AC3 `grep -c 'mem_used_mb\|MEM_USED\|MEM_AVAIL_KB' apps/web-platform/infra/registry-boot-guard.test.sh` == **0**.
- [ ] AC4 KEEP verified — the `LINE="SOLEUR_ZOT_DISK` assignment still contains `mem_total_mb=$MEM_TOTAL`, `zot_anon_mb=$ZOT_ANON_MB`, `zot_oom_kills=$ZOT_OOM_KILLS`, `exit_code=$EXIT_CODE`, `oom_kills_5m=$OOM_KILLS_5M` (grep each on the `:224`-equivalent line).
- [ ] AC5 `MEM_TOTAL_KB` and `MEM_TOTAL` remain in `cloud-init-registry.yml` (feed `mem_total_mb`); `MEM_TOTAL` present in the boot-guard brace-escape loop.
- [ ] AC6 `bash apps/web-platform/infra/registry-boot-guard.test.sh` exits 0; the field loop asserts `mem_total_mb=` and no longer asserts `mem_used_mb=`.
- [ ] AC7 followthrough `zot-restart-plateau-6288.sh` field-list comment reads `mem_total_mb` (not `mem_*_mb`) and no comment implies `mem_used_mb` is emitted; **no** executable line changed (`git diff` on the file is comment-only).
- [ ] AC8 Residual-reference sweep over live surfaces returns only the point-in-time carve-out: `grep -rn 'mem_used_mb' apps/ scripts/ knowledge-base/engineering/` shows **zero** hits that read as "currently emitted" (postmortem hit is historical/dropped-framed; ADR-096 hit is rejected-signal rationale). Carve-out paths in `knowledge-base/project/{plans,specs,learnings}/**` and `**/archive/**` are excluded.
- [ ] AC9 PR body uses `Closes #6292`.

### Post-merge (operator)
- [ ] AC10 Apply the cloud-init change to the running host. **Automation:** `gh workflow run apply-web-platform-infra.yml -f apply_target=registry-host-replace -f reason='#6292 drop mem_used_mb from SOLEUR_ZOT_DISK'` (automatable via gh CLI; a prod host-replace is a maintenance-window action the operator times — recommended to bundle with the next registry maintenance rather than fire a dedicated replace for a cosmetic field; see `## Infrastructure (IaC)` sequencing).
- [ ] AC11 After whichever `registry-host-replace` next applies it, verify in-surface (no SSH): `betterstack-query.sh --grep SOLEUR_ZOT_DISK` newest-`boot_id` line contains `mem_total_mb=` + `zot_anon_mb=` and does **not** contain `mem_used_mb=`, and the line still parses (host-tier read ~8000 confirms cx33). Then `gh issue close 6292` (use `Closes #6292` in the body; issue closes at merge — this is the confirmation).

## Test Scenarios

- Structural: `registry-boot-guard.test.sh` re-run green (Phase 2.3) — the canonical automated gate; it reads the RAW `$CI` cloud-init and asserts field presence/absence on the `LINE=` assignment specifically.
- No new test framework (bash `.test.sh` convention already in `apps/web-platform/infra/`); no unit-test harness needed for a field removal.

## Domain Review

**Domains relevant:** none

Infrastructure/observability change — a single telemetry field removed from an internal
operator self-report line on a prod registry host. No product/UI surface, no marketing, finance,
legal, sales, or support implication. No cross-domain leader spawned (headless one-shot;
proportional to a cosmetic field drop).

## Architecture Decision (ADR/C4)

**Not an architectural decision — skip.** Removing one host-memory telemetry key changes no
ownership/tenancy boundary, no substrate, no resolver/trust boundary, and reverses no ADR
`## Decision`. ADR-096 mentions host `mem_used` only in *rejected-signal* rationale (unchanged
decision). **C4 checked:** the three model files (`diagrams/model.c4`, `views.c4`, `spec.c4`) carry
the registry→Better Stack telemetry edge but model **no** field-level detail — `grep -n 'mem_used\|mem_total'`
over `model.c4`/`model.likec4.json` returns nothing, and no external actor/system/access-relationship
changes. No `.c4` edit.

## Non-Goals / Out of Scope

- Not touching `mem_total_mb`, `zot_anon_mb`, `zot_oom_kills`, `oom_kills_5m`, `exit_code`, or any
  other `SOLEUR_ZOT_DISK` field (operator-pinned).
- Not editing the #6288 point-in-time artifacts (Phase 4 carve-out).
- Not provisioning the deferred #6291 durable Better Stack recurrence alarm (separate tracked
  issue).
- No soak-gated follow-through enrollment: the verification is a single post-apply query, not a
  time-gated close criterion.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled above (threshold:
  none, with a sensitive-path scope-out reason).
- **`MEM_AVAIL_KB` is orphaned by the removal** — it exists solely to compute `MEM_USED`. Remove it
  in the same edit; leaving it is dead code that a future reader will mistake for a live signal.
- **Merged ≠ applied.** The source edit is inert on the running host until a `registry-host-replace`
  dispatch re-runs cloud-init (no SSH, immutable redeploy). Do not assume the telemetry stream
  changes at merge; the drift detector will (correctly) flag the pending `user_data` diff until the
  replace — do not "fix" that drift with an unplanned apply.
- **Comment-only followthrough edit.** `zot-restart-plateau-6288.sh` is enrolled in the
  scheduled-followthrough sweeper for #6288; keep the edit strictly comment-only so soak semantics
  (gates on `zot_anon_mb`/`exit_code`/`oom_kills_5m`) are byte-for-byte unchanged.

## Deepen-Plan Verification (2026-07-10)

**Mandatory gates:** 4.6 User-Brand Impact ✅ (threshold `none` + sensitive-path scope-out
reason — `apps/*/infra/` matches the sensitive-path regex). 4.7 Observability ✅ (5 fields
populated, discoverability_test is SSH-free). 4.8 PAT-shaped variable ✅ (none). 4.9 UI-wireframe ✅
(no UI surface). **4.55 Downtime & Cutover ✅ — gate FIRED** on the `registry-host-replace`
(`ForceNew` replace of the serving `hcloud_server.registry`); a `## Downtime & Cutover` section was
added defaulting to the zero-downtime path (no dedicated replace; GHCR-masked blue-green when a
replace does run). 4.5 Network-Outage — N/A (no SSH provisioner; "no-SSH" is descriptive).

**Cited-artifact re-verification (all held against the branch):** `cloud-init-registry.yml` —
`MEM_AVAIL_KB`/`MEM_USED` at `:176`/`:178`; `MEM_TOTAL_KB`/`MEM_TOTAL` at `:175`/`:177`; `LINE=`
emit at `:224`; comment block `:169-174`. `registry-boot-guard.test.sh` — field loop (`for f in`)
and brace-escape loop (`for v in MEM_… `) both present. `apply-web-platform-infra.yml` —
`registry-host-replace` is a dispatch choice (`:102`); `hcloud_server.registry` is **absent** from
the push/`manual-rerun` `-target` allow-list ⇒ merging the `.yml` does **not** auto-replace the
host. `zot-registry.tf` — `templatefile(...user_data...)` render + **no**
`lifecycle.ignore_changes=[user_data]` (confirmed). `ADR-096:148-151` (rejected-signal rationale,
KEEP-default), postmortem `:58` (historical context line), `betterstack-log-query.md:167` (decode
list omits both mem fields), followthrough `:8`/`:19-21` (comment-only). **C4:** zero
`mem_used`/`mem_total` references in `model.c4`/`model.likec4.json` — no field-level modeling.

**Scope discipline:** single-token field removal + dead-computation cleanup + doc de-reference. No
new dependency, framework, migration, secret, or infrastructure. Proportional review (headless
one-shot): the mandatory halt-gates ran deterministically; the plan-review panel that follows this
pipeline phase carries the DHH/Kieran/simplicity correctness pass.
