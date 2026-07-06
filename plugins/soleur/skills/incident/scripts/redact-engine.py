#!/usr/bin/env python3
# Hardened redaction engine (#5987). Adapted from gstack `redact-engine` (clean-room;
# see plugins/soleur/NOTICE). Contract preserved 1:1 with the former bash engine so the
# three in-repo consumers (incident dry-run.sh, code-to-prd Layer 2, legal-generate gate)
# need no change:
#   argv[1] = path to scan.
#   exit 0 = clean / 1 = redaction needed (incl. synthetic HIGH) / 2 = cannot-evaluate.
#   stdout finding lines: "at offset <normOffset>: <prefix>***<suffix> matched pattern <class>"
#
# Pipeline: cap -> strip -> NFKC(whole-string) -> strip -> confusable-fold -> match -> meta-redact.
# Detection matches over ONE whole-string NFKC(strip(text)): per-codepoint normalization is NOT
# equal to whole-string NFKC (a decomposed/combining sequence folds to an ASCII secret char only
# whole-string), so per-codepoint would be a fail-OPEN. The sentinel halts; it never rewrites in
# place and no consumer parses the offset, so there is no offset-map back to the original.
import os
import re
import sys
import unicodedata

# 1 MiB default cap. Overridable via env for tests/tuning.
MAX = int(os.environ.get("REDACT_MAX_INPUT_BYTES", str(1024 * 1024)))

# Invisible / break-rendering / bidi / format characters that NFKC does NOT remove and that splice
# tokens invisibly. Built by Unicode CATEGORY, not a hand-picked codepoint list — an enumeration
# silently misses whole families (C0 controls, DEL, variation selectors, the Tags block U+E0000-E007F,
# combining grapheme joiner), each the SAME evasion class this engine defeats. Strip:
#   - categories Cc (control), Cf (format), Cs (surrogate) — EXCEPT the meaningful ASCII whitespace
#     controls (tab/LF/VT/FF/CR), which are kept (whitespace token-splitting is a documented non-goal);
#   - variation selectors (U+FE00-FE0F, U+E0100-E01EF), combining grapheme joiner (U+034F), and the
#     Mongolian free variation selectors (U+180B-180D) — invisible marks NFKC leaves intact.
# Plus an explicit tail for the invisibles that are NOT in Cc/Cf/Cs: line/para separators (Zl/Zp),
# the replacement char (So, from an invalid-byte splice), and the Hangul/Khmer fillers that render as
# nothing (Lo/Mn). Keys are ordinals throughout (escapes-only per `cq-regex-unicode-separators-escape-only`).
_KEEP_WHITESPACE = {0x09, 0x0A, 0x0B, 0x0C, 0x0D}
_EXPLICIT_STRIP = (
    0x2028, 0x2029,                          # line / paragraph separators (Zl / Zp)
    0xFFFD,                                  # decode-replacement char (So — invalid-byte splice)
    0x115F, 0x1160, 0x3164, 0xFFA0,          # Hangul fillers (Lo) — incl. halfwidth U+FFA0 (NFKC->U+1160)
    0x17B4, 0x17B5,                          # Khmer inherent vowels (Mn) — render as nothing
)


def _strippable(o):
    if o in _KEEP_WHITESPACE:
        return False
    if unicodedata.category(chr(o)) in ("Cc", "Cf", "Cs"):
        return True
    return 0xFE00 <= o <= 0xFE0F or 0xE0100 <= o <= 0xE01EF or o == 0x034F or 0x180B <= o <= 0x180D


# Built once at import over the bounded ranges that hold every Cc/Cf/Cs + invisible-mark codepoint
# (all below U+30000, plus the Tags/variation-selector-supplement block U+E0000-E01FF). ~0.1s, ~2.5k keys.
STRIP = {o: None for o in _EXPLICIT_STRIP}
STRIP.update({o: None for o in range(0x30000) if _strippable(o)})
STRIP.update({o: None for o in range(0xE0000, 0xE0200) if _strippable(o)})

# Targeted ASCII-lookalike fold for the strong Cyrillic/Greek homoglyphs that appear in secret
# prefixes/bodies. Cheap partial cross-script coverage so AC1 is HONEST; the full TR39 skeleton is a
# named non-goal and the residual gap is version-controlled by redact-sentinel.test.sh Test 12.
# Deliberately NO ->t mapping: no Cyrillic/Greek 't' lookalike is folded (Test 12b pins this gap).
_CONFUSABLE_PAIRS = {
    # Cyrillic -> Latin
    "а": "a", "е": "e", "о": "o", "р": "p", "с": "c",
    "ѕ": "s", "х": "x", "у": "y", "і": "i", "ј": "j",
    "к": "k", "ԛ": "q", "ԁ": "d", "ѵ": "v", "ԝ": "w",
    "һ": "h", "ɡ": "g",
    # Greek -> Latin
    "ο": "o", "ρ": "p", "ν": "v", "α": "a", "ε": "e",
    "κ": "k", "ι": "i", "υ": "u", "χ": "x",
}
CONFUSABLE_MAP = {ord(k): v for k, v in _CONFUSABLE_PAIRS.items()}

# All classes compiled with re.ASCII so \b/\w/\s keep grep's C-locale (ASCII) semantics. WITHOUT
# re.ASCII, Python's Unicode \b makes "Юsk-ant-..." a MISS the bash version caught (a NEW evasion).
# POSIX [^[:space:]] is hand-translated to \S (a literal [^[:space:]] in Python re is the char set
# {[ : s p a c e ]} — a silent narrowing).
F = re.ASCII
PATTERNS = [
    ("JWT", re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}", F)),
    ("email", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b", F)),
    # UUID broadened to [0-9A-Fa-f] (uppercase — a latent lowercase-only gap in the bash baseline).
    ("UUID", re.compile(r"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b", F)),
    ("stripe_key", re.compile(r"\b(sk|pk|rk)_(live|test)_[A-Za-z0-9]{16,}\b", F)),
    ("stripe_whsec", re.compile(r"\bwhsec_[A-Za-z0-9]{16,}\b", F)),
    ("stripe_acct", re.compile(r"\bacct_[A-Za-z0-9]{16,}\b", F)),
    ("stripe_cust_pi_seti_sub_in", re.compile(r"\b(cus|pi|seti|sub|in)_[A-Za-z0-9]{14,}\b", F)),
    ("IPv4", re.compile(r"\b(([0-9]{1,3})\.){3}[0-9]{1,3}\b", F)),
    # env_var vendor list broadened (+HETZNER|FLAGSMITH|RESEND|TAILSCALE); \S+ (NOT [^[:space:]]+).
    ("env_var", re.compile(
        r"\b(DOPPLER|SENTRY|STRIPE|SUPABASE|OPENAI|ANTHROPIC|GITHUB|VERCEL|CLOUDFLARE"
        r"|HETZNER|FLAGSMITH|RESEND|TAILSCALE)_[A-Z_]+=\S+", F)),
    ("github_token", re.compile(r"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}\b", F)),
    ("anthropic_key", re.compile(r"\bsk-ant-[A-Za-z0-9_-]{32,}\b", F)),
    ("openai_key", re.compile(r"\bsk-(proj-)?[A-Za-z0-9_-]{20,}\b", F)),
    ("supabase_pat", re.compile(r"\bsbp_[a-z0-9]{20,}\b|\b(sb_secret|sb_publishable)_[A-Za-z0-9]{20,}\b", F)),
    # PEM header broadened to catch ENCRYPTED / SSH2 / any [A-Z0-9 ]* qualifier.
    ("pem_private_key", re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----", F)),
    # New Soleur crown-jewel classes (distinctive prefixes, low false-positive). Doppler token kinds:
    # service (st), personal (pt), CLI (ct), service-account (sa), scim, audit. Slack token kinds:
    # bot/user/app/refresh/legacy (baprs) + config (c) + config-refresh (e).
    ("doppler_token", re.compile(r"\bdp\.(st|pt|ct|sa|scim|audit)\.[A-Za-z0-9._-]{16,}", F)),
    ("slack_token", re.compile(r"\bxox[baprsce]-[A-Za-z0-9-]{10,}", F)),
    # Cloudflare API tokens are exactly 40 chars of [A-Za-z0-9_-] with NO vendor prefix (#6045 item 6).
    # A 40-char lowercase-hex git SHA collides on length (incident PIRs cite SHAs constantly), so the
    # class carries an anti-SHA PREDICATE (below) requiring BOTH an uppercase letter AND a digit. Explicit
    # non-class boundaries (lookaround), NOT \b — '-' is a non-word char and \b mis-anchors at token ends.
    ("cloudflare_token", re.compile(r"(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{40}(?![A-Za-z0-9_-])", F)),
]

# Per-class post-match predicates: a match is kept only if the predicate returns truthy. The bare-length
# Cloudflare class must be gated or it fires on a 40-char lowercase-hex git SHA and 40-char kebab prose.
# A real CF API token is high-entropy base64url, so require BOTH an uppercase letter AND a digit — hex
# SHAs have no uppercase; kebab prose has neither. Deliberate ~0.1% miss (a real token lacking a digit or
# uppercase) to preserve the engine's low-false-positive posture. No entry = always kept. Shared by the
# base pass and the decoded-content pass so the gate cannot be bypassed via an encoded blob.
PREDICATES = {
    "cloudflare_token": lambda t: bool(re.search(r"[A-Z]", t)) and bool(re.search(r"[0-9]", t)),
}

PAT_BY_NAME = dict(PATTERNS)

# #6045 item 1 — whitespace / newline token-splitting re-scan. strip() KEEPS meaningful whitespace (a
# documented non-goal of the base pass), so a secret reflowed across a line break by a markdown/PDF
# renderer survives normalization. For each DISTINCTIVE-prefix class, locate the prefix at a real word
# boundary and rejoin the token across a BOUNDED number of whitespace runs (a reflowed token is split a
# few times by a renderer; prose has a whitespace run every few chars, so the bound admits reflow and
# rejects prose). Excludes the short/ambiguous openai `sk-` prefix and the prefixless Cloudflare class.
# REFLOW_PREFIXES keys MUST be PATTERNS names (asserted at import — no silent drift).
REFLOW_WINDOW = 512               # ~2.5x the longest anchored body; a 4096 window would be wasted work.
_MAX_REFLOW_SPLITS = 4            # rejoin across at most 4 whitespace runs — a reflowed token wrapped a
                                  # few times is caught; prose (a run every few chars) never reaches a
                                  # class's min length within 4 joins, so it is rejected (no manufactured FP).
_MAX_REFLOW_CANDIDATES = 4000     # cap prefix occurrences per class so a prefix-flooded 1 MiB input stays
                                  # linear (code-to-prd scans attacker-controlled rendered text). Safe only
                                  # while the 1 MiB MAX input cap dominates; re-evaluate if MAX is raised.
REFLOW_PREFIXES = {
    "JWT": re.compile(r"eyJ", F),
    "stripe_key": re.compile(r"(sk|pk|rk)_(live|test)_", F),
    "stripe_whsec": re.compile(r"whsec_", F),
    "stripe_acct": re.compile(r"acct_", F),
    "github_token": re.compile(r"(gh[pousr]_|github_pat_)", F),
    "anthropic_key": re.compile(r"sk-ant-", F),
    "supabase_pat": re.compile(r"(sbp_|sb_secret_|sb_publishable_)", F),
    "doppler_token": re.compile(r"dp\.(st|pt|ct|sa|scim|audit)\.", F),
    "slack_token": re.compile(r"xox[baprsce]-", F),
}
assert set(REFLOW_PREFIXES) <= {n for n, _ in PATTERNS}, "REFLOW_PREFIXES has an unknown class name"


def _is_word(ch):
    # ASCII word char (matches re.ASCII \w): [A-Za-z0-9_]. Confirms a real boundary before a prefix.
    return ch == "_" or (ch.isascii() and ch.isalnum())


def _meta_redact(t):
    # Never emit a full token. Cap the revealed entropy — finding lines hit the transcript.
    if len(t) > 24:
        return f"{t[:4]}***{t[-4:]}"
    if len(t) > 12:
        return f"{t[:4]}***"
    return "***"


def _emit(name, value, offset, tag, seen):
    # Dedup on (class, raw value) so a token found by the base pass is not re-reported by the reflow /
    # decode passes. Offsets are NOT part of the key — base-pass offsets are norm-space, derived-pass
    # offsets are decoded-space, so they are not comparable; dedup affects finding-line noise only, never
    # the exit code. The tag note ALWAYS starts with " (" so the parity grep 'matched pattern [A-Za-z_]+'
    # (which stops at the space) never absorbs it. Returns 1 on a new emit, 0 on a dedup hit.
    key = (name, value)
    if key in seen:
        return 0
    seen.add(key)
    note = f" ({tag})" if tag else ""
    print(f"at offset {offset}: {_meta_redact(value)} matched pattern {name}{note}")
    return 1


def _scan_reflow(norm, seen):
    hits = 0
    for name, prefix_rx in REFLOW_PREFIXES.items():
        full_rx = PAT_BY_NAME[name]
        count = 0
        for pm in prefix_rx.finditer(norm):
            if count >= _MAX_REFLOW_CANDIDATES:
                break
            p = pm.start()
            if p > 0 and _is_word(norm[p - 1]):
                continue  # interior substring, not a real boundary — would fabricate a match
            window = norm[p : p + REFLOW_WINDOW]
            parts = re.split(r"\s+", window, maxsplit=_MAX_REFLOW_SPLITS)
            if len(parts) < 2:
                continue  # no whitespace in window — the base pass already saw this exact run
            count += 1
            # If the split cap was hit (len == _MAX_REFLOW_SPLITS+1), the last element is an unbounded
            # prose remainder — drop it so prose cannot be glued into a spurious token.
            joinable = parts[:-1] if len(parts) == _MAX_REFLOW_SPLITS + 1 else parts
            candidate = "".join(joinable)
            if candidate == window:
                continue  # nothing rejoined
            m = full_rx.match(candidate)
            if m:
                hits += _emit(name, m.group(0), p, "whitespace-rejoin", seen)
    return hits


def scan(path):
    if not os.path.isfile(path) or not os.access(path, os.R_OK):
        sys.stderr.write(f"redact-engine: file not readable: {path}\n")
        return 2
    with open(path, "rb") as fh:
        raw = fh.read()
    if len(raw) > MAX:
        print(f"SYNTHETIC HIGH: input exceeds {MAX} bytes ({len(raw)}) — fail closed")
        return 1
    stripped = raw.decode("utf-8", "replace").translate(STRIP)
    # strip -> NFKC -> strip again: NFKC can FOLD a compatibility character into a strippable one that
    # was not present in the raw input — e.g. U+FFA0 (halfwidth Hangul filler) -> U+1160 (Hangul filler,
    # in STRIP). The second strip closes that re-opened splitter; it is idempotent on already-clean text.
    # Then the targeted confusable fold.
    norm = unicodedata.normalize("NFKC", stripped).translate(STRIP).translate(CONFUSABLE_MAP)
    if len(norm.encode("utf-8")) > MAX:  # post-NFKC re-check (NFKC can expand 1 cp -> up to 18)
        print(f"SYNTHETIC HIGH: normalized input exceeds {MAX} bytes — fail closed")
        return 1
    seen = set()
    hits = 0
    # Base pass over the whole normalized string (real offsets). PREDICATES gate the bare-length classes.
    for name, rx in PATTERNS:
        pred = PREDICATES.get(name)
        for m in rx.finditer(norm):
            val = m.group(0)
            if pred and not pred(val):
                continue
            hits += _emit(name, val, m.start(), "", seen)
    hits += _scan_reflow(norm, seen)   # #6045 item 1 — whitespace/newline token-splitting re-scan
    return 1 if hits else 0


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: redact-engine.py <path>\n")
        return 2
    try:
        return scan(sys.argv[1])
    except Exception as e:  # any engine crash = cannot-evaluate, fail closed
        sys.stderr.write(f"redact-engine: internal error: {e}\n")
        return 2


if __name__ == "__main__":
    sys.exit(main())
