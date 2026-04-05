"use client";

import { useState } from "react";

import { LockIcon, GlobeIcon } from "@/components/icons";
import { Badge } from "@/components/ui/badge";
import { GoldButton } from "@/components/ui/gold-button";
import { OutlinedButton } from "@/components/ui/outlined-button";
import { serif } from "./fonts";

interface CreateProjectStateProps {
  onBack: () => void;
  onSubmit: (name: string, isPrivate: boolean) => void;
}

export function CreateProjectState({ onBack, onSubmit }: CreateProjectStateProps) {
  const [projectName, setProjectName] = useState("");
  const [isPrivate, setIsPrivate] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const slug = projectName
    .toLowerCase()
    .replace(/[^a-z0-9-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!slug) return;
    setSubmitting(true);
    setError("");
    try {
      onSubmit(slug, isPrivate);
    } catch {
      setError("Something went wrong. Please try again.");
      setSubmitting(false);
    }
  }

  return (
    <div className="mx-auto max-w-md space-y-8">
      <div className="space-y-4 text-center">
        <Badge>NEW PROJECT</Badge>
        <h1 className={`${serif.className} text-4xl font-semibold`}>
          Name Your Project
        </h1>
        <p className="text-base text-neutral-400">
          Give your project a name. This will be used to create your workspace on GitHub.
        </p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="space-y-2">
          <label htmlFor="project-name" className="block text-sm font-medium text-neutral-200">
            Project Name
          </label>
          <input
            id="project-name"
            type="text"
            required
            value={projectName}
            onChange={(e) => setProjectName(e.target.value)}
            placeholder="my-startup"
            className="w-full rounded-lg border border-neutral-700 bg-neutral-900 px-4 py-3 text-sm placeholder:text-neutral-500 focus:border-neutral-500 focus:outline-none"
          />
          {slug && (
            <p className="text-xs text-neutral-500">
              This becomes your project address on GitHub (e.g. github.com/you/{slug}).
            </p>
          )}
          {!slug && (
            <p className="text-xs text-neutral-500">
              This becomes your project address on GitHub (e.g. github.com/you/my-startup).
            </p>
          )}
        </div>

        <div className="space-y-2">
          <label className="block text-sm font-medium text-neutral-200">
            Visibility
          </label>
          <div className="flex overflow-hidden rounded-lg border border-neutral-700">
            <button
              type="button"
              onClick={() => setIsPrivate(true)}
              className={`flex flex-1 items-center justify-center gap-2 px-4 py-2.5 text-sm transition-colors ${
                isPrivate
                  ? "bg-neutral-800 text-neutral-100"
                  : "bg-transparent text-neutral-400 hover:text-neutral-200"
              }`}
            >
              <LockIcon className="h-4 w-4" />
              Private (recommended)
            </button>
            <button
              type="button"
              onClick={() => setIsPrivate(false)}
              className={`flex flex-1 items-center justify-center gap-2 border-l border-neutral-700 px-4 py-2.5 text-sm transition-colors ${
                !isPrivate
                  ? "bg-neutral-800 text-neutral-100"
                  : "bg-transparent text-neutral-400 hover:text-neutral-200"
              }`}
            >
              <GlobeIcon className="h-4 w-4" />
              Public
            </button>
          </div>
        </div>

        {error && <p role="alert" className="text-sm text-red-400">{error}</p>}

        <div className="flex items-center gap-3">
          <GoldButton type="submit" disabled={!slug || submitting}>
            {submitting ? "Creating..." : "Create Project"}
          </GoldButton>
          <OutlinedButton onClick={onBack}>Back</OutlinedButton>
        </div>
      </form>
    </div>
  );
}
