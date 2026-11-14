"""Original combustion placeholders, not recordings of a particular automobile.

Pulsed exhaust excitation, resonances and load-dependent noise replace pure tones.
Each file is periodic, deterministic and normalized to a specified RMS/headroom.
RPM reference banks allow high revs without pitching one recording indefinitely.
"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RATE = 22050
COUNT = RATE * 4


def build(name, rpm, grit, brightness, rms, seed):
    rng = np.random.default_rng(seed)
    firing_hz = rpm / 30  # Generic four-stroke, two firing events/revolution.
    excitation = np.zeros(COUNT)
    pattern = [1.0, .82, 1.13, .91, 1.06, .76, 1.17, .95]
    for event in range(round(4 * firing_hz)):
        position = round((event + rng.uniform(-.012, .012)) * RATE / firing_hz) % COUNT
        excitation[position] = pattern[event % len(pattern)] * rng.uniform(.9, 1.1)
    t = np.arange(COUNT) / RATE
    # Broad, short combustion transients excite low exhaust resonances.
    impulse = (np.sin(2*np.pi*115*t)*np.exp(-t/.009)
               + .5*np.sin(2*np.pi*235*t)*np.exp(-t/.005)
               + .18*np.sin(2*np.pi*510*t)*np.exp(-t/.0025))
    impulse += rng.normal(size=COUNT) * np.exp(-t/.0018) * .65
    pulse = np.fft.irfft(np.fft.rfft(excitation)*np.fft.rfft(impulse), n=COUNT)
    envelope = np.fft.irfft(np.fft.rfft(excitation)*np.fft.rfft(np.exp(-t/.004)), n=COUNT)
    envelope = np.maximum(envelope, 0)
    noise = rng.normal(size=COUNT)
    signal = pulse + grit*noise*(.10 + envelope)
    frequency = np.fft.rfftfreq(COUNT, 1/RATE)
    safe = np.maximum(frequency, 1)
    spectrum = np.fft.rfft(signal)
    spectrum *= (safe/(safe+35))**2 / np.sqrt(1+(safe/brightness)**6)
    spectrum[0] = 0
    signal = np.fft.irfft(spectrum, n=COUNT)
    if grit > .3:
        # Compress the pulse crest acoustically so the high bank does not thin out.
        signal = np.tanh(signal / np.sqrt(np.mean(signal**2)) * .85)
    signal -= np.mean(signal)
    signal *= min(rms/np.sqrt(np.mean(signal**2)), .85/np.max(np.abs(signal)))
    destination = ROOT / f'assets/audio/{name}.wav'
    with wave.open(str(destination), 'wb') as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(RATE)
        stream.writeframes(np.rint(signal*32767).astype('<i2').tobytes())
    return {'file': destination.name, 'reference_rpm': rpm,
            'rms': float(np.sqrt(np.mean(signal**2))), 'peak': float(np.max(np.abs(signal)))}


def main():
    results = [build('engine_combustion_coast', 3000, .12, 1800, .21, 3101),
               build('engine_combustion_load_low', 3000, .65, 2800, .25, 3102),
               build('engine_combustion_load_high', 6000, 1.4, 4200, .25, 3103),
               build('engine_combustion_body', 3000, .10, 750, .20, 3104)]
    (ROOT/'docs/combustion_sources.json').write_bytes((json.dumps(results, indent=2)+'\n').encode('utf8'))
    print(json.dumps(results))


if __name__ == '__main__':
    main()
