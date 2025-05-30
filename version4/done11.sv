`timescale 1ns / 10ps

module top (
    input wire clk,  // 100 MHz
    input wire btnC,  // Reset (center)
    input wire btnR,  // Submit (right)
    input wire btnL,  // Pause/step (left)
    input wire [15:0] sw,  // sw15:14=program, sw13=SNG enable, sw7:0=A/B, sw5:2=song_number
    output wire sclk,  // SPI clock
    output wire mosi,  // SPI data
    output wire cs_n,  // SPI chip select
    output wire [6:0] seg,  // 7-segment cathodes
    output wire [3:0] an,  // 7-segment anodes
    output wire [15:0] led  // led[15]=bus_conflict, led[14]=ir_load, led[13:12]=opcode[1:0], led[11]=write_done, led[10]=btnR_rising, led[9]=acc_load, led[8]=a_load, led[7]=b_load, led[6]=write_en, led[3]=halt, led[2]=sap1_clk, led[1:0]=input_state
);
  // Internal signals
  wire sap1_clk;
  wire [15:0] sw_stable;
  wire sys_reset;
  wire [3:0] opcode;
  wire halt;
  wire [7:0] bus;
  wire [3:0] pc_out, mar_out, operand;
  wire [7:0] ir_out, a_out, b_out;
  wire [15:0] acc_out, acc_reg_out;
  wire hlt, pc_inc, pc_en, mar_load, mem_en, ir_load, ir_en;
  wire a_load, a_en, b_load, alu_sub, alu_en, acc_load, acc_reg_load, acc_reg_en, sng_en;
  wire [2:0] state;
  wire overflow, underflow;
  wire [7:0] pc_bus_out, ir_bus_out, a_bus_out, alu_bus_out, ram_bus_out;

  // Make sure halt is properly connected - now hlt comes from controller output
  assign halt = hlt;

  // Bus conflict detection
  wire bus_conflict = (pc_en + ir_en + a_en + alu_en + mem_en + acc_reg_en) > 1;

  // Extend reset duration
  reg [9:0] reset_sync;
  always @(posedge clk) begin
    reset_sync <= {reset_sync[8:0], btnC};
  end
  assign sys_reset = |reset_sync;

  // Input state machine
  localparam [2:0] IDLE = 3'd0, SELECT_PROG = 3'd1, INPUT_A = 3'd2, INPUT_B = 3'd3, WRITE_RAM = 3'd4, EXECUTE = 3'd5, WRITE_WAIT = 3'd6;

  reg [2:0] input_state;
  reg [2:0] selected_prog;
  reg [7:0] input_A, input_B;
  reg [3:0] write_addr;
  reg write_en;
  reg [3:0] song_number;
  reg write_done_internal;
  wire write_done = write_done_internal;
  reg [2:0] write_counter;
  reg write_busy;

  // Button debouncing
  reg [15:0] btnR_shift, btnL_shift;
  reg btnR_stable, btnL_stable;
  reg btnR_rising_fast_reg, btnL_rising_fast_reg;

  always @(posedge clk or posedge sys_reset) begin
    if (sys_reset) begin
      btnR_shift <= 16'h0000;
      btnR_stable <= 0;
      btnR_rising_fast_reg <= 0;
      btnL_shift <= 16'h0000;
      btnL_stable <= 0;
      btnL_rising_fast_reg <= 0;
    end else begin
      btnR_shift <= {btnR_shift[14:0], btnR};
      if (btnR_shift == 16'hFFFF) btnR_stable <= 1;
      else if (btnR_shift == 16'h0000) btnR_stable <= 0;
      btnR_rising_fast_reg <= btnR_stable & ~btnR_rising_fast_reg;

      btnL_shift <= {btnL_shift[14:0], btnL};
      if (btnL_shift == 16'hFFFF) btnL_stable <= 1;
      else if (btnL_shift == 16'h0000) btnL_stable <= 0;
      btnL_rising_fast_reg <= btnL_stable & ~btnL_rising_fast_reg;
    end
  end
  wire btnR_rising_fast = btnR_stable & ~btnR_rising_fast_reg;
  wire btnL_rising_fast = btnL_stable & ~btnL_rising_fast_reg;

  // Synchronize button rising edges to sap1_clk
  reg btnR_latched, btnL_latched;
  reg [1:0] btnR_sync, btnL_sync;
  always @(posedge clk or posedge sys_reset) begin
    if (sys_reset) begin
      btnR_latched <= 0;
      btnL_latched <= 0;
    end else begin
      if (btnR_rising_fast) btnR_latched <= 1;
      else if (btnR_sync[1]) btnR_latched <= 0;
      if (btnL_rising_fast) btnL_latched <= 1;
      else if (btnL_sync[1]) btnL_latched <= 0;
    end
  end

  always @(posedge sap1_clk or posedge sys_reset) begin
    if (sys_reset) begin
      btnR_sync <= 2'b00;
      btnL_sync <= 2'b00;
    end else begin
      btnR_sync <= {btnR_sync[0], btnR_latched};
      btnL_sync <= {btnL_sync[0], btnL_latched};
    end
  end
  wire btnR_rising = btnR_sync[1] & ~btnR_sync[0];
  wire btnL_rising = btnL_sync[1] & ~btnL_sync[0];

  // Input state machine
  always @(posedge sap1_clk or posedge sys_reset) begin
    if (sys_reset) begin
      input_state <= IDLE;
      selected_prog <= 0;
      input_A <= 0;
      input_B <= 0;
      write_addr <= 0;
      write_en <= 0;
      song_number <= 0;
      write_done_internal <= 0;
      write_counter <= 0;
      write_busy <= 0;
    end else begin
      case (input_state)
        IDLE: begin
          if (btnR_rising) begin
            input_state <= SELECT_PROG;
          end
        end
        SELECT_PROG: begin
          if (btnR_rising) begin
            // Read switches and select operation HERE
            if (sw_stable[13]) begin
              selected_prog <= 3'b100;
              song_number <= sw_stable[5:2];
              input_state <= WRITE_RAM;
              write_busy <= 1;
              write_counter <= 0;
              write_en <= 1;
              write_addr <= 0;
            end else begin
              selected_prog <= (sw_stable[15:14] == 2'b10) ? 3'b010 : 3'b001;
              input_state <= INPUT_A;
            end
          end
          if (btnL_rising) input_state <= IDLE;
        end
        INPUT_A: begin
          if (btnR_rising) begin
            input_A <= sw_stable[7:0];
            input_state <= INPUT_B;
          end
          if (btnL_rising) input_state <= SELECT_PROG;
        end
        INPUT_B: begin
          if (btnR_rising) begin
            input_B <= sw_stable[7:0];
            input_state <= WRITE_RAM;
            write_busy <= 1;
            write_counter <= 0;
            write_en <= 1;
            write_addr <= 0;
          end
          if (btnL_rising) input_state <= INPUT_A;
        end
        WRITE_RAM: begin
          if (write_busy) begin
            if (selected_prog == 3'b100) begin // SNG
              if (write_counter == 0) begin
                write_addr <= 0;
                write_en <= 1;
                input_state <= WRITE_WAIT;
                write_counter <= 1;
              end else if (write_counter == 1) begin
                write_addr <= 1;
                write_en <= 1;
                input_state <= WRITE_WAIT;
                write_counter <= 2;
              end else begin
                write_en <= 0;
                write_busy <= 0;
                write_done_internal <= 1;
                input_state <= EXECUTE;
                write_counter <= 0;
              end
            end else begin // ADD or SUB
              if (write_counter == 0) begin
                write_addr <= 0;
                write_en <= 1;
                input_state <= WRITE_WAIT;
                write_counter <= 1;
              end else if (write_counter == 1) begin
                write_addr <= 1;
                write_en <= 1;
                input_state <= WRITE_WAIT;
                write_counter <= 2;
              end else if (write_counter == 2) begin
                write_addr <= 2;
                write_en <= 1;
                input_state <= WRITE_WAIT;
                write_counter <= 3;
              end else if (write_counter == 3) begin
                write_addr <= 3;
                write_en <= 1;
                input_state <= WRITE_WAIT;
                write_counter <= 4;
              end else if (write_counter == 4) begin
                write_addr <= 4;
                write_en <= 1;
                input_state <= WRITE_WAIT;
                write_counter <= 5;
              end else if (write_counter == 5) begin
                write_addr <= 14;
                write_en <= 1;
                input_state <= WRITE_WAIT;
                write_counter <= 6;
              end else if (write_counter == 6) begin
                write_addr <= 15;
                write_en <= 1;
                input_state <= WRITE_WAIT;
                write_counter <= 7;
              end else begin
                write_en <= 0;
                write_busy <= 0;
                write_done_internal <= 1;
                input_state <= EXECUTE;
                write_counter <= 0;
              end
            end
          end
        end
        WRITE_WAIT: begin
          write_en <= 0;
          input_state <= WRITE_RAM;
        end
        EXECUTE: begin
          if (halt) begin
            // When halted, stay in EXECUTE state but don't reset anything
            // This prevents the system from restarting
            // User must press btnC (reset) to start over
          end else if (btnL_rising) begin
            // Only allow manual exit with btnL when not halted
            input_state <= IDLE;
            write_done_internal <= 0;
            write_en <= 0;
            write_busy <= 0;
            write_counter <= 0;
          end
        end
        default: begin
          input_state <= IDLE;
          write_done_internal <= 0;
          write_en <= 0;
          write_busy <= 0;
          write_counter <= 0;
        end
      endcase
    end
  end

  // SPI timing
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
  wire spi_start = spi_delay[1] && (input_state == EXECUTE) && !halt && !spi_sending;

  // Latch SPI data - now includes overflow and underflow flags  
  reg [39:0] spi_data_latched;
  always @(posedge clk or posedge sys_reset) begin
    if (sys_reset) begin
      spi_data_latched <= 40'b0;
    end else if (spi_delay[1]) begin
      spi_data_latched <= {a_out, b_out, acc_out[7:0], {4'b0, pc_out}, overflow, underflow, sng_en, operand[3:0], state};
    end
  end

  // Bus multiplexer
  assign bus = mem_en ? ram_bus_out :
               pc_en ? pc_bus_out :
               ir_en ? ir_bus_out :
               a_en ? a_bus_out :
               alu_en ? alu_bus_out : 8'b0;

  // LEDs
  assign led = {
    bus_conflict,
    ir_load,
    opcode[1:0],
    write_done,
    btnR_rising,
    acc_load,
    a_load,
    b_load,
    write_en,
    halt,
    sap1_clk,
    input_state[1:0]
  };

  // SAP-1 Modules
  program_counter pc_inst (
      .clk(sap1_clk),
      .reset(sys_reset),
      .hlt(halt),
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
      .operand(operand),
      .execute(input_state == EXECUTE),
      .out({
        sng_en,        // [15]
        hlt,           // [14] - this is now the direct control signal
        pc_inc,        // [13]
        pc_en,         // [12]
        mar_load,      // [11]
        mem_en,        // [10]
        ir_load,       // [9]
        ir_en,         // [8]
        a_load,        // [7]
        a_en,          // [6]
        b_load,        // [5]
        alu_sub,       // [4]
        alu_en,        // [3]
        acc_load,      // [2]
        acc_reg_load,  // [1]
        acc_reg_en     // [0]
      }),
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
      .acc_out(acc_out),
      .overflow(overflow),
      .underflow(underflow),
      .alu_bus_out(alu_bus_out)
  );

  // Add accumulator register
  acc_register acc_reg_inst (
      .clk(sap1_clk),
      .reset(sys_reset),
      .acc_reg_load(acc_reg_load),
      .acc_reg_en(acc_reg_en),
      .acc_in(acc_out),
      .acc_reg_out(acc_reg_out)
  );

  spi_master spi_inst (
      .clk(clk),
      .reset(sys_reset),
      .start(spi_start),
      .data_in(spi_data_latched),
      .sclk(sclk),
      .mosi(mosi),
      .cs_n(cs_n),
      .sending(spi_sending)
  );

  clk_divider clk_div_inst (
      .clk(clk),
      .clk_reset(sys_reset),
      .btnL(btnL_rising),
      .halt(halt),
      .sap1_clk(sap1_clk)
  );

  switch_debouncer sw_debounce_inst (
      .clk(clk),
      .reset(sys_reset),
      .sw(sw),
      .sw_stable(sw_stable)
  );

  seven_segment_display seg_display_inst (
      .clk(clk),
      .reset(sys_reset),
      .halt(halt),
      .opcode(opcode),
      .input_state(input_state),
      .overflow(overflow),
      .underflow(underflow),
      .acc_out(acc_out[15:0]),  // Pass full 16-bit accumulator
      .seg(seg),
      .an(an)
  );
endmodule

module controller (
    input wire clk,
    input wire rst,
    input wire [3:0] opcode,
    input wire [3:0] operand,
    input wire execute,
    output wire [15:0] out,
    output reg [2:0] state
);
    localparam SIG_SNG_EN      = 15;
    localparam SIG_HLT         = 14;
    localparam SIG_PC_INC      = 13;
    localparam SIG_PC_EN       = 12;
    localparam SIG_MEM_LOAD    = 11;
    localparam SIG_MEM_EN      = 10;
    localparam SIG_IR_LOAD     = 9;
    localparam SIG_IR_EN       = 8;
    localparam SIG_A_LOAD      = 7;
    localparam SIG_A_EN        = 6;
    localparam SIG_B_LOAD      = 5;
    localparam SIG_ADDER_SUB   = 4;
    localparam SIG_ADDER_EN    = 3;
    localparam SIG_ACC_LOAD    = 2;
    localparam SIG_ACC_REG_LOAD = 1;
    localparam SIG_ACC_REG_EN   = 0;

    // Traditional SAP-1 opcodes - clean and working
    localparam OP_LDA = 4'h0;  // Load memory into A register
    localparam OP_ADD = 4'h1;  // Load memory into B register and add A+B
    localparam OP_SUB = 4'h2;  // Load memory into B register and subtract A-B
    localparam OP_SNG = 4'h3;  // Play song
    localparam OP_OUT = 4'hE;  // Output accumulator
    localparam OP_HLT = 4'hF;  // Halt

    reg [15:0] ctrl_word;

    always @(negedge clk or posedge rst) begin
        if (rst) begin
            state <= 0;
        end else if (execute && !ctrl_word[SIG_HLT]) begin  // Only advance if not executing HLT
            if (state == 5) state <= 0;
            else state <= state + 1;
        end
        // When ctrl_word[SIG_HLT] is true, state machine stops advancing
    end

    always @(*) begin
        ctrl_word = 16'b0;

        if (execute) begin
            case (state)
                0: begin
                    ctrl_word[SIG_PC_EN] = 1;
                    ctrl_word[SIG_MEM_LOAD] = 1;
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
                        OP_LDA: begin
                            ctrl_word[SIG_IR_EN] = 1;
                            ctrl_word[SIG_MEM_LOAD] = 1;
                        end
                        OP_ADD: begin
                            ctrl_word[SIG_IR_EN] = 1;
                            ctrl_word[SIG_MEM_LOAD] = 1;
                        end
                        OP_SUB: begin
                            ctrl_word[SIG_IR_EN] = 1;
                            ctrl_word[SIG_MEM_LOAD] = 1;
                        end
                        OP_SNG: begin
                            ctrl_word[SIG_SNG_EN] = 1;
                        end
                        OP_OUT: begin
                            ctrl_word[SIG_ADDER_EN] = 1;  // Only output, don't load
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
                        OP_ADD: begin
                            ctrl_word[SIG_MEM_EN] = 1;
                            ctrl_word[SIG_B_LOAD] = 1;
                        end
                        OP_SUB: begin
                            ctrl_word[SIG_MEM_EN] = 1;
                            ctrl_word[SIG_B_LOAD] = 1;
                        end
                    endcase
                end
                5: begin
                    case (opcode)
                        OP_ADD: begin
                            ctrl_word[SIG_ADDER_EN] = 1;
                            ctrl_word[SIG_ACC_LOAD] = 1;
                        end
                        OP_SUB: begin
                            ctrl_word[SIG_ADDER_SUB] = 1;
                            ctrl_word[SIG_ADDER_EN] = 1;
                            ctrl_word[SIG_ACC_LOAD] = 1;
                        end
                    endcase
                end
            endcase
        end
    end

    assign out = ctrl_word;
endmodule

// Simplified accumulator register module
module acc_register (
    input wire clk,
    input wire reset,
    input wire acc_reg_load,
    input wire acc_reg_en,
    input wire [15:0] acc_in,  // Expanded to 16 bits
    output reg [15:0] acc_reg_out  // Expanded to 16 bits
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            acc_reg_out <= 16'h0000;
        end else if (acc_reg_load) begin
            acc_reg_out <= acc_in;
        end
    end
endmodule

module clk_divider (
    input wire clk,
    input wire clk_reset,
    input wire btnL,
    input wire halt,
    output reg sap1_clk
);
    reg [25:0] clk_counter;
    reg sap1_clk_raw;

    always @(posedge clk or posedge clk_reset) begin
        if (clk_reset) begin
            clk_counter <= 0;
            sap1_clk_raw <= 0;
            sap1_clk <= 0;
        end else if (!halt) begin
            clk_counter <= clk_counter + 1;
            if (clk_counter == 26'd49_999_999) begin
                clk_counter <= 0;
                sap1_clk_raw <= ~sap1_clk_raw;
                sap1_clk <= sap1_clk_raw;
            end
        end
    end
endmodule

module switch_debouncer (
    input wire clk,
    input wire reset,
    input wire [15:0] sw,
    output reg [15:0] sw_stable
);
    reg [19:0] debounce_counter[15:0];
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
    input wire clk,
    input wire reset,
    input wire halt,
    input wire [3:0] opcode,
    input wire [2:0] input_state,
    input wire overflow,
    input wire underflow,
    input wire [15:0] acc_out,  // Now 16-bit to handle larger values
    output reg [6:0] seg,
    output reg [3:0] an
);
    localparam [6:0] SEG_0 = 7'b0111111;
    localparam [6:0] SEG_1 = 7'b0000110;
    localparam [6:0] SEG_2 = 7'b1011011;
    localparam [6:0] SEG_3 = 7'b1001111;
    localparam [6:0] SEG_4 = 7'b1100110;
    localparam [6:0] SEG_5 = 7'b1101101;
    localparam [6:0] SEG_6 = 7'b1111101;
    localparam [6:0] SEG_7 = 7'b0000111;
    localparam [6:0] SEG_8 = 7'b1111111;
    localparam [6:0] SEG_9 = 7'b1101111;
    localparam [6:0] SEG_A = 7'b1110111;
    localparam [6:0] SEG_B = 7'b1111100;
    localparam [6:0] SEG_C = 7'b0111001;
    localparam [6:0] SEG_D = 7'b1011110;
    localparam [6:0] SEG_E = 7'b1111001;
    localparam [6:0] SEG_F = 7'b1110001;
    localparam [6:0] SEG_I = 7'b0110000;
    localparam [6:0] SEG_L = 7'b0111000;
    localparam [6:0] SEG_S = 7'b1101101;
    localparam [6:0] SEG_X = 7'b1110110;
    localparam [6:0] SEG_O = 7'b0111111;
    localparam [6:0] SEG_U = 7'b0111110;
    localparam [6:0] SEG_N = 7'b1010100;
    localparam [6:0] SEG_R = 7'b1010000;
    localparam [6:0] SEG_MINUS = 7'b1000000;
    localparam [6:0] SEG_OFF = 7'b0000000;

    localparam [2:0] IDLE = 3'd0, SELECT_PROG = 3'd1, INPUT_A = 3'd2, INPUT_B = 3'd3, EXECUTE = 3'd5;

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

    // Function to convert digit to 7-segment
    function [6:0] digit_to_7seg;
        input [3:0] digit;
        begin
            case (digit)
                4'h0: digit_to_7seg = SEG_0;
                4'h1: digit_to_7seg = SEG_1;
                4'h2: digit_to_7seg = SEG_2;
                4'h3: digit_to_7seg = SEG_3;
                4'h4: digit_to_7seg = SEG_4;
                4'h5: digit_to_7seg = SEG_5;
                4'h6: digit_to_7seg = SEG_6;
                4'h7: digit_to_7seg = SEG_7;
                4'h8: digit_to_7seg = SEG_8;
                4'h9: digit_to_7seg = SEG_9;
                4'hA: digit_to_7seg = SEG_A;
                4'hB: digit_to_7seg = SEG_B;
                4'hC: digit_to_7seg = SEG_C;
                4'hD: digit_to_7seg = SEG_D;
                4'hE: digit_to_7seg = SEG_E;
                4'hF: digit_to_7seg = SEG_F;
                default: digit_to_7seg = SEG_OFF;
            endcase
        end
    endfunction

    always @(*) begin
        if (reset) begin
            digit0 <= SEG_OFF;
            digit1 <= SEG_OFF;
            digit2 <= SEG_OFF;
            digit3 <= SEG_OFF;
        end else if (halt && (overflow || underflow)) begin
            // Show overflow/underflow condition when halted
            if (overflow) begin
                digit3 <= SEG_O;      // O
                digit2 <= SEG_F;      // F
                digit1 <= SEG_L;      // L
                digit0 <= SEG_O;      // O (OFLO)
            end else if (underflow) begin
                digit3 <= SEG_MINUS;  // -
                digit2 <= digit_to_7seg(acc_out / 100);          // Hundreds digit
                digit1 <= digit_to_7seg((acc_out / 10) % 10);    // Tens digit  
                digit0 <= digit_to_7seg(acc_out % 10);           // Units digit
            end
        end else if (halt) begin
            // Show result when halted (normal case)
            if (acc_out >= 1000) begin
                // 4-digit display: 1000-9999
                digit3 <= digit_to_7seg(acc_out / 1000);
                digit2 <= digit_to_7seg((acc_out / 100) % 10);
                digit1 <= digit_to_7seg((acc_out / 10) % 10);
                digit0 <= digit_to_7seg(acc_out % 10);
            end else if (acc_out >= 100) begin
                // 3-digit display: 100-999
                digit3 <= SEG_OFF;
                digit2 <= digit_to_7seg(acc_out / 100);
                digit1 <= digit_to_7seg((acc_out / 10) % 10);
                digit0 <= digit_to_7seg(acc_out % 10);
            end else if (acc_out >= 10) begin
                // 2-digit display: 10-99
                digit3 <= SEG_OFF;
                digit2 <= SEG_OFF;
                digit1 <= digit_to_7seg(acc_out / 10);
                digit0 <= digit_to_7seg(acc_out % 10);
            end else begin
                // 1-digit display: 0-9
                digit3 <= SEG_OFF;
                digit2 <= SEG_OFF;
                digit1 <= SEG_OFF;
                digit0 <= digit_to_7seg(acc_out);
            end
        end else begin
            // Show current state when not halted
            case (input_state)
                IDLE: begin
                    digit3 <= SEG_I;
                    digit2 <= SEG_D;
                    digit1 <= SEG_L;
                    digit0 <= SEG_E;
                end
                SELECT_PROG: begin
                    digit3 <= SEG_S;
                    digit2 <= SEG_E;
                    digit1 <= SEG_L;
                    digit0 <= SEG_OFF;
                end
                INPUT_A: begin
                    digit3 <= SEG_OFF;
                    digit2 <= SEG_OFF;
                    digit1 <= SEG_OFF;
                    digit0 <= SEG_A;
                end
                INPUT_B: begin
                    digit3 <= SEG_OFF;
                    digit2 <= SEG_OFF;
                    digit1 <= SEG_OFF;
                    digit0 <= SEG_B;
                end
                EXECUTE: begin
                    digit3 <= SEG_E;
                    digit2 <= SEG_X;
                    digit1 <= SEG_E;
                    digit0 <= SEG_C;
                end
                default: begin
                    digit0 <= SEG_OFF;
                    digit1 <= SEG_OFF;
                    digit2 <= SEG_OFF;
                    digit3 <= SEG_OFF;
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
    input wire clk,
    input wire reset,
    input wire hlt,
    input wire pc_inc,
    input wire pc_en,
    output reg [3:0] pc_out,
    output wire [7:0] pc_bus_out
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc_out <= 0;
        end else if (!hlt && pc_inc) begin
            pc_out <= pc_out + 1;
            // Prevent PC from going beyond program memory
            if (pc_out >= 4'd15) begin
                pc_out <= 4'd15;  // Stay at last address when halted
            end
        end
    end
    assign pc_bus_out = pc_en ? {4'b0, pc_out} : 8'b0;
endmodule

module mar (
    input wire clk,
    input wire reset,
    input wire mar_load,
    input wire [3:0] bus,
    output reg [3:0] mar_out
);
    always @(posedge clk or posedge reset) begin
        if (reset) mar_out <= 0;
        else if (mar_load) mar_out <= bus;
    end
endmodule

module ram (
    input wire clk,
    input wire reset,
    input wire write_en,
    input wire [3:0] write_addr,
    input wire [2:0] selected_prog,
    input wire [7:0] input_A,
    input wire [7:0] input_B,
    input wire [3:0] song_number,
    input wire [3:0] addr,
    input wire mem_en,
    output reg [7:0] ram_bus_out
);
    reg [7:0] ram[0:15];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            integer i;
            for (i = 0; i < 16; i = i + 1) ram[i] <= 8'h00;
        end else if (write_en) begin
            if (selected_prog == 3'b100) begin // SNG
                case (write_addr)
                    0: ram[0] <= {4'h3, song_number};
                    1: ram[1] <= 8'hF0;
                endcase
            end else begin // ADD or SUB
                case (write_addr)
                    0: ram[0] <= 8'h0F; // LDA 15 (Load from memory[15] into A register)
                    1: ram[1] <= (selected_prog == 3'b001) ? 8'h1E : 8'h2E; // ADD 14 or SUB 14
                    2: ram[2] <= 8'hE0; // OUT (Display accumulator result)
                    3: ram[3] <= 8'h30; // SNG 0 (Play completion sound)
                    4: ram[4] <= 8'hF0; // HLT (Halt execution)
                    14: ram[14] <= input_B;  // Memory[14] = B value
                    15: ram[15] <= input_A;  // Memory[15] = A value
                endcase
            end
        end
    end

    always @(*) begin
        ram_bus_out = mem_en ? ram[addr] : 8'b0;
    end
endmodule

module instruction_reg (
    input wire clk,
    input wire reset,
    input wire ir_load,
    input wire ir_en,
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

module reg_a (
    input wire clk,
    input wire reset,
    input wire a_load,
    input wire a_en,
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
    input wire clk,
    input wire reset,
    input wire b_load,
    input wire [7:0] bus,
    output reg [7:0] b_out
);
    always @(posedge clk or posedge reset) begin
        if (reset) b_out <= 0;
        else if (b_load) b_out <= bus;
    end
endmodule

module ALU (
    input wire clk,
    input wire reset,
    input wire [7:0] a,
    input wire [7:0] b,
    input wire sub,
    input wire en,
    input wire load,
    output reg [15:0] acc_out,  // Expanded to 16 bits for larger results
    output reg overflow,
    output reg underflow,
    output wire [7:0] alu_bus_out
);
    wire [15:0] sum = a + b;  // 16-bit sum can handle 255+255=510
    wire signed [15:0] signed_diff = $signed({8'b0, a}) - $signed({8'b0, b});
    wire diff_underflow = (sub && signed_diff < 0);
    wire sum_overflow = (sum > 9999);  // 4-digit display overflow (0-9999)
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            acc_out <= 0;
            overflow <= 0;
            underflow <= 0;
        end else if (load) begin
            if (sub) begin
                if (diff_underflow) begin
                    // Store the absolute value for display, but keep underflow flag
                    acc_out <= (-signed_diff);  // Store positive equivalent 
                    underflow <= 1;
                    overflow <= 0;
                end else begin
                    acc_out <= signed_diff;
                    underflow <= 0;
                    overflow <= 0;
                end
            end else begin  // Addition
                if (sum_overflow) begin
                    acc_out <= 16'h270F;  // 9999 in hex (max 4-digit display)
                    overflow <= 1;
                    underflow <= 0;
                end else begin
                    acc_out <= sum;  // Store full 16-bit result (0-510 range)
                    overflow <= 0;
                    underflow <= 0;
                end
            end
        end
        // Keep the value when not loading
    end
    // Bus output only uses lower 8 bits for compatibility
    assign alu_bus_out = en ? acc_out[7:0] : 8'b0;
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
    parameter CLK_DIV = 100;
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
