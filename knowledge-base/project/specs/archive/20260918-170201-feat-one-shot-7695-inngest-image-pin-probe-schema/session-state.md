# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-07-fix-inngest-bootstrap-pin-and-guard-hardening-plan.md
- Status: complete (revised in place from the inherited 1209-line draft; deepen-plan run constrained)
- Plan artifact: complete (selector=branch)
- Worktree reused per operator brief; rebased onto 0ae1a39d2, 0 behind main.

### Errors

- deepen-plan did not run in the first planning turn (two plan reviews consumed it); run in the second turn, constrained to thin sections with explicit no-refanout.
- Phase 4 boundary-derivation shipped pre-review in the first turn; rewritten in the second.
- AC12 shipped incoherent in the first turn (asserted a merits verdict impossible at merge by construction); corrected to expect a `boundary_underivable` token.
- Length regressed 1209 -> 1255 lines against the "substantially shorter" instruction. Scope cut is large (six workstreams removed) but correctness material outgrew prose trimming. Instruction not met; recorded rather than reframed.

### Decisions

- #7761 premise INVERTED and corrected: its fix merged in PR #7768 (2026-09-03, closes=[] prose ref); the pin was set 2026-08-20, two weeks earlier. Re-pinning is the remediation, not a new exposure. Measured live: 4,204 inngest-cutover-flip rows in 48h, ZERO carrying the `guard` field -> production scheduler is running pre-fix code.
- Guard A redesigned hermetic and git-only (`git show <pinned tag>:<path>` vs HEAD over the cp-derived carrier set). Resolves BOTH P0s at once: no crane in deploy-script-tests, and authorship-before-consumption by construction.
- Guard B's live arm moved off PR-gating CI to the apply path (which already holds GHCR credentials), following the repo's own zot-image-staleness.test.sh NO-NETWORK-BY-DESIGN precedent.
- Phase 4 resolved by PROVENANCE, not override: supplied boundary keeps the committed header's FAIL arm verbatim; derived boundary is capped PASS-or-TRANSIENT. T6 is the control proving the split is by provenance, not a weakened rule.
- Digest-only substring matching is mandatory: the live host reports a zot-prefixed image_ref while the pin literal is GHCR, so whole-ref comparison would be a permanent silent no-op.
- Gate 4.55 (new): editing cloud-init-inngest.yml ARMS a force-replace of hcloud_server.inngest (no ignore_changes on user_data). Merging does not fire it (`target=hcloud_server` count 0 in the apply workflow). That armed replace IS the Step 2 delivery vehicle.
- Semver-max drift check KEPT (reverses the prior draft's R14; its claimed permanent-red window on main does not exist).

### Components Invoked

- Skill: soleur:plan, Skill: soleur:deepen-plan
- Agent: general-purpose x2; code-simplicity-reviewer; architecture-strategist
- scripts/betterstack-query.sh (control-paired queries throughout)
- scripts/lint-guard-contract.py, scripts/lint-infra-no-human-steps.py (both green)
- apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh (baseline 129/129)

## Preflight measured by pipeline runner (pre-work)

- Live probe row: no `probe_schema` AND no `redis_keys` field; image_ref v1.1.25@sha256:f23a2a0d...;
  server_active=inactive, redis_active=active, uptime_s=1620603, cutover_flag=aborted, instance_id=hetzner-162809678.

- probe_schema=3 (Merge A #7778 / 000fa4715) ALREADY emits redis_keys via INFO keyspace summed across all dbs
  (deliberately not DBSIZE, which reads db0 only while FLUSHALL spans all). No extra emitter work needed.

- INNGEST_REDIS_PASSWORD present in soleur-inngest/prd -> the cloud-init:1009 fail-closed
  `redis_keys=__UNREADABLE__` trap will NOT fire on replace. INNGEST_REDIS_LUKS_KEY present (Step 4).

- inngest-cutover environment required reviewers = [deruelle] (NON-EMPTY; no auto-approve).
- No secret name in soleur-inngest/prd collides with a CUTOVER_* fixture seam -> #7761 latent, not active.
- ci.yml on main last 3 runs 2332s/2143s/2438s (under the 3000s await-ci ceiling; today's peak 3366s).

## Review + QA Phase (2026-09-07)

- Panel: 7 agents, report-only (>3 concurrent share one worktree, so the lead owned every edit).
  Substituted observability-coverage-reviewer and a structural-enumeration seat for
  agent-native-reviewer and performance-oracle — no user-facing surface, no economics claim.
- Deterministic gates ran FIRST per the guard-shaped-PR rule: shellcheck (2 hits, both mine, both
  mutation-verified load-bearing), validate-infra-templates (caught a render break I introduced),
  semgrep deliberately skipped (vacuous on a bash-only diff).

### Findings — all fixed inline, none filed (NET 0 issues)

- P0 the probe could never PASS: EXPECTED_FLAG was `rolled-back`, live flag is `aborted`.
- P0 no assert() dispatcher self-test: `if eval` -> `if true` gave 163/163 with real defects.
- P0 no global floor: deleting the Guard A block reported 149/149 OK.
- P1 `armed` was capped on the only channel CI has (the sweeper provisions no Doppler token).
- P1 Guard D blind to `cat <<A > f`, `{ cat <<B; } > f`, `tee f <<C`, trailing-comment forms.
- P1 exemption scoped by NAME not SITE; body read only at the first occurrence.
- P1 a tag pinned to another tag's bytes passed 161/161; the comment I wrote claimed otherwise.
- P1 five false claims in prose (exposure window, Guard B's binding, an unbuilt apply-path arm,
  two ADR twins, and the operator-facing Guard 2 remediation).
- P2 Guard A ran bare `git` (process CWD) where AC6 in the same file uses `git -C "$SCRIPT_DIR"`.

### Verification state at ship

- bootstrap 163/163, inngest 305/305, follow-through 53/53, zot-pull 9/9 killed, dark-gate 115/115.
- validate-infra-templates rc=0; apply-web-platform-infra.yml YAML parses.
- AC5 re-derived by command: run 34159532201, headSha == the tag's commit, exactly one signing-line
  digest, equal to the pin at all four sites.
- Guard A: 10 carriers, 0 drifted at vinngest-v1.1.26 after 10 further commits.
- `scripts` TEST_GROUP shard NOT run as a shard (CAPACITY_CONTENDED throughout). Its only relevance
  is the follow-through suite, run directly and green; no sibling pins the strings this PR changed.
  CI's required `test` context runs it.

### Known, and stated rather than left implicit

- `infra-validation` is NOT a required status check: only the suites' REGISTRATION is
  merge-blocking (via test-infra-suite-registration.sh in the required
  `Bash fixture tests for guard scripts` context). Every red these three guards can produce is
  advisory at PR time today. That is a standing gap, not something this PR introduces.
- The hermetic residual: a digest that is well-formed, agreed across all four sites, and simply
  wrong. Guard B row6 catches the tag-moved-without-digest shape; AC5 is the only control on the
  rest. The apply-path live arm the plan listed was never built, and the plan now says so.
