"""Package a complete native desktop bundle; never ship a lone Windows EXE."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import zipfile


def windows_bundle(root: Path) -> Path:
    bundle = root / 'build/windows/x64/runner/Release'
    for relative in ['tingyu.exe', 'flutter_windows.dll', 'libmpv-2.dll', 'sqlite3.dll', 'data/app.so', 'data/icudtl.dat']:
        if not (bundle / relative).is_file():
            raise FileNotFoundError(f'Missing Windows runtime: {relative}')
    if not (bundle / 'data/flutter_assets').is_dir():
        raise FileNotFoundError('Missing Flutter assets directory')
    return bundle


def package(root: Path, target: str) -> Path:
    destination = root / 'artifacts'
    destination.mkdir(exist_ok=True)
    archive = destination / f'tingyu-{target}-release.zip'
    if target == 'windows-x64':
        bundle = windows_bundle(root)
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as output:
            for item in sorted(bundle.rglob('*')):
                if item.is_file():
                    output.write(item, Path('tingyu') / item.relative_to(bundle))
    else:
        apps = list((root / 'build/macos/Build/Products/Release').glob('*.app'))
        if len(apps) != 1 or not (apps[0] / 'Contents/MacOS').is_dir():
            raise FileNotFoundError('Expected one complete macOS .app bundle')
        # ditto preserves framework symlinks, resource forks, and bundle layout.
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(apps[0]), str(archive)], check=True)
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.json').write_text(json.dumps({'file': archive.name, 'bytes': archive.stat().st_size, 'sha256': checksum, 'platform': target, 'runtimeValidation': 'pending on target OS'}, indent=2) + '\n')
    return archive


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('target', choices=['windows-x64', 'macos'])
    args = parser.parse_args()
    print(package(Path(__file__).resolve().parents[1], args.target))
