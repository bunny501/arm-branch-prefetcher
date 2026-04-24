`timescale 1ns / 1ps

module prefetch_axi_master #(parameter AW=32, DW=32, FW=64)(
    input clk, rst_n, tgt_vld,
    input [AW-1:0] tgt_pc,
    
    output reg [AW-1:0] araddr,
    output reg arvalid,
    input arready,
    input [DW-1:0] rdata,
    input rvalid,
    input [1:0] rresp,
    output reg rready,
    
    output reg fifo_push,
    output reg [DW-1:0] fetched_inst,
    output [FW-1:0] fifo_din
);
    reg [1:0] state;
    reg [AW-1:0] pc_q;
    
    assign fifo_din = {pc_q, fetched_inst};

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state <= 0; pc_q <= 0; araddr <= 0;
            arvalid <= 0; rready <= 0; 
            fifo_push <= 0; fetched_inst <= 0;
        end else begin
            fifo_push <= 0; // DEFAULT
            case(state)
                0: begin // IDLE
                    arvalid <= 0; rready <= 0;
                    if(tgt_vld) begin
                        pc_q <= tgt_pc;
                        state <= 1;
                    end
                end
                1: begin // REQ
                    araddr <= pc_q; arvalid <= 1; rready <= 1;
                    if(arready) begin 
                        arvalid <= 0; 
                        state <= 2; 
                    end
                end
                2: begin // WAIT DATA and COMPLETE
                    arvalid <= 0; rready <= 1;
                    if(rvalid) begin
                        rready <= 0;
                        if(rresp == 0 || rresp == 1) begin
                            fetched_inst <= rdata;
                            fifo_push <= 1;
                        end
                        state <= 0;
                    end
                end
            endcase
        end
    end
endmodule
