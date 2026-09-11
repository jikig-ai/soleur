# Tasks — feat-one-shot-7946-sentry-org-token-retire

Derived from `knowledge-base/project/plans/2026-09-11-feat-sentry-org-token-retire-plan.md`
(post plan-review). Closes #7946 and #7993. Prod writes W1–W6 are per-command authorized; the
headless pipeline halts at 2.1 (W1, W2) and at 5.2 (W3, W4).

## Phase 0 — Preconditions (read-only)

- [ ] 0.1 Re-confirm populations: 16 files name `SENTRY_AUTH_TOKEN`; 13 carry `:+x`; 13 in the Rule D baseline plus `fresh-host-boot-trail.sh` at line 27; `bash scripts/lint-followthrough-varq-ban.sh` → `clean (N …)`, record N. Sweep `git grep -n 'SENTRY_AUTH_TOKEN' -- '*.test.sh' '*.test.ts' '.github/workflows/*.yml'` for claims a rename falsifies; add any hit to Files to Edit.
- [ ] 0.2 Write `specs/feat-one-shot-7946-sentry-org-token-retire/phase-0-scope-probe.md` from the 2026-09-11 reading (statuses + scope names only; no hashes, no values).
- [ ] 0.3 Confirm `agent-browser --version` (primary); MCP fallback only if it connects. Confirm `jq '.hooks.PreToolUse' plugins/soleur/hooks/hooks.json` names `browser-snapshot-credential-guard.sh`.
- [ ] 0.4 Enumerate trackers naming the retired secret (open, `--limit 200`; closed within 14 days). Stage rewritten bodies in `<scratchpad>/directive-rewrites/<n>.md`; record the before/after table and a resume recipe in `session-state.md`. No committed fixture.

## Phase 1 — RED tests first

- [ ] 1.1 Guard 1 cases in `scripts/lint-followthrough-varq-ban.test.sh`: M1 exec line, M2 second file, M3 `.test.sh`, M4 comment, M5 sandbox-copy mutation emptying rule 2's walk → exit 2 naming rule 2; H2 must-PASS non-canonical, H3 empty sandbox, H4 live tree. Add the ADR-193 floor the suite lacks (`MIN_ASSERTIONS` re-measured).
- [ ] 1.2 Guard 2 fixtures `scripts/fixtures/shell-trace-refusal/violation-empty-predicate-double.sh` (`[ -n "" ]`), `…-single.sh` (`[[ -n '' ]]`); cases M1, M2, M3 (`mutate_row` sed-copy with the predicate check removed → M1 fixture 1→0) in `scripts/lint-shell-trace-credential-refusal.test.sh`; H2 = existing `compliant-indirect-unconditional.sh`; bump `MIN_ASSERTIONS` from 61.
- [ ] 1.3 Guard 3 cases in `scripts/sweep-followthroughs.test.sh`, each running `bash "$SUT"` end to end (never `source; main`) against a stub `gh` that captures `issue comment` stdin: M1 missing → captured comment + `::error::` + `rc!=0`; M2 second tracker; M3 sed-copy with `MISSING_SECRET=1` deleted → rc 0 (+ diff proving mutation); M4 `DRY_RUN=1` → no comment, `::error::` logged, `rc!=0`; M5 `a[$(touch "$T/pwned")]` → refused before expansion, sentinel absent; M6 bound-but-empty → reported; H2 two names set and non-empty (one not GH_TOKEN) → forwarded; H3 no `secrets=`. Add the ADR-193 floor the suite lacks.
- [ ] 1.4 Retarget AC13 in `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh`: script reads `SENTRY_ACTIONS_RO_TOKEN` from env; the unbound case is anchored on the `echo "::warning::…"` call AND the `tee -a "$GITHUB_STEP_SUMMARY"` write carrying the sentence; zero `doppler` calls in the script; both `apply-web-platform-infra.yml` boot-trail steps bind the secret and no longer carry `DOPPLER_TOKEN` (reuse the AC8d awk at `:357-374`).

## Phase 2 — Mint and store (W1, W2 — first headless checkpoint)

- [ ] 2.0 Write `scripts/rotate-sentry-actions-ro-token.sh` (xtrace refusal; `mktemp -d` 0700 + timestamp marker; `trap … EXIT INT TERM HUP` with logged shred failure; capture → tolerant normalise asserting non-empty / no whitespace / 40-256 chars and logging only the length → `gh secret set SENTRY_ACTIONS_RO_TOKEN` on stdin, **no `--body`** → `gh secret list` presence → per-consumer endpoint probes with the bearer read from a header FILE (`-H @"$TOKEN_DIR/hdr"`, never argv) → shred; MCP-fallback branch moves the file from `.playwright-mcp/` into `$TOKEN_DIR`, fails if absent, shreds newer files there; dry-run is a separate flag and the only place `--no-store` appears).
- [ ] 2.0a Dry run, zero writes: sentinel page over `python3 -m http.server --bind 127.0.0.1`; capture + normalise `diff`-identical to `ZZQP-SENTINEL-7947`; `printf '%s' "$SENTINEL" | gh secret set ZZ_DRYRUN --no-store | wc -c` matches the computed ciphertext length; sentinel in no tool result; directory removed. Record in `session-state.md`.
- [ ] 2.1 **W1** — mint `actions-read-prd` at `https://jikigai-eu.sentry.io/settings/developer-settings/new-internal/`: Issue & Event = Read, Organization = Read, Project = Read, all else No Access, no webhook. Auth handoff only if the session has expired; nothing typed as an MCP argument; every snapshot via `filename:` + redactor; no snapshot/screenshot of the token panel. Sentry auto-issues the first token on save — capture that one; if missed, create a second and revoke the first; assert the panel holds exactly one before 2.3.
- [ ] 2.2 **W2** — run the rotation script live (one Bash process on the `agent-browser` path). On failure revoke the token in-page before the trap fires.
- [ ] 2.3 Verify before any file consumes it: `.auth.scopes` sorted == `[event:read, org:read, project:read]`; every consumer's exact host + org + path at 200 (sentry.io org/events/checkins ×3 slugs, regionUrl project issues, de.sentry.io project events). On a mismatch: edit permissions in-page, re-read scopes on the same token; if unchanged, revoke, recreate, re-run 2.2. Record in `phase-0-scope-probe.md`.

## Phase 3 — GREEN

Commit 1 (old name, mechanical):
- [ ] 3.3a Rule D remediation on the 13 baselined followthroughs using the lint's per-site remedy; delete their baseline lines.
- [ ] 3.3b Org slug: `sentry-checkins-3859.sh` → `jikigai-eu`; `sync-health-residual-5689.sh` default → `jikigai-eu` (pinned per Rule D).
- [ ] 3.5a Boot-trail `:177` curl to Rule D form; delete baseline line 27.
- [ ] 3.3c `git-data-birth-emitter-6982.sh`: add the unconditional refusal; delete its A/B/C baseline line.

Commit 2 (rename + guards + sweeper, one commit — `test-all.sh:1811` runs Guard 1 live):
- [ ] 3.1 Sweeper env: `SENTRY_ACTIONS_RO_TOKEN: ${{ secrets.SENTRY_ACTIONS_RO_TOKEN }}`; drop the old line; comment names the integration, ADR-031, and "not mirrored to Doppler" without spelling the retired name. Update `scripts/sweep-followthroughs.sh:28` header comment.
- [ ] 3.1b Guard 3 in `scripts/sweep-followthroughs.sh` `secrets=` loop: (a) validate `[[ "$name" =~ ^[A-Z][A-Z0-9_]*$ ]]` BEFORE any `${!name…}` expansion; (b) treat set-but-empty (`[[ -z "${!name:-}" ]]`) as missing ("bound but empty"); (c) collect all missing/malformed names, post ONE comment built from validated names only (existing `gh issue comment … --body-file -` shape, `|| fail`, honours `DRY_RUN`), emit `::error::` (also under DRY_RUN), set `MISSING_SECRET=1`; the `BASH_SOURCE == $0` block reads it beside `TRUNCATED_SWEEP` and exits 1.
- [ ] 3.2 Guard 1 in `scripts/lint-followthrough-varq-ban.sh`: second loop over `*.sh` incl. `.test.sh` and comments, `grep -nF 'SENTRY_AUTH_TOKEN'`, own `scanned_rule2` counter, same floor and exit contract; header `RULE 2` paragraph.
- [ ] 3.3d Rename in all 16 files: consumption, TRANSIENT guard form kept, `:+x` predicate in the 13, `.test.sh` stubs and comments (`anthropic-admin-key-6297.test.sh:109,253,279`; `zot-soak-6122.test.sh:141,302`), 6982's comment rewritten to name the consumer.
- [ ] 3.3e (after commit 1's pins) Exercise each of the 14 `.sh` once via `env -i PATH=… HOME="$HOME" bash -c 'export SENTRY_ACTIONS_RO_TOKEN="$(doppler secrets get SENTRY_IAC_AUTH_TOKEN -p soleur -c prd --plain)"; …; exec bash "$0"' <probe>` (value never on argv); record rc AND the observed HTTP status per script in `session-state.md`; `NOT EXERCISED` rows re-run; no curl usage error / HTTP 000 / 4xx TRANSIENT.
- [ ] 3.4 Guard 2 in `check_rule_c`: report `\[\[?\s+-n\s+(""|'')\s+\]\]?` before the `":+" not in window` return.
- [ ] 3.5b Boot-trail: read `SENTRY_ACTIONS_RO_TOKEN` from env; drop ALL three Doppler reads and `::add-mask::`; hardcode `jikigai-eu` / `web-platform`; when unbound emit `::warning::` + the same sentence via `tee -a "$GITHUB_STEP_SUMMARY"`, exit 0; both `apply-web-platform-infra.yml` boot-trail steps gain the `env:` binding, lose `DOPPLER_TOKEN`, and the step comment says why.
- [ ] 3.6 Runbook `knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md`: closed API path (and the `org:write` `POST …/api-tokens/` rung as a possible future, not taken); Bash-path-primary browser rung with profile + auth handoff + why (trap scope; `.playwright-mcp/` on the MCP path); script by reference; scopes equality + per-consumer probe; order store → dispatch → verdicts → revoke old (auto-issued token; 20 max; check count); cadence "on incident or scope change"; dry run = `gh workflow run scheduled-followthrough-sweeper.yml -f dry_run=true`; IaC-mirror assignment as last resort with caveat; `/tmp` tmpfs note; `## Failure modes` table incl. "integration/token deleted dashboard-side — 401 vs 403", one row per enumerated mode, next action per row; no `ssh `.
- [ ] 3.7 Docs by claim: `followthrough-convention.md` (3 occurrences + Guard 1 census row), `plugins/soleur/skills/schedule/SKILL.md:76`, sweeper `env:` comment.

## Phase 4 — ADR, post-mortem, register, deferrals

- [ ] 4.6 **W5** (pre-merge) — `gh issue create` ×2: personal-token revocation (readers enumerated incl. `cutover-verify.sh:318`; recommended shape: replace the value under the canonical name with the `iac-terraform-prd` token; `DOPPLER_TOKEN` reachability note; `Ref #7797`, `Ref #7946`); `rotate-x-api-secret-bootstrap.sh:56` `--body -` defect with the ciphertext-length evidence.
- [ ] 4.1 Amend `ADR-031-sentry-as-iac.md`: fourth class, permission set + returned scopes, store discriminator and its accurate cost (same-repo branch workflows by write collaborators; the two live `pull_request_target` workflows bind no Sentry secret; `event:read` reaches prod event context), environment-secret alternative with corrected cost, AP-008 divergence, surface distinction, DC-3 record incl. the rejected IaC-under-new-name shape, narrow-by-adding rule, mint path + the `org:write` API rung not taken, cadence, dry-run path, Doppler-unsatisfiable consequence, dashboard-drift and dashboard-deletion gaps (403 vs 401), duplicated-ordinal header note.
- [ ] 4.2 Post-mortem: append `## Addendum — <date> (#7946)` superseding `### Still open` and the 2026-09-07 ADR-031 sentence; cite both deferral numbers; nothing above changes.
- [ ] 4.3 Append `## DC-3 — RESOLUTION` to the 2026-09-09 spec's `decision-challenges.md` (reading + pointer to ADR-031).
- [ ] 4.4 `article-30-register.md` PA-8 §(g) dated bracket; `compliance-posture.md` Completed row; `bash scripts/lint-legal-registers.sh`.
- [ ] 4.5 C4: no edit; run `bash plugins/soleur/test/c4-count-parity.test.sh` green.

## Phase 5 — Verification and ship

- [ ] 5.1 Walk AC-1 … AC-24 with each command verbatim; record outputs.
- [ ] 5.2 (ship, post-merge, second headless checkpoint) **W6** observed (push-triggered infra apply, expected no-op; do not re-dispatch `apply-web-platform-infra.yml`); **W3** re-run the open + closed-within-14d queries, diff live bodies against staged "before", `gh issue edit <n> --body-file <staged>`; **W4** `gh workflow run scheduled-followthrough-sweeper.yml`, record `createdAt`, wait; assert AC-P1 (timestamp-gated comments on #6604, #6297, #5689; run log has no `required secret`) and AC-P2 (census queries return 0; before/after table in the PR body).
- [ ] 5.3 PR body: `Closes #7946`, `Closes #7993`; render this branch's `decision-challenges.md` (DC-4, DC-5) per ship Phase 6.
