/*
 * glitch_filter.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module glitch_filter #(
	parameter integer L = 2
)(
	input wire  pin_iob_reg,
	input wire  cond,

	output wire val,
	output reg  rise,
	output reg  fall,

	input  wire clk,
	input  wire rst
);
	// Signals
	wire [L-1:0] all_zero;
	wire [L-1:0] all_one;

	reg [1:0] sync;
	reg state;
	reg [L-1:0] cnt;

	// Constants
	assign all_zero = { L{1'b0} };
	assign all_one  = { L{1'b1} };

	// Synchronizer
	always @(posedge clk)
		sync <= { sync[0], pin_iob_reg };

	// Filter
	always @(posedge clk)
		if (rst)
			cnt <= all_one;
		else begin
			if (sync[1] & (cnt != all_one))
				cnt <= cnt + 1;
			else if (~sync[1] & (cnt != all_zero))
				cnt <= cnt - 1;
			else
				cnt <= cnt;
		end

	// State
	always @(posedge clk)
		if (rst)
			state <= 1'b1;
		else begin
			if (state & cnt == all_zero)
				state <= 1'b0;
			else if (~state & cnt == all_one)
				state <= 1'b1;
			else
				state <= state;
		end

	assign val = state;

	// Rise / Fall detection
	always @(posedge clk)
	begin
		if (~cond) begin
			rise <= 1'b0;
			fall <= 1'b0;
		end else begin
			rise <= ~state & (cnt == all_one);
			fall <=  state & (cnt == all_zero);
		end
	end

endmodule // glitch_filter
