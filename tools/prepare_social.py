#!/usr/bin/env python3
"""Add crawler-readable link cards to an exported site, without running the game."""
import argparse
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
import struct

ROOT = Path(__file__).resolve().parents[1]
START = '<!-- social-preview:start -->'
END = '<!-- social-preview:end -->'


class Head(HTMLParser):
    def __init__(self):
        super().__init__()
        self.tags = {}

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'meta':
            key = attrs.get('property', attrs.get('name', ''))
            self.tags.setdefault(key, []).append(attrs.get('content', ''))


def prepare(output):
    data = json.loads((ROOT / 'social/metadata.json').read_text())
    source_image = ROOT / 'social/preview.png'
    image_bytes = source_image.read_bytes()
    if image_bytes[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II', image_bytes[16:24]) != (1200, 630):
        raise ValueError('social/preview.png must be a 1200 x 630 PNG')
    url = data['url']
    if not url.startswith('https://') or not url.endswith('/'):
        raise ValueError('The canonical URL must be an absolute HTTPS URL ending in /')
    image_url = url + 'preview.png'
    tags = {
        'description': data['description'],
        'theme-color': data['color'],
        'og:type': 'website', 'og:site_name': data['title'],
        'og:title': data['title'], 'og:description': data['description'],
        'og:url': url, 'og:image': image_url,
        'og:image:secure_url': image_url, 'og:image:type': 'image/png',
        'og:image:width': '1200', 'og:image:height': '630',
        'og:image:alt': data['alt'], 'og:locale': 'en_US',
        'twitter:card': 'summary_large_image', 'twitter:title': data['title'],
        'twitter:description': data['description'], 'twitter:image': image_url,
        'twitter:image:alt': data['alt'],
    }
    lines = [START, '<link rel="canonical" href="' + html.escape(url, quote=True) + '" />']
    for key, value in tags.items():
        attr = 'property' if key.startswith('og:') else 'name'
        lines.append(f'<meta {attr}="{key}" content="{html.escape(value, quote=True)}" />')
    lines.append(END)
    page = output / 'index.html'
    document = page.read_text()
    if '</head>' not in document:
        raise ValueError(f'{page} has no closing head tag')
    document = re.sub(re.escape(START) + r'.*?' + re.escape(END) + r'\s*', '', document, flags=re.S)
    # Replace old metadata (including stale image URLs) instead of creating duplicates.
    def keep_meta(match):
        parser = Head()
        parser.feed(match.group())
        return '' if tags.keys() & parser.tags.keys() else match.group()
    document = re.sub(r'<meta\b[^>]*>', keep_meta, document, flags=re.I)
    document = re.sub(r'<link\b[^>]*\brel=[\"\x27]canonical[\"\x27][^>]*>', '', document, flags=re.I)
    document = document.replace('</head>', '\n'.join(lines) + '\n</head>', 1)
    check = Head()
    check.feed(document.split('</head>', 1)[0])
    for key, value in tags.items():
        if check.tags.get(key) != [value]:
            raise ValueError(f'Missing or duplicate preview metadata: {key}')
    shutil.copyfile(source_image, output / 'preview.png')
    page.write_text(document)
    print(f'Prepared and verified {data["title"]}: {image_url}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path, help='Exported directory containing index.html')
    prepare(parser.parse_args().output)
