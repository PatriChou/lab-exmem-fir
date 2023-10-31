// SPDX-FileCopyrightText: 2020 Efabless Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0

`default_nettype none
/*
 *-------------------------------------------------------------
 *
 * user_proj_example
 *
 * This is an example of a (trivially simple) user project,
 * showing how the user project can connect to the logic
 * analyzer, the wishbone bus, and the I/O pads.
 *
 * This project generates an integer count, which is output
 * on the user area GPIO pads (digital output only).  The
 * wishbone connection allows the project to be controlled
 * (start and stop) from the management SoC program.
 *
 * See the testbenches in directory "mprj_counter" for the
 * example programs that drive this user project.  The three
 * testbenches are "io_ports", "la_test1", and "la_test2".
 *
 *-------------------------------------------------------------
 */

module user_proj_example #(
    parameter BITS = 32,
    parameter DELAYS=10
)(
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
`endif

    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output wbs_ack_o,
    output [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    // IOs
    input  [`MPRJ_IO_PADS-1:0] io_in,
    output [`MPRJ_IO_PADS-1:0] io_out,
    output [`MPRJ_IO_PADS-1:0] io_oeb,

    // IRQ
    output [2:0] irq
);

// rename 
wire clk;
wire rst_n;

assign clk = wb_clk_i;
assign rst_n = wb_rst_i;


wire [`MPRJ_IO_PADS-1:0] io_in;
wire [`MPRJ_IO_PADS-1:0] io_out;
wire [`MPRJ_IO_PADS-1:0] io_oeb;


// write into the bram, and then read from the bram
// every time Addr will +4
// After wr/rd, you must reply the ack. 
// ================= FSM =================
localparam RECV_ST  = 2'd0;
localparam RD_ST    = 2'd1;
localparam WR_ST    = 2'd2;
localparam DELAY_ST = 2'd3;

reg [1:0] curr_state, next_state;

always@(posedge clk or negedge rst_n) begin     //curr_state
    if(rst_n)
        curr_state <= 2'd0;
    else
        curr_state <= next_state;
end

always@(*) begin            //next_state
    case(curr_state)
        RECV_ST: begin
            next_state = (wbs_stb_i && wbs_cyc_i)? DELAY_ST:
                                                   RECV_ST;
        end
        DELAY_ST: begin
            next_state = (!wbs_cyc_i)?              RECV_ST:
                         (fsm_cnt == DELAYS - 1)?   (wbs_we_i)? WR_ST:RD_ST :          // fsm_cnt == 4'd9  -> assign bram signal
                                                    DELAY_ST;
        end
        RD_ST: begin
            next_state = (fsm_cnt > 4'd0)?  RECV_ST:
                                            RD_ST;
        end
        WR_ST: begin
            next_state = RECV_ST;
        end
        default: begin
            next_state = RECV_ST;
        end
    endcase
end

// ================= CONTROL SIGNAL =================
reg [3:0] fsm_cnt;

always@(posedge clk or negedge rst_n) begin
    if(rst_n)
        fsm_cnt <= 4'd0;
    else if( (curr_state != next_state) || (fsm_cnt == 4'b1111) )
        fsm_cnt <= 4'd0;
    else 
        fsm_cnt <= fsm_cnt + 4'd1;
end

// ================= BRAM =================
wire [3:0]  bram_WE;
wire        bram_EN;
wire [31:0] bram_Di;
wire [31:0] bram_Do;
wire [31:0] bram_A;

bram user_bram (
    .CLK(clk),
    .WE0(bram_WE),
    .EN0(bram_EN),
    .Di0(bram_Di),
    .Do0(bram_Do),
    .A0(bram_A)       //word addr
);

assign bram_WE = (next_state == WR_ST)? wbs_sel_i : 4'd0;
assign bram_EN  = (next_state == RD_ST || next_state == WR_ST)? 1'b1 : 1'b0;
assign bram_A   = (wbs_adr_i - 32'h3800_0000) >> 2;
// addr = 0x38_000_000 

// ================= READ =================
reg [31:0] wbs_rd_data;

always@(posedge clk) begin          // wbs_rd_data
    if(curr_state == RD_ST && fsm_cnt == 4'd0)
        wbs_rd_data <= bram_Do;
    else
        wbs_rd_data <= wbs_rd_data;
end

// ================= WRITE =================
assign bram_Di = (next_state == WR_ST)? wbs_dat_i : 4'd0;

// ================= WISBONE =================
assign wbs_ack_o = ( (curr_state == RD_ST && fsm_cnt > 4'd0) || curr_state == WR_ST)? 1'b1 : 1'b0;
assign wbs_dat_o  = wbs_rd_data;

// ================= IO =================
assign io_out = bram_Do;
assign io_oeb = {(`MPRJ_IO_PADS-1){rst_n}};

// ================= IRQ =================
assign irq = 3'b000;	// Unused

endmodule

`default_nettype wire
