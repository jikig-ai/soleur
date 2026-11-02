---
title: "feat: split the Inngest host Doppler token into a read-only boot token and a root-only flip token"
date: 2026-11-01
slug: inngest-flip-token-split
branch: feat-one-shot-inngest-flip-token-split
issue: 9927
ref: 9927
closes: none
type: feat
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: split the Inngest host Doppler token into a read-only boot token and a root-only flip token

> Corrected 2026-11-01 (review round, PR #11815 panel; rulings R7-R11 in `decision-challenges.md`, which govern where this plan differs). (1) The 512 B cap-headroom floor and every stored/headroom figure below (572 B, 104 B under 32,300, "at least 512 B") are superseded: the floor is 384 B, measured with high-entropy stubs for all five secrets, and `INNGEST_GZIP_BUDGET` is not compared with the script's number (R7). (2) The replace job's budget step runs `--cap-only` (R9). (3) The claim that the `cutover-inngest.sh` G3/G3.7 liveness gates catch a dead flip token is withdrawn: they count the unit's tagged error rows as audible (R11). (4) "First flip: `op=arm`" is wrong: a replaced host inherits `done`; the first flip-token READ is the unit's own tick, the first WRITE is the `flushed` arm after `op=resume` (R11). (5) The recovery shape "both tokens no-op, server create, re-dispatch" is replaced by the runbook's state-to-dispatch matrix (R9). (6) "readable through the Hetzner metadata API by anyone with host access" means any local process on the host. The original text below is left as written.

> Corrected 2026-11-02 (fix round 2; rulings R12-R14 in `decision-challenges.md`). (7) The replace gate is no longer "exact equality, no per-address action rule" for the two tokens: R10 added the `doppler_token_touched` counter, so an `update`, a bare `delete` or a `forget` on either token aborts (only `no-op`, `create`, `delete`+`create` and `create`+`delete` pass). (8) The 384 B floor is a PR-visible policy check, not a merge gate: the `infra-validation` job `inngest-userdata-budget` and the floor rows of `cloud-init-user-data-size.test.ts` are not required status contexts (#6480), the hard gate is the 32,768 B Hetzner cap enforced by `--cap-only` before any destroy, and the owner checks the `inngest-userdata-budget` check on the head commit before the replace go (R13). Wherever this plan says the floor is enforced by a required job, read this note. (9) The text tripwire over the flip script (`T-flipsh`) is deleted and replaced by a runtime canary scan in `inngest-cutover-flip.test.sh` (R14); it never guarded the live host. The canary covers only the paths the suite exercises (not an unreached branch, the config-bundle copy, or children of `doppler run`), and runtime `*.service.d` drop-ins plus the bundle copy stay under #11816. (10) The write guard's residual is amended by R12: `/etc/default/inngest-doppler` is `.`-sourced as root, so an extra bare-word line there would execute as root (reachable only through a hostile Doppler API response, not new in this PR, accepted; the `dp.` prefix check is deferred until at least 50 B is reclaimed). (11) "Every `apply_target=inngest-host` dispatch aborts until the replace" holds for a live host only; the runbook's state-to-dispatch matrix lists the absent-host states that pass it. (12) The owner-run commands use the post-cutover Tier-B nested-loader form, not the single-loader form. (13) "Read only by the cutover-flip unit" (several places below) means consumed as an `EnvironmentFile` only by that unit; the log redactor also reads the flip file by value with `sed`, and only that file is never sourced (`/etc/default/inngest-doppler` is `.`-sourced as root).

Spec lane note: no `spec.md` exists for this branch (one-shot path, no brainstorm), so `lane:` took the fail-closed default `cross-domain` (TR2). The domain sweep below was run by hand and found engineering only.

## Enhancement Summary

**Deepened on:** 2026-11-01. **Agents and passes used:** repo-research-analyst, learnings-researcher, functional-discovery (no overlap), CTO (three rounds: R1-R6, N1-N7, N8-N12), CPO advisory, plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow), security-sentinel, observability-coverage-reviewer, test-design-reviewer, terraform-architect, a mechanical verify-the-negative pass (re-run by hand after the agent returned nothing), local measurements (userdata budget prototype, `systemd-analyze`, `systemd-run`, sed probes), and the Phase 4.6-4.13 gates (lint-infra-no-human-steps, lint-guard-contract, technical-ruling-gate, rule-id and PAT sweeps all pass).

### Key improvements
1. **Byte budget is measured and now enforced**: both stubs high-entropy (58-char tokens), a 512 B headroom floor added to the budget script, final prototype 32,196 B stored / 572 B headroom / 104 B under 32,300; the drop-in lost its Condition and the phone-home (CTO N1/N2), which returned the margin.
2. **First-replace hazard found**: with both token keys unknown at plan time the `user_data` length precondition is deferred to apply (after the destroy), so the budget script becomes a step inside `inngest_host_replace` before the plan (N9).
3. **A wrong tool in the ruling was caught by measurement**: `systemctl --root cat` is refused by systemd; section X now uses `systemd-analyze verify`/`cat-config` and the Tier B systemd container (`systemctl show -p EnvironmentFiles`) with CI fail-closed skips (N7, N11).
4. **Real recovery routes recorded** (N4): no dispatch rotates the flip token alone; revoked-token and guard-refusal recovery are owner-only; scenario 10 rewritten. Follow-ups filed: #11816, #11817, #11820.
5. **Merge-time blast radius stated** (N6): merging changes nothing in production, and every `inngest-host` dispatch aborts until the owner-gated replace.

### New considerations discovered
- The dotted `dp.st.<cfg>.<body>` token shape defeats both the redactor backstop and the phone-home dp-mask (one-byte fix included, N12).
- The plan's `#6890` rewrite scope is one file, not two; the second file's stale claim is the untracked `FLIP_READ` token paragraph.
- Pre-go rehearsal is a recommended owner option (N5), not an authorization; the Doppler write from the `ProtectSystem=strict` sandbox stays unmeasured until the first real flip.

## Overview

Build the token split decided in the ADR-282 addendum dated 2026-10-30, item 4 of #9927
("Addendum - 2026-10-30 (#9927 item 4, the flip-token design)" in
`knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md`).
After this PR merges, a replaced Inngest host carries two Doppler credentials on the isolated
`soleur-inngest/prd` config instead of one read/write credential:

- `doppler_service_token.inngest` (the boot token) becomes `access = "read"`. BOTH on-host copies
  of it downgrade together: `/etc/default/inngest-doppler` (0600 root) and
  `/etc/default/inngest-server` (0640 root:deploy).
- A new `doppler_service_token.inngest_flip` (`access = "read/write"`) is written to a new root-only
  0600 file `/etc/default/inngest-flip` and read ONLY by `inngest-cutover-flip.service`, through a
  cloud-init `write_files` drop-in whose later `EnvironmentFile=` overrides `DOPPLER_TOKEN`.

Code and tests only. Hard limits from the brief, restated as constraints on every phase: no
`apply_target=inngest-host-replace` dispatch, no config-bundle build or `INNGEST_CONFIG_DIGEST`
promotion, no Hetzner or Doppler write, no token minted. The owner has deferred the replace until
this build is done and will give a fresh in-session go; this PR delivers the code that replace will
carry. It uses `Ref #9927`, never `Closes`: the epic stays open (owner hold).

## Research Insights

### Premise Validation (Phase 0.6)

Checked with `gh`/`git` on 2026-11-01. Held: #9927 open (epic, items 2 and 4 ride the next host
replace); #6890 CLOSED (not planned), so the ADR's "no open tracker" is correct; #11265 and #11266
open; #11664 MERGED (bootstrap pin bump, 2026-10-30); #11602 CLOSED (host_metrics trim, live on the
replaced host, needs nothing); #6178 open (epic). The mechanism (a split token with a drop-in
override) is the ADR's own decision, not a rejected alternative; the ADR's rejected alternative (a
separate Doppler config for the flag) stays rejected. Collision pre-check
(`collision-precheck.sh 9927`): no open PR names #9927; the only hits are two foreign
`test-all.sh` processes owned by another worktree (`feat-one-shot-11648-fast-tier-demotion`), not
this work. Stale or inexact premises found: see the Research Reconciliation table.

### Property List (Phase 0.6b)

1. The leak surface for a write-capable token is narrowed: a leak of the boot token (the 0640 file read by app-user units, deploy-user env, shared logs) can read `soleur-inngest/prd` but can no longer overwrite the LUKS passphrase pair. Wording rule for the PR body and runbook: "leak surface narrowed", never "unreachable by deploy" (a deploy-user process is root-equivalent through the docker group and NOPASSWD sudo, #11816).
2. The cutover-flip FSM can still write `INNGEST_CUTOVER_FLIP`, under a token that only the flip unit's process sees.
3. No unit other than `inngest-cutover-flip.service` resolves the flip token through its effective `EnvironmentFile=` list.
4. The flip file is written safely: charset-guarded before any write, mode 0600 root, written before the provision unit is armed; a refusal aborts the runcmd.
5. The plan-time gates admit exactly the one new address and no lookalike, and the shape gate stays in lockstep with the `inngest_host` job's `-target` list.
6. `user_data` still fits the 32,768 B cap with at least 512 B of cap headroom and under `INNGEST_GZIP_BUDGET` (32,300).
7. The flip token is scrubbed from shared log tails, by value.
8. A flip file that fails to be written aborts the runcmd before the host arms (fail closed), and a flip file missing later fails the flip unit loudly (unprefixed `EnvironmentFile=`, no Condition, no fallback to the read-only token). Ruled N1/N2.
9. No code comment points at the closed-not-planned #6890 as the home of this design.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | What already covers it, or why cut |
|---|---|---|
| A separate Doppler config for `INNGEST_CUTOVER_FLIP` | 1, 2 | ADR-282 rejected alternative (touches the flip guard, bootstrap flag read, `cutover-inngest.yml`, apply preflight); stays later hardening |
| A `-target` on the `inngest_host_replace` job | 5 | The replace job pulls the token in as a `hcloud_server.inngest` dependency, exactly as it does `doppler_service_token.inngest` today (CTO R1); the replace gate `def allow` is the admission point |
| `create_before_destroy` or a rotation ordering guard on the tokens | none new | Terraform destroys dependents first; recovery is the existing `stock_recovery_report` re-dispatch (CTO R6) |
| A dedicated charset-guard block and phone-home tag for the flip token | 4 | Widening the existing guard heredoc into a loop over both tokens is byte-cheaper and keeps the guard in one place (measured, see the table below) |
| An explicit `--token` on `flag_set` in `inngest-cutover-flip.sh` | 2 | The drop-in makes the ambient token the flip token; editing the script would change a config-bundle and image-baked member (see Files NOT to Edit) |
| Delivering the drop-in through `infra-config-install.sh` DEST_SPEC / the config bundle | 3 | It would reach a running host without a replace but would widen the root helper's dest set (HARD-1 in `inngest-config-refresh-set.txt`) and needs a bundle build, which the brief forbids; cloud-init `write_files` is the birth path |
| A new rehearsal-root flip token | none | The rehearsal never arms the flip; it passes its existing read token as `doppler_flip_token` (Phase 2) |
| #11265 standalone keeper in `STAGED` | none for this PR | Separate PR (CTO R3) |
| #11266 bundle delivery, digest promotion, feeder dead-man | none for this PR | Owner-gated and outside the hard limits; cited as unchanged |
| Raising `INNGEST_GZIP_BUDGET` | 6 | Not needed; measured fit (CTO R2) |
| Drop-in `ConditionPathExists` plus a `flip-file-written` phone-home | 8 | Cut by CTO N1: the flip service and timer exist only after the runcmd write, a failed write aborts runcmd, and a Condition would turn a loud failure into a silent skip |
| A separate `flip-file-write-FAILED` phone-home | 8 | Cut by CTO N2: `|| exit 1` plus the missing `provision-unit-armed` row is the existing detector |
| A new alert for a stalled or revoked flip token | none new | CTO N8: not added here (a per-merge-applied alert falsifies the merge-changes-nothing sentence; a logs query cannot suppress itself in the replace window); pre-arm coverage is the G3.7 liveness refusal; follow-up #11820 |

### Value-Proposition Measurement (Phase 0.6c)

The plan's byte claim is a measured one, not a saving. Command: `bash apps/web-platform/infra/inngest-userdata-budget.sh` (real terraform `templatefile`/`replace`/`base64gzip`). Baseline on this branch: stored 31,996 B, cap 32,768 B, headroom 772 B (matches the ADR's recorded figure; #11664 changed a digest pin of the same length, not the size). A scratch prototype (a copy of the infra directory under the session scratchpad; no repo file touched) of the full design measured:

| Variant (all with the drop-in, widened guard loop and flip-file write line) | Stored | Cap headroom | Under 32,300 |
|---|---|---|---|
| Repo's existing low-entropy `STUB` stubs, flip stub low-entropy | 32,052 B | 716 B | by 248 B |
| Flip stub high-entropy (43-char sha512-derived body) | 32,108 B | 660 B | by 192 B |
| Both token stubs high-entropy | 32,156 B | 612 B | by 144 B |
| Both high-entropy + redactor by-value line + flip-file phone-home (the design before plan review) | 32,220 B | 548 B | by 80 B |
| Design after the first CTO round: both high-entropy (43-char bodies), redactor by-value line (one `vals+=` line), drop-in without a Condition, no phone-home, write ends `|| exit 1` | 32,180 B | 588 B | by 120 B |
| FINAL design: the row above with 48-char bodies for both stubs (the budget script's existing stub body width, CTO N12 default) and the phone-home dp-mask one-byte fix | 32,196 B | 572 B | by 104 B |

The existing stubs are length upper bounds but NOT entropy upper bounds: a repeated `STUB` run gzips to almost nothing, a real token does not, so the repo's measured headroom is optimistic by about 44 B per distinct token. The final row clears the CTO's 512 B hard floor by 60 B and is the figure CI will now gate (N3). The real Doppler token body width is unverified (the budget script's comment says about 43 B; no repo fixture records a real one, CTO N12), which is why the stubs use the wider 48-character body. Nothing else may be added to `cloud-init-inngest.yml` code in this PR (comments are stripped before gzip and are free). Re-measure in the work phase: the prototype is a scratch copy, not the committed edit. The first-replace caveat (CTO N9): both token keys are unknown at plan time on that replace, so the `hcloud_server.inngest` `user_data` length precondition is deferred to apply, after the destroy; this stub-based measurement is therefore the only pre-destroy gate, which is why the budget script now runs inside the replace job.

### Repo research (Phase 1) - sites that change or must be checked

- `apps/web-platform/infra/inngest-host.tf`: token resource (`resource "doppler_service_token" "inngest"`, `access = "read/write"`), the `templatefile(` var map (`doppler_token = doppler_service_token.inngest.key` is the only consumer of that key, per CTO grep), stale comments at the token resource ("tracked in #6890") and the `MEASURED` comment in the strip-local block ("stored 10,892 B").
- `apps/web-platform/infra/cloud-init-inngest.yml`: `write_files:` (top; no `inngest-cutover-flip.service.d` precedent on this host), the first write-guard runcmd item (heredoc `SOLEUR_WRITE_GUARD_EOV` over `${doppler_token}`), the `/etc/default/inngest-server` printf and `chown root:deploy` items, the `inngest-redact.sh` value list (`. /etc/default/inngest-doppler 2>/dev/null; vals+=("$DOPPLER_TOKEN")`), and the `STAGED=` list (untouched).
- The baked unit `inngest-cutover-flip.service` (`EnvironmentFile=/etc/default/inngest-server`, `ConditionPathExists=/etc/default/inngest-server`) and `inngest-cutover-flip.sh` (`flag_set` is the ONLY Doppler secret write on the host) are OCI-baked assets and `inngest-cutover-flip.sh` is also a config-bundle member. Not edited.
- The `10-inngest-*-doppler-token.conf` drop-ins in `apps/web-platform/infra/` are the co-located WEB host's (delivered by `server.tf` / `infra-config-install.sh`), not a precedent for this host.
- Readers of the two env files (all read-only uses, so a read token suffices): inngest-server, heartbeat, probe, trace-retention, vector, inngest-redis (+ its bootstrap), the verify unit, inngest-config-refresh, inngest-luks-open, soleur-inngest-provision, and the cloud-init runcmd blocks.
- Bootstrap "preserve" branch (`inngest-bootstrap.sh`) keeps a `^DOPPLER_TOKEN=dp\.` line in `/etc/default/inngest-server` and only appends project/config; a read token (`dp.st.`) still matches. No interaction with a separate flip file.
- Template callers (census by `git grep -n 'inngest_doppler_config *='`, re-run at work time): `inngest-host.tf` (production), `inngest-provision-rehearsal/rehearsal.tf` (rehearsal; its token is already `access = "read"`), `inngest-userdata-budget.sh` stub map, `inngest-boot-emitter.test.sh` (`RENDER_EXPR`, a hand-kept var map), `cloud-init-user-data-size.test.ts` (`SECRET_LENGTHS`, length only), and `.github/scripts/validate-infra-templates.sh` (derives its stub map from the call site, no edit).
- Plan-time gate lockstep: `tests/scripts/lib/inngest-host-replace-gate.sh` (`def allow`), `tests/scripts/lib/inngest-host-shape-gate.sh` (`def allow` + `doppler_touched` class + header), `.github/workflows/apply-web-platform-infra.yml` (`inngest_host` job `-target` list), `plugins/soleur/test/terraform-target-parity.test.ts` (the `OPERATOR_APPLIED_EXCLUSIONS` and `OPERATOR_APPLIED_TOKEN_EXCLUSIONS` sets that name `doppler_service_token.inngest`, and the shape-gate-equals-`-target` parity assertion with its `toBe(15)` floor).
- `.github/workflows/mint-inngest-bootstrap-tag.yml` triggers on pushes touching `apps/web-platform/infra/inngest*`, but the decision (`mint-inngest-bootstrap-tag.sh`) is content-based on the image's `cp`-staged carriers; none of this PR's files is a carrier. An acceptance criterion below proves `result=noop`.

### Institutional learnings applied

- `learnings/test-failures/2026-10-11-a-unit-file-content-pin-must-model-systemds-parser-not-the-files-bytes.md`: the drop-in test models systemd's parser (section scope, set identity not counts, bare reset lines, whitespace and `-` tolerance, path-prefix blindness, never pipe into `grep -q` under pipefail).
- `learnings/bug-fixes/2026-10-11-conditioning-a-unit-also-conditions-every-detector-wired-to-its-failures.md`: a Condition on the drop-in would silence the flip unit's own failure alarms for a missing file and demand a detector that does not share the gate; CTO N1 therefore drops the Condition (and the phone-home it would have needed) and lets the unprefixed `EnvironmentFile=` fail loud.
- `learnings/test-failures/2026-10-06-which-files-feed-user-data-with-no-ignore-changes-decides-whether-a-mechanical-edit-is-a-host-replace.md` and `learnings/2026-07-26-cloud-init-comment-is-a-live-host-input-...md`: any edit of `cloud-init-inngest.yml`, a comment included, re-renders `user_data` and is a host replace at the next dispatch; the replace window is owner-gated.
- `learnings/2026-07-03-cloud-init-32kb-cap-bake-and-extract-not-compress.md` and `...-base64gzip-hetzner-user-data-and-discrimination-test-must-exercise-sut.md`: measure the real render; a size test must gzip real bytes, not repeated characters.
- `learnings/security-issues/2026-06-18-inngest-secrets-env-not-argv-and-detection-sentinel-swap.md`: secrets stay in the environment, never in argv.
- `learnings/2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of.md`: the mutation matrices below are derived from the property, and include reorder rows.
- Discrepancy in the learnings sweep: the #8562 learning is the retrying-unit latch, not the charset guard; no learning covers the token-write guard, so the guard's tests are specified from the code.

## Research Reconciliation - Spec vs. Codebase

| Spec claim (ADR addendum / brief) | Reality | Plan response |
|---|---|---|
| "stale 'tracked in #6890' comments (`inngest-host.tf:244-258`, `inngest-arm-write-token.tf:145-146`)" | `#6890` text exists only in `inngest-host.tf` (the `isolated secrets ... is tracked in #6890` sentence). `inngest-arm-write-token.tf` has no `#6890`; its lines 143-151 say a second `access = "read"` token published as `DOPPLER_TOKEN_INNGEST_FLIP_READ` is "Tracked as a follow-up" with no issue number, a different token (a CI-side read token for consumer 3) whose name now collides in the eye with the new on-host `inngest_flip` | Rewrite both comment blocks to point at the ADR-282 addendum; in the arm-write file disambiguate `FLIP_READ` (CI-published read token, still untracked, state that plainly) from the on-host `inngest_flip` (never published) |
| "add the new token to the `allow[]` ... and the shape-gate table (not a `-target`)" | The shape gate's allow set must equal the `inngest_host` job's `-target` list (`terraform-target-parity.test.ts`, floor 15); an address in `def allow` with no `-target` reds that test | CTO R1: add the `-target` to the `inngest_host` job and bump the floor to 16; "not a `-target`" holds only for the `inngest_host_replace` job |
| "the review recorded 31,996 stored ... and #11664 bumped the bootstrap pin since" | Re-measured today: 31,996 stored, 772 B headroom, identical | Carry the measured table above; the budget is gated on the new total |
| `inngest-host.tf` MEASURED comment: "stored 10,892 B, headroom 21,876 B" | Stale by about 21 KB (the template grew with later work) | Comment-only refresh to the measured figure; .tf comments never reach `user_data` |
| ADR: the downgrade needs "a cloud-init drop-in" | No drop-in precedent exists on the dedicated host; `write_files` is the right birth path | `write_files` entry in `cloud-init-inngest.yml` |
| Brief: "the same write-time charset guard" | `cloud-init-inngest-provision-unit.test.sh` G4 asserts exactly two charset guards (`guards == 2`, naming `zot-read-write-REFUSED` and `inngest-doppler-write-REFUSED`) | Keep the count at two by widening the existing guard; update G4's message and add a census of `${doppler_` substitution sites |

## Implementation Phases

Order follows `cq-write-failing-tests-before`: the tests land RED first, then the code makes them green. Every file path is relative to the repo root; every cloud-init anchor is a content anchor, not a line number.

### Phase 1 - Tests first (RED)

1. **Create `apps/web-platform/infra/inngest-flip-token.test.sh`** (auto-registered: infra `*.test.sh` presence is registration). It reuses the render helper pattern of `cloud-init-inngest-provision-unit.test.sh` (python3 + yaml over the rendered template); do not re-implement the render. Sections:
   - **R. Effective-environment resolver** (Guard 1). Input population: the baked unit `inngest-cutover-flip.service`; the other baked/bootstrapped units (`inngest-redis.service`; the heredoc units inside `inngest-bootstrap.sh`: inngest-server, heartbeat, probe, trace-retention, vector and the verify unit); every `write_files` unit and drop-in in the render (`inngest-luks-open`, `soleur-inngest-provision`, `inngest-config-refresh`, the new drop-in, ...). Model systemd: per-section directive extraction, the ordered `EnvironmentFile=` list per unit with drop-ins merged across the `<unit>.service.d`, `<prefix>-.service.d` and `service.d` directories and ordered by FILENAME across directories (not per directory), after the unit body; the web host's `10-inngest-*-doppler-token.conf` files in `apps/web-platform/infra/` are explicitly EXCLUDED from the population (they share unit names but belong to another host); a bare `EnvironmentFile=` resets the list, a leading `-` marks optional, leading whitespace is honoured, `DOPPLER_TOKEN` is resolved last-wins across the files that define it. Assert: (a) the flip unit's final list ends with `/etc/default/inngest-flip` and its effective `DOPPLER_TOKEN` source is that file; (b) no other unit's list contains the flip file; (c) every other unit that reads a token resolves it from `inngest-server` or `inngest-doppler` (the read-only token); (d) the flip file defines exactly one variable, `DOPPLER_TOKEN` (extracted from the printf format string), so the project/config/config-dir variables still come from the baked file; (e) the drop-in carries an unprefixed `EnvironmentFile=/etc/default/inngest-flip` under `[Service]` and NO `ConditionPathExists` naming the flip file (CTO N1: a missing file must fail loud, and no fallback to the read-only token exists); (f) a census floor: the resolver parsed at least the known unit names (no "0 units, exit 0").
   - **X. Cross-check against systemd itself** (final shape, CTO N11; measured facts first). `systemctl --root=<dir> cat` is refused by systemd ("Verb 'cat' cannot be used with --root=", measured 2026-11-01, systemd 262) and must NOT be used. Two legs, both on the real artifacts: (X1) `systemd-analyze verify --root=<fixture>` on the real `inngest-cutover-flip.service` plus the rendered drop-in, with stub executables in the fixture so the missing-binary warnings do not trip it; it must flag a misplaced directive (an `EnvironmentFile=` under `[Unit]` is an "Unknown key" warning). `systemd-analyze --root=<dir> cat-config systemd/system/<unit>` may be printed for discovery (it showed the unit body's `EnvironmentFile=/etc/default/inngest-server` followed by the drop-in's `EnvironmentFile=/etc/default/inngest-flip`), but it is a text merge and proves only discovery and order. (X2) Ordering and last-wins in real systemd via the existing Tier B systemd-container harness of `cloud-init-inngest-provision-unit.test.sh` (it needs docker able to boot systemd 255 and FAILs rather than skips under `CI`; it installs a stand-in under the same unit name): after its T-rows, replace the stand-in with the real unit and the real drop-in, `daemon-reload`, and assert `systemctl show -p EnvironmentFiles inngest-cutover-flip.service` lists the server file first and the flip file second, with no `-` prefix (`show` starts nothing). Measured calibration (not a repo test): `systemd-run --user -p EnvironmentFile=<a> -p EnvironmentFile=<b> /usr/bin/env` printed `DOPPLER_TOKEN` from the later file and kept the other file's variables, confirming the override semantics. Skip policy: under `CI` or `GITHUB_ACTIONS` a skipped X leg is a FAIL, enforced by an executed-leg floor in the pinned counts (`X_EXECUTED >= 1`, printed in the summary); locally a skip is loud and counted. Terraform absent is a `die`, never a skip.
   - **W. Write guard behaviour** (Guard 2). Execute the rendered guard runcmd item under `sh` (the host runs runcmd under `/bin/sh`, dash) with synthetic token values. The item hard-codes `/usr/local/bin/inngest-boot-phone-home.sh`: rewrite that absolute path to a recording stub and assert the rewrite matched at least once (the provision-unit test's path-rewrite table is the precedent). A clean pair exits 0; a flip token carrying `;`, a boot token carrying a space, an empty flip token, and a clean first heredoc line followed by an unsafe SECOND line each exit 1 and record `inngest-doppler-write-REFUSED`. The guard is PER-LINE by design (CTO N10): a value with an embedded newline whose lines are individually clean passes it; that is reachable only through a hostile Doppler API response, the charset excludes `=`, space, quotes, `$` and `;` so a clean extra line is a bare word and never an assignment, the flip file is consumed by systemd and read with `sed` and never sourced, and the existing boot-token guard already behaves the same way. A test row DOCUMENTS this limit (the embedded-newline value exits 0 and the row says why) rather than asserting a refusal; the ADR build record notes it. Census, anchored on `\$\{doppler_(flip_)?token\}` (not `\${doppler_`, which also matches `${doppler_arch}` and `${doppler_sha256}`): every substitution site of the two tokens is either inside the guard heredoc or in one of exactly three `printf` writes (`inngest-doppler`, `inngest-server`, `inngest-flip`), and the guard item precedes all three. A comment that contains `${doppler_flip_token}` is interpolated by `templatefile` before the strip and would be miscounted, so new comments must not contain `${` or `%{` (write `$${` if a literal is needed).
   - **O. Order and mode.** Execute the flip-write runcmd item in a temp directory (path rewritten as in section W) and `stat` the result for mode 600, instead of text-pinning the umask; assert by TEXT census (a non-root test runner cannot observe ownership) that no `chown` names it, so the file stays root:root and that its runcmd index is before the item that arms `soleur-inngest-provision` (which is also the item that runs the bootstrap; CTO R5 amendment 1; reuse the G5 `pos()` approach).
   - **S. Path-occurrence census** (property 3 also quantifies over shell readers, which the unit resolver cannot see). Over the render and every infra script, `/etc/default/inngest-flip` appears only in: the drop-in (one `EnvironmentFile=` line), the flip `printf`, and the redactor `sed`. Any other reader or sourcer reds.
   - Harness rules (test-design review): terraform absent is a `die`, never a skip (the sibling render suite's Tier A rule); render ONCE and mutate copies of the stripped render, never re-render per row; pin `EXPECTED_ROWS`, `EXPECTED_RED` and `EXPECTED_MUSTPASS` in the style of `cloud-init-inngest-provision-unit.test.sh`, run a pristine control first, and verify per row that the mutation landed; reuse the section/heredoc helpers already in `inngest.test.sh` (`_luks_sec`, `_sec_body`, `_boot_unit`, `heredoc-hazard-units.awk`) instead of writing a third parser; Guard 2 rows 1, 3 and 8 perturb the same axis (guard content) and are counted as one. Mutation battery for sections R/W/O/S: see Guard Contract. (Section P, a `flip-file-written` phone-home test, was cut with the phone-home, CTO N1.)
2. **Rewrite `apps/web-platform/infra/inngest-host.test.sh` finding 1b** (the `1b. (#6178)` block, `TOKEN_ACCESS`/`FLAG_SET_BODY`). New assertions, each from block-scoped awk that skips comment lines and requires statement position (keep the decoy-comment hardening the old block documents): the `resource "doppler_service_token" "inngest"` block has `access = "read"`; a new `resource "doppler_service_token" "inngest_flip"` block exists with `access = "read/write"` and `name = "inngest-flip"`; the awk for the first block must not match the second (the old anchor `resource "doppler_service_token" "inngest"` is a prefix of `"inngest_flip"` when unanchored; anchor on the closing quote and brace). Keep the `flag_set` body cross-check (writes `INNGEST_CUTOVER_FLIP`, no `--token` in the body) but change its failure message and premise: the write runs under the flip unit's drop-in token, so the ambient-token premise is now "the ambient token is whichever the unit's `EnvironmentFile` order yields", which section R proves. Add the cross-reference to `inngest-flip-token.test.sh`.
3. **Gate tests** (RED until Phase 4):
   - `tests/scripts/test-inngest-host-replace-gate.sh`: PASS row: server replace plus `doppler_service_token.inngest_flip` `["create"]` (with the boot token `["delete","create"]`); PASS row: flip `["delete","create"]`; ABORT row: lookalike `doppler_service_token.inngest_flip_x` (exact-equality, mirrors T1c); keep T1c (`inngest_arm_write` aborts).
   - `tests/scripts/test-inngest-host-shape-gate.sh`: PASS `doppler_service_token.inngest_flip=["create"]`; PASS `["update"]` (mirror the existing `.inngest` update row); RED `doppler_touched` for `["delete","create"]` and `["delete"]` (mirror the existing RED row); RED `out_of_scope` for the lookalike; the `build` helper (which derives its no-op set from the workflow's `-target` list) must now include the new address, so the "every address no-op" PASS row proves the lockstep.
   - `plugins/soleur/test/terraform-target-parity.test.ts`: the `toBe(15)` floor becomes 16; add `doppler_service_token.inngest_flip` to both exclusion sets that already name `doppler_service_token.inngest` (`OPERATOR_APPLIED_EXCLUSIONS` and `OPERATOR_APPLIED_TOKEN_EXCLUSIONS`) with the comment from CTO R1 (key feeds `user_data` only; never publish it to a `github_actions_secret`, or the #5566 rule forces a per-merge target).
4. **Provision-unit G4** in `cloud-init-inngest-provision-unit.test.sh`: keep `len(guards) == 2`; reword the check message to "all Doppler credentials and the zot pull values are charset-guarded" (the old wording "both credential files" is now false). No separate heredoc-body row: section W below proves the same thing by behaviour (an unsafe flip token on the second heredoc line exits 1).
5. **Boot-emitter suite** `apps/web-platform/infra/inngest-boot-emitter.test.sh`, two edits. (a) Its render uses a hand-kept `templatefile` var map (`RENDER_EXPR`, with `doppler_token="d"` and a key-set parity diff against `inngest-host.tf`): add `doppler_flip_token` there first, or every render assertion in the suite reds for the wrong reason once the template gains the variable. (b) A redactor fixture row (the suite already executes `inngest-redact.sh` under `env -i` with the `SOLEUR_INNGEST_SENTRY_DSN_FILE` seam): a synthetic high-entropy flip token written to a fixture file is replaced with `REDACTED` while the boot token still is. The script hard-codes TWO paths, `/etc/default/inngest-flip` and `/etc/default/inngest-doppler` (sourced); rewrite BOTH in the extracted copy, assert each literal occurs exactly once (so a refactor cannot turn the rewrite into a no-op), and put stub `doppler` and `jq` executables first on the fixture `PATH` (a non-empty boot token otherwise triggers the redactor's Doppler download and a real network call).
6. **Budget stub assertions** (`plugins/soleur/test/cloud-init-user-data-size.test.ts`): the TS arm is a LENGTH model (`"x".repeat(n)` fillers gzip to almost nothing), so it cannot resolve entropy; give `doppler_token` and `doppler_flip_token` ONE consistent length in `SECRET_LENGTHS` equal to the `.sh` stub's total (`dp.st.prd.` + 48 = 58; today's `doppler_token: 48` is retuned to match), and say in its comment that the byte gate is `inngest-userdata-budget.sh`. The existing "inngest host base64gzip'd user_data is under the Hetzner cap" arm must stay green at `INNGEST_GZIP_BUDGET = 32_300` (do not raise it); if the 53-char retune moves the model past the budget, report the model figure and stop for a ruling rather than raising the constant.

7. **Tripwire** (test-only, in `inngest-flip-token.test.sh`): fail on any non-comment `DOPPLER_TOKEN` expansion, `printenv`, `env`, `declare -p` or `export -p` in `inngest-cutover-flip.sh`. `doppler run` hands the flip token to every child of that script (redis-cli, curl, jq, nft, logger, systemctl), so a future edit that echoes the environment would put a read/write token into logs; today the script has zero such expansions (security review, measured by grep).

Run Phase 1 and confirm each new or changed assertion is RED for the right reason before Phase 2.

### Phase 2 - Terraform (`apps/web-platform/infra/inngest-host.tf`, `inngest-provision-rehearsal/rehearsal.tf`, `inngest-arm-write-token.tf`)

1. `resource "doppler_service_token" "inngest"`: `access = "read"`. Rewrite its comment block (the `access = "read/write" (was "read" - #6178)` paragraph through the `#6890` sentence): state the new split, that `access` is ForceNew (so this is a host replace through the gated dispatch), that the key still feeds `user_data`, and cite the ADR-282 addendum "2026-10-30 (#9927 item 4, the flip-token design)" by TITLE only. The rewritten comment must not contain the string `#6890` (the closed-not-planned history belongs in the ADR build record, and the acceptance grep requires zero hits). Keep the corrected #7228 paragraph about the latch (it is unrelated and accurate).
2. New `resource "doppler_service_token" "inngest_flip"` beside it: same `project`/`config`, `name = "inngest-flip"`, `access = "read/write"`. Comment: read only by `inngest-cutover-flip.service` via the cloud-init drop-in; same exposure class as `inngest_arm_write` (read/write on the same config); placed in `user_data`, so retrievable through the metadata API by anyone with host access (the ADR residual; follow-ups #11816, #11817); never published to a `github_actions_secret`; created as a dependency of `hcloud_server.inngest`'s `user_data`, not `-target`ed on the replace dispatch. No `lifecycle` block.
3. `templatefile(...)` map: add `doppler_flip_token = doppler_service_token.inngest_flip.key` next to `doppler_token`, with a one-paragraph comment. Update the `doppler_token` comment ("read/write on the ISOLATED `soleur-inngest` project ... the flip FSM writes `INNGEST_CUTOVER_FLIP` under it") to say read-only.
4. Refresh the stale `MEASURED` comment (`stored 10,892 B ...`) to the measured figures from this PR (comment-only).
5. `inngest-provision-rehearsal/rehearsal.tf`: add `doppler_flip_token = doppler_service_token.rehearsal.key` to its `templatefile` map with a comment: the rehearsal host never arms the cutover flip, so it carries its read-only token in both files; a rehearsal that must exercise a flip write is out of scope. The plan-shape test (`tests/scripts/test-inngest-provision-plan-shape.sh`) is unchanged because no new rehearsal resource is created.
6. `inngest-arm-write-token.tf`: rewrite the paragraph that ends "Tracked as a follow-up because minting and publishing a new service token ..." so it (a) says the CI-side read token it proposes (`DOPPLER_TOKEN_INNGEST_FLIP_READ`) is still untracked, with the ADR-282 addendum as the nearest record, and (b) states that it is unrelated to the on-host `doppler_service_token.inngest_flip`. No behaviour change.

### Phase 3 - Cloud-init (`apps/web-platform/infra/cloud-init-inngest.yml`)

Byte-budget rule: only the items below may add non-comment bytes; measure after each (Phase 5 command).

1. **Drop-in** as the first `write_files` entry: the file `inngest-cutover-flip.service.d/10-flip-token.conf` in the system unit directory, `owner: root:root`, `permissions: '0644'`, body `[Service]` / `EnvironmentFile=/etc/default/inngest-flip` (no `-` prefix and NO `ConditionPathExists`: a missing or wrong file must fail loud, and there is deliberately no fallback to the read-only token; CTO N1). The baked unit's own `ConditionPathExists=/etc/default/inngest-server` still skips the unit when the base file is absent, which needs no new guard. Because the drop-in is appended after the baked `EnvironmentFile=/etc/default/inngest-server`, only `DOPPLER_TOKEN` is overridden.
2. **Widen the first charset guard** (the `SOLEUR_WRITE_GUARD_EOV` item over `${doppler_token}`) into the `while IFS= read -r _wv; do case ... done <<'SOLEUR_WRITE_GUARD_EOV'` form used by the zot guard, with `${doppler_token}` and `${doppler_flip_token}` on consecutive heredoc lines; the refusal message reads "a Doppler token carries a character outside [A-Za-z0-9._:/-]" and keeps the `inngest-doppler-write-REFUSED` phone-home tag and `exit 1`. The empty-value arm (`''|`) stays, so an empty flip token also refuses.
3. **Flip file write**, directly after the `chown root:deploy /etc/default/inngest-server` item, as its own runcmd item: `( umask 0177 && printf 'DOPPLER_TOKEN=%s\n' '${doppler_flip_token}' > /etc/default/inngest-flip ) || exit 1`. Fail closed (CTO N2): the runcmd script has no errexit, so the bare `exit 1` is what stops the host arming on a failed write (same mechanism as the charset guards). No phone-home (CTO N1/N2): the existing detector is the missing `provision-unit-armed` row for the instance id. Must precede the item that arms `soleur-inngest-provision`; the existing G5 prerequisite census stays green.
4. **Redactor** (`inngest-redact.sh` value list): after the Sentry DSN lines add `vals+=("$(sed -n 's/^DOPPLER_TOKEN=//p' /etc/default/inngest-flip 2>/dev/null)")` (the file is one line, so no `head`; measured 8 B smaller than the `fl=` form). Read with `sed`, never sourced (sourcing would overwrite `DOPPLER_TOKEN`, which the later Doppler download in the same function uses). An absent file yields an empty value and the loop already skips values under 6 bytes (CTO R4).
5. **Comment refresh** (free): the comment above the `/etc/default/inngest-doppler` write ("The token is read/write on the ISOLATED ..."), the one above the `/etc/default/inngest-server` write, and the comment above the bootstrap invocation ("scoped boot token reaches only soleur-inngest (read/write, #6178)") describe a read/write boot token; correct them to read-only and add one pointer to the ADR addendum and the drop-in. `git grep -n 'read/write' apps/web-platform/infra/cloud-init-inngest.yml` is the census to sweep.
6. **Phone-home dp-mask** (CTO N12): in `inngest-boot-phone-home.sh`'s detail scrub (the `s#dp\.[a-z0-9]+\.[A-Za-z0-9_-]{10,}#REDACTED#g` expression, the only copy in the repo) add `.` to the body character class: `[A-Za-z0-9_.-]{10,}`. The current expression leaves a `dp.st.<config>.<body>` token unmasked because the dot after the config segment ends the run; phone-home POSTs bypass Vector's scrub. About 1 B stored. Test: a synthetic-token row (`dp.st.prd.` plus a made-up body) in the existing phone-home test (`cloud-init-inngest-bootstrap.test.sh` or the suite that already exercises `inngest-boot-phone-home.sh`; find it with `git grep -ln 'inngest-boot-phone-home' apps/web-platform/infra/*.test.sh`).
7. Do NOT touch `STAGED=`, `inngest-bootstrap.sh`, `inngest-cutover-flip.sh`, `inngest-cutover-flip.service`, `inngest-server-flip-guard.sh` or any other image carrier.

### Phase 4 - Plan-time gates and workflow

1. `tests/scripts/lib/inngest-host-replace-gate.sh`: add `"doppler_service_token.inngest_flip"` to `def allow` (exact equality, no per-address action rule, like `.inngest`); extend the header's allow-set list with a sentence on why it is admitted (upstream of the server's `user_data`; the plan must STILL replace the server and preserve the volume, so admitting it cannot let a destructive plan through).
2. `tests/scripts/lib/inngest-host-shape-gate.sh`: add the address to `def allow` and to the existing `doppler_touched` class (no-op | create | update); update the header comment's class list. No new class (`allow_unpartitioned` forces one class per allow address).
3. `.github/workflows/apply-web-platform-infra.yml`: in the `inngest_host` job's plan step the existing last line is `-target='doppler_service_token.inngest' 2>&1 | tf_redact_random_ids` (no trailing backslash; the parity test's `commandIn()` treats a missing backslash as the end of the command). Insert the new `-target='doppler_service_token.inngest_flip' \` line BEFORE it, keeping every other line's continuation and keeping the `2>&1 | tf_redact_random_ids` suffix on the final `-target` line only. Add a one-line workflow comment that the line is graph-redundant (`-target=hcloud_server.inngest` already pulls both tokens in through the dependency closure) and exists so the shape-gate allow set and the parity test stay equal, so nobody removes it as redundant. The `inngest_host_replace` job's three `-target`s do not change (CTO R1).
4. **Pre-destroy size gate in the replace job** (CTO N9). In the `inngest_host_replace` job add a step running `bash apps/web-platform/infra/inngest-userdata-budget.sh` after `hashicorp/setup-terraform` and BEFORE the step named `Terraform plan (scoped inngest-host -replace) + destroy-guard`. The script is offline (needs only terraform), fails closed in CI and, with the Phase 5 floor, exits 1 below 512 B of cap headroom, so a failing step aborts before any plan or destroy. Reason (Terraform reviewer, probed with the cached DopplerHQ 1.21.2 provider; not re-run by us): when a token `.key` is unknown at plan time, `local.inngest_user_data_b64gz` is unknown and the `hcloud_server.inngest` `lifecycle.precondition` on `user_data` length is deferred to APPLY; on the first replace after merge the boot token is `-/+` and the flip token `+`, so both keys are unknown and the destroy runs before the cap is ever checked (the 2026-09-08 stranded-host shape). Add a row to `terraform-target-parity.test.ts` (it already parses job structure) asserting the step exists in that job and precedes the plan step. Correct the comment in `inngest-host.tf` that says the precondition "evaluates inside terraform plan ... BEFORE the destroy": it holds only when every input is known at plan time (comment-only; never reaches `user_data`).
5. Verify with the suites named in Phase 7.

### Phase 5 - Budget stubs and the measured record

1. `apps/web-platform/infra/inngest-userdata-budget.sh` (CTO N3, which reverses R2's "do not retune the boot stub"): make BOTH stubs high-entropy, `join(".", ["dp", "st", "prd", substr(replace(replace(base64sha512("<label>"), "+", "a"), "/", "b"), 0, 48)])` with labels `boot` and `flip` (the prototype's form: deterministic, random-shaped, 58 chars total, no contiguous token-shaped literal in source). Add `doppler_flip_token` to the `vars` map. Replace the stub-bound paragraph in the header so it says what the stubs bound: length AND entropy. Add a hard floor to the script's verdict: exit 1 when `stored_bytes > cap - 512` (the script already exits 1 over the cap; this adds the 512 B headroom floor, the only place that runs the real `templatefile`/`base64gzip`, run by the `infra-validation.yml` job `inngest-userdata-budget`). No dedicated suite exists for this script today (it is referenced by `cloud-init-user-data-size.test.ts` and the CI job only), so give the floor an env seam (for example `INNGEST_BUDGET_FLOOR_BYTES`, default 512) and add one row to `cloud-init-user-data-size.test.ts` that runs the script with the floor raised above the real headroom and expects exit 1 (skipped loudly where `terraform` is absent), plus a must-PASS row at the default floor; that proves the new exit is not vacuous. Assert `rc == 1` EXACTLY plus the floor message text (exit 2, unmeasurable, is also nonzero and would let the row pass for the wrong reason), give the `bun test` row an explicit timeout above the 5 s default (a terraform console run is slow), bound the must-PASS headroom instead of pinning it (it drifts), and add a row asserting the TS `SECRET_LENGTHS` value for both tokens equals the `.sh` stub's total length, so the comment cannot drift.
2. Run `bash apps/web-platform/infra/inngest-userdata-budget.sh` and record the stored figure, the cap headroom and the margin under 32,300 in the PR body and the ADR build record. Prototype expectation: about 32,196 B stored, 572 B headroom, 104 B under 32,300. The floor is 32,256 B. If it is breached, shrink code, never raise the budget and never add #11265 bytes.
3. Run `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` (from the repo root; do not `cd` into `plugins/soleur`, per the `bunfig.toml` resolution note) and confirm the inngest arms are green at the unchanged 32,300 budget.

### Phase 6 - Records (ADR, C4, runbook, follow-ups, PR)

1. **ADR-282 build-record addendum** (see the Architecture Decision section): append-only, no new ordinal.
2. **C4**: edit the `doppler -> inngest` edge description in `knowledge-base/engineering/architecture/diagrams/model.c4`.
3. **Runbook** `knowledge-base/engineering/operations/runbooks/inngest-server.md`, in the host-replace section near the A1 row, one subsection (keep it short; the ADR build record and the PR body point here rather than restating it) carrying: (a) the expected replace plan shape (`-/+ doppler_service_token.inngest`, `+ doppler_service_token.inngest_flip`, `-/+ hcloud_server.inngest`, `-/+` the network and attachment dependents, volume untouched) and the recovery plan shape after a mid-replace failure (both tokens `no-op`, server `create`); (b) replace-window impact: the sole scheduler is down for the window, scheduled agent runs and reminders due in it do not fire on time, a low-traffic window is recommended, and what happens to the jobs that come due is the existing AOF-preserved behaviour (state the measured behaviour from the earlier replaces if the runbook already records it, else say it is not measured here); (c) an abort and rollback rule: if the replaced host has not armed (no `provision-unit-armed` row for the new instance id) within the runbook's existing post-replace window, stop and use the existing re-dispatch recovery, and note that the old host's state is the thing at risk; (d) the three owner-only, production-mutating routes of CTO N4: rotating the flip token (an owner-run `terraform apply -replace=doppler_service_token.inngest_flip -target=doppler_service_token.inngest_flip`, then the gated host replace straight away), recovering from a revoked flip token (the same route; re-dispatching the replace alone re-embeds the dead key) and recovering from a guard refusal (same; the signals are the `inngest-doppler-write-REFUSED` row and no `provision-unit-armed` row), plus the unverified-on-a-live-host note that a revoked flip token fails `doppler run` before the script starts, so there is no FSM marker and a mid-FSM rollback is dead; (e) the pre-go rehearsal option of CTO N5 (what it proves and does not); (f) that until the replace every `apply_target=inngest-host` dispatch aborts by design (and the scheduled drift workflow's unscoped `terraform plan -detailed-exitcode` shows a pending server replace and token changes until then; confirm in the work phase how that workflow treats the existing `user_data` diff, and say so in the PR body); (g) a go-condition: the `inngest-userdata-budget` job is green on the exact dispatch SHA (and the same script now runs inside the replace job before the plan); (h) rotating the flip token alone leaves the RUNNING host's flip file holding a dead key until the host is replaced, so the flip FSM is dead in between: do the host replace straight away; (i) the recovery plan reading `provision-unit-armed` absent AND no `inngest-doppler-write-REFUSED` row means the flip write failed (the charset guards emit REFUSED, the flip write emits nothing); (j) a leak response: revoke-before-replace briefly leaves the old host with a dead boot token, so order it per the same route.
4. **Follow-ups** (already filed during planning, each in its own `gh issue create --body-file` call): #11816 (deploy docker-group and sudo root-equivalence review) and #11817 (metadata egress block for non-root, blocked by #11816). Cite them in the PR body and in the ADR build record.
5. **PR body** (condition 6). The FIRST line is the CTO N6 sentence: "Merging this PR changes nothing in production: it ships code only, the Inngest host is not replaced and no token is minted, and until the owner runs the gated `inngest-host-replace` every `inngest-host` dispatch aborts by design, so do not dispatch it." Then: link the addendum by title and file; `Ref #9927` (the Operator Hold that authorizing the replace, runbook row A1, is the tracker for the post-merge step); the stored figure, the cap headroom and the margin under 32,300; the stub-entropy correction (both stubs are now high-entropy, so the gated figure rose by about 44 B per token); a pointer to the runbook subsection for the plan shape instead of restating it; the `mint-inngest-bootstrap-tag.sh --dry-run` result; the unchanged residuals; the "Not measured" list from the addendum with what this PR did and did not measure; the pre-go rehearsal option (N5); the drift-workflow note; follow-ups #11816, #11817 and #11820.

### Phase 7 - Verification (all local, no network, no write)

Run and attach results (exact commands are the acceptance list). Finish with the full infra tier (`bash apps/web-platform/infra/run-registered-suites.sh`) and `bash scripts/lint-orphan-test-suites.sh`. Order: the new suite; `inngest-host.test.sh`; provision-unit; boot-emitter; the two gate suites; `bun test plugins/soleur/test/terraform-target-parity.test.ts plugins/soleur/test/cloud-init-user-data-size.test.ts`; `inngest-userdata-budget.sh`; `bash plugins/soleur/test/c4-count-parity.test.sh` plus the C4 syntax and render tests; `bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run`; `bash .github/scripts/validate-infra-templates.sh` if runnable locally; `terraform fmt -check` and `terraform validate` over the root if the providers are cached (otherwise report as not run, never as passed).

## Files to Edit

- `apps/web-platform/infra/inngest-host.tf`
- `apps/web-platform/infra/cloud-init-inngest.yml`
- `apps/web-platform/infra/inngest-arm-write-token.tf`
- `apps/web-platform/infra/inngest-provision-rehearsal/rehearsal.tf`
- `apps/web-platform/infra/inngest-userdata-budget.sh`
- `apps/web-platform/infra/inngest-host.test.sh`
- `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`
- `apps/web-platform/infra/inngest-boot-emitter.test.sh`
- `tests/scripts/lib/inngest-host-replace-gate.sh`
- `tests/scripts/lib/inngest-host-shape-gate.sh`
- `tests/scripts/test-inngest-host-replace-gate.sh`
- `tests/scripts/test-inngest-host-shape-gate.sh`
- `.github/workflows/apply-web-platform-infra.yml` (the `inngest_host` `-target` line and the new budget step in `inngest_host_replace`)
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `plugins/soleur/test/cloud-init-user-data-size.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`
- the existing phone-home test suite (find with `git grep -ln 'inngest-boot-phone-home' apps/web-platform/infra/*.test.sh`; one synthetic-token row for the dp-mask fix)
- `apps/web-platform/infra/inngest.test.sh` (one comment row recording the deliberate exception that the new drop-in has an unprefixed `EnvironmentFile=` with no `ConditionPathExists`, CTO N1, against the #9962 pairing calibration; confirm the `DROPIN_ACK_UNITS` ack-list assertions are unaffected)
- `apps/web-platform/infra/inngest-provision-rehearsal.test.sh` (one assertion that `doppler_flip_token` in `rehearsal.tf` references the rehearsal read token, so the rehearsal can never be handed a read/write one)
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (bump `BASELINE_DECLARED_PROBES` 90 to 91 with the PLACEMENT/TRUTH/NO-SUBSTITUTE comment its ratchet requires, because the Observability block declares `credentials_required`; the probe returns a row only after the owner-gated replace, which the comment says)

Every path above exists on the branch; no path glob is prescribed.

## Files to Create

- `apps/web-platform/infra/inngest-flip-token.test.sh` (auto-registered by presence under the infra test runner glob)
- `knowledge-base/project/specs/feat-one-shot-inngest-flip-token-split/tasks.md` (derived at plan finalization)
- `knowledge-base/project/specs/feat-one-shot-inngest-flip-token-split/decision-challenges.md` (written; CTO rulings R1-R6)

## Files NOT to Edit (and why)

- `apps/web-platform/infra/inngest-cutover-flip.service`, `inngest-cutover-flip.sh`, `inngest-server-flip-guard.sh`, `inngest-bootstrap.sh`, `inngest-redis-bootstrap.sh`, `cat-inngest-cutover-state.sh`, `vector.*`: image-baked carriers (the cutover-flip script, guard, state script and redis bootstrap are also config-bundle members). An edit changes the image source tree, so `mint-inngest-bootstrap-tag.yml` would mint a tag and dispatch a build on merge, and would drift the bundle - both outside the hard limits. Two pieces of stale prose are recorded in the ADR build record as stale-until-next-image instead: the comment in `inngest-cutover-flip.sh` ("The scoped soleur-inngest boot token ... authorizes the write") and the baked unit's "THIS UNIT'S ENVIRONMENT HAS EXACTLY TWO SOURCES ... fixed four-name printf" paragraph, which a second `EnvironmentFile` now makes incomplete (its threat model still holds: the flip file is Terraform-supplied, never Doppler content).
- `STAGED=` in `cloud-init-inngest.yml`: #11265 is a separate PR (R3).

## Open Code-Review Overlap

Queried open `code-review` issues against every path in Files to Edit/Create (two-stage `gh --json` then `jq --arg`). One hit: #10243 (`review: nft comment correction on PR 8945`, `cloud-init-inngest.yml`). **Acknowledge**: a comment-only correction about nftables atomicity, a different concern from this PR; leave it open for its own cycle (folding it in would widen review for no byte or behaviour effect). No other file has an overlap.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "`doppler_service_token.inngest` becomes access=\"read\", with BOTH copies of the boot token downgraded" | Phase 2 step 1; Phase 3 (both files keep the one token variable) | mapped |
| 2 | "a new read/write root-only 0600 inngest-flip token read only by the cutover-flip unit via a cloud-init drop-in EnvironmentFile override" | Phase 2 steps 2-3; Phase 3 steps 1 and 3 | mapped |
| 3 | "with a test that the flip unit resolves the flip token and every other unit the read-only one" | Phase 1 step 1 sections R and X | mapped |
| 4 | "and the same write-time charset guard" | Phase 3 step 2; Phase 1 step 1 section W; Phase 1 step 4 | mapped |
| 5 | "rewrite inngest-host.test.sh finding 1b (#6178)" | Phase 1 step 2 | mapped |
| 6 | "add the new token to the allow[] in tests/scripts/lib/inngest-host-replace-gate.sh and the inngest-host-shape-gate.sh table, with tests (not a -target)" | Phase 4 steps 1-2; Phase 1 step 3; the `inngest_host` `-target` is CTO R1's amendment | mapped |
| 7 | "user_data must fit the 32,768-byte Hetzner cap and INNGEST_GZIP_BUDGET 32,300 ... measure the real headroom first" | Value-Proposition Measurement table; Phase 5 | mapped |
| 8 | "rewrite the stale \"tracked in #6890\" comments (inngest-host.tf:244-258, inngest-arm-write-token.tf:145-146) to point at the ADR" | Phase 2 steps 1 and 6 | mapped |
| 9 | "the PR links the addendum" | Phase 6 step 5 | mapped |
| 10 | "file the two follow-ups the addendum names (deploy docker-group/sudo root-equivalence review; metadata egress block for non-root) with gh issue create as its own Bash call using --body-file" | Phase 6 step 4 (done at plan time: #11816, #11817) | mapped |
| 11 | "have the plan measure the user_data byte budget and let the CTO agent rule whether #11265 can share this PR or must be a separate one" | Measurement table; CTO R3 in `decision-challenges.md` | mapped |
| 12 | "Do NOT dispatch apply_target=inngest-host-replace, do not build or promote the config bundle or INNGEST_CONFIG_DIGEST, make no Hetzner or Doppler write, mint no token" | Overview constraint; Files NOT to Edit; no phase performs any | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Redactor by-value line (Phase 3 step 4) | - | inferred - justification: a new secret in a root-only file would otherwise reach shared log tails only through a 40-char backstop that the dotted `dp.st.<cfg>.` prefix defeats; CTO R4 ruled it required |
| Fail-closed `|| exit 1` on the flip write (Phase 3 step 3) | "a new read/write root-only 0600 inngest-flip token" | asked (a credential file that failed to be written must not leave the host armed without it); CTO N2 |
| `systemd-analyze --root cat-config` cross-check (section X) | "a test that the flip unit resolves the flip token and every other unit the read-only one" | asked (the model alone could drift from systemd) |
| Rehearsal-root var (Phase 2 step 5) | - | inferred - justification: the template gains a variable, and the rehearsal root renders the same template, so its plan fails without the key |
| Budget stub entropy (Phase 5 step 1) | "measure the real headroom first" | asked |
| Budget script step inside the `inngest_host_replace` job (Phase 4 step 4) | "user_data must fit the 32,768-byte Hetzner cap" | asked in substance - justification: the cap precondition is deferred to apply on the first replace (unknown token keys), so a CI-time measurement is the only gate before the destroy; CTO N9 |
| Phone-home dp-mask one-byte fix (Phase 3 step 6) | - | inferred - justification: the flip token is a new secret whose `dp.st.<cfg>.<body>` shape the current scrub leaves unmasked on a channel that bypasses Vector; verified by running the sed on a synthetic token; CTO N12 |
| Tripwire test on `inngest-cutover-flip.sh` (Phase 1 step 7) | - | inferred - justification: `doppler run` hands the read/write flip token to every child of that script, so a future environment dump would put it in logs; test-only, starts green; security review, CTO N12 (i) |
| `inngest.test.sh` comment row and rehearsal-test assertion (Files to Edit) | "a test that the flip unit resolves the flip token and every other unit the read-only one" | inferred - justification: the existing #9962 pairing calibration would otherwise read the Condition-less drop-in as a defect, and the rehearsal pass-through must stay a read token; both are one-line pins |
| ADR build-record addendum, C4 edge, runbook paragraph (Phase 6) | "the PR links the addendum" | inferred - justification: recorded architecture must not lag the change (`wg-architecture-decision-is-a-plan-deliverable`); the runbook paragraph carries the expected replace plan shape the owner needs at the go |
| Comment refresh of the stale "10,892 B" measurement | "measure the real headroom first" | inferred - justification: a comment that cites a figure about 21 KB wrong teaches the next reader the wrong budget; .tf comments are free |

### Split Assessment

- Subsystems touched: 4 - `apps/web-platform/infra`, `tests/scripts`, `plugins/soleur/test`, `.github/workflows` (plus knowledge-base docs)
- Planned files: 23 (22 edits, 1 test created; docs excluded from the threshold) | Estimated changed lines: about 650, most of them tests and comments
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the subsystem-root threshold is met only because the gate lockstep (shape gate, `-target` list, parity test) must land atomically or `terraform-target-parity.test.ts` and the shape-gate suite red against each other; the CTO ruled it medium (about a day), with the risk in the shell tests, not the Terraform. The one real split candidate, #11265, is already split out (R3).

## Acceptance Criteria

### Pre-merge (PR)

- [x] `doppler_service_token.inngest` has `access = "read"`; `doppler_service_token.inngest_flip` exists with `access = "read/write"` and `name = "inngest-flip"`; both asserted by the rewritten finding 1b, not by a bare grep (`inngest-host.test.sh` passes).
- [x] `cloud-init-inngest.yml` renders `/etc/default/inngest-flip` with exactly one variable (`DOPPLER_TOKEN`), written by an executed item that yields mode 600 root:root and ends `|| exit 1`, before the provision unit is armed (`inngest-flip-token.test.sh` sections O and R(d)); the drop-in has no `ConditionPathExists`.
- [x] The flip unit's effective `EnvironmentFile` list ends with the flip file and no other unit's list contains it; every other token-reading unit resolves `inngest-server` or `inngest-doppler` (sections R, X). Section X ran against real `systemd-analyze cat-config` in CI, or printed its counted loud skip locally.
- [x] Both Doppler tokens pass through ONE charset guard before any write; an unsafe flip token, an unsafe boot token and an empty flip token each exit 1 with `inngest-doppler-write-REFUSED` (section W); `cloud-init-inngest-provision-unit.test.sh` G4 passes with `guards == 2` and the new heredoc-body row.
- [x] `inngest-redact.sh` scrubs a synthetic flip token by value (`inngest-boot-emitter.test.sh` row), and the file is read with `sed`, not sourced.
- [x] `tests/scripts/test-inngest-host-replace-gate.sh` and `test-inngest-host-shape-gate.sh` pass with the new PASS, lookalike-ABORT and RED rows; `terraform-target-parity.test.ts` passes with the `-target` added to `inngest_host`, the floor at 16 and both exclusion entries present; the `inngest_host_replace` job still has exactly 3 `-target`s.
- [x] `inngest_host_replace` runs `inngest-userdata-budget.sh` before its plan step (parity-test row asserts presence and order), and the `inngest-host.tf` precondition comment is corrected.
- [x] The phone-home dp-mask masks a synthetic `dp.st.prd.<body>` token (test row), and the by-value redactor line and the tripwire test are present.
- [x] `bash apps/web-platform/infra/inngest-userdata-budget.sh` exits 0 with BOTH stubs high-entropy (48-char bodies); stored at most 32,256 B (cap headroom at least 512 B), and the script itself now exits 1 below that floor (a test row proves the exit is live); `INNGEST_GZIP_BUDGET` is still 32,300 and `cloud-init-user-data-size.test.ts` passes. The PR body records the stored figure, the headroom and the margin under 32,300.
- [x] `grep -rn '#6890' apps/web-platform/infra/inngest-host.tf apps/web-platform/infra/inngest-arm-write-token.tf` prints nothing; both blocks cite the ADR-282 addendum by title. The "Tracked as a follow-up" claim in `inngest-arm-write-token.tf` no longer implies a tracker that does not exist.
- [x] `bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run` prints `result=noop` on the branch tip (no image carrier changed). It needs a full-history clone with tags: if `git rev-parse --is-shallow-repository` prints `true`, run `git fetch --unshallow --tags origin` first (a shallow clone prints `result=error reason=shallow`, which is a failure, not a pass).
- [x] `git diff --stat origin/main...HEAD -- <each path under Files NOT to Edit>` prints nothing (three-dot diff against the merge base, so a sibling PR that touches those paths cannot redden it).
- [x] The full infra test tier is green, not only the named suites: `bash apps/web-platform/infra/run-registered-suites.sh` (other suites pin `/etc/default/inngest-server` content or the first guard's `read -r _wv` form: `inngest.test.sh`, `inngest-config-refresh.test.sh`, `cloud-init-inngest-bootstrap.test.sh`) and `bash scripts/lint-orphan-test-suites.sh` (the new suite is registered by presence).
- [x] ADR-282 build-record addendum appended (nothing above edited, status stays `accepted`, no new ordinal); `bash plugins/soleur/test/c4-count-parity.test.sh` and the C4 syntax and render tests pass after the `model.c4` edge edit.
- [x] #11816, #11817 and #11820 exist (filed at plan time) and are cited in the PR body; #11817 is blocked by #11816.
- [x] The PR body links the addendum ("Addendum - 2026-10-30 (#9927 item 4, the flip-token design)") and uses `Ref #9927` (never `Closes`).

### Post-merge (owner-gated, NOT part of this PR)

None of the following is run by this PR or its pipeline. The replace needs the owner's fresh in-session per-command go (`runbooks/inngest-server.md`, host-replace row A1; withheld from delegation). Tracker: the Operator Hold in #9927 ("authorizing apply_target=inngest-host-replace", runbook row A1). Owner options at the go (CTO N5; a rehearsal dispatch is a Hetzner write the owner authorizes, so nothing here authorizes it): boot the rehearsal root first to prove Hetzner accepts the real payload size, the guard and flip write precede `provision-unit-armed`, the bootstrap installs the flip trio and the drop-in parses under real systemd; it cannot prove the Doppler write from the `ProtectSystem=strict` sandbox or override order, because the rehearsal's flip token is its read token and the cutover FSMs are inert there. When the go is given: dispatch `apply_target=inngest-host-replace`, confirm the plan shows the shape in the runbook subsection, then read the existing post-replace checks (including `provision-unit-armed` for the new instance id), and let the existing `cutover-inngest.yml` `op=arm` exercise the first flip write (its G6 reports a missing terminal flag within 600 s). The abort and rollback rule is in the runbook subsection. The addendum's "Not measured" list is closed or carried forward in the build record based on that run, not before.

## Test Scenarios

1. Given the rendered template, when the resolver models the flip unit, then its last `EnvironmentFile` is `/etc/default/inngest-flip` and the effective `DOPPLER_TOKEN` comes from that file.
2. Given the same render, when it models every other unit, then none lists the flip file and each token reader resolves a boot-token file.
3. Given a drop-in with a `-` prefix, a wrong section, a typo'd path, a bare reset line after the flip line, or a deleted drop-in, then the suite goes RED (Guard 1 matrix rows 1-7).
4. Given a flip token with `;`, a space, a quote or an empty value, then the guard item exits 1 and phones home `inngest-doppler-write-REFUSED` before any write.
5. Given a plan with the server replaced, the boot token replaced and the flip token created, then the replace gate passes; given `inngest_flip_x`, then it aborts.
6. Given an `inngest_host` plan where the flip token is `["delete","create"]`, then the shape gate aborts with `reason=doppler_touched`.
7. Given the full render with high-entropy stubs, then stored bytes are at most 32,256.
8. Given a flip file that cannot be written (a failed `printf` redirect), then the runcmd item exits 1 and the host does not arm (no `provision-unit-armed` row for the instance id); given the file later missing, then the flip unit fails loud on every 30 s start under the `inngest-cutover-flip` tag.
9. Edge: reboot without replace - the files persist on the root disk and the preserve branch of the bootstrap leaves `DOPPLER_TOKEN` alone (the read-only token still matches `^DOPPLER_TOKEN=dp\.`).
10. Edge (CTO N4): the `inngest_host_replace` dispatch re-embeds the existing flip key unchanged (`-replace` on the server with three `-target`s). Rotating the flip token alone is an owner-run apply on the token resource followed by the gated host replace; revoked-token and guard-refusal recovery use that same route. The gates admit the resulting plan shapes (flip `["create"]` or `["delete","create"]` with the server replaced).

## Guard Contract

### Guard 1 - Effective-environment resolver (flip token reaches only the flip unit)

**Property.** Exactly one systemd unit on the dedicated host, `inngest-cutover-flip.service`, resolves `DOPPLER_TOKEN` from `/etc/default/inngest-flip`; every other unit that reads a Doppler token resolves it from a read-only boot-token file.

**Assembly.** The population of units is every unit source that can reach the host: the baked repo units, the heredoc units that `inngest-bootstrap.sh` writes, and every `write_files` unit and drop-in in the rendered `cloud-init-inngest.yml`. The chokepoint is the resolver's single `effective_env_files(unit)` function, which ingests the unit body plus every drop-in directory for that unit name and applies systemd's accumulation rules; the assertions quantify over the resolver's output for the WHOLE population, not over the files the author remembered. A census floor names the known unit set so a parser that finds nothing cannot pass. There are three injection routes for an `EnvironmentFile=` (the unit body, a `.service.d` drop-in, a `[Service]` line inside a heredoc in the bootstrap script); the resolver reads all three.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `EnvironmentFile=/etc/default/inngest-flip` line from the drop-in | RED |
| 2 | Prefix it with `-` (`EnvironmentFile=-/etc/default/inngest-flip`) | RED |
| 3 | Move the `EnvironmentFile=` line under `[Unit]` (inert "unknown lvalue" in systemd) | RED |
| 4 | Add a bare `EnvironmentFile=` reset line after the flip line | RED |
| 5 | Add the flip file as a second `EnvironmentFile=` in the heredoc unit for inngest-server (a SECOND member after a compliant first) | RED |
| 6 | Typo the path to `/etc/default/inngest-flp` in the drop-in only (printf and drop-in disagree) | RED |
| 7 | Rename the drop-in directory to `inngest-cutover-flip.servce.d` | RED |
| 8 | Gut the drop-in body but leave its path and both directive keywords present (for example only a comment line that spells them) | RED |
| 9 | Add a `ConditionPathExists=/etc/default/inngest-flip` back into the drop-in (N1: no silent skip) | RED |
| 10 | Move the flip `printf` item after the item that arms `soleur-inngest-provision` (REORDER, not delete) | RED |
| 11 | Change `umask 0177` to `umask 0137` on the flip write (the executed item yields mode 640) | RED |
| 11b | Remove `|| exit 1` from the flip write item; and a control case that points the redirect at a non-existent parent directory (NOT an unwritable one: root ignores directory permissions) and asserts the item exits 1 | RED |
| 12 | Add a shell reader of the flip file (a `. /etc/default/inngest-flip` line anywhere) | RED (census S) |
| H1 | Suite edit: make the resolver ignore drop-in directories | RED (positive assertion a fails; also proves the dispatch is not vacuous, the empty-population case being census floor f) |
| H2 | Must-PASS non-canonical: rename the drop-in to `20-whatever.conf` with 4-space-indented directives and a trailing comment line | PASS |
| H3 | Must-PASS non-canonical: the same drop-in delivered as a `<prefix>-.service.d` directory | PASS |

**Anchor.** No stored value is compared; the guard reads the live template and units, so nothing outside the commit needs to move for a weakening to pass. Not applicable.

### Guard 2 - Write-time charset guard covers both Doppler tokens

**Property.** No Doppler token byte reaches a file or a shell word unless the whole value matches `[A-Za-z0-9._:/-]` and is non-empty, and the refusal precedes every write of either token.

**Assembly.** Every substitution site of `${doppler_token}` and `${doppler_flip_token}` in `cloud-init-inngest.yml`: the guard heredoc and three `printf` writes (`inngest-doppler`, `inngest-server`, `inngest-flip`). The chokepoint is the one guard item; the census asserts that no fifth site exists and that the guard's runcmd index is lower than all three writes. The zot guard is a separate chokepoint over different values and is unchanged.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `${doppler_flip_token}` from the guard heredoc | RED |
| 2 | Execute the guard item with a flip token containing `;` | exit 1 + REFUSED row (the guard RED path) |
| 3 | Execute it with a clean boot token and an unsafe flip token on the SECOND heredoc line (a loop that stops after the first line) | exit 1 |
| 4 | Add a fourth `printf` write of the flip token with no guard before it | RED (census) |
| 5 | Move the guard item after the `inngest-server` write | RED (order) |
| 6 | Drop `exit 1` from the guard case arm | RED |
| 7 | Empty flip token | exit 1 |
| 8 | Replace the `while read -r` loop with a single `read -r` (a form that checks only the first heredoc line) | RED (row 3 fails) |
| H1 | Suite edit: stub `inngest-boot-phone-home.sh` to always succeed and assert the REFUSED call is still recorded | RED if the call is not recorded |
| H2 | Must-PASS non-canonical: a token body using each allowed punctuation class (`.` `_` `:` `/` `-`) | exit 0 |

**Anchor.** Not applicable (no stored value).

### Guard 3 - Plan-time gates admit exactly one new address, in lockstep

**Property.** The replace gate and the shape gate admit `doppler_service_token.inngest_flip` and nothing broader, and the shape gate's allow set equals the `inngest_host` job's `-target` set.

**Assembly.** The replace-gate `def allow`, the shape-gate `def allow` and its class table, the workflow's `inngest_host` `-target` list, and the parity test's exclusion sets: four places that must agree, with `terraform-target-parity.test.ts` as the cross-file chokepoint and the shape gate's `allow_unpartitioned` counter as the in-file one.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the address from the replace gate `def allow` | the new PASS row goes RED |
| 2 | Replace gate: plan with `inngest_flip_x` (lookalike) after a compliant `inngest_flip` | ABORT |
| 3 | Shape gate: remove the address from `def allow` but leave the class entry (executor: `test-inngest-host-shape-gate.sh` copies the gate lib to a temp dir with that line deleted and sources the copy) | `allow_unpartitioned` RED |
| 4 | Remove the new `-target` from the `inngest_host` job only (executor: a block in `terraform-target-parity.test.ts` that feeds its own `commandIn()` and parity assertion an in-memory mutated copy of the workflow text) | parity assertion RED |
| 4b | Replace gate fixture direction: flip token `["create"]` while the server is NOT replaced (no `inngest_server_replaced`) | ABORT |
| 5 | Shape gate: `["delete","create"]` on the flip token | `reason=doppler_touched` |
| 6 | Feed both gates an unreadable or empty plan (dispatch vacuity) | fail closed (preamble) |
| H1 | Suite edit: make `build` skip the new address | the "every address no-op" PASS row goes RED |
| H2 | Must-PASS non-canonical: `["update"]` on the flip token | PASS |

**Anchor.** The parity test reads the workflow and the gate from the same commit; a weakening that edits both passes consistency but not integrity. The independent anchor is the replace gate's own PASS/ABORT fixtures (synthesized plans in `test-inngest-host-replace-gate.sh`) and the owner's per-command go before any dispatch; stated rather than hidden.

## Architecture Decision (ADR/C4)

The decision (split the credential) is already recorded and accepted in ADR-282; this plan builds it. The deliverables below keep recorded architecture from lagging the build.

### ADR

Append a build-record addendum to `ADR-282-sole-copy-luks-volume-protection-set.md` (append-only, nothing above edited, status stays `accepted`, no new ordinal), via the `soleur:architecture` skill, at the end of `soleur:work`, containing: what landed (both tokens, the drop-in, the gates and the `-target`); the measured figures (stored bytes, cap headroom, margin under 32,300) and the stub-entropy correction (both stubs now high-entropy, a 512 B floor enforced by the budget script); the CTO rulings R1-R6 and N1-N6 as pointers to `knowledge-base/project/specs/feat-one-shot-inngest-flip-token-split/decision-challenges.md` (archived at ship); which of the addendum's "Not measured" items this PR closed (the real `user_data` headroom, the `allow[]`/shape-gate behaviour with a new address, the drop-in load order via `systemd-analyze --root cat-config`, and last-wins resolution via `systemd-run --user` where available) and which remain open (file mode and owner on a replaced host, an app boot on a read-only token, the Doppler write from the flip unit's `ProtectSystem=strict` sandbox, the reboot-without-replace path); the stale prose in `inngest-cutover-flip.sh`; the guard's per-line limit (CTO N10); the unverified real Doppler token body width behind the stub (CTO N12); the first-replace deferral of the `user_data` length precondition and the budget step that covers it (CTO N9); #11816, #11817 and #11820; that #11265 is a separate PR. Status wording: the build is merged but not yet delivered to any host.

### C4 views

Required reads (done at plan time by grep; the implementer reads all three files in full before editing): `diagrams/model.c4`, `views.c4`, `spec.c4`. Enumeration against the change: (a) external human actors - none added or changed; (b) external systems - Doppler (`doppler`) and the Hetzner metadata API (reached through `hetzner`) already modeled, no new system; (c) containers and stores - the `inngest` host container exists, a root-disk credential file is not a store; (d) actor-surface access - no change. The one falsified statement is the edge `doppler -> inngest`, whose description says "dedicated host's boot credential is scoped to the SEPARATE Doppler project" in the singular. Edit that description (in `model.c4`) to say the host holds a read-only boot credential plus a root-only read/write flip credential read only by the flip unit, with the ADR-282 pointer. No new element or relationship, so `views.c4` needs no `include` change. Run `bash plugins/soleur/test/c4-count-parity.test.sh` (baseline today: all passed) and the two C4 syntax and render tests after the edit.

### Sequencing

The ADR describes a build that is merged but undelivered until the owner-gated replace; the addendum says so and does not claim a live host state.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/inngest-host.tf` (token access change, new `doppler_service_token.inngest_flip`, `templatefile` var), `inngest-provision-rehearsal/rehearsal.tf` (var passthrough), `inngest-arm-write-token.tf` (comment only). Providers: DopplerHQ/doppler already pinned in this root; no new provider, no new version pin. Sensitive values: the new token's `.key` is Computed/write-once and lands in `terraform.tfstate` (R2 backend) like the other service tokens; no `TF_VAR` is added, no operator-minted default (`hr-tf-variable-no-operator-mint-default` is not triggered: the token is minted by Terraform in the apply, not by the operator). State exposure: the new key is Computed and sensitive (confirmed against DopplerHQ 1.21.2) and lands in `terraform.tfstate` twice, once as the resource attribute and once inside `hcloud_server.inngest.user_data`; the R2 backend is CI-only. Every host-side artifact (the drop-in, the flip file, the guard) is delivered by cloud-init `write_files`/`runcmd` at birth, not by an operator step.

### Apply path

(b) `terraform apply -replace` via the existing gated `apply_target=inngest-host-replace` dispatch (the host has state on a persistent LUKS volume that survives a replace). This PR does not run it. Expected blast radius at the owner's go: the sole scheduler is down for the replace window; the Redis AOF volume is preserved by omission from the plan. Expected plan shape: `-/+ doppler_service_token.inngest`, `+ doppler_service_token.inngest_flip`, `-/+ hcloud_server.inngest`, `-/+ hcloud_server_network.inngest`, `-/+ hcloud_volume_attachment.inngest_redis_luks`, volume untouched. A mid-replace failure leaves the host absent with both tokens rotated; recovery is the existing re-dispatch (`stock_recovery_report`), which is why the 512 B headroom floor exists.

### Host fan-out

No `terraform_data` SSH provisioner is added or edited, so the web-host fan-out classification does not apply. Fleet siblings: the registry and git-data hosts have their own tokens and are `role-only`; the co-located web host's inngest units use its own token files and are untouched.

### Distinctness / drift safeguards

`dev != prd` preconditions: the token lives in the `soleur-inngest` Doppler project only, with no inheritance path to `soleur/prd`. No `lifecycle.ignore_changes` is added (the key must propagate to `user_data` in the same apply). The shape-gate and replace-gate lockstep above is the drift safeguard for the plan-time surface.

### Vendor-tier reality check

Doppler service tokens with `access = "read/write"` and `"read"` are both available on the current plan (the repo already mints both kinds); no tier gate is needed.

## Observability

```yaml
liveness_signal:
  what: the existing boot phone-home row `provision-unit-armed` (emitted once per host life with the instance id; it can only follow a successful flip-file write because a failed write aborts runcmd first), plus the existing `flip-assets-staged` row
  cadence: once per host boot / provision attempt
  alert_target: Better Stack Logs source 2457081 (the boot phone-home channel); read by the existing post-replace checks in runbooks/inngest-server.md
  configured_in: apps/web-platform/infra/cloud-init-inngest.yml (the flip-file runcmd item ends `|| exit 1`; the `provision-unit-armed` call is later in runcmd)
error_reporting:
  destination: Better Stack boot phone-home (direct curl, Vector-independent) via inngest-boot-phone-home.sh
  fail_loud: `inngest-doppler-write-REFUSED` phone-home and runcmd `exit 1` when either Doppler token carries an unsafe character; the host does not arm
failure_modes:
  - mode: flip file not written, or later missing or wrong
    detection: layer 3 (Vector journald, tag `inngest-cutover-flip`) for a later-missing file, which fails the flip unit on every 30 s start with stderr shipped; and, for a failed write, the Vector-independent boot phone-home sibling of layer 3: runcmd aborts, so `provision-unit-armed` never arrives for that instance id (the existing follow-through detector keys on it). A guard refusal emits its own `inngest-doppler-write-REFUSED` row; `provision-unit-armed` absent AND no `REFUSED` row therefore means the flip write failed
    alert_route: layer 6 (workflow run log, `::error::` from the `cutover-inngest.yml` op=arm G6 step); post-replace check in the runbook; op=arm G6 "no terminal FSM flag within 600s" in cutover-inngest.yml; accepted residual tracked in #9927 (no new alert, CTO N4)
  - mode: flip token revoked or invalid
    detection: layer 3 (Vector journald, tag `inngest-cutover-flip`): `ExecStart` is `doppler run`, so a revoked token fails the unit BEFORE any script code on every 30 s start, and the `noop-*` liveness row (throttled to 300 s) stops arriving; the Doppler write in flag_set is a later failure site only for a token revoked mid-run
    alert_route: layer 6 (workflow run log): caught PRE-ARM by the `cutover-inngest.sh` G3.7 liveness refusal (`FLIP_LIVENESS_SINCE=15m` refuses a silent flip unit for op=arm, resume and reflush). After the cutover reaches `done`, a revoked flip token leaves rollback dead WITHOUT an alert (the only alert on that tag, `inngest_luks_key_probe_fail`, fires from inside the script, which never starts). Tracked follow-up #11820 (silence alert at 300/900 modelled on `egress_gw_probe_silent`, with replace-window suppression, ideally with the #11266 dead-man work); not added here because the alert file is applied per-merge and would make the PR's "merging changes nothing in production" sentence false (CTO N8)
  - mode: a hidden writer needs write access and fails under the read-only boot token
    detection: layer 3 (Vector journald): the only on-host Doppler secret-write verb is in flag_set (re-verified at deepen time by grep over the infra scripts: `inngest-cutover-flip.sh` is the sole executable one); any other would surface as a journald error for its unit
    alert_route: Better Stack Logs search by unit tag; no dedicated alert
logs:
  where: Better Stack Logs (boot phone-home source 2457081; journald tag inngest-cutover-flip via Vector)
  retention: per the Better Stack source plan (hot window about 40 minutes; archive at least 40 days measured, 90 days retention)
discoverability_test:
  command: bash scripts/betterstack-query.sh --since 72h --grep provision-unit-armed --limit 1
  expected_output: provision-unit-armed
  credentials_required: "Better Stack query credentials (BETTERSTACK_QUERY_*, Doppler soleur/prd_terraform) - the warehouse has no unauthenticated read path that verifies a boot row"
```

Affected-surface note (Phase 2.9.2): the flip unit runs as root on a host with no inbound SSH, a blind surface. This PR adds no new in-surface probe (CTO N1/N2 cut the proposed one: the byte margin is 60 B and the existing `provision-unit-armed` row already discriminates "armed" from "runcmd aborted" per instance id); the drop-in's correctness is proven offline by the resolver suite and the `systemctl --root cat` cross-check, file mode by the executed-item test, and the unproven residual (the Doppler write from the `ProtectSystem=strict` sandbox) is left to the first real flip and named in the build record. The probe above verifies boot arming only (a once-per-host-life row, so the window is 72 h and a healthy host older than that returns nothing; the instance-id keyed recipe in `inngest-server.md` is the precise read), NOT the flip-token property; the comment beside the ratchet bump must say so. It returns a row only after the owner-gated replace, and the preflight ratchet `BASELINE_DECLARED_PROBES` is bumped for the declared `credentials_required`.

## Encryption Posture

No new store and no new network connection: the PR adds no volume, bucket, table, queue, cache or backup target. It adds one credential file on the existing root disk of `hcloud_server.inngest`, the same posture as its siblings `/etc/default/inngest-doppler` and `/etc/default/inngest-server`. Because the detection patterns (`.tf`, cloud-init) match this diff, the credential file is declared explicitly rather than skipped:

```yaml
at_rest:
  - store: /etc/default/inngest-flip on the root disk of hcloud_server.inngest (not the LUKS volume hcloud_volume.inngest_redis_luks)
    mechanism: plaintext-exception
    evidence: apps/web-platform/infra/cloud-init-inngest.yml (the flip-file runcmd item, mode 0600 root:root via umask 0177); the file holds a Doppler service token, same class as /etc/default/inngest-doppler and /etc/default/inngest-server
    defends_against: a read by any non-root account (mode 0600 root), a read through an app-user unit (no unit but the flip unit lists the file), accidental disclosure into shared log tails (scrubbed by value in inngest-redact.sh)
    does_not_defend: root on the host; a deploy-user process, which is root-equivalent through the docker group and NOPASSWD sudo (#11816); any reader of the Hetzner metadata API, because the same value rides in user_data (#11817); a raw snapshot of the root disk (the root disk is not LUKS)
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:file mode and owner are unobserved until the owner-gated replace; pinned statically by the executed-item test
in_transit: []   # no new connection; user_data delivery over the Hetzner API and metadata service is the existing channel, unchanged
exception:
  justification: a root-disk credential file with 0600 root mode is the accepted posture for every host credential in this stack; the residual is the ADR-282 addendum's recorded "does not fix" list
  tracking_issue: "#11816"
  reevaluate_when: the deploy-user root-equivalence review (#11816) lands, or the metadata egress block (#11817) lands, whichever is first
  expires_on: 2027-01-08
```

## User-Brand Impact

- **If this lands broken, the user experiences:** a replaced Inngest host that boots with a refused or missing flip credential, so the cutover flip cannot advance (the sole scheduler keeps running its current state but a later cutover step stalls) or the host does not arm at all, leaving scheduled agent runs and reminders unfired until a re-dispatch; a mis-scoped drop-in could instead leave the read/write token readable by app-user units, silently defeating the split.
  > Corrected 2026-11-01 (review round): after a replace there is no running scheduler to "keep its current state". The replaced host inherits `INNGEST_CUTOVER_FLIP=done` and the scheduler is dark until `op=resume`; every user's scheduled routines then depend on the flip token being valid, because the on-host `flushed` arm (`start_server`, `verify_or_abort`, `flag_set "done"`) is what restores them. A dead or rejected flip token leaves the scheduler down until an owner-only rotation plus a second replace; a token that cannot write leaves the scheduler up with the flag parked at `flushed` and the unit failing every tick. The runbook's owner steps (a JSON `noop-done` row from the new host before `op=resume`) are the cover.
- **If this leaks, the user's workflow is exposed via:** the boot token (0640 root:deploy) or the flip token (in `user_data`, readable through the Hetzner metadata API by anyone with host access); either can read `soleur-inngest/prd`, and the flip token (like `inngest_arm_write`) can overwrite the LUKS passphrase pair, i.e. destroy the durable queue and run state that user jobs depend on. The split narrows who holds a write-capable token short of host root; it does not remove deploy-user or metadata-reader paths (#11816, #11817).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** carried from ADR-282's own `brand_survival_threshold: single-user incident` (the sole-copy volume holds user job state with no backup), not lowered because this PR only narrows exposure: the failure modes above can still strand or silently mis-secure the one scheduler host.

`requires_cpo_signoff: true` (frontmatter). CPO sign-off is carried from the ADR-282 chain and re-requested for this build at plan time (see Domain Review); `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Two CTO rounds recorded in `decision-challenges.md`: R1-R6 at plan time (gate and `-target` lockstep, byte budget and entropy floor, #11265 separate PR, redaction by value, drop-in semantics and the resolver test, rotation and ordering) and N1-N6 after the five-agent plan review (drop the Condition and phone-home, fail-closed write, both stubs high-entropy with a CI-enforced 512 B floor, the real rotation and recovery routes, the pre-go rehearsal option, the merge-time blast radius). Medium PR, risk in the shell tests, not the Terraform.

### Other domains

Legal/GDPR (`hr-gdpr-gate-on-regulated-data-surfaces`): not triggered - no schema, migration, auth flow, API route or `.sql`, and no personal data is processed; credential infrastructure only. Product/UX: none (no UI-surface file in Files to Edit or Create). Operations: the replace window and any provider action are owner-gated and not performed here. CPO (advisory, 2026-11-01): signed off with conditions, all encoded: the replace's tracker is the Operator Hold in #9927 (runbook row A1); the runbook subsection states the replace-window impact and an abort and rollback rule; the silent-stall case is an accepted residual tracked in #9927; the "Not measured" closeout gates closing the epic, not this PR.

## Downtime & Cutover

(Deepen-plan Phase 4.55. The trigger fires because the code this PR ships is only delivered by a destroy-and-recreate of `hcloud_server.inngest`; merging itself takes nothing offline, which is why the PR body leads with that sentence.)

**The offline-inducing operation.** The later owner-gated `apply_target=inngest-host-replace`: a `-replace` of the sole Inngest scheduler host (the `user_data` change from the token split cannot be applied in place, and the token `access` change is ForceNew). Affected surface: every scheduled agent run, reminder and cron the platform fires through the dedicated Inngest host, for the length of the replace window (destroy, create, cloud-init, bootstrap, LUKS reopen, the first flip poll).

**Zero-downtime paths evaluated, and why none is available.**

- Blue-green (provision a second host, drain, cut over, retire the first): rejected. The runbook records the single-writer constraint (two live schedulers on the production Postgres double-fire crons and reminders), and the sole-copy LUKS volume attaches to one server at a time; a second live host would need a second copy of the durable state the ADR-282 posture deliberately keeps single.
- In-place change (no replace): impossible. The credential split lives in `user_data` (re-rendered only at birth) and the new file is not in the config-refresh bundle, which the brief forbids building and whose HARD-1 membership rules would not admit a new credential file.
- Rolling, expand-contract, `terraform state mv`, drain-then-act: no applicable stage; there is one host and no schema.

**Accepted residual and bounds.** The replace is the same disruption class the stack has already run (the 2026-09-27 and 2026-10-20 replaces are recorded in the runbook); this build adds no new offline step, only a new payload. The window is bounded by the existing post-replace window and abort rule that the runbook subsection (Phase 6 step 3) restates, and it runs only in a maintenance window the owner chooses, bundled with whatever else is waiting on a replace (#9927 items 2 and 4, #11265 as a separate PR). Operator sign-off is the owner's fresh in-session per-command go, which the brief says is still withheld; nothing in this PR requests, simulates or pre-authorizes it. Per-stage verification and rollback: the existing post-replace checks (including `provision-unit-armed` for the new instance id), the abort and rollback rule and the re-dispatch recovery route in the runbook subsection, and the pre-go rehearsal option (CTO N5) to learn the unmeasured items before the destroy.

## Dependencies & Risks

- **Byte margin is 60 B over the CTO floor** in the prototype (32,196 B stored, 572 B cap headroom); every added code byte in `cloud-init-inngest.yml` is a risk to the replace window (a rejected CREATE after the DESTROY is the 2026-09-08 stranded-host failure). Mitigation: measure after each cloud-init edit, never raise the budget; the budget script now enforces the floor in CI.
- **Loud, not silent** (CTO N1): the drop-in has no Condition, so a flip file that goes missing after a good boot makes the flip unit fail on every 30 s start (a bounded loop reachable only by manual deletion, stderr shipped). A revoked flip token is worse mid-FSM: `doppler run` fails before the script starts, so no FSM marker and rollback is dead until the owner-only recovery route in the runbook (unverified on a live host). Pre-arm it is caught by the G3.7 liveness refusal; after `done` it is unalarmed. Accepted residual with follow-up #11820 (CTO N8).
- **No online repair path**: the drop-in and flip file are not in the config bundle, so any defect found after the replace needs a second replace of the sole scheduler. The pre-go rehearsal option (CTO N5) is the mitigation, owner's call.
- **The model could drift from systemd**: section X cross-checks against `systemd-analyze --root cat-config` (and `systemd-run --user` for last-wins); where those are absent the skip is counted and loud.
- **Stub entropy**: fixed here for both tokens (CTO N3): the gated figure rises by about 44 B per token and the budget script enforces the 512 B headroom floor.
- **Comment-only edits are host replaces** (`user_data` has no `ignore_changes`): even the free comment refresh in `cloud-init-inngest.yml` re-renders `user_data`; harmless because the replace is already owner-gated and this PR is its payload.
- **Unmeasured until a real replace**: file mode and owner on a replaced host, an app boot on a read-only token (the rehearsal root already boots a read-only token, supporting but not proving it), the Doppler write from the flip unit's sandbox, the reboot-without-replace path. All stay in the ADR's "Not measured" list.
- **Residuals unchanged**: root on the host, a deploy-user process via docker or sudo, any metadata reader, `doppler_service_token.inngest_arm_write`, `DOPPLER_TOKEN_TF` can still overwrite the key.

## References

- ADR-282 and its addendum "Addendum - 2026-10-30 (#9927 item 4, the flip-token design)"; ADR-100 (dedicated host), ADR-135 (config-refresh channel), ADR-142 (LUKS volume).
- Issues: #9927 (epic), #6890 (closed, not planned), #6178, #11265, #11266, #11664, #11602, #10243, #11816, #11817.
- Decision record: `knowledge-base/project/specs/feat-one-shot-inngest-flip-token-split/decision-challenges.md`.
- Gate sources: `tests/scripts/lib/inngest-host-replace-gate.sh`, `tests/scripts/lib/inngest-host-shape-gate.sh`, `plugins/soleur/test/terraform-target-parity.test.ts`, `apps/web-platform/infra/inngest-userdata-budget.sh`, `plugins/soleur/test/cloud-init-user-data-size.test.ts`.

## Sharp Edges

- A `## User-Brand Impact` section that is empty, `TBD`/`TODO`, or lacks the threshold fails `deepen-plan` Phase 4.6; this plan fills all four lines.
- Two block-scoped awk hazards in the rewritten finding 1b: the old anchor `resource "doppler_service_token" "inngest"` includes the closing quote, so it does NOT match `"inngest_flip"` (an earlier draft of this plan claimed it would; keep the quote anyway), but a block-scoped awk must exit at `^}` or it reads into the next resource, and the second block needs its OWN `name = "inngest-flip"` and `access = "read/write"` assertions rather than inheriting the first block's.
- A `-` prefix, a bare reset line, a wrong section or a typo'd path each make the drop-in inert while a whole-file presence grep stays green; the resolver, not a grep, is the assertion.
- Editing any image carrier or bundle member to "fix the stale comment" mints an image tag on merge (`mint-inngest-bootstrap-tag.yml`); run `--dry-run` and expect `result=noop`.
- Do not source the flip file anywhere: sourcing it overwrites `DOPPLER_TOKEN` for the rest of the shell. Read with `sed` only.
- Never print token values in test output, PR text or phone-home details; stubs are derived from a hash, and the phone-home detail is mode and owner only.
- The brief's "(not a -target)" is true only for the replace job; reading it as a ban on the `inngest_host` `-target` reds `terraform-target-parity.test.ts`.
