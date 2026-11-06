# Calibre

[Calibre-Web Automated](https://github.com/crocodilestick/Calibre-Web-Automated)
bundles Calibre's library tooling (`calibredb`, `ebook-convert`) with the
Calibre-Web front end, an ingest watcher and a KOReader sync endpoint.

Books searched in [Shelfmark](../shelfmark) land in the ingest queue this
application watches, so they join the library without any manual copy.

## Endpoints

- `https://calibre.lafranque.net` — web UI: upload books, edit metadata,
  convert formats.
- `https://calibre.lafranque.net/opds` — OPDS catalog consumed by KOReader.
- `https://calibre.lafranque.net/kosync` — optional KOReader reading-progress
  sync server.

## First login

The application creates its own `admin` account with the upstream default
password (`admin123`). Change it immediately under **Admin → Edit user**, then
create a dedicated account for the e-reader with only the *Download* and
*OPDS* permissions.

KOReader then uses that account for the catalog:

- Catalog URL: `https://calibre.lafranque.net/opds`
- Username / password: the account created above.

## Ingest queue

Calibre-Web watches `/cwa-book-ingest`, backed by the `calibre-ingest` volume.
Shelfmark mounts the same volume from another pod, so the queue lives on NFS
rather than on a block device. Inotify does not report writes made from
another node, hence `CWA_WATCH_MODE=poll`: the folder is scanned every five
seconds. The application deletes each file once it has been imported.

### Prerequisite

The NFS server (`10.243.2.11`) exports `/mnt/data-hdd/medias`; the volume
points at the `calibre-ingest` subdirectory, which must exist and be writable
by UID 1000:

```sh
mkdir -p /mnt/data-hdd/medias/calibre-ingest
chown 1000:1000 /mnt/data-hdd/medias/calibre-ingest
```

## Storage

- `calibre-config` (2 GiB) — Calibre-Web database, settings and sessions.
- `calibre-library` (30 GiB) — the Calibre library (`metadata.db` and books).
- `calibre-ingest` (NFS, RWX) — transient ingest queue shared with Shelfmark.

The deployment runs a single replica with the `Recreate` strategy: a Calibre
library is file-based and must not be written by two pods at once. It uses
`ceph-block`, so it is pinned to one node at a time by design.
