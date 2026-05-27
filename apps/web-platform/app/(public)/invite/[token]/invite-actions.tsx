"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";

interface Props {
  invitationId: string;
  token: string;
  isAuthenticated: boolean;
  expiresAt: string;
}

export function InviteActions({ invitationId, token, isAuthenticated, expiresAt }: Props) {
  const router = useRouter();
  const [loading, setLoading] = useState<"accept" | "decline" | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (!isAuthenticated) {
    return (
      <div className="space-y-3">
        <Link
          href={`/signup?redirectTo=/invite/${token}`}
          className="block w-full rounded-md bg-[#2563eb] px-4 py-3 text-center font-medium text-white hover:bg-[#1d4ed8] transition-colors"
        >
          Create an account to join
        </Link>
        <p className="text-center text-sm text-[#9a9a9a]">
          Already have an account?{" "}
          <Link href={`/login?redirectTo=/invite/${token}`} className="text-[#2563eb] hover:underline">
            Sign in
          </Link>
        </p>
      </div>
    );
  }

  async function handleAccept() {
    setLoading("accept");
    setError(null);
    try {
      const res = await fetch("/api/workspace/accept-invite", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ invitationId }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error ?? "Failed to accept invitation");
        return;
      }
      router.push("/dashboard/settings/team");
    } catch {
      setError("Network error. Please try again.");
    } finally {
      setLoading(null);
    }
  }

  async function handleDecline() {
    setLoading("decline");
    setError(null);
    try {
      const res = await fetch("/api/workspace/decline-invite", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ invitationId }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error ?? "Failed to decline invitation");
        return;
      }
      router.push("/dashboard");
    } catch {
      setError("Network error. Please try again.");
    } finally {
      setLoading(null);
    }
  }

  return (
    <div className="space-y-3">
      {error && (
        <p className="rounded-md bg-red-500/10 px-3 py-2 text-sm text-red-400">
          {error}
        </p>
      )}
      <button
        onClick={handleAccept}
        disabled={loading !== null}
        className="w-full rounded-md bg-[#2563eb] px-4 py-3 font-medium text-white hover:bg-[#1d4ed8] transition-colors disabled:opacity-50"
      >
        {loading === "accept" ? "Accepting..." : "Accept invitation"}
      </button>
      <button
        onClick={handleDecline}
        disabled={loading !== null}
        className="w-full rounded-md border border-[#2A2A2A] px-4 py-3 font-medium text-[#9a9a9a] hover:border-[#4a4a4a] hover:text-white transition-colors disabled:opacity-50"
      >
        {loading === "decline" ? "Declining..." : "Decline"}
      </button>
    </div>
  );
}
