# Tasks — feat-one-shot-9972-bump-pin-token-shape

Issue: #9972 | Plan: `knowledge-base/project/plans/2026-10-11-fix-bump-cloud-init-pin-token-shape-plan.md`

Status: all phases complete (2026-10-11); review-round deltas recorded inline.

## Phase 1 — Suite first (red)

- [x] 1.1 In `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` (~`:1171`), define
      `SYN_TOK_V2` (synthetic several-hundred-char token carrying every newly-admitted byte:
      `.` `-` `~` `+` `/` `=`, `ghs_` prefix split-concatenated like `SYN_TOK` so no contiguous
      token-shaped literal sits in source). *As-built delta:* no `SYN_B64_V2`
      constant — `accept_row` derives `tok_b64` from the row's own token
      (same idiom `run_shimmed` uses for `SHIM_B64`), so no fixture is pinned
      to a sibling value.
- [x] 1.2 In `run_shimmed` (~`:1245`), derive `SHIM_B64` from the passed `$tok`
      instead of pinning `$SYN_B64` — behavior-identical for existing rows.
      *Review r1 addendum:* the shim's `env=header-ok` conjunct now also
      requires `GIT_CONFIG_VALUE_0 == "Authorization: basic ${SHIM_B64}"`, so
      the derivation itself is pinned (a stale `SHIM_B64` reds every accept row).
- [x] 1.3 Replace `refuse_row dot` (~`:1981`) with the `newshape` accept row —
      *as-built:* `accept_row newshape "$SYN_TOK_V2"`, where `accept_row` is the
      argv row's fixture + assertion set extracted into a helper (dedup per the
      design pass). Assertion set: `rc=0`, `result=opened`,
      `soleur/inngest-pin-v1.1.38` branch present, `net=1` count 2,
      `sub=ls-remote`/`sub=push` 1 each, `argv=token`/`argv=b64` 0,
      `net=1 argv=clean url=ok` 2, `net=1 .*env=header-ok` 2,
      `net=0 .*env=header` 0, `out_lacks` on the row's token and its derived b64.
      Plus a fixture self-check: `SYN_TOK_V2` must carry a byte outside the
      legacy `[A-Za-z0-9_]` class, else `newshape` degenerates to a argv duplicate.
- [x] 1.4 Update the `assert_refused` needle to
      `'must match [A-Za-z0-9._~+/=-]+'` and the refuse-block comment — removed
      "a dot" (in-class now) and the "a blank" double-count of `empty`.
- [x] 1.5 Ran `bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh` —
      `newshape` RED at the guard (13 failures: 12 newshape assertions + wording
      needle on the 6 surviving refuse rows), all other rows unchanged.

## Phase 2 — Widen the guard (green)

- [x] 2.1 `.github/scripts/bump-inngest-bootstrap-pin.sh`: guard now invokes a
      canonical-body `_bearer_ok()` copy
      (`{ local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }`)
      defined at top level beside `die` — *as-built delta per design-pass P2:*
      a canonical-body copy joins the parity net in
      `lint-shell-trace-credential-refusal.test.sh` (73 copies, 0 off-canonical),
      so a future alphabet amendment cannot silently re-narrow this guard.
      `token_shape`/`control_char` split kept at the call site.
- [x] 2.2 die message → `must match [A-Za-z0-9._~+/=-]+ (value not shown)`.
- [x] 2.3/2.4 Comments updated: canonical alphabet + home + why (issued
      installation tokens now carry `.`/`-`; measured live 2026-10-11, #9972).
- [x] 2.5 Suite green: 699 pass / 0 fail (floor `MIN_ASSERTIONS` re-measured
      to 699 per its own contract).

## Phase 3 — Recorded architecture

- [x] 3.1 ADR-280 amended in place: class reads `[A-Za-z0-9._~+/=-]` with a dated
      correction note (measured 2026-10-11; legacy `ghs_` base62 assumption was
      the defect #9972 repaired).

## Phase 4 — Verify and ship

- [x] 4.1 Full suite green: 699 pass / 0 fail; whole `run-all.sh` fixture
      battery green; `lint-shell-trace-credential-refusal.test.sh` 636/0 incl.
      the new canonical copy in the 73-copy population.
- [x] 4.2 Residual greps clean (`A-Za-z0-9_\]`, `ghs_ class` → nothing).
- [x] 4.3 `grep -Fc -- '*[!A-Za-z0-9._~+/=-]*' .github/scripts/bump-inngest-bootstrap-pin.sh`
      prints `1`.
- [x] 4.4 Fix + suite + ADR committed; review-panel round committed separately.
- [x] 4.5 Deferred-capability follow-up FILED as #9999 (ghs_ sentinel sweep:
      `learning-retrieval-bench.sh:611`, `run-scan.sh:143` redaction,
      `kb-search/SKILL.md:162`, `work/SKILL.md:864`, `git-auth.ts:45`).
- [ ] 4.6 Post-merge (parent session): re-run run 38102444768's failed
      `bump-cloud-init-pin` job — marker absent, bump PR opens (AC8).
