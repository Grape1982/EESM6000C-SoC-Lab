module wb_axi (
    // Wishbone Interface
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

    // AXI-Lite Interface
    output reg [31:0] axil_awaddr,
    output reg        axil_awvalid,
    input             axil_awready,
    
    output reg [31:0] axil_wdata,
    output reg        axil_wvalid,
    input             axil_wready,
    
    output reg        axil_arvalid,
    output reg [31:0] axil_araddr,
    input             axil_arready,
    
    input      [31:0] axil_rdata,
    input             axil_rvalid,
    
    input             axil_bvalid,

    // AXI-Stream Interface
    output reg [31:0] axis_tdata,
    output reg        axis_tvalid,
    input             axis_tready,
    
    input      [31:0] fir_tdata,
    input             fir_tvalid,
    output reg        fir_tready
);

    // Address Decode
    wire is_axilite  = (wbs_adr_i >= 32'h3000_0000) && (wbs_adr_i <= 32'h3000_007F) &&
                      !((wbs_adr_i >= 32'h3000_0040) && (wbs_adr_i <= 32'h3000_0047));

    wire is_xn_write = (wbs_adr_i == 32'h3000_0040) && wbs_we_i;
    wire is_yn_read  = (wbs_adr_i == 32'h3000_0044) && !wbs_we_i;

    // State Machine Definition
    typedef enum {
        IDLE,
        AXI_WRITE_ADDR,
        AXI_WRITE_DATA,
        AXI_READ_ADDR,
        AXI_READ_DATA,
        AXIS_WRITE,
        AXIS_READ
    } state_t;

    reg [2:0] state;
    reg [31:0] read_buffer;

    // AXI-Lite Control Logic
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            state <= IDLE;
            axil_awvalid <= 0;
            axil_wvalid <= 0;
            axil_arvalid <= 0;
            axis_tvalid <= 0;
            fir_tready <= 0;
        end else begin
            case(state)
                IDLE: begin
                    if (wbs_cyc_i && wbs_stb_i) begin
                        if (is_axilite) begin
                            if (wbs_we_i) begin
                                state <= AXI_WRITE_ADDR;
                                axil_awaddr <= wbs_adr_i;
                                axil_awvalid <= 1;
                            end else begin
                                state <= AXI_READ_ADDR;
                                axil_araddr <= wbs_adr_i;
                                axil_arvalid <= 1;
                            end
                        end
                        else if (is_xn_write) begin
                            state <= AXIS_WRITE;
                            axis_tdata <= wbs_dat_i;
                            axis_tvalid <= 1;
                        end
                        else if (is_yn_read) begin
                            state <= AXIS_READ;
                            fir_tready <= 1;
                        end
                    end
                end

                AXI_WRITE_ADDR: begin
                    if (axil_awready) begin
                        axil_awvalid <= 0;
                        state <= AXI_WRITE_DATA;
                        axil_wdata <= wbs_dat_i;
                        axil_wvalid <= 1;
                    end
                end

                AXI_WRITE_DATA: begin
                    if (axil_wready) begin
                        axil_wvalid <= 0;
                        state <= IDLE;
                    end
                end

                AXI_READ_ADDR: begin
                    if (axil_arready) begin
                        axil_arvalid <= 0;
                        state <= AXI_READ_DATA;
                    end
                end

                AXI_READ_DATA: begin
                    if (axil_rvalid) begin
                        read_buffer <= axil_rdata;
                        state <= IDLE;
                    end
                end

                AXIS_WRITE: begin
                    if (axis_tready) begin
                        axis_tvalid <= 0;
                        state <= IDLE;
                    end
                end

                AXIS_READ: begin
                    if (fir_tvalid) begin
                        read_buffer <= fir_tdata;
                        fir_tready <= 0;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

    // Acknowledge Generation
    assign wbs_ack_o = (state == IDLE) ? 0 : 
                      (is_axilite && ((state == AXI_WRITE_DATA && axil_wready) || 
                                      (state == AXI_READ_DATA && axil_rvalid))) ||
                      (is_xn_write && axis_tready) ||
                      (is_yn_read && fir_tvalid);

    // Data Output Selection
    assign wbs_dat_o = (is_axilite && !wbs_we_i) ? read_buffer :
                      (is_yn_read) ? read_buffer :
                      32'hFFFF_FFFF;

    // Special Address Handling
    always @(*) begin
        if (wbs_adr_i == 32'h3000_0040 && !wbs_we_i)
            wbs_dat_o = 32'hFFFF_FFFF;  // Return fixed value for X[n] read
    end

endmodule