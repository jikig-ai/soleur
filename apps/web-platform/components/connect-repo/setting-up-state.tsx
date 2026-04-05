"use client";

import { CheckCircleIcon, SpinnerIcon } from "@/components/icons";
import { Badge } from "@/components/ui/badge";
import { GOLD_GRADIENT } from "@/components/ui/constants";
import { Card } from "@/components/ui/card";
import { serif } from "./fonts";
import type { SetupStep } from "./types";

interface SettingUpStateProps {
  steps: SetupStep[];
}

export function SettingUpState({ steps }: SettingUpStateProps) {
  return (
    <div className="mx-auto max-w-lg space-y-8">
      <div className="space-y-4 text-center">
        <Badge>SETTING UP</Badge>
        <h1 className={`${serif.className} text-4xl font-semibold`}>
          Setting up your AI team...
        </h1>
        <p className="text-base text-neutral-400">
          This usually takes less than a minute.
        </p>
      </div>

      {/* Progress bar */}
      <div className="h-1 overflow-hidden rounded-full bg-neutral-800">
        <div
          className="h-full rounded-full transition-all duration-700 ease-out"
          style={{
            background: GOLD_GRADIENT,
            width: `${
              ((steps.filter((s) => s.status === "done").length +
                (steps.some((s) => s.status === "active") ? 0.5 : 0)) /
                steps.length) *
              100
            }%`,
          }}
        />
      </div>

      {/* Step checklist */}
      <div className="space-y-3">
        {steps.map((step, i) => (
          <div key={i} className="flex items-center gap-3">
            {step.status === "done" && (
              <CheckCircleIcon className="h-5 w-5 shrink-0 text-green-400" />
            )}
            {step.status === "active" && (
              <SpinnerIcon className="h-5 w-5 shrink-0 text-amber-500/70" />
            )}
            {step.status === "pending" && (
              <div className="h-5 w-5 shrink-0 rounded-full border-2 border-neutral-600" />
            )}
            <span
              className={`text-sm ${
                step.status === "done"
                  ? "text-neutral-300"
                  : step.status === "active"
                    ? "text-neutral-100"
                    : "text-neutral-400"
              }`}
            >
              {step.label}
            </span>
          </div>
        ))}
      </div>

      {/* What happens next */}
      <Card>
        <h3 className="mb-2 text-sm font-medium text-neutral-200">What happens next</h3>
        <p className="text-xs text-neutral-500">
          Your AI team — marketing, engineering, legal, finance, and more —
          will have full context on your project from the first conversation.
        </p>
      </Card>

      <p className="text-center text-xs text-neutral-500">
        Your code stays in your GitHub account. Your AI team reads it —
        you decide what changes get made.
      </p>
    </div>
  );
}
