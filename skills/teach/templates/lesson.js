// lesson.js: quiz behaviour for a teach topic. Copied verbatim from oskr's
// skills/teach/templates/lesson.js into <topic>/assets/lesson.js; topic-specific
// behaviour lives in its own script beside it, never in this copy.
// Contract (markup, results line, styling hooks): skills/teach/QUIZ-FORMAT.md.
// Verified by tests/scripts/test_teach_quiz_template.sh in the oskr repo.
//
// Each question allows one try; its explanation stays hidden until an answer is
// picked. After each .quiz the script appends a results block: one line
// summarising every pick plus a Copy button, so the learner can paste it into the
// Claude session. The line stays visible, so copying by hand works when the
// clipboard is blocked.
(function () {
  document.querySelectorAll(".quiz").forEach(function (quiz) {
    var items = Array.prototype.slice.call(quiz.querySelectorAll(":scope > li"));
    var picks = items.map(function () {
      return null;
    });
    var lesson = quiz.dataset.lesson || document.title;

    var box = document.createElement("div");
    box.className = "results";
    var hint = document.createElement("p");
    hint.textContent =
      "When you’ve answered every question, copy your results and paste them into the Claude session.";
    var line = document.createElement("output");
    line.className = "results-line";
    var btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = "Copy results";
    var status = document.createElement("span");
    status.className = "results-status";
    status.setAttribute("aria-live", "polite");
    var row = document.createElement("div");
    row.className = "results-row";
    row.append(btn, status);
    box.append(hint, line, row);
    quiz.after(box);

    function summary() {
      var right = picks.filter(function (p) {
        return p && p.right;
      }).length;
      var parts = picks.map(function (p, i) {
        var q = "Q" + (i + 1);
        if (!p) return q + " —";
        if (p.right) return q + " ✓";
        return q + " ✗ picked “" + p.picked + "” (answer “" + p.answer + "”)";
      });
      return [lesson, right + "/" + picks.length].concat(parts).join(" · ");
    }

    function refresh() {
      line.textContent = summary();
    }

    items.forEach(function (item, i) {
      var answer = item.dataset.answer;
      var buttons = item.querySelectorAll(".options button");
      var feedback = item.querySelector(".feedback");
      var correct = item.querySelector('[data-option="' + answer + '"]');

      buttons.forEach(function (b) {
        b.addEventListener("click", function () {
          var right = b.dataset.option === answer;
          buttons.forEach(function (x) {
            x.disabled = true;
          });
          b.dataset.state = right ? "right" : "wrong";
          correct.dataset.state = "right";

          var verdict = document.createElement("span");
          verdict.className = "verdict";
          verdict.textContent = right
            ? "Right."
            : "Not this one. The answer is “" + correct.textContent.trim() + "”.";
          feedback.dataset.state = right ? "right" : "wrong";
          feedback.replaceChildren(verdict, " " + item.dataset.why);

          picks[i] = {
            right: right,
            picked: b.textContent.trim(),
            answer: correct.textContent.trim()
          };
          refresh();
        });
      });
    });

    btn.addEventListener("click", function () {
      var text = summary();
      line.textContent = text;
      function selectLine() {
        var range = document.createRange();
        range.selectNodeContents(line);
        var sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
        status.textContent = "Couldn’t reach the clipboard. The line is selected: copy it by hand.";
      }
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(function () {
          status.textContent = "Copied. Paste it into the Claude session.";
        }, selectLine);
      } else {
        selectLine();
      }
    });

    refresh();
  });
})();
