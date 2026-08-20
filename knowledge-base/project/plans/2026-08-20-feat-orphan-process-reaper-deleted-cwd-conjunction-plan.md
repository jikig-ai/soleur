---
title: "test-contention: no reaper exists for orphaned suite processes, and the fd-based discriminator is falsified as stated"
date: 2026-08-20
slug: feat-orphan-process-reaper-deleted-cwd-conjunction
branch: feat-one-shot-7537-orphan-process-reaper
issue: 7537
---

## Overview

Nothing in this repo terminates a *process* that has outlived its work. `scripts/tmpfs-guard.sh`
reclaims files and deliberately skips entries with open file descriptors, which is correct for a live
run and is exactly why an orphaned process survives it. The gap this plan closes is a suite process
whose working directory and executing script have both been unlinked out from under it, which keeps
consuming CPU and tmpfs on a shared box with its output unrecoverable by construction.

The difficulty is the discriminator, not the signal. A detached run and an orphaned one look
identical under `ps`. This plan builds a detector keyed on a narrow conjunction of deleted `/proc`
links, deliberately excluding the two signals that healthy processes on this box demonstrably
produce, and it fails toward leaving a process alive whenever the evidence is incomplete.
