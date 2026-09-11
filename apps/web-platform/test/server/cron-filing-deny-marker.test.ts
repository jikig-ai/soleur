// #8076 — the SOLEUR_CRON_FILING_DENY marker. A PreToolUse hook deny lands in
// the `claude --print --output-format json` result event's `permission_denials[]`
// (measured 2026-09-11); the substrate counts the filing-shaped ones and emits
// ONE WARN marker per run so Better Stack shows the deny the interactive gate
// records in its incident log. Same fail-open, WARN-level, PII-free contract as
// SOLEUR_CLAUDE_COST (claude-cost-marker.ts).
import { afterEach, describe, expect, it, vi } from "vitest";

const { warnMock } = vi.hoisted(() => ({ warnMock: vi.fn() }));
vi.mock("pino", () => ({
  default: vi.fn(() => ({ warn: warnMock })),
}));

import {
  countFilingDenials,
  emitCronFilingDenyMarker,
} from "@/server/cron-filing-deny-marker";

afterEach(() => {
  warnMock.mockReset();
});

describe("countFilingDenials", () => {
  it("counts only filing-shaped Bash denials (gh issue create, gh api …/issues -X POST)", () => {
    const denials = [
      { tool_name: "Bash", tool_input: { command: "gh issue create --title t --body b" } },
      { tool_name: "Bash", tool_input: { command: "gh api repos/jikig-ai/soleur/issues -X POST -f title=t" } },
      { tool_name: "Bash", tool_input: { command: "gh issue list --label x" } },
      { tool_name: "Bash", tool_input: { command: "cat /proc/self/environ" } },
      { tool_name: "Read", tool_input: { file_path: "/etc/passwd" } },
      { tool_name: "Bash", tool_input: { command: "gh issue list && gh issue create --title t" } },
    ];
    const r = countFilingDenials(denials);
    expect(r.count).toBe(3);
    // PII-free: only the command HEAD (first three tokens), never a title/body.
    expect(r.commands).toEqual(["gh issue create", "gh api repos/jikig-ai/soleur/issues", "gh issue create"]);
    expect(JSON.stringify(r)).not.toContain("--title");
  });

  it("returns 0 on an empty, absent, or malformed array", () => {
    expect(countFilingDenials([]).count).toBe(0);
    expect(countFilingDenials(undefined).count).toBe(0);
    expect(countFilingDenials("nope" as unknown as unknown[]).count).toBe(0);
    expect(countFilingDenials([{ tool_name: "Bash" }, null, 42]).count).toBe(0);
  });
});

describe("emitCronFilingDenyMarker", () => {
  const m = {
    fn: "cron-community-monitor",
    run_id: "01ABC",
    spawn_started_at: "2026-09-12T08:00:00.000Z",
    count: 2,
    commands: ["gh issue create", "gh issue create"],
  };

  it("emits one WARN line with the SOLEUR_CRON_FILING_DENY discriminator + fields", () => {
    emitCronFilingDenyMarker(m);
    expect(warnMock).toHaveBeenCalledTimes(1);
    const [obj, msg] = warnMock.mock.calls[0];
    expect(obj).toMatchObject({ SOLEUR_CRON_FILING_DENY: true, ...m });
    expect(msg).toBe("cron filing denied");
  });

  it("emits nothing at count 0 (the marker is a positive signal, not a heartbeat)", () => {
    emitCronFilingDenyMarker({ ...m, count: 0, commands: [] });
    expect(warnMock).not.toHaveBeenCalled();
  });

  it("is fail-open: a throwing log.warn does not propagate", () => {
    warnMock.mockImplementation(() => {
      throw new Error("sink down");
    });
    expect(() => emitCronFilingDenyMarker(m)).not.toThrow();
  });
});
