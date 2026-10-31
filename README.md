# BreathFloat (working name)

A soft breathing bubble that floats over every app, controlled from the menu bar.

- Build: `bin/build` (makes `build/BreathFloat.app`, ad-hoc signed)
- Panel from the menu bar icon: show/hide, pace, size and opacity sliders, colour, sound (our breath waves or one of macOS's 8 Background Sounds) with volume, clicks pass through, open at login
- Hold ⌘ and drag the bubble to move it; its place is remembered. It is left out of screen shares and recordings.
- `BreathFloat --snapshot <folder>` draws the panel (light and dark) and each colour to PNGs without opening a window.
- `BreathFloat --check-sounds` lists the sounds and checks each file loads, without playing them.
