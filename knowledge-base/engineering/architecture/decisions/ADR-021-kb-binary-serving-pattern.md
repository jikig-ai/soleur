---
adr: ADR-021
title: KB binary-serving pattern — point-of-use re-validation and extension-fork routing
status: active
date: 2026-04-18
---

# ADR-021: KB binary-serving pattern — point-of-use re-validation and extension-fork routing

## Context

PR #2282 extended KB share beyond markdown to PDFs, images, CSVs, TXTs, and DOCX. The change introduced a public-unauthenticated endpoint (`/api/shared/[token]`) that serves arbitrary user-uploaded binaries from the workspace filesystem and reused the same helper from the authenticated owner endpoint (`/api/kb/content/[...path]`).

Two cross-cutting patterns emerged from the implementation that deserve to be a documented standard for every future KB-adjacent route (export, download-all, attachment streaming, etc.):

1. **Point-of-use re-validation.** Even when a path was validated upstream (at share-create time, via `kb_share_links.document_path`), `validateBinaryFile` in `apps/web-platform/server/kb-binary-response.ts` re-runs path containment, null-byte rejection, `O_NOFOLLOW` symlink rejection, regular-file check, and size check at every read. `openBinaryStream` re-opens with `O_NOFOLLOW` and validates the inode/size tuple via `expected: { ino, size }` to close a TOCTOU window between the validate fd and the serve fd. This is the service-role-IDOR learning applied to binaries.
2. **Extension-fork routing.** `serveKbFile(kbRoot, path, { onMarkdown, onBinary })` (in `apps/web-platform/server/kb-serve.ts`) dispatches by extension via `isMarkdownKbPath`. Both the owner route and the shared route call it with their own `onMarkdown`/`onBinary` handlers — a two-branch fork. As more file types gain rich rendering (DOCX → HTML, CSV → table, etc.), the fork could grow; the question is whether to keep it a two-branch fork or escalate to a dispatch table.

Per AGENTS.md and AP-011, cross-boundary architecture changes should be captured as ADRs. This pattern is now consumed by two routes and will be consumed by more. Documenting it lets future contributors stay inside the lines.

## Considered Options

- **Option A: Document the established pattern as-is (two-branch fork + point-of-use re-validation).** Codify what shipped in PR #2282 as the standard for all KB-adjacent routes. Pros: zero migration cost, the implementation is already battle-tested across two routes, the two-branch fork is YAGNI-compliant — there are only two kinds (markdown JSON vs. binary stream) and that distinction is unlikely to subdivide. Cons: when a third "kind" emerges (e.g., HTML-rendered DOCX), the fork has to evolve, and a future reader has to re-derive the dispatch decision.
- **Option B: Escalate to a dispatch table immediately (Map<extension, handler>).** Replace the two-branch fork with a registry of extension → handler pairs, keyed off `kb-file-kind.ts`. Pros: extensible without touching `serveKbFile`, the dispatch surface is data not code. Cons: speculative — the only shipped fork branches are markdown vs. binary, which already have fundamentally different response shapes (JSON body vs. byte stream); a handler table would force a uniform `(root, rel) => Response` signature that erases the per-route hash-gate, ETag, and Range concerns the current branches express.
- **Option C: Inline the validation per route (no shared helper).** Drop `kb-binary-response.ts` and let each route do its own validation. Pros: maximum local clarity. Cons: duplicates the security-critical TOCTOU guard, null-byte check, and `O_NOFOLLOW` open in two places where they will inevitably drift; this is exactly the failure mode the helper exists to prevent.

## Decision

**Option A.** The two patterns ship as the documented standard.

**Point-of-use re-validation rule.** Every KB-adjacent route that serves filesystem bytes MUST go through `validateBinaryFile` + `openBinaryStream` (or `readContent`/`readContentRaw` for markdown). Upstream validation (at share-create time, at upload time, in a database row) is treated as a hint, not as a security guarantee. The helpers in `apps/web-platform/server/kb-binary-response.ts` and `apps/web-platform/server/kb-reader.ts` are the only sanctioned entry points to KB filesystem reads from a route handler. New routes that bypass them require an ADR amendment.

**Extension-fork routing rule.** `serveKbFile(kbRoot, path, { onMarkdown, onBinary })` stays a two-branch fork. New "kinds" (HTML-rendered DOCX, table-rendered CSV, etc.) are layered inside `onBinary` via the `SharedContentKind` discriminator returned by `classifyByContentType` and the `X-Soleur-Kind` response header — they are response-shape variants of the binary branch, not new dispatcher branches. The fork escalates to a dispatch table only when (a) a new kind needs a fundamentally different request lifecycle (e.g., neither JSON nor a byte stream), or (b) the number of kind-specific branches inside `onBinary` exceeds three. Both triggers require a follow-up ADR.

**Consumer contract.** All future KB-adjacent routes (export, download-all, attachment serving, the KB viewer's tree-content fetch) MUST call `serveKbFile`. They MUST NOT re-implement the markdown-vs-binary fork inline. They MUST handle the same `instanceof` chain (`KbAccessDeniedError`, `KbNotFoundError`, `KbFileTooLargeError`, `BinaryOpenError`) so error semantics never drift.

## Consequences

**Easier:**

- New routes that need to serve a KB file inherit the full security posture (path containment, null-byte rejection, `O_NOFOLLOW`, TOCTOU close, size cap) by importing one helper.
- Hash-gating (`serveSharedBinaryWithHashGate`), Range support (HTTP 206), conditional GET (HTTP 304), and HEAD short-circuiting compose on top of `validateBinaryFile`/`openBinaryStream` without each route re-deriving them.
- The `SharedContentKind` discriminator is the single classifier — server, client viewer, and `X-Soleur-Kind` header all read from `classifyByContentType` so kind drift is impossible.
- Future audits have one place to look (`kb-binary-response.ts`) when tightening filesystem-read security.

**Harder:**

- The point-of-use re-validation is non-trivially expensive: every read does `open(O_NOFOLLOW)` + `fstat` + a second open with inode-equality check. For a hot path (e.g., a viewer that polls), this is a measurable cost. Mitigation: HTTP 304 short-circuit (`build304Response`) and `shareHashVerdictCache` skip the second open when the client's `If-None-Match` matches.
- The two-branch fork forces every new "kind" to fit inside `onBinary` until a third dispatch branch is justified. Contributors who want a new top-level branch must either justify the dispatch-table escalation in a follow-up ADR or restructure their feature to live under `onBinary`.
- Inlining a route-specific shortcut ("this path is from a trusted DB column, skip validation") is now a documented anti-pattern. Reviewers should flag it.

## Cost Impacts

None. This is a documentation decision over an already-shipped pattern. No new infrastructure, no new vendor, no new API usage.

## NFR Impacts

- **NFR-024 (Attack Prevention):** Improves from Partial to Implemented for KB filesystem reads. Point-of-use re-validation closes the validate-then-trust gap that an upstream-validated path could otherwise expose, and the inode-equality check on the second open closes the TOCTOU window between validate and serve.
- **NFR-041 (Link-Level Access Control):** Reinforces existing controls. The shared-token path runs the same validation as the owner path, so a public-unauthenticated link cannot bypass the security posture an authenticated request goes through.
- **NFR-008 (Low Latency):** Mild negative impact on the cold-cache path (extra `open` + `fstat`). Compensated on the warm path by HTTP 304 short-circuit and `shareHashVerdictCache` skip; a 304 response opens zero file descriptors.
- **NFR-001 (Logging):** Unchanged. Errors continue to flow through the `instanceof` chain and Pino logger.

## Principle Alignment

- **AP-011 (ADRs for architecture decisions): Aligned** — this ADR captures a cross-boundary pattern consumed by two routes and standardizes the contract for all future KB-adjacent routes.
- **AP-010 (Convention over configuration for paths): Aligned** — extension-based routing (`isMarkdownKbPath`, `getKbExtension`, `CONTENT_TYPE_MAP`) is a convention, not per-route configuration. The two-branch fork keeps the convention legible.
- **AP-006 (All knowledge in committed repo files): Aligned** — pattern is captured in the committed ADR and the two helper modules, not in tribal knowledge.

## Diagram

```mermaid
flowchart TD
    OwnerReq["GET /api/kb/content/[...path]<br/>(authenticated)"] --> ServeKbFile
    SharedReq["GET /api/shared/[token]<br/>(public)"] --> PrepareShared["prepareSharedRequest:<br/>rate-limit, share row,<br/>If-None-Match short-circuit"]
    PrepareShared --> ServeKbFile

    ServeKbFile{{"serveKbFile(kbRoot, path,<br/>{ onMarkdown, onBinary })"}}
    ServeKbFile -->|isMarkdownKbPath| OnMd["onMarkdown handler<br/>(readContent / readContentRaw)"]
    ServeKbFile -->|else| OnBin["onBinary handler"]

    OnBin --> Validate["validateBinaryFile<br/>(O_NOFOLLOW open + fstat:<br/>null-byte, path-containment,<br/>symlink, regular-file, size)"]
    Validate -->|metadata: ino, size, mtimeMs| HashGate{"hash gate?<br/>(shared route only)"}
    HashGate -->|yes| ShareHashGate["serveSharedBinaryWithHashGate<br/>(verdict cache + SHA-256)"]
    HashGate -->|no| BuildResp["buildBinaryResponse"]
    ShareHashGate --> BuildResp
    BuildResp --> OpenStream["openBinaryStream<br/>(O_NOFOLLOW + expected{ino,size}<br/>= TOCTOU close)"]
    OpenStream --> Response[("HTTP 200 / 206 / 304 / 416<br/>+ X-Soleur-Kind<br/>+ ETag + Cache-Control")]

    OnMd --> MdResponse[("HTTP 200 JSON<br/>+ X-Soleur-Kind: markdown")]
```
