# ADR 0004: Whole boards, newest edit wins

**Owner:** Product and Architecture
**Status:** Accepted; replaces the conflict policy in [ADR 0003](0003-sync-conflict-and-media-queue.md)
**Date:** 2026-10-22

## Context

ADR 0003 kept a device's conflicting version behind a banner (Keep my version / Discard) so no edit was ever lost. Review found that keeping both sides correct in every case (a board deleted on one device and edited on another, Keep my version dropping boards made elsewhere, a second conflict on the same board) needed more machinery than an MVP warrants. Mosaic is mostly one person moving between their own devices, and the same board is rarely edited on two of them within a minute.

## Decision

**Decision:** A board is synced whole. When it changed on this device and on the server since this device last synced, whichever edit is newer stays: this device's last edit time against the time the server saved its version. There is no banner and no choice to make.

**Decision:** Deleting wins. A board deleted on another device is removed here even if it was edited here, and a save can't bring it back (`save_document` refuses with `document deleted`).

**Decision:** Editing works offline. Offline edits sync when the device is back online and win only if they are newer than what the server has.

**Reversible choice:** A version this device loses is saved on the phone (`replaced/` in the account folder) for 7 days, with nothing in the app showing it, so lost work can be recovered by hand if someone asks.

## Consequences

- Two devices editing the same board within the same minute or so: the earlier edit is lost from the board (kept only in the replaced folder of the device that lost it).
- Because a Mosaic is synced whole, a newer Mosaic version from one device can drop a Pursuit widget another device added in between; that Pursuit is then removed like any deleted board.
- Edit times come from the device's clock and save times from the server's, so a device with a badly wrong clock decides badly. Phones keep their clocks set automatically.
- Pulls on open, on returning to the app, every 60 seconds, and before every push keep the window for the cases above short.

## Status labels

**Open question:** Whether merging changes piece by piece is ever worth its complexity.
