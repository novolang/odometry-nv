#!/usr/bin/env bash
# tests/device_build.sh — builds the device probe, tests/embedded_probe.nv,
# for the two Nordic boards the toolchain supports and for the emulated
# one, and reports the image sizes beside the size of a program that
# does everything the probe does except call this package.
#
# The probe is a firmware `main`, so it is built as the `main` of a
# scratch package that holds this package's modules in `src/`, which is
# how the shard audit builds it too.  Nothing is flashed.  The emulated
# board's image (nrf52-qemu) is then run under QEMU and its first line
# must be PASS.
#
# Run from anywhere:  bash tests/device_build.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$HERE/.." && pwd)"
NAME="$(basename "$PKG")"
NOVO="${NOVO:-$HOME/.novo/bin/novo}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/$NAME-dev.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

stage() {  # stage <dir> <main file>
  mkdir -p "$1/src"
  cp "$PKG"/src/*.nv "$1/src/"
  cp "$2" "$1/src/probe.nv"
  printf '[package]\nname = "embprobe"\nversion = "0.1.0"\nmain = "src/probe.nv"\n\n[dependencies]\n' > "$1/novo.toml"
}

# The baseline: the same board start-up, one UART write and the same
# idle loop, with no call into the package.
cat > "$WORK/baseline.nv" <<'NV'
@tier(rt)
fn main() [hw, time]
    bsp.board.init()
    hal.uart.write("PASS: baseline\n")
    loop
        core.rt.sleep_ms(1000)
NV

stage "$WORK/probe" "$PKG/tests/embedded_probe.nv"
mkdir -p "$WORK/base/src"
cp "$WORK/baseline.nv" "$WORK/base/src/probe.nv"
printf '[package]\nname = "embbase"\nversion = "0.1.0"\nmain = "src/probe.nv"\n\n[dependencies]\n' > "$WORK/base/novo.toml"

size_of() {  # size_of <dir> <target> -> "flash <n> B; RAM <n> B"
  local dir="$1" target="$2"
  rm -f "$dir/probe.elf"
  ( cd "$dir" && NOVO_LEAK_CHECK=0 timeout 900 "$NOVO" build --target="$target" src/probe.nv ) > "$dir/$target.log" 2>&1
  if [ -f "$dir/probe.elf" ]; then
    local flash ram stack
    flash=$(grep -m1 '^  flash ' "$dir/$target.log" | sed -E 's/^  flash *([0-9,]+) B.*/\1/')
    ram=$(grep -m1 '\.data + \.bss' "$dir/$target.log" | sed -E 's/^ *\.data \+ \.bss *([0-9,]+) B.*/\1/')
    stack=$(grep -m1 'stack, worst case' "$dir/$target.log" | sed -E 's/^ *stack, worst case *([0-9,]+) B.*/\1/')
    echo "$flash $ram ${stack:-0}"
    cp "$dir/probe.elf" "$dir/$target.elf"
  else
    echo "FAIL FAIL"
    grep -vE '^novo:' "$dir/$target.log" | head -20 | sed 's/^/      /' >&2
  fi
}

fail=0
echo "  image sizes (flash B / .data + .bss B), package probe against baseline:"
for target in nrf52840-dk nrf54lm20-dk nrf52-qemu; do
  read -r pf pr ps <<< "$(size_of "$WORK/probe" "$target")"
  read -r bf br bs <<< "$(size_of "$WORK/base" "$target")"
  if [ "$pf" = "FAIL" ] || [ "$bf" = "FAIL" ]; then
    echo "  ✗ --target=$target does not build"
    fail=1
  else
    delta=$(( ${pf//,/} - ${bf//,/} ))
    echo "  ✓ --target=$target: probe flash $pf B, RAM $pr B, worst-case stack $ps B; baseline flash $bf B, RAM $br B, stack $bs B; the package adds $delta B of flash"
  fi
done

if ! command -v qemu-system-arm >/dev/null 2>&1; then
  echo "  - the image is not run: qemu-system-arm is not installed"
elif [ -f "$WORK/probe/nrf52-qemu.elf" ]; then
  out=$(timeout 12 qemu-system-arm -machine mps2-an386 -nographic -semihosting \
          -kernel "$WORK/probe/nrf52-qemu.elf" 2>&1 | head -5)
  if echo "$out" | head -1 | grep -q '^PASS'; then
    echo "  ✓ the emulated image answers: $(echo "$out" | head -1)"
  else
    echo "  ✗ the emulated image answers: $(echo "$out" | head -1)"
    fail=1
  fi
fi
exit $fail
