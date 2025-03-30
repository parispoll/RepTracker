import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

csv_file = "C:/Users/paris/imu_visualizer/dataAnalysis/data/Squats3_2025-03-30T19-32-54.523199.csv"

# Validate file
try:
    with open(csv_file, 'r') as f:
        pass
except FileNotFoundError:
    print(f"Error: File '{csv_file}' not found.")
    exit(1)
except PermissionError:
    print(f"Error: Permission denied for '{csv_file}'.")
    exit(1)

# Read and clean CSV
with open(csv_file, 'r') as f:
    lines = f.readlines()
    data_lines = []
    header_found = False
    for line in lines:
        if "Reps and Sets Summary" in line:
            break
        if not header_found and "Timestamp,X,Y,Z" in line:
            header_found = True
        if header_found and line.strip():
            data_lines.append(line)

cleaned_file = csv_file.replace('.csv', '_cleaned.csv')
with open(cleaned_file, 'w') as f:
    f.writelines(data_lines)

df = pd.read_csv(cleaned_file)
if len(df) == 0:
    print("Error: No data found in the CSV.")
    exit(1)

# Reverse X, Y, Z values
df['X'] = df['X'] * -1
df['Y'] = df['Y'] * -1
df['Z'] = df['Z'] * -1

# Calculate duration
df['Timestamp'] = pd.to_datetime(df['Timestamp'])
total_duration = (df['Timestamp'].iloc[-1] - df['Timestamp'].iloc[0]).total_seconds()
print(f"CSV contains {len(df)} samples and spans {total_duration:.2f} seconds.")

# Compute sampling rate
df['TimeDiff'] = df['Timestamp'].diff().dt.total_seconds()
actual_sample_rate = 1 / df['TimeDiff'].dropna().median()
print(f"Detected Sampling Rate: {actual_sample_rate:.2f} Hz")

# Correct timestamps
time_step = 1 / actual_sample_rate
start_time = df['Timestamp'].iloc[0]
df['Timestamp'] = [start_time + pd.Timedelta(seconds=i * time_step) for i in range(len(df))]

# Add Label column based on change magnitude
df['Delta_X'] = df['X'].diff()
df['Delta_Y'] = df['Y'].diff()
df['Delta_Z'] = df['Z'].diff()
df['Change_Magnitude'] = np.sqrt(df['Delta_X'] ** 2 + df['Delta_Y'] ** 2 + df['Delta_Z'] ** 2)

# Define thresholds and durations
idle_threshold = 0.1  # Small changes (noise or minor jitter)
exercise_threshold = 0.5  # Significant movement (e.g., bicep curl)
transition_samples = int(actual_sample_rate * 3)  # 3 seconds for initial Transition
idle_confirm_samples = int(actual_sample_rate * 1)  # 1 second to confirm Idle

# State machine labeling
df['Label'] = 'Idle'  # Start with Idle
current_state = 'Idle'
transition_counter = 0
idle_counter = 0

for i in range(1, len(df)):
    magnitude = df.loc[i, 'Change_Magnitude'] if not pd.isna(df.loc[i, 'Change_Magnitude']) else 0

    if current_state == 'Idle':
        if magnitude > idle_threshold:
            current_state = 'Transition'
            transition_counter = transition_samples
            df.loc[i, 'Label'] = 'Transition'
        else:
            df.loc[i, 'Label'] = 'Idle'

    elif current_state == 'Transition':
        df.loc[i, 'Label'] = 'Transition'
        transition_counter -= 1
        if transition_counter <= 0:
            if magnitude > exercise_threshold:
                current_state = 'Exercise'
                df.loc[i, 'Label'] = 'Exercise'
            elif magnitude <= idle_threshold:
                current_state = 'Idle'
                df.loc[i, 'Label'] = 'Idle'

    elif current_state == 'Exercise':
        if magnitude > exercise_threshold:
            df.loc[i, 'Label'] = 'Exercise'
            idle_counter = 0
        elif magnitude <= idle_threshold:
            idle_counter += 1
            if idle_counter >= idle_confirm_samples:
                current_state = 'Transition'
                transition_counter = transition_samples
                start_idx = max(i - transition_samples, 0)
                df.loc[start_idx:i - 1, 'Label'] = 'Transition'
                df.loc[i, 'Label'] = 'Transition'
            else:
                df.loc[i, 'Label'] = 'Exercise'
        else:
            df.loc[i, 'Label'] = 'Exercise'
            idle_counter = 0

# Post-process: Relabel Transition to Idle if Change_Magnitude <= idle_threshold for 1s
check_window = int(actual_sample_rate * 1)  # 1-second window
for i in range(check_window, len(df) - check_window):
    if df.loc[i, 'Label'] == 'Transition':
        start_idx = max(i - check_window // 2, 0)
        end_idx = min(i + check_window // 2 + 1, len(df))
        window_magnitudes = df.loc[start_idx:end_idx, 'Change_Magnitude'].fillna(0)
        if all(window_magnitudes <= idle_threshold):
            df.loc[i, 'Label'] = 'Idle'

# Convert Timestamp to seconds relative to start for plotting
df['Time_Sec'] = (df['Timestamp'] - df['Timestamp'].iloc[0]).dt.total_seconds()

# Save labeled file
labeled_file = csv_file.replace('.csv', '_labeled.csv')
df.drop(columns=['Delta_X', 'Delta_Y', 'Delta_Z', 'Change_Magnitude', 'TimeDiff']).to_csv(labeled_file, index=False)
print(
    f"Prepared {labeled_file} for Edge Impulse upload with X, Y, Z values reversed and labels (Idle/Transition/Exercise) added.")
print("First few rows of corrected data with labels:")
print(df[['Timestamp', 'X', 'Y', 'Z', 'Label']].head(10))

# Plotting
plt.figure(figsize=(12, 6))
plt.plot(df['Time_Sec'], df['X'], label='X (g)', color='r')
plt.plot(df['Time_Sec'], df['Y'], label='Y (g)', color='g')
plt.plot(df['Time_Sec'], df['Z'], label='Z (g)', color='b')
for label, color in zip(['Idle', 'Transition', 'Exercise'], ['lightgrey', 'yellow', 'lightgreen']):
    label_indices = df['Label'] == label
    plt.fill_between(df['Time_Sec'], plt.ylim()[0], plt.ylim()[1],
                     where=label_indices, color=color, alpha=0.3, label=label)
plt.xlabel('Time (seconds)')
plt.ylabel('Acceleration (g)')
plt.title('Accelerometer Data with Idle/Transition/Exercise Labels (Refined Transition Check)')
plt.legend()
plt.grid(True)
plt.show()