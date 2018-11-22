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

module pgen (
	// Frame Buffer write interface
	output wire [ 5:0] fbw_row_addr,
	output wire fbw_row_store,
	input  wire fbw_row_rdy,
	output wire fbw_row_swap,

	output wire [23:0] fbw_data,
	output wire [ 5:0] fbw_col_addr,
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
	reg [5:0] cnt_row;
	reg [5:0] cnt_col;
	reg cnt_row_last;
	reg cnt_col_last;


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
			cnt_row_last <= cnt_row == 6'b111110;
		end

	// Column counter
	always @(posedge clk)
		if (fsm_state != ST_GEN_ROW) begin
			cnt_col <= 0;
			cnt_col_last <= 0;
		end else begin
			cnt_col <= cnt_col + 1;
			cnt_col_last <= cnt_col == 6'b111110;
		end


	// Front-Buffer write
	// ------------------

	wire [3:0] c0 = frame[7:4];
	wire [3:0] c1 = frame[7:4] + 1;

	wire [3:0] a0 = 4'hf - frame[3:0];
	wire [3:0] a1 = frame[3:0];

	assign fbw_wren = fsm_state == ST_GEN_ROW;
	assign fbw_col_addr = cnt_col;
	assign fbw_data[23:16] = (cnt_col[5:2] * cnt_col[5:2]) + cnt_col[3:0];
	assign fbw_data[15: 8] =
		(((cnt_col[3:0] == c0) || (cnt_row[3:0] == c0)) ? {a0, a0} : 8'h00) +
		(((cnt_col[3:0] == c1) || (cnt_row[3:0] == c1)) ? {a1, a1} : 8'h00);
	assign fbw_data[ 7: 0] = (cnt_row[5:2] * cnt_row[5:2]) + cnt_row[3:0];


	// Back-Buffer store
	// -----------------

	assign fbw_row_addr  = cnt_row;
	assign fbw_row_store = (fsm_state == ST_WRITE_ROW) && fbw_row_rdy;
	assign fbw_row_swap  = (fsm_state == ST_WRITE_ROW) && fbw_row_rdy;


	// Next frame
	// ----------

	assign frame_swap = (fsm_state == ST_WAIT_ROW) && fbw_row_rdy;

endmodule // pgen
