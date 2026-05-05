---
date: 2026-05-05
category: best-practices
module: brand-workshop, pencil-setup, ux-design-lead
tags: [pencil-mcp, headless, brand-workshop, gitignore, image-export, founder-review]
related_pr: 3233
related_branch: feat-brand-guide-light
related_issue: 3232
---

# Learning: Brand mockup export and routing — four traps in the headless Pencil pipeline

## Problem

The brand-workshop skill (`plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md`) gates merging palette changes on a founder-approved Pencil mockup that renders the new tokens against representative app surfaces. PR #3233 (Solar Radiance light palette) was the first end-to-end exercise of the gate. The agent path produced output the founder rejected on first surface for two distinct reasons — wrong directory and blank-space export tail — and the staging path silently dropped the PNG.

Each issue is small individually; together they would burn ~20 min per future brand-workshop run if not captured.

## Solutions

### 1. Mockup output path: `product/design/brand/`, not `marketing/brand-mockups/`

The brand-workshop reference prescribed `knowledge-base/marketing/brand-mockups/<topic>-<YYYY-MM-DD>/`. Jean (founder/CEO) rejected on first surface: design artifacts (Pencil files, screenshots, wireframes) live in `knowledge-base/product/design/`, not under marketing. The repo already had `knowledge-base/product/design/brand/brand-visual-identity-brainstorm.pen` proving the convention.

Fix: `brainstorm-brand-workshop.md` lines 75 and 105 now prescribe `knowledge-base/product/design/brand/<topic>-<YYYY-MM-DD>/`. Mockups moved alongside the existing brand visual identity .pen file.

### 2. Pencil headless canvas color is `#F2F2F2`, not white

`mcp__pencil__export_nodes` against the root canvas frame produced a 3280×6600 PNG. The actual content occupied roughly 3280×2800; the rest was uniform canvas background. The naive crop attempt diff'd against pure white `(255,255,255)` and returned the original size unchanged. Pencil's headless renderer fills empty canvas with `#F2F2F2`.

Two viable fixes:

- **(a)** When calling `export_nodes`, pass the content container node id rather than the canvas root, so Pencil exports a tight frame.
- **(b)** Post-process the PNG with a `#F2F2F2`-aware crop. PIL is sufficient — no numpy required:

  ```python
  from PIL import Image
  im = Image.open(path).convert("RGB")
  W, H = im.size
  px = im.load()
  CANVAS, TOL = (0xF2, 0xF2, 0xF2), 4
  def is_canvas(p):
      return all(abs(p[i] - CANVAS[i]) <= TOL for i in range(3))
  # Scan rows/cols for non-canvas pixels at STEP=4 sampling, then crop with PAD=48
  ```

  The pure-PIL row/column scan is fast enough (~0.5s on a 3280×6600 image) and avoids the numpy install dependency.

### 3. `*.png` blanket gitignore needs a `product/design/**/*.png` negation

The repo's `.gitignore` has a `*.png` rule with negations for legitimate-image-asset directories. Brand mockups under `product/design/` were not negated — the only design-tree negation was `!knowledge-base/product/design/**/screenshots/*.png`, which doesn't match the brand-workshop output path.

Fix: add `!knowledge-base/product/design/**/*.png` so all design-domain PNGs are tracked. `git add <path>` silently drops ignored files; the only way to discover the gap is `git status` showing the PNG missing or `git check-ignore -v <path>` which prints the matching rule.

### 4. Headless Pencil MCP correctly chosen — gate caught it

The brand-workshop step 4.5.0 hard-gate (commit 2104ed31, this branch) verifies `claude mcp list` reports `pencil-mcp-adapter` and aborts otherwise. Without that gate, an IDE/Desktop-mode `.pen` would have been edited in editor memory and `export_nodes` would have read a stale on-disk file — exactly the failure mode described in `knowledge-base/project/learnings/best-practices/2026-05-05-pencil-mcp-headless-vs-ide-mode-selection.md`.

The gate is load-bearing: it converted a silent failure into a hard stop with a copy-pasteable remediation command (`bash ./plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --auto`).

## Key Insight

Founder review is the load-bearing review for brand artifacts. The gate's audit trail (commit body names the founder, date, and approving message) is more valuable than any multi-agent code review, because the artifact under review is a visual-design judgment call — multi-agent review can validate the .pen file's structural integrity but cannot replace the founder eye on whether the rendering "looks like Soleur."

The corollary: when a workflow gap surfaces during founder review, fix the skill that prescribed the wrong behavior in the same commit. The path mistake here is fixed inline in `brainstorm-brand-workshop.md`, so the next agent run lands in the right place with no learning lookup required.

## Session Errors

- **Wrong mockup output path** — Mockups initially landed under `knowledge-base/marketing/brand-mockups/` because the brand-workshop reference prescribed it. Jean rejected on first AskUserQuestion. Recovery: `mv` + Edit on lines 75 & 105 of `brainstorm-brand-workshop.md`. **Prevention:** the skill reference is now corrected; future runs land in `product/design/brand/`. No new rule needed — the fix is in the prescribing skill.

- **PNG export blank-space tail** — `mcp__pencil__export_nodes` on the canvas root frame produced 3280×6600 with ~3800px of empty canvas. Jean flagged "really big blank space under the elements." Recovery: post-export PIL crop. **Prevention:** documented above as solution #2; the pencil-setup skill should reference this learning so the next ux-design-lead invocation either exports a tight frame or applies the crop preemptively.

- **First PIL crop assumed white bg** — Initial script diff'd against `(255,255,255)`, got full-image bbox, returned the original PNG unchanged. Recovery: pixel-sampling at multiple Y positions revealed the actual canvas color `#F2F2F2`. **Prevention:** documented above; the canvas color is now in this learning for future reference.

- **PNG ignored by `*.png` blanket rule** — First `git add` silently dropped the PNG. Recovery: `git check-ignore -v` printed the rule, `.gitignore` got a `!product/design/**/*.png` negation. **Prevention:** the new negation covers all future design-tree PNGs; the failure mode (`git add` silent drop) is a known git pattern documented in many places.

- **ImageMagick not installed** — First post-export crop attempt invoked `identify` / `convert`. `which` returned not-found. Recovery: pivoted to Python PIL. **Prevention:** prefer Python PIL (always available on this dev box) over ImageMagick for compound-flow image manipulation. Single-line learning, not rule-worthy.

- **numpy not installed** — Second crop attempt imported numpy. `ModuleNotFoundError`. Recovery: pure-PIL pixel-by-pixel scan with STEP=4 sampling. **Prevention:** for compound-flow scripts that run inside the Bash tool, prefer pure-PIL or stdlib over numpy/pandas/scipy unless the operation is provably hot. This is a one-off; not rule-worthy.

## Tags

- category: best-practices
- module: brand-workshop, pencil-setup, ux-design-lead
- date: 2026-05-05
- branch: feat-brand-guide-light
- pr: 3233
- founder-approved: Jean Deruelle, 2026-05-05
