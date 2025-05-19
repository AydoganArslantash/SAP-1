module top (
    input wire clk,          // 100 MHz FPGA clock
    input wire reset,       // Reset button (active high)
    input wire sw0,         // Switch 0 for program selection
    input wire sw1,         // Switch 1 for program selection
    input wire sw2,         // Switch 2 for program selection
    output wire sclk,       // SPI clock to Arduino
    output wire mosi,       // SPI data to Arduino
    output wire cs_n,       // SPI chip select (active low)
    output wire [6:0] seg,  // 7-segment cathodes (A-G)
    output wire [3:0] an,   // 7-segment anodes (active low)
    output wire [4:0] led   // LEDs: led[2]=sw2, led[1]=sw1, led[0]=sw0, others off
);
    // Wires for module connections
    wire sap1_clk;
    wire sw0_stable, sw1_stable, sw2_stable;
    wire soft_reset;
    wire [3:0] opcode;
    wire halt;

    // Clock Divider Instantiation
    clk_divider clk_div_inst (
        .clk(clk),
        .reset(reset),
        .sap1_clk(sap1_clk)
    );

    // Switch Debouncer Instantiation
    switch_debouncer sw_debounce_inst (
        .clk(clk),
        .reset(reset),
        .sw0(sw0),
        .sw1(sw1),
        .sw2(sw2),
        .sw0_stable(sw0_stable),
        .sw1_stable(sw1_stable),
        .sw2_stable(sw2_stable),
        .soft_reset(soft_reset)
    );

    // 7-Segment Display Instantiation
    seven_segment_display seg_display_inst (
        .clk(clk),
        .reset(reset),
        .halt(halt),
        .opcode(opcode),
        .seg(seg),
        .an(an)
    );

    // LEDs: led[2]=sw2, led[1]=sw1, led[0]=sw0, others off
    assign led = {2'b00, sw2_stable, sw1_stable, sw0_stable};

    // SAP-1 Signals
    wire [7:0] bus;
    wire [3:0] pc_out, mar_out, operand;
    wire [7:0] ir_out, b_out, a_out, acc_out;
    wire hlt, pc_inc, pc_en, mar_load, mem_en, ir_load, ir_en;
    wire a_load, a_en, b_load, adder_sub, adder_en, acc_load;
    wire sng_en;
    wire sys_reset = reset | soft_reset;
    wire [2:0] state;

    // SAP-1 Module Instantiations
    program_counter pc_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .hlt(hlt),
        .pc_inc(pc_inc),
        .pc_en(pc_en),
        .bus(bus),
        .pc_out(pc_out)
    );

    mar mar_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .mar_load(mar_load),
        .bus(bus[3:0]),
        .mar_out(mar_out)
    );

    ram ram_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .sw0(sw0_stable),
        .sw1(sw1_stable),
        .sw2(sw2_stable),
        .addr(mar_out),
        .mem_en(mem_en),
        .bus(bus)
    );

    instruction_reg ir_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .ir_load(ir_load),
        .ir_en(ir_en),
        .bus(bus),
        .opcode(opcode),
        .operand(operand),
        .ir_out(ir_out)
    );

    controller controller_inst (
        .clk(sap1_clk),
        .rst(sys_reset),
        .opcode(opcode),
        .out({sng_en, hlt, pc_inc, pc_en, mar_load, mem_en, ir_load, ir_en, a_load, a_en, b_load, adder_sub, adder_en, acc_load}),
        .state(state)
    );

    reg_a reg_a_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .a_load(a_load),
        .a_en(a_en),
        .bus(bus),
        .a_out(a_out)
    );

    reg_b reg_b_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .b_load(b_load),
        .bus(bus),
        .b_out(b_out)
    );

    adder_sub adder_sub_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .a(a_out),
        .b(b_out),
        .sub(adder_sub),
        .en(adder_en),
        .load(acc_load),
        .bus(bus),
        .acc_out(acc_out)
    );

    // SPI Integration
    reg [2:0] spi_clk_sync;
    reg clk_prev;
    reg [1:0] spi_delay;
    wire spi_sending;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            spi_clk_sync <= 3'b000;
            clk_prev <= 0;
            spi_delay <= 2'b00;
        end else begin
            spi_clk_sync <= {spi_clk_sync[1:0], sap1_clk};
            clk_prev <= spi_clk_sync[2];
            spi_delay <= {spi_delay[0], spi_clk_sync[2] && !clk_prev};
        end
    end
    wire spi_start = spi_delay[1] && !hlt && !spi_sending;
    wire [39:0] spi_data = {a_out, b_out, acc_out, {4'b0, pc_out}, sng_en, operand[3:0], state[2:0]};

    spi_master spi_inst (
        .clk(clk),
        .reset(reset),
        .start(spi_start),
        .data_in(spi_data),
        .mosi(mosi),
        .sclk(sclk),
        .cs_n(cs_n),
        .sending(spi_sending)
    );
endmodule

module clk_divider (
    input wire clk,          // 100 MHz input clock
    input wire reset,        // Active high reset
    output reg sap1_clk      // 0.5 Hz output clock
);
    reg [25:0] clk_counter;
    reg sap1_clk_raw;
    reg [2:0] clk_sync;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            clk_counter <= 0;
            sap1_clk_raw <= 0;
            clk_sync <= 0;
            sap1_clk <= 0;
        end else begin
            clk_counter <= clk_counter + 1;
            if (clk_counter == 49_999_999) begin // 100 MHz / (2 * 50M) = 0.5 Hz
                clk_counter <= 0;
                sap1_clk_raw <= ~sap1_clk_raw;
            end
            clk_sync <= {clk_sync[1:0], sap1_clk_raw};
            sap1_clk <= clk_sync[2];
        end
    end
endmodule

module switch_debouncer (
    input wire clk,          // System clock
    input wire reset,        // Active high reset
    input wire sw0,         // Switch 0 input
    input wire sw1,         // Switch 1 input
    input wire sw2,         // Switch 2 input
    output reg sw0_stable,  // Debounced switch 0
    output reg sw1_stable,  // Debounced switch 1
    output reg sw2_stable,  // Debounced switch 2
    output reg soft_reset    // Soft reset signal
);
    reg [15:0] debounce_counter_sw0;
    reg [15:0] debounce_counter_sw1;
    reg [15:0] debounce_counter_sw2;
    reg sw0_sync, sw0_prev;
    reg sw1_sync, sw1_prev;
    reg sw2_sync, sw2_prev;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            debounce_counter_sw0 <= 0;
            sw0_sync <= 0;
            sw0_prev <= 0;
            sw0_stable <= 0;
            debounce_counter_sw1 <= 0;
            sw1_sync <= 0;
            sw1_prev <= 0;
            sw1_stable <= 0;
            debounce_counter_sw2 <= 0;
            sw2_sync <= 0;
            sw2_prev <= 0;
            sw2_stable <= 0;
            soft_reset <= 1;
        end else begin
            // Debounce sw0
            sw0_sync <= sw0;
            if (sw0_sync != sw0_prev) begin
                debounce_counter_sw0 <= 0;
                soft_reset <= 1;
            end else if (debounce_counter_sw0 < 50_000) begin
                debounce_counter_sw0 <= debounce_counter_sw0 + 1;
            end else begin
                sw0_stable <= sw0_sync;
            end
            sw0_prev <= sw0_sync;

            // Debounce sw1
            sw1_sync <= sw1;
            if (sw1_sync != sw1_prev) begin
                debounce_counter_sw1 <= 0;
                soft_reset <= 1;
            end else if (debounce_counter_sw1 < 50_000) begin
                debounce_counter_sw1 <= debounce_counter_sw1 + 1;
            end else begin
                sw1_stable <= sw1_sync;
            end
            sw1_prev <= sw1_sync;

            // Debounce sw2
            sw2_sync <= sw2;
            if (sw2_sync != sw2_prev) begin
                debounce_counter_sw2 <= 0;
                soft_reset <= 1;
            end else if (debounce_counter_sw2 < 50_000) begin
                debounce_counter_sw2 <= debounce_counter_sw2 + 1;
            end else begin
                sw2_stable <= sw2_sync;
            end
            sw2_prev <= sw2_sync;

            // Clear soft_reset when all switches are stable
            if (debounce_counter_sw0 >= 50_000 && debounce_counter_sw1 >= 50_000 && debounce_counter_sw2 >= 50_000) begin
                soft_reset <= 0;
            end
        end
    end
endmodule

module seven_segment_display (
    input wire clk,          // System clock (100 MHz)
    input wire reset,        // Active high reset
    input wire halt,         // Halt signal
    input wire [3:0] opcode, // Opcode to display
    output reg [6:0] seg,    // 7-segment cathodes (A-G, active low)
    output reg [3:0] an      // 7-segment anodes (active low)
);
    // 7-segment patterns for letters (active high internally, will be inverted for output)
    localparam [6:0] SEG_L = 7'b0111000; // L
    localparam [6:0] SEG_D = 7'b1011110; // D
    localparam [6:0] SEG_A = 7'b1110111; // A
    localparam [6:0] SEG_S = 7'b1101101; // S
    localparam [6:0] SEG_U = 7'b0111110; // U
    localparam [6:0] SEG_B = 7'b1111100; // b (for SUB)
    localparam [6:0] SEG_O = 7'b0111111; // O
    localparam [6:0] SEG_T = 7'b0111111; // O
    localparam [6:0] SEG_H = 7'b0110111; // H
    localparam [6:0] SEG_N = 7'b1010100; // n 
    localparam [6:0] SEG_G = 7'b1101111; // G
    localparam [6:0] SEG_OFF = 7'b0000000; // Blank (all segments off)

    reg [15:0] seg_counter; // 100 MHz / 2^16 ≈ 1526 Hz
    reg [1:0] digit_select;
    reg [6:0] digit0, digit1, digit2, digit3; // D0=rightmost, D3=leftmost

    // Clock divider for multiplexing
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            seg_counter <= 0;
            digit_select <= 0;
        end else begin
            seg_counter <= seg_counter + 1;
            if (seg_counter == 0) begin
                digit_select <= digit_select + 1; // Cycle through 0, 1, 2, 3
            end
        end
    end

    // Opcode to display string mapping (left-aligned: D3=first char, D0=blank)
    always @(*) begin
        if (reset || halt) begin
            digit0 = SEG_OFF;
            digit1 = SEG_OFF;
            digit2 = SEG_OFF;
            digit3 = SEG_OFF;
        end else begin
            case (opcode)
                4'b0000: begin // OP_LDA
                    digit3 = SEG_L; // L
                    digit2 = SEG_D; // D
                    digit1 = SEG_A; // A
                    digit0 = SEG_OFF; // Blank
                end
                4'b0001: begin // OP_ADD
                    digit3 = SEG_A; // A
                    digit2 = SEG_D; // D
                    digit1 = SEG_D; // D
                    digit0 = SEG_OFF; // Blank
                end
                4'b0010: begin // OP_SUB
                    digit3 = SEG_S; // S
                    digit2 = SEG_U; // U
                    digit1 = SEG_B; // b
                    digit0 = SEG_OFF; // Blank
                end
                4'b1110: begin // OP_OUT
                    digit3 = SEG_O; // O
                    digit2 = SEG_U; // U
                    digit1 = SEG_T; // T
                    digit0 = SEG_OFF; // Blank
                end
                4'b1111: begin // OP_HLT
                    digit3 = SEG_H; // H
                    digit2 = SEG_L; // L
                    digit1 = SEG_T; // T
                    digit0 = SEG_OFF; // Blank
                end
                4'b0011: begin // OP_SNG
                    digit3 = SEG_S; // S
                    digit2 = SEG_N; // n
                    digit1 = SEG_G; // G
                    digit0 = SEG_OFF; // Blank
                end
                default: begin
                    digit3 = SEG_OFF;
                    digit2 = SEG_OFF;
                    digit1 = SEG_OFF;
                    digit0 = SEG_OFF;
                end
            endcase
        end
    end

    // Multiplexing logic (active-low outputs for Basys 3)
    always @(posedge clk) begin
        case (digit_select)
            2'b00: begin
                an <= 4'b1110; // Enable rightmost digit (AN0, D0)
                seg <= ~digit0; // Invert for active-low segments
            end
            2'b01: begin
                an <= 4'b1101; // Enable second from right (AN1, D1)
                seg <= ~digit1;
            end
            2'b10: begin
                an <= 4'b1011; // Enable second from left (AN2, D2)
                seg <= ~digit2;
            end
            2'b11: begin
                an <= 4'b0111; // Enable leftmost digit (AN3, D3)
                seg <= ~digit3;
            end
            default: begin
                an <= 4'b1111; // All digits off
                seg <= ~SEG_OFF;
            end
        endcase
    end
endmodule


module spi_master (
    input wire clk,
    input wire reset,
    input wire start,
    input wire [39:0] data_in,
    output reg mosi,
    output reg sclk,
    output reg cs_n,
    output reg sending
);
    parameter CLK_DIV = 200; // 100 MHz / (2 * 200) = 250 kHz SCLK
    reg [8:0] clk_count;
    reg [39:0] shift_reg;
    reg [5:0] bit_count;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mosi <= 0;
            sclk <= 0;
            cs_n <= 1;
            clk_count <= 0;
            shift_reg <= 0;
            bit_count <= 0;
            sending <= 0;
        end else if (!sending) begin
            if (start) begin
                shift_reg <= data_in;
                bit_count <= 6'd40;
                sending <= 1;
                cs_n <= 0;
                clk_count <= 0;
            end
        end else begin
            if (clk_count < CLK_DIV - 1) begin
                clk_count <= clk_count + 1;
            end else begin
                clk_count <= 0;
                sclk <= ~sclk;
                if (!sclk) begin // Falling edge (SPI Mode 0)
                    mosi <= shift_reg[39];
                    shift_reg <= {shift_reg[38:0], 1'b0};
                    bit_count <= bit_count - 1;
                    if (bit_count == 0) begin
                        sending <= 0;
                        cs_n <= 1;
                    end
                end
            end
        end
    end
endmodule




module program_counter (
    input wire clk, reset, hlt, pc_inc, pc_en,
    input wire [7:0] bus,
    output reg [3:0] pc_out
);
    always @(posedge clk or posedge reset) begin
        if (reset) pc_out <= 0;
        else if (!hlt && pc_inc) pc_out <= pc_out + 1;
    end
    assign bus = pc_en ? {4'b0, pc_out} : 8'bz;
endmodule

module mar (
    input wire clk, reset, mar_load,
    input wire [3:0] bus,
    output reg [3:0] mar_out
);
    always @(posedge clk or posedge reset) begin
        if (reset) mar_out <= 0;
        else if (mar_load) mar_out <= bus;
    end
endmodule

module ram (
    input wire clk, reset, mem_en,
    input wire sw0, sw1, sw2, // Switches for program selection
    input wire [3:0] addr,
    output wire [7:0] bus
);
    reg [7:0] add_rom [0:15];
    reg [7:0] sub_rom [0:15];
    reg [7:0] song_rom1 [0:15];
    reg [7:0] song_rom2 [0:15];
    reg [7:0] song_rom3 [0:15];
    reg [7:0] song_rom4 [0:15];


    integer i;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Initialize add_rom (addition program)
            add_rom[0]  <= 8'h0F; // LDA 15
            add_rom[1]  <= 8'h1E; // ADD 14
            add_rom[2]  <= 8'hE0; // OUT
            add_rom[3]  <= 8'h30; // OP_SNG 0 (song 0)
            add_rom[4]  <= 8'hF0; // HLT
            for (i = 5; i <= 13; i = i + 1)
                add_rom[i] <= 8'h00;
            add_rom[14] <= 8'h04; // B=4
            add_rom[15] <= 8'h0A; // A=10

            // Initialize sub_rom (subtraction program)
            sub_rom[0]  <= 8'h0F; // LDA 15
            sub_rom[1]  <= 8'h2E; // SUB 14
            sub_rom[2]  <= 8'hE0; // OUT
            sub_rom[3]  <= 8'h30; // OP_SNG 0 (song 0)
            sub_rom[4]  <= 8'hF0; // HLT
            for (i = 5; i <= 13; i = i + 1)
                sub_rom[i] <= 8'h00;
            sub_rom[14] <= 8'h04; // B=4
            sub_rom[15] <= 8'h0A; // A=10


// 0: CLASSIC BEEP

// 1: ISTIKLAL MARSI
// 2: USSR 
// 3: DAISY BELL
// 4: CAN YOU HEAR THE MUSIC?
// 5: PAPERS PLEASE

            // Initialize song1_rom (song program)
            song_rom1[0] <= 8'h32; // OP_SNG 1 (song 2)
            song_rom1[1] <= 8'hF0; // HLT
            for (i = 2; i <= 15; i = i + 1)
                song_rom1[i] <= 8'h00;
                
           // Initialize song2_rom (song program)
            song_rom2[0] <= 8'h33; // OP_SNG 2 (song 3)
            song_rom2[1] <= 8'hF0; // HLT
            for (i = 2; i <= 15; i = i + 1)
                song_rom2[i] <= 8'h00;     
                           
            // Initialize song3_rom (song program)
            song_rom3[0] <= 8'h34; // OP_SNG 3 (song 4)
            song_rom3[1] <= 8'hF0; // HLT
            for (i = 2; i <= 15; i = i + 1)
                song_rom3[i] <= 8'h00;
                
            // Initialize song1_rom (song program)
            song_rom4[0] <= 8'h35; // OP_SNG 3 (song 5)
            song_rom4[1] <= 8'hF0; // HLT
            for (i = 2; i <= 15; i = i + 1)
                song_rom4[i] <= 8'h00;
                

                

        end
    end

    // Program selection based on switches
    assign bus = mem_en ? (
        (sw0 == 0 && sw1 == 0 && sw2 == 0) ? add_rom[addr] :    // Addition
        (sw0 == 1 && sw1 == 0 && sw2 == 0) ? sub_rom[addr] :    // Subtraction
        (sw0 == 0 && sw1 == 1 && sw2 == 0) ? song_rom1[addr] :   // Play song
        (sw0 == 1 && sw1 == 1 && sw2 == 0) ? song_rom2[addr] :   // Play song
        (sw0 == 0 && sw1 == 0 && sw2 == 1) ? song_rom3[addr] :   // Play song
 //       (sw0 == 0 && sw1 == 1 && sw2 == 1) ? song_rom4[addr] :   // Play song
        (sw0 == 1 && sw1 == 1 && sw2 == 1) ? song_rom4[addr] :   // Play song
        add_rom[addr]                               // Default (sw0=0, sw1=1)
    ) : 8'bz;
endmodule

module instruction_reg (
    input wire clk, reset, ir_load, ir_en,
    input wire [7:0] bus,
    output reg [3:0] opcode,
    output reg [3:0] operand,
    output wire [7:0] ir_out
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            opcode <= 0;
            operand <= 0;
        end else if (ir_load) begin
            opcode <= bus[7:4];
            operand <= bus[3:0];
        end
    end
    assign ir_out = {opcode, operand};
    assign bus = ir_en ? ir_out : 8'bz;
endmodule

module controller (
    input wire clk, rst,
    input wire [3:0] opcode,
    output wire [13:0] out, // Expanded for sng_en
    output reg [2:0] state
);
    localparam SIG_SNG_EN    = 13; // New signal for OP_SNG
    localparam SIG_HLT       = 12;
    localparam SIG_PC_INC    = 11;
    localparam SIG_PC_EN     = 10;
    localparam SIG_MAR_LOAD  = 9;
    localparam SIG_MEM_EN    = 8;
    localparam SIG_IR_LOAD   = 7;
    localparam SIG_IR_EN     = 6;
    localparam SIG_A_LOAD    = 5;
    localparam SIG_A_EN      = 4;
    localparam SIG_B_LOAD    = 3;
    localparam SIG_ADDER_SUB = 2;
    localparam SIG_ADDER_EN  = 1;
    localparam SIG_ACC_LOAD  = 0;

    localparam OP_LDA = 4'b0000;
    localparam OP_ADD = 4'b0001;
    localparam OP_SUB = 4'b0010;
    localparam OP_OUT = 4'b1110;
    localparam OP_HLT = 4'b1111;
    localparam OP_SNG = 4'b0011; // New opcode

    reg [13:0] ctrl_word;

    always @(negedge clk or posedge rst) begin
        if (rst) begin
            state <= 0;
        end else if (!out[SIG_HLT]) begin
            if (state == 5) state <= 0;
            else state <= state + 1;
        end
    end

    always @(*) begin
        ctrl_word = 14'b0;
        case (state)
            0: begin
                ctrl_word[SIG_PC_EN] = 1;
                ctrl_word[SIG_MAR_LOAD] = 1;
            end
            1: begin
                ctrl_word[SIG_PC_INC] = 1;
            end
            2: begin
                ctrl_word[SIG_MEM_EN] = 1;
                ctrl_word[SIG_IR_LOAD] = 1;
            end
            3: begin
                case (opcode)
                    OP_LDA, OP_ADD, OP_SUB: begin
                        ctrl_word[SIG_IR_EN] = 1;
                        ctrl_word[SIG_MAR_LOAD] = 1;
                    end
                    OP_OUT: begin
                        ctrl_word[SIG_A_EN] = 1;
                    end
                    OP_HLT: begin
                        ctrl_word[SIG_HLT] = 1;
                    end
                    OP_SNG: begin
                        ctrl_word[SIG_SNG_EN] = 1;
                    end
                endcase
            end
            4: begin
                case (opcode)
                    OP_LDA: begin
                        ctrl_word[SIG_MEM_EN] = 1;
                        ctrl_word[SIG_A_LOAD] = 1;
                    end
                    OP_ADD, OP_SUB: begin
                        ctrl_word[SIG_MEM_EN] = 1;
                        ctrl_word[SIG_B_LOAD] = 1;
                    end
                endcase
            end
            5: begin
                case (opcode)
                    OP_ADD: begin
                        ctrl_word[SIG_ACC_LOAD] = 1;
                    end
                    OP_SUB: begin
                        ctrl_word[SIG_ADDER_SUB] = 1;
                        ctrl_word[SIG_ACC_LOAD] = 1;
                    end
                endcase
            end
        endcase
    end

    assign out = ctrl_word;
endmodule

module reg_a (
    input wire clk, reset, a_load, a_en,
    input wire [7:0] bus,
    output reg [7:0] a_out
);
    always @(posedge clk or posedge reset) begin
        if (reset) a_out <= 0;
        else if (a_load) a_out <= bus;
    end
    assign bus = a_en ? a_out : 8'bz;
endmodule

module reg_b (
    input wire clk, reset, b_load,
    input wire [7:0] bus,
    output reg [7:0] b_out
);
    always @(posedge clk or posedge reset) begin
        if (reset) b_out <= 0;
        else if (b_load) b_out <= bus;
    end
endmodule

module adder_sub (
    input wire clk, reset,
    input wire [7:0] a, b,
    input wire sub, en, load,
    output wire [7:0] bus,
    output reg [7:0] acc_out
);
    wire [7:0] result = sub ? a - b : a + b;
    always @(posedge clk or posedge reset) begin
        if (reset) acc_out <= 0;
        else if (load) acc_out <= result;
    end
    assign bus = en ? acc_out : 8'bz;
endmodule
