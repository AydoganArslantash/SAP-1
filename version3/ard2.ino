#include <SPI.h>
#include <LedControl.h>
#include "pitches.h"

// Pin definitions for MAX7219 displays
#define DIN_PIN 9
#define CLK_PIN 8
#define CS_PIN 7
#define NUM_DEVICES 5  // Five daisy-chained displays for reg_a, reg_b, accumulator, pc_out, phase

// Buzzer pin definition
#define BUZZER_PIN 4

// LED pin definitions for sap1_overflow and sap1_underflow
#define sap1_overflow_LED_PIN 5
#define sap1_underflow_LED_PIN 6

// SPI SS pin for Arduino Mega (hardware SPI slave select)
#define SS_PIN 53  // Mega SPI SS pin (not 10)

// Initialize LedControl object for MAX7219 displays
LedControl lc = LedControl(DIN_PIN, CLK_PIN, CS_PIN, NUM_DEVICES);

// Variables for SPI communication
volatile uint8_t data_buffer[5]; // Back to 5 bytes
volatile uint8_t buffer_index = 0;
volatile bool new_data = false;

// Variables to hold parsed SAP-1 register values
uint8_t reg_a, reg_b, accumulator, pc_out, phase;
uint8_t sng_en, opcode, alu_sub; // Added alu_sub
uint8_t sap1_overflow, sap1_underflow;

// Previous sng_en state for edge detection
uint8_t prev_sng_en = 0;

// Melody definitions (unchanged, omitted for brevity)
// Melody 0: Simple melody to signify operation finished
const int melody0[][2] = {
  {NOTE_C4, 500}, {NOTE_E4, 500}, {NOTE_G4, 500}, {NOTE_C5, 500}
};
const int melody0_length = 4;

// Melody 1: istiklalMelody
const int melody1[][2] = {
  {NOTE_C4, 400}, {NOTE_D4, 400}, {NOTE_E4, 400}, {NOTE_C4, 400}, 
  {NOTE_C4, 400}, {NOTE_D4, 400}, {NOTE_E4, 400}, {NOTE_C4, 800},
  {NOTE_E4, 400}, {NOTE_F4, 400}, {NOTE_G4, 400}, {NOTE_E4, 400}, 
  {NOTE_F4, 400}, {NOTE_G4, 400}, {NOTE_G4, 800}, {NOTE_A4, 400},
  {NOTE_G4, 400}, {NOTE_E4, 400}, {NOTE_E4, 400}, {NOTE_F4, 400}, 
  {NOTE_E4, 400}, {NOTE_D4, 400}, {NOTE_C4, 400}, {NOTE_C4, 400},
  {NOTE_E4, 400}, {NOTE_D4, 400}, {NOTE_C4, 800}
};
const int melody1_length = 27;

// Melody 2: Long melody
const int melody2[] = {
  NOTE_G4, NOTE_C5, NOTE_G4, NOTE_A4, NOTE_B4, NOTE_E4, NOTE_E4, 
  NOTE_A4, NOTE_G4, NOTE_F4, NOTE_G4, NOTE_C4, NOTE_C4, 
  NOTE_D4, NOTE_D4, NOTE_E4, NOTE_F4, NOTE_F4, NOTE_G4, NOTE_A4, NOTE_B4, NOTE_C5, NOTE_D5, 
  NOTE_E5, NOTE_D5, NOTE_C5, NOTE_D5, NOTE_B4, NOTE_G4, 
  NOTE_C5, NOTE_B4, NOTE_A4, NOTE_B4, NOTE_E4, NOTE_E4, 
  NOTE_A4, NOTE_G4, NOTE_F4, NOTE_G4, NOTE_C4, NOTE_C4, 
  NOTE_C5, NOTE_B4, NOTE_A4, NOTE_G4, NOTE_B4, NOTE_C5, NOTE_D5, 
  NOTE_E5, NOTE_D5, NOTE_C5, NOTE_B4, NOTE_C5, NOTE_D5, NOTE_G4, NOTE_G4, NOTE_B4, NOTE_C5, NOTE_D5,
  NOTE_C5, NOTE_B4, NOTE_A4, NOTE_G4, NOTE_A4, NOTE_B4, NOTE_E4, NOTE_E4, NOTE_G4, NOTE_A4, NOTE_B4,
  NOTE_C5, NOTE_A4, NOTE_B4, NOTE_C5, NOTE_A4, NOTE_B4, NOTE_C5, NOTE_A4, NOTE_C5, NOTE_F5,
  NOTE_F5, NOTE_E5, NOTE_D5, NOTE_C5, NOTE_D5, NOTE_E5, NOTE_C5, NOTE_C5,
  NOTE_D5, NOTE_C5, NOTE_B4, NOTE_A4, NOTE_B4, NOTE_C5, NOTE_A4, NOTE_A4,
  NOTE_C5, NOTE_B4, NOTE_A4, NOTE_G4, NOTE_C4, NOTE_G4, NOTE_A4, NOTE_B4, NOTE_C5
};
const int noteDurations2[] = {
  8, 4, 6, 16, 4, 8, 8, 
  4, 6, 16, 4, 8, 8, 
  4, 8, 8, 4, 8, 8, 4, 8, 8, 2,
  4, 6, 16, 4, 8, 8, 
  4, 6, 16, 4, 8, 8, 
  4, 6, 16, 4, 6, 16, 
  4, 6, 16, 8, 8, 8, 8, 
  2, 8, 8, 8, 8, 3, 8, 8, 8, 8, 8,
  2, 8, 8, 8, 8, 3, 8, 8, 8, 8, 8,
  4, 6, 16, 4, 6, 16, 4, 8, 8, 2,
  2, 8, 8, 8, 8, 3, 8, 2,
  2, 8, 8, 8, 8, 3, 8, 2,
  4, 6, 16, 4, 4, 2, 4, 4, 1
};
const int melody2_length = sizeof(melody2) / sizeof(melody2[0]);

// Melody 3: Daisy Bell
const int melody3[][2] = {
  {NOTE_D5, 600},   {NOTE_B4, 600},   {NOTE_G4, 600},   {NOTE_D4, 600},
  {NOTE_E4, 200},   {NOTE_FS4, 200}, {NOTE_G4, 200},   {NOTE_E4, 400},
  {NOTE_G4, 200},   {NOTE_D4, 1600},  {NOTE_A4, 600},   {NOTE_D5, 600},
  {NOTE_B4, 600},   {NOTE_G4, 600},   {NOTE_E4, 200},   {NOTE_FS4, 200},
  {NOTE_G4, 200},   {NOTE_A4, 400},   {NOTE_B4, 200},   {NOTE_A4, 1600},
  {NOTE_B4, 200},   {NOTE_C5, 200},   {NOTE_B4, 200},   {NOTE_A4, 200},
  {NOTE_D5, 400},   {NOTE_B4, 200},   {NOTE_A4, 200},   {NOTE_G4, 800},
  {NOTE_A4, 200},   {NOTE_B4, 400},   {NOTE_G4, 200},   {NOTE_E4, 400},
  {NOTE_G4, 200},   {NOTE_E4, 200},   {NOTE_D4, 1200},  {NOTE_D4, 200},
  {NOTE_G4, 400},   {NOTE_B4, 200},   {NOTE_A4, 400},   {NOTE_G4, 400},
  {NOTE_B4, 200},   {NOTE_A4, 200},   {NOTE_B4, 200},   {NOTE_C5, 200},
  {NOTE_D5, 200},   {NOTE_B4, 200},   {NOTE_G4, 200},   {NOTE_A4, 400},
  {NOTE_D4, 200},   {NOTE_G4, 1200}
};
const int melody3_length = 50;

// Melody 4: Oppenheimer - Can You Hear the Music (Adjusted to 142 BPM)
const int melody4[][2] = {
  {NOTE_B4, 552}, {NOTE_C5, 552}, {NOTE_D5, 552}, {NOTE_F5, 552},
  {NOTE_G5, 552}, {NOTE_E5, 552}, {NOTE_C5, 552}, {NOTE_D5, 552},
  {NOTE_E5, 552}, {NOTE_G5, 552}, {NOTE_B5, 552}, {NOTE_F5, 552},
  {NOTE_D5, 552}, {NOTE_E5, 552}, {NOTE_F5, 552}, {NOTE_B5, 552},
  {NOTE_C6, 552}, {NOTE_G5, 552}, {NOTE_E5, 552}, {NOTE_F5, 552},
  {NOTE_G5, 552}, {NOTE_C6, 552}, {NOTE_D6, 552}, {NOTE_B5, 552},
  {NOTE_F5, 552}, {NOTE_G5, 552}, {NOTE_B5, 552}, {NOTE_D6, 552},
  {NOTE_E6, 552}, {NOTE_C6, 552}, {NOTE_B5, 552}, {NOTE_C6, 552},
  {NOTE_D6, 552}, {NOTE_F6, 552}, {NOTE_G6, 552}, {NOTE_E6, 552},
  {NOTE_C6, 552}, {NOTE_D6, 552}, {NOTE_E6, 552}, {NOTE_G6, 552},
  {NOTE_B6, 552}, {NOTE_F6, 552}, {NOTE_D6, 552}, {NOTE_E6, 552},
  {NOTE_F6, 552}, {NOTE_B6, 552}, {NOTE_C7, 552}, {NOTE_G6, 552},
  {NOTE_C6, 362}, {NOTE_D6, 374}, {NOTE_B6, 371}, {NOTE_F6, 362},
  {NOTE_E6, 374}, {NOTE_G6, 371}, {NOTE_B5, 362}, {NOTE_C6, 374},
  {NOTE_D6, 371}, {NOTE_E6, 362}, {NOTE_D6, 374}, {NOTE_F6, 371},
  {NOTE_G5, 362}, {NOTE_G6, 374}, {NOTE_C6, 371}, {NOTE_D6, 362},
  {NOTE_C6, 374}, {NOTE_E6, 371}, {NOTE_F5, 362}, {NOTE_G5, 374},
  {NOTE_B5, 371}, {NOTE_C6, 362}, {NOTE_B5, 374}, {NOTE_D6, 371},
  {NOTE_F6, 362}, {NOTE_E6, 374}, {NOTE_G5, 371}, {NOTE_B5, 362},
  {NOTE_G5, 374}, {NOTE_C6, 371}, {NOTE_F5, 362}, {NOTE_E5, 374},
  {NOTE_F5, 371}, {NOTE_G5, 362}, {NOTE_F5, 374}, {NOTE_B5, 371},
  {NOTE_D6, 362}, {NOTE_D5, 374}, {NOTE_E5, 371}, {NOTE_F5, 362},
  {NOTE_E5, 374}, {NOTE_G5, 371}, {NOTE_D5, 362}, {NOTE_C5, 374},
  {NOTE_D5, 371}, {NOTE_E5, 362}, {NOTE_D5, 374}, {NOTE_C5, 371},
  {NOTE_B4, 552}, {NOTE_C5, 552}, {NOTE_D5, 552}, {NOTE_F5, 552}
};
const int melody4_length = 96;


// Papers, Please - Main Theme
const int melody5[90][2] = {
    // Intro: Repeated D4, somber and steady
    {NOTE_D4, 1000}, {NOTE_D4, 1000}, {NOTE_D4, 1000}, {NOTE_D4, 1000}, {NOTE_D4, 100},
    {0, 1000}, {0, 1000}, {0, 1000}, {0, 1000}, // Silence for pacing

    // Phrase 1: A3 motif, grounding the melody
    {NOTE_A3, 1000}, {NOTE_A3, 1000}, {NOTE_A3, 1000}, {NOTE_A3, 500}, {0, 1000},
    {0, 1000}, {0, 1000}, {NOTE_D4, 1000}, {NOTE_D4, 1000}, {NOTE_D4, 1000},
    {NOTE_D4, 500}, {0, 1000}, {0, 1000}, {0, 1000},

    // Phrase 2: D5 escalation, building tension
    {NOTE_A3, 250}, {NOTE_D5, 1000}, {NOTE_D5, 1000}, {NOTE_D5, 1000}, {NOTE_D5, 500},
    {NOTE_D4, 100}, {0, 1000}, {0, 1000}, {0, 1000}, {NOTE_A3, 1000},
    {NOTE_A3, 1000}, {NOTE_A3, 500}, {0, 1000}, {0, 1000}, {NOTE_D4, 1000},
    {NOTE_D4, 1000}, {NOTE_D4, 500}, {0, 1000},

    // Phrase 3: F5 introduction, rising intensity
    {NOTE_A3, 250}, {NOTE_D5, 1000}, {NOTE_D5, 1000}, {NOTE_D5, 1000}, {NOTE_D5, 500},
    {NOTE_D4, 100}, {0, 1000}, {0, 1000}, {NOTE_F5, 1000}, {NOTE_F5, 1000},
    {NOTE_F5, 500}, {NOTE_A3, 100}, {0, 1000}, {0, 1000},

    // Phrase 4: A5 and D6, emotional peak
    {NOTE_A5, 1000}, {NOTE_A5, 1000}, {NOTE_A5, 1000}, {NOTE_A5, 500}, {NOTE_D4, 100},
    {0, 1000}, {0, 1000}, {0, 1000}, {NOTE_D6, 1000}, {NOTE_D6, 1000},
    {NOTE_D6, 1000}, {NOTE_D6, 500}, {NOTE_A3, 100}, {0, 1000}, {0, 1000},

    // Phrase 5: G6 climax, resolving to F4
    {NOTE_G6, 1000}, {NOTE_G6, 1000}, {NOTE_G6, 1000}, {NOTE_G6, 500}, {0, 100},
    {NOTE_F4, 1000}, {NOTE_F4, 1000}, {NOTE_F4, 1000}, {NOTE_F4, 1000}, {NOTE_F4, 100},
    {0, 1000}, {0, 1000}, {0, 1000}, {0, 1000}, // Fade out
    {NOTE_D4, 1000}, {NOTE_D4, 1000}, {NOTE_D4, 500}, {0, 1000} // Final cadence
};
const int melody5_length = 90;

void setup() {
    Serial.begin(9600);
    Serial.println("Starting setup...");
    for (int i = 0; i < NUM_DEVICES; i++) {
        lc.shutdown(i, false);
        lc.setIntensity(i, 4);
        lc.clearDisplay(i);
        lc.setScanLimit(i, 1);
        Serial.print("Initialized device ");
        Serial.println(i);
    }
    pinMode(MISO, OUTPUT);
    pinMode(SS_PIN, INPUT);
    SPCR = (1 << SPE) | (1 << SPIE);
    Serial.print("SPCR: 0x");
    Serial.println(SPCR, HEX);
    Serial.println("SPI slave initialized");
    pinMode(BUZZER_PIN, OUTPUT);
    pinMode(sap1_overflow_LED_PIN, OUTPUT);
    pinMode(sap1_underflow_LED_PIN, OUTPUT);
    digitalWrite(sap1_overflow_LED_PIN, LOW);
    digitalWrite(sap1_underflow_LED_PIN, LOW);
}
ISR(SPI_STC_vect) {
    if (digitalRead(SS_PIN) == HIGH && buffer_index > 0) {
        buffer_index = 0;
    }
    uint8_t data = SPDR;
    if (buffer_index < 5) {
        data_buffer[buffer_index] = data;
        buffer_index++;
        if (buffer_index == 5) {
            new_data = true;
            buffer_index = 0;
        }
    }
    SPDR = 0;
}
void loop() {
    if (new_data) {
        reg_a = data_buffer[0];
        reg_b = data_buffer[1];
        accumulator = data_buffer[2];
        pc_out = data_buffer[3] & 0x0F;
        sap1_overflow = (data_buffer[3] >> 5) & 0x01;
        sap1_underflow = (data_buffer[3] >> 4) & 0x01;
        uint8_t byte4 = data_buffer[4];
        sng_en = (byte4 >> 7) & 0x01;
        opcode = (byte4 >> 3) & 0x0F;
        phase = byte4 & 0x07;
        digitalWrite(sap1_overflow_LED_PIN, sap1_overflow);
        digitalWrite(sap1_underflow_LED_PIN, sap1_underflow);
        Serial.print("A=");
        Serial.print(reg_a, HEX);
        Serial.print(" B=");
        Serial.print(reg_b, HEX);
        Serial.print(" Acc=");
        Serial.print(accumulator, HEX);
        Serial.print(" PC=");
        Serial.print(pc_out, HEX);
        Serial.print(" Stage=");
        Serial.print(phase, HEX);
        Serial.print(" Opcode=");
        Serial.print(opcode, HEX);
        Serial.print(" Ovf=");
        Serial.print(sap1_overflow, HEX);
        Serial.print(" Unf=");
        Serial.println(sap1_underflow, HEX);
        displayHex(0, reg_a);
        displayHex(1, reg_b);
        displayHex(2, accumulator);
        displayHex(3, pc_out);
        displayHex(4, phase);
        if (sng_en == 1 && prev_sng_en == 0) {
            playSong(opcode); // Adjust if operand is needed
        }
        prev_sng_en = sng_en;
        new_data = false;
    }
}
void displayHex(uint8_t device, uint8_t value) {
    lc.clearDisplay(device);
    lc.setDigit(device, 1, (value >> 4) & 0x0F, false);
    lc.setDigit(device, 0, value & 0x0F, false);
}
void playSong(uint8_t song_number) {
    Serial.print("Playing song ");
    Serial.println(song_number);
    if (song_number == 0) {
        for (int i = 0; i < melody0_length; i++) {
            tone(BUZZER_PIN, melody0[i][0]);
            delay(melody0[i][1]);
            noTone(BUZZER_PIN);
            delay(50);
        }
    } else if (song_number == 1) {
        for (int i = 0; i < melody1_length; i++) {
            tone(BUZZER_PIN, melody1[i][0]);
            delay(melody1[i][1]);
            noTone(BUZZER_PIN);
            delay(50);
        }
    } else if (song_number == 2) {
        for (int i = 0; i < melody2_length; i++) {
            int noteDuration = 2000 / noteDurations2[i];
            tone(BUZZER_PIN, melody2[i], noteDuration);
            int pauseBetweenNotes = noteDuration * 1.30;
            delay(pauseBetweenNotes);
            noTone(BUZZER_PIN);
        }
    } else if (song_number == 3) {
        for (int i = 0; i < melody3_length; i++) {
            tone(BUZZER_PIN, melody3[i][0]);
            delay(melody3[i][1]);
            noTone(BUZZER_PIN);
            delay(50);
        }
    } else if (song_number == 4) {
        for (int i = 0; i < melody4_length; i++) {
            tone(BUZZER_PIN, melody4[i][0]);
            delay(melody4[i][1]);
            noTone(BUZZER_PIN);
            delay(50);
        }
    } else if (song_number == 5) {
        for (int i = 0; i < melody5_length; i++) {
            tone(BUZZER_PIN, melody5[i][0]);
            delay(melody5[i][1]);
            noTone(BUZZER_PIN);
            delay(50);
        }
    } else {
        tone(BUZZER_PIN, NOTE_A4, 500);
        delay(500);
        noTone(BUZZER_PIN);
    }
}
