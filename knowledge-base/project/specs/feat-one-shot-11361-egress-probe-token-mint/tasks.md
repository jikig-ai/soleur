---
title: "Tasks — fix(infra): egress-enforce probe mints empty session-token file"
branch: feat-one-shot-11361-egress-probe-token-mint
issue: 11361
plan: knowledge-base/project/plans/2026-10-27-fix-egress-probe-token-mint-plan.md
---

# Tasks

Plan: `knowledge-base/project/plans/2026-10-27-fix-egress-probe-token-mint-plan.md`

## Phase 1 — RED (test first, `cq-write-failing-tests-before`)

- [ ] 1.1. In `apps/web-platform/infra/cron-egress-enforce-probe.test.sh`, extend the `docker` stub's `exec` `--proxy` arm (currently line ~225) to replicate the `egress-auth-helper.sh` auth contract: parse `--proxy http://<user>:<tok>@<ip>:8443` from argv, read `"$EGRESS_GW_TOKEN_DIR/<tok>"` at CONNECT time, and answer `407` when file content ≠ presented `user` (else honor `${STUB_GW_ALLOW_CODE:-200}`). Log the observed verdict (user + whether content matched) to `$STUB_CALLS` so a non-vacuity row can assert the arm evaluated auth.
- [ ] 1.2. Add `check()` rows: (a) healthy run reaches `egress-enforce-ok` with the stub contract arm active; (b) non-vacuity row asserting the stub recorded an auth verdict for a real minted file in `$GWTOK_DIR`; (c) deny-leg discrimination unchanged (`STUB_GW_DENY_RC=0` → `ASSERT-FAILED: egress-gw-deny` already exists — confirm still green).
- [ ] 1.3. Add static pins: `assert_grep` on `$PROBE` for `printf 'probe' > "$GW_TOKEN_DIR/$GW_TOK"` mint syntax; `assert_not_grep` for the empty-mint shape `: > "$GW_TOKEN_DIR/$GW_TOK"`; anchor `assert_grep` on `egress-auth-helper.sh` for the `"$user" == "$(<"$TOKDIR/$pass")"` contract line.
- [ ] 1.4. Bump `MIN_CASES` by the number of rows added (anti-vacuity floor).
- [ ] 1.5. Run `bash apps/web-platform/infra/cron-egress-enforce-probe.test.sh` — MUST be RED (`ASSERT-FAILED: egress-gw-allow` on the healthy run, because the defect's empty mint now fails the stub contract). Record the red output.

## Phase 2 — GREEN

- [ ] 2.1. In `apps/web-platform/infra/cron-egress-enforce-probe.sh` line 190, change `: > "$GW_TOKEN_DIR/$GW_TOK"` to `printf 'probe' > "$GW_TOKEN_DIR/$GW_TOK"` (sibling `cron-egress-resolve.sh:958` exact form; keep the `if ! … 2>/dev/null` guard).
- [ ] 2.2. Re-run the suite — `0 failed`, exit 0.

## Phase 3 — Mutation battery (Guard Contract rows)

- [ ] 3.1. On a scratch copy, apply mutation rows 1-3 from the plan's Guard Contract (`: >` empty mint; `printf 'root'`; compliant mint + second `: >` write) — each must red the suite naming `egress-gw-allow`.
- [ ] 3.2. Confirm must-PASS rows: `STUB_GW_ALLOW_CODE=503` still fails the allow leg through the injected-code path; a different random token name each run passes (content property, not filename).
- [ ] 3.3. Record the battery results for the PR body.

## Phase 4 — Follow-through enrollment

- [ ] 4.1. Create `scripts/followthroughs/egress-enforce-probe-11361.sh`: Sentry query (`jikigai-eu`/`web-platform`) for `stage=egress_enforce_probe` fatal events since merge + `gh run list` evidence a `web-host-replace`/`web-host-create` apply run concluded `success` post-merge; exit 0 only when birth evidence exists AND zero matching fatal events; exit 1 on a `gw_allow_fail`/`egress_enforce_probe` fatal event; TRANSIENT on API errors. Carry the sibling xtrace credential-refusal shape and `_bearer_ok` token guard (model on `scripts/followthroughs/ac8-founder-ambiguous-soak-5673.sh`).
- [ ] 4.2. Verify `bash -n` parses and `bash scripts/followthroughs/egress-enforce-probe-11361.sh` exits non-zero today (no post-merge birth yet).
- [ ] 4.3. Post the tracker directive on #11361: `<!-- soleur:followthrough script=scripts/followthroughs/egress-enforce-probe-11361.sh earliest=<merge+7d> secrets=GH_TOKEN,SENTRY_ACTIONS_RO_TOKEN -->` and apply the `follow-through` label (at ship/post-merge).

## Phase 5 — Deployment (operator, post-merge)

- [ ] 5.1. Merge → `web-platform-release.yml` builds the new image tag (automatic on `apps/web-platform/**` push).
- [ ] 5.2. Operator re-dispatches `gh workflow run apply-web-platform-infra.yml -f apply_target=web-host-replace` under #11321 O2 pinning the NEW `image_tag` — never `0.364.13` (it bakes the defect).
- [ ] 5.3. Follow-through probe verifies the fresh host emits no `stage=egress_enforce_probe` fatal event and closes the tracker.
