import tempfile
import unittest
import zipfile
from pathlib import Path
from package_desktop import package, windows_bundle

class PackagingTests(unittest.TestCase):
    def test_windows_archive_contains_runtime_and_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            release=root/'build/windows/x64/runner/Release'
            for name in ['tingyu.exe','flutter_windows.dll','libmpv-2.dll','data/icudtl.dat','data/flutter_assets/AssetManifest.bin']:
                item=release/name;item.parent.mkdir(parents=True,exist_ok=True);item.write_bytes(b'fixture')
            archive=package(root,'windows-x64')
            with zipfile.ZipFile(archive) as contents:
                self.assertIn('tingyu/libmpv-2.dll',contents.namelist())
                self.assertIn('tingyu/data/flutter_assets/AssetManifest.bin',contents.namelist())
                self.assertIsNone(contents.testzip())
            self.assertTrue(archive.with_suffix('.json').exists())
    def test_missing_audio_runtime_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            release=root/'build/windows/x64/runner/Release';release.mkdir(parents=True)
            (release/'tingyu.exe').write_bytes(b'fixture')
            (release/'flutter_windows.dll').write_bytes(b'fixture')
            with self.assertRaisesRegex(FileNotFoundError,'libmpv-2.dll'):
                windows_bundle(root)
    def test_mac_requires_an_app_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(FileNotFoundError):
                package(Path(directory),'macos')

if __name__=='__main__':unittest.main()
