import tempfile
import unittest
import zipfile
import subprocess
import json
from unittest.mock import patch
from pathlib import Path
from package_desktop import package, windows_bundle
from build_windows_installer import build, product_version

class PackagingTests(unittest.TestCase):
    def test_invalid_payload_version_is_rejected(self):
        for version in ['', '0.1', '0.1.30-beta+31', '0.1.30;bad']:
            with self.subTest(version=version), patch('build_windows_installer.subprocess.run') as run:
                run.return_value.stdout = version
                with self.assertRaisesRegex(ValueError, '载荷版本'):
                    product_version(Path('tingyu.exe'))

    def test_installer_version_follows_payload_instead_of_old_release(self):
        for version in ['0.1.30+31', '0.2.0+42']:
            with self.subTest(version=version), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                bundle, output = root / '载荷 空格', root / '安装包'
                for name in ['tingyu.exe', 'flutter_windows.dll', 'libmpv-2.dll', 'sqlite3.dll',
                             'data/app.so', 'data/icudtl.dat', 'LICENSE.txt', 'msvcp140.dll', 'vcruntime140.dll']:
                    item = bundle / name
                    item.parent.mkdir(parents=True, exist_ok=True)
                    item.write_bytes(b'fixture')
                commands = []
                def run(command, **kwargs):
                    commands.append(command)
                    if command[0] == 'pwsh':
                        return subprocess.CompletedProcess(command, 0, stdout=version + '\n')
                    release = next((c.split('=', 1)[1] for c in command if c.startswith('/DAppVersion=')), '0.1.28')
                    (output / f'tingyu-{release}-windows-x64-setup.exe').write_bytes(b'installer')
                    return subprocess.CompletedProcess(command, 0)
                with patch('build_windows_installer.subprocess.run', side_effect=run):
                    build(bundle, output, root / 'ISCC.exe')
                manifest = json.loads((output / 'installer-manifest.json').read_text(encoding='utf-8'))
                release = version.split('+')[0]
                self.assertEqual(manifest['installer'], f'tingyu-{release}-windows-x64-setup.exe')
                self.assertEqual(manifest['productVersion'], version)
                self.assertIn(f'/DAppVersion={release}', commands[-1])
                usage = (output / '使用说明.txt').read_text(encoding='utf-8')
                self.assertIn(release, usage)
                self.assertNotIn('0.1.28', usage)

    def test_windows_archive_contains_runtime_and_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            release=root/'build/windows/x64/runner/Release'
            for name in ['tingyu.exe','flutter_windows.dll','libmpv-2.dll','sqlite3.dll','data/app.so','data/icudtl.dat','data/flutter_assets/AssetManifest.bin']:
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

    def test_windows_requires_database_and_aot_runtime(self):
        for missing in ['sqlite3.dll', 'data/app.so']:
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                release = root / 'build/windows/x64/runner/Release'
                for name in ['tingyu.exe', 'flutter_windows.dll', 'libmpv-2.dll', 'sqlite3.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin']:
                    if name != missing:
                        item = release / name
                        item.parent.mkdir(parents=True, exist_ok=True)
                        item.write_bytes(b'fixture')
                with self.assertRaisesRegex(FileNotFoundError, missing):
                    windows_bundle(root)

if __name__=='__main__':unittest.main()
