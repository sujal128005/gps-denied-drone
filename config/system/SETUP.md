# System Configuration Snapshots

Reference copies of the host-side configuration created during setup, so the
platform can be reproduced (e.g. if the microSD is re-flashed or a second unit
is built). These are **snapshots for reference** — the live files live at the
paths noted below. Editing a file here does nothing until copied to its real path.

## Files and their real locations

| Snapshot (here)            | Real path on host                                             | Purpose |
|----------------------------|---------------------------------------------------------------|---------|
| `daemon.json`              | `/etc/docker/daemon.json`                                     | Docker data-root on T7 + nvidia runtime |
| `fstab-t7.line`            | one line appended to `/etc/fstab`                             | Mount T7 by UUID with `nofail` |
| `wait-for-t7.conf`         | `/etc/systemd/system/docker.service.d/wait-for-t7.conf`       | Docker waits for T7 mount before starting |
| `isaac_ros_common-config`  | `<repo>/src/isaac_ros_common/scripts/.isaac_ros_common-config`| Isaac ROS container image key |

## Not snapshotted here (installed from upstream)

- **RealSense udev rules** — `/etc/udev/rules.d/99-realsense-libusb.rules`,
  downloaded from the official IntelRealSense/librealsense repo (do not hand-edit;
  re-download from upstream). Grants `plugdev`/`0666` USB access to the D435i.
- **CDI spec** — `/etc/cdi/nvidia.yaml`, generated on-device with
  `sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`.
  Static on Container Toolkit 1.16.2 — regenerate after any JetPack/driver upgrade.
- **`ISAAC_ROS_WS`** — exported in `~/.bashrc`:
  `export ISAAC_ROS_WS="/mnt/t7ssd/workspaces/isaac_ros-dev/"`

## Rebuild order (summary)

1. Flash JetPack 6.2 (L4T R36.4.3), Ubuntu 22.04.
2. Format T7 ext4, add fstab line (UUID differs per drive — re-check with `blkid`).
3. Docker: add user to `docker` group; apply `daemon.json`; add `wait-for-t7.conf`;
   `systemctl daemon-reload` + restart docker.
4. `sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`.
5. Install RealSense udev rules from upstream; `udevadm control --reload-rules && udevadm trigger`.
6. Install git-lfs (`sudo apt install git-lfs && git lfs install`).
7. Clone `isaac_ros_common` @ release-3.2 into `$ISAAC_ROS_WS/src`; add `.isaac_ros_common-config`.
8. `./scripts/run_dev.sh` to build/launch the container.
