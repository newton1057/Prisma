#!/bin/bash
# Builds the self-updating package (zip) and the manual-fallback DMG.
set -euo pipefail

cd "$(dirname "$0")/.."
root="$PWD"
app="$root/app/Prisma.app"
version=$(plutil -extract CFBundleShortVersionString raw app/Info.plist)
build=$(plutil -extract CFBundleVersion raw app/Info.plist)
dist="$root/dist"

mkdir -p "$dist"
stage=$(mktemp -d "$dist/instalador.XXXXXX")
trap 'rm -rf "$stage"' EXIT

"$root/app/build.sh"

ditto "$app" "$stage/Prisma.app"
ln -sfn /Applications "$stage/Aplicaciones"
codesign --force --deep --sign - "$stage/Prisma.app"

update="$dist/Prisma-$version.zip"
dmg="$dist/Prisma-$version.dmg"
ditto -c -k --keepParent "$stage/Prisma.app" "$update"
hdiutil create -volname "Prisma" -srcfolder "$stage" -format UDZO -fs HFS+ -ov "$dmg"

printf '%s\n' "$dmg" > "$dist/ultimo-dmg.txt"
printf '%s\n' "$update" > "$dist/ultima-actualizacion.txt"
echo "DMG creado: $dmg"
echo "Actualización creada: $update"
