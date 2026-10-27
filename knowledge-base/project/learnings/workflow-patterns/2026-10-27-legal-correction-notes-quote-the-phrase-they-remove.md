---
date: 2026-10-27
issue: 10849
---

# Legal correction notes quote the superseded phrase they remove — absence greps must strip note spans first

House-style `*(corrected <date>, ref #N: an earlier version stated '<old phrase>')*` notes — and `**Last Updated:**` amendment notes — quote the falsified text verbatim. A bare `grep -c '<old phrase>'` on a corrected legal doc counts its own audit trail. Verification must locate each surviving occurrence and prove it sits inside a `*( ... )*` italic-note span (paren-depth tracking — the notes contain nested parens like "eu-west-1 (Ireland)"), not just sed-strip `*(corrected*)` (the `**Last Updated:**` note also quotes). Second trap found the same run: an issue/audit section cite can be one level off — #10849 cites privacy-policy §5.9 while the sentence lives in §4.13's bullet that cross-references §5.9; grep for the quoted string, not the cited section.
