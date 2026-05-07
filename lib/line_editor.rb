module AI
  # ── Mini line editor with history + Tab completion (with cycling) ────
  class LineEditor
    attr_accessor :history, :completer

    SIGNALS = {
      "\ej"     => :sess_next,
      "\ek"     => :sess_prev,
      "\el"     => :redraw,  "\eL" => :redraw,
      "\e[3;7~" => :del_session, "\e\e[3;5~" => :del_session,
      "\e[3;5~" => :del_session, "\e\e[3^"   => :del_session,
      "\e[3^"   => :del_session, "\e[3;8~"   => :del_session
    }.freeze

    def initialize; @history = []; @completer = nil; end

    def readline(prompt)
      @prompt = prompt; @buf = +""; @cur = 0
      @hpos = @history.length; @stash = nil
      @prev_rows = 0; @prev_cur_row = 0
      @cycle = nil
      render
      $stdin.raw do |io|
        loop do
          k = read_key(io) or next
          if (sig = SIGNALS[k]) then return signal(sig) end
          @cycle = nil unless k == "\t"
          case k
          when "\r", "\n" then return submit
          when "\t"       then handle_tab
          when "\x03" then end_render; print "\r\n"; raise Interrupt
          when "\e[3~"
            @buf.slice!(@cur); render if @cur < @buf.length
          when "\x02", "\e[D" then move(-1)
          when "\x06", "\e[C" then move(+1)
          when "\x01", "\e[H", "\eOH", "\e[1~" then @cur = 0; render
          when "\x05", "\e[F", "\eOF", "\e[4~" then @cur = @buf.length; render
          when "\eb"  then @cur = word_back; render
          when "\ef"  then @cur = word_fwd;  render
          when "\x10", "\e[A" then history_step(-1)
          when "\x0e", "\e[B" then history_step(+1)
          when "\x7f", "\b", "\x08"
            (@buf.slice!(@cur - 1); @cur -= 1; render) if @cur > 0
          when "\x04"
            if @buf.empty? then end_render; print "\r\n"; return nil
            elsif @cur < @buf.length then @buf.slice!(@cur); render
            end
          when "\x0b" then @buf.slice!(@cur..);  render
          when "\x15" then @buf.slice!(0...@cur); @cur = 0; render
          when "\x17"
            j = word_back; @buf.slice!(j...@cur); @cur = j; render
          when "\ed"
            j = word_fwd;  @buf.slice!(@cur...j); render
          when "\eu" then case_word(:upcase);   render
          when "\eU" then case_word(:downcase); render
          when "\x14" then transpose; render
          when "\x0c" then print "\e[H\e[2J"; @prev_rows = 0; @prev_cur_row = 0; render
          when "\e"   then nil
          else insert(k) if printable?(k)
          end
        end
      end
    end

    private

    def signal(s); clear_render; s; end

    def submit
      end_render
      print "\r\n"
      @history << @buf.dup unless @buf.empty? || @buf == @history.last
      @buf
    end

    def end_render
      down = @prev_rows - 1 - @prev_cur_row
      print "\e[#{down}B" if down > 0
      print "\r"
    end

    def clear_render
      print "\e[#{@prev_cur_row}A" if @prev_cur_row > 0
      print "\r\e[J"
      @prev_rows = 0; @prev_cur_row = 0
    end

    def printable?(k) = !k.start_with?("\e") && k.ord >= 32

    def insert(k);  @buf.insert(@cur, k); @cur += k.length; render; end

    def move(d)
      nc = @cur + d
      (@cur = nc; render) if nc.between?(0, @buf.length)
    end

    def handle_tab
      if @cycle
        @cycle[:index] = (@cycle[:index] + 1) % @cycle[:matches].length
        apply_cycle
        return
      end

      return unless @completer
      prefix = @buf[0...@cur]
      result = @completer.call(prefix) or return
      matches, start = result[:matches], result[:start]
      return if matches.nil? || matches.empty?

      if matches.length == 1
        replace_arg(start, matches[0])
        return
      end

      common = matches.reduce do |a, b|
        i = 0
        i += 1 while i < a.length && i < b.length && a[i] == b[i]
        a[0...i]
      end
      current = prefix[start..]

      if common.length > current.length
        replace_arg(start, common)
      else
        @cycle = { matches: matches, start: start, suffix: @buf[@cur..] || "", index: 0 }
        apply_cycle
      end
    end

    def replace_arg(start, text)
      prefix = @buf[0...@cur]
      @buf = prefix[0...start] + text + (@buf[@cur..] || "")
      @cur = start + text.length
      render
    end

    def apply_cycle
      c = @cycle
      match = c[:matches][c[:index]]
      @buf = @buf[0...c[:start]] + match + c[:suffix]
      @cur = c[:start] + match.length
      render
    end

    def read_key(io)
      b = io.getbyte or return nil
      return read_escape(io) if b == 27
      return b.chr if b < 128
      n = b < 224 ? 2 : b < 240 ? 3 : 4
      bytes = [b]
      (n - 1).times { bytes << (io.getbyte || 0) }
      bytes.pack("C*").force_encoding("UTF-8")
    end

    def read_escape(io)
      return "\e" unless IO.select([io], nil, nil, 0.05)
      c = io.getbyte or return "\e"
      case c
      when 91 then read_csi(io, +"\e[")
      when 79 then "\eO#{(io.getbyte || 0).chr}"
      when 27
        return "\e\e" unless IO.select([io], nil, nil, 0.05)
        c2 = io.getbyte or return "\e\e"
        c2 == 91 ? read_csi(io, +"\e\e[") : "\e\e#{c2.chr}"
      else "\e#{c.chr}"
      end
    end

    def read_csi(io, buf)
      12.times do
        nb = io.getbyte or break
        buf << nb.chr
        break if nb.between?(64, 126)
      end
      buf
    end

    def render
      cols = (IO.console&.winsize&.last || 80)
      cols = 1 if cols < 1
      print "\e[#{@prev_cur_row}A" if @prev_cur_row > 0
      print "\r\e[J"
      print "#{@prompt}#{@buf}"

      prompt_w = Ansi.width(@prompt)
      total_w  = prompt_w + Ansi.width(@buf)
      cur_w    = prompt_w + Ansi.width(@buf[0...@cur] || "")
      total_rows = total_w.zero? ? 1 : ((total_w - 1) / cols) + 1
      end_row    = total_rows - 1
      cur_row = cur_w / cols
      cur_col = cur_w % cols
      if cur_w.positive? && cur_w == total_w && cur_w % cols == 0
        cur_row -= 1; cur_col = cols
      end

      print "\r"
      up = end_row - cur_row
      print "\e[#{up}A"      if up > 0
      print "\e[#{cur_col}C" if cur_col > 0
      @prev_rows    = total_rows
      @prev_cur_row = cur_row
    end

    def history_step(d)
      return if @history.empty?
      @stash = @buf.dup if @hpos == @history.length
      np = (@hpos + d).clamp(0, @history.length)
      return if np == @hpos
      @hpos = np
      @buf = (@hpos == @history.length ? (@stash || +"") : @history[@hpos]).dup
      @cur = @buf.length; render
    end

    def word_fwd
      j = @cur
      j += 1 while j < @buf.length && @buf[j] !~ /\w/
      j += 1 while j < @buf.length && @buf[j] =~ /\w/
      j
    end

    def word_back
      j = @cur
      j -= 1 while j > 0 && @buf[j - 1] !~ /\w/
      j -= 1 while j > 0 && @buf[j - 1] =~ /\w/
      j
    end

    def case_word(method)
      j = word_fwd
      return if j == @cur
      @buf[@cur...j] = @buf[@cur...j].public_send(method)
      @cur = j
    end

    def transpose
      return if @buf.length < 2 || @cur == 0
      p = @cur >= @buf.length ? @cur - 1 : @cur
      @buf[p - 1], @buf[p] = @buf[p], @buf[p - 1]
      @cur = [p + 1, @buf.length].min
    end
  end
end
