"""抓取地球联合百科主命名空间正文，保留来源与同人标记；不下载图片。"""
import argparse
import json
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote, urljoin
from urllib.request import Request, urlopen

from bs4 import BeautifulSoup

BASE = 'https://unitedearth.wiki/'
HEADERS = {'User-Agent': 'Mozilla/5.0 (compatible; MOSS-WorldbuildingResearch/1.0)'}


def fetch(url):
    with urlopen(Request(url, headers=HEADERS), timeout=25) as response:
        return response.read().decode('utf-8'), response.url


def crawl(output, delay):
    output.mkdir(parents=True, exist_ok=True)
    pages = output / 'pages'
    pages.mkdir(exist_ok=True)
    directory_url = BASE + quote('特殊:所有页面', safe=':')
    pending = [directory_url]
    visited = set()
    entries = {}
    while pending:
        url = pending.pop(0)
        if url in visited:
            continue
        visited.add(url)
        html, _ = fetch(url)
        (output / f'directory-{len(visited)}.html').write_text(html, encoding='utf-8')
        soup = BeautifulSoup(html, 'html.parser')
        for link in soup.select('.mw-allpages-body a'):
            title = link.get_text(strip=True)
            entries[title] = {'title': title, 'url': urljoin(BASE, link['href']),
                              'redirect': 'mw-redirect' in link.get('class', [])}
        for link in soup.select('.mw-allpages-nav a'):
            candidate = urljoin(BASE, link['href'])
            if candidate.startswith(BASE) and candidate not in visited:
                pending.append(candidate)
        time.sleep(delay)
    (output / 'directory.json').write_text(json.dumps(list(entries.values()), ensure_ascii=False, indent=2), encoding='utf-8')
    targets = [row for row in entries.values() if not row['redirect']]
    keywords = ('危机', '发动机', '550', 'MOSS', '计划', '编年史', '电梯', '机器人', '互联网', '火石', '运载', '地下城', '空间站')
    targets.sort(key=lambda row: (not any(word in row['title'] for word in keywords), row['title']))
    manifest = {'fetched_at': datetime.now(timezone.utc).isoformat(), 'directory_urls': sorted(visited),
                'listed_count': len(entries), 'article_count': len(targets),
                'redirect_count': len(entries) - len(targets), 'pages': []}
    print(f"目录 {len(entries)}，正文 {len(targets)}，别名 {manifest['redirect_count']}", flush=True)
    for number, entry in enumerate(targets, 1):
        row = dict(entry)
        try:
            html, final_url = fetch(entry['url'])
            soup = BeautifulSoup(html, 'html.parser')
            body = soup.select_one('.mw-parser-output')
            if body is None:
                raise ValueError('未找到条目正文')
            references = [el.get_text(' ', strip=True) for el in body.select('ol.references li')]
            links = [{'text': a.get_text(' ', strip=True), 'url': urljoin(final_url, a['href'])}
                     for a in body.select('a[href]')]
            for el in body.select('script,style,.navbox,.toc,.mw-editsection'):
                el.decompose()
            text = body.get_text('\n', strip=True)
            revision = re.search(r'"wgRevisionId":(\d+)', html)
            categories = [a.get_text(strip=True) for a in soup.select('#mw-normal-catlinks li a')]
            stem = re.sub(r'[<>:"/\\|?*]', '_', entry['title']).rstrip('. ')
            (pages / (stem + '.html')).write_text(html, encoding='utf-8')
            (pages / (stem + '.txt')).write_text(text, encoding='utf-8')
            row.update(status='ok', final_url=final_url, revision=revision.group(1) if revision else None,
                       fetched_at=datetime.now(timezone.utc).isoformat(), file=stem,
                       categories=categories, fan_content='同人创作' in categories or '本条目存在虚构信息' in text,
                       speculative_content='本条目存在推测内容' in text,
                       references=references, links=links, text_length=len(text))
            print(f"{number}/{len(targets)} {entry['title']} {len(text)} 字符 {'同人' if row['fan_content'] else ''}", flush=True)
        except Exception as error:
            row.update(status='error', error=str(error))
            print(f"{number}/{len(targets)} 失败 {entry['title']}: {error}", flush=True)
        manifest['pages'].append(row)
        (output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
        time.sleep(delay)
    failures = sum(row['status'] != 'ok' for row in manifest['pages'])
    print(f'完成：{len(targets)-failures} 成功，{failures} 失败', flush=True)
    return bool(failures)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('docs/worldbuilding/sources/unitedearth-cache'))
    parser.add_argument('--delay', type=float, default=1.0)
    args = parser.parse_args()
    if args.delay < 0:
        parser.error('--delay 不能为负数')
    raise SystemExit(crawl(args.output, args.delay))
