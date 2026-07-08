"""SRT and WebVTT parsing, serialization, and transcript utilities.

`parse_captions` auto-detects the format — a leading WEBVTT header line
means WebVTT, anything else is treated as SubRip — and parses liberally:

- Malformed cue blocks (no timing line, unparseable timestamps) are
  skipped, never fatal.
- WebVTT NOTE, STYLE, and REGION blocks are ignored.
- WebVTT cue settings after the timing arrow (`position:`, `align:`,
  ...) are dropped.
- Timestamps accept both the SRT comma (`00:01:02,345`) and the VTT dot
  (`00:01:02.345`) millisecond separator, with optional hours, in
  either format.
- CRLF and LF line endings and a UTF-8 BOM are accepted.
- An empty document parses as zero cues of kind "srt".

Speakers are recognized from WebVTT voice spans (`<v Name>text</v>`,
including class annotations like `<v.loud Name>`) and from the plain
"Name: text" convention on a cue's first line (prefix of at most 48
bytes with no angle brackets, to avoid eating markup or prose colons).
Voice-span markup is removed from the cue text; other inline markup is
left as-is in v0.1.

`to_srt` can only represent a speaker via the `Name: ` colon
convention, so it silently drops that prefix (keeping the speaker in
the `Cue`, out of the serialized text) for any speaker longer than 48
bytes or containing `:`, `<`, or `>` — such a speaker would otherwise
be unparseable, or would swallow the following cue's text, on
re-parse. `to_vtt` has no such limit since voice spans don't share
that ambiguity.

A cue's `index` uses -1 internally to mean "no explicit identifier";
callers building `Cue` values directly should use -1 the same way.
Both serializers substitute the cue's position in the document for
any negative index, but pass through zero and positive indices
(including an explicit `0`) unchanged.
"""

from captions.model import Cue, Captions, KIND_SRT, KIND_VTT

comptime _COLON = UInt8(ord(":"))
comptime _COMMA = UInt8(ord(","))
comptime _DOT = UInt8(ord("."))
comptime _LT = UInt8(ord("<"))
comptime _GT = UInt8(ord(">"))
comptime _SLASH = UInt8(ord("/"))
comptime _V = UInt8(ord("v"))
comptime _SPACE = UInt8(0x20)
comptime _TAB = UInt8(0x09)
comptime _CR = UInt8(0x0D)
comptime _NL = UInt8(0x0A)

# Longest "Speaker Name: " prefix (in bytes) the colon convention accepts.
comptime _MAX_SPEAKER_PREFIX = 48


def _is_digit(b: UInt8) -> Bool:
    return b >= UInt8(ord("0")) and b <= UInt8(ord("9"))


def _is_space(b: UInt8) -> Bool:
    return b == _SPACE or b == _TAB


def _split_lines(source: String) -> List[String]:
    """Split into lines, handling CRLF/LF and a leading UTF-8 BOM."""
    var data = source.as_bytes()
    var lines = List[String]()
    var start = 0
    if (
        len(data) >= 3
        and data[0] == 0xEF
        and data[1] == 0xBB
        and data[2] == 0xBF
    ):
        start = 3
    var i = start
    var line_start = start
    while i < len(data):
        if data[i] == _NL:
            var end = i
            if end > line_start and data[end - 1] == _CR:
                end -= 1
            lines.append(
                String(StringSlice(unsafe_from_utf8=data[line_start:end]))
            )
            i += 1
            line_start = i
        else:
            i += 1
    if line_start < len(data):
        var end = len(data)
        if data[end - 1] == _CR:
            end -= 1
        lines.append(String(StringSlice(unsafe_from_utf8=data[line_start:end])))
    return lines^


def _is_blank(line: String) -> Bool:
    for b in line.as_bytes():
        if not _is_space(b):
            return False
    return True


def _is_all_digits(line: String) -> Bool:
    var bytes = line.as_bytes()
    if len(bytes) == 0:
        return False
    for b in bytes:
        if not _is_digit(b):
            return False
    return True


def _parse_ts(raw: String) raises -> Int:
    """Milliseconds for `HH:MM:SS,mmm` / `HH:MM:SS.mmm` / `MM:SS.mmm`.

    Hours are optional and may exceed two digits; the fractional part
    is optional and read to millisecond precision.
    """
    var s = String(StringSlice(raw).strip())
    var bytes = s.as_bytes()
    var n = len(bytes)
    var i = 0
    var parts = List[Int]()
    while True:
        if i >= n or not _is_digit(bytes[i]):
            raise Error("mojo-captions: bad timestamp: " + s)
        var v = 0
        while i < n and _is_digit(bytes[i]):
            v = v * 10 + Int(bytes[i]) - ord("0")
            i += 1
        parts.append(v)
        if i < n and bytes[i] == _COLON:
            i += 1
            continue
        break
    var ms = 0
    if i < n and (bytes[i] == _COMMA or bytes[i] == _DOT):
        i += 1
        var digits = 0
        while i < n and _is_digit(bytes[i]) and digits < 3:
            ms = ms * 10 + Int(bytes[i]) - ord("0")
            i += 1
            digits += 1
        if digits == 0:
            raise Error("mojo-captions: bad timestamp: " + s)
        while digits < 3:
            ms *= 10
            digits += 1
    if len(parts) == 3:
        return ((parts[0] * 60 + parts[1]) * 60 + parts[2]) * 1000 + ms
    if len(parts) == 2:
        return (parts[0] * 60 + parts[1]) * 1000 + ms
    raise Error("mojo-captions: bad timestamp: " + s)


def _parse_timing(line: String, mut start_ms: Int, mut end_ms: Int) raises:
    """Parse `start --> end [settings]`; cue settings are dropped."""
    var arrow = line.find("-->")
    if arrow == -1:
        raise Error("mojo-captions: missing --> in timing line")
    var bytes = line.as_bytes()
    var left = String(StringSlice(unsafe_from_utf8=bytes[0:arrow]))
    var j = arrow + 3
    while j < len(bytes) and _is_space(bytes[j]):
        j += 1
    var k = j
    while k < len(bytes) and not _is_space(bytes[k]):
        k += 1
    var right = String(StringSlice(unsafe_from_utf8=bytes[j:k]))
    start_ms = _parse_ts(left)
    end_ms = _parse_ts(right)


def _is_timing_line(line: String) -> Bool:
    """Whether `line` is a genuine `timestamp --> timestamp` timing line.

    Cue text may legitimately contain `-->` (e.g. "map --> filter", or a
    Unicode-arrow gloss), so a bare `-->` substring is not enough to mark
    a line as a cue boundary; both sides must parse as timestamps.
    """
    if line.find("-->") == -1:
        return False
    var start_ms = 0
    var end_ms = 0
    try:
        _parse_timing(line, start_ms, end_ms)
    except:
        return False
    return True


def _strip_voice_tags(text: String, mut speaker: String) -> String:
    """Remove `<v ...>` / `</v>` markup; record the first voice's name."""
    if text.find("<v") == -1:
        return text.copy()
    var bytes = text.as_bytes()
    var n = len(bytes)
    var out = String()
    var i = 0
    while i < n:
        if bytes[i] == _LT:
            if (
                i + 3 < n
                and bytes[i + 1] == _SLASH
                and bytes[i + 2] == _V
                and bytes[i + 3] == _GT
            ):
                i += 4
                continue
            if (
                i + 2 < n
                and bytes[i + 1] == _V
                and (_is_space(bytes[i + 2]) or bytes[i + 2] == _DOT)
            ):
                var gt = i + 2
                while gt < n and bytes[gt] != _GT:
                    gt += 1
                if gt < n:
                    # Skip any `.class` annotations, then the space(s)
                    # before the voice name.
                    var sp = i + 2
                    while sp < gt and not _is_space(bytes[sp]):
                        sp += 1
                    while sp < gt and _is_space(bytes[sp]):
                        sp += 1
                    if speaker.byte_length() == 0 and sp < gt:
                        speaker = String(
                            StringSlice(unsafe_from_utf8=bytes[sp:gt])
                        )
                    i = gt + 1
                    continue
        var run = i
        i += 1
        while i < n and bytes[i] != _LT:
            i += 1
        out += String(StringSlice(unsafe_from_utf8=bytes[run:i]))
    return out^


def _extract_colon_speaker(text: String, mut speaker: String) -> String:
    """Split a leading `Speaker Name: ` off the cue's first line."""
    var c = text.find(": ")
    if c <= 0 or c > _MAX_SPEAKER_PREFIX:
        return text.copy()
    var nl = text.find("\n")
    if nl != -1 and c > nl:
        return text.copy()
    var bytes = text.as_bytes()
    for j in range(c):
        if bytes[j] == _LT or bytes[j] == _GT:
            return text.copy()
    speaker = String(StringSlice(unsafe_from_utf8=bytes[0:c]))
    return String(StringSlice(unsafe_from_utf8=bytes[c + 2 :]))


def _srt_speaker_representable(speaker: String) -> Bool:
    """Whether `speaker` can round-trip through the SRT `Name: ` prefix.

    Mirrors the acceptance rule in `_extract_colon_speaker`: the name
    must fit within `_MAX_SPEAKER_PREFIX` bytes and contain none of the
    characters that convention treats specially (`:` ends the prefix
    early or ambiguously, `<`/`>` look like markup).
    """
    if speaker.byte_length() > _MAX_SPEAKER_PREFIX:
        return False
    for b in speaker.as_bytes():
        if b == _COLON or b == _LT or b == _GT:
            return False
    return True


def _is_meta_block(first_line: String) -> Bool:
    """WebVTT NOTE/STYLE/REGION blocks carry no cues."""
    if first_line == "NOTE" or first_line.startswith("NOTE "):
        return True
    if first_line == "STYLE" or first_line.startswith("STYLE "):
        return True
    if first_line == "REGION" or first_line.startswith("REGION "):
        return True
    return False


def _parse_block(lines: List[String], start: Int, end: Int) raises -> List[Cue]:
    """Parse one or more cues out of a contiguous non-blank line block.

    Normally a block (the lines between two blank lines) holds exactly
    one cue. But if two cues are glued together with no blank line
    between them, a line that would otherwise be swallowed as cue 1's
    text is itself a timing line (`-->`). When that's found, cue 1's
    text stops there and a new cue begins — consuming its own optional
    leading index line — and parsing continues from there, so a block
    can yield more than one `Cue`.

    A cue's `index` is -1 when the block has no numeric identifier
    line for it; the caller resolves that to the cue's document
    position.
    """
    var result = List[Cue]()
    var seg_start = start
    while seg_start < end:
        var t = -1
        for j in range(seg_start, end):
            if _is_timing_line(lines[j]):
                t = j
                break
        if t == -1:
            if len(result) == 0:
                raise Error("mojo-captions: cue block without a timing line")
            break
        var index = -1
        if t == seg_start + 1 and _is_all_digits(lines[seg_start]):
            index = 0
            for b in lines[seg_start].as_bytes():
                index = index * 10 + Int(b) - ord("0")
        var start_ms = 0
        var end_ms = 0
        # Isolate each segment's parse: a malformed timing line skips just
        # this segment, never discarding cues already gathered from the
        # block. `_is_timing_line` already validated `lines[t]`, so this
        # is defense-in-depth against divergence between the two.
        try:
            _parse_timing(lines[t], start_ms, end_ms)
        except:
            seg_start = t + 1
            continue
        # A block can hold a second (or third...) cue glued on with no
        # blank-line separator. If a later "text" line is itself a
        # timing line, that's where this cue's text ends and the next
        # cue begins — including its optional index line just before it.
        # A bare `-->` inside cue text is not a boundary; only a line that
        # parses as `timestamp --> timestamp` is.
        var text_end = end
        for j in range(t + 1, end):
            if _is_timing_line(lines[j]):
                if j > t + 1 and _is_all_digits(lines[j - 1]):
                    text_end = j - 1
                else:
                    text_end = j
                break
        var joined = String()
        for j in range(t + 1, text_end):
            if j > t + 1:
                joined += "\n"
            joined += lines[j]
        var speaker = String()
        var text = _strip_voice_tags(joined, speaker)
        if speaker.byte_length() == 0:
            text = _extract_colon_speaker(text, speaker)
        result.append(Cue(index, start_ms, end_ms, speaker^, text^))
        seg_start = text_end
    return result^


def parse_captions(source: String) raises -> Captions:
    """Parse SRT or WebVTT text into `Captions` (format auto-detected)."""
    var lines = _split_lines(source)
    var n = len(lines)
    var i = 0
    while i < n and _is_blank(lines[i]):
        i += 1
    var is_vtt = i < n and lines[i].startswith("WEBVTT")
    var kind = String(KIND_SRT)
    if is_vtt:
        kind = String(KIND_VTT)
        # Skip the header block (the WEBVTT line and any metadata lines
        # that follow it, up to the first blank line).
        while i < n and not _is_blank(lines[i]):
            i += 1
    var cues = List[Cue]()
    while i < n:
        while i < n and _is_blank(lines[i]):
            i += 1
        if i >= n:
            break
        var block_start = i
        while i < n and not _is_blank(lines[i]):
            i += 1
        if is_vtt and _is_meta_block(lines[block_start]):
            continue
        try:
            var block_cues = _parse_block(lines, block_start, i)
            for cue in block_cues:
                var resolved = cue.copy()
                if resolved.index < 0:
                    resolved.index = len(cues) + 1
                cues.append(resolved^)
        except err:
            pass  # Liberal parsing: a malformed cue is skipped, not fatal.
    return Captions(kind^, cues^)


def _pad(value: Int, width: Int) -> String:
    var s = String(value)
    while s.byte_length() < width:
        s = String("0") + s
    return s^


def _format_ts(ms: Int, sep: StaticString) -> String:
    var total = ms
    if total < 0:
        total = 0
    var hours = total // 3600000
    var minutes = (total // 60000) % 60
    var seconds = (total // 1000) % 60
    var frac = total % 1000
    return (
        _pad(hours, 2)
        + ":"
        + _pad(minutes, 2)
        + ":"
        + _pad(seconds, 2)
        + String(sep)
        + _pad(frac, 3)
    )


def to_srt(captions: Captions) -> String:
    """Serialize to SubRip. Speakers become a `Name: ` text prefix.

    A speaker longer than 48 bytes, or containing `:`, `<`, or `>`,
    cannot be represented by that convention (it would fail to
    re-parse, or would absorb the following cue's text) — such a
    speaker is left out of the output text entirely rather than risk
    corrupting it. The speaker stays on the in-memory `Cue`.
    """
    var out = String()
    var pos = 0
    for cue in captions.cues:
        pos += 1
        var idx = cue.index
        if idx < 0:
            idx = pos
        out += String(idx) + "\n"
        out += (
            _format_ts(cue.start_ms, ",")
            + " --> "
            + _format_ts(cue.end_ms, ",")
            + "\n"
        )
        if cue.speaker.byte_length() > 0 and _srt_speaker_representable(
            cue.speaker
        ):
            out += cue.speaker + ": "
        out += cue.text + "\n\n"
    return out^


def to_vtt(captions: Captions) -> String:
    """Serialize to WebVTT. Speakers become `<v Name>...</v>` spans."""
    var out = String("WEBVTT\n\n")
    var pos = 0
    for cue in captions.cues:
        pos += 1
        var idx = cue.index
        if idx < 0:
            idx = pos
        out += String(idx) + "\n"
        out += (
            _format_ts(cue.start_ms, ".")
            + " --> "
            + _format_ts(cue.end_ms, ".")
            + "\n"
        )
        if cue.speaker.byte_length() > 0:
            out += String("<v ") + cue.speaker + ">" + cue.text + "</v>\n\n"
        else:
            out += cue.text + "\n\n"
    return out^


def plain_text(captions: Captions) -> String:
    """Transcript without timestamps: one `Speaker: text` line per cue.

    Cues with empty text are omitted; multi-line cue text keeps its
    internal newlines.
    """
    var out = String()
    for cue in captions.cues:
        if cue.text.byte_length() == 0:
            continue
        if out.byte_length() > 0:
            out += "\n"
        if cue.speaker.byte_length() > 0:
            out += cue.speaker + ": "
        out += cue.text
    return out^


def cues_between(captions: Captions, start_ms: Int, end_ms: Int) -> List[Cue]:
    """Cues overlapping the half-open window [start_ms, end_ms)."""
    var out = List[Cue]()
    for cue in captions.cues:
        if cue.start_ms < end_ms and cue.end_ms > start_ms:
            out.append(cue.copy())
    return out^


def duration_ms(captions: Captions) -> Int:
    """Largest cue end time, or 0 for an empty document."""
    var max_end = 0
    for cue in captions.cues:
        if cue.end_ms > max_end:
            max_end = cue.end_ms
    return max_end
