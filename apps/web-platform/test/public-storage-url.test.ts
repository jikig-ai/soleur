import { describe, it, expect, afterEach, vi } from "vitest";
import { toPublicStorageUrl } from "@/lib/supabase/public-storage-url";

afterEach(() => vi.unstubAllEnvs());

describe("toPublicStorageUrl", () => {
  it("rewrites the raw <ref>.supabase.co host to NEXT_PUBLIC_SUPABASE_URL (CSP img-src host)", () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://api.soleur.ai");
    const raw =
      "https://ifsccnjhymdmidffkzhl.supabase.co/storage/v1/object/sign/chat-attachments/u/c/f.webp?token=abc";
    const out = toPublicStorageUrl(raw);
    expect(new URL(out).host).toBe("api.soleur.ai");
    // path + token preserved (origin-only rewrite)
    expect(out).toContain("/storage/v1/object/sign/chat-attachments/u/c/f.webp");
    expect(out).toContain("token=abc");
  });

  it("is a no-op when the host already matches the public base", () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://api.soleur.ai");
    const already = "https://api.soleur.ai/storage/v1/object/sign/x?token=z";
    expect(toPublicStorageUrl(already)).toBe(already);
  });

  it("returns the input unchanged when NEXT_PUBLIC_SUPABASE_URL is unset", () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "");
    const raw = "https://proj.supabase.co/storage/v1/object/sign/x?token=z";
    expect(toPublicStorageUrl(raw)).toBe(raw);
  });

  it("returns the input unchanged on a malformed URL", () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://api.soleur.ai");
    expect(toPublicStorageUrl("not a url")).toBe("not a url");
  });
});
