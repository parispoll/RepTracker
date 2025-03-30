import pandas as pd

# Path to the original CSV file
csv_file = "C:/Users/paris/imu_visualizer/dataAnalysis/data/bicepCurl3_2025-03-30T13-27-03.419471.csv"

# Read CSV while keeping the headers
df = pd.read_csv(csv_file)

# Remove the first row (excluding headers)
df = df.iloc[1:]

# Save the modified CSV with the correct headers
fixed_file = csv_file.replace('.csv', '_fixed.csv')
df.to_csv(fixed_file, index=False)

print(f"✅ First row removed. New CSV saved as: {fixed_file}")
