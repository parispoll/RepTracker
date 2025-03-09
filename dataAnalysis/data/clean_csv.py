import pandas as pd
import datetime

# File path to your CSV (update this to your file location)
csv_file = "C:/Users/paris/imu_visualizer/dataAnalysis/data/Squats2.csv"  # Example path

# Validate file exists
try:
    with open(csv_file, 'r') as f:
        pass  # Just check if file can be opened
except FileNotFoundError:
    print(f"Error: File '{csv_file}' not found. Please check the path and try again.")
    exit(1)
except PermissionError:
    print(f"Error: Permission denied for file '{csv_file}'. Please ensure you have read access.")
    exit(1)

sample_rate = 33.56  # Hz from your output (adjust if different)
time_step = 1 / sample_rate  # ~0.0298 seconds per sample

# Read the CSV, stopping at "Reps and Sets Summary"
with open(csv_file, 'r') as f:
    lines = f.readlines()
    data_lines = []
    header_found = False
    for line in lines:
        if "Reps and Sets Summary" in line:
            break
        if not header_found and "Timestamp,X,Y,Z" in line:
            header_found = True
        if header_found:
            # Strip whitespace and ensure non-empty
            line = line.strip()
            if line:
                data_lines.append(line + '\n')

# Write cleaned data to a temporary file
cleaned_file = csv_file.replace('.csv', '_cleaned.csv')
with open(cleaned_file, 'w') as f:
    f.writelines(data_lines)  # Write cleaned lines starting with header

# Read the cleaned CSV into a DataFrame for timestamp correction
df = pd.read_csv(cleaned_file)

# Assume a starting timestamp (replace with your actual start time if known)
start_time = pd.Timestamp('2025-03-03T12:00:00.000Z')  # Example; adjust to your actual start

# Create new timestamps based on sample rate
df['Timestamp'] = [start_time + pd.Timedelta(seconds=i * time_step) for i in range(len(df))]

# Save to a final file with corrected timestamps, ready for Edge Impulse
fixed_file = csv_file.replace('.csv', '_fixed.csv')
df.to_csv(fixed_file, index=False)

print(f"Prepared {fixed_file} for Edge Impulse upload.")