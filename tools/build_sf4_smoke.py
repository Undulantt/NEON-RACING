"""Original three-tone lavender/pink smoke following the user's art direction."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import random

ROOT=Path(__file__).resolve().parents[1]

def build():
    mask=Image.new('L',(128,128),0);d=ImageDraw.Draw(mask)
    for x,y,r in [(28,72,21),(42,45,25),(68,30,22),(89,47,24),(99,73,22),(73,89,26),(45,91,20)]:
        d.ellipse((x-r,y-r,x+r,y+r),fill=255)
    # Wind-torn tips, rather than perfectly round soft discs.
    for poly in [[(14,84),(3,77),(20,67)],[(31,99),(22,112),(51,101)],[(88,27),(102,20),(97,42)],[(94,93),(118,104),(101,79)]]:d.polygon(poly,fill=255)
    inner=mask.filter(ImageFilter.MinFilter(5))
    highlights=Image.new('L',mask.size,0);d=ImageDraw.Draw(highlights)
    for x,y,r in [(42,45,14),(71,31,17),(91,48,13)]:d.ellipse((x-r,y-r,x+r,y+r),fill=255)
    highlights=ImageChops.multiply(highlights,inner)
    image=Image.new('RGBA',mask.size,(85,66,106,0))
    image.paste((85,66,106,255),(0,0,128,128),mask)
    image.paste((164,126,174,255),(0,0,128,128),inner)
    image.paste((222,166,207,255),(0,0,128,128),highlights)
    path=ROOT/'assets/textures/sf4_smoke.png';path.parent.mkdir(parents=True,exist_ok=True)
    image.save(path,optimize=True)
    print(path)

if __name__=='__main__':build()
