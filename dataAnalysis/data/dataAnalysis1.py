import pandas as pd
import matplotlib.pyplot as plt
import io
import numpy as np
import kineticstoolkit.lab as ktk

# File path to your CSV (update this to your file location)
csv_file = "C:/Users/paris/imu_visualizer/dataAnalysis/data/Raw_data/barbeleows_2025-03-30T15-06-49.910440.csv"  # Example path


# Read the CSV, skipping the "Reps and Sets Summary" section
def read_accelerometer_data(file_path):
    with open(file_path, 'r') as f:
        lines = f.readlines()
        accel_lines = []
        for line in lines:
            if line.strip() == "":
                break
            accel_lines.append(line)

    df = pd.read_csv(io.StringIO(''.join(accel_lines)), skiprows=1)
    df['Timestamp'] = pd.to_datetime(df['Timestamp'])
    return df


# Prepare TimeSeries and calculate magnitude
def prepare_timeseries(df):
    ts = ktk.TimeSeries()
    ts.time = (df['Timestamp'] - df['Timestamp'].iloc[0]).dt.total_seconds().to_numpy()
    ts.data['X'] = df['X'].to_numpy()
    ts.data['Y'] = df['Y'].to_numpy()
    ts.data['Z'] = df['Z'].to_numpy()
    ts.data['Magnitude'] = np.sqrt(df['X'] ** 2 + df['Y'] ** 2 + df['Z'] ** 2)
    print(
        f"Raw Magnitude Stats: Min={ts.data['Magnitude'].min():.2f}, Max={ts.data['Magnitude'].max():.2f}, Mean={ts.data['Magnitude'].mean():.2f}")
    return ts


# Smooth the TimeSeries data with a Butterworth filter
# Smooth the TimeSeries data with a Butterworth filter
def smooth_timeseries(ts, fc=5.0, order=2, btype='lowpass', sample_rate=33.29):
    # Check raw sample rate
    time_deltas = np.diff(ts.time)
    avg_sample_rate = 1 / np.mean(time_deltas)
    print(f"Raw Average Sample Rate: {avg_sample_rate:.2f} Hz")

    # Resample to a constant sample rate (33.29 Hz from data)
    ts_resampled = ts.resample(sample_rate)

    # Apply Butterworth filter to the resampled TimeSeries
    ts_smoothed = ktk.filters.butter(ts_resampled, btype=btype, fc=fc, order=order)

    # Print smoothed magnitude stats for verification
    print(
        f"Smoothed Magnitude Stats: Min={ts_smoothed.data['Magnitude'].min():.2f}, Max={ts_smoothed.data['Magnitude'].max():.2f}, Mean={ts_smoothed.data['Magnitude'].mean():.2f}")
    return ts_smoothed

# Manually edit events
def edit_events(ts):
    ts_events = ts.ui_edit_events()
    return ts_events




import numpy as np
import matplotlib.pyplot as plt
from scipy.signal import argrelextrema


def plot_z_with_filtered_local_max(ts, title="Local Maxima Below Zero in Z-Axis Data"):
    """
    Plots the Z-axis data from a TimeSeries object and marks only local maxima that are below zero.

    Parameters:
    - ts: KTK TimeSeries object containing 'Z' data key.
    - title: String, title of the plot.
    """
    # Ensure the data exists
    if 'Z' not in ts.data or len(ts.data['Z']) == 0:
        print("Error: No 'Z' data available in the TimeSeries.")
        return

    # Extract time and Z-axis acceleration data
    time = ts.time
    z_data = ts.data['Z']

    # Find local maxima
    local_max_indices = argrelextrema(z_data, np.greater)[0]  # Indices of local maxima

    # Filter to keep only those below zero
    local_max_indices = [idx for idx in local_max_indices if z_data[idx] < 0.5]

    # Extract corresponding time and values
    local_max_times = time[local_max_indices]
    local_max_vals = z_data[local_max_indices]

    # Create the plot
    plt.figure(figsize=(12, 6))
    plt.plot(time, z_data, label='Z-Axis Acceleration', color='blue')

    # Mark filtered local maxima (green)
    plt.scatter(local_max_times, local_max_vals, color='green', s=80, label='Local Maxima < 0', zorder=5)
    for t, v in zip(local_max_times, local_max_vals):
        plt.annotate(f"{v:.2f}", (t, v), textcoords="offset points", xytext=(0, 10), ha='center', fontsize=10,
                     color='green')

    # Add labels and styling
    plt.title(title)
    plt.xlabel('Time (s)')
    plt.ylabel('Acceleration (m/s²)')
    plt.legend()
    plt.grid(True)
    plt.tight_layout()
    plt.show()


from scipy.signal import find_peaks


from scipy.signal import find_peaks

def detect_cycles_peak_based(ts, min_height=0, min_distance=30, min_prominence=0.5):
    """
    Detects cycles based on local maxima in the Z-axis acceleration data.

    Parameters:
    - ts: KTK TimeSeries object containing 'Z' data key.
    - min_height: Minimum peak height to be considered a cycle (adjust based on data).
    - min_distance: Minimum number of points between detected peaks (to remove noise).
    - min_prominence: Minimum prominence of peaks to avoid small fluctuations.

    Returns:
    - cycle_times: List of timestamps where new cycles start.
    - cycle_indices: Indices in the time array where peaks occur.
    """
    if 'Z' not in ts.data or len(ts.data['Z']) == 0:
        print("Error: No 'Z' data available in the TimeSeries.")
        return [], []

    time = ts.time
    z_data = ts.data['Z']

    # Detect peaks with adjustable sensitivity
    peak_indices, _ = find_peaks(z_data, height=min_height, distance=min_distance, prominence=min_prominence)

    # Extract peak times
    cycle_times = time[peak_indices]

    print(f"Detected {len(cycle_times)} cycles based on peaks.")

    return cycle_times, peak_indices


def count_reps_and_sets(ts, min_height=0, min_distance=50, min_prominence=0.8, set_gap_threshold=5.0):
    """
    Counts the number of reps and sets based on detected peaks.

    Parameters:
    - ts: KTK TimeSeries object containing 'Z' data key.
    - min_height: Minimum peak height to detect reps.
    - min_distance: Minimum number of points between reps.
    - min_prominence: Minimum prominence of peaks (to remove noise).
    - set_gap_threshold: Time gap (in seconds) between peaks to consider a new set.

    Returns:
    - rep_count: Total number of reps detected.
    - set_count: Total number of sets detected.
    - sets: List of sets, each containing a list of rep timestamps.
    """

    if 'Z' not in ts.data or len(ts.data['Z']) == 0:
        print("Error: No 'Z' data available in the TimeSeries.")
        return 0, 0, []

    time = ts.time
    z_data = ts.data['Z']

    # Detect reps (peaks)
    peak_indices, _ = find_peaks(z_data, height=min_height, distance=min_distance, prominence=min_prominence)
    rep_times = time[peak_indices]  # Get timestamps of detected reps

    if len(rep_times) == 0:
        print("No reps detected.")
        return 0, 0, []

    # Detect sets by checking for large gaps between reps
    sets = []
    current_set = []
    last_rep_time = rep_times[0]

    for rep_time in rep_times:
        if (rep_time - last_rep_time) > set_gap_threshold:  # New set detected
            if len(current_set) > 0:
                sets.append(current_set)  # Save previous set
            current_set = []  # Start a new set

        current_set.append(rep_time)
        last_rep_time = rep_time  # Update last rep time

    if len(current_set) > 0:  # Add the last set
        sets.append(current_set)

    # Count total reps and sets
    rep_count = sum(len(s) for s in sets)
    set_count = len(sets)

    # Print results
    print(f"Total Sets: {set_count}")
    for i, s in enumerate(sets, start=1):
        print(f"  Set {i}: {len(s)} reps | Start: {s[0]:.2f}s | End: {s[-1]:.2f}s | Duration: {s[-1] - s[0]:.2f}s")

    return rep_count, set_count, sets


def plot_cycles(ts, cycle_times, cycle_indices, title="Detected Cycles in Z-Axis Data"):
    """
    Plots the Z-axis acceleration and marks cycle start points.

    Parameters:
    - ts: KTK TimeSeries object containing 'Z' data key.
    - cycle_times: List of timestamps where new cycles start.
    - cycle_indices: Indices in the time array where cycles start.
    - title: String, title of the plot.
    """
    time = ts.time
    z_data = ts.data['Z']

    plt.figure(figsize=(12, 6))
    plt.plot(time, z_data, label='Z-Axis Acceleration', color='blue')

    # Mark cycle start points
    plt.scatter(cycle_times, z_data[cycle_indices], color='orange', s=80, label='Cycle Start', zorder=5)
    for t, v in zip(cycle_times, z_data[cycle_indices]):
        plt.annotate(f"{t:.2f}s", (t, v), textcoords="offset points", xytext=(0, 10), ha='center', fontsize=10,
                     color='orange')

    # Add labels and styling
    plt.title(title)
    plt.xlabel('Time (s)')
    plt.ylabel('Acceleration (m/s²)')
    plt.legend()
    plt.grid(True)
    plt.tight_layout()
    plt.show()


# Detect reps and sets based on manually edited events
def label_reps_and_sets(ts_smoothed, original_df, max_rep_duration=3.0):
    import matplotlib
    # Set interactive backend for GUI
    matplotlib.use('Qt5Agg')  # Use Qt5 backend for interactive plotting

    # Prompt user to manually mark rep_start, set_start, and set_end events
    print(
        "Please mark 'rep_start' for each rep, 'set_start' for each set start, and 'set_end' for each set end in the plot.")
    ts_events = ts_smoothed.ui_edit_events(data_keys=['Magnitude'])

    # Convert to DataFrame
    df = ts_events.to_dataframe()
    # Reconstruct Timestamp from original DataFrame
    original_times = original_df['Timestamp']
    df['Timestamp'] = original_times.reindex(df.index, method='nearest')  # Match timestamps by nearest index
    df['Label'] = 'no_rep'
    df['Rep_Number'] = 0
    df['Set_Number'] = 0

    rep_count = 0
    set_count = 0
    set_boundaries = []  # Store (set_num, start_time, end_time) tuples

    # Collect set boundaries
    current_set_start = None
    for event in ts_events.events:
        if event.name == 'set_start':
            current_set_start = event.time
        elif event.name == 'set_end' and current_set_start is not None:
            set_count += 1
            set_boundaries.append((set_count, current_set_start, event.time))
            current_set_start = None  # Reset after pairing

    # Process rep events within set boundaries
    for i, event in enumerate(ts_events.events):
        if event.name == 'rep_start':
            rep_count += 1
            start_time = event.time

            # Find the set this rep belongs to
            current_set = 0
            set_end_time = ts_events.time[-1]  # Default to end if no set boundary
            for set_num, set_start, set_end in set_boundaries:
                if set_start <= start_time < set_end:
                    current_set = set_num
                    set_end_time = set_end
                    break
            if current_set == 0:
                current_set = 1  # Default to Set 1 if no set boundary found

            # End time: earliest of next event, set_end, or max duration
            next_event_time = next((e.time for e in ts_events.events[i + 1:] if e.time > start_time),
                                   ts_events.time[-1])
            end_time = min(start_time + max_rep_duration, set_end_time, next_event_time)

            # Label the rep window
            mask = (df.index >= start_time) & (df.index < end_time)
            df.loc[mask, 'Label'] = 'rep'
            df.loc[mask, 'Rep_Number'] = rep_count
            df.loc[mask, 'Set_Number'] = current_set

    print(f"Detected {rep_count} reps across {set_count if set_count > 0 else 1} sets")
    return df, ts_events, rep_count, set_count

# Plot raw, smoothed, and final rep/set data
def plot_data(ts_raw, ts_smoothed, df):
    plt.figure(figsize=(15, 20))

    # Plot X, Y, Z Acceleration (Raw)
    plt.subplot(4, 1, 1)
    plt.plot(ts_raw.time, ts_raw.data['X'], label='X', color='red')
    plt.plot(ts_raw.time, ts_raw.data['Y'], label='Y', color='green')
    plt.plot(ts_raw.time, ts_raw.data['Z'], label='Z', color='blue')
    plt.title('Raw Accelerometer Data (X, Y, Z)')
    plt.xlabel('Time (s)')
    plt.ylabel('Acceleration (m/s²)')
    plt.legend()
    plt.grid(True)

    # Plot Raw vs Smoothed Magnitude
    plt.subplot(4, 1, 2)
    plt.plot(ts_raw.time, ts_raw.data['Magnitude'], label='Raw Magnitude', color='gray', alpha=0.5)
    plt.plot(ts_smoothed.time, ts_smoothed.data['Magnitude'], label='Smoothed Magnitude', color='purple')
    plt.title('Raw vs Smoothed Magnitude (Before Rep Detection)')
    plt.xlabel('Time (s)')
    plt.ylabel('Magnitude (m/s²)')
    plt.legend()
    plt.grid(True)

    # Plot Smoothed Magnitude with Rep Labels
    plt.subplot(4, 1, 3)
    plt.plot(ts_smoothed.time, ts_smoothed.data['Magnitude'], label='Smoothed Magnitude', color='purple')
    for rep_num in df['Rep_Number'].unique():
        if rep_num > 0:
            subset = df[df['Rep_Number'] == rep_num]
            set_num = subset['Set_Number'].iloc[0]
            plt.scatter(subset.index, subset['Magnitude'], label=f"Set {set_num} Rep {rep_num}", s=10)
    plt.title('Smoothed Magnitude with Rep Labels by Set')
    plt.xlabel('Time (s)')
    plt.ylabel('Magnitude (m/s²)')
    plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
    plt.grid(True)

    # Plot Overlaid Reps per Set
    plt.subplot(4, 1, 4)
    set_numbers = df['Set_Number'].unique()
    colors = ['blue', 'green', 'red', 'orange', 'purple']
    for set_num in set_numbers:
        if set_num > 0:
            set_df = df[df['Set_Number'] == set_num]
            rep_numbers = set_df['Rep_Number'].unique()
            for rep_num in rep_numbers:
                if rep_num > 0:
                    rep_df = set_df[set_df['Rep_Number'] == rep_num]
                    time_normalized = rep_df.index - rep_df.index[0]  # Normalize time to rep start
                    plt.plot(time_normalized, rep_df['Magnitude'], label=f"Set {set_num} Rep {rep_num}",
                             color=colors[set_num % len(colors)], alpha=0.7)
    plt.title('Overlaid Smoothed Magnitude of Reps per Set')
    plt.xlabel('Time (s) from Rep Start')
    plt.ylabel('Magnitude (m/s²)')
    plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
    plt.grid(True)

    plt.tight_layout()
    plt.show()


# Save labeled data to a new CSV
def save_labeled_data(df, output_file):
    # Ensure 'Exercise' column exists; add it if missing with a default value
    if 'Exercise' not in df.columns:
        df['Exercise'] = 'unknown'  # Default value; overridden in main block if set
    labeled_df = df[['Timestamp', 'X', 'Y', 'Z', 'Label', 'Exercise', 'Rep_Number', 'Set_Number']]
    labeled_df.to_csv(output_file, index=False)
    print(f"Labeled data saved to {output_file}")
    for set_num in df['Set_Number'].unique():
        if set_num > 0:
            set_df = df[df['Set_Number'] == set_num]
            rep_numbers = set_df['Rep_Number'].unique()
            print(f"Set {set_num}:")
            for rep_num in rep_numbers:
                if rep_num > 0:
                    rep_data = set_df[set_df['Rep_Number'] == rep_num]
                    num_points = len(rep_data)
                    duration = (rep_data['Timestamp'].iloc[-1] - rep_data['Timestamp'].iloc[0]).total_seconds()
                    print(f"  Rep {rep_num}: {num_points} data points, Duration: {duration:.2f} seconds")

if __name__ == "__main__":
    # Read and process the data
    original_df = read_accelerometer_data(csv_file)
    ts_raw = prepare_timeseries(original_df)

    # Smooth the data
    ts_smoothed = smooth_timeseries(ts_raw, fc=5.0, order=2)


    # Label reps and sets with manual event editing
    while True:
        df, ts_events, rep_count, set_count = label_reps_and_sets(ts_smoothed, original_df)
        # Plot the data
        plot_data(ts_raw, ts_smoothed, df)

        # Ask for confirmation
        response = input(f"Detected {rep_count} reps across {set_count} sets. Save file? (yes/no/reedit): ").lower()
        if response == 'yes':
            output_file = csv_file.replace('.csv', '_labeled.csv')
            save_labeled_data(df, output_file)
            break
        elif response == 'no':
            print("File not saved.")
            break
        elif response == 'reedit':
            print("Re-editing events...")
            ts_smoothed = ts_events  # Use the edited TimeSeries for re-editing
        else:
            print("Invalid input. Please enter 'yes', 'no', or 'reedit'.")

    # # Detect reps and group them into sets
    # rep_count, set_count, sets = count_reps_and_sets(ts_smoothed, min_height=0, min_distance=50, min_prominence=0.8, set_gap_threshold=5.0)
    #
    # # Plot detected cycles (optional)
    # cycle_times, cycle_indices = detect_cycles_peak_based(ts_smoothed, min_height=0, min_distance=50, min_prominence=0.8)
    # plot_cycles(ts_smoothed, cycle_times, cycle_indices, title="Detected Cycles (Peak-Based)")

    # # Final print
    # print(f"\nFinal Summary: {set_count} sets, {rep_count} total reps detected.")
