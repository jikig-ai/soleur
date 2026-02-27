---
title: "fix: Add preflight dependency check to feature-video skill"
type: fix
date: 2026-02-27
---

# fix: Add preflight dependency check to feature-video skill

The `feature-video` skill silently fails when ffmpeg or rclone are missing. Add a `check_deps.sh` preflight script and conditional logic in the SKILL.md so the skill reports what's available and continues with whatever it can do.

## Acceptance Criteria

- [ ] `check_deps.sh` checks agent-browser (hard), ffmpeg (soft), rclone (soft)
- [ ] Missing agent-browser halts with install instructions (exit 1)
- [ ] Missing ffmpeg/rclone print warnings but skill continues
- [ ] SKILL.md Phase 0 runs `check_deps.sh` before recording
- [ ] SKILL.md skips ffmpeg steps when ffmpeg is absent
- [ ] SKILL.md skips rclone steps when rclone is absent/unconfigured
- [ ] Step 8 cleanup does not delete screenshots when they are the final output
- [ ] SKILL.md frontmatter `description:` reflects optional video capability
- [ ] Script linked as `[check_deps.sh](./scripts/check_deps.sh)`
- [ ] PATCH version bump (plugin.json, CHANGELOG.md, marketplace.json, root README badge, bug_report.yml)

## Context

### Files to create

**`plugins/soleur/skills/feature-video/scripts/check_deps.sh`**

```bash
#!/bin/bash
# feature-video dependency checker

echo "=== feature-video Dependency Check ==="
echo

# Hard dependency -- cannot record without this
if command -v agent-browser >/dev/null 2>&1; then
  echo "  [ok] agent-browser"
else
  echo "  [MISSING] agent-browser (required)"
  echo "    Install: npm install -g agent-browser && agent-browser install"
  echo
  echo "Cannot proceed without agent-browser."
  exit 1
fi

# Soft dependencies -- skill degrades without these
for tool in ffmpeg rclone; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "  [ok] $tool"
  else
    echo "  [skip] $tool not installed (optional)"
  fi
done

# Check rclone remote config if rclone is present
if command -v rclone >/dev/null 2>&1; then
  REMOTES=$(rclone listremotes 2>/dev/null || true)
  if [ -z "$REMOTES" ]; then
    echo "  [skip] rclone: no remotes configured (see rclone skill)"
  fi
fi

echo
echo "=== Check Complete ==="
```

### Files to modify

**`plugins/soleur/skills/feature-video/SKILL.md`**

Three changes:

1. **Add Phase 0** after the Setup section, before Step 1:
   - Run `bash scripts/check_deps.sh`
   - If exit 1: halt, show install instructions
   - Otherwise: continue. If ffmpeg or rclone were reported missing, the skill will skip those steps.

2. **Add conditionals to Steps 4-6:**
   - Before ffmpeg commands (Steps 4-5): "If ffmpeg is not available, skip video creation and proceed with screenshots only."
   - Before rclone commands (Step 6): "If rclone is not available or has no configured remotes, skip upload and report local file paths."
   - Step 7: "Adapt the Demo section based on what output was actually produced."

3. **Fix two pre-existing issues:**
   - Ensure `mkdir -p tmp/screenshots` runs unconditionally before recording (currently only created inside the ffmpeg block)
   - Step 8 cleanup: only delete screenshots if they were converted to video. In screenshots-only mode, screenshots are the deliverable.

4. **Update frontmatter and prerequisites:**
   - `description:` field: mention that video/GIF creation requires ffmpeg, upload requires rclone
   - Prerequisites section: mark ffmpeg and rclone as optional with degraded functionality

### Version bump files

- `plugins/soleur/.claude-plugin/plugin.json` — bump patch
- `plugins/soleur/CHANGELOG.md` — add entry
- `plugins/soleur/.claude-plugin/marketplace.json` — bump patch
- Root `README.md` — update version badge
- `.github/ISSUE_TEMPLATE/bug_report.yml` — update version placeholder

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-27-feature-video-deps-brainstorm.md`
- Spec: `knowledge-base/specs/feat-feature-video-deps/spec.md`
- Reference pattern: `plugins/soleur/skills/rclone/scripts/check_setup.sh`
- Related issue: #325
