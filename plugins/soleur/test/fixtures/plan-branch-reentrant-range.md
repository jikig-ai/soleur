---
title: "fixture: a plan that DOCUMENTS the frontmatter mechanism"
date: 2026-08-10
branch: real-branch
---

# The body carries a second `---` delimited block

This is the shape that defeated the previous reader. A `sed` range `/^---$/,/^---$/` closes on the
frontmatter terminator and then **re-arms** on the next bare `---`, harvesting the body value. Any
document explaining this mechanism has exactly this shape, so it is not a hypothetical.

---

Above is a bare horizontal rule at column 0. Below is a fenced frontmatter example:

```yaml
---
branch: body-example-branch
---
```

A correct reader returns `real-branch` — never `body-example-branch`.
