"""Keep a country MMDB for Envoy. Data: https://db-ip.com (CC BY 4.0)."""

import datetime
import gzip
import io
import os
from pathlib import Path
import sys
import time
import urllib.request


DATABASE = Path(os.environ.get("GEOIP_DATABASE", "/etc/envoy/geoip/country.mmdb"))
MAX_BYTES = 64 * 1024 * 1024


def refresh():
    today = datetime.datetime.now(datetime.timezone.utc).date().replace(day=1)
    months = [today, today - datetime.timedelta(days=1)]
    for month in months:
        release = month.strftime("%Y-%m")
        marker = DATABASE.with_suffix(".release")
        if DATABASE.is_file() and marker.is_file() and marker.read_text() == release:
            return
        url = f"https://download.db-ip.com/free/dbip-country-lite-{release}.mmdb.gz"
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "geoip-updater/1.0"})
            with urllib.request.urlopen(request, timeout=90) as response:
                compressed = response.read(MAX_BYTES + 1)
            if len(compressed) > MAX_BYTES:
                raise ValueError("compressed database exceeds size limit")
            with gzip.GzipFile(fileobj=io.BytesIO(compressed)) as archive:
                data = archive.read(MAX_BYTES + 1)
            if len(data) > MAX_BYTES or b"\xab\xcd\xefMaxMind.com" not in data[-131072:]:
                raise ValueError("invalid or oversized MMDB")
            DATABASE.parent.mkdir(parents=True, exist_ok=True)
            temporary = DATABASE.with_suffix(".tmp")
            temporary.write_bytes(data)
            temporary.chmod(0o644)
            # Envoy watches MOVED_TO and reloads the database after atomic replacement.
            temporary.replace(DATABASE)
            marker.write_text(release)
            print(f"Installed DB-IP Lite {release}", flush=True)
            return
        except (OSError, ValueError, EOFError) as error:
            print(f"GeoIP download {release} failed: {error}", file=sys.stderr, flush=True)
    raise RuntimeError("No country database downloaded; retaining the previous file if present")


if __name__ == "__main__":
    while True:
        try:
            refresh()
        except RuntimeError as error:
            print(error, file=sys.stderr, flush=True)
            if "--once" in sys.argv:
                sys.exit(1)
            time.sleep(60 if not DATABASE.is_file() else 3600)
        else:
            if "--once" in sys.argv:
                break
            time.sleep(86400)
