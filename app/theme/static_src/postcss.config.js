// Tailwind v4 runs as a PostCSS plugin. The configuration that used to live in
// tailwind.config.js (which files to scan, which plugins to load) is now in
// src/styles.css itself.
module.exports = {
  plugins: {
    "@tailwindcss/postcss": {},
    "postcss-simple-vars": {},
    "postcss-nested": {},
  },
};
