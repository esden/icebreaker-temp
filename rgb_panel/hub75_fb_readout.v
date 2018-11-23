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
	parameter integer BITDEPTH = 24,
	parameter integer FB_AW    = 13,
	parameter integer FB_DW    = 16,
	parameter integer FB_DC    = 2,

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
	output wire ctrl_req,
	input  wire ctrl_gnt,
	output reg  ctrl_rel,

	// Read Out - Frame Buffer Access
	output wire [FB_AW-1:0] fb_addr,
	input  wire [FB_DW-1:0] fb_data,

	// Clock / Reset
	input  wire clk,
	input  wire rst
);

	// Counter = [ col_addr : bank_addr : dc_idx ]
	localparam integer CS1 = $clog2(FB_DC);
	localparam integer CS2 = CS1 + LOG_N_BANKS;
	localparam integer CW  = CS2 + LOG_N_COLS;


	// Signals
	// -------

	// Read-out processl
	reg  rop_buf;

	reg  rop_pending;
	reg  rop_running;
	reg  rop_ready;

	reg [LOG_N_ROWS-1:0] rop_row_addr;

	reg [CW-1:0] rop_cnt;
	reg rop_last;

	// Frame buffer access
	wire [BITDEPTH-1:0] fb_data_ext;

	// Line buffer access
	wire [(N_BANKS * N_CHANS * N_PLANES)-1:0] rolb_wr_data;
	reg  [N_BANKS-1:0] rolb_wr_mask;
	reg  [LOG_N_COLS-1:0] rolb_wr_addr;
	reg  rolb_wr_ena;


	// Control
	// -------

	// Buffer swap
	always @(posedge clk or posedge rst)
		if (rst)
			rop_buf <= 1'b0;
		else
			rop_buf <= rop_buf ^ rd_row_swap;

	// Track status and requests
	always @(posedge clk or posedge rst)
		if (rst) begin
			rop_pending <= 1'b0;
			rop_running <= 1'b0;
			rop_ready   <= 1'b0;
		end else begin
			rop_pending <= (rop_pending & ~ctrl_gnt) |  rd_row_load;
			rop_running <= (rop_running & ~rop_last) |  ctrl_gnt;
			rop_ready   <= (rop_ready   |  rop_last) & ~rd_row_load;
		end

	// Arbiter interface
	assign ctrl_req = rop_pending;

	always @(posedge clk)
		ctrl_rel <= rop_last;

	// Read interface
	assign rd_row_rdy = rop_ready;

	// Latch row address
	always @(posedge clk)
		if (rd_row_load)
			rop_row_addr <= rd_row_addr;

	// Counter
	always @(posedge clk)
		if (~rop_running) begin
			rop_cnt  <= 0;
			rop_last <= 1'b0;
		end else begin
			rop_cnt  <= rop_cnt + 1;
			rop_last <= rop_cnt == (((N_COLS - 1) << CS2) | ((1 << CS2) - 2));
		end


	// Line buffer
	// -----------

	hub75_linebuffer #(
		.N_WORDS(N_BANKS),
		.WORD_WIDTH(N_CHANS * N_PLANES),
		.ADDR_WIDTH(1 + LOG_N_COLS)
	) readout_buf_I (
		.wr_addr({~rop_buf, rolb_wr_addr}),
		.wr_data(rolb_wr_data),
		.wr_mask(rolb_wr_mask),
		.wr_ena(rolb_wr_ena),
		.rd_addr({rop_buf, rd_col_addr}),
		.rd_data(rd_data),
		.rd_ena(rd_en),
		.clk(clk)
	);


	// Frame buffer -> Line buffer
	// ---------------------------

	// Frame buffer read
	assign fb_addr = { rop_row_addr, rop_cnt };

	// Delay the data from frame buffer so we get 32 bits at once
	// also select the required bits to get BITDEPTH bits out of it.
	generate
		if (FB_DC > 1) begin
			reg [(FB_DC-1)*FB_DW-1:0] fb_data_r;

			always @(posedge clk)
				fb_data_r <= fb_data;

			assign fb_data_ext = { fb_data[BITDEPTH-(FB_DC-1)*FB_DW-1:0], fb_data_r };
		end else
			assign fb_data_ext = fb_data[BITDEPTH-1:0];
	endgenerate

	// Route data from frame buffer to line buffer
	assign rolb_wr_data = { (N_BANKS){ fb_data_ext } };

	// Sync LB command with read data from frame buffer (1 cycle delay)
	reg i;

	always @(posedge clk)
	begin
		// Address is trivial
		rolb_wr_addr <= rop_cnt[CW-1:CS2];

		// Mask: Check which bank we're writing ATM
		if (N_BANKS > 1)
			for (i=0; i<N_BANKS; i=i+1)
				rolb_wr_mask[i] <= (rop_cnt[CS2-1:CS1] == i);
		else
			rolb_wr_mask <= 1'b1;

		// Write Enable: When we have a full word in the shift register
		if (FB_DC > 1)
			rolb_wr_ena <= rop_running & &rop_cnt[CS1-1:0];
		else
			rolb_wr_ena <= rop_running;
	end

endmodule // hub75_fb_readout
