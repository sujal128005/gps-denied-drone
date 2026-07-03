# GPS-Denied Autonomous Drone

Autonomous multirotor performing takeoff -> stable position hold -> landing
using Visual-Inertial Odometry (VIO) instead of GPS.

Status: Foundation complete — base platform and Isaac ROS container operational.

## Operating scope
- Environment: Outdoors, open area (primary). Indoor use also intended.
- Navigation: GPS-denied by design — position from VIO (vision + IMU), no GPS fusion.
- Conditions: Evening, no direct sun, good ambient light (avoids IR washout).
- Primary task: Takeoff, hold at 2-5 m, land — reliably.

## Hardware
- Companion: NVIDIA Jetson Orin Nano Dev Kit (hostname nexara9)
- Camera: Intel RealSense D435i (stereo + IMU)
- Flight controller: Cube Orange, ArduPilot Copter 4.6.3
- Ground station: Mission Planner
- Link: USB->UART, Jetson USB -> Cube Orange TELEM2
- Working storage: Samsung T7 1TB USB SSD (ext4 at /mnt/t7ssd)
- Boot: 128 GB microSD; Power: battery -> buck converter -> Jetson

### Camera mounting (design decision, not final)
- Target: ~40 deg below horizontal (down-and-forward), ~20 cm height, no roll.
- Rationale: best robustness for 2-5 m open-field evening VIO.
- To be validated by on-site cuVSLAM feature-tracking test. Forward-facing retired.

## Software stack (verified)
- JetPack 6.2 (L4T R36.4.3), Ubuntu 22.04.5 (jammy)
- ROS 2 Humble; Isaac ROS release-3.2 (isaac_ros_common)
- Container image key: ros2_humble.realsense
- Docker 27.5.0 (data-root on T7); NVIDIA Container Toolkit 1.16.2 (manual CDI spec)
- CUDA 12.6 (in container); librealsense 2.55.1; realsense2_camera pkgs installed
- VIO engine: Isaac ROS Visual SLAM (cuVSLAM)

## Reference
Adapted (not copied) from hackster.io/bandofpv GPS-denied drone project.
That project uses PX4 + QGroundControl; this one uses ArduPilot + Mission Planner,
so all flight-controller config is derived from official ArduPilot docs.

## Layout
config/ launch+YAML, ardupilot/ params, docs/ matrix+diagrams, notes/ engineering log.
Isaac ROS workspace and build artifacts live on the T7 and are NOT committed here.
