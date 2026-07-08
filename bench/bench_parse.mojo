"""Throughput benchmark for `parse_captions` over the bundled sample files.

Reports wall-clock per parse and MB/s. Run compiled for meaningful numbers:
`mojo build -I src bench/bench_parse.mojo -o .bench_parse && ./.bench_parse`
(or `pixi run bench`). The inputs are the same SRT/WebVTT fixtures the unit
tests parse, so the benchmark measures the real parse path.
"""
from std.time import perf_counter_ns

from captions import parse_captions


def bench(path: String, iterations: Int) raises:
    var source = open(path, "r").read()
    var size_mb = Float64(source.byte_length()) / (1024.0 * 1024.0)
    # Warmup + correctness anchor: count cues once, require stability.
    var warm = parse_captions(source.copy())
    var n = len(warm.cues)
    var start = perf_counter_ns()
    for _ in range(iterations):
        var parsed = parse_captions(source.copy())
        if len(parsed.cues) != n:
            raise Error("inconsistent parse")
    var elapsed_ns = perf_counter_ns() - start
    var per_parse_ms = Float64(elapsed_ns) / Float64(iterations) / 1e6
    var mb_per_s = size_mb / (per_parse_ms / 1000.0)
    print(path)
    print(t"  {source.byte_length()} bytes, {n} cues:")
    print(t"  {per_parse_ms} ms/parse, {mb_per_s} MB/s")


def main() raises:
    bench("test/data/sample.srt", 20000)
    bench("test/data/sample.vtt", 20000)
