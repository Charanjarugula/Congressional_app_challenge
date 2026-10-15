# Courtly website

Static pages, no build step: `index.html` (landing page), `privacy.html`, `terms.html`, `support.html`, with `styles.css`, `site.js`, the Nunito font (`fonts/`, SIL Open Font License) and `vercel.json` (clean URLs and security headers; the Content-Security-Policy hash must match the one inline script shared by every page).

Hosted on Vercel at https://courtly-sage.vercel.app with the project's root directory set to `site`. To preview locally, serve the folder with any static server, for example `python3 -m http.server --directory site 8000`, and open `http://localhost:8000/` (clean URLs such as `/privacy` work only on Vercel; locally use `/privacy.html`).

What the pages say must match what the backend does; the app links to `/privacy` and `/terms` from `AppConfig.siteURL`.
