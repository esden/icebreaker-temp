/*
 * spi_flash_reader_tb.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut
 *
 * vim: ts=4 sw=4
 */

`timescale 1ns / 1ps
`default_nettype none

module spi_flash_reader_tb;

	// Signals
	reg rst = 1'b1;
	reg clk = 1'b0;

	wire spi_mosi;
	wire spi_miso;
	wire spi_cs_n;
	wire spi_clk;

	wire [23:0] addr;
	wire [15:0] len;
	wire go;
	wire rdy;

	wire [7:0] data;
	wire valid;

	reg flip;
	reg [23:0] cnt;

	// Setup recording
	initial begin
		$dumpfile("spi_flash_reader_tb.vcd");
		$dumpvars(0,spi_flash_reader_tb);
	end

	// Reset pulse
	initial begin
		# 200 rst = 0;
		# 1000000 $finish;
	end

	// Clocks
	always #33 clk = !clk;	// ~ 30 MHz

	// DUT
	spi_flash_reader dut_I (
		.spi_mosi(spi_mosi),
		.spi_miso(spi_miso),
		.spi_cs_n(spi_cs_n),
		.spi_clk(spi_clk),
		.addr(addr),
		.len(len),
		.go(go),
		.rdy(rdy),
		.data(data),
		.valid(valid),
		.clk(clk),
		.rst(rst)
	);

	// No real RAM
	assign spi_miso = spi_cs_n ? 1'bz : flip;

	always @(posedge rst, negedge spi_clk)
		if (rst)
			flip <= 1'b0;
		else
			flip <= ~flip;

	// Read commands
	assign addr = cnt;
	assign len = 16'h0000;
	assign go = rdy & ~rst & ~valid;

	always @(posedge clk)
		if (rst)
			cnt <= 24'h00BABE;
		else if (valid)
			cnt <= cnt + 1;

endmodule // spi_flash_reader_tb
