/*
 * pkt_fifo_tb.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module pkt_fifo_tb;

	// Signals
	reg rst = 1'b1;
	reg clk = 1'b0;

	wire [7:0] wr_data;
	wire wr_last;
	wire wr_ena;
	wire full;

	wire [7:0] rd_data;
	wire rd_last;
	wire rd_ena;
	wire empty;

	// Setup recording
	initial begin
		$dumpfile("pkt_fifo_tb.vcd");
		$dumpvars(0,pkt_fifo_tb);
	end

	// Reset pulse
	initial begin
		# 200 rst = 0;
		# 1000000 $finish;
	end

	// Clocks
	always #10 clk = !clk;

	// DUT
	pkt_fifo #(
		.AWIDTH(5)
	) dut_I (
		.wr_data(wr_data),
		.wr_last(wr_last),
		.wr_ena(wr_ena),
		.full(full),
		.rd_data(rd_data),
		.rd_last(rd_last),
		.rd_ena(rd_ena),
		.empty(empty),
		.clk(clk),
		.rst(rst)
	);

	// Feed some data
	assign rd_ena = r & ~empty;

	reg [7:0] cnt;
	reg r;

	always @(posedge clk)
		if (rst)
			r <= 1'b0;
		else
			r <= $random & $random;

	always @(posedge clk)
		if (rst)
			cnt <= 0;
		else
			cnt <= cnt + 1;

	assign wr_data = cnt;
	assign wr_last = (cnt[2:0] == 3'b111);
	assign wr_ena  = ~full & (cnt[7:6] == 2'b01);

endmodule // pkt_fifo_tb
