#!/bin/bash
set -eu
cd "$(dirname "$0")"
rev=91d838791880d5c619bf9f9971a56d333e30bf7c
upstream=vendor/Kayoko
mkdir -p vendor
if [ ! -d "$upstream" ]; then
  git clone https://github.com/mlgm66/Kayoko.git "$upstream"
fi
git -C "$upstream" checkout --detach "$rev"
python3 - <<'PY'
from pathlib import Path
root = Path("vendor/Kayoko/Core")
build = root / "Makefile"
build.write_text(build.read_text().replace("KayokoCore_FILES += KayokoPasteTipHooks.m", ""))
core = root / "KayokoCore.m"
core.write_text(core.read_text().replace("[KayokoPasteTipHookInstaller installHooks];", ""))
(root / "KayokoCore.plist").write_text('{ Filter = { Bundles = ( "com.apple.springboard" ); }; }\n')
PY
mkdir -p layout/usr/share/doc/com.maxfilp.maxkeys
cp "$upstream/COPYING" layout/usr/share/doc/com.maxfilp.maxkeys/
printf '%s\n' "Kayoko by Alexandra Aurora Göttlicher and contributors, mlgm66 fork" "https://github.com/mlgm66/Kayoko/commit/$rev" > layout/usr/share/doc/com.maxfilp.maxkeys/upstream
