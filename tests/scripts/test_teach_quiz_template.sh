#!/usr/bin/env bash
# Behaviour test for skills/teach/templates/lesson.js: build a three-question quiz
# fixture, pick right / wrong / skip in headless Chrome, and assert the results line
# the learner pastes into the session. SKIPs when no Chrome/Chromium is installed.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

CHROME=""
for c in google-chrome google-chrome-stable chromium chromium-browser; do
  if command -v "$c" >/dev/null 2>&1; then CHROME=$(command -v "$c"); break; fi
done
MAC_CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[[ -z "$CHROME" && -x "$MAC_CHROME" ]] && CHROME="$MAC_CHROME"
if [[ -z "$CHROME" ]]; then
  echo "SKIP: no Chrome/Chromium for the headless quiz test"
  exit 0
fi

TMP=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/assets" "$TMP/lessons"
cp "$REPO_ROOT/skills/teach/templates/lesson.js" "$TMP/assets/lesson.js"

# Fixture per QUIZ-FORMAT.md's markup contract. The probe runs after lesson.js:
# Q1 right, Q2 wrong, Q3 left unanswered; it copies the results line and Q2's
# feedback into #probe for --dump-dom to carry out.
cat > "$TMP/lessons/0001-fixture.html" <<'EOF'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Fixture</title></head>
<body>
<ol class="quiz" data-lesson="fixture/0001">
  <li data-answer="a" data-why="Why one.">
    <p class="question">One?</p>
    <div class="options">
      <button type="button" data-option="a">Alpha</button>
      <button type="button" data-option="b">Bravo</button>
    </div>
    <p class="feedback" aria-live="polite"></p>
  </li>
  <li data-answer="c" data-why="Why two.">
    <p class="question">Two?</p>
    <div class="options">
      <button type="button" data-option="a">3 A</button>
      <button type="button" data-option="b">8 A</button>
      <button type="button" data-option="c">48 A</button>
    </div>
    <p class="feedback" aria-live="polite"></p>
  </li>
  <li data-answer="b" data-why="Why three.">
    <p class="question">Three?</p>
    <div class="options">
      <button type="button" data-option="a">Left</button>
      <button type="button" data-option="b">Right</button>
    </div>
    <p class="feedback" aria-live="polite"></p>
  </li>
</ol>
<script src="../assets/lesson.js"></script>
<script>
  var q = document.querySelectorAll(".quiz > li");
  q[0].querySelector('[data-option="a"]').click();
  q[1].querySelector('[data-option="b"]').click();
  var out = document.createElement("pre");
  out.id = "probe";
  out.textContent = [
    document.querySelector(".results-line").textContent,
    q[1].querySelector(".feedback").textContent,
    String(q[1].querySelector('[data-option="a"]').disabled),
    String(document.querySelectorAll(".results-row button").length)
  ].join("\n");
  document.body.append(out);
</script>
</body></html>
EOF

DOM=$("$CHROME" --headless=new --disable-gpu --no-sandbox --allow-file-access-from-files \
  --dump-dom "file://$TMP/lessons/0001-fixture.html" 2>/dev/null) || true
PROBE=$(printf '%s' "$DOM" | sed -n '/<pre id="probe">/,/<\/pre>/p' \
  | sed -e 's/.*<pre id="probe">//' -e 's/<\/pre>.*//' \
        -e 's/&amp;/\&/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g')
if [[ -z "$PROBE" ]]; then
  echo "FAIL: no probe output from headless Chrome" >&2
  exit 1
fi

LINE=$(sed -n 1p <<<"$PROBE")
FEEDBACK=$(sed -n 2p <<<"$PROBE")
DISABLED=$(sed -n 3p <<<"$PROBE")
COPY_BUTTONS=$(sed -n 4p <<<"$PROBE")

assert_eq 'fixture/0001 · 1/3 · Q1 ✓ · Q2 ✗ picked “8 A” (answer “48 A”) · Q3 —' "$LINE" \
  "results line: right, wrong with both picks named, unanswered as —"
assert_eq 'Not this one. The answer is “48 A”. Why two.' "$FEEDBACK" \
  "a wrong pick reveals the answer and data-why"
assert_eq "true" "$DISABLED" "one try per question: every option disabled after a pick"
assert_eq "1" "$COPY_BUTTONS" "one results block with a Copy button per quiz"

echo "test_teach_quiz_template: PASS"
