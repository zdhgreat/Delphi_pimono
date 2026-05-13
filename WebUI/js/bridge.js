// PiMono WebView2 Bridge - Communication layer between JS and Delphi
class PiMonoBridge {
  constructor() {
    this._listeners = {};
    this._ready = false;

    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.addEventListener('message', (e) => {
        try {
          const data = JSON.parse(e.data);
          const eventName = data.event;
          if (eventName && this._listeners[eventName]) {
            this._listeners[eventName].forEach(cb => {
              try { cb(data); } catch (err) { console.error('Bridge listener error:', err); }
            });
          }
        } catch (err) {
          console.error('Bridge parse error:', err, e.data);
        }
      });
    }
  }

  // Send action to Delphi
  send(action, data = {}) {
    data.action = action;
    const json = JSON.stringify(data);
    console.log('Bridge send:', action);
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage(json);
    } else {
      console.log('Bridge (no webview):', json);
    }
  }

  // Register handler for events from Delphi
  on(event, callback) {
    if (!this._listeners[event]) this._listeners[event] = [];
    this._listeners[event].push(callback);
  }

  // Remove handler
  off(event, callback) {
    if (!this._listeners[event]) return;
    this._listeners[event] = this._listeners[event].filter(cb => cb !== callback);
  }
}

const bridge = new PiMonoBridge();

// Global localization lookup. Populated by 'localization' event from Delphi.
// Usage: L('key') returns localized string, falls back to key itself.
window.__loc = window.__loc || {};
function L(key) { return window.__loc[key] || key; }

// Direct event dispatch — called by Delphi via ExecuteScript when PostWebMessageAsJson
// is unreliable.  Accepts raw JSON that contains an "event" key and dispatches to listeners.
window.__dispatchBridgeEvent = function(jsonStr) {
  try {
    var data = (typeof jsonStr === 'string') ? JSON.parse(jsonStr) : jsonStr;
    var eventName = data.event;
    if (eventName && bridge._listeners[eventName]) {
      bridge._listeners[eventName].forEach(function(cb) {
        try { cb(data); } catch (err) { console.error('__dispatchBridgeEvent error:', err); }
      });
    }
  } catch (err) {
    console.error('__dispatchBridgeEvent parse error:', err);
  }
};
