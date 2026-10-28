`timescale 1ns/1ps

import "DPI-C" function void python_initialize_c();
import "DPI-C" function void python_finalize_c();
import "DPI-C" function string aes_c(input string dataIn, input string keyIn, input int encdec);

import AES_address::*;

typedef enum logic { 
  AES_128_BIT_KEY = '0, 
  AES_256_BIT_KEY = '1 
} aes_keylength_t;

typedef enum logic { 
  AES_DECIPHER = '0,
  AES_ENCIPHER = '1
} aes_operation_t;
 
class Inputs; 
  rand logic[127:0]     cleartext;
  rand logic[255:0]     key;
  rand aes_keylength_t  keylen;
  rand aes_operation_t  encdec;

  constraint keylen_range { keylen inside {AES_128_BIT_KEY, AES_256_BIT_KEY}; }
  constraint aes_method { encdec inside {AES_DECIPHER, AES_ENCIPHER}; }
endclass: Inputs

module aes_tb #(
  parameter string OUTPUT_FILENAME    = "data/TD3_data_out.csv",  // Path to the output file to write the encrypted values to
  parameter int CLK_FREQ_MHZ          = 50,                       // Clock frequency in MHz
  parameter int DEFAULT_NB_ITERATION  = 100                       // Default number of times a random test is generated

)();
  //----------------------------------------------------------------
  // Type definitions
  //----------------------------------------------------------------

  localparam realtime CLK_PERIOD_NS       = 1000ns / CLK_FREQ_MHZ;
  localparam realtime CLK_HALF_PERIOD_NS  = CLK_PERIOD_NS/ 2;

  //----------------------------------------------------------------
  // Variables
  //----------------------------------------------------------------

  // DUT variables
  logic         hclk_tb;
  logic         hreset_tb;
  logic [31:0]  haddr_tb;
  logic [31:0]  hwdata_tb;
  logic         hwrite_tb;
  logic [ 1:0]  htrans_tb;
  logic [31:0]  hrdata_tb;
  logic         hreadyout_tb;
  logic         hresp_tb;

  // Statistics
  int round;
  int successful_encryption_counter;

  //----------------------------------------------------------------
  // DUT.
  //----------------------------------------------------------------
  ahb_interface dut(
    .hclk_i       (hclk_tb),
    .hreset_i     (hreset_tb),
    
    .haddr_i      (haddr_tb),
    .hwdata_i     (hwdata_tb),
    .hwrite_i     (hwrite_tb),
    .htrans_i     (htrans_tb),

    .hrdata_o     (hrdata_tb),
    .hreadyout_o  (hreadyout_tb),
    .hresp_o      (hresp_tb)
  );

  //----------------------------------------------------------------
  // Clock generation.
  //----------------------------------------------------------------
  initial begin : clk_gen
    hclk_tb = 1'b0;
    forever #CLK_HALF_PERIOD_NS hclk_tb = ~hclk_tb;
  end

  //----------------------------------------------------------------
  // Test
  //----------------------------------------------------------------
  initial begin
    // File descriptors
    int fd_o;

    // Internal signals
    int status_int;
    int iteration_nb_int;

    // Randomly generated inputs
    Inputs ival;

    // Holds the result of the testbench
    logic [127:0] testbench_result;

    // Python bridge variables
    logic [127:0] parsed_result_py;

    // Number of random tests initialization
    iteration_nb_int = DEFAULT_NB_ITERATION;
    status_int = $value$plusargs("iteration_nb_int=%d",iteration_nb_int);
    if (!status_int) $display("Parameter iteration_nb_int not passed, setting it to default value %0d", DEFAULT_NB_ITERATION);

    // Random tests class initialization
    ival = new();

    // Opening files
    fd_o = $fopen(OUTPUT_FILENAME, "w");

    // Verification
    if (!fd_o) $fatal("Could not open the output file!");

    // Writing CSV column definition
    $fwrite(fd_o, "data_in, key_in, encdec, testbench_result, parsed_result_py\n");

    // Python initialization
    python_initialize_c();

    round = 0;
    successful_encryption_counter = 0;

    // Initializing simulation signals
    init_sim();

    while (round < iteration_nb_int) begin
      
      if (!ival.randomize()) begin
        $fatal("ERROR: Could not randomize input!");
      end

      // Encrypt changes name to compute because
      // it can now either encrypt or decrypt.
      compute(ival, testbench_result);
      compute_python(ival, parsed_result_py);

      // Write results to CSV
      $fwrite(
        fd_o, 
        "%032h, %064h, %01h, %032h, %s\n", 
        ival.cleartext,
        ival.keylen == AES_128_BIT_KEY ? ival.key[255:128] : ival.key,
        ival.encdec,
        testbench_result,
        parsed_result_py
      );

      // Comparing testbench results to the python script's result
      check_result(ival, testbench_result, parsed_result_py);
    end

    // Closing files
    $fclose(fd_o);

    // Closing python
    python_finalize_c();

    $display("%0d / %0d tests sucessful!", successful_encryption_counter, round);

    // Leave one clock cycle visible after the result before stopping.
    @(posedge hclk_tb);
    $finish;
  end

  //----------------------------------------------------------------
  // Testbench initialisation and DUT reset
  //----------------------------------------------------------------
  task init_sim;
  begin

      // Valeurs AHB par défaut
      haddr_tb  = 32'b0;
      hwdata_tb = 32'b0;
      hwrite_tb = 1'b0;
      htrans_tb = 2'b00;   // IDLE

      reset_dut();
  end
  endtask

  //----------------------------------------------------------------
  // Selects the operation and the key length
  //----------------------------------------------------------------
  task setup_operation(input logic encdec, input logic keylen);
    begin
      logic [31:0] aes_param_content_s;

      // On doit mettre keylen dans le bit 2^0 et encdec dans le 2^8
      aes_param_content_s = '0;
      aes_param_content_s[PARAM_OFFSET_KEYLEN] = keylen;
      aes_param_content_s[PARAM_OFFSET_ENCDEC] = encdec;
      simple_write(AES_PARAM_address, aes_param_content_s);
    end
  endtask

  //----------------------------------------------------------------
  // Sets the key and the data to encipher/decipher
  //----------------------------------------------------------------
  task send_data(input logic [127:0] data_in, input logic [255:0] key_in);
    begin
      // Ecriture de la donnée
      simple_write(AES_DATA_address_W0, data_in[31:0]);
      simple_write(AES_DATA_address_W1, data_in[63:32]);
      simple_write(AES_DATA_address_W2, data_in[95:64]);
      simple_write(AES_DATA_address_W3, data_in[127:96]);

      // Ecriture de la clé
      simple_write(AES_KEY_address_W0, key_in[31:0]);
      simple_write(AES_KEY_address_W1, key_in[63:32]);
      simple_write(AES_KEY_address_W2, key_in[95:64]);
      simple_write(AES_KEY_address_W3, key_in[127:96]);
      simple_write(AES_KEY_address_W4, key_in[159:128]);
      simple_write(AES_KEY_address_W5, key_in[191:160]);
      simple_write(AES_KEY_address_W6, key_in[223:192]);
      simple_write(AES_KEY_address_W7, key_in[255:224]);
    end
  endtask

  //----------------------------------------------------------------
  // Wait until a bit in the AES_STATUS_address register is set to 1.
  //----------------------------------------------------------------
  task wait_computation_end(input logic [4:0] bit_offset);
    logic [31:0] aes_status_content_s;
    int timeout;
    begin
      timeout = 0;

      do begin
        simple_read(AES_STATUS_address, aes_status_content_s);
        timeout++;

        if (timeout > 500)         
        $fatal(
          1,
          "Timeout waiting for AES_STATUS[%0d]",
          bit_offset
        );
      end while (aes_status_content_s[bit_offset] !== 1'b1);

    end
  endtask

  //----------------------------------------------------------------
  // Proceeds to the whole compute operation (encryption OR decryption)
  //----------------------------------------------------------------
  task compute(input Inputs ival, output logic [127:0] ct_result);
    begin
      init_sim();

      // Operations to do + sending the data and key
      setup_operation(ival.encdec, ival.keylen);
      send_data(ival.cleartext, ival.key);

      //----------------------------------------------------------------
      // Initializing keys computation (W1P)
      //----------------------------------------------------------------
      write_w1p_bit(AES_CTRL_address, CTRL_OFFSET_INIT);
      wait_computation_end(STATUS_OFFSET_READY);

      //----------------------------------------------------------------
      // Starting bloc encryption
      //----------------------------------------------------------------
      write_w1p_bit(AES_CTRL_address, CTRL_OFFSET_NEXT);
      wait_computation_end(STATUS_OFFSET_RESULTVALID);

      simple_read(AES_OUT_address_W0, ct_result[31:0]);
      simple_read(AES_OUT_address_W1, ct_result[63:32]);
      simple_read(AES_OUT_address_W2, ct_result[95:64]);
      simple_read(AES_OUT_address_W3, ct_result[127:96]);
    end
  endtask

  //----------------------------------------------------------------
  // Python AES computation
  //----------------------------------------------------------------
  task compute_python(
      input Inputs ival,
      output logic [127:0] result_out
  );
      string data_in_py, key_in_py, result_py;

      int encdec_val;
      int status_int;

      // Convert inputs to hexadecimal strings and ints
      data_in_py = $sformatf("%032h", ival.cleartext); 
      set_key_for_c(ival, key_in_py);
      encdec_val = int'(ival.encdec);

      // Call Python AES implementation
      result_py = aes_c(data_in_py, key_in_py, encdec_val);

      // Convert Python result to logic [127:0]
      status_int = $sscanf(result_py, "%h", result_out);

      if (status_int != 1)
          $fatal(1, "Could not parse Python result: %s", result_py);
  endtask

  //----------------------------------------------------------------
  // We use $sformatf to convert the inputs to strings
  // instead of string'(), because we are not simply typecasting.
  // Rather, we are converting the input values into strings
  // containing their actual hexadecimal representation.
  //----------------------------------------------------------------
  task set_key_for_c(input Inputs ival, output string key_in_py);
    begin
      if (ival.keylen == AES_128_BIT_KEY) 
        key_in_py = $sformatf("%032h", ival.key[255:128]);
      else 
        key_in_py = $sformatf("%064h", ival.key);
    end
  endtask


  //----------------------------------------------------------------
  //  AHB write to one address
  //----------------------------------------------------------------
  task simple_write(input logic [31:0] addr, input logic [31:0] data);
    begin
      // Adressing phase
      @(negedge hclk_tb);

      haddr_tb  = addr;
      hwrite_tb = 1'b1;
      htrans_tb = 2'b10;       // NONSEQ

      // Wait until the address phase is ready
      do begin
        @(posedge hclk_tb);
      end while (hreadyout_tb !== 1'b1);

      // Data phase
      @(negedge hclk_tb);

      hwdata_tb = data;

      // No transfer afterwards
      htrans_tb = 2'b00;       // IDLE
      hwrite_tb = 1'b0;

      // Wait until data phase is ready
      do begin
        @(posedge hclk_tb);
      end while (hreadyout_tb !== 1'b1);

      @(negedge hclk_tb);
      if (hresp_tb !== 1'b0) $fatal(1, "AHB error response at address 0x%08h", addr);
    end
  endtask


  //----------------------------------------------------------------
  // AHB W1P write to one address
  //----------------------------------------------------------------
  task write_w1p_bit( input logic [31:0] addr, input logic [4:0]  bit_offset);
    logic [31:0] w1p_buffer_s;

    begin
      w1p_buffer_s = '0;
      w1p_buffer_s[bit_offset] = 1'b1;

      // First transaction: writing 1

      // Adressing phase
      @(negedge hclk_tb);

      haddr_tb  = addr;
      hwrite_tb = 1'b1;
      htrans_tb = HTRANS_NONSEQ;

      // Wait until the address phase is ready
      do begin
          @(posedge hclk_tb);
      end while (hreadyout_tb !== 1'b1);

      // Data phase for the 1
      // AND address phase for the 0
      // Second transaction: writing 0

      @(negedge hclk_tb);

      hwdata_tb = w1p_buffer_s;

      // IMPORTANT:
      // keeping hwrite_tb to 1 because we write the 0.
      haddr_tb  = addr;
      hwrite_tb = 1'b1;
      htrans_tb = HTRANS_NONSEQ;

      @(posedge hclk_tb);

      // Data phase for the 0

      @(negedge hclk_tb);

      hwdata_tb = 32'b0;

      // No more transactions afterwards
      hwrite_tb = 1'b0;
      htrans_tb = HTRANS_IDLE;

      @(posedge hclk_tb);

      @(negedge hclk_tb);

      if (hresp_tb !== HRESP_OK)
          $fatal(
              1,
              "AHB error response during W1P at address 0x%08h",
              addr
          );
    end
  endtask

  //----------------------------------------------------------------
  // AHB read one address
  //----------------------------------------------------------------
  task simple_read(input  logic [31:0] addr, output logic [31:0] data);
    begin
      // Adressing phase
      @(negedge hclk_tb);

      haddr_tb  = addr;
      hwrite_tb = 1'b0;
      htrans_tb = 2'b10;       // NONSEQ

      // Wait until the address phase is ready
      do begin
        @(posedge hclk_tb);
      end while (hreadyout_tb !== 1'b1);

      // Data phase
      @(negedge hclk_tb);

      htrans_tb = 2'b00;       // IDLE

      // Wait until data phase is ready
      do begin
        @(posedge hclk_tb);
      end while (hreadyout_tb !== 1'b1);

      @(negedge hclk_tb);
      data = hrdata_tb;

      if (hresp_tb !== 1'b0) $fatal(1, "AHB error response at address 0x%08h", addr);
    end
  endtask

  //----------------------------------------------------------------
  // Comparing the testbench result with the awaited result
  //----------------------------------------------------------------
  task check_result(
    input Inputs ival,
    input logic [127:0] actual,
    input logic [127:0] expected
    );
  begin
    if (actual === expected) begin
      successful_encryption_counter++;
      $display("Success (round %02d)", round);
    end
    else begin
      $display("Failure (round %02d):", round);
      $display("  Cleartext: 0x%032h", ival.cleartext);
      $display("  Key length: %s",
         ival.keylen == AES_128_BIT_KEY ?
         "AES-128" : "AES-256");
      $display("  Key:       0x%032h", ival.key);
      $display("  RTL:       0x%032h", actual);
      $display("  Python:    0x%032h", expected);
    end
    round++;
  end
  endtask

  //----------------------------------------------------------------
  // Reset du DUT
  //----------------------------------------------------------------
  task reset_dut;
    begin
      hreset_tb = 1'b0;

      repeat (2)
          @(posedge hclk_tb);

      @(negedge hclk_tb);
      hreset_tb = 1'b1;

      @(posedge hclk_tb);
    end
  endtask


  //----------------------------------------------------------------
  // Assertions
  //----------------------------------------------------------------
  property HTRANS_val;
    @(posedge hclk_tb)
    disable iff (!hreset_tb)
    htrans_tb inside {2'b00, 2'b10};
  endproperty

  assert property(HTRANS_val) else 
    $warning("ASSERTION WARNING: HTRANS_val not valid!");

  
  property HADDR_range;
    @(posedge hclk_tb)
    disable iff (!hreset_tb)
    haddr_tb inside {
      AES_PARAM_address,

      AES_DATA_address_W0,
      AES_DATA_address_W1,
      AES_DATA_address_W2,
      AES_DATA_address_W3,

      AES_KEY_address_W0,
      AES_KEY_address_W1,
      AES_KEY_address_W2,
      AES_KEY_address_W3,
      AES_KEY_address_W4,
      AES_KEY_address_W5,
      AES_KEY_address_W6,
      AES_KEY_address_W7,

      AES_STATUS_address,

      AES_CTRL_address,

      AES_OUT_address_W0,
      AES_OUT_address_W1,
      AES_OUT_address_W2,
      AES_OUT_address_W3
    };
  endproperty

  assert property(HADDR_range) else 
    $error("ASSERTION ERROR: HADDR_range not valid!");


  property HADDR_access;
    @(posedge hclk_tb)
    disable iff (!hreset_tb)

    // Overlapping implication operator.
    // Only when the first condition is true does the
    // second condition is evaluated.
    (htrans_tb == HTRANS_NONSEQ) |->
      (
        hwrite_tb
          ? dut.regbank_access_s[haddr_tb][1] == 1'b1
          : dut.regbank_access_s[haddr_tb][0] == 1'b1
      );
  endproperty

  assert property(HADDR_access) else
    $error("ASSERTION ERROR: HADDR_access not valid!");

  property HTRANS_stable;
    @(posedge hclk_tb)
    disable iff (!hreset_tb)

    (htrans_tb == HTRANS_NONSEQ && !hreadyout_tb)
      |=> ($stable(haddr_tb) &&
          $stable(hwrite_tb) &&
          $stable(htrans_tb));
  endproperty

  assert property (HTRANS_stable) else
    $error("ASSERTION ERROR: HTRANS_stable not valid!");


  //----------------------------------------------------------------
  // AES control properties
  //----------------------------------------------------------------

  // INIT and NEXT are W1P commands and must be one-cycle pulses.
  property AES_INIT_pulse;
    @(posedge hclk_tb)
    disable iff (!hreset_tb)
    dut.regbank_s[AES_CTRL_address][CTRL_OFFSET_INIT]
      |=> !dut.regbank_s[AES_CTRL_address][CTRL_OFFSET_INIT];
  endproperty

  assert property (AES_INIT_pulse) else
    $error("AES_INIT_pulse: INIT must last exactly one cycle");

  // The NEXT W1P command stays high for at most one sampled clock cycle.
  property AES_NEXT_pulse;
    @(posedge hclk_tb)
    disable iff (!hreset_tb)
    dut.regbank_s[AES_CTRL_address][CTRL_OFFSET_NEXT]
      |=> !dut.regbank_s[AES_CTRL_address][CTRL_OFFSET_NEXT];
  endproperty

  assert property (AES_NEXT_pulse) else
    $error("AES_NEXT_pulse: NEXT must last exactly one cycle");

  // A computation may only start after key scheduling completed.
  // This is a *command legality* rule, not a proof of key correctness.
  // The sampled STATUS.READY must already be high at the NEXT pulse.
  property AES_NEXT_requires_ready;
    @(posedge hclk_tb)
    disable iff (!hreset_tb)
    dut.regbank_s[AES_CTRL_address][CTRL_OFFSET_NEXT]
      |-> dut.regbank_s[AES_STATUS_address][STATUS_OFFSET_READY];
  endproperty

  assert property (AES_NEXT_requires_ready) else
    $error("AES_NEXT_requires_ready: NEXT issued while AES not ready");

  // The documentation states that both READY and RESULT_VALID
  // are asserted at the end of an encryption/decryption operation.
  property AES_RESULTVALID_implies_ready;
    @(posedge hclk_tb)
    disable iff (!hreset_tb)
    dut.regbank_s[AES_STATUS_address][STATUS_OFFSET_RESULTVALID]
      |-> dut.regbank_s[AES_STATUS_address][STATUS_OFFSET_READY];
  endproperty

  assert property (AES_RESULTVALID_implies_ready) else
    $error("AES_RESULTVALID_implies_ready: result valid while not ready");

  //----------------------------------------------------------------
  // HRESP observation
  //----------------------------------------------------------------
  property HRESP_known_when_ready;
    @(posedge hclk_tb)
    disable iff (!hreset_tb)
    hreadyout_tb |-> !$isunknown(hresp_tb);
  endproperty

  assert property (HRESP_known_when_ready) else
    $error("HRESP_known_when_ready: HRESP is X or Z on a ready cycle");

endmodule
