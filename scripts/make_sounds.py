"""合成棋境音效（纯 Python，无依赖）：木质落子 / 吃子 / 点击 / 胜负。
输出 44.1kHz 16bit mono wav 到 App/Resources/Sounds/。
"""
import wave, math, os, random

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "App", "Resources", "Sounds")

def write_wav(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for v in samples:
            v = max(-1.0, min(1.0, v))
            frames += int(v * 32000).to_bytes(2, "little", signed=True)
        w.writeframes(bytes(frames))
    print("OK", name, round(len(samples) / SR, 3), "s")

def env_exp(t, decay):
    return math.exp(-t * decay)

def tone(freq, dur, decay, amp=0.8, sr=SR, harmonics=((1, 1.0),)):
    n = int(dur * sr)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / sr
        ph += 2 * math.pi * freq / sr
        v = 0.0
        for mult, ha in harmonics:
            v += ha * math.sin(ph * mult)
        out.append(v * amp * env_exp(t, decay))
    return out

def noise_burst(dur, decay, amp=0.5, sr=SR, seed=7):
    r = random.Random(seed)
    n = int(dur * sr)
    return [r.uniform(-1, 1) * amp * env_exp(i / sr, decay) for i in range(n)]

def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out

def delay(track, seconds):
    return [0.0] * int(seconds * SR) + track

# 1) 木质落子（国象/象棋/将棋/跳棋/五子棋/黑白棋通用）：低频木腔 + 高频瞬态
wood = mix(
    tone(190, 0.16, 38, 0.9, harmonics=((1, 1.0), (2.7, 0.35), (4.2, 0.15))),
    noise_burst(0.02, 90, 0.35, seed=11),
    tone(950, 0.05, 60, 0.25),
)
write_wav("place_wood.wav", wood)

# 2) 棋子落盘（围棋/五子棋石子感更脆亮）
stone = mix(
    tone(260, 0.14, 45, 0.85, harmonics=((1, 1.0), (2.2, 0.4), (3.3, 0.18))),
    noise_burst(0.015, 110, 0.3, seed=3),
    tone(1350, 0.04, 70, 0.2),
)
write_wav("place_stone.wav", stone)

# 3) 吃子：两次错开的木声 + 低频砰
cap = mix(
    tone(170, 0.18, 34, 0.95, harmonics=((1, 1.0), (2.5, 0.4))),
    delay(noise_burst(0.03, 70, 0.4, seed=5), 0.075),
    delay(tone(240, 0.12, 40, 0.6), 0.075),
    tone(90, 0.22, 26, 0.5),
)
write_wav("capture.wav", cap)

# 4) UI 点击：极短柔和 tick
click = mix(
    tone(1150, 0.045, 90, 0.30),
    tone(2300, 0.02, 130, 0.12),
)
write_wav("click.wav", click)

# 5) 胜利：三音上行琶音（柔和正弦+轻泛音）
def note(freq, dur, amp=0.5):
    return tone(freq, dur, 7, amp, harmonics=((1, 1.0), (2, 0.25), (3, 0.08)))
win = mix(
    note(523.25, 0.55, 0.42),                    # C5
    delay(note(659.25, 0.55, 0.42), 0.14),       # E5
    delay(note(783.99, 0.75, 0.48), 0.28),       # G5
)
write_wav("win.wav", win)

# 6) 失败：下行双音
lose = mix(
    note(392.0, 0.5, 0.4),                       # G4
    delay(note(261.63, 0.8, 0.42), 0.20),        # C4
)
write_wav("lose.wav", lose)

# 7) 和棋：中性单音
draw = mix(note(440.0, 0.7, 0.4), delay(note(440.0, 0.5, 0.25), 0.25))
write_wav("draw.wav", draw)
print("ALL_DONE")

# ===== v1.2：多风格变体（供设置里挑选） =====

# 落子·木声 乙：更闷更厚（低频为主）
wood_b = mix(
    tone(140, 0.20, 30, 1.0, harmonics=((1, 1.0), (2.0, 0.3))),
    noise_burst(0.025, 60, 0.25, seed=21),
)
write_wav("place_wood_b.wav", wood_b)

# 落子·木声 丙：轻巧干净（高频短促）
wood_c = mix(
    tone(320, 0.10, 55, 0.7, harmonics=((1, 1.0), (2.5, 0.3))),
    noise_burst(0.012, 130, 0.3, seed=31),
)
write_wav("place_wood_c.wav", wood_c)

# 落子·石声 乙：玉子感（更亮）
stone_b = mix(
    tone(340, 0.12, 50, 0.8, harmonics=((1, 1.0), (2.8, 0.5), (4.5, 0.2))),
    noise_burst(0.012, 140, 0.35, seed=41),
    tone(1800, 0.035, 90, 0.22),
)
write_wav("place_stone_b.wav", stone_b)

# 落子·石声 丙：柔和（棉感）
stone_c = mix(
    tone(210, 0.13, 36, 0.6, harmonics=((1, 1.0), (1.8, 0.25))),
    noise_burst(0.02, 55, 0.15, seed=51),
)
write_wav("place_stone_c.wav", stone_c)

# 吃子 乙：干脆利落（双击更近）
cap_b = mix(
    tone(200, 0.14, 45, 0.9, harmonics=((1, 1.0), (2.6, 0.35))),
    delay(tone(150, 0.16, 40, 0.75), 0.05),
    delay(noise_burst(0.02, 90, 0.3, seed=61), 0.05),
)
write_wav("capture_b.wav", cap_b)

# 吃子 丙：轻巧（单次清脆）
cap_c = mix(
    tone(420, 0.10, 60, 0.7, harmonics=((1, 1.0), (2.2, 0.3))),
    noise_burst(0.012, 120, 0.3, seed=71),
)
write_wav("capture_c.wav", cap_c)
print("V12_DONE")
