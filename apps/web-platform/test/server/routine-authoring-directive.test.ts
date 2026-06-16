import { describe, it, expect } from "vitest";
import { ROUTINE_AUTHORING_DIRECTIVE } from "@/server/routine-authoring-directive";

describe("ROUTINE_AUTHORING_DIRECTIVE", () => {
  it("enumerates all four routine-creation edits (else a created routine never schedules)", () => {
    expect(ROUTINE_AUTHORING_DIRECTIVE).toContain("cron-");
    expect(ROUTINE_AUTHORING_DIRECTIVE).toMatch(/\{ cron:/); // schedule literal
    expect(ROUTINE_AUTHORING_DIRECTIVE).toContain("EXPECTED_CRON_FUNCTIONS");
    expect(ROUTINE_AUTHORING_DIRECTIVE).toContain("ROUTINE_METADATA");
    expect(ROUTINE_AUTHORING_DIRECTIVE).toMatch(/Inngest serve route|app\/api\/inngest/i);
  });

  it("frames create as propose-as-PR and never-fabricate-for-unmerged", () => {
    expect(ROUTINE_AUTHORING_DIRECTIVE).toMatch(/pull request/i);
    expect(ROUTINE_AUTHORING_DIRECTIVE).toMatch(/no .*create_routine.* tool|no `create_routine`/i);
    expect(ROUTINE_AUTHORING_DIRECTIVE).toMatch(/cannot run until.*merged/i);
    expect(ROUTINE_AUTHORING_DIRECTIVE).toMatch(/never fabricate/i);
  });

  it("conditions the create flow on a connected repo (no improvising)", () => {
    expect(ROUTINE_AUTHORING_DIRECTIVE).toMatch(/connect a (github )?repositor/i);
  });

  it("describes the run/verify loop via gated routine_run + routine_runs_list", () => {
    expect(ROUTINE_AUTHORING_DIRECTIVE).toContain("routine_run");
    expect(ROUTINE_AUTHORING_DIRECTIVE).toContain("routine_runs_list");
    expect(ROUTINE_AUTHORING_DIRECTIVE).toMatch(/gated/i);
    expect(ROUTINE_AUTHORING_DIRECTIVE).toMatch(/single confirmation/i);
  });

  it("contains NO gate-bypass phrasing (the review-gate is structural)", () => {
    expect(ROUTINE_AUTHORING_DIRECTIVE).not.toMatch(/auto-approve/i);
    expect(ROUTINE_AUTHORING_DIRECTIVE).not.toMatch(/without asking/i);
    expect(ROUTINE_AUTHORING_DIRECTIVE).not.toMatch(/skip (the )?confirmation/i);
    expect(ROUTINE_AUTHORING_DIRECTIVE).not.toMatch(/run without confirmation/i);
  });
});
