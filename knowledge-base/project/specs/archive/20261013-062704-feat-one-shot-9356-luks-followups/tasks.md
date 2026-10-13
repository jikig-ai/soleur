# Tasks: LUKS web-host follow-ups (#9356 #9357 #9358 #9377 #9378)

Plan: knowledge-base/project/plans/2026-10-01-chore-luks-web-host-followups-disposability-escrow-hardening-plan.md
Spec lacks valid lane: — defaulted to cross-domain (fail-closed).

Constraint: no terraform apply, no workflow_dispatch, no Doppler write, no Cloudflare token mint. Live steps are deferred and gated.

## Phase 0 — Baselines

- 0.1 Record apply-web-platform-infra.yml byte size (cap 490,000) and user_data gzip headroom
- 0.2 Time the provisioner suite and count sed execs in the fixture builder
- 0.3 Find the CI job that has terraform (infra-validation.yml candidate)
- 0.4 Measure /var/lib/cloud/instance presence on the CI runner image

## Phase 1 — #9378 provisioner hardening (RED rows first, Guard 1 and 2)

- 1.1 PATH pin first, then flock on fd 9 after command -v check; exec-open check; lock_timeout reason; real-flock held-fd case; seam-only short timeout; clamp SOLEUR_STAGE_DETAIL_DIR
- 1.2 Pin PATH when ROOT is empty
- 1.3 _seam_allowed (euid 0 + /var/lib/cloud/instance refuses the seam)
- 1.4 _install_file (symlink refusal x4, temp removal, validate before rename, ownership/mode, checked syncs, no-trailing-newline fixture) for fstab, crypttab, drop-in, intent file
- 1.5 cron-egress-nftables.test.sh (stateful stub nft) + range-arithmetic link-local overlap check in is_valid_ipv4_cidr + literal 169.254.0.0/16 drop before accepts; previous ruleset retained on die
- 1.6 Resolver link-local filter AFTER all feeders merge (container view, seen/ pool, DNS_IPS) + purge seen files + test; update metadata-endpoint test header
- 1.7 Split case_raw_formats_once into four cases; move EXPECTED_CASES and floors; re-drive every mutation row restricted vs full; fork trim only if measured
- 1.8 New provisioner cases for 1.1-1.4 (floors from a measured run)
- 1.9 Pin escrow endpoint shape (fixture update)

## Phase 2 — #9358 marker seam (Guard 5)

- 2.1 lb-weight-gate-with-marker.sh (names-list then single get; exit 3 on any failure after membership; unset caller value and DOPPLER_*; pinned PATH; shape-validate value)
- 2.2 Wrapper test with stub doppler
- 2.3 Census section; rewrite stale gate comments

## Phase 3 — #9377 escrow split (Guard 3; additive only)

- 3.1 workspaces-luks-header-web.tf (bucket, doppler_config, three secrets) + guard test
- 3.2 NEW fresh-boot token resource (config + token in fresh-boot.tf); server.tf reference; fix F1-F3 predicates; no ForceNew replace; old token retirement tracked
- 3.3 cloud-init.yml printf literal to prd_workspaces_luks_web
- 3.4 Provisioner closed-set config pin; luks-monitor.sh _one-shape parse of boot env file with fallback; heartbeat stays; reopen-failure.service default allowed by name
- 3.5 scripts/check-web-host-escrow-config.sh (+ test): --static and live mode
- 3.6a Move pins: fresh-boot-parity 16d/20a, workspaces-boot-unlock, F1-F3, provision fixtures, luks-monitor test
- 3.6b Enumerate every apply workflow that reaches the edited TF; PR body first line answers whether merge mutates production; saved plan JSON shows creates only
- 3.6 -target list, terraform-target-parity freshBoot, ledger row, test-all registration (no TSV hand-edit), byte-size check
- 3.7 Article 30 register, compliance-posture, read article-30-2-register
- 3.8 (deferred, gated) R2 pair mint and first signed PUT/HEAD — comment on #9377

## Phase 4 — #9356 arms, populated-volume proof (Guard 4)

- 4.1 Arms constant, extended allow-set, two requirement arms; refusal first; comment restates non-plan blockers
- 4.1b Add key-copy secret to luks_passphrase_touched arms (replace gate + recut gate); decide rotation HALT
- 4.2 Gate suite fixtures + mutation rows; refusal-intact case
- 4.3 Parity assertion for the arms extension (workflow -target list untouched)
- 4.4 Three populated-volume rows; header-restore drill in the loopback suite
- 4.5 Rehearsal runbook section with inline row query

## Phase 5 — #9357 offline rehearsal (Guard 6)

- 5.1 workspaces-luks-t2-rehearsal.test.sh (terraform_data mini-root, occupied web-1 slots, pinned terraform version; placement decided in Phase 0.3)
- 5.2 T2 runbook (preconditions, commands read by the test, rollback)
- 5.4 File de-pet issue; blocked-by edges; comments on #9356 #9357 #9358 #9377

## Phase 6 — Docs

- 6.1 ADR-263 amendment (D7, R4 narrowed, option b rejected, T2 readiness); ADR-148 and ADR-068 pointers
- 6.2 model.c4 doppler -> hetzner edge prose; run c4 tests
- 6.3 Sweep stale comments

## Ship notes

- PR body: Closes #9378; Ref #9356 #9357 #9358 #9377; #9372 not dispatched, not closed
- Review: user-impact-reviewer (single-user incident)
