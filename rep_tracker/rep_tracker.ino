#include <ArduinoBLE.h>
#include <Arduino_BMI270_BMM150.h>
#include <Exercice_clasifier_inferencing.h>

BLEService accelerometerService("19B10000-E8F2-537E-4F6C-D104768A1214");
BLEStringCharacteristic accelerometerDataChar("19B10001-E8F2-537E-4F6C-D104768A1214", BLERead | BLENotify, 50);

float features[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE];
size_t feature_ix = 0;

int get_features_from_signal(void *ptr, float *buf, size_t len) {
  float *features = static_cast<float*>(ptr);
  for (size_t i = 0; i < len; i++) {
    buf[i] = features[i];
  }
  return 0;
}

void setup() {
  Serial.begin(115200);
  //while (!Serial);

  if (!BLE.begin()) {
    Serial.println("Starting BLE failed!");
    while (1);
  }

  if (!IMU.begin()) {
    Serial.println("Failed to initialize IMU!");
    while (1);
  }

  Serial.print("Expected frame size: ");
  Serial.println(EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE);
  if (EI_CLASSIFIER_RAW_SAMPLES_PER_FRAME != 3) {
    Serial.println("ERR: EI_CLASSIFIER_RAW_SAMPLES_PER_FRAME should be 3 (x, y, z)");
    while (1);
  }

  BLE.setLocalName("Nano33BLE");
  BLE.setAdvertisedService(accelerometerService);
  accelerometerService.addCharacteristic(accelerometerDataChar);
  BLE.addService(accelerometerService);
  BLE.advertise();
  Serial.println("BLE started, waiting for connections...");
}

void loop() {
  BLE.poll();

  BLEDevice central = BLE.central();
  if (central) {
    Serial.println("Connected to central: " + central.address());
    while (central.connected()) {
      float x, y, z;
      if (IMU.accelerationAvailable()) {
        IMU.readAcceleration(x, y, z);

        // Change the sign of the accelerometer data
        x = -x;
        y = -y;
        z = -z;

        // Convert from g to m/s² (1 g = 9.81 m/s²)
        x *= 9.81;
        y *= 9.81;
        z *= 9.81;

        // Add the latest sample to the features buffer
        features[feature_ix * EI_CLASSIFIER_RAW_SAMPLES_PER_FRAME + 0] = x;
        features[feature_ix * EI_CLASSIFIER_RAW_SAMPLES_PER_FRAME + 1] = y;
        features[feature_ix * EI_CLASSIFIER_RAW_SAMPLES_PER_FRAME + 2] = z;
        feature_ix++;

        if (feature_ix >= 1 || (feature_ix >= (EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE / EI_CLASSIFIER_RAW_SAMPLES_PER_FRAME))) {
          ei::signal_t signal;
          signal.total_length = EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE;
          signal.get_data = [&features](size_t offset, size_t length, float *out_ptr) {
            return get_features_from_signal(features, out_ptr, length);
          };

          String exercise = classifyExercise(&signal);

          char data[50];
          snprintf(data, sizeof(data), "%.2f,%.2f,%.2f,exercise:%s", x, y, z, exercise.c_str());
          if (accelerometerDataChar.writeValue(data)) {
            Serial.println("Sent: " + String(data));
          } else {
            Serial.println("Failed to send data");
          }

          feature_ix = 0;
        }
      }
      delay(20); // 50 Hz
    }
    Serial.println("Disconnected from central");
  }
}

String classifyExercise(ei::signal_t *signal) {
  ei_impulse_result_t result = {0};

  EI_IMPULSE_ERROR res = run_classifier(signal, &result, true);
  if (res != EI_IMPULSE_OK) {
    Serial.println("Failed to run classifier: " + String(res));
    return "Unknown";
  }

  float maxConfidence = 0.0;
  String predictedLabel = "Unknown";
  for (uint16_t i = 0; i < EI_CLASSIFIER_LABEL_COUNT; i++) {
    float confidence = result.classification[i].value;
    String label = String(result.classification[i].label);
    Serial.print("Label: ");
    Serial.print(label);
    Serial.print(", Confidence: ");
    Serial.println(confidence);
    if (confidence > maxConfidence) {
      maxConfidence = confidence;
      predictedLabel = label;
    }
  }

  const float confidenceThreshold = 0.5;
  if (maxConfidence < confidenceThreshold) {
    return "Unknown";
  }

  if (predictedLabel == "BarbellRow") return "BarbellRows";
  else if (predictedLabel == "BicepCurl") return "BicepCurl";
  else if (predictedLabel == "Idle") return "Idle";
  else if (predictedLabel == "Deadlift") return "Deadlift";
  else if (predictedLabel == "Squat") return "Squat";
  else return "Unknown";
}