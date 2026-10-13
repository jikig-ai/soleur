---
name: version
description: "Show the installed Soleur plugin version and whether a newer release exists"
argument-hint: ""
disable-model-invocation: true
---

# Soleur Version

Report which Soleur plugin version is installed, what the latest release is, and how to update. Run the shared resolver; never guess or infer a version yourself. This command is Claude Code only and is started by the user; it is not run automatically.

This explicit run contacts github.com regardless of `SOLEUR_UPDATE_CHECK`, because you asked: one `git ls-remote --tags` against the public repo and, for a commit-hash or local-checkout install only, one unauthenticated GitHub compare API request whose URL includes the installed commit hash (for a local checkout that is the checkout's current commit, which may be one you have never pushed anywhere). It uses no tokens, no user git config and no credentials of its own (any proxy you configured in your environment is still used), and each request is time-limited.

## Step 1: Run the resolver

Run via the **Bash tool**:

```bash
if grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null; then
  if [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-version.sh" ]; then
    bash "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-version.sh" --compare --refresh
  else
    echo "source=unknown"
  fi
else
  echo "source=unknown"
fi
```

If `CLAUDE_PLUGIN_ROOT` is not set or the script does not exist at that path, do not look for it anywhere else (a script from the current directory is not trusted): print `Installed:  unknown` and stop. The output is `key=value` lines: `source`, `version`, `commit`, `marketplace`, `cache`, `latest_status`, `latest`, `latest_commit`, `relation`, `reason`, `cache_dir`. Use only these values. `source=checkout` means the plugin is loaded in place from a local git checkout (a local-folder marketplace or `--plugin-dir`); `commit` is that checkout's HEAD commit, read from its files without running git.

## Step 2: Print this block

Print the block below, filling it from the resolver output. Keep it compact, no emoji.

```text
Soleur plugin version

Installed:  <version, or "commit <sha12>", or "commit <sha12> (local checkout, HEAD commit, not uncommitted or unsynced files)">  (source: <manifest | commit | checkout>)
Latest:     <latest, e.g. v3.4.5>   (or the WHY line from the rules below)
Status:     <one status line from the rules below>

Update (Claude Code):
  <for source=checkout: the local-folder steps from "Update commands" below, never the GitHub marketplace pair>
  <otherwise: the two commands from "Update commands" below>
  Restart the CLI afterwards; plugin changes apply on restart.

Session-start newer-release check (off by default): the version line itself is shown at
every session start with no network. To also check for a newer release, set
SOLEUR_UPDATE_CHECK=1 in your user-level Claude Code settings "env" block (not a checked-in
project settings file, and not in CI or ephemeral containers); remove it to turn it off.
```

### Installed line

- `source=manifest`: print `version`.
- `source=commit`: print `commit <commit>` (the 12-character hash). Do not invent a version number for it.
- `source=checkout`: print `commit <commit> (local checkout, HEAD commit, not uncommitted or unsynced files)` exactly as the template shows it (`<commit>` is the 12-character hash of the HEAD commit of the git checkout that contains the plugin folder, read from its files without running git). Do not invent a version number for it.
- `source=unknown`, `source=none`, or any value other than `manifest`, `commit` and `checkout`: print `Installed:  unknown`, omit the `Update (Claude Code):` block, and say the plugin root could not be identified (not running from an installed plugin, a recognizable cache directory, or a local git checkout whose HEAD could be read: an unborn branch, a reftable or sha-256 repository or an unusual layout reads as unknown); tell the user they can compare with `claude plugin list` (you do not run it). Do not print a version.

### Latest line (explain WHY when missing)

When `latest=` is present, print it. Label it "(cached, may be out of date)" whenever `cache=stale` or `latest_status` is `offline` or `timeout`. When `latest=` is absent, print the first matching reason, never a blank:

1. `latest_status=offline`: "Could not reach github.com (offline or blocked)."
2. `latest_status=timeout`: "The lookup timed out."
3. `latest_status=no-git`: "`git` is not installed, so the release lookup was skipped."
4. `latest_status=no-tags`: "github.com answered but returned no release tags."
5. `cache=corrupt`: "The version cache is unreadable; it is rewritten on the next successful lookup." (the file is `latest-release.<install id>` under `cache_dir`, or `latest-release.checkout` for a local checkout).
6. Anything else: "The latest release could not be determined."

### Status line (compare result)

Read `relation` and `reason`:

- `relation=older`: "A newer release exists."
- `relation=current`: "No release newer than yours (latest tag vX.Y.Z)", with the `latest` value. This means only that no release tag newer than the installed commit or version was found. Never say "up to date" or "you are on the latest release".
- `relation=unknown`: "Cannot compare" plus the reason: `installed-unknown` (the installed version could not be read), `diverged` (the installed commit is not on the release line), `compare-failed` or `compare-unparseable` (the GitHub compare call failed; a local checkout may also be on a commit that was never published), `no-curl` (curl is missing), `stale-cache` (the answer came from a cached or failed lookup, so it is not trusted; run this command again when online), `cache-invalid` (the cached answer was unusable; run this command again).
- `relation` absent (no latest release is known): "Cannot compare: the latest release is not known", followed by the `latest_status` reason from the Latest line rules.

Never say "up to date" when the relation is unknown or absent, and never infer a relation by comparing strings yourself.

### Update commands

Choose by `source` first, then (for `manifest` and `commit` only) by the `marketplace` value:

- `source=checkout` (in place from a local git checkout; use this arm whatever `marketplace` says, and never print the GitHub marketplace pair for it, which would replace the in-place install with a published copy). **Print these steps for the user to run; never run any of them yourself** (no `git`, no `claude`, no `gh`). The marketplace is the local folder and is named `soleur`. Tell the user how to tell the two layouts apart: `git -C <folder> rev-parse --is-bare-repository` prints `true` for a bare layout (`<folder>` is the Source path in `claude plugin marketplace list`).
  1. Update the folder. Bare layout (`true`, files mirrored on disk): in the repository root run `git fetch --no-tags origin main:main`; if git refuses because `main` is checked out in a worktree, commit or stash there and run `git pull --ff-only` inside that worktree instead (never force-move `main`: that can orphan unpushed commits). Then run `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh sync`, which mirrors the repository's HEAD to the files on disk (it overwrites tracked files there and does not fetch). Normal clone (`false`): update the branch you run from, for example `git pull --ff-only`.
  2. If the plugin was added as a local-folder marketplace (the usual case): `claude plugin marketplace update soleur` then `claude plugin update soleur@soleur`, then restart. If it was started with `--plugin-dir <path>`, skip this step (no marketplace command applies) and just restart.
  The resolver cannot tell those two launch modes apart, so print both lines, each labelled. If the plugin folder is vendored inside another project's repository, the identity shown is that project's HEAD and these steps do not update the vendored copy.
- `source=manifest` or `source=commit`, with `marketplace` absent or `soleur-marketplace`:
  `claude plugin marketplace update soleur-marketplace` then `claude plugin update soleur@soleur-marketplace`
- `soleur`:
  `claude plugin marketplace update soleur` then `claude plugin update soleur@soleur`
- any other value: print the same pair with that marketplace name substituted.

If the install is project-scoped (`claude plugin list` shows Scope), add `--scope project` to the update command. See `knowledge-base/engineering/operations/runbooks/plugin-delivery-recovery.md` if an update says "already at the latest version" but nothing changes.

## Output Rules

- Print only values the resolver returned or the fixed text above; never report a version you did not read.
- Do not run `gh`, `curl`, `git` or `claude` yourself; the resolver owns every network call.
- If the Bash tool is unavailable, say so and print only `Installed:` from the plugin root directory name if it is a 12-character hex commit hash; otherwise print `unknown`.
