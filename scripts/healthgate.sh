#!/bin/bash
# healthgate.sh — runs inside the container, in pane 3.
source /opt/ros/humble/setup.bash
echo "=== HEALTH GATE ==="
echo "-- cuVSLAM stable when still? (hold drone still) --"
for i in 1 2 3; do
  ros2 topic echo /visual_slam/tracking/odometry --field pose.pose.position --once 2>/dev/null | grep -E "^[xyz]:"
  echo "-"; sleep 1
done
echo "-- cuVSLAM rate (~90 Hz) --"
timeout 4 ros2 topic hz /visual_slam/tracking/odometry
echo "-- vision_pose (~30 Hz) --"
timeout 4 ros2 topic hz /mavros/vision_pose/pose
echo "-- MAVROS state (~1 Hz = connected) --"
timeout 6 ros2 topic hz /mavros/state
echo "=== gate done. GREEN = all rates good + cuVSLAM near 0 when still ==="
