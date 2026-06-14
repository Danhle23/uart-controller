// =====================================================================
// uart_tx.sv  -  Parameterized UART transmitter
// FSM: IDLE -> START -> DATA(0..N-1) -> STOP -> IDLE
// Author: Grimm
// =====================================================================
`timescale 1ns/1ps

module uart_tx #(
    parameter int CLK_FREQ  = 50_000_000,  // system clock in Hz
    parameter int BAUD_RATE = 115_200,     // baud rate in bps
    parameter int DATA_BITS = 8
)(
    input  logic                 clk,
    input  logic                 rst_n,     // active-low async reset
    input  logic                 tx_start,  // pulse high to start a transfer
    input  logic [DATA_BITS-1:0] tx_data,   // byte to transmit
    output logic                 tx,        // serial output line
    output logic                 tx_busy    // high while a frame is in flight
);

    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t state;

    logic [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;
    logic [$clog2(DATA_BITS)-1:0]    bit_idx;
    logic [DATA_BITS-1:0]            shift_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            tx        <= 1'b1;          // line idles high
            tx_busy   <= 1'b0;
            clk_cnt   <= '0;
            bit_idx   <= '0;
            shift_reg <= '0;
        end else begin
            case (state)
                // ------------------------------------------------------
                IDLE: begin
                    tx      <= 1'b1;
                    tx_busy <= 1'b0;
                    clk_cnt <= '0;
                    bit_idx <= '0;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        tx_busy   <= 1'b1;
                        state     <= START;
                    end
                end
                // ------------------------------------------------------
                START: begin            // drive the start bit (low)
                    tx <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= '0;
                        state   <= DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                // ------------------------------------------------------
                DATA: begin             // shift out LSB first
                    tx <= shift_reg[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= '0;
                        if (bit_idx == DATA_BITS-1) begin
                            bit_idx <= '0;
                            state   <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                // ------------------------------------------------------
                STOP: begin             // drive the stop bit (high)
                    tx <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= '0;
                        tx_busy <= 1'b0;
                        state   <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                // ------------------------------------------------------
                default: state <= IDLE;
            endcase
        end
    end

endmodule
