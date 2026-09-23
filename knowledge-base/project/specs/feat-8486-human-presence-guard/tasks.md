---
feature: feat-8486-human-presence-guard
plan: knowledge-base/project/plans/2026-09-23-feat-human-presence-guard-operator-scripts-plan.md
issue: 8486
lane: cross-domain
---

# Tasks: human-presence guard for production-mutating operator scripts (step 1 of #8486)

## 0. Setup

- [x] 0.1 Follow-up issues filed at plan time: #8661 (ungated local production writers) and #8662
  (existing defer rules' whole-command read-only escape). Link both from the ADR and PR body.
- [ ] 0.2 Re-probe the ADR ordinal (245) and migration ordinal (140) across every `origin/*` ref.
- [ ] 0.3 Run Guard 1's detectors on the live tree and list every hit with its handling before
  freezing the exemption registry.

## 1. Failing tests first

- [ ] 1.1 Create `plugins/soleur/test/fixtures/operator-ack-arms.tsv` (write + readonly rows per
  ack-calling script).
- [ ] 1.2 Create `plugins/soleur/test/operator-ack-guard.test.sh` with Guard 1 (typed-yes census,
  exemption registry with set identity) and Guard 2 (sandbox-PATH behavioral arms, pty via
  `script -qec`, prompt-coverage anchor). Observe RED for the named reasons.
- [ ] 1.3 Extend `.claude/hooks/prod-write-defer-gate.test.sh` with Guard 3 (arm table × invocation
  shapes; segment-scoped escape rows). Observe RED.
- [ ] 1.4 Extend `plugins/soleur/test/operator-script.test.sh` with Guard 4 (Guard 9 arm-table
  fallback, widened `DESTRUCTIVE_RE`, fixture consumer rows).
- [ ] 1.5 Create `apps/web-platform/test/migration-140-flag-flip-audit-approval-method.test.ts`.

## 2. Core implementation

- [ ] 2.1 Contracts first
  - [ ] 2.1.1 Migration `140_flag_flip_audit_approval_method.sql` + `.down.sql` (column + CHECK;
    8-arg RPC with `p_approval_method DEFAULT NULL`; `SECURITY DEFINER SET search_path = public,
    pg_temp`; REVOKE/GRANT). Down order: drop the 8-arg function, recreate the 7-arg one, drop the
    column.
  - [ ] 2.1.2 `plugins/soleur/scripts/audit-flag-flip.sh` sends `p_approval_method: "tty-ack"`;
    update `audit-flag-flip.test.sh`.
  - [ ] 2.1.3 Guard 9 amendment in `operator-script.test.sh` (arm-table fallback; widened regex).
- [ ] 2.2 Flag scripts (`delete.sh`, `create.sh`, `set-role.sh`, `flip.sh`)
  - [ ] 2.2.1 Source the library below the xtrace refusal.
  - [ ] 2.2.2 Early no-TTY precheck right after argv parsing (write mode only).
  - [ ] 2.2.3 Replace typed-yes with `soleur_op_ack_or_die` (distinct prompt per site).
  - [ ] 2.2.4 `flip.sh`: single `gate_or_confirm`; remove `--confirmed`, reject it with exit 2 and an
    "own terminal" message.
  - [ ] 2.2.5 Header exit-code tables (abort 1, no-TTY 64, flip `--confirmed` 2).
  - [ ] 2.2.6 `umask 077` audit of every file each script writes.
- [ ] 2.3 `audit-sentry-extra-text-references.sh`: source library, precheck when `--apply`, ack after
  inventory and before the first PUT (skip on zero matches).
- [ ] 2.4 Migrate `flag-detach-shared.test.sh` and `flag-org-scoping-pr2.test.sh` from `--confirmed`
  to pty-driven `yes`; add a `--confirmed` → exit 2 case.
- [ ] 2.5 Defer-gate rule `prod-write-defer-operator-ack-script`: path suffix matched in any token
  position (bare path, interpreter, `script -qec`/`unbuffer`/`expect` wrappers, `cd … && ./x.sh`),
  reader-verb escape, segment-scoped read-only escape; header and `.claude/hooks/README.md` notes.
- [ ] 2.6 Per-harness `[[ -t 0 ]]` measurement (Claude Code measured; codex/grok/devin, ≤ 6 model
  calls; unrunnable → UNMEASURED).
- [ ] 2.7 ADR-245 (per-harness table, residual risks, step-2 design, `tty-ack` meaning, census and
  tracking issue); amend ADR-236.
- [ ] 2.8 C4: add `flagsmith` element and edges in `model.c4`; include in the `context` view.
- [ ] 2.9 SKILL.md bodies (four skills): `--dry-run`, then print the write command for the
  operator's terminal; remove `--confirmed`; exit-code tables. Runbook `oauth-probe-failure.md`.
- [ ] 2.10 Sweep model-read surfaces for agent-performed writes / `--confirmed`; update
  `components.test.ts` reason strings.
- [ ] 2.11 List open plans that prescribe agent flag writes (PR body; no edits to point-in-time
  plans).
- [ ] 2.12 LIA / Article 30 register: add `approval_method` only if columns are enumerated.

## 3. Testing and verification

- [ ] 3.1 `bash plugins/soleur/test/operator-ack-guard.test.sh`
- [ ] 3.2 `bash plugins/soleur/test/operator-script.test.sh`
- [ ] 3.3 `bash .claude/hooks/prod-write-defer-gate.test.sh`
- [ ] 3.4 `bash plugins/soleur/test/audit-flag-flip.test.sh`, `flag-detach-shared.test.sh`,
  `flag-org-scoping-pr2.test.sh`
- [ ] 3.5 Migration 140 and 071 tests; `invocation-axis.test.ts`; `components.test.ts`
- [ ] 3.6 C4 syntax, render and `plugins/soleur/test/c4-count-parity.test.sh`
- [ ] 3.7 Discoverability probe: `bash plugins/soleur/skills/flag-delete/scripts/delete.sh probe-flag`
  prints `SOLEUR_BOOTSTRAP_INPUT_REQUIRED` and exits 64.
- [ ] 3.8 Full review panel (TR5): security-sentinel, user-impact-reviewer, and the rest; run
  `soleur:gdpr-gate` against the diff.
