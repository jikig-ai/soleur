---
adr: ADR-001
title: PWA-First Platform Architecture
status: active
date: 2026-03-27
---

# ADR-001: PWA-First Platform Architecture

## Context

Cloud platform must be accessible across web, mobile, and desktop without installation friction. Native apps add development cost and App Store gatekeeping.

## Decision

Deploy as a Progressive Web App (PWA). One Next.js codebase covers web browsers, mobile (installable PWA), and desktop (installable PWA). Native apps (Electron, React Native) deferred unless PWA hits real user limits.

## Consequences

Faster iteration with single codebase. iOS limitations (push notifications require 16.4+, no background execution, service worker cache evicted after ~14 days) require email fallback for notifications. Desktop users get installable PWA without Electron overhead.
