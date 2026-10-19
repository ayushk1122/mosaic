# Mosaic beta-readiness review
**Owner:** Mosaic team
**Status:** Review findings and recommendations; not a launch approval
**Reviewed:** October 16, 2026 (America/New_York)
**Checkout:** `0c4de5e13e0f7b6748178c29ad0f76b8cf1a5455`
**Live backend:** Mosaic-dev / dnejxyohyzpwfjmnnarq; read-only inspection

## Assessment
**Recommendation:** Hold an external beta until the authorization and data-integrity findings are resolved. Continue internal testing with disposable/non-sensitive fixtures. Mosaic is a working, feature-rich early product with useful restoration tests, but its current sync and database-write boundaries are not yet a safe beta foundation.

SwiftUI + Supabase/Postgres remains a reasonable direction. This review does not justify microservices, sharding, or a rewrite. It does justify explicit document versioning/deletions, a testable sync state machine, server-enforced invariants, a bounded media pipeline, and operational release gates.

This review covers source, live schema/functions/policies/grants, bucket configuration, job state, migration drift, and current tests. It is not a penetration-test certificate or a capacity certification. No production data, policies, migrations, users or configuration were changed. No user media or credentials were downloaded. Prior chat claims were not taken as proof.

## Evidence and test status
- **Current repository fact:** Debug simulator build and **109 unit tests passed**, iPhone 18 Pro / iOS 27.0.
- **Current repository fact:** Functional UI smoke run: launch/navigation passed; Circle/Discover background editing passed; scroll-bubble test failed at MosaicUITests.swift:97 (54% instead of 100%). The isolated retry failed at the same assertion (54% instead of 100%).
- **Current repository fact:** 10 public tables, all with RLS; 3 profiles, 29 documents, 196 media assets, 196 queued media jobs, 28 processing assets, 28 visit rows at initial inspection. Counts are point-in-time observations.
- **Current repository fact:** 16 live migrations, 7 local migration files; latest live role-move migration is missing locally.
- **Current repository fact:** Both Storage buckets are private. Avatars enforce JPEG / 5 MiB; media has no bucket-specific MIME or file-size restriction. Project/global limits were not verified.
- **Current repository fact:** 34 media Storage objects have no media_assets row matching original/display/thumb paths. They need classification before any cleanup.
- **Current repository fact:** No anonymous caller can execute public SECURITY DEFINER functions. All public tables inspected have RLS.
- **Current repository fact:** No malformed cross-owner parents or mismatched request owners were found in the current data. This does not remove the policy flaw.
- **Current repository fact:** No Edge Functions are deployed; pg_cron is not installed. An external worker/scheduler has not been ruled out.
- Source and sanitized live function definitions accompany this report in `2026-10-16-backend-evidence.sql`.
- Unit log: /tmp/mosaic-codex-review-unit.log; result: /tmp/mosaic-codex-review-unit.xcresult.
- UI log: /tmp/mosaic-codex-review-ui.log; result: /tmp/mosaic-codex-review-ui.xcresult.
- No physical-device, Release archive, signed-in end-to-end, load, accessibility, backup restoration, or exploit test was completed.

## Findings
P1 means a high-priority beta gate; P2 means a material reliability, security, release-readiness or scaling gap. These labels include engineering release gates as well as reproducible code defects; each entry states its evidence level.

### SEC-01 · P1 · Request owners can forge approval for another owner's private Pursuit
**Area:** Security
**Location:** [supabase/migrations/20261014213723_security_advisor_fixes.sql:139](/Users/ayushkrishnappa/mosaic/supabase/migrations/20261014213723_security_advisor_fixes.sql:139)

**Evidence:** Live pursuit_access_update_owner checks only owner_id = auth.uid() before and after UPDATE. authenticated has UPDATE on pursuit_id, requester_id and status. No composite ownership constraint or request-update trigger binds pursuit_id to owner_id. viewer_can_open_pursuit trusts pursuit_id + requester_id + accepted status without validating request.owner_id.

**Impact / trigger:** Two cooperating accounts can use an incoming request owned by account A, retarget it to account C's private Pursuit, and approve account B. If B passes C's Mosaic gate and knows the Pursuit ID, server-side board/media access can be granted without C's approval. The client following check is bypassable by calling follow_pursuit or reading the RPC directly.

**Recommended fix:** Revoke direct request-table updates and funnel state transitions through owner-validated RPCs; bind each Pursuit request to the document's actual owner with constraints/triggers; validate that binding in read helpers. Add adversarial three-account tests.

**Validation boundary:** Confirmed from live policies/grants/constraints/functions; exploit not executed. Zero mismatched request owners currently stored.


### SYNC-01 · P1 · Conflict recovery overwrites the latest server document
**Area:** Data integrity
**Location:** [Mosaic/Mosaic/Composer/Sync/ComposerRemoteSync.swift:317](/Users/ayushkrishnappa/mosaic/Mosaic/Mosaic/Composer/Sync/ComposerRemoteSync.swift:317)

**Evidence:** On revisionConflict, save reads only the current revision and resubmits the unchanged local document with that revision. Established cached accounts skip restore, and shell launch schedules an upload.

**Impact / trigger:** Device B edits a board; later device A opens its stale cached copy. A's launch sync can overwrite B's newer content without conflict UI or a merge.

**Recommended fix:** Preserve conflicting local data; pull and reconcile server state before overwriting. Use a durable base revision and explicit conflict policy. Upload only genuinely dirty documents.

**Validation boundary:** Source-confirmed execution path; multi-device reproduction not run.


### SYNC-02 · P1 · Absence in a stale snapshot is treated as a remote deletion
**Area:** Data integrity
**Location:** [Mosaic/Mosaic/Composer/Sync/ComposerRemoteSync.swift:203](/Users/ayushkrishnappa/mosaic/Mosaic/Mosaic/Composer/Sync/ComposerRemoteSync.swift:203)

**Evidence:** The client lists remote document IDs and deletes every non-Mosaic ID missing from its local split, regardless of whether the device ever saw that document or explicitly deleted it.

**Impact / trigger:** A board newly created on another device can be deleted by a stale device's next launch/edit sync, including cascading children.

**Recommended fix:** Use explicit revisioned deletion tombstones, not set subtraction; reconcile new remote documents and make graph moves/deletes transactional.

**Validation boundary:** Source-confirmed; no production deletions performed.


### SYNC-03 · P1 · Queued sync re-enters while the active flag is still set
**Area:** Reliability
**Location:** [Mosaic/Mosaic/Composer/Sync/ComposerRemoteSync.swift:138](/Users/ayushkrishnappa/mosaic/Mosaic/Mosaic/Composer/Sync/ComposerRemoteSync.swift:138)

**Evidence:** run sets active = true and clears it in defer. If again is set while push awaits, run recursively calls itself before the defer executes. The recursive call sees active == true, sets again and returns without draining latest.

**Impact / trigger:** Edits or Settings Save arriving during an upload can remain queued until another unrelated sync trigger. Save may report the previous push's result rather than the newly requested snapshot.

**Recommended fix:** Replace recursive re-entry with one cancellation-aware draining loop, and associate Save completion with a snapshot/version.

**Validation boundary:** Source-confirmed state-machine trace; existing tests do not exercise this concurrency path.


### DATA-01 · P1 · Failed local saves are silently discarded
**Area:** Reliability
**Location:** [Mosaic/Mosaic/Composer/ComposerStore.swift:933](/Users/ayushkrishnappa/mosaic/Mosaic/Mosaic/Composer/ComposerStore.swift:933)

**Evidence:** persist encodes the entire snapshot and writes it atomically; catch is empty, and onPersisted is only called on success. Sync-state writes also use try? without reporting failure.

**Impact / trigger:** Disk-full, protection, or I/O failures leave edits visible in memory but neither durably saved nor scheduled to upload. Closing the app can lose work without warning.

**Recommended fix:** Expose durable-save state and actionable errors; preserve the last known-good copy; test write failures and avoid claiming Saved until persistence succeeds.

**Validation boundary:** Source-confirmed; disk failure not injected.


### SEC-03 · P1 · Media upload controls rely heavily on the honest client
**Area:** Abuse controls
**Location:** [Mosaic/Mosaic/Composer/Sync/ComposerMediaUpload.swift:270](/Users/ayushkrishnappa/mosaic/Mosaic/Mosaic/Composer/Sync/ComposerMediaUpload.swift:270)

**Evidence:** The private media bucket has null bucket-specific file_size_limit and allowed_mime_types. Its owner write policy checks only the first path segment. media_assets ownership policy permits client-supplied kind/status/size/duration metadata.

**Impact / trigger:** A signed-in custom client can bypass the app's 10-second trimming and upload arbitrary content within project/global limits. No app-specific quota/rate enforcement or content-validation worker was found.

**Recommended fix:** Set bucket-specific types and size ceilings, enforce per-account quotas and request rates, and validate duration/content server-side before publication. Keep public-beta scope bounded until controls exist.

**Validation boundary:** Live bucket/policy/metadata verified; project-wide limits and external infrastructure not verified.


### DB-01 · P1 · The repository cannot recreate the live database
**Area:** Reproducibility
**Location:** [supabase/migrations](/Users/ayushkrishnappa/mosaic/supabase/migrations)

**Evidence:** Live project has 16 migrations; checkout has 7. Eight baseline migrations and the latest 20261016162315_save_document_role_move migration are missing. No Supabase config or database policy regression suite is checked in.

**Impact / trigger:** Fresh staging environments, disaster recovery, onboarding, and trustworthy migration testing are blocked; app behavior already depends on unversioned live functions.

**Recommended fix:** Capture a sanitized complete baseline and the missing migration, version configuration/functions/bucket policies, and prove reset/apply from scratch in isolated staging.

**Validation boundary:** Compared live migration history with local file inventory.


### QUALITY-01 · P1 · Passing unit tests do not cover the beta's highest-risk journeys
**Area:** Release confidence
**Location:** [Mosaic/MosaicUITests/MosaicUITests.swift:26](/Users/ayushkrishnappa/mosaic/Mosaic/MosaicUITests/MosaicUITests.swift:26)

**Evidence:** Functional UI tests launch with UITestSkipLaunchAnimation, which bypasses account auth/network and disables persistence. Unit tests cover many useful pure/restore paths but do not exercise the remote-sync conflict/drain cases or live three-user security matrix. No CI workflow was found.

**Impact / trigger:** The current green suite cannot establish privacy, durable sync or end-to-end media correctness for real signed-in users.

**Recommended fix:** Add deterministic network-injected sync tests, isolated database/RLS tests, and signed-in staging smoke journeys; gate beta builds on them.

**Validation boundary:** 109 current unit tests passed; two functional UI smoke tests passed; the scroll test failed twice at the same 54%-versus-100% assertion.


### MEDIA-01 · P2 · GIF uploads prefer a flattened JPEG over the original animation
**Area:** Functionality
**Location:** [Mosaic/Mosaic/Composer/Sync/ComposerMediaUpload.swift:33](/Users/ayushkrishnappa/mosaic/Mosaic/Mosaic/Composer/Sync/ComposerMediaUpload.swift:33)

**Evidence:** photoPayloads flags every non-JPEG, including image/gif, for replacement by the display JPEG and puts that payload first. uploadMedia stops after its first successful payload.

**Impact / trigger:** A GIF animates locally but typically restores/downloads as a still JPEG, even though the file name remains .gif. Original bytes are lost from the successful uploaded asset.

**Recommended fix:** Special-case GIFs to preserve original bytes; do not flatten as a transparent fallback. Test the exact upload payload and restore/visitor animation, not just local decoding.

**Validation boundary:** Source-confirmed; current GIF test covers local save/decode, not uploaded original selection.


### MEDIA-02 · P2 · Upload failures and deletions leave unmanaged Storage objects
**Area:** Backend
**Location:** [Mosaic/Mosaic/Composer/Sync/ComposerMediaUpload.swift:238](/Users/ayushkrishnappa/mosaic/Mosaic/Mosaic/Composer/Sync/ComposerMediaUpload.swift:238)

**Evidence:** Uploads write original/display/thumb before inserting media_assets. A later failure has no rollback cleanup, retries allocate a new asset ID, and board deletion removes metadata rather than Storage objects. Live query found 34 media objects not referenced by any asset path.

**Impact / trigger:** Storage and costs grow from abandoned uploads and deleted content; the orphan count is confirmed, but each object's cause was not determined.

**Recommended fix:** Make upload attempts idempotent, finalize assets atomically, and run age-delayed reference-aware garbage collection through the Storage API. Preserve shared-file references.

**Validation boundary:** Live aggregate + source confirmed; no objects deleted.


### SEC-02 · P2 · Direct table writes bypass document validation and concurrency controls
**Area:** Security
**Location:** [supabase/migrations/20261014213723_security_advisor_fixes.sql:50](/Users/ayushkrishnappa/mosaic/supabase/migrations/20261014213723_security_advisor_fixes.sql:50)

**Evidence:** documents_owner_all permits all operations based only on owner_id. authenticated can directly insert/update documents and parent_id. save_document's parent ownership, role-transition, and revision checks are not enforced by equivalent table constraints/triggers.

**Impact / trigger:** A custom client can create invalid/cyclic/cross-owner parent links or overwrite its documents without revision checks. Recursive ancestry helpers have no cycle guard; malformed graphs can cause timeouts and break viewer/restore behavior.

**Recommended fix:** Make structural writes RPC-only or enforce graph/ownership/revision invariants at the table boundary, including cycle/depth/body validation.

**Validation boundary:** Live grants/constraints/function definitions confirmed; no malformed production rows created. Currently zero cross-owner parents.


### OPS-01 · P2 · Media processing queue has no observed consumer progress
**Area:** Backend
**Location:** [Mosaic/Mosaic/Composer/Sync/ComposerMediaUpload.swift:108](/Users/ayushkrishnappa/mosaic/Mosaic/Mosaic/Composer/Sync/ComposerMediaUpload.swift:108)

**Evidence:** All 196 media_jobs are queued, oldest October 12; 28 assets are processing. The trigger enqueues every asset, including ready photos. There are no deployed Edge Functions and no worker code in this checkout.

**Impact / trigger:** The queue is not an operational processing pipeline today. Client-side original playback can still work, but processing status/validation/transcodes cannot be relied on.

**Recommended fix:** Either retire the unused queue for a deliberately client-prepared beta or implement a bounded worker with leases, retries, dead-letter handling and alerts.

**Validation boundary:** Live aggregates confirmed; an out-of-repo worker cannot be ruled out, but no completed jobs were observed.


### PERF-01 · P2 · Each sync writes all documents sequentially
**Area:** Performance
**Location:** [Mosaic/Mosaic/Composer/Sync/ComposerRemoteSync.swift:189](/Users/ayushkrishnappa/mosaic/Mosaic/Mosaic/Composer/Sync/ComposerRemoteSync.swift:189)

**Evidence:** Every settled edit/launch splits the entire snapshot and saves all documents serially; uploads can then restamp documents. pg_stat_statements shows 15,244 successful save_document wrapper calls with 3 profiles at inspection time.

**Impact / trigger:** Write amplification grows with boards per user, increases conflict exposure and mobile latency. The observed count is cumulative since statistics reset, not a traffic rate or capacity estimate.

**Recommended fix:** Track dirty document hashes/base revisions and push only changes, batch safely, cap concurrency and measure calls per meaningful edit.

**Validation boundary:** Source + live cumulative statistic; no load test or throughput claim.


### PERF-02 · P2 · Visit and follower endpoints return unbounded lists
**Area:** Performance
**Location:** [Mosaic/Mosaic/Shell/MosaicVisit.swift:67](/Users/ayushkrishnappa/mosaic/Mosaic/Mosaic/Shell/MosaicVisit.swift:67)

**Evidence:** viewer_boards returns all accessible board bodies; circle_people and my_follows have no pagination parameters. Clients consume one response without page traversal. Only owner restoration has explicit paging.

**Impact / trigger:** Popular profiles/large Mosaics can incur slow, memory-heavy responses or silently truncated follower/following lists if the API row cap is reached. Detail follower total derives from fetched people.

**Recommended fix:** Cursor pagination with independent authoritative counts; lazy document-body fetching on navigation; retain compact metadata for locks and covers.

**Validation boundary:** Live function signatures + client code confirmed; configured API cap not inspected.


### PERF-03 · P2 · Per-GIF memory caps do not bound whole-board memory
**Area:** Mobile performance
**Location:** [Mosaic/Mosaic/Composer/ComposerAnimatedImage.swift:46](/Users/ayushkrishnappa/mosaic/Mosaic/Mosaic/Composer/ComposerAnimatedImage.swift:46)

**Evidence:** Each GIF predecodes up to about 32 MiB; the board uses a non-lazy ZStack/ForEach and carousel poster loading retains images for all items. Static image fallback can also load full-resolution originals.

**Impact / trigger:** Many GIFs and high-resolution photos can accumulate hundreds of MiB; scrolling away does not necessarily free them. Jetsam/frame drops are plausible, not measured in this audit.

**Recommended fix:** Introduce a shared memory-costed image pipeline, viewport-aware loading/playback, cancellation and poster-only offscreen rendering; downsample stills to target size.

**Validation boundary:** Source-confirmed architecture risk; Instruments/physical-device profiling still required.


### ANALYTICS-01 · P2 · Daily visits have midnight and retention edge cases
**Area:** Analytics
**Location:** [supabase/migrations/20261014213437_daily_visits.sql:54](/Users/ayushkrishnappa/mosaic/supabase/migrations/20261014213437_daily_visits.sql:54)

**Evidence:** A global 10-minute dedupe can suppress a new-day visit shortly after midnight; reportedVisits is never cleared for an open visit session. Retention deletes globally only on a newly inserted visit, after the duplicate early-return.

**Impact / trigger:** Today's unique count can be low; inactive projects can retain records longer than the stated 90 days. Concurrent repeat inserts are also not protected by a uniqueness constraint, though distinct counting hides duplicates.

**Recommended fix:** Agree on the reporting day/timezone semantics; make dedupe day-aware and expire client session dedupe; run scheduled bounded retention independent of user traffic.

**Validation boundary:** Source/live function confirmed; no clock-shift test run.


### PRIVACY-01 · P2 · An open visit does not revalidate the Mosaic gate itself
**Area:** Privacy
**Location:** [Mosaic/Mosaic/Shell/MosaicVisit.swift:385](/Users/ayushkrishnappa/mosaic/Mosaic/Mosaic/Shell/MosaicVisit.swift:385)

**Evidence:** Foreground/return refresh only fetches viewer_pursuits and reloads when open Pursuit IDs change. It does not refetch profile_view.canView. With zero open Pursuits before and after gate revocation, the sets are unchanged.

**Impact / trigger:** A visitor can keep the already-loaded Mosaic visible after the owner revokes access or makes it private, until a full visit reload. Already-delivered content cannot be made unread, but the app should stop presenting revoked views.

**Recommended fix:** Revalidate root and current document access on foreground/return, close revoked views and clear relevant cached presentation. Define revocation expectations explicitly.

**Validation boundary:** Source-confirmed edge case; two-device runtime test pending.


### AUTH-01 · P2 · Permanent token-refresh failure leaves the app without a recovery flow
**Area:** Authentication
**Location:** [Mosaic/Mosaic/Account/MosaicAccount.swift:228](/Users/ayushkrishnappa/mosaic/Mosaic/Mosaic/Account/MosaicAccount.swift:228)

**Evidence:** accessToken returns nil for all refresh failures, treating invalid/revoked refresh tokens like temporary offline errors; cached session remains. Many callers simply guard-return.

**Impact / trigger:** Users can remain signed in locally while network actions repeatedly do nothing or stay loading; retrying cannot fix a revoked session.

**Recommended fix:** Classify permanent auth errors versus transport failure, preserve local data, and present an explicit reauthentication path while cancelling old-account operations.

**Validation boundary:** Source confirmed; revocation and account-switch integration tests missing.


### RELEASE-01 · P2 · Account deletion, UGC safety and login-policy readiness are incomplete
**Area:** Distribution
**Location:** [Mosaic/Mosaic/Shell/MosaicSignInView.swift:15](/Users/ayushkrishnappa/mosaic/Mosaic/Mosaic/Shell/MosaicSignInView.swift:15)

**Evidence:** App exposes Google sign-in, public discovery and user media. No account-deletion, content-reporting or user-blocking flow/backend was found. Settings offers sign-out only.

**Impact / trigger:** A wider externally reviewed beta/public release needs a deletion/data-erasure path, public-content abuse handling and review of Apple's equivalent-login requirements. External services/dashboard submission assets were not inspected.

**Recommended fix:** Build deletion including Storage cleanup, user blocking/reporting and moderation/support handling; plan an equivalent privacy-preserving login option unless an applicable exception is documented.

**Validation boundary:** Repository search + current Apple guidelines; not an App Review determination.


### ARCH-01 · P2 · State, persistence, sync and interaction concerns are tightly coupled
**Area:** Architecture
**Location:** [Mosaic/Mosaic/Composer/MosaicComposerView.swift:1](/Users/ayushkrishnappa/mosaic/Mosaic/Mosaic/Composer/MosaicComposerView.swift:1)

**Evidence:** MosaicComposerView is 2,642 lines, ComposerModels 1,723, PursuitWidgetEditor 1,335. Store performs whole-snapshot JSON serialization/writes synchronously on the main actor; remote sync constructs concrete clients. Found actor-isolation warnings in current build.

**Impact / trigger:** Large edits/media preparation can affect UI responsiveness, and critical sync failures are difficult to inject/test. File size alone is not a defect; mixed ownership and hidden dependencies are the concern.

**Recommended fix:** Incrementally extract a document repository, sync actor/state machine, media pipeline and small interaction controllers behind explicit injected boundaries. Reconcile current architecture/product docs before broad refactors.

**Validation boundary:** Source inspection; no whole-app rewrite recommended.


### DB-02 · P2 · Media authorization repeatedly scans board JSON and filters widget trees
**Area:** Scale
**Location:** Supabase: public.viewer_can_read_media(text)

**Evidence:** Every media permission check finds the asset by iterating JSON mediaAssets in owned documents, checks document visibility, then invokes viewer_board_body and scans the filtered manifest again.

**Impact / trigger:** Serving many images multiplies JSON traversal and authorization work with board size; it is a likely scale bottleneck, not proven at the current 29-document dataset.

**Recommended fix:** Normalize asset-to-document references and enforce ownership/FKs; index readable reference lookup and validate plans under representative data before optimizing caching.

**Validation boundary:** Live function definition inspected; no production load test performed.


### OPS-02 · P2 · Operational beta gates and incident visibility are not established
**Area:** Operations
**Location:** [docs/quality/testing.md](/Users/ayushkrishnappa/mosaic/docs/quality/testing.md)

**Evidence:** No in-repo crash/error telemetry integration, alerts, CI, load test, backup/restore drill or measured device performance budget was found. Testing documentation explicitly leaves release criteria open.

**Impact / trigger:** A smooth beta cannot be promised from simulator unit tests. Capacity for thousands or millions is currently unmeasured; live sample is 3 profiles and about 94 KB of board bodies.

**Recommended fix:** Define SLOs and a support path, add privacy-safe errors/crashes/upload metrics, verify backup/PITR plan and restore, select supported devices/OS, and ramp an invite-only cohort with stop conditions.

**Validation boundary:** Repository/config review; external monitoring, backup settings and production arrangements remain unverified.


### UI-01 · P2 · The scroll-bubble smoke test is currently failing
**Area:** UI regression
**Location:** [Mosaic/MosaicUITests/MosaicUITests.swift:97](/Users/ayushkrishnappa/mosaic/Mosaic/MosaicUITests/MosaicUITests.swift:97)

**Evidence:** On iPhone 18 Pro / iOS 27.0, the scroll-bubble UI test reached its assertion and returned '54 percent' after the scripted drag instead of '100 percent'. The other two functional UI tests passed.

**Impact / trigger:** The current UI gate is not green. This may be a rail calculation regression or a stale gesture expectation; do not classify it as a simulator-only failure without investigation.

**Recommended fix:** Reproduce the drag, compare the rail's actual track bounds with the test target, and fix behavior or the test based on the intended interaction. Add durable accessibility identifiers.

**Validation boundary:** Observed runtime assertion in xcresult; isolated retry reproduced the same assertion.

## Current system flow

```text
Google OAuth / PKCE -> Keychain session -> account-scoped composition root
  -> ComposerStore -> local whole-snapshot JSON
  -> ComposerRemoteSync -> document RPCs + private Storage
Visitor -> profile gate -> filtered board RPCs -> viewer-scoped media cache
Circle -> owner-scoped follow/request RPCs + daily-visit aggregates
```

## Architecture and what is already sound
**Current repository fact:** The composition root creates account-specific stores; auth sessions use Keychain and PKCE. Concurrent token refreshes are coalesced. Restore validates owner/revision/identities and rejects unsafe manifest names; landing-board edits are preserved while children download. Visitor media caches are scoped by viewer and owner, validate manifest asset identity, and download with bounded concurrency. Visitor board filtering exists server-side; this is substantially better than relying only on a lock icon.

**Current repository fact:** Shared media is authorized through references in readable board bodies, not solely the asset's original document_id. Retain this behavior when normalizing references or adding garbage collection; a copied image must remain readable from its surviving board.

**Current repository fact:** There are no external package dependencies. Existing pure model/restoration tests are valuable. A green test suite is necessary, but the missing concurrency, negative-authorization and signed-in scenarios explain how important bugs escaped.

**Recommendation:** Extract responsibilities in small steps:
1. DocumentRepository: typed transport, owner-scoped local persistence, explicit durability errors.
2. SyncEngine: actor/state machine, dirty-document queue, versioned conflicts, explicit deletions, cancellation/account binding.
3. MediaPipeline: bounded decoding/playback/cache, durable upload jobs, server finalization and cleanup.
4. Feature-level models for Circle, Discover and Settings that use injected clients.
5. Keep the expressive board UI, while pulling unrelated networking and state transitions out of its large coordinator.

The older architecture ADRs describe a Golf-first destination model. README acknowledges that they have not been reconciled with the composer product. **Open question:** which historical decisions remain active for the beta? This review records the conflict rather than silently replacing those decisions.

## Ordered implementation plan
### Phase A — protect privacy and work
**Recommendation:** Fix SEC-01, SYNC-01/02/03 and DATA-01 first. Capture a full backend baseline before further live changes (DB-01). Add negative authorization and deterministic sync tests in the same patches. Configure bounded uploads (SEC-03) before inviting untrusted users.
Acceptance: no foreign grant injection; stale clients cannot erase remote work; queued edits drain; Save waits for its version; local disk failures are visible and recoverable.

### Phase B — make an invite-only beta dependable
**Recommendation:** Repair GIF upload preservation and upload cleanup; decide the media worker/queue contract; add reauthentication and access revocation handling; resolve the failing UI test; build account deletion/report/block flows appropriate to the distribution audience. Stand up reproducible staging and CI.
Acceptance: tested matrix covering photo/video/GIF/content/carousel/calendar/group/copy-cut-paste, relaunch, new-device restore, offline/online, interruption, retry, account switching, approval/denial/re-request/revocation. Verify with 3 staging accounts and physical devices, never by mutating personal production content.

### Phase C — prove capacity for the next cohort
**Recommendation:** Add dirty-document sync, paginated followers/metadata, lazy board retrieval, normalized media references and missing FK indexes. Measure query plans on representative synthetic fixtures and add observability/budgets.
Current missing FK indexes flagged by Supabase: circle_seen(document_id), follows(target_owner_id), mosaic_access_requests(requester_id). Do not delete indexes simply because this tiny dataset calls them unused.

### Phase D — scale from evidence
**Recommendation:** Grow from controlled invites to thousands, then larger cohorts only after measuring active concurrency, boards per account, media bytes, read/write amplification, egress and errors. Use managed Postgres/Storage longer; add cache/rollups/workers/partitioning only against measured bottlenecks.
A million registered users is not the same as a million concurrent users. Current 3-profile data cannot establish either capacity.

## Proposed beta release gates
These are **recommendations**, not previously approved product decisions:
- All P1 findings closed with regression coverage; no unresolved unauthorized-read/write paths.
- 109 current unit tests plus new sync/security tests green; functional UI suite consistently green.
- No lost acknowledged save in offline/relaunch/multi-device/kill tests.
- Signed-in staging journeys pass for all shipped components and access states.
- Physical-device image/GIF stress tests and Instruments measurements within an agreed memory/frame-time budget.
- Crash/error/upload/conflict visibility, actionable support path and rollback plan.
- Complete baseline + CI migrations + verified backup/restore rehearsal.
- Owner-approved privacy disclosures/retention, UGC safety, deletion, login and distribution requirements.
- Suggested measurement targets to approve: crash-free sessions >=99.5%, no observed data loss, API error rate <1% excluding expected denials, and p95 core metadata requests <1 second in the chosen region/network fixture. These are proposed starting gates, not measured results or promises.

## Advisor interpretation
The remaining 23 authenticated SECURITY DEFINER warnings are a review surface, not 23 proven vulnerabilities. RPC entry points intentionally need execution permissions, but their bodies and table invariants must still be correct; SEC-01 demonstrates why advisor cleanup alone is insufficient.
The visits RLS/no-policy notice is intentional deny-by-default protection. The leaked-password warning remains; email auth was reported disabled in the earlier chat, but this session did not independently read Auth provider configuration.
[Supabase definer-function advisory](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [missing FK indexes](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys), [column privileges](https://supabase.com/docs/guides/database/postgres/column-level-security).

## Distribution and remaining unknowns
Apple's current UGC guidance calls for reporting, blocking, moderation and contact information. Account-creating apps need an in-app deletion initiation path; third-party login requires checking the equivalent-login rule and applicable exceptions. These are distribution-readiness checks, not a prediction of TestFlight/App Review results.
Sources: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/).

**Open questions:** internal versus external beta audience; supported devices/OS (current target 26.5 is not an approved support matrix); permitted offline/multi-device conflict behavior; strict retention/timezone semantics; upload quotas and moderation ownership; data recovery objective and backup plan. External monitoring, Auth settings, production/staging separation, rate-limit settings, legal disclosures and existing operational processes need separate verification.

## Scope discipline
Only this report, its sanitized evidence snapshot, and a browsable analytical artifact are created. No app/backend fixes are included. Findings need focused patches and staging validation rather than a large mixed refactor.
