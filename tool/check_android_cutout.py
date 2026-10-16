from pathlib import Path
import argparse,hashlib,json,subprocess,time,re
from PIL import Image
parser=argparse.ArgumentParser(description='Isolated release cutout regression; requires Pillow')
parser.add_argument('--device',required=True)
parser.add_argument('--apk',required=True,type=Path)
args=parser.parse_args()
root=Path(__file__).resolve().parents[1];adb=str(root.parent/'.toolchains/android-sdk/platform-tools/adb');device=args.device;out=root/'artifacts/acceptance/cutout';out.mkdir(exist_ok=True)
def run(*args):return subprocess.check_output([adb,'-s',device,*args],timeout=30)
def shell(*args):return run('shell',*args).decode()
assert run('emu','avd','name').decode().splitlines()[0]=='tingyu-regression'
old_auto=shell('settings','get','system','accelerometer_rotation').strip();old_rotation=shell('settings','get','system','user_rotation').strip()
overlay='com.android.internal.display.cutout.emulation.hole';initial=shell('cmd','overlay','list');was_enabled=f'[x] {overlay}' in initial
results={}
try:
 run('install','-r',str(args.apk.resolve()))
 shell('cmd','overlay','enable','--user','0',overlay)
 shell('settings','put','system','accelerometer_rotation','0')
 for rotation,name in [('0','portrait'),('1','landscape')]:
  shell('settings','put','system','user_rotation',rotation);time.sleep(1)
  shell('am','force-stop','app.tingyu.tingyu');shell('am','start','-W','-n','app.tingyu.tingyu/.MainActivity');time.sleep(2)
  display=shell('dumpsys','window','displays');windows=shell('dumpsys','window','windows')
  (out/f'{name}-display.txt').write_text(display);(out/f'{name}-windows.txt').write_text(windows)
  image=out/f'{name}.png';image.write_bytes(run('exec-out','screencap','-p'))
  im=Image.open(image).convert('RGB');width,height=im.size
  points=[(100,12),(width-100,12)] if rotation=='0' else [(12,100),(12,height-100)]
  pixels=[im.getpixel(point) for point in points]
  assert all(min(rgb)>200 for rgb in pixels),(name,pixels)
  blocks=re.findall(r'Window #\d+ Window\{[^\n]*app\.tingyu\.tingyu[^\n]*\}:[\s\S]*?(?=\n  Window #|\Z)',windows)
  assert any('layoutInDisplayCutoutMode=always' in block for block in blocks), 'Explicit app cutout policy absent'
  assert 'DisplayCutout' in display
  results[name]={'status':'PASS','pixels':pixels,'imageSize':[width,height],'explicitCutoutPolicy':'always'}
finally:
 if not was_enabled:shell('cmd','overlay','disable','--user','0',overlay)
 for key,value in [('accelerometer_rotation',old_auto),('user_rotation',old_rotation)]:
  shell('settings','delete','system',key) if value=='null' else shell('settings','put','system',key,value)
 (out/'report.json').write_text(json.dumps({'apkSha256':hashlib.sha256(args.apk.read_bytes()).hexdigest(),'device':device,'overlay':overlay,'checks':results,'magic5PhysicalDevice':'NOT RUN'},indent=2)+'\n')
 print(json.dumps(results,indent=2))
