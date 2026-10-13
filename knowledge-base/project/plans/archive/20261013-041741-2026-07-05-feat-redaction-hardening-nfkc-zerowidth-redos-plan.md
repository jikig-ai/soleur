---
date: 2026-07-05
type: feat
issue: 5987
epic: 5983
wave: "2 · FR4"
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adapted_from: gstack redact-engine
brainstorm: knowledge-base/project/brainstorms/2026-07-04-gstack-capability-adoption-brainstorm.md
plan_review: applied (architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer, fable advisor)
---

# 🔒 feat: Redaction hardening — NFKC + zero-width strip before matching, ReDoS-safe fail-closed input cap

Closes #5987 (Wave 2 · FR4 of epic #5983). **CLO gate: this ships before any feature that increases data egress.**

## Enhancement Summary

**Deepened on:** 2026-07-05. **Passes:** 4-agent plan-review (architecture-strategist, spec-flow-analyzer,
code-simplicity-reviewer, fable advisor) → applied; deepen halt-gates (4.6/4.7/4.8/4.9/4.5/4.55) → all pass;
authoritative local Python-semantics verification; security-sentinel adversary-model pass → applied.

**Load-bearing claims verified live (python3.12):**
- `re.ASCII` restores C-locale `\b`: `Ю`+`sk-ant-`+32 → Unicode `\b` **MISS**, `re.ASCII` **CATCH** (validates the port-safety P0).
- NFKC expansion: `NFKC('ﷺ' U+FDFA)` → **18 codepoints** (validates the post-NFKC cap re-check).
- `str.translate({ord:None})` deletes invisibles; invalid byte `\x80` → U+FFFD → stripped → `sk_live_live` reassembled (validates AC1b + STRIP).
- POSIX trap: `[^[:space:]]+` in Python `re` matches only `DOPPLER_TOKEN=d` (stops at `s`); `\S+` correct (validates the hand-translate).
- `dry-run.sh` fails-closed on any non-zero sentinel exit (contract preserved).

**Key security-review-driven changes (folded in):** completed the STRIP set (added U+2028/U+2029 —
a self-inconsistency with the repo's own `cq-regex-unicode-separators-escape-only` invariant — plus
U+00AD soft-hyphen and other invisible splitters); `strip → NFKC → strip` double-strip; tightened
meta-redaction to cap transcript entropy leak; reworded AC1 to end false-confidence + added a
version-controlled homoglyph known-gap test (Test 12); added Soleur crown-jewel classes
(Doppler/Slack) + broadened PEM/UUID/env_var (Phase 2b); named the previously-silent whitespace-split
and encoding non-goals.

## Overview

The Soleur redaction engine (`plugins/soleur/skills/incident/scripts/redact-sentinel.sh`)
is a pure-bash `grep -oE` scanner that halts a write when it finds one of 14 secret/PII
classes in draft text. It is consumed **fail-closed** by three in-repo callers today:

- **incident** — SKILL.md Phase 6 runs it on the unwritten PIR draft (pre-inline-emit AND pre-disk); `dry-run.sh` invokes it twice (per-field capture pass + on-draft pass).
- **code-to-prd** — `code-to-prd.sh` "Layer 2" runs it on the staged PRD before `cp` to disk; any non-zero exit aborts the write.

This issue closes three adversary-model gaps, adapted from gstack's `redact-engine`:

1. **Unicode-confusable evasion.** `grep -oE` matches raw bytes. A secret typed with
   fullwidth compatibility characters (`ｓｋ＿ｌｉｖｅ＿…` → NFKC → `sk_live_…`), with a zero-width
   character spliced mid-token (`sk_li‹ZWSP›ve_…`), or with an invalid UTF-8 byte spliced in
   (→ U+FFFD) sails past every regex. Fix: **strip zero-width/bidi/U+FFFD, then NFKC-normalize,
   BEFORE matching.**
2. **ReDoS / unbounded input.** The email/UUID classes are quantified patterns over
   caller-supplied text with no length ceiling. Fix: a **byte cap enforced BEFORE any regex
   runs** — *and re-checked after NFKC*, because NFKC can expand (e.g. one codepoint → 18);
   oversize input (raw or expanded) emits a **synthetic HIGH** finding and exits fail-closed.
3. **No legal path.** The brainstorm/spec/issue name a "legal redaction path," but
   `legal-generate` / `legal-audit` have **zero** redaction wiring today. Fix: wire
   `legal-generate` to the hardened engine, gating **before the draft is presented inline**
   (transcripts are write boundaries). `legal-audit` is deferred (see Non-Goals / decision-challenges).

**Chosen shape (pressure-tested by the plan-review panel + fable advisor):** promote the engine
to a single **Python 3 implementation** (`redact-engine.py`) that does
`cap → strip → NFKC (whole-string) → match → meta-redact`, and reduce `redact-sentinel.sh` to a
**thin shim** that execs it — **preserving the exact CLI contract** (argv, exit codes, and the
`at offset N: …*** … matched pattern <class>` output shape) so the existing consumers need **no
change**. Python 3 (not Node): inline `python3` is the established skill-script interpreter
precedent (community/flag-create/flag-set-role) and `unicodedata.normalize('NFKC', …)` is the
canonical NFKC. Bash genuinely cannot do NFKC, so the engine rewrite (not a bash+preprocessor
split) is the YAGNI answer — a Python-normalized tmpfile of secret-bearing text would be a *worse*
posture, and a pipe leaves offset/preview logic in bash operating on text whose offsets are meaningless.

**Whole-string NFKC, no offset-map-to-original.** Detection matches over a single whole-string
`NFKC(strip(original))` — this is the correctness-critical choice: per-codepoint normalization is
**not** equal to whole-string NFKC (a base+combining or decomposed sequence can fold to an ASCII
secret character only under whole-string NFKC), so a per-codepoint approach is a genuine
**fail-open**. The plan therefore drops the offset-map-back-to-original entirely (it was a reporting
nicety — the sentinel *halts*, it never rewrites in place, and no consumer parses the offset; the
current bash script already prints match-length in the "offset" slot). Findings report the
normalized-string offset (`m.start()`) with a preview sliced from the normalized match and
meta-redacted (never a full token). This reducing-scope decision vs the issue's literal
"offset-mapped back to original" is recorded as a User-Challenge in
`knowledge-base/project/specs/feat-one-shot-5987-redaction-hardening-nfkc-zerowidth-redos/decision-challenges.md`.

## Premise Validation (Phase 0.6)

- **#5987 OPEN, epic #5983 OPEN** — premise holds; not already closed.
- **`redact-sentinel.sh` exists** and **`code-to-prd.sh` delegates to it** at Layer 2
  (non-zero ⇒ abort); **`dry-run.sh`** also calls it — verified.
- **Brainstorm** cited correctly (item T2-7 / FR4, threshold `single-user incident`, CTO+CLO assessed).
- **STALE premise (reconciled):** brainstorm's "redaction (incident/code-to-prd/**legal** paths exist)"
  is inaccurate — legal has no wiring. "Apply to legal" ⇒ **build + wire**, not harden-existing.
- **Mechanism vs ADR corpus:** no prior/rejected ADR for normalize-before-match / cap / synthetic-HIGH;
  the fail-closed contract is a new cross-cutting invariant ⇒ a new ADR is a deliverable.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "legal redaction path exists" (harden it) | `legal-generate`/`legal-audit` SKILL.md have **no** redaction wiring | Reframe: **add** the gate to legal-generate, before inline presentation |
| Engine is "redact-sentinel.sh" | `code-to-prd.sh` **already delegates** to it; it is the shared engine | Harden the shared engine once (Python behind the `.sh` shim); consumers inherit it, contract-unchanged |
| "offset-mapped back to original" (gstack) | Soleur sentinel **halts**, never rewrites; per-codepoint offset-map is a fail-open + no consumer reads offset | Drop offset-to-original; whole-string NFKC; report normalized offset (User-Challenge, surfaced) |
| Two consumers | `dry-run.sh` is a **third** in-repo caller (exit-code only) | Add dry-run smoke to the contract baseline |
| Three named paths = whole surface | `digest-scrub.sh`, `redact-linear-urls.sh` are independent egress redactors with own regex sets | Scope out; follow-up issue (Non-Goals) |

## User-Brand Impact

- **If this lands broken, the user experiences:** a redaction-gated artifact (PIR, PRD sent to a
  buyer data-room, or a generated legal document) that contains a live secret/PII the engine failed
  to catch — a confusable/zero-width/invalid-byte-encoded token evaded matching, or an oversize
  draft was written **without** being scanned (fail-open).
- **If this leaks, the user's secrets / customer PII are exposed via:** a committed or
  externally-shared PRD/PIR/legal doc carrying an unredacted API key, JWT, customer email, or Stripe
  identifier — the GDPR Art. 33/34 breach surface the incident skill exists to bound.
- **Brand-survival threshold:** `single-user incident`. `requires_cpo_signoff: true` (CPO was not
  spawned at brainstorm — only CTO+CLO; CPO sign-off is required at plan time before `/work`).
  `user-impact-reviewer` runs at review time.
- **Residual leak vectors still evading after this PR (surfaced per the threshold; each an ADR-086
  named non-goal + follow-up-issue item):**
  - **Whitespace / newline token-splitting** — the *highest-probability accidental* leak: strip cannot
    remove meaningful whitespace, so a secret a markdown/PDF renderer reflows across a line break is
    NOT caught. Follow-up: whitespace-collapse-and-re-scan second pass.
  - **Cross-script homoglyphs outside `CONFUSABLE_MAP`** (full TR39 skeleton) — version-controlled by
    Test 12; and **unprefixed / high-entropy secrets** (no vendor prefix to anchor on).
- **Availability cost (fail-closed, never a leak):** code-to-prd Layer 2 was pure-bash and always ran;
  it now hard-depends on `python3` and *blocks* all PRD writes (exit 2) on a `python3`-less runner. CI
  and operator machines have `python3` (precedent skills already depend on it); the posture is correct.

## Implementation Phases

### Phase 0 — Preconditions (verify before writing code)

1. **Interpreter + NFKC:** `python3 -c "import unicodedata; assert unicodedata.normalize('NFKC','ｓｋ_ｌｉｖｅ_1234')=='sk_live_1234'"`.
   Confirm python3 on PATH in CI (precedent skills already depend on it). The shim **fails closed
   (exit 2, never 0)** if python3 is absent.
2. **ReDoS micro-benchmark — WHOLE pipeline on a max-expansion payload.** Time
   `cap→strip→NFKC→match` on a 1 MiB input of high-NFKC-expansion codepoints (e.g. repeated
   U+FDFA `ﷺ` → 18 cp) AND an email/UUID storm. Confirm wall-time < ~1 s. If not, lower
   `REDACT_MAX_INPUT_BYTES` and re-measure. (ASCII-regex-only timing is insufficient — it exercises
   neither the expansion nor the normalize cost.)
3. **Contract baseline GREEN on `main`:** `redact-sentinel.test.sh`, `code-to-prd.test.sh`, **and a
   `dry-run.sh` smoke invocation** — so any post-change red is attributable.

### Phase 1 (RED) — Failing tests

File: `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` (extend).
Generate all confusable/oversize/invalid-byte inputs **at test runtime** via `python3 -c`/`printf`
with `\uXXXX` escapes — never commit literal invisibles (Edit-tool mangles U+2028/2029 per
`cq-regex-unicode-separators-escape-only`; invisibles are unreviewable). All tokens synthesized
(`cq-test-fixtures-synthesized-only`).

- **Test 5 — compatibility-confusable + invisible-splitter evasion (AC1):** JWT split by ZWSP **and**
  by U+00AD (soft hyphen) and U+2028; a fullwidth Stripe key. Assert (a) raw `grep -oE '<old pattern>'`
  **misses**; (b) engine **exits 1** with the correct classes. (The soft-hyphen/U+2028 vectors guard the
  STRIP-set completion — plan v1 omitted them.)
- **Test 12 — cross-script homoglyph KNOWN-GAP (AC1 honesty):** a Cyrillic-lookalike-prefixed secret
  whose glyphs are NOT in `CONFUSABLE_MAP` asserts the CURRENT behavior (exit 0 = not caught), so the
  residual fail-open is version-controlled and visible rather than silent. A `CONFUSABLE_MAP`-covered
  prefix (`ѕk_live_…`) asserts exit 1 (the targeted fold works).
- **Test 6 — oversize → synthetic HIGH (AC2):** file of `REDACT_MAX_INPUT_BYTES + 1` bytes → exit 1,
  distinct synthetic-HIGH marker, no per-class matching attempted.
- **Test 6b — expansion bomb (AC2):** raw < cap but NFKC-expanded > cap → synthetic HIGH, exit 1
  (proves the post-NFKC re-check).
- **Test 7 — invalid-UTF-8 splice (AC1b):** a synthesized secret with an invalid byte spliced in
  (→ U+FFFD) is **caught** (exit 1) after the strip.
- **Test 8 — no false positives:** hand-redacted negative baseline still **exits 0** after
  normalization (normalization must not manufacture matches).
- **Test 9 — golden ERE↔`re` parity (AC3):** capture the OLD bash engine's per-class hit set on
  `positive-corpus.md` (+ a near-miss negative set) as a golden file; assert the NEW engine
  reproduces the identical class-hit set. **Runs BEFORE normalization lands** so parity drift and
  normalization bugs stay separable.
- **Test 10 — fail-closed on no-python3 (AC4):** shim invoked with `python3` shadowed off `PATH`
  exits **2** (not 0, not 1) with the fail-closed message.
- **Test 11 — legal-generate gate blocks (AC5):** seed a draft `mktemp` with a synthesized secret;
  assert the sentinel invocation the legal-generate flow uses exits non-zero (⇒ no inline present, no write).
- **Preserve Tests 1–4** (contract: 14 classes trip; invalid-arg exits 2). **Test 4 format regex
  tightens** to the new capped reveal: `at offset [0-9]+: .{0,4}\*\*\*(.{0,4})? matched pattern [A-Za-z_]+`
  (was `.{8}\*\*\*.{8}` — the 8+8 reveal leaked ~50% of a fixed-prefix key's entropy into the transcript).

### Phase 2 (GREEN) — The hardened engine

File to create: `plugins/soleur/skills/incident/scripts/redact-engine.py`.
File to edit: `plugins/soleur/skills/incident/scripts/redact-sentinel.sh` (→ thin shim).

```python
#!/usr/bin/env python3
# Hardened redaction engine (#5987). Contract preserved:
#   argv[1]=path; exit 0 clean / 1 redaction-needed (incl synthetic HIGH) / 2 cannot-evaluate.
#   stdout: "at offset <normOffset>: <prefix>***<suffix> matched pattern <class>"
import os, re, sys, unicodedata

MAX = int(os.environ.get("REDACT_MAX_INPUT_BYTES", str(1024 * 1024)))  # 1 MiB

# Invisible / break-rendering / bidi separators + replacement char. NFKC does NOT remove these.
# INCLUDES U+2028/U+2029 (line/para sep) per the repo's own cq-regex-unicode-separators-escape-only
# invariant — omitting them (as plan v1 did) is a self-inconsistency + a live splitter evasion.
# str.translate map; keys are ordinals (escapes-only per that rule).
STRIP = {c: None for c in (
    0x200B,0x200C,0x200D,0x2060,0xFEFF,0x180E,           # zero-width
    0x200E,0x200F,0x202A,0x202B,0x202C,0x202D,0x202E,0x2066,0x2067,0x2068,0x2069,0x061C,  # bidi
    0x00AD,                                              # soft hyphen (renders invisibly, splits tokens)
    0x2028,0x2029,                                       # line / paragraph separators
    0x115F,0x1160,0x3164,0x17B4,0x17B5,                  # Hangul/Khmer fillers (render as nothing)
    0xFFF9,0xFFFA,0xFFFB,                                # interlinear annotation
    0xFFFD)}                                             # decode-replacement (invalid-byte splice)

# All 14 classes ported 1:1 from redact-sentinel.sh, compiled with re.ASCII so \b/\w/\s keep
# grep's C-locale (ASCII) semantics — WITHOUT re.ASCII, Python's Unicode \b makes "Юsk-ant-…"
# a MISS the bash version catches (a NEW evasion). POSIX [^[:space:]] hand-translated to \S.
F = re.ASCII
PATTERNS = [                                   # all compiled with F=re.ASCII
    ("JWT", re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}", F)),
    ("email", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b", F)),
    # … the 12 remaining FR3 classes ported 1:1 (env_var uses \S+ NOT [^[:space:]]+), plus
    #   deepen-security broadenings (see Phase 2b): UUID → [0-9A-Fa-f]; PEM header → [A-Z0-9 ]*PRIVATE KEY;
    #   new Soleur crown-jewel classes doppler_token (dp\.(st|pt)\.…), slack_token (xox[baprs]-…);
    #   env_var vendor list += HETZNER|FLAGSMITH|RESEND|TAILSCALE.
]
# CONFUSABLE_MAP: targeted ASCII-lookalike fold for ~25 Cyrillic/Greek codepoints that appear in
# secret PREFIXES (ѕ→s е→e р→p с→c а→a о→o k l i v t …). Cheap partial cross-script coverage so
# AC1 is honest; full TR39 skeleton stays a non-goal (residual gap version-controlled by Test 12).

def scan(path):
    if not os.path.isfile(path) or not os.access(path, os.R_OK):
        sys.stderr.write(f"redact-engine: file not readable: {path}\n"); return 2
    raw = open(path, "rb").read()
    if len(raw) > MAX:
        print(f"SYNTHETIC HIGH: input exceeds {MAX} bytes ({len(raw)}) — fail closed"); return 1
    stripped = raw.decode("utf-8", "replace").translate(STRIP)
    # strip → NFKC → strip again: NFKC decomposition can EMIT combining/zero-width chars, re-opening
    # a splitter after the first strip ran. Second strip is idempotent. Then targeted confusable fold.
    norm = unicodedata.normalize("NFKC", stripped).translate(STRIP).translate(CONFUSABLE_MAP)
    if len(norm.encode("utf-8")) > MAX:  # post-NFKC expansion re-check (NFKC can expand 1→18 cp)
        print(f"SYNTHETIC HIGH: normalized input exceeds {MAX} bytes — fail closed"); return 1
    hits = 0
    for name, rx in PATTERNS:
        for m in rx.finditer(norm):
            t = m.group(0)  # tightened meta-redaction — cap revealed entropy (finding lines hit the transcript)
            prev = f"{t[:4]}***{t[-4:]}" if len(t) > 24 else (f"{t[:4]}***" if len(t) > 12 else "***")
            print(f"at offset {m.start()}: {prev} matched pattern {name}"); hits += 1
    return 1 if hits else 0

def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: redact-engine.py <path>\n"); return 2
    try:
        return scan(sys.argv[1])
    except Exception as e:                       # any engine crash = cannot-evaluate, fail closed
        sys.stderr.write(f"redact-engine: internal error: {e}\n"); return 2

if __name__ == "__main__": sys.exit(main())
```

`redact-sentinel.sh` shim:

```bash
#!/usr/bin/env bash
# Thin shim (#5987): engine is redact-engine.py. Contract preserved (argv, output shape).
# Exit is NORMALIZED to {0,1,2}: any engine-cannot-run/unexpected code → 2 (cannot-evaluate),
# which all consumers already treat as fail-closed (code-to-prd:540, incident:221, dry-run any-nonzero).
# python3 absent → 2 (NOT 1: exit 1 = "matches found" would give a false "secrets found" message
# and trap the incident operator in an unsatisfiable redact-until-0 loop).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "redact-sentinel: python3 not found — failing closed." >&2; exit 2; }
python3 "${DIR}/redact-engine.py" "$@"; rc=$?
case "$rc" in 0|1|2) exit "$rc";; *) echo "redact-sentinel: engine exit ${rc} normalized to 2." >&2; exit 2;; esac
```

**Fail-closed is independent of any offset math** (there is no offset map). Exit code depends only
on `hits` over the whole-string-normalized text.

### Phase 2b — Class-breadth + confusable additions (from deepen security review)

File: `redact-engine.py` (PATTERNS + CONFUSABLE_MAP) and `positive-corpus.md` (new synthesized fixtures).

Folded in because this PR is the **pre-egress gate** and these are one-line, low-false-positive, and
target the modal Soleur secret. Golden-parity (Test 9) is old-vs-new on the **existing** corpus; new
classes are **additive** — add a synthesized fixture per new class so Test 2 still asserts "every class trips".

- **New classes (distinctive prefixes, low FP):** `doppler_token` (`\bdp\.(st|pt)\.[A-Za-z0-9._-]{16,}`),
  `slack_token` (`\bxox[baprs]-[A-Za-z0-9-]{10,}`).
- **Broaden existing:** `env_var` vendor list `+= HETZNER|FLAGSMITH|RESEND|TAILSCALE`; PEM header
  `-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----` (catches `ENCRYPTED`/`SSH2`); UUID `[0-9A-Fa-f]` (uppercase —
  a latent lowercase-only gap in the bash baseline, fixed deliberately; verify additive vs Test 9).
- **`CONFUSABLE_MAP`:** targeted ~25-codepoint Cyrillic/Greek→ASCII fold for secret-prefix lookalikes
  (closes the prefix-homoglyph vector so AC1 is honest). Full TR39 skeleton remains a non-goal; Test 12
  version-controls what is still not folded. Redaction false-positives on legit Cyrillic prose are the
  acceptable-asymmetry side (operator iterates) per the PII-scrubber learning.
- **Deferred to follow-up (higher FP / real detection-design):** Cloudflare bare 40-char token,
  prefix-agnostic high-entropy detection, base64/hex-decode-and-re-scan, headerless-PEM-body heuristic.

### Phase 3 — Wire the legal path (build + gate)

File to edit: `plugins/soleur/skills/legal-generate/SKILL.md`.

- **legal-generate Phase 3 (pre-*presentation*, BLOCKING):** write the generated draft to a
  `mktemp`, run `bash ../incident/scripts/redact-sentinel.sh <draft-tmpfile>` **before** the
  `AskUserQuestion` Accept/Edit/Reject presentation (SKILL.md:54) — because presenting inline is a
  transcript write boundary (incident SKILL.md:223 SpecFlow-Critical-#2). Exit 0 → present → on
  Accept, write. Exit 1 → print finding lines, revise/redact, re-run until 0. Exit 2 → halt (skill
  bug / engine cannot run). No un-scanned draft ever crosses the transcript or disk.
- Cite the shared owner (`incident/scripts/redact-sentinel.sh`) with the correct relative path.
- **legal-audit: deferred** to the follow-up issue (its findings quote already-committed docs — no
  new egress; gating it correctly would require scanning every inline surface it emits, not just the
  findings buffer). Recorded as a User-Challenge (scope vs the issue's "paths" plural).

### Phase 4 — Docs, NOTICE, ADR

Files: `plugins/soleur/skills/incident/SKILL.md` (note engine is now Python behind the shim;
contract unchanged), NOTICE stanza attributing the gstack `redact-engine` adaptation (clean-room),
and ADR-086 (below, minimal).

## Acceptance Criteria (all pre-merge — no operator post-merge steps)

- [ ] **AC1 (compatibility-confusable + invisible-splitter evasion):** Test 5 GREEN — JWT split by
      ZWSP/U+00AD/U+2028 + fullwidth Stripe key missed by raw regex, caught by engine. **AC1 is scoped to
      NFKC-foldable + stripped + CONFUSABLE_MAP-covered vectors** — cross-script homoglyphs outside the
      map are a version-controlled known gap (Test 12), NOT claimed as covered. (Reworded from "confusable
      evasion" after deepen review flagged false-confidence: fullwidth-only Test 5 would go green while
      un-folded homoglyphs stay fail-open.)
- [ ] **AC1b (invalid-UTF-8 splice):** Test 7 GREEN — a U+FFFD-spliced secret is caught after strip.
- [ ] **AC2 (oversize → synthetic HIGH → caller blocks):** Tests 6 + 6b GREEN — raw-oversize AND
      NFKC-expansion-oversize both exit 1 with a synthetic-HIGH line and skip per-class matching;
      a code-to-prd integration assertion shows Layer 2 aborts the write (no PRD on disk).
- [ ] **AC3 (contract + parity preserved):** Tests 1–4 GREEN (14 classes, exit-2 on bad arg,
      output-format regex); **Test 9 golden ERE↔`re` parity** GREEN; `code-to-prd.test.sh` GREEN.
- [ ] **AC4 (fail-closed on no-python3 = exit 2):** Test 10 GREEN — shim exits **2** with `python3`
      off PATH; the shim normalizes any non-{0,1,2} engine code to 2.
- [ ] **AC5 (legal gate is executable, not prose-only):** Test 11 GREEN — a synthesized secret in a
      legal draft `mktemp` makes the sentinel exit non-zero (⇒ no inline present, no write); and
      `grep -q 'redact-sentinel.sh' legal-generate/SKILL.md` with the exit-0/1/2 block placed
      **before** the presentation step.
- [ ] **AC6 (no literal invisibles committed):** `git grep -nP '[\x{200b}\x{200c}\x{200d}\x{2060}\x{feff}\x{202a}-\x{202e}\x{fffd}]' plugins/soleur/skills/incident plugins/soleur/skills/legal-generate`
      returns nothing (all expressed as `\uXXXX`/ordinals; fixtures runtime-generated).
- [ ] **AC7 (no false positives + `re.ASCII` semantics):** Test 8 GREEN (clean baseline exits 0);
      a Unicode-letter-prefixed secret (`Юsk-ant-…`) is still caught (guards the `re.ASCII` port).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` bodies reference none of `redact-sentinel`,
`code-to-prd`, `legal-generate`, `incident/scripts`, `positive-corpus`.

## Domain Review

**Domains relevant:** Engineering, Legal (carried forward from brainstorm `## Domain Assessments`;
no fresh spawn). Product: **NONE** — no UI-surface file (scripts + SKILL.md + test + ADR only).

### Engineering (CTO)
**Status:** reviewed (carry-forward + plan-review panel). **Assessment:** highest-priority Wave 2
item; must precede egress. Shared-surface risk mitigated by contract-preserving shim (consumers
untouched) and fail-closed-on-missing-interpreter. Plan-review added: `re.ASCII` port safety,
whole-string NFKC (fail-open fix), exit-2 normalization, post-NFKC cap re-check.

### Legal (CLO)
**Status:** reviewed (carry-forward). **GDPR gate (2.7) — advisory:** no regulated-data surface per
canonical regex (no schema/migration/auth/API/`.sql`); the change is **egress-reducing** (strengthens
existing gates, no new processing/sub-processor) ⇒ lowers Art. 33/34 breach surface. No Critical
findings expected; fresh agent spawn not warranted.

### Product/UX Gate
N/A — Product NONE.

## Architecture Decision (ADR / C4)

### ADR
**Create ADR-086 (provisional — 085 highest on `main`; `/ship`'s ordinal-collision gate re-verifies).**
Minimal (5–8 lines): the **fail-closed redaction-engine contract** — matching occurs over
whole-string `NFKC(strip(text))`; oversize (raw or NFKC-expanded) or a non-running engine → non-zero
exit → caller blocks; matching runs over `strip → NFKC → strip → CONFUSABLE_MAP` (double-strip because
NFKC can emit combining/zero-width chars); and the **scope boundary** — defeats compatibility-char /
zero-width / bidi / invalid-byte / soft-hyphen / prefix-homoglyph evasion but **NOT** the full
cross-script homoglyph space (TR39 skeleton), whitespace-splitting, or reversibly-encoded secrets —
each a named non-goal, with the residual homoglyph gap version-controlled by Test 12. Records that `redact-sentinel.sh` is
now a **shared cross-skill dependency** reached by relative path from three skills (code-to-prd,
incident, legal-generate) — accepted debt vs a shared-location move.

### C4 views
**No C4 impact** — all three model files (`diagrams/{model.c4,views.c4,spec.c4}`) checked: the
redaction engine is internal plugin-CLI tooling, not a modeled web-platform runtime element; no
external actor/system/data-store/access-relationship changes (`grep -niE 'redact|sentinel|incident|prd|pii'`
returns only unrelated Doppler secret-injection edges).

## Observability

Synchronous CLI tool (no service/Sentry surface); observability = exit-code + stderr + CI test suite.

```yaml
liveness_signal:
  what: redact-sentinel.test.sh (incl. golden parity) + code-to-prd.test.sh assert engine behavior
  cadence: every PR touching plugins/soleur/skills/{incident,code-to-prd,legal-generate}
  alert_target: CI red → PR blocked (branch protection)
  configured_in: existing plugin test workflow (bash .test.sh suites)
error_reporting:
  destination: process stderr + exit code (0 clean / 1 redaction-needed / 2 cannot-evaluate)
  fail_loud: true  # non-zero halts the caller; no path swallows a match to exit 0; crashes → 2
failure_modes:
  - mode: python3 absent / engine crash / non-{0,1,2} code
    detection: shim guard + normalization; Test 10 (AC4)
    alert_route: exit 2 (fail closed) → caller aborts
  - mode: input exceeds cap (raw OR NFKC-expanded)
    detection: pre- and post-NFKC byte check; Tests 6 + 6b (AC2)
    alert_route: synthetic-HIGH line + exit 1 → caller aborts
  - mode: confusable / zero-width / invalid-byte evades matching
    detection: Tests 5 + 7 (AC1/AC1b) go RED on regression
    alert_route: CI red → PR blocked
  - mode: ERE→re port narrows a class (e.g. env_var [:space:] mistranslation, Unicode \b)
    detection: Test 9 golden parity + Test 8 re.ASCII guard (AC3/AC7)
    alert_route: CI red → PR blocked
logs:
  where: stderr (surfaced into the operator transcript when run in-skill)
  retention: none (ephemeral synchronous CLI)
discoverability_test:
  command: bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh
  expected_output: "Total: N pass, 0 fail"
```

## Risks & Mitigations / Sharp Edges

- **`re.ASCII` is load-bearing.** Without it, Python's Unicode `\b`/`\w` lets any Unicode letter
  prefixed to a secret (`Юsk-ant-…`) break the boundary the bash C-locale grep caught — the port
  would *introduce* a Unicode evasion. Compile all 14 classes with `re.ASCII`; AC7 guards it.
- **POSIX classes don't exist in Python `re`.** `[^[:space:]]` copied literally becomes the set
  `{[,:,s,p,a,c,e,]}` — silently narrows `env_var` while Test 2 stays green. Hand-translate to `\S`;
  Test 9 golden parity guards the full 14-class port.
- **Whole-string NFKC, not per-codepoint.** Per-codepoint-then-join ≠ `NFKC(join)` and is a
  fail-open (a decomposed/combining sequence folds to an ASCII secret char only whole-string). Detection
  uses one `unicodedata.normalize("NFKC", …)` call over the fully-stripped string. This also deletes
  the offset-map machinery entirely.
- **ReDoS cap must bound the POST-NFKC string.** NFKC expands (1 cp → up to 18); capping only `raw`
  re-opens the latency surface. Re-check `len(norm.encode())` after normalization; Phase 0.2
  benchmarks the whole pipeline on an expansion payload.
- **Exit-code semantics:** synthetic HIGH and real matches → **1**; anything meaning "cannot
  evaluate" (bad arg, unreadable file, no python3, engine crash, non-{0,1,2}) → **2**. Exit 1 for a
  non-running engine would misreport as "secrets found" and trap the incident redact-loop.
- **Availability shift (not "no change"):** code-to-prd Layer 2 was pure-bash and always ran; it now
  hard-depends on python3 and fails-closed (blocks all PRD writes) on a python3-less runner — correct
  posture, but a green→red on such a runner is attributable to this.
- **Edit-tool mangles literal U+2028/U+2029** (`cq-regex-unicode-separators-escape-only`): the STRIP
  set + any separator in a regex use ordinals/`\uXXXX`; AC1/AC1b/AC6 fixtures are runtime-generated.
- **Meta-redaction never emits a full token** (closes the former bash ≤16-char full-token leak);
  the `.8***.8` shape for long tokens keeps Test 4 green.
- **`digest-scrub.sh` is NOT auto-updated** (own tuned regex set) — Non-Goal + follow-up.

## Alternatives Considered

| Alternative | Why not chosen |
|---|---|
| **Node engine** | Available but inline `python3` is the established skill-script precedent; `unicodedata` is canonical NFKC. |
| **Bash grep + Python *preprocessor* only** | A normalized tmpfile of secret-bearing text is a worse posture; a pipe strands offset/preview in bash on meaningless offsets; keeps grep's non-portable `\b`. Single in-memory Python process is simpler AND safer. |
| **Keep offset-map-to-original (per-codepoint)** | Fail-open (per-codepoint ≠ whole-string NFKC) + ~15 lines of incidental complexity for a nicety no consumer reads. Dropped; User-Challenge surfaced. |
| **Wire legal-audit too** | Redacts already-committed content (no un-leak); correct gating needs every inline surface (escalation H3, banner), not just findings buffer. Deferred to follow-up. |
| **Shared neutral engine location** | Cleaner ownership but larger blast radius (code-to-prd path + SKILL + NOTICE); existing cross-skill reference works. Recorded as accepted debt in ADR. |

## Test Scenarios

1. Positive-corpus (14 classes) fully trips (regression) + golden parity vs old engine (Test 9).
2. Confusable JWT (ZWSP) + fullwidth Stripe (AC1); invalid-byte splice (AC1b); `Юsk-ant-…` still caught (AC7).
3. Oversize (raw + NFKC-expansion) → synthetic HIGH → code-to-prd Layer 2 aborts (AC2).
4. Invalid/missing arg → exit 2; `python3` off PATH → exit 2 (AC4).
5. Clean hand-redacted PIR → exit 0 (AC7).
6. legal-generate: secret-bearing draft blocks before inline presentation (AC5).
7. **Review-time (learning 2026-05-14):** spawn `security-sentinel` prompted to "name redaction-bypass
   classes this engine MISSES — homoglyphs, unprefixed tokens, variable-length UTF-8 — do not restate
   the class set."

## Non-Goals (explicitly named — "not listed" must not read as "handled")

- **Full cross-script homoglyph** normalization (Unicode TR39 skeleton) — only the targeted
  `CONFUSABLE_MAP` prefix fold ships; the residual gap is version-controlled by Test 12. ADR boundary.
- **Whitespace / newline token-splitting** (a secret split across two lines, or with a space/tab/CR mid-token):
  strip cannot remove whitespace (it is meaningful in `env_var` values and prose), so a line-wrapped
  secret that a PDF/markdown renderer reflows is NOT caught. This is the most likely *accidental* leak —
  follow-up: a "collapse whitespace inside a high-entropy candidate run and re-scan" second pass.
- **Reversibly-encoded secrets** (base64/hex/percent-encoded, k8s Secret manifests) — the engine is a
  literal-shape matcher with no decode step. Follow-up: base64-decode candidate blobs and re-run the prefix classes.
- **Headerless PEM key body** — the class anchors on the `BEGIN … PRIVATE KEY` header; a base64 key body
  with the header stripped is not scanned. Follow-up: long-base64-run heuristic.
- **legal-audit** redaction wiring — deferred (already-committed content; multi-surface gating cost). User-Challenge.
- Hardening `operator-digest/digest-scrub.sh` + `linear-fetch/redact-linear-urls.sh`.
- In-place redaction/rewrite of the original (Soleur halts; only gstack rewrites).
- Offset-mapping back to the original text (User-Challenge; see decision-challenges.md).
- IPv6.

**One follow-up issue** (per `wg-when-deferring-a-capability-create-a`) bundles: legal-audit gating,
digest-scrub NFKC/class-sync, whitespace-collapse re-scan, base64-decode re-scan, headerless-PEM-body
heuristic, Cloudflare bare-token + prefix-agnostic detection, and full TR39.
