#!/usr/bin/env python3

import math
import time

from pyftdi.spi import SpiController


class PanelControl(object):

	def __init__(self, spi_frequency=5e6):
		# Params
		self.spi_frequency = spi_frequency

		# SPI link
		self.spi = SpiController(cs_count=3)
		self.spi.configure('ftdi://ftdi:2232h/1')
		self.slave = self.spi.get_port(cs=2, freq=self.spi_frequency, mode=0)

	def reg_w16(self, reg, v):
		self.slave.exchange([reg, v >> 8, v & 0xff])

	def reg_w8(self, reg, v):
		self.slave.exchange([reg, v])

	def read_status(self):
		rv = self.slave.exchange([0x00, 0x00], duplex=True)
		return rv[0] | rv[1]

	def send_data(self, data):
		self.slave.exchange([0x80] + data)

	def send_frame(self, frame, width=64, height=64, bits=16):
		# Size of a line
		ll = width * bits // 8

		# Scan all line
		for y in range(height):
			# Send write command to line buffer
			self.send_data(list(frame[y*ll:(y+1)*ll]))

			# Swap line buffer & Write it to line y of back frame buffer
			self.reg_w8(0x03, y)

		# Send frame swap command
		panel.reg_w8(0x04, 0x00)

		# Wait for the frame swap to occur
		while (panel.read_status() & 0x02 == 0):
			pass


panel = PanelControl(spi_frequency=5e6)


# Example loading a single frame
def nyan_load(filename='nyan_glitch_64x64x16.raw'):
	img = open(filename,'rb').read()
	return img[0:8192]

data = nyan_load()
panel.send_frame(data)


# Example of streaming video
fps = 25
tpf = 1.0 / fps
tt = time.time() + tpf

fh = open('video.raw', 'rb')
while True:
	# Read and send one frame
	d = fh.read(8192)
	if len(d) < 8192:
		break
	panel.send_frame(d)

	# Delay to match the FPS
	w = tt - time.time()
	if w > 0:
		time.sleep(w)
	tt += tpf
