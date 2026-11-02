# launch-check self-test (plan Phase 3, dry-run)

Two samples, scan plus `render --dry-run`, report never written into either repository:
(a) this repository (`jikig-ai/soleur`, a public Next.js monorepo), (b) one public non-Soleur Node/TS library, `github.com/sindresorhus/is`, shallow-cloned to a scratch directory and discarded.

## Sample (a): this repository

First run found 8 gaps; triage below. After the fixes (commit "launch-check: self-test triage") the run reports 3, all dispositioned.

| Gap | Disposition |
|---|---|
| SEC-02 credential-bearing file tracked (1 file) | (b) detector false positive: the file was a public CA certificate (`cacert.pem`). Fixed: `.pem` counts only when its name says key, priv or secret. Test added. |
| BASE-secret-scan, BASE-commit-on-main, BASE-block-stash, BASE-orphan-test | (b) false positive for the guards' source repo: Soleur has the originals under their source paths, not the scaffold's emitted names. Fixed: the guard check also accepts all `source_files` of the manifest row, reporting "original form present, advisory/unverified". Test added. Customers never have those paths, so their result is unchanged. |
| DEBT-05 reported not-applicable | (b) monorepo limitation: only the root `package.json` was read. Fixed: any `package.json` and any `.dependency-cruiser.*` count. Tests added. |
| SEC-01 secret-shaped content, 9 findings | (c) expected on a monorepo with design assets and synthesized test fixtures: 7 are `.pen` design files, 1 a doc example in a skill file, 1 a shell test with a synthesized token. Count only, as designed; no tuning. |
| SEC-04 no Dependabot/Renovate config | (a) real gap in this repository (it relies on other update tooling); left as a finding. |
| DEBT-01 1147 debt markers | (c) accurate and low severity; most are in documentation and learnings. |

## Sample (b): public non-Soleur Node/TS library

13 gaps in 1.6 s. Plausible and non-empty: no committed lockfile and no dependency-update config (real), no deploy path, no pinned runtime file, no architecture notes. The four reliability checks (error tracking, health endpoint, backups, runbooks) read as gaps for a library; that is expected non-applicability (c) because launch-check targets deployed applications, and the skill says so under *Coverage and limits*. Tests (2 of 5 files) and CI test run were detected correctly, and its `AGENTS.md` satisfied DEBT-04.

## Acceptance

Every reported gap above has a recorded disposition and an evidence line. Run time on this repository: about 27 s (dominated by the gitleaks pass over a roughly 20k-file tree).
