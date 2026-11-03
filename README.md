# Lowtide Vigil

Once a year the sea uncovers the drowned abbey of St. Maren for a single
night. The Saint below is weeping. As the last bell-keeper, carry the vigil
lantern down before dawn brings the water back. The town waits with candles.

Godot **4.7.2**, GDScript, Linux first. Open `project.godot` at the repository
root, or run `godot4 --path .`. The Milestone 1 slice covers **The Overgrown
Nave**: four rooms chosen by reward signs, then **The Drowned Tolling** and
a Level 1 victory or defeat. It includes six Kindles, a Font, the
Candlewright's shop, embers, and a second boss phase. GUT v9.6.1 tests cover
gameplay and verification tooling.

Move with WASD or the left stick. Fire with the mouse (hold left button),
arrow keys or right stick. Dash with Space, Shift, right mouse, controller
A or RB; dashing grants invulnerability. Pause with Esc, P or Start.
Use mouse, arrows/Enter or controller D-pad/A for menus. Walk into a signed
door after clearing a room. Your flames are health and light: the lantern
radius scales by `0.5 + 0.5 * hp / maxhp`.

The full browser reference remains at [web/lowtide-vigil.html](web/lowtide-vigil.html).
Open it directly, or serve the repo with `python3 -m http.server 8000` and
visit `/web/lowtide-vigil.html`. Fonts are bundled for offline play.
The browser has the original five-floor run; the native slice is a focused
Level 1 implementation rather than a feature-complete port. Browser audio,
touch controls, remaining levels, and the full upgrade pool are future
native work. Shore windows and starting-lantern unlocks are planned in the
[DRAFT story hook](docs/story-hook.md); they are not awarded for slice wins.

Local verification (use `godot` instead of `godot4` if that is your binary):

```sh
godot4 --headless --path . --import
gdlint scripts
gdformat --check scripts
bash tools/term-gate.sh
gitleaks git --redact --no-banner .
mkdir -p build/linux
heavy-run godot4 --headless --path . --export-release "Linux/X11"
heavy-run bash tools/winning-playthrough.sh
```

The export produces `build/linux/lowtide-vigil.x86_64` and its `.pck`; ship
both together. The input-only exported win check and retained evidence are
described in [winning playthrough](docs/winning-playthrough.md).
Install the matching export templates first. `heavy-run` is
the shared build host's serialization wrapper; on an unshared workstation,
run the Godot command directly. Vendored addon sources retain upstream
formatting and licences and are excluded from gdtoolkit style checks.
CI has one `ci` job and checks both downloads against pinned checksums.

The terminology gate uses only `git ls-files`: documentation, GDScript
string literals, scene/resource/data strings and web presentation text
(including canvas/DOM UI). Code identifiers, code comments, CSS and physics
properties are outside its scope. Its allowlist permits only tracked
licence/attribution files and the gate itself; every entry needs a reason.
See [third-party sources](docs/THIRD_PARTY.md) for pins and licence locations.
