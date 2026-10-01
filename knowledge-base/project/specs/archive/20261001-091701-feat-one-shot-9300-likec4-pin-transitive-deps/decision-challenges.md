# Decision challenges (plan-review, headless) - feat-one-shot-9300-likec4-pin-transitive-deps

Taste items the plan did not auto-apply. `ship` renders these into the PR body and files the issue.

## 1. Pin the Dockerfile's likec4 install in this PR (DHH, P1)

- Reviewer position: add `--before=2026-09-28` to `apps/web-platform/Dockerfile` now. A CDN 404 in the release image build is worse than a red CI shard, and CI would otherwise test a tree production does not ship.
- Plan position: defer. The Dockerfile change alters release-image contents with no PR-time test of the runner stage (PR CI builds only the `builder` target), and the CI failure being fixed does not involve it.
- Default taken: defer, with a tracking issue (Phase 4). Reversible: it is a one-line follow-up edit.

## 2. `scripts/bump-likec4-pin.sh` (CTO advisory, P1)

- Reviewer position: automate the version+date bump across all sites.
- Default taken: no script; the guard's failure message and the `BUMPING LIKEC4` header section carry the procedure.

## 3. Non-failing stale-date warning (CTO advisory, P1)

- Reviewer position: warn when the date is more than about 180 days old, because the frozen tree no longer receives transitive security fixes.
- Default taken: none; the plan states a bump policy (with a likec4 bump, or sooner on a transitive advisory affecting the CLI). Re-evaluate if the date is ever forgotten twice.
