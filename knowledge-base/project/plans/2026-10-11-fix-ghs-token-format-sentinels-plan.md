---
title: "fix: Update legacy ghs_ token-format sentinels for GitHub's rotated installation-token shape"
type: fix
date: 2026-10-11
slug: fix-ghs-token-format-sentinels
branch: feat-one-shot-9999-ghs-token-sentinels
issue: 9999
closes: 9999
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: Update legacy ghs_ token-format sentinels for GitHub's rotated installation-token shape

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-11 (soleur:deepen-plan, inline sequential fallback — no subagent spawn in this harness; gates 4.6–4.12 all run and pass)
**Sections enhanced:** Scope Check/site table, Research Insights, Per-site edits, Guard Contract, Observability, Architecture Decision, Acceptance Criteria, Test Scenarios, Risks

### Key Improvements

1. **Phase 4.7 reject fixed**: `discoverability_test.command` was suite-shaped (`*.test.sh` — Check 10's 15-second-cap proxy rejects it); replaced with the instant allowlisted-verb probe `grep -c 'ghs_\[A-Za-z0-9._~+/=-\]' run-scan.sh` → `1`.
2. **Site 7 re-grounded**: the regex at `redaction-allowlist.ts:71` is `API_KEY_RE` (plan originally paraphrased `TOKEN_RE`), and it is the mask behind `redactCommandForDisplay` — verified live to feed FOUR render sinks (`permission-callback.ts:1094` review_gate card + notifyOfflineUser, `run-log.ts:55,64`, `destroy-ask-lane.ts:198`, `debug-event.ts`). A truncated mask there displays a live token tail in the user-facing approval card — raises site 7 to the plan's most user-adjacent surface, per the render-sink learning.
3. **`work/SKILL.md` byte ceiling measured**: 362000/362000 — zero headroom; the +7-byte class widening requires a compensating prose trim in the same commit (tasks.md 2.3).
4. **Test-runner correction**: `apps/web-platform` is vitest (`bunfig.toml` blocks bun discovery); prescribed invocations updated to `vitest run`. New `.test.sh` auto-registers via `test-all.sh`'s `plugins/soleur/skills/*/test/*.test.sh` glob; orphan-census assertion added.
5. **Census coverage widened**: Guard 3 gains a family-alternation arm (`(?:ghp|…)_<class>` forms) and `github_pat_`/`gh[opsur]_` literal coverage — a bare `ghs_\[` grep would miss the `API_KEY_RE` shape entirely; `knowledge-base/` pathspec exclusion added (the corpus legitimately quotes legacy shapes).

### New Considerations Discovered

- `API_KEY_RE` carries non-GitHub arms (`sk-*`, `AKIA`, `xox*`, `sbp_`, `sb_secret_`) that stay documented-narrower — the widen is scoped to the two GitHub arms only.
- `redactCommandForDisplay`'s composition is cap-AFTER-redact (`preview` slices the redacted string) — consistent with the fixture's zero-tail assertion.
- ADR amendment precedent confirmed (ADR-067/070/071/126/222 carry `## Amendment`/`## Addendum`).
- `lint-guard-contract.py` green (3 guards); all cited rule IDs resolve; all cited issue/PR numbers verified live; all prescribed verification commands executed once against the pre-change tree (lockstep ok, boundary 37/37, orphan census 666/0).

## Overview

GitHub rotated the issued shape of `ghs_` installation access tokens: the
documented stateless format is `ghs_<APPID>_<JWT>` (~390 chars measured live
2026-10-11, ~520 chars per vendor docs), where the legacy shape was a ~40-char
base62 opaque string. Every sentinel, detection, redaction, and validation
pattern in this repo that was written against `ghs_[A-Za-z0-9]{N}` now judges
only the base62 prefix run of a real token. The redaction site under
`skill-security-scan` is the highest-severity instance: a ~390-char token's
punctuation-carrying tail survives the sed mask and leaks partially into scan
output — the tool meant to find leaks emits one. The write-boundary census for
this change found a seventh stale site the issue missed
(`apps/web-platform/lib/safety/redaction-allowlist.ts:71`), same defect class.

Each stale site moves to the canonical credential alphabet
`[A-Za-z0-9._~+/=-]` — the ADR-280 / `scripts/lib/bearer-curl.sh` class, a
strict superset of GitHub's own recommended `ghs_[A-Za-z0-9.\-_]{36,}` — so the
patterns judge a property (bearer-grammar membership) instead of a vendor's
current format, which is the durable fix for the whole rotation class.

## Problem Statement / Motivation

The #9972 bump-pin guard died on a live-minted ~390-char token and was repaired
by adopting the canonical `_bearer_ok` body (PR #9991). Issue #9999 is the
sibling sweep: every other `ghs_`-shape pin written for the legacy format still
exists and still only inspects the base62 prefix run. Failure modes differ per
site role:

- **Redaction** (`run-scan.sh`, `redaction-allowlist.ts`): a sed/TS mask keyed
  on `[A-Za-z0-9]` stops at the first `.`/`-`/`~`/`+`/`/`/`=` byte. The prefix
  is masked and the credential's tail ships unredacted — a partial-disclosure
  defect that is *worse* than no match, because the output looks handled.
- **Detection** (`SENSITIVE_QUERY_REGEX` pair, `work/SKILL.md` canonical scan,
  `boundary.test.sh` drift pin): the guard's sensitivity to a real credential
  now depends on where in the value the first punctuation byte happens to fall
  — "prefix ≥N alnum chars is luck, not contract."
- **Validation** (`git-auth.ts` `TOKEN_FORMAT_RE`): the `{30,128}` ceiling
  rejects every issued token by length alone, so the warn-not-throw diagnostic
  fires on every `gitWithInstallationAuth` call — telemetry noise that also
  trains readers to ignore the warn the day it signals a real malformation.

## Research Insights

### Relevant file paths (verified against this worktree, all `ghs_[`-shape sites enumerated)

| # | Site | Role | Current shape |
|---|------|------|---------------|
| 1 | `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh:143` (`redact_pii`) | redaction → `<github-server>` | `\bghs_[A-Za-z0-9]{20,}` |
| 2 | `scripts/learning-retrieval-bench.sh:611` (`SENSITIVE_QUERY_REGEX`) | detection (query-refusal guard) | `ghs_[a-zA-Z0-9]{36}` |
| 3 | `plugins/soleur/skills/kb-search/SKILL.md:162` (doc copy of #2) | detection | `ghs_[a-zA-Z0-9]{36}` — byte-equality pinned by `plugins/soleur/test/kb-search-lockstep.test.sh` |
| 4 | `plugins/soleur/skills/work/SKILL.md:864` (fixture-audit canonical scan) | detection | `ghs_[A-Za-z0-9_]{20,}` |
| 5 | `apps/web-platform/server/git-auth.ts:45` (`TOKEN_FORMAT_RE`, consumed at `:274`) | validation, warn-not-throw | `^ghs_[A-Za-z0-9_-]{30,128}$` |
| 6 | `plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh:148` (`check_value_safe_drift`) | detection (secret-literal drift pin) | `ghs_[A-Za-z0-9_]{20,}` |
| 7 | `apps/web-platform/lib/safety/redaction-allowlist.ts:71` (`API_KEY_RE` — the mask behind `redactCommandForDisplay`) | redaction → `[redacted-key]` | `(?:ghp\|gho\|ghu\|ghs\|ghr)_[A-Za-z0-9_-]{20,}` first alternation — **not in the issue's list; found by the write-boundary census**. The same regex also carries a `github_pat_[A-Za-z0-9]{22}_[A-Za-z0-9]{59,}` arm (widened consistently) and non-GitHub arms (`sk-*`, `AKIA`, `xox*`, `sbp_`, `sb_secret_`) that stay documented-narrower |

### Verified non-targets (checked, no change needed)

- `apps/web-platform/test/*` `ghs_*` literals (`ghs_faketoken…`, `ghs_t8_sentinel_value` in `scripts/sweep-followthroughs.test.sh:387`, `"ghs_<<synthetic>>"` in `test/fixtures/github/installation-access-token.json`) are synthesized fixtures whose values are never shape-judged — the sweep-followthroughs probe echoes `GH_TOKEN` verbatim; `git-auth.test.ts` fixtures feed `generateInstallationToken` mocks (the *consumers* of the regex, updated per-site below).
- `tests/scripts/lib/gate-suite-harness.sh` `_ghs_never_aborts` is a function name, not a pattern.
- Bare-prefix sites already shape-agnostic: `.github/workflows/apply-sentry-infra.yml:150`, `plugins/soleur/scripts/lib/domain-model-lib.sh:17`, `scripts/extract-api-spend.sh:83`, `tests/scripts/test-destroy-guard-counter*.sh` comments, `plugins/soleur/skills/ux-audit/SKILL.md:243` prose.
- `tests/scripts/lib/git-data-birth-readiness-gate.sh:1055` `_git_data_rung2_bearer_ok` already carries the canonical `_bearer_ok` body (inside the census ring); only its comment ("alphanumeric plus `_`") is stale — touch-up in scope as a comment-only edit.
- `plugins/soleur/skills/deepen-plan/SKILL.md:481` `ghp_[A-Za-z0-9]{36}` and all `github_pat_[A-Za-z0-9_]` pins: different prefixes whose issued formats have NOT rotated (classic PAT stays base62-36; fine-grained PAT keeps `[A-Za-z0-9_]` incl. `_`); documented-narrower per the issue's own acceptance arm.

### Canonical alphabet authority

- `scripts/lib/bearer-curl.sh` `bc_ok` body: `case "$_bc_v" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac` — the class is RFC 6750 b64token (`A-Za-z0-9` + `.` `_` `~` `+` `/` `=` `-`), the maximal alphabet a bearer value may occupy. The `_bearer_ok` copy ring is pinned byte-identically by `scripts/lint-shell-trace-credential-refusal.test.sh` (`_CANON_BODY`, ~line 2807).
- ADR-280 (`status: adopting`) records the canonical class for the credential channel; see `## Architecture Decision` for the scope extension this plan makes.

### Institutional learnings

- `knowledge-base/project/learnings/test-failures/2026-10-11-a-credential-guard-modeled-on-the-vendor-format-refused-the-vendors-next-format.md` — the direct precedent. Three load-bearing lessons applied throughout: (a) guard a property of the secret, not the vendor's current format; (b) a line-based census sweeps ANY `*.sh` line containing the contiguous literal `_bearer_ok() {` — code, comment, or test pattern — so shell text naming it MUST be assembled split (`'_bearer_''ok() {'`); (c) synthesized fixtures must carry every newly-admitted byte in one value and split-assemble the `ghs_` prefix so the staged-index scanner and GitHub push protection do not flag them.
- `knowledge-base/project/learnings/security-issues/2026-06-04-redaction-fix-must-sweep-all-render-sinks-not-just-new-path.md` — deepened relevance for site 7: a `ghs_` installation token previously leaked through the Concierge `review_gate` approval card via `permission-callback.ts` `preview = command.slice(0,200)`; the fix routed the preview through `redactCommandForDisplay` — **the same `redaction-allowlist.ts` module whose `API_KEY_RE` this plan widens** (verified live: `permission-callback.ts:1094` calls it before `slice(0,200)`). That makes site 7 the most user-adjacent surface in scope: the stale class truncates inside user-facing render paths, and the learning's composition rule (cap AFTER redact — `preview` slices the already-redacted string) is exactly what the new-shape fixture asserts. A punctuation-bearing tail surviving `API_KEY_RE` shows in the card.
- `knowledge-base/project/learnings/2026-03-05-awk-scoping-yaml-frontmatter-shell.md` — `sed` range expressions match EVERY occurrence of a start/stop pair; the `redact_pii` extraction must use flag-based `awk` (as prescribed), never a `sed /start/,/stop/` range, or a repeated delimiter silently widens the extracted program.

### External documentation

- GitHub changelog (2026-05-15): stateless format is `ghs_<APPID>_<JWT>`, ~520 chars variable length, two dots; **vendor-recommended regex `ghs_[A-Za-z0-9.\-_]{36,}`** matching both formats. Canonical class `[A-Za-z0-9._~+/=-]` is a strict superset of the vendor class — adopting canonical satisfies the vendor recommendation AND the issue's "adopt the canonical class" acceptance arm simultaneously.
- GitHub changelog (2026-10-02): stateless-token rollout complete for newly minted installation tokens.

### Premise Validation (Phase 0.6)

- `#9999` is OPEN; cited refs `#9972`/`#9939` CLOSED, `#9905` OPEN (sibling S4 follow-through tracker, not a blocker). PR `#9991` (the #9972 repair) merged.
- All six issue-enumerated sites verified at the cited lines on this worktree (the issue's table says `tests/scripts/` for the boundary test; the real path is `plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh:148` — noted in Research Reconciliation).
- Mechanism check: the feature cites no mechanism rejected by any ADR. The canonical class it points at is the ADR-280 authority — conforming, not diverging.
- Capability claims verified by grep, not assertion: the `_bearer_ok` census pathspec (`*.sh` minus `*.test.sh`/`tests/scripts/test-*`/`scripts/fixtures`) read directly at `scripts/lint-shell-trace-credential-refusal.test.sh:2808`; `redact_pii` has no dedicated test today (only argv-ceiling/meta-dir tests exist); `run-scan.sh` has no `BASH_SOURCE` guard so it cannot be sourced for a unit test — the new test extracts the sed program text instead.

### Property List (Phase 0.6b)

- P1 — No `ghs_`-shape pattern in the repo judges only the base62 prefix run: every site covers the canonical credential alphabet or documents why a narrower shape is correct.
- P2 — `redact_pii` masks a whole new-shape `ghs_` token; zero tail bytes survive into scan output.
- P3 — `TOKEN_FORMAT_RE` accepts every shape GitHub may issue (legacy 36-char body or `ghs_<APPID>_<JWT>` ~390–520) without warn-spam, and still warns on genuinely malformed input.
- P4 — Synthesized-fixture regression coverage exists at each changed detection/redaction/validation site.
- P5 — kb-search ↔ bench `SENSITIVE_QUERY_REGEX` byte-equality is preserved (existing lockstep).
- P6 — No `*.sh` line added by this change joins the `_bearer_ok` census accidentally (split-assembly rule).

### Cut List (Phase 0.6b)

- Shared `GITHUB_TOKEN_CHARS` constant — CUT: the sites span bash/sed ERE, TypeScript RegExp, and markdown prose; no single artifact can carry one constant across all three. The canonical artifact is the alphabet itself, cited per-site by comment to `bearer-curl.sh`/ADR-280 — exactly the pattern the repo already uses for the `_bearer_ok` ring.
- Extract `redact_pii` into a sourceable lib — CUT: `run-scan.sh` runs top-to-bottom with no `BASH_SOURCE` guard; a lib move is a refactor the issue did not ask for. The new test awk-extracts the sed program from the script's own text — the same text the runtime executes, so it cannot drift.
- New standalone census lint file — CUT: `scripts/lint-shell-trace-credential-refusal.test.sh` already owns the credential-guard census; new sweep rows ride in it (Guard 3).
- Rewriting `bc_ok`/`_bearer_ok` to also cover `ghs_` detection — CUT: they are credential-channel shape guards (already canonical); the defect class here is per-site judging, not the channel.

### Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality on this branch | Plan response |
|---|---|---|
| "tests/scripts/ boundary test (boundary.test.sh:148)" | File lives at `plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh:148` | Treat as citation drift; edit the real path |
| Enumerated sites = the stale set | `redaction-allowlist.ts:71` is a seventh same-class site (TS redaction family regex) | Fold in — `hr-write-boundary-sentinel-sweep-all-write-sites` |
| New tokens "~390 chars" | Vendor documents ~520 chars, variable | Bounds derived from vendor `{36,}` floor + unbounded top, not the single measurement |
| Canonical class fixes it | Canonical `[A-Za-z0-9._~+/=-]` ⊋ vendor `[A-Za-z0-9._-]` | Canonical adopted uniformly; vendor regex cited as the documented-narrower reference |

### Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain none of the seven file paths.

## Proposed Solution

Adopt the canonical credential alphabet `[A-Za-z0-9._~+/=-]` at every `ghs_`-
shape site, with per-site bounds/anchors preserved:

| Site | Edit |
|---|---|
| `run-scan.sh:141–144` | `s/\b(ghp\|gho\|ghs\|ghr)_[A-Za-z0-9._~+/=-]{20,}/<github-…>/g` — the whole GitHub family widens: a mask that truncates on ANY rotated family member leaks the same way. Siblings flagged as folded scope (see Scope Check). |
| `learning-retrieval-bench.sh:611` + `kb-search/SKILL.md:162` | `ghp_[a-zA-Z0-9._~+/=-]{36}`, `gho_[a-zA-Z0-9._~+/=-]{36}`, `ghs_[a-zA-Z0-9._~+/=-]{36}`, `github_pat_[a-zA-Z0-9._~+/=-]{40,}` — the refusal guard under-matching is also a paste-through leak; canonical for the GitHub alternation, byte-identical in both files (lockstep). |
| `work/SKILL.md:864` | `ghs_[A-Za-z0-9._~+/=-]{20,}` inside the fixture-audit canonical scan. **Byte-ceiling constraint (measured):** `work` is at `362000/362000` bytes against `plugins/soleur/test/skill-body-budget.json` — zero headroom, and the class widening is +7 bytes (`[A-Za-z0-9_]`→`[A-Za-z0-9._~+/=-]`). The same edit MUST trim ≥7 bytes of prose inside `work/SKILL.md` so the file's net delta is ≤ 0 against the merge base — pick a redundant word in the touched bullet, never a condition (per `knowledge-base/project/learnings/2026-09-23-compressing-prose-to-fit-a-byte-ceiling-dropped-the-conditions-that-made-it-correct.md`: compression under a failing hook drops conditions). |
| `git-auth.ts:45` | `/^ghs_[A-Za-z0-9._~+/=-]{36,}$/` — canonical class, vendor floor `{36,}`, **no ceiling** (vendor documents variable length; the `{,128}` bound is the actual defect). Comment extended: warn-not-throw rationale + vendor rec `ghs_[A-Za-z0-9.\-_]{36,}` citation + canonical-superset note + the warn doubles as a rotation tripwire. |
| `boundary.test.sh:148` | `ghs_[A-Za-z0-9._~+/=-]{20,}` in the `check_value_safe_drift` alternation; add a `bad-ghs-literal.ts` drift fixture (split-assembled new-shape token) exercising the pin. |
| `redaction-allowlist.ts:71` (`API_KEY_RE`) | Widen BOTH GitHub arms inside the regex: `(?:ghp\|gho\|ghu\|ghs\|ghr)_[A-Za-z0-9._~+/=-]{20,}` and `github_pat_[A-Za-z0-9._~+/=-]{22}_[A-Za-z0-9._~+/=-]{59,}` (canonical class per segment, structural `_` separator kept). Non-GitHub arms (`sk-*`, `AKIA`, `xox*`, `sbp_`, `sb_secret_`) stay documented-narrower — unmeasured vendor shapes. This is `redactCommandForDisplay`'s mask — the scrub on FOUR verified render sinks: `permission-callback.ts:1094` (`review_gate` card + `notifyOfflineUser`, the render-sink learning's fix site), `run-log.ts:55,64` (error-summary slices), `destroy-ask-lane.ts:198`, `debug-event.ts` — a truncated mask displays a live token tail in every one, not just log artifacts. |
| `git-data-birth-readiness-gate.sh:1055` | comment refresh only: "alphanumeric plus `_`" → cites canonical b64token alphabet + new issued shape. |

Per-site length floors keep their existing values (`{20,}`/`{36}`/`{40,}`) —
bounds gate detection/recall, the alphabet is what rotated.

### New durable guard

`scripts/lint-shell-trace-credential-refusal.test.sh` gains a **stale-`ghs_`-class
census**: `git grep` over tracked non-doc files flags (arm A) any `gh[opsur]_<char-class>`
or `github_pat_<char-class>` literal and (arm B) any `(...)_<char-class>` alternation
literal containing a `gh`-family member — the `redaction-allowlist.ts:71` site is
`(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_-]`, which a `ghs_\[` grep misses — whose class
does not carry the canonical `._~+/=` bytes.
Sweep pathspec excludes `knowledge-base/` (the corpus legitimately quotes legacy
shapes, this plan included); an explicit allowlist covers synthesized fixtures and
documentation that names the legacy shape in prose. Reintroducing a legacy-shape
pin anywhere fails CI — the enumeration-to-census upgrade this defect class
demands.

## Attack Surface Enumeration

Every code path that can carry a `ghs_` value into a judged position:

- **Token mint → git exec**: `generateInstallationToken` → `gitWithInstallationAuth` → askpass env (checked by `TOKEN_FORMAT_RE` — warn path only, never gates).
- **Token in scan findings**: category output → `jq '{verdict,findings}'` → `redact_pii` → `findings_summary` (the leak path this plan closes).
- **Token in displayed command lines / event text**: `redactCommandForDisplay` → `API_KEY_RE` (`redaction-allowlist.ts`) — display-surface redaction feeding FOUR verified sinks: `permission-callback.ts:1094` (`review_gate` approval-card preview + `notifyOfflineUser`), `run-log.ts:55,64` (error-summary slices), `destroy-ask-lane.ts:198`, `debug-event.ts` (closed by site 7).
- **Credential-shaped text in kb-search queries**: `query_is_sensitive` refusal (`SENSITIVE_QUERY_REGEX` pair) — under-match lets a pasted credential reach the paraphraser (closed by sites 2–3).
- **Secret literals committed into "value-safe" modules**: `check_value_safe_drift` in `boundary.test.sh` (closed by site 6).
- **Real tokens into curl header channel**: `bc_ok`/`_bearer_ok` — already canonical; NOT a stale site (verified).
- **Bypass paths**: `kb-search --no-paraphrase` (explicit opt-out, by design); `ghs_` bare-prefix sentinels (workflows/libs) need no charset — already shape-agnostic.

## Implementation Phases

### Phase 1: Failing tests first (`cq-write-failing-tests-before`)

1. `plugins/soleur/skills/skill-security-scan/test/redact-pii-ghs-shape.test.sh` (new): awk-extract the `redact_pii` sed program from `run-scan.sh` (lines between `^redact_pii() {` and its closing single-quote-only line), run it over a fixture line carrying a synthesized ~390-char `ghs_` token (split-assembled prefix, every canonical byte `.` `_` `~` `+` `/` `=` `-` in the tail). Assert `<github-server>` present AND zero residual tail bytes. Rows: new-shape mask / legacy 40-char still masks (positive control on the same input path) / extraction-dispatch anti-vacuity. Fixture floors the causal quantity: assert the synthesized token's own length (`wc -c` ≥ 380 after the `ghs_` prefix) AND self-check it is out-of-class for the legacy `[A-Za-z0-9]` alphabet (per the learning — a fixture that only carries base62 proves nothing). `mktemp` dirs get an owning `trap` placed before any `source` of helpers (`lint-trap-tempfile-ownership` rule (c)); scratch writes go under `TMPDIR`. The file auto-registers via `test-all.sh`'s `plugins/soleur/skills/*/test/*.test.sh` glob — assert registration with `bash scripts/lint-orphan-test-suites.sh` once tracked (edge: an unregistered suite is a ratchet that never runs).
2. `git-auth.test.ts`: extend the `test.each` accepts-table — add a ~390-char canonical-alphabet fixture incl. `.`/`-`/`_`/`~`/`=` bytes and a `ghs_<appid>_<jwt>`-shaped fixture; assert the format warn (`does not match expected format`) is NOT emitted for them (spy via `vi.doMock("../server/logger")`'s `createChildLogger` or `vi.spyOn` on the module's `log` — pick the seam that intercepts the child logger; the assertion must be on the warn, not on resolution, since warn-not-throw resolves either way), and IS emitted for the mismatch fixture. Retire `"a".repeat(30)` from the accepts table (it only "passes" via warn-not-throw — the table documents accepted *shapes*).
3. `redaction-allowlist.test.ts`: new-shape `ghs_` fixture (split-assembled) → `[redacted-key]` with no tail residue; legacy-shape fixture still masks.
4. `boundary.test.sh`: add `bad-ghs-literal.ts` (split-assembled new-shape token) to the drift-trip loop.
5. `lint-shell-trace-credential-refusal.test.sh`: add the stale-`ghs_`-class census rows (Guard 3) — RED on the CURRENT tree until Phase 2 lands.

### Phase 2: Site edits (single sweep, per Proposed Solution table)

All seven sites + the comment refresh + the ADR-280 amendment. The
bench/SKILL.md pair is edited byte-identically in the same commit.

### Phase 3: Verification

- `plugins/soleur/test/kb-search-lockstep.test.sh` — byte-equality green.
- `boundary.test.sh`, `argv-ceiling.test.sh`, `redact-pii-ghs-shape.test.sh` — suite green.
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/git-auth.test.ts lib/safety/redaction-allowlist.test.ts` — green. **Runner is vitest, not `bun test`**: `apps/web-platform/package.json` `scripts.test` = `vitest`, `bunfig.toml` carries `pathIgnorePatterns = ["**"]` (bun discovery fully blocked), and `vitest.config.ts` unit project `include: ["test/**/*.test.ts", "lib/**/*.test.ts"]` collects both target files.
- `bash scripts/lint-shell-trace-credential-refusal.test.sh` — census green; manually verify one mutation reddens the new rows.
- `bash scripts/lint-orphan-test-suites.sh` — reports `orphan test suites: none` once the new test file is tracked.

## Alternative Approaches Considered

| Option | Why rejected |
|---|---|
| Vendor regex `ghs_[A-Za-z0-9.\-_]{36,}` verbatim everywhere | Documented-narrower is permitted by the acceptance arm, but canonical is the *superset*: adopting it satisfies the vendor form AND removes the need to explain per-site why `~`/`+`/`/`/`=` are excluded. One alphabet = one mental model = the ADR-280 authority. |
| `ghs_` bare-prefix detection only | For redaction a bare prefix can't bound the mask; for `git-auth` an anchored prefix test accepts `ghs_!` — the warn gate becomes meaningless. |
| Per-site bespoke widths/charsets | The exact failure mode the learning names — "the guard judged a vendor's format." The canonical class is the property-shaped contract. |
| Wait for GitHub to stabilize before touching sentinels | Rollout is already complete (vendor changelog 2026-10-02); the live partial-leak window is open now. |

## Files to Edit

- `scripts/learning-retrieval-bench.sh` — `SENSITIVE_QUERY_REGEX` GitHub alternation → canonical class (byte-identical with kb-search copy)
- `plugins/soleur/skills/kb-search/SKILL.md` — same literal, same bytes
- `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh` — `redact_pii` GitHub family lines → canonical class
- `plugins/soleur/skills/work/SKILL.md` — canonical-scan `ghs_` pin → canonical class
- `apps/web-platform/server/git-auth.ts` — `TOKEN_FORMAT_RE` + rationale comment
- `apps/web-platform/test/git-auth.test.ts` — accepts-table fixtures + warn-spy assertions
- `apps/web-platform/lib/safety/redaction-allowlist.ts` — family alternation → canonical class
- `apps/web-platform/lib/safety/redaction-allowlist.test.ts` — new-shape fixture rows
- `plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh` — `check_value_safe_drift` pin + `bad-ghs-literal.ts` fixture
- `scripts/lint-shell-trace-credential-refusal.test.sh` — stale-class census rows
- `tests/scripts/lib/git-data-birth-readiness-gate.sh` — comment refresh only
- `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md` — amendment per `## Architecture Decision`

## Files to Create

- `plugins/soleur/skills/skill-security-scan/test/redact-pii-ghs-shape.test.sh` — the whole-mask regression guard (also the Observability discoverability probe)

## User-Brand Impact

- **If this lands broken, the user experiences:** a security scan whose output still carries the tail of their own GitHub installation token — the redaction visibly ran (`<github-server>` present) while the credential's punctuation suffix sits in the same artifact.
- **If this leaks, the user's data is exposed via:** partial `ghs_` installation-token disclosure inside `findings_summary` / redacted display text — an artifact agents and operators read and may paste onward. A full token grants repo write access for its lifetime.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one operator's partially-leaked installation token is a concrete credential breach for a security-tooling product — not an aggregate pattern, and `none` is unavailable because the diff touches `apps/web-platform/server/` (a canonical sensitive path).
- `requires_cpo_signoff: true` set in frontmatter; `soleur:engineering:review:user-impact-reviewer` runs at review time per the review skill's conditional-agent block. Headless: this sign-off requirement is persisted to `decision-challenges.md` for ship to render.

## Observability

```yaml
liveness_signal:
  what: Credential-guard census + shape regression suites (lint-shell-trace-credential-refusal.test.sh, redact-pii-ghs-shape.test.sh) run in CI; at runtime the git-auth warn path is the rotation tripwire
  cadence: per-PR (CI) / per-gitWithInstallationAuth-call (warn)
  alert_target: PR check failure; platform log pipeline for the warn
  configured_in: scripts/lint-shell-trace-credential-refusal.test.sh; apps/web-platform/server/git-auth.ts:274 (log.warn site)
error_reporting:
  destination: createChildLogger warn stream (apps/web-platform/server/logger.ts) → platform log/Sentry pipeline
  fail_loud: 'log line "Installation token does not match expected format — proceeding" carrying installationId + lengthBucket'
failure_modes:
  - mode: GitHub rotates the token alphabet outside canonical b64token
    detection: TOKEN_FORMAT_RE warn fires on issued tokens — the warn gate doubles as the vendor-rotation tripwire because the regex now accepts the full bearer grammar
    alert_route: platform log pipeline (log.warn)
  - mode: redaction truncates a token at a punctuation byte and leaks the tail
    detection: redact-pii-ghs-shape.test.sh asserts zero residual fixture bytes — RED in CI
    alert_route: PR check failure
  - mode: a new legacy-shape ghs_ pin is introduced in any tracked file
    detection: stale-class census rows in lint-shell-trace-credential-refusal.test.sh — RED in CI
    alert_route: PR check failure
logs:
  where: createChildLogger application log stream (platform)
  retention: platform default
discoverability_test:
  command: grep -c 'ghs_\[A-Za-z0-9._~+/=-\]' plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh
  expected_output: "1"
  why: Smallest probe printing the liveness property — the canonical credential class present in redact_pii's sed program. A suite-shaped command (`*.test.sh`) would be rejected by Check 10's 15-second-cap proxy; the grep is instant, allowlisted-verb, shell-metachar-free.
```

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (inline — this harness exposes no Task/subagent spawn; assessment performed by the planning orchestrator)
**Assessment:** Security-sensitive technical debt inside engineering tooling, no architecture move beyond the ADR-280 scope amendment already named. The one design judgment — canonical class vs vendor-narrow per site — is resolved by the learning's own rule (guard a property, not the vendor's format) and the issue's acceptance arm. No infrastructure, no blast radius outside CI + the redaction/validation surfaces enumerated.

### Product/UX Gate

**Tier:** none — mechanical UI-surface check run over `## Files to Edit` + `## Files to Create`: every path is `.sh`, `server/*.ts`, `lib/safety/*.ts`, `SKILL.md`, `.c4`-free docs, or test files; zero hits against the ui-surface glob superset (`components/**`, `app/**/page.tsx`, `*.njk`, etc.).
**Pencil available:** N/A (no UI surface)

## GDPR / Compliance Gate

Fired: `apps/web-platform/server/git-auth.ts` sits inside an auth-adjacent server surface. Disposition: the change alters a credential-shape regex only — no personal-data collection, storage, schema, lawful-basis, or data-movement change. Advisory disposition: no Art. 9/30 findings; nothing written to `compliance-posture.md`.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-280** (`knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md`, status `adopting`): add a scope-clarification to `## Decision` — the canonical credential alphabet `[A-Za-z0-9._~+/=-]` it adopted for the curl channel is the SAME class every credential-shape sentinel/detection/redaction/validation pattern in the repo must use (or document why narrower); add the rejected alternative "per-site vendor-format pins" naming this incident (#9972 → #9999) as the measured cost. One section amendment, no new ordinal. Precedent for the amendment shape exists: ADR-067/ADR-070/ADR-071/ADR-126/ADR-222 all carry `## Amendment`/`## Addendum` sections — follow that form rather than inventing a new one.

### C4 views

**No C4 impact.** Rubric enumeration against `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` (all three read): (a) external human actors — none added (the operator and the public-issue-reader are already modeled; the token's issuer is not a human); (b) external systems — GitHub is already modeled (e.g., the `github -> gitDataStore` edge and the App-token consumers); no new edge is created — this change alters how *we pattern-match* an already-flowing credential, not the flow; (c) containers/data-stores — none added (edits land inside `webapp` server/lib and `plugin` scripts, existing containers); (d) access relationships — none change.

### Sequencing

Not sequence-bound — the amendment describes the invariant as it exists after this PR lands.

## Guard Contract

### Guard 1 — skill-security-scan `ghs_` whole-mask (`redact-pii-ghs-shape.test.sh`)

**Property.** A `ghs_` credential of any issued shape reaching `redact_pii` is
masked whole — `<github-server>` in the output, zero tail bytes surviving.

**Assembly.** The `redact_pii` sed program in `run-scan.sh` — the single
chokepoint every `findings_summary` body flows through (`jq … | redact_pii`,
run-scan.sh:179). The test awk-extracts THAT program text, so an edit to the
program can't drift past the guard; the only second site of the property is
the family alternation the same sed lines carry.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Revert the `ghs_` class to `[A-Za-z0-9]` | RED — fixture tail survives unmasked |
| 2 | Rename `redact_pii` so the extraction awk matches nothing (guard's own dispatch) | RED — empty sed program leaves the token whole; assertion on `<github-server>` fails |
| 3 | Add a second GitHub-prefix line (`ghx_[A-Za-z0-9]{20,}`) beside a compliant first, then put a `ghx_` fixture through | RED — the family row enumerates each prefix, not the first hit |
| 4 | Harness row: a legacy 40-char base62 token (a non-canonical-but-permitted shape) still masks | PASS required — proves the guard isn't a tautology on the new fixture |

### Guard 2 — `TOKEN_FORMAT_RE` acceptance table (`git-auth.test.ts`)

**Property.** Every shape GitHub may issue (legacy `ghs_` + 36 base62, or
stateless `ghs_<APPID>_<JWT>` over the canonical alphabet, ~390–520 chars) is
accepted without a format warn; genuinely malformed input still warns-and-
proceeds.

**Assembly.** `TOKEN_FORMAT_RE` (git-auth.ts:45) → the single `.test()` call
site (git-auth.ts:274) → the `test.each` acceptance table + the mismatch row +
the new no-warn spy assertion in git-auth.test.ts. One regex, one consumer.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Reinstate the `{,128}` ceiling | RED — the ~390-char fixture triggers the warn the no-warn spy asserts absent |
| 2 | Narrow the class to `[A-Za-z0-9]` | RED — punctuation-carrying fixture warns |
| 3 | Drop the `^…$` anchors so `!ghs_<valid>` passes | RED — the malformed-input row asserts a warn still fires (over-widening is a RED condition, not a silent pass) |
| 4 | Harness row: `"a".repeat(36)` legacy floor AND a 520-char canonical fixture both accepted with no warn | PASS required — guards the floor and the ceiling-free top in one table |

### Guard 3 — stale-`ghs_`-class census (new rows in `lint-shell-trace-credential-refusal.test.sh`)

**Property.** No tracked file carries a GitHub-prefix-shaped char-class
pattern (`gh[opsur]_`, `github_pat_` — literal or inside an alternation)
narrower than the canonical credential alphabet.

**Assembly.** `git grep`/`git ls-files` over the tracked tree (`*.sh`, `*.ts`,
`*.md`, `*.cjs`, `*.yml`, `*.yaml` — every text file where a pattern literal
can live), two sweep arms — (A) `gh[opsur]_<char-class>` and
`github_pat_<char-class>` literals AND (B) `(...)_<char-class>` alternation
literals containing a `gh`-family member (the `redaction-allowlist.ts:71`
`(?:ghp|gho|ghu|ghs|ghr)_…` form a bare `ghs_\[` grep misses) — minus an
explicit allowlist (synthesized fixtures like `ghs_faketoken`, the census's
own sweep pattern, the `:!knowledge-base/` pathspec exclusion for the doc
corpus that legitimately quotes legacy shapes). Members drift; the chokepoint
is the committed tree itself.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Reintroduce `ghs_[A-Za-z0-9]{20,}` in any tracked file | RED |
| 2 | Weaken the sweep pattern so it matches zero literals (guard's own dispatch — "0 checked" must not exit 0) | RED — the row asserts a nonzero *classified* count, not just zero violations |
| 3 | Add a second stale site in a different file after a compliant first | RED — the sweep enumerates every hit, not the first |
| 4 | Harness row: canonical `ghs_[A-Za-z0-9._~+/=-]{20,}` + fixture `ghs_faketoken` + `github_pat_` pins | PASS required — the sweep discriminates stale classes from non-targets |

**Anchor.** The census reads the tracked tree: a weakening needs the stale
pattern AND the sweep edit in one commit — diff-visible to review; the sweep
regex is pinned in the suite the same way `_CANON_BODY` already is.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Each site either adopts the canonical `[A-Za-z0-9._~+/=-]` credential class (see `scripts/lib/bearer-curl.sh` `bc_ok` / the `_bearer_ok` canonical-body copies) or documents why a narrower shape is correct for it." | Phase 2 site-edit table; AC-1 | mapped |
| 2 | "`run-scan.sh` redaction is the highest-severity site — verify with a synthesized ~390-char fixture containing `.`/`-` that the whole value is masked." | Phase 1 item 1 (`redact-pii-ghs-shape.test.sh`); Guard 1; AC-2 | mapped |
| 3 | "`git-auth.ts` `TOKEN_FORMAT_RE` needs the length bound re-derived from the measured issued range, or a comment pinning the warn-not-throw rationale." | Phase 2 git-auth edit (`{36,}` re-derived from vendor floor + measured ~390–520 range); extended comment; AC-3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `redaction-allowlist.ts:71` edit | — | inferred — justification: `hr-write-boundary-sentinel-sweep-all-write-sites`; same truncation defect class as the run-scan redaction the issue flags highest-severity |
| GitHub-family widen in `run-scan.sh` (`ghp_`/`gho_`/`ghr_` lines) and in `SENSITIVE_QUERY_REGEX` (`ghp_`/`gho_`/`github_pat_`) | — | inferred — justification: under-match in a mask/refusal guard is the same disclosure class; canonical class is fail-safe superset. Reviewer may descope to `ghs_` only — flagged, not hidden |
| stale-`ghs_`-class census (Guard 3) | — | inferred — justification: enumeration-only fixes rot at the next unlisted site; the issue's own defect exists because a prior census missed this class |
| `bad-ghs-literal.ts` fixture in boundary.test.sh | — | inferred — justification: the edited drift pin is otherwise unexercised by any ghs_ fixture (current fixtures cover `sk_live_` only) |
| git-data-birth-readiness-gate.sh comment refresh | — | inferred — justification: the comment states a now-false alphabet ("alphanumeric plus `_`") above an already-canonical body |
| ADR-280 amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; extending the canonical class's authority to all credential-shape sites is an ADR extension |

### Split Assessment

- Subsystems touched: 3 — `apps` (web-platform), `plugins` (soleur), `scripts`
- Planned files: 12 edit + 1 create | Estimated changed lines: ~150
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC-1: The stale-class census (Guard 3, both arms — `gh[opsur]_`/`github_pat_` `<class>` literals AND `gh`-family alternation literals) reports zero non-allowlisted hits over tracked files excluding `knowledge-base/`: every GitHub-prefix-shaped char-class literal in swept files carries the canonical `[A-Za-z0-9._~+/=-]` alphabet, or the site documents why narrower (the allowlisted non-targets enumerated in Research Insights, e.g. `API_KEY_RE`'s non-GitHub arms). `knowledge-base/` is excluded by pathspec because plan/spec/learning docs legitimately quote the legacy shape — this plan file included (an unsatisfiable-by-construction AC is its own defect class).
- [ ] AC-2: `bash plugins/soleur/skills/skill-security-scan/test/redact-pii-ghs-shape.test.sh` prints `redact-pii-ghs-shape: ok` — a synthesized ~390-char `ghs_` token containing `.`, `-`, `_`, `~`, `+`, `/`, `=` is masked whole by `redact_pii` (zero tail bytes in output), AND the same assertion holds for a legacy 40-char token.
- [ ] AC-3: `TOKEN_FORMAT_RE` accepts `ghs_` + 36..520+ canonical-alphabet chars with NO format warn emitted (spy on the child logger), and `not-a-ghs-token` still produces the warn. The `{30,128}` ceiling is gone; the rationale comment cites the vendor-recommended `ghs_[A-Za-z0-9.\-_]{36,}` and the canonical-superset choice.
- [ ] AC-4: `plugins/soleur/test/kb-search-lockstep.test.sh` exits 0 — the bench and SKILL.md `SENSITIVE_QUERY_REGEX` literals remain byte-identical after the alternation edit.
- [ ] AC-5: `apps/web-platform/lib/safety/redaction-allowlist.test.ts` contains a new-shape `ghs_` fixture asserting `[redacted-key]` with no residual tail; the family regex uses the canonical class.
- [ ] AC-6: `boundary.test.sh` carries a `bad-ghs-literal.ts` drift-trip fixture with a split-assembled new-shape token, and its `check_value_safe_drift` pin uses the canonical class.
- [ ] AC-7: `lint-shell-trace-credential-refusal.test.sh` contains the stale-class census rows; manually reintroducing `ghs_[A-Za-z0-9]{20,}` in a scratch file under a swept pathspec drives them RED (mutation verified during implementation, result recorded in the PR body).
- [ ] AC-8: ADR-280 carries the scope-clarification amendment (canonical alphabet governs all credential-shape sites).
- [ ] AC-9: No `*.sh` line added by this change contains the contiguous literal `_bearer_ok() {` — verified by running the census suite itself.
- [ ] AC-10: All fixture `ghs_` values are split-assembled (prefix and body joined at write time) so `git-commit-secret-scan.sh` and GitHub push protection see no contiguous token-shaped literal.

## Test Scenarios

- **unit** — Given `redact_pii` extracted from run-scan.sh, when a ~390-char `ghs_` fixture with `.`/`-`/`_`/`~`/`+`/`/`/`=` bytes is piped through, then output contains `<github-server>` and contains none of the fixture's tail.
- **unit** — Given `gitWithInstallationAuth` and a mocked `generateInstallationToken` returning a ~390-char canonical fixture, when the call resolves, then no `does not match expected format` warn is emitted; given `"not-a-ghs-token"`, the warn IS emitted.
- **unit** — Given `redactGithubSourcedText`, when text embeds a new-shape `ghs_` fixture, then output contains `[redacted-key]` and no fixture bytes past the prefix.
- **integration** — Given the kb-search lockstep test, when it runs post-edit, then `SENSITIVE_QUERY_REGEX` is byte-identical across `learning-retrieval-bench.sh` and `kb-search/SKILL.md`.
- **integration** — Given `check_value_safe_drift`, when `bad-ghs-literal.ts` (new-shape token) is checked, then it returns drift (1); `good.ts` still passes (0).
- **integration** — Given the stale-class census rows, when a scratch file under a swept pathspec reintroduces `ghs_[A-Za-z0-9]{20,}`, then the census reports it RED.

**Verification commands:**

- `bash plugins/soleur/skills/skill-security-scan/test/redact-pii-ghs-shape.test.sh` → `redact-pii-ghs-shape: ok`
- `bash plugins/soleur/test/kb-search-lockstep.test.sh` → `kb-search-lockstep: ok`
- `bash plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh` → pass/fail ledger, 0 fail
- `bash scripts/lint-shell-trace-credential-refusal.test.sh` → pass ledger, 0 fail
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/git-auth.test.ts lib/safety/redaction-allowlist.test.ts` → green

## Non-Goals

- `ghu_`-only sites, `gho_`/`ghr_` vendor-format *verification* (whether those prefixes have actually rotated is unmeasured; widening the redaction/refusal family to canonical is the fail-safe posture either way).
- `github_pat_` format change — fine-grained PATs keep their documented `[A-Za-z0-9_]` shape; canonical superset covers it identically.
- Rewriting `bc_ok`/`_bearer_ok` or the canonical class itself — already canonical; the census ring is untouched.
- `deepen-plan/SKILL.md:481` `ghp_` pin — classic-PAT shape is still current.
- Refactoring `redact_pii` into a sourceable lib (cut per 0.6b).

## Dependencies & Risks

- **Lockstep drift**: bench ↔ kb-search edits must land byte-identically in the same commit — AC-4 + the lockstep test enforce.
- **Census self-sweep**: any `*.sh` line naming the canonical guard function contiguously joins the `_bearer_ok` copy ring — assemble split everywhere, including comments and the new test's own patterns.
- **Push protection / staged-index scan**: contiguous ~390-char `ghs_` fixtures could trip gitleaks or GitHub push protection — all fixtures split-assembled (precedent: `redaction-allowlist.test.ts:69` `"ghp"+"_"`, `boundary.test.sh` `"sk_""live_"`).
- **Vendor measurement vs docs**: issue measured ~390 chars; vendor documents ~520 variable — bounds use the vendor `{36,}` floor and no ceiling, so the discrepancy cannot re-break the validator.
- **Regex input size**: `redact_pii` input is per-finding bodies already bounded upstream (200-char snippet window, capped category output); the canonical class is a flat character class — linear-time, no catastrophic-backtracking surface. `TOKEN_FORMAT_RE` runs on a minted env value, not user input.
- **work/SKILL.md byte ceiling**: 0 bytes headroom (362000/362000) — the site edit is net +7 bytes; a compensating ≥7-byte prose trim in the same file must land in the same commit, on a redundant word (never a condition).

## Success Metrics

- Zero stale `ghs_` char-class literals in the tracked tree (Guard 3 census).
- `redact_pii` demonstrably masks the whole new-shape token (Guard 1).
- Zero format warns on issued-shape tokens (Guard 2 table).

## Sharp Edges

- **`_bearer_ok() {` census contamination**: `lint-shell-trace-credential-refusal.test.sh` sweeps ALL `*.sh` lines (excluding `*.test.sh`, `tests/scripts/test-*`, `scripts/fixtures`) for the contiguous literal — including comments. Any shell text added by this change that names the canonical guard MUST be assembled split (`'_bearer_''ok() {'`), and comments must avoid the contiguous form.
- **kb-search lockstep**: `SENSITIVE_QUERY_REGEX` lives in two files pinned byte-equal — edit both in the same edit/commit or CI reddens.
- **Fixture prefix splitting**: synthesize `ghs_` fixtures by joining `"ghs"+"_"` / `"ghs"_"` (or the file's existing idiom) — never a contiguous ~390-char literal; carry EVERY newly-admitted byte in one fixture value so the regression actually exercises the widened class.
- **`test.each` semantic drift**: warn-not-throw means a mismatched token still *resolves* — an "accepts" table row that now warns is silently testing nothing. The no-warn spy assertion is what makes the table meaningful.
- **sed `\b` and canonical `=`/`/`/`+` bytes**: `\bghs_` still anchors correctly (`:`/`"`/` ` precede the token); the widened class includes `=` so base64-padding tails are consumed too — verify the fixture's tail actually exercises `=` at a boundary.
- **A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6** — filled above.

## References & Research

- Issue: #9999 (this work); refs #9972 (the repaired site), #9939 (incident chain), #9905 (S4 sibling tracker, OPEN)
- Canonical alphabet: `scripts/lib/bearer-curl.sh:59` (`bc_ok`); copy-ring census `scripts/lint-shell-trace-credential-refusal.test.sh:~2807`
- ADR: ADR-280 (amendment target)
- Learning: `knowledge-base/project/learnings/test-failures/2026-10-11-a-credential-guard-modeled-on-the-vendor-format-refused-the-vendors-next-format.md`
- Vendor docs: GitHub changelog 2026-04-24 / 2026-05-15 / 2026-10-02 — `ghs_<APPID>_<JWT>` format, ~520 chars, recommended `ghs_[A-Za-z0-9.\-_]{36,}`
