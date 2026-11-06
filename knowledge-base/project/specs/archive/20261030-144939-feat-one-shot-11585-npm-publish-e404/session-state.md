# Session State

## Review Phase

- Status: complete (2026-10-30). Reviewed PR #11598 inline — Devin CLI has no Task/Agent tool, so all seats ran SEQUENTIALLY INLINE against `git diff origin/main...HEAD`; trailer carries `Reviewed-Coverage: sequential-fallback` (13/13).
- Classification: `code` class (diff contains `plugins/soleur/test/npm-publish-oidc.test.sh`). Risk tier: `aggregate pattern` (source: plan) → mandatory design-validity pass (code-simplicity + architecture; no findings — every mechanism names a requirement) + user-impact seat (exited per its own `single-user incident` threshold contract) + structural-enumeration seat (guard-shaped diff) + test-design-reviewer + shellcheck (bash-only → semgrep skipped per skill).
- Pre-panel: branch was CONFLICTING vs main on generated `model.likec4.json`; resolved via `resolve-regenerable-conflicts.sh origin/main` → merge commit 13af23bffb (regenerated artifact retains `npmRegistry`; merge-tree rc=0). Collision precheck: PR #11598 is this pipeline's own; sibling test-all.sh runs unrelated.
- Findings: 4 total — 3 P2 / 1 P3, all `pr-introduced` (the guard is new in this PR), all fixed inline in `644a04e39b`:
  - [P2] `no-cred-wiring` narrower than its property: missed `jobs.publish.env`, top-level `env:`, run-body credential channels, and `packages/opencode-plugin/.npmrc`.
  - [P2] OIDC binding shape unpinned: `environment:` on the job and `self-hosted` `runs-on` each silently break trusted publishing.
  - [P2] `npm11-step`/`npm-publish-retained` pinned presence, not position/shape (install-after-publish reorder, bare `npm publish` both stayed green).
  - [P3] code-quality nits (`lambda` assignment → `def`).
- Fix: guard widened to 6 members + 13-row mutation matrix (20/20 green, shellcheck clean); assertion floor bumped 11 → 20.
- Files changed by fixes: `plugins/soleur/test/npm-publish-oidc.test.sh` (+128/−16).
- Trailers: `Reviewed-By-Soleur` on d665dcad84 (sequential-fallback 13/13, risk-tier aggregate pattern); `Reviewed-Fix-Round`/`Reviewed-Fix-Range` on 41f5075a71 over `13af23bffb..HEAD` (fix-round seats: structural-enumeration, test-design-reviewer, code-quality-analyst, shellcheck — all clean).
- Open code-review issues for PR #11598: none (`gh issue list --label code-review --search "PR #11598"` → empty; nothing was filed — all dispositions were fix-inline).
- Verdict: green — no blocking findings; branch pushed.
- Remaining: compound → ship → merge. Operator steps T1a/4.x (npm trust entry, first green publish, NPM_TOKEN retirement) remain post-merge per the plan.

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-11585-npm-publish-e404/knowledge-base/project/plans/2026-10-30-fix-npm-publish-e404-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None. (Deviation notes: `cloud-detect.sh` returned `not-local:no-devin-env` in the subagent → proceeded normally; Devin has no Task/Agent tool, so all agent roles — repo/learnings researchers, SpecFlow analyzer, domain leaders, CTO ruling, scoped advisor, reviewer panel — were executed inline per the technical-rulings clause; the sharp-edges catalogue was applied as a verification pass via extracted entry list + targeted reads rather than a full verbatim load, due to context budget.)

### Decisions
- Root cause re-anchored: the issue's "unclaimed @soleur scope" premise is disproven — `GET registry.npmjs.org/@soleur%2fopencode` returns 200 (maintainer `deruelle`, `latest` 3.363.0, ~60 versions); publish worked until 2026-10-29T20:02Z and the workflow file was unchanged. E404-on-PUT is npm's authz-masking signal; `NPM_TOKEN` untouched since 2026-10-22T21:55Z → ~7.0-day gap to first failure, consistent with a short-lived granular-token expiry.
- Ruled by CTO agent, 2026-10-30 (row T1): adopt npm OIDC trusted publishing — `id-token: write` + `npm@^11` install step in `npm-publish.yml`, drop `registry-url`/`NODE_AUTH_TOKEN` (the stale `.npmrc` `_authToken` can mask OIDC selection). Rejected: claim scope (moot), repoint to GitHub Packages (breaks public `npx`), remove leg (real channel), rotate token (keeps the expiry class).
- Operator step (row T1a): maintainer runs `npm trust github @soleur/opencode --file npm-publish.yml --repo jikig-ai/soleur --allow-publish` (interactive login; GAT-bypass-2FA unsupported), then retires `NPM_TOKEN` after first green publish.
- No backfill of versions 3.363.1–3.364.3 (row T2) — `latest` moves to the newest tag.
- Supporting deliverables: parsed-YAML wiring guard (`npm-publish-oidc.test.sh`, Guard Contract emitted), provisional ADR-310 (credential-boundary change; ordinal re-verified free on `origin/main`), C4 `npmRegistry` element + `github -> npmRegistry` edge + `model.likec4.json` regen (mandate: npm registry was unmodeled). `lane:` defaulted `cross-domain` (no spec.md — TR2 fail-closed); threshold `aggregate pattern`.

### Components Invoked
- Skills: `soleur:plan` (full run incl. Phases 0.6 premise validation, 0.6b mechanism minimality, 0.7 skeleton, 2.4 scope check, 2.5 domain review, 2.6–2.12 gates, 6.5 sharp-edges pass), `soleur:deepen-plan` (all halt gates: 4.6 user-brand, 4.7 observability, 4.8 PAT sweep, 4.9 UI-wireframe skip, 4.10 encryption skip, 4.11 `lint-guard-contract.py` green, 4.12 scope check green, 4.13 skip; citation verifications + Enhancement Summary written)
- Agents (inline role execution): `soleur:engineering:cto` (Rule interface → `decision-challenges.md` rows T1/T1a/T2), `soleur:product:spec-flow-analyzer`, engineering/operations domain leaders, research agents
- Artifacts: plan (deepened), `tasks.md`, `decision-challenges.md` — all committed (`7026b4f6b1..aeb29c416e`) and pushed to `feat-one-shot-11585-npm-publish-e404`; markdownlint 0 issues; collision precheck reported (PR #11598 = this pipeline's own draft; foreign proc unrelated)
