#!/bin/bash
# start_drone.sh v3 — one command to bring up the whole pipeline.
# Runs host pre-checks, ensures container is up, then launches a 4-pane
# tmux session INSIDE the container (robust: no host->container quoting).
#
# tmux: move = Ctrl+b then arrow ; detach = Ctrl+b then d
#       reattach = docker exec -it -u admin <container> tmux attach -t drone

CONTAINER="isaac_ros_dev-aarch64-container"
WS="/mnt/t7ssd/workspaces/isaac_ros-dev"
COMMON="$WS/src/isaac_ros_common"

echo "=== HOST PRE-CHECKS ==="
YEAR=$(date +%Y)
if [ "$YEAR" -lt 2025 ]; then
  echo "!! CLOCK WRONG (year=$YEAR). Fix:  sudo date -s \"2026-MM-DD HH:MM:SS\""; exit 1
fi
echo "clock OK: $(date)"

findmnt /mnt/t7ssd >/dev/null || sudo mount /mnt/t7ssd || { echo "!! T7 mount failed"; exit 1; }
if findmnt -no OPTIONS /mnt/t7ssd | grep -qw ro; then
  echo "!! T7 READ-ONLY (drive dropped out). Recover:"
  echo "   sudo systemctl stop docker docker.socket; sudo umount -l /mnt/t7ssd"
  echo "   sudo fsck -y /dev/sda1; sudo mount /mnt/t7ssd  (and RESEAT the USB cable)"; exit 1
fi
( touch /mnt/t7ssd/.wtest && rm -f /mnt/t7ssd/.wtest ) 2>/dev/null || { echo "!! T7 not writable"; exit 1; }
echo "T7 OK (writable)"

lsusb | grep -qi realsense && echo "camera OK" || echo "!! CAMERA NOT FOUND (replug)"
[ -e /dev/ttyUSB0 ] && echo "serial OK" || echo "!! /dev/ttyUSB0 MISSING (Cube powered?)"

docker info >/dev/null 2>&1 || { sudo systemctl reset-failed docker 2>/dev/null; sudo systemctl start docker; sleep 3; }
echo "docker OK"
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml >/dev/null 2>&1 && echo "CDI OK"

# ensure container is running
if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "starting existing container..."; docker start "$CONTAINER" >/dev/null
  else
    echo "!! container does not exist. Create it once manually:"
    echo "   cd $COMMON && ./scripts/run_dev.sh   (then exit, then re-run this)"; exit 1
  fi
fi
# wait until it's truly running
for i in $(seq 1 15); do docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" && break; sleep 1; done
docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" || { echo "!! container not running"; exit 1; }
echo "container OK"

# copy the inner scripts into the container's workspace (from host T7 path)
cp /mnt/t7ssd/drone_panes.sh /mnt/t7ssd/healthgate.sh "$WS/" 2>/dev/null
chmod +x "$WS/drone_panes.sh" "$WS/healthgate.sh" 2>/dev/null

# build the panes INSIDE the container
docker exec -u admin "$CONTAINER" bash -lc "bash /workspaces/isaac_ros-dev/drone_panes.sh"

echo
echo "=== pipeline launching in container tmux session 'drone' ==="
echo "Attaching now. Detach: Ctrl+b then d.  Move: Ctrl+b then arrow."
sleep 1
exec docker exec -it -u admin "$CONTAINER" tmux attach -t drone
