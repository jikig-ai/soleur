# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-27-chore-cf-phase5-old-login-token-remint-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=0 (one-shot main context; the planning subagent ran its own CTO rounds)

### Errors
- Plan-file write guard refused a secret-write command pattern; acknowledged after Phase 2.8 IaC review ran.
- Issue-filing hook refused two filings (shell var in body path, missing Mandated-By); fixed, #13085 and #13086 filed.

### Decisions
- Ruled by CTO agent (F1, F11): new runbook `cloudflare-old-login-token-remint.md`; migration runbook untouched (#12958 owns it).
- Ruled by CTO agent (F2', F9', F14, F15): four-stage bootstrap (inventory, swap, holder-copies, verify); PURGE stays at Phase 3 step 5.
- Ruled by CTO agent (F13, F21): revoke only on a same-sitting SOLEUR_P5_REVOKE_READY line.
- Ruled by CTO agent (F17, F18, F20): account-owned mints on the Soleur account; audit token only in prd_terraform and dev.
- Ruled by CTO agent (F3): stale GitHub repo secrets CF_API_TOKEN/CF_ACCOUNT_ID stay; repoint recorded on #12983.

### Components Invoked
- soleur:plan, soleur:plan-review, soleur:deepen-plan; CTO (5 rounds), terraform-architect, research and review agents.

## Operator Constraints

- constraint: Never print token values.
- constraint: No SSH.
- constraint: Leave the old zone read-only.
- constraint: No gh-pages cert reissue with probeOnly:false before Phase 3 step 5.
- constraint: Each re-mint/revoke needs a typed go naming the exact command.

## Work Phase
- Affected gate (`gate-or-skip.sh`, selected 560 of 792, commit 56537963cf): rc=1. Every red was re-run in isolation and none is reached by this diff:
  - `ci-path-gating.test.sh`: 46/0 in isolation (contention under the gate).
  - `cloud-init-user-data-size.test.ts` "seam can only RAISE the floor" (also inside `cloud-init-strip-helpers-mutation` and the `plugins/soleur` bun aggregate): fails identically on main at the same base 1ec95e1664; tracked in #12850 (terraform-installed hosts only; CI skips it).
  - `pencil-adapter-stub-repl.test.ts`: a different case times out per run (60s), same class as #12853; main CI green.
  - `domain-model-headless-append`, `inngest-luks-sole-copy`: rc=0 in isolation (SIGTERM under the gate).
  - `destructive-command-guard-mutation`: 84/84, one mutant run timed out (rc=3 UNRESOLVED, wall-time over budget).
- New suite `tests/scripts/test-cf-old-login-token-remint-bootstrap.sh`: 85/0 (full), 47/0 (--mutants), 21 mutants killed.
- Plan correction: the three generated infra-security copies are pointer stubs with no ids; sync `--check` clean, nothing regenerated.

## Review Phase
- Panel: 10 seats (security, structural, test-design, data-integrity, architecture, quality, pattern, agent-native, simplicity, git-history); all findings pr-introduced, fixed inline.
- Ruled by CTO agent (D1): dashboard bodies committed as tested, sha256-pinned `p5-mint.js`, `p5-revoke.js`, `p5-sink.py` with their own suite.
- Ruled by CTO agent (D2): committed census floor (`# P5-PROJECT-FLOOR`, nine projects, plus the tracked soleur config inventory).
- Ruled by CTO agent (D3): drift gate removed from `verify`; one post-revoke drift run with DOPPLER_TOKEN scoped to that process.
- Ruled by CTO agent (D4): migration runbook untouched; pointer sentence in this runbook and the bootstrap header; comments on #12931 and #12958.
- Ruled by CTO agent (D5): swap op line binds `new_id`/`owner`; `_NEXT` equal to another CF_API_TOKEN* key refused.
- Suites: bootstrap 210/0 full, 127/0 mutants; browser 101/0 full, 25/0 mutants.
- Floor gap from the fix agent (8 of 9 projects) closed with a names-only `doppler projects` read (`example-project`).
- Review-round gate (`gate-or-skip.sh`): rc=1, ended `failed-before-budget`. Real red `lint-shell-capture-exit-live` (bootstrap floor capture) fixed; re-run 0 new findings. `apps/web-platform [unit]` reds (`agent-auth-failure-matcher`, `sandbox-network-access-runtime`) 60/60 in isolation (contention). Unmeasured suites covering this diff run directly: `test-affected-kb-consumers` 31/31, `test-affected-derive` 139/139, `lint-orphan-test-suites` clean.

## Fix Round 1
- Seats (report-only, at fd7b14bbb7): security, data-integrity, test-design, architecture, code-quality, pattern, agent-native. One P1 (post-revoke routing), the rest P2/P3; all fixed inline.
- Ruled by CTO agent (D6): `SOLEUR_P5_PREV state=` from the two-endpoint read; `denied` is revoked only after a same-sitting `REVOKE_READY` or a `P5-REVOKED` record; swap refuses any `_PREV` that is not pinned, denied or absent.
- Ruled by CTO agent (D7): `p5-mint.js` `owner` with `refuse_ids` for user mints; committed `p5-read.js`; paste fallback dropped.
- Ruled by CTO agent (D8): no rollback for a partial swap; guarded `_PREV` over `<KEY>` copy plus `p5-revoke.js` `mode:"retire"` for a completed swap with a bad token.
- Ruled by CTO agent (D9): `P5-MINTED` record; author-filtered, unedited-only lookups (REST `created_at == updated_at`, a verified field, in place of the unverified GraphQL one); data-only `JSON.parse` arguments.
- Exemptions from the class env refusal: `GIT_EDITOR`, `GIT_SEQUENCE_EDITOR`, `GIT_PAGER`, `GIT_TERMINAL_PROMPT`, `GIT_CEILING_DIRECTORIES` (the agent session exports one; none affects the git reads).
- Browser suite 220/0 full, 66/0 mutants (25 mutants killed); plan holds now a verbatim copy of runbook section 6 with a parity row.
