#!/usr/bin/env python3
"""Render bilingual buying guides from dated, centralized evidence. No dependencies."""
import argparse, hashlib, html, json, re, subprocess
from pathlib import Path
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
BASE='https://voice.ainauten.com'
DATA=json.loads((ROOT/'content/competitors/profiles.yaml').read_text())
GUIDES=json.loads((ROOT/'content/guides.json').read_text())
DATE=DATA['checked']
FOOTERS=json.loads(subprocess.check_output(['node',str(ROOT/'scripts/render-content-shell.mjs')],text=True))
E=lambda s:html.escape(str(s),quote=True)
P=lambda s:'<p>'+E(s)+'</p>'
L=lambda de,en,lang:de if lang=='de' else en
OWN={
'de':{'name':'AInauten Voice','position':'Kostenlose lokale Diktier-Beta für Apple-Silicon-Macs.','price':'Kostenlos, kein Abo. Modell-Download und Gerätespeicher gehören zum Aufwand; freiwillige Spenden sind möglich.','platform':'Apple Silicon, macOS 14 als Build-Ziel; nicht vollständig auf allen Zielsystemen praktisch abgenommen.','processing':'Standardmäßig lokale Erkennung und Textoptimierung. Cloud-Textoptimierung ist optional und aus. Der optionale lokale Verlauf speichert Text.','better':'AInauten Voice passt, wenn du auf einem Apple-Silicon-Mac lokal diktieren möchtest und die Grenzen einer kostenlosen Beta akzeptierst.','tradeoff':'Die Beta ist lokal signiert, noch nicht Apple-notarisiert und verwendet eine Ausnahme für Bibliotheksvalidierung. Das ist keine pauschale Sicherheitsfreigabe. Automatisches Einfügen ohne Zwischenablage funktioniert nicht in jedem Feld.','workflow':'Lokale Textmodi, Wörterbuch, optionaler Verlauf und Statistik unterstützen den Entwurfsablauf. Die allgemeine Zwischenablage wird für automatisches Einfügen standardmäßig nicht genutzt; kompatibles Einfügen lässt sich bewusst aktivieren. Ein kostenloser Download ersetzt keinen Kompatibilitätstest.','cost':'Der App-Preis bleibt auch bei zehn Downloads null. IT-Aufwand, Geräte, Speicher und Betreuung sind darin nicht enthalten; ein Enterprise-Serviceversprechen ist damit nicht verbunden.'},
'en':{'name':'AInauten Voice','position':'Free local dictation beta for Apple Silicon Macs.','price':'Free, no subscription. Model downloads and device storage are part of setup; donations are optional.','platform':'Apple Silicon, macOS 14 as build target; not fully validated hands-on on every target system.','processing':'Local recognition and text optimization by default. Optional cloud text optimization is off. Optional local history stores text.','better':'AInauten Voice fits local dictation on an Apple Silicon Mac if you accept the limits of a free beta.','tradeoff':'The beta is locally signed, not Apple-notarized, and uses a library-validation exception. This is not a blanket security approval. Automatic insertion without the clipboard does not work in every field.','workflow':'Local text modes, vocabulary, optional history and statistics support drafting. Automatic insertion does not use the general clipboard by default; compatible insertion is an explicit option. A free download does not replace a compatibility test.','cost':'The app price remains zero for ten downloads. IT effort, devices, storage and support are not included; this implies no enterprise service commitment.'}}

def path(lang,kind,slug=''):
    return f'/{lang}/'+({'hub':'compare','vs':'vs','alt':'alternatives','guide':'best'}[kind])+('/'+slug if slug else '')+'/'

def links(items):
    return '<ul class="link-list">'+''.join(f'<li><a href="{E(url)}">{E(label)} <span aria-hidden="true">↗</span></a></li>' for label,url in items)+'</ul>'

def cite(prod,lang):
    label=L('Herstellerquellen','Vendor sources',lang)
    return '<p class="source-note">'+label+': '+ ' · '.join(f'<a href="{E(url)}">{E(name)}</a>' for name,url in prod['sources'])+f'. {L("Geprüft","Checked",lang)}: {DATE}.</p>'

def owncite(lang):
    return '<p class="source-note">'+L('Eigene Produktbelege','Our product evidence',lang)+': <a href="https://github.com/MediaPublishing/ainauten-voice#readme">README</a> · <a href="https://github.com/MediaPublishing/ainauten-voice/blob/main/native/docs/user-verification-report.md">'+L('Nutzer-Prüfstand','User verification status',lang)+'</a>.</p>'

def section(id,title,body):return f'<section id="{id}"><h2>{E(title)}</h2>{body}</section>'

def table(prod,lang):
    d=prod[lang]; own=OWN[lang]
    labels=[('position','Schwerpunkt','Focus'),('platform','Geräte','Devices'),('processing','Datenweg','Processing'),('price','Kosten','Cost')]
    return '<p class="table-hint">'+L('Auf schmalen Ansichten kannst du die Tabelle seitlich verschieben.','On narrow screens, scroll the table sideways.',lang)+'</p><div class="table-scroll" role="region" tabindex="0" aria-label="'+L('Produktvergleich','Product comparison',lang)+'"><table><caption>'+L('Herstellerangaben und eigener Prüfstand, Stand ','Vendor statements and our own status, as of ',lang)+DATE+'</caption><thead><tr><th scope="col">'+L('Kriterium','Criterion',lang)+'</th><th scope="col">AInauten Voice</th><th scope="col">'+E(prod['name'])+'</th></tr></thead><tbody>'+''.join('<tr><th scope="row">'+L(de,en,lang)+'</th><td>'+E(own[key])+'</td><td>'+E(d[key])+'</td></tr>' for key,de,en in labels)+'</tbody></table></div>'+cite(prod,lang)+owncite(lang)

def methodology(lang):
    return P(L('Diese Seite stammt vom Team hinter AInauten Voice. Herstellerangaben wurden am '+DATE+' geprüft; Empfehlungen sind unsere Einordnung der beschriebenen Aufgaben. Wir haben hier keinen kontrollierten Genauigkeitsvergleich, keine unabhängigen Nutzerinterviews und keine Suchvolumenmessung durchgeführt. Nicht genannte Funktionen gelten nicht automatisch als fehlend. Preise sind Momentaufnahmen in der angegebenen Währung; Checkout und Tarifdetails haben Vorrang.','This page is published by the team behind AInauten Voice. Vendor statements were checked on '+DATE+'; recommendations are our interpretation of the tasks described. We performed no controlled accuracy comparison, independent customer interviews or keyword-volume measurement here. Unlisted features are not automatically absent. Prices are snapshots in the stated currency; checkout and plan details take precedence.',lang))

def page(out,lang,kind,slug,title,summary,sections,related,faq=None):
    route=path(lang,kind,slug); other='en' if lang=='de' else 'de'
    if kind=='vs':
        name=next(p['name'] for p in DATA['products'] if p['id']==slug)
        desc=L(f'AInauten Voice vs. {name}: Preis, Geräte, Datenwege und Grenzen. Wann welches Diktier-Tool besser zu deiner Arbeit passt.',f'AInauten Voice vs {name}: pricing, devices, processing and limits. Find out which dictation workflow fits your work better.',lang)
    elif kind=='alt':
        name=next(p['name'] for p in DATA['products'] if p['id']==slug)
        desc=L(f'Alternative zu {name}: lokal auf dem Mac diktieren. Prüfe Kosten, Wechsel und Beta-Grenzen, bevor du den bisherigen Ablauf ersetzt.',f'{name} alternative for local Mac dictation. Compare costs, migration and beta limits before replacing your existing workflow.',lang)
    elif kind=='guide':
        audience=next(g[lang]['audience'] for g in GUIDES if 'dictation-app-for-'+g['id']==slug)
        desc=L(f'Diktier-Apps für {audience} auf dem Mac: passende Optionen, Auswahlkriterien und ein praktischer Test. Mit Quellen und ehrlichen Grenzen.',f'Dictation apps for {audience} on Mac: suitable options, selection criteria and a practical trial. With sources and honest limitations.',lang)
    else:
        desc=L('Diktier-Apps auf dem Mac vergleichen: fünf Alternativen und zehn Zielgruppen-Ratgeber. Mit Quellen, Kosten und ehrlichen Empfehlungen.','Compare Mac dictation apps: five alternatives and ten audience guides. Sources, pricing and honest recommendations for your work.',lang)
    toc=links([(heading,'#'+id) for id,heading,_ in sections])
    article= ''.join(section(id,h,b) for id,h,b in sections)
    if faq:
        article+=section('faq',L('Eine häufige Frage','A common question',lang),'<details><summary>'+E(faq[0])+'</summary>'+P(faq[1])+'</details>')
    article+=section('method',L('So vergleichen wir','How we compare',lang),methodology(lang))
    article+=section('related',L('Weiter vergleichen','Explore related pages',lang),links(related))
    article+=section('try',L('Den passenden Ablauf testen','Test the right workflow',lang),P(L('Du möchtest unsere lokale Beta ausprobieren? Lies zuerst die Voraussetzungen und Startanleitung. Entscheide danach mit einem nicht vertraulichen Beispielsatz in deiner tatsächlichen Ziel-App.','Want to try our local beta? Read requirements and first-launch instructions first. Then decide using a non-sensitive sample in your actual destination app.',lang))+f'<a class="content-cta" href="/#download">'+L('Zur kostenlosen Beta','See the free beta',lang)+'</a> <a href="/installation.html" target="_blank" rel="noopener">'+L('Installation mit Bildern','Illustrated installation guide',lang)+'</a>')
    schema={'@context':'https://schema.org','@type':'Article','headline':title,'description':desc,'inLanguage':lang,'dateModified':DATE,'datePublished':DATE,'author':{'@type':'Organization','name':'AInauten Voice team','url':BASE},'publisher':{'@type':'Organization','name':'AInauten'},'mainEntityOfPage':BASE+route}
    doc=f'''<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{E(title)} | AInauten Voice</title><meta name="description" content="{E(desc)}"><link rel="canonical" href="{BASE+route}"><link rel="alternate" hreflang="de" href="{BASE+path('de',kind,slug)}"><link rel="alternate" hreflang="en" href="{BASE+path('en',kind,slug)}"><link rel="alternate" hreflang="x-default" href="{BASE+path('de',kind,slug)}"><meta property="og:type" content="article"><meta property="og:title" content="{E(title)}"><meta property="og:description" content="{E(desc)}"><meta property="og:url" content="{BASE+route}"><meta property="og:image" content="{BASE}/assets/video/promo-poster.jpg"><link rel="icon" href="/favicon.ico"><link rel="stylesheet" href="/assets/shell/ainauten-shell.css"><link rel="stylesheet" href="/content.css"><script type="application/ld+json">{json.dumps(schema,ensure_ascii=False).replace('<','\\u003c')}</script></head><body><a class="skip-link" href="#main">{L('Zum Inhalt','Skip to content',lang)}</a><header class="content-header"><a class="brand" href="/"><img src="/assets/nauti-logo.png" width="32" height="32" alt="">AInauten Voice</a><nav aria-label="{L('Navigation','Navigation',lang)}"><a href="{path(lang,'hub')}">{L('Vergleiche & Ratgeber','Comparisons & guides',lang)}</a><a href="{path(other,kind,slug)}" lang="{other}" hreflang="{other}">{'English' if other=='en' else 'Deutsch'}</a></nav></header><main id="main"><div class="article-intro"><p class="eyebrow">{L('Entscheidungshilfe · ','Buying guide · ',lang)}{DATE}</p><h1>{E(title)}</h1><p class="lead">{E(summary)}</p><p class="disclosure">{L('Vom AInauten-Voice-Team. Herstellerangaben und redaktionelle Empfehlungen, kein gemessener Produkttest.','By the AInauten Voice team. Vendor facts and editorial recommendations, not a measured product test.',lang)}</p></div><div class="reading-layout"><aside aria-label="{L('Inhalt','Contents',lang)}"><p>{L('Auf dieser Seite','On this page',lang)}</p>{toc}</aside><article>{article}</article></div></main><footer><a href="{path(lang,'hub')}">{L('Alle Vergleiche und Ratgeber','All comparisons and guides',lang)}</a><a href="https://learn.ainauten.com/impressum/">{L('Impressum','Legal notice',lang)}</a><a href="https://learn.ainauten.com/privacy/">{L('Datenschutz','Privacy',lang)}</a><a href="https://github.com/MediaPublishing/ainauten-voice">GitHub</a></footer><div id="ainauten-footer">{FOOTERS[lang]}</div></body></html>'''
    dest=out/route.strip('/')/'index.html';dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(doc)
    return route

def build(out):
    routes=[]
    for lang in ['de','en']:
        for prod in DATA['products']:
            d=prod[lang]; name=prod['name']; slug=prod['id']
            for kind in ['vs','alt']:
                title='AInauten Voice vs. '+name if kind=='vs' else L('Eine '+name+'-Alternative für lokales Diktieren',name+' alternative for local dictation',lang)
                summary= d['better']+' '+OWN[lang]['better'] if kind=='vs' else d['alternative']
                sections=[]
                if kind=='alt':
                    sections.append(('switch-fit',L('Was einen Wechsel rechtfertigt','What makes switching worthwhile',lang),P(d['alternative'])+P(L('Der relevante Unterschied ist dein Arbeitsablauf. Ein kostenloser Download ist sinnvoll, wenn er deine Aufgabe abdeckt. Fehlende Geräteunterstützung oder benötigte Zusatzfunktionen lassen sich durch den Preis nicht ausgleichen.','Your workflow is the relevant difference. A free download is useful when it covers your task. Price cannot compensate for unsupported devices or missing capabilities you require.',lang))))
                sections.extend([
                    ('comparison',L('Auf einen Blick','At a glance',lang),table(prod,lang)),
                    ('workflow',L('Funktionen im Alltag','Features in your workflow',lang),P(d['workflow'])+cite(prod,lang)+P(OWN[lang]['workflow'])+owncite(lang)),
                    ('cost',L('Kosten richtig vergleichen','Compare costs fairly',lang),P(d['cost'])+cite(prod,lang)+P(OWN[lang]['cost'])),
                    ('competitor',L('Wann '+name+' besser passt','When '+name+' is a better fit',lang),P(d['better'])+P(d['tradeoff'])+cite(prod,lang)),
                    ('own',L('Wann AInauten Voice passt','When AInauten Voice fits',lang),P(OWN[lang]['better'])+P(OWN[lang]['tradeoff'])+owncite(lang)),
                    ('migration',L('Wechsel und Einrichtung','Switching and setup',lang),P(d['switch'])+P(L('Behalte den bisherigen Ablauf während des Tests. Installiere die Beta nach der Anleitung, bestätige Mikrofon und Bedienungshilfen selbst und verwende ein eigenes Kürzel. Prüfe zuerst einen Satz, danach Fachbegriffe und einen längeren Absatz. Verlasse dich erst nach diesem Test auf das Einfügen in deiner Ziel-App.','Keep your existing workflow during the trial. Install the beta using the guide, approve microphone and accessibility permissions yourself and configure a separate shortcut. Test one sentence, specialist vocabulary and then a longer paragraph. Rely on insertion in your destination app only after that check.',lang))),
                    ('support',L('Support und Belege','Support and evidence',lang),P(L('Für unsere Beta gibt es Hilfe und eine Möglichkeit zur Fehlermeldung. Ein garantierter Enterprise-Support oder eine vollständige Abnahme aller Ziel-Apps wird nicht zugesagt. In diesem Vergleich veröffentlichen wir keine erfundenen Wechselberichte und keine zugeschriebenen Kundenzitate. Prüfe die Dokumentation des anderen Anbieters für verbindliche Supportbedingungen.','Our beta has help and a reporting option. It does not promise guaranteed enterprise support or full validation of every destination app. We publish no invented switching stories or attributed customer quotes in this comparison. Check the other vendor documentation for contractual support terms.',lang))+cite(prod,lang))])
                if kind=='alt':
                    alternatives=[p for p in DATA['products'] if p['id']!=slug][:3]
                    alternatives_body=P(L('Wenn unsere Beta die benötigte Aufgabe nicht abdeckt, prüfe diese anderen Wege. Der Wechsel sollte eine konkrete Lücke schließen, statt nur eine weitere App hinzuzufügen.','If our beta does not cover your task, evaluate these other routes. Switching should solve a specific gap rather than merely add another app.',lang))+''.join('<h3>'+p['name']+'</h3>'+P(p[lang]['position'])+links([(L('Vergleich lesen','Read comparison',lang),path(lang,'vs',p['id']))]) for p in alternatives)
                    sections=[sections[0],sections[1],
                        ('transfer',L('Was du übertragen kannst','What you can move',lang),P(d['switch'])+owncite(lang)),
                        ('pilot',L('Erst testen, dann wechseln','Trial first, switch later',lang),P(L('Notiere drei Dinge, die dein bisheriges Tool gut erledigt: ein typisches Textfeld, einen häufigen Fachbegriff und einen längeren Text. Wiederhole genau diese Aufgaben mit der Beta. Kontrolliere Sinn, Absätze und Einfügen. Wenn eine dieser Aufgaben schlechter funktioniert, behalte den bisherigen Ablauf für diese Aufgabe.','Record three things your current tool handles well: a typical text field, a recurring specialist term and a longer text. Repeat exactly those tasks with the beta. Check meaning, paragraphs and insertion. If any task works worse, keep your existing workflow for that task.',lang))+P(OWN[lang]['tradeoff'])+P(L('Kündige ein Abo und entferne die bisherige App erst nach dem Vergleich. Sichere eigene Begriffe und Entwürfe über die vorhandenen Exportmöglichkeiten. Ein Testimport ist kein Beleg, dass jedes Feld und jede Einstellung übertragen wurde.','Cancel a subscription and remove the old app only after comparing. Back up vocabulary and drafts using existing exports. A trial import does not prove that every field or setting transferred.',lang))),
                        ('stay',L('Wann du beim bisherigen Tool bleiben solltest','When to keep your existing tool',lang),P(d['better'])+P(d['workflow'])+cite(prod,lang)),
                        ('cost',L('Was der Wechsel kostet','What switching costs',lang),P(d['cost'])+cite(prod,lang)+P(OWN[lang]['cost'])),
                        ('other-options',L('Weitere Wege statt eines erzwungenen Wechsels','Other routes instead of forcing a switch',lang),alternatives_body)]
                related=[(L('Alle Vergleiche','All comparisons',lang),path(lang,'hub')),(L('Direkter Vergleich','Direct comparison',lang) if kind=='alt' else L('Wechsel als Alternative','Switching alternative',lang),path(lang,'vs' if kind=='alt' else 'alt',slug)),(L('Ratgeber für Freelancer','Guide for freelancers',lang),path(lang,'guide','dictation-app-for-freelancers'))]
                faq=(L('Ist AInauten Voice pauschal besser als '+name+'?','Is AInauten Voice universally better than '+name+'?',lang),L('Nein. Entscheide anhand von Geräten, Datenweg, benötigten Funktionen und Nacharbeit. Wir haben hier keine allgemeine Genauigkeitsüberlegenheit gemessen.','No. Decide by devices, data routes, required features and correction effort. We have measured no general accuracy advantage here.',lang))
                routes.append(page(out,lang,kind,slug,title,summary,sections,related,faq))
        for guide in GUIDES:
            d=guide[lang]; slug='dictation-app-for-'+guide['id']
            pickbody=''
            for pick_index,pick in enumerate(guide['picks']):
                if pick=='ainauten':
                    p=OWN[lang]; name='AInauten Voice'; cites=owncite(lang); link='/#download'
                else:
                    prod=next(p for p in DATA['products'] if p['id']==pick);p=prod[lang];name=prod['name'];cites=cite(prod,lang);link=path(lang,'vs',pick)
                pickbody+='<h3><a href="'+link+'">'+name+'</a></h3>'+P(d['pickReasons'][pick_index])+P(p['position'])+P(p['price'])+cites
            sections=[('task',L('Die eigentliche Aufgabe','The actual job',lang),P(d['scene'])),('criteria',L('Worauf es ankommt','What matters',lang),'<ul>'+''.join('<li>'+E(s)+'</li>' for s in d['criteria'])+'</ul>'),('shortlist',L('Diese Optionen zuerst prüfen','Options to evaluate first',lang),pickbody),('workflow',L('Ein passender Ablauf','A suitable workflow',lang),P(d['workflow'])),('test',L('Dein praktischer Vergleich','Your practical comparison',lang),P(d['test'])),('avoid',L('Wann du anders wählen solltest','When to choose differently',lang),P(d['avoid']))]
            related=[(L('Alle Zielgruppen','All audiences',lang),path(lang,'hub'))]+[(next(p['name'] for p in DATA['products'] if p['id']==pick)+' vs. AInauten Voice',path(lang,'vs',pick)) for pick in guide['picks'] if pick!='ainauten']
            routes.append(page(out,lang,'guide',slug,d['title'],d['summary'],sections,related,(d['faq'],d['answer'])))
        sections=[('selection',L('Fünf relevante Alternativen','Five relevant alternatives',lang),P(L('Diese Auswahl richtet sich nach Diktieren auf dem Mac, lokalen Optionen und angrenzender Datei-Transkription. Apple Dictation ist die integrierte Alternative. Die Reihenfolge ist weder Marktanteils- noch Suchvolumenranking.','This selection reflects Mac dictation, local options and adjacent file transcription. Apple Dictation is the built-in substitute. Order is not a market-share or search-volume ranking.',lang))+''.join('<h3>'+p['name']+'</h3>'+P(p[lang]['position'])+links([(L('AInauten Voice im Vergleich','Compare with AInauten Voice',lang),path(lang,'vs',p['id'])),(L('Als Alternative wechseln','Evaluate switching',lang),path(lang,'alt',p['id']))]) for p in DATA['products'])),('audiences',L('Nach deiner Aufgabe wählen','Choose by your task',lang),links([(g[lang]['title'],path(lang,'guide','dictation-app-for-'+g['id'])) for g in GUIDES])),('limits',L('Unsere Beta hat Grenzen','Our beta has limits',lang),P(OWN[lang]['tradeoff'])+owncite(lang))]
        routes.append(page(out,lang,'hub','',L('Diktier-Apps vergleichen: Was passt zu dir?','Compare dictation apps: what fits your work?',lang),L('Fünf Vergleiche, fünf Wechselhilfen und zehn Ratgeber. Mit konkreten Empfehlungen, Quellen und Situationen, in denen ein anderes Tool besser passt.','Five comparisons, five switching guides and ten audience guides. Practical recommendations, sources and situations where another tool is a better fit.',lang),sections,[]))
    (out/'content.css').write_text((ROOT/'content.css').read_text())
    sitemap=ET.fromstring((ROOT/'sitemap.xml').read_text());ns='{http://www.sitemaps.org/schemas/sitemap/0.9}'
    for node in list(sitemap):
        loc=node.find(ns+'loc')
        if loc is not None and loc.text and any(loc.text.startswith(BASE+'/'+lang+'/') for lang in ['de','en']):
            sitemap.remove(node)
    for route in routes:
        node=ET.SubElement(sitemap,ns+'url');ET.SubElement(node,ns+'loc').text=BASE+route;ET.SubElement(node,ns+'lastmod').text=DATE
    ET.register_namespace('',ns[1:-1]);ET.ElementTree(sitemap).write(out/'sitemap.xml',encoding='utf-8',xml_declaration=True)
    manifest={'checked':DATE,'articleCount':40,'hubCount':2,'routes':routes,'profilesSha256':hashlib.sha256((ROOT/'content/competitors/profiles.yaml').read_bytes()).hexdigest()}
    (out/'content-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'articles':40,'hubs':2,'output':str(out)}))
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=ROOT);args=parser.parse_args();build(args.output.resolve())
