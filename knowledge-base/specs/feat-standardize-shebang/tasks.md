# Tasks: standardize shebang to #!/usr/bin/env bash

Source: `knowledge-base/plans/2026-03-03-chore-standardize-shebang-env-bash-plan.md`
Issue: #403

## Phase 1: Shell Convention Fixes

- [x] 1.1 Update `.claude/hooks/guardrails.sh` shebang from `#!/bin/bash` to `#!/usr/bin/env bash`
- [x] 1.2 Update `.claude/hooks/worktree-write-guard.sh` shebang from `#!/bin/bash` to `#!/usr/bin/env bash`
- [x] 1.3 Update `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` shebang from `#!/bin/bash` to `#!/usr/bin/env bash`
- [x] 1.4 Update `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` from `set -e` to `set -euo pipefail`
- [x] 1.5 Update `plugins/soleur/skills/rclone/scripts/check_setup.sh` shebang from `#!/bin/bash` to `#!/usr/bin/env bash`
- [x] 1.6 Update `plugins/soleur/skills/rclone/scripts/check_setup.sh` from `set -e` to `set -euo pipefail`
- [x] 1.7 Fix `check_setup.sh` line 27: `[ -z "$REMOTES" ]` to `[[ -z "$REMOTES" ]]`

## Phase 2: Validation

- [x] 2.1 Run `grep -r '#!/bin/bash' --include='*.sh'` and confirm zero results
- [x] 2.2 Run `bun test` and confirm all tests pass
- [x] 2.3 Verify `guardrails.sh` still blocks commits on main
- [x] 2.4 Verify `worktree-write-guard.sh` still blocks writes to main repo
- [x] 2.5 Verify `worktree-manager.sh cleanup-merged` still executes correctly

## Phase 3: Version Bump and Ship

- [ ] 3.1 Run `soleur:compound` before commit
- [ ] 3.2 PATCH version bump in `plugin.json`, `CHANGELOG.md`, `README.md`
- [ ] 3.3 Commit, push, and create PR referencing #403
