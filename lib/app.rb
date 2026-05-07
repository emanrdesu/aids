module AI
  # ── App / REPL ───────────────────────────────────────────────────────
  class App
    TITLE_PROMPT = "Give a concise title (3-10 words) for this conversation. " \
                   "Respond with ONLY the title, nothing else."

    DISCARD_USAGE = "usage: /discard [all | N | A-B | A- | -B]"

    attr_reader :session, :attachments

    def initialize(key:, profile:, resume: false)
      @key = key; @profile = profile
      @editor = LineEditor.new
      @editor.completer = ->(prefix) { complete(prefix) }
      @hl     = Highlighter.new
      @fresh  = true
      @attachments = []
      @title_thread = nil
      if resume && (st = Session.all.last) && (s = Session.load(st))
        @session = s; @fresh = false
      end
      @session ||= Session.new
    end

    def ask(text)
      p = @profile
      attached_data = @attachments.map { |abs|
        { "path" => Paths.short(abs), "content" => safe_read(abs) }
      }
      user_msg = { "role" => "user", "content" => text }
      user_msg["attachments"] = attached_data unless attached_data.empty?
      pending = @session.messages.map { |m| AI.api_message(m) } << AI.api_message(user_msg)

      print_attachments(attached_data) if attached_data.any?
      puts "\n#{Ansi.fg(p.color)}#{p.icon} #{p.name}#{Ansi.reset}"
      reply, usage =
        begin
          AI.stream(pending, p.system, @key) { |chunk| print @hl.paint(chunk) }
        rescue Interrupt
          puts "\n#{Ansi.fg(220)}[interrupted — turn discarded]#{Ansi.reset}"
          return
        end
      puts
      @session.add_turn(text, reply, usage, attachments: attached_data)
      @attachments = []
      AI.print_usage(usage)
      @session.save(p)
      @fresh = false
      Stats.record(usage)
      kick_title_fetch if @session.title.nil? && @session.messages.length >= 2
    end

    def discard(arg)
      arg = arg.to_s.strip
      return discard_session if arg == "all"

      total = @session.turns
      range =
        if arg.empty?
          [total, total]
        else
          parsed = parse_discard_arg(arg, total)
          return notify(DISCARD_USAGE) unless parsed
          parsed
        end

      first, last = range
      first = first.clamp(1, total)
      last  = last.clamp(1, total)
      if last < first
        notify "no turns in that range"; return
      end

      removed = @session.remove_turns(first, last)
      if @session.empty?
        @session.delete_files
        @fresh = true
        redraw
        notify "\u2212 discarded #{removed} turn#{removed == 1 ? "" : "s"} · session is now empty"
      else
        @session.save(@profile)
        redraw
        notify "\u2212 discarded #{removed} turn#{removed == 1 ? "" : "s"}"
      end
    end

    def discard_session
      delete_session(announce: "discarded session #{@session.stamp}")
    end

    def set_title(text)
      if text.empty?
        notify "usage: /title <new title>"
        return
      end
      @session.title = text
      @session.save(@profile)
      redraw
      notify "title set"
    end

    def clone_session
      save_history
      src = @session
      dup = Session.new
      dup.messages = Marshal.load(Marshal.dump(src.messages))
      dup.usages   = Marshal.load(Marshal.dump(src.usages))
      dup.title    = src.title ? "#{src.title} (clone)" : "(clone)"
      dup.save(@profile)
      FileUtils.cp(src.history_file, dup.history_file) if File.exist?(src.history_file)
      @session = dup
      @fresh   = false
      load_history
      redraw
      notify "cloned to new session"
    end

    def attach(arg)
      if arg.empty?
        notify "usage: /attach <file-or-directory-or-pattern>"
        return
      end
      matches = Dir.glob(arg).map { |p| File.expand_path(p) }
      if matches.empty?
        expanded = File.expand_path(arg)
        if File.exist?(expanded)
          matches = [expanded]
        else
          notify "no such path: #{arg}"
          return
        end
      end
      files = []
      matches.each do |p|
        if File.directory?(p)
          files.concat(Dir.children(p).map { |c| File.join(p, c) }.select { |cp| File.file?(cp) })
        elsif File.file?(p)
          files << p
        end
      end
      added = files.uniq - @attachments
      if added.empty?
        notify "(nothing new to attach)"
        return
      end
      @attachments.concat(added)
      shorts = added.map { |p| Paths.short(p) }
      notify "+ attached #{shorts.join(", ")}"
    end

    def detach(arg)
      if arg.empty?
        notify "usage: /detach <path|pattern|directory>"
        return
      end
      expanded = File.expand_path(arg)
      targets = if File.directory?(expanded)
        @attachments.select { |p| File.dirname(p) == expanded }
      else
        exact = @attachments.find { |p| Paths.short(p) == arg }
        if exact
          [exact]
        else
          @attachments.select { |p|
            File.fnmatch(arg, File.basename(p)) ||
            File.fnmatch(arg, Paths.short(p)) ||
            File.fnmatch(arg, p)
          }
        end
      end
      if targets.empty?
        notify "no matching attachments: #{arg}"
        return
      end
      targets.each { |t| @attachments.delete(t) }
      shorts = targets.map { |p| Paths.short(p) }
      notify "\u2212 detached #{shorts.join(", ")}"
    end

    def list_files
      shorts = @attachments.map { |p| Paths.short(p) }
      notify "#{@attachments.length} file(s) attached:\n#{shorts.join("\n")}"
    end

    def repl
      load_history
      redraw if @session.messages.any?
      loop do
        puts format_attachment_summary if @attachments.any?
        result = begin; @editor.readline(build_prompt); rescue Interrupt; break; end
        case result
        when nil          then break
        when :sess_next   then switch_session(+1)
        when :sess_prev   then switch_session(-1)
        when :redraw      then redraw
        when :del_session then delete_session
        when String
          t = result.strip
          next if t.empty?
          break if %w[exit quit bye :q].include?(t)
          if Commands.slash?(t)
            handle_command(t)
          else
            @hl = Highlighter.new
            ask(t); puts
          end
        end
      end
      flush_title_fetch
      save_history
      footer
    end

    def notify(msg) = puts("#{CMT_STYLE}#{msg}#{Ansi.reset}\n\n")

    def format_attachment_summary
      return nil if @attachments.empty?
      counts = @attachments.group_by { |p| File.extname(p).delete_prefix(".") }
      parts = counts.sort_by { |ext, _| ext }.map do |ext, fs|
        ext_display = ext.empty? ? "(no ext)" : ext
        "#{fs.length} #{ext_display}"
      end
      suffix = counts.length == 1 ? " file included" : " file(s) included"
      "\e[2;38;5;75m#{parts.join(", ")}#{suffix}\e[0m"
    end

    private

    def parse_discard_arg(arg, total)
      case arg
      when /\A(\d+)\z/
        n = $1.to_i
        return nil if n < 1
        n = [n, total].min
        [total - n + 1, total]
      when /\A(\d+)-(\d+)\z/
        a, b = $1.to_i, $2.to_i
        return nil if a < 1 || b < a
        [a, b]
      when /\A(\d+)-\z/
        a = $1.to_i
        return nil if a < 1
        [a, total]
      when /\A-(\d+)\z/
        n = $1.to_i
        return nil if n < 1
        [1, n]
      end
    end

    def complete(prefix)
      return nil unless Commands.slash?(prefix)
      if (m = prefix.match(/\A(\/\S+)\s+/))
        name      = m[1]
        arg_start = m.end(0)
        arg       = prefix[arg_start..]
        cmd       = Commands.find(name)
        return nil unless cmd && cmd.available?(self) && cmd.arg_complete
        { matches: cmd.arg_complete.call(self, arg), start: arg_start }
      else
        { matches: Commands.complete_name(self, prefix), start: 0 }
      end
    end

    def handle_command(input)
      case Commands.dispatch(self, input)
      when :unknown     then notify "unknown command: #{input.split.first}"
      when :unavailable then notify "not available right now: #{input.split.first}"
      end
    end

    def safe_read(path)
      File.read(path, mode: "rb").force_encoding("UTF-8").scrub
    rescue StandardError => e
      "[could not read #{path}: #{e.message}]"
    end

    def clear_screen = print("\e[H\e[2J\e[3J")

    def center(str)
      cols = IO.console&.winsize&.last || 80
      pad  = [(cols - Ansi.width(str)) / 2, 0].max
      (" " * pad) + str
    end

    def print_attachments(attached)
      puts "#{Ansi.dim}#{Ansi.fg(ATT_FG)}📎 attached#{Ansi.reset}"
      attached.each { |a| puts "  #{Ansi.fg(ATT_FG)}#{a["path"]}#{Ansi.reset}" }
    end

    def delete_session(announce: nil)
      stamp = @session.stamp
      save_history
      all = Session.all
      idx = all.index(stamp)
      @session.delete_files

      remaining = Session.all
      target = idx && idx > 0 ? remaining[idx - 1] : remaining.first
      if target && (s = Session.load(target))
        @session = s; @fresh = false
        load_history; redraw
      else
        @fresh = true
        @session = Session.new
        @editor.history = []
        clear_screen
      end
      notify(announce || "deleted session #{stamp}")
    end

    def switch_session(dir)
      save_history
      all = Session.all

      if @fresh
        return unless dir < 0 && all.any?
        @fresh = false
        @session = Session.load(all.last) or return
        load_history; redraw
        return
      end

      return if all.empty?
      cur = all.index(@session.stamp) or return
      target = cur + dir
      if target >= all.length
        @fresh = true
        @session = Session.new
        @editor.history = []
        clear_screen
        return
      end
      target = target.clamp(0, all.length - 1)
      return if target == cur
      @session = Session.load(all[target]) or return
      load_history; redraw
    end

    def redraw
      clear_screen
      draw_title; draw_meta
      puts
      p = @profile
      @session.messages.each do |m|
        if m["role"] == "user"
          puts "#{Ansi.bold}#{Ansi.fg(USER_FG)}#{USER_ICON}  #{m["content"]}#{Ansi.reset}"
          print_attachments(m["attachments"]) if m["attachments"]&.any?
        else
          puts "#{Ansi.fg(p.color)}#{p.icon} #{p.name}#{Ansi.reset}"
          print Highlighter.new.paint(m["content"]); puts
        end
        puts
      end
      print_attachments(@attachments.map { |p| { "path" => Paths.short(p) } }) if @attachments.any?
    end

    def draw_title
      return unless @session.title
      e = Ansi.fg(@profile.color)
      inner = "  #{@session.title}  "
      w = Ansi.width(inner)
      puts center("#{e}\u256d#{"─" * w}\u256e#{Ansi.reset}")
      puts center("#{e}\u2502#{Ansi.reset}#{inner}#{e}\u2502#{Ansi.reset}")
      puts center("#{e}\u2570#{"─" * w}\u256f#{Ansi.reset}")
    end

    def draw_meta
      all = Session.all
      idx = all.index(@session.stamp)
      n   = idx ? idx + 1 : all.length + 1
      total = [all.length, n].max
      puts center("#{CMT_STYLE}session #{n}/#{total}  \u00b7  #{@session.human_time}#{Ansi.reset}")
    end

    def kick_title_fetch
      return if @title_thread&.alive?
      session = @session; profile = @profile; key = @key
      context = session.messages.first(2)
                       .map { |m| "#{m["role"]}: #{m["content"]}" }.join("\n\n")
      @title_thread = Thread.new do
        Thread.current.report_on_exception = false
        title = AI.title_query(TITLE_PROMPT, context, key)
        if title && session.title.nil?
          session.title = title
          session.save(profile) if File.exist?(session.json_file)
        end
      end
    end

    def flush_title_fetch
      @title_thread&.join(2.second) rescue nil
    end

    def build_prompt
      p = @profile; c = p.color
      turn = @session.turns + 1
      label = " #{p.icon} #{p.name} \u00b7#{turn} "
      "\e[38;5;#{c}m#{LCAP}\e[48;5;#{c};38;5;0m#{label}\e[0;38;5;#{c}m#{RCAP}\e[0m " \
      "\e[2;38;5;#{c}m#{p.prompt}\e[0m "
    end

    def load_history
      f = @session.history_file
      @editor.history = File.exist?(f) ? File.readlines(f, chomp: true).last(500) : []
    end

    def save_history
      return if @editor.history.empty?
      FileUtils.mkdir_p(META_DIR)
      File.write(@session.history_file, @editor.history.last(1000).join("\n"))
    end

    def footer
      return if @session.messages.empty?
      all = Session.all
      n = (all.index(@session.stamp) || all.length - 1) + 1
      puts "\n#{CMT_STYLE}session ##{n}#{Ansi.reset}"
    end
  end
end
