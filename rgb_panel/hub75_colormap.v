/*
 * hub75_colormap.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut <tnt@246tNt.com>
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module hub75_colormap #(
	parameter integer N_CHANS  = 3,
	parameter integer N_PLANES = 8,
	parameter integer BITDEPTH = 24,
	parameter integer USER_WIDTH = 1
)(
	// Input pixel
	input  wire [BITDEPTH-1:0] in_data,
	input  wire [USER_WIDTH-1:0] in_user,
	input  wire in_valid,
	output wire in_ready,

	// Output pixel
	output wire [(N_CHANS*N_PLANES)-1:0] out_data,
	output wire [USER_WIDTH-1:0] out_user,
	output wire out_valid,

	// Clock / Reset
	input  wire clk,
	input  wire rst
);

	// Trivial mapping ATM
	assign out_valid = in_valid;
	assign out_data  = in_data;
	assign out_user  = in_user;

	assign in_ready  = 1'b1;

endmodule // hub75_colormap
