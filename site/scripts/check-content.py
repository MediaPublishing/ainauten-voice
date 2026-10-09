#!/usr/bin/env python3
"""Check bilingual content count, language pairing, local links and disclosures."""
import argparse,json,re
from pathlib import Path
from html.parser import HTMLParser
import xml.etree.ElementTree as ET
class Parse(HTMLParser):
    def __init__(self):super().__init__();self.tags=[];self.ids=set();self.links=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs);self.tags.append((tag,a))
        if a.get('id'):self.ids.add(a['id'])
        if tag=='a' and a.get('href'):self.links.append(a['href'])
def check(root):
    manifest=json.loads((root/'content-manifest.json').read_text());routes=manifest['routes'];assert len(routes)==42 and len(set(routes))==42
    sitemap=ET.parse(root/'sitemap.xml');urls=[x.text for x in sitemap.findall('.//{*}loc')];assert len(urls)==len(set(urls))
    headings=set();local=0
    for route in routes:
        doc=(root/route.strip('/')/'index.html').read_text();p=Parse();p.feed(doc)
        lang=route.split('/')[1];assert ('html',{'lang':lang}) in p.tags
        assert len([t for t,a in p.tags if t=='h1'])==1
        title=re.search(r'<h1>(.*?)</h1>',doc).group(1);assert (lang,title) not in headings;headings.add((lang,title))
        assert [a['href'] for t,a in p.tags if t=='link' and a.get('rel')=='canonical']==['https://voice.ainauten.com'+route]
        for other in ['de','en']:
            assert [a['href'] for t,a in p.tags if t=='link' and a.get('hreflang')==other]==['https://voice.ainauten.com/'+other+route[3:]]
        descriptions=[a['content'] for t,a in p.tags if t=='meta' and a.get('name')=='description'];assert len(descriptions)==1 and 60<=len(descriptions[0])<=165
        schemas=re.findall(r'<script type="application/ld\+json">(.*?)</script>',doc);assert len(schemas)==1 and json.loads(schemas[0])['inLanguage']==lang
        assert '2026-10-09' in doc and 'id="method"' in doc and 'https://voice.ainauten.com'+route in urls
        assert not any(s in doc for s in ['/Users/','[TODO]','Lorem ipsum','—'])
        if '/vs/' in route or '/alternatives/' in route:
            assert ('id="competitor"' in doc and 'id="migration"' in doc) if '/vs/' in route else ('id="transfer"' in doc and 'id="stay"' in doc)
            assert ('Bibliotheksvalidierung' if lang=='de' else 'library-validation') in doc
        if '/best/' in route:assert all('id="'+id+'"' in doc for id in ['test','avoid','workflow','criteria','shortlist'])
        for href in p.links:
            if href.startswith('#'):assert href[1:] in p.ids,(route,href)
            elif href.startswith('/'):
                url=href.split('?')[0].split('#')[0];target=root/url.strip('/')
                if url=='/installation.html' and root.name=='site':
                    target=root.parent/'native/Resources/InstallerGuide/installation.html'
                assert target.is_file() or (target/'index.html').is_file(),(route,href)
                local+=1
    assert '/de/compare/' in (root/'index.html').read_text()
    print(json.dumps({'status':'pass','articles':40,'hubs':2,'localLinksChecked':local,'languagePairs':21,'uniqueH1':len(headings)}))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);check(p.parse_args().root.resolve())
