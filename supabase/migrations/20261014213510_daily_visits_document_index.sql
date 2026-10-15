-- Deleting a Mosaic or Pursuit removes its visits; this keeps that from scanning the whole table.
create index visits_document on public.visits (document_id);
