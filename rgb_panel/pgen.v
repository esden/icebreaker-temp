/*
 * pgen.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module pgen #(
	parameter integer N_ROWS   = 64,	// # of rows (must be power of 2!!!)
	parameter integer N_COLS   = 64,	// # of columns
	parameter integer BITDEPTH = 24,

	// Auto-set
	parameter integer LOG_N_ROWS  = $clog2(N_ROWS),
	parameter integer LOG_N_COLS  = $clog2(N_COLS)
)(
	// Frame Buffer write interface
	output wire [LOG_N_ROWS-1:0] fbw_row_addr,
	output wire fbw_row_store,
	input  wire fbw_row_rdy,
	output wire fbw_row_swap,

	output wire [BITDEPTH-1:0] fbw_data,
	output wire [LOG_N_COLS-1:0] fbw_col_addr,
	output wire fbw_wren,

	output wire frame_swap,
	input  wire frame_rdy,

	// Clock / Reset
	input  wire clk,
	input  wire rst
);

	// Signals
	// -------

	// FSM
	localparam
		ST_WAIT_FRAME	= 0,
		ST_GEN_ROW		= 1,
		ST_WRITE_ROW	= 2,
		ST_WAIT_ROW		= 3;

	reg  [2:0] fsm_state;
	reg  [2:0] fsm_state_next;

	// Counters
	reg [11:0] frame;
	reg [LOG_N_ROWS-1:0] cnt_row;
	reg [LOG_N_COLS-1:0] cnt_col;
	reg cnt_row_last;
	reg cnt_col_last;

	// Output
	wire [7:0] color [0:2];


	// FSM
	// ---

	// State register
	always @(posedge clk or posedge rst)
		if (rst)
			fsm_state <= ST_WAIT_FRAME;
		else
			fsm_state <= fsm_state_next;

	// Next-State logic
	always @(*)
	begin
		// Default is not to move
		fsm_state_next = fsm_state;

		// Transitions ?
		case (fsm_state)
			ST_WAIT_FRAME:
				if (frame_rdy)
					fsm_state_next = ST_GEN_ROW;

			ST_GEN_ROW:
				if (cnt_col_last)
					fsm_state_next = ST_WRITE_ROW;

			ST_WRITE_ROW:
				if (fbw_row_rdy)
					fsm_state_next = cnt_row_last ? ST_WAIT_ROW : ST_GEN_ROW;

			ST_WAIT_ROW:
				if (fbw_row_rdy)
					fsm_state_next = ST_WAIT_FRAME;
		endcase
	end


	// Counters
	// --------

	// Frame counter
	always @(posedge clk or posedge rst)
		if (rst)
			frame <= 0;
		else if ((fsm_state == ST_WAIT_ROW) && fbw_row_rdy)
			frame <= frame + 1;

	// Row counter
	always @(posedge clk)
		if (fsm_state == ST_WAIT_FRAME) begin
			cnt_row <= 0;
			cnt_row_last <= 1'b0;
		end else if ((fsm_state == ST_WRITE_ROW) && fbw_row_rdy) begin
			cnt_row <= cnt_row + 1;
			cnt_row_last <= cnt_row == ((1 << LOG_N_ROWS) - 2);
		end

	// Column counter
	always @(posedge clk)
		if (fsm_state != ST_GEN_ROW) begin
			cnt_col <= 0;
			cnt_col_last <= 0;
		end else begin
			cnt_col <= cnt_col + 1;
			cnt_col_last <= cnt_col == (N_COLS - 2);
		end


	// Front-Buffer write
	// ------------------

	// Generate R/B channels by taking 8 bits off the row/col counters
	// (and wrapping to the MSBs if those are shorter than 8 bits
	genvar i;
	generate
		for (i=0; i<8; i=i+1)
		begin
			assign color[0][7-i] = cnt_col[LOG_N_COLS-1-(i%LOG_N_COLS)];
			assign color[2][7-i] = cnt_row[LOG_N_ROWS-1-(i%LOG_N_ROWS)];
		end
	endgenerate

	// Moving green lines
	wire [3:0] c0 = frame[7:4];
	wire [3:0] c1 = frame[7:4] + 1;

	wire [3:0] a0 = 4'hf - frame[3:0];
	wire [3:0] a1 = frame[3:0];

	assign color[1] =
		(((cnt_col[3:0] == c0) || (cnt_row[3:0] == c0)) ? {a0, a0} : 8'h00) +
		(((cnt_col[3:0] == c1) || (cnt_row[3:0] == c1)) ? {a1, a1} : 8'h00);

	// Write enable and address
	assign fbw_wren = fsm_state == ST_GEN_ROW;
	assign fbw_col_addr = cnt_col;

	// Map to color
	generate
		if (BITDEPTH == 8)
			assign fbw_data = { color[0][7:5], color[1][7:5], color[2][7:6] };
		else if (BITDEPTH == 16)
			assign fbw_data = { color[0][7:3], color[1][7:2], color[2][7:3] };
		else if (BITDEPTH == 24)
			assign fbw_data = { color[0], color[1], color[2] };
	endgenerate


	// Back-Buffer store
	// -----------------

	assign fbw_row_addr  = cnt_row;
	assign fbw_row_store = (fsm_state == ST_WRITE_ROW) && fbw_row_rdy;
	assign fbw_row_swap  = (fsm_state == ST_WRITE_ROW) && fbw_row_rdy;


	// Next frame
	// ----------

	assign frame_swap = (fsm_state == ST_WAIT_ROW) && fbw_row_rdy;

endmodule // pgen
