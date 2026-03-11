# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ROS driver for Hikvision MVS (Machine Vision) cameras (GigE Vision / USB3 Vision). Built for ROS 1 (Melodic/Noetic) on aarch64 (Jetson) and x86_64. Uses the MvCameraControl SDK installed at `/opt/MVS/`.

## Build

```bash
# Build in catkin workspace
cd ~/catkin_ws && catkin_make
# Or build only this package
catkin_make --pkg mvs_ros_driver
```

The executable produced is `grabImgWithTrigger`.

## Run

```bash
# Single camera
roslaunch mvs_ros_driver mvs_camera_trigger.launch

# Dual camera (left + right)
roslaunch mvs_ros_driver mvs_multiple_camera.launch
```

Camera parameters are configured via YAML files in `config/`. The camera is selected by `SerialNumber` in the YAML.

## Architecture

- **Single source file:** `src/grab_trigger.cpp` — contains all logic
- **Main thread:** ROS init, camera enumeration (by serial number), parameter configuration, starts grabbing
- **Worker thread (`WorkThread`):** frame capture loop → pixel format conversion (Bayer→RGB) → optional resize → publish as `sensor_msgs/Image`
- **Hardware trigger:** optional GPIO-based external trigger (Line0), with shared memory timestamp sync from `/home/$USER/timeshare`

## MVS SDK Dependency

- SDK install path: `/opt/MVS/`
- Headers: `/opt/MVS/include/` (MvCameraControl.h, CameraParams.h, etc.)
- Libraries: `/opt/MVS/lib/aarch64/` (ARM) or `/opt/MVS/lib/64/` (x86_64)
- The CMakeLists.txt auto-detects architecture via `CMAKE_SYSTEM_PROCESSOR` to select the correct library path
- Links against `libMvCameraControl.so`

## Configuration (YAML)

Key parameters in `config/*.yaml`:
- `SerialNumber` — camera serial for identification
- `TopicName` — ROS image topic name
- `TriggerEnable` — 0=free-run, 1=hardware trigger
- `ExposureAutoMode` — 0=Off, 1=Once, 2=Continuous
- `PixelFormat` — 0=RGB8, 1=BayerRG8, 2=BayerRG12Packed, 3=BayerGB12Packed, 4=BayerGB8
- `image_scale` — output resize factor (1.0=full resolution)

## Platform Notes

- On Jetson (aarch64): links from `/opt/MVS/lib/aarch64/`
- On x86_64: links from `/opt/MVS/lib/64/`
- C++14 required
- ROS dependencies: cv_bridge, image_transport, roscpp, sensor_msgs, std_msgs
- Links OpenCV (via `find_package(OpenCV REQUIRED)`)

## Known Issues & Fixes (2026-03-11)

### OpenCV 4.2/4.5 双版本 ABI 冲突导致段错误 (SIGSEGV, exit code -11)

**问题背景：** JetPack 环境下同时存在 OpenCV 4.2（系统 apt 包，cv_bridge 依赖）和 OpenCV 4.5（NVIDIA 提供的 libopencv-dev）。`find_package(OpenCV)` 找到 4.5 的头文件和库，但 cv_bridge 运行时链接 4.2。两个版本同时加载会导致 ABI 不兼容。

**崩溃现象：** 相机能正常枚举和配置，`MV_CC_ConvertPixelType` 成功后，在 `cv::resize` 或 `cv_bridge::CvImage::toImageMsg()` 处段错误。

**根本原因：** OpenCV 4.5 将 `cv::Mat::Mat()`（默认构造函数）等函数从内联改为外部链接。用 4.5 头文件编译的代码引用这些符号，但 4.2 库中不存在。同时 `cv::resize` 原地操作在双版本环境下行为异常。

**已实施的修复（均在工作空间内，无系统级修改）：**

1. **CMakeLists.txt：**
   - 删除 `set(cv_bridge_DIR /usr/local/share/cv_bridge/cmake)` — 指向不存在的路径
   - 删除 `find_package(PCL REQUIRED)` 及相关 include/link — 代码未使用 PCL
   - 保留 `find_package(OpenCV REQUIRED)` 链接 4.5（无法用 4.5 头文件 + 4.2 库编译）

2. **src/grab_trigger.cpp：**
   - 消除 `cv::Mat` 默认构造函数调用：`cv::Mat srcImage;` → `cv::Mat srcImage(h, w, type, buf);`
   - `image_scale ≈ 1.0` 时完全跳过 `cv::resize`，避免触发 4.2/4.5 冲突
   - 需要 resize 时使用独立输出 Mat，避免原地 resize 内存问题
   - 修正 `cv::resize` 参数错误：`cv::INTER_LINEAR` 原来被错传给 `fx` 参数位置

**新设备部署注意：** 代码直接复制即可编译运行，只需修改 yaml 中的 `SerialNumber`。如果新设备不存在 OpenCV 双版本问题则更不会有问题。
