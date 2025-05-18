module top (
    input wire clk,          // 100 MHz FPGA clock
    input wire reset,       // Reset button (active high)
    input wire sw0,         // Switch to select program (0=add, 1=sub)
    output wire sclk,       // SPI clock to Arduino
    output wire mosi,       // SPI data to Arduino
    output wire cs_n,       // SPI chip select (active low)
    output wire [6:0] seg,  // 7-segment cathodes (A-G)
    output wire [3:0] an,   // 7-segment anodes (active low)
    output wire [4:0] led   // Debug LEDs: led[4]=sw0, led[3:0]=opcode
);

    // Clock divider for SAP-1 (0.5 Hz, 1 second per stage)
    reg [25:0] clk_counter;
    reg sap1_clk_raw;
    reg [2:0] clk_sync;
    reg sap1_clk;
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

    // Switch Debouncing for sw0
    reg [15:0] debounce_counter;
    reg sw0_sync, sw0_prev, sw0_stable;
    reg soft_reset;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            debounce_counter <= 0;
            sw0_sync <= 0;
            sw0_prev <= 0;
            sw0_stable <= 0;
            soft_reset <= 1;
        end else begin
            sw0_sync <= sw0;
            if (sw0_sync != sw0_prev) begin
                debounce_counter <= 0;
                soft_reset <= 1;
            end else if (debounce_counter < 50_000) begin // ~0.5 ms at 100 MHz
                debounce_counter <= debounce_counter + 1;
            end else begin
                sw0_stable <= sw0_sync;
                soft_reset <= 0;
            end
            sw0_prev <= sw0_sync;
        end
    end

    // 7-Segment Display (show a_out for debug, could show acc_out)
    reg [6:0] seg_reg;
    reg [3:0] an_reg;
    wire [7:0] a_out;  // For debug display
    wire [3:0] opcode; // For LED
    wire halt;         // For blanking display
    always @(posedge sap1_clk or posedge reset) begin
        if (reset || halt) begin
            seg_reg <= 7'b0000000;
            an_reg <= 4'b1111;
        end else begin
            an_reg <= 4'b1110;
            case (a_out[3:0]) // Display lower 4 bits of a_out
                4'h0: seg_reg <= ~7'b1111110; // 0
                4'h4: seg_reg <= ~7'b0110011; // 4
                4'hA: seg_reg <= ~7'b1110111; // A
                4'hE: seg_reg <= ~7'b1001111; // E
                default: seg_reg <= 7'b0000000;
            endcase
        end
    end
    assign seg = seg_reg;
    assign an = an_reg;

    // Debug LEDs: led[4]=sw0, led[3:0]=opcode
    assign led = {sw0_stable, opcode};

    // SAP-1 Signals
    wire [7:0] bus;        // 8-bit shared bus
    wire [3:0] pc_out, mar_out, operand;
    wire [7:0] ram_out, ir_out, b_out, acc_out; // acc_out replaces adder_out
    wire hlt, pc_inc, pc_en, mar_load, mem_en, ir_load, ir_en;
    wire a_load, a_en, b_load, adder_sub, adder_en, acc_load; // New acc_load
    wire sys_reset = reset | soft_reset;
    wire [2:0] state;

    // Program Counter
    program_counter pc_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .hlt(hlt),
        .pc_inc(pc_inc),
        .pc_en(pc_en),
        .bus(bus),
        .pc_out(pc_out)
    );

    // Memory Address Register
    mar mar_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .mar_load(mar_load),
        .bus(bus[3:0]),
        .mar_out(mar_out)
    );

    // RAM (ROM)
    ram ram_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .sw0(sw0_stable),
        .addr(mar_out),
        .mem_en(mem_en),
        .bus(bus)
    );

    // Instruction Register
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

    // Controller
    controller controller_inst (
        .clk(sap1_clk),
        .rst(sys_reset),
        .opcode(opcode),
        .out({hlt, pc_inc, pc_en, mar_load, mem_en, ir_load, ir_en, a_load, a_en, b_load, adder_sub, adder_en, acc_load}),
        .state(state)
    );

    // A Register (Input only, not accumulator)
    reg_a reg_a_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .a_load(a_load),
        .a_en(a_en),
        .bus(bus),
        .a_out(a_out)
    );

    // B Register
    reg_b reg_b_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .b_load(b_load),
        .bus(bus),
        .b_out(b_out)
    );

    // Adder/Subtractor (Now the accumulator)
    adder_sub adder_sub_inst (
        .clk(sap1_clk),
        .reset(sys_reset),
        .a(a_out),
        .b(b_out),
        .sub(adder_sub),
        .en(adder_en),
        .load(acc_load), // New load signal
        .bus(bus),
        .acc_out(acc_out) // Accumulator output
    );

    // SPI Integration
    reg [2:0] spi_clk_sync;
    reg clk_prev;
    reg [1:0] spi_delay;
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
    wire [39:0] spi_data = {a_out, b_out, acc_out, {4'b0, pc_out}, 5'b0, state};

    // SPI Master
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
    input wire clk, reset, sw0, mem_en,
    input wire [3:0] addr,
    output wire [7:0] bus
);
    reg [7:0] add_rom [0:15];
    reg [7:0] sub_rom [0:15];
    integer i;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            add_rom[0]  <= 8'h0F; // LDA 15
            add_rom[1]  <= 8'h1E; // ADD 14
            add_rom[2]  <= 8'hE0; // OUT
            add_rom[3]  <= 8'hF0; // HLT            
            add_rom[4]  <= 8'h00;
            add_rom[5]  <= 8'h00;
            add_rom[6]  <= 8'h00;
            add_rom[7]  <= 8'h00;
            add_rom[8]  <= 8'h00;
            add_rom[9]  <= 8'h00;
            add_rom[10] <= 8'h00;
            add_rom[11] <= 8'h00;
            add_rom[12] <= 8'h00;
            add_rom[13] <= 8'hF0; // HLT  
            add_rom[14] <= 8'h04; // B=4
            add_rom[15] <= 8'h0A; // A=10

            sub_rom[0]  <= 8'h0F; // LDA 15
            sub_rom[1]  <= 8'h2E; // SUB 14
            sub_rom[2]  <= 8'hE0; // OUT
            sub_rom[3]  <= 8'hF0; // HLT
            for (i = 4; i <= 14; i = i + 1)
                sub_rom[i] <= 8'h00;
            sub_rom[14] <= 8'h04; // B=4
            sub_rom[15] <= 8'h0A; // A=10
        end
    end

    assign bus = mem_en ? (sw0 ? sub_rom[addr] : add_rom[addr]) : 8'bz;
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
    output wire [12:0] out, // Expanded for acc_load
    output reg [2:0] state
);
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
    localparam SIG_ACC_LOAD  = 0; // New signal

    localparam OP_LDA = 4'b0000;
    localparam OP_ADD = 4'b0001;
    localparam OP_SUB = 4'b0010;
    localparam OP_OUT = 4'b1110;
    localparam OP_HLT = 4'b1111;

    reg [12:0] ctrl_word;

    always @(negedge clk or posedge rst) begin
        if (rst) begin
            state <= 0;
        end else if (!out[SIG_HLT]) begin
            if (state == 5) state <= 0;
            else state <= state + 1;
        end
    end

    always @(*) begin
        ctrl_word = 13'b0;
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
                        ctrl_word[SIG_A_EN] = 1; // Could use acc_out
                    end
                    OP_HLT: begin
                        ctrl_word[SIG_HLT] = 1;
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
                        ctrl_word[SIG_ACC_LOAD] = 1; // Update accumulator
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
    input wire sub, en, load, // load for acc_out
    output wire [7:0] bus,
    output reg [7:0] acc_out // Accumulator register
);
    wire [7:0] result = sub ? a - b : a + b;
    always @(posedge clk or posedge reset) begin
        if (reset) acc_out <= 0;
        else if (load) acc_out <= result;
    end
    assign bus = en ? acc_out : 8'bz; // Drive acc_out to bus
endmodule
