# Link preview

The deployed game uses a 1200 × 630 PNG card and static Open Graph / Twitter metadata.
`metadata.json` is the source for the title, description, canonical URL, and image alt text.
`preview.png` is the published card; `card.html` and `gameplay.png` are its editable source.

After exporting the game locally, run:

```sh
python3 tools/prepare_social.py build/web
```

The deployment pipeline runs this automatically before uploading the site. It validates
the image dimensions and tags and copies the image beside `index.html`, where link
crawlers can fetch it without loading JavaScript or the game.

To refresh the artwork, replace `gameplay.png`, edit `card.html`, and capture it at
1200 × 630 in a browser as `preview.png`. Keep text legible at thumbnail size.
Chat apps may cache old cards; sharing the game URL with `?preview=2` can request a fresh URL.
