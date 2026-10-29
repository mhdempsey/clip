#!/bin/sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
assets_dir="$repo_root/AppStore/ReviewAssets"
bundle_name="Clip-Demo.clipbook"
archive_name="Clip-Demo.clipbook.zip"

cd "$assets_dir"
rm -f "$archive_name"
/usr/bin/zip -qry "$archive_name" "$bundle_name"
echo "$assets_dir/$archive_name"
