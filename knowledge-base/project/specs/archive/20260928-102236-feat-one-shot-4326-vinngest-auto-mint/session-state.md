# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-27-feat-auto-mint-vinngest-tag-on-carrier-change-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
The planning subagent's first two `gh issue create` attempts were blocked by the issue-filing hooks: the body file had to exist first, and the body needed a `Mandated-By:` line. Both were fixed and retried, producing #9081 and #9082. Open risk R1 is unmeasured: whether GitHub refuses to create a tag ref on a commit touching `.github/workflows/*` when the token lacks `workflows` permission. Measuring it would need a tag write, which this session is not allowed to do.

### Decisions
- A new `mint-inngest-bootstrap-tag.yml` workflow, triggered by `push: main` (paths-filtered) plus `workflow_dispatch`. It compares HEAD's image inputs against the highest `vinngest-v*` tag merged into main: the 13 baked files, 4 pins and the Dockerfile block. Anchoring on the tag rather than on the previous push self-heals dropped runs.
- The next version is one patch above EVERY remote `vinngest-v*` tag (ADR-232 §7). A version component longer than 6 digits is refused.
- The tag is created with `GITHUB_TOKEN`, so no second build is triggered. The build is dispatched with an App installation token scoped to `actions:write` on this repo only. DC1 records that four reviewers preferred `GITHUB_TOKEN` for the dispatch as well. The operator's App-token direction is kept.
- ADR-232 gets a new §8 plus a dated amendment, and `model.c4` gets one sentence. No new ADR.
- #6766 sequencing: #9081 (a PR-context exemption for Guard A) is blocked by #4326 and blocks #6766. #9082 covers the residual gap for pin-only and Dockerfile-only changes.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; repo-research, learnings, best-practices, functional-discovery, git-history, cto, spec-flow, dhh/kieran/simplicity, security, architecture, test-design, observability, fable advisor consult.
