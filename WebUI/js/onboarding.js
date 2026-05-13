// PiMono Onboarding Wizard - First-run setup experience

class OnboardingWizard {
  constructor() {
    this.currentStep = 0;
    this.providerPreset = null;
    this.apiKey = '';
    this.endpoint = '';
    this.modelName = '';
    this.fetchedModels = null;
    this.testResult = null;  // { success, error? }
    this.testing = false;

    this.providerPresets = {
      // --- International ---
      openai: {
        name: 'OpenAI',
        category: 'international',
        endpoint: 'https://api.openai.com/v1/',
        models: ['gpt-4o', 'gpt-4o-mini', 'o3-mini', 'gpt-4-turbo']
      },
      anthropic: {
        name: 'Anthropic',
        category: 'international',
        endpoint: 'https://api.anthropic.com/v1/',
        models: ['claude-sonnet-4-6', 'claude-haiku-4-5', 'claude-opus-4-6']
      },
      google: {
        name: 'Google Gemini',
        category: 'international',
        endpoint: 'https://generativelanguage.googleapis.com/v1beta/openai/',
        models: ['gemini-2.5-pro', 'gemini-2.5-flash', 'gemini-2.0-flash']
      },
      deepseek: {
        name: 'DeepSeek',
        category: 'international',
        endpoint: 'https://api.deepseek.com/v1/',
        models: ['deepseek-chat', 'deepseek-reasoner']
      },
      mistral: {
        name: 'Mistral',
        category: 'international',
        endpoint: 'https://api.mistral.ai/v1/',
        models: ['mistral-large-latest', 'mistral-medium-latest', 'mistral-small-latest']
      },
      groq: {
        name: 'Groq',
        category: 'international',
        endpoint: 'https://api.groq.com/openai/v1/',
        models: ['llama-3.3-70b-versatile', 'mixtral-8x7b-32768', 'gemma2-9b-it']
      },
      xai: {
        name: 'xAI (Grok)',
        category: 'international',
        endpoint: 'https://api.x.ai/v1/',
        models: ['grok-3', 'grok-3-mini']
      },
      cohere: {
        name: 'Cohere',
        category: 'international',
        endpoint: 'https://api.cohere.ai/v1/',
        models: ['command-r-plus', 'command-r']
      },
      // --- China ---
      moonshot: {
        name: 'Moonshot (Kimi)',
        category: 'china',
        endpoint: 'https://api.moonshot.cn/v1/',
        models: ['moonshot-v1-128k', 'moonshot-v1-32k', 'moonshot-v1-8k']
      },
      qwen: {
        name: 'Qwen',
        category: 'china',
        endpoint: 'https://dashscope.aliyuncs.com/compatible-mode/v1/',
        models: ['qwen-max', 'qwen-plus', 'qwen-turbo', 'qwen-long']
      },
      zhipu: {
        name: 'Zhipu (GLM)',
        category: 'china',
        endpoint: 'https://open.bigmodel.cn/api/paas/v4/',
        models: ['glm-4-plus', 'glm-4-flash', 'glm-4-long']
      },
      yi: {
        name: 'Yi (零一万物)',
        category: 'china',
        endpoint: 'https://api.lingyiwanwu.com/v1/',
        models: ['yi-large', 'yi-medium', 'yi-spark']
      },
      siliconflow: {
        name: 'SiliconFlow',
        category: 'china',
        endpoint: 'https://api.siliconflow.cn/v1/',
        models: ['deepseek-ai/DeepSeek-V3', 'Qwen/Qwen2.5-72B-Instruct', 'meta-llama/Meta-Llama-3.1-405B-Instruct']
      },
      minimax: {
        name: 'MiniMax',
        category: 'china',
        endpoint: 'https://api.minimax.chat/v1/',
        models: ['MiniMax-Text-01', 'abab-6.5s-chat']
      },
      baichuan: {
        name: 'Baichuan',
        category: 'china',
        endpoint: 'https://api.baichuan-ai.com/v1/',
        models: ['Baichuan4', 'Baichuan3-Turbo', 'Baichuan3-Turbo-128k']
      },
      spark: {
        name: 'iFlytek Spark',
        category: 'china',
        endpoint: 'https://spark-api-open.xf-yun.com/v1/',
        models: ['generalv3.5', 'generalv3', '4.0Ultra']
      },
      // --- Custom ---
      custom: {
        name: 'Custom / Other',
        category: 'custom',
        endpoint: '',
        models: []
      }
    };
  }

  start() {
    const overlay = document.getElementById('onboarding-overlay');
    if (!overlay) return;
    // Prevent double-start (can happen when JS is reloaded while onboarding is already open)
    if (!overlay.classList.contains('hidden')) return;
    this.currentStep = 0;
    this.providerPreset = null;
    this.apiKey = '';
    this.endpoint = '';
    this.modelName = '';
    this.fetchedModels = null;
    this.testResult = null;
    overlay.classList.remove('hidden');
    this.render();
  }

  close() {
    const overlay = document.getElementById('onboarding-overlay');
    if (overlay) overlay.classList.add('hidden');
  }

  next() {
    if (this.currentStep === 0 && !this.providerPreset) return;
    if (this.currentStep === 1 && !this.apiKey.trim()) return;

    this.currentStep++;
    if (this.currentStep > 2) {
      this.finish();
      return;
    }
    this.render();
  }

  back() {
    if (this.currentStep > 0) {
      this.currentStep--;
      this.render();
    }
  }

  skip() {
    this.close();
  }

  selectProvider(id) {
    this.providerPreset = id;
    const preset = this.providerPresets[id];
    this.endpoint = preset.endpoint;
    this.fetchedModels = null;
    this.render();
  }

  testConnection() {
    if (this.testing) return;
    this.testing = true;
    this.testResult = null;
    this.render();

    // Client-side timeout: if no response in 15s, reset testing state
    const timeoutId = setTimeout(() => {
      if (this.testing) {
        this.testing = false;
        this.testResult = { success: false, error: 'Connection timed out (15s). Check your endpoint URL and network.' };
        this.render();
      }
    }, 15000);

    bridge.send('test_connection', {
      endpoint: this.endpoint,
      apiKey: this.apiKey,
      _timeoutId: timeoutId  // pass to identify this request
    });
  }

  handleTestResult(data) {
    this.testing = false;
    if (data.success) {
      this.fetchedModels = data.models || [];
      this.testResult = { success: true };
    } else {
      this.fetchedModels = null;
      this.testResult = { success: false, error: data.error || 'Unknown error' };
    }
    this.render();
  }

  finish() {
    bridge.send('save_onboarding', {
      provider: this.providerPreset || 'custom',
      apiKey: this.apiKey,
      endpoint: this.endpoint,
      modelName: this.modelName
    });
  }

  render() {
    const content = document.getElementById('onboarding-content');
    if (!content) return;

    let html = '';

    // Step indicator
    html += '<div class="onboard-steps">';
    for (let i = 0; i < 3; i++) {
      html += `<div class="onboard-step-dot ${i === this.currentStep ? 'active' : (i < this.currentStep ? 'done' : '')}"></div>`;
    }
    html += '</div>';

    if (this.currentStep === 0) {
      html += this.renderProviderStep();
    } else if (this.currentStep === 1) {
      html += this.renderApiKeyStep();
    } else if (this.currentStep === 2) {
      html += this.renderModelStep();
    }

    content.innerHTML = html;
    this.bindEvents();
  }

  renderProviderStep() {
    let html = '<div class="onboard-title">Welcome to PiMono</div>';
    html += '<div class="onboard-subtitle">Choose your AI provider to get started</div>';

    // Group by category
    const categories = [
      { key: 'international', label: 'International' },
      { key: 'china', label: 'China' },
      { key: 'custom', label: 'Other' }
    ];

    for (const cat of categories) {
      html += `<div class="provider-category">${cat.label}</div>`;
      html += '<div class="provider-grid">';
      for (const [id, p] of Object.entries(this.providerPresets)) {
        if (p.category !== cat.key) continue;
        const selected = this.providerPreset === id ? 'selected' : '';
        html += `<div class="provider-card ${selected}" data-provider="${id}">`;
        html += `<div class="provider-name">${this._escapeHtml(p.name)}</div>`;
        html += '</div>';
      }
      html += '</div>';
    }

    return html;
  }

  renderApiKeyStep() {
    const presetName = this.providerPreset ? this.providerPresets[this.providerPreset].name : 'Custom';
    let html = '<div class="onboard-title">API Key</div>';
    html += `<div class="onboard-subtitle">Enter your ${this._escapeHtml(presetName)} API key</div>`;
    html += '<div class="onboard-field">';
    html += '<div class="onboard-input-with-toggle">';
    html += '<input type="password" id="onboard-apikey" class="onboard-input" placeholder="sk-..." value="' + this._escapeHtml(this.apiKey) + '">';
    html += '<button type="button" class="onboard-toggle-vis" id="btn-toggle-vis" title="Show/Hide API Key">';
    html += '<svg class="icon-eye" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>';
    html += '<svg class="icon-eye-off" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="display:none"><path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19m-6.72-1.07a3 3 0 11-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>';
    html += '</button>';
    html += '</div>';
    html += '</div>';
    html += '<div class="onboard-hint">Your API key is stored locally on your device and never sent to third parties.</div>';

    html += '<div class="onboard-field" style="margin-top:12px">';
    html += '<label class="onboard-label">Endpoint</label>';
    html += '<input type="text" id="onboard-endpoint" class="onboard-input" placeholder="https://api.example.com/v1/" value="' + this._escapeHtml(this.endpoint) + '">';
    html += '</div>';

    return html;
  }

  renderModelStep() {
    let html = '<div class="onboard-title">Select Model</div>';
    html += '<div class="onboard-subtitle">Choose a model to use</div>';

    let models = [];
    if (this.fetchedModels && this.fetchedModels.length > 0) {
      models = this.fetchedModels;
    } else if (this.providerPreset && this.providerPresets[this.providerPreset].models.length > 0) {
      models = this.providerPresets[this.providerPreset].models;
    }

    if (models.length > 0) {
      html += '<div class="model-list">';
      for (const m of models) {
        const selected = this.modelName === m ? 'selected' : '';
        const isFirst = !this.modelName && models.indexOf(m) === 0;
        const recommended = isFirst ? ' <span class="model-recommended">(Recommended)</span>' : '';
        html += `<div class="model-option ${selected}" data-model="${this._escapeHtml(m)}">`;
        html += `<span class="model-radio ${selected ? 'checked' : ''}"></span>`;
        html += `<span class="model-name">${this._escapeHtml(m)}${recommended}</span>`;
        html += '</div>';
      }
      html += '</div>';
    }

    html += '<div class="onboard-field" style="margin-top:12px">';
    html += '<label class="onboard-label">Or type a custom model name</label>';
    html += '<input type="text" id="onboard-model" class="onboard-input" placeholder="e.g. gpt-4o" value="' + this._escapeHtml(this.modelName) + '">';
    html += '</div>';

    // Test Connection button - optional, user clicks manually
    html += '<div class="onboard-test-section">';
    html += '<button class="onboard-test-btn" id="btn-test-connection"' + (this.testing ? ' disabled' : '') + '>';
    if (this.testing) {
      html += '<span class="onboard-spinner"></span> Testing...';
    } else {
      html += 'Test Connection';
    }
    html += '</button>';
    html += '<div class="onboard-test-hint">Optional: verify your API connection works</div>';

    // Show test result
    if (this.testResult !== null) {
      if (this.testResult.success) {
        html += '<div class="onboard-success">Connection successful!</div>';
      } else {
        html += `<div class="onboard-warn">Connection failed: ${this._escapeHtml(this.testResult.error)}</div>`;
      }
    }
    html += '</div>';

    return html;
  }

  bindEvents() {
    // Provider cards
    document.querySelectorAll('.provider-card').forEach(card => {
      card.addEventListener('click', () => {
        this.selectProvider(card.dataset.provider);
      });
    });

    // API key input
    const apiKeyInput = document.getElementById('onboard-apikey');
    if (apiKeyInput) {
      apiKeyInput.addEventListener('input', (e) => {
        this.apiKey = e.target.value;
        // Dynamically update Next button state
        const nextBtn = document.getElementById('btn-onboard-next');
        if (nextBtn && this.currentStep === 1) {
          nextBtn.disabled = !this.apiKey.trim();
        }
      });
      apiKeyInput.focus();
    }

    // Toggle API key visibility
    const toggleBtn = document.getElementById('btn-toggle-vis');
    if (toggleBtn && apiKeyInput) {
      toggleBtn.addEventListener('click', () => {
        const isPassword = apiKeyInput.type === 'password';
        apiKeyInput.type = isPassword ? 'text' : 'password';
        toggleBtn.querySelector('.icon-eye').style.display = isPassword ? 'none' : '';
        toggleBtn.querySelector('.icon-eye-off').style.display = isPassword ? '' : 'none';
      });
    }

    // Endpoint input (always visible now)
    const endpointInput = document.getElementById('onboard-endpoint');
    if (endpointInput) {
      endpointInput.addEventListener('input', (e) => {
        this.endpoint = e.target.value;
      });
    }

    // Test connection button
    const testBtn = document.getElementById('btn-test-connection');
    if (testBtn) {
      testBtn.addEventListener('click', () => this.testConnection());
    }

    // Model options
    document.querySelectorAll('.model-option').forEach(opt => {
      opt.addEventListener('click', () => {
        this.modelName = opt.dataset.model;
        const modelInput = document.getElementById('onboard-model');
        if (modelInput) modelInput.value = this.modelName;
        this.render();
      });
    });

    // Custom model input
    const modelInput = document.getElementById('onboard-model');
    if (modelInput) {
      modelInput.addEventListener('input', (e) => {
        this.modelName = e.target.value;
        document.querySelectorAll('.model-option').forEach(o => o.classList.remove('selected'));
      });
      // Auto-select first model if none selected
      if (!this.modelName) {
        const firstOption = document.querySelector('.model-option');
        if (firstOption) {
          this.modelName = firstOption.dataset.model;
          modelInput.value = this.modelName;
        }
      }
    }

    // Nav buttons
    const backBtn = document.getElementById('btn-onboard-back');
    const nextBtn = document.getElementById('btn-onboard-next');
    const skipBtn = document.getElementById('btn-onboard-skip');

    if (backBtn) {
      backBtn.style.display = this.currentStep > 0 ? '' : 'none';
    }
    if (nextBtn) {
      let canNext = true;
      if (this.currentStep === 0 && !this.providerPreset) canNext = false;
      if (this.currentStep === 1 && !this.apiKey.trim()) canNext = false;
      if (this.currentStep === 2 && !this.modelName.trim()) canNext = false;

      nextBtn.disabled = !canNext;
      nextBtn.textContent = this.currentStep === 2 ? 'Start Chatting' : 'Next';
    }
    if (skipBtn) {
      skipBtn.style.display = this.currentStep === 0 ? '' : 'none';
    }
  }

  _escapeHtml(text) {
    if (!text) return '';
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
               .replace(/"/g, '&quot;').replace(/'/g, '&#039;');
  }
}

const onboarding = new OnboardingWizard();
