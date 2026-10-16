# ADR 0003: Sync conflict policy and media processing queue

**Owner:** Architecture
**Status:** Accepted
**Date:** 2026-10-16

## Context

The [beta-readiness review](../reviews/2026-10-16-beta-readiness.md) found that revision conflicts silently overwrite newer server documents (SYNC-01), and that the `media_jobs` queue has no observed consumer (OPS-01). Before hardening sync and media, the team needs settled behavior for both.

Apple Developer Program access and a hosted staging environment are deferred. Engineering work focuses on architecture, security, functional integrity, and local reproducibility so a later beta plan starts from a safe foundation.

## Decision

**Decision:** On a per-document sync conflict, the server revision wins presentation. The device’s conflicting local document is retained as a recoverable conflict copy. The board shows a banner offering Keep this version (push the local copy as a new revision) or Discard (drop the copy). Conflicts are not auto-merged.

**Decision:** Retire the unused media processing queue for the current product. Media readiness is established when the client-prepared upload is finalized. File-type limits, size limits, and account quotas are enforced at the Storage bucket and finalize RPC. A future server worker may be introduced when content validation, moderation, or server-side transcoding is required.

## Consequences

- Multi-device edits of the same board between syncs no longer silently erase either side’s work.
- Conflict UX stays rare if only dirty documents are pushed; automatic merge remains available later if evidence justifies it.
- Stuck `queued` / `processing` media job state is not treated as an operational pipeline.
- Client-side preparation (display/thumb variants, short video trim) remains the beta media path.

## Status labels

**Reversible choice:** Exact banner copy and whether a discarded conflict copy is kept offline for a short recovery window.

**Open question:** Whether a later merge-by-block strategy is worth the complexity after dirty-document sync ships.
