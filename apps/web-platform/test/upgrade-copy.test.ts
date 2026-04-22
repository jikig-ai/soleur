import { describe, test, expect } from "vitest";
import {
  defaultStateCopyFor,
  adminOverrideCopy,
  downgradeBannerCopy,
  AT_CAPACITY_BANNER,
  LOADING_COPY,
  ERROR_COPY,
} from "../components/concurrency/upgrade-copy";

describe("upgrade-copy", () => {
  test("Solo cap-hit title/subhead/CTA match copy artifact §1b", () => {
    const copy = defaultStateCopyFor("solo", 2);
    expect(copy.title).toBe("Both conversations are working.");
    expect(copy.subhead).toContain("Solo gives you 2 conversations at once");
    expect(copy.primaryCtaLabel).toBe("Upgrade to Startup — $149/mo");
    expect(copy.targetTier).toBe("startup");
  });

  test("Startup cap-hit routes to Scale @ $499/mo", () => {
    const copy = defaultStateCopyFor("startup", 5);
    expect(copy.title).toBe("All 5 of your conversations are working.");
    expect(copy.primaryCtaLabel).toBe("Upgrade to Scale — $499/mo");
    expect(copy.targetTier).toBe("scale");
  });

  test("Scale cap-hit has no targetTier (custom quota)", () => {
    const copy = defaultStateCopyFor("scale", 50);
    expect(copy.title).toBe("All 50 of your conversations are working.");
    expect(copy.primaryCtaLabel).toBe("Contact us for a custom quota");
    expect(copy.targetTier).toBeNull();
  });

  test("admin-override copy references a custom parallel set by the team", () => {
    const copy = adminOverrideCopy(100);
    expect(copy.title).toBe("All 100 of your conversations are working.");
    expect(copy.subhead).toContain("custom parallel set by our team");
    expect(copy.primaryCtaLabel).toBe("Email support");
  });

  test("at-capacity banner matches §3 short primary", () => {
    expect(AT_CAPACITY_BANNER.message).toBe(
      "Concurrent conversations now run per plan — see pricing.",
    );
    expect(AT_CAPACITY_BANNER.cta?.href).toBe("/pricing");
  });

  test("downgrade banner uses Option A (1-sentence)", () => {
    const banner = downgradeBannerCopy("solo");
    expect(banner.message).toBe(
      "You're now on Solo. Your running conversations will finish; new ones will start as soon as there's room.",
    );
  });

  test("loading + error copy exposed", () => {
    expect(LOADING_COPY.title).toBe("Opening checkout");
    expect(ERROR_COPY.title).toBe("Checkout didn't open.");
  });
});
