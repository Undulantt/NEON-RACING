"""Original deterministic synth study and coastal noise; no external samples."""
import math, random, wave, struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
RATE=22050

def save(name,samples):
    peak=max(abs(v) for v in samples)
    pcm=b''.join(struct.pack('<h',round(v/max(1,peak)*28000)) for v in samples)
    with wave.open(str(ROOT/'assets/audio'/name),'wb') as out:
        out.setparams((1,2,RATE,0,'NONE','not compressed'));out.writeframes(pcm)
    print(name,len(samples)/RATE,'seconds; peak',peak)

beat=60/160
length=32*beat
rng=random.Random(81090)
notes=[76,79,83,79,74,78,81,78,72,76,79,83,74,78,81,86]
bass=[40,38,36,38]
music=[]
for i in range(round(length*RATE)):
    t=i/RATE;b=t/beat;local=(b%1)*beat;half=(b%0.5)*beat
    kick=math.sin(2*math.pi*(48*local+7*(1-math.exp(-local*35))))*math.exp(-local*22)*0.5
    noise=rng.uniform(-1,1)
    snare=noise*math.exp(-local*35)*0.16 if int(b)%4 in (1,3) else 0
    hat=noise*math.exp(-half*90)*0.05
    f=440*2**((bass[int(b)//8]-69)/12)
    low=(math.sin(2*math.pi*f*t)+0.25*math.sin(4*math.pi*f*t))*math.exp(-half*9)*0.19
    n=notes[int(b*2)%len(notes)];f=440*2**((n-69)/12)
    lead=(math.sin(2*math.pi*f*t)+0.22*math.sin(4*math.pi*f*t))*math.exp(-half*13)*min(1,half*250)*0.14
    fade=min(1,t/0.008,(length-t)/0.008)
    music.append((kick+snare+hat+low+lead)*fade)
save('malecon_night_demo.wav',music)
surf=[];smooth=0.0
for i in range(RATE*12):
    t=i/RATE;smooth=0.94*smooth+0.06*rng.uniform(-1,1)
    surf.append(smooth*(0.5+0.2*math.sin(2*math.pi*t/6))*min(1,t/0.2,(12-t)/0.2))
save('malecon_surf.wav',surf)
