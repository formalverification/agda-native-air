/* Typed replay for the archived agda-mcp sessions (agda-native-air, #85).
 *
 * File: web/assets/replay.js
 *
 * The finished sessions are already in the HTML -- scripts/python/demo/
 * render.py puts them there, one tabpanel per session, every call beside
 * its answer and every verdict stated -- so a crawler, a reader with
 * JavaScript off and a reduced-motion reader all see complete sessions with
 * this file doing nothing.  What this adds is two layers, and the split
 * between them is deliberate.
 *
 * The tabs are navigation, not motion, so they are wired wherever this
 * script runs at all: a reduced-motion reader gets five finished sessions,
 * switched instantly.  They ship hidden, and so does every replay button,
 * because a control that switches nothing should not exist on a page that
 * has no script.
 *
 * The replay runs only where motion is allowed.  The first time a panel is
 * shown it rewinds and plays its session back: the model's words and its
 * tool calls are typed, one code point at a time, and every answer *appears*
 * whole after a beat.  That is not a stylistic choice.  The agent typed the
 * call; Agda answered in one response, the way a compiler answers in whole
 * lines, and typing the server's words would put them in the agent's hands.
 * The thinking markers hold the stage for a beat and appear: there is no
 * text to type, because the archive keeps each thinking block's signature
 * and an empty string in place of its passage.
 *
 * One session plays, and then it stops.  There is no auto-advance from tab
 * to tab and no loop: a proof session is a minute of reading, not a
 * three-second vignette, and five of them in a row would be a demand rather
 * than an offer.  Any gesture (choosing a tab, pressing the control) takes
 * the wheel; from then on a panel plays only when asked.
 *
 * The one control each panel has is a stop as well as a replay, because the
 * first session starts on its own and the five run 6 to 25 seconds: that is
 * auto-updating content beside other content, and WCAG 2.2.2 asks for a way
 * to stop it.  While a panel plays, the button reads "stop" and settles it
 * to the finished session; at rest it reads "replay" and starts one.
 *
 * Timing comes from the --motion-* custom properties, read off computed
 * style, so web/assets/demo.css stays the one place the rhythm is decided.
 * Text is iterated by code point (Array.from, never charAt): the content is
 * full of astral glyphs -- the 'A' of an algebra is U+1D468 and needs a
 * surrogate pair -- and slicing one in half flashes a replacement character
 * mid-word.  Nothing here invents content: every character typed was already
 * in the element it is typed back into.
 */
(function () {
  "use strict";

  function start() {
    document.querySelectorAll(".replay").forEach(arm);
  }

  function arm(root) {
    if (root.dataset.armed) return;
    root.dataset.armed = "1";

    var tablist = root.querySelector(".replay-tabs");
    var tabs = [].slice.call(root.querySelectorAll(".replay-tab"));
    var panels = [].slice.call(root.querySelectorAll(".replay-panel"))
      .map(build);
    if (!panels.length || panels.indexOf(null) !== -1) return;
    if (tabs.length !== panels.length) return;

    var reduced =
      window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    var canReplay = !reduced && "IntersectionObserver" in window;
    var active = 0;

    var style = getComputedStyle(document.body);
    function ms(name, fallback) {
      var raw = style.getPropertyValue(name).trim();
      var n = parseFloat(raw);
      // NaN means the token is absent; 0 is a value someone may set on
      // purpose, and an instant replay is still an honest one.
      if (Number.isNaN(n)) return fallback;
      return raw.endsWith("ms") ? n : n * 1000;
    }
    var TYPE = ms("--motion-type", 14);
    var CALL = ms("--motion-call", 9);
    var BEAT = ms("--motion-beat", 260);
    var ANSWER = ms("--motion-answer", 420);
    var THOUGHT = ms("--motion-thought", 700);
    var ENTER = ms("--motion-enter", 500);

    function wait(t) {
      return new Promise(function (r) { setTimeout(r, t); });
    }

    // The replay control does two jobs, and which one decides whether this
    // page is usable.  A replay starts on scroll into view and runs for 15
    // to 25 seconds on the longer sessions, which is auto-updating content
    // presented alongside the rest of the page, so WCAG 2.2.2 requires a
    // way to stop it.  While a panel is playing this button stops it; while
    // it is at rest, it plays it again.  Stopping settles the panel to the
    // finished session rather than freezing it mid-line: a half-typed call
    // is not a quotation of anything, and the finished state is the truth
    // the replay was only ever arriving at.
    var REPLAY_LABEL = "\u21bb replay";
    var STOP_LABEL = "\u25a0 stop";

    function setControl(p, playing) {
      p.playing = playing;
      p.button.textContent = playing ? STOP_LABEL : REPLAY_LABEL;
      p.button.setAttribute("aria-label", playing
        ? "Stop the replay and show the finished session"
        : "Replay this session");
    }

    // One state object per panel; null if the markup breaks the contract
    // render.py documents, in which case the whole player is left at rest.
    function build(el) {
      var steps = [].slice.call(el.querySelectorAll(".step")).map(function (s) {
        var typed = [].slice.call(s.querySelectorAll("[data-type-text]"))
          .map(function (t) {
            return { el: t, html: t.innerHTML, text: t.textContent };
          });
        return {
          el: s,
          kind: s.dataset.kind,
          typed: typed,
          after: [].slice.call(s.querySelectorAll("[data-after]"))
        };
      });
      var stream = el.querySelector(".replay-stream");
      var button = el.querySelector(".replay-again");
      if (!steps.length || !stream || !button) return null;
      return { el: el, steps: steps, stream: stream, button: button,
               played: false, run: 0 };
    }

    // A panel's finished state, exactly as the renderer shipped it.  Used
    // when a tab switch interrupts a replay, so an abandoned panel is a
    // finished session the next time it is shown, never a half-typed one.
    function settle(p) {
      p.run += 1;
      setControl(p, false);
      p.steps.forEach(function (step) {
        step.el.hidden = false;
        step.typed.forEach(function (t) {
          t.el.innerHTML = t.html;
          t.el.classList.remove("is-typing");
        });
        step.after.forEach(function (el) { el.hidden = false; });
      });
      p.stream.scrollTop = 0;
    }

    function play(p) {
      var mine = ++p.run;
      p.played = true;
      setControl(p, true);
      function live() { return p.run === mine; }
      function step(fn) {
        return function () { if (live()) return fn(); };
      }

      // Type plain text into an element, one code point per beat, jittered
      // +-35% so the rhythm reads as hands rather than a metronome.
      function typeInto(t, rate) {
        var glyphs = Array.from(t.text);
        t.el.classList.add("is-typing");
        return new Promise(function (resolve) {
          var i = 1;
          (function tick() {
            if (!live()) { resolve(); return; }
            t.el.textContent = glyphs.slice(0, i).join("");
            if (i < glyphs.length) {
              i += 1;
              setTimeout(tick, rate * (0.65 + 0.7 * Math.random()));
            } else {
              // The renderer's own markup is restored once the line is
              // typed: this file colours nothing and marks up nothing.
              t.el.innerHTML = t.html;
              t.el.classList.remove("is-typing");
              resolve();
            }
          })();
        });
      }

      function toBottom() { p.stream.scrollTop = p.stream.scrollHeight; }

      // Rewind: every step hidden, every typed element emptied, every
      // answer folded away.  The finished markup is kept in `typed[].html`,
      // so nothing is lost and nothing is re-derived.
      p.steps.forEach(function (s) {
        s.el.hidden = true;
        s.typed.forEach(function (t) {
          t.el.textContent = "";
          t.el.classList.remove("is-typing");
        });
        s.after.forEach(function (el) { el.hidden = true; });
      });
      p.stream.scrollTop = 0;

      var q = wait(ENTER);
      p.steps.forEach(function (s) {
        var rate = s.kind === "call" ? CALL : TYPE;
        q = q.then(step(function () {
          s.el.hidden = false;
          toBottom();
          return s.kind === "thinking" ? wait(THOUGHT) : null;
        }));
        s.typed.forEach(function (t) {
          q = q.then(step(function () {
            var typing = typeInto(t, rate);
            toBottom();
            return typing;
          }));
        });
        // The answer, and everything else the renderer put beside the typed
        // line, arrives whole after a beat.  A call waits BEAT before going
        // out and ANSWER for the reply; a plain remark needs neither.
        if (s.after.length) {
          q = q.then(step(function () {
            return wait(s.kind === "call" ? BEAT + ANSWER : BEAT);
          })).then(step(function () {
            s.after.forEach(function (el) { el.hidden = false; });
            toBottom();
          }));
        }
      });
      // Only this run may clear the control: a run cancelled by a stop or a
      // tab switch has already had `settle` do it, and `step` skips this.
      return q.then(step(function () { setControl(p, false); }));
    }

    function select(i) {
      if (i === active) return;
      if (canReplay) settle(panels[active]);
      panels[active].el.classList.remove("is-active");
      tabs.forEach(function (t, j) {
        t.setAttribute("aria-selected", j === i ? "true" : "false");
        if (j === i) t.removeAttribute("tabindex");
        else t.setAttribute("tabindex", "-1");
      });
      active = i;
      panels[i].el.classList.add("is-active");
      if (canReplay && !panels[i].played) play(panels[i]);
    }

    // The tab set is what `has-js` in the stylesheet is waiting for: the
    // class is on the root element before first paint, so the panels are
    // already collapsed and this only marks which one is showing.
    panels.forEach(function (p, i) {
      p.el.classList.toggle("is-active", i === 0);
    });
    tabs.forEach(function (tab, i) {
      tab.addEventListener("click", function () { select(i); });
    });
    if (tablist) {
      tablist.addEventListener("keydown", function (e) {
        var at = tabs.indexOf(document.activeElement);
        if (at === -1) return;
        var to = at;
        if (e.key === "ArrowRight") to = (at + 1) % tabs.length;
        else if (e.key === "ArrowLeft") to = (at + tabs.length - 1) % tabs.length;
        else if (e.key === "Home") to = 0;
        else if (e.key === "End") to = tabs.length - 1;
        else return;
        e.preventDefault();
        tabs[to].focus();
        select(to);
      });
      tablist.hidden = false;
    }

    // Everything past here is the replay itself, and exists only where
    // motion is allowed: no button is revealed and no observer is armed, so
    // a reduced-motion reader is left with five finished sessions and a tab
    // bar, which is the whole of what this page has to say.
    if (!canReplay) return;

    panels.forEach(function (p) {
      setControl(p, false);
      p.button.hidden = false;
      p.button.addEventListener("click", function () {
        if (p.playing) settle(p); else play(p);
      });
    });

    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        io.disconnect();
        if (!panels[active].played) play(panels[active]);
      });
    }, { threshold: 0.2 });
    io.observe(root);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
