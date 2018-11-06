/*
 * hub75_top_tb.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut
 *
 * vim: ts=4 sw=4
 */

`timescale 1ns / 1ps
`default_nettype none

module hub75_top_tb;

	// Params
	parameter integer N_BANKS  = 2;
	parameter integer N_ROWS   = 32;
	parameter integer N_COLS   = 64;
	parameter integer N_CHANS  = 3;
	parameter integer N_PLANES = 8;

	// Signals
	reg rst = 1'b1;
	reg clk = 1'b0;

	wire [$clog2(N_ROWS)-1:0] hub75_addr;
	wire [(N_BANKS*N_CHANS)-1:0] hub75_data;
	wire hub75_clk;
	wire hub75_le;
	wire hub75_blank;

	// Setup recording
	initial begin
		$dumpfile("hub75_top_tb.vcd");
		$dumpvars(0,hub75_top_tb);
	end

	// Reset pulse
	initial begin
		# 200 rst = 0;
		# 1000000 $finish;
	end

	// Clocks
	always #33 clk = !clk;	// ~ 30 MHz

	// DUT
	hub75_top #(
		.N_BANKS(N_BANKS),
		.N_ROWS(N_ROWS),
		.N_COLS(N_COLS),
		.N_CHANS(N_CHANS),
		.N_PLANES(N_PLANES)
	) dut_I (
		.hub75_addr(hub75_addr),
		.hub75_data(hub75_data),
		.hub75_clk(hub75_clk),
		.hub75_le(hub75_le),
		.hub75_blank(hub75_blank),
		.cfg_pre_latch_len(8'h00),
		.cfg_latch_len(8'h00),
		.cfg_post_latch_len(8'h00),
		.cfg_bcm_bit_len(8'h06),
		.clk(clk),
		.rst(rst)
	);

endmodule // hub75_top_tb
