// PiMono Sidebar - Session list management

class SidebarManager {
  constructor() {
    this.sessions = [];
    this.currentSessionId = '';
    this.expanded = true;
    this.contextSessionId = '';
    this.clickTimer = null;
    this.skills = [];
    this.expandedSkillId = null;

    this.listEl = document.getElementById('session-list');
    this.emptyEl = document.getElementById('sidebar-empty');
    this.skillTagsEl = document.getElementById('skill-tags');
  }

  setSessions(sessions, currentId) {
    this.sessions = sessions || [];
    this.currentSessionId = currentId || '';
    this.render();
  }

  setCurrentSession(sessionId) {
    this.currentSessionId = sessionId;
    this.render();
  }

  render() {
    this.listEl.innerHTML = '';

    if (this.sessions.length === 0) {
      this.emptyEl.classList.remove('hidden');
    } else {
      this.emptyEl.classList.add('hidden');
      for (const s of this.sessions) {
        const item = document.createElement('div');
        item.className = 'session-item' + (s.id === this.currentSessionId ? ' active' : '');
        item.dataset.id = s.id;
        let name = s.name || 'Untitled';
        if (s.parentId) name += ' [B]';
        item.textContent = name;
        item.title = name + ' (' + (s.messageCount || 0) + ' messages)';

        item.addEventListener('click', () => {
          // Use timer to distinguish single-click from double-click
          if (this.clickTimer) {
            clearTimeout(this.clickTimer);
            this.clickTimer = null;
            // Double-click: open in popup window
            this.openInPopup(s.id);
          } else {
            this.clickTimer = setTimeout(() => {
              this.clickTimer = null;
              this.selectSession(s.id);
            }, 300);
          }
        });
        item.addEventListener('contextmenu', (e) => this.showContextMenu(e, s.id));

        this.listEl.appendChild(item);
      }
    }
  }

  selectSession(id) {
    if (id === this.currentSessionId) return;
    bridge.send('load_session', { sessionId: id });
  }

  openInPopup(id) {
    bridge.send('open_session_popup', { sessionId: id });
  }

  showContextMenu(e, sessionId) {
    e.preventDefault();
    this.contextSessionId = sessionId;

    const menu = document.getElementById('context-menu');
    const overlay = document.getElementById('context-menu-overlay');

    menu.style.left = e.clientX + 'px';
    menu.style.top = e.clientY + 'px';
    menu.classList.remove('hidden');
    overlay.classList.remove('hidden');
  }

  hideContextMenu() {
    document.getElementById('context-menu').classList.add('hidden');
    document.getElementById('context-menu-overlay').classList.add('hidden');
  }

  setSkills(skills) {
    this.skills = skills || [];
    this.renderSkillTags();
  }

  renderSkillTags() {
    if (!this.skillTagsEl) return;
    this.skillTagsEl.innerHTML = '';

    if (this.skills.length === 0) {
      const panel = document.getElementById('skill-panel');
      if (panel) panel.style.display = 'none';
      return;
    }

    const panel = document.getElementById('skill-panel');
    if (panel) panel.style.display = '';

    for (const skill of this.skills) {
      const wrapper = document.createElement('div');
      wrapper.style.width = '100%';

      const tag = document.createElement('span');
      tag.className = 'skill-tag';
      tag.textContent = skill.name;
      tag.title = skill.description || skill.name;
      tag.addEventListener('click', () => {
        this.expandedSkillId = (this.expandedSkillId === skill.id) ? null : skill.id;
        this.renderSkillTags();
      });

      wrapper.appendChild(tag);

      if (this.expandedSkillId === skill.id) {
        const detail = document.createElement('div');
        detail.className = 'skill-detail';
        if (skill.description) {
          detail.innerHTML = '<div class="skill-detail-desc">' + this._esc(skill.description) + '</div>';
        }
        if (skill.content) {
          detail.innerHTML += '<div class="skill-detail-content">' + this._esc(skill.content) + '</div>';
        }
        if (!skill.description && !skill.content) {
          detail.innerHTML = '<div class="skill-detail-desc">' + L('sidebar.noSkillDetail') + '</div>';
        }
        wrapper.appendChild(detail);
      }

      this.skillTagsEl.appendChild(wrapper);
    }
  }

  _esc(text) {
    if (!text) return '';
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
               .replace(/"/g, '&quot;');
  }

  toggle() {
    this.expanded = !this.expanded;
    const sidebar = document.getElementById('sidebar');
    sidebar.classList.toggle('collapsed', !this.expanded);
  }
}

const sidebar = new SidebarManager();

// Context menu actions
document.getElementById('context-menu-overlay').addEventListener('click', () => sidebar.hideContextMenu());
document.querySelectorAll('#context-menu button').forEach(btn => {
  btn.addEventListener('click', () => {
    const action = btn.dataset.action;
    const id = sidebar.contextSessionId;
    sidebar.hideContextMenu();

    if (action === 'rename') {
      const session = sidebar.sessions.find(s => s.id === id);
      const newName = prompt(L('msg.selectRename'), session ? session.name : '');
      if (newName && newName.trim()) {
        bridge.send('rename_session', { sessionId: id, newName: newName.trim() });
      }
    } else if (action === 'delete') {
      if (confirm(L('msg.deleteConfirm'))) {
        bridge.send('delete_session', { sessionId: id });
      }
    }
  });
});
