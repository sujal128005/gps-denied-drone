# GPS-Denied Autonomous Drone

A drone that knows where it is and holds its position in the air **without GPS**, using a stereo camera and onboard visual-inertial odometry in place of satellite positioning.

We built this to work in the environments where GPS is unreliable or unavailable — indoors, near structures, and in other confined or obstructed spaces — where a conventional drone loses its position estimate and can no longer hold station or navigate.

---

## What it does

The core capability is GPS-denied flight: the drone determines its own position from what its camera sees, feeds that estimate to the flight controller exactly where GPS data would normally go, and uses it to hold position autonomously. We have demonstrated autonomous position hold in flight using vision alone, with no GPS.

The target mission is a complete autonomous sequence — takeoff, stable position hold at 2–5 m, and landing — flown entirely on vision-based navigation.

---

## How it works

The system is a pipeline from camera to motors:

```
RealSense D435i  (stereo infrared)
        |
        v
   cuVSLAM        visual SLAM on the Jetson GPU  ->  position at ~90 Hz
        |
        v
  vio_bridge      republishes the pose for the flight controller (30 Hz)
        |
        v
    MAVROS        ROS 2 <-> MAVLink bridge
        |
        v
  ArduPilot EKF3  fuses vision as the position source, in place of GPS
        |
        v
     motors
```

A stereo camera observes the environment and NVIDIA's cuVSLAM computes the drone's motion from the image stream, producing a metric-scale position estimate about ninety times a second. A small bridge node we wrote republishes this pose in the format the flight controller expects, MAVROS carries it over MAVLink, and ArduPilot's EKF3 estimator fuses it as an external navigation source — the same slot GPS would occupy. The flight controller then holds position on the vision estimate.

Altitude is taken from the barometer rather than vision, by design, so that a vision error affects only horizontal position and never height.

---

## Hardware

| Component | Part |
|---|---|
| Companion computer | NVIDIA Jetson Orin Nano Developer Kit |
| Operating system | JetPack 6.2 (Ubuntu 22.04), ROS 2 Humble |
| Camera | Intel RealSense D435i (stereo IR + depth + IMU) |
| Flight controller | Cube Orange Plus |
| Autopilot firmware | ArduCopter 4.6.3 |
| Motors | T-Motor Antigravity MN4006 KV380 (x4) |
| Propellers | T-Motor 15x5 carbon fibre |
| Battery | 6S 5200 mAh LiPo |
| Vision software | NVIDIA Isaac ROS (cuVSLAM) |
| Companion link | USB->UART to Cube TELEM2, 921600 baud, MAVLink 2 |

The camera is mounted with a downward tilt so it views the textured ground, which provides reliable visual features for tracking.

---

## Repository layout

```
config/      flight-controller parameters and system configuration snapshots
scripts/     startup, health-check, monitoring and shutdown tooling
vio_bridge/  the ROS 2 bridge node (cuVSLAM odometry -> MAVROS vision pose)
notes/       engineering log of the build, decisions, and debugging
```

---

## Status

The vision-navigation pipeline is built and flight-proven. cuVSLAM runs at ~90 Hz and has tracked reliably through real flight, the vision estimate is fused by the flight controller as its position source, and the drone has held position autonomously in the air using vision alone.

Current work is focused on extending the autonomous hold, tuning the position-hold response, and building toward the full takeoff-hold-land sequence. The engineering log in `notes/` records the build and the problems solved along the way in detail.

---

## Key engineering work

A few of the more substantial problems we worked through, documented fully in the engineering log:

- **Scale calibration.** An early configuration reported motion at roughly one hundred times its true magnitude. We isolated the cause by ruling out each possibility with direct measurement — IMU scale, frame rate, stereo baseline, and tracking state were each verified correct — and traced it to the inertial fusion stage. Running in vision-only stereo mode, where the known lens separation provides correct metric scale, resolved it.

- **Vision-as-GPS integration.** Configuring the EKF3 estimator to accept the external vision pose in place of GPS, and verifying end to end that the fused position moved correctly in response to real motion.

- **Thrust analysis.** Reading the flight logs to diagnose a thrust limitation — motor outputs were saturating at hover — and correcting it by matching the manufacturer-recommended propellers to the motors.

---

## Team

Sujal Negi and Made Navya, with contributions from Navya Sree (perception) and Sana (planning and control).

---

## Notes on references

The project concept — GPS-denied flight using a companion computer and visual odometry — is a well-established approach in the drone community, and we drew initial inspiration from existing work in this space. Our implementation is our own: it targets ArduPilot with Mission Planner, and every flight-controller parameter and configuration decision is derived from the official ArduPilot documentation and validated on our own hardware.
