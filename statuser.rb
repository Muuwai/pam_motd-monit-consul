#!/usr/bin/env ruby
# Encoding: utf-8

require 'colorize'
require 'oj'
require 'open3'

class Statuser
  MAX_WIDTH           = 80
  SINGLE_COLUMN_WIDTH = (MAX_WIDTH / 2 ) - 3
  MAX_WORD_LENGTH     = 26
  CHECK_MARK          = '✓'
  X_MARK              = '✗'
  WARNING_MARK        = '⚠'
  SPACER              = '·'
  TRUNCATOR           = '…'
  GOOD_COLOR          = :green
  GOOD_BACKGROUND     = :default
  WARNING_COLOR       = :yellow
  WARNING_BACKGROUND  = :default
  BAD_COLOR           = :black
  BAD_BACKGROUND      = :red

  class << self
    def system_status
      columns = []

      # Basics
      columns << format_to_column('Time', :good, Time.now.strftime('%d %b %y %H:%M:%S %Z'))
      columns << format_to_column('Uptime', :good, `uptime`.chomp.split('up ').last.split(',  ').first)
      columns << format_to_column('Release', :good, `lsb_release -s -d`)
      columns << format_to_column('Kernel', :good, `uname -r`)
      columns << format_to_column('Environment', :good, 'develop')

      # Load average
      load = `cat /proc/loadavg`.chomp.to_f
      status = load <= 0.8 ? :good : (load <= 0.95 ? :warning : :bad)
      columns << format_to_column('Load (1 min)', status, load)

      # Free space stats
      space = `df -h /`.split("\n").collect {|l| l.split(/\s+/) }

      root = space.find {|l| l.last == '/' }
      if root
        root_use = root[4]
        status = root_use.to_i <= 80 ? :good : (root_use.to_i <= 95 ? :warning : :bad)
        columns << format_to_column('Usage of /', status, root_use)
      end

      mnt = space.find {|l| l.last == '/mnt'}
      if mnt
        mnt_use = mnt[4]
        status = mnt_use.to_i <= 80 ? :good : (mnt_use.to_i <= 95 ? :warning : :bad)
        columns << format_to_column('Usage of /mnt', status, mnt_use)
      end

      # Memory stats
      memory = `free -m`.split("\n").collect {|l| l.split(/\s+/) }

      ram_usage = ((memory[1][2].to_f / memory[1][1].to_f) * 100).round(1).to_s + '%'
      status = ram_usage.to_i <= 80 ? :good : (ram_usage.to_i <= 95 ? :warning : :bad)
      columns << format_to_column('Memory usage', status, ram_usage)

      swap = memory[3][2] == '0' ? nil : ((memory[3][2].to_f / memory[3][1].to_f) * 100).round(1).to_s + '%'
      if swap
        status = swap.to_i <= 80 ? :good : (memory.to_i <= 95 ? :warning : :bad)
        columns << format_to_column('Swap usage', status, swap)
      end

      # User stats
      columns << format_to_column('Users', :good, `users | wc -w`)

      columns = columns.flatten.uniq

      puts "System Info".white.bold.underline
      columns.each_slice(2) {|c| puts combine_columns(c[0], c[1])}
      puts ""
    end

    def monit_status
      input, output, error, exit_status = Open3.popen3('monit summary')
      output = output.read

      raise 'Could not contact monit!' unless output =~ /uptime/

      columns = []

      summary = output.chomp.split("\n").collect {|l| l.split(/'\s+/) }
      summary[2..-1].each do |line|
        next if line[0] =~ /System/

        name = line[0].split("'").last
        status = line[1]
        status = 'Online' if status =~ /Online/
        color = if status == 'Online' || status == 'Running'
          :good
        else
          :bad
        end

        columns << format_to_column(name, color)
      end

      puts "Monit Summary".white.bold.underline
      columns.each_slice(2) {|c| puts combine_columns(c[0], c[1])}
      puts ""
    rescue Exception => e
      puts "Monit error: #{e}".red.underline
      puts ""
    end

    def consul_status
      input, output, error, exit_status = Open3.popen3('curl http://localhost:8500/v1/agent/checks')

      raise 'Could not contact consul!' unless exit_status.value.success?

      columns = []

      summary = Oj.load(output.read)
      summary.each do |name, hash|
        status = hash['Status']

        color = if status == 'passing'
          :good
        elsif status == 'warning'
          :warning
        else
          :bad
        end

        columns << format_to_column(name.split(':')[1..-1].join(':'), color)
      end

      puts "Consul Checks".white.bold.underline
      columns.each_slice(2) {|c| puts combine_columns(c[0], c[1])}
      puts ""
    rescue Exception => e
      puts "Consul error: #{e}".red.underline
      puts ""
    end

    private

    def combine_columns(left, right)
      return left unless right
      "#{left} | #{right}"
    end

    def format_to_column(left, status = :good, right = nil)
      return nil unless left

      right ||= case status
      when :good
        CHECK_MARK
      when :warning
        WARNING_MARK
      when :bad
        X_MARK
      end

      left = truncate(left, MAX_WORD_LENGTH)
      right = truncate(right, MAX_WORD_LENGTH)

      spacers = SINGLE_COLUMN_WIDTH - (left.size + right.size) - 1
      spacers = 1 if spacers <= 0

      "#{left} #{SPACER * spacers} #{right.colorize(
        color: Statuser.const_get(status.to_s.upcase + '_COLOR'),
        background: Statuser.const_get(status.to_s.upcase + '_BACKGROUND')
      )}"
    end

    def truncate(string, length)
      string = string.to_s.gsub("\n", "")

      return string if string.length <= length
      "#{string[0..(length - 1)]}#{TRUNCATOR}"
    end
  end

end

Statuser.system_status
Statuser.monit_status
Statuser.consul_status
