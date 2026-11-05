#!/bin/bash
# Publica la versión de Info.plist en GitHub (DMG) y en el bucket (zip firmado).
set -euo pipefail

cd "$(dirname "$0")/.."
repo="newton1057/Prisma"
bucket="prisma-updates"
proyecto="system-kn"
publico="https://storage.googleapis.com/$bucket"
notas="${1:-}"

error() { echo "$1" >&2; exit 1; }

[ -n "$notas" ] || error 'Uso: app/publicar.sh "Qué cambia en esta versión"'
version=$(plutil -extract CFBundleShortVersionString raw app/Info.plist)
build=$(plutil -extract CFBundleVersion raw app/Info.plist)
rama=$(git branch --show-current)

# Lo publicado debe corresponder a un commit que ya esté en GitHub.
[ -z "$(git status --porcelain)" ] || error "Hay cambios sin commit."
git fetch --quiet origin "$rama"
[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$rama")" ] || error "Sube primero la rama $rama a GitHub."

# Las apps solo instalan builds mayores: repetir uno no llegaría a nadie.
publicado=$(curl -fsS "$publico/latest.json" 2>/dev/null | python3 -c 'import json, sys; print(json.load(sys.stdin)["build"])' 2>/dev/null || echo 0)
[ "$build" -gt "$publicado" ] || error "Sube CFBundleVersion en Info.plist: el build $publicado ya está publicado."

app/empaquetar.sh
dmg=$(cat dist/ultimo-dmg.txt)
paquete=$(cat dist/ultima-actualizacion.txt)
python3 app/verificar_paquete.py "$paquete"

firmador=app/.build/release/UpdateSigner
archivo="versiones/$version/$(basename "$paquete")"
manifiesto=$(mktemp -t prisma-latest)
comprobacion=$(mktemp -t prisma-publicado)
trap 'rm -f "$manifiesto" "$comprobacion"' EXIT
"$firmador" manifiesto "$paquete" "$version" "$build" "$archivo" "$notas" > "$manifiesto"
"$firmador" verificar "$manifiesto" "$paquete"

# El manifiesto va al final para no anunciar nunca algo que aún no se puede descargar.
if gh release view "v$version" -R "$repo" >/dev/null 2>&1; then
    gh release upload "v$version" "$dmg" -R "$repo" --clobber
else
    gh release create "v$version" "$dmg" -R "$repo" \
        --target "$(git rev-parse HEAD)" --title "Prisma $version" --notes "$notas"
fi
gcloud storage cp "$paquete" "gs://$bucket/$archivo" --project="$proyecto"
gcloud storage cp "$manifiesto" "gs://$bucket/latest.json" --project="$proyecto" \
    --cache-control=no-store --content-type=application/json

# Comprueba lo mismo que verá una app sin sesión.
curl -fsS -o "$comprobacion" "$publico/latest.json"
"$firmador" verificar "$comprobacion" "$paquete"
curl -fsSI -o /dev/null "$publico/$archivo"
echo "Publicada la versión $version (build $build)."
