# Historical issue 87 measurements

The OC1 SSE logger, model-driven long-chat seeder, and `send` / `gfx-stream`
measurement scenarios were retired with OC1 support on 2026-10-15. Existing
measurement evidence remains historical; it does not qualify OC2 performance.

`measure.sh` retains the protocol-independent `cold`, `project`, `settings`,
and `gfx-scroll` scenarios. Use an already prepared synthetic conversation for
scrolling. `frames.py`, `timestats.py`, and the mock model remain usable helpers.
