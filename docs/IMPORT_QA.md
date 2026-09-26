# Schedule image import QA — 2026-09-26

This checkpoint covers the local schedule-photo flow only. The five PNGs in
`MaroonCompassTests/Fixtures` were generated with `generate.py`; they contain
invented course layouts and **no student screenshot or account data**. Their
expected text is printed in the generator. They are evaluation inputs, not
evidence that Vision or Apple Intelligence extracts a real Howdy screen.

## Prioritized flow matrix

| Priority | Scenario | Expected behavior | Branch change / remaining check |
| --- | --- | --- | --- |
| P0 | Manual edit, then choose another photo | Keep the edited draft until the student explicitly replaces it | Added a separate draft-replacement confirmation; simulator interaction still needs visual QA |
| P0 | Invalid dates, missing course fields | Show all relevant errors beside the fields; disable save | Validator now continues after a date error; unit regression added |
| P0 | Room without building | Do not silently discard the room | Blocks save until building is entered or room cleared; unit regression added |
| P0 | Duplicate courses, duplicate meetings, overlapping times | Identify conflicts before replacement | Normalized course/time keys and overlapping-day checks added; adjacent one-minute ENGR records remain valid |
| P0 | Ambiguous time such as `9:35` | Do not infer AM/PM | Existing strict clock parser retained; regression test remains |
| P1 | Repeated course header after another course | Attach later meetings to the right course | OCR parser tracks the current course; transcript regression added |
| P1 | Course title containing a number, multiple meetings, lab/recitation | Preserve visible text and separate meetings | Synthetic OCR transcript regression added; images generated for Vision evaluation |
| P1 | Missing weekday column or unrelated page time | Leave a correctable blank meeting; avoid attaching unrelated times | OCR parser requires visible weekdays for an extracted meeting; transcript regression added |
| P1 | Building/room with similar-looking `1`, `I`, `O`, `0` | Transcribe visible characters without automatic correction | Synthetic `BLOC 1O9` fixture; review note tells student to compare the image |
| P1 | Small iPhone, Dynamic Type, VoiceOver, dark mode | Keep every field and error readable and operable | Weekday controls now use 44-point targets in a four-column grid; field errors are inline; simulator screenshots and accessibility review pending |
| P2 | Analysis failure, cancellation, model unavailable | Preserve the existing draft and allow manual entry | Existing manual/OCR fallback retained; analysis task cancellation added; runtime test pending |
| P2 | iPad keyboard and reduced motion | Usable native form with clear focus and no decorative animation | No custom motion; direct iPad and keyboard review pending |
| P2 | Physical Apple Intelligence, photo permission, cloud absence | Check actual device availability; selected image remains local | Physical device and Auth state unavailable in this checkout; no external image/OCR transmission added |

## Synthetic fixture inventory

| Image | Layout condition | Specific extraction risk |
| --- | --- | --- |
| `clean-light.png` | 1200 px, light, five rows | Numbers in title, multiple meetings, lab/recitation, `1O9` versus `109` |
| `dark-compact.png` | 900 px, dark | Adjacent lab components, abbreviated weekdays, high contrast |
| `cropped-missing-column.png` | 770 px crop | POLS time lacks weekdays; parser must leave it for review |
| `blurry-low-resolution.png` | Downsampled and blurred | OCR omissions and substitutions; no inferred repair |
| `unrelated-text.png` | Light layout with dining hours | Avoid a false schedule meeting from unrelated time text |

`ScheduleImageEvaluationTests` runs Vision plus the deterministic OCR fallback
with Apple Intelligence explicitly disabled. It prints `OCR_EVAL` rows with
correct/expected counts for course code, title, section, weekdays, start/end
time, building, and room, plus omitted fields and false additions. A field
counts as correct only when it matches the visible synthetic ground truth;
time strings compare as parsed civil times. The cropped POLS meeting has no
weekday ground truth, so its missing meeting fields are excluded from accuracy
denominators. A blurry-image failure is reported rather than treated as a
successful extraction. These fixture scores must be copied here after the
macOS suite runs; none are claimed from source inspection alone.

## Privacy and save boundary

`PhotosPicker` requests selected-item access. The image, Vision lines, and
Foundation Models prompt stay in memory during the sheet and are not passed
to the cloud repository, analytics, logs, or GitHub. The review button remains
disabled while analysis runs or validation issues remain. A second explicit
dialog precedes replacement of the current local schedule. The cloud adapter
is unchanged and does not run without Auth/configuration.

## Evidence still required

- Full schedule suite and unsigned simulator Release build on Xcode 27.
- Inspect the compiled empty import sheet in light/dark iPhone screenshots;
  then exercise editing, keyboard, VoiceOver, Dynamic Type, and iPad layout.
- On a reachable iPhone, test a redacted real schedule image with Apple
  Intelligence available and unavailable. Record model availability and
  field-level results separately from synthetic Vision/OCR metrics.
