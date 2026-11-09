---
title: "feat(infra): standing kernel patch and reboot cadence per host class, plus a non-SSH exposure check for non-web hosts"
type: feat
date: 2026-11-09
slug: host-kernel-patch-cadence-and-nonweb-exposure-check
branch: feat-one-shot-12008-kernel-cadence
issue: 12008
closes: none
priority: p1
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# feat(infra): standing kernel patch and reboot cadence per host class, plus a non-SSH exposure check for non-web hosts

## Enhancement Summary

**Deepened on:** 2026-11-09. **Passes:** repo research, learnings research, functional-overlap check (no registry offers a Terraform-to-exposure parser or a log-marker cadence checker; build in-repo), three CTO ruling rounds (F1 to F5, the reader-reuse follow-up, R1 to R8), a five-seat plan review (DHH, Kieran, code-simplicity, CTO devex, plus the CTO re-rule), and the deepen-plan gates 4.4 to 4.13 run mechanically against this file.

### Key improvements
1. Per-workflow merge-trigger enumeration: the design keeps every new path under `scripts/` and `knowledge-base/`, so the merge cannot start an apply, a registry replace or a release.
2. The review round cut the surface roughly in half: one probe script (no conf file, no exemption ratchet, no extra modes), one exposure suite (no table script), and the probe is filed unarmed until a host reports.
3. A time-boxed per-row acknowledgement was planned for rows overdue by design; the review (CTO, 2026-11-09) deferred it to the change that arms the tracker, because no row can be overdue while the tracker is unarmed (see the Review Amendments section).
4. Verified-in-repo corrections: the right generator form for adding suites is `--incremental --write`; the sweeper gives probes no `HOME`, `CI` or `HEADLESS_MODE`; `kernel_age_hours` is the age of the report row, not of the kernel.

### New considerations discovered
- Three ADR files already share the ordinal 033 in the repo; this plan cites only the Inngest-cron one by title and creates no ADR.
- `ADR-263`'s "a host is replaced, not rebooted" is an owner decision (made 2026-10-07) recorded in the ADR-263 addendum dated 2026-10-08, so the runbook cites that addendum as the reason the web row the replace path refuses has no activation path.

Spec lacks a valid `lane:` (no spec.md exists for this branch): defaulted to `cross-domain` (fail-closed).
This PR is `Ref #12008`, never `Closes`: items 1 and 4 of the issue stay open.

## Review Amendments (2026-11-09, append-only record)

The review's design-validity pass (simplicity and architecture seats) and a CTO ruling on its dissents changed the plan as follows; the sections below were edited to match and each edited line names this section:

1. The real reader prints a sixth role (the default-off dogfood host), so the probe could never print the all-clear. The probe now skips an `IGNORED_ROLES` list, and the suite pins the reader's role table and column header against the probe.
2. Field-shape validation of the fixed columns (a column inserted before the uptime cannot silently shift a number into its place).
3. CTO item A (supersedes R4): per-row acknowledgements are deferred to the change that arms the tracker.
4. CTO item B: the mutation matrix stays, trimmed by the two acknowledgement mutants and made to stop at the first kill.
5. CTO item C (amends R6): any rule block on a non-web firewall is red.
6. CTO item D: the hygiene scan keeps covering the script, both suites and the runbook (AC7 stands).
7. CTO item E (amends R5): the tracker is armed only once a session run of the probe prints a line other than `cannot-establish`, which needs #12385 and #12386.

## Overview

Issue #12008 asks for four things; this plan covers items 2 and 3 only.

- **Item 2.** A standing kernel patch and reboot cadence for each host class (web, inngest, registry, git-data), written as
  durable repo artifacts: a runbook plus one machine-checkable overdue probe built on the #12007 host kernel marker, with
  the cadence numbers as constants at the top of that one script. git-data gets its own runbook section because ADR-115 did
  not adopt the reboot primitive for it.
- **Item 3.** A repeatable, read-only, non-SSH check of the public TCP surface the non-web hosts declare in Terraform,
  recorded as one test suite (synthesized fixtures plus a real-tree design invariant), never as a verdict.
- **Out of scope, stays tracked on #12008:** item 1 (patch and reboot the web hosts when the distro ships a fix) and
  item 4 (the 26.04 evaluation).
- **Nothing production-mutating runs.** Every reboot, replace, apply dispatch and host patching act is listed under
  `## Deferred Production Acts` and waits for the owner's typed go naming the exact command.
- **ADR-322 governs every new artifact:** no kernel strings, no CVE ids, no host names or addresses, no exposure verdicts.
  The only probe output is one fixed line (the sweeper republishes it inside its own heading and `<details>` fold, with the exit code, a timestamp and the script path), and the probe is not armed until a host actually reports (see Phase 5).

### What a merge of this PR can and cannot trigger (checked per workflow, not once)

Every workflow with a `push` trigger on `main` was enumerated by its `on.push.paths` (learning
`2026-11-08-a-merge-that-edits-registry-cloud-init-auto-replaces-the-registry-host-and-the-plan-checked-only-the-apply-workflow.md`).
The paths this plan writes are `knowledge-base/**`, `scripts/**` and `scripts/followthroughs/**`.

| Workflow | Push paths | Touched by this plan? |
|---|---|---|
| `apply-web-platform-infra.yml` (production plan and apply) | `apps/web-platform/infra/**` (minus four rehearsal and staging subtrees), itself, one jq filter | No. Any new file there, even a test or a markdown file, would fire it, so no new file goes there. |
| `registry-host-replace-dispatch.yml` (replaces the registry host, no reviewer gate) | `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`, itself | No. These three files are not edited. This is why the signal is not delivered through the registry cloud-init. |
| `apply-deploy-pipeline-fix.yml`, `apply-sentry-infra.yml`, `apply-github-infra.yml`, `apply-inngest-rls.yml`, `mint-inngest-bootstrap-tag.yml`, `zot-image-mirror.yml` | specific files under `apps/web-platform/infra/**` or `infra/**` | No. |
| `web-platform-release.yml` (web app release) and `version-bump-and-release.yml` (plugin release) | `apps/web-platform/**`, `plugins/soleur/**` | No. No plugin or app file is edited, tests under `plugins/soleur/test/` included. The one candidate edit (a new column in `host-state.sh`) is deferred to its own issue for exactly this reason. |
| `infra-validation.yml` (validates, deploys nothing) | `apps/*/infra/**`, `infra/**`, `apps/web-platform/test/infra/**` | No. |
| `ci.yml`, `secret-scan.yml`, `codeql-main-alert-gate.yml` and similar (no path filter) | all pushes | Yes, as ordinary CI. None of them mutates a host. |

So the merge cannot replace, reboot, patch or apply to any host. The new probe reaches production only as a read (a Better
Stack query) and only after a tracker directive enrols it on the existing daily follow-through sweeper, which this PR does not
do (CTO R5).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (measured on this branch) | Plan response |
|---|---|---|
| "git-data is barred from the reboot primitive by ADR-115, so it needs its own path" | True for the self-reboot primitive: the registry-only grant stands and the 2026-09-18 amendment explicitly does not extend it to git-data. But git-data already HAS a route: `git-data-host-replace` (apply_target), held by three interlocks (rung-2 evidence for the current cloud-init, plaintext volume id, SSH authorization map), volumes and LUKS passphrase preserved by omission. `git-data-host-rotate` is the only route allowed to touch the LUKS store. | git-data's "own path" is documentation of that existing route plus its interlocks and an owner-decision note. No new primitive, no ADR (CTO F3). |
| "Define a cadence ... expressed as durable repo artifacts, e.g. a cadence-overdue signal built on the #12007 marker/heartbeats" | The four `soleur-host-kernel-<role>-prd` heartbeats exist but are born paused, are not in the feeder loop, and any new heartbeat is a Terraform resource under `apps/web-platform/infra/` (auto-apply path). They measure 36 h staleness, not uptime. | Build on the marker rows through the existing reader `host-state.sh`, as a notify-only follow-through probe (CTO F1). No new heartbeat, no Terraform. |
| "A replace is the patch path" (immutable redeploy, `hr-prod-host-config-change-immutable-redeploy`) | Every cloud-init file sets `package_update: true` only. No `package_upgrade`, no unattended-upgrades or needrestart config anywhere in IaC. A replace boots the base image's kernel plus whatever apt state exists, so a patched kernel is NOT guaranteed to arrive. | The runbook never claims a replace patches. Each class section ends with a verification step (a fresh marker row after the act). Whether cloud-init should upgrade packages is deferred to its own issue because editing the registry cloud-init auto-fires a registry replace. |
| "The marker carries reboot_required, so the overdue rule can use it" | The marker emits it, but `host-state.sh` prints only `host_role marker_state kernel_state age_hours kernel uptime_s kernel_age_hours source_marker`. `kernel_age_hours` is the age of the newest report row, not of the kernel (CTO R7). Adding a column edits `plugins/soleur/skills/cve-exposure/**`, which fires the web app release and plugin release on merge. | Uptime alone decides "overdue" in this PR. The `reboot_required` clause and its column are a deferred issue that notes the release trigger. |
| "Check public TCP exposure of the non-web hosts" | The inngest, registry and git-data firewalls are declared with zero inbound rules, and all three servers keep public IPv4 and IPv6 for egress. inngest binds its firewall at creation (`firewall_ids`, ADR-100 addendum #8754). Registry and git-data still bind through a separate `hcloud_firewall_attachment` (open #6442: it attaches after first boot; a stale server id once left inngest unfirewalled, which is #8754 and the ADR-100 addendum 2026-09-25). The dogfood server is count-gated and default-off. | One suite asserts the declared design (no inbound rule on a non-web firewall, every mapped server bound) with a ratchet on attachment-shaped binding. Live state (drift, a stale id) needs a live read and is a deferred session-only step. |
| "Cloudflare ingress config" as evidence | `tunnel.tf` declares outbound-initiated cloudflared ingress rules. They open no inbound public port. | Out of scope; the suite header says so (CTO R6). |
| "ship via the merge queue and run postmerge verification" while "every production-mutating act is an Operator Hold" | `ship` Phase 6 step 5 runs `hold-gate-eval.sh` on a section headed `Operator Holds` and stops on any standing hold (exit 2), including `Operator-authorizes:`. The acts are neither performed nor required by this PR. | A `## Deferred Production Acts` section with `Operator-authorizes:` wording and no hold or gate marker lines (CTO F5). The PR body states this rationale so the ship gate's intent stays visible. |
| "The sweeper posts one comment and stays quiet" | `sweep-followthroughs.sh` comments on every run of an open notify-only tracker (exit 5 is ACTION REQUIRED, exit 2 is NOT YET and exit 3 is CANNOT ESTABLISH; only other exit codes are TRANSIENT), and I did not verify any de-duplication. | The tracker directive is not armed until a host reports (CTO R5); the arming step is a tracked issue with the directive text ready. |

## Research Insights

### Premise Validation (Phase 0.6)

Checked: #12008 is OPEN (labels p1, engineering, security); #12007 is CLOSED and merged as d731cfdebd; #12385 (git-data
marker emitter) and #12386 (roll-out of the emitter and arming of the four heartbeats) are OPEN; #6442 (attachment attaches
after first boot) is OPEN; PR #12497 naming this issue is this branch's own draft. The collision pre-check printed one foreign
`test-all.sh` process owned by an unrelated worktree: no overlap with this work.
Mechanism vs ADR corpus: ADR-115 (the git-data reboot exclusion and the replace-on-rotation blocker), ADR-322 (unknown by
default, session-only), ADR-100 addendum 2026-09-25 (firewall binding), ADR-263 (a host is replaced, not rebooted) were
read. None rejects a probe-plus-runbook design; ADR-322 rejects a durable exposure register, which this plan does not build.
Stale: the brief's commit hash had one extra character (the real one is d731cfdebd). Held: everything else.

### Property List (Phase 0.6b)

1. A written cadence per host class (interval, activation route, authorization, verification) exists and is findable.
2. git-data has an explicit route that never uses the self-reboot primitive and never replaces on rotation.
3. A machine-checkable signal says when a host row is past its cadence, unknown-by-default: absent, stale or unreadable
   evidence is never read as "within cadence", and a known-bad row cannot mask a new one forever.
4. The signal's public output carries no versions, host names, class names, counts or exposure verdicts.
5. The public TCP surface the non-web hosts declare is checkable from the repo without SSH and re-checked in CI, with a
   guard that cannot pass by parsing nothing.
6. Nothing in this change mutates production, and its merge triggers no production apply, replace or reboot.

### Cut List (Phase 0.6b, extended by the plan-review round)

| Mechanism proposed or imagined | Property | What already covers it, or why cut |
|---|---|---|
| New Better Stack heartbeat family for cadence | 3 | Cut. New Terraform under the auto-apply root, owner-only arming, measures staleness not uptime. The follow-through sweeper is already scheduled and holds the Better Stack read credentials. |
| New scheduled workflow for the overdue check | 3 | Cut. the Inngest-for-crons ADR (`inngest-cron-functions-invoke-claude-code-via-child-process-spawn`; the ordinal 033 is shared by three files) prefers Inngest for new crons and the sweeper already runs notify-only probes (precedent `arm-token-revisit-12229.sh`). |
| Second marker reader inside the probe | 3 | Cut. `host-state.sh` already holds the row-identity rules and the upstream-verified reader (ADR-322 decision 5). |
| Extending `host-state.sh` with a `reboot_required` column | 3 | Deferred to its own issue (release trigger on merge). Uptime alone is the conservative overdue rule. |
| Cadence conf file, `EMITTER_STATE` exemptions and their ratchet | 3 | Cut (CTO R3, DHH and simplicity reviewers). A class with no fresh observed marker is already unknown; the four numbers are constants at the top of the one script. |
| `FRESH_HOURS` anchored grep of the reader | 3 | Cut (CTO R1). The reader applies the 48 h bound before it prints `fresh` and `observed`; a second copy of the number is a drift hazard. |
| `--table`, `--self-check`, `--summary` modes and the separate engine and wrapper | 3 | Cut (CTO R2). One script; the per-class view is a runbook procedure over `host-state.sh` output. |
| Standalone exposure table script with a conf mapping and a session table | 5 | Cut (CTO R6). One suite with synthesized fixtures and a real-tree design invariant covers "repeatable check". |
| A durable per-host exposure register or a verdict file | 5 | Cut. ADR-322 option B was rejected. |
| A live Hetzner firewall read in CI | 5 | Deferred. It needs a production credential and is a session-only read. |
| Tunnel ingress parsing | 5 | Cut. Outbound-initiated; opens no inbound port. |
| New ADR for git-data's route | 2 | Cut. The route already exists (CTO F3). A reboot route for git-data would need a new ADR superseding ADR-115's "not adopted" and is an owner decision, noted in the runbook. |
| Enrolling the probe on the sweeper now | 3 | Deferred (CTO R5): until a host reports it can only print `cannot-establish` and post a daily public comment. The arming step is a tracked issue. |
| Per-class aggregate that never clears (rows past cadence by design) | 3 | A time-boxed per-row acknowledgement was the R4 answer; deferred to the arming change by the 2026-11-09 review ruling (see Review Amendments). |

### Institutional learnings applied

- `2026-11-08-a-merge-that-edits-registry-cloud-init-auto-replaces-...`: enumerate every `on.push.paths` workflow before saying a merge is inert (section above).
- `2026-10-06-a-lints-required-ness-belongs-to-its-job-and-auto-apply-on-merge-is-a-per-workflow-paths-fact.md`: "auto-applies on merge" is a per-workflow fact.
- `2026-11-03-base-image-cve-bump-is-a-pin-census-not-a-digest-edit.md` and ADR-322: unknown by default; public writes only through a fixed template.
- `2026-10-31-a-dead-man-alert-must-be-judged-by-what-its-evaluator-can-see-...`: size the evaluator's window from what it can see; here the reader owns the 48 h bound.
- `2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument.md`: a guard must not act on a fact it failed to read; every reader failure maps to `cannot-establish`.
- ADR-100 addendum #8754: the firewall binding shape is a security property; a plan-level check cannot see a deleted `firewall_ids` line, so a test must pin it.
- `followthrough-convention.md` and `sweep-followthroughs.sh`: notify-only probes never exit 0 or 1; exit 5 comments ACTION REQUIRED and leaves the tracker open, exit 2 comments NOT YET and exit 3 comments CANNOT ESTABLISH (only other exit codes are TRANSIENT); stdout is republished near-verbatim as a public comment; the sweeper runs probes under `env -i` with a fixed PATH, the `secrets=` names and one horizon variable (no `HOME`, `CI`, `HEADLESS_MODE`, `TMPDIR`).
- Plan sharp edge (census over the file set, with a case that ADDS an instance the guard has never seen): applied in both guards' matrices.

### CLI and tool-token verification (Phase 6 gate)

Every command string in this plan was read from the repository, not recalled: `apply_target` values and the `confirm`,
`web_host_key`, `reason`, `plan_only` inputs from `.github/workflows/apply-web-platform-infra.yml` (`on.workflow_dispatch.inputs`);
the sweeper directive fields from `followthrough-convention.md`; the exit-code vocabulary (2, 3, 5) from the same file and
`sweep-followthroughs.sh`; the registry re-fire command from `registry-host-replace-dispatch.md`; `--print-selection`,
`--print-affected-set` and the registration-only rule from `scripts/test-all.sh --help`. No external CLI flag is introduced.

### Deepen-plan verification (gates 4.4 to 4.13, run 2026-11-09)

| Gate | Result |
|---|---|
| 4.4 precedent diff | The probe follows `arm-token-revisit-12229.sh` (notify-only, exits 2/3/5, xtrace refusal, `env -i` suite). The suite follows its test's layout. The exposure suite follows `firewall-9000-deny.test.sh` (named design invariant, parser-liveness floor). No pattern is novel. Scheduled-work check: no new scheduled job is created; the probe enrols on the existing sweeper, so the prefer-Inngest hook (new workflow files only) does not apply. |
| 4.5 network | Answered in `## Hypotheses` (not a connectivity diagnosis; live firewall state explicitly unverified). Telemetry emitted. |
| 4.55 downtime | Not triggered: no host, volume, migration or router operation. |
| 4.6 user-brand | Section present, threshold `aggregate pattern`, both vectors concrete. |
| 4.7 observability | All five fields present and non-placeholder; the command starts with an allowlisted verb (`grep`), needs no SSH, finishes well inside 15 s, and `expected_output` is the literal `4`. Block is new in this plan, so the two #8412 conditions bind and pass. |
| 4.8 PAT | No PAT-shaped variable or token literal. |
| 4.9 UI | No UI-surface file. |
| 4.10 encryption | Not triggered (no `.tf`, migration, cloud-init or compose file is created or edited; no store or connection). |
| 4.11 guard contract | `lint-guard-contract.py` green on both guards; assemblies name chokepoints (the row classifier, the aggregate, the directory census), not member lists; matrices are derivable from the design and include own-dispatch, second-member, added-instance and reorder rows. |
| 4.12 scope check | Exactly one unfenced section, three subsections, no `unmapped` status cell, no `descoped` or `inferred` row without a justification, a `Recommendation:` line, no `BLOCKED` marker. |
| 4.13 task design | Not triggered (no new workflow, Inngest function, cron, timer or daemon). |
| Live citations | #12007 closed, #12008/#12385/#12386/#6442 open, PR #12497 is this branch's own draft; commit `d731cfdebd` resolves and is an ancestor of `origin/main`; rule ids `hr-menu-option-ack-not-prod-write-auth`, `hr-dispatch-async-must-arm-watch`, `hr-prod-host-config-change-immutable-redeploy` and `wg-when-deferring-a-capability-create-a` exist in `AGENTS.rules.md`; labels `follow-through`, `domain/engineering`, `type/security`, `type/chore` and `priority/p2-medium` exist; `cutover-inngest.yml` has an `op` input with a `resume` option; the generator, orphan lint and c4 parity test exist. |
| Literal consistency | The three public lines appear identically (two occurrences each) across the plan; the exit codes 5, 2, 3 map the same way in the runbook, guard and ACs. |

## Open Code-Review Overlap

Query run against 200 open `code-review` issues for each planned path.

- `scripts/test-all.sh`: #7942 (two mutation batteries run in no gate). Acknowledge: a different concern; this plan only adds registrations for its own suites.
- `scripts/followthroughs/**`: #11312, #10464, #10463, #10462, #8435. Acknowledge: each concerns a different, named probe; this plan adds a new probe and edits none of them.
- Every other planned path (the shard manifests, `host-state.sh`, `firewall.tf`, the sweeper workflow, `followthrough-convention.md`): none.

## Hypotheses

The description matches the network-outage trigger words (`firewall`, `SSH`). This is not a connectivity diagnosis, so the
four-layer checklist is answered for what it is, in L3 to L7 order, with nothing service-layer proposed:

- **L3 firewall allow-list:** declared state is checked from Terraform by the deliverable (item 3). Live state (`hcloud firewall describe` against the real firewalls) is NOT verified in this plan: it is a deferred session-only read.
- **L3 DNS and routing:** not verified; not relevant (no hostname is resolved).
- **L7 TLS or proxy:** not applicable; no HTTPS path is diagnosed.
- **L7 application:** not applicable; no host log is read.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "a standing cadence per host class" [issue #12008 item 2, brief] | Phase 1 (probe with cadence constants), Phase 3 (runbook) | mapped |
| 2 | "git-data on its own path per ADR-115" [brief] | Phase 3 runbook section "git-data" | mapped |
| 3 | "public TCP exposure check of the non-web hosts without SSH" [brief] | Phase 2 (exposure suite) | mapped |
| 4 | "any production-mutating step (reboot, -replace, apply dispatch, host patching) is NOT run; stop and ask the owner for an explicit per-command go-ahead first" [brief] | `## Deferred Production Acts`, merge-trigger table, AC2 | mapped |
| 5 | "No SSH." [brief] | every command path in the plan (reads via Better Stack query and Terraform text only) | mapped |
| 6 | "Do not put kernel versions, host names or exposure verdicts in durable or public artifacts (ADR-322)" [brief] | fixed-vocabulary output, AC7 forbidden-token scan | mapped |
| 7 | "prefer designs that do not touch cloud-init-registry.yml or any file that auto-fires a host replace/apply on merge, and state this explicitly in the plan" [brief] | merge-trigger table, Files lists | mapped |
| 8 | "Commit with LEFTHOOK_EXCLUDE=bun-test and git commit -F <file>; never git stash; CI is the merge gate; ship via the merge queue and run postmerge verification before reporting done." [brief] | Phase 5, Post-merge acceptance criteria | mapped |
| 9 | "Persist every decision as a row of the `| Item | Class | Ruling |` table" [brief] | `decision-challenges.md` (Files to Create) | mapped |
| 10 | "Item 1 (patch and reboot web hosts when Ubuntu ships the noble fix) and item 4 (26.04 evaluation) stay tracked and out of scope." [brief] | none | descoped — justification: the brief itself excludes them; they stay open on #12008 |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Runbook `host-kernel-patch-cadence.md` | "expressed as durable repo artifacts (runbook + whatever machine-checkable gate/alert fits the existing patterns" | asked |
| `scripts/followthroughs/host-kernel-cadence-12008.sh` (cadence constants, overdue rule, fixed public line) | "a cadence-overdue signal built on the #12007 marker/heartbeats" | asked |
| `ACK_UNTIL_<row>` acknowledgement constants inside that script (REMOVED from this PR by the 2026-11-09 review ruling; deferred to the arming change) | asks 1 | inferred — justification: two rows are past cadence by design (the one web host with no rebuild path, git-data behind its interlocks); without a time-boxed acknowledgement they hold the aggregate at `review-needed` forever and mask every new overdue row (CTO R4) |
| `scripts/followthroughs/host-kernel-cadence-12008.test.sh` | "recorded as a repeatable check/test" (item 3 wording, applied to item 2 because the probe is a guard) | inferred — justification: a guard with no suite is the vacuous-guard class (Guard Contract) |
| `scripts/host-tcp-exposure.test.sh` | "recorded as a repeatable check/test, not as a verdict in a durable or public artifact" | asked |
| Attachment-binding ratchet inside the exposure suite | "check public TCP exposure of the non-web hosts using only non-SSH, read-only, repo-and-IaC-derivable evidence" | inferred — justification: binding shape is the part of "exposure" a rule count cannot show (ADR-100 addendum #8754, open #6442), so a rule-count-only check would read clean over an unbound host |
| Suite registrations in `scripts/test-all.sh` and the regenerated shard manifests | "CI is the merge gate" | inferred — justification: this runner enumerates suites by hand; an unregistered `.test.sh` is an orphan that gates nothing (`lint-orphan-test-suites.sh`) |
| `## Deferred Production Acts` | "The plan must list every production-mutating act as an Operator Hold" | asked |
| Follow-up and arming issues | "Item 1 ... and item 4 ... stay tracked" and the deferral-tracking rule | inferred — justification: a deferral without an issue is invisible (plan skill deferral check) |

### Split Assessment

- Subsystems touched: 2 — `scripts`, `knowledge-base`
- Planned files: 8 (4 created under `scripts/` and `knowledge-base/engineering/`, 2 spec files, 2 edited registries) | Estimated changed lines: ~650
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The natural seam, if the owner wants two PRs, is item 2 (probe and runbook) versus item 3 (exposure suite); they share no code. Fixtures are synthesized inside the suites, not committed as files.

## User-Brand Impact

- **If this lands broken, the user experiences:** a false all-clear on host patching. Once armed, the tracker prints `nothing-to-report` while a host has run past its cadence, so hosts holding every user's workspaces stay on an unpatched kernel unnoticed. Mitigation: unknown is the default and every reader failure prints `cannot-establish`. Residual: `nothing-to-report` is unsound for a patched-kernel claim, because `uptime_s` is a lower bound on kernel age and resets on a reboot onto the same unpatched kernel or a replace onto an unpatched base image; the runbook states that it means only "uptime within cadence". Acknowledgements were deferred (CTO ruling A) to the arming change tracked in #12504, so the signal has no bypass today.
- **If this leaks, the user's workflow is exposed via:** a public tracker comment, a runbook, a script constant or a test message that names a kernel string, a host, a class that is overdue or a CVE next to a status. This repository is public, so that is a targeting list. Mitigation: the only public output is one of three fixed lines; failure messages name only resource addresses already public in the repo; a forbidden-token scan covers every new durable file.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** matches #12007, which shipped the marker this builds on. The change reads and documents; it mutates nothing and its worst failure is a missed notification on a signal that is `unknown` today anyway. A single-user-incident tier would add a CPO sign-off for a read-only probe; the owner can raise it.

## Architecture Decision (ADR/C4)

### ADR

None written or amended (CTO F3, 2026-11-09): this plan decides nothing architectural. It documents the existing `git-data-host-replace` route, adds a read-only probe on an existing substrate (the follow-through sweeper) and a Terraform text check. A future reboot route for git-data would be a new ADR superseding ADR-115's "not adopted" for that host; the runbook names that as an owner decision.

### C4 views

No C4 impact. All three files (`model.c4`, `views.c4`, `spec.c4`) were read. Checked and already modeled:
(a) external human actors: the founder, with `founder -> betterstack` already describing the `host-state.sh` read (session-only); no new actor.
(b) external systems: Better Stack (`github -> betterstack` already names the follow-through soak probes reading Logs through `betterstack-query.sh`), GitHub (the sweeper), Hetzner (`github -> hetzner` control-plane edge); no vendor is added.
(c) containers and stores: inngest, the zot registry and git-data hosts exist; no container or store is added; the probe is a script on the existing sweeper and the exposure suite reads repo text.
(d) actor-to-surface access relationships: unchanged; no new access path.
`plugins/soleur/test/c4-count-parity.test.sh` was run at plan time: 13 passed, 0 failed. It is re-run in AC8 because the change adds no workflow, monitor or heartbeat and must leave every derived cardinality unchanged.

### Sequencing

Not applicable: nothing here becomes true only after a later slice.

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file is created or edited. The exposure suite only reads them. Required providers, sensitive variables: not applicable.

### Apply path

None. No host resource is created or changed; there is no apply, replace or cloud-init delivery in this PR. The class-by-class routes the runbook documents already exist and stay owner-authorized (see `## Deferred Production Acts`).

### Host fan-out

Not applicable: no `terraform_data` provisioner is added or changed (`plan-host-fanout.md` applies only to those).

### Distinctness / drift safeguards

The exposure suite asserts a binding ratchet (the set of attachment-shaped bindings equals an allow-list that only shrinks) and a parser-liveness control (the web firewall must parse with inbound rules, so a parser that reads nothing cannot pass). Both are in Guard 2.

### Vendor-tier reality check

Not applicable: no vendor resource is created. The probe uses the Better Stack Logs read connection that already exists (`BETTERSTACK_QUERY_*` in the sweeper environment).

## Encryption Posture

Skipped by the gate's own rule: the plan introduces no persistent store and no new cross-component connection. The probe reuses the existing HTTPS read path to Better Stack and the existing sweeper-to-GitHub path; the exposure suite reads local files.

## Observability

```yaml
liveness_signal:
  what: once armed, the daily follow-through sweeper runs the probe and posts its one fixed line on the tracker issue; a missing run is visible as a gap in the tracker's comment dates. Until armed, the wiring is proven by the probe's own suite with a stubbed reader
  cadence: daily once armed (the existing scheduled sweeper)
  alert_target: tracker issue comment plus the sweeper heading (review-needed maps to ACTION REQUIRED, nothing-to-report maps to NOT YET and cannot-establish to CANNOT ESTABLISH; the sweeper wraps the probe's line in that heading, the exit code, a timestamp, the script path and a `<details>` fold)
  configured_in: the directive in the tracker issue body (filed unarmed in this PR, armed by the deferred arming step) and scripts/followthroughs/host-kernel-cadence-12008.sh
error_reporting:
  destination: the sweeper's per-probe heading and last-4KB comment (workflow-run log, observability layer 6)
  fail_loud: yes — any reader failure, unparseable output or missing role row exits 3 (CANNOT ESTABLISH); the probe never exits 0 or 1 and never prints the all-clear line on a failure
failure_modes:
  - mode: Better Stack credentials not injected into the sweeper (reader exit 3)
    detection: probe prints cannot-establish, sweeper heading CANNOT ESTABLISH
    alert_route: sweeper heading, layer 6 (workflow-run log)
  - mode: reader integrity failure (host-state.sh exit 4, reader differs from upstream main)
    detection: probe prints cannot-establish
    alert_route: layer 6
  - mode: host emitter not delivered or silent (today's state for every host)
    detection: every row unknown, probe prints cannot-establish; the runbook procedure names which row in a session
    alert_route: layer 6 for the aggregate; host-state.sh in a session for the row
  - mode: a row is past its cadence
    detection: probe prints review-needed, exit 5, sweeper heading ACTION REQUIRED
    alert_route: layer 6, tracker comment
  - mode: a non-web firewall gains any rule block, a server loses its binding, a new server appears unmapped, or the parser reads nothing
    detection: scripts/host-tcp-exposure.test.sh fails in CI
    alert_route: CI red on the PR (layer 6)
logs:
  where: GitHub Actions run logs for the sweeper and for CI; the per-row view is a session procedure and is never logged or written
  retention: the repository's Actions log retention
discoverability_test:
  command: grep -c '^readonly CADENCE_DAYS_' scripts/followthroughs/host-kernel-cadence-12008.sh
  expected_output: 4
```

Task Design gate: not triggered. No new workflow, Inngest function, cron, host timer or daemon is created; the probe enrols on the existing sweeper only through a tracker directive that is filed unarmed.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Three CTO rounds on 2026-11-09 (forks F1 to F5, the reader-reuse follow-up, and R1 to R8 after the review panel). Outcomes: a notify-only probe in ONE script with a three-line public vocabulary, uptime-only overdue rule, worst-case aggregation and, after the review ruling, no acknowledgements (deferred to the arming change); not armed until a host reports; git-data documented on its existing replace route with no ADR; one exposure suite with a binding ratchet and a parser-liveness control; production acts recorded outside the hold section so the PR's own merge is not wedged. The plan-review panel (DHH, Kieran, code-simplicity, CTO devex) cut roughly half the originally planned surface. No product, marketing, legal, finance, sales or support surface is touched. No UI file is created, so the Product/UX gate does not run.

## Deferred Production Acts

None of these is run, dispatched or prepared by this PR. Each needs the owner's typed go naming the exact command; a menu click, a bare "go" or an earlier approval is not a go (`hr-menu-option-ack-not-prod-write-auth`). After the go, the agent runs only that command and arms a Monitor in the same turn (`hr-dispatch-async-must-arm-watch`). This section deliberately contains no hold or gate marker lines (CTO F5): the acts are not required by this PR, and a real hold section would stop `ship` at the draft exit for acts this PR never performs. The PR body states that rationale. A lint-style check in Phase 4 pins that no line in this section or in the runbook begins with a hold or gate marker, inline mentions included.

<!-- lint-infra-ignore start: lists production acts this plan does NOT perform; each waits on a typed go naming the exact command -->

- Operator-authorizes: web class replace, `gh workflow run apply-web-platform-infra.yml -f apply_target=web-host-replace -f web_host_key=<key> -f confirm=REPLACE-<key> -f reason='<why>'`. Precondition: a fresh marker row shows the row past its cadence in a session run of the reader; the workflow refuses the one web key it has no supported rebirth route for (until #9421; that row has no activation path, see the runbook). Reviewer-gated by the workflow's own environment.
- Operator-authorizes: inngest class replace, `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason='<why>'`, then the separately human-approved `gh workflow run cutover-inngest.yml -f op=resume`. Precondition: the scheduler pause window is acceptable to the owner (the sole scheduler goes dark during the replace).
- Operator-authorizes: registry class replace, `gh workflow run apply-web-platform-infra.yml -f apply_target=registry-host-replace -f reason='<why>'` (or the dispatcher re-fire `gh workflow run registry-host-replace-dispatch.yml -f reason='<why>'`). Precondition: the registry preflight is green; the registry is the sole image pull path and a replace destroys before it creates.
- Operator-authorizes: git-data class replace, `gh workflow run apply-web-platform-infra.yml -f apply_target=git-data-host-replace -f reason='<why>'` (rehearsal first with `-f plan_only=true`). Precondition: the three interlocks clear (rung-2 evidence for the current cloud-init, plaintext volume id empty, SSH authorization map). Whether git-data should ever have a reboot route is a founder decision because it supersedes an ADR; it is not an act and is not authorized here.
- Operator-authorizes: delivering the host kernel emitter to running hosts and arming the four dead-man heartbeats, which is the existing owner-only roll-out tracked on #12386. This plan neither performs nor changes it.
- Operator-authorizes: arming the cadence probe on the sweeper (the tracker directive), once a session run of the probe prints `review-needed` or `nothing-to-report` (never `cannot-establish`), which needs #12385 and #12386. The tracker for this step is filed unarmed in Phase 5.
- Operator-authorizes: any host patching act that is not one of the dispatches above. None exists in this plan, and an in-place edit on a running host is forbidden by `hr-prod-host-config-change-immutable-redeploy`.

<!-- lint-infra-ignore end -->

Class R reads this work may run itself because they are read-only: the reader once under the injected Better Stack read credentials, and the exposure suite over the Terraform text. Neither mutates anything.

## Implementation Phases

### Phase 0 — Failing tests first (RED)

Write the two suites before the code. All fixtures are synthesized inside the suites (temporary directories, here-strings built with a function, no committed host data, no real names, no real kernel strings). Never spell a heredoc opener as a literal inside a test's own pattern (`guard-vacuity-floor.test.sh` reads it as a heredoc; learning 2026-11-08). Model the layout on `scripts/followthroughs/arm-token-revisit-12229.test.sh` (case-count and assertion-count floors, `env -i` invocation).

- `scripts/followthroughs/host-kernel-cadence-12008.test.sh` — decision table, aggregation precedence, ignored role, field-shape, reader-contract, stdout byte pin, fail-closed reader cases, stderr-leak case, hygiene scan of the script.
- `scripts/host-tcp-exposure.test.sh` — synthesized `.tf` fixtures plus the real-tree design invariant.

### Phase 1 — The probe (one script)

`scripts/followthroughs/host-kernel-cadence-12008.sh` (notify-only; header states credential posture, the proxy caveat and a `RETIREMENT:` list):

1. Constants at the top, all `readonly`: `CADENCE_DAYS_WEB=30`, `CADENCE_DAYS_INNGEST=30`, `CADENCE_DAYS_REGISTRY=30`, `CADENCE_DAYS_GIT_DATA=45` (CTO defaults; the owner edits one file). (Per-row `ACK_UNTIL_<row>` constants were planned here and are deferred to the arming change by the review ruling.)
2. Refuse xtrace (exit 78, the #7797 stub header). Accept no arguments. `cd` to the repository root before calling the reader (the reader resolves its tree from the working directory). The reader is `plugins/soleur/skills/cve-exposure/scripts/host-state.sh`, unmodified; its path may be overridden by `HKC_READER` only when `HKC_TEST=1` (the `HKM_TEST` precedent), so a sweeper run cannot be redirected.
3. Parse the reader's per-row lines and ignore its trailing `SOLEUR_CVE_HOST_STATE ...` summary line explicitly. Map the two web rows to the web cadence, inngest, registry and git-data to theirs.
4. Row rule (CTO F2 + R1): `overdue` iff `marker_state=fresh`, `kernel_state=observed` and numeric `uptime_s > cadence_days*86400`; `within-cadence` iff the same evidence and `uptime_s` at or below it; anything else (stale, silent, unknown, non-numeric `uptime_s`, role row missing) is `unknown`. `uptime_s` is time since last boot, a LOWER bound on how long the running kernel has run, so only `overdue` is sound: `within-cadence` means the uptime is inside the cadence, not that the kernel carries the fix (a reboot onto the same unpatched kernel, or a replace onto an unpatched base image, resets it; the value can also come from a row up to 48 h older than the state row), and the header and runbook say so.
5. Acknowledgement: DEFERRED to the change that arms the tracker (CTO review ruling, 2026-11-09; supersedes R4). The probe has no acknowledgement constants and no `acked` class.
6. Aggregate and public line (precedence overdue > unknown > within-cadence): any overdue row prints `host-kernel-cadence: review-needed` (exit 5); else any unknown row, or any reader problem (non-zero reader exit including 4, unparseable output, a role row missing) prints `host-kernel-cadence: cannot-establish` (exit 3); else `host-kernel-cadence: nothing-to-report` (exit 2). Stdout is exactly that one line (the sweeper wraps it in a heading and fold in the public comment): stderr of the reader is discarded, no digits, no class names, no counts, never exit 0 or 1.

### Phase 2 — Exposure suite

`scripts/host-tcp-exposure.test.sh` (CTO R6). Plain grep and awk by resource boundary (a resource header at column 0 to the next column-0 closing brace) over every `.tf` file in the Terraform directory; it relies on `terraform fmt` layout, and assertion 1 guards that assumption. Header comments: this asserts a declared design, not live state; tunnel ingress is outbound-initiated and out of scope; live state needs a live read (deferred). Assertions, each with a fixture case in the same file:

1. Parser liveness: the web firewall parses with more than zero rule blocks, else red.
2. Any `dynamic` rule block or `for_each` on a firewall resource, other than the web firewall's documented admin-IP block, is red, never silent.
3. A non-web firewall with any `rule` or `dynamic "rule"` block is red (CTO review ruling, 2026-11-09, amends R6: the check is "no rule block at all"; a future egress rule is then a deliberate edit to the suite). Wording is a declared-design invariant; no exposure-verdict words.
4. Every mapped server has a binding other than none, and the set of attachment-shaped bindings equals an allow-list (registry, git-data) that only shrinks, issue-keyed to #6442.
5. Any `hcloud_server` outside the mapping is red (the default-off dogfood server is mapped as excluded with its reason in a comment).
6. A directory with servers but zero firewall resources is red; a directory with zero servers is red.
7. Failure messages name the resource address only (already public in the repo): no counts, ports or addresses.
8. The real-tree invariant (named and commented as a design invariant, precedent `firewall-9000-deny.test.sh`) runs assertions 1 to 6 against `apps/web-platform/infra`.

### Phase 3 — Runbook

`knowledge-base/engineering/operations/runbooks/host-kernel-patch-cadence.md` (frontmatter `title`, `category: runbook`, `tags`).

<!-- lint-infra-ignore start: describes what the runbook will say about owner-authorized routes; this plan performs none of them -->

One table (class, route, interlock, who authorizes, verification) linking each workflow's own runbook rather than restating its commands, then one paragraph per class that needs more than a row. Cadence numbers are named by pointing at the script header, never copied. Sections:

- **web:** the replace route; the web row the replace path refuses has an explicit "no activation path" row citing the ADR-263 addendum 2026-10-08 ("a host is replaced, not rebooted"), the workflow's refusal and #9421 (no supported rebirth route until then); worded class-neutrally (ADR-322).
- **inngest:** replace plus the human-approved cutover resume; scheduler pause window.
- **registry:** replace; a merge to three render inputs wakes the delivery gate, which replaces the host when the rendered `user_data` changes, with no reviewer gate; this runbook states that no cadence act edits those files.
- **git-data:** its own path. The only sanctioned route is `git-data-host-replace` under its three interlocks, volumes and LUKS passphrase preserved by omission; `git-data-host-rotate` only with a founder rotation decision; no self-reboot primitive (ADR-115 not adopted for this host); until the interlocks clear the row is escalated to the owner and agents take no action; no acknowledgement exists in this PR (deferred to the arming change, #12504). A reboot route would be a new ADR.
- **Per-class view (session procedure):** run the reader in a session under the injected read credentials, then compare each row's `uptime_s` divided by 86400 against the constants in the script header. No new mode exists for this.
- **Reading the tracker line:** the three-line vocabulary, why no class or count is published, the proxy caveat, and that a replace does not by itself guarantee a patched kernel (cloud-init sets `package_update` only), with the deferred issue linked. Verification after any act: a later reader run shows a reset `uptime_s` and a changed kernel; absence or no change means not patched, escalate.
- **Exposure suite:** what it asserts, what it cannot see (live state, a stale attachment id), the allow-list that only shrinks, and that a new server needs a mapping line (the first unrelated infra PR that adds a server will see this suite fail closed, by design).

<!-- lint-infra-ignore end -->

No kernel strings, no CVE ids, no host names or addresses anywhere; `plan_only` rehearsal named as the first step of each replace.

### Phase 4 — Registration and hygiene sweeps

- Register the two suites with `run_suite` lines in `scripts/test-all.sh` (label equal to the manifest key, form `scripts/<name>`), then regenerate the shard manifests with `python3 scripts/regenerate-shard-manifest.py --incremental --write` (the add/remove path: it fetches no timings, pins incumbent rows verbatim, places only the new labels and merges their durations rows as `floor`; never hand-edit `scripts/suite-shard-legs.tsv` or `scripts/suite-durations.tsv`; `suite-durations.tsv` carries a growth stamp). A registration-only diff also needs, for each suite it registers, its own `AFFECTED_*_PATHS` block and `ALWAYS_ON_SUITES` entry (`bash scripts/test-all.sh --help`, "RUNNER EDITS"). The probe suite is path-selected on its own script and on `host-state.sh`. The exposure suite needs an affected-set edge from `apps/web-platform/infra/*.tf`: verify with `bash scripts/test-all.sh --print-selection --paths=apps/web-platform/infra/firewall.tf` that it is selected; if the registry has no declarative path edge, register it as a declared always-on ratchet.
- Run `bash scripts/lint-orphan-test-suites.sh`.
- Forbidden-token scan (a section of the probe suite, over the durable new files only: the script, both suites, the runbook): no CVE-id pattern, no kernel-version pattern, no IPv4 address, no Terraform host name (the scan reads the `name = "..."` string values of the server resources from the Terraform directory at run time and greps for each), no verdict phrase (the probe suite builds the list) next to a CVE id. A second check asserts that no line of the runbook and no line of this plan's Deferred Production Acts section begins with a hold or gate marker, inline occurrences of the literal marker words at line start included.
- Run `plugins/soleur/test/c4-count-parity.test.sh` (must stay 13/0), `python3 scripts/lint-infra-no-human-steps.py` on the runbook, `python3 scripts/lint-guard-contract.py` on this plan, and the shellcheck and format hooks the repo runs.

### Phase 5 — Follow-ups and PR

File these before PR-ready, each with what/why/re-evaluation criteria and a roadmap milestone, and `Refs #12008` in the PR body (`wg-when-deferring-a-capability-create-a`):

1. (Filed as #12502.) Add the `reboot_required` column to `host-state.sh` and the matching overdue clause; note the web app release and plugin release this triggers on merge; bundle a pointer from `cve-exposure/references/component-map.md` to the exposure suite.
2. (Filed as #12503.) Decide whether cloud-init should upgrade packages so a replace brings in a patched kernel; note that merging an edit to the registry cloud-init wakes the delivery gate, which replaces the host with no reviewer gate when the rendered `user_data` changes, so delivery needs an owner-authorized plan.
3. (Done: comment posted.) Comment on #6442 (move registry and git-data binding to `firewall_ids`, and a live firewall corroboration as a session-only read); do not file a new issue.
4. (Filed as #12504; its body also carries the deferred acknowledgement scope, and the arming order and preconditions now live in the runbook.) The arming tracker (CTO R5): one issue labelled `follow-through`, filed UNARMED. Its body states the precondition ("a session run of the reader shows at least one row with `marker_state=fresh` and `kernel_state=observed`; blocked on #12386, and on #12385 for git-data"), carries the directive text ready to paste inside a code fence (a fenced directive enrols nothing), the fixed three-line vocabulary and `Ref #12008`. It is the visible owner of the arming step; closing condition is the arming plus the first line observed.
5. (Done: comments posted.) Existing issues #12385 and #12386: comment the new dependency, do not re-file.

Commit with `LEFTHOOK_EXCLUDE=bun-test git commit -F <file>`; never stash; open the PR as a draft first, mark ready after CI, ship through the merge queue.

### Post-merge (read-only, agent-run)

1. Class R read: run the merged probe once under the injected Better Stack read credentials and record which of the three fixed lines it printed, in the session only. The one-off session run records whichever line prints (exit 5, 2 or 3 respectively); the expectation today is `cannot-establish`. Only `review-needed` or `nothing-to-report` satisfies the arming precondition.
2. Confirm the merge started no apply, replace or release workflow: `gh run list --commit <merge sha> --json workflowName,event` shows only ordinary CI workflows.
3. Run `soleur:postmerge` for the merged PR.

## Guard Contract

### Guard 1 — cadence decision and public vocabulary (the probe)

**Property.** No input in which any host row is past its cadence prints the all-clear line, no unknown, stale, absent, unreadable or wrongly-shaped evidence is ever read as within-cadence, a role outside the required and ignored lists is a problem, and stdout is always exactly one of three fixed lines.

**Assembly.** Every input and output path of the decision: the rows of the reader for BOTH web rows plus inngest, registry and git-data; the cadence constants; the reader's exit code (0, 2, 3, 4, 64, 78); the trailing summary line; the single decision chokepoint `classify_row` for rows and `aggregate` for the line; and the exit-code mapping. The chokepoints are those two functions; the line printer must not recompute either. Rows are enumerated from the reader's output (a census), not from a name list, so a row the script has never seen is `unknown`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | One web row overdue and the other unknown, in both row orders | RED (second member after a compliant first; precedence overdue > unknown) |
| 2 | Swap the precedence so unknown beats overdue | RED (the two-order case disagrees) |
| 3 | Reader exits 4, or prints no rows, or prints only the summary line | RED (own dispatch: "0 rows checked" must be cannot-establish, not all-clear) |
| 4 | Reader output gains a role row the script has never seen | RED (ADDS an instance: it must be unknown, not ignored) |
| 5 | `uptime_s` exactly at the threshold, then threshold plus one second | RED (boundary: within, then overdue) |
| 6 | Make the script print a class name, a digit, or one extra stdout byte | RED (public-vocabulary byte pin) |
| 7 | Make the reader write a distinctive token to stderr | RED (stdout must stay clean; no stderr passthrough) |
| 8 | Map an unknown aggregate token to the all-clear line | RED (the printer must not recompute) |

**Harness rows.** (a) Delete one case from the suite's case table: the case-count floor must fail. (b) Must-PASS non-canonical input: a within-cadence synthesized reader output whose rows are reordered, carry extra trailing tab fields and list the other web row first must still resolve to the same aggregate; and the whole suite is run under `env -i PATH=...` to match the sweeper's environment.

**Anchor.** The cadence numbers are stored values compared to the script's behavior, and one diff can edit both the value and the rule, so the suite proves consistency, not integrity. Outside the commit: the numbers are reviewed in the diff. This residual is accepted.

### Guard 2 — exposure suite and real-tree design invariant (host-tcp-exposure.test.sh)

**Property.** A non-web firewall is accepted only when the parser positively read it with no rule block and every mapped server is bound; anything unparsed, dynamic, unbound or unmapped is red, and the real tree cannot gain a non-web rule block, an unbound server or an unmapped server with the suite green.

**Assembly.** Every server resource, every firewall resource, every attachment resource and every inline `firewall_ids`, across ALL `.tf` files in the directory (not only the mapped ones); the server mapping inside the suite; the web firewall as the control. Members drift (a new server appears), so the assembly is the directory census, not the current server list.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a rule block (inbound or outbound) to a non-web firewall fixture | RED (declared-design invariant) |
| 2 | Add a second non-web server (with a rule) after a compliant first | RED (second member) |
| 3 | Point the parser at a directory with no servers | RED (own dispatch: zero servers parsed must fail, not print clean) |
| 4 | A directory with servers but zero firewall resources | RED (a clean-looking result over nothing) |
| 5 | Remove the control (web) firewall's rules in a fixture | RED (parser-liveness) |
| 6 | Add an `hcloud_server` that is not in the mapping | RED (ADDS an instance the guard has never seen) |
| 7 | Remove the binding of a mapped server | RED (binding none) |
| 8 | Add an attachment-bound server not in the allow-list; or drop an allow-list entry while its attachment remains | RED (ratchet both ways) |
| 9 | Replace a rule with a `dynamic` block on a non-web firewall | RED (never silent) |
| 10 | Make the parser count a rule that appears only inside a comment or a `removed` block | RED (those constructs must be ignored, so a fixture with a rule only there stays clean) |

**Harness rows.** (a) Delete the unmapped-server case from the suite: the case-count floor must fail. (b) Must-PASS non-canonical input: a fixture with inline binding where resource labels, attribute order and comments differ from the real files must pass.

**Anchor.** The mapping and the allow-list live in the suite beside the Terraform they describe, so one diff can move both; the suite proves consistency. Outside the commit: the allow-list is keyed to #6442, and a live Hetzner read (deferred, session-only) is the independent check that declared state matches reality. The suite header says so and never claims live state.

## Acceptance Criteria

### Pre-merge (PR)

1. `bash scripts/followthroughs/host-kernel-cadence-12008.test.sh` and `bash scripts/host-tcp-exposure.test.sh` exit 0, each with a non-zero case-count floor; both are registered in `scripts/test-all.sh` with the label equal to the shard-manifest key, the manifests were regenerated by the generator, and `bash scripts/lint-orphan-test-suites.sh` exits 0.
2. After `git fetch origin main`, `git diff --name-only origin/main...HEAD | grep -E '^(apps/|plugins/|infra/|\.github/)'` prints nothing, and none of `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf` appears in the diff.
3. The probe prints exactly one of `host-kernel-cadence: review-needed`, `host-kernel-cadence: nothing-to-report`, `host-kernel-cadence: cannot-establish`, never exits 0 or 1, accepts no arguments, and a test fails on any extra stdout byte, digit, class name or reader stderr token; the suite also runs under `env -i PATH=...`.
4. (Amended by the 2026-11-09 review ruling.) Acknowledgements are deferred to the arming change: the probe carries no `ACK_UNTIL_*` constants. In their place the probe skips the reader's default-off dogfood role, rejects rows whose fixed columns lack the reader's shape, and the suite pins the reader's role table and column header against the probe.
5. `bash scripts/test-all.sh --print-selection --paths=apps/web-platform/infra/firewall.tf` selects the exposure suite, and the exposure suite's real-tree invariant passes and is named as a design invariant, not an exposure verdict.
6. `grep -c '^readonly CADENCE_DAYS_' scripts/followthroughs/host-kernel-cadence-12008.sh` prints `4`.
7. The forbidden-token scan over the durable new files (the script, both suites, the runbook) finds no CVE-id pattern, no kernel-version pattern, no Terraform server `name` value and no IPv4 address; it reads the server names from the Terraform directory at run time.
8. `bash plugins/soleur/test/c4-count-parity.test.sh` reports 13 passed, 0 failed.
9. `python3 scripts/lint-guard-contract.py` accepts this plan; `python3 scripts/lint-infra-no-human-steps.py` accepts the runbook.
10. `bash plugins/soleur/skills/ship/scripts/hold-gate-eval.sh --plan <this plan>` exits 0 (no hold or gate marker line exists, so the PR's own merge is not wedged).
11. Follow-up issues 1, 2 and 4 of Phase 5 exist before PR-ready; the PR body says `Ref #12008`, lists the Deferred Production Acts in plain words, states that nothing production-mutating ran, and explains why the acts are not under a hold section.
12. `decision-challenges.md` passes `plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh`.

### Post-merge (agent-run, read-only)

13. The merged probe, run once under the injected read credentials, prints exactly one of the three fixed lines with its matching exit code (5, 2 or 3). Any other output is reported to the owner in the session only, never copied into a public artifact.
14. `gh run list --commit <merge sha>` shows none of the apply, replace or release workflows; `soleur:postmerge` reports the merge healthy.

## Test Scenarios

- Probe: all rows within; one overdue; one unknown; both web rows in each order; threshold boundary; reader exit 4; zero rows; summary-only output; an unseen role row; non-numeric `uptime_s`; a column inserted before the fixed columns; the ignored dogfood role; the reader's role table and header against the probe; stderr token; xtrace refusal exits 78; no arguments; `env -i` run.
- Exposure: zero rules; rules present; inline binding; attachment binding; no binding; dynamic block; unmapped server; ignored `removed` block and comment; control firewall with rules; empty directory; servers with no firewalls; real tree.
- Hygiene: forbidden-token scan; no hold or gate marker lines in the runbook or the deferred section; runbook lint.

## Test Strategy

Bash suites in the repository's existing style (`ok`/`bad` counters, a printed total, case-count and assertion-count floors), registered by hand and re-balanced by the generator. The probe suite stubs the reader with synthesized rows only (no real role output, no real kernel strings). The Terraform fixtures are synthesized in a temporary directory per case. No test uses the network, `gh`, Doppler or SSH.

## Risks

- **False all-clear.** Mitigated by unknown-by-default, fail-closed reader handling, and by not arming the probe until a host reports. Residual: `nothing-to-report` is reachable once every row is fresh and within cadence, and says nothing about unmeasured hosts beyond what the reader reports; it also does not show a patched kernel (see Proxy weakness); the tracker body states it is not an assurance.
- **Public residual.** `review-needed` on a public tracker discloses that some row is past cadence (no class, no count). CTO F1 accepted this under ADR-322; the owner can end it by closing the tracker and removing its label.
- **Proxy weakness.** `uptime_s` is a lower bound on kernel age: it resets on a reboot onto the same kernel or a replace onto an unpatched base image, and can come from a row up to 48 h old, so a within-cadence verdict never shows a patched kernel. The header and runbook say so; the `reboot_required` clause is tracked as #12502 and the cloud-init package-upgrade question as #12503.
- **Rows overdue by design.** With no acknowledgement mechanism, a row past its cadence keeps the aggregate at `review-needed`; the mechanism is a numbered arming precondition in the runbook and #12504, not a follow-up.
- **Public surface is wider than the line.** The sweeper wraps the line in a heading with the exit code and a timestamp and names the script path, and the thresholds are public in the probe; a dated daily line can date a reboot window or a lag. Accepted timing disclosure under ADR-322, ended by closing the tracker.
- **Never armed.** Arming needs #12385 (priority p3-low) for `nothing-to-report`; the runbook names raising it or re-evaluating #12504 by a date as the lever.
- **Daily comment volume.** Once armed the sweeper comments on every run; the arming step is deferred until a host reports, and the tracker has a retirement trigger (#12385 and #12386 done and the probe observed through one full cadence).
- **Parser blind spots.** Terraform text parsing relies on `terraform fmt` layout and misses constructs it does not model; every unmodelled construct on a non-web firewall is red, and the control firewall proves the parser reads at all.
- **Declared is not live.** The suite cannot see a stale attachment id or console drift. It says so; the live read is deferred and session-only.
- **A replace may not patch.** Cloud-init does not upgrade packages. Each runbook section ends in a verification step; the question is deferred.
- **Arming is easy to forget.** The only thing that makes the sweeper run the probe is a tracker directive; the unarmed tracker issue stays open until armed, so the gap is visible rather than silent.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder text fails deepen-plan Phase 4.6; this one is filled.
- Any new file under `apps/web-platform/infra/` fires a production apply on merge. All new files live under `scripts/` and `knowledge-base/`; re-check `git diff --name-only` before commit (AC2). The same holds for any path under `plugins/soleur/`, tests included.
- The section name `Deferred Production Acts` is load-bearing: renaming it to anything containing the words "Operator Holds", or starting any line in it with a hold or gate marker, makes `ship` stop at the draft exit (AC10).
- The sweeper republishes probe stdout into a public comment near-verbatim, and runs probes with no `HOME`, `CI` or `HEADLESS_MODE`. Any diagnostic echo added to the probe is a disclosure, and nothing in the probe may assume those variables.
- Do not read `reboot_required` from the marker inside the probe: that would be a second reader with its own copy of the identity rules.
- The shard manifests are generated; a hand-edited row can be rejected by the growth stamp.

## Files to Create

- `knowledge-base/engineering/operations/runbooks/host-kernel-patch-cadence.md`
- `scripts/followthroughs/host-kernel-cadence-12008.sh`
- `scripts/followthroughs/host-kernel-cadence-12008.test.sh`
- `scripts/host-tcp-exposure.test.sh`
- `knowledge-base/project/specs/feat-one-shot-12008-kernel-cadence/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-12008-kernel-cadence/decision-challenges.md`

## Files to Edit

- `scripts/test-all.sh` (two `run_suite` lines with explanatory comments, plus each suite's own `AFFECTED_*_PATHS` block and `ALWAYS_ON_SUITES` entry as the registration-only rule requires)
- `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` (regenerated by `scripts/regenerate-shard-manifest.py`, not hand-edited)
- `scripts/lib/test-affected-paths.sh` only if the selection check in AC5 shows the declarations live there (read it first; the registration-only rule admits only the shapes `bash scripts/test-all.sh --help` lists)

Not edited, deliberately: `apps/web-platform/infra/**`, `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`, `plugins/soleur/**`, `.github/workflows/**`.

## Follow-ups filed (deferral tracking)

Filed 2026-11-09: #12502 (reboot_required column in `host-state.sh` plus the matching overdue clause), #12503 (should cloud-init upgrade packages), #12504 (the unarmed arming tracker, which also carries the deferred acknowledgement scope). Comments posted on #6442, #12385 and #12386 (dependency notes, no new issue). Items 1 and 4 of #12008 itself stay open.
