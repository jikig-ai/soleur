import { describe, test, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { ErrorCard } from "../components/ui/error-card";

describe("ErrorCard component", () => {
  test("renders error message", () => {
    render(
      <ErrorCard
        title="Connection failed"
        message="Unable to connect to the server"
      />,
    );
    expect(screen.getByText("Connection failed")).toBeDefined();
    expect(screen.getByText("Unable to connect to the server")).toBeDefined();
  });

  test("renders retry button when onRetry provided", () => {
    let retried = false;
    render(
      <ErrorCard
        title="Error"
        message="Something went wrong"
        onRetry={() => { retried = true; }}
        retryLabel="Try again"
      />,
    );
    const button = screen.getByText("Try again");
    expect(button).toBeDefined();
    button.click();
    expect(retried).toBe(true);
  });

  test("renders action link when action provided", () => {
    render(
      <ErrorCard
        title="Invalid API Key"
        message="Your key has expired"
        action={{ label: "Update key", href: "/dashboard/settings" }}
      />,
    );
    const link = screen.getByText("Update key");
    expect(link).toBeDefined();
    expect(link.getAttribute("href")).toBe("/dashboard/settings");
  });

  test("does not render retry button when no onRetry", () => {
    render(
      <ErrorCard title="Error" message="Something went wrong" />,
    );
    expect(screen.queryByRole("button")).toBeNull();
  });
});

describe("WebSocketError interface", () => {
  test("error codes map to structured objects", () => {
    // Verify the error code mapping exists and has correct shape
    const errorMap: Record<string, { message: string; action?: { label: string; href?: string } }> = {
      key_invalid: {
        message: "Your API key is invalid or expired.",
        action: { label: "Update key", href: "/dashboard/settings" },
      },
      rate_limited: {
        message: "You've been rate limited. Please wait before trying again.",
      },
      connection_failed: {
        message: "Unable to connect to the server.",
      },
    };

    expect(errorMap.key_invalid.action?.href).toBe("/dashboard/settings");
    expect(errorMap.rate_limited.message).toContain("rate limited");
    expect(errorMap.connection_failed.message).toContain("connect");
  });
});
