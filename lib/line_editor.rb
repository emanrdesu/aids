module AI
  # ── Mini line editor with history + Tab completion ───────────────────
  class LineEditor
    attr_accessor :history, :completer

    SIGNALS = {
      "\ej" => :sess_next,
      "\ek" => :sess_prev,
      "\el" => :redraw, "\eL" => :redraw,
      "\e[3;7~" => :del_session, "\e\e[3;5~" => :del_session,
      "\e[3;5~" => :del_session, "\e\e[3^" => :del_session,
      "\e[3^" => :del_session, "\e[3;8~" => :del_session,
    }.freeze

    PASTE_STYLE = "\e[48;5;18;38;5;231m"
    BPASTE_ON = "\e[?2004h"
    BPASTE_OFF = "\e[?2004l"

    def initialize; @history = []; @completer = nil; end

    def readline(prompt)
      @prompt = prompt.to_s; @buf = +""; @cur = 0
      @hpos = @history.length; @stash = nil
      @prev_rows = 1; @prev_cur_row = 0
      @cycle = nil
      @pastes = []
      print BPASTE_ON
      render
      begin
        $stdin.raw do |io|
          loop do
            k = read_key(io) or next
            if (sig = SIGNALS[k]) then return signal(sig) end
            @cycle = nil unless k == "\t"
            case k
            when "\e[200~" then collect_paste(io)
            when "\r", "\n" then insert("\n")
            when "\e\r", "\e\n" then return submit
            when "\t" then handle_tab
            when "\x03" then end_render; print "\r\n"; raise Interrupt
            when "\e[3~" then forward_delete
            when "\x02", "\e[D" then move(-1)
            when "\x06", "\e[C" then move(+1)
            when "\x01", "\e[H", "\eOH", "\e[1~" then @cur = 0; render
            when "\x05", "\e[F", "\eOF", "\e[4~" then @cur = @buf.length; render
            when "\eb" then @cur = word_back; render
            when "\ef" then @cur = word_fwd; render
            when "\x10", "\e[A" then history_step(-1)
            when "\x0e", "\e[B" then history_step(+1)
            when "\x7f", "\b", "\x08" then backspace
            when "\x04"
              if @buf.empty? then end_render; print "\r\n"; return nil else forward_delete end
            when "\x0b" then del_range(@cur, @buf.length); render
            when "\x15" then del_range(0, @cur); render
            when "\x17" then j = word_back; del_range(j, @cur); render
            when "\ed" then j = word_fwd; del_range(@cur, j); render
            when "\eu" then case_word(:upcase); render
            when "\eU" then case_word(:downcase); render
            when "\x14" then transpose; render
            when "\x0c" then print "\e[H\e[2J"; @prev_rows = 0; @prev_cur_row = 0; render
            when "\e" then nil
            else insert(k) if printable?(k)
            end
          end
        end
      ensure
        print BPASTE_OFF
      end
    end

    private

    def signal(s); clear_render; s; end

    def submit
      end_render
      print "\r\n"
      out = @buf.dup
      @history << out unless out.empty? || out == @history.last
      out
    end

    def end_render
      down = (@prev_rows - 1) - @prev_cur_row
      print "\e[#{down}B" if down > 0
      print "\r"
    end

    def clear_render
      print "\e[#{@prev_cur_row}A" if @prev_cur_row > 0
      print "\r\e[J"
      @prev_rows = 0; @prev_cur_row = 0
    end

    def printable?(k) = !k.start_with?("\e") && k.ord >= 32

    # ── Buffer mutations (paste-aware) ───────────────────────────────

    def insert(k)
      @pastes.each { |p| p[:start] += k.length if p[:start] >= @cur }
      @buf.insert(@cur, k)
      @cur += k.length
      render
    end

    def del_range(from, to)
      from = [from, 0].max
      to = [to, @buf.length].min
      return if to <= from
      len = to - from
      @pastes.reject! { |p| p[:start] >= from && p[:start] + p[:length] <= to }
      @pastes.each { |p| p[:start] -= len if p[:start] >= to }
      @buf.slice!(from, len)
      @cur = from if @cur > from && @cur < to
      @cur -= len if @cur >= to
    end

    def backspace
      return if @cur == 0
      paste = @pastes.find { |p| @cur == p[:start] + p[:length] }
      if paste
        del_range(paste[:start], paste[:start] + paste[:length])
      else
        del_range(@cur - 1, @cur)
      end
      render
    end

    def forward_delete
      return if @cur >= @buf.length
      paste = @pastes.find { |p| @cur == p[:start] }
      if paste
        del_range(paste[:start], paste[:start] + paste[:length])
      else
        del_range(@cur, @cur + 1)
      end
      render
    end

    def move(d)
      nc = @cur + d
      return unless nc.between?(0, @buf.length)
      paste = @pastes.find { |p| nc > p[:start] && nc < p[:start] + p[:length] }
      nc = (d > 0 ? paste[:start] + paste[:length] : paste[:start]) if paste
      @cur = nc; render
    end

    # ── Tab completion ───────────────────────────────────────────────

    def handle_tab
      if @cycle
        @cycle[:index] = (@cycle[:index] + 1) % @cycle[:matches].length
        apply_cycle; return
      end
      return unless @completer
      prefix = @buf[0...@cur]
      result = @completer.call(prefix) or return
      matches, start = result[:matches], result[:start]
      return if matches.nil? || matches.empty?
      if matches.length == 1
        replace_arg(start, matches[0]); return
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

    # ── Input reading ────────────────────────────────────────────────

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
      when 13, 10 then "\e\r"
      else "\e#{c.chr}"
      end
    end

    def read_csi(io, buf)
      24.times do
        nb = io.getbyte or break
        buf << nb.chr
        break if nb.between?(64, 126)
      end
      buf
    end

    # ── Bracketed paste collection ───────────────────────────────────

    def collect_paste(io)
      terminator = "\e[201~".bytes
      raw = +"".b
      window = []
      loop do
        b = io.getbyte or break
        window << b; window.shift if window.length > terminator.length
        raw << b.chr
        break if window == terminator
      end
      raw.slice!(-terminator.length, terminator.length) if raw.bytes.last(terminator.length) == terminator
      text = raw.force_encoding("UTF-8").scrub
      return if text.empty?
      text = text.gsub("\r\n", "\n").tr("\r", "\n")
      start = @cur
      lines = text.count("\n") + 1
      @pastes.each { |p| p[:start] += text.length if p[:start] >= @cur }
      @buf.insert(@cur, text)
      @pastes << { start: start, length: text.length, lines: lines }
      @pastes.sort_by! { |p| p[:start] }
      @cur = start + text.length
      render
    end

    # ── Rendering ────────────────────────────────────────────────────

    def paste_label_for(p)
      n = p[:lines]
      "#{PASTE_STYLE} #{n} #{n == 1 ? "line" : "lines"} pasted #{Ansi.reset}"
    end

    def render
      cols = (IO.console&.winsize&.last || 80)
      cols = 1 if cols < 1

      print "\e[#{@prev_cur_row}A" if @prev_cur_row > 0
      print "\r\e[J"

      prompt_w = Ansi.width(@prompt)
      indent = " " * prompt_w

      out = +""
      out << @prompt

      row = 0
      col = prompt_w
      cur_row = 0
      cur_col = prompt_w
      cur_recorded = false

      advance = lambda do |w|
        col += w
        while col >= cols
          row += 1
          col -= cols
        end
      end

      newline_to_indent = lambda do
        out << "\r\n" << indent
        row += 1
        col = prompt_w
      end

      i = 0
      while i <= @buf.length
        if !cur_recorded && i == @cur
          cur_row = row; cur_col = col; cur_recorded = true
        end
        break if i == @buf.length

        paste = @pastes.find { |p| p[:start] == i }
        if paste
          newline_to_indent.call if col != prompt_w
          label = paste_label_for(paste)
          out << label
          advance.call(Ansi.width(label))
          i += paste[:length]
          newline_to_indent.call
          next
        end

        c = @buf[i]
        if c == "\n"
          newline_to_indent.call
          i += 1
          next
        end

        out << c
        advance.call(Ansi.width(c))
        i += 1
      end

      unless cur_recorded
        cur_row = row; cur_col = col
      end

      print out

      end_row = row
      print "\r"
      up = end_row - cur_row
      print "\e[#{up}A" if up > 0
      print "\e[#{cur_col}C" if cur_col > 0

      @prev_rows = end_row + 1
      @prev_cur_row = cur_row
    end

    # ── History / word ops ───────────────────────────────────────────

    def history_step(d)
      return if @history.empty?
      @stash = @buf.dup if @hpos == @history.length
      np = (@hpos + d).clamp(0, @history.length)
      return if np == @hpos
      @hpos = np
      @buf = (@hpos == @history.length ? (@stash || +"") : @history[@hpos]).dup
      @pastes = []
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
