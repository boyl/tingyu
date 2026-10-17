"""Real SAF save/cancel on the regression AVD, using observed native view geometry.

Avoid UIAutomator: attaching its accessibility service changes Flutter's semantics
handle count during a test and produces a framework end-of-test leak assertion.
"""
import argparse,queue,re,subprocess,sys,threading,time
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--device',required=True);args=p.parse_args()
adb=root.parent/'.toolchains/android-sdk/platform-tools/adb'
def run(*items):return subprocess.check_output([str(adb),'-s',args.device,*items],timeout=20)
def picker_focused():
 state=run('shell','dumpsys','window').decode()
 return bool(re.search(r'mCurrentFocus=Window\{[^\n}]*documentsui',state))
def save_point():
 state=run('shell','dumpsys','activity','top').decode()
 blocks=state.split('ACTIVITY ')
 for block in reversed(blocks):
  if 'documentsui' not in block.splitlines()[0] or 'View Hierarchy:' not in block:continue
  stack=[]
  for line in block.split('View Hierarchy:',1)[1].splitlines():
   found=re.match(r'^(\s+)\S+\{\S+ ([A-Z.]+) \S+ (-?\d+),(-?\d+)-(-?\d+),(-?\d+)',line)
   if not found:continue
   depth=len(found[1]);x,y,right,bottom=map(int,found.groups()[2:])
   while stack and stack[-1][0]>=depth:stack.pop()
   px,py,visible=(stack[-1][1:]) if stack else (0,0,True)
   visible=visible and found[2].startswith('V')
   absolute=(depth,px+x,py+y,visible);stack.append(absolute)
   if 'android:id/button1' in line and visible and 'E' in found[2] and right>x and bottom>y:
    return absolute[1]+(right-x)//2,absolute[2]+(bottom-y)//2
 return None
assert run('emu','avd','name').decode().splitlines()[0]=='tingyu-regression','Never automate human acceptance devices'
command=['sh','tool/flutterw.sh','drive','--no-pub','--driver=test_driver/integration_driver.dart','--target=integration_test/export_test.dart','-d',args.device]
process=subprocess.Popen(command,cwd=root,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
stages=queue.Queue();errors=[]
def reader():
 for line in process.stdout:
  print(line,end='',flush=True)
  if 'TINGYU_EXPORT_PICKER_READY' in line:stages.put('save')
  if 'TINGYU_EXPORT_CANCEL_READY' in line:stages.put('cancel')
thread=threading.Thread(target=reader,daemon=True);thread.start()
deadline=time.monotonic()+360
while process.poll() is None:
 if time.monotonic()>deadline:errors.append('Export test timeout');process.terminate();break
 try:stage=stages.get(timeout=1)
 except queue.Empty:continue
 try:
  for attempt in range(25):
   if not picker_focused():time.sleep(.4);continue
   screenshot=root/f'artifacts/acceptance/screenshots/export-system-{stage}.png'
   screenshot.parent.mkdir(parents=True,exist_ok=True)
   screenshot.write_bytes(run('exec-out','screencap','-p'))
   if stage=='cancel':
    for _ in range(6):
     run('shell','input','keyevent','4');time.sleep(.4)
     if not picker_focused():break
    else:raise RuntimeError('Document picker did not close on cancel')
    (screenshot.parent/'export-native-returned.png').write_bytes(run('exec-out','screencap','-p'))
    print('SAF cancellation verified',flush=True);break
   point=save_point()
   if point is None:time.sleep(.4);continue
   run('shell','input','tap',str(point[0]),str(point[1]))
   print(f'SAF save dispatched to observed button at {point}',flush=True);break
  else:raise RuntimeError('System document picker did not become actionable')
 except Exception as e:errors.append(str(e));process.terminate();break
code=process.wait(timeout=30);thread.join(timeout=5)
if errors:print(errors,file=sys.stderr)
sys.exit(code if code else (1 if errors else 0))
