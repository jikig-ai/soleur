---
title: "the mirror legal doc carries its own **Last Updated:** chain — moving canonical + hero but not the mirror chain fails legal-doc-consistency"
category: workflow-patterns
date: 2026-11-02
---

# The mirror legal doc carries its own `**Last Updated:**` chain

Each `plugins/soleur/docs/pages/legal/<doc>.md` has three date surfaces: the hero `<p>…Last Updated…</p>` AND its own `**Last Updated:**` chain that mirrors the canonical chain. Moving canonical's chain + the mirror hero but not the mirror's own chain fails `legal-doc-consistency.test.ts` (`expected 'October 29, 2026' to be 'November 2, 2026'`). Sync the mirror's whole `**Last Updated:**` line from canonical, not just the hero. Found in the #10848 compliance pipeline.
