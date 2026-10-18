#!/usr/bin/env bash
# A narrow compatibility fix for images whose service descriptor is id.waydro.waydroid.IPlatform.
# Run only if host service calls fail with a Binder token mismatch.
set -euo pipefail
file=/usr/lib/waydroid/tools/interfaces/IPlatform.py
backup="$file.pre-cm3588-atv"
[[ -f "$file" ]] || { echo "Missing $file" >&2; exit 1; }
value="$(sed -n 's/^INTERFACE = "\(.*\)"$/\1/p' "$file")"
case "$value" in
  id.waydro.waydroid.IPlatform) echo 'Already matches Android service descriptor'; exit 0 ;;
  lineageos.waydroid.IPlatform) ;;
  *) echo "Unexpected descriptor: $value (no changes)" >&2; exit 1 ;;
esac
sudo test ! -e "$backup" || { echo "Backup already exists: $backup" >&2; exit 1; }
sudo cp -a "$file" "$backup"
sudo python3 - "$file" <<'PYCODE'
from pathlib import Path
import sys
p=Path(sys.argv[1]); data=p.read_text()
a='INTERFACE = "lineageos.waydroid.IPlatform"'
b='INTERFACE = "id.waydro.waydroid.IPlatform"'
assert data.count(a) == 1
p.write_text(data.replace(a,b,1))
PYCODE
sudo python3 -m py_compile "$file"
echo "Patched $file; original at $backup. A package upgrade may overwrite the patch."
