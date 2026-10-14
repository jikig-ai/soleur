"use client";

import { Suspense, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { usePendingAction } from "@/hooks/use-pending-action";
import { usePendingRouter } from "@/hooks/use-pending-router";
import { safeReturnTo } from "@/lib/safe-return-to";
import { PENDING_WATCHDOG_MS } from "@/hooks/use-pending-action";

type Status = "idle" | "checking" | "valid" | "invalid" | "error";

// CLO-approved factual disclosure (#4642 FR4) shown beside "Set up later":
// Soleur cannot run without the user's own key, and getting one is a separate,
// paid Anthropic account — never imply Soleur provides the key.
const SKIP_WARNING_COPY =
  "Soleur requires your own Anthropic API key to function. You can add it " +
  "anytime in Settings. Until then, tasks are disabled. Getting a key " +
  "requires a separate, paid Anthropic account.";

export default function SetupKeyPage() {
  return (
    <Suspense>
      <SetupKeyForm />
    </Suspense>
  );
}

function SetupKeyForm() {
  const router = usePendingRouter();
  const searchParams = useSearchParams();
  // Validated invite return target (e.g. /invite/<token>) threaded from
  // accept-terms for a keyless invitee. connect-repo is the terminal funnel
  // hop and consumes `return_to`, so bridge the auth-funnel `redirectTo` param
  // to connect-repo's `return_to` on the next push. null when absent/rejected.
  const redirectTo = safeReturnTo(searchParams.get("redirectTo"));
  const [key, setKey] = useState("");
  const [status, setStatus] = useState<Status>("idle");
  const [errorMsg, setErrorMsg] = useState("");

  // latch(): a successful skip ends in window.location.assign — the
  // pending flag must never release in the gap before the hard nav commits.
  const skip = usePendingAction(
    async () => {
      let res: Response;
      try {
        res = await fetch("/api/setup-key/skip", { method: "POST" });
      } catch {
        throw new Error("Network error. Please try again.");
      }
      if (!res.ok) {
        throw new Error("Couldn't save that. Please try again.");
      }
      // Terminal hop: honor the invite return target (#4641) else the
      // dashboard, where the NoApiKeyBanner + in-chat CTA cover the degraded
      // keyless state. Deliberately NOT /connect-repo: repo setup auto-fires a
      // headless sync agent that needs a key, which would orphan a stalled
      // conversation behind a misleading "ready" screen (#4642 review).
      // GAP E (ADR-067 staleTimes): terminal entry into /dashboard (or a
      // safeReturnTo-sanitized invite target) — hard-nav to wipe the Router
      // Cache. The intermediate hop to /connect-repo below stays a soft push.
      skip.latch();
      window.location.assign(redirectTo ?? "/dashboard");
    },
  );
  const skipping = skip.pending;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setStatus("checking");
    setErrorMsg("");

    try {
      const res = await fetch("/api/keys", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ key }),
        // feat-ui-action-feedback: pending must always terminate — a hung
        // POST leaves status="checking" forever, disabling BOTH onboarding
        // exits (Save + Set up later). Abort into the error arm instead.
        signal: AbortSignal.timeout(PENDING_WATCHDOG_MS),
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
        // Brief delay so the user sees the success state. Carry the invite
        // target forward as connect-repo's `return_to` so a new invitee lands
        // back on /invite/<token> after the final onboarding hop.
        setTimeout(
          () =>
            router.push(
              redirectTo
                ? `/connect-repo?return_to=${encodeURIComponent(redirectTo)}`
                : "/connect-repo",
            ),
          600,
        );
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
          <p className="text-sm text-soleur-text-secondary">
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
            className="w-full rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-4 py-3 text-base placeholder:text-soleur-text-muted focus:border-soleur-border-emphasized focus:outline-none md:text-sm"
          />

          {status === "checking" && (
            <p className="text-sm text-soleur-text-secondary">Checking...</p>
          )}
          {status === "valid" && (
            <p className="text-sm text-green-400">
              Key is valid. Redirecting...
            </p>
          )}
          {(status === "invalid" || status === "error") && (
            <p role="alert" className="text-sm text-red-400">{errorMsg}</p>
          )}

          <Button
            variant="gold"
            type="submit"
            loading={status === "checking"}
            loadingLabel="Validating"
            disabled={status === "valid" || skipping}
            className="w-full"
          >
            Save key
          </Button>
        </form>

        <div className="space-y-2 border-t border-soleur-border-default pt-4">
          {skip.error && (
            <p role="alert" className="text-sm text-red-400">
              {skip.error.message}
            </p>
          )}
          <Button
            variant="outlined"
            type="button"
            onClick={skip.run}
            loading={skip.pending}
            loadingLabel="Saving"
            disabled={status === "checking" || status === "valid"}
            className="w-full text-soleur-text-secondary"
          >
            Set up later
          </Button>
          <p className="text-xs text-soleur-text-muted">{SKIP_WARNING_COPY}</p>
        </div>

        <p className="text-center text-xs text-soleur-text-muted">
          Need a key?{" "}
          <a
            href="https://console.anthropic.com/settings/keys"
            target="_blank"
            rel="noopener noreferrer"
            className="text-soleur-text-secondary hover:underline"
          >
            Get one from Anthropic
          </a>
        </p>
      </div>
    </main>
  );
}
