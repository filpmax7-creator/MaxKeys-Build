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
helper = root.parent / "Helper" / "Makefile"
helper.write_text(helper.read_text().replace("KayokoHelper_CFLAGS += -fobjc-arc", "KayokoHelper_CFLAGS += -fobjc-arc -Wno-error=deprecated-declarations"))
build = root / "Makefile"
build.write_text(build.read_text().replace("KayokoCore_FILES += KayokoPasteTipHooks.m", ""))
# This build uses the conventional /var/jb rootless package layout.
compat = root.parent / "Preferences" / "MaxKeysRootlessPath.h"
compat.write_text('''#import <Foundation/Foundation.h>
static inline NSString *jbroot(NSString *path) {
    if ([path hasPrefix:@"/var/mobile/"]) return path;
    return [@"/var/jb" stringByAppendingPathComponent:path];
}
''')
for directory in ("Core", "Helper", "Shared"):
    for source in (root.parent / directory).rglob("*"):
        if source.suffix in (".m", ".mm", ".h"):
            original = source.read_text()
            updated = original.replace("<roothide.h>", '"MaxKeysRootlessPath.h"')
            if original != updated:
                source.write_text(updated)
# Keep the list available for successive selections; the panel retains its own close control.
history = next(root.rglob("KayokoHistoryListViewController.m"))
source = history.read_text()
start = source.index("    [[self actionHandler] activateItem:item", source.index("didSelectRowAtIndexPath:"))
end = source.index("}];", start) + 3
history.write_text(source[:start] + """    [[self actionHandler] activateItem:item
                            historyKey:[self historyKey]
                            completion:nil];""" + source[end:])
core = root / "KayokoCore.m"
core.write_text(core.read_text().replace("[KayokoPasteTipHookInstaller installHooks];", ""))
(root / "KayokoCore.plist").write_text('{ Filter = { Bundles = ( "com.apple.springboard" ); }; }\n')
PY
resources=layout/Library/PreferenceBundles/KayokoPreferences.bundle
mkdir -p "$resources"
cp -R "$upstream/Preferences/Resources/en.lproj" "$upstream/Preferences/Resources/zh-Hans.lproj" "$resources/"
cp "$upstream"/Preferences/Resources/*.aiff "$upstream"/Preferences/Resources/*.png "$resources/"
mkdir -p layout/usr/share/doc/com.maxfilp.maxkeys
cp "$upstream/COPYING" layout/usr/share/doc/com.maxfilp.maxkeys/
printf '%s\n' "Kayoko by Alexandra Aurora Göttlicher and contributors, mlgm66 fork" "https://github.com/mlgm66/Kayoko/commit/$rev" > layout/usr/share/doc/com.maxfilp.maxkeys/upstream
