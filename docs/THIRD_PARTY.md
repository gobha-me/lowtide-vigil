# Third-party materials

## Fonts

Pixelify Sans (variable weight) and Silkscreen (regular and bold) are bundled
unmodified from the official [google/fonts repository](https://github.com/google/fonts),
revision `6c1dbe27dcf7d817d4b62cec033ba77fa8e2a5ec`, directories `ofl/pixelifysans` and `ofl/silkscreen`.
Each family includes its original `OFL.txt` (SIL Open Font License 1.1).
The variable TTF filename is normalized for portable asset paths.
Both builds load these local files and need no font service.

## GUT

GUT is vendored under `addons/gut` from pinned release **v9.6.1**:
<https://github.com/bitwes/Gut/releases/tag/v9.6.1>.
Source archive: <https://github.com/bitwes/Gut/archive/refs/tags/v9.6.1.zip>.
Only the upstream addon and its MIT licence are included; no project tests
are supplied. The editor plugin is available but disabled by default.
Third-party GDScript is excluded from our gdtoolkit style checks. Godot
imports the addon; release exports exclude `addons/gut/*` because this is
development tooling. The standalone licence is transcribed from the upstream
licence block at the end of `gut.gd`.

## CI tool downloads

Godot **4.7.2-stable**, engine and Linux templates, comes from the official
[release](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable).
`tools/install-godot-ci.sh` pins the SHA-512 hashes published in that release's
[SHA512-SUMS.txt](https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/SHA512-SUMS.txt).
The engine is MIT licensed; its distribution includes the upstream notices.

Gitleaks **8.24.3** is downloaded from its official
[release](https://github.com/gitleaks/gitleaks/releases/tag/v8.24.3) and checked
against the pinned SHA-256 in its published checksum file. Gdtoolkit is
pinned to **4.5.0**. CI does not format or lint vendored addon sources.
