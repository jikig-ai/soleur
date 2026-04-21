---
name: feature-video
description: "This skill should be used to record video walkthroughs of features for PR descriptions. Captures browser interactions via agent-browser CLI; optional GIF/MP4 via ffmpeg and upload via rclone."
---

# Feature Video Walkthrough

<command_purpose>Record a video walkthrough demonstrating a feature, upload it, and add it to the PR description.</command_purpose>

## Introduction

<role>Developer Relations Engineer creating feature demo videos</role>

This skill creates professional video walkthroughs of features for PR documentation:

- Records browser interactions using agent-browser CLI
- Demonstrates the complete user flow
- Converts screenshots to video/GIF (when ffmpeg is available)
- Uploads to cloud storage (when rclone is configured)
- Updates the PR description with the best available output

## Prerequisites

<requirements>
- Local development server running (e.g., `bin/dev`, `rails server`)
- agent-browser CLI installed (required)
- Git repository with a PR to document
- `ffmpeg` installed (optional -- without it, screenshots are captured but no video/GIF is created). Can be installed automatically by the dependency check script.
- `rclone` configured (optional -- without it, video stays local instead of uploading to cloud storage). Can be installed automatically by the dependency check script.
</requirements>

## Phase 0: Dependency Check

Run [check_deps.sh](./scripts/check_deps.sh) before proceeding. When invoked from a pipeline (e.g., one-shot), pass `--auto` to skip interactive prompts and install missing tools automatically:

```bash
bash ./plugins/soleur/skills/feature-video/scripts/check_deps.sh
```

For pipeline/automated use:

```bash
bash ./plugins/soleur/skills/feature-video/scripts/check_deps.sh --auto
```

If the script exits non-zero, agent-browser is missing and recording cannot proceed. Stop and inform the user.

If ffmpeg or rclone show `[skip]`, note which tools are unavailable. The skill continues with degraded capability:

- **No ffmpeg**: Capture screenshots only. Skip video/GIF creation in steps 4-5.
- **No rclone**: Create video locally. Skip upload in step 6.

Store the availability as variables for use in later steps:

```bash
HAS_FFMPEG=$(command -v ffmpeg >/dev/null 2>&1 && echo "true" || echo "false")
HAS_RCLONE=$(command -v rclone >/dev/null 2>&1 && echo "true" || echo "false")
RCLONE_CONFIGURED="false"
if [ "$HAS_RCLONE" = "true" ]; then
  REMOTES=$(rclone listremotes 2>/dev/null || true)
  [ -n "$REMOTES" ] && RCLONE_CONFIGURED="true"
fi
```

## Main Tasks

### 1. Parse Arguments

<parse_args>

**Arguments:** $ARGUMENTS

Parse the input:

- First argument: PR number or "current" (defaults to current branch's PR)
- Second argument: Base URL (defaults to `http://localhost:3000`)

```bash
# Get PR number for current branch if needed
gh pr view --json number -q '.number'
```

</parse_args>

### 2. Gather Feature Context

<gather_context>

**Get PR details:**

```bash
gh pr view [number] --json title,body,files,headRefName -q '.'
```

**Get changed files:**

```bash
gh pr view [number] --json files -q '.files[].path'
```

**Map files to testable routes** (same as playwright-test):

| File Pattern | Route(s) |
|-------------|----------|
| `app/views/users/*` | `/users`, `/users/:id`, `/users/new` |
| `app/controllers/settings_controller.rb` | `/settings` |
| `app/javascript/controllers/*_controller.js` | Pages using that Stimulus controller |
| `app/components/*_component.rb` | Pages rendering that component |

</gather_context>

### 3. Plan the Video Flow

<plan_flow>

Before recording, create a shot list:

1. **Opening shot**: Homepage or starting point (2-3 seconds)
2. **Navigation**: How user gets to the feature
3. **Feature demonstration**: Core functionality (main focus)
4. **Edge cases**: Error states, validation, etc. (if applicable)
5. **Success state**: Completed action/result

Ask user to confirm or adjust the flow:

```markdown
**Proposed Video Flow**

Based on PR #[number]: [title]

1. Start at: /[starting-route]
2. Navigate to: /[feature-route]
3. Demonstrate:
   - [Action 1]
   - [Action 2]
   - [Action 3]
4. Show result: [success state]

Estimated duration: ~[X] seconds

Does this look right?
1. Yes, start recording
2. Modify the flow (describe changes)
3. Add specific interactions to demonstrate
```

</plan_flow>

### 4. Setup Video Recording

<setup_recording>

**Create directories:**

```bash
mkdir -p tmp/screenshots tmp/videos
```

**Recording approach: Use browser screenshots as frames**

agent-browser captures screenshots at key moments. If ffmpeg is available, screenshots are combined into video/GIF in step 5.

**If ffmpeg is unavailable:** Screenshots are the final output. Skip video/GIF creation commands in step 5.

</setup_recording>

### 5. Record the Walkthrough

<record_walkthrough>

Execute the planned flow, capturing each step:

**Step 1: Navigate to starting point**

```bash
agent-browser open "[base-url]/[start-route]"
agent-browser wait 2000
agent-browser screenshot tmp/screenshots/01-start.png
```

**Step 2: Perform navigation/interactions**

```bash
agent-browser snapshot -i  # Get refs
agent-browser click @e1    # Click navigation element
agent-browser wait 1000
agent-browser screenshot tmp/screenshots/02-navigate.png
```

**Step 3: Demonstrate feature**

```bash
agent-browser snapshot -i  # Get refs for feature elements
agent-browser click @e2    # Click feature element
agent-browser wait 1000
agent-browser screenshot tmp/screenshots/03-feature.png
```

**Step 4: Capture result**

```bash
agent-browser wait 2000
agent-browser screenshot tmp/screenshots/04-result.png
```

**Create video/GIF from screenshots (skip if ffmpeg unavailable):**

If `HAS_FFMPEG=false`, skip the ffmpeg commands below. The screenshots in `tmp/screenshots/` are the final output. Inform the user: "ffmpeg not installed -- screenshots captured but video/GIF creation skipped."

```bash
# Only run if HAS_FFMPEG=true

# Create MP4 video (RECOMMENDED - better quality, smaller size)
# -framerate 0.5 = 2 seconds per frame (slower playback)
# -framerate 1 = 1 second per frame
ffmpeg -y -framerate 0.5 -pattern_type glob -i 'tmp/screenshots/*.png' \
  -c:v libx264 -pix_fmt yuv420p -vf "scale=1280:-2" \
  tmp/videos/feature-demo.mp4

# Create low-quality GIF for preview (small file, for GitHub embed)
ffmpeg -y -framerate 0.5 -pattern_type glob -i 'tmp/screenshots/*.png' \
  -vf "scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse" \
  -loop 0 tmp/videos/feature-demo-preview.gif
```

**Note:**

- The `-2` in MP4 scale ensures height is divisible by 2 (required for H.264)
- Preview GIF uses 640px width and 128 colors to keep file size small (~100-200KB)

</record_walkthrough>

### 6. Upload the Video

<upload_video>

**Skip this step if `RCLONE_CONFIGURED=false`.** Inform the user: "rclone not available or not configured -- video retained locally at tmp/videos/."

**Upload with rclone (only if RCLONE_CONFIGURED=true):**

```bash
# Upload video, preview GIF, and screenshots to cloud storage
# Use --s3-no-check-bucket to avoid permission errors
rclone copy tmp/videos/ r2:kieran-claude/pr-videos/pr-[number]/ --s3-no-check-bucket --progress
rclone copy tmp/screenshots/ r2:kieran-claude/pr-videos/pr-[number]/screenshots/ --s3-no-check-bucket --progress

# List uploaded files
rclone ls r2:kieran-claude/pr-videos/pr-[number]/
```

Public URLs (R2 with public access):

```
Video: https://pub-4047722ebb1b4b09853f24d3b61467f1.r2.dev/pr-videos/pr-[number]/feature-demo.mp4
Preview: https://pub-4047722ebb1b4b09853f24d3b61467f1.r2.dev/pr-videos/pr-[number]/feature-demo-preview.gif
```

</upload_video>

### 7. Update PR Description

<update_pr>

**Get current PR body:**

```bash
gh pr view [number] --json body -q '.body'
```

**Add a demo section to the PR description based on what was produced:**

If the PR already has a demo section, replace it. Otherwise, append.

**Case A: Video uploaded (HAS_FFMPEG=true, RCLONE_CONFIGURED=true)**

Use a clickable GIF that links to the video (GitHub cannot embed external MP4s directly):

```markdown
## Demo

[![Feature Demo]([preview-gif-url])]([video-mp4-url])

*Click to view full video*
```

**Case B: Video created locally (HAS_FFMPEG=true, RCLONE_CONFIGURED=false)**

Upload the video to the PR as a GitHub comment attachment before cleanup deletes local files:

```bash
# Upload video as a PR comment (GitHub accepts drag-and-drop or API upload)
echo "Upload tmp/videos/feature-demo.mp4 to PR #[number] as a comment attachment"
```

Then add to PR body:

```markdown
## Demo

See video in PR comments below.
```

**Case C: Screenshots only (HAS_FFMPEG=false)**

Upload screenshots to the PR as comment attachments before cleanup deletes local files, then embed in the PR body:

```markdown
## Demo

Screenshots captured (video conversion requires ffmpeg). See PR comments for images.
```

**Update the PR:**

```bash
gh pr edit [number] --body "[updated body with demo section]"
```

</update_pr>

### 8. Cleanup

<cleanup>

```bash
# Always clean up tmp artifacts after PR description is updated
rm -rf tmp/screenshots tmp/videos
echo "Cleaned up tmp/screenshots/ and tmp/videos/"
```

</cleanup>

### 9. Summary

<summary>

Present completion summary:

```markdown
## Feature Video Complete

**PR:** #[number] - [title]
**Video:** [url or local path]
**Duration:** ~[X] seconds
**Format:** [GIF/MP4]

### Shots Captured
1. [Starting point] - [description]
2. [Navigation] - [description]
3. [Feature demo] - [description]
4. [Result] - [description]

### PR Updated
- [x] Video section added to PR description
- [ ] Ready for review

**Next steps:**
- Review the video to ensure it accurately demonstrates the feature
- Share with reviewers for context
```

</summary>

## Quick Usage Examples

```bash
# Record video for current branch's PR
/feature-video

# Record video for specific PR
/feature-video 847

# Record with custom base URL
/feature-video 847 http://localhost:5000

# Record for staging environment
/feature-video current https://staging.example.com
```

## Tips

- **Keep it short**: 10-30 seconds is ideal for PR demos
- **Focus on the change**: Don't include unrelated UI
- **Show before/after**: If fixing a bug, show the broken state first (if possible)
- **Annotate if needed**: Add text overlays for complex features
