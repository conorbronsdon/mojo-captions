# Security Policy

mojo-captions is a pure-Mojo SRT/WebVTT parsing library with no network
access, no authentication, and no secrets handling — it reads a caption
file and returns structured data. The main risk surface is malformed or
adversarial input causing a crash or hang, which the fuzz suite
(`test/fuzz_runner.mojo`) specifically targets.

If you find a parsing input that crashes, hangs, or otherwise misbehaves
in a way that looks security-relevant (e.g. out-of-bounds access,
unbounded memory growth), please report it via a
[GitHub issue](https://github.com/conorbronsdon/mojo-captions/issues),
including the offending file or a minimal reproduction.

This is a personal open-source project maintained on a best-effort
basis — there's no formal SLA for response time, but reports are
welcome and taken seriously.
