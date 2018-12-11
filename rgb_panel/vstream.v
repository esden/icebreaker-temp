/*
 * vstream.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module vstream #(
	parameter integer N_ROWS   = 64,	// # of rows (must be power of 2!!!)
	parameter integer N_COLS   = 64,	// # of columns
	parameter integer BITDEPTH = 24,

	// Auto-set
	parameter integer LOG_N_ROWS  = $clog2(N_ROWS),
	parameter integer LOG_N_COLS  = $clog2(N_COLS)
)(
	// SPI to the host
	input  wire spi_mosi,
	output wire spi_miso,
	input  wire spi_cs_n,
	input  wire spi_clk,

	// Frame Buffer write interface
	output wire [LOG_N_ROWS-1:0] fbw_row_addr,
	output wire fbw_row_store,
	input  wire fbw_row_rdy,
	output wire fbw_row_swap,

	output wire [23:0] fbw_data,
	output wire [LOG_N_COLS-1:0] fbw_col_addr,
	output wire fbw_wren,

	output wire frame_swap,
	input  wire frame_rdy,

	// Clock / Reset
	input  wire clk,
	input  wire rst
);

	localparam integer TW = BITDEPTH / 8;

	// Signals
	// -------

	// SPI bus
	wire [7:0] sb_addr;
	wire [7:0] sb_data;
	wire sb_first;
	wire sb_last;
	wire sb_stb;
	wire [7:0] sb_out;
	
	// Front Buffer write
	reg [TW-1:0] trig;
	reg [LOG_N_COLS-1:0] cnt_col;
	reg [7:0] sb_data_r[0:1];


	// SPI interface
	// -------------

`ifdef SPI_FAST
	spi_fast spi_I (
`else
	spi_simple spi_I (
`endif
		.spi_mosi(spi_mosi),
		.spi_miso(spi_miso),
		.spi_cs_n(spi_cs_n),
		.spi_clk(spi_clk),
		.addr(sb_addr),
		.data(sb_data),
		.first(sb_first),
		.last(sb_last),
		.strobe(sb_stb),
		.out(sb_out),
		.clk(clk),
		.rst(rst)
	);

	assign sb_out = { 6'd0, frame_rdy, fbw_row_rdy };


	// Front-Buffer write
	// ------------------

	// "Trigger"
	always @(posedge clk or posedge rst)
		if (TW > 1) begin
			if (rst)
				trig <= { 1'b1, {(TW-1){1'b0}} };
			else if (sb_stb)
				trig <= sb_last ? { 1'b1, {(TW-1){1'b0}} } : { trig[0], trig[TW-1:1] };
		end else
			trig <= 1'b1;

	// Column counter
	always @(posedge clk or posedge rst)
		if (rst)
			cnt_col <= 0;
		else if (sb_stb)
			cnt_col <= sb_last ? 0 : (cnt_col + trig[0]);

	// Register data for wide writes
	always @(posedge clk)
		if (sb_stb) begin
			sb_data_r[0] <= sb_data;
			sb_data_r[1] <= sb_data_r[0];
		end

	// Write commands
	assign fbw_wren = sb_stb & sb_addr[7] & trig[0];
	assign fbw_col_addr = cnt_col;

	// Map to color
	generate
		if (BITDEPTH == 8)
			assign fbw_data = sb_data;
		else if (BITDEPTH == 16)
			assign fbw_data = { sb_data, sb_data_r[0] };
		else if (BITDEPTH == 24)
			assign fbw_data = { sb_data, sb_data_r[0], sb_data_r[1] };
	endgenerate


	// Back-Buffer store
	// -----------------

	assign fbw_row_addr  = sb_data[LOG_N_ROWS-1:0];
	assign fbw_row_store = sb_stb & ~sb_addr[7] & sb_addr[0];
	assign fbw_row_swap  = sb_stb & ~sb_addr[7] & sb_addr[1];


	// Next frame
	// ----------

	assign frame_swap = sb_stb & ~sb_addr[7] & sb_addr[2];

endmodule // vstream
