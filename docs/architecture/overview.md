# Architecture overview

**Owner:** Architecture
**Status:** Approved direction; implementation details remain reversible

## Stance

Use a thin Mosaic shell with feature-owned Pursuit destinations.

```text
Mosaic App / composition root
          |
          v
  Pursuits shell/catalog ------> PursuitsCore
          |
          v
  Pursuit destination seam
          |
          v
       Golf feature
  domain · state · UI · data
```

Dependencies point inward from the app composition root to small boundaries and concrete features. Golf may use shared Pursuit identity/display semantics; shared code must not depend on Golf.

## Boundaries

### App

Owns launch, top-level navigation, dependency composition, and a lightweight Pursuit catalog.

### PursuitsCore

Owns only demonstrated shared concepts: stable identity, type/kind identity, library display metadata, and lifecycle only after lifecycle states are confirmed.

### Golf

Owns Golf records, rules, repositories, state, screens, navigation within its destination, and presentation.

**Decision:** Golf rounds, scores, courses, and metrics stay Golf-owned until another Pursuit proves a reusable abstraction.

## Navigation and composition

**Decision:** The shell routes from the Pursuits entry point through a small destination boundary to a Golf-owned experience. See [ADR 0001](../decisions/0001-feature-owned-pursuit-destinations.md).

**Reversible choice:** The exact top-level navigation container and whether Golf is assembled at the boundary or supplies its whole destination.

**Open question:** Whether future Pursuits supply complete destinations or typed sections.

## State and dependencies

Prefer explicit, injectable feature state and dependencies. Avoid a global app object that accumulates every Pursuit.

**Assumption:** Direct concrete Swift types are sufficient for 0A; a plugin system or server-driven UI would add constraints without evidence.

## Data boundary

**Decision:** 0A uses deterministic, local, read-only fixtures with no account or network dependency. See [ADR 0002](../decisions/0002-deterministic-local-fixtures-for-0a.md).

**Decision:** 0B storage will be hidden behind a small Golf repository after capture fields and relaunch expectations are agreed.

**Open question:** The 0B persistence technology and relaunch guarantees.

**Reversible choice:** Fixture shape/content and eventual persistence implementation.

Eventual persisted practice sessions should have stable identifiers and account for schema evolution. This does not authorize a speculative universal activity schema.

## Testing seam

Fixtures must be deterministic. Test the critical 0A route; in 0B, test validation and summaries in pure Golf domain code and add one capture UI smoke journey. Details are in the [testing strategy](../quality/testing.md).

**Experiment:** At Iteration 0 closeout, route to a deliberately different mock Pursuit destination to test whether the seam preserves presentation freedom.
