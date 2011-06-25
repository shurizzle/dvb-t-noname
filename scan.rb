require 'rbconfig'

# Extensions {{{
class Dir # {{{
  def self.path
    (((ENV.key?('PATH') and ENV['PATH'] and !ENV['PATH'].empty?) ? ENV['PATH'] : nil) ||
     ['/bin', '/usr/bin', '/sbin', '/usr/sbin', '/usr/local/bin'].join(RbConfig::CONFIG['PATH_SEPARATOR'])
    ).split(RbConfig::CONFIG['PATH_SEPARATOR'])
  end
end # }}}

module Kernel # {{{
  def self.which (bin, which=0)
    res = Dir.path.map {|path|
      File.join(path, bin)
    }.select {|bin|
      File.executable_real?(bin)
    }

    if which == :all
      res
    elsif which.is_a?(Integer)
      res[which]
    else
      res[0]
    end
  end

  def die (message=nil)
    $stderr.puts message if message
    exit 1
  end
end # }}}
# }}}

class CLI
  def self.confirm? (query, default=true)
    $stdout.print "#{query} [#{default ? 'YES/no' : 'yes/NO'}] "

    case $stdin.gets.strip
      when /^(true|y(es)?|1)$/i then true
      when /^(false|no?|0)$/i then false
      else !!default
    end
  end

  def self.choice (list=nil, default=nil, query='The choice is yours')
    array = if list.is_a?(Array)
      list = Hash[list.each_with_index.map {|v, i|
        [i + 1, v]
      }]

      true
    else
      false
    end

    if list.is_a?(Hash)
      list = Hash[list.map {|i, v| [i.to_s, v] }]
    else
      return nil
    end

    max = list.keys.map {|x|
      x.to_s.size
    }.max

    list.each {|index, value|
      $stdout.puts " #{index.rjust(max)}: #{value}"
    }
    $stdout.print "#{query || "Choice"}#{" [#{list[(array ? default + 1 : default).to_s]}]" if default}: "

    choice = $stdin.gets.strip

    if list.keys.grep(/^#{Regexp.escape(choice)}$/i)
      array ? choice.to_i - 1 : choice
    else
      if default
        default
      else
        nil
      end
    end
  end
end

class Bin
  W_SCAN_BIN = Kernel.which('w_scan')
  DVBSCAN_BIN = Kernel.which('dvbscan') || Kernel.which('scan')

  def self.w_scan (*args)
    Kernel.die('Install w_scan bin') unless W_SCAN_BIN

    options, args = args.group_by {|x|
      x.is_a?(Hash)
    }.tap {|a|
      break [a[true] || {}, a[false] || []]
    }
    options = options.inject(:merge) if options.is_a?(Array)

    options[STDOUT] = [File.join(Dir.home, 'scan.dvb'), 'a'] unless \
        options.key?(STDOUT) or options.key?(:out) or options.key?(1)

    Kernel.system(W_SCAN_BIN, *args, options)
  end

  def self.dvbscan (*args)
    Kernel.die('Install dvbscan or scan bin') unless DVBSCAN_BIN

    options, args = args.group_by {|x|
      x.is_a?(Hash)
    }.tap {|a|
      break [a[true] || {}, a[false] || []]
    }

    File.join(Dir.home, '.mplayer').tap {|mplayer|
      File.unlink(mplayer) if File.file?(mplayer)
      Dir.mkdir(mplayer) unless File.directory?(mplayer)

      options[STDOUT] = [File.join(mplayer, 'channels.conf'), 'a'] unless \
        options.key?(STDOUT) or options.key?(:out) or options.key?(1)
    }

    Kernel.system(DVBSCAN_BIN, *args, options)
  end
end

class Device
  def self.get
    Kernel.die('There is no /dev/dvb') unless File.directory?('/dev/dvb')
    Kernel.die('There are no devices in /dev/dvb') if (devs = Dir['/dev/dvb/*']).empty?

    devs.map {|dev|
      File.basename(dev)
    }
  end
end

class CLI
  def self.choose_adapter
    devs = Device.get
    choice = devs.size == 1 ? 0 : CLI.choice(devs + ['AUTO'], devs.size, 'Choose adapter')

    choice = "/dev/dvb/#{choice == devs.size ? devs.first : devs[choice]}"

    Kernel.die("`#{choice}' doesn't exist") unless File.exists?(choice)

    choice
  end

  def self.choose_country
    r, w = IO.pipe
    Bin.w_scan('-c', '?', STDOUT => w)
    w.close

    countries = Hash[r.read.split(/\r?\n/).map {|line|
      line.strip.split(/\s+/, 2)
    }]

    r.close

    CLI.choice(countries, nil, 'Choose country').tap {|choice|
      Kernel.die("Country not valid") unless (choice)
    }
  end
end


adapter = CLI.choose_adapter.match(/\d+$/)[0]
country = CLI.choose_country
atsc = CLI.confirm?('Do you want to scan ATSC Cable too?', false) ? ['-A', '3', '-o', '7'] : []

Bin.w_scan('-x', '-c', country, '-a', adapter, '-O', '1', '-t', '3', *atsc)
Bin.dvbscan('-a', adapter, File.join(Dir.home, 'scan.dvb'))
