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
