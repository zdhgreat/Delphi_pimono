// PiMono Theme Manager — Multi-theme support

class ThemeManager {
  constructor() {
    this.THEMES = {
      'cyberpunk-neon': {
        name: 'Cyberpunk Neon',
        description: 'Deep space black with neon cyan and magenta',
        dark: true,
        preview: { bg: '#0A0E17', accent: '#00F0FF', secondary: '#FF0066' },
        fonts: ['Orbitron:wght@400;700;900', 'Share+Tech+Mono']
      },
      'classic-dark': {
        name: 'Classic Dark',
        description: 'IDE developer tool, compact code-editor layout',
        dark: true,
        preview: { bg: '#1E1E2E', accent: '#89B4FA', secondary: '#F38BA8' },
        fonts: ['IBM+Plex+Sans:wght@400;500;600;700', 'JetBrains+Mono:wght@400;500;700']
      },
      'minimal-modern': {
        name: 'Minimal Modern',
        description: 'Chat-first overlay sidebar, floating pill input',
        dark: true,
        preview: { bg: '#1A1A1A', accent: '#10A37F', secondary: '#A855F7' },
        fonts: ['DM+Sans:wght@400;500;600;700', 'JetBrains+Mono:wght@400;500']
      },
      'glass-morphism': {
        name: 'Glass Morphism',
        description: 'Floating panels with frosted glass and light blobs',
        dark: true,
        preview: { bg: '#1C1C2E', accent: '#7C6CF0', secondary: '#E860A0' },
        fonts: ['Plus+Jakarta+Sans:wght@400;500;600;700', 'JetBrains+Mono:wght@400;500']
      },
      'light': {
        name: 'Light',
        description: 'Warm editorial reading experience, comfortable layout',
        dark: false,
        preview: { bg: '#F8F7F4', accent: '#C44B2F', secondary: '#2C6B5E' },
        fonts: ['Instrument+Sans:wght@400;500;600;700', 'JetBrains+Mono:wght@400;500']
      }
    };
    this.current = 'cyberpunk-neon';
  }

  apply(themeName) {
    const normalized = this.normalizeName(themeName);
    if (!this.THEMES[normalized]) return;

    // Enable smooth theme transition
    document.documentElement.classList.add('theme-transitioning');
    document.documentElement.setAttribute('data-theme', normalized);
    this.current = normalized;
    this.loadFonts(normalized);
    try { localStorage.setItem('pimono-theme', normalized); } catch(e) {}

    // Remove transition class after animation completes
    setTimeout(function() {
      document.documentElement.classList.remove('theme-transitioning');
    }, 450);
  }

  normalizeName(name) {
    const lower = (name || '').toLowerCase().trim();
    if (lower === 'dark' || lower === 'cyberpunkneon') return 'cyberpunk-neon';
    if (lower === 'light') return 'light';
    if (this.THEMES[lower]) return lower;
    var hyphenated = lower.replace(/\s+/g, '-');
    if (this.THEMES[hyphenated]) return hyphenated;
    return 'cyberpunk-neon';
  }

  loadFonts(themeName) {
    var theme = this.THEMES[themeName];
    if (!theme || !theme.fonts || theme.fonts.length === 0) return;

    var url = 'https://fonts.googleapis.com/css2?' + theme.fonts.map(function(f) {
      return 'family=' + f;
    }).join('&') + '&display=swap';

    var link = document.getElementById('theme-fonts-link');
    if (!link) {
      link = document.createElement('link');
      link.id = 'theme-fonts-link';
      link.rel = 'stylesheet';
      link.media = 'print';
      link.onload = function() { this.media = 'all'; };
      document.head.appendChild(link);
    }
    if (link.href !== url) {
      // Reset async loading pattern when changing href
      link.media = 'print';
      link.onload = function() { this.media = 'all'; };
      link.href = url;
    }
  }

  getThemeList() {
    var self = this;
    return Object.keys(this.THEMES).map(function(id) {
      var t = self.THEMES[id];
      return { id: id, name: t.name, description: t.description, dark: t.dark, preview: t.preview };
    });
  }

  getCurrent() { return this.current; }
  isDark() { return this.THEMES[this.current] ? this.THEMES[this.current].dark : true; }
}

var themeManager = new ThemeManager();
