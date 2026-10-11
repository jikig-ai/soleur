# Session State — feat-one-shot-9815-vitest-related

Issue: #9815 — `apps/web-platform [unit]` (+ `[repo-wide+component]`) run the
FULL vitest project on any app diff (~82s + ~80s); narrow local `--affected`
runs to `vitest related <changed app files>`, fail-safe to the full project on
config/meta changes or zero resolved files. CI unchanged.

Sequence position: #9763 → #9813 (merged) → #9814 (in merge queue, PR #9990) →
#9815 (this issue).

Status: plan written (2026-10-11) — `knowledge-base/project/plans/2026-10-11-feat-one-shot-9815-vitest-related-plan.md`
+ phased `tasks.md`; deepen-pass ran empirically against the pinned vitest
(4.1.11): the issue's `vitest run --related` spelling does NOT exist (real form
is the `vitest related <files> --run --project <p>` subcommand via
`node_modules/.bin/vitest`), zero-resolution exits 0 with the
`No test files found` marker (silent-green shape the wrapper greps), and
setupFiles/globalSetup are invisible to `related` (meta set covers them).
Ready for soleur:work.
