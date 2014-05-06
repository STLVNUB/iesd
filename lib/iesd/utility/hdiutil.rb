require "shellwords"
require "tmpdir"
require_relative "tty"

module HDIUtil
  DEFAULT_MOUNT_OPTIONS = %w{ -nobrowse -quiet -noverify }
  DEFAULT_MOUNT_OPTIONS.concat(%w{ -owners on }) if Process.uid == 0
  DEFAULT_UNMOUNT_OPTIONS = %w{ -quiet }
  DEFAULT_CONVERT_OPTIONS = %w{ -quiet }

  def self.read input
    Dir.mktmpdir { |mountpoint|
      attach input, mountpoint, [*DEFAULT_MOUNT_OPTIONS]
      if block_given?
        yield mountpoint
      else
        shell mountpoint
      end
      detach input, mountpoint, [*DEFAULT_UNMOUNT_OPTIONS]
    }
  end

  def self.write input, output, options = {}
    options = {
      :resize => {
        :grow => 0,
        :shrink => false
      }
    }.merge(options)

    Dir.mktmpdir { |tmp|
      shadow = File.join(tmp, "#{File.basename input}.shadow")
      shadow_options = ["-shadow", shadow]
      format_options = ["-format", `/usr/bin/env hdiutil imageinfo -format #{input.shellescape}`.chomp]
      Dir.mktmpdir(nil, tmp) { |mountpoint|
        resize_limits = `/usr/bin/env hdiutil resize -limits -shadow #{shadow.shellescape} #{input.shellescape}`.chomp.split.map { |s| s.to_i }
        sectors = (resize_limits[1] + options[:resize][:grow]).to_s
        system("/usr/bin/env", "hdiutil", "resize", "-growonly", "-sectors", sectors, *shadow_options, input)
        attach input, mountpoint, [*DEFAULT_MOUNT_OPTIONS, *shadow_options]
        if block_given?
          yield mountpoint
        else
          shell mountpoint
        end
        detach input, mountpoint, [*DEFAULT_UNMOUNT_OPTIONS]
        system("/usr/bin/env", "hdiutil", "resize", "-shrinkonly", "-sectors", "min", *shadow_options, input) if options[:resize][:shrink]
      }
      oh1 "Merging #{shadow}"
      system("/usr/bin/env", "hdiutil", "convert", *DEFAULT_CONVERT_OPTIONS, *format_options, *shadow_options, "-o", output, input)
      puts "Merged: #{output}"
    }
  end

  def self.validate input
    Kernel.system(%Q{/usr/bin/env hdiutil imageinfo #{input.shellescape} >/dev/null 2>&1})
  end

  private

  def self.attach dmg, mountpoint, arguments = []
    ohai "Mounting #{dmg}"
    system("/usr/bin/env", "hdiutil", "attach", *arguments, "-mountpoint", mountpoint, dmg)
    puts "Mounted: #{mountpoint}"
  end

  def self.detach dmg, mountpoint, arguments = []
    ohai "Unmounting #{dmg}"
    system("/usr/bin/env", "hdiutil", "detach", *arguments, mountpoint)
    puts "Unmounted: #{mountpoint}"
  end

  def self.shell dir
    Dir.chdir(dir) {
      ohai ENV['SHELL']
      Kernel.system ENV, ENV['SHELL']
    }
  end
end

module HDIUtil
  class DMG
    attr_accessor :url

    def initialize url
      @url = File.absolute_path url
    end

    def show &block
      HDIUtil.read(@url, &block)
    end

    def edit
      update
    end

    def update &block
      Dir.mktmpdir { |tmp|
        flags = `/usr/bin/env ls -lO #{@url.shellescape}`.split[4]
        HDIUtil.write(@url, (tmpfile = File.join(tmp, File.basename(@url))), &block)
        system("/usr/bin/env", "mv", tmpfile, @url)
        system("/usr/bin/env", "chflags", flags, @url) unless flags == "-"
      }
    end

    def valid?
      HDIUtil.validate @url
    end
  end
end
