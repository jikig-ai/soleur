"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

type Status = "idle" | "checking" | "valid" | "invalid" | "error";

export default function SetupKeyPage() {
  const router = useRouter();
  const [key, setKey] = useState("");
  const [status, setStatus] = useState<Status>("idle");
  const [errorMsg, setErrorMsg] = useState("");

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setStatus("checking");
    setErrorMsg("");

    try {
      const res = await fetch("/api/keys", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ key }),
      });

      if (!res.ok) {
        const body = await res.json().catch(() => null);
        setStatus("error");
        setErrorMsg(body?.error ?? "Something went wrong. Please try again.");
        return;
      }

      const body = await res.json();

      if (body.valid) {
        setStatus("valid");
        // Brief delay so the user sees the success state
        setTimeout(() => router.push("/connect-repo"), 600);
      } else {
        setStatus("invalid");
        setErrorMsg("Invalid API key. Please check and try again.");
      }
    } catch {
      setStatus("error");
      setErrorMsg("Network error. Please try again.");
    }
  }

  return (
    <main className="flex min-h-screen items-center justify-center p-4">
      <div className="w-full max-w-sm space-y-6">
        <div className="space-y-2 text-center">
          <h1 className="text-2xl font-semibold">Connect your API key</h1>
          <p className="text-sm text-neutral-400">
            Soleur uses your own Anthropic API key. It&apos;s encrypted at rest
            and never shared.
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <input
            type="password"
            required
            value={key}
            onChange={(e) => {
              setKey(e.target.value);
              if (status !== "idle" && status !== "checking") {
                setStatus("idle");
              }
            }}
            placeholder="sk-ant-..."
            className="w-full rounded-lg border border-neutral-700 bg-neutral-900 px-4 py-3 text-sm placeholder:text-neutral-500 focus:border-neutral-500 focus:outline-none"
          />

          {status === "checking" && (
            <p className="text-sm text-neutral-400">Checking...</p>
          )}
          {status === "valid" && (
            <p className="text-sm text-green-400">
              Key is valid. Redirecting...
            </p>
          )}
          {(status === "invalid" || status === "error") && (
            <p className="text-sm text-red-400">{errorMsg}</p>
          )}

          <button
            type="submit"
            disabled={status === "checking" || status === "valid"}
            className="w-full rounded-lg bg-white px-4 py-3 text-sm font-medium text-black hover:bg-neutral-200 disabled:opacity-50"
          >
            {status === "checking" ? "Validating..." : "Save key"}
          </button>
        </form>

        <p className="text-center text-xs text-neutral-500">
          Need a key?{" "}
          <a
            href="https://console.anthropic.com/settings/keys"
            target="_blank"
            rel="noopener noreferrer"
            className="text-neutral-300 hover:underline"
          >
            Get one from Anthropic
          </a>
        </p>
      </div>
    </main>
  );
}
