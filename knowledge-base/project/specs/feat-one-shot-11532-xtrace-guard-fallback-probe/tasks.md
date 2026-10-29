# Tasks — feat-one-shot-11532-xtrace-guard-fallback-probe

Derived from `knowledge-base/project/plans/2026-10-29-fix-xtrace-refusal-fallback-probe-plan.md`.

## 1. Setup

- [x] 1.1 Verify branch `feat-one-shot-11532-xtrace-guard-fallback-probe`, worktree, PR #11543 (draft) — done at plan time.

## 2. Core Implementation

### 2.1 xtrace refusal (closes #11532)

- [ ] 2.1.1 Insert `case "$-" in *x*) ... exit 78` block in `scripts/content-publisher.sh` immediately after `set -euo pipefail` (:36), modeled on `scripts/followthroughs/cron-machinery-soak-9272.sh:35-46`; predicate covers `BSKY_APP_PASSWORD`, `LINKEDIN_ACCESS_TOKEN`, `LINKEDIN_ORG_ACCESS_TOKEN`, `LINKEDIN_TRACKER_REASON_MISSING_TOKEN`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET`, `X_API_KEY`, `X_API_SECRET`, `DISCORD_BLOG_WEBHOOK_URL`, `DISCORD_WEBHOOK_URL`, `GH_TOKEN` via concatenated `${VAR:+x}` limbs.
- [ ] 2.1.2 Delete the `scripts/content-publisher.sh` row from `scripts/lint-shell-trace-credential-refusal.baseline.txt`.
- [ ] 2.1.3 Verify: `python3 scripts/lint-shell-trace-credential-refusal.py scripts/content-publisher.sh` → 0; `--changed` → 0.

### 2.2 Probe + harness + registration

- [ ] 2.2.1 Create `scripts/followthroughs/discord-blog-webhook-fallback.sh` per the plan's canonical contract (header with exit vocabulary + CREDENTIAL POSTURE + RETIREMENT; xtrace refusal over `SENTRY_ACTIONS_RO_TOKEN`/`GH_TOKEN`; TLS-subversion prologue; `_bearer_ok`; `_sentry_get`; `jikigai-eu`/`de.sentry.io` pin + refusal; LIVENESS scan of `knowledge-base/marketing/distribution-content/*.md` → exit 2; Sentry events read → 1/0/3; never `${VAR:?}`; never `SENTRY_AUTH_TOKEN`). `chmod +x`.
- [ ] 2.2.2 Create `scripts/followthroughs/discord-blog-webhook-fallback.test.sh` in the `post-deploy-incident-soak.test.sh` idiom covering the plan's case list.
- [ ] 2.2.3 Run the new suite → green.
- [ ] 2.2.4 Register `run_suite "scripts/followthroughs/discord-blog-webhook-fallback" bash scripts/followthroughs/discord-blog-webhook-fallback.test.sh` in `scripts/test-all.sh` beside sibling registrations, with rationale comment.
- [ ] 2.2.5 `python3 scripts/regenerate-shard-manifest.py --incremental --write`; commit the resulting `scripts/suite-shard-legs.tsv` + `scripts/suite-durations.tsv` rows.
- [ ] 2.2.6 Run `bash scripts/lint-followthrough-varq-ban.sh` and `bash scripts/lint-orphan-test-suites.sh` → clean; declare `AFFECTED_SCRIPTS_FOLLOWTHROUGHS_DISCORD_BLOG_WEBHOOK_FALLBACK_PATHS` only if the census reports unclassified.
- [ ] 2.2.7 Optional: `gh workflow run scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true` and read the tracker `exit=` line.

### 2.3 Tracker issue + PR body

- [ ] 2.3.1 `gh issue create` from the worktree: labels `follow-through` + `meta/machinery`, milestone `Post-MVP / Later`, body per plan (context paragraph + close-criteria + UNFENCED column-0 directive `script=… earliest=2026-11-03T15:30:00Z secrets=GH_TOKEN,SENTRY_ACTIONS_RO_TOKEN`). Record issue number.
- [ ] 2.3.2 PR #11543 body: `Closes #11532` on its own line + `Ref #<tracker>`.

## 3. Testing

- [ ] 3.1 Run the affected-test selection for the touched scripts (`bash scripts/test-all.sh --affected`), including `scripts/content-publisher`, `scripts/content-publisher-residue`, `test/content-publisher`, the new probe suite, `lint-followthrough-varq-ban`, `lint-orphan-test-suites`, `lint-shell-trace-credential-refusal.test.sh`, argv-bearer-sweep.
- [ ] 3.2 Confirm no `#11504` token in the diff or PR body; merged feature cited as `347d3812` only.
