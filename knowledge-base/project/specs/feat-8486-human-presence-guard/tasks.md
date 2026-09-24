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
- [x] 0.2 Re-probe the ADR ordinal (245) and migration ordinal (140) across every `origin/*` ref.
- [x] 0.3 Run Guard 1's detectors on the live tree and list every hit with its handling before
  freezing the exemption registry.

## 1. Failing tests first

- [x] 1.1 Create `plugins/soleur/test/fixtures/operator-ack-arms.tsv` (write + readonly rows per
  ack-calling script).
- [x] 1.2 Create `plugins/soleur/test/operator-ack-guard.test.sh` with Guard 1 (typed-yes census,
  exemption registry with set identity) and Guard 2 (sandbox-PATH behavioral arms, pty via
  `script -qec`, prompt-coverage anchor). Pty-`yes` runs of `create.sh`/`delete.sh` execute against
  a scratch copy of `server.ts`, `.env.example` and `flip.sh` (delete.sh rewrites its
  `FLAG_ENV_VARS` map); assert the real worktree's `git status --porcelain` is unchanged and file
  modes are preserved. Observe RED for the named reasons.
- [x] 1.3 Extend `.claude/hooks/prod-write-defer-gate.test.sh` with Guard 3 (arm table × invocation
  shapes; segment-scoped escape rows). Observe RED.
- [x] 1.4 Extend `plugins/soleur/test/operator-script.test.sh` with Guard 4 (Guard 9 arm-table
  fallback, widened `DESTRUCTIVE_RE`, fixture consumer rows).
- [x] 1.5 Create `apps/web-platform/test/migration-140-flag-flip-audit-approval-method.test.ts`.

## 2. Core implementation

- [x] 2.1 Contracts first
  - [x] 2.1.1 Migration `140_flag_flip_audit_approval_method.sql` + `.down.sql` (column + CHECK;
    8-arg RPC with `p_approval_method DEFAULT NULL`; `SECURITY DEFINER SET search_path = public,
    pg_temp`; REVOKE/GRANT). Down order: drop the 8-arg function, recreate the 7-arg one, drop the
    column.
  - [x] 2.1.2 `operator-script.sh`: `soleur_op_ack_or_die` sets non-exported
    `SOLEUR_OP_ACKED=tty-ack` after `yes`; `unset SOLEUR_OP_ACKED` at load; re-run Guard 4
    (`g4_class2_body_ok`). `audit-flag-flip.sh` sends `p_approval_method: "tty-ack"` only when it is
    set, else returns 4; update `audit-flag-flip.test.sh`. Migration up order: drop 7-arg, plain
    `CREATE FUNCTION` 8-arg.
  - [x] 2.1.3 Guard 9 amendment in `operator-script.test.sh` (arm-table fallback; widened regex).
- [x] 2.2 Flag scripts (`delete.sh`, `create.sh`, `set-role.sh`, `flip.sh`)
  - [x] 2.2.1 Source the library below the xtrace refusal, preceded by `unset
    _SOLEUR_OPERATOR_SCRIPT_LOADED SOLEUR_OP_ACKED; unset -f soleur_op_ack_or_die
    soleur_op_input_required soleur_op_aborted`.
  - [x] 2.2.1a Argv hardening: value-taking options reject values starting with `--`; `flip.sh`
    rejects `--control-org` without `--org`; `set-role.sh` rejects >3 args or a 3rd arg other than
    `--dry-run` (all exit 2).
  - [x] 2.2.2 Early no-TTY precheck right after argv parsing (write mode only).
  - [x] 2.2.3 Replace typed-yes with `soleur_op_ack_or_die` (distinct prompt per site).
  - [x] 2.2.4 `flip.sh`: single `gate_or_confirm`; remove `--confirmed`, reject it with exit 2 and an
    "own terminal" message.
  - [x] 2.2.5 Header exit-code tables (abort 1, no-TTY 64, flip `--confirmed` 2).
  - [x] 2.2.6 `umask 077`: writes are in-place (no new files), so modes are unchanged; keep the
    mode-preserved assertion from 1.2.
- [x] 2.3 `audit-sentry-extra-text-references.sh`: source library, precheck when `--apply`, ack after
  inventory and before the first PUT (skip on zero matches).
- [x] 2.4 Migrate `flag-detach-shared.test.sh` and `flag-org-scoping-pr2.test.sh` from `--confirmed`
  to pty-driven `yes`; add a `--confirmed` → exit 2 case.
- [x] 2.5 Defer-gate rule `prod-write-defer-operator-ack-script`: unique basenames matched anywhere
  (dir-qualified for `create.sh`/`delete.sh`), every call evaluated (defer if any is a write), tail
  terminators incl. newline/quotes/`#`/backtick/`$(`; reader escape cancelled on pipe-to-shell;
  `--dry-run`-only escape, none under a PTY wrapper or `yes |`; fixed-string prefilter, copied
  captures, fail-closed function + EXIT trap; register for `Monitor` in `.claude/settings.json`;
  README "Starter manifest" → 4 entries.
- [x] 2.6 Per-harness `[[ -t 0 ]]` and `/dev/tty` reachability measurement (Claude Code measured:
  `stdin=notty`, `devtty=unreachable`; codex/grok/devin ≤ 6 model calls; `!` prefix and unrunnable
  harnesses → UNMEASURED).
- [x] 2.7 ADR-249 (per-harness table, residual risks, step-2 design, `tty-ack` meaning, census and
  tracking issue); amend ADR-236.
- [x] 2.8 C4: add `flagsmith` element and edges in `model.c4`; include in the `context` view.
- [x] 2.9 SKILL.md bodies (four skills): `--dry-run`, then print the write command for the
  operator's terminal as `cd <absolute worktree> && bash <absolute script> …`; the handoff is a
  blocking operator step (`wg-block-pr-ready-on-undeferred-operator-steps`); flag-set-role gets an
  incident-rollback block (no dry-run, own terminal not `!`, dashboard break-glass on exit 4); remove
  `--confirmed`; exit-code tables. Runbook `oauth-probe-failure.md`.
- [x] 2.9a `.down.sql` header + ADR: rollback order (revert helper and let it reach the installed
  plugin before running the down migration).
- [x] 2.9b `plugins/soleur/commands/go.md` §Operator-typed tooling: flag-create/flag-set-role run
  `--dry-run` only and hand off the write command.
- [x] 2.10 Sweep model-read surfaces for agent-performed writes / `--confirmed`; update
  `components.test.ts` reason strings.
- [x] 2.11 List open plans that prescribe agent flag writes (PR body; no edits to point-in-time
  plans).
- [x] 2.12 Flag-flip LIA: add the "Approval-method field" data-minimisation bullet (register: no change).

## 3. Testing and verification

- [x] 3.1 `bash plugins/soleur/test/operator-ack-guard.test.sh`
- [x] 3.2 `bash plugins/soleur/test/operator-script.test.sh`
- [x] 3.3 `bash .claude/hooks/prod-write-defer-gate.test.sh`
- [x] 3.4 `bash plugins/soleur/test/audit-flag-flip.test.sh`, `flag-detach-shared.test.sh`,
  `flag-org-scoping-pr2.test.sh`
- [x] 3.5 Migration 140 and 071 tests; `invocation-axis.test.ts`; `components.test.ts`
- [x] 3.6 C4 syntax, render and `plugins/soleur/test/c4-count-parity.test.sh`
- [x] 3.7 Discoverability probe: `bash plugins/soleur/skills/flag-delete/scripts/delete.sh probe-flag`
  prints `SOLEUR_BOOTSTRAP_INPUT_REQUIRED` and exits 64.
- [x] 3.7a AC14: each SKILL.md's printed write command reaches its ack under `script -qec` (stub
  PATH, `no` answer, zero mutating calls).
- [ ] 3.7b AC16 (pre-merge): read-only OpenAPI probe of dev PostgREST shows `rpc/audit_flag_flip`
  with `p_approval_method`; never call the RPC to test it.
- [ ] 3.8 Full review panel (TR5): security-sentinel, user-impact-reviewer, and the rest; run
  `soleur:gdpr-gate` against the diff.
