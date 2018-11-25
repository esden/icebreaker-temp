#!/usr/bin/env python3

import time

from pyftdi.spi import SpiController
from pycrc.algorithms import Crc


# ---------------------------------------------------------------------------
# DSI utilities
# ---------------------------------------------------------------------------

EOTP = [ 0x08, 0x0f, 0x0f, 0x01 ]

DSI_CRC = Crc(width=16, poly=0x1021, xor_in=0xffff, xor_out=0x0000, reflect_in=True, reflect_out=True)


def parity(x):
	p = 0
	while x:
		p ^= x & 1
		x >>= 1
	return p

def dsi_header(data):
	cmd = (data[2] << 16) | (data[1] << 8) | data[0]
	ecc = 0
	if parity(cmd & 0b111100010010110010110111): ecc |= 0x01;
	if parity(cmd & 0b111100100101010101011011): ecc |= 0x02;
	if parity(cmd & 0b011101001001101001101101): ecc |= 0x04;
	if parity(cmd & 0b101110001110001110001110): ecc |= 0x08;
	if parity(cmd & 0b110111110000001111110000): ecc |= 0x10;
	if parity(cmd & 0b111011111111110000000000): ecc |= 0x20;
	return data + [ecc]


def dsi_crc(payload):
	crc = DSI_CRC.bit_by_bit(bytes(payload))
	return [ crc & 0xff, (crc >> 8) & 0xff ]


def dcs_short_write(cmd, val=None):
	if val is None:
		return dsi_header([0x05, cmd, 0x00])
	else:
		return dsi_header([0x15, cmd, val])

def dcs_long_write(cmd, data):
	pl = [ cmd ] + data
	l = len(pl)
	return dsi_header([0x39, l & 0xff, l >> 8]) + pl + dsi_crc(pl)

def generic_short_write(cmd, val=None):
	if val is None:
		return dsi_header([0x13, cmd, 0x00])
	else:
		return dsi_header([0x23, cmd, val])

def generic_long_write(cmd, data):
	pl = [ cmd ] + data
	l = len(pl)
	return dsi_header([0x29, l & 0xff, l >> 8]) + pl + dsi_crc(pl)


class DSIControl(object):

	REG_LCD_CTRL = 0x00
	REG_DSI_HS_PREP = 0x10
	REG_DSI_HS_ZERO = 0x11
	REG_DSI_HS_TRAIL = 0x12
	REG_PKT_WR_DATA_RAW = 0x20
	REG_PKT_WR_DATA_U8 = 0x21

	def __init__(self, spi_frequency=15e6, dsi_frequency=84e6):
		# Params
		self.spi_frequency = spi_frequency
		self.dsi_frequency = dsi_frequency

		# SPI link
		self.spi = SpiController(cs_count=3)
		self.spi.configure('ftdi://ftdi:2232h/1')
		self.slave = self.spi.get_port(cs=2, freq=self.spi_frequency, mode=0)

		# Init LCD
		self.init()

	def reg_w16(self, reg, v):
		self.slave.exchange([reg, v >> 8, v & 0xff])

	def reg_w8(self, reg, v):
		self.slave.exchange([reg, v])

	def init(self):
		# Default values
		self.backlight = 0x100

		# Turn off Back Light / HS clock and assert reset
		self.reg_w16(self.REG_LCD_CTRL, 0x8000)

		# Wait a bit
		time.sleep(0.1)

		# Configure backlight and release reset
		self.reg_w16(self.REG_LCD_CTRL, self.backlight)

		# Configure DSI timings
		self.reg_w8(self.REG_DSI_HS_PREP,  0x10)
		self.reg_w8(self.REG_DSI_HS_ZERO,  0x18)
		self.reg_w8(self.REG_DSI_HS_TRAIL, 0x18)

		# Enable HS clock
		self.reg_w16(self.REG_LCD_CTRL, 0x4000 | self.backlight)

		# Wait a bit
		time.sleep(0.1)

		# Send DSI packets
		self.send_dsi_pkt(
			dcs_short_write(0x11) +			# Exist sleep
			dcs_short_write(0x29) +			# Display on
			dcs_short_write(0x36, 0x00) +	# Set address mode
			dcs_short_write(0x3a, 0x55) +	# Set pixel format
			EOTP							# EoTp
		)

	def send_dsi_pkt(self, data):
		# Write data
		self.slave.exchange([self.REG_PKT_WR_DATA_RAW] + data)

	def set_column_address(self, sc, ec):
		self.send_dsi_pkt(dcs_long_write(0x2a, [
			sc >> 8,
			sc & 0xff,
			ec >> 8,
			ec & 0xff,
		]))

	def set_page_address(self, sp, ep):
		self.send_dsi_pkt(dcs_long_write(0x2b, [
			sp >> 8,
			sp & 0xff,
			ep >> 8,
			ep & 0xff,
		]))

	def send_frame(self, frame, width=240, height=240):
		# Max packet size
		mtu = 1024 - 4 - 1 - 2
		psz = (mtu // (2 * width)) * (2 * width)
		pcnt = (width * height * 2 + psz - 1) // psz

		for i in range(pcnt):
			self.send_dsi_pkt(
				dsi_header([0x39, (psz + 1) & 0xff, (psz + 1) >> 8]) +
				[ 0x2C if i == 0 else 0x3C ] +
				frame[i*psz:(i+1)*psz] +
				[0x00, 0x00]
			)

	def send_frame8(self, frame, width=240, height=240):
		# Max packet size
		mtu = 1024 - 4 - 1 - 2
		psz = (mtu // (2 * width)) * (2 * width)
		pcnt = (width * height * 2 + psz - 1) // psz

		for i in range(pcnt):
			self.slave.exchange([self.REG_PKT_WR_DATA_U8] +
				dsi_header([0x39, (psz + 1) & 0xff, (psz + 1) >> 8]) +
				[ 0x2C if i == 0 else 0x3C ] +
				frame[i*(psz//2):(i+1)*(psz//2)] +
				[ 0x00 ]
			)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def nyan_load(filename='nyan-square.data'):
	img = open(filename,'rb').read()
	dat = []

	for i in range(len(img) // 4):
		b = img[4*i + 0]
		g = img[4*i + 1]
		r = img[4*i + 2]

		c  = ((r >> 3) & 0x1f) << 11;
		c |= ((g >> 2) & 0x3f) <<  5;
		c |= ((b >> 3) & 0x1f) <<  0;

		dat.append( ((c >> 0) & 0xff) )
		dat.append( ((c >> 8) & 0xff) )

	return dat


if __name__ == '__main__':
	ctrl = DSIControl(spi_frequency=10e6)
	data = nyan_load()
	ctrl.send_frame(data)

