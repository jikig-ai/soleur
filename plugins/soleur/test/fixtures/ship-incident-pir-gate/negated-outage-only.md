# fix: tighten the retry budget on the webhook worker

## Overview

The webhook worker retried too eagerly under load in production. There was no outage;
this is preventive hardening of the retry budget, measured on a synthetic replay.
