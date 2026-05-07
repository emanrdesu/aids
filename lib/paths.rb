module AI
  # ── Path helpers ─────────────────────────────────────────────────────
  module Paths
    module_function

    def short(abs)
      abs    = File.expand_path(abs)
      home   = Dir.home
      tilde  = (abs == home || abs.start_with?(home + "/")) ? "~" + abs[home.length..] : nil
      relcwd = begin
                 r = Pathname.new(abs).relative_path_from(Pathname.pwd).to_s
                 r == "." ? "./" : (r.start_with?("..") ? r : "./" + r)
               rescue StandardError
                 nil
               end
      [abs, tilde, relcwd].compact.min_by(&:length)
    end

    def complete(arg)
      if arg.empty?
        dir_text = ""; dir_real = "."; base = ""
      elsif arg.end_with?("/")
        dir_text = arg
        dir_real = arg.start_with?("~") ? File.expand_path(arg) : arg
        base     = ""
      else
        slash = arg.rindex("/")
        if slash
          dir_text = arg[0..slash]
          dir_real = dir_text.start_with?("~") ? File.expand_path(dir_text) : dir_text
          base     = arg[(slash + 1)..]
        else
          dir_text = ""; dir_real = "."; base = arg
        end
      end
      return [] unless File.directory?(dir_real)
      Dir.children(dir_real).select { |e| e.start_with?(base) }.sort.map do |e|
        full   = File.join(dir_real, e)
        suffix = File.directory?(full) ? "/" : ""
        dir_text + e + suffix
      end
    end
  end
end
