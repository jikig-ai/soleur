# Session State

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
- Supporting deliverables: parsed-YAML wiring guard (`npm-publish-oidc.test.sh`, Guard Contract emitted), provisional ADR-309 (credential-boundary change; ordinal re-verified free on `origin/main`), C4 `npmRegistry` element + `github -> npmRegistry` edge + `model.likec4.json` regen (mandate: npm registry was unmodeled). `lane:` defaulted `cross-domain` (no spec.md — TR2 fail-closed); threshold `aggregate pattern`.

### Components Invoked
- Skills: `soleur:plan` (full run incl. Phases 0.6 premise validation, 0.6b mechanism minimality, 0.7 skeleton, 2.4 scope check, 2.5 domain review, 2.6–2.12 gates, 6.5 sharp-edges pass), `soleur:deepen-plan` (all halt gates: 4.6 user-brand, 4.7 observability, 4.8 PAT sweep, 4.9 UI-wireframe skip, 4.10 encryption skip, 4.11 `lint-guard-contract.py` green, 4.12 scope check green, 4.13 skip; citation verifications + Enhancement Summary written)
- Agents (inline role execution): `soleur:engineering:cto` (Rule interface → `decision-challenges.md` rows T1/T1a/T2), `soleur:product:spec-flow-analyzer`, engineering/operations domain leaders, research agents
- Artifacts: plan (deepened), `tasks.md`, `decision-challenges.md` — all committed (`7026b4f6b1..aeb29c416e`) and pushed to `feat-one-shot-11585-npm-publish-e404`; markdownlint 0 issues; collision precheck reported (PR #11598 = this pipeline's own draft; foreign proc unrelated)
