---
title: An active Landlock ruleset beneath bwrap is recorded, not adopted
status: proposed
date: 2026-11-03
supersedes: none
issue: 9602
related: [9602, 9601, 9543, 9842]
related_adrs: [ADR-075, ADR-079, ADR-272, ADR-311, ADR-122]
tags: [sandbox, landlock, seccomp, bwrap, security, agent-runtime]
brand_survival_threshold: single-user incident
---

# ADR-316: An active Landlock ruleset beneath bwrap is recorded, not adopted

## Status

Proposed. This ADR ships no control. The control in force today is ADR-075 (bwrap per session inside one shared container) plus the current seccomp profile.

- Coverage of that control is the Bash tier.
  File tools run outside bwrap under the SDK permissions, as ADR-075 records (label: read from ADR-075 :221, addendum "2026-10-08 (#5863)", anchor "the file tools run in the CLI process itself").
  A ruleset applied beneath bwrap would have the same Bash-tier coverage and nothing wider.
- The option recorded here is a layer beneath bwrap.
  It supersedes nothing: bwrap, seccomp and AppArmor stay as they are.
- Flip to `adopting` happens mechanically when the six gate measurements G1 to G6 in the Decision section are recorded in a dated amendment, together with a green faithful canary that includes the Landlock probe.
  No money or topology decision is involved in that flip.
- `adopting` is a decision to plan, not to ship: shipping is a separate PR with the flag off.
- "Not adopted" is a sequencing decision gated on evidence. It is not acceptance of the residual risk in ADR-075.
- Residual-risk owner: ADR-075. This ADR neither closes nor accepts that risk.

Labels. Every factual claim in this ADR is labelled `measured`, `read from <file>` (with a content anchor, and the line coordinate where it helps a reader) or `unverified`.
Sources were re-read at origin/main 873659816f on 2026-11-03.
Claims from an issue body are mutable and carry the read date.
Claims about how Landlock behaves come from the upstream kernel documentation at <https://docs.kernel.org/userspace-api/landlock.html>.
They are `unverified` here because none of them was measured in this repository.

## Context

Terms, because the glossary does not define them.
A hosted agent session is one tenant's agent conversation run by the SDK.
"Sandbox" names only the bwrap surface. "Container" is the Docker container. "Host" is the Hetzner machine.
"Landlock" is a Linux kernel facility that lets a process restrict its own access to files (and, in later ABI versions, other resources) by installing a ruleset (label: unverified, upstream documentation).
"Broker" means the credential broker (#9543), which is not shipped. "Canary" means the faithful canary of ADR-079.

The rows below are the claims this ADR rests on; each carries one label.

| # | Claim | Label | Anchor |
|---|---|---|---|
| L1 | The current seccomp profile already permits the three Landlock syscalls | read from apps/web-platform/infra/seccomp-bwrap.json, anchor "landlock_create_ruleset" (the profile's default action is to return an error, and the three names are listed together in its allow list) | the allow-list entry containing `landlock_add_rule`, `landlock_create_ruleset` and `landlock_restrict_self`; cited by content anchor and not by line |
| L2 | No Landlock ruleset is configured by this repository's source | measured (absence in scope: `git grep -il landlock origin/main -- apps plugins scripts .github`, paths apps, plugins, scripts and .github, 2026-11-03; two hits); whether the SDK, the image or the host applies one is unverified | the only hits are the seccomp profile above and the pre-fix canary profile fixture `apps/web-platform/infra/test-fixtures/sandbox-canary/seccomp-pre-5874.json` |
| L3 | Restriction applies per calling thread by default, cannot be undone, and is inherited by children created later (persistence across exec is inferred, not stated) | unverified | upstream kernel documentation, not measured here |
| L4 | The SDK spawns a PATH-resolved bwrap, wrapped by a shim; the outer wrap is flag-off on the shared production container | read from file:line | ADR-075-agent-sandbox-tenant-read-isolation.md:93 (addendum "2026-10-06 (#8752)", anchor "`infra/bwrap-shim/bwrap` PATH shim") and :281 (addendum "2026-10-09 (#9873 disposition)", anchor "stays flag-off on the shared prod container") |
| L5 | The faithful canary replays the captured setup argv and never reaches `query()`; a Landlock probe would be added among its derived probes (G3) | read from file:line | ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md:120-124, anchor "it never reaches `query()`"; ADR-075 :102, anchor "four derived probes" |
| L6 | How Landlock interacts with the AppArmor profile attached to the container is not known | unverified | not measured here |
| L7 | Existing sandboxes named in the #9842 work (NVIDIA OpenShell, the `sandlock` OCI shim) pair Landlock with seccomp | unverified (mutable source: an unmerged spec document carried by PR #9832, README-level claims, 2026-11-03) | the #9842 spec as carried by PR #9832; no text is quoted here and the epic's own issue body does not name either project |
| L8 | A prior seccomp profile change caused a multi-day hosted-Bash outage | read from file:line | ADR-075-agent-sandbox-tenant-read-isolation.md:416 and :423-424 (addendum "2026-10-16 (#10445)", anchor "every hosted Bash call failed") and its post-incident report knowledge-base/engineering/operations/post-mortems/hosted-agent-bash-apply-seccomp-userns-eperm-postmortem.md |
| L9 | A thread restricted on filesystem access cannot change filesystem topology (the mount and root-switch system calls), so any placement earlier than the sandbox's own setup is expected to interfere | unverified | upstream kernel documentation, section on filesystem topology modification; not measured here |
| L10 | The ABI is queried with the version flag of `landlock_create_ruleset`; an unprivileged caller needs `no_new_privs` (or CAP_SYS_ADMIN in its namespace); ENOSYS means Landlock is absent and EOPNOTSUPP means it is present but disabled at boot | unverified | upstream kernel documentation, not measured here |

What a ruleset could add, at the granularity ADR-075 already publishes.
bwrap is the only filesystem isolation between tenants in the shared container (read from ADR-075 :17-18, anchor "bwrap is the only filesystem isolation between tenants").
A ruleset would be a kernel-enforced second layer of filesystem access control that does not depend on the order in which the sandbox arguments are built.
ADR-075's history shows that ordering has regressed once (read from ADR-075 :22-30, anchor "#5848 thereby converted").
It is now pinned by a canary test (read from ADR-075 :134, anchor "every covering `--tmpfs` precedes an rw `--bind` restore").
That the extra layer would catch anything the existing layers miss is an `unverified` expectation, not a measured benefit, and this ADR enumerates no gap.

Coverage.
The layer would cover the Bash tier only, as stated in Status.
File tools stay under ADR-075 and the SDK permissions.

Relation to the credential broker.
Landlock does not change credential exposure.
ADR-272's deny of the Anthropic auth variables and the unshipped broker (#9543, ADR-311) are separate controls.
#9543 is open and no broker is shipped; ADR-311 records that only the mechanism was measured (read from ADR-311-credential-broker-mechanism-measured-before-built.md:17, anchor "It ships no broker").

Relation to epic #9842.
The epic's executor work is separate from this option.
Whether #9842 includes a spike that covers Landlock is addressed under ownership in the Decision section.

### Relations (informational; none implies a dependency, a shipped control or adoption)

- ADR-075: the control in force and the owner of the residual risk (L4, L8).
- ADR-079: the faithful canary whose derived probes would carry the Landlock probe (L5).
- ADR-272: the credential deny for sandboxed Bash; a separate control that a ruleset does not change.
- ADR-311: "broker not shipped; mechanism measured only".
- ADR-122: the delivery and enforcement path for container sandbox controls; a helper and a ruleset policy would need a delivery path of the same kind (label: unverified).

## Considered Options

Dispositions below use "the control in force", "evaluated", "not evaluated" and "not adopted", each with its reason.

Option A, keep bwrap, seccomp and AppArmor as they are.
This is the control in force (L1, L4).
Pros: it exists, the faithful canary verifies it (L5), and it adds no new artifact.
Cons: it is the shape whose residual risk ADR-075 records and owns.
Disposition: the control in force.

Option B, a ruleset applied in the sandboxed child, after the sandbox view is built and before exec of the command, by a small helper.
This is the position the vendored apply-seccomp helper holds in the SDK's wrapper chain when it runs: it wraps the command the sandbox executes (read from ADR-075 :423-424, anchor "wraps **every** sandboxed command in that helper").
The same addendum records that the builder skips the helper under the configuration it sets (anchor "Skipping seccomp filter").
Evaluated only if the gate conditions below are met; no commitment to proceed.
Pros: the ruleset confines only the sandboxed command and not the process around it (label: unverified, L3).
Cons: a new maintained helper artifact; a new failure mode for hosted Bash; kernel and ABI dependence (L10).
Earlier placements, including the existing spawn wrappers, are not candidates, for two reasons.

- Upstream documentation states that a restricted thread cannot modify filesystem topology (L9), so an earlier placement is expected to interfere with the sandbox's own setup (unverified, not measured here).
- A prior seccomp profile change caused a multi-day hosted-Bash outage (L8), which is a reason to keep any new layer out of the setup path.

Option C, a ruleset applied in the shared server process.
Not adopted, because restriction is irreversible for the calling thread (L3, unverified, upstream documentation), so it would confine the process serving every tenant.
The ruleset must be applied in the sandboxed child, not in the shared server process.

Option D, an existing sandbox that pairs Landlock with seccomp (NVIDIA OpenShell, the `sandlock` OCI shim).
These are candidates named in the #9842 spec; capabilities unverified here; not evaluated by this ADR (L7).
No comparison is quoted and no claim about either project is made.

## Decision

Not adopted now. Adoption is gated on the measured preconditions below.

This is a sequencing decision gated on evidence.
It is not acceptance of the residual risk in ADR-075.
Residual-risk owner: ADR-075; this ADR neither closes nor accepts that risk.

The gate is a spike.
Its size is 3 to 5 days, an estimate read from the #9602 issue body, which says the repo audit sized Landlock at that range (label: unverified, mutable source: issue body, 2026-11-03).
The 3-5 day figure and everything in this section are internal tripwires and estimates, not a commitment, a schedule or a statement that risk below them is acceptable.

Each measurement below records the machine class, the Landlock ABI number and the date in the public amendment.
The exact kernel release and the image digest live in a private measurement record, cited from the amendment by an opaque id.
That private record must exist before the amendment merges, or the gate fails.

- G1, kernel and privilege prerequisites for the call, and Landlock ABI support.
  Measure the unprivileged-caller prerequisite, the distinction between "absent" and "present but disabled at boot", and the minimum ABI number the intended rule set needs (L10).
  Measure it on the production host and inside the container. Unverified until measured.
- G2, placement.
  The ruleset is applied in the child after the sandbox view is built and before exec of the command.
  The measurement shows that the shared server process is not confined by it (L3, L9).
- G3, the faithful canary stays green.
  The canary is extended by a Landlock hardening probe among its derived probes, and the replay argv is unchanged (L5).
- G4, a positive control.
  An access the ruleset denies fails inside the child and succeeds in a control child without the ruleset; the access class is chosen at the spike and recorded in its amendment, not in this ADR.
- G5, a real SDK Bash smoke.
  This is the hosted-Bash outage class (L8), so the existing Bash smoke recorded in ADR-079 (read from ADR-079 :700, anchor "`run_sdk_bash_smoke` in `ci-deploy.sh`") must pass with the layer present.
- G6, degrade and signal.
  On a kernel or ABI that lacks the needed rights, the child degrades to bwrap-only and emits a signal mirrored to Sentry.
  A silent skip and a fail-closed Bash outage both fail the gate.

Ownership.
Kernel-ABI support is "measured once, in whichever of this ADR's gate or a #9842 spike runs first; the other cites the result".
No separate spike is scheduled.
If a #9842 spike already covers Landlock, this ADR cites it and drops G1.
Measured absence at the time of writing: `gh issue view 9842 --json body --jq .body | grep -ci landlock` printed 0 on 2026-11-03.
Scope: the epic's issue body only. The child spike issues were not searched, and whether any of them covers Landlock is unverified.

Tracker: #9602, which stays open.

No public claim.
At any future adoption, flag creation and legal wording stay operator-class.
No public security claim is made or changed ahead of a measured control, and no claim wider than ADR-075 states is made or implied.
Any future layer would be conditional on kernel support, and no claim is made that it is always active or covers every session.

## Consequences

- Positive: the option, where it must be applied, and what must be measured before it is planned are recorded, so the spike is scoped once and not twice.
- Positive: nothing runs differently after this ADR merges. The control in force and its residual risk are exactly as ADR-075 records them.
- Negative: a record titled for a ruleset can be read as a control that exists.
  The Status line, the paired "not acceptance of the residual risk in ADR-075" sentence and the no-public-claim clause exist to prevent that.
  A security answer should cite ADR-075 and not this ADR.
- Negative: if adopted later, the layer would add a maintained helper artifact and a new failure mode on the hosted-Bash path (L8), which is why G5 and G6 are gates and not follow-ups.
- Neutral: the layer would be conditional on kernel support by construction (L10), so even after adoption it would not cover every session, and no claim of universal coverage may be made.
- Risk: Landlock behaviour here is taken from upstream documentation only (L3, L9, L10).
  Each such claim is `unverified` until G1 to G4 are measured, and no work should be scoped on one of them as if it were fact.

## Cost Impacts

No recurring cost.
The spike has an effort estimate of 3 to 5 days (unverified, read from the issue body).
A helper binary would add one maintained image artifact (unverified until the spike).
No vendor spend is involved.

## NFR Impacts

- NFR-038 (Least Privilege Container Images): the register records the Agent Runtime as Partial.
  A ruleset beneath bwrap would add a least-privilege layer for the Bash tier if adopted (label: unverified); nothing in this ADR changes the current rating, and the register is not edited.
  No other NFR row changes tier.

## Principle Alignment

- AP-011 (ADRs for architecture decisions): Aligned.
  A deferred architecture-scale option gets a decision record with a measurement gate and a named placement.
- AP-021 (Diagnostic honesty): Aligned.
  Every claim is labelled measured, read from a file or unverified; negative searches carry their command, paths and date (L2, and the ownership search).
  G6 requires that a skipped layer produce a signal and not a silent skip, so a message about the layer can name only what the job measured.
