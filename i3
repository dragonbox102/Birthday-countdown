// ============================================================
// AU IXL - Standalone Version (GitHub-hosted)
// Fully standalone. No Vercel deployment needed.
// Calls free AI APIs directly, bypassing IXL CSP via hidden iframe.
// Load via bookmarklet: javascript:void(fetch('https://raw.githubusercontent.com/YOU/REPO/main/ixl-standalone.js').then(r=>r.text()).then(eval))
// ============================================================
(function () {
  "use strict";

  // Prevent double-load
  if (window.__AU_IXL_LOADED) {
    console.log("[AU] Already loaded");
    return;
  }
  window.__AU_IXL_LOADED = true;

  // ========== SIMPLE MARKDOWN RENDERER ==========
  function simpleMarkdown(text) {
    if (!text) return "";
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/^### (.+)$/gm, "<h4>$1</h4>")
      .replace(/^## (.+)$/gm, "<h3>$1</h3>")
      .replace(/^# (.+)$/gm, "<h2>$1</h2>")
      .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
      .replace(/\*(.+?)\*/g, "<em>$1</em>")
      .replace(/`(.+?)`/g, "<code>$1</code>")
      .replace(/\n/g, "<br>");
  }

  // ========== CSP BYPASS: AI FETCH VIA HIDDEN IFRAME ==========
  // IXL's CSP blocks fetch()/XHR to external domains from the page context.
  // However, a blob: or data: URI iframe has NO inherited CSP restrictions.
  // We create a hidden iframe with a blob: URL that runs fetch() inside it,
  // then postMessage() the result back to the parent page.
  // This works because:
  //   1. CSP connect-src only restricts the document it's set on
  //   2. blob: iframes are a separate browsing context with no CSP
  //   3. postMessage between same-origin contexts is always allowed

  var _iframeReady = null;
  var _iframeEl = null;
  var _requestId = 0;
  var _pendingRequests = {};

  function getProxyIframe() {
    if (_iframeReady) return _iframeReady;

    _iframeReady = new Promise(function (resolve) {
      // The iframe's code: listens for fetch requests, makes them, sends back results
      var iframeCode =
        "<!DOCTYPE html><html><body><script>" +
        'window.addEventListener("message", function(ev) {' +
        "  if (!ev.data || !ev.data.__au_fetch) return;" +
        "  var id = ev.data.id;" +
        "  var url = ev.data.url;" +
        "  var opts = ev.data.opts || {};" +
        "  fetch(url, opts)" +
        "    .then(function(r) {" +
        "      if (!r.ok) return r.text().then(function(t) {" +
        '        ev.source.postMessage({__au_resp: true, id: id, error: "HTTP " + r.status, body: t}, "*");' +
        "      });" +
        "      return r.text().then(function(t) {" +
        '        ev.source.postMessage({__au_resp: true, id: id, ok: true, body: t, status: r.status}, "*");' +
        "      });" +
        "    })" +
        "    .catch(function(e) {" +
        '      ev.source.postMessage({__au_resp: true, id: id, error: e.message || "Network error"}, "*");' +
        "    });" +
        "});" +
        'parent.postMessage({__au_iframe_ready: true}, "*");' +
        "</scr" +
        "ipt></body></html>";

      var blob = new Blob([iframeCode], { type: "text/html" });
      var blobUrl = URL.createObjectURL(blob);

      var iframe = document.createElement("iframe");
      iframe.style.cssText =
        "position:fixed;width:0;height:0;border:none;opacity:0;pointer-events:none;z-index:-1;";
      iframe.src = blobUrl;
      _iframeEl = iframe;

      function onReady(ev) {
        if (ev.data && ev.data.__au_iframe_ready) {
          window.removeEventListener("message", onReady);
          console.log("[AU] CSP bypass iframe ready");
          resolve(iframe);
        }
      }
      window.addEventListener("message", onReady);

      // Listen for all responses
      window.addEventListener("message", function (ev) {
        if (ev.data && ev.data.__au_resp) {
          var cb = _pendingRequests[ev.data.id];
          if (cb) {
            delete _pendingRequests[ev.data.id];
            cb(ev.data);
          }
        }
      });

      document.body.appendChild(iframe);
    });

    return _iframeReady;
  }

  // Fetch via the hidden iframe (bypasses CSP)
  function proxyFetch(url, opts) {
    return getProxyIframe().then(function (iframe) {
      return new Promise(function (resolve, reject) {
        var id = ++_requestId;
        var timeout = setTimeout(function () {
          delete _pendingRequests[id];
          reject(new Error("Proxy fetch timeout (30s)"));
        }, 30000);

        _pendingRequests[id] = function (data) {
          clearTimeout(timeout);
          if (data.error) {
            reject(new Error(data.error + (data.body ? ": " + data.body.substring(0, 200) : "")));
          } else {
            resolve({ ok: true, status: data.status, text: data.body });
          }
        };

        iframe.contentWindow.postMessage(
          {
            __au_fetch: true,
            id: id,
            url: url,
            opts: {
              method: opts.method || "GET",
              headers: opts.headers || {},
              body: opts.body || null,
            },
          },
          "*"
        );
      });
    });
  }

  // ========== SPAM / DISCORD INVITE DETECTION ==========
  var SPAM_PATTERNS = [
    /discord\.gg\/[a-zA-Z0-9]+/i,
    /discord\.com\/invite\/[a-zA-Z0-9]+/i,
    /discordapp\.com\/invite\/[a-zA-Z0-9]+/i,
    /discord\.gg/i,
    /please\s+join\s+(our|my|the|this)/i,
    /join\s+(our|my|the)\s+(discord|server|community|channel|group)/i,
    /join\s+us\s+(at|on|in)\s+/i,
    /t\.me\/[a-zA-Z0-9_]+/i,
    /telegram\s*(group|channel|community)/i,
    /use\s+(my|our|this)\s+(code|link|referral)/i,
    /subscribe\s+to\s+(my|our)/i,
    /follow\s+(me|us)\s+on/i,
    /check\s+out\s+(my|our)\s+(channel|page|website|site|server)/i,
    /sign\s*up\s+(at|for|on)\s+\S+\.(com|org|net|io|gg|space|xyz)/i,
    /visit\s+(us\s+at|our\s+site)\s+/i,
    /patreon\.com\/[a-zA-Z0-9_]+/i,
    /buymeacoffee\.com/i,
    /ko-fi\.com/i,
  ];

  function isSpamResponse(text) {
    if (!text || typeof text !== "string") return false;
    for (var i = 0; i < SPAM_PATTERNS.length; i++) {
      if (SPAM_PATTERNS[i].test(text))
        return "Matched spam pattern: " + SPAM_PATTERNS[i].source;
    }
    if (
      text.length < 200 &&
      /https?:\/\/[^\s]+/i.test(text) &&
      !/<answer>/i.test(text) &&
      !/\d+[\+\-\*\/\=]/.test(text)
    ) {
      return "Short response with URL but no answer content";
    }
    var lowerText = text.toLowerCase();
    var spamWords = (
      lowerText.match(
        /\b(join|subscribe|follow|discord|server|community|channel|invite|signup|sign up|patreon)\b/g
      ) || []
    ).length;
    var mathWords = (
      lowerText.match(
        /\b(answer|solution|step|calculate|equals|equation|therefore|result|value|solve|simplif|fraction|decimal|percent)\b/g
      ) || []
    ).length;
    if (spamWords >= 3 && mathWords === 0) {
      return (
        "Response focused on social media (" +
        spamWords +
        " spam words, 0 math words)"
      );
    }
    return false;
  }

  // ========== MULTI-DOMAIN FREE AI (all called via CSP bypass iframe) ==========
  var AI_ENDPOINTS = [
    // Pollinations (confirmed free, CORS-friendly, OpenAI-compatible)
    {
      url: "https://text.pollinations.ai/openai/chat/completions",
      model: "openai",
      name: "Poll-OpenAI",
    },
    {
      url: "https://text.pollinations.ai/openai/chat/completions",
      model: "openai-fast",
      name: "Poll-Fast",
    },
    {
      url: "https://text.pollinations.ai/openai/chat/completions",
      model: "mistral",
      name: "Poll-Mistral",
    },
    {
      url: "https://text.pollinations.ai/openai/chat/completions",
      model: "deepseek",
      name: "Poll-DeepSeek",
    },
    {
      url: "https://text.pollinations.ai/openai/chat/completions",
      model: "qwen",
      name: "Poll-Qwen",
    },

    // Airforce (confirmed working, OpenAI-compatible)
    {
      url: "https://api.airforce/v1/chat/completions",
      model: "llama-4-maverick",
      name: "Airforce-Llama4",
    },
    {
      url: "https://api.airforce/v1/chat/completions",
      model: "gemini-2.0-flash",
      name: "Airforce-Gemini",
    },

    // g4f.space proxies
    {
      url: "https://g4f.space/api/pollinations/chat/completions",
      model: "openai",
      name: "G4F-Poll",
    },
    {
      url: "https://g4f.space/api/pollinations/chat/completions",
      model: "mistral",
      name: "G4F-Mistral",
    },
    {
      url: "https://g4f.space/api/pollinations/chat/completions",
      model: "deepseek",
      name: "G4F-DeepSeek",
    },

    // Blackbox AI (different payload format)
    {
      url: "https://www.blackbox.ai/api/chat",
      model: "gpt-4o-mini",
      name: "Blackbox-GPT4o",
      isBlackbox: true,
    },
  ];

  var _failedEndpoints = {};
  var _FAIL_COOLDOWN = 60000;

  function shuffleArray(arr) {
    var a = arr.slice();
    for (var i = a.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1));
      var tmp = a[i];
      a[i] = a[j];
      a[j] = tmp;
    }
    return a;
  }

  function getAvailableEndpoints() {
    var now = Date.now();
    var fresh = [];
    var cooldown = [];
    for (var i = 0; i < AI_ENDPOINTS.length; i++) {
      var ep = AI_ENDPOINTS[i];
      var failTime = _failedEndpoints[ep.name];
      if (failTime && now - failTime < _FAIL_COOLDOWN) {
        cooldown.push(ep);
      } else {
        if (failTime) delete _failedEndpoints[ep.name];
        fresh.push(ep);
      }
    }
    return shuffleArray(fresh).concat(shuffleArray(cooldown));
  }

  function tryEndpoint(endpoint, prompt) {
    var payload;
    var hdrs = {
      "Content-Type": "application/json",
      Accept: "application/json",
    };

    if (endpoint.isBlackbox) {
      payload = JSON.stringify({
        messages: [{ id: "msg1", role: "user", content: prompt }],
        agentMode: {},
        trendingAgentMode: {},
        isMicMode: false,
        maxTokens: 4096,
        playgroundTopP: 1,
        playgroundTemperature: 0.7,
        isChromeExt: false,
        githubToken: "",
        clickedAnswer2: false,
        clickedAnswer3: false,
        clickedForceWebSearch: false,
        visitFromDelta: false,
        mobileClient: false,
        userSelectedModel: endpoint.model,
      });
    } else {
      payload = JSON.stringify({
        model: endpoint.model,
        messages: [{ role: "user", content: prompt }],
      });
    }

    return proxyFetch(endpoint.url, {
      method: "POST",
      headers: hdrs,
      body: payload,
    }).then(function (resp) {
      var text = resp.text;

      // Check for HTML responses (Cloudflare block)
      if (text && text.indexOf("<!DOCTYPE") === 0) {
        _failedEndpoints[endpoint.name] = Date.now();
        throw new Error(endpoint.name + " Cloudflare blocked");
      }

      var data;
      try {
        data = JSON.parse(text);
      } catch (e) {
        // Blackbox sometimes returns plain text
        if (text && text.length > 20 && !text.startsWith("{") && !text.startsWith("<")) {
          var spamReason = isSpamResponse(text);
          if (spamReason) {
            _failedEndpoints[endpoint.name] = Date.now() + 240000;
            throw new Error(endpoint.name + " BLOCKED (spam: " + spamReason + ")");
          }
          return { text: text, provider: endpoint.name };
        }
        throw new Error(endpoint.name + " parse error");
      }

      if (data.error) {
        var errMsg = data.error.message || data.error;
        if (
          String(errMsg).indexOf("not exist") !== -1 ||
          String(errMsg).indexOf("not found") !== -1
        ) {
          _failedEndpoints[endpoint.name] = Date.now();
        }
        throw new Error(endpoint.name + " API error: " + errMsg);
      }

      var responseText = null;
      if (
        data.choices &&
        data.choices[0] &&
        data.choices[0].message &&
        data.choices[0].message.content
      ) {
        responseText = data.choices[0].message.content;
      } else if (data.reply) {
        responseText = data.reply;
      } else if (data.response) {
        responseText = data.response;
      } else if (data.message && typeof data.message === "string") {
        responseText = data.message;
      }

      if (responseText) {
        var spamReason2 = isSpamResponse(responseText);
        if (spamReason2) {
          _failedEndpoints[endpoint.name] = Date.now() + 240000;
          throw new Error(
            endpoint.name + " BLOCKED (spam: " + spamReason2 + ")"
          );
        }
        return { text: responseText, provider: endpoint.name };
      }

      throw new Error(endpoint.name + " unexpected response format");
    });
  }

  function getAIResponse(prompt, logFn) {
    var log =
      logFn ||
      function (m) {
        console.log("[AU] " + m);
      };
    var endpoints = getAvailableEndpoints();
    var errors = [];
    var index = 0;

    function tryNext() {
      if (index >= endpoints.length) {
        return Promise.reject(
          new Error(
            "All " +
              endpoints.length +
              " AI endpoints failed:\n" +
              errors.join("\n")
          )
        );
      }
      var ep = endpoints[index];
      index++;
      log("Trying " + ep.name + "...");
      return tryEndpoint(ep, prompt)
        .then(function (result) {
          log("Got answer via " + result.provider);
          return result.text;
        })
        .catch(function (err) {
          log(err.message);
          errors.push(err.message);
          return tryNext();
        });
    }

    return tryNext();
  }

  // ========== DIRECT REACT FIBER CLICK ==========
  function fiberClick(el) {
    var keys = Object.keys(el);
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i];
      if (
        k.indexOf("__reactFiber") === 0 ||
        k.indexOf("__reactInternalInstance") === 0
      ) {
        var node = el[k];
        var depth = 0;
        while (node && depth < 50) {
          var mp = node.memoizedProps || node.pendingProps;
          if (mp) {
            var fakeEvt = {
              preventDefault: function () {},
              stopPropagation: function () {},
              persist: function () {},
              nativeEvent: new MouseEvent("click", { bubbles: true }),
              target: el,
              currentTarget: el,
              bubbles: true,
              type: "click",
              isDefaultPrevented: function () {
                return false;
              },
              isPropagationStopped: function () {
                return false;
              },
            };
            if (typeof mp.onClick === "function") {
              mp.onClick(fakeEvt);
              return true;
            }
            if (typeof mp.onSelect === "function") {
              mp.onSelect(fakeEvt);
              return true;
            }
            if (typeof mp.onMouseDown === "function") {
              var downEvt = Object.assign({}, fakeEvt, {
                type: "mousedown",
                nativeEvent: new MouseEvent("mousedown", { bubbles: true }),
              });
              mp.onMouseDown(downEvt);
              if (typeof mp.onMouseUp === "function") {
                mp.onMouseUp(
                  Object.assign({}, fakeEvt, {
                    type: "mouseup",
                    nativeEvent: new MouseEvent("mouseup", { bubbles: true }),
                  })
                );
              }
              return true;
            }
          }
          node = node.return;
          depth++;
        }
      }
    }
    return false;
  }

  function smartClick(el) {
    var target = el;
    for (var level = 0; level < 5 && target; level++) {
      if (fiberClick(target)) return true;
      target = target.parentElement;
    }
    // Fallback: native events
    var r = el.getBoundingClientRect();
    var cx = r.left + r.width / 2,
      cy = r.top + r.height / 2;
    var o = {
      bubbles: true,
      cancelable: true,
      view: window,
      clientX: cx,
      clientY: cy,
      button: 0,
    };
    el.dispatchEvent(new PointerEvent("pointerdown", o));
    el.dispatchEvent(new MouseEvent("mousedown", o));
    el.dispatchEvent(new PointerEvent("pointerup", o));
    el.dispatchEvent(new MouseEvent("mouseup", o));
    el.dispatchEvent(new MouseEvent("click", o));
    return false;
  }

  // ========== REACT-AWARE INPUT VALUE SETTER ==========
  var nativeInputSetter = Object.getOwnPropertyDescriptor(
    HTMLInputElement.prototype,
    "value"
  ).set;
  var nativeTextareaSetter = Object.getOwnPropertyDescriptor(
    HTMLTextAreaElement.prototype,
    "value"
  ).set;

  function reactSetValue(el, val) {
    var setter =
      el.tagName === "TEXTAREA" ? nativeTextareaSetter : nativeInputSetter;
    setter.call(el, val);
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    var keys = Object.keys(el);
    for (var i = 0; i < keys.length; i++) {
      if (keys[i].indexOf("__reactProps") === 0) {
        var props = el[keys[i]];
        if (props && typeof props.onChange === "function") {
          props.onChange({
            target: el,
            currentTarget: el,
            type: "change",
            preventDefault: function () {},
            stopPropagation: function () {},
            persist: function () {},
          });
        }
      }
    }
  }

  // ========== INJECT STYLES ==========
  var style = document.createElement("style");
  style.textContent = [
    "#au-panel{position:fixed;top:16px;right:16px;width:380px;max-height:92vh;background:#09090b;border:1px solid #18181b;border-radius:16px;box-shadow:0 24px 64px rgba(0,0,0,0.85),0 0 0 1px rgba(255,255,255,0.04);z-index:99999999;font-family:system-ui,-apple-system,sans-serif;font-size:13px;color:#e4e4e7;display:flex;flex-direction:column;animation:au-slideIn 0.35s cubic-bezier(0.16,1,0.3,1);overflow:hidden}",
    "@keyframes au-slideIn{from{opacity:0;transform:translateY(-12px) scale(0.97)}to{opacity:1;transform:translateY(0) scale(1)}}",
    "@keyframes au-spin{to{transform:rotate(360deg)}}",
    "@keyframes au-slideUp{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:translateY(0)}}",
    ".au-header{display:flex;align-items:center;gap:8px;padding:14px 16px;border-bottom:1px solid #18181b;cursor:move;user-select:none}",
    ".au-header:hover{background:rgba(255,255,255,0.02)}",
    ".au-header-title{font-weight:700;font-size:14px;color:#f4f4f5;margin-right:auto;letter-spacing:-0.01em}",
    ".au-header-badge{font-size:9px;color:#22c55e;background:#052e16;border:1px solid #166534;border-radius:20px;padding:3px 8px;font-weight:600;letter-spacing:0.4px;text-transform:uppercase}",
    ".au-header-btn{background:none;border:none;color:#71717a;cursor:pointer;font-size:11px;font-weight:500;padding:4px 8px;border-radius:6px;transition:all 0.15s;font-family:inherit}",
    ".au-header-btn:hover{color:#f4f4f5;background:#27272a}",
    ".au-body{padding:14px;overflow-y:auto;flex:1;display:flex;flex-direction:column;gap:12px}",
    ".au-card{background:#0f0f11;border:1px solid #1e1e22;border-radius:12px;padding:14px}",
    ".au-card-label{font-size:10px;text-transform:uppercase;letter-spacing:1px;color:#52525b;font-weight:700;margin-bottom:10px}",
    ".au-select{width:100%;background:#09090b;border:1px solid #27272a;border-radius:8px;padding:8px 32px 8px 10px;color:#e4e4e7;font-size:12px;font-family:inherit;appearance:none;cursor:pointer;background-image:url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' fill='%2371717a' viewBox='0 0 16 16'%3E%3Cpath d='M8 11L3 6h10z'/%3E%3C/svg%3E\");background-repeat:no-repeat;background-position:right 10px center}",
    ".au-select:focus{outline:none;border-color:#3b82f6}",
    ".au-btn{border:none;border-radius:8px;font-weight:600;cursor:pointer;transition:all 0.15s;font-family:inherit;font-size:12px;padding:9px 16px}",
    ".au-btn-primary{background:#e4e4e7;color:#09090b}",
    ".au-btn-primary:hover{background:#f4f4f5}",
    ".au-btn-primary:active{transform:scale(0.97)}",
    ".au-btn-secondary{background:#18181b;color:#a1a1aa;border:1px solid #27272a}",
    ".au-btn-secondary:hover{background:#27272a;color:#e4e4e7}",
    ".au-answer-box{display:none;background:#09090b;border:1px solid #1e1e22;border-radius:12px;overflow:hidden;animation:au-slideUp 0.3s ease}",
    ".au-answer-header{background:#0c1425;border-bottom:1px solid #1e293b;padding:14px 16px}",
    ".au-answer-header h4{margin:0;font-size:10px;text-transform:uppercase;letter-spacing:1px;color:#3b82f6;font-weight:700;opacity:0.8;margin-bottom:8px}",
    ".au-answer-value{background:rgba(59,130,246,0.08);border:1px solid rgba(59,130,246,0.2);border-radius:8px;padding:12px 16px;font-size:16px;font-weight:700;color:#60a5fa;text-align:center;min-height:32px;display:flex;align-items:center;justify-content:center}",
    ".au-answer-value p{margin:0}",
    ".au-steps-section{padding:14px 16px}",
    ".au-steps-section h5{margin:0 0 10px 0;font-size:10px;text-transform:uppercase;letter-spacing:1px;color:#52525b;font-weight:700;padding-bottom:8px;border-bottom:1px solid #18181b}",
    ".au-steps-body{font-size:13px;color:#a1a1aa;line-height:1.7}",
    ".au-steps-body h2{color:#f4f4f5;font-size:14px;margin:14px 0 6px}",
    ".au-steps-body p{margin:6px 0;color:#a1a1aa}",
    ".au-steps-body code{background:#18181b;padding:1px 5px;border-radius:4px;font-size:12px;color:#60a5fa}",
    ".au-steps-body strong{color:#f4f4f5}",
    ".au-progress{display:none}",
    ".au-progress-bar{width:100%;height:3px;background:#18181b;border-radius:2px;overflow:hidden}",
    ".au-progress-fill{height:100%;background:linear-gradient(90deg,#3b82f6,#60a5fa);border-radius:2px;transition:width 0.3s}",
    ".au-progress-label{font-size:10px;color:#52525b;margin-top:6px}",
    ".au-status{font-size:11px;font-weight:600;color:#52525b}",
    ".au-status.active{color:#3b82f6}",
    ".au-status.error{color:#ef4444}",
    ".au-log{display:none;background:#09090b;border:1px solid #1e1e22;border-radius:8px;padding:8px 10px;font-family:'SF Mono',Consolas,monospace;font-size:10px;max-height:120px;overflow-y:auto;color:#52525b}",
    ".au-log div{margin-bottom:2px}",
    ".au-toggle-row{display:flex;align-items:center;justify-content:space-between;padding:6px 0}",
    ".au-toggle-row label{color:#a1a1aa;font-size:12px;font-weight:500;cursor:pointer}",
    ".au-check{accent-color:#3b82f6;width:auto;margin:0}",
    "#au-panel ::-webkit-scrollbar{width:5px}",
    "#au-panel ::-webkit-scrollbar-track{background:transparent}",
    "#au-panel ::-webkit-scrollbar-thumb{background:#27272a;border-radius:3px}",
    "#au-fab-min{position:fixed;bottom:16px;right:16px;width:46px;height:46px;border-radius:12px;border:1px solid #27272a;background:#09090b;color:#e4e4e7;font-size:12px;font-weight:700;cursor:pointer;display:none;align-items:center;justify-content:center;z-index:100000001;box-shadow:0 4px 16px rgba(0,0,0,0.5);font-family:system-ui,sans-serif;transition:all 0.2s}",
    "#au-fab-min:hover{background:#18181b;border-color:#3f3f46;transform:translateY(-2px)}",
  ].join("\n");
  document.head.appendChild(style);

  // ========== BUILD PANEL ==========
  var old = document.getElementById("au-panel");
  if (old) old.remove();
  var oldFab = document.getElementById("au-fab-min");
  if (oldFab) oldFab.remove();

  var config = {
    mode: "displayOnly",
    autoSubmit: false,
    autoNext: false,
    lastState: null,
  };

  var panel = document.createElement("div");
  panel.id = "au-panel";
  panel.innerHTML =
    '<div style="display:flex;flex-direction:column;height:100%;max-height:92vh;">' +
    '  <div class="au-header" id="au-drag-handle">' +
    '    <span class="au-header-title">AU IXL</span>' +
    '    <span class="au-header-badge">Standalone</span>' +
    '    <button class="au-header-btn" id="au-btn-logs">Logs</button>' +
    '    <button class="au-header-btn" id="au-btn-close">Close</button>' +
    "  </div>" +
    '  <div class="au-body">' +
    '    <div class="au-card">' +
    '      <div class="au-card-label">Mode</div>' +
    '      <select class="au-select" id="au-mode">' +
    '        <option value="displayOnly">Display Only</option>' +
    '        <option value="autoFill">Auto Fill</option>' +
    "      </select>" +
    '      <div style="display:flex;gap:8px;margin-top:10px;">' +
    '        <button class="au-btn au-btn-primary" id="au-start" style="flex:1;">Get Answer</button>' +
    '        <button class="au-btn au-btn-secondary" id="au-rollback" style="flex:1;">Undo</button>' +
    "      </div>" +
    "    </div>" +
    '    <div class="au-answer-box" id="au-answer-box">' +
    '      <div class="au-answer-header">' +
    "        <h4>Answer</h4>" +
    '        <div class="au-answer-value" id="au-answer-value"></div>' +
    "      </div>" +
    '      <div class="au-steps-section">' +
    "        <h5>Steps</h5>" +
    '        <div class="au-steps-body" id="au-steps-body"></div>' +
    "      </div>" +
    "    </div>" +
    '    <div class="au-progress" id="au-progress">' +
    '      <div class="au-progress-bar"><div class="au-progress-fill" id="au-progress-fill"></div></div>' +
    '      <div class="au-progress-label" id="au-progress-label">Thinking...</div>' +
    "    </div>" +
    '    <div class="au-status" id="au-status">Ready</div>' +
    '    <div class="au-log" id="au-log"></div>' +
    '    <div class="au-card" style="padding:10px 14px;">' +
    '      <div class="au-card-label">Settings</div>' +
    '      <div style="display:flex;flex-direction:column;gap:6px;">' +
    '        <div class="au-toggle-row">' +
    "          <label>Auto Submit</label>" +
    '          <input type="checkbox" class="au-check" id="au-auto-submit"/>' +
    "        </div>" +
    '        <div class="au-toggle-row">' +
    "          <label>Auto Next</label>" +
    '          <input type="checkbox" class="au-check" id="au-auto-next"/>' +
    "        </div>" +
    "      </div>" +
    "    </div>" +
    '    <div style="text-align:center;font-size:10px;color:#52525b;padding:4px 0 2px;">Standalone mode &mdash; no server needed &mdash; direct AI calls</div>' +
    "  </div>" +
    "</div>";
  document.body.appendChild(panel);

  // Minimize FAB
  var fab = document.createElement("button");
  fab.id = "au-fab-min";
  fab.textContent = "AU";
  fab.title = "Toggle AU panel";
  document.body.appendChild(fab);

  // ========== UI REFS ==========
  var UI = {
    mode: panel.querySelector("#au-mode"),
    start: panel.querySelector("#au-start"),
    rollback: panel.querySelector("#au-rollback"),
    answerBox: panel.querySelector("#au-answer-box"),
    answerValue: panel.querySelector("#au-answer-value"),
    stepsBody: panel.querySelector("#au-steps-body"),
    progress: panel.querySelector("#au-progress"),
    progressFill: panel.querySelector("#au-progress-fill"),
    progressLabel: panel.querySelector("#au-progress-label"),
    status: panel.querySelector("#au-status"),
    log: panel.querySelector("#au-log"),
    logBtn: panel.querySelector("#au-btn-logs"),
    closeBtn: panel.querySelector("#au-btn-close"),
    autoSubmit: panel.querySelector("#au-auto-submit"),
    autoNext: panel.querySelector("#au-auto-next"),
  };

  // ========== DRAG ==========
  var isDragging = false,
    dragX = 0,
    dragY = 0;
  var handle = panel.querySelector("#au-drag-handle");
  handle.addEventListener("mousedown", function (e) {
    isDragging = true;
    dragX = e.clientX - panel.getBoundingClientRect().left;
    dragY = e.clientY - panel.getBoundingClientRect().top;
    document.addEventListener("mousemove", onDrag);
    document.addEventListener("mouseup", stopDrag);
  });
  function onDrag(e) {
    if (!isDragging) return;
    panel.style.left = e.clientX - dragX + "px";
    panel.style.top = e.clientY - dragY + "px";
    panel.style.right = "auto";
  }
  function stopDrag() {
    isDragging = false;
    document.removeEventListener("mousemove", onDrag);
    document.removeEventListener("mouseup", stopDrag);
  }

  // ========== LOGGING ==========
  function logMsg(msg) {
    console.log("[AU] " + msg);
    var d = document.createElement("div");
    d.textContent = new Date().toLocaleTimeString() + " " + msg;
    UI.log.appendChild(d);
    UI.log.scrollTop = UI.log.scrollHeight;
  }

  // ========== EVENT LISTENERS ==========
  UI.logBtn.addEventListener("click", function () {
    var show = UI.log.style.display === "none" || !UI.log.style.display;
    UI.log.style.display = show ? "block" : "none";
    UI.logBtn.textContent = show ? "Hide" : "Logs";
  });
  UI.closeBtn.addEventListener("click", function () {
    panel.style.display = "none";
    fab.style.display = "flex";
  });
  fab.addEventListener("click", function () {
    panel.style.display = "flex";
    fab.style.display = "none";
  });
  UI.mode.addEventListener("change", function () {
    config.mode = UI.mode.value;
    if (config.mode === "autoFill")
      alert("Auto Fill is unstable. Use carefully.");
  });
  UI.start.addEventListener("click", function () {
    startAnswer();
  });
  UI.rollback.addEventListener("click", function () {
    if (config.lastState) {
      var d = getQuestionDiv();
      if (d) {
        d.innerHTML = config.lastState;
        logMsg("Rolled back");
      }
    } else logMsg("Nothing to undo");
  });
  UI.autoSubmit.addEventListener("change", function () {
    config.autoSubmit = UI.autoSubmit.checked;
  });
  UI.autoNext.addEventListener("change", function () {
    config.autoNext = UI.autoNext.checked;
  });

  // ========== PROGRESS ==========
  var progressTimer = null;
  function startProgress() {
    UI.progress.style.display = "block";
    UI.progressFill.style.width = "0%";
    var val = 0;
    progressTimer = setInterval(function () {
      if (val < 90) {
        val += 2;
        UI.progressFill.style.width = val + "%";
      }
    }, 200);
  }
  function stopProgress() {
    if (progressTimer) clearInterval(progressTimer);
    UI.progressFill.style.width = "100%";
    setTimeout(function () {
      UI.progress.style.display = "none";
      UI.progressFill.style.width = "0%";
    }, 400);
  }

  // ========== QUESTION EXTRACTION ==========
  function getQuestionDiv() {
    var d = document.evaluate(
      "/html/body/main/div/article/section/section/div/div[1]",
      document,
      null,
      XPathResult.FIRST_ORDERED_NODE_TYPE,
      null
    ).singleNodeValue;
    if (!d) d = document.querySelector("main div.article, main>div, article");
    return d;
  }

  function extractEssentialHTML(div) {
    var clone = div.cloneNode(true);
    [
      "script",
      "style",
      "noscript",
      '[class*="timer"]',
      '[class*="score"]',
      '[class*="toolbar"]',
      "iframe",
      "video",
      "audio",
    ].forEach(function (s) {
      clone.querySelectorAll(s).forEach(function (e) {
        e.remove();
      });
    });
    clone.querySelectorAll("*").forEach(function (el) {
      var keep = [
        "type",
        "value",
        "checked",
        "selected",
        "class",
        "id",
        "src",
        "alt",
        "title",
        "href",
        "role",
        "tabindex",
      ];
      Array.from(el.attributes).forEach(function (a) {
        if (
          keep.indexOf(a.name) === -1 &&
          a.name.indexOf("data-") !== 0 &&
          a.name.indexOf("aria-") !== 0
        )
          el.removeAttribute(a.name);
      });
    });
    return clone.innerHTML;
  }

  function extractTextOnly(div) {
    var clone = div.cloneNode(true);
    [
      "script",
      "style",
      "noscript",
      '[class*="timer"]',
      '[class*="score"]',
      '[class*="toolbar"]',
      "iframe",
      "video",
      "audio",
    ].forEach(function (s) {
      clone.querySelectorAll(s).forEach(function (e) {
        e.remove();
      });
    });
    return clone.textContent.trim().replace(/\s+/g, " ");
  }

  function captureLatex(div) {
    var arr = div.querySelectorAll(
      'script[type="math/tex"], .MathJax, .mjx-chtml, img[data-latex]'
    );
    if (arr.length === 0) return null;
    var out = "";
    arr.forEach(function (e) {
      out +=
        (e.tagName === "IMG" && e.dataset.latex
          ? e.dataset.latex
          : e.textContent) + "\n";
    });
    return out;
  }

  function cleanAnswer(str) {
    if (!str) return str;
    str = str.replace(/\\frac\{([^}]*)\}\{([^}]*)\}/g, "$1/$2");
    str = str.replace(/\\text\{([^}]*)\}/g, "$1");
    str = str.replace(
      /\\(?:left|right|cdot|times|div|pm|mp|approx|neq|leq|geq|lt|gt)/g,
      ""
    );
    str = str.replace(/\\([a-zA-Z]+)/g, "$1");
    str = str.replace(/\$\$/g, "").replace(/\$/g, "");
    str = str.replace(/`/g, "");
    str = str.replace(/\\\(|\\\)|\\\[|\\\]/g, "");
    str = str.replace(/\*\*/g, "");
    str = str.replace(/\s+/g, " ").trim();
    var eqMatch = str.match(/=\s*([^=]+)$/);
    if (eqMatch && eqMatch[1].trim().match(/^[+-]?\d/)) str = eqMatch[1].trim();
    return str;
  }

  function extractFinalAnswer(fullOut) {
    var m = fullOut.match(/<answer>([\s\S]*?)<\/answer>/i);
    if (m) return { finalAnswer: m[1].trim(), fullOut: fullOut };
    var lines = fullOut
      .split("\n")
      .map(function (l) {
        return l.trim();
      })
      .filter(function (l) {
        return l;
      });
    var best = "";
    for (var i = lines.length - 1; i >= 0; i--) {
      var line = lines[i];
      if (/step\s*\d+/i.test(line)) continue;
      best = line.replace(/^[\*\-\d\.]+\s*/, "").trim();
      if (best) break;
    }
    return { finalAnswer: best || "No answer found", fullOut: fullOut };
  }

  // ========== AUTO FILL ==========
  function doAutoFill(ans) {
    var div = getQuestionDiv();
    if (!div) return false;
    var inputs = div.querySelectorAll(
      'input:not([type="hidden"]):not([type="radio"]):not([type="checkbox"]), textarea'
    );
    if (inputs.length > 0) {
      var plain = ans.replace(/\$+|`|\\\(|\\\)|\\\[|\\\]/g, "").trim();
      if (inputs.length > 1) {
        var parts = [];
        if (
          inputs.length === 3 &&
          plain.match(/^[+-]?\d+\s+\d+\/\d+$/)
        ) {
          var mm = plain.match(/^([+-]?\d+)\s+(\d+)\/(\d+)$/);
          if (mm) parts = [mm[1], mm[2], mm[3]];
        } else if (
          plain.indexOf("/") !== -1 &&
          inputs.length === 2
        ) {
          parts = plain.split("/").filter(function (p) {
            return p.trim().length > 0;
          });
        } else if (plain.indexOf(",") !== -1) {
          parts = plain
            .split(",")
            .map(function (p) {
              return p.trim();
            })
            .filter(function (p) {
              return p.length > 0;
            });
        } else if (
          plain.match(/\s+/) &&
          (plain.match(/\s+/g) || []).length === inputs.length - 1
        ) {
          parts = plain.split(/\s+/).filter(function (p) {
            return p.length > 0;
          });
        }
        if (parts.length === 0 || parts.length < inputs.length) {
          reactSetValue(inputs[0], plain);
          return true;
        }
        inputs.forEach(function (inp, i) {
          reactSetValue(inp, parts[i] || "");
        });
        return true;
      } else {
        reactSetValue(inputs[0], plain);
        logMsg("Filled input: " + plain);
        return true;
      }
    }

    // ---- Multiple choice / button questions ----
    var norm = ans
      .replace(/[\$`\u2018\u2019()\[\]\\]/g, "")
      .replace(/\s+/g, " ")
      .trim()
      .toLowerCase();
    logMsg("Looking for button matching: '" + norm + "'");

    var sels = [
      '[class*="tile"]',
      '[class*="Tile"]',
      '[class*="option"]',
      '[class*="Option"]',
      '[class*="choice"]',
      '[class*="Choice"]',
      '[role="button"]',
      "[tabindex]",
      "button",
      "div[data-value]",
      "span[data-value]",
    ];
    var candidates = [];
    var seen = new Set();
    for (var si = 0; si < sels.length; si++) {
      var found = div.querySelectorAll(sels[si]);
      for (var fi = 0; fi < found.length; fi++) {
        if (!seen.has(found[fi])) {
          seen.add(found[fi]);
          candidates.push(found[fi]);
        }
      }
    }
    logMsg("Found " + candidates.length + " clickable candidates");

    var target = null,
      bestMatch = null,
      bestScore = 0;
    for (var ci = 0; ci < candidates.length; ci++) {
      var el2 = candidates[ci];
      var elText = el2.textContent
        .replace(/[\$`\u2018\u2019()\[\]\\]/g, "")
        .replace(/\s+/g, " ")
        .trim()
        .toLowerCase();
      if (elText === norm) {
        target = el2;
        break;
      }
      if (
        norm.length > 0 &&
        elText.indexOf(norm) !== -1 &&
        elText.length < 200
      ) {
        var score = norm.length / elText.length;
        if (score > bestScore) {
          bestScore = score;
          bestMatch = el2;
        }
      }
      if (elText.length > 0 && norm.indexOf(elText) !== -1) {
        var score2 = elText.length / norm.length;
        if (score2 > bestScore) {
          bestScore = score2;
          bestMatch = el2;
        }
      }
    }
    if (!target && bestScore > 0.4) target = bestMatch;

    if (target) {
      logMsg(
        "Matched: '" +
          (target.textContent || "").substring(0, 50).trim() +
          "' (score: " +
          (bestScore > 0 ? bestScore.toFixed(2) : "exact") +
          ")"
      );
      smartClick(target);
      return true;
    }
    logMsg("No button match found");
    return false;
  }

  function doAutoSubmit() {
    if (config.autoSubmit !== true) return;
    var btn = document.evaluate(
      "/html/body/main/div/article/section/section/div/div[1]/section/div/section/div/button",
      document,
      null,
      XPathResult.FIRST_ORDERED_NODE_TYPE,
      null
    ).singleNodeValue;
    if (!btn)
      btn = document.querySelector("button.submit, button[class*='submit']");
    if (btn) {
      logMsg("Auto-submitting...");
      smartClick(btn);
      if (config.autoNext) setTimeout(doAutoNext, 2000);
    } else {
      logMsg("No submit button found");
    }
  }

  function doAutoNext() {
    var btn = document.evaluate(
      '//button[contains(text(),"Next") or contains(text(),"next")]',
      document,
      null,
      XPathResult.FIRST_ORDERED_NODE_TYPE,
      null
    ).singleNodeValue;
    if (!btn) {
      var nextSels = [
        'button[class*="next"]',
        'a[class*="next"]',
        "button.continue",
      ];
      for (var ns = 0; ns < nextSels.length; ns++) {
        btn = document.querySelector(nextSels[ns]);
        if (btn) break;
      }
    }
    if (btn) {
      logMsg("Auto next");
      smartClick(btn);
      if (config.mode === "autoFill") setTimeout(startAnswer, 1500);
    } else logMsg("No next button");
  }

  // ========== MAIN ANSWER FLOW ==========
  function startAnswer() {
    logMsg("Starting answer...");
    var dv = getQuestionDiv();
    if (!dv) {
      logMsg("No question found");
      UI.status.textContent = "No question found";
      UI.status.className = "au-status error";
      return;
    }
    config.lastState = dv.innerHTML;

    var text = extractTextOnly(dv);
    var html = extractEssentialHTML(dv);
    var userPrompt = "Question:\n" + text + "\n";
    if (html.length < 8000)
      userPrompt += "\nPage HTML:\n" + html + "\n";
    var latex = captureLatex(dv);
    if (latex) userPrompt += "LaTeX:\n" + latex + "\n";
    logMsg("Content: " + text.length + " chars");

    UI.answerBox.style.display = "none";
    UI.status.textContent = "Thinking...";
    UI.status.className = "au-status active";
    startProgress();

    var systemPrompt;
    if (config.mode === "autoFill") {
      systemPrompt =
        "You are an IXL math solver. Analyze the question and solve it.\n\nFORMAT:\n## Steps\n[Brief solution]\n\n<answer>PLAIN_ANSWER</answer>\n\nRULES FOR <answer>:\n- ONLY plain text, NO LaTeX, NO $, NO \\frac, NO markdown\n- Plain fractions: 3/4 not \\frac{3}{4}\n- For multiple choice: the EXACT text of the correct option";
    } else {
      systemPrompt =
        "Solve the math problem.\n\nFORMAT:\n## Solution Steps\n[Step-by-step]\n\n## Final Answer\n<answer>[answer]</answer>\n\nRULES FOR <answer>:\n- ONLY plain text, NO LaTeX, NO $, NO \\frac, NO markdown\n- Plain fractions: 3/4, decimals: 73.6\n- Multiple choice: EXACT text of correct option";
    }

    var fullPrompt = systemPrompt + "\n\n" + userPrompt;
    logMsg("Calling AI (direct via CSP bypass)...");

    var aiPromise = getAIResponse(fullPrompt, logMsg);
    var timeoutPromise = new Promise(function (_, reject) {
      setTimeout(function () {
        reject(new Error("Timeout after 90s"));
      }, 90000);
    });

    Promise.race([aiPromise, timeoutPromise])
      .then(function (fullOut) {
        stopProgress();
        logMsg("Got response (" + fullOut.length + " chars)");

        var answerMatch = fullOut.match(/<answer>([\s\S]*?)<\/answer>/i);
        var finalAnswer = "",
          stepsText = "";
        if (answerMatch) {
          finalAnswer = cleanAnswer(answerMatch[1].trim());
          stepsText = fullOut
            .replace(/<answer>[\s\S]*?<\/answer>/i, "")
            .trim();
        } else {
          var extracted = extractFinalAnswer(fullOut);
          finalAnswer = cleanAnswer(extracted.finalAnswer);
          stepsText = fullOut;
        }

        if (config.mode === "displayOnly")
          UI.answerBox.style.display = "block";

        UI.answerValue.innerHTML = simpleMarkdown(finalAnswer);
        UI.stepsBody.innerHTML = simpleMarkdown(stepsText);

        if (config.mode === "autoFill") {
          doAutoFill(finalAnswer);
          if (config.autoSubmit === true) {
            logMsg("Auto Submit ON, submitting in 3s...");
            setTimeout(doAutoSubmit, 3000);
          }
        }

        UI.status.textContent = "Done";
        UI.status.className = "au-status";
      })
      .catch(function (err) {
        stopProgress();
        UI.status.textContent = "Error: " + (err.message || err);
        UI.status.className = "au-status error";
        logMsg("Error: " + (err.message || err));
      });
  }

  // ========== INIT ==========
  // Pre-warm the CSP bypass iframe
  getProxyIframe().then(function () {
    logMsg("CSP bypass ready - all AI providers available");
  });

  logMsg(
    "AU IXL Standalone loaded -- direct page context, blob iframe CSP bypass"
  );
  logMsg("Endpoints: " + AI_ENDPOINTS.length + " across multiple domains");
})();
