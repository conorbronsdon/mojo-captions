"""The parsed-caption data model shared by the SRT and WebVTT parsers."""

comptime KIND_SRT = "srt"
comptime KIND_VTT = "vtt"


@fieldwise_init
struct Cue(Copyable, Movable, Writable, Equatable):
    """One subtitle cue. Empty string means the field was absent.

    `index` is the SRT cue number or the numeric WebVTT cue identifier;
    cues without one get their 1-based position in the document by the
    time parsing returns. A negative `index` (e.g. -1) is the "absent"
    sentinel for hand-built cues: `to_srt`/`to_vtt` substitute the
    cue's document position for it, but pass an explicit `0` through
    unchanged, since `0` is a real identifier, not "absent".
    `speaker` is filled from a WebVTT voice span (`<v Name>`) or the
    plain "Name: text" convention on the cue's first line.
    """

    var index: Int
    var start_ms: Int
    var end_ms: Int
    var speaker: String
    var text: String

    def __eq__(self, other: Self) -> Bool:
        return (
            self.index == other.index
            and self.start_ms == other.start_ms
            and self.end_ms == other.end_ms
            and self.speaker == other.speaker
            and self.text == other.text
        )

    def write_to(self, mut writer: Some[Writer]):
        writer.write("Cue(", self.index, ": ", self.start_ms, "-", self.end_ms)
        if self.speaker.byte_length() > 0:
            writer.write(" ", self.speaker)
        writer.write(")")


@fieldwise_init
struct Captions(Copyable, Movable, Writable):
    """A parsed caption document: format kind plus ordered cues."""

    var kind: String  # KIND_SRT or KIND_VTT
    var cues: List[Cue]

    def write_to(self, mut writer: Some[Writer]):
        writer.write("Captions(", self.kind, ", ", len(self.cues), " cues)")
