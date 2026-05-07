module AI
  # ── Session ──────────────────────────────────────────────────────────
  class Session
    attr_accessor :stamp, :title, :messages, :usages

    def initialize
      @stamp    = Time.now.strftime("%Y%m%d-%H%M%S-%L")
      @title    = nil
      @messages = []
      @usages   = []
      @mutex    = Mutex.new
    end

    def turns  = @messages.length / 2
    def empty? = @messages.empty?

    def add_turn(user_content, assistant_content, usage = nil, attachments: [])
      user_msg = { "role" => "user", "content" => user_content }
      user_msg["attachments"] = attachments unless attachments.empty?
      @messages << user_msg
      @messages << { "role" => "assistant", "content" => assistant_content }
      @usages   << usage if usage
    end

    def remove_turns(first, last)
      total = turns
      return 0 if total.zero? || first > total || last < 1
      first = first.clamp(1, total)
      last  = last.clamp(1, total)
      return 0 if first > last
      count = last - first + 1
      @messages.slice!((first - 1) * 2, count * 2)
      if @usages.length >= first
        take = [count, @usages.length - first + 1].min
        @usages.slice!(first - 1, take)
      end
      @title = nil if @messages.empty?
      count
    end

    def discard_last_turn = remove_turns(turns, turns)

    def human_time
      Time.strptime(@stamp, "%Y%m%d-%H%M%S-%L").strftime("%b %-d, %Y · %-I:%M %p")
    rescue StandardError
      @stamp
    end

    def history_file = File.join(META_DIR, "#{@stamp}.readline")
    def json_file    = File.join(META_DIR, "#{@stamp}.json")
    def md_file      = File.join(DATA_DIR, "#{@stamp}.md")
    def files        = [json_file, md_file, history_file]

    def save(profile)
      @mutex.synchronize do
        FileUtils.mkdir_p(META_DIR)
        File.write(json_file, JSON.pretty_generate(
          "timestamp" => @stamp,
          "title"     => @title,
          "messages"  => @messages,
          "usages"    => @usages
        ))
        write_markdown(profile)
      end
    end

    def delete_files
      files.each { |f| File.delete(f) if File.exist?(f) }
    end

    def self.all
      Dir[File.join(META_DIR, "*.json")]
        .reject { |f| File.basename(f) == "stats.json" }
        .map    { |f| File.basename(f, ".json") }
        .sort
    end

    def self.load(stamp)
      data = JSON.parse(File.read(File.join(META_DIR, "#{stamp}.json"))) rescue (return nil)
      return nil unless data.is_a?(Hash)
      s = new; s.stamp = stamp; s.title = data["title"]
      if data["messages"].is_a?(Array)
        s.messages = data["messages"]
        s.usages   = data["usages"] || data["usage_log"] || []
      elsif data["branches"].is_a?(Array)
        first = data["branches"].first || {}
        s.messages = first["messages"] || []
        s.usages   = first["usages"]   || []
      else
        return nil
      end
      s
    end

    private

    def write_markdown(profile)
      md = +"# #{@title || @stamp}\n\n**#{profile.icon} #{profile.name}**\n\n"
      @messages.each do |m|
        if m["role"] == "user"
          md << "### You\n\n"
          (m["attachments"] || []).each { |a| md << "📎 `#{a["path"]}`\n" }
          md << "\n#{m["content"]}\n\n"
        else
          md << "### #{profile.icon} #{profile.name}\n\n#{m["content"]}\n\n"
        end
      end
      File.write(md_file, md)
    end
  end
end
