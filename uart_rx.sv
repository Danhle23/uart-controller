// =====================================================================
// uart_rx.sv  -  Parameterized UART receiver
// Two-flop synchronizer on the async rx line + mid-bit sampling
// for noise immunity. FSM: IDLE -> START -> DATA -> STOP -> IDLE
// Author: Grimm
// =====================================================================
`timescale 1ns/1ps

module uart_rx #(
    parameter int CLK_FREQ  = 50_000_000,
    parameter int BAUD_RATE = 115_200,
    parameter int DATA_BITS = 8
)(
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 rx,        // asynchronous serial input
    output logic [DATA_BITS-1:0] rx_data,   // received byte
    output logic                 rx_valid   // 1-clock pulse when byte ready
);

    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t state;

    // -----------------------------------------------------------------
    // Two-flop synchronizer: defends against metastability because rx
    // is asynchronous to clk.
    // -----------------------------------------------------------------
    logic rx_sync_0, rx_sync_1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync_0 <= 1'b1;
            rx_sync_1 <= 1'b1;
        end else begin
            rx_sync_0 <= rx;
            rx_sync_1 <= rx_sync_0;
        end
    end

    logic [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;
    logic [$clog2(DATA_BITS)-1:0]    bit_idx;
    logic [DATA_BITS-1:0]            shift_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            rx_valid  <= 1'b0;
            rx_data   <= '0;
            clk_cnt   <= '0;
            bit_idx   <= '0;
            shift_reg <= '0;
        end else begin
            rx_valid <= 1'b0;           // default: deassert each cycle
            case (state)
                // ------------------------------------------------------
                IDLE: begin
                    clk_cnt <= '0;
                    bit_idx <= '0;
                    if (rx_sync_1 == 1'b0) // falling edge = start bit
                        state <= START;
                end
                // ------------------------------------------------------
                START: begin            // sample at the MIDDLE of start bit
                    if (clk_cnt == (CLKS_PER_BIT-1)/2) begin
                        if (rx_sync_1 == 1'b0) begin
                            clk_cnt <= '0;
                            state   <= DATA;
                        end else begin
                            state <= IDLE;   // glitch, not a real start
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                // ------------------------------------------------------
                DATA: begin             // sample one full bit later each time
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt            <= '0;
                        shift_reg[bit_idx] <= rx_sync_1;
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
                STOP: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        rx_data  <= shift_reg;
                        rx_valid <= 1'b1;   // one-clock data-ready strobe
                        clk_cnt  <= '0;
                        state    <= IDLE;
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
