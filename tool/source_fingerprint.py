"""Stable source fingerprint shared by acceptance and APK verification.

Generated plugin registration changes between development and release modes;
ignore it while hashing application sources, tests and locked dependencies.
"""
import hashlib
from pathlib import Path


def source_fingerprint(root: Path) -> str:
    files = [root / name for name in ('pubspec.yaml', 'pubspec.lock', 'tool/source_fingerprint.py')]
    for folder in ('lib', 'android/app/src', 'test', 'integration_test'):
        files.extend(file for file in (root / folder).rglob('*')
                     if file.is_file() and file.name != 'GeneratedPluginRegistrant.java')
    digest = hashlib.sha256()
    for file in sorted(files):
        digest.update(str(file.relative_to(root)).encode())
        digest.update(file.read_bytes())
    return digest.hexdigest()
