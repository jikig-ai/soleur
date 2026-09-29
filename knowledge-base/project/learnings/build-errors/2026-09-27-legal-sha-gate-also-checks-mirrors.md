---
title: The legal SHA gate also verifies its documentation mirrors
date: 2026-09-27
category: build-errors
module: legal-document-validation
---

## Problem

Trying to run a separate Eleventy legal-mirror check failed because the assumed
script path did not exist. The maintained `apps/web-platform/scripts/check-tc-document-sha.sh`
already verifies canonical document hashes and normalized legal mirror parity.

## Prevention

Read the package's legal validation script before searching for a separate
mirror gate. Run `bash apps/web-platform/scripts/check-tc-document-sha.sh` for
the combined hash and mirror check, then run the focused legal document tests.
