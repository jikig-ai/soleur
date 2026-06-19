# Learning: Vector interpolates `$VAR` in raw config text — including comments

## Problem

Adding a new `[sources.host_scripts_journald]` block to `apps/web-platform/infra/vector.toml`
(#5499), `vector validate` failed:

```
x Missing environment variable in config. name = "LOG_TAG"
```

The new TOML block contained no `${LOG_TAG}` reference. The culprit was a **comment**:

```toml
# Seven bash scripts under apps/web-platform/infra/ log operational events to
# the journal via `logger -t "$LOG_TAG"`.   # <-- $LOG_TAG read as an env var
```

## Root cause

Vector's config loader performs environment-variable interpolation on the **raw file
bytes** *before* TOML parsing — so `$VAR` / `${VAR}` is expanded everywhere, including
inside `#` comments and string literals. A bare `$LOG_TAG` in a comment is treated as a
required env var; with `VECTOR_STRICT_ENV_VARS` unset/true it fails config load
(`vector validate` exit 78), even though the comment is documentation. The CI gate
`validate-vector-config.yml` runs `vector validate`, so this would have failed the PR.

## Solution

Do not write a literal `$NAME` in a vector.toml comment. Two options:
- Reword to a non-`$` form: `logger -t "$LOG_TAG"` → `logger -t <LOG_TAG>` (chosen — clearer anyway).
- Escape with `$$` (Vector treats `$$` as a literal `$`) — this is what the file's VRL
  regex replacement strings already do (e.g. `$${1}Bearer …`).

`vector validate --no-environment --config-toml <file>` reproduces the CI check locally
(download the pinned binary: parse `vector_version` from `vector.tf`, fetch from
`packages.timber.io/vector/<v>/...`).

## Key Insight

Treat a config file's comments as live text for any preprocessor that interpolates before
parsing (Vector `$VAR`, envsubst, Helm/Go templates, docker-compose `${}`). A `$`-prefixed
token in a comment is not inert. When documenting a shell snippet that contains `$VAR`
inside such a config, render the variable in angle-brackets (`<VAR>`) or escape per the
tool's rule. Cheapest gate: run the tool's own `validate` locally before relying on CI.

## Session Errors

- **`vector validate` failed `Missing environment variable LOG_TAG`** — Recovery: reworded
  the comment `"$LOG_TAG"` → `<LOG_TAG>`; re-validated green. Prevention: this learning +
  always run `vector validate` locally on a vector.toml edit (the pinned binary is a one-line
  download from `vector.tf`'s `vector_version`).
- **Config-block extraction awk over-captured the adjacent comment block** (caught at review,
  P2) — a `[sources.X]`-to-next-`[` awk window swept the *following* source's comment preamble;
  a `no-PRIORITY-filter` assertion over that window passed only because the neighbor's comment
  lacked the token. Recovery: reset the awk window on `^#`/blank line too, not just `^[`.
  Prevention: when extracting a TOML/INI block by "header to next header", stop at the first
  comment or blank line after the block's last key — block bodies here have no interior blanks.
- **Drift-guard `grep -q 'logger -t'` matched a comment mention** (caught at review, P3) — a
  script that only *documents* `logger -t` in a comment would be falsely classified as a
  journald emitter. Recovery: anchor on a real invocation shape `(^|\|)\s*logger -t`.
  Prevention: when a test classifies a file by "does it call X", match the call syntax
  (line-start or piped), never the bare token that also appears in prose.

## Tags
category: build-errors
module: apps/web-platform/infra/vector.toml
issue: 5499
