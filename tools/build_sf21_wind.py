"""Original deterministic, periodic wind placeholder. No recorded/licensed samples.

Run from any directory; requires NumPy, as existing audio analysis tools do.
The FFT creates a periodic noise loop, without a splice or a timed whoosh cue.
"""
from pathlib import Path
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def main():
    rate = 22050
    count = rate * 2
    rng = np.random.default_rng(2101)
    frequencies = np.fft.rfftfreq(count, 1 / rate)
    safe = np.maximum(frequencies, 1)
    spectrum = rng.normal(size=len(safe)) + 1j * rng.normal(size=len(safe))
    spectrum *= (safe / (safe + 50)) ** 2 / np.sqrt(safe)
    spectrum *= 1 / (1 + (safe / 2000) ** 4)
    spectrum[0] = 0
    spectrum[-1] = 0
    samples = np.fft.irfft(spectrum, n=count)
    samples *= min(0.16 / np.sqrt(np.mean(samples**2)), 0.65 / np.max(np.abs(samples)))
    path = ROOT / 'assets/audio/sf21_wind_placeholder.wav'
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(np.rint(samples * 32767).astype('<i2').tobytes())
    print('Original wind placeholder:', path.name, 'RMS', float(np.sqrt(np.mean(samples**2))))


if __name__ == '__main__':
    main()
