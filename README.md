# Mosaic

**Owner:** Mosaic team
**Status:** Iteration 0A visual-review implementation

Mosaic helps people capture the work they put into meaningful Pursuits and turn those moments into a visual story of progress.

## Current maturity

The repository contains a deterministic, local, read-only Iteration 0A experience. Home presents Golf, Fitness, Modeling, and Cooking as image-led Pursuits; only Golf opens a destination. Golf owns its June–September overview, progress story, season mosaic, sample rounds, milestone, and bundled fixture imagery. Practice capture, persistence, accounts, networking, and Iteration 0B remain unimplemented.

## Prerequisites

- macOS with Xcode capable of opening the current project format
- An installed iOS simulator compatible with the project's current deployment setting

The repository currently has no external package dependencies.

## Build and test

Open `Mosaic/Mosaic.xcodeproj` in Xcode, select the `Mosaic` scheme and an available iPhone simulator, then use **Product → Build** or **Product → Test**.

Command-line equivalents (replace the destination with an installed simulator):

```sh
xcodebuild build \
  -project Mosaic/Mosaic.xcodeproj \
  -scheme Mosaic \
  -destination 'platform=iOS Simulator,name=<installed iPhone>'

xcodebuild test \
  -project Mosaic/Mosaic.xcodeproj \
  -scheme Mosaic \
  -destination 'platform=iOS Simulator,name=<installed iPhone>'
```

## Documentation

- Product: [vision and principles](docs/product/vision-and-principles.md), [glossary](docs/product/glossary.md), and [Pursuit model](docs/product/pursuit-model.md)
- Design: [visual language](docs/design/visual-language.md)
- Feature: [Golf Iteration 0](docs/features/golf/iteration-0.md)
- Architecture: [overview](docs/architecture/overview.md)
- Decisions: [feature-owned Pursuit destinations](docs/decisions/0001-feature-owned-pursuit-destinations.md) and [deterministic fixtures for 0A](docs/decisions/0002-deterministic-local-fixtures-for-0a.md)
- Quality: [testing strategy](docs/quality/testing.md)

## Status labels

- **Decision:** settled direction
- **Reversible choice:** a selected approach intended to be inexpensive to change
- **Experiment:** a hypothesis that must be evaluated
- **Assumption:** a belief requiring validation
- **Open question:** intentionally unresolved
- **Current repository fact:** an observed implementation detail, not product approval

**Decision:** Golf is the first vertical slice; Iteration 0 begins with a fixture-driven visual review (0A), followed only later by practice-session capture (0B).

**Experiment:** Evaluate the implemented 0A journey against its comprehension question; evaluate 0B practice capture only after its fields and behavior are approved.
