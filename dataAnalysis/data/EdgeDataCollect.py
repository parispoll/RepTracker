import asyncio
import sys
from bleak import BleakClient, BleakScanner

# BLE UUIDs (same as in the Arduino sketch)
SERVICE_UUID = "19B10000-E8F2-537E-4F6C-D104768A1214"
CHARACTERISTIC_UUID = "19B10001-E8F2-537E-4F6C-D104768A1214"


# Callback function to handle incoming BLE notifications
def notification_handler(sender, data):
    # Decode the received data (it's a string like "x,y,z")
    data_str = data.decode("utf-8")
    print(data_str)  # Print to stdout (this will be piped to edge-impulse-data-forwarder)


async def main():
    # Scan for the Arduino device
    print("Scanning for Nano33BLE...")
    devices = await BleakScanner.discover()
    target_device = None
    for device in devices:
        if device.name == "Nano33BLE":
            target_device = device
            break

    if not target_device:
        print("Could not find Nano33BLE device")
        sys.exit(1)

    print(f"Found Nano33BLE at {target_device.address}")

    # Connect to the device
    async with BleakClient(target_device.address) as client:
        print("Connected to Nano33BLE")

        # Start notifications for the characteristic
        await client.start_notify(CHARACTERISTIC_UUID, notification_handler)
        print("Subscribed to accelerometer data")

        # Keep the connection alive indefinitely (stop with Ctrl+C)
        while True:
            await asyncio.sleep(1)


# Run the script
if __name__ == "__main__":
    asyncio.run(main())