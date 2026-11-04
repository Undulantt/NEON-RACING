"""Analyze the captured game Engine bus and export a level-normalized preview."""
from pathlib import Path
import json, math, wave
import numpy as np
ROOT=Path(__file__).resolve().parents[1]

def main():
    source=ROOT/'docs/evidence/engine_gear_changes.wav'
    with wave.open(str(source),'rb') as stream:
        rate=stream.getframerate(); channels=stream.getnchannels()
        assert stream.getsampwidth()==2
        samples=np.frombuffer(stream.readframes(stream.getnframes()),dtype='<i2').reshape(-1,channels).astype(np.float64)/32768
    mono=samples.mean(axis=1)
    rms=float(np.sqrt(np.mean(mono*mono)));peak=float(np.max(np.abs(mono)))
    assert rms>.0001 and peak<.99,(rms,peak)
    gain=min(.78/peak,.16/rms)
    new_rate=22050
    at=np.arange(int(len(mono)/rate*new_rate))*rate/new_rate
    preview=np.interp(at,np.arange(len(mono)),mono)*gain
    destination=ROOT/'docs/evidence/engine_gear_changes_preview.wav'
    with wave.open(str(destination),'wb') as output:
        output.setnchannels(1);output.setsampwidth(2);output.setframerate(new_rate)
        output.writeframes(np.clip(preview*32767,-32767,32767).astype('<i2').tobytes())
    capture=json.loads((ROOT/'docs/powertrain_capture_validation.json').read_text(encoding='utf-8'))
    telemetry=capture['telemetry']; shifts=[]
    for previous,current in zip(telemetry,telemetry[1:]):
        if previous['gear']>0 and current['gear']>0 and current['gear']!=previous['gear']:
            window=[v for v in telemetry if current['t']<=v['t']<=current['t']+.35]
            shifts.append({'t':current['t'],'from':previous['gear'],'to':current['gear'],'rpm_before':previous['rpm'],'minimum_rpm':min(v['rpm'] for v in window),'maximum_rpm':max(v['rpm'] for v in window),'pitch_before':previous['pitch'],'minimum_pitch':min(v['pitch'] for v in window),'maximum_pitch':max(v['pitch'] for v in window)})
    ups=[s for s in shifts if s['to']>s['from']];downs=[s for s in shifts if s['to']<s['from']]
    assert len(ups)==6 and len(downs)==6
    assert all(s['minimum_pitch']<s['pitch_before']*.95 for s in ups)
    assert all(s['maximum_pitch']>s['pitch_before']*1.02 for s in downs)
    report={'passed':True,'audio_source':'Real Engine bus through AudioEffectCapture; preview is resampled and gain-normalized only','duration_s':len(mono)/rate,'sample_rate':rate,'rms':rms,'peak':peak,'preview_gain_db':20*math.log10(gain),'shifts':shifts}
    (ROOT/'docs/powertrain_audio_validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('Engine audio verified:',len(ups),'RPM drops,',len(downs),'rev-matching blips,',round(report['duration_s'],2),'seconds, peak',round(peak,4))

if __name__=='__main__':main()
