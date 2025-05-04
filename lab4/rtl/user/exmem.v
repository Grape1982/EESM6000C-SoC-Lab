module exmem (
    // Wishbone interface
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
    
    // BRAM interface
    output        bram_clk,
    output [3:0]  bram_we,
    output        bram_en,
    output [31:0] bram_di,
    input  [31:0] bram_do,
    output [31:0] bram_addr
);

    // address decode
    wire bram_select = (wbs_adr_i[31:24] == 8'h38);
    
    // control signal
    assign bram_clk = wb_clk_i;
    assign bram_we = wbs_sel_i & {4{wbs_we_i & bram_select}};
    assign bram_en = wbs_stb_i & wbs_cyc_i & bram_select;
    assign bram_di = wbs_dat_i;
    assign bram_addr = wbs_adr_i;
    
    // data output
    assign wbs_dat_o = bram_do;
    
    // response signal
    reg ack;
    always @(posedge wb_clk_i) begin
        if (wb_rst_i)
            ack <= 1'b0;
        else
            ack <= bram_en;
    end
    assign wbs_ack_o = ack;

endmodule