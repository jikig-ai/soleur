---
title: "feat: ADRs for per-session ephemeral containers and Landlock ruleset"
date: 2026-11-03
slug: adrs-ephemeral-containers-landlock
branch: feat-one-shot-9602-adr-ephemeral-containers-landlock
issue: 9602
type: feat
priority: p3-low
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
detail_level: more
---

# feat: ADRs for per-session ephemeral containers and Landlock ruleset

**Ref #9602, Ref #9601.** Draft PR #11935. No `Closes`. #9602 stays open after merge.

CPO plan-time sign-off waived by CTO ruling 2026-11-03: diff is limited to two proposed ADRs (ADR-315, ADR-316), the spec dir and this plan, and changes no runtime behaviour or user-facing surface. soleur:engineering:review:user-impact-reviewer runs at review as the diff-time check. Any widening of the diff beyond this scope revokes the waiver and requires a CPO consult. (decision-challenges rows S and W; row W lets one knowledge-base learning file in without revoking it.)

## Overview

Two decision records, no implementation, no control shipped. Both are written at status `proposed` (rich shape, passed explicitly) and both open their Status section with the same line: the control in force today is ADR-075 (bwrap per session inside one shared container) plus the current seccomp profile.

- **ADR-315** (container ADR): records the per-session-ephemeral-container option for hosted agent sessions, its evidence gate and its cost axis. It relates to ADR-075 and makes no topology decision; the topology decision of record belongs to #9854 under epic #9842.
- **ADR-316** (Landlock ADR): records an active Landlock ruleset as a layer beneath bwrap. It supersedes nothing; the ruleset is applied inside the sandboxed child after the mount table is built and before the command is exec'd, and adoption is gated on a kernel-ABI and canary-compatibility spike.

Ordinals are provisional: the next two above the highest claimed on any origin ref or open PR (origin/main max is ADR-313; ADR-314 is claimed by both #11918 and #11867). Recomputed at write time, before the final push, and after every merge of origin/main (Phase 0 step 1, Phase 3 step 10).

## Research Reconciliation - Spec vs. Codebase

| Brief claim | Reality (evidence) | Plan response |
|---|---|---|
| "no open PR collides in scope with #9602" | Open epic #9842 (gVisor sandbox per tenant session, operator-selected Approach B), its pending decision-record child #9854 ("amends ADR-068 section 8 and ADR-075 Option B") and open WIP PR #9832 (brainstorm and spec only, branch `feat-tenant-executor-topology`) overlap the container ADR. No file collision, a real scope overlap. | Rulings M and O: bounded container ADR, relates-only, topology deferred to #9854; overlap recorded in the plan and PR body. |
| "a microVM or gVisor-class runtime (rejected for now)" | #9842 selects a gVisor-per-session executor as the operator's direction. | Ruling N: the option is "the operator-selected direction under epic #9842 ... not decided or shipped by this ADR; its topology decision is reserved to #9854". The words rejected, adopted and planned are not used for it. |
| tenant-count threshold "an estimate, marked as such, if not measured" | No recorded cold-start, per-session memory or tenant-count result exists (negative search, scope and date in claim C9). Existing numbers are the #9842 brainstorm Decision 11 tripwires and roadmap row 4.6 ("Container-per-workspace isolation", gate "5+ concurrent users", #673). | Ruling P: reuse the tripwire numbers under explicit labels; #9854 owns the recorded trigger and wins on conflict (Architecture review). |
| "the three landlock syscalls allowed near lines 194-196" | Verified: `apps/web-platform/infra/seccomp-bwrap.json:194-196` names the three syscalls in the unconditional allow block (opens at line 59, `SCMP_ACT_ALLOW` at line 422, no `includes`); `defaultAction` is `SCMP_ACT_ERRNO` at line 2. | Cite with the content anchor. |
| "no ruleset is configured" | Verified by negative search (claim L2): Landlock appears only as these allowlist names in the profile and the pre-5874 canary fixture. | Label `measured` with command, scope and date. |
| "expect ADR-315 and ADR-316" | origin/main max ADR-313; open PRs #11918 and #11867 both claim ADR-314. | ADR-315, ADR-316, recomputed (Phase 0). |
| "related ... plus the credential-broker measurement PR only if OPEN" | Measurement PR #11624 is MERGED (2026-10-30): not listed. | Not listed. |
| "ADR-075 ... one shared container, bwrap per session" | ADR-075 addenda through 2026-10-31: the per-session outer wrap is flag-off on the shared prod container, Option B exits only via #9773 Stage 1. | The ADRs say "the control in force is ADR-075 as amended" and cite addenda by content anchor. The #9842 spec is stale on this (it records arm F as merged; ADR-075 2026-10-09 records the elevation arm reverted): do not cite the spec for the control in force. |
| ADR template says status `active \| superseded` | The corpus uses `proposed` (ADR-131, 220, 221, 241) and `adopting`; no validator enforces a status enum. | `status: proposed`. |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #9602, #9601, #9543, #9773, #9842, #9854 OPEN; #11624 MERGED; #5863 CLOSED. PR #11935 is this branch's own draft; collision-precheck also reported two `test-all.sh` processes owned by another worktree, which touch nothing in this scope. Cited paths confirmed: the seccomp profile, ADR-075/079/272/311, `apps/web-platform/infra/bwrap-shim/bwrap`, `apps/web-platform/scripts/sandbox-canary.mjs`, `apps/web-platform/infra/sandbox-canary-argv.json`. Mechanism check against the ADR corpus: per-tenant containers are ADR-075 "Option B" (deferred) and the executor topology is the open #9854 record; Landlock appears in no ADR. Stale: "no open PR collides" and "gVisor-class rejected" (table above).

**Property List (Phase 0.6b).**

1. A reader of the public repo can find, for each option, what it is, what was considered, and what evidence must exist before adoption.
2. No reader can take either ADR as a shipped control or as acceptance of the residual risk ADR-075 records.
3. Every claim states whether it was measured, read from a file, or unverified.
4. The ADR text does not help an attacker (no exploit recipe, no unpatched-CVE detail, residual risk at ADR-075 and ADR-272 granularity).
5. The container ADR neither duplicates nor contradicts the executor-topology record (#9854).
6. The Landlock ADR names where the irreversible call must happen and who owns the kernel-ABI measurement, so no later spike is scoped twice.
7. The change is inert and reversible: nothing under apps/, .github/, docs/legal/, plugins/soleur/docs/, any .tf file or any flag configuration changes.

**Cut List (Phase 0.6b).** (a) model.c4 / nfr-register / domain-model edit: cut by ruling I; (b) ADR-075 body edit: cut by ruling I (`related_adrs` carries the link); (c) follow-up issues: cut by ruling K; (d) a new guard or test for the labelling convention: cut (no test may cite the new files; labels are verified by review and the ACs); (e) `pre-push-ratchet-lane.sh` as an extra step: cut (plan review: the individually named ratchets already cover the brief). Kept with a covering requirement: two ADR files (property 1), status `proposed` (properties 2 and 7).

**Skipped by ruling.** Functional-overlap registry check (ruling V), gdpr-gate (ruling R, acceptance criterion AC9; a known deviation from the gate's literal trigger, mitigated by that criterion), observability block (ruling U), value-proposition measurement (no saving is claimed). Community discovery: no uncovered stack (TypeScript and bash).

**Institutional learnings applied.** Re-census ADR ordinals on fresh refs at write, push and ship, and renumber own ADRs only (`workflow-patterns/2026-07-05-adr-ordinal-collision-on-rebase-renumber-mine-not-mains.md`); bare ordinals in renumber notes (`workflow-patterns/2026-07-06-adr-renumber-provenance-note-must-use-bare-ordinals.md`); write ADRs with the Write tool and verify line count and headings after (`2026-10-09-my-scripted-adr-rewrite-cut-the-file-at-the-wrong-match-and-every-gate-passed.md`); never `markdownlint --fix` on ADR prose (`best-practices/2026-04-19-markdownlint-fix-mangles-issue-ref-at-line-start.md`); measure and label every number, and a measurement carries its machine (`2026-10-07-a-docs-pr-took-four-review-rounds-because-each-fix-shipped-its-own-unmeasured-claims.md`, `2026-08-13-a-benchmark-carries-the-machine-that-produced-it.md`); a suite must prove its premises, so the Landlock gate carries a positive control (`2026-10-30-a-nonempty-check-was-satisfied-by-the-error-message-it-should-have-caught.md`); file tools run outside bwrap (`security-issues/2026-10-08-file-tool-tier-outside-bwrap-isolation-boundary-is-the-cli-process.md`); the KB-consumers gate runs even for docs (`2026-10-12-docs-only-ci-skip-premise-is-false-when-tests-read-the-kb.md`).

**Spawn facts the Landlock ADR rests on** (re-verified at write time, content anchors): the SDK spawns a PATH-resolved `bwrap`, wrapped by the shim `apps/web-platform/infra/bwrap-shim/bwrap` (ADR-075 2026-10-06 addendum); `makeSandboxedSpawn` in `apps/web-platform/server/agent-outer-wrap.ts` execs `/usr/bin/bwrap` directly and bypasses the shim, is reached through `spawnClaudeCodeProcess` in `agent-runner-query-options.ts`, and is gated by the outer-wrap flag and `AGENT_OUTER_WRAP_WORKSPACES` (flag-off on the shared prod container, ADR-075 2026-10-09 addendum). The shim therefore sees only the inner per-Bash bwrap. The faithful canary (ADR-079) replays the captured bwrap SETUP argv against the loaded profile and never reaches `query()`; its derived hardening probes (`runHardeningProbes`, `runArgsFdTransportProbe` in `sandbox-canary.mjs`) are where a Landlock probe would sit.

## Standing Constraints (operator, not steps of this PR)

No Standing Delegation exists on the epic and no act is delegable. This PR performs no production act, so none of the following is a step, task or wait state of this plan; they are boundaries the diff must not cross.

- Creating or flipping any feature flag (credential broker, approval queue, egress-audit collection) in any environment stays with the operator.
- The egress-audit enablement issue is not worked, referenced or closed by this PR.
- No production write needing operator approval is performed.
- Legal wording sign-off at flag-on stays with the operator; the CLO only prepares.
- No public security claim ahead of a measured control; toggle copy and legal docs stay unchanged unless a PR ships the control. Neither ADR ships a control.
- If the diff must touch a public or legal file, anything under apps/, .github/ or plugins/soleur/docs/, any .tf file or flag configuration: revert that file out of the diff, keep PR #11935 draft (no `gh pr ready`, no auto-merge armed), file exactly one `action-required` issue naming the action, record it in `session-state.md`, name it in the PR body, and print one plain sentence in the session (ruling AA). The CLO is then mandatory and these boundaries stand.

## Scope Check

### Ask Mapping

All brief rulings apply and are recorded as rows A-AA in `decision-challenges.md`. The asks that name a deliverable or a verifiable property:

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "write TWO decision records (ADRs, not implementation) for (1) per-session ephemeral containers for hosted agent sessions" [brief] | Phase 1: ADR-315 | mapped |
| 2 | "(2) an active Landlock ruleset" [brief] | Phase 2: ADR-316 | mapped |
| 3 | "write BOTH ADRs now at status `proposed`, NOT `adopting`" [brief ruling] | Phases 1-2 frontmatter and Status; AC3 | mapped |
| 4 | "take the next two ordinals above the highest ordinal claimed by origin/main OR any open PR" [brief ruling] | Phase 0 step 1, Phase 3 step 10; AC2 | mapped |
| 5 | "Pass `shape: rich` explicitly" [brief ruling] | Phases 1-2 heading list; AC4 | mapped |
| 6 | "Label EVERY claim in both ADRs as `measured`, `read from file:line`, or `unverified`" [brief ruling] | Claim ledgers; AC5 | mapped |
| 7 | "describe residual risk only at the granularity of ADR-075 and ADR-272; no exploit recipes; no unpatched-CVE detail" [brief ruling] | Disclosure rules; AC6 | mapped |
| 8 | "a decision stated as \"not adopted now, adoption gated on the measured preconditions below\"" [brief ruling] | Decision sections; AC3 | mapped |
| 9 | "the relation to the credential broker (#9543) and ADR-311 (the broker is NOT shipped, only its mechanism was measured)" [brief ruling] | Context sections; AC7 | mapped |
| 10 | "a no-public-claim clause (at any future adoption, flag creation and legal wording stay operator-class)" [brief ruling] | Decision sections; AC7 | mapped |
| 11 | "Adoption gate is quantified evidence: put a number on the tenant-count threshold" [brief ruling] | ADR-315 P1-P5 with ruling P labels | mapped |
| 12 | "the ruleset must be applied in the sandboxed child before exec, never in the shared server process" [brief ruling] | ADR-316 Considered Options and Decision; AC7 | mapped |
| 13 | "Gate: a spike that measures kernel ABI support on the prod host and in the container" [brief ruling] | ADR-316 G1-G6 (named, not scheduled; ruling Q) | mapped |
| 14 | "do NOT edit model.c4 or model.likec4.json; do NOT edit nfr-register.md; do NOT edit domain-model.md; do NOT edit the body of ADR-075" [brief ruling] | Architecture Decision section; AC1 | mapped |
| 15 | "`Ref #9602` and `Ref #9601` ONLY, never `Closes #9602`" [brief ruling] | Phase 4 PR body; AC8 | mapped |
| 16 | "After merge comment on #9602 with the ADR links and the remaining criterion" [brief ruling] | Phase 4 post-merge step | mapped |
| 17 | "file NOTHING" [brief ruling] | Non-Goals; AC8 | mapped |
| 18 | "Run the vocabulary check against glossary.md" and the ship-time ratchets [brief ruling] | Phase 3 | mapped |
| 19 | "git diff --name-only origin/main shows only the two new ADR files and this feature's own knowledge-base/project/specs/feat-* files" [brief ruling] | AC1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| ADR-315, ADR-316 files | asks 1-2 | asked |
| Phase 0 ordinal and overlap re-checks | "recompute at write time, and re-run the ordinal check right before the final push" | asked |
| Claim ledgers | "Label EVERY claim in both ADRs" | asked |
| `related` and `related_adrs` additions, gVisor sentence, tripwire label, G6, flip semantics | "Ruled by CTO agent, 2026-11-03" rows M, N, P, X, Y, Z in decision-challenges.md | asked |
| AC9 no-personal-data check | "add a work-phase acceptance criterion that the ADR text makes no personal-data claim" (ruling R) | asked |
| `c4-count-parity` evidence | "runs plugins/soleur/test/c4-count-parity.test.sh" (ruling T) | asked |
| AC1 negative control | - | inferred - justification: a diff-scope filter that cannot fail certifies nothing, so one control run that must trip it travels with the AC |

### Split Assessment

- Subsystems touched: 2 - knowledge-base/engineering/architecture/decisions, knowledge-base/project (plans and specs)
- Planned files: 2 ADRs + 4 feature artifacts = 6 | Estimated changed lines: 520-700
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (the brief mandates one PR; no threshold is reached)

## Architecture Decision (ADR/C4)

### ADR

The two ADRs are this plan's deliverable, written in this PR: ADR-315 (container; relates to ADR-075 and ADR-068; no `amends` or `supersedes` key) and ADR-316 (Landlock; supersedes nothing). Both `proposed`. No existing ADR body is edited (ruling I); ADR-075 is linked through `related_adrs` only. The `adr:` frontmatter key is forbidden (`scripts/check-adr-ordinals.sh` layer 4): the ordinal lives in the filename.

### C4 views

No C4 impact and no `.c4` edit (ruling T). Read: all three of `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4` and `spec.c4`. Checked: (a) actors - `founder` plus the product end-user and untrusted-contributor actors; no new actor, since neither ADR adds a person-facing surface; (b) external systems - Hetzner, GHCR/zot, Doppler, Flagsmith, Sentry/Better Stack are modelled and neither ADR adds a vendor edge (OpenShell and `sandlock` are named only as unverified candidates, not as model systems); (c) containers and stores - `platform.claude` (Agent Runtime), `hetzner` (Compute, "Nomad clients, spread placement"), `workspacesVolume`, `egressGw`, `coordinator` (Session Router), `scheduler` (Nomad Scheduler) are modelled and unchanged; (d) access relationships - unchanged. A `proposed` ADR that ships no control introduces no element or edge. Evidence: `bash plugins/soleur/test/c4-count-parity.test.sh` in Phase 3 step 6, exit code and output pasted into the PR.

### Sequencing

Both ADRs describe a target state that is only true after later work. They are authored now at `proposed`, flip to `adopting` under the semantics in rulings X, and are never postponed to their own issue; #9602 is the tracker.

## User-Brand Impact

- **If this lands broken, the user experiences:** a hosted-agent customer, or a prospect reading the public repo, takes a `proposed` record as a control that exists: an ADR titled for per-session containers or a Landlock ruleset reads as "my sessions are already isolated that way", and a buyer or the founder repeats it in a security answer ahead of any measurement. Two further concrete misreadings: an unverified Landlock claim (that the ruleset can be applied without affecting the shared server, or that the production kernel supports it) taken as fact and used to scope work or to answer a customer; and "not adopted" read as "accepted risk", letting the residual risk ADR-075 records look closed by silence.
- **If this leaks, the user's workflow is exposed via:** the ADR text itself, because the repo is public: exploit-shaped detail (a step list for crossing the shared-container boundary, the specific gaps a ruleset would close, unpatched-CVE detail for the sandbox stack) is a public statement aimed at the tenants who run on that container. The failure is disclosure that aids an attacker, not data exposure; residual risk is therefore described only at the granularity ADR-075 and ADR-272 already publish.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** `single-user incident`, not `aggregate pattern`, because the brief rules it so and one tenant acting on a mis-stated isolation claim, or one attacker helped by a published boundary description, is enough to damage the brand on a security-sensitive hosted-agent product; the diff is docs-only, so the review panel is the user-impact-reviewer and security-sentinel and not a CPO or CLO consult.

Review runs `soleur:engineering:review:user-impact-reviewer` (the four failure modes against the ADR text) and `soleur:engineering:review:security-sentinel` (disclosure level of the ADR text). Prior-art note: the archived three-layers brainstorm mentions a third-party sandbox-escape CVE from a secondary source; it is NOT carried into either ADR.

## Implementation Phases

All writing uses the Write tool, whole file, never a scripted rewrite. After writing, re-read each ADR for line count and the headings Status, Context, Considered Options, Decision, Consequences, Cost Impacts, NFR Impacts, Principle Alignment (in that order; no Diagram section; no section whose whole body is "None"). Citations read `read from <path>:<line>` with a content anchor and the origin/main short sha at write time.

### Phase 0 - Preconditions at work start

1. Ordinals. Fresh refs: `git fetch origin`. Census over every remote ref and open PRs: `for r in $(git for-each-ref --format='%(refname)' refs/remotes/origin); do git ls-tree --name-only $r knowledge-base/engineering/architecture/decisions/; done | sed 's|.*/||' | grep -oE '^ADR-[0-9]{3}' | sort -u | tail -3`, plus `gh pr list --state open --limit 200 --json number,files --jq '.[] | select(any(.files[]?; .path | test("decisions/ADR-3[0-9][0-9]"))) | {number, adrs: [.files[].path | select(test("decisions/ADR-3[0-9][0-9]"))]}'`. Take the next two above the maximum of both (315 and 316 at plan time). On a bump: rename highest first, sweep `grep -rn 'ADR-<old>' knowledge-base/project/plans/2026-11-03-feat-adrs-ephemeral-containers-landlock-plan.md knowledge-base/project/specs/feat-one-shot-9602-adr-ephemeral-containers-landlock/ knowledge-base/engineering/architecture/decisions/ADR-31*` in the same edit (a mechanical edit inside decision-challenges rows D and S, not a re-ruling), leave other PRs' ordinals alone, never reuse a number.
2. Overlap state: `gh issue view 9854 --json state`, `gh pr view 9832 --json state,files`, `git rev-parse origin/feat-tenant-executor-topology` (pin every citation to that branch as `at <sha>`; at plan time `a84445076cd9`), `gh pr view 11592 --json files`, `gh pr list --state open --search "ADR-075 OR landlock OR seccomp-bwrap" --json number,title`. If #9854's ADR has merged: read it; ADR-315 stays `proposed` with the Status line from ruling X ("Topology of record: <ADR for #9854>; this ADR keeps only the option record and measurement gate"), never "superseded". If a PR edits ADR-068 or ADR-075, re-read the changed text before citing it.
3. Re-verify every ledger row (read the file, run the command): re-find the content anchor and update the coordinate; relabel `unverified` only when the cited content is gone or changed; drop a row only when no Decision sentence depends on it.
4. Read `nfr-register.md` and `principles-register.md` (read-only) and pick real IDs for NFR Impacts and Principle Alignment. Candidates seen: NFR-010 (Linear Horizontal Scalability), NFR-038 (Least Privilege Container Images), NFR-009; AP-013, AP-020, AP-021 (a message may only name a cause the job measured). Cite only IDs whose text was read; no register is edited.

### Phase 1 - ADR-315: per-session ephemeral containers

File: `knowledge-base/engineering/architecture/decisions/ADR-315-per-session-ephemeral-containers-recorded-not-adopted.md` (final slug at write time).

```yaml
---
title: Per-session ephemeral containers for hosted agent sessions are recorded, not adopted
status: proposed
date: 2026-11-03
issue: 9602
related: [9602, 9601, 9543, 9842, 9854, 9773, 9859]
related_adrs: [ADR-075, ADR-068, ADR-079, ADR-272, ADR-311, ADR-122, ADR-119, ADR-052, ADR-096]
tags: [sandbox, isolation, containers, agent-runtime, security, capacity]
brand_survival_threshold: single-user incident
---
```

No `adr:`, `amends` or `supersedes` key (ruling M). Body:

- `## Status`: first line verbatim "Proposed. This ADR ships no control. The control in force today is ADR-075 (bwrap per session inside one shared container) plus the current seccomp profile." Then: relates to ADR-075, amends and supersedes nothing; topology of record (amends ADR-068 section 8, Phase 4a wording, and ADR-075 Option B, as #9854's body names it) belongs to #9854; flip semantics per ruling X (requires #9854's merged decision naming containers as the topology, P1-P5 necessary not sufficient, the cost ceiling and the go-ahead are operator-class, `adopting` is a decision to plan not to ship, a first trigger starts measurement and does not flip); "not adopted" is a sequencing decision gated on evidence, not acceptance of the residual risk in ADR-075.
- `## Context`: ledger rows C1-C10; the broker relation (#9543 open, mechanism measured in ADR-311, no broker shipped; ADR-272's per-variable deny is the credential control in force; per-session containers would be a separate layer, interaction `unverified`); a one-clause reason for each of ADR-068, ADR-122, ADR-119, ADR-052, ADR-096, ADR-079 in `related_adrs` (placement and lease routing; delivery and enforcement of container sandbox controls; workspace attach; per-container egress; image pull and warm pool; verification path).
- `## Considered Options`: (1) keep ADR-075 as is: the control in force; (2) per-session ephemeral containers: gated; cons name only costs and dependencies already public (cold start, per-session memory and CPU, image pull and warm pool, session resume across teardown, workspace attach, per-session egress and forwarder lifecycle, interplay with the deploy swap and cron drain of ADR-078) and that it does not close the shared parent-process state unless the SDK loop moves into the container, which depends on #9842's executor protocol (`read from` the #9842 spec Problem Statement at the pinned sha, unmerged); (3) per-tenant long-lived containers: gated with its reason (residue between a tenant's sessions and idle cost against cold start); it is the spec's named enterprise escape hatch (NG1), not a general boundary; (4) a gVisor- or Kata-class sandbox per tenant session: exactly "A gVisor- or Kata-class sandbox per tenant session is the operator-selected direction under epic #9842 (Approach B, Stage 0 spikes pending) and is not decided or shipped by this ADR; its topology decision is reserved to #9854." No option is called rejected here (ruling N forbids it for option 4), so say so in one line.
- `## Decision`: "Not adopted now. Adoption is gated on the measured preconditions below." P1 tenant-count threshold, an estimate: the ruling P wording verbatim plus roadmap row 4.6's "5+ concurrent users"; the numbers are quoted from the brainstorm, #9854 owns the recorded trigger and wins on conflict. P2 cold-start p50 and p95, per-session container versus the baseline arm = the production configuration today (SDK inner bwrap only; the outer wrap is flag-off). P3 memory and CPU per session. P4 maximum concurrent sessions per host with and without. P5 image-pull and warm-pool cost. Every measurement records machine type, kernel, image digest and date and is taken on production-class hardware. P6 (a consistency condition, not a measurement): #9854's merged decision names containers as the topology. Ceilings per ruling X. First triggers: a cross-tenant isolation incident; a bwrap or SDK-sandbox CVE; the issue's own criteria (slice 1 and the credential broker shipped; tenant count making the shared-container blast radius unacceptable), quoted `read from` #9602. No-public-claim clause: at any future adoption, flag creation and legal wording stay operator-class; no public security claim is made or changed ahead of a measured control; the bounded claim in ADR-075 ("per-session process-level filesystem isolation covering both agent tool tiers", never unqualified "tenant isolation") is not widened.
- `## Consequences`, `## Cost Impacts` (no spend now; adoption cost per hosted session `unverified`, driven by P3-P5; baseline facts C3), `## NFR Impacts`, `## Principle Alignment`: real content from Phase 0 step 4.

Claim ledger (label inline in the ADR; AC5 checks the ledger rows):

| # | Claim | Label | Anchor |
|---|---|---|---|
| C1 | Hosted agent sessions run in-process in one multi-tenant container; bwrap is the filesystem isolation between tenants as ADR-075 frames it | read from file:line | ADR-075 `## Context` first paragraph (`ADR-075-agent-sandbox-tenant-read-isolation.md:12-20`) |
| C2 | The prod container mounts one shared host directory at `/workspaces` | read from file:line | `apps/web-platform/infra/ci-deploy.sh`, prod block (`--name soleur-web-platform \` plus `-v /mnt/data/workspaces:/workspaces`; the canary block mounts the same path) |
| C3 | Memory cap defaults: prod 4096m, canary 1536m | read from file:line | `apps/web-platform/infra/ci-deploy.sh:274-275` |
| C4 | Option B exits only with #9773 Stage 1; the interim wrap arm was dropped | read from file:line | ADR-075 addendum "2026-10-09 (#9873 disposition)" |
| C5 | Epic #9842 selects a gVisor sandbox per tenant session; #9854 is the pending record; PR #9832 carries brainstorm and spec only | read from file:line | issue #9842 body; issue #9854 body; spec Goal G1 and operator-decisions paragraph at the pinned sha (spec is stale on arm F) |
| C6 | Tripwires: `active_sessions` alert >=4 sustained; >=~30 concurrent per host or >100 fleet | read from file:line, unverified for sufficiency | `knowledge-base/project/brainstorms/2026-10-08-tenant-executor-topology-brainstorm.md:139` at the pinned sha (unmerged), ruling P wording |
| C7 | Roadmap row 4.6 "Container-per-workspace isolation", gate "5+ concurrent users", #673 | read from file:line | `knowledge-base/product/roadmap.md:341` |
| C8 | The broker mechanism was measured, not shipped | read from file:line | ADR-311 `## Status` ("ships a measurement and a constraint. It ships no broker") |
| C9 | No recorded cold-start, per-session-memory or tenant-count result exists; an `active_sessions` gauge exists but no recorded peak | measured (negative search: command, paths and date written into the ADR; covers apps/web-platform, scripts, .github, knowledge-base) | the P2-P5 gate |
| C10 | The faithful canary replays the SDK's bwrap setup argv against the loaded profile and never reaches `query()`; a topology change needs its own verification path | read from file:line | ADR-079 `--replay` bullet |

### Phase 2 - ADR-316: active Landlock ruleset

File: `knowledge-base/engineering/architecture/decisions/ADR-316-active-landlock-ruleset-beneath-bwrap-recorded-not-adopted.md` (final slug at write time). Frontmatter: `status: proposed`, `date: 2026-11-03`, `supersedes: none`, `issue: 9602`, `related: [9602, 9601, 9543, 9842]`, `related_adrs: [ADR-075, ADR-079, ADR-272, ADR-311, ADR-122]`, `tags: [sandbox, landlock, seccomp, bwrap, security, agent-runtime]`, `brand_survival_threshold: single-user incident`.

- `## Status`: same first line as ADR-315; a layer beneath bwrap, supersedes nothing; flips to `adopting` mechanically when G1-G6 are recorded in a dated amendment with a green canary including the Landlock probe (ruling X); `adopting` is a decision to plan, shipping is a separate PR with the flag off; "not adopted" is not acceptance of residual risk.
- `## Context`: ledger rows L1-L8; what a ruleset could add at ADR-075's granularity (a kernel-enforced second filesystem-access layer that does not depend on mount-argument ordering, which ADR-075's history shows has regressed and is now pinned by the canary: an `unverified` expectation, not a measured benefit); coverage is the Bash tier only: file tools run in the CLI process outside bwrap and stay under ADR-075 and the SDK permissions until the flag-off outer wrap exists; relation to the broker (Landlock does not change credential exposure; ADR-272's deny and the unshipped broker, #9543 and ADR-311, are separate); a one-clause reason for ADR-122 (delivery and enforcement path for a helper and a ruleset policy).
- `## Considered Options`: (A) keep bwrap, seccomp and AppArmor as they are: the control in force; (B) a ruleset applied inside the sandboxed child after the mount table is built and before exec of the command (the position the vendored apply-seccomp multicall occupies), by a small helper: gated; applying it earlier, in the bwrap PATH shim or in the outer-wrap spawn (which execs the real bwrap directly and bypasses the shim), is expected to interfere with bwrap's own mount setup (`unverified`, upstream docs), and the outage class is documented (ADR-075 2026-10-16 addendum), so those placements are not candidates; (C) a ruleset applied in the shared server process: not adopted, because `landlock_restrict_self` is irreversible for the calling thread (`unverified`, upstream kernel behaviour) so it would confine the process serving every tenant; (D) an existing Landlock-plus-seccomp sandbox (NVIDIA OpenShell, the `sandlock` OCI shim): candidates only, "README-level, unverified, from the #9842 spec", with the spec's own note ("expected to be a weaker boundary") quoted as read, not endorsed; no CVE text.
- `## Decision`: "Not adopted now. Adoption is gated on the measured preconditions below." Gate (a spike, 3-5 days, an estimate read from #9602's body): G1 kernel and privilege prerequisites for the call, and Landlock ABI support (minimum ABI version the intended rule set needs and available access rights), measured on the production host and in the runner container (`unverified` until measured); G2 the ruleset is applied in the child after mount-table construction and before exec, and is shown not to confine the shared server process; G3 the faithful canary stays green, extended by a Landlock hardening probe among the derived probes, replay argv unchanged; G4 a positive control (the ruleset visibly denies an access class the current bwrap configuration allows, named at ADR-075 granularity with no gap enumeration); G5 a real SDK Bash smoke (the hosted-Bash outage class); G6 on a kernel or ABI lacking the needed rights the child degrades to bwrap-only and emits a Sentry-mirrored signal (a silent skip and a fail-closed Bash outage both fail the gate). Ownership (ruling Q) verbatim: kernel-ABI support is "measured once, in whichever of this ADR's gate or a #9842 spike runs first; the other cites the result"; no separate spike is scheduled; if a #9842 S-spike already covers Landlock this ADR cites it and drops G1. Tracker #9602. No-public-claim clause as in ADR-315.
- `## Consequences`, `## Cost Impacts` (spike effort estimate, no recurring cost; a helper binary adds a maintained image artifact, `unverified`), `## NFR Impacts`, `## Principle Alignment`: real content.

| # | Claim | Label | Anchor |
|---|---|---|---|
| L1 | The profile allows the three Landlock syscalls in its unconditional allow block; default action is deny-with-errno | read from file:line | `apps/web-platform/infra/seccomp-bwrap.json:194-196` (`landlock_add_rule`, `landlock_create_ruleset`, `landlock_restrict_self`), `:2` (`defaultAction`), `:422` |
| L2 | No Landlock ruleset is configured anywhere in the repo's code | measured (negative search: `git grep -il landlock origin/main -- apps plugins scripts .github`, scope and date written into the ADR) | profile and `apps/web-platform/infra/test-fixtures/sandbox-canary/seccomp-pre-5874.json` are the only hits |
| L3 | `landlock_restrict_self` is irreversible for the calling thread and inherited by children | unverified | upstream kernel documentation, not measured here |
| L4 | The SDK spawns a PATH-resolved bwrap wrapped by a shim; the outer-wrap spawn execs the real bwrap and bypasses the shim; the outer wrap is flag-off on the shared prod container | read from file:line | ADR-075 addenda "2026-10-06 (#8752)" and "2026-10-09 (#9873 disposition)"; shim header; `agent-outer-wrap.ts` (`makeSandboxedSpawn`) |
| L5 | The faithful canary replays the captured setup argv and never reaches `query()`; a command-side Landlock step is outside it | read from file:line | ADR-079 `--replay` bullet |
| L6 | AppArmor profile `soleur-bwrap` is attached to the prod container; its interplay with Landlock is not known | read from file:line / unverified (interplay) | `apps/web-platform/infra/apparmor-soleur-bwrap.profile`; `ci-deploy.sh` prod block |
| L7 | OpenShell and `sandlock` use Landlock with seccomp | unverified (README-level, from the #9842 spec) | spec rows "Egress + credential injection" and "Weaker-boundary comparison" at the pinned sha |
| L8 | An inferred twelve-day hosted-Bash outage (about ten days to detect) followed a seccomp filter change | read from file:line | ADR-075 addendum "2026-10-16 (#10445)" and its PIR `knowledge-base/engineering/operations/post-mortems/hosted-agent-bash-apply-seccomp-userns-eperm-postmortem.md` |

Disclosure rules for both ADRs: residual risk only in terms ADR-075 and ADR-272 already publish; no step sequence for crossing a boundary, no enumeration of hardening settings the run tuple lacks, no unpatched-CVE detail, no CVE identifier, no tenant identifiers; "not adopted" is always paired with "not acceptance of the residual risk". The ADR text cites no plan or spec path of this feature (both get archived).

### Phase 3 - Verification on the final tree

Run each; paste exit codes into the PR body. Preflight Check 4 reads Doppler and is skipped; say so in the PR body. If a repo-global gate is non-zero, re-run it at a detached `origin/main` before attributing it to this diff.

1. `bash scripts/markdown-lint.sh knowledge-base/engineering/architecture/decisions/ADR-315-*.md knowledge-base/engineering/architecture/decisions/ADR-316-*.md` (`knowledge-base/project/` is excluded by `.markdownlintignore`).
2. `bash scripts/check-adr-ordinals.sh` (ordinals and the no-`adr:`-key layer; headings of new ADRs are verified by AC4).
   Also `python3 scripts/lint-infra-no-human-steps.py` on both ADRs, this plan and the spec files: it flags a human-role word on or next to a line holding an infrastructure-imperative word, so ADR prose about the sandbox filesystem view must avoid that pairing (the plan phase hit it twice).
3. `bash scripts/test-affected-kb-consumers.test.sh` (baseline via `--write-baseline` only if a test pairs with a new file; none expected).
4. `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/guard-vacuity-floor.test.sh`, `bash plugins/soleur/test/fixture-relative-assert.test.sh`, `bash scripts/always-on-ledger.test.sh`.
5. The stale-ghs census: `bash scripts/lint-shell-trace-credential-refusal.test.sh`.
6. `bash plugins/soleur/test/c4-count-parity.test.sh` (evidence for "no C4 impact").
7. Not run, one line each: `_MIN_ALWAYS_ON_DECLARED` in `scripts/test-all.sh` and row f1 in `scripts/test-all-affected.test.sh` (no suite added); `plugins/soleur/test/merge-effect-class-parity.test.sh` (no workflow added).
8. Vocabulary check against `knowledge-base/project/glossary.md`: "Runner" (the bwrap surface; "sandbox" names the bwrap surface specifically), "session" (a runner-context, not the unit of work), and the avoid-list ("server", "host", "box" name infrastructure). The ADRs use "hosted agent session" for the SDK conversation, "sandbox" only for the bwrap surface, "container" for the Docker container and "host" for the Hetzner machine, and say which sense each time a word could read two ways; no glossary entry exists for tenant, broker, canary, ephemeral or container, so each is hedged on first use ("ephemeral = created for one session and destroyed when it ends").
9. `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` (exit 0).
10. After any ordinal bump, merge of origin/main or archive commit: re-run the Phase 0 step 1 census and steps 1, 2, 3, 6 here plus AC1 and AC2 (a bump renames the files, so earlier green runs no longer cover them); re-check #9854, PR #9832 and PR #11592 state. Run AC1 against the archive paths, and `grep -rn 'specs/feat-one-shot-9602\|plans/2026-11-03-feat-adrs' scripts plugins .github` for live-path consumers.

### Phase 4 - Commit, ship, post-merge

1. Commit exact paths: the two ADRs, plan, tasks.md, decision-challenges.md, session-state.md. Never a directory add of `plans/`. Compound runs at ship with no learning file for a clean session and all promotions Skip (ruling W).
2. Review: user-impact-reviewer and security-sentinel on the ADR text; resolve or rule findings. Record in the PR body that plan-review and deepen-plan ran.
3. PR body: `Ref #9602`, `Ref #9601`, the overlap with PR #9832 and #9854, "Preflight Check 4 skipped: it reads Doppler", "Net issue flow: 0 filed, 0 closed", and a line saying the ADRs are discoverable from ADR-075 only through the new ADRs' `related_adrs`, this PR and the #9602 comment (ruling I). No `Closes`.

#### Post-merge (automated with the gh CLI at ship)

`gh issue comment 9602` with the two ADR links (by filename) and the remaining criterion (each ADR's `proposed` to `adopting` gate per ruling X); leave #9602 open; do not close #9601 or tick any epic checklist item without cited evidence.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-315-per-session-ephemeral-containers-recorded-not-adopted.md`
- `knowledge-base/engineering/architecture/decisions/ADR-316-active-landlock-ruleset-beneath-bwrap-recorded-not-adopted.md`
- `knowledge-base/project/specs/feat-one-shot-9602-adr-ephemeral-containers-landlock/{tasks.md,decision-challenges.md,session-state.md}` (the last three are created by the plan phase)
- this plan file

## Files to Edit

None. Explicitly not edited: `model.c4`, `model.likec4.json`, `nfr-register.md`, `domain-model.md`, the body or frontmatter of ADR-075, any `.tf` file, anything under apps/, .github/, docs/legal/ or plugins/soleur/docs/, toggle copy, flag configuration, `knowledge-base/product/roadmap.md`.

## Open Code-Review Overlap

None: open `code-review` issues were searched for `ADR-075`, `apps/web-platform/infra/seccomp-bwrap.json`, `ADR-315` and `ADR-316`; no matches. No code file is edited.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

Deterministic over the final tree merged with a fresh `origin/main`. `N1` and `N2` are the two actual ordinals; `DEC=knowledge-base/engineering/architecture/decisions`.

- [ ] AC1 diff scope: with `RE='^('"$DEC"'/ADR-(N1|N2)-[a-z0-9-]+\.md|knowledge-base/project/specs/(archive/[0-9]{8}-[0-9]{6}-)?feat-one-shot-9602-adr-ephemeral-containers-landlock/[A-Za-z0-9._-]+|knowledge-base/project/plans/(archive/[0-9]{8}-[0-9]{6}-)?2026-11-03-feat-adrs-ephemeral-containers-landlock-plan\.md)$'` (plus the single learning path if ruling W fired), `git diff --name-only origin/main...HEAD | grep -v -E "$RE"` prints nothing and `git diff --name-only origin/main...HEAD | grep -c "$DEC/ADR-"` prints `2`. Negative control: `printf 'apps/web-platform/x.ts\ndocs/legal/x.md\nplugins/soleur/docs/x.md\n.github/workflows/x.yml\napps/web-platform/infra/x.tf\n'"$DEC"'/ADR-075-x.md\n'"$DEC"'/ADR-313-x.md\n' | grep -v -E "$RE" | wc -l` prints `7`.
- [ ] AC2 ordinals: `bash scripts/check-adr-ordinals.sh` exits 0; `[ "$(ls $DEC/ADR-N1-*.md $DEC/ADR-N2-*.md | wc -l)" -eq 2 ]`; `grep -c '^adr:' <each file>` prints 0. (That the ordinals exceed every open PR's claim is Phase 0 step 1 and Phase 3 step 10, a procedure: other PRs can claim ordinals without a line of this diff changing.)
- [ ] AC3 status and decision form: per file, `grep -c '^status: proposed$'` is 1; `awk '/^## Status$/{f=1;next} f&&NF{print;exit}' <file> | grep -c -F 'Proposed. This ADR ships no control. The control in force today is ADR-075 (bwrap per session inside one shared container) plus the current seccomp profile.'` is 1; frontmatter has no `adopting` (`sed -n '1,/^---$/p' <file> | grep -ci adopting` is 0); ADR-315 has no `amends:` or `supersedes:` key (`sed -n '1,/^---$/p' <file> | grep -cE '^(amends|supersedes):'` is 0); `grep -c -F 'Not adopted now. Adoption is gated on the measured preconditions below.'` is 1.
- [ ] AC4 headings and shape: each file has the level-2 headings Status, Context, Considered Options, Decision, Consequences, Cost Impacts, NFR Impacts, Principle Alignment in that order (`grep -n '^## ' <file>`), no Diagram section, and no section whose whole body is "None"; hand-verified because the repo gate does not check headings on new ADRs.
- [ ] AC5 labelling: in each ADR the claim-ledger rows are present and each carries a label: `awk -F'|' '/^\| [CL][0-9]+ /{print $4}' <file> | grep -c -E '^ *(measured|read from|unverified)'` equals `grep -c -E '^\| [CL][0-9]+ ' <file>` (10 for ADR-315, 8 for ADR-316); and by hand every Context and Decision sentence carrying a number, a path or a factual claim about the system has a label (review reads this, AC12).
- [ ] AC6 disclosure: `grep -c -i -E 'CVE[- ]?[0-9]{4}|GHSA-' <each file>` prints 0; no exploit recipe, boundary-crossing step sequence, hardening-setting enumeration or unpatched-CVE description (security-sentinel reports no disclosure finding).
- [ ] AC7 required content: per ADR, `grep -c '#9543'` and `grep -c 'ADR-311'` are at least 1; both carry the no-public-claim clause of ruling F; ADR-316 Considered Options states the ruleset is applied "in the sandboxed child" after mount-table construction and before exec and "not in the shared server process"; ADR-315 option 4 carries the exact ruling N sentence (awk-extract the paragraph from "gVisor- or Kata-class" to the next blank line: at least 1 line, and `grep -ciE '\b(rejected|adopted|planned)\b'` on it prints 0); ADR-315 names #9842, #9854, #9773 and PR #9832 with topology reserved to #9854.
- [ ] AC8 keywords and issue flow: PR title and every commit message and the PR body use `Ref #9602` and `Ref #9601` and match no `-iE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\b #?[0-9]'` form; the egress-audit enablement and broker-enablement issue numbers, resolved at check time (`gh issue list --state open --search 'egress audit enablement' --json number --jq '[.[].number]|join("|")'`, the broker-enablement issue the same way; both exclude 9543 and 9601; assert the joined list is non-empty), are absent from the diff: `git diff origin/main...HEAD | grep -n -E "#(<joined>)\b"` prints nothing (the numbers are deliberately not written into this plan, which is part of the diff); `bash plugins/soleur/skills/ship/scripts/net-issue-flow.sh 11935` stdout shows `Filing:  0` on the no-stop path (on the ruling AA stop path `Filing:  1` and the PR stays draft); the PR body states "Net issue flow: 0 filed, 0 closed" accordingly.
- [ ] AC9 no new personal-data claim (ruling R): neither ADR introduces a retention period, a data category or a tenant identifier beyond what ADR-075 and ADR-272 already state (reviewed against both); if one cannot be traced or removed, stop and follow ruling AA with `soleur:legal:clo` named as owner.
- [ ] AC10 flip semantics present: ADR-315 Status carries the ruling X conditions (requires #9854's merged decision; P1-P5 necessary not sufficient; cost ceiling and go-ahead operator-class; a decision to plan not to ship); ADR-316 Status carries G1-G6 plus the green-canary-with-Landlock-probe condition; every measurement in P2-P5 and G1-G6 states the measurement, machine record and where the result is recorded (P1 is an estimate and P6 a consistency condition and are exempt).
- [ ] AC11 gates: Phase 3 steps 1-6 and 9 exit 0 with output pasted (a non-zero repo-global gate is first re-run at a detached `origin/main`); `c4-count-parity` evidence pasted.
- [ ] AC12 review: soleur:engineering:review:user-impact-reviewer and soleur:engineering:review:security-sentinel both ran on the ADR text and their findings are resolved or ruled.

## Test Scenarios

No code is added and no suite may cite the new files (kb-consumers baseline); verification is AC1-AC12 and Phase 3. Regression class: two open PRs already collided on ADR-314, so the Phase 0 census lists every claim before the ordinals are chosen.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO agent ruled structure, status, ordinals, content, gate shape and registrations (rows A-L), the overlap with epic #9842 and #9854 (M-Q), the skill-gate deviations (R-V) and the plan-review forks (W-AA) in decision-challenges.md. Plan-review panel (dhh, kieran, code-simplicity, architecture-strategist, spec-flow-analyzer) and a sharp-edges verification pass ran; mechanical findings are applied above. No CLO, CPO or CMO consult is needed while the diff stays in ADR-only scope. Product/UX gate: NONE (no user-facing surface).

## Non-Goals (documented in place, no issues filed)

- Implementing per-session containers or a Landlock ruleset, or changing any runtime, profile, flag, copy or legal text.
- Scheduling the Landlock spike or the container measurements (named inside the ADRs, tracker #9602).
- Deciding the executor topology or the gVisor/Kata runtime (reserved to #9854 and #9842).
- Editing ADR-075, the C4 model, the NFR register, the principles register or the domain model.

## Dependencies and Risks

- **Scope overlap with #9842 / #9854:** relates-only record, #9854 wins on topology; if #9854 merges first the ADR stays `proposed` with the topology-of-record Status line (Phase 0 step 2, re-checked at Phase 3 step 10).
- **Ordinal collision:** a third claimant may take 315 or 316; recompute (Phase 0 step 1).
- **Unverified claims read as facts:** Landlock ABI support, carrier feasibility and all container cost numbers are `unverified` by construction; the labels are the control and the user-impact-reviewer checks them.
- **Disclosure:** the repo is public; security-sentinel reads the ADR text at that level. Citations to the unmerged `feat-tenant-executor-topology` branch are pinned to a sha and the numbers are quoted verbatim in the ADR so it stays self-contained if the branch moves.
- **Foreign `test-all.sh` processes** from another worktree were reported by the collision pre-check; they touch nothing in this scope.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only unfilled text, or omits the threshold fails `deepen-plan` Phase 4.6; this one names four concrete failure modes and the threshold.
- Do not write the standing constraints as hold or gate marker lines, or as `Operator-reserved:` lines under an `Operator Holds` heading: the hold evaluator exits 2 on those (ruling A). `hold-gate-eval.sh --plan` on this file reports 0 holds, exit 0.
- Do not write `Closes #9602`: it would close the issue whose remaining criterion (the proposed to adopting gate) is open.
- Do not copy the third-party CVE mention from the archived three-layers brainstorm into either ADR.
- A renumber sweep covers this plan, tasks.md and decision-challenges.md (they name the ordinals), not only the ADR files.
