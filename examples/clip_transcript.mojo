"""Print the cues (and a plain-text excerpt) covering a time window in an
SRT or WebVTT file — the "pull a clip" workflow this library exists for.

Usage:
    mojo run -I src examples/clip_transcript.mojo <captions.srt|.vtt> <start_ms> <end_ms>
"""

from std.sys import argv

from captions import parse_captions, cues_between, plain_text, Captions


def main() raises:
    var args = argv()
    if len(args) < 4:
        print("usage: clip_transcript <captions.srt|.vtt> <start_ms> <end_ms>")
        return

    var start_ms = Int(String(args[2]))
    var end_ms = Int(String(args[3]))

    var source = open(String(args[1]), "r").read()
    var caps = parse_captions(source^)

    print(caps)
    print(t"window: {start_ms}ms - {end_ms}ms")
    print()

    var clip = cues_between(caps, start_ms, end_ms)
    for cue in clip:
        print(cue)
        print(t"    {cue.text}")

    print()
    print("plain text excerpt:")
    print(plain_text(Captions(caps.kind.copy(), clip.copy())))
