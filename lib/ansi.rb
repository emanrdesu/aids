module AI
  # ── ANSI helpers ─────────────────────────────────────────────────────
  module Ansi
    module_function

    def reset    = "\e[0m"
    def bold     = "\e[1m"
    def dim      = "\e[2m"
    def fg(n)    = "\e[38;5;#{n}m"
    def strip(s) = s.gsub(/\e\[[\d;]*m/, "")

    def width(s)
      strip(s).each_char.sum do |c|
        case c.ord
        when 0..126, 57344..63743 then 1
        when 65024..65039, 8205 then 0
        when 4352..4447, 9000..9215, 9728..9983, 11088..11093, 11904..40959,
             44032..55215, 63744..64255, 65040..65135, 65281..65376,
             127744..131071, 131072..262143 then 2
        else 1
        end
      end
    end
  end
end
