# Writing an ad

Every app on the shelf gets a page in `ads.json` written as a **1990s magazine ad**: the full-page spreads at the
back of Macworld, sold by a small, confident software house that likes its customers. Read two or three of the ads
already there before writing; they are the voice, and this file names what they share.

## The voice

- **Dry.** The joke is in the understatement. "Same diagram. Better posture." The copy never winks, never uses an
  exclamation mark, and never calls anything powerful, seamless, revolutionary or next-generation.
- **Concrete.** Name the real thing: the keystroke (`Press m to pick up an item`), the file format (`.fiche`), the
  appearances by name (Platinum, Copland's Hi-Tech, OPEN LOOK), the protocol (MCP). A list of real nouns sells
  better than an adjective.
- **Plain words, short sentences.** A fragment is fine when it lands a beat ("No back door. No special treatment.").
- **One feature per section.** Each section sells one thing the app does, in two to four sentences. Pick the two to
  four features a newcomer would care about most; the docs carry the rest.
- **People, then the product.** Open on the reader's situation (a meeting you're late for, a review someone is
  waiting on, a dog with a lot going on), then bring the app in as the answer.

## The fields

| Field | What goes in it |
| --- | --- |
| `headline` | The reader's situation or the app's promise, in one line: a statement, not a feature list. 4–12 words. |
| `kicker` | Only `photo` shows it, over the picture: `Introducing <Name>.` or empty. |
| `sections` | `{ "body": … }`, with a `"heading"` only where a run-in head helps (`columns` reads best with them). Open with a scene-setting section; end with the call to action: `Visit the Phin Tech Store and …` or a line that closes the story. 3–7 sections. |
| `tagline` | The sign-off under the ad, 2–6 words: what the app is, said like a slogan ("The personal outliner.", "Code review, without the guilt."). A pun on the name is welcome when it is a good one. |
| `finePrint` | The honest requirements (macOS version, what it needs installed or signed in, what is sold separately), then **one** joke in the same shape as the rest: `<Prop> not included.`, `<Prop> sold separately.`, `No <subjects> were <verbed> against their will.` |
| `layout` | See below. Pick one its neighbours on the shelf don't use. |
| `boxColor` | A deep, slightly dusty colour (`#1F6F78`, `#8C4A1F`, `#5B3F8C`) unlike the boxes beside it. |
| `title` | Only when the name to show isn't the catalog's (`PhinTechStore` is shown as "The Phin Tech Store"). |

Pepper, the Phin Tech dog, can be the star of an ad (Microfiche, the store). Keep him a dog: he naps, walks and
has designs on the sausage, and never speaks.

## Layouts and their pictures

The hero picture (`<slug>-hero` in `art/prompts.json`) is cropped to the layout's shape, so draw it at that aspect.

| Layout | Shape of the page | Hero aspect | Suits |
| --- | --- | --- | --- |
| `classic` | Big centred headline, picture left, one column of copy right | 4:3 | a story with one character |
| `photo` | Full-bleed photograph with the kicker over it, two columns below | 4:3 | a scene that sells the app on its own |
| `columns` | Huge headline, two columns with run-in heads, picture along the foot | 16:10 (draw 16:9) | an app with several distinct features |
| `product` | The product big on the left, a narrow column beside it, tagline across the foot | 3:4 | an object you can hold, or a short punchy pitch |

## Done

The ad is done when every claim in it is true of the current release (checked against the README or the docs), each
section sells one feature, the fine print states what the app needs, and read aloud beside two of the existing ads
it sounds like the same shop.
