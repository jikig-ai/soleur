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

# Invisible / break-rendering / bidi separators + the decode-replacement char. NFKC does NOT
# remove these; they splice tokens invisibly. Keys are ordinals (escapes-only per the repo's own
# `cq-regex-unicode-separators-escape-only` invariant — INCLUDING U+2028/U+2029, whose omission
# would be both a self-inconsistency and a live splitter evasion).
STRIP = {c: None for c in (
    0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0x180E,          # zero-width
    0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,  # bidi (LRM/RLM/embeddings/overrides)
    0x2066, 0x2067, 0x2068, 0x2069, 0x061C,                  # bidi isolates + arabic letter mark
    0x00AD,                                                  # soft hyphen (renders invisibly, splits)
    0x2028, 0x2029,                                          # line / paragraph separators
    0x115F, 0x1160, 0x3164, 0x17B4, 0x17B5,                  # Hangul/Khmer fillers (render as nothing)
    0xFFF9, 0xFFFA, 0xFFFB,                                  # interlinear annotation anchors
    0xFFFD,                                                  # decode-replacement (invalid-byte splice)
)}

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
    # New Soleur crown-jewel classes (distinctive prefixes, low false-positive).
    ("doppler_token", re.compile(r"\bdp\.(st|pt)\.[A-Za-z0-9._-]{16,}", F)),
    ("slack_token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}", F)),
]


def _meta_redact(t):
    # Never emit a full token. Cap the revealed entropy — finding lines hit the transcript.
    if len(t) > 24:
        return f"{t[:4]}***{t[-4:]}"
    if len(t) > 12:
        return f"{t[:4]}***"
    return "***"


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
    # strip -> NFKC -> strip again: NFKC decomposition can EMIT combining/zero-width chars,
    # re-opening a splitter after the first strip. The second strip is idempotent. Then the
    # targeted confusable fold.
    norm = unicodedata.normalize("NFKC", stripped).translate(STRIP).translate(CONFUSABLE_MAP)
    if len(norm.encode("utf-8")) > MAX:  # post-NFKC re-check (NFKC can expand 1 cp -> up to 18)
        print(f"SYNTHETIC HIGH: normalized input exceeds {MAX} bytes — fail closed")
        return 1
    hits = 0
    for name, rx in PATTERNS:
        for m in rx.finditer(norm):
            print(f"at offset {m.start()}: {_meta_redact(m.group(0))} matched pattern {name}")
            hits += 1
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
