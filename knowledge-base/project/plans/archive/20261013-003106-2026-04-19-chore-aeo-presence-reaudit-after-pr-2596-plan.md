---
title: "AEO Presence score re-audit after PR #2596"
issue: 2615
source_pr: 2596
type: chore
priority: P3
domain: marketing
created: 2026-04-19
status: planned
---

# AEO Presence score re-audit after PR #2596

## Enhancement Summary

**Deepened on:** 2026-04-19
**Sections enhanced:** 6 (Context, Acceptance Criteria, Phase 2 score extraction,
Phase 3 escalation, Risks, Test Scenarios)
**Research performed:**

- Live verification of `https://soleur.ai/` (HTTP 200 after `https://www.soleur.ai/`
  redirect) — confirmed deployed surface includes (a) GitHub Stars tile rendering
  literal `6` (not `∞` glyph or placeholder), (b) `landing-press-strip` partial,
  (c) Organization JSON-LD with `@id: https://soleur.ai/#organization`, 5 `sameAs`
  URLs (github / x.com / linkedin / bsky / discord), and `subjectOf[NewsArticle]`
  pointing at the Inc.com Amodei article — all present in the page returned by
  `curl -sSL https://soleur.ai/`.
- Audit-history scan (`*-aeo-audit.md` 2026-02-19 → 2026-04-18) — confirmed the
  Presence row label `"Presence & Third-Party Mentions"` is stable in the most
  recent 2 audits, but the **column count differs**: 4-13 used 5 columns
  (Category / Score / Grade / Weight / Weighted), 4-18 added a 6th "Delta vs
  prior" column. The Phase 2 awk-by-position extraction is fragile to this
  drift.
- Status check of #2599–#2604 — all six off-site follow-ups remain OPEN as of
  2026-04-19, so the auditor will see no off-site changes between 2026-04-18 and
  the next cron. Any Presence delta in the next audit is therefore attributable
  exclusively to PR #2596's on-site surface.
- Cross-check of `scheduled-follow-through.yml` predicate types — confirmed only
  `manual / http-200 / dns-txt / dns-a` are supported. No `aeo-score` predicate
  exists. Manual operator action is required (matches plan).

### Key Improvements

1. **Replaced fragile awk column-position parsing with a column-name lookup.** The
   audit table column order has already drifted once (5→6 columns between
   2026-04-13 and 2026-04-18). A future audit may insert / reorder columns again.
   The new Phase 2 reads the header row, locates the `Score` column by name, and
   then reads the same column in the `Presence` row. Drift-resistant per
   `cq-code-comments-symbol-anchors-not-line-numbers`.
2. **Added a pre-audit live-surface sanity check** (curl + JSON-LD parse) that the
   operator can run BEFORE the cron to confirm the deployed surface is intact.
   Catches the failure mode where `_data/githubStats.js` degraded to dev-fallback
   and the auditor scored stale content.
3. **Tightened the credit-attribution language** in the closing comment template
   to enumerate which of #2599–#2604 are open at audit time, since all 6 remain
   open as of plan write.
4. **Added an audit-pair re-run rule** for marginal scores (54–58) to handle the
   growth-strategist agent's documented non-determinism (Princeton GEO research
   methods produce ±5–10 point variance on identical pages across runs).
5. **Added a "stub fallback" detection check** (audit body contains "audit failed
   — see CI logs") that prevents extracting a fake score from a failed cron.
6. **Documented the SAP-rubric weight math** explicitly in the closing comment so
   reviewers don't expect a B-grade overall jump from a 5%-weighted category.

### New Considerations Discovered

- The shipped Inc.com `subjectOf[NewsArticle]` is structured data, not visible
  copy. The growth-strategist's Presence rubric explicitly looks for "external
  reviews, comparisons, forums, press mentions" as visible signals. The
  `landing-press-strip` partial provides the visible signal; the JSON-LD
  reinforces it. If the Presence score moves only marginally (e.g., 40 → 50),
  the most likely cause is the rubric weighting visible-copy press over JSON-LD
  press — not a deployment failure. The escalation comment should raise this for
  CMO triage, not assume the surface is broken.
- The grade scale defines D as 60–69. The issue's `≥55` threshold is technically
  still F-grade, but accepting it as written. If the operator wants to be strict
  about the D-grade interpretation, treat 55–59 as "partial pass — comment but
  do not close" — see Phase 3 alternative branch.
- The `https://soleur.ai/` -> `https://www.soleur.ai/` 301 redirect means audit
  agents fetching the apex domain hit a redirect first; growth-strategist
  follows redirects via WebFetch. No fix required, but worth noting if a
  Presence number diverges from manual inspection.

## Overview

Verify that the third-party validation surface shipped in PR #2596 (live GitHub stars
on homepage + community, Organization JSON-LD with `sameAs` for 5 social URLs +
`subjectOf[NewsArticle]` Inc.com cite, "As seen in" press strip, community stats row +
synthesis paragraph) lifted the **Presence & Third-Party Mentions** sub-score in the
weekly AEO audit from `40/F` to `≥55/D`. Close issue #2615 on pass; file a P1 follow-up
issue + acknowledgment if the score does not lift.

This is a **verification-only** task. No code or content changes are in scope. If the
score misses the threshold, this plan does NOT extend to building remediation — that
work is tracked separately by the existing deferred follow-ups (#2599 G2, #2600
AlternativeTo, #2601 Product Hunt, #2602 TopAIProduct, #2603 first external case
study, #2604 future press expansion).

## Context

- **Issue:** #2615 (`follow-through`, `priority/p3-low`, `type/chore`,
  `domain/marketing`, milestone Phase 4)
- **Source PR:** #2596 — merged 2026-04-18 16:30 UTC, squash commit `62d96ae7`
- **Verification YAML in #2615:** `type: manual, sla_business_days: 30`
- **Audit cadence:** `.github/workflows/scheduled-growth-audit.yml` runs Mondays
  09:00 UTC. Next scheduled run: 2026-04-20.
- **Last audit before fix:** `knowledge-base/marketing/audits/soleur-ai/2026-04-18-aeo-audit.md`
  (Presence row: `40 | F | 5% | 2.0 | 0`)
- **Scoring rubric:** Structure / Authority / Presence (SAP), Presence weighted 5% of
  overall AEO score (so a 40→100 lift moves overall by only ~3 points; the 40→≥55
  threshold matters as a category signal, not as overall-grade arithmetic).
- **Grade scale:** D = 60–69; the issue's `≥55/D` threshold treats anything ≥55 as
  meaningful lift even though strict D starts at 60. The exit criterion below uses
  `≥55` to match the issue.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality (verified) | Plan response |
|---|---|---|
| "Next Growth Audit cron run will re-measure AEO Presence" | `scheduled-growth-audit.yml` exists; runs Mondays 09:00 UTC; produces `<date>-aeo-audit.md` with a Presence row in the Scoring Table. Confirmed via `.github/workflows/scheduled-growth-audit.yml` and `knowledge-base/marketing/audits/soleur-ai/2026-04-18-aeo-audit.md:49`. | Use the cron output as the source of truth. Do not hand-author an audit. |
| "Live GitHub star count replacing the ∞ glyph (homepage + community)" | Shipped in PR #2596 (`plugins/soleur/docs/_data/githubStats.js`). | No re-implementation. Verify rendering on live `soleur.ai` only as a sanity check before / instead of the cron, if cron is delayed. |
| "New Organization JSON-LD with `sameAs` (5 social URLs) + `subjectOf[NewsArticle]`" | Shipped in PR #2596 (`base.njk` `@graph` extension). | Same — verify presence via `curl https://soleur.ai/ \| grep '@id.*organization'` only if cron output is ambiguous. |
| "As seen in" press strip on homepage | Shipped in PR #2596 (`landing-press-strip` partial). | Same — sanity-check via WebFetch only if needed. |
| "Community stats row + synthesis paragraph" | Shipped in PR #2596 (`/community/` page additions). | Same. |
| Presence threshold `≥55/D` | The grade scale defines D as 60–69; 55 is technically still F. | Treat the issue's `≥55` as the literal threshold. Note in the closing comment that 55–59 is sub-D-grade but accepted by the issue text. |
| Audit category weight 5% | Confirmed in `2026-04-18-aeo-audit.md:49`. | Closing comment must explicitly state that even a 40→100 Presence lift moves the overall AEO score by only ~3 weighted points, so reviewers don't expect a B-grade jump. |

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open \
  --json number,title,body --limit 200 > /tmp/open-review-issues.json
for f in plugins/soleur/docs/_data/githubStats.js \
         plugins/soleur/docs/_data/communityStats.js \
         plugins/soleur/docs/_includes/base.njk \
         knowledge-base/marketing/audits/soleur-ai/; do
  jq -r --arg path "$f" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' \
    /tmp/open-review-issues.json
done
```

**Files this plan touches:** none (verification only — no source changes). The audit
report file written by the cron is an artifact of the cron run, not of this plan.

**Result:** None expected — this plan does not edit code-review-overlapping files.
Run the snippet above at execution time to confirm.

## Acceptance Criteria

### Pre-merge (this verification PR — none)

This plan does not produce a merging PR. It produces a verification action that either
(a) closes #2615 with a comment, or (b) escalates by filing a remediation tracker issue
and adding `needs-attention` to #2615.

### Post-trigger (operator / automation)

- [ ] An `aeo-audit.md` report dated on/after 2026-04-20 exists at
  `knowledge-base/marketing/audits/soleur-ai/<date>-aeo-audit.md` (produced by the
  Monday cron or by manual `gh workflow run scheduled-growth-audit.yml`).
- [ ] The Scoring Table row "Presence & Third-Party Mentions" reports a score
  **≥55** (the issue's literal threshold). Numeric extraction from the table — not
  prose.
- [ ] `#2615` is closed with a comment that includes:
  - The new Presence score and grade (e.g., `60/D`, `+20`).
  - The new overall AEO score and grade (for context).
  - A link to the dated audit file (`knowledge-base/marketing/audits/soleur-ai/<date>-aeo-audit.md`).
  - One sentence on the Presence-weight caveat (5% weight; overall delta ~+1 point).
  - The list of off-site follow-up issues (#2599-#2604) that are still OPEN at
    audit time, so credit attribution is unambiguous.
  - If `55 <= score < 60` (PARTIAL PASS): an explicit note that the rubric
    grade scale defines D as 60-69, so the score is technically still F-band
    even though the issue's ≥55 threshold is satisfied. This signals the
    closing operator to watch the next audit for regression.
- [ ] If the score does NOT meet ≥55: a P1 follow-up tracker issue is filed
  (`type/chore`, `domain/marketing`, `priority/p1-high`, milestone Phase 4) titled
  `chore(aeo): Presence score lift insufficient after PR #2596 — investigate` with
  the actual score, the deferred-follow-up issue numbers (#2599–#2604), and a
  request for cmo + seo-aeo-analyst triage. `#2615` gets the `needs-attention` label
  and a comment linking the new tracker. **#2615 stays open** until the new tracker
  is merged or the next audit shows the lift.

## Implementation Phases

### Phase 1 — Wait for or trigger the audit (no code)

The verification artifact is the cron's `<date>-aeo-audit.md` write. Two paths:

- **Default — wait for the Monday 2026-04-20 cron:** The follow-through monitor
  (`.github/workflows/scheduled-follow-through.yml`) will not auto-pass this issue
  because `type: manual` only tracks SLA, not score thresholds. Manual operator
  action is required to read the audit and close the issue.

- **Expedited — trigger now:** Run
  `gh workflow run scheduled-growth-audit.yml` to start an audit on demand. The
  workflow opens a PR (`ci/growth-audit-<timestamp>`) that auto-merges the report into
  `knowledge-base/marketing/audits/soleur-ai/`. Allow ~30–60 minutes for the agent +
  PR auto-merge. Use `gh run watch` to monitor.

**Decision rule:** Trigger expedited only if the operator wants to close #2615 before
Monday or if the Monday cron failed (check via
`gh run list --workflow=scheduled-growth-audit.yml --limit 5`).

### Phase 2 — Extract the Presence score

Once `<date>-aeo-audit.md` exists, use a **column-name lookup** rather than
fixed positional `awk` because the audit table has drifted multiple times
(5 cols on 2026-04-13, 6 cols on 2026-04-18, new SAP shape on 2026-04-21
after the rubric was pinned per PR reconciling #2679). The script locates
the `Score` column by reading the header row, then reads the same column
in the `Presence` row.

**Threshold translation (worked example — cross-rubric):**

The issue's `≥55` threshold normalizes to percentage-of-Presence-category
across both rubric eras:

- **Old format** (`| Presence & Third-Party Mentions | 40 | F | 5% | 2.0 |`):
  Score column is a bare 0–100 integer. `PRESENCE_SCORE=40` → `40 < 55` → FAIL.
- **New SAP format** (`| **Presence** | 25 | 20/25 | 20 | ... |`): Score column
  is `<n>/<weight>`. Normalize: `PRESENCE_SCORE = round(n/weight * 100) = 80`.
  `80 ≥ 55` → PASS. The 2026-04-21 audit proved #2615 under this format.

Both interpretations measure the same thing — what fraction of the rubric's
Presence-category maximum the audit awarded — so the downstream branching
(PASS/PARTIAL/FAIL) and the re-run band (52–58) apply uniformly.

```bash
set -euo pipefail

# Find the latest audit file
LATEST=$(ls -1 knowledge-base/marketing/audits/soleur-ai/*-aeo-audit.md | sort | tail -n 1)
echo "Reading: $LATEST"

# Guard 0: stub-fallback detection (workflow Step 3 writes this on agent failure)
if grep -qiE "(SEO|AEO) audit failed.*see CI logs" "$LATEST"; then
  echo "ERROR: latest audit is the stub-failure fallback. Cannot extract score." >&2
  echo "Action: file P1 tracker, add needs-attention to #2615, do NOT close." >&2
  exit 2
fi

# Locate the Scoring Table header row. Accept either the old "| Category |"
# (pre-2026-04-21) or the new SAP "| Dimension |" header.
HEADER=$(awk '/^\| (Category|Dimension) \|/{print; exit}' "$LATEST")
if [[ -z "$HEADER" ]]; then
  echo "ERROR: no Scoring Table header (expected '| Category |...' or '| Dimension |...')" >&2
  exit 3
fi
# Split the header on '|', strip whitespace, find index of "Score"
SCORE_COL=$(echo "$HEADER" | awk -F'|' '{
  for (i=2; i<=NF; i++) {
    gsub(/^[ \t]+|[ \t]+$/, "", $i)
    if ($i == "Score") { print i; exit }
  }
}')
if [[ -z "$SCORE_COL" ]]; then
  echo "ERROR: Scoring Table header does not contain a 'Score' column" >&2
  exit 4
fi
echo "Score is in column $SCORE_COL"

# Extract the Presence row. Match both the old "Presence & Third-Party Mentions"
# label and the new "**Presence**" bold label. Require NF >= 5 so a legend/footer
# row that happens to mention "Presence" does not match.
PRESENCE_LINE=$(awk -F'|' '
  NF >= 5 && $2 ~ /^ *(\*\*)?Presence(\*\*)?( & Third-Party Mentions)? *$/ { print; exit }
' "$LATEST")
if [[ -z "$PRESENCE_LINE" ]]; then
  echo "ERROR: no table row matches a Presence label (old or new)" >&2
  exit 5
fi

# Extract the Score cell. Accept both formats:
#   - bare integer (old rubric, e.g. "40")
#   - <n>/<weight> fraction (new SAP rubric, e.g. "20/25", tolerant of
#     "20 / 25" that markdownlint reflow can introduce).
SCORE_CELL=$(echo "$PRESENCE_LINE" | awk -F'|' -v c="$SCORE_COL" '{
  gsub(/^[ \t]+|[ \t]+$/, "", $c); print $c
}')
SCORE_CELL_TRIMMED="${SCORE_CELL// /}"    # strip inline spaces ("20 / 25" -> "20/25")
SCORE_CELL_TRIMMED="${SCORE_CELL_TRIMMED//\*/}"  # strip bold markdown markers ("**72**" -> "72")
if [[ "$SCORE_CELL_TRIMMED" =~ ^([0-9]+)/([0-9]+)$ ]]; then
  NUM="${BASH_REMATCH[1]}"; DEN="${BASH_REMATCH[2]}"
  if [[ "$DEN" -eq 0 ]]; then
    echo "ERROR: Presence score denominator is zero in '$SCORE_CELL' (line: $PRESENCE_LINE)" >&2
    exit 6
  fi
  PRESENCE_SCORE=$(awk "BEGIN { printf \"%.0f\", ($NUM / $DEN) * 100 }")
elif [[ "$SCORE_CELL_TRIMMED" =~ ^[0-9]+$ ]]; then
  PRESENCE_SCORE="$SCORE_CELL_TRIMMED"  # old rubric: already 0-100 on category
else
  echo "ERROR: unrecognized Presence score format: '$SCORE_CELL' in line: $PRESENCE_LINE" >&2
  exit 6
fi
if [[ "$PRESENCE_SCORE" -gt 100 ]]; then
  echo "ERROR: normalized Presence score > 100 ('$PRESENCE_SCORE' from '$SCORE_CELL')" >&2
  exit 6
fi
echo "Presence score (percentage-of-category, 0-100): $PRESENCE_SCORE"

# Alias to PRESENCE_PCT for downstream code that prefers the semantic name
# (the plan contract uses "percentage-of-category"). Both names reference
# the same value.
PRESENCE_PCT="$PRESENCE_SCORE"

# Derive a letter grade from PRESENCE_SCORE using the pinned SAP grading
# scale exactly as defined in growth-strategist.md and scheduled-growth-
# audit.yml Step 2 (A >= 90, B 80-89, B+ 75-79, C 60-74, D < 60). The old
# rubric included a separate Grade column per row; the new SAP rubric only
# grades the Total row. Deriving keeps PRESENCE_GRADE populated across
# both eras so downstream comment formatting stays clean. Do NOT introduce
# letters not in the pinned scale — agents produce audits against the
# pinned five-tier scale, and a runbook-internal sixth tier would desync.
if   [[ "$PRESENCE_SCORE" -ge 90 ]]; then PRESENCE_GRADE="A"
elif [[ "$PRESENCE_SCORE" -ge 80 ]]; then PRESENCE_GRADE="B"
elif [[ "$PRESENCE_SCORE" -ge 75 ]]; then PRESENCE_GRADE="B+"
elif [[ "$PRESENCE_SCORE" -ge 60 ]]; then PRESENCE_GRADE="C"
else                                      PRESENCE_GRADE="D"
fi
echo "Presence grade (derived from pinned scale): $PRESENCE_GRADE"

# Extract the overall score. The old rubric used "**Overall**"; the new SAP
# rubric uses "**Total**". Match either.
OVERALL_LINE=$(awk -F'|' '
  NF >= 5 && $2 ~ /^ *\*\*(Overall|Total)\*\* *$/ { print; exit }
' "$LATEST")
if [[ -z "$OVERALL_LINE" ]]; then
  echo "ERROR: no row matches '| **Overall** ...' or '| **Total** ...'" >&2
  exit 7
fi

# Look up the Weighted column index by name (parallel with SCORE_COL lookup).
# The new SAP Total row leaves the Score cell empty and puts the overall total
# in the Weighted column; old rubrics put the overall in Score directly. A
# first-integer-in-line fallback is unsafe because "Weight" (e.g. 100) precedes
# "Weighted" in new SAP column order and would be grabbed first.
WEIGHTED_COL=$(echo "$HEADER" | awk -F'|' '{
  for (i=2; i<=NF; i++) {
    gsub(/^[ \t]+|[ \t]+$/, "", $i)
    if ($i == "Weighted") { print i; exit }
  }
}')

OVERALL_CELL=$(echo "$OVERALL_LINE" | awk -F'|' -v c="$SCORE_COL" '{
  gsub(/^[ \t]+|[ \t]+$/, "", $c); print $c
}')
OVERALL_CELL_TRIMMED="${OVERALL_CELL// /}"
OVERALL_CELL_TRIMMED="${OVERALL_CELL_TRIMMED//\*/}"  # strip bold markers (old audits bold the Overall Score cell)
if [[ "$OVERALL_CELL_TRIMMED" =~ ^[0-9]+$ ]]; then
  OVERALL_SCORE="$OVERALL_CELL_TRIMMED"
elif [[ "$OVERALL_CELL_TRIMMED" =~ ^([0-9]+)/([0-9]+)$ ]]; then
  NUM="${BASH_REMATCH[1]}"; DEN="${BASH_REMATCH[2]}"
  if [[ "$DEN" -eq 0 ]]; then
    echo "ERROR: Overall denominator zero in '$OVERALL_CELL' (line: $OVERALL_LINE)" >&2
    exit 8
  fi
  OVERALL_SCORE=$(awk "BEGIN { printf \"%.0f\", ($NUM / $DEN) * 100 }")
elif [[ -n "$WEIGHTED_COL" ]]; then
  # New SAP Total row fallback: read the Weighted column explicitly.
  OVERALL_SCORE=$(echo "$OVERALL_LINE" | awk -F'|' -v c="$WEIGHTED_COL" '{
    gsub(/^[ \t]+|[ \t]+$/, "", $c); gsub(/[^0-9]/, "", $c); print $c
  }')
else
  echo "ERROR: cannot extract Overall score (Score cell empty, no Weighted column in header) (line: $OVERALL_LINE)" >&2
  exit 8
fi
if ! [[ "$OVERALL_SCORE" =~ ^[0-9]+$ ]] || [[ "$OVERALL_SCORE" -gt 100 ]]; then
  echo "ERROR: extracted Overall score is not a valid integer 0-100: '$OVERALL_SCORE' (line: $OVERALL_LINE)" >&2
  exit 8
fi
echo "Overall AEO score: $OVERALL_SCORE"
```

**Pre-audit live-surface sanity check (recommended before triggering the cron):**

```bash
# Confirm the deployed Presence surface is rendering, not degraded to fallback.
# Verified live at plan-write time (2026-04-19): all 4 signals present.
curl -sSL https://soleur.ai/ -o /tmp/soleur-home.html

# 1. GitHub Stars tile renders an integer (not the ∞ glyph or "—" fallback)
grep -B1 -A3 'GitHub Stars' /tmp/soleur-home.html | grep -oE '<div class="landing-stat-value">[0-9]+</div>' \
  || { echo "FAIL: GitHub Stars tile is not rendering an integer"; exit 10; }

# 2. Press strip partial rendered
grep -q 'class="landing-press-strip"' /tmp/soleur-home.html \
  || { echo "FAIL: landing-press-strip partial missing"; exit 11; }

# 3. Organization JSON-LD with the 5 sameAs URLs
python3 -c "
import re,json,sys
html=open('/tmp/soleur-home.html').read()
blocks=re.findall(r'<script type=\"application/ld\\+json\">(.*?)</script>', html, re.DOTALL)
ok=False
for b in blocks:
    try:
        d=json.loads(b)
        for n in (d.get('@graph') or []):
            if n.get('@type')=='Organization' and len(n.get('sameAs', []))>=5 and n.get('subjectOf'):
                print('OK: Organization node with', len(n['sameAs']), 'sameAs and subjectOf=', n['subjectOf'][0].get('url'))
                ok=True
    except Exception: pass
sys.exit(0 if ok else 12)
" || { echo "FAIL: Organization JSON-LD not as expected"; exit 12; }
```

**Failure modes to guard (extracted from script above):**

- Audit file missing → operator must trigger the cron manually (Phase 1 expedited
  path); do not invent a score.
- **Stub-fallback report** (workflow Step 3 writes "SEO audit failed — see CI logs"
  when the seo-aeo-analyst agent fails) → exit 2; file the P1 follow-up tracker;
  do NOT close #2615.
- **Header row missing** ("Scoring Table" structure changed) → exit 3; re-read
  the audit and adapt the header anchor before re-running.
- **Header row missing the `Score` column** (rubric overhaul) → exit 4; do not
  guess column position.
- **No `Presence & Third-Party Mentions` row** (rubric category renamed) → exit
  5; CMO must triage whether the rubric category was renamed (e.g., to "External
  Validation") and update the anchor in this plan.
- **Extracted Presence value is non-numeric or >100** (parsing drift) → exit 6; abort.
- **Overall row missing** (rubric structure changed) → exit 7; abort.
- **Extracted Overall value is non-numeric or >100** (parsing drift) → exit 8; abort.
- **`gh issue create` output not parseable as an issue number** (gh CLI URL
  format changed) → exit 9; abort.
- **Pre-audit surface check fails** (exit 10/11/12) → re-trigger the docs
  build (`gh workflow run deploy-docs.yml`), wait for it to complete, and re-run
  the surface check before triggering the audit. Do NOT score the audit against
  a degraded deployment.

### Phase 3 — Close or escalate

Three branches, gated on `PRESENCE_SCORE`:

| Branch | Range | Action |
|---|---|---|
| **PASS** | `>= 60` (true D-grade per rubric) | Close #2615 with strong-pass comment |
| **PARTIAL PASS** | `55 <= score < 60` | Close #2615 (issue says ≥55) but flag the F-band caveat in the comment so reviewers know the rubric is still calling Presence F-grade |
| **FAIL** | `< 55` | File P1 tracker, label #2615 `needs-attention`, do NOT close |

The audit-pair re-run rule (see Risks) MUST fire **before** branch selection
when `PRESENCE_SCORE` lands within `THRESHOLD ± 3`, i.e. 52–58. After the
re-run, take the higher of the two scores as canonical and re-enter branch
selection with the canonical value.

#### Phase 3 prelude (run before either branch)

Both branches reference `$AUDIT_REL` and `$OFFSITE_OPEN`. Compute them once
here so the FAIL branch is reachable standalone.

```bash
# Locate the actual audit file path for the link (used by both branches)
AUDIT_REL="knowledge-base/marketing/audits/soleur-ai/$(basename "$LATEST")"

# Enumerate which deferred off-site follow-ups are still open (credit attribution).
# A truly missing issue (404) prints a warning but does not silently disappear.
OFFSITE_OPEN=""
for n in 2599 2600 2601 2602 2603 2604; do
  state=$(gh issue view "$n" --json state --jq .state 2>/dev/null || echo "MISSING")
  if [[ "$state" == "MISSING" ]]; then
    echo "WARN: #$n could not be queried (deleted? renamed? gh auth?); excluding from credit list" >&2
    continue
  fi
  [[ "$state" == "OPEN" ]] && OFFSITE_OPEN="$OFFSITE_OPEN #$n"
done
OFFSITE_OPEN=$(echo "$OFFSITE_OPEN" | sed 's/^ //')
```

#### Branch A — PASS or PARTIAL PASS (`PRESENCE_SCORE >= 55`)

Build the closing comment dynamically so it enumerates which off-site
follow-ups (#2599–#2604) are still open at audit time. **All six are confirmed
OPEN as of plan write (2026-04-19),** so any Presence delta in the next audit
is attributable exclusively to PR #2596's on-site surface.

```bash
# Compute the weighted delta (Presence is 5% of overall in current rubric)
WEIGHTED_DELTA=$(awk "BEGIN { printf \"%.1f\", ($PRESENCE_SCORE - 40) * 0.05 }")

# Determine the F-band caveat (PARTIAL PASS only)
CAVEAT=""
if [[ "$PRESENCE_SCORE" -lt 60 ]]; then
  CAVEAT=$'\n\nNote: rubric grade scale defines D as 60-69, so '"$PRESENCE_SCORE"' is technically still F-band. The issue '"'"'s ≥55 threshold is satisfied, but CMO may want to revisit if the next audit drops back below 55.'
fi

# Write the comment to a file (avoid heredoc-in-CLI quoting headaches)
{
  echo "Verified post-merge: AEO Presence score lifted from 40/F to ${PRESENCE_SCORE}/${PRESENCE_GRADE} (delta +$((PRESENCE_SCORE - 40)))."
  echo
  echo "- Audit: \`${AUDIT_REL}\`"
  echo "- Overall AEO score: ${OVERALL_SCORE}/<grade>"
  echo "- Presence carries 5% weight in the SAP rubric, so the overall delta from this lift is ~+${WEIGHTED_DELTA} points."
  echo "- Off-site follow-ups still open at audit time (so this lift is attributable to PR #2596 alone): ${OFFSITE_OPEN:-none}."
  echo "- The remaining Presence ceiling is held by those off-site items: directory submissions (G2 / AlternativeTo / Product Hunt / TopAIProduct) and the first external case study."
  if [[ -n "$CAVEAT" ]]; then echo "$CAVEAT"; fi
  echo
  echo "Closes #2615."
} > /tmp/aeo-pass-comment.md

# Post comment via --body-file (safe from shell expansion of file contents),
# then close. `gh issue close` itself only supports --comment <string>, so we
# split the operations to avoid `--comment "$(cat ...)"` re-interpolation.
gh issue comment 2615 --body-file /tmp/aeo-pass-comment.md
gh issue close 2615 --reason completed
```

#### Branch B — FAIL (`PRESENCE_SCORE < 55`)

```bash
# 1. Build the tracker body
{
  echo "## Context"
  echo
  echo "Follow-through verification of PR #2596 (#2615) found that the AEO Presence sub-score did NOT lift to the ≥55 threshold."
  echo
  echo "- Latest audit: \`${AUDIT_REL}\`"
  echo "- Pre-PR Presence: 40/F (2026-04-18 audit)"
  echo "- Post-PR Presence: ${PRESENCE_SCORE}/${PRESENCE_GRADE} (delta $(( PRESENCE_SCORE - 40 )))"
  echo "- Issue threshold: ≥55"
  echo
  echo "## Why this is unexpected"
  echo
  echo "PR #2596 shipped a verified-deployed Presence surface (live GitHub stars on homepage + community, Organization JSON-LD with 5 sameAs URLs + subjectOf[NewsArticle], 'As seen in' press strip, community stats row). Live verification at $(date +%Y-%m-%d) confirmed all four signals render on https://soleur.ai/ . The growth-strategist's Presence rubric was expected to recognize at least three of these signals."
  echo
  echo "## Triage hypotheses (for CMO + seo-aeo-analyst)"
  echo
  echo "1. Rubric weights visible-copy press higher than JSON-LD press (subjectOf is structured data; press strip is visible). The shipped strip cites only Inc.com — possibly insufficient visible variety."
  echo "2. The Presence rubric requires off-site signals (G2, AlternativeTo, Product Hunt) to move at all — in which case the lift will only register after #2599/#2600/#2601/#2602 land. If true, this issue should block on those."
  echo "3. The rubric's ceiling on 'pure on-site Presence' is below 55 by design. Verify against the \`**Presence**\` heading in \`plugins/soleur/agents/marketing/growth-strategist.md\`."
  echo "4. The audit run was non-deterministic and produced a low-end result; re-run once before triaging."
  echo
  echo "## Action items"
  echo
  echo "- [ ] Re-run \`gh workflow run scheduled-growth-audit.yml\` once to control for non-determinism. If the second run reports ≥55, close this and #2615 with both audits cited."
  echo "- [ ] If the second run also <55, CMO triages hypotheses 1–3 above."
  echo "- [ ] Decide whether #2615 should block on #2599/#2600/#2601/#2602 (off-site directory submissions)."
  echo "- [ ] Update the SAP rubric in \`growth-strategist.md\` if hypothesis 3 is correct."
  echo
  echo "## Off-site follow-ups still open"
  echo
  echo "${OFFSITE_OPEN:-none}"
  echo
  echo "Source: #2596 (the on-site half of the AEO ceiling lift)."
  echo "Tracking: #2615 (this issue stays open until either audit shows the lift or rubric is re-anchored)."
} > /tmp/aeo-followup.md

# 2. File the P1 tracker. `gh issue create` prints a URL like
# https://github.com/owner/repo/issues/2648 — extract the last path component
# via awk -F/ rather than a regex that could match adjacent digits.
NEW_URL=$(gh issue create \
  --title "chore(aeo): Presence score lift insufficient after PR #2596 — investigate" \
  --label "priority/p1-high,type/chore,domain/marketing" \
  --milestone "Phase 4: Validate + Scale" \
  --body-file /tmp/aeo-followup.md)
NEW=$(echo "$NEW_URL" | awk -F/ '{print $NF}')
if ! [[ "$NEW" =~ ^[0-9]+$ ]]; then
  echo "ERROR: could not parse issue number from gh output: '$NEW_URL'" >&2
  exit 9
fi
echo "Filed #$NEW"

# 3. Mark #2615 needs-attention and link the tracker (do NOT close).
# Strip the "-aeo-audit.md" suffix from the audit filename to get the date stamp.
AUDIT_DATE=$(basename "$LATEST" "-aeo-audit.md")
gh issue edit 2615 --add-label "needs-attention"
gh issue comment 2615 --body "AEO Presence audit at ${AUDIT_DATE} reported ${PRESENCE_SCORE} (below the issue's ≥55 threshold). Filed #${NEW} for triage. This issue stays open until the next audit shows the lift or #${NEW} is resolved."
```

## Test Scenarios (manual, operator-driven)

| Scenario | Action | Expected |
|---|---|---|
| Happy path: cron runs, score ≥55 | Phase 2 extracts score; Phase 3 close branch fires | #2615 closed with score + audit link comment |
| Cron-day score <55 but >40 | Phase 3 escalation branch fires | New P1 tracker exists; #2615 has `needs-attention` and a link comment; #2615 still open |
| Cron-day score ≤40 (no lift) | Same as <55 path; tracker body explicitly notes the lift was zero | Same |
| Audit file missing on Monday >12:00 UTC | Operator runs `gh workflow run scheduled-growth-audit.yml`; waits for PR auto-merge | New `<date>-aeo-audit.md` exists; Phase 2 proceeds |
| Audit step 3 returned the stub fallback ("SEO audit failed — see CI logs.") | Skip the score extraction; do not infer a Presence number from a missing AEO report | File P1 tracker referencing the failed cron run; #2615 needs-attention |
| Table format changed (e.g., column reorder) | Re-read the latest audit, locate column by header name, abort if anchor missing | No silent default; operator notified to update Phase 2 anchors |
| New SAP rubric with fraction score (e.g., `20/25`) | Phase 2 parser normalizes fraction → percentage-of-category | `PRESENCE_SCORE=80`, `PRESENCE_GRADE=B`, PASS branch (threshold ≥55) |
| Old rubric with bare integer score (e.g., `40`) | Phase 2 parser treats bare integer as already-normalized | `PRESENCE_SCORE=40`, `PRESENCE_GRADE=D` (below 60 per pinned scale), FAIL branch (below ≥55) |
| Score cell reflowed with whitespace (e.g., `20 / 25`) | Parser strips inline whitespace before matching | Parsed identically to `20/25` |
| New SAP Total row with empty Score cell (e.g., `\| **Total** \| 100 \| \| 78 \| B+ \|`) | Parser reads Weighted column via header lookup | `OVERALL_SCORE=78` (not 100, the Weight) |

## Risks

- **Audit non-determinism.** The growth audit invokes WebFetch + the
  growth-strategist / seo-aeo-analyst agents — the same site can be scored
  slightly differently on consecutive runs. Princeton GEO research (cited in
  `knowledge-base/project/learnings/2026-02-20-geo-aeo-methodology-incorporation.md`)
  reports per-technique impact ranges of `+15-30%` to `+30-40%` for individual
  citation/quotation/statistic injections — implying score variance of ±5–10
  points on identical content across runs is normal. **Mitigation: audit-pair
  re-run rule.** If `PRESENCE_SCORE` lands within ±3 of the issue's ≥55
  threshold (i.e. 52–58 inclusive — straddles all three Phase 3 branches),
  re-trigger the cron once via `gh workflow run scheduled-growth-audit.yml`,
  wait for the PR to auto-merge, and take the higher of the two scores as
  canonical before re-entering branch selection. The re-run rule fires BEFORE
  the PASS/PARTIAL/FAIL branching so a borderline 53 isn't escalated as FAIL
  when a re-run would clear the ≥55 bar (and vice versa for a 58 that drops
  on re-run). Record both audit dates and scores in the closing comment or
  tracker body so future readers can audit the decision.
- **GitHub stars API failure on the live site.** `_data/githubStats.js` is CI-fail-fast
  but soft-fail in dev. If the build at audit time degraded the homepage stars tile to
  the dev fallback, the auditor may score Presence lower than the deployed best case.
  Mitigation: before scoring, sanity-check via
  `curl -s https://soleur.ai/ | grep -E 'GitHub Stars|stars-tile'` to confirm the
  live tile renders an integer; if it shows a placeholder, re-trigger the docs
  build (`gh workflow run deploy-docs.yml`) and re-run the audit.
- **Subjective re-scoring.** The Presence rubric checks "third-party mentions",
  "as featured in" surfaces, and citation monitoring. The growth-strategist agent's
  scoring is rubric-anchored but partly subjective. Mitigation: the closing comment
  must include the actual `Presence` row text from the audit so future readers can
  diff scoring rationale across runs.
- **Race with the deferred off-site work.** If #2599–#2603 land in the same audit
  window, the Presence lift will mix on-site (PR #2596) and off-site contributions —
  reviewers may miscredit the lift. Mitigation: the closing comment lists which of
  #2599–#2603 are still open at audit time so credit attribution is unambiguous.

## Non-Goals

- Building any new on-site Presence surface (already shipped in PR #2596).
- Submitting to G2 / AlternativeTo / Product Hunt / TopAIProduct (tracked in
  #2599–#2602).
- Authoring an external case study (tracked in #2603).
- Expanding the "As seen in" press strip with new outlets (tracked in #2604).
- Modifying the SAP rubric weights or the growth-audit workflow.
- Building automated parsing of audit reports into the follow-through monitor (would
  be a separate skill/workflow change; see Future Work).

## Future Work (not in this plan)

- **Automate AEO score extraction in `scheduled-follow-through.yml`.** Add a
  `type: aeo-score` predicate that reads the latest `<date>-aeo-audit.md`, extracts a
  named SAP category score, and passes/fails against a threshold. Would let future
  follow-through items like #2615 auto-close without operator action. File as a
  separate issue if the manual flow proves repeated.
- **Persist Presence score history.** A simple JSON file under
  `knowledge-base/marketing/audits/soleur-ai/presence-score-history.json` would let
  the growth-strategist agent compute deltas without parsing 12 markdown files.

## Files to edit

- None. Verification-only.

## Files to create

- None during plan execution. The growth-audit cron will create
  `knowledge-base/marketing/audits/soleur-ai/<YYYY-MM-DD>-aeo-audit.md` as a
  byproduct, but that is the cron's artifact, not this plan's deliverable.
- If escalation: `/tmp/aeo-followup.md` (transient body file for `gh issue create`).

## Domain Review

**Domains relevant:** Marketing (CMO)

### Marketing (CMO)

**Status:** assessed inline by planner (operator may invoke `cmo` agent for richer
review if Phase 3 escalates).

**Assessment:** This is a verification of a marketing-domain delivery (AEO surface
shipped in PR #2596). The CMO domain owns the SAP scoring rubric and the deferred
off-site follow-ups (#2599–#2604). No new marketing decisions are made in this
plan — it only confirms the on-site half of the P0-2 action list lifted Presence
as forecast.

If escalation fires (score <55), the new tracker issue MUST be assigned `domain/marketing`
and the CMO is the primary reviewer. The CMO should triage:
(a) whether the on-site surface needs strengthening (e.g., the Inc.com `subjectOf` is
not weighted as "press" by the rubric — try expanding to a `Mention` array with the
existing community references), (b) whether the auditor's Presence rubric is
mis-calibrated against the deployed surface (compare prompt to `growth-strategist.md`
"Presence" section), or (c) whether the off-site submissions (#2599–#2603) need to
land before the score will move at all (in which case #2615 should be relabeled to
block on those issues).

No Product/UX Gate: no new user-facing pages, no new components, no new flows.
No CTO involvement: no architectural change.

## CLI-Verification

Every CLI invocation prescribed in this plan is a stable, well-documented form:

- `gh issue close <N> --reason completed` paired with a preceding
  `gh issue comment <N> --body-file <path>` — `gh issue close` does NOT
  support `--body-file`, only `--comment <string>`. Splitting the operations
  avoids `gh issue close --comment "$(cat ...)"`, which would re-expand
  shell metacharacters from the file content.
- `gh issue create --title --label --milestone --body-file` — used pervasively
  in this repo (see `.github/workflows/scheduled-growth-audit.yml` Step 5.5).
  `gh issue create` prints a URL on success; parse the issue number with
  `awk -F/ '{print $NF}'` (NOT a `--json` flag — `gh issue create` has no
  `--json` support, verified via `gh issue create --help`).
- `gh issue edit <N> --add-label` — standard.
- `gh issue comment <N> --body` — standard.
- `gh workflow run <file>.yml` — standard, used in AGENTS.md `wg-after-merging-a-pr-that-adds-or-modifies`.
- `gh run watch` / `gh run list --workflow= --limit` — standard.
- `awk -F'|'`, `grep -E`, `sort | tail -n 1` — POSIX shell.
- `python3` — used inline for the optional pre-audit JSON-LD parse. The growth-
  audit cron itself does not depend on python3; this snippet is operator-side
  only. If `python3` is absent locally, swap to `jq` against an extracted
  JSON-LD blob or skip the surface check.
- No fabricated subcommands or flags; no `npm` or `bun` invocations; no Doppler
  reads.

The escalation `gh issue create --label "priority/p1-high,type/chore,domain/marketing"`
uses comma-separated label names. Verified label names match the repo convention
documented in `cq-gh-issue-label-verify-name`:

```bash
gh label list --limit 100 | grep -E "priority/p1-high|type/chore|domain/marketing|needs-attention"
```

The `needs-attention` label (used in Branch B `gh issue edit 2615
--add-label "needs-attention"`) is verified to exist with description "SLA
exceeded, requires human action" (color `#D93F0B`).

The milestone string `"Phase 4: Validate + Scale"` is the exact title from
`gh issue view 2615 --json milestone` (matches `cq-gh-issue-create-milestone-takes-title`).

## Out of Scope

- Code changes (none required — work shipped in PR #2596).
- New tests (no code under test).
- Database migrations (none).
- Terraform changes (none).
- Workflow changes (none — using existing `scheduled-growth-audit.yml`).

## How to resume / hand off

If the operator running this verification cannot complete it in one sitting (e.g.,
Monday cron has not run yet), leave #2615 open with no `needs-attention` label.
The next operator should:

1. Read `knowledge-base/project/plans/2026-04-19-chore-aeo-presence-reaudit-after-pr-2596-plan.md`
   (this file).
2. Run `ls -1 knowledge-base/marketing/audits/soleur-ai/*-aeo-audit.md | sort | tail -n 1`
   to find the latest audit.
3. If the latest audit is dated `>= 2026-04-20`, proceed to Phase 2.
4. If not, run `gh workflow run scheduled-growth-audit.yml` and wait for the
   `ci/growth-audit-*` PR to auto-merge, then proceed to Phase 2.

## Definition of Done

- `#2615` is in a terminal state — either CLOSED (score ≥55, comment recorded
  with audit link + score + weight caveat) or OPEN with `needs-attention` and a
  linked P1 tracker (score <55).
- The audit file used for the decision is committed to main under
  `knowledge-base/marketing/audits/soleur-ai/`.
- No code, content, workflow, or infra changes shipped from this plan.
