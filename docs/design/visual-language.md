# Visual language

**Owner:** Design
**Status:** Provisional guidance for 0A review

## Product expression

**Decision:** “Creativity in presentation. Simplicity in documentation.” Mosaic gives each Pursuit room for a fitting visual expression while keeping progress capture low-friction.

**Decision:** Golf should feel Golf-native rather than like generic dashboard cards with Golf labels.

## Guidance

### Color

Use a restrained neutral base and reserve color for hierarchy, progress, state, and Golf atmosphere. Never use color as the only carrier of meaning. Verify contrast in light and dark appearance.

**Reversible choice:** Exact palette and semantic color tokens will be selected during 0A visual exploration.

**Provisional example:** Pair a quiet system background with an evergreen accent for current focus and progress, plus a warm amber milestone accent. In a consistency grid, combine intensity with an accessible count or state so color is never the only signal.

### Typography

Use the platform text system and Dynamic Type. Favor a small, consistent hierarchy: clear page identity, scannable section titles, readable narrative, and tabular treatment where numeric comparison matters.

**Reversible choice:** Typeface, weight, and scale details are provisional.

**Provisional example:** Use semantic platform styles such as `largeTitle` for “My Golf,” `title2` for story chapters, `body` for narrative, and a monospaced-digit title style for comparable values. All styles scale with Dynamic Type.

### Spacing and surfaces

Use consistent spacing to reveal groups and sequence. Prefer content hierarchy over excessive containers. Surfaces should distinguish interaction or story chapters, not decorate every datum.

**Assumption:** A quieter shell will leave room for Pursuit-owned expression.

**Provisional example:** Start with an 8-point spacing rhythm, 16 points inside a grouped surface, and 24 points between story chapters. Let practice rows share one section surface; reserve a distinct surface for a milestone or current-focus callout.

### Imagery

Use imagery when it adds context, memory, or a sense of progression. Curated fixture media is allowed in 0A; user-added media and its pipeline are deferred. Provide meaningful accessibility descriptions or mark decorative imagery accordingly.

**Provisional example:** Place one fixture range photo beside its date and practice note to anchor a chapter in memory; use an accessibility description such as “Evening range session in light rain” rather than repeating nearby text.

### Motion

Use motion to preserve context or reveal change, not as a prerequisite for comprehension. Respect Reduce Motion and keep the experience complete without animation.

**Provisional example:** A short cross-fade may connect a selected month to its detail, while Reduce Motion presents the destination immediately. A progress value remains labeled before, during, and after any transition.

### Data display

Label values, time ranges, units, and derivation clearly. Use trends and consistency views only when fixture data supports them. Do not imply an official handicap or unsupported causation.

**Provisional example:** Show a 12-week practice grid with a labeled week range, session-count legend, and a text summary such as “18 sessions over 12 weeks.” Pair a trend with its dates and units; label a score as a fixture round, never as an official handicap.

### Accessibility

- Support Dynamic Type without truncating essential meaning.
- Provide VoiceOver labels and logical reading order.
- Meet platform contrast expectations in light and dark appearance.
- Keep controls identifiable without color alone.
- Respect Reduce Motion and comfortable target sizes.

**Provisional example:** Expose a grid cell as “Week of September 7, two practice sessions” and a milestone as one grouped element with title, date, and meaning. At large text sizes, stack metric labels and values instead of shrinking or truncating them.

## Golf tone

Golf should feel reflective, grounded, and encouraging: more like reviewing a season of deliberate work than judging a leaderboard. Overview, current focus, practice history, consistency, progress, sample rounds, media, and milestones should read as one story.

**Provisional example:** Open with “Working on consistent contact,” move through recent practice and a 12-week rhythm, then connect a sample round, range photo, and “First round under 90” milestone. Use observational copy such as “Practice became more consistent in August,” not judgmental streak or leaderboard language.

**Experiment:** In 0A, evaluate whether the hierarchy communicates “After several months, can I see the story of getting better?”

**Assumption:** Contribution-style consistency can reveal effort over time without becoming a streak-pressure mechanic.

**Open question:** Which visual treatment best joins practice, rounds, media, and milestones without flattening them into one card system?

**Open question:** The exact iPhone review size and all final tokens remain unresolved.
