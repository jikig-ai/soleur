---
name: version
description: "Show the installed Soleur plugin version and whether a newer release exists"
argument-hint: ""
---

# Soleur Version

Report which Soleur plugin version is installed, what the latest release is, and how to update. Run the shared resolver; never guess or infer a version yourself.

This explicit run contacts github.com (one `git ls-remote` against the public repo and, for a commit-hash install, one unauthenticated compare API call, 8 second timeout) regardless of `SOLEUR_UPDATE_CHECK`, because you asked. It sends no tokens and no user data.

## Step 1: Run the resolver

Run via the **Bash tool**:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-version.sh" --compare --refresh
```

If `CLAUDE_PLUGIN_ROOT` is not set or the script does not exist there, use `plugins/soleur/scripts/plugin-version.sh` (monorepo checkout). The output is `key=value` lines: `source`, `version`, `commit`, `cache`, `latest_status`, `latest`, `latest_commit`, `relation`, `reason`. Use only these values.

## Step 2: Print this block

Print the block below, filling it from the resolver output. Keep it compact, no emoji.

```text
Soleur plugin version

Installed:  <version, or "commit <sha12>">  (source: <manifest | commit>)
Latest:     <latest, e.g. v3.4.5>   (or the WHY line from the rules below)
Status:     <one status line from the rules below>

Update (Claude Code):
  claude plugin marketplace update soleur-marketplace
  claude plugin update soleur@soleur-marketplace
  Restart the CLI afterwards; plugin changes apply on restart.

Session-start check (off by default): set SOLEUR_UPDATE_CHECK=1 in the Claude Code
settings "env" block to show this at session start; remove it to turn it off.
```

### Installed line

- `source=manifest`: print `version`. Add the note "a new release can take up to ~2 hours to reach `plugin update` while its version stamp merges" only for this source.
- `source=commit`: print `commit <commit>` (the 12-character hash). Do not invent a version number for it.
- `source=unknown` or `source=none`: print `Installed:  unknown` and say the plugin root could not be identified (not running from an installed plugin or a recognizable cache directory). Do not print a version.

### Latest line (explain WHY when missing)

When `latest=` is present, print it. When it is absent, print the reason, never a blank:

- `latest_status=offline`: "Could not reach github.com (offline or blocked)."
- `latest_status=timeout`: "The lookup timed out after 8 seconds."
- `latest_status=no-git`: "`git` is not installed, so the release lookup was skipped."
- `latest_status=no-tags`: "github.com answered but returned no release tags."
- `cache=corrupt`: "The version cache at `~/.cache/soleur/latest-release` is unreadable; it is rewritten on the next successful lookup."
- Anything else: "The latest release could not be determined."

If `latest_status` is `offline` or `timeout` but a `latest=` value still came from a `cache=stale` entry, print it and label it "(cached, may be out of date)".

### Status line (compare result)

Read `relation`:

- `relation=older`: "A newer release exists."
- `relation=current`: "You are up to date."
- `relation=unknown`: "Cannot compare" plus the reason: `installed-unknown` (installed version could not be read), `diverged` (installed commit is not on the release line), `compare-failed` or `compare-unparseable` (the GitHub compare call failed), `no-curl` (curl is missing), `cache-for-different-install` (cached result belongs to a different install). **Never** say "up to date" when the relation is unknown or absent, and never infer it by comparing strings yourself.

### Update commands by harness

- **Claude Code:** print the two `claude plugin` commands above. If the install is project-scoped (`claude plugin list` shows Scope), add `--scope project` to the update command. See `knowledge-base/engineering/operations/runbooks/plugin-delivery-recovery.md` if an update says "already at the latest version" but nothing changes.
- **Other harnesses** (Codex, Cursor CLI, Devin CLI, Grok Build): do not print `claude plugin` commands. Replace the "Update" section with that harness's own reinstall pointer if one exists in `plugins/soleur/codex/INSTRUCTIONS.md`, `plugins/soleur/cursor/INSTRUCTIONS.md` or the repository README, otherwise omit the section. See `commands/help.md` Step 2.5 for how to detect the harness. Print the command name in the harness's form (for example `/version` on Grok Build).

## Output Rules

- Print only values the resolver returned or the fixed text above; never report a version you did not read.
- Do not run `gh`, `curl` or `git` yourself; the resolver owns every network call.
- If the Bash tool is unavailable, say so and print only `Installed:` from the plugin root directory name if it is a 12-character hex commit hash; otherwise print `unknown`.
