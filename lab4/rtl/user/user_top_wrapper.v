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
 * user_project_wrapper
 *
 * This wrapper enumerates all of the pins available to the
 * user for the user project.
 *
 * An example user project is provided in this wrapper.  The
 * example should be removed and replaced with the actual
 * user project.
 *
 *-------------------------------------------------------------
 */

module user_project_wrapper #(
    parameter BITS = 32
) (
`ifdef USE_POWER_PINS
    inout vdda1,    // User area 1 3.3V supply
    inout vdda2,    // User area 2 3.3V supply
    inout vssa1,    // User area 1 analog ground
    inout vssa2,    // User area 2 analog ground
    inout vccd1,    // User area 1 1.8V supply
    inout vccd2,    // User area 2 1.8v supply
    inout vssd1,    // User area 1 digital ground
    inout vssd2,    // User area 2 digital ground
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

    // Analog IO
    inout [`MPRJ_IO_PADS-10:0] analog_io,

    // Independent clock
    input user_clock2,

    // User interrupt
    output [2:0] user_irq
);

/*--------------------------------------*/
/* Internal Signal Definitions          */
/*--------------------------------------*/

// WBDecode interface signals
wire        fir_wbs_stb;
wire        fir_wbs_cyc;
wire        fir_wbs_we;
wire [3:0]  fir_wbs_sel;
wire [31:0] fir_wbs_dat_i;
wire [31:0] fir_wbs_adr;
wire        fir_wbs_ack;
wire [31:0] fir_wbs_dat_o;

wire        axi_wbs_stb;
wire        axi_wbs_cyc;
wire        axi_wbs_we;
wire [3:0]  axi_wbs_sel;
wire [31:0] axi_wbs_dat_i;
wire [31:0] axi_wbs_adr;
wire        axi_wbs_ack;
wire [31:0] axi_wbs_dat_o;

// exmem-FIR interface
wire [3:0]  data_WE;
wire        data_EN;
wire [31:0] data_Di;
wire [31:0] data_A;
wire [31:0] data_Do;

// WBAXI interface
wire        axil_awready;
wire        axil_wready;
wire        axil_awvalid;
wire [31:0] axil_awaddr;
wire        axil_wvalid;
wire [31:0] axil_wdata;
wire        axil_arready;
wire        axil_arvalid;
wire [31:0] axil_araddr;
wire        axil_rvalid;
wire [31:0] axil_rdata;

// FIR Core interface
wire [3:0]  tap_WE;
wire        tap_EN;
wire [31:0] tap_Di;
wire [31:0] tap_A;
wire [31:0] tap_Do;

// AXI-Stream interface
wire        ss_tready;
wire        sm_tvalid;
wire [31:0] sm_tdata;
wire        sm_tlast;

/*--------------------------------------*/
/* Module Instantiations                */
/*--------------------------------------*/

//  Wishbone address decoder
wb_decoder u_wb_decoder (
    
    .wb_clk_i(wb_clk_i),
    .wb_rst_i(wb_rst_i),
    .wbs_stb_i(wbs_stb_i),
    .wbs_cyc_i(wbs_cyc_i),
    .wbs_we_i(wbs_we_i),
    .wbs_sel_i(wbs_sel_i),
    .wbs_dat_i(wbs_dat_i),
    .wbs_adr_i(wbs_adr_i),
    .wbs_ack_o(wbs_ack_o),
    .wbs_dat_o(wbs_dat_o),

    // exmem-FIR interface
    .fir_wbs_stb_o(fir_wbs_stb),
    .fir_wbs_cyc_o(fir_wbs_cyc),
    .fir_wbs_we_o(fir_wbs_we),
    .fir_wbs_sel_o(fir_wbs_sel),
    .fir_wbs_dat_o(fir_wbs_dat_i),
    .fir_wbs_adr_o(fir_wbs_adr),
    .fir_wbs_ack_i(fir_wbs_ack),
    .fir_wbs_dat_i(fir_wbs_dat_o),

    // WBAXI interface
    .axi_wbs_stb_o(axi_wbs_stb),
    .axi_wbs_cyc_o(axi_wbs_cyc),
    .axi_wbs_we_o(axi_wbs_we),
    .axi_wbs_sel_o(axi_wbs_sel),
    .axi_wbs_dat_o(axi_wbs_dat_i),
    .axi_wbs_adr_o(axi_wbs_adr),
    .axi_wbs_ack_i(axi_wbs_ack),
    .axi_wbs_dat_i(axi_wbs_dat_o)
);

//  exmem-FIR memory
exmem_fir u_exmem_fir (
`ifdef USE_POWER_PINS
    .vccd1(vccd1),
    .vssd1(vssd1),
`endif
    .wb_clk_i(wb_clk_i),
    .wb_rst_i(wb_rst_i),
    
    // Wishbone interface
    .wbs_stb_i(fir_wbs_stb),
    .wbs_cyc_i(fir_wbs_cyc),
    .wbs_we_i(fir_wbs_we),
    .wbs_sel_i(fir_wbs_sel),
    .wbs_dat_i(fir_wbs_dat_i),
    .wbs_adr_i(fir_wbs_adr),
    .wbs_ack_o(fir_wbs_ack),
    .wbs_dat_o(fir_wbs_dat_o),

    // BRAM interface
    .data_WE(data_WE),
    .data_EN(data_EN),
    .data_Di(data_Di),
    .data_A(data_A),
    .data_Do(data_Do)
);

// WB_AXI module
wb_axi u_wb_axi (
`ifdef USE_POWER_PINS
    .vccd1(vccd1),
    .vssd1(vssd1),
`endif
    // Wishbone interface
    .wb_clk_i(wb_clk_i),
    .wb_rst_i(wb_rst_i),
    .wbs_stb_i(axi_wbs_stb),
    .wbs_cyc_i(axi_wbs_cyc),
    .wbs_we_i(axi_wbs_we),
    .wbs_sel_i(axi_wbs_sel),
    .wbs_dat_i(axi_wbs_dat_i),
    .wbs_adr_i(axi_wbs_adr),
    .wbs_ack_o(axi_wbs_ack),
    .wbs_dat_o(axi_wbs_dat_o),

    // AXI-Lite interface
    .awready(axil_awready),
    .wready(axil_wready),
    .awvalid(axil_awvalid),
    .awaddr(axil_awaddr),
    .wvalid(axil_wvalid),
    .wdata(axil_wdata),
    .arready(axil_arready),
    .arvalid(axil_arvalid),
    .araddr(axil_araddr),
    .rvalid(axil_rvalid),
    .rdata(axil_rdata),

    // AXI-Stream interface
    .ss_tvalid(io_in[0]),     
    .ss_tdata(io_in[31:1]),    
    .ss_tlast(io_in[32]),     
    .ss_tready(io_out[33]),   
    
    .sm_tvalid(sm_tvalid),
    .sm_tdata(sm_tdata),
    .sm_tlast(sm_tlast),
    .sm_tready(io_in[34])      
);

 fir fir_DUT(
        .awready(awready),
        .wready(wready),
        .awvalid(awvalid),
        .awaddr(awaddr),
        .wvalid(wvalid),
        .wdata(wdata),
        .arready(arready),
        .rready(rready),
        .arvalid(arvalid),
        .araddr(araddr),
        .rvalid(rvalid),
        .rdata(rdata),
        .ss_tvalid(ss_tvalid),
        .ss_tdata(ss_tdata),
        .ss_tlast(ss_tlast),
        .ss_tready(ss_tready),
        .sm_tready(sm_tready),
        .sm_tvalid(sm_tvalid),
        .sm_tdata(sm_tdata),
        .sm_tlast(sm_tlast),

        // ram for tap
        .tap_WE(tap_WE),
        .tap_EN(tap_EN),
        .tap_Di(tap_Di),
        .tap_A(tap_A),
        .tap_Do(tap_Do),

        // ram for data
        .data_WE(data_WE),
        .data_EN(data_EN),
        .data_Di(data_Di),
        .data_A(data_A),
        .data_Do(data_Do),

        .axis_clk(axis_clk),
        .axis_rst_n(axis_rst_n)

        );
    
    // RAM for tap
    bram11 tap_RAM (
        .CLK(axis_clk),
        .WE(tap_WE),
        .EN(tap_EN),
        .Di(tap_Di),
        .A(tap_A),
        .Do(tap_Do)
    );

    // RAM for data
    bram11 data_RAM(
        .CLK(axis_clk),
        .WE(data_WE),
        .EN(data_EN),
        .Di(data_Di),
        .A(data_A),
        .Do(data_Do)
    );


// IO connect
assign io_out[31:0] = sm_tdata;   
assign io_out[32] = sm_tvalid;    
assign io_out[33] = ss_tready;    
assign io_out[34] = sm_tlast;     



endmodule