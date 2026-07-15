#!/bin/bash
# stop_drone.sh — cleanly shut down the whole VIO pipeline.
# Run on the HOST. Stops ROS nodes gracefully (SIGINT so they flush/log),
# then kills the tmux session. Leaves the container + docker running.
#
# Usage:  /mnt/t7ssd/stop_drone.sh

CONTAINER="isaac_ros_dev-aarch64-container"

echo "=== stopping drone pipeline ==="

# is the container running? if not, nothing to stop inside it.
if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "-- sending graceful stop (SIGINT) to ROS nodes --"
  # SIGINT (like Ctrl+C) lets nodes shut down cleanly and flush logs
  docker exec -u admin "$CONTAINER" bash -lc '
    pkill -INT -f vio_to_mavros 2>/dev/null
    pkill -INT -f mavros_node 2>/dev/null
    pkill -INT -f flightmon 2>/dev/null
    sleep 2
    pkill -INT -f visual_slam 2>/dev/null
    pkill -INT -f realsense 2>/dev/null
    pkill -INT -f component_container 2>/dev/null
    sleep 3
    # anything still alive after grace period: force it
    pkill -f vio_to_mavros 2>/dev/null
    pkill -f mavros_node 2>/dev/null
    pkill -f visual_slam 2>/dev/null
    pkill -f realsense 2>/dev/null
    pkill -f component_container 2>/dev/null
    true
  '
  echo "-- ROS nodes stopped --"

  echo "-- killing tmux session 'drone' --"
  docker exec -u admin "$CONTAINER" bash -lc 'tmux kill-session -t drone 2>/dev/null; true'
else
  echo "container not running — nothing to stop inside it."
fi

# also clear any host-side tmux leftovers from earlier script versions
tmux kill-session -t drone 2>/dev/null
tmux kill-session -t _bootstrap 2>/dev/null

echo "=== done. Pipeline stopped cleanly. ==="
echo "Container and Docker are left running (start again with start_drone.sh)."
echo "To also stop the container:   docker stop $CONTAINER"
