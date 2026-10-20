from PIL import Image,ImageDraw,ImageFont
from pathlib import Path
P=Path(__file__).resolve().parent
S=2
im=Image.new('RGB',(1250*S,1040*S),'#f2eef0');d=ImageDraw.Draw(im)
font='/System/Library/Fonts/STHeiti Light.ttc'
ink='#28252c';mut='#726b75';pink='#fb7299';accent='#a93660';line='#eee9ed'
def t(x,y,v,s=14,c=ink):d.text((int(x*S),int(y*S)),v,font=ImageFont.truetype(font,int(s*S)),fill=c)
def rr(box,r,fill,outline=None,w=1):d.rounded_rectangle(tuple(int(v*S) for v in box),r*S,fill=fill,outline=outline,width=w*S)
def ln(pts,c=ink,w=1.7):d.line([(int(a*S),int(b*S)) for a,b in pts],fill=c,width=round(w*S),joint='curve')
def ico(x,y,k,c=ink):
 # Faithful 24-grid geometry from existing resources/icons/svg.
 def l(points):ln([(x+a,y+b) for a,b in points],c)
 if k in ['circle','done']:
  d.ellipse(((x+3)*S,(y+3)*S,(x+21)*S,(y+21)*S),outline=c,width=round(1.7*S))
  if k=='done':l([(7,12),(10,15),(17,8)])
 if k=='download':l([(12,3),(12,15)]);l([(7,10),(12,15),(17,10)]);l([(4,15),(4,19),(6,21),(18,21),(20,19),(20,15)])
 if k=='folderPlus':l([(3,19),(3,5),(5,3),(9,3),(12,7),(19,7),(21,9),(21,19),(19,21),(5,21),(3,19)]);l([(8,14),(16,14)]);l([(12,10),(12,18)])
 if k=='more':
  for a in [5,12,19]:d.ellipse(((x+a-1.2)*S,(y+10.8)*S,(x+a+1.2)*S,(y+13.2)*S),fill=c)
 if k=='pause':
  for a in [8,15]:rr((x+a,y+5,x+a+2.5,y+19),1,c)
 if k=='chevron':l([(9,5),(16,12),(9,19)])
def cover(x,y,n=0,size=44):
 a,b=[('#dcbba7','#7c5765'),('#b5cbd0','#375463'),('#d0bccc','#66566d'),('#ddc994','#6f6245')][n%4]
 rr((x,y,x+size,y+size),4,b)
 d.polygon([(x*S,y*S),((x+size)*S,y*S),((x+size)*S,(y+size*.5)*S),(x*S,(y+size*.8)*S)],fill=a)
def phone(x):
 y=153;rr((x,y,x+380,y+770),28,'white');t(x+22,y+16,'9:41',12);t(x+310,y+16,'5G',12);rr((x+134,y+753,x+246,y+757),2,ink);return y
def dock(x,y):
 rr((x+12,y+628,x+368,y+688),20,'#f7f1f4', '#eee6eb');cover(x+22,y+636,1);t(x+78,y+642,'日语经典歌曲',14);t(x+78,y+665,'80音乐分享',11,mut);ico(x+326,y+646,'pause');
 for j,v in enumerate(['音乐库','搜索','下载','喜欢']):t(x+30+j*92,y+712,v,13,accent if j==0 else mut)



material=ImageFont.truetype('/Users/dfq/works/repo/lw/tingyu/resources/icons/material/MaterialIcons-Regular.otf',24*S)
def clock(x,y,c):d.text((x*S,y*S),chr(58710),font=material,fill=c)
t(32,24,'听屿 · 定时关闭',29)
t(32,69,'紧凑面板 / 状态明确 / 选中样式统一 / 静态设计确认稿，非设备截图',15,mut)
for j in range(3):
 x=32+j*406;t(x,116,['01  关闭状态','02  已选时长 · 草稿','03  倒计时运行中'][j],17);y=phone(x)
 # Keep the player visible; reduce sheet height from 524 to 434.
 rr((x,y+45,x+380,y+343),0,'#aaa1a8');d.ellipse(((x+100)*S,(y+80)*S,(x+280)*S,(y+260)*S),fill='#353039');d.ellipse(((x+120)*S,(y+100)*S,(x+260)*S,(y+240)*S),fill='#ac828b')
 top=y+336;rr((x,top,x+380,y+770),25,'white');rr((x+174,top+12,x+206,top+16),2,'#e7e3e8')
 t(x+24,top+39,'定时关闭',20)
 clock(x+24,top+88,mut if j==0 else accent)
 t(x+62,top+84,['定时已关闭','30 分钟后','24:38'][j],23,mut if j==0 else ink)
 if j==1:t(x+257,top+91,'收起后生效',12,mut)
 if j==2:t(x+277,top+91,'剩余时间',12,mut)
 # Compact duration group, 48dp targets; selected state uses the same tint as finish control.
 for i,v in enumerate([15,30,45,60]):
  bx=x+24+i*85;sel=j>0 and v==30
  rr((bx,top+137,bx+77,top+185),12,'#fff0f5' if sel else '#f5f2f5')
  t(bx+12,top+153,str(v)+' 分钟',14,accent if sel else ink)
 t(x+26,top+215,'自定义时长',15);t(x+270,top+215,'未选择',13,mut);ico(x+329,top+210,'chevron',mut)
 ln([(x+24,top+254),(x+356,top+254)],line,1)
 t(x+24,top+276,'结束方式',13,mut)
 rr((x+24,top+305,x+356,top+353),12,'#f5f2f5');rr((x+28,top+309,x+188,top+349),9,'#fff0f5');t(x+68,top+321,'到时暂停',14,accent);t(x+231,top+321,'播完本首',14)
 if j>0:t(x+162,top+385,'关闭定时',14,mut)
 # Fixed geometry across all states; bottom clearance retained above home indicator.
t(32,956,'关闭状态明确表达，不再用空时间占位；状态行与时长、结束方式分层。',15)
t(32,990,'三种状态保持相同面板高度。保留收起后提交的现有逻辑，不增加额外确认按钮。',13,mut)
im.resize((1250,1040),Image.Resampling.LANCZOS).save(P/'overview.png')
