---
title: "HCL provider-block guards must enumerate all *.tf + modules, count braces by depth, and strip comments"
date: 2026-10-20
category: workflow-patterns
tags: [terraform, drift-guard, bash-parsing, review-findings]
---

A text-level guard asserting `provider "cloudflare"` block attributes needed three
successive hardening passes. Lessons generalize to any HCL block enumerator:

1. **Terraform merges the whole root dir** — a `main.tf`-only window misses sibling
   `.tf` files (this root once held a provider block in `jikigai-com.tf`), wired
   `modules/**/*.tf` children, and `*.tf.json` (fail closed on the syntax you can't
   parse). Plan claimed "no second injection site"; git history refuted it.
2. **Brace tracking needs depth + comment-stripping** — a col-0 `}` flush misses
   indented openers/next-line `{`/non-col-0 `}`; a naive depth counter is defeated
   by one stray `{` inside an HCL `#`/`//` comment, silently dropping the record.
3. **Generators are a second write site** — `provision-cloudflare.sh` emits provider
   blocks into new tenant roots outside both guarded roots; pin the emitted text
   in the same suite.
4. **`read -d ''` reads one record** — use a `while IFS= read -r -d ''` loop or
   `mapfile` for NUL-separated awk output.
