/*
 * spi_reg.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module spi_reg #(
	parameter ADDR = 8'h00,
	parameter integer BYTES = 1
)(
	// Bus interface
	input wire  [7:0] addr,
	input wire  [7:0] data,
	input wire  first,
	input wire  strobe,

	// Reset
	input wire  [(8*BYTES)-1:0] rst_val,

	// Output
	output wire [(8*BYTES)-1:0] out_val,
	output wire out_stb,

	// Clock / Reset
	input wire  clk,
	input wire  rst
);

	localparam integer WIDTH = 8*BYTES;

	// Signals
	wire [WIDTH-1:0] nxt_val;
	reg  [WIDTH-1:0] cur_val;
	wire [BYTES-1:0] hit_delay;
	wire hit;
	reg  out_stb_i;

	// History
	generate
		if (BYTES > 1) begin
			reg [WIDTH-9:0] history;
			reg [BYTES-2:0] bc;

			always @(posedge clk)
				if (rst) begin
					history <= 0;
					bc <= 0;
				end else if (strobe) begin
					history <= nxt_val[WIDTH-9: 0];
					bc <= hit_delay[BYTES-2:0];
				end

			assign nxt_val = { history, data };
			assign hit_delay = { bc, first };
		end else begin
			assign nxt_val = data;
			assign hit_delay = { first };
		end
	endgenerate

	// Address match
	assign hit = hit_delay[BYTES-1] & strobe & (addr == ADDR);

	// Value register
	always @(posedge clk)
		if (rst)
			cur_val <= rst_val;
		else if (hit)
			cur_val <= nxt_val;

	always @(posedge clk)
		out_stb_i <= hit;

	assign out_val = cur_val;
	assign out_stb = out_stb_i;

endmodule // spi_reg
