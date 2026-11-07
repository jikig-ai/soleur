# Tasks — feat-one-shot-11532-xtrace-guard-fallback-probe

Derived from `knowledge-base/project/plans/2026-10-29-fix-xtrace-refusal-fallback-probe-plan.md`.

## 1. Setup

- [x] 1.1 Verify branch `feat-one-shot-11532-xtrace-guard-fallback-probe`, worktree, PR #11543 (draft) — done at plan time.

## 2. Core Implementation

### 2.1 xtrace refusal (closes #11532)

- [x] 2.1.1 Insert `case "$-" in *x*) ... exit 78` block in `scripts/content-publisher.sh` immediately after `set -euo pipefail` (:36), modeled on `scripts/followthroughs/cron-machinery-soak-9272.sh:35-46`; predicate covers `BSKY_APP_PASSWORD`, `LINKEDIN_ACCESS_TOKEN`, `LINKEDIN_ORG_ACCESS_TOKEN`, `LINKEDIN_TRACKER_REASON_MISSING_TOKEN`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET`, `X_API_KEY`, `X_API_SECRET`, `DISCORD_BLOG_WEBHOOK_URL`, `DISCORD_WEBHOOK_URL`, `GH_TOKEN` via concatenated `${VAR:+x}` limbs.
- [x] 2.1.2 Delete the `scripts/content-publisher.sh` row from `scripts/lint-shell-trace-credential-refusal.baseline.txt`.
- [x] 2.1.3 Verify: `python3 scripts/lint-shell-trace-credential-refusal.py scripts/content-publisher.sh` → 0; `--changed` → 0.

### 2.2 Probe + harness + registration

- [x] 2.2.1 Create `scripts/followthroughs/discord-blog-webhook-fallback.sh` per the plan's canonical contract (header with exit vocabulary + CREDENTIAL POSTURE + RETIREMENT; xtrace refusal over `SENTRY_ACTIONS_RO_TOKEN`/`GH_TOKEN`; TLS-subversion prologue; `_bearer_ok`; `_sentry_get`; `jikigai-eu`/`de.sentry.io` pin + refusal; LIVENESS scan of `knowledge-base/marketing/distribution-content/*.md` → exit 2; Sentry events read → 1/0/3; never `${VAR:?}`; never the retired Sentry credential name). `chmod +x`. (One deviation noted in code comment: event timestamps are normalized `+00:00` → `Z` before `fromdateiso8601` — the serializer shape the events endpoint emits — so the FAIL arm can fire on real rows.)
- [x] 2.2.2 Create `scripts/followthroughs/discord-blog-webhook-fallback.test.sh` in the `post-deploy-incident-soak.test.sh` idiom covering the plan's case list.
- [x] 2.2.3 Run the new suite → green (29 assertions, 0 failures).
- [x] 2.2.4 Register `run_suite "scripts/followthroughs/discord-blog-webhook-fallback" bash scripts/followthroughs/discord-blog-webhook-fallback.test.sh` in `scripts/test-all.sh` beside sibling registrations, with rationale comment.
- [x] 2.2.5 `python3 scripts/regenerate-shard-manifest.py --incremental --write`; commit the resulting `scripts/suite-shard-legs.tsv` + `scripts/suite-durations.tsv` rows (17 rows — mine + 16 sibling registrations whose rows were never written on main; the tool is the only sanctioned writer).
- [x] 2.2.6 Run `bash scripts/lint-followthrough-varq-ban.sh` and `bash scripts/lint-orphan-test-suites.sh` → clean; declare `AFFECTED_SCRIPTS_FOLLOWTHROUGHS_DISCORD_BLOG_WEBHOOK_FALLBACK_PATHS` only if the census reports unclassified. (Census classified via name-stem derivation — no edge array needed. Fixture ratchets also run: fixture-relative-assert 63/63, fixture-dir-operand-assert 71/71, lint-shell-capture-exit --baseline 0 new findings.)
- [x] 2.2.7 Optional: `gh workflow run scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true` — SKIPPED: the sweeper execs probes from a checkout of main, and the probe does not exist on the pushed ref (or main) pre-merge, so a dry-run dispatch cannot reach it; nothing about the probe would be exercised.

### 2.3 Tracker issue + PR body

- [x] 2.3.1 `gh issue create` from the worktree: labels `follow-through` + `meta/machinery`, milestone `Post-MVP / Later`, body per plan (context paragraph + close-criteria + UNFENCED column-0 directive `script=… earliest=2026-11-03T15:30:00Z secrets=GH_TOKEN,SENTRY_ACTIONS_RO_TOKEN`). Tracker = **#11549**. (Directive gate resolves `script=` under HOOK_CWD = main checkout on Devin — filed after copying the probe there untracked per the convention's main-checkout caveat; untracked copy removed after filing.)
- [x] 2.3.2 PR #11543 body: `Closes #11532` on its own line + `Ref #11549` + `## Changelog`.

## 3. Testing

- [ ] 3.1 Run the affected-test selection for the touched scripts (`bash scripts/test-all.sh --affected`), including `scripts/content-publisher`, `scripts/content-publisher-residue`, `test/content-publisher`, the new probe suite, `lint-followthrough-varq-ban`, `lint-orphan-test-suites`, `lint-shell-trace-credential-refusal.test.sh`, argv-bearer-sweep.
- [x] 3.2 Confirm no `#11504` token in the diff or PR body; merged feature cited as `347d3812` only. (Code diff + PR body carry zero; the only `11504` occurrences are inside the plan/spec/tasks docs' own rule text, committed at plan time.)
