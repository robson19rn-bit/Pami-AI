"""Generuje własne (autorskie, MIT) dźwięki aplikacji: krótkie sygnały i spokojną muzyczkę w tle.
Uruchom: python3 tool/gen_audio.py assets/audio
Wyłącznie synteza – brak cudzych nagrań i sampli."""
import math, struct, sys, wave, random

SR = 22050
out = sys.argv[1]

def note_freq(midi): return 440.0 * 2 ** ((midi - 69) / 12)

def bell(buf, start, midi, dur, vol, sr=SR):
    """Dźwięk pozytywki: sinus + delikatne harmoniczne, szybki atak, wykładnicze wybrzmienie."""
    f = note_freq(midi)
    n = int(dur * sr)
    s0 = int(start * sr)
    for i in range(n):
        t = i / sr
        env = min(1.0, t / 0.008) * math.exp(-t * 3.2 / dur * 2.2)
        v = (math.sin(2 * math.pi * f * t) + 0.25 * math.sin(2 * math.pi * 2 * f * t) * math.exp(-t * 6)
             + 0.08 * math.sin(2 * math.pi * 3.01 * f * t) * math.exp(-t * 9))
        j = (s0 + i) % len(buf)
        buf[j] += vol * env * v

def pad(buf, start, midis, dur, vol, sr=SR):
    """Miękkie tło akordu (wolny atak i zanik)."""
    s0 = int(start * sr); n = int(dur * sr)
    for i in range(n):
        t = i / sr
        env = math.sin(math.pi * min(1.0, t / dur)) ** 2
        v = sum(math.sin(2 * math.pi * note_freq(m) * t) for m in midis) / len(midis)
        j = (s0 + i) % len(buf)
        buf[j] += vol * env * v

def echo(buf, delay, fb):
    d = int(delay * SR); res = buf[:]
    for i in range(len(res)):
        res[i] += fb * res[i - d] if i >= d else fb * res[len(res) - d + i] * 0.0
    return res

def save(name, buf, peak=0.8):
    m = max(1e-9, max(abs(x) for x in buf))
    with wave.open(f'{out}/{name}', 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, x / m * peak)) * 32767)) for x in buf))

def fade_tail(buf, sec):
    n = int(sec * SR)
    for i in range(n):
        buf[len(buf) - n + i] *= 1 - i / n
    return buf

# 1) Dobra odpowiedź: dwa wznoszące się dźwięki (G5 → C6)
b = [0.0] * int(0.9 * SR); bell(b, 0.0, 79, 0.6, 0.6); bell(b, 0.12, 84, 0.75, 0.7)
save('dobrze.wav', fade_tail(b, 0.1), 0.6)
# 2) Spróbuj jeszcze: jeden miękki, neutralny dźwięk (nie „karzący”)
b = [0.0] * int(0.6 * SR); bell(b, 0.0, 69, 0.55, 0.5)
save('jeszcze.wav', fade_tail(b, 0.1), 0.35)
# 3) Nowy etap: krótkie arpeggio C-E-G-C
b = [0.0] * int(1.6 * SR)
for k, m in enumerate([72, 76, 79, 84]):
    bell(b, k * 0.13, m, 1.0, 0.6)
save('nowy_etap.wav', fade_tail(b, 0.2), 0.65)

# 4) Muzyczka w tle: spokojna pozytywka, C–Am–F–G, 66 BPM, pętla ~29 s (bez szwu)
random.seed(7)
bpm = 66; beat = 60 / bpm; bars = 8; total = bars * 4 * beat
buf = [0.0] * int(total * SR)
chords = [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62]] * 2
melody_scale = [72, 74, 76, 79, 81]  # pentatonika C
for bar, ch in enumerate(chords):
    t0 = bar * 4 * beat
    pad(buf, t0, [m - 12 for m in ch], 4 * beat * 1.05, 0.10)
    for k, m in enumerate([ch[0], ch[1], ch[2], ch[1]]):
        bell(buf, t0 + k * beat, m + 12, 1.6, 0.22)
    # rzadka, łagodna melodia
    for k in range(2):
        if random.random() < 0.75:
            bell(buf, t0 + (k * 2 + random.choice([0, 1])) * beat + 0.5 * beat, random.choice(melody_scale), 1.8, 0.16)
buf = echo(buf, beat * 0.75, 0.25)
save('muzyka.wav', buf, 0.5)
print('ok')
