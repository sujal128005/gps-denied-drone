# Engineering Log

A dated record of building the GPS-denied drone: what we did, why we made the
decisions we made, and how we worked through the problems that came up. Written as
we went. Most recent entries are at the bottom.

---

## Timeline overview

| Date | Focus |
|---|---|
| Early July 2026 | Platform foundation — storage, Docker, Isaac ROS container |
| 2026-07-03 | Container persistence and serial-port access |
| Early July 2026 | Camera configuration for visual odometry |
| Mid July 2026 | cuVSLAM running; MAVROS link; the bridge node |
| Mid July 2026 | EKF3 fusing vision as GPS ("using external nav data") |
| Mid July 2026 | The scale problem — diagnosed and resolved |
| Mid July 2026 | Validation, sign/axis checks, first flights |
| 2026-07-08 | Flight 2 — autonomous position hold demonstrated |
| Mid July 2026 | Thrust analysis from flight logs; propeller change |
| 2026-07-15 | Infrastructure hardening; propeller validation flight |
| 2026-07-16 | Three flights; VIO accuracy investigation |

---

## Early July — Platform foundation

We started with a bare Jetson Orin Nano and built up the software platform everything
else depends on.

Storage was the first decision. The Jetson's internal storage is limited and the vision
software and workspace are large, so we run everything from a 1 TB external SSD mounted
at a fixed path by UUID, with Docker configured to keep its data there. We added a systemd
rule so Docker waits for the drive to be mounted before it starts, which avoids a race on
boot.

The vision stack (NVIDIA Isaac ROS, including cuVSLAM) runs in a Docker container. Getting
the container to have full GPU access took work — GPU devices are exposed through a CDI
specification that has to be regenerated after a reboot, or container creation fails.

## 2026-07-03 — Container persistence and serial access

We hit a recurring frustration: anything installed inside the container was lost whenever
the container was recreated by Isaac ROS's `run_dev.sh`. We solved it by baking our
dependencies (MAVROS and its message packages, the visual SLAM package, and supporting
libraries) into a custom image layer, so they are part of the image and survive every
restart.

A subtler problem sat underneath. The serial port to the flight controller needs group
permissions, but Isaac's runtime entrypoint re-creates the container user and strips any
extra groups we added — so baking the group in did not work. The fix was a host-side udev
rule that assigns the serial device to a group the container user is always in, so serial
access works in every fresh container automatically.

## Early July — Camera configuration

cuVSLAM is only as good as the images it receives, so configuring the RealSense correctly
for visual odometry mattered. We use the stereo infrared pair, because the known distance
between the two lenses is what gives the motion estimate a real-world scale in metres. We
turned the infrared projector off — counter-intuitive, since it exists to help depth
sensing, but for visual odometry the projected dots are fixed to the camera and appear
stationary as it moves, which corrupts feature tracking. With the projector off, the camera
tracks the real textured world. We run the IR pair at 640x360 at 90 Hz to keep the motion
between frames small, with the IMU at 200 Hz. On the bench this gives clean, matched
~90 Hz stereo and ~200 Hz IMU.

One recurring issue: only one process can own the camera at a time, so a stale process from
a previous run blocks a new launch. Clearing old processes, and replugging the camera when
needed, became a standard pre-launch step.

## Mid July — Vision to flight controller

The Jetson runs ROS 2 and the flight controller speaks MAVLink, so MAVROS bridges the two.
The companion computer connects to the Cube's TELEM2 serial port at 921600 baud.

cuVSLAM and the flight controller use different message formats, so we wrote a small bridge
node that subscribes to cuVSLAM's odometry and republishes the pose in the format MAVROS
expects for external navigation, rate-limited to 30 Hz. We looked carefully at coordinate
conventions here, because a sign or axis error would make the drone correct in the wrong
direction. cuVSLAM's output already matches the convention MAVROS expects on its vision
input, so the bridge copies the pose across without remapping, and we verified the direction
empirically later. One detail that caught us out more than once: cuVSLAM publishes with
best-effort reliability, and a subscriber that does not match that setting receives nothing
at all, silently.

With the bridge running and the parameters set, the flight controller reported that it was
using external navigation data — the point at which the vision system genuinely takes the
place of GPS.

## Mid July — The scale problem

This was the hardest problem of the project, and worth recording in full because the method
mattered as much as the fix.

With the full visual-inertial pipeline running, moving the camera a known distance produced
a wildly wrong reading — a slide of half a metre registered as about fifty metres, roughly
a hundred times too large. A drone acting on that would believe it had shot fifty metres
sideways and would command a violent correction, so nothing could fly until we understood it.

Rather than guess, we ruled out each possible cause with a direct measurement. The IMU scale
was correct — the accelerometer read gravity accurately at rest, and the way the reading
split across axes even confirmed the camera's mounting angle. The frame rate was clean. The
stereo baseline was correct — we computed it from the camera's own calibration and got
exactly the expected 50 mm. Tracking was healthy and stable when still. With each of these
eliminated, the remaining difference was the inertial fusion stage. We confirmed it by
running in vision-only stereo mode, where the same half-metre slide read as exactly half a
metre. The stereo pair alone provides correct metric scale, so vision-only operation is a
legitimate configuration, and it is what the drone flies on.

The underlying inertial-fusion issue is not yet solved and remains future work; the likely
cause is a mismatch between the camera's mounting angle and the frame convention the fusion
assumes. But the platform is correctly scaled and flyable as it stands.

## Mid July — Validation and first flights

Before flying we verified the whole chain was directionally correct: moving the camera
forward, sideways, and up, and confirming the flight controller's fused position moved the
correct way by the correct amount. We calibrated the radio, set the camera's measured offset
from the flight controller as parameters, and confirmed motor order and direction.

The first flight was flown manually in altitude-hold with the vision system running but not
controlling the aircraft. The purpose was to answer the one question the bench never could:
does the vision tracking survive real flight vibration? It did — the drone hovered stably and
cuVSLAM tracked cleanly throughout, with no errors.

## 2026-07-08 — Flight 2: autonomous position hold

The second flight was the core goal. We took off manually, then switched to a mode where the
vision system actively controls position, and the drone held its position autonomously using
vision alone, with no GPS. That flight also logged a thrust warning that limited how long the
hold could be sustained, which led directly to the next piece of work.

## Mid July — Thrust analysis and propeller change

We pulled the flight log to understand the thrust warning rather than guess at it. The
vibration was fine, which ruled that out. The motor outputs told the story: they were
saturating near maximum just to hover, leaving essentially no margin to hold position or
recover from a disturbance — exactly what the warning reports.

The cause was the propellers. Our motors are low-speed, high-efficiency motors designed to
swing large propellers, and the ones fitted were smaller than the manufacturer recommends.
An undersized propeller forces this kind of motor to spin near its limit to produce enough
lift. We ordered the recommended larger propellers to correct it.

## 2026-07-15 — Infrastructure hardening and propeller validation

Two threads this day. First, we made the platform more robust for field work: a permanent
fix for the clock (which reset on every power-up because the real-time clock has no backup
battery, causing secure downloads to fail with a 1970 date), a self-healing mount for the
external SSD after it dropped to read-only under an unclean shutdown, and a single-command
startup that brings up the whole pipeline in one place along with a health check and a clean
shutdown.

Second, we fitted the new propellers and validated them. The flight log confirmed the fix —
the hover throttle dropped substantially from near-saturation to a comfortable level, the
thrust warning was gone, and the aircraft flew with real margin. An earlier attempt that day
ended in a hard set-down traced to a calibration issue, which we corrected before flying
again.

## 2026-07-16 — Three flights and VIO accuracy

Flew three times, mostly at low altitude, building manual confidence on the more powerful
propellers. cuVSLAM tracked cleanly across all three flights, including a larger excursion
where it followed the drone out and settled back coherently. The last flight ended in a tip
on landing that lightly damaged two propellers — a landing-technique issue, since the larger
propellers produce much stronger ground effect and the aircraft floats more in the final
half-metre.

We also began a proper investigation into the accuracy of the vision position and the
camera-to-target distance, setting up a controlled bench test (measured one-metre moves in
each axis) to quantify any error against ground truth rather than judging it by eye in flight.

---

## Standing operational notes

Things we learned the hard way and now treat as standard practice:

- The Jetson clock resets to 1970 on power-up; fixed with network time sync plus a fallback
  that restores a valid time on boot. A hardware clock battery is the permanent fix.
- After a reboot, the GPU device specification must be regenerated before the container starts.
- MAVROS runs at high CPU, which can make interactive commands time out even though the link
  is healthy; the publish rate is the reliable check, not an interactive read.
- The external SSD can drop to read-only under an unclean shutdown, which stops Docker. We
  hardened the mount to self-repair on boot, but a soldered internal drive is the real fix
  before trusting the aircraft to fly unattended.
- A stable vision reading is not necessarily a correct one — the tracker can report a steady
  but completely wrong value when it has diverged, so our pre-flight check requires the
  reading to be both stable and near zero when the drone is still.

We run a health check before every flight — vision stable and at full rate, the pose reaching
the flight controller, the link connected, and external navigation being used — and only fly
once all of it passes.

---

## Where the project stands

The vision-navigation system is built and flight-proven, autonomous position hold has been
demonstrated in the air, and the thrust limitation has been diagnosed and corrected. The
remaining work is to extend and steady the autonomous hold, tune the position-hold response,
move to an internal SSD, verify vision accuracy against ground truth, and build up to the
full takeoff-hold-land sequence and the reliability testing that makes it dependable rather
than merely demonstrated.

## 2026-07-17 — VIO accuracy investigation (bench)

Set out to measure whether the vision position and camera-to-target distance are
accurate. Worked solo today.

Ran a controlled VIO test: placed marked points and hand-carried the drone through a
known path (1 m forward, 1 m left, 1.27 m right to x', 0.29 m to a fourth point, and a
1 m vertical move up a wall), capturing the reported position at each stop with a small
press-to-capture tool.

The results showed cuVSLAM losing its lock: the first 1 m move already read about 2.5 m,
and by the end of the path the estimate had diverged to impossible values (around -6 to
-10 m in a test area only 1-2 m across). The conclusion is that hand-carrying the drone
is not a valid way to measure VIO accuracy - moving it by hand introduces rotation, jerk,
and blank-wall views that break feature tracking. This is consistent with the fact that
in actual flight the tracking is smooth and returns cleanly to its origin. So the flight
data remains the better evidence of accuracy, and it has looked good.

Takeaway for the future: to test VIO accuracy on the bench, the camera must move very
slowly in a straight line, stay perfectly level, and always see texture - ideally mounted
on something that slides rather than carried. Hand-tests will always look broken even when
the system is fine.

The target-distance (depth) test is still pending: it needs the actual green-and-black
cross marker the detector was trained on, which was not available today.

Also cleaned up the repository - rewrote the README and this engineering log for clarity
and added a build timeline.
