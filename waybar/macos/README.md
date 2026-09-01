# macOS menu bar (parked for Hyprland)

This is the macOS-styled waybar built on 2026-09-01, kept here rather than in
`waybar/` because the **sway session is deliberately the plain rectangular
one** and gets the original compact bar instead. The macOS look now belongs to
the separate Hyprland session, so this is where that session should point.

Nothing symlinks these files today. `install.sh` links `waybar/config` and
`waybar/style.css` only.

## What differs from the normal bar

* `height` 26 instead of 16, and `modules-center` is empty. The clock moves to
  the far right, where macOS puts it.
* An Apple glyph (``) at the far left, then `sway/window` showing the
  focused app name in bold. That name is the only bold text in the bar.
* Every status module is a **monochrome white glyph**. This is the thing that
  actually makes it read as macOS: the real menu bar has no colour except the
  orange privacy dot, and it uses symbols where a Linux bar uses words.
* The ten status scripts are **unmodified**. A fixed glyph in a custom module's
  `format` overrides the script's emitted `text`, while `class` and `tooltip`
  still come from the script, so the colour policy in the stylesheet keeps
  working off the live classes.
* The clock is `custom/clock` running `date(1)`, not the built-in `clock`
  module. waybar's clock uses fmt's chrono formatter, which rejects the
  glibc-only padding specifiers `%-d`, `%e` and `%l` with
  `chrono format error: invalid specifier in chrono-specs`, and then renders
  as nothing at all with only a log line to say why.

## Known unfinished business

* The wifiband signal glyph renders as empty boxes; it is missing from Symbols
  Nerd Font at that codepoint.
* Glyph sizes are inconsistent because they come from two different Unicode
  planes. FontAwesome glyphs are drawn on a smaller em than Material Design
  ones, which is why `#custom-airdrop` and `#custom-github` carry their own
  `font-size`.
* Four numeric readouts (memory, cpu, temperature, battery) are still on the
  right, where macOS would have none.
