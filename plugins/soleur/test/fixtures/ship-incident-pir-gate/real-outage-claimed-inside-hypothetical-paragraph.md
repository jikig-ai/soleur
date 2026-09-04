---
title: "fix: restore release-outcome notification"
brand_survival_threshold: single-user incident
---

<!-- The `production` token MUST stay in ## Overview, OUTSIDE the stripped paragraph.
     `PROD_RE` matches the whole haystack; a fixture whose only `prod` token is inside
     the paragraph reads `no` under both scripts and makes M2/M7 vacuous.
     Both tokens are BACKTICKED: the inline-code strip removes them before either matcher
     runs, so this comment cannot satisfy the conjunct it exists to warn about. -->

# fix: restore the release-outcome notification

## Overview

The release-outcome notification step lost its env refs and the production
pipeline stopped reporting.

## User-Brand Impact

**If this lands broken, the user experiences:** the pipeline silently stops taking
new builds while every surface reports healthy. The operator merges work for days
believing all is well. This already happened — the outage began ~2026-07-30 and no
notification was ever sent.
