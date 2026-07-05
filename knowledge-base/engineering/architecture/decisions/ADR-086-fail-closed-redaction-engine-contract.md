# ADR-086: Fail-closed redaction-engine contract — normalize-before-match, capped, cross-skill shared

- **Status:** Accepted
- **Date:** 2026-07-05
- **Issue:** [#5987](https://github.com/jikigai/soleur/issues/5987) (Wave 2 · FR4 of epic [#5983](https://github.com/jikigai/soleur/issues/5983))
- **Adapted from:** gstack `redact-engine` (clean-room; see [plugins/soleur/NOTICE](../../../../plugins/soleur/NOTICE))

## Context

`redact-sentinel.sh` is the pre-write redaction gate shared by three in-repo callers — `incident` (Phase 6 PIR draft, via `dry-run.sh`), `code-to-prd` (Layer 2 pre-write), and now `legal-generate` (Phase 2.5 pre-presentation). The former pure-bash `grep -oE` scanner matched raw bytes, so three adversary-model gaps sailed past it: (1) **Unicode-confusable evasion** — a secret typed with fullwidth compatibility characters, a zero-width/soft-hyphen/bidi character spliced mid-token, or an invalid UTF-8 byte (→ U+FFFD); (2) **unbounded input** — quantified email/UUID patterns over caller-supplied text with no length ceiling; (3) **no legal path** — the spec named a "legal redaction path" that did not exist.

## Decision

1. **Match over whole-string `NFKC(strip(text))`, not raw bytes.** The engine is now `redact-engine.py` (`cap → strip → NFKC → strip → confusable-fold → match → meta-redact`) behind a contract-preserving `redact-sentinel.sh` shim (argv, exit codes `{0,1,2}`, and the `at offset N: …***… matched pattern <class>` output shape are unchanged, so consumers need no change). Python 3, not bash: `unicodedata.normalize('NFKC', …)` is the canonical NFKC and bash cannot do it. **Whole-string** NFKC is correctness-critical — per-codepoint normalization is a fail-OPEN (a decomposed/combining sequence folds to an ASCII secret char only whole-string). Because the sentinel HALTS (never rewrites in place) and no consumer parses the offset, the offset-map-back-to-original is dropped; findings report the normalized offset.

2. **Fail closed on cannot-evaluate and on oversize.** Any state meaning "cannot evaluate" (bad arg, unreadable file, `python3` absent, engine crash, non-`{0,1,2}` code) → exit **2** (never 1, which would misreport "secrets found" and trap the incident redact loop). Input exceeding the byte cap (default 1 MiB; re-checked AFTER NFKC because NFKC can expand 1 codepoint → up to 18) → a **synthetic HIGH** finding + exit 1, with no per-class matching attempted. All non-zero exits are treated as fail-closed by every consumer.

3. **`re.ASCII` on every class.** Without it, Python's Unicode `\b`/`\w` would let a Unicode letter prefixed to a secret (`Юsk-ant-…`) break the boundary the bash C-locale `grep` caught — the port would *introduce* an evasion. POSIX `[^[:space:]]` is hand-translated to `\S`.

4. **`redact-sentinel.sh` is an accepted shared cross-skill dependency**, reached by relative path from `code-to-prd`, `incident`, and `legal-generate`. A shared neutral location was rejected as a larger blast radius; the existing cross-skill reference is recorded here as accepted debt.

## Scope boundary (named non-goals)

The engine defeats compatibility-char / invisible / bidi / control / format / invalid-byte / soft-hyphen / **prefix-homoglyph** (targeted `CONFUSABLE_MAP` fold of ~25 Cyrillic/Greek lookalikes) evasion. Invisible-character stripping is done by **Unicode category** (`Cc`/`Cf`/`Cs` + variation selectors + combining grapheme joiner, keeping meaningful whitespace) rather than a hand-picked codepoint list, so whole families (C0 controls, DEL, the Tags block U+E0000–E007F) are covered. It does **NOT** defeat: the full cross-script homoglyph space (Unicode TR39 skeleton — the residual gap is version-controlled by `redact-sentinel.test.sh` Test 12); whitespace / newline token-splitting (strip cannot remove meaningful whitespace — **this is the highest-probability *accidental* leak**, e.g. a secret a markdown/PDF renderer reflows across a line break); reversibly-encoded secrets (base64/hex/percent — no decode step); a headerless PEM key body; or **unprefixed / high-entropy secrets** (a bcrypt hash, a random DB password, an opaque session token — every pattern is vendor-prefix/format anchored; prefix-agnostic entropy detection is a separate high-false-positive approach). Each is a named non-goal bundled into one follow-up issue. `operator-digest/digest-scrub.sh` and `linear-fetch/redact-linear-urls.sh` keep their own tuned regex sets and are out of scope.

## Consequences

- **Availability shift (not "no change"):** `code-to-prd` Layer 2 was pure-bash and always ran; it now hard-depends on `python3` and fails closed (blocks all PRD writes) on a `python3`-less runner. Correct posture, but a green→red on such a runner is attributable here.
- **Egress-reducing:** strengthens existing gates with no new processing or sub-processor — it lowers the GDPR Art. 33/34 breach surface rather than widening it.
- The fail-closed contract is enforced by `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` (golden ERE↔`re` parity, oversize, no-python3, homoglyph-known-gap) and `code-to-prd.test.sh`, run by the plugin bash test suite on every PR touching these skills.
