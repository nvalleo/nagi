# NagiMozcProto

This target holds Swift types generated from Mozc's `commands.proto` and its
dependencies.

The `.proto` files themselves are **not vendored into this repository** — we
fetch them from a pinned `google/mozc` tag at build-configure time and
regenerate the Swift source with `protoc-gen-swift`.

Why not vendor:

1. Mozc is licensed BSD-3-Clause; keeping the fetch step explicit makes the
   dependency and its licence visible in the build log.
2. `commands.proto` is treated as internal by Mozc. Pinning a tag and
   regenerating on bumps forces us to notice when the wire format changes,
   instead of silently drifting.

A `scripts/fetch-mozc-proto.sh` will land alongside M0.
