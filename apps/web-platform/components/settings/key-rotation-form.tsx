"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

interface KeyRotationFormProps {
  hasExistingKey: boolean;
}

export function KeyRotationForm({ hasExistingKey }: KeyRotationFormProps) {
  const router = useRouter();
  const [apiKey, setApiKey] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!apiKey.trim()) return;

    setIsSubmitting(true);
    setError(null);
    setSuccess(false);

    try {
      const res = await fetch("/api/keys", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ key: apiKey }),
      });

      const data = await res.json();

      if (!res.ok) {
        setError(data.error || "Failed to save key");
        setIsSubmitting(false);
        return;
      }

      if (!data.valid) {
        setError("Invalid API key. Please check and try again.");
        setIsSubmitting(false);
        return;
      }

      setSuccess(true);
      setApiKey("");
      setIsSubmitting(false);
      router.refresh();
    } catch {
      setError("Network error. Please try again.");
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div>
        <label htmlFor="api-key-input" className="mb-2 block text-sm text-neutral-300">
          Anthropic API Key
        </label>
        <input
          id="api-key-input"
          type="password"
          value={apiKey}
          onChange={(e) => setApiKey(e.target.value)}
          placeholder="sk-ant-..."
          className="w-full rounded-lg border border-neutral-700 bg-neutral-900 px-3 py-2 text-sm text-white placeholder:text-neutral-400 focus:border-amber-600 focus:outline-none focus:ring-1 focus:ring-amber-600"
          autoComplete="off"
        />
      </div>

      {error && (
        <p role="alert" className="text-sm text-red-400">{error}</p>
      )}

      {success && (
        <p className="text-sm text-green-400">Key saved successfully.</p>
      )}

      <button
        type="submit"
        disabled={!apiKey.trim() || isSubmitting}
        className="rounded-lg bg-amber-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-amber-500 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {isSubmitting
          ? "Validating..."
          : hasExistingKey
            ? "Rotate Key"
            : "Save Key"}
      </button>
    </form>
  );
}
