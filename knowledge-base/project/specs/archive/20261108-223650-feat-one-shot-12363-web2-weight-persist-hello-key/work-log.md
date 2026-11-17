# Work log: A-0 (web-2 weight default 1 + PROXY_HELLO_HMAC_KEY mint)

Verdict blocks only; raw streams are not committed.

## RED before GREEN (commit 1, run against the unchanged lib/tree)

```text
FAIL: pool-update: serve with everything no-op against live {1,1} passes (want rc 0, got 1)
FAIL: pool-update: serve no-op names the already-{1,1} notice (want rc 0, got 1)
FAIL: pool-update: serve no-op pool at web-2 weight 0 refused (not a serving shape) (want rc 1, got 0)
FAIL: pool-update: serve no-op pool with web-1 at weight 0 refused (origins pins reach the no-op path) (want rc 1, got 0)
FAIL: pool-update: serve with the pool entry absent refused (want rc 1, got 0)
FAIL: pool-update: serve pool-absent refusal carries its own distinct message (want rc 0, got 1)
FAIL: pool-update: serve no-op built exactly one copy, inside TMPDIR (instrument sees it) (want rc 0, got 1)
FAIL: pool-update: a REFUSED no-op serve still removes its temp copy (rc 1, dir empty, copy was built) (want rc 0, got 1)
FAIL: pool-update: serve no-op pool entry carrying previous_address refused (exact normalisation predicate) (want rc 1, got 0)
FAILURES PRESENT
  FAIL: C.4-V2: web2_lb_weight is type = number with default = 1 (the live serving shape; default plan is a no-op agains
  FAIL: C.4-F1: only variables.tf, cloudflare-lb.tf and cf-lb-overlay.yml name web2_lb_weight (got: .github/workflows/cf
  FAIL: C.4-F6: web2_lb_weight appears on exactly TWO non-comment lines of cf-lb-overlay.yml: the ga_pool_update plan st
  FAIL: C.4-F8: the ga_overlay plan step passes -var="web2_lb_weight=0" exactly once (literal 0, non-comment): a fresh G
  FAIL: C.4-F8m1 mutant: the ga_overlay -var carries weight 1 (a fresh create would pool web-2 hot): the mutation did no
  FAIL: C.4-F8m2 mutant: the ga_overlay -var line is deleted (default 1 would apply): the mutation did not land (copy id
```

## Stale-wording sweep (Phase 1.4), after the change; every hit is a true statement about drain as an explicit act, history, or the named L160 attribute exception

```text
apps/web-platform/infra/variables.tf:181:  # the freed 10.0.1.11 address. web-2 was OUT-OF-BAND (serving-weight 0, ADR-143 D2) until the
apps/web-platform/infra/variables.tf:567:  description = "web-2 origin weight in the GA LB pool (0 = drained, 1 = serving). Default 1 = the live servi
apps/web-platform/infra/variables.tf:573:    error_message = "web2_lb_weight must be 0 (drained) or 1 (serving)."
apps/web-platform/infra/cloudflare-lb.tf:71:# serving). A drained member (weight 0, via the explicit drain act) is health-checked but
apps/web-platform/infra/cloudflare-lb.tf:87:  # B2: gated member — weight 0 means health is still checked but no traffic is routed
apps/web-platform/infra/cloudflare-lb.tf:88:  # (provider drained semantic); weight 1 serves. var.web2_lb_weight DEFAULTS to 1
apps/web-platform/infra/cloudflare-lb.tf:104:  # least_* policies are meaningless at a {1,0} drained shape.
apps/web-platform/infra/cloudflare-lb.tf:152:  # default_pool_ids contains ONLY web-1's pool; web-2 rides inside it drained (B2).
apps/web-platform/infra/cloudflare-lb.tf:160:  description = "ADR-068 §(b) multi-host GA overlay (web-2 drained at weight 0 until the #6027 window fli
.github/workflows/cf-lb-overlay.yml:25:#                     web-2 at weight 0 (an explicit -var); mode=serve grades web-2 at
.github/workflows/cf-lb-overlay.yml:56:        description: "ga-pool-update only: drain = web-2 set to weight 0 (explicit); serve = grade and apply we
.github/workflows/cf-lb-overlay.yml:503:          # The web-2 weight variable defaults to 1 (live). A fresh GA3 create must stay the drained
.github/workflows/cf-lb-overlay.yml:873:            echo "::error::pool-health reports unhealthy origin(s) (${HEALTH}) across the ~5min poll under htt
.github/workflows/cf-lb-overlay.yml:882:    # REVIEWER-GATED like ga-overlay. mode=drain lands the drained shape (web-2 at
.github/workflows/cf-lb-overlay.yml:883:    # weight 0, health-monitored; an explicit -var, the variable's default is 1).
```

## Phase 3.6 / 3.7 evidence

```text
== 960ec26913
960ec26913 feat(infra): web-2 serve arm prep: web2_lb_weight (default 0) and the relay bind probe step (Ref #8211, #12167) (#12168)

apps/web-platform/infra
.github/workflows/cf-lb-overlay.yml
.github/workflows/infra-validation.yml
knowledge-base/engineering/operations
scripts/lib/web2-relay-rows.sh
scripts/lib/web2-relay-rows.test.sh
scripts/suite-durations.tsv/
scripts/suite-shard-legs.tsv/
== 9682d9440d
9682d9440d feat(lb): dispatch-only ga-monitor-https arm - LB monitor to https/443 (ADR-321 R7) (#12301)

apps/web-platform/infra
.github/workflows/cf-lb-overlay.yml
knowledge-base/engineering/architecture
knowledge-base/engineering/operations
plugins/soleur/test
tests/scripts/lib
tests/scripts/test-cf-lb-overlay-gate.sh
== e2964b801d
e2964b801d feat(infra): reviewer-gated key-rotate-approval environment + no-SSH vector restart enabling egress token rotation (#11923, #11920) (#12153)

apps/web-platform/infra
.github/workflows/apply-web-platform-infra.yml
.github/workflows/inngest-key-rotate.yml
.github/workflows/key-rotate.yml
knowledge-base/engineering/architecture
knowledge-base/engineering/operations
knowledge-base/project/learnings
knowledge-base/project/plans
== release workflow paths filter
on:
  push:
    branches: [main]
    # Runtime-plugin changes (skills/hooks/agents/scripts/commands/instructions the
    # Concierge executes) must rebuild+deploy the image so the host mount re-seeds
    # (plan 2026-07-02-fix-runtime-plugin-deploy-to-concierge-host, ADR-080).
    # DENYLIST: everything under plugins/soleur/ EXCEPT docs/ (deploys via
== 3.7 evidence
cloudflare_load_balancer in apply workflow: 0
tf files naming pool/lb/monitor:
apps/web-platform/infra/cloudflare-lb.tf
web_lb_health in apply workflow: 0
tf files naming web_lb_health/load_balancer_pool:
apps/web-platform/infra/cloudflare-lb.tf
workflows naming web2_lb_weight:
.github/workflows/cf-lb-overlay.yml
== full-root terraform plan/apply workflows (no -target on the line chain):
.github/workflows/apply-deploy-pipeline-fix.yml
.github/workflows/apply-git-data-root-key.yml
.github/workflows/apply-github-infra.yml
.github/workflows/apply-sentry-infra.yml
.github/workflows/apply-web-platform-infra.yml
.github/workflows/cf-lb-overlay.yml
.github/workflows/git-data-rung2-rehearsal.yml
.github/workflows/infra-validation.yml
.github/workflows/inngest-provision-rehearsal.yml
.github/workflows/merge-queue-stall-check.yml
.github/workflows/scheduled-sentry-alert-drift.yml
.github/workflows/scheduled-terraform-drift.yml
.github/workflows/test-pretooluse-hooks.yml
.github/workflows/validate-vector-config.yml
WEB2_LB_WEIGHT names in prd_terraform (names only): 0
```

## Sandbox mutation battery (Phase 3.5), control green first, every mutation asserted LANDED against a pristine copy

```text
ROW G1.1 serve passes the plan through (no normalisation): RED as expected [serve with everything no-op]
ROW G1.2 normalise in drain mode too: RED as expected [drain with only a no-op pool]
ROW G1.3 normalise EVERY no-op entry: RED as expected [serve with everything no-op]
ROW G1.4 delete the pool-absent refusal: RED as expected [carries its own distinct message]
ROW G1.5 skip the inner grader for no-op plans: RED as expected [web-2 weight 0 refused]
ROW G1.6 leak the normalised copy (drop rm -f): RED as expected [removes its temp copy]
ROW G1.7 default arm falls through to the inner grader: SURVIVED (suite green under the mutation)
ROW G1.8 drop the exact-entry predicate (previous_address): RED as expected [previous_address refused]
ROW H1 delete one pn fixture assertion line: the exact floor goes red: RED as expected [anti-vacuity]
ROW G2.3 value becomes ${WEB2_LB_WEIGHT}: F8 RED, F6 stays green (as expected)
ROW G2.4 a third non-comment line naming the variable: F6 RED
ROW G2.5 the drift workflow names the variable: F7 RED
ROW G2.mp a comment-only edit to the ga_overlay step stays GREEN (must-PASS)
ROW G3.1 remove the doppler_secret -target: RED [saved plan]
ROW G3.2 remove the random_bytes -target: RED [saved plan]
ROW G3.3 drop count from the secret: RED [count-gated]
ROW (G3) INVALID: mutation failed to land
ROW G3.5a visibility unmasked: RED [32 random bytes]
ROW G3.5b length 16: RED [32 random bytes]
ROW G3.5c an output exposing the value: RED [32 random bytes]
ROW G3.mp a comment-only edit stays GREEN (must-PASS)
== SUMMARY rows=20 as-expected=19 unexpected=2
ROW G3.4 add the address to web_host_create -target: RED [saved plan] (run by hand in the sandbox after the scripted row failed to land)
```

Row G1.7 (the dispatch default arm falls through to the inner grader) SURVIVED the first battery and was labelled equivalent. **That label was wrong** (test-design review): a pool entry with `["read"]` is dropped by the grader's change filter, so with POLICY_CREATE present it passes through the remnant branch; the default arm is load-bearing. Fixed by fixture pn13; re-driven in the post-review battery below.

## Floors (exact, measured)

- test-cf-lb-overlay-gate.sh checks: 125 (110 baseline + 14 enumerated + 1 single-chokepoint census row)
- lb-weight-gate.test.sh MIN_CASES: 285 (282 + F8 + two mutants)
- terraform-target-parity.test.ts TEST_FLOOR: 376 (372 declared + 4; the old floor of 367 was 5 loose)
- test-tf-redact-random-ids.sh MIN_ASSERTIONS: 331 (327 + 4)
- apply-web-platform-infra.yml: 488525 bytes (< 490000)

## Pre-push gates run locally

fixture-relative-assert 63/63, lint-shell-capture-exit (baseline), lint-trap-tempfile-ownership, grep-q-pipe-guard, lint-window-closure-assertion, lint-shell-trace-credential-refusal --changed, lint-encryption-posture (random_bytes added to non_store_types), lint-guard-contract (plan), terraform fmt -recursive and validate, guard-vacuity-floor 32/32, test-all-corpus-weight-budget 14/14, regenerate-shard-manifest (no row change; only the timestamp header, reverted), test-affected-kb-consumers (baseline unchanged), shellcheck -S warning on the two edited shell sources it can reach.

## Open pre-merge precondition (Phase 3.8)

No scheduled drift run exists yet after the 14:40Z serve flip (latest at 06:01Z). The 18:00Z run or later must show no pool change before this merges; read-only check.

## Post-review rework (review of bb10ba32d8)

- The wrapper no longer uses mktemp (the tempfile census ratchet only moves down: 36 stays 36). The normalised copy is written beside the plan file under umask 077 in a subshell, an existing path or symlink is refused, and it is removed on every normal return path.
- One jq read yields a verdict token (absent | ambiguous | update | plain-noop | unplain-noop | other) with null-safe addresses; every refusal prints an `::error::` line.
- New fixtures: pn11 (module-addressed no-op pool), pn12 (two pool entries, ambiguous verdict), pn13 (read verb), pn14 (deposed), pn15 (importing), the existing-path and symlink refusals; pn8/pn9 reworked to observe the sibling copy. Gate suite floor 133.
- Mutation re-drive on a /var/tmp copy (control green first, every mutation asserted to land): exact-address term, deposed term, importing term, previous_address term, default arm falling through, ambiguous collapsed to absent, copy leaked, existing path not refused, symlink not refused: 9 of 9 RED for the named reason.
- lb-weight-gate: F8 now requires the literal inside the `terraform plan` continuation chain and counts occurrences (two more in-suite mutants: literal moved to an echo before the plan, a second `-var=1`); F6 counts occurrences; V2 requires exactly one top-level `default`; MIN_CASES 287.
- Parity: T3 also asserts no other .tf file references the pair; T4 is a nine-clause table (both pair members, every shape clause, an output); TEST_FLOOR stays 376 (same four rows).

## Fix round 1 (review of 83001323b6; four report-only seats, no P1)

- Wrapper: the normalised copy is opened exclusively (`dd conv=excl`, atomic: an existing path or a symlink fails the write), written beside the plan, no redirect and no mktemp (ratchets unchanged).
- Tests: pn8/pn9 pin WHERE the copy is built; pn9b plants non-empty content and pins the refusal text; unwritable plan directory row (non-root); single count-indexed pool (pn11b); per-arm `::error::` pins; null-address entry; post-replace address-change flow admitted by drain and serve, repoint bound still bites (pn16a-c); census gets a positive control and a definition-anchored leg. Gate floor 141.
- lb-weight-gate: F8 anchors on the terraform-plan COMMAND (exactly one, literal before the first pipe) with four more mutants (post-pipe literal, echo decoy, second plan, same-line duplicate); F6 and V2 became functions with their own same-line / heredoc / duplicate-default / commented mutants. MIN_CASES 295.
- Parity: stray-reference exemption narrowed to plain-string descriptions, with bite/quiet control rows; the key is referenced exactly once in its own file; a local forward from the file itself is a mutant. TEST_FLOOR 376 unchanged.
- Mutation re-drive on a /var/tmp copy, control green first, every mutation landed: write-failure arm approves, exact-address weakened to startswith, copy built elsewhere, exclusive open dropped, unplain-noop and default-arm `::error::` silenced: 6 of 6 RED for the named reason.
- Docs: web-host-replace says drain, wait for healthy, then serve (serve's health precondition refuses while the stale origin is unhealthy), in the same session as the replace; the pre-step no longer cites a wrong ADR and distinguishes an accidental from an intended drain; variables.tf wording; plan Phase 4.3/AC-14 use the end-anchored log line on the right matrix leg or a relative check; stale mktemp text marked superseded.
- Deferred to PR A (comment on #12289): absent-key startup failure with Sentry mirror, names-only presence read in A's preflight, scrub-list entry, rotation counter in the destroy guard, rolling-deploy mixed-version window.
