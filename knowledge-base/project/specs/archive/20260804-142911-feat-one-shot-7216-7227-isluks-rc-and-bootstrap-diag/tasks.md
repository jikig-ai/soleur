# Tasks — fix(git-data): isLuks rc-branching + the bootstrap diagnostic path

Derived from
[`knowledge-base/project/plans/2026-08-03-fix-git-data-isluks-rc-and-bootstrap-diagnostic-plan.md`](../../plans/2026-08-03-fix-git-data-isluks-rc-and-bootstrap-diagnostic-plan.md)
(v2, post 6-agent plan-review).

Closes #7216. Closes #7227. Lane: `cross-domain`. Brand-survival threshold:
`single-user incident`.

**Do NOT dispatch the rung-2 rehearsal or the git-data birth in this run.**
**Do NOT create or regenerate `apps/web-platform/infra/git-data-rung2-boot-evidence.env`.**

---

## Phase 0 — Preconditions (measure, do not assume)

- [ ] 0.1 Confirm clean worktree on `feat-one-shot-7216-7227-isluks-rc-and-bootstrap-diag`.
- [ ] 0.2 Re-confirm the six baselines. Expected (measured at plan time):
      luks `113/113` · runcmd-rehearsal `36/36` · evidence-capture `30/30` ·
      rung2-rehearsal `70/70` · `stored=25968 B / cap=32768 B (headroom 6800 B)` ·
      `encryption-posture … 0 failing checks -> PASS`.
- [ ] 0.3 Confirm **docker** AND **terraform** present. **STOP if either is missing** —
      `git-data-userdata-budget.sh` SKIPs and exits 0 without terraform, making AC11 vacuous.
- [ ] 0.4 Re-take the `isLuks` rc measurement in `ubuntu:24.04`. Expect `2.7.0`,
      `rc_nonluks=1`, `rc_missing=4`, `rc_notfound=127`. **STOP if `rc_nonluks != 1`.**
- [ ] 0.5 Record that nothing waits on `$DEV` today; disposition = bounded wait then abort.
- [ ] 0.6 Read `plugins/soleur/test/cloud-init-user-data-size.test.ts` and note its modelled
      ceiling — it may bind tighter than the raw 32,768 cap.

## Phase 1 — RED (only `assert_holds` arms count as RED)

Mutation arms cannot match text that does not exist yet; pre-fix they report
`MUTATION DID NOT LAND`, an instrument fault. Add them in Phase 3.

- [ ] 1.1 Add `p_isluks_rc_branch` + `assert_holds "B18 …"` → must report
      `property does not hold on the real file`. Capture the output.
- [ ] 1.2 Widen `R3(3b)` → must report the verdict set
      `{on_err: LITERAL, sshd_config: LITERAL, bootstrap_err: LITERAL, luks_err: VAR:GUARDED}`.
      Capture the output.
- [ ] 1.3 Add the capture-script prefix arm → production name must be **accepted** (the defect).
- [ ] 1.4 Add the arm-10 prefix pin → literal must be **absent** from the validation regex.

## Phase 2 — GREEN: `cloud-init-git-data.yml` (+ one payload)

Parent runcmd shell is `/bin/sh` = **dash**. POSIX only.

- [ ] 2.1 Replace the `if ! cryptsetup isLuks …` block: bounded `$DEV` wait (30 s), rc capture via
      **command substitution** (never `2>>` on the probe — a failed redirect forges rc=1 without
      running it), `case` on `0` / `1` / `*`, catch-all `{ …; exit 1; } || exit 1`.
      Catch-all message must **not** contain `cryptsetup isLuks` or `luksFormat`.
      Do not change `luksFormat`'s flags, stdin delivery, or `$DEV` operand.
- [ ] 2.2 Seed `GIT_DATA_RUNCMD_DETAIL=/run/git-data-runcmd.log` after `export HOME=/root` and
      **before** `trap on_err EXIT`; `umask 077`; `[ -w ] || =/dev/null` fallback.
- [ ] 2.3 Rewrite `on_err` with local `_onerr_detail`, dmesg-first, **no cloud-init-log slot**,
      `else`-branch literal so the fallback is reachable, `umask 077` on `.final`,
      `MSG` derived as `"git-data $STAGE FAILED"`.
- [ ] 2.4 **Delete `bootstrap_err`** and its trap swap entirely (`on_err` + `$STAGE` covers it;
      also fixes the latent `gc_timer` mislabel).
- [ ] 2.5 Rename `luks_err`'s local `_detail` → `_luks_detail`; add `umask 077` on its `.final`.
- [ ] 2.6 Add `: > "$GIT_DATA_RUNCMD_DETAIL" 2>/dev/null || true` after **each** parent `STAGE=`.
- [ ] 2.7 Add `2>>"$GIT_DATA_RUNCMD_DETAIL"` to exactly four commands: the download `curl`,
      `sha256sum -c -`, and **both** `doppler run` invocations. Not `tar`, `chmod`,
      `mount … || true`, or `daemon-reload`.
- [ ] 2.8 Move the `gc_timer` guard **inside** the `||` failure branch.
- [ ] 2.9 `sshd_config`: bind `_sshd_detail` right after `_sshd_t_rc=$?`, `[ -s ]`-guard it, use in
      **all three** emits (fatal + 126/127 warning + restart-failed warning); fix that stage's own
      naked capture with the same substitution shape as 2.1.
- [ ] 2.10 `git-data-bootstrap.sh`: `log()` writes to **stderr** (`>&2`). Zero stored-byte cost.
- [ ] 2.11 Re-run `git-data-userdata-budget.sh`; headroom must be `> 0`. Trim comment prose only.

## Phase 3 — GREEN: the guards

- [ ] 3.1 `git-data-luks.test.sh`: re-point `p_isluks` (A1) at `_luks_slice`; add `B18` hold +
      3 mutation arms (revert-to-`if!` via line-anchored `s///`; drop-`exit 1` anchored on `\*\)`;
      naked-capture with a `#` delimiter). Predicate must match `cryptsetup[[:space:]]+luksFormat`.
- [ ] 3.2 `git-data-runcmd-rehearsal.test.sh`: add `runcmd-all.code.sh` with a **counted shell**
      non-vacuity arm (not a python `assert`); widen `R3(3b)` to emitter-relative token indexing,
      a message-literal **set**, a region-scoped guard search, and pairwise-distinct arg-4 names;
      add `R3(3c)` (LITERAL direction) and `R3(3d)` (UNGUARDED direction); add `R3(2d)` seed
      ordering + relocation mutation. Correct the Phase 2.1 comment's claim about what it asserts.
- [ ] 3.3 `tests/scripts/test-git-data-rung2-evidence-capture.sh`: three arms — production name
      refused (rc 64), rehearsal name accepted, quote-bearing rehearsal name still refused.
- [ ] 3.4 `git-data-rung2-rehearsal.test.sh`: fold the capture-script prefix into **arm 10's
      existing comparison chain** (not a new arm + mutation).
- [ ] 3.5 Mechanize Decision clause B: assert `special = false` on `random_password.git_data_luks`,
      no `set -x` in template or bootstrap, `--key-file -` on every key-consuming `cryptsetup`.
- [ ] 3.6 **Re-derive all four floors from measured totals** after the arms exist; itemise each
      raise in its file's floor comment. Do not carry a number from the plan.

## Phase 4 — Capture script, CI filter, ADR

- [ ] 4.1 Constrain `--host-name` to `^soleur-git-data-rehearsal-[A-Za-z0-9._-]+$`. No override
      flag. Update the usage line and header.
- [ ] 4.2 Add `scripts/followthroughs/git-data-rung2-evidence-capture.sh` to
      `.github/workflows/infra-validation.yml`'s `paths:`.
- [ ] 4.3 Write the **ADR-147 addendum**: the git-data `user_data`-diagnostics exception now covers
      diagnostic capture plumbing; record the measured byte cost and remaining headroom.

## Phase 5 — Verification

- [ ] 5.1 `bash scripts/test-all.sh`, plus
      `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`
      (**not** vitest, **not** `apps/web-platform/test/`).
- [ ] 5.2 `python3 scripts/lint-encryption-posture.py` **and** `--repo-sweep` → both PASS at
      baseline counts.
- [ ] 5.3 `test ! -e apps/web-platform/infra/git-data-rung2-boot-evidence.env`, and it is not in
      `git diff --name-only origin/main...HEAD`.
- [ ] 5.4 Birth-readiness gate library untouched; `git_data_rung2_rehearsal_gate` still HOLDs
      fail-closed with no evidence file.
- [ ] 5.5 Walk every AC1–AC19 and record the verifying command + output.

## Phase 6 — Ship

- [ ] 6.1 `/soleur:ship`. PR body carries: the Phase 0.4 rc measurement; the forged-rc-1
      measurement; the two-clause invariant; both `sshd_config` divergences; before/after budget
      numbers; the deliberate Sentry regrouping from deriving `MSG`; `Closes #7216. Closes #7227.`
      in the **body**.
- [ ] 6.2 Ensure `decision-challenges.md` (UC-1 + T-1..T-4) is rendered into the PR body and filed
      as an `action-required` issue.
- [ ] 6.3 **No rehearsal dispatch. No birth.** Both are operator steps after merge.

## Post-merge (operator, not this run)

- [ ] P.1 Dispatch `git-data-rung2-rehearsal.yml` once. PASS = `boot_complete`, four booleans
      positive, no `level:fatal`. On FAIL: diagnose from the capture artifact **and Sentry** — a
      parent-shell fatal reports TRANSIENT until #7116 closes. **Spend dispatch #2 only after a fix
      lands, never as a bare retry.** Cap: two.
- [ ] P.2 Release the interlock per
      `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md`.
