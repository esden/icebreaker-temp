/*
 * vgen.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module vgen #(
	parameter ADDR_BASE = 24'h040000,
	parameter integer N_FRAMES = 30,
	parameter integer N_ROWS   = 64,	// # of rows (must be power of 2!!!)
	parameter integer N_COLS   = 64,	// # of columns

	// Auto-set
	parameter integer LOG_N_ROWS  = $clog2(N_ROWS),
	parameter integer LOG_N_COLS  = $clog2(N_COLS)
)(
	// SPI reader interface
	output wire [23:0] sr_addr,
	output wire [15:0] sr_len,
	output wire sr_go,
	input  wire sr_rdy,

	input wire [7:0] sr_data,
	input wire sr_valid,

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

	localparam integer FW = 23 - LOG_N_ROWS - LOG_N_COLS;

	// Signals
	// -------

	// FSM
	localparam
		ST_FRAME_WAIT	= 0,
		ST_ROW_SPI_CMD	= 1,
		ST_ROW_SPI_READ	= 2,
		ST_ROW_WRITE	= 3,
		ST_ROW_WAIT		= 4;

	reg  [2:0] fsm_state;
	reg  [2:0] fsm_state_next;

	// Counters
	reg [FW-1:0] cnt_frame;
	reg cnt_frame_last;

	reg [7:0] cnt_rep;
	reg cnt_rep_last;

	reg [LOG_N_ROWS-1:0] cnt_row;
	reg cnt_row_last;

	reg [LOG_N_COLS:0] cnt_col;

	// SPI
	reg [7:0] sr_data_r;
	wire [15:0] sr_data16;


	// FSM
	// ---

	// State register
	always @(posedge clk or posedge rst)
		if (rst)
			fsm_state <= ST_FRAME_WAIT;
		else
			fsm_state <= fsm_state_next;

	// Next-State logic
	always @(*)
	begin
		// Default is not to move
		fsm_state_next = fsm_state;

		// Transitions ?
		case (fsm_state)
			ST_FRAME_WAIT:
				if (frame_rdy & sr_rdy)
					fsm_state_next = ST_ROW_SPI_CMD;

			ST_ROW_SPI_CMD:
				fsm_state_next = ST_ROW_SPI_READ;

			ST_ROW_SPI_READ:
				if (sr_rdy)
					fsm_state_next = ST_ROW_WRITE;

			ST_ROW_WRITE:
				if (fbw_row_rdy)
					fsm_state_next = cnt_row_last ? ST_ROW_WAIT : ST_ROW_SPI_CMD;

			ST_ROW_WAIT:
				if (fbw_row_rdy)
					fsm_state_next = ST_FRAME_WAIT;
		endcase
	end


	// Counters
	// --------

	// Frame counter
	always @(posedge clk or posedge rst)
		if (rst) begin
			cnt_frame <= 0;
			cnt_frame_last <= 1'b0;
		end else if ((fsm_state == ST_ROW_WAIT) && fbw_row_rdy && cnt_rep_last) begin
			cnt_frame <= cnt_frame_last ? { (FW){1'b0} } : (cnt_frame + 1);
			cnt_frame_last <= (cnt_frame == (N_FRAMES - 2));
		end

	// Repeat counter
	always @(posedge clk)
		if ((fsm_state == ST_ROW_WAIT) && fbw_row_rdy) begin
			cnt_rep <= cnt_rep_last ? 8'h00 : (cnt_rep + 1);
			cnt_rep_last <= (cnt_rep == 6);
		end

	// Row counter
	always @(posedge clk)
		if (fsm_state == ST_FRAME_WAIT) begin
			cnt_row <= 0;
			cnt_row_last <= 1'b0;
		end else if ((fsm_state == ST_ROW_WRITE) && fbw_row_rdy) begin
			cnt_row <= cnt_row + 1;
			cnt_row_last <= (cnt_row == (1 << LOG_N_ROWS) - 2);
		end

	// Column counter
	always @(posedge clk)
		if (fsm_state != ST_ROW_SPI_READ)
			cnt_col <= 0;
		else if (sr_valid)
			cnt_col <= cnt_col + 1;


	// SPI reader
	// ----------

	// Requests
	assign sr_addr = { cnt_frame, cnt_row, {(LOG_N_COLS+1){1'b0}} } + ADDR_BASE;
	assign sr_len = (N_COLS << 1) - 1;
	assign sr_go = (fsm_state == ST_ROW_SPI_CMD);

	// Data
	always @(posedge clk)
		if (sr_valid)
			sr_data_r <= sr_data;
	
	assign sr_data16 = { sr_data, sr_data_r };


	// Front-Buffer write
	// ------------------

	assign fbw_wren = sr_valid & cnt_col[0];
	assign fbw_col_addr = cnt_col[6:1];
	assign fbw_data[23:16] = { sr_data16[15:11], sr_data16[15:13] };
	assign fbw_data[15: 8] = { sr_data16[10: 5], sr_data16[10: 9] };
	assign fbw_data[ 7: 0] = { sr_data16[ 4: 0], sr_data16[ 4: 2] };


	// Back-Buffer store
	// -----------------

	assign fbw_row_addr  = cnt_row;
	assign fbw_row_store = (fsm_state == ST_ROW_WRITE) && fbw_row_rdy;
	assign fbw_row_swap  = (fsm_state == ST_ROW_WRITE) && fbw_row_rdy;


	// Next frame
	// ----------

	assign frame_swap = (fsm_state == ST_ROW_WAIT) && fbw_row_rdy;

endmodule // vgen
