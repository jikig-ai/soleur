# Fixture — a document with NO leading frontmatter

This file starts with a heading, not `---`. It documents the cursor mechanism, so it contains the
key inside a fenced example. A reader whose leading-frontmatter guard is inert will latch its sed
range onto the first `---` it finds anywhere below and mis-parse this example as metadata (#4724).

```yaml
---
branch: fenced-example-branch
---
```

The correct answer for this file is empty.
