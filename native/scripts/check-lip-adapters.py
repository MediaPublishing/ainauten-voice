#!/usr/bin/env python3
"""Stdlib-only checks of private downloads and the camera-free IPC adapter."""
import base64
import contextlib
import hashlib
import http.server
import io
import pathlib
import sys
import tarfile
import tempfile
import threading
import unittest
import uuid

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lipreading_runtime"))
from setup_runtime import checked_download, unpack_verified
from worker import Reader


class AdapterChecks(unittest.TestCase):
    def test_resumes_and_verifies_download(self):
        body = b"public download test" * 128
        requests = []

        class Server(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                start = int(self.headers.get("Range", "bytes=0-").split("=")[1].split("-")[0])
                requests.append(start)
                self.send_response(206 if start else 200)
                self.send_header("Content-Length", str(len(body) - start))
                self.end_headers()
                self.wfile.write(body[start:])

            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Server)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
                target = pathlib.Path(directory) / "model"
                target.write_bytes(b"corrupted previous file")
                target.with_suffix(".part").write_bytes(body[:123])
                digest = hashlib.sha256(body).hexdigest()
                url = f"http://127.0.0.1:{server.server_port}/fixture"
                checked_download(url, target, digest)
                self.assertEqual(target.read_bytes(), body)
                self.assertEqual(requests, [123])
                self.assertEqual(len(list(target.parent.glob("model.invalid-*"))), 1)
                checked_download(url, target, digest)
                self.assertEqual(requests, [123])
                # A complete partial download also resumes without HTTP 416.
                completed = target.parent / "completed"
                completed.with_suffix(".part").write_bytes(body)
                checked_download(url, completed, digest)
                self.assertEqual(completed.read_bytes(), body)
                self.assertEqual(requests, [123])
        finally:
            server.shutdown()
            server.server_close()

    def test_archive_rejects_escape_and_skips_links(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            archive = root / "source.tar"
            with tarfile.open(archive, "w") as stream:
                item = tarfile.TarInfo("../escape")
                item.size = 1
                stream.addfile(item, io.BytesIO(b"x"))
            with self.assertRaises(RuntimeError):
                unpack_verified(archive, root / "unsafe")
            with tarfile.open(archive, "w") as stream:
                stream.addfile(tarfile.TarInfo("source/"))
                link = tarfile.TarInfo("source/link")
                link.type = tarfile.SYMTYPE
                link.linkname = "/private"
                stream.addfile(link)
            unpack_verified(archive, root / "safe")
            self.assertFalse((root / "safe/source/link").exists())

    def test_ipc_rejects_invalid_and_late_frames(self):
        reader = Reader("/absent-private-models", "en")
        session = str(uuid.uuid4())
        with contextlib.redirect_stdout(io.StringIO()) as output:
            reader.begin({"session": session, "ts_ms": 0})
            reader.begin({"session": session})
            frame = {"session": session, "ts_ms": 0, "jpeg": base64.b64encode(b"jpeg fixture").decode()}
            reader.frame(frame)
            reader.frame(frame)  # repeated timestamp
            reader.frame({**frame, "ts_ms": 30001})
            self.assertEqual(len(reader.capture.frames), 1)
            reader.finish({"session": session})
            self.assertIsNone(reader.capture)
            reader.frame({**frame, "ts_ms": 1})
        for code in ("duplicate_start", "invalid_timestamp", "too_few_frames", "no_session"):
            self.assertIn(code, output.getvalue())


if __name__ == "__main__":
    unittest.main()
