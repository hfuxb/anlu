"""Extract two independent 16x16 templates using the RTL sampling rules.

Run with two source paths once; subsequent runs use local reference originals.
The clean blue-face rectangle (not paper/text) is normalized. Pixel thresholds,
4-pixel majority, sampled row phase, foreground occupancy and INNER_MASK match RTL.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter
import sys, re, json, hashlib, shutil, random

here=Path(__file__).resolve().parent
root=here.parents[1]
refs=here/'reference_20261012'
refs.mkdir(exist_ok=True)
if len(sys.argv)==3:
    for name,p in zip(('left_original.jpg','right_original.jpg'),sys.argv[1:]):
        shutil.copy2(p,refs/name)
rtl=root/'fpga/traffic_sign_td/user_source/image/traffic_sign/traffic_sign_detector_96.v'
text=rtl.read_text(encoding='utf-8')
mask=int(re.search(r"INNER_MASK=256'h([0-9a-fA-F]+)",text)[1],16)
def blue(p):
    r,g,b=p
    return b>=40 and b>r+12 and b>g+5 and r*4<=b*3
def white(p):
    return max(p)>=65 and min(p)*3>=max(p)*2
faces={};originals={};meta={};templates={}
for direction in ('left','right'):
    p=refs/(direction+'_original.jpg')
    im=Image.open(p).convert('RGB');originals[direction]=im
    w,h=im.size
    coords=[(i%w,i//w) for i,c in enumerate(im.getdata()) if blue(c)]
    bbox=(min(x for x,y in coords),min(y for x,y in coords),max(x for x,y in coords)+1,max(y for x,y in coords)+1)
    face=im.crop(bbox);faces[direction]=face
    face.save(refs/(direction+'_face.png'))
    # 512px face has enough samples per cell to avoid a tiny-image phase bias.
    face=face.resize((512,512),Image.Resampling.LANCZOS)
    pixels=face.load();samples=[];blue_coords=[]
    for y in range(1,512,4):
        cy=y//4
        for gx in range(128):
            chunk=[pixels[gx*4+k,y] for k in range(4)]
            is_b=sum(blue(c) for c in chunk)>=2
            is_w=sum(white(c) for c in chunk)>=2
            samples.append((gx,cy,is_w))
            if is_b:blue_coords.append((gx,cy))
    x0=min(x for x,y in blue_coords);x1=max(x for x,y in blue_coords)
    y0=min(y for x,y in blue_coords);y1=max(y for x,y in blue_coords)
    counts=[[0,0] for _ in range(256)]
    for x,y,on in samples:
        if x0<=x<=x1 and y0<=y<=y1:
            bx=(x-x0)*16//(x1-x0+1);by=(y-y0)*16//(y1-y0+1)
            c=counts[by*16+bx];c[0]+=on;c[1]+=1
    bits=0
    for i,(n,total) in enumerate(counts):
        if total and n*4>=total and (mask>>i)&1:bits|=1<<i
    templates[direction]=bits
    preview=Image.new('RGB',(384,384));d=ImageDraw.Draw(preview)
    for i in range(256):
        x=i%16;y=i//16
        color='white' if (bits>>i)&1 else ('black' if (mask>>i)&1 else (90,90,90))
        d.rectangle((x*24,y*24,x*24+23,y*24+23),fill=color)
    preview.save(refs/(direction+'_template.png'))
    meta[direction]={'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'image_size':im.size,'blue_bbox':bbox,'sample_roi_512':[x0,y0,x1,y1],'template_hex':f'{bits:064x}','foreground_cells':bits.bit_count()}
    print(direction,meta[direction])
text=re.sub(r"LEFT_TEMPLATE=256'h[0-9a-fA-F]+;",f"LEFT_TEMPLATE=256'h{templates['left']:064x};",text)
if 'RIGHT_TEMPLATE=' in text:
    text=re.sub(r"RIGHT_TEMPLATE=256'h[0-9a-fA-F]+;",f"RIGHT_TEMPLATE=256'h{templates['right']:064x};",text)
else:
    text=text.replace(f"LEFT_TEMPLATE=256'h{templates['left']:064x};",f"LEFT_TEMPLATE=256'h{templates['left']:064x};\n localparam [255:0] RIGHT_TEMPLATE=256'h{templates['right']:064x};")
text=text.replace('wire template_r=LEFT_TEMPLATE[{scan_addr[7:4],~scan_addr[3:0]}];','wire template_r=RIGHT_TEMPLATE[scan_addr];')
text=text.replace('// bit y*16+x; sign FACE from supplied image; text is excluded.','// bit y*16+x; independent left/right templates from the 2026-10-12\n // user reference images, normalized with the same blue/white sampling rules.')
rtl.write_text(text,encoding='utf-8')
(refs/'template_evidence.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')

def save_rgb(path,im):
    pix=list(im.getdata())
    path.with_suffix('.png').parent.mkdir(exist_ok=True)
    im.save(path.with_suffix('.png'))
    path.with_suffix('.hex').write_text('\n'.join(''.join(''.join(f'{v:02x}' for v in p) for p in pix[i:i+4][::-1]) for i in range(0,len(pix),4))+'\n')

# Replace the regression fixtures with scenes from the user's actual standards.
cases=[]
def scene(name,direction,size,xy,brightness=1.0,blur=0,angle=0,noise=False,distract=False):
    face=faces[direction]
    if blur:face=face.filter(ImageFilter.GaussianBlur(blur))
    if angle:face=face.rotate(angle,resample=Image.Resampling.BICUBIC,fillcolor='white')
    im=Image.new('RGB',(320,240),(76,76,76))
    if distract:
        d=ImageDraw.Draw(im);d.rectangle((2,2,290,18),fill=(35,54,145));d.rectangle((240,178,300,238),fill=(35,54,145))
    im.paste(face.resize((size,size),Image.Resampling.LANCZOS),xy)
    im=ImageEnhance.Brightness(im).enhance(brightness)
    if noise:
        rnd=random.Random(1012);p=im.load()
        for y in range(240):
            for x in range(320):p[x,y]=tuple(max(0,min(255,v+rnd.randint(-5,5))) for v in p[x,y])
    cases.append((name,im,'L' if direction=='left' else 'R'))
scene('left120','left',120,(80,48))
scene('right160','right',160,(60,36))
scene('left_dark','left',144,(76,48),brightness=.45,noise=True)
scene('right_distractors','right',128,(60,32),distract=True)
blank=Image.new('RGB',(160,160),'white');ImageDraw.Draw(blank).ellipse((0,0,159,159),fill=(35,54,145))
im=Image.new('RGB',(320,240),(76,76,76));im.paste(blank.resize((128,128)),(72,48));cases.append(('blue_no_arrow',im,'?'))
straight=blank.copy();ImageDraw.Draw(straight).polygon([(70,135),(90,135),(90,65),(110,65),(80,30),(50,65),(70,65)],fill='white')
im=Image.new('RGB',(320,240),(76,76,76));im.paste(straight.resize((128,128)),(72,48));cases.append(('straight_reject',im,'?'))
scene('right96','right',96,(156,80))
scene('left_blur','left',160,(24,40),blur=2)
scene('left_rotate12','left',144,(84,56),angle=12)
scene('right_rotate12','right',144,(68,44),angle=-12)
for direction in ('left','right'):
    im=Image.new('RGB',(320,240),(76,76,76));src=originals[direction]
    im.paste(src.resize((160,round(160*src.height/src.width)),Image.Resampling.LANCZOS),(64,20))
    cases.append((direction+'_with_text',im,'L' if direction=='left' else 'R'))
calls=[]
for name,im,expected in cases:
    save_rgb(here/name,im);calls.append(f'run_case("../{name}.hex",8\'h{ord(expected):02x});')
(here/'cases.vh').write_text('\n'.join(calls)+'\n')
im=Image.new('RGB',(1280,720),(76,76,76));src=originals['right']
im.paste(src.resize((360,round(360*src.height/src.width)),Image.Resampling.LANCZOS),(600,180))
save_rgb(here/'right_full720',im)
print('Prepared independent reference templates and 12 reference scenes')
