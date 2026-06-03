module AI
  # ── Slash commands ───────────────────────────────────────────────────
  module Commands
    Command = Struct.new(:name, :desc, :available, :arg_complete, :run, keyword_init: true) do
      def available?(app) = available.nil? || available.call(app)
    end

    REGISTRY = {}

    def self.register(name, desc:, available: nil, arg_complete: nil, &run)
      REGISTRY[name] = Command.new(
        name: name, desc: desc, available: available, arg_complete: arg_complete, run: run,
      )
    end

    def self.find(name) = REGISTRY[name]
    def self.slash?(input) = input.start_with?("/")

    def self.available_names(app)
      REGISTRY.values.select { |c| c.available?(app) }.map(&:name).sort
    end

    def self.complete_name(app, prefix)
      available_names(app).select { |n| n.start_with?(prefix) }
    end

    def self.dispatch(app, input)
      name, rest = input.strip.split(/\s+/, 2)
      cmd = REGISTRY[name] or return :unknown
      return :unavailable unless cmd.available?(app)
      cmd.run.call(app, rest || "")
      :ok
    end

    register("/discard",
             desc: "Remove turn(s): /discard [*|N|A-B|A-|-B]",
             available: ->(app) { !app.session.empty? },
             arg_complete: ->(_app, arg) { %w[*].select { |x| x.start_with?(arg) } }) do |app, args|
      app.discard(args)
    end

    register("/title",
             desc: "Set the session title",
             available: ->(app) { !app.session.empty? }) do |app, args|
      app.set_title(args.strip)
    end

    register("/clone",
             desc: "Clone this session into a new active one",
             available: ->(app) { !app.session.empty? }) do |app, _|
      app.clone_session
    end

    register("/attach",
             desc: "Attach a file or directory to the next turn",
             arg_complete: ->(_app, arg) { Paths.complete(arg) }) do |app, args|
      app.attach(args.strip)
    end

    register("/detach",
             desc: "Remove an attachment",
             available: ->(app) { app.attachments.any? },
             arg_complete: ->(app, arg) {
               app.attachments.map { |p| Paths.short(p) }.select { |s| s.start_with?(arg) }
             }) do |app, args|
      app.detach(args.strip)
    end

    register("/files",
             desc: "List currently attached files",
             available: ->(app) { app.attachments.any? }) do |app, _|
      app.list_files
    end
  end
end
