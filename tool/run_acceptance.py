"""Run reproducible local gates; never equate unexecuted device checks with PASS."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--device', help='Run native Android navigation integration test on this device')
parser.add_argument('--live', action='store_true', help='Also run anonymous public BV playback/download probe; requires --device')
args = parser.parse_args()
if args.live and not args.device:
    parser.error('--live requires an isolated Android device')
if args.device:
    adb = ROOT.parent / '.toolchains/android-sdk/platform-tools/adb'
    adb_command = str(adb) if adb.exists() else 'adb'
    identity = subprocess.check_output([adb_command, '-s', args.device, 'emu', 'avd', 'name'], text=True, timeout=10)
    if identity.splitlines()[0].strip() != 'tingyu-regression':
        parser.error('Native acceptance requires the isolated tingyu-regression AVD; never use the human acceptance device.')
output = ROOT / 'artifacts' / 'acceptance'
output.mkdir(parents=True, exist_ok=True)
flutter = ['flutter'] if os.name == 'nt' else ['sh', 'tool/flutterw.sh']
commands = [('analyze', flutter + ['analyze']), ('offline-tests', flutter + ['test', '--reporter', 'expanded']),
            ('desktop-packaging-tests', [sys.executable, 'tool/test_package_desktop.py'])]
if args.device:
    for name, target in [('android-navigation', 'navigation_test.dart'), ('android-interactions', 'interaction_test.dart')]:
        commands.append((name, flutter + ['drive', '--driver=test_driver/integration_driver.dart', f'--target=integration_test/{target}', '-d', args.device]))
    if args.live:
        commands.append(('android-live-playback', flutter + ['drive', '--driver=test_driver/integration_driver.dart', '--target=integration_test/live_playback_test.dart', '-d', args.device]))
def source_fingerprint():
    fingerprint = hashlib.sha256()
    for folder in ['lib', 'android/app/src', 'test', 'integration_test']:
        for file in sorted((ROOT / folder).rglob('*')):
            if file.is_file():
                fingerprint.update(str(file.relative_to(ROOT)).encode())
                fingerprint.update(file.read_bytes())
    return fingerprint.hexdigest()

fingerprint_before = source_fingerprint()
results = {}
for name, command in commands:
    print(f'Running {name}...', flush=True)
    with (output / f'{name}.log').open('w') as log:
        process = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    results[name] = {'status': 'PASS' if process.returncode == 0 else 'FAIL', 'exitCode': process.returncode, 'log': f'{name}.log'}
    if process.returncode:
        print((output / f'{name}.log').read_text()[-6000:])
        break
fingerprint_after = source_fingerprint()
results['source-stability'] = {'status': 'PASS' if fingerprint_before == fingerprint_after else 'FAIL'}
report = {'checkedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'sourceSha256': fingerprint_after,
          'checks': results, 'notExecutedByThisCommand': ([] if args.device and results.get('android-navigation', {}).get('status') == 'PASS' else ['G02 Android tab navigation']) + ['G03 Release full screen lifecycle', 'G04 native desktop / large-font / screen-reader review', 'G05 real account import and keyword search',
          'G06 actual storage exhaustion and real account expiry', 'G07 physical Android device', 'G08 matching release APK', 'D01 native desktops'],
          'humanHandoffReady': False}
(output / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False, indent=2))
sys.exit(1 if any(r['status'] == 'FAIL' for r in results.values()) else 0)
