---
title: "infra: LUKS web-host follow-ups (#9356 #9357 #9358 #9377 #9378)"
date: 2026-10-01
slug: luks-web-host-followups-disposability-escrow-hardening
branch: feat-one-shot-9356-luks-followups
issue: 9356
type: chore
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
closes: [9378]
refs: [9356, 9357, 9358, 9377]
lane: cross-domain
---

# infra: LUKS web-host follow-ups (#9356 #9357 #9358 #9377 #9378)

## Overview

Group A of the post-ADR-263 LUKS follow-ups: five open issues deferred out of the guest-side fresh-boot
LUKS work for web hosts. They cover a proof path for replacing a populated web host, collapsing the two
LUKS volume addresses into one keyed resource, wiring the cutover marker into the weight gate, splitting
the header-escrow credential, and hardening the provisioner plus its tests. Every live or destructive step
stays behind existing gates and is recorded as a deferred operator-gated follow-up.

## Research Insights

**Premise Validation (Phase 0.6).** All five issues (#9356, #9357, #9358, #9377, #9378) are OPEN with no closing PR.
PR #9396 (provisioner mutant speed-up) and PR #9352 (ADR-263) are MERGED. Stale or unmet premises found:
(1) PR #9348 ("PR B", the web-1 plaintext wipe convergence) is still an open, held draft, and no web-1 de-pet rebuild
issue exists, so the two blockers #9357 names are both unmet; (2) no flip orchestrator exists on origin/main
(`grep -rn lb-weight-gate` finds only tests, docs and two workflow comments), so #9358 cannot be "wired into the
orchestrator" literally; (3) the review-disposition file cited by #9378 now lives under
`knowledge-base/project/specs/archive/20261001-210331-feat-one-shot-6931-web2-fresh-boot-luks/`; (4) a research
agent claimed the web-host-replace gate already carries the two key-conditional arms; measured false: the gate has only
the three requirement arms (nic, vatt, fw) and refuses web-1 by name (`_WEB_HOST_REPLACE_LUKS_PINNED_KEY`); (5) ADR-263
and the ADR-148 corpus were read for #9356/#9357 mechanisms: T2 is in ADR-263's alternatives table as "Deferred (#9357)",
not rejected; relaxing the web-1 refusal is ADR-148 alternative 4 "rejected for now". No cited mechanism sits in a
rejected-alternatives row, but both ADRs set the unblock conditions this plan builds toward.

**Property List (Phase 0.6b).**
P1 (#9378) Two provisioner invocations cannot interleave; the provisioner's commands cannot be hijacked through PATH;
the test seam cannot be activated on a real cloud-init host; `/etc/fstab`, `/etc/crypttab`, the docker drop-in and the
intent file are never observable half-written after a crash.
P2 (#9378) A link-local address can never be an accept target of the container egress ruleset, proved at the rendered
ruleset and resolver level, not only over allowlist text.
P3 (#9358) The only way the marker reaches `lb-weight-gate.sh` is one fail-closed sourcing seam that reads one exact
Doppler config; the gate stays env-only.
P4 (#9377) A web-host-class token cannot reach web-1's R2 escrow pair or bucket (narrowed, not eliminated: the token still resolves
the inherited `prd` root, which a live-mode scan lists for review).
P5 (#9356) A replace plan for the LUKS-pinned key that omits the LUKS attachment or the apex repoint aborts; the web-1
refusal stays until a rehearsal exists; the populated-volume path never formats.
P7 (#9356, CPO) A LUKS header restored from its escrow object reopens the volume with the sentinel data intact (header-restore drill).
P6 (#9357) The state-move recipe for the singleton-to-keyed collapse is proven safe offline and its preconditions are
machine-checkable before any live move.

**Cut List.**

- R2 bucket lock rule (#9377 option b) -> P4 -> the credential split (option a) buys it fully. Lock rules fail here:
  R2 has no versioning, an `Age` rule leaves a post-retention overwrite window, `Indefinite` breaks web-1's cutover flow
  (`workspaces-cutover.sh` uploads then `aws s3 rm`s a probe object, and re-key rewrites `workspaces-luks-header-<uuid>.img`).
- Per-host-class passphrase -> not in any issue's property list -> tracked by the shared-passphrase residual in ADR-263
  and #6167; the split only narrows the residual (stated plainly in the ADR amendment).
- Merging the T2 HCL and a single-use state-move workflow -> P6 is bought by the offline rehearsal plus the runbook;
  the HCL cannot merge before the live move (see Risks) and ADR-263 treats the analogous #9372 workflow as an
  operation, not PR content.
- Removing the web-1 refusal -> not required by P5; needs a live rehearsal and the T2 topology.
- Terraform-minted R2 pair -> unproven (repo learning `2026-05-18-cla-evidence-r2-s3-creds-not-derived.md` measured
  `SignatureDoesNotMatch` for id + sha256(value) while the Cloudflare docs say it works); the live mint is a gated probe.
- A flip orchestrator -> out of #9358's reach; the wrapper is the seam it will call.

**Relevant files (anchors, no line numbers).** Provisioner `apps/web-platform/infra/workspaces-luks-provision.sh`
(ROOT/seam block, `_may_format`, `# ── wire`, `_escrow`); suite `workspaces-luks-provision.test.sh` (`case_raw_formats_once`,
`READONLY=`, mutation rows, `WLP_ONLY_CASES`); `cron-egress-nftables.sh` (`is_valid_ipv4_cidr`, Phase 3 heredoc, env
seams `RESOLVE_SCRIPT` and `CIDR_FILE`); `cron-egress-resolve.sh` (flock re-exec idiom, no link-local filter);
`cron-egress-metadata-endpoint.test.sh` (allowlist-text suite, 17 plant rows); `lb-weight-gate.sh` (Condition B.6-B.10,
"no caller sources the marker"); `scripts/lib/web2-luks-rows.sh` (`W2L_MARKER_NAME`, `W2L_MARKER_CONFIG`);
`tests/scripts/lib/web-host-replace-gate.sh` + `tests/scripts/test-web-host-replace-gate.sh`;
`workspaces-luks-header.tf`, `workspaces-luks-fresh-boot.tf`, `server.tf` (fresh-boot token in the templatefile map),
`cloud-init.yml` (the `WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks` printf); `luks-monitor.sh` (`--config prd_workspaces_luks`
key read); `.github/workflows/workspaces-plaintext-forget.yml` (state-surgery precedent with push-apply pause check);
`.github/workflows/apply-web-platform-infra.yml` (482,241 bytes against the 490,000-byte gate in
`plugins/soleur/test/workflow-file-size.test.ts`).

**Institutional learnings applied.** `2026-07-23-terraform-destroy-guard-address-vs-physical-id-and-replace-recovery-arm`
(plan-shape guards prove addresses, not physical objects); `2026-07-02-moved-block-on-operator-excluded-resource-wedges-targeted-ci-apply`
(why T2 uses a state move, not `moved`); `2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice...` and
`2026-08-09-my-tests-pinned-a-constant-by-indexing-it...` (matrix and harness-row discipline);
`2026-09-21-my-escrow-suite-stubbed-the-one-tool-that-would-have-refused-it` (stubs prove spelling, not acceptance);
`2026-05-18-cla-evidence-r2-s3-creds-not-derived` (R2 pair is not derivable until probed);
`2026-06-02-verify-terraform-target-set-not-header-prose` (new resources must be in the `-target` list or the merge is a
silent no-op); `2026-07-14-cloud-init-templatefile-escaping...` (user_data budget).

## Research Reconciliation — Spec vs. Codebase

| Issue/brief claim | Reality (measured this session) | Plan response |
|---|---|---|
| #9356: "key-conditional requirement arms for `hcloud_volume_attachment.workspaces_luks` and `cloudflare_record.app`" are missing | Confirmed: `web_host_replace_gate` has only nic/vatt/fw requirement arms and refuses web-1 by name before reading the plan | Phase 4 adds the arms behind a SEPARATE constant so the by-name refusal stays |
| #9356: unblock needs "a rehearsal on a non-production host" | No non-production host exists. web-2 (weight 0, empty) becomes the rehearsal host only after #9372 converts it | Offline rehearsal now; live rehearsal on web-2 is a deferred gated step with a prewritten verifier |
| #9356: "and #6964" | #6964 is the web-1-bound `workspaces_luks` attachment outside the birth fan-out; T2 (#9357) dissolves it | Arms cover it for the current topology; T2 removes the need |
| #9357: "after the web-1 de-pet" and "PR B (#9348) has landed" | #9348 is an open held draft; no de-pet rebuild issue exists | Only the offline rehearsal, runbook and blocked-by edges ship; HCL and state move wait |
| #9358: "in the flip orchestrator" | No flip orchestrator exists; `lb-weight-gate.sh` has no caller | Ship the sourcing seam the orchestrator will call, plus a census that nothing else feeds the gate |
| #9377: web-2's token reads the shared pair | Confirmed (`workspaces-luks-fresh-boot.tf`); also `luks-monitor.sh` hardcodes `--config prd_workspaces_luks` for the key read, so a naive config split would silently break web-2's daily probe | Phase 3 parameterizes the monitor and adds a census over every web-class path |
| #9377: R2 pair "minted" | Not Terraform-derivable per repo learning; Cloudflare docs claim derivation works, repo measurement says otherwise | The mint is a deferred gated probe; this PR ships everything that does not need the pair |
| #9378: provisioner suite "~3.5 min", "~34 sed forks per fixture" | PR #9396 already cut full-suite wall time to ~1m10s at 3 jobs by restricting each mutant to its covering cases | Phase 1 measures first; only the maintainability split of `case_raw_formats_once` is unconditional |
| #9378: nft-runtime test needs "a live nft kernel" (research-agent claim) | `cron-egress-nftables.sh` already exposes `RESOLVE_SCRIPT` and `CIDR_FILE` seams and calls `nft` by bare name, so a stub `nft` that records stdin renders the exact ruleset text | Stub-based rendered-ruleset test; the limits of a stub are stated in Sharp Edges |

## Problem Statement / Motivation

ADR-263 shipped the guest-side fresh-boot LUKS path and recorded five things it deliberately left open. Three are
risk reductions that must land before web-2 holds production data (#9377, #9358, and #9378's hardening), and two are
the proof work for making a populated web host disposable (#9356, #9357). The sole copy of every user's checked-out
repository sits on web-1's LUKS volume, so the cost of a wrong gate or provisioner is permanent loss, which is why
the plan keeps every irreversible step behind a gate and proves the rest offline.

## Scope and Disposition per Issue

| Issue | Delivered by this PR | Deferred (gated, tracked on the issue itself) | PR body keyword |
|---|---|---|---|
| #9378 | Provisioner hardening (flock, pinned PATH, seam refusal on a real host, atomic fsynced writes), nft-runtime test, resolver link-local filter, `case_raw_formats_once` split, fork-count trim if measurement justifies | none | `Closes #9378` |
| #9358 | `lb-weight-gate-with-marker.sh` sourcing seam + census + ADR text | Wiring into the flip orchestrator when it is planned | `Ref #9358` |
| #9377 | New bucket, Doppler config, secret copies, token re-point, monitor/provisioner/cloud-init config parameterization, census, ledger row, `-target` list, ADR amendment, Article 30 edits, readiness checker | Live R2 pair mint (API probe, else dashboard automation) and its first signed PUT/HEAD; must complete before #9372 | `Ref #9377` |
| #9356 | Key-conditional arms (web-1 refusal kept), populated-volume offline cases, header-restore drill on the real-device loopback suite, rehearsal runbook + verifier | Live rehearsal on web-2 after #9372; relaxing the web-1 refusal | `Ref #9356` |
| #9357 | Offline state-move rehearsal, runbook, readiness checker, ADR addendum, blocked-by edges | HCL collapse + single-use state-move workflow (their own PR, after #9348 and the de-pet) | `Ref #9357` |

EXPLICITLY NOT DONE HERE: the gated live web-2 conversion (#9372) is neither dispatched, planned for dispatch, nor closed.
No `terraform apply`, no `workflow_dispatch` with `dry_run=false`, no Doppler write, no Cloudflare token mint is part of
any phase below. The normal merge pipeline's push-apply (existing gates, `-target` lists) is the only path by which
Phase 3's Terraform reaches production, and its resources are additive.

## Implementation Phases

Order is by dependency, not by issue number. Each phase ends with its own suite green before the next starts
(`cq-write-failing-tests-before`: the RED rows named in the Guard Contract are written first).

### Phase 0 — Baselines (read-only, minutes)

- 0.1 Record `wc -c .github/workflows/apply-web-platform-infra.yml` (482,241 at planning time against the 490,000 gate
  in `plugins/soleur/test/workflow-file-size.test.ts`) and the `cloud-init.yml` gzip budget headroom
  (`plugins/soleur/test/cloud-init-user-data-size.test.ts`). Phase 3 must stay under both.
- 0.2 Time the provisioner suite outer run (`time bash apps/web-platform/infra/workspaces-luks-provision.test.sh`) and
  count `sed` execs in the fixture builder (`strace -f -qq -e trace=execve ... 2>&1 | grep -c '/sed'` or a `PATH` shim
  that counts). Write the numbers into the PR body. This decides the fork-trim half of Phase 1.7.
- 0.4 Measure whether `/var/lib/cloud/instance` exists on the CI runner image (`ls -d /var/lib/cloud/instance` in a throwaway workflow step
  or from a recent run's logs); it decides whether Phase 1.3's refusal needs the non-root carve-out to keep the suite green there.
- 0.3 Confirm which CI job installs `terraform` for shell suites (`grep -ln setup-terraform .github/workflows/*.yml`;
  `infra-validation.yml` is the candidate) so the Phase 5 rehearsal is registered where it can run.

### Phase 1 — #9378 provisioner hardening and test quality

All edits in `apps/web-platform/infra/workspaces-luks-provision.sh` unless named.

- 1.1 **Serialize.** After the seam block and before the first side effect (`_secure_file "$ENVFILE"`): check
  `command -v flock >/dev/null 2>&1 || fatal config 10 "flock is absent"` (a missing `flock` must be arm `config`, not rc 127: the
  required-commands loop runs later), create the lock directory (`mkdir -p "${ROOT}/run"`, which moves that one existing side effect
  earlier and is harmless), then `exec 9>"${ROOT}/run/workspaces-luks-provision.lock" || fatal config 10 "cannot open the lock file"`
  (a failed `exec` redirection does not stop bash outside POSIX mode, so the `||` is load-bearing) and
  `flock -w 600 9 || fatal config 10 "lock_timeout: another provisioner holds the lock"`. File-descriptor form, not the
  `cron-egress-resolve.sh` re-exec-with-env-guard form: no env flag to forge, no second exec. Reuses arm `config` (10) so the 13-stage
  Sentry alert contract and `sentry-fresh-boot-luks-alert-op-contract.test.ts` do not move; the distinct `lock_timeout` reason text
  separates contention from misconfiguration in the detail row. The 600 s bound sits inside cloud-init's once-per-instance `runcmd`,
  which has no unit timeout, and below the existing 300 s device wait plus ~300 s key retry. Children inherit fd 9 (`apt-get`,
  `cryptsetup`, `mount`, `systemctl`); none daemonizes holding it in the flows this script runs, and that is stated in a comment.
- 1.2 **Pin PATH.** Immediately after the seam block, only when `ROOT` is empty (production): `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; export PATH`.
  Under the seam the scratch `PATH` stays so the suite's stubs intercept (every external is called by bare name).
- 1.3 **Refuse the seam on a real host.** A function `_seam_allowed <cloud-init-marker-path>` returns non-zero when
  the marker exists; the production call site passes the constant `/var/lib/cloud/instance` (root-owned, present on every
  cloud-init host, never under `ROOT`), and the seam block refuses with exit 2 when it returns non-zero. The refusal fires only for
  `euid 0` plus the marker, so a non-root CI runner that happens to carry cloud-init state (Phase 0.4) keeps the suite green, while the
  production provisioner always runs as root. The suite tests the
  function with a scratch marker path and pins the call-site constant with a static grep plus a mutation row (an env-settable
  marker path would re-introduce the unauthenticated knob). `WORKSPACES_PROVISION_TEST_SEAM`/`_ROOT` stay the only seam vars.
- 1.4 **Atomic writes.** One helper `_install_file <dest> <mode>` (content on stdin): temp file in the SAME directory
  (`$dest.provision.tmp`), write, `chmod`, `sync "$tmp"` (coreutils >= 8.24 `sync FILE` is an fsync; the host and the runner are Ubuntu; pinned by a comment), `mv -f "$tmp" "$dest"`,
  `sync "$(dirname "$dest")"`. Used for fstab (replaces the current awk-to-tmp + mv, adding the fsyncs), crypttab (replaces the
  in-place append with read-modify-write that preserves an existing file's mode, 0600 when it creates one, as today), the docker
  drop-in (0644), and the format intent file (fsync before the mv that precedes `luksFormat`). A stale `*.provision.tmp` from a
  crash is overwritten, never read. The suite's `READONLY` allow-list gains `sync` (check how the existing bare `sync` calls already pass the stub layer first); refusal cases still assert no
  non-read-only call.
- 1.5 **nft-runtime test** (new `apps/web-platform/infra/cron-egress-nftables.test.sh`): runs the REAL
  `cron-egress-nftables.sh` with a stub `nft` on a scratch `PATH` that appends each call's argv and stdin to a log, stub `ip`/`docker`,
  `RESOLVE_SCRIPT` pointing at a stub, `CIDR_FILE` pointing at a scratch file. Asserts over the rendered text: Phase-3
  transaction order (return traffic first, pinned DNS, default-drop log then drop LAST), exactly one DOCKER-USER jump insert, no
  rendered line or `add element` payload contains `169.254`, and a CIDR file containing `169.254.0.0/16`, `169.254.169.254/32`,
  `169.0.0.0/8` or `0.0.0.0/0` makes the script die with rc 1 before any `add element` reaches `nft`. This needs a new check in
  `is_valid_ipv4_cidr` rejecting any CIDR that overlaps `169.254.0.0/16` (reject-whole-file, the existing doctrine).
- 1.6 **Resolver link-local filter** in `cron-egress-resolve.sh`: drop any resolved A record in `169.254.0.0/16` (and log the
  host) before it is added to `@soleur_egress_allow`, treating "all records filtered" as a resolution failure for that host
  (additive-only tick, existing partial-failure doctrine). Test with the stub-`getent`/resolver seam the suite already uses
  (read the resolver's gather loop before wiring; do not invent a seam). The existing `cron-egress-metadata-endpoint.test.sh`
  header's "deferred" sentence is updated to point at the new suite; its 17 plant rows and the exactly-17 floor stay.
- 1.7 **Test maintainability.** Split `case_raw_formats_once` (about 26 assertions) into four cases of at most ~8 assertions
  (`raw_order`, `raw_wiring`, `raw_secret_hygiene`, `raw_idempotent`); update the case-set assertion, `EXPECTED_CASES` (17 to 20), the exact assertion floor (180 + 68 today) and every mutation row's `WLP_ONLY_CASES` that named `raw` (each row names the NEW cases that hold its target assertion; re-drive
  every row restricted vs full as PR #9396 did, identical rc, no row weakened). If Phase 0.2 shows the fixture builder forks `sed`
  more than ~10 times per fixture, replace them with parameter expansion or one multi-`-e` `sed`; otherwise leave it and record the
  measurement (no speculative optimisation).
- 1.8 New provisioner cases for 1.1-1.4 (RED first): see Guard 1.

### Phase 2 — #9358 marker-sourcing seam

- 2.1 New `apps/web-platform/infra/lb-weight-gate-with-marker.sh`: unsets any caller-supplied `WORKSPACES_LUKS_CUTOVER_AT`,
  reads it once with `doppler secrets get WORKSPACES_LUKS_CUTOVER_AT --plain --project soleur --config prd_workspaces_luks_marker`
  (the exact config, the R9 single-secret form, never `doppler run`/`download`; name and config come from the same constants
  as `scripts/lib/web2-luks-rows.sh` `W2L_MARKER_NAME`/`W2L_MARKER_CONFIG`, parity-pinned by a test), exports the value, then
  `exec`s `lb-weight-gate.sh`. "Not found" is told apart from a transport error WITHOUT parsing stderr: first
  `doppler secrets --only-names --project soleur --config prd_workspaces_luks_marker` (any failure exits 3 without running the gate), then a
  membership test on the names; an absent name leaves the variable unset (the gate fails closed with `B_workspaces_luks_marker_absent`),
  a present one is read with the single-secret `get`. The wrapper handles only the WORKSPACES marker; `GIT_DATA_LUKS_CUTOVER_AT` and the
  rest of the gate environment remain the orchestrator's. It requires `DOPPLER_TOKEN` in its environment; no read-only token on the marker
  config exists (the CI write token is read/write), so minting one is recorded on #9358 as a prerequisite of the orchestrator, not done here. `lb-weight-gate.sh` stays pure
  and env-only; its header sentences "no caller sources the marker" and "ships with the deferred orchestrator" are rewritten.
- 2.2 New `apps/web-platform/infra/lb-weight-gate-with-marker.test.sh` with a stub `doppler` replaying the real CLI contract (output shape, exit codes, last-value-wins flags): marker present -> gate sees it
  and the weight-flip branches behave as in `lb-weight-gate.test.sh`; absent -> `B_workspaces_luks_marker_absent`; transport
  error -> rc 3 and the gate never runs; a pre-set caller value is discarded; the stub proves the argv (`--config prd_workspaces_luks_marker`, `--plain`).
- 2.3 **Census** (Guard 5, a pass/fail section of `lb-weight-gate-with-marker.test.sh`): no file other than the wrapper and `*.test.sh`, and no comment-only mention, invokes `lb-weight-gate.sh` or assigns
  `WORKSPACES_LUKS_CUTOVER_AT` into a gate environment. The marker value stays advisory and shape-only: provenance is not validated here
  (a value planted in `prd` shows through the branch config; ADR-263 records this) and the plan does not claim otherwise.

### Phase 3 — #9377 escrow credential split (code only; live mint deferred)

Design decision: separate bucket + separate Doppler branch config for the web-host class (issue option a). Option b
(R2 bucket lock) is cut (see Cut List). The split narrows ADR-263's R4 residual; it does not remove the shared passphrase.

- 3.1 New `apps/web-platform/infra/workspaces-luks-header-web.tf` (a NEW file: `workspaces-luks.test.sh`'s A11 guard is
  file-scoped to `workspaces-luks.tf`, the header test rejects `config = "prd"`, and #9348 edits `workspaces-luks.tf`):
  `cloudflare_r2_bucket.workspaces_luks_header_web` (provider alias `cloudflare.r2`, name `soleur-workspaces-luks-header-web`,
  `location = "WEUR"`, `prevent_destroy = true`); `doppler_config.workspaces_luks_web` (`prd_workspaces_luks_web`, environment
  `prd`, copying `doppler_config.workspaces_luks_marker`); `doppler_secret`s in it for `WORKSPACES_LUKS_KEY`
  (`= random_password.workspaces_luks.result`, in-graph so rotation cannot drift; never `-replace` that password),
  `WORKSPACES_HEADER_BUCKET` (a reference to the new bucket) and `WORKSPACES_HEADER_R2_ENDPOINT` (`local.r2_s3_endpoint`),
  all `visibility = "masked"`, `config` as a reference to the resource (#6197 edge).
- 3.2 `workspaces-luks-fresh-boot.tf`: a NEW `doppler_service_token.workspaces_luks_fresh_boot_web` (project `soleur`, config
  `doppler_config.workspaces_luks_web.name`, `access = "read"`, no `create_before_destroy`), and `server.tf`'s
  `workspaces_luks_fresh_boot_token` points at it. The existing `workspaces_luks_fresh_boot` token resource is LEFT IN PLACE and unused: changing its
  `config` is ForceNew (a destroy), which the push-apply destroy guard (`destroy_count` over every resource) halts without `[ack-destroy]`,
  and a new resource keeps the merge apply purely additive. Retiring the old token is a later, acknowledged destroy (follow-up table). Its
  comment block is corrected, and the `F1`/`F2`/`F3` predicates in `workspaces-luks-fresh-boot.test.sh` are rewritten for the second token
  (F1 currently pins `config = "prd_workspaces_luks"` as a literal; the new pin is the resource-reference form used elsewhere in that suite).
- 3.3 `cloud-init.yml`: the `WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks` literal in the `/etc/default/workspaces-luks-boot`
  printf becomes `prd_workspaces_luks_web`, kept a literal, not a template variable (user_data headroom is thin). web-1's own
  SSH installer in `workspaces-luks.tf` keeps `prd_workspaces_luks`; `fresh-boot-parity.test.sh` check 17d keeps pinning that.
- 3.4 Baked scripts: `workspaces-luks-provision.sh` accepts the closed set `prd_workspaces_luks` | `prd_workspaces_luks_web` (replacing the
  `[ "$CFG" = prd_workspaces_luks ]` pin; the token's own config scope, not the name check, is what stops a mis-paired image from reading web-1's
  pair, and an image/user_data mismatch at birth would otherwise leave the host dark; the existing birth flow already pins the image to the
  commit through the `host_scripts_content_hash` label, ADR-263); `luks-monitor.sh` gains NEW parsing code: one single-line `grep`
  (never `source`) of `WORKSPACES_DOPPLER_CONFIG` from `/etc/default/workspaces-luks-boot` (only `workspaces-luks-reopen.service` loads that
  file today; the monitor's own `EnvironmentFile` is `/etc/default/luks-monitor`), validated against the same closed set, falling back to
  `prd_workspaces_luks` when the file or line is absent (web-1 behaviour unchanged, cloud-init bytes unchanged). Only the key read (the
  `WORKSPACES_LUKS_KEY` line) moves; the heartbeat read stays on `prd_workspaces_luks` because the standby profile web-2 runs skips it, and
  Guard 3 excludes it by name. `luks-monitor-token-refresh.sh` is web-1-only and stays, pinned by the census.
- 3.5 **Census + readiness checker** (new `scripts/check-web-host-escrow-config.sh`): `--static` (repo only, no Doppler) verifies
  that every web-class path (provisioner, reopen, monitor, cloud-init, the fresh-boot token) names only `prd_workspaces_luks_web`,
  that the web-1 paths keep `prd_workspaces_luks`, and that no web-class path greps `--config prd_workspaces_luks` literal;
  prints `escrow-split-contract: ok`. Live mode (needs a read token, names only via `doppler secrets --only-names`) asserts the
  five names exist in `prd_workspaces_luks_web` (KEY, BUCKET, ENDPOINT from Terraform; the R2 key id and secret from the deferred mint), that
  `WORKSPACES_HEADER_R2_ACCESS_KEY_ID`/`_SECRET_ACCESS_KEY` are absent from the `prd` root (so a branch config inheriting `prd` cannot hand
  web-2 web-1's pair), and lists `prd`-root names matching `R2|CLOUDFLARE|AWS_` as an advisory scan (the token resolves about 116 inherited
  secrets, so isolation is "narrowed", not proven). Both modes are exercised by `scripts/check-web-host-escrow-config.test.sh` with a stub
  `doppler` that replays the real CLI contract (the real `doppler secrets --only-names` output shape and exit codes, taken from the CLI help or a
  recorded run, never assumed); running live mode against Doppler is the first step of the #9372 workflow (ADR-263 amendment makes it a hard precondition,
  because the provisioner formats even when escrow is missing by design) and is not run by this PR.
  `workspaces-luks-header-web.test.sh` replicates the per-file cardinality and no-`config = "prd"` guards of `workspaces-luks.test.sh` A11 and
  `workspaces-luks-header.test.sh`, because a new file escapes both.
- 3.6 Plumbing that makes the merge safe (a missed item here is a silent no-op, `2026-06-02-verify-terraform-target-set...`):
  add the bucket, config, three secrets and the new fresh-boot token to the push-apply `-target` list in
  `.github/workflows/apply-web-platform-infra.yml` (stay under the 490,000-byte gate; record the post-edit size) and to the
  `freshBoot` array in `plugins/soleur/test/terraform-target-parity.test.ts` (confirm `allResources` picks up the new file by itself); add the ledger row
  `cloudflare_r2_bucket.workspaces_luks_header_web` to `scripts/encryption-posture-ledger.json` (copy the
  `workspaces_luks_header` row, same attestation); do NOT add the config to `doppler-config-inventory.txt` (same reason the marker
  config is absent: adding a name mints a drift-read token and forces floor edits; record this decision in the ADR amendment);
  suite registration, from the consumers that read each list (quote the line at work time): suites under `apps/web-platform/infra/` register by
  filesystem glob presence in `apps/web-platform/infra/run-registered-suites.sh` (ADR-252: presence IS registration, picked up by the
  deploy-script-tests matrix and by `scripts/test-all.sh`'s nested `run_suite` when the diff touches that directory), with an optional per-suite
  bound in that runner's table (the provisioner suite has one at 900 s) for any new suite that can exceed the default; a `scripts/*.test.sh` suite
  is NOT globbed (`SUITE_GLOBS` in `scripts/test-all.sh` covers `scripts/lib/*.test.sh` only), so `scripts/check-web-host-escrow-config.test.sh`
  needs an explicit `run_suite "scripts/check-web-host-escrow-config" bash scripts/check-web-host-escrow-config.test.sh` line (precedent:
  `scripts/lint-guard-contract`) or must live under a globbed directory; the generated `suite-shard-legs.tsv` / `suite-durations.tsv` are NOT
  hand-edited (shard parity regressed in this area this week, commit `abd29f4bcf`); verify with the repo's orphan-suite linter and the runner's own
  enumeration. A suite that needs `terraform` or root (Phase 5.1, the loopback drill) must be checked against the runner's tooling-dependency table first.
- 3.6b **Every workflow that can apply the edited Terraform** (`server.tf`, `workspaces-luks-fresh-boot.tf` and the new file): enumerate, from each
  push-triggered apply workflow's `paths:` filter and `-target` graph, which one reaches the new resources and `hcloud_server.web` (the new token is
  referenced from `server.tf`'s user_data map, which `apply-deploy-pipeline-fix.yml`'s graph may reach). Confirm for each that the plan is create-only
  and that no workflow creates the new token or secrets without the guard that would count a destroy
  (`2026-09-24-a-second-apply-workflow-could-perform-the-rotation-without-its-gate`). The PR body's first line answers "does merging this alone mutate
  production?": it DOES, by creating the new bucket, Doppler config, three secrets and token through the push-apply; nothing is replaced or destroyed and
  no host changes (or the measured truth if the enumeration says otherwise).
- 3.7 Docs: ADR-263 amendment (Phase 6), `knowledge-base/legal/article-30-register.md` (PA-1 (e) R2 bucket note: add the second bucket
  and mark the "not to a new recipient" sentence superseded; the R4 residual row narrowed and conditioned on this merge),
  `knowledge-base/legal/compliance-posture.md` (the web-2 row and the Cloudflare row), read
  `knowledge-base/legal/article-30-2-register.md` and amend if it names the escrow bucket; `docs/legal/**` needs no edit (CLO).
- 3.8 Deferred live step (stays on #9377): mint a bucket-scoped Object Read and Write R2 pair for the new bucket and write both
  values into `prd_workspaces_luks_web`. First attempt is a gated API probe (create the token, derive id + sha256(value), signed PUT
  and HEAD against the new bucket) because the repo's own measurement contradicts the docs; if the probe fails, the dashboard
  mint is automated through the Playwright route. Until the pair exists the provisioner records `escrow=missing`, which withholds
  the soak marker; the first birth after the split must not precede it (blocked-by edge #9372 -> #9377).

### Phase 4 — #9356 key-conditional arms, populated-volume proof, rehearsal tooling

- 4.1 `tests/scripts/lib/web-host-replace-gate.sh`: keep `_WEB_HOST_REPLACE_LUKS_PINNED_KEY` as the refusal constant
  (`terraform-target-parity.test.ts` binds its literal with the workflow). Add `_WEB_HOST_REPLACE_LUKS_ARMS_KEY="web-1"` and, for
  that key only, an extended allow-set (`hcloud_volume_attachment.workspaces_luks`, `cloudflare_record.app`) and two requirement
  arms: the LUKS attachment shows `create`, and `cloudflare_record.app` shows exactly `["update"]` with its `content` changing
  (`after != before` or `after_unknown.content == true`; a delete/create of the apex record is an outage window and aborts).
  `hcloud_volume.workspaces_luks` and the passphrase resources remain prohibitions. The refusal stays first in the function, so with
  the refusal active a web-1 plan carrying every arm still aborts (CPO condition 1). The arm comment restates the three blockers no plan can
  show (the by-id mount pin to the superseded plaintext volume, the web-1-pinned `terraform_data` SSH provisioners, whose count the gate's own text states as both 17 and 15, so count with `grep -c` at work time, and `-target` being upstream-only), so "arms
  complete" is never read as "web-1 safe"; the arms-only fixture is named as such. T2 later dissolves the `workspaces_luks` address, and its
  arm becomes obsolete with it.
- 4.2 `tests/scripts/test-web-host-replace-gate.sh`: fixtures for a complete web-1 plan (the refusal constant overridden inside a
  subshell to drive the arms), a web-1 plan missing each arm, a web-2 plan that touches `workspaces_luks` or `cloudflare_record.app`
  (out-of-scope abort), and the refusal-intact case. Mutation rows per Guard 4.
- 4.3 Parity: extend `plugins/soleur/test/terraform-target-parity.test.ts` with an assertion that the arms-key extension is exactly
  those two addresses. The workflow's `-target` list is NOT edited here (byte budget and the refusal make it dead code until the
  relaxing PR); the header comment in the gate says so.
- 4.4 Populated-volume proof, offline: audit `case_luks_opens` / `case_ext4_refused` / `no_writes` in the provisioner suite against
  "a replacement host meets a LUKS volume whose mapper carries an ext4 filesystem with content" and add rows for exactly these three
  if absent (the audit stops there): zero `luksFormat`/`mkfs`/`wipefs` writes, arm file `luks_arm=opened`, escrow idempotent by md5. In `workspaces-luks-loopback.test.sh` (real
  cryptsetup, root required, no silent skip) add a **header-restore drill** (CPO): format a loop device, write a sentinel file,
  `luksHeaderBackup`, zero the header region, `luksHeaderRestore`, reopen, read the sentinel back.
- 4.5 Rehearsal runbook (no dispatch, no new script): a new section in
  `knowledge-base/engineering/operations/runbooks/web-host-replace.md` ("Populated-volume rehearsal on web-2, after #9372") with the sentinel
  placed before the replace and the post-replace acceptance as an inline no-SSH row query through the existing rows library
  (`luks_arm=opened`, never `formatted`; `escrow=ok`). Evidence scope, stated plainly: a web-2 rehearsal proves the populated-volume-preserve
  path and the dispatch mechanics; it does NOT exercise the web-1 arms or the web-1-only blockers, which are proven only offline (fixtures) and by
  the T2 topology. A scripted verifier is written with the live run if it proves useful.

### Phase 5 — #9357 offline state-move rehearsal and readiness

- 5.1 New `apps/web-platform/infra/workspaces-luks-t2-rehearsal.test.sh`: in a scratch dir, a mini root using the built-in
  `terraform_data` type (no provider download) with the real addresses' shape: singleton volume + attachment + a keyed
  `for_each` family. It asserts (a) with the state as-is and the T2 config, `terraform plan` shows destroy+create of the
  sole-copy stand-in (anti-vacuity: the hazard is real); (b) after the exact `terraform state mv` sequence the runbook prescribes
  the plan shows no change; (c) a `moved` block under `-target` fails the plan (the ADR-119 2026-09-28 measurement, re-proved);
  (d) state serial moved by the expected amount and lineage unchanged. Labelled a state-address rehearsal, not evidence about hcloud
  provider behaviour. Registered in the CI job that has `terraform` (Phase 0.3); outside it, exit non-zero when `CI` is set (no
  silent skip).
- 5.2 New runbook `knowledge-base/engineering/operations/runbooks/workspaces-luks-t2-collapse-9357.md`: preconditions (PR #9348
  merged, checked with `gh pr view 9348 --json state`; a web-1 de-pet rebuild issue exists and is scheduled; push-apply pause check as in
  `workspaces-plaintext-forget.yml`; physical-id pins; re-read after #9348 merges because it edits the same surfaces), the ordered
  state-move commands, the post-move expectations, rollback (the reverse `state mv` from the same recipe; never write state to a file, the state
  holds `random_password.workspaces_luks`; unpause push-apply only after a clean plan), and the statement that the HCL and the single-use workflow are authored
  in the live operation's own PR.
- 5.4 Tracking: file the missing web-1 de-pet rebuild issue (milestone from the roadmap) and `gh issue edit 9357 --add-blocked-by <it>`; `gh issue edit 9357 --add-blocked-by 9348`; `gh issue edit 9372 --add-blocked-by 9377` (the only change to #9372: not dispatched, not closed); comments on #9356, #9357,
  #9358, #9377 listing what shipped and the dated, owned remainder (CPO condition 2) with the Phase 4/Post-Phase follow-ups below.
  (Issue edits are metadata, not infrastructure; run at ship time.)

### Phase 6 — Architecture, docs, compound

- 6.1 ADR-263 amendment (via `soleur:architecture`): D7 "web-host escrow credential and config split", R4 narrowed (not closed),
  T2 readiness status, the `doppler-config-inventory.txt` decision, option (b) rejected with its three reasons. ADR-148 gets a pointer:
  the arms exist, the refusal and its unblock list stand. ADR-068 gets the wrapper as the Phase-6 sourcing entry.
- 6.2 `knowledge-base/engineering/architecture/diagrams/model.c4`: amend the `doppler -> hetzner` edge description (the
  "header-escrow R2 S3 creds ... delivered via the SAME" sentence) for the web-class config split; no new element (R2 buckets are
  not modeled; Cloudflare and Doppler already are). Re-run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`
  and `plugins/soleur/test/c4-count-parity.test.sh`.
- 6.3 Stale comments swept in the same edit: `lb-weight-gate.sh`, `workspaces-luks-fresh-boot.tf`, `server.tf`, the
  `cron-egress-metadata-endpoint.test.sh` header.

## Files to Edit

- `apps/web-platform/infra/workspaces-luks-provision.sh`, `workspaces-luks-provision.test.sh`
- `apps/web-platform/infra/cron-egress-nftables.sh`, `cron-egress-resolve.sh`, `cron-egress-metadata-endpoint.test.sh`
- `apps/web-platform/infra/lb-weight-gate.sh` (comments only)
- `apps/web-platform/infra/workspaces-luks-fresh-boot.tf`, `cloud-init.yml`, `server.tf` (token reference + comment), `luks-monitor.sh`
- `apps/web-platform/infra/fresh-boot-parity.test.sh`, `workspaces-luks-fresh-boot.test.sh`, `luks-monitor.test.sh`
  (config-name pins), `workspaces-luks-loopback.test.sh`
- `tests/scripts/lib/web-host-replace-gate.sh`, `tests/scripts/test-web-host-replace-gate.sh`
- `plugins/soleur/test/terraform-target-parity.test.ts`, `.github/workflows/apply-web-platform-infra.yml` (`-target` lines only)
- `scripts/encryption-posture-ledger.json`
- `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md`, `ADR-148-...md`,
  `ADR-068-...md`; `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/operations/runbooks/web-host-replace.md`
- `knowledge-base/legal/article-30-register.md`, `knowledge-base/legal/compliance-posture.md` (and `article-30-2-register.md` if it names the bucket)

## Files to Create

- `apps/web-platform/infra/workspaces-luks-header-web.tf`, `workspaces-luks-header-web.test.sh`
- `apps/web-platform/infra/lb-weight-gate-with-marker.sh`, `lb-weight-gate-with-marker.test.sh`
- `apps/web-platform/infra/cron-egress-nftables.test.sh`
- `apps/web-platform/infra/workspaces-luks-t2-rehearsal.test.sh`
- `scripts/check-web-host-escrow-config.sh` (+ `.test.sh`)
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-t2-collapse-9357.md`
- `knowledge-base/project/specs/feat-one-shot-9356-luks-followups/tasks.md`

Verify before work: every path above with `git ls-files | grep` for edits and `test ! -e` for creates, and re-check each glob/filename
convention against a sibling (`hr-when-a-plan-specifies-relative-paths-e-g`).

## Open Code-Review Overlap

One open `code-review` issue names a planned path: #2197 (billing `SubscriptionStatus` refactor) matches `server.tf` as a
substring of an unrelated `apps/web-platform/server/...` path. Disposition: **Acknowledge** — different concern, no file in common
with the infra `server.tf` edit (comment-only). All other planned files: none.

## User-Brand Impact

- **If this lands broken, the user experiences:** a replaced or rebooted web host whose workspace volume is formatted, left
  unopened, or mounted from the wrong device, so a user's checked-out repository is destroyed or reads as an old snapshot with no
  recovery (the sole copy lives on web-1's LUKS volume); or a web-2 whose boot fails closed on a mis-pointed Doppler config.
- **If this leaks, the user's data is exposed via:** the web-host fresh-boot token in user_data (it reads the LUKS passphrase shared
  with web-1, and, before this change, web-1's R2 escrow pair); a seam or PATH hijack of the root provisioner; a link-local address
  admitted to the container egress allowlist, which would let a container read user_data from the metadata endpoint.
- **Brand-survival threshold:** `single-user incident`

CPO signed off at plan time (conditions: web-1 refusal tested with arms active; deferred steps carry dated, owned tracking; header
restore drill added, which is Phase 4.4). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what: the existing provisioner evidence rows (SOLEUR_WORKSPACES_LUKS_PROVISION, journald tag workspaces-luks-reopen) and the daily luks-monitor probe row, now read from the web-class config; plus the escrow-split contract check
  cadence: per instance for the readiness row, daily for the probe row, per CI run for the contract check
  alert_target: Sentry web-host-luks-boot-fatal (pages) and web-host-luks-boot-warning (NoOne) issue alerts; the workspaces-luks-verify web-2 leg files a GitHub issue on RED
  configured_in: apps/web-platform/infra/sentry/issue-alerts.tf and .github/workflows/workspaces-luks-verify.yml (unchanged by this PR)
error_reporting:
  destination: Sentry via soleur-boot-emit stages workspaces_luks_provision_<arm>; a lock timeout reuses stage workspaces_luks_provision_config
  fail_loud: a lock timeout, a refused seam (exit 2), a pin mismatch on the new config name, and a link-local CIDR each exit non-zero with a logged reason row
failure_modes:
  - mode: web-2 monitor reads the old config after the split and its probe goes dark or false-red
    detection: scripts/check-web-host-escrow-config.sh --static census in CI; the host-timer-dark alert counts missing probe rows
    alert_route: CI red on the PR; Sentry host-timer-dark for a live host
  - mode: web-class escrow pair absent when the first birth runs
    detection: escrow=missing in the readiness row, which withholds the soak marker; live mode of the readiness checker as the #9372 precondition
    alert_route: workspaces_luks_provision_escrow warning stage; GitHub issue from the verify web-2 leg
  - mode: a resolver tick admits a link-local record
    detection: cron-egress-nftables.test.sh and the resolver filter test; resolver logs the dropped host
    alert_route: CI red; cron-egress-alarm@ on a failed tick
  - mode: replace-gate arm drift (an arm deleted or the refusal removed)
    detection: the mutation rows in test-web-host-replace-gate.sh and the target-parity test, both in CI
    alert_route: CI red on the PR
logs:
  where: journald (workspaces-luks-reopen tag) shipped to Better Stack by Vector; CI logs for the suites
  retention: Better Stack retention; CI log retention
discoverability_test:
  command: bash scripts/check-web-host-escrow-config.sh --static
  expected_output: escrow-split-contract: ok
```

## Encryption Posture

```yaml
at_rest:
  - store: cloudflare_r2_bucket.workspaces_luks_header_web
    mechanism: provider-managed:Cloudflare-R2-SOC2-Type-II
    evidence: Cloudflare R2 encrypts objects at rest with AES-256-GCM (developers.cloudflare.com/r2/reference/data-security/); Cloudflare holds an AICPA SOC 2 Type II attestation with R2 in scope (https://www.cloudflare.com/trust-hub/compliance-resources/soc-2/), retrieved on the ledger row's date, copied from the existing workspaces_luks_header row
    defends_against: physical-media compromise of the escrowed LUKS headers in Cloudflare's infrastructure
    does_not_defend: a leaked bucket-scoped R2 token (it can overwrite this bucket's own objects); a LUKS header alone cannot open a volume without the passphrase, which web-2's token also reads (shared-passphrase residual, ADR-263)
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:provider-managed at-rest; no customer-side live probe of Cloudflare disk encryption
in_transit:
  - connection: web host (curl SigV4) -> Cloudflare R2 S3 endpoint
    enforced_at: apps/web-platform/infra/workspaces-luks-provision.sh:_escrow (https:// shape check on the endpoint, curl default verification)
    tls: TLS 1.2+ as negotiated by curl against the Cloudflare endpoint
    cert_verification: on
    does_not_defend: a host-level attacker who already holds the credential pair
    disclosed_as: not-publicly-claimed
  - connection: web host (doppler CLI) -> Doppler API for prd_workspaces_luks_web
    enforced_at: apps/web-platform/infra/workspaces-luks-provision.sh:_dget
    tls: TLS 1.2+ (Doppler CLI default)
    cert_verification: on
    does_not_defend: a holder of the scoped token, which also resolves inherited prd secrets (ADR-164 census)
    disclosed_as: not-publicly-claimed
```

## Guard Contract

### Guard 1 — provisioner hardening properties

**Property.** The provisioner takes an exclusive lock before its first side effect, runs only pinned-PATH commands in production, refuses its test seam on a cloud-init host, and replaces fstab, crypttab, the docker drop-in and the intent file only through a same-directory temp file that is fsynced before an atomic rename.

**Assembly.** Every write site in `workspaces-luks-provision.sh` that names `$FSTAB`, `$CRYPTTAB`, `$DROPIN` or `$INTENT` (all must flow through `_install_file`); the single seam block (`WORKSPACES_PROVISION_TEST_SEAM`) and its one call to `_seam_allowed`; the single `flock` call site, which must precede `_secure_file "$ENVFILE"`; the single `PATH=` assignment, which must precede the first external command. Members drift: the guard is a static census over the script (no direct `>`, `>>` or bare `mv` to those four variables) plus behavioural cases, not a list of today's lines.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace `_install_file` for the docker drop-in with a direct `printf > "$DROPIN"` | RED |
| 2 | Drop the `sync` of the temp file (or of the directory) in `_install_file` | RED |
| 3 | Add a second writer to `$CRYPTTAB` (a trailing `>>`) after a compliant first | RED |
| 4 | Move the `flock` call after the first `_secure_file` / mkdir side effect | RED |
| 5 | Delete the `PATH=` pin, and separately set it only after the first external command | RED |
| 6 | Make `_seam_allowed` return 0 unconditionally, and separately let the marker path come from an env var | RED |
| 7 | The suite runs zero cases or the new cases are deleted (`WLP_DROP_CASE`, case-set floor) | RED |
| H1 | Harness: stubs record nothing (`WLP_STUB_NOLOG=1`) so the lock and ordering assertions see no calls | RED |
| H2 | Must-PASS: a crypttab that already holds the canonical line plus an unrelated mount line, mode 0644, is preserved byte for byte and mode | GREEN |

### Guard 2 — container egress never admits a link-local address

**Property.** No rule or set element the egress loader renders, and no address the resolver adds, can match 169.254.0.0/16.

**Assembly.** Three feeders into `SOLEUR-EGRESS`: the static CIDR file through `is_valid_ipv4_cidr` (Phase 1.5 `add element`), the resolver's A-record additions to `@soleur_egress_allow`, and the literal rules of the Phase 3 heredoc; plus the two allowlist files the existing text suite already walks. The chokepoint for the first two is one overlap predicate, shared or duplicated with a parity assertion.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the overlap check from `is_valid_ipv4_cidr` | RED |
| 2 | Resolver stub returns `169.254.169.254` for an allowlisted host and the filter is removed | RED |
| 3 | A second element in the CIDR file (`169.254.0.0/16`) after a compliant first line | RED |
| 4 | The stub `nft` log is empty (the loader never ran) while the suite reports pass | RED |
| 5 | Add a literal `ip daddr 169.254.169.254 accept` rule to the Phase 3 heredoc | RED |
| H1 | Harness: the assertion that no rendered line contains `169.254` is run against a log seeded with such a line | RED |
| H2 | Must-PASS: an unrelated CIDR (203.0.113.0/24) and a resolver answer of 203.0.113.7 install normally | GREEN |

### Guard 3 — web-class paths never read web-1's config

**Property.** Every path executed on a web-class host names `prd_workspaces_luks_web` as its Doppler config and none names `prd_workspaces_luks`.

**Assembly.** `cloud-init.yml`, `workspaces-luks-provision.sh`, `workspaces-luks-reopen.sh`, `luks-monitor.sh` (the key read; the heartbeat read is excluded by name because the standby profile skips it), `workspaces-luks-fresh-boot.tf` (the token's `config`), and anything the bake copies onto fresh hosts (`soleur-host-bootstrap.sh` family); web-1-only paths (`workspaces-luks.tf` installer, `luks-monitor-token-refresh.sh`) are the explicit exclusion list, itself pinned. The census enumerates every `--config` / `WORKSPACES_DOPPLER_CONFIG` occurrence under `apps/web-platform/infra/`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert `cloud-init.yml`'s printf to `prd_workspaces_luks` | RED |
| 2 | Hardcode `--config prd_workspaces_luks` in a new web-class script | RED |
| 3 | Re-point the fresh-boot token back to `prd_workspaces_luks` | RED |
| 4 | Add a second `--config prd_workspaces_luks` read to `luks-monitor.sh` after the parameterized one | RED |
| 5 | The census enumerates zero occurrences (path glob broken) | RED |
| H1 | Harness: the census is run against a tree with one injected violation and must report it | RED |
| H2 | Must-PASS: a comment mentioning `prd_workspaces_luks` in a web-class file does not trip the census | GREEN |

### Guard 4 — replace gate: arms active, refusal intact

**Property.** For key web-1 the gate aborts on every plan while the refusal constant is set, and, with it cleared, passes only a plan that replaces exactly web-1, creates the LUKS attachment, updates the apex record in place with changed content, and touches nothing else.

**Assembly.** The single `web_host_replace_gate` function, its single `_WEB_HOST_REPLACE_ALLOW` definition plus the keyed extension, both requirement arms, and the call sites in `apply-web-platform-infra.yml` (the workflow's fail-fast copy of the refusal) bound by `terraform-target-parity.test.ts`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the LUKS-attachment requirement arm | RED |
| 2 | Delete the apex-record requirement arm; separately allow `["delete","create"]` on `cloudflare_record.app` | RED |
| 3 | Add `hcloud_volume.workspaces_luks` to the keyed allow-set | RED |
| 4 | Remove the refusal while the arms are active (the "arms became the relaxation path" mutation) | RED |
| 5 | Apply the arms to key web-2 (a web-2 plan touching `workspaces_luks` must abort) | RED |
| 6 | A plan that is missing `actions` on the apex entry | RED |
| H1 | Harness: run the complete web-1 plan through a gate whose arms are removed; the suite must notice | RED |
| H2 | Must-PASS (arms-only fixture, NOT a safety claim): an arms-complete web-1 plan with the refusal constant cleared in a subshell, and a differently ordered equivalent plan JSON | GREEN |

### Guard 5 — the marker reaches the gate through one seam

**Property.** `WORKSPACES_LUKS_CUTOVER_AT` enters `lb-weight-gate.sh`'s environment only via `lb-weight-gate-with-marker.sh`, from the exact config `prd_workspaces_luks_marker` (provenance is not asserted: a value planted in the `prd` root shows through the branch config, as ADR-263 records).

**Assembly.** Every script and workflow that invokes `lb-weight-gate.sh` or exports the marker name; the wrapper's single `doppler` call; the constants parity with `scripts/lib/web2-luks-rows.sh`. `*.test.sh` files are the explicit exclusion.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | The wrapper stops unsetting a caller-supplied marker | RED |
| 2 | The wrapper reads `--config prd` or drops `--config` | RED |
| 3 | A second script invokes the gate directly | RED |
| 4 | Doppler transport error is treated as "absent" and the gate runs | RED |
| H1 | Harness: stub `doppler` records nothing; the argv assertion must fail | RED |
| H2 | Must-PASS: a valid marker 4 days old yields the gate's authorized-shape exit 0 | GREEN |

### Guard 6 — the T2 rehearsal is not vacuous

**Property.** The rehearsal demonstrates, in one run, that the collapsed configuration destroys the sole-copy stand-in without the state move and plans no change after it.

**Assembly.** The mini-root fixture, the `terraform state mv` sequence copied verbatim from the runbook (one source of truth read by the test), and the plan classifier.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Skip the state move: the plan must show destroy and the suite must report the hazard as demonstrated | RED if the destroy is absent |
| 2 | Perform only one of the two moves (volume without attachment) | RED |
| 3 | Add a second keyed member after a compliant first (a `web-2` key must not be disturbed) | RED |
| 4 | The runbook's command list and the test's list diverge | RED |
| H1 | Harness: classifier fed a plan with a delete the suite must flag | RED |
| H2 | Must-PASS: the same state with an unrelated attribute difference plans no destroy | GREEN |

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-263 (status stays `adopting`) with D7: web-host escrow credential and Doppler config are split from web-1's
(`prd_workspaces_luks_web`, bucket `soleur-workspaces-luks-header-web`); R4 is narrowed to the shared passphrase; option (b) bucket lock
is recorded as rejected with its three reasons; T2's readiness conditions and the offline rehearsal are recorded. This is a task in
Phase 6.1 (via `soleur:architecture`), not a deferred issue. Pointers added to ADR-148 (arms exist, refusal stands) and ADR-068 (wrapper).

### C4 views

All three of `model.c4`, `views.c4`, `spec.c4` are in scope for review (model.c4 is ~209 KB; the relevant surfaces were enumerated by
grep for `header`, `escrow`, `WORKSPACES_HEADER`, `prd_workspaces_luks_marker`, `workspacesVolume`, and the two small files read in
full). Enumeration: (a) external human actors: only `founder` (gated dispatch approver), unchanged; (b) external systems: Cloudflare (R2),
Doppler, Hetzner, GitHub, Better Stack, Sentry are all modeled, no new vendor; (c) containers/data stores: the R2 header bucket is not a
modeled element (it appears in edge prose), the new bucket follows suit; (d) access relationships: the `doppler -> hetzner` edge prose
names the shared escrow credential delivery and is the one description this change falsifies, so it is edited (Phase 6.2). No `views.c4`
include changes. Validation: the two C4 tests plus `c4-count-parity.test.sh`.

### Sequencing

The ADR describes the target state with its existing `adopting` status; it is authored in this PR.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/workspaces-luks-header-web.tf` (new), `workspaces-luks-fresh-boot.tf`, `cloud-init.yml`, `server.tf` (the token reference). Providers: `cloudflare`
`~> 4.0` (alias `cloudflare.r2`), `DopplerHQ/doppler` `~> 1.21`, both already pinned. No new sensitive variable: the R2 pair is not
a Terraform input in this PR. Any later Terraform-minted pair would need a new narrowly scoped provider alias and an operator-provisioned
`TF_VAR` token (ADR-065, `hr-tf-variable-no-operator-mint-default`); that is the reason the mint is deferred rather than designed here.

### Apply path

(b) the existing push-apply `-target` list plus idempotent additions: every change is a create (bucket, config, three secrets, a NEW
fresh-boot token); nothing is replaced or destroyed, so the destroy guard demands no `[ack-destroy]`. The old token resource stays until a later
acknowledged retirement. Expected downtime: none. Blast radius: web-1 untouched (`ignore_changes = [user_data]`,
its own config). The new bucket and config are in the `-target` list in the same PR, or the merge would be a silent no-op.

### Distinctness / drift safeguards

`prd_workspaces_luks_web` is a branch config of `prd` distinct from `prd_workspaces_luks` and from the marker config; the contract check asserts
web-1's R2 pair names are absent from the `prd` root so a branch config cannot inherit them. State holds `random_password.workspaces_luks`
in plaintext (existing), now referenced by two secrets. `prevent_destroy` on the bucket.

### Vendor-tier reality check

R2 free-tier limits are not engaged (a single small object per host). No Better Stack resource is added, so the paid-tier gate does not apply.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (sign-off only)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Scoping sound. Risks adopted: the `luks-monitor.sh` hardcoded config (census + parameterization, Phase 3.4/3.5 and Guard 3); the
#9377-before-#9372 ordering (blocked-by edge); the shared passphrase making the split partly cosmetic (stated in the ADR); put all new resources
in a new file (A11 and #9348); keep the arms from becoming a relaxation path (Guard 4 row 4); seam detection by a root-owned marker, not an env var (Phase 1.3);
keep the wrapper as the only Doppler reader (Phase 2). Suggestion not adopted: adding the new config to `doppler-config-inventory.txt` (the terraform-architect
review and the marker-config precedent say a new name forces floor edits and a drift-read token; recorded in the ADR instead).

### Legal (CLO)

**Status:** reviewed
**Assessment:** No DPIA or transfer-assessment trigger. Edit `article-30-register.md` (PA-1 (e) bucket note, R4 residual row) and
`compliance-posture.md` (web-2 and Cloudflare rows); read `article-30-2-register.md`; no `docs/legal/**` edit. Do not describe web-2 as encrypted
before #9372. Verify isolation before asserting it (the contract check's `prd`-root absence assertion). `soleur:gdpr-gate` is not deferred to a later plan
(single-user-incident threshold): `deepen-plan` runs it advisory-only with its findings recorded in this plan, because its optional write to
`compliance-posture.md` falls outside this planning phase's file scope; the CLO assessment above already covers the same surface.

### Product (CPO)

**Status:** reviewed (no UI surface; Product/UX Gate not applicable)
**Assessment:** Signed off at `single-user incident` with two conditions (refusal tested with arms active; deferred steps tracked with dates and owners) and one
addition adopted as Phase 4.4 (header-restore drill). Underweighted risk named: header-backup coverage never proven restorable; a standing read-back check is a
follow-up below.

## Acceptance Criteria

### Functional

- [ ] `bash apps/web-platform/infra/workspaces-luks-provision.test.sh` exits 0 with the new cases (case-set floor 20) and every Guard 1 mutation row caught.
- [ ] `bash apps/web-platform/infra/cron-egress-nftables.test.sh` exits 0 and its Guard 2 rows are caught; `bash apps/web-platform/infra/cron-egress-metadata-endpoint.test.sh` still reports its exactly-17 plant rows.
- [ ] `bash apps/web-platform/infra/lb-weight-gate-with-marker.test.sh` (including its census section, which passes or fails by exit status) and `bash apps/web-platform/infra/lb-weight-gate.test.sh` exit 0.
- [ ] `bash scripts/check-web-host-escrow-config.sh --static` prints `escrow-split-contract: ok`; `bash apps/web-platform/infra/workspaces-luks-header-web.test.sh`, `fresh-boot-parity.test.sh`, `workspaces-luks-fresh-boot.test.sh`, `luks-monitor.test.sh`, `workspaces-luks.test.sh` and `workspaces-luks-header.test.sh` all exit 0.
- [ ] `bash tests/scripts/test-web-host-replace-gate.sh` exits 0; a web-1 plan with every arm satisfied and the refusal active still aborts; `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes.
- [ ] `bash apps/web-platform/infra/workspaces-luks-t2-rehearsal.test.sh` exits 0 with `terraform` on `PATH`, exits non-zero (never skips) when `terraform` is absent, and is listed in the workflow job Phase 0.3 selected (`grep -n workspaces-luks-t2-rehearsal .github/workflows/*.yml`).
- [ ] `python3 scripts/lint-encryption-posture.py --repo-sweep` passes with the new bucket ledgered; `python3 scripts/lint-guard-contract.py` passes on this plan.
- [ ] `plugins/soleur/test/workflow-file-size.test.ts` passes; `wc -c .github/workflows/apply-web-platform-infra.yml` is under 490,000 and recorded in the PR body; the cloud-init user_data size test passes.
- [ ] C4 tests (`c4-code-syntax`, `c4-render`, `c4-count-parity`) pass after the `model.c4` edit.

### Non-functional / process

- [ ] Phase 0 measurements (workflow bytes, user_data headroom, suite wall time, sed-fork count, terraform CI job) are in the PR body.
- [ ] No `terraform apply`, no `workflow_dispatch`, no Doppler write and no Cloudflare token mint was run by this work; the PR body states it.
- [ ] PR body: `Closes #9378`; `Ref #9356`, `Ref #9357`, `Ref #9358`, `Ref #9377`; #9372 untouched and not closed.
- [ ] The de-pet rebuild issue is filed; `gh issue edit 9357 --add-blocked-by 9348` and `--add-blocked-by <de-pet issue>`, and `gh issue edit 9372 --add-blocked-by 9377` are done (`gh issue view 9357 --json` shows the edges), and each of #9356/#9357/#9358/#9377 has a comment listing the shipped parts and the dated, owned remainder.
- [ ] Review runs `soleur:engineering:review:user-impact-reviewer` (threshold single-user incident).

## Test Scenarios

- Given a second provisioner invocation while the first holds the lock, then it waits and, after the bound, exits 10 with a logged reason and no writes.
- Given a cloud-init host marker present, when the seam env vars are set, then the provisioner exits 2 before reading any file.
- Given a kill between the fstab temp write and the rename, then `/etc/fstab` is unchanged and the next run overwrites the stale temp file.
- Given an egress CIDR file listing `169.254.0.0/16`, then the loader dies rc 1 and no `add element` reaches `nft`.
- Given a resolver answer in 169.254.0.0/16 for an allowlisted host, then the address is not added and the tick is additive-only.
- Given Doppler returns "not found" for the marker, then the wrapper runs the gate with the variable unset and the gate reports `B_workspaces_luks_marker_absent`.
- Given a web-1 replace plan carrying every arm, when the refusal is active, then the gate aborts naming the refusal; when the refusal is cleared in a test subshell and an arm is removed, then it aborts naming that arm.
- Given a LUKS volume whose mapper holds a populated ext4 filesystem, then the provisioner records `luks_arm=opened` and makes no `luksFormat`, `mkfs` or `wipefs` write.
- Given a zeroed LUKS header and a prior `luksHeaderBackup`, then `luksHeaderRestore` plus `luksOpen` returns the sentinel file (real loop device).
- Given the T2 mini-root without the state move, then the plan shows destroy+create of the sole-copy stand-in; with the move, no change.
- Given a web-class tree where `luks-monitor.sh` reads `--config prd_workspaces_luks`, then the census fails.

## Deferred, gated follow-ups (tracked; none executed here)

| Item | Gate | Tracked in | Owner | Re-evaluate when |
|---|---|---|---|---|
| Mint the web-class R2 pair and first signed PUT/HEAD | credential mint, own approval | #9377 | founder/operator via the gated route | before #9372 dispatches |
| Live rehearsal of web-host-replace on web-2 with verifier | #9372 complete, environment approval | #9356 | founder/operator | after web-2's first green probe row |
| Remove the web-1 refusal + extend the workflow `-target` set | rehearsal evidence + T2 topology | #9356 | engineering | after #9357's live move |
| T2 HCL collapse + single-use state-move workflow | #9348 merged, de-pet scheduled, push-apply pause, own approval | #9357 | engineering | after #9348 lands |
| Run the live-mode escrow check as a precondition on EVERY route that can create a web host (web-host-create, web-host-replace, the #9372 rebirth, any apply that can create the web-2 server) | one gate edit per route, own PR | #9377 | engineering | with the live mint |
| Wire the wrapper into the flip orchestrator | orchestrator planned (ADR-068 Phase 6) | #9358 | engineering | when the orchestrator is planned |
| Distinct passphrase per host class: explicit go/no-go (a one-way door: after web-2 formats with the shared key, fixing it is a re-key) | decision recorded before #9372 dispatches | #6167 (comment) and #9377 | founder + engineering | before #9372 |
| Retire the unused `workspaces_luks_fresh_boot` token resource and the stale `prd_workspaces_luks` read path | acknowledged destroy (`[ack-destroy]`) in its own PR | #9377 | engineering | after the first web-2 birth on the new token |
| Standing header-backup read-back and restore check for web-1 | needs a read credential on web-1's bucket | new issue filed at ship (Phase 4 milestone) | engineering | after Phase 4 lands |

## Risks

- **HCL/state ordering for T2.** State-move-first plans destroy the keyed address against old HCL; HCL-first plans destroy the singleton. No merge order is safe,
  which is why the HCL waits for the live operation and why the rehearsal exists. Never add a `moved` block on this root (fails every `-target` plan).
- **Merge-time apply of Phase 3.** It runs through the existing push-apply. A missing `-target` entry makes it a silent no-op; an extra replace of
  `random_password.workspaces_luks` would rotate both key copies. The parity test and the ledger lint guard the first; the plan forbids the second.
- **Workflow byte cap.** 482,241 of 490,000; Phase 3.6 adds roughly 400-600 bytes. If it overruns, move prose to `apply-web-platform-infra-job-rationale.md` (precedent), never drop targets.
- **Stub fidelity.** The nft test proves the rendered text, not kernel semantics; the terraform_data rehearsal proves state addresses, not hcloud behaviour. Both are labelled so.
- **R2 derivation conflict.** Docs and the repo's measurement disagree; nothing in this PR depends on either.
- **Partial push-apply.** A first apply that creates the `prevent_destroy` bucket and then fails on Doppler resources is safe to re-run (creates are idempotent in state); if the bucket exists in R2 but not in state, import it before re-running. Never `-replace` `random_password.workspaces_luks`.
- **Re-read after #9348.** #9348 edits the same surfaces (`workspaces-luks.tf`, ledger row, comments); re-read the `-target` list additions and the T2 runbook after it merges.
- **Shared passphrase.** web-2's token still reads web-1's passphrase; the split closes header overwrite/delete only.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or placeholder fails `deepen-plan` Phase 4.6; this one is filled and carries the threshold.
- The provisioner suite's case-set and assertion floors move together with the `case_raw_formats_once` split; update the floor, the case-set assertion and every
  `WLP_ONLY_CASES` in one commit and re-drive each mutation row restricted vs full.
- `fresh-boot-parity.test.sh` check 17d must keep pinning web-1's installer to `prd_workspaces_luks`; only the web-class pins move.
- Do not add the `luks-monitor.sh` config read as an env var in `/etc/default/luks-monitor`: the boot env file is the single source and cloud-init bytes are scarce.
- Any new `doppler secrets get` in a web-class path must use the single-secret `--plain --config` form (CWE-522), never `doppler run`/`secrets download`.
- A fail-closed refusal's natural repair is tried before shipping: the seam refusal's repair (delete the cloud-init marker as root) is root-equivalent and recorded as such; the gate refusal's repair (clear the constant) is Guard 4 row 4; a stuck lock's repair (delete the lock file) is harmless because the lock is re-taken on the next run.
- Plan prose here avoids operator-actor plus infrastructure-imperative pairings (`lint-infra-no-human-steps.py`); keep it that way when editing.

## Plan Review Disposition (Phase: plan-review, five-seat panel)

Panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow (single-user-incident escalation). The named CEO/design/devex panel
was not re-run: CTO, CLO and CPO had already reviewed this plan's scope in Phase 2.5 and their conditions are folded in.

**Applied (mechanical):** the Phase 3 token re-point became a NEW token resource (a ForceNew replace would halt the push-apply destroy guard);
provisioner accepts both config names while the token scope enforces isolation; `luks-monitor.sh` parsing is new code with a fallback and the
heartbeat read stays on the old config; `flock` command check, `exec` open check and reorder note; euid-0 carve-out for the seam refusal; five (not
four) names in the readiness checker and a `prd`-root advisory scan; marker wrapper tells not-found from transport error without parsing stderr;
census as a pass/fail suite section; generated shard TSVs not hand-edited; exact case/assertion floors named; `check-t2-collapse-readiness.sh`
and `verify-web-host-replace-rehearsal.sh` cut (redundant with the blocked-by edge and the inline runbook query); P7 added for the header-restore drill;
rehearsal evidence scope stated; de-pet issue to be filed; T2 rollback outlined; partial-apply and re-read-after-#9348 risks added; arms comment restates
the three non-plan blockers.

**Surfaced, not applied (taste / operator-requested scope; kept as specified by the five issues):** the DHH, simplicity and architecture seats
recommend deferring the #9358 wrapper (no caller), the #9356 gate arms (dead code behind the refusal), the #9357 `terraform_data` rehearsal suite, and the
`case_raw_formats_once` split. All four map to items the issues name explicitly, so dropping them is a scope change for the operator. Recorded in
`knowledge-base/project/specs/feat-one-shot-9356-luks-followups/decision-challenges.md`. A single shared overlap predicate across the egress loader and the
resolver was suggested; they ship as two baked scripts with separate delivery, so the plan keeps two copies with a parity assertion.
