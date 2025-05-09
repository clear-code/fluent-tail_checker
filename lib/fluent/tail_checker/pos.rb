# frozen_string_literal: true

# Copyright 2025 Daijiro Fukuda
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Fluent
  module TailChecker
    UNWATCHED_POSITION = 0xffffffffffffffff
    POSITION_FILE_ENTRY_REGEX = /^([^\t]+)\t([0-9a-fA-F]+)\t([0-9a-fA-F]+)/

    class PosFile
      attr_reader :entries

      def initialize(entries)
        @entries = entries
      end

      def self.load(path)
        PosFile.new(PosFile.load_entries(path))
      end

      def self.load_entries(path)
        entries = []

        File.open(path, File::RDONLY|File::BINARY) do |file|
          file.each_line do |line|
            m = POSITION_FILE_ENTRY_REGEX.match(line)
            next if m.nil?

            entries << PosEntry.new(
              m[1],
              m[2].to_i(16),
              m[3].to_i(16),
            )
          end
        end

        entries
      end

      def watching_entries
        entries.select do |entry|
          not entry.unwatched?
        end
      end
    end

    class PosEntry
      attr_reader :path, :pos, :ino

      def initialize(path, pos, ino)
        @path = path
        @pos = pos
        @ino = ino
      end

      def unwatched?
        @pos == UNWATCHED_POSITION
      end
    end
  end
end
