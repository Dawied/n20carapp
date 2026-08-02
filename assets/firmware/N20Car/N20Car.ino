#include <Arduino.h>

#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>

// --- Pin Definitions ---
// Motor 1 (Left Motor)
constexpr uint8_t M1_IN1 = 0;
constexpr uint8_t M1_IN2 = 1;
constexpr uint8_t M1_PWM = 2;

// Motor 2 (Right Motor)
constexpr uint8_t M2_IN1 = 5;
constexpr uint8_t M2_IN2 = 6;
constexpr uint8_t M2_PWM = 7;

// Standby (might not be needed, try without)
constexpr uint8_t STBY_PIN = 9;

// --- PWM Configuration ---
constexpr uint8_t M1_PWM_CH = 0;
constexpr uint8_t M2_PWM_CH = 1;
constexpr uint32_t PWM_FREQ = 20000; // 20 kHz PWM frequency
constexpr uint8_t PWM_RES = 8;       // 8-bit PWM resolution (0 - 255)

// --- BLE Serial UUIDs ---
#define SERVICE_UUID "0000ffe0-0000-1000-8000-00805f9b34fb"
#define CHARACTERISTIC_UUID "0000ffe1-0000-1000-8000-00805f9b34fb"

// Global Variables
bool deviceConnected = false;
int currentSpeed = 200;

// --- Function Prototypes ---
void driveMotor(uint8_t motor, int speed);
void stopMotors();
void driveForward(int speed);
void driveBackward(int speed);
void driveLeftForward(int speed);
void driveLeftBackward(int speed);
void driveRightForward(int speed);
void driveRightBackward(int speed);
void JoystickDrive(int x, int y, int speed = 50, float steeringStrength = 0.2f);
void _JoystickDrive(int x, int y);
void processCommand(String cmd);
void runMotorTest();

// --- BLE Callbacks ---
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) override {
    deviceConnected = true;
    Serial.println("BLE Client Connected!");
  }

  void onDisconnect(BLEServer *pServer) override {
    deviceConnected = false;
    Serial.println("BLE Client Disconnected!");
    stopMotors();
    BLEDevice::startAdvertising();
  }
};

class MyCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) override {
    std::string rxValue = pCharacteristic->getValue();
    if (rxValue.length() > 0) {
      String cmd = String(rxValue.c_str());
      processCommand(cmd);
    }
  }
};

/**
 * Drive a specified motor with a given speed and direction.
 *
 * @param motor Motor index (1 = Left Motor, 2 = Right Motor)
 * @param speed Speed value from -255 to 255:
 *              > 0: Forward (CW)
 *              < 0: Backward (CCW)
 *              = 0: Stop
 */
void driveMotor(uint8_t motor, int speed) {
  speed = constrain(speed, -255, 255);

  uint8_t in1Pin, in2Pin, pwmChannel;
  if (motor == 1) {
    in1Pin = M1_IN1;
    in2Pin = M1_IN2;
    pwmChannel = M1_PWM_CH;
  } else if (motor == 2) {
    in1Pin = M2_IN1;
    in2Pin = M2_IN2;
    pwmChannel = M2_PWM_CH;
  } else {
    return; // Invalid motor number
  }

  if (speed > 0) {
    digitalWrite(in1Pin, HIGH);
    digitalWrite(in2Pin, LOW);
    ledcWrite(pwmChannel, speed);
  } else if (speed < 0) {
    digitalWrite(in1Pin, LOW);
    digitalWrite(in2Pin, HIGH);
    ledcWrite(pwmChannel, -speed);
  } else {
    digitalWrite(in1Pin, LOW);
    digitalWrite(in2Pin, LOW);
    ledcWrite(pwmChannel, 0);
  }
}

/**
 * Stop both motors immediately.
 */
void stopMotors() {
  driveMotor(1, 0);
  driveMotor(2, 0);
}

/**
 * Drive straight forward.
 * @param speed Speed from 0 to 255
 */
void driveForward(int speed) {
  driveMotor(1, speed);
  driveMotor(2, speed);
}

/**
 * Drive straight backward.
 * @param speed Speed from 0 to 255
 */
void driveBackward(int speed) {
  driveMotor(1, -speed);
  driveMotor(2, -speed);
}

/**
 * Turn left while moving forward.
 */
void driveLeftForward(int speed) {
  driveMotor(1, 0);
  driveMotor(2, speed);
}

/**
 * Turn left while moving backward.
 */
void driveLeftBackward(int speed) {
  driveMotor(1, 0);
  driveMotor(2, -speed);
}

/**
 * Turn right while moving forward.
 */
void driveRightForward(int speed) {
  driveMotor(1, speed);
  driveMotor(2, 0);
}

/**
 * Turn right while moving backward.
 */
void driveRightBackward(int speed) {
  driveMotor(1, -speed);
  driveMotor(2, 0);
}

/**
 * Original threshold-based joystick drive (preserved for reference).
 */
void _JoystickDrive(int x, int y) {
  constexpr int STEADY_SPEED = 50;

  // Deadzone around center
  if (abs(x) < 5 && abs(y) < 5) {
    stopMotors();
    return;
  }

  if (y > 0) {
    if (x < -5) {
      driveLeftForward(STEADY_SPEED);
    } else if (x > 5) {
      driveRightForward(STEADY_SPEED);
    } else {
      driveForward(STEADY_SPEED);
    }
  } else if (y < 0) {
    if (x < -5) {
      driveLeftBackward(STEADY_SPEED);
    } else if (x > 5) {
      driveRightBackward(STEADY_SPEED);
    } else {
      driveBackward(STEADY_SPEED);
    }
  } else {
    if (x < 0) {
      driveLeftForward(STEADY_SPEED);
    } else if (x > 0) {
      driveRightForward(STEADY_SPEED);
    } else {
      stopMotors();
    }
  }
}

/**
 * Translates X and Y joystick direction to motor speeds with configurable speed and steering strength.
 *
 * @param x Steering direction (-50 to 50)
 * @param y Throttle direction (-50 to 50)
 * @param speed Drive speed magnitude (default 50)
 * @param steeringStrength Steering strength factor (default 0.2f)
 */
void JoystickDrive(int x, int y, int speed, float steeringStrength) {
  if (speed <= 0) speed = 50;
  if (steeringStrength <= 0.001f) steeringStrength = 0.2f;

  // Deadzone around center
  if (abs(x) < 4 && abs(y) < 4) {
    stopMotors();
    return;
  }

  // Small steering deadzone near straight North/South axis to prevent accidental drift
  if (abs(x) < 3) {
    x = 0;
  }

  // Calculate direction vector length
  float len = sqrtf((float)(x * x + y * y));
  if (len < 0.001f) {
    stopMotors();
    return;
  }

  // Normalized direction vector (independent of joystick magnitude)
  float nx = (float)x / len;
  float ny = (float)y / len;

  // Apply aggressiveness scaling to X steering component
  float scaled_nx = nx * steeringStrength;

  // Arcade drive direction components
  // In reverse (ny < 0), invert steering component so reverse left/right matches driveLeftBackward & driveRightBackward
  float rawLeft  = (ny < 0) ? (ny - scaled_nx) : (ny + scaled_nx);
  float rawRight = (ny < 0) ? (ny + scaled_nx) : (ny - scaled_nx);

  // Scale so the faster motor runs at target speed
  float maxMag = max(fabsf(rawLeft), fabsf(rawRight));
  if (maxMag < 0.001f) {
    stopMotors();
    return;
  }

  int leftSpeed = (int)roundf((rawLeft / maxMag) * speed);
  int rightSpeed = (int)roundf((rawRight / maxMag) * speed);

  // Motor 1 = Left Motor, Motor 2 = Right Motor
  driveMotor(1, leftSpeed);
  driveMotor(2, rightSpeed);
}

/**
 * Process received command string (via BLE or Serial).
 * Commands are formatted as comma-separated values, e.g. "joystick,x,y,speed,steeringStrength".
 */
unsigned long lastRxTime = 0;

void processCommand(String cmd) {
  lastRxTime = millis();
  cmd.trim();
  if (cmd.length() == 0)
    return;

  int firstComma = cmd.indexOf(',');
  String action = (firstComma == -1) ? cmd : cmd.substring(0, firstComma);
  action.trim();
  action.toLowerCase();

  if (action == "joystick") {
    int x = 0;
    int y = 0;
    int speed = 50;
    float steeringStrength = 0.2f;

    if (firstComma != -1) {
      int secondComma = cmd.indexOf(',', firstComma + 1);
      if (secondComma != -1) {
        x = cmd.substring(firstComma + 1, secondComma).toInt();
        int thirdComma = cmd.indexOf(',', secondComma + 1);
        if (thirdComma != -1) {
          y = cmd.substring(secondComma + 1, thirdComma).toInt();
          int fourthComma = cmd.indexOf(',', thirdComma + 1);
          if (fourthComma != -1) {
            speed = cmd.substring(thirdComma + 1, fourthComma).toInt();
            steeringStrength = cmd.substring(fourthComma + 1).toFloat();
          } else {
            speed = cmd.substring(thirdComma + 1).toInt();
          }
        } else {
          y = cmd.substring(secondComma + 1).toInt();
        }
      } else {
        x = cmd.substring(firstComma + 1).toInt();
      }
    }

    Serial.print("Command: ");
    Serial.print(action);
    Serial.print(" -> X: ");
    Serial.print(x);
    Serial.print(", Y: ");
    Serial.print(y);
    Serial.print(", Speed: ");
    Serial.print(speed);
    Serial.print(", Steering: ");
    Serial.println(steeringStrength);

    JoystickDrive(x, y, speed, steeringStrength);
  }
}

void setup() {
  Serial.begin(115200);
  Serial.setTimeout(50);
  unsigned long start = millis();
  while (!Serial && (millis() - start < 2000)) {
    delay(10);
  }

  // Motor pin modes
  pinMode(M1_IN1, OUTPUT);
  pinMode(M1_IN2, OUTPUT);
  pinMode(M2_IN1, OUTPUT);
  pinMode(M2_IN2, OUTPUT);

  // Enable standby pin
  pinMode(STBY_PIN, OUTPUT);
  digitalWrite(STBY_PIN, HIGH);

  // Configure ESP32 LEDC PWM
  ledcSetup(M1_PWM_CH, PWM_FREQ, PWM_RES);
  ledcAttachPin(M1_PWM, M1_PWM_CH);

  ledcSetup(M2_PWM_CH, PWM_FREQ, PWM_RES);
  ledcAttachPin(M2_PWM, M2_PWM_CH);

  Serial.println("Motor control initialized.");

  // Initialize BLE
  BLEDevice::init("N20 Car");
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  BLECharacteristic *pCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID, BLECharacteristic::PROPERTY_READ |
                               BLECharacteristic::PROPERTY_WRITE |
                               BLECharacteristic::PROPERTY_WRITE_NR |
                               BLECharacteristic::PROPERTY_NOTIFY);

  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("BLE Bluetooth initialized. Advertising as 'N20 Car'.");
}

void loop() {
  if (Serial.available()) {
    String serialCmd = Serial.readStringUntil('\n');
    processCommand(serialCmd);
  }

  // Safety Watchdog: If connected but no command received for 800ms, auto-stop motors
  if (deviceConnected && lastRxTime > 0 && (millis() - lastRxTime > 800)) {
    stopMotors();
  }

  delay(10);
}

/**
 * Runs a test sequence demonstrating all movement functions.
 */
void runMotorTest() {
  int testSpeed = 150;
  int runTime = 2000;
  int pauseTime = 1000;

  Serial.println("--- 1. Drive Straight Forward ---");
  driveForward(testSpeed);
  delay(runTime);
  stopMotors();
  delay(pauseTime);

  Serial.println("--- 2. Drive Straight Backward ---");
  driveBackward(testSpeed);
  delay(runTime);
  stopMotors();
  delay(pauseTime);

  Serial.println("--- 3. Turn Left Forward ---");
  driveLeftForward(testSpeed);
  delay(runTime);
  stopMotors();
  delay(pauseTime);

  Serial.println("--- 4. Turn Left Backward ---");
  driveLeftBackward(testSpeed);
  delay(runTime);
  stopMotors();
  delay(pauseTime);

  Serial.println("--- 5. Turn Right Forward ---");
  driveRightForward(testSpeed);
  delay(runTime);
  stopMotors();
  delay(pauseTime);

  Serial.println("--- 6. Turn Right Backward ---");
  driveRightBackward(testSpeed);
  delay(runTime);
  stopMotors();
  delay(pauseTime);
}
