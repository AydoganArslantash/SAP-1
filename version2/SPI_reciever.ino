#include <SPI.h>
#include <LedControl.h>

// Pin definitions for MAX7219 displays
#define DIN_PIN 9
#define CLK_PIN 8
#define CS_PIN 7
#define NUM_DEVICES 5

// Initialize LedControl object for MAX7219 displays
LedControl lc = LedControl(DIN_PIN, CLK_PIN, CS_PIN, NUM_DEVICES);

// Variables for SPI communication
volatile uint8_t data_buffer[5];  // Buffer to store the 5-byte frame
volatile uint8_t buffer_index = 0;  // Index for buffer position
volatile bool new_data = false;     // Flag for new complete frame

// Variables to hold parsed SAP-1 register values
uint8_t reg_a, reg_b, adder_out, pc_out, stage;

void setup() {
  // Initialize Serial communication
  Serial.begin(9600);
  Serial.println("Starting setup...");

  // Initialize each MAX7219 display
  for (int i = 0; i < NUM_DEVICES; i++) {
    lc.shutdown(i, false);       // Wake up display
    lc.setIntensity(i, 4);       // Set brightness (0-15)
    lc.clearDisplay(i);          // Clear display
    lc.setChar(i, 0x0F, 0, false);  // Disable test mode
    lc.setScanLimit(i, 3);       // Use 4 digits (0-3)
    Serial.print("Initialized device ");
    Serial.println(i);
  }

  // Configure SPI as slave
  pinMode(MISO, OUTPUT);           // Set MISO as output for SPI slave
  SPCR = (1 << SPE) | (1 << SPIE); // Enable SPI and SPI interrupts
  Serial.print("SPCR: 0x");
  Serial.println(SPCR, HEX);
  Serial.println("SPI slave initialized");
}

// SPI Interrupt Service Routine
ISR(SPI_STC_vect) {
  uint8_t data = SPDR;              // Read received byte
  data_buffer[buffer_index] = data; // Store in buffer
  buffer_index++;
  if (buffer_index >= 5) {          // Full frame received
    buffer_index = 0;
    new_data = true;
  }
  SPDR = 0;                         // Set SPDR to 0 for next transfer
}

void loop() {
  if (new_data) {
    // Parse the received frame
//    reg_a = data_buffer[0];
//    reg_b = data_buffer[1];
//    adder_out = data_buffer[2];
//    pc_out = data_buffer[3];
//    stage = data_buffer[4] & 0x07;  // Mask to get lower 3 bits for stage

    reg_a = data_buffer[0];
    reg_b = data_buffer[1];
    adder_out = data_buffer[2];
    pc_out = data_buffer[3] & 0x0F;    // Lower 4 bits of byte 3
    stage = data_buffer[4] & 0x07;     // Lower 3 bits of byte 4

    

    // Display raw buffer on Serial Monitor
    Serial.print("Buffer: ");
    for (int i = 0; i < 5; i++) {
      Serial.print(data_buffer[i], HEX);
      Serial.print(" ");
    }
    Serial.println();

    // Display parsed values on Serial Monitor
    Serial.print("Parsed: A=");
    Serial.print(reg_a, HEX);
    Serial.print(" B=");
    Serial.print(reg_b, HEX);
    Serial.print(" Add=");
    Serial.print(adder_out, HEX);
    Serial.print(" PC=");
    Serial.print(pc_out, HEX);
    Serial.print(" Stage=");
    Serial.println(stage, HEX);

    // Display values on MAX7219 displays
    displayNumber(0, reg_a);
    displayNumber(1, reg_b);
    displayNumber(2, adder_out);
    displayNumber(3, pc_out);
    displayNumber(4, stage);

    new_data = false;  // Reset flag
  }
}

//void displayNumber(uint8_t device, uint8_t hexValue) {
//    uint8_t decimal = hexValue; // Directly display hex as decimal (e.g., 0x1E → 30)
//    lc.setDigit(device, 0, (decimal / 1000) % 10, false);
//    lc.setDigit(device, 1, (decimal / 100) % 10, false);
//    lc.setDigit(device, 2, (decimal / 10) % 10, false);
//    lc.setDigit(device, 3, decimal % 10, false);
//}

// Function to display a number on a specific MAX7219 device
void displayNumber(uint8_t device, uint16_t number) {
  Serial.print("Displaying on device ");
  Serial.print(device);
  Serial.print(": ");
  Serial.println(number);
  lc.setDigit(device, 0, (number / 1000) % 10, false); // Thousands
  lc.setDigit(device, 1, (number / 100) % 10, false);  // Hundreds
  lc.setDigit(device, 2, (number / 10) % 10, false);   // Tens
  lc.setDigit(device, 3, number % 10, false);          // Units
}
