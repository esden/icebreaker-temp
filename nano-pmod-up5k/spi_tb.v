/*
 * spi_tb.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module spi_tb;

	// Signals
	reg rst = 1'b1;
	reg clk = 1'b0;

	wire spi_mosi;
	wire spi_miso;
	wire spi_cs_n;
	wire spi_clk;

	wire [7:0] sb_addr;
	wire [7:0] sb_data;
	wire sb_first;
	wire sb_last;
	wire sb_strobe;

	wire [15:0] reg_val;
	wire reg_stb;

	wire [7:0] spf_wr_data;
	wire spf_wr_last;
	wire spf_wr_ena;
	wire spf_full = 1'b0;

	// Setup recording
	initial begin
		$dumpfile("spi_tb.vcd");
		$dumpvars(0,spi_tb);
	end

	// Reset pulse
	initial begin
		# 200 rst = 0;
		# 1000000 $finish;
	end

	// Clocks
	always #10 clk = !clk;

	// DUT
	spi_simple spi_I (
		.spi_mosi(spi_mosi),
		.spi_miso(spi_miso),
		.spi_cs_n(spi_cs_n),
		.spi_clk(spi_clk),
		.addr(sb_addr),
		.data(sb_data),
		.first(sb_first),
		.last(sb_last),
		.strobe(sb_strobe),
		.out(8'hba),
		.clk(clk),
		.rst(rst)
	);

	spi_reg #(
		.ADDR(8'hA5),
		.BYTES(2)
	) reg_I (
		.addr(sb_addr),
		.data(sb_data),
		.first(sb_first),
		.strobe(sb_strobe),
		.rst_val(16'hbabe),
		.out_val(reg_val),
		.out_stb(reg_stb),
		.clk(clk),
		.rst(rst)
	);

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
	reg [71:0] spi_csn_data = 72'b11110000000000000000000000000000000000000000000000000001111;
	reg [71:0] spi_clk_data = 72'b00000010101010101010101010101010101010101010101010101000000;
	reg [71:0] spi_dat_data = 72'b00000110011000011001111110000000000111111000000001100000000;

	reg [4:0] div;

	always @(posedge clk)
		if (rst)
			div <= 0;
		else
			div <= div + 1;

	always @(posedge clk)
		if (div == 4'hf) begin
			spi_csn_data <= { spi_csn_data[70:0], 1'b0 & spi_csn_data[71] };
			spi_clk_data <= { spi_clk_data[70:0], spi_clk_data[71] };
			spi_dat_data <= { spi_dat_data[70:0], spi_dat_data[71] };
		end

	assign spi_mosi = spi_dat_data[70];
	assign spi_cs_n = spi_csn_data[70];
	assign spi_clk  = spi_clk_data[70];

endmodule // spi_tb
