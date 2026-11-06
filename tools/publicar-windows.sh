#!/usr/bin/env bash
# Signs and publishes the Windows ZIP in the update bucket and on GitHub.
# Mirrors app/publicar.sh: the manifest is uploaded last so a version is never
# announced before it can be downloaded. The newest release, Windows or macOS,
# holds the single "Latest" slot.
set -euo pipefail

cd "$(dirname "$0")/.."
repo="newton1057/Prisma"
bucket="prisma-updates"
proyecto="system-kn"
publico="https://storage.googleapis.com/$bucket"
notas="${1:-}"

error() { echo "$1" >&2; exit 1; }

[ -n "$notas" ] || error 'Uso: tools/publicar-windows.sh "Qué cambia en esta versión"'
version=$(sed -n "s/^VERSION = '\([^']*\)'.*/\1/p" windows/common.py)
build=$(sed -n 's/^BUILD = \([0-9][0-9]*\)$/\1/p' windows/common.py)
[ -n "$version" ] && [ -n "$build" ] || error 'No pude leer VERSION y BUILD de windows/common.py'
rama=$(git branch --show-current)

# Lo publicado debe corresponder a un commit que ya esté en GitHub.
[ -z "$(git status --porcelain)" ] || error 'Hay cambios sin commit.'
git fetch --quiet origin "$rama"
[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$rama")" ] || error "Sube primero la rama $rama a GitHub."

# Las apps solo instalan builds mayores: repetir uno no llegaría a nadie.
publicado=$(curl -fsS "$publico/windows-latest.json" 2>/dev/null | python3 -c 'import json, sys; print(json.load(sys.stdin)["build"])' 2>/dev/null || echo 0)
[ "$build" -gt "$publicado" ] || error "Sube BUILD en windows/common.py: el build $publicado ya está publicado."

signer="app/.build/release/UpdateSigner"
if [ ! -x "$signer" ]; then
    (cd app && swift build -c release --product UpdateSigner)
fi

tools/package-windows.sh >/dev/null
paquete="dist/Prisma-Windows-$version.zip"
[ -f "$paquete" ] || error "No se generó $paquete."
archivo="windows/versiones/$version/Prisma-Windows-$version.zip"

trabajo=$(mktemp -d)
trap 'rm -rf "$trabajo"' EXIT
manifiesto="$trabajo/windows-latest.json"
comprobacion="$trabajo/comprobacion.json"

"$signer" manifiesto "$paquete" "$version" "$build" "$archivo" "$notas" > "$manifiesto"

# GitHub primero: la descarga manual queda disponible antes del anuncio.
tag="windows-v$version"
if gh release view "$tag" -R "$repo" >/dev/null 2>&1; then
    gh release upload "$tag" "$paquete" -R "$repo" --clobber
elif git rev-parse "$tag" >/dev/null 2>&1; then
    gh release create "$tag" "$paquete" -R "$repo" --verify-tag \
        --title "Prisma for Windows $version" --notes "$notas"
else
    gh release create "$tag" "$paquete" -R "$repo" --target "$(git rev-parse HEAD)" \
        --title "Prisma for Windows $version" --notes "$notas"
fi
# Latest follows the most recently published release, whichever app it is for.
id=$(gh release view "$tag" -R "$repo" --json databaseId --jq .databaseId)
gh api -X PATCH "repos/$repo/releases/$id" -f make_latest=true >/dev/null

gcloud storage cp "$paquete" "gs://$bucket/$archivo" --project="$proyecto"
gcloud storage cp "$manifiesto" "gs://$bucket/windows-latest.json" --project="$proyecto" \
    --cache-control=no-store --content-type=application/json

# Comprueba lo mismo que verá una app sin sesión.
curl -fsS -o "$comprobacion" "$publico/windows-latest.json"
"$signer" verificar "$comprobacion" "$paquete"
curl -fsSI -o /dev/null "$publico/$archivo"
echo "Publicada la versión $version para Windows (build $build)."
echo "GitHub: https://github.com/$repo/releases/tag/$tag"
echo "Manifiesto: $publico/windows-latest.json"
