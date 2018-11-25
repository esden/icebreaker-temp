/*
 * pkt_spi_write.v
 *
 * CERN Open Hardware Licence v1.2 - See LICENSE
 *
 * Copyright (C) 2018  Sylvain Munaut
 *
 * vim: ts=4 sw=4
 */

`default_nettype none

module pkt_spi_write #(
	parameter BASE = 8'h20
)(
	// SPI 'simple bus'
	input  wire [7:0] sb_addr,
	input  wire [7:0] sb_data,
	input  wire sb_first,
	input  wire sb_last,
	input  wire sb_strobe,

	// Packet FIFO write
	output reg  [7:0] fifo_data,
	output reg  fifo_last,
	output reg  fifo_wren,
	input  wire fifo_full,

	// Clock / Reset
	input  wire clk,
	input  wire rst
);
	// Signals
	reg [7:0] data;
	reg first;
	reg last;

	reg [2:0] cnt;

	reg [7:0] data_mux;

	reg hit_ena;
	reg hit_type;
	reg hit_ext;

	// Decode 'hits'
	always @(posedge clk)
	begin
		hit_ena  <= sb_strobe & (sb_addr[7:1] == (BASE >> 1));
		hit_type <= sb_addr[0] & cnt[2] & ~sb_first;
		hit_ext  <= hit_ena & hit_type;
	end

	// Register data
	always @(posedge clk)
		if (sb_strobe) begin
			data  <= sb_data;
			first <= sb_first;
			last  <= sb_last;
		end

	// Position counter
	always @(posedge clk)
		if (sb_strobe) begin
			if (sb_first)
				cnt <= 0;
			else
				cnt <= cnt + { 3'b000, ~cnt[2] };
		end

	// Data Mux
	always @(*)
		if (~hit_type)
			// RAW
			data_mux = data;
		else if (~hit_ext)
			// Ext First byte
			data_mux = { data[4:2], data[1:0], data[1:0], data[1] };
		else
			// Ext Second byte
			data_mux = { data[7:5], data[7:6], data[4:2] };

	// FIFO interface
	always @(posedge clk)
	begin
		fifo_data <= data_mux;
		fifo_last <= last & (~hit_type | hit_ext);
		fifo_wren <= hit_ena | hit_ext;
	end

endmodule // pkt_spi_write
