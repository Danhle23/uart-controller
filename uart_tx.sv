// =====================================================================
// uart_tx.sv - Parameterized UART Transmitter with Runtime Baud & Parity
// FSM: IDLE -> START -> DATA(0..N-1) -> PARITY(opt) -> STOP -> IDLE
// Author: Le Thanh Danh (Danhle23)
// =====================================================================
`timescale 1ns/1ps

module uart_tx #(
    parameter int CLK_FREQ   = 50_000_000,
    parameter int BAUD_RATE  = 115_200,
    parameter int DATA_BITS  = 8,
    parameter int DIV_WIDTH  = 16
)(
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 tx_start,
    input  logic [DATA_BITS-1:0] tx_data,
    input  logic [DIV_WIDTH-1:0] cfg_clk_div, // 0 => use default CLK_FREQ/BAUD_RATE
    input  logic                 parity_en,
    input  logic                 parity_odd,  // 0: even parity, 1: odd parity
    output logic                 tx,
    output logic                 tx_busy
);

    localparam [DIV_WIDTH-1:0] DEFAULT_DIV = (CLK_FREQ / BAUD_RATE) > 2 ? (CLK_FREQ / BAUD_RATE) : 4;

    typedef enum logic [2:0] {IDLE, START, DATA, PARITY, STOP} state_t;
    state_t state;

    logic [DIV_WIDTH-1:0]         active_div;
    logic [DIV_WIDTH-1:0]         clk_cnt;
    logic [$clog2(DATA_BITS)-1:0] bit_idx;
    logic [DATA_BITS-1:0]         shift_reg;
    logic                         parity_bit;

    wire [DIV_WIDTH-1:0] eff_div = (cfg_clk_div != '0) ? cfg_clk_div : DEFAULT_DIV;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            tx         <= 1'b1;
            tx_busy    <= 1'b0;
            active_div <= DEFAULT_DIV;
            clk_cnt    <= '0;
            bit_idx    <= '0;
            shift_reg  <= '0;
            parity_bit <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    tx      <= 1'b1;
                    tx_busy <= 1'b0;
                    clk_cnt <= '0;
                    bit_idx <= '0;
                    if (tx_start) begin
                        shift_reg  <= tx_data;
                        active_div <= eff_div;
                        parity_bit <= parity_odd ? ~(^tx_data) : (^tx_data);
                        tx_busy    <= 1'b1;
                        state      <= START;
                    end
                end

                START: begin
                    tx <= 1'b0;
                    if (clk_cnt == active_div - 1'b1) begin
                        clk_cnt <= '0;
                        state   <= DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                DATA: begin
                    tx <= shift_reg[bit_idx];
                    if (clk_cnt == active_div - 1'b1) begin
                        clk_cnt <= '0;
                        if (bit_idx == DATA_BITS - 1) begin
                            bit_idx <= '0;
                            state   <= parity_en ? PARITY : STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                PARITY: begin
                    tx <= parity_bit;
                    if (clk_cnt == active_div - 1'b1) begin
                        clk_cnt <= '0;
                        state   <= STOP;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                STOP: begin
                    tx <= 1'b1;
                    if (clk_cnt == active_div - 1'b1) begin
                        clk_cnt <= '0;
                        tx_busy <= 1'b0;
                        state   <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
