`timescale 1ns / 1ps

module arm_branch_predecoder #(parameter D_W=32, P_W=32)(
    input clk, rst_n, vld_in,
    input [D_W-1:0] inst,
    input [P_W-1:0] pc_in,
    output reg is_br,
    output reg [P_W-1:0] tgt_pc,
    output reg tgt_vld
);
    // Decode ARM B/BL (opcode 101, ignore condition 1111)
    wire is_br_c = vld_in && (inst[27:25] == 3'b101) && (inst[31:28] != 4'b1111);
    
    // Shift left by 2 and sign extend in one go
    wire [P_W-1:0] offset = {{6{inst[23]}}, inst[23:0], 2'b00};
    wire [P_W-1:0] tgt_c = (pc_in + 8) + offset;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            is_br <= 0; 
            tgt_pc <= 0; 
            tgt_vld <= 0;
        end else begin
            is_br <= is_br_c;
            tgt_vld <= is_br_c;
            tgt_pc <= is_br_c ? tgt_c : 0;
        end
    end
endmodule