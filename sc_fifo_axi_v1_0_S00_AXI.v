`timescale 1ns / 1ps

module sc_fifo_axi_v1_0_S00_AXI #(
    parameter integer WIDTH = 16,
    parameter integer DEPTH = 32,
    parameter integer ALMOST_EMPTY_THRESHOLD = 1,
    parameter integer ALMOST_FULL_THRESHOLD = 31,
    parameter integer READ_LATENCY = 1,
    parameter integer ADDR_WIDTH = $clog2(DEPTH),
    parameter integer COUNT_WIDTH = $clog2(DEPTH + 1),
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6
)(
    input wire S_AXI_ACLK,
    input wire S_AXI_ARESETN,

    input wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input wire [2:0] S_AXI_AWPROT,
    input wire S_AXI_AWVALID,
    output wire S_AXI_AWREADY,

    input wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_WDATA,
    input wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input wire S_AXI_WVALID,
    output wire S_AXI_WREADY,

    output wire [1:0] S_AXI_BRESP,
    output wire S_AXI_BVALID,
    input wire S_AXI_BREADY,

    input wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input wire [2:0] S_AXI_ARPROT,
    input wire S_AXI_ARVALID,
    output wire S_AXI_ARREADY,

    output wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_RDATA,
    output wire [1:0] S_AXI_RRESP,
    output wire S_AXI_RVALID,
    input wire S_AXI_RREADY
);

    localparam integer ADDR_LSB =
        (C_S_AXI_DATA_WIDTH / 32) + 1;
    localparam integer OPT_MEM_ADDR_BITS = 3;

    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg axi_awready;
    reg axi_wready;
    reg [1:0] axi_bresp;
    reg axi_bvalid;
    reg aw_en;

    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    reg [1:0] axi_rresp;
    reg axi_rvalid;

    wire slv_reg_wren;
    wire slv_reg_rden;
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_data_out;

    wire fifo_full;
    wire fifo_empty;
    wire fifo_almost_full;
    wire fifo_almost_empty;
    wire fifo_valid;

    wire [WIDTH-1:0] fifo_data_out;
    wire [COUNT_WIDTH-1:0] fifo_data_count;

    wire fifo_reset_cmd;
    wire fifo_write_cmd;
    wire fifo_read_cmd;
    wire fifo_srst;

    reg [WIDTH-1:0] fifo_data_in;
    reg [WIDTH-1:0] fifo_read_data;
    reg fifo_read_valid;

    integer fifo_bit;

    localparam [31:0] FIFO_CONFIG =
        ((READ_LATENCY & 32'hF) << 24) |
        ((DEPTH & 32'hFFFF) << 8) |
        (WIDTH & 32'hFF);

    localparam [31:0] FIFO_THRESHOLDS =
        ((ALMOST_FULL_THRESHOLD & 32'hFFFF) << 16) |
        (ALMOST_EMPTY_THRESHOLD & 32'hFFFF);

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    // Write address handshake.
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready <= 1'b0;
            aw_en <= 1'b1;
        end else begin
            if (!axi_awready &&
                S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                axi_awready <= 1'b1;
                aw_en <= 1'b0;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                aw_en <= 1'b1;
                axi_awready <= 1'b0;
            end else begin
                axi_awready <= 1'b0;
            end
        end
    end

    // Capture the write address.
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awaddr <= 0;
        end else if (!axi_awready &&
                     S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
            axi_awaddr <= S_AXI_AWADDR;
        end
    end

    // Write data handshake.
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_wready <= 1'b0;
        end else begin
            if (!axi_wready &&
                S_AXI_WVALID && S_AXI_AWVALID && aw_en)
                axi_wready <= 1'b1;
            else
                axi_wready <= 1'b0;
        end
    end

    assign slv_reg_wren =
        axi_wready && S_AXI_WVALID &&
        axi_awready && S_AXI_AWVALID;

    // Write response.
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_bvalid <= 1'b0;
            axi_bresp <= 2'b00;
        end else begin
            if (axi_awready && S_AXI_AWVALID &&
                !axi_bvalid && axi_wready && S_AXI_WVALID) begin
                axi_bvalid <= 1'b1;
                axi_bresp <= 2'b00;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    // Read address handshake.
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_arready <= 1'b0;
            axi_araddr <= 0;
        end else begin
            if (!axi_arready && S_AXI_ARVALID && !axi_rvalid) begin
                axi_arready <= 1'b1;
                axi_araddr <= S_AXI_ARADDR;
            end else begin
                axi_arready <= 1'b0;
            end
        end
    end

    // Read response.
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_rvalid <= 1'b0;
            axi_rresp <= 2'b00;
        end else begin
            if (axi_arready && S_AXI_ARVALID && !axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp <= 2'b00;
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    assign slv_reg_rden =
        axi_arready && S_AXI_ARVALID && !axi_rvalid;

    // Manual Sections 6.2.1 through 6.2.9.
    // WO and reserved registers return zero.
    always @(*) begin
        reg_data_out = 0;

        case (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
            4'h0: reg_data_out = 32'h5200_0004;
            4'h4: reg_data_out = fifo_read_data;

            4'h5: reg_data_out = {
                27'd0,
                fifo_read_valid,
                fifo_almost_full,
                fifo_almost_empty,
                fifo_full,
                fifo_empty
            };

            4'h6: reg_data_out = fifo_data_count;
            4'h7: reg_data_out = FIFO_CONFIG;
            4'h8: reg_data_out = FIFO_THRESHOLDS;
            default: reg_data_out = 0;
        endcase
    end

    // Hold read data while waiting for the master.
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_rdata <= 0;
        else if (slv_reg_rden)
            axi_rdata <= reg_data_out;
    end

    // Single-clock commands from accepted AXI writes.
    assign fifo_reset_cmd =
        S_AXI_ARESETN && slv_reg_wren &&
        (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h1) &&
        S_AXI_WSTRB[0] && S_AXI_WDATA[0];

    assign fifo_write_cmd =
        S_AXI_ARESETN && slv_reg_wren &&
        (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h2) &&
        (|S_AXI_WSTRB[(WIDTH+7)/8-1:0]);

    assign fifo_read_cmd =
        S_AXI_ARESETN && slv_reg_wren &&
        (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h3) &&
        S_AXI_WSTRB[0] && S_AXI_WDATA[0];

    assign fifo_srst = !S_AXI_ARESETN || fifo_reset_cmd;

    // Only enabled data bytes are pushed.
    always @(*) begin
        fifo_data_in = 0;

        for (fifo_bit = 0; fifo_bit < WIDTH;
             fifo_bit = fifo_bit + 1) begin
            if (S_AXI_WSTRB[fifo_bit/8])
                fifo_data_in[fifo_bit] = S_AXI_WDATA[fifo_bit];
        end
    end

    // Retain the last valid output and a sticky valid flag.
    always @(posedge S_AXI_ACLK) begin
        if (fifo_srst) begin
            fifo_read_data <= 0;
            fifo_read_valid <= 1'b0;
        end else begin
            if (fifo_valid)
                fifo_read_data <= fifo_data_out;

            if (fifo_read_cmd)
                fifo_read_valid <= 1'b0;
            else if (fifo_valid)
                fifo_read_valid <= 1'b1;
        end
    end

    sc_fifo #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .ALMOST_EMPTY_THRESHOLD(ALMOST_EMPTY_THRESHOLD),
        .ALMOST_FULL_THRESHOLD(ALMOST_FULL_THRESHOLD),
        .READ_LATENCY(READ_LATENCY),
        .ADDR_WIDTH(ADDR_WIDTH),
        .COUNT_WIDTH(COUNT_WIDTH)
    ) sc_fifo_inst (
        .clk(S_AXI_ACLK),
        .srst(fifo_srst),
        .data_in(fifo_data_in),
        .write_enable(fifo_write_cmd),
        .read_enable(fifo_read_cmd),
        .data_out(fifo_data_out),
        .valid(fifo_valid),
        .full(fifo_full),
        .empty(fifo_empty),
        .almost_full(fifo_almost_full),
        .almost_empty(fifo_almost_empty),
        .data_count(fifo_data_count)
    );

endmodule