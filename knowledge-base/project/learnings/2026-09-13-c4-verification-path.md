---
title: "C4 version pin is a Vitest check, not a shell test"
date: 2026-09-13
category: workflow
---

The C4 freshness check is exposed as
`plugins/soleur/test/c4-model-freshness.test.sh`, while the LikeC4 version-pin
check lives at `apps/web-platform/test/c4-likec4-version-pin.test.ts` and must
run through the web-platform Vitest project. Do not infer a shell-script path
from the freshness test name. Run the shell freshness check from the repository
root, because its path is relative to the checkout rather than the app package.
