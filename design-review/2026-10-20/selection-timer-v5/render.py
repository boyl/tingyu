from PIL import Image,ImageDraw,ImageFont
from pathlib import Path
P=Path(__file__).resolve().parent
S=2
im=Image.new('RGB',(1660*S,1070*S),'#f2eef0');d=ImageDraw.Draw(im)
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


material=ImageFont.truetype('/Users/dfq/works/repo/lw/tingyu/resources/icons/material/MaterialIcons-Regular.otf',20*S)
def clock(x,y,c):d.text((x*S,y*S),chr(58710),font=material,fill=c)
t(32,24,'tingyu · 连续列表与自定义定时',29)
t(32,69,'设计确认稿 05 / 多选取消底色与歌名染色 / 定时状态统一16字号 / 示例内容，非设备截图',15,mut)
x=32;t(x,116,'01  全选 · 无背景图层',17);y=phone(x)
t(x+20,y+57,'音乐库',28);t(x+20,y+120,'已选 78 首',14,accent)
# Existing checklist Material icon is used rather than a drawn substitute.
# resources/icons/svg/select.svg, 24-grid.
for dy in [5,12,19]:
 ln([(x+113+3,y+115+dy),(x+113+5,y+115+dy+2),(x+113+8,y+115+dy-2)])
 ln([(x+113+12,y+115+dy),(x+113+21,y+115+dy)])
ico(x+174,y+115,'folderPlus');ico(x+254,y+115,'download');ln([(x+302,y+114),(x+302,y+140)],line,1);t(x+320,y+120,'完成',14,accent)
names=['诺爷Plus · 归途的光','印度神曲 · Aankhen Khuli','日语经典歌曲 · 东京爱情故事','工作／睡眠／学习专用音乐','怀旧经典 · 细听有味道','雨落在城市的夜晚']
for i,v in enumerate(names):
 ry=y+177+i*68;ico(x+20,ry+8,'done',pink);cover(x+62,ry,i);t(x+118,ry+3,v,13,ink);t(x+118,ry+27,['4K无损音乐','4K音乐馆','80音乐分享','ACG妙音乐'][i%4],11,mut)
 if i==2:
  for z,h in enumerate([4,10,6]):rr((x+339+z*4,ry+36-h,x+341+z*4,ry+36),1,pink)
dock(x,y)
for j in range(3):
 x=438+j*406;t(x,116,['02  定时 · 已关闭','03  自定义 · 40分钟','04  滑动后 · 80分钟'][j],17);y=phone(x)
 top=y+(336 if j==0 else 185)
 rr((x,y+45,x+380,top+8),0,'#aaa1a8');d.ellipse(((x+110)*S,(y+66)*S,(x+270)*S,(y+226)*S),fill='#353039');d.ellipse(((x+130)*S,(y+86)*S,(x+250)*S,(y+206)*S),fill='#ac828b')
 rr((x,top,x+380,y+770),25,'white');rr((x+174,top+12,x+206,top+16),2,'#e7e3e8');t(x+24,top+39,'定时关闭',18)
 clock(x+24,top+88,mut if j==0 else accent)
 t(x+58,top+87,['定时已关闭','40 分钟后','80 分钟后'][j],16,mut if j==0 else ink)
 if j>0:t(x+275,top+90,'收起后生效',12,mut)
 for i,v in enumerate([15,30,45,60]):
  bx=x+24+i*85;rr((bx,top+133,bx+77,top+181),12,'#f5f2f5');t(bx+12,top+149,str(v)+' 分钟',14)
 t(x+26,top+211,'自定义时长',15)
 t(x+(270 if j==0 else 247),top+211,['未选择','40 分钟','1 小时 20 分钟'][j],12,mut if j==0 else accent)
 if j==0:ico(x+329,top+206,'chevron',mut)
 else:
  # Open wheel: same font hierarchy and existing neutral selected band.
  wy=top+258;rr((x+24,wy+48,x+356,wy+96),10,'#f5f2f5')
  rows=[['0 小时','0 小时','1 小时'],['39 分钟','40 分钟','41 分钟']] if j==1 else [['0 小时','1 小时','2 小时'],['19 分钟','20 分钟','21 分钟']]
  for col,vals in enumerate(rows):
   for row,v in enumerate(vals):
    if j==1 and col==0 and row==0:continue
    t(x+79+col*154,wy+row*48+15,v,18 if row==1 else 15,ink if row==1 else '#aaa3ac')
  # Caret uses the same chevron geometry with a rotation indicated by its orientation.
  ln([(x+332,top+224),(x+338,top+218),(x+344,top+224)],mut)
 by=top+(254 if j==0 else 417)
 ln([(x+24,by),(x+356,by)],line,1);t(x+24,by+21,'结束方式',13,mut)
 rr((x+24,by+50,x+356,by+98),12,'#f5f2f5');rr((x+28,by+54,x+188,by+94),9,'#fff0f5');t(x+68,by+66,'到时暂停',14,accent);t(x+231,by+66,'播完本首',14)
 if j>0:t(x+162,by+126,'关闭定时',14,mut)
t(32,960,'多选只保留左侧粉色勾；全选时仍是干净的连续列表，歌名保持正常色。',15)
t(32,995,'当前播放用音柱单独表达。封面、行高、工具栏及底部播放器沿用现有布局。',13,mut)
t(844,960,'滚轮40分钟 → 上方40分钟后；滚轮1小时20分钟 → 上方80分钟后。',15)
t(844,995,'滚动时实时预览，入口右侧同步显示；收起后开始计时。以上尚未改应用。',13,mut)
im.resize((1660,1070),Image.Resampling.LANCZOS).save(P/'overview.png')
