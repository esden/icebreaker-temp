/*
 * spi_fast_core_tb.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module spi_fast_core_tb;

	// Signals
	reg rst = 1'b1;
	reg clk = 1'b0;

	wire spi_mosi;
	wire spi_miso;
	wire spi_cs_n;
	wire spi_clk;

	wire [7:0] user_out;
	wire user_out_stb;

	wire [7:0] user_in;
	wire user_in_ack;

	wire csn_state;
	wire csn_rise;
	wire csn_fall;

	// Setup recording
	initial begin
		$dumpfile("spi_fast_core_tb.vcd");
		$dumpvars(0,spi_fast_core_tb);
	end

	// Reset pulse
	initial begin
		# 200 rst = 0;
		# 1000000 $finish;
	end

	// Clocks
	always #10 clk = !clk;

	// DUT
	spi_fast_core spi_I (
		.spi_mosi(spi_mosi),
		.spi_miso(spi_miso),
		.spi_cs_n(spi_cs_n),
		.spi_clk(spi_clk),
		.user_out(user_out),
		.user_out_stb(user_out_stb),
		.user_in(user_in),
		.user_in_ack(user_in_ack),
		.csn_state(csn_state),
		.csn_rise(csn_rise),
		.csn_fall(csn_fall),
		.clk(clk),
		.rst(rst)
	);

	// Dummy TX
	assign user_in = 8'hBA;

	// SPI data generation
	reg [71:0] spi_csn_data = 72'b11110000000000000000000000000000000000000000000000000001111;
	reg [71:0] spi_clk_data = 72'b00000010101010101010101010101010101010101010101010101000000;
	reg [71:0] spi_dat_data = 72'b00000110011000011001111110000000000111111000000001100000000;

	reg [4:0] div;

	always @(posedge clk)
		if (rst)
			div <= 0;
		else
			div <= div + 1;

	always @(posedge clk)
		if (1 || div == 4'hf) begin
			spi_csn_data <= { spi_csn_data[70:0], spi_csn_data[71] };
			spi_clk_data <= { spi_clk_data[70:0], spi_clk_data[71] };
			spi_dat_data <= { spi_dat_data[70:0], spi_dat_data[71] };
		end

	assign spi_mosi = spi_dat_data[70];
	assign spi_cs_n = spi_csn_data[70];
	assign spi_clk  = spi_clk_data[70];

endmodule // spi_fast_core_tb
