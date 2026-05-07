module AI
  # ── Streaming syntax highlighter ─────────────────────────────────────
  class Highlighter
    R = "\e[0m"
    OPENERS = { "(" => ")", "[" => "]", "{" => "}" }.freeze
    CLOSERS = OPENERS.invert.freeze
    PINK   = [255, 128, 170].freeze
    PURPLE = [204, 153, 255].freeze
    SALMON = [250, 128, 114].freeze
    BROWN  = [196, 168, 130].freeze
    BG     = [40, 42, 54].freeze
    TAG_DELIM = "38;2;170;255;220"
    TAG_NAME  = "38;2;200;240;215"
    STRING    = "38;2;195;255;195"
    NUM_FG = 183
    SYMS = { ":" => 159, ";" => 159, "@" => 229, "^" => 229, "&" => 229,
             "*" => 229, "-" => 180, "+" => 180, "." => 180, "," => 180,
             "!" => 210, "~" => 217, "'" => 217 }.freeze

    def initialize
      @col = 0; @at_line_start = true
      @mode = nil
      @slash = false; @star = false
      @in_string = false; @escape = false
      @brackets = []; @in_word = false
      @tag_state = nil; @tag_buf = +""; @tag_width = 0
    end

    def paint(text)
      out = +""
      text.each_char do |c|
        if c == "\n" then out << newline
        else out << paint_char(c); @col += 1
        end
      end
      out
    end

    private

    def newline
      if @tag_state == :markup
        @tag_state = nil; @tag_buf = +""; @tag_width = 0
      end
      @mode = nil if @mode == :line_comment
      @slash = @star = false
      @in_word = @in_string = @escape = false
      @col = 0; @at_line_start = true
      "\n"
    end

    def paint_char(c)
      if @mode == :block_comment
        out = "#{CMT_STYLE}#{c}#{R}"
        if @star && c == "/" then @mode = nil; @star = false
        else @star = (c == "*")
        end
        return out
      end

      return "#{CMT_STYLE}#{c}#{R}" if @mode == :line_comment

      if @in_string
        out = "\e[#{STRING}m#{c}#{R}"
        if @escape then @escape = false
        elsif c == "\\" then @escape = true
        elsif c == '"' then @in_string = false
        end
        return out
      end

      if @slash
        @slash = false
        return case c
               when "/" then @mode = :line_comment;  "\b \b#{CMT_STYLE}//#{R}"
               when "*" then @mode = :block_comment; "\b \b#{CMT_STYLE}/*#{R}"
               else "\b \b\e[38;5;229m/#{R}" << paint_char(c)
               end
      end

      return paint_in_tag(c) if @tag_state == :markup

      was_at_line_start = @at_line_start
      @at_line_start = was_at_line_start && !!c.match?(/\s/)

      if c == '"'
        @in_string = true; @in_word = false
        return "\e[#{STRING}m\"#{R}"
      end
      if c == "/"  then @slash = true; return "/" end
      if c == "#"  then @mode = :line_comment; return "#{CMT_STYLE}##{R}" end
      if c == ";" && was_at_line_start
        @mode = :line_comment; return "#{CMT_STYLE};#{R}"
      end

      if @tag_state == :attrs
        if c == ">" then @tag_state = nil; return "\e[#{TAG_DELIM}m>#{R}" end
        return "\e[#{TAG_DELIM}m/#{R}" if c == "/"
      end

      if c == "<" && @tag_state.nil?
        @tag_state = :markup; @tag_buf = +"<"; @tag_width = 1
        @in_word = false
        return "<"
      end

      if OPENERS[c]
        clr = bracket_color(@col, @brackets.length)
        @brackets.push(clr); @in_word = false
        return "\e[38;2;#{clr}m#{c}#{R}"
      end
      if CLOSERS[c]
        clr = @brackets.pop || bracket_color(@col, 0)
        @in_word = false
        return "\e[38;2;#{clr}m#{c}#{R}"
      end

      return (@in_word = true; c) if c.match?(/[A-Za-z_]/)
      return (@in_word ? c : "\e[38;5;#{NUM_FG}m#{c}#{R}") if c.match?(/\d/)

      @in_word = false
      (sc = SYMS[c]) ? "\e[38;5;#{sc}m#{c}#{R}" : c
    end

    def paint_in_tag(c)
      if @tag_buf == "<" && c == "/"
        @tag_buf << c; @tag_width += 1; return c
      end
      name_started = @tag_buf.match?(%r{\A</?[A-Za-z]})
      if c.match?(/[A-Za-z]/) || (name_started && c.match?(/[\w\-]/))
        @tag_buf << c; @tag_width += 1; return c
      end
      return abort_tag(c) unless name_started

      case c
      when ">"
        s = render_tag << "\e[#{TAG_DELIM}m>#{R}"
        @tag_state = nil; @tag_buf = +""; @tag_width = 0; s
      when "/", /\s/
        s = render_tag
        @tag_state = :attrs; @tag_buf = +""; @tag_width = 0
        s << (c == "/" ? "\e[#{TAG_DELIM}m/#{R}" : c)
      else abort_tag(c)
      end
    end

    def render_tag
      erase = "\b" * @tag_width
      colored = @tag_buf.each_char.map { |c|
        style = %w[< / >].include?(c) ? TAG_DELIM : TAG_NAME
        "\e[#{style}m#{c}#{R}"
      }.join
      +"" << erase << (" " * @tag_width) << erase << colored
    end

    def abort_tag(c)
      @tag_state = nil; @tag_buf = +""; @tag_width = 0
      paint_char(c)
    end

    def bracket_color(col, depth)
      t = ([col / 80.0, 1].min + [depth / 5.0, 1].min) / 2.0
      o = [1 - depth * 0.08, 0.55].max
      warm = (depth * 13 + col * 7) % 4 == 0
      a, b = warm ? [SALMON, BROWN] : [PINK, PURPLE]
      a.zip(b, BG).map { |fa, fb, bg|
        (bg + ((fa + (fb - fa) * t).round - bg) * o).round
      }.join(";")
    end
  end
end
