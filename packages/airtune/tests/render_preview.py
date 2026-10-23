#!/usr/bin/env python3
"""Render exported real-VM commands with approximate desktop fonts, not a panel emulator."""
from pathlib import Path
import argparse
import json
from PIL import Image, ImageDraw, ImageFont

def render(path, font_path):
    data=json.loads(path.read_text())
    image=Image.new('RGB',(data['width'],data['height']),'white')
    draw=ImageDraw.Draw(image)
    sizes=[18,24,30,46]
    fonts=[ImageFont.truetype(str(font_path),size) for size in sizes]
    for c in data['commands']:
        kind=c['kind'];x,y,w,h=c['x'],c['y'],c['w'],c['h']
        rect=(x,y,x+w-1,y+h-1);shade=(c['gray']*17,)*3
        if kind in (0,3):
            radius=min(w,h)//2 if kind==3 else c['radius']
            draw.rounded_rectangle(rect,radius,fill=None if c['style'] else shade,
                                   outline=shade if c['style'] else None,width=max(1,c['style']))
        elif kind in (1,4):
            font=fonts[c['font']] if kind==1 else fonts[1]
            color=shade if kind==1 else (255,)*3 if c['style']==3 else (0,)*3
            if kind==4:
                fill='black' if c['style']==3 else '#dddddd' if c['style']==2 else 'white'
                draw.rounded_rectangle(rect,min(16,h//4),fill=fill,outline=None if c['style']==1 else color,width=1)
            label=c['text'];lines=[];line='';available=w-(12 if kind==4 else 0)
            for char in label:
                if line and draw.textlength(line+char,font=font)>available:lines.append(line);line=''
                line+=char
            if line:lines.append(line)
            max_lines=max(1,h//(font.size+2));lines=lines[:max_lines]
            top=y+(h-len(lines)*(font.size+2))/2
            for line in lines:
                length=draw.textlength(line,font=font)
                align=1 if kind==4 else c['align']
                left=x+(w-length)*align/2
                draw.text((left,top),line,font=font,fill=color,anchor='lt');top+=font.size+2
    output=path.with_suffix('.png');image.save(output);print(output)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory',type=Path)
    parser.add_argument('--font',type=Path,default=Path('/System/Library/Fonts/STHeiti Medium.ttc'))
    args=parser.parse_args()
    for path in sorted(args.directory.glob('*.json')):render(path,args.font)
