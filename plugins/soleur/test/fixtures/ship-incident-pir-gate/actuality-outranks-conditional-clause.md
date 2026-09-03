---
title: "fix: restore the release-outcome notification"
---

<!-- The claim sentence MUST carry BOTH an actuality idiom and a DROP_RE conditional
     (a `DROP_RE` conditional) on the SAME physical line. That collision is the whole point.
     This comment deliberately uses none of the report vocabulary: prose in a fixture is
     matched too, and a comment naming it would satisfy the assertion by itself. -->
# fix: restore the release-outcome notification

## Overview

The release-outcome step lost its env refs and the production pipeline stopped reporting.

## User-Brand Impact

**If this lands broken, the user experiences:** the pipeline silently stops taking new builds.
The outage already happened on 2026-07-30 and it would break every release again if reverted.
