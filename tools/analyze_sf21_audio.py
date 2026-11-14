"""Measure real Godot bus captures and produce RMS-matched A/B listening copies.

No EQ, pitch modification, denoising or compression is applied to the previews.
The original stereo captures remain alongside them for independent inspection.
"""
from pathlib import Path
import argparse
import json
import math
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefix", choices=["sf21", "sf21r"], default="sf21")
    prefix = parser.parse_args().prefix
    results = []
    for mode in ['A', 'B']:
        path = ROOT / f'docs/evidence/{prefix}_audio_{mode}.wav'
        with wave.open(str(path), 'rb') as stream:
            rate = stream.getframerate()
            assert stream.getsampwidth() == 2
            samples = np.frombuffer(stream.readframes(stream.getnframes()), dtype='<i2')
            samples = samples.reshape(-1, stream.getnchannels()).astype(float) / 32768
        mono = samples.mean(axis=1)
        rms = float(np.sqrt(np.mean(mono**2)))
        peak = float(np.max(np.abs(samples)))
        assert rms > .001 and peak < .95
        gain = min(.08 / rms, .55 / peak)
        new_rate = 22050
        at = np.arange(round(len(mono) / rate * new_rate)) * rate / new_rate
        preview = np.interp(at, np.arange(len(mono)), mono) * gain
        with wave.open(str(ROOT / f'docs/evidence/{prefix}_audio_{mode}_matched.wav'), 'wb') as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(new_rate)
            output.writeframes(np.rint(preview * 32767).astype('<i2').tobytes())
        stages = {}
        for name, first, last in [('idle', 0, 1), ('accel', 7, 8), ('top', 19, 20), ('lift', 22, 23), ('brake', 25, 26)]:
            window = mono[int(first*rate):int(last*rate)]
            stages[name] = float(np.sqrt(np.mean(window**2)))
        results.append({'mode': mode, 'duration_s': len(mono)/rate, 'rms': rms, 'peak': peak,
                        'preview_gain_db': 20*math.log10(gain), 'preview_rms': float(np.sqrt(np.mean(preview**2))),
                        'stage_rms': stages})
    difference = 20*math.log10(results[1]['rms']/results[0]['rms'])
    assert abs(results[0]['preview_rms']-results[1]['preview_rms']) < .001
    report = {'passed': True, 'source': 'Actual Master bus captures of the unchanged physical controller; music absent',
              'raw_B_minus_A_rms_db': difference, 'previews': '22.05 kHz mono, gain-only RMS matching to 0.08; these gains are NOT game defaults',
              'samples': results}
    (ROOT / f'docs/{prefix}_audio_analysis.json').write_bytes((json.dumps(report, indent=2)+'\n').encode('utf8'))
    print('Audio A/B measured; matched previews ready; raw B-A:', round(difference, 2), 'dB')


if __name__ == '__main__':
    main()
