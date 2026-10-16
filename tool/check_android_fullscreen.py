"""Check actual system bars on the project's local Android emulator."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--device', required=True)
parser.add_argument('--apk', type=Path, required=True)
args = parser.parse_args()
if not args.device.startswith('emulator-'):
    parser.error('This automated lifecycle check is limited to a local emulator.')
adb = shutil.which('adb') or str(ROOT.parent / '.toolchains/android-sdk/platform-tools/adb')
identity = subprocess.check_output([adb, '-s', args.device, 'emu', 'avd', 'name'], text=True, timeout=10)
if identity.splitlines()[0].strip() != 'tingyu-regression':
    parser.error('Use the isolated tingyu-regression AVD; do not interrupt the human acceptance device.')
out = ROOT / 'artifacts/acceptance/release'
out.mkdir(parents=True, exist_ok=True)
results = {}

def run(*command):
    return subprocess.check_output([adb, '-s', args.device, *command], timeout=20)

def shell(*command):
    return run('shell', *command).decode()

def start():
    shell('am', 'start', '-W', '-n', 'app.tingyu.tingyu/.MainActivity')
    time.sleep(1.5)

def capture(name, hidden=True):
    display = shell('dumpsys', 'window', 'displays')
    (out / f'{name}-display.txt').write_text(display)
    (out / f'{name}.png').write_bytes(run('exec-out', 'screencap', '-p'))
    bars = {kind: re.findall(r'InsetsSource id=\w+ type=' + kind + r' .*?visible=(true|false)', display)
            for kind in ['statusBars', 'navigationBars']}
    visible = 'false' if hidden else 'true'
    passed = all(values and set(values) == {visible} for values in bars.values())
    passed = passed and 'app.tingyu.tingyu/app.tingyu.tingyu.MainActivity' in display
    results[name] = {'status': 'PASS' if passed else 'FAIL', 'bars': bars}
    assert passed, f'{name}: system bar state did not match expectation'

def nodes():
    shell('uiautomator', 'dump', '/sdcard/tingyu-acceptance.xml')
    return list(ET.fromstring(run('exec-out', 'cat', '/sdcard/tingyu-acceptance.xml')).iter('node'))

def tap(node):
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.attrib['bounds']))
    shell('input', 'tap', str((x1 + x2)//2), str((y1 + y2)//2))
    time.sleep(.5)

try:
    run('install', '-r', str(args.apk.resolve()))
    shell('am', 'force-stop', 'app.tingyu.tingyu')
    start()
    capture('cold-start')
    search = next(n for n in nodes() if n.get('class') == 'android.widget.Button' and n.get('content-desc', '').split('\n')[0] == '搜索')
    tap(search)
    field = next(n for n in nodes() if n.get('class') == 'android.widget.EditText')
    tap(field)
    assert 'mInputShown=true' in shell('dumpsys', 'input_method'), 'Real Android keyboard did not open'
    shell('input', 'keyevent', 'KEYCODE_BACK')
    time.sleep(1.5)
    capture('keyboard-dismiss')
    shell('input', 'keyevent', 'KEYCODE_HOME')
    time.sleep(.5)
    start()
    capture('resume')
    shell('input', 'swipe', '200', '1', '200', '300', '300')
    capture('transient-bars', hidden=False)
    time.sleep(4)
    capture('transient-dismiss')
finally:
    report = {'apkSha256': hashlib.sha256(args.apk.read_bytes()).hexdigest(), 'device': args.device, 'checks': results}
    (out / 'fullscreen.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
