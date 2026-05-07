module AI
  # ── Stats / cost tracking ────────────────────────────────────────────
  module Stats
    module_function

    def blank
      { "interactions" => 0, "tokens_in" => 0, "tokens_out" => 0, "cost" => 0.0 }
    end

    def read
      File.exist?(STATS_FILE) ? (JSON.parse(File.read(STATS_FILE)) rescue blank) : blank
    end

    def cost(usage)
      (usage["prompt_cache_hit_tokens"]  || 0) * RATES[:hit]  +
      (usage["prompt_cache_miss_tokens"] || 0) * RATES[:miss] +
      (usage["completion_tokens"]        || 0) * RATES[:out]
    end

    def record(usage)
      s = read
      s["interactions"] = s["interactions"].to_i + 1
      if usage
        s["tokens_in"]  = s["tokens_in"].to_i  + (usage["prompt_tokens"]     || 0)
        s["tokens_out"] = s["tokens_out"].to_i + (usage["completion_tokens"] || 0)
        s["cost"]       = s["cost"].to_f       + cost(usage)
      end
      FileUtils.mkdir_p(META_DIR)
      File.write(STATS_FILE, JSON.pretty_generate(s))
    end
  end
end
