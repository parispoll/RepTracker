import asyncio
import sys
import requests
import argparse
from datetime import datetime
from bleak import BleakClient, BleakScanner

# Edge Impulse API settings
API_KEY = "ei_a0bb646faa68dd8fcd5b57a33dc11f9ee85ae9283cb82a66ef855477e05b7e2c"  # Replace with your full API key
PROJECT_ID = "149805"  # Replace with your project ID
INGESTION_URL = "https://ingestion.edgeimpulse.com/api/training/data"

# BLE UUIDs
SERVICE_UUID = "19B10000-E8F2-537E-4F6C-D104768A1214"
CHARACTERISTIC_UUID = "19B10001-E8F2-537E-4F6C-D104768A1214"

# Data collection settings
SAMPLE_DURATION_MS = 20000  # 10 seconds
SAMPLE_RATE_HZ = 50  # 50 Hz
SAMPLES_PER_REQUEST = SAMPLE_DURATION_MS // (1000 // SAMPLE_RATE_HZ)  # 500 samples (10 seconds at 50 Hz)

# Global list to store data points
data_buffer = []
sample_count = 0

# Parse command-line arguments for the label
parser = argparse.ArgumentParser(description="BLE receiver for Edge Impulse")
parser.add_argument("--label", default="unknown", help="Label for the data (e.g., Squat)")
args = parser.parse_args()
LABEL = args.label

# Callback function to handle incoming BLE notifications
def notification_handler(sender, data):
    global data_buffer, sample_count

    try:
        data_str = data.decode("utf-8").strip()
        values = data_str.split(",")
        if len(values) == 3:
            # Add the data point to the buffer
            data_buffer.append([float(values[0]), float(values[1]), float(values[2])])
            sample_count += 1

            # If we've collected enough samples, send to Edge Impulse
            if sample_count >= SAMPLES_PER_REQUEST:
                send_to_edge_impulse()
                # Reset the buffer and counter
                data_buffer.clear()
                sample_count = 0

    except Exception as e:
        print(f"Error decoding data: {e}", file=sys.stderr)

def send_to_edge_impulse():
    if not data_buffer:
        return

    # Generate a unique filename for this sample
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"{LABEL}_{timestamp}.json"

    # Prepare the data for Edge Impulse
    payload = {
        "protected": {
            "ver": "v1",
            "alg": "none"
        },
        "signature": "0".zfill(64),  # Dummy signature
        "payload": {
            "device_name": "Nano33BLE",
            "device_type": "Arduino Nano 33 BLE Sense",
            "interval_ms": 1000 // SAMPLE_RATE_HZ,  # 20 ms (50 Hz)
            "sensors": [
                {"name": "accX", "units": "m/s2"},
                {"name": "accY", "units": "m/s2"},
                {"name": "accZ", "units": "m/s2"}
            ],
            "values": data_buffer
        }
    }

    # Send to Edge Impulse with the required headers
    headers = {
        "x-api-key": API_KEY,
        "x-file-name": filename,
        "x-label": LABEL
    }
    response = requests.post(INGESTION_URL, json=payload, headers=headers)
    if response.status_code == 200:
        print(f"Sent sample: {filename} with label {LABEL}", file=sys.stderr)
    else:
        print(f"Failed to send: {response.text}", file=sys.stderr)

async def main():
    print("Scanning for Nano33BLE...", file=sys.stderr)
    devices = await BleakScanner.discover()
    target_device = None
    for device in devices:
        if device.name == "Nano33BLE":
            target_device = device
            break

    if not target_device:
        print("Could not find Nano33BLE device", file=sys.stderr)
        sys.exit(1)

    print(f"Found Nano33BLE at {target_device.address}", file=sys.stderr)

    async with BleakClient(target_device.address) as client:
        print("Connected to Nano33BLE", file=sys.stderr)
        await client.start_notify(CHARACTERISTIC_UUID, notification_handler)
        print("Subscribed to accelerometer data", file=sys.stderr)

        while True:
            await asyncio.sleep(1)

if __name__ == "__main__":
    asyncio.run(main())