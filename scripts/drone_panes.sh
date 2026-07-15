#!/bin/bash
# drone_panes.sh — runs INSIDE the container. Builds the 4-pane tmux session.
SESSION="drone"
WS="/workspaces/isaac_ros-dev"
LAUNCH="$WS/vio_slam_noimu.launch.py"
SRC="source /opt/ros/humble/setup.bash"

# clear stale nodes (but NOT the tmux server)
pkill -f visual_slam 2>/dev/null; pkill -f realsense 2>/dev/null
pkill -f component_container 2>/dev/null; pkill -f mavros_node 2>/dev/null
pkill -f vio_to_mavros 2>/dev/null
sleep 2

# kill only our session if it exists, leave the server alone
tmux has-session -t "$SESSION" 2>/dev/null && tmux kill-session -t "$SESSION"

# pane 0: cuVSLAM  — detached session, server persists
tmux new-session -d -s "$SESSION" -n main \
  "$SRC; echo '[cuVSLAM]'; sleep 3; ros2 launch $LAUNCH; echo '[cuVSLAM EXITED]'; exec bash"

# pane 1: MAVROS
tmux split-window -h -t "$SESSION" \
  "sleep 8; $SRC; echo '[MAVROS]'; ros2 launch mavros apm.launch fcu_url:=/dev/ttyUSB0:921600; echo '[MAVROS EXITED]'; exec bash"

# pane 2: bridge
tmux split-window -v -t "${SESSION}.0" \
  "sleep 15; $SRC; source $WS/install/setup.bash; echo '[bridge]'; ros2 run vio_bridge vio_to_mavros; echo '[bridge EXITED]'; exec bash"

# pane 3: health gate
tmux split-window -v -t "${SESSION}.1" \
  "sleep 24; $SRC; bash $WS/healthgate.sh; exec bash"

tmux select-layout -t "$SESSION" tiled
# leave the panes with a shell so they never collapse the session
tmux set-option -t "$SESSION" remain-on-exit on 2>/dev/null
echo "built session $SESSION"
tmux ls
