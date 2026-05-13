// PiMono Chat Renderer - Message display, streaming, markdown rendering
// Layout: CSS Grid on .message-row (28px icon | 1fr bubble) — no inline style hacks needed.

class ChatRenderer {
  constructor() {
    this.messagesEl = document.getElementById('messages');
    this.welcomeEl = document.getElementById('welcome');
    this.typingEl = document.getElementById('typing-indicator');
    this.streamingEl = null;
    this.streamingText = '';
    this.streamingType = '';
    this.renderTimer = null;
  }

  showWelcome() {
    this.welcomeEl.classList.remove('hidden');
    this.messagesEl.innerHTML = '';
    this.renderSuggestions();
  }

  // Render welcome suggestion cards using localized strings
  renderSuggestions() {
    const grid = document.getElementById('suggestion-grid');
    if (!grid) return;
    const suggestions = [
      L('welcome.suggest1'),
      L('welcome.suggest2'),
      L('welcome.suggest3'),
      L('welcome.suggest4')
    ];
    grid.innerHTML = suggestions.map(text =>
      '<button class="suggestion-card" data-text="' + this._escapeHtml(text) + '">' +
        '<span class="suggestion-icon">&gt;</span>' +
        '<span>' + this._escapeHtml(text) + '</span>' +
      '</button>'
    ).join('');
    // Wire click handlers
    grid.querySelectorAll('.suggestion-card').forEach(card => {
      card.addEventListener('click', () => {
        document.getElementById('input').value = card.dataset.text;
        if (typeof sendMessage === 'function') sendMessage();
      });
    });
  }

  hideWelcome() {
    this.welcomeEl.classList.add('hidden');
  }

  clear() {
    this.messagesEl.innerHTML = '';
    this.streamingEl = null;
    this.streamingText = '';
  }

  // Add a user message bubble (with optional images)
  addUserMessage(text, images) {
    this.hideWelcome();

    const row = document.createElement('div');
    row.className = 'message-row user';

    const bubble = document.createElement('div');
    bubble.className = 'bubble user';

    if (text && text.trim()) {
      bubble.innerHTML = this.renderMarkdown(text);
    }

    // Add images if present
    if (images && images.length > 0) {
      for (const img of images) {
        const imgEl = document.createElement('img');
        imgEl.src = img;
        imgEl.className = 'chat-image';
        imgEl.onclick = () => this.showLightbox(img);
        bubble.appendChild(imgEl);
      }
    }

    // Copy button
    const copyBtn = document.createElement('button');
    copyBtn.className = 'msg-copy-btn';
    copyBtn.innerHTML = '&#x2398;';
    copyBtn.title = L('chat.copyMsg');
    copyBtn.onclick = () => {
      navigator.clipboard.writeText(text || '').then(() => {
        copyBtn.innerHTML = '&#x2713;';
        copyBtn.title = L('chat.copyMsgDone');
        setTimeout(() => { copyBtn.innerHTML = '&#x2398;'; copyBtn.title = L('chat.copyMsg'); }, 1200);
      });
    };
    bubble.appendChild(copyBtn);

    const icon = document.createElement('div');
    icon.className = 'role-icon user';
    icon.textContent = 'U';

    // Grid order: bubble first, icon second (user = right-aligned)
    row.appendChild(bubble);
    row.appendChild(icon);
    this.messagesEl.appendChild(row);
    this.scrollToBottom();
    return row;
  }

  // Start streaming assistant message
  startAssistantMessage() {
    this.hideWelcome();
    this.hideTypingIndicator();

    const row = document.createElement('div');
    row.className = 'message-row assistant';

    const icon = document.createElement('div');
    icon.className = 'role-icon assistant';
    icon.textContent = 'A';

    const bubble = document.createElement('div');
    bubble.className = 'bubble assistant';

    const content = document.createElement('div');
    content.className = 'bubble-content streaming-cursor';
    bubble.appendChild(content);

    row.appendChild(icon);
    row.appendChild(bubble);
    this.messagesEl.appendChild(row);

    this.streamingEl = content;
    this.streamingText = '';
    this.scrollToBottom();
  }

  // Append streaming delta
  appendStreamDelta(type, content) {
    if (!this.streamingEl) this.startAssistantMessage();

    this.streamingType = type;
    this.streamingText += content;

    // Throttle markdown rendering to every 100ms
    if (!this.renderTimer) {
      this.renderTimer = setTimeout(() => {
        this._renderStreaming();
        this.renderTimer = null;
      }, 100);
    }

    // Also do a plain text update immediately for responsiveness
    this.streamingEl.textContent = this.streamingText;
    this.scrollToBottom();
  }

  _renderStreaming() {
    if (!this.streamingEl) return;
    this.streamingEl.innerHTML = this.renderMarkdown(this.streamingText);
    this.scrollToBottom();
  }

  // Finalize streaming message
  finalizeMessage(messageData) {
    if (this.renderTimer) {
      clearTimeout(this.renderTimer);
      this.renderTimer = null;
    }

    if (this.streamingEl) {
      this.streamingEl.classList.remove('streaming-cursor');
      // Use the full message content for final render
      if (messageData) {
        const text = this._extractText(messageData);
        if (text) {
          this.streamingEl.innerHTML = this.renderMarkdown(text);
        }
      } else {
        this.streamingEl.innerHTML = this.renderMarkdown(this.streamingText);
      }
    }

    this.streamingEl = null;
    this.streamingText = '';
    this.scrollToBottom();
  }

  // Add a tool call indicator
  addToolCall(name, callId, args) {
    this.hideWelcome();
    const row = document.createElement('div');
    row.className = 'message-row';

    const icon = document.createElement('div');
    icon.className = 'role-icon tool';
    icon.textContent = 'T';

    const bubble = document.createElement('div');
    bubble.className = 'bubble tool';
    bubble.innerHTML = `<strong>${L('chat.tool').replace('%s', this._escapeHtml(name))}</strong>` +
      (args ? `<pre>${this._escapeHtml(typeof args === 'string' ? args : JSON.stringify(args, null, 2))}</pre>` : '');

    row.appendChild(icon);
    row.appendChild(bubble);
    row.dataset.callId = callId;
    this.messagesEl.appendChild(row);
    this.scrollToBottom();
    return row;
  }

  // Update tool call with result
  updateToolResult(callId, name, result, isError) {
    const row = this.messagesEl.querySelector(`[data-call-id="${callId}"]`);
    if (row) {
      const bubble = row.querySelector('.bubble');
      const resultHtml = `<div style="margin-top:8px;border-top:1px solid var(--border);padding-top:8px;">` +
        `<strong>${isError ? L('status.error') : L('status.toolDoneShort')}:</strong>` +
        `<pre>${this._escapeHtml(result)}</pre></div>`;
      bubble.innerHTML += resultHtml;
      if (isError) {
        bubble.classList.remove('tool');
        bubble.classList.add('error');
      }
      this.scrollToBottom();
    }
  }

  // Show tool confirmation panel
  showToolConfirm(callId, name, filePath, diff, args) {
    const row = document.createElement('div');
    row.className = 'message-row';

    const icon = document.createElement('div');
    icon.className = 'role-icon tool';
    icon.textContent = '!';

    const panel = document.createElement('div');
    panel.className = 'confirm-panel';
    panel.dataset.callId = callId;

    let html = `<h4>Confirm: ${this._escapeHtml(name)}</h4>`;
    if (filePath) html += `<p>File: <code>${this._escapeHtml(filePath)}</code></p>`;
    if (diff) {
      html += `<pre>${diff.split('\n').map(line => {
        if (line.startsWith('+') && !line.startsWith('+++')) return `<span class="diff-added">${this._escapeHtml(line)}</span>`;
        if (line.startsWith('-') && !line.startsWith('---')) return `<span class="diff-removed">${this._escapeHtml(line)}</span>`;
        return this._escapeHtml(line);
      }).join('\n')}</pre>`;
    }

    html += `<div class="confirm-buttons">` +
      `<button class="btn-approve" data-call-id="${callId}" data-approved="true">${L('btn.approve')}</button>` +
      `<button class="btn-reject" data-call-id="${callId}" data-approved="false">${L('btn.reject')}</button>` +
      `</div>`;

    panel.innerHTML = html;
    row.appendChild(icon);
    row.appendChild(panel);
    this.messagesEl.appendChild(row);
    this.scrollToBottom();
  }

  // Add a system message
  addSystemMessage(text) {
    this.hideWelcome();
    const row = document.createElement('div');
    row.className = 'message-row';

    const bubble = document.createElement('div');
    bubble.className = 'bubble';
    bubble.style.background = 'transparent';
    bubble.style.border = 'none';
    bubble.style.color = 'var(--text-secondary)';
    bubble.style.fontSize = '13px';
    bubble.style.padding = '4px 0';
    bubble.textContent = text;

    // System messages: bubble spans both grid columns (no icon)
    bubble.style.gridColumn = '1 / -1';
    row.appendChild(bubble);
    this.messagesEl.appendChild(row);
    this.scrollToBottom();
  }

  // Show an error message with red styling
  showError(message) {
    this.hideWelcome();
    this.hideTypingIndicator();
    const row = document.createElement('div');
    row.className = 'message-row';

    const icon = document.createElement('div');
    icon.className = 'role-icon error';
    icon.textContent = '!';

    const bubble = document.createElement('div');
    bubble.className = 'bubble error';
    bubble.innerHTML = '<strong>' + L('status.error') + '</strong><br>' + this._escapeHtml(message);

    row.appendChild(icon);
    row.appendChild(bubble);
    this.messagesEl.appendChild(row);
    this.scrollToBottom();
  }

  // Load messages from session
  loadMessages(messages) {
    this.clear();
    this.hideWelcome();

    for (const msg of messages) {
      const role = msg.role || '';
      if (role === 'user') {
        const row = this._createUserRowFromMessage(msg);
        this.messagesEl.appendChild(row);
      } else if (role === 'assistant') {
        const row = this._createAssistantRowFromMessage(msg);
        if (row) this.messagesEl.appendChild(row);
      } else if (role === 'tool_result') {
        const text = this._extractText(msg);
        const isError = msg.isError || false;
        const row = document.createElement('div');
        row.className = 'message-row';
        const icon = document.createElement('div');
        icon.className = `role-icon ${isError ? 'error' : 'tool'}`;
        icon.textContent = isError ? '!' : 'T';
        const bubble = document.createElement('div');
        bubble.className = `bubble ${isError ? 'error' : 'tool'}`;
        const content = document.createElement('div');
        content.className = 'bubble-content';
        content.innerHTML = this.renderMarkdown(text);
        bubble.appendChild(content);
        row.appendChild(icon);
        row.appendChild(bubble);
        this.messagesEl.appendChild(row);
      }
    }
    this.scrollToBottom();
  }

  showTypingIndicator() {
    this.typingEl.classList.remove('hidden');
    this.scrollToBottom();
  }

  hideTypingIndicator() {
    this.typingEl.classList.add('hidden');
  }

  scrollToBottom() {
    const chatArea = document.getElementById('chat-area');
    requestAnimationFrame(() => {
      chatArea.scrollTop = chatArea.scrollHeight;
    });
  }

  // --- Markdown rendering ---
  renderMarkdown(text) {
    if (!text) return '';
    try {
      if (typeof marked !== 'undefined') {
        marked.setOptions({
          highlight: function(code, lang) {
            if (typeof hljs !== 'undefined') {
              if (lang && hljs.getLanguage(lang)) {
                return hljs.highlight(code, { language: lang }).value;
              }
              return hljs.highlightAuto(code).value;
            }
            return code;
          },
          breaks: true,
          gfm: true
        });

        let html = marked.parse(text);

        // Wrap code blocks with our custom structure
        html = html.replace(/<pre><code class="language-(\w+)">([\s\S]*?)<\/code><\/pre>/g,
          (match, lang, code) => {
            const id = 'code-' + Math.random().toString(36).substr(2, 9);
            return `<div class="code-block">` +
              `<div class="code-block-header"><span>${lang}</span><button class="code-copy-btn" onclick="chat.copyCode('${id}')">${L('chat.codeCopy')}</button></div>` +
              `<pre id="${id}">${code}</pre></div>`;
          });
        html = html.replace(/<pre><code>([\s\S]*?)<\/code><\/pre>/g,
          (match, code) => {
            const id = 'code-' + Math.random().toString(36).substr(2, 9);
            return `<div class="code-block">` +
              `<div class="code-block-header"><span>code</span><button class="code-copy-btn" onclick="chat.copyCode('${id}')">${L('chat.codeCopy')}</button></div>` +
              `<pre id="${id}">${code}</pre></div>`;
          });

        // Make markdown images clickable for lightbox
        html = html.replace(/<img([^>]*)>/g, (match, attrs) => {
          return `<img${attrs} onclick="chat.showLightbox(this.src)" style="max-width:100%;max-height:400px;border-radius:8px;cursor:pointer;">`;
        });

        return html;
      }
    } catch (e) {
      console.error('Markdown render error:', e);
    }
    return this._escapeHtml(text).replace(/\n/g, '<br>');
  }

  // Render content blocks from serialized message (includes images)
  renderContentBlocks(contentBlocks) {
    if (!contentBlocks || !Array.isArray(contentBlocks)) return '';
    let html = '';
    let textParts = [];

    for (const block of contentBlocks) {
      if (block.type === 'text' && block.text) {
        textParts.push(block.text);
      } else if (block.type === 'thinking' && block.thinking) {
        textParts.push('<details class="thinking-block"><summary>' + L('chat.thinking') + '</summary><div class="thinking-content">' +
          this._escapeHtml(block.thinking).replace(/\n/g, '<br>') + '</div></details>');
      } else if (block.type === 'image' && block.data) {
        // Flush accumulated text
        if (textParts.length > 0) {
          html += this.renderMarkdown(textParts.join('\n'));
          textParts = [];
        }
        // Render image from base64 data
        const src = block.data.startsWith('data:') ? block.data :
                    `data:${block.mimeType || 'image/png'};base64,${block.data}`;
        html += `<img src="${src}" class="chat-image" onclick="chat.showLightbox(this.src)">`;
      }
    }
    // Flush remaining text
    if (textParts.length > 0) {
      html += this.renderMarkdown(textParts.join('\n'));
    }
    return html;
  }

  copyCode(elementId) {
    const el = document.getElementById(elementId);
    if (el) {
      navigator.clipboard.writeText(el.textContent).then(() => {
        const btn = el.parentElement.querySelector('.code-copy-btn');
        if (btn) { btn.textContent = L('chat.codeCopied'); setTimeout(() => btn.textContent = L('chat.codeCopy'), 1200); }
      });
    }
  }

  // Show image in fullscreen lightbox
  showLightbox(src) {
    const lb = document.createElement('div');
    lb.id = 'image-lightbox';
    lb.innerHTML = `<img src="${src}">`;
    lb.addEventListener('click', () => lb.remove());
    document.body.appendChild(lb);
  }

  // --- Helpers ---

  _createAssistantRow(text) {
    const row = document.createElement('div');
    row.className = 'message-row assistant';

    const icon = document.createElement('div');
    icon.className = 'role-icon assistant';
    icon.textContent = 'A';

    const bubble = document.createElement('div');
    bubble.className = 'bubble assistant';

    const content = document.createElement('div');
    content.className = 'bubble-content';
    content.innerHTML = this.renderMarkdown(text);
    bubble.appendChild(content);

    const copyBtn = document.createElement('button');
    copyBtn.className = 'msg-copy-btn';
    copyBtn.innerHTML = '&#x2398;';
    copyBtn.title = L('chat.copyMsg');
    copyBtn.onclick = () => {
      navigator.clipboard.writeText(text).then(() => {
        copyBtn.innerHTML = '&#x2713;';
        copyBtn.title = L('chat.copyMsgDone');
        setTimeout(() => { copyBtn.innerHTML = '&#x2398;'; copyBtn.title = L('chat.copyMsg'); }, 1200);
      });
    };
    bubble.appendChild(copyBtn);

    row.appendChild(icon);
    row.appendChild(bubble);
    return row;
  }

  // Create user row from serialized message (may contain image content blocks)
  _createUserRowFromMessage(msg) {
    const row = document.createElement('div');
    row.className = 'message-row user';

    const bubble = document.createElement('div');
    bubble.className = 'bubble user';

    // Check for structured content blocks (text + images)
    if (msg.contentBlocks && Array.isArray(msg.contentBlocks) && msg.contentBlocks.length > 0) {
      bubble.innerHTML = this.renderContentBlocks(msg.contentBlocks);
    } else if (msg.content) {
      bubble.innerHTML = this.renderMarkdown(msg.content);
    }

    const copyBtn = document.createElement('button');
    copyBtn.className = 'msg-copy-btn';
    copyBtn.innerHTML = '&#x2398;';
    copyBtn.title = L('chat.copyMsg');
    copyBtn.onclick = () => {
      const text = msg.content || this._extractText(msg);
      navigator.clipboard.writeText(text).then(() => {
        copyBtn.innerHTML = '&#x2713;';
        copyBtn.title = L('chat.copyMsgDone');
        setTimeout(() => { copyBtn.innerHTML = '&#x2398;'; copyBtn.title = L('chat.copyMsg'); }, 1200);
      });
    };
    bubble.appendChild(copyBtn);

    const icon = document.createElement('div');
    icon.className = 'role-icon user';
    icon.textContent = 'U';

    // Grid order: bubble first, icon second (user = right-aligned)
    row.appendChild(bubble);
    row.appendChild(icon);
    return row;
  }

  // Create assistant row from serialized message (may contain image content blocks)
  _createAssistantRowFromMessage(msg) {
    const row = document.createElement('div');
    row.className = 'message-row assistant';

    const icon = document.createElement('div');
    icon.className = 'role-icon assistant';
    icon.textContent = 'A';

    const bubble = document.createElement('div');
    bubble.className = 'bubble assistant';

    const content = document.createElement('div');
    content.className = 'bubble-content';

    // Check for structured content blocks
    if (msg.contentBlocks && Array.isArray(msg.contentBlocks) && msg.contentBlocks.length > 0) {
      content.innerHTML = this.renderContentBlocks(msg.contentBlocks);
    } else {
      const text = this._extractAssistantText(msg);
      if (!text) return null;
      content.innerHTML = this.renderMarkdown(text);
    }

    bubble.appendChild(content);

    const copyBtn = document.createElement('button');
    copyBtn.className = 'msg-copy-btn';
    copyBtn.innerHTML = '&#x2398;';
    copyBtn.title = L('chat.copyMsg');
    copyBtn.onclick = () => {
      const text = this._extractAssistantText(msg) || '';
      navigator.clipboard.writeText(text).then(() => {
        copyBtn.innerHTML = '&#x2713;';
        copyBtn.title = L('chat.copyMsgDone');
        setTimeout(() => { copyBtn.innerHTML = '&#x2398;'; copyBtn.title = L('chat.copyMsg'); }, 1200);
      });
    };
    bubble.appendChild(copyBtn);

    row.appendChild(icon);
    row.appendChild(bubble);

    return row;
  }

  _createMessageRow(role, text) {
    const row = document.createElement('div');
    row.className = `message-row ${role}`;

    const icon = document.createElement('div');
    icon.className = `role-icon ${role}`;
    icon.textContent = role === 'user' ? 'U' : 'A';

    const bubble = document.createElement('div');
    bubble.className = `bubble ${role}`;
    bubble.innerHTML = this.renderMarkdown(text);

    // Copy button
    const copyBtn = document.createElement('button');
    copyBtn.className = 'msg-copy-btn';
    copyBtn.innerHTML = '&#x2398;';
    copyBtn.title = L('chat.copyMsg');
    copyBtn.onclick = () => {
      navigator.clipboard.writeText(text).then(() => {
        copyBtn.innerHTML = '&#x2713;';
        copyBtn.title = L('chat.copyMsgDone');
        setTimeout(() => { copyBtn.innerHTML = '&#x2398;'; copyBtn.title = L('chat.copyMsg'); }, 1200);
      });
    };
    bubble.appendChild(copyBtn);

    if (role === 'user') {
      row.appendChild(bubble);
      row.appendChild(icon);
    } else {
      row.appendChild(icon);
      row.appendChild(bubble);
    }
    return row;
  }

  _extractText(msg) {
    if (msg.content) return msg.content;
    if (msg.contentBlocks) {
      return msg.contentBlocks
        .filter(b => b.type === 'text')
        .map(b => b.text)
        .join('');
    }
    return '';
  }

  _extractAssistantText(msg) {
    if (msg.content) {
      if (typeof msg.content === 'string') return msg.content;
      if (Array.isArray(msg.content)) {
        // Join with '' (not '\n') — streaming chunks are continuous text.
        // Using '\n' with breaks:true causes every chunk boundary to become <br>,
        // inflating height. Each block already contains its own newlines if needed.
        return msg.content
          .filter(b => b.type === 'text' || b.type === 'thinking')
          .map(b => b.text || b.thinking || '')
          .join('');
      }
    }
    return '';
  }

  _escapeHtml(text) {
    if (!text) return '';
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
               .replace(/"/g, '&quot;').replace(/'/g, '&#039;');
  }
}

const chat = new ChatRenderer();
