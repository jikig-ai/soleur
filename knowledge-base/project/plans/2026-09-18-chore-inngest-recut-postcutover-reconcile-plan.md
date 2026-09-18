---
title: "chore(inngest): reconcile the inngest-volume-recut work against the completed dedicated-host cutover"
date: 2026-09-18
slug: chore-inngest-recut-postcutover-reconcile
branch: feat-one-shot-7695-recut-postcutover-reconcile
issue: 7695
closes: [7695, 8017, 8015]
refs: [8078, 7777, 8018, 8316, 6894, 6178, 7674]
type: chore
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: none
---

## Enhancement Summary

**Deepened on:** 2026-09-18
**Sections enhanced:** Phase 1.1c callout (layer citations), Architecture Decision § C4 views,
Acceptance Criteria AC1/AC2/AC5/AC7/AC11/AC13/AC14/AC15/AC18/AC19, Phase 4.3.
**Research agents used:** git-history-analyzer (16/16 attribution claims CONFIRMED live — commit
`000fa4715`, PRs #7778/#8019/#7887/#8191/#8248/#8314, 14 issues, ADR/runbook anchors, G1/G19
sets, four archive dry-runs); verify-the-negative pass (11 negative claims: 10 confirm, 1 contradict
— `model.c4`'s `inngestRedis` DESCRIPTION names the recut dispatch; C4 wording corrected);
observability-coverage-reviewer (5 findings, all folded: every measured value in the callout now
names its read and layer — `inngest-host-state.sh` for row fields, Doppler `INNGEST_CUTOVER_FLIP` as
G19's authority, Hetzner `GET /v1/volumes/106261946` for the attachment, `gh run view 34948112813`
for the latch provenance; closing comments carry the read beside each quoted field);
code-quality-analyst AC-executability audit (8 findings, all folded: G3.7-gated awk for AC1,
blank-line-terminated awk for AC2, `find` for AC7, anchored grep for AC5, `--no-renames` for AC11,
case-insensitive closing-keyword grep for AC14, `(\D|$)` for AC18, paginated last-comment for AC19,
AC15 restored). Halt gates 4.5–4.11 all pass or skip (docs-only; threshold `none` with scope-out;
no PAT shape; no UI surface; no new store; no guard). Fan-out was deliberately scoped to four
agents: the plan had already been through CTO, spec-flow, an advisor consult and a four-agent
plan-review in the same session, and the deliverable is prose + issue state.

### Key Improvements

1. The paste-ready runbook callout is now re-measurable sentence by sentence without SSH.
2. The C4 "no impact" claim states the one stale element description honestly and routes it.
3. Every AC command was executed for shape against the live tree and corrected where it would have
   false-passed (AC7) or mis-scoped (AC1, AC2).

### New Considerations Discovered

- `git diff --name-only` hides the delete side of a `git mv`; the diff-scope AC needs `--no-renames`.
- Two runbook bullets carry `**Remediation:**`; any awk on that token must be gated on the G3.7 heading.

## Overview

The `inngest-volume-recut` apply_target that #7695 asked for was built and merged on 2026-09-04
(Merge B, squash `000fa4715`). The issue stayed open only because its four operator-gated
dispatches never ran. The dedicated-host cutover then completed on 2026-09-15 by the standard
`op=arm` path, on the same plaintext volume `106261946`, and the store it runs on is populated.
ADR-199 refuses a recut of a populated store on a serving host, so the recut is not the path
forward for this volume, and the runbook, the ADR-100 record, the 2026-09-02 plan and its spec all
still describe a world in which it is. This plan reconciles those records against the measured live
state, decides the fate of the five open recut-gate issues with evidence, and closes #7695.

No spec.md exists for this branch — spec lacks valid `lane:`, defaulted to `cross-domain` (TR2
fail-closed).

**Shape of the change:** documentation, plan/spec archival and GitHub issue state. No code, no
Terraform, no workflow, no dispatch, no gate edit. Every file this plan edits is disjoint from open draft PR #8248's
file set (`gh pr diff 8248 --name-only`, 54 paths at plan time — re-measured by AC12, since that
draft moves), with two pipeline-owned exceptions: the regenerated `knowledge-base/INDEX.md` (a textual conflict with 8248 is guaranteed and
harmless — whichever merges second regenerates it) and `knowledge-base/kb-tags.txt` if /compound adds a
tagged learning. The PR body names both rather than claiming full disjointness.

## Research Insights

### Premise Validation (Phase 0.6) — every cited reading re-measured 2026-09-18

All measurements taken this session via `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh`,
`doppler secrets get`, the Hetzner API (`curl https://api.hetzner.cloud/v1/...` with the
`prd_terraform` token) and `gh`. No SSH.

| Premise (from the brief) | Live reading | Verdict |
|---|---|---|
| Cutover completed 2026-09-15; scheduling runs on `soleur-inngest` 10.0.1.40:8288, FSM `done` | ADR-100 addendum 2026-09-15 (`op=arm` run 34948112813 → FSM `done`; `op=registry-probe` 70 functions). Doppler `soleur-inngest/prd`: `INNGEST_CUTOVER_FLIP=done`, `INNGEST_DIAGNOSTIC_BOOT=0`. Newest dedicated probe row: `http_code=200 server_active=active cutover_flag=done registry_fns=70` | **HOLDS** |
| Same plaintext volume `106261946` | Hetzner `GET /volumes/106261946`: `name=soleur-inngest-redis-store size=10 format=ext4 created=2026-07-07T23:51:07Z server=166317708 linux_device=/dev/disk/by-id/scsi-0HC_Volume_106261946`. Probe row `data_mount_devid=scsi-0HC_Volume_106261946` | **HOLDS** |
| Store populated ("hundreds of Redis keys") | Probe row `redis_keys=1081 redis_expires=1070 data_bytes=38671222`, key histogram `?queue?:queue:*=153,?estate?:key:*=767,…` | **HOLDS** (thousand, not hundreds) |
| Host is the 2026-09-15 cutover host | Hetzner server `166317708` **created 2026-09-17T12:47:37Z** — this is the host born of the inherited-`done` replace incident (runbook § Inherited `done` after a host replace, "Measured 2026-09-17: two replaces and 76 minutes with no live scheduler"), recovered with `op=resume`. `uptime_s=90359` on the row agrees. | **HOLDS with correction** — same volume, third host since 2026-09-04 |
| `flush_latched` | Row: `flush_latched=true`. The 2026-09-15 `op=arm` performed the one authorized `FLUSHALL` and `record_flush_latch` wrote the durable latch on `/mnt/data`; it survived the 09-17 replace, exactly as designed (`inngest-cutover-flip.sh` "the volume that SURVIVES a host replace") | **The latch now STANDS** — the pre-cutover plan's "the latch is NOT standing" (#7695 comment 2026-09-09) is superseded |
| `#7695` open, no closing PR | `gh issue view 7695`: OPEN, `closedByPullRequestsReferences=[]`, milestone "Phase 4: Validate + Scale" | HOLDS |
| Merge B merged as PR #7778 squash `000fa4715` | `git log` on main carries `000fa4715 feat(inngest): the gated inngest-volume-recut target…` (2026-09-04) | HOLDS |
| PR #8248 carries ADR-142 blue-green for #6894 and does not touch this plan's files | `gh pr view 8248`: OPEN, draft, `closingIssuesReferences=[]`, body `Ref #6894 / Ref #7695 / Ref #8017` (never `Closes`). Its plan states: *"This plan does not retire `inngest-volume-recut`; that is a separate decision with its own evidence."* Its file list does NOT include `runbooks/inngest-server.md`, ADR-100, the 2026-09-02 plan or its spec dir | HOLDS — and it hands THIS plan the retire-or-keep decision |
| #8017 close condition | Issue's own close condition (comment 2026-09-10): *"a live probe row … carrying `probe_schema=8` and, for this issue specifically, the field named in its own body"* (`data_mount_devid`). Live row: `probe_schema=8 data_mount_devid=scsi-0HC_Volume_106261946` | **MET → closable** |
| #8015 close condition | Same comment; field is `registry_fns`. Live row `registry_fns=70`; `scripts/followthroughs/inngest-host-not-serving-7674.sh` → `PASS … 24 row(s) carrying ALL THREE server_active=active, http_code=200 and a NON-ZERO registry_fns` rc=0 | **MET → closable** |
| #8078 (G8 `== inactive`) | `tests/scripts/lib/inngest-host-dark-gate.sh` still carries `[[ "$server_active" == "inactive" ]] \|\| { _ihdg_verdict "host_serving"; …}` (G8) and the deliberate-divergence header naming #8078; sibling E10 is `!= active` | defect still on main; consumer dormant (see Guard re-grade) |
| #7777 (append-only latch clear) | OPEN, `deferred-scope-out`, mis-triaged `domain/legal`. `inngest-cutover-flip.sh` `flush_already_performed` is still a monotonic disjunction with no clear path | still true; scope re-bound below |
| #8018 (AGENTS rule) | OPEN. `grep -n 'every predicate' AGENTS.rules.md plugins/soleur/skills/go/SKILL.md` → 0 hits: the rule was never added | unaffected by the cutover |
| ADR-199 status | `status: accepted`, 2026-09-03 addendum + 2026-09-10 amendment (C1 pin → `data_mount_devid`). Decision: *"`redis_keys > 0` routes to ADR-142, with no override."* ADR-199 is IN 8248's file set | do not edit |
| Recut-gate stale prose on main outside this plan's reach | `.github/workflows/cutover-inngest.yml` (content anchor: "recuts /mnt/data today; the design for one is tracked in #7695") and `scripts/cutover-inngest.sh` (anchor: "recovery from `aborted` is a /mnt/data recut via the inngest-host-replace window") — both in 8248's file set | reconciled by reference; carried on the retire-or-keep issue |

**Mechanism-vs-ADR check (0.6 item 4).** Grepped `knowledge-base/engineering/architecture/decisions/`
for `recut`, `retire`, `dormant`: ADR-199 (bounds ADR-142; refuses populated stores), ADR-142's
2026-09-03 addendum (bounded by ADR-199), ADR-100 §"What remains open" (stale: says no recut target
exists). No ADR has rejected "document the target as dormant and defer retirement"; PR 8248's plan
explicitly leaves retirement as a separate decision. The mechanism this plan proposes — records +
issue state, no code — sits in no rejected-alternatives table.

### Property List (Phase 0.6b)

1. **P-RUNBOOK** — an engineer reading `inngest-server.md` G3.7 on the live `done` host is told the
   truth: the recut target exists, it refuses this store by design, the standing latch is the #5450
   guard working, and the routes are `op=resume` / P1-13 rollback — never "wait for a recut to be built".
2. **P-RECORD** — ADR-100's recorded state no longer says "no apply_target that recuts /mnt/data"
   after one exists; the dormancy and the retire-or-keep deferral are on the architectural record.
3. **P-ISSUES** — each of #7695, #8017, #8015, #8078, #7777, #8018 carries a measured disposition,
   and the ones that close, close on a met condition, not a promise.
4. **P-ARTIFACTS** — the 2026-09-02 plan and its spec stop presenting P1–P10 as pending dispatches,
   and every `issue: 7695` plan/spec pair (09-02 and 09-07) leaves the active directories with the issue.
5. **P-DISJOINT** — nothing this PR touches other than the pipeline-regenerated `INDEX.md` /
   `kb-tags.txt` is in PR 8248's file set, so neither PR forces the other to rebase over a semantic conflict.

### Cut List (Phase 0.6b) — mechanisms removed before research

| Mechanism considered | Property | Why cut |
|---|---|---|
| Retire the `inngest-volume-recut` enum option + job + two gates now | P-RECORD | Every file involved (`apply-web-platform-infra.yml`, `infra-validation.yml`, `terraform-target-parity.test.ts`, ADR-199) is in 8248's set → violates P-DISJOINT. Deferred to a decision issue gated on 8248 landing. |
| Fix G8 (`== inactive` → `!= active`, #8078) in this PR | none of P1–P5 | The gate's consumer is dormant on this volume (G13 refuses `redis_keys=1081` before any G8 verdict matters for a real dispatch); a Guard Contract + mutation battery for a predicate that may be deleted after the retire-or-keep decision is spend with no property behind it. Re-graded instead; see Domain Review for the CTO ruling. |
| Edit `cloud-init-inngest.yml` to drop the #7695 LUKS runcmd arms | none | `user_data` is ForceNew on the sole scheduler host — forbidden by the brief and by `2026-09-03-the-gate-cleared-the-destroy-and-never-graded-the-create.md`. |
| Complete the `inngest-aof-destruction-record.md` template | none | No destruction happened and none is scheduled; the template's consumer is a future measured-empty dispatch. Leave `status: template`. |
| Notify-only follow-through probe (exit 5) driving #8316's "PR 8248 merged" trigger | none listed; spends P-DISJOINT (`scripts/test-all.sh` is in 8248's set) | Proposed by spec-flow, then cut at plan-review: the simplification panel (DHH, code-simplicity) and the correctness panel (Kieran: exit-3 arm, header self-match, repo pin; architecture: `RETIREMENT:` header, shard placement) BOTH fired on it — delete beats fix. The trigger is a PR the operator authors and merges; a cross-link comment on PR 8248 naming #8316 (Phase 4.2) is the whole mechanism. |
| Flip ADR-100 `adopting → accepted` | none | Owned by the #6178 remnant (soak ends 2026-09-22), explicitly out of this batch step. |

### Live-state evidence (verbatim, 2026-09-18 ~14:00Z)

```
SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active vector_active=active redis_active=active
uptime_s=90359 boot_id=ef763c72-74bb-44ff-aa74-c19dc25ca13c
image_ref=10.0.1.30:5000/jikig-ai/soleur-inngest-bootstrap:v1.1.35@sha256:c8e27c71bb3f4b79379bb0929e89acef1b4bf18b80b41e14496dd96c726ed0cd
instance_id=hetzner-166317708 cli_version=1.19.4-2c8385ba8 cutover_flag=done probe_schema=8 host_role=dedicated
flush_latched=true redis_keys=1081 redis_expires=1070
redis_key_patterns=?queue?:queue:*=153,?estate?:key:*=767,?cs?:a:*=13,?queue?:partition:*=2,?queue?:accounts:*=2,?connect?:gateways:*=1
data_mount_src=/dev/sdb data_bytes=38671222 data_mount_base=sdb data_mount_devid=scsi-0HC_Volume_106261946 registry_fns=70
```

Doppler `soleur-inngest/prd` names: `BETTERSTACK_LOGS_TOKEN DOPPLER_* INNGEST_CUTOVER_FLIP=done
INNGEST_DIAGNOSTIC_BOOT=0 INNGEST_EVENT_KEY INNGEST_HEARTBEAT_URL INNGEST_POSTGRES_URI
INNGEST_REDIS_LUKS_KEY INNGEST_REDIS_PASSWORD INNGEST_SIGNING_KEY` (values other than the two flags
never printed). `INNGEST_CUTOVER_DONE_OWNER` / `INNGEST_EXPECT_LUKS` do not exist as secrets.

Hetzner: volume `106261946` `{status: available, format: ext4, server: 166317708, created 2026-07-07}`;
server `166317708 soleur-inngest running, created 2026-09-17T12:47:37Z, ip 10.0.1.40, volumes [106261946]`.

### Guard re-grade — `inngest_host_dark_gate` G1–G20 against the live row

The gate (`tests/scripts/lib/inngest-host-dark-gate.sh`, DISJOINT from 8248) is evaluated in order and
stops at the first refusal. Against the row above:

| Gate | Predicate (from the lib header) | Live | Verdict |
|---|---|---|---|
| G1–G4 | readable, ≥1 row, ≤90 min old, `probe_schema == 8` | rows hourly, schema 8 | pass |
| G5–G7 | host/host_name/`host_role=dedicated` | dedicated | pass |
| **G8** | `server_active == inactive` | `active` | **REFUSE `host_serving`** (first refusal) |
| G9 | `http_code != 200` | `200` | would refuse `host_serving` |
| G13 | `redis_keys == 0` | `1081` | would refuse `store_populated` |
| G14 | `data_mount_devid == scsi-0HC_Volume_106261946` | matches | pass — the #8017 fix is live |
| G18 | #7674 probe PASS | PASS (registry_fns=70) | pass — the #8015 fix is live |
| **G19** | `INNGEST_CUTOVER_FLIP ∈ {rolled-back, aborted}` | `done` | would refuse `flag_unsafe` |
| G20 | `INNGEST_DIAGNOSTIC_BOOT ∈ {0, unset}` | `0` | pass |

**Reading.** G19 alone makes the target unreachable from a `done` host; G9 and G13 are correct
refusals in their own right: the host serves production. The gate is doing what ADR-199 built it to
do — they are the reason the recut is not the path forward. G8 refuses for the right OUTCOME today but
through the predicate ADR-100 §7 (2026-09-11) already records as the #8078 defect class: its
`== inactive` bakes in a pre-cutover shape, since a dark host under a P1-5 refusal loop reads
`activating`, so even a post-rollback dark host would be refused as `host_serving`. It does not matter on this volume because G13 refuses the
populated store regardless, and the recut can only reach an empty store through a second `FLUSHALL`
that the standing latch forbids (#7777). **The target is dormant on volume `106261946` until #7777
exists, and the encryption motive is carried by ADR-142 (PR 8248), which never needs it.** That is the
finding the records below must carry.

### Reusable precedents

- **ADR "superseded, not edited" addendum shape** — ADR-100 addendum 2026-09-15 opens *"The
  2026-08-12 addendum's 'the cutover did not hold' is superseded, not edited."* Append-only; the new
  addendum follows the same shape.
- **Runbook correction callout shape** — `inngest-server.md` uses `> **Corrected YYYY-MM-DD (#N).**`
  blockquotes that paraphrase the old wording rather than quoting it (so absence-greps stay honest).
- **Archive** — `bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh [--dry-run] <slug>`.
  Dry-run measured: slug `infra-inngest-volume-recut-luks` → moves the 2026-09-02 plan;
  slug `one-shot-7695-inngest-volume-recut-luks` → moves the spec dir. `**/archive/**` is excluded
  by `scripts/lint-infra-no-human-steps.py`, so the addenda are written BEFORE the move.
- **Issue-closure verification** — `gh pr view <N> --json closingIssuesReferences`
  (`2026-09-17-the-sentence-i-wrote-to-prevent-the-close-is-what-assigned-it.md`): GitHub's detector
  reads PR-body prose, so a sentence that *mentions* `Closes #7777` while arguing against it would close
  it. The PR body may only contain the three intended `Closes` lines; every other issue is `Ref`.

### Institutional learnings that shape this plan

- `2026-09-11-every-sentence-my-runbook-inherited-was-false-when-measured.md` — inherited runbook
  prose skips measurement. Every sentence the new G3.7 paragraph asserts is tied to a row/flag/API
  reading in this section.
- `2026-09-10-every-instrument-i-verified-was-verified-inside-its-own-blind-spot.md` — positive
  controls sit on the far side of the filter. The #8015 closure cites the probe script's own PASS
  output (rc=0 with the three-conjunct message), not a hand grep of the row.
- `2026-09-15-my-legal-record-said-the-change-had-landed-inside-the-pr-that-lands-it.md` — a
  diff-scope AC must list what the PIPELINE writes (INDEX.md, session-state.md, tasks.md), not only
  what the plan edits. AC11 does.
- `2026-09-14-a-systemd-state-used-as-a-signal-had-no-provenance-and-replayed-a-stale-capture.md` —
  a state used as a signal needs provenance. The runbook paragraph says WHO wrote the latch
  (`op=arm` run 34948112813, 2026-09-15) and WHEN, not just that it stands.
- `2026-09-03-the-gate-cleared-the-destroy-and-never-graded-the-create.md` — `user_data` is
  ForceNew; do not touch `cloud-init-inngest.yml` (also forbidden by the brief).

### Related issues and PRs

#7695 (this), #8017/#8015 (closed by this PR on met conditions), #8078/#7777/#8018 (re-graded, stay
open), #6894 + PR #8248 (ADR-142 blue-green, disjoint), #6178 (cutover umbrella; soak remnant is batch
step 4), #7674 (heartbeat arm; batch step 2), #8013 (ULID leak; unrelated, stays), PR #7778 (Merge B),
PR #8019 (probe_schema=8), PR #8191 (2.4 repoint), PR #8252 (`inngest-host-state.sh`).

### Conventions carried forward

`hr-before-asserting-github-issue-status` (every state above from `gh`), `hr-no-dashboard-eyeball-pull-data-yourself`
(rows pulled by script), `wg-use-closes-n-in-pr-body-not-title-to`, `wg-when-deferring-a-capability-create-a`
(retire-or-keep issue), `cq-cite-content-anchor-not-line-number` (edits below are anchored on text),
`hr-no-ssh-fallback-in-runbooks` (the new runbook prose names no SSH step).

### Research decision

Strong local context (the whole surface is in-repo and every claim was measured live); no external
research. Community discovery: no uncovered stack. Functional overlap: three registries queried,
no overlap (closest hits are ADR/runbook *authoring* templates, not evidence-based reconciliation).

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "the store is populated (hundreds of Redis keys)" | `redis_keys=1081` | Quote the measured figure |
| "the dedicated-host cutover completed on 2026-09-15" | Completed 09-15; the HOST was then replaced 09-17 (inherited-`done` incident) and recovered via `op=resume`; volume unchanged | Runbook prose must not say "the cutover host" — say "the volume the cutover landed on" |
| "guards that assume a pre-cutover dark host must be re-graded" | Only G8 encodes a pre-cutover shape; G9/G13/G19 are correct refusals | Re-grade = record the verdict table + re-prioritise #8078; no gate edit |
| "the four operator-gated dispatches were never run" | True; and two of the four (host-replace) have since happened for other reasons (09-09 user_data cap, 09-17 inherited done) — neither was the recut sequence | Say so in the plan addendum so the record does not read "no replace ever happened" |
| #7695 comment 2026-09-09: "The flush latch is NOT standing" | `flush_latched=true` since the 09-15 arm | Supersede explicitly in the issue-closing comment |
| "#8017 … #8018 are now moot post-cutover" (hypothesis) | #8017/#8015 not moot — RESOLVED (conditions met). #8078/#7777 not moot — dormant-consumer. #8018 not moot — process rule | Per-issue dispositions below |

## Issue dispositions (with evidence)

| Issue | Disposition | Evidence | Vehicle |
|---|---|---|---|
| **#7695** | **CLOSE** | Two evidence lines, neither a promise: (1) **build delivered** — Merge B `000fa4715` (2026-09-04, post-merge verification comment: `inngest-volume-recut-gate` 53/0, `inngest-host-dark-gate` 115/0, `inngest_volume_recut` job dispatch-only), plus the two later gate fixes #7761/#8019 now live on the host (`probe_schema=8`); (2) **dispatch refused by design against the measured row** — on `cutover_flag=done` G19 alone makes the target unreachable, and G8/G9/G13 refuse independently (`active`/`200`/`1081`). The cutover landed by the standard `op=arm` path (ADR-100 addendum 2026-09-15). The title's second clause — "nothing clears a standing /mnt/data flush latch" — is still TRUE and is #7777's, which stays open; the plaintext posture is #6894's (ADR-142). Closing is NOT "superseded by PR 8248" — 8248 is unmerged and closes nothing. | `Closes #7695` in PR body + closing comment with the verdict table and the quoted row fields |
| **#8017** | **CLOSE** | Its own close condition: live row with `probe_schema=8` carrying `data_mount_devid`. Measured: `probe_schema=8 data_mount_devid=scsi-0HC_Volume_106261946` on boot `ef763c72`, instance `hetzner-166317708`. G14 on main compares `data_mount_devid` (2026-09-10 amendment). The closing comment quotes the row fields verbatim. | `Closes #8017` |
| **#8015** | **CLOSE** | Its own close condition: live row with `probe_schema=8` carrying `registry_fns`. Measured `registry_fns=70`; `inngest-host-not-serving-7674.sh` rc=0 with the three-conjunct PASS message. G18 on main requires the third conjunct. The closing comment quotes `registry_fns=70` and the PASS line verbatim. | `Closes #8015` |
| **#8078** | **STAY OPEN, re-grade `priority/p1-high` → `priority/p3-low`** | Defect confirmed on main (G8 `== inactive`). Its consumer is dormant on this volume (G13 refuses before G8 matters for any real dispatch; latch forbids emptying the store). Fixing it is only worth doing if the target survives the retire-or-keep decision. | `Ref #8078`; comment linking #8316; `gh issue edit 8078 --remove-label priority/p1-high --add-label priority/p3-low` |
| **#7777** | **STAY OPEN, re-scope** | The circularity now binds for real: the latch STANDS (`flush_latched=true`). It matters in exactly one live scenario — a P1-13 rollback during the ADR-100 soak (ends 2026-09-22) followed by a re-arm, which `flush_already_performed` refuses into `aborted`. After the soak and after ADR-142 lands (copy, never flush) there is no planned consumer. Also mis-labelled `domain/legal` by automated triage. | `Ref #7777`; comment with the bound scope, the cross-link "clause 2 of #7695's title now lives here", and the re-evaluation trigger (decided together with #8316 once PR 8248 merges and the soak closed without a rollback); relabel `domain/legal` → `domain/engineering` |
| **#8018** | **STAY OPEN, unchanged** | A process-rule proposal (`AGENTS.rules.md`) whose trigger — dispatching an irreversible step after a partial predicate sweep — is not specific to the recut; the rule was never added (0 hits). Cutover completion changes nothing about its validity. Rule authoring is an AGENTS-budget decision outside this chore. | `Ref #8018` only — no comment (an "unchanged" note is not a measured disposition) |
| **#8316** (filed at plan time, 2026-09-18) | **OPEN — the retire-or-keep decision** | "chore(inngest): retire-or-keep decision for the dormant `inngest-volume-recut` target, after PR 8248 lands". Carries: the dormancy finding; the 8248-set files that still describe the recut as the remediation (content anchors "recuts /mnt/data today; the design for one is tracked in #7695" in `cutover-inngest.yml`, "recovery from `aborted` is a /mnt/data recut via the inngest-host-replace window" in `cutover-inngest.sh`); dependents #8078, #7777; the Retire vs Keep checklists. Labels `type/chore domain/engineering priority/p3-low meta/machinery`, milestone "Phase 4: Validate + Scale", `Mandated-By: wg-when-deferring-a-capability-create-a`. Its re-evaluation trigger is the merge (or unmerged close) of PR 8248, which the operator authors; Phase 4.2 cross-links it from a comment on PR 8248 and adds `Ref #8285` (the plaintext backstop-volume retirement 8248's ADR-142 amendment schedules for the same volume, expiring 2026-10-22) plus the stale ADR-199 §Consequences anchor "Until the host is replaced, every dispatch" to its stale-prose list. | `Ref #8316`; Phase 4.2 edits its body |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — no runtime, config or dispatch
changes. The exposed party is an engineer reading the runbook mid-outage on the `done` host: a wrong
G3.7 sentence could send them toward a re-arm (refused, lands `aborted`, flag worse than `done`) or
toward "wait for the recut" (which can never fire here). The reconciled paragraph names the two real
routes (`op=resume`, P1-13 rollback) and says explicitly that a standing latch on a `done` host is
expected.

**If this leaks, the user's [data / workflow / money] is exposed via:** no vector — the PR contains
no secret values (the Doppler read printed names and two boolean-shaped flags only), no user data, and
the probe row quoted carries infrastructure identifiers only.

**Brand-survival threshold:** none

- threshold: none, reason: the diff is documentation, archival moves and issue state; it touches no
  sensitive path (`SENSITIVE_PATH_RE` matches none of the files in § Files to Edit) and no runtime.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open --json number,title,body --limit 200` (65
issues) contains no body naming `runbooks/inngest-server.md`, ADR-100, the 2026-09-02 plan, its spec
dir, or `inngest-host-dark-gate.sh`.

## Architecture Decision (ADR/C4)

Detection fires on the "reversal or extension of an existing ADR" arm: ADR-100 §"What remains open"
records a fact ("no apply_target recuts /mnt/data") that has been false since 2026-09-04, and the
dormancy + deferred-retirement of the target is a state a future engineer would be misled about.

### ADR

**Amend ADR-100** (`knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`,
DISJOINT from 8248) with an append-only addendum — no new ordinal, no edit of the superseded text:

`## Addendum — 2026-09-18 (#7695) — the recut target exists, and is dormant on the volume the cutover landed on`

Body (≤ 25 lines): (1) the 2026-08-25 addendum's "there is still no `apply_target` that recuts
`/mnt/data`" is superseded, not edited — `apply_target=inngest-volume-recut` merged 2026-09-04 (PR
#7778) behind the `inngest-cutover` environment, dispatch-only; (2) against the live row of
2026-09-18 its Guard 2 is unreachable on G19 alone (`cutover_flag=done`) and G9/G13 refuse
independently (`http_code=200`, `redis_keys=1081`) — correct refusals under ADR-199; G8 refuses for
the right outcome (`server_active=active`) through the `== inactive` predicate this ADR's 2026-09-11 §7
already records as the #8078 defect class — say so, so the file does not contradict itself; (3) the durable flush latch stands since the 2026-09-15 arm and survived the
2026-09-17 replace, so the store can be emptied only through the append-only clear #7777 defers, which
makes the target dormant on `106261946`; (4) the plaintext posture is #6894's and is carried by
ADR-142's additive path; (5) retire-or-keep is a separate decision, tracked on #8316 (with #8285, the
scheduled retirement of this same volume as the plaintext backstop after the ADR-142 cutover), gated on
that path landing — this addendum does not retire anything; "dormant on this volume" is the only verb. ADR-199 is not edited here (it is in PR
8248's file set); this addendum cites it.

### C4 views

**No C4 impact** — asserted from the enumeration, not from a keyword grep. External human actors:
the operator (already modelled; no access relationship changes — this PR grants or removes no
dispatch). External systems/vendors: Hetzner (volume/server), Doppler, Better Stack, GitHub Actions —
all already present in `model.c4`; no element or RELATIONSHIP in the three `.c4` files models the
recut or cutover dispatch as an edge (measured: the only `recut` edge is zot's). One element
DESCRIPTION does name it — `inngestRedis`'s prose ("becomes crypto_LUKS only when the gated
`apply_target=inngest-volume-recut` dispatch destroys and recreates the volume") — and it is stale
after this plan, but `model.c4` is in PR 8248's file set and 8248 already rewrites that description;
the retire-or-keep issue #8316 carries it as a second stale-prose anchor in case 8248 does not land.
Nothing is added, removed or re-pointed here. Containers/data stores: `soleur-inngest` host and the Redis AOF
volume — unchanged; no new store. Actor↔surface relationships: unchanged. Derived cardinalities:
none of this PR's files is a `model.c4` count source (no monitor, heartbeat slug, workflow or cron is
added). `model.c4` is in PR 8248's file set and must not be edited here in any case. Verification is
AC10: `bash plugins/soleur/test/c4-count-parity.test.sh` green on the branch.

### Sequencing

The addendum describes the present state; it is true today, not soak-gated. Nothing waits on a later
slice.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Verdict "approve with changes", all applied in this revision. Risks named: (MEDIUM)
`INDEX.md`/`kb-tags.txt` ARE in 8248's set — a textual conflict is guaranteed and harmless; name it,
do not claim full disjointness (→ Overview, AC12). (MEDIUM) the G3.7 callout must lead with G19 —
on `cutover_flag=done` the recut is unreachable by the flag alone, so "the target exists" is not a
route (→ Phase 1.1(b), AC2). (LOW) the 2026-08-25 callout's measured example (host created 2026-08-20)
is stale after the 09-17 replace — refresh with `166317708`/2026-09-17 and state that
`flush_latched=true` + `flag=done` is the steady state of a healthy done host (→ Phase 1.1(c)). (LOW)
the second `issue: 7695` spec dir (`feat-one-shot-7695-inngest-image-pin-probe-schema`) would be
orphaned by the close — archive it (→ Phase 3.3/3.4, AC8). (LOW) cite content anchors, not
`file:line`, for the 8248-set stale comments carried on the new issue (→ dispositions table). Rulings:
(a) declining the G8 fix is correct — over-refusal on a refuse-by-default destructive gate, no
reachable consequence on the live host, and a fix would need a Guard Contract for a target that may be
retired; (b) close #7695 on "build delivered + dispatch refused by design against the measured row",
never on "superseded by 8248" (which is unmerged and closes nothing); the title's second clause stays
true and is #7777's (→ dispositions, Phase 4.3); (c) the rewrite must keep "op=resume is not a latch
remediation" and not invert it (→ Phase 1.1(d), AC2); (d) the CTO's claim that
`article-30-register.md` is not in 8248's set was re-measured FALSE (`gh pr diff 8248 --name-only`
lists it) — it stays on the not-edited list either way.

### Product/UX Gate

Not relevant — no user-facing surface (mechanical UI-surface scan of § Files to Edit: no `components/`,
`app/`, `.tsx`, `.njk` path).

### SpecFlow (Phase 3)

**Status:** reviewed — 8 findings folded: #8316 filed at plan time so its number reaches the prose;
rollback-is-one-way warning (1.1b); blockquote lazy-continuation hygiene + `FLUSH_LATCH_SINCE`
non-applicability (1.1a, (g)); `Closes` grep gated BEFORE the PR-body write (4.4); #8017/#8015
comments + AC19; AC6/AC9 literals. Its exit-5 follow-through probe was adopted and then cut at
plan-review (Cut List).

### Plan review (DHH, Kieran, code-simplicity, architecture-strategist)

Mechanical, applied: probe deleted (both panels fired on it — delete over fix); AC1 paragraph-scoped
(the runbook hard-wraps); AC2 awk terminator `!/^[[:space:]]*>/`; scenario greps the full AC1 string
(the strikethrough note also contains `Post-cutover status`); disjointness aligned to
INDEX/kb-tags everywhere; CTO ruling (d) re-measured false; G8 worded as the #8078 predicate so
ADR-100 does not contradict its own §7; `Ref #8285` + ADR-199 §Consequences anchor added to #8316;
C4 claim reworded to "no element names the dispatch"; Phase 0.4 read-and-record and 0.5 label check
dropped; spec `tasks.md` notes dropped (archive unchanged); #8018 comment dropped; AC15 folded into
AC11. Taste, not applied (recorded to `decision-challenges.md`): DHH's "trim Research Insights to
five bullets" and "drop `measurements.md`" — the plan skill mandates the section and the advisor
consult asked for the measurement file as the closing comments' source.

### Scoped advisor consult (Step 4.5, semantic tier `advisor`)

Two changes, both applied: the Phase 0.1 STOP set now includes the #8017/#8015 close-condition
fields and closing comments quote `measurements.md`; the #7695 verdict comment is posted in /work
before merge (not left to /postmerge) with a cross-link on #7777; the superseded runbook sentence is
struck where it is read (1.0), and "dormant on this volume" is the only verb permitted (Sharp Edges).

Legal, Finance, Marketing, Sales, Support, Operations: not relevant — no processing-activity change
(the Article 30 register and the AOF destruction record are untouched; no destruction occurs), no
spend, no external communication.

## Implementation Phases

### Phase 0 — Preconditions (measure, do not assume)

0.1 Re-run the four live reads (Better Stack probe row, Doppler two flags, Hetzner volume+server,
`doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/inngest-host-not-serving-7674.sh`)
and paste them verbatim into `specs/<branch>/measurements.md`. **STOP** — the premise moved and the
plan must be re-cut — if ANY of: `cutover_flag != done`; `redis_keys == 0`; volume id ≠ `106261946`;
`probe_schema != 8`; `data_mount_devid != scsi-0HC_Volume_106261946` (the #8017 close condition);
`registry_fns` absent or `0`, or the #7674 probe rc ≠ 0 (the #8015 close condition). Every closing
comment in Phase 4 quotes the fields from `measurements.md`, never the plan-time values above.
0.2 `gh pr diff 8248 --name-only > /tmp/8248.txt` and keep it for AC12.
0.3 `bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh --dry-run infra-inngest-volume-recut-luks`
and `… --dry-run one-shot-7695-inngest-volume-recut-luks` — each must list exactly one artifact.
0.4 `bash plugins/soleur/test/c4-count-parity.test.sh` → exit 0 (the C4 enumeration is already in
§ Architecture Decision; nothing to re-record).
0.5 Re-measure the two `- [ ]` counts (`26` / `40`) the archive ACs cite; a concurrent merge can move them.

### Phase 1 — Runbook (`knowledge-base/engineering/operations/runbooks/inngest-server.md`)

1.0 Mark the superseded sentence where it is READ, not only below it: in the 2026-08-25 blockquote,
wrap the sentence carrying the content anchor `There is **no `apply_target` that recuts `/mnt/data` today.**`
in `~~…~~` and append ` *(superseded 2026-09-18 — see the Post-cutover status callout below)*` on the
same line, leaving the anchor text itself byte-intact (an engineer reads top-down mid-outage and must
not act on the stale line; `cq-cite-content-anchor-not-line-number` keeps the anchor greppable).
Likewise rewrite the remediation sentence anchored `The latch clears only when the host's` so the
PRECONDITION comes before the mechanism: the latch clears only when the store is measured empty AND
the volume is recut (`apply_target=inngest-volume-recut`, ADR-199 Guard 2) — never by SSH, not by an
`inngest-host-replace` — keeping the preceding `op=resume` is not it (its G1 accepts `done` only)
clause verbatim.
1.1 In the G3.7 bullet, directly after that 2026-08-25 blockquote, insert a new correction
blockquote opening `> **Post-cutover status (2026-09-18, #7695).**` that: (a) states the target
merged 2026-09-04 (PR #7778) as `apply_target=inngest-volume-recut`, dispatch-only, behind the
`inngest-cutover` environment (so the paragraph above it is superseded on that point; paraphrase, do
not quote the old sentence); (b) **G19 first**: on `cutover_flag=done` the target is unreachable by
G19 alone (its flag set is `{rolled-back, aborted}`), independent of the store — so "the target
exists" is NOT a route from a `done` host; then, for the record, that G8/G9/G13 refuse independently
with the measured values (`active`/`200`/`1081`) — all four are ADR-199 doing its job, a populated
store on a serving host is never recut; (c) refreshes the measurement the 2026-08-25 callout carries
(it cites a host created 2026-08-20): as of 2026-09-18 the same volume `106261946` is attached to host
`166317708` created 2026-09-17 — a third host across two further replaces, latch intact; the durable
latch STANDS since `op=arm` run 34948112813 (2026-09-15) and `flush_latched=true` + `cutover_flag=done`
is the steady state of a healthy `done` host, not a fault to clear; (d) keeps the existing sentence
that `op=resume` is NOT a latch remediation (its G1 is `done`-only) and does not invert it: `op=resume`
is the route for a stalled or inherited `done` (§ Inherited `done`), the P1-13 rollback is the route
back, and a second `op=arm` is refused by design; (e) points the "latch clears only via recut" sentence
at its real precondition — an empty store, which this volume cannot reach without #7777; (f) names
#6894 / ADR-142 as the encryption route and the retire-or-keep issue #8316 as where the target's fate
is decided; (g) states that the `FLUSH_LATCH_SINCE` narrowing described at the end of the 2026-08-25
callout has **no application on this volume** — no recut has happened, the latch rows are genuine.
Cite the probe row read command already in § `inactive` because a standing `rollback` flag (no new
command).
1.1a **Anchor hygiene before inserting.** The 2026-08-25 blockquote ends in lazy-continuation lines
with no leading `>` (the sentence beginning `the old rows have not aged out, set the repo variable
`FLUSH_LATCH_SINCE``). Prefix those continuation lines with `> ` first so the blockquote closes
cleanly, then insert the new callout AFTER the last of them — never between them, and never so that an
`op=arm` re-dispatch imperative is the last instruction the reader sees.
1.1b In (d), add the one-way warning: on this volume a P1-13 rollback **cannot be re-armed** — after
`rolled-back`, `op=arm` G1 admits the flag (`cutover-inngest.sh` accepts `""|unset|aborted|rolled-back`)
but G3.7 and the on-host latch then refuse into terminal `aborted` (the #7777 scenario). An engineer
must read that before choosing rollback.
1.1c **Paste-ready callout** (the clauses above are the checklist; this is the text — indent to the
bullet's blockquote depth, `>`-prefix every line, keep the file's ~100-col wrap):

```markdown
> **Post-cutover status (2026-09-18, #7695).** The recut target now exists: `apply_target=inngest-volume-recut`
> merged 2026-09-04 (PR #7778), dispatch-only, behind the `inngest-cutover` required-reviewer
> environment. It is NOT a route from this host. On `INNGEST_CUTOVER_FLIP=done` (Doppler
> `soleur-inngest/prd`, the authority G19 reads; the row's `cutover_flag` mirrors it) its Guard 2 is
> unreachable on G19 alone (the flag set is `{rolled-back, aborted}`), and G8/G9/G13 refuse
> independently on the live row — `server_active=active`, `http_code=200`, `redis_keys=1081`
> (ADR-199: a populated store on a serving host is never recut; G8's `== inactive` form is #8078).
> As of 2026-09-18 the same volume `106261946` is attached to host `166317708` (created 2026-09-17,
> the third host since 2026-09-04, across two more replaces; Hetzner API
> `GET /v1/volumes/106261946` → `.volume.server`) with the latch intact. The durable latch STANDS
> since `op=arm` run 34948112813 (`gh run view 34948112813`, 2026-09-15): `flush_latched=true` +
> `cutover_flag=done` is the steady state of a healthy `done` host, not a fault to clear. Re-measure
> every row value above with `doppler run -p soleur -c prd_terraform -- scripts/inngest-host-state.sh`
> (the Better Stack probe row; § Reading host state without SSH). A second `op=arm` is refused by
> design.
> The routes from here are `op=resume` for a stalled or inherited `done` (§ Inherited `done`; it
> is still not a latch remediation) and the P1-13 rollback — and on this volume a rollback is
> one-way: after `rolled-back`, `op=arm` G1 admits the flag but G3.7 and the on-host latch refuse
> into terminal `aborted` (#7777). The `FLUSH_LATCH_SINCE` narrowing above has no application
> here — no recut has happened and the latch rows are genuine. The latch's real precondition is a
> measured-empty store, which this volume cannot reach without #7777; the plaintext posture is
> #6894's (ADR-142, additive), and the target's fate — dormant on this volume, not retired — is
> decided on #8316.
```

1.2 In § Quick reference (table shape `| Concern | Procedure |`, rows like
`| Scheduler dead after a host replace | [§ Inherited `done`](#inherited-done-after-a-host-replace-7228) |`),
add one row: `| Flush latch stands on a `done` host / `op=arm` refused at G3.7 | expected — [§ Dedicated-host cutover](#dedicated-host-cutover-phase-2-opexecute-gated-sequence--ref-6178), G3.7 post-cutover status |`
(G3.7 is a bullet, not a heading, so the link targets the enclosing section's existing anchor).
1.3 Run `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` — the linter
rejects a human-actor token and an infra-imperative token co-occurring on one line (its `ACTOR_RES` /
`IMPERATIVE_RES` lists); keep them on separate lines in the new prose.

### Phase 2 — ADR-100 addendum

2.1 Append the addendum specified in § Architecture Decision at the end of the file (after the
2026-09-15 addendum). Do not edit the 2026-08-25 §"What remains open" text.
2.2 `grep -c '^## Addendum — 2026-09-18 (#7695)' ADR-100…md` → 1.

### Phase 3 — Reconcile and archive the 2026-09-02 plan and its spec

3.1 Append to `knowledge-base/project/plans/2026-09-02-infra-inngest-volume-recut-luks-plan.md`:
`## Addendum — 2026-09-18 (#7695) — reconciled against the completed cutover; P1–P10 superseded`
stating: Merge A/B delivered (with the two later probe_schema fixes #7761/#8019); the post-merge
dispatch sequence never ran; two host replaces happened since for other reasons (09-09 user_data cap,
09-17 inherited done) and neither was Dispatch A/C; the cutover completed 09-15 via the standard path;
P1–P10 are superseded (P2 is in fact MET — the #7674 probe PASSes — but its consumer is not
dispatched); the encryption-posture flip (P9) and the destruction record (P10) belong to the ADR-142
path and stay unflipped/template.
3.2 The two spec `tasks.md` files are archived UNCHANGED — no note, no ticking (the 09-02 plan's
addendum is the record for its spec; the 09-07 pair's record is its merged PR #7887, 2026-09-08).
3.3 `bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh <slug>` for each of the four slugs
(dry-run-measured to move exactly one artifact each): `infra-inngest-volume-recut-luks` (09-02 plan),
`one-shot-7695-inngest-volume-recut-luks` (its spec), `fix-inngest-bootstrap-pin-and-guard-hardening`
(09-07 plan), `one-shot-7695-inngest-image-pin-probe-schema` (its spec) — git mv, history preserved.
Both `issue: 7695` pairs leave the active directories with the issue. Do NOT archive the 2026-09-10
probe_schema=8 plan/spec (`feat-one-shot-8017-8015-8013-probe-schema-8`): #8013 is still open.

### Phase 4 — GitHub records (Phase 4 runs in /work; the closes themselves fire at merge)

4.1 #8316 is already filed (plan time) — verify `gh issue view 8316 --json state` reads OPEN; do not
file a second one.
4.2 Comments on #8078 and #7777 per the table; relabels on #8078 and #7777. Edit #8316's body
(`gh issue edit 8316 --body-file`) to add `Ref #8285`, the ADR-199 §Consequences stale anchor, the
`model.c4` `inngestRedis` description anchor ("becomes crypto_LUKS only when the gated"), and the G8
wording of § Architecture Decision item (2). Post one comment on PR 8248: "when this merges,
the retire-or-keep decision for `inngest-volume-recut` is due — #8316". No comment on #8018.
4.3 Post the #7695 verdict comment **in /work, before merge** (not deferred to /postmerge — if
postmerge does not run, the tracker would sit closed with the 2026-09-09 "latch is NOT standing"
comment as its last word): the verdict table, the measured row fields from `measurements.md`, the
explicit superseding of the 2026-09-09 comment, and the sentence "closes on merge of PR #8314". Same
timing for the #8017/#8015 comments (each quoting its own close-condition field verbatim). Every
quoted field sits beside the one-line read that produced it (`doppler run -p soleur -c prd_terraform
-- scripts/inngest-host-state.sh` for row fields; `doppler secrets get INNGEST_CUTOVER_FLIP -p
soleur-inngest -c prd --plain` for the flag; the Hetzner `GET /v1/volumes/106261946` for the
attachment) — `hr-observability-layer-citation`. Add a
one-line cross-link comment on #7777: clause 2 of #7695's title ("nothing clears a standing /mnt/data
flush latch") now lives on #7777.
4.4 PR body: exactly `Closes #7695`, `Closes #8017`, `Closes #8015`; every other number as `Ref`.
**Gate BEFORE `gh pr edit --body`**, not after: `grep -oE 'Closes #[0-9]+' <drafted-body-file> | sort -u`
must print exactly those three lines (this plan's own Risks table contains the strings `Closes #7777` /
`Closes #8078` as examples of what must NOT appear — /ship drafts the body from the plan, and GitHub
links closures at creation time, so the grep runs on the draft). Then
`gh pr view 8314 --json closingIssuesReferences` must list exactly the three.

### Phase 5 — Verification

5.1 All ACs below; `bash scripts/test-all.sh` per the /ship full-battery checkpoint.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-7695-recut-postcutover-reconcile/measurements.md` —
  the Phase 0.1 verbatim reads (row, flags, Hetzner JSON, probe-script output).
- `knowledge-base/project/plans/archive/<ts>-2026-09-02-infra-inngest-volume-recut-luks-plan.md`,
  `knowledge-base/project/plans/archive/<ts>-2026-09-07-fix-inngest-bootstrap-pin-and-guard-hardening-plan.md`,
  `knowledge-base/project/specs/archive/<ts>-feat-one-shot-7695-inngest-volume-recut-luks/` and
  `knowledge-base/project/specs/archive/<ts>-feat-one-shot-7695-inngest-image-pin-probe-schema/` —
  via `archive-kb.sh` (renames, not new content).

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — Phase 1 (G3.7 post-cutover
  callout; Quick-reference row).
- `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`
  — Phase 2 addendum (append-only).
- `knowledge-base/project/plans/2026-09-02-infra-inngest-volume-recut-luks-plan.md` — Phase 3.1
  addendum, then archived.
- `knowledge-base/project/specs/feat-one-shot-7695-inngest-volume-recut-luks/` — archived unchanged.
- `knowledge-base/project/plans/2026-09-07-fix-inngest-bootstrap-pin-and-guard-hardening-plan.md` —
  archived unchanged.
- `knowledge-base/project/specs/feat-one-shot-7695-inngest-image-pin-probe-schema/` — archived unchanged.
- Pipeline-written: `knowledge-base/INDEX.md` (regenerated), `knowledge-base/kb-tags.txt` (only if
  /compound adds a new tag), `knowledge-base/project/specs/<branch>/{tasks,session-state}.md`, this
  plan, any `knowledge-base/project/learnings/*.md` from /compound.

**Not edited, by decision:** `apps/web-platform/infra/cloud-init-inngest.yml` (ForceNew, brief);
everything in PR 8248's file set (ADR-199, ADR-142, `cutover-inngest.{yml,sh}`,
`apply-web-platform-infra.yml`, `inngest-host.tf`, `model.c4`, encryption ledger, Article 30
register); `tests/scripts/lib/inngest-host-dark-gate.sh` (G8 fix declined — Cut List);
`knowledge-base/legal/audits/inngest-aof-destruction-record.md` (stays `status: template`).

## Acceptance Criteria

### Pre-merge (PR)

- AC1 `grep -c 'Post-cutover status (2026-09-18, #7695)' knowledge-base/engineering/operations/runbooks/inngest-server.md` → `1`, and the callout sits after the paragraph anchored `There is **no `apply_target` that recuts` (verify with `grep -n` ordering, not line numbers). That anchored line still exists exactly once and now also carries `~~` and `superseded 2026-09-18` (`grep -c 'recuts `/mnt/data` today.\*\*~~' <runbook>` → `1`). Paragraph-scoped (the file hard-wraps at ~100 cols, so no same-line assertion; two bullets carry `**Remediation:**`, so gate on the G3.7 bullet first): `awk '/G3\.7 pre-flush-latch/{g=1} g&&/\*\*Remediation:\*\*/{f=1} f&&/^[[:space:]]*$/{exit} f' <runbook>` — within that block `op=resume` is not it` is present, and `measured empty` occurs before `recut`.
- AC2 Within the callout — every line of it is `>`-prefixed (1.1a/1.1c), so extract with `awk '/Post-cutover status \(2026-09-18, #7695\)/{f=1} f&&/^[[:space:]]*$/{exit} f' <runbook>` (blank-line terminated; a `!/^[[:space:]]*>/` terminator would stop at the pre-existing lazy-continuation lines) — each of `inngest-volume-recut`, `INNGEST_CUTOVER_FLIP`, `G19`, `G8`, `G9`, `G13`, `redis_keys=1081`, `flush_latched=true`, `34948112813`, `166317708`, `inngest-host-state.sh`, `op=resume`, `rolled-back`, `#7777`, `#6894`, `#8316` occurs ≥ 1 time, the first `G19` precedes the first `G8`, and `op=resume` precedes `FLUSH_LATCH_SINCE`.
- AC3 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main 2>&1 | tail -1` → `OK: …`.
- AC4 `grep -c '^## Addendum — 2026-09-18 (#7695)' knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` → `1`; `git diff origin/main -- <ADR-100>` shows additions only (no `-` lines other than context).
- AC5 `[[ ! -e knowledge-base/project/plans/2026-09-02-infra-inngest-volume-recut-luks-plan.md ]]` and `ls knowledge-base/project/plans/archive/ | grep -c -- '-2026-09-02-infra-inngest-volume-recut-luks-plan.md$'` → `1`; `git log --follow --oneline -- knowledge-base/project/plans/archive/*2026-09-02-infra-inngest-volume-recut-luks-plan.md | wc -l` ≥ 2 (history preserved).
- AC6 The archived plan's last H2 starts with `## Addendum — 2026-09-18 (#7695)`; the archived spec dir is byte-identical to `origin/main`'s (`git diff origin/main:<old-dir> HEAD:<archived-dir>` empty) — boxes were not ticked.
- AC7 `[[ ! -d knowledge-base/project/specs/feat-one-shot-7695-inngest-volume-recut-luks ]]` and `find knowledge-base/project/specs/archive -maxdepth 1 -type d -name '*feat-one-shot-7695-inngest-volume-recut-luks' | wc -l` → `1` (a `find`, not `ls 2>&1 | wc -l`, which counts the no-such-file line as 1).
- AC8 `knowledge-base/project/plans/2026-09-10-fix-inngest-probe-schema-8-mount-devid-plan.md` and `knowledge-base/project/specs/feat-one-shot-8017-8015-8013-probe-schema-8/` still exist unarchived (#8013 open); `[[ ! -e knowledge-base/project/plans/2026-09-07-fix-inngest-bootstrap-pin-and-guard-hardening-plan.md && ! -d knowledge-base/project/specs/feat-one-shot-7695-inngest-image-pin-probe-schema ]]` and exactly one archived copy of each exists, byte-identical to `origin/main`'s (`git diff origin/main:<old-path> HEAD:<archived-path>` empty).
- AC9 `specs/<branch>/measurements.md` exists, non-empty, and contains `cutover_flag=done`, `redis_keys=`, `probe_schema=8`, `data_mount_devid=scsi-0HC_Volume_106261946`, `registry_fns=`, a line matching `grep -E '"id": ?106261946'`, and the `inngest-host-not-serving-7674.sh` `PASS` line.
- AC10 `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0 on the branch.
- AC11 Diff scope (run with `--no-renames` so the archive moves list BOTH sides; default rename detection would print only the destination): every path in `git diff --no-renames --name-only origin/main...HEAD` matches one of `knowledge-base/engineering/operations/runbooks/inngest-server.md`, `knowledge-base/engineering/architecture/decisions/ADR-100-*.md`, `knowledge-base/project/plans/2026-09-02-infra-inngest-volume-recut-luks-plan.md` (delete side), `knowledge-base/project/plans/archive/*`, `knowledge-base/project/specs/archive/*`, `knowledge-base/project/specs/feat-one-shot-7695-inngest-volume-recut-luks/*` (delete side), `knowledge-base/project/plans/2026-09-07-fix-inngest-bootstrap-pin-and-guard-hardening-plan.md` (delete side), `knowledge-base/project/specs/feat-one-shot-7695-inngest-image-pin-probe-schema/*` (delete side), `knowledge-base/project/specs/feat-one-shot-7695-recut-postcutover-reconcile/*`, `knowledge-base/project/plans/2026-09-18-chore-inngest-recut-postcutover-reconcile-plan.md`, `knowledge-base/INDEX.md`, `knowledge-base/kb-tags.txt`, `knowledge-base/project/learnings/*`.
- AC12 `comm -12 <(git diff --name-only origin/main...HEAD | sort) <(gh pr diff 8248 --name-only | sort)` prints nothing other than `knowledge-base/INDEX.md` and/or `knowledge-base/kb-tags.txt`; the PR body names the overlap.
- AC13 `gh pr view 8314 --json closingIssuesReferences --jq '[.closingIssuesReferences[].number]|sort'` → `[7695,8015,8017]` (gh's `--jq` prints compact JSON, measured).
- AC14 The PR body contains no closing keyword for any other issue (`grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?) #[0-9]+' | sort -u` → exactly the three, any case).
- AC15 `git diff --no-renames --name-only origin/main...HEAD | grep -c 'cloud-init-inngest.yml'` → `0` (restated from AC11 for the brief's explicit prohibition).

### Post-merge (postmerge skill — all automatable, no operator step)

- AC16 `gh issue view 7695 --json state --jq .state` → `CLOSED`; same for 8017 and 8015.
- AC17 `gh issue view 8078 --json labels --jq '[.labels[].name]'` contains `priority/p3-low` and not `priority/p1-high`; `gh issue view 7777 …` contains `domain/engineering` and not `domain/legal`.
- AC18 `gh issue view 8316 --json state,body --jq '[.state, (.body|test("#8285(\\D|$)")), (.body|test("Until the host is replaced"))]'` → `["OPEN",true,true]`; `gh pr view 8248 --json comments --jq '[.comments[].body] | map(test("#8316(\\D|$)")) | any'` → `true`.
- AC19 The verdict comment is the LAST comment on #7695 at merge time and after (`gh api repos/jikig-ai/soleur/issues/7695/comments --paginate --jq 'last.body'` — `gh issue view --json comments` caps at 100 — contains `superseded`, `closes on merge of PR #8314`, and `data_mount_devid=scsi-0HC_Volume_106261946`); the last comments on #8017 and #8015 contain `data_mount_devid=scsi-0HC_Volume_106261946` and `registry_fns=` respectively.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The runbook paragraph misleads an engineer on the `done` host during a future replace incident | It names `op=resume` and the § Inherited `done` section explicitly, and states the latch on a `done` host is expected |
| PR 8248 lands first and rewrites `INDEX.md` | INDEX is regenerated by the pipeline on rebase; the only shared path |
| A future rollback during the soak makes #7777 live again | #7777 stays OPEN with the exact scenario written into it |
| Closing #7695 reads as "the recut is retired" | The ADR-100 addendum and the new issue both say retirement is undecided and gated on 8248 |
| A `Closes #7777` / `Closes #8078` sentence sneaks into the PR body while arguing against closing | AC13/AC14; body uses `Ref` everywhere else |
| Premise moves before /work (rollback, new replace) | Phase 0.1 STOP condition |

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Fix G8 (#8078) here | Dormant consumer; requires a Guard Contract for a predicate that may be deleted; CTO consulted (Domain Review) |
| Retire the target now | Files are all in PR 8248's set; 8248's own plan hands the decision over as separate work; needs its own evidence after ADR-142 lands |
| Close #7777 as superseded now | It binds in the rollback-during-soak scenario until 2026-09-22 and until ADR-142 lands; closing would be on a promise |
| Leave #7695 open until 8248 merges | The issue is "build the target"; the target is built and verified; keeping it open conflates it with the encryption issue #6894 |
| Leave the 2026-09-07 image-pin plan/spec (`issue: 7695`) unarchived | CTO: closing the umbrella would orphan it; archived with a note instead. The 2026-09-10 pair stays — #8013 is open |

## Non-Goals

- No dispatch of any apply_target; no Doppler write; no Terraform; no scripts.
- No edit to any file in PR 8248's set, to `cloud-init-inngest.yml`, or to the gate libraries.
- No ADR-100 status flip (`adopting → accepted` is the #6178 soak remnant, batch step 4).
- No #7674 heartbeat arming (batch step 2); no cloud-init helper extraction (#7968, batch step 3).
- No AGENTS rule for #8018.

## Test Scenarios

- Given the runbook on the branch, when an engineer greps `Post-cutover status (2026-09-18, #7695)`,
  then exactly one callout is found under G3.7, it names `G19` before `G8`, it names `op=resume`
  before any mention of `FLUSH_LATCH_SINCE`, and it says a rollback cannot be re-armed on this volume.
- Given `origin/main`'s ADR-100, when the branch diff is read, then it is append-only.
- Given the archive script dry-run for both slugs, when run, then each lists exactly one artifact and
  the wet run moves it with history (`git log --follow` ≥ 2 entries).
- Given the PR body, when `closingIssuesReferences` is read, then it is exactly {7695, 8015, 8017}.
- Given the branch diff and 8248's file list, when intersected, then only `knowledge-base/INDEX.md`
  and/or `knowledge-base/kb-tags.txt` may appear.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. It is filled above.
- The runbook callout must PARAPHRASE the superseded sentence; quoting "no `apply_target` that recuts"
  verbatim would defeat any later absence-grep (see the correction convention already in that file).
- `archive-kb.sh` matches on slug substrings of the filename/dirname — the plan slug is
  `infra-inngest-volume-recut-luks` (not the branch name); the spec slug is the branch minus `feat-`.
  Run `--dry-run` first (Phase 0.3) and expect exactly one artifact each.
- Write the addenda BEFORE the archive move: `lint-infra-no-human-steps.py` skips `**/archive/**`,
  so a violation introduced into an already-archived file is invisible to CI but still wrong.
- Do not tick the old spec's boxes; superseded ≠ done (P-ARTIFACTS).
- Runbook and ADR-100 prose must say the target is **dormant on this volume** — never "retired".
  The retire-or-keep issue owns that verb; `grep -ci 'retired' <new callout / addendum>` → 0 except
  in the phrase "retire-or-keep".
- The closing comments are posted in /work and must quote `measurements.md`, not the plan; a probe
  regression between plan time and merge is exactly the false-resolved state the Phase 0.1 STOP set
  exists to catch.
