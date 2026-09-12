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
    // PII-free: only the command HEAD, never a title/body.
    expect(r.commands).toEqual(["gh issue create", "gh api repos/jikig-ai/soleur/issues", "gh issue create"]);
    expect(JSON.stringify(r)).not.toContain("--title");
  });

  // The counter is the hook's OWN `filingShape` predicate (imported), so every
  // api spelling the gate denies is counted — the hand-mirrored regex this
  // replaced missed the first three (#8074 review) and counted the fourth.
  it("counts every api spelling the hook classifies as a filing, and no non-create endpoint", () => {
    const filing = [
      "gh api -X POST repos/jikig-ai/soleur/issues -f title=t",
      "gh api repos/jikig-ai/soleur/issues -f title=t -f body=b",
      "gh api --method POST /repos/jikig-ai/soleur/issues -f title=t",
      "gh api repos/jikig-ai/soleur/issues?labels=x -X POST",
      "gh api repos/jikig-ai/soleur/issues/ -XPOST",
      "gh api repos/jikig-ai/soleur/issues --input body.json",
    ];
    const notFiling = [
      "gh api repos/jikig-ai/soleur/issues/123/comments -X POST",
      "gh api repos/jikig-ai/soleur/issues",
      "gh api repos/jikig-ai/soleur/issues?state=open --paginate",
    ];
    const asDenials = (cmds: string[]) => cmds.map((command) => ({ tool_name: "Bash", tool_input: { command } }));
    expect(countFilingDenials(asDenials(filing)).count).toBe(filing.length);
    expect(countFilingDenials(asDenials(notFiling)).count).toBe(0);
  });

  it("head is the endpoint PATH only — query dropped, capped, one per command, no chain separator", () => {
    const long = "x".repeat(200);
    const r = countFilingDenials([
      { tool_name: "Bash", tool_input: { command: `gh api repos/jikig-ai/soleur/issues?title=${long} -X POST` } },
      { tool_name: "Bash", tool_input: { command: "gh issue create --title a; gh issue create --title b" } },
      { tool_name: "Bash", tool_input: { command: 'gh issue create --title "unbalanced' } },
    ]);
    expect(r.commands).toEqual(["gh api repos/jikig-ai/soleur/issues", "gh issue create"]);
    expect(r.count).toBe(2);
    expect(JSON.stringify(r)).not.toContain(long.slice(0, 8));
    expect(JSON.stringify(r)).not.toContain(";");
    expect(r.commands.every((h) => h.length <= 64 + "gh api ".length)).toBe(true);
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
    capture_status: "ok" as const,
  };

  it("emits one WARN line with the SOLEUR_CRON_FILING_DENY discriminator + fields", () => {
    emitCronFilingDenyMarker(m);
    expect(warnMock).toHaveBeenCalledTimes(1);
    const [obj, msg] = warnMock.mock.calls[0];
    expect(obj).toMatchObject({ SOLEUR_CRON_FILING_DENY: true, ...m });
    expect(msg).toBe("cron filing denied");
  });

  it("emits nothing at count 0 with a healthy capture (the marker is a positive signal, not a heartbeat)", () => {
    emitCronFilingDenyMarker({ ...m, count: 0, commands: [] });
    expect(warnMock).not.toHaveBeenCalled();
  });

  it("DOES emit at count 0 when the permission_denials field was absent (the deny channel went dark)", () => {
    emitCronFilingDenyMarker({ ...m, count: 0, commands: [], capture_status: "field-absent" });
    expect(warnMock).toHaveBeenCalledTimes(1);
    expect(warnMock.mock.calls[0][0]).toMatchObject({ SOLEUR_CRON_FILING_DENY: true, count: 0, capture_status: "field-absent" });
  });

  it("is fail-open: a throwing log.warn does not propagate", () => {
    warnMock.mockImplementation(() => {
      throw new Error("sink down");
    });
    expect(() => emitCronFilingDenyMarker(m)).not.toThrow();
  });
});
