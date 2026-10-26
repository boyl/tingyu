"""Stable source fingerprint shared by acceptance and APK verification.

Generated plugin registration changes between development and release modes;
ignore it while hashing application sources, tests and locked dependencies.
"""
import hashlib
from pathlib import Path


def source_fingerprint(root: Path) -> str:
    files = [root / name for name in ('pubspec.yaml', 'pubspec.lock', 'tool/source_fingerprint.py', 'tool/run_acceptance.py', 'tool/run_android_export_test.py', 'tool/flutterw.ps1', 'tool/windows.ps1', 'tool/package_desktop.py', 'tool/test_package_desktop.py', 'tool/prepare_windows_plugins.ps1', 'tool/generate_app_icons.py', 'tool/icon_catalog.py', 'windows/CMakeLists.txt', 'windows/flutter/CMakeLists.txt')]
    for folder in ('lib', 'assets', 'android/app/src', 'windows/runner', 'test', 'integration_test', 'test_driver'):
        files.extend(file for file in (root / folder).rglob('*')
                     if file.is_file() and file.name != 'GeneratedPluginRegistrant.java')
    digest = hashlib.sha256()
    for file in sorted(files):
        digest.update(file.relative_to(root).as_posix().encode())
        digest.update(file.read_bytes())
    return digest.hexdigest()
