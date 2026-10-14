# fix: restore the export job after the rollback

## Overview

We rolled back rather than patching; production went down for forty minutes before the
rollback finished, and this PR adds the missing readiness probe.
