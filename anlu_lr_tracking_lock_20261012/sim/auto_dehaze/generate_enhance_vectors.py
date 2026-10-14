from pathlib import Path
import random,math
root=Path(__file__).resolve().parent.parent.parent
sim=root/'sim/auto_dehaze';sim.mkdir(exist_ok=True)
def write(p,s):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf-8',newline='\n')
rng=random.Random(20261013);W,H=1280,12
cycles=[];gold=[];validgroups=0
def pack(ps):return sum(((r<<16)|(g<<8)|b)<<(24*p) for p,(r,g,b) in enumerate(ps))
def sat(v):return min(255,max(0,v))
def lum(p):return (p[0]+2*p[1]+p[2])//4
for f,enable in enumerate([0,1,1,0,1,1]):
 pixels=[]
 for y in range(H):
  row=[]
  for x in range(W):
   if f==1:rgb=(48,64,80) # gamma, no false detail on a flat field
   elif f==2:rgb=(255,255,255) if x%21<10 else (0,0,0)
   elif f==4:rgb=((x*7+y*3)%256,(x*3+y*5)%256,(x+y*11)%256)
   else:rgb=tuple(rng.randrange(256) for _ in range(3))
   row.append(rgb)
  pixels.append(row)
 gamma_pixels=[[(tuple(sat(c+round(255*(lum(p)/255)**.85)-lum(p)) for c in p) if enable else p) for p in row] for row in pixels]
 ys=[[lum(p) for p in row] for row in gamma_pixels]
 for y in range(H):
  for gx in range(W//4):
   out=[]
   for px in range(gx*4,gx*4+4):
    cy=ys[y][px];left=ys[y][max(0,px-1)];up=ys[max(0,y-1)][px];ul=ys[max(0,y-1)][max(0,px-1)]
    d=cy-(cy+left+up+ul)//4
    amount=min(4,max(0,(abs(d)-4)//4));correction=(-amount if d<0 else amount) if enable else 0
    out.append(tuple(sat(c+correction) for c in gamma_pixels[y][px]))
   u=int(y==0 and gx==0);l=int(gx==W//4-1)
   for _ in range(rng.randrange(2)):cycles.append(0);gold.append(0)
   # Pin enable flips after SOF; the entire frame must retain its original value.
   pin=enable if u else 1-enable
   cycles.append(pack(pixels[y][gx*4:gx*4+4])|(pin<<96)|(l<<97)|(u<<98)|(1<<99))
   gold.append(pack(out)|(l<<96)|(u<<97)|(1<<98));validgroups+=1
  for _ in range(4):cycles.append(0);gold.append(0)
for _ in range(20):cycles.append(0);gold.append(0)
expected=([0]*6+gold)[:len(cycles)]
work=sim/'work/tb_enhance';work.mkdir(parents=True,exist_ok=True)
write(work/'input.hex','\n'.join(f'{x:025x}' for x in cycles)+'\n')
write(work/'expected.hex','\n'.join(f'{x:025x}' for x in expected)+'\n')
write(work/'count.vh',f'`define N {len(cycles)}\n`define GROUPS {validgroups}\n')
