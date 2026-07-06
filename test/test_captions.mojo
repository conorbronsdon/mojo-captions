from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from captions import (
    Cue,
    Captions,
    KIND_SRT,
    KIND_VTT,
    parse_captions,
    to_srt,
    to_vtt,
    plain_text,
    cues_between,
    duration_ms,
)

comptime SRT_BASIC = (
    "1\n00:00:01,000 --> 00:00:04,000\nHello there.\n\n"
    "2\n00:01:02,345 --> 00:01:05,500\nSecond cue.\n"
)

comptime VTT_BASIC = (
    "WEBVTT\n\n"
    "1\n00:00:01.000 --> 00:00:04.000\nHello there.\n\n"
    "2\n00:01:02.345 --> 00:01:05.500\nSecond cue.\n"
)


def test_detect_srt_kind() raises:
    var caps = parse_captions(String(SRT_BASIC))
    assert_equal(caps.kind, String(KIND_SRT))
    assert_equal(len(caps.cues), 2)


def test_detect_vtt_kind() raises:
    var caps = parse_captions(String(VTT_BASIC))
    assert_equal(caps.kind, String(KIND_VTT))
    assert_equal(len(caps.cues), 2)


def test_srt_fields_and_comma_timestamps() raises:
    var caps = parse_captions(String(SRT_BASIC))
    assert_equal(caps.cues[0].index, 1)
    assert_equal(caps.cues[0].start_ms, 1000)
    assert_equal(caps.cues[0].end_ms, 4000)
    assert_equal(caps.cues[0].text, "Hello there.")
    assert_equal(caps.cues[1].start_ms, 62345)
    assert_equal(caps.cues[1].end_ms, 65500)


def test_srt_multiline_text() raises:
    var caps = parse_captions(
        String("1\n00:00:01,000 --> 00:00:04,000\nline one\nline two\n")
    )
    assert_equal(caps.cues[0].text, "line one\nline two")


def test_srt_speaker_colon_convention() raises:
    var caps = parse_captions(
        String("1\n00:00:01,000 --> 00:00:04,000\nConor Bronsdon: Welcome back.\n")
    )
    assert_equal(caps.cues[0].speaker, "Conor Bronsdon")
    assert_equal(caps.cues[0].text, "Welcome back.")


def test_srt_missing_index_line() raises:
    var caps = parse_captions(
        String("00:00:01,000 --> 00:00:02,000\nNo index here.\n")
    )
    assert_equal(len(caps.cues), 1)
    assert_equal(caps.cues[0].index, 1)
    assert_equal(caps.cues[0].text, "No index here.")


def test_vtt_hourless_timestamps() raises:
    var caps = parse_captions(
        String("WEBVTT\n\n01:02.345 --> 01:05.000\nShort clock.\n")
    )
    assert_equal(caps.cues[0].start_ms, 62345)
    assert_equal(caps.cues[0].end_ms, 65000)


def test_vtt_voice_span_speaker() raises:
    var caps = parse_captions(
        String("WEBVTT\n\n00:01.000 --> 00:04.000\n<v Conor Bronsdon>Welcome.</v>\n")
    )
    assert_equal(caps.cues[0].speaker, "Conor Bronsdon")
    assert_equal(caps.cues[0].text, "Welcome.")


def test_vtt_voice_span_with_class() raises:
    var caps = parse_captions(
        String("WEBVTT\n\n00:01.000 --> 00:04.000\n<v.loud Guest>Hi!</v>\n")
    )
    assert_equal(caps.cues[0].speaker, "Guest")
    assert_equal(caps.cues[0].text, "Hi!")


def test_vtt_note_style_region_skipped() raises:
    var caps = parse_captions(
        String(
            "WEBVTT\n\n"
            "NOTE\nA comment\nspanning lines.\n\n"
            "STYLE\n::cue { color: red }\n\n"
            "REGION\nid:fred width:40%\n\n"
            "NOTE single-line comment\n\n"
            "00:01.000 --> 00:02.000\nOnly real cue.\n"
        )
    )
    assert_equal(len(caps.cues), 1)
    assert_equal(caps.cues[0].text, "Only real cue.")


def test_vtt_cue_settings_ignored() raises:
    var caps = parse_captions(
        String(
            "WEBVTT\n\n"
            "00:01.000 --> 00:04.000 position:10%,line-left align:start\n"
            "Positioned.\n"
        )
    )
    assert_equal(caps.cues[0].end_ms, 4000)
    assert_equal(caps.cues[0].text, "Positioned.")


def test_vtt_cue_identifiers() raises:
    var caps = parse_captions(
        String(
            "WEBVTT\n\n"
            "opening slide\n00:01.000 --> 00:02.000\nNamed identifier.\n\n"
            "7\n00:03.000 --> 00:04.000\nNumeric identifier.\n"
        )
    )
    assert_equal(caps.cues[0].index, 1)  # non-numeric id -> position
    assert_equal(caps.cues[1].index, 7)


def test_crlf_line_endings() raises:
    var caps = parse_captions(
        String(
            "1\r\n00:00:01,000 --> 00:00:02,000\r\nWindows line one\r\n"
            "and two\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nDone\r\n"
        )
    )
    assert_equal(len(caps.cues), 2)
    assert_equal(caps.cues[0].text, "Windows line one\nand two")
    assert_equal(caps.cues[1].text, "Done")


def _with_bom(source: String) -> String:
    var buf = List[UInt8]()
    buf.append(0xEF)
    buf.append(0xBB)
    buf.append(0xBF)
    for b in source.as_bytes():
        buf.append(b)
    return String(StringSlice(unsafe_from_utf8=Span(buf)))


def test_utf8_bom() raises:
    var srt = parse_captions(_with_bom(String(SRT_BASIC)))
    assert_equal(srt.kind, String(KIND_SRT))
    assert_equal(len(srt.cues), 2)
    var vtt = parse_captions(_with_bom(String(VTT_BASIC)))
    assert_equal(vtt.kind, String(KIND_VTT))
    assert_equal(len(vtt.cues), 2)


def test_empty_file() raises:
    var caps = parse_captions(String(""))
    assert_equal(caps.kind, String(KIND_SRT))
    assert_equal(len(caps.cues), 0)
    assert_equal(duration_ms(caps), 0)
    assert_equal(plain_text(caps), "")


def test_malformed_cue_skipped() raises:
    var caps = parse_captions(
        String(
            "1\n00:00:01,000 --> 00:00:02,000\nGood cue.\n\n"
            "2\nnot a timestamp --> also bad\nBroken cue.\n\n"
            "3\nno timing line at all\n\n"
            "4\n00:00:05,000 --> 00:00:06,000\nAnother good cue.\n"
        )
    )
    assert_equal(len(caps.cues), 2)
    assert_equal(caps.cues[0].text, "Good cue.")
    assert_equal(caps.cues[1].index, 4)
    assert_equal(caps.cues[1].text, "Another good cue.")


def test_timestamp_only_cue() raises:
    var caps = parse_captions(
        String(
            "1\n00:00:01,000 --> 00:00:02,000\n\n"
            "2\n00:00:03,000 --> 00:00:04,000\nHas text.\n"
        )
    )
    assert_equal(len(caps.cues), 2)
    assert_equal(caps.cues[0].text, "")
    assert_equal(caps.cues[1].text, "Has text.")


def test_overlapping_cues_preserved() raises:
    var caps = parse_captions(
        String(
            "1\n00:00:01,000 --> 00:00:05,000\nFirst.\n\n"
            "2\n00:00:03,000 --> 00:00:07,000\nOverlaps first.\n"
        )
    )
    assert_equal(len(caps.cues), 2)
    assert_true(caps.cues[1].start_ms < caps.cues[0].end_ms)


def test_roundtrip_srt() raises:
    var original = parse_captions(
        String(
            "1\n00:00:01,000 --> 00:00:04,000\nConor: Hello there.\n\n"
            "2\n01:02:03,456 --> 01:02:05,789\nTwo lines\nof text.\n\n"
            "3\n01:02:06,000 --> 01:02:07,000\n"
        )
    )
    var reparsed = parse_captions(to_srt(original))
    assert_equal(reparsed.kind, String(KIND_SRT))
    assert_equal(len(reparsed.cues), len(original.cues))
    for i in range(len(original.cues)):
        assert_equal(reparsed.cues[i], original.cues[i])


def test_roundtrip_vtt() raises:
    var original = parse_captions(
        String(
            "WEBVTT\n\n"
            "1\n00:00:01.000 --> 00:00:04.000\n<v Conor Bronsdon>Hello there.</v>\n\n"
            "2\n01:02:03.456 --> 01:02:05.789\nTwo lines\nof text.\n"
        )
    )
    var reparsed = parse_captions(to_vtt(original))
    assert_equal(reparsed.kind, String(KIND_VTT))
    assert_equal(len(reparsed.cues), len(original.cues))
    for i in range(len(original.cues)):
        assert_equal(reparsed.cues[i], original.cues[i])


def test_cross_format_conversion() raises:
    # SRT in, VTT out: timestamps switch comma -> dot, speaker becomes
    # a voice span, and the cue data survives untouched.
    var srt = parse_captions(
        String("1\n00:00:01,500 --> 00:00:04,250\nConor: Cross format.\n")
    )
    var vtt = parse_captions(to_vtt(srt))
    assert_equal(vtt.kind, String(KIND_VTT))
    assert_equal(vtt.cues[0].start_ms, 1500)
    assert_equal(vtt.cues[0].end_ms, 4250)
    assert_equal(vtt.cues[0].speaker, "Conor")
    assert_equal(vtt.cues[0].text, "Cross format.")


def test_plain_text_transcript() raises:
    var caps = parse_captions(
        String(
            "1\n00:00:01,000 --> 00:00:02,000\nConor: Welcome.\n\n"
            "2\n00:00:03,000 --> 00:00:04,000\n\n"
            "3\n00:00:05,000 --> 00:00:06,000\nGreat to be here.\n"
        )
    )
    assert_equal(plain_text(caps), "Conor: Welcome.\nGreat to be here.")


def test_cues_between() raises:
    var caps = parse_captions(
        String(
            "1\n00:00:01,000 --> 00:00:02,000\nA\n\n"
            "2\n00:00:03,000 --> 00:00:05,000\nB\n\n"
            "3\n00:00:06,000 --> 00:00:08,000\nC\n"
        )
    )
    var window = cues_between(caps, 1500, 6500)
    assert_equal(len(window), 3)
    var tight = cues_between(caps, 2500, 5500)
    assert_equal(len(tight), 1)
    assert_equal(tight[0].text, "B")
    var empty = cues_between(caps, 9000, 10000)
    assert_equal(len(empty), 0)


def test_duration_ms() raises:
    var caps = parse_captions(String(SRT_BASIC))
    assert_equal(duration_ms(caps), 65500)


def test_fixture_srt_file() raises:
    var caps = parse_captions(open("test/data/sample.srt", "r").read())
    assert_equal(caps.kind, String(KIND_SRT))
    assert_equal(len(caps.cues), 5)
    assert_equal(caps.cues[0].speaker, "Conor Bronsdon")
    assert_equal(caps.cues[1].text, "This cue has text\nthat spans two lines.")
    assert_equal(caps.cues[2].speaker, "Guest")
    assert_equal(caps.cues[3].text, "")  # timestamp-only cue
    assert_equal(caps.cues[4].index, 5)
    assert_equal(duration_ms(caps), 15000)


def test_srt_long_speaker_not_absorbed_into_text() raises:
    """A speaker too long (or too markup-like) for the `Name: ` prefix
    must not be emitted into the text, since re-parsing would either
    reject the prefix or mangle the following cue."""
    var long_speaker = String(
        "Extremely Long Speaker Name That Exceeds Forty Eight Bytes Total"
    )
    var cue = Cue(1, 1000, 2000, long_speaker^, String("Hello there."))
    var cues = List[Cue]()
    cues.append(cue^)
    var caps = Captions(String(KIND_SRT), cues^)
    var srt = to_srt(caps)
    var reparsed = parse_captions(srt)
    assert_equal(len(reparsed.cues), 1)
    assert_equal(reparsed.cues[0].text, "Hello there.")
    assert_equal(reparsed.cues[0].speaker, "")


def test_srt_glued_cues_without_blank_line() raises:
    """Two cues glued together with no blank-line separator must not
    swallow the second cue's index/timing/text into the first cue."""
    var caps = parse_captions(
        String(
            "1\n00:00:01,000 --> 00:00:02,000\nFirst cue text.\n"
            "2\n00:00:03,000 --> 00:00:04,000\nSecond cue text.\n"
        )
    )
    assert_equal(len(caps.cues), 2)
    assert_equal(caps.cues[0].index, 1)
    assert_equal(caps.cues[0].text, "First cue text.")
    assert_equal(caps.cues[1].index, 2)
    assert_equal(caps.cues[1].text, "Second cue text.")


def test_arrow_in_cue_text_not_a_boundary() raises:
    """A `-->` inside cue text is prose, not a timing line: the cue must
    survive whole rather than being split (or discarded) as a boundary."""
    var caps = parse_captions(
        String("1\n00:00:01,000 --> 00:00:02,000\nUse map --> filter here.\n")
    )
    assert_equal(len(caps.cues), 1)
    assert_equal(caps.cues[0].text, "Use map --> filter here.")
    # And it must round-trip through both serializers unchanged.
    var via_srt = parse_captions(to_srt(caps))
    assert_equal(len(via_srt.cues), 1)
    assert_equal(via_srt.cues[0].text, "Use map --> filter here.")
    var via_vtt = parse_captions(to_vtt(caps))
    assert_equal(len(via_vtt.cues), 1)
    assert_equal(via_vtt.cues[0].text, "Use map --> filter here.")


def test_arrow_in_multiline_text_preserved() raises:
    """A `-->` on a later text line must not truncate the cue or spawn a
    bogus second cue; the full multi-line text is kept."""
    var caps = parse_captions(
        String(
            "1\n00:00:01,000 --> 00:00:02,000\n"
            "first line\nx --> y transform\nthird line\n"
        )
    )
    assert_equal(len(caps.cues), 1)
    assert_equal(caps.cues[0].text, "first line\nx --> y transform\nthird line")


def test_arrow_text_still_splits_glued_real_cue() raises:
    """Even when a cue's text holds a `-->`, a genuinely glued second cue
    (a real timing line, no blank separator) is still split out."""
    var caps = parse_captions(
        String(
            "1\n00:00:01,000 --> 00:00:02,000\nUse map --> filter here.\n"
            "2\n00:00:03,000 --> 00:00:04,000\nSecond cue text.\n"
        )
    )
    assert_equal(len(caps.cues), 2)
    assert_equal(caps.cues[0].text, "Use map --> filter here.")
    assert_equal(caps.cues[1].index, 2)
    assert_equal(caps.cues[1].text, "Second cue text.")


def test_srt_explicit_zero_index_roundtrip() raises:
    """An explicit cue number of 0 is a real index, not the "absent"
    sentinel, and must survive a to_srt round trip unchanged."""
    var caps = parse_captions(
        String("0\n00:00:01,000 --> 00:00:02,000\nZeroth cue.\n")
    )
    assert_equal(caps.cues[0].index, 0)
    var reparsed = parse_captions(to_srt(caps))
    assert_equal(len(reparsed.cues), 1)
    assert_equal(reparsed.cues[0].index, 0)
    assert_equal(reparsed.cues[0].text, "Zeroth cue.")


def test_fixture_vtt_file() raises:
    var caps = parse_captions(open("test/data/sample.vtt", "r").read())
    assert_equal(caps.kind, String(KIND_VTT))
    assert_equal(len(caps.cues), 3)
    assert_equal(caps.cues[0].index, 1)  # "intro" id -> position
    assert_equal(caps.cues[0].start_ms, 1000)
    assert_equal(caps.cues[0].speaker, "Conor Bronsdon")
    assert_equal(caps.cues[0].text, "Welcome to the show.")
    assert_equal(caps.cues[1].index, 2)
    assert_equal(caps.cues[1].text, "A cue with text\nacross two lines.")
    assert_equal(caps.cues[2].speaker, "Guest")
    # Round-trip the real fixture through both serializers.
    var via_srt = parse_captions(to_srt(caps))
    assert_equal(len(via_srt.cues), 3)
    assert_equal(via_srt.cues[0].speaker, "Conor Bronsdon")
    var via_vtt = parse_captions(to_vtt(caps))
    for i in range(len(caps.cues)):
        assert_equal(via_vtt.cues[i], caps.cues[i])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
