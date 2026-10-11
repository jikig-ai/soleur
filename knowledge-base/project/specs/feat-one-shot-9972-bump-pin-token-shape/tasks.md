# Tasks — fix(ci): bump-cloud-init-pin fails with SOLEUR_CREDENTIAL_REFUSED reason=token_shape

Plan: `knowledge-base/project/plans/2026-10-11-fix-bump-cloud-init-pin-token-shape-plan.md`
Issue: #9972 · Branch: `feat-one-shot-9972-bump-pin-token-shape`

## Phase 1 — Suite first (red)

- [ ] 1.1 In `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` (~`:1171`), define
      `SYN_TOK_V2` (synthetic ≥100-char token carrying every newly-admitted byte:
      `.` `-` `~` `+` `/` `=`, split-concatenated like `SYN_TOK` so no contiguous
      token-shaped literal sits in source) and `SYN_B64_V2`
      (`printf '%s' "x-access-token:${SYN_TOK_V2}" | base64 | tr -d '\n'`).
- [ ] 1.2 In `run_shimmed` (~`:1245`), derive `SHIM_B64` from the passed `$tok`
      instead of pinning `$SYN_B64` — behavior-identical for existing rows.
- [ ] 1.3 Replace `refuse_row dot` (~`:1981`) with the `newshape` accept row
      mirroring the `argv` local row (`:1260-1297`): `new_fixture_repo` →
      `write_fixture_cloud_inits` → `fixture_commit` → `seed_tag vinngest-v1.1.38`
      → crane-map append → push → `run_shimmed newshape local "$SYN_TOK_V2"`,
      then assert `rc=0`, `result=opened`, `soleur/inngest-pin-v1.1.38` branch
      present, `net=1` count 2, `sub=ls-remote`/`sub=push` 1 each,
      `argv=token`/`argv=b64` 0, `net=1 argv=clean url=ok` 2,
      `net=1 .*env=header-ok` 2, `net=0 .*env=header` 0, `out_lacks` both
      `$SYN_TOK_V2` and `$SYN_B64_V2`.
- [ ] 1.4 Update the `assert_refused` needle (`:1969`) to
      `'must match [A-Za-z0-9._~+/=-]+'` and the refuse-block comment
      (`:1959-1963`) — remove "a dot" from the refused-shapes enumeration, note
      `.`/`-` are in-class and covered by the accept row.
- [ ] 1.5 Run `bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh`;
      confirm `newshape` is RED at the guard and every other row is unchanged.

## Phase 2 — Widen the guard (green)

- [ ] 2.1 `.github/scripts/bump-inngest-bootstrap-pin.sh:237`:
      `''|*[!A-Za-z0-9_]*)` → `''|*[!A-Za-z0-9._~+/=-]*)` (byte-identical to
      `bc_ok` at `scripts/lib/bearer-curl.sh:59`).
- [ ] 2.2 `:241` die message → `must match [A-Za-z0-9._~+/=-]+ (value not shown)`.
- [ ] 2.3 `:47` comment → name the canonical alphabet and its home
      (`scripts/lib/bearer-curl.sh` `bc_ok`).
- [ ] 2.4 `:234-235` comment → canonical alphabet + why (issued installation
      tokens now carry `.`/`-`; measured live 2026-10-11, #9972).
- [ ] 2.5 Re-run the suite — all rows green including `newshape`.

## Phase 3 — Recorded architecture

- [ ] 3.1 Amend `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md`
      (`:190`): the guard's class reads `[A-Za-z0-9._~+/=-]` (canonical,
      `bc_ok`) with a dated correction note (GitHub's issued installation
      tokens changed format; measured 2026-10-11; #9972).

## Phase 4 — Verify and ship

- [ ] 4.1 Full suite green: `bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh`.
- [ ] 4.2 Residual greps: `grep -n 'A-Za-z0-9_\]' .github/scripts/bump-inngest-bootstrap-pin.sh`
      and `grep -n 'ghs_ class' .github/scripts/bump-inngest-bootstrap-pin.sh`
      return nothing.
- [ ] 4.3 `grep -Fc -- '*[!A-Za-z0-9._~+/=-]*' .github/scripts/bump-inngest-bootstrap-pin.sh`
      prints `1` (the Observability discoverability probe — verified returning
      `0`/`1` at plan time).
- [ ] 4.4 Commit the fix + suite + ADR amendment; PR body closes #9972
      (`Closes #9972` in body per `wg-use-closes-n-in-pr-body`).
- [ ] 4.5 Post-merge (parent session): re-run run 38102444768's failed
      `bump-cloud-init-pin` job — marker absent, bump PR opens (AC8).
