// Terminal typing animation engine

class TerminalPlayer {
  constructor(el, opts = {}) {
    this.el = el;
    this.pre = el.querySelector('pre');
    this.speed = opts.speed || 50; // chars per second
    this.pauseMs = opts.pauseMs || 300;
    this.queue = [];
    this.playing = false;
    this.aborted = false;
  }

  prompt(text) {
    this.queue.push({ type: 'prompt', text });
    return this;
  }

  type(text) {
    this.queue.push({ type: 'type', text });
    return this;
  }

  output(text) {
    this.queue.push({ type: 'output', text });
    return this;
  }

  pause(ms) {
    this.queue.push({ type: 'pause', ms });
    return this;
  }

  clear() {
    this.queue.push({ type: 'clear' });
    return this;
  }

  async play() {
    if (this.playing) return;
    this.playing = true;
    this.aborted = false;

    for (const item of this.queue) {
      if (this.aborted) break;

      switch (item.type) {
        case 'prompt':
          this._appendHTML(`<span class="term-prompt">${this._esc(item.text)}</span>`);
          break;

        case 'type':
          await this._typeChars(item.text);
          this._append('\n');
          break;

        case 'output':
          await this._sleep(80);
          this._appendHTML(item.text + '\n');
          break;

        case 'pause':
          await this._sleep(item.ms);
          break;

        case 'clear':
          this.pre.innerHTML = '';
          break;
      }

      this._scrollDown();
    }

    // Add final cursor
    this._appendHTML('<span class="term-cursor"></span>');
    this.playing = false;
  }

  abort() {
    this.aborted = true;
  }

  // Show everything instantly (for reduced motion)
  showAll() {
    this.pre.innerHTML = '';
    for (const item of this.queue) {
      switch (item.type) {
        case 'prompt':
          this._appendHTML(`<span class="term-prompt">${this._esc(item.text)}</span>`);
          break;
        case 'type':
          this._append(item.text + '\n');
          break;
        case 'output':
          this._appendHTML(item.text + '\n');
          break;
        case 'clear':
          this.pre.innerHTML = '';
          break;
      }
    }
    this._appendHTML('<span class="term-cursor"></span>');
  }

  async _typeChars(text) {
    const delay = 1000 / this.speed;
    for (let i = 0; i < text.length; i++) {
      if (this.aborted) return;
      this._append(text[i]);
      this._scrollDown();
      // Add slight variance for realism
      const jitter = delay * (0.5 + Math.random());
      await this._sleep(jitter);
    }
  }

  _append(text) {
    this.pre.appendChild(document.createTextNode(text));
  }

  _appendHTML(html) {
    const span = document.createElement('span');
    span.innerHTML = html;
    while (span.firstChild) {
      this.pre.appendChild(span.firstChild);
    }
  }

  _scrollDown() {
    const body = this.el.querySelector('.terminal-body');
    if (body) body.scrollTop = body.scrollHeight;
  }

  _esc(text) {
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  _sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
  }
}

// Hero terminal demo
function initHeroTerminal() {
  const el = document.getElementById('hero-terminal');
  if (!el) return;

  const player = new TerminalPlayer(el, { speed: 50 });

  player
    .prompt('$ ')
    .type('/projd-plan "A CLI tool for managing dev environments with Docker"')
    .pause(400)
    .output('')
    .output(`<span class="term-output">  Created 7 features in .projd/progress/:</span>`)
    .output(`<span class="term-output">    1. </span><span class="term-highlight">config-loader</span><span class="term-output">       Parse YAML config with validation</span>`)
    .output(`<span class="term-output">    2. </span><span class="term-highlight">env-lifecycle</span><span class="term-output">       Create, start, stop, destroy envs</span>`)
    .output(`<span class="term-output">    3. </span><span class="term-highlight">docker-backend</span><span class="term-output">      Docker container management </span><span class="term-warn">(blocked by: config-loader)</span>`)
    .output(`<span class="term-output">    4. </span><span class="term-highlight">template-engine</span><span class="term-output">     Project templates </span><span class="term-warn">(blocked by: config-loader)</span>`)
    .output(`<span class="term-output">    5. </span><span class="term-highlight">port-forwarding</span><span class="term-output">     Automatic port mapping </span><span class="term-warn">(blocked by: docker-backend)</span>`)
    .output(`<span class="term-output">    6. </span><span class="term-highlight">shell-completions</span><span class="term-output">   Bash/zsh/fish </span><span class="term-warn">(blocked by: env-lifecycle)</span>`)
    .output(`<span class="term-output">    7. </span><span class="term-highlight">status-dashboard</span><span class="term-output">    Live TUI </span><span class="term-warn">(blocked by: docker-backend)</span>`)
    .pause(800)
    .output('')
    .prompt('$ ')
    .type('/projd-hands-off --dry-run')
    .pause(300)
    .output('')
    .output(`<span class="term-output">  Dispatch plan </span><span class="term-warn">(max_agents: 20)</span><span class="term-output">:</span>`)
    .output(`<span class="term-output">    Wave 1: </span><span class="term-highlight">config-loader, env-lifecycle</span><span class="term-output">                        (2 agents)</span>`)
    .output(`<span class="term-output">    Wave 2: </span><span class="term-highlight">docker-backend, template-engine, shell-completions</span><span class="term-output">  (3 agents)</span>`)
    .output(`<span class="term-output">    Wave 3: </span><span class="term-highlight">port-forwarding, status-dashboard</span><span class="term-output">                  (2 agents)</span>`)
    .output('')
    .output(`<span class="term-output">  7 features, 3 waves. Run without --dry-run to start.</span>`)
    .pause(800)
    .output('')
    .prompt('$ ')
    .type('/projd-hands-off')
    .pause(500)
    .output('')
    .output(`<span class="term-output">  Dispatching wave 1...</span>`)
    .output(`<span class="term-output">    </span><span class="term-highlight">[config-loader]</span><span class="term-output">      worktree created   branch: </span><span class="term-success">agent/config-loader</span>`)
    .output(`<span class="term-output">    </span><span class="term-highlight">[env-lifecycle]</span><span class="term-output">      worktree created   branch: </span><span class="term-success">agent/env-lifecycle</span>`)
    .pause(600)
    .output('')
    .output(`<span class="term-output">  Wave 1 complete. Dispatching wave 2...</span>`)
    .output(`<span class="term-output">    </span><span class="term-highlight">[docker-backend]</span><span class="term-output">     worktree created   branch: </span><span class="term-success">agent/docker-backend</span>`)
    .output(`<span class="term-output">    </span><span class="term-highlight">[template-engine]</span><span class="term-output">    worktree created   branch: </span><span class="term-success">agent/template-engine</span>`)
    .output(`<span class="term-output">    </span><span class="term-highlight">[shell-completions]</span><span class="term-output">  worktree created   branch: </span><span class="term-success">agent/shell-completions</span>`)
    .pause(600)
    .output('')
    .output(`<span class="term-output">  Wave 2 complete. Dispatching wave 3...</span>`)
    .output(`<span class="term-output">    </span><span class="term-highlight">[port-forwarding]</span><span class="term-output">    worktree created   branch: </span><span class="term-success">agent/port-forwarding</span>`)
    .output(`<span class="term-output">    </span><span class="term-highlight">[status-dashboard]</span><span class="term-output">   worktree created   branch: </span><span class="term-success">agent/status-dashboard</span>`)
    .pause(400)
    .output('')
    .output(`<span class="term-success">  7/7 features complete. 7 PRs ready for review.</span>`);

  // Check reduced motion preference
  const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        if (prefersReducedMotion) {
          player.showAll();
        } else {
          player.play();
        }
        observer.disconnect();
      }
    });
  }, { threshold: 0.3 });

  observer.observe(el);
}

// Quick start terminal
function initQuickStartTerminal() {
  const el = document.getElementById('quickstart-terminal');
  if (!el) return;

  const player = new TerminalPlayer(el, { speed: 45 });

  player
    .prompt('$ ')
    .type('npx @0x3k/projd')
    .pause(300)
    .output(`<span class="term-output">  Fetching projd...</span>`)
    .output(`<span class="term-success">  Skills installed to ~/.claude/skills/</span>`)
    .pause(500)
    .output('')
    .prompt('$ ')
    .type('# from any Claude Code session:')
    .pause(200)
    .output('')
    .prompt('$ ')
    .type('/projd-create noter')
    .pause(300)
    .output(`<span class="term-output">  Language? </span><span class="term-highlight">typescript</span>`)
    .output(`<span class="term-output">  Description? </span><span class="term-highlight">Markdown note-taking tool with full-text search</span>`)
    .output(`<span class="term-success">  Created noter/ with projd harness</span>`)
    .pause(500)
    .output('')
    .prompt('$ ')
    .type('/projd-plan "Notes with tagging, full-text search, and sync"')
    .pause(300)
    .output(`<span class="term-output">  Created 4 features in .projd/progress/</span>`)
    .pause(400)
    .output('')
    .prompt('$ ')
    .type('/projd-hands-off')
    .pause(400)
    .output(`<span class="term-output">  Dispatching wave 1 (3 agents)...</span>`)
    .output(`<span class="term-output">  Wave 2 (1 agent)...</span>`)
    .output(`<span class="term-success">  4/4 features complete. PRs ready.</span>`);

  const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        if (prefersReducedMotion) {
          player.showAll();
        } else {
          player.play();
        }
        observer.disconnect();
      }
    });
  }, { threshold: 0.3 });

  observer.observe(el);
}

document.addEventListener('DOMContentLoaded', () => {
  initHeroTerminal();
  initQuickStartTerminal();
});
