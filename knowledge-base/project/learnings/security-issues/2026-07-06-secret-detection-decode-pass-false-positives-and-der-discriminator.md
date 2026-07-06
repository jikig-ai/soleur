---
date: 2026-07-06
category: security-issues
module: redaction-engine (plugins/soleur/skills/incident/scripts/redact-engine.py)
issue: 6045
tags: [redaction, secret-detection, false-positive, base64, DER, regex, ReDoS]
---

# Learning: adding decode/length-anchored passes to a secret redactor introduces predictable false-positive & FN classes

Context: extending a fail-closed secret-redaction engine (#6045) with a base64/hex/percent
decode-and-rescan pass, a headerless-PEM DER heuristic, a bare-length Cloudflare token class, and a
whitespace-reflow pass. Brand-survival threshold = single-user incident, so both a missed secret
(GDPR Art. 33/34) and an over-redaction (fail-closes a legitimate write) are user incidents. Five
non-obvious traps, each caught by a review agent (not by the passing test suite that shipped first).

## Problem → Solution (reusable class)

1. **A bare-length token class (`[A-Za-z0-9_-]{40}`) false-positives on STANDARD base64 content.**
   Standard base64 uses `+` and `/`, which are NOT in `[A-Za-z0-9_-]`, so they split a base64 blob into
   segments — and a 40-char segment satisfies a `(?<![A-Za-z0-9_-])…{40}(?![A-Za-z0-9_-])` boundary
   lookaround, tripping the class on any embedded base64 asset (data-URI image/font). **Fix:** add the
   encoding's structural delimiters to the boundary exclusion — `(?<![A-Za-z0-9_+/=-])…(?![A-Za-z0-9_+/=-])`.
   url-safe base64 (`-_`, one contiguous run) never had this problem (no 40-char *segment* is boundary-isolated).
   **Generalizes:** any length-anchored (prefixless) detector must exclude the delimiter alphabet of the
   encodings its inputs commonly carry.

2. **Re-running secret patterns over DECODED bytes false-positives on binary assets.** A legitimate
   base64/hex-encoded font/wasm/image decodes to bytes that can carry an incidental short-anchored run
   (`sk-…`, `whsec_…`), manufacturing a match that fail-closes the write. **Fix:** a printable-text ratio
   gate (`sum(printable)/len >= 0.85`) before re-scanning decoded content — a real encoded secret decodes
   to text; a binary asset does not. Run any binary-shaped check (DER key body) BEFORE the text gate.

3. **A DER private-key discriminator must handle BOTH short- and long-form length.** `raw[1] in
   (0x81,0x82,0x83)` matches only DER *long-form* length (content ≥128 B) → silently misses EC P-256
   (~118 B) and Ed25519 (~48–85 B), which use short-form (`raw[1] < 0x80`). And it must discriminate a
   private key (first inner element = `INTEGER` version, `0x02`) from a cert/SPKI/EncryptedPrivateKeyInfo
   (first inner = `SEQUENCE`, `0x30`) — flagging a public cert fail-closes a legitimate write. Parse the
   length, index the first inner tag, require `0x02`. `EncryptedPrivateKeyInfo` (inner SEQUENCE) is an
   accepted residual — record it, don't silently claim coverage.

4. **A multi-line base64 block assembler must `.strip()` each line, not `.rstrip()`.** Real k8s Secret /
   Helm `data:` values (the canonical "base64 in a manifest" leak vector) are INDENTED; a `re.fullmatch`
   over the raw (indented) line fails, so the wrapped body never assembles into a decodable blob → FN.

5. **An unbounded regex over user-controlled input is an O(n²) ReDoS.** `\b[A-Za-z0-9._%+-]+@…` backtracks
   quadratically on a long email-class run with no `@` (a crafted ~1 MiB input hung the fail-closed gate
   ~30 min, blocking all egress). **Fix:** bound the quantifiers with RFC caps (`{1,64}` local, `{1,255}`
   domain) → linear, no detection change for real emails.

## Key Insight

Each new detection pass has a symmetric failure surface: a **length/format-anchored** class FPs on the
structural alphabet of the encodings it scans, and a **decode-and-rescan** pass FPs on binary and FNs on
indentation/multi-encoding. At a fail-closed single-user-incident threshold, the FP (over-redaction) is a
first-class user incident, not just noise — every new pass needs a paired no-FP negative test with a
REALISTIC innocent input (embedded binary asset, indented manifest, git SHA, standard-base64 blob), and the
positive test must prove the *new pass* catches what the base pass misses (two-engine or base-pass-misses assertion).

## Process note

All five were caught by the review agents (security-sentinel: ReDoS + fuzz; user-impact-reviewer:
indented-k8s FN + binary FP), NOT by the 83/0 test suite that shipped before review — the suite encoded
the author's imagined inputs. A plausible, fully-passing implementation is not a verified one at this
threshold; the adversarial review pass is load-bearing precisely there.

## Tags
category: security-issues
module: redaction-engine
