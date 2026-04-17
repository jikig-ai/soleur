---
name: Plan preflight must verify CLI invocation form, not just availability
description: --version proves installability, not usability. Preflight must exercise the exact flags/pipe form the plan depends on.
type: best-practice
category: plan
date: 2026-04-17
pr: 2457
issue: 2456
---

# Plan preflight must verify CLI invocation form, not just availability

## Problem

In the #2456 PDF linearization plan, the initial Phase 0 preflight verified only `qpdf --version` — availability in the runner base image. A reviewer challenged whether `qpdf --linearize - -` (stdin/stdout pipe form) would actually work, since some CLI tools don't support `-` as a positional sentinel for stdin/stdout.

The original preflight would have passed — qpdf is installable in `node:22-slim` — even if the pipe form silently misbehaved (e.g., treating `-` as a literal filename, producing an obscure error mid-implementation). The whole helper design (spawn + stdin pipe + stdout collection) depends on the pipe form working; a late failure here would collapse the plan.

## Solution

Expand Phase 0 / preflight to pipe a real fixture PDF through the exact invocation form and verify both exit code AND output validity:

```bash
docker run --rm -i node:22-slim bash -lc '
  apt-get update -qq
  apt-get install -y --no-install-recommends qpdf
  qpdf --version | head -1
  cat > /tmp/in.pdf
  qpdf --linearize - - < /tmp/in.pdf > /tmp/out.pdf
  qpdf --check /tmp/out.pdf | grep -i linearization
' < fixture.pdf
```

Expected: exit 0 AND `Linearization: yes` in the output. A failure here aborts the plan and triggers a pivot to tempfile-based I/O (documented as a fallback path in the plan).

## Key Insight

**Installability ≠ usability.** A preflight that only checks `--version` or `--help` tells you nothing about whether the specific flags / pipe form / long options your plan relies on are actually supported by the installed version.

For plans that prescribe a particular CLI invocation, the preflight must exercise that **exact form** with realistic input — not a surrogate check. This applies generally to:

- Specific stdin/stdout pipe forms (`-` as a sentinel for stdin/stdout)
- Long options or flag combinations that vary by version
- Output format options (JSON, CSV, `--porcelain=v2`)
- Multi-stage Docker build syntax
- Language runtime CLI options (`node --experimental-*`)
- GNU vs. BSD tool differences (`sed`, `grep`, `tar`)

This complements the existing plan-skill Sharp Edge about exit-code semantics — that rule addresses what a command returns; this rule addresses whether the invocation form is even recognized.

## Tags

category: best-practices
module: plan
