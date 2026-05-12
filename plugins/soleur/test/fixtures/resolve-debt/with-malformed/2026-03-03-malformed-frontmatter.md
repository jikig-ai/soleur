---
title: Malformed — never closes
date: 2026-03-03
category: technical-debt
tags: [fixture, malformed]

# Body Without Closing Frontmatter

This file's frontmatter has no closing `---` within the first 30 lines, so `parse_frontmatter` returns None. The resolve-debt walker must emit a stderr warning and skip this file without crashing.

Padding lines below to push any later `---` out of the parser's 30-line window:

Line 1
Line 2
Line 3
Line 4
Line 5
Line 6
Line 7
Line 8
Line 9
Line 10
Line 11
Line 12
Line 13
Line 14
Line 15
Line 16
Line 17
Line 18
Line 19
Line 20

---
