"""Fuzz target: parse argv[1]; raising is fine, crashing/hanging is not."""

from std.sys import argv

from captions import parse_captions


def main():
    try:
        var c = parse_captions(open(String(argv()[1]), "r").read())
        print("cues:", len(c.cues))
    except e:
        print("raised:", e)
