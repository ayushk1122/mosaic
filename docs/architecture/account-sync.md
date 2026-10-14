# Account restoration and sync

**Owner:** Engineering
**Status:** Current repository fact — implemented behavior, not a complete multi-device sync design

## Current structure

- `Mosaic/Mosaic/Account/MosaicAccount.swift`: Google OAuth with PKCE, token refresh, and Keychain sessions.
- `Mosaic/Mosaic/MosaicApp.swift`: launch, login, and account preparation before the editor opens.
- `Mosaic/Mosaic/Composer/ComposerStorageLocation.swift`: account-specific local folders and migration of pre-account data.
- `Mosaic/Mosaic/Composer/ComposerStore.swift`: local editable snapshot and media files.
- `Mosaic/Mosaic/Composer/Sync/ComposerAccountRestore.swift`: landing-board restoration and safe local installation.
- `Mosaic/Mosaic/Composer/Sync/ComposerBackgroundRestore.swift`: remaining board and media downloads, retry, and progress.
- `Mosaic/Mosaic/Composer/ComposerMediaAvailability.swift`: refreshes individual media views when files arrive.
- `Mosaic/Mosaic/Composer/Sync/SupabaseDocumentSync.swift`: authenticated document reads and writes.
- `Mosaic/Mosaic/Composer/Sync/ComposerRemoteSync.swift`: debounced uploads and revision bookkeeping.
- `Mosaic/Mosaic/Shell/`: navigation, discovery, visits, circle, profile, and sharing UI.

## Login behavior

**Current repository fact:** The stored session is loaded from Keychain without waiting for a network refresh. Network operations share a lazy token refresh; a connection failure leaves the cached account available. The app checks for legacy local data belonging to the account. An account with a readable local snapshot and sync state opens that local copy immediately, including offline edits.

On a new installation, `own_mosaic_id` identifies the saved board. A JSON `null` means the account has no cloud Mosaic. Failed or malformed responses remain errors. For an existing cloud Mosaic, the app downloads just its owner-filtered document row, then installs `composer.json` and a sync state with `pendingRestore: true`. The prior local folder is retained as a sibling `.before-restore-*` recovery copy. The main board becomes editable without waiting for Pursuits or media.

The shell then fetches all owner-filtered document pages in the background. It validates the complete board graph and merges missing Pursuits, nodes, and scrapbook pages into the live store, preserving main-board edits and newly created local boards. Opening a not-yet-downloaded board shows a loading view rather than an editable empty page. Undo entries are reconciled with downloaded children. Local edits are persisted throughout; uploads and remote deletions are blocked until the complete board snapshot and revisions are saved and `pendingRestore` is cleared.

Uploaded media downloads in the background, prioritizing main-board references. Each successful file is written atomically and updates just the corresponding image/video load identity. Missing media shows the existing placeholder until it arrives. A failed file does not prevent other files from downloading. The status banner offers Retry while the editor remains available; returning to the foreground also retries work. Relaunch uses the saved pending flag and missing-file checks to resume without refetching completed boards or files. Network or media failure never replaces the editor with the login screen.

The starter heading from older versions can be replaced with cloud content. Actual unsynced local edits with a separate cloud Mosaic stop initial restoration with a reconciliation message. The old startup call that cleared Pursuit pages has been removed.

## Backend contract

**Current repository fact:** This change uses the same Supabase project and user identity as existing authentication. It does not require a new project, API key, bucket, or auth redirect. It uses:

- `own_mosaic_id` RPC, returning a UUID or JSON `null`.
- Authenticated owner access to `documents`: `id`, `owner_id`, `parent_id`, `role`, `title`, `body`, and `revision`.
- Authenticated reads of `media/{owner UUID}/{asset UUID}/original`.

RLS remains enforced by Supabase. No service-role key is used. The repository does not contain a complete versioned backend schema; the live project must expose the existing owner-read contract.

## Visiting another person's boards

**Current repository fact:** Visits fetch fresh `profile_view`, `viewer_boards`, and `viewer_pursuits` results before displaying content, preserving server access checks. Once authorized layouts arrive, the read-only board opens immediately without waiting for media. Each opened Mosaic, Pursuit, node, or scrapbook page downloads its media independently, with up to four concurrent requests. Photos try the display variant before falling back to the original; videos use the original. Individual views refresh as files arrive. Failed downloads leave the board usable and offer Retry; leaving the view cancels its media task.

Media caches are separated by viewer and owner. A manifest associates filenames with asset UUIDs, removes files that changed or disappeared from the newly authorized response, and allows unchanged files to be reused on later visits. Unsafe filenames, invalid asset IDs, and conflicting filename mappings are rejected. Cached layouts are not displayed offline, and an access denial cannot fall back to cached boards. Access changes while a visit remains open are not monitored continuously.

**Reversible choice:** Keep the existing `viewer_boards` RPC, which returns all authorized layout JSON together. Media is loaded on demand per board; per-board metadata requests, viewport-level media loading, and adaptive video streaming remain future work. No Supabase schema or configuration changes are required for this visit flow.

## Limits

**Current repository fact:** This restores a fresh or starter-only account installation. It is not continuous multi-device synchronization: an established local copy is not replaced on every login, and automatic merging of conflicting offline edits is not implemented.

Only media uploaded and referenced by a cloud asset can be restored. Files that never reached Supabase cannot be recovered from it. If a referenced cloud object is unavailable, its placeholder remains and the status banner offers Retry. Boards stay usable. Already established local boards are not refreshed from other devices by this downloader.

## Verification

`ComposerAccountRestoreTests` covers landing-board-first opening, delayed children and media, saved revisions, pagination, account filtering, failed downloads, relaunch/resume, edits and undo during downloads, upload gating, media refresh identities, starter recognition, UUID casing, and malformed responses. Network responses are mocked; tests do not modify a live Supabase project.

Visitor tests also cover per-board media requests, repeat-visit cache reuse, failed-download retry, cancellation before download, changed/removed asset invalidation, and unsafe paths. For manual verification, open another person’s Mosaic on a slow connection: text/layout should appear first, media should fill in, and unopened Pursuit media should not download. Open a Pursuit or scrapbook page, retry a failed file, then revisit to confirm cache reuse. A private board without access should remain locked.

Run the Mosaic unit tests on an installed iPhone simulator. For a manual check, use an account with known uploaded boards and media on a fresh app installation: sign in and use the main board while the download banner is present; edit some text, open a pending Pursuit, and verify the content appears without losing your edit. Check photos/videos as they arrive, retry after a failed connection, and verify an interrupted download resumes after relaunch. Existing cached boards should also open offline. Keep the old installation until cloud restoration is confirmed.

## Content link cards

**Current repository fact:** Content is available in both Mosaic and Pursuit add menus. It uses the existing `link` block kind with a `content:<platform>` marker in `socialPlatform`, plus `linkURL`, `text`, and `mediaFileName`. Older clients can decode it as a link rather than rejecting an unknown block kind. An older client may display only its title/URL. No backend schema change is required.

The Content editor shares Socials’ logo picker and styled link field, with a preview section below. Content accepts a full URL only; it does not use Socials’ username-to-profile-URL conversion.

The editor validates HTTPS post/video URLs for YouTube, Instagram, TikTok, and Twitch, detects the source, and uses Apple's Link Presentation framework to request a title and image. Preview requests are made on the author's device, not during visitor board loading. Missing previews can be retried or supplied as a cover photo; saving a link without a cover is also supported. Cover images are resized to at most 1280 pixels on the long edge and use the existing media catalog, upload, cache, and visitor-download flow.

In edit mode, tapping a selected Content card edits it; dragging and pinching use the board's existing gestures. In view mode, tapping opens the validated HTTPS source link through iOS. Source-app routing depends on installed apps and their universal-link support; a website may open instead. There are no embedded players. This does not change video upload or audio behavior.

**Reversible choice:** Use system link previews without provider credentials for this first version. Automatic thumbnail availability varies by platform, post permissions, and network conditions; it is not guaranteed for all four sources. Twitch channel/live-stream links are not included in this version; clips and VOD links are supported.

`ComposerContentTests` covers supported share/post URLs, rejected schemes and lookalike domains, menu availability, serialization, and thumbnail inclusion in board sync. Manual device checks should cover adding/editing/canceling, a missing preview and custom cover, drag/pinch/group behavior, visiting a restored card, and opening links with and without the source apps installed.
