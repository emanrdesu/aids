%w[net/http uri json optparse fileutils io/console pathname time emanlib].each { |lib| require lib }

module AI
  VERSION = "0.1.0"
  API_URL = URI("https://api.deepseek.com/chat/completions")
  MODEL = "deepseek-chat"
  DATA_DIR = File.expand_path("~/.local/share/ai")
  META_DIR = File.join(DATA_DIR, ".meta")
  STATS_FILE = File.join(META_DIR, "stats.json")
  RATES = { hit: 0.028, miss: 0.28, out: 0.42 }.freeze

  LCAP = "\ue0b6"; RCAP = "\ue0b4"; USER_ICON = "👤"
  USER_FG = 117; ATT_FG = 180; CMT_FG = 247
  CMT_STYLE = "\e[2;3;38;5;#{CMT_FG}m"
end

require "profile"
require "ansi"
require "paths"
require "highlighter"
require "stats"
require "session"
require "commands"
require "line_editor"
require "app"

module AI
  # ── HTTP / streaming ─────────────────────────────────────────────────
  def self.stream(messages, system, key)
    body = { model: MODEL,
             messages: [{ role: "system", content: system }, *messages],
             stream: true,
             stream_options: { include_usage: true } }.to_json
    usage = nil
    full = +""
    Net::HTTP.start(API_URL.host, API_URL.port, use_ssl: true, read_timeout: 120) do |http|
      req = Net::HTTP::Post.new(API_URL,
                                "Authorization" => "Bearer #{key}",
                                "Content-Type" => "application/json")
      req.body = body
      http.request(req) do |res|
        abort "#{Ansi.fg(196)}API #{res.code}#{Ansi.reset}" unless res.is_a?(Net::HTTPSuccess)
        buf = +""
        res.read_body do |chunk|
          buf << chunk
          while (nl = buf.index("\n"))
            line = buf.slice!(0..nl).strip
            next unless line.start_with?("data: ")
            payload = line.delete_prefix("data: ")
            next if payload == "[DONE]"
            event = JSON.parse(payload) rescue next
            usage = event["usage"] if event["usage"]
            if (tok = event.dig("choices", 0, "delta", "content"))
              full << tok
              yield tok
            end
          end
        end
      end
    end
    [full, usage]
  end

  def self.title_query(system, user, key)
    body = { model: MODEL, max_tokens: 40,
            messages: [{ role: "system", content: system },
                       { role: "user", content: user }] }.to_json
    Net::HTTP.start(API_URL.host, API_URL.port, use_ssl: true, read_timeout: 15) do |http|
      req = Net::HTTP::Post.new(API_URL,
                                "Authorization" => "Bearer #{key}",
                                "Content-Type" => "application/json")
      req.body = body
      res = http.request(req)
      return nil unless res.is_a?(Net::HTTPSuccess)
      (JSON.parse(res.body) rescue nil)&.dig("choices", 0, "message", "content")&.strip
    end
  rescue StandardError
    nil
  end

  def self.print_usage(usage)
    return unless usage
    g = "#{Ansi.dim}#{Ansi.fg(243)}"; r = Ansi.reset
    cells = %w[hit miss out total].zip([
      usage["prompt_cache_hit_tokens"] || 0,
      usage["prompt_cache_miss_tokens"] || 0,
      usage["completion_tokens"] || 0,
      usage["total_tokens"] || 0,
    ]).map { |label, val| "#{g}#{label}#{r} #{Ansi.fg(87)}#{val}#{r}" }
    cells << "#{Ansi.fg(220)}#{format("%.4f", Stats.cost(usage))}\u03bc$#{r}"
    row = "  #{cells.join("  #{g}\u2502#{r}  ")}  "
    w = Ansi.width(row)
    puts "\n#{g}\u256d#{"─" * w}\u256e#{r}"
    puts "#{g}\u2502#{r}#{row}#{g}\u2502#{r}"
    puts "#{g}\u2570#{"─" * w}\u256f#{r}"
    puts
  end

  def self.api_message(msg)
    if msg["role"] == "user" && (atts = msg["attachments"]) && atts.any?
      blocks = atts.map { |a| "<attached path=\"#{a["path"]}\">\n#{a["content"]}\n</attached>" }
      { "role" => "user", "content" => blocks.join("\n") + "\n\n" + msg["content"].to_s }
    else
      { "role" => msg["role"], "content" => msg["content"] }
    end
  end

  # ── Entry point ──────────────────────────────────────────────────────
  def self.run(argv = ARGV)
    resume = false
    rest = OptionParser.new { |o|
      o.on("-c", "--continue") { resume = true }
      o.on("--history") { exec("lf", DATA_DIR) }
      o.on("--clean") { clean!; exit }
    }.order(argv)

    key = ENV["DEEPSEEK_API_KEY"] or abort "#{Ansi.fg(196)}DEEPSEEK_API_KEY not set#{Ansi.reset}"
    app = App.new(key: key, profile: Profile.load, resume: resume)

    piped = $stdin.tty? ? "" : $stdin.read.strip
    text = [piped, rest.join(" ")].map(&:strip).reject(&:empty?).join(" ")

    if text.empty?
      app.repl
    else
      puts "#{Ansi.dim}> #{text}#{Ansi.reset}"
      app.ask(text); puts
    end
  end

  def self.clean!
    files = Dir[File.join(DATA_DIR, "*.md")] +
            Dir[File.join(META_DIR, "*")].select { |x| File.file?(x) }
    files.each { |f| File.delete(f) }
    puts "#{Ansi.fg(114)}\u2726 #{files.size} files removed#{Ansi.reset}"
  end
end
