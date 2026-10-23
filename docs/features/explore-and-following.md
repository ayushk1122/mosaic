# Explore, cards, and following updates

**Owner:** Mosaic team
**Status:** Current repository fact, with the product decisions it rests on labeled below

**Decision:** Following other people and seeing when the boards you follow change are part of the MVP, confirmed by the product owner on 2026-10-22. This replaces the "social features" deferral in [AGENTS.md](../../AGENTS.md) and [Golf Iteration 0](golf/iteration-0.md) for the features below; those documents still describe the earlier Golf iteration and haven't been reconciled.

## Explore

**Decision:** Explore shows Mosaics and Pursuits their owners chose to share there. Sharing to Explore is a separate opt-in from making a board Public, and nothing is shared by default.

**Decision:** Only a Public board on a Public Mosaic can be shared. A Pursuit on a private Mosaic can't be, and a board that stops being Public leaves Explore at once; a Mosaic that goes private takes all of its owner's boards out.

**Current repository fact:** Settings has a small **Explore** switch beside each eligible board's privacy picker. Turning a board Public asks "Share to Explore too?". The server enforces the rules above in `set_explore_sharing`, and the `documents_leave_explore` trigger turns sharing off whenever visibility leaves Public (`20261022010000_explore.sql`).

**Current repository fact:** The Explore tab (third, between Circle and Discover, with the `sparkles` icon) is a three-column grid of 3:4 previews. Each tile shows the owner's picture and "Name", or "Name: Pursuit" for a Pursuit. Tapping a tile opens the board (a Pursuit opens on that Pursuit); tapping the picture opens the owner's profile card. The chips filter All, Mosaics, or Pursuits, and the search field matches board titles, display names, and usernames. Pulling down reshuffles. The page takes a background like Circle and Discover. The caller's own boards never appear.

**Current repository fact:** The Filters button sorts by Shuffled (default), Trending (most new followers in the last 7 days), Most followers, Fewest followers, Newest to Explore, or Recently updated, and has a **Hide boards I follow** switch. Boards the sort ranks equally keep the session's shuffled order, so paging never repeats a tile. All of this is `explore_feed` (`20261023020000_explore_more_sorts.sql`).

**Decision:** Hide boards I follow is on by default and remembered on the device, because Explore is for finding new people. It hides only boards followed directly: following a Mosaic doesn't hide its Pursuits.

**Current repository fact:** Previews are drawn on the owner's phone, off screen, as a visitor would see the board (hidden Pursuits removed, private ones locked, videos as still frames), at the phone's own width. The image is a 3:4 frame around the board's pieces, zoomed in no further than 60% of the board's width, uploaded as `media/{owner}/{asset}/display`. A preview is made when a board is shared, and again when the app becomes active if the board's content or its Pursuits' privacy changed, at most once an hour. When one of the owner's Pursuits changes visibility, the server drops their shared Mosaic's preview (the picture may show that Pursuit as it was), so the Mosaic is out of Explore until a new one is drawn; Settings draws it right after saving (`20261023060000_review_fixes.sql`). Only the `display` file of a preview's folder is readable through Explore. **Reversible choice:** rendering on the owner's device, the hourly refresh, and the framing rules. Raising `MosaicExplorePreviews.rendererVersion` redraws every shared board once.

**Open question:** Reporting, blocking, and moderation of shared boards. **Open question:** Age limits for Explore. Both are deferred to a later full pass once most features exist.

**Open question:** A Following view inside Explore. Followed boards that aren't shared to Explore have no preview image, so it is on hold.

## Profile and Pursuit cards

**Current repository fact:** Tapping someone's picture on an Explore tile, a visited Mosaic, or a visited Pursuit opens their **profile card**: the picture large with a copy-link button, name, @username, follower count, **Follow** / **Following** (unfollowing also unfollows their Pursuits) or **Request to view** for a private Mosaic, and **Visit Mosaic** where there is somewhere further to go.

**Current repository fact:** On a visited Pursuit, the Pursuit's bubble opens its **Pursuit card**: the cover large with a copy-link button, its name, "by @owner" (which switches to the owner's card), follower count, and **Follow** / **Following** or **Request to view**. The bubble and the owner's picture carry a badge: "+" when not followed, a check when followed, a white lock when private and closed, an amber lock while a request waits. The separate follow buttons on visited boards were removed; following happens in the cards.

**Decision:** Follower counts show only to people who may see that board (`profile_view` and `viewer_pursuits`, `20261023030000` and `20261023040000`).

**Current repository fact:** Links are `mosaic://@username` for a Mosaic and `mosaic://@username/pursuit/<id>` for a Pursuit. A Pursuit link the visitor can't open lands on the Mosaic with the request prompt; a broken Pursuit part still opens the Mosaic.

## Following updates

**Decision:** Before any feed, Discover's following list marks boards that changed since the follower last opened them.

**Current repository fact:** A blue dot sits beside each followed Mosaic or Pursuit with an update. A Pursuit is updated when it, or a page inside it, was saved after the follower last opened it. A Mosaic is updated when it was saved after they last opened it, or when one of its Pursuits they can open changed since they last saw that Pursuit or the Mosaic. Opening a board clears its dot; tapping a row opens the board directly. Changes from before someone followed a board don't count.

**Current repository fact:** Opening a board records when in `board_reads` through `record_visit`; the table is service-only, and `my_follows` returns `has_update` (`20261023050000_following_updates.sql`). The table started from the previous 90 days of visits.

**Reversible choice:** Any save counts as an update, including moving or restyling pieces.

**Open question:** A Mosaic's save time also moves when the owner changes something visitors can't see (their saved stickers, a hidden Pursuit's widget), so followers can get a mark, and Explore's "Recently updated" order can shift, for nothing they can see. A "visible change" time stamped by `save_document`, which would also make `my_follows` cheaper for people who follow many boards, is the likely fix.

**Open question:** Old preview images stay in storage after a new one replaces them.

**Open question:** A real feed of what changed (for example "Ada added 3 photos to Golf"), push notifications, and whether owners can make quiet edits.

## Verification

`supabase/tests/07-explore.sql`, `08-profile-card.sql`, and `09-following-updates.sql` cover eligibility, privacy, sorting, paging, follower-count gating, and update marks. `MosaicExploreTests` and `ComposerBoardSyncTests` cover feed requests, preview framing, links, badges, and clearing marks. For a manual check, use two accounts: share a Public Pursuit from one, find it on Explore from the other, follow it from its card, edit it on the first account, and confirm the dot appears in the second account's Discover list and clears when the Pursuit is opened.
