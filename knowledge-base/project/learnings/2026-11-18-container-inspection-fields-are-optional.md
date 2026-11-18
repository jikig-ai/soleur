---
title: "Treat container inspection fields as optional"
date: 2026-11-18
category: workflow-issues
tags: [docker, inspection, verification]
related: []
---

# Learning: treat container inspection fields as optional

## Problem

An image inspection template accessed `.Config.User` directly, but the pinned
image omits that key and Docker's formatter exited with a template error.

## Solution

Read the inspection JSON and access optional fields with a fallback, while
printing only the specific metadata needed for the check. The retry confirmed
the image has no configured user, the expected entrypoint and command, and the
previously observed image digest.

## Key Insight

Image metadata fields are not guaranteed to exist; missing values must be
handled as part of the inspection.
