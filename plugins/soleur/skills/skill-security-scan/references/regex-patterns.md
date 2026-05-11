# skill-security-scan: regex pattern provenance

Authoritative regex pattern list for the five detection categories. The bash
scripts under [../scripts/](../scripts/) source patterns from this file and the
sibling [rules/](./rules/) YAML files. Patterns live HERE (not in plan or
learning prose) per Sharp Edge #16 of `2026-05-10-feat-skill-security-scan-plan.md`.

All regexes use POSIX extended (`grep -E`) syntax unless otherwise noted.
ReDoS-bounded: every quantifier has an explicit upper bound (no unbounded `+`
or `*` against attacker-controlled input).

---

## Category 1: code-execution anti-patterns

Bash patterns are stored in [rules/code-exec.yaml](./rules/code-exec.yaml). The
script `check-codeexec.sh` consumes the YAML and applies each rule's regex
against fenced code blocks in the input.

**Severity rules:**

- Dynamic-evaluation primitives in code blocks → `HIGH-RISK`
- Shell-spawn invocation that interpolates user-controllable args → `HIGH-RISK`
- Shell-spawn with hardcoded args → `REVIEW`
- Obfuscation signatures (decode-then-execute, hex-encoded ≥40 chars) → `HIGH-RISK`
- Fetch-then-execute family (`curl|wget|fetch <url> | bash`, `bash <(curl ...)`, `eval "$(curl ...)"`) → `HIGH-RISK`. Rule_ids: `fetch-pipe-shell`, `fetch-process-sub-shell`, `fetch-cmdsub-exec`. Added per #3554 — the canonical install-flow RCE vector was missing from the pack.
- Shell-expansion inside string interpolation spanning ≥2 user-tokens → `REVIEW`

**Format-only carve-out (calibration):** rules ignore code-fence content whose
language tag is `json`, `yaml`, `toml`, `csv`, or `text`. Calibration corpus on
first-party `plugins/soleur/skills/**/SKILL.md` requires this to hit the <5%
REVIEW target.

---

## Category 2: prompt-injection

**Frontmatter rules (high-precision, severity HIGH-RISK):**

- Role-hijack imperative — instructions directing the agent to discard prior
  instructions. Pattern keywords: `ignore`, `disregard`, `forget` + proximity
  to `previous`, `prior`, `above`, `system`, `instructions`.
- Mode-jailbreak signature — any of `DAN`, `developer.mode`, `jailbreak` (case
  insensitive, word-boundary anchored).
- System-prompt exfiltration imperative — `(reveal|print|show|output|leak)`
  within 6 tokens of `system.prompt`.
- Delimiter break-out tokens — `</system>`, `<|im_end|>`, `<|im_start|>`,
  fenced code-block immediately followed by `system:`.

**Body rules (proximity-gated, severity REVIEW):**

The same patterns as frontmatter apply, but with one additional gate to
suppress false-positives on legitimate prose:

- Body match counts ONLY IF: `(you must|you should)` proximity within 10
  tokens, OR a base64-blob `[A-Za-z0-9+/]{40,}={0,2}` is present nearby.

**Soleur prose allowlist (downgrade match to LOW-RISK):**

The string `ignore` is downgraded if followed within 6 tokens by ANY of:
`step`, `cache`, `warning`, `error`, `file`, `test`, `null`, `undefined`,
`empty`, `comment`. This is the legitimate-flow-control prose carve-out
that prevents self-trip on `social-distribute`, `brainstorm`, etc.

**Zero-width characters anywhere:** `[​‌‍﻿]` → `REVIEW`.
Encoded literally with `\uXXXX` per AGENTS.md `cq-regex-unicode-separators-escape-only`.

---

## Category 3: supply-chain

No regex; this category dispatches a structured query to the OSV.dev batch
API (`https://api.osv.dev/v1/querybatch`) for parsed manifest references.
See [rules/supply-chain.yaml](./rules/supply-chain.yaml) for the ecosystem
allowlist.

**Typosquat detection** uses Levenshtein distance ≤ 2 against the vendored
top-1k package list at [typosquat-targets.yaml](./typosquat-targets.yaml).

---

## Category 4: filesystem-boundary

Patterns are stored in [rules/filesystem-boundary.yaml](./rules/filesystem-boundary.yaml).

**Severity rules:**

- Write attempts to credential dotfiles (`.env`, `doppler.yaml`, SSH/AWS keys,
  `.claude/settings.json`) → `HIGH-RISK`
- Read attempts on credential paths → `HIGH-RISK`
- Path traversal in declarative paths (`../` sequences, absolute paths to
  `/etc`, `/root`) → `REVIEW`
- Symlink-creation calls targeting paths outside designated dirs → `REVIEW`

---

## Category 5: telemetry-surface

**URL host-aware allowlist (R14 mitigation).** First-party allowlist matching
operates on the parsed URL `host` segment, not raw substring. Adversarial
`https://attacker.com/redirect?ref=soleur.ai` is detected as `host=attacker.com`
and trips category 5; first-party `https://soleur.ai/foo` is `host=soleur.ai`
and is allowlisted.

URL extraction regex: `https?://[^\s'\"<>)]+` — matches plain URLs in markdown
prose, code blocks, and image tags.

**Severity rules:**

- Outbound-beacon in postinstall hook / install-time content → `HIGH-RISK`
- Redirect-tracking URLs in install-time content (`bit.ly`, `lnkd.in`,
  `t.co`, `trk.*`, `track.*`) → `HIGH-RISK`
- utm-tagged link to non-allowlisted host → `REVIEW`
- Branding-only ("powered by", "sponsored by", logos) → finding-level
  `WARN` (downgrades to `REVIEW` in aggregation, never `HIGH-RISK` alone)

**utm tag pattern:** `utm_(source|medium|campaign|term|content)=`

**Branding patterns:** case-insensitive match for `powered by`, `brought to you by`,
`sponsored by`. Image tags whose attributes include `logo`, `brand`, or `sponsor`.

See [first-party-allowlist.yaml](./first-party-allowlist.yaml) for Soleur-owned
hosts and approved utm campaign IDs.

---

## Provenance

Pattern taxonomy adapted from `alirezarezvani/claude-skills` (skill-security-auditor),
licensed under MIT. License at [../../../../LICENSES/skill-security-auditor.MIT.txt](../../../../LICENSES/skill-security-auditor.MIT.txt).
No verbatim regex copies.
