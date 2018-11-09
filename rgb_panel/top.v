/*
 * top.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module top (
	// RGB panel PMOD
	output wire [4:0] hub75_addr,
	output wire [5:0] hub75_data,
	output wire hub75_clk,
	output wire hub75_le,
	output wire hub75_blank,

	// Clock
	input  wire clk_12m
);

	// Params
	localparam integer N_BANKS  = 2;
	localparam integer N_ROWS   = 32;
	localparam integer N_COLS   = 64;
	localparam integer N_CHANS  = 3;
	localparam integer N_PLANES = 8;

	localparam integer LOG_N_BANKS = $clog2(N_BANKS);
	localparam integer LOG_N_ROWS  = $clog2(N_ROWS);
	localparam integer LOG_N_COLS  = $clog2(N_COLS);


	// Signals
	// -------

	// Clock / Reset logic
`ifdef NO_PLL
	reg [7:0] rst_cnt = 8'h00;
	wire rst_i;
`endif

	wire clk;
	wire rst;

	// Frame buffer write port
	wire [LOG_N_BANKS-1:0] fbw_bank_addr;
	wire [LOG_N_ROWS-1:0]  fbw_row_addr;
	wire fbw_row_store;
	wire fbw_row_rdy;
	wire fbw_row_swap;

	wire [(N_CHANS * N_PLANES)-1:0] fbw_data;
	wire [LOG_N_COLS-1:0] fbw_col_addr;
	wire fbw_wren;

	wire frame_swap;
	wire frame_rdy;


	// Hub75
	// -----

	hub75_top #(
		.N_BANKS(N_BANKS),
		.N_ROWS(N_ROWS),
		.N_COLS(N_COLS),
		.N_CHANS(N_CHANS),
		.N_PLANES(N_PLANES)
	) hub75_I (
		.hub75_addr(hub75_addr),
		.hub75_data(hub75_data),
		.hub75_clk(hub75_clk),
		.hub75_le(hub75_le),
		.hub75_blank(hub75_blank),
		.fbw_bank_addr(fbw_bank_addr),
		.fbw_row_addr(fbw_row_addr),
		.fbw_row_store(fbw_row_store),
		.fbw_row_rdy(fbw_row_rdy),
		.fbw_row_swap(fbw_row_swap),
		.fbw_data(fbw_data),
		.fbw_col_addr(fbw_col_addr),
		.fbw_wren(fbw_wren),
		.frame_swap(frame_swap),
		.frame_rdy(frame_rdy),
		.cfg_pre_latch_len(8'h80),
		.cfg_latch_len(8'h80),
		.cfg_post_latch_len(8'h80),
		.cfg_bcm_bit_len(8'h06),
		.clk(clk),
		.rst(rst)
	);

	pgen pgen_I (
		.fbw_row_addr({fbw_bank_addr, fbw_row_addr}),
		.fbw_row_store(fbw_row_store),
		.fbw_row_rdy(fbw_row_rdy),
		.fbw_row_swap(fbw_row_swap),
		.fbw_data(fbw_data),
		.fbw_col_addr(fbw_col_addr),
		.fbw_wren(fbw_wren),
		.frame_swap(frame_swap),
		.frame_rdy(frame_rdy),
		.clk(clk),
		.rst(rst)
	);


	// Clock / Reset
	// -------------

`ifdef NO_PLL
	always @(posedge clk)
		if (~rst_cnt[7])
			rst_cnt <= rst_cnt + 1;

	wire rst_i = ~rst_cnt[7];

	SB_GB clk_gbuf_I (
		.USER_SIGNAL_TO_GLOBAL_BUFFER(clk_12m),
		.GLOBAL_BUFFER_OUTPUT(clk)
	);

	SB_GB rst_gbuf_I (
		.USER_SIGNAL_TO_GLOBAL_BUFFER(rst_i),
		.GLOBAL_BUFFER_OUTPUT(rst)
	);
`else
	sysmgr sys_mgr_I (
		.clk_in(clk_12m),
		.rst_in(1'b0),
		.clk_out(clk),
		.rst_out(rst)
	);
`endif

endmodule // top

