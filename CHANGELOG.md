# Changelog

## 0.1.0 — 2026-07-05

Initial release. Liberal SRT and WebVTT parser with format auto-detection,
both timestamp separator conventions, speaker extraction (WebVTT voice
spans and the plain `Speaker Name:` convention), WebVTT NOTE/STYLE/REGION
and cue-settings handling, CRLF/BOM support, and glued-cue recovery.
Round-trip `to_srt`/`to_vtt` serialization, plus transcript utilities
(`plain_text`, `cues_between`, `duration_ms`). 29 tests, fuzz-tested
against 1,300+ mutated documents with zero crashes and zero hangs.
