# AIDS

AI DeepSeek client REPL for the terminal. An interactive assistant with persistent chat sessions, file attachments, streaming syntax highlighting, and cost tracking.

## Installation

```bash
gem install aids
```

Requires Ruby >= 3.0.

## Configuration

Set your DeepSeek API key:

```bash
export DEEPSEEK_API_KEY="sk-..."
```

### Persona (optional)

| Variable           | Default                  | Description                        |
| ------------------ | ------------------------ | ---------------------------------- |
| `AI_NAME`          | `Assistant`              | Display name                       |
| `AI_ICON`          | `✦`                      | Icon shown before responses        |
| `AI_PROMPT`        | `❯`                      | Input prompt character             |
| `AI_COLOR`         | `110`                    | ANSI 256-color index for responses |
| `AI_SYSTEM_PROMPT` | Helpful assistant prompt | Custom system prompt               |

```bash
export AI_NAME="CodeBot"
export AI_ICON="🤖"
export AI_SYSTEM_PROMPT="You are an expert Ruby and Rust developer."
```

## Usage

Start the REPL:

```bash
aids
```

One-shot queries:

```bash
aids "explain this regex: /(?<=\s|^)#[a-z]+/"
echo "what does this error mean?" | aids
```

### CLI Flags

| Flag               | Behavior                            |
| ------------------ | ----------------------------------- |
| `-c`, `--continue` | Resume the most recent session      |
| `--history`        | Open the sessions directory in `lf` |
| `--clean`          | Delete all sessions and stats       |

## Built-in Commands

| Command          | Description                                           |
| ---------------- | ----------------------------------------------------- |
| `/attach <path>` | Attach files or directories as context (glob support) |
| `/detach <path>` | Remove an attachment                                  |
| `/files`         | List current attachments                              |
| `/discard N`     | Remove the last N turns                               |
| `/discard A-B`   | Remove a range of turns (`A-`, `-B`, `*` for all)     |
| `/title <text>`  | Set a custom session title                            |
| `/clone`         | Create a deep copy of the current session             |

## Keyboard Shortcuts

| Key               | Action                              |
| ----------------- | ----------------------------------- |
| `Enter`           | Insert newline                      |
| `Alt+Enter`       | Send message                        |
| `Ctrl+c`          | Interrupt streaming response        |
| `Ctrl+l`          | Redraw conversation                 |
| `Alt+j` / `Alt+k` | Switch to next / previous session   |
| `Alt+l`           | Redraw current session              |
| `Alt+Delete`      | Delete current session              |
| `Up` / `Down`     | Navigate input history              |
| `Ctrl+u`          | Clear to beginning of line          |
| `Ctrl+k`          | Clear to end of line                |
| `Ctrl+w`          | Delete previous word                |
| `Alt+b` / `Alt+f` | Jump backward / forward a word      |
| `Tab`             | Complete file paths and attachments |

You can also paste content in, and it will show `[ $n lines pasted ]` instead of the the actual contents.

## Session Management

Sessions are saved automatically after each turn. To continue where you left off:

```bash
aids -c
```

All data lives under `~/.local/share/ai/`:

```
~/.local/share/ai/
├── 20260102-143052-001.md        # Human-readable conversation
├── .meta/
│   ├── 20260102-143052-001.json  # Session data
│   ├── 20260102-143052-001.readline
│   └── stats.json               # Cumulative usage & cost
```

Press Control+D (EOF) to exit the REPL.

## Usage & Cost Tracking

After each response, a summary shows token counts and estimated cost in microunits ($0.0001 per unit). Cumulative stats are stored in `~/.local/share/ai/.meta/stats.json`.

Pricing tiers:

- Cache hits: $0.028 / million tokens
- Cache misses: $0.28 / million tokens
- Output: $0.42 / million tokens

## Examples

```
❯ /attach src/main.rb
  + src/main.rb

❯ what does the error on line 42 mean?

✦ The NameError on line 42 means you're referencing a variable `user`
  that hasn't been defined in that scope. Try passing it as a parameter.
```

```
❯ /discard 2
  — 2 turns removed

❯ /clone
  + cloned → 20260102-143630-002

❯ /title Debugging the API client
  ✓ title set
```

## License

MIT
