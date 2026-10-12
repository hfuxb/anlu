from pathlib import Path
from PIL import Image, ImageDraw

out=Path(__file__).resolve().parent/'tracking'
out.mkdir(exist_ok=True)
left=Image.open(out.parent/'reference_20261012/left_face.png').convert('RGB')
right=Image.open(out.parent/'reference_20261012/right_face.png').convert('RGB')
blank_face=Image.new('RGB',(120,120),'white')
ImageDraw.Draw(blank_face).ellipse((0,0,119,119),fill=(29,57,133))

def write(name,sign=None,size=120,xy=(48,48),distractor=False):
    im=Image.new('RGB',(640,360),(76,76,76))
    if sign is not None:
        im.paste(sign.resize((size,size),Image.Resampling.LANCZOS),xy)
    if distractor:
        im.paste(right.resize((200,200),Image.Resampling.LANCZOS),(360,100))
    im.save(out/(name+'.png'))
    pix=list(im.getdata())
    (out/(name+'.hex')).write_text('\n'.join(''.join(''.join(f'{v:02x}' for v in p) for p in pix[i:i+4][::-1]) for i in range(0,len(pix),4))+'\n')

write('left',left)
write('left_moved',left,xy=(56,48))
write('no_arrow',blank_face,xy=(64,48))
write('opposite_in_lock',right,xy=(72,48))
write('two_signs',left,xy=(80,48),distractor=True)
write('only_distractor',distractor=True)
write('left_return',left,xy=(84,48))
write('blank')
write('right_new',right,size=140,xy=(300,120))
write('right_same_position',right)
print('Generated tracking/loss/distractor frames:',out)
