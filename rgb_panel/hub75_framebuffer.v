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

	// FSM
	localparam
		ST_IDLE_WRITE	= 0,
		ST_IDLE_READ	= 1,
		ST_WRITEIN_BOOT	= 2,
		ST_WRITEIN_RUN	= 3,
		ST_READOUT_BOOT	= 4,
		ST_READOUT_RUN	= 5;

	reg  [2:0] fsm_state;
	reg  [2:0] fsm_state_next;

	// Frame buffer access
	wire [15:0] fb_di;
	wire [15:0] fb_do;
	wire [13:0] fb_addr;
	wire [3:0] fb_mask;
	wire fb_wren;

	reg  fb_pingpong;

	// Write-in control
	wire wi_pending;
	wire wi_boot;
	wire wi_active;
	wire wi_done;

	// Write-in frame buffer access
	wire [12:0] wifb_addr;
	wire [15:0] wifb_data;
	wire wifb_wren;

	// Read-out control
	wire ro_pending;
	wire ro_boot;
	wire ro_active;
	wire ro_done;

	// Read-out frame-buffer access
	wire [12:0] rofb_addr;
	wire [15:0] rofb_data;


	// Frame buffer
	// ------------

	// FSM
		// State register
	always @(posedge clk or posedge rst)
		if (rst)
			fsm_state <= ST_IDLE_WRITE;
		else
			fsm_state <= fsm_state_next;

		// Next-State logic
	always @(*)
	begin
		// Default is not to move
		fsm_state_next = fsm_state;

		// Transitions ?
		case (fsm_state)
			ST_IDLE_WRITE:
				if (wi_pending)
					fsm_state_next = ST_WRITEIN_BOOT;
				else if (ro_pending)
					fsm_state_next = ST_READOUT_BOOT;

			ST_IDLE_READ:
				if (ro_pending)
					fsm_state_next = ST_READOUT_BOOT;
				else if (wi_pending)
					fsm_state_next = ST_WRITEIN_BOOT;

			ST_WRITEIN_BOOT:
				fsm_state_next = ST_WRITEIN_RUN;

			ST_WRITEIN_RUN:
				if (wi_done)
					fsm_state_next = ST_IDLE_READ;

			ST_READOUT_BOOT:
				fsm_state_next = ST_READOUT_RUN;

			ST_READOUT_RUN:
				if (ro_done)
					fsm_state_next = ST_IDLE_WRITE;

		endcase
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
		// We default to 'WRITE' because it will actually access the RAM one
		// cycle after the state has gone to IDLE due to pipeline delay
	assign fb_di = wifb_data;
	assign rofb_data = fb_do;
	assign fb_addr = wifb_wren ? { ~fb_pingpong, wifb_addr } : { fb_pingpong, rofb_addr };
	assign fb_mask = 4'hf;
	assign fb_wren = wifb_wren;

	// Interface to the Write-in / Read-out control
	assign wi_boot   = (fsm_state == ST_WRITEIN_BOOT);
	assign wi_active = (fsm_state == ST_WRITEIN_RUN);
	assign ro_boot   = (fsm_state == ST_READOUT_BOOT);
	assign ro_active = (fsm_state == ST_READOUT_RUN);


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
		.ctrl_pending(wi_pending),
		.ctrl_boot(wi_boot),
		.ctrl_active(wi_active),
		.ctrl_done(wi_done),
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
		.ctrl_pending(ro_pending),
		.ctrl_boot(ro_boot),
		.ctrl_active(ro_active),
		.ctrl_done(ro_done),
		.fb_addr(rofb_addr),
		.fb_data(rofb_data),
		.clk(clk),
		.rst(rst)
	);

endmodule // hub75_framebuffer
