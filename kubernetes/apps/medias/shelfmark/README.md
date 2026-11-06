# Shelfmark

[Shelfmark](https://github.com/calibrain/shelfmark) is the search and download
front end for the Calibre library: pick a title, choose a release, and the file
is written into the ingest queue Calibre-Web watches.

- `https://shelfmark.lafranque.net` — web interface.

It runs as UID 1000, in its documented Kubernetes mode, and keeps its own login
(it does not reuse the Calibre-Web accounts).

## Storage

- `shelfmark-config` (1 GiB) — database, settings and artwork cache.
- `calibre-ingest` — the ingest queue, declared with the Calibre application in
  `../calibre/nfs-pv.yaml` and mounted here at `/books` (`INGEST_DIR`).

Downloads must land on the NFS share rather than on a local volume because
Calibre-Web, in another pod, imports them from the same directory.
