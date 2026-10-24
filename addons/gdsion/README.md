# GDSiON runtime

Upstream: https://github.com/YuriSizov/gdsion
Pinned release: **0.7-beta8**
Binary source: https://github.com/YuriSizov/gdsion/releases/download/0.7-beta8/libgdsion-linux.zip

The two Linux x86_64 libraries are unmodified release artifacts. The extension
manifest was adapted to this directory. `LICENSE` preserves both the GDSiON and
original SiON MIT notices. Summit's sequencer/UI are original code; Bosca Ceoil
Blue informed the pattern-editor approach, but no Bosca source or assets are bundled.

This initial integration includes **Linux x86_64 only**. For other export targets,
add the matching libraries from the same upstream release and their manifest
entries before exporting. Do not silently mix GDSiON versions.

Tested with Godot 4.7.2. One SiONDriver is created lazily and kept for the app's
lifetime, because the library has global state and recreating drivers caused a
native crash during testing. Leaving Music Studio stops streaming. Basic presets
are serialized as MML custom voices (`%5`); special dual-oscillator presets do not
serialize completely, so the initial instrument list uses supported voices.

SHA-256:

```text
e335cc481e719417a0413a9f569e9b0f49a59af387442595bcd627dea900d69e  libgdsion.linux.template_debug.x86_64.so
1569750d1a5ec2d290c69f5db367b9b2ea192f179a72af2bcd13a0f8ae1be690  libgdsion.linux.template_release.x86_64.so
```

Known verification limitation: shutdown can report one leaked
`AudioStreamGeneratorPlayback` from the native runtime after playback. Transport,
rendering, and screen reentry checks pass; this is still a beta dependency.
