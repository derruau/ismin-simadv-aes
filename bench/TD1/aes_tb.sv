`timescale 1ns/1ps

module aes_tb #(
  parameter string INPUT_FILENAME   = "./data/pt_ct_pairs.csv",   // Path to the file containing the plaintexts and ciphertexts pairs
  parameter string OUTPUT_FILENAME  = "./data/TD1_data_out.txt",  // Path to the output file to write the encrypted values to
  parameter int CLK_FREQ_MHZ        = 50                          // Clock frequency in MHz
) ();

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

  // Introspection signals
  logic [31:0] w0_r, w1_r, w2_r, w3_r;
  logic [1:0]  sword_ctr_r;
  logic [3:0]  round_ctr_r;

  // FIPS-197 test vector key. AES-128 uses the 128 MSB.
  logic [255 : 0] nist_aes128_key1 = 256'h2b7e1516_28aed2a6_abf71588_09cf4f3c_00000000_00000000_00000000_00000000;

  // Statistics
  int round;
  int successful_encryption_counter;

  //----------------------------------------------------------------
  // Introspection signals assignation
  //----------------------------------------------------------------

  assign w0_r = dut.enc_block.block_w0_reg;
  assign w1_r = dut.enc_block.block_w1_reg;
  assign w2_r = dut.enc_block.block_w2_reg;
  assign w3_r = dut.enc_block.block_w3_reg;

  assign sword_ctr_r = dut.enc_block.sword_ctr_reg;
  assign round_ctr_r = dut.enc_block.round_ctr_reg;

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
    int fd_i, fd_o;
    logic [127:0] pt_data;
    logic [127:0] ct_data;

    // Throwaway variable
    string _;

    // Opening files
    fd_i    = $fopen(INPUT_FILENAME, "r");
    fd_o    = $fopen(OUTPUT_FILENAME, "w");
   
    // Verifiation
    if (!fd_i)    $fatal(1, "Could not open the input file to read values from!\n",
                          "Try launching `python scripts/gen_aes_test_vectors.py`");
    if (!fd_o)    $fatal(1, "Could not open the output file!");

    // Initialization: reading/writing CSV column definition
    void'($fgets(_, fd_i));
    $fwrite(fd_o, "sv_plaintext, sv_ciphertext\n");

    round = 0;
    successful_encryption_counter = 0;

    while ($fscanf(fd_i, "%h, %h", pt_data, ct_data) == 2) begin

        encrypt(pt_data, nist_aes128_key1);

        // Writing the result in the output file.
        $fwrite(fd_o, "%h, %h\n", pt_data, tb_result);

        // Comparing testbench results to the python script's result
        check_result(tb_result, ct_data);
    end

    // Closing files
    $fclose(fd_i);
    $fclose(fd_o);

    // Last metric
    $display(
      "%0d/%0d encryptions successful!", 
      successful_encryption_counter, 
      round
    );

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
  // Comparing the testbench result with the awaited result
  //----------------------------------------------------------------
  task check_result(
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
      $display("    DUT : 0x%032h", expected);
      $display("    REF : 0x%032h", actual);
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
