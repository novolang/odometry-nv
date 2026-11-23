# Changelog

All notable changes to odometry-nv are recorded here. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
package follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
with the pre-1.0 rule that a breaking change bumps the MINOR number.

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
