//**************************************************************//
//																//
//	Simplified version of AHB transfer protocol					//
//																//
//**************************************************************//

import AES_address::*;

module ahb_interface(
                input  bit 			hclk_i,
                input  bit 			hreset_i,
                input  bit [31:0]	haddr_i,
                input  bit [31:0]	hwdata_i,
                input  bit     		hwrite_i,
				input  bit [ 1:0]	htrans_i,

				output bit [31:0]	hrdata_o,
				output bit			hreadyout_o,
				output bit 			hresp_o
               );


bit 		encdec_s;
bit 		init_s;
bit 		next_s;
bit 		ready_s;
bit 		keylen_s;
bit [255:0]	key_s;
bit [127:0]	block_s;
bit [127:0]	result_s;
bit 		result_valid_s;
bit 		set_address_s;
bit 		data_set_s;

bit [31:0]	regbank_s [0:31];
bit [ 1:0] 	regbank_access_s [0:31];
bit [31:0]	address_ahb_s;

bit 		error_ready_s,error_start;
bit 		error_start_forbidden_addr_s;
bit 		error_cycle_counter;
bit 		forbidden_address_error_s;
bit			hwrite_s;
bit 		init_pulse_s;
bit 		next_pulse_s;
bit 		pulse_en_s;

int 		i;

  	aes_core aes_core_u(
		.clk(hclk_i),
		.reset_n(hreset_i),

		.encdec(encdec_s),
		.init(init_s),
		.next(next_s),
		.ready(ready_s),

		.key(key_s),
		.keylen(keylen_s),

		.block(block_s),
		.result(result_s),
		.result_valid(result_valid_s)
    );

assign hreadyout_o = ready_s & error_ready_s;

always @(posedge hclk_i, negedge hreset_i) begin
	if(hreset_i == 0) begin
		hwrite_s			<= 0;
		address_ahb_s 		<= 0;
	end else begin
		if(htrans_i == HTRANS_NONSEQ) begin
			address_ahb_s <= haddr_i;
		end

		if (hwrite_i == 1 && hreadyout_o == 1) begin
			hwrite_s			<= 1;			
		end else begin
			hwrite_s			<= 0;
		end
	end
end

// Writing into regbank
always @(posedge hclk_i, negedge hreset_i) begin
	if(hreset_i == 0) begin
		for(i=0;i<16;i=i+1) begin
			regbank_s[i] 	<= 0;
		end
		pulse_en_s <= 1'b0;
		init_pulse_s <= 1'b0;
        next_pulse_s <= 1'b0;
	end else begin
		pulse_en_s <= 1'b0;
		init_pulse_s <= 1'b0;
        next_pulse_s <= 1'b0;
		if(hresp_o == 0 && hreadyout_o == 1) begin //no error
			if (hwrite_s == 1) begin	
			 	case (regbank_access_s[address_ahb_s])
                	READ_WRITE: begin
                	    regbank_s[address_ahb_s] <= hwdata_i;
                	end
	
                	WRITE1PULSE: begin
                	    regbank_s[address_ahb_s] <= '0; // or keep it unchanged
                	    pulse_en_s <= 1'b1;
                	    if (address_ahb_s == AES_CTRL_address) begin
                	        if (hwdata_i[CTRL_OFFSET_INIT]) init_pulse_s <= 1'b1;
                	        if (hwdata_i[CTRL_OFFSET_NEXT]) next_pulse_s <= 1'b1;
                	    end 
                	end
	
                	default: begin
                	    // READ_ONLY / RESERVED: ignore write
                	end
            	endcase
			end
		end


		// Update status and output registers
		regbank_s[AES_STATUS_address]	= {23'b0,result_valid_s,7'b0,ready_s};
		regbank_s[AES_OUT_address_W3]	= result_s[ 127: 96];
		regbank_s[AES_OUT_address_W2]	= result_s[  95: 64];
		regbank_s[AES_OUT_address_W1]	= result_s[  63: 32];
		regbank_s[AES_OUT_address_W0]	= result_s[  31:  0];	
		regbank_s[AES_TESTREAD_address] = 32'hFAD0CAFE;
	end
end

// Reading regbank
always @(*) begin
	if(hresp_o == 0 && hreadyout_o == 1) begin //no error
		hrdata_o = regbank_s[address_ahb_s];
	end else begin
		hrdata_o = '0;	
	end
end

/////////////////////
// Error management
/////////////////////

// forbidden address error
always @(*) begin
	if(regbank_access_s[haddr_i] == RESERVED && htrans_i == HTRANS_NONSEQ) begin //Forbidden address error
		error_start_forbidden_addr_s = 1;
		forbidden_address_error_s = 1;		
	end	else begin
		error_start_forbidden_addr_s = 0;
		forbidden_address_error_s = 0;
	end
end

//error signals
always @(*) begin
	if(hreset_i == 0) begin
		hresp_o 		= HRESP_OK;
		error_ready_s 	= 1;
		error_start 	= 0;
	end else 
	if( forbidden_address_error_s == 1) begin
		hresp_o		 	= HRESP_ERROR;
		error_ready_s 	= 0;
		error_start 	= 1;
	end else if(error_cycle_counter == 1) begin
		hresp_o 		= HRESP_ERROR;
		error_ready_s 	= 1;
		error_start 	= 0;
	end else begin
		hresp_o 		= HRESP_OK;
		error_ready_s 	= 1;
		error_start 	= 0;
	end
end

//error counter
always @(posedge hclk_i, negedge hreset_i) begin
	if(hreset_i == 0) begin
		error_cycle_counter = 0;
	end	else begin
		if(error_start_forbidden_addr_s == 0) begin
			error_cycle_counter = 0;
		end else if (error_start == 1) begin
			error_cycle_counter = 1;
		end else begin
			error_cycle_counter = (error_cycle_counter +1)%2;
		end
	end
end


// managing AHB addresses
always @(*) begin
	
	keylen_s			= regbank_s[AES_PARAM_address][PARAM_OFFSET_KEYLEN];
	encdec_s			= regbank_s[AES_PARAM_address][PARAM_OFFSET_ENCDEC];
	if(pulse_en_s == 0) begin
		init_s				= regbank_s[AES_CTRL_address ][CTRL_OFFSET_INIT];
		next_s				= regbank_s[AES_CTRL_address ][CTRL_OFFSET_NEXT];
	end else begin
		init_s				= init_pulse_s;
		next_s				= next_pulse_s;
	end

	key_s[ 255:224]		= regbank_s[AES_KEY_address_W7];
	key_s[ 223:192]		= regbank_s[AES_KEY_address_W6];
	key_s[ 191:160]		= regbank_s[AES_KEY_address_W5];
	key_s[ 159:128]		= regbank_s[AES_KEY_address_W4];
	key_s[ 127: 96]		= regbank_s[AES_KEY_address_W3];
	key_s[  95: 64]		= regbank_s[AES_KEY_address_W2];
	key_s[  63: 32]		= regbank_s[AES_KEY_address_W1];
	key_s[  31:  0]		= regbank_s[AES_KEY_address_W0];

	block_s[ 127: 96]	= regbank_s[AES_DATA_address_W3];
	block_s[  95: 64]	= regbank_s[AES_DATA_address_W2];
	block_s[  63: 32]	= regbank_s[AES_DATA_address_W1];
	block_s[  31:  0]	= regbank_s[AES_DATA_address_W0];

	regbank_s[AES_STATUS_address]	= {23'b0,result_valid_s,7'b0,ready_s};
	regbank_s[AES_OUT_address_W3]	= result_s[ 127: 96];
	regbank_s[AES_OUT_address_W2]	= result_s[  95: 64];
	regbank_s[AES_OUT_address_W1]	= result_s[  63: 32];
	regbank_s[AES_OUT_address_W0]	= result_s[  31:  0];	
	regbank_s[AES_TESTREAD_address] = 32'hFAD0CAFE;
end

// Regbank access

genvar g;

generate
	for(g=AES_TESTREAD_address+1 ; g<32 ; g=g+1) begin : empty_addresses
		assign regbank_access_s[g] = RESERVED;
	end
endgenerate
 

assign regbank_access_s[AES_PARAM_address]   	= AES_PARAM_access;
assign regbank_access_s[AES_CTRL_address]    	= AES_CTRL_access;
assign regbank_access_s[AES_TESTREAD_address]	= AES_TESTREAD_access;
	
assign regbank_access_s[AES_KEY_address_W7]  	= AES_KEY_access_W7;
assign regbank_access_s[AES_KEY_address_W6]  	= AES_KEY_access_W6;
assign regbank_access_s[AES_KEY_address_W5]  	= AES_KEY_access_W5;
assign regbank_access_s[AES_KEY_address_W4]  	= AES_KEY_access_W4;
assign regbank_access_s[AES_KEY_address_W3]  	= AES_KEY_access_W3;
assign regbank_access_s[AES_KEY_address_W2]  	= AES_KEY_access_W2;
assign regbank_access_s[AES_KEY_address_W1]  	= AES_KEY_access_W1;
assign regbank_access_s[AES_KEY_address_W0]  	= AES_KEY_access_W0;
	
assign regbank_access_s[AES_DATA_address_W3] 	= AES_DATA_access_W3;
assign regbank_access_s[AES_DATA_address_W2] 	= AES_DATA_access_W2;
assign regbank_access_s[AES_DATA_address_W1] 	= AES_DATA_access_W1;
assign regbank_access_s[AES_DATA_address_W0] 	= AES_DATA_access_W0;
	
assign regbank_access_s[AES_STATUS_address]	 	= AES_STATUS_access;
	
assign regbank_access_s[AES_OUT_address_W3]	 	= AES_OUT_access_W3;
assign regbank_access_s[AES_OUT_address_W2]	 	= AES_OUT_access_W2;
assign regbank_access_s[AES_OUT_address_W1]	 	= AES_OUT_access_W1;
assign regbank_access_s[AES_OUT_address_W0]	 	= AES_OUT_access_W0;

endmodule