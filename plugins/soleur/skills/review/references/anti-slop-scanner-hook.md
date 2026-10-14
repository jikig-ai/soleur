# Anti-slop Scanner Hook

Extracted from SKILL.md (§conditional agents) — #9093 body-budget move. The trigger below is evaluated inline during review; nothing else changed.

**If the diff touches `apps/web-platform/(app|components)/.*\.(tsx|jsx|css)$` OR `apps/web-platform/server/.*\.(ts|tsx)$` OR `plugins/soleur/docs/.*\.(njk|css)$`:**

17. Run the `soleur:frontend-anti-slop` Tier 1 scanner inline (no separate agent spawn — v1 simplification per plan PR #4265). Scope covers the Next.js platform, the server-side email/HTML templates, and the Eleventy marketing site so AI-assisted edits to landing pages, transactional emails, or blog posts get the same audit as React component changes.

    ```bash
    # Keep NUL framing end-to-end. The host `grep` is ugrep, where the NUL-data
    # flag means `--decompress` (NOT GNU `--null-data`) and silently matches
    # zero files (the #4635 false-clean). Do NOT use grep at all in this
    # collector: read the NUL-delimited diff with `read -r -d ''` and match each
    # path against EXT_RE in bash, so filenames containing literal newlines
    # survive intact. The path regex mirrors `DEFAULT_PATH_RE_SOURCE` in
    # tier1-scan.ts (parity-tested).
    EXT_RE='(apps/web-platform/(app|components)/.*\.(tsx|jsx|css)|apps/web-platform/server/.*\.(ts|tsx)|plugins/soleur/docs/.*\.(njk|css))$'
    CHANGED_FILES=()
    HAS_EXT_FILE=0
    while IFS= read -r -d '' f; do
      [[ "$f" =~ $EXT_RE ]] && CHANGED_FILES+=("$f")
      [[ "$f" =~ \.(tsx|jsx|ts|css|njk)$ ]] && HAS_EXT_FILE=1
    done < <(git diff --name-only -z origin/main...HEAD)
    if (( ${#CHANGED_FILES[@]} > 0 )); then
      bun run plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts \
        --paths "${CHANGED_FILES[@]}" --json
    elif (( HAS_EXT_FILE == 1 )); then
      # Guard against silent false-clean: the diff DOES contain scanner-extension
      # files but none matched the scope regex (or the collector mis-fired).
      # Warn loudly instead of reporting clean — this is the #4635 failure class.
      echo "WARNING: diff contains scanner-extension files but none matched the anti-slop scope regex; the scanner did NOT run — verify the path regex / collector did not silently drop files." >&2
    fi
    ```

**What this hook checks:**

- 18 deterministic Tier 1 gates adapted from [Nutlope/hallmark](https://github.com/Nutlope/hallmark) (MIT) — gradient-fill headlines, generic display fonts, purple→blue gradients, `transition-all`, uniform `hover:scale-105`, placeholder names, zero-chroma neutrals, off-scale spacing, prose-width out of range, two-icon-library imports, plus 3 `brand`-category gates (raw hex, white-on-gold contrast, non-zero corners), etc. See [slop-rules.md](../../frontend-anti-slop/references/slop-rules.md).
- The anti-slop (non-brand) findings are **advisory and non-blocking** in v1 (calibration mode). They surface in the review output for operator triage; no auto-file to GitHub issues. Promotion to auto-file gates on ≤ 10% FP rate over ≥ 20 findings ≥ 2 weeks (per `soleur:frontend-anti-slop` SKILL.md §"Calibration mode").
- **High-severity `brand` findings are a required-fix gate, NOT operator triage.** When the scanner reports a finding whose originating rule is `category: brand` and `severity: high` (BRAND-RAW-HEX, BRAND-WHITE-ON-GOLD), the scanner exits non-zero (1) — the diff must be fixed before merge, the reviewing agent does not get to narrate it away as a likely false positive. Brand `medium` findings (BRAND-NONZERO-CORNER) stay advisory like the rest.
- Findings conform to `finding.schema.json` with `category: "anti-slop"`, `selector: "<file-path>#<RULE-ID>"`. Pretty-print the JSON array directly into the review output as a fenced code block; the reviewing agent narrates which findings look like true positives.
