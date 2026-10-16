# Pursuit model

**Owner:** Product and Architecture
**Status:** Approved semantic boundary; no implementation schema

## Shared semantics

**Decision:** A Pursuit is a long-running, intentional area of life and growth. It has stable identity and type/kind identity plus enough display metadata for a Pursuits library.

**Decision:** A Pursuit may contain goals, milestones, activities or sessions, media, notes, and metrics, but that list describes product possibilities rather than a universal storage schema.

**Decision:** People will eventually be able to create and customize Pursuits. That authoring experience is outside Iteration 0.

**Decision:** In the composer, folder widgets share one board model. Placement sets role: a folder on the Mosaic is a Pursuit; a folder inside a Pursuit is a Node. Copy pastes a new folder with the destination role; cut relocates the same document and updates its role. Nested folders inside a moved board keep their roles. Journal and scrapbook pages do not host folder widgets.

**Open question:** Which lifecycle states should become shared semantics?

## Pursuit-owned behavior

**Decision:** Each Pursuit owns domain-specific records, rules, summaries, vocabulary, interaction patterns, and presentation. The app shell must not require one universal Pursuit screen template.

Golf may organize around practice consistency, current focus, rounds, media, and milestones. A creative Pursuit might foreground works-in-progress, drafts, references, and a gallery. A fitness Pursuit might emphasize workouts, recovery, and trend ranges. These differences are product behavior, not labels applied to identical cards.

**Decision:** Golf records such as rounds, scores, courses, and Golf metrics remain Golf-owned until another concrete Pursuit demonstrates a stable shared abstraction.

**Non-goal:** This document does not define an exhaustive cross-Pursuit schema, generic metric/card database, plugin protocol, or server-driven UI.

## Evolution rule

1. Build the concrete Golf story.
2. Observe a second concrete need.
3. Extract only semantics that are stable across both.

**Assumption:** Stable identity, kind identity, and library display metadata will be sufficient for the first shell boundary.

**Experiment:** At Iteration 0 closeout, review the composition seam with a deliberately different mock Pursuit destination without shipping or deeply modeling that Pursuit.

**Reversible choice:** The exact representation of Pursuit identity, kind, and display metadata remains open until implementation.

**Open question:** Whether future Pursuits provide whole destinations or typed sections should be decided from concrete evidence.
