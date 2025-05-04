module wb_decoder (
    // Main Wishbone Interface
    input         wb_clk_i,
    input         wb_rst_i,
    input         wbs_stb_i,
    input         wbs_cyc_i,
    input         wbs_we_i,
    input  [3:0]  wbs_sel_i,
    input  [31:0] wbs_dat_i,
    input  [31:0] wbs_adr_i,
    output        wbs_ack_o,
    output [31:0] wbs_dat_o,

    // exmem-FIR Interface (Address 3800_xxxx)
    output        exmem_wbs_stb_o,   // exmem-FIR strobe
    output        exmem_wbs_cyc_o,   // exmem-FIR cycle
    output        exmem_wbs_we_o,    // exmem-FIR write enable
    output [3:0]  exmem_wbs_sel_o,   // exmem-FIR byte select
    output [31:0] exmem_wbs_dat_o,   // exmem-FIR write data
    output [31:0] exmem_wbs_adr_o,   // exmem-FIR address
    input         exmem_wbs_ack_i,   // exmem-FIR acknowledge
    input  [31:0] exmem_wbs_dat_i,   // exmem-FIR read data

    // WB-AXI Interface (Address 3000_xxxx)
    output        wbaxi_wbs_stb_o,   // WB-AXI strobe
    output        wbaxi_wbs_cyc_o,   // WB-AXI cycle
    output        wbaxi_wbs_we_o,    // WB-AXI write enable
    output [3:0]  wbaxi_wbs_sel_o,   // WB-AXI byte select
    output [31:0] wbaxi_wbs_dat_o,   // WB-AXI write data
    output [31:0] wbaxi_wbs_adr_o,   // WB-AXI address
    input         wbaxi_wbs_ack_i,   // WB-AXI acknowledge
    input  [31:0] wbaxi_wbs_dat_i    // WB-AXI read data
);

    // Address Decoding Logic
    wire is_wbaxi  = (wbs_adr_i[31:16] == 16'h3000);  // 3000_xxxx range
    wire is_exmem  = (wbs_adr_i[31:16] == 16'h3800);  // 3800_xxxx range

    // exmem-FIR Interface Connections
    assign exmem_wbs_stb_o  = wbs_stb_i & is_exmem;
    assign exmem_wbs_cyc_o  = wbs_cyc_i & is_exmem;
    assign exmem_wbs_we_o   = wbs_we_i;
    assign exmem_wbs_sel_o  = wbs_sel_i;
    assign exmem_wbs_dat_o  = wbs_dat_i;
    assign exmem_wbs_adr_o  = wbs_adr_i;

    // WB-AXI Interface Connections
    assign wbaxi_wbs_stb_o  = wbs_stb_i & is_wbaxi;
    assign wbaxi_wbs_cyc_o  = wbs_cyc_i & is_wbaxi;
    assign wbaxi_wbs_we_o   = wbs_we_i;
    assign wbaxi_wbs_sel_o  = wbs_sel_i;
    assign wbaxi_wbs_dat_o  = wbs_dat_i;
    assign wbaxi_wbs_adr_o  = wbs_adr_i;

    // Acknowledge Signal Multiplexing
    assign wbs_ack_o = is_exmem  ? exmem_wbs_ack_i : 
                       is_wbaxi  ? wbaxi_wbs_ack_i : 
                       1'b0;      // Default acknowledge

    // Data Output Selection
    assign wbs_dat_o = is_exmem  ? exmem_wbs_dat_i :
                       is_wbaxi  ? wbaxi_wbs_dat_i :
                       32'h0000_0000;  // Default read data

    // Timeout Counter (Reserved, not affecting interface)
    reg [15:0] timeout_counter;
    wire transaction_active = wbs_cyc_i && wbs_stb_i && !wbs_ack_o;
    
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            timeout_counter <= 16'b0;
        end else begin
            timeout_counter <= transaction_active ? 
                             timeout_counter + 1 : 
                             16'b0;
        end
    end

endmodule