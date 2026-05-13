// PiMono Settings - Unified Profiles-based settings

class SettingsManager {
  constructor() {
    this.config = {};
    this.currentTab = 'profiles';
    this.activeProfileIdx = -1;
    this.activeSkillIdx = -1;
  }

  open() {
    document.getElementById('settings-overlay').classList.remove('hidden');
    this.renderCurrentTab();
    bridge.send('get_config');
  }

  close() {
    document.getElementById('settings-overlay').classList.add('hidden');
    if (this._pendingTheme) {
      const savedTheme = this.config.theme || 'cyberpunk-neon';
      themeManager.apply(themeManager.normalizeName(savedTheme));
    }
    this._pendingTheme = null;
  }

  setConfig(config) {
    this.config = config;
    this.renderCurrentTab();
  }

  renderCurrentTab() {
    const content = document.getElementById('settings-content');
    switch (this.currentTab) {
      case 'profiles': content.innerHTML = this.renderProfilesTab(); break;
      case 'ui': content.innerHTML = this.renderUITab(); break;
      case 'paths': content.innerHTML = this.renderPathsTab(); break;
      case 'search': content.innerHTML = this.renderSearchTab(); break;
      case 'skills': content.innerHTML = this.renderSkillsTab(); break;
    }
  }

  // === PROFILES TAB (unified: endpoint/key/model + shared settings) ===

  renderProfilesTab() {
    const c = this.config;

    // Shared settings section (apply to all profiles)
    const sharedHtml = `
      <div style="margin-bottom:20px;padding-bottom:16px;border-bottom:1px solid var(--border)">
        <div style="font-family:var(--font-display);font-size:11px;color:var(--text-secondary);margin-bottom:12px;text-transform:uppercase">Shared Settings</div>
        <div class="form-row">
          <div class="form-group"><label>${L('settings.streaming')}</label>
            <div class="form-checkbox" style="margin:0"><input type="checkbox" id="s-streaming" ${c.streaming ? 'checked' : ''}><label for="s-streaming">Enable</label></div>
          </div>
          <div class="form-group"><label>${L('settings.timeout')}</label><input class="form-input" id="s-timeout" type="number" value="${c.timeout || 30}"></div>
          <div class="form-group"><label>${L('settings.retryCount')}</label><input class="form-input" id="s-retryCount" type="number" value="${c.retryCount || 3}"></div>
        </div>
        <div class="form-group"><label>${L('settings.modelsEndpoint')}</label><input class="form-input" id="s-modelsEndpoint" value="${this._esc(c.modelsEndpoint)}"></div>
      </div>`;

    // Profile list + detail panel
    const profiles = this.config.profiles || [];
    const listHtml = profiles.map((p, i) =>
      `<div class="list-item ${i === this.activeProfileIdx ? 'active' : ''}" onclick="settings.selectProfile(${i})">${this._esc(p.displayName)}</div>`
    ).join('');

    let detailHtml = '';
    if (this.activeProfileIdx >= 0 && this.activeProfileIdx < profiles.length) {
      const p = profiles[this.activeProfileIdx];
      detailHtml = `
        <div class="form-group"><label>${L('settings.profileDisplayName')}</label><input class="form-input" id="s-profileName" value="${this._esc(p.displayName)}" onchange="settings.updateProfileField('displayName', this.value)"></div>
        <div class="form-group"><label>${L('settings.profileEndpoint')}</label><input class="form-input" id="s-profileEndpoint" value="${this._esc(p.endpoint)}" onchange="settings.updateProfileField('endpoint', this.value)"></div>
        <div class="form-group"><label>${L('settings.profileApiKey')}</label><input class="form-input" id="s-profileApiKey" type="password" value="${this._esc(p.apiKey || '')}" onchange="settings.updateProfileField('apiKey', this.value)"></div>
        <div class="form-group"><label>${L('settings.profileModelName')}</label><input class="form-input" id="s-profileModel" value="${this._esc(p.modelName)}" onchange="settings.updateProfileField('modelName', this.value)"></div>
        <div class="form-row">
          <div class="form-group"><label>${L('settings.profileMaxTokens')}</label><input class="form-input" id="s-profileMaxTokens" type="number" value="${p.maxTokens}" onchange="settings.updateProfileField('maxTokens', parseInt(this.value)||8192)"></div>
          <div class="form-group"><label>${L('settings.profileTemperature')}</label><input class="form-input" id="s-profileTemp" type="number" step="0.1" value="${p.temperature}" onchange="settings.updateProfileField('temperature', parseFloat(this.value)||0.7)"></div>
        </div>
        <div class="form-row">
          <div class="form-group"><label>Top P</label><input class="form-input" id="s-profileTopP" type="number" step="0.1" value="${p.topP !== undefined ? p.topP : (c.topP || 1.0)}" onchange="settings.updateProfileField('topP', parseFloat(this.value)||1.0)"><div style="font-size:10px;color:var(--text-secondary);margin-top:2px">${L('settings.topPHint') || 'Default 1.0, controls sampling range'}</div></div>
          <div class="form-group"><label>${L('settings.thinkingLevel')}</label>
            <select class="form-input" id="s-profileThinking" onchange="settings.updateProfileField('thinkingLevel', this.value)">
              <option value="off" ${(p.thinkingLevel||'')==='off'?'selected':''}>Off</option>
              <option value="minimal" ${(p.thinkingLevel||'')==='minimal'?'selected':''}>Minimal</option>
              <option value="low" ${(p.thinkingLevel||'')==='low'?'selected':''}>Low</option>
              <option value="medium" ${(p.thinkingLevel||'')==='medium'?'selected':''}>Medium</option>
              <option value="high" ${(p.thinkingLevel||'')==='high'?'selected':''}>High</option>
            </select>
            <div style="font-size:10px;color:var(--text-secondary);margin-top:2px">${L('settings.thinkingHint') || 'Only for reasoning models'}</div>
          </div>
        </div>`;
    }

    return sharedHtml + `
      <div class="list-panel">
        <div class="list-left"><div class="list-actions"><button onclick="settings.addProfile()">${L('settings.addProfile')}</button><button onclick="settings.deleteProfile()">${L('settings.deleteProfile')}</button><button onclick="settings.setActiveProfile()">${L('settings.setActive')}</button></div>${listHtml}</div>
        <div class="list-right">${detailHtml || '<p style="color:var(--text-secondary)">' + L('settings.tabProfiles') + '</p>'}</div>
      </div>`;
  }

  // === UI TAB ===

  renderUITab() {
    const c = this.config;
    const themes = themeManager.getThemeList();
    const currentTheme = this._pendingTheme || themeManager.normalizeName(c.theme || 'cyberpunk-neon');

    const themeCards = themes.map(t => `
      <div class="theme-card ${t.id === currentTheme ? 'active' : ''}"
           data-theme-id="${t.id}" onclick="settings.selectTheme('${t.id}')">
        <div class="theme-preview">
          <div class="theme-swatch" style="background:${t.preview.bg}">
            <div class="theme-accent-bar" style="background:${t.preview.accent}"></div>
            <div class="theme-secondary-bar" style="background:${t.preview.secondary}"></div>
          </div>
        </div>
        <div class="theme-info">
          <div class="theme-name">${t.name}</div>
          <div class="theme-desc">${t.description}</div>
        </div>
        ${t.id === currentTheme ? '<div class="theme-active-badge">Active</div>' : ''}
      </div>
    `).join('');

    return `
      <div class="theme-card-grid">${themeCards}</div>
      <div class="form-row">
        <div class="form-group"><label>${L('settings.fontSize')}</label><input class="form-input" id="s-fontSize" type="number" value="${c.fontSize || 12}"></div>
        <div class="form-group"><label>${L('settings.fontFamily')}</label><input class="form-input" id="s-fontFamily" value="${this._esc(c.fontFamily || 'Segoe UI')}"></div>
      </div>
      <div class="form-group"><label>${L('settings.language')}</label>
        <select class="form-input" id="s-language">
          <option value="en" ${c.language==='en'?'selected':''}>${L('settings.langEn')}</option>
          <option value="zh" ${c.language==='zh'?'selected':''}>${L('settings.langZh')}</option>
        </select>
      </div>`;
  }

  // === PATHS TAB ===

  renderPathsTab() {
    const c = this.config;
    return `
      <div class="form-group"><label>${L('settings.workingDir')}</label>
        <div class="form-inline"><input class="form-input" id="s-workingDir" value="${this._esc(c.workingDir)}"><button class="form-btn-browse" onclick="settings.browseDirectory('workingDir')">${L('settings.browse')}</button></div>
      </div>
      <div class="form-group"><label>${L('settings.backupDir')}</label>
        <div class="form-inline"><input class="form-input" id="s-backupDir" value="${this._esc(c.backupDir)}"><button class="form-btn-browse" onclick="settings.browseDirectory('backupDir')">${L('settings.browse')}</button></div>
      </div>`;
  }

  // === SEARCH TAB ===

  renderSearchTab() {
    const c = this.config;
    const providers = ['None','Google','DuckDuckGo','SearXNG','Brave','Serper','Tavily','You.com','Exa','Firecrawl','Linkup','Perplexity','Moonshot'];
    const providerOptions = providers.map(p => `<option value="${p}" ${c.searchProvider===p?'selected':''}>${p}</option>`).join('');
    return `
      <div class="form-checkbox"><input type="checkbox" id="s-searchEnabled" ${c.searchEnabled?'checked':''}><label for="s-searchEnabled">${L('settings.searchEnabled')}</label></div>
      <div class="form-group"><label>${L('settings.searchProvider')}</label><select class="form-input" id="s-searchProvider">${providerOptions}</select></div>
      <div class="form-group"><label>${L('settings.searchApiKey')}</label><input class="form-input" id="s-searchApiKey" value="${this._esc(c.searchApiKey || '')}"></div>
      <div class="form-group"><label>${L('settings.searchCustomId')}</label><input class="form-input" id="s-searchCustomId" value="${this._esc(c.searchCustomId || '')}"></div>
      <div class="form-row">
        <div class="form-group"><label>${L('settings.searchMaxResults')}</label><input class="form-input" id="s-searchMaxResults" type="number" value="${c.searchMaxResults || 5}"></div>
        <div class="form-group"><label>${L('settings.searchTimeout')}</label><input class="form-input" id="s-searchTimeout" type="number" value="${c.searchTimeout || 10}"></div>
      </div>`;
  }

  // === SKILLS TAB ===

  renderSkillsTab() {
    const skills = this.config.skills || [];
    const listHtml = skills.map((s, i) =>
      `<div class="list-item ${i === this.activeSkillIdx ? 'active' : ''}" onclick="settings.selectSkill(${i})">${this._esc(s.name)}</div>`
    ).join('');

    let detailHtml = '';
    if (this.activeSkillIdx >= 0 && this.activeSkillIdx < skills.length) {
      const s = skills[this.activeSkillIdx];
      detailHtml = `
        <div class="form-group"><label>${L('settings.skillName') || 'Name'}</label><input class="form-input" id="s-skillName" value="${this._esc(s.name)}" onchange="settings.updateSkillField('name', this.value)"></div>
        <div class="form-group"><label>${L('settings.skillDescription') || 'Description'}</label><input class="form-input" id="s-skillDesc" value="${this._esc(s.description)}" onchange="settings.updateSkillField('description', this.value)"></div>
        <div class="form-group"><label>${L('settings.skillContent') || 'Prompt Content'}</label><textarea class="form-input" id="s-skillContent" rows="10" style="resize:vertical;font-family:var(--font-mono);font-size:13px" onchange="settings.updateSkillField('content', this.value)">${this._esc(s.content || '')}</textarea></div>`;
    }

    return `
      <div class="list-panel">
        <div class="list-left"><div class="list-actions"><button onclick="settings.addSkill()">${L('settings.skillNew')}</button><button onclick="settings.deleteSkill()">${L('settings.skillDelete')}</button></div>${listHtml}</div>
        <div class="list-right">${detailHtml || '<p style="color:var(--text-secondary)">' + L('settings.tabSkills') + '</p>'}</div>
      </div>`;
  }

  // === ACTIONS ===

  selectProfile(idx) { this.activeProfileIdx = idx; this.renderCurrentTab(); }
  selectSkill(idx) { this.activeSkillIdx = idx; this.renderCurrentTab(); }

  selectTheme(themeId) {
    this._pendingTheme = themeId;
    themeManager.apply(themeId);
    this.renderCurrentTab();
  }

  addProfile() {
    if (!this.config.profiles) this.config.profiles = [];
    const idx = this.config.profiles.length + 1;
    const id = 'profile_' + Date.now();
    this.config.profiles.push({
      id: id,
      displayName: 'Profile ' + idx,
      endpoint: '',
      apiKey: '',
      modelName: '',
      maxTokens: 8192,
      temperature: 0.7
    });
    this.activeProfileIdx = this.config.profiles.length - 1;
    this.renderCurrentTab();
  }

  deleteProfile() {
    if (this.activeProfileIdx < 0 || !this.config.profiles) return;
    this.config.profiles.splice(this.activeProfileIdx, 1);
    if (this.activeProfileIdx >= this.config.profiles.length)
      this.activeProfileIdx = this.config.profiles.length - 1;
    this.renderCurrentTab();
  }

  updateProfileField(field, value) {
    if (this.activeProfileIdx < 0 || !this.config.profiles) return;
    this.config.profiles[this.activeProfileIdx][field] = value;
  }

  setActiveProfile() {
    if (this.activeProfileIdx >= 0 && this.config.profiles) {
      const p = this.config.profiles[this.activeProfileIdx];
      if (p) bridge.send('change_model', { profileId: p.id });
    }
  }

  addSkill() {
    if (!this.config.skills) this.config.skills = [];
    const id = 'skill_' + Date.now();
    this.config.skills.push({
      id: id,
      name: 'New Skill',
      description: '',
      content: ''
    });
    this.activeSkillIdx = this.config.skills.length - 1;
    this.renderCurrentTab();
  }

  deleteSkill() {
    if (this.activeSkillIdx < 0 || !this.config.skills) return;
    this.config.skills.splice(this.activeSkillIdx, 1);
    if (this.activeSkillIdx >= this.config.skills.length)
      this.activeSkillIdx = this.config.skills.length - 1;
    this.renderCurrentTab();
  }

  updateSkillField(field, value) {
    if (this.activeSkillIdx < 0 || !this.config.skills) return;
    this.config.skills[this.activeSkillIdx][field] = value;
  }

  browseDirectory(field) {
    bridge.send('browse_directory', { field: field });
  }

  save() {
    const settings = {};

    // Shared settings from Profiles tab
    const sharedFields = ['modelsEndpoint','workingDir','backupDir',
      'fontFamily','thinkingLevel','theme','language','searchProvider','searchApiKey','searchCustomId'];
    for (const f of sharedFields) {
      const el = document.getElementById('s-' + f);
      if (el) settings[f] = el.value;
    }

    const numFields = ['timeout','retryCount','fontSize','searchMaxResults','searchTimeout'];
    for (const f of numFields) {
      const el = document.getElementById('s-' + f);
      if (el) settings[f] = parseInt(el.value) || 0;
    }

    const checkFields = { streaming: 's-streaming', searchEnabled: 's-searchEnabled' };
    for (const [key, id] of Object.entries(checkFields)) {
      const el = document.getElementById(id);
      if (el) settings[key] = el.checked;
    }

    if (this._pendingTheme) {
      settings.theme = this._pendingTheme;
      this._pendingTheme = null;
    }

    bridge.send('save_settings', { settings });

    // Send profiles update
    if (this.config.profiles) {
      bridge.send('update_profiles', {
        profiles: this.config.profiles,
        activeId: this.config.activeModelId || ''
      });
    }

    // Send skills update
    if (this.config.skills) {
      bridge.send('update_skills', {
        skills: this.config.skills
      });
    }

    this.close();
  }

  _esc(text) {
    if (!text) return '';
    return text.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
}

const settings = new SettingsManager();
