# mojo-captions

SRT and WebVTT subtitle/transcript parsing in pure Mojo. No Python
dependencies, no FFI — byte-level parsing on UTF-8 strings.

## Why

Podcast and video tooling constantly needs to read caption files —
pull a transcript, find what was said in a time window, convert
between formats. The Mojo ecosystem has no library for this. This is
v0.1: a liberal parser (malformed cues are skipped, not fatal), two
serializers, and a few transcript utilities.

## What it handles

- **Auto-detection**: a leading `WEBVTT` header means WebVTT, anything
  else parses as SubRip.
- **Timestamps**: SRT comma (`00:01:02,345`) and VTT dot
  (`00:01:02.345`) millisecond separators, optional hours, in either
  format.
- **Speakers**: WebVTT voice spans (`<v Conor Bronsdon>text</v>`,
  including `<v.class Name>`) and the plain `Speaker Name: text`
  convention on a cue's first line.
- **WebVTT extras**: NOTE/STYLE/REGION blocks skipped, cue settings
  after the timing arrow (`position:`, `align:`, ...) dropped, cue
  identifiers (numeric ones become the cue index).
- **Robustness**: multi-line cue text, CRLF and LF line endings,
  UTF-8 BOM, missing SRT index lines, empty documents.

## Usage

```mojo
from captions import parse_captions, to_srt, to_vtt, plain_text
from captions import cues_between, duration_ms

def main() raises:
    var caps = parse_captions(open("episode.vtt", "r").read())
    print(caps)                          # Captions(vtt, 512 cues)
    print(caps.cues[0].speaker)          # "Conor Bronsdon"
    print(caps.cues[0].start_ms)         # 1000

    print(plain_text(caps))              # transcript, no timestamps
    var minute_one = cues_between(caps, 60_000, 120_000)
    print(duration_ms(caps))             # last cue end, in ms

    var srt = to_srt(caps)               # convert VTT -> SRT
    var vtt = to_vtt(caps)               # and back
```

`Cue` fields: `index`, `start_ms`, `end_ms`, `speaker`, `text` — empty
string means absent, mirroring mojo-feed's model conventions.

## Tests

```sh
pixi run test
# or directly:
mojo run -I src test/test_captions.mojo
```

26 tests cover parsing, round-trip serialization, speaker extraction,
and edge cases (BOM, CRLF, malformed cues, timestamp-only cues,
overlapping cues, empty input). Fixtures live in `test/data/`.

## Parsing philosophy

Liberal, like mojo-feed: a cue block with no timing line or an
unparseable timestamp is skipped and parsing continues. `parse_captions`
never fails on malformed cue content — an empty document returns zero
cues of kind `"srt"`. Inline markup other than voice spans is left
verbatim in cue text in v0.1.
