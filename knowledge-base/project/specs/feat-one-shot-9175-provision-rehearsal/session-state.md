# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9175-provision-rehearsal/knowledge-base/project/plans/2026-10-08-infra-inngest-provision-forced-race-rehearsal-plan.md
- Status: complete

### Errors
- `iac-plan-write-guard` hook blocked the first plan edit (flagged a `doppler secrets set` pattern in descriptive text); resolved via the gate's documented `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out — the plan routes every write through Terraform/GHA anyway.
- Provisional ADR-278 was already claimed by sibling branch `feat-open-web-egress` — caught by the all-refs ordinal probe; the plan now carries provisional ADR-279.
- Initially cited a nonexistent `data "hcloud_network_subnet"`; corrected to the `network_id`+`ip` attach form with a work-time verify note.
- No Task/Skill tool in subagent harness — deepen-plan's parallel research/review agents could not be spawned; every deepen phase ran inline instead.
- Pre-existing `.mcp.json` modification noted — not touched by this work.

### Decisions
- Two coupled deliverables: (A) parameterize `--config prd` → `${DOPPLER_CONFIG:-prd}`/`inngest_doppler_config` across ~20 sites in `cloud-init-inngest.yml` + image-shipped scripts — the hard blocker, since a scratch Doppler config can never be named `prd`; requires a new `vinngest-v*` mint via existing ADR-232 machinery (delivered dark); (B) the rehearsal harness modeled on `rung2-rehearsal/`.
- Scratch Doppler = a new `doppler_environment` (non-inheriting root config) in project `soleur-inngest`, not a branch config — verified via Doppler docs; flagged rung2's isolation claim for work-time recheck.
- Two-phase apply makes the race deterministic: `nic_attached` gates `hcloud_server_network.rehearsal` onto the real prod subnet (`10.0.1.60`); phase B fires only after >=2 observed failed attempts — the miss is observed, then healed.
- `INNGEST_DIAGNOSTIC_BOOT=true` gives the rehearsal a latch-capable success path with no scratch Postgres and no second-scheduler risk (exemption verified at `cloud-init-inngest.yml:1309–1318`).
- Ships unfired: `Ref #9175` never `Closes`; evidence attaches to the issue post-run; reboot asserted via `SOLEUR_INNGEST_BS_TOKEN_RESTAGED` post-reboot anchor + zero new `provision-attempt-start` for the iid.

### Components Invoked
soleur:plan (inline execution), soleur:deepen-plan (inline; all gates passed: PAT-grep clean, Guard Contract lint green with 5 entries, Scope Check well-formed, Encryption Posture + Observability complete, network-outage + downtime sections emitted with telemetry), cloud-detect.sh (`local`), scripts/lint-guard-contract.py, gh issue/pr view (citation verification), git fetch/ls-tree/for-each-ref (ADR ordinal probe), web_search (Doppler branch-config semantics)

## Work Phase
- Status: implementation complete (Phases 1–4); pre-commit

### Implementation
- Phase 1: all 19 boot-path `--config` sites parameterized (`${inngest_doppler_config}` in the template; `@@DOPPLER_CONFIG@@` sentinel in emitted units; `${DOPPLER_CONFIG:-prd}`/`${DOPPLER_CONFIG}` in committed units+scripts); `DOPPLER_CONFIG` written to both env files + provision-unit env thread; `--only-secrets DOPPLER_CONFIG` added to both cutover units; census arm in inngest.test.sh pins exactly 19 sites + allowed forms.
- Phase 2: `apps/web-platform/infra/inngest-provision-rehearsal/` (main/variables/rehearsal.tf + committed lockfile); non-inheriting `doppler_environment.rehearsal` on soleur-inngest; two-phase `nic_attached` gate; `scripts/inngest-provision-plan-shape.sh` + 23-case mutation test.
- Phase 3: `inngest-provision-rehearsal.yml` (dispatch-only, two jobs, reviewer env on rehearse + infra-privileged on teardown); `inngest-provision-rehearsal-capture.sh` + 23-arm test (TRANSIENT=absence, FAIL=violation); probe; 63-assertion sentinel suite; apply-workflow exclusion; drift-sweep job; infra-validation path entries; test-all.sh registrations.
- Phase 4: runbook + ADR-279 (all-refs probe re-run immediately before writing: 278 confirmed claimed) + model.c4 edge prose + inngest-server.md paragraph + tasks.md.

### Verdict-semantics decision (capture script)
FAIL is reserved for VIOLATIONS (a forbidden row exists — bootstrap-done pre-NIC, provision rows post-reboot); absent required markers report TRANSIENT so the poll loop owns the terminal verdict at its deadline. A FAIL for "not yet" would burn a paid host on a timing accident.

### Verification
- Green: inngest.test.sh 419/419; inngest-provision-rehearsal.test.sh 63/63; capture test 23/23; plan-shape test 23/23 (4 mutants); provision-unit 161 asserts + 83 mutation rows; doppler-injection-bound 33/33; boot-emitter 95/95; cutover-flip 178/178; luks-cutover 97/97; host 87/87; nic-wait 400/400; redis-luks 57/57 + 46/46; tier-census 296/296; workflow-errexit 38/38; orphan-test-suites 638 covered/0; suite-registration 174; diagnosis-claims 24/24; kb-consumers 22/22; dual-lockfile 18/18.
- Known non-blocking: GuardA carrier drift (post-merge mint/pin-bump tripwire by design, advisory job); run-registered-suites.test.sh fails identically on main (pre-existing).

### Post-merge gates (not this branch's work)
- vinngest-v* mint + pin bump (parameterization must reach the image before any dispatch).
- Re-probe ADR ordinal before merge; dry_run dispatch; real dispatch; attach evidence to #9175.
