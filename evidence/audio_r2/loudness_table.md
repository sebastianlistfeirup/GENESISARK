# Audio mix check (D-064)

Movie Maker clips 960x540 @30 fps, audio from the Master bus, ffmpeg ebur128. `voice` = Voice bus solo, `beds` = Voice bus muted; M = momentary loudness (400 ms) sampled every 100 ms; margin = median voice M minus median beds M while the voice is active (voice M > -45 LUFS).

| scene | full mix I (LUFS) before → after | LRA before → after | beds, no voice (M median) | beds under voice | voice (M median) | dialogue margin (LU) |
|---|---|---|---|---|---|---|
| menu | -30.9 → -26.4 | 1.3 → 1.8 | -30.9 → -26.5 | – → – | – → – | – → – |
| ship_fresh | -18.9 → -20.1 | 13.7 → 9.1 | -31.6 → -27.3 | -30.9 → -32.7 | -17.7 → -17.7 | 13.2 → 15.0 |
| ship_powered | -18.1 → -19.5 | 14.2 → 10.0 | -31.6 → -27.1 | -30.6 → -31.9 | -17.7 → -17.7 | 12.9 → 14.2 |
| flight | -22.6 → -22.2 | 13.5 → 10.7 | -38.4 → -36.3 | -31.1 → -33.2 | -17.5 → -17.5 | 13.6 → 15.7 |
| descent | -32.0 → -27.3 | 4.9 → 8.0 | -32.9 → -29.1 | – → – | – → – | – → – |
| surface | -17.6 → -18.5 | 15.6 → 12.3 | -33.7 → -30.6 | -35.1 → -37.5 | -17.3 → -17.3 | 17.8 → 20.2 |
| colony | -32.5 → -29.3 | 0.8 → 0.7 | -32.7 → -29.3 | – → – | – → – | – → – |
| ending | -37.4 → -26.5 | 7.1 → 7.1 | -39.9 → -28.9 | – → – | – → – | – → – |
