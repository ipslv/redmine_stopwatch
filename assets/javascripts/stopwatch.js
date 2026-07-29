/* Redmine Stopwatch Plugin — Client-side timer widget */
(function ($) {
  'use strict';

  // ── State ────────────────────────────────────────────────────────────────
  var widget          = null;
  var timerState      = 'stopped';   // 'stopped' | 'running' | 'paused'
  var accSeconds      = 0;           // accumulated_seconds from server
  var startedAtMs     = null;        // Date.now() equivalent of started_at
  var tickInterval    = null;
  var tickTimeout     = null;        // used to align first tick to minute boundary
  var busy            = false;       // prevents concurrent API calls
  var pendingCount    = 0;           // unsaved segments count

  // Timer context (the issue/project the timer was started on)
  var timerContextLabel = '';
  var timerContextUrl   = '';
  var timerIssueId      = '';
  var timerProjectId    = '';

  // Page context (current page — static for this page load)
  var pageContextLabel  = '';
  var pageContextUrl    = '';
  var pageIssueId       = '';
  var pageProjectId     = '';

  // ── Cross-tab sync ────────────────────────────────────────────────────────

  var swChannel = null;

  function broadcastState(data) {
    if (!swChannel) { return; }
    swChannel.postMessage({
      state:                  data.state,
      accumulated_seconds:    data.accumulated_seconds,
      started_at:             data.started_at,
      pending_segments_count: data.pending_segments_count,
      timerContextLabel:      timerContextLabel,
      timerContextUrl:        timerContextUrl,
      timerIssueId:           timerIssueId,
      timerProjectId:         timerProjectId
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute('content') : '';
  }

  function formatTime(totalSeconds) {
    var totalMinutes = Math.floor(totalSeconds / 60);
    var hours        = Math.floor(totalMinutes / 60);
    var minutes      = totalMinutes % 60;
    return hours + ':' + (minutes < 10 ? '0' : '') + minutes;
  }

  function computeElapsed() {
    if (timerState === 'running' && startedAtMs !== null) {
      return Math.max(0, accSeconds + Math.floor((Date.now() - startedAtMs) / 1000));
    }
    return accSeconds;
  }

  // Safely escape a string for use in HTML attribute/text content
  function escHtml(str) {
    var div = document.createElement('div');
    div.appendChild(document.createTextNode(str || ''));
    return div.innerHTML;
  }

  // Reserved path segments — populated from server data-reserved-paths in $(document).ready().
  // Initialised to an empty pattern so detectContext() is safe before DOM ready.
  var RESERVED_PROJECT_PATHS = /^$/;

  // Detect issue_id / project_id from current URL (used as API params)
  function detectContext() {
    var path = window.location.pathname;
    var issueMatch   = path.match(/\/issues\/(\d+)/);
    var projectMatch = path.match(/\/projects\/([^/]+)/);

    if (issueMatch) { return { issue_id: issueMatch[1] }; }
    if (projectMatch && !RESERVED_PROJECT_PATHS.test(projectMatch[1])) {
      return { project_id: projectMatch[1] };
    }
    return {};
  }

  // True if the timer context and current page context are the same
  function isSameContext() {
    // Both have an issue — compare issues
    if (timerIssueId && pageIssueId) {
      return timerIssueId === pageIssueId;
    }
    // Both have only a project (no issue) — compare projects
    if (!timerIssueId && timerProjectId && !pageIssueId && pageProjectId) {
      return timerProjectId === pageProjectId;
    }
    // Both have no context
    if (!timerIssueId && !timerProjectId && !pageIssueId && !pageProjectId) {
      return true;
    }
    return false;
  }

  // ── API calls ─────────────────────────────────────────────────────────────

  function setButtonsDisabled(disabled) {
    if (!widget) { return; }
    var buttons = widget.querySelectorAll('button.sw-btn');
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].disabled = disabled;
    }
  }

  function apiCall(url, method, extraParams, callback) {
    if (busy) { return; }
    busy = true;
    setButtonsDisabled(true);

    var params = $.extend({}, detectContext(), extraParams || {});
    $.ajax({
      url:      url,
      type:     method,
      data:     params,
      dataType: 'json',
      headers:  { 'X-CSRF-Token': csrfToken() },
      success: function (data) {
        busy = false;
        if (callback) { callback(data); }
        broadcastState(data);
      },
      error: function (xhr) {
        busy = false;
        setButtonsDisabled(false);
        console.error('[Stopwatch] API error', xhr.status, xhr.responseText);
      }
    });
  }

  // ── State update ──────────────────────────────────────────────────────────

  function isOnSegmentsPage() {
    var segUrl = widget && widget.dataset.segmentsUrl;
    if (!segUrl) { return false; }
    var segPath = segUrl.split('?')[0].split('#')[0];
    return window.location.pathname === segPath;
  }

  function applyState(data) {
    if (isOnSegmentsPage()) {
      window.location.reload();
      return;
    }
    timerState = data.state || 'stopped';
    accSeconds = data.accumulated_seconds || 0;

    if (data.started_at) {
      startedAtMs = new Date(data.started_at).getTime();
    } else {
      startedAtMs = null;
    }

    if (typeof data.pending_segments_count !== 'undefined') {
      pendingCount = data.pending_segments_count;
    }

    renderWidget();
    resetTick();
  }

  // After start/snap the timer context becomes the current page context
  function applyStateAfterStart(data) {
    timerContextLabel = pageContextLabel;
    timerContextUrl   = pageContextUrl;
    timerIssueId      = pageIssueId;
    timerProjectId    = pageProjectId;
    applyState(data);
  }

  // After stop, clear timer context
  function applyStateAfterStop(data) {
    timerContextLabel = '';
    timerContextUrl   = '';
    timerIssueId      = '';
    timerProjectId    = '';
    applyState(data);
  }

  // ── Tick ──────────────────────────────────────────────────────────────────

  function resetTick() {
    if (tickTimeout)  { clearTimeout(tickTimeout);   tickTimeout  = null; }
    if (tickInterval) { clearInterval(tickInterval); tickInterval = null; }
    if (timerState !== 'running') { return; }

    // Align the first tick to the next whole-minute boundary
    var msUntilNextMinute = 60000 - (Date.now() % 60000);
    tickTimeout = setTimeout(function () {
      tickTimeout  = null;
      renderWidget();
      tickInterval = setInterval(function () { renderWidget(); }, 60000);
    }, msUntilNextMinute);
  }

  // ── Render ────────────────────────────────────────────────────────────────

  function renderSegmentsLink(segUrl) {
    var s = '<a class="sw-btn sw-list" href="' + segUrl + '" title="Segments">\u2630';
    if (pendingCount > 0) {
      s += '<span class="sw-badge">' + pendingCount + '</span>';
    }
    s += '</a>';
    return s;
  }

  function renderContextLink(label, url, extraClass) {
    var cls = 'sw-ctx' + (extraClass ? ' ' + extraClass : '');
    return '<a class="' + cls + '" href="' + escHtml(url) + '">' + escHtml(label) + '</a>';
  }

  function renderWidget() {
    if (!widget) { return; }

    var segUrl  = widget.dataset.segmentsUrl;
    var elapsed = formatTime(computeElapsed());
    var sameCtx = isSameContext();
    var html    = '';

    if (timerState === 'stopped') {
      // [pageCtxLink ▶ | ☰ badge]
      if (pageContextLabel) {
        html += renderContextLink(pageContextLabel, pageContextUrl);
      }
      html += '<button class="sw-btn sw-start" title="Start">\u25B6</button>';
      html += '<span class="sw-vsep"></span>';
      html += renderSegmentsLink(segUrl);

    } else if (timerState === 'running') {
      // [timerCtxLink - H:MM | ⏸ ⏹ [| pageCtxLink] ⏭ | ☰ badge]
      if (timerContextLabel) {
        html += renderContextLink(timerContextLabel, timerContextUrl);
        html += '<span class="sw-sep">-</span>';
      }
      html += '<span class="sw-time">' + elapsed + '</span>';
      html += '<span class="sw-vsep"></span>';
      html += '<button class="sw-btn sw-pause" title="Pause">\u23F8</button>';
      html += '<button class="sw-btn sw-stop"  title="Stop">\u23F9</button>';
      if (!sameCtx && pageContextLabel) {
        html += '<span class="sw-vsep"></span>';
        html += renderContextLink(pageContextLabel, pageContextUrl, 'sw-ctx-page');
      }
      html += '<button class="sw-btn sw-snap"  title="Next segment">\u23ED</button>';
      html += '<span class="sw-vsep"></span>';
      html += renderSegmentsLink(segUrl);

    } else if (timerState === 'paused') {
      // [timerCtxLink - H:MM | ⏯ ⏹ [| pageCtxLink] ⏭ | ☰ badge]
      if (timerContextLabel) {
        html += renderContextLink(timerContextLabel, timerContextUrl);
        html += '<span class="sw-sep">-</span>';
      }
      html += '<span class="sw-time sw-paused">' + elapsed + '</span>';
      html += '<span class="sw-vsep"></span>';
      html += '<button class="sw-btn sw-resume" title="Resume">\u23EF</button>';
      html += '<button class="sw-btn sw-stop"   title="Stop">\u23F9</button>';
      if (!sameCtx && pageContextLabel) {
        html += '<span class="sw-vsep"></span>';
        html += renderContextLink(pageContextLabel, pageContextUrl, 'sw-ctx-page');
      }
      html += '<button class="sw-btn sw-snap"   title="Next segment">\u23ED</button>';
      html += '<span class="sw-vsep"></span>';
      html += renderSegmentsLink(segUrl);
    }

    widget.innerHTML = html;
    bindButtons();
  }

  // ── Event binding ─────────────────────────────────────────────────────────

  function bindButtons() {
    var startUrl  = widget.dataset.startUrl;
    var pauseUrl  = widget.dataset.pauseUrl;
    var resumeUrl = widget.dataset.resumeUrl;
    var snapUrl   = widget.dataset.snapUrl;
    var stopUrl   = widget.dataset.stopUrl;

    var startBtn  = widget.querySelector('.sw-start');
    var pauseBtn  = widget.querySelector('.sw-pause');
    var resumeBtn = widget.querySelector('.sw-resume');
    var stopBtn   = widget.querySelector('.sw-stop');
    var snapBtn   = widget.querySelector('.sw-snap');

    if (startBtn)  { startBtn.addEventListener('click',  function () { apiCall(startUrl,  'POST', {}, applyStateAfterStart); }); }
    if (pauseBtn)  { pauseBtn.addEventListener('click',  function () { apiCall(pauseUrl,  'POST', {}, applyState); }); }
    if (resumeBtn) { resumeBtn.addEventListener('click', function () { apiCall(resumeUrl, 'POST', {}, applyState); }); }
    if (snapBtn)   { snapBtn.addEventListener('click',   function () { apiCall(snapUrl,   'POST', {}, applyStateAfterStart); }); }
    if (stopBtn)   { stopBtn.addEventListener('click',   function () { apiCall(stopUrl,   'POST', {}, applyStateAfterStop); }); }
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  $(document).ready(function () {
    widget = document.getElementById('stopwatch-widget');
    if (!widget) { return; }

    // Build reserved-paths regex from server data (single source of truth in Ruby)
    var reservedPathsAttr = widget.dataset.reservedPaths || '';
    if (reservedPathsAttr) {
      var paths = reservedPathsAttr.split(',').filter(Boolean);
      RESERVED_PROJECT_PATHS = new RegExp('^(' + paths.join('|') + ')$');
    }

    // Read initial state rendered by server into data-* attributes
    timerState = widget.dataset.state || 'stopped';
    accSeconds = parseInt(widget.dataset.accumulatedSeconds, 10) || 0;
    pendingCount = parseInt(widget.dataset.pendingCount, 10) || 0;

    var startedAtStr = widget.dataset.startedAt;
    startedAtMs = startedAtStr ? new Date(startedAtStr).getTime() : null;

    // Timer context (from server)
    timerContextLabel = widget.dataset.timerContextLabel || '';
    timerContextUrl   = widget.dataset.timerContextUrl   || '';
    timerIssueId      = widget.dataset.timerIssueId      || '';
    timerProjectId    = widget.dataset.timerProjectId    || '';

    // Page context (from server — static for this page load)
    pageContextLabel  = widget.dataset.pageContextLabel  || '';
    pageContextUrl    = widget.dataset.pageContextUrl    || '';
    pageIssueId       = widget.dataset.pageIssueId       || '';
    pageProjectId     = widget.dataset.pageProjectId     || '';

    // Move widget into #top-menu (it was injected before #wrapper by the hook).
    // On mobile Redmine hides #top-menu; fall back to .flyout-menu if present.
    var topMenu = document.getElementById('top-menu');
    if (topMenu && window.getComputedStyle(topMenu).display !== 'none') {
      topMenu.appendChild(widget);
    } else {
      var flyout = document.querySelector('.flyout-menu ul') ||
                   document.querySelector('.flyout-menu');
      if (flyout) {
        var li = document.createElement('li');
        li.id = 'stopwatch-widget-mobile';
        li.appendChild(widget);
        flyout.appendChild(li);
      }
      // If neither container exists, leave widget in place (before #wrapper).
    }

    try { swChannel = new BroadcastChannel('stopwatch-' + (widget.dataset.userId || '0')); } catch (e) { /* unsupported */ }
    if (swChannel) {
      swChannel.onmessage = function (e) {
        var msg = e.data;
        timerContextLabel = msg.timerContextLabel || '';
        timerContextUrl   = msg.timerContextUrl   || '';
        timerIssueId      = msg.timerIssueId      || '';
        timerProjectId    = msg.timerProjectId    || '';
        applyState(msg);
      };
    }

    renderWidget();
    resetTick();
  });

}(jQuery));
