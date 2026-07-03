# Engineering Log

Dated record of work, decisions, and rationale. Newest entries at the bottom.

---

## 2026-07-03 -- Foundation: storage, Docker, Isaac ROS container

### Storage (T7 SSD)
- Confirmed no NVMe on carrier board; Samsung T7 (USB) is the only external storage.
- Wiped T7, created GPT + single ext4 partition, label t7ssd,
  UUID 2363d201-6ef9-4e64-ba8d-afbafc811355.
- Mounted at /mnt/t7ssd via /etc/fstab using UUID with nofail +
  x-systemd.device-timeout=10 so a missing drive never blocks boot.
- User-owned; verified writable. Rebooted to confirm auto-mount holds.
- Known risk: USB storage on a vibrating airframe. OK for bench/tethered
  bring-up. NVMe SSD recommended before untethered flight.

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

### Next
- Re-mount camera at ~40 deg; measure and record achieved angle.
- Bring up RealSense inside container: firmware vs librealsense 2.55.1,
  USB3 enumeration, live topics.
