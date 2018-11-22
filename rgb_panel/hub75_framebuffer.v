/*
 * hub75_framebuffer.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut <tnt@246tNt.com>
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module hub75_framebuffer #(
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
	// Write interface - Row store/swap
	input  wire [LOG_N_BANKS-1:0] wr_bank_addr,
	input  wire [LOG_N_ROWS-1:0]  wr_row_addr,
	input  wire wr_row_store,
	output wire wr_row_rdy,
	input  wire wr_row_swap,

	// Write interface - Access
	input  wire [(N_CHANS * N_PLANES)-1:0] wr_data,
	input  wire [LOG_N_COLS-1:0] wr_col_addr,
	input  wire wr_en,

	// Read interface - Preload
	input  wire [LOG_N_ROWS-1:0] rd_row_addr,
	input  wire rd_row_load,
	output wire rd_row_rdy,
	input  wire rd_row_swap,

	// Read interface - Access
	output wire [(N_BANKS * N_CHANS * N_PLANES)-1:0] rd_data,
	input  wire [LOG_N_COLS-1:0] rd_col_addr,
	input  wire rd_en,

	// Frame swap request
	input  wire frame_swap,

	// Clock / Reset
	input  wire clk,
	input  wire rst
);

	// Signals
	// -------

	// Arbitration logic
	reg  arb_busy;
	reg  arb_prio;

	// Write-in control
	wire wi_req;
	reg  wi_gnt;
	wire wi_rel;

	// Read-out control
	wire ro_req;
	reg  ro_gnt;
	wire ro_rel;

	// Frame buffer access
	wire [15:0] fb_di;
	wire [15:0] fb_do;
	wire [13:0] fb_addr;
	wire [3:0] fb_mask;
	wire fb_wren;

	reg  fb_pingpong;

	// Write-in frame buffer access
	wire [12:0] wifb_addr;
	wire [15:0] wifb_data;
	wire wifb_wren;

	// Read-out frame-buffer access
	wire [12:0] rofb_addr;
	wire [15:0] rofb_data;


	// Frame buffer
	// ------------

	// Arbitration logic
	always @(posedge clk or posedge rst)
	begin
		if (rst) begin
			arb_prio <= 1'b0;
			arb_busy <= 1'b0;
			wi_gnt   <= 1'b0;
			ro_gnt   <= 1'b0;
		end else begin
			arb_busy <= (arb_busy | wi_req | ro_req) & ~(wi_rel | ro_rel);
			arb_prio <= (wi_gnt | ro_gnt) ? ro_gnt  : arb_prio;
			wi_gnt   <= ~arb_busy & wi_req & (~ro_req |  arb_prio);
			ro_gnt   <= ~arb_busy & ro_req & (~wi_req | ~arb_prio);
		end
	end

	// Storage
`ifdef SIM
	SB_SPRAM256KA_SIM mem_I (
`else
	SB_SPRAM256KA mem_I (
`endif
		.DATAIN(fb_di),
		.ADDRESS(fb_addr),
		.MASKWREN(fb_mask),
		.WREN(fb_wren),
		.CHIPSELECT(1'b1),
		.CLOCK(clk),
		.STANDBY(1'b0),
		.SLEEP(1'b0),
		.POWEROFF(1'b1),
		.DATAOUT(fb_do)
	);

	// Double-Buffer
	always @(posedge clk or posedge rst)
		if (rst)
			fb_pingpong <= 1'b0;
		else
			fb_pingpong <= fb_pingpong ^ frame_swap;

	// Shared access
		// We assume users as well behaved and just use wren for mux control
	assign fb_di = wifb_data;
	assign rofb_data = fb_do;
	assign fb_addr = wifb_wren ? { ~fb_pingpong, wifb_addr } : { fb_pingpong, rofb_addr };
	assign fb_mask = 4'hf;
	assign fb_wren = wifb_wren;


	// Write-in
	// --------

	hub75_fb_writein #(
		.N_BANKS(N_BANKS),
		.N_ROWS(N_ROWS),
		.N_COLS(N_COLS),
		.N_CHANS(N_CHANS),
		.N_PLANES(N_PLANES)
	) writein_I (
		.wr_bank_addr(wr_bank_addr),
		.wr_row_addr(wr_row_addr),
		.wr_row_store(wr_row_store),
		.wr_row_rdy(wr_row_rdy),
		.wr_row_swap(wr_row_swap),
		.wr_data(wr_data),
		.wr_col_addr(wr_col_addr),
		.wr_en(wr_en),
		.ctrl_req(wi_req),
		.ctrl_gnt(wi_gnt),
		.ctrl_rel(wi_rel),
		.fb_addr(wifb_addr),
		.fb_data(wifb_data),
		.fb_wren(wifb_wren),
		.clk(clk),
		.rst(rst)
	);


	// Read-out
	// --------

	hub75_fb_readout #(
		.N_BANKS(N_BANKS),
		.N_ROWS(N_ROWS),
		.N_COLS(N_COLS),
		.N_CHANS(N_CHANS),
		.N_PLANES(N_PLANES)
	) readout_I (
		.rd_row_addr(rd_row_addr),
		.rd_row_load(rd_row_load),
		.rd_row_rdy(rd_row_rdy),
		.rd_row_swap(rd_row_swap),
		.rd_data(rd_data),
		.rd_col_addr(rd_col_addr),
		.rd_en(rd_en),
		.ctrl_req(ro_req),
		.ctrl_gnt(ro_gnt),
		.ctrl_rel(ro_rel),
		.fb_addr(rofb_addr),
		.fb_data(rofb_data),
		.clk(clk),
		.rst(rst)
	);

endmodule // hub75_framebuffer
