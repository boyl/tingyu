"""Verify the real release's explicit external browser handoff on the isolated AVD."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--device', required=True)
p.add_argument('--apk', required=True, type=Path)
args = p.parse_args()
adb = str(root.parent / '.toolchains/android-sdk/platform-tools/adb')
def run(*items):
    return subprocess.check_output([adb, '-s', args.device, *items], timeout=25)
def shell(*items):
    return run('shell', *items).decode()
assert run('emu', 'avd', 'name').decode().splitlines()[0] == 'tingyu-regression'
for package in ['tv.danmaku.bili', 'com.bilibili.app.in']:
    check = subprocess.run([adb, '-s', args.device, 'shell', 'pm', 'path', package], capture_output=True, text=True)
    assert not check.stdout.strip(), 'This scenario requires no real Bilibili client installed'
out = root / 'artifacts/acceptance/external'
out.mkdir(parents=True, exist_ok=True)
def nodes():
    shell('uiautomator', 'dump', '/sdcard/tingyu-external.xml')
    return list(ET.fromstring(run('exec-out', 'cat', '/sdcard/tingyu-external.xml')).iter('node'))
def click(node):
    x, y, right, bottom = map(int, re.findall(r'\d+', node.attrib['bounds']))
    shell('input', 'tap', str((x + right)//2), str((y + bottom)//2))
    time.sleep(.8)
results = {}
try:
    run('install', '-r', str(args.apk.resolve()))
    shell('am', 'force-stop', 'app.tingyu.tingyu')
    shell('am', 'start', '-W', '-n', 'app.tingyu.tingyu/.MainActivity')
    time.sleep(1.5)
    candidates = [n for n in nodes() if n.get('content-desc', '').split('\n')[0] == '搜索' or n.get('text', '') == '搜索']
    assert candidates, 'Search navigation missing'
    click(max(candidates, key=lambda n: int(re.findall(r'\d+', n.attrib['bounds'])[1])))
    resolution = shell('cmd', 'package', 'resolve-activity', '--brief', '-a', 'android.intent.action.VIEW', '-d', 'https://www.bilibili.com/')
    component = resolution.strip().splitlines()[-1]
    assert '/' in component, resolution
    browser_package = component.split('/')[0]
    assert browser_package not in ['android', 'app.tingyu.tingyu'], resolution
    # Chrome's first-run screen keeps the VIEW data URI out of dumpsys text.
    subprocess.run([adb, '-s', args.device, 'shell',
                    'echo "chrome --disable-fre --no-first-run --no-default-browser-check" > /data/local/tmp/chrome-command-line'],
                   check=False, capture_output=True)
    shell('am', 'force-stop', 'com.android.chrome')
    entry = next(n for n in nodes() if '前往哔哩哔哩' in n.get('content-desc', ''))
    (out / 'search-entry.png').write_bytes(run('exec-out', 'screencap', '-p'))
    run('logcat', '-c')
    click(entry)
    time.sleep(1)
    state = shell('dumpsys', 'activity', 'activities')
    (out / 'browser-activities.txt').write_text(state)
    start_log = run('logcat', '-d', '-s', 'ActivityTaskManager:I').decode(errors='replace')
    (out / 'browser-start.txt').write_text(start_log)
    resumed = '\n'.join(line for line in state.splitlines() if 'topResumedActivity=' in line or 'mResumedActivity:' in line)
    assert resumed and browser_package + '/' in resumed, resumed
    view = f'act=android.intent.action.VIEW dat=https://www.bilibili.com'
    assert 'https://www.bilibili.com' in state or (view in start_log and browser_package in start_log), 'Canonical external URL missing from browser intent'
    (out / 'browser.png').write_bytes(run('exec-out', 'screencap', '-p'))
    results['missing-client-external-browser'] = {'status': 'PASS', 'browserPackage': browser_package, 'resumed': resumed.strip()}
finally:
    shell('am', 'start', '-W', '-n', 'app.tingyu.tingyu/.MainActivity')
    report = {'apkSha256': hashlib.sha256(args.apk.read_bytes()).hexdigest(), 'checks': results,
              'officialClientInstalled': 'NOT RUN - requires a device with the official client; priority/failure paths covered with injected host launchers'}
    (out / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))
