---
title: "feat: ship the Inngest TLS terminator's journald to Better Stack"
date: 2026-10-25
slug: ship-terminator-journald-to-better-stack
branch: feat-one-shot-terminator-journald-shipping
issue: 10136
closes: none
type: feat
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

The Inngest link self-gate failed a third time on 2026-10-24 with `phase=request` (run 40079474290: `rc=56 http=000 attempts=3 phase=request
tcp=3 tls=3 verify=0`, so TCP connected, TLS completed, the certificate verified, and no HTTP response came back). The stunnel terminator runs
as `soleur-inngest-tls.service` on the Inngest host only, and its journal is not shipped to Better Stack, so its side of the request stage
cannot be read without SSH. This plan ships that unit's journal through the host's Vector agent so the next self-gate failure is diagnosable
from Better Stack alone. It is the exit the runbook names for the `request` stop rule (ruling R2b of the prior self-gate PR, approved by the
owner as "move forward on the change").

The change is small in code and large in delivery. The code is a unit match on Vector Sources 1 and 2, a fail-open message filter that keeps
the row volume bounded, pins in three tests, a new `vector test` suite and two doc edits. The delivery has two paths for one file: web-1 and
web-2 receive it automatically when the PR merges (existing SSH provisioners), and the Inngest host receives it only through a new bootstrap
image and a host replace that is a production act needing the owner's typed go. This pipeline stops before merge; it dispatches nothing.

## Research Reconciliation — Spec vs. Codebase

| Brief or runbook claim | Reality (verified 2026-10-25) | Plan response |
|---|---|---|
| The runbook calls the change "a small `vector.toml` change by reading" (add the unit to Source 1 `include_units` and Source 2 `exclude_units`) | Source 1 admits the unit at every priority and stunnel's lines carry no `<N>` prefix, so they take systemd's default `SyslogLevel=info` (PRIORITY 6), as the runbook states and as the existing `inngest-server.service` rows show (derived, not measured on the host; the filter and the derived corpus do not depend on the value), so the bare change ships 4 lines per connection: about 1,150 rows/day today (the host's own 5-minute health probe) and an estimated 7,000 to 24,000 rows/day after a flip (`legacy_8288_packets` rose 36,368 over 24 hours). | Add a fail-open message-text filter (CTO T2), a row budget and a post-replace measurement. |
| "touching the #10880 carrier pin" (#10880 is the Guard A carrier-drift guard, open) | Guard A is green on HEAD today at v1.1.58 (the bump cleared the v1.1.57 drift; `cloud-init-inngest-bootstrap.test.sh` prints `GuardA: every baked carrier is byte-identical at vinngest-v1.1.58 (drifted: none)`). This PR reopens the red window until the next bump lands. `deploy-script-tests` is not a required check (#9081 is the open PR-context exemption). | `Ref #10880`, never `Closes`; the PR body states the red window (CTO T5). |
| "delivered via a bootstrap-image digest bump and an Inngest host replace" | The same `vector.toml` is also delivered to the running web-1 and web-2 by `terraform_data.journald_persistent` and `..._web2` (their `triggers_replace` hashes the file), which run in the merge-triggered apply and restart journald and vector on both web hosts. | Name the web fan-out as a merge-time production effect (CTO T3). |
| "No issue tracks it" (runbook, `request` row) and "not shipped" | True today; false once this PR merges and the replaced host runs v1.1.59. The live host runs v1.1.57 (Better Stack `pre-zot-pull` row, 2026-10-20T09:26:39Z). | Runbook wording is conditional on the image tag (CTO T6). |
| The runbook's replace precondition: `inngest-userdata-budget.sh` green with at least 300 B margin | HEAD prints stored 32,512 B of 32,768 B, headroom 256 B (offline), and the CI render exceeds the offline measure by an unmeasured amount. The next replace also carries c15ed71796, e002f2bc47 and dc9391d11c and two image generations (v1.1.57 to v1.1.59). This PR adds 0 B. | A separate trim PR must merge before the replace go is asked (CTO T4); this PR does not restate the precondition. |
| Older ledgers cite a 25,000 rows/day Better Stack threshold | Retired: the account is on a paid tier after the 2026-08-14 quota exhaustion (HTTP 402 on every ingest for about 49 hours). Better Stack rows read for 2026-10-24 UTC: soleur-inngest-prd 106,560; no host_name 65,935; soleur-web-platform 25,836; soleur-web-2 9,823. The paid limit is unverified and the vendor exposes no usage endpoint. | The budget is stated per unit (400 before a flip, 8,000 after) and measured after the replace. |

## Research Insights

**Premise Validation.** Checked: #10205 (open epic), #10136 (open, the encryption-posture item), #10880 (open, drift now cleared), draft PR #10975,
the prior self-gate PR d9e38b4c87 (an ancestor of `origin/main`), the runbook section "Reading `selfgate_failed`" (its `request` row names this exit),
ADR-294 (adopting; three flip addenda), the live link state (both web hosts print `class=resolved state=http_default scheme=http` through
2026-10-25T09:56Z, so the link is http and the flag is absent), and the production evidence path (Better Stack only; reads below were made through
`doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh`). Held: every cited artifact exists and the decode table row is as
described. Stale or narrower than stated: #10880's drift (cleared at v1.1.58) and "small change" (see the reconciliation table).

**Property List.**
1. An agent can read the terminator's own side of a `phase=request` failure from Better Stack, with no SSH.
2. Each journal record reaches Better Stack through at most one source (the partition contract of #6551 holds).
3. The terminator's row volume is bounded and the bound is measured after delivery; a wording mismatch over-ships and never silences.
4. The change reaches each host through its existing delivery path, and the one act with user impact (the Inngest host replace) happens only on the owner's typed go.
5. The web hosts' observability is not degraded by the shared-file delivery.
6. The runbook and ADR say truthfully, per image tag, whether the journal ships.

**Cut List.**
- Source 4 identifier match on `stunnel4` -> property 1 -> covered by the unit arm, which also ships the ExecStartPre fetch script's output (CTO T1).
- Lower stunnel's `debug` level in `cloud-init-inngest.yml` -> property 3 -> covered by the filter at zero `user_data` bytes (CTO T2).
- An Inngest-only vector config split -> property 5 -> the existing designed delivery already protects web hosts with a `.prev` restore (CTO T3).
- A new Better Stack alert on terminator error lines -> no property in the ask needs it; the diagnosis is an on-demand read, and alert routing for `op=inngest-link` is the open #10556.
- Fixing the user_data size and the `fetch_rc=93` oddity in this PR -> separate sequencing items (CTO T4, T5).
- Any flip, canary or apply dispatch -> the next flip is a separate owner act.

**Existing mechanisms checked (authority named).** The `tls-health` stage row (`cloud-init-inngest.yml`, `/usr/local/bin/soleur-inngest-tls`) samples
the terminator's unit state every 5 minutes and "describes the terminator only: no field shows its upstream" (runbook, `request` row), so it does not
buy property 1. The `/hooks/inngest-tls-handshake` call repeats the gate's request against the installed CA and "adds nothing while the gate is failing"
(same row). Source 4 and the unit arm of Source 1 are the only journald admission mechanisms in `vector.toml` (grepped: `include_units`,
`exclude_units` appear only in `vector.toml`, `vector-admission.test.sh`, `inngest-step-524-alert.test.sh`, the runbook and ADR-286).

**Measured evidence (not re-derived from the incident).**
- stunnel 5.72 line shapes, captured locally in a container (scratch `stunnel-measure.out`): a healthy request logs `LOG5 Service [inngest] accepted
  connection from <ip:port>`, `LOG5 s_connect: connected 127.0.0.1:8288`, `LOG5 Service [inngest] connected remote server from ...` and `LOG5 Connection
  closed: 59 byte(s) sent to TLS, 78 byte(s) sent to socket`. Upstream refused (the incident's curl shape, rc 56) logs `LOG3 s_connect: connect
  127.0.0.1:8288: Connection refused (111)`, `LOG3 No more addresses to connect`, `LOG5 Connection reset: 0 byte(s) sent to TLS, 0 byte(s) sent to
  socket`. Upstream accepts then closes with no reply (curl rc 52) logs `LOG5 Connection closed: 0 byte(s) sent to TLS, 78 byte(s) sent to socket`.
  A plain-HTTP client logs `LOG3 SSL_accept ... http request`; a client rejecting the certificate logs `LOG3 SSL_accept ... tlsv1 alert unknown ca`.
  Startup logs 7 `LOG5` lines. The level is in the message text only. The container has no journald, so the line shapes are measured but the journald PRIORITY is derived (above). Not measured: the host's stunnel build (Ubuntu package), so the filter fails open.
- `tls-health` rows, Better Stack, 2026-10-24T13:33Z to 2026-10-25T13:27Z: one boot (`94b7cf33`), `unit=active nrestarts=0 listener=1`, served and
  Terraform certificate fingerprints equal, `legacy_8288_packets` 10,867 to 47,235, `tls_8443_packets` constant at 21. All rows show `fetch_rc=93`
  (the Doppler key fetch in the unit's ExecStartPre failed at the last start; `die()` falls back to existing material and exits 0). Observed, not
  explained, and not explained by this journal either (the fetch script discards doppler stderr); tracked separately (CTO T5).
- `bash apps/web-platform/infra/inngest-userdata-budget.sh`: raw 229,750 B, stored 32,512 B, cap 32,768 B, headroom 256 B.

**Institutional learnings applied** (learnings researcher, 2026-10-25):
- `2026-10-19-the-sinks-have-admission-rules-journald-priority-annotation-alphabet-and-job-ceiling.md`: stdout is PRIORITY 6 and stderr PRIORITY 3; a
  source admits only what its rules name. Applied: the unit arm is used because PRIORITY cannot split stunnel's lines.
- `2026-07-18-adr-ordinal-collision-sweep-and-off-box-journald-cost-surface.md`: shipping a unit's journal off-box changes its trust and quota
  properties. Applied: the sweep of every line the unit can emit (below) and the drop-list filter.
- `2026-07-18-web-1-root-doppler-unit-needs-home-and-dedicated-token-and-vector-toml-has-no-running-host-delivery.md`: a `vector.toml` edit is file-only
  on a host that never re-runs cloud-init. Applied: delivery is verified live (rows from the new boot), not by the committed file.
- `test-failures/2026-10-06-which-files-feed-user-data-with-no-ignore-changes-decides-whether-a-mechanical-edit-is-a-host-replace.md` and
  `workflow-patterns/2026-06-18-inngest-bootstrap-release-tag-then-dispatch-deploy.md`: the tag, build, bump, dispatch flow; an image edit is a replace.
- `2026-07-03-cloud-init-32kb-cap-bake-and-extract-not-compress.md`: the 32,768 B cap is hard. Applied: CTO T4.
- `2026-06-10-betterstack-quota-diagnosis-host-metrics-dominate-generic-http-sink.md`: measure per-source rows first. Applied: the per-host counts above.
- `build-errors/2026-06-18-vector-interpolates-dollar-vars-in-comments.md`: Vector interpolates `$VAR` in `vector.toml` comments. Applied: no dollar-variable text in new comments.

**Sweep of what the unit can emit (leak check, per the off-box journal learning).** `stunnel4` lines carry timestamps, the config path, peer
addresses (the web hosts' private IPs and the host's own), byte counts and TLS error strings; startup at `LOG5` prints no key or certificate material.
The ExecStartPre script `soleur-inngest-tls fetch` writes only a return code to a file and discards doppler stderr; it prints no secret. The shipped rows
traverse `pii_scrub_drop_userdata`, `pii_scrub_structured` and `pii_scrub_string` like every other journald row.

## Hypotheses

The change does not assume a cause of the `phase=request` failure. The shipped rows discriminate the candidates in one read (measured line shapes
above): upstream down (`LOG3 s_connect ... Connection refused`), upstream closed with no reply (`Connection closed: 0 byte(s) sent to TLS, N byte(s) sent
to socket` with N above 0), a handshake-class fault on the terminator (`LOG3 SSL_accept`), or no per-connection close or reset row for the gate's window
(the connection was still open, the rows were not shipped, or the host is on an older image: check the unit's row count and the boot first).
The keyword gate for network checks matched `timeout` and `handshake` in the brief; the L3 checks (firewall allow-list, routing) are already carried
by the decode table's `connect` row and the `tls=3 verify=0` fields, which place the failure above L4: TCP and TLS completed.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Ship the terminator-journald (stunnel TLS terminator) logs to Better Stack so the Inngest link self-gate's `phase=request` stage becomes diagnosable" [brief] | Phase 2 (`vector.toml` Source 1/2 + filter), Files to Edit 1 | mapped |
| 2 | "a `vector.toml` Source 1/2 change delivered via a bootstrap-image digest bump and an Inngest host replace, touching the #10880 carrier pin" [brief] | Phase 2, `## Infrastructure (IaC)` delivery, Operator Holds TJ-2 and TJ-3 | mapped |
| 3 | "state in the plan exactly which hosts need what delivery and in what order" [brief] | `### Host fan-out` and the delivery order table | mapped |
| 4 | "read runbook knowledge-base/engineering/operations/runbooks/inngest-server.md section 'Reading selfgate_failed' (the `request` stop rule names this change as its exit) and ADR-294" [brief] | Phase 4 (runbook edit, ADR-294 addendum), Files to Edit 6 and 7 | mapped |
| 5 | "The PR body must state the host replace order, the blast radius (Inngest host replace, scheduler and reminders), the precondition list and the typed-go ask." [brief] | `## PR Body Requirements` | mapped |
| 6 | "Run the full pipeline through plan, work, review and ship with --stop-before-merge semantics." [brief] | Phase 6, AC10 | mapped |
| 7 | "arm nothing and MERGE NOTHING (a merge auto-applies, and any Inngest host replace is a production act needing the owner's typed go naming that act; a menu answer is not a go)" [brief] | `## Operator Holds`, AC9 | mapped |
| 8 | "the plan must declare brand_survival_threshold (this surface holds user queue and run state: expect `single-user incident`)" [brief] | frontmatter and `## User-Brand Impact` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Files to Edit 1: `apps/web-platform/infra/vector.toml` (Source 1/2 unit match, filter transform, wiring) | "a `vector.toml` Source 1/2 change" | asked |
| The fail-open message-text filter inside Files to Edit 1 | asks 1 and 2 | inferred - justification: with the bare unit match every stunnel line ships (all PRIORITY 6, measured), which could re-trigger the 2026-08-14 ingest refusal that blinded the whole fleet; CTO T2 rules the filter |
| Files to Edit 2: `apps/web-platform/test/infra/vector-admission.test.sh` | "update `apps/web-platform/test/infra/vector-admission.test.sh`, which pins both lists" (runbook, quoted in the brief's reading) and ask 2 | inferred - justification: the suite pins both lists, so the edit reds it; the partition contract rots without the rows |
| Files to Edit 3: `apps/web-platform/test/infra/inngest-step-524-alert.test.sh` | ask 2 | inferred - justification: it pins `include_units = ["inngest-server.service"]` and the `inputs` list verbatim (line 275) and would red on the change |
| Files to Create 1 and 2: `scripts/vector-terminator-filter.test.sh` and `apps/web-platform/infra/vector-terminator-filter.test.toml` | ask 1 | inferred - justification: `vector validate --no-environment` accepts VRL that does not compile (the workflow header says so), and a bad filter would first reach the web hosts at merge |
| Files to Edit 4: `.github/workflows/validate-vector-config.yml` | ask 1 | inferred - justification: the new `vector test` suite is only blocking if this workflow runs it and its path filter covers the new files |
| Files to Edit 5: `knowledge-base/engineering/architecture/diagrams/model.c4` (one clause on the `inngest -> betterstack` edge) | ask 4 | inferred - justification: the edge description enumerates what is shipped from the Inngest node and would be incomplete; the C4 mandate makes the edit part of this lifecycle |
| Files to Edit 6: `knowledge-base/engineering/operations/runbooks/inngest-server.md` | "the `request` stop rule names this change as its exit" | asked |
| Files to Edit 7: `knowledge-base/engineering/architecture/decisions/ADR-294-inngest-link-tls-terminator-and-flagged-flip.md` (addendum) | "and ADR-294" | asked |
| PR Body Requirements section | "The PR body must state the host replace order" | asked |

### Split Assessment

- Subsystems touched: 3 - `apps/web-platform` (infra config and tests), `.github` (one workflow path filter), `knowledge-base` (runbook, ADR, C4)
- Planned files: 10 | Estimated changed lines: 380
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The two sequencing items the CTO rules out of scope (the `user_data` trim and the `fetch_rc=93` fix) are separate PRs because they edit `cloud-init-inngest.yml`.

## Files to Edit

1. `apps/web-platform/infra/vector.toml` - Source 1 `include_units`, Source 2 `exclude_units`, new `inngest_terminator_filter` transform, `pii_scrub_drop_userdata` `inputs`, header comments (no dollar-variable text).
2. `apps/web-platform/test/infra/vector-admission.test.sh` - the S1 and S2 unit pins (lines ~294 to 299, which also carry text naming `inngest-server.service` alone; sweep the mirror and `sinks.betterstack` pins in the same block), and literal terminator corpus rows at PRIORITY 0, 3, 4, 5 and 6.
3. `apps/web-platform/test/infra/inngest-step-524-alert.test.sh` - the line-275 shape pin (two units) and the `inputs` regex, which must become a `tomllib` parse that asserts the filter's `inputs` and `pii_scrub_drop_userdata`'s `inputs` separately (the old regex would pass vacuously on the filter's own `inputs = ["inngest_journald"]` line), plus its mutation row V1 (the 524 rows still ship through Source 1; re-run `scripts/probe-inngest-524-count.sh` through Better Stack per the comment at that pin and record `unit_rows`).
4. `.github/workflows/validate-vector-config.yml` - run the new suite (blocking, `REQUIRE_VECTOR_TEST=1`), add the two new files to both `paths:` filters (they list files, not globs), and check the job's `timeout-minutes: 5` still fits the added step.
5. `knowledge-base/engineering/architecture/diagrams/model.c4` - one clause on the `inngest -> betterstack` edge.
6. `knowledge-base/engineering/operations/runbooks/inngest-server.md` - the `request` row and the paragraph under the decode table.
7. `knowledge-base/engineering/architecture/decisions/ADR-294-inngest-link-tls-terminator-and-flagged-flip.md` - one addendum paragraph.

## Files to Create

1. `scripts/vector-terminator-filter.test.sh` - structure check (python3 `tomllib` over the real `vector.toml`) plus `vector test` against the real file, modelled on `scripts/vector-egress-rollup.test.sh`.
2. `apps/web-platform/infra/vector-terminator-filter.test.toml` - `vector test` cases: the measured stunnel lines (verbatim), a line of another unit that matches a drop prefix, a row with no `.message`, an unknown-wording stunnel line.
3. `knowledge-base/project/specs/feat-one-shot-terminator-journald-shipping/tasks.md` - the work breakdown.

Glob check (`hr-when-a-plan-specifies-relative-paths-e-g`): every path above was resolved against the tree (`git ls-files`) or is marked create. The new suite must be registered where `lint-orphan-test-suites` looks (the workflow step above is the registration; verify at work time that the lint accepts it).

## Open Code-Review Overlap

None found at plan time for the paths above (checked with a two-stage `gh issue list --label code-review` plus `jq --arg`; re-run at work time after the file list is final).

## Domain Review

**Domains relevant:** Engineering, Product (sign-off only; no UI surface)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** One batched consult on 2026-10-25 ruled six items (T1 to T6) and is recorded verbatim in `decision-challenges.md`: admission by the unit arm,
a fail-open drop-list filter with a row budget, acceptance of the web-host fan-out, a separate `user_data` trim before the replace go, `Ref` not
`Closes` for #10880, and conditional runbook wording with an ADR-294 addendum.

### Product (CPO sign-off, single-user-incident threshold)

**Status:** reviewed (2026-10-25); disposition under `### CPO disposition` below. No UI surface (no page, component or flow); the Product/UX gate is not triggered.

### Legal and compliance

**Status:** no regulated-data surface by the canonical regex (no schema, migration, auth, route or `.sql` file in the lists). The single-user-incident
trigger (b) makes the GDPR gate advisory here: the shipped rows hold peer addresses of the owner's own hosts, byte counts and TLS error strings, no
end-user identifier or payload; the existing three-stage PII pipeline sits in front of the sink. See `## Plan Review Disposition

Panel (single-user-incident threshold): DHH, Kieran, code-simplicity, architecture-strategist, spec-flow; CPO as the named business reviewer (sign-off above). Findings classified per ADR-084.

- **Cut the filter and its chain (DHH, code-simplicity).** A technical fork, so it went back to the CTO (not to the owner): R1 on 2026-10-25 keeps the filter, because a wrong or missing filter later costs a second image and a second replace of the sole scheduler; the design takes three changes from the review (infallible VRL, one `vector test` case per class with `no_outputs_from`, a `tomllib` wiring assertion). Simplifications adopted per R2: literal terminator rows instead of a derived loop, Guard 2 trimmed to three rows, `journald-config.test.sh` run-only, the `fetch_rc=93` issue is not an acceptance gate. The C4 clause stays.
- **Mechanical, auto-applied:** the priority claim reworded as derived (not measured on the host) with PRIORITY 3 and 5 in the corpus; the cutover-heartbeat premise corrected (Source 4, not Source 1; E13 is in `scripts/cutover-inngest.sh`); the web-host-birth content-hash caveat; time-ordered fan-out; the evidence that a bump merge does not replace the Inngest host (PR #10878); `inputs` readers named; workflow `paths:` and `timeout-minutes`; the quiesce op as an Operator Hold; the typed go bound to tag, digest and host id with a re-verify; failure branches (bump chain, degraded mirror, half-applied replace, no rows after replace); two precondition lists; the first-hour read and an independent signal for ingest refusal; the 24-hour clock defined; the unknowns recorded.
- **Taste, recorded and not applied:** staggering web-1 and web-2 (needs a Terraform change this PR does not make); whether the typed go expires (the owner's call; the plan binds it to the tag and digest and requires a re-verify); whether the go also covers dispatching the resume (the plan says it does not).

## Sharp Edges` for the gate run.

### Gates evaluated and not triggered

- Encryption posture (Phase 2.11): no new store and no new cross-component connection (the rows use the existing `sinks.betterstack` HTTPS sink); no `.tf`, `cloud-init*.yml` or compose file is in this PR's lists.
- Task design (Phase 2.9.3): no new autonomous-task surface (a filter transform is not a workflow, function, timer or daemon).
- Skill description budget (Phase 1.8): no `SKILL.md` description is edited.

## User-Brand Impact

- **If this lands broken, the user experiences:** the Inngest host replace (the delivery of this image) makes the sole scheduler unavailable for a bounded
  window, so cron-fired agent runs and reminder fires are delayed (each missed tick fires once on resume) and event sends during the window can fail: the
  dashboard send archives the draft with `degraded=enqueue_failed` (#10543 is still open), a reminder arm returns a retryable 503 or a 502 the caller must
  re-arm, and webhooks release their dedup row and redeliver. A broken `vector.toml` reaching web-1 and web-2 at merge would take host observability dark
  there until the `.prev` restore runs; a broken filter that silences rows would blind the cutover heartbeat that `cutover-inngest.yml` reads.
- **If this leaks, the user's workflow data is exposed via:** the shipped rows themselves: they must carry no key, certificate or request payload. The
  terminator terminates TLS for event payloads (user prompts and agent output) but logs only peer addresses, byte counts and error strings; the exposure
  vector to guard is a future `debug` level or a wording change that prints more, which the keep-set and the fail-open design do not cover, so the
  stunnel `debug` level stays untouched and the fixture pins the measured shapes.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one tier above `aggregate pattern` because the only act with user impact, the host replace, acts on the sole
  scheduler and the queue and run state of every user, and a single lost reminder or archived draft is a visible, personal failure; the code change
  alone would be `none`.

The Inngest host replace is a production act that needs the owner's typed go naming that act. This plan, the PR and this pipeline never perform it.

## Operator Holds

Every item below is an act this pipeline does NOT take. Each needs the owner's own typed go naming the act (an AskUserQuestion option is a menu
acknowledgement, not a go: `hr-menu-option-ack-not-prod-write-auth`). No delegation is recorded on #10205, so the in-session per-command form is the live authority.

| Act | What it does in plain words | Authority |
|---|---|---|
| TJ-1: merge this PR | Re-delivers `vector.toml` to web-1 and web-2 (restarting journald and vector on both) and arms the automatic tag, build and pin-bump chain. | owner's typed go naming the merge |
| TJ-2: automatic bump chain | After TJ-1 a mint cuts `vinngest-v1.1.59`, the build publishes and mirrors the image, and a bot PR bumps the four pin lines (auto-merge armed when the zot mirror reports `ok`). Nothing deploys. | none new (consequence of TJ-1); watched, not dispatched |
| TJ-3: Inngest host replace | The Inngest host (the sole scheduler) is destroyed and recreated from `user_data` pinned to v1.1.59; the scheduler and reminders are unavailable for a bounded window. **A production act: needs the owner's typed go naming the replace.** Not delegable (a replace has no nameable rollback); a re-dispatch after a failed or in-flight replace needs a fresh go. | owner's typed go naming the replace dispatch |
| TJ-4: resume after the replace | `INNGEST_CUTOVER_FLIP=done` is inherited, so the new host refuses to start the scheduler until a resume runs, and the `inngest-cutover` environment approval is owner-human. | owner (dispatch may follow a recorded delegation; the approval never does) |
| TJ-5: the 24-hour volume read | Count the unit's rows before any flip; report. Read-only through Better Stack. | none (read-only) |
| TJ-3a: quiesce for the window | The `cutover-inngest.yml` quiesce op (reminder arming) set for the replace window, and the replay check afterwards. A production act: never taken unprompted. | owner's typed go naming the quiesce, or the same go that names the replace if it says so in terms |
| The next flip | Separate owner act, outside this plan. The A5, A6 and A7 records stay owner-typed and are not written here. | owner |

**What the typed go is bound to.** The go for TJ-3 names the image tag and digest it will deploy (v1.1.59 and its `@sha256`) and the host id read just before dispatch (the dispatch has no id-pin input, #10544), and the executing session re-verifies the agent-checkable preconditions immediately before dispatching; a go given earlier does not carry over a changed pin. A go covers the replace dispatch only; the resume (TJ-4) needs its own dispatch and the owner's environment approval, and the session pings the owner when the replace is dispatched because the approval wait was 30 of the 35 measured minutes on 2026-09-27.

**Failure branches the plan does not leave open (each ends at an owner go, never at an agent retry).**
- Bump chain fails (build, mirror or bot PR red): Guard A stays red on `main`; the session arms a watch on the mint and build runs with a stated deadline of the next session start, reads the stage-named `::error::` lines and uses the runbook's auto-mint recovery table (every row is a `gh` command or a code fix). It never hand-writes a pin after a refusal at stage `args`, `ancestry` or `resolve`.
- Zot mirror degraded (`mirror_status` not `ok`): auto-merge does not arm. An agent does not merge the bot PR by hand; the owner decides after the `mirror_only` backfill the build's warning names. Mirror `ok` is re-read at the go, not only after the bump.
- Replace half-applied (destroyed with no create, created with no `bootstrap-done`, up with the unit failed): read-only recovery per the runbook's "Abort thresholds" (10 minutes after the apply with `provision-unit-armed` and no `provision-attempt-start`, 2 hours with no `bootstrap-done`, `tls-health` absent 30 minutes after the apply) and the apply run's recovery-read block, then stop; a re-dispatch needs a fresh owner go. The owner may pre-authorize a conditional retry in the same go; that is the owner's choice, not assumed.
- No terminator rows after the replace: cross-check the host's `tls-health` rows and its other vector-shipped rows for the new `boot_id` (vector broken versus unit down versus Better Stack refusing ingest); never restart the unit (#10545) and never SSH; hand off to the owner with those reads.

## Infrastructure (IaC)

### Terraform changes

None authored by this PR. The PR edits no `.tf` file and no `cloud-init*.yml`. Terraform reacts to it in two existing places: `terraform_data.journald_persistent`
and `terraform_data.journald_persistent_web2` (`server.tf`) hash `vector.toml` in `triggers_replace`, so the merge apply re-runs them; and, after the
automatic bump PR (not this PR) edits the pins in `cloud-init-inngest.yml`, `hcloud_server.inngest` plans a replace on its next dispatch because its
`user_data` has no `ignore_changes`. No sensitive variable is added.

### Apply path

(b) the separately gated `inngest-host-replace` dispatch for the Inngest host (a running host with durable state: the Redis AOF volume is retained by
omission and the destroy-guard asserts zero deletes), and the existing merge-time SSH provisioners for web-1 and web-2. Expected disruption: 79 seconds
from server creation to `bootstrap-done` on the clean 2026-09-27 path, about 2.5 minutes of apply, then the inherited-`done` resume; plan 15 to 60 minutes
plus approval latency (incidents measured: 59 and 76 minutes).

### Host fan-out

Delivery order, by time (the answer to "which hosts need what, in what order"):

| Step | Host | Delivery | Trigger | Order and notes |
|---|---|---|---|---|
| 1 | web-1 | `vector.toml` copied, validated (`vector validate`), installed, vector restarted, `.prev` kept for restore | `terraform_data.journald_persistent` (SSH provisioner), merge apply | automatic at TJ-1; the new unit match is inert (no terminator unit there) |
| 1 | web-2 | same | `terraform_data.journald_persistent_web2`, merge apply | automatic at TJ-1; the two provisioners run in the same apply and are not staggered (a stagger would need a Terraform change this PR does not make); verify vector `active` on both through each host's own rows after the apply |
| 2 | web-1, web-2 `cloud-init.yml` and Inngest `cloud-init-inngest.yml` pin lines | four pin lines bumped by the automatic bot PR | TJ-2 (after the mint and build) | inert for running hosts: web `user_data` has `ignore_changes`, and the push apply's `-target` list excludes `hcloud_server.inngest` (evidence: the v1.1.58 bump PR #10878 merged 2026-10-22T23:56Z and the live Inngest host kept running v1.1.57) |
| 3 | Inngest host | `vector.toml` rides the bootstrap image `soleur-inngest-bootstrap` v1.1.59; a host created from `user_data` pinned to it extracts the file | the owner-gated `inngest-host-replace` dispatch (TJ-3), gated on the separate `user_data` trim PR having merged, then the resume (TJ-4) | the only host that runs the terminator; an in-place edit of a running Inngest host does not exist (replace-only, ADR-100) |
| - | registry host, git-data host | none | n/a | they do not consume this file (`cloud-init-git-data.yml` says `vector.toml` reaches the web host alone; the registry has no `vector.toml` delivery) |
| - | a NEW web host (birth or replace) | `vector.toml` is also a baked carrier of the web app image (`host_scripts_content_hash`, `server.tf`; verified at boot by `cloud-init.yml`) | `web-host-create` or `web-host-replace` | do NOT birth or replace a web host between this merge and the publish of the app image built from it: the boot-time content-hash verify would fail closed. Running hosts are unaffected |

Fleet siblings are classified `twin` for the provisioner (both web hosts get the file hot, already enforced by `web-host-provisioner-parity.test.sh`); no new
`terraform_data` is added, so no parity entry changes.

### Distinctness / drift safeguards

Guard A (`cloud-init-inngest-bootstrap.test.sh`) compares the pinned tag's tree with HEAD's carriers byte for byte. After TJ-1 it is red on the PR and on `main`
until the bump lands (one mint, build and bump cycle); `deploy-script-tests` is not a required check (#9081). AC6 and the digest-freshness job are unchanged.

### Vendor-tier reality check

Better Stack is on a paid tier of unverified limit; the vendor exposes no usage endpoint (expenses ledger). The terminator budget is stated per unit and measured
from rows (below), not from a plan limit.

## Downtime & Cutover

**The offline-inducing operation.** The Inngest host replace (TJ-3): `hcloud_server.inngest` is destroyed and recreated, so the sole scheduler (cron-fired agent runs, reminder arming and firing) is unavailable until `bootstrap-done` and the resume. The merge itself restarts journald and vector on web-1 and web-2, which takes no serving surface offline (the app container keeps serving; only log shipping pauses for seconds, and `.prev` is restored on a rejected config).

**Zero-downtime paths evaluated, and why none applies to the Inngest host.**
- Blue-green (a second Inngest host, cut over, old one retired): refused by design. ADR-100 and `inngest-server-flip-guard.sh` enforce exactly one prod scheduler (the guard prints `BLOCK: cutover flag='done' but this host carries no done-owner marker` for a second start), so two hosts cannot run together.
- In-place delivery of `vector.toml` without a replace: not available. The signed config-refresh channel (`inngest-config-refresh-set.txt`) admits only host-executed `*.sh` scripts and its membership rules bind (a config file is not a member, and the engine itself is never a member), so `vector.toml` rides the image and an image edit reaches the host only through a replace (runbook, "Refresh-channel cross-ref").
- Drain-then-act: partly available and used. The `cutover-inngest.yml` quiesce op covers reminder arming for the window and the replay check follows (TJ-3a); a clean replace is 79 seconds from server creation to `bootstrap-done` and the queue and run state survive on the retained Redis AOF volume.
- Defer to a replace that is needed anyway: the CPO's suggestion, recorded as a scheduling option the owner may take. The only costs of waiting are that the next self-gate failure stays as hard to diagnose as the last one and that a user_data trim is needed before any replace.

**Residual downtime accepted with a bounded window and owner sign-off.** Plan for up to about 80 minutes (measured: 59 and 76 minutes in incidents, 34 minutes 49 seconds on the clean 2026-09-27 path of which about 30 were approval latency). The window is chosen by the owner, low-traffic, with the quiesce op set, and begins only on the owner's typed go naming the replace. Per-stage verification and rollback: the runbook's A1 success evidence (boot event with the private NIC up, `bootstrap-done` for the new `iid`, `tls-health` rows with `listener=1`), the abort thresholds (10 minutes, 2 hours, 30 minutes) and, for a failed replace, a fresh owner go; there is no rollback of a replace (the link stays http, so nothing needs reverting on the web side).

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-294 with one dated addendum (decision of this PR: the terminator's journal ships through Sources 1 and 2, the drop-list filter keys on message text
and fails open, the row budget, shipping starts only on the replaced host). It is not a new ADR: the mechanism is ADR-286's admission model applied to one more
unit, and ADR-294 already carries the flip addenda. Written in this PR, not deferred.

### C4 views

Read all three files (`model.c4` 1,031 lines, `views.c4` 142, `spec.c4` 54). Enumeration: (a) external human actors: none added; (b) external systems: Better Stack is
already modelled (`betterstack`, with the `inngest -> betterstack` edge at the Vector shipping description); no new vendor; (c) containers and stores: the `inngest`
container already carries the TLS terminator edge (`api -> inngest`, ADR-294); no new store; (d) access relationships: none change. Conclusion: no new element or
edge; the one `inngest -> betterstack` edge description enumerates what that edge ships and gains a clause naming the filtered terminator journal. Run
`apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` after the edit (the clause adds no count).

### Sequencing

The decision is true for the template at merge and for the Inngest host only after the replace; the addendum says so, and the runbook wording is keyed to the image tag.

## Observability

```yaml
liveness_signal:
  what: terminator journal rows in Better Stack source 2457081 with _SYSTEMD_UNIT soleur-inngest-tls.service - startup rows per boot and one Connection closed row per 5-minute health probe (about 288 per day before a flip)
  cadence: 5 minutes (the host's own tls-health timer drives the probe connection)
  alert_target: none added - this is an on-demand diagnosis surface; the tls-health stage rows and the selfgate_failed event stay the alerting inputs, and the Sentry rule for op=inngest-link is the open #10556
  configured_in: apps/web-platform/infra/vector.toml (Sources 1 and 2, inngest_terminator_filter) and cloud-init-inngest.yml (tls-health timer, unchanged)
error_reporting:
  destination: Better Stack Logs source 2457081, filtered by host_name soleur-inngest-prd and the unit
  fail_loud: LOG3 rows (s_connect refused, No more addresses to connect, SSL_accept errors) and Connection reset rows are always kept by the filter
failure_modes:
  - mode: the filter's wording does not match the host's stunnel build and over-ships
    detection: a group-by-message-prefix read over the first hour after the resume (a dropped class present means the wording differs), then the unit row count over the first 24 hours before any flip, both through betterstack-query.sh, compared with the 400 per day budget; the 24-hour clock starts at the first startup row of the new boot_id and its baseline excludes that boot's startup rows
    alert_route: the executing session reads it after the replace and fixes the filter before the flip go is asked
  - mode: vector rejects the new config on web-1 or web-2 at merge
    detection: the provisioner prints FATAL and restores vector.toml.prev (the apply fails loudly); Better Stack shows no rows for that host_name after the apply
    alert_route: the failed merge apply run and the existing host-dark Better Stack checks
  - mode: no terminator rows after the replace
    detection: zero startup row for the new boot_id within 30 minutes of bootstrap-done, read through betterstack-query.sh
    alert_route: the executing session; the stop rule in the runbook stays in force
  - mode: Better Stack ingest refused for quota (HTTP 402) after a flip
    detection: the existing ingest-402 detection, an independent signal that does not ride the blocked sink (the self-gate and deploy-state side of the flip, and the host-dark Better Stack checks), and the unit row count over 10,000 per day
    alert_route: the second drop in the CTO ruling (Connection closed lines with both byte counts above 0), never the 0-byte shapes
logs:
  where: Better Stack Logs source 2457081 (host_name soleur-inngest-prd, unit soleur-inngest-tls.service)
  retention: 90 days (measured on the source 2026-09-04 per the expenses ledger)
discoverability_test:
  command: bash -c 'doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 1h --grep "Connection closed" --limit 3'
  expected_output: Connection closed
  credentials_required: BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD in Doppler soleur/prd_terraform (read-only ClickHouse connection) - no unauthenticated probe verifies that rows reached the warehouse
```

## Encryption Posture

No persistent store and no new cross-component connection is introduced; the terminator's rows reuse the one existing store and the one existing connection below, both already declared. This section exists so the gate reads a posture, not an absence.

```yaml
at_rest:
  - store: betterstack.logs (existing; scripts/encryption-posture-ledger.json, source 2457081)
    mechanism: provider-managed:betterstack-encrypted-at-rest
    evidence: the ledger row names the vendor security documentation (attestation_url https://betterstack.com/security, retrieved_on 2026-07-24); this PR adds rows to the same source and changes no store property
    defends_against: physical-media compromise of the log store
    does_not_defend: a leaked Better Stack API token; log sanitization at the emitter (the three pii_scrub transforms and the fail-open filter's drop-list) is the primary control against sensitive data reaching the sink
    disclosed_as: not-publicly-claimed
    live_verification: unavailable - named SOC 2 attestation formalization pending, tracked #6911 (inherited from the ledger row)
in_transit:
  - connection: Vector on the Inngest host to the Better Stack ingest sink (sinks.betterstack in vector.toml, existing)
    tls: HTTPS to https://s2457081.eu-fsn-3.betterstackdata.com/ with a bearer token
    cert_verification: on (the sink block sets no tls override; verified by reading the block, vector.toml lines 800 to 812)
    does_not_defend: a compromised Vector process or host (it holds the token), and Better Stack-side access
    disclosed_as: not-publicly-claimed
```

## Guard Contract

### Guard 1 — terminator admission partition

**Property.** Every journald record of unit `soleur-inngest-tls.service`, at every priority, is admitted by exactly one source (`inngest_journald`) and by no other.

**Assembly.** The journald source set as the real `vector.toml` declares it, modelled by the evaluator in `vector-admission.test.sh`: Source 1 `include_units` and its two
`exclude_matches` maps, Source 2 `exclude_units` and its `exclude_matches`, Sources 3 and 3b `include_matches.CONTAINER_NAME`, Source 4 `include_matches.SYSLOG_IDENTIFIER`. The
chokepoint is the parsed TOML model (never a hand list). The corpus is literal terminator rows at PRIORITY 0, 3, 4, 5 and 6 (CTO R2: a derived per-unit loop is cut), and
the exact-list equality pins on Source 1 `include_units` and Source 2 `exclude_units` are what catch a second unit added to one list only.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | remove `soleur-inngest-tls.service` from Source 1 `include_units` | RED (the PRIORITY 6 terminator record is admitted by no source, and the equality pin fails) |
| 2 | remove it from Source 2 `exclude_units` only | RED (the PRIORITY 2 terminator record is admitted by Source 1 and Source 2: multiplicity 2) |
| 3 | rename the sources' `type` so the model parses zero journald sources | RED (the suite exits 2 on an empty model and reports zero cases; never "0 checked, pass") |
| 4 | add a SECOND, third-listed unit to Source 1 `include_units` after the compliant first, and not to Source 2 `exclude_units` | RED (the exact-list equality pins fail on both lists) |

The CTO trimmed this matrix to rows 1 to 3; row 4 stays because the guard-contract rule requires a row that adds a second member after a compliant first, and the equality
pin (not a loop) is what makes it RED (plan-author note P2 in `decision-challenges.md`).

**Harness rows.** Edit the SUITE: make the evaluator ignore `exclude` maps -> RED (the existing multi-admission rows must redden). Must-PASS non-canonical input: a fixture
`vector.toml` that lists the same two units in the opposite order and a PRIORITY 5 record for the terminator unit -> PASS for the evaluator rows (order is permitted; the equality
pin compares sorted lists).

**Anchor.** No stored value is compared; the corpus is literal rows and the pins are read from the file under test. What moves outside the commit for a weakening to pass: nothing, because the
evaluator reads the file in the same diff, so this guard proves consistency of the partition, not that Vector's evaluator matches the emulator; the emulator's fidelity is
pinned to Vector 0.43.1 `journald.rs` by the existing header comment and by the live row record after delivery.

### Guard 2 — terminator filter keep and drop set

**Property.** The filter drops exactly the three healthy-request line shapes of unit `soleur-inngest-tls.service` and passes every other row: any other unit, a row with no
`.message`, every `LOG0` to `LOG4` line, every `Connection reset` and `Connection closed` line, startup lines and any unknown wording.

**Assembly.** The `condition` of `[transforms.inngest_terminator_filter]`; its `inputs` (exactly `["inngest_journald"]`); the `inputs` of `pii_scrub_drop_userdata` (must name the
filter's output and still name every other source, and must not name the raw `inngest_journald`); the fixture file `vector-terminator-filter.test.toml`, whose population is every
line in the measured stunnel output plus synthetic unknown lines. The chokepoint is the one transform every Source 1 record flows through before the PII stages.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | leave `pii_scrub_drop_userdata` `inputs` on the raw `inngest_journald` (filter unwired) | RED (the `tomllib` wiring assertion) |
| 2 | add a SECOND drop pattern for `Connection closed` after the compliant three | RED (the 0-byte closed shape is dropped; the per-class `vector test` case for it fails; CTO: never dropped) |
| 3 | make the extractor or the fixture file yield zero test cases (the guard's own dispatch) | RED (a floor on the number of `[[tests]]` cases and on the extracted condition bytes: "0 checked" cannot pass) |

CTO R1 trimmed this matrix to the wiring row: the other four mutations of the earlier draft (drop every row, drop nothing, drop the unit check, and the like) are exactly what the
per-class `vector test` cases prove directly, so they are cases, not mutation rows. Rows 2 and 3 stay because the guard-contract rule requires a second-member row and an own-dispatch row.
Mutation rows run in the `vector test` half of the suite (they edit a temp copy of `vector.toml` and need a Vector binary); under `REQUIRE_VECTOR_TEST=1` a missing binary is a failure, and
without it the half is reported SKIP and never as a pass.

**Harness rows.** Edit the SUITE: make the extractor return an empty condition -> RED (the same floor). Must-PASS non-canonical input: a stunnel line with different wording (`LOG6`, another
service name), a row with no `.message`, and a row whose `.message` is not a string -> PASS through unfiltered.

**Anchor.** The fixture lines are measured against stunnel 5.72 in a container; the host's build is unverified, so the anchor outside the commit is the post-replace row count over
24 hours before any flip (CTO T2): over 400 per day or a dropped class present means the wording differs and the filter is fixed before the flip go.

## Implementation Phases

### Phase 0: preflight (work phase)

1. `git fetch origin && git rebase origin/main` (never merge main in; no stash). Re-run the `gh issue list --label code-review` overlap check on the final file list.
2. File the two trackers the rulings create, as separate issues (O3): the `user_data` trim PR (target at least 500 B offline, must merge before the replace go; precondition: CI render at least 300 B margin on the trial merge; a hard precondition, so it is an acceptance gate) and the `fetch_rc=93` oddity (sequenced after the trim; states that this journal will not explain it; filed, but not an acceptance gate of this PR per CTO R2). Milestone from `knowledge-base/product/roadmap.md`.
3. Confirm the Vector binary for `vector test` (pinned 0.43.1 from `vector.tf`, or `timberio/vector:0.43.1-alpine`); record the path.

### Phase 1: failing tests first (`cq-write-failing-tests-before`)

Run each suite alone with stdin from `/dev/null`; each must go RED for the intended reason before Phase 2.
1. `vector-admission.test.sh`: update the S1 and S2 unit pins to the two-unit lists; add literal terminator rows (PRIORITY 0, 3, 4, 5, 6). Verify the harness rows.
2. `inngest-step-524-alert.test.sh`: update the line-275 shape pin (two units; `inputs` now reaches `inngest_journald` through the filter) and V1; keep V2.
3. `scripts/vector-terminator-filter.test.sh` and `vector-terminator-filter.test.toml`: the structure half (python3 `tomllib`: the filter's `inputs`, and `pii_scrub_drop_userdata`'s `inputs` naming the filter and not the raw source) and the `vector test` half with ONE `[[tests]]` case per class (a case that expects a dropped line uses `no_outputs_from = ["inngest_terminator_filter"]`, since a test has one `extract_from` per output): the three dropped lines, each kept class (the `LOG3` refusal lines, `Connection reset`, both `Connection closed` shapes, startup, the `SSL_accept` lines), a differently-worded line, another unit's line with a drop prefix, a message-less row and a row whose `.message` is not a string; `REQUIRE_VECTOR_TEST` turns a missing binary into a failure.
4. Write the Guard 1 and Guard 2 mutation rows as suite rows before the guard changes (a mutation row edits a copy of `vector.toml` in a temp dir, never the real file).

### Phase 2: `vector.toml`

1. Source 1: `include_units = ["inngest-server.service", "soleur-inngest-tls.service"]`; update the header comments that say the source admits `inngest-server.service` (the ADMISSION SEMANTICS block) and the `Consequences` bullets. Keep the SYSLOG_IDENTIFIER and CONTAINER_NAME mirrors untouched.
2. Source 2: `exclude_units` carries the same two units (excludes win; the two lists move together; `vector.service`'s CRIT path is unchanged).
3. New transform `[transforms.inngest_terminator_filter]`: `type = "filter"`, `inputs = ["inngest_journald"]`, `condition` an INFALLIBLE VRL drop-list that fails open. A Vector filter treats a runtime error in its condition as false and DROPS the event, and `vector validate --no-environment` does not compile VRL, so every field read carries a fallback: `unit = string(._SYSTEMD_UNIT) ?? ""` and `msg = string(.message) ?? ""`, then a pure boolean: pass when `unit` is not `soleur-inngest-tls.service`; pass when `msg` is empty (absent or not a string); otherwise drop only when `msg` contains (via `contains()` with literal strings, so `[inngest]` needs no escaping) `Service [inngest] accepted connection from`, `s_connect: connected 127.0.0.1:8288` or `Service [inngest] connected remote server from`. Everything else passes. No `$VAR` text in comments.
4. Rewire `pii_scrub_drop_userdata` `inputs`: replace `"inngest_journald"` with `"inngest_terminator_filter"`.
5. Comments: record the budget (400 per day before a flip, 8,000 after), the second-drop rule, that PRIORITY cannot split the lines (all PRIORITY 6) and that the stunnel wording is measured on 5.72 only.

### Phase 3: validate

Each command alone, stdin from `/dev/null`: `vector validate --no-environment --config-toml apps/web-platform/infra/vector.toml` (and the rendered `@@HOST_NAME@@` form the workflow uses);
`vector-admission.test.sh`; `vector-pii-scrub.test.sh` (with the fixture pepper and `VECTOR_BIN`); `scripts/vector-terminator-filter.test.sh`; `inngest-step-524-alert.test.sh`;
`journald-config.test.sh`; `cloud-init-inngest-bootstrap.test.sh` (expect Guard A to name `vector.toml` as drifted: advisory, #9081; every other row green; the local run's
tool-gated floor message is the known local skip, CI installs the tool); `inngest-userdata-budget.sh` (expect 256 B, unchanged). Run `scripts/probe-inngest-524-count.sh`
through Better Stack and record `unit_rows` (the 524 rows must still ship).

### Phase 4: docs

1. Runbook, `request` row and the paragraph under the decode table: conditional wording keyed to the image tag, the three decodes (upstream refused; closed with no reply; no per-connection row), the line "healthy `accepted connection`, `s_connect: connected` and `connected remote server` lines are omitted by design", the budget and the 24-hour check. Keep the stop rule: never re-flip on `phase=request` alone, every flip needs the owner's per-command go. Do NOT write "no stunnel line means it never reached the terminator" (P1 in `decision-challenges.md`). Replace "No issue tracks it" with the tracker number only once one exists; reword "no cause is readable" only after the first post-replace row shows terminator lines.
2. ADR-294 addendum (dated 2026-10-25, one paragraph).
3. `model.c4`: one clause on the `inngest -> betterstack` edge; run the three C4 tests.
4. Run `python3 scripts/lint-infra-no-human-steps.py` over the changed docs and plan.

### Phase 5: PR body (see `## PR Body Requirements`)

### Phase 6: review and ship, stop before merge

`soleur:review` (the single-user-incident panel includes `soleur:engineering:review:user-impact-reviewer` and `soleur:engineering:review:observability-coverage-reviewer`), then `soleur:ship` with
`--stop-before-merge`: the PR is marked ready only if the owner's merge go is given; otherwise it stays draft. No workflow is dispatched; no merge is armed.

## PR Body Requirements

The PR body must state, in plain sentences, each of the following (draft text; `soleur:ship` renders the `decision-challenges.md` table beside it). CPO condition: the PR body LEADS with item 0 in plain language, before any jargon (stunnel, journald, Guard A).

0. **The plain-language ask (first lines of the PR body).** "Nothing is broken for users today: the link between the app and the scheduler is still the old plain one, and this change does not touch it. Merging this PR causes no user impact; it only adds logging to two web servers (a short restart of the logging agent). The one step with user impact comes later and needs your separate go: replacing the scheduler's server so it can send us the logs that explain the last failed switch-over. While that server is replaced, scheduled agent runs and reminders are unavailable and late (plan for up to about 80 minutes; the measured past windows were 59 and 76 minutes), event sends can fail during the window, and a dashboard draft can be archived without being sent (issue #10543 is still open, so that must be fixed or the window quiesced first). This is optional hardening: if you decline, nothing changes for users, and the next switch-over failure stays as hard to diagnose as the last one (or needs a one-off server read). I recommend a low-traffic window, ideally the next time the host has to be replaced anyway."
1. **What it does.** Ships the stunnel terminator's journal (`soleur-inngest-tls.service`) to Better Stack through Sources 1 and 2 with a fail-open drop-list filter, so a `phase=request` self-gate failure can be read from Better Stack.
2. **Delivery and host replace order.** (1) Merge: web-1 and web-2 get `vector.toml` through the existing SSH provisioners and restart journald and vector (the new rules are inert there; `.prev` restore on a rejected config). (2) Automatic: mint `vinngest-v1.1.59`, build and mirror, bot pin-bump PR. (3) Owner-gated: the Inngest host replace, then the resume. The link stays http throughout; the flip is a separate owner act.
3. **Blast radius.** The Inngest host replace makes the sole scheduler unavailable for a bounded window (clean path 79 seconds to `bootstrap-done`, plan 15 to 60 minutes plus approval latency); scheduler ticks and reminder fires are delayed and each missed tick fires once on resume; event sends can fail during the window (webhooks redeliver, a reminder arm may need re-arming, #10543 dashboard send is open); the Redis AOF volume is retained.
4. **Precondition list for the replace go (two lists).** Agent-checkable, read by the executing session immediately before dispatch: the PR is merged and the automatic chain finished (pin on `main` is v1.1.59, mirror `ok`, Guard A green again); the `user_data` trim PR is merged and the CI-rendered `user_data` on the trial merge shows at least 300 B margin including c15ed71796, e002f2bc47, dc9391d11c and the v1.1.59 digest; the link is http on both web hosts (`class=resolved state=http_default`); no in-flight `apply-web-platform-infra.yml` or `registry-host-replace-dispatch.yml`; stock preflight and destroy-guard pass; #10542 is closed and #10543 is fixed or the window is quiesced with the replay check (a HARD precondition per the CPO: the dashboard draft archived on a failed enqueue is the one personal, visible loss, and when the choice is the quiesced window, the replay check is named in the go); the host id is recorded before dispatch and after; the runbook sections "Replace triggers" and "Inherited `done`" are re-read; the CI-rendered `user_data` margin is read from the trial merge's plan output (the offline script's number does not count). Owner-attested, asked in the go: the low-traffic window is chosen, the quiesce op (TJ-3a) is set, and the owner is available for the `inngest-cutover` environment approval.
5. **The typed-go ask.** "This replaces the Inngest host so it boots from the image that ships the terminator's journal; the scheduler and reminders are unavailable for a bounded window and need your approval to resume. Reply with your own go naming the Inngest host replace. A menu answer is not a go." Also state: merging needs a separate typed go naming the merge.
6. **Issue and CI notes.** `Ref #10136`, `Ref #10205`, `Ref #10880` (never `Closes`); Guard A reds on the PR and on `main` until the bump lands (advisory, #9081); nothing in this PR dispatches a workflow.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `vector.toml` Source 1 `include_units` and Source 2 `exclude_units` both equal `["inngest-server.service", "soleur-inngest-tls.service"]` (`vector-admission.test.sh` asserts it).
- [ ] AC2 `vector-admission.test.sh` proves exactly one admitting source (`inngest_journald`) for literal terminator rows at PRIORITY 0, 3, 4, 5 and 6, and every Guard 1 mutation row goes RED.
- [ ] AC3 The filter drops exactly the three measured healthy-request prefixes of the terminator unit and passes every other fixture (kept classes, another unit, no `.message`, unknown wording), proven by one `vector test` case per class against the real `vector.toml` (`scripts/vector-terminator-filter.test.sh`, `REQUIRE_VECTOR_TEST=1`) with infallible VRL (a row whose `.message` is not a string passes), the `tomllib` wiring assertion holds, and every Guard 2 mutation row goes RED.
- [ ] AC4 `vector validate --no-environment` is green on `vector.toml` and on its rendered `@@HOST_NAME@@` form with Vector 0.43.1.
- [ ] AC5 `inngest-step-524-alert.test.sh` is green with the updated shape pin and its V1 and V2 rows RED on mutation; `unit_rows` from `scripts/probe-inngest-524-count.sh` is recorded.
- [ ] AC6 The runbook and the ADR-294 addendum state, per image tag, whether the journal ships, name the three decodes and the omitted lines, and keep the stop rule; neither says an absent line means the request never reached the terminator.
- [ ] AC7 The PR body carries the six items under `## PR Body Requirements` and the `decision-challenges.md` table.
- [ ] AC8 `inngest-userdata-budget.sh` still reports headroom 256 B (this PR adds 0 B to `user_data`); Guard A names only `vector.toml` as drifted; every other row of `cloud-init-inngest-bootstrap.test.sh` is green.
- [ ] AC9 Nothing is merged, armed or dispatched by this pipeline; the PR stays draft unless the owner gives a typed merge go.
- [ ] AC10 The `user_data` trim tracker exists as a separate issue (a hard precondition of the replace go); the `fetch_rc=93` issue is filed but is not a gate; `Ref #10880` appears and `Closes #10880` does not.
- [ ] AC11 `python3 scripts/lint-infra-no-human-steps.py` is clean over the plan, runbook and ADR edits; the C4 tests and `c4-count-parity.test.sh` are green.

### Post-merge (owner-gated; not performed by this pipeline)

- [ ] TJ-1 merge on the owner's typed go; both web hosts show vector `active` after the merge apply (their own rows keep arriving).
- [ ] TJ-2 the automatic chain ends with the pin on `main` at v1.1.59, mirror `ok`, Guard A green.
- [ ] TJ-3 and TJ-4 only after the precondition list is met and the owner's typed go names the replace; success evidence per the runbook A1 row plus startup rows of `soleur-inngest-tls.service` for the new `boot_id` in Better Stack.
- [ ] TJ-5 the unit's row count over the first 24 hours before any flip is at most 400 per day, and none of the three dropped classes is present.

## Test Scenarios

- Given the measured healthy-request lines, when they pass through `inngest_terminator_filter`, then `accepted connection`, `s_connect: connected` and `connected remote server` are dropped and `Connection closed: 59 byte(s) sent to TLS, 78 byte(s) sent to socket` is kept.
- Given the upstream-refused lines (`LOG3 s_connect ... Connection refused (111)`, `LOG3 No more addresses to connect`, `Connection reset: 0 byte(s) ...`), then all three are kept.
- Given the upstream-closed shape (`Connection closed: 0 byte(s) sent to TLS, 78 byte(s) sent to socket`), then it is kept.
- Given a `LOG3 SSL_accept ... http request` line and a `tlsv1 alert unknown ca` line, then both are kept.
- Given a line of another unit that contains `Service [inngest] accepted connection from`, then it is kept (fail open).
- Given a terminator row with no `.message`, or whose `.message` is not a string, then it is kept; given an unknown-wording stunnel line (`LOG6 ...`), then it is kept.
- Given a third unit added to Source 1 `include_units` without Source 2 `exclude_units`, then the exact-list equality pins red.
- Given `pii_scrub_drop_userdata` `inputs` still naming the raw `inngest_journald`, then the wiring assertion reds.

## Dependencies & Risks

- **Shared file, two delivery paths.** A rejected config at merge reaches web-1 and web-2 first; mitigated by `vector validate` plus `vector test` in CI and the provisioner's `.prev` restore. Rollback: revert the PR (the mint then publishes a new, higher version; never tag an older commit).
- **Shared pipeline.** The cutover heartbeat that `scripts/cutover-inngest.sh` grades (E13) enters through Source 4 (`host_scripts_journald`), not Source 1, so a Source 1 filter never sees it; the risks it does share are a config that fails to compile or start (web-1 and web-2 first, mitigated by `vector validate`, `vector test` and the `.prev` restore) and a Source 1/2 partition error (Guard 1). A Source 1 filter does see every `inngest-server.service` row (including the rows the 524 alert reads), so it must be fail-open with infallible VRL, and a fixture asserts a non-terminator row passes unchanged.
- **Rollback asymmetry.** Reverting the PR restores web-1 and web-2 (the `.prev` restore plus the revert's own delivery) and the mint cuts a NEW higher image (v1.1.60; never tag an older commit); an Inngest host that has already been replaced keeps this image's `vector.toml` until another replace, and a replace has no rollback. Nothing in the new rules is harmful on a replaced host, so the revert is not urgent there.
- **Other carrier PRs.** Any concurrent PR that touches a baked carrier sees the same Guard A red from this merge until the bump lands; the PR body says so.
- **The wording is unproven until the replace.** The filter's wording match and the row budget can only be confirmed from the first rows of the replaced host; a wording fix or the second drop then needs a NEW image and another host replace (each with downtime and a fresh owner go), and the 24-hour clock restarts at the next boot.
- **Volume.** Budget 400 per day before a flip, 8,000 after (CTO T2); estimated unfiltered volume after a flip is up to 24,000 per day; the 2026-08-14 ingest refusal blinded every host for about 49 hours.
- **`user_data` size.** 256 B headroom against the 300 B precondition; the replace go is blocked on the separate trim and a CI-rendered measurement (CTO T4). A tag or digest swap changes the stored size by at most a few bytes; the CI render, not the offline number, decides.
- **Not measured.** The host's stunnel build and curl version; how the filter's `._SYSTEMD_UNIT` and `.message` field names look on the host's Vector 0.43.1 (the `vector test` fixtures set them by assumption; the first post-replace row is the check, and the journald field names are those the existing rows already carry: `SYSLOG_IDENTIFIER`, `_SYSTEMD_UNIT`, `message`).
- **Window.** From merge until the bump lands, `main`'s Guard A is red and `deploy-script-tests` is advisory. A concurrent unrelated carrier PR sees the same red.
- **Status checks.** #10542 closed; #10543 open; #10544 open (the replace dispatch has no confirm or id-pin input, so the typed go is the only gate); #10545 open (the nft loader is not idempotent: never restart the unit on the host).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6. This one declares `single-user incident`.
- `vector validate --no-environment` does not compile VRL; only `vector test` does. The filter's correctness rests on the new suite, which must be blocking in `validate-vector-config.yml`.
- Source 1 is an OR over fields: the unit arm admits the terminator at any priority, and the `{3,4}` PRIORITY arm admits any other unit's errors. The terminator's `LOG3` lines are expected at PRIORITY 6 (not 3; derived from systemd's default, not measured on the host), so they ship only through the unit arm; do not "fix" the filter with a priority test, and keep PRIORITY 3 and 5 in the derived corpus so either value is covered.
- Never add `systemd` to any `SYSLOG_IDENTIFIER` array in either direction (ADR-286, tests pin its absence).
- Text containing the two words for the infrastructure apply command is written with the Write tool only; this plan names the dispatch by its input value (`inngest-host-replace`) and not by the command line.
- The GDPR gate (`soleur:gdpr-gate`) is advisory for the single-user-incident trigger; run it at deepen time against this plan and record the output under `### Legal and compliance`.
- Describe the replace window as "unavailable" or a "disruption" in every artifact this change touches.

### CPO disposition

CPO sign-off: approved with conditions (2026-10-25), all four adopted: (1) #10543 fixed, or the window quiesced with the replay check, is a hard precondition of the replace go; (2) the typed-go ask is rewritten in plain language with the duration range (up to about 80 minutes), the user-visible effects, the optional benefit and the cost of declining, and leads the PR body (`## PR Body Requirements` item 0); (3) the replace is scheduled in a low-traffic window, ideally combined with the next replace needed anyway (a scheduling suggestion; the date is the owner's call); (4) the PR body states that merging causes no user impact. The CPO also noted the replace "buys no user value" by itself: it is operator diagnosability only, which is why the ask names the cost of declining. The CPO's note that the "15 to 60 minutes" range understates the measured 59 and 76 minute incidents is applied (the ask says up to about 80 minutes). Do not tell customers "each missed tick fires once on resume" externally: it was measured once on 2026-09-17 and is an internal claim.
