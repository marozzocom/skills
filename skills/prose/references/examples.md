# Examples

Picked and rejected versions from the owner's calibration rounds. "Picked" is what the owner chose. "Rejected" shows the habit to avoid. They show the direction. Do not copy them as templates.

## Sentences

**Rhythm.** Picked: "We build software for people who work with their hands and their heads. We keep the team small. We ship often. When something breaks, the person who wrote it fixes it."

A long sentence was picked once, for a museum label where one chain of facts ran through it: "Printed in 1536 and written in Italian rather than scholarly Latin, this manual was meant for the people who actually held swords, and its woodcuts, one guard to a page, still work as a training plan for fencers almost five centuries later."

**One small image.** Picked: "The trail climbs 200 m in 6 km, about two hours, to a lookout where the whole lake opens below you. In spring the lower part turns to mud, so wear boots."
Rejected: "Winding six kilometres through ancient spruce, the trail rises gently toward a lookout where the lake lies spread like hammered silver."

**Scoped claim.** Picked: "This change made nightly backups about 40% faster on my machine (210 GB). I haven't measured it on the server yet."
Rejected: "This change may potentially help improve backup performance in some cases."

**Term of art, plain verbs.** Picked: "When an alert fires, the on-call engineer acknowledges it within 15 minutes and opens an incident channel."
Rejected (padding): "Upon alert activation, the on-call engineer is responsible for the acknowledgement of the alert within a 15-minute timeframe..."
Rejected (too vague): "If something breaks, whoever is on duty should answer quickly and get people talking."

**Plain result, no colon reveal.** Picked: "We moved the build to our own runner, and it now takes four minutes instead of nineteen."
Rejected: "We moved the build to our own runner. The result: builds that take four minutes instead of nineteen."

**Hero line.** Picked: "Houses for long winters. Drawn slowly, built once."
Rejected: "We don't design houses. We design the winters you'll spend in them."

**Values.** Picked: "We would rather ship one thing that works than three that almost do."
Rejected: "We value clarity, craft, and care."

**Opening.** Picked: "Last March my laptop died on a train, and I lost two days of work."
Rejected: "In today's digital world, data is more valuable than ever."

**Ending.** Picked: "If the morning report shows a failed run two nights in a row, the backup disk is probably full. Delete old snapshots."
Rejected: "In conclusion, backups are an essential part of any workflow..."

**Essay.** Picked: "I learned to sharpen a knife from my grandfather. He did not explain much. He pushed the blade across the stone, ten times on each side, and then he shaved a little hair off his arm. That was the test. It took me a year to pass it."

## Technical

**Commit.** Picked: `feat(db): add index on orders.created_at`

**PR description.** The owner picked this shape twice over longer prose: short headings and bold change labels. The picked versions had generic lines. This one keeps the shape with concrete lines, and was shipped in validation.

```
## Summary
Nightly backups now survive a dropped connection to the backup server.
## Changes
- **Retry:** a failed upload is retried three times, after 10 s, 30 s and 90 s.
- **Report:** each retry is listed in the morning report.
## Testing
- Cut the network for 20 s during a run. The backup finished.
```

**Release notes.** Picked: plain bullets, no bold labels.
"- Search results now appear as you type, even in folders with 50,000 files."

**Error.** Picked: "Backup drive not found. Connect the drive or check that the network share is mounted, then run the backup again."

**Postmortem.** Picked prose over headings: "At 14:02 a config change set the database pool to 5 connections instead of 50. Requests queued, and the API returned timeouts for 23 minutes. The change passed review because the diff showed only a file rename. We now validate pool size in CI."

**Slack.** Picked: "Deployed 2.4 to prod. Migration took 40 s, no errors. Watching the dashboards for an hour, ping me if anything looks off."

**Client email.** Picked: "The launch moves from 3 March to 17 March. The payment provider has not approved our account yet, and we can't go live without it. Everything else is ready. I'll write again on Friday with their answer."

## Finnish

**Verbs, not nouns.** Picked: "Kun hälytys laukeaa, päivystäjä kuittaa sen 15 minuutin kuluessa ja avaa häiriökanavan."
Rejected: "Hälytyksen aktivoituessa päivystäjän vastuulla on hälytyksen kuittaaminen 15 minuutin aikaikkunan puitteissa..."

**No calques.** Picked: "Uusi versio julkaistaan maanantaina, ja ylläpito päivittää koneet." Standard Finnish drops that comma before "ja".
Rejected: "Uusi versio tulee olemaan saatavilla maanantaina, ja päivitys suoritetaan ylläpidon toimesta."

**Short sentences work in Finnish too.** Picked: "Paahdamme kahvin pienessä huoneessa myymälän takana. Yksi erä on kaksitoista kiloa. Paahdamme tiistaisin ja perjantaisin. Perjantaina paahdettu kahvi on kupissasi maanantaina."

**Small image.** Picked: "Joka yö tiedostosi siirtyvät palvelimelle Suomeen. Jos läppäri hajoaa, työsi odottaa siellä aamulla."

**Company site.** Picked: "Olemme pieni ohjelmistoyritys. Teemme verkkosovelluksia yrityksille, jotka haluavat ne kerralla kuntoon."

**Translated Finnish fails.** These were written by translating the English, and were rejected or marked "almost":
- "Käytä pistettä, älä ajatusviivaa. Virke, joka kaipaa viivaa, haluaa yleensä olla kaksi virkettä." (rejected: a personified abstraction, copied from English)
- A Finnish PR description (rejected: PRs are English, and the Finnish was translated line by line)
- "Uusintatyö oli epäonnistunut äänettömästi kaksi viikkoa..." (almost: an invented compound and a carried-over English idiom)

**Team chat register.** The owner picked both slang ("Mergesin PR:n, joka fiksaa backupin retry-bugin.") and formal standard Finnish ("Versio 2.4 on otettu tuotantokäyttöön.") in different rounds. Match the room. When unsure, use standard Finnish and keep the established terms.
