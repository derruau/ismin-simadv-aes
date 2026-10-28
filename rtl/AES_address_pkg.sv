package AES_address;

	parameter 	 HRESP_OK 		= 1'b0;
	parameter 	 HRESP_ERROR	= 1'b1;

	parameter 	 HTRANS_IDLE	= 2'b00;
	parameter 	 HTRANS_NONSEQ 	= 2'b10;

	parameter 	 RESERVED   	= 4'b0000;
	parameter 	 READ_ONLY  	= 4'b0001;
	parameter 	 READ_WRITE 	= 4'b0010;
	parameter 	 WRITE1PULSE 	= 4'b0011;

	// address decoding
	parameter	 AES_STATUS_address = 32'h14;
	parameter	 AES_STATUS_access = READ_ONLY;	
	parameter	 STATUS_OFFSET_READY = 32'h00;
	parameter	 STATUS_OFFSET_RESULTVALID = 32'h08;

	parameter	 AES_TESTREAD_address = 32'h15;
	parameter	 AES_TESTREAD_access = READ_ONLY;

	parameter	 AES_CTRL_address = 32'h00;
	parameter	 AES_CTRL_access = READ_WRITE;
	parameter	 CTRL_OFFSET_INIT = 32'h00;
	parameter	 CTRL_OFFSET_NEXT = 32'h08;

	parameter	 AES_PARAM_address = 32'h01;
	parameter	 AES_PARAM_access = READ_WRITE;
	parameter	 PARAM_OFFSET_KEYLEN = 32'h00;
	parameter	 PARAM_OFFSET_ENCDEC = 32'h08;

	parameter	 AES_DATA_address_W0 = 32'h02;
	parameter	 AES_DATA_address_W1 = 32'h03;
	parameter	 AES_DATA_address_W2 = 32'h04;
	parameter	 AES_DATA_address_W3 = 32'h05;
	
	parameter	 AES_DATA_access_W0 = READ_WRITE;
	parameter	 AES_DATA_access_W1 = READ_WRITE;
	parameter	 AES_DATA_access_W2 = READ_WRITE;
	parameter	 AES_DATA_access_W3 = READ_WRITE;

	parameter	 AES_KEY_address_W0 = 32'h06;
	parameter	 AES_KEY_address_W1 = 32'h07;
	parameter	 AES_KEY_address_W2 = 32'h08;
	parameter	 AES_KEY_address_W3 = 32'h09;
	parameter	 AES_KEY_address_W4 = 32'h0A;
	parameter	 AES_KEY_address_W5 = 32'h0B;
	parameter	 AES_KEY_address_W6 = 32'h0C;
	parameter	 AES_KEY_address_W7 = 32'h0D;

	parameter	 AES_KEY_access_W0 = READ_WRITE;
	parameter	 AES_KEY_access_W1 = READ_WRITE;
	parameter	 AES_KEY_access_W2 = READ_WRITE;
	parameter	 AES_KEY_access_W3 = READ_WRITE;
	parameter	 AES_KEY_access_W4 = READ_WRITE;
	parameter	 AES_KEY_access_W5 = READ_WRITE;
	parameter	 AES_KEY_access_W6 = READ_WRITE;
	parameter	 AES_KEY_access_W7 = READ_WRITE;

	parameter	 AES_OUT_address_W0 = 32'h10;
	parameter	 AES_OUT_address_W1 = 32'h11;
	parameter	 AES_OUT_address_W2 = 32'h12;
	parameter	 AES_OUT_address_W3 = 32'h13;

	parameter	 AES_OUT_access_W0 = READ_ONLY;
	parameter	 AES_OUT_access_W1 = READ_ONLY;
	parameter	 AES_OUT_access_W2 = READ_ONLY;
	parameter	 AES_OUT_access_W3 = READ_ONLY;


endpackage
