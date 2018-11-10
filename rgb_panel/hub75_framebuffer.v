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
	// Write interface - Access
	input  wire [LOG_N_BANKS-1:0] wr_bank_addr,
	input  wire [LOG_N_ROWS-1:0]  wr_row_addr,
	input  wire wr_row_store,
	output wire wr_row_rdy,
	input  wire wr_row_swap,

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
	reg  wi_pingpong;
	reg  wi_pending;
	wire wi_boot;
	wire wi_active;
	wire wi_done;

	// Write-in frame buffer access
	reg  [12:0] wifb_addr;
	wire [15:0] wifb_data;
	wire [ 3:0] wifb_mask;
	reg  wifb_wren;

	// Write-in line-buffer access
	wire [LOG_N_COLS-1:0] wilb_col_addr;
	wire [(N_CHANS * N_PLANES)-1:0] wilb_data;
	wire wilb_rden;

	// Write-in process
	reg  [LOG_N_BANKS-1:0] wip_bank_addr;
	reg  [LOG_N_ROWS-1:0]  wip_row_addr;

	reg  [LOG_N_COLS:0] wip_cnt;
	reg  wip_last;

	// Read-out control
	reg  ro_pingpong;
	reg  ro_pending;
	wire ro_boot;
	wire ro_active;
	wire ro_done;

	// Read-out frame-buffer access
	wire [12:0] rofb_addr;
	wire [15:0] rofb_data;

	// Read-out line-buffer access
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


	// Frame buffer
	// ------------

	// FSM
		// State register
	always @(posedge clk)
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
	always @(posedge clk)
		if (rst)
			fb_pingpong <= 1'b0;
		else
			fb_pingpong <= fb_pingpong ^ frame_swap;

	// Shared access
	assign fb_di = wifb_data;
	assign rofb_data = fb_do;
	assign fb_addr = ((fsm_state == ST_WRITEIN_BOOT) || (fsm_state == ST_WRITEIN_RUN)) ? { ~fb_pingpong, wifb_addr } : { fb_pingpong, rofb_addr };
	assign fb_mask = wifb_mask;
	assign fb_wren = ((fsm_state == ST_WRITEIN_BOOT) || (fsm_state == ST_WRITEIN_RUN)) ? wifb_wren : 1'b0;

	// Interface to the Write-in / Read-out control
	assign wi_boot   = (fsm_state == ST_WRITEIN_BOOT);
	assign wi_active = (fsm_state == ST_WRITEIN_RUN);
	assign ro_boot   = (fsm_state == ST_READOUT_BOOT);
	assign ro_active = (fsm_state == ST_READOUT_RUN);


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

	// Latch bank/row address
	always @(posedge clk)
		if (wr_row_store) begin
			wip_bank_addr <= wr_bank_addr;
			wip_row_addr  <= wr_row_addr;
		end

	// Counter
	always @(posedge clk)
		if (wi_boot)
			wip_cnt <= 0;
		else if (wi_active)
			wip_cnt <= wip_cnt + 1;

	always @(posedge clk)
		if (rst)
			wip_last <= 1'b0;
		else if (wi_active)
			wip_last <= (wip_cnt == { {(LOG_N_COLS){1'b1}}, 1'b0 });

	// Line buffer read
	assign wilb_col_addr = wip_cnt[LOG_N_COLS:1];
	assign wilb_rden = wi_active;

	// Route data from frame buffer to line buffer
	assign wifb_data = wip_cnt[0] ? {8'h00, wilb_data[23:16] } : wilb_data[15:0];
	assign wifb_mask = 4'hf;

		// Those are one cycle late because we need to wait for the FB data
	always @(posedge clk)
	begin
		wifb_addr <= { wip_row_addr, wip_cnt, wip_bank_addr };
		wifb_wren <= wi_active;
	end


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

	// Latch row address
	always @(posedge clk)
		if (rd_row_load)
			rop_row_addr <= rd_row_addr;

	// Counter
	always @(posedge clk)
		if (ro_boot)
			rop_cnt <= 0;
		else if (ro_active)
			rop_cnt  <= rop_cnt + 1;

	always @(posedge clk)
		if (rst)
			rop_last <= 1'b0;
		else if (ro_active)
			rop_last <= (rop_cnt == { 7'h7f, 1'b0 });

	// Delay some data to sync with the frame-buffer read data
	always @(posedge clk)
	begin
		rop_active_r <= ro_active;
		rop_cnt_r <= rop_cnt;
	end

	// Delay the data from frame buffer so we get 32 bits at once
	always @(posedge clk)
		rop_data_r <= rofb_data;

	// Route data from frame buffer to line buffer
	assign rofb_addr = { rop_row_addr, rop_cnt };

	assign rolb_wr_data = { rofb_data[7:0], rop_data_r, rofb_data[7:0], rop_data_r };
	assign rolb_wr_mask = { rop_cnt_r[1], ~rop_cnt_r[1] };
	assign rolb_wr_addr = rop_cnt_r[7:2];
	assign rolb_wr_ena  = rop_active_r & rop_cnt_r[0];

endmodule // hub75_framebuffer


module hub75_linebuffer #(
	parameter N_WORDS = 1,
	parameter WORD_WIDTH = 24,
	parameter ADDR_WIDTH = 6
)(
	input  wire [ADDR_WIDTH-1:0] wr_addr,
	input  wire [(N_WORDS*WORD_WIDTH)-1:0] wr_data,
	input  wire [N_WORDS-1:0] wr_mask,
	input  wire wr_ena,

	input  wire [ADDR_WIDTH-1:0] rd_addr,
	output reg  [(N_WORDS*WORD_WIDTH)-1:0] rd_data,
	input  wire rd_ena,

	input  wire clk
);
	integer i;
	reg [(N_WORDS*WORD_WIDTH)-1:0] ram [(1<<ADDR_WIDTH)-1:0];

`ifdef SIM
	initial
		for (i=0; i<(1<<ADDR_WIDTH); i=i+1)
			ram[i] = 0;
`endif

	always @(posedge clk)
	begin
		// Read
		if (rd_ena)
			rd_data <= ram[rd_addr];

		// Write
		if (wr_ena)
			for (i=0; i<N_WORDS; i=i+1)
				if (wr_mask[i])
					ram[wr_addr][((i+1)*WORD_WIDTH)-1 -: WORD_WIDTH] = wr_data[((i+1)*WORD_WIDTH)-1 -: WORD_WIDTH];
	end

endmodule // hub75_linebuffer
