# -*- encoding: utf-8 -*-

require 'fiber'
require 'zlib'
require 'hexapdf/filter/predictor'
require 'hexapdf/configuration'
require 'hexapdf/error'

module HexaPDF
  module Filter

    # Implements the Deflate filter using the Zlib library.
    #
    # See: HexaPDF::Filter, PDF1.7 s7.4.4
    module FlateDecode

      # See HexaPDF::Filter
      def self.decoder(source, options = nil)
        fib = Fiber.new do
          inflater = Zlib::Inflate.new
          while source.alive? && (data = source.resume)
            begin
              data = inflater.inflate(data)
            rescue
              raise FilterError, "Problem while decoding Flate encoded stream: #{$!}"
            end
            Fiber.yield(data)
          end
          begin
            inflater.finish
          rescue
            raise FilterError, "Problem while decoding Flate encoded stream: #{$!}"
          end
        end

        if options && options[:Predictor]
          Predictor.decoder(fib, options)
        else
          fib
        end
      end

      # See HexaPDF::Filter
      def self.encoder(source, options = nil)
        if options && options[:Predictor]
          source = Predictor.encoder(source, options)
        end

        Fiber.new do
          deflater = Zlib::Deflate.new(HexaPDF::GlobalConfiguration['filter.flate_compression'])
          while source.alive? && (data = source.resume)
            data = deflater.deflate(data)
            Fiber.yield(data)
          end
          deflater.finish
        end
      end

    end

  end
end
