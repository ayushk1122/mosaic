# Testing strategy

**Owner:** Engineering and Quality
**Status:** Approved foundation; gates activate with implemented behavior

## Test layers

1. **Domain unit tests:** Fast tests for Golf validation, calculations, and derived summaries. These become material in 0B.
2. **Feature/integration tests:** Verify fixture mapping, feature state, and shell-to-destination composition.
3. **UI smoke tests:** Cover the critical 0A visual route and, in 0B, one cancel/save capture journey. Keep UI tests few and deterministic.
4. **Manual visual and accessibility review:** Evaluate hierarchy, terminology, appearance, and assistive behavior that automation cannot fully judge.

**Decision:** Tests follow feature ownership. Shared tests must not force Golf domain behavior into a universal Pursuit model.

## Fixture policy

**Decision:** 0A fixtures are local, deterministic, read-only, and independent of accounts or networking.

- Use stable identities, dates, values, and ordering.
- Make the several-month narrative internally consistent.
- Keep fixture construction separate from production boundaries.
- Avoid random, clock-dependent, locale-fragile, or network-dependent assertions.
- Treat fixtures as review/test data, not as a persisted production schema.

**Reversible choice:** Exact fixture content and loading mechanism.

## Accessibility checks

For the critical journey, verify:

- Dynamic Type, including larger accessibility sizes;
- VoiceOver names, values, hints, traits, and reading order;
- light and dark appearance contrast;
- meaning without color alone;
- comfortable control targets;
- Reduce Motion behavior; and
- no loss of essential content from truncation.

## Devices and OS

**Decision:** 0A design and review are iPhone-primary; no iPad-specific optimization is required.

**Current repository fact:** The Xcode project currently targets iPhone and iPad and sets an iOS 26.5 deployment target. This documentation does not approve, change, or guarantee that deployment target or device support.

**Reversible choice:** Select and record one available iPhone simulator size for repeatable 0A review.

**Open question:** Supported OS versions, final device matrix, and the canonical review iPhone remain undecided.

## Review gates

### 0A

- The critical Golf route runs from Pursuits entry to the Golf-owned destination.
- Deterministic fixtures show the complete agreed story.
- A reviewer can evaluate “After several months, can I see the story of getting better?”
- Accessibility basics and light/dark appearance have been checked.
- No capture, persistence, account, network, or round-entry behavior is implied.

### 0B

- Practice fields and validation are explicitly approved.
- Domain validation and summaries have unit coverage.
- Cancel, save, validation error, and agreed relaunch behavior are tested.
- One UI smoke journey proves a saved session joins the progress story.

**Assumption:** One stable UI smoke path per critical journey provides useful integration confidence while most logic remains below the UI layer.

**Experiment:** Refine the gate based on defects and comprehension issues found during 0A review.

## Release gate

No production release criteria are established in Iteration 0. Before release, the team must define supported OS/devices, privacy disclosures, data handling, performance expectations, and regression gates.

**Open question:** What constitutes the first release candidate and which non-functional thresholds it must meet?
