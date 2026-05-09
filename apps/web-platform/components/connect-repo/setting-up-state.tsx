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
        <p className="text-base text-soleur-text-secondary">
          This usually takes less than a minute.
        </p>
      </div>

      {/* Progress bar */}
      <div className="h-1 overflow-hidden rounded-full bg-soleur-bg-surface-2">
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
              <SpinnerIcon className="h-5 w-5 shrink-0 text-soleur-accent-gold-fg/70" />
            )}
            {step.status === "pending" && (
              <div className="h-5 w-5 shrink-0 rounded-full border-2 border-soleur-border-default" />
            )}
            <span
              className={`text-sm ${
                step.status === "done"
                  ? "text-soleur-text-secondary"
                  : step.status === "active"
                    ? "text-soleur-text-primary"
                    : "text-soleur-text-secondary"
              }`}
            >
              {step.label}
            </span>
          </div>
        ))}
      </div>

      {/* What happens next */}
      <Card>
        <h3 className="mb-2 text-sm font-medium text-soleur-text-primary">What happens next</h3>
        <p className="text-xs text-soleur-text-muted">
          Your AI team — marketing, engineering, legal, finance, and more —
          will have full context on your project from the first conversation.
        </p>
      </Card>

      <p className="text-center text-xs text-soleur-text-muted">
        Your code stays in your GitHub account. Your AI team reads it —
        you decide what changes get made.
      </p>
    </div>
  );
}
