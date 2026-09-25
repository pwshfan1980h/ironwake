#!/usr/bin/env python3
"""Serve the Godot web export locally:  python3 tools/serve_web.py  ->  http://localhost:8060
Deep links: #mission (skip title), #play (skip title, film and drop)."""
import functools, http.server, os, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8060


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # not required for the no-threads build, but lets a threaded export work too
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


http.server.ThreadingHTTPServer.allow_reuse_address = True
print(f"Iron Wake: http://localhost:{PORT}")
http.server.ThreadingHTTPServer(("", PORT), functools.partial(Handler, directory=ROOT)).serve_forever()
