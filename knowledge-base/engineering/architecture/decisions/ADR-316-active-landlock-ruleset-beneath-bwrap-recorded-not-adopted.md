---
title: An active Landlock ruleset beneath bwrap is recorded, not adopted
status: proposed
date: 2026-11-03
supersedes: none
issue: 9602
related: [9602, 9601, 9543, 9842, 9859]
related_adrs: [ADR-075, ADR-079, ADR-272, ADR-311, ADR-122]
tags: [sandbox, landlock, seccomp, bwrap, security, agent-runtime]
brand_survival_threshold: single-user incident
---

# ADR-316: An active Landlock ruleset beneath bwrap is recorded, not adopted

## Status

Proposed. This ADR ships no control. The control in force today is ADR-075 (bwrap sandboxing of Bash commands inside one shared container, with the seccomp controls ADR-075 records and the AppArmor profile ADR-122 records). As of 2026-11-03; if this ADR disagrees with ADR-075 or ADR-122 on the control in force, those ADRs govern.

- Coverage of that control is the Bash tier.
  File tools run in the CLI process outside bwrap; their containment is the `createSandboxHook` realpath hook (label: read from ADR-075, addendum "2026-10-08 (#5863)", anchor "the file tools run in the CLI process itself"; opening-paragraph anchor "realpath-containment covers file-tools"), and the residuals ADR-075 records for that tier stay open there (anchor "stays open **for the wrapped-CLI tier specifically**").
  A ruleset applied beneath bwrap would have the same Bash-tier coverage and nothing wider.
- The option recorded here is a layer beneath bwrap.
  It supersedes nothing: bwrap, seccomp and AppArmor stay as they are.
- Flip to `adopting` is made only when every one of the six gates G1 to G6 in the Decision section is recorded as MET in a dated amendment, together with G3 (the faithful canary green with the Landlock probe, run per the spike-branch rule in the Decision section).
  A recorded miss leaves the status `proposed`. A green canary is necessary and not sufficient: the prior hosted-Bash outage ran with the canary green (L8; the post-incident report records that the canary was green during the outage).
  The dated amendment names the ADR-075 residual its measurements address, citing the ADR-075 anchor. An amendment that names none leaves the status `proposed`.
  The flip is made by the PR that adds the dated amendment, authored by the engineering owner of #9602, and is reviewed by a second reviewer other than the author (a person, or a separate review pass recorded in the PR) who confirms each gate's recorded result against the private measurement record, including that the record exists by its opaque id. No money or topology decision is involved in that flip.
- `adopting` is a decision to plan, not to ship: shipping is a separate PR with the flag off.
- "Not adopted" is a sequencing decision gated on evidence. It is not acceptance of the residual risk in ADR-075.
- Residual-risk owner: ADR-075. This ADR neither closes nor accepts that risk.

Labels. Every claim about the system in the ledger rows below, and every claim marked in the text, is labelled `measured`, `read from <file>` (with a content anchor, and the line coordinate where it helps a reader) or `unverified`; option descriptions, pros and cons are unlabelled prose unless marked.
Sources were re-read at origin/main on 2026-11-03.
Claims from an issue body are mutable and carry the read date.
Claims about how Landlock behaves come from the upstream kernel documentation at <https://docs.kernel.org/userspace-api/landlock.html>.
They are `unverified` here because none of them was measured in this repository.

## Context

Driver, at ADR-075's published granularity: the open residuals named in ADR-075's 2026-10-09 addendum (#9873 disposition, anchor "The open residual") and the ordering dependence recorded under "What a ruleset could add" below. The expectation that this option would close any of them is unverified, and the amendment must say which residual its measurements address.

Terms (glossary.md pins "sandbox" to the bwrap surface; its Run and Runner entries reserve "session" and "host" for other meanings, so this ADR defines them locally below).
A hosted agent session is one tenant's agent conversation run by the SDK.
"Sandbox" names the bwrap surface; where an external project's sandbox is meant the text says so. "Container" is the Docker container. "Host" is the Hetzner machine.
"Landlock" is a Linux kernel facility that lets a process restrict its own access to files (and, in later ABI versions, other resources) by installing a ruleset (label: unverified, upstream documentation).
"Broker" means the credential broker (#9543), which is not shipped. "Canary" means the faithful canary of ADR-079.
"Session" here means the hosted agent session; ADR-075's per-sandboxed-command wording is not restated and no sandbox instances are counted here.

The rows below are the claims this ADR rests on; each carries one label.

| # | Claim | Label | Anchor |
|---|---|---|---|
| L1 | The current seccomp profile already permits the three Landlock syscalls | read from file | apps/web-platform/infra/seccomp-bwrap.json, anchor "landlock_create_ruleset": the allow-list entry containing `landlock_add_rule`, `landlock_create_ruleset` and `landlock_restrict_self`; cited by content anchor and not by line |
| L2 | No Landlock ruleset is configured by this repository's source | measured (absence in scope: `git grep -il landlock origin/main -- apps plugins scripts .github`, paths apps, plugins, scripts and .github, 2026-11-03; two hits); whether the SDK, the image or the host applies one is unverified | the only hits are the seccomp profile above and the pre-fix canary profile fixture `apps/web-platform/infra/test-fixtures/sandbox-canary/seccomp-pre-5874.json` |
| L3 | Restriction applies per calling thread by default, cannot be undone, and is inherited by children created later (persistence across exec is inferred, not stated) | unverified | upstream kernel documentation, not measured here |
| L4a | The SDK spawns a PATH-resolved bwrap, wrapped by a shim | read from file | ADR-075-agent-sandbox-tenant-read-isolation.md:93 (addendum "2026-10-06 (#8752)", anchor "`infra/bwrap-shim/bwrap` PATH shim") |
| L4b | The outer wrap is flag-off on the shared production container | read from file | ADR-075-agent-sandbox-tenant-read-isolation.md:281 (addendum "2026-10-09 (#9873 disposition)", anchor "stays flag-off on the shared prod container") |
| L5 | The faithful canary replays the captured setup argv and never reaches `query()`; it has derived hardening probes | read from file | ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md:120-124, anchor "it never reaches `query()`"; ADR-075 :102, anchor "four derived probes" |
| L6 | How Landlock interacts with the AppArmor profile attached to the container (L11) is not known | unverified | not measured here |
| L7 | Existing sandboxes that pair Landlock with seccomp are listed in the #9842 work | unverified (mutable source: an unmerged spec document carried by PR #9832, README-level claims, 2026-11-03) | the #9842 spec as carried by PR #9832; no text is quoted here and the epic's own issue body does not name either project |
| L8 | A prior change to the shared bwrap seccomp filter (injected by the shim, not `seccomp-bwrap.json`) caused a multi-day hosted-Bash outage | read from file | ADR-075-agent-sandbox-tenant-read-isolation.md:416 and :423-424 (addendum "2026-10-16 (#10445)", anchor "every hosted Bash call failed"; partly superseded by the 2026-10-19 addendum) and its post-incident report knowledge-base/engineering/operations/post-mortems/hosted-agent-bash-apply-seccomp-userns-eperm-postmortem.md |
| L9 | A thread restricted on filesystem access cannot change filesystem topology (the mount and `pivot_root` system calls; upstream states `chroot` is not denied), so any placement earlier than the sandbox's own setup is expected to interfere | unverified | upstream kernel documentation, section on filesystem topology modification; not measured here |
| L10 | The ABI is queried with the version flag of `landlock_create_ruleset`; an unprivileged caller needs `no_new_privs` (or CAP_SYS_ADMIN in its namespace); ENOSYS means Landlock is absent and EOPNOTSUPP means it is present but disabled at boot | unverified | upstream kernel documentation, not measured here |
| L11 | The production container runs under an AppArmor profile | read from file | apps/web-platform/infra/ci-deploy.sh, anchor "--security-opt apparmor=soleur-bwrap" |

Provenance of L1 (label: measured, `git log -S landlock -- apps/web-platform/infra/seccomp-bwrap.json` and `git log -i --grep=landlock origin/main`, 2026-11-03): the three names entered the profile in a 2026-04 commit whose message describes the file as based on Docker's default profile and does not mention Landlock; no commit message records a decision to allow them for Landlock.
Not checked: whether the shim-injected inner seccomp filters (ADR-075 addenda 2026-10-06 and 2026-10-19) affect these three syscalls (unverified).

What a ruleset could add, at the granularity ADR-075 already publishes.
ADR-075 frames bwrap as the filesystem isolation between tenants for the Bash tier in the shared container, with file tools under the in-process realpath containment (read from ADR-075, anchors "bwrap is the only filesystem isolation between" and "realpath-containment covers file-tools").
A ruleset would be a kernel-enforced second layer of filesystem access control that does not depend on the order in which the sandbox arguments are built (label: unverified).
ADR-075's history records that argument ordering once caused a functional regression, a read-only workspace (read from ADR-075 :22-30, anchor "#5848 thereby converted"); whether it also weakened isolation was not assessed (unverified).
It is now pinned by a canary test (read from ADR-075 :134, anchor "every covering `--tmpfs` precedes an rw `--bind` restore").
That the extra layer would catch anything the existing layers miss is an `unverified` expectation, not a measured benefit, and this ADR enumerates no gap.

Coverage.
The layer would cover the Bash tier only, as stated in Status.
File tools stay under ADR-075 and its realpath containment.

Relation to the credential broker.
Landlock does not change credential exposure.
ADR-272's deny of the Anthropic auth variables and the unshipped broker (#9543, ADR-311) are separate controls.
#9543 is open and no broker is shipped; ADR-311 records that only the mechanism was measured (read from ADR-311-credential-broker-mechanism-measured-before-built.md:17, anchor "It ships no broker").

Relation to epic #9842.
The epic's executor work is separate from this option.
Whether #9842 includes a spike that covers Landlock is addressed under ownership in the Decision section.

### Relations (informational; none implies a dependency, a shipped control or adoption)

- ADR-075: the control in force and the owner of the residual risk (L4a, L4b, L8).
- ADR-079: the faithful canary whose derived probes would carry the Landlock probe (L5).
- ADR-272: the credential deny for sandboxed Bash; a separate control that a ruleset does not change.
- ADR-311: records that only the broker mechanism was measured and that it ships no broker.
- ADR-122: the delivery and enforcement path for container sandbox controls; a helper and a ruleset policy would need a delivery path of the same kind (label: unverified).

## Considered Options

Dispositions below use "the control in force", "may be evaluated", "not evaluated" and "not a candidate", each with its reason. "Not adopted" appears only for the sequencing decision.

Option 1, keep bwrap, seccomp and AppArmor as they are.
This is the control in force (L1, L4a, L4b, L11).
Pros: it exists, the faithful canary replays its setup argv under the loaded profile at deploy (L5; the replay checks that the sandbox starts under the loaded profile; the separate deploy-time workspace-isolation probe recorded in ADR-079 is not restated here), and it adds no new artifact.
Cons: it is the shape whose residual risk ADR-075 records and owns.
Disposition: the control in force.

Option 2, a ruleset applied in the sandboxed child, after the sandbox view is built and before exec of the command, by a small helper.
This is the position the vendored apply-seccomp helper holds in the SDK's wrapper chain when it runs: it wraps the command the sandbox executes (read from ADR-075 :423-424, anchor "wraps **every** sandboxed command in that helper").
ADR-075's 2026-10-16 addendum records that this helper is not run under the production configuration (anchor "Skipping seccomp filter"); the position named above therefore has no occupant as of 2026-11-03 per that addendum (unverified against the 2026-10-19 addendum's second seccomp artifact, and unverified for any new helper until G2).
The injection mechanism (argv rewrite in the PATH shim, a patch of the vendored builder, or another) is chosen at the spike and recorded in its amendment. A wrapper that restricts its own process before bwrap setup is not a candidate (L9). G5 is run with the helper present under the shim's filter.
May be evaluated once the gate conditions below are met; no commitment to proceed.
Pros: the ruleset confines only the sandboxed command and not the process around it (label: unverified, L3).
Cons: a new maintained helper artifact; a new failure mode for hosted Bash; kernel and ABI dependence (L10); and the prior hosted-Bash outage (L8) occurred with a helper in this same position under the shim's seccomp filter.
Earlier placements, including the existing spawn wrappers, are not candidates, for two reasons.

- Upstream documentation states that a restricted thread cannot modify filesystem topology (L9), so an earlier placement is expected to interfere with the sandbox's own setup (unverified, not measured here).
- A prior change to the shared bwrap seccomp filter caused a multi-day hosted-Bash outage (L8), which is a reason to keep any new layer out of the setup path.

Option 3, a ruleset applied in the shared server process.
Disposition: not a candidate, because upstream documentation states a restriction cannot be removed from the thread that enforces it and is inherited by children created later (L3, unverified here). Applied in the shared server it would be expected to confine work serving every tenant. The placement recorded for evaluation is the sandboxed child, not the shared server process (expectation per L3, unverified until G2).

Option 4, existing sandboxes that pair Landlock with seccomp, as listed in the #9842 spec; capabilities unverified here; not evaluated by this ADR (L7).
No product is named, no comparison is quoted and no claim about any project is made.

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
  G1 is MET when, inside the production container and on the production host, the unprivileged-caller prerequisite holds and the reported ABI number is at or above the minimum the spike's rule set needs (L10).
  Absent, disabled at boot, or a lower ABI is a recorded miss, and the amendment records which.
  The production-host half is taken by a read-only probe that mirrors to Sentry, delivered by its own PR; this ADR schedules no shell access to the host. Unverified until measured.
- G2, placement.
  The ruleset is applied in the child after the sandbox view is built and before exec of the command.
  The measurement shows two things (L3, L9). First, from a thread of the server process, the same access succeeds after the child applied its ruleset. Second, a sandboxed command started after that child's ruleset was applied is not confined by it.
- G3, the faithful canary stays green.
  The canary is extended by a Landlock hardening probe among its derived probes, and the replay argv is unchanged (L5).
  It is run against the throwaway image, per the spike-branch rule below.
- G4, a positive control.
  The denied access is one that the bwrap view alone permits on the production sandbox configuration, and it is attempted by the exec'd command, not by the helper. It fails with the ruleset and succeeds in a control child without it. The access class is chosen at the spike and recorded in its amendment, not in this ADR. If no such access class exists, G4 is a recorded miss.
- G5, a real SDK Bash smoke.
  This is the hosted-Bash outage class (L8). The baked SDK Bash probe that `run_sdk_bash_smoke` execs (read from ADR-079 :700, anchor "`run_sdk_bash_smoke` in `ci-deploy.sh`") must return verdict `pass` with coverage `sdk_wrapper_shim_prodtuple`, not `replay_only`, with the layer present. It is run against the throwaway image, per the spike-branch rule below. The verdict is read from the probe's own `SDK_BASH_RESULT` line. It is not read from deploy success (the production smoke call site is non-blocking, anchor "`run_sdk_bash_smoke || true`"), not from the deploy-time host ledger, and not from canary green (L8).
- G6, degrade and signal.
  On a kernel or ABI that lacks the needed rights, the child degrades to bwrap-only and emits a signal mirrored to Sentry.
  A silent skip and a fail-closed Bash outage both fail the gate.

Ownership.
Kernel-ABI support is "measured once, in whichever of this ADR's gate or a #9842 spike runs first; the other cites the result".
No separate spike is scheduled.
If a #9842 spike already covers Landlock, this ADR cites it and drops G1 only if that spike covers the privilege prerequisite, the absent-versus-disabled distinction and the minimum ABI number (L10).
Measured (absence in scope: `gh issue view 9842 --json body --jq .body | grep -ci landlock`, epic issue body only, 2026-11-03; child spike issues not searched): 0.
A 2026-10-09 comment on #9859 names a Landlock-plus-seccomp candidate as an optional comparison arm (label: unverified, mutable source: issue comment, 2026-11-03). Whether any #9842 spike measures kernel ABI support is unverified, so G1 stays in this gate until a #9842 spike records an ABI result.

G3 to G6 are measured on a spike branch or a throwaway image, on a non-production host of the machine class the amendment records, with prototype helper, probe and signal code that lives on that branch and is not merged. Shipping delivers the production version of that code in a separate flag-off PR after the flip. G3 and G5 are taken by running the canary replay and the baked SDK Bash probe against the throwaway image; the deploy-time smoke and its host ledger are not their source, because they run only inside a production deploy. Measurements on the production host (G1) are read-only and run under the operator's authorization at that time.

Tracker: #9602 (open on 2026-11-03).

No public claim.
At any future adoption, flag creation and legal wording stay operator-class.
No public security claim is made or changed ahead of a measured control, and no claim wider than ADR-075 states is made or implied.
Any future layer would be conditional on kernel support, and no claim is made that it is always active or covers every session.

## Consequences

- Positive: the option, where it must be applied, and what must be measured before it is planned are recorded, so the spike is scoped once and not twice.
- Positive: nothing runs differently after this ADR merges. The control in force and its residual risk are exactly as ADR-075 records them.
- Negative: a record titled for a ruleset can be read as a control that exists.
  The Status line, the paired "not acceptance of the residual risk in ADR-075" sentence and the no-public-claim clause exist to prevent that.
  A security answer is operator-class wording and does not quote this ADR; engineering facts about the control in force are read from ADR-075.
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

- NFR-038 (Least Privilege Container Images): the register records the Agent Runtime as Partial (nearest register row; its evidence is image hardening, not runtime isolation).
  A ruleset beneath bwrap would add a least-privilege layer for the Bash tier if adopted (label: unverified); nothing in this ADR changes the current rating, and the register is not edited.
  No other NFR row changes tier.

## Principle Alignment

- AP-011 (ADRs for architecture decisions): Aligned.
  A deferred architecture-scale option gets a decision record with a measurement gate and a named placement.
- AP-021 (Diagnostic honesty): Aligned, applied by analogy (the register scopes AP-021 to operator-facing messages).
  Every ledger claim is labelled measured, read from a file or unverified; negative searches carry their command, paths and date (L2, and the ownership search).
  G6 requires that a skipped layer produce a signal and not a silent skip, so a message about the layer can name only what the job measured.
