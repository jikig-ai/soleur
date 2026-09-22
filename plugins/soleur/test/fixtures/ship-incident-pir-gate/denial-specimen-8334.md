# feat: a drift canary for the session hook

## Overview

The canary runs on every deployed host. Its value is narrower than the design claims: it
signals that the measurements have gone stale, not that the feature has stopped working.
