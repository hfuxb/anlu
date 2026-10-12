"""Independent whole-image Sobel + erosion + dilation reference, zero padding."""
from pathlib import Path
from random import Random
from PIL import Image
import json

out = Path(__file__).resolve().parent/'opening_golden'
out.mkdir(exist_ok=True)
W,H=64,32
rng=Random(8715)
rgb=[]
for y in range(H):
    row=[]
    for x in range(W):
        # Sloping bright region, fine texture, and sparse impulse noise.
        v=min(245,max(15,15+(x-18)*14)) if 5<=y<27 and 16<=x<45 else 35
        if 8<=x<14 and 8<=y<23: v=220 if x%2 else 20
        if rng.random()<0.045: v=rng.choice((0,255))
        row.append((v,max(0,v-7),min(255,v+9)))
    rgb.append(row)

def at(a,x,y): return a[y][x] if x>=0 and y>=0 else 0
def morph(a,erosion):
    return [[int(all(values) if erosion else any(values))
             for x in range(W)
             for values in [[at(a,x-dx,y-dy) for dy in range(3) for dx in range(3)]]]
            for y in range(H)]
gray=[[(77*r+150*g+29*b)>>8 for r,g,b in row] for row in rgb]
sobel=[]
for y in range(H):
    row=[]
    for x in range(W):
        gx=sum(at(gray,x,y-k)*v-at(gray,x-2,y-k)*v for k,v in enumerate((1,2,1)))
        gy=sum(at(gray,x-k,y)*v-at(gray,x-k,y-2)*v for k,v in enumerate((1,2,1)))
        row.append(int(abs(gx)+abs(gy)>24))
    sobel.append(row)
ero=morph(sobel,True)
opened=morph(ero,False)
direct=morph(sobel,False)
counts={n:sum(map(sum,a)) for n,a in [('sobel',sobel),('erosion',ero),('opening',opened),('direct_dilation',direct)]}
assert 0<counts['erosion']<counts['opening']<counts['direct_dilation'],counts
assert opened!=direct

def pack_rgb(a):
    return '\n'.join(''.join(''.join(f'{v:02x}' for v in p) for p in row[x:x+4][::-1])
                     for row in a for x in range(0,W,4))+'\n'
def binary_rgb(a): return [[(255,)*3 if v else (0,)*3 for v in row] for row in a]
(out/'input.hex').write_text(pack_rgb(rgb))
def pack128(a):
    words=pack_rgb(a).splitlines()
    bits=''.join(words)
    return '\n'.join(bits[i:i+32] for i in range(0,len(bits),32))+'\n'
(out/'input128.hex').write_text(pack128(rgb))
(out/'gray.hex').write_text('\n'.join(''.join(f'{v:02x}' for v in row[x:x+4][::-1]) for row in gray for x in range(0,W,4))+'\n')
for name,a in [('erosion',ero),('opening',opened),('direct_dilation',direct)]:
    (out/(name+'.hex')).write_text(pack_rgb(binary_rgb(a)))
    (out/(name+'128.hex')).write_text(pack128(binary_rgb(a)))
    im=Image.new('RGB',(W,H));im.putdata([p for row in binary_rgb(a) for p in row]);im.resize((640,320)).save(out/(name+'.png'))
(out/'counts.json').write_text(json.dumps(counts,indent=2))
print(counts)
