/*
 * sysmgr.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018 Sylvain Munaut
 *
 * vim: ts=4 sw=4
 */

`default_nettype none
//`define FREQ_60M

module sysmgr (
	input  wire clk_in,
	input  wire rst_in,
	output wire clk_out,
	output wire rst_out
);

	// Signals
	wire pll_lock;
	wire pll_reset_n;

	wire clk_i;
	wire rst_i;
	reg [3:0] rst_cnt;

	// PLL instance
`ifdef SIM
	assign clk_i = clk_in;
	assign pll_lock = pll_reset_n;
`else
	SB_PLL40_PAD #(
`ifdef FREQ_60M
			// 60 M
		.DIVR(4'b0000),
		.DIVF(7'b1001111),
		.DIVQ(3'b100),
		.FILTER_RANGE(3'b001),
`else
			// 48 M
		.DIVR(4'b0000),
		.DIVF(7'b0111111),
		.DIVQ(3'b100),
		.FILTER_RANGE(3'b001),
`endif
		.FEEDBACK_PATH("SIMPLE"),
		.DELAY_ADJUSTMENT_MODE_FEEDBACK("FIXED"),
		.FDA_FEEDBACK(4'b0000),
		.SHIFTREG_DIV_MODE(2'b00),
		.PLLOUT_SELECT("GENCLK"),
		.ENABLE_ICEGATE(1'b0)
	) pll_I (
		.PACKAGEPIN(clk_in),
		.PLLOUTGLOBAL(clk_i),
		.EXTFEEDBACK(1'b0),
		.DYNAMICDELAY(8'h00),
		.RESETB(pll_reset_n),
		.BYPASS(1'b0),
		.LATCHINPUTVALUE(1'b0),
		.LOCK(pll_lock),
		.SDI(1'b0),
		.SDO(),
		.SCLK(1'b0)
	);
`endif

	assign clk_out = clk_i;

	// PLL reset generation
	assign pll_reset_n = ~rst_in;

	// Logic reset generation
	always @(posedge clk_i)
		if (!pll_lock)
			rst_cnt <= 4'h8;
		else if (rst_cnt[3])
			rst_cnt <= rst_cnt + 1;

	assign rst_i = rst_cnt[3];

	SB_GB rst_gbuf_I (
		.USER_SIGNAL_TO_GLOBAL_BUFFER(rst_i),
		.GLOBAL_BUFFER_OUTPUT(rst_out)
	);

endmodule // sysmgr
