# Tasks: agent-runnable operator bootstrap with a harness-approved human acknowledgement

Plan: `knowledge-base/project/plans/2026-10-01-feat-agent-runnable-operator-bootstrap-plan.md`
Issue: #9321 (this PR uses `Ref #9321`, never `Closes`).

Standing constraints: no production write by the pipeline (never run the real bootstrap, never apply, never mint
or store a token, never read a real secret); stubs on a scratch PATH only; do not merge, do not queue auto-merge;
CI is the test gate; no closed issue number in `#N` form; GHCR retirement and the legal cluster are untouched.

## 0. W0 probes (STOP gate)

- 0.1 Run the five CTO probes (ask + updatedInput prompt display, ask under bypass and allow rules, defer + resume marker, interactive-vs-headless discriminator, nonce non-leak) per `DEFER-DECISION-PAYLOAD-SHAPE.md`; cite `UPDATED-INPUT-PAYLOAD-SHAPE.md`.
- 0.2 Record measurements and the Claude Code version. Probe 1, 2 or 4 failing: STOP and report.
- 0.3 Verify hook-file and settings edit guards cover `.claude/hooks` and `plugins/soleur/hooks`; decide the Devin binding.

## 1. Tests first (RED)

- 1.1 `plugins/soleur/test/operator-agent-runnable.test.sh` (Guard 1) and fixtures (v2 template-shaped, non-canonical `case`-table, legacy v1-shaped).
- 1.2 `plugins/soleur/test/operator-stage-approval-hook.test.sh` (Guard 3).
- 1.3 Guard 11 in `plugins/soleur/test/operator-script.test.sh` (Guard 2, known-answer digest vectors via python3 hashlib).
- 1.4 Run the shard-parity reproduction harness.

## 2. Library

- 2.1 `plugins/soleur/scripts/lib/operator-approval.sh` (digest, directory, record validation, `algo=1`; portable `stat`; no shell options).
- 2.2 `operator-script.sh`: `plan_emit`, `soleur_op_stage_gate`, stage-ok marker, ledger fields, exit 75 and marker tables, wording.
- 2.3 Keep `soleur_op_ack_or_die` unchanged.

## 3. Hook (registered last)

- 3.1 `plugins/soleur/hooks/operator-stage-approval.sh` (prefilter, v2 fingerprint by static read, single simple command, nonce before `bash`, ask/defer/deny, no execution of the script).
- 3.2 `agent-env.ts` web opt-out variable and test.
- 3.3 ADR-162 amendment and `hookeventname-coverage.test.sh` allowlist.
- 3.4 After 1.2 is green: register in `hooks.json` (anchored matchers) and add `devin-dispositions.tsv` rows.

## 4. Template and skill

- 4.1 `template.sh` v2 (stage lines, `--list` above library resolution, `--stage`, `--apply`, `--plan-digest`, `--rotate-token`, `declare -F` capability assert).
- 4.2 `operator-bootstrap/SKILL.md` (contract, agent protocol, exit/marker/wording table, plain residual).

## 5. Re-cut the 9321 script

- 5.1 Five stages (preflight, copy-app-values, prove-live-app, mint-and-store-token, verify) with plan/apply pairs, preconditions, vendor-derived READY, orphan-token marker.
- 5.2 Keep G7d traps and every safety property; run census and the credential linter.
- 5.3 Update runbook step 3 and Rotation. 5.4 Stub-binary runs only.

## 6. Workflow, skills, rules

- 6.1 ship Phase 5.5 option 4 and headless abort text (attended-only `auto_command:`).
- 6.2 Shorten the two AGENTS.rules.md rules; run the budget lint.
- 6.3 Terminal-only sweep and the four flag skills plus go.md wording.
- 6.4 Defer-gate rule 4 comment and hooks README cross-reference.

## 7. Guards, ADR, C4, learning

- 7.1 Generalize Guards 4 and 9 for `soleur_op_stage_gate`; relevance map entries; shard harness.
- 7.2 ADR-262 plus blockquotes on ADR-228 and ADR-249; C4 edges (`founder -> doppler`, `founder -> github`), Hook Engine and plugin descriptions; run C4 tests.
- 7.3 Learning file.

## 8. Deferral issues and PR

- 8.1 File four follow-ups with milestone and roadmap listing before merge.
- 8.2 PR body (`Ref #9321`, plain residual, W0 measurements, files not touched); CI green; mark ready; do not merge.
