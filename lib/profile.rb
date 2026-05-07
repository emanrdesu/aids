module AI
  # ── Profile ──────────────────────────────────────────────────────────
  # Loads user-facing configuration from environment variables.
  module Profile
    module_function
    DEFAULT_SYSTEM = "You are a helpful assistant. Be direct and concise."

    def color(var, fallback)
      v = ENV[var]
      v && v.match?(/\A\d+\z/) && (0..255).cover?(v.to_i) ? v.to_i : fallback
    end

    def load
      let(
        name:   ENV["AI_NAME"]   || "Assistant",
        icon:   ENV["AI_ICON"]   || "\u2726",
        prompt: ENV["AI_PROMPT"] || "\u276f",
        color:  color("AI_COLOR", 110),
        system: ENV["AI_SYSTEM_PROMPT"] || DEFAULT_SYSTEM
      )
    end
  end
end
