---
title: Exposure answers are unknown-by-default and session-only in a public repo
status: accepted
date: 2026-11-07
issue: 12006
related_adrs: [ADR-281, ADR-197, ADR-192, ADR-286, ADR-287, ADR-236, ADR-214, ADR-280, ADR-179]
---

# ADR-322: Exposure answers are unknown-by-default and session-only in a public repo

Refs: #12006, #12007. Related: ADR-281 (image scan, public-repo constraint), ADR-197 and ADR-192 (absence of evidence on a log
surface), ADR-286 (Vector admission), ADR-287 (untrusted content), ADR-236 (human-only skills), ADR-214, ADR-280 (credentials on
stdin), ADR-179 (bare plugin-root anchor). Plan: `knowledge-base/project/plans/archive/20261108-004152-2026-11-07-feat-cve-exposure-skill-plan.md`.

## Context

`plugins/soleur/skills/cve-exposure/` answers "are we subject to CVE-X" for Soleur's own infrastructure, read-only, from Terraform
and Better Stack telemetry, never SSH. The question has two failure modes that a plain checklist does not prevent:

1. **A silent surface reads as a clean surface.** A host that stopped shipping logs, a stale marker, a query error or a component
   with no mapping all return "nothing found". Reading that as "not affected" is the error ADR-197 and ADR-192 already name for
   log surfaces; here the cost is a false all-clear on a security question.
2. **This repository is public.** An exposure table that lists exact component versions, host names or addresses next to a CVE is
   a targeting list (the constraint ADR-281 records for the image scan). Issues, commit messages, PR titles, review comments and CI
   logs are all publicly readable. The skill also reads advisory text from the network, which is attacker-influenced input.

ADR-281 left one item open: there is no private durable place for per-finding dispositions. That is still true, and this ADR does
not close it.

## Considered Options

- **A. Unknown-by-default, session-only table, one-status chokepoint for durable artifacts (chosen).** Pros: no exact exposure data
  leaves the operator session; the only public write is fixed and enumerable. Cons: the answer is not durable, so a later session
  repeats the read.
- **B. A durable private exposure register (rejected).** No private durable store exists for this repo; ADR-281 records the same gap.
  Building one is a separate decision and would hold the most sensitive data the company has.
- **C. Exact versions in gap issues after redaction (rejected).** Redaction of a free-text body is a second uncontrolled path, and
  a public issue naming a component version and a CVE is a targeting list whatever else is removed.
- **D. Mark the skill `disable-model-invocation` to save description budget (rejected).** The Skill tool refuses such skills, so
  `/go` could not route to it (ADR-236). The skill pays the description-budget cost like the other customer-session skills
  (precedent: `invoice`, `operator-digest`); the cap is raised by the measured words in the same change.
- **E. No gap issues at all (dissent, recorded).** See Consequences.

## Decision

1. **Affected and Reachable are three-valued: yes, no, unknown.** An unobservable, stale, silent or unmapped surface is `unknown`,
   never "not affected". `Affected=no` on a mutable host needs fresh observation of the kernel or package version itself (marker liveness is not that); a declared-only source supports `no` only for an
   immutable, digest-pinned artifact. `Reachable=no` needs positive evidence from both the network layer and the code path. The
   overall verdict is worst-case: unknown reachability counts as reachable. This extends ADR-197 and ADR-192; "tri-state" is
   avoided in the title because ADR-192 already uses "three states" for a different classifier.
2. **The detailed exposure table is session output only.** Durable public artifacts carry only the single status
   `exposure-review-needed`, the CVE id and a generalized class (`infra`, `runtime` or `dependency`), and they are written through
   one chokepoint script, `file-gap-issue.sh`, the only place that composes public issue text. It takes enumerated arguments only
   (no free text), uses a fixed title and body, defaults to a draft, requires `--exploitation none-found` to create, refuses
   `--create` when an unattended run is detectable (`HEADLESS_MODE` set to anything but empty/`0`/`false`, or `CI`/`GITHUB_ACTIONS`
   set), and de-duplicates against open and closed issues in `jikig-ai/soleur`. The operator's explicit yes is an instruction to the
   agent in SKILL.md that the script cannot verify: measured in a tool shell, `HEADLESS_MODE` is unset and stdin is not a TTY even
   when attended, so neither can tell attended from unattended (CTO ruling on the review of #12343). Never versions, hosts, addresses, kernel strings, advisory text, or the words "not affected" or "patched" beside a CVE
   id. A confirmed "no exposure" files nothing; any permitted wording is source-bounded and dated and states that it is not a
   security representation. This generalizes ADR-281 constraint 2 beyond the image scan; it does not close ADR-281's open item
   on a private place for dispositions.
3. **Fetched advisory text is untrusted.** It is annotated and never executed or copied into a durable artifact. This applies ADR-287's
   untrusted-content stance to a stricter case (never executed, never copied into a durable artifact); ADR-287 itself is cited, not re-decided.
4. **Hand-off to `fix` carries only the CVE id, the component class and the verbatim disclosure rule.** The disclosure rule for
   fix-flow artifacts lives in the skill's hand-off text, not in AGENTS.md: exposure data exists only in this skill's context, and an
   always-loaded rule is paid on every turn for a single-skill concern. `fix`, `compound` and `ship` do not load the rule, so the
   hand-off payload carries its text.
5. **The reader is verified before it runs.** `host-state.sh` executes `scripts/betterstack-query.sh` (and may source
   `scripts/lib/betterstack-read-classify.sh`) from the current checkout under the operator's injected Doppler credentials. The
   Step 0 file-existence guard only separates a Soleur checkout from a customer checkout; it does not make a planted clone safe, and
   the earlier reasoning that "a fork that passes lacks the credential" is withdrawn (the credential is the operator's, not the
   clone's). So the helper clears every `GIT_*` variable, downloads the two reader files from upstream main over HTTPS, and runs
   nothing unless both are byte-identical to the checkout's copies; offline, a failed download or any difference makes every host
   `unknown` and exits 4. A branch that edits the reader is refused by design. The residual is the helper itself, which the operator
   chose to run from this plugin (CTO ruling on the review of #12343).
6. **A failed-deploy kernel row never grounds `Affected=no`.** It is `observed-stale` evidence (up to 7 days old); `no` on a mutable
   host needs a periodic report at most 48 hours old, which no marker supplies until #12007 ships. An image-scan finding list holds
   only fixable critical/high matches, so absence from it is `unknown`, never `no`.

## Consequences

- **Enforcement covers this skill's own writes only.** `fix`, `compound` and `ship` hold no exposure table and are not constrained
  by it; the hand-off payload is the only thing that reaches them. A lint over `knowledge-base/**` that rejects a CVE id paired
  with "not affected" is the cross-skill backstop; it is a tracked follow-up (#12348) filed with this change, not delivered here.
- **Public residual.** Even the single status discloses that Soleur may be exposed to a named CVE. That is bounded by dedupe (one
  issue per CVE and class), draft-by-default, the unattended-run refusal plus the operator's explicit yes, and the exploitation gate: with any evidence of exploitation the skill
  files nothing public and hands off to the breach-triage path. The skill never decides that a breach occurred.
- **Dissent.** The DHH plan-review reviewer argued for dropping gap-issue filing entirely, since any public mention is a
  disclosure. The plan keeps filing, narrowed to one status and a fixed body, and records the dissent as a user-challenge row in
  `knowledge-base/project/specs/archive/20261108-004152-feat-one-shot-12006-cve-exposure-skill/decision-challenges.md` for `ship` to surface. Reversing it
  later is a deletion of the script and its call site; no data depends on it.
- **Not durable.** Re-asking the question re-runs the telemetry read. That is cheap and keeps the answer fresh, which is the point
  for a mutable host.
- **Fix diffs and search consistency.** A runtime or dependency fix PR shows the new version in its public diff; the skill asks the
  operator to acknowledge that residual before the PR is opened and cannot prevent it. The duplicate check relies on GitHub search,
  which is eventually consistent, so two rapid `--create` runs can still file twice.
- **Telemetry rows are trusted as written.** Anyone holding the Better Stack ingest token can forge a marker row, and a forged row
  can fabricate `fresh`. The skill never lets a single marker ground `Affected=no`, and the reader is verified; forged telemetry from
  a legitimate ingest credential is a residual this skill does not defend against.
- **Scope.** The skill is operator tooling for Soleur's own stack (file-existence scope guard); a customer's question about their
  own product goes elsewhere. It is read-only, makes no coverage or assurance claim, and its output is labelled advisory in SKILL.md. No row is added to the public security-claim ledger, whose scope is isolation, egress and approval.

## Cost Impacts

None. Reads use the existing Better Stack credential; the only recurring cost is the skill description's share of the per-session
description budget, paid by raising the cap by the measured word count.

## NFR Impacts

None. No new container, store or link is introduced; two operator-session edges are added to the C4 model (`founder` to
`betterstack`, `founder` to `github`).

## Principle Alignment

None. No AP-NNN deviation; the skill follows the no-SSH diagnosis rule and the Terraform-first rule by construction.

## Diagram

The two edges are in `knowledge-base/engineering/architecture/diagrams/model.c4`: `founder -> betterstack` (fixed read-only
ClickHouse SQL, session-only output) and `founder -> github` (gap issues in the Soleur repository only, through the chokepoint,
visible to `publicReader`). There is deliberately no `plugin -> betterstack` edge: it would contradict the customer-facing edges
that state Jikigai receives nothing from the customer's repository.

## Addendum 2026-11-08 (#12007): the periodic kernel marker

Decision 6 said a periodic report "no marker supplies until #12007 ships". This addendum records that the marker now exists. It
amends decision 6 and leaves decisions 1 to 5 unchanged; the text above is not rewritten.

**Rollout status: adopting.** The target state below lands in the repository in this change. No running host emits the marker
yet: delivery to running hosts, the inngest and registry re-provision and arming the heartbeats are operator-reserved holds
tracked in #12386. Until a host emits, it stays `unknown` in the skill output, which is the honest state and not a defect.

1. **The marker.** `SOLEUR_HOST_KERNEL v=1` is printed by one shared collector every 6 hours and once per boot on web-1, web-2,
   the inngest host and the registry. Journald hosts ship it through the Vector path they already have; the registry posts it
   directly through its existing disk-heartbeat sender.
2. **Identity.** For journald hosts the identity is the Vector-stamped `host_name` plus the exact `SYSLOG_IDENTIFIER`; a
   self-declared `role=` field is only a cross-check, and a mismatch drops the row. The registry has no Vector stamp, so its
   identity is `role=registry` plus `host=<registry host id>`, and both must match. A row on the journald path that carries a
   `host=` field is rejected. A row with an unknown version token is ignored, and the kernel must match the existing anchored
   kernel shape. The residual stays the one decision 5 and the Consequences already accept: a holder of the ingest token can
   forge a row.
3. **A third `kernel_state` value, `stale`.** The enum becomes `observed | stale | unknown`. `observed` needs a valid kernel
   shape on the newest valid periodic row, at most `FRESH_HOURS` = 48 hours old. `stale` keeps the kernel string and its age
   visible for an older periodic row or for a failed-deploy row alone, and never grounds `Affected=no`. Anything else is
   `unknown`. Precedence: a fresh periodic row, then the newest older periodic row, then the failed-deploy row. A newest row
   with an unreadable kernel does not shadow an older valid one.
4. **The staleness alert is a per-host dead-man heartbeat, not a native alert.** There is one Better Stack heartbeat per host
   (`soleur-host-kernel-<role>-prd`), fed hourly by the existing dead-man feeder only while that host has a qualifying row inside
   a literal 36 hour window. With period 3600 and grace 7200 the worst case from a host going dark to a page is about 40 hours,
   before the skill stops trusting a report at 48 hours. A native alert cannot do this: its `query_period` is capped at 900
   seconds, and a row that arrives every 6 hours is invisible to a window that short, so a native alert would be blind.
   The heartbeats are born paused and armed by the owner (#12386).
5. **Hosts that stay `unknown` by design.** The git-data host ships to its own Logs source and needs a table pin in two readers;
   it is tracked in #12385. The grok-dogfood host is default-off with no shipper and is a census exemption. Both remain
   `unknown` and are never read as clean.
6. **Display-only fields.** `reboot_required`, `sec_updates` and uptime are emitted on a best-effort basis, print `unknown` when
   unmeasurable, and never feed `kernel_state`. The patching-cadence alert that would use them belongs to #12008.

### Alternatives considered in this addendum

- **A native Better Stack log alert for staleness (rejected).** The 900 second `query_period` ceiling makes it blind to a
  6-hourly row; it would either never fire or fire constantly. This is the reason for the dead-man design above.
- **One aggregate heartbeat for all hosts (rejected).** A single beat fed while any host reports hides the one host that went
  dark, which is the failure the alert exists to catch. One heartbeat per host names the dark host.
- **Per-class emitters (rejected).** A separate emitter for each shipper class (journald hosts, registry) would be a second and
  third copy of the line format and the kernel shape. One shared collector prints one canonical line and thin sink adapters
  carry it.
- **`--sink post` in the collector (rejected).** Letting the collector post directly would add a fifth hand-pinned copy of the
  ingest-token judge. The collector only prints; the registry's existing sender, which already holds that judge, posts it.

### Consequences of this addendum

- The skill can ground `Affected=no` on a mutable host for the first time, but only from an `observed` row at most 48 hours
  old; `stale` and `unknown` never do, and one marker still never grounds `no` on a path it cannot observe.
- A planned replace of the inngest or registry host goes dark for up to the 36 hour window, so its heartbeat is paused first
  (runbook `workspaces-luks-cutover-6604.md`, arming section).
- No new ordinal, container, store or link is introduced. The C4 edge prose in `model.c4` is extended for the existing edges
  to `betterstack`; no element or relationship is added.

## Addendum 2026-11-08 (#12007 review)

Append-only: the addendum above is not rewritten. Where this section disagrees with it, this section governs. The rulings are
recorded in `knowledge-base/project/specs/feat-one-shot-12007-host-kernel-marker/decision-challenges.md`.

1. **Item 3 is amended (unreadable newest row).** The newest mapped periodic row of a host decides. If that row is unreadable,
   `kernel_state` is capped at `stale`: the kernel string and the age of the older valid row stay visible and never ground
   `Affected=no`. The sentence "a newest row with an unreadable kernel does not shadow an older valid one" is withdrawn, as is
   the matching G1 wording. The `LIMIT 6 BY` bound on the kernel bucket is unchanged: eviction can only lose the older kernel
   shown in a `stale` display and cannot create a false `observed`, because the newest rows are the ones kept.
2. **What "decisions 1 to 5 are unchanged" does not cover.** The Consequences bullet "Telemetry rows are trusted as written",
   whose second sentence reads "The skill never lets a single marker ground `Affected=no`", is superseded for the periodic
   marker. A single valid periodic row at most 48 hours old may ground `Affected=no` on the kernel question, because that is
   the point of the marker; the matching clause "one marker still never grounds `no` on a path it cannot observe" in the
   addendum's consequences is withdrawn in the same sense. The bullet stands for everything else the skill reads.
3. **Residuals, stated for each path.**
   - *Freshness clock.* Freshness is measured on Better Stack ingestion time (`dt`), not on a time the host wrote, and there is
     no `ts=` field. A delayed delivery makes a row look younger than it is. Accepted and documented; evidence that would flip
     it is Vector's journald events carrying the original `__REALTIME_TIMESTAMP` in `raw` (unverified, a follow-up).
   - *Journald path.* Identity additionally pins `_SYSTEMD_UNIT` to `host-kernel-marker.service` in the helper and in the three
     feeder journald predicates. A local process can forge `SYSLOG_IDENTIFIER` with `logger -t`; it cannot choose the systemd
     unit of its message, so local-process forgery is closed. What remains on this path is root on the host. There is no
     `_HOSTNAME` requirement, recorded as an accepted residual; evidence that would flip it is `host_name` proving not constant
     per host. Both readers also reject any occurrence of the substring `host=` in a journald-path message, not only a trailing
     token.
   - *Registry path.* The registry has no Vector stamp, so its identity (`role=registry` plus a trailing `host=<registry host
     id>`) is declared inside the message itself. The residual is the holder of the shared Logs ingest token, who can post a
     row that satisfies both checks. The runbook sentence that a marker never grounds `Affected=no` by itself on a path it
     cannot observe is read as this residual and nothing wider; it does not promise more than the registry can give.
4. **The 900 second figure is a repo policy ceiling, not an incident cause.** The sentinel test
   `logs-alert-query-period-ceiling.test.sh` enforces 900 seconds for new native logs alerts, and a 2026-11-07 vendor
   measurement (see the logs-alert comments near the dead-man heartbeats in `uptime-alerts.tf`) found newly created alerts above
   900 seconds refused with a 422. ADR-218 records a contrary read-back of 97200, so the vendor limit is not treated as a
   stable fact. Incident 1023423999 is not evidence of a cap: it was a 97200 second window reading 0 on a once-daily row. The
   decision rests on the cadence argument, which holds either way: a window shorter than 6 hours cannot see a 6-hourly row, so
   a native alert is blind to this marker. Where the earlier text above attributes the choice to a "900 second cap", read it as
   this.
5. **Identity safety across a host rename.** Until 2026-09-19 Vector stamped web-1's rows with the inngest host's `host_name`
   (see the comment on the shared-predicate alerts in `betterstack-logs-alerts.tf`). The `role=` cross-check and the 36 hour
   window keep identity safe: a stale row under the wrong stamp is outside the window, and a current row whose `role=`
   disagrees with its `host_name` is dropped.
6. **Delivery caveat and what "held" means for the inngest host.** The inngest host receives the emitter only through the
   digest-pinned bootstrap OCI image. A new bootstrap tag must be minted and the pin bumped before a replaced host boots with
   it, and a routine bootstrap-version bump re-runs the bootstrap on the running inngest host, which would also install the
   emitter. So for the inngest host "held" means the pin bump is itself the delivery event, and #12386 must say so. The
   per-host-class carrier, precondition and expected drift are in one table, the delivery matrix in the host-kernel section of
   `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`; this ADR, the C4 prose and the query
   runbook refer to it and do not restate it.

## Addendum 2026-11-08 (#12007 fix round)

Append-only: the earlier addenda are not rewritten. Where this section disagrees with them, this section governs. The ruling is
recorded in `knowledge-base/project/specs/feat-one-shot-12007-host-kernel-marker/decision-challenges.md`.

1. **The registry emitter is deferred to an owner-approved follow-up PR.** The earlier addendum of this date (item 1, "the registry posts it
   directly through its existing disk-heartbeat sender") states that the registry
   emits the marker. That statement is superseded by this addendum: the registry does not emit the marker in the change that
   introduces it, and no registry emitter edit is in that change.
2. **Why.** Merging a change to the registry host's cloud-init auto-fires the registry-host-replace dispatcher
   (`.github/workflows/registry-host-replace-dispatch.yml`). The dispatcher renders the registry user_data offline and, when it
   differs from the merge base, emits deliver=true and, after a read-only preflight, runs the registry-host-replace apply with no
   reviewer gate and no confirm token (ADR-190: the merge is the intent to deliver). That replaces the production registry host,
   the sole pull path, with no rollback if the create fails after the destroy. The follow-up PR is therefore merged only with the
   owner's explicit go-ahead and never ahead of the owner; it is tracked in #12386.
3. **What stays in the first change.** The collector's `--role registry` support, the helper and feeder registry decode (the
   identity rule of the earlier addenda, `role=registry` plus the trailing `host=<registry host id>`), and the paused
   `host-kernel-registry` heartbeat. They are inert for the registry until the follow-up merges.
4. **Expected state.** The registry reads `unknown` in the skill output until the follow-up merges and the host is replaced. That
   is the honest state, not a defect, and it is never read as clean. Until the heartbeats are armed, the only read for any host is
   the credentialed query or the credentialed helper (`host-state.sh`).
5. **Decisions 1 to 5 and the other addendum items are unchanged.** The journald-path residual, the registry-path residual (the
   holder of the shared ingest token) and the freshness-clock residual of the review addendum stand; the registry-path residual
   applies from the day the follow-up delivers a row.
