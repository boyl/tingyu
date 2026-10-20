from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
p=Path('/Users/dfq/works/repo/lw/tingyu/design-review/2026-10-20/queue-select-badge')
W,H=1600,1070
im=Image.new('RGB',(W,H),'#f1edef'); d=ImageDraw.Draw(im)
font='/System/Library/Fonts/STHeiti Light.ttc'
def text(x,y,t,s=16,c='#28252c'): d.text((x,y),t,font=ImageFont.truetype(font,s),fill=c)
def rr(b,r,fill,outline=None,w=1):d.rounded_rectangle(b,r,fill=fill,outline=outline,width=w)
def icon(x,y,k,c='#28252c',size=24):
 # Geometry mirrors resources/icons/svg exports, scaled to 24 grid.
 def pts(v):return [(x+a*size/24,y+b*size/24) for a,b in v]
 def ln(v):d.line(pts(v),fill=c,width=2,joint='curve')
 if k=='more':
  for a in [5,12,19]: d.ellipse((x+a-1,y+11,x+a+1,y+13),fill=c)
 if k=='done':d.ellipse((x+3,y+3,x+21,y+21),outline=c,width=2);ln([(7,12),(10,15),(17,8)])
 if k=='download':ln([(12,3),(12,15)]);ln([(7,10),(12,15),(17,10)]);ln([(4,15),(4,21),(20,21),(20,15)])
 if k=='pause':
  for a in [8,15]:rr((x+a,y+5,x+a+2.5,y+19),1,c)
 if k=='select' or k=='selected':
  d.ellipse((x+3,y+3,x+21,y+21),outline='#fb7299' if k=='selected' else '#726b75',width=2)
  if k=='selected':
   c='#fb7299';ln([(7,12),(10,15),(17,8)])
def cover(x,y,n=0,badge=False):
 cols=[('#e5b697','#713c4c'),('#abc6cd','#294859'),('#d6bdba','#5c536a'),('#d6b66f','#695149')];a,b=cols[n%4]
 rr((x,y,x+44,y+44),5,b);d.polygon([(x,y),(x+44,y),(x+44,y+24),(x,y+38)],fill=a)
 if badge:
  rr((x+23,y+23,x+42,y+42),7,'#534953','#c8bfc9')
  for j,h in enumerate([5,10,7]):rr((x+27+j*4,y+37-h,x+29+j*4,y+37),1,'#fff9fc')
names=['在百万豪装录音棚大声听','日语经典歌曲','晚风中的慢节奏','把日子唱成一首歌','雨落在城市的夜晚','今天也要好好听歌']
text(32,24,'听屿 · 队列与选择体验修订',30);text(32,68,'设计确认稿 / 保留哔哩粉与现有页面语言 / 示意歌曲与封面 / 尚未修改正式应用',16,'#726b75')
for col,title in enumerate(['01  播放队列','02  音乐库 · 多选','03  喜欢 · 多选','04  下载 · 已下载']):
 x=32+col*391; y=152; text(x,112,title,19);rr((x,y,x+362,y+750),25,'white');text(x+20,y+16,'9:41',12);text(x+294,y+16,'5G',12)
 if col==0:
  rr((x+1,y+45,x+361,y+205),0,'#c9b9c3');d.ellipse((x+118,y+55,x+244,y+181),fill='#302b34');d.ellipse((x+140,y+77,x+222,y+159),fill='#aa7c84')
  rr((x,y+184,x+362,y+750),24,'white');text(x+20,y+206,'播放队列 · 78 首',18);text(x+20,y+237,'当前歌曲以音柱与高亮标识',12,'#726b75');start=y+278
 else:
  text(x+20,y+52,'音乐库' if col==1 else '喜欢' if col==2 else '下载',28)
  if col<3:text(x+20,y+112,'已选 2 首',14,'#a93660');text(x+166,y+112,'全选     ⋯     完成',14,'#a93660')
  else:text(x+20,y+110,'已下载          下载任务',16,'#a93660');text(x+20,y+145,'6 首 · 182.6 MB',12,'#726b75')
  start=y+171
 for i in range(6):
  ry=start+i*68
  if col==0 and i==1:rr((x+8,ry-4,x+354,ry+58),8,'#fff0f5')
  cx=x+20
  if col in [1,2]:icon(x+12,ry+10,'selected' if i in [0,2] else 'select');cx=x+54
  if col==0:
   cx=x+34
   if i==1:
    for j,h in enumerate([7,15,10]):rr((x+12+j*5,ry+30-h,x+15+j*5,ry+30),1,'#fb7299')
  cover(cx,ry,i,col==3 and i==1);tx=cx+56
  text(tx,ry+3,names[i][:12] if col in [1,2] else names[i],13,'#a93660' if col in [0,3] and i==1 else '#28252c');text(tx,ry+27,['JLRS-LeoFM','80音乐分享','听见生活'][i%3],11,'#726b75')
  if col in [0,3]:icon(x+323,ry+10,'more')
  d.line((x+16,ry+59,x+346,ry+59),fill='#eee8ed')
 if col:
  rr((x+12,y+627,x+350,y+685),16,'#f6edf2');cover(x+20,y+634,1);text(x+75,y+639,'日语经典歌曲',13);text(x+75,y+661,'80音乐分享',11,'#726b75');icon(x+306,y+642,'pause');text(x+24,y+704,'音乐库        搜索        喜欢        下载',13,'#726b75')
 rr((x+129,y+735,x+233,y+739),2,'#302a32')
text(32,938,'选择与已下载复用现有圆圈勾',18)
for i,(k,label) in enumerate([('select','未选择'),('selected','已选择'),('download','下载'),('done','已下载')]):
 x=32+i*225;icon(x,980,k,'#fb7299' if k in ['selected','done'] else '#28252c');text(x+34,984,label,15)
text(975,948,'当前曲目徽标',18);cover(975,984,1,True);text(1035,987,'封面内圆角玻璃底＋白色音柱',15);text(1035,1014,'播放时轻动，暂停与减少动态时静止',13,'#726b75')
im.save(p/'overview.png')
