"""Original procedural 2D cloud masks. No downloaded images or AI assets.

Four seeded, wind-stretched angular silhouettes, generated offline once.
Requires Pillow, already used by the project's image tooling.
"""
import random
from pathlib import Path
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]


def build():
    size=128
    atlas=Image.new('RGBA',(size*4,size),(255,255,255,0))
    outline=[(.04,.68),(.29,.54),(.21,.54),(.39,.43),(.36,.33),(.64,.23),(.54,.38),(.77,.36),(.69,.48),(.96,.54),(.75,.61),(.85,.64),(.55,.74),(.40,.69),(.13,.76),(.27,.65)]
    for tile in range(4):
        rng=random.Random(20261113+tile)
        scale=4
        mask=Image.new('L',(size*scale,size*scale),0)
        draw=ImageDraw.Draw(mask)
        points=[((u+rng.uniform(-.018,.018))*size*scale,(v+rng.uniform(-.025,.025))*size*scale) for u,v in outline]
        draw.polygon(points,fill=255)
        # Narrow horizontal gaps and detached wisps break up the cloud into
        # the wind-carved ribbons of the user's visual reference.
        for i in range(2):
            u=rng.uniform(.28,.48);v=.49+i*.13
            draw.polygon([(u*size*scale,v*size*scale),((u+.27)*size*scale,(v-.025)*size*scale),((u+.18)*size*scale,(v+.025)*size*scale)],fill=0)
        draw.polygon([(.06*size*scale,.83*size*scale),(.32*size*scale,.78*size*scale),(.24*size*scale,.82*size*scale),(.35*size*scale,.83*size*scale)],fill=180)
        mask=mask.resize((size,size),Image.Resampling.LANCZOS)
        tile_image=Image.new('RGBA',(size,size),(255,255,255,0))
        tile_image.putalpha(mask)
        atlas.paste(tile_image,(tile*size,0))
    path=ROOT/'assets/textures/sf3_cloud_atlas.png'
    path.parent.mkdir(parents=True,exist_ok=True)
    atlas.save(path,optimize=True)
    print(path)


if __name__=='__main__': build()
