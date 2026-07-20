---
date: 2026-07-05
category: security-issues
module: plugins/soleur/skills/incident
issue: 5987
tags: [redaction, unicode, nfkc, invisible-characters, fail-open, defense-in-depth]
---

# Learning: invisible-character neutralization (redaction / scrubbing) must strip by Unicode CATEGORY, not a hand-picked codepoint list

## Problem

The redaction engine (#5987) strips zero-width/bidi/invisible characters BEFORE NFKC +
regex matching, so a secret spliced with an invisible splitter (`sk_li‹ZWSP›ve_…`)
reassembles and gets caught. The first implementation used a hand-enumerated `STRIP`
dict of ~30 codepoints (the "obvious" zero-widths, bidi controls, soft-hyphen, fillers,
U+FFFD).

`security-sentinel` proved with 5 PoCs that the enumeration was **materially incomplete**
— whole invisible/NFKC-invariant families were absent, so a token spliced with any of
them exited 0 (fail-OPEN) against the *exact* engine that advertises defeating this class:

- C0 controls U+0000–U+001F (NUL is valid UTF-8, distinct from the invalid-byte→U+FFFD case)
- DEL U+007F
- variation selectors U+FE00–U+FE0F (category `Mn`, not `Cf`)
- the Tags block U+E0000–E007F (the classic invisible-injection block)
- combining grapheme joiner U+034F

An enumerate-by-codepoint approach cannot keep pace with Unicode; each omission is a
silent fail-open on a security-critical gate.

## Solution

Strip by **Unicode general category**, keeping meaningful whitespace, with a small
explicit tail for the invisibles that are NOT in the control/format categories:

```python
_KEEP_WHITESPACE = {0x09, 0x0A, 0x0B, 0x0C, 0x0D}
def _strippable(o):
    if o in _KEEP_WHITESPACE: return False
    if unicodedata.category(chr(o)) in ("Cc", "Cf", "Cs"): return True   # control/format/surrogate
    return 0xFE00 <= o <= 0xFE0F or 0xE0100 <= o <= 0xE01EF or o == 0x034F or 0x180B <= o <= 0x180D
# built once at import over bounded ranges (all cats live < U+30000, plus the Tags/VS-supp
# block U+E0000–E01FF) → ~0.09s, ~2.5k keys. Plus an explicit tail for Zl/Zp (U+2028/2029),
# So (U+FFFD), and the Hangul/Khmer fillers (Lo/Mn) that are not Cc/Cf/Cs.
STRIP = {o: None for o in _EXPLICIT_STRIP}
STRIP.update({o: None for o in range(0x30000) if _strippable(o)})
STRIP.update({o: None for o in range(0xE0000, 0xE0200) if _strippable(o)})
```

Keep `tab/LF/VT/FF/CR` (whitespace token-splitting is a *documented non-goal* — stripping
whitespace would merge lines and is a different problem). Scan bounded ranges at import,
not all 0x110000 (0.44s), to stay under the per-invocation latency budget.

## Key Insight

For any **security allow/deny gate over text** (redaction, secret scanning, log
scrubbing, homoglyph normalization), an allowlist/denylist of literal codepoints is a
standing fail-open: the character space grows and the list rots. Prefer a **category /
property predicate** (`unicodedata.category`, script, bidi class) so new codepoints in a
covered class are handled by construction. Reserve the explicit list only for the
handful of chars whose *category* doesn't capture intent (e.g. U+2028/2029 are `Zl`/`Zp`
you deliberately strip; U+FFA0→U+1160 NFKC folds need a second strip pass). Corollary:
`str.translate(dict)` is C-speed; build the strip table once at import over bounded
ranges, not per-scan and not over all of Unicode.

## Prevention

When reviewing/authoring an invisible-character or homoglyph gate, ask "is coverage a
Unicode *category*, or a hand-list?" A hand-list on a security gate is a finding — its
non-goals (what still evades) must be named in the ADR, and its covered set should be a
category predicate. Spawn `security-sentinel` with an explicit "enumerate evasion inputs
the strip step misclassifies, fail-open vs fail-closed for each" prompt — it reliably
finds the omitted families the author's enumeration missed.
