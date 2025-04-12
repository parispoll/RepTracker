# IMU Visualizer

A Flutter app and Python script for tracking workouts using an IMU sensor. The app connects to an Arduino via Bluetooth, processes accelerometer data, detects reps, classifies exercises, and exports the data to a CSV file. The Python script visualizes the Z-axis data and rep detection.

## Features
- Connects to an Arduino via Bluetooth to receive IMU data.
- Detects reps based on Z-axis acceleration peaks.
- Classifies exercises (Squat, BicepCurl, RomanianDeadlift, BarbellRows) for each set.
- Exports session data to a CSV file in the Downloads directory.
- Visualizes the data using a Python script with Matplotlib.

## Setup
1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/imu_visualizer.git