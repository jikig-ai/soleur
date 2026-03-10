---
title: "jq generator-style joins silently drop unmatched records"
date: 2026-03-10
category: logic-errors
tags: [jq, shell, data-integrity, silent-failure]
symptoms: "Output array shorter than input array with no error. result_count disagrees with mentions array length."
module: plugins/soleur/skills/community/scripts/x-community.sh
---

# Learning: jq generator-style joins silently drop unmatched records

## Problem

When joining two arrays in jq (e.g., tweets with their author info from `includes.users`), the idiomatic-looking generator pattern silently drops records that have no match:

```jq
# BROKEN: silently drops tweets whose author_id is not in includes.users
[
  .data[] |
  (.includes.users[] | select(.id == .author_id)) as $user |
  {
    id: .id,
    text: .text,
    author_username: $user.username
  }
]
```

The `(.includes.users[] | select(.id == .author_id)) as $user` is a jq generator expression. When `select()` produces zero results for a given tweet, the generator yields nothing -- and the entire downstream expression (the object construction) is never evaluated for that tweet. The tweet vanishes from the output array with no error, no warning, and no indication that data was lost.

This is especially dangerous with the X/Twitter mentions API because `includes.users` may omit suspended or deleted accounts, so the output array can be shorter than `.meta.result_count` indicates. The mismatch is silent and easy to miss in testing with well-formed data.

## Solution

Replace the generator-style join with `INDEX()` to build a lookup map. Missing entries resolve to `{}`, keeping fallbacks like `// "unknown"` reachable:

```jq
# CORRECT: every tweet is preserved; missing users get "unknown" fallbacks
((.includes.users // []) | INDEX(.id)) as $users |
{
  mentions: [
    .data[] |
    ($users[.author_id] // {}) as $user |
    {
      id: .id,
      text: .text,
      author_username: ($user.username // "unknown"),
      author_name: ($user.name // "unknown"),
      created_at: .created_at,
      conversation_id: .conversation_id
    }
  ]
}
```

`INDEX(.id)` constructs `{"user_id_1": {user_obj}, "user_id_2": {user_obj}, ...}`. Looking up a missing key returns `null`, which `// {}` coerces to an empty object, and then field access on `{}` returns `null`, which `// "unknown"` coerces to the fallback string. Every tweet is preserved.

## Key Insight

jq generators that produce zero results cause the entire surrounding expression to emit nothing -- not null, not an error, just silence. This is by design (generators are like nested loops where zero iterations produce zero output), but it makes generator-style joins fundamentally unsafe for data pipelines where every input record must produce an output record.

The safe pattern is always `INDEX` + map lookup + `// fallback`:
1. `INDEX(.key_field)` builds an O(1) lookup from the join table
2. `$lookup[.foreign_key] // {}` ensures a missing match returns an empty object (not nothing)
3. `$obj.field // "default"` provides graceful degradation for each field

This mirrors the difference between SQL `INNER JOIN` (generator pattern -- drops unmatched rows) and `LEFT JOIN` (INDEX pattern -- preserves all rows from the left table). In data pipelines, default to the LEFT JOIN equivalent unless you explicitly want to discard unmatched records.

## Related Learnings

- `2026-03-09-shell-api-wrapper-hardening-patterns.md` -- other jq failure modes in the same shell scripts (fallback chains, JSON validation)
- `2026-03-10-require-jq-startup-check-consistency.md` -- ensuring jq is available before scripts run
- `2026-03-05-github-output-newline-injection-sanitization.md` -- another jq output pitfall (`jq -r` producing literal newlines)
- `2026-03-03-fix-release-notes-pr-extraction.md` -- `jq '.[0].number'` returning literal "null" instead of empty (same class: jq silent misbehavior)

## Tags

category: logic-errors
module: x-community.sh
symptoms: silent-data-loss, array-length-mismatch, generator-zero-emission
