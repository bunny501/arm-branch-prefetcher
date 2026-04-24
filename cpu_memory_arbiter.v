`timescale 1ns / 1ps

module cpu_memory_arbiter #(parameter AW=32, DW=32, FW=64)(
    input clk, rst_n,
    // CPU Port
    input [AW-1:0] c_araddr,
    input c_arvalid,
    output reg c_arready,
    output reg [DW-1:0] c_rdata,
    output reg c_rvalid,
    output reg [1:0] c_rresp,
    input c_rready,
    
    // Prefetch Port
    input [AW-1:0] p_araddr,
    input p_arvalid,
    output reg p_arready,
    output reg [DW-1:0] p_rdata,
    output reg p_rvalid,
    output reg [1:0] p_rresp,
    input p_rready,
    
    // Mem Port
    output reg [AW-1:0] m_araddr,
    output reg m_arvalid,
    input m_arready,
    input [DW-1:0] m_rdata,
    input m_rvalid,
    output reg m_rready,
    input [1:0] m_rresp,
    
    // FIFO Interface
    input f_empty,
    input [FW-1:0] f_dout,
    output reg f_pop
);
    reg [3:0] state;
    reg [AW-1:0] c_addr_q, p_addr_q;
    reg [DW-1:0] dat_q;

    wire hit = (!f_empty) && (f_dout[FW-1 : DW] == c_araddr);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state <= 0;
            c_addr_q <= 0; p_addr_q <= 0; dat_q <= 0;
            c_arready <= 0; c_rdata <= 0; c_rvalid <= 0; c_rresp <= 0;
            p_arready <= 0; p_rdata <= 0; p_rvalid <= 0; p_rresp <= 0;
            m_araddr <= 0; m_arvalid <= 0; m_rready <= 0; f_pop <= 0;
        end else begin
            // Defaults
            c_arready <= 0; c_rvalid <= 0; p_arready <= 0; p_rvalid <= 0;
            m_arvalid <= 0; m_rready <= 0; f_pop <= 0;

            case(state)
                0: begin // IDLE
                    if(c_arvalid) begin
                        c_addr_q <= c_araddr;
                        if(hit) begin
                            dat_q <= f_dout[DW-1:0];
                            state <= 1;
                        end else state <= 3;
                    end else if(p_arvalid) begin
                        p_addr_q <= p_araddr;
                        state <= 6;
                    end
                end
                
                //  HIT PATH 
                1: begin c_arready <= 1; f_pop <= 1; state <= 2; end
                2: begin 
                    c_rvalid <= 1; c_rdata <= dat_q; c_rresp <= 0;
                    if(c_rready) state <= 0;
                end
                
                //  MISS PATH 
                3: begin
                    c_arready <= 1; m_araddr <= c_addr_q; m_arvalid <= 1;
                    if(m_arready) state <= 4;
                end
                4: begin
                    m_rready <= 1;
                    if(m_rvalid) begin
                        dat_q <= m_rdata; c_rresp <= m_rresp;
                        state <= 5;
                    end
                end
                5: begin
                    c_rvalid <= 1; c_rdata <= dat_q;
                    if(c_rready) state <= 0;
                end
                
                // PREFETCH PATH 
                6: begin
                    p_arready <= 1; m_araddr <= p_addr_q; m_arvalid <= 1;
                    if(m_arready) state <= 7;
                end
                7: begin
                    m_rready <= 1;
                    if(m_rvalid) begin
                        dat_q <= m_rdata; p_rresp <= m_rresp;
                        state <= 8;
                    end
                end
                8: begin
                    p_rvalid <= 1; p_rdata <= dat_q;
                    if(p_rready) state <= 0;
                end
                default: state <= 0;
            endcase
        end
    end
endmodule
