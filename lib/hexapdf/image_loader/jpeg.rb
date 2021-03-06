# -*- encoding: utf-8 -*-
#
#--
# This file is part of HexaPDF.
#
# HexaPDF - A Versatile PDF Creation and Manipulation Library For Ruby
# Copyright (C) 2014-2017 Thomas Leitner
#
# HexaPDF is free software: you can redistribute it and/or modify it
# under the terms of the GNU Affero General Public License version 3 as
# published by the Free Software Foundation with the addition of the
# following permission added to Section 15 as permitted in Section 7(a):
# FOR ANY PART OF THE COVERED WORK IN WHICH THE COPYRIGHT IS OWNED BY
# THOMAS LEITNER, THOMAS LEITNER DISCLAIMS THE WARRANTY OF NON
# INFRINGEMENT OF THIRD PARTY RIGHTS.
#
# HexaPDF is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public
# License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with HexaPDF. If not, see <http://www.gnu.org/licenses/>.
#
# The interactive user interfaces in modified source and object code
# versions of HexaPDF must display Appropriate Legal Notices, as required
# under Section 5 of the GNU Affero General Public License version 3.
#
# In accordance with Section 7(b) of the GNU Affero General Public
# License, a covered work must retain the producer line in every PDF that
# is created or manipulated using HexaPDF.
#++

require 'hexapdf/error'

module HexaPDF
  module ImageLoader

    # This module is used for loading images in the JPEG format from files or IO streams.
    #
    # See: PDF1.7 s7.4.8, ITU T.81 Annex B
    module JPEG

      # The magic marker that tells us if the file/IO contains an image in JPEG format.
      MAGIC_FILE_MARKER = "\xFF\xD8\xFF".b

      # The various start-of-frame markers that tell us which kind of JPEG it is. The marker
      # segment itself contains all the needed information needed for creating the PDF image
      # object.
      #
      # See: ITU T.81 B1.1.3
      SOF_MARKERS = [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF].freeze

      # Adobe uses the marker 0xEE (APPE) for its purposes. We need to use it for determinig
      # whether to invert the colors for CMYK/YCCK images or not (Adobe does this...).
      #
      # The marker also let's us distinguish between YCCK and CMYK images. However, we don't
      # actually need this information (and we don't need to set the /ColorTransform value)
      # because if the image has this information it is automically used.
      ADOBE_MARKER = 0xEE

      # End-of-image marker
      EOI_MARKER = 0xD9

      # Start-of-scan marker
      SOS_MARKER = 0xDA

      # :call-seq:
      #   JPEG.handles?(filename)     -> true or false
      #   JPGE.handles?(io)           -> true or false
      #
      # Returns +true+ if the given file or IO stream can be handled, ie. if it contains an image
      # in JPEG format.
      def self.handles?(file_or_io)
        if file_or_io.kind_of?(String)
          File.read(file_or_io, 3, mode: 'rb') == MAGIC_FILE_MARKER
        else
          file_or_io.rewind
          file_or_io.read(3) == MAGIC_FILE_MARKER
        end
      end

      # :call-seq:
      #   JPEG.load(document, filename)    -> image_obj
      #   JPEG.load(document, io)          -> image_obj
      #
      # Creates a PDF image object from the JPEG file or IO stream.
      def self.load(document, file_or_io)
        dict = if file_or_io.kind_of?(String)
                 File.open(file_or_io, 'rb') {|io| image_data_from_io(io)}
               else
                 image_data_from_io(file_or_io)
               end
        document.add(dict, stream: HexaPDF::StreamData.new(file_or_io))
      end

      # Returns a hash containing the extracted JPEG image data.
      def self.image_data_from_io(io)
        io.seek(2, IO::SEEK_SET)

        while true
          code0 = io.getbyte
          code1 = io.getbyte

          # B1.1.2 - all markers start with 0xFF
          if code0 != 0xFF
            raise HexaPDF::Error, "Invalid bytes found, expected marker code"
          end

          # B1.1.2 - markers may be preceeded by any number of 0xFF fill bytes
          code1 = io.getbyte while code1 == 0xFF

          break if code1 == SOS_MARKER || code1 == EOI_MARKER

          # B1.1.4 - next two bytes are the length of the segment (except for RSTm or TEM markers
          # but those shouldn't appear here)
          length = io.read(2).unpack('n').first

          if code1 == ADOBE_MARKER # Adobe apps invert the colors when using CMYK color space
            invert_colors = true
            io.seek(length - 2, IO::SEEK_CUR)
            next
          elsif !SOF_MARKERS.include?(code1)
            io.seek(length - 2, IO::SEEK_CUR)
            next
          end

          bits, height, width, components = io.read(6).unpack('CnnC')
          io.seek(length - 2 - 6, IO::SEEK_CUR)

          # short-cut loop if we have all needed information
          break if components != 4 || invert_colors
        end

        # PDF1.7 s8.9.5.1
        if bits != 8
          raise HexaPDF::Error, "Unsupported number of bits per component: #{bits}"
        end

        color_space = case components
                      when 1 then :DeviceGray
                      when 3 then :DeviceRGB
                      when 4 then :DeviceCMYK
                      end

        dict = {
          Type: :XObject,
          Subtype: :Image,
          Width: width,
          Height: height,
          ColorSpace: color_space,
          BitsPerComponent: bits,
          Filter: :DCTDecode,
        }
        if invert_colors && color_space == :DeviceCMYK
          dict[:Decode] = [1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0]
        end

        dict
      end
      private_class_method :image_data_from_io

    end

  end
end
