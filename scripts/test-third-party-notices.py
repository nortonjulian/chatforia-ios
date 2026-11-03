import hashlib
import importlib.util
import json
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('notices', pathlib.Path(__file__).with_name('generate-third-party-notices.py'))
notices = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notices)

class NoticesCheckTests(unittest.TestCase):
    def test_detects_dependency_and_notice_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            original = notices.LOCK, notices.OUTPUT, notices.MANIFEST
            try:
                notices.LOCK, notices.OUTPUT, notices.MANIFEST = root/'lock', root/'notices', root/'manifest'
                notices.LOCK.write_bytes(b'pinned dependencies')
                notices.OUTPUT.write_bytes(b'preserved license')
                notices.MANIFEST.write_text(json.dumps({
                    'lockSha256': hashlib.sha256(b'pinned dependencies').hexdigest(),
                    'noticesSha256': hashlib.sha256(b'preserved license').hexdigest(),
                }))
                notices.check()
                notices.LOCK.write_bytes(b'changed dependencies')
                with self.assertRaisesRegex(SystemExit, 'Package.resolved changed'):
                    notices.check()
                notices.LOCK.write_bytes(b'pinned dependencies')
                notices.OUTPUT.write_bytes(b'changed license')
                with self.assertRaisesRegex(SystemExit, 'Bundled notices differ'):
                    notices.check()
            finally:
                notices.LOCK, notices.OUTPUT, notices.MANIFEST = original

if __name__ == '__main__':
    unittest.main()
