# JS tests

No test runner and no dependencies — these are plain `node` scripts, because the
fork has no JS toolchain and adding one for a handful of assertions is not worth the
maintenance.

```bash
node tests/js/test-imgtools.js          # asserts against the shipped file
node tests/js/test-imgtools.js <path>   # same assertions against another revision
```

Exit status is 0 on pass, 1 on failure, so it drops into CI unchanged if a workflow
is ever added.

## Why they take a path argument

So a fix can be shown to actually fix something. Every one of these was written
against a real defect, and the useful measurement is running the *same* assertions
against the previous revision and watching them fail:

```bash
git show origin/dev-all-features:js/symb/collections.editor.imgtools.js > /tmp/base.js
node tests/js/test-imgtools.js /tmp/base.js     # expect failures
```

A test that passes both before and after a change is either testing nothing or
testing something the change did not touch. Several assertions here deliberately
pass in both directions — those are the regression guard, confirming the fix did
not break the working path.

## test-imgtools.js

Drives the real `collections.editor.imgtools.js` in a stubbed DOM (`node:vm`), so the
tests cannot drift from shipped code. Covers handover-audit findings high 4, high 5
(both sites), medium 9 and low 6, plus two regressions introduced by an earlier
version of the high 4/5 fix and caught in review:

- OCR could not populate `institutionCode` at all, because the guard skipped
  `type="hidden"` and the form's only such input is hidden.
- Real DWC values were being written into `institutionCode` — `county: Norfolk`
  became `institutionCode "Norfolk"`.
