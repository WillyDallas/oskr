# Quiz Format

Every lesson ends with a quiz: retrieval practice the user takes alone in the browser.
Its **results line** carries their picks into the session, where the chat round
(SKILL.md Step 2) picks up.

## Script

Quiz behaviour is [templates/lesson.js](./templates/lesson.js). Copy it verbatim (Read,
then Write) to `$TOPIC_DIR/assets/lesson.js` the first time a topic has a quiz, and
again whenever the topic's copy has no `results-line` in it. Topic-specific behaviour
(a timer, a drill) goes in its own script beside it — never into this copy, which a
later re-copy would overwrite.

## Markup contract

```html
<ol class="quiz" data-lesson="<topic-slug>/NNNN">
  <li data-answer="b" data-why="<explanation shown after any pick; names each slip>">
    <p class="question">…</p>
    <div class="options">
      <button type="button" data-option="a">…</button>
      <button type="button" data-option="b">…</button>
      <button type="button" data-option="c">…</button>
    </div>
    <p class="feedback" aria-live="polite"></p>
  </li>
</ol>
<script src="../assets/lesson.js"></script>
```

The script appends the results block after each `.quiz`. The topic stylesheet styles
these hooks: `.options button[data-state="right"|"wrong"]`, `.feedback[data-state]`,
`.verdict`, `.results`, `.results-line`, `.results-row`, `.results-status`.

## Results line

```
<topic-slug>/NNNN · <right>/<total> · Q1 ✓ · Q2 ✗ picked “<option>” (answer “<option>”) · Q3 —
```

`—` marks an unanswered question. The user pastes this line into the session; it is
the chat round's input.

## Options

- **Length gives no clue**: options of similar length; the answer is not reliably the
  longest, and its position rotates across questions.
- **Every distractor is a named slip** — a wrong operation, a skipped unit conversion,
  a confused term — and `data-why` names it. A wrong pick in the results line then
  tells the chat round which slip to target.
- **Interleave**: at least one question draws on an earlier lesson's idea.
