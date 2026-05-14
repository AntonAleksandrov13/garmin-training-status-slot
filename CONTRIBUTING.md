# Contributing

Bug reports, ideas, and PRs welcome.

## Getting started

1. Install the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) (9.1.0+).
2. Generate a developer key:
   ```bash
   openssl genrsa | openssl pkcs8 -topk8 -outform DER -nocrypt -out developer_key.der
   ```
3. Build:
   ```bash
   CIQ_KEY=$PWD/developer_key.der ./scripts/build.sh
   ```
4. Run in the simulator:
   ```bash
   "$CIQ_SDK/bin/connectiq" &
   "$CIQ_SDK/bin/monkeydo" bin/trainingstatusslot.prg epix2
   ```

## Style

- Monkey C only — no external barrels.
- Keep `BanditView.mc` focused on layout + state. Push pure data/logic (status mappings, classifications, color palettes) into the `*Provider.mc` modules.
- Vector icons go in `Icons.mc`. Anchor them at `(cx, cy)` and accept a `size` and `color`.
- No emojis in source unless they render reliably in Garmin's system font (most don't — use `Icons.mc` instead).
- Match existing brace / indent style (4-space indent, K&R braces).

## Adding a new device

1. Add an `<iq:product id="..."/>` line to `manifest.xml`.
2. Build with `-e` to confirm it compiles for the new device.
3. If the device is MIP (not AMOLED), check contrast on grey-on-black text — the palette was tuned for AMOLED.

## Adding a metric

1. Read the value in `BanditView.drawDataFields` (use `ActivityMonitor`, `Activity`, `SensorHistory`, `Weather`, or `Complications`).
2. Add a vector glyph in `Icons.mc` if you need a new icon.
3. Wire it into `drawCellCentered` with one of the existing icon symbols.
4. Watch for permission errors at build time — Garmin will tell you what to add to `manifest.xml`.

## Releasing

1. Bump `version=` in `manifest.xml`.
2. Run `./scripts/build.sh` — both `.prg` and `.iq` rebuild.
3. Upload `bin/trainingstatusslot.iq` to the Connect IQ developer dashboard.
4. Tag the commit: `git tag v0.x.y && git push --tags`.

Never change the app `id=` in `manifest.xml` after publishing — Garmin treats a new ID as a brand-new app and existing installs lose update visibility.
