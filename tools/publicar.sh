#!/usr/bin/env bash
# Publishes one Prisma release for macOS and Windows with a single version.
# The DMG and the Windows ZIP go to one GitHub release; the two signed ZIPs and
# their manifests go to the bucket, with the manifests uploaded last so a
# version is never announced before it can be downloaded.
set -euo pipefail

cd "$(dirname "$0")/.."
repo="newton1057/Prisma"
bucket="prisma-updates"
proyecto="system-kn"
publico="https://storage.googleapis.com/$bucket"
notas="${1:-}"

error() { echo "$1" >&2; exit 1; }

[ -n "$notas" ] || error 'Uso: tools/publicar.sh "Qué cambia en esta versión"'

# Both apps must share the version and the build, so one release covers both.
version=$(plutil -extract CFBundleShortVersionString raw app/Info.plist)
build=$(plutil -extract CFBundleVersion raw app/Info.plist)
win_version=$(sed -n "s/^VERSION = '\([^']*\)'.*/\1/p" windows/common.py)
win_build=$(sed -n 's/^BUILD = \([0-9][0-9]*\)$/\1/p' windows/common.py)
[ -n "$version" ] && [ -n "$build" ] || error 'No pude leer la versión de app/Info.plist.'
[ -n "$win_version" ] && [ -n "$win_build" ] || error 'No pude leer VERSION y BUILD de windows/common.py.'
[ "$version" = "$win_version" ] || error "Versiones distintas: macOS $version, Windows $win_version. Iguales para publicar una sola release."
[ "$build" = "$win_build" ] || error "Builds distintos: macOS $build, Windows $win_build. Iguales para publicar una sola release."
rama=$(git branch --show-current)

# Lo publicado debe corresponder a un commit que ya esté en GitHub.
[ -z "$(git status --porcelain)" ] || error 'Hay cambios sin commit.'
git fetch --quiet origin "$rama"
[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$rama")" ] || error "Sube primero la rama $rama a GitHub."

# Las apps solo instalan builds mayores: repetir uno no llegaría a nadie.
mac_publicado=$(curl -fsS "$publico/latest.json" 2>/dev/null | python3 -c 'import json, sys; print(json.load(sys.stdin)["build"])' 2>/dev/null || echo 0)
win_publicado=$(curl -fsS "$publico/windows-latest.json" 2>/dev/null | python3 -c 'import json, sys; print(json.load(sys.stdin)["build"])' 2>/dev/null || echo 0)
[ "$build" -gt "$mac_publicado" ] || error "Sube CFBundleVersion en Info.plist: el build $mac_publicado ya está publicado."
[ "$build" -gt "$win_publicado" ] || error "Sube BUILD en windows/common.py: el build $win_publicado ya está publicado."

firmador=app/.build/release/UpdateSigner
if [ ! -x "$firmador" ]; then
    (cd app && swift build -c release --product UpdateSigner)
fi

app/empaquetar.sh
dmg=$(cat dist/ultimo-dmg.txt)
mac_zip=$(cat dist/ultima-actualizacion.txt)
python3 app/verificar_paquete.py "$mac_zip"

tools/package-windows.sh >/dev/null
win_zip="dist/Prisma-Windows-$version.zip"
[ -f "$win_zip" ] || error "No se generó $win_zip."

mac_archivo="versiones/$version/$(basename "$mac_zip")"
win_archivo="windows/versiones/$version/$(basename "$win_zip")"

trabajo=$(mktemp -d)
trap 'rm -rf "$trabajo"' EXIT
manifiesto_mac="$trabajo/latest.json"
manifiesto_win="$trabajo/windows-latest.json"
firmado_mac="$trabajo/latest-publicado.json"
firmado_win="$trabajo/windows-latest-publicado.json"

"$firmador" manifiesto "$mac_zip" "$version" "$build" "$mac_archivo" "$notas" > "$manifiesto_mac"
"$firmador" manifiesto "$win_zip" "$version" "$build" "$win_archivo" "$notas" > "$manifiesto_win"
"$firmador" verificar "$manifiesto_mac" "$mac_zip"
"$firmador" verificar "$manifiesto_win" "$win_zip"

# GitHub first: the manual downloads exist before the bucket announces anything.
tag="v$version"
if gh release view "$tag" -R "$repo" >/dev/null 2>&1; then
    gh release upload "$tag" "$dmg" "$win_zip" -R "$repo" --clobber
else
    gh release create "$tag" "$dmg" "$win_zip" -R "$repo" \
        --target "$(git rev-parse HEAD)" --title "Prisma $version" --notes "$notas"
fi
# The newest release, Windows or macOS, holds the single "Latest" slot.
id=$(gh release view "$tag" -R "$repo" --json databaseId --jq .databaseId)
gh api -X PATCH "repos/$repo/releases/$id" -f make_latest=true >/dev/null

gcloud storage cp "$mac_zip" "gs://$bucket/$mac_archivo" --project="$proyecto"
gcloud storage cp "$win_zip" "gs://$bucket/$win_archivo" --project="$proyecto"
gcloud storage cp "$manifiesto_mac" "gs://$bucket/latest.json" --project="$proyecto" \
    --cache-control=no-store --content-type=application/json
gcloud storage cp "$manifiesto_win" "gs://$bucket/windows-latest.json" --project="$proyecto" \
    --cache-control=no-store --content-type=application/json

# Comprueba lo mismo que verá una app sin sesión.
curl -fsS -o "$firmado_mac" "$publico/latest.json"
curl -fsS -o "$firmado_win" "$publico/windows-latest.json"
"$firmador" verificar "$firmado_mac" "$mac_zip"
"$firmador" verificar "$firmado_win" "$win_zip"
curl -fsSI -o /dev/null "$publico/$mac_archivo"
curl -fsSI -o /dev/null "$publico/$win_archivo"
echo "Publicada la versión $version (build $build) para macOS y Windows."
echo "GitHub: https://github.com/$repo/releases/tag/$tag"
echo "Manifiestos: $publico/latest.json y $publico/windows-latest.json"
