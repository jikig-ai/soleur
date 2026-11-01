# Tasks: cf-token-scope default-token profile (epic #11181)

Plan: `knowledge-base/project/plans/2026-10-28-feat-cf-token-scope-default-token-profile-plan.md`

## Phase 1: Tests, RED-first (cq-write-failing-tests-before)

- [x] 1.1 `plugins/soleur/test/cf-token-scope.test.sh` — mock `doppler`: add `CF_API_TOKEN) printf '%s' "${MOCK_API_TOKEN-default-token-xyz789}" ;;` arm (synthesized value only, `cq-test-fixtures-synthesized-only`).
- [x] 1.2 Mock `curl` — add URL-substring arms BEFORE the catch-all, in this order: `*cfd_tunnel*` (`MOCK_TUNNEL`), `*access/apps*` (`MOCK_ACCESS`), `*dns_records*` (`MOCK_DNS`), `*notification_policies*` (`MOCK_NOTIF`), `*load_balancers/pools*` (`MOCK_LB_POOLS`), `*load_balancers*` (`MOCK_LB_ZONE`) — pools BEFORE zone-LB (superstring collision); defaults `200:{"success":true,"result":[]}` (array shape). Existing arms byte-identical.
- [x] 1.3 RED-by-construction pin: run the suite against the UNMODIFIED script; record the failure set (D0 documented; D1–D12 + D-doc fail; C1–C14 pass). Evidence line for the PR work log.
- [x] 1.4 Add D1/D1b/D10/D11: dry-run per-profile (rc 0; `doppler secrets get CF_API_TOKEN` literal; all six URLs; `"$TOK"` unexpanded; private-fd form present; `CF_API_TOKEN_RULESETS` forbidden in the default-token run; rulesets dry-run unchanged; parameterized table-size row count).
- [x] 1.5 Add D2–D5 baseline: both LB rows `not-yet-widened (403` per-row assertions + `NOTE:` line + rc 0 + `PASS: no scope dropped`; D3 retained 403 ⇒ rc 3; D4 degraded-200 and wrong-shape ⇒ rc 3; D5 LB 404 ⇒ rc 3.
- [x] 1.6 Add D6–D8 assert mode: `--expect-lb-scopes` with 403 ⇒ rc 3 + `FAIL: LB scope still absent`, lacks `PASS: LB scopes present`; with both authorized ⇒ rc 0 + present line; half-green ⇒ rc 3 (per-row gating).
- [x] 1.7 Add D9 + D-mint usage errors: unknown profile; `default-token`+`--target-entrypoint`; `rulesets`+`--expect-lb-scopes`; `--profile` with no value — all rc 2, before any secret read; empty `MOCK_API_TOKEN` ⇒ rc 2 naming `CF_API_TOKEN`.
- [x] 1.8 Add D12 read-only source guards (no `-X POST|PUT|PATCH|DELETE` in SUT; no Doppler verb other than `secrets get`) and D-doc SKILL.md/playbook grep pins (`--profile default-token`, `--expect-lb-scopes`, `not-yet-widened`, `profiles only`).
- [x] 1.9 Keep C1–C14 verbatim (D13 = back-compat pin); `bash -n` the test file; run — confirm RED exactly where expected.

## Phase 2: Script (`plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh`)

- [x] 2.1 Profile table: `PROFILES=(rulesets default-token)` + `profile_token_secret()` case; `TOKEN_SECRET` (line 64 constant) becomes profile-resolved; `DOPPLER_PROJECT`/`DOPPLER_CONFIG`/`ZONE_SECRET`/`ACCT_SECRET` shared (config-difference is a future table row, not a flag).
- [x] 2.2 argv: `--profile <name>` (validate ∈ `PROFILES` else usage+exit 2), `--expect-lb-scopes`; post-parse cross-validation gate BEFORE the dry-run block (mispaired flags print nothing).
- [x] 2.3 Generalize `check()` second arg to `want_type` (`object|array`); rulesets call sites pass exactly their scheme-mapped types (zone→object, account→array); trusted-404 conjunction (`trust404=1` + `ZONE_CONTROL_OK`) otherwise untouched.
- [x] 2.4 `default-token` retained loop over rows D0–D3 (`trust404=0` all), header line names the resolved secret; retained verdicts unchanged.
- [x] 2.5 `classify_target()` per plan pseudocode — the ONLY neutrality site; `LB_OK`/`LB_NOTED`/`LB_MISSING` counters; err-code suffix via `jq -r '.errors[0].code // empty'` on the captured 403 body.
- [x] 2.6 Summary lines: `NOTE:` (stdout, baseline-only), `PASS: LB scopes present —` (stdout, assert-green), `FAIL: LB scope still absent —` (stderr, assert-red) + final exit codes per the plan's exit-code contract table. <!-- Superseded 2026-10-28 (advisor consult, disposition 1): the assert-red verdict emits on STDOUT (the #7797 data channel), not stderr; shipped shape follows the addendum, pinned by D6 via run_out. -->
- [x] 2.7 `--dry-run` branch prints the selected profile's rows from the same table (print/run parity); recipes carry `--disable --noproxy '*'` and `-H @<(printf 'Authorization: Bearer %s' \"$TOK\")` forms verbatim (#7873/#6892 posture).
- [x] 2.8 `usage()`/`-h` text updated (profile flag, both flags, exit-code states); xtrace guard, env `unset` block, `cleanup()` trap unchanged; `bash -n` + shellcheck clean.
- [x] 2.9 Run the suite → D-series GREEN with C-series still GREEN; no real Doppler/CF call occurred (mock PATH held).

## Phase 3: Docs

- [x] 3.1 `SKILL.md` §Usage: default-token example lines (baseline + `--expect-lb-scopes`), profile table doc, posture re-word — **profiles only, no raw token-var knob** (replaces the §Usage hardcoding paragraph; the refusal rationale keeps its first sentence).
- [x] 3.2 `SKILL.md` §Probe-set contract: append the `default-token` table (D0–D3 retained / L0–L1 target) + expected-missing/assert semantics; three-layer classifier text unchanged (profile-independent).
- [x] 3.3 `SKILL.md` §Exit codes: extend 0/2/3 rows with the target-class states (no new numeric codes).
- [x] 3.4 `SKILL.md` §Execution: default-token variant of the 3-step widen flow (baseline → operator-typed widen → assert run green); §Sharp Edges: LB probes attest read-not-`Edit`; `not-yet-widened` is neutral only in baseline; ledger follow-on wording (description edit lands in the PR that consummates the widen).
- [x] 3.5 `references/widen-playbook.md` §After the widen: pointer lines — for the `CF_API_TOKEN` widen, step 1 = `cf-token-scope.sh --profile default-token --expect-lb-scopes`; permissions to append: Zone `soleur.ai` → `Load Balancers: Edit` AND Account → `Load Balancing: Monitors and Pools: Edit` (append, never rebuild; Edit not Read).
- [x] 3.6 SKILL.md frontmatter `description:` UNCHANGED; compliance greps green (no bare-backtick refs; third-person description intact); do NOT touch `plugins/soleur/cursor/skills/soleur-cf-token-scope/SKILL.md` (CI-managed mirror).

## Phase 4: Verification & artifacts

- [x] 4.1 `timeout 120 bash plugins/soleur/test/cf-token-scope.test.sh` → `0 failed`, rc 0.
- [x] 4.2 `python3 scripts/lint-guard-contract.py <plan>` → rc 0 (green at plan time; re-verify post-edit); `python3 scripts/lint-infra-no-human-steps.py` over changed KB artifacts → rc 0.
- [x] 4.3 Credential-hygiene spot checks: `--profile default-token --dry-run` under a PATH without curl/doppler → rc 0, no secret-looking literals in combined output; xtrace refusal still exit 78.
- [x] 4.4 Diff census (AC11): changed paths ⊆ {`plugins/soleur/skills/cf-token-scope/**`, `plugins/soleur/test/cf-token-scope.test.sh`, `knowledge-base/project/{plans,specs}/**`}; zero hunks under `apps/web-platform/infra/` or `plugins/soleur/cursor/`.
- [x] 4.5 `bun test plugins/soleur/test/components.test.ts` → skill-description budget green (no description edit expected; verify, don't assume).
- [x] 4.6 CI registration: confirm the suite auto-runs via `scripts/test-all.sh` glob `plugins/soleur/test/*.test.sh` (no runner edit; `bash scripts/test-all.sh --print-suite-globs` receipt).
- [x] 4.7 `ship`: PR body `## Changelog` section; semver label decision at ship (new flag surface inside an existing skill — lean `semver:minor` per "new capabilities", ship owns it); `Closes:` none — the PR references #11181 without closing the epic.

## Follow-on tasks (NOT in this PR — tracked here so they are not invisible)

- [x] F1 After the operator widen LANDS: append the two LB permissions to the `cf_api_token` description in `apps/web-platform/infra/variables.tf` (ADR-130 scope-ledger rule; "records only what is true" per the operator-answer comment) — in the PR that consumes the widen, per the ruling. **Done 2026-10-30:** ledger line updated + `## Amendment (#11181)` appended to ADR-130 pinning the retained-scope re-check to the `default-token` profile (decision-challenges D5).
- [x] F2 Operator-typed widen execution (standing operator-reserved hold on #11181): baseline `--profile default-token` → Playwright dashboard widen (widen-playbook) → `--profile default-token --expect-lb-scopes` green + `/user/tokens/verify` active. **Done 2026-10-30:** widen executed on `soleur-terraform-tunnel` (token `62702ea2…`, owned by member `ops@jikigai.com` — the earlier OpenCode attempt was under the wrong login and never reached an edit; zero `token_update` events in the account audit trail) — appended account `Load Balancing: Monitors and Pools:Edit` + zone `Load Balancers:Edit`, Update-token commit confirmed by the dashboard (`Modified: 2s ago`), assert run rc 0 with both LB rows 403→200, `/user/tokens/verify` still `active`.
- [x] F3 Part-2 staging convert + GA overlay — **Done 2026-10-31:** `cf-lb-overlay.yml` dispatched staging-record → staging-overlay → staging-teardown → ga-overlay, each under fresh named operator authorization. Staging continuity measured **GO**: 174/174 samples = HTTP 200 across the apply transition (~85s window incl. ~73s post-apply on `lb-staging.soleur.ai`); the `VERDICT=NO-GO` token was a sample-floor calibration false negative (filed #11749). GA trio applied on `app.soleur.ai` (post-apply continuity check green; endpoint serving 200 through the LB). Two live fixes were needed en route: #11693 (Flexible-SSL rule widened to the throwaway host — origin is HTTP:80-only) and #11739 (ga-overlay `-target` flags were eaten by a misplaced redactor pipe).
- [x] F4 Parent session: run the plan Step 4.5 advisor consult and rule the `pending - assumed` rows D1–D7 in `decision-challenges.md`. **Done:** both halves landed 2026-10-28 in the planning session and were verified 2026-10-30 — CTO batch spawn ruled all D1–D7 (rulings transcribed from epic #11181 comment 6464031261; `decision-challenges.md` shows every row `Ruled by CTO agent`), and the Step 4.5 advisor consult ran as one bounded spawn (architecture-strategist, tier-degraded + `Reviewed-Coverage: sequential-fallback` disclosed) producing zero TECHNICAL findings and 19 TASTE/PROCESS dispositions recorded as the binding `## Advisor Consult Dispositions` addendum in the archived plan; technical-ruling-gate re-run passed on 9 rows.
