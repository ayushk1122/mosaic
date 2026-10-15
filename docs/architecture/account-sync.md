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
- `Mosaic/Mosaic/Composer/ComposerMediaAvailability.swift`: refreshes individual media views when files arrive, and tells them which missing files are still coming.
- `Mosaic/Mosaic/Composer/Sync/SupabaseDocumentSync.swift`: authenticated document reads and writes.
- `Mosaic/Mosaic/Composer/Sync/ComposerRemoteSync.swift`: debounced uploads and revision bookkeeping.
- `Mosaic/Mosaic/Shell/`: navigation, discovery, visits, circle, profile, and sharing UI.

## Login behavior

**Current repository fact:** The stored session is loaded from Keychain without waiting for a network refresh. Network operations share a lazy token refresh; a connection failure leaves the cached account available. The app checks for legacy local data belonging to the account. An account with a readable local snapshot and sync state opens that local copy immediately, including offline edits.

On a new installation, `own_mosaic_id` identifies the saved board. A JSON `null` means the account has no cloud Mosaic. Failed or malformed responses remain errors. For an existing cloud Mosaic, the app downloads just its owner-filtered document row, then installs `composer.json` and a sync state with `pendingRestore: true`. The prior local folder is retained as a sibling `.before-restore-*` recovery copy. The main board becomes editable without waiting for Pursuits or media.

The shell then fetches all owner-filtered document pages in the background. It validates the complete board graph and merges missing Pursuits, nodes, and scrapbook pages into the live store, preserving main-board edits and newly created local boards. Opening a not-yet-downloaded board shows a loading view rather than an editable empty page. Undo entries are reconciled with downloaded children. Local edits are persisted throughout; uploads and remote deletions are blocked until the complete board snapshot and revisions are saved and `pendingRestore` is cleared.

Uploaded media downloads in the background, prioritizing main-board references. Each successful file is written atomically and updates just the corresponding image/video load identity. Missing media shows a spinner in its place until it arrives; there is no banner while content loads. A failed file does not prevent other files from downloading. After a failure, a banner offers Retry while the editor remains available; returning to the foreground also retries work. Relaunch uses the saved pending flag and missing-file checks to resume without refetching completed boards or files. Network or media failure never replaces the editor with the login screen.

The starter heading from older versions can be replaced with cloud content. Actual unsynced local edits with a separate cloud Mosaic stop initial restoration with a reconciliation message. The old startup call that cleared Pursuit pages has been removed.

## Backend contract

**Current repository fact:** This change uses the same Supabase project and user identity as existing authentication. It does not require a new project, API key, bucket, or auth redirect. It uses:

- `own_mosaic_id` RPC, returning a UUID or JSON `null`.
- Authenticated owner access to `documents`: `id`, `owner_id`, `parent_id`, `role`, `title`, `body`, and `revision`.
- Authenticated reads of `media/{owner UUID}/{asset UUID}/original`.

RLS remains enforced by Supabase. No service-role key is used. The repository does not contain a complete versioned backend schema; the live project must expose the existing owner-read contract. Only migrations added since Daily Visits are kept in `supabase/migrations/`.

**Current repository fact:** `20261014213723_security_advisor_fixes.sql` and `20261014213754_lock_internal_helpers.sql` address the Supabase advisors without changing what any rule allows:

- Trigger functions can't be called through the API.
- `touch_updated_at` has a fixed search path.
- Every `public` row-level security policy reads the signed-in user once per query (`(select auth.uid())`) instead of once per row.
- `circle_counts` and `viewer_can_open_pursuit` can't be called by signed-in users, since neither the app nor a policy needs them.

`pursuit_is_requestable`, `viewer_can_read_document`, `viewer_can_read_media`, and `viewer_passes_mosaic_gate` stay callable because policies run them as the signed-in user. They only report the caller's own access.

**Current repository fact:** Mosaic signs in only with Google, and every existing account uses Google. The Email provider is turned off in Supabase Auth (a dashboard setting outside this repository), so password accounts can't be created. The leaked-password advisor still appears because it checks that setting independently; it doesn't apply while email sign-in is off.

## Visiting another person's boards

**Current repository fact:** Visits fetch fresh `profile_view`, `viewer_boards`, and `viewer_pursuits` results before displaying content, preserving server access checks. Once authorized layouts arrive, the read-only board opens immediately without waiting for media. Each opened Mosaic, Pursuit, node, or scrapbook page downloads its media independently, with up to four concurrent requests. Photos try the display variant before falling back to the original; videos and GIFs use the original. Individual views refresh as files arrive, showing a spinner in place until then, with no loading banner. Failed downloads leave the board usable and offer Retry; leaving the view cancels its media task.

Media caches are separated by viewer and owner. A manifest associates filenames with asset UUIDs, removes files that changed or disappeared from the newly authorized response, and allows unchanged files to be reused on later visits. Unsafe filenames, invalid asset IDs, and conflicting filename mappings are rejected. Cached layouts are not displayed offline, and an access denial cannot fall back to cached boards. Access is not monitored continuously, but an open visit re-reads `viewer_pursuits` when it reappears or the app returns to the foreground, and reloads its boards if any Pursuit's access changed.

**Current repository fact:** A visitor can open a Pursuit only when `viewer_pursuits` returns it with `can_open`; a Pursuit missing from that list is treated as locked. A private or hidden Pursuit must also still be followed by the visitor: following the Mosaic does not open it, and unfollowing it locks it again until the owner approves a new request. Locked Pursuit widgets show a white lock, or an amber lock while the visitor's request is pending; a declined request shows the white lock again. Tapping a locked Pursuit offers a view request, or says the request is still pending. After a successful `request_pursuit_access` call, the client re-reads `viewer_pursuits` and shows that status, because the call's own reply isn't treated as a reliable status. A declined request returns the Pursuit to the white lock, and the visitor may request again. If the Pursuit is still locked with no pending request after the call, the visitor is told the request wasn't saved.

**Current repository fact:** Following a Mosaic follows the person, not their Pursuits. `follow_mosaic`, and accepting a Mosaic view request, add only the Mosaic follow; each Pursuit is followed on its own. Tapping Follow on a visited Mosaic follows it immediately, with no confirmation sheet. Unfollowing a Mosaic still unfollows every Pursuit of that owner, since it means the visitor no longer follows that person's content. The `mosaic_follow_is_just_the_person` migration removed earlier Pursuit follows that had been added automatically with a Mosaic follow, identified by sharing that follow's timestamp, unless the person had an approved request for that Pursuit. **Open question:** how a visitor follows all of a person's Pursuits at once.

**Open question:** `request_pursuit_access` and `viewer_pursuits` live outside this repository. Re-requesting after a decline, and requesting a private Pursuit the server already reports as `can_open`, depend on those functions creating a new `pending` request. Before a visit is assembled, the client drops locked Pursuit documents and their nodes and pages from the `viewer_boards` response. This is defense in depth: the server must still withhold unauthorized boards, and that enforcement lives outside this repository.

**Current repository fact:** In a Circle bubble, accepting a follower or view request moves the person into Followers immediately; declining removes the request. Answering a request marks the bubble seen again, so a follower the owner just accepted doesn't count as unread. Tapping a person opens a visit to their Mosaic, which shows its own lock and request flow when private. Each follower row has one Instagram-style button, using follow state that `circle_people` returns with the list. **Following** opens a menu that unfollows their Mosaic through `unfollow_mosaic`. **Requested** means the owner is waiting on a request to see the person's private Mosaic. **Follow back** (they follow the owner's Mosaic) and **Follow** (they follow only a Pursuit) call `follow_mosaic` when the person's Mosaic is open to the owner, and otherwise `request_mosaic_access`. Someone without a Mosaic gets no button. Removing a follower from the Mosaic's list removes all of their follows of the owner's Mosaic and Pursuits; this matches `unfollow_mosaic` on the follower's side, and the existing trigger revokes their approved access to private Pursuits. It also revokes their approved Mosaic access request, so following a private Mosaic again needs a new request. Removing a follower from a Pursuit's list removes only that Pursuit. Above Requests and Followers, a bubble shows its follower total (for example "Golf Followers") beside its Daily Visits. On the Circle itself, bubbles show only the red badge for new followers and pending requests; the total appears once a bubble is opened.

## Daily Visits

**Decision:** Daily Visits is the number of distinct people, other than the owner, who opened that Mosaic or Pursuit since midnight in the owner's time zone. A person counts once per day however often they open it. Opening a Mosaic and then one of its Pursuits counts once for each. A visit that stops at a private lock doesn't count.

**Current repository fact:** `supabase/migrations/20261014213437_daily_visits.sql`, applied to the live project along with an index in `20261014213510_daily_visits_document_index.sql`, adds a `visits` table that the app can't read or write directly, plus two functions for signed-in users:

- `record_visit(p_document_id)` saves a visit only when the caller isn't the owner and passes the same checks that decide what a visitor sees (`viewer_passes_mosaic_gate` for a Mosaic, `viewer_can_open_pursuit` for a Pursuit). Repeat opens by the same person within 10 minutes add no row. Anything it ignores returns quietly.
- `circle_visits(p_time_zone)` returns distinct visitors since midnight in that zone for each of the caller's boards, falling back to UTC for an unknown zone. Owners see counts only, never who visited.

The app reports the visited Mosaic when it opens and each Pursuit page the visitor can open, once per visit. Reports run in the background and failures are ignored. A Circle bubble reads `circle_visits` with the device's time zone alongside its people list. Until the migration is applied, or when the read fails, Daily Visits shows a dash.

**Reversible choice:** `supabase/migrations/` is the first versioned backend SQL in this repository. The live project's earlier migrations (`backend_skeleton` through `accept_request_follows`) are not in it yet.

**Decision:** Visit rows are kept for 90 days, so future visit analytics have history to draw on. Only today's count is read now. Each recorded visit deletes rows older than 90 days, so no scheduled job is needed.

To verify after applying the migration, use two accounts. Visiting the other account's Mosaic and a public Pursuit should raise each Daily Visits by one, and visiting again the same day shouldn't change them. Opening your own boards, or reaching a private lock without access, should leave them unchanged.

**Current repository fact:** In Settings, typed names, a new profile picture, and privacy choices all wait for Save. Save writes them, pushes the boards immediately instead of after the usual pause, and closes Settings; if anything fails, Settings stays open with a message and the unsaved choices kept. Closing with unsaved changes asks "Save your changes?" with Save (saves, then closes), Discard (closes without saving), and Keep editing. A new profile picture is framed (drag and pinch inside the circle) before Save uploads it. The copy button beside the picture copies `mosaic://@username`; opening that link in the app switches to Discover and opens that person's Mosaic, or the owner's own Mosaic tab. In view mode on the owner's own Mosaic, their profile picture sits beside the eye button and copies the same link. When visiting someone else's Mosaic, including a private one shown locked, tapping the owner's picture shows it larger and still round, with a copy button on the circle's lower right that copies that person's link. The app opens in edit mode; the eye switches to view mode, where it becomes a pencil that switches back. The bottom-row buttons are all the same size, and the row looks the same on the Mosaic and on a Pursuit board or page; the back arrow on a Pursuit board, page, or visited Mosaic sits at the top left instead, as a small frosted circle the same height as the scroll bubble and level with it.

**Current repository fact:** In view mode on the owner's own Mosaic, a "View as" pill with **Me** and **User** sits between the profile picture and the pencil. Every switch into view mode starts on **User**, which shows Pursuit widgets the way a visitor with no approved requests sees them: hidden Pursuits, and Pursuits the server has no row for yet, disappear (inside groups too), and private Pursuits show the visitor lock. **Me** shows everything the owner built. In edit mode, hidden Pursuit widgets carry an eye-slash badge and private ones a lock. Privacy levels come from the same `documents` read Settings uses, refreshed on each switch between edit and view mode and updated as soon as Settings saves a change. Until they load, the pill reads "Checking…" and the board shows everything. **Reversible choice:** the preview applies the server's visitor rules on the phone rather than fetching the board through `viewer_boards`, so the two must be kept in step. It covers Pursuit widgets only; it doesn't preview a private Mosaic's locked page, and tapping a locked Pursuit in the preview still opens it for the owner. **Open question:** previewing as a specific person who has approved access.

**Reversible choice:** The Mosaic link uses the app's custom URL scheme, so it only opens on a device with Mosaic installed. A web link would need a domain and universal-link setup.

**Current repository fact:** Circle and Discover each have the composer's add menu in the lower right, limited to Background, which opens the same color, gradient, and photo editor as boards. Each page keeps its own background.

**Reversible choice:** Circle and Discover backgrounds stay on the phone, in `page-backgrounds.json` inside the signed-in account's folder, and do not sync. Their photos are saved in that folder's media, but no board refers to them, so they are not uploaded and visitors never see them. A new phone or reinstall starts with the default background. Syncing them later would need private storage that visitors can't read, since the Mosaic document is visible to them.

**Reversible choice:** Keep the existing `viewer_boards` RPC, which returns all authorized layout JSON together. Media is loaded on demand per board; per-board metadata requests, viewport-level media loading, and adaptive video streaming remain future work. No Supabase schema or configuration changes are required for this visit flow.

## Limits

**Current repository fact:** This restores a fresh or starter-only account installation. It is not continuous multi-device synchronization: an established local copy is not replaced on every login, and automatic merging of conflicting offline edits is not implemented.

**Current repository fact:** GIFs play in media and carousel blocks, the photo viewer, board backgrounds, banners, and Pursuit widget backgrounds. An imported GIF keeps its `.gif` filename and original bytes, so it uploads as `image/gif`; its display and thumbnail copies are still JPEGs. Playback decodes frames at most 540 pixels on the long edge and thins frames for long GIFs, keeping about 32 MB per GIF while preserving the total duration. GIFs imported earlier were saved as `.jpg`: they play on the owner's device, but visitors see a still. Content card covers and the Pursuit editor's preview stay still.

**Open question:** Whether the Supabase `media` bucket's allowed MIME types include `image/gif` is configured outside this repository.

Only media uploaded and referenced by a cloud asset can be restored. Files that never reached Supabase cannot be recovered from it. Boards stay usable. Already established local boards are not refreshed from other devices by this downloader.

**Current repository fact:** A board is saved before its new media uploads, so a board can reference a file the cloud never received, for example when an upload fails, or the phone's copy is lost before an upload succeeds. The app handles that case without failing silently:

- Before downloading, the restore looks for each missing file in older copies of the boards on the phone (the `.before-restore-*` folders and the pre-account Documents folder) and copies it back. A recovered file that has no cloud copy is uploaded by the next sync.
- A loading spinner shows only while a copy is on its way: during a restore, while the owner's download of that file is pending, or before and during a visited board's media fetch. Otherwise a missing or unreadable photo or video shows "Photo unavailable" or "Video unavailable" in media blocks, carousel cards, and the full-screen viewer. When the owner selects the block in edit mode, the placeholder offers Replace, which opens the photo library for that block. A failed replacement keeps the block. The placeholder is the only signal; there is no banner for missing media. Any media block, including one inside a group, can also be replaced from its media menu: Replace (two arrows) sits beside crop, beyond it from the menu icon. A replacement keeps the frame shape and resets zoom and pan; cropping or trimming keeps them.
- A file that can't be read or uploaded keeps no cloud asset, so every later sync tries it again.

## Verification

`ComposerAccountRestoreTests` covers landing-board-first opening, delayed children and media, saved revisions, pagination, account filtering, failed downloads, relaunch/resume, edits and undo during downloads, upload gating, media refresh identities, starter recognition, UUID casing, and malformed responses. Network responses are mocked; tests do not modify a live Supabase project.

Visitor tests also cover per-board media requests, repeat-visit cache reuse, failed-download retry, cancellation before download, changed/removed asset invalidation, and unsafe paths. For manual verification, open another person’s Mosaic on a slow connection: text/layout should appear first, media should fill in, and unopened Pursuit media should not download. Open a Pursuit or scrapbook page, retry a failed file, then revisit to confirm cache reuse. A private board without access should remain locked: request access, confirm the lock turns amber, decline from the owner's Circle, and confirm the lock returns to white without the board opening.

Run the Mosaic unit tests on an installed iPhone simulator. For a manual check, use an account with known uploaded boards and media on a fresh app installation: sign in and use the main board while the download banner is present; edit some text, open a pending Pursuit, and verify the content appears without losing your edit. Check photos/videos as they arrive, retry after a failed connection, and verify an interrupted download resumes after relaunch. Existing cached boards should also open offline. Keep the old installation until cloud restoration is confirmed.

## Content link cards

**Current repository fact:** Content is available in both Mosaic and Pursuit add menus. It uses the existing `link` block kind with a `content:<platform>` marker in `socialPlatform`, plus `linkURL`, `text`, and `mediaFileName`. Older clients can decode it as a link rather than rejecting an unknown block kind. An older client may display only its title/URL. No backend schema change is required.

The Content editor shares Socials’ logo picker and styled link field, with a preview section below. Content accepts a full URL only; it does not use Socials’ username-to-profile-URL conversion.

The editor validates HTTPS post/video URLs for YouTube, Instagram, TikTok, and Twitch, detects the source, and uses Apple's Link Presentation framework to request a title and image. Preview requests are made on the author's device, not during visitor board loading. Missing previews can be retried or supplied as a cover photo; saving a link without a cover is also supported. Cover images are resized to at most 1280 pixels on the long edge and use the existing media catalog, upload, cache, and visitor-download flow.

Instagram and TikTok cards take the cover's own shape; YouTube and Twitch cards stay 16:9. Because Instagram's Link Presentation image is often a square crop, the editor also reads the full image from the post's public embed page, accepting only Instagram/Facebook CDN hosts. Twitch pages carry no title or thumbnail for Link Presentation, which looks like a browser; Twitch adds them only for link-preview bots. For Twitch links the editor therefore also requests the page as `MosaicLinkPreview/1.0`, a bot identity of its own, and uses its title and thumbnail, accepting only Twitch's `static-cdn.jtvnw.net` host and skipping Twitch's generic logo. Twitch often answers the first request for a VOD with its generic page and the real one about a second later, so the editor asks up to four times, a second apart. When that yields nothing (short `clips.twitch.tv` links, which lack the channel, and removed videos), Link Presentation's result or a chosen cover photo is used instead. Authors can reposition the cover inside the card in the editor preview, crop it with the media frame editor, and resize the card from its corners.

In edit mode, tapping a selected Content card edits it; dragging and pinching use the board's existing gestures. In view mode, tapping opens the validated HTTPS source link through iOS. Source-app routing depends on installed apps and their universal-link support; a website may open instead. There are no embedded players. This does not change video upload or audio behavior.

**Reversible choice:** Use system link previews without provider credentials for this first version. Automatic thumbnail availability varies by platform, post permissions, and network conditions; it is not guaranteed for all four sources. The Twitch bot request relies on undocumented Twitch behavior and may stop working; Twitch's credentialed API would need a server-side secret. Twitch channel/live-stream links are not included in this version; clips and VOD links are supported.

`ComposerContentTests` covers supported share/post URLs, rejected schemes and lookalike domains, menu availability, serialization, and thumbnail inclusion in board sync. Manual device checks should cover adding/editing/canceling, a missing preview and custom cover, drag/pinch/group behavior, visiting a restored card, and opening links with and without the source apps installed.

## Mixed carousels and calendar days

**Current repository fact:** Carousel items, which calendar days also use, may be a photo or video, a social profile, or a content link, in any mix and order. Each item records `kind`, `platform`, `link`, and `title` alongside `fileName`. Items without a `kind` decode as media, so existing boards are unchanged. Each card keeps its item's shape: a photo or video's own proportions (between 1:2 and 2:1), a content card's shape, or a social's square logo with its handle below. A content item's cover is its `fileName`, so it uploads and downloads like other media; socials have no file. Placing a carousel opens its editor instead of the photo picker, and a carousel closed before anything is added is removed. In view mode, and inside a calendar day, tapping a centered social or content card opens its link and tapping a photo or video opens it full screen. A carousel needs only one item. A single item sits centered and doesn't swipe; with two or more the strip wraps, so with two the other item shows on both sides of the center. An empty calendar day shows one dashed placeholder card. A calendar day's notes start closed and open on their own once they have text; a visitor doesn't see empty notes.

**Assumption:** Older app versions show a social item as a loading card, and drop social items if they edit that calendar day.
