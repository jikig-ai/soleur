---
title: "A new wrapper that re-echoes an untrusted value a hardened sibling sanitizes is a new sink — re-apply the sanitizer"
date: 2026-07-11
category: security-issues
module: apps/web-platform/infra
issue: 6353
pr: 6354
tags: [log-injection, github-actions, sanitization, defense-in-depth, deploy-status]
---

# Wrapper around a sanitizing sibling must re-apply the sanitizer

## Problem

While fixing #6353 (the deploy fan-out `tag_malformed` wedge), the fix added a new
wrapper `_resolve_known_good_tag()` in `apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh`
that fetches web-1's `/health .version` (an untrusted public value) and passes it to the
pure resolver `resolve-web1-known-good-tag.sh`. On the rejection path the wrapper echoed
the raw value into a GitHub Actions log line:

```bash
echo "::error::… (/health .version='${version}') …" >&2   # RAW — vulnerable
```

The sibling resolver it wraps ALREADY sanitizes the identical value before echoing it
(`resolve-web1-known-good-tag.sh:55`: `tr -d '\000-\037'`), specifically to block
workflow-command injection. The wrapper is reached on **exactly** the malformed-version
path — i.e. precisely when `version` is most likely to carry an embedded newline. A spoofed
`.version` of `"1.2.3\n::error::SPOOFED\n::add-mask::x"` produced line-start
`::error::SPOOFED` + `::add-mask::x` in the runner log — genuine forged workflow commands
(annotation spoofing, log-mask poisoning, `::stop-commands::` suppression).

Green CI + the resolver's own sanitization masked it: the resolver's diagnostic collapsed
the newlines correctly, so a casual read of "the value is sanitized" was true for the
*sibling* and false for the *new wrapper*.

## Solution

Re-apply the sibling's sanitization at the new sink before interpolating the untrusted value:

```bash
local safe_version; safe_version=$(printf '%s' "$version" | tr -d '\000-\037')
echo "::error::… (/health .version='${safe_version}') …" >&2
```

Empirically confirmed: the spoofed `::error::`/`::add-mask::` no longer land at line start.

## Key Insight

**Sanitization travels with the SINK, not the value.** When a fix introduces a new
function that re-emits an untrusted value a nearby/hardened function already sanitizes,
the new emit is a NEW sink and must re-apply the same scrub — "the value is already
sanitized upstream" is a property of the OTHER sink, not a transitive guarantee. This is
the render-sink analogue of `hr-write-boundary-sentinel-sweep-all-write-sites`: enumerate
every place the untrusted value is emitted, not just the one the issue names.

Detection that worked: `security-sentinel`, prompted to *trace whether raw `$version` can
reach a log line unsanitized* and to reproduce the injection empirically — it built the
exact newline-carrying payload and observed the forged commands. A prompt that only asked
"is the input sanitized?" would have gotten a false "yes" from the sibling resolver.

## Session Errors

1. **P2 log-injection introduced in the new wrapper (pr-introduced).** — Recovery: strip
   C0 controls (`tr -d '\000-\037'`) before echoing, mirroring the sibling resolver.
   **Prevention:** when a fix wraps a sanitizing primitive and re-emits the same untrusted
   value, `git grep` every emit of that value in the new code and confirm each re-applies
   the scrub. Reviewer prompt: "trace whether the raw untrusted value can reach a log/echo
   line unsanitized, and reproduce the injection."
2. **P3 lost RC==0 coverage (pr-introduced).** Replacing AC3e/AC4-latest-resolve with T-D
   dropped the "retrigger-advance → accept (exit 0)" green-path assertion (T-D asserts the
   POST payload but ends RC=1). — Recovery: added T-D-green (an `ok` completion at the
   `/health`-advanced tag → exit 0). **Prevention:** when REPLACING a test, diff the
   assertions it made and confirm each behavior still has a home; a replacement that only
   covers the failure arm silently drops the success arm.
3. **P3 comment rot (pr-introduced).** Removing the trigger's `_get_status` re-read left
   the harness SEQ position-contract comment describing the deleted behavior. — Recovery:
   updated the comment. **Prevention:** when deleting the code a comment describes, grep the
   file for the comment's claims in the same edit.

## Related

- [[2026-07-09-sanitized-marker-alongside-raw-sibling-diagnostic-leaks-and-purity-test-scope]] — the closely-related class: a sanitized emitter shipped ALONGSIDE a pre-existing raw sibling on the same sink; here the raw sink is a NEW wrapper around the sanitizing sibling.
- `knowledge-base/project/learnings/best-practices/2026-07-07-deploy-status-tag-reader-resolve-running-version-from-health.md` — the direct predecessor (#6147): the reader-classification sweep this fix (the third `.tag` reader) extends.
- ADR-079 amendment (#6353) — the `.tag` is acceptance-proof-only, never a tag source.
