## Summary

Adds a read-only wrapper so the CTO agent can run four live checks. It is a draft and unarmed.

## Owner review items (read these first)

1. **Write-capable tokens used for reads.** Three checks use the infrastructure tokens, which can write. No read-only equivalent exists. Stricter alternative (recorded dissent): keep these reads unverified until read-only tokens are minted.
2. **Brand-survival threshold raised to `single-user incident`** because a leaked token could change the edge that carries sign-in and chat. The CPO sign-off that threshold implies has NOT happened; it is yours.
3. **Push-bar exemption (owner-visible widening).** Ruled by CTO agent, 2026-11-03: narrow the exemption to exactly two paths.
4. **Post-merge workflows.** This diff touches the plugin tree, so the post-merge release workflows will run when you merge.

## What the review found and fixed

- Nine reviewers ran; every finding was fixed.
- A planted config file can no longer print the bound token.
