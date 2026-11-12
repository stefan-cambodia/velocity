#!/usr/bin/env python3
"""
Procedural audio generator for VELOCITY: Anti-Gravity League.

Everything is synthesised from code (numpy only, the ffmpeg CLI for Vorbis encoding): no samples,
no downloaded material; every melody, bassline, drum pattern and chord progression is original.

    python3 tools/gen_audio.py                  # everything
    python3 tools/gen_audio.py --only engine    # engine / motion loops  -> assets/audio/engine/*.wav
    python3 tools/gen_audio.py --only sfx       # one-shots              -> assets/audio/sfx/*.wav
    python3 tools/gen_audio.py --only music     # music                  -> assets/audio/music/*.ogg
    python3 tools/gen_audio.py --check          # verify every output (format, length, levels, loop seams)

WAVs are 16-bit mono 32 kHz; music is OGG Vorbis stereo 44.1 kHz.  Output is deterministic:
every sound draws from its own RNG seeded from its name.  Loops are built in circular buffers
(whole-cycle oscillators, circular FFT filters, events / delays / reverb tails wrapped round the
end), so they are seamless by construction; the music loops additionally share one sample grid
so main / intense pairs can be crossfaded in sync.

Layout of this file
    1. core DSP helpers          5. music toolkit (drums, voices, harmony)
    2. oscillators / SFX voices  6. sequencer, arranger, mixer, mastering
    3. engine & motion loops     7. songs
    4. one-shot SFX              8. verification   9. main
"""
import argparse
import os
import subprocess
import sys
import time
import wave
import zlib

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")
SR = 32000        # engine loops / sfx
MSR = 44100       # music
TAU = 2.0 * np.pi


# =====================================================================================
# 1. Core DSP helpers
# =====================================================================================

def rng_for(name):
    """Deterministic RNG per sound name."""
    return np.random.default_rng(zlib.crc32(name.encode("utf-8")))


def db(x):
    return 10.0 ** (x / 20.0)


def to_db(x):
    return 20.0 * np.log10(max(float(x), 1e-12))


def rms(x):
    return float(np.sqrt(np.mean(np.square(x)))) + 1e-12


# ---- magnitude responses (functions of a frequency array) ---------------------------------

def m_lp(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def m_hp(f, fc, order=2):
    r = (f / fc) ** (2 * order)
    return np.sqrt(r / (1.0 + r))


def m_bp(f, lo, hi, order=2):
    return m_hp(f, lo, order) * m_lp(f, hi, order)


def m_reson(f, fc, q):
    """Band-pass resonance, peak gain 1 at fc."""
    x = f / fc
    return (x / q) / np.sqrt((1.0 - x * x) ** 2 + (x / q) ** 2 + 1e-18)


def m_shelf(f, fc, gain_db, high=True):
    g = db(gain_db)
    r = (f / fc) ** 2
    w = r / (1.0 + r) if high else 1.0 / (1.0 + r)
    return 1.0 + (g - 1.0) * w


def _minphase(mag, n):
    """Minimum-phase rfft response with the given magnitude (cepstral folding)."""
    lm = np.log(np.maximum(mag, 1e-3))      # deeper floors alias in the cepstrum (smeared tails)
    c = np.fft.irfft(lm, n)
    half = n // 2
    c[1:half] *= 2.0
    c[half + 1:] = 0.0
    return np.exp(np.fft.rfft(c, n))


def fft_filter(x, sr, mag_fn, minphase=False):
    """Circular FFT filter along the last axis (seamless for loops)."""
    n = x.shape[-1]
    f = np.fft.rfftfreq(n, 1.0 / sr)
    h = mag_fn(f) * np.ones_like(f)
    if minphase:
        h = _minphase(h, n)
    spec = np.fft.rfft(x, axis=-1)
    if spec.dtype == np.complex64:          # float32 input stays float32 (music buses)
        h = h.astype(np.complex64 if np.iscomplexobj(h) else np.float32)
    return np.fft.irfft(spec * h, n, axis=-1)


def fast_len(m):
    """Smallest 5-smooth even length >= m (FFT friendly)."""
    best = None
    p2 = 2
    while p2 < 2 * m:
        p3 = p2
        while p3 < 2 * m:
            p5 = p3
            while p5 < 2 * m:
                if p5 >= m and (best is None or p5 < best):
                    best = p5
                p5 *= 5
            p3 *= 3
        p2 *= 2
    return best


def filt(x, sr, mag_fn, tail=0.06):
    """Causal (minimum-phase) filter for one-shots; zero padded so nothing wraps."""
    n = x.shape[-1]
    m = fast_len(n + int(sr * tail))
    xp = np.zeros(x.shape[:-1] + (m,))
    xp[..., :n] = x
    return fft_filter(xp, sr, mag_fn, minphase=True)[..., :n]


def noise_shaped(n, sr, r, mag_fn, ch=None):
    """Filtered white noise, circular (loops seamlessly), unit RMS."""
    n2 = n + (n % 2)
    shape = (n2,) if ch is None else (ch, n2)
    y = fft_filter(r.standard_normal(shape), sr, mag_fn)[..., :n]
    return y / (np.sqrt(np.mean(y * y, axis=-1, keepdims=True)) + 1e-12)


def loop_lfo(n, r, kmax, kmin=1, power=0.5):
    """Smooth random periodic function (loop harmonics kmin..kmax), zero mean, std 1."""
    t = np.arange(n) / float(n)
    out = np.zeros(n)
    for k in range(kmin, kmax + 1):
        out += r.standard_normal() / k ** power * np.sin(TAU * (k * t + r.random()))
    return out / (np.std(out) + 1e-12)


def ragged(n, sr, r, rate_hz, power=1.0):
    """Irregular positive envelope (mean 1) fluctuating at about rate_hz; circular."""
    e = np.abs(noise_shaped(n, sr, r, lambda f: m_lp(f, rate_hz, 2))) ** power
    e = fft_filter(e, sr, lambda f: m_lp(f, rate_hz * 2.5, 2))
    e = np.maximum(e, 0.0)
    return e / (np.mean(e) + 1e-12)


def add_circ(buf, i0, sig, gain=1.0):
    """Add sig into buf at i0 with wrap-around (last axis)."""
    n = buf.shape[-1]
    length = sig.shape[-1]
    i0 = int(i0) % n
    pos = 0
    while pos < length:
        k = min(n - i0, length - pos)
        buf[..., i0:i0 + k] += gain * sig[..., pos:pos + k]
        pos += k
        i0 = 0


def add_at(buf, i0, sig, gain=1.0):
    """Add sig into buf at i0, truncating at the end."""
    n = buf.shape[-1]
    i0 = int(i0)
    if i0 >= n or i0 < 0:
        return
    k = min(n - i0, sig.shape[-1])
    buf[..., i0:i0 + k] += gain * sig[..., :k]


def pan_st(sig, pan):
    """Mono -> stereo (2, n), constant power, pan in [-1, 1]."""
    a = (np.clip(pan, -1, 1) + 1.0) * np.pi / 4.0
    return np.stack([np.cos(a) * sig, np.sin(a) * sig])


def stft_shape(x, sr, gain_fn, win=1024):
    """Time-varying spectral shaping of a one-shot: gain_fn(t[:,None], f[None,:]) -> gains."""
    hop = win // 4
    n = len(x)
    xp = np.concatenate([np.zeros(win), x, np.zeros(win)])
    xp = np.concatenate([xp, np.zeros((-(len(xp) - win)) % hop)])
    nfr = 1 + (len(xp) - win) // hop
    w = 0.5 - 0.5 * np.cos(TAU * np.arange(win) / win)
    idx = np.arange(win)[None, :] + hop * np.arange(nfr)[:, None]
    spec = np.fft.rfft(xp[idx] * w, axis=1)
    tc = (np.arange(nfr) * hop + win / 2.0 - win) / sr
    f = np.fft.rfftfreq(win, 1.0 / sr)
    spec *= gain_fn(tc[:, None], f[None, :])
    y = np.fft.irfft(spec, win, axis=1) * w
    out = np.zeros(len(xp))
    for k in range(nfr):
        out[k * hop:k * hop + win] += y[k]
    return out[win:win + n] / 1.5


def env_ad(n, sr, attack, tau):
    """Linear attack then exponential decay."""
    t = np.arange(n) / sr
    return np.minimum(t / max(attack, 1e-6), 1.0) * np.exp(-np.maximum(t - attack, 0) / tau)


def adsr(n, sr, a, d, s, r):
    """ADSR over n samples; the release occupies the last r seconds."""
    t = np.arange(n) / sr
    dur = n / sr
    e = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    rel = np.clip((dur - t) / max(r, 1e-6), 0.0, 1.0)
    return e * rel


def fade(x, sr, fin=0.002, fout=0.01):
    x = x.copy()
    n = x.shape[-1]
    a = min(int(sr * fin), n // 2)
    b = min(int(sr * fout), n // 2)
    if a > 0:
        x[..., :a] *= np.linspace(0, 1, a)
    if b > 0:
        x[..., -b:] *= np.linspace(1, 0, b) ** 2
    return x


def softclip(x, thr=0.8, ceil=0.97):
    """Memoryless soft limiter: linear below thr, tanh knee approaching ceil."""
    a = np.abs(x)
    over = np.maximum(a - thr, 0.0)
    y = np.where(a > thr, thr + (ceil - thr) * np.tanh(over / (ceil - thr)), a)
    return np.sign(x) * y


def norm_loop(x, rms_db=-16.0, peak_db=-1.2):
    """RMS-normalise a loop; peaks tamed with a memoryless soft clip (seam safe)."""
    x = x - np.mean(x, axis=-1, keepdims=True)
    ceil = db(peak_db)
    for _ in range(4):
        x = x * (db(rms_db) / rms(x))
        if np.max(np.abs(x)) > ceil:
            x = softclip(x, thr=ceil * 0.72, ceil=ceil)
    return x


def one_shot(x, peak_db=-3.0, fout=0.012, hp=30.0, sr=SR):
    """Finish a one-shot: rumble / DC removal, fades, peak normalise."""
    x = filt(x, sr, lambda f: m_hp(f, hp, 2), tail=0.25)
    x = fade(x - np.mean(x), sr, 0.0005, fout)
    return x * (db(peak_db) / (np.max(np.abs(x)) + 1e-12))


def make_ir(sr, rt60, r, lo=250.0, hi=5500.0, predelay=0.012, ch=2):
    """Synthetic reverb impulse response: decaying noise, darker tail, sparse early taps."""
    n = int(sr * rt60 * 1.3)
    n += n % 2
    t = np.arange(n) / sr
    ir = r.standard_normal((ch, n)) * np.exp(-6.91 * t / rt60)
    dark = fft_filter(ir, sr, lambda f: m_bp(f, lo, hi * 0.35, 1))
    bright = fft_filter(ir, sr, lambda f: m_bp(f, lo, hi, 1))
    mixw = np.exp(-t / (rt60 * 0.25))
    ir = bright * mixw + dark * (1 - mixw) * 1.6
    ir *= np.minimum(t / 0.004, 1.0)
    for c in range(ch):
        for _ in range(7):
            k = int(sr * r.uniform(0.003, 0.045))
            ir[c, k] += r.choice([-1, 1]) * r.uniform(2, 5) * np.std(ir[c, :2000])
    pd = int(sr * predelay)
    ir = np.concatenate([np.zeros((ch, pd)), ir], axis=1)
    ir /= np.sqrt(np.sum(ir * ir, axis=1, keepdims=True))
    return ir


def convolve(x, ir, circular=False):
    """FFT convolution of (ch, n) or (n,) with a matching-channel ir."""
    n = x.shape[-1]
    k = ir.shape[-1]
    if circular:
        irw = np.zeros(ir.shape[:-1] + (n,))
        add_circ(irw, 0, ir)
        return np.fft.irfft(np.fft.rfft(x, axis=-1) * np.fft.rfft(irw, axis=-1), n, axis=-1)
    m = fast_len(n + k)
    return np.fft.irfft(np.fft.rfft(x, m, axis=-1) * np.fft.rfft(ir, m, axis=-1), m, axis=-1)[..., :n]


# ---- writers -------------------------------------------------------------------------------

def _stats(x):
    return "peak %6.2f dBFS  rms %6.2f dBFS" % (to_db(np.max(np.abs(x))), to_db(rms(x)))


def write_wav(rel, x, sr=SR):
    """x: (n,) float in [-1, 1] -> 16-bit PCM mono WAV."""
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    assert np.max(np.abs(x)) < 1.0, "clipping in %s" % rel
    pcm = np.round(x * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    print("  %-30s %6.3f s  %s" % (rel, x.shape[-1] / sr, _stats(x)), flush=True)


def write_ogg(rel, x, sr=MSR, quality=5):
    """x: (2, n) float -> OGG Vorbis via ffmpeg (bit-exact flags for reproducibility)."""
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    assert np.max(np.abs(x)) < 1.0, "clipping in %s" % rel
    raw = np.ascontiguousarray(x.T.astype("<f4")).tobytes()
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(sr), "-ac", "2", "-i", "pipe:0",
           "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
           "-c:a", "libvorbis", "-q:a", str(quality), path]
    subprocess.run(cmd, input=raw, check=True)
    return "  %-30s %7.3f s  %s  %d kB" % (rel, x.shape[-1] / sr, _stats(x), os.path.getsize(path) // 1024)


# =====================================================================================
# 2. Oscillators and shared voices
# =====================================================================================

def osc(f, n, sr=SR, wave="saw", cutoff=None, res=0.0, order=2, hmax=160, phase=0.0, pw=0.5):
    """Band-limited additive oscillator.  f: Hz (scalar or per-sample array, e.g. glides / vibrato).
    cutoff: None, Hz scalar or per-sample array -> low-pass applied per harmonic (order 2 = 12 dB/oct,
    4 = 24 dB/oct) with an optional resonant bump.  Harmonics come from the Chebyshev recurrence
    sin((h+1)p) = 2 cos(p) sin(hp) - sin((h-1)p), so only one sin/cos per sample is evaluated."""
    f = np.asarray(f, dtype=float)
    if f.ndim == 0:
        ph = TAU * float(f) * np.arange(n) / sr + phase
        fmax = float(f)
    else:
        ph = TAU * np.cumsum(f) / sr + phase
        fmax = float(np.max(f))
    if wave == "sine":
        return np.sin(ph)
    top = 0.45 * sr
    if cutoff is not None:
        top = min(top, 7.0 * float(np.max(cutoff)))
    hn = max(1, int(min(hmax, top // max(fmax, 1e-3))))
    s0 = np.zeros(n)
    s1 = np.sin(ph)
    c2 = 2.0 * np.cos(ph)
    out = np.zeros(n)
    rr = None
    if cutoff is not None:
        rr = f / np.asarray(cutoff, dtype=float)
        if res:
            lr = np.log2(np.maximum(rr, 1e-9))
            lmin, lmax = float(np.min(lr)), float(np.max(lr))
    for h in range(1, hn + 1):
        if wave == "saw":
            a = 1.0 / h
        elif wave == "square":
            a = 1.0 / h if h % 2 else 0.0
        elif wave == "pulse":
            a = np.sin(np.pi * h * pw) / h
        else:                                   # triangle
            a = ((1.0 if (h // 2) % 2 == 0 else -1.0) / (h * h)) if h % 2 else 0.0
        if a != 0.0:
            if rr is None:
                out += a * s1
            else:
                x2 = (h * rr) ** 2
                x4 = x2 * x2
                g = 1.0 / np.sqrt(1.0 + (x4 if order == 2 else x4 * x4))
                if res:
                    lh = np.log2(h)
                    if lh + lmin < 1.3 and lh + lmax > -1.3:
                        g = g * (1.0 + res * np.exp(-0.5 * ((lh + lr) / 0.3) ** 2))
                out += a * g * s1
        s0, s1 = s1, c2 * s1 - s0
    return out


def midi_f(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


_NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def nn(name):
    """'F#5' / 'Bb3' -> MIDI number (C4 = 60)."""
    pc = _NOTE[name[0]]
    rest = name[1:]
    while rest and rest[0] in "#b":
        pc += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + pc


def nf(name):
    return midi_f(nn(name))


def fm(freq, dur, ratio=2.0, idx=1.5, tau=0.2, itau=None, attack=0.002, sr=SR):
    """Two-operator FM tone (bells, blips, plucks); index limited to keep sidebands below Nyquist."""
    n = int(sr * dur)
    t = np.arange(n) / sr
    idx = min(idx, max(0.0, (0.44 * sr / freq - 1.0) / ratio - 1.0))
    i_env = idx * np.exp(-t / (itau if itau else tau * 0.5))
    y = np.sin(TAU * freq * t + i_env * np.sin(TAU * freq * ratio * t))
    return y * np.minimum(t / attack, 1.0) * np.exp(-t / tau)


def brass(freq, dur, sr=SR, bright=1.0):
    """Two detuned saws with a brassy filter swell."""
    n = int(round(sr * dur))
    t = np.arange(n) / sr
    cutoff = 450.0 + 3300.0 * bright * (1.0 - np.exp(-t / 0.03)) * (0.6 + 0.4 * np.exp(-t / 0.3))
    vib = freq * (1.0 + 0.004 * np.sin(TAU * 5.5 * t) * np.clip((t - 0.15) / 0.12, 0, 1))
    y = osc(vib * 1.003, n, sr, "saw", cutoff, res=0.2, hmax=60)
    y += osc(vib * 0.997, n, sr, "saw", cutoff, phase=1.3, hmax=60)
    return y * adsr(n, sr, 0.012, 0.15, 0.8, min(0.06, dur * 0.3))


def sweep_tone(dur, pts, harm=((1, 1.0),), sr=SR, shape=0.6):
    """Tone following a (fraction, Hz) breakpoint curve with a smooth swell envelope."""
    n = max(int(sr * dur), 8)
    x = np.arange(n) / float(n)
    f = np.exp(np.interp(x, [p[0] for p in pts], np.log([p[1] for p in pts])))
    ph = TAU * np.cumsum(f) / sr
    y = sum(a * np.sin(h * ph) for h, a in harm)
    edge = np.clip(np.minimum(x, 1.0 - x) * n / (0.003 * sr), 0.0, 1.0)
    return y * np.sin(np.pi * x) ** shape * (0.5 - 0.5 * np.cos(np.pi * edge))


def glide(dur, pts, wave="saw", cutoff=None, res=0.0, hmax=64, sr=SR):
    """Band-limited oscillator following a (fraction, Hz) breakpoint curve."""
    n = int(sr * dur)
    x = np.arange(n) / float(n)
    f = np.exp(np.interp(x, [p[0] for p in pts], np.log([p[1] for p in pts])))
    return osc(f, n, sr, wave, cutoff, res, hmax=hmax)


def grains(n, sr, r, rate, f_lo, f_hi, ms_lo, ms_hi, amp_pow=2.0, wobble=0.35, circ=True):
    """Many tiny narrow-band noise bursts (sparks, grit, debris) scattered round the buffer."""
    buf = np.zeros(n)
    for _ in range(max(1, int(rate * n / sr))):
        m = max(4, int(sr * r.uniform(ms_lo, ms_hi) / 1000.0))
        t = np.arange(m) / sr
        fc = np.exp(r.uniform(np.log(f_lo), np.log(f_hi)))
        ph = TAU * fc * t + wobble * np.cumsum(r.standard_normal(m))
        sig = np.sin(ph + r.uniform(0, TAU)) * np.exp(-t / (m / sr / 4.5)) * np.minimum(t * sr / 4.0, 1.0)
        (add_circ if circ else add_at)(buf, r.integers(n), sig, r.random() ** amp_pow)
    return buf / rms(buf)


# =====================================================================================
# 3. Engine & motion loops (mono 32 kHz).  Every tonal partial is snapped to a whole number
#    of cycles per loop, phase modulation uses periodic LFOs, noise is circularly filtered
#    and events wrap round the end - so each loop is seamless by construction.
# =====================================================================================

def lsin(n, freq, phase=0.0, pm=0.0):
    """Sine snapped to a whole number of cycles over n samples; pm: periodic phase modulation."""
    k = max(1, int(round(freq * n / SR)))
    return np.sin(TAU * k * np.arange(n) / n + phase + pm)


def spark_crackle(n, r, rate, burst_hz=6.0):
    """Clustered spark clicks (circular), unit RMS."""
    buf = np.zeros(n)
    for _ in range(int(rate * n / SR)):
        m = max(4, int(SR * r.uniform(0.0003, 0.0025)))
        tt = np.arange(m) / SR
        add_circ(buf, r.integers(n), r.standard_normal(m) * np.exp(-tt / (m / SR / 3.0)), r.random() ** 2)
    buf *= ragged(n, SR, r, burst_hz, 2.5)
    buf = fft_filter(buf, SR, lambda f: m_hp(f, 2200, 2) * m_lp(f, 11000, 1))
    return buf / rms(buf)


def eng_low(n, r):
    """Deep flux-turbine hum: 55 Hz harmonic stack, detuned twins beating at 0.5-1.5 Hz,
    band noise breathing at the fundamental, sub rumble, gentle saturation."""
    pm = 0.8 * loop_lfo(n, r, 3)
    f0 = 55.0
    y = np.zeros(n)
    for h in range(1, 90):
        fh = f0 * h
        if fh > 4500.0:
            break
        a = h ** -1.1 * (0.3 + 1.5 * m_reson(fh, 110.0, 1.2) + 0.9 * m_reson(fh, 385.0, 1.6)
                         + 0.45 * m_reson(fh, 990.0, 2.0)) * m_lp(fh, 2000.0, 1)
        y += a * lsin(n, fh, r.uniform(0, TAU), h * pm)
        if h <= 18:
            y += 0.5 * a * lsin(n, fh + 0.5 * (1 + h % 3), r.uniform(0, TAU), h * pm)
    y /= rms(y)
    flux = noise_shaped(n, SR, r, lambda f: m_bp(f, 120, 1500, 1) * (1 + m_reson(f, 440, 2)))
    flux *= 1.0 + 0.8 * lsin(n, f0, 0.5, pm)
    rumble = noise_shaped(n, SR, r, lambda f: m_bp(f, 25, 110, 2)) * np.exp(0.3 * loop_lfo(n, r, 4))
    y = y + 0.18 * flux + 0.25 * rumble
    y = np.tanh(1.3 * y / np.max(np.abs(y)))
    y *= 1.0 + 0.05 * lsin(n, 1.0, 1.0)
    return fft_filter(y, SR, lambda f: m_hp(f, 28, 2) * m_lp(f, 5500, 2))


def eng_mid(n, r):
    """Turbine / jet whine: strong 220-660 Hz partials, compressor whine with shimmer,
    rotor amplitude modulation at 27.5 Hz, band-limited jet noise."""
    pm = 0.5 * loop_lfo(n, r, 4)
    parts = ((110, 0.22), (220, 0.8), (330, 1.0), (440, 0.7), (550, 0.5), (660, 0.8), (770, 0.28),
             (880, 0.3), (990, 0.16), (1100, 0.1), (1320, 0.12), (1650, 0.06))
    y = np.zeros(n)
    for f, a in parts:
        h = f / 110.0
        y += a * lsin(n, f, r.uniform(0, TAU), h * pm)
        if f in (220, 330, 660):
            y += 0.4 * a * lsin(n, f + 1.0, r.uniform(0, TAU), h * pm)
    vib = 1.6 * np.sin(TAU * 6 * np.arange(n) / n + 0.4)
    whine = lsin(n, 587.5, 0.0, vib) + 0.45 * lsin(n, 1175.0, 1.0, 2 * vib) + 0.2 * lsin(n, 1762.5, 2.0, 3 * vib)
    y = y / rms(y) + 0.35 * whine / rms(whine)
    rotor = 1.0 + 0.13 * lsin(n, 27.5, 0.0) + 0.05 * lsin(n, 82.5, 1.3)
    jet = noise_shaped(n, SR, r, lambda f: m_bp(f, 250, 3500, 1) * (1 + 1.2 * m_reson(f, 750, 1.5) + 0.6 * m_reson(f, 1700, 2)))
    y = (y + 0.4 * jet) * rotor
    y = np.tanh(1.2 * y / np.max(np.abs(y)))
    return fft_filter(y, SR, lambda f: m_hp(f, 70, 2) * m_lp(f, 7000, 2))


def eng_high(n, r):
    """High plasma whistle (1.3-3.5 kHz partials with vibrato and a 6 Hz beat) + 1.2-4 kHz hiss."""
    t = np.arange(n) / n
    vib = 0.9 * np.sin(TAU * 10 * t) + 0.4 * loop_lfo(n, r, 3)
    whistle = (lsin(n, 1760.0, 0.0, vib) + 0.5 * lsin(n, 2640.0, 1.0, 1.5 * vib) + 0.3 * lsin(n, 1320.0, 2.0, 0.75 * vib)
               + 0.18 * lsin(n, 3520.0, 0.5, 2 * vib) + 0.25 * lsin(n, 1766.0, 0.3, vib))
    whistle *= 1.0 + 0.15 * loop_lfo(n, r, 5)
    hiss = noise_shaped(n, SR, r, lambda f: m_bp(f, 1200, 4000, 2) * (1 + 0.8 * m_reson(f, 1900, 2.5) + 0.6 * m_reson(f, 3100, 3)))
    hiss *= 0.7 + 0.3 * ragged(n, SR, r, 45, 1.3)
    sizzle = grains(n, SR, r, 90, 3500, 7500, 1, 4, amp_pow=3.0)
    y = 0.55 * whistle / rms(whistle) + hiss + 0.12 * sizzle
    return fft_filter(y, SR, lambda f: m_hp(f, 600, 2) * m_lp(f, 9000, 2))


def airbrake(n, r):
    """Turbulent air rush with 16 Hz flap buffet and 12 Hz low buffeting."""
    t = np.arange(n) / n
    secs = n / SR
    wob = 0.7 * loop_lfo(n, r, 4)
    flutter = 1.0 + 0.55 * np.sin(TAU * round(16 * secs) * t + wob)
    flutter2 = 1.0 + 0.35 * np.sin(TAU * round(12 * secs) * t + 1.7 + 0.5 * wob)
    rush = noise_shaped(n, SR, r, lambda f: m_bp(f, 220, 3800, 1) * (1 + 1.3 * m_reson(f, 650, 1.4) + 0.7 * m_reson(f, 1600, 1.8)))
    buffet = noise_shaped(n, SR, r, lambda f: m_bp(f, 40, 220, 2))
    hiss = noise_shaped(n, SR, r, lambda f: m_hp(f, 3500, 2) * m_lp(f, 9000, 2))
    gust = ragged(n, SR, r, 5, 0.8)
    return rush * flutter * (0.6 + 0.4 * gust) + 0.7 * buffet * flutter2 * flutter + 0.25 * hiss * flutter


def wind(n, r):
    """Broadband wind rush with slowly drifting resonant bands."""
    y = 0.9 * noise_shaped(n, SR, r, lambda f: m_hp(f, 45, 2) * m_lp(f, 220, 1) * m_lp(f, 4000, 1))
    for fc, q, lvl, depth in ((380, 1.0, 0.8, 0.3), (900, 1.3, 0.55, 0.45), (2100, 1.8, 0.32, 0.6),
                              (4300, 2.0, 0.16, 0.7), (7000, 1.5, 0.08, 0.6)):
        y += lvl * noise_shaped(n, SR, r, lambda f, fc=fc, q=q: m_reson(f, fc, q)) * np.exp(depth * loop_lfo(n, r, 6))
    return y * np.exp(0.15 * loop_lfo(n, r, 4))


def scrape(n, r):
    """Hull grinding along an energy barrier: resonant metal grind, stick-slip squeal, flickering
    100 Hz barrier hum, clustered spark crackle."""
    modes = [(r.uniform(700, 6500), r.uniform(6, 18)) for _ in range(9)]
    grind = noise_shaped(n, SR, r, lambda f: m_hp(f, 300, 2) * (0.25 + sum(m_reson(f, fc, q) for fc, q in modes)))
    grind *= 0.35 + ragged(n, SR, r, 30, 1.8)
    sq_pm = 3.0 * loop_lfo(n, r, 9)
    squeal = sum(a * lsin(n, fq, r.uniform(0, TAU), sq_pm * fq / 1300.0) for fq, a in ((1300.0, 1.0), (2610.0, 0.45), (3915.0, 0.2)))
    squeal *= np.clip(0.3 + 0.7 * loop_lfo(n, r, 6), 0.0, None)
    buzz = sum(lsin(n, 100.0 * h, r.uniform(0, TAU)) / h for h in range(1, 30, 2))
    buzz = fft_filter(buzz, SR, lambda f: m_lp(f, 2500, 1)) * (0.4 + 0.6 * ragged(n, SR, r, 18, 2.0))
    sparks = spark_crackle(n, r, 160)
    y = grind / rms(grind) + 0.35 * squeal / rms(squeal) + 0.3 * buzz / rms(buzz) + 0.6 * sparks
    return fft_filter(y, SR, lambda f: m_hp(f, 120, 2) * m_lp(f, 12000, 2))


def ai_engine(n, r):
    """Opponent ship: one combined, mid-heavy engine (110 Hz stack, whine, jet noise, rotor AM)."""
    pm = 0.5 * loop_lfo(n, r, 3)
    y = np.zeros(n)
    for h in range(1, 46):
        fh = 110.0 * h
        if fh > 5000:
            break
        a = h ** -0.8 * (0.25 + 1.2 * m_reson(fh, 440.0, 1.0) + 0.8 * m_reson(fh, 1100.0, 1.5))
        y += a * lsin(n, fh, r.uniform(0, TAU), h * pm)
    y /= rms(y)
    vib = 1.2 * np.sin(TAU * 4 * np.arange(n) / n)
    whine = lsin(n, 747.0, 0.0, vib) + 0.4 * lsin(n, 1494.0, 1.0, 2 * vib)
    jet = noise_shaped(n, SR, r, lambda f: m_bp(f, 400, 2500, 1) * (1 + m_reson(f, 900, 1.5)))
    rotor = 1.0 + 0.15 * lsin(n, 20.0, 0.0)
    y = (y + 0.35 * whine / rms(whine) + 0.45 * jet) * rotor
    y = np.tanh(1.3 * y / np.max(np.abs(y)))
    return fft_filter(y, SR, lambda f: m_hp(f, 150, 2) * (1 + 0.8 * m_reson(f, 900, 0.8)) * m_lp(f, 5000, 2))


def boost_loop(n, r):
    """Afterburner roar: turbulent low-mid noise, saturated 80 Hz thrust stack, flame pops, hiss."""
    roar = noise_shaped(n, SR, r, lambda f: m_hp(f, 40, 2) * m_lp(f, 2200, 1) * (1 + 1.4 * m_reson(f, 140, 1.2) + 0.9 * m_reson(f, 520, 1.5)))
    roar *= 0.55 + 0.45 * ragged(n, SR, r, 22, 1.4)
    pm = 0.5 * loop_lfo(n, r, 3)
    thrust = sum(lsin(n, 80.0 * h, r.uniform(0, TAU), h * pm) / h ** 0.9 for h in range(1, 40))
    thrust = np.tanh(1.5 * thrust / np.max(np.abs(thrust)))
    pops = grains(n, SR, r, 45, 250, 1600, 4, 18, amp_pow=2.5)
    hiss = noise_shaped(n, SR, r, lambda f: m_hp(f, 3000, 2) * m_lp(f, 10000, 2)) * ragged(n, SR, r, 30, 1.2)
    y = (roar + 0.45 * thrust / rms(thrust) + 0.35 * pops + 0.18 * hiss) * (1.0 + 0.2 * lsin(n, 30.0, 0.7))
    y = np.tanh(1.3 * y / np.max(np.abs(y)))
    return fft_filter(y, SR, lambda f: m_hp(f, 35, 2) * m_lp(f, 6500, 2))


LOOPS = [   # name, seconds, generator, RMS dBFS
    ("engine_low", 2.0, eng_low, -16.0),
    ("engine_mid", 2.0, eng_mid, -17.0),
    ("engine_high", 2.0, eng_high, -19.0),
    ("airbrake", 1.5, airbrake, -18.0),
    ("wind", 3.0, wind, -18.0),
    ("scrape", 1.5, scrape, -17.0),
    ("ai_engine", 1.5, ai_engine, -16.0),
    ("boost_loop", 1.5, boost_loop, -16.0),
]


def build_engine():
    print("engine / motion loops", flush=True)
    for name, secs, fn, lvl in LOOPS:
        n = int(round(secs * SR))
        y = fft_filter(fn(n, rng_for(name)), SR, lambda f: m_hp(f, 25, 2))
        write_wav("engine/%s.wav" % name, norm_loop(y, lvl, -1.2))


# =====================================================================================
# 4. One-shot SFX (mono 32 kHz)
# =====================================================================================

def _n(dur):
    return int(SR * dur)


def _t(n):
    return np.arange(n) / SR


def _nz(n, r, mag_fn):
    return noise_shaped(n + n % 2, SR, r, mag_fn)[:n]


def modal(parts, dur, r=None, attack=0.0005, glide_amt=0.0):
    """Sum of decaying partials: parts = [(Hz, amp, tau), ...]."""
    n = _n(dur)
    t = _t(n)
    y = np.zeros(n)
    for f, a, tau in parts:
        ph = r.uniform(0, TAU) if r is not None else 0.0
        fi = f * (1.0 + glide_amt * np.exp(-t / 0.015))
        y += a * np.sin(TAU * np.cumsum(fi) / SR + ph) * np.exp(-t / tau)
    return y * np.minimum(t / attack, 1.0)


def thump(f_end, f_start, tau_f, tau_a, dur=None):
    """Sine with falling pitch: the body of an impact."""
    n = _n(dur if dur else tau_a * 7)
    t = _t(n)
    f = f_end + (f_start - f_end) * np.exp(-t / tau_f)
    return np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t / tau_a) * np.minimum(t / 0.001, 1.0)


def layer(total, items):
    """items = [(time s, signal, gain)] -> mixed buffer of `total` seconds."""
    buf = np.zeros(_n(total))
    for t, sig, g in items:
        add_at(buf, int(t * SR), fade(sig, SR, 0.0, 0.004), g)     # no layer ends with a step
    return buf


def room(x, r, rt=0.5, wet=0.2):
    ir = make_ir(SR, rt, r, lo=300, hi=6000, ch=1)[0]
    return x + wet * convolve(x, ir)


def tick(r, f=2800.0):
    return modal([(f, 1.0, 0.005), (f * 1.47, 0.5, 0.003)], 0.03, r)


def sweep_noise(dur, r, pts, q=1.5, lowpass=False, win=512, band=(40.0, 12000.0)):
    """Noise through a resonant band-pass (or low-pass) following a (fraction, Hz) curve."""
    n = _n(dur)
    src = _nz(n, r, lambda f: m_bp(f, band[0], band[1], 1))
    fr = [p[0] for p in pts]
    lf = np.log([p[1] for p in pts])

    def g(tt, f):
        fc = np.exp(np.interp(np.clip(tt / dur, 0, 1), fr, lf))
        return m_lp(f, fc, 2) if lowpass else m_reson(f, fc, q)
    return stft_shape(src, SR, g, win=win)


def discharge(dur, r, tau, lo=1500.0, hi=9000.0, rate=250.0, hum=120.0):
    """Energy-barrier arc: gated crackling noise over a buzzing hum."""
    n = _n(dur)
    nz = _nz(n, r, lambda f: m_bp(f, lo, hi, 1))
    gate = ragged(n + n % 2, SR, r, rate, 2.5)[:n]
    gate = 2.5 * np.tanh(gate / 2.5)                                  # crackle, but no lone spikes
    buzz = osc(hum, n, SR, "square", cutoff=2500.0, hmax=25)
    return (nz * gate + 0.25 * buzz / rms(buzz)) * env_ad(n, SR, 0.001, tau)


# ---- impacts -----------------------------------------------------------------------------

def sfx_wall_hit_heavy(r):
    low = np.tanh(2.6 * thump(42.0, 150.0, 0.025, 0.16))
    n = _n(0.6)
    crunch = np.tanh(3.0 * _nz(n, r, lambda f: m_bp(f, 250, 6500, 1)) * env_ad(n, SR, 0.0008, 0.06))
    hull = modal([(r.uniform(160, 3600), r.uniform(0.3, 1.0), r.uniform(0.05, 0.35)) for _ in range(12)], 1.0, r)
    hull = filt(hull, SR, lambda f: m_lp(f, 4500, 1))
    ring = sweep_tone(0.3, ((0, 2600), (1, 300)), ((1, 1), (2, 0.4), (3, 0.25)), shape=0.15) * env_ad(_n(0.3), SR, 0.001, 0.07)
    y = layer(1.1, [(0, low, 1.0), (0, crunch, 0.55), (0.002, hull, 0.3), (0, discharge(0.35, r, 0.07), 0.35),
                    (0.004, ring, 0.15)])
    return room(y, r, 0.6, 0.18)


def sfx_wall_hit_light(r):
    low = thump(85.0, 190.0, 0.012, 0.045)
    ting = modal([(r.uniform(900, 4200), r.uniform(0.4, 1.0), r.uniform(0.02, 0.09)) for _ in range(6)], 0.3, r)
    n = _n(0.2)
    scuff = _nz(n, r, lambda f: m_bp(f, 800, 7000, 1)) * env_ad(n, SR, 0.0005, 0.018)
    y = layer(0.45, [(0, low, 0.8), (0, ting, 0.35), (0, scuff, 0.5), (0.003, discharge(0.14, r, 0.035), 0.35)])
    return room(y, r, 0.35, 0.12)


def sfx_ship_contact(r):
    low = np.tanh(1.6 * thump(95.0, 210.0, 0.012, 0.05))
    clank = modal([(r.uniform(600, 3500), r.uniform(0.4, 1.0), r.uniform(0.02, 0.06)) for _ in range(5)], 0.3, r)
    n = _n(0.16)
    scrape_ = _nz(n, r, lambda f: m_bp(f, 1000, 6000, 1)) * ragged(n, SR, r, 80, 1.5) * env_ad(n, SR, 0.003, 0.05)
    return layer(0.45, [(0, low, 1.0), (0.001, clank, 0.4), (0.01, scrape_, 0.45), (0.0, discharge(0.08, r, 0.02, hum=180.0), 0.2)])


def sfx_land(r):
    thud = np.tanh(1.6 * thump(38.0, 92.0, 0.05, 0.14))
    cushion = sweep_noise(0.4, r, ((0, 2600), (0.4, 700), (1, 250)), lowpass=True, band=(100.0, 3000.0))
    cushion *= env_ad(len(cushion), SR, 0.008, 0.11)
    clunk = modal([(210, 1, 0.05), (335, 0.6, 0.04), (720, 0.35, 0.03), (1530, 0.2, 0.015)], 0.3, r)
    n = _n(0.35)
    hum = np.sin(TAU * 110.0 * _t(n)) * (1 + 0.5 * np.sin(TAU * 22 * _t(n))) * env_ad(n, SR, 0.02, 0.09)
    return layer(0.7, [(0, thud, 1.0), (0, cushion, 0.6), (0.004, clunk, 0.3), (0.03, hum, 0.15)])


# ---- race events -------------------------------------------------------------------------

def sfx_boost(r):
    n = _n(1.1)
    t = _t(n)
    f = 140.0 * 2.0 ** (2.3 * (1.0 - np.exp(-t / 0.18)))
    cut = 600.0 + 5000.0 * (1.0 - np.exp(-t / 0.12))
    env = np.minimum(t / 0.01, 1.0) * np.exp(-t / 0.35)
    tone = (osc(f, n, SR, "saw", cut, res=0.4, hmax=60) + 0.6 * osc(f * 1.5 * 1.003, n, SR, "saw", cut, hmax=40)) * env
    whoosh = sweep_noise(1.1, r, ((0, 300), (0.35, 4500), (1, 2500)), q=1.3) * np.sin(np.pi * np.clip(t / 1.1, 0, 1)) ** 0.7
    shimmer = fm(1760.0, 0.6, 3.0, 1.0, 0.18) + 0.6 * fm(2637.0, 0.6, 3.0, 1.0, 0.15)
    return room(layer(1.1, [(0, tone, 0.5), (0, whoosh, 0.6), (0, thump(55.0, 160.0, 0.02, 0.09), 0.9),
                            (0.12, shimmer, 0.12)]), r, 0.5, 0.15)


def sfx_pad_weapon(r):
    items = []
    for i, f in enumerate((880.0, 1318.5, 1760.0, 2637.0)):
        items.append((0.045 * i, fm(f, 0.16, 2.0, 2.0, 0.05), 0.55))
        items.append((0.045 * i, osc(f / 2, _n(0.05), SR, "square", 3000.0, hmax=9) * env_ad(_n(0.05), SR, 0.001, 0.015), 0.15))
    lock = sweep_tone(0.09, ((0, 1200), (1, 2400)), ((1, 1), (3, 0.3)), shape=0.3)
    items += [(0.2, lock, 0.35), (0.29, fm(3520.0, 0.3, 1.5, 0.8, 0.12), 0.35)]
    return room(layer(0.65, items), r, 0.35, 0.15)


def _beep(freq, dur, rel, parts):
    n = _n(dur)
    t = _t(n)
    y = sum(a * np.sin(TAU * freq * m * t + m) for m, a in parts)
    return y * np.minimum(t / 0.003, 1.0) * np.clip((dur - t) / rel, 0, 1) ** 1.5


def sfx_beep_count(r):
    return _beep(880.0, 0.26, 0.07, ((1, 1.0), (2, 0.28), (3, 0.12), (0.5, 0.25)))


def sfx_beep_go(r):
    y = _beep(1760.0, 0.8, 0.35, ((1, 1.0), (0.5, 0.6), (1.5, 0.22), (2, 0.12), (0.25, 0.3)))
    return room(np.concatenate([y, np.zeros(_n(0.15))]), r, 0.45, 0.15)


def sfx_lap(r):
    a = fm(nf("E6"), 0.5, 2.0, 1.2, 0.16)
    b = fm(nf("B6"), 0.75, 2.0, 1.2, 0.3)
    n = _n(0.7)
    pad = sum(osc(nf(nm), n, SR, "saw", 1800.0, hmax=20) for nm in ("E5", "B5")) * adsr(n, SR, 0.03, 0.2, 0.5, 0.3)
    return room(layer(1.0, [(0, a, 0.7), (0.09, b, 0.9), (0.0, pad, 0.08), (0.09, fm(nf("E7"), 0.4, 3.0, 0.5, 0.12), 0.15)]), r, 0.6, 0.2)


def sfx_final_lap(r):
    items = []
    for i, nm in enumerate(("A5", "C#6", "E6")):
        items.append((0.08 * i, fm(nf(nm), 0.18, 2.0, 1.6, 0.07), 0.6))
    n = _n(0.95)
    t = _t(n)
    trem = 0.6 + 0.4 * np.sin(TAU * 10.0 * t)
    held = (osc(nf("A6"), n, SR, "square", 4000.0, hmax=7) + 0.7 * osc(nf("E6"), n, SR, "square", 4000.0, hmax=9))
    held *= trem * adsr(n, SR, 0.01, 0.3, 0.6, 0.35)
    hit = brass(nf("A3"), 0.5) + brass(nf("E4"), 0.5)
    items += [(0.24, held, 0.25), (0.24, hit, 0.3), (0.24, thump(55.0, 140.0, 0.02, 0.1), 0.6)]
    return room(layer(1.4, items), r, 0.6, 0.2)


def sfx_finish(r):
    items = []

    def chord(t0, dur, names, g=0.4, bright=1.0):
        for nm in names:
            items.append((t0, brass(nf(nm), dur, bright=bright), g))

    chord(0.0, 0.1, ["A4", "C#5", "E5"])
    chord(0.13, 0.1, ["B4", "D5", "F#5"])
    chord(0.26, 0.12, ["C#5", "E5", "G#5"])
    chord(0.42, 1.5, ["A4", "E5", "A5", "C#6"], 0.42, 1.3)
    items.append((0.42, brass(nf("A2"), 1.5), 0.45))
    for i, nm in enumerate(("A6", "C#7", "E7", "A7")):
        items.append((0.45 + 0.06 * i, fm(nf(nm), 0.9, 3.0, 1.0, 0.3), 0.18))
    for t0, f in ((0.0, 60.0), (0.42, 45.0)):
        items.append((t0, np.tanh(1.5 * thump(f, f * 2.6, 0.03, 0.18)), 0.8))
    m = _n(1.6)
    items.append((0.42, _nz(m, r, lambda f: m_hp(f, 3500, 2)) * env_ad(m, SR, 0.003, 0.4), 0.12))
    return room(layer(2.5, items), r, 1.1, 0.25)


def sfx_wrong_way(r):
    items = []
    for i in range(4):
        f = 740.0 if i % 2 == 0 else 587.3
        n = _n(0.17)
        tone = osc(f, n, SR, "square", 2600.0, hmax=15) + 0.5 * osc(f * 1.006, n, SR, "saw", 2600.0, hmax=15)
        items.append((0.2 * i, tone * adsr(n, SR, 0.004, 0.05, 0.85, 0.02), 0.5))
    return layer(0.95, items)


def sfx_eliminated(r):
    n = _n(2.1)
    t = _t(n)
    x = np.clip(t / 1.7, 0, 1)
    f = 520.0 * 2.0 ** (-4.0 * x ** 0.8)
    cut = 200.0 + 4800.0 * (1 - x) ** 2
    env = np.minimum(t / 0.01, 1.0) * np.clip((2.0 - t) / 0.4, 0, 1)
    down = (osc(f, n, SR, "saw", cut, res=0.5, hmax=80) + osc(f * 1.01, n, SR, "square", cut, hmax=60)) * env
    # digital failure: a short stutter of the power-down start
    k = _n(0.045)
    stut = np.zeros(n)
    for i in range(4):
        add_at(stut, _n(0.12) + i * k, down[_n(0.05):_n(0.05) + k] * np.hanning(k), 0.8 - 0.15 * i)
    blast = _nz(_n(0.5), r, lambda f_: m_bp(f_, 80, 6000, 1)) * env_ad(_n(0.5), SR, 0.002, 0.08)
    boom = np.tanh(2.0 * thump(36.0, 130.0, 0.04, 0.4))
    return room(layer(2.4, [(0, boom, 1.0), (0, blast, 0.5), (0.02, down, 0.35), (0.02, stut, 0.25)]), r, 1.0, 0.25)


def sfx_unlock(r):
    items = []
    for i, nm in enumerate(("D6", "E6", "F#6", "G#6", "A6", "C#7", "D7")):
        items.append((0.055 * i, fm(nf(nm), 0.5, 2.0, 1.2, 0.18), 0.45))
    for nm in ("D6", "F#6", "A6", "C#7"):
        items.append((0.42, fm(nf(nm), 1.1, 2.0, 1.0, 0.45), 0.35))
    n = _n(1.1)
    pad = sum(osc(nf(nm), n, SR, "saw", 2200.0, hmax=24) for nm in ("D5", "A5", "C#6")) * adsr(n, SR, 0.15, 0.3, 0.6, 0.5)
    items.append((0.35, pad, 0.06))
    for _ in range(14):
        items.append((r.uniform(0.3, 1.1), fm(r.uniform(3000, 6000), 0.25, 1.0, 0.0, r.uniform(0.04, 0.1)), r.uniform(0.04, 0.12)))
    return room(layer(1.7, items), r, 0.9, 0.25)


# ---- UI ----------------------------------------------------------------------------------

def sfx_ui_move(r):
    y = sweep_tone(0.045, ((0, 2300), (1, 1900)), ((1, 1), (2, 0.15)), shape=0.2) * env_ad(_n(0.045), SR, 0.0008, 0.012)
    return layer(0.06, [(0, y, 1.0), (0, tick(r, 4200.0), 0.15)])


def sfx_ui_select(r):
    return layer(0.24, [(0, fm(1046.5, 0.1, 2.0, 1.4, 0.035), 0.8), (0.06, fm(1568.0, 0.17, 2.0, 1.4, 0.06), 1.0),
                        (0.06, fm(3136.0, 0.1, 1.0, 0.0, 0.03), 0.15)])


def sfx_ui_back(r):
    return layer(0.22, [(0, fm(1318.5, 0.1, 2.0, 1.0, 0.035), 0.9), (0.06, fm(880.0, 0.15, 2.0, 1.0, 0.05), 0.85)])


def sfx_ui_error(r):
    n = _n(0.1)
    b = (osc(160.0, n, SR, "square", 1500.0, hmax=20) + osc(169.0, n, SR, "square", 1500.0, hmax=20)) * adsr(n, SR, 0.004, 0.05, 0.8, 0.02)
    return layer(0.28, [(0, b, 1.0), (0.14, b, 0.9)])


# ---- weapons -------------------------------------------------------------------------------

def sfx_explosion(r):
    n = _n(2.4)
    t = _t(n)
    boom = np.tanh(2.0 * thump(32.0, 110.0, 0.06, 0.45, dur=2.0))
    blast = _nz(n, r, lambda f: m_bp(f, 60, 9000, 1)) * env_ad(n, SR, 0.003, 0.35)
    blast = stft_shape(blast, SR, lambda tt, f: m_lp(f, 400.0 + 8600.0 * np.exp(-np.maximum(tt, 0) / 0.25), 2), win=512)
    sparks = grains(n, SR, r, 160, 1500, 8000, 1, 6, amp_pow=2.0, circ=False) * np.exp(-t / 0.35) * np.minimum(t / 0.01, 1)
    rumble = _nz(n, r, lambda f: m_bp(f, 30, 220, 2)) * np.minimum(t / 0.05, 1) * np.exp(-t / 0.8)
    items = [(0, boom, 1.0), (0, np.tanh(2.5 * blast), 0.7), (0, sparks, 0.08), (0, rumble, 0.5)]
    for _ in range(12):
        f = r.uniform(1500, 6000)
        t0 = 0.1 + 1.2 * r.random() ** 1.5
        items.append((t0, modal([(f, 1, r.uniform(0.01, 0.04)), (f * 1.53, 0.5, 0.01)], 0.15, r), 0.1 * np.exp(-t0 / 0.6)))
    return room(layer(2.4, items), r, 1.2, 0.25)


def sfx_shield_hit(r):
    parts = []
    for f, a, tau in ((1180, 1.0, 0.25), (1730, 0.8, 0.2), (2410, 0.6, 0.15), (3350, 0.45, 0.1), (4720, 0.3, 0.07)):
        parts += [(f, a, tau), (f + 7.0, 0.7 * a, tau * 0.9)]
    ting = modal(parts, 0.8, r)
    n = _n(0.4)
    t = _t(n)
    field = np.sin(TAU * 220.0 * t) * (0.5 + 0.5 * np.sin(TAU * 30.0 * t)) * env_ad(n, SR, 0.005, 0.12)
    return room(layer(0.8, [(0, ting, 0.4), (0, discharge(0.1, r, 0.025, lo=2000.0), 0.5),
                            (0, thump(110.0, 260.0, 0.01, 0.04), 0.5), (0, field, 0.3)]), r, 0.5, 0.2)


def sfx_plasma_fire(r):
    n = _n(0.42)
    t = _t(n)
    f = 260.0 + 2200.0 * np.exp(-t / 0.045)
    ph = TAU * np.cumsum(f) / SR + 1.5 * np.sin(TAU * 90.0 * t)
    tone = (np.sin(ph) + 0.45 * np.sin(2 * ph) + 0.2 * np.sin(3 * ph)) * env_ad(n, SR, 0.001, 0.09)
    m = _n(0.1)
    burst = _nz(m, r, lambda f_: m_bp(f_, 1000, 8000, 1)) * env_ad(m, SR, 0.0005, 0.02)
    return room(layer(0.45, [(0, tone, 0.8), (0, burst, 0.45), (0, thump(70.0, 180.0, 0.015, 0.05), 0.5)]), r, 0.3, 0.12)


def sfx_missile_launch(r):
    n = _n(1.4)
    t = _t(n)
    hiss = sweep_noise(1.4, r, ((0, 600), (0.5, 2500), (1, 1800)), q=0.9) * ragged(n + n % 2, SR, r, 35, 1.2)[:n]
    env = np.minimum(t / 0.05, 1.0) * np.clip((1.4 - t) / 0.9, 0, 1) ** 1.5
    roar = _nz(n, r, lambda f: m_bp(f, 60, 500, 1)) * env
    whine = glide(1.4, ((0, 300), (0.6, 900), (1, 820)), "saw", cutoff=2000.0, hmax=30) * env
    m = _n(0.2)
    pop = np.tanh(2.0 * (thump(60.0, 160.0, 0.015, 0.06, dur=0.2) + _nz(m, r, lambda f: m_bp(f, 300, 5000, 1)) * env_ad(m, SR, 0.0005, 0.02)))
    return room(layer(1.45, [(0, pop, 0.9), (0.02, hiss * env, 0.55), (0.02, roar, 0.45), (0.02, whine, 0.08)]), r, 0.6, 0.18)


def sfx_missile_hit(r):
    m = _n(0.06)
    crack = _nz(m, r, lambda f: m_hp(f, 1500, 2)) * env_ad(m, SR, 0.0002, 0.008)
    boom = np.tanh(2.2 * thump(40.0, 150.0, 0.03, 0.25))
    n = _n(0.9)
    blast = _nz(n, r, lambda f: m_bp(f, 100, 7000, 1)) * env_ad(n, SR, 0.002, 0.15)
    blast = stft_shape(blast, SR, lambda tt, f: m_lp(f, 500.0 + 6500.0 * np.exp(-np.maximum(tt, 0) / 0.12), 2), win=512)
    debris = modal([(r.uniform(700, 4500), r.uniform(0.3, 1.0), r.uniform(0.03, 0.15)) for _ in range(8)], 0.6, r)
    return room(layer(1.3, [(0, crack, 0.8), (0, boom, 1.0), (0, np.tanh(2.0 * blast), 0.6), (0.01, debris, 0.12)]), r, 0.9, 0.22)


def sfx_emp(r):
    n = _n(1.5)
    t = _t(n)
    charge = sweep_tone(0.25, ((0, 200), (1, 1600)), ((1, 1), (2, 0.3)), shape=1.5)
    f = 45.0 + 900.0 * np.exp(-t / 0.25)
    buzz = np.tanh(2.5 * osc(f, n, SR, "saw", 3000.0, hmax=60)) * env_ad(n, SR, 0.002, 0.45)
    crackle = _nz(n, r, lambda f_: m_bp(f_, 2000, 9000, 1)) * 2.5 * np.tanh(ragged(n, SR, r, 300, 2.5) / 2.5) * env_ad(n, SR, 0.002, 0.3)
    wob = np.sin(TAU * 60.0 * t) * (0.5 + 0.5 * np.sin(TAU * 8.0 * t)) * env_ad(n, SR, 0.01, 0.4)
    return room(layer(1.8, [(0, charge, 0.25), (0.25, thump(45.0, 130.0, 0.03, 0.2), 0.9), (0.25, buzz, 0.35),
                            (0.25, crackle, 0.4), (0.25, wob, 0.4)]), r, 0.8, 0.2)


def sfx_shockwave(r):
    n = _n(1.8)
    t = _t(n)
    pre = sweep_noise(0.18, r, ((0, 3000), (1, 600)), lowpass=True) * np.linspace(0, 1, _n(0.18)) ** 2
    boom = np.tanh(1.8 * thump(30.0, 120.0, 0.05, 0.5, dur=1.6))
    wave_ = sweep_noise(1.6, r, ((0, 150), (0.25, 5000), (1, 300)), lowpass=True, band=(40.0, 9000.0))
    wave_ *= env_ad(len(wave_), SR, 0.01, 0.4)
    k = len(wave_)
    d = (0.004 + 0.003 * np.sin(TAU * 0.8 * _t(k))) * SR       # sweeping comb: "phasey" pressure front
    idx = np.clip(np.arange(k) - d, 0, k - 1).astype(int)
    wave_ = wave_ + 0.7 * wave_[idx]
    whoomp = thump(32.0, 110.0, 0.12, 0.35, dur=1.0)
    return room(layer(2.0, [(0, pre, 0.3), (0.18, boom, 1.0), (0.18, wave_, 0.6), (0.18, whoomp, 0.6)]), r, 1.1, 0.25)


def sfx_mine_drop(r):
    clunk = modal([(140, 1, 0.08), (310, 0.7, 0.05), (590, 0.4, 0.03), (1230, 0.25, 0.02)], 0.35, r)
    items = [(0, clunk, 0.8), (0, thump(70.0, 160.0, 0.015, 0.05), 0.7), (0.12, tick(r, 3200.0), 0.4)]
    for t0 in (0.3, 0.45):
        items.append((t0, _beep(2400.0, 0.05, 0.02, ((1, 1.0), (1.5, 0.3))), 0.35))
    return layer(0.62, items)


def sfx_shield_up(r):
    n = _n(1.1)
    t = _t(n)
    rise = 0.85 + 0.15 * (1 - np.exp(-t / 0.1))
    cut = 300.0 + 4200.0 * (1 - np.exp(-t / 0.25))
    chord = sum(osc(nf(nm) * rise * (1 + dt), n, SR, "saw", cut, res=0.3, hmax=40, phase=k)
                for k, (nm, dt) in enumerate((("A4", 0.0), ("A4", 0.006), ("E5", -0.004), ("A5", 0.003))))
    chord *= adsr(n, SR, 0.15, 0.4, 0.4, 0.5)
    hum = np.sin(TAU * 110.0 * t) * (0.7 + 0.3 * np.sin(TAU * 6.0 * t)) * adsr(n, SR, 0.05, 0.3, 0.5, 0.5)
    items = [(0, chord, 0.4), (0, hum, 0.3)]
    for _ in range(8):
        items.append((r.uniform(0.1, 0.6), fm(r.uniform(2500, 5000), 0.3, 1.0, 0.0, 0.08), 0.06))
    return room(layer(1.2, items), r, 0.7, 0.25)


def sfx_repair(r):
    items = [(0.07 * i, fm(nf(nm), 0.4, 2.0, 1.0, 0.15), 0.45) for i, nm in enumerate(("C#6", "E6", "G#6", "B6", "C#7"))]
    n = _n(0.9)
    t = _t(n)
    whir = (np.sin(TAU * 520.0 * t) + 0.3 * np.sin(TAU * 1040.0 * t)) * (0.6 + 0.4 * np.sin(TAU * 14.0 * t))
    items.append((0, whir * adsr(n, SR, 0.08, 0.3, 0.6, 0.4), 0.2))
    for _ in range(6):
        items.append((r.uniform(0.2, 0.7), fm(r.uniform(3500, 6500), 0.2, 1.0, 0.0, 0.05), 0.05))
    return room(layer(1.25, items), r, 0.7, 0.22)


SFX = [   # name, generator, peak dBFS
    ("wall_hit_heavy", sfx_wall_hit_heavy, -1.5), ("wall_hit_light", sfx_wall_hit_light, -3.0),
    ("land", sfx_land, -2.5), ("boost", sfx_boost, -2.0), ("pad_weapon", sfx_pad_weapon, -3.0),
    ("beep_count", sfx_beep_count, -3.0), ("beep_go", sfx_beep_go, -2.5), ("lap", sfx_lap, -3.0),
    ("final_lap", sfx_final_lap, -2.5), ("finish", sfx_finish, -2.0), ("ui_move", sfx_ui_move, -8.0),
    ("ui_select", sfx_ui_select, -6.0), ("ui_back", sfx_ui_back, -6.5), ("ui_error", sfx_ui_error, -6.0),
    ("explosion", sfx_explosion, -1.5), ("shield_hit", sfx_shield_hit, -2.5), ("plasma_fire", sfx_plasma_fire, -3.0),
    ("missile_launch", sfx_missile_launch, -2.5), ("missile_hit", sfx_missile_hit, -1.5), ("emp", sfx_emp, -2.0),
    ("shockwave", sfx_shockwave, -1.5), ("mine_drop", sfx_mine_drop, -3.0), ("shield_up", sfx_shield_up, -3.0),
    ("repair", sfx_repair, -3.5), ("wrong_way", sfx_wrong_way, -4.0), ("eliminated", sfx_eliminated, -1.5),
    ("ship_contact", sfx_ship_contact, -2.5), ("unlock", sfx_unlock, -3.0),
]


def build_sfx():
    print("one-shots", flush=True)
    for name, fn, pk in SFX:
        y = fn(rng_for(name))
        write_wav("sfx/%s.wav" % name, one_shot(y, pk, fout=min(0.03, len(y) / SR * 0.2)))


# =====================================================================================
# 5. Music toolkit (44.1 kHz): drum kit, FX, instruments, harmony
# =====================================================================================

_CACHE = {}


def cached(fn):
    """Memoise synth voices on their arguments (notes repeat a lot)."""
    def wrap(*args):
        key = (fn.__name__,) + args
        if key not in _CACHE:
            _CACHE[key] = fn(*args)
        return _CACHE[key]
    return wrap


def _mt(dur):
    n = int(MSR * dur)
    return n, np.arange(n) / MSR


def _mnz(n, name, mag_fn):
    return noise_shaped(n + n % 2, MSR, rng_for(name), mag_fn)[:n]


def _tail(y, ms=8.0):
    k = min(y.shape[-1], int(MSR * ms / 1000.0))
    y = y.copy()
    y[..., -k:] *= np.linspace(1, 0, k)
    return y


def _norm(y):
    return y / (np.max(np.abs(y)) + 1e-12)


# ---- drum kit --------------------------------------------------------------------------------

@cached
def d_kick(tune=50.0, decay=0.32, click=1.0, drive=1.8):
    """909-flavoured kick: pitch-swept sine + click, soft-clipped."""
    n, t = _mt(0.6)
    f = tune + 90.0 * np.exp(-t / 0.032) + 230.0 * np.exp(-t / 0.0045)
    body = np.sin(TAU * np.cumsum(f) / MSR) * np.exp(-t / decay) * np.minimum(t / 0.0005, 1.0)
    clk = _mnz(n, "kclick", lambda fr: m_bp(fr, 1500, 9000, 1)) * np.exp(-t / 0.0022) * 0.3 * click
    return _tail(np.tanh(drive * (body + clk)) / np.tanh(drive), 40.0)


@cached
def d_kick_ind():
    """Industrial kick: hard asymmetric distortion, gritty body."""
    n, t = _mt(0.5)
    f = 46.0 + 120.0 * np.exp(-t / 0.025) + 300.0 * np.exp(-t / 0.004)
    body = np.sin(TAU * np.cumsum(f) / MSR) * np.exp(-t / 0.26)
    grit = _mnz(n, "kgrit", lambda fr: m_bp(fr, 200, 3000, 1)) * np.exp(-t / 0.03) * 0.25
    y = np.tanh(4.0 * (body + grit) + 0.4) - np.tanh(0.4)
    y = filt(y, MSR, lambda fr: m_lp(fr, 6000, 2) * m_hp(fr, 30, 2))
    return _tail(_norm(y) * np.minimum(t / 0.0005, 1.0), 40.0)


@cached
def d_snare(tune=185.0, tau=0.14, drive=1.6):
    n, t = _mt(0.45)
    ph = TAU * np.cumsum(tune * (1 + 0.6 * np.exp(-t / 0.008))) / MSR
    body = (np.sin(ph) + 0.55 * np.sin(1.62 * ph)) * np.exp(-t / 0.055)
    nz = _mnz(n, "snare", lambda fr: m_bp(fr, 900, 11000, 1) * (1 + 0.8 * m_reson(fr, 5200, 1.2))) * np.exp(-t / tau)
    return _tail(np.tanh(drive * (0.7 * body + nz)) * np.minimum(t / 0.0004, 1.0), 20.0)


@cached
def d_bsnare():
    """Breakbeat snare: fat tone + noise with a small room baked in."""
    n, t = _mt(0.5)
    ph = TAU * np.cumsum(205.0 * (1 + 0.5 * np.exp(-t / 0.01))) / MSR
    body = (np.sin(ph) + 0.4 * np.sin(2.3 * ph)) * np.exp(-t / 0.07)
    nz = _mnz(n, "bsn", lambda fr: m_bp(fr, 600, 9000, 1) * (1 + 0.7 * m_reson(fr, 2500, 1.0))) * np.exp(-t / 0.11)
    y = np.tanh(1.8 * (0.8 * body + nz))
    ir = make_ir(MSR, 0.35, rng_for("bsn_room"), lo=300, hi=7000, predelay=0.004, ch=1)[0]
    y = y + 0.35 * convolve(y, ir)
    return _tail(y * np.minimum(t / 0.0004, 1.0), 30.0)


@cached
def d_isnare():
    """Industrial snare: distorted crack, gated noise, metallic ring."""
    n, t = _mt(0.45)
    ph = TAU * np.cumsum(170.0 * (1 + 0.8 * np.exp(-t / 0.006))) / MSR
    body = np.sin(ph) * np.exp(-t / 0.05)
    gate = np.clip((0.13 - t) / 0.012, 0, 1)
    nz = _mnz(n, "isn", lambda fr: m_bp(fr, 400, 10000, 1)) * (np.exp(-t / 0.09) * gate + 0.3 * np.exp(-t / 0.05))
    ring = np.sin(TAU * 1130.0 * t) * np.exp(-t / 0.04) * 0.3
    y = np.tanh(3.5 * (body + nz + ring))
    y = filt(y, MSR, lambda fr: m_hp(fr, 150, 2) * m_lp(fr, 9000, 1))
    return _tail(_norm(y) * np.minimum(t / 0.0004, 1.0), 20.0)


@cached
def d_clap():
    n, t = _mt(0.35)
    env = np.zeros(n)
    for k, a in ((0.0, 0.8), (0.011, 0.9), (0.022, 1.0)):
        env += a * np.exp(-np.maximum(t - k, 0) / 0.006) * (t >= k)
    env += 0.5 * np.exp(-np.maximum(t - 0.03, 0) / 0.07) * (t >= 0.03)
    env *= np.minimum(t / 0.0004, 1.0)
    return _tail(_mnz(n, "clap", lambda fr: m_bp(fr, 800, 6000, 1) * (0.4 + m_reson(fr, 1500, 1.5))) * env)


@cached
def d_hat(open_=False):
    n, t = _mt(0.5 if open_ else 0.1)
    tau = 0.16 if open_ else 0.028
    metal = sum(np.sign(np.sin(TAU * fq * t + k)) for k, fq in enumerate((3510.0, 4687.0, 5327.0, 6240.0, 7181.0, 8401.0)))
    metal = fft_filter(np.concatenate([metal, np.zeros(n % 2)]), MSR, lambda fr: m_hp(fr, 7000, 3) * m_lp(fr, 15000, 2))[:n]
    nz = _mnz(n, "hat%d" % open_, lambda fr: m_hp(fr, 7500, 3) * m_lp(fr, 16000, 2))
    y = (0.6 * nz + 0.5 * metal / rms(metal)) * np.exp(-t / tau) * np.minimum(t / 0.0005, 1.0)
    return _tail(y, 5.0)


@cached
def d_ride():
    n, t = _mt(0.6)
    nz = _mnz(n, "ride", lambda fr: m_bp(fr, 4000, 12000, 1))
    ping = np.sin(TAU * 3120 * t) + 0.7 * np.sin(TAU * 4350 * t) + 0.5 * np.sin(TAU * 6730 * t)
    return _tail((0.6 * nz * np.exp(-t / 0.12) + 0.5 * ping * np.exp(-t / 0.22)) * np.minimum(t / 0.0006, 1.0))


@cached
def d_shaker():
    n, t = _mt(0.11)
    env = np.minimum(t / 0.012, 1.0) * np.exp(-np.maximum(t - 0.012, 0) / 0.025)
    return _tail(_mnz(n, "shaker", lambda fr: m_bp(fr, 4500, 12000, 1)) * env, 4.0)


@cached
def d_rim():
    n, t = _mt(0.08)
    y = np.sin(TAU * 1750 * t) * np.exp(-t / 0.012) + 0.6 * np.sin(TAU * 480 * t) * np.exp(-t / 0.02)
    y += 0.5 * _mnz(n, "rim", lambda fr: m_hp(fr, 2000, 1)) * np.exp(-t / 0.002)
    return _tail(y * np.minimum(t / 0.0003, 1.0), 3.0)


@cached
def d_tom(freq):
    n, t = _mt(0.45)
    f = freq * (1 + 0.7 * np.exp(-t / 0.05))
    y = np.sin(TAU * np.cumsum(f) / MSR) * np.exp(-t / 0.17)
    y += 0.2 * _mnz(n, "tom", lambda fr: m_bp(fr, 300, 3500, 1)) * np.exp(-t / 0.02)
    return _tail(np.tanh(1.4 * y) * np.minimum(t / 0.0008, 1.0))


@cached
def d_crash():
    n, t = _mt(2.6)
    nz = _mnz(n, "crash", lambda fr: m_hp(fr, 2500, 2) * (1 + m_reson(fr, 5200, 2) + 0.7 * m_reson(fr, 8300, 2)))
    env = 0.6 * np.exp(-t / 0.9) + 0.4 * np.exp(-t / 0.15)
    return _tail(nz * env * np.minimum(t / 0.001, 1.0), 60.0)


@cached
def d_metal(f0=520.0):
    """Industrial clank: inharmonic modal partials + strike noise, saturated."""
    n, t = _mt(0.6)
    y = np.zeros(n)
    for ratio, a, tau in ((1.0, 1.0, 0.22), (1.47, 0.8, 0.16), (2.09, 0.65, 0.12), (2.76, 0.5, 0.09),
                          (3.52, 0.4, 0.06), (4.61, 0.3, 0.04), (5.93, 0.2, 0.03)):
        if f0 * ratio < 16000:
            y += a * np.sin(TAU * f0 * ratio * t + ratio) * np.exp(-t / tau)
    y += 0.6 * _mnz(n, "metal%d" % int(f0), lambda fr: m_bp(fr, 1000, 9000, 1)) * np.exp(-t / 0.006)
    return _tail(np.tanh(1.6 * y) * np.minimum(t / 0.0003, 1.0), 20.0)


@cached
def d_blip(f=880.0):
    """Electro percussion blip."""
    n, t = _mt(0.12)
    fr = f * (1 + np.exp(-t / 0.006))
    return _tail(np.sin(TAU * np.cumsum(fr) / MSR) * np.exp(-t / 0.035) * np.minimum(t / 0.0004, 1.0), 5.0)


@cached
def d_zap():
    n, t = _mt(0.18)
    f = 300.0 + 3500.0 * np.exp(-t / 0.02)
    return _tail(osc(f, n, MSR, "saw", 6000.0, hmax=20) * np.exp(-t / 0.04) * np.minimum(t / 0.0004, 1.0), 5.0)


# ---- FX ---------------------------------------------------------------------------------------

@cached
def d_riser(n):
    """Noise sweep rising over n samples with a 3-octave saw siren underneath."""
    x = np.arange(n) / float(n)
    dur = n / MSR
    src = _mnz(n, "riser", lambda fr: m_bp(fr, 150, 14000, 1))

    def g(tt, fr):
        fc = 300.0 * 30.0 ** np.clip(tt / dur, 0, 1)
        return m_reson(fr, fc, 1.6) + 0.15 * m_hp(fr, fc, 2)
    y = stft_shape(src, MSR, g, win=1024)
    tone = osc(110.0 * 2.0 ** (3.0 * x), n, MSR, "saw", hmax=24)
    y = y / rms(y) + 0.2 * tone / rms(tone)
    return y * x ** 2 * np.clip((1 - x) * 80.0, 0, 1)


@cached
def d_down(n):
    """Downlifter: noise with a closing low-pass and decaying level."""
    x = np.arange(n) / float(n)
    dur = n / MSR
    src = _mnz(n, "down", lambda fr: m_bp(fr, 100, 14000, 1))
    y = stft_shape(src, MSR, lambda tt, fr: m_lp(fr, 9000.0 * (1.0 / 45.0) ** np.clip(tt / dur, 0, 1), 2), win=1024)
    return y * (1 - x) ** 2 * np.minimum(x * n / (0.004 * MSR), 1.0)


@cached
def d_impact():
    n, t = _mt(2.0)
    f = 34.0 + 60.0 * np.exp(-t / 0.08)
    boom = np.sin(TAU * np.cumsum(f) / MSR) * np.exp(-t / 0.5)
    nz = _mnz(n, "impact", lambda fr: m_lp(fr, 1500, 1)) * np.exp(-t / 0.12)
    return _tail(np.tanh(1.5 * (boom + 0.4 * nz)) * np.minimum(t / 0.001, 1.0), 100.0)


@cached
def d_revcrash(n):
    c = d_crash()[: min(n, int(2.4 * MSR))][::-1]
    out = np.zeros(n)
    out[n - len(c):] = c
    return out * np.minimum(np.arange(n) / (0.05 * MSR), 1.0)


#           name: (sample factory, bus, pan)
KIT = {
    "kick": (lambda: d_kick(), "kick", 0.0),
    "kick_soft": (lambda: d_kick(54.0, 0.24, 0.4, 1.2), "kick", 0.0),
    "kick_ind": (lambda: d_kick_ind(), "kick", 0.0),
    "snare": (lambda: d_snare(), "snare", 0.0),
    "bsnare": (lambda: d_bsnare(), "snare", 0.03),
    "isnare": (lambda: d_isnare(), "snare", 0.0),
    "clap": (lambda: d_clap(), "snare", -0.05),
    "rim": (lambda: d_rim(), "perc", -0.25),
    "hat": (lambda: d_hat(False), "hats", 0.2),
    "ohat": (lambda: d_hat(True), "hats", 0.25),
    "ride": (lambda: d_ride(), "hats", -0.3),
    "shaker": (lambda: d_shaker(), "perc", -0.4),
    "blip": (lambda: d_blip(880.0), "perc", 0.35),
    "bliplo": (lambda: d_blip(440.0), "perc", -0.35),
    "metal": (lambda: d_metal(510.0), "perc", 0.3),
    "anvil": (lambda: d_metal(190.0), "perc", -0.25),
    "zap": (lambda: d_zap(), "perc", -0.3),
    "tomh": (lambda: d_tom(190.0), "toms", -0.4),
    "tomm": (lambda: d_tom(140.0), "toms", 0.0),
    "toml": (lambda: d_tom(100.0), "toms", 0.4),
    "crash": (lambda: d_crash(), "cym", -0.15),
}
VEL = {"x": 1.0, "o": 0.65, "-": 0.32}
HUMANIZE = ("hat", "ohat", "ride", "shaker", "metal")


# ---- instruments -------------------------------------------------------------------------------

def _lvl(y):
    """Level a note on the RMS of its first 150 ms so different voices share a bus sensibly."""
    k = min(y.shape[-1], int(0.15 * MSR))
    return y / (rms(y[..., :k]) + 1e-9)


def up2(y):
    """Band-limited 2x upsampling (FFT zero padding) along the last axis."""
    n = y.shape[-1]
    spec = np.fft.rfft(y, axis=-1)
    z = np.zeros(y.shape[:-1] + (n + 1,), dtype=complex)
    z[..., :spec.shape[-1]] = spec
    return np.fft.irfft(z, 2 * n, axis=-1) * 2.0


@cached
def v_bass(kind, midi, n, acc=False, gfrom=None):
    f = midi_f(midi)
    t = np.arange(n) / MSR
    fr = f * (midi_f(gfrom) / f) ** np.exp(-t / 0.035) if gfrom is not None else f
    if kind == "sub":
        ph = TAU * (np.cumsum(fr) if np.ndim(fr) else fr * np.arange(n)) / MSR
        y = np.sin(ph) + 0.12 * np.sin(2 * ph)
        env = adsr(n, MSR, 0.004, 0.2, 0.9, 0.015)
    elif kind == "roll":           # punchy filter-envelope mid bass (no sub: the sub bus carries the low end)
        cut = 260.0 + (1500.0 + 1200.0 * acc) * np.exp(-t / 0.05)
        y = osc(fr, n, MSR, "saw", cut, res=0.6, hmax=96) + 0.5 * osc(fr, n, MSR, "square", cut * 0.8, hmax=48)
        y = np.tanh(1.4 * y)
        env = adsr(n, MSR, 0.002, 0.08, 0.6, 0.012)
    elif kind == "acid":           # squelchy resonant 24 dB saw with accents and slides
        cut = (330.0 + 250.0 * acc) * (1.0 + (5.0 + 6.0 * acc) * np.exp(-t / (0.09 + 0.08 * acc)))
        y = osc(fr, n, MSR, "saw", cut, res=1.6 + 0.8 * acc, order=4, hmax=110)
        y = np.tanh((1.6 + acc) * y)
        env = adsr(n, MSR, 0.002, 0.15, 0.75, 0.01)
    elif kind in ("reese", "reese_hard"):   # detuned saw stack, beating slowly; hard = brighter + driven
        hard = kind == "reese_hard"
        cut = 1500.0 if hard else 800.0
        y = sum(osc(fr * 2.0 ** (c / 1200.0), n, MSR, "saw", cut, res=0.5 if hard else 0.2, phase=p, hmax=120)
                for c, p in ((-14.0, 0.0), (-2.0, 1.7), (13.0, 3.1)))
        y = np.tanh(3.2 * y + 0.35) - np.tanh(0.35) if hard else np.tanh(1.3 * y)
        env = adsr(n, MSR, 0.006, 0.3, 0.9, 0.03)
    elif kind == "pulse":          # short distorted pulse stab-bass
        cut = 400.0 + 3000.0 * np.exp(-t / 0.03)
        y = np.tanh(2.5 * osc(fr, n, MSR, "pulse", cut, res=0.5, pw=0.3, hmax=64))
        env = env_ad(n, MSR, 0.002, 0.07) * np.clip((n / MSR - t) / 0.006, 0, 1)
    else:                          # "round": mellow
        y = osc(fr, n, MSR, "saw", 160.0 + 900.0 * np.exp(-t / 0.12), hmax=60) + 0.8 * np.sin(TAU * np.cumsum(fr * np.ones(n)) / MSR)
        env = adsr(n, MSR, 0.005, 0.2, 0.75, 0.04)
    return _lvl(y * env)


@cached
def v_lead(kind, midi, n):
    f = midi_f(midi)
    t = np.arange(n) / MSR
    vib = f * (1.0 + 0.006 * np.sin(TAU * 5.5 * t) * np.clip((t - 0.18) / 0.15, 0, 1))
    if kind == "saw":              # soaring detuned saw lead
        cut = 2200.0 + 3800.0 * np.exp(-t / 0.25)
        y = (osc(vib * 1.0045, n, MSR, "saw", cut, res=0.3, hmax=60) + osc(vib * 0.9955, n, MSR, "saw", cut, phase=2.1, hmax=60)
             + 0.7 * osc(vib, n, MSR, "saw", cut, phase=4.0, hmax=60))
        y = np.tanh(1.1 * y) + 0.35 * osc(vib / 2, n, MSR, "square", 1400.0, hmax=20)
        env = adsr(n, MSR, 0.004, 0.12, 0.8, 0.05)
    elif kind == "dist":           # driven saw + pulse for the industrial track
        y = osc(vib, n, MSR, "saw", 3200.0, hmax=50) + 0.8 * osc(vib * 1.007, n, MSR, "pulse", 3200.0, pw=0.3, hmax=50)
        y = filt(np.tanh(3.5 * y), MSR, lambda fr: m_hp(fr, 250, 1) * m_lp(fr, 5000, 2) * (1 + 0.6 * m_reson(fr, 1400, 1.5)), tail=0.0)
        env = adsr(n, MSR, 0.003, 0.1, 0.85, 0.04)
    elif kind == "pluck":          # hook pluck
        cut = 600.0 + 5200.0 * np.exp(-t / 0.06)
        y = osc(f * 1.003, n, MSR, "saw", cut, res=0.35, hmax=60) + 0.6 * osc(f * 0.997, n, MSR, "square", cut, phase=1.0, hmax=40)
        env = env_ad(n, MSR, 0.002, 0.22) * np.clip((n / MSR - t) / 0.02, 0, 1)
    elif kind == "bell":
        y = fm(f, n / MSR, 3.01, 1.6, 0.5, sr=MSR)
        y = np.concatenate([y, np.zeros(n - len(y))])
        y += 0.25 * np.sin(TAU * 2 * f * t) * np.exp(-t / 0.3) * (2 * f < 0.45 * MSR)
        env = np.minimum(t / 0.0015, 1.0) * np.clip((n / MSR - t) / 0.05, 0, 1)
    elif kind == "glass":          # soft FM keys
        y = fm(f, n / MSR, 2.0, 1.2, 0.9, itau=0.25, sr=MSR)
        y = np.concatenate([y, np.zeros(n - len(y))])
        env = np.clip((n / MSR - t) / 0.06, 0, 1)
    elif kind == "brass":
        y = brass(f, n / MSR, sr=MSR, bright=1.2)
        y = np.concatenate([y, np.zeros(n - len(y))])[:n]
        env = 1.0
    else:                          # "soft": rounded square / triangle
        y = osc(vib, n, MSR, "square", 3200.0, hmax=30) + 0.6 * osc(vib, n, MSR, "tri", hmax=9)
        env = adsr(n, MSR, 0.015, 0.2, 0.8, 0.07)
    return _lvl(y * env)


@cached
def v_pluck(kind, midi, n):
    f = midi_f(midi)
    t = np.arange(n) / MSR
    rel = np.clip((n / MSR - t) / 0.01, 0, 1)
    if kind == "fm":
        y = np.sin(TAU * f * t + 2.2 * np.exp(-t / 0.06) * np.sin(TAU * 2.0 * f * t)) * np.exp(-t / 0.3)
        y *= np.minimum(t / 0.002, 1.0)
    elif kind == "sq":
        y = osc(f, n, MSR, "square", 500.0 + 3500.0 * np.exp(-t / 0.05), hmax=40) * env_ad(n, MSR, 0.002, 0.09)
    elif kind == "metal":
        idx = 3.0 * np.exp(-t / 0.03) + 0.4
        y = np.tanh(1.8 * np.sin(TAU * f * t + idx * np.sin(TAU * 1.41 * f * t))) * env_ad(n, MSR, 0.001, 0.08)
    else:                          # "pluck": filtered saw
        y = osc(f, n, MSR, "saw", 350.0 + 4800.0 * np.exp(-t / 0.04), res=0.45, hmax=60) * env_ad(n, MSR, 0.002, 0.11)
    return _lvl(y * rel)


@cached
def v_stab(kind, notes, n):
    """Chord stab -> stereo (2, n)."""
    t = np.arange(n) / MSR
    out = np.zeros((2, n))
    for j, m in enumerate(notes):
        f = midi_f(m)
        if kind == "rave":         # detuned saws with a snappy filter and a small pitch drop
            bend = f * (1.0 + 0.02 * np.exp(-t / 0.015))
            cut = 500.0 + 4800.0 * np.exp(-t / 0.075)
            out[0] += osc(bend * 1.004, n, MSR, "saw", cut, res=0.5, hmax=50, phase=j)
            out[1] += osc(bend * 0.996, n, MSR, "saw", cut, res=0.5, hmax=50, phase=j + 1.3)
            sub = 0.5 * osc(f / 2, n, MSR, "square", cut * 0.5, hmax=20)
            out += sub
        elif kind == "metal":      # inharmonic FM + saw, distorted
            idx = 4.0 * np.exp(-t / 0.05) + 0.8
            fmv = np.sin(TAU * f * t + idx * np.sin(TAU * 1.414 * f * t))
            saw = osc(f, n, MSR, "saw", 300.0 + 3000.0 * np.exp(-t / 0.06), hmax=40, phase=j)
            y = np.tanh(2.2 * (fmv + 0.6 * saw))
            out[0] += y
            out[1] += np.roll(y, 40 + 13 * j)
        elif kind == "brass":
            y = brass(f, n / MSR, sr=MSR, bright=1.3)
            y = np.concatenate([y, np.zeros(n - len(y))])[:n]
            out[0] += y
            out[1] += np.roll(y, 30 + 11 * j)
        else:                      # "keys": FM electric piano
            idx = 1.2 * np.exp(-t / 0.25) + 0.2
            y = np.sin(TAU * f * t + idx * np.sin(TAU * f * t)) * np.exp(-t / 0.9)
            out[j % 2] += y
            out[1 - j % 2] += 0.6 * y
    if kind == "rave":
        out = np.tanh(1.3 * out / len(notes))
        out *= adsr(n, MSR, 0.002, 0.1, 0.3, 0.03)
    elif kind == "metal":
        out *= adsr(n, MSR, 0.002, 0.12, 0.25, 0.03)
    else:
        out *= np.minimum(t / 0.002, 1.0) * np.clip((n / MSR - t) / 0.04, 0, 1)
    return _lvl(out)


FORMANTS = ((700.0, 1.0, 5.0), (1150.0, 0.6, 6.0), (2600.0, 0.3, 8.0), (3300.0, 0.15, 8.0))   # "ah"


@cached
def v_pad(kind, notes, n):
    """Sustained chord -> stereo (2, n).  Rendered at 22.05 kHz and upsampled (pads are dark)."""
    sr = MSR / 2.0
    h = (n + 1) // 2 + 1
    t = np.arange(h) / sr
    out = np.zeros((2, h))
    for j, m in enumerate(notes):
        f = midi_f(m)
        for side in (0, 1):
            dets = (-8.0, 7.0) if side == 0 else (-5.0, 10.0)
            if kind == "glass":
                for k, c in enumerate(dets):
                    fc = f * 2.0 ** (c / 1200.0)
                    out[side] += np.sin(TAU * fc * t + 0.8 * np.sin(TAU * 2.0 * fc * t) + k + j)
            elif kind == "choir":
                for k, c in enumerate(dets):
                    vib = f * 2.0 ** (c / 1200.0) * (1.0 + 0.004 * np.sin(TAU * (4.6 + 0.4 * k + 0.3 * side) * t + j))
                    out[side] += osc(vib, h, sr, "saw", 3500.0, hmax=60, phase=1.3 * k + 2.1 * side + 0.7 * j)
            else:                  # "warm" / "dark"
                cut = 1500.0 if kind == "warm" else 750.0
                for k, c in enumerate(dets):
                    out[side] += osc(f * 2.0 ** (c / 1200.0), h, sr, "saw", cut, hmax=80, phase=1.3 * k + 2.1 * side + 0.7 * j)
    if kind == "choir":
        hh = h + h % 2
        pad = np.zeros((2, hh))
        pad[:, :h] = out
        out = fft_filter(pad, sr, lambda fr: m_hp(fr, 150, 2) * sum(a * m_reson(fr, fc, q) for fc, a, q in FORMANTS))[:, :h]
    att = {"glass": 0.25, "choir": 0.5, "dark": 0.6}.get(kind, 0.35)
    out *= adsr(h, sr, att, 0.6, 0.85, 0.5)
    return _lvl(up2(out)[:, :n])


def snap_f(f, n):
    """Frequency snapped to a whole number of cycles over n samples at MSR."""
    return max(1, round(f * n / MSR)) * MSR / n


def loop_drone(n, notes, name, cut=900.0):
    """Seamlessly looping detuned-saw drone (every partial completes whole cycles over n)."""
    r = rng_for(name)
    out = np.zeros((2, n))
    for m in notes:
        for side in (0, 1):
            for c in ((-7.0, 6.0) if side == 0 else (-4.0, 9.0)):
                out[side] += osc(snap_f(midi_f(m) * 2.0 ** (c / 1200.0), n), n, MSR, "saw", cut, hmax=60, phase=r.uniform(0, TAU))
    swell = np.exp(0.35 * loop_lfo(n, r, 3))
    return out * swell


def shepard(n, name, f_lo=40.0, octaves=8):
    """Endlessly rising Shepard-Risset glissando, one octave per n samples, exactly periodic:
    component k at loop end has the frequency, amplitude and phase of component k+1 at the start;
    the wrapping component is silent (sin^2 window over the octave span)."""
    x = np.arange(n) / float(n)
    out = np.zeros(n)
    phi = rng_for(name).uniform(0, TAU)
    for k in range(octaves):
        u = k + x
        f = f_lo * 2.0 ** u
        ph = phi + TAU * np.concatenate([[0.0], np.cumsum(f[:-1])]) / MSR
        amp = np.sin(np.pi * u / octaves) ** 2 * m_lp(f, 2500.0, 1)
        out += amp * np.sin(ph)
        phi = ph[-1] + TAU * f[-1] / MSR
    return out


# ---- harmony -------------------------------------------------------------------------------------

_QUAL = {"": (0, 4, 7), "m": (0, 3, 7), "7": (0, 4, 7, 10), "m7": (0, 3, 7, 10), "maj7": (0, 4, 7, 11),
         "sus4": (0, 5, 7), "sus2": (0, 2, 7), "add9": (0, 4, 7, 14), "6": (0, 4, 7, 9), "m6": (0, 3, 7, 9),
         "m9": (0, 3, 7, 10, 14), "maj9": (0, 4, 7, 11, 14)}


def _pc(s):
    return (_NOTE[s[0]] + s.count("#") - s[1:].count("b")) % 12


def parse_chord(c):
    """'F#m7', 'G/B' -> (root pitch class, intervals, bass pitch class)."""
    bass = None
    if "/" in c:
        c, b = c.split("/")
        bass = _pc(b)
    k = 2 if len(c) > 1 and c[1] in "#b" else 1
    root = _pc(c[:k])
    return root, _QUAL[c[k:]], root if bass is None else bass


def voicing(c, lo=55):
    root, iv, _ = parse_chord(c)
    return sorted(lo + ((root + i - lo) % 12) for i in iv)


def bass_note(c, lo=33):
    return lo + ((parse_chord(c)[2] - lo) % 12)


def parse_melody(s):
    """'E5:1 G5:.5 r:.5 | ...' -> [(beat, beats, midi)]; every bar must hold 4 beats."""
    out = []
    for b, bar in enumerate(s.split("|")):
        pos = 0.0
        for tok in bar.split():
            name, d = tok.split(":")
            d = float(d)
            if name != "r":
                out.append((b * 4 + pos, d, nn(name)))
            pos += d
        assert abs(pos - 4.0) < 1e-9, "melody bar %d has %.2f beats: %s" % (b + 1, pos, bar)
    return out


def parse_line(s):
    """Bassline bar: 16 tokens, '.' rest, '-' tie, '<semitones>[a][s]' (a = accent, s = slide in).
    -> [(step, length, interval, accent, slide)]"""
    toks = s.split()
    assert len(toks) == 16, s
    notes = []
    for i, tok in enumerate(toks):
        if tok == ".":
            continue
        if tok == "-":
            if notes and notes[-1][0] + notes[-1][1] == i:
                st, ln, iv, a, sl = notes[-1]
                notes[-1] = (st, ln + 1, iv, a, sl)
            continue
        notes.append((i, 1, int(tok.rstrip("as")), "a" in tok, "s" in tok))
    return notes


# =====================================================================================
# 6. Sequencer, arranger, mixer, mastering
# =====================================================================================

def in_version(bus, version):
    """Bus prefixes: 'x_' = intense-only layer, 'm_' = main-only layer."""
    if version == "main":
        return not bus.startswith("x_")
    if version == "intense":
        return not bus.startswith("m_")
    return True


def tv_lowpass(x, fc_at, res=0.5, q=1.4, circular=True, win=2048):
    """Time-varying resonant low-pass by STFT overlap-add.  fc_at(sample positions) -> Hz; frames
    whose cutoff is >= 19 kHz are bypassed.  Hann^2 frames at 75 % overlap sum to 1.5 x the input,
    so the output starts as the input and only filtered frames add their difference."""
    hop = win // 4
    n = x.shape[-1]
    pad = np.zeros((x.shape[0], win), dtype=x.dtype)
    ext = np.concatenate([x[:, -win:], x, x[:, :2 * win]] if circular else [pad, x, pad, pad], axis=1)
    out = ext * 1.5
    w = (0.5 - 0.5 * np.cos(TAU * np.arange(win) / win)).astype(x.dtype)
    f = np.fft.rfftfreq(win, 1.0 / MSR)
    ks = np.arange((n + win) // hop + 1)
    centers = ks * hop + win / 2.0 - win
    fc = fc_at(np.mod(centers, n) if circular else centers)
    act = np.flatnonzero(fc < 19000.0)
    for b0 in range(0, len(act), 256):
        kk = act[b0:b0 + 256]
        starts = kk * hop
        fr = ext[:, starts[:, None] + np.arange(win)[None, :]] * w
        g = m_lp(f[None, :], fc[kk][:, None], 2)
        if res:
            g = g * (1.0 + res * m_reson(f[None, :], fc[kk][:, None], q))
        delta = (np.fft.irfft(np.fft.rfft(fr, axis=-1) * g, win, axis=-1) - fr) * w
        for j, s0 in enumerate(starts):
            out[:, s0:s0 + win] += delta[:, j, :]
    return (out[:, win:win + n] / 1.5).astype(x.dtype)


def active_rms(x, block=2048):
    """RMS over the blocks where the bus is actually playing."""
    m = x.reshape(-1, x.shape[-1])
    nb = m.shape[1] // block
    e = (m[:, :nb * block] ** 2).reshape(m.shape[0], nb, block).mean(axis=(0, 2))
    act = e > e.max() * 0.003
    return float(np.sqrt(e[act].mean())) + 1e-12


LUFS_OFFSET = 0.0     # calibrated against ffmpeg's ebur128 filter on the rendered songs (see --check)


def lufs(x, sr):
    """Gated integrated loudness, BS.1770-style.  K-weighting is applied as a power weighting of
    100 ms block spectra (Parseval); 400 ms gating blocks = 4 consecutive 100 ms blocks (75 % overlap)."""
    blk = int(0.1 * sr)
    nb = x.shape[-1] // blk
    seg = np.asarray(x[:, :nb * blk], dtype=np.float32).reshape(x.shape[0], nb, blk)
    f = np.fft.rfftfreq(blk, 1.0 / sr)
    fx = f / 38.13                                        # RLB high-pass (Q 0.5) and +4 dB shelf
    k2 = (m_shelf(f, 1682.0, 4.0) * fx * fx / np.sqrt((1 - fx * fx) ** 2 + (fx / 0.5) ** 2 + 1e-18)) ** 2
    k2[1:(blk + 1) // 2] *= 2.0
    e = np.zeros(nb)
    for c in range(x.shape[0]):
        for i in range(0, nb, 512):
            spec = np.fft.rfft(seg[c, i:i + 512], axis=-1)
            e[i:i + 512] += (np.abs(spec) ** 2 * k2).sum(axis=-1) / float(blk) ** 2
    p = np.convolve(e, np.ones(4) / 4.0, mode="valid")
    p = p[p > 10 ** ((-70 + 0.691) / 10)]
    p = p[p > np.mean(p) * 0.1]
    return -0.691 + 10 * np.log10(np.mean(p)) + LUFS_OFFSET


def limiter(x, sr, ceil=0.84, win=0.012):
    """Look-ahead peak limiter (circular, so loop seams stay intact)."""
    n = x.shape[1]
    need = np.minimum(1.0, ceil / np.maximum(np.max(np.abs(x), axis=0), 1e-9))
    blk = 32
    nb = -(-n // blk)
    g = np.concatenate([need, np.ones(nb * blk - n)]).reshape(nb, blk).min(axis=1)
    w = max(2, int(win * sr / blk))
    gm = g.copy()
    for s in range(1, w + 1):
        gm = np.minimum(gm, np.minimum(np.roll(g, s), np.roll(g, -s)))
    kern = np.hanning(2 * w + 1)
    kern /= kern.sum()
    kw = np.zeros(nb)
    kw[:w + 1] = kern[w:]
    kw[-w:] = kern[:w]
    gs = np.fft.irfft(np.fft.rfft(gm) * np.fft.rfft(kw), nb)
    centers = (np.arange(nb) + 0.5) * blk
    gain = np.interp(np.arange(n), np.concatenate([[centers[-1] - nb * blk], centers, [centers[0] + nb * blk]]),
                     np.concatenate([[gs[-1]], gs, [gs[0]]]))
    return np.clip(x * gain, -ceil, ceil)


def master(mix, sr, lufs_target, ceil_db=-2.0):
    mix = mix - mix.mean(axis=1, keepdims=True)
    ceil = db(ceil_db)
    gain = db(lufs_target - lufs(mix, sr))
    for _ in range(3):                       # loudness target and limiter interact: iterate
        y = limiter(mix * gain, sr, ceil)
        gain *= db(lufs_target - lufs(y, sr))
    return limiter(mix * gain, sr, ceil)


MIX_BASE = {
    "kick": dict(peak=-6.0), "snare": dict(peak=-9.0, rev=0.12), "hats": dict(rms=-29.0, hp=4500),
    "perc": dict(rms=-28.5, rev=0.12, hp=200), "toms": dict(peak=-11.0, rev=0.15), "cym": dict(peak=-13.0, rev=0.15, hp=1500),
    "sub": dict(rms=-21.0, duck=0.6, lp=220), "m_bass": dict(rms=-21.0, duck=0.45, hp=70), "x_bass": dict(rms=-20.5, duck=0.45, hp=70),
    "x_pulse": dict(rms=-25.0, duck=0.3, hp=150), "stab": dict(rms=-20.5, rev=0.2, dly=0.15, duck=0.3, hp=200),
    "pad": dict(rms=-25.0, rev=0.35, duck=0.45, hp=180), "arp": dict(rms=-26.0, rev=0.25, dly=0.35, duck=0.25, hp=300),
    "hook": dict(rms=-21.5, rev=0.2, dly=0.3, hp=250), "keys": dict(rms=-21.5, rev=0.35, dly=0.3, hp=250),
    "riff": dict(rms=-24.0, rev=0.12, dly=0.12, duck=0.3, hp=180), "x_lead": dict(rms=-19.5, rev=0.2, dly=0.25, hp=220),
    "lead": dict(rms=-19.0, rev=0.25, dly=0.3, hp=220), "x_hats": dict(rms=-30.0, hp=5000), "x_perc": dict(rms=-28.5, rev=0.12, hp=250),
    "fx": dict(peak=-13.0, rev=0.3), "drone": dict(rms=-26.0, rev=0.3, hp=120),
}


def mixcfg(**over):
    cfg = {k: dict(v) for k, v in MIX_BASE.items()}
    for k, v in over.items():
        c = cfg.setdefault(k, {})
        if "rms" in v:
            c.pop("peak", None)
        if "peak" in v:
            c.pop("rms", None)
        c.update(v)
    return cfg


class Song:
    def __init__(self, name, bpm, bars, swing=0.0, circular=True, tail=0.0, kit=None, rt60=1.6,
                 delay_beats=0.75, delay_fb=0.45):
        self.name = name
        self.beat = 60.0 / bpm * MSR
        self.bars = bars
        self.n = int(round(bars * 4 * self.beat + tail * MSR))
        self.circular = circular
        self.swing = swing
        self.bus = {}
        self.kicks = []
        self.auto = {}
        self.kit = dict(KIT, **(kit or {}))
        self.rt60 = rt60
        self.delay_beats = delay_beats
        self.delay_fb = delay_fb
        self.r = rng_for(name)

    # ---- placement ---------------------------------------------------------------------------
    def pos(self, bar, step):
        """Sample position of a 16th step (odd 16ths are delayed by the swing amount)."""
        if self.swing and float(step).is_integer() and int(step) % 2 == 1:
            step = step + self.swing
        return int(round((bar * 4 + step / 4.0) * self.beat))

    def dur(self, steps):
        return max(64, int(steps / 4.0 * self.beat))

    def put(self, bus, sig, bar, step, gain=1.0, pan=0.0):
        buf = self.bus.get(bus)
        if buf is None:
            buf = self.bus[bus] = np.zeros((2, self.n), dtype=np.float32)
        st = pan_st(sig, pan) if sig.ndim == 1 else sig
        (add_circ if self.circular else add_at)(buf, self.pos(bar, step), st, gain)

    def drum(self, name, bar, step, vel=1.0, prefix=""):
        fn, bus, pan = self.kit[name]
        if bus == "kick" and not prefix:
            self.kicks.append(self.pos(bar, step))
        if name in HUMANIZE:
            vel *= 1.0 + 0.1 * self.r.standard_normal()
        self.put(prefix + bus, fn(), bar, step, vel, pan)

    def pattern(self, bar, pat, prefix="", upto=16, skip=()):
        for name, s in pat.items():
            if name in skip:
                continue
            for i, ch in enumerate(s[:upto]):
                if ch != ".":
                    self.drum(name, bar, i, VEL[ch], prefix)

    def bassline(self, bar, line, kind, bus, chord_at, lo):
        notes = parse_line(line)
        prev = None
        for k, (st, ln, iv, acc, sl) in enumerate(notes):
            m = bass_note(chord_at(st), lo) + iv
            legato = k + 1 < len(notes) and notes[k + 1][4] and notes[k + 1][0] == st + ln
            n = int(self.dur(ln) * (1.06 if legato else 0.9))
            sig = v_bass(kind, m, n, bool(acc), prev if (sl and prev is not None) else None)
            self.put(bus, sig, bar, st, 1.0 if acc else 0.8)
            prev = m

    def stabs(self, bar, rhythm, ln, kind, bus, chord_at, lo):
        for st, ch in enumerate(rhythm):
            if ch != ".":
                self.put(bus, v_stab(kind, tuple(voicing(chord_at(st), lo)), self.dur(ln)), bar, st, VEL[ch])

    def pad(self, bar, halves, kind, bus, lo):
        ln = 16 // len(halves)
        for h, c in enumerate(halves):
            self.put(bus, v_pad(kind, tuple(voicing(c, lo)), int(self.dur(ln) * 1.12)), bar, h * ln)

    def arp(self, bar, pat, kind, bus, chord_at, lo):
        order, glen = pat
        toks = order.split()
        for st in range(16):
            tok = toks[st % len(toks)]
            if tok == ".":
                continue
            v = voicing(chord_at(st), lo)
            seq = v + [m + 12 for m in v] + [m + 24 for m in v]
            self.put(bus, v_pluck(kind, seq[int(tok)], self.dur(glen)), bar, st,
                     1.0 if st % 4 == 0 else 0.72, 0.35 if st % 2 else -0.35)

    def melody(self, bar0, nb, mel, kind, bus, octave=0, gate=0.92, gain=1.0, pan=0.0):
        for beat, d, m in parse_melody(mel):
            if beat < nb * 4:
                self.put(bus, v_lead(kind, m + 12 * octave, int(d * self.beat * gate)), bar0, beat * 4.0, gain, pan)

    def lp(self, buses, pts):
        """Low-pass automation: pts = [(bar, Hz)], log-interpolated; bypassed outside the span."""
        xs = np.array([b * 4 * self.beat for b, _ in pts])
        ys = np.log([h for _, h in pts])
        for b in buses:
            self.auto.setdefault(b, []).append((xs, ys))

    def _auto_fn(self, bus):
        segs = self.auto[bus]

        def fn(pos):
            out = np.full(pos.shape, 30000.0)
            for xs, ys in segs:
                inside = (pos >= xs[0]) & (pos <= xs[-1])
                out = np.where(inside, np.minimum(out, np.exp(np.interp(pos, xs, ys))), out)
            return out
        return fn

    # ---- mixdown -----------------------------------------------------------------------------
    def _shift(self, x, k):
        if self.circular:
            return np.roll(x, k, axis=-1)
        y = np.zeros_like(x)
        y[..., k:] = x[..., :-k]
        return y

    def _filter(self, x, mag):
        return fft_filter(x, MSR, mag) if self.circular else filt(x, MSR, mag, tail=0.0)

    def mixdowns(self, cfg, versions=("all",), lufs_target=-14.0, ceil_db=-2.0):
        """Mix every requested version.  Each bus is processed once (automation, EQ with the master
        EQ folded in, drive, level, side-chain duck) and summed into a shared / main-only / intense-
        only group; a version is its groups' sum through the delay, reverb and master.  Shared buses
        are therefore sample-identical in main and intense.  Consumes the buses."""
        n = self.n
        f32 = np.float32
        duck = np.zeros(n)
        tpl = np.exp(-np.arange(int(0.38 * MSR)) / (0.10 * MSR))
        for p in self.kicks:
            (add_circ if self.circular else add_at)(duck, p, tpl)
        duck = np.clip(duck, 0.0, 1.0).astype(f32)
        groups = {}

        def master_eq(f):
            return m_hp(f, 30, 2) * m_shelf(f, 120, -1.0, high=False) * m_shelf(f, 4000, 1.5)
        for name in sorted(self.bus):
            buf = self.bus.pop(name)
            if not any(in_version(name, v) for v in versions):
                continue
            c = cfg[name]
            if name in self.auto:
                buf = tv_lowpass(buf, self._auto_fn(name), res=c.get("ares", 0.5), circular=self.circular)
            buf = self._filter(buf, lambda f, c=c: master_eq(f) * (m_hp(f, c["hp"], 2) if c.get("hp") else 1.0)
                               * (m_lp(f, c["lp"], 2) if c.get("lp") else 1.0)).astype(f32)
            if c.get("drive"):
                buf = np.tanh(f32(c["drive"]) * buf / (np.max(np.abs(buf)) + 1e-12))
            if "peak" in c:
                buf *= f32(db(c["peak"]) / (np.max(np.abs(buf)) + 1e-12))
            else:
                buf *= f32(db(c["rms"]) / active_rms(buf))
            if c.get("duck"):
                buf *= 1.0 - f32(c["duck"]) * duck
            key = name[:2] if name[:2] in ("x_", "m_") else "s"
            if key not in groups:
                groups[key] = [np.zeros((2, n), f32), np.zeros((2, n), f32), np.zeros(n, f32)]
            g = groups[key]
            g[0] += buf
            if c.get("rev"):
                g[1] += f32(c["rev"]) * buf
            if c.get("dly"):
                g[2] += f32(c["dly"]) * buf.mean(axis=0)
            del buf
        ir = make_ir(MSR, self.rt60, rng_for(self.name + "_ir"), lo=280, hi=6500, predelay=0.02)
        out = {}
        for v in versions:
            keys = [k for k in ("s", "m_", "x_") if k in groups and (k == "s" or in_version(k + "bus", v))]
            dry = sum(groups[k][0].astype(np.float64) for k in keys)
            rev = sum(groups[k][1].astype(np.float64) for k in keys)
            dly = sum(groups[k][2].astype(np.float64) for k in keys)
            if np.any(dly):                  # dotted-eighth ping-pong delay
                dly = self._filter(dly, lambda f: m_bp(f, 350, 4500, 1))
                d = int(round(self.delay_beats * self.beat))
                for i in range(1, 7):
                    e = self.delay_fb ** (i - 1) * self._shift(dly, i * d)
                    dry[i % 2] += e
                    rev[i % 2] += 0.3 * e
            dry += convolve(rev, ir, circular=self.circular)
            del rev, dly
            out[v] = master(dry, MSR, lufs_target, ceil_db)
            del dry
        return out


FILLS = {
    "toms": {"snare": "........x.xx....", "tomh": "............xx..", "tomm": "..............x.", "toml": "...............x"},
    "snare": {"snare": "........x..x.xxx"},
    "soft": {"snare": "..............-o", "tomm": "............o...", "toml": "..............o."},
    "break": {"bsnare": "........x.-x.x.x", "tomh": "..........x.....", "toml": "............x..."},
    "metal": {"snare": "........x..x..x.", "metal": "..........x..x.x", "anvil": "...............x"},
}
KEEP = ("kick", "kick_soft", "hat", "shaker", "ohat")


def arrange(s, sp):
    """Lay out every section of a song spec into the Song's buses.
    Section keys: bars, chords, drums [(pattern, bus prefix)], fill, roll, crash, impact, down,
    bass [(bus, kind, line)], stab [(bus, kind, rhythm)], pad [(bus, kind)], arp [(bus, kind, pattern)],
    lead [(bus, kind, melody, octave, gate[, gain])], riser (bars), lp [(buses, [(bar in section, Hz)])]."""
    bar0 = 0
    for sec in sp["sections"]:
        nb = sec["bars"]
        chords = sec["chords"].split()
        roll = sec.get("roll", 0)
        for b in range(nb):
            bar = bar0 + b
            halves = chords[b % len(chords)].split(",")

            def chord_at(step, h=halves):
                return h[min(len(h) - 1, int(step) * len(h) // 16)]

            last = b == nb - 1
            fill = FILLS.get(sec.get("fill")) if last else None
            in_roll = roll and b >= nb - roll
            for pname, prefix in sec.get("drums", ()):
                pat = sp["drums"][pname]
                skip = ("snare", "clap", "bsnare", "isnare") if in_roll else ()
                if fill and not prefix:
                    s.pattern(bar, pat, prefix, 8, skip)
                    s.pattern(bar, {k: "." * 8 + v[8:] for k, v in pat.items() if k in KEEP}, prefix)
                else:
                    s.pattern(bar, pat, prefix, 16, skip)
            if fill:
                s.pattern(bar, fill)
            if in_roll:                      # snare roll: 8ths then 16ths, crescendo
                k = b - (nb - roll)
                dense = k >= roll // 2
                for st in range(0, 16, 1 if dense else 2):
                    s.drum("snare", bar, st, 0.25 + 0.75 * (k * 16 + st) / float(roll * 16))
            if b == 0 and sec.get("crash"):
                s.drum("crash", bar, 0)
            if b == 0 and sec.get("impact"):
                s.put("fx", d_impact(), bar, 0, 0.8)
            if b == 0 and sec.get("down"):
                s.put("fx", d_down(int(2 * 4 * s.beat)), bar, 0, 0.5)
            for bus, kind, line in sec.get("bass", ()):
                s.bassline(bar, sp["bass"][line], kind, bus, chord_at, sp["bass_lo"])
            for bus, kind, rname in sec.get("stab", ()):
                rhythm, ln = sp["stabs"][rname]
                s.stabs(bar, rhythm, ln, kind, bus, chord_at, sp.get("stab_lo", 57))
            for bus, kind in sec.get("pad", ()):
                s.pad(bar, halves, kind, bus, sp.get("pad_lo", 55))
            for bus, kind, pname in sec.get("arp", ()):
                s.arp(bar, sp["arps"][pname], kind, bus, chord_at, sp.get("arp_lo", 64))
        for item in sec.get("lead", ()):
            bus, kind, mel, octave, gate = item[:5]
            s.melody(bar0, nb, sp["melodies"][mel], kind, bus, octave, gate, item[5] if len(item) > 5 else 1.0)
        if sec.get("riser"):
            nr = sec["riser"]
            s.put("fx", d_riser(int(nr * 4 * s.beat)), bar0 + nb - nr, 0)
            s.put("cym", d_revcrash(int(min(nr, 1) * 4 * s.beat)), bar0 + nb - min(nr, 1), 0, 0.6)
        for buses, pts in sec.get("lp", ()):
            s.lp(buses, [(bar0 + rb, hz) for rb, hz in pts])
        bar0 += nb
    assert bar0 == s.bars, "%s: sections hold %d bars, song has %d" % (s.name, bar0, s.bars)


# =====================================================================================
# 7. Songs (all progressions, basslines, patterns and melodies original)
# =====================================================================================

DRUM_BUSES = ["kick", "snare", "hats", "perc", "toms", "x_hats", "x_perc"]
BASS_BUSES = ["sub", "m_bass", "x_bass", "x_pulse"]

# ---- race1 "Overdrive": 140 BPM, A minor, driving techno / breakbeat ---------------------------------
R1_PA = "Am Am Fmaj7 G Am Am Dm7 Esus4,E"
R1_PB = "F G Em7 Am F G Esus4 E"
R1_PK = "Fmaj7 G Am Am Fmaj7 G Dm7 Esus4,E"

RACE1 = dict(
    name="race1", bpm=140, bars=64, bass_lo=33, stab_lo=57, pad_lo=55, arp_lo=64, rt60=1.5, lufs=-14.0,
    drums={
        "intro": {"kick": "x...x...x...x...", "hat": "..o...o...o...o.", "shaker": "-.-.-.-.-.-.-.-."},
        "intro2": {"kick": "x...x...x...x...", "hat": "..o...o...o...o.", "shaker": "-.-.-.-.-.-.-.-.", "clap": "............o..."},
        "four": {"kick": "x...x...x...x...", "clap": "....x.......x...", "snare": "....o.......o...",
                 "ohat": "..o...o...o...o.", "hat": "-...-...-...-...", "shaker": "..-...-...-...-."},
        "four2": {"kick": "x...x...x...x...", "clap": "....x.......x...", "snare": "....o.......o..-",
                  "ohat": "..o...o...o...o.", "hat": "-...-...-...-...", "blip": "...x.....x....x.", "bliplo": "......x.......x."},
        "break": {"kick": "x......x..x.....", "bsnare": "....x....-..x.-.", "hat": "x.o.x.o.x.o.x.o.", "ohat": "..............o.",
                  "shaker": "-.-.-.-.-.-.-.-."},
        "break2": {"kick": "x..x......x..x..", "bsnare": "....x.-.....x...", "clap": "............x...", "hat": "x.o.x.o.x.o.xoo.",
                   "ohat": "......o.......o."},
        "brk": {"hat": "..-...-...-...-.", "shaker": "-.-.-.-.-.-.-.-.", "rim": "...........-...."},
        "bld": {"kick": "x...x...x...x...", "ohat": "..o...o...o...o."},
        "out": {"kick": "x...x...x...x...", "clap": "....x.......x...", "ohat": "..o...o...o...o.", "shaker": "-.-.-.-.-.-.-.-."},
        # intense-only layers (placed on x_ buses)
        "x16": {"hat": "x-o-x-o-x-o-x-o-", "ride": "..x...x...x...x."},
        "xperc": {"blip": "..x..x.x..x..x..", "zap": "...........x...x"},
        "xbrk": {"ride": "x.o.x.o.x.o.x.o.", "hat": ".-.-.-.-.-.-.-.-"},
    },
    bass={
        "roll": ". . 0 0 . . 12 0 . . 0 0 . . 12 7",
        "roll2": ". . 0 0 . 0 12 0 . . 0 0 . 7 12 0",
        "brkb": "0 - - 12 . 0 - . 0 12 . 0 - 7 12 0",
        "long": "0 - - - - - - - - - - - - - 7 -",
        "bld": "0 . 0 . 0 . 0 . 0 . 0 . 0 0 0 0",
        "acid": "0a . 12 0 . 0s 12a 0 . 7 0s 12 0a . 12s 7",
        "acid2": "0a 0 . 12s . 0 7a . 0 12 0s . 7a . 12 0s",
        "acidl": "0a - - 12s - - 0 . 0 - 7s - 12a - 0s -",
    },
    stabs={"A": ("..x..x..x.....x.", 1.5), "B": ("x..x..x...x..x..", 1.5), "O": ("..x.....x.....x.", 1.5)},
    arps={"up": ("0 1 2 3 4 3 2 1", 1.3), "climb": ("0 2 1 3 2 4 3 5", 1.3), "slow": ("0 . 2 . 4 . 2 .", 2.5)},
    melodies={
        "A": "A5:.75 C6:.75 E6:.5 D6:.5 C6:.5 B5:.5 C6:.5 | A5:.75 E5:.75 A5:.5 r:1 G5:.5 A5:.5 |"
             " C6:.75 A5:.75 F5:.5 E6:1 C6:1 | D6:.75 B5:.75 G5:.5 D6:.5 E6:.5 D6:1 |"
             " A5:.75 C6:.75 E6:.5 G6:.5 E6:.5 D6:.5 C6:.5 | E6:.75 C6:.75 A5:.5 r:1 A5:.5 B5:.5 |"
             " C6:.75 D6:.75 F6:.5 E6:.5 D6:.5 C6:.5 A5:.5 | B5:1 A5:.5 B5:.5 G#5:1.5 E5:.5",
        "B": "A5:1.5 C6:.5 F6:2 | G6:1.5 F6:.5 D6:2 | E6:1 G6:1 B6:1.5 A6:.5 | A6:3 r:1 |"
             " A5:1.5 C6:.5 F6:1.5 E6:.5 | D6:1 G6:1 B6:1 D7:1 | B6:1.5 A6:.5 E6:2 | G#6:2 B6:1 E7:1",
        "K": "C6:1.5 A5:.5 E6:2 | D6:1.5 B5:.5 G5:2 | C6:1 E6:1 A6:2 | r:4 |"
             " C6:1.5 A5:.5 E6:2 | D6:1.5 G6:.5 B6:2 | A6:1 F6:1 D6:2 | B5:2 G#5:2",
        "BLD": "A5:1 C6:1 F6:2 | B5:1 D6:1 G6:2 | A5:.5 B5:.5 E6:1 A6:2 | G#6:1 E6:1 B5:1 G#6:1",
    },
    sections=[
        dict(bars=4, chords="Am Am Fmaj7 G", drums=[("intro", "")], pad=[("pad", "dark")],
             lp=[(DRUM_BUSES, [(0, 380), (4, 380)])]),
        dict(bars=4, chords="Am Am Dm7 Esus4,E", drums=[("intro2", "")], fill="snare", riser=2,
             bass=[("sub", "sub", "roll"), ("m_bass", "roll", "roll"), ("x_bass", "acid", "acid")], stab=[("stab", "rave", "O")],
             lp=[(DRUM_BUSES + BASS_BUSES + ["stab"], [(0, 380), (2.5, 1400), (3.75, 5000), (4, 19500)])]),
        dict(bars=8, chords=R1_PA, drums=[("four", ""), ("x16", "x_")], crash=True, impact=True, fill="toms",
             bass=[("sub", "sub", "roll"), ("m_bass", "roll", "roll"), ("x_bass", "acid", "acid")], stab=[("stab", "rave", "A")],
             lead=[("x_lead", "saw", "A", 0, 0.92)]),
        dict(bars=8, chords=R1_PA, drums=[("four2", ""), ("x16", "x_"), ("xperc", "x_")], fill="snare", riser=1,
             bass=[("sub", "sub", "roll2"), ("m_bass", "roll", "roll2"), ("x_bass", "acid", "acid2")], stab=[("stab", "rave", "A")],
             arp=[("arp", "pluck", "up")], lead=[("hook", "pluck", "A", 0, 0.9), ("x_lead", "saw", "A", 0, 0.92)]),
        dict(bars=8, chords=R1_PB, drums=[("break", ""), ("xbrk", "x_")], crash=True, impact=True, fill="break",
             bass=[("sub", "sub", "brkb"), ("m_bass", "roll", "brkb"), ("x_bass", "acid", "acid2")], stab=[("stab", "rave", "B")],
             pad=[("pad", "warm")], lead=[("x_lead", "saw", "B", 0, 0.95)]),
        dict(bars=8, chords=R1_PK, drums=[("brk", "")], crash=True, down=True,
             bass=[("sub", "sub", "long"), ("x_bass", "acid", "acidl")], pad=[("pad", "warm")], arp=[("arp", "pluck", "climb")],
             lead=[("keys", "bell", "K", 0, 1.0), ("x_lead", "saw", "K", 0, 0.95, 0.6)],
             lp=[(["arp", "x_bass"], [(0, 500), (7.9, 4500)])]),
        dict(bars=4, chords="Fmaj7 G Esus4 E", drums=[("bld", "")], roll=4, riser=4,
             bass=[("sub", "sub", "bld"), ("m_bass", "roll", "bld"), ("x_bass", "acid", "bld")], pad=[("pad", "warm")],
             arp=[("arp", "pluck", "up")], lead=[("x_lead", "saw", "BLD", 0, 0.92)],
             lp=[(DRUM_BUSES + BASS_BUSES, [(0, 450), (3.5, 3000), (4, 19500)])]),
        dict(bars=8, chords=R1_PA, drums=[("four2", ""), ("x16", "x_"), ("xperc", "x_")], crash=True, impact=True, fill="snare",
             bass=[("sub", "sub", "roll"), ("m_bass", "roll", "roll"), ("x_bass", "acid", "acid")], stab=[("stab", "rave", "A")],
             arp=[("arp", "pluck", "up")], lead=[("hook", "pluck", "A", 0, 0.9), ("x_lead", "saw", "A", 0, 0.92)]),
        dict(bars=8, chords=R1_PB, drums=[("break2", ""), ("xbrk", "x_"), ("xperc", "x_")], crash=True, fill="toms",
             bass=[("sub", "sub", "brkb"), ("m_bass", "roll", "brkb"), ("x_bass", "acid", "acid2")], stab=[("stab", "rave", "B")],
             pad=[("pad", "warm")], arp=[("arp", "pluck", "climb")],
             lead=[("hook", "pluck", "B", 0, 0.9, 0.8), ("x_lead", "saw", "B", 0, 0.95)]),
        dict(bars=2, chords="Am Am", drums=[("out", ""), ("x16", "x_")], crash=True,
             bass=[("sub", "sub", "roll"), ("m_bass", "roll", "roll"), ("x_bass", "acid", "acid")], stab=[("stab", "rave", "O")]),
        dict(bars=2, chords="Fmaj7 G", drums=[("out", "")], stab=[("stab", "rave", "O")], pad=[("pad", "dark")]),
    ],
    # outro filter closes over the last 4 bars onto the intro's 380 Hz: the loop seam is continuous
    tail_lp=[(DRUM_BUSES + BASS_BUSES + ["stab"], [(60, 19500), (62, 2500), (64, 380)])],
    mix=mixcfg(),
)

# ---- race2 "Iron Lung": 150 BPM, C minor / Phrygian, industrial breakbeat -------------------------------
R2_PA = "Cm Cm Db Cm Cm Cm Ab G"
R2_PB = "Ab Bb Cm Cm Ab Bb Db G"
R2_PK = "Fm Fm Db Db Ab Ab G G"

RACE2 = dict(
    name="race2", bpm=150, bars=64, bass_lo=30, stab_lo=55, pad_lo=53, arp_lo=48, rt60=1.3, lufs=-14.0,
    kit={"kick": (lambda: d_kick_ind(), "kick", 0.0), "snare": (lambda: d_isnare(), "snare", 0.0)},
    drums={
        "intro": {"metal": "x..x..x...x..x..", "hat": "..x...x...x...x.", "anvil": "x..............."},
        "intro2": {"kick": "x.........x.....", "metal": "x..x..x...x..x..", "hat": "x.x.x.x.x.x.x.x.", "anvil": "x..............."},
        "brkA": {"kick": "x.x.......x..x..", "snare": "....x..-.x..x..-", "hat": "x.x.x.x.x.xxx.x.", "metal": "......x.......x."},
        "brkB": {"kick": "x.....xx..x.....", "snare": "....x.-...-.x...", "clap": "....x.......x...", "hat": "x.x.x.x.x.x.x.x.",
                 "ohat": "..............o.", "anvil": "...........x...."},
        "stomp": {"kick": "x.......x.x.....", "snare": "........x.......", "clap": "........x.......", "metal": "..x...x...x...x.",
                  "hat": "x-x-x-x-x-x-x-x-"},
        "brk": {"anvil": "x.......x.......", "hat": "..-...-...-...-.", "zap": "...........-...."},
        "bld": {"kick": "x...x...x...x...", "hat": "x-x-x-x-x-x-x-x-"},
        "out": {"kick": "x.x.......x..x..", "snare": "....x.......x...", "metal": "x..x..x...x..x.."},
        "x16": {"hat": "-x-x-x-x-x-x-x-x", "ride": "x.o.x.o.x.o.x.o."},
        "xmetal": {"metal": ".x..x.x..x..x.x.", "zap": "...x.......x...."},
        "xride": {"ride": "x.x.x.x.x.x.x.x.", "hat": "-x-x-x-x-x-x-x-x"},
    },
    bass={
        "A": "0 - - 0 - - 12 - 0 - 0 - - 7 12 -",
        "B": "0 - - - - - 0 - 12 - - - 0 - 7 -",
        "long": "0 - - - - - - - - - - - - - - -",
        "bld": "0 . 0 . 0 . 0 . 0 0 0 0 0 0 0 0",
        "pulse": "12a 12 0 12 12a 0 12 12 0a 12 12 0 12a 12 0 12",
        "pulseB": "12a . 12 12 . 12 12a . 12 . 12 12 12a . 12 12",
    },
    stabs={"A": ("x..x..x...x.....", 1.5), "B": ("x.......x..x....", 3.0), "O": ("x.........x.....", 2.0)},
    arps={"riff": ("0 . 0 1 . 0 2 . 0 . 1 0 . 2 1 .", 1.0), "dark": ("0 . 1 . 2 . 3 . 4 . 3 . 2 . 1 .", 2.0)},
    melodies={
        "A": "C6:.5 C6:.25 r:.25 Eb6:.5 C6:.5 Db6:.75 C6:.75 G5:.5 | Bb5:.75 G5:.75 Eb5:.5 F5:1 G5:1 |"
             " Ab5:.5 Ab5:.25 r:.25 F5:.5 Db6:.5 C6:.75 Ab5:.75 F5:.5 | G5:1.5 Eb5:.5 C5:1 r:1 |"
             " C6:.5 C6:.25 r:.25 Eb6:.5 G6:.5 F6:.75 Eb6:.75 Db6:.5 | C6:.75 G5:.75 Eb5:.5 G5:.5 C6:.5 Eb6:1 |"
             " Eb6:.75 C6:.75 Ab5:.5 C6:.5 Eb6:.5 Ab6:1 | G6:1.5 F6:.5 D6:.5 B5:.5 G5:1",
        "B": "C6:1.5 Eb6:.5 Ab6:2 | F6:1.5 D6:.5 Bb5:2 | G6:1 Eb6:1 C6:1 Eb6:1 | G6:3 r:1 |"
             " C6:1 Eb6:1 Ab6:1.5 G6:.5 | F6:1 D6:1 Bb6:1.5 Ab6:.5 | F6:1 Ab6:1 Db7:1.5 C7:.5 | B6:2 D7:1 G6:1",
        "K": "C6:2 Ab5:1 F5:1 | G5:2 Ab5:2 | F5:2 Db5:1 F5:1 | Ab5:4 | Eb6:2 C6:1 Ab5:1 | G5:2 Eb5:2 |"
             " D5:2 G5:1 B5:1 | D6:4",
        "BLD": "F5:1 Ab5:1 C6:2 | F5:1 Ab5:1 Db6:2 | D6:1 G6:1 B6:2 | B6:.5 G6:.5 D6:.5 B5:.5 G5:.5 B5:.5 D6:.5 G6:.5",
    },
    sections=[
        dict(bars=4, chords="Cm Cm Cm Cm", drums=[("intro", "")], pad=[("pad", "dark")],
             lp=[(DRUM_BUSES, [(0, 500), (4, 500)])]),
        dict(bars=4, chords="Cm Cm Db G", drums=[("intro2", "")], fill="metal", riser=2,
             bass=[("sub", "sub", "A"), ("m_bass", "reese", "A"), ("x_bass", "reese_hard", "A")], pad=[("pad", "dark")],
             lp=[(DRUM_BUSES + BASS_BUSES, [(0, 500), (2.5, 1600), (3.75, 5000), (4, 19500)])]),
        dict(bars=8, chords=R2_PA, drums=[("brkA", ""), ("x16", "x_")], crash=True, impact=True, fill="toms",
             bass=[("sub", "sub", "A"), ("m_bass", "reese", "A"), ("x_bass", "reese_hard", "A"), ("x_pulse", "pulse", "pulse")],
             stab=[("stab", "metal", "A")], lead=[("x_lead", "dist", "A", 0, 0.9)]),
        dict(bars=8, chords=R2_PA, drums=[("brkB", ""), ("x16", "x_"), ("xmetal", "x_")], fill="snare", riser=1,
             bass=[("sub", "sub", "A"), ("m_bass", "reese", "A"), ("x_bass", "reese_hard", "A"), ("x_pulse", "pulse", "pulse")],
             stab=[("stab", "metal", "A")], arp=[("riff", "metal", "riff")], lead=[("x_lead", "dist", "A", 0, 0.9)]),
        dict(bars=8, chords=R2_PB, drums=[("stomp", ""), ("xride", "x_")], crash=True, impact=True, fill="metal",
             bass=[("sub", "sub", "B"), ("m_bass", "reese", "B"), ("x_bass", "reese_hard", "B"), ("x_pulse", "pulse", "pulseB")],
             stab=[("stab", "metal", "B")], pad=[("pad", "choir")], lead=[("x_lead", "dist", "B", 0, 0.95)]),
        dict(bars=8, chords=R2_PK, drums=[("brk", "")], crash=True, down=True,
             bass=[("sub", "sub", "long"), ("m_bass", "reese", "long"), ("x_bass", "reese_hard", "long")],
             pad=[("pad", "choir")], arp=[("arp", "metal", "dark")],
             lead=[("keys", "bell", "K", 0, 1.0), ("x_lead", "saw", "K", 0, 0.95, 0.6)],
             lp=[(["arp", "m_bass", "x_bass"], [(0, 400), (7.9, 3500)])]),
        dict(bars=4, chords="Fm Db G G", drums=[("bld", "")], roll=4, riser=4,
             bass=[("sub", "sub", "bld"), ("m_bass", "reese", "bld"), ("x_bass", "reese_hard", "bld")], pad=[("pad", "choir")],
             lead=[("x_lead", "dist", "BLD", 0, 0.92)],
             lp=[(DRUM_BUSES + BASS_BUSES, [(0, 450), (3.5, 3000), (4, 19500)])]),
        dict(bars=8, chords=R2_PA, drums=[("brkA", ""), ("x16", "x_"), ("xmetal", "x_")], crash=True, impact=True, fill="snare",
             bass=[("sub", "sub", "A"), ("m_bass", "reese", "A"), ("x_bass", "reese_hard", "A"), ("x_pulse", "pulse", "pulse")],
             stab=[("stab", "metal", "A")], arp=[("riff", "metal", "riff")], lead=[("x_lead", "dist", "A", 0, 0.9)]),
        dict(bars=8, chords=R2_PB, drums=[("stomp", ""), ("xride", "x_"), ("xmetal", "x_")], crash=True, fill="toms",
             bass=[("sub", "sub", "B"), ("m_bass", "reese", "B"), ("x_bass", "reese_hard", "B"), ("x_pulse", "pulse", "pulseB")],
             stab=[("stab", "metal", "B")], pad=[("pad", "choir")], arp=[("riff", "metal", "riff")],
             lead=[("keys", "bell", "B", -1, 0.9, 0.7), ("x_lead", "dist", "B", 0, 0.95)]),
        dict(bars=2, chords="Cm Cm", drums=[("out", ""), ("x16", "x_")], crash=True,
             bass=[("sub", "sub", "A"), ("m_bass", "reese", "A"), ("x_bass", "reese_hard", "A")], stab=[("stab", "metal", "O")]),
        dict(bars=2, chords="Db G", drums=[("out", "")], stab=[("stab", "metal", "O")], pad=[("pad", "dark")]),
    ],
    tail_lp=[(DRUM_BUSES + BASS_BUSES + ["stab", "riff"], [(60, 19500), (62, 2800), (64, 500)])],
    mix=mixcfg(snare=dict(peak=-8.5, rev=0.1, drive=1.6), perc=dict(rms=-26.5, rev=0.15, hp=200), kick=dict(peak=-6.0, drive=1.3),
               m_bass=dict(rms=-20.5, duck=0.4, hp=60), x_bass=dict(rms=-20.0, duck=0.4, hp=60), stab=dict(rms=-21.0, rev=0.2, dly=0.12, duck=0.3, hp=180),
               pad=dict(rms=-25.5, rev=0.4, duck=0.4, hp=200), x_lead=dict(rms=-20.0, rev=0.18, dly=0.22, hp=250)),
)

# ---- menu "Low Orbit": 110.25 BPM (exactly 24000 samples per beat), D major, progressive / ambient ---------
PM_A = "Gmaj7 A6 F#m7 Bm7 Gmaj7 A6 Bm7 Bm7"
PM_B = "Em7 Gmaj7 Dmaj7 A Em7 Gmaj7 Bm7 Asus4,A"

MENU = dict(
    name="menu", bpm=110.25, bars=48, swing=0.06, bass_lo=31, stab_lo=57, pad_lo=55, arp_lo=62, rt60=2.4, lufs=-15.0,
    kit={"kick": (lambda: d_kick(54.0, 0.24, 0.4, 1.2), "kick", 0.0)},
    drums={
        "light": {"kick": "x.........x.....", "rim": "....-.......-...", "shaker": "-.-.-.-.-.-.-.-.", "hat": "..o...o...o...o."},
        "full": {"kick": "x.......x.x.....", "snare": "....o.......o...", "clap": "....-.......-...", "hat": "..o...o...o...o.",
                 "shaker": "o-o-o-o-o-o-o-o-"},
        "brk": {"shaker": "-.-.-.-.-.-.-.-.", "hat": "..-...-...-...-."},
        "outro": {"kick": "x.........x.....", "hat": "..o...o...o...o.", "shaker": "-.-.-.-.-.-.-.-."},
    },
    bass={"pulse": "0 - - 0 . . 0 - . . 0 - 12 - 7 -", "long": "0 - - - - - - - - - - - 7 - - -"},
    stabs={"comp": ("x.....x......o..", 5.0)},
    arps={"m16": ("0 1 2 4 3 1 2 4", 1.6), "m8": ("0 . 2 . 4 . 3 .", 3.0)},
    melodies={
        "B": "B5:1.5 G5:.5 E5:1 F#5:1 | D6:1.5 B5:.5 F#6:2 | E6:1 C#6:1 A5:1.5 F#5:.5 | E5:3 r:1 |"
             " B5:1.5 D6:.5 E6:1 G6:1 | F#6:1.5 D6:.5 B5:2 | A5:1 B5:1 D6:1 F#6:1 | E6:2 C#6:2",
        "K": "F#6:1 D6:1 A5:2 | E6:1 C#6:1 A5:2 | C#6:1 A5:1 F#5:2 | D6:2 F#6:2 |"
             " F#6:1 D6:1 B5:2 | E6:1 C#6:1 A5:2 | D6:1 B5:1 F#5:2 | F#5:4",
    },
    sections=[
        dict(bars=8, chords=PM_A, pad=[("pad", "warm")], arp=[("arp", "fm", "m16")],
             lp=[(["arp"], [(0, 600), (8, 4000)])]),
        dict(bars=8, chords=PM_A, drums=[("light", "")], bass=[("sub", "round", "pulse")], pad=[("pad", "warm")],
             arp=[("arp", "fm", "m16")], stab=[("stab", "keys", "comp")], fill="soft"),
        dict(bars=8, chords=PM_B, drums=[("full", "")], crash=True, bass=[("sub", "round", "pulse")], pad=[("pad", "warm")],
             arp=[("arp", "fm", "m16")], lead=[("lead", "soft", "B", 0, 0.95)], fill="soft", riser=1),
        dict(bars=8, chords=PM_A, drums=[("brk", "")], bass=[("sub", "round", "long")], pad=[("pad", "glass")],
             arp=[("arp", "fm", "m8")], lead=[("keys", "glass", "K", 0, 1.0)], down=True),
        dict(bars=8, chords=PM_B, drums=[("full", "")], crash=True, bass=[("sub", "round", "pulse")], pad=[("pad", "warm")],
             arp=[("arp", "fm", "m16")], stab=[("stab", "keys", "comp")],
             lead=[("lead", "soft", "B", 0, 0.95), ("keys", "bell", "B", 1, 0.9, 0.5)], fill="soft"),
        dict(bars=4, chords="Gmaj7 A6 F#m7 Bm7", drums=[("outro", "")], bass=[("sub", "round", "long")], pad=[("pad", "warm")],
             arp=[("arp", "fm", "m16")]),
        dict(bars=4, chords="Gmaj7 A6 Bm7 Bm7", pad=[("pad", "warm")], arp=[("arp", "fm", "m16")],
             lp=[(["arp"], [(0, 4000), (4, 600)])]),
    ],
    mix=mixcfg(kick=dict(peak=-9.0), snare=dict(peak=-12.0, rev=0.25), hats=dict(rms=-28.0, hp=4500), perc=dict(rms=-29.0, rev=0.2, hp=300),
               sub=dict(rms=-20.0, duck=0.3, lp=500), stab=dict(rms=-24.0, rev=0.3, dly=0.15, duck=0.15, hp=180),
               pad=dict(rms=-22.5, rev=0.45, duck=0.2, hp=150), arp=dict(rms=-24.5, rev=0.35, dly=0.45, duck=0.1, hp=250),
               lead=dict(rms=-20.0, rev=0.35, dly=0.35, hp=220), keys=dict(rms=-21.0, rev=0.45, dly=0.35, hp=250)),
)


def render_spec(sp):
    s = Song(sp["name"], sp["bpm"], sp["bars"], sp.get("swing", 0.0), kit=sp.get("kit"), rt60=sp.get("rt60", 1.6))
    arrange(s, sp)
    for buses, pts in sp.get("tail_lp", ()):
        s.lp(buses, pts)
    return s


def song_grid():
    """Pre-race tension loop, 140 BPM, 8 bars: filtered kick slowly opening, sub pulse, dark drone,
    endlessly rising Shepard tone (one octave per 4 bars), hats and blips entering, soft snare build."""
    s = Song("grid", 140, 8, rt60=1.8)
    n = s.n
    for bar in range(8):
        s.pattern(bar, {"kick": "x...x...x...x..."})
        for st in (2, 6, 10, 14):
            s.put("sub", v_bass("sub", 33, s.dur(1.5), False, None), bar, st, 1.0 if st == 14 else 0.85)
        if bar >= 2:
            s.pattern(bar, {"hat": "..o...o...o...o."})
        if bar >= 4:
            s.pattern(bar, {"shaker": "-.-.-.-.-.-.-.-.", "rim": "...........-...."})
        if bar >= 6:
            s.pattern(bar, {"blip": "x..x..x..x..x.x."})
        if bar % 2 == 0:
            s.put("keys", v_lead("bell", 81 if bar % 4 == 0 else 76, int(2.0 * s.beat)), bar, 0, 0.8)
    for k, st in enumerate(range(0, 16, 2)):
        s.drum("snare", 6, st, 0.18 + 0.02 * k)
    for st in range(16):
        s.drum("snare", 7, st, 0.25 + 0.035 * st)
    s.lp(["kick"], [(0, 260), (8, 900)])
    s.put("drone", loop_drone(n, (45, 52, 57, 58), "grid_drone"), 0, 0)
    half = n // 2
    shep = np.tile(shepard(half, "grid_shep"), 2)
    s.put("fx", np.stack([shep, np.roll(shep, 300)]), 0, 0)
    cfg = mixcfg(kick=dict(peak=-6.0), sub=dict(rms=-19.0, duck=0.5, lp=180), fx=dict(rms=-25.0, rev=0.3, hp=100),
                 drone=dict(rms=-25.0, rev=0.3, hp=100, duck=0.3), keys=dict(rms=-25.0, rev=0.4, dly=0.4, hp=300),
                 snare=dict(peak=-14.0, rev=0.2), hats=dict(rms=-29.0, hp=5000), perc=dict(rms=-30.0, rev=0.1, hp=300))
    return s, cfg


def song_victory():
    """Triumphant sting, 128 BPM: bVI - bVII - I hits, rising run, held A major with bell sparkle."""
    s = Song("victory", 128, 3, circular=False, tail=1.5, rt60=2.0)
    hits = [(0, ("F3", "A3", "C4", "F4"), 2.0, 0.85), (3, ("G3", "B3", "D4", "G4"), 2.0, 0.9),
            (6, ("A3", "C#4", "E4", "A4"), 9.0, 1.0), (16, ("D4", "F#4", "A4"), 3.0, 0.7),
            (24, ("E4", "G#4", "B4"), 3.0, 0.75), (32, ("A3", "D4", "E4", "A4"), 4.0, 0.9),
            (36, ("A3", "C#4", "E4", "A4", "C#5"), 12.0, 1.0)]
    for st, names, ln, g in hits:
        notes = tuple(nn(x) for x in names)
        s.put("stab", v_stab("brass", notes, s.dur(ln)), 0, st, g)
        s.put("sub", v_bass("sub", notes[0] - 12, s.dur(min(ln, 8.0)), False, None), 0, st, g)
        s.drum("kick", 0, st, 1.0)
    for st in (6, 32, 36):
        s.drum("crash", 0, st, 0.9)
    s.put("fx", d_impact(), 0, 6, 0.7)
    s.put("fx", d_impact(), 0, 36, 0.8)
    run = "r:4 | F#5:.5 A5:.5 D6:.5 F#6:.5 E6:.5 G#6:.5 B6:1 | A6:4"
    s.melody(0, 3, run, "saw", "lead", 0, 0.95)
    s.melody(0, 3, run, "bell", "keys", 0, 1.0, 0.6)
    for st in range(16, 32, 2):
        s.drum("snare", 0, st, 0.3 + 0.03 * (st - 16))
    for st in range(24, 32):
        s.drum("snare", 0, st, 0.5 + 0.05 * (st - 24))
    for i, m in enumerate((81, 85, 88, 93, 97, 100)):
        s.put("keys", v_lead("bell", m, int(1.5 * s.beat)), 0, 36 + 1.0 * i, 0.5)
    for st, nm in ((36, "toml"), (38, "tomm"), (39, "tomm"), (40, "toml")):
        s.drum(nm, 0, st, 0.8)
    s.put("pad", v_pad("warm", (57, 61, 64, 69), int(3.0 * s.beat + 1.4 * MSR)), 0, 36, 0.8)
    cfg = mixcfg(stab=dict(rms=-19.0, rev=0.3, dly=0.1), lead=dict(rms=-19.5, rev=0.3, dly=0.25, hp=220),
                 keys=dict(rms=-23.0, rev=0.4, dly=0.3, hp=300), pad=dict(rms=-24.0, rev=0.4, hp=150),
                 sub=dict(rms=-21.0, lp=200), snare=dict(peak=-11.0, rev=0.2), fx=dict(peak=-10.0, rev=0.2))
    return s, cfg


def song_defeat():
    """Downbeat sting, 96 BPM: Am - Fmaj7 - Dm6 - Am, falling line, closing filter."""
    s = Song("defeat", 96, 2, circular=False, tail=0.8, rt60=2.4)
    chords = [(0, "Am", 8), (8, "Fmaj7", 8), (16, "Dm6", 6), (22, "E", 4), (26, "Am", 6)]
    for st, c, ln in chords:
        s.put("pad", v_pad("dark", tuple(voicing(c, 52)), s.dur(ln + 2)), 0, st, 0.9)
        s.put("sub", v_bass("sub", bass_note(c, 28), s.dur(ln), False, None), 0, st, 0.9)
    s.melody(0, 2, "E5:1 D5:1 C5:1 B4:1 | A4:1.5 G#4:.5 A4:2", "soft", "lead", 0, 0.98)
    s.melody(0, 2, "E5:1 D5:1 C5:1 B4:1 | A4:1.5 G#4:.5 A4:2", "glass", "keys", 0, 1.0, 0.5)
    s.put("fx", d_impact(), 0, 0, 0.6)
    s.put("fx", d_down(int(6 * s.beat)), 0, 0, 0.4)
    s.drum("kick_soft", 0, 0, 1.0)
    s.drum("crash", 0, 0, 0.5)
    s.lp(["pad", "lead", "keys"], [(0, 6000), (1.0, 3500), (2.0, 900), (2.33, 400)])
    cfg = mixcfg(pad=dict(rms=-21.0, rev=0.45, hp=120), lead=dict(rms=-20.0, rev=0.45, dly=0.3, hp=200),
                 keys=dict(rms=-25.0, rev=0.5, dly=0.3, hp=250), sub=dict(rms=-21.0, lp=180), fx=dict(peak=-10.0, rev=0.3),
                 kick=dict(peak=-10.0), cym=dict(peak=-16.0, rev=0.3, hp=1500))
    return s, cfg


OGG_QUALITY = 5
SONG_SPECS = {"menu": MENU, "race1": RACE1, "race2": RACE2}
MUSIC_JOBS = ["race1", "race2", "menu", "grid", "victory", "defeat"]   # heaviest first


def _music_job(name):
    """Render one composition (both versions for the race songs) and write its OGG file(s)."""
    t0 = time.time()
    lines = []
    if name in SONG_SPECS:
        sp = SONG_SPECS[name]
        s = render_spec(sp)
        versions = (("main", "_main"), ("intense", "_intense")) if name.startswith("race") else (("all", ""),)
        t1 = time.time()
        mixes = s.mixdowns(sp["mix"], [v for v, _ in versions], sp.get("lufs", -14.0))
        t2 = time.time()
        for v, suffix in versions:
            lines.append(write_ogg("music/%s%s.ogg" % (name, suffix), mixes.pop(v), MSR, OGG_QUALITY))
        lines.append("    (%s: compose %.1f s, mix %.1f s)" % (name, t1 - t0, t2 - t1))
    else:
        s, cfg = {"grid": song_grid, "victory": song_victory, "defeat": song_defeat}[name]()
        target = {"grid": -15.0, "victory": -14.0, "defeat": -15.5}[name]
        y = s.mixdowns(cfg, ("all",), target)["all"]
        if not s.circular:
            y = fade(y, MSR, 0.0, 0.25)
        lines.append(write_ogg("music/%s.ogg" % name, y, MSR, OGG_QUALITY))
    lines.append("    (%s rendered in %.1f s)" % (name, time.time() - t0))
    return lines


def build_music(jobs=2):
    print("music", flush=True)
    names = list(MUSIC_JOBS)
    if jobs > 1:
        from concurrent.futures import ProcessPoolExecutor
        with ProcessPoolExecutor(max_workers=min(jobs, len(names))) as ex:
            results = list(ex.map(_music_job, names))
    else:
        results = [_music_job(nm) for nm in names]
    for lines in results:
        for ln in lines:
            print(ln, flush=True)


# =====================================================================================
# 8. Verification
# =====================================================================================

ENGINE_FILES = [(name, secs) for name, secs, _, _ in LOOPS]
SFX_FILES = [name for name, _, _ in SFX]
MUSIC_FILES = [  # name, loop, expected samples (None = no fixed length), samples per bar
    ("menu", True, 48 * 4 * 24000, 4 * 24000), ("grid", True, 8 * 4 * 18900, 4 * 18900),
    ("race1_main", True, 64 * 4 * 18900, 4 * 18900), ("race1_intense", True, 64 * 4 * 18900, 4 * 18900),
    ("race2_main", True, 64 * 4 * 17640, 4 * 17640), ("race2_intense", True, 64 * 4 * 17640, 4 * 17640),
    ("victory", False, None, None), ("defeat", False, None, None),
]


def _read_wav(path):
    with wave.open(path, "rb") as w:
        sr, ch, sw, n = w.getframerate(), w.getnchannels(), w.getsampwidth(), w.getnframes()
        data = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float64) / 32768.0
    return sr, ch, sw, data.reshape(-1, ch).T


def _read_ogg(path):
    pr = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
                         "stream=codec_name,sample_rate,channels", "-of", "default=nw=1", path],
                        capture_output=True, text=True, check=True).stdout
    info = dict(line.split("=", 1) for line in pr.strip().splitlines())
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-acodec", "pcm_f32le", "-"],
                         capture_output=True, check=True).stdout
    ch = int(info["channels"])
    data = np.frombuffer(raw, dtype="<f4").astype(np.float64).reshape(-1, ch).T
    lo = subprocess.run(["ffmpeg", "-nostats", "-v", "info", "-i", path, "-af", "ebur128=framelog=quiet", "-f", "null", "-"],
                        capture_output=True, text=True).stderr
    integ = None
    for line in lo.splitlines():
        if line.strip().startswith("I:") and "LUFS" in line:
            integ = float(line.split()[1])
    return int(info["sample_rate"]), ch, info["codec_name"], data, integ


def seam_metrics(x, sr, period=None):
    """Loop seam check on (ch, n), comparing the wrap point with comparable points inside the file
    (bar lines for music, 63 evenly spaced points otherwise):
      jump  |last - first sample| / 99.9th percentile of ordinary sample steps (< 1: an ordinary step)
      drms  level change between the 10 ms before and after the seam, in dB of excess over the
            95th percentile of the same measure at the reference points (0: nothing unusual)
      click high-frequency energy (2nd differences, +-9 samples) at the seam / median of the same
            measure 3-25 ms either side of it (about 1: no local spike at the wrap)"""
    n = x.shape[-1]
    steps = np.abs(np.diff(x, axis=-1))
    jump = float(np.max(np.abs(x[:, 0] - x[:, -1]))) / (np.percentile(steps, 99.9) + 1e-12)
    k = int(0.01 * sr)

    def lvl(i):
        a = x[:, np.arange(i - k, i) % n]
        b = x[:, np.arange(i, i + k) % n]
        return abs(to_db(rms(a)) - to_db(rms(b)))

    def hf(i):
        seg = x[:, np.arange(i - 9, i + 9) % n]
        return float(np.sqrt(np.mean(np.diff(seg, 2, axis=-1) ** 2)))
    pts = ([int(round(i * period)) for i in range(1, int(round(n / period)))] if period
           else [int(i * n / 64) for i in range(1, 64)])
    drms = max(0.0, lvl(0) - float(np.percentile([lvl(i) for i in pts], 95)))
    near = [int(s_ * ms * sr / 1000.0) for ms in (3, 6, 12, 25) for s_ in (-1, 1)]
    # Floor the local baseline at 5 % of the file's typical high-frequency level at the reference
    # points: a quiet wrap (intro/outro) otherwise divides two near-silent values and reports a
    # "click" that is ~40 dB below the music around it.
    floor = 0.05 * float(np.median([hf(i) for i in pts]))
    return jump, drms, hf(0) / (max(float(np.median([hf(i) for i in near])), floor) + 1e-12)


def check():
    rows = []
    ok = True
    sizes = {}

    def add(rel, sr, ch, n, x, loop, extra="", lufs_i=None, expect_sr=None, expect_ch=None, expect_n=None, secs=None,
            period=None):
        nonlocal ok
        pk = to_db(np.max(np.abs(x)))
        rm = to_db(rms(x))
        dc = float(np.max(np.abs(np.mean(x, axis=-1))))
        notes = []
        if expect_sr and sr != expect_sr:
            notes.append("SR!")
        if expect_ch and ch != expect_ch:
            notes.append("CH!")
        if expect_n is not None and n != expect_n:
            notes.append("LEN %d!=%d" % (n, expect_n))
        if secs is not None and abs(n / sr - secs) > 0.002:
            notes.append("DUR!")
        if pk > -1.0:
            notes.append("PEAK>-1")
        if dc > 0.002:
            notes.append("DC %.4f" % dc)
        seam = ""
        if loop:
            j, dr, cl = seam_metrics(x, sr, period)
            seam = "%5.2f %5.2f %5.2f" % (j, dr, cl)
            if j > 1.0 or dr > 1.0 or cl > 4.0:
                notes.append("SEAM?")
        if notes:
            ok = False
        rows.append((rel, sr, ch, n / sr, pk, rm, "" if lufs_i is None else "%.1f" % lufs_i, seam, extra + " ".join(notes)))

    for name, secs in ENGINE_FILES:
        rel = "engine/%s.wav" % name
        path = os.path.join(OUT, rel)
        if not os.path.exists(path):
            rows.append((rel, 0, 0, 0, 0, 0, "", "", "MISSING"))
            ok = False
            continue
        sr, ch, sw, x = _read_wav(path)
        add(rel, sr, ch, x.shape[-1], x, True, "" if sw == 2 else "16bit! ", expect_sr=SR, expect_ch=1, secs=secs)
    for name in SFX_FILES:
        rel = "sfx/%s.wav" % name
        path = os.path.join(OUT, rel)
        if not os.path.exists(path):
            rows.append((rel, 0, 0, 0, 0, 0, "", "", "MISSING"))
            ok = False
            continue
        sr, ch, sw, x = _read_wav(path)
        tail = to_db(np.max(np.abs(x[:, -16:])))
        add(rel, sr, ch, x.shape[-1], x, False, ("" if sw == 2 else "16bit! ") + ("" if tail < -60 else "tail %.0fdB " % tail),
            expect_sr=SR, expect_ch=1)
    lens = {}
    for name, loop, expect, period in MUSIC_FILES:
        rel = "music/%s.ogg" % name
        path = os.path.join(OUT, rel)
        if not os.path.exists(path):
            rows.append((rel, 0, 0, 0, 0, 0, "", "", "MISSING"))
            ok = False
            continue
        sr, ch, codec, x, integ = _read_ogg(path)
        lens[name] = x.shape[-1]
        add(rel, sr, ch, x.shape[-1], x, loop, "" if codec == "vorbis" else codec + "! ", integ,
            expect_sr=MSR, expect_ch=2, expect_n=expect, period=period)
    for a, b in (("race1_main", "race1_intense"), ("race2_main", "race2_intense")):
        if a in lens and b in lens and lens[a] != lens[b]:
            ok = False
            print("LENGTH MISMATCH %s %s" % (a, b))
    for folder in ("engine", "sfx", "music"):
        d = os.path.join(OUT, folder)
        sizes[folder] = sum(os.path.getsize(os.path.join(d, f)) for f in os.listdir(d)) if os.path.isdir(d) else 0

    print("%-28s %6s %2s %8s %7s %7s %6s  %-17s %s" % ("file", "rate", "ch", "dur s", "peak", "rms", "LUFS",
                                                        "seam jump/dRMS+/clk", "notes"))
    for rel, sr, ch, dur, pk, rm, lu, seam, notes in rows:
        print("%-28s %6d %2d %8.3f %7.2f %7.2f %6s  %-17s %s" % (rel, sr, ch, dur, pk, rm, lu, seam, notes))
    for folder, sz in sizes.items():
        print("  %-7s %8.2f MB" % (folder, sz / 1e6))
    print("ALL CHECKS PASSED" if ok else "SOME CHECKS FAILED")
    return ok


# =====================================================================================
# 9. Main
# =====================================================================================

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", choices=["engine", "sfx", "music"], help="generate only one group")
    ap.add_argument("--jobs", type=int, default=2, help="parallel music renders (each needs up to ~1.2 GB RAM)")
    ap.add_argument("--check", action="store_true", help="only verify the existing output files")
    args = ap.parse_args()
    if args.check:
        return 0 if check() else 1
    t0 = time.time()
    if args.only in (None, "engine"):
        build_engine()
    if args.only in (None, "sfx"):
        build_sfx()
    if args.only in (None, "music"):
        build_music(args.jobs)
    print("done in %.1f s" % (time.time() - t0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
