"""Loopback-only video fixture with the same Range behavior as streaming CDNs."""
import http.server
import pathlib
import re
import sys
from urllib.parse import urlsplit

fixture = pathlib.Path(sys.argv[1]).resolve() / "mbn-compatibility.mp4"
assert fixture.is_file()

class Handler(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.serve(True)

    def do_GET(self):
        self.serve(False)

    def serve(self, head):
        if urlsplit(self.path).path != "/mbn-compatibility.mp4":
            self.send_error(404)
            return
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
        self.send_header("Content-Type", "video/mp4")
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

http.server.ThreadingHTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
