## File Scopes

| Agent | Files |
|-------|-------|
| Agent 1 (Code) | `.codex/config.toml`, `.devin/config.json` |
| Agent 2 (Tests) | `plugins/soleur/test/repo-hook-launchers.test.ts` |

## Public Interfaces

The interface is each existing repository hook's configured shell command, parsed from its native registry. No new executable, matcher, hook target or public function is introduced.

- Codex commands derive the selected repository root from Git. Devin preserves `CLAUDE_PROJECT_DIR`, then `DEVIN_PROJECT_DIR`, then Git precedence; empty overrides fall through.
- Git discovery first tries `git rev-parse --show-toplevel`. Only after that fails and Git positively reports a bare repository, use `--absolute-git-dir` and strip a terminal `/.git`. Keep conventional bare-directory paths unchanged.
- Assign the selected root once; failed root assignment stops before target execution. No target-absence fallback to a common checkout, sibling worktree or filesystem root.
- Invoke exactly the original interpreter and target with original trailing arguments. Preserve stdin bytes, stdout, stderr and exit status; do not change the working directory or consume stdin during discovery.
- Execute real registry commands against synthetic ordinary, nested, linked-worktree, Soleur-style bare and conventional-bare repositories, including spaces. Distinct checkout markers must detect selection of shared-root bytes in place of worktree bytes.
- Test invalid environment overrides, missing selected targets, non-repositories, failed non-bare discovery, input/output and nonzero statuses, plus structural enumeration of all affected registrations.
- Claude/Grok's existing project-environment launchers are compatibility controls. Cursor's existing absence of repository hook support is a boundary, not a new feature.
- Use existing fixture Git isolation. All fixture identities and data must be synthesized. Tests must not operate on PR #9051, live services, providers, containers or accounts.
