/*
 * pwm.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module pwm #(
	parameter integer WIDTH = 10
)(
	// PWM out
	output wire pwm,

	// Config
	input wire [WIDTH-1:0] cfg_val,

	// Clock / Reset
	input wire  clk,
	input wire  rst
);
	wire [WIDTH:0] cnt_cycle_rst;
	reg [WIDTH:0] cnt_cycle;
	reg [WIDTH:0] cnt_on;

	assign cnt_cycle_rst = { { (WIDTH-1){1'b0} }, 2'b10 };

	always @(posedge clk)
		if (rst)
			cnt_cycle <= cnt_cycle_rst;
		else
			cnt_cycle <= cnt_cycle[WIDTH] ? cnt_cycle_rst : (cnt_cycle + 1);

	always @(posedge clk)
		if (rst)
			cnt_on <= 0;
		else
			cnt_on <= (cnt_cycle[WIDTH] ? { 1'b1, cfg_val } : cnt_on) - 1;

	assign pwm = cnt_on[WIDTH];

endmodule // pwm
