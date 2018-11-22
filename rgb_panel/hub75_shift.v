/*
 * hub75_shift.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut <tnt@246tNt.com>
 *
 * vim: ts=4 sw=4
 */

// FIXME: - Support non-pow2 N_COLS

`default_nettype none

module hub75_shift #(
	parameter integer N_BANKS  = 2,
	parameter integer N_COLS   = 64,
	parameter integer N_CHANS  = 3,
	parameter integer N_PLANES = 8,

	// Auto-set
	parameter integer LOG_N_COLS  = $clog2(N_COLS)
)(
	// Hub75 interface
	output wire [(N_BANKS*N_CHANS)-1:0] hub75_data,
	output wire hub75_clk,

	// RAM interface
	input  wire [(N_BANKS*N_CHANS*N_PLANES)-1:0] ram_data,
	output wire [LOG_N_COLS-1:0] ram_col_addr,
	output wire ram_rden,

	// Control
	input  wire [N_PLANES-1:0] ctrl_plane,
	input  wire ctrl_go,
	output wire ctrl_rdy,

	// Clock / Reset
	input  wire clk,
	input  wire rst
);

	genvar i;

	// Signals
	// -------

	reg active_0;
	reg active_1;
	reg active_2;
	reg active_3;
	reg [LOG_N_COLS:0] cnt_0;

	wire [(N_BANKS*N_CHANS)-1:0] ram_data_bit;
	reg  [(N_BANKS*N_CHANS)-1:0] data_2;


	// Control logic
	// -------------

	// Active / Valid flag
	always @(posedge clk or posedge rst)
		if (rst) begin
			active_0 <= 1'b0;
			active_1 <= 1'b0;
			active_2 <= 1'b0;
			active_3 <= 1'b0;
		end else begin
			active_0 <= (active_0 & ~cnt_0[LOG_N_COLS]) | ctrl_go;
			active_1 <= active_0 & ~cnt_0[LOG_N_COLS];	// Post-Fix overflow
			active_2 <= active_1;
			active_3 <= active_2;
		end

	// Counter
	always @(posedge clk)
		if (ctrl_go)
			cnt_0 <= 0;
		else if (active_0)
			cnt_0 <= cnt_0 + 1;

	// Ready ?
	assign ctrl_rdy = ~active_0;


	// Data path
	// ---------

	// RAM access
	assign ram_rden = active_0;
	assign ram_col_addr = cnt_0[LOG_N_COLS-1:0];

	// Data plane mux
	generate
		for (i=0; i<(N_BANKS*N_CHANS); i=i+1)
			assign ram_data_bit[i] = |(ram_data[((i+1)*N_PLANES)-1:i*N_PLANES] & ctrl_plane);
	endgenerate

	// Mux register
	always @(posedge clk)
		data_2 <= ram_data_bit;


	// IOBs
	// ----

	// Data lines
	generate
		for (i=0; i<(N_BANKS*N_CHANS); i=i+1)
			SB_IO #(
				.PIN_TYPE(6'b010100),
				.PULLUP(1'b0),
				.NEG_TRIGGER(1'b0),
				.IO_STANDARD("SB_LVCMOS")
			) iob_data_I (
				.PACKAGE_PIN(hub75_data[i]),
				.CLOCK_ENABLE(1'b1),
				.OUTPUT_CLK(clk),
				.D_OUT_0(data_2[i])
			);
	endgenerate

	// Clock DDR register
    SB_IO #(
        .PIN_TYPE(6'b010000),
        .PULLUP(1'b0),
        .NEG_TRIGGER(1'b0),
        .IO_STANDARD("SB_LVCMOS")
    ) iob_clk_I (
        .PACKAGE_PIN(hub75_clk),
        .CLOCK_ENABLE(1'b1),
        .OUTPUT_CLK(clk),
        .D_OUT_0(1'b0),
        .D_OUT_1(active_3)	// Falling edge, so need one more delay so it's not too early !
    );

endmodule // hub75_shift
