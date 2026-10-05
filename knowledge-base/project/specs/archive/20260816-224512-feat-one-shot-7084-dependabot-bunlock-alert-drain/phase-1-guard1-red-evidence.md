# Phase 1.2 — Guard 1 RED on the pre-fix tree (2026-08-16)

```
$ bash scripts/lint-dual-lockfile.sh
::error::lint-dual-lockfile: tracked bun lockfile: apps/web-platform/bun.lock. npm is the single lockfile of record (ADR-191); delete it and install with 'npm ci --ignore-scripts'. Leaving it re-creates the dual-lockfile split that makes every Dependabot PR born red (#7084).
::error::lint-dual-lockfile: tracked bun lockfile: bun.lock. npm is the single lockfile of record (ADR-191); delete it and install with 'npm ci --ignore-scripts'. Leaving it re-creates the dual-lockfile split that makes every Dependabot PR born red (#7084).
::error::lint-dual-lockfile: apps/web-platform/bunfig.toml declares an [install] section. bun is the test runner only (ADR-191) — keep [test], drop [install]. The supply-chain floor now lives in the per-directory .npmrc.
::error::lint-dual-lockfile: bunfig.toml declares an [install] section. bun is the test runner only (ADR-191) — keep [test], drop [install]. The supply-chain floor now lives in the per-directory .npmrc.
lint-dual-lockfile: scanned 13726 tracked files; 4 package-lock.json director(ies) (floor 4); 2 bunfig.toml; 2 bun lockfile(s).
::error::lint-dual-lockfile: 4 violation(s).
exit=1
```
