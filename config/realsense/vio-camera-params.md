# RealSense D435i — Verified VIO Camera Parameters

These are the camera parameters that Isaac ROS Visual SLAM (cuVSLAM) uses for a
RealSense stereo camera, taken from NVIDIA's official
`isaac_ros_visual_slam_realsense.launch.py` and confirmed working on our D435i.

## Device (this unit)
- Model: Intel RealSense D435i
- Serial: 344522070088
- Firmware: 5.13.0.50 (production-designated; compatible with librealsense 2.55.1)
- USB: 3.2 (5000 Mbps negotiated) — confirmed, not USB2

## Parameters (what cuVSLAM expects)
- `enable_infra1: true`, `enable_infra2: true`   # stereo IR pair (cuVSLAM input)
- `enable_color: false`, `enable_depth: false`    # not used by stereo VIO
- `depth_module.emitter_enabled: 0`               # emitter OFF — projector dots
                                                  #   corrupt feature tracking / cause drift
- `depth_module.profile: 640x360x90`              # low-res, high-FPS IR for VIO
- `enable_gyro: true`, `enable_accel: true`
- `gyro_fps: 200`, `accel_fps: 200`
- `unite_imu_method: 2`                           # linear-interpolated unified /camera/imu

## Standalone camera-only launch (for testing the camera without VSLAM)
```
ros2 launch realsense2_camera rs_launch.py \
  enable_color:=false enable_depth:=false \
  enable_infra1:=true enable_infra2:=true \
  depth_module.emitter_enabled:=0 depth_module.profile:=640x360x90 \
  enable_gyro:=true enable_accel:=true gyro_fps:=200 accel_fps:=200 \
  unite_imu_method:=2
```

## Measured rates (bench, this config) — healthy
- /camera/infra1/image_rect_raw : ~89.9 Hz (std dev ~0.0005 s)
- /camera/infra2/image_rect_raw : ~89.9 Hz (matched to infra1)
- /camera/imu                   : ~199.6 Hz (std dev ~0.0004 s)
- USB control_transfer warnings: only at startup, then clean
  (the earlier warning flood was caused by the color stream; removing it fixed it)

## Notes / open items
- IMU factory calibration not present ("default intrinsic/extrinsic used").
  Consider running Intel's rs-imu-calibration for better VIO accuracy later.
- Emitter is OFF for VIO. (If ever using RGBD/depth mode instead, emitter would be ON;
  but D435i lacks RGB-depth hardware sync, so stereo-IR mode is preferred.)
- IMU gyro uses static sensitivity (FW < 5.16), the stable path for our SDK.
