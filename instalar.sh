#!/usr/bin/env bash
# =============================================================================
# instalar.sh — transforma a TV Box em video game de verdade
#
#   curl -fsSL https://raw.githubusercontent.com/astaviolet/tv-jogos/main/instalar.sh | bash
#
# O que ele faz:
#   1. instala o RetroArch 32 bits (versao que roda no Android 7 / Cortex-A7)
#   2. baixa e instala 7 cores: NES, SNES, Game Boy, Mega Drive, GBA, PS1, Doom
#   3. instala o FREEDOOM (Doom completo, gratuito e legal) pra jogar na hora
#   4. pronto: abre o RetroArch na TV
#
# Nao mexe em nada que ja existe. Nao desinstala nada.
# =============================================================================
set -uo pipefail

PKG="com.retroarch.ra32"
APK_URL="https://buildbot.libretro.com/stable/1.22.2/android/RetroArch_ra32.apk"
CORES_BASE="https://buildbot.libretro.com/nightly/android/latest/armeabi-v7a"
DOOM_URL="https://github.com/freedoom/freedoom/releases/download/v0.13.0/freedoom-0.13.0.zip"
CORES="fceumm snes9x gambatte genesis_plus_gx mgba prboom pcsx_rearmed"
DIR="$HOME/tv-jogos"

azul(){ printf '\033[1;36m%s\033[0m\n' "$*"; }
verde(){ printf '\033[1;32m%s\033[0m\n' "$*"; }
verm(){ printf '\033[1;31m%s\033[0m\n' "$*"; }
info(){ printf '   %s\n' "$*"; }

SH(){ adb shell "$@" 2>/dev/null | tr -d '\r'; }

command -v adb >/dev/null || { verm "!! falta adb: pkg install android-tools -y"; exit 1; }
command -v curl >/dev/null || { verm "!! falta curl: pkg install curl -y"; exit 1; }
if ! command -v unzip >/dev/null; then
  verm ">> instalando unzip"
  pkg install -y unzip >/dev/null 2>&1 || { verm "!! rode: pkg install unzip -y"; exit 1; }
fi

if ! adb devices | awk 'NR>1 && $2=="device"' | grep -q .; then
  verm "!! TV nao conectada. Rode: adb connect IP_DA_TV:5555"
  exit 1
fi

MODELO=$(SH getprop ro.product.model)
SDK=$(SH getprop ro.build.version.sdk)
azul "TV: ${MODELO:-?} | Android API $SDK"
mkdir -p "$DIR"

# ---------------------------------------------------------------- 1. RetroArch
azul ">> 1/4 RetroArch 32 bits (176 MB, o download demora um pouco)"
APK="$DIR/retroarch.apk"
if [ -f "$APK" ] && [ "$(stat -c%s "$APK")" -gt 150000000 ]; then
  info "ja baixado antes, reaproveitando ($(du -h "$APK" | cut -f1))"
else
  curl -fL --progress-bar -o "$APK" "$APK_URL" || { verm "!! falhou o download"; exit 1; }
fi
info "$(du -h "$APK" | cut -f1) — instalando (pode levar 1-2 min)..."
adb install -r "$APK" 2>&1 | grep -E "Success|Failure|INSTALL_" | sed 's/^/   /'

# primeira abertura: cria a pasta de dados do app
azul ">> 2/4 preparando as pastas do app"
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 9
adb shell am force-stop "$PKG" >/dev/null 2>&1
UID_APP=$(SH "stat -c %u /data/data/$PKG")
info "app instalado (uid ${UID_APP:-?})"

# ---------------------------------------------------------------- 3. cores
azul ">> 3/4 instalando os emuladores (cores)"
TMPC="$DIR/cores"
mkdir -p "$TMPC"
for c in $CORES; do
  alvo="$TMPC/${c}_libretro_android.so"
  if [ -f "$alvo" ]; then info "$c (ja tinha)"; continue; fi
  curl -fsL --max-time 180 -o "$TMPC/$c.zip" "$CORES_BASE/${c}_libretro_android.so.zip" || {
    info "falhou: $c"; continue; }
  unzip -o -q "$TMPC/$c.zip" -d "$TMPC" && rm -f "$TMPC/$c.zip"
  info "$c ok"
done

# com root, poe os cores na pasta certa do app (senao o Android 7 nao deixa carregar)
adb root >/dev/null 2>&1 && sleep 2 && adb wait-for-device
if [ "$(SH id -u)" = "0" ]; then
  info "root ativo — copiando cores para dentro do app"
  adb push "$TMPC" /data/local/tmp/cores >/dev/null 2>&1
  SH "mkdir -p /data/data/$PKG/cores" >/dev/null
  SH "cp /data/local/tmp/cores/*.so /data/data/$PKG/cores/" >/dev/null
  SH "chown $UID_APP:$UID_APP /data/data/$PKG/cores/*.so" >/dev/null
  SH "chmod 644 /data/data/$PKG/cores/*.so" >/dev/null
  SH "restorecon -R /data/data/$PKG/cores" >/dev/null
  N=$(SH "ls /data/data/$PKG/cores/ | wc -l")
  info "cores instalados: ${N:-0}"
  adb unroot >/dev/null 2>&1
else
  verm "!! sem root: copie os cores pelo menu 'Carregar Core' do RetroArch"
  info "os arquivos estao em: $TMPC"
fi

# ---------------------------------------------------------------- 4. jogo livre
azul ">> 4/4 FREEDOOM — Doom completo, gratuito e de licenca livre"
DZ="$DIR/freedoom.zip"
if [ -f "$DZ" ] && [ "$(stat -c%s "$DZ")" -gt 20000000 ]; then
  info "ja baixado"
else
  curl -fL --progress-bar -o "$DZ" "$DOOM_URL" || verm "!! falhou o freedoom"
fi
if [ -f "$DZ" ]; then
  mkdir -p "$DIR/doom"
  unzip -o -q "$DZ" -d "$DIR/doom"
  WADS=$(find "$DIR/doom" -name "*.wad" | head -3)
  adb shell mkdir -p /sdcard/RetroArch/downloads >/dev/null 2>&1
  for w in $WADS; do
    adb push "$w" /sdcard/RetroArch/downloads/ >/dev/null 2>&1 && info "$(basename "$w") enviado"
  done
fi

azul ">> abrindo o RetroArch na TV"
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1

echo
verde "==============================================="
verde "  pronto"
verde "==============================================="
echo
info "Na TV, use o CONTROLE DA BOX: setas + OK navegam no menu."
info "Para jogar Doom: Carregar Conteudo > Downloads > freedoom2.wad > PrBoom"
info ""
info "Para colocar seus proprios jogos: copie as ROMs para"
info "  /sdcard/RetroArch/downloads/   (via cabo USB, ou: adb push jogo.zip /sdcard/RetroArch/downloads/)"
