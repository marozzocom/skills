---
name: prose
description: Write or edit prose people will read, in English or Finnish, at a plain and essential level: website copy, posts, emails, READMEs, docs, PR descriptions, commit messages, release notes, error messages, Slack updates. Also decides who should hold the pen (AI writes, AI drafts, the owner writes, or the owner dictates and AI shapes). Use whenever you produce text for a human reader beyond a chat reply. Not for code comments, chat answers to the user, or prompts, briefs and instructions for other models.
---

# Prose

These are guidelines, and they bend. Every text has an audience and an occasion, and the job is to land something that works for both. When a guideline and the occasion disagree, the occasion wins, and you say which guideline you bent.

The models are Hemingway for sentences and Orwell's "Politics and the English Language" for words. Technical text leans toward controlled language (think ASD-STE100) without going all the way. Essential first. A little flourish is allowed when it earns its place. Mannerism never is.

Owner-specific facts (which sites are whose, which projects the owner writes by hand) live in `references/authorship.md`. Read it first if it exists. Picked and rejected examples behind these guidelines are in `references/examples.md`. Read them when a call is close.

## 1. Who holds the pen

Decide this before writing a word.

- **Write it yourself (AI)** when the reader is there for the information and every claim can be checked: PR descriptions, commit messages, docs, release notes, a style guide's rules.
- **Draft for the owner to edit** when the text carries the company's voice but not the owner's personal judgment, such as a company website.
- **Check only** when the owner writes: personal site, personal Slack messages, proposals. Routine status updates (a deploy, a test run) are the AI's to write. Point out problems. Do not rewrite the voice.
- **Hand the pen back** when the reader is there for the owner: essays, client email, projects the owner writes by hand. If asked to write one of these, say so in one line and offer to check, outline, or shape dictation instead.
- **Dictation.** When the owner dictates and keeps steering until it feels right, the owner is the author. Keep their words and their order. Fix grammar, rhythm and punctuation, and cut repetition. Do not add claims, images or structure they did not say.

Two tests decide the unclear cases. Is the reader there for the owner or for the information? Would a reader feel misled on learning AI wrote it? If the answer is "the owner" or "yes", hand the pen back.

Rules for others (a style guide, a spec) should come from verifiable truths where they can, with the owner setting the overall tone and direction.

Writing with the owner is teamwork aimed at landing. Give honest feedback and aim for a text that works for its audience.

## 2. Sentences

- Default to short sentences. Vary the length so the text does not stutter. A long sentence is fine when it carries one connected chain of facts.
- One idea per sentence. Join two clauses with "and", "so" or "because", or make two sentences.
- Concrete beats abstract. Name the thing, the number, the behaviour. "Backups that hit a network error now retry" beats "Improved reliability".
- Scope a claim to its evidence and name the gap: "40% faster on my machine (210 GB). Not yet measured on the NAS." No stacked hedges ("may potentially").
- Short, plain words. Keep a precise term of art ("on-call", "staged rollout", "päivystäjä") and drop the padding around it ("utilize", "in order to facilitate", "methodology").
- Active voice, and in English "we" for a company and "you" for the reader.
- One small image is allowed in prose, a verb or a picture that makes the fact easier to see ("the whole lake opens below you"). Ornate writing is not: personification, "like hammered silver", "a quiet journey", a dialogue between steel and stone.
- Headlines and hero lines may be short fragments ("Houses for long winters. Drawn slowly, built once."). That is the one place for slogan rhythm.

## 3. Punctuation and devices to avoid

These are the habits that make text read as generated. Avoid them in both languages.

- **Dashes.** No em dashes. An en dash is rare and needs a reason. Use a full stop or a comma. Number ranges (14:02–14:25, pages 12–18) are fine.
- **Semicolons.** None. Two sentences, or one joined with a conjunction.
- **"Not X, but Y"** and "This isn't just X. It's Y." as a rhetorical reveal. A plain correction ("use a full stop, not a dash") is fine.
- **Colon reveals** ("The result: faster builds.") and "Bad news first:" framing.
- **Abstract groups of three** ("clarity, craft, and care"). A list of three concrete habits is fine when there really are three.
- **Throat-clearing openers** ("In today's digital world") and **summary closers** ("In conclusion", "By following these steps you can ensure"). Open with the story or the point. Stop on the last useful fact.
- **Hype and filler:** passionate, dynamic, robust, seamless, blazing-fast, "I hope this finds you well", "don't hesitate to reach out", emoji as decoration, apology without content.
- **Scare quotes** around invented labels, and stock phrases like "worth noting" or "it's important to".

## 4. Technical forms

- **Commit subject:** conventional-commit prefix, then a concrete change. `feat(db): add index on orders.created_at`. The body, if any, says why.
- **PR description:** short and quick to scan. Use small headings (Summary, Changes, Testing) with a line or two each. Bullets with bold labels are fine for the changes. Keep the reader's time short, and let the diff and commits carry the detail. Every line still names something real.
- **Release notes:** a plain bulleted list, one behaviour per bullet, no bold labels.
- **Docs step:** the instruction, then the one fact the reader needs. "In Settings > Backup, set the schedule to 02:00 and select Save. The backup then runs every night while the laptop is on power."
- **Comparisons and definitions:** bullets with a bold term are fine when the bold is the term being defined.
- **README top:** one or two plain sentences saying what the tool does and what running it gives you.
- **Error message:** what happened, then what to do. No apology, no "Oops", no raw error code as the only text.
- **Postmortem summary:** prose with times and numbers. What changed, what broke, for how long, why review missed it, what now prevents it.
- **Slack update:** a short prose message in the team's working register. State the fact, the number, and what you are doing next. Chat may run clauses together the way people talk.
- **Client email:** the change, the reason, what is ready, when you write next. No corporate padding. (Usually the owner's to write. See section 1.)

## 5. Finnish

Write Finnish as Finnish. The same guidelines apply, with these additions:

- **Write from the meaning.** When both languages are needed, write the Finnish fresh from what the text must say, never by translating the English sentence by sentence. Translated Finnish was the main failure in calibration.
- **Do not personify abstractions or carry over English idioms.** English tolerates "a sentence that wants to be two sentences" or "the job failed silently". Finnish does not ("virke haluaa olla", "epäonnistui äänettömästi"). Say what happens: "Jaa virke kahdeksi", "epäonnistui kenenkään huomaamatta".
- **Do not coin technical compounds.** Use the established Finnish term, or the English term the team already uses. "Uusintatyö" for a certificate renewal job reads as invented. Prefer "varmenteen automaattinen uusinta" or a plain verb: "siirtoa yritetään uudelleen".
- **Technical text the owner reads in English stays English.** PR descriptions and commit messages are English unless asked otherwise.
- **No comma before "ja" or "tai" between two main clauses.** "Uusi versio julkaistaan maanantaina ja ylläpito päivittää koneet." The English comma habit is a translation tell.
- **Finnish is the weaker half of this skill so far.** For public Finnish text, offer the owner a check before it ships.
- **Verbs over nouns.** Avoid substantiivitauti: "Otamme muutokset käyttöön vaiheittain" and not "vaiheittaisen käyttöönottomenetelmän hyödyntäminen".
- **No translation calques:** "tulee olemaan", "toimesta", "suorittaa" for a plain verb, "omata", "-n osalta" as filler. "Ylläpito päivittää koneet", not "päivitys suoritetaan ylläpidon toimesta".
- **Instructions use the imperative:** "Avaa Asetukset ja valitse Varmuuskopio." Not "Voit avata" and not the manual passive.
- **Company sites use written Finnish (kirjakieli),** in the first person plural: "Olemme pieni ohjelmistotalo."
- **Tech register depends on the room.** In a team chat, established developer words (PR, diff, deploy, migraatio, dashboard) are fine. In text for customers, use Finnish words. If unsure in team chat, write plain standard Finnish and keep the established terms.
- **Punctuation:** the Finnish ajatusviiva is a spaced en dash, but the no-dash default still applies. Times are 14.02, decimals 1,2, percentages "40 %", dates "17. maaliskuuta" or 17.3.
- One small image is as welcome in Finnish as in English. Avoid ornate imagery here too.

## 6. Before handing over

Read the text once as the reader. Then check:

1. Count dashes and semicolons. Remove them unless one has a stated reason.
2. Look for each device in section 3.
3. Every claim is concrete or scoped to its evidence.
4. The first sentence does work and the last sentence is useful.
5. Finnish: read it aloud in your head. If it sounds translated, rewrite it from the meaning.

If you bent a guideline for the occasion, say which one in one line when you hand the text over.
