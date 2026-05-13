// PiMono App - Main application wiring

(function() {
  'use strict';

  // --- State ---
  let isStreaming = false;

  // --- Wire bridge events from Delphi ---

  bridge.on('initial_state', (data) => {
    console.log('Initial state received');

    // Apply theme via ThemeManager
    if (data.theme) {
      themeManager.apply(data.theme);
    }
    if (data.fontSize) {
      document.documentElement.style.setProperty('--font-size', data.fontSize + 'px');
    }
    if (data.fontFamily) {
      document.documentElement.style.setProperty('--font-family', data.fontFamily);
    }

    // Popup window mode: hide sidebar
    if (data.isPopupWindow) {
      const sidebar = document.getElementById('sidebar');
      if (sidebar) sidebar.classList.add('hidden');
      const toggleBtn = document.getElementById('btn-toggle-sidebar');
      if (toggleBtn) toggleBtn.classList.add('hidden');
      const newChatBtn = document.getElementById('btn-new-chat');
      if (newChatBtn) newChatBtn.classList.add('hidden');
    }

    // Update status
    if (data.gitBranch) {
      document.getElementById('status-text').textContent =
        L('status.readyBranch').replace('%s', data.gitBranch);
    } else {
      document.getElementById('status-text').textContent = L('status.ready');
    }

    // Populate model combo
    if (data.profiles) {
      const combo = document.getElementById('cmb-model');
      combo.innerHTML = '';
      data.profiles.forEach(p => {
        const opt = document.createElement('option');
        opt.value = p.id;
        opt.textContent = p.displayName;
        if (p.id === data.activeModelId) opt.selected = true;
        combo.appendChild(opt);
      });
    }

    // Onboarding: show wizard if API is not configured
    bridge.send('diag_check', {
      isConfigured: data.isConfigured,
      type: typeof data.isConfigured,
      strictFalse: data.isConfigured === false,
      looseFalse: data.isConfigured == false
    });
    if (data.isConfigured === false) {
      onboarding.start();
    }

    // Seed settings config so language/theme are correct before user opens settings
    settings.setConfig(data);

    // Render skill tags in sidebar
    if (data.skills) {
      sidebar.setSkills(data.skills);
    }
  });

  bridge.on('localization', (data) => {
    // Store all localization data into the global dictionary
    // (data contains 'event' key plus all localization key-value pairs)
    var count = 0;
    for (const key of Object.keys(data)) {
      if (key !== 'event') {
        window.__loc[key] = data[key];
        count++;
      }
    }
    console.log('[DIAG] localization event: stored ' + count + ' keys, status.ready=' + L('status.ready') + ', welcome.title=' + L('welcome.title'));

    // Apply localization to static UI elements
    const newChatSpan = document.querySelector('#btn-new-chat span');
    if (newChatSpan) newChatSpan.textContent = L('sidebar.newChat');

    const welcomeTitle = document.getElementById('welcome-title');
    if (welcomeTitle) welcomeTitle.textContent = L('welcome.title');

    const welcomeSubtitle = document.getElementById('welcome-subtitle');
    if (welcomeSubtitle) welcomeSubtitle.textContent = L('welcome.subtitle');

    const inputEl = document.getElementById('input');
    if (inputEl) inputEl.placeholder = L('chat.placeholder');

    const sidebarEmpty = document.getElementById('sidebar-empty');
    if (sidebarEmpty) sidebarEmpty.textContent = L('sidebar.empty');

    // Update status bar with localized text
    const statusText = document.getElementById('status-text');
    if (statusText) statusText.textContent = L('status.ready');

    // Update settings tab labels
    document.querySelectorAll('.settings-tab').forEach(tab => {
      const tabKey = 'settings.tab' + tab.dataset.tab.charAt(0).toUpperCase() + tab.dataset.tab.slice(1);
      if (window.__loc[tabKey]) {
        tab.textContent = L(tabKey);
      }
    });

    // Update settings button labels
    const saveBtn = document.getElementById('btn-settings-save');
    if (saveBtn) saveBtn.textContent = L('settings.save');
    const cancelBtn = document.getElementById('btn-settings-cancel');
    if (cancelBtn) cancelBtn.textContent = L('settings.cancel');
    const menuBtn = document.getElementById('btn-menu');
    if (menuBtn) menuBtn.title = L('btn.settings');

    // Re-render welcome suggestion cards with new language
    if (typeof chat !== 'undefined' && chat.renderSuggestions) chat.renderSuggestions();

    // Update context menu buttons
    document.querySelectorAll('#context-menu button').forEach(btn => {
      const key = 'context.' + btn.dataset.action;
      if (window.__loc[key]) btn.textContent = L(key);
    });

    // Update skill panel label
    const skillLabel = document.querySelector('.skill-label');
    if (skillLabel && window.__loc['skills.label']) skillLabel.textContent = L('skills.label');
  });

  bridge.on('theme_colors', (data) => {
    // Theme colors are now defined in CSS (themes.css).
    // This handler is kept as a no-op for backward compatibility with older Delphi builds.
  });

  bridge.on('session_list', (data) => {
    sidebar.setSessions(data.sessions, data.currentSessionId);
  });

  bridge.on('session_loaded', (data) => {
    sidebar.setCurrentSession(data.sessionId);
    chat.loadMessages(data.messages);
  });

  bridge.on('new_session_created', (data) => {
    sidebar.setCurrentSession(data.sessionId);
    chat.clear();
    chat.showWelcome();
  });

  bridge.on('show_welcome', () => {
    chat.showWelcome();
  });

  // Agent events
  bridge.on('agent_start', () => {
    isStreaming = true;
    chat.showTypingIndicator();
    document.getElementById('btn-send').classList.add('hidden');
    document.getElementById('btn-stop').classList.remove('hidden');
  });

  bridge.on('stream_delta', (data) => {
    chat.appendStreamDelta(data.type, data.content);
  });

  bridge.on('message_end', (data) => {
    chat.finalizeMessage(data.message);
  });

  bridge.on('tool_start', (data) => {
    chat.addToolCall(data.name, data.callId, data.args);
    document.getElementById('status-text').textContent = L('status.executingTool') + data.name;
  });

  bridge.on('tool_end', (data) => {
    chat.updateToolResult(data.callId, data.name, data.result, data.error);
    document.getElementById('status-text').textContent = data.error ?
      L('status.toolFailedShort') + data.name : L('status.toolDoneShort') + data.name;
  });

  bridge.on('tool_confirm', (data) => {
    chat.showToolConfirm(data.callId, data.name, data.filePath, data.diff, data.args);
  });

  bridge.on('agent_end', () => {
    isStreaming = false;
    chat.hideTypingIndicator();
    chat.finalizeMessage(null);
    document.getElementById('btn-stop').classList.add('hidden');
    document.getElementById('btn-send').classList.remove('hidden');
    document.getElementById('status-text').textContent = L('status.ready');
  });

  bridge.on('agent_error', (data) => {
    chat.showError(data.message || L('status.error'));
    document.getElementById('status-text').textContent = L('status.error');
  });

  bridge.on('status', (data) => {
    document.getElementById('status-text').textContent = data.text;
  });

  bridge.on('config_data', (data) => {
    console.log('[DIAG] config_data received, language=' + data.language + ', theme=' + data.theme);
    settings.setConfig(data);
    if (data.skills) {
      sidebar.setSkills(data.skills);
    }
  });

  bridge.on('browse_result', (data) => {
    const el = document.getElementById('s-' + data.field);
    if (el) el.value = data.path;
  });

  bridge.on('settings_saved', () => {
    console.log('[DIAG] settings_saved received, requesting get_config');
    bridge.send('get_config');
  });

  bridge.on('settings_applied', (data) => {
    // Apply font changes
    if (data.fontSize) {
      document.documentElement.style.setProperty('--font-size', data.fontSize + 'px');
    }
    if (data.fontFamily) {
      document.documentElement.style.setProperty('--font-family', data.fontFamily);
    }
    // Update model combo
    if (data.profiles) {
      const combo = document.getElementById('cmb-model');
      combo.innerHTML = '';
      data.profiles.forEach(p => {
        const opt = document.createElement('option');
        opt.value = p.id;
        opt.textContent = p.displayName;
        if (p.id === data.activeModelId) opt.selected = true;
        combo.appendChild(opt);
      });
    }
  });

  bridge.on('model_changed', (data) => {
    chat.addSystemMessage(L('settings.activeModel').replace('%s', data.name));
  });

  bridge.on('export_done', (data) => {
    chat.addSystemMessage(L('msg.exportedTo') + data.path);
  });

  bridge.on('test_connection_result', (data) => {
    onboarding.handleTestResult(data);
  });

  bridge.on('onboarding_complete', () => {
    onboarding.close();
    // Refresh model combo with new profile
    bridge.send('get_config');
  });

  // --- Wire user actions ---

  // Pending images for next message (base64 data URLs)
  let pendingImages = [];

  // Onboarding nav buttons
  document.getElementById('btn-onboard-next').addEventListener('click', () => {
    onboarding.next();
  });
  document.getElementById('btn-onboard-back').addEventListener('click', () => {
    onboarding.back();
  });
  document.getElementById('btn-onboard-skip').addEventListener('click', () => {
    onboarding.skip();
  });

  // Send message
  document.getElementById('btn-send').addEventListener('click', sendMessage);
  document.getElementById('input').addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  });

  function sendMessage() {
    const input = document.getElementById('input');
    const text = input.value.trim();
    const images = pendingImages.slice(); // copy
    if ((!text && images.length === 0) || isStreaming) return;

    // Show user message in chat (with images)
    chat.addUserMessage(text || '', images);
    input.value = '';
    input.style.height = 'auto';
    clearPendingImages();

    if (images.length > 0) {
      // Send message with image attachments
      bridge.send('send_message', {
        content: text || '',
        images: images
      });
    } else {
      bridge.send('send_message', { content: text });
    }
  }

  // Handle image paste
  document.getElementById('input').addEventListener('paste', (e) => {
    const items = e.clipboardData && e.clipboardData.items;
    if (!items) return;

    for (const item of items) {
      if (item.type.startsWith('image/')) {
        e.preventDefault();
        const file = item.getAsFile();
        if (!file) continue;

        const reader = new FileReader();
        reader.onload = (ev) => {
          pendingImages.push(ev.target.result); // data URL
          renderPendingImages();
        };
        reader.readAsDataURL(file);
      }
    }
  });

  // Handle drag-and-drop images onto input
  const inputCard = document.getElementById('input-card');
  inputCard.addEventListener('dragover', (e) => {
    e.preventDefault();
    e.stopPropagation();
    inputCard.style.borderColor = 'var(--accent)';
  });
  inputCard.addEventListener('dragleave', (e) => {
    e.preventDefault();
    e.stopPropagation();
    inputCard.style.borderColor = '';
  });
  inputCard.addEventListener('drop', (e) => {
    e.preventDefault();
    e.stopPropagation();
    inputCard.style.borderColor = '';

    const files = e.dataTransfer && e.dataTransfer.files;
    if (!files) return;

    for (const file of files) {
      if (file.type.startsWith('image/')) {
        const reader = new FileReader();
        reader.onload = (ev) => {
          pendingImages.push(ev.target.result);
          renderPendingImages();
        };
        reader.readAsDataURL(file);
      }
    }
  });

  function renderPendingImages() {
    const container = document.getElementById('image-attachments');
    container.innerHTML = '';
    for (let i = 0; i < pendingImages.length; i++) {
      const preview = document.createElement('div');
      preview.className = 'paste-preview';
      preview.innerHTML = `<img src="${pendingImages[i]}"><button class="paste-preview-remove" data-index="${i}">&times;</button>`;
      container.appendChild(preview);
    }
    // Wire remove buttons
    container.querySelectorAll('.paste-preview-remove').forEach(btn => {
      btn.addEventListener('click', () => {
        pendingImages.splice(parseInt(btn.dataset.index), 1);
        renderPendingImages();
      });
    });
  }

  function clearPendingImages() {
    pendingImages = [];
    const container = document.getElementById('image-attachments');
    if (container) container.innerHTML = '';
  }

  // Stop button
  document.getElementById('btn-stop').addEventListener('click', () => {
    bridge.send('abort');
  });

  // New chat
  document.getElementById('btn-new-chat').addEventListener('click', () => {
    if (isStreaming) return;
    bridge.send('new_session');
  });

  // Toggle sidebar
  document.getElementById('btn-toggle-sidebar').addEventListener('click', () => {
    sidebar.toggle();
  });

  // Model combo
  document.getElementById('cmb-model').addEventListener('change', (e) => {
    bridge.send('change_model', { profileId: e.target.value });
  });

  // Menu button - show simple menu options via settings
  document.getElementById('btn-menu').addEventListener('click', () => {
    // For now, open settings directly
    settings.open();
  });

  // Settings tabs
  document.querySelectorAll('.settings-tab').forEach(tab => {
    tab.addEventListener('click', () => {
      document.querySelectorAll('.settings-tab').forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      settings.currentTab = tab.dataset.tab;
      settings.renderCurrentTab();
    });
  });

  // Settings buttons
  document.getElementById('btn-settings-save').addEventListener('click', () => settings.save());
  document.getElementById('btn-settings-cancel').addEventListener('click', () => settings.close());
  document.getElementById('settings-close').addEventListener('click', () => settings.close());

  // Close settings on overlay click
  document.getElementById('settings-overlay').addEventListener('click', (e) => {
    if (e.target.id === 'settings-overlay') settings.close();
  });

  // Suggestion cards (dynamically rendered by chat.renderSuggestions)

  // Auto-resize textarea
  document.getElementById('input').addEventListener('input', function() {
    this.style.height = 'auto';
    this.style.height = Math.min(this.scrollHeight, 200) + 'px';
  });

  // Keyboard shortcuts
  document.addEventListener('keydown', (e) => {
    if (e.ctrlKey || e.metaKey) {
      switch (e.key) {
        case 'n': e.preventDefault(); bridge.send('new_session'); break;
        case ',': e.preventDefault(); settings.open(); break;
        case 'q': e.preventDefault(); bridge.send('quit'); break;
      }
    }
    if (e.key === 'Escape' && isStreaming) {
      bridge.send('abort');
    }
    if (e.key === 'Escape' && !document.getElementById('settings-overlay').classList.contains('hidden')) {
      settings.close();
    }
  });

  console.log('PiMono App initialized');

  // Hide loading screen with fade-out
  var loadingScreen = document.getElementById('loading-screen');
  if (loadingScreen) {
    loadingScreen.classList.add('fade-out');
    setTimeout(function() { loadingScreen.remove(); }, 500);
  }

  // Signal to Delphi that the page is ready
  bridge.send('page_ready');
})();
