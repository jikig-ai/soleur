# skill-security-scan override mechanism

When the scanner returns `HIGH-RISK` or `REVIEW` and the operator judges the
finding to be a false-positive or accepted-risk, override by committing a
**structured artifact** under `knowledge-base/security/skill-overrides/`.

The artifact alone is the audit-trail. **No git trailer is involved** — the
`Skill-Security-Ack:` trailer was dropped during plan review (DHH + simplicity
HIGH-confidence cut, Kieran P0-2). This eliminates squash-merge invariant
concerns: the artifact appears in `git diff main...HEAD --diff-filter=A`
regardless of merge strategy.

## Artifact location and naming

```
knowledge-base/security/skill-overrides/YYYY-MM-DD-<slug>.md
```

- `YYYY-MM-DD` — ISO-8601 date the override was created.
- `<slug>` — skill slug, lowercase + hyphens only, regex `^[a-z][a-z0-9-]*$`.
  Capital letters and regex meta-characters are rejected (prevents bash
  interpolation hazards in the filename match).

## Artifact frontmatter schema

Validated against [override-artifact-schema.json](./override-artifact-schema.json).

```yaml
---
skill: <slug>
source: <url-or-skill-creator>
findings_json: <inline-JSON-or-path-to-.scan-meta.json>
justification: <free-text explaining why operator accepts the verdict>
approver: <git config user.email>
scanner_version: 0.1.0
rule_pack_sha256: <prefix ≥ 8 chars from .scan-meta.json>
verdict: HIGH-RISK | REVIEW
timestamp: <ISO-8601>
---

# Override: <skill-slug>

## Findings (verdict: <verdict>)
<path to .scan-meta.json — see "PII safety" below>

## Justification
<free-text rationale>
```

## Operator workflow

1. Operator hits HIGH-RISK on a third-party skill they want to install.
2. Scanner emits findings + suggested override-artifact path + the runtime
   path to the redacted `.scan-meta.json` (printed on stdout).
3. Operator inspects the findings, decides override is appropriate.
4. Operator creates the artifact (manual or via `skill-creator` Step 5):

   ```bash
   cat > knowledge-base/security/skill-overrides/$(date -u +%Y-%m-%d)-<slug>.md <<EOF
   ---
   skill: <slug>
   source: <where-the-skill-came-from>
   findings_json: <path-to-redacted-.scan-meta.json>
   justification: <rationale>
   approver: $(git config user.email)
   scanner_version: 0.1.0
   rule_pack_sha256: <prefix-from-scan-meta>
   verdict: HIGH-RISK
   timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
   ---

   # Override: <slug>

   ## Findings
   <path to .scan-meta.json>

   ## Justification
   <text>
   EOF
   ```

5. Operator commits the artifact in the same PR as the skill install.
6. CI pre-merge gate (`skill-security-scan-pr-trailer.yml`) and the PreToolUse
   hook on Write run `parse-override.sh` to validate. Valid artifact → install
   accepted.

### PII safety — path-form mandate

The `findings_json` field MUST be a **path to the persisted, redacted
`.scan-meta.json`** — not an inline JSON copy of findings. Reason: scanner
stdout (which the operator sees during review) is intentionally unredacted
for in-terminal inspection; the persisted `.scan-meta.json` runs through
`redact_pii()` (email, IPv4, IBAN, JWT, Anthropic/OpenAI keys, GitHub
PAT/OAuth, GitLab PAT, Doppler tokens, Slack tokens, AWS keys). Copy-pasting
from terminal scrollback lands raw PII / secrets in a permanent git artifact
retained "for repository lifetime" per Art. 32 evidence retention.

`parse-override.sh` enforces this: artifacts whose body contains a raw email
pattern outside the `approver:` field are rejected with `invalid_schema`.

## Multiple overrides per PR

A single PR may install multiple skills. Each skill's override is one artifact
file. `parse-override.sh` enumerates all matched artifacts independently;
there is no shared state.

## Stale findings

If the rule pack updates between override creation and PR merge, the artifact's
`rule_pack_sha256` will no longer match the current `manifest.yaml` SHA.
`parse-override.sh` reports this as `stale_findings` and the CI gate fails with
an instruction to re-run the scan and update the artifact.

## Retention

Override artifacts are retained for the **repository lifetime** as Article 32
evidence (GDPR Art. 6(1)(c) lawful basis: legal obligation; Art. 6(1)(f):
legitimate interest in maintaining audit trail). Future operators must NOT
bulk-delete them. PII in the embedded `findings_json` is redacted at scan-time
per `GDPR-DataMin-1` (email/IPv4/IBAN-shape).

## Defense-in-depth

The override mechanism is the LAST gate. Earlier gates:

1. **PreToolUse hook on Write** (`.claude/hooks/skill-security-scan-write.sh`)
   — load-bearing tool-layer block on `HIGH-RISK without override artifact`.
2. **Cooperative-fast-path in agent-finder §4b.5** — surfaces findings to
   operator before the Write attempt.
3. **Cooperative-fast-path in skill-creator Step 5** — same as above for
   scaffold workflows.
4. **Lefthook commit-time advisory** (`.claude/hooks/skill-security-scan.sh`)
   — belt-and-suspenders for IDE / manual `git commit` paths.
5. **CI pre-merge required check** (`skill-security-scan-pr-trailer.yml`) —
   Layer C: blocks merge if any new HIGH-RISK skill install lacks a valid
   override artifact.
6. **CI post-merge audit** (`skill-security-scan-postmerge.yml`) — Layer D:
   re-validates on push to main. Auto-files `compliance/critical` issue if
   pre-merge gate was bypassed via admin merge or force-push.
7. **Branch protection** — `main` requires `skill-security-scan-pr-trailer`
   pre-merge status check. Bypassing requires explicit admin action that
   auto-files a compliance issue.

## Future extensions (NOT implemented in v1)

The original brainstorm and CTO Decision 12 contemplated a `/plan`-aware
skip-and-warn mode for the scanner. Phase 6 of the plan removed this for v1
because `/soleur:plan` does not scaffold or fetch skills — those code paths
live in `skill-creator` and `agent-finder` only. If a future plan-time
scaffolding workflow emerges, re-evaluate this design with a tracking issue.
The `SKILL_SECURITY_SCAN_PLAN_MODE` env-flag idea is preserved here as
documented future-extension guidance only; it is not implemented in this v1
release.
