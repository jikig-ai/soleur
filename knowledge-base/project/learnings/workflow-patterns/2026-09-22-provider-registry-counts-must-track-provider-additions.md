---
title: Provider registry count tests must change with provider additions
date: 2026-09-22
category: workflow-pattern
---

Adding a provider to `PROVIDER_CONFIG` changes both the registry count and the
derived services count. The focused provider tests passed because they were not
run in the initial slice, while CI caught stale exact-count assertions. When a
provider is added, run `test/providers.test.ts` in the same change and update
its descriptive count assertions together with the registry.
