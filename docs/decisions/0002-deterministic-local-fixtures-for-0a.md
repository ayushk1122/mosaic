# ADR 0002: Deterministic local fixtures for 0A

**Owner:** Product and Architecture
**Status:** Accepted for Iteration 0A
**Date:** 2026-09-29

## Context

Iteration 0A is a comprehension and design review of a longitudinal Golf story. Capture fields, relaunch behavior, accounts, synchronization, and backend requirements are not agreed. Introducing persistence or networking would couple the review to unresolved concerns.

## Decision

Use deterministic, local, read-only fixture data for 0A. The fixture story spans several months and covers current focus, practice history, consistency, progress, sample rounds, curated media, and milestones. It has no account or network dependency.

Do not select persistence in 0A. In 0B, place storage behind a small Golf repository only after practice-session fields and relaunch expectations are agreed.

## Consequences

- Reviews and tests can reproduce the same story.
- Product and visual learning can happen before storage design.
- Fixture data must not be mistaken for a production schema.
- Accounts, synchronization, backend work, and user-added media remain deferred.

## Status labels

**Reversible choice:** Fixture values, shape, and loading implementation.

**Assumption:** A deterministic story covering several months is sufficient to evaluate the 0A hypothesis.

**Experiment:** Ask reviewers, “After several months, can I see the story of getting better?”

**Open question:** Which 0B fields and relaunch guarantees will determine the eventual persistence choice?
