/*
 * hub75_fb_writein.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut <tnt@246tNt.com>
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module hub75_fb_writein #(
	parameter integer N_BANKS  = 2,
	parameter integer N_ROWS   = 32,
	parameter integer N_COLS   = 64,
	parameter integer BITDEPTH = 24,

	// Auto-set
	parameter integer LOG_N_BANKS = $clog2(N_BANKS),
	parameter integer LOG_N_ROWS  = $clog2(N_ROWS),
	parameter integer LOG_N_COLS  = $clog2(N_COLS)
)(
	// Write interface - Row store/swap
	input  wire [LOG_N_BANKS-1:0] wr_bank_addr,
	input  wire [LOG_N_ROWS-1:0]  wr_row_addr,
	input  wire wr_row_store,
	output wire wr_row_rdy,
	input  wire wr_row_swap,

	// Write interface - Access
	input  wire [BITDEPTH-1:0] wr_data,
	input  wire [LOG_N_COLS-1:0] wr_col_addr,
	input  wire wr_en,

	// Write In - Control
	output wire ctrl_req,
	input  wire ctrl_gnt,
	output reg  ctrl_rel,

	// Write In - Frame Buffer Access
	output wire [12:0] fb_addr,
	output wire [15:0] fb_data,
	output wire fb_wren,

	// Clock / Reset
	input  wire clk,
	input  wire rst
);

	// Signals
	// -------

	// Write-in process
	reg  wip_buf;

	reg  wip_pending;
	reg  wip_running;
	reg  wip_ready;

	reg  [LOG_N_BANKS-1:0] wip_bank_addr;
	reg  [LOG_N_ROWS-1:0]  wip_row_addr;

	reg  [LOG_N_COLS:0] wip_cnt;
	reg  wip_last;

	// Line buffer access
	wire [LOG_N_COLS-1:0] wilb_col_addr;
	wire [BITDEPTH-1:0] wilb_data;
	wire wilb_rden;

	// Frame buffer access
	reg  [12:0] fb_addr_i;
	reg  fb_wren_i;


	// Control
	// -------

	// Buffer swap
	always @(posedge clk or posedge rst)
		if (rst)
			wip_buf <= 1'b0;
		else
			wip_buf <= wip_buf ^ wr_row_swap;

	// Track status and requests
	always @(posedge clk or posedge rst)
		if (rst) begin
			wip_pending <= 1'b0;
			wip_running <= 1'b0;
			wip_ready   <= 1'b1;
		end else begin
			wip_pending <= (wip_pending & ~ctrl_gnt) |  wr_row_store;
			wip_running <= (wip_running & ~wip_last) |  ctrl_gnt;
			wip_ready   <= (wip_ready   |  wip_last) & ~wr_row_store;
		end

	// Arbiter interface
	assign ctrl_req = wip_pending;

	always @(posedge clk)
		ctrl_rel <= wip_last;

	// Write interface
	assign wr_row_rdy = wip_ready;

	// Latch bank/row address
	always @(posedge clk)
		if (wr_row_store) begin
			wip_bank_addr <= wr_bank_addr;
			wip_row_addr  <= wr_row_addr;
		end

	// Counter
	always @(posedge clk)
		if (~wip_running) begin
			wip_cnt  <= 0;
			wip_last <= 1'b0;
		end else begin
			wip_cnt  <= wip_cnt + 1;
			wip_last <= (wip_cnt[LOG_N_COLS:1] == (N_COLS - 1)) & ~wip_cnt[0];
		end


	// Line buffer
	// -----------

	hub75_linebuffer #(
		.N_WORDS(1),
		.WORD_WIDTH(BITDEPTH),
		.ADDR_WIDTH(1 + LOG_N_COLS)
	) writein_buf_I (
		.wr_addr({~wip_buf, wr_col_addr}),
		.wr_data(wr_data),
		.wr_mask(1'b1),
		.wr_ena(wr_en),
		.rd_addr({wip_buf, wilb_col_addr}),
		.rd_data(wilb_data),
		.rd_ena(wilb_rden),
		.clk(clk)
	);


	// Line buffer -> Frame buffer
	// ---------------------------

	// Line buffer read
	assign wilb_col_addr = wip_cnt[LOG_N_COLS:1];
	assign wilb_rden = wip_running;

	// Route data from frame buffer to line buffer
	assign fb_data = fb_addr_i[0] ? {8'h00, wilb_data[23:16] } : wilb_data[15:0];

	// Sync FB command with the read data from line buffer (1 cycle delay)
	always @(posedge clk)
	begin
		fb_addr_i <= { wip_row_addr, wip_cnt[LOG_N_COLS:1], wip_bank_addr, wip_cnt[0] };
		fb_wren_i <= wip_running;
	end

	assign fb_addr = fb_addr_i;
	assign fb_wren = fb_wren_i;

endmodule // hub75_fb_writein
