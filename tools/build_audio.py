"""Original deterministic modal sketches and effects; no sampled recordings."""
from array import array
import math
from pathlib import Path
import random
import subprocess
import wave

ROOT = Path(__file__).resolve().parents[1]
RATE = 22050


def render(name, duration, sample):
    temporary = ROOT / "build/audio"
    temporary.mkdir(parents=True, exist_ok=True)
    output = ROOT / "assets/audio"
    output.mkdir(parents=True, exist_ok=True)
    pcm = array("h", (int(max(-0.9, min(0.9, sample(index / RATE))) * 32767)
                      for index in range(round(duration * RATE))))
    wav = temporary / (name + ".wav")
    with wave.open(str(wav), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(RATE)
        stream.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav),
                    "-c:a", "libvorbis", "-q:a", "3", str(output / (name + ".ogg"))], check=True)


def music(name, notes, beat, percussion):
    scale = [146.832, 155.563, 174.614, 195.998, 220.0, 233.082, 261.626, 293.665]
    duration = beat * len(notes)

    def sample(t):
        index = int(t / beat) % len(notes)
        age = t % beat
        frequency = scale[notes[index]]
        envelope = min(1, age * 90) * math.exp(-age * 4.5)
        tone = (math.sin(math.tau * frequency * t) +
                0.28 * math.sin(math.tau * frequency * 2 * t)) * envelope * 0.15
        drone = math.sin(math.tau * scale[0] / 2 * t) * 0.035
        drum = math.sin(math.tau * (72 * age - 26 * age * age)) * math.exp(-age * 24) * percussion
        # Short attack/release avoids a hard edge when the Ogg loops.
        return (tone + drone + drum) * min(1, t * 20, (duration - t) * 20)

    render(name, duration, sample)


def main():
    music("city", [0, 2, 4, 2, 1, 0, 3, 2, 0, 4, 5, 4, 2, 1, 2, 0] * 2, 0.6, 0.025)
    music("march", [0, 0, 4, 3, 2, 0, 1, 0, 0, 2, 4, 5, 4, 2, 1, 0] * 2, 0.5, 0.12)
    music("battle", [0, 4, 0, 2, 1, 4, 3, 2, 0, 5, 4, 3, 2, 1, 2, 0] * 2, 0.375, 0.18)
    music("tension", [0, 1, 0, 3, 0, 1, 2, 1] * 4, 0.7, 0.055)
    music("sadness", [4, 3, 2, 0, 1, 0, 2, 0] * 4, 0.95, 0.0)
    music("triumph", [0, 2, 4, 5, 7, 5, 4, 2] * 4, 0.62, 0.07)
    noise = random.Random(1543)
    for name,base in [("forest",0.055),("camp",0.038),("forum",0.05),("sea",0.075)]:
        def ambient(t, mood=name, gain=base):
            wind = (math.sin(t * 3.1) + math.sin(t * 7.7) * 0.5) * gain * 0.18
            grain = noise.uniform(-1, 1) * gain * (0.35 + 0.25 * math.sin(t * 0.7))
            bird = math.sin(math.tau * (1800 + 300 * math.sin(t * 24)) * t) * 0.018 if mood == 'forest' and t % 4 < 0.25 else 0
            voices = (math.sin(math.tau * 124 * t) + math.sin(math.tau * 157 * t)) * 0.012 * (0.5 + 0.5 * math.sin(t * 1.8)) if mood == 'forum' else 0
            return (wind + grain + bird + voices) * min(1, t * 5, (20-t) * 5)
        render('ambient_' + name, 20, ambient)
    render("step", 0.16, lambda t: noise.uniform(-1, 1) * 0.16 * math.exp(-t * 30))
    render("shield", 0.35, lambda t: (math.sin(math.tau * 213 * t) + 0.6 * math.sin(math.tau * 337 * t)) * 0.14 * math.exp(-t * 12))
    render("horns", 1.5, lambda t: (math.sin(math.tau * 146.832 * t) + 0.35 * math.sin(math.tau * 293.665 * t)) * 0.12 * min(1,t*6,(1.5-t)*4))
    render("fire", 0.6, lambda t: noise.uniform(-1,1) * 0.07 * (0.4 + 0.4 * math.sin(t * 75)) * math.exp(-t*3))
    render("crowd", 1.5, lambda t: sum(math.sin(math.tau * f * t) for f in [91,127,173,211]) * 0.025 * (0.7 + 0.3 * math.sin(t * 7)) * min(1,t*8,(1.5-t)*5))
    render("sword", 0.18, lambda t: (noise.uniform(-1, 1) * 0.13 + math.sin(math.tau * 1537 * t) * 0.1) * math.exp(-t * 26))
    render("hit", 0.2, lambda t: (noise.uniform(-1, 1) * 0.17 + math.sin(math.tau * 98 * t) * 0.2) * math.exp(-t * 20))
    render("choice", 0.13, lambda t: math.sin(math.tau * 659.25 * t) * 0.14 * math.exp(-t * 35))
    render("turn", 0.22, lambda t: math.sin(math.tau * 196 * t) * 0.16 * math.exp(-t * 14))
    render("victory", 0.9, lambda t: math.sin(math.tau * [293.665, 349.228, 440][min(2, int(t / 0.3))] * t) * 0.16 * math.exp(-(t % 0.3) * 7))
    print("AUDIO PASS: 6 original music loops, 4 ambiences, 10 effects, Ogg Vorbis")


if __name__ == "__main__":
    main()
