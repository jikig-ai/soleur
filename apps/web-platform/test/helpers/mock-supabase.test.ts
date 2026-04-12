import { describe, expect, it, vi, beforeEach } from "vitest";
import { mockQueryChain } from "./mock-supabase";

describe("mockQueryChain", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("resolves to { data, error } when awaited without terminal (thenable)", async () => {
    const chain = mockQueryChain({ id: "123" });
    const result = await chain.select("*").eq("id", "123");
    expect(result).toEqual({ data: { id: "123" }, error: null });
  });

  it("resolves to { data, error } when awaited with .single() terminal", async () => {
    const chain = mockQueryChain({ id: "123" });
    const result = await chain.select().eq("id", "123").single();
    expect(result).toEqual({ data: { id: "123" }, error: null });
  });

  it("resolves with error when error is provided", async () => {
    const chain = mockQueryChain(null, { message: "not found" });
    const result = await chain.select().eq("id", "missing");
    expect(result).toEqual({ data: null, error: { message: "not found" } });
  });

  it("supports variable-depth chaining", async () => {
    const chain = mockQueryChain([{ id: "1" }, { id: "2" }]);
    const result = await chain.select("*").eq("org_id", "org1").order("created_at").limit(10);
    expect(result).toEqual({
      data: [{ id: "1" }, { id: "2" }],
      error: null,
    });
  });

  it("resets vi.fn() call counts on clearAllMocks", async () => {
    const chain = mockQueryChain({ id: "1" });
    await chain.select().eq("id", "1");
    expect(chain.select).toHaveBeenCalledTimes(1);

    vi.clearAllMocks();
    expect(chain.select).toHaveBeenCalledTimes(0);
  });

  it("supports insert/update/delete mutations", async () => {
    const chain = mockQueryChain({ id: "new" });
    const result = await chain.insert({ name: "test" }).select();
    expect(result).toEqual({ data: { id: "new" }, error: null });
  });
});
