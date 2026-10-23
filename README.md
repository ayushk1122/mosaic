# Mosaic

**Owner:** Mosaic team
**Status:** Working SwiftUI board editor with account-backed Supabase storage

Mosaic helps people capture the work they put into meaningful Pursuits and turn those moments into a visual story of progress.

## Current maturity

**Current repository fact:** The app contains a local board editor (Mosaic, Pursuits, nodes, and scrapbook pages), media and layout tools, Google sign-in, account-specific storage, Supabase uploads, discovery, profile settings, and sharing/access flows.

**Current repository fact:** Existing accounts open their cached boards without waiting for network refresh. On a new or starter-only installation, login downloads the main Mosaic board first and opens the editor; Pursuits, scrapbook pages, and media then download in the background. Interrupted downloads resume on reopening or Retry, and edits stay local until the remaining boards are present. See [account restoration and sync](docs/architecture/account-sync.md).

**Current repository fact:** Visits to other people’s boards open after access checks and layout loading, while media downloads per opened board. Repeat visits reuse unchanged media; failed files offer Retry without blocking navigation.

**Current repository fact:** Explore lists Mosaics and Pursuits their owners chose to share, with sorting and search. Profile and Pursuit cards handle following, and Discover marks followed boards that changed since you last opened them. See [Explore, cards, and following updates](docs/features/explore-and-following.md).

**Current repository fact:** The Content composer item links to YouTube videos, Instagram posts/reels, TikTok posts, and Twitch clips/VODs. It stores a preview cover with the board and opens the source link when tapped in view mode. Existing photo and 10-second video uploads remain supported.

The foundation product and architecture documents below describe the earlier Golf iteration and have not yet been reconciled with the implemented board editor. Their historical decisions are preserved; they are not a complete description of the current source tree.

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
- Features: [Golf Iteration 0](docs/features/golf/iteration-0.md) and [Explore, cards, and following updates](docs/features/explore-and-following.md)
- Architecture: [overview](docs/architecture/overview.md), [account restoration and sync](docs/architecture/account-sync.md)
- Decisions: [feature-owned Pursuit destinations](docs/decisions/0001-feature-owned-pursuit-destinations.md), [deterministic fixtures for 0A](docs/decisions/0002-deterministic-local-fixtures-for-0a.md), and [sync conflicts and the media queue](docs/decisions/0003-sync-conflict-and-media-queue.md)
- Quality: [testing strategy](docs/quality/testing.md)

## Status labels

- **Decision:** settled direction
- **Reversible choice:** a selected approach intended to be inexpensive to change
- **Experiment:** a hypothesis that must be evaluated
- **Assumption:** a belief requiring validation
- **Open question:** intentionally unresolved
- **Current repository fact:** an observed implementation detail, not product approval

**Decision:** Golf is the first vertical slice; Iteration 0 begins with a fixture-driven visual review (0A), followed only later by practice-session capture (0B).

**Experiment:** Validate the planned product behavior through the stated 0A comprehension review and 0B practice-capture review.
