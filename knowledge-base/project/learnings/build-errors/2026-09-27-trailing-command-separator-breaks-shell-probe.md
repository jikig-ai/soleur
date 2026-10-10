---
title: A trailing command separator makes a valid shell probe fail at parse time
date: 2026-09-27
category: build-errors
module: shell-probes
---

## Problem

A bounded repository inventory command ended with a trailing `&&` and Bash
returned `syntax error: unexpected end of file`. No part of the probe ran.

## Prevention

Before running a composed shell probe, inspect the final token as well as the
individual commands. Use `;` between independent checks, or keep dependent
commands in one valid `&&` chain without a dangling operator. Rerun the whole
probe after correcting syntax; never interpret parse failure as an empty result.
