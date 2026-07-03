# Engineering Log

Dated record of work, decisions, and rationale. Newest entries at the bottom.

---

## 2026-07-03 — Foundation: storage, Docker, Isaac ROS container

### Storage (T7 SSD)
- Confirmed no NVMe on carrier board; Samsung T7 (USB) is the only external storage.
- Wiped T7, created GPT + single ext4 partition, label t7ssd,
  UUID 2363d201-6ef9-4e64-ba8d-afbafc811355.
- Mounted at /mnt/t7ssd via /etc/fstab using UUID with nofail +
  x-systemd.device-timeout=10 so a missing/disconnected drive never blocks boot.
- User-owned; verified writable. Rebooted to confirm auto-mount holds.
- Known risk: USB-attached storage on a vibrating airframe. Acceptable for
  bench/tethered bring-up. Sourcing an NVMe SSD recommended before untethered flight.

### Docker
- JetPack shipped Docker CE 27.5.0 + NVIDIA Container Toolkit 1.16.2. Did not reinstall.
- Added user to docker group.
- Relocated Docker data-root to /mnt/t7ssd/docker via daemon.json
  (merged with existing nvidia runtimes block).
- Added systemd drop-in wait-for-t7.conf (RequiresMountsFor=/mnt/t7ssd)
  so Docker never starts before the T7 is mounted.
- Verified post-reboot: data-root on T7, docker usable without sudo.

### Isaac ROS
- Workspace on T7: /mnt/t7ssd/workspaces/isaac_ros-dev/; ISAAC_ROS_WS in .bashrc.
- Cloned isaac_ros_common at branch release-3.2 (verified compatible with
  JetPack 6.2; requires Docker >= 27.2.0).
- Config CONFIG_IMAGE_KEY=ros2_humble.realsense.
- Installed git-lfs (was missing; run_dev.sh requires it, set -e caused
  a silent early exit until fixed).
- First container build pulled NVIDIA base + compiled realsense layer (~59 min).
  Image isaac_ros_dev-aarch64 cached.

### CDI / GPU-in-container fix
- Launch failed: unresolvable CDI devices nvidia.com/gpu=all.
- Cause: Toolkit 1.16.2 does not auto-generate CDI spec (auto from v1.18.0).
- Fix: sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml.
- nvidia-ctk cdi list now shows nvidia.com/gpu=all. Container launches cleanly.
- Note: CDI spec is static on this toolkit; regenerate after JetPack/driver upgrade.

### Verified inside the container
- ROS 2 Humble, CUDA 12.6, OpenCV 4.5.4, GPU device nodes present.
- librealsense 2.55.1; realsense2_camera packages installed and discoverable.

### Scope clarification
- Refined to outdoor-primary, GPS-denied, evening, no direct sun,
  good ambient light, hover 2-5 m, open area.
- Implication: pure VIO (no GPS fusion). Simpler EKF3 source config.

### Open decisions
- Camera orientation: target ~40 deg below horizontal at ~20 cm;
  to be validated on-site with cuVSLAM feature-tracking. Mount easy to change.
- Storage: NVMe SSD recommended before untethered flight.

---

## 2026-07-03 (later) — RealSense camera bring-up (VIO-verified)

### USB / permissions
- D435i enumerated at 5000 Mbps (USB3.0) on host — full bandwidth, no USB2 trap.
- Container could not open camera: RS2_USB_STATUS_ACCESS (failed to set power state).
- Cause: no RealSense udev rules on the HOST (container reuses host USB perms).
  The Isaac image's own rules reference a container-only script and are not for the host.
- Fix: installed official IntelRealSense/librealsense 99-realsense-libusb.rules to
  /etc/udev/rules.d/ (grants plugdev/0666); udevadm reload + trigger.
- Camera node then went from crw-rw-r-- root:root to crw-rw-rw- root:plugdev. Access OK.

### Firmware / SDK compatibility (verified vs Intel docs)
- FW 5.13.0.50 (production-designated). librealsense 2.55.1 needs >= 5.11.6.250 -> compatible.
- FW < 5.16 uses static gyro sensitivity (stable path); no action needed.
- Serial: 344522070088.

### Camera config for VIO (from NVIDIA official VSLAM realsense launch)
- IR stereo pair (infra1/infra2), color+depth OFF, EMITTER OFF (dots corrupt tracking),
  profile 640x360x90, IMU united (method 2) at gyro/accel 200 Hz.
- First tried color+depth+IMU: color at 720p saturated USB -> control_transfer
  warning flood, color dropping to ~22 Hz. Depth/IMU stayed healthy.
- Switched to the VIO config: warnings stopped, all rates stable.

### Measured rates (VIO config) — healthy
- infra1 ~89.9 Hz, infra2 ~89.9 Hz (matched), imu ~199.6 Hz, all low std dev.

### Notes
- IMU factory calibration absent (defaults used). Consider rs-imu-calibration later.
- See config/realsense/vio-camera-params.md for the full verified parameter set.

### Next
- Bring up Isaac ROS Visual SLAM (cuVSLAM) with the combined realsense launch.
- Set up TF frames; run on-site feature-tracking test to finalize camera angle (~40 deg).

---

## 2026-07-03 (evening) — cuVSLAM VIO pipeline working (bench)

- Installed ros-humble-isaac-ros-visual-slam via apt (Isaac repo in container).
- Launched isaac_ros_visual_slam_realsense.launch.py (camera + cuVSLAM together).
- cuVSLAM tracker initialized OK (use_gpu: true, IMU fusion: true, ~6s GPU/TRT setup).
- /visual_slam/tracking/odometry publishing steady at ~89.8 Hz.
- Confirmed tracking responds to motion: position values change when camera moved,
  return near start when returned. VIO is real.
- GPU acceleration working inside container (CDI fix confirmed in practice).

Proven: camera -> cuVSLAM -> odometry pipeline, GPU, IMU fusion, motion tracking.
Not yet proven: tracking quality in real open-field evening conditions (on-site test, 40 deg).

### Next
- MAVROS bridge: Jetson <-> Cube Orange over USB->UART (CP210x).
- Then: time sync, then EKF3 vision fusion.
- In parallel (field): re-mount camera 40 deg, run cuVSLAM feature-tracking test.

---

## 2026-07-03 (night) — MAVROS bridge to Cube Orange (stable)

### Serial link
- Cube Orange Plus, ArduCopter 4.6.3. TELEM2 = SERIAL2: PROTOCOL=2 (MAVLink2), BAUD=921 (921600).
- Jetson sees adapter as /dev/ttyUSB0 (CP210x). Added user to dialout (host + container admin).

### Install
- installed ros-humble-mavros + -extras + -msgs (v2.14.0) via apt.
- Needed ros-humble-diagnostic-updater (missing lib; MAVROS died with libdiagnostic_updater.so not found until installed).
- geographiclib egm96-5 geoid already present.
- Launch: ros2 launch mavros apm.launch fcu_url:=/dev/ttyUSB0:921600 (apm = ArduPilot, NOT px4).

### Key debug: dual-GCS conflict (NOT baud/wiring)
- Initial symptom: /mavros/state connected flapping true/false; garbage "remote address" flood;
  param download never completed (1000+ params missing), unsolicited param values.
- Root cause: Mission Planner (Cube USB) AND MAVROS (TELEM2) both connected + polling at once.
- Fix: disconnect Mission Planner. Then MAVROS alone = rock solid:
  connected true steady, "PR: parameters list received", full FCU info.
- BAUD 921600 IS FINE. Lesson: do not run MP (USB) + MAVROS (TELEM2) both polling FCU at once.
  Later route MP through MAVROS gcs_url for a single clean pipeline.

### Verified
- /mavros/state: connected=true, armed=false, mode=STABILIZE, system_status=3 (STANDBY).
- FCU: ArduCopter V4.6.3, CubeOrangePlus, Frame QUAD/X, 3 IMUs.
- Pre-arm (via MAVROS): "RC not found" (expected, no TX) and "VisOdom: not healthy"
  -> Cube ALREADY expects vision odometry (EKF3 vision source partly set). Good sign.

### Next
- Connect cuVSLAM odometry -> MAVROS /mavros/vision_pose/pose -> EKF3.
- Verify EKF3 vision params (EK3_SRCn, VISO_*) per official ArduPilot docs.
- Time sync (chrony + MAVLink TIMESYNC); verify VisOdom healthy.

---

## 2026-07-03 (late night) — VIO -> EKF3 INTEGRATION WORKING (bench)

**Core milestone: cuVSLAM VIO is now fused by ArduPilot EKF3.**

### Container persistence (solved first)
- Discovered run_dev.sh recreates the container -> in-container apt installs were lost.
- Fix: Dockerfile.user custom layer (MAVROS + VSLAM + deps), key ros2_humble.realsense.user.
- Serial access: Isaac entrypoint strips group-add; fixed with HOST udev rule
  (cp210x tty -> GROUP=plugdev, which admin always has). Now persistent.

### Frame convention (measured empirically)
- Moved camera in known directions; cuVSLAM output: forward=+X, up=+Z, right=-Y.
- That is FLU / ROS ENU convention = exactly what MAVROS vision_pose expects.
- So pose copies straight through (no axis remap); MAVROS does ENU->NED.

### Bridge node
- vio_bridge/vio_to_mavros.py: subscribes /visual_slam/tracking/odometry
  (nav_msgs/Odometry, BEST_EFFORT QoS), republishes as geometry_msgs/PoseStamped
  on /mavros/vision_pose/pose, rate-capped to 30 Hz. Preserves header stamp.

### Result (full chain proven)
- camera -> cuVSLAM -> odom -> bridge -> /mavros/vision_pose/pose (30 Hz) -> MAVLink -> EKF3.
- MAVROS log: "EKF3 IMU0 is using external nav data" + "initial pos NED = -0.0,-0.2,-0.1".
  -> EKF3 has ACCEPTED and is FUSING the VIO.
- /mavros/local_position/pose publishes a fused estimate (ArduPilot's own).
- Pre-arm still shows "RC not found" (expected, no TX on bench).

### Open / next
- Validate fused position TRACKS camera motion correctly (sign/axis sanity).
- Formalize bridge into a proper ROS 2 package in the repo.
- Time sync (chrony + MAVLink TIMESYNC) for fusion quality.
- Tune EK3_SRC_OPTIONS=0, VISO_POS_XYZ offsets, VISO_DELAY_MS after 40 deg mount.
- 10 deg... on-site field test; NVMe before flight.
