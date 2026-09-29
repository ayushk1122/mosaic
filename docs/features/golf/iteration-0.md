# Golf Iteration 0

**Owner:** Golf feature team
**Status:** Approved brief; 0A and 0B not implemented

## Goal

Prove one coherent Golf journey while preserving room for future Pursuits to own different information architecture and interactions.

## Iteration 0A — fixture-driven visual journey

**Decision:** 0A is a read-only, iPhone-primary comprehension and design review using deterministic local fixtures. It does not include capture or persistence.

### Fixture story

Fixtures span several months and connect:

- overview and current focus;
- practice history;
- contribution-style consistency over time;
- visible progress;
- sample rounds as story evidence, without round-entry UI;
- curated media that adds context and memory; and
- milestones that make meaningful change legible.

Exact people, dates, values, copy, media, and screen decomposition are not established.

### Acceptance criteria

- A reviewer can enter a Golf Pursuit from the minimum Pursuits shell and navigate a Golf-owned destination on iPhone.
- The elements above form one understandable longitudinal story.
- Sample rounds are visibly read-only evidence; no flow suggests round entry.
- The critical question can be evaluated: “After several months, can I see the story of getting better?”
- Hierarchy, terminology, tone, navigation, Dynamic Type basics, VoiceOver labels, and light/dark appearance can be reviewed.
- The journey has no account or network dependency.

**Experiment:** Determine whether the journey makes improvement legible and feels native to Golf rather than forced into a universal dashboard.

**Assumption:** Several months of deterministic fixture history can tell a credible story without data capture.

**Reversible choice:** Fixture values, route shape, screen decomposition, exact review device, and visual treatment may change after review.

### 0A non-goals

No data capture, practice entry, round logging, persistence selection, account, sync, backend, iPad-specific optimization, or generalized Pursuit schema is required. Implementing 0A is outside this documentation change.

## Iteration 0B — practice-session capture

**Decision:** 0B begins only after 0A review and adds a thin practice-session capture journey, not completed-round logging.

### Candidate record—not approved fields

The minimum record and language must be confirmed from 0A learning. Potential inputs such as date/time, focus, duration, location, notes, media, or outcomes are **open questions**, not requirements.

### Required behavior once fields are agreed

- one focused, accessible entry path;
- clear validation and error presentation;
- explicit cancel and save behavior;
- loading/saving, success, empty, and failure states appropriate to the chosen storage behavior;
- the saved session appears in the Golf progress story;
- storage is hidden behind a small Golf repository; and
- validation and derived summaries live in pure Golf domain code.

**Experiment:** Verify that a person can easily record the agreed minimal session and see it become part of the progress story.

**Open question:** Which fields, validation rules, summaries, and relaunch behavior make the smallest useful 0B?

**Reversible choice:** Persistence technology is selected only after those requirements are agreed.

## Deferred from Iteration 0

- completed-round logging, hole-by-hole scoring, detailed shot analytics, and official handicap;
- course discovery or provider integrations;
- accounts, cloud sync, collaboration, social feeds, and public profiles;
- user-added media and media pipelines;
- notifications, widgets, watch support, and monetization;
- Pursuit creation/customization UI and user-authored schemas;
- universal dashboards, generalized plugins, or server-driven UI.

## Closeout

Review accessibility, appearances, empty/error states, and the review-device boundary. Exercise the composition seam with a deliberately different mock Pursuit destination. Record findings and extract abstractions only when concrete evidence supports them.
