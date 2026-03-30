import "@testing-library/jest-dom/vitest";
import { afterEach } from "vitest";

afterEach(async () => {
  // Only cleanup DOM when running in a browser-like environment
  if (typeof document !== "undefined") {
    const { cleanup } = await import("@testing-library/react");
    cleanup();
  }
});
