#!/bin/bash
# Instalador do Varys Monitor para macOS.
#
#   curl -fsSL https://varys.oclerio.com/install-mac | bash
#
# POR QUE UM SCRIPT, e não só o DMG na landing page:
#
#   O app é assinado com certificado local, sem Developer ID da Apple (US$ 99/ano).
#   Um DMG baixado pelo NAVEGADOR recebe a marca de quarentena
#   (com.apple.quarantine), e aí o Gatekeeper bloqueia a primeira abertura com
#   "não foi possível verificar" — no macOS 15+ nem o botão direito › Abrir
#   resolve mais; o usuário tem que fuçar em Ajustes › Privacidade e Segurança.
#
#   Um download por CURL não recebe marca nenhuma (verificado em 2026-09-01:
#   navegador → com.apple.quarantine presente; curl → ausente). Sem quarentena,
#   o Gatekeeper nunca é acionado e o app abre como qualquer outro. É o mesmo
#   mecanismo que o Homebrew usa desde sempre.
#
#   O que se perde em relação à notarização: a varredura de malware da Apple.
#   O que se ganha: instalação de um comando, sem custo. Quando o produto tiver
#   Developer ID, este script continua funcionando — só deixa de ser necessário.
set -euo pipefail

# Modelo de publicação (02/09): os binários oficiais moram no repositório
# público github.com/oclerio/varys-releases — o mesmo release carrega o .exe do
# Windows e o .dmg do Mac. varys.oclerio.com REDIRECIONA para lá; este script
# fala com o GitHub direto para não depender do redirecionamento.
REPO="${VARYS_REPO_RELEASES:-oclerio/varys-releases}"
API="https://api.github.com/repos/$REPO/releases/latest"
DEST="${VARYS_INSTALL_DIR:-/Applications}"
APP="Varys Monitor.app"

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "ERRO: $*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "este instalador é para macOS."
[ "$(uname -m)" = "arm64" ]  || fail "esta build é para Apple Silicon (M1 ou mais novo)."

say "Varys Monitor — instalador para macOS"

# 1. qual é a release mais recente, e qual asset é o do Mac
INFO="$(curl -fsSL --max-time 30 "$API")" \
  || fail "não consegui falar com o GitHub — verifique a conexão."
read -r VER DMG_URL <<EOF2
$(printf '%s' "$INFO" | /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)
ver = (d.get("tag_name") or "").lstrip("v")
url = next((a["browser_download_url"] for a in d.get("assets", [])
            if a["name"].endswith(".dmg")), "")
print(ver, url)')
EOF2
[ -n "$VER" ] || fail "a release respondeu sem versão."
[ -n "$DMG_URL" ] || fail "a release $VER ainda não tem o instalador do macOS."
say "  versão publicada: $VER"

# 2. baixa SEM quarentena (curl não aplica com.apple.quarantine)
TMP="$(mktemp -d /tmp/varys-install.XXXXXX)"
trap 'rm -rf "$TMP"; [ -n "${VOL:-}" ] && hdiutil detach "$VOL" -force >/dev/null 2>&1 || true' EXIT
say "  baixando…"
curl -fL --progress-bar --max-time 900 -o "$TMP/varys.dmg" "$DMG_URL" \
  || fail "o download falhou."
SIZE=$(stat -f%z "$TMP/varys.dmg")
[ "$SIZE" -gt 10000000 ] || fail "o arquivo veio pequeno demais ($SIZE bytes) — download incompleto?"

# 3. monta e valida ANTES de tocar em /Applications
VOL="$(hdiutil attach "$TMP/varys.dmg" -readonly -nobrowse 2>/dev/null | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)"
[ -d "$VOL/$APP" ] || fail "o DMG não contém o $APP."
codesign --verify --deep --strict "$VOL/$APP" 2>/dev/null \
  || fail "a assinatura do app não confere — download corrompido, não vou instalar."

# 4. instala (fechando o app se estiver aberto, preservando gravações — elas
#    vivem em ~/Library/Application Support/VarysMonitor, fora do bundle)
if [ -d "$DEST/$APP" ]; then
  say "  substituindo a versão instalada…"
  osascript -e 'quit app "Varys Monitor"' >/dev/null 2>&1 || true
  sleep 2
  pkill -f "Varys Monitor.app/Contents" >/dev/null 2>&1 || true
  sleep 1
  rm -rf "$DEST/$APP"
fi
cp -R "$VOL/$APP" "$DEST/" || fail "não consegui copiar para $DEST (permissão?)."
hdiutil detach "$VOL" -force >/dev/null 2>&1; VOL=""

# 5. cinto e suspensório: se algum passo anterior (ou um download antigo pelo
#    navegador) deixou quarentena, sai agora
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

say "✅ Varys Monitor $VER instalado em $DEST."
say "   Na primeira gravação o macOS vai pedir o Microfone; para gravar o áudio"
say "   das reuniões, ligue também Gravação de Tela em Ajustes › Privacidade."
[ -z "${VARYS_INSTALL_DIR:-}" ] && open "$DEST/$APP" || true
