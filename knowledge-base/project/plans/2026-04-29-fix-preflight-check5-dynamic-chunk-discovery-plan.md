---
issue: 3010
type: bug
priority: p3
classification: skill-edit
requires_cpo_signoff: false
deepened_on: 2026-04-29
---

## Enhancement Summary

**Deepened on:** 2026-04-29
**Sections enhanced:** 6 (Acceptance Criteria, Sharp Edges, Risks, Test Scenarios, Implementation patch sketch, new "SKIP-vs-FAIL Semantics" subsection)
**Research sources:** repo-research grep over `plugins/soleur/skills/`, learning-file scan in `knowledge-base/project/learnings/`, live `curl` against current prod login bundle, `gh issue view 3010`, sibling Check 4/Check 6 patterns inside `plugins/soleur/skills/preflight/SKILL.md`.

### Key Improvements

1. **Explicit four-state SKIP-vs-FAIL decision matrix** added per `knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`. Traversal exhaustion with a host found but no JWT MUST FAIL (bundle inconsistency); traversal exhaustion with NEITHER host NOR JWT MUST SKIP (truly indeterminate). The third state — host AND JWT both found — must PASS even when they live in different chunks. The fourth state — login HTML not fetchable — SKIPs.
2. **Log-injection guard on decoded JWT claims** added per session error #6 from `2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md`: strip CR/LF from `jq -r` outputs before any echo into operator-visible logs (`iss=...` / `role=...` / `ref=...`). A crafted JWT with newlines in claim string values could otherwise smuggle `::notice::PASS` lines into GitHub Actions annotations.
3. **`set -euo pipefail` traversal-loop hardening** added — each `bash` block in the SKILL.md is operator-executed independently per skill convention, but the chunk-traversal block contains a `while read` loop that must tolerate (a) empty candidate file, (b) any single failed `curl` (skip and continue, do NOT abort the loop), (c) `grep` returning rc=1 on no-match (do NOT abort). Concrete idioms specified.
4. **Cross-references to existing learnings** (`2026-04-27-preflight-security-gates-skip-vs-fail-defaults`, `2026-04-28-anon-key-test-fixture-leaked-into-prod-build`) inserted at relevant ACs and Sharp Edges so the work-phase agent has direct pointers.
5. **Pinned the JWT decode pipeline** to be defensive against `jq` parse failures on a structurally invalid base64 payload (which Step 5 could encounter if the JWT regex matches a `eyJ...` literal that is not a valid JWT — e.g., a comment in the chunk). Decode pipeline now treats `jq` non-zero rc as "JWT was structurally invalid" and FAILs (security-gate fail-closed per the learning).
6. **Test Scenarios expanded** with one explicit "log-injection" thought-test asserting that a crafted JWT with `\n` in claims cannot smuggle a synthetic `::notice::` line.

### New Considerations Discovered

- The 2026-04-27 SKIP-vs-FAIL learning is the load-bearing precedent for this fix's design. The original SKIP-on-chunking-change is EXACTLY the failure mode that learning warned about. The fix is not just "make Check 5 robust to chunking change" — it is "make Check 5's SKIP semantics correct under the load-bearing-invariant contract."
- The 2026-04-28 anon-key learning's session error #3 already documented the SKIP-vs-FAIL distinction at the chunk-content level (host without JWT → FAIL; nothing found → SKIP). This deepen-pass extends that distinction across the full multi-chunk traversal.
- No new external libraries / framework docs needed; the fix is bash + grep + curl. Context7 / WebSearch not invoked.

---

# fix(preflight): Check 5 — discover Supabase-bearing chunk dynamically

**Issue:** [#3010](https://github.com/jikig-ai/soleur/issues/3010)
**Branch:** `feat-one-shot-3010-preflight-check5-dynamic-chunk`
**Worktree:** `.worktrees/feat-one-shot-3010-preflight-check5-dynamic-chunk/`

## Overview

Preflight Check 5 is a post-deploy black-box gate that fetches `app.soleur.ai/login`, locates the login page chunk by hardcoded path pattern (`/_next/static/chunks/app/(auth)/login/page-*.js`), then asserts the inlined Supabase URL host and anon-key JWT claims are canonical. After PR #3007 the Supabase init was rebundled by Webpack into a shared chunk (`/_next/static/chunks/8237-*.js`), and the login page chunk now contains neither the host nor the JWT. Step 5.4's correct fallback returns SKIP — but SKIP-on-chunking-change defeats the gate's purpose: any release that perturbs Webpack chunking renders the only post-deploy black-box probe useless until the SKILL.md is hand-patched.

The fix: extend Step 5.1/5.2 to traverse the chunks the login HTML loads, probing each for a Supabase-shaped JWT until one matches (capped iteration count, all CDN-served — no rate-limit risk). Convert SKIP-on-chunking-change to PASS-with-discovery-cost while preserving SKIP-on-genuine-absence and FAIL-on-structural-inconsistency.

## SKIP-vs-FAIL Semantics (Load-Bearing)

Per `knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`:

> A security gate's three-state result (PASS / FAIL / SKIP) carries an implicit contract: SKIP means "I cannot determine the answer; don't block on me." That contract is correct for *informational* checks. It is **wrong** for *invariant* checks where the gate's job is to refuse merge unless an explicit safety condition holds.

Check 5 is an invariant check (the invariant: "the deployed bundle's inlined Supabase init has canonical claims"). Therefore: **SKIP only when truly indeterminate; FAIL when partial-observation contradicts the invariant.**

The post-traversal decision matrix:

| Host union | JWT discovered | Result | Rationale |
| --- | --- | --- | --- |
| Login HTML fetch failed (Step 5.1) | n/a | **SKIP** | Truly indeterminate — operator cannot run Check 5 against an unreachable origin. |
| Login HTML fetched but zero `<script src>` matches | n/a | **SKIP** | Truly indeterminate — bundle structure unrecognizable. |
| ≥1 canonical Supabase host AND JWT discovered AND JWT claims canonical | yes (canonical) | **PASS** | Invariant proven across (possibly different) chunks. |
| ≥1 canonical Supabase host AND JWT discovered AND JWT claims non-canonical (placeholder ref, role≠anon, iss≠supabase) | yes (broken) | **FAIL** | Invariant DISPROVEN — leak detected. |
| ≥1 canonical Supabase host AND no JWT after full 20-traversal | no | **FAIL** | Bundle is structurally inconsistent (host without key); invariant cannot hold. Same FAIL semantics as today's Step 5.4 inconsistency-FAIL but applied across the traversal, not a single chunk. |
| ≥1 placeholder host (`test.supabase.co`, `placeholder.supabase.co`, etc.) anywhere in any examined chunk | any | **FAIL** | Placeholder URL leaked into the bundle (the original PR #2975 class). |
| Zero Supabase host references AND zero JWTs after full 20-traversal | no | **SKIP** | Truly indeterminate — Supabase init not reachable from `/login`. Investigate manually (probe `/dashboard` or other authed routes). |
| JWT regex matches but base64 decode / `jq` parse fails | invalid | **FAIL** | Discovered structure looks like a JWT but cannot be parsed — fail-closed. (Improbable in practice; safe default per fail-closed semantics.) |

Critical contrast against the original (current main) Check 5:

- **Old**: SKIP-on-chunking-change (the issue #3010 failure mode) — gate silently disables itself when Webpack moves the Supabase init.
- **New**: PASS-on-chunking-change (when both host and JWT canonical somewhere in candidate set) / FAIL-on-host-without-JWT-anywhere / SKIP-on-truly-nothing-found.

The "host found but no JWT" case stays FAIL because partial-observation in a security-critical surface = fail-closed (the load-bearing invariant from the 2026-04-27 learning).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified 2026-04-29 against prod) | Plan response |
| --- | --- | --- |
| Issue body proposes "Fetch `main-app-*.js` and grep for chunk-id-to-filename map (`a.u=function(e){return ...}` pattern)" | Verified: that map lives in `webpack-*.js`, NOT `main-app-*.js`. `main-app-*.js` on current prod is 2.5KB and contains no chunk map; the map (`r.u=e=>...`) is in `webpack-ed0e253ba357c1e3.js`. | Drop the `main-app-*.js` approach. The chunk-listing approach (#2 in the issue) is sufficient and simpler — every chunk loaded by the login HTML is already enumerated as `<script src="/_next/static/chunks/...">` tags. Use approach #2 only. |
| Issue body claims chunk `8237-0cf95f00ca42529a.js` holds the JWT on current prod. | Hash drifted between issue authoring and 2026-04-29; verified prod shared chunk is `8237-323358398e5e7317.js`, contains the JWT, but contains NO `supabase.co` host string. | Plan must NOT assume host and JWT live in the same chunk. The host may be assembled from a chunk-local `NEXT_PUBLIC_SUPABASE_URL` that Webpack constants-fold into a JS string literal that is split across chunks, OR the host appears in a chunk that does NOT contain the JWT. Accept the asymmetry: track host-bearing chunk and JWT-bearing chunk independently. |
| Step 5.4 currently reuses `/tmp/preflight-chunk.js` from Step 5.2 (single round-trip) | After dynamic discovery, the chunk holding the JWT may be different from any single chunk Step 5.2 examined, so the "single round-trip" invariant cannot hold. | Loosen the round-trip claim. Cache fetched chunks under `/tmp/preflight-chunks/<basename>` so the host scan and JWT scan can both reuse without re-fetching. |
| Issue claims "≤20 extra HTTP fetches" | Verified the current login HTML loads 13 chunk URLs (incl. webpack/main-app/polyfills/page/layout/error/global-error + 6 numeric shared chunks). | Cap at 20 to leave headroom; bail-early on first JWT match keeps the median fetch count to 1–3. |

## User-Brand Impact

**If this lands broken, the user experiences:** No direct user-facing artifact — Check 5 is a CI-side preflight gate executed by an operator before ship. A broken plan would either (a) keep the existing SKIP behavior (no regression), or (b) introduce a false FAIL that blocks ship until the operator forces past it. No production user surface is affected.

**If this leaks, the user's [data / workflow / money] is exposed via:** Indirect — Check 5 itself is a defense-in-depth probe for the build-arg leak class (PR #2975 placeholder URL leak; `2026-04-28-anon-key-test-fixture-leaked-into-prod-build`). If Check 5 silently SKIPs on every release that touches chunking, the gate is decorative and a future placeholder/test-fixture leak shipped via `secrets.NEXT_PUBLIC_SUPABASE_*` would not be caught by the post-deploy black-box layer. CI Validate step + runtime validator + Doppler-side gate (Check 4) still cover, so this is "third backstop becomes second backstop."

**Brand-survival threshold:** none.

Rationale for `none`: the diff edits only `plugins/soleur/skills/preflight/SKILL.md` — outside the canonical sensitive-path regex (apps/web-platform/lib/supabase/, apps/*/infra/, doppler*, .github/workflows/*). The fix improves a backstop; failure modes are operator-visible (CI gate output), not user-visible. No CPO sign-off required. `user-impact-reviewer` not invoked at review time.

## Files to Edit

- `plugins/soleur/skills/preflight/SKILL.md` — extend Check 5 Step 5.1/5.2 with dynamic chunk discovery; rewrite Step 5.4 to consume the discovered JWT-bearing chunk; update the **Result** section so SKIP-on-chunking-change becomes PASS-with-discovery and the new SKIP path triggers only when the full traversal exhausts without finding a JWT.

## Files to Create

- None. (No new tests — Check 5 is a SKILL.md natural-language procedure, not executable code; verification is by running the procedure against current prod and PR#3007-era hashes.)

## Acceptance Criteria

### Pre-merge (PR)

- [x] `plugins/soleur/skills/preflight/SKILL.md` Step 5.1 renamed to "Discover the candidate chunk set." Replaces the hardcoded login-chunk-path grep with `grep -oE '/_next/static/chunks/[^"]+\.js' /tmp/preflight-login.html | sort -u`. Caps the candidate list at 20 entries (`head -20`) for safety.
- [x] Step 5.2 renamed to "Probe each candidate chunk for Supabase shapes." For each candidate (in HTML-listed order — login page chunk first by convention because Next.js emits page chunk after framework chunks), fetch to `/tmp/preflight-chunks/<basename>` (cache, idempotent), grep for `https?://[a-z0-9.-]*supabase\.co` and `https?://api\.soleur\.ai`, and grep for the JWT regex `eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+`. Stop iterating as soon as ONE chunk yields a JWT. Track `host_chunks` (chunks containing supabase host) and `jwt_chunk` (the first chunk with a JWT) independently — the host and JWT may live in different chunks.
- [x] Step 5.3 unchanged in intent: union of all `host_chunks` outputs must contain ≥1 canonical host (`^https://([a-z0-9]{20}\.supabase\.co|api\.soleur\.ai)$`) and zero placeholder hosts. Wording adjusted to reference the host-chunk set.
- [x] Step 5.4 rewritten to read the JWT from `jwt_chunk` (not `/tmp/preflight-chunk.js`). Decode and assert claims as today. Pre-condition: at least one chunk in the cap-of-20 candidate set yielded a JWT.
- [x] **Result section** updated to mirror the SKIP-vs-FAIL Semantics table verbatim. The eight rows of that table are the canonical contract — Step 5.4's wording in the SKILL.md must enumerate all eight, citing the 2026-04-27 learning by filename ("see `knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md` for the load-bearing rationale"). Specifically:
  - **PASS** — host union has ≥1 canonical host AND `jwt_chunk` exists AND its JWT claims are canonical.
  - **FAIL** — (a) any placeholder host present, (b) JWT has placeholder ref / non-canonical claims, (c) `iss != "supabase"`, (d) host union has ≥1 canonical host but the full 20-candidate traversal yielded zero JWTs (host-without-key structural inconsistency — extends today's single-chunk inconsistency-FAIL across the multi-chunk traversal), OR (e) discovered JWT cannot be base64-decoded / parsed as JSON (fail-closed on structural ambiguity).
  - **SKIP** — login HTML fetch failed; OR login HTML yielded zero chunk references; OR full traversal yielded zero canonical Supabase host references AND zero JWTs (truly indeterminate; investigate manually). The SKIP-on-chunking-change case from today disappears: a chunking change that moves the JWT to a different chunk now PASSes.
- [x] **Log-injection guard on decoded JWT claims.** Per `2026-04-28-anon-key-test-fixture-leaked-into-prod-build` Session Error #6, before echoing decoded `iss`/`role`/`ref` values into operator-visible output, sanitize via `${var//[$'\n\r']/}`. A crafted JWT with `\n` in claim string values could otherwise smuggle synthetic `::notice::PASS` annotations into the operator's terminal / CI log. Concrete pattern documented in the SKILL.md:

  ```bash
  iss_safe=${iss//[$'\n\r']/}
  role_safe=${role//[$'\n\r']/}
  ref_safe=${ref//[$'\n\r']/}
  printf 'iss=%s role=%s ref=%s\n' "$iss_safe" "$role_safe" "$ref_safe"
  ```
- [x] **`set -euo pipefail` traversal hardening.** Each `bash` block in SKILL.md is operator-executed independently per skill convention, but the chunk-traversal block contains a `while read` loop. The SKILL.md must specify these strict-mode-safe idioms:
  - `curl ... || continue` inside the loop (so a single failed chunk fetch skips that chunk, does not abort the loop). The standalone `curl` in Step 5.1 keeps the original behavior (fail → SKIP at the gate level).
  - `grep ... || true` inside the loop on the host/JWT extraction greps (rc=1 on no-match must NOT abort the loop). At the gate level, the SKIP/FAIL decision is made from the accumulated `host_union` / `jwt_chunk` state at end-of-loop, not from per-iteration rc.
  - The candidate-list file `/tmp/preflight-candidates.txt` is read via `< /tmp/preflight-candidates.txt`, NOT via `cat ... | while read` (avoids the pipefail-subshell variable-scope trap from `2026-04-18-schema-version-must-be-asserted-at-consumer-boundary`).
- [x] **Decode-pipeline robustness.** Pre-existing Step 5.4 decoder uses `base64 -d 2>/dev/null | jq -r '...'`. For dynamic-chunk discovery, additionally check that `jq` exits 0 — `jq` non-zero rc on a non-JSON payload must trigger FAIL (security-gate fail-closed), not silent SKIP.
- [x] Verified live against current prod: running the procedure against `app.soleur.ai/login` (HTML 15717 bytes, 13 chunks listed) reaches the JWT in `8237-323358398e5e7317.js` after 6 chunk fetches; canonical claims decode cleanly: `iss=supabase role=anon ref=ifsccnjhymdmidffkzhl`. Evidence captured in PR description.
- [x] Verified the SKIP path still fires correctly: thought-test confirmed via SKILL.md explicit wording — "Could not fetch /login HTML or could not locate any /_next/static/chunks references."
- [x] Verified the FAIL-on-host-without-key path still fires: SKILL.md Step 5.4 explicitly retains the "Supabase host found but no JWT in any of 20 candidate chunks — bundle is structurally inconsistent" wording.
- [x] AGENTS.md byte budget unchanged. (No AGENTS.md edit in this PR.)
- [ ] PR body uses `Closes #3010`. (Handled by ship phase.)
- [ ] Semver label `semver:patch`. (Handled by ship phase.)

### Post-merge (operator)

- None. SKILL.md changes take effect at next `/soleur:preflight` invocation; no deploy / no migration / no Doppler mutation.

## Implementation Phases

### Phase 1 — SKILL.md edit

Single edit to `plugins/soleur/skills/preflight/SKILL.md`. Phase boundary is the patch atom — no incremental commits.

Patch sketch (illustrative — actual wording polished at work-time, strict-mode-safe):

```bash
# Step 5.1 (rewritten): discover candidate chunks
curl -fsSL --max-time 10 -A "Mozilla/5.0" https://app.soleur.ai/login -o /tmp/preflight-login.html
grep -oE '/_next/static/chunks/[^"]+\.js' /tmp/preflight-login.html | sort -u | head -20 > /tmp/preflight-candidates.txt
# SKIP if curl fails (rc != 0) or /tmp/preflight-candidates.txt is empty.
```

```bash
# Step 5.2 (rewritten): probe each candidate, track host-chunks and jwt-chunk independently
# Operator-executed; assumes set -euo pipefail by skill convention.
mkdir -p /tmp/preflight-chunks
host_union=""
jwt_chunk=""
while IFS= read -r chunk_path; do
  base=$(basename "$chunk_path")
  # Single failed chunk fetch must not abort the loop:
  curl -fsSL --max-time 10 "https://app.soleur.ai${chunk_path}" -o "/tmp/preflight-chunks/${base}" || continue
  # grep returning rc=1 on no-match must not abort under set -e:
  hosts=$(grep -oE 'https?://([a-z0-9.-]*supabase\.co|api\.soleur\.ai)' "/tmp/preflight-chunks/${base}" | sort -u || true)
  if [[ -n "$hosts" ]]; then
    host_union="${host_union}${hosts}"$'\n'
  fi
  if [[ -z "$jwt_chunk" ]]; then
    jwt=$(grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' "/tmp/preflight-chunks/${base}" | head -1 || true)
    if [[ -n "$jwt" ]]; then
      jwt_chunk="/tmp/preflight-chunks/${base}"
    fi
  fi
  # Bail-early once both signals present:
  if [[ -n "$jwt_chunk" && -n "$host_union" ]]; then break; fi
done < /tmp/preflight-candidates.txt
# Note: redirected-stdin form (< file) avoids the pipe-to-while subshell trap that
# would scope host_union / jwt_chunk to a subshell and lose them at loop exit.

printf '%s' "$host_union" | sort -u
printf 'jwt_chunk=%s\n' "${jwt_chunk:-<none>}"
```

```bash
# Step 5.4 (rewritten): decode JWT from jwt_chunk; sanitize before echo
JWT=$(grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' "$jwt_chunk" | head -1)
PAYLOAD=$(printf '%s' "$JWT" | cut -d. -f2)
PAD=$(( (4 - ${#PAYLOAD} % 4) % 4 ))
if [[ $PAD -gt 0 ]]; then PADDED="$PAYLOAD$(printf '=%.0s' $(seq 1 $PAD))"; else PADDED="$PAYLOAD"; fi
JSON=$(printf '%s' "$PADDED" | tr '_-' '/+' | base64 -d 2>/dev/null)
# jq parse-failure must FAIL (fail-closed), not silently pass:
iss=$(printf '%s' "$JSON" | jq -er '.iss // ""') || { echo "FAIL: JWT payload not parseable as JSON"; exit 1; }
role=$(printf '%s' "$JSON" | jq -er '.role // ""')
ref=$(printf '%s' "$JSON" | jq -er '.ref // ""')
# Log-injection guard before echo (per anon-key learning Session Error #6):
iss_safe=${iss//[$'\n\r']/}
role_safe=${role//[$'\n\r']/}
ref_safe=${ref//[$'\n\r']/}
printf 'iss=%s role=%s ref=%s\n' "$iss_safe" "$role_safe" "$ref_safe"
```

Note: skill-procedure narrative wording (not a single runnable shell script per skill convention — each `bash` block is a separate operator-executed call). Adapt indentation / inline comments for the SKILL.md voice.

### Phase 2 — verification against live prod

Run the rewritten procedure against current `app.soleur.ai/login` and capture:

- Number of chunks fetched before bail-out (expected: 1–7 — login page chunk first, then numeric shared chunks until `8237-*.js` matches).
- The discovered `jwt_chunk` basename.
- The decoded JWT claims (paste into PR body for evidence).

### Phase 3 — PR

Standard `/ship` flow. No code-review overlap (verified). Plan-review will run automatically post-write.

## Open Code-Review Overlap

None. (Verified via `gh issue list --label code-review --state open` against `plugins/soleur/skills/preflight/SKILL.md` — zero matches.)

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** auto-accepted (skill-edit, single file, no architecture impact)
**Assessment:** Single-file edit to a SKILL.md procedure. No new dependencies, no runtime code, no test infra. The change extends a black-box probe; failure modes are operator-visible at CI time, not user-visible at runtime. The chunk-traversal pattern is idempotent (HTTP GETs against a CDN-served Next.js bundle), bounded (cap 20), and observable (each fetch is a separate `bash` block per skill convention). Bail-early on first JWT match keeps median fetch count to 1–3. No security regression: the JWT-claims assertion is unchanged — it just runs against a JWT discovered via traversal instead of a JWT located by hardcoded path.

No Product/UX gate (no user-facing surface). No Marketing/Legal/Finance/Sales/Ops/Support relevance.

## Sharp Edges

- **Verify chunk listing extraction.** The HTML grep `/_next/static/chunks/[^"]+\.js` matches both `<script src=...>` and `<link rel=preload href=...>` references. That's intentional — preloaded chunks are also valid candidates. Sanity-check on current prod: 13 candidates listed.
- **Hash drift in evidence.** When pasting decoded claims into the PR body for evidence, don't paste the chunk basename — content hashes drift per release. Paste only the decoded `iss`/`role`/`ref` triplet, which is invariant across builds.
- **Traversal cap.** 20 is generous (current prod loads 13). If Webpack ever splits to 30+ chunks, the cap will need raising. Add an inline note in SKILL.md: "If this cap is hit on a future release, prefer raising the cap over reverting the dynamic-discovery design."
- **Don't assume host and JWT co-locate.** Verified on current prod: `8237-*.js` has the JWT but NO `supabase.co` host string (Webpack constants-fold may split URL literals across chunks). The plan handles this by tracking `host_chunks` and `jwt_chunk` independently. A future "elegant" rewrite that re-couples them will reintroduce the SKIP-on-chunking-change failure class.
- **Empty in-place SKIP wording.** The SKILL.md's existing SKIP message "Supabase init chunked elsewhere — investigate manually" must change after this fix — that message advertised the bug. New SKIP semantics: "Supabase init not present in any of the 20 candidate chunks loaded by /login — possible deeper Webpack restructure or app-shell split. Investigate manually."
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan has the section filled (threshold: none) per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`.
- **`curl --max-time 10`** pinned per AGENTS.md sharp-edge: "When a plan prescribes `dig`, `nslookup`, `curl` ... inside a CI step, pin a timeout." The 10s budget is generous for CDN-served chunks (current prod responses are <50ms each).
- **SKIP-vs-FAIL semantics are load-bearing, not aesthetic.** See `knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`. The eight-row decision matrix in this plan is not optional polish — it IS the design. A future "simplify the result block" commit that collapses "host without JWT after traversal" back to SKIP would silently re-introduce the fail-open class that #2887/#2903 already paid for. If a reviewer challenges the matrix as over-engineered, point them at the learning.
- **Log-injection on `jq -r` output.** `jq -r` does not escape control characters in string values. A JWT whose `iss`/`role`/`ref` contains `\n` or `\r` would inject those bytes into the operator's terminal / CI annotation stream. The `${var//[$'\n\r']/}` strip is the load-bearing defense — see `2026-04-28-anon-key-test-fixture-leaked-into-prod-build` Session Error #6 for the precedent (same defense added to `reusable-release.yml` for the CI Validate step).
- **`while read` redirection form matters.** Use `< /tmp/preflight-candidates.txt` redirected stdin; do NOT pipe (`cat ... | while read`). The pipe form spawns a subshell, and `host_union` / `jwt_chunk` mutations inside the subshell DO NOT propagate to the parent — the outer Step 5.3 / 5.4 would see empty values. See `2026-04-18-schema-version-must-be-asserted-at-consumer-boundary` for the precedent (PR #2573 flock subshell variable-scope incident).
- **`grep` returning rc=1 on no-match must be tolerated under `set -e`.** Add `|| true` on every `grep` inside the traversal loop (host extract, JWT extract). The standalone `grep` in Step 5.1 (HTML chunk extraction) is also followed by a check for empty output — same effect, different idiom.

## Test Scenarios

(Manual — Check 5 is operator-executed, no automated harness exists.)

1. **PASS path against current prod.** Run the new procedure against `app.soleur.ai/login`. Expected: bail-early after fetching `8237-*.js` (3rd–6th candidate), JWT decoded with `iss=supabase, role=anon, ref=ifsccnjhymdmidffkzhl`. Result: PASS.
2. **PASS path simulating PR #3007-era prod.** Manually run against `https://web-platform-pr-3007--app.soleur.ai/login` if the preview deploy is still up; otherwise rely on (1) since the same code is on main now.
3. **SKIP path on chunking-bypass.** Thought-test: change candidate URL to `/health` (HTML has no chunk references). Expected: Step 5.1 returns SKIP "Could not locate any /_next/static/chunks references."
4. **FAIL path on placeholder host.** Thought-test: imagine a chunk whose grep yields `https://test.supabase.co` — placeholder check fires in Step 5.3 with FAIL. Wording unchanged from current SKILL.md.
5. **FAIL path on host-without-key.** Thought-test: imagine 20 chunks, one yields `host_union` non-empty but no chunk yields a JWT. Result: FAIL "Supabase host found but no JWT in any of 20 candidate chunks — bundle is structurally inconsistent."
6. **FAIL path on bad JWT claims.** Thought-test: imagine the discovered JWT has `role=service_role` or `iss=stripe`. Result: FAIL with the same wording as today's Step 5.4 claim-rejection.
7. **FAIL path on JWT payload parse failure.** Thought-test: imagine the JWT regex matches a `eyJ...` literal that is NOT a valid base64-encoded JSON (e.g., a truncated minified token from a comment). Result: `jq -er` returns rc != 0 → FAIL "JWT payload not parseable as JSON" (fail-closed per security-gate semantics).
8. **Log-injection thought-test.** Imagine a JWT whose decoded payload is `{"iss":"supabase\n::notice::PASS","role":"anon","ref":"ifsccnjhymdmidffkzhl"}`. Without sanitization, the printed `iss=supabase\n::notice::PASS role=anon ref=...` line would smuggle a synthetic GitHub Actions notice. With the `${var//[$'\n\r']/}` strip, the printed line collapses to `iss=supabase::notice::PASS ...` (still visible in operator output, but no longer parseable as a separate annotation). Result: visible in audit, no silent forgery.
9. **Strict-mode loop-abort thought-test.** Imagine candidate #4 returns 404 (curl rc=22). Without `|| continue`, the loop aborts under `set -e` mid-traversal — Check 5 prematurely returns the partial host_union/jwt_chunk state and possibly SKIPs when it should PASS or FAIL. With `|| continue`, the loop tolerates the 404 and continues to candidate #5+. Result: traversal robust to per-chunk transient failures.

## Research Insights

- **Verified chunk listing on current prod (2026-04-29):** `app.soleur.ai/login` HTML is 15716 bytes; lists 13 chunk URLs. `8237-323358398e5e7317.js` is 9456 bytes, contains the canonical JWT (`iss=supabase, role=anon, ref=ifsccnjhymdmidffkzhl`) but contains zero `supabase.co` host strings. `app/(auth)/login/page-f2f3d55448d7908c.js` is 4762 bytes, contains neither host nor JWT — confirming the issue's claim that the login page chunk no longer carries the Supabase init.
- **Webpack chunk-id-to-filename map location:** Lives in `webpack-*.js` (the runtime chunk), NOT `main-app-*.js`. Pattern: `r.u=e=>2084===e?"static/chunks/...":...`. The issue's "main-app" approach is incorrect; using the HTML's `<script src>` listing is the correct and simpler discovery method.
- **`curl` test against CDN:** Each chunk fetch is <50ms from the test environment. 20 fetches worst-case = ~1s wall-clock. Bail-early on first JWT match makes median 3 fetches = ~150ms. No CDN rate-limit concerns at this volume.
- **No `WebFetch`/`context7` lookup needed:** The fix is a SKILL.md procedure rewrite. No library, framework, or vendor API behavior is in scope. Webpack/Next.js chunking semantics are observed empirically against the live deployment, not derived from docs.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
| --- | --- | --- | --- |
| **A: Static path pin** (current) — hardcoded `app/(auth)/login/page-*.js` | Simple, single fetch | Breaks on every Webpack chunking change — exactly the failure class #3010 documents | Reject — current state, status quo to be replaced |
| **B: Issue's main-app approach** — fetch `main-app-*.js`, parse `r.u=function(e)` chunk-id→filename map | Deterministic mapping | Verified incorrect: that map lives in `webpack-*.js`, not `main-app-*.js`. Adds parser complexity for marginal gain over (C). | Reject — plan reconciliation found the issue's approach hypothesis is empirically wrong |
| **C: HTML-listed chunk traversal** (chosen) | Uses what Webpack already declares — `<script src>` is authoritative for "what does /login load." Idempotent, bounded, simple grep. | Up to 20 HTTP fetches per Check 5 invocation (worst case ~1s; median 1–3 fetches with bail-early). | **Choose** — minimum complexity, maximum coverage, no parser fragility |
| **D: White-box (build-time) probe** — assert the JWT in the build output before deploy | Faster, no network | Replaces the post-deploy black-box layer with a build-time check that already exists (CI Validate step). Defeats the gate's purpose: catching "passed CI but somehow shipped wrong" | Reject — would dissolve the layer the gate exists to provide |
| **E: Proxy via Next.js source-map** to find which chunk holds `lib/supabase/client.ts` | Most precise discovery | Requires source-maps in prod (not enabled), and parsing source-maps is heavyweight. Overkill for "find which chunk has a JWT-shaped string." | Reject — disproportionate complexity for a P3 fix |

## Risks

- **Webpack restructures the bundle further** so the JWT lives in a chunk NOT loaded by `/login`. (Possible if Next.js moves the Supabase init into a layout chunk that only `(authed)` routes load.) Mitigation: if the 20-traversal returns SKIP, the SKIP wording explicitly says "investigate manually" — operator can broaden by probing `/dashboard` instead. Future enhancement: add `/dashboard` to the candidate URL set, but that's out of scope for this P3 fix.
- **CDN rate-limit on rapid sequential fetches.** Mitigation: 20 fetches against CloudFront-fronted Next.js static assets is far below any rate limit; verified empirically.
- **`curl` `--max-time` too aggressive.** Mitigation: 10s per fetch is generous for CDN; if a future deploy is slow, raise per-fetch timeout, don't reduce the candidate cap.
- **Step 5.4 cache-file path drift.** Old Step 5.4 reads `/tmp/preflight-chunk.js`; new reads `/tmp/preflight-chunks/<basename>`. If a future skill edit reverts Step 5.2 without updating Step 5.4, the read will fail silently with empty grep output. Mitigation: Step 5.4's SKIP wording explicitly references "the discovered jwt_chunk" — drift would surface as a clear "no JWT discovered" SKIP, not a silent pass.
- **`jq` parse failure on a non-JSON payload.** The JWT regex `eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+` can theoretically match a literal in a chunk that is NOT a real JWT (e.g., a `eyJ...`-prefixed token in a comment, a documentation example, or a sibling cookie). If the base64-decoded payload is not valid JSON, `jq` returns rc != 0. Mitigation: `jq -er` (raise on null/error) plus an explicit FAIL-on-non-zero-rc per the SKIP-vs-FAIL matrix. Probability of false-FAIL on real prod bundles: very low (the 8237-* chunk JWT is the only `eyJ...` literal in current prod), but fail-closed is correct.
- **Future Webpack restructure could move Supabase init out of all `/login`-loaded chunks.** Mitigation: SKIP-with-investigate-manually wording. Future enhancement (out of scope): probe `/dashboard` (or any authed route) as a secondary candidate URL. Track separately if observed.

## Non-Goals / Out of Scope

- **Adding `/dashboard` or other authed routes to the candidate URL set.** That's a separate widening that would handle the case where Supabase init is in a layout chunk only authed routes load. Defer until a real release exhibits that pattern.
- **Source-map-based discovery.** Disproportionate complexity for a P3 backstop.
- **Test harness for Check 5 itself.** Check 5 is operator-executed against a live deployment; building a fixture-based test would require a fully synthetic Next.js bundle. Not worth it for a procedure that runs <10× per release.
- **Updating the related learning file.** The issue references `knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md`; that file is not in this worktree's tree (recent main commits don't include it). If it lands separately, this plan's PR can `Ref` it but does not depend on it.

## Related

- PR #3007 — added Step 5.4 (the JWT-claims gate); also the release that perturbed Webpack chunking and exposed #3010.
- PR #2975 — added the original Check 5 (URL-host class).
- `knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md` — the leak class Check 5 defends against.
