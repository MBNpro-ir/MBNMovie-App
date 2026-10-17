"""Loopback-only video fixture with the same Range behavior as streaming CDNs."""
import http.server
import pathlib
import re
import sys
from urllib.parse import urlsplit

directory = pathlib.Path(sys.argv[1]).resolve()
assert directory.is_dir()
port = int(sys.argv[2]) if len(sys.argv) > 2 else 8765
fixtures = {"mbn-compatibility.mp4", "mbn-legacy-h264.mkv", "mbn-legacy-fallback.mkv"}

class Handler(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.serve(True)

    def do_GET(self):
        self.serve(False)

    def serve(self, head):
        name = urlsplit(self.path).path.removeprefix("/")
        if name not in fixtures or not (directory / name).is_file():
            self.send_error(404)
            return
        fixture = directory / name
        size = fixture.stat().st_size
        start, end = 0, size - 1
        value = self.headers.get("Range")
        if value:
            match = re.fullmatch(r"bytes=(\d+)-(\d*)", value)
            if not match or int(match[1]) >= size:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            start = int(match[1])
            end = min(int(match[2]) if match[2] else end, end)
        self.send_response(206 if value else 200)
        self.send_header("Content-Type", "video/mp4" if fixture.suffix == ".mp4" else "video/x-matroska")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if value:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if head:
            return
        try:
            with fixture.open("rb") as stream:
                stream.seek(start)
                remaining = end - start + 1
                while remaining:
                    chunk = stream.read(min(65536, remaining))
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass

http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
