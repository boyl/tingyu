"""Verify and archive split APKs only against a successful source-stable gate report."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile
from source_fingerprint import source_fingerprint

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT.parent / '.toolchains'
report = json.loads((ROOT / 'artifacts/acceptance/report.json').read_text())
assert report['checks'] and all(x['status'] == 'PASS' for x in report['checks'].values()), 'Acceptance gates must pass first'
assert source_fingerprint(ROOT) == report['sourceSha256'], 'Source changed after acceptance; rerun gates before delivery'
version, number = re.search(r'^version: ([^+]+)\+(\d+)', (ROOT / 'pubspec.yaml').read_text(), re.M).groups()
build_tools = TOOLS / 'android-sdk/build-tools/36.0.0'
env = dict(os.environ)
env['JAVA_HOME'] = str(next(TOOLS.glob('jdk-*/Contents/Home')))
expected_cert = '27279eafd4c4ffc5c68b69af7a3adbc4889031b1a7896ac30e18e86b7950c32c'
items = []
for abi, offset in [('armeabi-v7a', 1000), ('arm64-v8a', 2000), ('x86_64', 4000)]:
    source = ROOT / f'build/app/outputs/flutter-apk/app-{abi}-release.apk'
    with zipfile.ZipFile(source) as apk:
        assert apk.testzip() is None, 'ZIP integrity failed'
        actual = {name.split('/')[1] for name in apk.namelist() if name.startswith('lib/') and name.endswith('.so')}
        assert actual == {abi}, actual
    badging = subprocess.check_output([str(build_tools / 'aapt'), 'dump', 'badging', str(source)], text=True, env=env)
    assert "name='app.tingyu.tingyu'" in badging
    assert f"versionName='{version}'" in badging
    code = int(re.search(r"versionCode='(\d+)'", badging)[1])
    assert code == offset + int(number), code
    signature = subprocess.check_output([str(build_tools / 'apksigner'), 'verify', '--print-certs', str(source)], text=True, env=env)
    assert expected_cert in signature, 'Signature differs; cannot upgrade existing human acceptance app'
    destination = ROOT / f'artifacts/tingyu-{version}-android-{abi}-release.apk'
    shutil.copy2(source, destination)
    items.append({'abi': abi, 'path': str(destination.relative_to(ROOT)), 'bytes': destination.stat().st_size,
                  'sha256': hashlib.sha256(destination.read_bytes()).hexdigest(), 'zipIntegrity': 'PASS',
                  'exactAbi': 'PASS', 'versionCode': str(code)})
manifest = {'version': f'{version}+{number}', 'sourceSha256': report['sourceSha256'],
            'signing': 'development/debug key', 'signerCertificateSha256': expected_cert,
            'sameDevelopmentSigner': True, 'validation': 'ZIP, exact ABI, package, version and signatures PASS',
            'apks': items, 'runtimeEvidence': 'artifacts/acceptance/release/fullscreen.json; artifacts/acceptance/cutout/report.json',
            'limitations': ['physical Android lockscreen/Bluetooth/calls/background scenarios pending', 'emulator audible issue deferred by user', 'native desktops pending']}
(ROOT / 'tool/release-apks.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(manifest, ensure_ascii=False, indent=2))
