---
name: skill-security-scan
description: "This skill should be used when scanning Claude Code skills or agent files for advisory security risks: code-execution, prompt-injection, supply-chain, filesystem-boundary, telemetry. Emits LOW-RISK | REVIEW | HIGH-RISK."
---

# skill-security-scan

<!--
Pattern provenance: portions of the detection-pattern taxonomy and the five-category
breakdown are adapted from alirezarezvani/claude-skills (skill-security-auditor),
licensed under the MIT License. The verbatim license text is preserved at
[LICENSES/skill-security-auditor.MIT.txt](../../../../LICENSES/skill-security-auditor.MIT.txt).
No verbatim code is copied; only the conceptual taxonomy and category framing.
-->

Advisory static-analysis gate that scans a SKILL.md or agent markdown file for five
categories of security risk. Emits one of `LOW-RISK | REVIEW | HIGH-RISK` plus a
findings report, with a mandatory advisory disclaimer footer. **Advisory only:**
output is not a security audit, certification, or warranty. The skill executes in
the operator's environment under the operator's account; the operator remains
responsible for review.

## Detection categories

1. **Code-execution anti-patterns** — dynamic-eval primitives, shell-spawn with
   user-controlled args, obfuscation signatures. See
   [references/rules/code-exec.yaml](./references/rules/code-exec.yaml).
2. **Prompt-injection** — frontmatter role-hijack and body proximity-gated patterns,
   with Soleur prose allowlist. See
   [references/regex-patterns.md](./references/regex-patterns.md).
3. **Supply-chain risk** — osv.dev batch query against parsed manifest references,
   with ecosystem allowlist + REVIEW-on-unknown + network-error-as-REVIEW.
4. **Filesystem boundary violations** — path traversal, symlink-out, write attempts
   to credential dotfiles. See
   [references/rules/filesystem-boundary.yaml](./references/rules/filesystem-boundary.yaml).
5. **Third-Party Telemetry Surface** — utm-tagged links, redirect-tracking domains,
   outbound-beacon URLs, vendor-branding footers. URL host-aware allowlist (not raw
   substring match — adversarial `https://attacker.com/?ref=soleur.ai` is detected
   as host=attacker.com). See
   [references/first-party-allowlist.yaml](./references/first-party-allowlist.yaml).

## Verdict semantics

| Verdict | Meaning | Operator action |
|---|---|---|
| `LOW-RISK` | No findings, or only finding-level metadata WARN tags | Proceed silently |
| `REVIEW` | At least one category emitted REVIEW | Read findings; decide |
| `HIGH-RISK` | At least one category emitted HIGH-RISK | Block-by-default; override via structured artifact |

Aggregation rule: max-severity across the five categories wins. Per-finding
`severity: WARN` contributes `REVIEW` to the aggregate verdict, never `HIGH-RISK`
alone.

## Invocation

Scan a file:

```bash
bash plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh < path/to/SKILL.md
```

Scan stdin content (used by `agent-finder` post-fetch / `skill-creator` post-scaffold
integrations):

```bash
echo "$skill_md_content" | bash plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh
```

Output: markdown findings table on stdout, mandatory advisory disclaimer footer
(non-removable), and `.scan-meta.json` written next to the input file (or to
`$XDG_RUNTIME_DIR/skill-security-scan-$$/` for stdin input).

## Override mechanism

When the scanner returns `HIGH-RISK` and the operator judges the finding to be a
false-positive or accepted-risk, override by committing a structured artifact:

```
knowledge-base/security/skill-overrides/YYYY-MM-DD-<slug>.md
```

The artifact is the sole audit-trail (no git trailer involved — squash-merge-safe).
Schema: [references/override-artifact-schema.json](./references/override-artifact-schema.json).
Process: [references/override-mechanism.md](./references/override-mechanism.md).

## Self-defense

The scanner is itself an attack surface. Defenses:

- **Rule-pack SHA pinning** via [references/rules/manifest.yaml](./references/rules/manifest.yaml).
  `run-scan.sh` validates rule-file SHAs at every run; tampering → REVIEW with
  reason `rule pack tampered`.
- **OSV untrusted-input handling**: schema validation, body-size cap, ecosystem
  allowlist (unknown ecosystem → REVIEW, never LOW-RISK), network-failure →
  REVIEW.
- **Fail-loud self-test**:
  [scripts/run-self-test.sh](./scripts/run-self-test.sh) runs the scanner over
  known-malicious + known-clean fixtures; any false-negative or false-positive on
  the seed set fails the test loudly. Wired into CI per
  `.github/workflows/skill-security-scan-corpus.yml`.

## PII redaction

Findings persisted to `.scan-meta.json` and override artifacts run through
email/IP/IBAN-shape redaction before write (per gdpr-gate `GDPR-DataMin-1`).
Operator-facing stdout is unredacted; persisted forms are redacted. Sentry mirrors
of scanner errors use `reportSilentFallback(err, { feature: 'skill-security-scan',
extra: { ...redacted } })`.

## Integrations

- `skill-creator` Step 5: post-validation scan before packaging.
- `agent-finder` §4b.5: cooperative-fast-path scan post-fetch / pre-write.
- PreToolUse hook on `Write` to `.claude/skills/**` and `.claude/agents/**`:
  load-bearing block-on-HIGH-RISK gate at the tool layer.
- Lefthook commit-time advisory: belt-and-suspenders for IDE / CLI commit paths.
- CI pre-merge required check + post-merge audit: defense-in-depth against
  tool-layer bypass.

See [references/override-mechanism.md](./references/override-mechanism.md) for
operator workflows.
