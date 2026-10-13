"""Independent whole-image dehaze and temporal luma-grid reference."""
from pathlib import Path
import random
root=Path(__file__).parent
out=root/'work/tb_extra_modes';out.mkdir(parents=True,exist_ok=True)
rng=random.Random(20261013)
gw,h=16,12
modes=[3,2,1,4,4,4,4,5,0,4,4,5,5,3]
prev=None
inputs=[];values=[]
def restore(v,d):
    t=max(64,256-((d*218+128)>>8));m=abs(v-240)
    if t>=240:c=m
    elif t>=224:c=m+(m>>4)
    elif t>=192:c=m+(m>>2)
    elif t>=160:c=m+(m>>1)
    elif t>=128:c=m+(m>>1)+(m>>2)
    else:c=m<<1
    return max(0,min(255,240+(c if v>=240 else -c)))
for f,mode in enumerate(modes):
    # Several MOT frames share a static scene; f=5 changes one 4x4 block,
    # f=6 only adds low-amplitude noise. Non-MOT frames break continuity.
    scene=[];dark=[]
    for y in range(h):
        row=[];dr=[]
        for x in range(gw):
            base=65+(x*7+y*3)%80
            if f in (5,6) and x==7 and 4<=y<8:base+=70
            if f==6:base+=3
            rgb=[(base+p,base+2*p,base+3*p) for p in range(4)]
            if mode==5:rgb=[tuple(rng.randrange(256) for _ in range(3)) for p in range(4)]
            row.append(rgb);dr.append(min(min(p) for p in rgb))
        scene.append(row);dark.append(dr)
    current=[[sum(r+2*g+b for r,g,b in scene[y][x])//16 for x in range(gw)] for y in range(0,h,4)]
    for y in range(h):
        for x in range(gw):
            rgb=scene[y][x];res=rgb
            if mode==5:
                d=min(dark[yy][xx] for yy in range(max(0,y-2),y+1) for xx in range(max(0,x-2),x+1))
                res=[tuple(restore(v,d) for v in p) for p in rgb]
            elif mode==4 and prev is not None and abs(current[y//4][x]-prev[y//4][x])>=24:
                res=[(255,g//2,b//2) for r,g,b in rgb]
            user=int(y==0 and x==0);last=int(x==gw-1)
            # A different mode mid-frame must not split the frame.
            pin_mode=mode if user else ((mode+1)%6)
            for _ in range(rng.randrange(3)):inputs.append(0);values.append(0)
            pack=lambda pixels:sum(((r<<16)|(g<<8)|b)<<(24*p) for p,(r,g,b) in enumerate(pixels))
            inputs.append(pack(rgb)|(pin_mode<<96)|(last<<99)|(user<<100)|(1<<101))
            values.append(pack(res)|(last<<96)|(user<<97)|(1<<98))
    prev=current if mode==4 else None
for _ in range(20):inputs.append(0);values.append(0)
checks=([0]*12+values)[:len(inputs)]
(out/'input.hex').write_text('\n'.join(f'{v:026x}' for v in inputs)+'\n')
(out/'expected.hex').write_text('\n'.join(f'{v:025x}' for v in checks)+'\n')
(out/'count.vh').write_text(f'`define EXTRA_CYCLES {len(inputs)}\n')
print(f'Generated {len(inputs)} cycles, {len(modes)} frames, independent pixel reference.')
