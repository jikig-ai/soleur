import { describe, it, expect } from "vitest";
import {
  stripUserContextFromEvent,
  scrubJwtFromEvent,
} from "@/sentry.client.config";
import { PII_KEY_RE } from "@/lib/client-observability";

describe("PII_KEY_RE source of truth", () => {
  it("is shared between client-observability and sentry.client.config (anchored, case-insensitive)", () => {
    // Smoke test against the import — if anyone forks the constant into
    // a private literal in `sentry.client.config.ts`, the canonical
    // shape assertions below will still pass for whichever copy stays
    // hooked up, but this assertion locks the canonical regex source.
    expect(PII_KEY_RE.source).toBe("^user_?id$|^email$");
    expect(PII_KEY_RE.flags).toContain("i");
  });
});

describe("sentry.client.config beforeSend stripUserContext", () => {
  it("zeros event.user.{id,email,username,ip_address}", () => {
    const event = {
      user: {
        id: "u1",
        email: "a@b.com",
        username: "alice",
        ip_address: "1.2.3.4",
      },
    } as never;
    const out = stripUserContextFromEvent(event) as {
      user?: Record<string, unknown>;
    };
    expect(out.user?.id).toBeUndefined();
    expect(out.user?.email).toBeUndefined();
    expect(out.user?.username).toBeUndefined();
    expect(out.user?.ip_address).toBeUndefined();
  });

  it("strips userId / user_id / email from event.extra", () => {
    const event = {
      extra: {
        userId: "u1",
        user_id: "u2",
        email: "a@b.com",
        segment: "kept",
      },
    } as never;
    const out = stripUserContextFromEvent(event) as {
      extra?: Record<string, unknown>;
    };
    expect(out.extra?.userId).toBeUndefined();
    expect(out.extra?.user_id).toBeUndefined();
    expect(out.extra?.email).toBeUndefined();
    expect(out.extra?.segment).toBe("kept");
  });

  it("strips userId from event.contexts.<any>", () => {
    const event = {
      contexts: {
        user: { userId: "u1", role: "kept" },
        auth: { user_id: "u2", session: "kept" },
      },
    } as never;
    const out = stripUserContextFromEvent(event) as {
      contexts?: {
        user?: Record<string, unknown>;
        auth?: Record<string, unknown>;
      };
    };
    expect(out.contexts?.user?.userId).toBeUndefined();
    expect(out.contexts?.user?.role).toBe("kept");
    expect(out.contexts?.auth?.user_id).toBeUndefined();
    expect(out.contexts?.auth?.session).toBe("kept");
  });

  it("strips userId from event.breadcrumbs[*].data", () => {
    const event = {
      breadcrumbs: [
        { data: { userId: "u1", url: "kept" } },
        { data: { email: "a@b.com" } },
      ],
    } as never;
    const out = stripUserContextFromEvent(event) as {
      breadcrumbs?: Array<{ data?: Record<string, unknown> }>;
    };
    expect(out.breadcrumbs?.[0]?.data?.userId).toBeUndefined();
    expect(out.breadcrumbs?.[0]?.data?.url).toBe("kept");
    expect(out.breadcrumbs?.[1]?.data?.email).toBeUndefined();
  });

  it("leaves events without PII keys unchanged", () => {
    const event = {
      extra: { segment: "dashboard" },
      contexts: { app: { name: "soleur" } },
    } as never;
    const out = stripUserContextFromEvent(event) as {
      extra?: Record<string, unknown>;
      contexts?: { app?: Record<string, unknown> };
    };
    expect(out.extra?.segment).toBe("dashboard");
    expect(out.contexts?.app?.name).toBe("soleur");
  });

  it("handles all-undefined optional fields without throwing", () => {
    const event = {} as never;
    expect(() => stripUserContextFromEvent(event)).not.toThrow();
  });

  it("strip alone leaves event.message untouched (one direction of independence)", () => {
    const event = {
      message: "boom",
      extra: { userId: "u1" },
    } as never;
    const out = stripUserContextFromEvent(event) as {
      message?: string;
      extra?: Record<string, unknown>;
    };
    expect(out.extra?.userId).toBeUndefined();
    expect(out.message).toBe("boom");
  });

  it("JWT-scrub alone leaves event.extra.userId untouched (other direction)", () => {
    const event = {
      message: "boom",
      extra: { userId: "u1" },
    } as never;
    const out = scrubJwtFromEvent(event) as {
      message?: string;
      extra?: Record<string, unknown>;
    };
    // Strip is independent of JWT scrub — if a refactor wired scrub into
    // user-context stripping, this assertion would fail.
    expect(out.extra?.userId).toBe("u1");
    expect(out.message).toBe("boom");
  });

  it("composed beforeSend handles JWT in message AND userId in extra", () => {
    // Synthesized fake JWT (3 base64url segments, "eyJ"-prefixed). Same
    // shape used by `sentry-client-jwt-scrub.test.ts` fixtures.
    const FAKE_JWT =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSJ9.synthesized-signature-for-test"; // gitleaks:allow # synthesized
    const event = {
      message: `boom (preview: ${FAKE_JWT})`,
      extra: { userId: "u1", segment: "kept" },
    } as never;
    // Mirror the beforeSend chain order in `sentry.client.config.ts`.
    const out = stripUserContextFromEvent(scrubJwtFromEvent(event)) as {
      message?: string;
      extra?: Record<string, unknown>;
    };
    expect(out.message).toContain("<jwt-redacted>");
    expect(out.message).not.toContain("eyJ");
    expect(out.extra?.userId).toBeUndefined();
    expect(out.extra?.segment).toBe("kept");
  });

  it("handles undefined breadcrumb data entries without throwing", () => {
    const event = {
      breadcrumbs: [
        { data: undefined },
        { data: { userId: "u1" } },
      ],
    } as never;
    const out = stripUserContextFromEvent(event) as {
      breadcrumbs?: Array<{ data?: Record<string, unknown> }>;
    };
    expect(out.breadcrumbs?.[1]?.data?.userId).toBeUndefined();
  });

  it("matches case-insensitive userId variants in event.extra", () => {
    const event = {
      extra: { UserID: "u1", USERID: "u2", segment: "kept" },
    } as never;
    const out = stripUserContextFromEvent(event) as {
      extra?: Record<string, unknown>;
    };
    expect(out.extra?.UserID).toBeUndefined();
    expect(out.extra?.USERID).toBeUndefined();
    expect(out.extra?.segment).toBe("kept");
  });
});
