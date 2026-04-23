`timescale 1ns / 1ps

module prefetch_sidecar_fifo #(parameter W=64, D=8)(
    input clk, rst_n, push, pop, flush,
    input [W-1:0] din,
    output [W-1:0] dout,
    output full, empty
);
    localparam A_BITS = $clog2(D);
    reg [W-1:0] mem [0:D-1];
    reg [A_BITS:0] wp, rp;

    // N+1 pointer logic
    assign empty = (wp == rp);
    assign full = (wp[A_BITS-1:0] == rp[A_BITS-1:0]) && (wp[A_BITS] != rp[A_BITS]);
    assign dout = mem[rp[A_BITS-1:0]];

    always @(posedge clk) begin
        if(push && !full && !flush) 
            mem[wp[A_BITS-1:0]] <= din;
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wp <= 0; rp <= 0;
        end else if(flush) begin
            wp <= 0; rp <= 0; // 1-cycle reset
        end else begin
            if(push && !full) wp <= wp + 1;
            if(pop && !empty) rp <= rp + 1;
        end
    end
endmodule