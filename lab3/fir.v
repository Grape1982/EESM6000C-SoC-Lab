`timescale 1ns / 1ps

`define SS_IDLE 1'b1
`define SS_DONE 1'b0

`define SM_IDLE 1'b1
`define SM_DONE 1'b0

`define AP_PROC 2'b00
`define AP_IDLE 2'b01
`define AP_DONE 2'b10

module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    //Tap_RAM AXI-Lite Interface
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata, 

    //Data_RAM input AXI-stream interface   
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready,

    //Output AXI-stream interfacee
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);
   
//---------------------FSM register configuration address map---------------
    reg [2:0]  ap_ctrl; 
    reg [1:0]  ap_state;
    reg [1:0]  next_ap_state;
   // ap_ctrl: bit 0: ap_start, bit 1: ap_done, bit 2: ap_idle
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n)
            ap_state <= `AP_IDLE;
        else
            ap_state <= next_ap_state;
    end

    always @* begin
        case (ap_state)
            `AP_IDLE:
            begin
                if (awaddr == 12'd0 && wdata[0] == 1 && tlast_cnt != data_length) begin
                    next_ap_state = `AP_PROC;
                end
                else begin
                    next_ap_state = `AP_IDLE;
                end  
            end
            `AP_PROC:
            begin
                if (sm_tvalid && sm_tlast) begin // output last Y
                    next_ap_state = `AP_DONE;
                end
                else begin
                    next_ap_state = `AP_PROC;
                end
            end
            `AP_DONE:
            begin
                if (araddr == 12'd0 && arvalid && rvalid) begin
                    next_ap_state = `AP_IDLE;
                end
                else begin
                    next_ap_state = `AP_DONE;
                end
            end
            default:
            begin
                if (awaddr == 12'd0 && wdata[0] == 1 && tlast_cnt != data_length) begin
                    next_ap_state = `AP_PROC; 
                end
                else begin
                    next_ap_state = `AP_IDLE;
                end 
            end
        endcase
    end
      
    always @* begin      
        /*------- ap_start --------*/
        //ap_ctrl[0] - ap_start (r/w) command 
        //When ap_start is programmed one, the FIR engine starts.
        if (ap_state == `AP_IDLE && awaddr == 12'd0 && wdata[0] == 1 && tlast_cnt != data_length)
            ap_ctrl[0] = 1;
        else
            ap_ctrl[0] = 0;
            
        /*-------- ap_done --------*/
        //ap_ctrl[1] - ap_done (rwc) status 
        //1: indicate FIR has processed all the dataset, i.e. receive last data X, and the last Y is transferred. 
        if (sm_tvalid && sm_tlast)
            ap_ctrl[1] = 1;
        else if (ap_state == `AP_DONE)
            ap_ctrl[1] = 1;
        else
            ap_ctrl[1] = 0;

        /*-------- ap_idle --------*/
        //ap_ctrl[2] - ap_idle (ro) status
        //1: indicate FIR is idle. 0: FIR is actively processing data
        if (ap_state == `AP_IDLE)
            ap_ctrl[2] = 1;
        else
            ap_ctrl[2] = 0;    
    
    end

    //-------------------------data length-----------------------------
    reg  [31:0] data_length;  // 0x10-14: data length
    wire [31:0] data_length_tmp;
    
    assign data_length_tmp = (awaddr == 8'h10)? wdata : data_length;
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n)
            data_length <= 0;
        else
            data_length <= data_length_tmp;
    end

//--------------------------ADDR GEN module----------------------------
//--------------------------Address tap------------------------
    wire [5:0] tap_AR;    // address which will send into tap_RAM
    reg  [3:0] k;
    wire [3:0] k_tmp;
    
    assign k_tmp = (k != 4'd10)? k+1 : 4'd0;

    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n || ap_ctrl[2])
            k <= 4'd10;
        else
            k <= k_tmp;
    end
    
    // if ap_idle = 0, use value of address generator
    assign tap_AR = (ap_ctrl[2] == 1'b0)? 4 * k : araddr[5:0]; // else, tb check value
//------------------------ Address Data --------------------------
    reg [3:0] x_cnt;
    reg [3:0] x_cnt_tmp;
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n)
            x_cnt <= 4'd0;
        else
            x_cnt <= x_cnt_tmp;
    end

    always @* begin
        if (ap_ctrl[2] == 1'b0) begin
            if (k == 4'd10)
                if (x_cnt != 4'd10)
                    x_cnt_tmp = x_cnt + 1'b1;
                else
                    x_cnt_tmp =  4'd0;
            else
                x_cnt_tmp = x_cnt;
        end
        else
            x_cnt_tmp = 4'd0;
    end
    
    // count x[t-i]   
    wire [5:0] data_A_tmp;
    assign data_A_tmp = (k <= x_cnt)? 4 * (x_cnt - k) : 4 * (11 + x_cnt - k);
    
//---------------------AXI Lite for tap_ram---------------------------
    reg ARREADY;
    reg AWREADY;
    reg WREADY;
    reg RVALID;
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            RVALID  <= 0;
            ARREADY <= 0;
            AWREADY <= 0;
            WREADY  <= 0;
        end else begin
            RVALID  <= (arvalid | rvalid & ~rready)? 1 : 0;
            ARREADY <= (arvalid)?                    1 : 0;
            AWREADY <= (awvalid && wvalid)?          1 : 0;
            WREADY  <= (awvalid && wvalid)?          1 : 0;
        end   
    end

    assign awready = AWREADY;
    assign arready = ARREADY; 
    assign wready  = WREADY;
    assign rvalid  = RVALID;
    assign rdata   = (araddr[7:0] == 8'd0)? ap_ctrl : tap_Do; // if read 0x00, ap_ctrl

    // 0x80-FF: tap parameter
    assign tap_EN = ((awaddr[11:7] == 0) && (araddr[11:7] == 0))? 1'b0 : 1'b1;
    assign tap_WE = ((wvalid == 1) && (awaddr[7:0] != 0))? 4'b1111 : 4'b0000;
    assign tap_A  = (awvalid == 1)? awaddr[5:0] : tap_AR[5:0]; 
    assign tap_Di = wdata;


//---------------------FSM AXI stream for X data_ram--------------------
    
    assign data_EN = ss_tvalid; 
    assign data_WE = (ss_tready & ss_idle || init_addr != 6'd44)? 4'b1111 : 4'b0000; 
    assign data_A  = (ap_ctrl[2] == 1 && init_addr != 6'd44)? init_addr : data_A_tmp; // data initialize before ap_start
    assign data_Di = (ap_ctrl[2] == 1 && init_addr != 6'd44)? 0 : ss_tdata;
    
    // data RAM  address initialize
    wire [5:0] next_init_addr;
    reg  [5:0] init_addr;
    
    assign next_init_addr = (init_addr == 6'd44)? init_addr : init_addr + 6'd4;
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n)
            init_addr <= -6'd4;
        else
            init_addr <= next_init_addr;
    end
    
    assign ss_tready = (ap_ctrl[2] == 0 && init_addr == 6'd44 && k == 4'd0)? 1'b1 : 1'b0; 
    
    //FSM
    reg ss_state;
    reg next_ss_state;
    reg ss_idle;
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n)
            ss_state <= `SS_DONE;
        else
            ss_state <= next_ss_state;
    end

    always @* begin
        case (ss_state)
        `SS_IDLE:
        begin
            if (ss_tvalid && ss_tlast) begin
                next_ss_state = `SS_DONE;
                ss_idle = 1;
            end
            else begin
                next_ss_state = `SS_IDLE;
                ss_idle = 1;
            end
        end
        `SS_DONE:
        begin
            if (ss_tvalid) begin
                next_ss_state = `SS_IDLE;
                ss_idle = 1;
            end
            else begin
                next_ss_state = `SS_DONE;
                ss_idle = 0;
            end
        end
        default:
        begin
            if (ss_tvalid) begin
                next_ss_state = `SS_IDLE;
                ss_idle = 1;
            end
            else begin
                next_ss_state = `SS_DONE;
                ss_idle = 0;
            end
        end
        endcase
    end
    
//-------------- FSM  AXI Stream output Y --------------------------
    //------------------ Count the cycle of output Y -----------------------
    reg  [4:0] y_cnt; 
    wire [4:0] y_cnt_tmp;
    
    assign y_cnt_tmp = (y_cnt != 6'd10 && ap_ctrl[2] == 1'b0)? y_cnt + 1'b1 : 5'd0;
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n || ap_ctrl[2])
            y_cnt <= 5'd0 - 5'd15; // 3 for operation pipeline, 11 for calculation
        else
            y_cnt <= y_cnt_tmp;
    end
      
    //-------------- For sm_tlast count to data length ------------------
    reg  [9:0] tlast_cnt;
    wire [9:0] tlast_cnt_tmp;
    
    assign tlast_cnt_tmp = (sm_tvalid == 1'b1)? tlast_cnt + 1'b1 : tlast_cnt;
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) 
            tlast_cnt <= 10'd0;
        else
            tlast_cnt <= tlast_cnt_tmp;
    end
    
    assign sm_tvalid = (y_cnt == 5'd0)? 1'b1 : 1'b0;    
    assign sm_tdata  = y;                               
    assign sm_tlast  = _sm_tlast;


    //FSM
    reg sm_state;
    reg next_sm_state;   
    reg _sm_tlast;
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n)
            sm_state <= `SM_DONE;
        else
            sm_state <= next_sm_state;
    end

    always @* begin
        case (sm_state)
            `SM_IDLE:
            begin
                if (tlast_cnt_tmp == data_length) begin
                    _sm_tlast     = 1'b1;
                    next_sm_state = `SM_DONE;
                end
                else begin
                    _sm_tlast     = 1'b0;
                    next_sm_state = `SM_IDLE;
                end
            end
            `SM_DONE:
            begin
                if (sm_tvalid == 1'b1) begin
                    _sm_tlast     = 1'b0;
                    next_sm_state = `SM_IDLE;
                end
                else begin
                    _sm_tlast     = 1'b0;
                    next_sm_state = `SM_DONE;
                end
            end
        endcase
    end

//---------------------Computing Core---------------------------
    reg  [(pDATA_WIDTH-1):0] h;
    reg  [(pDATA_WIDTH-1):0] x;
    reg  [(pDATA_WIDTH-1):0] m;
    reg  [(pDATA_WIDTH-1):0] y;
    
    wire [(pDATA_WIDTH-1):0] h_tmp;
    wire [(pDATA_WIDTH-1):0] x_tmp;
    wire [(pDATA_WIDTH-1):0] m_tmp;
    wire [(pDATA_WIDTH-1):0] y_tmp;

    assign h_tmp = tap_Do;          // h[i]
    assign x_tmp = data_Do;         // x[t-i]
    assign m_tmp = h * x;           // h[i] * x[t-i]
    assign y_tmp = m + y; 
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n || ap_ctrl[2]) begin
            h <= 32'd0;
            x <= 32'd0;
            m <= 32'd0;
            y <= 32'd0;
        end
        else begin
            h <= h_tmp;
            x <= x_tmp;
            m <= m_tmp;
            if (y_cnt == 4'd0)
                y <= 0;
            else
                y <= y_tmp;
        end
    end
endmodule
