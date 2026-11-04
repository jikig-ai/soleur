---
title: "CodeQL js/request-forgery on an egress-pinned sink — in-source suppression mechanics"
category: security-issues
tags: [codeql, request-forgery, ssrf, github-app, suppression]
module: apps/web-platform/server
symptom: "CodeQL alert stays open on a sink that is already egress-pinned (created after the guard landed)"
root_cause: "js/request-forgery has no sanitizer for a throwing hostname pin — only UriEncodingSanitizer + SanitizerFromModel (data extensions, unavailable under default setup); taint propagates through new URL(arg)"
---

# CodeQL `js/request-forgery` on an egress-pinned sink — in-source suppression

Alert #268 flagged `fetch(url, …)` in `githubFetch` even though `url` is rebound through
`githubEgressUrl` (throws unless origin == api.github.com) first. Verified against
`github/codeql` `RequestForgeryCustomizations.qll`: the query's only `Sanitizer` subclasses are
`UriEncodingSanitizer` and `SanitizerFromModel` — no hostname-allowlist barrier, and
`isAdditionalRequestForgeryStep` propagates taint through `new URL(arg)`. So **no code refactor can
clear the alert**; the in-code mechanism is a `// codeql[<query-id>]` annotation.

**Placement contract** (`AlertSuppression.qll` `covers`): the annotation must be a standalone `//`
line (first node on its line — NOT a trailing comment, NOT inside a string literal) and it covers
exactly `commentEndLine + 1`. `codeql[...]` same-line comments are NOT honored (github/codeql#11772
closed unmerged; `lgtm[...]` legacy form is, prefer `codeql[…]`). Multi-line alert spans are covered
by suppressing the alert's start line.

**Drift risk:** the annotation silently un-covers the sink on any reflow/interposed statement — pin
adjacency with a sentinel test using the anchored regex `^\s*//\s*codeql\[<qid>\]\s*$` for BOTH the
line-above assertion and the exactly-once count (a `toContain` check passes on trailing comments and
string literals). Assert exactly-one sink match, or scope the sink locator to the function body.

**Verification:** default setup (`query_suite: extended`) emits SARIF `suppressions:
[{kind: inSource}]` → the alert leaves `open` on the next scan after merge; confirm via
`gh api repos/<o>/<r>/code-scanning/alerts/<N> --jq .state`. API dismissal is operator-gated — the
in-source path needs no sign-off.
