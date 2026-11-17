// =====================================================================
// apb_uart.sv - AMBA APB3 Memory-Mapped UART Peripheral IP Core
// Integrates 16x8 TX/RX Synchronous FIFOs, Programmable Baud Divider,
// Parity/Framing/Overrun Error Sticky Flags, Internal Loopback & IRQ.
//
// Register Map (Byte Offsets, 32-bit aligned):
//   0x00 TXDATA   [W]   [7:0]  Push byte into TX FIFO
//   0x04 RXDATA   [R]   [7:0]  Pop byte from RX FIFO
//   0x08 STATUS   [R/W1C] [0] tx_full, [1] tx_empty, [2] rx_full,
//                         [3] rx_empty, [4] tx_busy,
//                         [5] parity_err (W1C), [6] framing_err (W1C),
//                         [7] rx_overrun (W1C)
//   0x0C CTRL     [R/W] [0] tx_en, [1] rx_en, [2] parity_en,
//                       [3] parity_odd, [4] irq_rx_en, [5] irq_tx_en,
//                       [6] loopback_en, [7] fifo_clr (self-clearing)
//   0x10 BAUD_DIV [R/W] [15:0] Clock cycles per bit (CLKS_PER_BIT)
//   0x14 FIFO_LVL [R]   [15:8] rx_count, [7:0] tx_count
//
// Author: Le Thanh Danh (Danhle23)
// =====================================================================
`timescale 1ns/1ps

module apb_uart #(
    parameter int CLK_FREQ   = 50_000_000,
    parameter int BAUD_RATE  = 115_200,
    parameter int FIFO_DEPTH = 16
)(
    input  logic        pclk,
    input  logic        presetn,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [7:0]  paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,

    input  logic        uart_rxd,
    output logic        uart_txd,
    output logic        irq
);

    localparam [15:0] DEFAULT_DIV = (CLK_FREQ / BAUD_RATE) > 2 ? (CLK_FREQ / BAUD_RATE) : 8;

    assign pready  = 1'b1; // Zero-wait-state APB3 slave
    assign pslverr = 1'b0;

    wire apb_write = psel && penable && pwrite;
    wire apb_read  = psel && penable && !pwrite;

    // Configuration registers
    logic        ctrl_tx_en, ctrl_rx_en, ctrl_parity_en, ctrl_parity_odd;
    logic        ctrl_irq_rx_en, ctrl_irq_tx_en, ctrl_loopback;
    logic        fifo_clr_pulse;
    logic [15:0] reg_baud_div;

    // Sticky error status flags (Write-1-to-Clear)
    logic sticky_parity_err, sticky_framing_err, sticky_rx_overrun;

    // TX FIFO signals
    logic                        tx_fifo_wr, tx_fifo_rd;
    logic [7:0]                  tx_fifo_dout;
    logic                        tx_fifo_full, tx_fifo_empty;
    logic [$clog2(FIFO_DEPTH):0] tx_fifo_cnt;

    // RX FIFO signals
    logic                        rx_fifo_wr, rx_fifo_rd;
    logic [7:0]                  rx_fifo_dout;
    logic                        rx_fifo_full, rx_fifo_empty;
    logic [$clog2(FIFO_DEPTH):0] rx_fifo_cnt;

    // UART engine signals
    logic       tx_start_pulse, tx_busy;
    logic [7:0] tx_byte_latched;
    logic [7:0] rx_byte_wire;
    logic       rx_valid_wire, rx_par_err_wire, rx_frm_err_wire;
    wire        serial_rx_mux = ctrl_loopback ? uart_txd : uart_rxd;

    assign tx_fifo_wr = apb_write && (paddr[7:2] == 6'h00) && ctrl_tx_en;
    assign rx_fifo_rd = apb_read  && (paddr[7:2] == 6'h01);

    // Pop TX FIFO into UART TX engine whenever idle and data available
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            tx_start_pulse  <= 1'b0;
            tx_fifo_rd      <= 1'b0;
            tx_byte_latched <= 8'h00;
        end else begin
            tx_start_pulse <= 1'b0;
            tx_fifo_rd     <= 1'b0;
            if (ctrl_tx_en && !tx_fifo_empty && !tx_busy && !tx_start_pulse && !tx_fifo_rd) begin
                tx_byte_latched <= tx_fifo_dout;
                tx_fifo_rd      <= 1'b1;
                tx_start_pulse  <= 1'b1;
            end
        end
    end

    assign rx_fifo_wr = rx_valid_wire && ctrl_rx_en && !rx_fifo_full;

    sync_fifo #(.DATA_WIDTH(8), .DEPTH(FIFO_DEPTH)) u_tx_fifo (
        .clk     (pclk),
        .rst_n   (presetn),
        .clr     (fifo_clr_pulse),
        .wr_en   (tx_fifo_wr),
        .wr_data (pwdata[7:0]),
        .rd_en   (tx_fifo_rd),
        .rd_data (tx_fifo_dout),
        .full    (tx_fifo_full),
        .empty   (tx_fifo_empty),
        .count   (tx_fifo_cnt)
    );

    sync_fifo #(.DATA_WIDTH(8), .DEPTH(FIFO_DEPTH)) u_rx_fifo (
        .clk     (pclk),
        .rst_n   (presetn),
        .clr     (fifo_clr_pulse),
        .wr_en   (rx_fifo_wr),
        .wr_data (rx_byte_wire),
        .rd_en   (rx_fifo_rd),
        .rd_data (rx_fifo_dout),
        .full    (rx_fifo_full),
        .empty   (rx_fifo_empty),
        .count   (rx_fifo_cnt)
    );

    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .DATA_BITS(8)
    ) u_tx (
        .clk        (pclk),
        .rst_n      (presetn),
        .tx_start   (tx_start_pulse),
        .tx_data    (tx_byte_latched),
        .cfg_clk_div(reg_baud_div),
        .parity_en  (ctrl_parity_en),
        .parity_odd (ctrl_parity_odd),
        .tx         (uart_txd),
        .tx_busy    (tx_busy)
    );

    uart_rx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .DATA_BITS(8)
    ) u_rx (
        .clk        (pclk),
        .rst_n      (presetn),
        .rx         (serial_rx_mux),
        .cfg_clk_div(reg_baud_div),
        .parity_en  (ctrl_parity_en),
        .parity_odd (ctrl_parity_odd),
        .rx_data    (rx_byte_wire),
        .rx_valid   (rx_valid_wire),
        .parity_err (rx_par_err_wire),
        .framing_err(rx_frm_err_wire)
    );

    // APB Write & Sticky Status Logic
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            ctrl_tx_en         <= 1'b1;
            ctrl_rx_en         <= 1'b1;
            ctrl_parity_en     <= 1'b0;
            ctrl_parity_odd    <= 1'b0;
            ctrl_irq_rx_en     <= 1'b0;
            ctrl_irq_tx_en     <= 1'b0;
            ctrl_loopback      <= 1'b0;
            fifo_clr_pulse     <= 1'b0;
            reg_baud_div       <= DEFAULT_DIV;
            sticky_parity_err  <= 1'b0;
            sticky_framing_err <= 1'b0;
            sticky_rx_overrun  <= 1'b0;
        end else begin
            fifo_clr_pulse <= 1'b0;

            if (rx_valid_wire && ctrl_rx_en) begin
                if (rx_par_err_wire) sticky_parity_err  <= 1'b1;
                if (rx_frm_err_wire) sticky_framing_err <= 1'b1;
                if (rx_fifo_full)    sticky_rx_overrun  <= 1'b1;
            end

            if (apb_write) begin
                case (paddr[7:2])
                    6'h02: begin // 0x08 STATUS (W1C bits [7:5])
                        if (pwdata[5]) sticky_parity_err  <= 1'b0;
                        if (pwdata[6]) sticky_framing_err <= 1'b0;
                        if (pwdata[7]) sticky_rx_overrun  <= 1'b0;
                    end
                    6'h03: begin // 0x0C CTRL
                        ctrl_tx_en      <= pwdata[0];
                        ctrl_rx_en      <= pwdata[1];
                        ctrl_parity_en  <= pwdata[2];
                        ctrl_parity_odd <= pwdata[3];
                        ctrl_irq_rx_en  <= pwdata[4];
                        ctrl_irq_tx_en  <= pwdata[5];
                        ctrl_loopback   <= pwdata[6];
                        fifo_clr_pulse  <= pwdata[7];
                    end
                    6'h04: begin // 0x10 BAUD_DIV
                        reg_baud_div <= pwdata[15:0];
                    end
                    default: ;
                endcase
            end
        end
    end

    wire [7:0] rx_cnt_u8 = {{(8 - ($clog2(FIFO_DEPTH)+1)){1'b0}}, rx_fifo_cnt};
    wire [7:0] tx_cnt_u8 = {{(8 - ($clog2(FIFO_DEPTH)+1)){1'b0}}, tx_fifo_cnt};

    // APB Read Mux (Combinational during SETUP/ACCESS)
    always_comb begin
        prdata = 32'h0000_0000;
        if (psel && !pwrite) begin
            case (paddr[7:2])
                6'h01: prdata = {24'h0, rx_fifo_dout};
                6'h02: prdata = {24'h0, sticky_rx_overrun, sticky_framing_err,
                                 sticky_parity_err, tx_busy, rx_fifo_empty,
                                 rx_fifo_full, tx_fifo_empty, tx_fifo_full};
                6'h03: prdata = {25'h0, ctrl_loopback, ctrl_irq_tx_en,
                                 ctrl_irq_rx_en, ctrl_parity_odd,
                                 ctrl_parity_en, ctrl_rx_en, ctrl_tx_en};
                6'h04: prdata = {16'h0, reg_baud_div};
                6'h05: prdata = {16'h0, rx_cnt_u8, tx_cnt_u8};
                default: prdata = 32'h0000_0000;
            endcase
        end
    end

    assign irq = (ctrl_irq_rx_en && !rx_fifo_empty) ||
                 (ctrl_irq_tx_en && tx_fifo_empty && !tx_busy);

    // Tie off unused upper/alignment APB bits cleanly for strict RTL lint
    wire _unused_apb = &{1'b0, paddr[1:0], pwdata[31:8], 1'b0};

endmodule
