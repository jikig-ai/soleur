# Spec: Operations Provisioner Agent

**Date:** 2026-02-22
**Issue:** #212
**Status:** Draft

## Problem Statement

When a new SaaS tool is chosen for the project (after evaluation via ops-research), the signup, payment, initial configuration, and verification steps are entirely manual. There is no agent-assisted workflow to guide users through account creation, ensure proper setup, verify the integration works, and record the expense.

## Goals

- G1: Provide a generic guided workflow for setting up any SaaS tool account
- G2: Use agent-browser to automate non-sensitive signup steps
- G3: Verify tool setup with browser screenshots and integration tests
- G4: Automatically record expenses via ops-advisor after successful setup

## Non-Goals

- NG1: Tool evaluation or alternative comparison (handled by ops-research)
- NG2: Entering credentials, passwords, or payment information
- NG3: Tool-specific recipes or per-tool setup scripts
- NG4: Managing ongoing tool administration or configuration changes

## Functional Requirements

- FR1: Agent accepts tool name, purpose, and signup URL as input
- FR2: Agent checks expenses.md for existing entries to prevent duplicate setup
- FR3: Agent navigates signup pages using agent-browser, filling non-sensitive fields
- FR4: Agent pauses for manual payment completion with clear instructions
- FR5: Agent resumes after payment to guide initial tool configuration
- FR6: Agent takes browser screenshots of the configured dashboard as verification
- FR7: Agent performs integration tests when applicable (e.g., visit site + check analytics)
- FR8: Agent invokes ops-advisor to record the new expense entry
- FR9: Agent makes corresponding code changes when tool setup requires them (e.g., update script tags, add env vars)
- FR10: Agent pauses for email verification loops with same pattern as payment pause

## Technical Requirements

- TR1: Agent definition at `plugins/soleur/agents/operations/ops-provisioner.md`
- TR2: Uses agent-browser for all web interaction (graceful degradation if unavailable)
- TR3: Follows existing safety patterns: never enters credentials, never clicks payment buttons
- TR4: Uses AskUserQuestion for all pause/confirmation points
- TR5: Follows ops-advisor conventions for expense recording (no $ symbols, ISO dates, category tags)
