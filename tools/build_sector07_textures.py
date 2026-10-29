"""Original tileable Sector 07 PBR textures and compound wear mask; dev-only NumPy/Pillow."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter
OUT=Path(__file__).resolve().parents[1]/'assets/sector07/textures';OUT.mkdir(parents=True,exist_ok=True)
rng=np.random.default_rng(7012);N=512

def noise(size):
 a=rng.integers(0,256,(size,size),dtype=np.uint8)
 return np.asarray(Image.fromarray(a).resize((N,N),Image.Resampling.BICUBIC),dtype=float)/255
fine=noise(512);medium=noise(64);macro=noise(12)
def write(name,base,height,rough):
 col=np.array(base)[None,None,:]*(.82+.23*medium[:,:,None]+.07*fine[:,:,None])
 if name=='wood':
  y,x=np.mgrid[:N,:N];grain=np.sin(x*.33+medium*8)+.4*np.sin(x*.82+macro*6)
  col*=.91+grain[:,:,None]*.08; height=height+grain*.13
 rgba=np.concatenate([np.clip(col,0,255),np.full((N,N,1),rough)],axis=2).astype(np.uint8)
 Image.fromarray(rgba,'RGBA').save(OUT/(name+'_albedo.png'))
 dy,dx=np.gradient(height);n=np.stack([-dx*3,-dy*3,np.ones_like(dx)],axis=2);n/=np.linalg.norm(n,axis=2)[:,:,None]
 Image.fromarray(np.uint8(np.clip((n*.5+.5)*255,0,255)),'RGB').save(OUT/(name+'_normal.png'))
write('sand',(158,147,125),medium*.5+fine*.16,242)
write('dirt',(117,110,94),medium*.7+fine*.2,248)
pits=(fine<.035).astype(float)
write('concrete',(180,181,173),medium*.1+fine*.035-pits*.22,230)
write('wood',(159,120,78),medium*.18+fine*.07,225)
y,x=np.mgrid[:N,:N]
weave=(np.sin(x*np.pi/2)*np.sin(y*np.pi/2))*.04
write('canvas',(144,131,101),weave+fine*.015,247)
# World-specific variation: worn vehicle tracks and compacted routes; no per-pixel procedural shader noise.
x=(x/N-.5)*64; z=(y/N-.5)*64
mask=.15+.20*macro
for xx in [-10,10]:
 for offset in [-.65,.65]:mask+=np.exp(-((x-xx-offset)/.23)**2)*.38*np.exp(-(z/22)**8)
mask+=np.exp(-((x-1)/4.8)**2)*np.exp(-((z-6)/17)**8)*.48
for cx,cz in [(-18,-8),(14,-1),(-18,13.5)]:mask+=.75*np.exp(-((x-cx)/3)**2-((z-cz)/4)**2)
mask=np.clip(mask,0,1)
Image.fromarray(np.uint8(np.stack([mask,.25+macro*.65,medium],axis=2)*255),'RGB').save(OUT/'ground_mask.png')
print('Original 512px PBR tiles and wear mask generated; existing cargo textures preserved.')
