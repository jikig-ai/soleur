# ADR-095: Fail-closed redaction-engine contract — normalize-before-match, capped, cross-skill shared

- **Status:** Accepted
- **Date:** 2026-07-05
- **Issue:** [#5987](https://github.com/jikigai/soleur/issues/5987) (Wave 2 · FR4 of epic [#5983](https://github.com/jikigai/soleur/issues/5983))
- **Adapted from:** gstack `redact-engine` (clean-room; see [plugins/soleur/NOTICE](../../../../plugins/soleur/NOTICE))
- **Ordinal note:** Ordinal chain: 086 (original — one of three PRs that concurrently claimed 086 on 2026-07-05) → 093 (assigned in the #6054 collision cleanup) → **095** (bumped again mid-pipeline when a sibling ADR landed 093 on main before this merged). Moved to the next-free ordinal each time.

## Context

`redact-sentinel.sh` is the pre-write redaction gate shared by three in-repo callers — `incident` (Phase 6 PIR draft, via `dry-run.sh`), `code-to-prd` (Layer 2 pre-write), and now `legal-generate` (Phase 2.5 pre-presentation). The former pure-bash `grep -oE` scanner matched raw bytes, so three adversary-model gaps sailed past it: (1) **Unicode-confusable evasion** — a secret typed with fullwidth compatibility characters, a zero-width/soft-hyphen/bidi character spliced mid-token, or an invalid UTF-8 byte (→ U+FFFD); (2) **unbounded input** — quantified email/UUID patterns over caller-supplied text with no length ceiling; (3) **no legal path** — the spec named a "legal redaction path" that did not exist.

## Decision

1. **Match over whole-string `NFKC(strip(text))`, not raw bytes.** The engine is now `redact-engine.py` (`cap → strip → NFKC → strip → confusable-fold → match → meta-redact`) behind a contract-preserving `redact-sentinel.sh` shim (argv, exit codes `{0,1,2}`, and the `at offset N: …***… matched pattern <class>` output shape are unchanged, so consumers need no change). Python 3, not bash: `unicodedata.normalize('NFKC', …)` is the canonical NFKC and bash cannot do it. **Whole-string** NFKC is correctness-critical — per-codepoint normalization is a fail-OPEN (a decomposed/combining sequence folds to an ASCII secret char only whole-string). Because the sentinel HALTS (never rewrites in place) and no consumer parses the offset, the offset-map-back-to-original is dropped; findings report the normalized offset.

2. **Fail closed on cannot-evaluate and on oversize.** Any state meaning "cannot evaluate" (bad arg, unreadable file, `python3` absent, engine crash, non-`{0,1,2}` code) → exit **2** (never 1, which would misreport "secrets found" and trap the incident redact loop). Input exceeding the byte cap (default 1 MiB; re-checked AFTER NFKC because NFKC can expand 1 codepoint → up to 18) → a **synthetic HIGH** finding + exit 1, with no per-class matching attempted. All non-zero exits are treated as fail-closed by every consumer.

3. **`re.ASCII` on every class.** Without it, Python's Unicode `\b`/`\w` would let a Unicode letter prefixed to a secret (`Юsk-ant-…`) break the boundary the bash C-locale `grep` caught — the port would *introduce* an evasion. POSIX `[^[:space:]]` is hand-translated to `\S`.

4. **`redact-sentinel.sh` is an accepted shared cross-skill dependency**, reached by relative path from `code-to-prd`, `incident`, and `legal-generate`. A shared neutral location was rejected as a larger blast radius; the existing cross-skill reference is recorded here as accepted debt.

## Scope boundary (named non-goals)

The engine defeats compatibility-char / invisible / bidi / control / format / invalid-byte / soft-hyphen / **prefix-homoglyph** (targeted `CONFUSABLE_MAP` fold of ~25 Cyrillic/Greek lookalikes) evasion. Invisible-character stripping is done by **Unicode category** (`Cc`/`Cf`/`Cs` + variation selectors + combining grapheme joiner, keeping meaningful whitespace) rather than a hand-picked codepoint list, so whole families (C0 controls, DEL, the Tags block U+E0000–E007F) are covered. It does **NOT** defeat: the full cross-script homoglyph space (Unicode TR39 skeleton — the residual gap is version-controlled by `redact-sentinel.test.sh` Test 12); whitespace / newline token-splitting (strip cannot remove meaningful whitespace — **this is the highest-probability *accidental* leak**, e.g. a secret a markdown/PDF renderer reflows across a line break); reversibly-encoded secrets (base64/hex/percent — no decode step); a headerless PEM key body; or **unprefixed / high-entropy secrets** (a bcrypt hash, a random DB password, an opaque session token — every pattern is vendor-prefix/format anchored; prefix-agnostic entropy detection is a separate high-false-positive approach). Each is a named non-goal bundled into one follow-up issue. `operator-digest/digest-scrub.sh` and `linear-fetch/redact-linear-urls.sh` keep their own tuned regex sets and are out of scope.

### Amended 2026-07-06 (#6045 PRs A–C) — four non-goals now covered

The non-goal paragraph above is **preserved verbatim** as the breach-forensics record of the engine's coverage as of #6032 (2026-07-05) — do not delete it (a GDPR Art. 33/34 forensic answer to "was X covered as of date Y?"). As of #6045 the following are **now defeated** (see `redact-sentinel.test.sh` Tests 13–16 and `plugins/soleur/test/redact-class-parity.test.sh`):

- **Whitespace / newline token-splitting** (item 1) — a bounded-rejoin re-scan (`_scan_reflow`): for each distinctive-prefix class, rejoin the token across ≤4 whitespace runs and re-test. The bound admits renderer reflow (a few splits) and rejects prose (a run every few chars), so `dp.st.`+prose does not manufacture a match.
- **Reversibly-encoded secrets** (item 2) — base64 (incl. 64-char-wrapped **block assembly** for k8s Secret `data:` values) / hex / percent decode-and-rescan (`_scan_encoded`), re-running only the **anchored** secret classes over decoded bytes (`IPv4`/`UUID`/`email`/`cloudflare_token` excluded — weakly anchored, they manufacture FPs on decoded high-entropy bytes). Per-candidate decode errors are swallowed (never bubble to the exit-2 catch-all).
- **Headerless PEM key body** (item 3) — a **private-key DER discriminator**: an outer `SEQUENCE` whose first inner element is an `INTEGER` version (PKCS#1 / SEC1 / PKCS#8), handling **both** short-form (EC ~118 B, Ed25519 ~48–85 B) and long-form (RSA ≥128 B) length. A public cert / SPKI / `EncryptedPrivateKeyInfo` opens with an inner `SEQUENCE` and is deliberately **NOT** flagged (public/encrypted material — flagging fail-closes a legitimate write).
- **Bare Cloudflare 40-char token** (item 6) — a length-anchored class gated by an uppercase-AND-digit **anti-SHA predicate** (a 40-char lowercase-hex git SHA and 40-char kebab prose are rejected). Accepted trade: ~0.1 % of real tokens (lacking a digit or uppercase) are missed, and a 40-char base64 blob of a ~30-byte value can false-positive — an accepted cost of a prefixless class.

**Still non-goals (unchanged):** the full cross-script TR39 homoglyph skeleton (item 4) and a prefix-agnostic entropy detector (item 5) → deferred to **#6104** (needs-evidence: a real leak + a labeled corpus + a satisfiable fail-closed FP rate). `legal-audit` multi-surface gating (item 7, UC2) → **#6105**.

**Residual detection gaps recorded at #6045 review (single-user-incident threshold) — the coverage claims above are honest about these:**

- **`EncryptedPrivateKeyInfo` headerless bodies** — uncovered (inner-`SEQUENCE` shape indistinguishable from a cert without decrypting).
- **Multiply-encoded secrets** (item 2) — `_scan_encoded` decodes **one** level only (base64-of-base64, hex-of-base64, etc. survive). Single-level was the deliberate v1 scope (YAGNI); recursion is deferred until evidence of a real double-encoded leak.
- **Reflow across > `_MAX_REFLOW_SPLITS` (4) whitespace runs** (item 1) — a token wrapped into ≥6 fragments (a very long token in a narrow PDF/markdown column, or an adversarial ≥5-space insertion) is not rejoined. The ≤4 bound is the false-positive defense (prose has a whitespace run every few chars); raising it re-admits prose FPs.
- **Whitespace-reflow of the openai `sk-` class** (item 5-adjacent) — `sk-` is deliberately excluded from `REFLOW_PREFIXES` (too short/ambiguous — `risk-based` would trip it), so a whitespace-split OpenAI key is caught by the base pass only when contiguous.
- **Decoded content that is a legitimate BINARY asset** (font/wasm/image) is intentionally NOT re-scanned (a printable-text ratio gate) — this trades a small detection gap (a secret spliced into a mostly-binary blob) for not fail-closing every embedded asset. The bare `cloudflare_token` class likewise excludes `+`/`/`/`=`-adjacent 40-char runs so a standard-base64 segment does not FP.

**Cross-redactor consistency (item 8):** `linear-fetch/redact-linear-urls.sh` stays out of scope (a single orthogonal Linear-CDN-URL class, no secret overlap). `operator-digest/digest-scrub.sh` keeps its own ERE regex set (bash cannot NFKC — the reason this engine is Python), but its secret-class **name** set is now CI-enforced against the engine by `plugins/soleur/test/redact-class-parity.test.sh`; regex-**body** parity remains a manual-review non-goal.

## Consequences

- **Availability shift (not "no change"):** `code-to-prd` Layer 2 was pure-bash and always ran; it now hard-depends on `python3` and fails closed (blocks all PRD writes) on a `python3`-less runner. Correct posture, but a green→red on such a runner is attributable here.
- **Egress-reducing:** strengthens existing gates with no new processing or sub-processor — it lowers the GDPR Art. 33/34 breach surface rather than widening it.
- The fail-closed contract is enforced by `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` (golden ERE↔`re` parity, oversize, no-python3, homoglyph-known-gap) and `code-to-prd.test.sh`, run by the plugin bash test suite on every PR touching these skills.
- **#6045 availability hardening:** the `email` class quantifiers are bounded (RFC 5321 `{1,64}`/`{1,255}`) to remove a pre-existing O(n²) ReDoS (a crafted ~1 MiB email-class run could hang the gate ~30 min, blocking all egress); the reflow occurrence cap now counts every prefix examined; and the decode fan-out is bounded per pass. Regression tests: `redact-sentinel.test.sh` Test 17 (email flood) + Test 16e (base64 flood). The cross-redactor secret-class **name** parity between the engine and `operator-digest/digest-scrub.sh` is CI-enforced by `plugins/soleur/test/redact-class-parity.test.sh`.
