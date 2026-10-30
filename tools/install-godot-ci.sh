#!/usr/bin/env bash
# Official Godot 4.7.2 release archives, pinned to their published SHA-512 sums.
set -euo pipefail
base=https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable
engine=Godot_v4.7.2-stable_linux.x86_64.zip
templates=Godot_v4.7.2-stable_export_templates.tpz
stage=$(mktemp -d)
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1])" "$stage"' EXIT
cd "$stage"
curl --fail --location --retry 3 "$base/$engine" -o "$engine"
curl --fail --location --retry 3 "$base/$templates" -o "$templates"
cat > SHA512-SUMS.txt <<'SUMS'
9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65  Godot_v4.7.2-stable_linux.x86_64.zip
ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079  Godot_v4.7.2-stable_export_templates.tpz
SUMS
sha512sum --check SHA512-SUMS.txt
unzip -q "$engine"
mkdir -p "$GITHUB_WORKSPACE/.ci-bin"
install -m 755 Godot_v4.7.2-stable_linux.x86_64 "$GITHUB_WORKSPACE/.ci-bin/godot"
echo "$GITHUB_WORKSPACE/.ci-bin" >> "$GITHUB_PATH"
unzip -q "$templates"
template_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.7.2.stable"
mkdir -p "$template_dir"
cp templates/linux_* "$template_dir/"
