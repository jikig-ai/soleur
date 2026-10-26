---
title: "chore(inngest): trim cloud-init-inngest.yml user_data by at least 500 B before the next host replace"
date: 2026-10-26
slug: trim-inngest-user-data-before-host-replace
branch: feat-one-shot-11080-inngest-userdata-trim
issue: 11080
---

## Overview

The Inngest host's rendered `user_data` sits 280 B under Hetzner's 32,768 B cap on current main, against a runbook precondition of 300 B of CI-rendered margin before a host replace. This change trims the template so a trial merge of main reaches at least 300 B of margin, with a target of at least 500 B removed offline. It is its own pull request, and it must neither replace nor dispatch anything on the Inngest host.
