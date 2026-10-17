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
    noise = random.Random(1543)
    render("sword", 0.18, lambda t: (noise.uniform(-1, 1) * 0.13 + math.sin(math.tau * 1537 * t) * 0.1) * math.exp(-t * 26))
    render("hit", 0.2, lambda t: (noise.uniform(-1, 1) * 0.17 + math.sin(math.tau * 98 * t) * 0.2) * math.exp(-t * 20))
    render("choice", 0.13, lambda t: math.sin(math.tau * 659.25 * t) * 0.14 * math.exp(-t * 35))
    render("turn", 0.22, lambda t: math.sin(math.tau * 196 * t) * 0.16 * math.exp(-t * 14))
    render("victory", 0.9, lambda t: math.sin(math.tau * [293.665, 349.228, 440][min(2, int(t / 0.3))] * t) * 0.16 * math.exp(-(t % 0.3) * 7))
    print("AUDIO PASS: 3 original music loops, 5 effects, Ogg Vorbis")


if __name__ == "__main__":
    main()
