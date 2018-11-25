/*
 * dsi_tb.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module dsi_tb;

	// Signals
	reg rst = 1'b1;
	reg clk = 1'b0;

	// PHY
	output wire clk_lp;
	output wire clk_hs_p;
	output wire clk_hs_n;
	output wire data_lp;
	output wire data_hs_p;
	output wire data_hs_n;

	// Packet interface
	wire hs_clk_req;
	wire hs_clk_rdy;
	wire hs_clk_sync;

	wire hs_start;
	wire [7:0] hs_data;
	wire hs_last;
	wire hs_ack;

	reg [7:0] cnt;
	reg in_pkt;

	// Setup recording
	initial begin
		$dumpfile("dsi_tb.vcd");
		$dumpvars(0,dsi_tb);
	end

	// Reset pulse
	initial begin
		# 200 rst = 0;
		# 1000000 $finish;
	end

	// Clocks
	always #10 clk = !clk;

	// DUT
	nano_dsi_clk dsi_clk_I (
		.clk_lp(clk_lp),
		.clk_hs_p(clk_hs_p),
		.clk_hs_n(clk_hs_n),
		.hs_req(hs_clk_req),
		.hs_rdy(hs_clk_rdy),
		.clk_sync(hs_clk_sync),
		.cfg_hs_prep(8'h10),
		.cfg_hs_zero(8'h10),
		.cfg_hs_trail(8'h10),
		.clk(clk),
		.rst(rst)
	);
	nano_dsi_data dsi_data_I (
		.data_lp(data_lp),
		.data_hs_p(data_hs_p),
		.data_hs_n(data_hs_n),
		.hs_start(hs_start),
		.hs_data(hs_data),
		.hs_last(hs_last),
		.hs_ack(hs_ack),
		.clk_sync(hs_clk_sync),
		.cfg_hs_prep(8'h10),
		.cfg_hs_zero(8'h10),
		.cfg_hs_trail(8'h10),
		.clk(clk),
		.rst(rst)
	);

	// Packet generator
	always @(posedge clk)
		if (rst)
			cnt <= 0;
		else
			cnt <= cnt + (!in_pkt || hs_ack);

	always @(posedge clk)
		if (rst)
			in_pkt <= 1'b0;
		else
			in_pkt <= (in_pkt | hs_start) & ~(hs_last & hs_ack);

	assign hs_clk_req = (cnt != 8'h00);
	assign hs_start   = (cnt == 8'h0f);
	assign hs_data    = cnt;
	assign hs_last    = (cnt == 8'h1f);

endmodule // dsi_tb
