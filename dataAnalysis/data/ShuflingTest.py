import pandas as pd
import numpy as np

# List of CSV files to merge (adjust paths; use multiple if available, or just one)
csv_files = [
    "C:/Users/paris/imu_visualizer/dataAnalysis/data/Labeled_data/Squats3_2025-03-30T19-32-54.523199_labeled.csv",
    "C:/Users/paris/imu_visualizer/dataAnalysis/data/Labeled_data/Squats_2025-03-30T16-29-02.537433_labeled.csv",
    "C:/Users/paris/imu_visualizer/dataAnalysis/data/Labeled_data/Squats2_2025-03-30T19-22-09.404243_labeled.csv",
]

# Load and merge CSVs
dataframes = []
for csv_file in csv_files:
    try:
        df = pd.read_csv(csv_file)
        if df.empty:
            print(f"Warning: {csv_file} is empty.")
        else:
            dataframes.append(df)
    except FileNotFoundError:
        print(f"Error: File '{csv_file}' not found.")
        exit(1)
    except Exception as e:
        print(f"Error loading {csv_file}: {e}")
        exit(1)

if not dataframes:
    print("Error: No valid CSVs loaded.")
    exit(1)

merged_df = pd.concat(dataframes, ignore_index=True)
print(f"Merged {len(dataframes)} CSVs into a DataFrame with {len(merged_df)} rows.")


# Function to identify complete cycles
def extract_cycles(df):
    cycles = []
    start_idx = 0
    state_sequence = ['Idle', 'Transition', 'Exercise', 'Transition', 'Idle']
    i = 0

    while i < len(df) - 1:
        # Look for the start of a cycle (Idle)
        if df.loc[i, 'Label'] == 'Idle':
            start_idx = i
            valid_cycle = True
            cycle_length = 0

            # Check if we can find a full cycle
            for state in state_sequence[1:]:
                while i < len(df) and df.loc[i, 'Label'] != state:
                    i += 1
                    cycle_length += 1
                if i >= len(df):
                    valid_cycle = False
                    break
                cycle_length += 1

            # If a full cycle is found, extract it
            if valid_cycle and i < len(df):
                end_idx = i + 1  # Include the last Idle
                cycles.append(df.iloc[start_idx:end_idx])
            i = end_idx if valid_cycle else i + 1
        else:
            i += 1

    # Handle any remaining data (e.g., incomplete cycle at the end)
    if start_idx < len(df) - 1 and not cycles or cycles[-1].index[-1] < len(df) - 1:
        remaining = df.iloc[cycles[-1].index[-1] + 1:] if cycles else df
        if not remaining.empty:
            cycles.append(remaining)

    return cycles


# Extract cycles from the merged data
cycles = extract_cycles(merged_df)
print(f"Found {len(cycles)} cycles (including any incomplete trailing data).")

# Shuffle the cycles
np.random.seed(42)  # For reproducibility; remove for true randomness
shuffled_cycles = np.random.permutation(cycles).tolist()

# Recombine the shuffled cycles
randomized_df = pd.concat(shuffled_cycles, ignore_index=True)
print(f"Recombined shuffled cycles into {len(randomized_df)} rows.")

# Recompute timestamps to maintain continuity
# Estimate sampling rate from the original data
original_df = pd.read_csv(csv_files[0])
original_df['Timestamp'] = pd.to_datetime(original_df['Timestamp'])
time_diff = original_df['Timestamp'].diff().dt.total_seconds().dropna().median()
sampling_rate = 1 / time_diff
print(f"Using estimated sampling rate: {sampling_rate:.2f} Hz")

# Generate new timestamps
start_time = pd.to_datetime("2025-03-30 14:00:00")  # Arbitrary start for testing
time_step = 1 / sampling_rate
randomized_df['Timestamp'] = [start_time + pd.Timedelta(seconds=i * time_step) for i in range(len(randomized_df))]

# Ensure column order
randomized_df = randomized_df[['Timestamp', 'X', 'Y', 'Z', 'Label']]

# Save the randomized data
output_file = "C:/Users/paris/imu_visualizer/dataAnalysis/data/bicepCurl_randomized_cycles_test.csv"
randomized_df.to_csv(output_file, index=False)
print(f"Saved randomized test data with preserved cycles to {output_file}.")

# Optional: Preview
print("First few rows of randomized data:")
print(randomized_df.head(10))