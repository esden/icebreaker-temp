/*
 * pkt_spi_write_tb.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module pkt_spi_write_tb;

	// Signals
	reg rst = 1'b1;
	reg clk = 1'b0;

	wire [7:0] sb_addr;
	wire [7:0] sb_data;
	wire sb_first;
	wire sb_last;
	wire sb_strobe;

	wire [7:0] spf_wr_data;
	wire spf_wr_last;
	wire spf_wr_ena;
	wire spf_full = 1'b0;

	// Setup recording
	initial begin
		$dumpfile("pkt_spi_write_tb.vcd");
		$dumpvars(0,pkt_spi_write_tb);
	end

	// Reset pulse
	initial begin
		# 200 rst = 0;
		# 1000000 $finish;
	end

	// Clocks
	always #10 clk = !clk;

	// DUT
	pkt_spi_write #(
		.BASE(8'hA4)
	) pkt_I (
		.sb_addr(sb_addr),
		.sb_data(sb_data),
		.sb_first(sb_first),
		.sb_last(sb_last),
		.sb_strobe(sb_strobe),
		.fifo_data(spf_wr_data),
		.fifo_last(spf_wr_last),
		.fifo_wren(spf_wr_ena),
		.fifo_full(spf_full),
		.clk(clk),
		.rst(rst)
	);

	// SPI data generation
	reg [7:0] cnt;

	always @(posedge clk)
		if (rst)
			cnt <= 0;
		else
			cnt <= cnt + 1;


	assign sb_addr   = sb_strobe ? 8'ha5 : 8'hxx;
	assign sb_data   = sb_strobe ? cnt : 8'hxx;
	assign sb_first  = sb_strobe ? cnt[7:4] == 4'h0 : 1'bx;
	assign sb_last   = sb_strobe ? cnt[7:4] == 4'hf : 1'bx;
	assign sb_strobe = cnt[3:0] == 4'hf;

endmodule // pkt_spi_write_tb
