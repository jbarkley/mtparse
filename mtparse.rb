#!/usr/bin/ruby 

require 'nokogiri'


USAGE = <<ENDUSAGE
Usage:
   mt-parse.rb [-h] [-v] [filename]
ENDUSAGE

HELP = <<ENDHELP
   -h, --help       Show this help.
#   -v, --version    Show the version number (#{DocuBot::VERSION}).
ENDHELP

ARGS = { :shell=>'default', :writer=>'chm' } # Setting default values
UNFLAGGED_ARGS = [ :directory ]              # Bare arguments (no flag)
next_arg = UNFLAGGED_ARGS.first
ARGV.each do |arg|
  case arg
    when '-h','--help'      then ARGS[:help]      = true
    when '-v','--version'   then ARGS[:version]   = true
    else
      if next_arg
        ARGS[next_arg] = arg
        UNFLAGGED_ARGS.delete( next_arg )
      end
      next_arg = UNFLAGGED_ARGS.first
  end
end

puts "DocuBot v#{DocuBot::VERSION}" if ARGS[:version]

if ARGS[:help] or !ARGS[:directory]
  puts USAGE unless ARGS[:version]
  puts HELP if ARGS[:help]
  exit
end

if ARGS[:logfile]
  $stdout.reopen( ARGS[:logfile], "w" )
  $stdout.sync = true
  $stderr.reopen( $stdout )
end



f = File.open("data/sample2.xml")
doc = Nokogiri::XML(f)
f.close

puts doc.class 

doc.xpath('//DataItem').each do |node|
    puts node
end

