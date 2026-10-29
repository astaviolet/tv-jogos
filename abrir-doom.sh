#!/usr/bin/env bash
# =============================================================================
# abrir-doom.sh — abre o Freedoom direto no RetroArch, sem tocar no menu
#
#   curl -fL -o abrir.sh https://raw.githubusercontent.com/astaviolet/tv-jogos/main/abrir-doom.sh && bash abrir.sh
#
# Faz tudo: garante o jogo, garante o core, e manda a TV abrir.
# =============================================================================
set -uo pipefail

PKG="com.retroarch.ra32"
WAD_URL="https://github.com/freedoom/freedoom/releases/download/v0.13.0/freedoom-0.13.0.zip"
CORE_URL="https://buildbot.libretro.com/nightly/android/latest/armeabi-v7a/prboom_libretro_android.so.zip"
DIR="$HOME/doom"
IP="${1:-192.168.0.103}"

azul(){ printf '\033[1;36m%s\033[0m\n' "$*"; }
verde(){ printf '\033[1;32m%s\033[0m\n' "$*"; }
verm(){ printf '\033[1;31m%s\033[0m\n' "$*"; }
info(){ printf '   %s\n' "$*"; }
SH(){ adb shell "$@" 2>/dev/null | tr -d '\r'; }

command -v adb >/dev/null || { verm "!! pkg install android-tools -y"; exit 1; }
command -v curl >/dev/null || { verm "!! pkg install curl -y"; exit 1; }
command -v unzip >/dev/null || pkg install -y unzip >/dev/null 2>&1

# ------------------------------------------------------------------ conexao
if ! adb devices | awk 'NR>1 && $2=="device"' | grep -q .; then
  azul ">> conectando na TV ($IP)"
  adb connect "$IP:5555" >/dev/null 2>&1
  sleep 2
fi
if ! adb devices | awk 'NR>1 && $2=="device"' | grep -q .; then
  verm "!! TV nao respondeu. Rode antes: adb connect ${IP}:5555"; exit 1
fi

if ! SH "pm path $PKG" | grep -q package:; then
  verm "!! RetroArch nao esta instalado na TV."; exit 1
fi
info "TV conectada, RetroArch instalado"

# ------------------------------------------------------------------ arquivos
mkdir -p "$DIR"; cd "$DIR" || exit 1

if [ ! -f freedoom2.wad ]; then
  azul ">> baixando o Freedoom (23 MB)"
  curl -fL --progress-bar -o fd.zip "$WAD_URL" || { verm "!! falhou"; exit 1; }
  unzip -oq fd.zip
  rm -f fd.zip
  # os .wad vem dentro de uma subpasta: traz eles pra raiz
  find . -name "freedoom*.wad" -exec mv -f {} . \; 2>/dev/null
  rm -rf freedoom-0.13.0
fi
if [ ! -f freedoom2.wad ]; then
  verm "!! os WADs nao foram encontrados"; exit 1
fi
info "jogo: $(ls -1 *.wad 2>/dev/null | tr '\n' ' ')"

if [ ! -f prboom_libretro_android.so ]; then
  azul ">> baixando o core PrBoom"
  curl -fsL -o pr.zip "$CORE_URL" || { verm "!! falhou"; exit 1; }
  unzip -oq pr.zip && rm -f pr.zip
fi
info "core: $(du -h prboom_libretro_android.so | cut -f1)"

# ------------------------------------------------------------------ root
azul ">> pedindo root no adb"
adb root >/dev/null 2>&1; sleep 3; adb wait-for-device
if [ "$(SH id -u)" = "0" ]; then
  ROOT=1; info "root ativo"
else
  ROOT=0; verm "!! adb root recusou, vou tentar sem root"
fi

UID_APP=$(SH "stat -c %u /data/data/$PKG" | head -1)
[ -n "${UID_APP:-}" ] || UID_APP=10000

# ------------------------------------------------------------------ copiar
azul ">> copiando jogo e core para a TV"
SH "mkdir -p /sdcard/RetroArch/downloads"
adb push freedoom1.wad /sdcard/RetroArch/downloads/ >/dev/null 2>&1
adb push freedoom2.wad /sdcard/RetroArch/downloads/ >/dev/null 2>&1
info "WADs em /sdcard/RetroArch/downloads/"

CORES='/data/data/com.retroarch.ra32/cores'
if [ "$ROOT" = "1" ]; then
  adb push prboom_libretro_android.so /data/local/tmp/ >/dev/null 2>&1
  SH "mkdir -p $CORES"
  SH "cp /data/local/tmp/prboom_libretro_android.so $CORES/"
  SH "chown $UID_APP:$UID_APP $CORES/prboom_libretro_android.so"
  SH "chmod 644 $CORES/prboom_libretro_android.so"
  SH "restorecon -R $CORES"
  if SH "ls $CORES/prboom_libretro_android.so" | grep -q prboom; then
    info "core instalado no app"
  else
    verm "!! nao consegui copiar o core"
  fi
else
  SH "mkdir -p /sdcard/RetroArch/cores"
  adb push prboom_libretro_android.so /sdcard/RetroArch/cores/ >/dev/null 2>&1
  CORES='/sdcard/RetroArch/cores'
  info "core em $CORES"
fi

# ------------------------------------------------------------------ abrir
azul ">> abrindo o jogo na TV"
adb shell am force-stop "$PKG" >/dev/null 2>&1
sleep 1
adb shell am start \
  -n "$PKG/com.retroarch.browser.retroactivity.RetroActivityFuture" \
  --es ROM "/sdcard/RetroArch/downloads/freedoom2.wad" \
  --es LIBRETRO "$CORES/prboom_libretro_android.so" \
  --es SDCARD /storage/emulated/0 2>&1 | grep -E "Starting|Error|Warning" | sed 's/^/   /'

echo
verde "se a TV abriu o Doom, pronto."
info "para trocar de fase: o jogo abre direto no menu do Doom, aperte 23 (OK) pelo adb"
info "para sair: adb shell am force-stop $PKG"
