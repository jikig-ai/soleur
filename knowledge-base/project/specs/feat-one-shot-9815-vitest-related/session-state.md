# Session State — feat-one-shot-9815-vitest-related

Issue: #9815 — `apps/web-platform [unit]` (+ `[repo-wide+component]`) run the
FULL vitest project on any app diff (~82s + ~80s); narrow local `--affected`
runs to `vitest related <changed app files>`, fail-safe to the full project on
config/meta changes or zero resolved files. CI unchanged.

Sequence position: #9763 → #9813 (merged) → #9814 (in merge queue, PR #9990) →
#9815 (this issue).

Status: worktree + branch created; planning pending.
