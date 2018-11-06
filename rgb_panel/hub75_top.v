/*
 * hub75_top.v
 *
 * Copyright (C) 2018  Sylvain Munaut <tnt@246tNt.com>
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module hub75_top #(
	parameter integer N_BANKS  = 2,		// # of parallel readout rows
	parameter integer N_ROWS   = 32,	// # of rows (must be power of 2!!!)
	parameter integer N_COLS   = 64,	// # of columns
	parameter integer N_CHANS  = 3,		// # of data channel
	parameter integer N_PLANES = 8,		// # bitplanes

	// Auto-set
	parameter integer LOG_N_BANKS = $clog2(N_BANKS),
	parameter integer LOG_N_ROWS  = $clog2(N_ROWS),
	parameter integer LOG_N_COLS  = $clog2(N_COLS)
)(
	// Hub75 interface
	output wire [LOG_N_ROWS-1:0] hub75_addr,
	output wire [(N_BANKS*N_CHANS)-1:0] hub75_data,
	output wire hub75_clk,
	output wire hub75_le,
	output wire hub75_blank,

	// Frame Buffer write interface

	// Config
	input  wire [7:0] cfg_pre_latch_len,
	input  wire [7:0] cfg_latch_len,
	input  wire [7:0] cfg_post_latch_len,
	input  wire [7:0] cfg_bcm_bit_len,

	// Clock / Reset
	input  wire clk,
	input  wire rst
);

	// Signals
	// -------

	// Frame Buffer access
		// Read - Back Buffer loading
	wire [LOG_N_ROWS-1:0] fbr_row_addr;
	wire fbr_row_load;
	wire fbr_row_rdy;
	wire fbr_row_swap;

		// Read - Front Buffer access
	wire [(N_BANKS*N_CHANS*N_PLANES)-1:0] fbr_data;
	wire [LOG_N_COLS-1:0] fbr_col_addr;
	wire fbr_rden;

	// Scanning
	wire scan_go;
	wire scan_rdy;

	// Binary Code Modulator
	wire [LOG_N_ROWS-1:0] bcm_row;
	wire bcm_go;
	wire bcm_rdy;

	// Shifter
	wire [N_PLANES-1:0] shift_plane;
	wire shift_go;
	wire shift_rdy;

	// Blanking control
	wire [N_PLANES-1:0] blank_plane;
	wire blank_go;
	wire blank_rdy;


	// Debug temp
	// ----------

	// Go if we're ready
	assign scan_go = scan_rdy;

	// Latch ROW
	reg [LOG_N_ROWS-1:0] dbg_row_back;
	reg [LOG_N_ROWS-1:0] dbg_row_front;
	reg dbg_row_rdy;

	always @(posedge clk)
	begin
		if (rst) begin
			dbg_row_back  <= 0;
			dbg_row_front <= 0;
			dbg_row_rdy   <= 1'b0;
		end else begin
			if (fbr_row_load)
				dbg_row_back <= fbr_row_addr;

			if (fbr_row_swap)
				dbg_row_front <= dbg_row_back;

			dbg_row_rdy <= (dbg_row_rdy & ~fbr_row_swap) | fbr_row_load;
		end
	end

	assign fbr_row_rdy = dbg_row_rdy;

	// Pattern generation
	wire [5:0] dbg_pg_col  = fbr_col_addr;
	wire [5:0] dbg_pg_row0 = {1'b0, dbg_row_front};
	wire [5:0] dbg_pg_row1 = {1'b1, dbg_row_front};

	reg [7:0] dbg_pg_r0;
	reg [7:0] dbg_pg_g0;
	reg [7:0] dbg_pg_b0;
	reg [7:0] dbg_pg_r1;
	reg [7:0] dbg_pg_g1;
	reg [7:0] dbg_pg_b1;

	always @(posedge clk)
	begin
		if (fbr_rden)
		begin
			dbg_pg_r0 <= { dbg_pg_col[5:0],  dbg_pg_col[5:4]  };
			dbg_pg_g0 <= (dbg_pg_col[2:0] == 3'b000) ? 8'hff : 8'h00;
			dbg_pg_b0 <= { dbg_pg_row0[5:0], dbg_pg_row0[5:4] };
			dbg_pg_r1 <= { dbg_pg_col[5:0],  dbg_pg_col[5:4]  };
			dbg_pg_g1 <= (dbg_pg_row1[2:0] == 3'b000) ? 8'hff : 8'h00;
			dbg_pg_b1 <= { dbg_pg_row1[5:0], dbg_pg_row1[5:4] };
		end
	end

	assign fbr_data = { dbg_pg_b1, dbg_pg_g1, dbg_pg_r1, dbg_pg_b0, dbg_pg_g0, dbg_pg_r0 };


	//
	// -----


	// Frame Buffer



	// Scan
	hub75_scan #(
		.N_ROWS(N_ROWS)
	) scan_I (
		.bcm_row(bcm_row),
		.bcm_go(bcm_go),
		.bcm_rdy(bcm_rdy),
		.fb_row_addr(fbr_row_addr),
		.fb_row_load(fbr_row_load),
		.fb_row_rdy(fbr_row_rdy),
		.fb_row_swap(fbr_row_swap),
		.ctrl_go(scan_go),
		.ctrl_rdy(scan_rdy),
		.clk(clk),
		.rst(rst)
	);

	// Binary Code Modulator control
	hub75_bcm #(
		.N_PLANES(N_PLANES)
	) bcm_I (
		.hub75_addr(hub75_addr),
		.hub75_le(hub75_le),
		.shift_plane(shift_plane),
		.shift_go(shift_go),
		.shift_rdy(shift_rdy),
		.blank_plane(blank_plane),
		.blank_go(blank_go),
		.blank_rdy(blank_rdy),
		.ctrl_row(bcm_row),
		.ctrl_go(bcm_go),
		.ctrl_rdy(bcm_rdy),
		.cfg_pre_latch_len(cfg_pre_latch_len),
		.cfg_latch_len(cfg_latch_len),
		.cfg_post_latch_len(cfg_post_latch_len),
		.clk(clk),
		.rst(rst)
	);

	// Shifter
	hub75_shift #(
		.N_BANKS(N_BANKS),
		.N_COLS(N_COLS),
		.N_CHANS(N_CHANS),
		.N_PLANES(N_PLANES)
	) shift_I (
		.hub75_data(hub75_data),
		.hub75_clk(hub75_clk),
		.ram_data(fbr_data),
		.ram_col_addr(fbr_col_addr),
		.ram_rden(fbr_rden),
		.ctrl_plane(shift_plane),
		.ctrl_go(shift_go),
		.ctrl_rdy(shift_rdy),
		.clk(clk),
		.rst(rst)
	);

	// Blanking control
	hub75_blanking #(
		.N_PLANES(N_PLANES)
	) blank_I (
		.hub75_blank(hub75_blank),
		.ctrl_plane(blank_plane),
		.ctrl_go(blank_go),
		.ctrl_rdy(blank_rdy),
		.cfg_bcm_bit_len(cfg_bcm_bit_len),
		.clk(clk),
		.rst(rst)
	);

endmodule // hub75_top
