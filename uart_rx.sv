// =====================================================================
// uart_rx.sv - Parameterized UART Receiver with 2-FF CDC, Mid-Bit
// Sampling, Parity Checking & Framing Error Detection
// Author: Le Thanh Danh (Danhle23)
// =====================================================================
`timescale 1ns/1ps

module uart_rx #(
    parameter int CLK_FREQ   = 50_000_000,
    parameter int BAUD_RATE  = 115_200,
    parameter int DATA_BITS  = 8,
    parameter int DIV_WIDTH  = 16
)(
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 rx,
    input  logic [DIV_WIDTH-1:0] cfg_clk_div, // 0 => use default CLK_FREQ/BAUD_RATE
    input  logic                 parity_en,
    input  logic                 parity_odd,
    output logic [DATA_BITS-1:0] rx_data,
    output logic                 rx_valid,
    output logic                 parity_err,
    output logic                 framing_err
);

    localparam [DIV_WIDTH-1:0] DEFAULT_DIV = (CLK_FREQ / BAUD_RATE) > 2 ? (CLK_FREQ / BAUD_RATE) : 4;

    typedef enum logic [2:0] {IDLE, START, DATA, PARITY, STOP} state_t;
    state_t state;

    // 2-stage metastability synchronizer for async RX input
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

    logic [DIV_WIDTH-1:0]         active_div;
    logic [DIV_WIDTH-1:0]         clk_cnt;
    logic [$clog2(DATA_BITS)-1:0] bit_idx;
    logic [DATA_BITS-1:0]         shift_reg;
    logic                         sampled_parity;

    wire [DIV_WIDTH-1:0] eff_div = (cfg_clk_div != '0) ? cfg_clk_div : DEFAULT_DIV;
    wire                 exp_par = parity_odd ? ~(^shift_reg) : (^shift_reg);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            rx_valid       <= 1'b0;
            rx_data        <= '0;
            parity_err     <= 1'b0;
            framing_err    <= 1'b0;
            active_div     <= DEFAULT_DIV;
            clk_cnt        <= '0;
            bit_idx        <= '0;
            shift_reg      <= '0;
            sampled_parity <= 1'b0;
        end else begin
            rx_valid    <= 1'b0;
            parity_err  <= 1'b0;
            framing_err <= 1'b0;

            case (state)
                IDLE: begin
                    clk_cnt <= '0;
                    bit_idx <= '0;
                    if (rx_sync_1 == 1'b0) begin
                        active_div <= eff_div;
                        state      <= START;
                    end
                end

                START: begin
                    if (clk_cnt == ((active_div - 1'b1) >> 1)) begin
                        if (rx_sync_1 == 1'b0) begin
                            clk_cnt <= '0;
                            state   <= DATA;
                        end else begin
                            state <= IDLE; // reject false start glitch
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                DATA: begin
                    if (clk_cnt == active_div - 1'b1) begin
                        clk_cnt            <= '0;
                        shift_reg[bit_idx] <= rx_sync_1;
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
                    if (clk_cnt == active_div - 1'b1) begin
                        clk_cnt        <= '0;
                        sampled_parity <= rx_sync_1;
                        state          <= STOP;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                STOP: begin
                    if (clk_cnt == active_div - 1'b1) begin
                        rx_data     <= shift_reg;
                        rx_valid    <= 1'b1;
                        parity_err  <= parity_en && (sampled_parity != exp_par);
                        framing_err <= (rx_sync_1 != 1'b1);
                        clk_cnt     <= '0;
                        state       <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
