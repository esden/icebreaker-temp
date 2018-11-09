/*
 * hub75_blanking.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut <tnt@246tNt.com>
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module hub75_blanking #(
	parameter integer N_PLANES = 8
)(
	// Hub75 interface
	output wire hub75_blank,

	// Control
	input  wire [N_PLANES-1:0] ctrl_plane,
	input  wire ctrl_go,
	output wire ctrl_rdy,

	// Config
	input  wire [7:0] cfg_bcm_bit_len,

	// Clock / Reset
	input  wire clk,
	input  wire rst
);

	// Signals
	// -------

	wire active;
	wire plane_cnt_ce;
	reg [N_PLANES:0] plane_cnt;
	reg [7:0] bit_cnt;
	wire bit_cnt_trig;


	// Control
	// -------

	// Active
	assign active = plane_cnt[N_PLANES];

	// Plane length counter
	always @(posedge clk)
		if (rst)
			plane_cnt <= 0;
		else if (plane_cnt_ce)
			plane_cnt <= (ctrl_go ? { 1'b1, ctrl_plane } : plane_cnt) - 1;

	assign plane_cnt_ce = (bit_cnt_trig & active) | ctrl_go;

	// Base len bit counter
	always @(posedge clk)
		if (~active | bit_cnt_trig)
			bit_cnt <= cfg_bcm_bit_len;
		else
			bit_cnt <= bit_cnt - 1;

	assign bit_cnt_trig = bit_cnt[7];

	// Ready
	assign ctrl_rdy = ~active;


	// IOBs
	// ----

	// Blanking
	SB_IO #(
		.PIN_TYPE(6'b010100),
		.PULLUP(1'b0),
		.NEG_TRIGGER(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) iob_blank_I (
		.PACKAGE_PIN(hub75_blank),
		.CLOCK_ENABLE(1'b1),
		.OUTPUT_CLK(clk),
		.D_OUT_0(active)
	);

endmodule // hub75_blanking
