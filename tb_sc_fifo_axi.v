`timescale 1ns / 1ps

module tb_sc_fifo_axi;

    reg clk = 0;
    always #10 clk = ~clk;

    reg resetn = 0;

    reg [5:0] awaddr = 0;
    reg [5:0] araddr = 0;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 0;

    reg awvalid = 0;
    reg wvalid = 0;
    reg bready = 0;
    reg arvalid = 0;
    reg rready = 0;

    wire awready;
    wire wready;
    wire bvalid;
    wire arready;
    wire rvalid;
    wire [1:0] bresp;
    wire [1:0] rresp;
    wire [31:0] rdata;

    reg [15:0] test_data [0:35];
    reg [31:0] result;

    integer i;
    integer errors = 0;
    integer writes = 0;
    integer reads = 0;
    integer resets = 0;
    integer old_writes;
    integer old_reads;
    integer old_resets;

    reg previous_write = 0;
    reg previous_read = 0;
    reg previous_reset = 0;

    sc_fifo_axi_v1_0 DUT (
        .s00_axi_aclk(clk),
        .s00_axi_aresetn(resetn),

        .s00_axi_awaddr(awaddr),
        .s00_axi_awprot(3'b000),
        .s00_axi_awvalid(awvalid),
        .s00_axi_awready(awready),

        .s00_axi_wdata(wdata),
        .s00_axi_wstrb(wstrb),
        .s00_axi_wvalid(wvalid),
        .s00_axi_wready(wready),

        .s00_axi_bresp(bresp),
        .s00_axi_bvalid(bvalid),
        .s00_axi_bready(bready),

        .s00_axi_araddr(araddr),
        .s00_axi_arprot(3'b000),
        .s00_axi_arvalid(arvalid),
        .s00_axi_arready(arready),

        .s00_axi_rdata(rdata),
        .s00_axi_rresp(rresp),
        .s00_axi_rvalid(rvalid),
        .s00_axi_rready(rready)
    );

    wire push_cmd =
        DUT.sc_fifo_axi_v1_0_S00_AXI_inst.fifo_write_cmd;
    wire pop_cmd =
        DUT.sc_fifo_axi_v1_0_S00_AXI_inst.fifo_read_cmd;
    wire reset_cmd =
        DUT.sc_fifo_axi_v1_0_S00_AXI_inst.fifo_reset_cmd;

    // Check that commands last exactly one clock.
    always @(posedge clk) begin
        if (!resetn) begin
            previous_write <= 0;
            previous_read <= 0;
            previous_reset <= 0;
        end else begin
            if ((push_cmd && previous_write) ||
                (pop_cmd && previous_read) ||
                (reset_cmd && previous_reset)) begin
                $display("ERROR: command exceeded one clock");
                errors = errors + 1;
            end

            if (push_cmd) writes = writes + 1;
            if (pop_cmd) reads = reads + 1;
            if (reset_cmd) resets = resets + 1;

            previous_write <= push_cmd;
            previous_read <= pop_cmd;
            previous_reset <= reset_cmd;

            if (pop_cmd) begin
                #1;
                if (DUT.sc_fifo_axi_v1_0_S00_AXI_inst
                       .fifo_read_valid !== 1'b0) begin
                    $display("ERROR: RD_REQ did not clear RD_VALID");
                    errors = errors + 1;
                end
            end
        end
    end

    // Write one AXI register.
    task axi_write;
        input [5:0] address;
        input [31:0] value;
        input [3:0] strobes;
        begin
            @(negedge clk);
            awaddr = address;
            awvalid = 1;

            repeat (2) @(negedge clk);

            wdata = value;
            wstrb = strobes;
            wvalid = 1;

            @(posedge clk);
            while (!(awready && wready))
                @(posedge clk);

            @(negedge clk);
            awvalid = 0;
            wvalid = 0;

            wait (bvalid === 1'b1);

            if (bresp !== 2'b00) begin
                $display("ERROR: AXI write response");
                errors = errors + 1;
            end

            // Stall response to detect repeated commands.
            repeat (2) @(negedge clk);

            bready = 1;
            @(posedge clk);
            @(negedge clk);
            bready = 0;
        end
    endtask

    // Read one AXI register.
    task axi_read;
        input [5:0] address;
        output [31:0] value;
        begin
            @(negedge clk);
            araddr = address;
            arvalid = 1;

            @(posedge clk);
            while (!arready)
                @(posedge clk);

            @(negedge clk);
            arvalid = 0;

            wait (rvalid === 1'b1);
            value = rdata;

            if (rresp !== 2'b00) begin
                $display("ERROR: AXI read response");
                errors = errors + 1;
            end

            repeat (2) @(negedge clk);

            if (rdata !== value || rvalid !== 1'b1) begin
                $display("ERROR: stalled read response changed");
                errors = errors + 1;
            end

            rready = 1;
            @(posedge clk);
            @(negedge clk);
            rready = 0;
        end
    endtask

    // Read and compare a register.
    task expect_reg;
        input [5:0] address;
        input [31:0] expected;
        reg [31:0] actual;
        begin
            axi_read(address, actual);

            if (actual !== expected) begin
                $display(
                    "ERROR: offset %h expected %08h got %08h",
                    address, expected, actual
                );
                errors = errors + 1;
            end
        end
    endtask

    task push;
        input [15:0] value;
        begin
            old_writes = writes;
            axi_write(6'h08, {16'd0, value}, 4'hF);

            if (writes != old_writes + 1) begin
                $display("ERROR: push command count");
                errors = errors + 1;
            end
        end
    endtask

    // Request a pop, poll RD_VALID, then check RD_DATA.
    task pop_check;
        input [15:0] expected;
        integer polls;
        reg [31:0] status_value;
        begin
            old_reads = reads;
            axi_write(6'h0C, 32'd1, 4'hF);

            status_value = 0;
            polls = 0;

            while (!status_value[4] && polls < 32) begin
                axi_read(6'h14, status_value);
                polls = polls + 1;
            end

            if (status_value[4] !== 1'b1) begin
                $display("ERROR: RD_VALID timeout");
                errors = errors + 1;
            end

            expect_reg(6'h10, {16'd0, expected});

            // Reading again must not pop another word.
            expect_reg(6'h10, {16'd0, expected});

            axi_read(6'h14, status_value);
            if (status_value[4] !== 1'b1) begin
                $display("ERROR: RD_VALID was not retained");
                errors = errors + 1;
            end

            if (reads != old_reads + 1) begin
                $display("ERROR: pop command count");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $display("Michael Hernandez - Lab 4 AXI FIFO Test");

        test_data[0] = 16'hFFFF;
        test_data[1] = 16'h0000;
        test_data[2] = 16'hAAAA;
        test_data[3] = 16'h5555;

        for (i = 0; i < 32; i = i + 1)
            test_data[i + 4] = i;

        repeat (4) @(negedge clk);
        resetn = 1;
        repeat (2) @(negedge clk);

        $display("TEST 1: Reset and configuration registers");

        expect_reg(6'h00, 32'h52000004);
        expect_reg(6'h10, 0);
        expect_reg(6'h14, 5);
        expect_reg(6'h18, 0);
        expect_reg(6'h1C, 32'h01002010);
        expect_reg(6'h20, 32'h001F0001);

        $display("TEST 2: RO, WO and reserved register behavior");

        for (i = 0; i < 16; i = i + 1) begin
            if (i != 1 && i != 2 && i != 3)
                axi_write(i * 4, 32'hFFFFFFFF, 4'hF);
        end

        expect_reg(6'h00, 32'h52000004);
        expect_reg(6'h10, 0);
        expect_reg(6'h14, 5);
        expect_reg(6'h18, 0);
        expect_reg(6'h1C, 32'h01002010);
        expect_reg(6'h20, 32'h001F0001);

        expect_reg(6'h04, 0);
        expect_reg(6'h08, 0);
        expect_reg(6'h0C, 0);

        for (i = 9; i < 16; i = i + 1)
            expect_reg(i * 4, 0);

        $display("TEST 3: Data patterns and FIFO ordering");

        for (i = 0; i < 4; i = i + 1)
            push(test_data[i]);

        expect_reg(6'h18, 4);

        for (i = 0; i < 4; i = i + 1)
            pop_check(test_data[i]);

        expect_reg(6'h18, 0);

        $display("TEST 4: Full, thresholds and rejected extra write");

        for (i = 0; i < 31; i = i + 1)
            push(i);

        axi_read(6'h14, result);
        if (result[3:0] !== 4'h8) begin
            $display("ERROR: almost-full flags");
            errors = errors + 1;
        end

        push(31);
        expect_reg(6'h18, 32);

        axi_read(6'h14, result);
        if (result[3:0] !== 4'hA) begin
            $display("ERROR: full flags");
            errors = errors + 1;
        end

        push(16'hDEAD);
        expect_reg(6'h18, 32);

        for (i = 0; i < 31; i = i + 1)
            pop_check(i);

        expect_reg(6'h18, 1);
        expect_reg(6'h14, 32'h00000014);

        pop_check(31);

        expect_reg(6'h18, 0);
        expect_reg(6'h14, 32'h00000015);

        $display("TEST 5: Empty read and RD_VALID clearing");

        axi_write(6'h0C, 1, 4'hF);
        repeat (8) @(negedge clk);

        expect_reg(6'h14, 5);
        expect_reg(6'h18, 0);

        $display("TEST 6: Zero commands and byte strobes");

        push(16'h1111);

        old_reads = reads;
        old_resets = resets;
        old_writes = writes;

        axi_write(6'h04, 0, 4'hF);
        axi_write(6'h0C, 0, 4'hF);
        axi_write(6'h04, 1, 4'h0);
        axi_write(6'h0C, 1, 4'h0);
        axi_write(6'h08, 32'hFFFF, 4'h0);

        if (reads != old_reads ||
            resets != old_resets ||
            writes != old_writes) begin
            $display("ERROR: disabled command had an effect");
            errors = errors + 1;
        end

        expect_reg(6'h18, 1);
        pop_check(16'h1111);

        axi_write(6'h08, 32'h0000ABCD, 4'h1);
        pop_check(16'h00CD);

        $display("TEST 7: Software reset");

        push(16'h1234);
        old_resets = resets;

        axi_write(6'h04, 1, 4'hF);

        if (resets != old_resets + 1) begin
            $display("ERROR: software reset command count");
            errors = errors + 1;
        end

        expect_reg(6'h10, 0);
        expect_reg(6'h14, 5);
        expect_reg(6'h18, 0);

        $display("TEST 8: Pattern sequence and pointer wraparound");

        for (i = 0; i < 36; i = i + 1) begin
            push(test_data[i]);
            pop_check(test_data[i]);
        end

        expect_reg(6'h18, 0);

        $display("TEST 9: AXI reset after activity");

        push(16'hABCD);

        @(negedge clk);
        resetn = 0;

        repeat (4) @(negedge clk);
        resetn = 1;
        repeat (2) @(negedge clk);

        expect_reg(6'h10, 0);
        expect_reg(6'h14, 5);
        expect_reg(6'h18, 0);

        if (errors == 0)
            $display("ALL AXI FIFO TESTS PASSED");
        else
            $fatal(1, "TEST FAILED: %0d errors", errors);

        $finish;
    end

    // Stop a hung simulation.
    initial begin
        #2000000;
        $fatal(1, "TEST FAILED: simulation watchdog timeout");
    end

endmodule