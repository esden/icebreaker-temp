/*
 * hub75_fb_readout.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut <tnt@246tNt.com>
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module hub75_fb_readout #(
	parameter integer N_BANKS  = 2,
	parameter integer N_ROWS   = 32,
	parameter integer N_COLS   = 64,
	parameter integer N_CHANS  = 3,
	parameter integer N_PLANES = 8,

	// Auto-set
	parameter integer LOG_N_BANKS = $clog2(N_BANKS),
	parameter integer LOG_N_ROWS  = $clog2(N_ROWS),
	parameter integer LOG_N_COLS  = $clog2(N_COLS)
)(
	// Read interface - Preload
	input  wire [LOG_N_ROWS-1:0] rd_row_addr,
	input  wire rd_row_load,
	output wire rd_row_rdy,
	input  wire rd_row_swap,

	// Read interface - Access
	output wire [(N_BANKS * N_CHANS * N_PLANES)-1:0] rd_data,
	input  wire [LOG_N_COLS-1:0] rd_col_addr,
	input  wire rd_en,

	// Read Out - Control
	output wire ctrl_pending,
	input  wire ctrl_boot,
	input  wire ctrl_active,
	output wire ctrl_done,

	// Read Out - Frame Buffer Access
	output wire [12:0] fb_addr,
	input  wire [15:0] fb_data,

	// Clock / Reset
	input  wire clk,
	input  wire rst
);

	// Signals
	// -------

	// Read-out control
	reg  ro_pingpong;
	reg  ro_pending;
	wire ro_done;

	// Line-Buffer access
	wire [(N_BANKS * N_CHANS * N_PLANES)-1:0] rolb_wr_data;
	wire [N_BANKS-1:0] rolb_wr_mask;
	wire [LOG_N_COLS-1:0] rolb_wr_addr;
	wire rolb_wr_ena;

	// Read-out process
	reg [LOG_N_ROWS-1:0] rop_row_addr;
	reg [7:0] rop_cnt;
	reg rop_last;

	reg rop_active_r;
	reg [7:0] rop_cnt_r;
	reg [15:0] rop_data_r;


	// Read-out
	// --------

	// Line buffer
	hub75_linebuffer #(
		.N_WORDS(N_BANKS),
		.WORD_WIDTH(N_CHANS * N_PLANES),
		.ADDR_WIDTH(1 + LOG_N_COLS)
	) readout_buf_I (
		.wr_addr({~ro_pingpong, rolb_wr_addr}),
		.wr_data(rolb_wr_data),
		.wr_mask(rolb_wr_mask),
		.wr_ena(rolb_wr_ena),
		.rd_addr({ro_pingpong, rd_col_addr}),
		.rd_data(rd_data),
		.rd_ena(rd_en),
		.clk(clk)
	);

	// Buffer swap
	always @(posedge clk)
		if (rst)
			ro_pingpong <= 1'b0;
		else
			ro_pingpong <= ro_pingpong ^ rd_row_swap;

	// Requests
	always @(posedge clk)
		if (rst)
			ro_pending <= 1'b0;
		else
			ro_pending <= (ro_pending & ~ro_done) | rd_row_load;

	assign rd_row_rdy = ~ro_pending;

	assign ro_done = rop_last;

	assign ctrl_pending = ro_pending;
	assign ctrl_done = ro_done;

	// Latch row address
	always @(posedge clk)
		if (rd_row_load)
			rop_row_addr <= rd_row_addr;

	// Counter
	always @(posedge clk)
		if (ctrl_boot)
			rop_cnt <= 0;
		else if (ctrl_active)
			rop_cnt  <= rop_cnt + 1;

	always @(posedge clk)
		if (rst)
			rop_last <= 1'b0;
		else if (ctrl_active)
			rop_last <= (rop_cnt == { 7'h7f, 1'b0 });

	// Delay some data to sync with the frame-buffer read data
	always @(posedge clk)
	begin
		rop_active_r <= ctrl_active;
		rop_cnt_r <= rop_cnt;
	end

	// Delay the data from frame buffer so we get 32 bits at once
	always @(posedge clk)
		rop_data_r <= fb_data;

	// Route data from frame buffer to line buffer
	assign fb_addr = { rop_row_addr, rop_cnt };

	assign rolb_wr_data = { fb_data[7:0], rop_data_r, fb_data[7:0], rop_data_r };
	assign rolb_wr_mask = { rop_cnt_r[1], ~rop_cnt_r[1] };
	assign rolb_wr_addr = rop_cnt_r[7:2];
	assign rolb_wr_ena  = rop_active_r & rop_cnt_r[0];

endmodule // hub75_fb_readout
