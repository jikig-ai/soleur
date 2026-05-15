---
title: Bundled secret-scan hardening sweep
type: bundled-fix
classification: ci-tooling-hardening
lane: cross-domain
created: 2026-05-15
branch: feat-one-shot-secret-scan-hardening-sweep
closes: [3759, 3322, 3323, 3160]
related: [3121, 3268, 3281, 3194]
requires_cpo_signoff: false
---

# Bundled secret-scan hardening sweep — fix #3759 #3322 #3323 #3160 in one PR

## Overview

Four open issues in the secret-scanning floor (#3121-era) collapse into a single CI-tooling hardening PR because they share the same surface (`.gitleaks.toml`, `.github/workflows/secret-scan.yml`, `apps/web-platform/scripts/lint-fixture-content.mjs`, runbook) and the same review path (CODEOWNERS-gated). Bundling avoids 4 sequential CODEOWNERS round-trips and lets the rename-laundering guard (#3160) and the allowlist-diff gate (#3323) share an `.gitleaks.toml`-allowlist-parser helper.

The four sub-fixes:

1. **#3759 — Synthesize the JWT fixture.** Replace the JWT-shape line in `plugins/soleur/skills/incident/test/fixtures/positive-corpus.md` with a structurally-broken-but-sentinel-matching token. The fixture exists to exercise the redact-sentinel's positive-class detection (`scripts/redact-sentinel.sh`); the new shape MUST keep that test green.
2. **#3322 — Extend lint-fixture-content glob.** Add `knowledge-base/project/learnings/**/*.md` to both lefthook and the CI workflow's two file-set extractors so future `# gitleaks:allow` waivers in learnings carry the `issue:#NNN <reason>` trailer.
3. **#3323 — Allowlist-diff CI gate.** New CI job that diffs `paths = [...]` arrays in `.gitleaks.toml` between PR base and head, comments on the PR with added paths, and requires explicit acknowledgement (label OR commit trailer).
4. **#3160 — Rename-laundering CI guard.** New CI job that fails on `git mv` into any allowlisted path unless the PR carries `secret-scan-allow-rename` label OR a commit trailer `Rename-Allowed-By: <name>`.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality (verified at plan time) | Plan response |
|---|---|---|
| #3759: "real-shape JWT in positive-corpus.md fires gitleaks `jwt` rule" | Current line 13 is `eyJaaaa...aaaa.aaaa...aaaa.aaaa...aaaa` — does NOT match the gitleaks `jwt` regex (`ey[A-Za-z0-9_-]{17,}\.ey[A-Za-z0-9_-]{17,}\.[A-Za-z0-9_-]{10,}`) because seg2 doesn't start with `ey`. The leak commit `687ace6e` is on an unmerged branch. The new top-level allowlist (`.gitleaks.toml` line 83: `plugins/soleur/skills/.*/test/fixtures/.*\.md$`) also covers the path now. | Phase 0 verifies via local `gitleaks git --no-banner` against this branch. Even if 0 findings, still synthesize to a placeholder-word shape that is unmistakably non-real (no `aaaa`-padding cosplay), per `cq-test-fixtures-synthesized-only` intent. |
| #3759 suggested form `eyJ.HEADER.PLACEHOLDER.SIG` | Each segment after `eyJ` is too short for the redact-sentinel JWT regex (`eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}`); using literally that form would break Test 2.JWT in `redact-sentinel.test.sh:64`. | Plan uses a longer placeholder form (≥10 chars per segment, no `eyJ`/`ey` in seg2/3) — see Phase 2 fixture. |
| #3322: "linter glob doesn't scan learnings" | Verified — `lefthook.yml:36-44` glob lists `apps/web-platform/test/{fixtures,__synthesized__,__goldens__}/**`, `**/__goldens__/**`, `**/*.snap`. CI workflow `secret-scan.yml:107` and `:115` grep -E lists same paths. Neither covers `knowledge-base/project/learnings/**/*.md`. One existing waiver lives at `knowledge-base/project/learnings/best-practices/2026-05-05-leak-tripwire-self-trips-on-mask-registrations.md` (with valid `# issue:#3268` trailer). | Phase 3 extends BOTH lefthook glob AND both grep -E patterns in `secret-scan.yml`. |
| #3323: "no CI gate diffs `paths` arrays" | Verified — only `waiver-discipline` job exists; CODEOWNERS gates `.gitleaks.toml` to `@jeanderuelle` (single-reviewer). | Phase 5 adds new `allowlist-diff` job. |
| #3160: "rename-laundering allowed at v8.24.2" | Verified — `secret-scan.yml:285-296` `rename-laundering` smoke case empirically prints `VERDICT: rename-laundering=allowed`. Runbook §Rename-laundering documents the gap; #3160 is the tracked follow-up. | Phase 4 adds new `rename-guard` job. The existing smoke matrix `rename-laundering` case becomes a TWO-stage check: (a) confirm gitleaks itself still allows it (canary on bumps), (b) confirm the new `rename-guard` job fires. Phase 4 splits the smoke into `rename-laundering-baseline` (existing) + `rename-guard-fires` (new). |
| `secret-scan-allow-rename` label exists | Verified absent via `gh label list --limit 200 \| grep -E "^secret-scan"` returns empty. | Phase 0.1 creates the label via `gh label create`. Same applies to `secret-scan-allowlist-ack` (also absent). |

## User-Brand Impact

**If this lands broken, the user experiences:** No direct user-facing impact — failure mode is a missed real-credential leak landing in the public repo. CI-tooling-only PR; no production code path, no schema, no runtime surface.

**If this leaks, the user's data is exposed via:** N/A directly. Indirect path: the four hardening gates collectively reduce the probability that a future PR launders a real credential into an allowlisted fixture path. Pre-existing defense-in-depth (GitHub push protection, CODEOWNERS) remains the load-bearing floor.

**Brand-survival threshold:** none — reason: CI gate hardening; no user data path, no credential storage path, no runtime surface. Pre-existing GitHub push protection covers the well-known token shapes regardless of allowlist state.

## Domain Review

**Domains relevant:** Engineering (CTO scope) — CI/workflow + linter + runbook. No Product, Legal, Finance, Marketing, Sales, Support, or Operations implications.

### Engineering (CTO)

**Status:** reviewed (inline at plan time — single-domain CI-hardening PR within established secret-scanning-floor pattern from #3121).

**Assessment:** Bundling 4 issues touching the same 3 files (`secret-scan.yml`, `.gitleaks.toml`, `lint-fixture-content.mjs` + runbook) into one PR is the correct CODEOWNERS-cost optimization. The shared `.gitleaks.toml`-paths-extractor helper (used by #3160 + #3323) is the right DRY boundary. Risk profile is low — gates are additive (new jobs that fail-closed on positive matches), no existing behavior is relaxed. Defense-relaxation analysis (per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`) NOT triggered: no defense is widened or removed.

## Files to Edit

- `plugins/soleur/skills/incident/test/fixtures/positive-corpus.md` — replace JWT line (#3759, Phase 2)
- `apps/web-platform/scripts/lint-fixture-content.mjs` — no edit needed; the script reads paths from argv. The CHANGE is upstream in lefthook + workflow globs (#3322, Phase 3)
- `lefthook.yml` — extend `lint-fixture-content` glob (#3322, Phase 3)
- `.github/workflows/secret-scan.yml` — extend grep -E patterns (#3322, Phase 3); add `rename-guard` job (#3160, Phase 4); add `allowlist-diff` job (#3323, Phase 5); split `rename-laundering` smoke into baseline + guard-fires (Phase 4)
- `knowledge-base/engineering/operations/secret-scanning.md` — update §Rename-laundering ("Follow-up tracked" → "Mitigation: see `rename-guard` job"); add §Allowlist-diff gate; add §Linter glob coverage now includes learnings (Phase 6)
- `.github/CODEOWNERS` — verify the new helper script gets coverage. Add line if helper lives outside already-covered paths (Phase 0)

## Files to Create

- `apps/web-platform/scripts/parse-gitleaks-allowlists.mjs` — shared helper that parses `.gitleaks.toml` and emits the union of allowlisted-path regexes as a JSON array on stdout. Used by both `rename-guard` (#3160) and `allowlist-diff` (#3323) jobs (Phase 1)
- `apps/web-platform/test/__synthesized__/parse-gitleaks-allowlists.test.sh` — RED/GREEN harness for the helper (Phase 1)

## Acceptance Criteria

### Pre-merge (CI / reviewer)

- [ ] AC1 — Local `gitleaks git --no-banner --exit-code 1` exits 0 on this branch BEFORE Phase 2 (verifies the existing fixture state); exits 0 AFTER Phase 2 (verifies the new placeholder-word JWT didn't introduce a leak).
- [ ] AC2 — `bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh` passes all 4 tests (Test 2.JWT specifically — the new fixture must still exercise the JWT regex class). Verification: `grep -c "Total: [0-9]\+ pass, 0 fail"` returns 1.
- [ ] AC3 — Lefthook `lint-fixture-content` hook fires when a `# gitleaks:allow` waiver missing the `issue:#NNN <reason>` trailer is staged in `knowledge-base/project/learnings/**/*.md`. Verification: see Phase 3 RED test.
- [ ] AC4 — CI `lint-fixture-content` job (both PR-diff and push/schedule branches) includes `knowledge-base/project/learnings/` in its grep -E pattern. Verification: `grep -c "knowledge-base/project/learnings" .github/workflows/secret-scan.yml` returns ≥2.
- [ ] AC5 — `apps/web-platform/scripts/parse-gitleaks-allowlists.mjs` exits 0 on `.gitleaks.toml` and emits valid JSON. Verification: `node apps/web-platform/scripts/parse-gitleaks-allowlists.mjs .gitleaks.toml | jq -e 'type == "array"'` exits 0.
- [ ] AC6 — `parse-gitleaks-allowlists.test.sh` passes (RED/GREEN harness covers: malformed TOML, missing file, top-level allowlist, per-rule allowlists, dedupe across rules, regex-meta-char-safe paths).
- [ ] AC7 — `rename-guard` job in `secret-scan.yml` fires on `git mv apps/web-platform/server/X.ts apps/web-platform/test/__synthesized__/Y.ts` UNLESS the PR carries `secret-scan-allow-rename` label OR commit trailer `Rename-Allowed-By: <name>`. Verification: smoke matrix `rename-guard-fires` case.
- [ ] AC8 — `allowlist-diff` job fires on a PR that adds a `paths = [...]` entry under any `[[rules.allowlists]]` or `[allowlist]` block. Job posts a PR comment listing added paths. Verification: smoke matrix `allowlist-diff-fires` case OR a manual `gh pr comment --list` check after a fixture PR.
- [ ] AC9 — `allowlist-diff` job permission scope is `pull-requests: write` ONLY (no `contents: write`). Verification: `awk '/^  allowlist-diff:/,/^  [a-z-]+:$/' .github/workflows/secret-scan.yml | grep -E "^\s+(pull-requests|contents):"` shows `pull-requests: write` and no other write permission.
- [ ] AC10 — `rename-guard` job permission scope is `contents: read` ONLY (read-only diff inspection). Verification: same awk pattern over `rename-guard:`.
- [ ] AC11 — Labels `secret-scan-allow-rename` and `secret-scan-allowlist-ack` exist in repo. Verification: `gh label list --limit 200 | grep -E "^(secret-scan-allow-rename|secret-scan-allowlist-ack)\b" | wc -l` returns 2.
- [ ] AC12 — Existing smoke matrix `rename-laundering` case still runs and prints VERDICT (canary on gitleaks bumps). Verification: `grep -c "rename-laundering" .github/workflows/secret-scan.yml` returns ≥1, AND a freshly-triggered CI run on a draft PR shows `VERDICT: rename-laundering=allowed` in the step summary.
- [ ] AC13 — Runbook §Rename-laundering "Follow-up tracked: #3160" callout removed; replaced with "Mitigation: `rename-guard` CI job fails on `git mv` into allowlisted paths unless overridden by label/trailer".
- [ ] AC14 — Runbook gains a new §Allowlist-diff gate section AND §Waiver linter (now covers learnings).
- [ ] AC15 — `git diff main..HEAD --name-only` shows no other files modified beyond the 6 in `## Files to Edit` + 2 in `## Files to Create`.
- [ ] AC16 — PR body includes `Closes #3759 #3322 #3323 #3160` on its own line (per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] AC17 — All review agents pass (DHH, Kieran, code-simplicity, security-sentinel, architecture-strategist).

### Post-merge (operator)

- [ ] AC18 — Verify the new `rename-guard` and `allowlist-diff` jobs appear as required checks in branch protection (`gh api repos/jikig-ai/soleur/branches/main/protection/required_status_checks --jq '.contexts'` includes both job names). If absent, add via `gh api ... --method PATCH`.
- [ ] AC19 — Trigger a manual canary by creating an intentional rename-into-`__synthesized__` on a throwaway branch and confirm the `rename-guard` job fails the PR check.

## Implementation Phases

### Phase 0 — Preconditions (label creation, baseline verification)

0.1. Create labels:

```bash
gh label create secret-scan-allow-rename \
  --description "Override the rename-guard job for renames into gitleaks-allowlisted paths" \
  --color "FBCA04"

gh label create secret-scan-allowlist-ack \
  --description "Acknowledgement that this PR widens .gitleaks.toml allowlist paths (per #3323 gate)" \
  --color "FBCA04"
```

0.2. Baseline-verify current state:

```bash
# Install gitleaks v8.24.2 locally if not present (use the same SHA from secret-scan.yml line 44).
gitleaks git --no-banner --exit-code 1 || echo "Pre-existing findings — must be 0 before Phase 2."
bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh
```

0.3. CODEOWNERS check: `apps/web-platform/scripts/parse-gitleaks-allowlists.mjs` lives under a path NOT currently in CODEOWNERS. Either (a) add a CODEOWNERS line `/apps/web-platform/scripts/parse-gitleaks-allowlists.mjs @jeanderuelle` (mirrors `lint-fixture-content.mjs`), or (b) add the entry under a wider scripts/ glob if one exists. Verification: `grep -E "parse-gitleaks-allowlists" .github/CODEOWNERS` returns ≥1.

### Phase 1 — Shared allowlist-paths parser

Create `apps/web-platform/scripts/parse-gitleaks-allowlists.mjs`:

- Input: path to a `.gitleaks.toml` file (single positional arg). Default `.gitleaks.toml`.
- Output: JSON array on stdout. Each element is a string (the regex literal as it appears in the TOML `paths = [...]` array — `'''…'''`-delimited triple-quote literals stripped of delimiters, NOT compiled).
- Behavior: parse the TOML using either Node's built-in toml support OR a lightweight regex-only walker (no new deps). Walk both the top-level `[allowlist]` `paths = [...]` AND every `[[rules.allowlists]]` `paths = [...]` block. Dedupe.
- Edge cases: missing file → exit 2; malformed TOML → exit 3; empty allowlist → emit `[]`.

**Implementation note:** Adding `toml` as a runtime dep for one helper script is overkill. A regex-based walker over `\[\[rules\.allowlists\]\]` and `\[allowlist\]` blocks with `paths\s*=\s*\[(.*?)\]` (DOTALL) extraction is sufficient and parallels the existing `lint-fixture-content.mjs` no-dep convention. Cite this rationale in a top-of-file comment.

Create `apps/web-platform/test/__synthesized__/parse-gitleaks-allowlists.test.sh` — RED/GREEN harness mirroring `redact-sentinel.test.sh` shape. Test cases:

- T1: missing file → exit 2.
- T2: malformed TOML → exit 3.
- T3: empty allowlist → exit 0, output `[]`.
- T4: top-level `[allowlist]` only → output contains those paths.
- T5: per-rule `[[rules.allowlists]]` only → output contains those paths, deduped across rules.
- T6: mixed top-level + per-rule with overlap → output is the deduped union.
- T7: regex-meta-char-safe — paths containing `\.`, `(?:…)`, character classes are emitted verbatim.

### Phase 2 — Synthesize JWT fixture (#3759)

Edit `plugins/soleur/skills/incident/test/fixtures/positive-corpus.md` line 13. Replace:

```
eyJaaaaaaaaaaaaaaaaaa.aaaaaaaaaaaaaaaaaaa.aaaaaaaaaaaaaaaaaa
```

With (placeholder-word form, ≥10 chars per segment after `eyJ`, no `ey` prefix on segments 2 or 3 to avoid the gitleaks default `jwt` regex `ey[A-Za-z0-9_-]{17,}\.ey[A-Za-z0-9_-]{17,}\.[A-Za-z0-9_-]{10,}`):

```
eyJsynthesized_HEADER_placeholder.synthesized_PAYLOAD_placeholder.synthesized_SIGNATURE_placeholder
```

This shape:
- Matches the redact-sentinel JWT regex `eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}` ✓
- Does NOT match the gitleaks default `jwt` regex (seg 2 is `synthesized_PAYLOAD_placeholder`, no `ey` prefix) ✓
- Reads as obviously synthetic on visual inspection (placeholder words instead of opaque `aaaa` padding) — closes the original "looks like a real-shape JWT" aesthetic concern.

Verify: re-run `bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh` (Test 2.JWT must remain green) and `gitleaks git --no-banner --exit-code 1` (still 0 findings).

### Phase 3 — Extend linter glob to learnings (#3322)

3.1. RED test: stage a fixture-only file at `knowledge-base/project/learnings/best-practices/_red-test.md` containing a line `<!-- gitleaks:allow -->` (waiver missing the trailer). Run `lefthook run pre-commit --commands lint-fixture-content` and confirm it does NOT fire (current bug). Run the linter directly: `node apps/web-platform/scripts/lint-fixture-content.mjs knowledge-base/project/learnings/best-practices/_red-test.md` — confirm it DOES fire (linter logic is already correct; the gap is the glob).

3.2. Edit `lefthook.yml` `lint-fixture-content` glob (around line 36-44):

```yaml
    lint-fixture-content:
      priority: 4
      glob:
        - "apps/web-platform/test/fixtures/**"
        - "apps/web-platform/test/__synthesized__/**"
        - "apps/web-platform/test/__goldens__/**"
        - "**/__goldens__/**"
        - "**/*.snap"
        - "knowledge-base/project/learnings/**/*.md"   # added: #3322
      run: node apps/web-platform/scripts/lint-fixture-content.mjs {staged_files}
```

3.3. Edit `.github/workflows/secret-scan.yml` lines 105-116. Both grep -E patterns (PR-diff branch line 107, push/schedule branch line 115) need to add `|^knowledge-base/project/learnings/.*\.md$` to the alternation. Final form for the PR-diff grep:

```yaml
            | grep -E '^(apps/web-platform/test/(fixtures|__synthesized__|__goldens__)/|.*/__goldens__/|.*\.snap$|knowledge-base/project/learnings/.*\.md$)' \
```

(Mirror in the push/schedule branch.)

3.4. GREEN test: re-run lefthook + the CI workflow's grep against a staged learnings file. Confirm both fire on a malformed-trailer waiver. Delete `_red-test.md` before commit.

### Phase 4 — Rename-laundering CI guard (#3160)

4.1. Add a new job `rename-guard` to `.github/workflows/secret-scan.yml` (after `waiver-discipline`, before `smoke-tests`):

```yaml
  # ===========================================================================
  # 5. Rename-laundering guard (#3160). gitleaks v8.24.2 evaluates path
  #    allowlists against the DESTINATION of a `git mv` and does not re-scan
  #    the diff content against the source. A `git mv server/X.ts
  #    test/__synthesized__/Y.ts` slips a real secret past the gate. This job
  #    blocks the rename unless an operator opts in.
  # ===========================================================================
  rename-guard:
    name: rename-guard (allowlist destinations)
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    if: github.event_name == 'pull_request'
    permissions:
      contents: read
    steps:
      - name: Checkout
        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        with:
          fetch-depth: 0

      - name: Inspect PR for renames into allowlisted paths
        env:
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
          HEAD_SHA: ${{ github.event.pull_request.head.sha }}
          PR_LABELS: ${{ toJSON(github.event.pull_request.labels.*.name) }}
        run: |
          set -euo pipefail

          # 1. Extract allowlisted-path regexes from .gitleaks.toml.
          mapfile -t ALLOW_RES < <(node apps/web-platform/scripts/parse-gitleaks-allowlists.mjs .gitleaks.toml | jq -r '.[]')
          if [[ ${#ALLOW_RES[@]} -eq 0 ]]; then
            echo "No allowlist paths to guard; skipping."
            exit 0
          fi

          # 2. Find renames in the PR diff. R-status with --name-status emits:
          #    R<score>\t<source>\t<target>
          renames=$(git diff --diff-filter=R --name-status "${BASE_SHA}..${HEAD_SHA}" || true)
          if [[ -z "${renames}" ]]; then
            echo "No renames in PR; nothing to guard."
            exit 0
          fi

          # 3. For each rename, check if target matches any allowlist regex.
          violations=""
          while IFS=$'\t' read -r status source target; do
            for re in "${ALLOW_RES[@]}"; do
              if printf '%s' "${target}" | grep -qE "${re}"; then
                violations+="${source} -> ${target} (matches /${re}/)"$'\n'
                break
              fi
            done
          done <<<"${renames}"

          if [[ -z "${violations}" ]]; then
            echo "OK — no renames target allowlisted paths."
            exit 0
          fi

          # 4. Allow if PR has the override label.
          if printf '%s' "${PR_LABELS}" | jq -e 'index("secret-scan-allow-rename")' >/dev/null 2>&1; then
            echo "::notice::rename-guard suppressed by 'secret-scan-allow-rename' label."
            printf 'Renames into allowlisted paths (label-suppressed):\n%s' "${violations}"
            exit 0
          fi

          # 5. Allow if any commit in the range carries the trailer.
          #    Use --format=%(trailers) for trailer-aware extraction.
          trailers=$(git log --format='%(trailers:key=Rename-Allowed-By,valueonly)' "${BASE_SHA}..${HEAD_SHA}" | tr -d '\n\r')
          if [[ -n "${trailers}" ]]; then
            # Strip CR/LF before echoing into annotations (log-injection guard).
            safe="${trailers//[$'\n\r']/}"
            echo "::notice::rename-guard suppressed by Rename-Allowed-By trailer: ${safe}"
            printf 'Renames into allowlisted paths (trailer-suppressed):\n%s' "${violations}"
            exit 0
          fi

          # 6. Block.
          echo "::error::Rename(s) into gitleaks-allowlisted paths require either the 'secret-scan-allow-rename' label OR a 'Rename-Allowed-By: <name>' commit trailer." >&2
          printf '%s' "${violations}" >&2
          exit 1
```

4.2. Split the existing `smoke-tests` matrix `rename-laundering` case (kept as canary) and add a NEW `rename-guard-fires` case that exercises the new job's failure mode locally:

- Keep `rename-laundering` exactly as-is (verifies gitleaks itself behavior on bumps).
- Add `rename-guard-fires` (new matrix entry). The smoke step constructs a fixture rename, then runs the rename-guard's logic block (extracted into a sourceable script OR inlined verbatim). Expected: exit 1 unless override is present.

To keep the smoke test self-contained without re-running the full PR-diff workflow, the smoke case stages the rename in a local repo and invokes the same shell logic against `HEAD~1..HEAD`. Pseudocode:

```yaml
            rename-guard-fires)
              # Construct a baseline commit + a rename-into-allowlist commit.
              mkdir -p apps/web-platform/server/smoke
              echo "$FAKE_DOPPLER" > apps/web-platform/server/smoke/with-secret.ts
              git add apps/web-platform/server/smoke/with-secret.ts
              git commit -m "fixture: baseline" --no-verify
              mkdir -p apps/web-platform/test/__synthesized__
              git mv apps/web-platform/server/smoke/with-secret.ts \
                     apps/web-platform/test/__synthesized__/now-allowed.ts
              git commit -m "fixture: rename into allowlist" --no-verify
              # Run guard against HEAD~1..HEAD.
              BASE_SHA=$(git rev-parse HEAD~1) HEAD_SHA=$(git rev-parse HEAD) PR_LABELS='[]' \
                bash -c "$(awk '/^      - name: Inspect PR for renames/,/^  [a-z-]+:$/' .github/workflows/secret-scan.yml | sed -n 's/^[[:space:]]*//;p' | tail -n +2)" \
                && { echo "FAIL: rename-guard did NOT fire" >&2; exit 1; }
              echo "PASS: rename-guard fired on rename-into-allowlist"
              ;;
```

(The `awk | sed | bash -c` extraction is fragile across YAML-indent changes. **Cleaner alternative — adopt instead:** extract the rename-guard inspection logic into `apps/web-platform/scripts/rename-guard.sh` and have BOTH the workflow job AND the smoke test invoke it. This is the recommended path. The script reads `BASE_SHA`, `HEAD_SHA`, `PR_LABELS` (JSON) from env. Smoke test calls it with `PR_LABELS='[]'` → expect exit 1; with `PR_LABELS='["secret-scan-allow-rename"]'` → expect exit 0; commit with `Rename-Allowed-By: smoke-tests` trailer → expect exit 0.)

4.3. **Adopted approach:** create `apps/web-platform/scripts/rename-guard.sh`. Both the workflow job AND the smoke matrix call it. Smoke matrix gains 3 new cases:

- `rename-guard-fires` — renames into allowlist, no override → exit 1.
- `rename-guard-label-override` — renames into allowlist, `PR_LABELS='["secret-scan-allow-rename"]'` → exit 0.
- `rename-guard-trailer-override` — renames into allowlist, commit has `Rename-Allowed-By: smoke-tests` trailer → exit 0.

(The existing `rename-laundering` case stays as the gitleaks-bump canary.)

CODEOWNERS update (Phase 0.3 list): add `/apps/web-platform/scripts/rename-guard.sh @jeanderuelle`.

### Phase 5 — Allowlist-diff CI gate (#3323)

5.1. Add a new job `allowlist-diff` to `.github/workflows/secret-scan.yml`:

```yaml
  # ===========================================================================
  # 6. Allowlist-diff gate (#3323). Diffs `paths = [...]` arrays in
  #    .gitleaks.toml between PR base and head. Posts a comment listing
  #    additions; the PR author MUST add the 'secret-scan-allowlist-ack'
  #    label OR include a 'Allowlist-Widened-By: <name>' commit trailer.
  # ===========================================================================
  allowlist-diff:
    name: allowlist-diff (.gitleaks.toml paths surface)
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    if: github.event_name == 'pull_request'
    permissions:
      contents: read
      pull-requests: write
    steps:
      - name: Checkout
        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        with:
          fetch-depth: 0

      - name: Diff allowlist paths
        env:
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
          HEAD_SHA: ${{ github.event.pull_request.head.sha }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
          PR_LABELS: ${{ toJSON(github.event.pull_request.labels.*.name) }}
          GH_TOKEN: ${{ github.token }}
        run: |
          set -euo pipefail

          # Skip cheaply if .gitleaks.toml didn't change.
          if ! git diff --name-only "${BASE_SHA}..${HEAD_SHA}" | grep -qx '.gitleaks.toml'; then
            echo ".gitleaks.toml unchanged; skipping."
            exit 0
          fi

          # Extract allowlist arrays at base and head.
          git show "${BASE_SHA}:.gitleaks.toml" > /tmp/base.toml || echo "" > /tmp/base.toml
          git show "${HEAD_SHA}:.gitleaks.toml" > /tmp/head.toml
          node apps/web-platform/scripts/parse-gitleaks-allowlists.mjs /tmp/base.toml | jq -r '.[]' | sort -u > /tmp/base-paths.txt
          node apps/web-platform/scripts/parse-gitleaks-allowlists.mjs /tmp/head.toml | jq -r '.[]' | sort -u > /tmp/head-paths.txt

          added=$(comm -13 /tmp/base-paths.txt /tmp/head-paths.txt)
          removed=$(comm -23 /tmp/base-paths.txt /tmp/head-paths.txt)

          if [[ -z "${added}" && -z "${removed}" ]]; then
            echo "No allowlist path changes (regex re-orderings only)."
            exit 0
          fi

          # Build a comment body.
          body=$(printf '## Secret-scan allowlist diff\n\nThis PR modifies `.gitleaks.toml` allowlist paths.\n\n### Added paths\n```\n%s\n```\n\n### Removed paths\n```\n%s\n```\n\nAcknowledge via either:\n- Add the `secret-scan-allowlist-ack` label, OR\n- Include `Allowlist-Widened-By: <name>` in any commit trailer.\n' "${added:-(none)}" "${removed:-(none)}")

          # Post / update the comment (idempotent — keyed on a marker line in the body).
          marker="<!-- allowlist-diff-comment -->"
          full_body="${marker}"$'\n'"${body}"
          # Find existing comment with the marker; update if present, else create.
          existing=$(gh api "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
            --jq '.[] | select(.body | startswith("'"${marker}"'")) | .id' | head -n 1)
          if [[ -n "${existing}" ]]; then
            gh api "repos/${GITHUB_REPOSITORY}/issues/comments/${existing}" \
              --method PATCH --field body="${full_body}" >/dev/null
          else
            gh pr comment "${PR_NUMBER}" --body "${full_body}"
          fi

          # Block until acknowledged. Only ADDED paths require ack (removals
          # are net-tightening — let them through to avoid friction).
          if [[ -z "${added}" ]]; then
            echo "Only removals; no acknowledgement required."
            exit 0
          fi

          if printf '%s' "${PR_LABELS}" | jq -e 'index("secret-scan-allowlist-ack")' >/dev/null 2>&1; then
            echo "::notice::allowlist-diff acknowledged by label."
            exit 0
          fi
          if git log --format='%(trailers:key=Allowlist-Widened-By,valueonly)' "${BASE_SHA}..${HEAD_SHA}" | grep -q '\S'; then
            echo "::notice::allowlist-diff acknowledged by Allowlist-Widened-By trailer."
            exit 0
          fi

          echo "::error::Allowlist widening detected. Add label 'secret-scan-allowlist-ack' or include 'Allowlist-Widened-By: <name>' trailer." >&2
          exit 1
```

5.2. Smoke-test cases (added to the `smoke-tests` matrix):

- `allowlist-diff-fires` — stage a `.gitleaks.toml` edit that adds a new path under `[allowlist]`. Drive the job's logic via a local `BASE_SHA=HEAD~1 HEAD_SHA=HEAD` invocation (extract job logic into `apps/web-platform/scripts/allowlist-diff.sh`, mirror the rename-guard refactor). Expect exit 1 without ack. Cannot fully exercise the `gh pr comment` path in smoke (no PR context); skip the comment step under `[[ -z "${PR_NUMBER:-}" ]]` and exit 1 to prove the gate.

5.3. **Adopted refactor** (mirroring Phase 4): create `apps/web-platform/scripts/allowlist-diff.sh`. Workflow job calls the script. Smoke matrix tests the script directly. CODEOWNERS update: add `/apps/web-platform/scripts/allowlist-diff.sh @jeanderuelle`.

### Phase 6 — Runbook updates

Edit `knowledge-base/engineering/operations/secret-scanning.md`:

6.1. § Rename-laundering — empirical behavior (gitleaks v8.24.2):

- Replace the "Follow-up tracked: #3160" callout (line 114) with: "**Mitigation:** the `rename-guard` CI job (added 2026-05-15, this PR) fails on `git mv` into any allowlisted path unless the PR carries the `secret-scan-allow-rename` label OR a commit trailer `Rename-Allowed-By: <name>`. The smoke matrix `rename-laundering` case remains as a canary on gitleaks bumps."

6.2. Add a new section after § Rename-laundering: § Allowlist-diff gate (#3323):

> Any PR that modifies `paths = [...]` under `[allowlist]` or `[[rules.allowlists]]` in `.gitleaks.toml` triggers the `allowlist-diff` CI job. The job posts (or updates) a PR comment listing added/removed paths and blocks merge for additions until the PR author acknowledges via either the `secret-scan-allowlist-ack` label OR an `Allowlist-Widened-By: <name>` commit trailer. Removals are auto-allowed (net-tightening). The job uses `apps/web-platform/scripts/parse-gitleaks-allowlists.mjs` to extract the regex literals from each `paths` array; review that helper if behavior looks wrong.

6.3. § `# gitleaks:allow` waivers — add a sentence: "As of 2026-05-15 (#3322), the lefthook + CI `lint-fixture-content` linter also covers `knowledge-base/project/learnings/**/*.md` so future learning-file waivers carry the `issue:#NNN <reason>` trailer."

6.4. Update `last_updated:` frontmatter to 2026-05-15.

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json`, then `jq` per planned file. Files queried: `.github/workflows/secret-scan.yml`, `.gitleaks.toml`, `apps/web-platform/scripts/lint-fixture-content.mjs`, `plugins/soleur/skills/incident/test/fixtures/positive-corpus.md`, `knowledge-base/engineering/operations/secret-scanning.md`.

Result: **Folded in** — #3759 (bug, not code-review), #3322 + #3323 + #3160 (the four `code-review` / `deferred-scope-out` issues this PR closes). No additional open `code-review` issues touch these files. No additional folds; no acknowledgements; no deferrals.

## Risks

- **R1 — gitleaks v8.24.2 behavior on bumps.** Both the rename-guard logic and the path-extractor depend on `.gitleaks.toml`'s v8.24.2 syntax. If gitleaks bumps to v8.25+ and we adopt the top-level `[[allowlists]] targetRules = [...]` form, the parser MUST be extended. Mitigation: parser explicitly logs a warning if it encounters any `[[allowlists]]` block (v8.25+ shape) without `targetRules` handling. Add to `parse-gitleaks-allowlists.mjs` Phase 1 spec.
- **R2 — Allowlist-diff false positives on TOML re-formatting.** If a reviewer reformats `.gitleaks.toml` (e.g., re-orders `paths` entries), the diff is empty (sets are equal), no comment posted. Confirmed by `comm -13 sort | sort` semantics. ✓
- **R3 — Rename-guard false positive on benign refactors.** A legitimate move of a test file from one `__synthesized__/` to another would trip the guard if the target path matches the regex AND the source doesn't (or vice versa). Source check is moot — guard fires on any rename TARGET in allowlist regardless of source. Acceptable trade-off; documented in runbook + override path is one-line.
- **R4 — `gh pr comment` rate limit.** Idempotent comment-update via the marker line means at most one comment per PR. Re-runs `PATCH` the existing comment. ✓
- **R5 — Per Sharp Edge `2026-05-15-github-push-protection-rejects-synthetic-tokens-in-plan-prose`:** This plan uses the literal Doppler-shape token `dp.pt.‹SMOKETEST-40-alnum-body›` only in the existing `secret-scan.yml` smoke matrix (already gated through `FAKE_DOPPLER_PREFIX`/`FAKE_DOPPLER_BODY` split). Plan prose uses non-alnum placeholders so GitHub push protection's regex (`dp\.(pt|st|sa|ct)\.[A-Za-z0-9_-]{40,}`) does not match. ✓
- **R6 — Sharp Edge `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug`**: any `bash -c '<snippet>'` verification commands in this plan extract from YAML; per the sharp edge, verify embedded shell with `bash -c '<snippet>'` not `bash -n <file.yml>`. Phase 1 RED/GREEN harness uses `bash -n script.sh` (script files, not YAML) ✓.

## Sharp Edges

- The plan's `## User-Brand Impact` section declares `threshold: none, reason: <one-sentence non-empty reason>`. Without it, preflight Check 6 will FAIL at ship time.
- `apps/web-platform/scripts/parse-gitleaks-allowlists.mjs` is regex-based and intentionally avoids a TOML-parser dep. If the file gains nested arrays or multi-line strings in the future, replace with `bun add -d toml` + structural parse. Document the trade-off at top of file.
- The rename-guard and allowlist-diff jobs use `git log --format='%(trailers:key=X,valueonly)' BASE..HEAD` for trailer extraction. This requires `git` ≥ 2.13 (ubuntu-24.04 ships ≥ 2.34). Verified.
- Per `2026-05-15-plan-ac-verification-commands-awk-self-match-and-marker-conjunction`: AC verification commands use exit-code signals (jq `-e`, grep `-c`, file existence) — no implementation-variant string literals as load-bearing AND clauses.
- Per `2026-04-22-plan-ac-external-state-must-be-api-verified`: AC11 (label existence) and AC18 (branch protection) are external-state claims — verified via `gh label list` (Phase 0) and `gh api` (Phase 0/post-merge), NOT via codebase grep alone.
- Per `2026-05-12-plan-time-api-contract-verification-and-pipeline-via-package-json`: the `gh api repos/.../issues/{N}/comments` and `repos/.../issues/comments/{id}` endpoints used in Phase 5 are GitHub REST v3 issue-comment endpoints (PRs are issues for comment purposes); contract verified via `gh api -X GET /repos/{owner}/{repo}/issues/{number}/comments --include` (returns 200 + array of comment objects with `.id` and `.body` fields).
- Per `2026-05-10-plan-phase-order-load-bearing-when-contract-changes`: Phase 1 (parser) MUST land before Phase 4 (rename-guard) and Phase 5 (allowlist-diff) — both consume the parser. Phase 0 labels MUST land before AC7/AC8 verification. Phase 2 fixture synthesis is independent of all other phases. Phase 6 runbook lands last (documents the new gates). Documented; `/work` will execute in this order.
- Per `cq-test-fixtures-synthesized-only`: the Phase 2 JWT replacement uses placeholder words (`synthesized_HEADER_placeholder`, etc.) so the fixture's intent is unmistakable. The shape still triggers the redact-sentinel JWT regex (Test 2 stays green) but cannot be mistaken for a real JWT shape on visual review.

## Test Plan

- **Phase 1**: `bash apps/web-platform/test/__synthesized__/parse-gitleaks-allowlists.test.sh` — 7 tests (T1-T7).
- **Phase 2**: `bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh` — all 4 existing tests including Test 2.JWT.
- **Phase 3**: manual RED/GREEN with a throwaway `_red-test.md` learning file containing a malformed waiver; verify lefthook + CI grep both fire then no longer fire after a valid trailer.
- **Phase 4**: smoke matrix cases `rename-laundering` (canary, kept) + `rename-guard-fires` + `rename-guard-label-override` + `rename-guard-trailer-override` (new).
- **Phase 5**: smoke matrix case `allowlist-diff-fires` (new). Manual draft-PR canary verifies the comment is posted with the marker line and the gate blocks until the label/trailer is added.
- **End-to-end**: push the PR; verify all jobs run green except deliberately-failing fixtures in matrix smoke cases (which are expected exit-1 inside an exit-0 wrapper).

## PR Body Template

```
Bundled secret-scan hardening sweep — closes 4 deferred-scope-out / code-review issues touching the same surface.

## Changes

- #3759: synthesize JWT fixture in incident skill positive-corpus.md
- #3322: extend lint-fixture-content glob to knowledge-base/project/learnings
- #3323: new `allowlist-diff` CI job + label `secret-scan-allowlist-ack` + trailer `Allowlist-Widened-By:`
- #3160: new `rename-guard` CI job + label `secret-scan-allow-rename` + trailer `Rename-Allowed-By:`

## New helper scripts

- `apps/web-platform/scripts/parse-gitleaks-allowlists.mjs` — extracts allowlist regexes (used by both new jobs)
- `apps/web-platform/scripts/rename-guard.sh` — rename-into-allowlist guard logic
- `apps/web-platform/scripts/allowlist-diff.sh` — allowlist-diff gate logic
- `apps/web-platform/test/__synthesized__/parse-gitleaks-allowlists.test.sh` — RED/GREEN harness

## Closes

Closes #3759
Closes #3322
Closes #3323
Closes #3160

## Changelog

PATCH — CI tooling hardening (no user-facing surface; no schema; no runtime path).
```

(Use `Closes #N` on its own body lines per `wg-use-closes-n-in-pr-body-not-title-to`.)
