`timescale 1ns/1ps

import "DPI-C" function void python_initialize_c();
import "DPI-C" function void python_finalize_c();
import "DPI-C" function string aes_c(input string dataIn, input string keyIn, input int encdec);

// Used to generate random inputs
class Inputs; 
  rand logic[127:0] cleartext;
  rand logic[255:0] key;
endclass: Inputs

module aes_tb #(
  parameter string OUTPUT_FILENAME    = "./data/TD2_data_out.csv",  // Path to the output file to write the encrypted values to
  parameter int CLK_FREQ_MHZ          = 50,                         // Clock frequency in MHz
  parameter int DEFAULT_NB_ITERATION  = 100                         // Default number of times a random test is generated
)();
  //----------------------------------------------------------------
  // Type definitions
  //----------------------------------------------------------------

  localparam realtime CLK_PERIOD_NS       = 1000ns / CLK_FREQ_MHZ;
  localparam realtime CLK_HALF_PERIOD_NS  = CLK_PERIOD_NS/ 2;

  typedef enum logic { 
    AES_128_BIT_KEY = '0, 
    AES_256_BIT_KEY = '1 
  } aes_keylength_t;

  typedef enum logic { 
    AES_DECIPHER = '0,
    AES_ENCIPHER = '1
  } aes_operation_t;

  //----------------------------------------------------------------
  // Variables
  //----------------------------------------------------------------

  // DUT variables
  logic            tb_clk;
  logic            tb_reset_n;
  aes_operation_t  tb_encdec;
  logic            tb_init;
  logic            tb_next;
  logic            tb_ready;
  logic [255 : 0]  tb_key;
  aes_keylength_t  tb_keylen;
  logic [127 : 0]  tb_block;
  logic [127 : 0]  tb_result;
  logic            tb_result_valid;

  // Statistics
  int round;
  int successful_encryption_counter;

  //----------------------------------------------------------------
  // DUT.
  //----------------------------------------------------------------
  aes_core dut(
               .clk          (tb_clk),
               .reset_n      (tb_reset_n),

               .encdec       (tb_encdec),
               .init         (tb_init),
               .next         (tb_next),
               .ready        (tb_ready),

               .key          (tb_key),
               .keylen       (tb_keylen),

               .block        (tb_block),
               .result       (tb_result),
               .result_valid (tb_result_valid)
              );

  //----------------------------------------------------------------
  // Clock generation.
  //----------------------------------------------------------------
  initial begin : clk_gen
    tb_clk = 1'b0;
    forever #CLK_HALF_PERIOD_NS tb_clk = ~tb_clk;
  end

  //----------------------------------------------------------------
  // Test
  //----------------------------------------------------------------
  initial begin
    // File descriptors
    int fd_o;

    // Internal variables (int suffix for internal variables)
    int status_int;
    int iteration_nb_int;

    // Randomly generated inputs
    Inputs ival;

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
    $fwrite(fd_o, "testbench_result, parsed_result_py\n");

    // Python initialization
    python_initialize_c();

    round = 0;
    successful_encryption_counter = 0;

    while (round < iteration_nb_int) begin
      
      if (!ival.randomize()) begin
        $fatal("ERROR: Could not randomize input!");
      end

      encrypt(ival.cleartext, ival.key);
      encrypt_python(ival.cleartext, ival.key, parsed_result_py);

      // Write results to CSV
      $fwrite(fd_o, "%032h, %032h\n", tb_result, parsed_result_py);

      // Comparing testbench results to the python script's result
      check_result(ival, tb_result, parsed_result_py);
    end

    // Closing files
    $fclose(fd_o);

    // Closing python
    python_finalize_c();

    $display("%0d / %0d encryptions sucessful!", successful_encryption_counter, round);

    // Leave one clock cycle visible after the result before stopping.
    @(posedge tb_clk);
    $finish;
  end

  //----------------------------------------------------------------
  // Testbench initialisation and DUT reset
  //----------------------------------------------------------------
  task init_sim;
  begin
    tb_reset_n = 1'b1;
    tb_encdec  = AES_ENCIPHER;
    tb_init    = 1'b0;
    tb_next    = 1'b0;
    tb_key     = 256'b0;
    tb_keylen  = AES_128_BIT_KEY;
    tb_block   = 128'b0;

    reset_dut();
  end
  endtask

  //----------------------------------------------------------------
  // Selects the operation and the key length
  //----------------------------------------------------------------
  task setup_operation(input aes_operation_t op, input aes_keylength_t keylen);
  begin
    tb_encdec = op;
    tb_keylen = keylen;
  end
  endtask

  //----------------------------------------------------------------
  // Sets the key and the data to encipher/decipher
  //----------------------------------------------------------------
  task send_data(input logic [127:0] data_in, input logic [255:0] key_in);
  begin
    tb_block = data_in;
    tb_key   = key_in;
  end
  endtask


  //----------------------------------------------------------------
  // Proceeds to the whole encryption operation
  //----------------------------------------------------------------
  task encrypt(input logic [127:0] data_in, input logic [255:0] key_in);
    begin
      init_sim();

      // Operations to do + sending the data and key
      setup_operation(AES_ENCIPHER, AES_128_BIT_KEY);
      send_data(data_in, key_in);

      // Cipher computing initialization
      @(negedge tb_clk);
      tb_init = 1'b1;
      @(negedge tb_clk);
      tb_init = 1'b0;

      // Waiting until the keys are ready
      wait (tb_ready === 1'b1);

      // Starting data bloc encryption
      @(negedge tb_clk);
      tb_next = 1'b1;
      @(negedge tb_clk);
      tb_next = 1'b0;

      // Waiting until the operation is done.
      wait (tb_result_valid === 1'b1);
    end
  endtask

  //----------------------------------------------------------------
  // Python AES encryption
  //----------------------------------------------------------------
  task encrypt_python(
      input  logic [127:0] data_in,
      input  logic [255:0] key_in,
      output logic [127:0] result_out
  );
      string data_in_py, key_in_py, result_py;
      int status_int;

      // Convert inputs to hexadecimal strings
      data_in_py = $sformatf("%032h", data_in);
      key_in_py  = $sformatf("%032h", key_in[255:128]);

      // Call Python AES implementation
      result_py = aes_c(data_in_py, key_in_py, AES_ENCIPHER);

      // Convert Python result to logic [127:0]
      status_int = $sscanf(result_py, "%h", result_out);

      if (status_int != 1)
          $fatal(1, "Could not parse Python result: %s", result_py);
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
      $display("  Key:       0x%032h", ival.key);
      $display("  RTL:       0x%032h", actual);
      $display("  Python:    0x%032h", expected);
    end
    round++;
  end
  endtask

  //----------------------------------------------------------------
  // AES Reset
  //----------------------------------------------------------------
  task reset_dut;
  begin
    tb_reset_n = 1'b0;
    repeat (2) @(posedge tb_clk);

    @(negedge tb_clk);
    tb_reset_n = 1'b1;

    @(posedge tb_clk);
  end
  endtask

endmodule
