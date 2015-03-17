`define REG_PADDIR      4'b0000 //BASEADDR+0x00
`define REG_PADIN       4'b0001 //BASEADDR+0x04
`define REG_PADOUT      4'b0010 //BASEADDR+0x08
`define REG_INTEN       4'b0011 //BASEADDR+0x0C
`define REG_INTTYPE0    4'b0100 //BASEADDR+0x10
`define REG_INTTYPE1    4'b0101 //BASEADDR+0x14
`define REG_INTSTATUS   4'b0110 //BASEADDR+0x18

`define REG_PADCFG0     4'b1000 //BASEADDR+0x18
`define REG_PADCFG1     4'b1001 //BASEADDR+0x18
`define REG_PADCFG2     4'b1010 //BASEADDR+0x18
`define REG_PADCFG3     4'b1011 //BASEADDR+0x18
`define REG_PADCFG4     4'b1100 //BASEADDR+0x18

module apb_gpio #(
		parameter APB_ADDR_WIDTH = 12  //APB slaves are 4KB by default
		parameter PADCFG_BITS = 5      //how many bits are used for pad configuration
		) (
	input  logic                      HCLK,
	input  logic                      HRESETn,
	input  logic [APB_ADDR_WIDTH-1:0] PADDR,
	input  logic               [31:0] PWDATA,
	input  logic                      PWRITE,
	input  logic                      PSEL,
	input  logic                      PENABLE,
	output logic               [31:0] PRDATA,
	output logic                      PREADY,
	output logic                      PSLVERR,

	input  logic               [31:0] gpio_in,
	output logic               [31:0] gpio_out,
	output logic               [31:0] gpio_dir,
	output logic      [31:0]    [4:0] gpio_padcfg,
	output logic                      interrupt
	
	);
	
    logic [PADCFG_BITS-1:0] [31:0] r_gpio_padcfg;

	logic [31:0] r_gpio_inten;
	logic [31:0] r_gpio_inttype0;
	logic [31:0] r_gpio_inttype1;
	logic [31:0] r_gpio_fun0;
	logic [31:0] r_gpio_fun1;
	logic [31:0] r_gpio_out;
	logic [31:0] r_gpio_dir;
	logic [31:0] r_gpio_sync0;
	logic [31:0] r_gpio_sync1;
	logic [31:0] r_gpio_in;
	logic [31:0] s_gpio_rise;
	logic [31:0] s_gpio_fall;
	logic [31:0] s_is_int_rise;
	logic [31:0] s_is_int_fall;
	logic [31:0] s_is_int_lev0;
	logic [31:0] s_is_int_lev1;
	logic [31:0] s_is_int_all;
	logic        s_rise_int;
	
	logic  [3:0] s_apb_addr;

    logic [31:0] r_status;

	assign s_apb_addr = PADDR[5:2];
	
	assign s_gpio_rise = r_gpio_sync1 & ~r_gpio_in; //foreach input check if rising edge 
	assign s_gpio_fall = ~r_gpio_sync1 & r_gpio_in; //foreach input check if falling edge 
	
	assign s_is_int_rise =  r_gpio_inttype1 & ~r_gpio_inttype0 & s_gpio_rise; // inttype 01 rise
	assign s_is_int_fall =  r_gpio_inttype1 &  r_gpio_inttype0 & s_gpio_fall; // inttype 00 fall
	assign s_is_int_lev0 = ~r_gpio_inttype1 &  r_gpio_inttype0 & ~r_gpio_in;  // inttype 10 level 0
	assign s_is_int_lev1 = ~r_gpio_inttype1 & ~r_gpio_inttype0 &  r_gpio_in;  // inttype 11 level 1
	
	//check if bit if interrupt is enable and if interrupt specified by inttype occurred 
	assign s_is_int_all  = r_gpio_inten & (s_is_int_rise | s_is_int_fall | s_is_int_lev0 | s_is_int_lev1);
	
	//is any bit enabled and specified interrupt happened?
	assign s_rise_int = |s_is_int_all;
	
	always @ (posedge HCLK or negedge HRESETn) begin
		if(~HRESETn) 
        begin
			interrupt = 1'b0;
            r_status  =  'h0;
        end
		else
			if (!interrupt && s_rise_int ) //rise interrupt if not already rise
            begin
				interrupt = 1'b1;
                r_status  = s_is_int_all;
            end
			else if (interrupt && PSEL && PENABLE && !PWRITE && (s_apb_addr == `REG_INTSTATUS)) //clears int if status is read
            begin
				interrupt = 1'b0;
                r_status  =  'h0;
            end
	end
	
	always @ (posedge HCLK or negedge HRESETn) begin
		if(~HRESETn) begin
			r_gpio_sync0    = 'h0;
			r_gpio_sync1    = 'h0;
			r_gpio_in       = 'h0;
		end
		else begin
			r_gpio_sync0    = gpio_in;      //first 2 sync for metastability resolving
			r_gpio_sync1    = r_gpio_sync0;
			r_gpio_in       = r_gpio_sync1; //last reg used for edge detection
		end
	end //always

	always @ (posedge HCLK or negedge HRESETn) begin
		if(~HRESETn) begin
			r_gpio_inten    = 'h0;
			r_gpio_inttype0 = 'h0;
			r_gpio_inttype1 = 'h0;
			r_gpio_out      = 'h0;
			r_gpio_dir      = 'h0;
		end
		else begin
			if (PSEL && PENABLE && PWRITE)
			begin
				case (s_apb_addr)
				`REG_PADDIR:
					r_gpio_dir = PWDATA;
				`REG_PADOUT:	
					r_gpio_out = PWDATA;
				`REG_INTEN:
					r_gpio_inten = PWDATA;
				`REG_INTTYPE0:
					r_gpio_inttype0 = PWDATA;
				`REG_INTTYPE1:
					r_gpio_inttype1 = PWDATA;
                `REG_PADCFG0:
                    r_gpio_padcfg[0] = PWDATA;
                `REG_PADCFG1:
                    r_gpio_padcfg[1] = PWDATA;
                `REG_PADCFG2:
                    r_gpio_padcfg[2] = PWDATA;
                `REG_PADCFG3:
                    r_gpio_padcfg[3] = PWDATA;
                `REG_PADCFG4:
                    r_gpio_padcfg[4] = PWDATA;
				endcase
			end
		end
	end //always

	always_comb
	begin
		case (s_apb_addr)
			`REG_PADDIR:
				PRDATA = r_gpio_dir;
			`REG_PADIN:	
				PRDATA = r_gpio_in;
			`REG_PADOUT:	
				PRDATA = r_gpio_out;
			`REG_INTEN:
				PRDATA = r_gpio_inten;
			`REG_INTTYPE0:
				PRDATA = r_gpio_inttype0;
			`REG_INTTYPE1:
				PRDATA = r_gpio_inttype1;
			`REG_INTSTATUS:
				PRDATA = r_status;
		endcase
	end

    always_comb
    begin
        for(int i=0;i<32;i++)
            gpio_padcfg[i] = {r_gpio_padcfg[4][i],r_gpio_padcfg[3][i],r_gpio_padcfg[2][i],r_gpio_padcfg[1][i],r_gpio_padcfg[0][i]};
    end

    assign gpio_out = r_gpio_out;
    assign gpio_dir = r_gpio_dir;
    
    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;
    
endmodule

