// SAFETY-CRITICAL isolation guard (ADR-109, CTO Option D test #4).
//
// The whole point of the SSE transport is that a support turn CANNOT disturb the
// paying Command Center WebSocket. That guarantee holds only while the support
// route + hook stay decoupled from the WS server internals. This test fails LOUDLY
// if a future edit reaches into ws-handler's per-user socket map or its WS
// `sendToClient`, re-introducing the supersession risk the CTO ruling avoids.
//
// Standalone source-read test (no mocks) per
// 2026-04-17-regex-on-source-delegation-tests-trim-to-negative-space.md.

import { readFileSync } from "fs";
import { resolve } from "path";
import { describe, it, expect } from "vitest";

const read = (rel: string) => readFileSync(resolve(__dirname, "..", rel), "utf8");

describe("support transport isolation from the Command Center WS", () => {
  const files = [
    "app/api/support/route.ts",
    "components/support/use-support-chat.ts",
    "lib/support-sse.ts",
    "server/support-conversation.ts",
  ];

  for (const f of files) {
    it(`${f} does not import ws-handler`, () => {
      const src = read(f);
      // No import from the WS handler module (its per-user `sessions` map +
      // supersedeExistingUserSocket live there — touching it risks CC).
      expect(src).not.toMatch(/from\s+["']@\/server\/ws-handler["']/);
      expect(src).not.toMatch(/from\s+["'][.\/]+ws-handler["']/);
    });
  }
});
