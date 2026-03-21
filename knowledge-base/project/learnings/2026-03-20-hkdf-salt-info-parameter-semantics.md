---
title: "HKDF salt vs info parameter semantics (RFC 5869)"
date: 2026-03-20
category: security-issues
tags: [hkdf, encryption, cryptography, rfc-5869, key-derivation]
module: apps/web-platform/server/byok.ts
symptoms:
  - "HKDF-derived keys differ between implementations when salt/info are swapped"
  - "Encrypted data unrecoverable if wrong derivation parameters used"
---

# Learning: HKDF salt vs info parameter semantics

## Problem

During planning for BYOK per-user key derivation (#676), the spec incorrectly assigned `salt = user_id, info = "byok"`. This would have produced valid but wrong derived keys — data encrypted with the wrong derivation is permanently unrecoverable.

## Solution

RFC 5869 defines clear roles:

- **salt** (Extract phase): Strengthens non-uniform IKM. When IKM is already high-entropy random (e.g., 32-byte key from CSPRNG), empty salt is correct. Varying salt (e.g., with user_id) downgrades security from KDF-level to PRF-level per Soatok's analysis.
- **info** (Expand phase): Binds derived key to application context and identity. User identity, purpose, and version go here.

Correct: `hkdfSync('sha256', masterKey, Buffer.alloc(0), 'soleur:byok:' + userId, 32)`
Wrong: `hkdfSync('sha256', masterKey, userId, 'byok', 32)`

## Key Insight

Salt and info serve different cryptographic purposes and are not interchangeable. The mistake is easy to make because both accept arbitrary strings, both "work" (produce valid keys), and neither causes an error. The failure mode is silent data corruption — keys derived with swapped parameters are valid AES keys but cannot decrypt data encrypted with correctly-derived keys. Always reference RFC 5869 Sections 3.1 (salt) and 3.2 (info) when implementing HKDF.

## References

- [RFC 5869](https://datatracker.ietf.org/doc/html/rfc5869)
- [Soatok — Understanding HKDF](https://soatok.blog/2021/11/17/understanding-hkdf/)
- [Cendyne — How to Use HKDF](https://cendyne.dev/posts/2023-01-30-how-to-use-hkdf.html)
