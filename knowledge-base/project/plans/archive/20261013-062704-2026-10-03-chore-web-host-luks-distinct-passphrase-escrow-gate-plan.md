---
title: "infra: distinct web-host LUKS passphrase, rotation HALT, and a hard escrow gate on every web-host birth route"
date: 2026-10-03
slug: chore-web-host-luks-distinct-passphrase-escrow-gate
branch: feat-one-shot-9377-web-escrow-distinct-passphrase
issue: 9377
type: chore
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
closes: []
refs: [9377, 9372, 9397]
lane: cross-domain
---

# infra: distinct web-host LUKS passphrase, rotation HALT, and a hard escrow gate on every web-host birth route

## Enhancement Summary

**Deepened on:** 2026-10-03
**Agents used:** learnings-researcher, CTO and CLO domain consults, plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow), then deepen-plan passes by security-sentinel, terraform-architect, observability-coverage-reviewer and user-impact-reviewer. Mechanical gates (User-Brand Impact, Observability, Encryption Posture, Guard Contract lint, Scope Check, PAT sweep, rule-id and issue-state checks) were run directly and pass.

### Key improvements
1. **Sequencing bug fixed.** The live mint cannot precede the push-apply: the web-class config exists only after it. Order is now reviewed push-apply, then mint and isolation proof, then preflight, then #9372; this PR must merge before the push-apply is enabled.
2. **Census predicate corrected.** A bare mention of `hcloud_server.web[` matches three non-creating jobs; the predicate is a `-target`/`-replace` argument.
3. **Simpler mechanisms.** The `--token-env` flag and the dedicated cross-gate census were cut; a ten-line reusable wrapper and per-gate removal rows replace them. The wrapper reads one secret instead of running `doppler run`.
4. **Reach pinned.** `WEB_HOST_REPLACE_PRESERVED` and a job-reach row cover every dispatch job for the new password and the web key copy.
5. **Impact section completed** with passphrase loss, state rewind, false-positive HALT, delayed recovery, token exposure and the pre-split-token carve-out; observability failure modes now cite their layer.

### New considerations discovered
- A first create cannot be told from a state loss; recorded as a known limit.
- `prevent_destroy` on a tainted first create needs a documented recovery.
- Taste and user-challenge items (fail-closed birth on missing escrow, preflight before the environment approval) are in `knowledge-base/project/specs/feat-one-shot-9377-web-escrow-distinct-passphrase/decision-challenges.md`.

## Overview

Offline-only follow-up to #9397 (the escrow credential split) for issue #9377 (`Ref`, never `Closes`: the
live mint and the pre-split token retirement stay open on that issue). It is a prerequisite of the gated
live web-2 LUKS conversion (#9372) and performs **no live step**: no apply, no workflow dispatch, no
Doppler write, no Cloudflare or R2 mint, and `apply-web-platform-infra.yml` stays disabled. The PR body
must say so, and must also state the one automatic merge-time effect (see "Merge-time effects" below).

Two decisions were taken by the issue owner and are recorded here, in the ADR-263 addendum, and on #9377:

- **(A) Distinct passphrase per host class.** `prd_workspaces_luks_web` gets its OWN passphrase from a new
  `random_password.workspaces_luks_web`, not a copy of `random_password.workspaces_luks` (web-1). Web-1 keeps
  its own. A holder of the web-class token can no longer read web-1's passphrase. This plan also decides
  (and records) that a **non-bypassable HALT on rotating either workspaces passphrase in the push-apply is
  needed**, and implements it.
- **(B) Enforce the escrow readiness check in the workflow, on every route that can create a web host**
  (`web-host-create`, `web-host-replace`, and the future web-2 rebirth), instead of a person-run runbook step,
  and make `escrow=missing` on a web-class birth page a person.

Plus the cheap hardening leftovers from item 6 of the #9377 follow-up comment: shape-validate the R2 key
id/secret before the curl config stream, route the Sentry op `resolve_link_local`, and name the web key copy in
the cutover gate's `luks_passphrase_touched` clause.

The follow-up PR for the single-use web-2 rebirth workflow (#9372 scope) comes after this one and is NOT part
of this task. This plan only guarantees that workflow cannot be written without the escrow gate (Guard 3).

### Merge-time effects (what the PR body must state)

| Surface | State | Effect of merging this PR |
|---|---|---|
| `apply-web-platform-infra.yml` | `disabled_manually` (measured: `gh api repos/jikig-ai/soleur/actions/workflows`, newest run 2026-10-01 21:19Z, none since the #9397 merge) | None. Nothing in the web-class Doppler config, token or secrets from #9397 is applied yet, so the passphrase change is a first CREATE when the workflow is eventually enabled. |
| `apply-deploy-pipeline-fix.yml` | `disabled_manually` | None. |
| `apply-sentry-infra.yml` | active, path-filtered on `apps/web-platform/infra/sentry/**` | Applies in place the routing change of 3 EXISTING `sentry_alert` rules (no create, no destroy). Requested by (B); it is not one of the forbidden live steps, but it is an automatic apply and is disclosed. |
| Baked host scripts (`workspaces-luks-provision.sh`) | change `host_scripts_content_hash` | Reaches no running host (`user_data` and the image are ignored on live hosts). A new image must carry the script before any #9372 birth; the coherence preflight enforces it. |

## Research Insights

**Premise validation (Phase 0.6).** Held: #9377 OPEN, #9372 OPEN (blocked-by #9377), #9397 merged
(`c6ae165d0e`, 2026-10-03) and shipped every artifact this plan edits. Measured on `origin/main`:
`scripts/check-web-host-escrow-config.sh` exists and is documented as "step 0" of both runbooks and "NOT
enforced by any workflow"; `workspaces-luks-header-web.tf` writes `random_password.workspaces_luks.result`
into the web-class key secret; the replace gate (`tests/scripts/lib/web-host-replace-gate.sh`) and the recut
gate already name `doppler_secret.workspaces_luks_web_key` in `luks_passphrase_touched`, the cutover gate does
not. The destroy-guard counter `luks_passphrase_rotations` covers ONLY the inngest pair
(`random_password.inngest_redis_luks`, `doppler_secret.inngest_redis_luks_key`). Nothing was stale. ADR corpus
(mechanism check): no ADR lists a per-host-class passphrase as rejected; the 2026-10-01 plan's Cut List dropped it
only as "not in any issue's property list" and ADR-263 recorded it as the accepted shared-passphrase residual.
The owner's decision reverses that acceptance for new web-class births.

**Property List (Phase 0.6b).**

1. A leak of the web-class passphrase or of the web-class token does not yield web-1's passphrase.
2. No merge-time apply can rotate or drop either workspaces passphrase (or its Doppler copy) without a
   non-ackable stop, so a host never reboots into a header its Doppler key no longer opens.
3. No workflow route that the census can see (a job that applies against `hcloud_server.web[...]`) can create or replace a web host without the escrow readiness check passing first.
4. A web-class birth that ends with `escrow=missing` reaches a person.
5. Nothing outside a strict charset reaches the curl config stream that carries the R2 credential pair.
6. The Sentry op `resolve_link_local` reaches a person; the cutover gate names the web key copy.

**Cut List (Phase 0.6b).**

- A separate `sentry_alert` for `escrow=missing` -> property 4 -> moving the stage between the two existing rules
  buys it with no new frequency slot, create gate or import/forget bijection (CTO concurred).
- `lifecycle { prevent_destroy }` on web-1's `random_password.workspaces_luks` -> property 2 -> the HALT covers it,
  and `workspaces-luks.test.sh` A11 pins that file's exact content. (Applied to the NEW password only.)
- Comparing the two passphrases by value in CI (hash-compare) -> property 1 -> would give a CI job read access to web-1's
  LUKS key, widening exposure to prove something Terraform already guarantees (two independent `random_password`
  resources). Distinctness is enforced structurally (Guard 1).
- A minted read-only Doppler token for the preflight -> property 3 -> needs a live mint; deferred with a tracking issue.
- Census proofs for the provisioner write census / escrow census / marker census, and the runtime link-local-in-live-chain
  assert (`cron-egress-postapply-assert.sh`) -> item 6 remainder, not named by the owner's "where cheap" list ->
  stay on #9377.
- A dedicated cross-gate census suite (plan review: simplicity + DHH; CTO had suggested it, the per-gate `gate_mutate_and_check` rows plus the job-reach row cover the same ground) -> property 2 -> per-gate rows.
- A `--token-env` flag on the checker (plan review) -> property 3 -> a ten-line wrapper script that the birth routes share.
- Whole-tree plus file-scoped duplicate assertions of the password shape (plan review) -> property 1 -> W-tests own the shape, the checker owns the whole-tree census.
- Live R2 mint, isolation proof both ways, retiring the pre-split token -> gated live work, stays on #9377.

**Relevant files** (all verified present): `scripts/check-web-host-escrow-config.sh` (+ `.test.sh`),
`apps/web-platform/infra/{workspaces-luks-header-web.tf,workspaces-luks-header-web.test.sh,workspaces-luks-fresh-boot.tf,
workspaces-luks-provision.sh,workspaces-luks-provision.test.sh,luks-monitor.sh,cron-egress-resolve.sh}`,
`apps/web-platform/infra/sentry/{issue-alerts.tf,alert-reference.json}`,
`apps/web-platform/test/{sentry-fresh-boot-luks-alert-op-contract.test.ts,sentry-egress-ghcr-deny-alert-op-contract.test.ts}`,
`.github/workflows/apply-web-platform-infra.yml` (jobs `apply`, `web_host_create`, `web_host_replace`),
`tests/scripts/lib/{destroy-guard-filter-web-platform.jq,web-host-replace-gate.sh,workspaces-luks-recut-gate.sh,workspaces-luks-cutover-gate.sh}`
and their suites, `plugins/soleur/test/{terraform-target-parity.test.ts,workflow-file-size.test.ts}`.

**Institutional learnings applied** (paths verified present):
`2026-09-24-a-second-apply-workflow-could-perform-the-rotation-without-its-gate.md` (a rotation resource can be
reached by more than one workflow; enumerate every one) -> Guard 2 assembly;
`2026-09-21-my-escrow-suite-stubbed-the-one-tool-that-would-have-refused-it.md` (a stub proves the plan's spelling,
not the tool's contract) -> the checker suite replays the real CLI table shape and the new preflight wrapper is
tested against that stub;
`2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md` and
`2026-08-20-every-guard-i-fixed-was-narrower-than-the-claim-it-carried.md` -> job-scoped, comment-stripped workflow
assertions and per-address mutation rows;
`2026-07-10-shared-vendor-key-fingerprint-attribution-and-required-iac-secret-apply-gate.md` and
`2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md` (a preflight must fail, not skip, on missing input).

**CTO and CLO consults (Phase 2.5, incorporated):** add `prevent_destroy` to the new password; a table-driven
cross-gate check that every gate names all four addresses (met by per-gate removal rows after plan review cut the dedicated census); the census must fail on an empty match set and carry a
reviewed exempt list; the wrapper must not write the token anywhere itself (security review measured that in the Tier-B arm the loader already exports it to `GITHUB_ENV` for every later step, masked per line, so it is ambient and not "scoped to one step"); keep the byte budget;
wording must say "narrowed", not "eliminated"; the pre-split token still reads web-1's config until retired, so the
Article 30 sentences are scoped to NEW births.

**Skipped with reason:** Phase 1.5 community discovery and Phase 1.5b functional overlap (headless pipeline; repo-specific
Terraform and CI gate hardening with no registry analog, and an unattended artifact install would be a side effect).
Phase 1.6b external research (strong local context; vendor facts were measured in earlier plans).

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief | Reality | Plan response |
|---|---|---|
| "an `[ack-destroy]` can wave a rotation through today" | True for `random_password.workspaces_luks`: it enters the push-apply plan only as a dependency of `doppler_secret.workspaces_luks_web_key` (`-target` pulls dependencies, and `doppler_secret.workspaces_luks_key` is not targeted). A replace trips `resource_deletes`, so acking an unrelated delete acks it. The `luks_passphrase_rotations` HALT exists but names only the inngest pair. | Extend the HALT (Phase 2). After the swap the web-1 password leaves the push-apply graph; its address stays in the list as defense in depth. |
| "the cutover gate `luks_passphrase_touched` clause naming the web key copy" | `workspaces-luks-cutover-gate.sh` names only `random_password.workspaces_luks` and `doppler_secret.workspaces_luks_key`. The recut and replace gates already name the web copy. | Phase 2: name the web copy and the new password in the cutover gate; table-driven cross-gate test. |
| "make `escrow=missing` ... a page" | The stage `workspaces_luks_provision_escrow` is on `web_luks_boot_warning` (NoOne). The provisioner continues after a failed escrow by design. | Move the stage to `web_luks_boot_fatal`; page by stage name (no rule filters on level). |
| "the provisioner/monitor expectations" | Neither reads web-1's key; both take the config from the boot env file (`CFG`, `KEY_CONFIG`). The provisioner has no fallback to web-1's config on an empty read, and nothing pins that. | Phase 1 adds a regression case: an unreadable web-class key never retries against `prd_workspaces_luks`. |
| "`--live` as a workflow gate" | `--live` needs a token that can list BOTH configs; a config-scoped service token exits 3 (`does not have access to requested config`). The birth jobs hold only `DOPPLER_TOKEN` (a `prd_terraform` token); the workplace-scope provider token (`variables.tf` `doppler_token_tf`) reaches them as `TF_VAR_doppler_token_tf` (Tier-B loader export) or as the `prd_terraform` secret `DOPPLER_TOKEN_TF` in the legacy arm. | Phase 3.2: a small wrapper script reads that token (env first, one single-secret read otherwise) and runs the checker with it; no new checker flag. |
| Workflow size | `apply-web-platform-infra.yml` is 482,795 bytes against the 490,000 gate (`workflow-file-size.test.ts`, ADR-231). | Byte budget AC: net growth at most 2,500 bytes; all logic stays in committed scripts. |

## Decision Records (to be written into ADR-263 and posted on #9377)

**D-A1 - distinct passphrase per host class: GO.** Rationale: the shared passphrase made a web-2 leak a web-1 leak,
and made any future web-1 `luksChangeKey` a two-host re-key. Nothing is lost by splitting now: no web-class volume
is LUKS-formatted yet (the live web-2 volume is plaintext, empty), the web-class key secret has never been applied,
so there is no data keyed by the old value and no rotation to perform. The split is cheapest exactly now and
becomes a data-bearing rotation after #9372.

**D-A2 - non-bypassable rotation HALT in the push-apply: YES.** Reasons, all verified: (1) `[ack-destroy]` cannot
discriminate a passphrase replace from any other delete in the same merge; (2) a rotated Terraform value leaves the
LUKS header cut from the old one and no copy of the old value survives (Terraform state keeps only the latest), so the
volume is unopenable on the next boot of a host with no console; (3) the same hazard already has a HALT for the
inngest pair (#7695) and the web pair is the same class with a worse payload; (4) cost is an address-list extension
of an existing counter plus one message. Mitigation layering: `prevent_destroy` on the new password (plan-time error,
independent of CI), the counter extension (covers `update` of the Doppler copy, `forget`, and an undecidable verb set,
which `prevent_destroy` does not), and the gate clauses on the dispatch routes. A first CREATE stays legal. If a first create half-fails and taints the password, `prevent_destroy` blocks the next plan; the remediation text names the recovery (`terraform untaint` or removing the tainted state entry under review). The only
bypass is `[skip-web-platform-apply]` (skips the apply, performs nothing). The supported way to rotate a populated
volume's passphrase is a header re-key (`cryptsetup luksChangeKey`) followed by an intentional state change under review,
never a Terraform replace; this is written into the HALT's remediation text and the ADR.

**D-B1 - the escrow check is a workflow gate: GO.** `check-web-host-escrow-config.sh --live` runs as a fail-closed step
before any Terraform command in `web_host_create` and `web_host_replace`, and a census test makes every future
host-creating job (the #9372 rebirth) carry it or be on a reviewed exempt list. The runbooks' "step 0" becomes a
diagnostic, not the control.

**D-B2 - `escrow=missing` pages a person.** The stage moves to the paging rule. It remains a boot-continues event
(level warning); severity is by stage name, as the existing rules document.

## Implementation Phases

### Phase 0 - Baselines (read-only)

- 0.1 Record `wc -c .github/workflows/apply-web-platform-infra.yml` (482,795 at plan time) and run the baseline suites
  that this change edits: `scripts/check-web-host-escrow-config.test.sh`, `apps/web-platform/infra/workspaces-luks-header-web.test.sh`,
  `apps/web-platform/infra/workspaces-luks-provision.test.sh`, `tests/scripts/test-destroy-guard-counter-web-platform.sh`,
  `tests/scripts/test-web-host-replace-gate.sh`, `tests/scripts/test-workspaces-luks-recut-gate.sh`,
  `tests/scripts/test-workspaces-luks-cutover-gate.sh`, `plugins/soleur/test/terraform-target-parity.test.ts`,
  `apps/web-platform/test/sentry-fresh-boot-luks-alert-op-contract.test.ts`,
  `apps/web-platform/test/sentry-egress-ghcr-deny-alert-op-contract.test.ts`. Note any pre-existing red as pre-existing.
- 0.2 Re-confirm the two workflow states with `gh api repos/jikig-ai/soleur/actions/workflows --jq` (must still read
  `disabled_manually` for the apply workflows); if either is active, STOP: the first-CREATE premise of D-A1 no longer holds
  and the swap would plan as an UPDATE that the new HALT stops.
- 0.3 Capture the `--help` text of `doppler secrets` locally (`doppler secrets --help`) into the PR notes, for the
  CLI-verification gate: the `--only-names` flag and the `--no-check-version` flag are already used by the checker; the new
  step adds no new Doppler flag.

### Phase 1 - Distinct passphrase (decision A1)

- 1.1 `apps/web-platform/infra/workspaces-luks-header-web.tf`: add `resource "random_password" "workspaces_luks_web"`
  (`length = 40`, `special = false`, `lifecycle { prevent_destroy = true }`, no `ignore_changes`, no `keepers`), point
  `doppler_secret.workspaces_luks_web_key.value` at `random_password.workspaces_luks_web.result`, and rewrite the header
  comment: delete the "SAME passphrase" paragraph, state the new truth (independent passphrase, narrowed not proven
  isolation: same Doppler project, same state, same provider token), and keep "NEVER `-replace`". The file stays separate so
  `workspaces-luks.test.sh` A11 (file-scoped to `workspaces-luks.tf`) is not touched.
- 1.2 `apps/web-platform/infra/workspaces-luks-header-web.test.sh`: W2's expected value reference changes to
  `random_password.workspaces_luks_web.result`; W3's cardinality becomes 5 resources (1 bucket, 3 secrets, 1 password) with the
  password pinned by a new predicate W7 (name, `length = 40`, `special = false`, `prevent_destroy = true`, no `ignore_changes`, no
  `keepers`); a new W8 asserts the file never names `random_password.workspaces_luks` (word-bounded, so `_web` does not match) in
  code. Update the assertion floor (30 -> the new count, recomputed from the header formula in the file).
- 1.3 `scripts/check-web-host-escrow-config.sh --static` gains the whole-tree passphrase-distinct clause (Guard 1 below), and
  only that: (c) the word-bounded address `random_password.workspaces_luks` appears in code under ROOT only in `workspaces-luks.tf` (comment-stripped, and over the same file classes the existing sweep covers, so a comment in a workflow or a `.tf` header that names it for contrast cannot trip it);
  (d) `census-empty` if `workspaces-luks-header-web.tf` is missing. The file-scoped shape claims (one `random_password`, the key
  secret's `value`) live in `workspaces-luks-header-web.test.sh` W2/W7/W8 only, not duplicated here (plan review: two suites
  asserting one property double the mutation rows for no extra reach). Update the `--live` header docs (it still asserts the five names and the absence of
  the passphrase and the R2 pair from the `prd` root; value distinctness is NOT checkable from names and the doc says so) and the
  "NOT enforced by any workflow" sentence.
- 1.4 `scripts/check-web-host-escrow-config.test.sh`: positive control stays; add mutation rows per Guard 1; keep the exact-count
  anti-vacuity floor current.
- 1.5 `apps/web-platform/infra/workspaces-luks-provision.test.sh`: add a case where the stubbed `doppler` returns empty for
  `WORKSPACES_LUKS_KEY` under `CFG=prd_workspaces_luks_web`; assert the provisioner ends in the fatal `key` arm (exit 13) and that
  the stub never saw `--config prd_workspaces_luks` (the stub logs every requested config). Audit `luks-monitor.test.sh` and
  `workspaces-luks-reopen*` tests for fixtures that assume one key across hosts (`rg 'WORKSPACES_LUKS_KEY'` over
  `apps/web-platform/infra/*.test.sh`); change only assertions that encode the shared value.
- 1.6 `apps/web-platform/infra/workspaces-luks-fresh-boot.tf` comments: replace the "SAME `WORKSPACES_LUKS_KEY` unlocks web-2 and
  web-1's sole-copy volume" passage with the narrowed statement; pin nothing new there.
- 1.7 `.github/workflows/apply-web-platform-infra.yml`: add `-target=random_password.workspaces_luks_web` to the default
  allow-list beside the web-class secret targets, and `plugins/soleur/test/terraform-target-parity.test.ts` adds
  `random_password.workspaces_luks_web` to the `freshBoot` list (must be declared, default-targeted, never an operator-applied
  exclusion) and to `WEB_HOST_REPLACE_PRESERVED` (so no replace job may name it in its `-target` set). `random_password.workspaces_luks` stays in `OPERATOR_APPLIED_EXCLUSIONS`.

### Phase 2 - Rotation HALT and gate naming (decision A2)

- 2.1 `tests/scripts/lib/destroy-guard-filter-web-platform.jq`: widen `luks_passphrase_rotations` from the two inngest addresses to
  six: add `random_password.workspaces_luks`, `random_password.workspaces_luks_web`, `doppler_secret.workspaces_luks_key`,
  `doppler_secret.workspaces_luks_web_key`. Keep the verbs (`update`, `delete`, `forget`, plus decidability-first: a missing
  or empty or non-array verb list counts). `create` and `no-op` stay legal. Rewrite the explanatory comment for the new members.
- 2.2 `.github/workflows/apply-web-platform-infra.yml`, `apply` job HALT block: generalize the message
  ("inngest LUKS passphrase resource(s)" -> "LUKS passphrase resource(s) (inngest or workspaces)"), add the workspaces remediation
  branch (rotation = header re-key then an intentional state change under review; never a replace; for a not-yet-formatted
  web-class volume the first create is the only legal verb; unwedge `[skip-web-platform-apply]`), and widen the `grep` that prints
  the offending plan lines to `_luks`. Keep the block BEFORE the `destroy_count` sum and outside it. Budget: net growth in this
  hunk at most 1,200 bytes (move rationale to `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`
  if needed, per ADR-231).
- 2.3 Gate naming (property 2 on the dispatch routes; item 6c of the issue): `tests/scripts/lib/workspaces-luks-cutover-gate.sh` names
  `doppler_secret.workspaces_luks_web_key` and `random_password.workspaces_luks_web` in a `named_live`-style passphrase set (the
  shape `workspaces-luks-recut-gate.sh` already uses), with the full four-verb rule for the web copies (the cutover never creates
  them; they ride the push-apply) and `out_of_scope` excluding them so each clause is independently load-bearing.
  `tests/scripts/lib/workspaces-luks-recut-gate.sh` and the `luks_passphrase_touched` clause plus message in
  `tests/scripts/lib/web-host-replace-gate.sh` gain `random_password.workspaces_luks_web`. The by-name web-1 refusal in
  `web-host-replace-gate.sh` is NOT touched and stays first (see the diff-scope AC).
- 2.4 Suites: `tests/scripts/test-destroy-guard-counter-web-platform.sh` gains rows for each new address (replace, update, forget,
  first create passes, no-op passes, undecidable verb list at a web address, and no-ack-bypass for the workspaces addresses) and keeps
  the job-scoped, comment-stripped `T60g` assertion that the `apply` job HALTs before the `destroy_count` sum;
  `test-workspaces-luks-cutover-gate.sh`, `test-workspaces-luks-recut-gate.sh`, `test-web-host-replace-gate.sh` gain the new-address
  rows and a `gate_mutate_and_check` row that removes the new address from the clause (the shape at
  `test-workspaces-luks-recut-gate.sh` row 4.1b), which is what makes each gate clause independently load-bearing; there is no separate
  cross-gate census (plan review: those per-gate rows already cover the four named addresses). Job reach is pinned in
  `plugins/soleur/test/terraform-target-parity.test.ts`, which already extracts each job's `-target` list: a new row asserts the web
  key copy and the new password appear in the `apply` job's list and in EVERY dispatch job's list not at all (iterate all dispatch jobs, not only the two birth routes), and that the `apply` job carries the
  rotation HALT block. The transitive reach (`-target` pulls dependencies) was traced at plan time by reading the five
  `apply-deploy-pipeline-fix.yml` targets and the `apply` post-bridge targets: neither closure reaches the key secrets or either
  password (they stop at `hcloud_server.web` -> the fresh-boot token -> the config); `scheduled-terraform-drift.yml` is plan-only and
  `workspaces-plaintext-forget.yml` only removes volume addresses from state.

### Phase 3 - Escrow check as a workflow gate (decision B1)

- 3.1 `scripts/check-web-host-escrow-config.sh`: no new flag. Failure output gains a one-line cause map (kept here and only here; the
  runbooks point at it): a missing `WORKSPACES_LUKS_KEY`, `WORKSPACES_HEADER_BUCKET` or `WORKSPACES_HEADER_R2_ENDPOINT` means the
  web-platform push-apply has not created them; a missing R2 pair name means the live mint (#9377) has not been done. Exit codes
  (0/1/2/3) are unchanged and every non-zero one fails the step.
- 3.2 New `scripts/web-host-escrow-preflight.sh` (about 10 lines, the one reusable unit every birth route calls, so the #9372 rebirth
  copies one line, not a five-attribute step). `set -euo pipefail`; refuses xtrace when a token is set; takes the provider token from
  the environment (`TF_VAR_doppler_token_tf`, exported by the Tier-B loader) and otherwise reads exactly one secret with
  `doppler secrets get DOPPLER_TOKEN_TF -p soleur -c prd_terraform --plain` using the step's `DOPPLER_TOKEN` (never `doppler run`, so the
  checker does not inherit every `prd_terraform` secret, and it keeps working after the Tier-A eviction, runbook `infra-credential-tiers-8209.md`
  O10/O13); then `DOPPLER_TOKEN="$tok" exec bash scripts/check-web-host-escrow-config.sh --live`. The value never reaches argv, a file,
  `GITHUB_ENV` or stdout. Order inside the wrapper (security review): refuse xtrace FIRST (`case "$-" in *x*) exit 78 ;; esac`, before any read, as the workflow's own step at `apply-web-platform-infra.yml` does), then read, then `::add-mask::` the legacy-arm value and require the shape `^dp\.pt\.[A-Za-z0-9]+$` (a plantable `prd_terraform` value cannot then carry newlines or directives), then exec.
- 3.3 `.github/workflows/apply-web-platform-infra.yml`, jobs `web_host_create` and `web_host_replace`: one step each, after "Verify
  required secrets present" and before any Terraform command, with no `working-directory` (the script path is repo-root relative; the
  neighbouring steps set `INFRA_DIR`), no `if:`, no `continue-on-error`, no `|| true`, `timeout-minutes: 2`, and `DOPPLER_TOKEN` only in
  that step's `env:`: `run: bash scripts/web-host-escrow-preflight.sh`. About 200 bytes per step. The discoverability probe
  `bash scripts/check-web-host-escrow-config.sh --static` was run on the real tree at plan time: `escrow-split-contract:ok`, 2.6 s, well
  under preflight Check 10's 15 s cap.
- 3.4 New census test `plugins/soleur/test/web-host-escrow-preflight-census.test.ts` (bun, registered where its siblings are): Guard 3.
  New `scripts/web-host-escrow-preflight.test.sh` against the Doppler stub the checker suite already uses: env token wins over the
  fallback read; the fallback reads one named secret only; an empty token exits non-zero before any checker call; no token bytes on
  stdout or stderr, including a row proving the checker child never echoes its environment; xtrace refused. Tokens in the suites are synthetic. Register it in `scripts/test-all.sh`.
- 3.5 Runbooks `knowledge-base/engineering/operations/runbooks/web-host-birth.md` and `web-host-replace.md`: Step 0 now says the workflow
  runs the check and aborts before any change; the person-run command is for diagnosing an abort and the cause map lives in the checker's output
  (not duplicated). Add the remediation for a paged `escrow=missing`: escrow is attempted once at birth, so the way to re-attempt is a host
  replace; for a web-2 that holds no user data that is cheap, and once a web-class host holds data the page's remediation is owned by the
  #9372 follow-up (record that dependency in the runbook row, do not invent a re-escrow step here).

### Phase 4 - Page a person on `escrow=missing`; route `resolve_link_local` (decision B2, item 6b)

- 4.1 `apps/web-platform/infra/sentry/issue-alerts.tf`: move `workspaces_luks_provision_escrow` from `web_luks_boot_warning`'s `stage in`
  list to `web_luks_boot_fatal`'s (14 paging stages, 3 quiet). Update the comment blocks above both rules (the escrow description moves,
  the "Severity is separated by STAGE NAME" paragraph gains the one stage that pages while the boot continues). Add `resolve_link_local` to
  `sentry_alert.egress_blocked`'s `op in` list and its comment. No rename of any resource or live rule name.
- 4.2 `apps/web-platform/infra/sentry/alert-reference.json`: the two `web-host-luks-boot-*` entries and the `cron-egress-blocked` entry carry
  the same lists (the `sentry-alert-reference-gate.sh` plan-PR check requires the committed projection to equal the plan projection).
- 4.3 `apps/web-platform/test/sentry-fresh-boot-luks-alert-op-contract.test.ts`: escrow moves from `QUIET_STAGES` to `PAGE_STAGES`; the
  "a quiet stage is never emitted at level fatal" and "a warning never reuses a paging arm's stage name" rows get an explicit
  `PAGE_AT_WARNING = [escrow]` carve-out so the contract states the one stage that pages at level warning on purpose; a new row asserts the
  provisioner still emits it at level `warning` (boot continues) and that the router lists it on exactly one rule. Mutation rows are updated.
  `apps/web-platform/test/sentry-egress-ghcr-deny-alert-op-contract.test.ts`: `ROUTED_OPS` gains `resolve_link_local`; assert the resolver
  emits it (the existing `resolverEvents()` extractor) and the reference entry carries it.
- 4.4 Sweep: `rg 'workspaces_luks_provision_escrow|13 stages|thirteen'` over `knowledge-base/` (runbook table at `web-host-replace.md`, ADR-263
  Consequences) and update counts and the "NoOne" statements. The runbook decode table row for `escrow` changes from "none" to "pages".

### Phase 5 - Shape-validate the R2 credential pair (item 6e)

- 5.1 `apps/web-platform/infra/workspaces-luks-provision.sh` `_escrow`: before `_curl` is defined, under `LC_ALL=C` (locale collation can widen `[A-Za-z]`), require
  `[[ "$kid" =~ ^[A-Za-z0-9]{16,128}$ ]]` and `[[ "$sec" =~ ^[A-Za-z0-9/+=_-]{16,256}$ ]]`, else `ESCROW_WHY=shape; return 1` (no curl call,
  no value echoed). Deliberately wider than R2's current 32/64 hex so a vendor format change does not silently turn escrow off; the property is
  "no quote, backslash, whitespace or control byte can reach the `user = "..."` line". The existing `bucket`/`ep` shape line is the model.
- 5.2 `workspaces-luks-provision.test.sh`: cases per Guard 5; the curl stub records its stdin so the assertion reads what would have been streamed.

### Phase 6 - Architecture, legal and documentation

- 6.1 ADR-263 addendum (2026-10-03): rewrite D7's passphrase sentence (copies -> independent), add D8 (the HALT, the gate, the page), rewrite
  "Shared-passphrase residual" (narrowed for NEW births; not closed while the pre-split token exists; the `luksChangeKey` constraint on web-1
  is lifted for web-class hosts, and the loss-recovery path is stated: the web-class passphrase lives in Doppler and Terraform state only, the
  escrowed header cannot open a volume alone), fix the Consequences counts (14/3), keep the status `adopting`.
- 6.2 `knowledge-base/legal/article-30-register.md` (cross-host replication row) and `knowledge-base/legal/compliance-posture.md` (Hetzner row):
  apply the CLO's replacement text, including the second "the passphrase is still shared" clause in the "NOT closed" run; scope "narrowed" to NEW
  births; add one sentence that a web-class birth with `escrow=missing` now pages a person (alerting change, not a processing change); keep every
  web-2 encryption statement conditioned on #9372. Both cells are byte-identical copies and are edited identically. Cite by name, not line number.
- 6.3 `scripts/encryption-posture-ledger.json` row `cloudflare_r2_bucket.workspaces_luks_header_web`: replace the "the web-class Doppler config
  carries the same passphrase" clauses in `evidence` and `does_not_defend` with the CLO's text; `disclosed_as` stays `not-publicly-claimed`. Run
  `scripts/lint-encryption-posture.py` and its suite.
- 6.4 C4: `knowledge-base/engineering/architecture/diagrams/model.c4` `doppler -> hetzner` edge text (web-class hosts read a separate config with a
  separate passphrase). Regenerate `model.likec4.json` with
  `scripts/regenerate-c4-model.sh`. See "Architecture Decision" for the completeness enumeration.
- 6.5 Add a one-paragraph note to `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md` for the new
  preflight steps and the widened HALT (rationale relocates there, ADR-231).

### Phase 7 - Verification and hand-off

- 7.1 Byte budget: `wc -c` the workflow (AC below) and run `bun test plugins/soleur/test/workflow-file-size.test.ts`.
- 7.2 Run every suite from Phase 0 plus the new census, `plugins/soleur/test/c4-count-parity.test.sh`,
  `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`, `scripts-shard-totality.test.sh`, `scripts/lint-guard-contract.py` over this plan,
  and the CI invocation `scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- 7.3 Post the decision record on #9377 (a comment, GitHub write only): decisions A1, A2, B1, B2, what shipped, and the still-open items
  (live mint, isolation proof both ways, pre-split token retirement, census proofs, runtime link-local assert).
- 7.4 File one tracking issue for the deferred read-only preflight token (CTO), with re-evaluation criteria: before the #9372 workflow is
  reusable for a second host, or when Doppler offers a workplace read-only token; milestone from `knowledge-base/product/roadmap.md`.
- 7.5 PR body: `Ref #9377` (never `Closes`), the "Merge-time effects" table, and the line "no live step performed".

## Files to Edit

- `apps/web-platform/infra/workspaces-luks-header-web.tf`, `apps/web-platform/infra/workspaces-luks-header-web.test.sh`
- `apps/web-platform/infra/workspaces-luks-fresh-boot.tf` (comments only)
- `apps/web-platform/infra/workspaces-luks-provision.sh`, `apps/web-platform/infra/workspaces-luks-provision.test.sh`
- `scripts/check-web-host-escrow-config.sh`, `scripts/check-web-host-escrow-config.test.sh`
- `.github/workflows/apply-web-platform-infra.yml`
- `tests/scripts/lib/destroy-guard-filter-web-platform.jq`, `tests/scripts/test-destroy-guard-counter-web-platform.sh`
- `tests/scripts/lib/workspaces-luks-cutover-gate.sh`, `tests/scripts/test-workspaces-luks-cutover-gate.sh`
- `tests/scripts/lib/workspaces-luks-recut-gate.sh`, `tests/scripts/test-workspaces-luks-recut-gate.sh`
- `tests/scripts/lib/web-host-replace-gate.sh` (the `luks_passphrase_touched` clause and its message only), `tests/scripts/test-web-host-replace-gate.sh`
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `apps/web-platform/infra/sentry/issue-alerts.tf`, `apps/web-platform/infra/sentry/alert-reference.json`
- `apps/web-platform/test/sentry-fresh-boot-luks-alert-op-contract.test.ts`, `apps/web-platform/test/sentry-egress-ghcr-deny-alert-op-contract.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md`
- `knowledge-base/legal/article-30-register.md`, `knowledge-base/legal/compliance-posture.md`, `scripts/encryption-posture-ledger.json`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (and the generated `model.likec4.json`)
- `knowledge-base/engineering/operations/runbooks/web-host-birth.md`, `web-host-replace.md`, `apply-web-platform-infra-job-rationale.md`
- `scripts/test-all.sh` (register the new suite; verify with `rg 'check-web-host-escrow' scripts/test-all.sh`), `apps/web-platform/infra/suite-shard-legs.tsv` (the checked-in shard manifest, ADR-240: regenerate or extend per `scripts-shard-totality.test.sh`), and `.github/CODEOWNERS` if it carries rows for the destroy-guard filter or the new scripts

## Files to Create

- `plugins/soleur/test/web-host-escrow-preflight-census.test.ts` (Guard 3)
- `scripts/web-host-escrow-preflight.sh` and `scripts/web-host-escrow-preflight.test.sh` (the reusable birth-route step and its suite; registered in `scripts/test-all.sh`)
- `tests/scripts/fixtures/tfplan-workspaces-luks-passphrase-{first-create,rotation,forget}.json` (plan fixtures for the new counter rows, shaped like the three existing `tfplan-inngest-luks-passphrase-*.json` fixtures)

Glob verification (hr-when-a-plan-specifies-relative-paths-e-g): every path above was checked with `git ls-files` or `test -f` at plan time except the
Files-to-Create entries. The Files-to-Edit list for the allow-list extension was derived from
`git grep -ln 'workspaces_luks_web_key\|workspaces_luks_fresh_boot_web\|inngest_redis_luks_key' -- tests scripts plugins .github apps/web-platform/infra apps/web-platform/test`
rather than from the filter alone; the other hits are the inngest gates and fixtures (unchanged: they bind the inngest pair) and
`workspaces-luks-fresh-boot.test.sh` / `fresh-boot-parity.test.sh` / `server.tf`, which name the web-class token but never the key
secret's value (re-run the grep at work time; any new hit is a Files-to-Edit entry).

## Open Code-Review Overlap

None. Queried open `code-review` issues against every planned path (two-stage `gh issue list --json` then `jq --arg`); zero matches.

## User-Brand Impact

**If this lands broken, the user experiences:** a web-class host (web-2 or a future cattle host) that boots into a LUKS header its Doppler
key no longer opens, so the host powers off or its store is unopenable and its users' work is unreachable until a rebuild; or a birth that
silently proceeds without an off-host header backup, so a later header damage cannot be repaired and the store's contents are permanently lost.
Today web-2 holds no user data, so the exposure is the first user-bearing cutover (#9372 and the flip), not this merge.

**If this leaks, the user's data is exposed via:** the web-class passphrase or the fresh-host token read from `prd_workspaces_luks_web`; before this
change that same read returned web-1's passphrase (the sole-copy store of every user's repositories). After it, a web-2 compromise yields web-2's
store passphrase only. The shared Doppler project, Terraform state and provider-token reach still bound the claim: narrowed, not proven isolated.

**Further failure vectors named by the review and their disposition:**

- *Passphrase loss.* With independent passphrases, web-1's copy no longer backs up the web-class one. The only copies are the Doppler secret and Terraform state, and the escrowed header cannot open a volume alone. Compensating control for the period before #9372: no web-class volume holds data yet, so a loss costs a rebuild of an empty standby; a recovery path for the data-bearing period is owned by #9372 and the CLO asked that it be recorded when data lands (Art. 32(1)(c)).
- *State loss or rewind after a format.* Both web resources would plan as `create`, which the HALT permits, and the provider would overwrite the live secret. The HALT cannot see it; the state bucket's own protections are the control (recorded in the ADR as a known limit).
- *A false-positive HALT* (a provider-driven update of a key copy) wedges every merge apply until `[skip-web-platform-apply]`; accepted, the same trade the inngest pair already carries, and a hotfix route exists because the skip token skips only the apply.
- *A fail-closed preflight delays recovery of a down web-class host* (a Doppler API error, a revoked R2 pair). Accepted: while web-2 holds no data a delayed birth costs nothing; once it serves users the break-glass question belongs to the #9372 follow-up, and each retry spends a reviewer approval.
- *Provider-token exposure.* The workplace-scope token reaches the preflight step and its checker child. Leak paths (argv, file, `GITHUB_ENV`, stdout, xtrace) are pinned by the wrapper suite, which also gets a row proving the checker child never echoes its environment.
- *The pre-split token still reads web-1's config* until it is retired, so "a web-2 compromise yields web-2's passphrase only" holds for NEW births only.

- **Brand-survival threshold:** `single-user incident`.

CPO sign-off: the issue owner's decisions (A) and (B) on #9377 are the product-owner call and are recorded; this plan does not claim a separate
CPO agent ran. `soleur:engineering:review:user-impact-reviewer` runs at review time on the diff.

## Observability

```yaml
liveness_signal:
  what: the escrow preflight step passing in each web_host_create / web_host_replace dispatch run; the static census of the escrow contract in CI
  cadence: per dispatch (live), per PR (static)
  alert_target: the dispatching person sees a red job; the repo CI check for the static census; Sentry stage workspaces_luks_provision_escrow for a runtime escrow failure
  configured_in: .github/workflows/apply-web-platform-infra.yml (steps), scripts/check-web-host-escrow-config.sh, apps/web-platform/infra/sentry/issue-alerts.tf
error_reporting:
  destination: the Actions job log (preflight, token-redacted), Sentry via soleur-boot-emit for the provisioner stages, GitHub issue [ci/luks-verify-web2] for a RED verify run
  fail_loud: true
failure_modes:
  - mode: web-class config missing a name (key, bucket, endpoint, R2 pair) at birth
    detection: layer 6 (workflow run log, ::error:: from the preflight step): exit 1 names the missing name and its cause (push-apply not run, or live mint not done); the birth never starts
    alert_route: workflow run log of the dispatch (the dispatcher is attending the run)
  - mode: preflight cannot read Doppler (token scope, vendor error)
    detection: layer 6 (workflow run log, ::error::): exit 3 or 2, never treated as absence; the birth never starts
    alert_route: workflow run log of the dispatch
  - mode: provisioner records escrow=missing at birth
    detection: soleur-boot-emit posts Sentry stage workspaces_luks_provision_escrow straight to Sentry (the boot-trail path; Vector is not up yet on a fatal boot) and the readiness row carries escrow=missing, so the verify web-2 leg's workflow run log is RED (existing reason ready_escrow) and no soak marker is written
    alert_route: Sentry issue alert web-host-luks-boot-fatal emails ActiveMembers (page), plus the [ci/luks-verify-web2] GitHub issue. Known soft spots, recorded not hidden: soleur-boot-emit ends in `|| true` (a failed emit is silent, so the readiness row and the verify leg are the second channel) and the rule's 35-minute frequency throttle can fold an escrow page into one that followed another fatal stage of the same boot
  - mode: a merge plan rotates or drops a workspaces passphrase or its Doppler copy
    detection: layer 6 (workflow run log, ::error:: in the apply job): luks_passphrase_rotations > 0, HALT before destroy_count
    alert_route: notify-apply-failure on the failed push-apply, and the workflow run log
  - mode: a resolver answer in the metadata range during allowlist resolution
    detection: cron-egress-resolve.sh posts Sentry op resolve_link_local with feature cron-egress-firewall directly to Sentry (not through pino or Vector)
    alert_route: Sentry issue alert cron-egress-blocked emails ActiveMembers on first seen, reappeared or regression events only (a second occurrence within one unresolved issue group stays quiet)
logs:
  where: GitHub Actions run logs; Better Stack Logs (journald tag workspaces-luks-reopen, shipped by Vector); Sentry
  retention: Actions default retention; Better Stack and Sentry plan retention
discoverability_test:
  command: bash scripts/check-web-host-escrow-config.sh --static
  expected_output: escrow-split-contract:ok
```

The probe covers the escrow-config census only. The Sentry routing (the escrow stage on the paging rule, `resolve_link_local` on `egress_blocked`) is pinned by the two op-contract suites and the alert-reference gate in CI, not by this probe; both are named in Guard 4 so the split is explicit rather than implied.

## Encryption Posture

```yaml
at_rest:
  - store: doppler.secrets (new secret copy: WORKSPACES_LUKS_KEY in prd_workspaces_luks_web, now an independent value)
    mechanism: existing ledger row doppler.secrets (secret-store); no new store introduced
    evidence: scripts/encryption-posture-ledger.json row doppler.secrets; the new value is created by random_password and written masked
    defends_against: casual disclosure of the value in Doppler listings and CLI output (masked visibility)
    does_not_defend: a holder of any token that resolves the web-class config (and the ~116 inherited prd secrets, ADR-164 census); a holder of the provider token; Terraform state readers
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:Doppler gives no customer-side probe of at-rest encryption; the names-only live check proves presence, not distinctness
  - store: r2.terraform_state_backend (now also holds random_password.workspaces_luks_web.result in plaintext state)
    mechanism: existing ledger row r2.terraform_state_backend (provider-managed R2 encryption, state bucket access limited to the CI credentials)
    evidence: scripts/encryption-posture-ledger.json row r2.terraform_state_backend; the same exposure already applies to random_password.workspaces_luks (workspaces-luks-header.tf comment)
    defends_against: physical-media compromise at the provider
    does_not_defend: any principal with state-bucket read, which now also yields the web-class passphrase
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:provider-managed at-rest; no customer-side probe
in_transit:
  - connection: CI runner (doppler CLI) -> Doppler API for the names-only escrow preflight
    tls: TLS 1.2+ (Doppler CLI default)
    cert_verification: on
    does_not_defend: a runner-side attacker who already holds the provider token in the step environment
    disclosed_as: not-publicly-claimed
```

## Guard Contract

### Guard 1 - the web-class passphrase is generated independently and no web-1 path feeds it

**Property.** No Terraform resource, secret copy or code path under `apps/web-platform/infra/` derives the web-class `WORKSPACES_LUKS_KEY` from `random_password.workspaces_luks`, and no web-class host path falls back to web-1's config when its own key read fails.

**Assembly.** Every non-comment occurrence of the word-bounded address `random_password.workspaces_luks` (not `_web`) across ROOT, which must be confined to `workspaces-luks.tf`; both `doppler_secret` resources named `WORKSPACES_LUKS_KEY` with their `value` and `config` pair (web-1's in `workspaces-luks.tf`, the web-class one in `workspaces-luks-header-web.tf`); the `random_password` census of `workspaces-luks-header-web.tf` (exactly one, shape pinned); the key-read lines of the provisioner (`_dget`, config from `CFG`) and the monitor (`KEY_CONFIG`). Two chokepoints enforce it from two sides and must agree: the checker's `--static` census (whole-tree) and `workspaces-luks-header-web.test.sh` (file-scoped predicates); the provisioner case guards the runtime fallback. Members drift: the census quantifies over files found by `find`, not over a list of today's files.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-point the web-class key secret `value` at `random_password.workspaces_luks.result` | RED in `--static` (whole-tree census) and in W2 and W8 |
| 2 | Add a second reference to `random_password.workspaces_luks` in another `.tf` (an output or a local in `server.tf`) after the compliant first | RED (census over all files) |
| 3 | Replace the web-class value with a string literal, and separately delete the new `random_password` block | RED each (W2, W7) |
| 4 | Declare a second `random_password` in `workspaces-luks-header-web.tf` (a decoy) | RED (W3 cardinality 5 -> 6) |
| 5 | Run `--static` against a ROOT without `workspaces-luks-header-web.tf` | RED as `census-empty`, never a pass |
| 6 | Add a fallback read against `prd_workspaces_luks` to the provisioner key read | RED (the stub logs every requested config) |
| 7 | Drop `prevent_destroy` or add `ignore_changes` / `keepers` to the new password | RED (W7) |
| H1 | Harness: the suites' assertion-count floor with a case deleted | RED |
| H2 | Must-PASS: a comment in `workspaces-luks-header-web.tf` naming `random_password.workspaces_luks`, and web-1's own `workspaces-luks.tf` naming it | GREEN |

**Anchor.** No value-level anchor exists offline: the guard proves structure (two independent `random_password` resources), and Terraform's generator makes the values independent by construction. What would catch a manual overwrite of the Doppler value is outside this change: the live mint's isolation proof and the retained state. The ADR says so and does not claim the live distinctness is verified.

### Guard 2 - no merge apply can rotate or drop a workspaces passphrase without a non-ackable stop

**Property.** No plan reaching the push-apply that updates, replaces, deletes or forgets `random_password.workspaces_luks`, `random_password.workspaces_luks_web`, `doppler_secret.workspaces_luks_key` or `doppler_secret.workspaces_luks_web_key` (or carries an unreadable verb list at one of them) can proceed, with or without `[ack-destroy]`; a first create proceeds.

**Assembly.** The four addresses across every consumer: the jq counter `luks_passphrase_rotations` (read by the `apply` job only); the `apply` job HALT block and its position before the `destroy_count` sum; the `luks_passphrase_touched` clause of `web-host-replace-gate.sh`, `workspaces-luks-recut-gate.sh` and `workspaces-luks-cutover-gate.sh`; and every workflow job whose `-target` list contains any of the four addresses or a resource depending on them (the web copy rides only the `apply` job; the web-1 pair rides `workspaces_luks_recut` and the cutover dispatch). Enumerated, not assumed: the per-gate removal rows fail if any consumer omits any of its named addresses, the `terraform-target-parity.test.ts` row above fails if a job other than `apply` targets the web copies, or if `apply` lacks the HALT. `prevent_destroy` on the new password is the plan-time layer; it does not cover `update` or `forget`, which is why the counter exists.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove each one of the four addresses from the jq list in turn (four rows) | RED each (the replace fixture scores 0) |
| 2 | Drop `update` from the verb list, and separately drop `forget` | RED each |
| 3 | A fixture entry at a web address with `"actions": []` and `after` null | RED (counts as a rotation) |
| 4 | A fixture with first `["create"]` of both web resources, and a `["no-op"]` re-run | GREEN (must-PASS; a first create is legal) |
| 5 | Move the HALT after the `destroy_count` sum, or let `[ack-destroy]` skip it | RED (`T60g`-style job-scoped, comment-stripped assertion) |
| 6 | Delete the HALT block entirely | RED (the same assertion; the counter alone does not stop an apply) |
| 7 | Remove one address from each gate clause in turn (`gate_mutate_and_check`) | RED each |
| 8 | Add the web copy to a second job's `-target` list | RED (the `terraform-target-parity.test.ts` job-reach row) |
| 9 | The reach row extracting zero jobs or zero targets | RED (floor) |
| H1 | Harness: a gate fixture with the passphrase entry absent entirely (the plan simply lacks it) | GREEN, so a RED row is not "everything fails" |
| H2 | Must-PASS: a plan touching only unrelated resources, and a replace of the workspaces store volume under its own gate | unchanged verdicts |

**Anchor.** The HALT list lives in the same diff as its tests. The anchor outside the commit is the merge-base comparison in the acceptance criteria: the jq address list may only grow against `origin/main`, and the `apply`-job HALT block may not move below the `destroy_count` line; a reviewer sees both as diff facts.

### Guard 3 - every web-host-creating route runs the live escrow check before it can change anything

**Property.** Every workflow job able to create or replace `hcloud_server.web[...]` runs `scripts/web-host-escrow-preflight.sh` (the live escrow check) fail-closed before any Terraform command, or is on a reviewed exempt list because it refuses host creation outright.

**Assembly.** All `.github/workflows/*.yml` files and, within each, all jobs. A job is host-creating when its non-comment text contains a `terraform apply` AND a `-target`/`-replace` argument whose address is `hcloud_server.web[` (a bare mention is not enough: `inngest_volume_recut`, `workspaces_luks_cutover` and `workspaces_luks_recut` loop over that address in `jq` state-presence checks and are not creators; plan review measured this against the workflow). Today that is `web_host_create` and `web_host_replace`; any job that matches the predicate and is not one of those two must be on the reviewed exempt list, each entry pinned by its `host_creates` HALT text (no bypass); security review measured the predicate against the workflow: it matches only `web_host_create` and `web_host_replace`, so the exempt list is empty by construction. The refusing routes (`apply-web-platform-infra.yml:apply` and `apply-deploy-pipeline-fix.yml:apply`) never match, which means "every route" holds only while their `host_creates` HALTs survive; the census therefore pins those two HALTs by name (the block exists and exits non-zero with no acknowledgement path), as a separate assertion that does not depend on the predicate. `workspaces-plaintext-forget.yml` has no `terraform apply`. The step's attributes are asserted in order: it exists, precedes the first `terraform` command, carries no `if:`, no `continue-on-error`, no `|| true`, runs `bash scripts/web-host-escrow-preflight.sh` (which runs the checker in `--live` mode, pinned by the wrapper's own suite). A new workflow file or job (the #9372 rebirth) is unexempt by default. The census is not a proof that the check passes (the checker reads names only); it proves the check cannot be skipped.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the step from `web_host_create`; separately from `web_host_replace` | RED each |
| 2 | Move the step after the `Terraform plan` step | RED (ordering) |
| 3 | Add `continue-on-error: true`, an `if:`, or `|| true` to the step | RED each |
| 4 | Point the step at the checker's `--static` mode, or at a different script | RED |
| 5 | Add a third job (fixture) that runs `terraform apply` against `hcloud_server.web[` with no preflight, after a compliant first and second | RED (the check does not stop at the first compliant job) |
| 6 | Add a new workflow file of the rebirth shape with no preflight | RED |
| 7 | Remove the `host_creates` HALT from `apply-web-platform-infra.yml:apply`, and separately from `apply-deploy-pipeline-fix.yml:apply` | RED each (the two refusing routes are pinned by name; the predicate alone would never see them) |
| 8 | The census finding fewer than two host-creating jobs | RED (floor; it must not pass over an empty set) |
| H1 | Harness: a fixture job with the preflight under a different step name and unrelated steps reordered | GREEN |
| H2 | Harness: the suite's own assertion floor with the dispatch removed | RED |

**Anchor.** The checker is names-only (necessary, not sufficient). The outside anchor is the live mint's two-way signed `HEAD` isolation proof, tracked on #9377 and a precondition of #9372. This guard proves the check runs, not that the credentials are correct.

### Guard 4 - an escrow-missing web-class birth reaches a person

**Property.** The stage emitted when the off-host header copy fails is routed to a rule that emails a person, and no stage the provisioner emits is routed to no rule.

**Assembly.** The provisioner's emitted stages (the eight fatal arms, `escrow`, `wire_warn`, `result`), the cloud-init and readiness stages, the two `sentry_alert` blocks' `stage in` lists, `alert-reference.json`, the op-contract test's `PAGE_STAGES`/`QUIET_STAGES`, and the runbook decode table. The contract test reads emitter and router both, so a stage cannot be added to one side only. The same shape covers `resolve_link_local` on the `egress_blocked` rule.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Move `escrow` back to the warning list | RED |
| 2 | Remove `escrow` from both lists | RED |
| 3 | List `escrow` on both rules | RED (no stage on both) |
| 4 | Change the warning rule's action to `ActiveMembers`, and separately empty or change the paging rule's actions away from `ActiveMembers` | RED each (the first would page the quiet stages, the second would silence the page) |
| 5 | Rename the emitted stage in the provisioner | RED (router and emitter disagree) |
| 6 | Drop `resolve_link_local` from `egress_blocked`, and separately rename the op in the resolver | RED each |
| 7 | Leave `alert-reference.json` at the old lists | RED (the reference equality check) |
| H1 | Harness: a copy of the rule text with the paging list emptied | RED (an extractor that returns nothing cannot pass) |
| H2 | Must-PASS: `wire_warn`, `result` and `fresh_boot_ready_bs_egress` stay on the quiet rule | GREEN |

**Anchor.** The committed `alert-reference.json` is compared with the plan projection by `sentry-alert-reference-gate.sh` in the PR job, so a `.tf` edit with a stale reference reds independently of vitest. Sentry's live rule state is verified after the apply-sentry-infra run by that workflow's own drift read.

### Guard 5 - nothing outside a strict charset reaches the curl config stream

**Property.** The R2 access key id and secret are shape-checked before `printf 'user = "%s:%s"\n' ... | curl --config -`, and a failed check records `escrow=missing` with no curl call and no credential bytes in any output.

**Assembly.** Every `curl --config -` site that streams a credential in `apps/web-platform/infra/*.sh` (measured: `workspaces-luks-provision.sh:_curl` is the only R2 one; `cutover-verify.sh` streams a different credential and is out of this property); within `_escrow`, the order of the shape check relative to the `_curl` definition. The suite records the curl stub's stdin.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Key id containing a double quote plus a second config directive line | RED if streamed; the compliant code records `shape` and never invokes curl |
| 2 | Secret containing a newline, backslash, space, or a control byte (four sub-cases) | RED if streamed |
| 3 | Empty and over-length values | `shape` or `creds`, no curl call |
| 4 | Delete the shape check | RED |
| 5 | Harness: the curl stub that records nothing | RED (an unrecorded stdin cannot certify "no bytes streamed") |
| H2 | Must-PASS: a 32-hex id and a 64-hex secret, and a mixed-case alphanumeric id | the upload path is reached |

**Anchor.** The vendor's credential format is the external fact; the regexes are deliberately wider than it, so the anchor is the injection-class property (no quote, backslash, whitespace, control byte), which does not move with a vendor format change.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-263 (no new ADR; it is the owning record and the owner asked for the addendum there). Tasks (Phase 6.1): rewrite D7's passphrase sentence; add D8 (rotation HALT + escrow gate + paging); rewrite "Shared-passphrase residual"; fix Consequences counts; record decisions A1, A2, B1, B2 with their rationale and the Cut List items. The status stays `adopting`; the claim "web-2 is LUKS-backed at boot" is still conditioned on #9372. Run through `soleur:architecture`.

### C4 views

All three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` must be READ in full at work time; the plan-time enumeration, against what was read of `model.c4` (the `doppler -> hetzner` edge) and the ADR, is: (a) external human actors: none new (the dispatching person already exists); (b) external systems: Doppler, Hetzner, Cloudflare R2, Sentry, GitHub Actions, Better Stack, all already modeled; (c) containers and stores: no new store (a new secret value in the existing Doppler secret-store, a new value in existing state); (d) access relationships that change: the web-class token no longer reaches web-1's passphrase (one clause on the `doppler -> hetzner` edge text, which today describes only the escrow pair). The CI preflight is not a new relationship (the `github -> doppler` edge already exists and the check is a names-only read), so that edge is not edited. Tasks: add the one clause, regenerate the JSON, run `c4-count-parity.test.sh` (a derived cardinality on the `github -> sentry` edge may move with the alert counts: it does not here, 3 rules updated, none added, but the gate is run anyway) and the two C4 vitest files. A "no further C4 impact" claim stands only with those runs green.

### Sequencing

The ADR describes the target state with `adopting`; nothing is postponed to a follow-up issue.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/workspaces-luks-header-web.tf`: one new `random_password` (provider `hashicorp/random`, already pinned) and one changed `value` reference. No new variable, no operator-supplied default (hr-tf-variable-no-operator-mint-default). `apps/web-platform/infra/sentry/issue-alerts.tf`: in-place condition-list edits on 3 existing alerts.

### Apply path

(a) The Terraform change rides the existing push-apply `-target` list when that workflow is enabled (a first create, since the key secret was never applied). Nothing is applied by this PR. (b) The Sentry edits apply automatically on merge through `apply-sentry-infra.yml` (in-place). No host change, no downtime.

### Distinctness / drift safeguards

The two passwords are independent resources with no shared input. `prevent_destroy` on the new one; the widened HALT; the gates' naming; `lifecycle.ignore_changes` absent on both. Dev and prd are untouched.

### Vendor-tier reality check

None: no new vendor resource and no paid-tier gate.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (owner decision carried forward)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The direction is sound. Incorporated: `prevent_destroy` on the new password; a table-driven cross-gate census; fail-closed semantics (exit 1/3/2 all fail the step; no `|| true`); scope the provider token to the single step and keep it out of `GITHUB_ENV`; keep the byte budget by putting logic in committed scripts; move the stage rather than add a rule; the census must fail on an empty set and name an exempt list with reasons (`apply-deploy-pipeline-fix.yml` and `workspaces-plaintext-forget.yml` considered, the first exempt by its `host_creates` HALT, the second by having no `terraform apply`); wording says "narrowed". Noted and tracked: the provider token is a write-capable workplace token, so a read-only preflight token is a deferred follow-up (Phase 7.4).

### Legal (CLO)

**Status:** reviewed
**Assessment:** No blocker. Replace the shared-passphrase sentence in the Article 30 register and the compliance posture, and the second "the passphrase is still shared" clause in the same cells, scoped to NEW births (the pre-split token still reads web-1's config until retired). Ledger evidence and `does_not_defend` updated; `disclosed_as` stays `not-publicly-claimed`. No published privacy or GDPR document needs an edit (the "Encrypted workspace storage" wording is scoped to web-1's served volume). Re-attest at #9372 and before web-2's serving weight rises; record a passphrase-loss recovery path when data lands (Art. 32(1)(c)). Wording is conditional until this merges.

### Product/UX Gate

**Tier:** none
**Decision:** no user-facing surface (no page, component or flow); the decisions are the owner's, recorded on #9377.
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** no UI surface

## Downtime & Cutover

None. No host, volume or live credential changes in this PR. Sequence for the gated work that follows (not part of this PR), corrected after
plan review: the web-class config, its token and its secrets were first declared in #9397 and exist only once the push-apply creates them, so
there is nothing to mint the R2 pair into before that. Order: (1) a reviewed plan, then enabling the push-apply (its first run also applies
everything merged since 2026-10-01, under a HALT that permits creates); (2) the live R2 mint and its two-way signed `HEAD` isolation proof
(#9377 item 1); (3) the escrow preflight now passes; (4) #9372. The widened HALT and the preflight are in place before any of them. This PR
must merge BEFORE step 1: if the push-apply were enabled between #9397 and this PR, it would create the key from the shared password and the
swap would then plan as an UPDATE that the new HALT stops (recovery: treat the swap as a rotation of a never-formatted key and re-create the
Doppler secret and its state entry under review; recorded in the ADR). The disabled state is re-measured at ship.

## Scope Check

<!-- lint-infra-ignore start: quotes the requesting brief verbatim; prescribes no step -->

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "no terraform apply, no workflow_dispatch, no Doppler write, no Cloudflare/R2 mint, do not enable apply-web-platform-infra.yml; the PR body must state this" [brief] | Overview, Merge-time effects, Phase 0.2, Phase 7.5 | mapped |
| 2 | "the web-host config prd_workspaces_luks_web must get its OWN passphrase from a new random_password" [brief] | Phase 1.1, 1.7 | mapped |
| 3 | "update the escrow census/readiness checker (scripts/check-web-host-escrow-config.sh) and tests" [brief] | Phase 1.3, 1.4, 3.1, 3.4 | mapped |
| 4 | "the provisioner/monitor expectations" [brief] | Phase 1.5 | mapped |
| 5 | "the Article 30 register / compliance posture wording" [brief] | Phase 6.2, 6.3 | mapped |
| 6 | "ADR-263 'Shared-passphrase residual' + D7" [brief] | Phase 6.1 | mapped |
| 7 | "Decide and record whether a non-bypassable HALT on rotating either random_password for workspaces LUKS in the push-apply is needed ... implement it if yes" [brief] | Decision D-A2, Phase 2.1 to 2.4 | mapped |
| 8 | "Enforce check-web-host-escrow-config.sh --live as a workflow preflight/gate on EVERY route that can create a web host" [brief] | Decision D-B1, Phase 3, Guard 3 | mapped |
| 9 | "make escrow=missing on a web-class birth page a person" [brief] | Decision D-B2, Phase 4.1 to 4.4, Guard 4 | mapped |
| 10 | "shape-validate the R2 key id/secret before the curl config stream" [brief] | Phase 5, Guard 5 | mapped |
| 11 | "add Sentry op resolve_link_local to the routed alert set" [brief] | Phase 4.1 to 4.3 | mapped |
| 12 | "the cutover gate luks_passphrase_touched clause naming the web key copy" [brief] | Phase 2.3 | mapped |
| 13 | "the by-name web-1 refusal in tests/scripts/lib/web-host-replace-gate.sh stays first and untouched" [brief] | Phase 2.3, diff-scope AC | mapped |
| 14 | "never write state/secrets to files; do not touch other sessions' worktrees or the main checkout" [brief] | Phase 3.4 (suite tokens are synthetic), all phases (this worktree only) | mapped |
| 15 | "Work targets only OPEN issue #9377" [brief] | `refs` and `Ref #9377`, Phase 7.3 | mapped |
| 16 | "record them in the ADR-263 addendum and on #9377" [brief] | Phase 6.1, 7.3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `random_password.workspaces_luks_web` and its `prevent_destroy` | "must get its OWN passphrase from a new random_password" (ask 2) | asked; `prevent_destroy` inferred - justification: an independent plan-time layer for the non-bypassable-rotation ask 7, covering the point before CI sees the plan |
| Passphrase-distinct static clause (Guard 1) | "update the escrow census/readiness checker" (ask 3) | asked |
| Reusable preflight wrapper `scripts/web-host-escrow-preflight.sh` and its suite | "Enforce check-web-host-escrow-config.sh --live as a workflow preflight/gate on EVERY route that can create a web host" (ask 8) | inferred - justification: the birth jobs cannot run the checker without the provider token, and one reusable line is what keeps the #9372 rebirth route (a separate workflow) from hand-copying the credential plumbing; it also keeps the 482 KB workflow inside its byte gate |
| Job-reach row in `terraform-target-parity.test.ts` | "implement it if yes" (ask 7) | inferred - justification: the HALT lives in one job, and the reach of the web copies must stay confined to it or a second apply path rotates without the gate (the 2026-09-24 learning) |
| Workflow census (`web-host-escrow-preflight-census.test.ts`) | "on EVERY route that can create a web host" (ask 8) | asked |
| Provisioner no-fallback regression case | "the provisioner/monitor expectations" (ask 4) | asked |
| Moving the escrow stage between rules | "make escrow=missing on a web-class birth page a person" (ask 9) | asked |
| Runbook Step 0 rewrite, rationale-runbook note | "rather than a person-run runbook step" (ask 8) | asked; the rationale-runbook note is inferred - justification: ADR-231 requires rationale to relocate out of the 482 KB workflow |
| Tracking issue for the read-only preflight token | "Enforce ... as a workflow preflight" (ask 8) | inferred - justification: the deferral-tracking rule (a deferral without an issue is invisible) |
| ADR-263 D8 | "record them in the ADR-263 addendum" (ask 16) | asked |

### Split Assessment

- Subsystems touched: 6 - `apps/web-platform`, `.github`, `tests`, `scripts`, `plugins/soleur`, `knowledge-base`
- Planned files: 38 | Estimated changed lines: about 1,400, of which roughly 60 percent are test and mutation rows
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the brief asks for one offline PR and states the sequencing (this precedes the #9372 PR). The natural seam (A: passphrase + HALT, B: gate + paging) is deliberately not taken: B's census must see A's HALT and the escrow checker is edited by both, so two PRs would conflict on the same four files and leave a window where the passphrase is distinct but unguarded.

<!-- lint-infra-ignore end -->

## Acceptance Criteria

### Functional

- [ ] `workspaces-luks-header-web.tf` declares `random_password.workspaces_luks_web` (length 40, `special = false`, `prevent_destroy = true`, no `ignore_changes`, no `keepers`) and the web-class `WORKSPACES_LUKS_KEY` secret's value is `random_password.workspaces_luks_web.result`. The authority for "no other code path names web-1's password" is the checker's comment-stripped `--static` census (a raw `rg` would also match the contrast comments the header legitimately keeps), and W8 in `workspaces-luks-header-web.test.sh`.
- [ ] `bash scripts/check-web-host-escrow-config.sh --static` prints `escrow-split-contract:ok` on the real tree, and `bash scripts/check-web-host-escrow-config.test.sh` passes with every Guard 1 mutation row RED.
- [ ] `luks_passphrase_rotations` counts the six addresses; `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` passes with a RED row per removed address; a first-create fixture and a no-op fixture score 0.
- [ ] In the `apply` job the rotation HALT block sits before the `destroy_count` sum and does not read `ack_destroy`; the job-scoped, comment-stripped assertion (`T60g` style) passes.
- [ ] The cutover, recut and replace gates each name the web copy and the new password in their passphrase clause, and each gate suite has a RED row (`gate_mutate_and_check`) for the removed address; the `terraform-target-parity.test.ts` job-reach row passes (web copies only in the `apply` job; the HALT block present there).
- [ ] `web_host_create` and `web_host_replace` each contain the escrow preflight step before any Terraform command with no `if:`, no `continue-on-error`, no `|| true`; `bun test plugins/soleur/test/web-host-escrow-preflight-census.test.ts` passes with every Guard 3 mutation RED, and a fixture rebirth-shaped workflow without the step is RED.
- [ ] `web-host-luks-boot-fatal` lists 14 stages including `workspaces_luks_provision_escrow`, `web-host-luks-boot-warning` lists 3; `egress_blocked` lists `resolve_link_local`; `alert-reference.json` matches. Verified by the two op-contract suites (`bun`/`vitest` per `apps/web-platform/package.json scripts.test`) and by `jq -r '."web-host-luks-boot-fatal".actionFilters[0].conditions[0].comparison.value | split(",") | length' apps/web-platform/infra/sentry/alert-reference.json` printing `14` (and `3` for the warning rule).
- [ ] `_escrow` rejects a key id or secret outside the strict charset without invoking curl; `bash apps/web-platform/infra/workspaces-luks-provision.test.sh` passes with the Guard 5 rows.
- [ ] ADR-263 carries the addendum: `rg -c 'D8' <ADR>` is at least 1 and `rg -c 'the same .WORKSPACES_LUKS_KEY. unlocks' <ADR> knowledge-base/legal/*.md scripts/encryption-posture-ledger.json` prints 0 for every file (the superseded sentence is gone); the Article 30 register cell and the compliance posture cell carry the same replacement sentence (`diff <(rg -o 'NARROWED on merge[^|]*' knowledge-base/legal/article-30-register.md) <(rg -o 'NARROWED on merge[^|]*' knowledge-base/legal/compliance-posture.md)` is empty); the ledger row text is updated and the `scripts/lint-encryption-posture.py` suite passes.
- [ ] The cutover gate names `doppler_secret.workspaces_luks_web_key` and `random_password.workspaces_luks_web` in `luks_passphrase_touched`.

### Non-functional / process

- [ ] Byte budget: `wc -c .github/workflows/apply-web-platform-infra.yml` is at most 485,300 (net growth at most 2,500 from 482,795) and `bun test plugins/soleur/test/workflow-file-size.test.ts` passes.
- [ ] Diff-scope for the replace gate (a command that fails on any stray edit, including to the refusal): `git diff origin/main -U0 -- tests/scripts/lib/web-host-replace-gate.sh | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE 'passphrase|workspaces_luks'` prints nothing.
- [ ] No workflow other than the one named is edited: `git diff --name-only origin/main -- .github/workflows` lists only `apply-web-platform-infra.yml`. `scripts-shard-totality.test.sh` passes with the new suites registered (shard manifest updated if it demands it).
- [ ] `python3 scripts/lint-guard-contract.py` passes over this plan, and the CI invocation of the human-step sentinel, not a hand-listed path set, is green: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (it covers this plan, the tasks file, the ADR and the edited runbooks).
- [ ] The first line of the PR body answers "does merging this alone mutate production?": the web-platform and deploy-pipeline-fix applies are disabled and untouched; the only automatic effect is the in-place Sentry alert update through `apply-sentry-infra.yml`. The body also states no live step was performed, `Ref #9377` and not `Closes`, and carries the Merge-time effects table (workflow states re-measured at ship).
- [ ] The two new preflight steps carry `timeout-minutes: 2`; the checker's Doppler calls are bounded by the CLI's own HTTP timeout (`doppler --help` lists `--timeout duration`, default 10s, measured at plan time).
- [ ] A comment on #9377 records decisions A1, A2, B1, B2 and the still-open items; a tracking issue exists for the read-only preflight token.

### Post-merge (verification only, no write)

- [ ] `gh run list --workflow apply-sentry-infra.yml --limit 1 --json conclusion` reads `success`, which confirms the in-place alert update.
- [ ] `gh api repos/jikig-ai/soleur/actions/workflows --jq '.workflows[]|select(.path|test("apply-web-platform"))|.state'` still reads `disabled_manually`.

## Test Scenarios

1. Replace fixture: `random_password.workspaces_luks_web` `["delete","create"]` plus `doppler_secret.workspaces_luks_web_key` `["update"]` with an unrelated `["delete"]` in the same plan, commit message carrying `[ack-destroy]` -> the apply job aborts at the rotation HALT, not the ackable gate.
2. First-apply fixture: both new web resources `["create"]` -> counter 0, apply proceeds to the ackable gate (which has nothing to ack).
3. Birth dispatch with the web config missing the R2 pair names -> the preflight exits 1 with the cause line naming the mint; no Terraform command ran.
4. Birth dispatch with a config-scoped token only -> exit 3 (`does not have access to requested config`), treated as unreadable, never as absence.
5. Provisioner: stub `doppler` returns an empty key under `prd_workspaces_luks_web` -> fatal `key` arm, the stub never saw `prd_workspaces_luks`.
6. Provisioner escrow with a key id containing a double quote -> `escrow=missing` reason `shape`, the curl stub records zero invocations.
7. Sentry contract: moving the escrow stage back to the warning list reds the op-contract suite.
8. Census: a fixture workflow with `terraform apply` against `hcloud_server.web["web-2"]` and no preflight reds the census.

## Deferred, gated follow-ups (tracked; none executed here)

| Item | Tracker | Gate |
|---|---|---|
| Live R2 pair mint into `prd_workspaces_luks_web` (only possible after the push-apply has created the config), with a signed `HEAD` of web-1's bucket returning 403 with the new pair and the reverse | #9377 item 1 | after the push-apply's first reviewed run, before #9372 dispatches |
| Retire the pre-split token `doppler_service_token.workspaces_luks_fresh_boot` (confirm destroyed, confirm from Hetzner `created` timestamps that no live host received it) | #9377 item 4 | after the live mint |
| Census proofs for the provisioner write census / escrow census / marker census; runtime link-local-in-live-chain assert in `cron-egress-postapply-assert.sh` | #9377 item 6 (remainder) | with the next hardening pass |
| Read-only, project-scoped Doppler token for the preflight | new issue filed in Phase 7.4 | before the #9372 workflow is reusable for a second host |
| Single-use web-2 rebirth workflow | #9372 (separate PR, after this one) | must pass the Guard 3 census |

## Risks

- **The swap becomes an UPDATE if anything applied the web-class secret.** Mitigated by the Phase 0.2 re-measurement and the workflow-disabled evidence; if either fails, stop and take the HALT's route (a deliberate, reviewed state change), because the new HALT will stop an UPDATE on `doppler_secret.workspaces_luks_web_key`.
- **The preflight credential is unmeasured offline.** `TF_VAR_doppler_token_tf` is a workplace-scope personal token (per `variables.tf` and `git-data-luks.tf`), and the checker's stub replays the CLI contract, but no live Doppler call is made here. The first real read is the first dispatch; the gate fails closed (exit 3/2 aborts the job), so the failure mode is "a birth is blocked until the token path is fixed", never "a birth proceeds ungated".
- **The preflight uses a write-capable token.** Names-only and token-redacted; in the Tier-B arm the token is already ambient in the job environment (loader export, masked), so this adds a new reader, not a new exposure; in the legacy arm the wrapper's single-secret read is registered with `::add-mask::` and shape-checked. A read-only token is a tracked deferral.
- **Editing a baked host script changes `host_scripts_content_hash`.** A new image must carry it before any birth; the coherence preflight in both birth jobs enforces this and the #9372 PR must pass an explicit `image_tag`.
- **Paging semantics:** `escrow` pages on every web-class birth that cannot reach the bucket, including a replaced host whose escrow was already fine and whose R2 pair was later revoked. That is the intent (a header with no off-host copy is a single-point loss), and the page names the reason in `extra`.
- **The workflow census is heuristic about "can create a host".** Job text containing `terraform apply` and `hcloud_server.web[` is a deliberately sensitive predicate; the exempt list is explicit and each entry is pinned by its refusal. A creation route that builds the address dynamically would evade it; the floor and the default-unexempt rule bound that, and review of any new workflow stays the backstop.
- **"First create is legal" cannot tell a true first create from a state loss.** If the Terraform state were lost or rewound after a web-class volume was formatted, both web resources would plan as `create` and the Doppler provider would overwrite the live secret. The HALT cannot see this; the ADR records it as a known limit and the state bucket's own protections are the control. Not mitigable in this PR.
- **Any provider-driven UPDATE of the web key wedges the whole push-apply** (only `[skip-web-platform-apply]` bypasses). The inngest pair already accepts this trade; the web pair gets the same.
- **`prevent_destroy` on the new password also blocks a legitimate teardown of the web-class config.** The retirement path (remove the lifecycle line under review in the same change that removes the resource) is written into the ADR.
- **The preflight depends on the provider token's lifecycle.** The Tier-A eviction and the revocation of `DOPPLER_TOKEN_TF` (runbook `infra-credential-tiers-8209.md`, O10/O13) must keep the Tier-B `TF_VAR_doppler_token_tf` export; the wrapper prefers the environment value for that reason.
- **The preflight runs after the reviewer approval of the dispatch environment**, so a failed check spends an approval. Moving it to a preceding ungated job is a taste call recorded in `decision-challenges.md`.
- **Pre-split token.** Until retired it still reads web-1's config; the Article 30 text is scoped to NEW births and says so.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, carries only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `single-user incident`.
- The new HALT must be proven against the tree its own remediation produces: after the swap the web-1 password leaves the push-apply graph, so its address in the list is dormant by design (defense in depth, and the owner asked for both passwords); the gates' per-address removal rows keep it from being "tidied" away.
- `terraform-target-parity.test.ts` treats an undeclared or untargeted resource as a failure in both directions: the new password needs the `-target` line and the `freshBoot` list entry in the same change.
- The op-contract test's quiet/paging split is by stage name; moving `escrow` requires the explicit `PAGE_AT_WARNING` carve-out or the "a quiet stage is never emitted at level fatal" and "a warning never reuses a paging arm's stage name" rows contradict the new design.
- The wrapper must never put the provider token on argv, in a file, in `GITHUB_ENV` or on stdout, and must refuse xtrace as its first statement (before the fallback read, where the token is not yet set); its suite pins each, including the mask and shape check on the fallback value.
- Plan prose here avoids human-actor words next to infrastructure verbs (the `lint-infra-no-human-steps` sentinel); the quoted brief sits inside a paired ignore region.
- If the Guard 3 census matched any mention of `hcloud_server.web[` it would be red on day one (three jobs loop over that address in `jq` state checks); the predicate is a `-target`/`-replace` argument. If it is written against `run:` text only it misses a job that calls a composite action which applies; assert on the job's whole non-comment text.
