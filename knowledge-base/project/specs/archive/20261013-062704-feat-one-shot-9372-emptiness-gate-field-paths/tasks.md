# Tasks: fix the web-2 rebirth emptiness gate field paths (Ref #9372)

Plan: `knowledge-base/project/plans/2026-10-06-fix-web2-rebirth-emptiness-gate-field-paths-plan.md`
Hard limits: code PR only. No dispatch (plan-only or real) of `web2-luks-rebirth.yml`, no environment approval, no Doppler write, no token mint, no workflow pause/enable, no Terraform apply. `Ref #9372`, never `Closes`. Pre-work gate: CPO/owner sign-off (not self-attributed).

## Phase 1: Tests first (RED)

- 1.1 In `scripts/web2-rebirth-emptiness.test.sh` add the synthesized real-shape rows (used, total, non-canonical used with extra tags and permuted keys, legacy flat, other-host decoy, scalar-`tags` row, absent-`gauge` row).
- 1.2 Add `w2r_sql_paths <sql-text>`: anchored `^WHERE`..`^GROUP BY` block, strict grammar (unknown line shape prints `FAILED`), extract string conjuncts, float paths and the SELECT name path.
- 1.3 Add assertions: exact (path,value) set; two float paths both `gauge,value`; SELECT name path equals IN name path; conjuncts hold on real rows (with `try getpath` coalescing); violated by legacy and other-host rows; non-zero float; in-process negative controls (empty WHERE -> fail; legacy-path SQL -> violated). Every failure line starts `FAILED`; each assertion bumps `n`.
- 1.3b Assert a green baseline before mutation kill-counting.
- 1.4 Add mutations 1-12 from the plan's Guard Contract (host path, vmin-only and vmax-only value path, SELECT-only and IN-only name path, host/mountpoint/namespace/HAVING deletions, archive arm, unrecognized conjunct) and re-aim the two existing path-bearing mutations; update the SQL-shape fragment loop (UNION arms, `GROUP BY metric_name`, `INTERVAL 7 DAY`, `HAVING uniqExact`).
- 1.5 Run the suite against the UNCHANGED SQL and record that the path assertions are RED.

## Phase 2: Fix (GREEN)

- 2.1 In `scripts/web2-rebirth-emptiness.sh` change only `w2r_sql_emptiness`: `tags.host`, `namespace`, `tags.mountpoint`, `name`, `gauge.value`, plus `HAVING uniqExact(JSONExtractString(raw,'tags','device')) = 1`.
- 2.2 Rewrite the header: confirmed paths, date and control values (n, hours, age, min, max), keep the `dm-*` caveat, correct approval-before-evidence, state the shape-drift/multi-device meaning of `used_bytes_absent_or_host_dark`.
- 2.3 Re-run the emptiness suite; re-derive `ran` from the green run and set the floor to exactly that.
- 2.4 `git diff` check (AC2): constants, `w2r_emptiness_verdict`, `w2r_main` and the `W2R_DETACHED` arm byte-identical.

## Phase 3: Docs

- 3.1 ADR-263: amend the pass-condition prose (approval precedes evidence; first live query done) and the "Known limits" sentence (paths confirmed 2026-10-06; `dm-*` still unconfirmed).
- 3.2 `web2-luks-rebirth-9372.md`: the unconfirmed sentence and approval-before-evidence wording.
- 3.3 `betterstack-log-query.md`: one sentence, root cause replaces "tracked in #6944 separately"; the gate reads the native shape.
- 3.4 `model.c4`: one clause on the `hetzner -> betterstack` edge (host_metrics rows carry `tags.host`, not `host_name`).

## Phase 4: Regression gates

- 4.1 `bash scripts/web2-rebirth-emptiness.test.sh`; `bash scripts/web2-rebirth.test.sh` (123); `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` (107).
- 4.2 `bash plugins/soleur/test/c4-model-freshness.test.sh` and the C4 count-parity test; `python3 scripts/lint-encryption-posture.py --repo-sweep`; `python3 scripts/lint-guard-contract.py` on the plan.
- 4.3 `shellcheck` the two scripts; markdownlint the edited docs.
- 4.4 `git diff --stat origin/main` shows `vector.toml`, `web2-rebirth.test.sh`, the workflow and `lib/web2-luks-rows.sh` unchanged (AC7).

## Phase 5: Ship

- 5.1 Security-focused review (security-sentinel + user-impact-reviewer) before merge; resolve findings.
- 5.2 PR body: `Ref #9372`, the recorded live control, Vector 0.43.1 reproduction summary, observed level (the volume's own reading, not an independent empty reference), `tags.host` trust note, decision-challenges, and the no-dispatch/no-approval/no-write statement.
- 5.3 Comment on #6944 (root cause; does not close it) and on #9372 (next owner-gated step: first post-merge plan-only dispatch).
