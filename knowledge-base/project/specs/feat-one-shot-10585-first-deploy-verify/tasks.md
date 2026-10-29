# Tasks — feat-one-shot-10585-first-deploy-verify

Plan: `knowledge-base/project/plans/2026-10-29-verify-web-host-replace-first-deploy-plan.md`

## Phase 1 — Probe + fixture suite (failing tests first)

- [ ] 1.1 Write `scripts/followthroughs/web-first-deploy-10585.test.sh` with synthesized fixtures covering the verdict table: accounted (marker postdates boot), pending (inside 2d window), overdue (past deadline → exit 5), second-member overdue, dark-boot exclusion, echoed-source exclusion (`${WEB_HOST_KEY_RAW}` unexpanded), supersession (newest boot wins), roster gate (host absent from `variables.tf` `web_hosts`), credential-missing → exit 3, transport failure → exit 3, xtrace+live cred → exit 78, never-0/never-1 sweep.
- [ ] 1.2 Write `scripts/followthroughs/web-first-deploy-10585.sh`: population via `gh run list`/`gh run view` emitted-line parse of the `Surface fresh-host Sentry breadcrumb trail` step; roster parse of `apps/web-platform/infra/variables.tf`; verdict via `scripts/betterstack-query.sh` `host_name` + `dt >= boot_ts` positive control + Deploy-succeeded marker; `FT10585_QUERY_SH` test seam; `RETIREMENT:` header; exit vocabulary 5/2/3/78 only.
- [ ] 1.3 Register `run_suite "scripts/web-first-deploy-10585" bash scripts/followthroughs/web-first-deploy-10585.test.sh` in `scripts/test-all.sh`; run `python3 scripts/regenerate-shard-manifest.py --incremental --write` and commit the regenerated `scripts/suite-shard-legs.tsv`.
- [ ] 1.4 Run `bash scripts/lint-followthrough-varq-ban.sh`, `bash scripts/followthrough-exec-bit.test.sh`, `bash scripts/followthrough-predicate-parity.test.sh`, and the orphan-suite gate on the new files — all clean.

## Phase 2 — Discoverability + docs

- [ ] 2.1 Add one line to the `web_host_replace` "Dispatch summary" step in `.github/workflows/apply-web-platform-infra.yml` naming the standing first-deploy tracker; verify the workflow still lints clean.
- [ ] 2.2 Add one line to `knowledge-base/engineering/operations/runbooks/web-host-replace.md` §"Verify the result": the replace's verification extends to first deploy via the standing tracker.
- [ ] 2.3 Add a one-line verification-coverage addendum to `knowledge-base/engineering/architecture/decisions/ADR-148-web-host-replacement-is-a-distinct-gated-dispatch.md`.
- [ ] 2.4 Optionally note the standing-watchdog shape in `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` (only if the pattern wants naming there).

## Phase 3 — Enrollment (ship-time, automated)

- [ ] 3.1 Pre-merge: `gh workflow run scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true`; read the new tracker's parse/exit line in the run log (no REQUIRED-SECRET-MISSING).
- [ ] 3.2 Post-merge: `gh issue create` the standing tracker — title `follow-through: every web-host replace/create owes a verified first deploy (watchdog for #10585)`, label `follow-through`, body with the column-0 unfenced directive `<!-- soleur:followthrough script=scripts/followthroughs/web-first-deploy-10585.sh earliest=<merge-ISO8601Z> secrets=GH_TOKEN,BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->`.
- [ ] 3.3 `gh issue close 10585` citing the tracker + merge run; PR body uses `Ref #10585` (not `Closes`).
- [ ] 3.4 Verify the first real sweep reports NOT YET or ACTION REQUIRED (never script-missing).
