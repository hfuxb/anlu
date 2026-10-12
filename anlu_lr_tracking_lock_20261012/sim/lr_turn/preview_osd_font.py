"""Render actual RTL font rows exported by run_osd_font_sim.ps1."""
from pathlib import Path
from PIL import Image, ImageDraw
root=Path(__file__).resolve().parent
glyphs={}
for line in (root/'work/tb_osd_font/font_rows.txt').read_text().splitlines():
    c,row,bits=line.split()
    glyphs.setdefault(int(c,16),[0]*16)[int(row)]=int(bits,16)
im=Image.new('RGB',(704,272),(22,25,29))
draw=ImageDraw.Draw(im)
for y,text in [(8,'ABCDEFGHIJKLMNOPQRSTUVWXYZ'),(56,'0123456789:?'),
               (120,'CNT:012345'),(152,'DIR:L  DIR:R  DIR:?'),
               (184,'MODE:RAW  MODE:SIG'),(216,'MATCH:093')]:
    for i,ch in enumerate(text):
        x=8+i*24
        for r,bits in enumerate(glyphs.get(ord(ch),[0]*16)):
            for c in range(16):
                if bits&(1<<(15-c)):
                    draw.rectangle((x+c,y+r,x+c,y+r),fill=(255,242,0))
out=root/'osd_preview'
out.mkdir(exist_ok=True)
im.resize((1408,544),Image.Resampling.NEAREST).save(out/'uniform_font_preview.png')
print(out/'uniform_font_preview.png')
