# ADR 0001: Feature-owned Pursuit destinations

**Owner:** Architecture
**Status:** Accepted
**Date:** 2026-09-29

## Context

Mosaic must support Pursuits with different information architecture and interaction patterns. Golf is the first concrete Pursuit, and the foundation must preserve optionality without predicting every future Pursuit.

## Decision

Use a thin app shell that owns launch, top-level navigation, dependency composition, and a lightweight Pursuit catalog. Route through the smallest practical destination seam to a Golf-owned experience. Golf owns navigation and presentation within that destination.

Keep shared Pursuit concepts limited to demonstrated identity and library metadata. Do not require a universal dashboard, card schema, plugin framework, or server-driven UI.

## Consequences

- Golf can use native domain language and hierarchy.
- The shell does not depend on Golf-specific records or presentation.
- A future Pursuit can present a different experience.
- Shared abstractions are extracted only after concrete reuse is demonstrated.

## Status labels

**Reversible choice:** The precise seam, top-level navigation container, and whether Golf supplies or is assembled into its destination.

**Assumption:** A small compile-time composition seam is enough for the first two iterations.

**Experiment:** At Iteration 0 closeout, exercise the seam with one deliberately different mock destination.

**Open question:** Whether evidence will favor complete feature destinations or typed, feature-owned sections.
