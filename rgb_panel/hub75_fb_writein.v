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
	parameter integer N_CHANS  = 3,
	parameter integer N_PLANES = 8,

	// Auto-set
	parameter integer LOG_N_BANKS = $clog2(N_BANKS),
	parameter integer LOG_N_ROWS  = $clog2(N_ROWS),
	parameter integer LOG_N_COLS  = $clog2(N_COLS)
)(
	// Write interface - Access
	input  wire [LOG_N_BANKS-1:0] wr_bank_addr,
	input  wire [LOG_N_ROWS-1:0]  wr_row_addr,
	input  wire wr_row_store,
	output wire wr_row_rdy,
	input  wire wr_row_swap,

	input  wire [(N_CHANS * N_PLANES)-1:0] wr_data,
	input  wire [LOG_N_COLS-1:0] wr_col_addr,
	input  wire wr_en,

	// Write In - Control
	output wire ctrl_pending,
	input  wire ctrl_boot,
	input  wire ctrl_active,
	output wire ctrl_done,

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

	// Write-in control
	reg  wi_pingpong;
	reg  wi_pending;
	wire wi_done;

	// Write-in line-buffer access
	wire [LOG_N_COLS-1:0] wilb_col_addr;
	wire [(N_CHANS * N_PLANES)-1:0] wilb_data;
	wire wilb_rden;

	// Write-in process
	reg  [LOG_N_BANKS-1:0] wip_bank_addr;
	reg  [LOG_N_ROWS-1:0]  wip_row_addr;

	reg  [LOG_N_COLS:0] wip_cnt;
	reg  wip_last;

	// Frame Buffer Access
	reg  [12:0] fb_addr_i;
	reg  fb_wren_i;


	// Write-in
	// --------

	// Line buffer
	hub75_linebuffer #(
		.N_WORDS(1),
		.WORD_WIDTH(N_CHANS * N_PLANES),
		.ADDR_WIDTH(1 + LOG_N_COLS)
	) writein_buf_I (
		.wr_addr({~wi_pingpong, wr_col_addr}),
		.wr_data(wr_data),
		.wr_mask(1'b1),
		.wr_ena(wr_en),
		.rd_addr({wi_pingpong, wilb_col_addr}),
		.rd_data(wilb_data),
		.rd_ena(wilb_rden),
		.clk(clk)
	);

	// Buffer swap
	always @(posedge clk)
		if (rst)
			wi_pingpong <= 1'b0;
		else
			wi_pingpong <= wi_pingpong ^ wr_row_swap;

	// Requests
	always @(posedge clk)
		if (rst)
			wi_pending <= 1'b0;
		else
			wi_pending <= (wi_pending & ~wi_done) | wr_row_store;

	assign wr_row_rdy = ~wi_pending;

	assign wi_done = wip_last;

	assign ctrl_pending = wi_pending;
	assign ctrl_done = wi_done;

	// Latch bank/row address
	always @(posedge clk)
		if (wr_row_store) begin
			wip_bank_addr <= wr_bank_addr;
			wip_row_addr  <= wr_row_addr;
		end

	// Counter
	always @(posedge clk)
		if (ctrl_boot)
			wip_cnt <= 0;
		else if (ctrl_active)
			wip_cnt <= wip_cnt + 1;

	always @(posedge clk)
		if (rst)
			wip_last <= 1'b0;
		else if (ctrl_active)
			wip_last <= (wip_cnt == { {(LOG_N_COLS){1'b1}}, 1'b0 });

	// Line buffer read
	assign wilb_col_addr = wip_cnt[LOG_N_COLS:1];
	assign wilb_rden = ctrl_active;

	// Route data from frame buffer to line buffer
	assign fb_data = fb_addr_i[0] ? {8'h00, wilb_data[23:16] } : wilb_data[15:0];

		// Those are one cycle late because we need to wait for the FB data
	always @(posedge clk)
	begin
		fb_addr_i <= { wip_row_addr, wip_cnt[LOG_N_COLS:1], wip_bank_addr, wip_cnt[0] };
		fb_wren_i <= ctrl_active;
	end

	assign fb_addr = fb_addr_i;
	assign fb_wren = fb_wren_i;

endmodule // hub75_fb_writein
