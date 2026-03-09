# Tasks: fix discord recursive 429 retry depth

## Phase 1: Core Fix

- [ ] 1.1 Add `depth` parameter to `discord_request()` in `discord-community.sh`
  - [ ] 1.1.1 Add `local depth="${2:-0}"` after `local endpoint="$1"`
  - [ ] 1.1.2 Add depth guard: exit 2 when `depth >= 3`
  - [ ] 1.1.3 Update 429 handler to pass `$((depth + 1))` to recursive call
  - [ ] 1.1.4 Update 429 log message to include attempt count `(attempt N/3)`

- [ ] 1.2 Add `depth` parameter to `discord_request()` in `discord-setup.sh`
  - [ ] 1.2.1 Add `local depth="${4:-0}"` after the existing 3 parameters
  - [ ] 1.2.2 Add depth guard: exit 2 when `depth >= 3`
  - [ ] 1.2.3 Update 429 handler to pass `$((depth + 1))` to recursive call
  - [ ] 1.2.4 Update 429 log message to include attempt count `(attempt N/3)`

## Phase 2: Verification

- [ ] 2.1 Verify backward compatibility: confirm all callers pass no depth argument
  - [ ] 2.1.1 Grep for `discord_request` calls in `discord-community.sh`
  - [ ] 2.1.2 Grep for `discord_request` calls in `discord-setup.sh`
- [ ] 2.2 Run `shellcheck` on both modified scripts (if available)
- [ ] 2.3 Run `markdownlint` on plan file

## Phase 3: Ship

- [ ] 3.1 Run compound
- [ ] 3.2 Commit, push, create PR with `Closes #472`
