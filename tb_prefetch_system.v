`timescale 1ns/1ps

module tb_prefetch_system;

    // params
    localparam AW = 32, DW = 32, FW = 64;
    localparam HALF = 5;   // 10ns clock

    // a few instructions used in the test
    localparam NOP    = 32'hE1A0_0000;   // MOV R0,R0  @ 0x00
    localparam BRANCH = 32'hEA00_0002;   // B +2  → target 0x14  @ 0x04
    localparam TARGET = 32'hE3A0_1001;   // MOV R1,#1  @ 0x14
    localparam MISS_I = 32'hE3A0_0001;   // MOV R0,#1  @ 0x08

    // clock and reset
    reg clk = 0, rst_n = 0;
    always #HALF clk = ~clk;

    // wires between modules
    wire            pd_is_branch, pd_valid;
    wire [AW-1:0]   pd_target;

    wire [AW-1:0]   pf_araddr;
    wire            pf_arvalid, pf_arready;
    wire [DW-1:0]   pf_rdata;
    wire            pf_rvalid, pf_rready;
    wire [1:0]      pf_rresp;

    wire            fw_en;
    wire [FW-1:0]   fw_data;
    wire            fifo_full, fifo_empty;
    wire [FW-1:0]   fifo_rdata;
    wire            fifo_ren;

    wire            cpu_arready;
    wire [DW-1:0]   cpu_rdata;
    wire            cpu_rvalid;
    wire [1:0]      cpu_rresp;

    wire [AW-1:0]   mem_araddr;
    wire            mem_arvalid, mem_rready;

    // testbench-driven registers
    reg [AW-1:0] cpu_araddr;
    reg          cpu_arvalid, cpu_rready;

    reg          pd_valid_in;
    reg [DW-1:0] pd_inst_in;
    reg [AW-1:0] pd_pc_in;

    reg          mem_arready;
    reg [DW-1:0] mem_rdata;
    reg          mem_rvalid;
    reg [1:0]    mem_rresp;
    reg          fifo_flush;

    // latch fetch address while arvalid is held (address is stable for whole transaction)
    reg [AW-1:0] fetch_addr_q;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) fetch_addr_q <= 0;
        else if (cpu_arvalid) fetch_addr_q <= cpu_araddr;  // cpu holds araddr stable

    always @(*) begin
        pd_valid_in = cpu_rvalid;
        pd_inst_in  = cpu_rdata;
        pd_pc_in    = fetch_addr_q;
    end

    // sticky latches: predecoder outputs stay high for one cycle,
    // so capture them here and check latched values in the tests
    reg          pd_branch_seen;
    reg [AW-1:0] pd_target_seen;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pd_branch_seen <= 0;
            pd_target_seen <= 0;
        end else if (pd_is_branch) begin
            pd_branch_seen <= 1;
            pd_target_seen <= pd_target;
        end
    end

    // sticky flag that stays high if mem_arvalid ever pulses
    reg mem_seen;
    always @(posedge clk) if (mem_arvalid) mem_seen = 1;

    // dut instantiations
    arm_branch_predecoder #(.D_W(DW),.P_W(AW)) u_pd (
        .clk(clk), .rst_n(rst_n),
        .vld_in(pd_valid_in), .inst(pd_inst_in), .pc_in(pd_pc_in),
        .is_br(pd_is_branch), .tgt_pc(pd_target), .tgt_vld(pd_valid)
    );

    prefetch_axi_master #(.AW(AW),.DW(DW),.FW(FW)) u_pf (
        .clk(clk), .rst_n(rst_n),
        .tgt_vld(pd_valid), .tgt_pc(pd_target),
        .araddr(pf_araddr), .arvalid(pf_arvalid), .arready(pf_arready),
        .rdata(pf_rdata), .rvalid(pf_rvalid), .rresp(pf_rresp), .rready(pf_rready),
        .fifo_push(fw_en), .fetched_inst(), .fifo_din(fw_data)
    );

    prefetch_sidecar_fifo #(.W(FW),.D(8)) u_fifo (
        .clk(clk), .rst_n(rst_n),
        .push(fw_en), .din(fw_data),
        .pop(fifo_ren), .dout(fifo_rdata),
        .full(fifo_full), .empty(fifo_empty),
        .flush(fifo_flush)
    );

    cpu_memory_arbiter #(.AW(AW),.DW(DW),.FW(FW)) u_arb (
        .clk(clk), .rst_n(rst_n),
        .c_araddr(cpu_araddr), .c_arvalid(cpu_arvalid),
        .c_arready(cpu_arready), .c_rdata(cpu_rdata),
        .c_rvalid(cpu_rvalid), .c_rresp(cpu_rresp), .c_rready(cpu_rready),
        .p_araddr(pf_araddr), .p_arvalid(pf_arvalid), .p_arready(pf_arready),
        .p_rdata(pf_rdata), .p_rvalid(pf_rvalid), .p_rresp(pf_rresp), .p_rready(pf_rready),
        .m_araddr(mem_araddr), .m_arvalid(mem_arvalid), .m_arready(mem_arready),
        .m_rdata(mem_rdata), .m_rvalid(mem_rvalid), .m_rready(mem_rready), .m_rresp(mem_rresp),
        .f_empty(fifo_empty), .f_dout(fifo_rdata), .f_pop(fifo_ren)
    );

    // mock memory (axi slave, 64 words)
    reg [DW-1:0] ram [0:63];
    integer i;
    initial begin
        for (i = 0; i < 64; i = i+1) ram[i] = NOP;
        ram[0]  = 32'hE3A0_0000;   // 0x00
        ram[1]  = BRANCH;          // 0x04 branch to 0x14
        ram[2]  = MISS_I;          // 0x08
        ram[3]  = 32'hE3A0_0002;   // 0x0C
        ram[4]  = 32'hE3A0_0003;   // 0x10
        ram[5]  = TARGET;          // 0x14 prefetch target
    end

    reg [1:0] mst;   // memory slave state
    localparam MS_IDLE=0, MS_AR=1, MS_HOLD=2;
    reg [AW-1:0] maddr_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mst <= MS_IDLE; mem_arready <= 0; mem_rvalid <= 0;
        end else begin
            mem_arready <= 0; mem_rvalid <= 0;
            case (mst)
                MS_IDLE: if (mem_arvalid) begin
                    maddr_q <= mem_araddr;
                    mem_arready <= 1;
                    mst <= MS_AR;
                end
                MS_AR: begin
                    mem_rvalid <= 1;
                    mem_rdata  <= ram[maddr_q[AW-1:2]];
                    mem_rresp  <= 0;
                    mst <= mem_rready ? MS_IDLE : MS_HOLD;
                end
                MS_HOLD: begin
                    mem_rvalid <= 1;
                    mem_rdata  <= ram[maddr_q[AW-1:2]];
                    if (mem_rready) mst <= MS_IDLE;
                end
            endcase
        end
    end

    // test counters
    integer pass_cnt, fail_cnt;
    `define CHK(cond, msg) \
        if (cond) begin $display("  PASS: %s", msg); pass_cnt=pass_cnt+1; end \
        else begin $display("  FAIL: %s (t=%0t)", msg, $time); fail_cnt=fail_cnt+1; end

    // cpu_read task
    task cpu_read;
        input  [AW-1:0] addr;
        output [DW-1:0] data;
        output [1:0]    resp;
        integer tmout;
        begin
            @(negedge clk);
            cpu_araddr = addr; cpu_arvalid = 1; cpu_rready = 1;
            tmout = 0; @(posedge clk); #1;
            while (!cpu_arready) begin
                @(posedge clk); #1;
                if (++tmout > 100) begin $display("AR timeout"); $finish; end
            end
            @(negedge clk); cpu_arvalid = 0;
            tmout = 0; @(posedge clk); #1;
            while (!cpu_rvalid) begin
                @(posedge clk); #1;
                if (++tmout > 100) begin $display("R timeout"); $finish; end
            end
            data = cpu_rdata; resp = cpu_rresp;
            $display("  CPU fetch 0x%08h → 0x%08h", addr, data);
            @(negedge clk); cpu_rready = 0;
        end
    endtask

    task wait_cyc; input integer n; integer k;
        begin for (k=0;k<n;k=k+1) @(posedge clk); #1; end
    endtask

    // main test
    reg [DW-1:0] d; reg [1:0] r; integer wc;

    initial begin
        pass_cnt=0; fail_cnt=0;
        cpu_arvalid=0; cpu_rready=0; fifo_flush=0; mem_seen=0;
        pd_branch_seen=0; pd_target_seen=0;

        $display("\n=== Branch-Based Prefetcher TB ===");

        // phase 0 reset
        $display("\n[Phase 0] Reset");
        repeat(5) @(posedge clk);
        @(negedge clk); rst_n = 1;
        wait_cyc(3);

        // phase 1 nop fetch, predecoder should stay quiet
        $display("\n[Phase 1] NOP at 0x00");
        cpu_read(32'h0, d, r);
        wait_cyc(3);
        `CHK(d == 32'hE3A00000,   "got NOP instruction")
        `CHK(!pd_is_branch,       "predecoder silent on NOP")
        `CHK(fifo_empty,          "FIFO still empty")

        // phase 2 fetch branch, predecoder must fire
        $display("\n[Phase 2] Branch at 0x04");
        @(negedge clk); pd_branch_seen = 0; pd_target_seen = 0;  // clear sticky flags
        cpu_read(32'h4, d, r);
        wait_cyc(3);   // predecoder registers one cycle after cpu_rvalid; keep margin
        `CHK(d == BRANCH,              "got branch instruction")
        `CHK(pd_branch_seen,           "predecoder flagged branch (sticky)")
        `CHK(pd_target_seen == 32'h14, "target computed = 0x14 (sticky)")

        // phase 3 cpu idles, prefetcher should fill fifo
        $display("\n[Phase 3] Waiting for prefetch fill...");
        wc = 0; @(posedge clk); #1;
        while (fifo_empty && wc < 30) begin @(posedge clk); #1; wc=wc+1; end
        wait_cyc(2);
        `CHK(!fifo_empty,                              "FIFO filled by prefetcher")
        `CHK(fifo_rdata[FW-1:DW] == 32'h14,          "FIFO head PC = 0x14")
        `CHK(fifo_rdata[DW-1:0]  == TARGET,            "FIFO head instr = MOV R1,#1")

        // phase 4 cpu asks for 0x14, should come from fifo and not memory
        $display("\n[Phase 4] CPU fetch 0x14 (expect FIFO hit, no memory access)");
        @(negedge clk); mem_seen = 0;
        cpu_read(32'h14, d, r);
        wait_cyc(4);
        `CHK(d == TARGET,      "got MOV R1,#1 from FIFO")
        `CHK(!mem_seen,        "mem_arvalid never went high — memory bypassed!")
        `CHK(fifo_empty,       "FIFO empty after pop")

        // phase 5 flush test
        $display("\n[Phase 5] Flush on misprediction");
        cpu_read(32'h4, d, r);   // retrigger prefetch
        wc=0; @(posedge clk); #1;
        while (fifo_empty && wc < 30) begin @(posedge clk); #1; wc=wc+1; end
        `CHK(!fifo_empty, "FIFO re-filled before flush")
        @(negedge clk); fifo_flush = 1;
        @(posedge clk); #1;
        @(negedge clk); fifo_flush = 0;
        wait_cyc(1);
        `CHK(fifo_empty, "FIFO empty 1 cycle after flush")

        // phase 6 miss path check
        $display("\n[Phase 6] Miss at 0x08 (not in FIFO)");
        @(negedge clk); mem_seen = 0;
        cpu_read(32'h8, d, r);
        wait_cyc(3);
        `CHK(d == MISS_I,  "got MOV R0,#1 from memory")
        `CHK(mem_seen,     "mem_arvalid went high — miss path works")

        // summary
        $display("\n=== RESULTS: %0d passed, %0d failed ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial begin
        $dumpfile("tb_prefetch_system.vcd");
        $dumpvars(0, tb_prefetch_system);
    end

    // watchdog
    initial begin #200_000; $display("WATCHDOG hit"); $finish; end

endmodule