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

require "fluent/env"

# For compatibility with Fluentd v1.15.2 and earlier.
# See https://github.com/fluent/fluentd/pull/3883
begin
  require "fluent/file_wrapper"
rescue LoadError
  if Fluent.windows?
    require "fluent/plugin/file_wrapper"
  else
    Fluent::FileWrapper = File
  end
end

module Fluent
  module TailChecker
    class CollectionRatioChecker
      def initialize(posfile, follow_inodes, collection_ratio_threshold)
        @posfile = posfile
        @follow_inodes = follow_inodes
        @collection_ratio_threshold = collection_ratio_threshold
      end

      def check
        unacceptable_collection_ratio_found = false
        unacceptable_collection_ratio_path_and_ratio_list = []
        checked_file_counts = 0

        @posfile.watching_entries.each do |entry|
          size = get_file_size(entry)
          next if size.nil?

          checked_file_counts += 1
          ratio = collection_ratio(entry.pos, size)
          if ratio < @collection_ratio_threshold
            unacceptable_collection_ratio_found = true
            unacceptable_collection_ratio_path_and_ratio_list.push([entry.path, ratio])
          end
        end

        puts "Done collection ratio check for #{checked_file_counts} files."

        if unacceptable_collection_ratio_found
          log_issue(unacceptable_collection_ratio_path_and_ratio_list)
          return false
        end

        true
      end

      def get_file_size(pos_entry)
        if @follow_inodes
          get_file_size_from_inode(pos_entry)
        else
          get_file_size_from_path(pos_entry)
        end
      end

      def get_file_size_from_path(pos_entry)
        size = FileTest.size?(pos_entry.path)
        unless size
          $stderr.puts "Skip #{pos_entry.path} because it is not found. Make sure you have the proper privilege, e.g. 'sudo'."
        end
        size
      end

      def get_file_size_from_inode(pos_entry)
        unless FileTest.exist?(pos_entry.path)
          $stderr.puts "Skip #{pos_entry.path} because it is not found. Make sure you have the proper privilege, e.g. 'sudo'."
          return nil
        end

        stat = Fluent::FileWrapper.stat(pos_entry.path)
        # If follow_inodes is enabled, the inode of the current logfile should match the inode in the pos_file.
        # It may not match for the rotated logfiles because the path info in the pos_file is not updated.
        # So, at least, check the current logfile.
        # For rotated logfiles, check them if inode matches.
        return nil unless stat.ino == pos_entry.ino

        stat.size
      end

      def collection_ratio(pos, file_size)
        return 1.0 if file_size == 0

        pos.to_f / file_size
      end

      def log_issue(path_and_ratio_list)
        if @follow_inodes
          puts "Collection ratio of some files are too low. Collection of those files may not be keeping up. Or it may have stopped with some anomalies. This can be a known log missing issue of the follow_inodes feature that was fixed in Fluentd v1.16.2 (fluent-package v5.0.0, td-agent v4.5.1). If you are using any version older than these, updating Fluentd will resolve the issue."
        else
          puts "Collection ratio of some files are too low. Collection of those files may not be keeping up. Or it may have stopped with some anomalies. It is recommended to verify whether there is any log missing."
        end

        puts "Filepaths with too low collection ratio (threshold: #{@collection_ratio_threshold}):"
        path_and_ratio_list.each do |path, ratio|
          puts "  #{path} (ratio: #{ratio})"
        end
      end
    end
  end
end
