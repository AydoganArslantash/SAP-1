`timescale 1ns / 10ps

module top (
    input wire clk,          // 100 MHz
    input wire btnC,        // Reset (center)
    input wire btnR,        // Submit (right)
    input wire btnL,        // Pause/step (left)
    input wire [15:0] sw,   // sw15:14=program, sw13=SNG enable, sw7:0=A/B, sw5:2=song_number
    output wire sclk,       // SPI clock
    output wire mosi,       // SPI data
    output wire cs_n,       // SPI chip select
    output wire [6:0] seg,  // 7-segment cathodes
    output wire [3:0] an,   // 7-segment anodes
    output wire [15:0] led  // led[0]=btnR, led[1]=sw15, led[2]=sw14, led[3]=sw13, led[4]=sap1_clk, led[5]=halt, led[6]=input_state[0], led[7]=input_state[1], led[8]=btnR_rising, led[9]=btnR, led[10]=sw[13], led[11]=sys_reset, led[12]=write_done, led[15:13]=state
);
    // Internal signals
    wire sap1_clk;
    wire [15:0] sw_stable;
    wire sys_reset;
    wire [3:0] opcode;
    wire halt;
    wire [7:0] bus;
    wire [3:0] pc_out, mar_out, operand;
    wire [7:0] ir_out, a_out, b_out, acc_out;
    wire hlt, pc_inc, pc_en, mar_load, mem_en, ir_load, ir_en;
    wire a_load, a_en, b_load, alu_sub, alu_en, acc_load;
    wire sng_en;
    wire [2:0] state;
    wire overflow, underflow;
    wire [7:0] pc_bus_out, ir_bus_out, a_bus_out, alu_bus_out, ram_bus_out;

    // Extend reset duration
    reg [9:0] reset_sync;
    always @(posedge clk) begin
        reset_sync <= {reset_sync[8:0], btnC};
    end
    assign sys_reset = |reset_sync;

    // Input state machine
    localparam [2:0]
        IDLE = 3'd0,
        SELECT_PROG = 3'd1,
        INPUT_A = 3'd2,
        INPUT_B = 3'd3,
        EXECUTE = 3'd5;

    reg [2:0] input_state;
    reg [2:0] selected_prog;
    reg [7:0] input_A, input_B;
    reg [3:0] write_addr;
    reg write_en;
    reg [3:0] song_number;
    reg write_done;
    reg [3:0] write_counter;
    reg write_busy;

    // Button debouncing
    reg [19:0] btnR_counter, btnL_counter;
    reg btnR_prev, btnL_prev;
    reg btnR_lockout, btnL_lockout;
    wire btnR_rising = (btnR_counter == 20'd500000) & ~btnR_prev & btnR & ~btnR_lockout;
    wire btnL_rising = (btnL_counter == 20'd500000) & ~btnL_prev & btnL & ~btnL_lockout;

    always @(posedge clk or posedge sys_reset) begin
        if (sys_reset) begin
            btnR_counter <= 0;
            btnR_prev <= 0;
            btnR_lockout <= 0;
            btnL_counter <= 0;
            btnL_prev <= 0;
            btnL_lockout <= 0;
        end else begin
            if (btnR != btnR_prev) begin
                btnR_counter <= 0;
            end else if (btnR_counter < 20'd500000) begin
                btnR_counter <= btnR_counter + 1;
            end
            btnR_prev <= (btnR_counter == 20'd500000) ? btnR : btnR_prev;
            if (btnR_rising) btnR_lockout <= 1;
            else if (!btnR && btnR_counter >= 20'd10000) btnR_lockout <= 0;

            if (btnL != btnL_prev) begin
                btnL_counter <= 0;
            end else if (btnL_counter < 20'd500000) begin
                btnL_counter <= btnL_counter + 1;
            end
            btnL_prev <= (btnL_counter == 20'd500000) ? btnL : btnL_prev;
            if (btnL_rising) btnL_lockout <= 1;
            else if (!btnL && btnL_counter >= 20'd10000) btnL_lockout <= 0;
        end
    end

    // Input state machine
    always @(posedge clk or posedge sys_reset) begin
        if (sys_reset) begin
            input_state <= IDLE;
            selected_prog <= 0;
            input_A <= 0;
            input_B <= 0;
            write_addr <= 0;
            write_en <= 0;
            song_number <= 0;
            write_done <= 0;
            write_counter <= 0;
            write_busy <= 0;
        end else begin
            case (input_state)
                IDLE: begin
                    if (btnR_rising) begin
                        input_state <= SELECT_PROG;
                        if (sw_stable[13]) begin
                            selected_prog <= 3'b100;
                        end else begin
                            case (sw_stable[15:14])
                                2'b00, 2'b01: selected_prog <= 3'b001;
                                2'b10: selected_prog <= 3'b010;
                                default: selected_prog <= 3'b001;
                            endcase
                        end
                        song_number <= sw_stable[5:2];
                    end
                end
                SELECT_PROG: begin
                    if (btnR_rising) begin
                        if (selected_prog[2]) begin
                            input_state <= EXECUTE;
                            write_busy <= 1;
                            write_counter <= 0;
                        end else begin
                            input_state <= INPUT_A;
                        end
                    end
                end
                INPUT_A: begin
                    if (btnR_rising) begin
                        input_A <= sw_stable[7:0];
                        input_state <= INPUT_B;
                    end
                end
                INPUT_B: begin
                    if (btnR_rising) begin
                        input_B <= sw_stable[7:0];
                        input_state <= EXECUTE;
                        write_busy <= 1;
                        write_counter <= 0;
                    end
                end
                EXECUTE: begin
                    if (halt) begin
                        input_state <= IDLE;
                        write_done <= 0;
                    end
                end
                default: input_state <= IDLE;
            endcase
        end
    end

    // Write sequence logic
    always @(posedge clk or posedge sys_reset) begin
        if (sys_reset) begin
            write_counter <= 0;
            write_busy <= 0;
            write_en <= 0;
            write_done <= 0;
        end else if (write_busy) begin
            if (selected_prog == 3'b100) begin
                if (write_counter < 2) begin
                    write_addr <= write_counter;
                    write_en <= 1;
                    write_counter <= write_counter + 1;
                end else begin
                    write_en <= 0;
                    write_busy <= 0;
                    write_done <= 1;
                end
            end else begin
                if (write_counter < 7) begin
                    case (write_counter)
                        0: write_addr <= 0;
                        1: write_addr <= 1;
                        2: write_addr <= 2;
                        3: write_addr <= 3;
                        4: write_addr <= 4;
                        5: write_addr <= 14;
                        6: write_addr <= 15;
                        default: write_addr <= 0;
                    endcase
                    write_en <= 1;
                    write_counter <= write_counter + 1;
                end else begin
                    write_en <= 0;
                    write_busy <= 0;
                    write_done <= 1;
                end
            end
        end else begin
            write_en <= 0;
        end
    end

    // SPI start signal
    reg [2:0] spi_clk_sync;
    reg clk_prev;
    reg [1:0] spi_delay;
    wire spi_sending;
    always @(posedge clk or posedge sys_reset) begin
        if (sys_reset) begin
            spi_clk_sync <= 3'b000;
            clk_prev <= 0;
            spi_delay <= 2'b00;
        end else begin
            spi_clk_sync <= {spi_clk_sync[1:0], sap1_clk};
            clk_prev <= spi_clk_sync[2];
            spi_delay <= {spi_delay[0], spi_clk_sync[2] && !clk_prev};
        end
    end
    wire spi_start = spi_delay[1] && !halt && !spi_sending && (input_state == EXECUTE);

    // Bus multiplexer
    assign bus = pc_en ? pc_bus_out :
                 ir_en ? ir_bus_out :
                 a_en ? a_bus_out :
                 alu_en ? alu_bus_out :
                 mem_en ? ram_bus_out : 8'b0;

    // Clock Divider
    clk_divider clk_div_inst (
        .clk(clk),
        .clk_reset(sys_reset),
        .btnL(btnL_rising),
        .halt(halt),
        .sap1_clk(sap1_clk)
    );

    // Switch Debouncer
    switch_debouncer sw_debounce_inst (
        .clk(clk),
        .reset(sys_reset),
        .sw(sw),
        .sw_stable(sw_stable)
    );

    // Seven-Segment Display
    seven_segment_display seg_display_inst (
        .clk(clk),
        .reset(sys_reset),
        .halt(halt),
        .opcode(opcode),
        .input_state(input_state),
        .seg(seg),
        .an(an)
    );

    // LEDs
    assign led = {state, write_done, sys_reset, sw[13], btnR, btnR_rising, input_state[1:0], halt, sap1_clk, sw_stable[13], sw_stable[14], sw_stable[15], btnR};

    // SAP-1 Modules
    program_counter pc_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .hlt(hlt),
        .pc_inc(pc_inc),
        .pc_en(pc_en),
        .pc_out(pc_out),
        .pc_bus_out(pc_bus_out)
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
        .write_en(write_en),
        .write_addr(write_addr),
        .selected_prog(selected_prog),
        .input_A(input_A),
        .input_B(input_B),
        .song_number(song_number),
        .addr(mar_out),
        .mem_en(mem_en),
        .ram_bus_out(ram_bus_out)
    );

    instruction_reg ir_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .ir_load(ir_load),
        .ir_en(ir_en),
        .bus(bus),
        .opcode(opcode),
        .operand(operand),
        .ir_out(ir_out),
        .ir_bus_out(ir_bus_out)
    );

    controller controller_inst (
        .clk(sap1_clk),
        .rst(sys_reset),
        .opcode(opcode),
        .execute(input_state == EXECUTE),
        .halt(halt),
        .out({sng_en, hlt, pc_inc, pc_en, mar_load, mem_en, ir_load, ir_en, a_load, a_en, b_load, alu_sub, alu_en, acc_load}),
        .state(state)
    );

    reg_a reg_a_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .a_load(a_load),
        .a_en(a_en),
        .bus(bus),
        .a_out(a_out),
        .a_bus_out(a_bus_out)
    );

    reg_b reg_b_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .b_load(b_load),
        .bus(bus),
        .b_out(b_out)
    );

    ALU alu_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .a(a_out),
        .b(b_out),
        .sub(alu_sub),
        .en(alu_en),
        .load(acc_load),
        .bus(bus),
        .acc_out(acc_out),
        .overflow(overflow),
        .underflow(underflow),
        .alu_bus_out(alu_bus_out)
    );

    spi_master spi_inst (
        .clk(clk),
        .reset(sys_reset),
        .data_in({a_out, b_out, acc_out, {2'b0, overflow, underflow, pc_out}, sng_en, operand[3:0], state[2:0]}),
        .start(spi_start),
        .sclk(sclk),
        .mosi(mosi),
        .cs_n(cs_n),
        .sending(spi_sending)
    );
endmodule

// Submodules

module clk_divider (
    input wire clk,          // 100 MHz
    input wire clk_reset,    // Dedicated reset
    input wire btnL,         // Pause/step (debounced)
    input wire halt,         // Halt from controller
    output reg sap1_clk      // 0.5 Hz
);
    reg [25:0] clk_counter;
    reg sap1_clk_raw;
    reg [2:0] clk_sync;
    reg paused;

    always @(posedge clk or posedge clk_reset) begin
        if (clk_reset) begin
            paused <= 0;
        end else if (btnL) begin
            paused <= ~paused;
        end
    end

    always @(posedge clk or posedge clk_reset) begin
        if (clk_reset) begin
            clk_counter <= 0;
            sap1_clk_raw <= 0;
            clk_sync <= 0;
            sap1_clk <= 0;
        end else if (!halt && !paused) begin
            clk_counter <= clk_counter + 1;
            if (clk_counter == 26'd49_999_999) begin // 100 MHz / (2 * 50M) = 0.5 Hz
                clk_counter <= 0;
                sap1_clk_raw <= ~sap1_clk_raw;
            end
            clk_sync <= {clk_sync[1:0], sap1_clk_raw};
            sap1_clk <= clk_sync[2];
        end
    end
endmodule

module switch_debouncer (
    input wire clk,
    input wire reset,
    input wire [15:0] sw,
    output reg [15:0] sw_stable
);
    reg [19:0] debounce_counter [15:0]; // ~5ms
    reg [15:0] sw_sync, sw_prev;
    integer i;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 16; i = i + 1) begin
                debounce_counter[i] <= 0;
                sw_sync[i] <= 0;
                sw_prev[i] <= 0;
                sw_stable[i] <= 0;
            end
        end else begin
            for (i = 0; i < 16; i = i + 1) begin
                sw_sync[i] <= sw[i];
                if (sw_sync[i] != sw_prev[i]) begin
                    debounce_counter[i] <= 0;
                end else if (debounce_counter[i] < 20'd500000) begin
                    debounce_counter[i] <= debounce_counter[i] + 1;
                end else begin
                    sw_stable[i] <= sw_sync[i];
                end
                sw_prev[i] <= sw_sync[i];
            end
        end
    end
endmodule

module seven_segment_display (
    input wire clk,          // System clock (100 MHz)
    input wire reset,        // Active high reset
    input wire halt,         // Halt signal
    input wire [3:0] opcode, // Opcode to display
    input wire [2:0] input_state, // Input state for display
    output reg [6:0] seg,    // 7-segment cathodes (A-G, active low)
    output reg [3:0] an      // 7-segment anodes (active low)
);
    localparam [6:0] SEG_A = 7'b1110111; // A
    localparam [6:0] SEG_B = 7'b1111100; // b
    localparam [6:0] SEG_C = 7'b0111001; // C
    localparam [6:0] SEG_D = 7'b1011110; // d
    localparam [6:0] SEG_E = 7'b1111001; // E
    localparam [6:0] SEG_G = 7'b1101111; // G
    localparam [6:0] SEG_H = 7'b0110111; // H
    localparam [6:0] SEG_I = 7'b0110000; // I
    localparam [6:0] SEG_L = 7'b0111000; // L
    localparam [6:0] SEG_N = 7'b1010100; // n
    localparam [6:0] SEG_O = 7'b0111111; // O
    localparam [6:0] SEG_S = 7'b1101101; // S
    localparam [6:0] SEG_T = 7'b1111000; // t
    localparam [6:0] SEG_U = 7'b0111110; // U
    localparam [6:0] SEG_X = 7'b1110110; // X
    localparam [6:0] SEG_OFF = 7'b0000000; // Blank

    localparam [2:0]
        IDLE = 3'd0,
        SELECT_PROG = 3'd1,
        INPUT_A = 3'd2,
        INPUT_B = 3'd3,
        EXECUTE = 3'd5;

    reg [15:0] seg_counter;
    reg [1:0] digit_select;
    reg [6:0] digit0, digit1, digit2, digit3;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            seg_counter <= 0;
            digit_select <= 0;
        end else begin
            seg_counter <= seg_counter + 1;
            if (seg_counter == 0) begin
                digit_select <= digit_select + 1;
            end
        end
    end

    always @(*) begin
        if (reset || halt) begin
            digit0 = SEG_OFF;
            digit1 = SEG_OFF;
            digit2 = SEG_OFF;
            digit3 = SEG_OFF;
        end else begin
            case (input_state)
                IDLE: begin
                    digit3 = SEG_I; // IdLE
                    digit2 = SEG_D;
                    digit1 = SEG_L;
                    digit0 = SEG_E;
                end
                SELECT_PROG: begin
                    digit3 = SEG_S; // SEL
                    digit2 = SEG_E;
                    digit1 = SEG_L;
                    digit0 = SEG_OFF;
                end
                INPUT_A: begin
                    digit3 = SEG_OFF; // A
                    digit2 = SEG_OFF;
                    digit1 = SEG_OFF;
                    digit0 = SEG_A;
                end
                INPUT_B: begin
                    digit3 = SEG_OFF; // b
                    digit2 = SEG_OFF;
                    digit1 = SEG_OFF;
                    digit0 = SEG_B;
                end
                EXECUTE: begin
                    digit3 = SEG_E; // EXEC
                    digit2 = SEG_X;
                    digit1 = SEG_E;
                    digit0 = SEG_C;
                end
                default: begin
                    digit0 = SEG_OFF;
                    digit1 = SEG_OFF;
                    digit2 = SEG_OFF;
                    digit3 = SEG_OFF;
                end
            endcase
        end
    end

    always @(posedge clk) begin
        case (digit_select)
            2'b00: begin
                an <= 4'b1110;
                seg <= ~digit0;
            end
            2'b01: begin
                an <= 4'b1101;
                seg <= ~digit1;
            end
            2'b10: begin
                an <= 4'b1011;
                seg <= ~digit2;
            end
            2'b11: begin
                an <= 4'b0111;
                seg <= ~digit3;
            end
            default: begin
                an <= 4'b1111;
                seg <= ~SEG_OFF;
            end
        endcase
    end
endmodule

module program_counter (
    input wire clk, reset, hlt, pc_inc, pc_en,
    output reg [3:0] pc_out,
    output wire [7:0] pc_bus_out
);
    always @(posedge clk or posedge reset) begin
        if (reset) pc_out <= 0;
        else if (!hlt && pc_inc) pc_out <= pc_out + 1;
    end
    assign pc_bus_out = pc_en ? {4'b0, pc_out} : 8'b0;
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
    input wire clk, reset,
    input wire write_en,
    input wire [3:0] write_addr,
    input wire [2:0] selected_prog,
    input wire [7:0] input_A, input_B,
    input wire [3:0] song_number,
    input wire [3:0] addr,
    input wire mem_en,
    output wire [7:0] ram_bus_out
);
    reg [7:0] ram [0:15];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            integer i;
            for (i = 0; i < 16; i = i + 1)
                ram[i] <= 8'h00;
        end else if (write_en) begin
            if (selected_prog == 3'b100) begin // SNG
                if (write_addr == 0) ram[0] <= {4'h3, song_number};
                if (write_addr == 1) ram[1] <= 8'hF0;
            end else begin // ADD or SUB
                case (write_addr)
                    0: ram[0] <= 8'h0F; // LDA 15
                    1: ram[1] <= (selected_prog == 3'b001) ? 8'h1E : 8'h2E; // ADD 14 or SUB 14
                    2: ram[2] <= 8'hE0; // OUT
                    3: ram[3] <= 8'h30; // SNG 0
                    4: ram[4] <= 8'hF0; // HLT
                    14: ram[14] <= input_B;
                    15: ram[15] <= input_A;
                    default: ram[write_addr] <= 8'h00;
                endcase
            end
        end
    end

    assign ram_bus_out = mem_en ? ram[addr] : 8'b0;
endmodule

module instruction_reg (
    input wire clk, reset, ir_load, ir_en,
    input wire [7:0] bus,
    output reg [3:0] opcode,
    output reg [3:0] operand,
    output wire [7:0] ir_out,
    output wire [7:0] ir_bus_out
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
    assign ir_bus_out = ir_en ? ir_out : 8'b0;
endmodule

module controller (
    input wire clk, rst,
    input wire [3:0] opcode,
    input wire execute,
    output reg halt,
    output reg [13:0] out, // {sng_en, hlt, pc_inc, pc_en, mar_load, mem_en, ir_load, ir_en, a_load, a_en, b_load, alu_sub, alu_en, acc_load}
    output reg [2:0] state
);
    localparam [3:0] LDA = 4'h0, ADD = 4'h1, SUB = 4'h2, SNG = 4'h3, OUT = 4'hE, HLT = 4'hF;
    localparam [2:0] FETCH1 = 3'd0, FETCH2 = 3'd1, DECODE = 3'd2, EXEC1 = 3'd3, EXEC2 = 3'd4, EXEC3 = 3'd5;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= FETCH1;
            out <= 14'b0;
            halt <= 0;
        end else if (execute) begin
            case (state)
                FETCH1: begin
                    out <= 14'b00011011000000; // pc_en, mar_load, mem_en
                    halt <= 0;
                    state <= FETCH2;
                end
                FETCH2: begin
                    out <= 14'b00000110000000; // ir_load, mem_en
                    halt <= 0;
                    state <= DECODE;
                end
                DECODE: begin
                    out <= 14'b00000000000000; // No control signals
                    halt <= 0;
                    state <= EXEC1;
                end
                EXEC1: begin
                    case (opcode)
                        LDA: out <= 14'b00011010000000; // pc_en, mar_load, mem_en
                        ADD, SUB: out <= 14'b00011010000000; // pc_en, mar_load, mem_en
                        SNG: out <= 14'b10000000000000; // sng_en
                        OUT: out <= 14'b00000000000101; // alu_en, acc_load
                        HLT: out <= 14'b01000000000000; // hlt
                        default: out <= 14'b0;
                    endcase
                    halt <= (opcode == HLT);
                    state <= EXEC2;
                end
                EXEC2: begin
                    case (opcode)
                        LDA: out <= 14'b00000110010000; // mem_en, a_load
                        ADD: out <= 14'b00000110001000; // mem_en, b_load
                        SUB: out <= 14'b00000110001000; // mem_en, b_load
                        SNG, OUT, HLT: out <= 14'b0;
                        default: out <= 14'b0;
                    endcase
                    halt <= (opcode == HLT);
                    state <= EXEC3;
                end
                EXEC3: begin
                    case (opcode)
                        LDA: out <= 14'b0;
                        ADD: out <= 14'b00000000000101; // alu_en, acc_load
                        SUB: out <= 14'b00000000001101; // alu_sub, alu_en, acc_load
                        SNG, OUT, HLT: out <= 14'b0;
                        default: out <= 14'b0;
                    endcase
                    halt <= (opcode == HLT);
                    state <= FETCH1;
                end
                default: begin
                    out <= 14'b0;
                    halt <= 0;
                    state <= FETCH1;
                end
            endcase
        end else begin
            out <= 14'b0;
            halt <= 0;
            state <= FETCH1;
        end
    end
endmodule

module reg_a (
    input wire clk, reset, a_load, a_en,
    input wire [7:0] bus,
    output reg [7:0] a_out,
    output wire [7:0] a_bus_out
);
    always @(posedge clk or posedge reset) begin
        if (reset) a_out <= 0;
        else if (a_load) a_out <= bus;
    end
    assign a_bus_out = a_en ? a_out : 8'b0;
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

module ALU (
    input wire clk, reset,
    input wire [7:0] a, b,
    input wire sub, en, load,
    output wire [7:0] bus,
    output reg [7:0] acc_out,
    output reg overflow,
    output reg underflow,
    output wire [7:0] alu_bus_out
);
    wire [8:0] sum = a + b;
    wire [7:0] diff = a - b;
    wire diff_underflow = (a < b);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            acc_out <= 0;
            overflow <= 0;
            underflow <= 0;
        end else if (load) begin
            if (sub) begin
                if (diff_underflow) begin
                    acc_out <= 8'h00;
                    underflow <= 1;
                    overflow <= 0;
                end else begin
                    acc_out <= diff;
                    underflow <= 0;
                    overflow <= 0;
                end
            end else begin
                if (sum[8]) begin
                    acc_out <= 8'hFF;
                    overflow <= 1;
                    underflow <= 0;
                end else begin
                    acc_out <= sum[7:0];
                    overflow <= 0;
                    underflow <= 0;
                end
            end
        end
    end
    assign alu_bus_out = en ? acc_out : 8'b0;
    assign bus = alu_bus_out;
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
                if (!sclk) begin
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
