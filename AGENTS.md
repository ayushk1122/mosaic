# Instructions for agents

**Owner:** Mosaic team
**Status:** Active repository guidance

## Start here

Read [README.md](README.md), then the documents relevant to the task:

- product intent and language: [vision and principles](docs/product/vision-and-principles.md), [glossary](docs/product/glossary.md), and [Pursuit model](docs/product/pursuit-model.md);
- experience direction: [visual language](docs/design/visual-language.md) and [Golf Iteration 0](docs/features/golf/iteration-0.md);
- engineering boundaries: [architecture overview](docs/architecture/overview.md), [ADRs](docs/decisions/), and [testing strategy](docs/quality/testing.md).

Repository documents are the durable source of truth. If implementation and documentation disagree, surface the conflict; do not silently invent a new product decision.

## Preserve decision status

- **Decision:** settled direction; implement consistently or record an approved replacement.
- **Reversible choice:** selected for now and intentionally inexpensive to change.
- **Experiment:** hypothesis to evaluate against stated acceptance criteria.
- **Assumption:** unverified belief; do not promote it to a requirement.
- **Open question:** unresolved; do not answer it implicitly in code or prose.
- **Current repository fact:** describes the checkout, not product approval.

Keep these labels explicit when adding or revising documentation. Write ADRs only for consequential, genuinely settled decisions; do not create ADRs for deployment target, persistence technology, or other unresolved choices.

## Settled product boundaries

- Pursuits are long-running, intentional areas of life and growth.
- Golf is the first vertical slice; Pursuits may own different information architecture and interaction patterns.
- Prefer concrete Golf needs over speculative shared schemas or frameworks.
- Keep Pursuits and activity private by default; any future sharing is intentional and opt-in.
- Apply “Creativity in presentation. Simplicity in documentation.” to expressive Pursuit storytelling and low-friction progress capture.

## Iteration 0 sequence

- **0A decision:** an iPhone-primary, read-only Golf visual journey using deterministic local fixtures. Sample rounds are story evidence, not a round-entry workflow.
- **0A experiment:** determine whether a reviewer can answer, “After several months, can I see the story of getting better?”
- **0B decision:** only after 0A review, add a thin practice-session capture journey.
- **Open questions:** 0B fields, validation, summaries, relaunch behavior, persistence technology, supported OS matrix, and Pursuit lifecycle states.
- **Deferred:** completed-round logging, official handicap, accounts/sync/backend, social features, user-added media pipelines, iPad-specific optimization, Pursuit authoring, and universal dashboard/plugin/server-driven UI systems.

Do not implement 0A or later scope during documentation-only work. Do not pull 0B or deferred behavior into 0A.

## Architecture and quality

Use a thin app shell with feature-owned Pursuit destinations. The approved shared boundary may include stable Pursuit identity, kind identity, and display metadata needed by the library. Keep lifecycle states unshared until confirmed, and keep Golf records, rules, state, repositories, metrics, and presentation Golf-owned; do not invent generic activity, card, metric, or dashboard behavior. Prefer explicit injectable state and dependencies over a global app object.

Treat the exact navigation container, composition mechanism, fixture shape, review-device size, and eventual persistence implementation as reversible. Follow the acceptance gates and deterministic-fixture policy in the [feature brief](docs/features/golf/iteration-0.md) and [testing strategy](docs/quality/testing.md).

**Decision:** Every new board component works with Orbit's update navigator (product owner, 2026-10-23). Before handing off a component, follow the [checklist for new components](docs/architecture/update-navigation.md#checklist-for-new-components):
- keep what people add in lists with ids, and add look and layout keys to `board_key_ignored`;
- anchor what the component shows with `updateAnchor`;
- give it a reveal host if it shows only part of what it holds;
- add the database and unit tests the checklist names.

## Change discipline

- Keep the change within the requested scope and preserve unrelated work.
- For documentation-only tasks, do not modify Swift/Xcode source or project files, dependencies, deployment target, bundle identifiers, or implement product behavior.
- Do not treat the current iOS 26.5 setting, iPhone/iPad target, Swift version, or bundle identifiers as settled product decisions.
- Update links and the documentation map when paths change.
- Before handoff, validate relative links, explicit status labels, changed-file scope, and `git diff --check`; report tests that could not run.
