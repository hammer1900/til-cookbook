# TIL Cookbook

A personal log of small, real problems I've solved with code — mostly things
that came up once, took a while to figure out, and are probably useful to
someone else too.

This is not a blog. There's no comment section, no discussion thread, no
"thoughts?" at the end. It's a dump of working solutions, written so a
stranger (or future me) can land on one entry, copy the code, and move on.

## Format

Every problem gets one file in `entries/`, named `kebab-case-title.md`.
Each entry follows [`TEMPLATE.md`](./TEMPLATE.md):

- **Problem** — one or two sentences, what you were stuck on
- **Solution** — the fix, in plain language
- **Code** — the actual script/snippet, runnable as-is
- **Notes** — gotchas, alternatives you tried, things to watch for

Standalone scripts that are long or have their own dependencies live in
`scripts/<entry-name>/` instead of being pasted inline — the entry file
just links to them.

## Index

| Entry | Problem |
|---|---|
| [yt-dlp-clip-extractor](./entries/yt-dlp-clip-extractor.md) | Pull specific timestamp ranges out of a long YouTube video without downloading the whole thing, via a menu-driven CLI |

## Adding a new entry

1. Copy `TEMPLATE.md` into `entries/your-title.md`
2. Fill it in
3. Add a row to the index above
4. Commit

No PR template, no issue template, no CI. Keep it that way — the whole
point is zero friction between "I solved this" and "it's documented."

## Getting started

```bash
cd til-cookbook
git init
git add .
git commit -m "Initial cookbook scaffold"
git branch -M main
git remote add origin <your-repo-url>
git push -u origin main
```

Then on GitHub: **Settings → General → Features** — turn off Issues and
Discussions if you want zero surface area for unsolicited feedback.

## Why no comments / discussions

This repo is intentionally one-directional: I share what I built, you take
what's useful. If you want to build on it, fork it. Issues and Discussions
are disabled on purpose, not as an oversight.
