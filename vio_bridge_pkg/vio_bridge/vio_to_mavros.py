#!/usr/bin/env python3
# vio_to_mavros.py
# Minimal bridge: cuVSLAM odometry -> MAVROS vision_pose.
# cuVSLAM outputs FLU (X-forward, Y-left, Z-up) = ROS ENU convention,
# which is exactly what MAVROS vision_pose expects before its internal
# ENU->NED conversion. So pose copies straight across (no axis remap).
# Rate-limited to ~RATE_HZ to avoid flooding the FCU link.

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy
from nav_msgs.msg import Odometry
from geometry_msgs.msg import PoseStamped

RATE_HZ = 30.0  # republish cap; ArduPilot vision fusion needs ~10-30 Hz


class VioToMavros(Node):
    def __init__(self):
        super().__init__('vio_to_mavros')
        # cuVSLAM publishes best-effort; match it on the subscription.
        sub_qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )
        self.sub = self.create_subscription(
            Odometry, '/visual_slam/tracking/odometry',
            self.cb, sub_qos)
        self.pub = self.create_publisher(
            PoseStamped, '/mavros/vision_pose/pose', 10)
        self._min_dt = 1.0 / RATE_HZ
        self._last = 0.0
        self._n = 0
        self.get_logger().info(
            'vio_to_mavros: /visual_slam/tracking/odometry -> '
            '/mavros/vision_pose/pose @ %s Hz' % RATE_HZ)

    def cb(self, msg: Odometry):
        # rate-limit using the message stamp
        t = msg.header.stamp.sec + msg.header.stamp.nanosec * 1e-9
        if (t - self._last) < self._min_dt:
            return
        self._last = t
        p = PoseStamped()
        p.header = msg.header  # preserve stamp + frame_id (fresh -> MAVROS accepts)
        p.pose = msg.pose.pose  # copy position + orientation (no remap; FLU=ENU)
        self.pub.publish(p)
        self._n += 1
        if self._n % 150 == 0:
            self.get_logger().info('forwarded %d poses' % self._n)


def main():
    rclpy.init()
    n = VioToMavros()
    try:
        rclpy.spin(n)
    except KeyboardInterrupt:
        pass
    finally:
        n.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
