# Changelog

All notable changes to odometry-nv are recorded here. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
package follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
with the pre-1.0 rule that a breaking change bumps the MINOR number.

## 0.2.0 — 2026-11-24

### Breaking

- **`odotrig.sin` and `odotrig.cos` move to the package
  [fpmath-nv](https://novo-lang.org/packages/fpmath-nv)** as `fpmath.sin`
  and `fpmath.cos`; this package depends on it.  `odotrig.wrap_pi` stays.
  *Migration:* a program that called `odotrig.sin(x)` or `odotrig.cos(x)`
  adds `fpmath-nv = "^0.1.0"` to its `[dependencies]` and calls
  `fpmath.sin(x)` and `fpmath.cos(x)`.
- The tests of the accuracy of the sine and the cosine move with them, to
  `fpmath-nv/tests/fpmath_tests.nv`.

### Changed

- The probe `tests/embedded_probe.nv` is the same program; its image is the
  size it was or smaller.  Built as the main of a program that depends on the
  package, it is 56 bytes smaller on `nrf52840-dk` (12,164 bytes before, 12,108
  after) and on `nrf52-qemu` (12,884 and 12,828).  `tests/device_build.sh`
  stages the modules as the `src/` of its own scratch package and reads 96
  bytes more (12,044 and 12,140): the trap sites of the sine and the cosine
  name the file of the dependency, whose path is longer than `./src/fpmath.nv`.

## 0.1.0 — 2026-11-23

### Added

- **`odometry`** — differential-drive kinematics in single precision:
  `Params`, `Pose`, `Twist`, `Wheels`, `Limits` and `Odometer`; encoder ticks
  to distance and back; the counter step across a wrap; the pose advanced
  along the exact circular arc; the twist of a step; the odometer's sample;
  and the velocity command to wheel speeds, held to a linear, an angular and
  a wheel limit with the curve kept when the wheels are scaled.
- **`odotrig`** — single-precision `sin` and `cos`, and the wrap of an angle
  into `(-pi, pi]`, for a device whose tier refuses libm.
- **`tests/embedded_probe.nv`** and **`tests/device_build.sh`** — the device
  claim as a program, built for the nRF52840-DK, the nRF54LM20-DK and the
  emulated board, with the image sizes beside a baseline and a QEMU run.
- **`tests/fixtures/odometry_reference.py`** — the float64 reference that
  writes `tests/odometry_vector_tests.nv`.

### Known

- Counter widths above 62 bits are not supported by `odometer`, whose range
  is `1 << bits`.
