import pandas as pd
import matplotlib.pyplot as plt

# Load the CSV file
# Replace with the path to your CSV file
csv_file = "C:/Users/paris/imu_visualizer/dataAnalysis/data/WorkoutSucces.csv"
df = pd.read_csv(csv_file)

# Convert Timestamp to datetime and calculate time in seconds since the start
df["Timestamp"] = pd.to_datetime(df["Timestamp"])
df["Time (s)"] = (df["Timestamp"] - df["Timestamp"].iloc[0]).dt.total_seconds()

# Plot the Z-axis data
plt.figure(figsize=(12, 6))

# Plot Smoothed Z for each exercise
exercises = df["Exercise"].unique()
colors = {"Squat": "blue", "BicepCurl": "green", "RomanianDeadlift": "orange", "BarbellRows": "purple", "unknown": "gray", "": "gray"}
for exercise in exercises:
    subset = df[df["Exercise"] == exercise]
    plt.plot(subset["Time (s)"], subset["Smoothed Z"], label=exercise if exercise else "Idle", color=colors.get(exercise, "gray"))

# Mark where reps were detected
rep_points = df[df["Rep Detected"] == 1]
plt.scatter(rep_points["Time (s)"], rep_points["Smoothed Z"], color="red", label="Rep Detected", marker="o")

# Mark Idle periods
plt.fill_between(
    df["Time (s)"],
    df["Smoothed Z"].min(),
    df["Smoothed Z"].max(),
    where=df["isIdle"] == 1,
    color="gray",
    alpha=0.2,
    label="Idle Periods"
)

# Add labels and legend
plt.xlabel("Time (s)")
plt.ylabel("Z-Axis Acceleration (m/s²)")
plt.title("Workout Session: Z-Axis Data and Rep Detection")
plt.legend()
plt.grid(True)

# Show the plot
plt.show()