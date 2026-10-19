#!/usr/bin/env python3
"""Export the existing Tingyu painter and inventory Material fallbacks. No app changes."""
import argparse, hashlib, json, re, shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'resources/icons'
# SVG equivalents of lib/ui/icons.dart, kept reviewable beside its source fingerprint.
D={
'endPause':'M2 12h9 M7 8l4 4-4 4',
'back':'M15 5 8 12 15 19','right':'M9 5 16 12 9 19',
'moveUp':'M12 4v17 M5 11l7-7 7 7','toTop':'M4 3h16 M12 7v14 M7 12l5-5 5 5',
'moveDown':'M12 3v17 M5 13l7 7 7-7','down':'M5 9l7 7 7-7',
'search':'M15.5 15.5 21 21','minus':'M5 12h14','plus':'M12 5v14 M5 12h14',
'minusCircle':'M7 12h10',
'eraser':'M3 13 13 3 21 11 11 21 7 21Z M9 7l8 8 M11 21h11',
 'trash':'M3 6h18 M8 6V3h8v3 M5 6l1 14Q6 21 8 21H16Q18 21 18 20L19 6 M10 10v7 M14 10v7',
'sort':'M3 6h14 M3 12h10 M3 18h6 M19 11v9 M16 17l3 3 3-3',
'download':'M12 3v12 M7 10l5 5 5-5 M4 15v4Q4 21 6 21H18Q20 21 20 19V15',
'check':'M7 12l3 3 7-7','done':'M7 12l3 3 7-7',
'next':'M5 5 15 12 5 19Z M19 5v14','previous':'M19 5 9 12 19 19Z M5 5v14',
'playNext':'M3 5h17 M3 10h9 M3 15h7 M16 12 22 16 16 20Z',
'queue':'M3 5h16 M3 10h12 M3 15h9 M20 10v9 M20 10l3-1',
'music':'M10 5v12 M10 5l10-2v12 M10 8l10-2',
'heart':'M12 20C9 17 3 13 3 8C3 3 9 2 12 7C15 2 21 3 21 8C21 13 15 17 12 20Z',
'heartFilled':'M12 20C9 17 3 13 3 8C3 3 9 2 12 7C15 2 21 3 21 8C21 13 15 17 12 20Z',
'locate':'M12 2v2 M12 20v2 M2 12h2 M20 12h2',
'folder':'M3 20V5h6l2 3h10v12Z','info':'M12 10v7',
'external':'M7 17 19 5 M11 5h8v8',
'select':'M3 5l2 2 3-4 M12 5h9 M3 12l2 2 3-4 M12 12h9 M3 19l2 2 3-4 M12 19h9',
'wave':'M4 9.5v5 M8 6.5v11 M12 3v18 M16 7.5v9 M20 10v4',
'lyrics':'M7 18v4l5-4 M7 9h10 M7 13h7',
'queuePlus':'M3 5h15 M3 10h11 M3 15h6 M18 13v8 M14 17h8',
'folderPlus':'M3 19V5Q3 3 5 3H9L12 7H19Q21 7 21 9V19Q21 21 19 21H5Q3 21 3 19 M8 14h8 M12 10v8',
'trackPlus':'M7 17V5l9-2 M7 8l9-2 M18 12v10 M13 17h10',
'playlist':'M3 8h18 M8 12h9 M8 17h9',
'refresh':'M19.8405326 13.5893546A8 8 0 1 1 17.077543 5.817884 M15 3l5 2V.5',
}
def circle(x,y,r):return f'<circle cx="{x}" cy="{y}" r="{r}"/>'
def svg(name):
 a=''
 if name in D:a='<path d="'+D[name]+'"/>'
 if name in ['done','minusCircle','circle','info']:a=circle(12,12,9)+a
 if name=='search':a=circle(10.5,10.5,6.5)+a
 if name=='locate':a=circle(12,12,6)+circle(12,12,1.5)+a
 if name=='info':a+='<circle cx="12" cy="7" r="1" fill="currentColor" stroke="none"/>'
 if name=='queue':a+='<ellipse cx="17.5" cy="19.5" rx="2.5" ry="1.5"/>'
 if name=='music':a+='<ellipse cx="7" cy="18" rx="3" ry="2"/><ellipse cx="17" cy="16" rx="3" ry="2"/>'
 if name=='trackPlus':a+='<ellipse cx="4.5" cy="18" rx="2.5" ry="2"/>'
 if name=='playlist':a='<rect x="3" y="3" width="18" height="18" rx="3"/>'+a+circle(6,12,.5)+circle(6,17,.5)
 if name=='lyrics':a='<rect x="3" y="4" width="18" height="14" rx="3"/>'+a
 if name=='endPause':a+=''.join(f'<rect x="{x}" y="5" width="2.5" height="14" rx="1" fill="currentColor" stroke="none"/>' for x in [15,20])
 if name=='play':a='<path d="M8 5 19 12 8 19Z" fill="currentColor" stroke="none"/>'
 if name=='pause':a=''.join(f'<rect x="{x}" y="5" width="2.5" height="14" rx="1" fill="currentColor" stroke="none"/>' for x in [8,15])
 if name=='more':a=''.join(f'<circle cx="{x}" cy="12" r="1.2" fill="currentColor" stroke="none"/>' for x in [5,12,19])
 if name=='grip':a=''.join(f'<circle cx="{x}" cy="{y}" r="1" fill="currentColor" stroke="none"/>' for x in [9,15] for y in [6,12,18])
 if name=='heartFilled':a='<path d="'+D[name]+'" fill="currentColor" stroke="none"/>'
 assert a,name
 return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'+a+'</svg>\n'
def sha(b):return hashlib.sha256(b).hexdigest()
def inventory():
 runtime=ROOT/'lib/ui/icons.dart';source=runtime.read_text();aliases=dict(re.findall(r'Icons\.(\w+): \'(\w+)\'',source))
 names=sorted(set(re.findall(r"case '(\w+)':",source)))
 usages={}
 for f in sorted((ROOT/'lib').rglob('*.dart')):
  for i,line in enumerate(f.read_text().splitlines(),1):
   for name in re.findall(r'\bIcons\.(\w+)',line):usages.setdefault(name,[]).append(f'{f.relative_to(ROOT)}:{i}')
 # Register existing Material reuse for new designs, even if not yet in app call sites.
 for name in ['speed','schedule','visibility','visibility_off','tune','person_outline','storage','blur_on','logout','shield_outlined','repeat','repeat_one','shuffle','looks_one_outlined','pause_circle_outline','close']:
  usages.setdefault(name,[])
 sdk=ROOT.parent/'.toolchains/flutter';mat=sdk/'packages/flutter/lib/src/material/icons.dart'
 text=mat.read_text();glyphs={name:{'codepoint':int(cp,16),'matchTextDirection':bool(direction)} for name,cp,direction in re.findall(r'static const IconData (\w+) = IconData\(0x([0-9a-f]+), fontFamily: \'MaterialIcons\'(, matchTextDirection: true)?\);',text)}
 entries=[]
 for name in names:
  entries.append({'id':name,'provider':'tingyu-painter','status':'existing','asset':f'svg/{name}.svg','runtimeSource':'lib/ui/icons.dart','aliases':[k for k,v in aliases.items() if v==name]})
 if 'endPause' not in names: entries.append({'id':'endPause','provider':'tingyu-design','status':'pending-confirmation','asset':'candidates/endPause.svg','semantics':'当前曲目播放到结尾后暂停；不是正在暂停的状态','reuseDecision':'单独暂停双柱缺少曲尾语义，方框1缺少暂停语义；以曲尾箭头与原暂停双柱组合','runtimeSource':None})
 for name,uses in sorted(usages.items()):
  if name in aliases and name != 'close':continue
  assert name in glyphs,name
  entries.append({'id':'material/'+name,'provider':'Flutter MaterialIcons','status':'existing-app-use' if uses else 'design-reuse','asset':'material/MaterialIcons-Regular.otf',**glyphs[name],'uses':uses})
 design_uses={}
 for f in sorted((ROOT/'design-review').rglob('*.html')):
  for icon_id in set(re.findall(r'data-icon-id="([^"<>]+)"',f.read_text())):
   design_uses.setdefault(icon_id,[]).append(str(f.relative_to(ROOT)))
 valid={e['id'] for e in entries}
 assert not (set(design_uses)-valid), f'Unregistered design icons: {set(design_uses)-valid}'
 for e in entries:e['designUses']=design_uses.get(e['id'],[])
 return source,entries,glyphs

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true');args=ap.parse_args()
 source,entries,glyphs=inventory(); assets={e['asset']:svg(e['id']) for e in entries if e['provider']=='tingyu-painter'}
 if any(e['asset']=='candidates/endPause.svg' for e in entries): assets['candidates/endPause.svg']='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12h9 M7 8l4 4-4 4"/><rect x="15" y="5" width="2.5" height="14" rx="1" fill="currentColor" stroke="none"/><rect x="20" y="5" width="2.5" height="14" rx="1" fill="currentColor" stroke="none"/></svg>\n'
 matroot=ROOT.parent/'.toolchains/flutter/bin/cache/artifacts/material_fonts'
 font=(matroot/'MaterialIcons-Regular.otf').read_bytes();license=(matroot/'MaterialIcons_LICENSE.txt').read_bytes()
 registry={'schema':1,'geometrySource':'lib/ui/icons.dart','runtimeSha256':sha(source.encode()),'fontSha256':sha(font),'note':'SVG review exports mirror runtime painter; app still reads TingyuIcon. Font glyphs are existing Flutter resources, not newly drawn icons.','tokens':{'grid':24,'stroke':1.7,'download.completed':'tokens.accent','download.idle':'tokens.text','download.failed':'tokens.danger','player.glyph':'tokens.onPlayerButton','player.button':'tokens.playerButton'},'entries':entries,'assetSha256':{p:sha(s.encode()) for p,s in assets.items()}}
 serialized=json.dumps(registry,ensure_ascii=False,indent=2)+'\n'
 if args.check:
  assert (OUT/'registry.json').read_text()==serialized,'Catalog drift: review source/usage and rerun export'
  for p,s in assets.items():assert (OUT/p).read_text()==s,p
  assert (OUT/'material/MaterialIcons-Regular.otf').read_bytes()==font
  assert (OUT/'material/LICENSE.txt').read_bytes()==license
  print(f'PASS: {len(assets)} SVG exports, {len(entries)-len(assets)} Material entries; source, use inventory, geometry and font hashes match');return
 for p,s in assets.items():(OUT/p).parent.mkdir(parents=True,exist_ok=True);(OUT/p).write_text(s)
 (OUT/'material').mkdir(exist_ok=True);(OUT/'material/MaterialIcons-Regular.otf').write_bytes(font);(OUT/'material/LICENSE.txt').write_bytes(license)
 (OUT/'registry.json').write_text(serialized)
 cards=[]
 for e in entries:
  drawing=(OUT/e['asset']).read_text() if e['asset'].endswith('.svg') else '<span class="material">&#'+str(e['codepoint'])+';</span>'
  cards.append('<article>'+drawing+'<b>'+e['id']+'</b><small>'+e['status']+'</small></article>')
 (OUT/'index.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>听屿图标资源库</title><style>@font-face{font-family:MaterialIcons;src:url(material/MaterialIcons-Regular.otf)}body{font-family:-apple-system,sans-serif;background:#faf8fa;color:#19191b;padding:40px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(145px,1fr));gap:12px}article{background:white;padding:20px;display:flex;flex-direction:column;gap:12px;border:1px solid #e7e7eb;border-radius:8px}svg{width:28px;height:28px}.material{font-family:MaterialIcons;font-size:28px;line-height:1}b{font-size:12px;word-break:break-all}small,p{font-size:11px;color:#68686e}</style><h1>听屿图标资源库</h1><p>既有图形优先 · 状态颜色由主题决定 · 本页默认中性色展示，不代表业务状态颜色</p><div class="grid">'+''.join(cards)+'</div></html>')
 print(f'Exported {len(assets)} SVGs and {len(entries)-len(assets)} Material registrations')
if __name__=='__main__':main()
