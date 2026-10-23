# Orbit update navigation: addresses, anchors, reveal hosts, spotlight, and trail

**Owner:** Mosaic team
**Status:** Built: steps 1 (done, order, and trail), 2 (server addresses), 3 (anchors and spotlight), and 4 (reveal hosts), plus the checklist below. The current behavior is described in [Explore, cards, and following updates](../features/explore-and-following.md).

**Decision:** Orbit's navigator (Orbit was called Today) moves off per-component code onto a general mechanism, so new components get update tracking, marks, and navigation with little or no new code. Confirmed by the product owner on 2026-10-23.

**Decision:** The same sweep changes how Orbit looks (product owner, 2026-10-23):

- The per-board progress bars become a **trail**: a circle for each board, joined by lines that grow as its updates are seen, with the current board's circle outlined. The circles stay large enough to see, the trail scrolls, and tapping a circle goes to that board (section 5).
- The box outline and "New" tag around updated pieces become a **spotlight**: a glow around the new thing itself, with no icon, brightest on the update the navigator is on (section 6).
- A board whose updates have all been seen is **done** and stays done unless more updates arrive within the day. As with Instagram Stories, boards not yet done come first and done boards move to the end. Orbit shows every board with updates that day, with no limit (section 7).

## Why

Before this sweep, every component was wired by hand on both ends:

- The server (`board_units` in `20261023080000_today_changes.sql`, replaced in step 2) named where carousel cards, calendar days and their photos and notes, list items, tabs, graph points, and table entries live in a saved board.
- The app builds (until step 3) stops, marks, and "seen" rules separately for carousels, calendars, groups, and nodes (`MosaicComposerView.updateStops`, `ComposerCarouselBlock`, `ComposerCalendarBlock`, `ComposerNewPieces.itemStops`).

Each new component, and each new place content can hide (a new kind of container, a deeper nesting), would need both ends written again. The goal of the navigator is to catch someone up on everything new as quickly as possible, wherever it is.

## Design

Three parts share one idea: every new thing has an **address**, a path that says where it lives in the saved data. The server finds addresses from the data itself, the app labels where each address appears on screen, and containers that hide content say how to show an address.

### 1. Addresses from the saved data (server)

A board's body is JSON. Almost everything a person adds already carries an `id`: pieces (`id.rawValue`), carousel cards, list items, tabs, graph points, table rows and entries.

**Built (step 2):** a generic walk of each piece's JSON replaced the field-specific `board_units` (`board_addressed` and `board_changes`, `20261023100000_update_addresses.sql` and `20261023110000_update_addresses_faster.sql`).

- **Pieces:** any object with `id.rawValue` and a `kind` is a piece, including pieces inside groups. Its address is its id.
- **Items:** an object inside a list is an item if it has a string `id`. Failing that, its date (`year`, `month`, `day`, as `2026-03-05`), or failing that its `fileName`, names it. Its address is the address of what holds it, the list's key, and that name, all lowercased:
  - `car/carouselitems/<card>`
  - `cal/calendarentries/2026-10-22/media/<photo>`
  - `list/listitems/<item>`
  - `tbl/tableentries/<entry>/rows/<row>`
- **Everything else** in an item or piece is one of its fields: text, files (keys ending in `fileName`), and checkboxes (`isChecked`). That includes strings in a plain list, like a table row's cells (`cells.2`).
- The board around a piece is part of the address too: Orbit's feed already returns the nodes and pages a change sits in (`in`), so a full address reads `<pursuit>/<node>/<page>/<piece>/<key>/<id>/…`.
- **Changes**, compared address by address between the saved versions before and after:
  - something with content that wasn't there, or was there empty: **new**, recorded as its address. A blank list item that gets words, or an empty table row that gets a score, counts at that point.
  - a text field that grew by ten or more characters: **writing**, `address#text:<field>`;
  - a checkbox turned on: **checked**, `address#on:<field>`;
  - a different file: **new photo or video**, `address#file:<field>`.
- **Content:** a piece has content once placed, except containers (groups, tab sets) and text and headings waiting for words. Anything else has content once it holds text, a file, a ticked box, or a number.
- **Ignored keys:** look, layout, identity, and references never count, listed in one place (`board_key_ignored`):
  - position, rotation, style, scale, sizes, pan and zoom, opacity, shadows, frames other than captions, and tab styling;
  - indexes, selections, locks, backgrounds, drawing strokes, ids, kinds, and dates stamped on entries;
  - any key ending in `ID` or `IDs`, or in `X` or `Y` after a lowercase letter.

  Moving, restyling, cropping, and reordering stay invisible.
- **Only changed pieces are walked:** a piece saved exactly as it was can't hold a change, so it's skipped.
- Visibility filtering doesn't change: a change counts for a viewer while its piece is on a board they can see (`board_visible_additions`).

**Changed from the proposal:** calendar entries needed no stored id. The server names a day by its date, as the app's `CalendarDayEntry.id` does, so the app writes nothing new. Table cells are addressed as the row plus the cell's position, which answers that open question.

**Until step 3:** the app reads the carousel's and calendar's addresses back into the names those components use (`card/<id>`, `day/2026-3-5/<id>`, a day's own content as `day/…/note`), in `MosaicOrbitItem.Piece.componentItem`. Changes recorded before step 2 keep their old names, which pass through unchanged. Step 3 removes this along with the per-component code.

**Reversible choice:** the deny list, the ten-character threshold, and that `is…` booleans count only when listed (`isChecked`).

### 2. Anchors (app): where an address appears

Any view that shows an addressable thing adds one modifier:

```swift
CarouselCard(item)
    .updateAnchor("carouselItems/\(item.id)", isPresented: isCenter)
```

- Anchors are collected through a SwiftUI preference into the board's update guide, only on boards opened from Orbit, so other boards pay nothing.
- Each anchor reports its frame on the board and whether it's **presented**: on screen and not set aside by its container. A carousel's side cards are anchored but not presented; that flag is the only thing a component says about itself.
- From anchors the navigator gets, with no per-component rules:
  - **marks:** an anchored address with a change gets the "New" tag and glow;
  - **order:** stops follow where things appear on screen (top to bottom, then left to right), with hidden ones placed at their container's position, in data order;
  - **seen:** an address is seen once its anchor is presented and mostly on screen, or when the navigator reaches it.

**Built (step 3):** `updateAnchor(_:isPresented:order:)` and `hiddenUpdateAnchors(_:)` in `ComposerUpdateGuide.swift`.

- **Collection:** anchors are measured in the board's canvas and collected by `ComposerUpdateAnchorKey`. A shown anchor wins over a hidden one under the same address. They're kept per board in the guide, not in the board's view state, so a carousel swiping doesn't redraw the board.
- **Where anchors are placed:**
  - every piece, and every piece inside a group;
  - each carousel card, shown while centered;
  - each calendar day in the month shown;
  - each list row.

  Carousels and calendars also place **hidden anchors**, at the container, for cards turned away and days in other months, so stops don't come and go as they turn.
- **Also anchored:**
  - **Graph points, tab chips, and table rows.** Tables also place hidden anchors for rows in entries not on screen.
  - **The banner.** It's always in view above the board (`isPinned`), is seen when the board opens, and comes first in the order.
  - **The ignored-keys list:** it now includes a table's on-screen `tableRows`. They copy the entry on screen, which every table has, so one row edit counts once (`20261023130000_table_rows_mirror.sql`).
- **Where an update goes (`ComposerUpdateGuide.target`):**
  - something inside a thing that was **added** goes with it, so a new carousel is one stop, not one per card;
  - otherwise, the deepest anchor holding it;
  - otherwise, its piece.

  Additions are told apart from changes by the server's id: a change has `#…` after its address.
- **Order:** by piece in reading order (a group's pieces right after it), then in the order the container keeps them (cards as arranged, days by date, rows top to bottom), then by position. This differs from the proposal's pure screen order. A shown card and a hidden one are measured at different places, which would otherwise scramble them.
- **Board's part:** the board says only which updates are on it and which pieces open nodes or pages with updates (`ComposerUpdateGuide.Plan`).
- **Removed:** the per-component stop, seen, and mark code; the item names from step 2; and `composerNewItems` and `composerNewPieces`. Seen is recorded under each update's address.

### 3. Reveal hosts (app): containers that hide content

A few components show only part of what they hold: a carousel one card, a calendar one month, tabs one tab, a scrapbook one page, and a node or Pursuit widget a whole board behind a tap. Each registers how to reveal an address under it:

```swift
.revealHost("carouselItems/") { address in turnTo(address) }   // carousel
.revealHost("calendarEntries/") { address in showMonth(of: address) }   // calendar
.revealHost(boardID) { _ in open(board) }   // node or Pursuit widget
```

**Navigating to an address:**

1. If its anchor is presented, glide the board so it's centered, and mark it.
2. If not, find the deepest host whose prefix matches the address, ask it to reveal, wait (up to about half a second) for the anchor to appear, and repeat.
3. If a host opens another board, the new board's anchors and hosts take over, and back returns to where the navigator was, as it does now.

Nesting works by repetition: a card in a carousel, in a group, in a node, in a Pursuit is a chain of reveals, and none of the hosts know about the others.

**Built (step 4):** `revealHost(_:claim:reveal:)` in `ComposerUpdateGuide.swift`.
- **Registering:** a view registers its host with the guide while it's on screen, for its board (`composerUpdateBoard`). `claim` says how closely it holds an address, and the closest claim wins.
- **The hosts:**
  - **Carousels:** they turn to a card.
  - **Calendars:** they turn to a day's month, then open the day once the navigator is there (`open`), which checks off what's on it.
  - **Tables:** they turn to the entry with the update.
  - **The board's tab set:** it shows a piece on another tab. On someone else's board this lasts only for the visit, as tapping a tab does.
- **The reveal loop (`MosaicComposerView.reveal`):**
  - It glides at once to what holds the address, then asks the host and waits up to half a second for the address to show.
  - It repeats up to three times, so a card in a carousel on another tab takes two reveals.
  - A newer request stops an older one.
- **Every tab's updates are now planned,** tab by tab in the tab set's order, so updates on a tab that isn't showing are reached and a board with tabs can be done.
- **Journals:** a journal with updates on its pages is a stop that opens, like a node, on the page that has them. The page's updates are walked in turn, and the journal closes after the last one, so Next carries on. While a journal is open, the navigator stays and the header steps aside.
- **Changed from the proposal:** opening a node, Pursuit, or journal stays with the board view, which already owns that navigation, rather than becoming a host. Hosts reveal what's inside a board.

### 4. Fallback

An address with no anchor (a component added later, or something without ids) is navigated to through its nearest anchored ancestor, usually the piece. New components therefore work at piece level from the start; item-level precision costs one `updateAnchor` line, and only components that hide content need a reveal host.

### 5. The trail (Orbit's header)

Orbit's header currently has one thin bar per board, and it's hard to tell which bar is the board on screen. The trail replaces the bars with the boards themselves:

```text
(Golf) ━━━━━━━━ (Gym) ━━━━──── (Ada) ──────── ✓
 seen, faded     current        not yet         caught up
```

- **Circles:** one per board in Orbit's order: the Pursuit's cover for a Pursuit, the owner's picture for a Mosaic, and the owner's initial when there's no picture.
- **Connectors:** the line after each circle fills from left to right as that board's updates are seen (the same `progress(of:)` as the bars), so it grows as you work through the board. When everything on the board is seen, the line reaches the next circle and turns green.
- **Completed boards:** the circle fades, to about 40% opacity, once its connector is green.
- **The current board:** the circle of the board on screen has a white outline and a soft glow, at full opacity even when completed. Swiping to another board moves the outline there.
- **The end:** the last board's connector leads to a small end node, the "You're all caught up" page. It is outlined while that page shows, and turns green when every board is done; all connectors are green by then, and the existing haptics stay.
- **Size and scrolling (decision):** circles stay large enough to recognize, about 44 points with connectors at least 24, however many boards there are. The trail scrolls sideways to reach them all and glides to keep the current circle in view as boards change. There's no limit on how many boards a day's Orbit shows.
- **Header line:** below the trail, "Ada · Golf" and how long ago stay. The separate 34-point picture is dropped, because the outlined circle already shows whose board it is.

**Decision:** tapping a circle goes to that board; swiping still pages. Tapping the end node goes to the caught-up page.

**Accessibility:** each circle is one element, for example "Golf by Ada, 3 of 7 updates seen, current board". With Reduce Motion, connectors fill without animating and the glow doesn't pulse.

**Reversible choice:** the exact sizes, the 40% fade, the green, and the end node's look.

### 6. The spotlight (marks on the board)

The glow comes from the anchors in section 2, so every anchored thing gets it with no component code:

- **New, not yet reached:** a soft glow just outside the item's edges. There's no outline, no box, and no tag.
- **The update the navigator is on:** a stronger glow that pulses once on arrival. The rest of the board dims slightly around it, so the item looks lit by a spotlight.
- **Seen:** the glow fades out over a moment, so whatever still glows is what's left to see.
- **Containers on the way to an update:** node, Pursuit, and scrapbook pieces, and a carousel or calendar holding something new, get the same soft glow until what's inside is seen. When the navigator opens one, the spotlight moves inside.
- **Hidden items glow only when presented:** a carousel's side cards and days in another month don't glow, and their container glows for them.

**How it's drawn:**

- The anchor modifier draws the glow behind its own view, shaped like the view (rounded to match), so it follows the piece through scrolling, rotation, and resizing.
- The dimming is one layer over the board, with a soft cutout at the focused anchor's frame.
- Nothing is drawn on boards not opened from Orbit.

**Accessibility:** VoiceOver still says "New" in the item's value, since the tag that used to say it is gone. With Reduce Motion, there's no pulse and the glow fades instantly.

**Built (step 3):**
- **Glow:** white shadows on the anchored view itself, following its shape: glyphs for text, edges for photos.
- **Spotlit:** a third, wider layer, brighter overall; the thing lifts to 103% and pulses once when the navigator brings it up.
- **Seen:** it fades over 0.6 s.
- **Dimming:** a layer over the canvas (`ComposerSpotlightDim`), 50% darker, with a soft opening 26 points around the spotlit anchor so its glow shows in full. It started at 25%; the product owner found that too subtle on 2026-10-23. It shows only while that anchor is on screen, and clears when the board is scrolled away.
- **VoiceOver:** "Update: New" or "Seen" as custom content.

**Experiment:** how much to dim around the spotlight, if at all. Now 50% darker, raised from 25% after the first look. Keep it if moving from update to update is easier to follow on light, dark, and photo backgrounds; drop the dimming and keep only the glow if it makes the board feel hidden.

**Reversible choice:** glow size, strength, and color, the pulse, and the fade timing.

### 7. Done, and the order of boards

**Decision:** A board is **done** when everything new on it that day has been seen. It stays done, faded and at the end, unless someone adds more to it within the 24 hours. Then it's not done again, and only the new updates are left to see.

**Decision:** As in Instagram Stories, boards that aren't done come first and done boards go to the end, in the trail and in the pages alike.

What happens now, and what changes:

- **Now:** done means every update in the feed has its key in the phone's seen set (`MosaicOrbitModel.progress`). Keys are the piece, or the piece and item (`car/card/abc`), and are kept 36 hours.
- **Gap, repeat updates:** a second update to something already seen (ten more characters written in the same note, the same list item changed again) has the same key, so the board wrongly stays done. **Built:** `today_feed` returns each change's time with its piece (`at`). For each key, what's kept is the time of the version seen, taken from the feed rather than the phone's clock, and an update counts as seen only if its key was seen through its time or later. New updates to anything reopen the board, and nothing else does. Times are compared in the app, both read to the millisecond the same way.
- **Gap, unreachable updates (fixed in step 4):** updates on a tab that wasn't open were left out of the board's stops, so the board could never be done. Every tab's updates are now planned, and the tab set's host shows them.
- **Gap, removed content:** an update whose piece was deleted afterward can never be seen. `board_visible_additions` should leave it out; this needs checking with a test.
- **Order now:** the server puts boards not *opened* since their latest update first, newest first. **Built:** the app orders the deck itself (`MosaicOrbitModel.ordered`): not done first, by newest update, then done, by newest update. A partly seen board counts as not done. The server's `seen` (opened) no longer decides the order.
- **When the order changes:** never while someone is paging; a board finished now keeps its place until the next time Orbit is put together. That happens when the app becomes active, on Check again, and when the Orbit tab is opened again after leaving it. Then finished boards move to the end.
- **Where Orbit opens:** on the first board that isn't done. When everything is done, it opens on the caught-up page, with the trail all green and faded behind it.
- **Badge:** still the number of boards not done, so it agrees with the trail.

**Decision:** What's been seen is kept on the server, so a board done on one device is done on every device and after a reinstall (product owner, 2026-10-23). Owners never see who viewed their boards.

**Built:** `orbit_seen` (viewer, board, key, seen through) is a service-only table, written by `mark_orbit_seen(board, {key: time})` and returned with each board as `seen_keys` (`20261023090000_orbit_seen.sql`).
- **Writes:** later reports never lower a time, a time in the future counts as now, boards the caller can't read store nothing, and rows untouched for two days are dropped.
- **On the phone:** a copy of the last 36 hours makes progress instant and works offline. What's seen goes to the server three seconds after the last thing seen, before each feed load, and when the app goes to the background. Once per launch, the phone sends again everything it kept, in case a send was cut off. A send fails and is retried when the connection drops, the server errors, or a token has expired; one the server turns down for good isn't sent again.
- **Earlier progress:** progress already on the phone in the older format carries over.

## What it replaces

- Server: the field-by-field `board_units`; `board_changes` becomes the generic comparison.
- App: `ComposerNewPieces.itemStops`, `calendarDay(of:)`, `marksItemsItself`; the carousel's and calendar's own new-item, focus, and seen code; the group and node branches in `MosaicComposerView.updateStops` and `updateWatchPieces`; `ComposerUpdateWatcher` becomes the anchor collector.
- App, look: the header's per-board progress bars (`MosaicOrbitView.progressBar`) and the 34-point picture beside the name; `ComposerNewPieceMark`'s outline; `ComposerNewTag`; and the carousel's and calendar's own rings and tags. The trail and the anchors' spotlight take their place.
- Kept: the Orbit feed, progress per board (now drawn by the trail), the navigator pill, the glass header, the guide's board stack (nodes opening and closing), and `board_visible_additions`.

## Migration

One sweep, in this order. Each step ships on its own and leaves Orbit working.

1. **Done, order, and trail (built).** What's been seen is kept on the server; `today_feed` returns each change's time (old builds ignore it); seen keys keep their time; the deck is ordered not done first, done last, and rebuilt only at the moments in section 7. Then the trail: large circles in a scrolling row, connectors, the current outline, tap to go to a board, and the end node. This touches the feed, the model, and the header, so it comes first and can be judged right away.
2. **Server addresses (built).** Generic walk and comparison with the ignored keys; calendar days are named by their date, so no app data changed; `today_feed` returns the new addresses, and the app reads them into the carousel's and calendar's names until step 3. Additions from before roll out of Orbit within a day.
3. **Anchors and spotlight (built; tabs, graph points, and table rows still go to their piece).** The anchor modifier and collector; the guide orders stops and decides seen from anchors; the fallback. Carousel cards, calendar days and their entries, list items, tabs, graph points, and table rows add anchors. The anchor modifier draws the spotlight, the dimming layer follows the focused anchor, and the outline, tag, and per-component rings are removed with the per-component stop and seen code.
4. **Reveal hosts (built; opening boards stays with the board view).** Carousel, calendar, tabs, scrapbook, and node and Pursuit widgets register hosts; the navigator's reveal loop replaces the per-component turning and opening code, and the spotlight moves into whatever a host reveals.
5. **Checklist for new components (below).**

## Checklist for new components

When a component is added, three things decide how Orbit handles it:

1. **On the server:** keep anything a person adds inside it in lists of objects with an `id`, so each thing gets an address with no server code. Add the component's look and layout keys (sizes, styles, positions, selections) to `board_key_ignored`, so changing them never counts as an update.
2. **Anchor what it shows:** add `.updateAnchor("<piece>/<list key>/<id>", isPresented:, order:)` to each thing's view, lowercased as the server writes addresses. That gives it the glow, its own stop, and seen tracking. Without it, updates go to the piece, which already works.
3. **If it shows only part of what it holds,** add `.revealHost` with a claim on its addresses and a reveal that shows one, and `.hiddenUpdateAnchors` for the things it isn't showing, so their stops stay in order.

Add a database test with a before-and-after body for the component (`supabase/tests/14-update-addresses.sql`), and a unit test for its host if it has one.

## Testing

- **Database (pgTAP):** the generic comparison on fixtures for each existing component, including nested ones (a card in a carousel in a group, an entry in a calendar day), the deny list, writing, checked, and file changes, and that an unknown component's new `id`'d objects are found with no code.
- **Unit:** the reveal loop against fake hosts (one level, several levels, a host that never reveals, a host that opens a board); ordering from anchors with hidden items; seen rules; the fallback.
- **Unit, trail:** from a deck and its progress, each connector's fill, which circles are faded, which is current (including a completed board revisited), the end node's state, and the accessibility text.
- **Unit, done and order:**
  - A board stays done across a relaunch.
  - A repeat update to an already seen item reopens it, and only that update is left.
  - An update seen before it was made doesn't count.
  - The deck orders not done before done, partly seen as not done, and newest first within each.
  - The order holds while paging and changes only on a rebuild.
  - Orbit opens on the first board not done, or on the caught-up page when all are done.
- **Database (pgTAP), feed:** `today_feed` returns each change's time, and leaves out changes whose piece was deleted.
- **UI:** a fixture board, opened through a launch argument, with nested updates (a card in a carousel in a group in a node), stepped through end to end until every connector is green. Along the way, check that the current circle's outline follows each swipe, that the focused anchor reports it's spotlit (an accessibility value), and that no "New" tag remains. Take screenshots of the spotlight on a light, a dark, and a photo background for review.

## Risks

- **Trigger cost:** measured on the live database on 2026-10-23.
  - A typical save (one piece edited) on the largest real board, 56 KB, takes about 17 ms; changing half of that board takes about 36 ms.
  - A brand-new board near the 2 MB cap takes about 2.5 s, once, when it's first uploaded.
  - If that becomes a problem, walk new boards in the background instead of in the save.
- **Address stability:** ids must not change when items are edited. They don't today; components that regenerate ids would show everything as new.
- **Waiting on reveals:** a host that animates slowly could make a step feel late; the half-second wait and an immediate glide to the container keep it responsive.
- **Glow on light backgrounds:** a white glow can disappear on a white or pale board. A faint dark edge outside the white glow should keep it visible; check it on the screenshots above before step 3 ships.
- **Long trails:** with many boards the trail is wide; it scrolls rather than shrinking. It's a plain row, not a lazy one: a lazy row reused a stale view when ids shifted. Switch back only with ids that never collide, and measure first.
- **Glow cost:** blurred shadows on many pieces at once can slow scrolling. Draw the glow only on presented anchors, and fall back to a cheaper non-blurred halo if profiling shows dropped frames.

## Open questions

- Whether reordering items (moving a card earlier in a carousel) should ever count.
- How deep the navigator goes before stopping at a container (no limit is proposed; nesting is bounded by what boards allow).
