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
