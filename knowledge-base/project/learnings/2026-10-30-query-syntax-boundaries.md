---
date: 2026-10-30
category: integration-issues
module: tooling
---

# Learning: keep shell, jq, and SQL quoting boundaries distinct

## Problem

A one-off `gh api --jq` comment filter used a regex containing escaped parentheses inside a shell-quoted jq expression. jq rejected the expression before the API response could be inspected. A separate Better Stack ClickHouse query used double quotes for SQL string literals; ClickHouse treated them as identifiers and rejected the query before it ran.

## Solution

Use jq `contains()` checks for fixed comment phrases. In ClickHouse SQL, use single quotes for string literals; when passing the SQL through a shell variable, preserve the helper's `$BS_TABLE` substitution token by escaping the dollar at the shell layer. Validate the selector/query independently before embedding it in a longer command.

## Key Insight

Each parser has its own quoting rules: shell, jq, and SQL do not share one escape convention. Prefer literal predicates for fixed phrases, use the query language's native string-literal syntax, and test the smallest query before combining it with transport and shell quoting.

## Session Errors

**Malformed jq regex selector failed before returning comments** — Recovery: changed the selector to fixed-string `contains()` predicates and reran successfully — **Prevention:** prefer literal jq predicates for known phrases; add regex escaping only when literal matching is insufficient.

**ClickHouse SQL used double quotes for string literals and failed with `UNKNOWN_IDENTIFIER` before querying logs** — Recovery: used SQL single-quoted literals inside a double-quoted shell variable and escaped the `$BS_TABLE` token — **Prevention:** preserve each parser boundary and validate the query syntax before the credential-wrapped call.

## Tags

category: integration-issues
module: tooling
