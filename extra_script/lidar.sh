cd ~/catkin_ws
sudo chmod 777 /dev/ttyUSB0
source /home/nvidia/catkin_ws/devel/setup.bash
roslaunch livox_ros_driver livox_lidar_msg.launch
