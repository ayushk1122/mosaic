# Explore, cards, and following updates

**Owner:** Mosaic team
**Status:** Current repository fact, with the product decisions it rests on labeled below

**Decision:** Following other people and seeing when the boards you follow change are part of the MVP, confirmed by the product owner on 2026-10-22. This replaces the "social features" deferral in [AGENTS.md](../../AGENTS.md) and [Golf Iteration 0](golf/iteration-0.md) for the features below; those documents still describe the earlier Golf iteration and haven't been reconciled.

## Tabs

**Decision:** The app has four tabs: Mosaic, Orbit, Circle, and Explore (product owner, 2026-10-23). Orbit, the daily catch-up, was called Today. Discover is gone: its people search moved into Explore and its following lists into Circle.

**Decision:** Tapping the tab that's already open goes back to where that tab starts (product owner, 2026-10-23).

**Current repository fact:** How each tab goes back to its start:
- **Mosaic and Circle:** they start over, closing anything opened on top. Circle keeps the side it was on.
- **Explore:** it closes what's open, cancels a search, and scrolls the feed to the top, without reloading or reshuffling it.
- **Orbit:** every board page closes what was opened from it, and Orbit opens on the first board not done.

**Current repository fact:** Mosaic, Orbit, and Circle use the app's own template icons (`MosaicMonogramTab`, `OrbitTab`, a planet on a tilted ring with a sparkle, and `CircleTab`, two arcs around a center with a dot in each gap); Explore uses `sparkles`. **Reversible choice:** the icons' drawings and the tabs' order.

## Circle

**Decision:** Circle has two sides, **Me** and **Following**, switched by tabs across the top that control the whole page.

**Current repository fact:** The tabs each take half the width, with a white bar under the side that's showing; the bar slides with a sideways swipe, which also switches sides, and the tabs stay at the top while the side below scrolls. Me is the owner's Pursuits around their Mosaic, as before. Following has two columns, Pursuits and Mosaics, each with its own search field; a row opens the board, holding it offers Unfollow, and the blue update dot is described under [Following updates](#following-updates). The lists reload each time Following is shown. Circle opens on Me the first time, then on the side that was showing last (kept on the phone). One page background covers both sides. **Reversible choice:** the tab style and the two-column layout.

## Explore

**Decision:** Explore shows Mosaics and Pursuits their owners chose to share there. Sharing to Explore is a separate opt-in from making a board Public, and nothing is shared by default.

**Decision:** Only a Public board on a Public Mosaic can be shared. A Pursuit on a private Mosaic can't be, and a board that stops being Public leaves Explore at once; a Mosaic that goes private takes all of its owner's boards out.

**Current repository fact:** Settings has a small **Explore** switch beside each eligible board's privacy picker. Turning a board Public asks "Share to Explore too?". The server enforces the rules above in `set_explore_sharing`, and the `documents_leave_explore` trigger turns sharing off whenever visibility leaves Public (`20261022010000_explore.sql`).

**Current repository fact:** The Explore tab (last, with the `sparkles` icon) is a three-column grid of 3:4 previews. Each tile shows the owner's picture and "Name", or "Name: Pursuit" for a Pursuit. Tapping a tile opens the board (a Pursuit opens on that Pursuit); tapping the picture opens the owner's profile card. The chips filter All, Mosaics, or Pursuits. Pulling down reshuffles. The page takes a background like Circle. The caller's own boards never appear.

**Decision:** Explore's search bar finds people, as on Instagram: while it's in use, the grid, chips, and sort step aside for the results, people first and then matching boards.

**Current repository fact:** The title and search bar stay at the top. Tapping the bar hides the grid (it keeps its place underneath) and shows Cancel. Typing searches names and usernames (a leading @ is ignored) and, under **Boards**, shared boards whose titles or owners match, most followed first, followed boards included. A person opens their Mosaic; the signed-in person is marked "You". Cancel clears the search and brings the grid back. A `mosaic://@username` link opens on Explore; an unknown name is left in the search bar.

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

**Decision:** Before any feed, the following lists (now on Circle's Following side) mark boards that changed since the follower last opened them.

**Current repository fact:** A blue dot sits beside each followed Mosaic or Pursuit with an update the follower can see, made after they last opened the board. A Mosaic is also marked when one of its Pursuits they can open has an update since they last saw that Pursuit or the Mosaic. Opening a board clears its dot; tapping a row opens the board directly. Updates from before someone followed a board don't count.

**Current repository fact:** Every save that adds pieces writes them to `board_additions` (a trigger on `documents`; a page's pieces count toward its Pursuit; kept 30 days), and `board_visible_additions` filters them to what the caller can see now. Opening a board records when in `board_reads` through `record_visit`. Both tables are service-only. `my_follows` returns `has_update`, and Explore's Recently updated order uses the latest visible addition (`20261023070000_today_feed.sql`).

**Decision:** An update is any of these, on the board or in a node or page inside a Pursuit:

- a new piece (a text piece once it has words in it);
- something new inside a piece: a carousel card, a calendar day's photo or note, a list item, a tab, a graph point, a table entry, a scrapbook page;
- a different photo or video in a photo piece, or a new banner photo;
- about ten or more characters written into existing text (a note, list item, calendar note, or table entry), so fixing a typo doesn't count;
- a list item checked off.

Moving, resizing, rotating, restyling, cropping, reordering, deleting, changing a background, and changing privacy never count.

**Current repository fact:** `board_changes` compares a board before and after each save, walking only the pieces that changed (`board_addressed`, `20261023110000_update_addresses_faster.sql`).
- **Addresses:** every piece, and everything inside one with an id, a date, or a file, has an address (`car/carouselitems/<card>`, `cal/calendarentries/2026-10-22/media/<photo>`). A component added later gets addresses with no server change.
- **Changes:** each change names the piece it marks. Look and layout keys never count (`board_key_ignored`), and an item saved empty counts once it gets content.
- **Location:** Orbit lists, with each change, the nodes and pages it sits in, so the pieces that open them glow on the way to the change.

See [Orbit update navigation](../architecture/update-navigation.md), section 1.

**Reversible choice:** A piece taken off and put back counts as new again; a piece moved from one board to another counts as new on the one it lands on; the ten-character threshold.

**Open question:** Old preview images stay in storage after a new one replaces them.

**Open question:** A real feed of what changed (for example "Ada added 3 photos to Golf"), push notifications, and whether owners can make quiet edits.

## Orbit

**Decision:** The catch-up tab is called **Orbit**, "your daily orbit": a distinctive name that also works as a noun for the brand (product owner, 2026-10-23; it was called Today). The server function keeps the name `today_feed`.

**Decision:** Orbit shows, one board at a time, the followed boards that gained pieces the follower can see in the last 24 hours: Pursuits they follow, and Mosaics they follow when pieces are added to them. Only boards they follow themselves appear: following someone's Mosaic doesn't bring in their Pursuits (product owner, 2026-10-23; `20261023120000_orbit_followed_only.sql`). Boards they haven't opened since come first, newest first. It ends with "You're all caught up". Older updates aren't kept here; the dots on Circle's Following lists and the boards themselves are always there.

**Current repository fact:** `today_feed()` returns each board with its owner, the time of its latest addition, the pieces added (id and kind, newest first), and whether the follower has opened it since.

**Current repository fact:** The Orbit tab (second, with the `OrbitTab` icon) shows a badge with the number of boards not done, refreshed whenever the app becomes active. Boards page sideways under one glass header; each board reaches the top of the screen, starts below the header, and scrolls beneath it. The header has the **trail** and, below it, "Ada · Golf" and how long ago.

- **Circles:** one per board, 44 points: the Pursuit's cover, or the owner's picture for a Mosaic.
- **Lines:** each board's line grows as its updates are seen and turns green when they all are. A finished board's circle fades.
- **Current board:** its circle has a white outline and glow.
- **The end:** the trail ends in a check node for the caught-up page.
- **Many boards:** the trail scrolls rather than shrinking. Tapping a circle goes to that board.

Below the header is the board itself, read-only, as on a visit. Scroll it, open Pursuits and nodes from it (they open within the page and go back to it), and use the owner's picture and the Pursuit bubble for follow, links, and cards. Visit Mosaic slides the Mosaic in over the page, outside Orbit's update walk. The header and navigator step aside, sideways swipes between boards pause, and the Mosaic's back arrow or a swipe in from the left edge returns to the page. Whatever has an update glows (the **spotlight**), with no outline or tag. That covers a piece, a carousel card, a calendar day, or a list row, and the containers and the node, Pursuit, and scrapbook pieces on the way to it. The glow fades once what's in it is seen.

**Current repository fact:** A board is done when all its updates have been seen, and it stays done until something more is added to it that day.
- **Order:** boards not done come first and done boards go last, each newest first.
- **When it's rebuilt:** when the Orbit tab is opened, when the app becomes active, and on Check again, but not while someone is inside a node or on the owner's Mosaic. It never reorders while paging.
- **Where it opens:** on the first board not done, or on the caught-up page.
- **Kept on the server:** what's been seen goes to the server (`orbit_seen`), so it holds across devices and reinstalls. See [Orbit update navigation](../architecture/update-navigation.md), section 7.

**Current repository fact:** A navigator pill at the bottom left ("3 of 7", up for the update before, down for the next) glides the board to each update in reading order. That update lifts slightly and glows brighter with one pulse, and the rest of the board dims by half while it's on screen.
- **Nodes:** when the next update is inside a node, Next opens the node and continues there, then closes it after its last one.
- **Next board:** after the board's last update, Next moves on to the next board.
- **Stops:** each update goes to the finest place showing it: a carousel card (Next turns the carousel), a calendar day (Next turns to its month), a list row, or a piece inside a group. Tabs, graph points, and table rows are reached through their piece. Something inside a thing that was added counts with it.
- **Checking off:** reaching a stop with the navigator checks off everything it covers.
- **Seen without the navigator:** a card counts once centered and mostly on screen, a day once its month shows it, and anything else once mostly on screen. Opening a day also checks off what's on it.

A light haptic plays when a board is done; when every board is done, every line is green, the header says "All caught up", and a stronger haptic plays. The last page is "You're all caught up" ("That's your daily orbit."), with Check again and Explore. Signed out, Orbit says "Sign in to see your daily orbit". **Reversible choice:** the tab's place and icon, the highlight and navigator's look, and that "mostly on screen" means half the piece (or half the screen for a taller one). **Open question:** updates on a tab that isn't open aren't reached by the navigator.

**Decision:** The trail replaced the progress bars, the spotlight replaced the outline and "New" tag, and boards are ordered as with Instagram Stories, with no limit on boards per day. See [Orbit update navigation](../architecture/update-navigation.md), sections 2 and 5 to 7.

## Verification

`supabase/tests/07-explore.sql`, `08-profile-card.sql`, `09-following-updates.sql`, `11-today-feed.sql`, `12-today-changes.sql`, `13-orbit-seen.sql`, and `14-update-addresses.sql` cover eligibility, privacy, sorting, paging, follower-count gating, update marks, and the Orbit feed (`today_feed`). `MosaicExploreTests`, `MosaicOrbitTests`, and `ComposerBoardSyncTests` cover feed requests, preview framing, links, badges, and clearing marks. For a manual check, use two accounts: share a Public Pursuit from one, find it on Explore from the other, follow it from its card, edit it on the first account, and confirm the dot appears in the second account's Circle Following list and clears when the Pursuit is opened. The UI launch test checks the four tabs, Explore's search taking over from the grid and Cancel bringing it back, and Circle's Me and Following tabs and swipe.
