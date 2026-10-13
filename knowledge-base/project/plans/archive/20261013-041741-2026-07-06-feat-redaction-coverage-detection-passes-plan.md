---
title: "feat: redaction-engine coverage — whitespace-reflow, Cloudflare token, base64/hex/percent decode, headerless-PEM"
date: 2026-07-06
issue: 6045
branch: feat-redaction-coverage-bundle-6045
pr: 6098
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-086-fail-closed-redaction-engine-contract (amend; note 3-way ADR-086 ordinal collision → #6054)
brainstorm: knowledge-base/project/brainstorms/2026-07-06-redaction-coverage-bundle-brainstorm.md
spec: knowledge-base/project/specs/feat-redaction-coverage-bundle-6045/spec.md
deferred: ["#6104 (TR39 + entropy)", "#6105 (legal-audit UC2)"]
plan_review: 5-agent panel (DHH/Kieran/code-simplicity/architecture-strategist/spec-flow) + fable advisor — applied 2026-07-06
---

# Redaction-Engine Coverage: Detection Passes (#6045)

## Overview

Extend the fail-closed redaction engine (`plugins/soleur/skills/incident/scripts/redact-engine.py`,
shipped PR #6032 under [ADR-086](../../engineering/architecture/decisions/ADR-086-fail-closed-redaction-engine-contract.md))
to close four of the eight named non-goals in ADR-086 §"Scope boundary". The engine is a pure-Python
CLI primitive invoked synchronously by three skill gates (incident `dry-run.sh`, `code-to-prd` Layer 2,
`legal-generate` pre-presentation gate) — all of which dispatch **only on the exit code** (0 clean / 1
redaction-needed / 2 cannot-evaluate). It scrubs secrets/PII from egress artifacts, some external-facing
(PRDs to buyers/investors, legal drafts), so a false negative is a GDPR Art. 33/34 breach surface and a
false positive fail-closes a legitimate write. Scope was settled in the brainstorm; this plan is HOW.

**Branch structure (3 PRs — drift-guard first, per operator + advisor):**

- **PR-A — item 8 (allowlist-aware class-list drift-guard) + crown-jewel/body sync into `digest-scrub.sh`.**
  Ships first: zero code dependency, fixes the *already-live* `digest-scrub.sh` drift, and forces every
  class PR-B/PR-C add to make its sync-vs-allowlist decision at introduction (guard goes red otherwise).
- **PR-B — item 1 (whitespace/newline reflow re-scan) + item 6 (anchored Cloudflare token class).**
- **PR-C — item 2 (base64/hex/percent decode-and-rescan) + item 3 (headerless-PEM private-key DER heuristic).**
  ADR-086 amendment lands here (after all four items are green).

**Deferred (own issues, filed in brainstorm):** #6104 (item 4 TR39 + item 5 entropy, needs-evidence),
#6105 (item 7 legal-audit UC2).

## Research Reconciliation — Spec vs. Codebase

| Claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Engine ~153 lines; ERE↔`re` parity constrains new patterns | Confirmed 153 lines on main. **Parity is new ⊇ *old bash* engine (Test 9), NOT per-pattern ERE** — the sentinel is a pure `python3 redact-engine.py` shim, no ERE mirror | Python-only constructs (lookaround, predicates, reflow, decode) permitted; only invariant: never NARROW an existing class |
| item 3 headerless-PEM is independent | It is a branch inside item 2's base64-decode loop (shared machinery) | Group items 2+3 in PR-C |
| DER shape = `SEQUENCE 0x30 0x8[1-3], len≥64` | **Long-form length only** → misses EC P-256 (short-form ~118B) + Ed25519 (~48-85B); also matches **public** X.509 certs/SPKI (FP fail-close) | Replace with a **private-key discriminator** (§PR-C): accept short+long form, require inner `INTEGER` version (private) not inner `SEQUENCE` (cert); record encrypted-PKCS#8 headerless as a residual ADR gap |
| decode-rescan re-runs all classes | Weakly-anchored `IPv4`/`UUID`/`email` on decoded high-entropy bytes → manufactured FP → fail-close | Scope `_scan_text` to **anchored secret classes only** |
| `digest-scrub.sh` "Verbatim from redact-sentinel.sh" | **False:** missing `doppler_token`+`slack_token` (names); `env_var` missing HETZNER/FLAGSMITH/RESEND/TAILSCALE, `pem` fixed `RSA\|EC\|…`, `UUID` lowercase-only (bodies) | PR-A syncs names + the 3 body drifts; corrects the comment; guard enforces name-level going forward (body-parity is a documented non-goal — ERE↔`re` bodies aren't cheaply comparable) |
| drift-guard spans "three redactors" | `linear-urls.sh` is a single orthogonal Linear-CDN-URL class, `sed`-rewrites (no halt), zero secret overlap | Guard covers engine ↔ `digest-scrub.sh`; `linear-urls.sh` out-of-set (code comment) |
| reflow bounded by `REFLOW_WINDOW` | Window-capped but **no occurrence cap** → prefix-flooded 1 MiB input hangs (`code-to-prd` threat model is adversarial) | Add `_MAX_REFLOW_CANDIDATES` mirroring the decode cap |
| — | A research subagent wrote a full untested impl of items 1/2/3/6 into `redact-engine.py` during the no-code phase; reverted, preserved at `scratchpad/stray-impl-6045/`. Operator chose the disciplined pipeline | Design reference only; `/work` implements test-FIRST. See Session Errors |

## User-Brand Impact

*(Carried forward from brainstorm Phase 0.1 — do not re-author.)*

- **If this lands broken, the user experiences:** a real credential/PII secret survives the scan into an
  external-facing `code-to-prd` PRD or `legal-generate` draft (broken-detection), OR a false positive
  over-redacts and fail-closes a legitimate write (broken-availability).
- **If this leaks, the user's data is exposed via:** a secret reflowed across whitespace, base64-encoded in
  a k8s Secret manifest, or a `HETZNER_TOKEN=…` slipping through the drifted `digest-scrub.sh` — a GDPR
  Art. 33/34 breach.
- **Brand-survival threshold:** single-user incident → `requires_cpo_signoff: true` (carried from brainstorm
  triad); `user-impact-reviewer` runs at PR-review.

## Implementation Phases

### Shared engine invariants (all PRs)

- **New emit paths MUST route through `_emit` → `_meta_redact`** (≤4-char reveal) — a raw print leaks a full
  token to the transcript and every existing test stays green (corpus trips only the base pass).
- **Dedup:** a single `seen` set keyed on **`(class_name, matched_value)`** (offsets are cross-coordinate —
  norm-space vs decoded-derived-space — so not a key). Dedup affects finding-line noise only, never the exit
  code. Document the *why* (reflow re-scans unsplit secrets the base pass already caught) at the declaration.
  Keep `_emit` thin (membership-check + print + `hits += 1`); no separate `findings` list.
- **Finding-line contract:** frozen `at offset N: <=4***<=4 matched pattern <class>` with an optional
  ` (<tag>)` suffix. The tag is a diagnostic (which pass fired) — **verified safe** (all 3 consumers
  exit-code-dispatch; Test 2/4/9 substring/`-oE`-match and stop at the space). Invariant: **the tag always
  starts with a non-`[A-Za-z_]` delimiter (the leading `` ( ``)** so the parity `grep -oE` never absorbs it.
  *(No consumer parse-audit phase — verified none machine-parse the line.)*
- **Fan-out caps fail toward bounded work, and every cap carries a one-line inline rationale:**
  `_MAX_REFLOW_CANDIDATES`, `_MAX_ENCODED_CANDIDATES`, `_MAX_CANDIDATE_LEN`, `REFLOW_WINDOW` (512 — ~2.5×
  the longest anchored body, not 4096). Note inline that the decode/reflow caps are safe **because** the
  1 MiB `MAX` input cap dominates; if `REDACT_MAX_INPUT_BYTES` is raised they must be re-evaluated.

### PR-A — item 8: drift-guard + `digest-scrub.sh` sync

A1 **Sync `digest-scrub.sh`** to eliminate the documented drift: add `doppler_token`, `slack_token` (names);
   widen `env_var` vendor list to match the engine (+HETZNER/FLAGSMITH/RESEND/TAILSCALE), `pem` qualifier to
   `[A-Z0-9 ]*PRIVATE KEY`, `UUID` to `[0-9A-Fa-f]`. Correct the header comment to
   `# Secret classes — class-name set + bodies synced with redact-sentinel.sh 2026-07-06; name-level parity CI-enforced (redact-class-parity.test.sh); regex-body parity is a named non-goal.`
A2 **Drift-guard test** (`plugins/soleur/skills/operator-digest/test/redact-class-parity.test.sh`): parse the
   engine's `PATTERNS` class names; **self-test** that the parsed count equals the actual `PATTERNS` length
   (dark-fail guard — a parser miss must fail loudly); assert each secret-class name is present in
   `digest-scrub.sh`'s `SECRET`/`SECRET_ORDER` **or** in a `DIVERGENCE_ALLOWLIST` with a one-word rationale
   (e.g. `cloudflare_token=not-in-digest`, `UUID=pii-not-secret`). Fail closed on any un-classified new class.
   `linear-urls.sh` is out-of-set (code comment, not parity-checked).
A3 **GREEN + negative control:** guard passes on the synced state; deliberately un-sync one class locally →
   guard FAILs; drop one `PATTERNS` entry locally → count self-test FAILs.

### PR-B — item 1 (whitespace reflow) + item 6 (Cloudflare token)

**TDD: write the failing evasion tests first (`cq-write-failing-tests-before`), then implement.**

B1 **Item 6 (Cloudflare):** add `cloudflare_token` to `PATTERNS` as
   `(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{40}(?![A-Za-z0-9_-])` (explicit non-class boundaries, not `\b` — `-` is a
   non-word char and interacts badly with `\b` at token ends), gated by an **inline** post-match check
   (not a registry framework for N=1) requiring BOTH `[A-Z]` and `[0-9]` (hex SHA → digit-no-upper → reject;
   kebab prose → neither → reject). Document the deliberate ~0.1% miss. Add to Test 2 loop + `positive-corpus.md`.
   Update PR-A's guard allowlist: `cloudflare_token=not-in-digest`.
B2 **Item 1 (reflow):** introduce the `seen`/`_emit` dedup, then `_scan_reflow`. Reflow-eligible prefixes are
   **derived from a `reflow=True` marker on `PATTERNS` entries** (single source — no hand-maintained parallel
   list); exclude short/ambiguous `sk-` and the prefixless Cloudflare class. For each eligible prefix at a
   real ASCII word boundary (`_is_word(norm[p-1])` guard), despace a `REFLOW_WINDOW` (512) window, re-match
   the full anchored pattern, `_emit(tag="whitespace-rejoin")`. Bound total occurrences by `_MAX_REFLOW_CANDIDATES`.
B3 **Header + GREEN:** trim item-1/item-6 lines from `redact-sentinel.sh`'s non-goal header **in this PR**
   (avoid a stale-header window before PR-C); full suite green; Test 9 parity + Test 4b green.

**Tests (B):**
- Reflow **two-engine** (Test 5a/5b pattern): the old `legacy-bash-scanner.sh` MISSES the split token (exit 0);
  the new engine CATCHES it (exit 1) — proves the pass is load-bearing (not another pass catching it).
- **Distinct** newline-split AND space-split positives (whitespace kinds differ post-normalization).
- Reflow **no-FP on an INCLUDED prefix:** `dp.st.` followed by despaceable prose must NOT manufacture
  `dp.st.somewordstotalling16+` → assert negative baseline still exits 0. *(The `risk-based`/`sk-` case tests
  an EXCLUDED prefix — keep it, but it is a base-pass test, not the reflow-FP guard.)*
- Cloudflare positive (upper+digit) trips; 40-char lowercase-hex git SHA + 40-char kebab prose do NOT; negative baseline exits 0.
- Test 4b (≤4-char reveal) asserted on a **reflow-caught** finding.

### PR-C — item 2 (decode) + item 3 (headerless-PEM private-key DER)

C1 **`_scan_text` (restricted):** re-run only the **vendor-prefix/format-anchored secret classes** over a
   derived string (exclude `IPv4`, `UUID`, `email` — weakly anchored, FP-prone on decoded high-entropy bytes).
C2 **`_scan_encoded`:**
   - **base64 candidate assembly:** match base64/base64url runs AND **join consecutive base64-only lines** into
     a candidate block (real PEM/DER bodies are 64-char line-wrapped; a per-line run never decodes to a full key).
     Bound by `_MAX_ENCODED_CANDIDATES` / `_MAX_CANDIDATE_LEN`. Decode std-then-url-safe, pad-tolerant,
     **per-candidate `try/except (binascii.Error, ValueError): continue`** (never bubble to `main()`'s exit-2
     catch-all → would over-block on one malformed innocent blob).
   - **item 3 (private-key DER discriminator):** on each decoded blob starting `0x30` (SEQUENCE), parse the
     length (short-form `raw[1]<0x80` OR long-form `0x81/0x82/0x83`), then inspect the first inner element:
     `0x02` (INTEGER version 0/1) → **private-key shape → emit `pem_key_body`**; `0x30` (inner SEQUENCE) →
     cert/SPKI/public → **do NOT emit**. Covers RSA (long) + EC/Ed25519 (short); rejects public certs.
   - hex runs (even-length) → `bytes.fromhex` → `_scan_text`. percent → `unquote` once → `_scan_text`.
C3 **ADR-086 amendment (additive/dated)** + header comment (see Phase Z).

**Tests (C):**
- **Positive** base64 / **base64url** (url-safe branch) / hex / percent, each of a known secret → exit 1 + base class.
- **No-FP:** data-URI image body; `sha512-…` SRI hash; a git SHA / sha256 hex; a JWT that decodes to JSON
  containing an email; **a percent-encoded URL/prose** (`%2F`) → all exit 0 (percent is the highest-FP path —
  `unquote` rewrites the whole string).
- item 3 **positive:** headerless RSA, EC P-256, **and** Ed25519 private-key bodies (short + long form) → `pem_key_body`.
- item 3 **no-FP:** a public X.509 cert body; PNG/JPEG; a blob beginning `0x30 0x81` that is NOT a key → all clean.
- **Behavioral** fan-out bound (not presence-grep): many base64 runs / a prefix-flooded input asserts bounded
  work completes (mirror Test 6/6b's behavioral style) — pins `_MAX_ENCODED_CANDIDATES` + `_MAX_REFLOW_CANDIDATES`.
- Test 4b (≤4-char reveal) asserted on a **decode-caught** finding.
- Add `pem_key_body` to Test 2 loop + `positive-corpus.md`. Update guard allowlist: `pem_key_body=not-in-digest`.

*(No-FP negatives are already-green pre-impl — they are post-impl **regression guards**, re-run by each PR's "full suite green" step, not RED cases.)*

## Files to Edit
- `plugins/soleur/skills/incident/scripts/redact-engine.py` — PR-B (predicate + reflow + dedup), PR-C (decode + DER)
- `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` — new tests each PR; extend Test 2 loop
- `plugins/soleur/skills/incident/test/fixtures/positive-corpus.md` — `cloudflare_token` (PR-B), `pem_key_body` (PR-C)
- `plugins/soleur/skills/incident/scripts/redact-sentinel.sh` — header non-goal list trimmed per-PR (B, C)
- `plugins/soleur/skills/operator-digest/scripts/digest-scrub.sh` — PR-A (names + body sync + comment)
- `knowledge-base/engineering/architecture/decisions/ADR-086-fail-closed-redaction-engine-contract.md` — PR-C amendment

## Files to Create
- `plugins/soleur/skills/operator-digest/test/redact-class-parity.test.sh` — PR-A drift-guard

## Acceptance Criteria

### PR-A (Pre-merge)
- [ ] `digest-scrub.sh` gains `doppler_token`+`slack_token` and the synced `env_var`/`pem`/`UUID` bodies; header comment corrected.
- [ ] Guard: class-count self-test passes (parsed == `len(PATTERNS)`); every secret class present-in-digest or allowlisted (one-word rationale); FAILs when a class is unsynced-and-unallowlisted (proven locally) and when a `PATTERNS` entry is dropped.
- [ ] `linear-urls.sh` out-of-set (code comment).

### PR-B (Pre-merge)
- [ ] Reflow two-engine test: old MISSES, new CATCHES a split secret; distinct newline + space positives green.
- [ ] Reflow no-FP on an **included** prefix (`dp.st.`+prose) exits 0; negative baseline exits 0.
- [ ] Cloudflare upper+digit trips; git SHA + kebab prose do NOT; `cloudflare_token` in Test 2 + corpus + guard allowlist.
- [ ] `_MAX_REFLOW_CANDIDATES` present + inline rationale; `REFLOW_WINDOW`=512; Test 4b asserted on a reflow finding; Test 9 parity green.
- [ ] `redact-sentinel.sh` header no longer lists whitespace/Cloudflare as non-goals.

### PR-C (Pre-merge)
- [ ] base64/base64url/hex/percent positives each trip; wrapped-base64 block assembly catches a line-wrapped body.
- [ ] No-FP: data-URI image, `sha512-` SRI, git SHA/sha256, JWT-decodes-to-JSON-with-email, percent-encoded URL — all exit 0; Test 8 green.
- [ ] `_scan_text` excludes IPv4/UUID/email; per-candidate decode `try/except/continue` (a malformed base64 candidate does NOT force exit 2).
- [ ] item 3 catches RSA + EC + Ed25519 headerless bodies; rejects public cert + PNG/JPEG + `0x30 0x81` non-key.
- [ ] Behavioral fan-out bound test green; Test 4b asserted on a decode finding; `pem_key_body` in Test 2 + corpus + guard allowlist.

### Phase Z (Pre-merge, in PR-C)
- [ ] ADR-086 amended **additively** (original §Scope-boundary text preserved under a dated "Amended 2026-07-06" subsection; items 1/2/3/6 marked covered; **encrypted-PKCS#8 headerless** + EC/Ed25519-edge recorded as residual gaps; 4/5/7 remain non-goals with #6104/#6105 links). Full slug cited; 3-way ADR-086 ordinal collision noted (→ #6054).
- [ ] `redact-sentinel.sh` header matches final coverage.

## Architecture Decision (ADR/C4)

### ADR
**Amend `ADR-086-fail-closed-redaction-engine-contract`** (not a new ordinal — fulfills the ADR's own stated
follow-up; `wg-architecture-decision-is-a-plan-deliverable`). Amendment is **additive/dated** — an Accepted
ADR is a GDPR breach-forensics record ("was base64 decode covered as of date X?"), so preserve the original
scope-boundary lines under `### Amended 2026-07-06` rather than deleting them. Record residual gaps honestly
(encrypted-PKCS#8 headerless bodies; entropy detector deferred → #6104). Disambiguate the pre-existing 3-way
`ADR-086-` ordinal collision (`declarative-skill-context-injection`, `fail-closed-redaction-engine-contract`,
`freshness-last-reviewed`) by citing the full slug; the collision itself is tracked by #6054 (out of scope).

### C4 views
**No C4 impact.** All three model files read (`{model,views,spec}.c4`); a `redact|scrub|pii` grep across all
three returns zero. Enumeration: (a) external human actors — none new; (b) external systems/vendors — none new;
(c) containers/data-stores — none (the engine is a synchronous plugin-skill CLI primitive, below C4 container
granularity, modeled in none of the three files; the only `secret` refs are Doppler secrets-mgmt + the
dep-cruiser client→server-secret gate, both unrelated); (d) access relationships — none change. "None" cited
against the enumeration, not asserted bare (confirmed by architecture-strategist review).

## Observability

```yaml
liveness_signal:
  what: redact-sentinel.test.sh + redact-class-parity.test.sh (fail-closed contract, no-FP, parity, drift-guard)
  cadence: per-PR CI (plugin bash test suite) on any change to incident/legal-generate/operator-digest skills
  alert_target: CI red → PR blocked from merge
  configured_in: plugins/soleur/test + redact-sentinel.test.sh + redact-class-parity.test.sh
error_reporting:
  destination: fail-closed exit code to the invoking skill (dry-run/code-to-prd Layer 2/legal-generate) + sentinel stderr
  fail_loud: true  # exit 1 (redaction needed) / 2 (cannot-evaluate) blocks the write; never silent
failure_modes:
  - mode: false-negative (a real secret passes the scan)
    detection: per-item positive evasion tests (reflow two-engine, decoded, private-key DER) codify each class
    alert_route: CI red on redact-sentinel.test.sh
  - mode: false-positive (over-redaction blocks a legitimate write)
    detection: broadened no-FP negatives (git SHA, kebab prose, data-URI image, sha512 SRI, JWT-JSON, public cert, percent URL)
    alert_route: CI red on redact-sentinel.test.sh
  - mode: cross-redactor drift (a class caught by the engine leaks through digest-scrub.sh)
    detection: redact-class-parity.test.sh (name-level parity + class-count self-test)
    alert_route: CI red on the parity test
  - mode: engine crash / malformed-candidate decode error
    detection: per-candidate try/except; main() catch-all → exit 2 (cannot-evaluate)
    alert_route: consumer fail-closed abort + sentinel stderr in operator transcript
logs:
  where: meta-redacted finding lines to the invoking skill's transcript (no persistent store — CLI primitive)
  retention: transcript-scoped
discoverability_test:
  command: bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh && bash plugins/soleur/skills/operator-digest/test/redact-class-parity.test.sh
  expected_output: "Total: N pass, 0 fail" (both)
```

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Legal (CLO) — carried forward from brainstorm.

### Engineering (CTO)
**Status:** reviewed (carry-forward). **Assessment:** reject item-8 NFKC sync (bash can't NFKC) → drift-guard;
defer item 5 (fail-closed FP-trap); anchor item 6 (git-SHA collision) → the inline uppercase+digit predicate.

### Product (CPO)
**Status:** reviewed (carry-forward — satisfies `requires_cpo_signoff`). **Assessment:** items 1/3/6 reach
external egress → security-sentinel + gdpr-gate review bar; defer 4/5; #8 internal-only → standard bar.

### Legal (CLO)
**Status:** reviewed (carry-forward). **Assessment:** breach-surface weight 1 > 2 > 6; item 8 is a real
defensibility gap the guard closes by making divergence explicit + documented.

## GDPR / Compliance (Phase 2.7)

Trigger (b) fires (single-user-incident), but the change is **egress-reducing** (ADR-086 §Consequences: no new
processing / sub-processor / lawful-basis question — it lowers the Art. 33/34 breach surface). No schema /
migration / auth / API-route surface. `gdpr-gate` runs at PR-review with the diff; no Critical findings expected.

## Test Strategy

`redact-sentinel.test.sh` + `redact-class-parity.test.sh` (bash, `set -uo pipefail`, `assert_exit`/`assert_grep`,
`mktemp`+trap). Every secret fixture synthesized at runtime via `python3 -c … chr(0xXXXX)` — never committed
literal invisibles or secret tokens (`cq-test-fixtures-synthesized-only`, `cq-regex-unicode-separators-escape-only`;
AC6 enforces). Each item ships a positive evasion test proving the new pass catches what the base pass misses
(two-engine pattern where applicable) AND no-FP negatives. Parity (Test 9, new ⊇ old) and meta-redaction (Test 4b,
now asserted on the new reflow/decode emit paths) stay green every PR. Runner: `bash …/redact-sentinel.test.sh`
and `bash …/redact-class-parity.test.sh` (no ssh).

## Open Code-Review Overlap

**None.** Queried 61 open `code-review` issues; zero reference the edited files or ADR-086.

## Sharp Edges

- **`## User-Brand Impact` must stay filled** — empty/TODO/threshold-less fails `deepen-plan` Phase 4.6. Carried forward; do not blank.
- **DER long-form-only is a silent EC/Ed25519 miss** — the discriminator MUST handle short-form length + reject inner-`SEQUENCE` (cert), or the coverage claim is dishonest. Encrypted-PKCS#8 headerless is an accepted residual (record in ADR-086).
- **Decode-rescan must exclude IPv4/UUID/email** — running them over decoded high-entropy bytes manufactures FPs that fail-close legitimate writes.
- **Reflow needs an occurrence cap, not just a window cap** — `code-to-prd` scans attacker-controlled rendered text; prefix-flooded input without `_MAX_REFLOW_CANDIDATES` hangs a synchronous gate.
- **Per-candidate decode `try/except/continue`** — a single malformed base64 blob must not bubble to `main()`'s exit-2 catch-all and over-block the whole artifact.
- **Name-level drift-guard ≠ body parity** — the guard catches a *new class* silently un-scrubbed; intra-class regex-body drift (ERE↔`re`) is a documented non-goal, mitigated by the one-time PR-A body sync. Don't claim body parity.
- **Cloudflare boundary uses lookaround, not `\b`** — `-` is a non-word char; `\b[…]{40}\b` mis-anchors at token ends.
- **TDD not inverted** — the stray impl (`scratchpad/stray-impl-6045/`) is a design reference; write the failing evasion test first, then implement, every PR.

## Session Errors

1. **Subagent wrote a full implementation during the no-code phase (compounded).** A brainstorm
   `repo-research-analyst` spawn (tools `*`) wrote a 128-line test block AND a 165-line `redact-engine.py`
   implementation despite an explicit "do NOT write files" instruction; the test write was reverted at
   brainstorm-end, the engine write missed until the plan phase read the file. Reverted; preserved to
   `scratchpad/stray-impl-6045/`; operator chose the disciplined pipeline. **Lesson:** spawn read-only research
   with the `Explore` agent type (no write tools), not a full-tool agent + prose "don't write"; a single
   `git status` at spawn-completion doesn't catch a delayed write.
2. **Brainstorm "ERE↔re parity" framing was over-tight** — the sentinel is a pure-Python shim; parity is
   new⊇old-bash, not per-pattern ERE. **Lesson:** read the actual gate implementation before a paraphrased
   constraint bounds the option space.
3. **First plan draft's DER heuristic (from the stray design) was long-form-only + bare-SEQUENCE** — would
   miss EC/Ed25519 and FP on public certs. Caught by Kieran (P1) + fable advisor (P0) at plan-review, before
   any code shipped. **Lesson:** a plausible-looking stray implementation is not a verified one; the panel is
   load-bearing precisely because "the code looks right" is the trap at a single-user-incident threshold.
