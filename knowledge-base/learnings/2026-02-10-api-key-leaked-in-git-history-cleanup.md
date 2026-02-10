# Learning: API key leaked in git history -- full cleanup procedure

## Problem

An API key was accidentally committed in `.claude/settings.local.json`. Simply deleting the key and making a new commit is insufficient -- the secret remains accessible in every historical commit that touched the file, across all branches, and even in GitHub's cached PR refs.

## Symptoms

- API key visible in `.claude/settings.local.json` via git history
- File present in multiple branches (main + 9 feature branches)
- Old commit SHAs remain accessible on GitHub even after force-push (e.g., `github.com/org/repo/blob/<old-sha>/.claude/settings.local.json`)

## Root Cause

`.claude/settings.local.json` was never in `.gitignore`. It was committed early in the project and propagated across all branches. Git preserves full history, so deleting the file in a new commit does not remove it from old commits.

## Solution

### Step 1: Revoke the key immediately

Before any cleanup, revoke the leaked credential so it cannot be used.

### Step 2: Add file to .gitignore

```
.claude/settings.local.json
```

### Step 3: Remove from git tracking

```bash
git rm --cached .claude/settings.local.json
```

### Step 4: Rewrite history with git-filter-repo

```bash
pip install git-filter-repo
git filter-repo --invert-paths --path .claude/settings.local.json --force
```

Note: `git filter-repo` removes the `origin` remote as a safety measure. Re-add it after:

```bash
git remote add origin git@github.com:org/repo.git
```

### Step 5: Rewrite ALL branches, not just main

Fetch all affected remote branches locally first, then re-run filter-repo:

```bash
# Create local tracking branches for all affected remotes
for branch in branch1 branch2 ...; do
  git checkout -B "$branch" "origin/$branch"
done
git checkout main

# Re-run filter-repo (processes all local branches)
git filter-repo --invert-paths --path .claude/settings.local.json --force
git remote add origin git@github.com:org/repo.git
```

### Step 6: Force-push all branches

```bash
git push --force origin main branch1 branch2 ...
```

### Step 7: Delete merged remote branches

Old branch refs keep dangling commits alive on GitHub:

```bash
for branch in branch1 branch2 ...; do
  git push origin --delete "$branch"
done
```

### Step 8: Contact GitHub Support

GitHub caches old commit objects via internal `refs/pull/*/head` refs. These cannot be deleted via git or the API. Submit a support request at https://support.github.com/request asking them to run garbage collection and purge dangling objects.

## Key Insight

Removing a secret from git requires a multi-layer cleanup: rewrite history locally, force-push ALL branches (not just main), delete stale remote branches, and request GitHub garbage collection. Missing any layer leaves the secret accessible. The most commonly missed step is rewriting non-main branches and cleaning up GitHub's internal PR refs.

Always `.gitignore` files that may contain secrets (API keys, credentials, local settings) from day one.

## Prevention

- Add `.claude/settings.local.json` and similar local config files to `.gitignore` at project initialization
- Use `git-secrets` or similar pre-commit hooks to scan for API key patterns before they are committed
- Treat any `*.local.*` or `settings.local.*` file as potentially sensitive

## Tags

category: security-issues
module: git, github
symptoms: api key in git history, leaked secret, settings.local.json committed
