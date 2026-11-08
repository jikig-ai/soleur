# Tasks: Persist web-2's LB weight (default 1) and mint PROXY_HELLO_HMAC_KEY (#12363)

Plan: `knowledge-base/project/plans/2026-11-08-chore-web2-lb-weight-default-and-proxy-hello-key-mint-plan.md`
Lane: cross-domain · Threshold: aggregate pattern · Rulings: `decision-challenges.md` (8 rows, all CTO)
Owner-gated, never run by an agent: the merge, any workflow dispatch, any Doppler write, flip.sh.

## Phase 0 — Baseline and safety

- [ ] 0.1 Confirm worktree and clean tree
- [ ] 0.2 Record baselines: cf-lb-overlay-gate suite (110), lb-weight-gate suite (282), parity `test(` count (372), apply workflow bytes (488411), encryption-posture lint, c4-count-parity
- [ ] 0.3 Offline init of the web-platform root (`-backend=false`) for later validate and fmt checks

## Phase 1 — Commit 1: persist the weight (flip), tests first

- [ ] 1.1 RED: `tests/scripts/test-cf-lb-overlay-gate.sh` fixtures pn1-pn10 (serve everything-no-op {1,1} and no-op+policy pass; no-op {1,0}, web-1 weight 0, pool absent with distinct message, replace verb refuse; drain lone no-op refuses; no leaked temp copy incl. refuse path with a mktemp shim; exact normalization predicate; pu15 retained); defect fixtures carry POLICY_CREATE so they are RED today
  - [ ] 1.1.1 RED: `lb-weight-gate.test.sh` V2 default=1, F6 two-line census, F8 (ga_overlay literal 0, own `GAO_JOB`/`GAO_PLAN` extractor) with two mutants, C.3 wording (no F9, no prose census)
  - [ ] 1.1.2 Keep the RED output as evidence
- [ ] 1.2 GREEN: rename the grader body to `_cf_lb_gate_ga_pool_update_graded` unchanged; thin `cf_lb_gate_ga_pool_update` wrapper: assert_readable/classifiable first; serve counts pool entries in RAW `.resource_changes[]`; three-way `case` whose default arm refuses (zero or several entries refuse); `["update"]` goes to the inner grader; an exact-address, no-`previous_address`/`importing`/`deposed` `["no-op"]` entry is normalized in a `{resource_changes}`-only `umask 077` mktemp copy, graded, copy removed, rc returned explicitly; notice printed first; drain passes straight through; header rewrite
- [ ] 1.3 Set the `checks` floor in `test-cf-lb-overlay-gate.sh` to the measured value (measured value; cross-check 110 + 14 = 124)
- [ ] 1.4 `variables.tf` default 1 + comment (L555-561) + description + L181 comment; `cloudflare-lb.tf` comments only (L10-13, L48, L70, L87-95; leave the live `description =` at L160); `cf-lb-overlay.yml` ga_overlay `-var="web2_lb_weight=0"` + comment rewrites (L25, L55 dispatch-input description, L706, L879, pin step); record the before/after sweep grep in the work log
- [ ] 1.5 Re-run all suites green; confirm RED rows flipped for the right reason
- [ ] 1.6 Reword C.3 comments (static anti-pooling guard now means literal 0 or the gated variable)
- [ ] 1.7 Rewrite runbook `cf-lb-a-record-gaplessness-verify.md` (arm list, relay-evidence section, "After the serve" incl. the untargeted-apply `-var=web2_lb_weight=0` MUST and non-durable drain, L424, rule sentence); same MUST in `fresh-host-bootstrap-recovery.md` step 3
- [ ] 1.8 ADR-068 `## Addendum — 2026-11-08 (#12363)` at the end of the file, rejected option in the body (via soleur:architecture)
- [ ] 1.9 model.c4 `cloudflare` phrase (L448) only, regenerate model.likec4.json, run C4 tests and c4-count-parity
- [ ] 1.10 Commit 1; set `MIN_CASES` to the measured value (measured value; cross-check 282 + 3 = 285) before committing

## Phase 2 — Commit 2: mint PROXY_HELLO_HMAC_KEY, tests first

- [ ] 2.1 RED: parity tests T1-T4 (count gate, plan membership, slim shape and no-output pin, two-mutant battery); one redactor fixture for the counted `random_bytes.proxy_hello_hmac[0]` plan block (first confirm the redactor accepts a counted address)
- [ ] 2.2 GREEN: `apps/web-platform/infra/proxy-hello-hmac.tf` (random_bytes length 32, masked doppler_secret in soleur/prd, count-gated); re-prove `hex` sensitive on the locked provider schema
- [ ] 2.3 GREEN: two `-target` lines after `proxy_tls_cert` in `apply-web-platform-infra.yml`; `host_proxy_tls_enabled` description; sweep destroy-guard, parity and redaction census; re-measure bytes (< 490000)
- [ ] 2.4 Set `TEST_FLOOR` to the measured value (measured value; cross-check 372 + 4 = 376)
- [ ] 2.5 Commit 2

## Phase 3 — Verification (local, read-only)

- [ ] 3.1 Run all touched suites
- [ ] 3.2 Pre-push gates: fixture-relative-assert, lint-shell-capture-exit --baseline, lint-trap-tempfile-ownership, grep-q-pipe-guard, lint-window-closure-assertion (allowlist), lint-shell-trace-credential-refusal --changed, shellcheck -S warning, terraform fmt -check and validate, guard-vacuity-floor, test-all-corpus-weight-budget, lint-encryption-posture, lint-guard-contract
- [ ] 3.3 `regenerate-shard-manifest.py --incremental --write` produces no tsv diff (no new suite)
- [ ] 3.4 kb-consumers baseline decision: no change; ratchet green, baseline unchanged
- [ ] 3.5 Sandbox mutation run (`bash scripts/soleur-sandbox.sh new` / `rm`): control green first, every Guard 1-3 row LANDS and goes RED
- [ ] 3.6 Record path-filter evidence (release push arm fires; accepted)
- [ ] 3.7 Record evidence that nothing else plans the pool (incl. `web_lb_health` greps and the read-only `WEB2_LB_WEIGHT` absence check in `prd_terraform`)
- [ ] 3.8 Pre-merge precondition: the first drift run after the 14:40Z serve flip shows no pool change (read-only)

## Phase 4 — PR body, follow-ups, post-merge

- [ ] 4.1 PR body: `Closes #12363` only; `Ref` the rest; squash and revert-rule note; release-arm finding; generator note; expected plan comment (two additions, no pool change)
- [ ] 4.2 File two follow-up issues (release-filter audit; stale C4 and L160 attribute wording incl. model.c4 L351/L355/L926); post PR A rollout compatibility, the previous-key mechanism and two preconditions (Sentry scrub-list entry for the new key; the presence read) as a comment on #12289
- [ ] 4.3 Post-merge read-only verification via soleur:postmerge (apply run matched by address, first drift run, names-only prd presence read)
- [ ] 4.4 Hold: the merge is operator-reserved (see plan `## Operator Holds`)
