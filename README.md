# odometry-nv

**Odometry** estimates where a robot is by adding up how far it has moved. A
**differential-drive** robot has two wheels on one axle, each with its own
motor and its own encoder, and steers by driving them at different speeds:
equal speeds go straight, opposite speeds spin on the spot, and any other pair
follows a circle. This package is the arithmetic of that machine in
novo-lang: encoder ticks to distance, distance to pose, and a velocity command
back to wheel speeds. It is single precision, allocates nothing and has no
effects, so it runs on a microcontroller beside the motor driver. The
reference for the conventions is ROS 2's REP 103, with `cmd_vel` a
`geometry_msgs/Twist` and the pose and twist of a `nav_msgs/Odometry`.

## What the vocabulary means

The **pose** is where the robot is: `(x, y)` in metres and a heading `theta`
in radians, counted anticlockwise from the x axis. The **twist** is how it
moves: `v`, the speed of the midpoint of the axle along its heading, and `w`,
the turn rate. Three numbers describe the machine: the **wheel radius**, the
**track width**, which is the distance between the two wheels' contact
points, and the **ticks per revolution** of an encoder.

An encoder is a counter, and a counter has a fixed number of bits. It counts
past its largest value and begins again at zero: it **wraps**. The step
between two readings is therefore taken modulo the counter's range and read as
a signed number.

The path of the robot between two samples is a **circular arc** when the two
wheels turned steadily. The midpoint moves along a chord of that arc, and the
length of the chord is `d * sin(u) / u`, where `d` is the distance the
midpoint travelled and `u` is half the change in heading. Taking the step as
`d` along the old heading is the straight-line approximation, and it is wrong
by a fraction of `u` squared over six.

| Quantity | Value |
| --- | --- |
| Number format | single precision (`fp32`) |
| Storage of an odometer | 72 bytes |
| Allocations | none |
| Effects | none |
| Encoder counters | any width up to 62 bits, or a counter that does not wrap |

## Install

```
novo pkg add odometry-nv
```

## Example

A robot with a 3.25 cm wheel radius and a track of 28.7 cm reads two 16-bit
encoders at 50 Hz while it curves to the left, then turns a `cmd_vel` command
into wheel speeds under limits.

```novo
use odometry

fn main() [io]
    // A wheel of 3.25 cm radius, 28.7 cm between the wheels, and an encoder
    // of 1440 ticks a turn.
    let machine = odometry.params(0.0325, 0.287, 1440)

    // The encoders are 16-bit counters, so the odometer is told 16 bits and
    // handles the wrap.
    var o = odometry.odometer(machine, 16)

    // The first sample only sets the baseline.
    o = odometry.update(o, 65000, 100, 0.02)

    // Fifty samples at 50 Hz of a gentle left curve: the right wheel counts
    // 30 ticks a sample, the left 25. The left counter wraps part way.
    var left = 65000
    var right = 100
    for sample in 0..50
        left = (left + 25) % 65536
        right = (right + 30) % 65536
        o = odometry.update(o, left, right, 0.02)

    println("x ${o.pose.x} y ${o.pose.y} heading ${o.pose.theta}")
    println("speed ${o.twist.v} turn rate ${o.twist.w}")

    // A velocity command, as ROS 2 sends it on `cmd_vel`: 0.8 m/s forward
    // while turning at 3 rad/s. The right wheel would need 37.9 rad/s and
    // may not exceed 30, so both wheels are scaled and the curve is kept.
    let limits = odometry.limits(0.8, 3.0, 30.0)
    let wheels = odometry.wheel_speeds(machine, odometry.twist(0.8, 3.0), limits)
    println("left ${wheels.left} right ${wheels.right} rad/s")
    let ticks = odometry.ticks_per_second(machine, wheels)
    println("left ${ticks.left} right ${ticks.right} ticks/s")
```

After a second the robot has moved 19.4 cm along a gentle curve, heading 0.124
rad to the left, at 0.195 m/s. The command asked for more turn than the right
wheel may give, so the right wheel stays at its 30 rad/s limit and the left is
scaled with it.

Build and test with `novo pkg build` and `novo test`.

## What the package contains

| Module | Contents |
| --- | --- |
| `odometry` | The types `Params`, `Pose`, `Twist`, `Wheels`, `Limits` and `Odometer`; ticks to distance and back, the counter step, the arc, the twist of a step, the sample, and the command to wheel speeds with limits. |
| `odotrig` | Single-precision `sin` and `cos`, and the wrap of an angle into `(-pi, pi]`, written without libm. |

## How to choose an entry point

**`odometry.update` for a robot.** An `Odometer` holds the machine, the pose,
the twist and the last counter readings. Each call takes the two counter
readings and the seconds since the last, and answers the new odometer.

**`odometry.advance` and `odometry.twist_of` for a caller that has its own
distances.** A robot whose wheel travel arrives in metres, from a wheel speed
sensor or a simulation, steps its pose by `advance` and reads its twist with
`twist_of`.

**`odometry.wheel_speeds` for a command.** It answers the rotation speed of
each wheel in radians per second. `ticks_per_second` converts that for a motor
controller that closes its loop on the encoder, and `twist_of_wheels` is the
inverse before any limit.

## The rules a user needs

1. **The robot faces along x at heading zero, and the left wheel is on the
   left.** A positive `w` turns the robot anticlockwise, which is a faster
   right wheel.
2. **The first sample sets the baseline and moves nothing.** There is no
   previous reading to measure from. The odometer's `started` field says
   whether the baseline is set; `with_pose` starts the pose elsewhere.
3. **Say how many bits the counters have.** `odometer(params, 16)` reads a
   16-bit counter's wrap as a small step. A counter that does not wrap, such
   as one extended in software to 32 or 64 bits, takes 0.
4. **A wheel must move less than half the counter's range between samples.**
   The step is read in `[-range/2, range/2)`, so a larger one is read as the
   other way round. At 1440 ticks per turn and 16 bits that is 22 turns of the
   wheel between samples.
5. **The twist is the average over the last interval.** `v = (dl + dr) / (2
   dt)` and `w = (dr - dl) / (track * dt)`. A `dt` of zero or less gives a
   zero twist rather than a division by it.
6. **The heading is kept in `(-pi, pi]`.** The pose does not accumulate turns;
   a program that counts laps counts the wraps of `theta` itself.
7. **A command is held to the limits in two steps.** The speed is held to
   `max_linear` and the turn rate to `max_angular`, both in either direction.
   If a wheel would then turn faster than `max_wheel`, both wheels are scaled
   by the same factor, which slows the robot and keeps the curve.
8. **Wheel speeds are in radians per second at the wheel.** A gearbox between
   the encoder and the wheel is part of `ticks_per_rev`: the number of ticks in
   one turn of the wheel, not of the motor.
9. **Slip is not modelled.** Odometry from wheels drifts, because a wheel that
   slips counts distance the robot did not move. A filter that fuses it with a
   gyroscope corrects the heading, and `kalman-nv` is the package for that.
10. **Precision limits the range.** A pose in single precision resolves a
    millimetre out to about 8 km from the origin; beyond that the steps are
    lost in rounding.

## Design

**The step is the chord and its sinc, not a sine difference.** The textbook
arc, `x + R (sin(theta + dtheta) - sin theta)` with `R = d / dtheta`, divides
by `dtheta`, which is zero on a straight line, and subtracts two nearly equal
numbers when it is small. The chord form has neither problem: its only
division is `sin(u) / u`, which is a series below `|u| = 0.25` and a plain
division above, and it agrees with the textbook arc to the last digit of the
tests' tolerance.

**The functions the embedded tier refuses are written out.** `@tier(embedded)`
refuses `math.sin` and `math.cos` because they lower to calls into libm.
`odotrig` is the Cephes single-precision routines, a reduction by quarter
turns and a polynomial, within 3e-7 of libm over `|x| <= 100`. The same two
functions are in [ahrs-nv](https://novo-lang.org/packages/ahrs-nv), and each
package carries its own so that neither depends on the other.

**There is no dependency on a filter.** The twist that `update` answers is
what [kalman-nv](https://novo-lang.org/packages/kalman-nv) takes as a
measurement, and the example in its README fuses it with a gyroscope; this
package has no knowledge of the filter, and the filter none of this one.

## Running on a microcontroller

`tests/embedded_probe.nv` samples two 16-bit counters across the wrap, drives a
straight line, a spin and an arc, turns commands into wheel speeds under
limits, and prints `PASS: odometry-embedded`. `--target=nrf52-qemu` stamps
`@tier(embedded)` on every function it compiles, so a build that links has
checked the whole package. It also runs under QEMU.

`bash tests/device_build.sh` builds it for the nRF52840-DK and the
nRF54LM20-DK and reports the sizes beside a program that does everything but
call this package. Nothing is flashed.

| Image | Flash | Of which this package | `.data` + `.bss` | Worst-case stack |
| --- | --- | --- | --- | --- |
| `nrf52840-dk` | 13,196 B | 6,312 B | 2,624 B | 40 B |
| `nrf54lm20-dk` | 14,460 B | 6,264 B | 2,624 B | 40 B |

The probe calls every public function, so the flash figure is the cost of the
whole package.

## What is not included

- **Other drive geometries.** Mecanum, omnidirectional and car-like steering
  have different kinematics; this package is the two-wheel differential drive.
- **A pose covariance.** The uncertainty of the pose, and its growth with
  distance, is what a filter carries. [kalman-nv](https://novo-lang.org/packages/kalman-nv)
  does.
- **Slip detection and wheel calibration.** The wheel radius and the track
  width are measured by driving a known path and comparing; the package takes
  the result.
- **Acceleration limits.** A limit on how fast a command may change needs the
  previous command and the time between them, and is a smoother in front of
  `wheel_speeds`.
- **A motor driver or an encoder reader.** The counts arrive as integers and
  the speeds leave as numbers.

## Related packages

- [kalman-nv](https://novo-lang.org/packages/kalman-nv) fuses this package's
  twist with a gyroscope into a pose that does not drift as the wheels slip.
- [ahrs-nv](https://novo-lang.org/packages/ahrs-nv) gives the heading from an
  IMU, which replaces the one this package integrates from the wheels.
- [pid-nv](https://novo-lang.org/packages/pid-nv) closes each wheel's loop on
  the speeds `wheel_speeds` answers.
- [ros2-nv](https://novo-lang.org/packages/ros2-nv) carries `cmd_vel` and
  `odom` between the robot and a ROS 2 graph.

## Tests

```bash
novo test                                    # 25 tests
novo test tests/odometry_vector_tests.nv     #  2: a drive across the wrap and the command table against a reference
novo test tests/odometry_edge_tests.nv       # 23: closed-form paths, the wrap, the limits, odotrig against libm
bash tests/device_build.sh                   # the device probe, sizes and a QEMU run
```

`tests/fixtures/odometry_reference.py` writes `odometry_vector_tests.nv`. The
reference is float64 and takes the arc of each step from the textbook formula,
which shares no expression with the package's chord form; the counter step is
Python's modular integer arithmetic; and the commands are clipped and scaled by
the rule the package states, written out separately. The edge tests carry
closed-form answers: a straight line is the tick count times the distance per
tick, a spin turns by `2 s / track` and does not move, and a circle of a metre
radius closes on itself after one lap. The tolerance on the drive is 1e-5,
ten times the largest difference measured.
