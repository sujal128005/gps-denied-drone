#!/bin/bash
# flightmon.sh — live flight monitor + post-flight summary.
# Run in terminal 4 (inside container) during a flight.
# It streams health once per second while flying, and when you press
# Ctrl+C (after landing + disarm) it prints a summary of the whole flight.
#
# Usage:  bash /workspaces/isaac_ros-dev/flightmon.sh

source /opt/ros/humble/setup.bash 2>/dev/null

# ---- state for the summary ----
SAMPLES=0
VIO_OK=0; VIO_BAD=0
MAX_ABS=0.0
LAST_MODE=""
declare -A MODES_SEEN
ARM_EVENTS=0
START_T=$(date +%s)
MAX_X=-9999; MIN_X=9999; MAX_Y=-9999; MIN_Y=9999; MAX_Z=-9999; MIN_Z=9999
LOGFILE="/workspaces/isaac_ros-dev/flightlog_$(date +%H%M%S).txt"

echo "============================================================"
echo " LIVE FLIGHT MONITOR — logging to $LOGFILE"
echo " Streaming health every 1s. Press Ctrl+C after LAND+DISARM"
echo " to see the flight summary."
echo "============================================================"

# ---- summary printed on Ctrl+C ----
summary() {
  END_T=$(date +%s)
  DUR=$((END_T - START_T))
  echo ""
  echo "============================================================"
  echo " FLIGHT SUMMARY"
  echo "============================================================"
  echo " Duration monitored : ${DUR}s"
  echo " Samples taken      : $SAMPLES"
  echo " VIO healthy samples: $VIO_OK"
  echo " VIO bad/no-data    : $VIO_BAD"
  echo " Flight modes seen  : ${!MODES_SEEN[@]}"
  echo " Arm/disarm events  : $ARM_EVENTS"
  echo " cuVSLAM position range during flight:"
  echo "     X: $MIN_X .. $MAX_X m"
  echo "     Y: $MIN_Y .. $MAX_Y m"
  echo "     Z: $MIN_Z .. $MAX_Z m"
  echo " Max abs position   : $MAX_ABS m  (huge = VIO diverged)"
  echo ""
  if [ "$VIO_BAD" -gt "$VIO_OK" ]; then
    echo " >> WARNING: VIO was unhealthy for most of the flight."
  else
    echo " >> VIO tracking was healthy for most of the flight."
  fi
  echo ""
  echo " NOTE: this is a live-monitor summary. The AUTHORITATIVE data"
  echo " is the flight controller .BIN log — pull it and check RCOU"
  echo " (motor outputs) and VIBE (vibration) for the real verdict."
  echo " Full stream saved to: $LOGFILE"
  echo "============================================================"
  exit 0
}
trap summary INT

# ---- helper: get one numeric field from a topic ----
getpos() {
  ros2 topic echo /visual_slam/tracking/odometry --field pose.pose.position --once 2>/dev/null
}

# ---- main loop ----
while true; do
  SAMPLES=$((SAMPLES+1))
  TS=$(date +%H:%M:%S)

  # cuVSLAM position
  POS=$(getpos)
  X=$(echo "$POS" | awk '/^x:/{print $2}')
  Y=$(echo "$POS" | awk '/^y:/{print $2}')
  Z=$(echo "$POS" | awk '/^z:/{print $2}')

  if [ -n "$X" ]; then
    VIO_OK=$((VIO_OK+1))
    read MAX_X MIN_X MAX_Y MIN_Y MAX_Z MIN_Z MAX_ABS <<< $(awk -v x="$X" -v y="$Y" -v z="$Z" \
      -v mx="$MAX_X" -v nx="$MIN_X" -v my="$MAX_Y" -v ny="$MIN_Y" -v mz="$MAX_Z" -v nz="$MIN_Z" -v ma="$MAX_ABS" \
      'BEGIN{
        if(x>mx)mx=x; if(x<nx)nx=x;
        if(y>my)my=y; if(y<ny)ny=y;
        if(z>mz)mz=z; if(z<nz)nz=z;
        ax=(x<0?-x:x); ay=(y<0?-y:y); az=(z<0?-z:z);
        m=ax; if(ay>m)m=ay; if(az>m)m=az; if(m>ma)ma=m;
        printf "%.3f %.3f %.3f %.3f %.3f %.3f %.3f", mx,nx,my,ny,mz,nz,ma
      }')
    VIOSTR=$(printf "VIO x=%+.3f y=%+.3f z=%+.3f" "$X" "$Y" "$Z")
  else
    VIO_BAD=$((VIO_BAD+1))
    VIOSTR="VIO --no data--"
  fi

  ST=$(timeout 1 ros2 topic echo /mavros/state --once 2>/dev/null)
  MODE=$(echo "$ST" | awk -F'"' '/mode:/{print $2}')
  ARMED=$(echo "$ST" | awk '/armed:/{print $2}')
  [ -n "$MODE" ] && MODES_SEEN["$MODE"]=1
  if [ -n "$MODE" ] && [ "$MODE" != "$LAST_MODE" ]; then
    [ -n "$LAST_MODE" ] && ARM_EVENTS=$((ARM_EVENTS+1))
    LAST_MODE="$MODE"
  fi
  MODESTR="mode=${MODE:-?} armed=${ARMED:-?}"

  LINE="[$TS] $VIOSTR | $MODESTR"
  echo "$LINE"
  echo "$LINE" >> "$LOGFILE"
  sleep 1
done
