# Decision challenges (plan phase, 2026-10-22)

Headless plan run. No operator-direction challenge arose: the brief is fully specified and no reviewer finding argues for a different scope. Technical choices were resolved without an operator question.

| Item | Class | Ruling |
|------|-------|--------|
| Bring the runbook in by cherry-pick of `f0fe42d2b9` versus copy of the `/var/tmp` backup | technical | Ruled by CTO agent, 2026-10-22: Copy the /var/tmp backup into the PR branch, with cherry-pick as the fallback - backup and f0fe42d2b9 both hash to 1076fca7...4504, so the bytes are identical, and copying avoids carrying the scratch commit's history into a squash-merged PR. |
| `git branch -D` (force) for the scratch branch | technical | Ruled by CTO agent, 2026-10-22: Use `git branch -D` on deleg-env-10789 only after the PR exists, the PR branch with the sha256-verified copy is pushed, and the scratch worktree is clean - the content is also in the /var/tmp backup and will be in the PR, so nothing is lost. |
| Skip the plan-review panel and external research | technical | Ruled by CTO agent, 2026-10-22: Skip the plan-review panel and external research - the change is one byte-pinned file plus one ignore line, so a sha256 equality check and CI lint are the real controls; the usual ship-time review still applies. |
