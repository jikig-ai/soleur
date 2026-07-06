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
import base64
import binascii
import os
import re
import sys
import unicodedata
import urllib.parse

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
    # Local-part/domain quantifiers are BOUNDED (RFC 5321: local <=64, domain <=255) — an unbounded
    # `+` backtracks O(n^2) on a long email-class run with no '@', hanging the fail-closed gate on a
    # crafted ~1 MiB input (#6045 security review). Bounding keeps it linear without narrowing real emails.
    ("email", re.compile(r"\b[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9.-]{1,255}\.[A-Za-z]{2,}\b", F)),
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
    # The boundary ALSO rejects `+` / `/` / `=` adjacency (base64 specials) so a 40-char SEGMENT of a
    # standard-base64 blob (split by +//) does not fire — that FP fail-closes a legitimate embedded asset
    # (#6045 review F4). Real tokens sit on whitespace / quote / colon boundaries; the `=`-prefixed env-var
    # case (`CLOUDFLARE_*_TOKEN=…`) is already caught by the env_var class.
    ("cloudflare_token", re.compile(r"(?<![A-Za-z0-9_+/=-])[A-Za-z0-9_-]{40}(?![A-Za-z0-9_+/=-])", F)),
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
            count += 1
            if count > _MAX_REFLOW_CANDIDATES:
                break  # bound total prefix occurrences EXAMINED per class (incremented before the skips)
            p = pm.start()
            if p > 0 and _is_word(norm[p - 1]):
                continue  # interior substring, not a real boundary — would fabricate a match
            window = norm[p : p + REFLOW_WINDOW]
            parts = re.split(r"\s+", window, maxsplit=_MAX_REFLOW_SPLITS)
            if len(parts) < 2:
                continue  # no whitespace in window — the base pass already saw this exact run
            # If the split cap was hit (len == _MAX_REFLOW_SPLITS+1), the last element is an unbounded
            # prose remainder — drop it so prose cannot be glued into a spurious token. A token split at
            # more than _MAX_REFLOW_SPLITS points is missed — a recorded residual (ADR-093). Joining
            # removes the whitespace separators, so the candidate is always shorter than the window.
            joinable = parts[:-1] if len(parts) == _MAX_REFLOW_SPLITS + 1 else parts
            m = full_rx.match("".join(joinable))
            if m:
                hits += _emit(name, m.group(0), p, "whitespace-rejoin", seen)
    return hits


# #6045 items 2 & 3 — reversibly-encoded secrets + headerless-PEM private-key body.
# Classes EXCLUDED from the decoded-content re-scan: weakly-anchored classes manufacture false positives
# on decoded high-entropy bytes (an IPv4/UUID/email surfacing INSIDE decoded bytes is far likelier a false
# positive than a real leak — over-redaction fail-closes a legitimate write). cloudflare_token (bare 40-char
# + predicate) is likewise excluded — a base64 blob is routinely 40 chars.
_DECODE_SKIP = {"IPv4", "UUID", "email", "cloudflare_token"}
# Bounds on the decode fan-out: the 1 MiB MAX input cap already bounds total input; these keep adversarial
# input (many candidate blobs) linear. Safe ONLY while MAX dominates — re-evaluate if MAX is raised.
_MAX_ENCODED_CANDIDATES = 4000
_MAX_CANDIDATE_LEN = 200000


def _b64_decode(s):
    # Try standard then url-safe base64; tolerate missing padding. None on failure (never raises).
    for alt in (s, s.replace("-", "+").replace("_", "/")):
        body = alt.rstrip("=")
        try:
            return base64.b64decode(body + "=" * ((-len(body)) % 4), validate=True)
        except (binascii.Error, ValueError):
            continue
    return None


def _is_der_private_key(raw):
    # #6045 item 3. True iff `raw` looks like an UNENCRYPTED private-key body: an outer DER SEQUENCE whose
    # FIRST inner element is an INTEGER (the version field of PKCS#1 / SEC1 / PKCS#8). A cert / SPKI /
    # EncryptedPrivateKeyInfo opens with an inner SEQUENCE and is REJECTED — those are public/encrypted
    # material and flagging them would fail-close a legitimate write (a public cert in a legal draft is fine).
    # Handles BOTH short-form (EC ~118B, Ed25519 ~48-85B) and long-form (RSA >=128B) length encodings; a
    # long-form-only check would silently miss EC/Ed25519. Residual gap: EncryptedPrivateKeyInfo (inner
    # SEQUENCE) is not caught — a named non-goal recorded in ADR-093. Floor guards tiny innocent DER.
    if len(raw) < 48 or raw[0] != 0x30:
        return False
    lb = raw[1]
    if lb < 0x80:
        content_start = 2
    elif lb in (0x81, 0x82, 0x83, 0x84):
        content_start = 2 + (lb - 0x80)
    else:
        return False
    return content_start < len(raw) and raw[content_start] == 0x02


def _scan_text(text, offset, tag, seen):
    # Re-run only the vendor-prefix/format-ANCHORED secret classes over a derived string (a decoded blob).
    # _DECODE_SKIP excludes the weakly-anchored classes that FP on decoded high-entropy bytes.
    hits = 0
    for name, rx in PATTERNS:
        if name in _DECODE_SKIP:
            continue
        pred = PREDICATES.get(name)
        for m in rx.finditer(text):
            val = m.group(0)
            if pred and not pred(val):
                continue
            hits += _emit(name, val, offset, tag, seen)
    return hits


def _mostly_text(raw):
    # Only re-scan decoded content that is plausibly TEXT. A real base64/hex-encoded secret decodes to
    # printable text; a legitimate embedded BINARY asset (font/wasm/image) decodes to bytes that can carry
    # an INCIDENTAL short-anchored run (e.g. `sk-…`, `whsec_…`) and manufacture a false positive that
    # fail-closes the write (#6045 review F4). A private-key body is binary but is handled by the DER check
    # BEFORE this gate. Empty → not text.
    if not raw:
        return False
    printable = sum(1 for b in raw if 0x20 <= b < 0x7F or b in (0x09, 0x0A, 0x0D))
    return printable / len(raw) >= 0.85


def _scan_encoded(norm, seen):
    hits = 0
    candidates = []  # (blob, offset)
    # (1) single-line / inline base64 runs (inline blobs).
    for m in re.finditer(r"[A-Za-z0-9+/_-]{24,}={0,2}", norm):
        candidates.append((m.group(0), m.start()))
    # (2) multi-line base64 BLOCKS: consecutive whole-line base64 joined into one blob — real PEM/DER
    #     bodies are 64-char line-wrapped, and k8s Secret / Helm `data:` values are INDENTED, so `.strip()`
    #     each line (not just rstrip) before the fullmatch or an indented wrapped body never assembles.
    block_lines = []
    block_off = None
    pos = 0
    for line in norm.splitlines(keepends=True):
        stripped = line.strip()
        if re.fullmatch(r"[A-Za-z0-9+/_-]{16,}={0,2}", stripped):
            if not block_lines:
                block_off = pos
            block_lines.append(stripped)
        else:
            if len(block_lines) >= 2:
                candidates.append(("".join(block_lines), block_off))
            block_lines = []
        pos += len(line)
    if len(block_lines) >= 2:
        candidates.append(("".join(block_lines), block_off))

    b64_count = 0
    for blob, off in candidates:
        if b64_count >= _MAX_ENCODED_CANDIDATES:
            break
        if len(blob) > _MAX_CANDIDATE_LEN:
            continue
        b64_count += 1
        raw = _b64_decode(blob)  # never raises — returns None on failure (no exit-2 bubble)
        if raw is None:
            continue
        if _is_der_private_key(raw):   # binary key body — DER-checked BEFORE the text gate
            hits += _emit("pem_key_body", blob, off, "headerless-PEM-DER", seen)
        if _mostly_text(raw):
            hits += _scan_text(raw.decode("utf-8", "replace"), off, "decoded base64", seen)
    # hex runs (even length only — an odd run cannot be whole bytes).
    hex_count = 0
    for m in re.finditer(r"\b[0-9A-Fa-f]{32,}\b", norm):
        if hex_count >= _MAX_ENCODED_CANDIDATES:
            break
        blob = m.group(0)
        if len(blob) % 2 or len(blob) > _MAX_CANDIDATE_LEN:
            continue
        hex_count += 1
        try:
            raw = bytes.fromhex(blob)
        except ValueError:
            continue
        if _mostly_text(raw):
            hits += _scan_text(raw.decode("utf-8", "replace"), m.start(), "decoded hex", seen)
    # percent-encoding: unquote once over the normalized text (bounded like the base64/hex paths; a
    # >_MAX_CANDIDATE_LEN document skips the decoded layer — its raw form is still scanned by the base pass).
    if re.search(r"%[0-9A-Fa-f]{2}", norm) and len(norm) <= _MAX_CANDIDATE_LEN:
        decoded = urllib.parse.unquote(norm)
        if decoded != norm:
            hits += _scan_text(decoded, 0, "decoded percent", seen)
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
    hits += _scan_reflow(norm, seen)    # #6045 item 1  — whitespace/newline token-splitting re-scan
    hits += _scan_encoded(norm, seen)   # #6045 items 2 & 3 — reversibly-encoded + headerless-PEM DER body
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
