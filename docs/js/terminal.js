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
    .type('/projd-plan "A REST API with user auth and todo CRUD"')
    .pause(400)
    .output('')
    .output(`<span class="term-output">  Created 3 features in progress/:</span>`)
    .output(`<span class="term-output">    1. </span><span class="term-highlight">user-auth</span><span class="term-output">       JWT-based login and registration</span>`)
    .output(`<span class="term-output">    2. </span><span class="term-highlight">todo-crud</span><span class="term-output">       CRUD endpoints for todo items </span><span class="term-warn">(blocked by: user-auth)</span>`)
    .output(`<span class="term-output">    3. </span><span class="term-highlight">api-docs</span><span class="term-output">        OpenAPI spec generation</span>`)
    .pause(800)
    .output('')
    .prompt('$ ')
    .type('/projd-hands-off --dry-run')
    .pause(300)
    .output('')
    .output(`<span class="term-output">  Dispatch plan </span><span class="term-warn">(max_agents: 20)</span><span class="term-output">:</span>`)
    .output(`<span class="term-output">    Wave 1: </span><span class="term-highlight">user-auth, api-docs</span><span class="term-output">      (2 agents, parallel)</span>`)
    .output(`<span class="term-output">    Wave 2: </span><span class="term-highlight">todo-crud</span><span class="term-output">                (1 agent, after user-auth completes)</span>`)
    .output('')
    .output(`<span class="term-output">  3 features, 2 waves. Run without --dry-run to start.</span>`)
    .pause(800)
    .output('')
    .prompt('$ ')
    .type('/projd-hands-off')
    .pause(500)
    .output('')
    .output(`<span class="term-output">  Dispatching wave 1...</span>`)
    .output(`<span class="term-output">    </span><span class="term-highlight">[user-auth]</span><span class="term-output">  worktree created   branch: </span><span class="term-success">agent/user-auth</span>`)
    .output(`<span class="term-output">    </span><span class="term-highlight">[api-docs]</span><span class="term-output">   worktree created   branch: </span><span class="term-success">agent/api-docs</span>`)
    .pause(600)
    .output('')
    .output(`<span class="term-output">  Wave 1 complete. Dispatching wave 2...</span>`)
    .output(`<span class="term-output">    </span><span class="term-highlight">[todo-crud]</span><span class="term-output">  worktree created   branch: </span><span class="term-success">agent/todo-crud</span>`)
    .pause(400)
    .output('')
    .output(`<span class="term-success">  3/3 features complete. 3 PRs ready for review.</span>`);

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
    .type('bash <(curl -fsSL https://raw.githubusercontent.com/0x3k/projd/main/scripts/remote-install.sh)')
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
    .type('/projd-create my-api')
    .pause(300)
    .output(`<span class="term-output">  Language? </span><span class="term-highlight">go</span>`)
    .output(`<span class="term-output">  Description? </span><span class="term-highlight">REST API for task management</span>`)
    .output(`<span class="term-success">  Created my-api/ with projd harness</span>`)
    .pause(500)
    .output('')
    .prompt('$ ')
    .type('/projd-plan "User auth with JWT and CRUD for tasks"')
    .pause(300)
    .output(`<span class="term-output">  Created 2 features in progress/</span>`)
    .pause(400)
    .output('')
    .prompt('$ ')
    .type('/projd-hands-off')
    .pause(400)
    .output(`<span class="term-output">  Dispatching 2 agents...</span>`)
    .output(`<span class="term-success">  2/2 features complete. PRs ready.</span>`);

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
