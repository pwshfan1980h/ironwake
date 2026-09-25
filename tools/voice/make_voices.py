#!/usr/bin/env python3
"""Generate IRON WAKE radio voice lines: macOS `say` -> ffmpeg radio chain -> MP3.

  python3 tools/voice/make_voices.py [out_dir] [--only id1,id2]   (default: game/assets/voice)

--only regenerates just those ids and keeps every other line (and its manifest entry) as it is.

Writes <id>.mp3 per line and lines.json (id, who, text, duration) for subtitles.
Swap `say` for recorded or generated VO later: keep the ids and file names.
"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
ONLY = None
if "--only" in args:
    i = args.index("--only")
    ONLY = set(args[i + 1].split(","))
    del args[i:i + 2]
OUT = args[0] if args else os.path.join(HERE, "../../game/assets/voice")
spec = json.load(open(os.path.join(HERE, "lines.json")))
os.makedirs(OUT, exist_ok=True)

RADIO = ("highpass=f=330,lowpass=f=3300,acompressor=threshold=0.08:ratio=9:attack=4:release=60,"
         "volume=2.2,alimiter=limit=0.9")
CYBORG = "aecho=0.8:0.55:9|17:0.35|0.2,flanger=delay=1.2:depth=1.4:speed=0.35,"
SYSTEM = "highpass=f=180,lowpass=f=6000,aecho=0.7:0.4:5:0.3,volume=1.4"


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


manifest = []
old = {}
if ONLY is not None:
    old = {m["id"]: m for m in json.load(open(os.path.join(OUT, "lines.json")))}
with tempfile.TemporaryDirectory() as tmp:
    for ln in spec["lines"]:
        if ONLY is not None and ln["id"] not in ONLY and ln["id"] in old:
            manifest.append(old[ln["id"]])
            continue
        v = spec["voices"][ln["who"]]
        raw = os.path.join(tmp, ln["id"] + ".aiff")
        run(["say", "-v", v["say"], "-r", str(v["rate"]), "-o", raw, ln["text"]])
        out = os.path.join(OUT, ln["id"] + ".mp3")
        if v.get("system"):
            fc = f"[0]{SYSTEM},aresample=22050[o]"
        else:
            voice = (CYBORG if v.get("cyborg") else "") + RADIO
            # squelch click in, voice over a static bed, squelch tail out
            fc = (f"[0]aresample=22050,{voice},adelay=140|140,apad=pad_dur=0.22[v];"
                  "anoisesrc=c=pink:r=22050:a=0.02,highpass=f=600,lowpass=f=3800[bed];"
                  "[v][bed]amix=inputs=2:duration=first:normalize=0[vb];"
                  "anoisesrc=c=white:r=22050:a=0.35:d=0.06,bandpass=f=1800:w=900[k1];"
                  "anoisesrc=c=white:r=22050:a=0.25:d=0.09,bandpass=f=1400:w=700[k2];"
                  "[k1][vb][k2]concat=n=3:v=0:a=1[o]")
        run(["ffmpeg", "-y", "-i", raw, "-filter_complex", fc, "-map", "[o]", "-ac", "1",
             "-c:a", "libmp3lame", "-b:a", "64k", out])
        dur = float(subprocess.check_output(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", out]).strip())
        manifest.append({"id": ln["id"], "who": ln["who"], "text": ln["text"], "dur": round(dur, 2)})
        print(f"{ln['id']:16s} {ln['who']:8s} {dur:5.2f}s")

json.dump(manifest, open(os.path.join(OUT, "lines.json"), "w"), indent=1)
