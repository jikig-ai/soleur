---
title: Work skill must read prior-phase artifacts before implementing
date: 2026-03-25
scope: skills/work
tags: [workflow, design, phase-coupling]
---

## Context

During dogfood-pencil-headless (#656), Phase 1 produced a `.pen` wireframe with two pricing tier cards (Open Source $0, Hosted Pro $49/mo). Phase 2 (HTML/Eleventy) was implemented without reading the wireframe file, resulting in a page that diverged from the design — missing the $49 Pro tier entirely and replacing tier cards with a generic cost explainer.

## Learning

The `/work` skill has no instruction to read design artifacts (wireframes, mockups, `.pen` files) from prior phases before implementing HTML. When a multi-phase plan produces intermediate artifacts (Phase 1 wireframe -> Phase 2 HTML), each subsequent phase must treat the prior phase's output as a required input, not just the spec text.

## Recommendation

Add a pre-flight check to `/work` Phase 2 (Execute): when the task file references prior phases that produced design artifacts (`.pen`, `.fig`, screenshots), read those artifacts before writing any implementation code. The task loop should enforce "read wireframe -> extract structure -> implement" rather than "read spec -> invent structure -> implement."
